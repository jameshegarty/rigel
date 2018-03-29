local R = require "rigel"
local RM = require "modules"
local C = require "examplescommon"
local types = require("types")
--local fixed = require("fixed")
local SDFRate = require "sdfrate"
local J = require "common"
local err = J.err

local H = {}

if terralib~=nil then
  --harnessWrapperFn = underoverWrapper
  H.terraOnly = require("harnessTerra")
end

local function writeMetadata(filename, tab)
  err(type(filename)=="string")
  err(type(tab)=="table")

  local f = io.open(filename,"w")

  local res = {}
  for k,v in pairs(tab) do
    if type(v)=="number" then
      table.insert(res,k.."="..tostring(v))
    else
      table.insert(res,k.."='"..tostring(v).."'")
    end
  end

  f:write( "return {"..table.concat(res,",").."}" )
  f:close()
end

function H.verilogOnly(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH,simCycles,harnessOption,X)

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

------------------------
-- verilator just uses the top module directly
  io.output(filename..".v")
  io.write(hsfn:toVerilog())
  io.output():close()

end

function guessP(ty, tapType)
  err(tapType==nil or types.isType(tapType),"tapType should be type or nil")

  -- if user didn't pass us type, try to guess it
  -- if array: then it is an array with P=array size
  -- if not array: then it is P=1
  local ty = R.extractData(ty)

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

  local backend = t.backend
  if backend==nil then backend = arg[1] end
  if backend==nil then backend = "verilog" end

  local outDir = t.outDir
  if outDir==nil then outDir=os.getenv("BUILDDIR") end
  if outDir==nil then outDir= "out" end
  
  -- if user explicitly passes us the the info, just trust them...
  local iover, inputP, oover, outputP, fn = t.inType, t.inP, t.outType, t.outP, t.fn

  if iover==nil or inputP==nil then
    iover, inputP = guessP(fn.inputType,t.tapType)
  end

  if oover==nil or outputP==nil then
    oover, outputP = guessP(fn.outputType)
  end

  err(types.isType(iover) and type(inputP)=="number","Error, could not derive input type and P from arguments to harness, type was "..tostring(fn.inputType))
  err(types.isType(oover) and type(outputP)=="number","Error, could not derive output type and P from arguments to harness, type was "..tostring(fn.outputType))

  err( R.isBasic(iover), "Harness error: iover ended up being handshake?")
  err( R.isBasic(oover), "Harness error: oover ended up being handshake?")

  err( (t.inSize[1]*t.inSize[2]) % inputP == 0, "Error, # of input tokens is non-integer, inSize={"..tostring(t.inSize[1])..","..tostring(t.inSize[2]).."}, inputP="..tostring(inputP))
  local inputCount = (t.inSize[1]*t.inSize[2])/inputP
  err( (t.outSize[1]*t.outSize[2]) % outputP == 0, "Error, # of output tokens is non-integer, outSize:"..tostring(t.outSize[1]).."x"..tostring(t.outSize[2]).." outputP:"..tostring(outputP) )

  local outputCountFrac = {t.outSize[1]*t.outSize[2], outputP}

  if R.SDF and iover~=types.null() then
    local expectedOutputCountFrac = {inputCount*fn.sdfOutput[1][1]*fn.sdfInput[1][2],fn.sdfOutput[1][2]*fn.sdfInput[1][1]}

    err( SDFRate.fracEq(expectedOutputCountFrac,outputCountFrac), "Error, SDF predicted output tokens ("..tostring(SDFRate.fracToNumber(expectedOutputCountFrac))..") does not match stated output tokens ("..tostring(SDFRate.fracToNumber(outputCountFrac))..")")
  end

  if backend=="verilog" or backend=="verilator" then
    H.verilogOnly( outDir.."/"..t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.simCycles, t.harness )
  elseif backend=="terra" then
    H.terraOnly( outDir.."/"..t.outFile, fn, t.inFile, t.tapType, t.tapValue, iover, inputP, t.inSize[1], t.inSize[2], oover, outputP, t.outSize[1], t.outSize[2], t.underflowTest, t.earlyOverride,  t.doHalfTest, t.simCycles, t.harness, t.ramFile )
  elseif backend=="metadata" then
    local tapValueString = "x"
    local tapBits = 0
    if t.tapType~=nil then
      err(t.tapType:toCPUType()==t.tapType, "NYI - tap type must be a CPU type")
      tapValueString = t.tapType:valueToHex(t.tapValue)
      tapBits = t.tapType:verilogBits()
    end

    local harnessOption = t.harness
    if harnessOption==nil then harnessOption=1 end

    local MD = {inputBitsPerPixel=R.extractData(iover):verilogBits()/(inputP), inputWidth=t.inSize[1], inputHeight=t.inSize[2], outputBitsPerPixel=oover:verilogBits()/(outputP), outputWidth=t.outSize[1], outputHeight=t.outSize[2], inputImage=t.inFile, topModule= fn.name, inputV=inputP, outputV=outputP, simCycles=t.simCycles, tapBits=tapBits, tapValue=tapValueString, harness=harnessOption, ramFile=t.ramFile}

    if fn.sdfInput~=nil then
      assert(#fn.sdfInput==1)
      MD.sdfInputN = fn.sdfInput[1][1]
      MD.sdfInputD = fn.sdfInput[1][2]
    end

    if fn.sdfOutput~=nil then
      assert(#fn.sdfOutput==1)
      MD.sdfOutputN = fn.sdfOutput[1][1]
      MD.sdfOutputD = fn.sdfOutput[1][2]
    end
    
    MD.earlyOverride=t.earlyOverride
    MD.underflowTest = t.underflowTest
    
    if t.ramType~=nil then MD.ramBits = t.ramType:verilogBits() end

    writeMetadata(outDir.."/"..t.outFile..".metadata.lua", MD)
  else
    print("unknown build target "..arg[1])
    assert(false)
  end

end

return harnessTop
