local IR = require("ir")
local types = require("types")
--local ffi = require("ffi")
local S = require("systolic")
local Ssugar = require("systolicsugar")
local SDFRate = require "sdfrate"
local J = require "common"
local err = J.err
local SDF = require("sdf")
local P = require "params"

-- We can operate in 2 different modes: either we stream frames continuously (STREAMING==true), or we only do one frame (STREAMING==false). 
-- If STREAMING==false, we artificially cap the output once the expected number of pixels is reached. This is needed for some test harnesses
STREAMING = false

local darkroom = {}

-- enable SDF checking? (true:enable, false:disable)
darkroom.SDF = true
darkroom.default_nettype_none = true

darkroom.MONITOR_FIFOS = false
darkroom.AUTO_FIFOS = false
darkroom.THROTTLE_FIFOS = false
darkroom.Z3_FIFOS = false -- use z3 to alloc fifos

-- path to root of rigel repo
darkroom.path = string.sub(debug.getinfo(1).source,2,#debug.getinfo(1).source-9)

DEFAULT_FIFO_SIZE = 2048*16*16

if os.getenv("v") then
  DARKROOM_VERBOSE = true
else
  DARKROOM_VERBOSE = false
end

local function getloc()
  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline.."\n"..debug.traceback()
end

darkroom.VTrigger = types.VTrigger
darkroom.RVTrigger = types.RVTrigger
darkroom.HandshakeTrigger = types.HandshakeTrigger
darkroom.V = types.V
darkroom.RV = types.RV
darkroom.Handshake = types.Handshake
darkroom.HandshakeArray = types.HandshakeArray
darkroom.HandshakeTriggerArray = types.HandshakeTriggerArray
darkroom.HandshakeTuple = types.HandshakeTuple
darkroom.HandshakeArrayOneHot = types.HandshakeArrayOneHot
darkroom.HandshakeTmuxed = types.HandshakeTmuxed
darkroom.isHandshakeArrayOneHot = types.isHandshakeArrayOneHot
darkroom.isHandshakeTmuxed = types.isHandshakeTmuxed
darkroom.isHandshake = types.isHandshake
darkroom.isHandshakeTrigger = types.isHandshakeTrigger
darkroom.isHandshakeArray = types.isHandshakeArray
darkroom.isHandshakeTriggerArray = types.isHandshakeTriggerArray
darkroom.isHandshakeTuple = types.isHandshakeTuple
darkroom.isHandshakeAny = types.isHandshakeAny
darkroom.isV = types.isV
darkroom.isVTrigger = types.isVTrigger
darkroom.isRV = types.isRV
darkroom.isRVTrigger = types.isRVTrigger
darkroom.expectBasic = types.expectBasic
darkroom.expectV = types.expectV
darkroom.expectRV = types.expectRV
darkroom.expectHandshake = types.expectHandshake
darkroom.lower = types.lower
darkroom.extractData = types.extractData
darkroom.hasReady = types.hasReady
darkroom.extractReady = types.extractReady
darkroom.extractValid = types.extractValid
darkroom.streamCount = types.streamCount
darkroom.isStreaming = types.isStreaming
darkroom.isBasic = types.isBasic

-- some basic classes
local SizeFunctions = {}
local SizeMT = {__index=SizeFunctions}
SizeMT.__tostring=function(tab) return "Size("..tostring(tab[1])..","..tostring(tab[2])..")" end
function darkroom.isSize(t) return getmetatable(t)==SizeMT end

local AddressMT = {}
function darkroom.Address(num)
  assert(type(num)=="number")
  return setmetatable({num},AddressMT)
end

-- generator flags
darkroom.Async={} -- generate async (0 cycle delay) module
darkroom.Unoptimized={} -- disable rate optimization (at the instance level, instead of globally)

darkroom.Size = J.memoize(function( w, h, X )
  assert(X==nil)
  local Uniform = require "uniform"
  if darkroom.isSize(w) then
    assert(h==nil)
    return w
  elseif (type(w)=="number" or Uniform.isUniform(w)) and (type(h)=="number" or Uniform.isUniform(h)) then
    return setmetatable({w,h},SizeMT)
  elseif type(w)=="table" and h==nil and w[1]~=nil and w[2]~=nil then
    return darkroom.Size(w[1],w[2])
  else
    err(false, "Passed strange arguments to rigel.Size? w=",w," h=",h)
  end
end)

-- sizes may contain uniforms
function SizeFunctions:eq(a,b)
  local Uniform = require "uniform"
  if darkroom.isSize(a) then
    assert(b==nil)

    local x = Uniform(self[1]):eq( Uniform(a[1]) )
    local y = Uniform(self[2]):eq( Uniform(a[2]) )
    return ( x:And(y) ):assertAlwaysTrue()
  elseif type(a)=="number" and type(b)=="number" then
    return self:eq(darkroom.Size(a,b))
  end
  assert(false)
end

local function discoverName(x)
  local y = 1
  while true do
    local name, value = debug.getlocal(3,y)
    if not name then break end
    --print(name,value)

    if value==x then
      return name
    end
    
    y = y + 1
  end

  for k,v in pairs(_G) do
    if v==x then
      --print("FOUND_G")
      return k
    end
  end
--  return {input=x}    
end

darkroom.__unnamedID = 0

local function typeToKey(t)
  local res = {}

  local Uniform = require "uniform"
  
  for k,v in pairs(t) do
    if type(k)=="number" then
      local outk
      
      if type(v)=="number" then
        outk="number"
      elseif type(v)=="boolean" then
        outk="bool"
      elseif type(v)=="string" then
        outk="string"
      elseif type(v)=="function" then
        outk="luaFunction"
      elseif types.isType(v) then
        outk="type"
      elseif darkroom.isFunction(v) then
        outk="rigelFunction"
      elseif SDF.isSDF(v) then
        outk="rate"
      elseif type(v)=="table" and getmetatable(v)==AddressMT then
        outk="address"
        v=v[1]
      elseif type(v)=="table" and J.keycount(v)==2 and #v==2 and type(v[1])=="number" and type(v[2])=="number" then
        outk="size"
        v = darkroom.Size(v)
      elseif darkroom.isSize(v) then
        outk="size"
      elseif type(v)=="table" and J.keycount(v)==4 and #v==4 and type(v[1])=="number" and type(v[2])=="number"
             and type(v[3])=="number" and type(v[4])=="number" then
        outk="bounds"
      elseif Uniform.isUniform(v) then
        if v:isNumber() then
          outk="number"
          if v.kind=="const" then
            v = v:toNumber()
          else
	    
          end
        else
          J.err("NYI - typeToKey "..tostring(v))
        end
      elseif type(v)=="table" and #t==J.keycount(t) and J.foldl(J.andop,false,J.map(v,darkroom.isInstance)) then
        outk="instanceList"
      elseif v==darkroom.Async then
        outk="async"
        v = true
      elseif v==darkroom.Unoptimized then
        outk="unoptimized"
        v = true
      else
        J.err(false,"unknown type to key? "..tostring(v))
      end
      
      --J.err( res[outk]==nil, "Generator key '"..outk.."' is set twice?" )
      local o_outk = outk
      local i=1
      while res[outk]~=nil do outk=o_outk..tostring(i);i=i+1 end
      res[outk] = v
    else
      J.err( res[k]==nil, "Generator key '"..k.."' is set twice?" )
      res[k] = v
    end
  end
  return res
end

local functionGeneratorFunctions = {}
local functionGeneratorMT={}

-- find how to lift parameterized type Tparam to match Ttarget
local function findLifts( generatorName, fn, Ttarget, Tparam, TparamOutput, X )
  assert(X==nil)
  assert(type(generatorName)=="string")
  J.err( darkroom.isPlainFunction(fn),"findLifts: input function should return plain function, but instead is: ",fn )
  
  --print("findLifts ",generatorName," Target(input):",Ttarget,"ParameterizedTypeInput:",Tparam,"ParameterizedTypeOutput:",TparamOutput)
  
  local finVars = {}
  if Tparam:isSupertypeOf(Ttarget,finVars,"") then
    err(finVars.type==nil,"findLifts: argument 'type' already set? Don't use 'type' as a parameter name")

    err(fn~=nil,"findLifts: generator function returned nil?")

    J.err( fn.inputType==Ttarget,"findLifts: generator '",generatorName,"' returned an input type that doesn't conform to interface it promised? \nTarget Input:",Ttarget," \nPromised Input:",Tparam," \nReturned Input Type:",fn.inputType,"\n",fn)
    J.err( TparamOutput:isSupertypeOf(fn.outputType,{},""), "findLifts: '",generatorName,"' returned an output type that doesn't conform to interface it promised? \npromised:",TparamOutput," \nreturned:",fn.outputType,"\ninputType:",fn.inputType)
    return fn
  else
    --print("Trivial check failed")
  end

  local L = require "generators.lifts"

  -- search through lifts
  local liftsFound = false
  for liftName,lift in pairs(L) do
    local vars1, vars2, vars3 = {},{},{}
  
    local check1 = lift[3]:isSupertypeOf(Ttarget,vars1,"")
    --print("check1",lift[3],"isSupertypeOf",Ttarget, check1)
    local check2 = lift[1]:isSupertypeOf(Tparam,vars2,"")
    --print("check2",lift[1],":isSupertypeOf",Tparam, check2)
    local check3 = lift[2]:isSupertypeOf(TparamOutput,vars3,"")
    --print("check3",lift[2],":isSupertypeOf",TparamOutput, check3)

    --print("Try lift",liftName,check1,check2,check3)

    if check1 and check2 and check3 then
      --print("Apply lift: "..tostring(lift[1]).."->"..tostring(lift[2]).." to "..tostring(lift[3]).."->"..tostring(lift[4]))

      --for kk,vv in pairs(vars1) do print("SPEC",kk,vv) end
      --local spec = lift[3]:specialize(vars1)

      --print("SPECIALIZE",Ttarget,lift[3],spec)
      
      --print("res",Ttarget,spec)
      --err( Ttarget==spec, "Internal error, specialized lift doesn't match target? target:"..tostring(Ttarget).." Specialized:"..tostring(spec) )
      --print("SPECIALIZE",lift[1])
      local newTtarget = lift[1]:specialize(vars1)
      --print("NewTarget:",newTtarget)
      
      liftsFound = true

      local res = findLifts( generatorName, fn, newTtarget, Tparam, TparamOutput )

      if res==nil then
        return nil
      else
        --print("Found lift",liftName,res)
        --print("Because ",lift[3],":isSupertypeOf",Ttarget)
        --print("And ",lift[1],":isSupertypeOf",Tparam)
        --for k,v in pairs(vars2) do print("VARS2",k,v) end
        --for k,v in pairs(vars1) do print("VARS1",k,v) end

        local liftFn = lift[5](vars1)
        return liftFn(res)
      end
    else
      --print("Lift '"..liftName.."' doesn't apply")
      --print(lift[3],"supertypeof?",Ttarget,lift[3]:isSupertypeOf(Ttarget,vars1))
      --print(lift[1],"Supertypeof?",Tparam,lift[1]:isSupertypeOf(Tparam,vars2))
      --print(lift[2],"Supertypeof?",TparamOutput,lift[2]:isSupertypeOf(TparamOutput,vars3))
    end
  end

  --err(liftsFound,"No lifts found?")
  --if liftsFound==false then print("No lifts found?") end

  return nil
end

functionGeneratorMT.__call=function(tab,...)
  local rawarg = {...}

  if darkroom.isIR(rawarg[1]) then -- calling with a value
    local arg
    if #rawarg>1 and rawarg[1].type:is("HandshakeTrigger") then
      -- sort of a hack: handshake trigger can only be made into arrays
      arg = darkroom.concatArray2d(nil,rawarg,#rawarg)
    elseif #rawarg>1 then
      -- collapse multi args into tuple
      arg = darkroom.concat(nil, rawarg)
    else
      arg = rawarg[1]
    end

    if arg.scheduleConstraints~=nil and arg.scheduleConstraints.RV then
      -- early out hack: if schedule pass is done (RV is known, just skip the apply)
      return arg
    end

    local arglist = {}
    for k,v in pairs(tab.curriedArgs) do arglist[k] = v end

    if arglist.type==nil and (tab.requiredArgs.type~=nil or tab.optArgs.type~=nil) then arglist.type = arg.type end
    if arglist.rate==nil and (tab.requiredArgs.rate~=nil or tab.optArgs.rate~=nil) then arglist.rate = arg.rate end

    local rfn = tab:complete(arglist,rawarg[1].loc)

    if arg.scheduleConstraints==nil then -- if we're doing the schedule pass, don't show an error
      err( rfn.inputType==arg.type, "Failed to find a conversion for fn '",rfn.name,"' with \ninput type:'",rfn.inputType,"'\ninput rate ",rfn.sdfInput," \noutput type '",rfn.outputType,"' \nto convert to type:'",arg.type,"' rate:",arg.rate)
    end
    
    return rfn(arg)
  elseif type(rawarg[1])=="table" and #rawarg==1 then
    -- calling with a list of generator params. Either complete, or curry.
    
    local arg = rawarg[1]
    err( J.keycount(arg)>0, "Calling function generator '",tab.name,"' with an empty parameter list?" )
            
    arg = typeToKey(arg)

    local arglist = {}
    for k,v in pairs(tab.curriedArgs) do arglist[k] = v end
    for k,v in pairs(arg) do
      if k=="type" and arg.type1==nil and tab.requiredArgs.type1~=nil then
        -- special case: explicitly passing a type will put it in type1. Fix behavior later
        J.err( arglist.type1==nil or arglist.type1==v, "Argument 'type1' was already passed to function generator '"..tab.name.."'" )
        arglist.type1=v
      elseif k=="rate" and arg.rate1==nil and (tab.requiredArgs.rate1~=nil or tab.optArgs.rate1~=nil) then
        -- special case: explicitly passing a type will put it in type1. Fix behavior later
        J.err( arglist.rate1==nil or arglist.rate1==v, "Argument 'rate1' was already passed to function generator '"..tab.name.."'" )
        arglist.rate1=v
      else
        J.err( arglist[k]==nil or arglist[k]==v, "Argument '"..k.."' was already passed to function generator '"..tab.name.."', prev:",arglist[k]," new:",v )
        arglist[k] = v
      end
    end

    -- Hack: if this module is parametric (inputType~=unknown), we need to have the input before we run it
    if tab:checkArgs(arglist) then
      return tab:complete(arglist)
    else
      -- not done yet, return curried generator
      local res = darkroom.FunctionGenerator( tab.name, tab.requiredArgs, tab.optArgs, tab.completeFn, tab.inputType, tab.optimized )
      res.curriedArgs = arglist
      return res
    end
  elseif tab.inputType~=nil and types.Interface():isSupertypeOf(tab.inputType,{},"") then
    err(#rawarg==0,"Calling a nullary function with an argument?")

    local arglist = {}
    for k,v in pairs(tab.curriedArgs) do arglist[k] = v end
    if arglist.type==nil and (tab.requiredArgs.type~=nil or tab.optArgs.type~=nil) then arglist.type = types.Interface() end
    if arglist.rate==nil and (tab.requiredArgs.rate~=nil or tab.optArgs.rate~=nil) then arglist.rate = SDF{1,1} end

    return tab:complete(arglist)()
  else
    J.err(false, "Called function generator '"..tab.name.."' with something other than a Rigel value or table ("..tostring(rawarg[1])..")? Make sure you call function generator with curly brackets {} ")
  end
end
functionGeneratorMT.__tostring=function(tab)
  local res = {}
  table.insert(res,"Function Generator "..tab.name)
  table.insert(res,"  Input Type: "..tostring(tab.inputType))
  table.insert(res,"  Output Type: "..tostring(tab.outputType))
  table.insert(res,"  Required Args:")
  for k,v in pairs(tab.requiredArgs) do table.insert(res,"    "..k) end
  table.insert(res,"  Curried Args:")
  for k,v in pairs(tab.curriedArgs) do table.insert(res,"    "..k) end
  table.insert(res,"  Optional Args:")
  for k,v in pairs(tab.optArgs) do table.insert(res,"    "..k) end
  return table.concat(res,"\n")
end
functionGeneratorMT.__index = functionGeneratorFunctions


-- this will specialize the generator to the given type. It must return a plain function.
-- This function may fail to return you exactly what you want, but it will try, and return something.
-- convert: should we add conversion functions to get exactly what you want? default true
function functionGeneratorFunctions:specializeToType( ty, rate, convert )
  err( types.isType(ty),"specializeToType: first arg should be a type, but is: ",ty)
  err( ty:isInterface(),"specializeToType: first arg should be interface type, but is: ",ty)
  err( SDFRate.isSDFRate(rate),"specializeToType: second arg should be a rate, but is: ",rate)
  local arglist = {}

  if self.requiredArgs.type~=nil then
    if self.curriedArgs.type~=nil then
      if self.curriedArgs.type~=ty then
        print("specializeToType error: type was already set to something different")
        return nil
      end
    else
      arglist.type = ty
    end
  end

  if self.requiredArgs.rate~=nil or self.optArgs.rate~=nil then
    if self.curriedArgs.rate~=nil then
      if self.curriedArgs.rate~=rate then
        print("specializeToType error: rate was already set to something different")
        return nil
      end
    else
      arglist.rate = rate
    end
  end

  if self:checkArgs(arglist)==false then
    print("Could not specialize '",self.name,"' to type, missing args")
    for k,v in pairs(self.requiredArgs) do
      if self.curriedArgs[k]==nil and arglist[k]==nil then print("Requires argument '"..k.."'") end
    end

    return nil
  end

  for k,v in pairs(self.curriedArgs) do
    assert(arglist[k]==nil)
    arglist[k] = v
  end
  

  return self:complete( arglist, nil, convert )
end

-- return true if done, false if not done
function functionGeneratorFunctions:checkArgs(arglist)
  local reqArgs = {}
  
  for k,v in pairs(arglist) do
    if self.requiredArgs[k]==nil and self.optArgs[k]==nil then
      print("Error, arg '"..k.."' is not in list of required or optional args on function generator '"..self.name.."'!" )
      print("Required Args: ")
      for k,v in pairs(self.requiredArgs) do print(k..",") end
      print("Curried Args: ")
      for k,v in pairs(self.curriedArgs) do print(k..",") end
      assert(false)
    elseif self.requiredArgs[k]~=nil then
      reqArgs[k]=1
    end
    -- if it's optional, we don't care: we're only checking if all required args are set
  end

  for k,v in pairs(self.curriedArgs) do
    if arglist[k]~=nil and arglist[k]~=v then
      print("error, '",self.name,"' overrided a curried arg with another value? k:",k," curried:",v," passed:",arglist[k])
      return false
    end
    if self.requiredArgs[k]~=nil then
      reqArgs[k] = 1
    end
  end
  
  return J.keycount(reqArgs)==J.keycount(self.requiredArgs)
end

function functionGeneratorFunctions:listRequiredArgs()
  local s = {}
  for k,v in pairs(self.requiredArgs) do if self.curriedArgs[k]==nil then table.insert(s,k) end end
  return table.concat(s,",")
end

-- does this generate require the arg 'arg'? (returns true if either required or optional)
function functionGeneratorFunctions:requiresArg(arg)
  assert(type(arg)=="string")
  return (self.requiredArgs[arg]~=nil or self.optArgs[arg]~=nil) and (self.curriedArgs[arg]==nil)
end

-- top level function that implements logic to convert a fn to a given type.
-- If this fails, it just returns fn
darkroom.convertInterface = J.memoize(function( fn, targetInputTypeOrig, targetInputRateOrig, loc, X )
  assert( X==nil )
  assert( types.isType(targetInputTypeOrig) )
  err( SDF.isSDF(targetInputRateOrig), "convertInterfaces SDF should be SDF but is: ", targetInputRateOrig )

--  print("CONVERT_INTERFACE ",targetInputTypeOrig, targetInputRateOrig," TO ", fn.inputType, fn.sdfInput, fn.name )

  -- nothing to do!
  if fn.inputType == targetInputTypeOrig then
return fn
  end
  
  local G = require "generators.core"
  local C = require "generators.examplescommon"
  local RM = require "generators.modules"
  
  local functionStack = {}

  err( targetInputTypeOrig:deSchedule()==fn.inputType:deSchedule(), "convertInterface: unscheduled types don't even match! nothing we can do. Converting ",targetInputTypeOrig," to ",fn.inputType," unscheduled ",targetInputTypeOrig:deSchedule()," to ",fn.inputType:deSchedule())
  
  -- does this require a space-time conversion?
  local function reshape( fnType, targetType )
    err( fnType:isSchedule(), "reshape: input should be schedule type, but is: ",fnType )
    assert( targetType:isSchedule() )
    
    local res
    
    if fnType:isArray() then
      -- if not an array, nothing we can do!
      if fnType.V[1]*fnType.V[2] ~= targetType.V[1]*targetType.V[2] then
        -- we need to serialize

        local resStack = {}

        local fnTypeShadow, targetTypeShadow = fnType, targetType

        -- we're deser: need to go from inner to outer
        if targetTypeShadow:arrayOver()~=fnTypeShadow:arrayOver() and fnTypeShadow.V[1]*fnTypeShadow.V[2]>targetTypeShadow.V[1]*targetTypeShadow.V[2] then
          table.insert( resStack, RM.mapSeq(reshape( fnTypeShadow.over, targetTypeShadow.over ), fnType.size[1], fnType.size[2]) )
          assert( darkroom.isPlainFunction(resStack[#resStack]) )
          targetTypeShadow = resStack[#resStack].outputType:deInterface()
        end

        if fnTypeShadow:rowMajor() and targetTypeShadow:rowMajor() then
          table.insert( resStack, C.ChangeRateRowMajor( targetTypeShadow:arrayOver(), targetTypeShadow.V[1], targetTypeShadow.V[2],
                                        fnTypeShadow.V[1]*fnTypeShadow.V[2],
                                        targetTypeShadow.size[1], targetTypeShadow.size[2] ) )
          assert( darkroom.isPlainFunction(resStack[#resStack]) )
        elseif fnTypeShadow:columnMajor() or targetTypeShadow:columnMajor() then
          --err( false,"NYI - convertInterface to a column major array converting:",targetType," to:",fnType," for:",fn,loc)
          err( targetTypeShadow.V[2]==fnTypeShadow.V[2],"NYI - column major change rate with different array height. Converting ",targetTypeShadow," to ",fnTypeShadow)
          table.insert( resStack, RM.changeRate( targetTypeShadow:arrayOver(), fnTypeShadow.V[2], targetTypeShadow.V[1], fnTypeShadow.V[1], true, fnTypeShadow.size[1], fnTypeShadow.size[2] ) )
          assert( darkroom.isPlainFunction(resStack[#resStack]) )
        else
          J.err("converting between strange vector sizes! ",targetTypeShadow," to ",fnTypeShadow)
        end

        -- we're ser: need to go from outer to inner
        if targetTypeShadow:arrayOver()~=fnTypeShadow:arrayOver()  and fnTypeShadow.V[1]*fnTypeShadow.V[2]<targetTypeShadow.V[1]*targetTypeShadow.V[2] then
          table.insert( resStack, RM.mapSeq(reshape( fnTypeShadow.over, targetTypeShadow.over ), fnTypeShadow.size[1], fnTypeShadow.size[2]) )
          assert( darkroom.isPlainFunction(resStack[#resStack]) )
          targetTypeShadow = resStack[#resStack].outputType:deInterface()
        end

        if #resStack==1 then
          res = resStack[1]
        else
          J.err( #resStack>0,"bad fn stack? converting ",fnType," to ",targetType )
          res = C.linearPipeline(resStack,"ConvertInterface_Ser_stack_"..tostring(fnType).."_"..tostring(targetType))
        end
      elseif fnType.V==targetType.V  and  fnType:arrayOver()~=targetType:arrayOver() then
        -- recurse
        if fnType.V:eq(0,0) then
          if fnType.var then
            res = RM.mapVarSeq( reshape( fnType.over, targetType.over ), fnType.size[1], fnType.size[2] )
          else
            res = RM.mapSeq( reshape( fnType.over, targetType.over ), fnType.size[1], fnType.size[2] )
          end
        else
          print("NYI - ", targetType, " to ", fnType )
          assert(false)
        end
      elseif fnType.V==targetType.V  and
        fnType:arrayOver()==targetType:arrayOver() then
          -- nothing to do!
      else
        J.err(false,"convertInterface NYI - convert ",fnType," to ",targetType," calling function:",fn.name,loc)
      end
    elseif fnType:isTuple() then
      assert( targetType:isTuple() and #fnType.list==#targetType.list )

      res = G.Function{"FannedConvertInterface_"..tostring(targetType).."_"..tostring(fnType), types.RV(targetType), SDF{1,1},
        function(inp)
          local tmp = RM.broadcastStream( targetType, #targetType.list)(inp)
          local out = {}
          for k,v in ipairs(targetType.list) do
            local i = darkroom.selectStream( "str"..k, tmp, k-1 )
            i = RM.makeHandshake(C.index( targetType, k-1 ))(i)
            i = C.fifo( v, 128, nil, nil, nil, nil, "fannedconvertInterface_"..tostring(k))(i)

            local rec = reshape( fnType.list[k], v )

            if rec==nil then
              -- this is OK: means no change
              table.insert( out, i )
            else
              local recres = rec(i)
              recres = C.fifo( recres.type:deInterface(), 128, nil, nil, nil, nil, "fannedconvertInterface_"..tostring(k))(recres)
              table.insert( out, recres )
              assert( out[#out].type:deInterface()==fnType.list[k] )
            end
          end

          local rrr = darkroom.concat(out)
          
          local ptList = {}
          for k,v in ipairs( fnType.list) do table.insert(ptList,types.RV(v)) end
          return RM.packTuple( ptList )(rrr)
        end}
    end

    if res~=nil then
      err( res.inputType==types.RV(targetType), "convertInterface: conversion function input type should have been: ",types.RV(targetType)," but was: ",res.inputType )
      err( res.outputType==types.RV(fnType), "convertInterface: conversion function output type should have been: ",types.RV(fnType)," but was: ",res.outputType,". input type should be: ",types.RV(targetType),", and was correct." )
    else
      err( targetType==fnType, "convertInterface: conversion function returned noop, but should have been conversion from ",targetType," to ",fnType )
    end
    
    return res
  end

  local targetInputType = targetInputTypeOrig
  local targetInputRate = targetInputRateOrig
  
  -- rate optimization
  if targetInputType:deInterface()~=fn.inputType:deInterface() then
    if targetInputType:isArray() then
      -- RV()[N] optimization
      err( fn.inputType:isArray(), "ConvertInterface NYI = if input is array of interfaces, so must output be. target: ",targetInputType," to ",fn.inputType )
      err( targetInputType.size==fn.inputType.size, "ConvertInterface NYI = if input is array of interfaces, size must match. target: ",targetInputType," to ",fn.inputType )
      assert( targetInputType.over:is("Interface") )
      
      local res = RM.mapOverInterfaces( reshape( fn.inputType.over.over, targetInputType.over.over ), targetInputType.size[1], targetInputType.size[2] )
      
      table.insert( functionStack, res )
    elseif targetInputType:isTuple() then
      -- {RV(),RV()} optimization

      -- NOTE: at this point, the fn may expect a rv, not a RV, but we don't do that conversion yet! First: make the rates match
      --err( fn.inputType:isTuple(), "ConvertInterface NYI = if input is tuple of interfaces, so must output be. target: ",targetInputType," to ",fn.inputType )

      err( #targetInputType:deInterface().list==#fn.inputType:deInterface().list, "ConvertInterface NYI = if input is tuple of interfaces, size of tuple must match. target: ",targetInputType," to ",fn.inputType )
      assert( targetInputType.list[1]:is("Interface") )

      local res = G.Function{"TupleConvertInterface_"..tostring(targetInputType).."_"..tostring(fn.inputType), targetInputType, targetInputRate,
        function(inp)
          local out = {}
          for k,v in ipairs(targetInputType:deInterface().list) do
            local i = darkroom.selectStream( "str"..k, inp, k-1 )

            local rec = reshape( fn.inputType:deInterface().list[k], v )

            if rec==nil then
              -- this is OK: means no change
              table.insert( out, i )
            else
              local recres = rec(i)
              table.insert( out, recres )
              assert( out[#out].type:deInterface()==fn.inputType:deInterface().list[k] )
            end
          end

          local rrr = darkroom.concat(out)
          
          return rrr
        end}

      -- hack: tell the FIFO check code that streams are not mixed
      res.fifoStraightThrough = true
      
      table.insert( functionStack, res )
    else
      -- simple case of RV(T1) to RV(T2)
      err( targetInputType:is("Interface") and fn.inputType:is("Interface"),"ConvertInterface NYI - must both be single interfaces, but is conversion from ",targetInputType," to ",fn.inputType )

      local res = reshape( fn.inputType.over, targetInputType.over )

      if res~=nil then
        table.insert( functionStack, res )
      end
    end
  end

  --local liftTargetInputType = targetInputType
  --local liftTargetInputRate = targetInputRate
  if #functionStack>0 then
    targetInputType = functionStack[#functionStack].outputType
    targetInputRate = functionStack[#functionStack].sdfOutput
  end

  -- convert tuples of interfaces to interfaces of tuples, AFTER RATE MATCHING
  -- this has to happen after rate matching, because after this conversion, the whole bundle will have 1 rate!
  -- but some of the S-T conversions may require you to mess with individual (multiple) rates
  if targetInputType:isTuple() and fn.inputType:isrv() and fn.inputType.over:isTuple() then
    -- this means we are converting <RV(a),RV(b)> to rv({a,b}), by doing a packtuple
    table.insert( functionStack, RM.packTuple( targetInputType.list ) )
    targetInputType = functionStack[#functionStack].outputType
  end
  

  J.err( targetInputType:deInterface()==fn.inputType:deInterface(),"Reshape failed: function has input type: ",fn.inputType," but reshape returned type: ", targetInputType )

  --J.err( liftTargetInputRate==fn.sdfInput, "Reshape failed: function has input rate: ",fn.sdfInput," but reshaped returned rate: ", liftTargetInputRate )

  local mod = findLifts( fn.name, fn, targetInputType, fn.inputType, fn.outputType )

  if mod~=nil then
    table.insert( functionStack, mod )
  else
    table.insert( functionStack, fn )
  end

  if #functionStack==1 then
    return functionStack[1]
  else
    local res = C.linearPipeline( functionStack, "convertInterface_"..tostring(targetInputTypeOrig).."_to_"..tostring(fn.inputType).."_"..fn.name, targetInputRateOrig )
    return res
  end
end)

-- this function either returns a plain function, or fails
-- This may not return a function with exactly the type you asked for! You need to check for that!
-- convert: should we add conversion functions to get exactly the type you want? default true
function functionGeneratorFunctions:complete( arglist, loc, convert, X )
  assert( X==nil )
  
  if DARKROOM_VERBOSE then print("FunctionGenerator:complete() ",self.name) end


  if self:checkArgs(arglist)==false then
    print("Function generator '"..self.name.."' is missing arguments!")
    for k,v in pairs(self.requiredArgs) do
      if arglist[k]==nil and self.curriedArgs[k]==nil then print("Requires argument '"..k.."'") end
    end
    assert(false)
  end

  -- don't mutate input!
  local a = {}
  for k,v in pairs(arglist) do a[k]=v end

  for k,v in pairs(self.curriedArgs) do
    err( arglist[k]==nil or arglist[k]==v, ":complete() ",self.name,", value in arglist was already in curried args? k ",k," v ",v," prev ",arglist[k] )
    a[k] = v
  end

  if self.optimized and arglist.rate~=nil and arglist.type~=nil and arglist.unoptimized~=true then
    a.type, a.rate = arglist.type:optimize( arglist.rate )
    assert( types.isType(a.type) )
    assert( SDF.isSDF(a.rate) )
  end

  if self.inputType~=nil and self.inputType~=types.Unknown then
    local newlist = {}
    
    err( self.inputType:isSupertypeOf( a.type:deInterface(), newlist, "" ), "Input type to generator '",self.name,"' is incorrect!, expected: ",self.inputType," passed:", arglist.type, " which is deinterfaced/optimized into type: ", a.type:deInterface()," optimized:",self.optimized)

    for k,v in pairs(newlist) do
      assert(a[k]==nil)
      a[k] = v
    end
  end

  local fn = self.completeFn( a )
  J.err( darkroom.isPlainFunction(fn), "function generator '",self.name,"' returned something other than a plain rigel function? returned:",fn )

  if self.requiredArgs.type~=nil and self.requiredArgs.rate~=nil and convert~=false then -- if we don't know type, we can't lift
    fn = darkroom.convertInterface( fn, arglist.type, arglist.rate )
    --J.err( fn.inputType == arglist.type, "convertInterface Fail wanted: ",arglist.type," returned: ",fn.inputType )
  end
  
  fn.generator = self
  fn.generatorArgs = arglist

  if DARKROOM_VERBOSE then print("FunctionGenerator:complete() DONE,TRIVIAL",self.name) end

  return fn
end

-- optimized: should input type be optimized before being passed to completeFn?
function darkroom.FunctionGenerator( name, requiredArgs, optArgs, completeFn, inputType, optimized, X )
  assert(X==nil)
  err( type(name)=="string", "FunctionGenerator: name must be string, but is: "..tostring(name) )
  err( type(requiredArgs)=="table", "FunctionGenerator: requiredArgs must be table, but is: "..tostring(requiredArgs) )
  if J.keycount(requiredArgs)==#requiredArgs then
    -- convert array of names to set
    requiredArgs = J.invertTable(requiredArgs)
  end 
  for k,v in pairs(requiredArgs) do J.err( type(k)=="string", "FunctionGenerator: requiredArgs must be set of strings" ) end
  err( type(optArgs)=="table", "FunctionGenerator: requiredArgs must be table" )
  if J.keycount(optArgs)==#optArgs then optArgs = J.invertTable(optArgs) end -- convert array of names to set
  for k,v in pairs(optArgs) do J.err( type(k)=="string", "FunctionGenerator: optArgs must be set of strings" ) end
  optArgs.unoptimized = 1
  err( type(completeFn)=="function", "FunctionGenerator: completeFn must be lua function" )

  if optimized==nil then optimized=true end
  err( type(optimized)=="boolean", "FunctionGenerator: 'optimized' should be boolean, but is: ", optimized )
  
  if inputType==nil or inputType==types.Unknown then
    inputType=types.Unknown
  else
    err(types.isType(inputType) or P.isParam(inputType),"FunctionGenerator, type should be type, but is: "..tostring(inputType))

    requiredArgs.type=true
    requiredArgs.rate=true
  end

  return setmetatable( {name=name, requiredArgs=requiredArgs, optArgs=optArgs, completeFn=completeFn, curriedArgs={}, inputType=inputType, optimized=optimized }, functionGeneratorMT )
end

function darkroom.isFunctionGenerator(t) return (getmetatable(t)==functionGeneratorMT) or darkroom.isModuleGeneratorInstanceCallsite(t) end

local function buildAndCheckSystolicModule( tab, isModule )
  if DARKROOM_VERBOSE then print("buildAndCheckSystolicModule",tab.name) end
  -- build the systolic module as needed
  err( rawget(tab, "makeSystolic")~=nil, "missing makeSystolic() for "..J.sel(isModule,"module","function").." '"..tab.name.."'" )
  local sm = rawget(tab,"makeSystolic")()
  if Ssugar.isModuleConstructor(sm) then sm:complete(); sm=sm.module end
  J.err( S.isModule(sm),"makeSystolic didn't return a systolic module? Returned '",sm,"'. Module: ",tab)

  if DARKROOM_VERBOSE then print("buildAndCheckSystolicModule","CHECK",tab.name) end
  
  local systolicFns = sm.functions
  local rigelFns = tab.functions
  if isModule==false then
    systolicFns={["process"]=sm.functions.process}
    rigelFns = {["process"]=tab}
  end

  err( tab.name==sm.name, "systolic module name doesn't match rigel module name! rigelName:'",tab.name,"' systolicName:'",sm.name,"'")
  
  for fnname,rigelFn in pairs(rigelFns) do
    local systolicFn = systolicFns[fnname]

    err( systolicFn~=nil, "systolic module function is missing (",sm.name,")")

    -- LUTS contain brams, which aren't 'pure' (whatever that means), but they also aren't really 'stateful'
    -- they have no reset or carried state
    --err( systolicFn:isPure()~=rigelFn.stateful,"Error, rigel module '",tab.name,"' fn '",fnname,"' was declared with stateful=",rigelFn.stateful," but systolic function isPure=",systolicFn:isPure())
         
    if rigelFn.outputType==types.Interface() then
    else
      err( systolicFn.output~=nil, "module '",tab.name,"' output is not null (is ",rigelFn.outputType,", lowered to: ",rigelFn.outputType:lower(),"), but systolic output is missing")
      err( darkroom.lower(rigelFn.outputType)==systolicFn.output.type, "systolic module output type wrong on module '",tab.name,"'? systolic output is '",systolicFn.output.type,"' but should be '",darkroom.lower(rigelFn.outputType),"' (because rigel type is ",rigelFn.outputType,")" )
    end

    local shouldHaveCE = (types.isHandshakeAny(rigelFn.inputType) or types.isHandshakeAny(rigelFn.outputType))==false and (rigelFn.stateful or (rigelFn.delay~=nil and rigelFn.delay>0)) and (rigelFn.inputType==types.Interface() and rigelFn.outputType==types.Interface())==false
    err( shouldHaveCE==(systolicFn.CE~=nil), "Systolic function CE doesn't match rigel definition. Module '",tab.name,"' fn '",fnname,"'. rigelFn.stateful=",rigelFn.stateful," rigelFn.delay=",rigelFn.delay," rigelFn.inputType=",rigelFn.inputType," shouldHaveCE=",shouldHaveCE," systolicCE:",systolicFn.CE)
      
    if types.isHandshakeAny(rigelFn.inputType) or types.isHandshakeAny(rigelFn.outputType) then
      local readyName = fnname.."_ready"
      if isModule==false then readyName="ready" end
      
      err( sm.functions[readyName]~=nil, "module '"..tab.name.."' ready function '"..readyName.."' missing?")

      local expectedInputReady = darkroom.extractReady(rigelFn.inputType)
      local expectedOutputReady = darkroom.extractReady(rigelFn.outputType)

      err( sm.functions[readyName]~=nil,"missing ready fn?")
      err( rigelFn.inputType==types.Interface() or sm.functions[readyName].output~=nil,"ready fn '"..readyName.."' has no output? module: ",rigelFn)

      if rigelFn.inputType~=types.Interface() then
        err( expectedInputReady==sm.functions[readyName].output.type, "module '"..tab.name.."' systolic ready '",readyName,"' output type wrong. Systolic ready output type is '",sm.functions[readyName].output.type,"', but should be '",expectedInputReady,"', because Rigel function input type is '",rigelFn.inputType,"'.")
      end

      if rigelFn.outputType~=types.Interface() then
        err( rigelFn.outputType==types.Interface() or expectedOutputReady==sm.functions[readyName].inputParameter.type, "module '",tab.name,"' systolic ready '",readyName,"' input type wrong. Systolic ready input type is '",sm.functions[readyName].inputParameter.type,"', but should be '",darkroom.extractReady(rigelFn.outputType),"', because Rigel function output type is '",rigelFn.outputType,"'.")
      end
      --elseif (rigelFn.inputType==types.Interface() and rigelFn.outputType==types.Interface())==false and rigelFn.outputType:isrv() then
    elseif rigelFn.inputType~=types.Interface() or rigelFn.outputType~=types.Interface() then
      err( type(rigelFn.delay)=="number","Error, rigel module missing delay? fnname '",fnname,"' should have been caught earlier ",tab)
      err( sm:getDelay(fnname)==rigelFn.delay, "Error, rigel module '",tab.name,"' fn '",fnname,"' was declared with delay=",rigelFn.delay," but systolic function delay is:",sm:getDelay(fnname)," Module ",sm)      
    end

    local expectedInput = types.lower(rigelFn.inputType,rigelFn.outputType)
    err( expectedInput==systolicFn.inputParameter.type, "systolic module input type wrong? fnname:'",fnname,"' module:'",tab.name,"' Rigel input type:",rigelFn.inputType," Rigel Lowered:",expectedInput," module type:",systolicFn.inputParameter.type )
    
  end

  err( (sm.functions.reset~=nil)==tab.stateful, "Modules must have reset iff the module is stateful (module "..tab.name.."). stateful:"..tostring(tab.stateful).." hasReset:"..tostring(sm.functions.reset~=nil))
  
  for inst,lst in pairs(sm.externalInstances) do
    for _,fnname in ipairs(lst) do
      local found = false

      for ic,_ in pairs(tab.requires) do if ic.instance.name==inst.name and ic.functionName==fnname then found=true end end
      for ic,_ in pairs(tab.provides) do if ic.instance.name==inst.name and ic.functionName==fnname then found=true end end
      err( found, "makeSystolic(): systolic module '"..sm.name.."' refers to external instance '"..inst.name.."', but rigel module doesn't?")
    end
  end

  for inst,fnmap in pairs(tab.requires) do
    err( sm.externalInstances[inst:toSystolicInstance()]~=nil, "Rigel module '"..tab.name.."' requires instance '"..inst.name.."', but it's missing from systolic module external list? ")
    for fnname,_ in pairs(fnmap) do
      err( sm.externalInstances[inst:toSystolicInstance()][fnname]~=nil, "Rigel module requires instance, but it's missing from systolic module? ")

      local fn = inst.module.functions[fnname]
      if types.isHandshakeAny(fn.inputType) or types.isHandshakeAny(fn.outputType) then
        err( sm.externalInstances[inst:toSystolicInstance()][fnname.."_ready"]~=nil, "Rigel module '"..tab.name.."' requires instance callsite '"..inst.name..":"..fnname.."()', but its ready fn is missing from systolic module external list? ")
      end
    end
  end
  
  rawset(tab,"systolicModule", sm )

  if DARKROOM_VERBOSE then print("buildAndCheckSystolicModule","DONE",tab.name) end
  return sm
end

function buildAndCheckTerraModule(tab)
  err( rawget(tab, "makeTerra")~=nil, "missing terraModule, and 'makeTerra' doesn't exist on module '",tab.name,"'" )
  err( type(rawget(tab, "makeTerra"))=="function", "'makeTerra' function not a lua function, but is "..tostring(rawget(tab, "makeTerra")) )
  local tm = rawget(tab,"makeTerra")()
  err( terralib.types.istype(tm) and tm:isstruct(), "makeTerra for module '",tab.name,"' returned something other than a terra struct? returned: ",tm)

  rawset(tab,"terraModule", tm )
  return tm
end

local darkroomFunctionFunctions = {}
local darkroomFunctionMT = {
__index=function(tab,key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  v = darkroomFunctionFunctions[key]
  if v~=nil then return v end

  if key=="systolicModule" then
    return buildAndCheckSystolicModule(tab,false)
  elseif key=="terraModule" then
    return buildAndCheckTerraModule(tab)
  end
end,
__call=function(tab,...)
  local rawarg = {...}

  for _,arg in pairs(rawarg) do
    J.err( arg==nil or darkroom.isIR(arg),"Input argument to rigel function '",tab.name,"' must be a rigel value, but is:'",arg,"'")

    -- discover variable name from lua
    if arg~=nil and arg.defaultName then
      local n = discoverName(arg)
      if n~=nil then
        arg.name=n.."_"..darkroom.__unnamedID
        darkroom.__unnamedID = darkroom.__unnamedID+1
        arg.defaultname=false
      end
    end
  end

  local arg
  if #rawarg>1 and rawarg[1].type:is("HandshakeTrigger") then
    -- sort of a hack: handshake trigger can only be made into arrays
    arg = darkroom.concatArray2d(nil,rawarg,#rawarg)
  elseif #rawarg>1 then
    arg = darkroom.concat(nil,rawarg)
  else
    arg = rawarg[1]
  end
  
  local res = darkroom.apply(J.sanitize("un"..darkroom.__unnamedID.."_"..tab.name:sub(1,20)), tab, arg)
  res.defaultName=true
  darkroom.__unnamedID = darkroom.__unnamedID+1
  return res
end,
__tostring=function(mod,longform)
  local res = {}

  local mt = getmetatable(mod)
  setmetatable(mod,nil)
  local tabstr = tostring(mod)
  setmetatable(mod,mt)

  if darkroom.isPlainFunction(mod) then
    table.insert(res,"* Plain Rigel Function "..mod.name.." ("..tabstr..")")
  else
    table.insert(res,"* Rigel Function "..mod.name.." ("..tabstr..")")
  end
  
  table.insert(res,"  InputType: "..tostring(mod.inputType))
  table.insert(res,"  OutputType: "..tostring(mod.outputType))

  if SDFRate.isSDFRate(mod.sdfInput) then
    table.insert(res,"  InputSDF: "..tostring(mod.sdfInput))
  else
    table.insert(res,"  InputSDF: Not an SDF rate?")
  end

  if SDFRate.isSDFRate(mod.sdfOutput) then
    table.insert(res,"  OutputSDF: "..tostring(mod.sdfOutput))
  else
    table.insert(res,"  OutputSDF: Not an SDF rate?")
  end

  table.insert(res,"  Stateful: "..tostring(mod.stateful))
  table.insert(res,"  Delay: "..tostring(mod.delay))
  table.insert(res,"  InputBurstiness: "..tostring(mod.inputBurstiness))
  table.insert(res,"  OutputBurstiness: "..tostring(mod.outputBurstiness))
  
  table.insert(res,"  Metadata:")
  for k,v in pairs(mod.globalMetadata) do
    table.insert(res,"    "..tostring(k).." = "..tostring(v))
  end

  if J.keycount(mod.requires)>0 then
    table.insert(res,"  Requires:")
    for inst,fnlist in pairs(mod.requires) do
      for fn,_ in pairs(fnlist) do
        table.insert(res,"    "..inst.name..":"..fn.."()")
      end
    end
  else
    table.insert(res,"  Requires: (none)")
  end

  if J.keycount(mod.provides)>0 then
    table.insert(res,"  Provides:")
    for inst,fnlist in pairs(mod.provides) do
      for fn,_ in pairs(fnlist) do
        table.insert(res,"    "..inst.name..":"..fn.."()")
      end
    end
  else
    table.insert(res,"  Provides: (none)")
  end

  if mod.kind=="lambda" then
    if J.keycount(mod.instanceMap)==0 then
      table.insert(res,"  Internal Instances: (none)")
    else
      table.insert(res,"  Internal Instances:")
      for inst,_ in pairs(mod.instanceMap) do
        table.insert(res,"    "..inst.name..":"..inst.module.name)
      end
    end

    if longform then
      local liveTracks = {}
      local maxTracks = 4
      local function addTracks(N)
        local Ninp = N
        local atres = {}
        for k,v in ipairs(liveTracks) do
          if v==false and N>0 then
            liveTracks[k] = true
            table.insert(atres,k)
            N = N-1
          end
        end

        while N>0 do
          table.insert(liveTracks,true)
          table.insert(atres,#liveTracks)
          N = N-1
        end

        J.err( #atres==Ninp,"Add tracks",Ninp,#atres )
        return atres
      end
      
      mod.output:visitEach(
        function(n,arg)
          local tres
          if n.kind=="input" then
            tres = addTracks(n.type:streamCount())
          elseif n.kind=="concat" then
            tres = {}
            for k,v in ipairs(arg) do
              assert(#v==1)
              tres[k] = v[1]
            end
          elseif n.kind=="selectStream" then
            J.err(arg[1][n.i+1]~=nil,"selectstream bug?",n.i,#arg)
            tres = {arg[1][n.i+1]}
          elseif #n.inputs==1 and n.inputs[1].type:streamCount()==1 and n.type:streamCount()>1 then
            -- fan out
            J.err(type(arg[1][1])=="number","arg should be number, but is:",#arg,arg[1][1])
            tres = {arg[1][1]}
            local tmp = addTracks(n.type:streamCount()-1)
            for k,v in ipairs(tmp) do
              assert(type(v)=="number")
              table.insert(tres,v)
            end

            for k,v in ipairs(tres) do
            J.err(type(v)=="number","Xres should be number but is",v,n,"#inp ",#n.inputs,"stcnt:",n.type:streamCount(),"#tres",#tres,"k",k)
          end

          elseif #n.inputs==1 and n.inputs[1].type:streamCount()>1 and n.type:streamCount()==1 then
            -- fan in
            tres = {arg[1][1]}
            for i=2,#arg[1] do
              liveTracks[arg[1][i]]=false
            end
          elseif #n.inputs==1 and n.inputs[1].type:streamCount() == n.type:streamCount() then
            tres = {}
            for k,v in ipairs(arg[1]) do
              table.insert(tres,v)
            end
          else
            J.err(false,"coult not handle node",n)
          end

          J.err(#tres==n.type:streamCount(),"streamcount doesn't match",#tres,n.type:streamCount(),n)
          for k,v in ipairs(tres) do
            J.err(type(v)=="number","res should be number but is",v,n,"#inp ",#n.inputs,"stcnt:",n.type:streamCount(),"#tres",#tres,"k",k)
          end
          
          local track = ""
          for i=1,math.max(maxTracks,#liveTracks) do
            local thist = false
            for k,v in ipairs(tres) do if v==i then thist=true end end

            if thist then
              track = track.."*"    
            elseif liveTracks[i] then
              track = track.."|"
            else
              track = track.." "
            end
            track = track.."  "
          end

          table.insert(res,"** "..track..n:tostringPlain())
          --          table.insert(res,tostring(n))
          
          return tres
        end)

      table.insert(res,"** return "..mod.output.name)
    end
  end
  
  return table.concat(res,"\n").."\n"
end
}

function darkroomFunctionFunctions:tostringLong()
  return darkroomFunctionMT.__tostring(self,true)  
end

function darkroomFunctionFunctions:specializeToType( ty, rate )
  -- maybe do lifts?
  return self
end

-- takes SDF input rate I and returns output rate after I is processed by this function
-- I is the format: {{A_sdfrate,B_sdfrate},{A_converged,B_converged}}
function darkroomFunctionFunctions:sdfTransfer( Isdf, loc )
  err( SDFRate.isSDFRate(Isdf), "sdfTransfer: first argument index 1 should be SDF rate" )
  err( type(loc)=="string", "sdfTransfer: loc should be string" )

  -- a few things can happen here:
  -- (1) inputs are converged, but ratio is inconsistant. Return unconverged
  -- (2) ratio is consistant, but some inputs are unconverged. Return unconverged.

  err( SDFRate.isSDFRate(self.sdfInput), "Missing SDF rate for fn ",self.name,". is: ",self.sdfInput)
  err( SDFRate.isSDFRate(self.sdfOutput), "Missing SDF output rate for fn ",self.name)

  local consistantRatio = true

  err( SDFRate.isSDFRate(Isdf), "sdfTransfer: input argument should be SDF rate" )
  err( #self.sdfInput == #Isdf, "# of SDF streams into function '",self.name,"' doesn't match. Was ",#Isdf," but expected ",#self.sdfInput,", ",loc )

  local Uniform = require "uniform"

  local ratio
  for i=1,#self.sdfInput do
    local thisR = { Isdf[i][1]*self.sdfInput[i][2], Isdf[i][2]*self.sdfInput[i][1] } -- I/self.sdfInput ratio
    --thisR[1],thisR[2] = J.simplify(thisR[1],thisR[2])
    if ratio==nil then
      ratio=thisR
    else
      consistantRatio = consistantRatio and ( (Uniform(ratio[1]*thisR[2])):eq(ratio[2]*thisR[1]):assertAlwaysTrue() )
    end
  end

  err( consistantRatio, "SDFTransfer: ratio is not consistant going into function '",self.name,"', Input rate: ",Isdf," function rate: ",self.sdfInput, loc )
  
  local res = {}
  for i=1,#self.sdfOutput do
    --local On, Od = J.simplify(self.sdfOutput[i][1]*ratio[1], self.sdfOutput[i][2]*ratio[2])
    local On, Od = self.sdfOutput[i][1]*ratio[1], self.sdfOutput[i][2]*ratio[2]
    table.insert( res, {On,Od} )
  end

  assert( SDFRate.isSDFRate(res) )

  return res
end

function darkroomFunctionFunctions:toTerra() return self.terraModule end
function darkroomFunctionFunctions:toVerilog() 
  local ntn = ""
  if darkroom.default_nettype_none then
    ntn = [[`default_nettype none // enable extra sanity checking
]]
  end
  return ntn..self.systolicModule:getDependencies()..self.systolicModule:toVerilog() 
end

function darkroomFunctionFunctions:toVerilogNoHeader()
  return self.systolicModule:toVerilogNoHeader()
end

function darkroomFunctionFunctions:vHeaderInOut(fnname)
  if fnname==nil then fnname="process" end
  assert(type(fnname)=="string")
  
  local v = {"\n/* function "..fnname.."*/\n"}
  if self.inputType==types.Interface() then
  elseif types.isHandshakeAny(self.inputType) then
    local readyName = "ready"
    if fnname~="process" then readyName=fnname.."_ready" end
    table.insert(v,", input wire ["..(types.lower(self.inputType):verilogBits()-1)..":0] "..fnname.."_input, output wire ["..(types.extractReady(self.inputType):verilogBits()-1)..":0] "..readyName)
  elseif self.inputType:isrv() then
    if self.inputType:lower():verilogBits()>0 then
      table.insert(v,", input wire ["..(self.inputType:lower():verilogBits()-1)..":0] "..fnname.."_input")
    end
    
    if self.stateful or (self.delay~=nil and self.delay>0) then
      table.insert(v,", input wire "..fnname.."_CE")
    end

    if self.stateful then
      table.insert(v,", input wire "..fnname.."_valid")
    end
  else
    print("vHeaderInOut NYI type: "..tostring(self.inputType))
    assert(false)
  end

  if self.outputType==types.Interface() then
  elseif types.isHandshakeAny(self.outputType) then
    local readyName = "ready_downstream"
    if fnname~="process" then readyName=fnname.."_ready_downstream" end
    
    table.insert(v,", output wire ["..(types.lower(self.outputType):verilogBits()-1)..":0] "..fnname.."_output, input wire ["..(types.extractReady(self.outputType):verilogBits()-1)..":0] "..readyName)
  elseif (self.outputType:isrv() or self.outputType:isS()) then
    if self.outputType:lower():verilogBits()>0 then
      table.insert(v,", output wire ["..(self.outputType:lower():verilogBits()-1)..":0] "..fnname.."_output")
    end
  else
    print("vHeaderInOut NYI",self.outputType)
    assert(false)
  end

  return table.concat(v,"")
end

function darkroomFunctionFunctions:vHeaderRequires()
  local v = {}
  for inst,fnmap in pairs(self.requires) do
    for fnname,_ in pairs(fnmap) do
      local fn = inst.module.functions[fnname]

      --table.insert(v,"/* HEADER REQUIRES "..inst.name..":"..fnname.."*/")
      
      if types.isHandshakeAny(fn.inputType) then
        table.insert(v,", output wire ["..(types.lower(fn.inputType):verilogBits()-1)..":0] "..inst.name.."_"..fnname.."_input, input wire ["..(types.extractReady(fn.inputType):verilogBits()-1)..":0] "..inst.name.."_"..fnname.."_ready")
      elseif fn.inputType==types.Interface() then
      else
        print("NYI - require of: "..tostring(inst.name),fn.inputType)
        assert(false)
      end
      
      if types.isHandshakeAny(fn.outputType) then
        table.insert(v,", input wire ["..(types.lower(fn.outputType):verilogBits()-1)..":0] "..inst.name.."_"..fnname.."_output, output wire "..inst.name.."_"..fnname.."_ready_downstream")
      elseif (fn.outputType:isrv() or fn.outputType:isS()) and fn.outputType:deInterface():isData() then
        table.insert(v,", input wire ["..(types.lower(fn.outputType:deInterface()):verilogBits()-1)..":0] "..inst.name.."_"..fnname.."_output")
      else
        print("NYI - require of: "..tostring(inst))
        assert(false)
      end
    end
  end

  return table.concat(v,"")
end

-- verilog header
function darkroomFunctionFunctions:vHeader()
  local v = {"module "..self.name.." (input wire CLK"}

  if self.stateful then
    table.insert(v, ", input wire reset")
  end

  table.insert(v,self:vHeaderInOut())
  table.insert(v,self:vHeaderRequires())
  
  
  assert(J.keycount(self.provides)==0)
  
  table.insert(v,[[);
parameter INSTANCE_NAME="INST";
]])
  return table.concat(v,"")
end

-- generate verilog code for set of instances
function darkroomFunctionFunctions:vInstances()
  local res = {}
  for inst,_ in pairs(self.instanceMap) do
    table.insert(res,inst:toVerilog())
  end
  return table.concat(res,"\n")
end

local darkroomModuleFunctions = {}

darkroomModuleFunctions.vInstances = darkroomFunctionFunctions.vInstances

function darkroomModuleFunctions:vHeader()
    local v = {"module "..self.name.." (input wire CLK"}

  if self.stateful then
    table.insert(v, ", input wire reset")
  end

  for fnname,fn in pairs(self.functions) do
    table.insert(v,fn:vHeaderInOut(fnname))
  end

  table.insert(v,darkroomFunctionFunctions.vHeaderRequires(self))
  
  table.insert(v,[[);
parameter INSTANCE_NAME="INST";
]])
  return table.concat(v,"")
end

-- verilog value of input data (if handshaked)
function darkroomFunctionFunctions:vInput()
  return "process_input"
end

function darkroomModuleFunctions:vInput( fnname )
  return fnname.."_input"
end

function darkroomFunctionFunctions:vInputData()
  assert(self.inputType:isRV())
  assert( self.inputType~=types.HandshakeTrigger )
  return "process_input["..(types.extractData(self.inputType):verilogBits()-1)..":0]"
end

-- verilog value of input valid (if handshaked)
function darkroomFunctionFunctions:vInputValid()
  assert(self.inputType:isRV())
  return "process_input["..(types.lower(self.inputType):verilogBits()-1)..":"..types.extractData(self.inputType):verilogBits().."]"
end

-- verilog value of input ready (upstream ready) (if handshaked)
function darkroomFunctionFunctions:vInputReady()
  assert(types.isHandshakeAny(self.inputType))
  return "ready"
end

function darkroomModuleFunctions:vInputReady( fnname )
  assert( self.functions[fnname]~=nil )
  assert( types.isHandshakeAny(self.functions[fnname].inputType) )
  return fnname.."_ready"
end

function darkroomFunctionFunctions:vOutput()
  return "process_output"
end

function darkroomModuleFunctions:vOutput( fnname )
  return fnname.."_output"
end

-- verilog value of output data (if handshaked)
function darkroomFunctionFunctions:vOutputData()
  assert(self.outputType:isRV())
  err( self.outputType~=types.HandshakeTrigger, "vOutputData(): attempting to get data channel of a HandshakeTrigger" )
  return "process_output["..(types.extractData(self.outputType):verilogBits()-1)..":0]"
end

-- verilog value of output valid (if handshaked)
function darkroomFunctionFunctions:vOutputValid()
  assert(self.outputType:isRV())
  return "process_output["..(types.lower(self.outputType):verilogBits()-1)..":"..types.extractData(self.outputType):verilogBits().."]"
end

-- verilog value of output ready (upstream ready) (if handshaked)
function darkroomFunctionFunctions:vOutputReady()
  assert(types.isHandshakeAny(self.outputType))
  return "ready_downstream"
end

function darkroomModuleFunctions:vOutputReady( fnname )
  assert( self.functions[fnname]~=nil )
  assert( types.isHandshakeAny(self.functions[fnname].outputType))
  return fnname.."_ready_downstream"
end

function darkroomFunctionFunctions:instantiate(name,X)
  err( name==nil or type(name)=="string", "functon instantiate: input should be string")
  err( X==nil, "function instantiate: too many arguments" )
  
  if name==nil then
    name = "UnnamedFunctionInstance"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID + 1
  end
  local res = darkroom.instantiate(name, self )
  return res
end

darkroom.newInstanceCallsite = J.memoize(function( instance, functionName, X )
  err( darkroom.isInstance(instance),"newInstanceCallsite: instance should be instance" )
  err( type(functionName)=="string", "newInstanceCallsite: function name must be string, but is: ",functionName )
  err( X==nil, "newInstanceCallsite: too many arguments" )

  err( darkroom.isPlainModule(instance.module), "newInstanceCallsite: instance should be plain module" )

  local fn = instance.module.functions[functionName]
  assert(fn~=nil)

  local G = require "generators.core"

  local res = G.Function{"InstCall_"..instance.name.."_"..functionName, fn.inputType, fn.sdfInput,
                       function(i)
                         local res = darkroom.applyMethod("callinstfn",instance,functionName,i)
                         return res
  end}

  assert(darkroom.isPlainFunction(res))
  return res
end)

local function checkRigelFunction(tab)
  err( type(tab.name)=="string", "rigel.newFunction: name must be string, but is: ",tab.name )
  err( darkroom.SDF==false or SDF.isSDF(tab.sdfInput), "rigel.newFunction: sdf input is not valid SDF rate" )
  err( darkroom.SDF==false or SDF.isSDF(tab.sdfOutput), "rigel.newFunction: sdf input is not valid SDF rate" )
  err( darkroom.SDF==false or tab.sdfInput:allLE1(), "rigel.newFunction: sdf input rate is not <=1, but is: ",tab.sdfInput )
  err( darkroom.SDF==false or tab.sdfOutput:allLE1(), "rigel.newFunction: sdf output rate is not <=1, but is: ",tab.sdfOutput )

  err( darkroom.SDF==false or tab.sdfInput:nonzero(), "rigel.newFunction: sdf input rate is not >0, but is: ",tab.sdfInput )
  err( darkroom.SDF==false or tab.sdfOutput:nonzero(), "rigel.newFunction: sdf output rate is not >0, but is: ",tab.sdfOutput )

  err( types.isType(tab.inputType), "rigel.newFunction: input type must be type, but is: ",tab.inputType )
  err( types.isType(tab.outputType), "rigel.newFunction: output type must be type, but is ",tab.outputType," (",tab.name,")" )

  -- legacy code hack
  if tab.inputType==types.null() then
    tab.inputType = types.Interface()
  elseif types.isBasic(tab.inputType) then
    tab.inputType = types.rv(types.Par(tab.inputType))
  end
  if tab.outputType==types.null() then
    tab.outputType = types.Interface()
  elseif types.isBasic(tab.outputType) then
    tab.outputType = types.rv(types.Par(tab.outputType))
  end
  
  err( tab.inputType:isInterface(), "rigel.newFunction: '",tab.name,"' input type must be Interface type, but is: ",tab.inputType )
  err( tab.outputType:isInterface(), "rigel.newFunction: output type must be Interface type, but is ", tab.outputType," (",tab.name,")" )

  -- even if we have multiple streams in/out, we just have one delay right now: all channels must arrive/leave at same time.
  -- expand this to a per-stream delay at some point, if needed
  err( type(tab.delay)=="number", "rigel.newFunction: missing delay? fn '",tab.name,"' inputType:",tab.inputType," outputType:",tab.outputType," delay is: ",tab.delay )
  err( tostring(tab.delay)~="inf","rigel.newFunction: delay is inf?")
  err( tostring(tab.delay)~="nan","rigel.newFunction: delay is nan?")

  if tab.inputBurstiness==nil then tab.inputBurstiness=0 end
  if tab.outputBurstiness==nil then tab.outputBurstiness=0 end

  -- if fifoed==true, this means a RV module has a FIFO along its datapath
  -- if module has multiple stream inputs, behavior of fifoed is undefined (IE: only applies to 1 stream in/out!)
  if tab.fifoed==nil then tab.fifoed=false end
  
  if types.isHandshakeAny(tab.inputType) or types.isHandshakeAny(tab.outputType) then
    err( type(tab.inputBurstiness)=="number", "rigel.newFunction: missing inputBurstiness? fn '",tab.name,"' inputType:",tab.inputType," outputType:",tab.outputType )
    err( type(tab.outputBurstiness)=="number", "rigel.newFunction: missing outputBurstiness? fn '",tab.name,"' inputType:",tab.inputType," outputType:",tab.outputType )
  end

  err( type(tab.stateful)=="boolean", "rigel.newFunction: stateful should be bool" )
end

-- this function doesn't check that the function struct is valid, it only creates the data structure.
-- (ie that input type is correct, or that requires table is consistant).
function darkroom.newFunction(tab,X)
  err( type(tab) == "table", "rigel.newFunction: input must be table" )
  err( X==nil, "rigel.newFunction: too many arguments")
  err( getmetatable(tab)==nil,"rigel.newFunction: input table already has a metatable?")
  
  checkRigelFunction(tab)
  
  if tab.globalMetadata==nil then tab.globalMetadata={} end

  assert(getmetatable(tab)==nil)
  if tab.systolicModule~=nil then
    print("systolic module already exists?", tab.name, getmetatable(tab))
    assert(false)
  end

  if tab.requires==nil then tab.requires={} end
  if tab.provides==nil then tab.provides={} end

  for instance,fnmap in pairs(tab.requires) do
    err( darkroom.isInstance(instance), "Require list should be instance/fnlist table, but is: ",instance )
    err( type(fnmap)=="table", "Require list fnmap should be table, but is: ",fnmap )
    for fn,_ in pairs(fnmap) do
      err( type(fn)=="string", "Require list should be instance/fnlist table, but is: ",fn )
    end
  end

  for instance,fnlist in pairs(tab.provides) do
    err( darkroom.isInstance(instance), "Provides list should be instance/fnlist table, but is: ",instance )
    for fn,_ in pairs(fnlist) do
      err( type(fn)=="string", "Provides list should be instance/fnlist table, but is: ",fn )
    end
  end

  assert(getmetatable(tab)==nil)
  setmetatable( tab, darkroomFunctionMT )

  return tab
end


darkroomModuleMT = {
__tostring = function(tab)
  local res = {}

  local mt = getmetatable(tab)
  setmetatable(tab,nil)
  local tabstr = tostring(tab)
  setmetatable(tab,mt)
  
  table.insert(res,"* Rigel Module "..tab.name.." ("..tabstr..")")

  table.insert(res,"  Functions:")
  for fnname,fn in pairs(tab.functions) do
    local fnmt = getmetatable(fn)
    setmetatable(fn,nil)
    local fntabstr = tostring(fn)
    setmetatable(fn,fnmt)

    table.insert(res,"    "..fnname.."("..fntabstr..") : "..tostring(fn.inputType).."->"..tostring(fn.outputType)..", "..tostring(fn.sdfInput).."->"..tostring(fn.sdfOutput))
    table.insert(res,tostring(fn))
  end

  table.insert(res,"  Stateful: "..tostring(tab.stateful))
    
  table.insert(res,"  Metadata:")
  for k,v in pairs(tab.globalMetadata) do
    table.insert(res,"    "..tostring(k).." = "..tostring(v))
  end

  if J.keycount(tab.requires)>0 then
    table.insert(res,"  Requires:")
    for inst,fnlist in pairs(tab.requires) do
      for fn,_ in pairs(fnlist) do
        table.insert(res,"    "..inst.name..":"..fn.."()")
      end
    end
  else
    table.insert(res,"  Requires: (none)")
  end

  if J.keycount(tab.provides)>0 then
    table.insert(res,"  Provides:")
    for inst,fnlist in pairs(tab.provides) do
      for fn,_ in pairs(fnlist) do
        table.insert(res,"    "..inst.name..":"..fn.."()")
      end
    end
  else
    table.insert(res,"  Provides: (none)")
  end

  if J.keycount(tab.instanceMap)==0 then
    table.insert(res,"  Internal Instances: (none)")
  else
    table.insert(res,"  Internal Instances:")
    for inst,_ in pairs(tab.instanceMap) do
      table.insert(res,"    "..inst.name..":"..inst.module.name)
    end
  end
  
  return table.concat(res,"\n")
end,
__index=function(tab,key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  v = darkroomModuleFunctions[key]
  if v~=nil then return v end

  if key=="systolicModule" then
    return buildAndCheckSystolicModule(tab,true)
  elseif key=="terraModule" then
    return buildAndCheckTerraModule(tab)
  end
end
}

function darkroomModuleFunctions:instantiate( name, X )
  err( name==nil or type(name)=="string", "instantiate: input should be string")
  err( X==nil, "instantiate: too many arguments" )
  
  if name==nil then
    name = "UnnamedInstance"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID + 1
  end
  local res = darkroom.instantiate(name, self )
  return res
end

-- this function doesn't check that the module struct is valid, it only creates the data structure.
-- (ie that input type is correct, or that requires table is consistant).
function darkroom.newModule( tab, X )
  err( type(tab)=="table","newModule: input should be table" )
  err( type(tab.name)=="string", "newModule: name must be string" )
  err( type(tab.functions)=="table", "newModule: function list must be table (map from fn name to fn)")
  err( tab.makeSystolic==nil or type(tab.makeSystolic)=="function", "newModule: makeSystolic should be function")
  err( type(tab.stateful)=="boolean","newModule: stateful should be boolean" )
  err( tab.makeTerra==nil or type(tab.makeTerra)=="function","newModule: makeTerra should be function, but is: "..tostring(tab.makeTerra))
  err( X==nil, "newModule: too many arguments" )

  if tab.globalMetadata==nil then tab.globalMetadata={} end

  if tab.instanceMap==nil then tab.instanceMap={} end
  if tab.requires==nil then tab.requires={} end
  if tab.provides==nil then tab.provides={} end

  err( type(tab.instanceMap)=="table", "newModule: instanceMap should be table")
  for inst,_ in pairs(tab.instanceMap) do
    assert( darkroom.isInstance(inst) )
  end

  for fnname,fn in pairs(tab.functions) do
    checkRigelFunction(fn)
    err( darkroom.isPlainFunction(fn),"newModule error, function '"..fnname.."' is not a plain Rigel function? is: ", fn)
  end
  
  for instance,fnlist in pairs(tab.requires) do
    err( darkroom.isInstance(instance), "Require list should be instance/fnlist table, but is: ",instance )
    for fn,_ in pairs(fnlist) do
      err( type(fn)=="string", "Require list should be instance/fnlist table, but is: ",fn )
    end
  end

  for instance,fnlist in pairs(tab.provides) do
    err( darkroom.isInstance(instance), "Provides list should be instance/fnlist table, but is: ",instance )
    for fn,_ in pairs(fnlist) do
      err( type(fn)=="string", "Provides list should be instance/fnlist table, but is: ",fn )
    end
  end

  assert(getmetatable(tab)==nil)

  return setmetatable( tab, darkroomModuleMT )
end

moduleGeneratorFunctions = {}
moduleGeneratorMT = {
__index=moduleGeneratorFunctions,
__tostring = function(tab) return "ModuleGenerator" end
}

moduleGeneratorInstanceCallsiteMT = {
__call = function(tab,...)
  local rawarg = {...}
  if darkroom.isIR(rawarg[1]) then
    assert(false)
  elseif type(rawarg[1])=="table" and #rawarg==1 then
    local arg = rawarg[1]
    err( J.keycount(arg)>0, "Calling a function generator with an empty parameter list?" )
            
    arg = typeToKey(arg)

    local res = tab.moduleGeneratorInstance.module.fnCallback(tab.moduleGeneratorInstance,tab.fnname,arg)

    J.err( darkroom.isPlainFunction(res), "ModuleGenerator fnCallback should return plain function, but returned: "..tostring(res))
    return res
  else
    J.err(false, "Called module generator instance callsite with something other than a Rigel value or table ("..tostring(rawarg[1])..")? Make sure you call function generator with curly brackets {}")
  end
end,
__tostring = function(tab) return "ModuleGeneratorInstanceCallsite" end
}

function darkroom.isModuleGeneratorInstanceCallsite(t) return getmetatable(t)==moduleGeneratorInstanceCallsiteMT end

moduleGeneratorInstanceMT = {
__index = function(tab, key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  return setmetatable({moduleGeneratorInstance=tab,fnname=key}, moduleGeneratorInstanceCallsiteMT)
end,
__tostring = function(tab) return "ModuleGeneratorInstance "..tab.name.." of moduleGenerator "..tab.module.name end
}

function moduleGeneratorFunctions:instantiate(name)
  if name==nil then
    name = "UnnamedInstance"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID + 1
  end
  local res = { name=name, module=self }

  -- mixin initial config
  for k,v in pairs(self.instanceInitial) do
    assert(res[k]==nil)
    res[k] = v
  end
  
  return setmetatable( res, moduleGeneratorInstanceMT )
end

-- fnCallback: called when 
--     input: moduleGeneratorInstance, functionname, generator args
--     output: a plain Rigel function
--     (mutate the moduleGeneratorInst to store whatever data you need to reconstruct the module later)
-- completeFn: called when we need to actually instantiate the module for real
--     input: a module generator instance
--     output: should return a plain Rigel module
--     (the framework will then mutate the moduleGeneratorInstance to point to the plain module)
-- instInitial: this is a table of values which are mixed into the moduleGeneratorInstance at start of time
function darkroom.newModuleGenerator( namespace, name, requiredArgs, optArgs, instInitial, fnCallback, completeFn, X )
  err( type(namespace)=="string", "newModuleGenerator: namespace must be string" )
  err( type(name)=="string", "newModuleGenerator: name must be string, but is: "..tostring(name) )
  err( type(instInitial)=="table", "newModuleGenerator: instance initial values must be table" )
  err( type(fnCallback)=="function", "newModuleGenerator: fnCallback must be a lua function" )
  err( type(completeFn)=="function", "newModuleGenerator: completeFn must be a lua function" )
  err( X==nil, "newModuleGenerator: too many args")
  
  local tab = { namespace=namespace, name=name, requiredArgs=requiredArgs, optArgs=optArgs, fnCallback=fnCallback, completeFn=completeFn, instanceInitial = instInitial}
  return setmetatable( tab, moduleGeneratorMT )
end

function darkroom.isPlainModule(m) return getmetatable(m)==darkroomModuleMT end
function darkroom.isModuleGenerator(m) return getmetatable(m)==moduleGeneratorMT end
function darkroom.isModule(m) return darkroom.isPlainModule(m) or darkroom.isModuleGenerator(m) end

darkroomIRFunctions = {}
darkroomIRFunctions.isIR=true
setmetatable( darkroomIRFunctions,{__index=IR.IRFunctions})
darkroomIRMT = {}

function darkroomIRMT.__index(tab,key)
  local res = rawget(tab,key)
  if res~=nil then return res end

  if darkroomIRFunctions[key]~=nil then
    return darkroomIRFunctions[key]
  end

  if type(key)=="number" and tab.scheduleConstraints~=nil and tab.scheduleConstraints.RV then
    -- HACK: early out for schedule pass
    return tab
  end
  
  if type(key)=="number" and types.isHandshakeAny(tab.type) and (tab.type:isTuple() or tab.type:isArray()) then
    local res = darkroom.selectStream(nil,tab,key)
    rawset(tab,key,res)
    return res
  elseif type(key)=="number" and (tab.type:deInterface():isArray() or tab.type:deInterface():isTuple()) then
    local G = require "generators.core"
    local res = G.Index{key}(tab)
    rawset(tab,key,res)
    return res
  elseif type(key)=="number" then
    err(false,"Attempted to index something other than a tuple or array? "..tostring(tab.type))
  end
end

darkroomIRMT.__tostring = function(tab,prefix)
  local res
  local extraAtEnd = "*** Loc\n"..tab.loc

  if prefix==nil then prefix="** " end
  
  if tab.kind=="input" then
    res = prefix..tab.name.." = R.input("..tostring(tab.type)..")"
  elseif tab.kind=="constant" then
    res = prefix..tab.name.." = R.constant('"..tab.name.."',"..tostring(tab.value)..","..tostring(tab.type)..")"
  elseif tab.kind=="applyMethod" then
    if #tab.inputs==0 then
      res = prefix..tab.name.." = "..tab.inst.name..":"..tab.fnname.."()"
    else
      res = prefix..tab.name.." = "..tab.inst.name..":"..tab.fnname.."("..tab.inputs[1].name..")"
    end
  elseif tab.kind=="apply" then
    if #tab.inputs==0 then
      res = tab.name.." = "..tab.fn.name.."()"
    else
      if tab.fn.generator~=nil then
        local gen
        if type(tab.fn.generator)=="string" then
          -- legacy
          gen = tab.fn.generator
        else
          gen = tab.fn.generator.name.."{"
          local lst = {}
          for k,v in pairs(tab.fn.generatorArgs) do
            if k=="luaFunction" then
              table.insert(lst,k.."=SKIP")
            elseif k=="rigelFunction" then
              table.insert(lst,v.name)
            elseif k=="type" or k=="rate" then
              -- skip
            elseif k=="number" then
              table.insert(lst,v)
            else
              table.insert(lst,k.."="..tostring(v))
            end
          end
          gen = gen..table.concat(lst,",").."}"
        end
        
        res = prefix..tab.name.." = "..gen.."("..tab.inputs[1].name..")\nModule:"..tab.fn.name

        -- exhaustive generator arg list list
        if type(tab.fn.generator)~="string" then
          extraAtEnd = extraAtEnd.."*** Generator Args\n"
          for k,v in pairs(tab.fn.generatorArgs) do
            if k=="rigelFunction" then
              extraAtEnd = extraAtEnd..k..": "..tostring(v.name).."\n"
            elseif k=="luaFunction" then
              extraAtEnd = extraAtEnd..k..": (Lua Function) "..tostring(v).."\n"
            else
              extraAtEnd = extraAtEnd..k..": "..tostring(v).."\n"
            end
          end
        end
      else
        res = prefix..tab.name.." = "..tab.fn.name.."("..tab.inputs[1].name..")"
      end
    end
  elseif tab.kind=="selectStream" then
    res = prefix..tab.name.." = "..tab.inputs[1].name.."["..tab.i.."] -- selectStream"
  elseif tab.kind=="statements" then
    res = "** statements{"
    for k,v in ipairs(tab.inputs) do
      res = res..v.name..","
    end
    res = res.."}"
  elseif tab.kind=="concat" or tab.kind=="concatArray2d" then
    res = prefix..tab.name.." = R.concat('"..tab.name.."',{"
    for k,v in ipairs(tab.inputs) do
      res = res..v.name
      if k~=#tab.inputs then res = res.."," end
    end
    res = res.."})"
  else
    res = "NYI-print of "..tab.kind
  end

  if darkroom.SDF then
    res = res .."\nRate:"..tostring(tab.rate)
    local util = tab:utilization()
    local Uniform = require "uniform"
    if util~=nil then res=res.."\nUtilization: "..tostring(util[1]).."/"..tostring(util[2])..", "..(Uniform(util[1]):toNumber()*100/Uniform(util[2]):toNumber()).."%" end
  end

  if true then
    res = res .. "\nType:"..tostring(tab.type)
  end

  if extraAtEnd~=nil then res = res.."\n"..extraAtEnd end
  return res
end

function darkroomIRFunctions:tostringPlain()
  return darkroomIRMT.__tostring(self,"")
end

local darkroomInstanceFunctions = {}
local darkroomInstanceMT = {
  __index = function( tab, key )
    local v = rawget(tab, key)
    if v ~= nil then return v end
    v = darkroomInstanceFunctions[key]
    if v~=nil then return v end

    if darkroom.isModule(tab.module) and tab.module.functions[key]~=nil then
      return darkroom.newInstanceCallsite( tab, key )
    end
  end,
  __call = function(tab,inp,X)
    if darkroom.isPlainFunction(tab.module) then
      return darkroom.applyMethod("INSTCALL",tab,"process",inp,X)
    else
      assert(false)
    end
  end,
  __tostring = function(tab) return "Instance "..tab.name.." of "..tostring(tab.module) end}

-- we want there to be a 1-1 correspondence between systolic instances and rigel instances
darkroomInstanceFunctions.toSystolicInstance = J.memoize(function(tab,X)
  assert(X==nil)
  err( S.isModule(tab.module.systolicModule), "Missing systolic module for instance '"..tab.name.."' of module '"..tab.module.name.."'")
  return tab.module.systolicModule:instantiate(tab.name)
end)

-- get a reference to the instance in terra
darkroomInstanceFunctions.terraReference = J.memoize(function(tab,X)
  local MT = require "generators.modulesTerra"
  return MT.terraReference(tab)
end)

function darkroomInstanceFunctions:vInput( fnname )
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_input"
  elseif darkroom.isPlainModule(self.module) then
    return self.name.."_"..fnname.."_input"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vInputData()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_input["..(types.extractData(self.module.inputType):verilogBits()-1)..":0]"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vInputValid()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_input["..(types.lower(self.module.inputType):verilogBits()-1).."]"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vInputReady( fnname )
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_ready"
  elseif darkroom.isPlainModule(self.module) then
    return self.name.."_"..fnname.."_ready"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vOutput( fnname )
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_output"    
  elseif darkroom.isPlainModule(self.module) then
    return self.name.."_"..fnname.."_output"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vOutputData()
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_output["..(types.extractData(self.module.outputType):verilogBits()-1)..":0]"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vOutputValid( fnname )
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_process_output["..(types.lower(self.module.outputType):verilogBits()-1).."]"
  elseif darkroom.isPlainModule(self.module) then
    assert( self.module.functions[fnname] ~= nil )
    return self.name.."_"..fnname.."_output["..( self.module.functions[fnname].outputType:lower():verilogBits()-1).."]"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:vOutputReady( fnname )
  if darkroom.isPlainFunction(self.module) then
    return self.name.."_ready_downstream"
  elseif darkroom.isPlainModule(self.module) then
    return self.name.."_"..fnname.."_ready_downstream"
  else
    assert(false)
  end
end

function darkroomInstanceFunctions:toVerilog()
  if darkroom.isPlainFunction(self.module) or darkroom.isPlainModule(self.module) then

    local fnList = {}
    if darkroom.isPlainFunction(self.module) then
      fnList.process = self.module
    else
      fnList = self.module.functions
    end

    local vstr = {}
    local decls = {}
    local ports = {}
    
    for fnname,fn in pairs(fnList) do
      local prefix=""
      if fnname~="process" then prefix=fnname.."_" end
      
      if fn.inputType~=types.Interface() then
        table.insert(decls,"wire ["..(types.lower(fn.inputType):verilogBits()-1)..":0] "..self.name.."_"..fnname.."_input;\n")
        if types.isHandshakeAny(fn.inputType) then 
          table.insert(decls,"wire ["..(types.extractReady(fn.inputType):verilogBits()-1)..":0] "..self.name.."_"..prefix.."ready;\n")
        end
      end
      
      if fn.outputType~=types.Interface() then
        table.insert(decls,"wire ["..(types.lower(fn.outputType):verilogBits()-1)..":0] "..self.name.."_"..fnname.."_output;\n")
        if types.isHandshakeAny(fn.outputType) then
          table.insert(decls,"wire ["..(types.extractReady(fn.outputType):verilogBits()-1)..":0] "..self.name.."_"..prefix.."ready_downstream;\n")
        end
      end
      
      if fn.inputType~=types.Interface() then
        table.insert(ports,",."..fnname.."_input("..self.name.."_"..fnname.."_input)")
        if types.isHandshakeAny(fn.inputType) then 
          table.insert(ports,",."..prefix.."ready("..self.name.."_"..prefix.."ready)")
        end
      end
      
      if fn.outputType~=types.Interface() then
        table.insert(ports,",."..fnname.."_output("..self.name.."_"..fnname.."_output)")
        if types.isHandshakeAny(fn.outputType) then
          table.insert(ports,",."..prefix.."ready_downstream("..self.name.."_"..prefix.."ready_downstream)")
        end
      end

      if types.isHandshakeAny(fn.inputType)==false and types.isHandshakeAny(fn.outputType)==false and (fn.stateful or fn.delay>0) then
        table.insert(decls,"wire "..self.name.."_"..fnname.."_CE;\n")
        table.insert(ports,",."..fnname.."_CE("..self.name.."_"..fnname.."_CE)")
      end

      if types.isHandshakeAny(fn.inputType)==false and types.isHandshakeAny(fn.outputType)==false and fn.stateful then
        table.insert(decls,"wire "..self.name.."_"..fnname.."_valid;\n")
        table.insert(ports,",."..fnname.."_valid("..self.name.."_"..fnname.."_valid)")
      end

    end

    for _,v in ipairs(decls) do table.insert(vstr,v) end
    table.insert(vstr,self.module.name.." "..self.name.."(.CLK(CLK)")
    if self.module.stateful then table.insert(vstr,",.reset(reset)") end
    for _,v in ipairs(ports) do table.insert(vstr,v) end
    
    for inst,fnmap in pairs(self.module.requires) do
      for fnname,_ in pairs(fnmap) do
        local fn = inst.module.functions[fnname]

        if fn.inputType~=types.Interface() then
          table.insert(vstr,",."..inst.name.."_"..fnname.."_input("..inst.name.."_"..fnname.."_input)")
          if types.isHandshakeAny(fn.inputType) then 
            table.insert(vstr,",."..inst.name.."_"..fnname.."_ready("..inst.name.."_"..fnname.."_ready)")
          end
        end

        if fn.outputType~=types.Interface() then
          table.insert(vstr,",."..inst.name.."_"..fnname.."_output("..inst.name.."_"..fnname.."_output)")
          if types.isHandshakeAny(fn.outputType) then 
            table.insert(vstr,",."..inst.name.."_"..fnname.."_ready_downstream("..inst.name.."_"..fnname.."_ready_downstream)")
          end
        end
      end
    end
    
    table.insert(vstr,");\n")
    return table.concat(vstr,"")
  else
    print("Error, NYI instance:toVerilog() of "..tostring(self))
    assert(false)
  end
end

function darkroom.isInstance(t) return getmetatable(t)==darkroomInstanceMT end
function darkroom.newIR(tab)
  assert( type(tab) == "table" )
  err( type(tab.name)=="string", "IR node "..tab.kind.." is missing name" )
  err( type(tab.loc)=="string", "IR node "..tab.kind.." is missing loc" )
  err( type(tab.inputs)=="table","IR node "..tab.kind..", inputs should be table")
  assert( #tab.inputs==J.keycount(tab.inputs))
  for i=1,#tab.inputs do
    assert(darkroom.isIR(tab.inputs[i]))
  end
  
  IR.new( tab )
  local r = setmetatable( tab, darkroomIRMT )

  local scheduleMode = (r.scheduleConstraints~=nil)
  for _,i in ipairs(r.inputs) do scheduleMode = scheduleMode or (i.scheduleConstraints~=nil) end
  
  if scheduleMode then
    r:typecheckSchedulePass()
  else
    r:typecheck()
  end

  if darkroom.SDF then
    r.rate = r:calcSDF()
    assert(SDF.isSDF(r.rate))
  end
  
  return r
end

function darkroomIRFunctions:setName(nm) assert(type(nm)=="string"); self.name=nm; return self end

function darkroomIRFunctions:calcSDF( )
  local res
  if self.kind=="input" or self.kind=="constant" then
    err( SDF.isSDF(self.rate),"input missing SDF?")
    res = self.rate
  elseif self.kind=="apply" or (self.kind=="applyMethod" and darkroom.isPlainFunction(self.inst.module)) then

    local fn = self.fn
    if self.kind=="applyMethod" and darkroom.isPlainFunction(self.inst.module) then
      fn = self.inst.module
    end
    
    if #self.inputs==1 then
      res =  fn:sdfTransfer(self.inputs[1].rate, self.loc)
      if DARKROOM_VERBOSE then print("APPLY",self.name,fn.kind,"rate",res) end
    elseif #self.inputs==0 then
      err( SDF.isSDF(self.rate),"nullary apply missing SDF?")
      res = self.rate
    else
      -- ??
      assert(false)
    end
  elseif self.kind=="applyMethod" then
    -- spaghetti code: see case in 'apply' above
    assert( darkroom.isModule(self.inst.module) )

    if #self.inputs==0 or self.inputs[1].type==types.Interface() then
      err( self.inst.module.functions[self.fnname].sdfExact==true or types.isHandshakeAny(self.inst.module.functions[self.fnname].outputType)==false, "null input applyMethod '"..self.fnname.."' on module '"..self.inst.module.name.."' should have sdfExact==true")
      res = self.inst.module.functions[self.fnname].sdfOutput
    elseif self.inst.module.functions[self.fnname].sdfExact==true then
      err( self.inst.module.functions[self.fnname].inputType==types.null() or self.inst.module.functions[self.fnname].sdfInput:equals(self.inputs[1].rate),"applyMethod: a function method was declared as requiring its input rate to match a given rate exactly (sdfExact), but the rate doesn't match! input rate ("..tostring(self.inputs[1].rate)..") does not match expected rate declared by the instance ("..tostring(self.inst.module.functions[self.fnname].sdfInput).."). Function '"..self.fnname.."' on instance '"..self.inst.name.."' of module '"..self.inst.module.name.."'.")
      res = self.inputs[1].rate
    elseif #self.inputs==1 then
      res =  self.inst.module.functions[self.fnname]:sdfTransfer(self.inputs[1].rate, self.loc)
    else
      assert(false)
    end
  elseif self.kind=="concat" or self.kind=="concatArray2d" then
    if self.inputs[1]:outputStreams()==0 then
      -- for non-handshake values (i.e. no streams), we just count this as 1 output stream
      -- this is the _very_ rare case where we're doing multi-rate statically timed pipelines
      
      local IR
      -- all input rates must match!
      for key,i in ipairs(self.inputs) do
        assert(#self.inputs[key].rate==1)
        
        if IR==nil then
          IR=self.inputs[key].rate[1]
        else
          local rateList = {}
          for _,v in ipairs(self.inputs) do table.insert(rateList,v.rate) end
          err(self.inputs[key].rate[1][1]==IR[1] and self.inputs[key].rate[1][2]==IR[2], "SDF ",self.kind," rate mismatch. \ninput 0 rate is:",self.inputs[1].rate," type:",self.inputs[1].type,"\ninput ",(key-1)," rate is:",self.inputs[key].rate," type:",self.inputs[key].type,"\n",self," ",self.loc)
        end
      end
      res = {IR}
      --if DARKROOM_VERBOSE then print("CONCAT",self.name,"converged=",res[2][1],"RATE",res[1][1][1],res[1][1][2]) end
    else
      res = {}
      for k,v in ipairs(self.inputs) do
        assert(#v.rate==1)
        table.insert(res, v.rate[1])
      end
      
      if DARKROOM_VERBOSE then
        print("CONCAT",self.name)
        for k,v in ipairs(res) do
          print("        concat["..tostring(k).."] ",self.name,"RATE",SDF(v))
        end
      end
    end

    -- HACK: in schedule pass, we may switch to RV inside a concat!
    -- broadcast the rate to make this work
    if self.scheduleConstraints~=nil and self:outputStreams()>0 and self.inputs[1]:outputStreams()==0 then
      res = J.broadcast(res[1],self:outputStreams())
    end
  elseif self.kind=="statements" then
    res = self.inputs[1].rate
  elseif self.kind=="selectStream" then
    assert( #self.inputs==1 )
    err( self.inputs[1].rate[self.i+1]~=nil, "selectStream ",self.i,": stream does not exist! There are only ",#self.inputs[1].rate," streams.",self.loc )
    res = {self.inputs[1].rate[self.i+1]}
  else
    print("NYI? sdftotal of node: ",self.kind,self)
    assert(false)
  end

  err( SDFRate.isSDFRate(res), "calcSDF returned something other than SDF rate? "..self.kind )
  return SDF(res)
end

function darkroomIRFunctions:outputStreams() return darkroom.streamCount(self.type) end

-- This converts our stupid internal represention into the SDF 'rate' used in the SDF paper
-- i.e. the number you multiply the input/output rate by to make the rates match.
-- Meaning for us: if < 1, then not is underutilized (sits idle). If >1, then node is
-- oversubscribed (will limit speed)
function darkroomIRFunctions:utilization()
  if self.kind=="apply" then
    assert(#self.inputs<=1)
    local total = self.rate
    err(SDF.isSDF(total),"missing rate? "..self.kind..","..self.name)
    local res = SDFRate.fracMultiply({total[1][1],total[1][2]},{self.fn.sdfOutput[1][2],self.fn.sdfOutput[1][1]})
    if DARKROOM_VERBOSE then print("SDF RATE",self.name,res[1],res[2],"sdfINP",self.fn.sdfInput[1][1],self.fn.sdfInput[1][2],"SDFOUT",self.fn.sdfOutput[1][1],self.fn.sdfOutput[1][2]) end
    assert(SDFRate.isFrac(res))
    return res
  else
    return nil
  end
end

-- assuming that the inputs are running at {1,1}, wht is the lowest/highest SDF utilization in this DAG?
-- (this will limit the speed of the whole pipe)
-- In our implementaiton, the utilization of any node can't be >1, so if the highest utilization is >1, we need to scale the throughput of the whole pipe
darkroomIRFunctions.sdfExtremeRate = J.memoize(
  function(self, highest, returnHighestNode )
    local highestRate -- this is a frac
    local highestNode
    self:visitEach(
      function(n)
        local Uniform = require "uniform"

        if n.kind=="apply" then
          local util = n:utilization()
          
          if highestRate==nil then
            highestRate={util[1],util[2]}
            highestNode = n
          else
            local cond
            if highest then
              cond = Uniform(highestRate[1]*util[2]):gt(util[1]*highestRate[2])
            else
              cond = Uniform(highestRate[1]*util[2]):lt(util[1]*highestRate[2])
            end
            
            highestRate[1] = cond:sel(highestRate[1],util[1])
            highestRate[2] = cond:sel(highestRate[2],util[2])

            if cond:isConst() then
              if cond.value==false then
                highestNode = n
              end
            else
              highestNode = "unknown due to sdf cond" -- unknown
            end
          end
        end
      end)

    if highestRate==nil then
      -- this can happen if we have no function calls (no other operators have utilization)
      if returnHighestNode then
        return {{1,1},"unknown: no function calls!"}
      else
        return {1,1}
      end
    end

    if returnHighestNode then
      return {highestRate, highestNode}
    else
      return highestRate
    end
  end)

function darkroomIRFunctions:typecheck()
  local n = self
  if n.kind=="apply" or (n.kind=="applyMethod" and darkroom.isPlainFunction(n.inst.module)) then
    local fn = n.fn
    if n.kind=="applyMethod" and darkroom.isPlainFunction(n.inst.module) then fn=n.inst.module end
    
    err( fn.registered==false or fn.registered==nil, "Error, applying registered type! "..fn.name)
    if #n.inputs==0 then
      -- verilogbits==0 => this is just a trigger, so no input required when rv
      err( fn.inputType==types.Interface(), "Missing function argument, (expected input type ",fn.inputType," on function '",fn.name,"') ",n.loc)
    else
      assert( types.isType( n.inputs[1].type ) )
      err( n.inputs[1].type==fn.inputType, "Input type mismatch to function '",fn.name,"'. Is ",n.inputs[1].type," but should be ",fn.inputType,", ",n.loc)
    end
    n.type = fn.outputType
  elseif n.kind=="applyMethod" then
    -- spaghetti code: see case in 'apply' above
    assert( darkroom.isModule(n.inst.module) )
          
    err( darkroom.isPlainFunction(n.inst.module.functions[n.fnname]), "Error, instance '"..n.inst.name.."' of module '"..n.inst.module.name.."' does not have a method named '",n.fnname,"'!")
    
    if n.inputs[1]==nil then
      err( n.inst.module.functions[n.fnname].inputType==types.Interface(), "Error, method '"..n.fnname.."' on instance '"..n.inst.name.."' of module '"..n.inst.module.name.."' was passed no input, but expected an input (of type "..tostring(n.inst.module.functions[n.fnname].inputType)..")")
    else
      err( n.inst.module.functions[n.fnname].inputType==n.inputs[1].type, "Error, input to function '"..n.fnname.."' should have type '"..tostring(n.inst.module.functions[n.fnname].inputType).."', but was passed type '"..tostring(n.inputs[1].type).."'")
    end
    
    n.type = n.inst.module.functions[n.fnname].outputType
  elseif n.kind=="input" then
  elseif n.kind=="constant" then
  elseif n.kind=="concat" then
    if darkroom.isHandshake(n.inputs[1].type) then
      n.type = types.tuple( J.map(n.inputs,
                                  function(v,k)
                                    err(darkroom.isHandshake(v.type),"concat: if one input is Handshake, all inputs must be Handshake, but idx "..tostring(k).." is "..tostring(v.type));
                                    return v.type
                                  end) )
    elseif n.inputs[1].type:isrv() and n.inputs[1].type:deInterface():isData() then
      -- perform automatic zip
      n.type = types.rv(types.Par(types.tuple( J.map(n.inputs, function(v,k) err(v.type:isrv(),"concat: if one input is rv, all inputs must be rv, but input "..tostring(k).." is "..tostring(v.type)); return v.type:deInterface() end) )))
    elseif n.inputs[1].type:isrv() then
      n.type = types.rv(types.tuple( J.map(n.inputs,
                                  function(v,k)
                                    err(v.type:isrv(),"concat: if one input is rv, all inputs must be rv, but idx "..tostring(k).." is "..tostring(v.type));
                                    return v.type.over
      end) ))

    else
      err(false,"concat: unsupported input type "..tostring(n.inputs[1].type))
    end
  elseif n.kind=="concatArray2d" then
    J.map( n.inputs, function(i,k) err(i.type==n.inputs[1].type, "All inputs to concatArray2d must have same type! index "..tostring(k-1).." is type "..tostring(i.type)..", but index 0 is "..tostring(n.inputs[1].type)) end )
    
    if darkroom.isHandshake(n.inputs[1].type) then
      n.type = types.array2d(types.RV( n.inputs[1].type:deInterface() ), n.W, n.H )
    elseif n.inputs[1].type:is("HandshakeFramed") then
      n.type = types.HandshakeArrayFramed( darkroom.extractData(n.inputs[1].type), n.inputs[1].type.params.mixed, n.inputs[1].type.params.dims, n.W, n.H )
    elseif n.inputs[1].type:isrv() and n.inputs[1].type:deInterface():isData() then
      n.type = types.rv(types.array2d( n.inputs[1].type:deInterface(), n.W, n.H ))
    elseif darkroom.isHandshakeTrigger(n.inputs[1].type) then
      for k,v in ipairs(n.inputs) do
        err(types.isHandshakeTrigger(v.type),"concat: is one input is HandshakeTrigger, all inputs must be HandshakeTrigger")
      end
      n.type = types.HandshakeTriggerArray(#n.inputs)
    else
      err(false,"concatArray2d: unsupported input type "..tostring(n.inputs[1].type))
    end
  elseif n.kind=="statements" then
    n.type = n.inputs[1].type
  elseif n.kind=="selectStream" then
    if n.inputs[1].type:isInterface() and n.inputs[1].type:is("array") then
      err( n.i < n.inputs[1].type.size[1], "selectStream index out of bounds. inputType: "..tostring(n.inputs[1].type).." index:"..tostring(n.i))
      err( n.j==nil or (n.j < n.inputs[1].type.size[2]), "selectStream index out of bounds")
      n.type =n.inputs[1].type.over
    elseif n.inputs[1].type:isInterface() and n.inputs[1].type:isTuple() then
      err( n.i < #n.inputs[1].type.list, "selectStream index out of bounds")
      n.type = n.inputs[1].type.list[n.i+1]
    else
      err(false, "selectStream input must be array or tuple of handshakes, but is "..tostring(n.inputs[1].type) )
    end
  else
    print("Rigel Typecheck NYI ",n.kind)
    assert(false)
  end
end

function darkroomIRFunctions:typecheckSchedulePass()
  if self.scheduleConstraints==nil then self.scheduleConstraints={} end

  -- early out: if we already know we need RV, we're done
  for k,v in ipairs(self.inputs) do
    if v.scheduleConstraints.RV then
      self.scheduleConstraints.RV = true
      self.type = types.null()
      return
    end
  end
  
  if self.kind=="input" then
    -- nothing to do
  elseif self.kind=="apply" then
    -- try to send rv version of input type into fn, and see if it supports it

    --assert( self.inputs[1].type:isrv() ) -- we should have done this earlier in other nodes

    J.err( self.inputs[1].type:deSchedule()==self.fn.inputType:deSchedule(),"Error, deScheduled inputs to function '",self.fn.name,"' must match, but is: input:",self.inputs[1].type," fnInput:",self.fn.inputType," input:deScheduled()=",self.inputs[1].type:deSchedule()," fnInput:deScheduled()=",self.fn.inputType:deSchedule() )

    if self.fn.inputType:isrv()==false or self.fn.outputType:isrv()==false then
      self.scheduleConstraints.RV = true
      if self.inputs[1].scheduleConstraints.RV==false then
        --print("Function forced RV:", self.fn.name, self.loc )
      end
    else
      assert( self.fn.inputType:isrv() )
      assert( self.fn.outputType:isrv() )
      self.scheduleConstraints.RV = self.inputs[1].scheduleConstraints.RV
    end

    -- always return rv
    --self.type = types.rv( self.fn.outputType:deInterface() )

    -- just return the type the function gave us
    -- if this ended up RV, we'll get boxed into being RV, but whatever, we need to do that to prevent errors
    -- (ie if we change the type to RV, the number of SDF streams may no longer match)
    self.type = self.fn.outputType
  elseif self.kind=="concat" or self.kind=="concatArray2d" then
    self.scheduleConstraints.RV = false
    local promoteToRV = false
    for k,i in ipairs(self.inputs) do
      self.scheduleConstraints.RV = self.scheduleConstraints.RV or i.scheduleConstraints.RV
      if i.type:isrv()==false and i.type:isRV()==false then
        -- if this is, for example rvV, we need to promote to RV in this node
        promoteToRV = true
        self.scheduleConstraints.RV = true
      end
    end

    if promoteToRV then
      if self.kind=="concatArray2d" then
        J.map( self.inputs, function(i,k) err(i.type==self.inputs[1].type, "All inputs to concatArray2d must have same type! index "..tostring(k-1).." is type "..tostring(i.type)..", but index 0 is "..tostring(self.inputs[1].type)) end )
        self.type = types.array2d(types.RV( self.inputs[1].type:deInterface() ), self.W, self.H )
      elseif self.kind=="concat" then
        self.type = types.tuple( J.map(self.inputs,function(v,k) return types.RV(v.type:deInterface()) end) )

      else
        print("NYI")
        assert(false)
      end
    else
      self:typecheck() -- default to regular behavior
    end
  elseif self.kind=="selectStream" then
    self.scheduleConstraints.RV = self.inputs[1].scheduleConstraints.RV
    self:typecheck() -- default to regular behavior
  else
    print("Rigel Schedule Typeheck NYI", self.kind )
    assert(false)
  end

  J.err( type(self.scheduleConstraints.RV)=="boolean", "RV schedule constraint missing for ", self.kind )
  
  for k,i in ipairs(self.inputs) do
    if i.scheduleConstraints.RV then
      assert( self.scheduleConstraints.RV )
    end
  end

  assert( types.isType(self.type) )
end

function darkroomIRFunctions:codegenSystolicReady( module, rateMonitors, X )
  assert( type(rateMonitors)=="table" )
  assert( X==nil )
          
  local readyinp
  local readyout

  -- if we have nil->Handshake(A) types, we have to drive these ready chains somehow (and they're not connected to input)
  local readyPipelines={}

  -- remember, we're visiting the graph in reverse here.
  -- if the node takes I inputs, we return a lua array of size I
  -- for each input i in I:
  -- if that input has 1 input stream, we out[i] is a systolic bool value
  -- if that input has N input streams, we out[i] is a systolic array of bool values
  -- if that input is 0 streams, out[i] is nil
  
  self:visitEachReverse(
    function(n, args)
      
      local input
      
      -- why do we need to support multiple readers of a HS stream? (ie ANDing the ready bits?)
      -- A stream may be read by multi selectStreams, which is OK.
      -- However: why can't we just special-case expect all multiple readers to be selectStreams? It seems like this should work.
      -- Note 1: Take a look at modulesTerra.lambda... it basically implements this that way
      -- Note 2: one issue is that it's very important that this function returns a systolic value of the correct type for
      --         every intermediate! We can return/examine any intermediate, and it must have the right type!
      --         don't try to special case by having this function return intermediates as lua arrays of bools or something.
      
      for k,i in pairs(args) do
        local parentKey = i[2]
        local value = i[1]
        local thisi = value[parentKey]
        
        if types.isHandshake(n.type) or types.isHandshakeTrigger(n.type) or n.type:is("HandshakeFramed") then
          assert(systolicAST.isSystolicAST(thisi))
          assert(thisi.type:isBool() or thisi.type:isUint())
          
          if input==nil then
            input = thisi
          else
            input = S.__and(input,thisi)
          end
        elseif n:outputStreams()>1 or types.isHandshakeArray(n.type) then
          assert(systolicAST.isSystolicAST(thisi))
          
          if types.isHandshakeTmuxed(n.type) or types.isHandshakeArrayOneHot(n.type) then
            assert(J.keycount(args)==1) -- NYI
            input = thisi
          else
            err(thisi.type==types.extractReady(n.type),"Ready type isn't what was expected. Is:",thisi.type," but expected: ",types.extractReady(n.type)," on node: ",n," inside module: ",module.__name)
            
            if input==nil then
              input = thisi
            else
              local r = {}
              for i=0,n:outputStreams()-1 do
                r[i+1] = S.__and(S.index(input,i),S.index(thisi,i))
              end
              if n.type:isArray() then
                input = S.cast(S.tuple(r),types.array2d(types.bool(),n:outputStreams()))
              elseif n.type:isTuple() then
                input = S.tuple(r)
              else
                assert(false)
              end
            end
          end
        else
          --err(false,"no output streams? why is this getting a ready bit? "..n.loc)
          -- this is OK - fifo:store() for example has nil output
        end
      end
      
      if J.keycount(args)==0 then
        -- this is the output of the pipeline
        assert(readyinp==nil)
        assert(n:parentCount(self)==0)
        
        if n:outputStreams()>=1 then
          readyinp = S.parameter( "ready_downstream", n.type:extractReady() )
          input = readyinp
--        elseif n:outputStreams()>1 then
--          readyinp = S.parameter( "ready_downstream", types.array2d(types.bool(),n:outputStreams()) )
--          input = readyinp
        else
          -- this is ok: ready bit may be totally internal to the module
          readyinp = S.parameter( "ready_downstream", types.null() )
          input = readyinp
        end
      else
        -- if any downstream nodes are selectStream, they'd better all be selectStream, and the count had better match
        local anySS = false
        local allSS = true
        for dsNode,_ in n:parents(self) do
          if dsNode.kind=="selectStream" then
            anySS = true
          else
            allSS = false
          end
        end
        
        err( anySS==allSS,"If any consumers are selectStream, all consumers must be selectStream ",n.loc )
        err( allSS==false or J.keycount(args)==n:outputStreams(), "Unconnected output? Module expects ",n:outputStreams()," stream readers, but only ",J.keycount(args)," were found. ",n.loc )
        
        if n:outputStreams()>=1 and n:parentCount(self)>1 then
          if allSS==false then
            print("Error, a Handshaked, multi-reader node is being consumed by something other than a selectStream? Node '",tostring(n),"' Inside function '",module.__name,"'. Handshaked nodes with multiple consumers should use broadcastStream. ",n.loc)

            for dsNode,_ in n:parents(self) do
              print("CONSUMER",dsNode,dsNode.loc)
            end
            assert(false)
          end
        end
      end
      
      local res
      
      if n.kind=="input" then
        assert(readyout==nil)
        readyout = input
      elseif n.kind=="apply" then
        rateMonitors.dsReady[n.name] = input
        
        res = {module:lookupInstance(n.name):ready(input)}
        if n.fn.inputType==types.Interface() then
          table.insert(readyPipelines, res[1])
        end
      elseif n.kind=="applyMethod" then
        local inst = module:lookupInstance(n.inst.name)

        res = {inst[n.fnname.."_ready"](inst, input)}
        
        if n.inst.module.functions[n.fnname].inputType==types.Interface() then
          -- eg fifo:load_ready()... nothing else will drive this, so we need to add it
          table.insert(readyPipelines,res[1])
        end
      elseif n.kind=="concat" or n.kind=="concatArray2d" then
        if n.kind=="concat" then
          err( input.type:isTuple(), "Error, tuple should have an input type of a tuple of ready bits")

          for _,v in ipairs(input.type.list) do
            err( v:isBool(), "Error, tuple should have an input type of a tuple of ready bits")
          end

        elseif n.kind=="concatArray2d" then
          err( input.type:isArray(), "Error, concatArray2d should have an input type of an array of ready bits")
          err( input.type==n.type:extractReady(),"Error, concatArray2d has incorrect ready bit format?")
        else
          assert(false)
        end
        
        -- tuple has N input streams, N output streams
        
        res = {}
        local i=0
        for i=0,n:outputStreams()-1 do
          table.insert(res, S.index(input,i) )
        end
      elseif n.kind=="statements" then
        res = {input}
        for i=2,#n.inputs do
          if n.inputs[i]:outputStreams()==1 then
            res[i] = S.constant(true,types.bool())
          elseif n.inputs[i]:outputStreams()>1 then
            local r = {}
            for ii=1,n.inputs[i]:outputStreams() do table.insert(r,S.constant(true,types.bool())) end
            res[i] = S.cast(S.concat(r), types.array2d(types.bool(),n.inputs[i]:outputStreams()) ) 
          else
            -- res[i]=nil
          end
        end
        
      elseif n.kind=="selectStream" then
        
        res = {}
        
        res[1] = {}
        for i=1,n.inputs[1]:outputStreams() do
          if i-1==n.i then
            res[1][i] = input
          else
            res[1][i] = S.constant(true,types.bool())
          end
        end

        if n.inputs[1].type:isTuple() then
          res[1] = S.tuple(res[1])
        elseif n.inputs[1].type:isArray() then
          res[1] = S.cast( S.tuple(res[1]),types.array2d(types.bool(),n.inputs[1]:outputStreams()) )
        else
          err(false,"Error, input to selectStream isn't tuple or array?")
        end
      else
        print("missing ready wiring of op - "..n.kind)
        assert(false)
      end
      
      -- now, validate that the output is what we expect
      err( #n.inputs==0 or type(res)=="table","res should be table "..n.kind.." inputs "..tostring(#n.inputs))
      
      for k,i in ipairs(n.inputs) do
        if types.isHandshake(i.type) or i.type:is("HandshakeFramed") then
          err(systolicAST.isSystolicAST(res[k]), "incorrect output format "..n.kind.." input "..tostring(k)..", not systolic value" )
          err(systolicAST.isSystolicAST(res[k]) and res[k].type==i.type:extractReady(), "incorrect output format of ready function. This node: kind='",n.kind,"' ",n," input index ",k,"/",#n.inputs," (with input type "..tostring(i.type)..", and input name "..i.name..") is "..tostring(res[k].type).." but expected "..tostring(i.type:extractReady())..", ",n.loc )
        elseif types.isHandshakeTrigger(i.type) then
          --assert(#res==1)
          assert(res[k].type:isBool())
        elseif i:outputStreams()>1 then
          
          err(systolicAST.isSystolicAST(res[k]), "incorrect output format "..n.kind.." input "..tostring(k)..", not systolic value" )
          if types.isHandshakeTmuxed(i.type) then
            err( res[k].type:isBool(),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
          elseif types.isHandshakeArrayOneHot(i.type) then
            err( res[k].type==types.uint(8),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
          elseif i.type:is("InterfaceArray") then
            err(res[k].type:isArray() and res[k].type:arrayOver():isBool(),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
          end
        elseif i:outputStreams()==0 then
          if res[k]~=nil then
            err( res[k].type==types.null(), "incorrect ready bit format. input ",k," outputStreams()==0, however ready type is '",res[k].type,"'. kind:'",n.kind,"' node: ",n," input node: ",i," - ",n.loc)
          end
        else
          print("NYI "..tostring(i.type))
          assert(false)
        end
      end
      -- end validate
      
      return res
    end, true)
  
  return readyinp, readyout, readyPipelines
end

function darkroomIRFunctions:codegenSystolic( module, rateMonitors, X )
  assert( Ssugar.isModuleConstructor(module) )
  assert( type(rateMonitors) == "table" )
  assert( X==nil )

  return self:visitEach(
    function(n, inputs)
      if n.kind=="input" then
        local res = {module:lookupFunction("process"):getInput()}
        if n.type:isrRV() or n.type:isrRvV() then res[2] = module:lookupFunction("ready"):getInput() end
        return res
      elseif n.kind=="applyMethod" then
        local I = module:lookupInstance(n.inst.name)
        local inp = inputs[1]
        if inp~=nil then inp=inp[1] end
        return {I[n.fnname](I,inp)}
      elseif n.kind=="apply" then
        err( n.fn.systolicModule~=nil, "Error, missing systolic module for "..n.fn.name)
        err( n.fn.systolicModule:lookupFunction("process")~=nil, "Error, missing process fn? "..n.fn.name)
        err( n.fn.systolicModule:lookupFunction("process"):getInput().type==darkroom.lower(n.fn.inputType), "Systolic input type doesn't match fn type, fn '",n.fn.name,"', is ",n.fn.systolicModule:lookupFunction("process"):getInput().type," but should be ",darkroom.lower(n.fn.inputType)," (Rigel type: ",n.fn.inputType,")" )

        if n.fn.outputType==types.null() then
          err(n.fn.systolicModule.functions.process.output==nil or n.fn.systolicModule.functions.process.output.type==types.null(), "Systolic output type doesn't match fn type, fn '", n.fn.name, "', is ", n.fn.systolicModule.functions.process.output, " but should be ", darkroom.lower(n.fn.outputType) )
        else
          err( n.fn.systolicModule:lookupFunction("process").output~=nil, "Systolic output type doesn't match fn type, fn '"..n.fn.name.."', is (NONEXISTANT) but should be "..tostring(darkroom.lower(n.fn.outputType)) )
          
          err( n.fn.systolicModule:lookupFunction("process").output.type == darkroom.lower(n.fn.outputType), "Systolic output type doesn't match fn type, fn '",n.fn.name,"', is ",n.fn.systolicModule:lookupFunction("process").output.type, " but should be ",darkroom.lower(n.fn.outputType) )
        end
        
        err(type(n.fn.stateful)=="boolean", "Missing stateful annotation "..n.fn.name)
        
        local I = module:add( n.fn.systolicModule:instantiate(n.name) )

        if n.fn.stateful then
          if darkroom.isHandshakeAny( n.fn.inputType ) or
          darkroom.isHandshakeAny(n.fn.outputType) then
            err(I.module.functions["reset"]~=nil,"missing reset function? instance '"..I.name.."' of module '"..I.module.name.."'")
            module:lookupFunction("reset"):addPipeline( I:reset(nil,module:lookupFunction("reset"):getValid()) )
          else
            module:lookupFunction("reset"):addPipeline( I:reset() )
          end
        end

        -- this is a total hack, for the FIFO monitors: pass the start valid bit into them so they know when to start monitoring for tokens
        if n.fn.systolicModule.functions.startMonitorTrigger~=nil then
          module:lookupFunction("process"):addPipeline( I:startMonitorTrigger( S.index(module:lookupFunction("process"):getInput(),1) ) )
        end
        
        if n.fn.inputType==types.Interface() then
          return { I:process() }
        elseif n.inputs[1].type:isrV() then
          return { I:process(inputs[1][1]), I:ready() }
        elseif n.inputs[1].type:isrRV() then
          return { I:process(inputs[1][1]), I:ready(inputs[1][2]) }
        elseif n.type:isrRvV() then
          -- the strange basic->RV case
          err( false, "You shouldn't use Basic->RV directly, loc "..n.loc )
        else -- RV
          local ooo = I:process( inputs[1][1] )

          if n.inputs[1].type:isRV() and n.fn.outputType:isRV() then
            -- note: no Inils
            rateMonitors.usValid[n.name] = S.index(inputs[1][1],1)
            rateMonitors.dsValid[n.name] = S.index(ooo,1)
            rateMonitors.rate[n.name] = n.rate
            rateMonitors.delay[n.name] = n.fn.delay
            rateMonitors.functionName[n.name] = n.fn.name
          end
          
          return {ooo}
        end
      elseif n.kind=="constant" then
        return {S.constant( n.value, n.type:extractData() )}
      elseif n.kind=="concat" then
        return {S.tuple( J.map(inputs,function(i) return i[1] end) ) }
      elseif n.kind=="concatArray2d" then
        local outtype = types.lower(n.type)
--        if darkroom.isHandshakeArray(n.type) or n.type:is("HandshakeTriggerArray")then
--          outtype = n.type.structure
--        elseif n.type:isrv() and n.type.over:is("Par") then
--          outtype = types.array2d(darkroom.lower(n.type.over.over:arrayOver()),n.W,n.H)
--        else
--          print("NYI - concatArray2d of type ",n.type)
--          assert(false)
--        end
        return {S.cast(S.tuple( J.map(inputs,function(i) return i[1] end) ), outtype) }
      elseif n.kind=="statements" then
        for i=2,#inputs do
          module:lookupFunction("process"):addPipeline( inputs[i][1] )
        end
        return inputs[1]
      elseif n.kind=="selectStream" then
        return {S.index(inputs[1][1],n.i)}
      else
        print(n.kind)
        assert(false)
      end
    end)
end


function darkroom.isPlainFunction(t) return getmetatable(t)==darkroomFunctionMT end
function darkroom.isFunction(t) return darkroom.isPlainFunction(t) or darkroom.isFunctionGenerator(t) or darkroom.isModuleGeneratorInstanceCallsite(t) end
function darkroom.isIR(t) return getmetatable(t)==darkroomIRMT end

-- function argument
-- schedulePass: if true, proceed in schedule mode, instead of wire mode
function darkroom.input( ty, sdfRate, schedulePass, X )
  err( types.isType( ty ), "input: first argument should be type, but is: "..tostring(ty) )
  err( ty:isInterface(),"input: type should be interface type, but is: "..tostring(ty))
  err( sdfRate==nil or SDFRate.isSDFRate(sdfRate), "input: second argument should be SDF rate or nil")
  if schedulePass==nil then schedulePass = false end
  err( type(schedulePass)=="boolean","input: schedulePass should be boolean" )
  err( X==nil, "input: too many args!")
  
  if sdfRate==nil then
    sdfRate=J.broadcast({1,1}, math.max(1,darkroom.streamCount(ty)) )
  end

  err( SDF(sdfRate):nonzero(),"input: error, input SDF rate must be >0! but is:", sdfRate )
  
  err( darkroom.streamCount(ty)==0 or darkroom.streamCount(ty)==#sdfRate, "rigel.input: number of streams in type "..tostring(ty).." ("..tostring(darkroom.streamCount(ty))..") != number of SDF streams passed in ("..tostring(#sdfRate)..")" )

  local res = {kind="input", type = ty, name="input", id={}, inputs={}, rate=SDF(sdfRate), loc=getloc()}

  if schedulePass then
    res.scheduleConstraints={RV=false}
  end
  
  return darkroom.newIR( res )
end

darkroom.instantiate = function( name, mod, X )
  err( type(name)=="string", "instantiate: name must be string")
  err( darkroom.isModule(mod) or darkroom.isPlainFunction(mod), "instantiate: module must be a Rigel module or function, but is: ",mod )
  err( X==nil, "darkroom.instantiate: too many arguments" )

  local t = {name=name, module=mod }
  return setmetatable(t, darkroomInstanceMT)
end

-- sdfRateOverride: override the firing rate of this apply. useful for nullary modules.
function darkroom.apply( name, fn, input, sdfRateOverride )
  err( type(name) == "string", "apply: first argument to apply must be name" )
  err( name==J.verilogSanitize(name),"apply: name must be verilog sanitized, from '",name,"' to '",J.verilogSanitize(name),"'")
  err( darkroom.isFunction(fn), "second argument to apply must be a darkroom function, but is:",fn )
  err( input==nil or darkroom.isIR( input ), "last argument to apply must be darkroom value or nil" )
  err( sdfRateOverride==nil or SDFRate.isSDFRate(sdfRateOverride), "sdfRateOverride must be SDF rate" )

  if input.scheduleConstraints~=nil and input.scheduleConstraints.RV then
    -- early out hack: if schedule pass is done (RV is known, just skip the apply)
    return input
  end

  if input==nil and sdfRateOverride==nil then
    sdfRateOverride={{1,1}}
  end
  
  if darkroom.isFunctionGenerator(fn) then
return fn(input)    
  end

  if darkroom.isPlainFunction(fn)==false then
    print("Function generator '"..fn.name.."' could not be resolved into a module?")
    print("missing args: "..fn:listRequiredArgs())
    assert(false)
  end

  if sdfRateOverride~=nil then
    sdfRateOverride=SDF(sdfRateOverride)
  end
  
  return darkroom.newIR( {kind = "apply", name = name, loc=getloc(), fn = fn, inputs = {input}, rate=sdfRateOverride } )
end

function darkroom.applyMethod( name, inst, fnname, input, X )
  err( type(name)=="string", "name must be string")
  err( darkroom.isInstance(inst), "applyMethod: second argument should be instance" )
  err( type(fnname)=="string", "fnname must be string")
  err( input==nil or darkroom.isIR( input ), "applyMethod: last argument should be rigel value or nil, but is: ", input )
  err( X==nil, "applyMethod: too many arguments")

  return darkroom.newIR( {kind = "applyMethod", name = name, fnname=fnname, loc=getloc(), inst = inst, inputs = {input} } )
end

-- can be called either as constant(name,value,ty) or constant(value,ty)
function darkroom.constant( name, value, ty, X )
  err( X==nil, "rigel.constant: too many arguments" )

  local res = {kind="constant", loc=getloc(), inputs = {}, rate=SDF{1,1}}
  if type(name)=="string" then
    res.name = name
    res.value = value
    res.type = ty
  else
    res.defaultName=true
    res.name="const"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID+1
    res.value = name
    res.type = value
    if types.isType(res.value) then
      -- user gave them in other order: swap
      res.value, res.type = res.type, res.value
    end
    
    err( types.isType(res.type),"rigel.constant: type should be type, but is: ",res.type)
    err( ty==nil, "rigel.constant: too many arguments" )
  end
  
  --err( types.isType(res.type), "rigel.constant: type must be rigel type" )
  if res.type==nil then
    -- user just called constant(val), try to guess type
    res.type = types.valueToType(res.value)
  end
  
  res.type:checkLuaValue(res.value)
  res.type = types.rv(types.Par(res.type))
  
  return darkroom.newIR( res )
end
darkroom.c = darkroom.constant

-- this can be called with either (name,{}) or just {}
function darkroom.concat( name, t, X )

  local r = {kind="concat", loc=getloc(), inputs={} }

  if type(name)=="string" then
    r.name = name
  elseif (name==nil and type(t)=="table") or (type(name)=="table" and t==nil) then
    r.defaultName=true
    r.name="concat"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID+1

    if type(name)=="table" and t==nil then
      t = name
    end
  else
    err( type(name)=="string", "first concat input should be name")
  end
    
  err( type(t)=="table", "tuple input should be table of darkroom values" )
  err( #t>0,"tuple should have at least 1 input!")
  err( X==nil, "rigel.concat: too many arguments")

  for k,v in ipairs(t) do
    err( darkroom.isIR(v),"concat input ",k-1," is not a darkroom value, is: ",v);
    table.insert( r.inputs, v )

    -- early out if we already know schedule constraints
    if v.scheduleConstraints~=nil and v.scheduleConstraints.RV then
      return v
    end
  end
  
  return darkroom.newIR( r )
end

function darkroom.concatArray2d( name, t, W, H, X )
  err( type(t)=="table", "array2d input should be table of darkroom values" )
  err(X==nil, "rigel concatArray2d too many arguments")

  err( type(W)=="number", "W must be number")
  if H==nil then H=1 end
  err( type(H)=="number", "H must be number")

  local r = {kind="concatArray2d", name=name, loc=getloc(), inputs={}, W=W, H=H}

  if name==nil then
    r.defaultName=true
    r.name="concatArray2d"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID+1
  end
  
  for k,v in ipairs(t) do
    err( darkroom.isIR(v),"concatArray2d input ",k-1," is not a darkroom value, is: ",v);
    table.insert( r.inputs, v )

    -- early out if we already know schedule constraints
    if v.scheduleConstraints~=nil and v.scheduleConstraints.RV then
      return v
    end
  end
  
  return darkroom.newIR( r )
end

function darkroom.selectStream( name, input, i, j, X )

  local r = {kind="selectStream"}
  
  if name==nil then
    r.defaultName=true
    r.name="selectStream"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID+1
  else
    err( type(name)=="string", "first selectStream input should be name")
    r.name=name
  end

  err( type(i)=="number", "i must be number")
  err( j==nil or type(j)=="number", "j must be number or nil")
  if j==nil then j=0 end

  assert( j==0 ) -- NYI
  
  err( darkroom.isIR(input), "input must be IR")
  err(X==nil,"selectStream: too many arguments")

  if input.scheduleConstraints~=nil and input.scheduleConstraints.RV then
    -- early out hack: if schedule pass is done (RV is known, just skip this)
    return input
  end
  
  r.i=i
  r.j=j
  r.loc = getloc()
  r.inputs={input}
  
  return darkroom.newIR(r)
end

function darkroom.statements( t )
  err( type(t)=="table", "statements: argument should be table" )
  err( #t>0 and J.keycount(t)==#t, "statements: argument should be lua array")
  J.map(t, function(i) err(darkroom.isIR(i), "statements: argument should be rigel value") end )
  return darkroom.newIR{kind="statements",inputs=t,loc=getloc(),name="__&STATEMENTS"}
end

-- this should go somewhere else
function darkroom.handshakeMode(output)
  local HANDSHAKE_MODE = darkroom.isHandshakeAny(output.type)
  output:visitEach(
    function(n)
      if n.kind=="apply" then
        HANDSHAKE_MODE = HANDSHAKE_MODE or darkroom.isHandshakeAny(n.fn.inputType) or darkroom.isHandshakeAny(n.fn.outputType)
      elseif n.kind=="applyMethod" then
        HANDSHAKE_MODE = HANDSHAKE_MODE or darkroom.isHandshakeAny(n.inst.module.functions[n.fnname].inputType) or darkroom.isHandshakeAny(n.inst.module.functions[n.fnname].outputType)
      end
    end)
  return HANDSHAKE_MODE
end

function darkroom.export(t)
  if t==nil then t=_G end

  rawset(t,"c",darkroom.constant)
end

return darkroom
