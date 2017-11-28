local R = require "rigel"
local RS = require "rigelSimple"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local harris = require "harris_core"
local C = require "examplescommon"
local f = require "fixed_float"
local SDFRate = require "sdfrate"
f.DISABLE_SYNTH=true
local J = require "common"

local siftCoreHWTerra
if terralib~=nil then siftCoreHWTerra=require("sift_core_hw_terra") end

sift = {}

local fixedSum = J.memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("II",types.tuple{A,A})
  local out = inp:index(0)+inp:index(1)
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toRigelModule("fixedSum")
                   end)

local fixedSumPow2 = J.memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("II",types.tuple{A,A})
  local out = inp:index(0)+(inp:index(1)*inp:index(1))
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toRigelModule("fixedSumPow2")
                   end)

local fixedDiv = J.memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("II",types.tuple{A,A})
  local out = (inp:index(0))/(inp:index(1))
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toRigelModule("fixedDiv")
                   end)

local fixedSqrt = J.memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("II",A)
  local out = inp:sqrt()
--  out = out:disablePipelining()
--  out = out:cast(A)
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
  return out:toRigelModule("siftmag"), out.type
end
----------------
-- input: {dx,dy}
-- output: descType[BUCKETS], descType
local function siftDescriptor(dxdyType)
  local G = calcGaussian(16)
  G = tileGaussian(G,16,4)

  local ITYPE = types.tuple{dxdyType,dxdyType}
  local inp = R.input(ITYPE)
  local gweight = R.apply("gweight",RM.constSeq(G,dxdyType,16*16,1,1/256))
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
  local inp = R.input(types.tuple{descArray,descArray})
  local out = R.apply("SOA",C.SoAtoAoS(N,1,{descType,descType}),inp)
  local out = R.apply("MP",RM.map(fixedSum(descType),N),out)
  return RM.lambda("bucketReduce",inp,out)
end
----------------
-- input: A[W,H]
-- output: A[(W/T)*(H/T)][T*T]
local function tile(W,H,T,A)
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(T)=="number")
  assert(W%T==0)
  assert(H%T==0)

  local ITYPE = types.array2d(A,W,H)
  local inp = R.input(ITYPE)

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
local function addDescriptorPos(descType)
  local inp = f.parameter("descpos",types.tuple{types.array2d(descType,128),types.uint(16),types.uint(16)})
  local desc = inp:index(0)
  local px = inp:index(1):lift(0)
  local py = inp:index(2):lift(0)
  
  local a = {px,py}
  for i=0,127 do table.insert(a,desc:index(i)) end
  local out = f.array2d(a,130)
  return out:toRigelModule("addDescriptorPos")
end
----------------
-- input: {{dx,dy}[16,16],{posX,posY}}
-- output: descType[128+2], descType
local function siftKernel(dxdyType)
  --print("sift")

  local dxdyPair = types.tuple{dxdyType,dxdyType}
  local posType = types.uint(16)
  local PTYPE = types.tuple{posType,posType}
  local ITYPE = types.tuple{types.array2d(dxdyPair,16,16),PTYPE}

  local fifos = {}
  local statements = {}

  local inp = R.input(R.Handshake(ITYPE))
  local inp_broad = R.apply("inp_broad", RM.broadcastStream(ITYPE,2), inp)

  local inp_pos = C.fifoLoop( fifos, statements, ITYPE, R.selectStream("i0",inp_broad,0), 1, "p0", true)
  local pos = R.apply("p",RM.makeHandshake(C.index(ITYPE,1)), inp_pos)
  local pos = C.fifoLoop( fifos, statements, PTYPE, pos, 1024, "posfifo")
  local posL, posR = RS.fanOut{input=pos,branches=2}
--  local pos = C.fifo( fifos, statements, PTYPE, pos, 1024, "p0")
  local posX = R.apply("px",RM.makeHandshake(C.index(PTYPE,0)),posL)
  local posX = C.fifoLoop( fifos, statements, posType, posX, 1024, "pxfifo" )
  local posY = R.apply("py",RM.makeHandshake(C.index(PTYPE,1)),posR)
  local posY = C.fifoLoop( fifos, statements, posType, posY, 1024, "pyfifo" )

  local inp_dxdy = C.fifoLoop( fifos, statements, ITYPE, R.selectStream("i1",inp_broad,1), 1, "p1", true)
  local dxdy = R.apply("dxdy",RM.makeHandshake(C.index(ITYPE,0,0)), inp_dxdy)
  local dxdyTile = R.apply("TLE",RM.makeHandshake(tile(16,16,4,dxdyPair)),dxdy)
  local dxdy = R.apply( "down1", RM.liftHandshake(RM.changeRate(types.array2d(dxdyPair,16),1,16,1)), dxdyTile )
  local dxdy = R.apply("down1idx",RM.makeHandshake(C.index(types.array2d(types.array2d(dxdyPair,16),1),0,0)), dxdy)
  local dxdy = R.apply("down2", RM.liftHandshake(RM.changeRate(dxdyPair,1,16,1)), dxdy )
  local dxdy = R.apply("down2idx",RM.makeHandshake(C.index(types.array2d(dxdyPair,1),0,0)), dxdy)
  local descFn, descType = siftDescriptor(dxdyType)
  local desc = R.apply("desc",RM.makeHandshake(descFn),dxdy)

  local desc = R.apply("rseq",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(bucketReduce(descType,8),1/16)),"BUCKET"),desc)

  -- it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
  -- We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
  -- that reduceSeq only has an output every 16 cycles, so it can't overlap them)
  local desc = C.fifoLoop(fifos,statements,types.array2d(descType,8),desc,1,"lol",true)

  local desc = R.apply("up",RM.liftHandshake(RM.changeRate(descType,1,8,1),"CR"),desc)
  local desc = R.apply("upidx",RM.makeHandshake(C.index(types.array2d(descType,1),0,0)), desc)

  -- sum and normalize the descriptors
  local desc_broad = R.apply("desc_broad", RM.broadcastStream(descType,2), desc)

  local desc0 = R.selectStream("d0",desc_broad,0)
  local desc0 = C.fifoLoop( fifos, statements, descType, desc0, 256, "d0")

  local desc1 = R.selectStream("d1",desc_broad,1)
  local desc1 = C.fifoLoop( fifos, statements, descType, desc1, 256, "d1")

  local desc_sum = R.apply("sum",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(fixedSumPow2(descType),1/128))),desc1)
  local desc_sum = R.apply("sumsqrt",RM.makeHandshake(fixedSqrt(descType)), desc_sum)
  local desc_sum = R.apply("DAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc_sum)
  local desc_sum = R.apply("sumup",RM.upsampleXSeq( descType, 1, 128), desc_sum)
  local desc_sum = R.apply("Didx",RM.makeHandshake(C.index(types.array2d(descType,1),0,0)), desc_sum)

  local desc = R.apply("pt",RM.packTuple{descType,descType},R.concat("PTT",{desc0,desc_sum}))
  local desc = R.apply("ptt",RM.makeHandshake(fixedDiv(descType)),desc)
  local desc = R.apply("DdAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc)

  local desc = R.apply("repack",RM.liftHandshake(RM.changeRate(descType,1,1,128)),desc)
  -- we now have an array of type descType[128]. Add the pos.
  local desc_pack = R.apply("dp", RM.packTuple{types.array2d(descType,128),posType,posType},R.concat("DPT",{desc,posX,posY}))
  local desc = R.apply("addpos",RM.makeHandshake(addDescriptorPos(descType)), desc_pack)

  table.insert(statements,1,desc)

  local siftfn = RM.lambda("siftd",inp,R.statements(statements),fifos)
  
  --print("SIFTSDF",SDFRate.fracToNumber(siftfn.sdfInput[1]),SDFRate.fracToNumber(siftfn.sdfOutput[1]))
  return siftfn, descType
end

----------------
function posSub(x,y)
  local A = types.uint(16)
  local ITYPE = types.tuple {A,A}

  local ps = RM.lift("possub", types.tuple{A,A}, types.tuple{A,A},1,
    function(sinp) return sinp end, function() return siftCoreHWTerra.posSub(ITYPE,x,y) end )

  return ps
end
----------------
-- This fn takes in dxdy (tuple pair), turns it into a stencil of size windowXwindow, performs harris on it,
-- then returns type {dxdyStencil,bool}, where bool is set by harris NMS.
local function makeHarrisWithDXDY(dxdyType, W,H, window)
  --print("makeHarrisWithDXDY")
  assert(window==16)

  local function res(internalW, internalH)
    --print("MAKE HARRIS",internalW, internalH)

    local ITYPE = types.array2d(types.tuple{dxdyType,dxdyType},window,window)
    
    local inp = R.input(ITYPE)
    
    local PS = RM.posSeq(internalW,internalH,1)
    local pos = R.apply("posseq", PS)
    local pos = R.apply("pidx",C.index(types.array2d(types.tuple{types.uint(16),types.uint(16)},1),0,0),pos)
    local pos = R.apply("PS", posSub(15,15), pos)
    
    local filterseqValue = R.concat("fsv",{inp,pos})
    
    local filterseqCond = R.apply("idx",C.index(ITYPE,8,8),inp)
    local harrisFn, harrisType = harris.makeHarrisKernel(dxdyType,dxdyType)
    local filterseqCond = R.apply("harris", harrisFn, filterseqCond)
    local filterseqCond = R.apply("AO",C.arrayop(harrisType,1,1),filterseqCond)
    -- now stencilify the harris
    local filterseqCond = R.apply( "harris_st", C.stencilLinebuffer(harrisType,internalW,internalH,1,-2,0,-2,0), filterseqCond)
    local nmsFn = harris.makeNMS( harrisType, true )
    local filterseqCond = R.apply("nms", nmsFn, filterseqCond)
    
    local fsinp = R.concat("PTT",{filterseqValue,filterseqCond})
    
    local filterfn = RM.lambda( "filterfn", inp, fsinp )
    
    return filterfn
  end

  return res
end
----------------

local function descInner(dxdyType,W,H)
  assert(types.isType(dxdyType))
  assert(type(W)=="number")
  assert(type(H)=="number")

  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  local inp = R.input(types.array2d(DXDY_PAIR,1))

  local out = R.apply("ST",C.stencilLinebuffer(DXDY_PAIR,W,H,1,-15,0,-15,0), inp)

  local PS = RM.posSeq(W,H,1)
  local pos = R.apply("posseq", PS)
  local pos = R.apply("pidx",C.index(types.array2d(types.tuple{types.uint(16),types.uint(16)},1),0,0),pos)
  
  local out = R.concat("FO",{out,pos})
  return RM.lambda("descinner",inp,out)
end

function sift.siftDesc(W,H,inputT,X)
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(inputT)=="number")
  assert(X==nil)

  local ITYPE = types.array2d(types.uint(8),inputT)
  
  local inpraw = R.input(R.Handshake(ITYPE))
  local inp = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,1)), inpraw )
  local dxdyFn, dxdyType = harris.makeDXDY(W,H)
  local out = R.apply("dxdy",dxdyFn,inp)
  
  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  local DXDY_ST = types.array2d(DXDY_PAIR,16,16)
  --- now stencilify dxdy

  local DI = descInner(dxdyType,W,H)
  local out = R.apply("desc_inner",RM.makeHandshake(DI),out)
  local out = R.apply("AO", RM.makeHandshake(C.arrayop(DI.outputType,1,1)), out)
  local out = R.apply("CRP", RM.liftHandshake(RM.liftDecimate(RM.cropSeq( DI.outputType, W, H, 1, 15, 0, 15, 0))), out)
  local out = R.apply("I0", RM.makeHandshake(C.index(types.array2d(DI.outputType,1),0,0)), out)

  local siftFn, descType = siftKernel(dxdyType)
  local out = R.apply("sft", siftFn, out)

  local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(descType,1,130,2)), out )

  local fn = RM.lambda( "harris", inpraw, out)
  return fn, descType
end

function sift.siftTop(W,H,T,FILTER_RATE,FILTER_FIFO,X)
  assert(type(FILTER_FIFO)=="number")
  assert(X==nil)

  local fifos = {}
  local statements = {}

  local ITYPE = types.array2d(types.uint(8),T)
  
  local inpraw = R.input(R.Handshake(ITYPE))
  local inp = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,1)), inpraw )
  local dxdyFn, dxdyType = harris.makeDXDY(W,H)
  local out = R.apply("dxdy",dxdyFn,inp)
  
  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  local DXDY_ST = types.array2d(DXDY_PAIR,16,16)
  --- now stencilify dxdy
  local T = 1
  
  local harrisFn = makeHarrisWithDXDY(dxdyType, W,H, 16)

  local out = R.apply("st",C.stencilKernelPadcropUnpure(DXDY_PAIR,W,H,T,7,8,7,8,{0,0},harrisFn,false),out)

  local FILTER_TYPE = types.tuple{types.array2d(DXDY_PAIR,16,16),types.tuple{types.uint(16),types.uint(16)}}
  local out = R.apply("stidx",RM.makeHandshake(C.index(types.array2d(types.tuple{FILTER_TYPE,types.bool()},1),0,0)), out)

  local filterFn = RM.filterSeq(FILTER_TYPE,W,H,{1,FILTER_RATE},FILTER_FIFO)

  local out = R.apply("FS",RM.liftHandshake(RM.liftDecimate(filterFn)),out)
  local out = C.fifoLoop( fifos, statements, FILTER_TYPE, out, FILTER_FIFO, "fsfifo", true)

  local siftFn, descType = siftKernel(dxdyType)
  local out = R.apply("sft", siftFn, out)

  local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(descType,1,130,2)), out )

  table.insert( statements, 1, out )
  local fn = RM.lambda( "harris", inpraw, R.statements(statements), fifos )

  return fn, descType
end

return sift
