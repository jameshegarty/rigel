local types = require "types"
local J = require "common"
local R = require "rigel"
local S = require "systolic"
local IR = require("ir")

local UniformFunctions = {}
setmetatable( UniformFunctions,{__index=IR.IRFunctions})
local UniformMT = {__index=UniformFunctions}
local Uniform = {}

function Uniform.new(tab)
  assert(type(tab.inputs)=="table")
  return setmetatable(tab,UniformMT)
end

local opToZ3={mul="*",mod="mod",eq="=",gt=">",lt="<",max="max",ge=">=",le="<=",div="/",sub="-",add="+"}
function UniformFunctions:toSMT(includeProperties)
  if includeProperties==nil then includeProperties = true end
  local stats = {}
  local fres = self:visitEach(
    function(n,inputs)
      local res
      if n.kind=="const" then
        res = tostring(n.value)
      elseif n.kind=="global" then
        table.insert(stats,"(declare-const "..n.global.name.." Int)")
        res = n.global.name
      elseif n.kind=="var" then
        table.insert(stats,"(declare-const "..n.name.." Int)")
        res = n.name
      elseif n.kind=="binop" then
        if opToZ3[n.op]==nil then print("OP",t.op) end
        res = "("..opToZ3[n.op].." "..inputs[1].." "..inputs[2]..")"
      elseif n.kind=="not" then
        res = "(not "..inputs[1]..")"
      elseif n.kind=="addMSBs" then
        res = inputs[1]
      else
        print(":toSMT() NYI - "..tostring(n.kind))
      end
      assert(type(res)=="string")

      if n.properties~=nil and includeProperties then
        for _,v in ipairs(n.properties) do
          table.insert(stats,"(assert "..v:toSMT(false)..")")
        end
      end

      return res
    end)

  return fres,table.concat(stats,"\n")
end

function UniformFunctions:addProperty(stat)
  assert(Uniform.isUniform(stat))
  J.err(stat.type==types.bool(),"stat should have boolean type? "..tostring(stat))
  if self.properties==nil then self.properties={} end
  table.insert(self.properties,stat)
end

-- replace inp with out in formula
-- this is just for Solver!
function UniformFunctions:addSimplification(inp,out)
  assert(Uniform.isUniform(inp))
  assert(Uniform.isUniform(out))
  if self.simplifications==nil then self.simplifications={} end
  self.simplifications[inp]=out
end

function UniformFunctions:applySimplifications()
  -- collect them
  local simplificationMap = {}
  self:visitEach(
    function(n,inputs)
      if n.simplifications~=nil then
        for k,v in pairs(n.simplifications) do
          assert(simplificationMap[k]==nil)
          simplificationMap[k]=v
        end
      end
    end)

  for k,v in pairs(simplificationMap) do
    --print(k,"=>",v)
  end

  local res =  self:visitEach(
    function(n,inputs)
      if simplificationMap[n]~=nil then
        --print("REPLACE",n,"=>",simplificationMap[n])
        return simplificationMap[n]
      elseif n.kind=="global" or n.kind=="const" then
        return n
      elseif n.kind=="binop" then
        return Uniform.binop(n.op,inputs[1],inputs[2])
      elseif n.kind=="not" then
        return inputs[1]:n()
      elseif n.kind=="addMSBs" then
        return Uniform.addMSBs(inputs[1],n.msbs)
      else
        print("n.kind",n.kind)
        assert(false)
      end
      return n
    end)

  return res
end

function UniformFunctions:simplify()
  
  local res = self:visitEach(
    function(n,inputs)
      
      if n.kind=="binop" and inputs[1].kind=="const" and inputs[2].kind=="const" then
        if n.op=="eq" then
          return Uniform(inputs[1].value==inputs[2].value)
        elseif n.op=="gt" then
          return Uniform(inputs[1].value>inputs[2].value)
        elseif n.op=="ge" then
          return Uniform(inputs[1].value>=inputs[2].value)
        elseif n.op=="le" then
          return Uniform(inputs[1].value<=inputs[2].value)
        elseif n.op=="mul" then
          local prod = inputs[1].value*inputs[2].value
          assert(inputs[1].type==inputs[2].type)
          local ty = inputs[1].type
          return Uniform(prod,ty)
        elseif n.op=="add" then
          local sum = inputs[1].value+inputs[2].value
          assert(inputs[1].type==inputs[2].type)
          local ty = inputs[1].type
          return Uniform(sum,ty)
        elseif n.op=="sub" then
          assert(inputs[1].type==inputs[2].type)
          local ty = inputs[1].type
          return Uniform(inputs[1].value-inputs[2].value,ty)
        elseif n.op=="div" then
          local res = inputs[1].value/inputs[2].value
          if res == math.floor(res) then
            return Uniform(res)
          else
            local nn,dd = J.simplify(inputs[1].value,inputs[2].value)
            return Uniform.binop("div",nn,dd)
          end
        elseif n.op=="mod" then
          return Uniform(inputs[1].value%inputs[2].value)
        else
          print("NYI - const op "..tostring(n.op))
          assert(false)
        end
      elseif n.kind=="binop" and n.op=="max" and
        inputs[1].kind=="const" and inputs[1].value==0 and inputs[2].type:isUint() then
        -- max(0,X:uint)->X
        return inputs[2]
      elseif n.kind=="binop" and n.op=="mul" and inputs[1].kind=="const" and inputs[1].value==1 then
        -- 1*X->X
--        assert(false)
        return inputs[2]
      elseif n.kind=="binop" and n.op=="mul" and inputs[2].kind=="const" and inputs[2].value==1 then
        -- X*1->X
--        assert(false)
        return inputs[1]
      elseif n.kind=="binop" and n.op=="mul" and inputs[1].kind=="const" and inputs[1].value==0 then
        return Uniform(0)
      elseif n.kind=="binop" and n.op=="mul" and inputs[2].kind=="const" and inputs[2].value==0 then
        return Uniform(0)
      elseif n.kind=="binop" and n.op=="add" and inputs[1].kind=="const" and inputs[1].value==0 then
        return inputs[2]
      elseif n.kind=="binop" and n.op=="add" and inputs[2].kind=="const" and inputs[2].value==0 then
        return inputs[1]
      elseif (n.kind=="binop" and n.op=="mul") and
        (inputs[1].kind=="binop" and inputs[1].op=="mul") and
        (inputs[1].inputs[2].kind=="const") and
        (inputs[2].kind=="const") then
          --(* (* X C) D) = (* X (C*D) )
--          assert(false)
          return Uniform.binop("mul",inputs[1].inputs[1],Uniform(inputs[2].value*inputs[1].inputs[2].value))
      elseif (n.kind=="binop" and n.op=="mul") and
        (inputs[2].kind=="binop" and inputs[2].op=="mul") and
        (inputs[2].inputs[1].kind=="const") and
        (inputs[1].kind=="const") then
          --(* C (* D X) ) = (* (C*D) X )
--          assert(false)
          return Uniform.binop("mul",inputs[2].inputs[2],Uniform(inputs[1].value*inputs[2].inputs[1].value))
      elseif (n.kind=="binop" and n.op=="div") and
        (inputs[1].kind=="binop" and inputs[1].op=="div") and
        (inputs[1].inputs[2].kind=="const") and
        (inputs[2].kind=="const") then
          --(/ (/ X D) C) = (/ X (C*D) )
          --assert(false)
          return Uniform.binop("div",inputs[1].inputs[1],Uniform(inputs[2].value*inputs[1].inputs[2].value))
      elseif (n.kind=="binop" and n.op=="div") and
        (inputs[1].kind=="binop" and inputs[1].op=="mul") and
        (inputs[1].inputs[2].kind=="const") and
        (inputs[2].kind=="const") then
          --(/ (* X D) C) = (* X (D/C) )

          local D,C = inputs[1].inputs[2].value, inputs[2].value

          if D==C then
            local res =  inputs[1].inputs[1]
            return res
          elseif D<C then
            local V = C/D
            assert(V==math.floor(V))
            local res = Uniform.binop("div",inputs[1].inputs[1],Uniform(V))

            print("DSM",self,res)
            assert(false)
            return res
          elseif C>D then
            assert(false)
          end

      elseif (n.kind=="binop" and n.op=="mul") and
        (inputs[1].kind=="binop" and inputs[1].op=="div") and
        (inputs[1].inputs[2].kind=="const") and
        (inputs[2].kind=="const") then
          --(* (/ X D) C) = (* X (C/D) )

          local D,C = inputs[1].inputs[2].value, inputs[2].value

          if D==C then
            local res =  inputs[1].inputs[1]
            return res
          elseif D<C then
            assert(false)
          elseif C>D then
            assert(false)
          end
      elseif n.kind=="addMSBs" and inputs[1].kind=="const" then
        return Uniform.const( n.type, inputs[1].value )
      end

      
      ---------- passthroughs (no simplification)
      if n.kind=="binop" then
        return Uniform.binop(n.op,inputs[1],inputs[2])
      elseif n.kind=="addMSBs" then
        return Uniform.addMSBs(inputs[1],n.msbs)
      elseif n.kind=="const" or n.kind=="var" or n.kind=="global" then
        return n
      else
        print("simplify missing passthrough?",n.kind)
        assert(false)
      end

    end)

  --print("SIMPLIFY",self,res)
  return res
end

Uniform.binop = J.memoize(function(op,lhs,rhs)
  local ty = types.uint(32)

  lhs,rhs = Uniform(lhs),Uniform(rhs)

  if op=="eq" or op=="gt" or op=="lt" or op=="ge" or op=="le" then
    ty = types.bool()
  else
    assert(lhs.type:isUint())
    J.err(rhs.type:isUint(),"Uniform.binop op:"..op.." rhs is not a uint? "..tostring(rhs))
    J.err(lhs.type==rhs.type,"Uniform.binop, LHS and RHS types don't match: "..tostring(lhs).." "..tostring(rhs))
  end
  
  return Uniform.new{kind="binop",op=op,inputs={lhs,rhs},type=ty }
end)

UniformMT.__mul = function(lhs,rhs) return Uniform.binop("mul",lhs,rhs):simplify() end
UniformMT.__add = function(lhs,rhs) return Uniform.binop("add",lhs,rhs):simplify() end
UniformMT.__sub = function(lhs,rhs) return Uniform.binop("sub",lhs,rhs):simplify() end
UniformMT.__div = function(lhs,rhs) return Uniform.binop("div",lhs,rhs):simplify() end
UniformMT.__mod = function(lhs,rhs) return Uniform.binop("mod",lhs,rhs):simplify() end

-- not
function UniformFunctions:n()
  return Uniform.new{kind="not",inputs={self}, type=types.bool() }
end

function UniformFunctions:eq(rhs) return Uniform.binop("eq",self,rhs):simplify() end
function UniformFunctions:ge(rhs) return Uniform.binop("ge",self,rhs):simplify() end
function UniformFunctions:lt(rhs) return Uniform.binop("lt",self,rhs):simplify() end
function UniformFunctions:le(rhs) return Uniform.binop("le",self,rhs):simplify() end
function UniformFunctions:gt(rhs) return Uniform.binop("gt",self,rhs):simplify() end
function UniformFunctions:max(rhs) return Uniform.binop("max",self,rhs):simplify() end

Uniform.addMSBs = J.memoize(
  function(v,msbs)
    assert(type(msbs)=="number")
    assert(v.type:isUint())
    return Uniform.new{kind="addMSBs",inputs={v},type=types.uint(v.type:verilogBits()+msbs),msbs=msbs}
  end)

function UniformFunctions:addMSBs(msbs) return Uniform.addMSBs(self,msbs):simplify() end

function UniformFunctions:assertAlwaysTrue()
  J.err( self.type:isBool(),"Uniform:assert() "..tostring(self)..", not a bool?")

  if self.kind=="const" then
    return self.value
  else
    print(":assert() - "..tostring(self))
    local z3str = {}
    --table.insert(z3str,"(set-logic QF_LIA)")
    table.insert(z3str,"(define-fun max ((x Int) (y Int)) Int (ite (< x y) y x))")
    table.insert(z3str,"(set-option :produce-models true)")
    local smtexpr, smtstats = self:applySimplifications():n():toSMT()
    table.insert(z3str,smtstats)
    table.insert(z3str, "(assert "..smtexpr..")" )
    table.insert(z3str, "(check-sat)")
    table.insert(z3str, "(get-model)")
    z3str = table.concat(z3str,"\n")
    local z3call = [[echo "]]..z3str..[[" | z3 -in -smt2]]

    print("Z3CALL")
    print(z3call)

    f = assert (io.popen (z3call))

    local res = ""
    for line in f:lines() do
      --print(line)
      res = res..line
    end -- for loop

    f:close()

    print("Z3RESULT:"..res.."END")

    if string.match(res,"unsat") then
--      print(debug.traceback())
      return true
    else
      print(debug.traceback())
      return false
    end
  end

  assert(false)
end

local opToInfix = {mul="*",eq="==",mod="%",lt="<",gt=">",ge=">=",le="<=",max="max",div="/",sub="-",add="+"}
function UniformMT.__tostring(tab)
  local function tostringInner(t)
    if t.kind=="const" then
      return tostring(t.value)..":"..tostring(t.type)
    elseif t.kind=="global" then
      return t.global.name
    elseif t.kind=="binop" and t.op=="max" then
      return "max("..tostringInner(t.inputs[1])..","..tostringInner(t.inputs[2])..")"
    elseif t.kind=="binop" then
      if opToInfix[t.op]==nil then print("OP",t.op) end
      return "("..tostringInner(t.inputs[1])..opToInfix[t.op]..tostringInner(t.inputs[2])..")"
    elseif t.kind=="not" then
      return "not("..tostringInner(t.inputs[1])..")"
    elseif t.kind=="addMSBs" then
      return tostringInner(t.inputs[1])..":"..tostring(t.type)
    elseif t.kind=="var" then
      return t.name
    else
      J.err(false,"Uniform tostring() NYI - "..t.kind)
    end
  end
  return "Uniform("..tostringInner(tab)..")"
end

-- returns a string that can be dumped into a lua file
function UniformFunctions:toEscapedString()
  if self.kind=="const" then
    return tostring(self.value)
  elseif self.kind=="global" then
    return [["]]..self.global.name..[["]]
  else
    J.err(false,"Uniform toEscapedString() NYI - "..self.kind)
  end
end

-- 'tab' should be a map of globals, to which we will append any globals in this uniform
-- this will mutate 'tab'!
function UniformFunctions:appendGlobals(tab)
  self:visitEach(
    function(n)
      if n.kind=="global" then
        assert(tab[n.global]==nil)
        tab[n.global] = 1
      end
    end)
end

-- convert to a verilog string for the value
function UniformFunctions:toVerilog()
  if self.kind=="global" then
    return self.global.name
  elseif self.kind=="const" then
    return S.valueToVerilog( self.value, self.type )
  elseif self.kind=="binop" then
    return self.inputs[1]:toVerilog()..opToInfix[self.op]..self.inputs[2]:toVerilog()
  else
    J.err(false,"Uniform:toVerilog() NYI - "..self.kind)
  end
end

function UniformFunctions:toSystolic()
  if self.kind=="global" then
    return S.readSideChannel(self.global.systolicValue)
  elseif self.kind=="const" then
    return S.constant( self.value, self.type )
  else
    J.err(false,"Uniform:toSystolic() NYI - "..self.kind)
  end
end

function UniformFunctions:isUint()
  return self.type:isUint()
end

-- convert to a verilog string of the input ports required for any globals
function UniformFunctions:toVerilogPortList()
  local res = {}

  self:visitEach(
    function(n)
      if n.kind=="global" then
        table.insert( res, S.declarePort( n.type, n.global.name, true ) )
      end
    end)

  local rr = table.concat(res,",")
  if #res>0 then rr = rr.."," end
  return rr
end

local UniformTopMT = {}
setmetatable(Uniform,UniformTopMT)

Uniform.const = J.memoize(
  function(ty,value)
    assert( types.isType(ty) )
    ty:checkLuaValue(value)
    return Uniform.new{kind="const",value=value,type=ty,inputs={}}
  end)
  
UniformTopMT.__call = J.memoize(function(tab,arg1,arg2,X)
  assert(X==nil)
  
  local ty, value

  if arg2==nil then
    if Uniform.isUniform(arg1) then
return arg1
    elseif R.isGlobal(arg1) then
      J.err( arg1.direction=="input", "Uniform: global uniform must be an input" )
return Uniform.new{kind="global",global=arg1,type=arg1.type,inputs={}}
    elseif type(arg1)=="number" then
return Uniform.const(types.uint(32),arg1)
    elseif type(arg1)=="boolean" then
return Uniform.const(types.bool(),arg1)
    else
      J.err(false,"Uniform: incorrect args? "..tostring(arg1)..","..tostring(arg2))
    end
  end
  
  if types.isType(arg1) then
    ty, value = arg1, arg2
  elseif types.isType(arg2) then
    ty, value = arg2, arg1
  else
    J.err(false,"Uniform: should be passed a value and a type, but was passed: "..tostring(arg1)..","..tostring(arg2))
  end

  if R.isGlobal(value) then
    J.err( value.type==ty,"Uniform: global input type ("..tostring(value.type)..") must match requested type ("..tostring(ty)..")")
    J.err( value.direction=="input", "Uniform: global uniform must be an input" )
return Uniform.new{kind="global",global=value,type=ty,inputs={}}
  elseif Uniform.isUniform(value) then
    if value.type~=ty and value.type:isUint() and ty:isUint() and ty:verilogBits()>value.type:verilogBits() then
      -- convert to larger size
return value:addMSBs(ty:verilogBits()-value.type:verilogBits())
    end
    
    J.err(value.type==ty,"Initializing a uniform with another uniform of unexpected type? expected type:"..tostring(ty).." input type:"..tostring(value.type))
return value
  elseif type(value)=="string" then
return Uniform.new{kind="var",type=ty,name=value,inputs={}}
  else
return Uniform.const(ty,arg1)
  end
  
end)
  
function Uniform.isUniform(tab) return getmetatable(tab)==UniformMT end

return Uniform
