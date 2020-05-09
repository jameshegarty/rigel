local R = require "rigel"
local RM = require "generators.modules"
local C = require "generators.examplescommon"
local cstdlib = terralib.includec("stdlib.h", {"-Wno-nullability-completeness"})
local cstdio = terralib.includec("stdio.h", {"-Wno-nullability-completeness"})
local fixed = require "fixed"
local types = require("types")
local J = require "common"
local soc = require "generators.soc"

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)
local ready = macro(function(i) return `i._2 end)

local terraWrapper = J.memoize(function(fn,inputFilename,inputType,tapType,tapValue,outputFilename,outputType,id,harnessoption,ramFile)
  local out
  local inpSymb
  local instances = {}
  local dram, dramAddr
  
  if inputType~=types.null() and inputType:lower():verilogBits()>0 then
    inpSymb = R.input(R.HandshakeTrigger)
    
    out = R.apply( "fread", RM.makeHandshake(RM.freadSeq(inputFilename,R.extractData(inputType)),nil,true), inpSymb )
    local hsfninp = out
    out = R.apply("HARNESS_inner", fn, hsfninp )
  elseif inputType:lower():verilogBits()==0 then
    inpSymb = R.input(R.HandshakeTrigger)
    out = R.apply("HARNESS_inner", fn, inpSymb )
  else
    out = R.apply("HARNESS_inner", fn )
  end

  out = R.apply("fwrite", RM.makeHandshake(RM.fwriteSeq(outputFilename,outputType,nil,false,true),nil,true), out )

  if harnessoption==2 then
    out = R.statements{out,dramAddr}
  end
  
  local res = RM.lambda( "harness"..id..tostring(fn.name):gsub('%W','_'), inpSymb, out, instances )

  return res
end)

return function(filename, hsfn, inputFilename, tapType, tapValue,
                inputType, inputT, inputW, inputH, outputType,
                outputT, outputW, outputH, outputN, outputD,
                underflowTest, earlyOverride, doHalfTest, simCycles, harnessoption, ramFile, X)

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
    local f = terraWrapper(hsfn,inputFilename,inputType,tapType,tapValue,filename..ext..".terra.raw",outputType,i, harnessoption, ramFile)
    local Module = f:toTerra()

    local m = symbol(&Module)
    local valid_in = symbol(tuple(&opaque,bool))
    local valid_out = symbol(tuple(&opaque,bool))
    local incnt = symbol(int)
    
    local callQ, incQ
    if inputType==types.null() then
      callQ = quote m:process(&[valid_out]) end
      incQ = quote end
    else
      callQ = quote m:process(&[valid_in],&[valid_out]) end
      incQ = quote if m.ready and valid([valid_in]) then incnt = incnt+1 end end
    end

    local setTap = quote end

    -- this is a hack to set the tap values on the fake register slave
    if J.keycount( hsfn.requires )==1 then
      for inst,fnmap in pairs(hsfn.requires) do
        for fnname,_ in pairs(fnmap) do
          assert(fnname=="taps")
          setTap = quote var taptmp : inst.module.terraModule
            [inst:terraReference()] = &taptmp end
        end
      end
    else
      assert( J.keycount( hsfn.requires )==0 )
    end


    local terra dosim() 
      if DARKROOM_VERBOSE then cstdio.printf("Start CPU Sim\n") end

      setTap

      var [m] = [&Module](cstdlib.malloc(sizeof(Module))); 
      m:init()
      m:reset();
      
      var [incnt] = 0
      var cnt = 0
      var cycles = 0
      
      while(cnt<outputCount) do
        m:calculateReady(true)
        var [valid_in]
        valid([valid_in])= (incnt < inputCount)
        
        incQ
        var [valid_out]
        valid([valid_out])= false
        
        callQ
        if valid(valid_out) then cnt=cnt+1 end

        var expectedOutputsAtThisPoint : float = ([float](cycles)*outputN)/outputD
        if expectedOutputsAtThisPoint > cnt*16+40960*8 then
          cstdio.printf("Simulation went on for too long, giving up! cycles: %d outputsSeen: %d expectedTotalOutputs:%d inputsSent:%d expectedTotalInputs:%d outputRate:%d/%d\n", cycles, cnt, outputCount, [incnt], inputCount, outputN, outputD )
          cstdlib.exit(1)
        end
        
        cycles = cycles+1
      end
      
      if DARKROOM_VERBOSE then m:stats("TOP");  end
      m:free()
      cstdlib.free(m)

      --cstdio.printf("Terra Cycles %d\n",cycles)
      var f = cstdio.fopen([filename..".terra.cycles.txt"], "w");
      if f==nil then
        cstdio.printf("Error opening file '%s'!\n",[filename..".terra.cycles.txt"]);
        cstdlib.exit(1);
      end
      cstdio.fprintf(f,"%d",cycles)
      cstdio.fclose(f)
    end

    if DARKROOM_VERBOSE then print("compile terra top") end
    dosim:compile()

    if DARKROOM_VERBOSE then print("Call CPU sim, heap size: "..terralib.sizeof(Module)) end
    dosim()

    if DARKROOM_VERBOSE then fixed.printHistograms() end
  end

end
