local R = require "rigel"
local RM = require "generators.modules"
local RS = require "rigelSimple"
local G = require "generators.core"
local SOC = require "generators.soc"
local SDF = require "sdf"
local Zynq = require "generators.zynq"
local T = require "types"
local types = T
local C = require "generators.examplescommon"
local J = require "common"
local P = require "params"
local harness = require "generators.harnessSOC"

local SIFT_OLD = require "sift_core_hw"
-- this is just lua code, so just use old code
local calcGaussian = SIFT_OLD.calcGaussian
local tileGaussian = SIFT_OLD.tileGaussian
SIFT_OLD=nil

local siftTerra
if terralib~=nil then siftTerra = require("sift_core_hw_terra") end

R.default_nettype_none = false

local GRAD_INT = true
local GRAD_SCALE = 4 -- <2 is bad
local GRAD_TYPE = types.int(8)

local GAUSS_SIGMA = 5

local W = 256
local H = 256

local cycles = W*H*128
print("CYCLES",cycles)
local regs = SOC.axiRegs({},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

local FILTER_FIFO = 512
local OUTPUT_COUNT = 614
local FILTER_RATE = {OUTPUT_COUNT,W*H}

local TILES_X = 4
local TILES_Y = 4

local GAUSS  = {14 , 62 , 104 , 62 , 14}

local Clamp = G.Function{"Clampint8",types.rv(types.FloatRec32),
function(i)
  local v127 = G.FtoFR(R.c(types.Float32,127))
  local vm128 = G.FtoFR(R.c(types.Float32,-128))
  local tmp = G.Sel(G.GTF(i,v127),v127,i)
  local tmp = G.Sel(G.LTF(i,vm128),vm128,tmp)
  return tmp
end}


local siftlowerPair = J.memoize(function( TO, scale, X )
  assert(types.isType(TO))
  assert( scale==math.floor(scale) )
  assert( X==nil )

  assert( TO:isInt() )
  assert(TO==types.int(8))
  assert( scale==4 )

  return G.Function{"LowerPair",types.rv(types.tuple{T.FloatRec32,T.FloatRec32}),
    function(i)
      local tmp = R.concat{G.MulF{scale}(i[0]), G.MulF{scale}(i[1])}

      tmp = G.TupleToArray(tmp)
      tmp = G.Map{Clamp}(tmp)
      tmp = G.Map{G.FRtoI{8}}(tmp)
      return G.ArrayToTuple(tmp)
    end}
end)

function ConvolveFloat( ConvWidth, ConvHeight, coeffs, shift )
  return G.Function{"ConvolveFloat", T.rv(T.Array2d( T.FloatRec32, ConvWidth, ConvHeight )),
    function(i)
      local c = R.constant( "convkernel", coeffs, types.array2d( types.Float32, ConvWidth, ConvHeight) )
      c = G.Map{G.FloatRec{32}}(c)
      local packed = G.Zip(i,c)
      local conv = G.Map{G.MulF}(packed)
      conv = G.Reduce{G.AddF}(conv)
      conv = G.MulF{1/math.pow(2,shift)}(conv)
      return conv
    end}
end

harrisDXDYKernel = G.Function{"DXDYKernel", types.rv(types.Array2d(types.FloatRec32,3,3)),
function(i)
  local dx = G.SubF(G.Index{{2,1}}(i),G.Index{{0,1}}(i))
  dx = G.MulF{1/2}(dx)

  local dy = G.SubF(G.Index{{1,2}}(i),G.Index{{1,0}}(i))
  dy = G.MulF{1/2}(dy)

  return R.concat{dx,dy}
end}

harrisHarrisKernel = G.SchedulableFunction{"HarrisKernel",T.Tuple{T.FloatRec32,T.FloatRec32},
function(i)
  local dx, dy = i[0], i[1]
  local Ixx, Ixy, Iyy = G.MulF(dx,dx), G.MulF(dx,dy), G.MulF(dy,dy)
  local det = G.SubF(G.MulF(Ixx,Iyy),G.MulF(Ixy,Ixy))
  local tr = G.AddF(Ixx,Iyy)
  local trsq = G.MulF(tr,tr)

  local K = 0.00000001
  local Krigel = G.FloatRec{32}(G.Const{T.Float32,K}(G.ValueToTrigger(i)))
  local out = G.SubF( det, G.MulF(trsq,Krigel) )
  return out
end}

harrisNMS = G.Function{"NMS", T.rv(types.Array2d(types.FloatRec32,3,3)),
function(i)
  local N = G.GTF(G.Index{{1,1}}(i),G.Index{{1,0}}(i))
  local S = G.GTF(G.Index{{1,1}}(i),G.Index{{1,2}}(i))
  local E = G.GTF(G.Index{{1,1}}(i),G.Index{{2,1}}(i))
  local W = G.GTF(G.Index{{1,1}}(i),G.Index{{0,1}}(i))
  local nms = G.And(G.And(G.And(N,S),E),W)

  local THRESH = 0.001
  local THRESHrigel = G.FloatRec{32}(G.Const{T.Float32,THRESH}(G.ValueToTrigger(i)))
  local aboveThresh = G.GTF(G.Index{{1,1}}(i),THRESHrigel)
  local out = G.And(nms, aboveThresh)
  return out
end}

HarrisDXDY = G.SchedulableFunction{"HarrisDXDY",T.Array2d(T.U(8),P.SizeValue("size")),
function(i)
  local blurX =  G.Pad{{2,2,0,0}}(i)
  blurX = G.Map{G.FloatRec{32}}(blurX)
  blurX = G.Stencil{{-4,0,0,0}}(blurX)
  blurX = G.Map{ConvolveFloat(5,1,GAUSS,8)}(blurX)
  blurX = G.Crop{{4,0,0,0}}(blurX)

  local blurXY = G.Pad{{0,0,2,2}}(blurX)
  blurXY = G.Stencil{{0,0,-4,0}}(blurXY)
  blurXY = G.Map{ConvolveFloat(1,5,GAUSS,8)}(blurXY)
  blurXY = G.Crop{{0,0,4,0}}(blurXY)

  local dxdy = G.Pad{{1,1,1,1}}(blurXY)
  dxdy = G.Stencil{{-2,0,-2,0}}(dxdy)
  dxdy = G.Map{harrisDXDYKernel}(dxdy)
  dxdy = G.Crop{{2,0,2,0}}(dxdy)
  
  return dxdy
end}

function siftbucketReduce( descType, N,X)
  assert(types.isType(descType))
  assert(type(N)=="number")
  assert(X==nil)

  local descArray = types.array2d(descType,N)
  local inp = R.input(types.rv(types.Par(types.tuple{descArray,descArray})))
  local out = R.apply("SOA",C.SoAtoAoS(N,1,{descType,descType}),inp)
  local out = R.apply("MP",RM.map(C.sum(types.int(32),types.int(32),types.int(32),true),N),out)
  return RM.lambda("bucketReduce",inp,out)
end

local function siftBucket( dxdyType, magtype, REDUCE_TYPE, REDUCE_SCALE, X )
  assert(type(REDUCE_SCALE)=="number")
  assert( types.isType(magtype) )
  print("DXDYTYPE",dxdyType,magtype)
  
  return G.Function{"SiftBucket",types.rv(types.tuple{dxdyType,dxdyType,magtype}),
    function(i)
      local dx = G.FtoFR(i[0])
      local dy = G.FtoFR(i[1])
      local mag = G.MulF{REDUCE_SCALE}(i[2]) --*f.constant(RED_SCALE)):lower(RED_TYPE)
      assert( REDUCE_TYPE==types.int(32) )
      mag = G.FRtoI{32}(mag)

      local zero = R.c( REDUCE_TYPE, 0 ) --f.plainconstant(0,RED_TYPE)

      local zf = R.c( types.FloatRec32, 0 )
      
      local dx_ge_0 = G.GEF( dx, zf )
      local dy_ge_0 = G.GEF( dy, zf )
      local dx_gt_dy = G.GTF( dx, dy )
      local dx_gt_negdy = G.GTF( dx, G.NegF(dy) )
      local dy_gt_negdx = G.GTF( dy, G.NegF(dx) )
      local negdx_gt_negdy = G.GTF( G.NegF(dx), G.NegF(dy) )
        
      local v0 = G.Sel(G.And(dx_ge_0,G.And(dy_ge_0,dx_gt_dy)),mag,zero)
      local v1 = G.Sel(G.And(dx_ge_0,G.And(dy_ge_0,G.Not(dx_gt_dy))),mag,zero)
      local v7 = G.Sel(G.And(dx_ge_0,G.And(G.Not(dy_ge_0),dx_gt_negdy)),mag,zero)
      local v6 = G.Sel(G.And(dx_ge_0,G.And(G.Not(dy_ge_0),G.Not(dx_gt_negdy))),mag,zero)
      local v2 = G.Sel(G.And(G.Not(dx_ge_0),G.And(dy_ge_0,dy_gt_negdx)),mag,zero)
      local v3 = G.Sel(G.And(G.Not(dx_ge_0),G.And(dy_ge_0,G.Not(dy_gt_negdx))),mag,zero)
      local v4 = G.Sel(G.And(G.Not(dx_ge_0),G.And(G.Not(dy_ge_0),negdx_gt_negdy)),mag,zero)
      local v5 = G.Sel(G.And(G.Not(dx_ge_0),G.And(G.Not(dy_ge_0),G.Not(negdx_gt_negdy))),mag,zero)

      return G.TupleToArray(R.concat{v0,v1,v2,v3,v4,v5,v6,v7})
    end}
end

local siftMag = J.memoize(function(dxdyType)
  local Pre = G.Function{"siftMagPre",types.rv(types.tuple{dxdyType,dxdyType}),
    function(i)
      local dx = G.FloatRec(i[0])
      local dy = G.FloatRec(i[1])
      local magsq = G.AddF( G.MulF(dx,dx), G.MulF(dy,dy) )
      return magsq
    end}
  
  return G.Function{"siftMagInp",types.RV(types.tuple{dxdyType,dxdyType,dxdyType}),
    function(inp)
      local i = G.FanOut{2}(inp)
      local gauss_weight = G.FIFO{128}(G.FloatRec(i[1][2]))

      local magsq = G.Fmap{Pre}(G.Slice{{0,1}}(i[0]))
      local mag = G.SqrtF( magsq )
      mag = G.FIFO{1}(mag)

      local out = G.MulF(G.FanIn(mag,gauss_weight))
      return out
    end}
end)

function posSub(x,y)
  local A = types.uint(16)
  local ITYPE = types.tuple {A,A}

  local ps = RM.lift("Possub", types.tuple{A,A}, types.tuple{A,A},1,
    function(sinp)
      local xinp = S.index(sinp,0)
      local yinp = S.index(sinp,1)
      
      local xo = xinp-S.constant(x,A)
      local yo = yinp-S.constant(y,A)
      
      return S.tuple{xo,yo}
    end,
    function() return siftTerra.posSub(ITYPE,x,y) end)

  return ps
end

function siftaddPos( dxdyType, W, H, subX, subY, TILES_X, TILES_Y, X )
  assert(types.isType(dxdyType))
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(TILES_X)=="number")
  assert(type(TILES_Y)=="number")
  assert( X==nil )
  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  local inp = R.input(types.rv(types.Par(types.array2d(DXDY_PAIR,TILES_X*4,TILES_Y*4))))

  local PS = RM.posSeq(W,H,1)
  local pos = R.apply("posseq", PS, G.ValueToTrigger(inp))
  local pos = R.apply("pidx", C.index(types.array2d(types.tuple{types.uint(16),types.uint(16)},1),0,0), pos )
  
  if subX~=nil then
    assert(type(subX)=="number")
    assert(type(subY)=="number")
    pos = R.apply("possub",posSub(subX,subY), pos)
  end

  local out = R.concat("FO",{inp,pos})
  return RM.lambda("addPosAtInput",inp,out)
end

function siftDescriptor( dxdyType, TILES_X, TILES_Y, X )
  assert( type(TILES_X)=="number" )
  assert( type(TILES_Y)=="number" )
  assert( X==nil )
  
  if GRAD_INT then
    assert(dxdyType==GRAD_TYPE)
  else
    assert(dxdyType==types.Float32)
  end

  local GAUSS = calcGaussian(GAUSS_SIGMA,TILES_X*4,TILES_Y*4) -- sigma was 5
  GAUSS = tileGaussian(GAUSS,TILES_X*4,TILES_Y*4,4)

  local calcType = types.Float32

  local ITYPE = types.tuple{dxdyType,dxdyType}
  local inp = R.input(types.RV(types.Par(ITYPE)))
  local inpb = G.FanOut{3}(inp)
  
  local gweight = R.apply("gweight",RM.makeHandshake(RM.constSeq(GAUSS,calcType,TILES_X*TILES_Y*16,1,(TILES_X*TILES_Y*16))),G.FIFO{128}(G.ValueToTrigger(inpb[0])))
  --local gweight = R.apply("gwidx",C.index(types.array2d(calcType,1),0,0),gweight)
  gweight = G.Index{0}(gweight)
  --local dx = R.apply("i0", C.index(ITYPE,0), inp)
  local dx = G.FIFO{128}(inpb[1][0])
  --local dy = R.apply("i1", C.index(ITYPE,1), inp)
  local dy = G.FIFO{128}(inpb[2][1])

  if GRAD_INT then
    print("DXDY",dxdyType)
    dx = G.Float(G.ItoFR(dx))
    dy = G.Float(G.ItoFR(dy))
  end

  dx, dy = G.FanOut{2}(dx), G.FanOut{2}(dy)
  
  local maginp = R.concat("maginp",{G.FIFO{128}(dx[0]),G.FIFO{128}(dy[0]),gweight})
  local magFn = siftMag(calcType)
  local magType = magFn.outputType:deInterface()
  local mag = R.apply("mag",magFn,G.FanIn(maginp))
  local bucketInp = R.concat("bktinp",{G.FIFO{128}(dx[1]),G.FIFO{128}(dy[1]),mag})
  local out = R.apply( "out", G.Fmap{siftBucket( calcType, magType, types.int(32), 1024/GRAD_SCALE )}, G.FanIn(bucketInp) )
  return RM.lambda("siftDescriptor",inp,out), types.int(32)
end

function sifttile(W,H,T,A)
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(T)=="number")
  assert(W%T==0)
  assert(H%T==0)

  local ITYPE = types.array2d(A,W,H)
  local inp = R.input(types.rv(types.Par(ITYPE)))

  local tab = {}
  for y=0,H-1 do
    tab[y] = {}
    for x=0,W-1 do
      tab[y][x] = R.apply("idx_"..y.."_"..x, C.index( ITYPE, x, y ), inp)
    end
  end

  local outarr = {}
  for ty=0,(H/T)-1 do
    for tx=0,(W/T)-1 do
      local out = {}
      for y=0,T-1 do
        for x=0,T-1 do
          table.insert(out, tab[ty*T+y][tx*T+x])
        end
      end
      table.insert(outarr, R.concatArray2d("AR_"..ty.."_"..tx,out,T*T) )
    end
  end

  local fin = R.concatArray2d("fin",outarr,(W/T)*(H/T))

  return RM.lambda("tile", inp, fin )
end

local siftaddDescriptorPos = J.memoize(function( descType, TILES_X, TILES_Y, X)
  assert( type(TILES_X)=="number" )
  assert( type(TILES_Y)=="number" )
  assert( X==nil )
  
  return G.Function{"descpos",types.rv(types.tuple{types.array2d(descType,TILES_X*TILES_Y*8),types.uint(16),types.uint(16)}),
    function(i)
      local desc = i[0]
      local px = G.UtoFR(i[1]) --inp:index(1):lift(0)
      local py = G.UtoFR(i[2]) --inp:index(2):lift(0)
      
      local a = {px,py}
      for i=0,(TILES_X*TILES_Y*8-1) do table.insert(a,desc[i]) end
      --local out = f.array2d(a,TILES_X*TILES_Y*8+2)
      local out = G.TupleToArray(R.concat(a))
      return out --:toRigelModule("addDescriptorPos")
    end}
end)

--function siftKernel( dxdyType, TILES_X, TILES_Y, X )
--  assert( type(TILES_X)=="number" )
--  assert( type(TILES_Y)=="number" )
--  assert(X==nil)

--  print("SiftKernel",dxdyType)
  
--  local dxdyPair = types.tuple{dxdyType,dxdyType}
--  local posType = types.uint(16)
--  local PTYPE = types.tuple{posType,posType}
--  local ITYPE = types.tuple{types.array2d(dxdyPair,TILES_X*4,TILES_Y*4),PTYPE}

--  local fifos = {}
--  local statements = {}

--  local inp = R.input(R.Handshake(ITYPE))
local SiftKernel = G.SchedulableFunction{"SiftKernel",
T.Tuple{T.Array2d(T.Tuple{T.I8,T.I8},TILES_X*4,TILES_Y*4), T.Tuple{T.U16,T.U16} },
function(i)
  local dxdyType = types.I8
  local dxdyPair = types.tuple{dxdyType,dxdyType}
  local posType = types.uint(16)
  
  --local inp_broad = R.apply("inp_broad", RM.broadcastStream(types.Par(ITYPE),2), inp)
  local inp = G.FanOut{2}(i)

  --local inp_pos = C.fifo(ITYPE,1,nil,true)(R.selectStream("i0",inp_broad,0))
  --local inp_pos = G.FIFO{1}(inp[0])
  --local pos = R.apply("p",RM.makeHandshake(C.index(ITYPE,1)), inp_pos)

  local pos = inp[0][1]
  --local pos = C.fifo(PTYPE,1024)(pos)
  pos = G.FIFO{1024}(pos)
  
  --local pos0, pos1 = RS.fanOut{input=pos,branches=2}
  local posFO = G.FanOut{2}(pos)

  --local posX = R.apply("px",RM.makeHandshake(C.index(PTYPE,0)),pos0)
  --local posX = C.fifo(posType,1024)(posX)
  local posX = G.FIFO{1024}(posFO[0][0])
  
  --local posY = R.apply("py",RM.makeHandshake(C.index(PTYPE,1)),pos1)
  --local posY = C.fifo(posType,1024)(posY)
  local posY = G.FIFO{1024}(posFO[1][1])

  --local inp_dxdy = C.fifo(ITYPE,1,nil,true)(R.selectStream("i1",inp_broad,1))
  local dxdy = inp[1][0]
  --local dxdy = R.apply("dxdy",RM.makeHandshake(C.index(ITYPE,0,0)), inp_dxdy)

  local dxdyTile = R.apply("TLE",RM.makeHandshake( sifttile(TILES_X*4,TILES_Y*4,4,dxdyPair)),dxdy)
  local dxdy = R.apply( "down1", RM.liftHandshake(RM.changeRate(types.array2d(dxdyPair,16),1,TILES_X*TILES_Y,1)), dxdyTile )
  local dxdy = R.apply("down1idx",RM.makeHandshake(C.index(types.array2d(types.array2d(dxdyPair,16),1),0,0)), dxdy)
  local dxdy = R.apply("down2", RM.liftHandshake(RM.changeRate(dxdyPair,1,16,1)), dxdy )
  local dxdy = R.apply("down2idx",RM.makeHandshake(C.index(types.array2d(dxdyPair,1),0,0)), dxdy)
  local descFn, descTypeRed = siftDescriptor( dxdyType, TILES_X, TILES_Y )
  local descType = types.Float32
  local desc = R.apply("desc",descFn,dxdy)

  local desc = R.apply("rseq",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq( siftbucketReduce(descTypeRed,8),16))),desc)

  -- it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
  -- We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
  -- that reduceSeq only has an output every 16 cycles, so it can't overlap them)
  --local desc = C.fifoLoop(fifos,statements,types.array2d(descTypeRed,8),desc,128,"lol",false) -- fifo size can also be 1 (tested in SW)
  local desc = C.fifo(types.array2d(descTypeRed,8),128)(desc)

  local desc = R.apply("up",RM.liftHandshake(RM.changeRate(descTypeRed,1,8,1)),desc)
  local desc = R.apply("upidx",RM.makeHandshake(C.index(types.array2d(descTypeRed,1),0,0)), desc)

  -- sum and normalize the descriptors
  local desc_broad = R.apply("desc_broad", RM.broadcastStream(types.Par(descTypeRed),2), desc)

  local desc0 = R.selectStream("d0",desc_broad,0)
  --local desc0 = C.fifoLoop( fifos, statements, descTypeRed, desc0, 256, "d0")
  local desc0 = C.fifo(descTypeRed,256)(desc0)

  local desc1 = R.selectStream("d1",desc_broad,1)

  local desc1 = C.fifo(descTypeRed,256)(desc1)

  local desc_sum = R.apply("sum",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq( RS.modules.sumPow2{inType=types.int(32),outType=types.int(32)},(TILES_X*TILES_Y*8)))),desc1)
  --local desc_sum = R.apply("sumlift",RM.makeHandshake( sift.fixedLift(types.int(32))), desc_sum)
  desc_sum = G.ItoFR(desc_sum)

  --local desc_sum = R.apply("sumsqrt",RM.makeHandshake( sift.fixedSqrt(descType)), desc_sum)
  desc_sum = G.SqrtF( desc_sum )
  --desc_sum = G.Broadcast{{TILES_X*TILES_Y*8,1}}(desc_sum)

  local descType = T.FloatRec32
  local desc_sum = R.apply("DAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc_sum)
  local desc_sum = R.apply("sumup",RM.upsampleXSeq( descType, 1, TILES_X*TILES_Y*8), desc_sum)
  local desc_sum = R.apply("Didx",RM.makeHandshake(C.index(types.array2d(descType,1),0,0)), desc_sum)

  --local desc0 = R.apply("d0lift",RM.makeHandshake( sift.fixedLift(types.int(32))), desc0)
  desc0 = G.ItoFR(desc0)
  print("DESC0",desc0.type,desc0.rate)
  
  --local desc = R.apply("pt",RM.packTuple{types.RV(types.Par(descType)),types.RV(types.Par(descType))},R.concat("PTT",{desc0,desc_sum}))
  local desc = G.FanIn(desc0,desc_sum)
  --local desc = R.apply("ptt",RM.makeHandshake( sift.fixedDiv(descType)),desc)
  print("DESC",desc.type,desc.rate)
--  desc = G.TupleToArray(desc)
--  desc = G.Map{G.FtoFR}(desc)
  print("DESC",desc.type,desc.rate)
--  desc = G.ArrayToTuple(desc)

  desc = G.DivF(desc)

  --desc = G.Float(desc)
  
  local desc = R.apply("DdAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc)

  local desc = R.apply("repack",RM.liftHandshake(RM.changeRate(descType,1,1,TILES_X*TILES_Y*8)),desc)
  -- we now have an array of type descType[128]. Add the pos.
  local desc_pack = R.apply("dp", RM.packTuple{types.RV(types.Par(types.array2d(descType,TILES_X*TILES_Y*8))),types.RV(types.Par(posType)),types.RV(types.Par(posType))},R.concat("DPT",{desc,posX,posY}))
  local desc = R.apply("addpos",RM.makeHandshake( siftaddDescriptorPos( descType, TILES_X, TILES_Y )), desc_pack)

--  table.insert(statements,1,desc)

--  local siftfn = RM.lambda("siftd",inp,R.statements(statements),fifos)
  
  --  return siftfn, descType
  return desc
end}

function SiftTop( FILTER_RATE, FILTER_FIFO, TILES_X, TILES_Y, X)
  assert(type(FILTER_FIFO)=="number")
  assert(type(TILES_X)=="number")
  assert(type(TILES_Y)=="number")
  assert(X==nil)

  return G.SchedulableFunction{"SiftTop", T.Array2d(T.U(8),P.SizeValue("size")),
    function(inp)                           

      local dxdyType = types.Float32
      local DXDY_PAIR = types.tuple{dxdyType,dxdyType}

      local out = HarrisDXDY(inp)

      out = G.Pad{{7,8,7,8}}(out)
      
      local dxdyBroad = G.FanOut{2}(out)

      local internalW = W+15
      local internalH = H+15

      -------------------------------
      -- right branch: make the harris bool
      local right = R.selectStream("d1",dxdyBroad,1)
      
      right = G.RVFIFO{128}(right)
      
      right = G.Map{harrisHarrisKernel}(right)
      local harrisType = types.Float32
      
      -- now stencilify the harris
      local right = G.Stencil{{-2,0,-2,0}}(right)
      
      right = G.Map{harrisNMS}(right)
      
      -------------------------------
      -- left branch: make the dxdy int8 stencils
      local left = R.selectStream("d0",dxdyBroad,0)
      
      if GRAD_INT then
        left = G.Map{siftlowerPair( GRAD_TYPE, GRAD_SCALE)}(left)
        dxdyType = GRAD_TYPE
        DXDY_PAIR = types.tuple{GRAD_TYPE,GRAD_TYPE}
      end

      left = G.FIFO{2048/DXDY_PAIR:verilogBits()}(left)

      left = G.Stencil{{-TILES_X*4+1,0,-TILES_Y*4+1,0}}(left)
      left = G.Map{siftaddPos( dxdyType, internalW, internalH, 15, 15, TILES_X, TILES_Y )}(left)
      -------------------------------

      -- merge left/right
      local out = G.Zip(left,right)

      out = G.Crop{{15,0,15,0}}(out)

      out = G.Filter{{FILTER_RATE[1],FILTER_RATE[2]}}(out)

      out = G.FIFO{FILTER_FIFO}(out)

      --local siftFn, descType = siftKernel( dxdyType, TILES_X, TILES_Y )

      out = G.Map{SiftKernel}(out)

      -- hack: we know how many descriptors will be written out, so just clamp the array to that size!
      -- this will allow use to use the standard DMAs
      out = G.ClampToSize{{OUTPUT_COUNT,1}}(out)
      out = G.Flatten(out)

      -- bitcast to uint8[8] for display...
      out = G.Map{G.Float}(out)
      out = G.Map{G.Bitcast{types.Array2d(types.Uint(8),4)}}(out)
      out = G.Flatten(out)
      out = G.Reshape{{130*4,OUTPUT_COUNT}}(out)
      
      return out
    end}
end

local OffsetModule = G.SchedulableFunction{ "OffsetModule", T.Trigger,
  function(i)
    local readStream = G.AXIReadBurst{ "boxanim_256.raw", {W,H}, T.u(8), 8, noc.read }(i)
    local offset = SiftTop(FILTER_RATE,FILTER_FIFO,TILES_X,TILES_Y)(readStream)
    return G.AXIWriteBurst{"out/soc_sift",noc.write}(offset)
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
