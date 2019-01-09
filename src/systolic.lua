local IR = require("ir")
local types = require("types")
local typecheckAST = require("typecheck")
local systolic={}
local J = require "common"
local err = J.err
local memoize = J.memoize

systolicModuleFunctions = {}
systolicModuleMT={__index=systolicModuleFunctions}

systolicInstanceFunctions = {}

systolicAST = {}
function systolicAST.isSystolicAST(ast)
  return getmetatable(ast)==systolicASTMT
end
systolic.isAST = systolicAST.isSystolicAST
systolic.ast = systolicAST

local __usedNameCnt = 0
function systolicAST.new(tab)
  assert(type(tab)=="table")
  assert(type(tab.inputs)=="table")
  err(#tab.inputs==J.keycount(tab.inputs), "systolicAST.new inputs list is not a well formed array ("..tostring(tab.kind)..")")
  if tab.name==nil then tab.name="unnamed"..tab.kind..__usedNameCnt; __usedNameCnt=__usedNameCnt+1 end
  assert(types.isType(tab.type))
  assert(type(tab.loc)=="string")
  if tab.pipelined==nil then tab.pipelined=true end
  J.map(tab.inputs, function(n) assert(systolicAST.isSystolicAST(n)) end)
  IR.new(tab)
  return setmetatable(tab,systolicASTMT)
end


local function getloc()
--  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline
  return debug.traceback()
end

local sanitize = J.verilogSanitize

local function checkast(ast) err( systolicAST.isSystolicAST(ast), "input should be a systolic AST" ); return ast end

local function typecheck(ast)
  return systolicAST.new( typecheckAST(ast,systolicAST.new) )
end

local checkReserved = J.verilogCheckReserved


local binopToVerilog={["+"]="+",["*"]="*",["<<"]="<<<",[">>"]=">>>",["pow"]="**",["=="]="==",["and"]="&",["or"]="|",["-"]="-",["<"]="<",[">"]=">",["<="]="<=",[">="]=">="}

local binopToVerilogBoolean={["=="]="==",["and"]="&&",["~="]="!=",["or"]="||",["xor"]="^"}

function systolic.declareReg(ty, name, initial, comment)
  assert(type(name)=="string")

  if comment==nil then comment="" end

  if initial==nil or initial=="" then 
    initial=""
  else
    initial = " = "..systolic.valueToVerilog(initial,ty)
  end

  if ty:isBool() then
    return "reg "..name..initial..";"..comment
  else
    return "reg ["..(ty:verilogBits()-1)..":0] "..name..initial..";"..comment
 end
end
declareReg = systolic.declareReg

function systolic.declareWire( ty, name, str, comment )
  assert( types.isType(ty) )
  assert(type(str)=="string" or str==nil)

  if comment==nil then comment="" end

  if str == nil or str=="" then
    str = ""
  else
    str = "assign "..name.." = "..str.."; "
  end

  assert( ty~=types.null() )
  if ty:isBool() then
    return "wire "..name..";"..str..comment
  else
    return "wire ["..(ty:verilogBits()-1)..":0] "..name..";"..str..comment
  end
end
declareWire = systolic.declareWire

function systolic.wireIfNecessary( alreadyWiredSet, declarations, ty, name, str, comment )
  assert(type(alreadyWiredSet)=="table")
  if alreadyWiredSet[name]~=nil then return str end
  local decl = systolic.declareWire( ty, name, str, comment)
  table.insert(declarations, decl)
  alreadyWiredSet[name] = 1
  return name
end

function systolic.declarePort( ty, name, isInput )
  err( type(name)=="string","declarePort: name should be string but is "..tostring(name))

  local t = "input wire "
  if isInput==false then t = "output wire " end

  assert( ty~=types.null() )
  if ty:isBool()==false and ty:verilogBits()>1 then
    t = t .."["..(ty:verilogBits()-1)..":0] "
  end
  t = t..name
  
  return t
end

function channelIndex( ty, c )
  assert(darkroom.type.isType(ty))
  assert(type(c)=="number")

  if ty:channels()==1 then
    return ""
  elseif ty:baseType():isBool() then
    assert(false)
  else
    return "["..(c*ty:baseType():sizeof()*8-1)..":"..((c-1)*ty:baseType():sizeof()*8).."]"
  end
end

function numToVarname(x)
  if x>0 then return x end
  if x==0 then return "0" end
  return "m"..math.abs(x)
end

function pointerToVarname(x)
  assert(type(x)=="table")
  return tostring(x):sub(10)
end

function valueToVerilogLL(value,signed,bits)
  assert(type(value)=="number")
  assert(value==math.floor(value))
  if signed==false then assert(value>=0) end

  if signed then
    if value==0 then
      return bits.."'d0"
    elseif value<0 then
      return "-"..bits.."'d"..math.abs(value)
    else
      return bits.."'d"..value
    end
  else
    assert(value>=0)
    err(value < math.pow(2,bits),"valueToVerilog: value out of range for type, "..tostring(value)..", bits:"..tostring(bits)) -- probably a mistake
    return bits.."'d"..math.abs(value)
  end
end

function systolic.valueToVerilog( value, ty )
  J.err(types.isType(ty),"systolic.valueToVerilog: not a type")

  if ty:isInt() then
    return valueToVerilogLL( value, true, ty:verilogBits() )
  elseif ty:isUint() or ty:isBits() then
    return valueToVerilogLL( value, false, ty:verilogBits() )
  elseif ty:isBool() then
    assert(type(value)=="boolean")
    if value then
      return "1'd1"
    else
      return "1'd0"
    end
  elseif ty:isArray() then
    assert(type(value)=="table")
    assert(#value==ty:channels())
    return "{"..table.concat( J.reverse( J.map( value, function(v) return systolic.valueToVerilog(v,ty:arrayOver()) end ) ), "," ).."}"
  elseif ty:isTuple() then
    assert(type(value)=="table")
    assert(#value==#ty.list)
    return "{"..table.concat( J.reverse( J.map( value, function(v,k) return systolic.valueToVerilog(v,ty.list[k]) end ) ), "," ).."}"
  elseif ty==types.float(32) then
    local ffi = require("ffi")
    local a = ffi.new("float[1]",value)
    local b = ffi.cast("unsigned int*",a)
    return "32'd"..tostring(b[0])
  elseif ty:isFloat() then
    return tostring(ty).."systolic.valueToVerilog_float_garbage)@(*%(*&^*%$)_@)(^&$" -- garbage
  elseif ty:isNamed() then
    return systolic.valueToVerilog(value,ty.structure)
  else
    print("valueToVerilog",ty)
    assert(false)
  end
end

function systolicModuleFunctions:instantiate( name, parameters, X )
  err( type(name)=="string", "instantiation name must be a string")
  err( X==nil,"instantiate: too many arguments" )
  err( name==sanitize(name), "instantiate: name must be verilog sanitized ("..name..") to ("..sanitize(name)..")")

  err( parameters==nil or type(parameters)=="table", "parameters must be table")

--  local A,B=0,0
--  if sideChannels~=nil then A=J.keycount(sideChannels) end
--  if self.sideChannels~=nil then B=J.keycount(self.sideChannels) end
--  err( A==B, "instantiate ("..name.."): # of input sideChannels ("..tostring(A)..","..tostring(sideChannels)..") must match expected # ("..tostring(B)..")")

--  local SC = {}

--  if self.sideChannels~=nil then
--    for k,_ in pairs(self.sideChannels) do
--        err( systolic.isSideChannel(sideChannels[k]), "instantiate: NYI - instantiate currently expects list of side channels, but is "..tostring(sideChannels[k]))
--        SC[k] = sideChannels[k]
--    end
--  end
  
  -- Instances are mutable (they collect callsites etc). We will only mutate it when final=false. Adding it to a module marks final=true (we can't mutate it anymore)
  return systolicInstance.new({ kind="module", module=self, name=name, parameters=parameters, callsites={}, arbitration={}, final=false, loc=getloc() })
end

function systolicModuleFunctions:lookupFunction( fnname )
  for k,v in pairs(self.functions) do
    if v.name==fnname then return v end
  end
  --print "Function "..fnname.." not found!")
  return nil
end

systolicFunctionFunctions = {}
systolicFunctionMT={__index=systolicFunctionFunctions}

function systolicFunctionMT.__tostring(tab)
  local res = {}
  table.insert(res,"\t\tInputParameter: "..tab.inputParameter.name.." : "..tostring(tab.inputParameter.type) )

  if tab.output~=nil then
    table.insert(res,"\t\tOutputType: "..tostring(tab.output.type))
  else
    table.insert(res,"\t\tOutputType: no output")
  end
  
  return table.concat(res,"\n")
end

systolicFunction = {}
function systolic.isFunction(t)
  return getmetatable(t)==systolicFunctionMT --or getmetatable(t)==systolicFunctionConstructorMT
end

function systolic.lambdaTab( tab )
  return systolic.lambda(tab.name, tab.input, tab.output, tab.outputName, tab.pipelines, tab.valid, tab.CE )
end

function systolic.lambda( name, inputParameter, output, outputName, pipelines, validParameter, CEParameter, X )
  err( systolicAST.isSystolicAST(inputParameter), "inputParameter must be a systolic AST, but is '"..tostring(inputParameter).."'" )
  err( systolicAST.isSystolicAST(output) or output==nil, "output must be a systolic AST or nil" )
  err( systolicAST.isSystolicAST(validParameter) or validParameter==nil, "valid parameter must be a systolic AST or nil" )
  if validParameter~=nil then err(validParameter.kind=="parameter","valid parameter must be parameter") end
  err( inputParameter.kind=="parameter", "input must be a parameter" )
  err( output==nil or (output~=nil and output.type==types.null()) or type(outputName)=="string", "output name must be a string if output is given, but is "..type(outputName))
  err( CEParameter==nil or (systolicAST.isSystolicAST(CEParameter) and CEParameter.kind=="parameter" and CEParameter.type==types.bool(true)), "CE Parameter must be nil or parameter")
  assert(X==nil)

  if pipelines==nil then pipelines={} end

  -- a (possibly unnecessary) sanity check
  for k,v in pairs(pipelines) do
    err(v~=output,"pipeline "..k.." is the same as the output!")
    for kk,vv in pairs(pipelines) do err(v~=vv or k==kk, "Pipeline "..k.." is the same as pipeline "..kk) end
  end
  J.err( J.keycount(pipelines)==#pipelines, "systolic.lambda: pipelines is not an array?" )

  local implicitValid = false
  if validParameter==nil then implicitValid=true; validParameter = systolic.parameter(name.."_valid", types.bool()) end
  
  if type(outputName)=="string" then outputName = sanitize(outputName) end
  local t = { name=name, inputParameter=inputParameter, output = output, outputName=outputName, pipelines=pipelines, valid=validParameter, implicitValid=implicitValid, CE=CEParameter }

  return setmetatable(t,systolicFunctionMT)
end

function systolicInstanceFunctions:setParameters( v )  self.parameters=v; return self end

function systolicInstanceFunctions:getDelay( fn )
  assert( systolic.isFunction(fn) )
  return self.module:getDelay( fn )
end

function systolicInstanceFunctions:toVerilog( module )
  return self.module:instanceToVerilog( self, module)
end

-- some functions don't modify state. These do not need a valid bit
function systolicFunctionFunctions:isPure()
  local purePipes = true
  -- it's possible for pipelines to end up being a noop, which are pure
  J.map( self.pipelines, function(n) purePipes = purePipes and n:isPure(self.valid) end )

  if self.output==nil then return purePipes end
  return self.output:isPure(self.valid) and purePipes
end

function systolicFunctionFunctions:getInput() return self.inputParameter end
function systolicFunctionFunctions:getOutput() return self.output end
function systolicFunctionFunctions:getOutputName() return self.outputName end
function systolicFunctionFunctions:getValid() return self.valid end
function systolicFunctionFunctions:getCE() return self.CE end

function systolicFunctionFunctions:isAccessor()
  return #self.inputs==0
end


function systolicFunctionFunctions:getDefinitionKey()
  assert(self.pure)
  return self
end

systolic.binop = function(lhs, rhs, op)
  lhs, rhs = checkast(lhs), checkast(rhs)
  return typecheck({kind="binop",op=op,inputs={lhs,rhs},loc=getloc()})
end

local binop=systolic.binop

local function unary(expr, op)
  expr = checkast(expr)
  return typecheck{kind="unary",op=op,inputs={expr},loc=getloc()}
end

systolic._callsites = {}
systolicInstance = {}
function systolicInstance.new(tab)
  return setmetatable(tab,systolicInstanceMT)
end

function systolic.isInstance(tab)
  return getmetatable(tab)==systolicInstanceMT
end

local function createCallsite( fn, fnname, instance, input, valid, CE, X )
--  assert( systolic.isFunction(fn) )
  assert( systolic.isInstance(instance) )
  assert( systolicAST.isSystolicAST(input))
  assert(X==nil)

  local otype = types.null()
  if fn.output~=nil then otype = fn.output.type end

  local t = { kind="call", inst=instance, fnname=fnname, func=fn, type=otype, loc=getloc(), inputs={input,valid,CE} }
  return systolicAST.new(t)
end

systolicInstanceMT={
__index = function(tab,key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  v = systolicInstanceFunctions[key]
    
  if v==nil and rawget(tab,"kind")=="module" then
    -- try to find key in function tab
    local fn = rawget(tab,"module").functions[key]
    --err( systolic.isFunction(fn), "Function "..key.." is not a function on module "..tab.module.kind.."?")
    if fn~=nil then
      return function(self, inp, valid, ce, X)
        assert(systolic.isInstance(self))
        err(tab.final==false, "Attempting to modify a finalized instance!")
        if inp==nil then inp = systolic.null() end -- give this a stub value that evaluates to nil
        err( systolicAST.isSystolicAST(inp), "input must be a systolic ast or nil" )
        err( valid==nil or systolicAST.isSystolicAST(valid), "valid must be a systolic ast or nil" )
        err( ce==nil or systolicAST.isSystolicAST(ce), "CE must be a systolic ast or nil" )
        assert(X==nil)
        
        tab.callsites[key] = tab.callsites[key] or {}
        tab.arbitration[key] = tab.arbitration[key] or {}

        if inp.type==fn.inputParameter.type then
          
        elseif inp.type==fn.inputParameter.type then
          --  stripping the Const-ness will cause problems when we CSE with multiple stall domains
          -- We don't actually need to insert an explicit cast, it doesn't matter. Cast would be a noop
--          inp = systolic.cast( inp, fn.inputParameter.type )
        else
          err( false, "Error, input type to function '"..fn.name.."' on instance '"..tab.name.."' of module '"..tostring(tab.module.name).."' incorrect. Is '"..tostring(inp.type).."' but should be '"..tostring(fn.inputParameter.type).."'" )
        end

        return createCallsite( fn, key, tab, inp, valid, ce )
      end
    end
    
  end
  return v
end}

systolicASTFunctions = {}
setmetatable(systolicASTFunctions,{__index=IR.IRFunctions})

if terralib~=nil then
  require "systolicTerra"
end

systolicASTMT={__index = systolicASTFunctions,
__add=function(l,r) return binop(l,r,"+") end, 
__sub=function(l,r) return binop(l,r,"-") end,
__mul=function(l,r) return binop(l,r,"*") end,
__call = function(tab, delayvalue)
  err( type(delayvalue)=="number", "delay must be a number")
  if tab.kind=="delay" then
    assert(false) -- we should merge them or do something more intelligent?
  elseif delayvalue==0 then
    return tab
  else
    return systolicAST.new({kind="delay",delay=delayvalue,inputs={tab},type=tab.type,loc=getloc()})
  end
end,
  __newindex = function(table, key, value)
                    error("Attempt to modify systolic AST node")
                  end}

function systolicASTFunctions:init()
  setmetatable(self,nil)
  systolicAST.new(self)
end

function systolic.cast( expr, ty )
  err( systolicAST.isSystolicAST(expr), "input to cast must be a systolic ast")
  err( types.isType(ty), "input to cast must be a type")
  return typecheck({kind="cast",inputs={expr},type=ty,loc=getloc()})
end

-- ops. idx, idy are inclusive
function systolic.slice( expr, idxLow, idxHigh, idyLow, idyHigh )
  assert(systolicAST.isSystolicAST(expr))
  err( type(idxLow)=="number", "idxLow should be a number" )
  err( type(idxHigh)=="number", "idxHigh should be a number" )
  if idyLow==nil then idyLow=0 end
  if idyHigh==nil then idyHigh=0 end
  return typecheck({kind="slice", idxLow=idxLow, idxHigh=idxHigh, idyLow=idyLow, idyHigh=idyHigh, inputs={expr}, loc=getloc()})
end

function systolic.index( expr, idx, idy )
  err( systolicAST.isSystolicAST(expr), "expr should be systolic value")
  err( type(idx)=="number", "index: idx must be number")
  err( type(idy)=="number" or idy==nil, "index: idy must be number or nil")
  
  -- slice will return an array or tuple with one element. so we need to do a cast.
  if expr.type:isArray() then
    return systolic.cast( systolic.slice(expr, idx, idx, idy, idy), expr.type:arrayOver() )
  elseif expr.type:isTuple() then
    local v = systolic.slice(expr, idx, idx, idy, idy)
    assert(#v.type.list==1)
    return systolic.cast( v, v.type.list[1] )
  end
  err(false, "Index only works on tuples and arrays, not "..tostring(expr.type))
end

-- low,high are inclusive
function systolic.bitSlice( expr, low, high, X )
  err( systolicAST.isSystolicAST(expr), "input to bitSlice must be a systolic ast")
  err( type(low)=="number", "bitSlice: low must be number")
  err( type(high)=="number", "bitSlice: high must be number")
  err( high>=low, "bitSlice: high<low, (low="..tostring(low)..",high="..tostring(high)..")" )
  err( X==nil, "systolic.bitSlice: too many arguments")
  return typecheck({kind="bitSlice",inputs={expr},low=low,high=high,loc=getloc()})
end

function systolic.constant( v, ty )
  err( types.isType(ty), "constant type must be a type")
  ty:checkLuaValue(v)
  return typecheck({ kind="constant", value=J.deepcopy(v), type = ty, loc=getloc(), inputs={} })
end

function systolic.readSideChannel( sc )
  err( systolic.isSideChannel(sc), "systolic.readSideChannel: input must be a side channel" )
  return typecheck({ kind="readSideChannel", sideChannel=sc, type = sc.type, loc=getloc(), inputs={} })
end

function systolic.writeSideChannel( sc, expr )
  err( systolic.isSideChannel(sc), "systolic.writeSideChannel: input must be a side channel" )
  err( systolicAST.isSystolicAST(expr), "input to writeSideChannel must be a systolic ast, but is:"..tostring(expr))
  return typecheck({ kind="writeSideChannel", sideChannel=sc, type = types.null(), loc=getloc(), inputs={expr} })
end

function systolic.tuple( tab )
  err( type(tab)=="table", "systolic.tuple: input to tuple should be a table")
  err( #tab==J.keycount(tab), "systolic.tuple: input must be a lua array")
  local res = {kind="tuple",inputs={}, loc=getloc()}
  J.map(tab, function(v,k) err( systolicAST.isSystolicAST(v), "input to tuple should be table of ASTs"); res.inputs[k]=v end )

  for k,v in ipairs(tab) do
    err(v.type:verilogBits()>0,"tuple input "..tostring(k-1).." size must be >0")
  end
  
  return typecheck(res)
end

-- concat multiple bit arrays together
function systolic.bitConcat( tab )
  assert(false) -- just do a tuple and a cast
end

-- tab should be in row major order
function systolic.array( tab, W, H )
  assert(false)
  -- just do a cast from a tuple to an array
end

local __NULLTAB = systolicAST.new({kind="null",type=types.null(),inputs={},loc="Null LOC"})
function systolic.null() return __NULLTAB end

function systolic.select( cond, a, b )
  err( systolicAST.isSystolicAST(cond), "cond must be a systolic AST")
  err( systolicAST.isSystolicAST(a), "a must be a systolic AST")
  err( systolicAST.isSystolicAST(b), "b must be a systolic AST")
  return typecheck({kind="select",inputs={cond,a,b},loc=getloc()})
end

function systolic.le(lhs, rhs) return binop(lhs,rhs,"<=") end
function systolic.eq(lhs, rhs) return binop(lhs,rhs,"==") end
function systolic.lt(lhs, rhs) return binop(lhs,rhs,"<") end
function systolic.ge(lhs, rhs) return binop(lhs,rhs,">=") end
function systolic.gt(lhs, rhs) return binop(lhs,rhs,">") end
function systolic.__or(lhs, rhs) return binop(lhs,rhs,"or") end
function systolic.__and(lhs, rhs) return binop(lhs,rhs,"and") end
function systolic.xor(lhs, rhs) return binop(lhs,rhs,"xor") end
function systolic.rshift(lhs, rhs) return binop(lhs,rhs,">>") end
function systolic.lshift(lhs, rhs) return binop(lhs,rhs,"<<") end
function systolic.neg(expr) return unary(expr,"-") end
function systolic.isX(expr) return unary(expr,"isX") end
function systolic.__not(expr) return unary(expr,"not") end
function systolic.abs(expr) return unary(expr,"abs") end

function systolicASTFunctions:cname(c)
  return self:name().."_c"..c
end


function checkForInst(inst, scopes)
  assert(systolicInstance.isSystolicInstance(inst))

  local fnd = false
  for k,scope in ipairs(scopes) do
    fnd = fnd or scope.instanceMap[inst]~=nil
  end
  
  if fnd==false then
    print("missing instance "..inst.name.." (kind "..inst.kind..")")
    J.map(scopes, function(n) print("scope",n.name) end)
    assert(false)
  end
end

function systolicASTFunctions:checkInstances( instMap )
  self:visitEach( 
    function(n)
      if n.kind=="call" then
        err( instMap[n.inst]~=nil, "Error, instance "..n.inst.name.." is not a member of this module, "..n.inst.loc )
      end
    end)
end

-- does this need a valid bit?
function systolicASTFunctions:isPure( validbit )
  assert( systolicAST.isSystolicAST(validbit) )

  return self:visitEach(
    function( n, inputs )
      if n.kind=="call" then
        assert(#inputs>=1)
        return n.func:isPure() and inputs[1]
      elseif n.kind=="parameter" then
        return n.key~=validbit.key -- explicitly used valid bit
      elseif n.kind=="delay" then
        return false
      elseif n.kind=="fndefn" then
          assert(false) -- we shouldn't call isPure on lowered ASTs
      else
        return J.foldl( J.andop, true, inputs )
      end
    end)
end

-- attempts to get the value of the constant
function systolicASTFunctions:const()
  if self.kind=="constant" then
    return self.value
  elseif self.kind=="null" then
    return nil -- not sure what do do here?
  end
  return nil
end

function systolicASTFunctions:setName(s)
  assert(type(s)=="string")
  self.name = self.name.."_"..s
  return self
end

-- When we disable pipelining, we mutate the nodes. The reason is that I don't think you'd ever want 
-- to compute something both pipelined, and not pipelined (you clock period would still be limited by the non-pipelined stuff, 
-- so pipelining it would provide no benefit).
--
-- Theoretically, functions can only be driven by parameters, calls on instances, and constants. So, disabling pipelining shouldn't be able to
-- escape the scope of one module (??!)
function systolicASTFunctions:disablePipelining()
  self:visitEach(function(n) n.pipelined=false end)
  return self
end

-- this disables pipelining on a single node.
-- Note that this doesn't guarantee that this is at pipe depth 0! (no pipelining).
-- this just requests that we don't add any pipeline registers (if we were going to)
function systolicASTFunctions:disablePipeliningSingle()
  if self.pipelined~=nil and self.pipelined==false then return self end

  local r = self:shallowcopy()
  r.pipelined=false
  return systolicAST.new(r)
end

-- replace the explicit delay nodes with registers
function systolicASTFunctions:removeDelays( )
  local pipelineRegisters = {}

  local delayCache = {}
  local nilCE = {}
  local function getDelayed( node, delay, validbit, cebit )
    -- if node is a constant, we don't need to put it in a register.
    if node.kind=="null" or node.type:verilogBits()<=0 or node.kind=="constant" or node==cebit then return node end
    
    delayCache[node] = delayCache[node] or {}
    delayCache[node][validbit] = delayCache[node][validbit] or {}
    local celookup = J.sel(cebit==nil,nilCE,cebit)
    delayCache[node][validbit][celookup] = delayCache[node][validbit][celookup] or {}
    if delay==0 then return node
    elseif delayCache[node][validbit][celookup][delay]==nil then
      -- explicit delay registers have both a valid bit, and a CE (if their parent has a CE)
      -- they have a valid bit b/c their semantics say they shift whenever the function is called
      local CENAME=""
      if cebit~=nil then CENAME="_CE"..cebit.name end
      local hasvalid = true
      if validbit==nil or validbit.kind=="null" then hasvalid=false end
      local reg = systolic.module.reg( node.type, cebit~=nil, nil, hasvalid ):instantiate(node.name.."_delay"..delay.."_valid"..validbit.name..CENAME)
      table.insert( pipelineRegisters, reg )
      local d = getDelayed(node, delay-1, validbit, cebit)
      delayCache[node][validbit][celookup][delay] = reg:delay( d, validbit, cebit )
    end
    return delayCache[node][validbit][celookup][delay]
  end

  local finalOut = self:process(
    function ( n )
      if n.kind=="delay" then
        -- notice that we DO NOT add the explicit delay to the retiming number.
        -- if we did that, the other nodes would compensate and the delay
        -- we want would disappear!
        return getDelayed( n.inputs[1], n.delay, n.inputs[2], n.inputs[3] )
      end
    end)

  return finalOut, pipelineRegisters
end

-- scale all internal pipeline delay values up/down
systolic.delayScale = 1

-- NOTE: we allow non-integer pipeline delays. The behavior here is we FLOOR the delays to get the # of cycles of each op.
-- We have to do this consistantly everywhere!!
local delayTable = {}
delayTable.abs={[8]=2-0.97, [16]=2-0.57, [24]=2-0.18, [32]=2-0.05}
delayTable["*"]={[8]=2-0.22, [16]=2-0.01, [24]=2-0.03, [32]=2}
delayTable["+"]={[8]=2-0.84, [16]=2-0.35, [24]=2-0.44, [32]=2-0.27}
delayTable["-"]={[8]=2-0.51, [16]=2-0.66, [24]=2-0.37, [32]=2-0.03}
delayTable[">="]={[0]=0} --???
delayTable["<="]={[0]=0} --???
delayTable["<"]={[0]=0} --???
delayTable[">"]={[0]=0} --???
delayTable["=="]={[0]=0} --???
delayTable[">>"]={[0]=0}
delayTable["<<"]={[0]=0}
delayTable["and"]={[0]=0}
delayTable["not"]={[0]=0}
delayTable["or"]={[0]=0}
delayTable["select"]={[0]=0}

local function interp(tab,bits)
  local lowerk,lowerv,higherk,higherv
  for k,v in pairs(tab) do
    if k<=bits and (lowerk==nil or k>lowerk) then
      lowerk = k
      lowerv = v
    end
    
    if k>bits and (higherk==nil or k<higherk) then
      higherk = k
      higherv = v
    end
  end

  if lowerk~=nil and higherk~=nil then
    local pct = (bits-lowerk)/(higherk-lowerk)
    local res = lowerv+pct*(higherv-lowerv)
    --print("INTERPOLATE",lowerk,lowerv,higherk,higherv,bits,"RES",res)
    return res
  elseif higherk~=nil then
    return higherv
  else
    return lowerv
  end
end

-- this returns (I=total internal delay of node), (D=delays pipelining has to add)
-- I-D is the amount that the op has built in (eg delay of a call)
function systolicASTFunctions:internalDelay()
  if self.kind=="call" then 
    local res = self.inst.module:getDelay( self.fnname ) 
    err( res==0 or self.pipelined, "Error, could not disable pipelining, "..self.loc)
    return res, 0
  elseif self.kind=="binop" or self.kind=="select" or self.kind=="unary" then 
    if self.pipelined==nil or self.pipelined then
      local op = self.op
      if self.kind=="select" then assert(op==nil); op="select" end
      local tab = delayTable[op]
      err(tab~=nil,"Pipelining error: no data for op '"..op.."'")
      local id = interp(tab,self.type:verilogBits())
      id = id*systolic.delayScale
      return id,id
    else
      return 0,0 -- if pipelining is disabled on an op
    end
  elseif self.kind=="tuple" or self.kind=="fndefn" or self.kind=="parameter" or self.kind=="slice" or self.kind=="cast" or self.kind=="module" or self.kind=="constant" or self.kind=="null" or self.kind=="bitSlice" or self.kind=="readSideChannel" or self.kind=="writeSideChannel" then
    return 0,0 -- purely wiring, or inputs
  elseif self.kind=="delay" then
    return 0,0
  else
    print("KIND",self.kind)
    assert(false)
  end
end

-- this function calculates the pipe delay of each op in the AST.
-- You can add constraints (disable pipelinging, coherence groups), and it will solve for them.
function systolicASTFunctions:calculateDelays(coherentDelays)
  local delaysAtInput = {}
  local coherentConverged = true
  local firstFailure

  local finalOut = self:visitEach(
    function( n )
      local maxd = 0
      J.map( n.inputs, function(a) maxd=math.max(maxd,delaysAtInput[a]+a:internalDelay()) end)
          
      -- for coherent modules, we need all calls to have the same delay at their input.
      -- record what delay the coherent modules are at, and whether we had to change it this round.
      if n.kind=="call" and n.inst.coherent then 
        if coherentDelays[n.inst]==nil or coherentDelays[n.inst] < maxd then
          coherentConverged = false
          coherentDelays[n.inst]=maxd
          if firstFailure==nil then firstFailure = n end
        else
          -- the coherent module is at a later delay than us - we just add extra delays to match
          maxd = coherentDelays[n.inst]
        end
      end

      delaysAtInput[n] = maxd      

--    pipelined==false is a soft request
--      if n.pipelined~=nil and n.pipelined==false then 
--        local loc = ""
--        if n.loc~=nil then loc=n.loc end
--        err( delaysAtInput[n]+n:internalDelay()==0, "failed to disable pipelining for "..n.kind..loc) 
--      end
    end)

  return delaysAtInput, coherentDelays, coherentConverged, firstFailure
end

function systolicASTFunctions:addPipelineRegisters( delaysAtInput, stallDomains )
  local pipelineRegisters = {}
  local fnDelays = {}

  local function getDelayed( node, delay, orig )
    assert( systolic.isAST(orig) )
    assert( math.floor(delay)==delay )
    local CE
    if stallDomains[orig]~="___NOSTALL" and stallDomains[orig]~="___CONST" then CE = stallDomains[orig] end
    return systolicAST.new{kind="delay",delay=delay,inputs={node,systolic.null(),CE},type=node.type,loc=getloc()}
  end

  local finalOut = self:process(
    function( n, orig )
      local thisDelay = delaysAtInput[orig]
      assert(type(thisDelay)=="number")
      n.pipelined = nil -- clear pipelined bit: we no longer need it, and it interferes with CSE

      if n.kind=="fndefn" then 
        -- remember, we want the delay of the fn to be based on the delay of the output, not the pipelines
        if n.fn.output==nil then
          fnDelays[n.fn.name] = 0
        else
          fnDelays[n.fn.name] = delaysAtInput[orig.inputs[1]]+orig.inputs[1]:internalDelay()
        end
      end

      if n.kind=="module" then
        -- obviously, we do not want to pipeline this.
      else
        local inputList = n.inputs

        -- the reason we don't pipeline fndefns is that we want the output delay to _only_ depend on the output. If some pipelines are longer than the output, that's ok (don't count that)
        if n.kind=="fndefn" then inputList={n.inputs[1]} end

        for k,_ in pairs(inputList) do
          -- insert delays so that each input is delayed the same amount
          -- Note: we have to do this on the original node, before we removed the pipeling information!
          local ID, delaysToAdd = orig.inputs[k]:internalDelay()
          local inpDelay = delaysAtInput[orig.inputs[k]] + (ID-delaysToAdd)

          n.inputs[k] = getDelayed( n.inputs[k], math.floor(thisDelay) - math.floor(inpDelay), orig.inputs[k])
        end
      end

      return systolicAST.new(n)
    end)

  return finalOut, pipelineRegisters, fnDelays
end

function systolicASTFunctions:pipeline(stallDomains)
  local iter=1
  local delaysAtInput = {}
  local coherentDelays = {}
  local converged = false
  local firstFailure
  while converged==false do
    if iter==100 then print(firstFailure.fnname,firstFailure.loc);error("Pipelining solve failed to converge! Probably, you created an unsatisfiable loop (a coherent module that reads and writes in the same cycle along a pipelined path)") end
    delaysAtInput, coherentDelays, converged, firstFailure = self:calculateDelays(coherentDelays)
    iter = iter + 1
  end

  return self:addPipelineRegisters( delaysAtInput, stallDomains )
end

function systolicASTFunctions:calculateStallDomains()
  local stallDomains = {}
  self:visitEachReverse(
    function( n, args )
      if n.kind=="fndefn" then
        if n.fn.CE==nil then return "___NOSTALL" end
        return n.fn.CE
      elseif n:parentCount(self)==0 then
        return "___UNKNOWN"
      else
        local seen
        local seenloc
        for k,v in pairs(args) do
          if seen==nil or seen=="___NOSTALL" or seen=="___CONST" then
            seen = v
            seenloc = k.loc
          elseif v~="___NOSTALL" and v~="___CONST" then
            -- notice: it's OK if something constant ends up under multiple stall domains, just surpress the error.
            -- if somehow something constant has a unconstant input (can happen with slice), and that ends up having 
            -- multiple stall domains, then that's an error. So we keep going to make sure that doesn't happen.
            if seen~=v then 
              print("multiple stall LOC",n.loc) 
              if type(seen)=="string" then
                print("Domain 1:"..seen)
              else
                print("Domain 1:"..seen.name)
              end
              print("Domain 1 Site:"..seenloc)
              if type(v)=="string" then
                print("Domain 2:"..v)
              else
                print("Domain 2:"..v.name)
              end
              print("Domain 2 Site:"..k.loc)

              print("Op is under multiple stall domains! "..tostring(seen).." "..tostring(v).."KIND:"..n.kind.."TYPE:"..tostring(n.type) )
              assert(false)
            end
          end
        end
        assert(seen~=nil)
        stallDomains[n] = seen
        return seen
      end
    end)
  return stallDomains
end

local function addArbitration( callsite )
  assert(systolicAST.isSystolicAST(callsite))
    --fn, fnname, instance, input, valid)
--  assert( systolic.isFunction(fn) )
  local fn, fnname, instance, input, valid, CE = callsite.func, callsite.fnname, callsite.inst, callsite.inputs[1], callsite.inputs[2], callsite.inputs[3]
  assert( systolic.isInstance(instance) )

  local otype = types.null()
  if fn.output~=nil then otype = fn.output.type end
  
  if fn.inputParameter.type==types.null() then
    -- if this fn takes no inputs, it doesn't matter what arbitration strategy we use
    return callsite
  else
    -- no arbitration
    if #instance.callsites[fnname]==0 then
      table.insert(instance.callsites[fnname],callsite)
      return callsite
    else
      error("Function '"..fn.name.."' on instance '"..instance.name.."' can't have multiple callsites!"..callsite.loc)
    end
  end
end

function systolicASTFunctions:mergeCallsites()
  return self:process(
    function(n)
      if n.kind=="call" then
        return addArbitration( systolicAST.new(n) )
      end
    end)
end

function systolicASTFunctions:addValid( validbit, module )
  assert( systolicAST.isSystolicAST(validbit) )
  err( systolic.isModule(module), ":addValid missing module") -- for debugging use only
       
  return self:process(
    function(n)
      if n.kind=="call" and n.func:isPure()==false then
        -- don't add valid bit to pure functions
        if n.inputs[2]==nil then
          n.inputs[2] = validbit
        else
          --n.inputs[2]:visitEach(function(nn) if nn.kind=="parameter" and nn.key==validbit.key then error("Explicit valid bit includes parent scope valid bit (function call to "..n.func.name..")! This is not necessary, it's added automatically. "..n.loc.." \n\n valid bit at loc: "..nn.loc) end end)
          local function checkValidBit(nn)
            if nn.kind=="call" then
              -- don't recurse into other calls, they may include the valid bit, but that's OK!
            elseif nn.kind=="parameter" and nn.key==validbit.key then 
              error("Explicit valid bit includes parent scope valid bit (function call to '"..n.func.name.."' on instance '"..n.inst.name.."' of module '"..n.inst.module.name.."' inside module '"..module.name.."')! This is not necessary, it's added automatically. "..n.loc.." \n\n valid bit at loc: "..nn.loc.." \n\n call at loc:"..n.loc)
            else
              J.map(nn.inputs, function(i) checkValidBit(i) end)
            end
          end
          checkValidBit(n.inputs[2])
          n.inputs[2] = systolic.__and(n.inputs[2], validbit)
          n.inputs[2].pipelined=false
        end
        return systolicAST.new(n)
      elseif n.kind=="delay" then
        n.inputs[2] = validbit
        return systolicAST.new(n)
      end
    end)
end

function systolicASTFunctions:addCE( ce )
  assert( systolicAST.isSystolicAST(ce) )
  return self:process(
    function(n)
      if n.kind=="call" and n.func.CE~=nil then
        -- some functions don't need a CE
        if n.inputs[3]==nil then
          n.inputs[3] = ce

          -- some pure functions need a CE (for pipeline registers).
          if n.inputs[2]==nil then n.inputs[2]=systolic.null() end
          assert(n.inputs[2]~=nil)
        else
          assert(false)
        end
        return systolicAST.new(n)
      elseif n.kind=="delay" then
        -- we automatically wire delay nodes to the CE to save the user from having to do this
        n.inputs[3] = ce
        return systolicAST.new(n)
      end
    end)

end

-- this converts ASTs so that different (but equivilant) delay arrangements
-- result in the same AST, so that they can be CSE'd
function systolicASTFunctions:internalizeDelays()
  local res = self:visitEach(
    function(n, args)

      if n.kind=="delay" then
        return {args[1][1],args[1][2]+n.delay}
      else
        local r = n:shallowcopy()
        local minDelay = 1000000
        if #n.inputs==0 then minDelay=0 end

        for k,v in pairs(n.inputs) do 
          r.inputs[k] = args[k][1]
          minDelay = math.min(minDelay, args[k][2])
        end

        for k,v in pairs(n.inputs) do 
          -- remember the delay delta. If it's zero, just don't store it (CSE correctly with non-delayed nodes)
          if args[k][2]>minDelay then
            assert(r["delay"..k]==nil) -- just in case
            r["delay"..k] = args[k][2]-minDelay
          end
        end
        return {systolicAST.new(r), minDelay}
      end
    end)

  return res[1], res[2]
end

function systolicASTFunctions:CSE(repo)
  local seenlist = repo or {}
  return self:process(
    function(n)
      n = systolicAST.new(n)
      seenlist[n.kind] = seenlist[n.kind] or {}
      for k,v in pairs(seenlist[n.kind]) do
        if n:eq(v) then 
          return v
        end
        
      end
      -- not found
      table.insert(seenlist[n.kind],n)
      return n
    end)
end

function systolicASTFunctions:toVerilog( module )
  assert( systolic.isModule(module))
  --local clockedLogic = {}
  local declarations = {}
  local wired = {} -- set of variable names that have been put in decls (wires) already
  
  local finalOut = self:visitEach(
    function(n, args)
      local finalResult
      local argwire = J.map(args, function(nn) assert(type(nn[2])=="boolean");return nn[2] end)
      args = J.map(args, function(nn) assert(type(nn[1])=="string"); return nn[1] end)

      -- if finalResult is already a wire, we don't need to assign it to a wire at the end
      -- if wire==false, then finalResult is an expression, and can't be used multiple times
      local wire = false

      -- constants don't need to be assigned to wires if we use them multiple times (can just duplicate the text to make the verilog code easier to read)
      local const = false

      if n.kind=="call" then
        local decl
        finalResult, decl, wire = n.inst.module:instanceToVerilog( n.inst, module, n.fnname, args[1], args[2], args[3] )
        table.insert( declarations, decl )
      elseif n.kind=="constant" then
        local function cconst( ty, val )
          if ty:isArray() then
            return "{"..table.concat( J.reverse( J.map(J.range(ty:channels()), function(c) return cconst(ty:arrayOver(), val[c])  end)),", " ).."}"
          else
            return systolic.valueToVerilog(val, ty)
          end
        end
        finalResult = "("..cconst(n.type,n.value)..")"
        const = true
      elseif n.kind=="fndefn" then
        --table.insert(declarations,"  // function: "..n.fn.name..", pure="..tostring(n.fn:isPure()))
        if n.fn.output~=nil and n.fn.output.type~=types.null() then table.insert(declarations,"assign "..n.fn.outputName.." = "..args[1]..";") end
        finalResult = "_ERR_NULL_FNDEFN"
      elseif n.kind=="module" then
        for _,v in pairs(n.module.functions) do
          if n.module.onlyWire then
            table.insert( declarations,"// function: "..v.name.." pure="..tostring(v:isPure()).." ONLY WIRE" )
          else
            table.insert( declarations,"// function: "..v.name.." pure="..tostring(v:isPure()).." delay="..n.module:getDelay(v.name) )
          end
        end
        finalResult = "__ERR_NULL_MODULE"
      elseif n.kind=="bitSlice" then
        -- verilog doesn't have expressions - we can only bitslice on a wire. So coerce input into a wire.
        local inp = systolic.wireIfNecessary( wired, declarations, n.inputs[1].type, n.inputs[1].name, args[1], " // wire for bitslice" )

        if n.high==0 and n.low==0 and n.inputs[1].type:verilogBits()==1 then
          finalResult = inp
        else
          finalResult = inp.."["..n.high..":"..n.low.."]"
        end
      elseif n.kind=="slice" then
        if n.inputs[1].type:isArray() then
          local inp = systolic.wireIfNecessary( wired, declarations, n.inputs[1].type, n.inputs[1].name, args[1], " // wire for array index" )
          local sz = n.inputs[1].type:arrayOver():verilogBits()
          local W = (n.inputs[1].type:arrayLength())[1]

          local res = {}
          for y=n.idyHigh,n.idyLow,-1 do
            local highbit = ((y*W+n.idxHigh+1)*sz-1)
            local lowbit = ((y*W+n.idxLow)*sz)
            if highbit==0 and lowbit==0 and n.inputs[1].type:verilogBits()==1 then
              table.insert( res, inp )
            elseif highbit==lowbit then
              table.insert( res, inp.."["..lowbit.."]" )
            else
              table.insert( res, inp.."["..highbit..":"..lowbit.."]" )
            end
          end

          finalResult = "({"..table.concat(res,",").."})"
        elseif n.inputs[1].type:isTuple() then
          local lowbit = 0
          local highbit = 0
          for k,v in pairs(n.inputs[1].type.list) do 
            if k-1<n.idxLow then lowbit = lowbit + v:verilogBits() end 
            if k-1<=n.idxHigh then highbit = highbit + v:verilogBits() end 
          end
          highbit = highbit-1
          --local ty = n.inputs[1].type.list[n.idxHigh+1]
          if (highbit-lowbit+1)==n.inputs[1].type:verilogBits() then
            -- no index necessary. either we sliced whole tuple, or other types were null.
            finalResult = args[1]
          elseif n.inputs[1].type:verilogBits()>=1 then
            local inp = systolic.wireIfNecessary( wired, declarations, n.inputs[1].type, n.inputs[1].name, args[1], " // wire for array index" )
            if highbit~=lowbit then
              finalResult = "("..inp.."["..highbit..":"..lowbit.."])"
            else
              finalResult = "("..inp.."["..lowbit.."])"
            end
          else
            -- type has no bits?
            finalResult = "___NIL_INDEX"
          end
        else
          print(n.expr.type)
          assert(false)
        end
      elseif n.kind=="tuple" then
        local nonulls = J.ifilter(args, function(v,k) return n.inputs[k].type:verilogBits()>0 end )
        finalResult="{"..table.concat(J.reverse(nonulls),",").."}"
      elseif n.kind=="cast" then
        
        local function docast( expr, fromType, toType, inputIsWire, inputName )
          assert(type(expr)=="string")
          assert(type(inputIsWire)=="boolean")
          assert(type(inputName)=="string")

          local allBits = true
          if fromType:isTuple() then
            for k,v in pairs(fromType.list) do if v:isBits()==false then allBits=false end end
          end
          
          if fromType:isTuple() and allBits then
            -- casting tuple of bit type {bits,bits,bits...} to anything: a noop
            return expr
          elseif toType:isBits() or fromType:isBits() then
            -- noop: verilog is blind to types anyway
            
            local diff = toType:verilogBits()-fromType:verilogBits()
            if diff>0 then
              -- pad it with some 0's
              return "{"..tostring(diff).."'b0,"..expr.."}"
            elseif diff==0 then
              return expr
            else
              assert(false)
            end
          elseif toType:isArray() and fromType:isTuple() then
            -- Theoretically, typechecker should only allow valid tuple array casts to be allowed? (always row-major order)
            err( toType:verilogBits()==fromType:verilogBits(), "tuple to array cast verilog size doesn't match?")
            return expr
          elseif toType:isArray() and fromType:isArray()==false and fromType:isTuple()==false then
            return "{"..table.concat( J.map( J.range(toType:channels()), function(n) return expr end),",").."}" -- broadcast
          elseif fromType:isArray() and toType:isArray()==false and fromType:arrayOver():isBool() and (toType:isUint() or toType:isInt()) then
            err("systolic cast from array of bools to type NYI")
          elseif toType:isArray() and fromType:isArray() and toType:baseType()==fromType:baseType() then
            assert(toType:channels() == fromType:channels())
            -- array reshaping is noop
            return expr
          elseif fromType:isTuple() and #fromType.list==1 and fromType.list[1]==toType then
            -- {A} to A.  Noop
            return expr
          elseif fromType:isArray() and fromType:arrayOver()==toType and fromType:channels()==1 then
            -- A[1] to A. Noop
            return expr
          elseif fromType==toType then
            return expr -- casting const to non-const. Verilog doesn't care.
          elseif fromType:isNamed() and toType:isNamed()==false and fromType.structure==toType then
            -- noop, explicit cast of named type to its structural type
            return expr
          elseif fromType:isNamed()==false and toType:isNamed() and fromType==toType.structure then
            -- noop, cast to named type with same structure
            return expr
          elseif fromType:isNamed() and toType:isNamed()==false then
            -- structure not identical, attempt base cast
            return docast( expr, fromType.structure, toType, inputIsWire, inputName )
          elseif fromType:isNamed()==false and toType:isNamed() then
            -- structure not identical, attempt base cast
            return docast( expr, fromType, toType.structure, inputIsWire, inputName )
          elseif fromType:isUint() and (toType:isInt() or toType:isUint()) and fromType.precision <= toType.precision then
            -- casting smaller uint to larger or equal int or uint. Don't need to sign extend
            local bitdiff = toType.precision-fromType.precision
	    
            if bitdiff>0 then
              return "{"..bitdiff.."'b0,"..expr.."}"
            elseif bitdiff==0 then
              return expr
            else
              assert(false)
            end
          elseif toType:isInt() and fromType:isInt() and toType.precision > fromType.precision then
            -- casting smaller int to larger int. must sign extend
            expr = systolic.wireIfNecessary( wired, declarations, fromType, inputName, expr, " // wire for int size extend (cast)" )
            return "{ {"..(toType:verilogBits() - fromType:verilogBits()).."{"..expr.."["..(fromType:verilogBits()-1).."]}},"..expr.."["..(fromType:verilogBits()-1)..":0]}"
          elseif (fromType:isUint() or fromType:isInt()) and (toType:isInt() or toType:isUint()) and fromType.precision>toType.precision then
            -- truncation. I don't know how this works
            local exp = systolic.wireIfNecessary( wired, declarations, fromType, inputName, expr, " // wire for truncation")
            return exp.."["..(toType.precision-1)..":0]"
          elseif fromType:isInt() and toType:isUint() and fromType.precision == toType.precision then
            -- int to uint with same precision. I don't know how this works
            return expr
          elseif fromType:isBits() or toType:isBits() then
            -- noop: verilog is blind to types anyway
            assert(fromType:verilogBits()==toType:verilogBits())
            return expr
	    	  elseif fromType:isTuple() and toType:isTuple() and #fromType.list==#toType.list then
            local allnoop = true
            
            local low = 0
            for k,v in ipairs(fromType.list) do
              local sub = expr.."["..tostring(low+v:verilogBits()-1)..":"..tostring(low).."]"
              local e = docast(sub,v,toType.list[k],false,"")
              if e~=sub then allnoop=false end
            end
            
            err( allnoop, "Error, NYI, systolic cast tuple to tuple that is not a noop, "..tostring(fromType).." to "..tostring(toType))
            return expr
          elseif fromType:isArray() and toType:isArray() and fromType:channels()==toType:channels() then
            -- HACK: just check if this is a noop
            
            local e = docast(expr,fromType:arrayOver(),toType:arrayOver(),false,"")
            
            err(e==expr,"NYI - systolic cast array type to array type that is not a noop. "..tostring(fromType).." to "..tostring(toType))
            return expr
          elseif fromType:isArray() and toType:isArray() then
            -- HACK: just check if this is a noop

            -- HACK: if just one of the types is an array of one element, unwrap it and try again
            if fromType:channels() == 1 then
              local e = docast(expr,fromType:arrayOver(),toType,false,"")
              err(e==expr,"NYI - systolic cast array type to array type that is not a noop. "..tostring(fromType).." to "..tostring(toType))
            elseif toType:channels() == 1 then
              local e = docast(expr,fromType,toType:arrayOver(),false,"")
              err(e==expr,"NYI - systolic cast array type to array type that is not a noop. "..tostring(fromType).." to "..tostring(toType))
            else
              err(false,"NYI - systolic cast array type to array type that is not a noop. "..tostring(fromType).." to "..tostring(toType))
            end

            return expr
          else
            err(false,"FAIL TO CAST"..tostring(fromType).." to "..tostring(toType) )
          end
        end
        
        finalResult = docast( args[1], n.inputs[1].type, n.type, argwire[1], n.inputs[1].name )
      elseif n.kind=="parameter" then
        finalResult = n.name
        wire = true
      elseif n.kind=="instanceParameter" then
        table.insert(declarations, declareWire(n.type, n.name, n.variable))
        finalResult = n.name
        wire=true
      elseif n.kind=="null" then
        finalResult = "__SYSTOLIC_NULL"
        wire = true
      elseif n.kind=="select" then
        finalResult = "(("..args[1]..")?("..args[2].."):("..args[3].."))"
      elseif n.kind=="binop" then
        if n.op=="<" or n.op==">" or n.op=="<=" or n.op==">=" then
          local lhs = n.inputs[1]
          local rhs = n.inputs[2]
          if n.type:baseType():isBool() and lhs.type:baseType():isInt() and rhs.type:baseType():isInt() then
            local lhsv = systolic.wireIfNecessary( wired, declarations, n.inputs[1].type, n.inputs[1].name, args[1], "// wire for $signed")
            local rhsv = systolic.wireIfNecessary( wired, declarations, n.inputs[2].type, n.inputs[2].name, args[2], "// wire for $signed")
            finalResult = "($signed("..lhsv..")"..n.op.."$signed("..rhsv.."))"
          elseif n.type:baseType():isBool() and lhs.type:baseType():isUint() and rhs.type:baseType():isUint() then
            finalResult = "(("..args[1]..")"..n.op.."("..args[2].."))"
          else
            print( n.type:baseType():isBool() , n.lhs.type:baseType():isInt() , n.rhs.type:baseType():isInt(),n.type:baseType():isBool() , n.lhs.type:baseType():isUint() , n.rhs.type:baseType():isUint())
            assert(false)
          end
        elseif n.type:isBool() then
          local op = binopToVerilogBoolean[n.op]
          if type(op)~="string" then print("OP_BOOLEAN",n.op); assert(false) end
          finalResult = "("..args[1]..op..args[2]..")"
        else
          local op = binopToVerilog[n.op]
          if type(op)~="string" then print("OP",n.op); assert(false) end
          local lhs = args[1]
          if n.inputs[1].type:baseType():isInt() then 
            lhs = systolic.wireIfNecessary( wired, declarations, n.inputs[1].type, n.inputs[1].name, lhs, "// wire for $signed")
            lhs = "$signed("..lhs..")" 
          end
          local rhs = args[2]
          if n.inputs[2].type:baseType():isInt() then 
            rhs = systolic.wireIfNecessary( wired, declarations, n.inputs[2].type, n.inputs[2].name, rhs, "// wire for $signed")
            rhs = "$signed("..rhs..")" 
          end
          finalResult = "("..lhs..op..rhs..")"
        end
        
      elseif n.kind=="unary" then
        if n.op=="abs" then
          if n.type:isInt() then
            finalResult = systolic.wireIfNecessary( wired, declarations, n.inputs[1].type, n.inputs[1].name, args[1], "// wire for abs")
            finalResult = "(("..finalResult.."["..(n.type:verilogBits()-1).."])?(-"..finalResult.."):("..finalResult.."))"
          else
            err(false,"NYI - abs on type "..tostring(n.type))
          end
        elseif n.op=="-" then
          finalResult = "(-"..args[1]..")"
        elseif n.op=="not" then
          finalResult = "(~"..args[1]..")"
        elseif n.op=="isX" then
          finalResult = "("..args[1].."===1'bx)"
        else
          print(n.op)
          assert(false)
        end
      elseif n.kind=="vectorSelect" then
        finalResult = "(("..args[1]..")?("..args[2].."):("..args[3].."))"
      elseif n.kind=="readSideChannel" then
        -- this is ok: read may be totally internal, so won't be on external list
        J.err( module.sideChannels[n.sideChannel]~=nil or module.sideChannelsInternal[n.sideChannel.name]~=nil,"readSideChannel: side channel named '"..n.sideChannel.name.."' is not attached to module '"..module.name.."'?")
        finalResult = n.sideChannel.name
      elseif n.kind=="writeSideChannel" then
        table.insert( declarations, "assign "..n.sideChannel.name.." = "..args[1].."; // writeSideChannel\n" )
        finalResult = "____^&%WRITESIDECHANNELOUT"
      else
        print(n.kind)
        assert(false)
      end

      if wire then wired[n.name]=1 end
      
      -- if this value is used multiple places, store it in a variable
      if n:parentCount(self)>1 and wire==false and const==false then
        if n.type==types.null() then
          -- null outputs with multiple consumers are strange, but OK. Example: A coherent call with null output that is used in two different functions. (they will both share the same node, with null output)
        else
          local newName = n.name.."USEDMULTIPLE"..n.kind
          table.insert( declarations, declareWire( n.type, newName, finalResult ) )
          wired[newName] = 1
          return {newName,true}
        end
      else
        err(type(finalResult)=="string","finalResult is not string? "..n.kind)
        return {finalResult, wire}
      end
    end)

  declarations = J.map(declarations, function(i) return "  "..i end )
  local fin = table.concat(declarations,"\n").."\n"

  return fin
end

function systolic.instanceParameter( variable, ty )
  -- HACK: get a verilog instance varible
  assert(type(variable)=="string")
  assert( types.isType(ty) )
  return systolicAST.new({kind="instanceParameter",variable=variable,type=ty,inputs={},loc=getloc()})
end

function systolic.parameter( name, ty )
  err( type(name)=="string", "parameter name must be string" )
  checkReserved(name)
  err( types.isType(ty), "systolic.parameter: type must be type but is "..tostring(ty) )
  return systolicAST.new({kind="parameter",name=name,type=ty,inputs={},key={},loc=getloc()})
end

function systolic.CE( name )
  return systolic.parameter( name, types.bool(true) )
end

systolicSideChannelFunctions = {}
systolicSideChannelMT={__index=systolicSideChannelFunctions}

function systolic.newSideChannel( name, direction, ty, global, X )
  err( type(name)=="string", "systolic.sideParameter: name must be string" )
  checkReserved(name)
  err( direction=="input" or direction=="output","systolic.sideParameter: direction must be 'input' or 'output'" )
  err( types.isType(ty), "systolic.sideParameter: type must be type but is "..tostring(ty) )
  err( global~=nil,"systolic.newSideChannel: missing global")
  err( X==nil, "systolic.sideParameter: too many arguments")

  return setmetatable({name=name,direction=direction,type=ty,key={},inputs={},loc=getloc(),global=global},systolicSideChannelMT)
end

function systolic.isSideChannel(t) return getmetatable(t)==systolicSideChannelMT end

--------------------------------------------------------------------
-- Module Definitions
--------------------------------------------------------------------
function systolic.isModule(t)
  return getmetatable(t)==userModuleMT or getmetatable(t)==fileModuleMT or getmetatable(t)==regModuleMT
end

systolic.module = {}
local __usedModuleNames = {}

userModuleFunctions={}
setmetatable(userModuleFunctions,{__index=systolicModuleFunctions})
userModuleMT={__index=userModuleFunctions}

function userModuleMT.__tostring(tab)
  local res = {}
  table.insert(res,"SystolicModule "..tab.name)

  table.insert(res,"Side Channels:")
  for k,_ in pairs(tab.sideChannels) do
    table.insert(res,k.name)
  end
  
  for fnname,fn in pairs(tab.functions) do
    table.insert(res,"Function "..fnname)
    table.insert(res,tostring(fn))
  end
  
  return table.concat(res,"\n")
end

function userModuleFunctions:instanceToVerilogStart( instance, module )
  instance.verilogCompilerState = instance.verilogCompilerState or {}
  assert(instance.verilogCompilerState[module]==nil)
  instance.verilogCompilerState[module] = {}
  instance.CEState = instance.CEState or  {}
  instance.CEState[module] = {}
end

function userModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar, cevar )
  local fn = self.functions[fnname]
  if fn:isPure()==false and fn.inputParameter.type==types.null() then
    -- it's ok to have multiple calls to a pure function w/ no inputs
    err( instance.verilogCompilerState[module][fnname]==nil, "multiple calls to a function! function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."' "..instance.loc)

  end

  if fn.CE==nil and cevar~=nil then err(false, "module was given a CE, but does not expect a CE. Function '"..fnname.."' on instance '"..instance.name.."' of module '"..instance.module.name.."' inside module '"..module.name.."' "..instance.loc) end

  if fn.CE~=nil then
    err(type(cevar)=="string", "Module expected a CE, but was not given one. Function '"..fnname.."' on instance '"..instance.name.."' (of module "..instance.module.name..") inside module '"..module.name.."' "..instance.loc)

    if instance.CEState[module][fn.CE.name]==nil then
      instance.CEState[module][fn.CE.name]=cevar
    else
      err( instance.CEState[module][fn.CE.name] == cevar, "Mismatched CE. Function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."' "..instance.loc.." ----- "..cevar.." vs "..instance.CEState[module][fn.CE.name])
    end
  end

  instance.verilogCompilerState[module][fnname]={datavar,validvar,cevar}
  local decl = nil

  if fn.output~=nil and fn.output.type~=types.null() then
    decl = declareWire( fn.output.type, instance.name.."_"..fn.outputName)
  end

  local outname = instance.name.."_NILOUTPUT"
  if fn.output~=nil and fn.output.type~=types.null() then outname = instance.name.."_"..fn.outputName end
  return outname, decl, true
end

function userModuleFunctions:instanceToVerilogFinalize( instance, module )
  local wires = {}
  local arglist = {}
    
  local CESeen = {}
  for fnname,fn in pairs(self.functions) do
    local canBeUndriven = fn:isPure()
    local modtype = instance.module.name
    if modtype==nil then modtype="" end
    err( instance.verilogCompilerState[module][fnname]~=nil or canBeUndriven, "Undriven function "..fnname.." on instance "..instance.name.." (of type "..modtype..") in module "..module.name)
    
    -- if onlyWire==true, don't try to be clever - always wire the valid bit if it exists.
    if fn:isPure()==false or self.onlyWire then
      if self.onlyWire and fn.implicitValid then
        -- when in onlyWire mode, it's ok to have an undriven valid bit
      else
        local inp = instance.verilogCompilerState[module][fnname][2]
        err( type(inp)=="string", "undriven valid bit, function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."'")
        table.insert( arglist, ", ."..fn.valid.name.."("..inp..")") 
      end      
    end

    if fn.CE~=nil and CESeen[fn.CE.name]==nil then
      local inp = instance.CEState[module][fn.CE.name]
      err( type(inp)=="string", "undriven CE '"..fn.CE.name.."', function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."'")
      table.insert( arglist, ", ."..fn.CE.name.."("..inp..")") 
      CESeen[fn.CE.name] = 1
    end
    
    if fn.inputParameter.type~=types.null() and fn.inputParameter.type:verilogBits()>0  then
      err( instance.verilogCompilerState[module][fnname]~=nil, "No calls to fn '"..fnname.."' on instance '"..instance.name.."' (of module '"..instance.module.name.."') in module '"..module.name.."'? input type "..tostring(fn.inputParameter.type))
      local inp = instance.verilogCompilerState[module][fnname][1]
      err( type(inp)=="string", "undriven input, function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."'")
      table.insert(arglist,", ."..fn.inputParameter.name.."("..inp..")")
    end

    if fn.output~=nil and fn.output.type~=types.null() and fn.output.type:verilogBits()>0 then
      table.insert(arglist,", ."..fn.outputName.."("..instance.name.."_"..fn.outputName..")")

      -- if this fn is never actually used, this output will be dangling, so make a dummy wire to make verilator happy
      local fnUsed = instance.verilogCompilerState[module][fnname]
      if fnUsed==nil then
         table.insert(wires, systolic.declareWire(fn.output.type, instance.name.."_"..fn.outputName, nil, " //unused port tieoff\n" ) )
      end
    end

  end

  for scSink,_ in pairs(self.sideChannels) do
--    if instance.module.sideChannels~=nil then
--      local scSource = instance.module.sideChannels[scSink]
    table.insert(arglist,", ."..scSink.name.."("..scSink.name..")")
--    else
--      table.insert(arglist,", ."..scSink.name.."()")
--    end
  end
  
  local params = ""
  if type(instance.parameters)=="table" then
    for k,v in pairs(instance.parameters) do
      params = params..",."..k.."("..tostring(v)..")"
    end
  end

  return table.concat(wires)..self.name..[[ #(.INSTANCE_NAME({INSTANCE_NAME,"_]]..instance.name..[["})]]..params..[[) ]]..instance.name.."(.CLK(CLK)"..table.concat(arglist)..");"
end

function userModuleFunctions:lower()
  local mod = {kind="module", type=types.null(), inputs={}, module=self,loc="userModuleFunctions:lower()"}

  for _,fn in pairs(self.functions) do
    local O = fn.output
    if O~=nil and self.onlyWire~=true then O = O:addValid(fn.valid,self) end
    if O~=nil and self.onlyWire~=true and fn.CE~=nil then O = O:addCE(fn.CE) end
    local node = { kind="fndefn", fn=fn, type=types.null(), valid=fn.valid, inputs={O},loc="userModuleFUnctions:lower()" }
    for k,pipe in pairs(fn.pipelines) do
      local P = pipe
      if self.onlyWire~=true then P = P:addValid(fn.valid,self) end
      if self.onlyWire~=true and fn.CE~=nil then P = P:addCE(fn.CE) end
      table.insert( node.inputs, P )
    end

    node = systolicAST.new(node)
    table.insert( mod.inputs, node )
  end
  mod = systolicAST.new(mod)
  return mod
end

function userModuleFunctions:toVerilog()
  if self.verilog==nil then
    local t = {}

    local CEseen = {}
    table.insert(t,"module "..self.name.."(")

    local portlist = {{"CLK",types.bool(),true}}

    for fnname,fn in pairs(self.functions) do
      -- our purity analysis isn't smart enough to know whether a valid bit is needed when onlyWire==true.
      -- EG, if we use the valid bit to control clock enables or something. So just do what the user said (include the valid unless it was implicit)
      if fn:isPure()==false or self.onlyWire then 
        if self.onlyWire and fn.implicitValid then
        else table.insert(portlist,{fn.valid.name,types.bool(),true}) end
      end

      if fn.CE~=nil and CEseen[fn.CE.name]==nil then CEseen[fn.CE.name]=1; table.insert(portlist,{fn.CE.name,types.bool(),true}) end

      if fn.inputParameter.type~=types.null() and fn.inputParameter.type:verilogBits()>0 then 
        table.insert(portlist,{ fn.inputParameter.name, fn.inputParameter.type, true})
      end

      if fn.output~=nil and fn.output.type~=types.null() and fn.output.type:verilogBits()>0 then table.insert(portlist,{ fn.outputName, fn.output.type, false })  end
    end

    -- is there an input/output (internally wired) pair for this SC?
    local SCPairDefn = ""
    for name,sc in pairs(self.sideChannelsInternal) do
      SCPairDefn = SCPairDefn.."  "..declareWire(sc.type,sc.name,nil," // Side Channel internal pair" ).."\n"
    end
    
    for sc,_ in pairs(self.sideChannels) do
      table.insert(portlist,{sc.name,sc.type,sc.direction=="input"})
    end
    
    table.insert(t,table.concat(J.map(portlist,function(n) return systolic.declarePort(n[2],n[1],n[3]) end),", "))
    table.insert(t,");\n")

    table.insert(t,[[parameter INSTANCE_NAME="INST";]].."\n")
    if type(self.parameters)=="table" then
      for k,v in pairs(self.parameters) do
        table.insert(t,"parameter "..k.."="..v..";\n")
      end
    end

    table.insert(t,SCPairDefn)
    
    for k,v in pairs(self.instances) do
      if v.module.instanceToVerilogStart~=nil then
        v.module:instanceToVerilogStart( v, self )
      end
    end

    table.insert( t, self.ast:toVerilog(self) )

    for k,v in pairs(self.instances) do
      if v.module.instanceToVerilogFinalize~=nil then
        table.insert(t, "  "..v.module:instanceToVerilogFinalize( v, self ).."\n" )
      end
    end

    table.insert(t,"endmodule\n\n")

    self.verilog = table.concat(t,"")
  end

  return self.verilog
end

function userModuleFunctions:getDependenciesLL()
  local dep = {}
  local depMap = {}

  for _,i in pairs(self.instances) do
    local deplist = i.module:getDependenciesLL()
    for _,D in pairs(deplist) do
      if depMap[D[1]]==nil then table.insert(dep, D) end
      depMap[D[1]]=1
    end
    if depMap[i.module]==nil then
      table.insert(dep,{i.module,i.module:toVerilog()})
      depMap[i.module]=1
    end
  end
  return dep
end

function userModuleFunctions:getDependencies()
  return table.concat(J.map(self:getDependenciesLL(), function(n) return n[2] end),"")
end

function userModuleFunctions:getDelay( fnname )
  err( self.functions[fnname]~=nil, ":getDelay() error, '"..fnname.."' is not a valid function on module "..self.name)
  if self.onlyWire then 
    err( type(self.verilogDelay)=="table" and type(self.verilogDelay[fnname])=="number", "Error, onlyWire module '"..self.name.."' function '"..fnname.."' is missing delay information")
    return self.verilogDelay[fnname] 
  end
  assert(type(self.fndelays[fnname])=="number")
  return math.floor(self.fndelays[fnname])
end

-- 'verilog' input is a string of verilog code. When this is provided, this module just becomes a wrapper. verilogDelay must be provided as well.
function systolic.module.new( name, fns, instances, onlyWire, parameters, verilog, verilogDelay, sideChannels, X )
  err( type(name)=="string", "systolic.module.new: name must be string" )
  --name = sanitize(name)
  err( name == sanitize(name), "systolic.module.new: name must be verilog sanitized ("..name..") to ("..sanitize(name)..")" )
  checkReserved(name)
  err( type(fns)=="table", "functions must be a table")
  J.map(fns, function(n) err( systolic.isFunction(n), "functions must be systolic functions" ) end )
  err( type(instances)=="table", "instances must be a table")
  J.map(instances, function(n) err( systolic.isInstance(n), "instances must be systolic instances" ) end )
  J.map(instances, function(n) err(n.final==false, "Instance was already added to another module?"); n.final=true end )

  err( onlyWire==nil or type(onlyWire)=="boolean", "onlyWire must be nil or bool")
  err( parameters==nil or type(parameters)=="table", "parameters must be nil or table")
  err( verilog==nil or type(verilog)=="string", "verilog must be nil or string, module "..name)
  err( verilogDelay==nil or type(verilogDelay)=="table", "verilogDelay must be nil or table, module "..name)

  err( X==nil, "systolic.module.new: too many arguments" )

  -- not actually true: verilogDelay can be missing if this module is never used by a module with onlyWire==false
  --if onlyWire then err(type(verilogDelay)=="table", "if onlyWire is true, verilogDelay must be passed") end

  local SC = {}
  local SCInternal = {} -- sc internal pairs (name->SC map)
  local SCPairs = {}
  
  if sideChannels~=nil then
    for k,_ in pairs(sideChannels) do
      err(systolic.isSideChannel(k),"systolic.module.new: element in side channel set is not a side channel")
      SC[k]=1
      SCPairs[k.name] = k
    end
  end

  -- add missing side channels from instances
  for _,inst in pairs(instances) do
    if inst.module.sideChannels~=nil then
      for sc,_ in pairs(inst.module.sideChannels) do
        if SCInternal[sc.name]~=nil then
        elseif SCPairs[sc.name]~=nil and SCPairs[sc.name].direction~=sc.direction then
          SC[SCPairs[sc.name]] = nil
          SC[sc]=nil
          SCInternal[sc.name]=sc
        else
          SC[sc] = 1
          SCPairs[sc.name]=sc
        end
      end
    end
  end

  -- add missing side channels from reads/writes
  for k,v in pairs(fns) do
    local function checkForSC(expr)
      expr:visitEach(
        function(n,args)
          if n.kind=="readSideChannel" or n.kind=="writeSideChannel" then
            if SCInternal[n.sideChannel.name]~=nil then
            elseif SCPairs[n.sideChannel.name]~=nil and
              ((n.kind=="readSideChannel" and SCPairs[n.sideChannel.name].direction=="output") or
               (n.kind=="writeSideChannel" and SCPairs[n.sideChannel.name].direction=="input")) then
                SC[SCPairs[n.sideChannel.name]] = nil
                SC[n.sideChannel] = nil
                SCInternal[n.sideChannel.name]=n.sideChannel
            else
              SC[n.sideChannel] = 1
              SCPairs[n.sideChannel.name]=n.sideChannel
              assert(SCInternal[n.sideChannel.name]==nil)
            end
          end
        end)
    end
    
    if v.output~=nil then
      checkForSC(v.output)
    end

    if v.pipelines~=nil then
      for kk,vv in ipairs(v.pipelines) do
        checkForSC(vv)
      end
    end
  end

  -- sanity check: make sure internal and external are exclusive
  for k,v in pairs(SCInternal) do
    err(SC[v]==nil,"Internal SC "..v.name.." is also in external list?")
  end
  
  if __usedModuleNames[name]~=nil then
    print("Module name ",name, "already used")
    assert(false)
  end
  __usedModuleNames[name]=1

  -- We let users choose whatever parameter names they want. Check for duplicate variable names in functions.
  local _usedPname = {}
  for k,v in pairs(fns) do
    if v.output~=nil and v.output.type~=types.null() then err( _usedPname[v.outputName]==nil, "output name "..v.outputName.." used somewhere else in module" ) end
    if v.output~=nil and v.output.type~=types.null() then _usedPname[v.outputName]="output" end
    err( _usedPname[v.inputParameter.name]==nil, "input name "..v.inputParameter.name.." used somewhere else in module" )
    _usedPname[v.inputParameter.name]="input"
    if _usedPname[v.valid.name]~=nil then
      err( _usedPname[v.valid.name]==nil, "valid bit name '"..v.valid.name.."' for function '"..k.."' used somewhere else in module. Used as ".._usedPname[v.valid.name] )
    end
    _usedPname[v.valid.name]="valid for fn '"..k.."'"
  end

  local SCNames = {}
  for k,_ in pairs(SC) do
    if SCNames[k.name]~=nil and SCNames[k.name]~=k.direction then
      -- OK: found a matching SC with opposite direction
    elseif SCNames[k.name]~=nil and SCNames[k.name]=="input" and k.direction=="input" then
      -- OK: a side channel can be an input into two modules
    else
      err( _usedPname[k.name]==nil,k.direction.." side channel name '"..k.name.."' is used somewhere else in module (as a "..tostring(_usedPname[k.name])..")")
      _usedPname[k.name]=k.direction.." side channel"
      SCNames[k.name]=k.direction
    end
  end
  
  -- check for dangling params
  if onlyWire==false then
    for k,v in pairs(fns) do
      if v.output~=nil then
        v.output:visitEach(
          function(n,args) 
            if n.kind=="parameter" then 
              err( n.key==v.inputParameter.key or (v.valid~=nil and n.key==v.valid.key) or (v.CE~=nil and n.key==v.CE.key),"Systolic function '"..name.."' has dangling input parameter '"..n.name.."' (should be '"..v.inputParameter.name.."', or the CE or valid bit), "..n.loc) 
            end end)
      end
    end
  end

  -- different functions can have the same stall domains. We consider them identical if they have the same name
  for k,v in pairs(fns) do
    if v.CE~=nil then 
      if _usedPname[v.CE.name]~=nil then err( false, "CE name '"..v.CE.name.."' for function '"..k.."' used somewhere else in module. Used as ".._usedPname[v.CE.name] ) end
    end
  end

  local t = {name=name,kind="user",instances=instances,functions=fns, instanceMap={}, usedInstanceNames = {}, isComplete=false, onlyWire=onlyWire, verilogDelay=verilogDelay, parameters=parameters, verilog=verilog, sideChannels=SC, sideChannelsInternal=SCInternal}
  setmetatable(t,userModuleMT)

  t.ast = t:lower()

  -- the idea here is that we first do the pipelineing, before _any_ CSE.
  -- the reason is that pipeline registers need a clock enable. For callsites under multiple
  -- domains, we want to create multiple sets of pipelining registers for them (with different CE's)
  -- Running pipelining before CSE allows that to happen. Then, we run CSE after. If pipeline registers ended up with same CE, they should be deduped.
  if onlyWire==nil or onlyWire==false then
    local pipelineRegisters
    local stallDomains = t.ast:calculateStallDomains()
    t.ast, pipelineRegisters, t.fndelays = t.ast:pipeline(stallDomains)
  end

  t.ast = t.ast:CSE() -- call CSE before mergeCallsites to merge identical callsites
  t.ast = t.ast:mergeCallsites()

  local delayRegisters
  t.ast, delayRegisters = t.ast:removeDelays()
  t.instances = J.concat(t.instances, delayRegisters)

  t.ast = t.ast:CSE()

  J.map( t.instances, function(i) t.instanceMap[i]=1; err(t.usedInstanceNames[i.name]==nil,"Instance name '"..i.name.."' used multiple times!"); t.usedInstanceNames[i.name]=1 end )

  -- check that the instances refered to by this module are actually in the module
  t.ast:checkInstances( t.instanceMap )

  return t
end

----------------------------
regModuleFunctions={}
setmetatable(regModuleFunctions,{__index=systolicModuleFunctions})
regModuleMT={__index=regModuleFunctions}

function regModuleFunctions:instanceToVerilogStart( instance, module )
  instance.verilogCompilerState = instance.verilogCompilerState or {}
  assert(instance.verilogCompilerState[module]==nil)
  instance.verilogCompilerState[module] = {decl=false}
end

function regModuleFunctions:instanceToVerilog( instance, module, fnname, inputVar, validVar, CEVar )
  local decl = nil
  if instance.verilogCompilerState[module].decl==false then
    decl = declareReg(self.type, instance.name, self.initial)
    instance.verilogCompilerState[module].decl=true
  end

  if fnname=="delay" or fnname=="set" then
    if self.hasCE==false and CEVar~=nil then err(false, "Reg was given a CE, but does not expect a CE. Function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."' "..instance.loc) end
    if self.hasCE and type(CEVar)~="string" then err(false, "Reg missing a CE. Function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."' "..instance.loc) end

    err( type(inputVar)=="string", "reg:set() or reg:delay() expected an input!")

    instance.verilogCompilerState[module].setData = inputVar
    instance.verilogCompilerState[module].setValid = validVar
    instance.verilogCompilerState[module].setCE = CEVar

    local name = instance.name
    if fnname=="set" then name = "_____REG_SET" end
    return name, decl, true
  elseif fnname=="get" then
    return instance.name, decl, true
  elseif fnname=="reset" then
    err( type(validVar)=="string", "reg:reset() was not given a valid var, but expects one "..instance.loc)
    err( CEVar==nil, "reg:reset() was given a CE, but does not expect one")
    --err( inputVar==nil, "reg:reset() was given data ("..inputVar..", but does not expect any")
    instance.verilogCompilerState[module].resetValid = validVar
    return "_____REG_RESET", decl, true
  else
    print("regModuleFunctions:instanceToVerilog",fnname)
    assert(false)
  end

end

function regModuleFunctions:instanceToVerilogFinalize( instance, module )
  local setData, setValid, setCE, resetValid = instance.verilogCompilerState[module].setData, instance.verilogCompilerState[module].setValid, instance.verilogCompilerState[module].setCE, instance.verilogCompilerState[module].resetValid

  err( type(setData)=="string", "reg, missing input value? "..instance.loc)

  if (self.hasCE or module.hasValid) then
    local resetExpr
    if self.resetValue~=nil then
      return [[  always @ (posedge CLK) begin if(]]..resetValid..") begin "..instance.name.." <= "..systolic.valueToVerilog(self.resetValue,self.type).."; end else if ("..J.sel(self.hasValid,setValid,"")..J.sel(self.hasValid and self.hasCE," && ","")..J.sel(self.hasCE,setCE,"")..") begin "..instance.name.." <= "..setData.."; end end"
    else
      return "  always @ (posedge CLK) begin if ("..J.sel(self.hasValid,setValid,"")..J.sel(self.hasValid and self.hasCE," && ","")..J.sel(self.hasCE,setCE,"")..") begin "..instance.name.." <= "..setData.."; end end"
    end

  elseif self.resetValue~=nil then
    return "  always @ (posedge CLK) begin "..instance.name.." <= ("..resetValid..")?"..systolic.valueToVerilog(self.resetValue,self.type)..":"..setData.."; end"
  else
    return "  always @ (posedge CLK) begin "..instance.name.." <= "..setData.."; end"
  end

end

function regModuleFunctions:getDependenciesLL() return {} end
function regModuleFunctions:toVerilog() return "" end
function regModuleFunctions:getDelay( fnname )
  return 0
end

-- by default, hasValid=true. (you would only want a register w/o a valid bit if you're wiring stuff up by hand and doing strange things)
function systolic.module.reg( ty, hasCE, initial, hasValid, resetValue, X )
  assert(X==nil)
  err(types.isType(ty),"type must be a type")
  err( ty:verilogBits()>0, "0 bit size register?")
  err(type(hasCE)=="boolean", "hasCE must be bool")
  if initial~=nil then ty:checkLuaValue(initial) end
  assert(hasValid==nil or type(hasValid)=="boolean")
  if hasValid==nil then hasValid=true end
  if resetValue~=nil then ty:checkLuaValue(resetValue) end

  -- ******** Note that hasValid==false makes this module pure!!!!!!!!!!!

  local t = {kind="reg",initial=initial,type=ty,options={coherent=true}, hasCE=hasCE, hasValid=hasValid, resetValue=resetValue}
  t.functions={}
  t.functions.delay={name="delay", output={type=ty}, inputParameter={name="DELAY_INPUT",type=ty},outputName="DELAY_OUTPUT",CE=systolic.CE("CE")}
  t.functions.delay.isPure = function() return hasValid==false end
  t.functions.set={name="set", output={type=types.null()}, inputParameter={name="SET_INPUT",type=ty},outputName="SET_OUTPUT",CE=systolic.CE("CE")}
  t.functions.set.isPure = function() return hasValid==false end

  if resetValue~=nil then
    t.functions.reset={name="reset", output={type=types.null()}, inputParameter={name="RESET_INPUT",type=types.null()},outputName="RESET_OUTPUT"}
    t.functions.reset.isPure = function() return false end
  end

  t.functions.get={name="get", output={type=ty}, inputParameter={name="GET_INPUT",type=types.null()},outputName="GET_OUTPUT"}
  t.functions.get.isPure = function() return true end
  return setmetatable(t,regModuleMT)
end

-------------------
systolic.module.regBy = memoize(function( ty, setby, CE, init, resetValue, hasSet, X)
  err( types.isType(ty), "systolic.module.regBy, type must be type" )
  assert( systolic.isModule(setby) )
  assert( setby:getDelay( "process" ) == 0 )
  assert( CE==nil or type(CE)=="boolean" )
  if init~=nil then ty:checkLuaValue(init) end
  if resetValue~=nil then ty:checkLuaValue(resetValue) end
  if hasSet==nil then hasSet=false end
  err( type(hasSet)=="boolean", "systolic.module.regBy: hasSet must be boolean but is "..tostring(hasSet))
  assert(X==nil)

  local R = systolic.module.reg( ty, CE, init, nil, resetValue ):instantiate("R")
  local inner = setby:instantiate("regby_inner")
  local fns = {}
  fns.get = systolic.lambda("get", systolic.parameter("getinp",types.null()), R:get(), "GET_OUTPUT" )

  -- check setby type
  --err(#setby.functions==1, "regBy setby module should only have process function")
  assert(setby.functions.process:isPure())
  local setbytype = setby:lookupFunction("process"):getInput().type
  assert(setbytype:isTuple())
  local setbyTypeA = setbytype.list[1]
  local setbyTypeB = setbytype.list[2]
  err( setbyTypeA==ty, "regby type does not match type on setby function" )

  local CEVar
  if CE then CEVar = systolic.CE("CE") end

  -- if we include the set function, and both set and setBy are called in the same cycle, set gets prescedence
  local sinp, setvalid
  if hasSet then
    sinp = systolic.parameter("set_inp",ty)
    setvalid = systolic.parameter("set_valid",types.bool())
    fns.set = systolic.lambda("set", sinp, nil, "SET_OUTPUT",{}, setvalid, CEVar )
  end

  local sbinp = systolic.parameter("setby_inp",setbyTypeB)
  local setbyvalidparam = systolic.parameter("setby_valid",types.bool())
  local setbyvalid = setbyvalidparam
  local setbyout = inner:process(systolic.tuple{R:get(),sbinp},systolic.null(),CEVar)

  if hasSet then
    setbyvalid = systolic.__or(setbyvalid,setvalid)
    setbyout = systolic.select(setvalid,sinp,setbyout)
  end

  fns.setBy = systolic.lambda("setby", sbinp, setbyout, "SETBY_OUTPUT",{R:set(setbyout,setbyvalid,CEVar)}, setbyvalidparam, CEVar )

  if resetValue~=nil then
    local resetvalid = systolic.parameter("reset_valid",types.bool())
    fns.reset = systolic.lambda("reset", systolic.parameter("reset_input",types.null()), R:reset(nil,resetvalid), "RESET_OUTPUT",{}, resetvalid )
  end

  local name = sanitize("RegBy_"..setby.name.."_CE"..tostring(CE).."_init"..tostring(init).."_reset"..tostring(resetValue))
  local M = systolic.module.new( name, fns, {R,inner}, true, nil,nil,{get=0,reset=0,setBy=0,set=0} )
  assert(systolic.isModule(M))
  return M
end)

-------------------
ram128ModuleFunctions={}
setmetatable(ram128ModuleFunctions,{__index=systolicModuleFunctions})
ram128ModuleMT={__index=ram128ModuleFunctions}

function ram128ModuleFunctions:getDelay(fnname) return 0 end
function ram128ModuleFunctions:getDependenciesLL() return {} end
function ram128ModuleFunctions:toVerilog() return "" end

function ram128ModuleFunctions:instanceToVerilogStart( instance, module )
  instance.verilogCompilerState = instance.verilogCompilerState or {}
  assert(instance.verilogCompilerState[module]==nil)
  instance.verilogCompilerState[module] = {}
end

function ram128ModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar, cevar )
  instance.verilogCompilerState[module][fnname]={datavar,validvar,cevar}
  local fn = self.functions[fnname]
  local decl
  if fnname=="write" then
    assert(type(cevar)=="string")
--    decl = declareWire( types.bool(), instance.name.."_"..fn.outputName)
  elseif fnname=="read" then
    decl = declareWire( types.bool(), instance.name.."_"..fn.outputName)
  else assert(false) end

  return instance.name.."_"..fn.outputName, decl, true
end


function ram128ModuleFunctions:instanceToVerilogFinalize( instance, module )
--[=[ wire ]]..instance.name..[[_WE;
wire ]]..instance.name..[[_D;
wire ]]..instance.name..[[_writeOut;
wire ]]..instance.name..[[_READ_OUTPUT;
wire [6:0] ]]..instance.name..[[_writeAddr;
wire [6:0] ]]..instance.name..[[_readAddr;
                               ]=]


local readAddr = instance.verilogCompilerState[module].read[1]

local writeInput, writeData, writeAddr, valid, CE, WE
if self.hasWrite then
  err(instance.verilogCompilerState[module].write~=nil, "Undriven write port, instance '"..instance.name.."' in module '"..module.name.."'"..instance.loc)

  writeInput = instance.verilogCompilerState[module].write[1]
  writeData = instance.name.."_writeInput[7]"
  writeAddr = instance.name.."_writeInput[6:0]"

  valid = instance.verilogCompilerState[module].write[2]
  CE = instance.verilogCompilerState[module].write[3]
  WE = valid.." && "..CE

else
  WE="1'b0"
  CE="1'b0"
  writeInput="8'd0"
  writeData="1'b0"
  writeAddr="7'd0"
end

local initS = ""
if self.init~=nil then
  local strlst = J.map(self.init,function(n) assert(type(n)=="boolean"); if n then return "1" else return "0" end end)
  strlst = J.reverse(strlst)
  initS = " #(.INIT(128'b"..table.concat( strlst,"")..")) "
end

return [[wire [7:0] ]]..instance.name..[[_writeInput = ]]..writeInput..[[;
wire ]]..instance.name..[[_writeOut;
RAM128X1D ]]..initS..instance.name..[[  (
  .WCLK(CLK),
  .D(]]..writeData..[[),
  .WE(]]..WE..[[),
  .SPO(]]..instance.name..[[_writeOut),
  .DPO(]]..instance.name..[[_READ_OUTPUT),
  .A(]]..writeAddr..[[),
  .DPRA(]]..readAddr..[[));
]]
end

function systolic.module.ram128(hasWrite,hasRead,init)
  if hasWrite==nil then hasWrite=true else assert(type(hasWrite)=="boolean") end
  if hasRead==nil then hasRead=true else assert(type(hasRead)=="boolean") end

  local __ram128 = {kind="ram128", functions={}, init=init, hasWrite=hasWrite, hasRead=hasRead}
  if hasRead then
    __ram128.functions.read={name="read", inputParameter={name="READ",type=types.uint(7)},outputName="READ_OUTPUT", output={type=types.bits(1)}}
    __ram128.functions.read.isPure = function() return true end
  end

  if hasWrite then
    __ram128.functions.write={name="write", inputParameter={name="WRITE",type=types.tuple{types.uint(7),types.bits(1)}},outputName="WRITE_OUTPUT", output={type=types.bits(1)}, CE=systolic.CE("CE")}
    __ram128.functions.write.isPure = function() return false end
  end

  setmetatable(__ram128,ram128ModuleMT)

  return __ram128 
end

--------------------
bramModuleFunctions={}
setmetatable(bramModuleFunctions,{__index=systolicModuleFunctions})
bramModuleMT={__index=bramModuleFunctions}

function bramModuleFunctions:instanceToVerilogStart( instance, module )
  instance.verilogCompilerState = instance.verilogCompilerState or {}
  assert(instance.verilogCompilerState[module]==nil)
  instance.verilogCompilerState[module] = {}
end

function bramModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar, cevar )
  instance.verilogCompilerState[module][fnname]={datavar,validvar,cevar}
  local fn = self.functions[fnname]
  local decl
  if fnname=="writeAndReturnOriginal" then
    assert(type(cevar)=="string")
    decl = declareWire( types.bits( self.inputBits ), instance.name.."_"..fn.outputName)
  elseif fnname=="read" then
    decl = declareWire( types.bits( self.outputBits ), instance.name.."_"..fn.outputName)
  else assert(false) end

  return instance.name.."_"..fn.outputName, decl, true
end


function bramModuleFunctions:getDependenciesLL() return {} end
function bramModuleFunctions:toVerilog() return "" end
function bramModuleFunctions:getDelay( fnname ) 
  if fnname=="writeAndReturnOriginal" then return 1
  elseif fnname=="read" then return 1
  else assert(false) end
end

----------------------
-- the tradeoff is:
-- TDP has 2 independent RW/R/W. 2 input ports, 2 output ports.
-- SDP has either 1 RW or (1 R and 1 W), but twice the bit width as TDP. It has enough address lines to do 2 RW, but only has 1 input port and 1 output port.
-- where 'RW' means a read and write at same address. 'RW/R/W' means either a RW, R, or W at an address.


-- 2KB SDP ram
bram2KSDPModuleFunctions={}
setmetatable(bram2KSDPModuleFunctions,{__index=bramModuleFunctions})
bram2KSDPModuleMT={__index=bram2KSDPModuleFunctions}

function bram2KSDPModuleFunctions:instanceToVerilogFinalize( instance, module )
  local VCS = instance.verilogCompilerState[module]
  
  for k,v in pairs(VCS) do assert(k=="writeAndReturnOriginal" or k=="read") end

  if self.writeAndReturnOriginal then
    -- we only used 1 port

    -- we only use the 18 kbit wide BRAM here, b/c AFAIK using the 36 kbit BRAM doesn't provide a benefit, so there's no reason to special case that

    local width
    if self.inputBits<8 and self.inputBits>0 then
      width = self.inputBits -- BRAM modules <8 bits have no parity bits
    elseif self.inputBits==8 then
      width = 9
    elseif self.inputBits==16 then
      width = 18
    elseif self.inputBits==32 then
      width = 36
    else
      error("unsupported BRAM2KSDP bitwidth,"..self.inputBits )
      assert(false)
    end


    local initS = ""
    if self.init~=nil then
      -- init should be an array of bytes
      assert( type(self.init)=="table")
      assert( #self.init == 2048 )
      for block=0,63 do
        local S = {}
        for i=0,31 do 
          local value = self.init[block*32+i+1]
          err( value < 256 and value>=0, "bram2KSDP: value must be <256 and >=0, but is "..tostring(value)..", block "..tostring(block).." index "..tostring(i) )
          table.insert(S,1,string.format("%02x",value)) 
        end
        initS = initS..".INIT_"..string.format("%02X",block).."(256'h"..table.concat(S,"").."),\n"
      end
    end

    local addrbits = math.log((2048*8)/self.inputBits)/math.log(2)

    local valid = VCS.writeAndReturnOriginal[2]
    local CEvar = VCS.writeAndReturnOriginal[3]
    if self.CE then valid=valid.." && "..CEvar end
    assert(type(CEvar)=="string")

    local conf={name=instance.name}
    conf.A={bits=self.inputBits,
           DI = instance.name.."_INPUT["..(addrbits+self.inputBits-1)..":"..addrbits.."]",
           DO = instance.name.."_SET_AND_RETURN_ORIG_OUTPUT",
           ADDR = instance.name.."_INPUT["..(addrbits-1)..":0]",
           CLK = "CLK",
           EN=CEvar,
           WE = valid,
           readFirst = true}

    if VCS.read~=nil then

      conf.B={bits=self.outputBits,
           DI = instance.name.."_DI_B",
           DO = instance.name.."_READ_OUTPUT",
           ADDR = VCS.read[1],
           CLK = "CLK",
           EN=VCS.read[3],
           WE = "1'd0",
           readFirst = true}

    else
    conf.B={bits=self.inputBits,
           DI = instance.name.."_DI_B",
           DO = instance.name.."_DO_B",
           ADDR = instance.name.."_addr_B",
           CLK = "CLK",
           EN=CEvar,
           WE = "1'd0",
           readFirst = true}

    end

    conf.init = self.init

   return [[reg []]..(self.inputBits-1)..":0] "..instance.name..[[_DI_B;
reg []]..(addrbits-1)..":0] "..instance.name..[[_addr_B;
wire []]..(self.inputBits-1)..":0] "..instance.name..[[_DO_B;
wire []]..(self.inputBits+addrbits-1)..[[:0] ]]..instance.name..[[_INPUT;
assign ]]..instance.name..[[_INPUT = ]]..VCS.writeAndReturnOriginal[1]..[[;
]]..table.concat(fixedBram(conf))

-- It turns out that once you drill down, the 7 series BRAMs are just macros
-- built out of Spartan 3 BRAMS, but with less options.
--[=[
    local addrbits = math.log((2048*8)/self.inputBits)/math.log(2)
    local addrS = instance.name.."_INPUT[13:0]"
    if self.inputBits>1 then
      -- bram macro ignore bottom bits
      addrS = "{"..instance.name.."_INPUT["..(addrbits-1)..":0],"..(14-addrbits).."'b0}"
    end

    local DI = [[.DIBDI(]]..instance.name.."_INPUT["..(addrbits+16-1)..":"..addrbits.."]),"
    if self.inputBits>16 then
      -- for whatever reason, input ports are flipped in this mode
      DI = ".DIADI("..instance.name.."_INPUT["..(addrbits+16-1)..":"..addrbits.."]),.DIBDI("..instance.name.."_INPUT["..(addrbits+32-1)..":"..(addrbits+16).."]),"
    end


    --local debug = [[always @(posedge CLK) begin $display("BRAM v %d ce %d addr %d OUT %H inp %H",]]..VCS.writeAndReturnOriginal[2]..[[,CE,]]..addrS..[[,]]..instance.name..[[_SET_AND_RETURN_ORIG_OUTPUT[15:0],]]..instance.name..[[_INPUT[]]..(addrbits+32-1)..":"..(addrbits)..[[]); end]]

    -- signals that don't seem to matter: DIPADIP, DIPBDIP, DOPADOP, DOPBDOP:
    -- //.ENBWREN(1'b0), // in SDP this is write enable
    -- //.REGCEAREGCE(1'b1), // DO_REG clock enable
    -- //.REGCEB(1'b1), // DO_REG clock enable

    return [[wire []]..(self.inputBits+addrbits-1)..[[:0] ]]..instance.name..[[_INPUT;
assign ]]..instance.name..[[_INPUT = ]]..VCS.writeAndReturnOriginal[1]..[[;
RAMB18E1 #(.DOA_REG(0),
.DOB_REG(0),
.RAM_MODE("SDP"),
.READ_WIDTH_A(]]..width..[[),  // in SDP, this is read width including parity
.READ_WIDTH_B(0),  // not used for SDP
.WRITE_WIDTH_A(0), // not used in SDP
.WRITE_WIDTH_B(]]..width..[[),  // in SDP, this is write width including parity
.WRITE_MODE_A("READ_FIRST"),  // READ_FIRST
.WRITE_MODE_B("READ_FIRST"),
.RDADDR_COLLISION_HWCONFIG("PERFORMANCE"),
]]..initS..[[
.SIM_DEVICE("7SERIES"),
.SIM_COLLISION_CHECK("ALL")
) ]]..instance.name..[[(]]..DI..[[
.DOADO(]]..instance.name..[[_SET_AND_RETURN_ORIG_OUTPUT[15:0]),
.DOBDO(]]..instance.name..[[_SET_AND_RETURN_ORIG_OUTPUT[31:16]),
.ADDRARDADDR(]]..addrS..[[), // in SDP, this is read addr
.ADDRBWRADDR(]]..addrS..[[), // in SDP, this is write addr
.WEBWE(4'b1111), // in SDP this is write port enable
.ENARDEN(]]..valid..[[), // in SDP this is read enable
.ENBWREN(]]..valid..[[), // in SDP this is write enable
.WEA(2'b0),             // Port A (read port in SDP) Write Enable[3:0], input
.RSTRAMARSTRAM(1'b0),
.RSTREGARSTREG(1'b0),
.RSTRAMB(1'b0),
.RSTREGB(1'b0),
.CLKARDCLK(CLK), // in SDP, this is read clock
.CLKBWRCLK(CLK) // in SDP, this is write clock
);]]
]=]
  else
    print("INVALID BRAM CONFIGURATION")
    for k,v in pairs(VCS) do print("VCS",k) end
    assert(false)
  end
end

-- if outputBits==nil, we don't make a read port (only a write port)
function systolic.module.bram2KSDP( writeAndReturnOriginal, inputBits, outputBits, CE, init, X )
  assert(X==nil)
  err( type(writeAndReturnOriginal)=="boolean", "writeAndReturnOriginal must be bool")
  err( type(inputBits)=="number", "inputBits must be a number")
  err( outputBits==nil or type(outputBits)=="number", "outputBits must be a number")
  err( type(CE)=="boolean", "CE must be bool" )

  if init~=nil then
    assert(type(init)=="table")
    err(#init==2048, "init table has size "..(#init).." but should have size 2048")
  end

  err(inputBits==8 or inputBits==16 or inputBits==32 or inputBits==4 or inputBits==2 or inputBits==1, "inputBits must be 1,2,4,8,16, or 32")

  local t = {kind="bram2KSDP",functions={}, inputBits = inputBits, outputBits = outputBits, writeAndReturnOriginal=writeAndReturnOriginal, init=init}
  local addrbits = math.log((2048*8)/inputBits)/math.log(2)
  if writeAndReturnOriginal then
    --err( inputBits==outputBits, "with writeAndReturnOriginal, inputBits and outputBits must match")
    t.functions.writeAndReturnOriginal = {name="writeAndReturnOriginal", inputParameter={name="SET_AND_RETURN_ORIG",type=types.tuple{types.uint(addrbits),types.bits(inputBits)}},outputName="SET_AND_RETURN_ORIG_OUTPUT", output={type=types.bits(inputBits)}, CE=systolic.CE("CE_write")}
    t.functions.writeAndReturnOriginal.isPure = function() return false end

    if outputBits~=nil then
      t.functions.read = {name="read", inputParameter={name="READ",type=types.uint(addrbits)},outputName="READ_OUTPUT", output={type=types.bits(outputBits)},CE=systolic.CE("CE_read")}
      t.functions.read.isPure = function() return true end
    end
  else
    -- NYI
    assert(false)
  end

  return setmetatable( t, bram2KSDPModuleMT )
end

--------------------
fileModuleFunctions={}
setmetatable(fileModuleFunctions,{__index=systolicModuleFunctions})
fileModuleMT={__index=fileModuleFunctions}

function fileModuleFunctions:instanceToVerilogStart( instance, module )
  instance.verilogCompilerState = instance.verilogCompilerState or {}
  assert(instance.verilogCompilerState[module]==nil)
  instance.verilogCompilerState[module] = {}
end

function fileModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar, cevar )
  assert( type(validvar) == "string" )
  instance.verilogCompilerState[module][fnname]={datavar,validvar,cevar}

  if fnname~="reset" and self.CE then err(type(cevar)=="string","Missing CE for file, function '"..fnname.."' instance '"..instance.name.."'") end

  local decl = nil
  local fn = self.functions[fnname]
  if fnname=="read" or fnname=="write" then
    decl = declareReg( fn.output.type, instance.name.."_"..fn.outputName)
  end
  return instance.name.."_"..fn.outputName, decl, true
end

-- verilator doesn't suport $fopen etc so hack around it...
FILEMODULE_VERILATOR = true

function fileModuleFunctions:instanceToVerilogFinalize( instance, module )
  if instance.callsites.read~=nil and instance.callsites.write==nil then
    local assn = ""
    for i=0,(self.type:verilogBits()/8)-1 do
      assn = assn .. instance.name.."_out["..((i+1)*8-1)..":"..(i*8).."] <= $fgetc("..instance.name.."_file); "
    end

    local RST = ""
    if instance.verilogCompilerState[module].reset~=nil then
      RST = "if ("..instance.verilogCompilerState[module].reset[2]..") begin r=$fseek("..instance.name.."_file,0,0); end"
    end

    return [[integer ]]..instance.name..[[_file,r;
  initial begin ]]..instance.name..[[_file = $fopen("]]..self.filename..[[","r"); end
  always @ (posedge CLK) begin 
  if (]]..instance.verilogCompilerState[module].read[2]..J.sel(self.CE," && "..instance.verilogCompilerState[module].read[3],"")..[[) begin ]]..assn..[[ end 
    ]]..RST..[[
  end
]]
  elseif instance.callsites.read==nil and instance.callsites.write~=nil then
    local assn = ""

    local debug = ""
    --debug = [[always @(posedge CLK) begin $display("write v %d ce %d value %h",]]..instance.verilogCompilerState[module].write[2]..[[,CE,]]..instance.verilogCompilerState[module].write[1]..[[); end]]

    err(self.type:verilogBits() % 8 == 0, "Error, systolic file module type ("..tostring(self.type)..") is not byte aligned. NYI. Use a cast!")

    for i=0,math.ceil(self.type:verilogBits()/8)-1 do
      if FILEMODULE_VERILATOR then
--        assn = assn .. [[$c("fwrite( (void*) &",]]..instance.verilogCompilerState[module].write[1].."["..((i+1)*8-1)..":"..(i*8)..[[],",1,1, (FILE*)",]]..instance.name..[[_file,");" );]]
        assn = assn .. [[$c("fwrite( (void*) &",]]..instance.name.."_buffer_"..tostring(i)..[[,",1,1, (FILE*)",]]..instance.name..[[_file,");" );]]
      else
        assn = assn .. "$fwrite("..instance.name..[[_file, "%c", ]]..instance.verilogCompilerState[module].write[1].."["..((i+1)*8-1)..":"..(i*8).."] ); "
      end
    end

    local RST = ""
    if instance.verilogCompilerState[module].reset~=nil then
      if FILEMODULE_VERILATOR then
        RST = "if ("..instance.verilogCompilerState[module].reset[2]..[[) begin $c("rewind( (FILE*)",]]..instance.name..[[_file,");"); end]]
      else
        RST = "if ("..instance.verilogCompilerState[module].reset[2]..[[) begin r=$fseek(]]..instance.name..[[_file,0,0); end]]
      end
    end
    if FILEMODULE_VERILATOR then
      local buffers = ""
      local bufferassn = ""
      -- if we don't assign to buffers of the right size, the c escape won't work properly
      for i=0,math.ceil(self.type:verilogBits()/8)-1 do
        buffers = buffers.."reg [7:0] "..instance.name.."_buffer_"..tostring(i)..";\n"
        bufferassn = bufferassn..[[if (]]..J.sel(self.CE,instance.verilogCompilerState[module].write[3],"true")..[[) begin ]]
        bufferassn = bufferassn..instance.name.."_buffer_"..tostring(i).."<="..instance.verilogCompilerState[module].write[1].."["..((i+1)*8-1)..":"..(i*8).."]; end\n"
      end

      local obuffers = ""
      local fn = self.functions.write
      obuffers = obuffers..declareReg( fn.output.type, instance.name.."_obuffer0",nil,"\n")
      --obuffers = obuffers..declareReg( fn.output.type, instance.name.."_obuffer1")

      local oassign = ""
      oassign = oassign..[[  if (]]..J.sel(self.CE,instance.verilogCompilerState[module].write[3],"true")..[[) begin ]]..instance.name.."_obuffer0<="..instance.verilogCompilerState[module].write[1].."; end\n"
      oassign = oassign..[[  if (]]..J.sel(self.CE,instance.verilogCompilerState[module].write[3],"true")..[[) begin ]]..instance.name.."_writeOut<="..instance.name.."_obuffer0; end\n"
      
      return debug..obuffers..buffers..[[
  reg[63:0] ]]..instance.name..[[_file;
  reg ]]..instance.name..[[_dowrite=1'b0;
  initial begin $c(]]..instance.name..[[_file," = (QData)fopen(\"]]..self.filename..[[\",\"wb\");"); 
$c("if(",]]..instance.name..[[_file,"==0){printf(\"ERROR OPENING FILE ]]..self.filename..[[\");exit(1);}");
end

  always @ (posedge CLK) begin 
    ]]..bufferassn..oassign..[[
    if (]]..instance.name..[[_dowrite]]..J.sel(self.CE," && "..instance.verilogCompilerState[module].write[3],"")..[[) begin ]]..assn..[[ end
    if (]]..J.sel(self.CE,instance.verilogCompilerState[module].write[3],"true")..[[) begin ]]..instance.name..[[_dowrite<=]]..instance.verilogCompilerState[module].write[2]..[[; end 
    ]]..RST..[[
  end
]]
    else
      return debug..[[integer ]]..instance.name..[[_file,r;
  initial begin ]]..instance.name..[[_file = $fopen("]]..self.filename..[[","wb"); end
  always @ (posedge CLK) begin 
    if (]]..instance.verilogCompilerState[module].write[2]..J.sel(self.CE," && "..instance.verilogCompilerState[module].write[3],"")..[[) begin ]]..assn..[[ end 
    ]]..RST..[[
  end
]]
   end
  else
    assert(false)
  end
end

function fileModuleFunctions:toVerilog() return "" end
function fileModuleFunctions:getDependenciesLL() return {} end
function fileModuleFunctions:getDelay(fnname)
  if fnname=="write" then
    if FILEMODULE_VERILATOR then
      -- hack: write enough cycles for the c code to actually execute before we return data, to make sure all writes occur before simulator is killed.
      return 2
    else
      return 0
    end
  elseif fnname=="read" then
    return 1
  elseif fnname=="reset" then
    return 0
  else
    print(fnname)
    assert(false)
  end
end

function systolic.module.file( filename, ty, CE, passthrough, X)
  assert(X==nil)
  assert(type(CE)=="boolean")

  err(ty:verilogBits() % 8 == 0, "Error, systolic file module type ("..tostring(ty)..") is not byte aligned. NYI. Use a cast!")
  
  local res = {kind="file",filename=filename, type=ty, CE=CE, passthrough }
  res.functions={}
  res.functions.read={name="read",output={type=ty},inputParameter={name="FREAD_INPUT",type=types.null()},outputName="readOut",valid={name="read_valid"},CE=systolic.CE("CE")}
  res.functions.read.isPure = function() return false end
  res.functions.write={name="write",output={type=J.sel(passthrough,ty,types.null())},inputParameter={name="input",type=ty},outputName="writeOut",valid={name="write_valid"},CE=systolic.CE("CE")}
  res.functions.write.isPure = function() return false end
  res.functions.reset = {name="reset",output={type=types.null()},inputParameter={name="input",type=types.null()},outputName="out",valid={name="reset_valid"}}
  res.functions.reset.isPure = function() return false end

  return setmetatable(res, fileModuleMT)
end

--------------------------------------------------------------------
printModuleFunctions={}
setmetatable(printModuleFunctions,{__index=systolicModuleFunctions})
printModuleMT={__index=printModuleFunctions}

function printModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar, cevar )

  local datalist = ""
  if self.type:isTuple() then
    local bit = 0
    for k,v in pairs(self.type.list) do
      if k~=1 then datalist=datalist.."," end
      if v:verilogBits()==0 then
        datalist = datalist.."0"
      else
        datalist = datalist..instance.name.."["..(bit+v:verilogBits()-1)..":"..bit.."]"
      end
      bit = bit + v:verilogBits()
    end
  else
    datalist = datavar
  end

  local validS = ""
  local validSS = ""
  if validvar~=nil then validS,validSS="valid %d",validvar.."," end

  err(self.CE==false or type(cevar)=="string", "Error, missing CE from print instance '"..instance.name.."' on module '"..module.name.."'")
  if self.CE then validS = validS.." CE %d"; validSS = validSS..cevar.."," end

  local decl = [[wire []]..(self.type:verilogBits()-1)..":0] "..instance.name..[[;
assign ]]..instance.name..[[ = ]]..datavar..[[;
]]

  if self.showIfInvalid then
    decl = decl..[[always @(posedge CLK) begin $display("%s(]]..validS..[[): ]]..self.str..[[",INSTANCE_NAME,]]..validSS..datalist..[[); end]]
  else
    decl = decl..[[always @(posedge CLK) begin if(]]..validvar..[[) begin $display("%s: ]]..self.str..[[",INSTANCE_NAME,]]..datalist..[[);end end]]
  end

  return "___NULL_PRINT_OUT", decl, true
end

function printModuleFunctions:toVerilog() return "" end
function printModuleFunctions:getDependenciesLL() return {} end
function printModuleFunctions:getDelay(fnname) return 0 end

-- showIfInvalid: should we display the print in invalid cycles? default true
function systolic.module.print( ty, str, CE, showIfInvalid, X )
  assert(X==nil)
  err( types.isType(ty), "type input to print module should be type")
  err( type(str)=="string", "string input to print module should be string")
  err( CE==nil or type(CE)=="boolean", "CE must be bool")
  err( showIfInvalid==nil or type(showIfInvalid)=="boolean", "showIfInvalid should be nil or bool")
  if CE==nil then CE=false end
  if showIfInvalid==nil then showIfInvalid=true end

  local res = {kind="print",str=str, type=ty, CE=CE, showIfInvalid=showIfInvalid}
  res.functions={}
  res.functions.process={name="process",output={type=types.null()},inputParameter={name="PRINT_INPUT",type=ty},outputName="out",valid={name="process_valid"},CE=J.sel(CE,systolic.CE("CE"),nil)}
  res.functions.process.isPure = function() return false end
  return setmetatable(res, printModuleMT)
end

--------------------------------------------------------------------
assertModuleFunctions={}
setmetatable(assertModuleFunctions,{__index=systolicModuleFunctions})
assertModuleMT={__index=assertModuleFunctions}

function assertModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar, cevar )
  local CES = ""
  if self.CE then 
    err( type(cevar)=="string", "Assert missing CE for instance '"..instance.name.."' in module '"..module.name.."'")
    CES=" && "..cevar.."==1'b1" 
  end
  local finish = "$finish(); "
  if self.exit==false then finish="" end
  local decl = [[always @(posedge CLK) begin if(]]..datavar..[[ == 1'b0 && ]]..validvar..[[==1'b1]]..CES..[[) begin $display("%s: ]]..self.str..[[",INSTANCE_NAME);]]..finish..[[ end end]]
  return "___NULL_ASSERT_OUT", decl, true
end

function assertModuleFunctions:toVerilog() return "" end
function assertModuleFunctions:getDependenciesLL() return {} end
function assertModuleFunctions:getDelay(fnname) return 0 end

function systolic.module.assert( str, CE, exit, X )
  assert(X==nil)
  err( type(str)=="string", "string input to print module should be string")
  err( type(CE)=="boolean", "CE must be boolean" )
  err( exit==nil or type(exit)=="boolean", "Exit must be bool or nil")

  local res = {kind="assert",str=str, exit=exit, CE = CE}
  res.functions={}
  res.functions.process={name="process",output={type=types.null()},inputParameter={name="ASSERT_INPUT",type=types.bool()},outputName="out",valid={name="process_valid"},CE=J.sel(CE,systolic.CE("CE"),nil)}
  res.functions.process.isPure = function() return false end
  return setmetatable(res, assertModuleMT)
end

return systolic
