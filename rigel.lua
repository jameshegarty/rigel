local IR = require("ir")
local types = require("types")
--local ffi = require("ffi")
local S = require("systolic")
local Ssugar = require("systolicsugar")
local SDFRate = require "sdfrate"
local J = require "common"
local err = J.err

-- We can operate in 2 different modes: either we stream frames continuously (STREAMING==true), or we only do one frame (STREAMING==false). 
-- If STREAMING==false, we artificially cap the output once the expected number of pixels is reached. This is needed for some test harnesses
STREAMING = false

local darkroom = {}

-- enable SDF checking? (true:enable, false:disable)
darkroom.SDF = true

DEFAULT_FIFO_SIZE = 2048*16*16

if os.getenv("v") then
  DARKROOM_VERBOSE = true
else
  DARKROOM_VERBOSE = false
end

local function getloc()
  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline.."\n"..debug.traceback()
end

darkroom.VTrigger = types.named("VTrigger", types.bool(), "VTrigger",{})
darkroom.HandshakeTrigger = types.named("HandshakeTrigger", types.bool(), "HandshakeTrigger",{})

function darkroom.V(A) 
  err(types.isType(A),"V: argument should be type"); 
  err(darkroom.isBasic(A), "V: argument should be basic type"); 
  return types.named("V("..tostring(A)..")", types.tuple{A,types.bool()}, "V", {A=A}) 
end

function darkroom.RV(A) 
  err(types.isType(A), "RV: argument should be type"); 
  err(darkroom.isBasic(A), "RV: argument should be basic type"); 
  return types.named("RV("..tostring(A)..")",types.tuple{A,types.bool()}, "RV", {A=A})  
end

function darkroom.Handshake(A)
  err(types.isType(A),"Handshake: argument should be type")
  err(darkroom.isBasic(A),"Handshake: argument should be basic type")
  return types.named("Handshake("..tostring(A)..")", types.tuple{A,types.bool()}, "Handshake", {A=A} )
end

function darkroom.HandshakeArray(A,W,H)
  err(types.isType(A),"HandshakeArray: argument should be type")
  err(darkroom.isBasic(A),"HandshakeArray: argument should be basic type")
  err(type(W)=="number" and W>0,"HandshakeArray: W should be number > 0")
  if H==nil then H=1 end
  err(type(H)=="number" and H>0,"HandshakeArray: H should be number > 0")
  return types.named("HandshakeArray("..tostring(A)..","..tostring(W)..","..tostring(H)..")", types.array2d(types.tuple{A,types.bool()},W,H), "HandshakeArray", {A=A,W=W,H=H} )
end

function darkroom.HandshakeTriggerArray(W,H)
  err(type(W)=="number" and W>0,"HandshakeTriggerArray: W should be number > 0")
  if H==nil then H=1 end
  err(type(H)=="number" and H>0,"HandshakeTriggerArray: H should be number > 0")
  return types.named("HandshakeTriggerArray("..tostring(W)..","..tostring(H)..")", types.array2d(types.bool(),W,H), "HandshakeTriggerArray", {W=W,H=H} )
end

function darkroom.HandshakeTuple(tab)
  err( type(tab)=="table" and J.keycount(tab)==#tab,"HandshakeTuple: argument should be table of types")

  local s = {}
  local ty = {}
  for k,v in ipairs(tab) do
    err(types.isType(v) and darkroom.isBasic(v),"HandshakeTuple: type list must all be basic types, but index "..tostring(k).." is "..tostring(v))
    table.insert(s,tostring(v))
    table.insert(ty,types.tuple{v,types.bool()})
  end

  return types.named("HandshakeTuple("..table.concat(s,",")..")", types.tuple(ty), "HandshakeTuple", {list=tab} )
end

function darkroom.HandshakeArrayOneHot(A,N)
  err(types.isType(A),"HandshakeArrayOneHot: first argument should be type")
  err(darkroom.isBasic(A),"HandshakeArrayOneHot: first argument should be basic type")
  err(type(N)=="number","HandshakeArrayOneHot: second argument should be number")
  return types.named("HandshakeArrayOneHot("..tostring(A)..","..tostring(N)..")", types.tuple{A,types.bool()}, "HandshakeArrayOneHot", {A=A,N=N} )
end

function darkroom.HandshakeTmuxed(A,N)
  err(types.isType(A),"HandshakeTmuxed: first argument should be type")
  err(darkroom.isBasic(A),"HandshakeTmuxed: first argument should be basic type")
  err(type(N)=="number","HandshakeTmuxed: second argument should be number")
  return types.named("HandshakeTmuxed("..tostring(A)..","..tostring(N)..")", types.tuple{A,types.uint(8)}, "HandshakeTmuxed",{A=A,N=N} )
end
function darkroom.Sparse(A,W,H) return types.array2d(types.tuple({A,types.bool()}),W,H) end

function darkroom.isHandshakeArrayOneHot(a)
  err(types.isType(a),"isHandshakeArrayOneHot: argument must be a type")
  return a:isNamed() and a.generator=="HandshakeArrayOneHot"
end
function darkroom.isHandshakeTmuxed(a)
  return a:isNamed() and a.generator=="HandshakeTmuxed"
end

function darkroom.isHandshake( a ) return a:isNamed() and a.generator=="Handshake" end
function darkroom.isHandshakeTrigger( a ) return a:isNamed() and a.generator=="HandshakeTrigger" end
function darkroom.isHandshakeArray( a ) return a:isNamed() and a.generator=="HandshakeArray" end
function darkroom.isHandshakeTriggerArray( a ) return a:isNamed() and a.generator=="HandshakeTriggerArray" end
function darkroom.isHandshakeTuple( a ) return a:isNamed() and a.generator=="HandshakeTuple" end

-- is this any of the handshaked types?
function darkroom.isHandshakeAny( a ) return darkroom.isHandshake(a) or darkroom.isHandshakeTrigger(a) or darkroom.isHandshakeTuple(a) or darkroom.isHandshakeArray(a) or darkroom.isHandshakeTmuxed(a) or darkroom.isHandshakeArrayOneHot(a) end

function darkroom.isV( a ) return a:isNamed() and a.generator=="V" end
function darkroom.isRV( a ) return a:isNamed() and a.generator=="RV" end
function darkroom.isBasic(A)
  assert(types.isType(A))
  if A:isArray() then return darkroom.isBasic(A:arrayOver()) end
  if A:isTuple() then for _,v in ipairs(A.list) do if darkroom.isBasic(v)==false then return false end end return true end
    
  if darkroom.isV(A) or darkroom.isRV(A) or darkroom.isHandshake(A) or darkroom.isHandshakeTrigger(A) or darkroom.isHandshakeArrayOneHot(A) or darkroom.isHandshakeTmuxed(A) or darkroom.isHandshakeArray(A) or darkroom.isHandshakeTuple(A) or darkroom.isHandshakeTriggerArray(A) then
    return false
  end

  return true
end
function darkroom.expectBasic( A ) err( darkroom.isBasic(A), "type should be basic but is "..tostring(A) ) end
function darkroom.expectV( A, er ) if darkroom.isV(A)==false then error(er or "type should be V but is "..tostring(A)) end end
function darkroom.expectRV( A, er ) if darkroom.isRV(A)==false then error(er or "type should be RV") end end
function darkroom.expectHandshake( A, er ) if darkroom.isHandshake(A)==false then error(er or "type should be handshake") end end


-- extract takes the darkroom, and returns the type that should be used by the terra/systolic process function
-- ie V(A) => {A,bool}
-- RV(A) => {A,bool}
-- Handshake(A) => {A,bool}
function darkroom.lower( a, loc )
  assert(types.isType(a))
  if darkroom.isHandshake(a) or darkroom.isHandshakeTrigger(a) or  darkroom.isRV(a) or darkroom.isV(a) or darkroom.isHandshakeArray(a) or darkroom.isHandshakeArrayOneHot(a) or darkroom.isHandshakeTmuxed(a) or darkroom.isHandshakeTuple(a) or darkroom.isHandshakeTriggerArray(a) then
    return a.structure
  elseif darkroom.isBasic(a) then 
    return a 
  end
  print("rigel.lower: unknown type? ",a)
  assert(false)
end

-- extract underlying actual data type.
-- V(A) => A
-- RV(A) => A
-- Handshake(A) => A
function darkroom.extractData(a)
  if darkroom.isHandshake(a) or darkroom.isV(a) or darkroom.isRV(a) then return a.params.A end
  if darkroom.isHandshakeTrigger(a) then return types.null() end
  if darkroom.isHandshakeArray(a) then return types.array2d(a.params.A,a.params.N) end
  return a -- pure
end

function darkroom.hasReady(a)
  if darkroom.isHandshake(a) or darkroom.isHandshakeTrigger(a) or darkroom.isRV(a) or darkroom.isHandshakeArray(a) or darkroom.isHandshakeTuple(a) or darkroom.isHandshakeArrayOneHot(a) or darkroom.isHandshakeTmuxed(a) then
    return true
  elseif darkroom.isBasic(a) or darkroom.isV(a) then
    return false
  else
    print("UNKNOWN READY",a)
    assert(false)
  end
end

function darkroom.extractReady(a)
  if darkroom.isHandshake(a) or darkroom.isHandshakeTrigger(a) then return types.bool()
  elseif darkroom.isV(a) then return types.bool()
  elseif darkroom.isRV(a) then return types.bool()
  elseif darkroom.isHandshakeTuple(a) then
    return types.array2d(types.bool(),#a.params.list) -- we always use arrays for ready bits. no reason not to.
  elseif darkroom.isHandshakeArrayOneHot(a) then
    return types.uint(8)
  else 
    print("COULD NOT EXTRACT READY",a)
    assert(false) 
  end
end

function darkroom.extractValid(a)
  if darkroom.isHandshakeTmuxed(a) then
    return types.uint(8)
  end
  return types.bool()
end

function darkroom.streamCount(A)
  if darkroom.isBasic(A) or darkroom.isV(A) or darkroom.isRV(A) then
    return 0
  elseif darkroom.isHandshake(A) or darkroom.isHandshakeTrigger(A) then
    return 1
  elseif darkroom.isHandshakeArray(A) or darkroom.isHandshakeTriggerArray(A) then
    return A.params.W*A.params.H
  elseif darkroom.isHandshakeTuple(A) then
    return #A.params.list
  elseif darkroom.isHandshakeTmuxed(A) or darkroom.isHandshakeArrayOneHot(A) then
    return A.params.N
  else
    err(false, "NYI streamCount "..tostring(A))
  end
end

-- is this type any type of handshake type?
function darkroom.isStreaming(A)
  if darkroom.isHandshake(A) or darkroom.isHandshakeTrigger(A) or darkroom.isHandshakeArray(A) or darkroom.isHandshakeTuple(A) or  darkroom.isHandshakeTmuxed(A) or darkroom.isHandshakeArrayOneHot(A) then
    return true
  end
  return false
end


rigelGlobalFunctions = {}
rigelGlobalMT = {__index=rigelGlobalFunctions}

-- direction is the direction of this signal on the top module:
-- 'output' means this is an output of the top module. 'input' means its an input to the top module.
-- we can't write to an 'output' global twice!
function darkroom.newGlobal( name, direction, typeof, initValue )
  err( type(name)=="string", "newGlobal: name must be string" )
  err( direction=="input" or direction=="output","newGlobal: direction must be 'input' or 'output'" )
  err( types.isType(typeof), "newGlobal: type must be rigel type" )
  err( initValue==nil or typeof:checkLuaValue(initValue), "newGlobal: init value must be valid value of type" )

  err( darkroom.isBasic(typeof) or darkroom.isHandshake(typeof) or darkroom.isHandshakeTrigger(typeof), "NYI - globals must be basic type or handshake")

  local t = {name=name,direction=direction,type=typeof,initValue=initValue}



  if darkroom.isHandshakeAny(typeof) then
    t.systolicValue = S.newSideChannel( name, direction, darkroom.lower(typeof), t )
    local flip = "input"
    if direction=="input" then flip="output" end
    t.systolicValueReady = S.newSideChannel( name.."_ready", flip, darkroom.extractReady(typeof), t )
  else
    t.systolicValue = S.newSideChannel( name, direction, darkroom.extractData(typeof), t )
  end

  return setmetatable(t,rigelGlobalMT)
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
  for k,v in pairs(t) do
    if type(k)=="number" then
      local outk
      if type(v)=="number" then
        outk="number"
      elseif type(v)=="boolean" then
        outk="bool"
      elseif type(v)=="function" then
        outk="luaFunction"
      elseif types.isType(v) then
        outk="type"
      elseif darkroom.isFunction(v) then
        outk="rigelFunction"
      elseif type(v)=="table" and J.keycount(v)==2 and #v==2 and type(v[1])=="number" and type(v[2])=="number" then
        outk="size"
      elseif type(v)=="table" and J.keycount(v)==4 and #v==4 and type(v[1])=="number" and type(v[2])=="number"
             and type(v[3])=="number" and type(v[4])=="number" then
        outk="bounds"
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
    return tab:complete(arglist)(arg)
  elseif type(rawarg[1])=="table" and #rawarg==1 then
    local arg = rawarg[1]
    err( J.keycount(arg)>0, "Calling a generator with an empty parameter list?" )
            
    arg = typeToKey(arg)

    local arglist = {}
    for k,v in pairs(tab.curriedArgs) do arglist[k] = v end
    for k,v in pairs(arg) do
      J.err( arglist[k]==nil, "Argument '"..k.."' was already passed to generator" )
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
    J.err(false, "Called a generator with something other than a Rigel value or table? Make sure you call generator with curly brackets {}")
  end
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

function generatorFunctions:listArgs()
  local s = ""
  for k,v in pairs(self.requiredArgs) do s = k..","..s end
  return s
end

function generatorFunctions:complete(arglist)
  self:checkArgs(arglist)
  local mod = self.completeFn(arglist)
  J.err( darkroom.isModule(mod), "generator returned something other than a rigel module?" )
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
    assert( rawget(tab, "makeSystolic")~=nil )
    local sm = rawget(tab,"makeSystolic")()
    assert(S.isModule(sm))

    -- self check module matches format we expect
    --local A,B=0,0
    --if tab.globals~=nil then A=J.keycount(tab.globals) end
    --if sm.sideChannels~=nil then B=J.keycount(sm.sideChannels) end
    --err(A==B,"makeSystolic: side channels doesn't match globals")
    for k,_ in pairs(tab.globals) do
      err( sm.sideChannels[k.systolicValue]~=nil, "makeSystolic: systolic module lacks side channel for global "..k.name )
      err( k.systolicValueReady==nil or sm.sideChannels[k.systolicValueReady]~=nil, "makeSystolic: systolic module lacks side channel for global ready "..k.name )
    end

    for k,_ in pairs(sm.sideChannels) do
      err( tab.globals[k.global]~=nil, "makeSystolic: rigel module lacks global for side channel "..k.name )
    end
      
    if tab.registered==false then
      err( sm.functions.process~=nil, "systolic process function is missing ("..tostring(sm.name)..")")
          
      if tab.outputType~=types.null() then
        err( sm.functions.process.output~=nil, "module output is not null (is "..tostring(tab.outputType).."), but systolic output is missing")
      end

      err( darkroom.lower(tab.outputType)==sm.functions.process.output.type, "module output type wrong?" )
      err( darkroom.lower(tab.inputType)==sm.functions.process.input.type, "module input type wrong?" )
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
__call=function(tab,arg)
  J.err( darkroom.isIR(arg),"applying a module to something other than a rigel value?")

  -- discover variable name from lua
  if arg.defaultName then
    local n = discoverName(arg)
    if n~=nil then
      arg.name=n.."_"..darkroom.__unnamedID
      darkroom.__unnamedID = darkroom.__unnamedID+1
      arg.defaultname=false
    end
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

  table.insert(res,"  Globals:")
  for k,v in pairs(mod.globals) do
    table.insert(res,"    "..k.direction.." "..tostring(k.type).." "..k.name)
  end
  table.insert(res,"  GlobalMetadata:")
  for k,v in pairs(mod.globalMetadata) do
    table.insert(res,"    "..tostring(k).." = "..tostring(v))
  end
  
  return table.concat(res,"\n")
end
}


-- takes SDF input rate I and returns output rate after I is processed by this function
-- I is the format: {{A_sdfrate,B_sdfrate},{A_converged,B_converged}}
function darkroomFunctionFunctions:sdfTransfer( I, loc )
  err( type(I)=="table", "sdfTransfer: first argument should be table" )
  err( SDFRate.isSDFRate(I[1]), "sdfTransfer: first argument index 1 should be SDF rate" )
  err( type(I[2][1])=="boolean", "sdfTransfer: converged should be bool")
  err( type(loc)=="string", "sdfTransfer: loc should be string" )

  -- a few things can happen here:
  -- (1) inputs are converged, but ratio is inconsistant. Return unconverged
  -- (2) ratio is consistant, but some inputs are unconverged. Return unconverged.

  err( SDFRate.isSDFRate(self.sdfInput), "Missing SDF rate for fn "..self.name)
  err( SDFRate.isSDFRate(self.sdfOutput), "Missing SDF output rate for fn "..self.name)

  -- if we're going from N->N, we don't know how stuff maps so we can't do it automatically
  if #self.sdfInput~=1 and #self.sdfOutput~=1 then
    print( "ERROR: sdf rate with no default behavior ("..self.kind..": "..tostring(#self.sdfInput).."->"..tostring(#self.sdfOutput)..") "..loc )
  end

  local allConverged, consistantRatio = true, true

  local Isdf, Iconverged = I[1], I[2]

  err( SDFRate.isSDFRate(Isdf), "sdfTransfer: input argument should be SDF rate" )
  err( #self.sdfInput == #Isdf, "# of SDF streams doesn't match. Was "..(#Isdf).." but expected "..(#self.sdfInput)..", "..loc )

  local R
  for i=1,#self.sdfInput do
    if self.sdfInput[i]=="x" or Isdf[i]=="x" then
      -- don't care
    else
      local thisR = { Isdf[i][1]*self.sdfInput[i][2], Isdf[i][2]*self.sdfInput[i][1] } -- I/self.sdfInput ratio
      thisR[1],thisR[2] = J.simplify(thisR[1],thisR[2])
      if R==nil then R=thisR end
      consistantRatio = consistantRatio and (R[1]==thisR[1] and R[2]==thisR[2])

      assert(type(Iconverged[i])=="boolean")
      allConverged = allConverged and Iconverged[i]
    end
  end

  local res, resConverged = {},{}
  for i=1,#self.sdfOutput do
    local On, Od = J.simplify(self.sdfOutput[i][1]*R[1], self.sdfOutput[i][2]*R[2])

    table.insert( res, {On,Od} )
    table.insert( resConverged, allConverged and consistantRatio )
  end

  assert(#res==#resConverged)
  assert( SDFRate.isSDFRate(res) )
  J.map( resConverged, function(n) assert(type(n)=="boolean") end )

  return { res, resConverged }
end

function darkroomFunctionFunctions:toTerra() return self.terraModule end
function darkroomFunctionFunctions:toVerilog() return [[`default_nettype none // enable extra sanity checking
]]..self.systolicModule:getDependencies()..self.systolicModule:toVerilog() end

function darkroomFunctionFunctions:instantiate(name)
  err( self.registered, "Can't instantiate a non-registered module!")
  if name==nil then
    name = "UnnamedInstance"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID + 1
  end
  local res = darkroom.instantiateRegistered(name, self )

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
  err( darkroom.SDF==false or SDFRate.isSDFRate(tab.sdfInput), "rigel.newFunction: sdf input is not valid SDF rate" )
  err( darkroom.SDF==false or SDFRate.isSDFRate(tab.sdfOutput), "rigel.newFunction: sdf input is not valid SDF rate" )
  err( darkroom.SDF==false or (tab.sdfInput[1]=='x' or #tab.sdfInput==0 or tab.sdfInput[1][1]/tab.sdfInput[1][2]<=1), "rigel.newFunction: sdf input rate is not <=1" )
  err( darkroom.SDF==false or (tab.sdfOutput[1]=='x' or #tab.sdfOutput==0 or tab.sdfOutput[1][1]/tab.sdfOutput[1][2]<=1), "rigel.newFunction: sdf output rate is not <=1" )

  err( types.isType(tab.inputType), "rigel.newFunction: input type must be type" )
  err( types.isType(tab.outputType), "rigel.newFunction: output type must be type, but is "..tostring(tab.outputType).." ("..tab.name..")" )

  if tab.inputType:isArray() or tab.inputType:isTuple() then err(darkroom.isBasic(tab.inputType),"array/tup module input is not over a basic type?") end
  if tab.outputType:isArray() or tab.outputType:isTuple() then err(darkroom.isBasic(tab.outputType)) end

  if tab.globals==nil then tab.globals={} end
  if tab.globalMetadata==nil then tab.globalMetadata={} end
  
  return setmetatable( tab, darkroomFunctionMT )
end

darkroomIRFunctions = {}
setmetatable( darkroomIRFunctions,{__index=IR.IRFunctions})
darkroomIRMT = {__index = darkroomIRFunctions}

darkroomInstanceMT = {}

function darkroom.isInstance(t) return getmetatable(t)==darkroomInstanceMT end
function darkroom.newIR(tab)
  assert( type(tab) == "table" )
  err( type(tab.name)=="string", "IR node "..tab.kind.." is missing name" )
  err( type(tab.loc)=="string", "IR node "..tab.kind.." is missing loc" )
  IR.new( tab )
  local r = setmetatable( tab, darkroomIRMT )
  r:typecheck()
  return r
end

local __sdfTotalCache = {}
-- assume that inputs have SDF rate {1,1}, then what is the rate of this node?
function darkroomIRFunctions:sdfTotalInner( registeredInputRates )
  assert( type(registeredInputRates)=="table" )

  local res = self:visitEach( 
    function( n, args )
      local res
      if n.kind=="input" or n.kind=="constant" or n.kind=="readGlobal" then
        local rate = {{1,1}}
        if n.kind=="input" and n.sdfRate~=nil then 
          err( SDFRate.isSDFRate(n.sdfRate),"sdf rate not an sdf rate? "..n.kind..n.loc)
          rate=n.sdfRate; 
        end
        res = {rate,J.broadcast(true,#rate)}
        if DARKROOM_VERBOSE then print("INPUT",n.name,"converged=",res[2][1],"RATE",res[1][1][1],res[1][1][2]) end
      elseif n.kind=="applyMethod" then
        if n.fnname=="load" then
          if registeredInputRates[n.inst]==nil then
            res = {{{1,1}},{false}} -- just give it an arbitrary rate (we have no info at this point)
          else
            res = n.inst.fn:sdfTransfer(registeredInputRates[n.inst], "APPLY LOAD "..n.loc)
          end
        elseif n.fnname=="store" then
          registeredInputRates[n.inst] = args[1]
          -- rate doesn't matter
          assert( SDFRate.isSDFRate(args[1][1]))
          assert(type(args[1][2][1])=="boolean")
          res = {args[1][1],args[1][2]}
        elseif n.fnname=="start" or n.fnname=="done" then
          -- just pass through
          res = {args[1][1],args[1][2]}
        else
          err( false, "sdfTotalInner: unknown method '"..n.fnname.."'" )
        end
      elseif n.kind=="apply" then
        if #n.inputs==0 then
          assert( SDFRate.isSDFRate(n.fn.sdfOutput))
          res = {n.fn.sdfOutput,J.broadcast(true,#n.fn.sdfOutput)}

          if n.sdfRateOverride~=nil then
            assert( SDFRate.isSDFRate(n.sdfRateOverride))
            res[1] = n.sdfRateOverride
          end
	  
          if DARKROOM_VERBOSE then print("NULLARY",n.name,n.fn.kind,"converged=",res[2][1],"RATE",res[1][1][1],res[1][1][2]) end
        elseif #n.inputs==1 then
          res =  n.fn:sdfTransfer(args[1], "APPLY "..n.name.." "..n.loc)
          if DARKROOM_VERBOSE then print("APPLY",n.name,n.fn.kind,"converged=",res[2][1],"RATE",res[1][1][1],res[1][1][2]) end
        else
          assert(false)
        end
      elseif n.kind=="concat" or n.kind=="concatArray2d" then
        if n.inputs[1]:outputStreams()==0 then
          -- for non-handshake values (i.e. no streams), we just count this as 1 output stream
          
          local IR, allConverged, ratesMatch
          -- all input rates must match!
          for key,i in pairs(n.inputs) do
            assert(#args[key][1]==1)
            local isdf = args[key][1][1]
            local iconverged = args[key][2][1]

            if IR==nil then IR=isdf; allConverged = iconverged; ratesMatch=true end
            if isdf[1]~=IR[1] or isdf[2]~=IR[2] then
              ratesMatch=false
              print("SDF "..n.kind.." rate mismatch "..n.loc)
            end
          end
          res = {{IR},{allConverged and ratesMatch}}
          if DARKROOM_VERBOSE then print("CONCAT",n.name,"converged=",res[2][1],"RATE",res[1][1][1],res[1][1][2]) end
        else
          res = {{},{}}
          for k,v in ipairs(args) do
            assert( SDFRate.isSDFRate( v[1] ) )
            table.insert(res[1], v[1][1])
            table.insert(res[2], v[2][1])
          end
  
          if DARKROOM_VERBOSE then
            print("CONCAT",n.name)
            for k,v in ipairs(res[2]) do
              print("        concat["..tostring(k).."] converged=",v,"RATE",res[1][k][1],res[1][k][2])
            end
          end
        end
      elseif n.kind=="statements" then
        local allConverged = true
        for _,arg in pairs(args) do
          for k,v in pairs(arg[2]) do 
            assert(type(v)=="boolean"); 
            allConverged=allConverged and v 
          end
        end
        res = { args[1][1], { allConverged } }
      elseif n.kind=="selectStream" then
        assert( #args==1 )
        assert( SDFRate.isSDFRate(args[1][1]) )
        err( args[1][1][n.i+1]~=nil, "selectStream "..tostring(n.i)..": stream does not exist! There are only "..tostring(#args[1][1]).." streams."..n.loc )
        res = { {args[1][1][n.i+1]}, {args[1][2][n.i+1]} }
      else
        print("sdftotal",n.kind)
        assert(false)
      end

      assert( SDFRate.isSDFRate(res[1]) )
      J.map( res[2], function(n) assert(type(n)=="boolean") end )

      __sdfTotalCache[n] = res[1]
      return res
    end)

  -- output is format {{sdfRateInput1,...}, {convergedInput1,...} }

  -- check if all are converged
  for k,v in pairs(res[2]) do
    assert(type(v)=="boolean")
    if v==false then return false end
  end
  
  return true
end

function darkroomIRFunctions:outputStreams() return darkroom.streamCount(self.type) end

local __sdfConverged = {}
function darkroomIRFunctions:sdfTotal(root)
  assert(darkroom.isIR(root))
  if __sdfConverged[root]==nil then
    local iter, converged = 10, false
    local registeredInputRates = {} -- hold the rate of back edges between iterations
    while iter>=0 and converged==false do
      if DARKROOM_VERBOSE then print("SDF ITER", iter,"-------------------------------------") end
      converged = root:sdfTotalInner( registeredInputRates )
      iter = iter - 1
    end
    err( converged==true, "Error, SDF solve failed to converge. Do you have a feedback loop?" )
    __sdfConverged[root] = converged
  end

  assert( type(__sdfTotalCache[self])=="table" )
  return __sdfTotalCache[self]
end

-- This converts our stupid internal represention into the SDF 'rate' used in the SDF paper
-- i.e. the number you multiply the input/output rate by to make the rates match.
-- Meaning for us: if < 1, then not is underutilized (sits idle). If >1, then node is
-- oversubscribed (will limit speed)
function darkroomIRFunctions:calcSdfRate(root)
  assert(darkroom.isIR(root))

  if self.kind=="apply" then
    assert(#self.inputs<=1)
    local total = self:sdfTotal(root)
    local res = SDFRate.fracMultiply({total[1][1],total[1][2]},{self.fn.sdfOutput[1][2],self.fn.sdfOutput[1][1]})
    if DARKROOM_VERBOSE then print("SDF RATE",self.name,res[1],res[2],"sdfINP",self.fn.sdfInput[1][1],self.fn.sdfInput[1][2],"SDFOUT",self.fn.sdfOutput[1][1],self.fn.sdfOutput[1][2]) end
    return res
  else
    return nil
  end
end

-- assuming that the inputs are running at {1,1}, wht is the lowest/highest SDF utilization in this DAG?
-- (this will limit the speed of the whole pipe)
-- In our implementaiton, the utilization of any node can't be >1, so if the highest utilization is >1, we need to scale the throughput of the whole pipe
local __sdfExtremeRateCache = {}
function darkroomIRFunctions:sdfExtremeRate( highest )
  err(type(highest)=="boolean", "sdfExtremeRate: first argument should be bool")

  __sdfExtremeRateCache[self] = __sdfExtremeRateCache[self] or {}

  if __sdfExtremeRateCache[self][highest]==nil then

    self:visitEach(
      function( n, args )
        local r = n:calcSdfRate(self)
        assert( SDFRate.isFrac(r) or r==nil )
        
        local res 

        if __sdfExtremeRateCache[self][highest]==nil and r~=nil then
          __sdfExtremeRateCache[self][highest] = {r,n.loc}
        elseif highest and r~=nil and SDFRate.fracToNumber(r)>=SDFRate.fracToNumber(__sdfExtremeRateCache[self][highest][1]) then
          __sdfExtremeRateCache[self][highest] = {r,n.loc}
        elseif highest==false and r~=nil and SDFRate.fracToNumber(r)<=SDFRate.fracToNumber(__sdfExtremeRateCache[self][highest][1]) then
          __sdfExtremeRateCache[self][highest] = {r,n.loc}
        end

      end)

    if __sdfExtremeRateCache[self][highest]==nil then
      -- no function calls => no changes to rate. (none of our other operators change rate)
      return {1,1},"NO_APPLIES"
    end
  end


  return __sdfExtremeRateCache[self][highest][1], __sdfExtremeRateCache[self][highest][2]
end

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
    J.map( n.inputs, function(i) err(i.type==n.inputs[1].type, "All inputs to array2d must have same type!") end )
    
    if darkroom.isHandshake(n.inputs[1].type) then
      n.type = darkroom.HandshakeArray( darkroom.extractData(n.inputs[1].type), n.W, n.H )
    elseif darkroom.isBasic(n.inputs[1].type) then
      n.type = types.array2d( n.inputs[1].type, n.W, n.H )
    else
      err(false,"concatArray2d: unsupported input type "..tostring(n.inputs[1].type))
    end
  elseif n.kind=="statements" then
    n.type = n.inputs[1].type
  elseif n.kind=="selectStream" then
    if darkroom.isHandshakeArray(n.inputs[1].type) then
      err( n.i < n.inputs[1].type.params.W, "selectStream index out of bounds")
      err( n.j==nil or (n.j < n.inputs[1].type.params.H), "selectStream index out of bounds")
      n.type = darkroom.Handshake(n.inputs[1].type.params.A)
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
    err( n.global.direction=="input", "Error, attempted to read a global output ("..n.global.name..")" )
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

        module:lookupFunction("reset"):addPipeline( I[n.fnname.."_reset"](I,nil,module:lookupFunction("reset"):getValid()) )
        local inp = inputs[1]
        if inp~=nil then inp=inp[1] end
        return {I[n.fnname](I,inp)}
      elseif n.kind=="apply" then
        err( n.fn.systolicModule~=nil, "Error, missing systolic module for "..n.fn.name)
        err( n.fn.systolicModule:lookupFunction("process")~=nil, "Error, missing process fn? "..n.fn.name)
        err( n.fn.systolicModule:lookupFunction("process"):getInput().type==darkroom.lower(n.fn.inputType), "Systolic type doesn't match fn type, fn '"..n.fn.name.."', is "..tostring(n.fn.systolicModule:lookupFunction("process"):getInput().type).." but should be "..tostring(darkroom.lower(n.fn.inputType)) )

        if n.fn.outputType==types.null() then
          err(n.fn.systolicModule.functions.process.output==nil, "Systolic output type doesn't match fn type, fn '"..n.fn.kind.."', is "..tostring(n.fn.systolicModule.functions.process.output).." but should be "..tostring(darkroom.lower(n.fn.outputType)) )
        else
          err(n.fn.systolicModule.functions.process.output.type == darkroom.lower(n.fn.outputType), "Systolic output type doesn't match fn type, fn '"..n.fn.name.."', is "..tostring(n.fn.systolicModule.functions.process.output.type).." but should be "..tostring(darkroom.lower(n.fn.outputType)) )
        end
        
        err(type(n.fn.stateful)=="boolean", "Missing stateful annotation "..n.fn.name)

--        local SC = {}
--        for g,_ in pairs(n.fn.globals) do
--          SC[g.systolicValue] = g.systolicValue
--          if g.systolicValueReady~=nil then SC[g.systolicValueReady] = g.systolicValueReady end
--        end
        
        local I = module:add( n.fn.systolicModule:instantiate(n.name) )

        if darkroom.isHandshakeAny( n.fn.inputType ) or
        darkroom.isHandshakeAny(n.fn.outputType) then
          err(I.module.functions["reset"]~=nil,"missing reset function? instance '"..I.name.."' of module '"..I.module.name.."'")
          module:lookupFunction("reset"):addPipeline( I:reset(nil,module:lookupFunction("reset"):getValid()) )
        elseif n.fn.stateful then
          module:lookupFunction("reset"):addPipeline( I:reset() )
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
  
  return darkroom.newIR( {kind="input", type = ty, name="input", id={}, inputs={}, sdfRate=sdfRate, loc=getloc()} )
end

function darkroom.readGlobal( name, g, X )
  err( type(name)=="string", "rigel.readGlobal: name must be string" )
  err( darkroom.isGlobal(g),"readGlobal: input must be rigel global" )
  err(X==nil,"readGlobal: too many arguments")
  return darkroom.newIR{kind="readGlobal",name=name,global=g,type=g.type,loc=getloc(),inputs={}}
end

function darkroom.writeGlobal( name, g, input, X )
  err( type(name)=="string", "rigel.writeGlobal: name must be string" )
  err( darkroom.isGlobal(g),"writeGlobal: first argument must be rigel global" )
  err( darkroom.isIR(input),"writeGlobal: second argument must be rigel value" )
  err(X==nil,"writeGlobal: too many arguments")
  return darkroom.newIR{kind="writeGlobal",name=name,global=g,loc=getloc(),inputs={input},type=types.null()}
end

function darkroom.instantiateRegistered( name, fn )
  err( type(name)=="string", "name must be string")
  err( darkroom.isFunction(fn), "fn must be function" )
  err( fn.registered, "fn must be registered")
  local t = {name=name, fn=fn}
  return setmetatable(t, darkroomInstanceMT)
end

-- sdfRateOverride: override the firing rate of this apply. useful for nullary modules.
function darkroom.apply( name, fn, input, sdfRateOverride )
  err( type(name) == "string", "first argument to apply must be name" )
  err( darkroom.isFunction(fn), "second argument to apply must be a darkroom function" )
  err( input==nil or darkroom.isIR( input ), "last argument to apply must be darkroom value or nil" )
  err( sdfRateOverride==nil or SDFRate.isSDFRate(sdfRateOverride), "sdfRateOverride must be SDF rate" )

  if darkroom.isGenerator(fn) then
    fn = fn{input.type}
  elseif darkroom.isInstanceCallsite(fn) then
    return darkroom.applyMethod( name, fn.instance, fn.functionName, input )
  end

  if darkroom.isModule(fn)==false then
    print("Generator '"..table.concat(fn.name,".").."' could not be resolved into a module?")
    print("Unbounded args: "..fn:listArgs())
    assert(false)
  end
  
  return darkroom.newIR( {kind = "apply", name = name, loc=getloc(), fn = fn, inputs = {input}, sdfRateOverride=sdfRateOverride } )
end

function darkroom.applyMethod( name, inst, fnname, input )
  err( type(name)=="string", "name must be string")
  err( darkroom.isInstance(inst), "applyMethod: second argument should be instance" )
  err( type(fnname)=="string", "fnname must be string")
  err( input==nil or darkroom.isIR( input ), "applyMethod: last argument should be rigel value or nil" )

  return darkroom.newIR( {kind = "applyMethod", name = name, fnname=fnname, loc=getloc(), inst = inst, inputs = {input} } )
end

function darkroom.constant( name, value, ty )
  err( type(name) == "string", "constant name must be string" )
  err( types.isType(ty), "constant type must be rigel type" )
  ty:checkLuaValue(value)

  return darkroom.newIR( {kind="constant", name=name, loc=getloc(), value=value, type=ty, inputs = {}} )
end

function darkroom.concat( name, t, X )
  local r = {kind="concat", name=name, loc=getloc(), inputs={} }
  
  if name==nil then
    r.defaultName=true
    r.name="concat"..darkroom.__unnamedID
    darkroom.__unnamedID = darkroom.__unnamedID+1
  else
    err( type(name)=="string", "first tuple input should be name")
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
  err( type(i)=="number", "i must be number")
  err( darkroom.isIR(input), "input must be IR")
  err(X==nil,"selectStream: too many arguments")
  return darkroom.newIR({kind="selectStream", name=name, i=i, loc=getloc(), inputs={input}})
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
      end
    end)
  return HANDSHAKE_MODE
end

function darkroom.export(t)
  if t==nil then t=_G end

  -- constants
  local t_c = function(arg)
    J.err( type(arg)=="table", "c: argument should be table" )
    J.err( #arg==2, "c: should have 2 args" )

    local ty, val
    if types.isType(arg[1]) then
      ty = arg[1]
      val = arg[2]
    else
      ty = arg[2]
      val = arg[1]
    end

    local res = darkroom.constant("const"..darkroom.__unnamedID,val,ty)
    res.defaultName = true
    darkroom.__unnamedID = darkroom.__unnamedID+1

    return res
  end

  rawset(t,"c",t_c)
end

return darkroom
