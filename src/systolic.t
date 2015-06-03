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

local __usedNameCnt = 0
function systolicAST.new(tab)
  assert(type(tab)=="table")
  if tab.scaleN1==nil then tab.scaleN1=0 end
  if tab.scaleD1==nil then tab.scaleD1=0 end
  if tab.scaleN2==nil then tab.scaleN2=0 end
  if tab.scaleD2==nil then tab.scaleD2=0 end
  assert(type(tab.inputs)=="table")
  assert(#tab.inputs==keycount(tab.inputs))
  if tab.name==nil then tab.name="unnamed"..__usedNameCnt; __usedNameCnt=__usedNameCnt+1 end
  assert(types.isType(tab.type))
  if tab.pipelined==nil then tab.pipelined=true end
  IR.new(tab)
  return setmetatable(tab,systolicASTMT)
end


local function getloc()
  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline
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

local binopToVerilogBoolean={["=="]="==",["and"]="&&",["~="]="!=",["or"]="||"}

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

function systolic.declareWire(ty, name, str, comment)
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
    if value then
      return "1'd1"
    else
      return "1'd0"
    end
  else
    assert(false)
  end
end

function systolicModuleFunctions:instantiate(name)
  err( type(name)=="string", "instantiation name must be a string")
  return systolicInstance.new({kind="module",module=self,name=name,callsites={}})
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
  expr = convert(expr)
  return typecheck(darkroom.ast.new({kind="unary",op=op,expr=expr}):copyMetadataFrom(expr))
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
        table.insert(tab.callsites[fn.name],1)

        err( inp.type==fn.input.type, "Error, input type to function incorrect. Is "..tostring(inp.type).." but should be "..tostring(fn.input.type) )

        local otype = types.null()
        if fn.output~=nil then otype = fn.output.type end

        local t = { kind="call", inst=self, func=fn, type=otype, loc=getloc(), inputs={inp,valid} }
        
        return systolicAST.new(t)
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
  __newindex = function(table, key, value)
                    darkroom.error("Attempt to modify systolic AST node")
                  end}

function systolicASTFunctions:init()
  setmetatable(self,nil)
  systolicAST.new(self)
end

-- ops
function systolic.index( expr, idx, idy )
  assert(systolicAST.isSystolicAST(expr))
  err( type(idx)=="number", "idx should be a number" )
  if idy==nil then idy=0 end
  return typecheck({kind="index", idx=idx, idy=idy, inputs={expr}, loc=getloc()})
end

function systolic.cast( expr, ty )
  err( systolicAST.isSystolicAST(expr), "input to cast must be a systolic ast")
  err( types.isType(ty), "input to cast must be a type")
  return typecheck({kind="cast",inputs={expr},type=ty,loc=getloc()})
end

function systolic.constant( v, ty )
  err( types.isType(ty), "constant type must be a type")

  if ty:isArray() then
    err( type(v)=="table", "if type is an array, v must be a table")
    map( v,function(n) err(type(n)=="number", "array element must be a number") end )
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
function systolic.rshift(lhs, rhs) return binop(lhs,rhs,">>") end
function systolic.neg(expr) return unary(expr,"-") end

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
        return n.func:isPure()
      elseif n.kind=="parameter" then
        return n.key~=validbit.key -- explicitly used valid bit
      elseif n.kind=="fndefn" then
          assert(false) -- we shouldn't call isPure on lowered ASTs
      else
        return foldl( andop, true, inputs )
      end
    end)
end

function systolicASTFunctions:disablePipelining()
  return self:process(
    function(n)
      n.pipelined=false
      return systolicAST.new(n)
    end)
end

function systolicASTFunctions:pipeline()
  local pipelineRegisters = {}
  local fnDelays = {}

  local delayCache = {}
  local function getDelayed( node, delay )
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

      if n.kind=="parameter" or n.kind=="constant" or n.kind=="module" or n.kind=="null" then
        return {n, 0}
      elseif n.kind=="index" or n.kind=="cast" then
        -- passthrough, no pipelining
        return {n, args[1][2]}
      elseif n.kind=="call" or n.kind=="tuple" or n.kind=="binop" or n.kind=="select" then
        -- tuples and calls happen to be almost identical

        if n.kind=="call" and n.func.input.type==types.null() then
          -- no inputs, so this gets put at time 0
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
            internalDelay= n.inst.module:getDelay( n.func.name ) 
            err( internalDelay==0 or n.pipelined, "Error, could not disable pipelining, "..n.loc)
          elseif n.kind=="binop" or n.kind=="select" then 
            if n.pipelined then
              n = getDelayed(n,1)
              internalDelay = 1
            else
              internalDelay = 0
            end
          elseif n.kind=="tuple" then
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
      end
    end)
end

function systolicASTFunctions:toVerilog( module )
  assert( systolic.isModule(module))
  --local clockedLogic = {}
  local declarations = {}

  local finalOut = self:visitEach(
    function(n, args)
      local finalResult
      -- if finalResult is already a wire, we don't need to assign it to a wire at the end
      -- if wire==false, then finalResult is an expression, and can't be used multiple times
      local wire = false

      if n.kind=="call" then
--        if n.inst.module.options.lateInstantiation then
          local decl
          finalResult, decl, wire = n.inst.module:instanceToVerilog( n.inst, module, n.func.name, args[1], args[2] )
          table.insert( declarations, decl )
--[=[        else
          if n.func:isPure()==false then
            table.insert(declarations, "assign "..n.inst.name.."_"..n.func.valid.name.." = "..args[2].."; // call valid")
          end
          
          if n.func.input.type~=types.null() then table.insert(declarations, "assign "..n.inst.name.."_"..n.func.input.name.." = "..args[1].."; // call input") end
          
          if n.func.output~=nil then
            finalResult =  n.inst.name.."_"..n.func.outputName
            wire = true
          else
            finalResult =  "__NILVALUE_ERROR"
          end     
      end]=]
      elseif n.kind=="constant" then
        local function cconst( ty, val )
          if ty:isArray() then
            return "{"..table.concat( map(range(ty:channels()), function(c) return cconst(n.type:baseType(), val[c])  end) ).."}"
          else
            return valueToVerilog(val, ty)
          end
        end
        finalResult = "("..cconst(n.type,n.value)..")"
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
      elseif n.kind=="index" then
        if n.inputs[1].type:isArray() then
          local flatIdx = (n.inputs[1].type:arrayLength())[1]*n.idy+n.idx
          local sz = n.inputs[1].type:arrayOver():verilogBits()
          finalResult = args[1].."["..((flatIdx+1)*sz-1)..":"..(flatIdx*sz).."]"
        elseif n.inputs[1].type:isUint() or n.inputs[1].type:isInt() then
          table.insert( resDeclarations, declareWire( n.type:baseType(), n:cname(c), "", " // index result" ))
          table.insert( resDeclarations, "assign "..n:cname(c).." = "..inputs["expr"][c].."["..n.index1.constLow_1.."]; // index")
          finalResult = n:cname(c)
        elseif n.inputs[1].type:isTuple() then
          local lowbit = 0
          for k,v in pairs(n.inputs[1].type.list) do if k-1<n.idx then lowbit = lowbit + v:verilogBits() end end
          local ty = n.inputs[1].type.list[n.idx+1]
          if n.inputs[1].type:verilogBits()==ty:verilogBits() then
            finalResult = args[1] -- no index necessary
          elseif ty:verilogBits()>1 then
            finalResult = args[1].."["..(lowbit+ty:verilogBits()-1)..":"..lowbit.."]"
          elseif ty:verilogBits()==1 then
            finalResult = args[1].."["..lowbit.."]"
          else
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
              return expr
            elseif toType:isInt() and fromType:isInt() and toType.precision > fromType.precision then
              -- casting smaller int to larger int. must sign extend
              return "{ {"..(8*(toType:sizeof() - fromType:sizeof())).."{"..expr.."["..(fromType:sizeof()*8-1).."]}},"..expr.."["..(fromType:sizeof()*8-1)..":0]}"
            elseif (fromType:isUint() or fromType:isInt()) and (toType:isInt() or toType:isUint()) and fromType.precision>toType.precision then
              -- truncation. I don't know how this works
              return expr
            elseif fromType:isInt() and toType:isUint() and fromType.precision == toType.precision then
              -- int to uint with same precision. I don't know how this works
              return expr
            else
              print("FAIL TO CAST",fromType,"to",toType)
              assert(false)
            end
          end

          if n.type:isArray() and n.inputs[1].type:isTuple()==true then
            err( #n.inputs[1].type.list == n.type:channels(), "tuple to array cast sizes don't match" )
            for k,v in pairs(n.inputs[1].type.list) do
              err( v==n.type:arrayOver(), "NYI - tuple to array cast, all tuple types must match array type. Is "..tostring(v).." but should be "..tostring(n.type:arrayOver())..", "..n.loc)
            end
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
          elseif n.type:isArray() and n.inputs[1].type:isArray()  then
            assert(false)
            assert(n.type:arrayLength() == n.expr.type:arrayLength())
            -- same shape arrays, different base types
            expr = dobasecast( inputs.expr[c], n.expr.type:baseType(), n.type:baseType() )
          else
            expr = dobasecast( args[1], n.inputs[1].type, n.type )
          end

          finalResult = expr
      elseif n.kind=="parameter" then
        finalResult = n.name
        wire = true
      elseif n.kind=="null" then
        finalResult = ""
        wire = true
      else
        local resTable = {}
        for c=0,n.type:channels()-1 do
          local res
          local sub = "["..((c+1)*n.type:baseType():verilogBits()-1)..":"..(c*n.type:baseType():verilogBits()).."]" 

          if n.kind=="binop" then

            if n.op=="<" or n.op==">" or n.op=="<=" or n.op==">=" then
              if n.type:baseType():isBool() and n.lhs.type:baseType():isInt() and n.rhs.type:baseType():isInt() then
                res = "($signed("..args[1]..sub..")"..n.op.."$signed("..inputs.rhs[c]..sub.."));"
              elseif n.type:baseType():isBool() and n.lhs.type:baseType():isUint() and n.rhs.type:baseType():isUint() then
                res = "(("..args[1]..")"..n.op.."("..inputs.rhs[c].."));"
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
          addInput("expr")
          getInputs()
          thisDelay = 1

          if n.op=="abs" then
            if n.type:baseType():isInt() then
              table.insert(resDeclarations, declareReg( n.type:baseType(), callsite..n:cname(c) ))
              table.insert(resClockedLogic, callsite..n:cname(c).." <= ("..inputs.expr[c].."["..(n.type:baseType():sizeof()*8-1).."])?(-"..inputs.expr[c].."):("..inputs.expr[c].."); //abs")
              res = callsite..n:cname(c)
            else
              return inputs.expr[c] -- must be unsigned
            end
          elseif n.op=="-" then
            assert(n.type:baseType():isInt())
            table.insert(resDeclarations, declareReg(n.type:baseType(), callsite..n:cname(c)))
            table.insert(resClockedLogic, callsite..n:cname(c).." <= -"..inputs.expr[c].."; // unary sub")
            res = callsite..n:cname(c)
          else
            print(n.op)
            assert(false)
          end
        elseif n.kind=="select" or n.kind=="vectorSelect" then
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
      if n:parentCount(self)>1 and wire==false then
        table.insert( declarations, declareWire( n.type, n.name.."USEDMULTIPLE", finalResult ) )
        return n.name.."USEDMULTIPLE"
      else
        return finalResult
      end
    end)

  declarations = map(declarations, function(i) return "  "..i end )
  local fin = table.concat(declarations,"\n").."\n"
  --fin = fin.."\nalways @(posedge CLK) begin\n"
  --fin = fin..table.concat(clockedLogic,"\n")
  --fin = fin.."end\n"
  return fin
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
  return getmetatable(t)==userModuleMT or getmetatable(t)==fileModuleMT or getmetatable(t)==systolicModuleConstructorMT
end

systolic.module = {}
local __usedModuleNames = {}

userModuleFunctions={}
setmetatable(userModuleFunctions,{__index=systolicModuleFunctions})
userModuleMT={__index=userModuleFunctions}

function userModuleFunctions:instanceToVerilogStart( instance, module )
  instance.verilogCompilerState = instance.verilogCompilerState or {}
  assert(instance.verilogCompilerState[module]==nil)
  instance.verilogCompilerState[module] = {}
end

function userModuleFunctions:instanceToVerilog( instance, module, fnname, datavar, validvar )
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
      err( instance.verilogCompilerState[module][fnname]~=nil, "Undriven function "..fnname.." on instance "..instance.name.." in module "..module.name)
      
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
        local inp = instance.verilogCompilerState[module][fnname][1]
        err( type(inp)=="string", "undriven input, function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."'")
        table.insert(arglist,", ."..fn.input.name.."("..inp..")")
      end
      
      if fn.output~=nil and fn.output.type~=types.null() then
        table.insert(arglist,", ."..fn.outputName.."("..instance.name.."_"..fn.outputName..")")
      end
    end
  end

  return table.concat(wires)..self.name..[[ #(.INSTANCE_NAME("]]..instance.name..[[")) ]]..instance.name.."(.CLK(CLK)"..sel(module.options.CE,",.CE(CE)","")..table.concat(arglist)..");"
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
  if self.options.onlyWire then return self.options.verilogDelay[fnname] end
  return self.fndelays[fnname]
end

function systolic.module.new( name, fns, instances, options )
  assert(type(name)=="string")
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
  for _,v in pairs(fns) do
    err( _usedPname[v.outputName]==nil, "output name "..v.outputName.." used somewhere else in module" )
    _usedPname[v.outputName]=1
    err( _usedPname[v.input.name]==nil, "input name "..v.input.name.." used somewhere else in module" )
    _usedPname[v.input.name]=1
    err( _usedPname[v.valid.name]==nil, "valid bit name "..v.valid.name.." used somewhere else in module" )
    _usedPname[v.valid.name]=1
  end

  local t = {name=name,kind="user",instances=instances,functions=fns, instanceMap={}, usedInstanceNames = {}, options=options,isComplete=false}
  map( instances, function(i) t.instanceMap[i]=1; t.usedInstanceNames[i.name]=1 end )
  setmetatable(t,userModuleMT)

  t.ast = t:lower()
  -- check that the instances refered to by this module are actually in the module
  t.ast:checkInstances( t.instanceMap )
  
  if options.onlyWire==nil or options.onlyWire==false then
    local pipelineRegisters
    t.ast, pipelineRegisters, t.fndelays = t.ast:pipeline()
    map( pipelineRegisters, function(p) table.insert( t.instances, p ) end )
  end

  return t
end

----------------------------
regModuleFunctions={}
setmetatable(regModuleFunctions,{__index=systolicModuleFunctions})
regModuleMT={__index=regModuleFunctions}

function regModuleFunctions:instanceToVerilog( instance, module, fnname, inputVar, validVar )
  if fnname=="delay" or fnname=="set" then
    local decl = declareReg(self.type, instance.name, self.initial).."\n"

    if module.options.CE or fnname=="set" then
      decl = decl.."  always @ (posedge CLK) begin if ("..sel(fnname=="set",validVar,"")..sel(fnname=="set" and module.options.CE," && ","")..sel(module.options.CE,"CE","")..") begin "..instance.name.." <= "..inputVar.."; end end"
    else
      decl = decl.."  always @ (posedge CLK) begin "..instance.name.." <= "..inputVar.."; end"
    end
    local name = instance.name
    if fnname=="set" then name = "_____REG_SET" end
    return name, decl, true
  elseif fnname=="get" then
    return instance.name, nil, true
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
-------------------
function systolic.module.regBy( ty, initial, setby )
  assert( systolic.isModule(setby) )
  assert( setby:getDelay( "process" ) == 0 )
  local sinp = systolic.parameter("inp",ty)
  local R = systolic.module.reg( ty, initial ):instantiate("R")
  local inner = setby:instantiate("inner")
  local fns = {}
  fns.get = systolic.lambda("get", systolic.parameter("getinp",types.null()), R:get(), "GET_OUTPUT" )
  local setvalid = systolic.parameter("set_valid",types.bool())
  fns.set = systolic.lambda("set", sinp, R:set(inner:process(systolic.tuple{R:get(),sinp}),setvalid), "SET_OUTPUT",{}, setvalid )

  return systolic.module.new( "RegBy_"..setby.name, fns, {R,inner}, {onlyWire=true,verilogDelay={get=0,set=0}} )
end

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
  return instance.name.."_"..fn.outputName, nil, true
end

function bramModuleFunctions:instanceToVerilogFinalize( instance, module )
  local VCS = instance.verilogCompilerState[module]
  if keycount(VCS)==1 then
    -- we only used 1 port
    local WRITE_MODE = "WRITE_FIRST"
    if VCS.writeAndReturnOriginal~=nil then WRITE_MODE="READ_FIRST" end

    local BRAM_SIZE
    if self.type:verilogBits()>32 then
      BRAM_SIZE="36Kb" -- large port widths only available with this ram size
    elseif (self.ramSizeInBytes>2048 and self.ramSizeInBytes<4096) then
      BRAM_SIZE="36Kb" 
    elseif self.ramSizeInBytes<=2048 then
      BRAM_SIZE="18Kb"
    else
      print("RAM SIZE",self.ramSizeInBytes)
      assert(false)
    end

    local WIDTH = self.type:verilogBits()
    assert(WIDTH<=64)

    return [[BRAM_SINGLE_MACRO #(
   .BRAM_SIZE("]]..BRAM_SIZE..[["), // Target BRAM, "18Kb" or "36Kb"
   .DEVICE("VIRTEX6"), // Target Device: "VIRTEX5", "VIRTEX6", "SPARTAN6"
   .DO_REG(0), // Optional output register (0 or 1)
   .INIT(36’h000000000), // Initial values on output port
   .INIT_FILE ("NONE"),
   .WRITE_WIDTH(]]..WIDTH..[[), // Valid values are 1-72 (37-72 only valid when BRAM_SIZE="36Kb")
   .READ_WIDTH(]]..WIDTH..[[),  // Valid values are 1-72 (37-72 only valid when BRAM_SIZE="36Kb")
   .SRVAL(36’h000000000), // Set/Reset value for port output
   .WRITE_MODE("]]..WRITE_MODE..[[")) ]]..instance.name..[[(.DO(]]..instance.name..[[_writeAndReturnOriginal), // Output data
.ADDR(ADDR), // Input address
.CLK(CLK), // Input clock
.DI(DI), // Input data port
.EN(EN), // Input RAM enable
.REGCE(REGCE), // Input output register enable
.RST(RST),     // Input reset
   .WE(WE)        // Input write enable
);]]

  else
    print("INVALID BRAM CONFIGURATION")
    for k,v in pairs(VCS) do print("VCS",k) end
    assert(false)
  end
end

function bramModuleFunctions:getDependenciesLL() return {} end
function bramModuleFunctions:toVerilog() return "" end
function bramModuleFunctions:getDelay( fnname )
  return 0
end

function systolic.module.bram( ramSizeInBytes, ty, Btype ) 
  err( types.isType(ty), "type must be a type")

  local t = {kind="bram",functions={},ramSizeInBytes=ramSizeInBytes, type=ty, Btype=Btype}
  t.functions.writeAndReturnOriginal = {name="writeAndReturnOriginal", input={name="SET_AND_RETURN_ORIG",type=types.tuple{types.uint(16),ty}},outputName="SET_AND_RETURN_ORIG_OUTPUT", output={type=ty}}
  t.functions.writeAndReturnOriginal.isPure = function() return false end

  return setmetatable( t, bramModuleMT )
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
      assn = assn .. instance.name.."_out["..((i+1)*8-1)..":"..(i*8).."] = $fgetc("..instance.name.."_file); "
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
    for i=0,self.type:sizeof()-1 do
      assn = assn .. "$fwrite("..instance.name..[[_file, "%c", ]]..instance.verilogCompilerState[module].write[1].."["..((i+1)*8-1)..":"..(i*8).."] ); "
    end

    local RST = ""
    if instance.verilogCompilerState[module].reset~=nil then
      RST = "if ("..instance.verilogCompilerState[module].reset[2]..[[) begin r=$fseek(]]..instance.name..[[_file,0,0); end]]
    end
    return [[integer ]]..instance.name..[[_file,r;
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
    print("Error, name "..inst.name.." already in use")
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

function systolicModuleConstructor:instantiate( name )
  self:complete()
  return self.module:instantiate(name)
end


return systolic