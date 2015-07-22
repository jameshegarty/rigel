local d = require "darkroom"
local types = require("types")

local function harness( hsfn, infile, inputType, tapInputType, outfile, outputType, id, outputCount,X)
  assert(X==nil)
  assert(type(outputCount)=="number")
  local fixedTapInputType = tapInputType
  if tapInputType==nil then fixedTapInputType = types.null() end

  local inp = d.input( d.StatefulHandshake(types.tuple{types.null(),fixedTapInputType}) )
  local inpdata = d.apply("inpdata", d.makeHandshake(d.makeStateful(d.index(types.tuple{types.null(),fixedTapInputType},0))), inp)
  local inptaps = d.apply("inptaps", d.makeHandshake(d.makeStateful(d.index(types.tuple{types.null(),fixedTapInputType},1))), inp)
  local out = d.apply("fread",d.makeHandshake(d.freadSeq(infile,inputType)),inpdata)
  local hsfninp = out

  if tapInputType~=nil then
    print("TIP",tapInputType)
    hsfninp = d.tuple("hsfninp",{out,inptaps})
    hsfninp = d.apply("HFN",d.packTuple({inputType,tapInputType},true),hsfninp)
  end


  local out = d.apply("HARNESS_inner", hsfn, hsfninp )
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

function H.sim(filename, hsfn, T, inputType, tapType, tapValue, inputW, inputH, outputType, outputW, outputH, X)
  assert(X==nil)
  assert( tapType==nil or types.isType(tapType) )
  assert( types.isType(inputType) )
  assert( types.isType(outputType) )
  assert(type(outputH)=="number")

  local outputCount = (outputW*outputH)/T
-------------
local f = d.seqMapHandshake( harness(hsfn,"frame_128.raw",inputType,tapType,"out/"..filename..".raw",outputType,1,outputCount), inputType, tapType, tapValue, inputW, inputH, T, outputW, outputH, T,false )
local Module = f:compile()
(terra() var m:Module; m:reset(); m:process(nil,nil); m:stats() end)()
------
local f = d.seqMapHandshake( harness(hsfn, "../../frame_128.raw", inputType, tapType, filename..".sim.raw",outputType,2,outputCount), inputType, tapType, tapValue, inputW, inputH, T, outputW, outputH, T,false )
io.output("out/"..filename..".sim.v")
io.write(f:toVerilog())
io.close()
------
local f = d.seqMapHandshake( harness(hsfn, "../../frame_128.raw",inputType,tapType,filename.."_half.sim.raw",outputType,3, outputCount), inputType, tapType, tapValue, inputW, inputH, T, outputW, outputH, T,false,2 )
io.output("out/"..filename.."_half.sim.v")
io.write(f:toVerilog())
io.close()
----------
d.writeMetadata("out/"..filename..".metadata.lua", outputW, outputH,1,1,"frame_128.raw")
d.writeMetadata("out/"..filename.."_half.metadata.lua", outputW, outputH,1,1,"frame_128.raw")

end

-- AXI must have T=8
function H.axi(filename, hsfn, inputType, tapType, tapValue, inputW, inputH, outputType, outputW, outputH,X)
  print("AXI",tapType,tapValue)

  assert(X==nil)
  assert( types.isType(inputType) )
  assert( tapType==nil or types.isType(tapType) )
  assert( tapType==nil or type(tapValue)==tapType:toLuaType() )
  assert( types.isType(outputType) )
  assert(type(inputW)=="number")
  assert(type(outputH)=="number")

-- axi runs the sim as well
H.sim(filename, hsfn,8,inputType,tapType,tapValue,inputW, inputH, outputType, outputW, outputH)

local axifn = harnessAxi(hsfn, inputW*inputH/8)
local fnaxi = d.seqMapHandshake( axifn, inputType, tapType, tapValue, inputW, inputH, 8, outputW, outputH, 8, true )
io.output("out/"..filename..".axi.v")
io.write(fnaxi:toVerilog())
io.close()
--------
end

return H