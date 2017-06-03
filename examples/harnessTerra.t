local R = require "rigel"
local RM = require "modules"
local C = require "examplescommon"
local cstdlib = terralib.includec("stdlib.h")
local fixed = require "fixed"
local types = require("types")

local terraWrapper = memoize(function(fn,inputFilename,inputType,tapType,outputFilename,outputType,id)
  local fixedTapInputType = tapType
  if tapType==nil then fixedTapInputType = types.null() end

  local ITYPE = types.tuple{types.null(),fixedTapInputType}
  local inpSymb = R.input( R.Handshake(ITYPE) )
  
  local inpdata = R.apply("inpdata", RM.makeHandshake(C.index(types.tuple{types.null(),fixedTapInputType},0),nil,true), inpSymb)
  local inptaps = R.apply("inptaps", RM.makeHandshake(C.index(types.tuple{types.null(),fixedTapInputType},1)), inpSymb)
  local out = R.apply("fread",RM.makeHandshake(RM.freadSeq(inputFilename,inputType),nil,true),inpdata)
  local hsfninp = out
  
  if tapType~=nil then
    hsfninp = R.apply("HFN",RM.packTuple({inputType,tapType}), R.concat("hsfninp",{out,inptaps}))
  end

  local out = R.apply("HARNESS_inner", fn, hsfninp )

  local out = R.apply("fwrite", RM.makeHandshake(RM.fwriteSeq(outputFilename,outputType),nil,true), out )
  return RM.lambda( "harness"..id..fn.systolicModule.name, inpSymb, out )
end)

return function(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, underflowTest, earlyOverride, doHalfTest, simCycles, X)

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
    --local f = harnessWrapperFn( hsfn, inputFilename, inputType, tapType, "out/"..filename, "out/"..filename..ext..".terra.raw", outputType, i, inputCount, outputCount, 1, underflowTest, earlyOverride, true )
    --local f = terraWrapper{fn=hsfn, inputFilename=inputFilename, outputFilename="out/"..filename..ext..".terra.raw",tapType=tapType, inputType=inputType, outputType=outputType,id=i}
    local f = terraWrapper(hsfn,inputFilename,inputType,tapType,"out/"..filename..ext..".terra.raw",outputType,i)
    f = RM.seqMapHandshake( f, inputType, tapType, tapValue, inputCount, outputCount, false, i, simCycles )
    local Module = f:compile()
    if DARKROOM_VERBOSE then print("Call CPU sim, heap size: "..terralib.sizeof(Module)) end
    (terra() 
       --cstdio.printf("Start CPU Sim\n")
       var m:&Module = [&Module](cstdlib.malloc(sizeof(Module))); 
       m:reset(); 
       m:process(nil,nil); 
       if DARKROOM_VERBOSE then m:stats();  end
       cstdlib.free(m) 
     end)()

    if DARKROOM_VERBOSE then fixed.printHistograms() end
  end

end
