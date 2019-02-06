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
systolicFunctionConstructorMT={__index=systolicFunctionConstructor}

function sugar.isFunctionConstructor(t) return getmetatable(t)==systolicFunctionConstructorMT end

function sugar.lambdaConstructor( name, inputType, inputName, validName )
  err( type(name)=="string", "name must be string")
  err( inputType==nil or types.isType(inputType), "inputType must be type")
  err( inputType==nil or type(inputName)=="string", "input name must be string")

  local t = {name=name, isComplete=false, pipelines={} }
  if inputType~=nil then t.inputParameter=systolic.parameter(inputName, inputType) 
  else t.inputParameter=systolic.parameter(name.."_NULL_INPUT",types.null()) end

  if type(validName)=="string" then t.validParameter = systolic.parameter(validName, types.bool()) end
  return setmetatable(t, systolicFunctionConstructorMT)
end

function systolicFunctionConstructor:getInput() return self.inputParameter end
function systolicFunctionConstructor:getValid() 
  --err(self.validParameter~=nil, "validName was not passed at creation time"); 
  return self.validParameter 
end
function systolicFunctionConstructor:getCE() 
  --err(self.CEparameter~=nil, "CE not given"); 
  return self.CEparameter 
end
function systolicFunctionConstructor:setOutput( o, oname ) 
  err( self.isComplete==false, "function is already complete"); 
  assert(systolic.isAST(o)); 
  err(type(oname)=="string", "output must be given a name")
  self.output = o;
  self.outputName = oname
end
function systolicFunctionConstructor:getOutputName() return self.outputName end
function systolicFunctionConstructor:getOutput() return self.output end

function systolicFunctionConstructor:setCE( ce ) 
  err( self.isComplete==false, "function is already complete"); 
  assert( systolic.isAST(ce) and ce.kind=="parameter" and ce.type==types.bool(true) )
  self.CEparameter = ce 
end

function systolicFunctionConstructor:addPipeline( p ) 
  err( self.isComplete==false, "function is already complete"); 
  assert(systolic.isAST(p)); 
  table.insert( self.pipelines, p )
end

function systolicFunctionConstructor:complete()
  if self.isComplete==false then
    self.fn = systolic.lambda( self.name, self.inputParameter, self.output, self.outputName, self.pipelines, self.validParameter, self.CEparameter )
    self.isComplete=true
  end
  return self.fn
end

function systolicFunctionConstructor:isPure() self:complete(); return self.fn:isPure() end

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
  local t = { __name=name, __functions={}, __instances={}, isComplete=false, __usedInstanceNames={}, __instanceMap={}, __options={}, __sideChannels={} }

  return setmetatable( t, systolicModuleConstructorMT )
end

function systolicModuleConstructor:add( inst,X )
  err(X==nil,"systolicsugar: too many arguments")
  err( systolic.isInstance(inst), "must be an instance" )

  checkReserved(inst.name)
  if self.__usedInstanceNames[inst.name]~=nil then
    print("Error, instance name "..inst.name.." already in use")
    assert(false)
  end

  self.__instanceMap[inst] = 1
  self.__usedInstanceNames[inst.name] = inst

  table.insert(self.__instances,inst)
  return inst
end

function systolicModuleConstructor:lookupInstance( instName,X )
  err(X==nil,"systolicsugar: too many arguments")
  assert( type(instName)=="string")
  err( systolic.isInstance(self.__usedInstanceNames[instName]), "Could not find instance named '"..instName.."' on module")
  return self.__usedInstanceNames[instName]
end

function systolicModuleConstructor:lookupFunction( funcName,X )
  err(X==nil,"systolicsugar: too many arguments")
  return self.__functions[funcName]
end

function systolicModuleConstructor:addFunction( fn, X )
  err(X==nil,"systolicsugar: too many arguments")
  err( self.isComplete==false, "module is already complete")
  err( systolic.isFunction(fn) or sugar.isFunctionConstructor(fn), "input must be a systolic function")

  if self.__usedInstanceNames[fn.name]~=nil then
    print("Error, function name "..fn.name.." already in use")
    assert(false)
  end

  self.__functions[fn.name]=fn
  fn.module = self
  return fn
end

function systolicModuleConstructor:onlyWire(v) err( self.isComplete==false, "module is already complete"); self.__options.onlyWire=v; return self end
function systolicModuleConstructor:verilog(v) err( self.isComplete==false, "module is already complete"); self.__options.verilog=v; return self end
function systolicModuleConstructor:parameters(p) err( self.isComplete==false, "module is already complete"); self.__options.parameters=p; return self end

function systolicModuleConstructor:addSideChannel(sc,X)
  err(X==nil,"systolicsugar: too many arguments")
  err( self.isComplete==false, "module is already complete");
  err( systolic.isSideChannel(sc),":addSideChannel must be side channel")
  self.__sideChannels[sc] = 1
  return self
end

function systolicModuleConstructor:complete()
  if self.isComplete==false then
    local fns = J.map(self.__functions, function(f) if sugar.isFunctionConstructor(f) then return f:complete() else return f end end)
    self.module = systolic.module.new( self.__name, fns, self.__instances, self.__options.onlyWire, self.__options.parameters, self.__options.verilog, self.__options.verilogDelay, self.__sideChannels )
    self.isComplete = true
  end
end

-- convert to plain module
function systolicModuleConstructor:toModule()
  self:complete()
  return self.module
end

function systolicModuleConstructor:setDelay( fnname, delay, X )
  err(X==nil,"systolicsugar: too many arguments")
  assert(type(fnname)=="string")
  assert(type(delay)=="number")
  self.__options.verilogDelay = self.options.verilogDelay or {}
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
