local IR = require("ir")
local types = require("types")
--local ffi = require("ffi")
local S = require("systolic")
local Ssugar = require("systolicsugar")
local SDFRate = require "sdfrate"
local J = require "common"
local err = J.err
local SDF = require("sdf")

-- We can operate in 2 different modes: either we stream frames continuously (STREAMING==true), or we only do one frame (STREAMING==false). 
-- If STREAMING==false, we artificially cap the output once the expected number of pixels is reached. This is needed for some test harnesses
STREAMING = false

local darkroom = {}

-- enable SDF checking? (true:enable, false:disable)
darkroom.SDF = true
darkroom.default_nettype_none = true

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

rigelGlobalFunctions = {}
rigelGlobalMT = {__index=rigelGlobalFunctions,
                 __tostring = function(tab) return "Global "..tab.direction.." "..tab.name.." : "..tostring(tab.type) end}

-- direction is the direction of this signal on the top module:
-- 'output' means this is an output of the top module. 'input' means its an input to the top module.
-- we can't write to an 'output' global twice!
local darkroomNewGlobal = J.memoize(function( name, direction, typeof, X )
  err( type(name)=="string", "newGlobal: name must be string" )
  err( direction=="input" or direction=="output","newGlobal: direction must be 'input' or 'output'" )
  err( types.isType(typeof), "newGlobal: type must be rigel type" )
  assert(X==nil)
  
  err( darkroom.isBasic(typeof) or darkroom.isHandshake(typeof) or darkroom.isHandshakeTrigger(typeof), "NYI - globals must be basic type or handshake")

  local t = {name=name,direction=direction,type=typeof}

  if darkroom.isHandshakeAny(typeof) then
    t.systolicValue = S.newSideChannel( name, direction, darkroom.lower(typeof), t )
    local flip = "input"
    if direction=="input" then flip="output" end
    t.systolicValueReady = S.newSideChannel( name.."_ready", flip, darkroom.extractReady(typeof), t )
  else
    t.systolicValue = S.newSideChannel( name, direction, darkroom.extractData(typeof), t )
  end

  return setmetatable(t,rigelGlobalMT)
end)

function darkroom.newGlobal( name, direction, typeof, initValue )
  local g = darkroomNewGlobal(name,direction,typeof)

  err( initValue==nil or typeof:checkLuaValue(initValue), "newGlobal: init value must be valid value of type" )

  local function fl(x) if x=="input" then return "output" else return "input" end end

  if g.initValue==nil then
    g.initValue=initValue
  else
    assert(g.initValue==initValue)
  end

  if g.flip==nil then
    g.flip = darkroomNewGlobal(name,fl(direction),typeof)
    g[direction]=g
    g[fl(direction)]=g.flip
    
    if g.flip.initValue==nil then
      g.flip.initValue=initValue
    else
      assert(g.flip.initValue==initValue)
    end

    g.flip.flip=g
    g.flip[g.flip.direction]=g.flip
    g.flip[fl(g.flip.direction)]=g
  end

  return g
end

function darkroom.isGlobal(g) return getmetatable(g)==rigelGlobalMT end

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
      elseif darkroom.isGlobal(v) then
        outk="global"
      elseif SDF.isSDF(v) then
        outk="rate"
      elseif type(v)=="table" and J.keycount(v)==2 and #v==2 and type(v[1])=="number" and type(v[2])=="number" then
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
      else
        J.err(false,"unknown type to key? "..tostring(v))
      end
      
      J.err( res[outk]==nil, "Generator key '"..outk.."' is set twice?" )
      res[outk] = v
    else
      J.err( res[k]==nil, "Generator key '"..k.."' is set twice?" )
      res[k] = v
    end
  end
  return res
end

local generatorFunctions = {}
local generatorMT={}

generatorMT.__call=function(tab,...)
  local rawarg = {...}

  if darkroom.isIR(rawarg[1]) then
    local arg
    if #rawarg>1 then
      -- collapse multi args into tuple
      arg = darkroom.concat(nil, rawarg)
    else
      arg = rawarg[1]
    end
    
    local arglist = {}
    for k,v in pairs(tab.curriedArgs) do arglist[k] = v end
    if arglist.type==nil then arglist.type = arg.type end
    if arglist.rate==nil then arglist.rate = arg.rate end
    return tab:complete(arglist)(arg)
  elseif type(rawarg[1])=="table" and #rawarg==1 then
    local arg = rawarg[1]
    err( J.keycount(arg)>0, "Calling a generator with an empty parameter list?" )
            
    arg = typeToKey(arg)

    local arglist = {}
    for k,v in pairs(tab.curriedArgs) do arglist[k] = v end
    for k,v in pairs(arg) do
      J.err( arglist[k]==nil, "Argument '"..k.."' was already passed to generator '"..tab.name.."'" )
      arglist[k] = v
    end
    
    if tab:checkArgs(arglist) then
      return tab:complete(arglist)
    else
      -- not done yet, return curried generator
      --local res = setmetatable( {name=tab.name, requiredArgs=tab.requiredArgs, optArgs=tab.optArgs, completeFn=tab.completeFn, curriedArgs=arglist }, generatorMT )
      local res = darkroom.newGenerator( tab.namespace, tab.name, tab.requiredArgs, tab.optArgs, tab.completeFn )
      res.curriedArgs = arglist
      return res
    end
  else
    J.err(false, "Called generator '"..tab.name.."' with something other than a Rigel value or table ("..tostring(rawarg[1])..")? Make sure you call generator with curly brackets {}")
  end
end
generatorMT.__tostring=function(tab)
  local res = {}
  table.insert(res,"Generator "..tab.namespace.."."..tab.name)
  table.insert(res,"  Required Args:")
  for k,v in pairs(tab.requiredArgs) do table.insert(res,"    "..k) end
  table.insert(res,"  Curried Args:")
  for k,v in pairs(tab.curriedArgs) do table.insert(res,"    "..k) end
  table.insert(res,"  Optional Args:")
  for k,v in pairs(tab.optArgs) do table.insert(res,"    "..k) end
  return table.concat(res,"\n")
end
generatorMT.__index = generatorFunctions


-- return true if done, false if not done
function generatorFunctions:checkArgs(arglist)
  local reqArgs = {}

  for k,v in pairs(arglist) do
    if self.requiredArgs[k]==nil and self.optArgs[k]==nil then
      print("Error, generator arg '"..k.."' is not in list of required or optional args on generator '"..self.namespace.."."..self.name.."'!" )
      print("Required Args: ")
      for k,v in pairs(self.requiredArgs) do print(k..",") end
      assert(false)
    end
    if self.requiredArgs[k]~=nil then reqArgs[k]=1 end
  end

  return J.keycount(reqArgs)==J.keycount(self.requiredArgs)
end

function generatorFunctions:listRequiredArgs()
  local s = {}
  for k,v in pairs(self.requiredArgs) do if self.curriedArgs[k]==nil then table.insert(s,k) end end
  return table.concat(s,",")
end

-- does this generate require the arg 'arg'? (returns true if either required or optional)
function generatorFunctions:requiresArg(arg)
  assert(type(arg)=="string")
  return (self.requiredArgs[arg]~=nil or self.optArgs[arg]~=nil) and (self.curriedArgs[arg]==nil)
end

function generatorFunctions:complete(arglist)
  if self:checkArgs(arglist)==false then
    print("Generator '"..self.name.."' is missing arguments!")
    for k,v in pairs(self.requiredArgs) do
      if self.curriedArgs[k]==nil then print("Argument '"..k.."'") end
    end
    assert(false)
  end
  local mod = self.completeFn(arglist)
  J.err( darkroom.isModule(mod), "generator '"..self.namespace.."."..self.name.."' returned something other than a rigel module? "..tostring(mod) )
  mod.generator = self
  mod.generatorArgs = arglist
  return mod
end

function darkroom.newGenerator( namespace, name, requiredArgs, optArgs, completeFn )
  err( type(namespace)=="string", "newGenerator: namespace must be string" )
  err( type(name)=="string", "newGenerator: name must be table" )
  err( type(requiredArgs)=="table", "newGenerator: requiredArgs must be table" )
  if J.keycount(requiredArgs)==#requiredArgs then requiredArgs = J.invertTable(requiredArgs) end -- convert array of names to set
  for k,v in pairs(requiredArgs) do J.err( type(k)=="string", "newGenerator: requiredArgs must be set of strings" ) end
  err( type(optArgs)=="table", "newGenerator: requiredArgs must be table" )
  if J.keycount(optArgs)==#optArgs then optArgs = J.invertTable(optArgs) end -- convert array of names to set
  for k,v in pairs(optArgs) do J.err( type(k)=="string", "newGenerator: optArgs must be set of strings" ) end
  err( type(completeFn)=="function", "newGenerator: completeFn must be lua function" )
  
  return setmetatable( {namespace=namespace, name=name, requiredArgs=requiredArgs, optArgs=optArgs, completeFn=completeFn, curriedArgs={} }, generatorMT )
end
function darkroom.isGenerator(t) return getmetatable(t)==generatorMT end

darkroomFunctionFunctions = {}
darkroomFunctionMT={
__index=function(tab,key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  v = darkroomFunctionFunctions[key]
  if v~=nil then return v end

  if key=="systolicModule" then
    -- build the systolic module as needed
    err( rawget(tab, "makeSystolic")~=nil, "missing makeSystolic() for module '"..tab.name.."'" )
    local sm = rawget(tab,"makeSystolic")()
    if Ssugar.isModuleConstructor(sm) then sm:complete(); sm=sm.module end
    J.err( S.isModule(sm),"makeSystolic didn't return a systolic module? Module: "..tostring(tab))

    -- self check module matches format we expect
    --local A,B=0,0
    --if tab.globals~=nil then A=J.keycount(tab.globals) end
    --if sm.sideChannels~=nil then B=J.keycount(sm.sideChannels) end
    --err(A==B,"makeSystolic: side channels doesn't match globals")
    for k,_ in pairs(tab.globals) do
      err( sm.sideChannels[k.systolicValue]~=nil, "makeSystolic: systolic module '"..sm.name.."' lacks side channel for global "..k.name )
      err( k.systolicValueReady==nil or sm.sideChannels[k.systolicValueReady]~=nil, "makeSystolic: systolic module '"..sm.name.."' lacks side channel for global ready "..k.name )
    end

    for k,_ in pairs(sm.sideChannels) do
      err( tab.globals[k.global]~=nil, "makeSystolic: rigel module '"..tab.name.."' lacks global for side channel "..k.name )
    end

    if tab.registered==false then
      err( sm.functions.process~=nil, "systolic process function is missing ("..tostring(sm.name)..")")
          
      if tab.outputType~=types.null() then
        err( sm.functions.process.output~=nil, "module output is not null (is "..tostring(tab.outputType).."), but systolic output is missing")
      end

      err( darkroom.lower(tab.outputType)==sm.functions.process.output.type, "module output type wrong?" )
      err( darkroom.lower(tab.inputType)==sm.functions.process.input.type, "module input type wrong?" )
    end

    if tab.registered then
      local hasReset = (sm.functions.load_reset~=nil) and (sm.functions.store_reset~=nil)
      hasReset = hasReset or (sm.functions.start_reset~=nil) and (sm.functions.done_reset~=nil)
      err( hasReset==tab.stateful, "Modules must have reset iff the module is stateful (module "..tab.name.."). stateful:"..tostring(tab.stateful).." hasReset:"..tostring(hasReset).." registered")
    else
      err( (sm.functions.reset~=nil)==tab.stateful, "Modules must have reset iff the module is stateful (module "..tab.name.."). stateful:"..tostring(tab.stateful).." hasReset:"..tostring(sm.functions.reset~=nil))
    end
    
    rawset(tab,"systolicModule", sm )
    return sm
  elseif key=="terraModule" then
    err( rawget(tab, "makeTerra")~=nil, "missing terraModule, and 'makeTerra' doesn't exist on module '"..tab.name.."'" )
    err( type(rawget(tab, "makeTerra"))=="function", "'makeTerra' function not a lua function, but is "..tostring(rawget(tab, "makeTerra")) )
    local tm = rawget(tab,"makeTerra")()

    rawset(tab,"terraModule", tm )
    return tm
  end
end,
__call=function(tab,...)
  local rawarg = {...}

  for _,arg in pairs(rawarg) do
    J.err( arg==nil or darkroom.isIR(arg),"applying a module to something other than a rigel value? Is '"..tostring(arg).."'")

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
  if #rawarg>1 then
    arg = darkroom.concat(nil,rawarg)
  else
    arg = rawarg[1]
  end
  
  local res = darkroom.apply("unnamed"..darkroom.__unnamedID, tab, arg)
  res.defaultName=true
  darkroom.__unnamedID = darkroom.__unnamedID+1
  return res
end,
__tostring=function(mod)
  local res = {}

  table.insert(res,"Module "..mod.name)
  table.insert(res,"  InputType: "..tostring(mod.inputType))
  table.insert(res,"  OutputType: "..tostring(mod.outputType))

  if SDFRate.isSDFRate(mod.sdfInput) then
    table.insert(res,"  InputSDF: "..SDFRate.tostring(mod.sdfInput))
  else
    table.insert(res,"  InputSDF: Not an SDF rate?")
  end

  if SDFRate.isSDFRate(mod.sdfOutput) then
    table.insert(res,"  OutputSDF: "..SDFRate.tostring(mod.sdfOutput))
  else
    table.insert(res,"  OutputSDF: Not an SDF rate?")
  end

  table.insert(res,"  Stateful: "..tostring(mod.stateful))
  
  table.insert(res,"  Globals:")
  for k,v in pairs(mod.globals) do
    table.insert(res,"    "..k.direction.." "..tostring(k.type).." "..k.name)
  end

  if mod.globalsInternal~=nil then
    table.insert(res,"  Globals (Internal):")
    for k,v in pairs(mod.globalsInternal) do
      table.insert(res,"    "..tostring(v.type).." "..v.name)
    end
  end
  
  table.insert(res,"  GlobalMetadata:")
  for k,v in pairs(mod.globalMetadata) do
    table.insert(res,"    "..tostring(k).." = "..tostring(v))
  end

  --print("TOSTRINGMODKIND",mod.name,mod.kind)
  if mod.kind=="lambda" then
    mod.output:visitEach(function(n) table.insert(res,tostring(n)) end)
  end
  
  return table.concat(res,"\n")
end
}


-- takes SDF input rate I and returns output rate after I is processed by this function
-- I is the format: {{A_sdfrate,B_sdfrate},{A_converged,B_converged}}
function darkroomFunctionFunctions:sdfTransfer( Isdf, loc )
  err( SDFRate.isSDFRate(Isdf), "sdfTransfer: first argument index 1 should be SDF rate" )
  err( type(loc)=="string", "sdfTransfer: loc should be string" )

  -- a few things can happen here:
  -- (1) inputs are converged, but ratio is inconsistant. Return unconverged
  -- (2) ratio is consistant, but some inputs are unconverged. Return unconverged.

  err( SDFRate.isSDFRate(self.sdfInput), "Missing SDF rate for fn "..self.name..". is: "..tostring(self.sdfInput))
  err( SDFRate.isSDFRate(self.sdfOutput), "Missing SDF output rate for fn "..self.name)

  local consistantRatio = true

  err( SDFRate.isSDFRate(Isdf), "sdfTransfer: input argument should be SDF rate" )
  err( #self.sdfInput == #Isdf, "# of SDF streams doesn't match. Was "..(#Isdf).." but expected "..(#self.sdfInput)..", "..loc )

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

  err( consistantRatio, "SDFTransfer: ratio is not consistant, Input rate: "..tostring(Isdf).." module rate: "..tostring(self.sdfInput) )
  
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

function darkroomFunctionFunctions:instantiate(arg0)
  err( self.registered, "Can't instantiate a non-registered module!")

  local name, rate
  if type(arg0)=="string" then
    name = arg0
  elseif SDF.isSDF(arg0) then
    rate = arg0
  elseif arg0~=nil then
    assert(false)
  end
  
  if name==nil then
    name = "UnnamedInstance"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID + 1
  end
  local res = darkroom.instantiateRegistered(name, self, rate )

  -- hack
  res.start = darkroom.newInstanceCallsite(res,"start")
  res.done = darkroom.newInstanceCallsite(res,"done")
  res.load = darkroom.newInstanceCallsite(res,"load")
  res.store = darkroom.newInstanceCallsite(res,"store")
  
  return res
end

function darkroomFunctionFunctions:getGlobal(name)
  for k,_ in pairs(self.globals) do
    if k.name==name then return k end
  end
  --print("Could not find global '"..name.."'")
end

darkroomInstanceCallsiteMT = {}
darkroomInstanceCallsiteMT.__call = darkroomFunctionMT.__call

function darkroom.newInstanceCallsite( instance, functionName, X )
  err( darkroom.isInstance(instance),"newInstanceCallsite: instance should be instance" )
  err( type(functionName)=="string", "newInstanceCallsite: function name must be string" )
  err( X==nil, "newInstanceCallsite: too many arguments" )

  local res = { instance=instance, functionName=functionName }
  if functionName=="load" or functionName=="start" then
    res.outputType = instance.fn.outputType
    res.inputType = types.null()
  elseif functionName=="store" or functionName=="done" then
    res.inputType = instance.fn.inputType
    res.outputType = types.null()
  else
    err(false,"newInstanceCallsite: unknown function '"..functionName.."'")
  end

  return setmetatable( res, darkroomInstanceCallsiteMT )
end

function darkroom.isInstanceCallsite( t ) return getmetatable(t)==darkroomInstanceCallsiteMT end

function darkroom.newFunction(tab,X)
  err( type(tab) == "table", "rigel.newFunction: input must be table" )
  err(X==nil, "rigel.newFunction: too many arguments")

  err( type(tab.name)=="string", "rigel.newFunction: name must be string" )
  err( darkroom.SDF==false or SDF.isSDF(tab.sdfInput), "rigel.newFunction: sdf input is not valid SDF rate" )
  err( darkroom.SDF==false or SDF.isSDF(tab.sdfOutput), "rigel.newFunction: sdf input is not valid SDF rate" )
  err( darkroom.SDF==false or tab.sdfInput:allLE1(), "rigel.newFunction: sdf input rate is not <=1, but is: "..tostring(tab.sdfInput) )
  err( darkroom.SDF==false or tab.sdfOutput:allLE1(), "rigel.newFunction: sdf output rate is not <=1, but is: "..tostring(tab.sdfOutput) )

  err( types.isType(tab.inputType), "rigel.newFunction: input type must be type" )
  err( types.isType(tab.outputType), "rigel.newFunction: output type must be type, but is "..tostring(tab.outputType).." ("..tab.name..")" )

  if tab.inputType:isArray() or tab.inputType:isTuple() then err(darkroom.isBasic(tab.inputType),"array/tup module input is not over a basic type?") end
  if tab.outputType:isArray() or tab.outputType:isTuple() then err(darkroom.isBasic(tab.outputType),"array/tup module output is not over a basic type? "..tostring(tab.outputType) ) end

  if tab.globals==nil then tab.globals={} end
  if tab.globalMetadata==nil then tab.globalMetadata={} end

  if tab.systolicModule~=nil then
    assert(false)
  end
  
  return setmetatable( tab, darkroomFunctionMT )
end

darkroomIRFunctions = {}
darkroomIRFunctions.isIR=true
setmetatable( darkroomIRFunctions,{__index=IR.IRFunctions})
darkroomIRMT = {}--{__index = darkroomIRFunctions}
function darkroomIRMT.__index(tab,key)
  local res = rawget(tab,key)
  if res~=nil then return res end

  if darkroomIRFunctions[key]~=nil then
    return darkroomIRFunctions[key]
  end

  if type(key)=="number" and (darkroom.isHandshakeArray(tab.type) or darkroom.isHandshakeTuple(tab.type) or tab.type:is("HandshakeArrayFramed") or tab.type:is("HandshakeTriggerArray")) then
    print("TY",tab.type)
    --assert(false)
    local res = darkroom.selectStream(nil,tab,key)
    rawset(tab,key,res)
    return res
  elseif type(key)=="number" and darkroom.isBasic(tab.type) and (tab.type:isArray() or tab.type:isTuple()) then
    local G = require "generators"
    local res = G.Index{key}(tab)
    rawset(tab,key,res)
    return res
  end
end

darkroomIRMT.__tostring = function(tab)
  local res
  if tab.kind=="input" then
    res = "local "..tab.name.." = R.input("..tostring(tab.type)..")"
  elseif tab.kind=="constant" then
    res = "local "..tab.name.." = R.constant('"..tab.name.."',"..tostring(tab.value)..","..tostring(tab.type)..")"
  elseif tab.kind=="applyMethod" then
    if #tab.inputs==0 then
      res = tab.name.." = "..tab.inst.name..":"..tab.fnname.."()"
    else
      res = tab.name.." = "..tab.inst.name..":"..tab.fnname.."("..tab.inputs[1].name..")"
    end
  elseif tab.kind=="apply" then
    if #tab.inputs==0 then
      res = "local "..tab.name.." = "..tab.fn.name.."()"
    else
      if tab.fn.generator~=nil then
        local gen
        if type(tab.fn.generator)=="string" then
          -- legacy
          gen = tab.fn.generator
        else
          gen = tab.fn.generator.namespace.."."..tab.fn.generator.name.."{"
          local lst = {}
          for k,v in pairs(tab.fn.generatorArgs) do
            if k=="luaFunction" or k=="rigelFunction" then
              table.insert(lst,k.."=SKIP")
            else
              table.insert(lst,k.."="..tostring(v))
            end
          end
          gen = gen..table.concat(lst,",").."}"
        end
        
        res = "local "..tab.name.." = "..gen.."("..tab.inputs[1].name..")  -- Module:"..tab.fn.name
      else
        res = "local "..tab.name.." = "..tab.fn.name.."("..tab.inputs[1].name..")"
      end
    end
  elseif tab.kind=="readGlobal" then
    res = "local "..tab.name.." = readGlobal('"..tab.name.."',"..tab.global.name..")"
  elseif tab.kind=="writeGlobal" then
    res = "local "..tab.name.." = writeGlobal('"..tab.name.."',"..tab.global.name..","..tab.inputs[1].name..")"
  elseif tab.kind=="selectStream" then
    res = tab.name.." = "..tab.inputs[1].name.."["..tab.i.."] -- selectStream"
  elseif tab.kind=="statements" then
    res = "statements{"
    for k,v in ipairs(tab.inputs) do
      res = res..v.name..","
    end
    res = res.."}"
  elseif tab.kind=="concat" or tab.kind=="concatArray2d" then
    res = "local "..tab.name.." = R.concat('"..tab.name.."',{"
    for k,v in ipairs(tab.inputs) do
      res = res..v.name
      if k~=#tab.inputs then res = res.."," end
    end
    res = res.."})"
  else
    res = "NYI-print of "..tab.kind
  end

  if darkroom.SDF then
    res = res .." -- RateOut:"..tostring(tab.rate)
    local util = tab:utilization()
    if util~=nil then res=res.." Util:"..tostring(util[1]).."/"..tostring(util[2]) end
  end

  if true then
    res = res .. " type:"..tostring(tab.type)
  end
  
  return res
end
  
darkroomInstanceMT = {}

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
  r:typecheck()

  if darkroom.SDF then
    r.rate = r:calcSDF()
    assert(SDF.isSDF(r.rate))
  end
  
  return r
end

function darkroomIRFunctions:calcSDF( )
  local res
  if self.kind=="input" or self.kind=="constant" or self.kind=="readGlobal" then
    err( SDF.isSDF(self.rate),"input missing SDF?")
    res = self.rate
  elseif self.kind=="applyMethod" then
    if self.fnname=="store" or self.fnname=="done" then
      err( self.inst.rate:equals(self.inputs[1].rate),"applyMethod: input rate ("..tostring(self.inputs[1].rate)..") does not match expected rate declared by the instance ("..tostring(self.inst.rate)..")")
      res = self.inputs[1].rate
    elseif self.fnname=="load" or self.fnname=="start" then
      --err( #self.inputs==0 or self.inst.rate:equals(self.inputs[1].rate), "applyMethod: input rate to nullary not the same?" )
      res = self.inst.rate
    else
      err( false, "sdfTotalInner: unknown method '"..self.fnname.."'" )
    end
  elseif self.kind=="writeGlobal" then
    res = self.inputs[1].rate
  elseif self.kind=="apply" then
    if #self.inputs==1 then
      res =  self.fn:sdfTransfer(self.inputs[1].rate, "APPLY "..self.name.." "..self.loc)
      if DARKROOM_VERBOSE then print("APPLY",self.name,self.fn.kind,"rate",res) end
    elseif #self.inputs==0 then
      err( SDF.isSDF(self.rate),"nullary apply missing SDF?")
      res = self.rate
    else
      -- ??
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
          local rateList = ""
          for _,v in ipairs(self.inputs) do rateList = rateList..","..tostring(v.rate) end
          err(self.inputs[key].rate[1][1]==IR[1] and self.inputs[key].rate[1][2]==IR[2], "SDF "..self.kind.." rate mismatch "..rateList.." "..self.loc)
        end
      end
      res = {IR}
      if DARKROOM_VERBOSE then print("CONCAT",self.name,"converged=",res[2][1],"RATE",res[1][1][1],res[1][1][2]) end
    else
      res = {}
      for k,v in ipairs(self.inputs) do
        assert(#v.rate==1)
        table.insert(res, v.rate[1])
      end
      
      if DARKROOM_VERBOSE then
        print("CONCAT",self.name)
        for k,v in ipairs(res[2]) do
          print("        concat["..tostring(k).."] converged=",v,"RATE",res[1][k][1],res[1][k][2])
        end
      end
    end
  elseif self.kind=="statements" then
    res = self.inputs[1].rate
  elseif self.kind=="selectStream" then
    assert( #self.inputs==1 )
    err( self.inputs[1].rate[self.i+1]~=nil, "selectStream "..tostring(self.i)..": stream does not exist! There are only "..tostring(#self.inputs[1].rate).." streams."..self.loc )
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
  function(self, highest )
    local highestRate -- this is a frac
    self:visitEach(
      function(n)
        if n.kind=="apply" then
          local util = n:utilization()

          local Uniform = require "uniform"
          
          if highestRate==nil then
            highestRate={util[1],util[2]}
          else
            local cond
            if highest then
              cond = Uniform(highestRate[1]*util[2]):gt(util[1]*highestRate[2])
            else
              cond = Uniform(highestRate[1]*util[2]):lt(util[1]*highestRate[2])
            end
            
            highestRate[1] = cond:sel(highestRate[1],util[1])
            highestRate[2] = cond:sel(highestRate[2],util[2])
          end
        end
      end)

    if highestRate==nil then
      -- this can happen if we have no function calls (no other operators have utilization)
      return {1,1}
    end
    
    return highestRate
  end)

function darkroomIRFunctions:typecheck()
  local n = self
  if n.kind=="apply" then
    err( n.fn.registered==false or n.fn.registered==nil, "Error, applying registered type! "..n.fn.name)
    if #n.inputs==0 then
      err( n.fn.inputType==types.null(), "Missing function argument, "..n.loc)
    else
      assert( types.isType( n.inputs[1].type ) )
      err( n.inputs[1].type==n.fn.inputType, "Input type mismatch. Is "..tostring(n.inputs[1].type).." but should be "..tostring(n.fn.inputType)..", "..n.loc)
    end
    n.type = n.fn.outputType
  elseif n.kind=="applyMethod" then
    err( n.inst.fn.registered==true, "Error, calling method "..n.fnname.." on a non-registered type! "..n.loc)
    
    if n.fnname=="load" or n.fnname=="start" then
      n.type = n.inst.fn.outputType
    elseif n.fnname=="store" or n.fnname=="done" then
      if n.inputs[1].type~=n.inst.fn.inputType then error("input to reg store has incorrect type, should be "..tostring(n.inst.fn.inputType).." but is "..tostring(n.inputs[1].type)..", "..n.loc) end
      n.type = types.null()
    else
      err(false,"Unknown method "..n.fnname)
    end

  elseif n.kind=="input" then
  elseif n.kind=="constant" then
  elseif n.kind=="concat" then
    if darkroom.isHandshake(n.inputs[1].type) then
      n.type = darkroom.HandshakeTuple( J.map(n.inputs, function(v,k) err(darkroom.isHandshake(v.type),"concat: if one input is Handshake, all inputs must be Handshake, but idx "..tostring(k).." is "..tostring(v.type)); return darkroom.extractData(v.type) end) )
    elseif darkroom.isBasic(n.inputs[1].type) then
      n.type = types.tuple( J.map(n.inputs, function(v) err(darkroom.isBasic(v.type),"concat: if one input is basic, all inputs must be basic"); return v.type end) )
    else
      err(false,"concat: unsupported input type "..tostring(n.inputs[1].type))
    end
  elseif n.kind=="concatArray2d" then
    J.map( n.inputs, function(i,k) err(i.type==n.inputs[1].type, "All inputs to concatArray2d must have same type! index "..tostring(k-1).." is type "..tostring(i.type)..", but index 0 is "..tostring(n.inputs[1].type)) end )
    
    if darkroom.isHandshake(n.inputs[1].type) then
      n.type = darkroom.HandshakeArray( darkroom.extractData(n.inputs[1].type), n.W, n.H )
    elseif n.inputs[1].type:is("HandshakeFramed") then
      n.type = types.HandshakeArrayFramed( darkroom.extractData(n.inputs[1].type), n.inputs[1].type.params.mixed, n.inputs[1].type.params.dims, n.W, n.H )
    elseif darkroom.isBasic(n.inputs[1].type) then
      n.type = types.array2d( n.inputs[1].type, n.W, n.H )
    else
      err(false,"concatArray2d: unsupported input type "..tostring(n.inputs[1].type))
    end
  elseif n.kind=="statements" then
    n.type = n.inputs[1].type
  elseif n.kind=="selectStream" then
    if darkroom.isHandshakeArray(n.inputs[1].type) or n.inputs[1].type:is("HandshakeArrayFramed") then
      err( n.i < n.inputs[1].type.params.W, "selectStream index out of bounds. inputType: "..tostring(n.inputs[1].type).." index:"..tostring(n.i))
      err( n.j==nil or (n.j < n.inputs[1].type.params.H), "selectStream index out of bounds")
      if n.inputs[1].type:is("HandshakeArrayFramed") then
        n.type = types.HandshakeFramed(n.inputs[1].type.params.A,n.inputs[1].type.params.mixed,n.inputs[1].type.params.dims)
      else
        n.type = darkroom.Handshake(n.inputs[1].type.params.A)
      end
    elseif darkroom.isHandshakeTriggerArray(n.inputs[1].type) then
      err( n.i < n.inputs[1].type.params.W, "selectStream index out of bounds")
      err( n.j==nil or (n.j < n.inputs[1].type.params.H), "selectStream index out of bounds")
      n.type = darkroom.HandshakeTrigger
    elseif darkroom.isHandshakeTuple(n.inputs[1].type) then
      err( n.i < #n.inputs[1].type.params.list, "selectStream index out of bounds")
      n.type = darkroom.Handshake(n.inputs[1].type.params.list[n.i+1])
    else
      err(false, "selectStream input must be array or tuple of handshakes, but is "..tostring(n.inputs[1].type) )
    end
  elseif n.kind=="readGlobal" then
    -- this is actually ok: we may be making an internal connection here
    --err( n.global.direction=="input", "Error, attempted to read a global output ("..n.global.name..")" )
  elseif n.kind=="writeGlobal" then
    err( n.global.direction=="output", "Error, attempted to write a global input ("..n.global.name..")" )
    err( n.inputs[1].type==n.global.type, "Error, input to writeGlobal is incorrect type. is "..tostring(n.inputs[1].type).." but should be "..tostring(n.global.type)..", "..n.loc )
  else
    print("Rigel Typecheck NYI ",n.kind)
    assert(false)
  end
end

function darkroomIRFunctions:codegenSystolic( module )
  assert(Ssugar.isModuleConstructor(module))
  return self:visitEach(
    function(n, inputs)
      if n.kind=="input" then
        local res = {module:lookupFunction("process"):getInput()}
        if darkroom.isRV(n.type) then res[2] = module:lookupFunction("ready"):getInput() end
        return res
      elseif n.kind=="applyMethod" then
        assert( n.inst.fn.registered )
        local I = module:lookupInstance(n.inst.name)

        if n.inst.fn.stateful then
          module:lookupFunction("reset"):addPipeline( I[n.fnname.."_reset"](I,nil,module:lookupFunction("reset"):getValid()) )
        end
        
        local inp = inputs[1]
        if inp~=nil then inp=inp[1] end
        return {I[n.fnname](I,inp)}
      elseif n.kind=="apply" then
        err( n.fn.systolicModule~=nil, "Error, missing systolic module for "..n.fn.name)
        err( n.fn.systolicModule:lookupFunction("process")~=nil, "Error, missing process fn? "..n.fn.name)
        err( n.fn.systolicModule:lookupFunction("process"):getInput().type==darkroom.lower(n.fn.inputType), "Systolic input type doesn't match fn type, fn '"..n.fn.name.."', is "..tostring(n.fn.systolicModule:lookupFunction("process"):getInput().type).." but should be "..tostring(darkroom.lower(n.fn.inputType)).." (Rigel type: "..tostring(n.fn.inputType)..")" )

        if n.fn.outputType==types.null() then
          err(n.fn.systolicModule.functions.process.output==nil or n.fn.systolicModule.functions.process.output.type==types.null(), "Systolic output type doesn't match fn type, fn '"..n.fn.kind.."', is "..tostring(n.fn.systolicModule.functions.process.output).." but should be "..tostring(darkroom.lower(n.fn.outputType)) )
        else
          err( n.fn.systolicModule:lookupFunction("process").output.type == darkroom.lower(n.fn.outputType), "Systolic output type doesn't match fn type, fn '"..n.fn.name.."', is "..tostring(n.fn.systolicModule:lookupFunction("process").output.type).." but should be "..tostring(darkroom.lower(n.fn.outputType)) )
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
        
        if n.fn.inputType==types.null() then
          return { I:process() }
        elseif darkroom.isV(n.inputs[1].type) then
          return { I:process(inputs[1][1]), I:ready() }
        elseif darkroom.isRV(n.inputs[1].type) then
          return { I:process(inputs[1][1]), I:ready(inputs[1][2]) }
        elseif darkroom.isRV(n.type) then
          -- the strange basic->RV case
          err( false, "You shouldn't use Basic->RV directly, loc "..n.loc )
        else
          return {I:process(inputs[1][1])}
        end
      elseif n.kind=="constant" then
        return {S.constant( n.value, n.type )}
      elseif n.kind=="concat" then
        return {S.tuple( J.map(inputs,function(i) return i[1] end) ) }
      elseif n.kind=="concatArray2d" then
        local outtype
        if darkroom.isHandshakeArray(n.type) then
          outtype = n.type.structure
        else
          outtype = types.array2d(darkroom.lower(n.type:arrayOver()),n.W,n.H)
        end
        return {S.cast(S.tuple( J.map(inputs,function(i) return i[1] end) ), outtype) }
      elseif n.kind=="statements" then
        for i=2,#inputs do
          module:lookupFunction("process"):addPipeline( inputs[i][1] )
        end
        return inputs[1]
      elseif n.kind=="selectStream" then
        return {S.index(inputs[1][1],n.i)}
      elseif n.kind=="readGlobal" then
        return {S.readSideChannel(n.global.systolicValue)}
      elseif n.kind=="writeGlobal" then
        return {S.writeSideChannel(n.global.systolicValue,inputs[1][1])}
      else
        print(n.kind)
        assert(false)
      end
    end)
end


function darkroom.isModule(t) return getmetatable(t)==darkroomFunctionMT end
function darkroom.isFunction(t) return darkroom.isModule(t) or darkroom.isGenerator(t) or darkroom.isInstanceCallsite(t) end
function darkroom.isIR(t) return getmetatable(t)==darkroomIRMT end

-- function argument
function darkroom.input( ty, sdfRate )
  err( types.isType( ty ), "darkroom.input: first argument should be type" )
  err( sdfRate==nil or SDFRate.isSDFRate(sdfRate), "input: second argument should be SDF rate or nil")

  if sdfRate==nil then
    sdfRate=J.broadcast({1,1}, math.max(1,darkroom.streamCount(ty)) )
  end

  err( darkroom.streamCount(ty)==0 or darkroom.streamCount(ty)==#sdfRate, "rigel.input: number of streams in type "..tostring(ty).." ("..tostring(darkroom.streamCount(ty))..") != number of SDF streams passed in ("..tostring(#sdfRate)..")" )
  
  return darkroom.newIR( {kind="input", type = ty, name="input", id={}, inputs={}, rate=SDF(sdfRate), loc=getloc()} )
end

function darkroom.readGlobal( name, g, X )
  err( type(name)=="string", "rigel.readGlobal: name must be string" )
  err( darkroom.isGlobal(g),"readGlobal: input must be rigel global" )
  err( g.direction=="input","readGlobal: global must be an input")
  err(X==nil,"readGlobal: too many arguments")
  return darkroom.newIR{kind="readGlobal",name=name,global=g,type=g.type,loc=getloc(),inputs={},rate=SDF{1,1}}
end

function darkroom.writeGlobal( name, g, input, X )
  err( type(name)=="string", "rigel.writeGlobal: name must be string" )
  err( darkroom.isGlobal(g),"writeGlobal: first argument must be rigel global, but is: "..tostring(g) )
  err( darkroom.isIR(input),"writeGlobal: second argument must be rigel value" )
  err( g.direction=="output","writeGlobal: global must be an output")
  err(X==nil,"writeGlobal: too many arguments")
  return darkroom.newIR{kind="writeGlobal",name=name,global=g,loc=getloc(),inputs={input},type=types.null()}
end

function darkroom.instantiateRegistered( name, fn, rate, X )
  err( type(name)=="string", "name must be string")
  err( darkroom.isFunction(fn), "fn must be function" )
  err( fn.registered, "fn must be registered")
  err( rate==nil or SDFRate.isSDFRate(rate),"instantiateRegistered: rate must be SDF rate or nil")
  err( X==nil, "darkroom.instantiateRegistered: too many arguments" )

  if rate==nil then rate={{1,1}} end
  local t = {name=name, fn=fn, rate=SDF(rate)}
  return setmetatable(t, darkroomInstanceMT)
end

-- sdfRateOverride: override the firing rate of this apply. useful for nullary modules.
function darkroom.apply( name, fn, input, sdfRateOverride )
  err( type(name) == "string", "first argument to apply must be name" )
  err( darkroom.isFunction(fn), "second argument to apply must be a darkroom function" )
  err( input==nil or darkroom.isIR( input ), "last argument to apply must be darkroom value or nil" )
  err( sdfRateOverride==nil or SDFRate.isSDFRate(sdfRateOverride), "sdfRateOverride must be SDF rate" )

  if input==nil and sdfRateOverride==nil then
    sdfRateOverride={{1,1}}
  end
  
  if darkroom.isGenerator(fn) then
    local arglist = {}
    for k,v in pairs(fn.curriedArgs) do arglist[k] = v end
    local ty, rate
    if arglist.type==nil then ty=input.type end
    if arglist.rate==nil then rate=input.rate end
    fn = fn{ty,rate}
  elseif darkroom.isInstanceCallsite(fn) then
    return darkroom.applyMethod( name, fn.instance, fn.functionName, input )
  end

  if darkroom.isModule(fn)==false then
    print("Generator '"..fn.name.."' could not be resolved into a module?")
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
  err( input==nil or darkroom.isIR( input ), "applyMethod: last argument should be rigel value or nil" )
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
    err( ty==nil, "rigel.constant: too many arguments" )
  end
  
  err( types.isType(res.type), "rigel.constant: type must be rigel type" )
  res.type:checkLuaValue(res.value)

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
  err( X==nil, "rigel.concat: too many arguments")
  
  J.map(t, function(n,k) err(darkroom.isIR(n),"tuple input is not a darkroom value"); table.insert(r.inputs,n) end)
  return darkroom.newIR( r )
end

function darkroom.concatArray2d( name, t, W, H, X )
  err( type(t)=="table", "array2d input should be table of darkroom values" )
  err(X==nil, "rigel concatArray2d too many arguments")

  err( type(W)=="number", "W must be number")
  if H==nil then H=1 end
  err( type(H)=="number", "H must be number")

  local r = {kind="concatArray2d", name=name, loc=getloc(), inputs={}, W=W, H=H}
  J.map(t, function(n,k) assert(darkroom.isIR(n)); table.insert(r.inputs,n) end)
  return darkroom.newIR( r )
end

function darkroom.selectStream( name, input, i, X )

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
  err( darkroom.isIR(input), "input must be IR")
  err(X==nil,"selectStream: too many arguments")

  r.i=i
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
  local HANDSHAKE_MODE = false
  output:visitEach(
    function(n)
      if n.kind=="apply" then
        HANDSHAKE_MODE = HANDSHAKE_MODE or darkroom.isHandshakeAny(n.fn.inputType) or darkroom.isHandshakeAny(n.fn.outputType)
      elseif n.kind=="applyMethod" then
        HANDSHAKE_MODE = HANDSHAKE_MODE or darkroom.isHandshakeAny(n.inst.fn.inputType) or darkroom.isHandshakeAny(n.inst.fn.outputType)
      elseif n.kind=="writeGlobal" then
        HANDSHAKE_MODE = HANDSHAKE_MODE or n.global.type:is("Handshake")
      end
    end)
  return HANDSHAKE_MODE
end

function darkroom.export(t)
  if t==nil then t=_G end

  rawset(t,"c",darkroom.constant)
end

return darkroom
