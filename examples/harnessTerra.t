local R = require "rigel"
local RM = require "modules"
local C = require "examplescommon"
local cstdlib = terralib.includec("stdlib.h")
local fixed = require "fixed"
local types = require("types")
local J = require "common"

local terraWrapper = J.memoize(function(fn,inputFilename,inputType,tapType,outputFilename,outputType,id,harnessoption,ramFile)

  local out
  local inpSymb
  local instances = {}
  local dram, dramAddr
  
  if inputType~=types.null() then
    local fixedTapInputType = tapType
    if tapType==nil then fixedTapInputType = types.null() end
    
    local ITYPE = types.tuple{types.null(),fixedTapInputType}
    inpSymb = R.input( R.Handshake(ITYPE) )

    local inpL, inpR = inpSymb, inpSymb

    if tapType~=nil then
      local O = R.apply("bstream",RM.broadcastStream(ITYPE,2),inpSymb)
      inpL = R.selectStream("b0",O,0)
      inpR = R.selectStream("b1",O,1)
    end
    
    local inpdata = R.apply("inpdata", RM.makeHandshake(C.index(types.tuple{types.null(),fixedTapInputType},0),nil,true), inpL)
    local inptaps = R.apply("inptaps", RM.makeHandshake(C.index(types.tuple{types.null(),fixedTapInputType},1)), inpR)
    
    out = R.apply("fread",RM.makeHandshake(RM.freadSeq(inputFilename,R.extractData(inputType)),nil,true),inpdata)
    local hsfninp = out
  
    if tapType~=nil then
      hsfninp = R.apply("HFN",RM.packTuple({inputType,tapType}), R.concat("hsfninp",{out,inptaps}))
    end


    if harnessoption==2 then
      dram = R.instantiateRegistered("dram", RM.dram( R.extractData(fn.inputType.list[2]),10,ramFile))
      table.insert(instances,dram)
      local dramData = R.applyMethod("dramData", dram, "load" )
      hsfninp = R.concat("hsfninp2",{out,dramData})
      --
    end
    
    out = R.apply("HARNESS_inner", fn, hsfninp )

    if harnessoption==2 then
      local daddr = R.selectStream("s1",out,1)
      out = R.selectStream("s0",out,0)
      dramAddr = R.applyMethod("dramAddr", dram, "store",daddr )
    end
  else
    out = R.apply("HARNESS_inner", fn )
  end

  out = R.apply("fwrite", RM.makeHandshake(RM.fwriteSeq(outputFilename,outputType),nil,true), out )

  if harnessoption==2 then
    out = R.statements{out,dramAddr}
  end
  
  return RM.lambda( "harness"..id..tostring(fn):gsub('%W','_'), inpSymb, out, instances )
end)

return function(filename, hsfn, inputFilename, tapType, tapValue, inputType, inputT, inputW, inputH, outputType, outputT, outputW, outputH, underflowTest, earlyOverride, doHalfTest, simCycles, harnessoption, ramFile, X)

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
    local f = terraWrapper(hsfn,inputFilename,inputType,tapType,"out/"..filename..ext..".terra.raw",outputType,i, harnessoption, ramFile)
    f = RM.seqMapHandshake( f, inputType, tapType, tapValue, inputCount, outputCount, false, i, simCycles )
    local Module = f:compile()

    local terra dosim() 
       if DARKROOM_VERBOSE then cstdio.printf("Start CPU Sim\n") end
       var m:&Module = [&Module](cstdlib.malloc(sizeof(Module))); 
       m:init()
       m:reset(); 
       m:process(nil,nil); 
       if DARKROOM_VERBOSE then m:stats();  end
       m:free()
       cstdlib.free(m) 
     end
    
    if DARKROOM_VERBOSE then print("compile terra top") end
    dosim:compile()

    if DARKROOM_VERBOSE then print("Call CPU sim, heap size: "..terralib.sizeof(Module)) end
    dosim()

    if DARKROOM_VERBOSE then fixed.printHistograms() end
  end

end
