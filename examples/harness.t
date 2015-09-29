local d = require "darkroom"
local types = require("types")
local cstdlib = terralib.includec("stdlib.h")
local fixed = require("fixed")

local function harness( hsfn, infile, inputType, tapInputType, outfile, outputType, id, outputCount,X)
  assert(X==nil)
  assert(type(outputCount)=="number")
  local fixedTapInputType = tapInputType
  if tapInputType==nil then fixedTapInputType = types.null() end

  local inp = d.input( d.Handshake(types.tuple{types.null(),fixedTapInputType}) )
  local inpdata = d.apply("inpdata", d.makeHandshake(d.index(types.tuple{types.null(),fixedTapInputType},0)), inp)
  local inptaps = d.apply("inptaps", d.makeHandshake(d.index(types.tuple{types.null(),fixedTapInputType},1)), inp)
  local out = d.apply("fread",d.makeHandshake(d.freadSeq(infile,inputType)),inpdata)
  local hsfninp = out

  if tapInputType~=nil then
    hsfninp = d.apply("HFN",d.packTuple({inputType,tapInputType}), d.tuple("hsfninp",{out,inptaps},false))
  end


  local out = d.apply("HARNESS_inner", hsfn, hsfninp )
  out = d.apply("overflow", d.liftHandshake(d.liftDecimate(d.overflow(outputType, outputCount))), out)
  local out = d.apply("fwrite", d.makeHandshake(d.fwriteSeq(outfile,outputType)), out )
  return d.lambda( "harness"..id, inp, out )
end

local function harnessAxi( hsfn, outputCount)
  local inp = d.input(hsfn.inputType )
  local out = d.apply("hsfna",hsfn,inp)
  out = d.apply("overflow", d.liftHandshake(d.liftDecimate(d.overflow(d.extractData(hsfn.outputType), outputCount))), out)
  return d.lambda( "harnessaxi", inp, out )
end

local H = {}

function H.terraOnly(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, X)
  local outputCount = (outputW*outputH)/outputT

  -------------
  for i=1,2 do
    local ext=""
    if i==2 then ext="_half" end
    local f = d.seqMapHandshake( harness( hsfn, inputFilename, inputType, tapType, "out/"..filename..ext..".raw", outputType, i, outputCount ), inputType, tapType, tapValue, inputW, inputH, inputT, outputW, outputH, outputT, false, i )
    local Module = f:compile()
    if DARKROOM_VERBOSE then print("Call CPU sim, heap size: "..terralib.sizeof(Module)) end
    (terra() 
       cstdio.printf("Start CPU Sim\n")
       var m:&Module = [&Module](cstdlib.malloc(sizeof(Module))); m:reset(); m:process(nil,nil); m:stats(); cstdlib.free(m) end)()
    fixed.printHistograms()

    d.writeMetadata("out/"..filename..ext..".metadata.lua", inputType:verilogBits()/(8*inputT), inputW, inputH, outputType:verilogBits()/(8*outputT), outputW, outputH, inputFilename)
  end

end

function H.sim(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, X)
  assert(X==nil)
  assert( tapType==nil or types.isType(tapType) )
  assert( types.isType(inputType) )
  assert( types.isType(outputType) )
  assert(type(outputH)=="number")
  assert(type(inputFilename)=="string")

  local outputCount = (outputW*outputH)/outputT

  H.terraOnly(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, X)

  ------
  for i=1,2 do
    local ext=""
    if i==2 then ext="_half" end
    local f = d.seqMapHandshake( harness(hsfn, "../../"..inputFilename, inputType, tapType, filename..ext..".sim.raw",outputType,2+i,outputCount), inputType, tapType, tapValue, inputW, inputH, inputT, outputW, outputH, outputT, false, i )
    io.output("out/"..filename..ext..".sim.v")
    io.write(f:toVerilog())
    io.close()
  end
  
end

-- AXI must have T=8
function H.axi(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH,X)

  assert(X==nil)
  assert( types.isType(inputType) )
  assert( tapType==nil or types.isType(tapType) )
  assert( tapType==nil or type(tapValue)==tapType:toLuaType() )
  assert( types.isType(outputType) )
  assert(type(inputW)=="number")
  assert(type(outputH)=="number")
  assert(type(inputFilename)=="string")
  err(d.isFunction(hsfn), "second argument to harness.axi must be function")

-- axi runs the sim as well
H.sim(filename, hsfn,inputFilename, tapType,tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH)

local axifn = harnessAxi(hsfn, (outputW*outputH)/outputT)
local fnaxi = d.seqMapHandshake( axifn, inputType, tapType, tapValue, inputW, inputH, inputT, outputW, outputH, outputT, true )
io.output("out/"..filename..".axi.v")
io.write(fnaxi:toVerilog())
io.close()
--------
end

return H