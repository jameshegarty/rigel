local rigel = require "rigel"
local J = require "common"

local VERILOGFILE = arg[1]
local METADATAFILE = arg[2]
local metadata = dofile(METADATAFILE)
local OUTFILE = arg[3]
local PLATFORMDIR = arg[4]

print("VERILOGFILE",VERILOGFILE)
print("OUTFILE",OUTFILE)

local function readAll(file)
    local f = io.open(file, "rb")
    local content = f:read("*all")
    f:close()
    return content
end

local function harnessAxi( hsfn, inputCount, outputCount, underflowTest, inputType, earlyOverride)
  local outputBytes = J.upToNearest(128,outputCount*8) -- round to axi burst
  local inputBytes = J.upToNearest(128,inputCount*8) -- round to axi burst

  err(outputBytes==outputCount*8, "NYI - non-burst-aligned output counts")
  err(inputBytes==inputCount*8, "NYI - non-burst-aligned input counts")

  local ITYPE = inputType

  local inpSymb = R.input( R.Handshake(ITYPE) )
  local inpdata
  local inptaps

  inpdata = inpSymb

  local EC
  if type(earlyOverride)=="number" then
    EC=earlyOverride
  else
    EC = expectedCycles(hsfn,inputCount,outputCount,underflowTest,1.85)
  end
  
  local inpdata = R.apply("underflow_US", RM.underflow( R.extractData(inputType), inputBytes/8, EC, true ), inpdata)

  local hsfninp

  hsfninp = inpdata

  -- add a FIFO to all pipelines. Some user's pipeline may not have any FIFOs in them.
  -- you would think it would be OK to have no FIFOs, but for some reason, sometimes wiring the AXI read port and write port
  -- directly won't work. The write port ready seizes up (& the underflow_US is needed to prevent deadlock, but then the image is incorrect).
  -- The problem is intermittent.
  local regs, out
  local stats = {}
  local EXTRA_FIFO = false

  if EXTRA_FIFO then
      regs = {R.instantiateRegistered("f1",RM.fifo(R.extractData(hsfn.inputType),256))}
      stats[2] = R.applyMethod("s1",regs[1],"store",hsfninp)
      hsfninp = R.applyMethod("l1",regs[1],"load")
  end

  local pipelineOut = R.apply("hsfna",hsfn,hsfninp)

  if EXTRA_FIFO then
     regs[2] = R.instantiateRegistered("f2",RM.fifo(R.extractData(hsfn.outputType),256))
     out = R.applyMethod("l2",regs[2],"load")
     stats[3] = R.applyMethod("s2",regs[2],"store",pipelineOut)
  else
     out = pipelineOut
  end

  out = R.apply("overflow", RM.liftHandshake(RM.liftDecimate(RM.overflow(R.extractData(hsfn.outputType), outputCount))), out)
  out = R.apply("underflow", RM.underflow(R.extractData(hsfn.outputType), outputBytes/8, EC, false ), out)
  out = R.apply("cycleCounter", RM.cycleCounter(R.extractData(hsfn.outputType), outputBytes/8 ), out)

  if EXTRA_FIFO then
     stats[1] = out
     out = R.statements(stats)
  end

  return RM.lambda( "harnessaxi", inpSymb, out, regs )
end

--local baseTypeI = inputType
--local baseTypeO = rigel.extractData(f.outputType)
J.err(metadata.inputBitsPerPixel*metadata.inputP==64, "axi input must be 64 bits")
J.err(metadata.outputBitsPerPixel*metadata.outputP==64, "axi output must be 64 bits")

local axiv = readAll("../platform/axi/axi.v")
axiv = string.gsub(axiv,"___PIPELINE_MODULE_NAME","harnessaxi")

local inputCount = (metadata.inputWidth*metadata.inputHeight)/metadata.inputP
local outputCount = (metadata.outputWidth*metadata.outputHeight)/metadata.outputP
  
-- input/output tokens are one axi bus transaction => they are 8 bytes
local inputBytes = J.upToNearest(128,inputCount*8)
local outputBytes = J.upToNearest(128,outputCount*8)
axiv = string.gsub(axiv,"___PIPELINE_INPUT_BYTES",inputBytes)
-- extra 128 bytes is for the extra AXI burst that contains cycle count
axiv = string.gsub(axiv,"___PIPELINE_OUTPUT_BYTES",outputBytes+128)

local maxUtilization = 1

--axiv = string.gsub(axiv,"___PIPELINE_WAIT_CYCLES",math.ceil(inputCount*maxUtilization)+1024) -- just give it 1024 cycles of slack

if metadata.tapBits>0 then
  local tv = J.map( J.range(metadata.tapBits),function(i) return J.sel(math.random()>0.5,"1","0") end )
  local tapreg = "reg ["..(metadata.tapBits-1)..":0] taps = "..tostring(metadata.tapBits).."'b"..table.concat(tv,"")..";\n"
  
  axiv = string.gsub(axiv,"___PIPELINE_TAPS", tapreg.."\nalways @(posedge FCLK0) begin if(CONFIG_READY) taps <= "..tostring(metadata.tapBits).."'h"..metadata.tapValue.."; end\n")
  axiv = string.gsub(axiv,"___PIPELINE_TAPINPUT",",.taps(taps)")
else
  axiv = string.gsub(axiv,"___PIPELINE_TAPS","")
  axiv = string.gsub(axiv,"___PIPELINE_TAPINPUT","")
end

verilogStr = readAll(VERILOGFILE)..readAll("../platform/axi/ict106_axilite_conv.v")..readAll("../platform/axi/conf.v")..readAll("../platform/axi/dramreader.v")..readAll("../platform/axi/dramwriter.v")..axiv

io.output(OUTFILE)
io.write(verilogStr)
io.close()
