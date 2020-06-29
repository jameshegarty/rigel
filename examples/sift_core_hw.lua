local R = require "rigel"
local RM = require "generators.modules"
local RS = require "rigelSimple"
local types = require("types")
local S = require("systolic")
local harris = require "harris_core"
local C = require "generators.examplescommon"
local f = require "fixed_float"
local SDFRate = require "sdfrate"
local J = require "common"
local G = require "generators.core"

local siftTerra
if terralib~=nil then siftTerra = require("sift_core_hw_terra") end

local GAUSS_SIGMA = 5 --5

local sift = {}

local Clamp = G.Function{"Clampint8",types.rv(types.FloatRec32),
  function(i)
    local v127 = G.FtoFR(R.c(types.Float32,127))
    local vm128 = G.FtoFR(R.c(types.Float32,-128))
    local tmp = G.Sel(G.GTF(i,v127),v127,i)
    local tmp = G.Sel(G.LTF(i,vm128),vm128,tmp)
    return tmp
  end}
                                             
sift.lowerPair = J.memoize(function( FROM, TO, scale, X )
  assert(types.isType(FROM))
  assert(types.isType(TO))
  assert( scale==math.floor(scale) )
  assert( X==nil )

  assert( FROM:isFloat() )
  assert( TO:isInt() )
  assert(TO==types.int(8))
  assert( scale==4 )

  return G.Function{"LowerPair",types.rv(types.tuple{FROM,FROM}),
    function(i)
      local tmp = R.concat{G.MulF{scale}(G.FloatRec{32}(i[0])), G.MulF{scale}(G.FloatRec{32}(i[1]))}

      tmp = G.TupleToArray(tmp)
      tmp = G.Map{Clamp}(tmp)
      tmp = G.Map{G.FRtoI{8}}(tmp)
      return G.ArrayToTuple(tmp)
    end}
end)
  
----------------
function sift.calcGaussian(sig,GAUSS_WIDTH_inp,GAUSS_HEIGHT_inp)
  assert(type(GAUSS_WIDTH_inp)=="number")

  local GAUSS_WIDTH = GAUSS_WIDTH_inp/2
  local GAUSS_HEIGHT = GAUSS_HEIGHT_inp/2

  local G = {}
  local sum = 0

  for y=0,GAUSS_HEIGHT-1 do
    for x=0,GAUSS_WIDTH-1 do
      local sigma = math.sqrt(sig)
      local a = 1/(sigma*math.sqrt(2*3.141526))
      local X  = x-3.5
      local Y  = y-3.5
      local dist = math.sqrt(X*X+Y*Y)
      G[y*GAUSS_WIDTH+x] = a * math.exp(-(dist*dist)/(2*sigma*sigma))
      sum = sum + G[y*GAUSS_WIDTH+x]
    end
  end

  -- normalize
  for y=0,GAUSS_HEIGHT-1 do
    for x=0,GAUSS_WIDTH-1 do
      G[y*GAUSS_WIDTH+x] = G[y*GAUSS_WIDTH+x]/sum
      --print("GAUSS X",x,"Y",y,"Value",G[y*GAUSS_WIDTH+x])
    end
  end

  -- dup
  local GG = {}

  for y=0,GAUSS_HEIGHT_inp-1 do
    for x=0,GAUSS_WIDTH_inp-1 do
      local xx = math.floor(x/2)
      local yy = math.floor(y/2)
      GG[y*GAUSS_WIDTH_inp+x] = G[yy*GAUSS_WIDTH+xx]
    end
  end

  return GG
end
local calcGaussian = sift.calcGaussian

-- T: tile size
function sift.tileGaussian(G,W,H,T)
  assert(type(G)=="table")
  assert(type(W)=="number")
  assert(type(T)=="number")

  local GG = {}
  for ty=0,(H/T)-1 do
    for tx=0,(W/T)-1 do
      for y=0,T-1 do
        for x=0,T-1 do
          table.insert(GG,G[(ty*T+y)*W+(tx*T+x)])
        end
      end
    end
  end

  return GG
end
local tileGaussian = sift.tileGaussian
----------------
--[=[
local function siftBucket(dxdyType,magtype)
  local inp = f.parameter("bucketinp",types.tuple{dxdyType,dxdyType,magtype})
  local dx = inp:index(0)
  local dy = inp:index(1)
  local mag = (inp:index(2)*f.constant(RED_SCALE)):lower(RED_TYPE)

  local zero = f.plainconstant(0,RED_TYPE)
  local dx_ge_0 = dx:ge(f.constant(0))
  local dy_ge_0 = dy:ge(f.constant(0))
  local dx_gt_dy = dx:gt(dy)
  local dx_gt_negdy = dx:gt(dy:neg())
  local dy_gt_negdx = dy:gt(dx:neg())
  local negdx_gt_negdy = (dx:neg()):gt(dy:neg())

  local v0 = f.select(dx_ge_0:__and(dy_ge_0:__and(dx_gt_dy)),mag,zero)
  local v1 = f.select(dx_ge_0:__and(dy_ge_0:__and(dx_gt_dy:__not())),mag,zero)
  local v7 = f.select(dx_ge_0:__and((dy_ge_0:__not()):__and(dx_gt_negdy)),mag,zero)
  local v6 = f.select(dx_ge_0:__and((dy_ge_0:__not()):__and(dx_gt_negdy:__not())),mag,zero)
  local v2 = f.select((dx_ge_0:__not()):__and(dy_ge_0:__and(dy_gt_negdx)),mag,zero)
  local v3 = f.select((dx_ge_0:__not()):__and(dy_ge_0:__and(dy_gt_negdx:__not())),mag,zero)
  local v4 = f.select((dx_ge_0:__not()):__and((dy_ge_0:__not()):__and(negdx_gt_negdy)),mag,zero)
  local v5 = f.select((dx_ge_0:__not()):__and((dy_ge_0:__not()):__and(negdx_gt_negdy:__not())),mag,zero)

  local out = f.array2d({v0,v1,v2,v3,v4,v5,v6,v7},8)
  return out:toRigelModule("siftBucket")
  end]=]

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
----------------
-- input {dx,dy,gaussweight}
--[=[local function siftMag(dxdyType)
  local inp = f.parameter("siftMagInp",types.tuple{dxdyType,dxdyType,dxdyType})
  local dx = inp:index(0)
  local dy = inp:index(1)
  local gauss_weight = inp:index(2)
  local magsq = (dx*dx)+(dy*dy)
  local mag = magsq:sqrt()

  local out = mag*gauss_weight
  return out:toRigelModule("siftmag"), out.type
  end]=]

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
      local mag = G.BoostRate{G.SqrtF,8}( magsq )
      mag = G.FIFO{1}(mag)

      local out = G.MulF(G.FanIn(mag,gauss_weight))
      return out
    end}
end)

----------------
-- input: {dx,dy}
-- output: descType[BUCKETS], descType
function sift.siftDescriptor( dxdyType, TILES_X, TILES_Y, X )
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
----------------
-- input: {descType[N],descType[N]}
-- output: descType[N]
function sift.bucketReduce( descType, N,X)
  assert(types.isType(descType))
  assert(type(N)=="number")
  assert(X==nil)

  local descArray = types.array2d(descType,N)
  local inp = R.input(types.rv(types.Par(types.tuple{descArray,descArray})))
  local out = R.apply("SOA",C.SoAtoAoS(N,1,{descType,descType}),inp)
  local out = R.apply("MP",RM.map(C.sum(types.int(32),types.int(32),types.int(32),true),N),out)
  return RM.lambda("bucketReduce",inp,out)
end
----------------
-- input: A[W,H]
-- output: A[(W/T)*(H/T)][T*T]
function sift.tile(W,H,T,A)
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

----------------
-- input: {descType[128],uint16,uint16}
-- output: descType[130]
--[=[function sift.addDescriptorPos( descType, TILES_X, TILES_Y, X)
  assert( type(TILES_X)=="number" )
  assert( type(TILES_Y)=="number" )
  assert( X==nil )
  
  local inp = f.parameter("descpos",types.tuple{types.array2d(descType,TILES_X*TILES_Y*8),types.uint(16),types.uint(16)})
  local desc = inp:index(0)
  local px = inp:index(1):lift(0)
  local py = inp:index(2):lift(0)
  
  local a = {px,py}
  for i=0,(TILES_X*TILES_Y*8-1) do table.insert(a,desc:index(i)) end
  local out = f.array2d(a,TILES_X*TILES_Y*8+2)
  return out:toRigelModule("addDescriptorPos")
  end]=]

sift.addDescriptorPos = J.memoize(function( descType, TILES_X, TILES_Y, X)
  assert( type(TILES_X)=="number" )
  assert( type(TILES_Y)=="number" )
  assert( X==nil )
  
  return G.Function{"descpos",types.rv(types.tuple{types.array2d(descType,TILES_X*TILES_Y*8),types.uint(16),types.uint(16)}),
    function(i)
      local desc = i[0]
      local px = G.FRtoF(G.UtoFR(i[1])) --inp:index(1):lift(0)
      local py = G.FRtoF(G.UtoFR(i[2])) --inp:index(2):lift(0)
      
      local a = {px,py}
      for i=0,(TILES_X*TILES_Y*8-1) do table.insert(a,desc[i]) end
      --local out = f.array2d(a,TILES_X*TILES_Y*8+2)
      local out = G.TupleToArray(R.concat(a))
      return out --:toRigelModule("addDescriptorPos")
    end}
end)

----------------
-- input: {{dx,dy}[16,16],{posX,posY}}
-- output: descType[128+2], descType
function sift.siftKernel( dxdyType, TILES_X, TILES_Y, X )
  assert( type(TILES_X)=="number" )
  assert( type(TILES_Y)=="number" )
  assert(X==nil)
  
  local dxdyPair = types.tuple{dxdyType,dxdyType}
  local posType = types.uint(16)
  local PTYPE = types.tuple{posType,posType}
  local ITYPE = types.tuple{types.array2d(dxdyPair,TILES_X*4,TILES_Y*4),PTYPE}

  local fifos = {}
  local statements = {}

  local inp = R.input(R.Handshake(ITYPE))
  local inp_broad = R.apply("inp_broad", RM.broadcastStream(types.Par(ITYPE),2), inp)

  local inp_pos = C.fifo(ITYPE,1,nil,true)(R.selectStream("i0",inp_broad,0))
  local pos = R.apply("p",RM.makeHandshake(C.index(ITYPE,1)), inp_pos)

  local pos = C.fifo(PTYPE,1024)(pos)
  local pos0, pos1 = RS.fanOut{input=pos,branches=2}

  local posX = R.apply("px",RM.makeHandshake(C.index(PTYPE,0)),pos0)

  local posX = C.fifo(posType,1024)(posX)
  local posY = R.apply("py",RM.makeHandshake(C.index(PTYPE,1)),pos1)

  local posY = C.fifo(posType,1024)(posY)

  local inp_dxdy = C.fifo(ITYPE,1,nil,true)(R.selectStream("i1",inp_broad,1))
  local dxdy = R.apply("dxdy",RM.makeHandshake(C.index(ITYPE,0,0)), inp_dxdy)

  local dxdyTile = R.apply("TLE",RM.makeHandshake( sift.tile(TILES_X*4,TILES_Y*4,4,dxdyPair)),dxdy)
  local dxdy = R.apply( "down1", RM.changeRate(types.array2d(dxdyPair,16),1,TILES_X*TILES_Y,1), dxdyTile )
  local dxdy = R.apply("down1idx",RM.makeHandshake(C.index(types.array2d(types.array2d(dxdyPair,16),1),0,0)), dxdy)
  local dxdy = R.apply("down2", RM.changeRate(dxdyPair,1,16,1), dxdy )
  local dxdy = R.apply("down2idx",RM.makeHandshake(C.index(types.array2d(dxdyPair,1),0,0)), dxdy)
  local descFn, descTypeRed = sift.siftDescriptor( dxdyType, TILES_X, TILES_Y )
  local descType = types.Float32
  local desc = R.apply("desc",descFn,dxdy)

  local desc = R.apply("rseq",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq( sift.bucketReduce(descTypeRed,8),16))),desc)

  -- it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
  -- We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
  -- that reduceSeq only has an output every 16 cycles, so it can't overlap them)
  --local desc = C.fifoLoop(fifos,statements,types.array2d(descTypeRed,8),desc,128,"lol",false) -- fifo size can also be 1 (tested in SW)
  local desc = C.fifo(types.array2d(descTypeRed,8),128)(desc)

  local desc = R.apply("up",RM.changeRate(descTypeRed,1,8,1),desc)
  local desc = R.apply("upidx",RM.makeHandshake(C.index(types.array2d(descTypeRed,1),0,0)), desc)

  -- sum and normalize the descriptors
  local desc_broad = R.apply("desc_broad", RM.broadcastStream(types.Par(descTypeRed),2), desc)

  local desc0 = R.selectStream("d0",desc_broad,0)
  --local desc0 = C.fifoLoop( fifos, statements, descTypeRed, desc0, 256, "d0")
  local desc0 = C.fifo(descTypeRed,256)(desc0)

  local desc1 = R.selectStream("d1",desc_broad,1)

  local desc1 = C.fifo(descTypeRed,256)(desc1)

  desc1 = G.ItoFR(desc1)
  local descpow2 = G.Pow2(desc1)
  descpow2 = G.Broadcast{{1,1}}(descpow2)
  local desc_sum = G.DeserSeq{TILES_X*TILES_Y*8}(descpow2)
  desc_sum = G.Reduce{G.AddF}(desc_sum)
  
  --local desc_sum = R.apply("sumlift",RM.makeHandshake( sift.fixedLift(types.int(32))), desc_sum)


  --local desc_sum = R.apply("sumsqrt",RM.makeHandshake( sift.fixedSqrt(descType)), desc_sum)
  desc_sum = G.SqrtF( desc_sum )
  desc_sum = G.Float(desc_sum)
  local desc_sum = R.apply("DAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc_sum)
  local desc_sum = R.apply("sumup",RM.upsampleXSeq( descType, 1, TILES_X*TILES_Y*8), desc_sum)
  local desc_sum = R.apply("Didx",RM.makeHandshake(C.index(types.array2d(descType,1),0,0)), desc_sum)

  --local desc0 = R.apply("d0lift",RM.makeHandshake( sift.fixedLift(types.int(32))), desc0)
  desc0 = G.FRtoF(G.ItoFR(desc0))
  local desc = R.apply("pt",RM.packTuple{types.RV(types.Par(descType)),types.RV(types.Par(descType))},R.concat("PTT",{desc0,desc_sum}))
  --local desc = R.apply("ptt",RM.makeHandshake( sift.fixedDiv(descType)),desc)
  desc = G.TupleToArray(desc)
  desc = G.Map{G.FtoFR}(desc)
  desc = G.ArrayToTuple(desc)

  desc = G.BoostRate{G.DivF,4}(desc)

  desc = G.Float(desc)
  
  local desc = R.apply("DdAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc)

  local desc = R.apply("repack",RM.changeRate(descType,1,1,TILES_X*TILES_Y*8),desc)
  -- we now have an array of type descType[128]. Add the pos.
  local desc_pack = R.apply("dp", RM.packTuple{types.RV(types.Par(types.array2d(descType,TILES_X*TILES_Y*8))),types.RV(types.Par(posType)),types.RV(types.Par(posType))},R.concat("DPT",{desc,posX,posY}))
  local desc = R.apply("addpos",RM.makeHandshake( sift.addDescriptorPos( descType, TILES_X, TILES_Y )), desc_pack)

  table.insert(statements,1,desc)

  local siftfn = RM.lambda("siftd",inp,R.statements(statements),fifos)
  
  return siftfn, descType
end

----------------
local function posSub(x,y)
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

function sift.addPos( dxdyType, W, H, subX, subY, TILES_X, TILES_Y, X )
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

function sift.siftDesc( W, H, inputT, TILES_X, TILES_Y, X )
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(inputT)=="number")
  assert(type(TILES_X)=="number")
  assert(type(TILES_Y)=="number")
  assert(X==nil)

  local ITYPE = types.array2d(types.uint(8),inputT)
  
  local inpraw = R.input(R.Handshake(ITYPE))
  local inp = R.apply("reducerate", RM.changeRate(types.uint(8),1,8,1), inpraw )
  local dxdyFn, dxdyType = harris.makeDXDY(W,H)
  local dxdyType = types.Float32
  local out = R.apply("dxdy",dxdyFn,inp)

  out = G.Map{G.TupleToArray}(out)
  out = G.Map{G.Map{G.Float}}(out)
  out = G.Map{G.ArrayToTuple}(out)

    
  if GRAD_INT then
    out = R.apply("dxdy0", RM.makeHandshake(C.index(types.array2d(types.tuple{dxdyType,dxdyType},1),0)), out)
    out = R.apply("dxdyint",RM.makeHandshake(sift.lowerPair(dxdyType,GRAD_TYPE,GRAD_SCALE)),out)
    out = R.apply("dxdyao", RM.makeHandshake( C.arrayop( types.tuple{GRAD_TYPE,GRAD_TYPE}, 1, 1 ) ), out)
    dxdyType = GRAD_TYPE
    
  end

  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  local DXDY_ST = types.array2d(DXDY_PAIR,TILES_X*4,TILES_Y*4)

  --- now stencilify dxdy
  local out = R.apply("ST",RM.makeHandshake(C.stencilLinebuffer(DXDY_PAIR,W,H,1,(-TILES_X*4)+1,0,(-TILES_Y*4)+1,0)), out)

  local DI = sift.addPos( dxdyType, W, H, nil, nil, TILES_X, TILES_Y )
  local out = R.apply("desc_inner",RM.makeHandshake(DI),out)
  local out = R.apply("AO", RM.makeHandshake(C.arrayop(DI.outputType:extractData(),1,1)), out)
  local out = R.apply("CRP", RM.liftHandshake(RM.liftDecimate(RM.cropSeq( DI.outputType:extractData(), W, H, 1, 15, 0, 15, 0))), out)
  local out = R.apply("I0", RM.makeHandshake(C.index(types.array2d(DI.outputType:extractData(),1),0,0)), out)

  local siftFn, descType = sift.siftKernel( dxdyType, TILES_X, TILES_Y )
  local out = R.apply("sft", siftFn, out)

  local out = R.apply("incrate", RM.changeRate(descType,1,TILES_X*TILES_Y*8+2,2), out )

  local fn = RM.lambda( "harris", inpraw, out)
  return fn, descType
end

function sift.siftTop( W, H, T, FILTER_RATE, FILTER_FIFO, TILES_X, TILES_Y, X)
  assert(type(FILTER_FIFO)=="number")
  assert(type(TILES_X)=="number")
  assert(type(TILES_Y)=="number")
  assert(X==nil)

  local fifos = {}
  local statements = {}

  local ITYPE = types.array2d(types.uint(8),T)
  
  local inpraw = R.input(R.Handshake(ITYPE))
  local inp = R.apply("reducerate", RM.changeRate(types.uint(8),1,8,1), inpraw )
  local dxdyFn, dxdyType = harris.makeDXDY(W,H)
  local dxdyType = types.Float32
  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}

  local out = R.apply("dxdy",dxdyFn,inp)

  out = G.Map{G.TupleToArray}(out)
  out = G.Map{G.Map{G.Float}}(out)
  out = G.Map{G.ArrayToTuple}(out)
  
  out = R.apply("pad", RM.liftHandshake(RM.padSeq(DXDY_PAIR, W, H, 1, 7, 8, 7, 8, {0,0})), out)
  
  out = R.apply("dxdyix",RM.makeHandshake(C.index(types.array2d(DXDY_PAIR,1,1),0,0)),out)

  local dxdyBroad = R.apply("dxdy_broad", RM.broadcastStream(types.Par(DXDY_PAIR),2), out)

  local internalW = W+15
  local internalH = H+15

  -------------------------------
  -- right branch: make the harris bool
  local right = R.selectStream("d1",dxdyBroad,1)

  right = C.fifo(DXDY_PAIR,128)(right)

  right = G.TupleToArray(right)
  right = G.Map{G.FloatRec{32}}(right)
  right = G.ArrayToTuple(right)

  right = harris.HarrisKernel(right)
  right = G.Float(right)
  local harrisType = types.Float32
  local right = R.apply("AO",RM.makeHandshake(C.arrayop(harrisType,1,1)), right)

  -- now stencilify the harris
  local right = R.apply( "harris_st", RM.makeHandshake(C.stencilLinebuffer(harrisType, internalW, internalH, 1,-2,0,-2,0)), right)

  right = G.Map{G.FloatRec{32}}(right)
  right = G.Fmap{harris.NMS}(right)

  -------------------------------
  -- left branch: make the dxdy int8 stencils
  local left = R.selectStream("d0",dxdyBroad,0)

  if GRAD_INT then
    left = R.apply("lower", RM.makeHandshake(sift.lowerPair( dxdyType, GRAD_TYPE, GRAD_SCALE)), left)
    dxdyType = GRAD_TYPE
    DXDY_PAIR = types.tuple{GRAD_TYPE,GRAD_TYPE}
  end

  left = C.fifo(DXDY_PAIR,2048/DXDY_PAIR:verilogBits())(left)

  local left = R.apply("stlbinp", RM.makeHandshake(C.arrayop(DXDY_PAIR,1,1)), left)
  local left = R.apply( "stlb", RM.makeHandshake(C.stencilLinebuffer(DXDY_PAIR, internalW, internalH, 1,-TILES_X*4+1,0,-TILES_Y*4+1,0)), left)
  left = R.apply("stpos", RM.makeHandshake(sift.addPos( dxdyType, internalW, internalH, 15, 15, TILES_X, TILES_Y )), left)
  -------------------------------


  local FILTER_TYPE = types.tuple{types.array2d(DXDY_PAIR,TILES_X*4,TILES_Y*4),types.tuple{types.uint(16),types.uint(16)}}
  local FILTER_PAIR = types.tuple{FILTER_TYPE,types.bool()}
  
  -- merge left/right
  local out = R.apply("merge",RM.packTuple{types.RV(types.Par(FILTER_TYPE)),types.RV(types.Par(types.bool()))},R.concat("MPT",{left,right}))

  local out = R.apply("cropao", RM.makeHandshake(C.arrayop(FILTER_PAIR,1,1)), out)
  local out = R.apply("crp", RM.liftHandshake(RM.liftDecimate(RM.cropSeq(FILTER_PAIR,W+15,H+15,1,15,0,15,0))), out)
  local out = R.apply("crpidx", RM.makeHandshake(C.index(types.array2d(FILTER_PAIR,1,1),0,0)), out)
  
  local filterFn = RM.filterSeq( FILTER_TYPE, W, H, FILTER_RATE, FILTER_FIFO, false )

  local out = R.apply("FS",RM.liftHandshake(RM.liftDecimate(filterFn)),out)
  local out = C.fifo(FILTER_TYPE,FILTER_FIFO)(out)

  local siftFn, descType = sift.siftKernel( dxdyType, TILES_X, TILES_Y )

  local out = R.apply("sft", siftFn, out)

  local out = R.apply("incrate", RM.changeRate(descType,1,TILES_X*TILES_Y*8+2,2), out )

  -- bitcast to uint8[8] for display...
  out = G.Fmap{C.bitcast(types.array2d(types.Float32,2),types.Array2d(types.uint(8),8))}(out)
  
  table.insert( statements, 1, out )
  local fn = RM.lambda( "SiftTop", inpraw, R.statements(statements), fifos )

  return fn, descType
end

return sift
