local types = require "types"
local J = require "common"
local R = require "rigel"
local S = require "systolic"
local IR = require("ir")

local UniformFunctions = {}
setmetatable( UniformFunctions,{__index=IR.IRFunctions})
local UniformMT = {__index=UniformFunctions}
local Uniform = {}

if terralib~=nil then
  UniformFunctions.toTerra = require("uniformTerra")
end

function Uniform.new(tab)
  assert(type(tab.inputs)=="table")
  return setmetatable(tab,UniformMT)
end

local opToZ3={mul="*",mod="mod",eq="=",gt=">",lt="<",max="max",ge=">=",le="<=",div="/",sub="-",add="+",["and"]="and",["or"]="or"}
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
  J.err( stat:isBool(),"stat should have boolean type? "..tostring(stat))
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
        return inputs[1]:Not()
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
        elseif n.op=="lt" then
          return Uniform(inputs[1].value<inputs[2].value)
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
        elseif n.op=="max" then
          return Uniform(math.max(inputs[1].value,inputs[2].value))
        elseif n.op=="and" then
          return Uniform(inputs[1].value and inputs[2].value)
        elseif n.op=="or" then
          return Uniform(inputs[1].value or inputs[2].value)
        else
          print("NYI - const op "..tostring(n.op))
          assert(false)
        end
      elseif n.kind=="binop" and n.op=="max" and
        inputs[1].kind=="const" and inputs[1].value==0 and inputs[2]:isUint() then
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
      elseif (n.kind=="binop" and n.op=="div") and (inputs[1]==inputs[2]) then
        return Uniform(1)
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

  if op=="and" or op=="or" then
    J.err(lhs:isBool(),"Uniform.binop: lhs should be bool")
    J.err(rhs:isBool(),"Uniform.binop: rhs should be bool")
  else
    J.err(lhs:isNumber(),"Uniform.binop: lhs should be number, but is: "..tostring(lhs))
    J.err(rhs:isNumber(),"Uniform.binop: rhs should be number, but is: "..tostring(rhs))
  end
  
  return Uniform.new{kind="binop",op=op,inputs={lhs,rhs}}
end)

UniformMT.__mul = function(lhs,rhs) return Uniform.binop("mul",lhs,rhs):simplify() end
UniformMT.__add = function(lhs,rhs) return Uniform.binop("add",lhs,rhs):simplify() end
UniformMT.__sub = function(lhs,rhs) return Uniform.binop("sub",lhs,rhs):simplify() end
UniformMT.__div = function(lhs,rhs) return Uniform.binop("div",lhs,rhs):simplify() end
UniformMT.__mod = function(lhs,rhs) return Uniform.binop("mod",lhs,rhs):simplify() end

-- not
function UniformFunctions:Not()
  return Uniform.new{kind="not",inputs={self}, type=types.bool() }
end

function UniformFunctions:And(rhs) return Uniform.binop("and",self,rhs):simplify() end
function UniformFunctions:Or(rhs) return Uniform.binop("or",self,rhs):simplify() end
function UniformFunctions:eq(rhs) return Uniform.binop("eq",self,rhs):simplify() end
function UniformFunctions:ge(rhs) return Uniform.binop("ge",self,rhs):simplify() end
function UniformFunctions:lt(rhs) return Uniform.binop("lt",self,rhs):simplify() end
function UniformFunctions:le(rhs) return Uniform.binop("le",self,rhs):simplify() end
function UniformFunctions:gt(rhs) return Uniform.binop("gt",self,rhs):simplify() end
function UniformFunctions:max(rhs) return Uniform.binop("max",self,rhs):simplify() end

boolOps = {["and"]=1,["or"]=1,eq=1,ge=1,lt=1,le=1,gt=1}
Uniform.isNumber = J.memoize(
  function(n)
    if n.kind=="const" then
      return type(n.value)=="number"
    elseif n.kind=="var" then
      return true
    elseif n.kind=="binop" then
      return boolOps[n.op]==nil
    elseif n.kind=="global" then
      return n.global.type:isNumber()
    else
      print("NYI isNumber "..tostring(n.kind))
      assert(false)
    end
  end)

function UniformFunctions:isNumber() return Uniform.isNumber(self) end
function UniformFunctions:isBool() return not Uniform.isNumber(self) end

-- This should be avoided!!
function UniformFunctions:toNumber()
  assert(self:isNumber())
  assert(self.kind=="const")
  return self.value
end

Uniform.addMSBs = J.memoize(
  function(v,msbs)
    assert(type(msbs)=="number")
    assert(v.type:isUint())
    return Uniform.new{kind="addMSBs",inputs={v},type=types.uint(v.type:verilogBits()+msbs),msbs=msbs}
  end)

function UniformFunctions:addMSBs(msbs) return Uniform.addMSBs(self,msbs):simplify() end

function UniformFunctions:assertAlwaysTrue()
  J.err( self:isBool(),"Uniform:assert() "..tostring(self)..", not a bool?")

  if self.kind=="const" then
    return self.value
  else
    print(":assert() - "..tostring(self))
    local z3str = {}
    --table.insert(z3str,"(set-logic QF_LIA)")
    table.insert(z3str,"(define-fun max ((x Int) (y Int)) Int (ite (< x y) y x))")
    table.insert(z3str,"(set-option :produce-models true)")
    local smtexpr, smtstats = self:applySimplifications():Not():toSMT()
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

-- what is the maximum value this expr can be?
function UniformFunctions:maximum()
  J.err( self:isNumber(),"Uniform:maximum() "..tostring(self)..", not a number?")

  if self.kind=="const" then
    return self.value
  else
  end

  assert(false)
end

local opToInfix = {mul="*",eq="==",mod="%",lt="<",gt=">",ge=">=",le="<=",max="max",div="/",sub="-",add="+",["and"]="&",["or"]="|"}
function UniformMT.__tostring(tab)
  local function tostringInner(t)
    if t.kind=="const" then
      return tostring(t.value)
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
function UniformFunctions:toVerilog(ty)
  J.err( types.isType(ty),"Uniform:toVerilog(): input must be type" )
  assert(self:canRepresentUsing(ty))

  if self.kind=="global" then
    return self.global.name
  elseif self.kind=="const" then
    return S.valueToVerilog( self.value, ty )
  elseif self.kind=="binop" then
    return self.inputs[1]:toVerilog(ty)..opToInfix[self.op]..self.inputs[2]:toVerilog(ty)
  else
    J.err(false,"Uniform:toVerilog() NYI - "..self.kind)
  end
end

function UniformFunctions:toSystolic(ty)
  J.err( types.isType(ty),"Uniform:toSystolic(): input must be type" )
  assert(self:canRepresentUsing(ty))
  
  return self:visitEach(
    function(n,inputs)

      if self.kind=="global" then
        return S.readSideChannel(self.global.systolicValue)
      elseif self.kind=="const" then
        return S.constant( self.value, types.valueToType(self.value) )
      else
        J.err(false,"Uniform:toSystolic() NYI - "..self.kind)
      end
    end)
end

-- can this uniform value be safely represented using type 'ty'?
Uniform.canRepresentUsing = J.memoize(
  function(n,ty)
    assert(Uniform.isUniform(n))
    assert(types.isType(ty))
    
    if n.kind=="const" then
      local ot = types.valueToType(n.value)
      return ot:canSafelyConvertTo(ty)
    elseif n.kind=="global" then
      return n.global.type:canSafelyConvertTo(ty)
    elseif n.kind=="binop" then
      local minv,maxv = ty:minValue(), ty:maxValue()
      return (n:ge(minv):And(n:le(maxv))):assertAlwaysTrue()
    else
      J.err(false,"Uniform.canRepresentUsing: NYI - "..n.kind)
    end
  end)

function Uniform.upToNearest(roundto,x)
  roundto,x = Uniform(roundto),Uniform(x)

  local ox = x + roundto - 1 - ((x + roundto - 1) % roundto)

  J.err( ox:ge(x):assertAlwaysTrue(), "roundto: "..tostring(roundto).." x:"..tostring(x).." ox:"..tostring(ox) )
  assert( ox:lt(x+roundto):assertAlwaysTrue() )
  assert( (ox % roundto):eq(0):assertAlwaysTrue() )
  return ox
end

function Uniform.makeDivisible(x,lst)
  x = Uniform(x)
  while true do
    local divisible = true
    for _,v in pairs(lst) do
      v = Uniform(v)
      divisible = divisible and ((x%v):eq(0):assertAlwaysTrue())
    end

    if divisible then return x end
    x = x + 1
  end
end

function UniformFunctions:canRepresentUsing(ty) return Uniform.canRepresentUsing(self,ty) end

function UniformFunctions:isUint()
  return self:isNumber() and self:ge(0):assertAlwaysTrue()
end

-- convert to a verilog string of the input ports required for any globals
function UniformFunctions:toVerilogPortList()
  local res = {}

  self:visitEach(
    function(n)
      if n.kind=="global" then
        table.insert( res, S.declarePort( n.global.type, n.global.name, true ) )
      end
    end)

  local rr = table.concat(res,",")
  if #res>0 then rr = rr.."," end
  return rr
end

local UniformTopMT = {}
setmetatable(Uniform,UniformTopMT)

Uniform.const = J.memoize(
  function(value,X)
    assert( X==nil )
    return Uniform.new{kind="const",value=value,inputs={}}
  end)
  
UniformTopMT.__call = J.memoize(function(tab,arg,X)
  J.err(X==nil,"Uniform(): too many args")

  if Uniform.isUniform(arg) then
return arg
  elseif R.isGlobal(arg) then
    J.err( arg.direction=="input", "Uniform: global uniform must be an input" )
return Uniform.new{kind="global",global=arg,inputs={}}
  elseif type(arg)=="number" then
return Uniform.const(arg)
  elseif type(arg)=="boolean" then
return Uniform.const(arg)
  elseif type(arg)=="string" then
return Uniform.new{kind="var",name=arg,inputs={}}
  else
    J.err(false,"Uniform: incorrect arg? "..tostring(arg))
  end
end)
  
function Uniform.isUniform(tab) return getmetatable(tab)==UniformMT end

return Uniform
