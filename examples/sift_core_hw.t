local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"
local harris = require "harris_core"
local C = require "examplescommon"
local f = require "fixed_float"
--f.DISABLE_SYNTH=true


TILES_X = 4
TILES_Y = 4
GAUSS_SIGMA = 5 --5


RED_TYPE = types.int(32)
RED_SCALE = 1024/GRAD_SCALE -- 1024

sift = {}

local fixedSum = memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("II",types.tuple{A,A})
  local out = inp:index(0)+inp:index(1)
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toDarkroom("fixedSum")
                   end)

local fixedSumPow2 = memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("II",types.tuple{A,A})
  local out = inp:index(0)+(inp:index(1)*inp:index(1))
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toDarkroom("fixedSumPow2")
                   end)

local sumPow2 = function(A,B,outputType)
  local sinp = S.parameter( "inp", types.tuple {A,B} )

  local sout = S.cast(S.index(sinp,0),outputType)+(S.cast(S.index(sinp,1),outputType)*S.cast(S.index(sinp,1),outputType))
  sout = sout:disablePipelining()
  local partial = d.lift( "sumpow2", types.tuple {A,B}, outputType, 0,
                          terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](a._0)+([outputType:toTerraType()](a._1)*[outputType:toTerraType()](a._1))
                  end, sinp, sout )
  return partial
                end

local fixedDiv = memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("II",types.tuple{A,A})
  local out = (inp:index(0))*(inp:index(1):invert())
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toDarkroom("fixedDiv")
                   end)

local fixedSqrt = memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("II",A)
  local out = inp:sqrt()
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toDarkroom("fixedSqrt")
                   end)

local fixedLift = memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("IIlift",A)
  local out = inp:lift()
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toDarkroom("fixedLift_"..tostring(A):gsub('%W','_'))
                   end)

local lowerPair = memoize(function(FROM,TO,scale)
  assert(types.isType(FROM))
  assert(types.isType(TO))
  local inp = f.parameter("IIlift",types.tuple{FROM,FROM})
  local out = f.tuple{(inp:index(0)*f.constant(scale)):lower(TO),(inp:index(1)*f.constant(scale)):lower(TO)}
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toDarkroom("lowerpair")
                   end)

----------------
local function calcGaussian(sig,GAUSS_WIDTH_inp,GAUSS_HEIGHT_inp)
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
      print("GAUSS X",x,"Y",y,"Value",G[y*GAUSS_WIDTH+x])
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

-- T: tile size
local function tileGaussian(G,W,H,T)
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
----------------
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
  return out:toDarkroom("siftBucket")
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
  return out:toDarkroom("siftmag"), out.type
end
----------------
-- input: {dx,dy}
-- output: descType[BUCKETS], descType
local function siftDescriptor(dxdyType)
  if GRAD_INT then
    assert(dxdyType==GRAD_TYPE)
  else
    assert(dxdyType==types.float(32))
  end

  local G = calcGaussian(GAUSS_SIGMA,TILES_X*4,TILES_Y*4) -- sigma was 5
  G = tileGaussian(G,TILES_X*4,TILES_Y*4,4)

  local calcType = types.float(32)

  local ITYPE = types.tuple{dxdyType,dxdyType}
  local inp = d.input(ITYPE)
  local gweight = d.apply("gweight",d.constSeq(G,calcType,TILES_X*TILES_Y*16,1,1/(TILES_X*TILES_Y*16)))
  local gweight = d.apply("gwidx",d.index(types.array2d(calcType,1),0,0),gweight)
  local dx = d.apply("i0", d.index(ITYPE,0), inp)
  local dy = d.apply("i1", d.index(ITYPE,1), inp)

  if GRAD_INT then
    dx = d.apply("ixl",fixedLift(dxdyType),dx)
    dy = d.apply("iyl",fixedLift(dxdyType),dy)
  end

  local maginp = d.tuple("maginp",{dx,dy,gweight})
  local magFn, magType = siftMag(calcType)
  local mag = d.apply("mag",magFn,maginp)
  local bucketInp = d.tuple("bktinp",{dx,dy,mag})
  local out = d.apply( "out", siftBucket(calcType,magType), bucketInp)
  return d.lambda("siftDescriptor",inp,out), RED_TYPE
end
----------------
-- input: {descType[N],descType[N]}
-- output: descType[N]
local function bucketReduce(descType,N,X)
  assert(types.isType(descType))
  assert(type(N)=="number")
  assert(X==nil)

  local descArray = types.array2d(descType,N)
  local inp = d.input(types.tuple{descArray,descArray})
  local out = d.apply("SOA",d.SoAtoAoS(N,1,{descType,descType}),inp)
  local out = d.apply("MP",d.map(C.sum(RED_TYPE,RED_TYPE,RED_TYPE,true),N),out)
  return d.lambda("bucketReduce",inp,out)
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
  local inp = d.input(ITYPE)

  local tab = {}
  for y=0,H-1 do
    tab[y] = {}
    for x=0,W-1 do
      tab[y][x] = d.apply("idx_"..y.."_"..x, d.index( ITYPE, x, y ), inp)
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
      table.insert(outarr, d.array2d("AR_"..ty.."_"..tx,out,T*T) )
    end
  end

  local fin = d.array2d("fin",outarr,(W/T)*(H/T))

  return d.lambda("tile", inp, fin )
end
----------------
-- input: {descType[128],uint16,uint16}
-- output: descType[130]
local function addDescriptorPos(descType)
  local inp = f.parameter("descpos",types.tuple{types.array2d(descType,TILES_X*TILES_Y*8),types.uint(16),types.uint(16)})
  local desc = inp:index(0)
  local px = inp:index(1):lift(0)
  local py = inp:index(2):lift(0)
  
  local a = {px,py}
  for i=0,(TILES_X*TILES_Y*8-1) do table.insert(a,desc:index(i)) end
  local out = f.array2d(a,TILES_X*TILES_Y*8+2)
  return out:toDarkroom("addDescriptorPos")
end
----------------
-- input: {{dx,dy}[16,16],{posX,posY}}
-- output: descType[128+2], descType
local function siftKernel(dxdyType)
  print("sift")

  local dxdyPair = types.tuple{dxdyType,dxdyType}
  local posType = types.uint(16)
  local PTYPE = types.tuple{posType,posType}
  local ITYPE = types.tuple{types.array2d(dxdyPair,TILES_X*4,TILES_Y*4),PTYPE}

  local fifos = {}
  local statements = {}

  local inp = d.input(d.Handshake(ITYPE))
  local inp_broad = d.apply("inp_broad", d.broadcastStream(ITYPE,2), inp)

  local inp_pos = C.fifo( fifos, statements, ITYPE, d.selectStream("i0",inp_broad,0), 1, "p0", true) -- fifo size can also be 1 (tested in SW)
  local pos = d.apply("p",d.makeHandshake(d.index(ITYPE,1)), inp_pos)
  local pos = C.fifo( fifos, statements, PTYPE, pos, 1024, "posfifo")

--  local pos = C.fifo( fifos, statements, PTYPE, pos, 1024, "p0")
  local posX = d.apply("px",d.makeHandshake(d.index(PTYPE,0)),pos)
  local posX = C.fifo( fifos, statements, posType, posX, 1024, "pxfifo" )
  local posY = d.apply("py",d.makeHandshake(d.index(PTYPE,1)),pos)
  local posY = C.fifo( fifos, statements, posType, posY, 1024, "pyfifo" )

  local inp_dxdy = C.fifo( fifos, statements, ITYPE, d.selectStream("i1",inp_broad,1), 1, "p1", true) -- fifo size can also be 1 (tested in SW)
  local dxdy = d.apply("dxdy",d.makeHandshake(d.index(ITYPE,0,0)), inp_dxdy)

--  if GRAD_INT then
--    dxdy = d.apply("dxdylower",d.makeHandshake(d.map(lowerPair(dxdyType,GRAD_TYPE,GRAD_SCALE),TILES_X*4,TILES_Y*4)), dxdy)
--    dxdyType = GRAD_TYPE
--    dxdyPair = types.tuple{GRAD_TYPE,GRAD_TYPE}
--  end

  local dxdyTile = d.apply("TLE",d.makeHandshake(tile(TILES_X*4,TILES_Y*4,4,dxdyPair)),dxdy)
  local dxdy = d.apply( "down1", d.liftHandshake(d.changeRate(types.array2d(dxdyPair,16),1,TILES_X*TILES_Y,1)), dxdyTile )
  local dxdy = d.apply("down1idx",d.makeHandshake(d.index(types.array2d(types.array2d(dxdyPair,16),1),0,0)), dxdy)
  local dxdy = d.apply("down2", d.liftHandshake(d.changeRate(dxdyPair,1,16,1)), dxdy )
  local dxdy = d.apply("down2idx",d.makeHandshake(d.index(types.array2d(dxdyPair,1),0,0)), dxdy)
  local descFn, descTypeRed = siftDescriptor(dxdyType)
  local descType = types.float(32)
  local desc = d.apply("desc",d.makeHandshake(descFn),dxdy)

  local desc = d.apply("rseq",d.liftHandshake(d.liftDecimate(d.reduceSeq(bucketReduce(descTypeRed,8),1/16)),"BUCKET"),desc)

  -- it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
  -- We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
  -- that reduceSeq only has an output every 16 cycles, so it can't overlap them)
  local desc = C.fifo(fifos,statements,types.array2d(descTypeRed,8),desc,128,"lol",false) -- fifo size can also be 1 (tested in SW)

  local desc = d.apply("up",d.liftHandshake(d.changeRate(descTypeRed,1,8,1),"CR"),desc)
  local desc = d.apply("upidx",d.makeHandshake(d.index(types.array2d(descTypeRed,1),0,0)), desc)

  -- sum and normalize the descriptors
  local desc_broad = d.apply("desc_broad", d.broadcastStream(descTypeRed,2), desc)

  local desc0 = d.selectStream("d0",desc_broad,0)
  local desc0 = C.fifo( fifos, statements, descTypeRed, desc0, 256, "d0")

  local desc1 = d.selectStream("d1",desc_broad,1)
  local desc1 = C.fifo( fifos, statements, descTypeRed, desc1, 256, "d1")

  local desc_sum = d.apply("sum",d.liftHandshake(d.liftDecimate(d.reduceSeq(sumPow2(RED_TYPE,RED_TYPE,RED_TYPE),1/(TILES_X*TILES_Y*8)))),desc1)
  local desc_sum = d.apply("sumlift",d.makeHandshake(fixedLift(RED_TYPE)), desc_sum)

  local desc_sum = d.apply("sumsqrt",d.makeHandshake(fixedSqrt(descType)), desc_sum)
  local desc_sum = d.apply("DAO",d.makeHandshake(C.arrayop(descType,1,1)), desc_sum)
  local desc_sum = d.apply("sumup",d.upsampleXSeq( descType, 1, TILES_X*TILES_Y*8), desc_sum)
  local desc_sum = d.apply("Didx",d.makeHandshake(d.index(types.array2d(descType,1),0,0)), desc_sum)

  local desc0 = d.apply("d0lift",d.makeHandshake(fixedLift(RED_TYPE)), desc0)
  local desc = d.apply("pt",d.packTuple{descType,descType},d.tuple("PTT",{desc0,desc_sum},false))
  local desc = d.apply("ptt",d.makeHandshake(fixedDiv(descType)),desc)
  local desc = d.apply("DdAO",d.makeHandshake(C.arrayop(descType,1,1)), desc)

  local desc = d.apply("repack",d.liftHandshake(d.changeRate(descType,1,1,TILES_X*TILES_Y*8)),desc)
  -- we now have an array of type descType[128]. Add the pos.
  local desc_pack = d.apply("dp", d.packTuple{types.array2d(descType,TILES_X*TILES_Y*8),posType,posType},d.tuple("DPT",{desc,posX,posY},false))
  local desc = d.apply("addpos",d.makeHandshake(addDescriptorPos(descType)), desc_pack)

  table.insert(statements,1,desc)

  local siftfn = d.lambda("siftd",inp,d.statements(statements),fifos)
  
  print("SIFTSDF",fracToNumber(siftfn.sdfInput[1]),fracToNumber(siftfn.sdfOutput[1]))
  return siftfn, descType
end

----------------
function posSub(x,y)
  local A = types.uint(16)
  local ITYPE = types.tuple {A,A}
  local sinp = S.parameter( "inp", ITYPE )
  local ps = d.lift("possub", types.tuple{A,A}, types.tuple{A,A},1,
                    terra( a : &ITYPE:toTerraType(), out:&ITYPE:toTerraType() )
                      var xo = a._0-x
                      var yo = a._1-y
                      @out = {xo,yo}
                    end, sinp, sinp)
  return ps
end
----------------
-- This fn takes in dxdy (tuple pair), turns it into a stencil of size windowXwindow, performs harris on it,
-- then returns type {dxdyStencil,bool}, where bool is set by harris NMS.
local function makeHarrisWithDXDY(dxdyType, W,H)
  print("makeHarrisWithDXDY")
  --assert(window==16)

  local function res(internalW, internalH)
    print("MAKE HARRIS",internalW, internalH)

    local ITYPE = types.array2d(types.tuple{dxdyType,dxdyType},TILES_X*4,TILES_Y*4)
    
    local inp = d.input(ITYPE)
    
    local PS = d.posSeq(internalW,internalH,1)
    local pos = d.apply("posseq", PS)
    local pos = d.apply("pidx",d.index(types.array2d(types.tuple{types.uint(16),types.uint(16)},1),0,0),pos)
    local pos = d.apply("PS", posSub(TILES_X*4-1,TILES_Y*4-1), pos)
    
    local filterseqValue = d.tuple("fsv",{inp,pos})
    
    local filterseqCond = d.apply("idx",d.index(ITYPE,TILES_X*2,TILES_Y*2),inp)
    local harrisFn, harrisType = harris.makeHarrisKernel(dxdyType,dxdyType)
    local filterseqCond = d.apply("harris", harrisFn, filterseqCond)
    local filterseqCond = d.apply("AO",C.arrayop(harrisType,1,1),filterseqCond)
    -- now stencilify the harris
    local filterseqCond = d.apply( "harris_st", d.stencilLinebuffer(harrisType,internalW,internalH,1,-2,0,-2,0), filterseqCond)
    local nmsFn = harris.makeNMS( harrisType, true )
    local filterseqCond = d.apply("nms", nmsFn, filterseqCond)
    
    local fsinp = d.tuple("PTT",{filterseqValue,filterseqCond})
    
    local filterfn = d.lambda( "filterfn", inp, fsinp )
    --  local filterfn = d.lambda( "filterfn", inp, filterseqCond )
    
    return filterfn
  end

  return res
end
----------------

local function addPos(dxdyType,W,H,subX,subY)
  assert(types.isType(dxdyType))
  assert(type(W)=="number")
  assert(type(H)=="number")

  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  local inp = d.input(types.array2d(DXDY_PAIR,TILES_X*4,TILES_Y*4))

  local PS = d.posSeq(W,H,1)
  local pos = d.apply("posseq", PS)
  local pos = d.apply("pidx", d.index(types.array2d(types.tuple{types.uint(16),types.uint(16)},1),0,0), pos )
  
  if subX~=nil then
    pos = d.apply("possub",posSub(subX,subY), pos)
  end

  local out = d.tuple("FO",{inp,pos})
  return d.lambda("addPosAtInput",inp,out)
end

function sift.siftDesc(W,H,inputT,X)
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(inputT)=="number")
  assert(X==nil)

  local ITYPE = types.array2d(types.uint(8),inputT)
  
  local inpraw = d.input(d.Handshake(ITYPE))
  local inp = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,1)), inpraw )
  local dxdyFn, dxdyType = harris.makeDXDY(W,H)
  local out = d.apply("dxdy",dxdyFn,inp)

  if GRAD_INT then
    out = d.apply("dxdy0", d.makeHandshake(d.index(types.array2d(types.tuple{dxdyType,dxdyType},1),0)), out)
    out = d.apply("dxdyint",d.makeHandshake(lowerPair(dxdyType,GRAD_TYPE,GRAD_SCALE)),out)
    out = d.apply("dxdyao", d.makeHandshake( C.arrayop( types.tuple{GRAD_TYPE,GRAD_TYPE}, 1, 1 ) ), out)
    dxdyType = GRAD_TYPE
    
  end

  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  local DXDY_ST = types.array2d(DXDY_PAIR,TILES_X*4,TILES_Y*4)

  --- now stencilify dxdy
--  local T = 1
  
  local out = d.apply("ST",d.makeHandshake(d.stencilLinebuffer(DXDY_PAIR,W,H,1,(-TILES_X*4)+1,0,(-TILES_Y*4)+1,0)), out)

  local DI = addPos(dxdyType,W,H)
  local out = d.apply("desc_inner",d.makeHandshake(DI),out)
  local out = d.apply("AO", d.makeHandshake(C.arrayop(DI.outputType,1,1)), out)
  local out = d.apply("CRP", d.liftHandshake(d.liftDecimate(d.cropSeq( DI.outputType, W, H, 1, TILES_X*4-1, 0, TILES_Y*4-1, 0))), out)
  local out = d.apply("I0", d.makeHandshake(d.index(types.array2d(DI.outputType,1),0,0)), out)

  local siftFn, descType = siftKernel(dxdyType)
  local out = d.apply("sft", siftFn, out)

--  local out = d.apply("AO", d.makeHandshake(C.arrayop(types.array2d(descType,130),1,1)), out)

--  local out = d.apply("I0", d.makeHandshake(d.index(types.array2d(types.array2d(descType,130),1),0,0)), out)
  --local out = d.apply("AO",d.makeHandshake(C.arrayop(types.array2d(types.uint(8),2),1,1)),out)
  local out = d.apply("incrate", d.liftHandshake(d.changeRate(descType,1,TILES_X*TILES_Y*8+2,2)), out )

--  table.insert( statements, 1, out )
--  local fn = d.lambda( "harris", inpraw, d.statements(statements), fifos )
  local fn = d.lambda( "harris", inpraw, out)
  return fn, descType
end

function sift.siftTop(W,H,T,FILTER_RATE,FILTER_FIFO,X)
  assert(type(FILTER_FIFO)=="number")
  assert(X==nil)

  local fifos = {}
  local statements = {}

  local ITYPE = types.array2d(types.uint(8),T)
  
  local inpraw = d.input(d.Handshake(ITYPE))
  local inp = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,1)), inpraw )
  local dxdyFn, dxdyType = harris.makeDXDY(W,H)
  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}

  local out = d.apply("dxdy",dxdyFn,inp)

  out = d.apply("pad", d.liftHandshake(d.padSeq(DXDY_PAIR, W, H, 1, 7, 8, 7, 8, {0,0})), out)

  out = d.apply("dxdyix",d.makeHandshake(d.index(types.array2d(DXDY_PAIR,1,1),0,0)),out)

  local dxdyBroad = d.apply("dxdy_broad", d.broadcastStream(DXDY_PAIR,2), out)

  local internalW = W+15
  local internalH = H+15

  -------------------------------
  -- right branch: make the harris bool
  local right = d.selectStream("d1",dxdyBroad,1)
  right = C.fifo( fifos, statements, DXDY_PAIR, right, 128, "rightFIFO")

  local harrisFn, harrisType = harris.makeHarrisKernel(dxdyType,dxdyType)
  local right = d.apply("harris", d.makeHandshake(harrisFn), right)
  local right = d.apply("AO",d.makeHandshake(C.arrayop(harrisType,1,1)), right)

  -- now stencilify the harris
  local right = d.apply( "harris_st", d.makeHandshake(d.stencilLinebuffer(harrisType, internalW, internalH, 1,-2,0,-2,0)), right)
  local nmsFn = harris.makeNMS( harrisType, true )
  local right = d.apply("nms", d.makeHandshake(nmsFn), right)

  -------------------------------
  -- left branch: make the dxdy int8 stencils
  local left = d.selectStream("d0",dxdyBroad,0)

  if GRAD_INT then
    print("GRAD_INT=true")
    left = d.apply("lower", d.makeHandshake(lowerPair(dxdyType,GRAD_TYPE,GRAD_SCALE)), left)
    dxdyType = GRAD_TYPE
    DXDY_PAIR = types.tuple{GRAD_TYPE,GRAD_TYPE}
  else
    print("GRAD_INT=false")
  end
  
  left = C.fifo( fifos, statements, DXDY_PAIR, left, 2048/DXDY_PAIR:verilogBits(), "leftFIFO")

  local left = d.apply("stlbinp", d.makeHandshake(C.arrayop(DXDY_PAIR,1,1)), left)
  local left = d.apply( "stlb", d.makeHandshake(d.stencilLinebuffer(DXDY_PAIR, internalW, internalH, 1,-TILES_X*4+1,0,-TILES_Y*4+1,0)), left)
  left = d.apply("stpos", d.makeHandshake(addPos(dxdyType,internalW,internalH,15+15,15+15)), left)
  -------------------------------


  local FILTER_TYPE = types.tuple{types.array2d(DXDY_PAIR,TILES_X*4,TILES_Y*4),types.tuple{types.uint(16),types.uint(16)}}
  local FILTER_PAIR = types.tuple{FILTER_TYPE,types.bool()}

  -- merge left/right
  local out = d.apply("merge",d.packTuple{FILTER_TYPE,types.bool()},d.tuple("MPT",{left,right},false))

  local out = d.apply("cropao", d.makeHandshake(C.arrayop(FILTER_PAIR,1,1)), out)
  local out = d.apply("crp", d.liftHandshake(d.liftDecimate(d.cropSeq(FILTER_PAIR,W+15,H+15,1,15,0,15,0))), out)
  local out = d.apply("crpidx", d.makeHandshake(d.index(types.array2d(FILTER_PAIR,1,1),0,0)), out)
  
  local filterFn = d.filterSeq(FILTER_TYPE,W,H,FILTER_RATE,FILTER_FIFO)

  local out = d.apply("FS",d.liftHandshake(d.liftDecimate(filterFn)),out)
  local out = C.fifo( fifos, statements, FILTER_TYPE, out, FILTER_FIFO, "fsfifo", true)

  local siftFn, descType = siftKernel(dxdyType)
  local out = d.apply("sft", siftFn, out)
  --local out = d.apply("AO",d.makeHandshake(C.arrayop(types.array2d(types.uint(8),2),1,1)),out)
  local out = d.apply("incrate", d.liftHandshake(d.changeRate(descType,1,TILES_X*TILES_Y*8+2,2)), out )

  table.insert( statements, 1, out )
  local fn = d.lambda( "harris", inpraw, d.statements(statements), fifos )
--  local fn = d.lambda( "harris", inpraw, out)
  return fn, descType
end

return sift