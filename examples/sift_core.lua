local R = require "rigel"
local RS = require "rigelSimple"
local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local harris = require "harris_core"
local C = require "generators.examplescommon"
local f = require "fixed_float"
local SDFRate = require "sdfrate"
f.DISABLE_SYNTH=true
local J = require "common"
local G = require "generators.core"

local siftCoreHWTerra
if terralib~=nil then siftCoreHWTerra=require("sift_core_hw_terra") end

sift = {}

local fixedSum = J.memoize(function(A,async)
  assert(types.isType(A))
  local inp = f.parameter("II",types.tuple{A,A})
  local out = inp:index(0)+inp:index(1)
--  out = out:disablePipelining()
  --  out = out:cast(A)
  if async==true then out = out:disablePipelining() end
  return out:toRigelModule("fixedSum")
                   end)

local fixedSumPow2 = J.memoize(function(A,async)
  assert(types.isType(A))
  local inp = f.parameter("II",types.tuple{A,A})
  local out = inp:index(0)+(inp:index(1)*inp:index(1))
--  out = out:disablePipelining()
  --  out = out:cast(A)
  if async==true then out = out:disablePipelining() end
  return out:toRigelModule("fixedSumPow2")
                   end)

local fixedDiv = J.memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("II",types.tuple{A,A})
  local out = (inp:index(0))/(inp:index(1))
--  out = out:disablePipelining()
  --  out = out:cast(A)
  if A:isFloat() then out = out:disablePipelining() end
  return out:toRigelModule("fixedDiv")
                   end)

local fixedSqrt = J.memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("II",A)
  local out = inp:sqrt()
--  out = out:disablePipelining()
  --  out = out:cast(A)
  if A:isFloat() then out = out:disablePipelining() end
  return out:toRigelModule("fixedSqrt")
                   end)

----------------
local function calcGaussian(GAUSS_WIDTH_inp)
  assert(type(GAUSS_WIDTH_inp)=="number")

  local GAUSS_WIDTH = GAUSS_WIDTH_inp/2

  local G = {}
  local sum = 0

  for y=0,GAUSS_WIDTH-1 do
    for x=0,GAUSS_WIDTH-1 do
      local sigma = math.sqrt(5)
      local a = 1/(sigma*math.sqrt(2*3.141526))
      local X  = x-3.5
      local Y  = y-3.5
      local dist = math.sqrt(X*X+Y*Y)
      G[y*GAUSS_WIDTH+x] = a * math.exp(-(dist*dist)/(2*sigma*sigma))
      sum = sum + G[y*GAUSS_WIDTH+x]
    end
  end

  -- normalize
  for y=0,GAUSS_WIDTH-1 do
    for x=0,GAUSS_WIDTH-1 do
      G[y*GAUSS_WIDTH+x] = G[y*GAUSS_WIDTH+x]/sum
    end
  end

  -- dup
  local GG = {}

  for y=0,GAUSS_WIDTH_inp-1 do
    for x=0,GAUSS_WIDTH_inp-1 do
      local xx = math.floor(x/2)
      local yy = math.floor(y/2)
      GG[y*GAUSS_WIDTH_inp+x] = G[yy*GAUSS_WIDTH+xx]
    end
  end

  return GG
end

-- T: tile size
local function tileGaussian(G,W,T)
  assert(type(G)=="table")
  assert(type(W)=="number")
  assert(type(T)=="number")

  local GG = {}
  for ty=0,(W/T)-1 do
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
----------------
local function siftBucket(dxdyType,magtype)
  local inp = f.parameter("bucketinp",types.tuple{dxdyType,dxdyType,magtype})
  local dx = inp:index(0)
  local dy = inp:index(1)
  local mag = inp:index(2)

  local zero = f.constant(0)
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

  if dxdyType:isFloat() then out = out:disablePipelining() end
  return out:toRigelModule("siftBucket")
end
----------------
-- input {dx,dy,gaussweight}
local function siftMag(dxdyType)
  local inp = f.parameter("siftMagInp",types.tuple{dxdyType,dxdyType,dxdyType})
  local dx = inp:index(0)
  local dy = inp:index(1)
  local gauss_weight = inp:index(2)
  local magsq = (dx*dx)+(dy*dy)
  local mag = magsq:sqrt()

  local out = mag*gauss_weight
  if dxdyType:isFloat() then out = out:disablePipelining() end
  return out:toRigelModule("siftmag"), out.type
end
----------------
-- input: {dx,dy}
-- output: descType[BUCKETS], descType
local function siftDescriptor(dxdyType)
  local GAUSS = calcGaussian(16)
  GAUSS = tileGaussian(GAUSS,16,4)

  local ITYPE = types.tuple{dxdyType,dxdyType}
  local inp = R.input(types.rv(types.Par(ITYPE)))
  local gweight = R.apply("gweight",RM.constSeq(GAUSS,dxdyType,16*16,1,256), G.ValueToTrigger(inp))
  local gweight = R.apply("gwidx",C.index(types.array2d(dxdyType,1),0,0),gweight)
  local dx = R.apply("i0", C.index(ITYPE,0), inp)
  local dy = R.apply("i1", C.index(ITYPE,1), inp)
  local maginp = R.concat("maginp",{dx,dy,gweight})
  local magFn, magType = siftMag(dxdyType)
  local mag = R.apply("mag",magFn,maginp)
  local bucketInp = R.concat("bktinp",{dx,dy,mag})
  local out = R.apply( "out", siftBucket(dxdyType,magType), bucketInp)
  return RM.lambda("siftDescriptor",inp,out), magType
end
----------------
-- input: {descType[N],descType[N]}
-- output: descType[N]
local function bucketReduce(descType,N,X)
  assert(types.isType(descType))
  assert(type(N)=="number")
  assert(X==nil)

  local descArray = types.array2d(descType,N)
  local inp = R.input(types.rv(types.Par(types.tuple{descArray,descArray})))
  local out = R.apply("SOA",C.SoAtoAoS(N,1,{descType,descType}),inp)
  local out = R.apply("MP",RM.map(fixedSum(descType,true),N),out)
  return RM.lambda("bucketReduce",inp,out)
end
----------------
-- input: A[TILE_W*TILES_X,TILE_H*TILES_Y]
-- output: A[TILE_W*TILE_H][TILES_X,TILES_Y]
local function tile( TILE_W, TILE_H, TILES_X, TILES_Y, A, X )
  assert(type(TILE_W)=="number")
  assert(type(TILE_H)=="number")
  assert(type(TILES_X)=="number")
  assert(type(TILES_Y)=="number")

  local W,H = TILE_W*TILES_X, TILE_H*TILES_Y

  local ITYPE = types.array2d( A, W, H )
  local inp = R.input(types.rv(types.Par(ITYPE)))

  local tab = {}
  for y=0,H-1 do
    tab[y] = {}
    for x=0,W-1 do
      tab[y][x] = R.apply("idx_"..y.."_"..x, C.index( ITYPE, x, y ), inp)
    end
  end

  local outarr = {}
  for ty=0,TILES_Y-1 do
    for tx=0,TILES_X-1 do
      local out = {}
      for y=0,TILE_H-1 do
        for x=0,TILE_W-1 do
          table.insert(out, tab[ty*TILE_H+y][tx*TILE_W+x])
        end
      end
      table.insert(outarr, R.concatArray2d( "AR_"..ty.."_"..tx, out, TILE_W*TILE_H ) )
    end
  end

  local fin = R.concatArray2d( "fin", outarr, TILES_X*TILES_Y )

  return RM.lambda("tile", inp, fin )
end
----------------
-- input: {descType[128],uint16,uint16}
-- output: descType[130]
local function addDescriptorPos( descType, TILES_X, TILES_Y, X )
  local inp = f.parameter("descpos",types.tuple{types.array2d(descType,TILES_X*TILES_Y*8),types.uint(16),types.uint(16)})
  local desc = inp:index(0)
  local px = inp:index(1):lift(0)
  local py = inp:index(2):lift(0)
  
  local a = {px,py}
  for i=0,TILES_X*TILES_Y*8-1 do table.insert(a,desc:index(i)) end
  local out = f.array2d(a,2+8*TILES_X*TILES_Y)
  if descType:isFloat() then out = out:disablePipelining() end
  return out:toRigelModule("addDescriptorPos")
end

----------------
-- input: {{dx,dy}[16,16],{posX,posY}}
-- output: descType[128+2], descType
local function siftKernel( dxdyType, TILES_X, TILES_Y, TILE_W, TILE_H, X )
  assert( type(TILES_X)=="number" )
  assert( type(TILES_Y)=="number" )
  assert( type(TILE_W)=="number" )
  assert( type(TILE_H)=="number" )
  assert( X==nil )
  
  local dxdyPair = types.tuple{dxdyType,dxdyType}
  local posType = types.uint(16)
  local PTYPE = types.tuple{posType,posType}
  local ITYPE = types.tuple{types.array2d( dxdyPair, TILE_W*TILES_X, TILE_H*TILES_Y ),PTYPE}

  local fifos = {}
  local statements = {}

  local inp = R.input(R.Handshake(ITYPE))
  local inpt = inp
  
  local inp_broad = R.apply("inp_broad", RM.broadcastStream(types.Par(ITYPE),2), inpt)


  local inp_pos = C.fifo(ITYPE,1,nil,true)(R.selectStream("i0",inp_broad,0))
  local pos = R.apply("p",RM.makeHandshake(C.index(ITYPE,1)), inp_pos)

  local pos = C.fifo(PTYPE,1024)(pos)
  local posL, posR = RS.fanOut{input=pos,branches=2}

  local posX = R.apply("px",RM.makeHandshake(C.index(PTYPE,0)),posL)

  local posX = C.fifo(posType,1024)(posX)
  local posY = R.apply("py",RM.makeHandshake(C.index(PTYPE,1)),posR)

  local posY = C.fifo(posType,1024)(posY)

  local inp_dxdy = C.fifo(ITYPE,1,nil,true)(R.selectStream("i1",inp_broad,1))
  local dxdy = R.apply("dxdy",RM.makeHandshake(C.index(ITYPE,0,0)), inp_dxdy)
  local dxdyTile = R.apply("TLE",RM.makeHandshake(tile( TILE_W, TILE_H, TILES_X, TILES_Y, dxdyPair )),dxdy)
  local dxdy = R.apply( "down1", RM.changeRate(types.array2d(dxdyPair,TILE_W*TILE_H),1,TILES_X*TILES_Y,1), dxdyTile )
  
  local dxdy = R.apply("down1idx",RM.makeHandshake(C.index(types.array2d(types.array2d(dxdyPair,TILE_W*TILE_H),1),0,0)), dxdy)
  local dxdy = R.apply("down2", RM.changeRate(dxdyPair,1,TILE_W*TILE_H,1), dxdy )
  local dxdy = R.apply("down2idx",RM.makeHandshake(C.index(types.array2d(dxdyPair,1),0,0)), dxdy)
  local descFn, descType = siftDescriptor(dxdyType)

  local desc = R.apply("desc",RM.makeHandshake(descFn),dxdy)
  
  local desc = R.apply("rseq",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(bucketReduce(descType,8),TILE_W*TILE_H))),desc)

  -- it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
  -- We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
  -- that reduceSeq only has an output every 16 cycles, so it can't overlap them)

  local desc = C.fifo(types.array2d(descType,8),1,nil,true)(desc)

  local desc = R.apply("up", RM.changeRate(descType,1,8,1), desc )
  local desc = R.apply("upidx",RM.makeHandshake(C.index(types.array2d(descType,1),0,0)), desc)

  -- sum and normalize the descriptors
  local desc_broad = R.apply("desc_broad", RM.broadcastStream(types.Par(descType),2), desc)

  local desc0 = R.selectStream("d0",desc_broad,0)
  --local desc0 = C.fifoLoop( fifos, statements, descType, desc0, 256, "d0")
  local desc0 = C.fifo(descType,256)(desc0)

  local desc1 = R.selectStream("d1",desc_broad,1)
  --local desc1 = C.fifoLoop( fifos, statements, descType, desc1, 256, "d1")
  local desc1 = C.fifo(descType,256)(desc1)

  local desc_sum = R.apply("sum",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(fixedSumPow2(descType,true), 8*TILES_X*TILES_Y ))),desc1)
  local desc_sum = R.apply("sumsqrt",RM.makeHandshake(fixedSqrt(descType)), desc_sum)
  local desc_sum = R.apply("DAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc_sum)
  
  local desc_sum = R.apply("sumup",RM.upsampleXSeq( descType, 1, 8*TILES_X*TILES_Y), desc_sum)
  local desc_sum = R.apply("Didx",RM.makeHandshake(C.index(types.array2d(descType,1),0,0)), desc_sum)

  local desc = R.apply("pt",RM.packTuple{types.RV(types.Par(descType)),types.RV(types.Par(descType))},R.concat("PTT",{desc0,desc_sum}))
  local desc = R.apply("ptt",RM.makeHandshake(fixedDiv(descType)),desc)
  local desc = R.apply("DdAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc)

  local desc = R.apply("repack", RM.changeRate( descType, 1, 1, 8*TILES_X*TILES_Y ),desc)

  -- we now have an array of type descType[128]. Add the pos.
  local desc_pack = R.apply("dp", RM.packTuple{types.RV(types.Par(types.array2d( descType, 8*TILES_X*TILES_Y ))),types.RV(types.Par(posType)),types.RV(types.Par(posType))},R.concat("DPT",{desc,posX,posY}))
  local desc = R.apply("addpos",RM.makeHandshake(addDescriptorPos( descType, TILES_X, TILES_Y )), desc_pack)

  table.insert(statements,1,desc)

  local siftfn = RM.lambda("siftd",inp,R.statements(statements),fifos)
  
  return siftfn, descType
end

----------------
function posSub(x,y)
  local A = types.uint(16)
  local ITYPE = types.tuple {A,A}

  local ps = RM.lift("possub", types.tuple{A,A}, types.tuple{A,A},0,
    function(sinp) return sinp end, function() return siftCoreHWTerra.posSub(ITYPE,x,y) end )

  return ps
end
----------------
-- This fn takes in dxdy (tuple pair), turns it into a stencil of size windowXwindow, performs harris on it,
-- then returns type {dxdyStencil,bool}, where bool is set by harris NMS.
local function makeHarrisWithDXDY(dxdyType, W,H, window)
  print("makeHarrisWithDXDY",dxdyType)
  assert(window==16)

  local function res(internalW, internalH)
    local ITYPE = types.array2d(types.tuple{dxdyType,dxdyType},window,window)
    
    local inp = R.input(types.rv(types.Par(ITYPE)))
    
    local PS = RM.posSeq(internalW,internalH,1)
    local pos = R.apply("posseq", PS, G.ValueToTrigger(inp))
    local pos = R.apply("pidx",C.index(types.array2d(types.tuple{types.uint(16),types.uint(16)},1),0,0),pos)
    local pos = R.apply("PS", posSub(15,15), pos)
    
    local filterseqValue = R.concat("fsv",{inp,pos})
    
    local filterseqCond = R.apply("idx",C.index(ITYPE,8,8),inp)

    filterseqCond = G.TupleToArray(filterseqCond)
    filterseqCond = G.Map{G.FloatRec{32}}(filterseqCond)
    filterseqCond = G.ArrayToTuple(filterseqCond)
  
    filterseqCond = harris.HarrisKernel(filterseqCond)

    filterseqCond = G.Float(filterseqCond)

    local harrisType = types.Float32
    local filterseqCond = R.apply("AO",C.arrayop(harrisType,1,1),filterseqCond)
    -- now stencilify the harris
    local filterseqCond = R.apply( "harris_st", C.stencilLinebuffer(harrisType,internalW,internalH,1,-2,0,-2,0), filterseqCond)

    filterseqCond = G.Map{G.FloatRec{32}}(filterseqCond)
    filterseqCond = harris.NMS(filterseqCond)
    
    local fsinp = R.concat("PTT",{filterseqValue,filterseqCond})
    
    local filterfn = RM.lambda( "filterfn", inp, fsinp )
    
    return filterfn
  end

  return res
end
----------------

local function descInner( dxdyType, W, H, TILES_X, TILES_Y, TILE_W, TILE_H )
  assert(types.isType(dxdyType))
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(TILE_W)=="number")
  assert(type(TILE_H)=="number")

  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  local inp = R.input(types.rv(types.Par(types.array2d(DXDY_PAIR,1))))

  local out = R.apply("ST",C.stencilLinebuffer( DXDY_PAIR, W, H, 1, -TILE_W*TILES_X+1, 0, -TILE_H*TILES_Y+1, 0 ), inp)

  local PS = RM.posSeq( W, H, 1 )
  local pos = R.apply("posseq", PS, G.ValueToTrigger(inp) )
  local pos = R.apply("pidx",C.index(types.array2d(types.tuple{types.uint(16),types.uint(16)},1),0,0),pos)
  
  local out = R.concat("FO",{out,pos})
  return RM.lambda("descinner",inp,out)
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
  local out = R.apply( "dxdy", dxdyFn, inp )
  
  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  local DXDY_ST = types.array2d( DXDY_PAIR, TILES_X*4, TILES_Y*4 )
  --- now stencilify dxdy

  out = G.Map{G.TupleToArray}(out)
  out = G.Map{G.Map{G.Float}}(out)
  out = G.Map{G.ArrayToTuple}(out)
  
  local DI = descInner( dxdyType, W, H, TILES_X, TILES_Y, 4, 4 )
  local out = R.apply("desc_inner",RM.makeHandshake(DI),out)
  local out = R.apply("AO", RM.makeHandshake(C.arrayop(DI.outputType:extractData(),1,1)), out)
  local out = R.apply("CRP", RM.liftHandshake(RM.liftDecimate(RM.cropSeq( DI.outputType:extractData(), W, H, 1, 15, 0, 15, 0))), out)
  local out = R.apply("I0", RM.makeHandshake(C.index(types.array2d(DI.outputType:extractData(),1),0,0)), out)

  local siftFn, descType = siftKernel( dxdyType, TILES_X, TILES_Y, 4, 4 )
  local out = R.apply("sft", siftFn, out)

  local out = R.apply("incrate", RM.changeRate(descType,1,2+8*TILES_Y*TILES_X,2), out )

  local fn = RM.lambda( "harris", inpraw, out)
  return fn, descType
end

function sift.siftTop( W, H, T, FILTER_RATE, FILTER_FIFO, TILES_X, TILES_Y, X )
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
  local out = R.apply("dxdy",dxdyFn,inp)
  
  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  local DXDY_ST = types.array2d(DXDY_PAIR,16,16)
  --- now stencilify dxdy
  local T = 1
  
  local harrisFn = makeHarrisWithDXDY(dxdyType, W,H, 16)

  out = G.Map{G.TupleToArray}(out)
  out = G.Map{G.Map{G.Float}}(out)
  out = G.Map{G.ArrayToTuple}(out)

    
  print("OYTT",out.type)
  local out = R.apply("st",C.stencilKernelPadcropUnpure(DXDY_PAIR,W,H,T,7,8,7,8,{0,0},harrisFn,false),out)

  local FILTER_TYPE = types.tuple{types.array2d(DXDY_PAIR,16,16),types.tuple{types.uint(16),types.uint(16)}}
  local out = R.apply("stidx",RM.makeHandshake(C.index(types.array2d(types.tuple{FILTER_TYPE,types.bool()},1),0,0)), out)

  local filterFn = RM.filterSeq(FILTER_TYPE,W,H,{1,FILTER_RATE},FILTER_FIFO)

  local out = R.apply("FS",RM.liftHandshake(RM.liftDecimate(filterFn)),out)

  out = C.fifo(FILTER_TYPE,FILTER_FIFO,nil,true)(out)

  local siftFn, descType = siftKernel( dxdyType, TILES_X, TILES_Y, 4, 4 )
  local out = R.apply("sft", siftFn, out)

  local out = R.apply("incrate", RM.changeRate(descType,1,130,2), out )

  table.insert( statements, 1, out )
  local fn = RM.lambda( "harris", inpraw, R.statements(statements), fifos )

  return fn, descType
end

return sift
