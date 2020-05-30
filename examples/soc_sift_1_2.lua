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
local Uniform = require "uniform"

local SIFT_OLD = require "sift_core_hw"
-- this is just lua code, so just use old code
local calcGaussian = SIFT_OLD.calcGaussian
SIFT_OLD=nil

local function tileGaussian(G,W,H,Tw,Th)
  assert(type(G)=="table")
  assert(type(W)=="number")
  assert(type(Tw)=="number")
  assert(type(Th)=="number")

  local GG = {}
  for ty=0,(H/Th)-1 do
    for tx=0,(W/Tw)-1 do
      local tmp = {}
      for y=0,Th-1 do
        for x=0,Tw-1 do
          table.insert(tmp,G[(ty*Th+y)*W+(tx*Tw+x)])
        end
      end
      table.insert(GG,tmp)
    end
  end

  return GG
end

local siftTerra
if terralib~=nil then siftTerra = require("sift_core_hw_terra") end

R.default_nettype_none = false

local GRAD_INT = true
local GRAD_SCALE = 4 -- <2 is bad
local GRAD_TYPE = types.int(8)

local GAUSS_SIGMA = 5

local first,flen = string.find(arg[0],"%d+")
local TILES = tonumber(string.sub(arg[0],first,flen))
local V = tonumber(string.sub(arg[0], string.find(arg[0],"%d+",flen+1)))

local size1080p = (string.find(arg[0],"1080p")~=nil)

local W = 256
local H = 256

local FILTER_FIFO = 512
local OUTPUT_COUNT = 614

if size1080p then
  W,H = 1920, 1080
  OUTPUT_COUNT = 3599
end

local FILTER_RATE = {OUTPUT_COUNT,W*H}

local TILES_X = TILES
local TILES_Y = TILES
local TILE_W = 4
local TILE_H = 4

local invV = (TILES_X*TILES_Y*TILE_W*TILE_H)/V
local cycles = W*H*invV
print("CYCLES",cycles,"invV",invV)

local outfile = "soc_sift_"..tostring(TILES).."_"..tostring(V)..J.sel(size1080p,"_1080p","")

io.output("out/"..outfile..".design.txt"); io.write("SIFT "..TILES..J.sel(size1080p," 1080p","")); io.close()
io.output("out/"..outfile..".designT.txt"); io.write(1/invV); io.close()
io.output("out/"..outfile..".dataset.txt"); io.write("SIG20_zu9"); io.close()

local regs = SOC.axiRegs({},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

local GAUSS  = {14 , 62 , 104 , 62 , 14}

local ClampToInt8 = G.Function{"Clampint8",types.rv(types.FloatRec32),
function(i)
  local v127 = G.FtoFR(R.c(types.Float32,127))
  local vm128 = G.FtoFR(R.c(types.Float32,-128))
  local tmp = G.Sel(G.GTF(i,v127),v127,i)
  local tmp = G.Sel(G.LTF(i,vm128),vm128,tmp)
  return tmp
end}

local DXDYToInt8 = G.Function{"LowerPair",types.rv(types.tuple{T.FloatRec32,T.FloatRec32}),
function(i)
  local tmp = R.concat{G.MulF{GRAD_SCALE}(i[0]), G.MulF{GRAD_SCALE}(i[1])}

  tmp = G.TupleToArray(tmp)
  tmp = G.Map{ClampToInt8}(tmp)
  tmp = G.Map{G.FRtoI{8}}(tmp)
  return G.ArrayToTuple(tmp)
end}

function ConvolveFloat( ConvWidth, ConvHeight, coeffs, shift )
  return G.Function{"ConvolveFloat_"..tostring(ConvWidth).."_"..tostring(ConvHeight), T.rv(T.Array2d( T.FloatRec32, ConvWidth, ConvHeight )),
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

local harrisDXDYKernel = G.Function{"DXDYKernel", types.rv(types.Array2d(types.FloatRec32,3,3)),
function(i)
  local dx = G.SubF(G.Index{{2,1}}(i),G.Index{{0,1}}(i))
  dx = G.MulF{1/2}(dx)

  local dy = G.SubF(G.Index{{1,2}}(i),G.Index{{1,0}}(i))
  dy = G.MulF{1/2}(dy)

  return R.concat{dx,dy}
end}

local harrisHarrisKernel = G.SchedulableFunction{"HarrisKernel",T.Tuple{T.FloatRec32,T.FloatRec32},
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

local harrisNMS = G.Function{"NMS", T.rv(types.Array2d(types.FloatRec32,3,3)),
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

local HarrisDXDY = G.SchedulableFunction{"HarrisDXDY",T.Array2d(T.U(8),P.SizeValue("size")),
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

local BucketReduce = G.Function{"BucketReduce", T.rv(T.Tuple{T.Array2d(T.I32,8),T.Array2d(T.I32,8)}),
function(i)
  local z = G.Zip(i)
  return G.Map{G.Add{R.Async}}(z)
end}

local Bucketize = G.Function{"Bucketize",types.rv(types.tuple{T.FloatRec32,T.FloatRec32,T.FloatRec32}),
function(i)
  local dx = i[0]

  local dy = i[1]
  local mag = G.MulF{1024/GRAD_SCALE}(i[2]) --*f.constant(RED_SCALE)):lower(RED_TYPE)

  mag = G.FRtoI{32}(mag)

  local zero = R.c( T.I32, 0 ) --f.plainconstant(0,RED_TYPE)

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

local SiftMagPre = G.Function{"siftMagPre",types.rv(types.tuple{T.FloatRec32,T.FloatRec32}),
function(i)
  local dx = i[0]
  local dy = i[1]
  local magsq = G.AddF( G.MulF(dx,dx), G.MulF(dy,dy) )
  return magsq
end}
  
local SiftMag = G.Function{"siftMagInp",types.RV(types.tuple{T.FloatRec32,T.FloatRec32,T.FloatRec32}),
function(inp)
  local i = G.FanOut{2}(inp)
  local gauss_weight = G.FIFO{128}(i[1][2])

  local magsq = G.Fmap{SiftMagPre}(G.Slice{{0,1}}(i[0]))
  local mag = G.SqrtF( magsq )
  mag = G.FIFO{1}(mag)

  local out = G.MulF(G.FanIn(mag,gauss_weight))
  return out
end}

local GAUSS = calcGaussian(GAUSS_SIGMA,TILES_X*TILE_W,TILES_Y*TILE_H) -- sigma was 5
GAUSS = tileGaussian( GAUSS, TILES_X*TILE_W, TILES_Y*TILE_H, TILE_W, TILE_H)

local SiftDescriptor = G.SchedulableFunction{"SiftDescriptor",
T.Array2d(T.Array2d(T.Tuple{T.I8,T.I8},TILE_W,TILE_H),TILES_X,TILES_Y),
function(inp)                                             
  local inpb = G.FanOut{3}(inp)
  
  local gtrig = G.FIFO{128}(G.ValueToTrigger(inpb[0]))

  local gweight = G.Const{T.Array2d(T.Array2d(T.Float32,TILE_W,TILE_H),TILES_X,TILES_Y),value=GAUSS}(gtrig)

  local dx = G.FIFO{128}(G.Map{G.Map{G.Index{0}}}(inpb[1]))
  local dy = G.FIFO{128}(G.Map{G.Map{G.Index{1}}}(inpb[2]))

  if GRAD_INT then
    dx = G.Map{G.Map{G.ItoFR}}(dx)
    dy = G.Map{G.Map{G.ItoFR}}(dy)
    gweight = G.Map{G.Map{G.Identity}}(gweight)
    gweight = G.Map{G.Map{G.FtoFR}}(gweight)
  end

  dx, dy = G.FanOut{2}(dx), G.FanOut{2}(dy)
  
  local maginp = R.concat("maginp",{G.FIFO{128}(dx[0]),G.FIFO{128}(dy[0]),gweight})

  maginp = G.FanIn(maginp)
  maginp = G.Zip(maginp)
  maginp = G.Map{G.Zip}(maginp)

  local mag = G.Map{G.Map{SiftMag}}(maginp)
  local bucketInp = R.concat("bktinp",{G.FIFO{128}(dx[1]),G.FIFO{128}(dy[1]),mag})
  bucketInp = G.FanIn(bucketInp)
  bucketInp = G.Zip(bucketInp)
  bucketInp = G.Map{G.Zip}(bucketInp)

  local out = G.Map{G.Map{Bucketize}}(bucketInp)
  return out
end}

local AddDescriptorPos = G.Function{"descpos",types.rv(types.tuple{types.array2d(T.FloatRec32,TILES_X*TILES_Y*8),types.uint(16),types.uint(16)}),
function(i)
  local desc = i[0]
  local px = G.UtoFR(i[1])
  local py = G.UtoFR(i[2])
  
  local a = {px,py}
  for i=0,(TILES_X*TILES_Y*8-1) do table.insert(a,desc[i]) end

  local out = G.TupleToArray(R.concat(a))
  return out
end}

local SiftKernel = G.SchedulableFunction{"SiftKernel",
T.Tuple{T.Array2d(T.Tuple{T.I8,T.I8},TILES_X*TILE_W,TILES_Y*TILE_H), T.Tuple{T.U16,T.U16} },
--T.Tuple{T.Array2d(T.Tuple{T.I8,T.I8},TILES_X*4,TILES_Y*4), T.Array2d(T.U16,2) },
function(i)
  local dxdyType = types.I8
  local dxdyPair = types.tuple{dxdyType,dxdyType}
  local posType = types.uint(16)
  
  local inp = G.FanOut{2}(i)

  local pos = inp[0][1]

  pos = G.FIFO{1024}(pos)
  
  local posFO = G.FanOut{2}(pos)

  local posX = G.FIFO{1024}(posFO[0][0])
  local posY = G.FIFO{1024}(posFO[1][1])

  local dxdy = inp[1][0]

  local dxdyTiles = G.Tile{{TILE_W,TILE_H}}(dxdy)

  local desc = SiftDescriptor(dxdyTiles)
  local desc = G.Map{G.Reduce{BucketReduce}}(desc)

  -- it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
  -- We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
  -- that reduceSeq only has an output every 16 cycles, so it can't overlap them)

  local desc = G.FIFO{128}(desc)

  -- sum and normalize the descriptors
  local desc_broad = G.FanOut{2}(desc)

  local desc0 = R.selectStream("d0",desc_broad,0)
  local desc0 = G.FIFO{256}(desc0)
  
  local desc1 = R.selectStream("d1",desc_broad,1)
  local desc1 = G.FIFO{256}(desc1)

  -- sum up all the mags in all the buckets
  desc1 = G.Flatten(desc1)

  local desc_sum = G.Reduce{ RS.modules.sumPow2{inType=types.int(32),outType=types.int(32)} }(desc1)

  desc_sum = G.ItoFR(desc_sum)
  desc_sum = G.SqrtF( desc_sum )
  desc_sum = G.Broadcast{{8,1}}(desc_sum)
  desc_sum = G.Broadcast{{TILES_X,TILES_Y}}(desc_sum)

  desc0 = G.Map{G.Map{G.ItoFR}}(desc0)

  local desc = G.FanIn(desc0,desc_sum)

  desc = G.Zip(desc)
  desc = G.Map{G.Zip}(desc)
  desc = G.Map{G.Map{G.DivF}}(desc)
  desc = G.Flatten(desc)
  desc = G.ReshapeArray{{TILES_X*TILES_Y*8,1}}(desc)

  -- HACK:FIX: work around bug in interface conversion
  desc = G.Deser{TILES_X*TILES_Y*8}(desc)
  
  local desc_cc = R.concat{desc,posX,posY}

  desc = G.FanIn(desc_cc)
  desc = G.Fmap{AddDescriptorPos}(desc)

  return desc
end}

local IT = T.Array2d(T.Tuple{T.I8,T.I8},TILES_X*TILE_W,TILES_Y*TILE_H)
local AddImagePos = G.Function{"AddImagePos",T.rv(T.Array2d(IT,Uniform(W+15),H+15,0,0)),
function(i)
  local trig = G.Map{G.ValueToTrigger}(i)
  local pos = G.PosCounter{true}(trig)
  pos = G.Map{G.TupleToArray}(pos)
  pos = G.Map{G.Map{G.Sub{15}}}(pos)
  pos = G.Map{G.ArrayToTuple}(pos)
  local res =  G.Zip(G.FanIn(i,pos))
  return res
end}
                                          
local SiftTop = G.SchedulableFunction{"SiftTop", T.Array2d(T.U(8),P.SizeValue("size")),
function(inp)                           
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
    left = G.Map{DXDYToInt8}(left)
  end

  left = G.FIFO{2048/(types.tuple{GRAD_TYPE,GRAD_TYPE}:verilogBits())}(left)

  left = G.Stencil{{-TILES_X*TILE_W+1,0,-TILES_Y*TILE_H+1,0}}(left)

  left = G.Fmap{AddImagePos}(left)
  -------------------------------

  -- merge left/right
  local out = G.Zip(left,right)
  out = G.Crop{{15,0,15,0}}(out)
  out = G.Filter{{FILTER_RATE[1],FILTER_RATE[2]}}(out)
  out = G.FIFO{FILTER_FIFO}(out)
  out = G.Map{SiftKernel}(out)

  -- hack: we know how many descriptors will be written out, so just clamp the array to that size!
  -- this will allow use to use the standard DMAs
  out = G.ClampToSize{{OUTPUT_COUNT,1}}(out)
  out = G.Flatten(out)

  -- bitcast to uint8[8] for display...
  out = G.Map{G.Float}(out)
  out = G.Map{G.Bitcast{types.Array2d(types.Uint(8),4)}}(out)
  out = G.Flatten(out)
  out = G.Reshape{{(TILES_X*TILES_Y*8+2)*4,OUTPUT_COUNT}}(out)
  
  return out
end}

local TopModule = G.SchedulableFunction{ "TopModule", T.Trigger,
function(i)
  local readStream = G.AXIReadBurst{ J.sel(size1080p,"boxanim0000.raw","boxanim_256.raw"), {W,H}, T.u(8), 8, noc.read }(i)
  local offset = SiftTop(readStream)
  print("SIFTOUT",offset.type)
  return G.AXIWriteBurst{"out/"..outfile,noc.write}(offset)
end}

harness({regs.start, TopModule, regs.done},nil,{regs})
