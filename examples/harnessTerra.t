local RM = require "modules"
local cstdlib = terralib.includec("stdlib.h")
local fixed = require "fixed"

return function(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, underflowTest, earlyOverride, doHalfTest, X)
  --print("UNDERFLOWTEST",underflowTest)
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
    local f = RM.seqMapHandshake( harnessWrapperFn( hsfn, inputFilename, inputType, tapType, "out/"..filename, "out/"..filename..ext..".terra.raw", outputType, i, inputCount, outputCount, 1, underflowTest, earlyOverride, true ), inputType, tapType, tapValue, inputCount, outputCount, false, i )
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
