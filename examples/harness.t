local d = require "darkroom"
local types = require("types")

local function harness( hsfn, infile, inputType, outfile, outputType, id, outputCount)
  assert(type(outputCount)=="number")

  local inp = d.input( d.StatefulHandshake(types.null()) )
  local out = d.apply("fread",d.makeHandshake(d.freadSeq(infile,inputType)),inp)
  local out = d.apply("conv_wide", hsfn, out )
  out = d.apply("overflow", d.liftHandshake(d.liftDecimate(d.overflow(outputType, outputCount))), out)
  local out = d.apply("fwrite", d.makeHandshake(d.fwriteSeq(outfile,outputType)), out )
  return d.lambda( "harness"..id, inp, out )
end

local function harnessAxi( hsfn, outputCount)
  local inp = d.input(hsfn.inputType )
  local out = d.apply("hsfna",hsfn,inp)
  out = d.apply("overflow", d.liftHandshake(d.liftDecimate(d.overflow(d.extractStatefulHandshake(hsfn.outputType), outputCount))), out)
  return d.lambda( "harnessaxi", inp, out )
end

local H = {}

function H.sim(filename, hsfn, T, inputType, inputW, inputH, outputType, outputW, outputH)
  assert( types.isType(inputType) )
  assert( types.isType(outputType) )

  local outputCount = (outputW*outputH)/T
-------------
local f = d.seqMapHandshake( harness(hsfn,"frame_128.raw",inputType,"out/"..filename..".raw",outputType,1,outputCount), inputW, inputH, T, outputW, outputH, T,false )
local Module = f:compile()
(terra() var m:Module; m:reset(); m:process(nil,nil); m:stats() end)()
------
local f = d.seqMapHandshake( harness(hsfn, "../../frame_128.raw", inputType, filename..".sim.raw",outputType,2,outputCount), inputW, inputH, T, outputW, outputH, T,false )
io.output("out/"..filename..".sim.v")
io.write(f:toVerilog())
io.close()
------
local f = d.seqMapHandshake( harness(hsfn, "../../frame_128.raw",inputType,filename.."_half.sim.raw",outputType,3, outputCount), inputW, inputH, T, outputW, outputH, T,false,2 )
io.output("out/"..filename.."_half.sim.v")
io.write(f:toVerilog())
io.close()
----------
d.writeMetadata("out/"..filename..".metadata.lua", outputW, outputH,1,1,"frame_128.raw")
d.writeMetadata("out/"..filename.."_half.metadata.lua", outputW, outputH,1,1,"frame_128.raw")

end

-- AXI must have T=8
function H.axi(filename, hsfn, inputType, inputW, inputH, outputType, outputW, outputH)
  assert( types.isType(inputType) )
  assert( types.isType(outputType) )

-- axi runs the sim as well
H.sim(filename, hsfn,8,inputType,inputW, inputH, outputType, outputW, outputH)

local axifn = harnessAxi(hsfn, inputW*inputH/8)
local fnaxi = d.seqMapHandshake( axifn, inputW, inputH, 8, outputW, outputH, 8, true )
io.output("out/"..filename..".axi.v")
io.write(fnaxi:toVerilog())
io.close()
--------
end

return H