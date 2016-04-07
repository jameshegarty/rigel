local R = require "rigel"
local RM = require "modules"
local C = require "examplescommon"
local P = {}

local function FIFOp(fifos,statements,A,inp, size, name, W,H,T)
  local id = #fifos
  
  -- prevent underutilization. if bit width < 4, we might as well use whole bram.
  local sz = 2048/(math.min(4,A:verilogBits()/8))
  sz = math.max(sz,size)

  print("FIFO SZ",sz)
  if name==nil then name = "fifo"..tostring(id) end
  table.insert( fifos, R.instantiateRegistered(name, RM.fifo(A,sz,nil,W,H,T)) )
  table.insert( statements, R.applyMethod("s"..tostring(id),fifos[#fifos],"store",inp) )
  return R.applyMethod("l"..tostring(id),fifos[#fifos],"load")
end

function P.FIFO(fifos,statements,A,inp,size, name,W,H,T)
  if size==nil then size=2048 end
  inp = FIFOp(fifos,statements,A,inp, size, name,W,H,T)
  return inp
end

function P.gaussian(W,sigma)
  local center = W/2
  local tab = {}
  local sum = 0
  for y=0,W-1 do
    for x=0,W-1 do
      local a = 1/(sigma*math.sqrt(2*math.pi))
      local dist = math.sqrt(math.pow(x-center,2)+math.pow(y-center,2))
      local v = a*math.exp(-(dist*dist)/(2*sigma*sigma))
      sum = sum + v
      print(x,y,v)
      table.insert(tab,v)
    end
  end

  print("sum",sum)
  local newsum = 0
  for i=1,#tab do 
    tab[i] = math.floor((tab[i]*64/sum)+0.4)
    newsum = newsum + tab[i]
  end

  print("newsum",newsum)
  tab[4*W+4] = tab[4*W+4] + (64-newsum)

  for i=1,#tab do print(tab[i]) end

  return tab
end

local TConvWidth = 8
P.G = P.gaussian(TConvWidth,3)
local convolvefn = C.convolveConstant( types.uint(8), TConvWidth, TConvWidth, P.G, 6 )

function P.pyramidIter(i,doDownsample,internalT,W,H,ConvWidth)
  assert(type(ConvWidth)=="number")


  local inp = R.input( R.Handshake(types.array2d(A,internalT)) )
  local borderValue = 0

  local PadWidth = ConvWidth/2
  if PadWidth < internalT then PadWidth = internalT end
  local PadExtra = PadWidth-(ConvWidth/2)
  print("pyramidIter",i,"internalT",internalT,"padWIdth",PadWidth,"padextra",PadExtra)

  local internalW = W+PadWidth*2
  local internalH = H+ConvWidth
  local PS = RM.padSeq(A, W, H, internalT, PadWidth, PadWidth, 4, 4, borderValue)
  print("PS",PS.sdfInput[1][1],PS.sdfInput[1][2],PS.sdfOutput[1][1],PS.sdfOutput[1][2])
  local out = R.apply("pad", RM.liftHandshake(PS), inp)

  local out = R.apply( "convLB", RM.makeHandshake(RM.stencilLinebuffer( A, internalW, internalH, internalT, -ConvWidth+1, 0, -ConvWidth+1, 0 )), out)
  local out = R.apply( "convstencils", RM.makeHandshake(RM.unpackStencil( A, ConvWidth, ConvWidth, internalT )), out )
  local st_type = types.array2d(A,ConvWidth,ConvWidth)
  local CHS = RM.cropHelperSeq(st_type,internalW,internalH,internalT,8+PadExtra,PadExtra,8,0)
  print("CHS",CHS.sdfInput[1][1],CHS.sdfInput[1][2],CHS.sdfOutput[1][1],CHS.sdfOutput[1][2])
  local out = R.apply( "cs", RM.liftHandshake(RM.liftDecimate(CHS)), out)

  local scaleX, scaleY = 2,2

  local convT = internalT
  if doDownsample then
    out = R.apply("downsampleSeq_Y", RM.liftHandshake( RM.liftDecimate( RM.downsampleYSeq( st_type, W, H, internalT, scaleY ))), out)
    out = R.apply("downsampleSeq_X", RM.liftHandshake( RM.liftDecimate( RM.downsampleXSeq( st_type, W, H, internalT, scaleX ))), out)
    convT = math.max(1,internalT/2)
  end

  out = R.apply("conv", RM.makeHandshake(RM.map(convolvefn,convT)), out)

  return RM.lambda("pyramid"..i, inp, out )
end

local convolvefntaps = C.convolveTaps( types.uint(8), TConvWidth, 6 )

-- DUMB_DOWNSAMPLE: instead of doing the convolution at internalT/4 throughput when downsampling, do it at internalT throughput.
function P.pyramidIterTaps(i,doDownsample,internalT,W,H,ConvWidth,nofifo,DUMB_DOWNSAMPLE,X)
  assert(type(ConvWidth)=="number")
  assert(type(nofifo)=="boolean")
  assert(type(DUMB_DOWNSAMPLE)=="boolean")
  assert(X==nil)
  
  local DATA_TYPE = types.array2d(A,internalT)
  local TAP_TYPE = types.array2d( A, ConvWidth, ConvWidth):makeConst()
  local INP_TYPE = types.tuple{DATA_TYPE,TAP_TYPE}
  local inp = R.input( R.Handshake(INP_TYPE) )
  local borderValue = 0

  local fifos = {}
  local statements = {}

  local out = R.apply("idx0",RM.makeHandshake(RM.index(INP_TYPE,0)),inp)
  local tapinp = R.apply("idx1",RM.makeHandshake(RM.index(INP_TYPE,1)),inp)

  local PadWidth = ConvWidth/2
  if PadWidth < internalT then PadWidth = internalT end
  local PadExtra = PadWidth-(ConvWidth/2)
  print("pyramidIter",i,"internalT",internalT,"padWIdth",PadWidth,"padextra",PadExtra)

  local internalW = W+PadWidth*2
  local internalH = H+ConvWidth
  local PS = RM.padSeq(A, W, H, internalT, PadWidth, PadWidth, 4, 4, borderValue)
  print("PS",PS.sdfInput[1][1],PS.sdfInput[1][2],PS.sdfOutput[1][1],PS.sdfOutput[1][2])
  local out = R.apply("pad", RM.liftHandshake(PS), out)

  local out = R.apply( "convLB", RM.makeHandshake(RM.stencilLinebuffer( A, internalW, internalH, internalT, -ConvWidth+1, 0, -ConvWidth+1, 0 )), out)
  local out = R.apply( "convstencils", RM.makeHandshake(RM.unpackStencil( A, ConvWidth, ConvWidth, internalT )), out )
  local st_type = types.array2d(A,ConvWidth,ConvWidth)
  local CHS = RM.cropHelperSeq(st_type,internalW,internalH,internalT,8+PadExtra,PadExtra,8,0)
  print("CHS",CHS.sdfInput[1][1],CHS.sdfInput[1][2],CHS.sdfOutput[1][1],CHS.sdfOutput[1][2])
  local out = R.apply( "cs", RM.liftHandshake(RM.liftDecimate(CHS)), out)

  local scaleX, scaleY = 2,2


  local convT = internalT
  if doDownsample then
    out = R.apply("downsampleSeq_Y", RM.liftHandshake( RM.liftDecimate( RM.downsampleYSeq( st_type, W, H, internalT, scaleY ))), out)
    out = R.apply("downsampleSeq_X", RM.liftHandshake( RM.liftDecimate( RM.downsampleXSeq( st_type, W, H, internalT, scaleX ))), out)
    if nofifo==false then out = P.FIFO(fifos,statements,types.array2d(st_type,convT/2),out,nil,"downsample"..i,W,H,internalT) end

    if DUMB_DOWNSAMPLE then
      out = R.apply("CR2x",RM.liftHandshake(RM.changeRate(st_type,1,convT/2,convT)), out)
    else
      convT = internalT/4
      assert(convT==math.floor(convT))
      out = R.apply("CR2x",RM.liftHandshake(RM.changeRate(st_type,1,convT*2,convT)), out)
    end
  end

  local st_tap_inp = R.apply( "broad", RM.makeHandshake(RM.broadcast(TAP_TYPE,convT)), tapinp )
  st_tap_inp = R.tuple("sttapinp",{out,st_tap_inp},false)
  st_tap_inp = R.apply("ST",RM.SoAtoAoSHandshake(convT,1,{st_type,TAP_TYPE}),st_tap_inp)
  out = R.apply("conv_", RM.makeHandshake(RM.map(convolvefntaps,convT)), st_tap_inp)

  if #statements>0 then
    table.insert(statements,1,out)
    return RM.lambda("pyramid"..i, inp, R.statements(statements), fifos )
  else
    return RM.lambda("pyramid"..i, inp, out, fifos )
  end

--  
end

function P.pyramidIterTR(i, internalT, W, H, ConvWidth, nofifo, X)
  assert(type(internalT)=="number")
  assert(internalT<=1)
  assert(type(ConvWidth)=="number")
  assert(type(nofifo)=="boolean")
  assert(X==nil)

  local fifos = {}
  local statements = {}

  local inp = R.input( R.Handshake(types.array2d(A,1)) )
  local borderValue = 0

  local PadWidth = ConvWidth/2

  local internalW = W+PadWidth*2
  local internalH = H+ConvWidth
  local PS = RM.padSeq(A, W, H, 1, PadWidth, PadWidth, 4, 4, borderValue)

  local out = R.apply("pad", RM.liftHandshake(PS), inp)

  local out = R.apply( "convLB", RM.makeHandshake(RM.stencilLinebuffer( A, internalW, internalH, 1, -ConvWidth+1, 0, -ConvWidth+1, 0 )), out)
  local out = R.apply( "convstencils", RM.makeHandshake(RM.unpackStencil( A, ConvWidth, ConvWidth, 1 )), out )
  local st_type = types.array2d(A,ConvWidth,ConvWidth)
  local CHS = RM.cropHelperSeq(st_type,internalW,internalH,1,8,0,8,0)

  local out = R.apply( "cs", RM.liftHandshake(RM.liftDecimate(CHS)), out)

  local scaleX, scaleY = 2,2

  out = R.apply("downsampleSeq_Y", RM.liftHandshake( RM.liftDecimate( RM.downsampleYSeq( st_type, W, H, 1, scaleY ))), out)
  if nofifo==false then out = P.FIFO(fifos,statements,types.array2d(st_type,1),out,128,"downsampleY"..i,W,H,1) end
  out = R.apply("downsampleSeq_X", RM.liftHandshake( RM.liftDecimate( RM.downsampleXSeq( st_type, W, H, 1, scaleX ))), out)

  local convT = internalT/4 -- T after downsample

  print("convT",convT)
  if true then
    out = R.apply("IDX", RM.makeHandshake(RM.index(types.array2d(st_type,1),0,0)), out)
    out = R.apply("CST", RM.makeHandshake( C.cast(st_type,types.array2d(A,ConvWidth*ConvWidth)) ), out)
    out = R.apply("CR", RM.liftHandshake(RM.changeRate( types.uint(8), 1, ConvWidth*ConvWidth, ConvWidth*ConvWidth*convT )), out )
    out = R.apply("conv", RM.liftHandshake(C.convolveConstantTR(types.uint(8),ConvWidth*ConvWidth,1,convT,P.G,6)), out)
  else
    out = R.apply("IDX", RM.makeHandshake(RM.index(types.array2d(st_type,1),0,0)), out)
    out = R.apply("CR", RM.liftHandshake(RM.changeRate( types.uint(8), ConvWidth, ConvWidth, convT )), out )
    out = R.apply("conv", RM.liftHandshake(C.convolveConstantTR(types.uint(8),ConvWidth,ConvWidth,convT,P.G,6)), out)

  end

  if nofifo then
    return RM.lambda("pyramid"..i, inp, out )
  else
    table.insert(statements,1,out)
    return RM.lambda("pyramid"..i, inp, R.statements(statements), fifos )
  end
end

return P