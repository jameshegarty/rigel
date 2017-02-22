local R = require "rigel"
local RM = require "modules"
local C = require "examplescommon"
local types = require("types")
local cstdlib = terralib.includec("stdlib.h")
local fixed = require("fixed")
local SDFRate = require "sdfrate"

local function writeMetadata(filename, inputBytesPerPixel, inputWidth, inputHeight, outputBytesPerPixel, outputWidth, outputHeight, inputImage, topModule, X)
  assert(type(inputImage)=="string")
  assert(type(inputBytesPerPixel)=="number")
  assert(type(inputWidth)=="number")
  assert(type(inputHeight)=="number")
  assert(type(outputBytesPerPixel)=="number")
  assert(type(outputWidth)=="number")
  assert(type(outputHeight)=="number")
  assert(type(topModule)=="string")
  assert(X==nil)

  local scaleX = {outputWidth,inputWidth}
  local scaleY = {outputHeight,inputHeight}
  local scale = SDFRate.fracMultiply(scaleX,scaleY)

  io.output(filename)
    io.write("return {inputWidth="..inputWidth..",inputHeight="..inputHeight..",outputWidth="..outputWidth..",outputHeight="..outputHeight..",scaleN="..scale[1]..",scaleD="..scale[2]..",inputBytesPerPixel="..inputBytesPerPixel..",outputBytesPerPixel="..outputBytesPerPixel..",inputImage='"..inputImage.."',topModule='"..topModule.."'}")
  io.close()
end

local function expectedCycles(hsfn,inputCount,outputCount,underflowTest,slackPercent)
  assert(type(outputCount)=="number")
  assert(type(slackPercent)=="number")

  local EC_RAW = inputCount*(hsfn.sdfInput[1][2]/hsfn.sdfInput[1][1])
  EC_RAW = math.ceil(EC_RAW)

  if DARKROOM_VERBOSE then print("Expected cycles:",EC_RAW,"IC",inputCount,hsfn.sdfInput[1][1],hsfn.sdfInput[1][2]) end

  local EC = math.floor(EC_RAW*slackPercent) -- slack
  if underflowTest then EC = 1 end
  return EC, EC_RAW
end

local function harness( hsfn, infile, inputType, tapInputType, outfileraw, outfile, outputType, id, inputCount, outputCount, frames, underflowTest, earlyOverride, disableCycleCounter, X)
  assert(X==nil)
  assert(type(inputCount)=="number")
  assert(type(outputCount)=="number")
  err( darkroom.isFunction(hsfn), "hsfn must be a function")
  assert(type(frames)=="number")

  local fixedTapInputType = tapInputType
  if tapInputType==nil then fixedTapInputType = types.null() end

--  local slack = math.floor(math.max(outputCount*0.3,inputCount*0.3))
  local EC, EC_RAW = expectedCycles(hsfn,inputCount,outputCount,underflowTest,1.5)

  if outfileraw~=nil then
    local fi = outfileraw..".cycles.txt"
    print("WRITE CYCLES",fi)
    io.output(fi)
    io.write(EC_RAW/frames)
    io.close()
  end

  local ECTooSoon = expectedCycles(hsfn,inputCount,outputCount,underflowTest,0.5)
  if earlyOverride~=nil then ECTooSoon=earlyOverride end

  local outputBytes = outputCount*8
  local inputBytes = inputCount*8

  -- check that we end up with a multiple of the axi burst size.  If not, just fail.
  -- dealing with multiple frames w/o this alignment is a pain, so don't allow it
  err(outputBytes/128==math.floor(outputBytes/128), "outputBytes ("..tostring(outputBytes)..") not aligned to axi burst size")
  err(inputBytes/128==math.floor(inputBytes/128), "inputBytes not aligned to axi burst size")
 
  local ITYPE = types.tuple{types.null(),fixedTapInputType}
  local inpSymb = R.input( R.Handshake(ITYPE) )
  -- we give this a less strict timing requirement b/c this counts absolute cycles
  -- on our quarter throughput test, this means this will appear to take 4x as long as it should
  local inp = R.apply("underflow_US", RM.underflow(ITYPE, inputBytes/8, EC*4, true, ECTooSoon), inpSymb)
  local inpdata = R.apply("inpdata", RM.makeHandshake(C.index(types.tuple{types.null(),fixedTapInputType},0)), inp)
  local inptaps = R.apply("inptaps", RM.makeHandshake(C.index(types.tuple{types.null(),fixedTapInputType},1)), inp)
  local out = R.apply("fread",RM.makeHandshake(RM.freadSeq(infile,inputType)),inpdata)
  local hsfninp = out

  if tapInputType~=nil then
    hsfninp = R.apply("HFN",RM.packTuple({inputType,tapInputType}), R.tuple("hsfninp",{out,inptaps},false))
  end

  local out = R.apply("HARNESS_inner", hsfn, hsfninp )
  out = R.apply("overflow", RM.liftHandshake(RM.liftDecimate(RM.overflow(outputType, outputCount))), out)
  out = R.apply("underflow", RM.underflow(outputType, (outputBytes/8), EC, false, ECTooSoon), out)
  if disableCycleCounter==nil or disableCycleCounter==false then 
    out = R.apply("cycleCounter", RM.cycleCounter(R.extractData(hsfn.outputType), outputBytes/(8*frames) ), out)
  end

  local out = R.apply("fwrite", RM.makeHandshake(RM.fwriteSeq(outfile,outputType)), out )
  return RM.lambda( "harness"..id, inpSymb, out )
end

local function harnessAxi( hsfn, inputCount, outputCount, underflowTest, inputType, tapType, earlyOverride)


  local outputBytes = upToNearest(128,outputCount*8) -- round to axi burst
  local inputBytes = upToNearest(128,inputCount*8) -- round to axi burst

  local ITYPE = inputType
  if tapType~=nil then ITYPE = types.tuple{inputType,tapType} end

  local inpSymb = R.input( R.Handshake(ITYPE) )
  local inpdata
  local inptaps

  if tapType==nil then
    inpdata = inpSymb
  else
    inpdata = R.apply("inpdata", RM.makeHandshake(C.index(ITYPE,0)), inpSymb)
    inptaps = R.apply("inptaps", RM.makeHandshake(C.index(ITYPE,1)), inpSymb)
  end

  local EC = expectedCycles(hsfn,inputCount,outputCount,underflowTest,1.85)
  if type(earlyOverride)=="number" then EC=earlyOverride end
  local inpdata = R.apply("underflow_US", RM.underflow( R.extractData(inputType), inputBytes/8, EC, true ), inpdata)

  local hsfninp

  if tapType==nil then
    hsfninp = inpdata
  else
    hsfninp = R.apply("HFN",RM.packTuple({inputType,tapType}), R.tuple("hsfninp",{inpdata,inptaps},false))
  end

  local out = R.apply("hsfna",hsfn,hsfninp)
  out = R.apply("overflow", RM.liftHandshake(RM.liftDecimate(RM.overflow(R.extractData(hsfn.outputType), outputCount))), out)
  out = R.apply("underflow", RM.underflow(R.extractData(hsfn.outputType), outputBytes/8, EC, false ), out)
  out = R.apply("cycleCounter", RM.cycleCounter(R.extractData(hsfn.outputType), outputBytes/8 ), out)
  return RM.lambda( "harnessaxi", inpSymb, out )
end

local H = {}

function H.terraOnly(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, underflowTest, earlyOverride, doHalfTest, X)
  print("UNDERFLOWTEST",underflowTest)
  if doHalfTest==nil then doHalfTest=true end
  assert(X==nil)
  local inputCount = (inputW*inputH)/inputT
  local outputCount = (outputW*outputH)/outputT

  local bound = 2
  if doHalfTest==false then bound=1 end
  -------------
  for i=1,bound do
    local ext=""
    if i==2 then ext="_half" end
    local f = RM.seqMapHandshake( harness( hsfn, inputFilename, inputType, tapType, "out/"..filename, "out/"..filename..ext..".raw", outputType, i, inputCount, outputCount, 1, underflowTest, earlyOverride, true ), inputType, tapType, tapValue, inputCount, outputCount, false, i )
    local Module = f:compile()
    if DARKROOM_VERBOSE then print("Call CPU sim, heap size: "..terralib.sizeof(Module)) end
    (terra() 
       cstdio.printf("Start CPU Sim\n")
       var m:&Module = [&Module](cstdlib.malloc(sizeof(Module))); m:reset(); m:process(nil,nil); m:stats(); cstdlib.free(m) end)()
    fixed.printHistograms()

  end

end

function H.sim(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, underflowTest, earlyOverride, X)
  assert(X==nil)
  assert( tapType==nil or types.isType(tapType) )
  assert( types.isType(inputType) )
  assert( types.isType(outputType) )
  assert(type(outputH)=="number")
  assert(type(inputFilename)=="string")


  local inputCount = (inputW*inputH)/inputT
  local outputCount = (outputW*outputH)/outputT

--  H.terraOnly(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, X)

  local frames = 2
  local simInputH = inputH*frames
  local simOutputH = outputH*frames
  local simInputCount = (inputW*simInputH)/inputT
  local simOutputCount = (outputW*simOutputH)/outputT

  local cycleCountPixels = (128*8)/(outputType:verilogBits())
  ------
  for i=1,2 do
    local ext=""
    if i==2 then ext="_half" end
    local f = RM.seqMapHandshake( harness(hsfn, "../"..inputFilename..".dup", inputType, tapType, "out/"..filename..ext, filename..ext..".sim.raw",outputType,2+i, simInputCount, simOutputCount, frames, underflowTest, earlyOverride), inputType, tapType, tapValue, simInputCount, simOutputCount+cycleCountPixels*frames, false, i )
    io.output("out/"..filename..ext..".sim.v")
    io.write(f:toVerilog())
    io.close()
  end
  
end

function H.verilogOnly(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH,underflowTest,earlyOverride,X)

  assert(X==nil)
  assert( types.isType(inputType) )
  assert( tapType==nil or types.isType(tapType) )
  if tapType~=nil then tapType:checkLuaValue(tapValue) end
  assert( types.isType(outputType) )
  assert(type(inputW)=="number")
  assert(type(outputH)=="number")
  assert(type(inputFilename)=="string")
  err(R.isFunction(hsfn), "second argument to harness.axi must be function")
  assert(earlyOverride==nil or type(earlyOverride)=="number")

  writeMetadata("out/"..filename..".metadata.lua", inputType:verilogBits()/(8*inputT), inputW, inputH, outputType:verilogBits()/(8*outputT), outputW, outputH, inputFilename,hsfn.systolicModule.name)

------------------------
-- verilator just uses the top module directly
  io.output("out/"..filename..".v")
  io.write(hsfn:toVerilog())
  io.close()

end

-- AXI must have T=8
function H.axi(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH,underflowTest,earlyOverride,X)

  assert(X==nil)
  assert( types.isType(inputType) )
  assert( tapType==nil or types.isType(tapType) )
  if tapType~=nil then tapType:checkLuaValue(tapValue) end
  assert( types.isType(outputType) )
  assert(type(inputW)=="number")
  assert(type(outputH)=="number")
  assert(type(inputFilename)=="string")
  assert(type(outputFilename)=="string")
  err(R.isFunction(hsfn), "second argument to harness.axi must be function")
  assert(earlyOverride==nil or type(earlyOverride)=="number")

  err(inputType:verilogBits()==64, "input type must be 64 bits for AXI bus, but is "..tostring(inputType:verilogBits()))
  err(outputType:verilogBits()==64, "output type must be 64 bits for AXI bus")

  local inputCount = (inputW*inputH)/inputT
  local outputCount = (outputW*outputH)/outputT



-- axi runs the sim as well
--H.sim(filename, hsfn,inputFilename, tapType,tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, underflowTest,earlyOverride)
  local inputCount = (inputW*inputH)/inputT
local axifn = harnessAxi(hsfn, inputCount, (outputW*outputH)/outputT, underflowTest, inputType, tapType, earlyOverride)
local cycleCountPixels = 128/8
local fnaxi = RM.seqMapHandshake( axifn, inputType, tapType, tapValue, inputCount, outputCount+cycleCountPixels, true )
io.output("out/"..filename..".axi.v")
io.write(fnaxi:toVerilog())
io.close()
--------
end

function harnessTop(t)
  err(type(t.inFile)=="string", "expected input filename to be string")
  err(type(t.outFile)=="string", "expected output filename to be string")

  -- just assume we were given a handshake vector...
  print("ITYPE",t.fn.inputType)
  R.expectHandshake(t.fn.inputType)

  local iover, inputP, oover, outputP, fn

  if t.inType~=nil then
    -- if user explicitly passes us the type, just trust them...
    iover, inputP = t.inType, t.inP
    oover, outputP = t.outType, t.outP
    fn = t.fn
  else
    
    iover = R.extractData(t.fn.inputType)
    
    if t.tapType~=nil then
      -- taps have tap value packed into argument
      assert(iover.list[2]==t.tapType)
      iover = iover.list[1]
    end
    
    err(iover:isArray(), "expected input to be array but is "..tostring(iover))
    inputP = iover:channels()

    print("OTYPE",t.fn.outputType)
    R.expectHandshake(t.fn.outputType)
    oover = R.extractData(t.fn.outputType)
    assert(oover:isArray())
    outputP = oover:channels()

    fn = t.fn
    
    if iover:verilogBits()~=64 or oover:verilogBits()~=64 then
      local inputP_orig = inputP
      inputP = (64/t.fn.inputType:verilogBits())*inputP
      iover = types.array2d( iover:arrayOver(), inputP )
      
      local inp = R.input( R.Handshake(iover) )
      local out
      
      if t.fn.inputType:verilogBits()~=64 then
        --out = RS.connect{input=inp, toModule=RS.HS(RS.modules.changeRate{ type = iover:arrayOver(), H=1, inW=inputP, outW=inputP_orig })}
        out = R.apply("harnessCR", RM.liftHandshake(RM.changeRate(iover:arrayOver(), 1, inputP, inputP_orig )), inp)
      end
      
      out = R.apply("HarnessHSFN",fn,out) --{input=out, toModule=fn}
      
      local outputP_orig = outputP
      outputP = (64/t.fn.outputType:verilogBits())*outputP
      oover = types.array2d( oover:arrayOver(), outputP )
      
      if t.fn.outputType:verilogBits()~=64 then
        --out = RS.connect{input=out, toModule=RS.HS(RS.modules.changeRate{ type = oover:arrayOver(), H=1, inW=outputP_orig, outW=outputP})}
        out = R.apply("harnessCREnd", RM.liftHandshake(RM.changeRate(oover:arrayOver(),1,outputP_orig,outputP)),out)
      end
      
      --fn = RS.defineModule{input=inp,output=out}
      fn = RM.lambda("hsfn",inp,out)
    end
  end

  if(arg[1]==nil or arg[1]=="verilog") then
    H.verilogOnly( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2] )
  elseif(arg[1]=="axi") then
    H.axi( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.underflowTest, t.earlyOverride )
  elseif(arg[1]=="isim") then
    H.sim( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.underflowTest, t.earlyOverride )
  elseif(arg[1]=="terrasim") then
    H.terraOnly( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.underflowTest, t.earlyOverride,  t.doHalfTest )
  else
    print("unknown build target "..arg[1])
    assert(false)
  end

end

return harnessTop