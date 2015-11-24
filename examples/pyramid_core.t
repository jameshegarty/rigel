local d = require "darkroom"
local C = require "examplescommon"
local P = {}

local function FIFOp(fifos,statements,A,inp, size, name, W,H,T)
  local id = #fifos
  
  -- prevent underutilization. if bit width < 4, we might as well use whole bram.
  local sz = 2048/(math.min(4,A:verilogBits()/8))
  sz = math.max(sz,size)
--  local sz = 2048
  print("FIFO SZ",sz)
  if name==nil then name = "fifo"..tostring(id) end
  table.insert( fifos, d.instantiateRegistered(name, d.fifo(A,sz,nil,W,H,T)) )
  table.insert( statements, d.applyMethod("s"..tostring(id),fifos[#fifos],"store",inp) )
  return d.applyMethod("l"..tostring(id),fifos[#fifos],"load")
end

function P.FIFO(fifos,statements,A,inp,size, name,W,H,T)
  if size==nil then size=1024 end
--  if size==nil then size = 4 end
--  for i=0,size-1 do
    inp = FIFOp(fifos,statements,A,inp, size, name,W,H,T)
--  end
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
local convolvefn = C.convolveConstant( types.uint(8), TConvWidth, P.G, 6 )

function P.pyramidIter(i,doDownsample,internalT,W,H,ConvWidth)
  assert(type(ConvWidth)=="number")


  local inp = d.input( d.Handshake(types.array2d(A,internalT)) )
  local borderValue = 0

  local PadWidth = ConvWidth/2
  if PadWidth < internalT then PadWidth = internalT end
  local PadExtra = PadWidth-(ConvWidth/2)
  print("pyramidIter",i,"internalT",internalT,"padWIdth",PadWidth,"padextra",PadExtra)

  local internalW = W+PadWidth*2
  local internalH = H+ConvWidth
  local PS = d.padSeq(A, W, H, internalT, PadWidth, PadWidth, 4, 4, borderValue)
  print("PS",PS.sdfInput[1][1],PS.sdfInput[1][2],PS.sdfOutput[1][1],PS.sdfOutput[1][2])
  local out = d.apply("pad", d.liftHandshake(PS), inp)

  local out = d.apply( "convLB", d.makeHandshake(d.stencilLinebuffer( A, internalW, internalH, internalT, -ConvWidth+1, 0, -ConvWidth+1, 0 )), out)
  local out = d.apply( "convstencils", d.makeHandshake(d.unpackStencil( A, ConvWidth, ConvWidth, internalT )), out )
  local st_type = types.array2d(A,ConvWidth,ConvWidth)
  local CHS = d.cropHelperSeq(st_type,internalW,internalH,internalT,8+PadExtra,PadExtra,8,0)
  print("CHS",CHS.sdfInput[1][1],CHS.sdfInput[1][2],CHS.sdfOutput[1][1],CHS.sdfOutput[1][2])
  local out = d.apply( "cs", d.liftHandshake(d.liftDecimate(CHS)), out)

  local scaleX, scaleY = 2,2

  local convT = internalT
  if doDownsample then
    out = darkroom.apply("downsampleSeq_Y", d.liftHandshake(darkroom.liftDecimate(darkroom.downsampleYSeq( st_type, W, H, internalT, scaleY ))), out)
    out = darkroom.apply("downsampleSeq_X", d.liftHandshake(darkroom.liftDecimate(darkroom.downsampleXSeq( st_type, W, H, internalT, scaleX ))), out)
    convT = math.max(1,internalT/2)
  end

  out = d.apply("conv", d.makeHandshake(d.map(convolvefn,convT)), out)

  return darkroom.lambda("pyramid"..i, inp, out )
end

local convolvefntaps = C.convolveTaps( types.uint(8), TConvWidth, 6 )

function P.pyramidIterTaps(i,doDownsample,internalT,W,H,ConvWidth,nofifo,X)
  assert(type(ConvWidth)=="number")
  assert(type(nofifo)=="boolean")
  assert(X==nil)
  
  local DATA_TYPE = types.array2d(A,internalT)
  local TAP_TYPE = types.array2d( A, ConvWidth, ConvWidth):makeConst()
  local INP_TYPE = types.tuple{DATA_TYPE,TAP_TYPE}
  local inp = d.input( d.Handshake(INP_TYPE) )
  local borderValue = 0

  local fifos = {}
  local statements = {}

  local out = d.apply("idx0",d.makeHandshake(d.index(INP_TYPE,0)),inp)
  local tapinp = d.apply("idx1",d.makeHandshake(d.index(INP_TYPE,1)),inp)

  local PadWidth = ConvWidth/2
  if PadWidth < internalT then PadWidth = internalT end
  local PadExtra = PadWidth-(ConvWidth/2)
  print("pyramidIter",i,"internalT",internalT,"padWIdth",PadWidth,"padextra",PadExtra)

  local internalW = W+PadWidth*2
  local internalH = H+ConvWidth
  local PS = d.padSeq(A, W, H, internalT, PadWidth, PadWidth, 4, 4, borderValue)
  print("PS",PS.sdfInput[1][1],PS.sdfInput[1][2],PS.sdfOutput[1][1],PS.sdfOutput[1][2])
  local out = d.apply("pad", d.liftHandshake(PS), out)

  local out = d.apply( "convLB", d.makeHandshake(d.stencilLinebuffer( A, internalW, internalH, internalT, -ConvWidth+1, 0, -ConvWidth+1, 0 )), out)
  local out = d.apply( "convstencils", d.makeHandshake(d.unpackStencil( A, ConvWidth, ConvWidth, internalT )), out )
  local st_type = types.array2d(A,ConvWidth,ConvWidth)
  local CHS = d.cropHelperSeq(st_type,internalW,internalH,internalT,8+PadExtra,PadExtra,8,0)
  print("CHS",CHS.sdfInput[1][1],CHS.sdfInput[1][2],CHS.sdfOutput[1][1],CHS.sdfOutput[1][2])
  local out = d.apply( "cs", d.liftHandshake(d.liftDecimate(CHS)), out)

  local scaleX, scaleY = 2,2


  local convT = internalT
  if doDownsample then
    out = darkroom.apply("downsampleSeq_Y", d.liftHandshake(darkroom.liftDecimate(darkroom.downsampleYSeq( st_type, W, H, internalT, scaleY ))), out)
    out = darkroom.apply("downsampleSeq_X", d.liftHandshake(darkroom.liftDecimate(darkroom.downsampleXSeq( st_type, W, H, internalT, scaleX ))), out)
    if nofifo==false then out = P.FIFO(fifos,statements,types.array2d(st_type,convT/2),out,nil,"downsample"..i,W,H,internalT) end

    convT = internalT/4
    assert(convT==math.floor(convT))
    out = d.apply("CR2x",d.liftHandshake(d.changeRate(st_type,1,convT*2,convT)), out)
  end

  local st_tap_inp = d.apply( "broad", d.makeHandshake(d.broadcast(TAP_TYPE,convT)), tapinp )
  st_tap_inp = d.tuple("sttapinp",{out,st_tap_inp},false)
  st_tap_inp = d.apply("ST",d.SoAtoAoSHandshake(convT,1,{st_type,TAP_TYPE}),st_tap_inp)
  out = d.apply("conv_", d.makeHandshake(d.map(convolvefntaps,convT)), st_tap_inp)

  if #statements>0 then
    table.insert(statements,1,out)
    return darkroom.lambda("pyramid"..i, inp, d.statements(statements), fifos )
  else
    return darkroom.lambda("pyramid"..i, inp, out, fifos )
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

  local inp = d.input( d.Handshake(types.array2d(A,1)) )
  local borderValue = 0

  local PadWidth = ConvWidth/2

  local internalW = W+PadWidth*2
  local internalH = H+ConvWidth
  local PS = d.padSeq(A, W, H, 1, PadWidth, PadWidth, 4, 4, borderValue)

  local out = d.apply("pad", d.liftHandshake(PS), inp)

  local out = d.apply( "convLB", d.makeHandshake(d.stencilLinebuffer( A, internalW, internalH, 1, -ConvWidth+1, 0, -ConvWidth+1, 0 )), out)
  local out = d.apply( "convstencils", d.makeHandshake(d.unpackStencil( A, ConvWidth, ConvWidth, 1 )), out )
  local st_type = types.array2d(A,ConvWidth,ConvWidth)
  local CHS = d.cropHelperSeq(st_type,internalW,internalH,1,8,0,8,0)
--  print("CHS",CHS.sdfInput[1][1],CHS.sdfInput[1][2],CHS.sdfOutput[1][1],CHS.sdfOutput[1][2])
  local out = d.apply( "cs", d.liftHandshake(d.liftDecimate(CHS)), out)

  local scaleX, scaleY = 2,2

  out = darkroom.apply("downsampleSeq_Y", d.liftHandshake(darkroom.liftDecimate(darkroom.downsampleYSeq( st_type, W, H, 1, scaleY ))), out)
  if nofifo==false then out = P.FIFO(fifos,statements,types.array2d(st_type,1),out,nil,"downsampleY"..i,W,H,1) end
  out = darkroom.apply("downsampleSeq_X", d.liftHandshake(darkroom.liftDecimate(darkroom.downsampleXSeq( st_type, W, H, 1, scaleX ))), out)

  local convT = internalT/4 -- T after downsample

  print("convT",convT)
  if true then
    out = d.apply("IDX", d.makeHandshake(d.index(types.array2d(st_type,1),0,0)), out)
    out = d.apply("CST", d.makeHandshake( C.cast(st_type,types.array2d(A,ConvWidth*ConvWidth)) ), out)
    out = d.apply("CR", d.liftHandshake(d.changeRate( types.uint(8), 1, ConvWidth*ConvWidth, ConvWidth*ConvWidth*convT )), out )
    out = d.apply("conv", d.liftHandshake(C.convolveConstantTR(types.uint(8),ConvWidth*ConvWidth,1,convT,P.G,6)), out)
  else
    out = d.apply("IDX", d.makeHandshake(d.index(types.array2d(st_type,1),0,0)), out)
    out = d.apply("CR", d.liftHandshake(d.changeRate( types.uint(8), ConvWidth, ConvWidth, convT )), out )
    out = d.apply("conv", d.liftHandshake(C.convolveConstantTR(types.uint(8),ConvWidth,ConvWidth,convT,P.G,6)), out)

  end
--  out = d.apply("AO", d.makeHandshake(C.arrayop(types.uint(8),1,1)), out)

  if nofifo then
    return darkroom.lambda("pyramid"..i, inp, out )
  else
    table.insert(statements,1,out)
    return darkroom.lambda("pyramid"..i, inp, d.statements(statements), fifos )
  end
end

return P