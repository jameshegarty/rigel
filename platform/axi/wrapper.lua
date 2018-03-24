local rigel = require "rigel"
local R = rigel
local RM = require "modules"
local J = require "common"
local types = require "types"
local C = require "examplescommon"

local VERILOGFILE = arg[1]
local METADATAFILE = arg[2]
local metadata = dofile(METADATAFILE)
local OUTFILE = arg[3]
local PLATFORMDIR = arg[4]
local TOPLEVEL = arg[5]
if TOPLEVEL==nil then TOPLEVEL="axi" end

print("VERILOGFILE",VERILOGFILE)
print("OUTFILE",OUTFILE)

local function readAll(file)
    local f = io.open(file, "rb")
    local content = f:read("*all")
    f:close()
    return content
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

local function axiRateWrapper( fn, metadata )
  R.expectHandshake(fn.inputType)

  local iover = R.extractData(fn.inputType)

  R.expectHandshake(fn.outputType)
  oover = R.extractData(fn.outputType)

  if iover:verilogBits()==64 and oover:verilogBits()==64 then
return fn
  end

  local inputP
  if iover:isArray() then
    inputP = iover:channels()
    iover = iover:arrayOver()
  else
    inputP = 1 -- just assume pointwise...
  end


  local outputP
  if oover:isArray() then
    outputP = oover:channels()
    oover = oover:arrayOver()
  else
    outputP = 1
  end

  local targetInputP = (64/iover:verilogBits())
  J.err( targetInputP==math.floor(targetInputP), "axiRateWrapper error: input type does not divide evenly into axi bus size ("..tostring(fn.inputType)..") iover:"..tostring(iover).." inputP:"..tostring(inputP))
  
  local inp = R.input( R.Handshake(types.array2d(iover,targetInputP)) )
  local out = inp

  if fn.inputType:verilogBits()~=64 then
    out = R.apply("harnessCR", RM.liftHandshake(RM.changeRate(iover, 1, targetInputP, inputP )), inp)
  end

  if R.extractData(fn.inputType):isArray()==false then out = R.apply("harnessPW",RM.makeHandshake(C.index(types.array2d(iover,1),0)),out) end

  -- NOTE: should probably pad/crop here!!!
  out = R.apply("HarnessHSFN",fn,out) --{input=out, toModule=fn}

  if outputP==1 and oover:verilogBits()>64 then
    -- we're writing a huge sized output
    J.err( oover:verilogBits()%64==0, "output bitwidth is not divisible by bus width (64)")
    local divs = oover:verilogBits() / 64

--    out = R.apply("cast1",RM.makeHandshake(C.cast(oover,types.bits(oover:verilogBits()))), out)
    out = R.apply("cast",RM.makeHandshake(C.cast(types.bits(oover:verilogBits()),types.array2d(types.bits(64),divs))), out)
    out = R.apply("down",RM.liftHandshake(RM.changeRate(types.bits(64),1,divs,1)),out)
  else
    if R.extractData(fn.outputType):isArray()==false then out = R.apply("harnessPW0",RM.makeHandshake(C.arrayop(oover,1)),out) end
    
    local targetOutputP = (64/oover:verilogBits())
    J.err( targetOutputP==math.floor(targetOutputP), "axiRateWrapper error: output type ("..tostring(fn.outputType)..") does not divide evenly into axi bus size")
    
    if fn.outputType:verilogBits()~=64 then
      out = R.apply("harnessCREnd", RM.liftHandshake(RM.changeRate(oover,1,outputP,targetOutputP)),out)
    end

  end
  
  local outFn =  RM.lambda("hsfnAxiRateWrapper",inp,out)

  J.err( R.extractData(outFn.inputType):verilogBits()==64, "axi rate wrapper: failed to make input type 64 bit (originally "..tostring(fn.inputType)..")")
  J.err( R.extractData(outFn.outputType):verilogBits()==64, "axi rate wrapper: failed to make output type 64 bit")

  return outFn
end

local function harnessAxi( hsfn, metadata) --inputCountArg, outputCountArg, underflowTest, inputType, earlyOverride)
  local inputBitsArg = metadata.inputWidth*metadata.inputHeight*metadata.inputBitsPerPixel
  local outputBitsArg = metadata.outputWidth*metadata.outputHeight*metadata.outputBitsPerPixel
  J.err( inputBitsArg%8==0, "NYI - non byte aligned inputs")
  J.err( outputBitsArg%8==0, "NYI - non byte aligned outputs")
  local inputBytesArg = inputBitsArg/8
  local outputBytesArg = outputBitsArg/8
  local inputBytes = J.upToNearest(128,inputBytesArg) -- round to axi burst
  local outputBytes = J.upToNearest(128,outputBytesArg) -- round to axi burst
  
  local inputCount = inputBytes/8
  local outputCount = outputBytes/8

  J.err( R.extractData(hsfn.inputType):verilogBits()==64,"harnessAxi: hsfn should have 64 bit input!")
  
  local inpSymb = R.input( R.Handshake(R.extractData(hsfn.inputType)) )
  local inpdata
  local inptaps

  inpdata = inpSymb

  local EC
  if type(metadata.earlyOverride)=="number" then
    EC = metadata.earlyOverride
  else
    EC = expectedCycles( hsfn, inputCount, outputCount, metadata.underflowTest, 1.85 )
  end
  
  local inpdata = R.apply("underflow_US", RM.underflow( R.extractData(hsfn.inputType), inputBytes/8, EC, true ), inpdata)

  local out = inpdata

  -- add a FIFO to all pipelines. Some user's pipeline may not have any FIFOs in them.
  -- you would think it would be OK to have no FIFOs, but for some reason, sometimes wiring the AXI read port and write port
  -- directly won't work. The write port ready seizes up (& the underflow_US is needed to prevent deadlock, but then the image is incorrect).
  -- The problem is intermittent.
  local regs
  local stats = {}
  local EXTRA_FIFO = false

  if EXTRA_FIFO then
      regs = {R.instantiateRegistered("f1",RM.fifo(R.extractData(hsfn.inputType),256))}
      stats[2] = R.applyMethod("s1",regs[1],"store",out)
      out = R.applyMethod("l1",regs[1],"load")
  end

  -- crop down to correct size (from burst size)
--  if inputCount~=inputCountArg then
--    local T = R.extractData(hsfn.inputType):channels()
--    out = R.apply("burstcrop", RM.liftHandshake(RM.liftDecimate(RM.cropSeq( R.extractData(hsfn.inputType):arrayOver(), inputCount*T,1,T,0,(inputCount-inputCountArg)*T,0,0))), out)
--  end
  
  out = R.apply("hsfna",hsfn,out)

  J.err( R.extractData(hsfn.outputType):verilogBits()==64, "harnessAxi: expected 64 bit output" )

  local CYCLES_BURST = 16
  --print("OUTTYPE",hsfn.outputType)
  out = R.apply("cycleCounter", RM.cycleCounter( R.extractData(hsfn.outputType), outputCount ), out)

  -- pad up to burst size
--  if outputCount~=outputCountArg then
--    local T = R.extractData(hsfn.outputType):channels()
--    out = R.apply("burstpad", RM.liftHandshake(RM.padSeq( R.extractData(hsfn.outputType):arrayOver(), (outputCountArg+CYCLES_BURST)*T,1,T,0,(outputCount-outputCountArg)*T,0,0, R.extractData(hsfn.outputType):arrayOver():fakeValue() )), out)
--  end
  
  if EXTRA_FIFO then
     regs[2] = R.instantiateRegistered("f2",RM.fifo(R.extractData(hsfn.outputType),256))
     out = R.applyMethod("l2",regs[2],"load")
     stats[3] = R.applyMethod("s2",regs[2],"store",out)
  end

  out = R.apply("overflow", RM.liftHandshake(RM.liftDecimate(RM.overflow(R.extractData(hsfn.outputType), outputCount+CYCLES_BURST))), out)
  out = R.apply("underflow", RM.underflow(R.extractData(hsfn.outputType), (outputBytes/8)+CYCLES_BURST, EC, false ), out)

  if EXTRA_FIFO then
     stats[1] = out
     out = R.statements(stats)
  end

  return RM.lambda( "harnessaxi", inpSymb, out, regs ), inputBytes, outputBytes
end


------------------------------
-- add axi harness
local globals = {}
if metadata.tapBits>0 then
  globals[R.newGlobal("taps","input",types.bits(metadata.tapBits),0)] = 1
end

local hsfnSdfInput = {{1,1}}
local hsfnSdfOutput = {{1,1}}

if metadata.sdfInputN~=nil then
  hsfnSdfInput = {{metadata.sdfInputN,metadata.sdfInputD}}
  hsfnSdfOutput = {{metadata.sdfOutputN,metadata.sdfOutputD}}
end

-- hack: if user passed us now extected cycles info, just set expected cycles to a billion,
-- which should work for almost all pipelines, but still protect the bus (maybe?)
if metadata.sdfInputN==nil and metadata.earlyOverride==nil then
  metadata.earlyOverride = 16*1024*1024*100
end

-- hack: if verilogFile is 'none', don't concat it
local HSFN_VERILOG = ""
if VERILOGFILE~="none" then HSFN_VERILOG = readAll(VERILOGFILE) end

local hsfnorig = RM.liftVerilog( metadata.topModule, R.Handshake(types.bits(metadata.inputBitsPerPixel*metadata.inputV)), R.Handshake(types.bits(metadata.outputBitsPerPixel*metadata.outputV)), HSFN_VERILOG, globals, hsfnSdfInput, hsfnSdfOutput)
local hsfn = axiRateWrapper(hsfnorig,metadata)
--local iRatio, oRatio = R.extractData(hsfn.inputType):verilogBits()/R.extractData(hsfnorig.inputType):verilogBits(), R.extractData(hsfn.outputType):verilogBits()/R.extractData(hsfnorig.outputType):verilogBits()

--local inputCount = (metadata.inputWidth*metadata.inputHeight)/(iRatio*metadata.inputV)
--local outputCount = (metadata.outputWidth*metadata.outputHeight)/(oRatio*metadata.outputV)
local inputBytes, outputBytes
hsfn, inputBytes, outputBytes = harnessAxi( hsfn, metadata) --inputCount, outputCount, metadata.underflowTest, hsfn.inputType, metadata.earlyOverride )
------------------------------

--local baseTypeI = inputType
--local baseTypeO = rigel.extractData(f.outputType)
--J.err(metadata.inputBitsPerPixel*metadata.inputP==64, "axi input must be 64 bits")
--J.err(metadata.outputBitsPerPixel*metadata.outputP==64, "axi output must be 64 bits")

J.err(R.extractData(hsfn.inputType):verilogBits()==64, "axi input must be 64 bits")
J.err(R.extractData(hsfn.outputType):verilogBits()==64, "axi output must be 64 bits")

local axiv
if TOPLEVEL=="axi" then
  axiv = readAll(PLATFORMDIR.."/axi/axi.v")
else
  axiv = readAll(PLATFORMDIR.."/mpsoc/mpsoc_iptop.sv")..readAll(PLATFORMDIR.."/mpsoc/mpsoc_top.sv")
end

axiv = string.gsub(axiv,"___PIPELINE_MODULE_NAME","harnessaxi")

--local inputCount = (metadata.inputWidth*metadata.inputHeight)/metadata.inputP
--local outputCount = (metadata.outputWidth*metadata.outputHeight)/metadata.outputP
  
-- input/output tokens are one axi bus transaction => they are 8 bytes
--local inputBytes = J.upToNearest(128,inputCount*8)
--local outputBytes = J.upToNearest(128,outputCount*8)
assert(inputBytes%128==0)
assert(outputBytes%128==0)
--local inputBytes = inputCount*8
--local outputBytes = outputCount*8

axiv = string.gsub(axiv,"___PIPELINE_INPUT_BYTES",inputBytes)
-- extra 128 bytes is for the extra AXI burst that contains cycle count
axiv = string.gsub(axiv,"___PIPELINE_OUTPUT_BYTES",outputBytes+128)

local maxUtilization = 1

--axiv = string.gsub(axiv,"___PIPELINE_WAIT_CYCLES",math.ceil(inputCount*maxUtilization)+1024) -- just give it 1024 cycles of slack


verilogStr = (hsfn:toVerilog())..readAll(PLATFORMDIR.."/axi/ict106_axilite_conv.v")
if TOPLEVEL=="axi" then
  verilogStr = verilogStr..readAll(PLATFORMDIR.."/axi/conf.v")

  if metadata.tapBits>0 then
    local tv = J.map( J.range(metadata.tapBits),function(i) return J.sel(math.random()>0.5,"1","0") end )
    local tapreg = "reg ["..(metadata.tapBits-1)..":0] taps = "..tostring(metadata.tapBits).."'b"..table.concat(tv,"")..";\n"
    
    axiv = string.gsub(axiv,"___PIPELINE_TAPS", tapreg.."\nalways @(posedge FCLK0) begin if(CONFIG_READY) taps <= "..tostring(metadata.tapBits).."'h"..metadata.tapValue.."; end\n")
    axiv = string.gsub(axiv,"___PIPELINE_TAPINPUT",",.taps(taps)")
  else
    axiv = string.gsub(axiv,"___PIPELINE_TAPS","")
    axiv = string.gsub(axiv,"___PIPELINE_TAPINPUT","")
  end

else
  J.err(metadata.tapBits%32==0,"NYI - tapBits must be in chunks of 32 bits")
  J.err(metadata.tapBits<1024*32,"NYI - hw module only supports <4KB of taps")
  axiv = string.gsub(axiv,"___CONF_NREG",tostring(4+(metadata.tapBits/32)))
  verilogStr = verilogStr..readAll(PLATFORMDIR.."/axi/conf_nports.v")

  if metadata.tapBits>0 then
    axiv = string.gsub(axiv,"___PIPELINE_TAPINPUT",",.taps(CONFIG_DATA["..(128+metadata.tapBits-1)..":128])")
  else
    axiv = string.gsub(axiv,"___PIPELINE_TAPINPUT","")
  end
end
verilogStr = verilogStr..readAll(PLATFORMDIR.."/axi/dramreader.v")..readAll(PLATFORMDIR.."/axi/dramwriter.v")..axiv

io.output(OUTFILE)
io.write(verilogStr)
io.close()
