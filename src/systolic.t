local IR = require("ir")
local types = require("types")
local typecheckAST = require("typecheck")
local systolic={}

systolicModuleFunctions = {}
systolicModuleMT={__index=systolicModuleFunctions}

systolicInstanceFunctions = {}

systolicAST = {}
function systolicAST.isSystolicAST(ast)
  return getmetatable(ast)==systolicASTMT
end
systolic.isAST = systolicAST.isSystolicAST

local __usedNameCnt = 0
function systolicAST.new(tab)
  assert(type(tab)=="table")
  assert(type(tab.inputs)=="table")
  assert(#tab.inputs==keycount(tab.inputs))
  if tab.name==nil then tab.name="unnamed"..__usedNameCnt; __usedNameCnt=__usedNameCnt+1 end
  assert(types.isType(tab.type))
  if tab.pipelined==nil then tab.pipelined=true end
  IR.new(tab)
  return setmetatable(tab,systolicASTMT)
end


local function getloc()
--  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline
  return debug.traceback()
end

function sanitize(s)
  s = s:gsub("%[","_")
  s = s:gsub("%]","_")
  s = s:gsub("%,","_")
  s = s:gsub("%.","_")
  return s
end

local function checkast(ast) err( systolicAST.isSystolicAST(ast), "input should be a systolic AST" ); return ast end

local function typecheck(ast)
  return systolicAST.new( typecheckAST(ast,systolicAST.new) )
end

function checkReserved(k)
  if k=="input" or k=="output" or k=="reg" then
    print("Error, variable name ",k," is a reserved keyword in verilog")
    assert(false)
  end
end

local binopToVerilog={["+"]="+",["*"]="*",["<<"]="<<<",[">>"]=">>>",["pow"]="**",["=="]="==",["and"]="&",["-"]="-",["<"]="<",[">"]=">",["<="]="<=",[">="]=">="}

local binopToVerilogBoolean={["=="]="==",["and"]="&&",["~="]="!=",["or"]="||",["xor"]="^"}

function systolic.declareReg(ty, name, initial, comment)
  assert(type(name)=="string")

  if comment==nil then comment="" end

  if initial==nil or initial=="" then 
    initial=""
  else
    initial = " = "..valueToVerilog(initial,ty)
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
    str = " = "..str
  end

  assert( ty~=types.null() )
  if ty:isBool() then
    return "wire "..name..str..";"..comment
  else
    return "wire ["..(ty:verilogBits()-1)..":0] "..name..str..";"..comment
  end
end
declareWire = systolic.declareWire

function systolic.wireIfNecessary( inputIsWire, declarations, ty, name, str, comment )
  if inputIsWire then return str end
  local decl = systolic.declareWire( ty, name, str, comment)
  table.insert(declarations, decl)
  return name
end

function declarePort( ty, name, isInput )
  assert(type(name)=="string")

  local t = "input "
  if isInput==false then t = "output " end

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
    return bits.."'d"..math.abs(value)
  end
end

function valueToVerilog(value,ty)
  assert(types.isType(ty))

  if ty:isInt() then
    assert(type(value)=="number")
    if value==0 then
      return (ty:sizeof()*8).."'d0"
    elseif value<0 then
      return "-"..(ty:sizeof()*8).."'d"..math.abs(value)
    else
      return (ty:sizeof()*8).."'d"..value
    end
  elseif ty:isUint() then
    assert(type(value)=="number")
    assert(value>=0)
    return (ty:sizeof()*8).."'d"..value
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
    return "{"..table.concat( reverse( map( value, function(v) return valueToVerilog(v,ty:arrayOver()) end ) ), "," ).."}"
  else
    print("valueToVerilog",ty)
    assert(false)
  end
end

function systolicModuleFunctions:instantiate( name, options )
  err( type(name)=="string", "instantiation name must be a string")
  if options==nil then options={} end
  return systolicInstance.new({ kind="module", module=self, name=name, options=options, callsites={} })
end

systolicFunctionFunctions = {}
systolicFunctionMT={__index=systolicFunctionFunctions}

systolicFunction = {}
function systolic.isFunction(t)
  return getmetatable(t)==systolicFunctionMT or getmetatable(t)==systolicFunctionConstructorMT
end

function systolic.lambda( name, input, output, outputName, pipelines, valid )
  err( systolicAST.isSystolicAST(input), "input must be a systolic AST" )
  err( systolicAST.isSystolicAST(output) or output==nil, "output must be a systolic AST or nil" )
  err( systolicAST.isSystolicAST(valid) or valid==nil, "valid must be a systolic AST or nil" )
  err( input.kind=="parameter", "input must be a parameter" )
  err( type(outputName)=="string", "output name must be a string")
  
  if pipelines==nil then pipelines={} end
  local implicitValid = false
  if valid==nil then implicitValid=true;valid = systolic.parameter(name.."_valid", types.bool()) end
  --if output~=nil then output = output:addValid( valid ) end
  --pipelines = map( pipelines, function(n) return n:addValid(valid) end )

  local t = { name=name, input=input, output = output, outputName=outputName, pipelines=pipelines, valid=valid, implicitValid=implicitValid }

  return setmetatable(t,systolicFunctionMT)
end

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
  map( self.pipelines, function(n) purePipes = purePipes and n:isPure(self.valid) end )

  if self.output==nil then return purePipes end
  return self.output:isPure(self.valid) and purePipes
end

function systolicFunctionFunctions:isAccessor()
  return #self.inputs==0
end


function systolicFunctionFunctions:getDefinitionKey()
  assert(self.pure)
  return self
end

local function binop(lhs, rhs, op)
  lhs, rhs = checkast(lhs), checkast(rhs)
  return typecheck({kind="binop",op=op,inputs={lhs,rhs},loc=getloc()})
end

local function unary(expr, op)
  expr = checkast(expr)
  return typecheck{kind="unary",op=op,inputs={expr}}
end

systolic._callsites = {}
systolicInstance = {}
function systolicInstance.new(tab)
  return setmetatable(tab,systolicInstanceMT)
end

function systolic.isInstance(tab)
  return getmetatable(tab)==systolicInstanceMT
end

systolicInstanceMT={
__index = function(tab,key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  v = systolicInstanceFunctions[key]

  if v==nil and rawget(tab,"kind")=="module" then
    -- try to find key in function tab
    local fn = rawget(tab,"module").functions[key]
    if fn~=nil then
      return function(self, inp, valid)
        if inp==nil then inp = systolic.null() end -- give this a stub value that evaluates to nil
        err( systolicAST.isSystolicAST(inp), "input must be a systolic ast or nil" )
        
        tab.callsites[fn.name] = tab.callsites[fn.name] or {}

        err( inp.type==fn.input.type, "Error, input type to function '"..fn.name.."' on module '"..tab.name.."' incorrect. Is '"..tostring(inp.type).."' but should be '"..tostring(fn.input.type).."'" )

        local otype = types.null()
        if fn.output~=nil then otype = fn.output.type end

        if fn.input.type==types.null() then
          -- if this fn takes no inputs, it doesn't matter what arbitration strategy we use
          if #tab.callsites[fn.name]==0 then
            local t = { kind="call", inst=self, fnname=key, func=fn, type=otype, loc=getloc(), inputs={inp,valid} }
            table.insert(tab.callsites[fn.name], systolicAST.new(t))
            return tab.callsites[fn.name][1]
          else
            -- cheap CSE
            return tab.callsites[fn.name][1]
          end
        elseif self.options.arbitrate==nil then
          -- no arbitration
          if #tab.callsites[fn.name]==0 then
            local t = { kind="call", inst=self, fnname=key, func=fn, type=otype, loc=getloc(), inputs={inp,valid} }
            table.insert(tab.callsites[fn.name], systolicAST.new(t))
            return tab.callsites[fn.name][1]
          else
            error("Function '"..fn.name.."' on instance '"..self.name.."' can't have multiple callsites!")
          end
        elseif self.options.arbitrate=="valid" then
          if #tab.callsites[fn.name]==0  then

            err(inp~=nil, "call aribtrate - missing input?")
            err(valid~=nil, "NYI - in call arbitrate, you must explicitly pass valid bits")
            local tca = { kind="callArbitrate", fn=fn.name, instance=self, type=types.tuple{fn.input.type,types.bool()}, loc=getloc(), inputs={inp,valid} }
            tca = systolicAST.new(tca)
            local t = { kind="call", inst=self, fnname=key, func=fn, type=otype, loc=getloc(), inputs={systolic.index(tca,0),systolic.index(tca,1)} }
            table.insert( tab.callsites[fn.name], {tca,t} )
            return systolicAST.new(t)
          else
            -- mutate the callArbitrate. Don't introduce cycles! NYI - CHECK FOR THAT
            local tca = tab.callsites[fn.name][1][1]
            local t = tab.callsites[fn.name][1][2]
            print("CABEFORE",self.kind,self.name,tca,#tca.inputs)
            err(inp~=nil, "call aribtrate - missing input?")
            table.insert(tca.inputs,inp)
            err(valid~=nil, "NYI - in call arbitrate, you must explicitly pass valid bits")
            table.insert(tca.inputs,valid)
            print("CA",self.kind,self.name,tca,#tca.inputs)
            return t
          end
          assert(false)
        else
          assert(false)
        end

      end
    end
    
  end
  return v
end}

systolicASTFunctions = {}
setmetatable(systolicASTFunctions,{__index=IR.IRFunctions})
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
    return systolicAST.new({kind="delay",delay=delayvalue,inputs={tab},type=tab.type})
  end
end,
  __newindex = function(table, key, value)
                    darkroom.error("Attempt to modify systolic AST node")
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
  -- slice will return an array or tuple with one element. so we need to do a cast.
  if expr.type:isArray() then
    return systolic.cast( systolic.slice(expr, idx, idx, idy, idy), expr.type:arrayOver() )
  elseif expr.type:isTuple() then
    local v = systolic.slice(expr, idx, idx, idy, idy)
    return systolic.cast( v, v.type.list[1] )
  end
  err(false, "Index only works on tuples and arrays")
end

function systolic.bitSlice( expr, low, high )
  err( systolicAST.isSystolicAST(expr), "input to bitSlice must be a systolic ast")
  err( type(low)=="number", "low must be number")
  err( type(high)=="number", "high must be number")
  return typecheck({kind="bitSlice",inputs={expr},low=low,high=high,loc=getloc()})
end

function systolic.constant( v, ty )
  err( types.isType(ty), "constant type must be a type")

  if ty:isArray() then
    err( type(v)=="table", "if type is an array, v must be a table")
    map( v,function(n) err(type(n)=="number", "array element must be a number") end )
    err( #v==ty:channels(), "incorrect number of channels" )
  else
    err( type(v)=="number" or type(v)=="boolean", "systolic constant must be bool or number")
  end

  return typecheck({ kind="constant", value=v, type = ty, loc=getloc(), inputs={} })
end

function systolic.tuple( tab )
  err( type(tab)=="table", "input to tuple should be a table")
  local res = {kind="tuple",inputs={}, loc=getloc()}
  map(tab, function(v,k) err( systolicAST.isSystolicAST(v), "input to tuple should be table of ASTs"); res.inputs[k]=v end )
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

local __NULLTAB = systolicAST.new({kind="null",type=types.null(),inputs={}})
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
function systolic.neg(expr) return unary(expr,"-") end
function systolic.isX(expr) return unary(expr,"isX") end
function systolic.__not(expr) return unary(expr,"not") end

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
    map(scopes, function(n) print("scope",n.name) end)
    assert(false)
  end
end

-- check that all of the variables refered to are actually in scope
-- scopes goes from innermost (index 1) to outermost (index n)
function systolicASTFunctions:checkVariables(scopes)
  assert(type(scopes)=="table")

  local function astcheck(n)
    if n.kind=="readinput" or n.kind=="reg" or n.kind=="ram128" or n.kind=="call" then
      checkForInst(n.inst, scopes)
    end

    if n.kind=="fndefn" then
      local i=1
      while n["dst"..i] do
        checkForInst(n["dst"..i], scopes)
        i = i + 1
      end
    end

    if n.kind=="call" and n.func:isPure()==false then
      assert(systolicAST.isSystolicAST(n.valid))
    end
  end

  self:visitEach(astcheck)
end

function systolicASTFunctions:checkInstances( instMap )
  self:visitEach( 
    function(n)
      if n.kind=="call" then
        err( instMap[n.inst]~=nil, "Error, instance "..n.inst.name.." is not a member of this module, "..n.loc )
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
        return foldl( andop, true, inputs )
      end
    end)
end

function systolicASTFunctions:const()
  if self.kind=="constant" then
    return self.value
  end
  return nil
end

function systolicASTFunctions:setName(s)
  assert(type(s)=="string")
  self.name = self.name.."_"..s
  return self
end

function systolicASTFunctions:disablePipelining()
  return self:process(
    function(n)
      n.pipelined=false
      return systolicAST.new(n)
    end)
end

function systolicASTFunctions:removeDelays( )
  local pipelineRegisters = {}

  local delayCache = {}
  local function getDelayed( node, delay, validbit )
    -- if node is a constant, we don't need to put it in a register.
    if node:const()~=nil then return node end
    
    delayCache[node] = delayCache[node] or {}
    delayCache[node][validbit] = delayCache[node][validbit] or {}
    if delay==0 then return node
    elseif delayCache[node][validbit][delay]==nil then
      local reg = systolic.module.reg( node.type ):instantiate(node.name.."_delay"..delay.."_valid"..validbit.name)
      table.insert( pipelineRegisters, reg )
      local d = getDelayed(node, delay-1, validbit)
      delayCache[node][validbit][delay] = reg:delay( d, validbit )
    end
    return delayCache[node][validbit][delay]
  end

  local finalOut = self:process(
    function ( n )
      if n.kind=="delay" then
        -- notice that we DO NOT add the explicit delay to the retiming number.
        -- if we did that, the other nodes would compensate and the delay
        -- we want would disappear!
        return getDelayed( n.inputs[1], n.delay, n.inputs[2] )
      end
    end)

  return finalOut, pipelineRegisters
end

function systolicASTFunctions:pipeline()
  local pipelineRegisters = {}
  local fnDelays = {}

  local delayCache = {}
  local function getDelayed( node, delay )
    -- if node is a constant, we don't need to put it in a register.
    if node:const()~=nil then return node end
    
    delayCache[node] = delayCache[node] or {}
    if delay==0 then return node
    elseif delayCache[node][delay]==nil then
      local reg = systolic.module.reg( node.type ):instantiate(node.name.."_pipeline"..delay)
      table.insert( pipelineRegisters, reg )
      local d = getDelayed(node, delay-1)
      delayCache[node][delay] = reg:delay( d )
    end
    return delayCache[node][delay]
  end

  local finalOut = self:visitEach(
    function( inpn, args )
      local n = inpn:shallowcopy()
      n.inputs={}
      for k,v in pairs(args) do n.inputs[k] = v[1] end
      n = systolicAST.new(n)
      local pipelined = n.pipelined
      n.pipelined = nil -- clear pipelined bit: we no longer need it, and it interferes with CSE

      if n.kind=="parameter" or n.kind=="constant" or n.kind=="module" or n.kind=="null" then
        return {n, 0}
      elseif n.kind=="slice" or n.kind=="cast" or n.kind=="bitSlice" then
        -- passthrough, no pipelining
        return {n, args[1][2]}
      elseif n.kind=="unary" then
        return {n, args[1][2]}
      elseif n.kind=="call" or n.kind=="tuple" or n.kind=="binop" or n.kind=="select" or n.kind=="callArbitrate" then
        -- tuples and calls happen to be almost identical

        if n.kind=="call" and n.func.input.type==types.null() then
          -- no inputs, so this gets put at time 0
          err( n.inst.module:getDelay( n.func.name )==0 or pipelined, "Error, could not disable pipelinging for function '"..n.func.name.."' on instance '"..n.inst.name.."', "..n.loc)
          return { n, n.inst.module:getDelay( n.func.name ) }
        else
          -- delay match on all inputs
          local maxd = 0
          map(args, function(a) maxd=math.max(maxd,a[2]) end)
          
          for k,v in pairs(n.inputs) do
            -- insert delays so that each input is delayed the same amount
            n.inputs[k] = getDelayed( args[k][1], maxd - args[k][2])
          end
          
          local internalDelay = 0
          if n.kind=="call" then 
            internalDelay= n.inst.module:getDelay( n.fnname ) 
            err( internalDelay==0 or pipelined, "Error, could not disable pipelining, "..n.loc)
            if n.func:isPure()==false then print("validbitPIPEDELAY",args[2][2],args[2][1].kind,args[2][1].loc) end
            -- actually, it is OK to have pipelined valid bits (eg the input to one function is the output of another, which has a delay).
            -- The problem comes up when we're trying to interact with non-coherent modules: then the timing of the callsites matters.
            -- So, enforce valid delay==0 when calling noncoherent modules?
            err( n.func:isPure() or args[2][2]==0, "Error, valid bit should not be pipelined. Call to function '"..n.func.name.."', "..n.loc )
--            err(args[1][2]==0 and args[2][2]==0,"Error, function should not be pipelined. "..n.func.name..", "..n.loc)
          elseif n.kind=="binop" or n.kind=="select" then 
            if pipelined then
              n = getDelayed(n,1)
              internalDelay = 1
            else
              internalDelay = 0
            end
          elseif n.kind=="tuple" or n.kind=="callArbitrate" then
            internalDelay = 0 -- purely wiring
          else
            assert(false)
          end

          return { n, maxd+internalDelay }
        end
      elseif n.kind=="fndefn" then
        if #n.inputs==0 then
          -- its possible for functions to do nothing
          fnDelays[n.fn.name] = 0
        else
          fnDelays[n.fn.name] = args[1][2]
        end
        return {n,0}
      else
        print(n.kind)
        assert(false)
      end
    end)

  return finalOut[1], pipelineRegisters, fnDelays
end

function systolicASTFunctions:addValid( validbit )
  assert( systolicAST.isSystolicAST(validbit) )
  return self:process(
    function(n)
      if n.kind=="call" and n.inputs[2]==nil and n.func:isPure()==false then
        -- don't add valid bit to pure functions
        assert( systolicAST.isSystolicAST(n.inputs[1]) )
        n.inputs[2] = validbit
        return systolicAST.new(n)
      elseif n.kind=="delay" then
        n.inputs[2] = validbit
        return systolicAST.new(n)
      end
    end)
end

function systolicASTFunctions:CSE()
  local seenlist = {}
  return self:process(
    function(n)
      n = systolicAST.new(n)
      seenlist[n.kind] = seenlist[n.kind] or {}
      for k,v in pairs(seenlist[n.kind]) do
        if n:eq(v) then 
          print("CSE",n.kind)
          return v
        else
--          print("CSEFAIL",n.kind)
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

  local finalOut = self:visitEach(
    function(n, args)
      local finalResult
      local argwire = map(args, function(nn) assert(type(nn[2])=="boolean");return nn[2] end)
      args = map(args, function(nn) assert(type(nn[1])=="string"); return nn[1] end)

      -- if finalResult is already a wire, we don't need to assign it to a wire at the end
      -- if wire==false, then finalResult is an expression, and can't be used multiple times
      local wire = false

      -- constants don't need to be assigned to wires if we use them multiple times (can just duplicate the text to make the verilog code easier to read)
      local const = false

      if n.kind=="call" then
        local decl
        finalResult, decl, wire = n.inst.module:instanceToVerilog( n.inst, module, n.fnname, args[1], args[2] )
        table.insert( declarations, decl )
      elseif n.kind=="callArbitrate" then
        -- inputs are stored as {data,validbit} pairs, ie {call1data,call1valid,call2data,call2valid}
        local argpairs = split(args,2)
        if #argpairs==1 then
          -- we're in arbitrate mode, but we didn't actually end up calling it multiple times. Passthrough
          finalResult = "{"..args[2]..","..args[1].."}"
        else
          for k,v in pairs(argpairs) do
            table.insert( declarations, "always @(posedge CLK) begin if("..v[2]..[[===1'bx) begin $display("valid bit can't be x! Module '%s' instance ']]..n.instance.name..[[' function ']]..n.fn..[['", INSTANCE_NAME); end end]])
          end

          local data = foldt(argpairs, function(a,b) return "(("..a[2]..")?("..a[1].."):("..b[1].."))" end )
          local v = foldt(argpairs, function(a,b) return "("..a[2].."||"..b[2]..")" end )
          
          -- do bitcount w/ the array of valid bits. Pad to 5 bits so that sum works correctly
          local cnt = foldt(argpairs, function(a,b) return {"LOL","(({4'b0,"..a[2].."})+({4'b0,"..b[2].."}))"} end )
          
          table.insert( declarations, "always @(posedge CLK) begin if("..cnt[2]..[[ > 5'd1) begin $display("error, function ']]..n.fn..[[' on instance ']]..n.instance.name..[[' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end]])
          finalResult = "{"..v..","..data.."}"
        end
      elseif n.kind=="constant" then
        local function cconst( ty, val )
          if ty:isArray() then
            return "{"..table.concat( reverse(map(range(ty:channels()), function(c) return cconst(n.type:baseType(), val[c])  end)),", " ).."}"
          else
            return valueToVerilog(val, ty)
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
          if n.module.options.onlyWire then
            table.insert( declarations,"// function: "..v.name.." pure="..tostring(v:isPure()).." ONLY WIRE" )
          else
            table.insert( declarations,"// function: "..v.name.." pure="..tostring(v:isPure()).." delay="..n.module:getDelay(v.name) )
          end
        end
        finalResult = "__ERR_NULL_MODULE"
      elseif n.kind=="bitSlice" then
        -- verilog doesn't have expressions - we can only bitslice on a wire. So coerce input into a wire.
        local inp = systolic.wireIfNecessary( argwire[1], declarations, n.inputs[1].type, n.inputs[1].name, args[1], " // wire for bitslice" )
        finalResult = inp.."["..n.high..":"..n.low.."]"
      elseif n.kind=="slice" then
        if n.inputs[1].type:isArray() then
          local inp = systolic.wireIfNecessary( argwire[1], declarations, n.inputs[1].type, n.inputs[1].name, args[1], " // wire for array index" )
          local sz = n.inputs[1].type:arrayOver():verilogBits()
          local W = (n.inputs[1].type:arrayLength())[1]

          local res = {}
          for y=n.idyHigh,n.idyLow,-1 do
            table.insert( res, inp.."["..((y*W+n.idxHigh+1)*sz-1)..":"..((y*W+n.idxLow)*sz).."]" )
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
            local inp = systolic.wireIfNecessary( argwire[1], declarations, n.inputs[1].type, n.inputs[1].name, args[1], " // wire for array index" )
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
        finalResult="{"..table.concat(reverse(args),",").."}"
      elseif n.kind=="cast" then

        local expr
        local cmt = " // cast "..tostring(n.inputs[1].type).." to "..tostring(n.type)
        
        local function dobasecast( expr, fromType, toType )
          assert(type(expr)=="string")
          
          if fromType:isUint() and (toType:isInt() or toType:isUint()) and fromType.precision <= toType.precision then
            -- casting smaller uint to larger or equal int or uint. Don't need to sign extend
            local bitdiff = toType.precision-fromType.precision
            return "{"..bitdiff.."'b0,"..expr.."}"
          elseif toType:isInt() and fromType:isInt() and toType.precision > fromType.precision then
            -- casting smaller int to larger int. must sign extend
            return "{ {"..(8*(toType:sizeof() - fromType:sizeof())).."{"..expr.."["..(fromType:sizeof()*8-1).."]}},"..expr.."["..(fromType:sizeof()*8-1)..":0]}"
          elseif (fromType:isUint() or fromType:isInt()) and (toType:isInt() or toType:isUint()) and fromType.precision>toType.precision then
            -- truncation. I don't know how this works
            return expr.."["..(toType.precision-1)..":0]"
          elseif fromType:isInt() and toType:isUint() and fromType.precision == toType.precision then
            -- int to uint with same precision. I don't know how this works
            return expr
          elseif fromType:isBits() or toType:isBits() then
            -- noop: verilog is blind to types anyway
            assert(fromType:verilogBits()==toType:verilogBits())
            return expr
          else
            print("FAIL TO CAST",fromType,"to",toType)
            assert(false)
          end
        end
        
        if n.type:isBits() or n.inputs[1].type:isBits() then
          -- noop: verilog is blind to types anyway
          assert(n.type:verilogBits()==n.inputs[1].type:verilogBits())
          expr = args[1]
        elseif n.type:isArray() and n.inputs[1].type:isTuple() then
          --err( #n.inputs[1].type.list == n.type:channels(), "tuple to array cast sizes don't match" )
          --for k,v in pairs(n.inputs[1].type.list) do
          --  err( v==n.type:arrayOver(), "NYI - tuple to array cast, all tuple types must match array type. Is "..tostring(v).." but should be "..tostring(n.type:arrayOver())..", "..n.loc)
          --end
          
          -- Theoretically, typechecker should only allow valid tuple array casts to be allowed? (always row-major order)
          err( n.type:verilogBits()==n.inputs[1].type:verilogBits(), "tuple to array cast verilog size doesn't match?")
          expr = args[1] 
        elseif n.type:isArray() and n.inputs[1].type:isArray()==false and n.inputs[1].type:isTuple()==false then
          expr = "{"..table.concat( map(range(n.type:channels()), function(n) return args[1] end),",").."}" -- broadcast
          cmt = " // broadcast "..tostring(n.inputs[1].type).." to "..tostring(n.type)
        elseif n.inputs[1].type:isArray() and n.type:isArray()==false and n.inputs[1].type:arrayOver():isBool() and (n.type:isUint() or n.type:isInt()) then
          assert(false)
          -- casting an array of bools (bitfield) to an int or uint
          expr = "}"
          for c=1,n.expr.type:channels() do
            if c>1 then expr = ","..expr end
            expr = inputs.expr[c]..expr
          end
          expr = "{"..expr
        elseif n.type:isArray() and n.inputs[1].type:isArray() and n.type:baseType()==n.inputs[1].type:baseType() then
          assert(false)
          assert(n.type:channels() == n.expr.type:channels())
          expr = inputs.expr[c]
          cmt = " // cast, array size change from "..tostring(n.expr.type).." to "..tostring(n.type)
        elseif n.inputs[1].type:isTuple() and #n.inputs[1].type.list==1 and n.inputs[1].type.list[1]==n.type then
          -- {A} to A.  Noop
          expr = args[1]
        elseif n.inputs[1].type:isArray() and n.inputs[1].type:arrayOver()==n.type and n.inputs[1].type:channels()==1 then
          -- A[1] to A. Noop
          expr = args[1]
        else
          expr = dobasecast( args[1], n.inputs[1].type, n.type )
        end
        
        finalResult = expr
      elseif n.kind=="parameter" then
        finalResult = n.name
        wire = true
      elseif n.kind=="instanceParameter" then
        table.insert(declarations, declareWire(n.type, n.name, n.variable))
        finalResult = n.name
        wire=true
      elseif n.kind=="null" then
        finalResult = ""
        wire = true
      elseif n.kind=="select" then
        finalResult = "(("..args[1]..")?("..args[2].."):("..args[3].."))"
      else
        local resTable = {}
        assert(n.type:channels()==1)
        for c=0,n.type:channels()-1 do
          local res
          local sub = "["..((c+1)*n.type:baseType():verilogBits()-1)..":"..(c*n.type:baseType():verilogBits()).."]" 
          if n.type:channels()==1 then sub="" end

          if n.kind=="binop" then

            if n.op=="<" or n.op==">" or n.op=="<=" or n.op==">=" then
              local lhs = n.inputs[1]
              local rhs = n.inputs[2]
              if n.type:baseType():isBool() and lhs.type:baseType():isInt() and rhs.type:baseType():isInt() then
                res = "($signed("..args[1]..")"..n.op.."$signed("..args[2].."))"
              elseif n.type:baseType():isBool() and lhs.type:baseType():isUint() and rhs.type:baseType():isUint() then
                res = "(("..args[1]..")"..n.op.."("..args[2].."))"
              else
                print( n.type:baseType():isBool() , n.lhs.type:baseType():isInt() , n.rhs.type:baseType():isInt(),n.type:baseType():isBool() , n.lhs.type:baseType():isUint() , n.rhs.type:baseType():isUint())
                assert(false)
              end
            elseif n.type:isBool() then
              local op = binopToVerilogBoolean[n.op]
              if type(op)~="string" then print("OP_BOOLEAN",n.op); assert(false) end
              res = "("..args[1]..op..args[2]..")"
            else
              local op = binopToVerilog[n.op]
              if type(op)~="string" then print("OP",n.op); assert(false) end
              local lhs = args[1]
              if n.inputs[1].type:baseType():isInt() then lhs = "$signed("..lhs..")" end
              local rhs = args[2]
              if n.inputs[2].type:baseType():isInt() then rhs = "$signed("..rhs..")" end
              res = "("..lhs..op..rhs..")"
            end

          elseif n.kind=="unary" then
            if n.op=="abs" then
              if n.type:baseType():isInt() then
                table.insert(resDeclarations, declareReg( n.type:baseType(), callsite..n:cname(c) ))
                table.insert(resClockedLogic, callsite..n:cname(c).." <= ("..inputs.expr[c].."["..(n.type:baseType():sizeof()*8-1).."])?(-"..inputs.expr[c].."):("..inputs.expr[c].."); //abs")
                res = callsite..n:cname(c)
              else
                --              return inputs.expr[c] -- must be unsigned
                assert(false)
              end
            elseif n.op=="-" then
              assert(n.type:baseType():isInt())
              table.insert(resDeclarations, declareReg(n.type:baseType(), callsite..n:cname(c)))
              table.insert(resClockedLogic, callsite..n:cname(c).." <= -"..inputs.expr[c].."; // unary sub")
              res = callsite..n:cname(c)
            elseif n.op=="not" then
              res = "(~"..args[1]..")"
            elseif n.op=="isX" then
              res = "("..args[1].."===1'bx)"
            else
              print(n.op)
              assert(false)
            end
          elseif n.kind=="vectorSelect" then
            res = "(("..args[1]..")?("..args[2].."):("..args[3].."))"
          else
            print(n.kind)
            assert(false)
          end
          
          table.insert( resTable, res )
        end

        finalResult = "{"..table.concat(resTable,",").."}"
      end

      -- if this value is used multiple places, store it in a variable
      if n:parentCount(self)>1 and wire==false and const==false then
        table.insert( declarations, declareWire( n.type, n.name.."USEDMULTIPLE"..n.kind, finalResult ) )
        return {n.name.."USEDMULTIPLE"..n.kind,true}
      else
        assert(type(finalResult)=="string")
        return {finalResult, wire}
      end
    end)

  declarations = map(declarations, function(i) return "  "..i end )
  local fin = table.concat(declarations,"\n").."\n"
  --fin = fin.."\nalways @(posedge CLK) begin\n"
  --fin = fin..table.concat(clockedLogic,"\n")
  --fin = fin.."end\n"
  return fin
end

function systolic.instanceParameter( variable, ty )
  -- HACK: get a verilog instance varible
  assert(type(variable)=="string")
  assert( types.isType(ty) )
  return systolicAST.new({kind="instanceParameter",variable=variable,type=ty,inputs={}})
end

function systolic.parameter( name, ty )
  assert(type(name)=="string")
  checkReserved(name)
  assert( types.isType(ty) )
  return systolicAST.new({kind="parameter",name=name,type=ty,inputs={},key={}})
end

--------------------------------------------------------------------
-- Module Definitions
--------------------------------------------------------------------
function systolic.isModule(t)
  return getmetatable(t)==userModuleMT or getmetatable(t)==fileModuleMT or getmetatable(t)==systolicModuleConstructorMT or getmetatable(t)==regModuleMT
end

systolic.module = {}
local __usedModuleNames = {}

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
  function constFunctions:instantiate( name )
    self:complete()
    return self.module:instantiate(name)
  end

  local constMT = {__index=constFunctions}
  return function(...)
    print("MODULE CONSTRUCTOR")
    local t = tab.new(...)
    t.isComplete=false
print(t,tab.configFns)
    return setmetatable(t,constMT)
  end
end


userModuleFunctions={}
setmetatable(userModuleFunctions,{__index=systolicModuleFunctions})
userModuleMT={__index=userModuleFunctions}

function userModuleFunctions:instanceToVerilogStart( instance, module )
  instance.verilogCompilerState = instance.verilogCompilerState or {}
  assert(instance.verilogCompilerState[module]==nil)
  instance.verilogCompilerState[module] = {}
end

function userModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar )
  err( instance.verilogCompilerState[module][fnname]==nil, "multiple calls to a function! function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."'")
  instance.verilogCompilerState[module][fnname]={datavar,validvar}
  local decl = nil
  local fn = self.functions[fnname]
  if fn.output~=nil and fn.output.type~=types.null() then
    decl = declareWire( fn.output.type, instance.name.."_"..fn.outputName)
  end
  return instance.name.."_"..fn.outputName, decl, true
end

function userModuleFunctions:instanceToVerilogFinalize( instance, module )
  local wires = {}
  local arglist = {}
    
  for fnname,fn in pairs(self.functions) do
    if fnname=="CE" and module.options.CE then
      -- HACK: we will wire this automatically
    else
      local canBeUndriven = fn:isPure()
      err( instance.verilogCompilerState[module][fnname]~=nil or canBeUndriven, "Undriven function "..fnname.." on instance "..instance.name.." in module "..module.name)
      
      if fn:isPure()==false then
        if self.options.onlyWire and fn.implicitValid then
          -- when in onlyWire mode, it's ok to have an undriven valid bit
        else
          local inp = instance.verilogCompilerState[module][fnname][2]
          err( type(inp)=="string", "undriven valid bit, function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."'")
          table.insert( arglist, ", ."..fn.valid.name.."("..inp..")") 
        end
      end
      
      if fn.input.type~=types.null() then
        err( instance.verilogCompilerState[module][fnname]~=nil, "No calls to fn '"..fnname.."' on instance '"..instance.name.."'?")
        local inp = instance.verilogCompilerState[module][fnname][1]
        err( type(inp)=="string", "undriven input, function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."'")
        table.insert(arglist,", ."..fn.input.name.."("..inp..")")
      end
      
      if fn.output~=nil and fn.output.type~=types.null() then
        table.insert(arglist,", ."..fn.outputName.."("..instance.name.."_"..fn.outputName..")")
      end
    end
  end

  local params = ""
  if type(instance.options.parameters)=="table" then
    for k,v in pairs(instance.options.parameters) do
      params = params..",."..k.."("..tostring(v)..")"
    end
  end

  return table.concat(wires)..self.name..[[ #(.INSTANCE_NAME("]]..instance.name..[[")]]..params..[[) ]]..instance.name.."(.CLK(CLK)"..sel(module.options.CE,",.CE(CE)","")..table.concat(arglist)..");"
end

function userModuleFunctions:lower()
  local mod = {kind="module", type=types.null(), inputs={}, module=self}

  for _,fn in pairs(self.functions) do
    local O = fn.output
    if O~=nil and self.options.onlyWire~=true then O = O:addValid(fn.valid) end
    local node = { kind="fndefn", fn=fn,type=types.null(), valid=fn.valid, inputs={O} }
    for k,pipe in pairs(fn.pipelines) do
      local P = pipe
      if self.options.onlyWire~=true then P = P:addValid(fn.valid) end
      table.insert( node.inputs, P )
    end

    node = systolicAST.new(node)
    table.insert( mod.inputs, node )
  end
  mod = systolicAST.new(mod)

  return mod
end

function userModuleFunctions:toVerilog()
  if self.verilog==nil and type(self.options.verilog)=="string" then
    self.verilog = self.options.verilog
  elseif self.verilog==nil then
    local t = {}

    table.insert(t,"module "..self.name.."(input CLK")
    for fnname,fn in pairs(self.functions) do
      if fn:isPure()==false then 
        if self.options.onlyWire and fn.implicitValid then
        else table.insert(t,", input "..fn.valid.name) end
      end
      if fn.input.type~=types.null() then table.insert(t,", "..declarePort( fn.input.type, fn.input.name, true)) end
      if fn.output~=nil and fn.output.type~=types.null() then table.insert(t,", "..declarePort( fn.output.type, fn.outputName, false ))  end
    end

    table.insert(t,");\n")
    table.insert(t,[[parameter INSTANCE_NAME="INST";]].."\n")
    if type(self.options.parameters)=="table" then
      for k,v in pairs(self.options.parameters) do
        table.insert(t,"parameter "..k.."="..v..";\n")
      end
    end

    for fnname,fn in pairs(self.functions) do
--      if fn:isPure()==false and (self.options.onlyWire and fn.implicitValid)==false then 
      if fn:isPure()==false and self.options.onlyWire~=true then

        table.insert(t, [[always @(posedge CLK) begin if(]]..fn.valid.name..[[===1'bx) begin $display("Valid bit can't be x! Module '%s' function ']]..fnname..[['", INSTANCE_NAME);  end end
]])
      end
    end

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
  return table.concat(map(self:getDependenciesLL(), function(n) return n[2] end),"")
end

function userModuleFunctions:getDelay( fnname )
  err( self.functions[fnname]~=nil, ":getDelay() error, '"..fnname.."' is not a valid function on module "..self.name)
  if self.options.onlyWire then 
    err( type(self.options.verilogDelay[fnname])=="number", "Error, onlyWire module function '"..fnname.."' is missing delay information")
    return self.options.verilogDelay[fnname] 
  end
  assert(type(self.fndelays[fnname])=="number")
  return self.fndelays[fnname]
end

function systolic.module.new( name, fns, instances, options )
  assert(type(name)=="string")
  name = name:gsub('%W','_')
  checkReserved(name)
  err( type(fns)=="table", "functions must be a table")
  map(fns, function(n) err( systolic.isFunction(n), "functions must be systolic functions" ) end )
  err( type(instances)=="table", "instances must be a table")
  map(instances, function(n) err( systolic.isInstance(n), "instances must be systolic instances" ) end )

  if options==nil then options={} end

  -- if we have a CE, add a stub function so that other functions can call it (hack)
  if options.CE then
    assert(fns.CE==nil)
    fns.CE = {name="CE",output=nil,input={name="CE",type=types.bool()},outputName="____CEOUT_SHOULDNOTAPPEAR",valid={name="____CEVALID_SHOULDNOTAPPEAR"},pipelines={},instances={}}
    fns.CE.isPure = function() return true end
  end

  if __usedModuleNames[name]~=nil then
    print("Module name ",name, "already used")
    assert(false)
  end
  __usedModuleNames[name]=1

  -- We let users choose whatever parameter names they want. Check for duplicate variable names in functions.
  local _usedPname = {}
  for k,v in pairs(fns) do
    err( _usedPname[v.outputName]==nil, "output name "..v.outputName.." used somewhere else in module" )
    _usedPname[v.outputName]="output"
    err( _usedPname[v.input.name]==nil, "input name "..v.input.name.." used somewhere else in module" )
    _usedPname[v.input.name]="input"
    if _usedPname[v.valid.name]~=nil then
      err( _usedPname[v.valid.name]==nil, "valid bit name '"..v.valid.name.."' for function '"..k.."' used somewhere else in module. Used as ".._usedPname[v.valid.name] )
    end
    _usedPname[v.valid.name]="valid for fn '"..k.."'"
  end

  local t = {name=name,kind="user",instances=instances,functions=fns, instanceMap={}, usedInstanceNames = {}, options=options,isComplete=false}
  setmetatable(t,userModuleMT)


  t.ast = t:lower()
  t.ast = t.ast:CSE()

  local delayRegisters
  t.ast, delayRegisters = t.ast:removeDelays()


print("DR",#delayRegisters)
for k,v in pairs(delayRegisters) do print("DRR",v.name) end
  t.instances = concat(t.instances, delayRegisters)

  map( t.instances, function(i) t.instanceMap[i]=1; err(t.usedInstanceNames[i.name]==nil,"Instance name '"..i.name.."' used multiple times!"); t.usedInstanceNames[i.name]=1 end )

  -- check that the instances refered to by this module are actually in the module
  t.ast:checkInstances( t.instanceMap )
  
  if options.onlyWire==nil or options.onlyWire==false then
    local pipelineRegisters
    t.ast, pipelineRegisters, t.fndelays = t.ast:pipeline()
    t.ast = t.ast:CSE() -- after pipeline bits are cleared, some more stuff can be CSE'd
    map( pipelineRegisters, function(p) table.insert( t.instances, p ) end )
  end

  return t
end

----------------------------
regModuleFunctions={}
setmetatable(regModuleFunctions,{__index=systolicModuleFunctions})
regModuleMT={__index=regModuleFunctions}

function regModuleFunctions:instanceToVerilogStart( instance, module )
  instance.verilogCompilerState = instance.verilogCompilerState or {}
  assert(instance.verilogCompilerState[module]==nil)
  instance.verilogCompilerState[module] = false
end


function regModuleFunctions:instanceToVerilog( instance, module, fnname, inputVar, validVar )
  local decl = nil
  if instance.verilogCompilerState[module]==false then
    decl = declareReg(self.type, instance.name, self.initial)
    instance.verilogCompilerState[module]=true
  end

  if fnname=="delay" or fnname=="set" then
    err( #instance.callsites[fnname]==1, "Error, multiple ("..(#instance.callsites[fnname])..") calls to '"..fnname.."' on instance '"..instance.name.."'")

    if decl==nil then decl="" end
    if module.options.CE or fnname=="set" then
      -- some callsites (e.g. pipeline registers) don't provide a valid bit, so that's ok
      decl = decl.."  always @ (posedge CLK) begin if ("..sel(validVar~=nil,validVar,"")..sel(validVar~=nil and module.options.CE," && ","")..sel(module.options.CE,"CE","")..") begin "..instance.name.." <= "..inputVar.."; end end"
    else
      decl = decl.."  always @ (posedge CLK) begin "..instance.name.." <= "..inputVar.."; end"
    end
    local name = instance.name
    if fnname=="set" then name = "_____REG_SET" end
    return name, decl, true
  elseif fnname=="get" then
    return instance.name, decl, true
  else
    print("regModuleFunctions:instanceToVerilog",fnname)
    assert(false)
  end
end

function regModuleFunctions:getDependenciesLL() return {} end
function regModuleFunctions:toVerilog() return "" end
function regModuleFunctions:getDelay( fnname )
  return 0
end

function systolic.module.reg( ty, initial )
  err(types.isType(ty),"type must be a type")
  local t = {kind="reg",initial=initial,type=ty,options={lateInstantiation=true}}
  t.functions={}
  t.functions.delay={name="delay", output={type=ty}, input={name="DELAY_INPUT",type=ty},outputName="DELAY_OUTPUT"}
  t.functions.delay.isPure = function() return false end
  t.functions.set={name="set", output={type=types.null()}, input={name="SET_INPUT",type=ty},outputName="SET_OUTPUT"}
  t.functions.set.isPure = function() return false end
  t.functions.get={name="get", output={type=ty}, input={name="GET_INPUT",type=types.null()},outputName="GET_OUTPUT"}
  t.functions.get.isPure = function() return true end
  return setmetatable(t,regModuleMT)
end

systolic.module.regConstructor = moduleConstructor{
new=function(ty) return {type=ty} end,
complete=function(self) return systolic.module.reg( self.type, self.init) end,
configFns={setInit=function(self,I) assert(type(I)==self.type:toLuaType()); self.init=I; return self end}
}

-------------------
systolic.module.regBy = memoize(function( ty, setby, CE, init )
  assert( types.isType(ty) )
  assert( systolic.isModule(setby) )
  assert( setby:getDelay( "process" ) == 0 )
  assert( CE==nil or type(CE)=="boolean" )
  assert( init==nil or type(init)==ty:toLuaType() )

  local R = systolic.module.reg( ty, init ):instantiate("R",{arbitrate="valid"})
  local inner = setby:instantiate("regby_inner")
  local fns = {}
  fns.get = systolic.lambda("get", systolic.parameter("getinp",types.null()), R:get(), "GET_OUTPUT" )

  -- check setby type
  --err(#setby.functions==1, "regBy setby module should only have process function")
  assert(setby.functions.process:isPure())
  local setbytype = setby.functions.process.input.type
  assert(setbytype:isTuple())
  local setbyTypeA = setbytype.list[1]
  local setbyTypeB = setbytype.list[2]
  assert(setbyTypeA==ty)

  local sbinp = systolic.parameter("setby_inp",setbyTypeB)
  local setbyvalid = systolic.parameter("setby_valid",types.bool())
  local setbyout = inner:process(systolic.tuple{R:get(),sbinp})
  fns.setBy = systolic.lambda("setby", sbinp, setbyout, "SETBY_OUTPUT",{R:set(setbyout,setbyvalid)}, setbyvalid )

  local sinp = systolic.parameter("set_inp",ty)
  local setvalid = systolic.parameter("set_valid",types.bool())
  fns.set = systolic.lambda("set", sinp, R:set(sinp,setvalid), "SET_OUTPUT",{}, setvalid )
--  fns.set = systolic.lambda("set", sinp, sinp, "SET_OUTPUT",{}, setvalid )

  print("make regby")
  local M = systolic.module.new( "RegBy_"..setby.name.."_CE"..tostring(CE).."_init"..tostring(init), fns, {R,inner}, {onlyWire=true,verilogDelay={get=0,set=0,setBy=0},CE=CE} )
  assert(systolic.isModule(M))
  return M
end)


systolic.module.regByConstructor = moduleConstructor{
new=function( ty, setby )
  assert( types.isType(ty) )
  assert( systolic.isModule(setby) )
  assert( setby:getDelay( "process" ) == 0 )
  return {type=ty, setby=setby}
end,
complete=function(self) 
  print("REGBYCONST COMPLERE")
local M= systolic.module.regBy( self.type, self.setby, self.CE, self.init ) 
map(M,print)
print("RGBY",systolic.isModule(M),M,keycount(M),__memoizedNilHack)
return M
end,
configFns={includeCE=function(self) self.CE=true; return self end, setInit=function(self,I) assert(type(I)==self.type:toLuaType()); self.init=I; return self end}
}

-------------------
ram128ModuleFunctions={}
setmetatable(ram128ModuleFunctions,{__index=systolicModuleFunctions})
ram128ModuleMT={__index=ram128ModuleFunctions}
local __ram128 = {kind="ram128"}
setmetatable(__ram128,ram128ModuleMT)

function ram128ModuleFunctions:instanceToVerilog( instance )
    return [[ wire ]]..instance.name..[[_WE;
wire ]]..instance.name..[[_D;
wire ]]..instance.name..[[_writeOut;
wire ]]..instance.name..[[_readOut;
wire [6:0] ]]..instance.name..[[_writeAddr;
wire [6:0] ]]..instance.name..[[_readAddr;
RAM128X1D ]]..instance.name..[[  (
  .WCLK(CLK),
  .D(]]..instance.name..[[_D),
  .WE(]]..instance.name..[[_WE),
  .SPO(]]..instance.name..[[_writeOut),
  .DPO(]]..instance.name..[[_readOut),
  .A(]]..instance.name..[[_writeAddr),
  .DPRA(]]..instance.name..[[_readAddr));
]]
end

function systolic.module.ram128() return __ram128 end

--------------------
bramModuleFunctions={}
setmetatable(bramModuleFunctions,{__index=systolicModuleFunctions})
bramModuleMT={__index=bramModuleFunctions}

function bramModuleFunctions:instanceToVerilogStart( instance, module )
  instance.verilogCompilerState = instance.verilogCompilerState or {}
  assert(instance.verilogCompilerState[module]==nil)
  instance.verilogCompilerState[module] = {}
end

function bramModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar )
  instance.verilogCompilerState[module][fnname]={datavar,validvar}
  local fn = self.functions[fnname]
  local decl = declareWire( types.bits( self.outputBits ), instance.name.."_"..fn.outputName)
  return instance.name.."_"..fn.outputName, decl, true
end


function bramModuleFunctions:getDependenciesLL() return {} end
function bramModuleFunctions:toVerilog() return "" end
function bramModuleFunctions:getDelay( fnname ) 
  if fnname=="writeAndReturnOriginal" then return 1
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
  if self.writeAndReturnOriginal then
    assert(keycount(VCS)==1)
    -- we only used 1 port

    -- we only use the 18 kbit wide BRAM here, b/c AFAIK using the 36 kbit BRAM doesn't provide a benefit, so there's no reason to special case that

--    err(self.inputBits==32 or self.outputBits==32, "BRAM2KSDP requires one of the ports to be 32 bit")

    local width
    if self.inputBits==8 then
      width = 9
    elseif self.inputBits==16 then
      width = 18
    elseif self.inputBits==32 then
      width = 36
    else
      error("unsupported BRAM2KSDP bitwidth,"..self.inputType:verilogBits() )
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
          assert( value < 256 )
          table.insert(S,1,string.format("%02x",value)) 
        end
        initS = initS..".INIT_"..string.format("%02X",block).."(256'h"..table.concat(S,"").."),\n"
      end
    end

    local addrbits = math.log((2048*8)/self.inputBits)/math.log(2)

    local valid = VCS.writeAndReturnOriginal[2]
    if self.options.CE then valid=valid.." && CE" end

    local conf={name=instance.name}
    conf.A={chunk=self.inputBits/8,
           DI = instance.name.."_INPUT["..(addrbits+self.inputBits-1)..":"..addrbits.."]",
           DO = instance.name.."_SET_AND_RETURN_ORIG_OUTPUT",
           ADDR = instance.name.."_INPUT["..(addrbits-1)..":0]",
           CLK = "CLK",
           EN="CE",
           WE = valid,
           readFirst = true}
    conf.B={chunk=self.inputBits/8,
           DI = instance.name.."_DI_B",
           DO = instance.name.."_DO_B",
           ADDR = instance.name.."_addr_B",
           CLK = "CLK",
           EN="CE",
           WE = "1'd0",
           readFirst = true}

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

function systolic.module.bram2KSDP( writeAndReturnOriginal, inputBits, outputBits, options )
  err( type(inputBits)=="number", "inputBits must be a number")
  err( type(outputBits)=="number", "outputBits must be a number")
  err( options==nil or type(options)=="table", "options must be table")

  if options.init~=nil then
    assert(type(options.init)=="table")
    err(#options.init==2048, "init table has size "..(#options.init))
  end

  local t = {kind="bram2KSDP",functions={}, inputBits = inputBits, outputBits = outputBits, writeAndReturnOriginal=writeAndReturnOriginal, options=options}
  local addrbits = math.log((2048*8)/inputBits)/math.log(2)
  if writeAndReturnOriginal then
    err( inputBits==outputBits, "with writeAndReturnOriginal, inputBits and outputBits must match")
    t.functions.writeAndReturnOriginal = {name="writeAndReturnOriginal", input={name="SET_AND_RETURN_ORIG",type=types.tuple{types.uint(addrbits),types.bits(inputBits)}},outputName="SET_AND_RETURN_ORIG_OUTPUT", output={type=types.bits(outputBits)}}
    t.functions.writeAndReturnOriginal.isPure = function() return false end
  else
    -- NYI
    assert(false)
  end

  return setmetatable( t, bram2KSDPModuleMT )
end

----------------
-- supports any size/bandwidth by instantiating multiple BRAMs
function systolic.module.bramSDP( writeAndReturnOriginal, sizeInBytes, inputBits, outputBits, options)
  err( type(sizeInBytes)=="number", "sizeInBytes must be a number")
  err( type(inputBits)=="number", "inputBits must be a number")
  err( type(outputBits)=="number", "outputBits must be a number")
  err( isPowerOf2(sizeInBytes), "Size in Bytes must be power of 2, but is "..sizeInBytes)

  local bwcount = math.ceil(inputBits/32)
  local szcount = math.ceil(sizeInBytes/(2*1024))
  local count = math.max(bwcount,szcount)

  assert(szcount==1)

  if options.init~=nil then
    err( #options.init==sizeInBytes, "init field has size "..(#options.init).." but should have size "..sizeInBytes )
    while #options.init < 2048 do
      table.insert(options.init,0)
    end
  end

  if writeAndReturnOriginal then
    err( inputBits==outputBits, "with writeAndReturnOriginal, inputBits and outputBits must match")
    local addrbits = math.log((sizeInBytes*8)/inputBits)/math.log(2)
    local mod = systolic.moduleConstructor( "bramSDP_size"..sizeInBytes.."_bw"..inputBits, options )
    local sinp = systolic.parameter("inp",types.tuple{types.uint(addrbits),types.bits(inputBits)})
    local inpAddr = systolic.index(sinp,0)
    local inpData = systolic.index(sinp,1)
    
    local eachSize = math.min( 32, inputBits )
    local eachAddrbits = math.log((2048*8)/eachSize)/math.log(2)

    local out = {}
    for bw=0,bwcount-1 do
      local m =  mod:add( systolic.module.bram2KSDP( writeAndReturnOriginal, eachSize, eachSize, options ):instantiate("bram_"..bw) )
      local inp = systolic.bitSlice( inpData, bw*eachSize, (bw+1)*eachSize-1 )
      table.insert( out, m:writeAndReturnOriginal( systolic.tuple{ systolic.cast(inpAddr,types.uint(eachAddrbits)),inp} ) )
    end
    mod:addFunction( systolic.lambda("writeAndReturnOriginal", sinp, systolic.cast(systolic.tuple(out),types.bits(outputBits)), "WARO_OUT") )

    return mod
  else
    assert(false)
  end
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

function fileModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar )
  instance.verilogCompilerState[module][fnname]={datavar,validvar}
  local decl = nil
  local fn = self.functions[fnname]
  if fnname=="read" then
    decl = declareReg( fn.output.type, instance.name.."_"..fn.outputName)
  end
  return instance.name.."_"..fn.outputName, decl, true
end


function fileModuleFunctions:instanceToVerilogFinalize( instance, module )
--  return "FILELOL"
  if instance.callsites.read~=nil and instance.callsites.write==nil then
    local assn = ""
    for i=0,self.type:sizeof()-1 do
      assn = assn .. instance.name.."_out["..((i+1)*8-1)..":"..(i*8).."] <= $fgetc("..instance.name.."_file); "
    end

    local RST = ""
    if instance.verilogCompilerState[module].reset~=nil then
      RST = "if ("..instance.verilogCompilerState[module].reset[2]..") begin r=$fseek("..instance.name.."_file,0,0); end"
    end

--  reg []]..(self.type:sizeof()*8-1)..[[:0] ]]..instance.name..[[_out;

    return [[integer ]]..instance.name..[[_file,r;
  initial begin ]]..instance.name..[[_file = $fopen("]]..self.filename..[[","r"); end
  always @ (posedge CLK) begin 
    if (]]..instance.verilogCompilerState[module].read[2]..sel(module.options.CE," && CE","")..[[) begin ]]..assn..[[ end 
    ]]..RST..[[
  end
]]
  elseif instance.callsites.read==nil and instance.callsites.write~=nil then
    local assn = ""

    local debug = ""
    --debug = [[always @(posedge CLK) begin $display("write v %d ce %d value %h",]]..instance.verilogCompilerState[module].write[2]..[[,CE,]]..instance.verilogCompilerState[module].write[1]..[[); end]]

    for i=0,self.type:sizeof()-1 do
      assn = assn .. "$fwrite("..instance.name..[[_file, "%c", ]]..instance.verilogCompilerState[module].write[1].."["..((i+1)*8-1)..":"..(i*8).."] ); "
    end

    local RST = ""
    if instance.verilogCompilerState[module].reset~=nil then
      RST = "if ("..instance.verilogCompilerState[module].reset[2]..[[) begin r=$fseek(]]..instance.name..[[_file,0,0); end]]
    end
    return debug..[[integer ]]..instance.name..[[_file,r;
  initial begin ]]..instance.name..[[_file = $fopen("]]..self.filename..[[","wb"); end
  always @ (posedge CLK) begin 
    if (]]..instance.verilogCompilerState[module].write[2]..sel(module.options.CE," && CE","")..[[) begin ]]..assn..[[ end 
    ]]..RST..[[
  end
]]
  else
    assert(false)
  end
end

function fileModuleFunctions:toVerilog() return "" end
function fileModuleFunctions:getDependenciesLL() return {} end
function fileModuleFunctions:getDelay(fnname)
  if fnname=="write" then
    return 0
  elseif fnname=="read" then
    return 1
  elseif fnname=="reset" then
    return 0
  else
    print(fnname)
    assert(false)
  end
end

function systolic.module.file( filename, ty)
  local res = {kind="file",filename=filename, type=ty, options={}}
  res.functions={}
  res.functions.read={name="read",output={type=ty},input={name="FREAD_INPUT",type=types.null()},outputName="out",valid={name="read_valid"}}
  res.functions.read.isPure = function() return false end
  res.functions.write={name="write",output={type=types.null()},input={name="input",type=ty},outputName="out",valid={name="write_valid"}}
  res.functions.write.isPure = function() return false end
  res.functions.reset = {name="reset",output={type=types.null()},input={name="input",type=types.null()},outputName="out",valid={name="reset_valid"}}
  res.functions.reset.isPure = function() return false end

  return setmetatable(res, fileModuleMT)
end

--------------------------------------------------------------------
printModuleFunctions={}
setmetatable(printModuleFunctions,{__index=systolicModuleFunctions})
printModuleMT={__index=printModuleFunctions}

function printModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar )

  local datalist = ""
  if self.type:isTuple() then
    local bit = 0
    for k,v in pairs(self.type.list) do
      if k~=1 then datalist=datalist.."," end
      datalist = datalist..instance.name.."["..(bit+v:verilogBits()-1)..":"..bit.."]"
      bit = bit + v:verilogBits()
    end
  else
    datalist = datavar
  end

  local validS = ""
  local validSS = ""
  if validvar~=nil then validS,validSS="valid %d",validvar.."," end
  if module.options.CE then validS = validS.." CE %d"; validSS = validSS.."CE," end

  local decl = [[wire []]..(self.type:verilogBits()-1)..":0] "..instance.name..[[;
assign ]]..instance.name..[[ = ]]..datavar..[[;
always @(posedge CLK) begin $display("%s(]]..validS..[[): ]]..self.str..[[",INSTANCE_NAME,]]..validSS..datalist..[[); end]]
  return "___NULL_PRINT_OUT", decl, true
end

function printModuleFunctions:toVerilog() return "" end
function printModuleFunctions:getDependenciesLL() return {} end
function printModuleFunctions:getDelay(fnname) return 0 end

function systolic.module.print( ty, str )
  err( types.isType(ty), "type input to print module should be type")
  err( type(str)=="string", "string input to print module should be string")
  local res = {kind="print",str=str, type=ty, options={}}
  res.functions={}
  res.functions.process={name="process",output={type=types.null()},input={name="PRINT_INPUT",type=ty},outputName="out",valid={name="process_valid"}}
  res.functions.process.isPure = function() return false end
  return setmetatable(res, printModuleMT)
end

--------------------------------------------------------------------
assertModuleFunctions={}
setmetatable(assertModuleFunctions,{__index=systolicModuleFunctions})
assertModuleMT={__index=assertModuleFunctions}

function assertModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar )
  local CES = ""
  if self.options.CE then CES=" && CE==1'b1" end
  local finish = "$finish(); "
  if self.options.exit==false then finish="" end
  local decl = [[always @(posedge CLK) begin if(]]..datavar..[[ == 1'b0 && ]]..validvar..[[==1'b1]]..CES..[[) begin $display("%s: ]]..self.str..[[",INSTANCE_NAME);]]..finish..[[ end end]]
  return "___NULL_ASSERT_OUT", decl, true
end

function assertModuleFunctions:toVerilog() return "" end
function assertModuleFunctions:getDependenciesLL() return {} end
function assertModuleFunctions:getDelay(fnname) return 0 end

function systolic.module.assert( str, options )
  err( type(str)=="string", "string input to print module should be string")

  if options==nil then options={} end
  local res = {kind="assert",str=str,  options=options}
  res.functions={}
  res.functions.process={name="process",output={type=types.null()},input={name="ASSERT_INPUT",type=types.bool()},outputName="out",valid={name="process_valid"}}
  res.functions.process.isPure = function() return false end
  return setmetatable(res, assertModuleMT)
end

--------------------------------------------------------------------
-- Syntax sugar for incrementally defining a function
--------------------------------------------------------------------

systolicFunctionConstructor = {}
systolicFunctionConstructorMT={__index=systolicFunctionConstructor}

function systolic.lambdaConstructor( name, input, valid )
  err( systolicAST.isSystolicAST(input), "input must be a systolic AST" )
  if valid==nil then valid = systolic.parameter( name.."_valid", types.bool() ) end
  local t = {name=name, input=input, isComplete=false }
end

function systolicFunctionConstructor:complete()
  if self.isComplete==false then
    if self.returnValue==nil then self.returnValue={type=types.null()} end
    self.isComplete=true
  end
end

function systolicFunctionConstructor:output( expr )
  err( systolicAST.isSystolicAST(expr), "output must be a systolic AST" )
  self.returnValue = expr
end

function systolicFunctionConstructor:output( expr )

end

--------------------------------------------------------------------
-- Syntax sugar for incrementally defining a module
--------------------------------------------------------------------

systolicModuleConstructor = {}
systolicModuleConstructorMT={__index=systolicModuleConstructor}

function systolic.moduleConstructor( name, options )
  assert(type(name)=="string")
  checkReserved(name)
  if options==nil then options={} end

  local t = { name=name, options=options, functions={}, instances={}, isComplete=false, usedInstanceNames={}, instanceMap={} }

  return setmetatable( t, systolicModuleConstructorMT )
end

function systolicModuleConstructor:add( inst )
  err( systolic.isInstance(inst), "must be an instance" )
  assert( inst.kind=="module" or inst.kind=="reg" or inst.kind=="ram128" or inst.kind=="bram")

  checkReserved(inst.name)
  if self.usedInstanceNames[inst.name]~=nil then
    print("Error, instance name "..inst.name.." already in use")
    assert(false)
  end

  self.instanceMap[inst] = 1
  self.usedInstanceNames[inst.name] = 1

  table.insert(self.instances,inst)
  return inst
end


function systolicModuleConstructor:addFunction( fn )
  err( self.isComplete==false, "module is already complete")
  err( systolic.isFunction(fn), "input must be a systolic function")

  if self.usedInstanceNames[fn.name]~=nil then
    print("Error, function name "..fn.name.." already in use")
    assert(false)
  end

  self.functions[fn.name]=fn
  fn.module = self
  return fn
end

function systolicModuleConstructor:onlyWire(v) self.options.onlyWire=v; return self end
function systolicModuleConstructor:parameters(p) self.options.parameters=p; return self end

function systolicModuleConstructor:complete()
  if self.isComplete==false then
    self.module = systolic.module.new( self.name, self.functions, self.instances, self.options )
    self.isComplete = true
  end
end

function systolicModuleConstructor:getDelay( fnname )
  self:complete()
  return self.module:getDelay( fnname )
end

function systolicModuleConstructor:toVerilog()
  self:complete()
  return self.module:toVerilog()
end

function systolicModuleConstructor:instantiate( name, options )
  self:complete()
  return self.module:instantiate( name, options )
end


return systolic