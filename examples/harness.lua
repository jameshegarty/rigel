local R = require "rigel"
local RM = require "modules"
local C = require "examplescommon"
local types = require("types")
--local fixed = require("fixed")
local SDFRate = require "sdfrate"

local function writeMetadata(filename, tab)
  err(type(filename)=="string")
  err(type(tab)=="table")
  
  io.output(filename)

  local res = {}
  for k,v in pairs(tab) do
    if type(v)=="number" then
      table.insert(res,k.."="..tostring(v))
    else
      table.insert(res,k.."='"..tostring(v).."'")
    end
  end
      
  io.write( "return {"..table.concat(res,",").."}" )
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

--[=[
local underoverWrapper=memoize(function( hsfn, infile, inputType, tapInputType, outfileraw, outfile, outputType, id, inputCount, outputCount, frames, underflowTest, earlyOverride, disableCycleCounter, X)
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
  return RM.lambda( "harness"..id..hsfn.systolicModule.name, inpSymb, out )
end)
]=]

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


if terralib~=nil then 
  --harnessWrapperFn = underoverWrapper
  H.terraOnly = require("harnessTerra") 
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
    local f = RM.seqMapHandshake( underoverWrapper(hsfn, "../"..inputFilename..".dup", inputType, tapType, "out/"..filename..ext, filename..ext..".isim.raw",outputType,2+i, simInputCount, simOutputCount, frames, underflowTest, earlyOverride), inputType, tapType, tapValue, simInputCount, simOutputCount+cycleCountPixels*frames, false, i )
    io.output("out/"..filename..ext..".isim.v")
    io.write(f:toVerilog())
    io.close()
  end
  
end

function H.verilogOnly(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH,simCycles,X)

  assert(X==nil)
  assert( types.isType(inputType) )
  assert( tapType==nil or types.isType(tapType) )
  if tapType~=nil then tapType:checkLuaValue(tapValue) end
  assert( types.isType(outputType) )
  assert(type(inputW)=="number")
  assert(type(outputH)=="number")
  assert(type(inputFilename)=="string")
  err(R.isFunction(hsfn), "second argument to harness.axi must be function")
  --assert(earlyOverride==nil or type(earlyOverride)=="number")

  writeMetadata("out/"..filename..".metadata.lua", {inputBitsPerPixel=inputType:verilogBits()/(inputT), inputWidth=inputW, inputHeight=inputH, outputBitsPerPixel=outputType:verilogBits()/(outputT), outputWidth=outputW, outputHeight=outputH, inputImage=inputFilename, topModule= hsfn.systolicModule.name, inputP=inputT, outputP=outputT, simCycles=simCycles})
  
------------------------
-- verilator just uses the top module directly
  io.output("out/"..filename..".v")
  io.write(hsfn:toVerilog())
  io.close()

end

local function axiRateWrapper(fn, tapType)
  err(tapType==nil or types.isType(tapType),"tapType should be type or nil")

  R.expectHandshake(fn.inputType)
  
  local iover = R.extractData(fn.inputType)
  
  if tapType~=nil then
    -- taps have tap value packed into argument
    assert(iover.list[2]==tapType)
    iover = iover.list[1]
  end

  R.expectHandshake(fn.outputType)
  oover = R.extractData(fn.outputType)

  if iover:verilogBits()==64 and oover:verilogBits()==64 then
return fn
  end
  
  --err(iover:isArray(), "expected input to be array but is "..tostring(iover))

  local inputP
  local inputPointwise
  if iover:isArray() then
    inputP = iover:channels()
    iover = iover:arrayOver()
    inputPointwise=false
  else
    inputP = 1 -- just assume pointwise...
    inputPointwise=true
  end
  

  local outputP
  if oover:isArray() then
    outputP = oover:channels()
    oover = oover:arrayOver()
  else
    outputP = 1
  end
  
  local targetInputP = (64/iover:verilogBits())
  err( targetInputP==math.floor(targetInputP), "axiRateWrapper error: input type does not divide evenly into axi bus size ("..tostring(fn.inputType)..") iover:"..tostring(iover).." inputP:"..tostring(inputP).." tapType:"..tostring(tapType))
  
  --iover = types.array2d( iover, inputP )
  
  local inp = R.input( R.Handshake(types.array2d(iover,targetInputP)) )
  local out = inp
  
  if fn.inputType:verilogBits()~=64 then
    out = R.apply("harnessCR", RM.liftHandshake(RM.changeRate(iover, 1, targetInputP, inputP )), inp)
  end
  
  if inputPointwise then out = R.apply("harnessPW",RM.makeHandshake(C.index(types.array2d(iover,1),0)),out) end
  out = R.apply("HarnessHSFN",fn,out) --{input=out, toModule=fn}
  if inputPointwise then out = R.apply("harnessPW0",RM.makeHandshake(C.arrayop(oover,1)),out) end
  
  local targetOutputP = (64/oover:verilogBits())
  err( targetOutputP==math.floor(targetOutputP), "axiRateWrapper error: output type does not divide evenly into axi bus size")
  --oover = types.array2d( oover, outputP )
  
  if fn.outputType:verilogBits()~=64 then
    out = R.apply("harnessCREnd", RM.liftHandshake(RM.changeRate(oover,1,outputP,targetOutputP)),out)
  end
  
    --fn = RS.defineModule{input=inp,output=out}
  local outFn =  RM.lambda("hsfnAxiRateWrapper",inp,out)

  assert(outFn.inputType:verilogBits()==64)
  assert(outFn.outputType:verilogBits()==64)
  
  return outFn
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
  assert(type(filename)=="string")
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

function guessP(ty, tapType)
  err(tapType==nil or types.isType(tapType),"tapType should be type or nil")
  
  -- if user didn't pass us type, try to guess it
  -- if array: then it is an array with P=array size
  -- if not array: then it is P=1
  local ty = R.extractData(ty)


  if tapType~=nil then
      assert(ty.list[2]==tapType)
      ty = ty.list[1]
  end

  local iover, inputP
  
  if ty:isArray() then
      iover = ty
      inputP = ty:channels()
  else
      iover = ty
      inputP = 1
  end

  return iover, inputP
end

function harnessTop(t)
  err(type(t.inFile)=="string", "expected input filename to be string")
  err(type(t.outFile)=="string", "expected output filename to be string")

  if(arg[1]=="axi") then
    t.fn = axiRateWrapper(t.fn, t.tapType)
  end
  
  -- just assume we were given a handshake vector...
  R.expectHandshake(t.fn.inputType)

  -- if user explicitly passes us the the info, just trust them...
  local iover, inputP, oover, outputP, fn = t.inType, t.inP, t.outType, t.outP, t.fn

  if iover==nil and inputP==nil then
    iover, inputP = guessP(fn.inputType,t.tapType)
  end

  if oover==nil and outputP==nil then
    oover, outputP = guessP(fn.outputType)
  end

  err(types.isType(iover) and type(inputP)=="number","Error, could not derive input type and P from arguments to harness, type was "..tostring(fn.inputType))
  err(types.isType(oover) and type(outputP)=="number","Error, could not derive output type and P from arguments to harness, type was "..tostring(fn.outputType))

  local inputCount = (t.inSize[1]*t.inSize[2])/inputP
  local outputCount = (t.outSize[1]*t.outSize[2])/outputP
  
  local expectedOutputCount = (inputCount*fn.sdfOutput[1][1]*fn.sdfInput[1][2])/(fn.sdfOutput[1][2]*fn.sdfInput[1][1])
  err(expectedOutputCount==outputCount, "Error, SDF predicted output tokens ("..tostring(expectedOutputCount)..") does not match stated output tokens ("..tostring(outputCount)..")")
  
  if (t.backend==nil and (arg[1]==nil or arg[1]=="verilog")) or t.backend=="verilog" then
    H.verilogOnly( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.simCycles )
  elseif(arg[1]=="axi") then
    H.axi( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.underflowTest, t.earlyOverride )
  elseif(arg[1]=="isim") then
    H.sim( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.underflowTest, t.earlyOverride )
  elseif (t.backend==nil and arg[1]=="terrasim") or t.backend=="terra" then
    H.terraOnly( t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.underflowTest, t.earlyOverride,  t.doHalfTest, t.simCycles )
  else
    print("unknown build target "..arg[1])
    assert(false)
  end

end

return harnessTop
