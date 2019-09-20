local types = require "types"
local systolic = require "systolic"
local J = require "common"
local err = J.err
local checkReserved = J.verilogCheckReserved


local sugar = {}

-- generates a class that provides a nice interface for setting optional parameters
local function moduleConstructor(tab)
  local constFunctions=tab.configFns
  function constFunctions:complete()
    if self.isComplete==false then
      self.module = tab.complete(self)
      assert( systolic.isModule(self.module) )
      self.isComplete = true
    end
  end
  function constFunctions:instantiate(...)
    self:complete()
    return self.module:instantiate(...)
  end

  local constMT = {__index=constFunctions}
  return function(...)
    local t = tab.new(...)
    t.isComplete=false
    return setmetatable(t,constMT)
  end
end



sugar.regConstructor = moduleConstructor{
new=function(ty) return {type=ty,hasCE=false} end,
complete=function(self) return systolic.module.reg( self.type, self.hasCE, self.init) end,
configFns={setInit=function(self,I) self.type:checkLuaValue(I); self.init=I; return self end,
CE=function(self,I) self.hasCE=I; return self end}
}

sugar.regByConstructor = moduleConstructor{
new=function( ty, setby )
  assert( types.isType(ty) )
  if sugar.isModuleConstructor(setby) then setby=setby:complete() end
  assert( systolic.isModule(setby) )
  assert( setby:getDelay( "process" ) == 0 )
  return {type=ty, setby=setby}
end,
complete=function(self)
  local fpgamodules = require "fpgamodules"
  return fpgamodules.regBy( self.type, self.setby, self.CE, self.init, self.resetValue, self.hasSetFn )
end,
configFns={CE=function(self,v) self.CE=v; return self end, 
hasSet=function(self,v) err(type(v)=="boolean", "hasSet should be bool");self.hasSetFn=v; return self end, 
setInit=function(self,I) self.type:checkLuaValue(I); self.init=I; return self end,
setReset=function(self,I) self.type:checkLuaValue(I); self.resetValue=I; return self end}
}

--------------------------------------------------------------------
-- Syntax sugar for incrementally defining a function
--------------------------------------------------------------------

systolicFunctionConstructor = {}
systolicFunctionConstructorMT={
  __index=systolicFunctionConstructor,
  __tostring=function(tab) return "SystolicFunctionConstructor "..tab.__name end}

function sugar.isFunctionConstructor(t) return getmetatable(t)==systolicFunctionConstructorMT end

function sugar.lambdaConstructor( name, inputType, inputName, validName )
  err( type(name)=="string", "name must be string")
  err( inputType==nil or types.isType(inputType), "inputType must be type")
  err( inputType==nil or type(inputName)=="string", "input name must be string")

  local t = {__name=name, isComplete=false, __pipelines={} }
  if inputType~=nil then t.__inputParameter=systolic.parameter(inputName, inputType) 
  else t.__inputParameter=systolic.parameter(name.."_NULL_INPUT",types.null()) end

  if type(validName)=="string" then t.__validParameter = systolic.parameter(validName, types.bool()) end
  return setmetatable(t, systolicFunctionConstructorMT)
end

function systolicFunctionConstructor:getInput() return self.__inputParameter end
function systolicFunctionConstructor:getValid() 
  --err(self.validParameter~=nil, "validName was not passed at creation time"); 
  return self.__validParameter 
end
function systolicFunctionConstructor:getCE() return self.__CEparameter end

function systolicFunctionConstructor:setOutput( o, oname ) 
  err( self.isComplete==false, "function is already complete"); 
  err( systolic.isAST(o),":setOutput(), output is not a systolic ast, but is: ",o); 
  err(o.type==types.null() or type(oname)=="string", "output must be given a name")
  self.__output = o;
  self.__outputName = oname
end
function systolicFunctionConstructor:getOutputName() return self.__outputName end
function systolicFunctionConstructor:getOutput() return self.__output end

function systolicFunctionConstructor:setCE( ce ) 
  err( self.isComplete==false, "function is already complete");
  if ce~=nil then
    err( systolic.isAST(ce) and ce.kind=="parameter" and ce.type==types.bool(true), "CE wasn't as expected: "..tostring(ce) )
    self.__CEparameter = ce
  end
end

function systolicFunctionConstructor:setValid( validName ) 
  err( self.isComplete==false, "function is already complete");
  self.__validParameter = systolic.parameter( validName, types.bool() )
end

function systolicFunctionConstructor:addPipeline( p ) 
  err( self.isComplete==false, "function is already complete"); 
  err( systolic.isAST(p), "systolicFunctionConstructor:addPipeline(), input should be systolic AST, but is: "..tostring(p) )
  table.insert( self.__pipelines, p )
end

function systolicFunctionConstructor:clearPipelines() self.__pipelines={} end

function systolicFunctionConstructor:complete()
  if self.isComplete==false then
    self.__fn = systolic.lambda( self.__name, self.__inputParameter, self.__output, self.__outputName, self.__pipelines, self.__validParameter, self.__CEparameter )
    self.isComplete=true
  end
  return self.__fn
end

function systolicFunctionConstructor:isPure() self:complete(); return self.__fn:isPure() end

--------------------------------------------------------------------
-- Syntax sugar for incrementally defining a module
--------------------------------------------------------------------

systolicModuleConstructor = {}
systolicModuleConstructorMT={__index=systolicModuleConstructor}

function systolicModuleConstructorMT.__tostring(tab)
  tab:complete()
  return tostring(tab.module)
end

function sugar.isModuleConstructor(I) return getmetatable(I)==systolicModuleConstructorMT end

function sugar.moduleConstructor( name, X )
  assert(type(name)=="string")
  assert(X==nil)
  checkReserved(name)

  -- we need to put the options in their own table, b/c otherwise nil options will go to the __index metamethod
  local t = { __name=name, __functions={}, isComplete=false, __usedNames={}, __instanceMap={}, __options={}, __sideChannels={}, __externalInstances={}, __providesMap={} }

  return setmetatable( t, systolicModuleConstructorMT )
end

-- externalFnMap: if this is nil, add this instance as an internal instances
--                otherwise, externalFnLst should be a map of fnnames (ie externalFnMap[inst][fnname])
function systolicModuleConstructor:add( inst, X )
  err(X==nil,"systolicsugar: too many arguments")

  err( systolic.isInstance(inst), "must be an instance" )

  checkReserved(inst.name)
  if self.__usedNames[inst.name]~=nil then
    print("Error, instance name '"..inst.name.."' of module '"..inst.module.name.."' already in use")
    assert(false)
  end

  self.__instanceMap[inst] = 1
  self.__usedNames[inst.name] = inst

  return inst
end

function systolicModuleConstructor:addExternal( inst, fnmap, X )
  err( fnmap==nil or type(fnmap)=="table","systolicsugar: external fn list should be table of strings" )
  err(X==nil,"systolicsugar: too many arguments")
  err( systolic.isInstance(inst), "must be an instance" )

  checkReserved(inst.name)

  -- we can refer to an external inst multiple times, that is ok
--  if self.__usedInstanceNames[inst.name]~=nil then
--    print("Error, instance name "..inst.name.." already in use")
--    assert(false)
--  end

  if self.__externalInstances[inst]==nil then
    self.__externalInstances[inst] = {}
  end
  
  for k,v in pairs(fnmap) do
    self.__externalInstances[inst][k]=1
  end
  
  self.__usedNames[inst.name] = inst

  return inst
end

-- add reference to external fn on an instance
function systolicModuleConstructor:addExternalFn( inst, fnname, X )
  assert(type(fnname)=="string")

  if self.__instanceMap[inst]==nil then
    return self:addExternal(inst,{[fnname]=1})
  else
    self.__externalInstances[inst][fnname]=1
    return inst
  end
end

function systolicModuleConstructor:addProvidesFn( inst, fnname, X )
  err( type(fnname)=="string","addProvidesFn: fnname should be string")
  err(X==nil,"systolicsugar: too many arguments")
  err( systolic.isInstance(inst), "must be an instance" )

  checkReserved(inst.name)

  if self.__providesMap[inst]==nil then
    self.__providesMap[inst] = {}
  end
  
  self.__providesMap[inst][fnname]=1
  
  self.__usedNames[inst.name] = inst

  return inst
end

function systolicModuleConstructor:lookupInstance( instName,X )
  err(X==nil,"systolicsugar: too many arguments")
  assert( type(instName)=="string")
  err( systolic.isInstance(self.__usedNames[instName]), "Could not find instance named '"..instName.."' on module")
  return self.__usedNames[instName]
end

function systolicModuleConstructor:lookupFunction( funcName,X )
  err(X==nil,"systolicsugar: too many arguments")
  return self.__functions[funcName]
end

function systolicModuleConstructor:addFunction( fn, X )
  err(X==nil,"systolicsugar: too many arguments")
  err( self.isComplete==false, "module is already complete")
  err( systolic.isFunction(fn) or sugar.isFunctionConstructor(fn), "input must be a systolic function")

  if self.__usedNames[fn.name]~=nil then
    print("Error, function name "..fn.name.." already in use")
    assert(false)
  end

  if sugar.isFunctionConstructor(fn) then
    self.__functions[fn.__name]=fn
  else
    self.__functions[fn.name]=fn
  end
  
  fn.module = self
  return fn
end

function systolicModuleConstructor:onlyWire(v) err( self.isComplete==false, "module is already complete"); self.__options.onlyWire=v; return self end
function systolicModuleConstructor:verilog(v) err( self.isComplete==false, "module is already complete"); self.__options.verilog=v; return self end
function systolicModuleConstructor:parameters(p) err( self.isComplete==false, "module is already complete"); self.__options.parameters=p; return self end

function systolicModuleConstructor:complete()
  if self.isComplete==false then
    local fns = J.map(self.__functions, function(f) if sugar.isFunctionConstructor(f) then return f:complete() else return f end end)
    self.module = systolic.module.new( self.__name, fns, J.invertAndStripKeys(self.__instanceMap), self.__options.onlyWire, self.__options.parameters, self.__options.verilog, self.__options.verilogDelay, self.__externalInstances, self.__providesMap )
    self.isComplete = true
  end
  return self.module
end

-- convert to plain module
function systolicModuleConstructor:toModule()
  self:complete()
  return self.module
end

function systolicModuleConstructor:setName( name, X ) self.__name=name end

function systolicModuleConstructor:setDelay( fnname, delay, X )
  err(X==nil,"systolicsugar: too many arguments")
  assert(type(fnname)=="string")
  assert(type(delay)=="number")
  self.__options.verilogDelay = self.__options.verilogDelay or {}
  self.__options.verilogDelay[fnname]=delay
end

function systolicModuleConstructor:getDelay( fnname, X )
  err(X==nil,"systolicsugar: too many arguments")
  self:complete()
  return self.module:getDelay( fnname )
end

function systolicModuleConstructor:toVerilog(X)
  err(X==nil,"systolicsugar: too many arguments")
  self:complete()
  return self.module:toVerilog()
end


function systolicModuleConstructor:getDependencies(X)
  err(X==nil,"systolicsugar: too many arguments")
  self:complete()
  return self.module:getDependencies()
end

function systolicModuleConstructor:instantiate( name, options, sideChannels, X )
  err(X==nil,"systolicsugar: too many arguments")
  self:complete()
  return self.module:instantiate( name, options, sideChannels )
end

return sugar
