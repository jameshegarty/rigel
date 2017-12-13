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
