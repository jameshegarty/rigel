local types = require "types"
local J = require "common"
local R = require "rigel"
local S = require "systolic"
local Ssugar = require "systolicsugar"
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

local opToZ3={mul="*",mod="mod",eq="=",gt=">",lt="<",max="max",ge=">=",le="<=",div="/",sub="-",add="+",["and"]="and",["or"]="or",["^"]="^"}
function UniformFunctions:toSMT(includeProperties)
  if includeProperties==nil then includeProperties = true end
  local stats = {}
  local fres = self:visitEach(
    function(n,inputs)
      local res
      if n.kind=="const" then
        res = tostring(n.value)
      elseif n.kind=="apply" then
        res = n.instance.module.name
        table.insert(stats,"(declare-const "..res.." Int)")
      elseif n.kind=="var" then
        table.insert(stats,"(declare-const "..n.name.." Int)")
        res = n.name
      elseif n.kind=="binop" then
        if n.op=="rshift" then
          J.err(n.inputs[2].kind=="const","Rshift: rhs should be const, but is: "..tostring(n.inputs[2]))
          res = "(/ "..inputs[1].." "..tostring(math.pow(2,n.inputs[2].value))..")"
        else
          if opToZ3[n.op]==nil then print("missing OP",n.op) end
          
          if n.op=="^" and n.inputs[2].kind=="const" and n.inputs[2].value==2 then
            res = "(* "..inputs[1].." "..inputs[1]..")"
          else
            J.err(n.op~="^","Uniform: could not codegen '"..tostring(self).."' b/c uses ^? ") -- not implemented in some versions of z3
            res = "("..opToZ3[n.op].." "..inputs[1].." "..inputs[2]..")"
          end
        end
      elseif n.kind=="unary" then
        res = "("..n.op.." "..inputs[1]..")"
      elseif n.kind=="addMSBs" then
        res = inputs[1]
      elseif n.kind=="sel" then
        res = "(ite "..inputs[1].." "..inputs[2].." "..inputs[3]..")"
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
      elseif n.kind=="apply" or n.kind=="const" or n.kind=="var" then
        return n
      elseif n.kind=="binop" then
        return Uniform.binop(n.op,inputs[1],inputs[2])
      elseif n.kind=="not" then
        return inputs[1]:Not()
      elseif n.kind=="addMSBs" then
        return Uniform.addMSBs(inputs[1],n.msbs)
      elseif n.kind=="sel" then
        return Uniform.sel(inputs[1],inputs[2],inputs[3])
      else
        print("n.kind",n.kind)
        assert(false)
      end
      return n
    end)

  return res
end

DEEP_SIMPLIFY = true
UniformFunctions.simplify = J.memoize(function(self)
  local n = self
  local inputs = {}                                      

  for k,v in ipairs(self.inputs) do inputs[k] = self.inputs[k]:simplify() end
  
  if n.kind=="binop" and inputs[1].kind=="const" and inputs[2].kind=="const" then
    -- constant propagate
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
  elseif n.kind=="unary" and inputs[1].kind=="const" then
    if n.op=="ceil" then
      return Uniform(math.ceil(inputs[1].value))
    elseif n.op=="floor" then
      return Uniform(math.floor(inputs[1].value))
    else
      print("NYI - const op "..tostring(n.op))
      assert(false)
    end
  elseif n.kind=="sel" and inputs[1].kind=="const" then
    if inputs[1].value then
      return inputs[2]
    else
      return inputs[3]
    end
  elseif n.kind=="sel" and DEEP_SIMPLIFY then
    if inputs[1]:assertAlwaysTrue() then
      -- cond is always true: we can simplify
      return inputs[2]
    elseif inputs[1]:assertAlwaysFalse() then
      return inputs[3]
    else
      return Uniform.sel(inputs[1],inputs[2],inputs[3])
    end
  elseif n.kind=="binop" and n.op=="max" and
    inputs[1].kind=="const" and inputs[1].value==0 and inputs[2]:isUint() then
    -- max(0,X:uint)->X
    return inputs[2]
  elseif n.kind=="binop" and n.op=="mul" and inputs[1].kind=="const" and inputs[1].value==1 then
    -- 1*X->X
    return inputs[2]
  elseif n.kind=="binop" and n.op=="mul" and inputs[2].kind=="const" and inputs[2].value==1 then
    -- X*1->X
    return inputs[1]
  elseif n.kind=="binop" and n.op=="div" and inputs[2].kind=="const" and inputs[2].value==1 then
    -- X/1->X
    return inputs[1]
  elseif n.kind=="binop" and n.op=="div" and inputs[1]==inputs[2] then
    -- X/X->1
    return Uniform.const(1)
  elseif n.kind=="binop" and n.op=="mul" and inputs[1]==inputs[2] then
    -- X*X->X^2
    return Uniform.binop("^",inputs[1],Uniform.const(2))
  elseif n.kind=="binop" and n.op=="^" and inputs[2].kind=="const" and inputs[2].value==1 then
    -- X^1 -> X
    return inputs[1]
  elseif n.kind=="binop" and n.op=="mul" and inputs[2].kind=="binop" and inputs[2].op=="^" and inputs[1]==inputs[2].inputs[1] then
    -- X*(X^N)->X^(N+1)
    return Uniform.binop("^",inputs[1],Uniform.const(inputs[2].inputs[2].value+1))
  elseif n.kind=="binop" and n.op=="mul" and inputs[1].kind=="binop" and inputs[1].op=="^" and inputs[2]==inputs[1].inputs[1] then
    -- (X^N)*X->X^(N+1)
    return Uniform.binop("^",inputs[2],Uniform.const(inputs[1].inputs[2].value+1))
  elseif n.kind=="binop" and n.op=="div" and inputs[2].kind=="binop" and inputs[2].op=="^" and inputs[1]==inputs[2].inputs[1] then
    -- X/X^N -> 1/X^(N-1)
    return Uniform.binop("div",Uniform.const(1),Uniform.binop("^",inputs[1],inputs[2].inputs[2].value-1))
  elseif n.kind=="binop" and n.op=="div" and inputs[1].kind=="binop" and inputs[1].op=="^" and inputs[1].inputs[1]==inputs[2] then
    -- X^N/X -> X^(N-1)
    assert(false)
  elseif n.kind=="binop" and n.op=="div" and inputs[1].kind=="binop" and inputs[1].op=="^" and inputs[2].kind=="binop" and inputs[2].op=="^" then
    -- X^N/X^M
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
      --(/ (* X D) C) = (* X (D/C) ) = (/ X (C/D) )
      local V = C/D
      assert(V==math.floor(V))
      local res = Uniform.binop("div",inputs[1].inputs[1],Uniform(V))
      
      print("DSM",self,res)
      --assert(false)
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
  elseif n.kind=="unary" then
    return Uniform.unary(n.op,inputs[1])
  elseif n.kind=="addMSBs" then
    return Uniform.addMSBs(inputs[1],n.msbs)
  elseif n.kind=="sel" then
    return Uniform.sel(inputs[1],inputs[2],inputs[3])
  elseif n.kind=="const" or n.kind=="var" or n.kind=="apply" then
    return n
  else
    print("simplify missing passthrough?",n.kind)
    assert(false)
  end
end)

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

Uniform.unary = J.memoize(
  function(op,expr)
    return Uniform.new{kind="unary",op=op, inputs={expr}, type=expr.ty }
  end)

UniformMT.__mul = function(lhs,rhs) return Uniform.binop("mul",lhs,rhs):simplify() end
UniformMT.__add = function(lhs,rhs) return Uniform.binop("add",lhs,rhs):simplify() end
UniformMT.__sub = function(lhs,rhs) return Uniform.binop("sub",lhs,rhs):simplify() end
UniformMT.__div = function(lhs,rhs) return Uniform.binop("div",lhs,rhs):simplify() end
UniformMT.__mod = function(lhs,rhs) return Uniform.binop("mod",lhs,rhs):simplify() end

-- not
function UniformFunctions:Not() return Uniform.unary("not",self):simplify() end
function UniformFunctions:ceil() return Uniform.unary("ceil",self):simplify() end
function UniformFunctions:floor() return Uniform.unary("floor",self):simplify() end

function UniformFunctions:And(rhs) return Uniform.binop("and",self,rhs):simplify() end
function UniformFunctions:Or(rhs) return Uniform.binop("or",self,rhs):simplify() end
function UniformFunctions:eq(rhs) return Uniform.binop("eq",self,rhs):simplify() end
function UniformFunctions:ge(rhs) return Uniform.binop("ge",self,rhs):simplify() end
function UniformFunctions:lt(rhs) return Uniform.binop("lt",self,rhs):simplify() end
function UniformFunctions:le(rhs) return Uniform.binop("le",self,rhs):simplify() end
function UniformFunctions:gt(rhs) return Uniform.binop("gt",self,rhs):simplify() end
function UniformFunctions:max(rhs) return Uniform.binop("max",self,rhs):simplify() end
function UniformFunctions:lshift(rhs) return Uniform.binop("lshift",self,rhs):simplify() end
function UniformFunctions:rshift(rhs) return Uniform.binop("rshift",self,rhs):simplify() end

Uniform.sel = J.memoize(
  function(cond,iftrue,iffalse)
    J.err(cond:isBool(),"sel: cond should be bool")
    return Uniform.new{kind="sel",inputs={cond,iftrue,iffalse}}
  end)

function UniformFunctions:sel(iftrue,iffalse) return Uniform.sel(self,iftrue,iffalse):simplify() end

boolOps = {["and"]=1,["or"]=1,eq=1,ge=1,lt=1,le=1,gt=1,["not"]=1}
Uniform.isNumber = J.memoize(
  function(n)
    if n.kind=="const" then
      return type(n.value)=="number"
    elseif n.kind=="var" then
      return true
    elseif n.kind=="binop" or n.kind=="unary" then
      return boolOps[n.op]==nil
    elseif n.kind=="apply" then
      assert(n.instance.module.outputType:isS())
      assert(n.instance.module.outputType.over:is("Par"))
      assert(n.instance.module.outputType.over.over:isData())
      return n.instance.module.outputType.over.over:isNumber()
    elseif n.kind=="sel" then
      assert(n.inputs[2]:isNumber()==n.inputs[3]:isNumber())
      return n.inputs[2]:isNumber()
    else
      print("NYI isNumber "..tostring(n.kind))
      assert(false)
    end
  end)

Uniform.isInteger = J.memoize(
  function(n)
    if n.kind=="const" then
      return type(n.value)=="number" and (n.value==math.floor(n.value))
    else
      print("NYI isInteger "..tostring(n.kind))
      assert(false)
    end
  end)

function UniformFunctions:isNumber() return Uniform.isNumber(self) end
function UniformFunctions:isInteger() return Uniform.isInteger(self) end
function UniformFunctions:isBool() return not Uniform.isNumber(self) end

-- This should be avoided!!
function UniformFunctions:toNumber()
  assert(self:isNumber())
  J.err(self.kind=="const",":toNumber(): not a const? "..tostring(self))
  return self.value
end

function UniformFunctions:toNumberIfPossible()
  if self.kind=="const" and self:isNumber() then return self.value end
  return self
end

-- is this uniform exactly one value?
function UniformFunctions:isConst()
  return self.kind=="const"
end

Uniform.addMSBs = J.memoize(
  function(v,msbs)
    assert(type(msbs)=="number")
    assert(v.type:isUint())
    return Uniform.new{kind="addMSBs",inputs={v},type=types.uint(v.type:verilogBits()+msbs),msbs=msbs}
  end)

function UniformFunctions:addMSBs(msbs) return Uniform.addMSBs(self,msbs):simplify() end

-- if alwaysTrue=true, assert always true
-- if alwaysTrue=false, assert alwaysFalse
UniformFunctions.assertAlways = J.memoize(function(self,alwaysTrue)
  J.err( self:isBool(),"Uniform:assert() "..tostring(self)..", not a bool?")
  assert(type(alwaysTrue)=="boolean")
  
  if self.kind=="const" then
    assert(type(self.value)=="boolean")
    return self.value==alwaysTrue
  else

    local z3str = {}
    --table.insert(z3str,"(set-logic QF_LIA)")
    table.insert(z3str,"(define-fun max ((x Int) (y Int)) Int (ite (< x y) y x))")
    table.insert(z3str,"(set-option :produce-models true)")
    local expr = self:applySimplifications()
    if alwaysTrue then expr = expr:Not() end
    local smtexpr, smtstats = expr:toSMT()
    table.insert(z3str,smtstats)
    table.insert(z3str, "(assert "..smtexpr..")" )
    table.insert(z3str, "(check-sat)")
    table.insert(z3str, "(get-model)")
    z3str = table.concat(z3str,"\n")
    local z3call = [[echo "]]..z3str..[[" | z3 -in -smt2]]

    --print(debug.traceback())

    local f = assert (io.popen (z3call))

    local res = ""
    for line in f:lines() do
      --print(line)
      res = res..line
    end -- for loop

    f:close()

    if string.match(res,"unsat") then
      --      print(debug.traceback())
      --print("ASSERT_ALWAYS("..tostring(alwaysTrue)..") return true")
      return true
    else
      print(":assertAlways() - "..tostring(self))
      print("Z3CALL assertAlways()")
      print(z3call)
      print("Z3RESULT:"..res.."END")
      print("ASSERT_ALWAYS("..tostring(alwaysTrue).." return false")
      print(debug.traceback())
      return false
    end
  end

  assert(false)
end)

function UniformFunctions:assertAlwaysTrue() return self:assertAlways(true) end
function UniformFunctions:assertAlwaysFalse() return self:assertAlways(false) end

-- what is the maximum value this expr can be?
function UniformFunctions:maximum()
  J.err( self:isNumber(),"Uniform:maximum() "..tostring(self)..", not a number?")

  if self.kind=="const" then
    return self.value
  else
    local z3str = {}
    table.insert(z3str,"(declare-const MAXIMUSVAR Int)")
    table.insert(z3str,"(define-fun max ((x Int) (y Int)) Int (ite (< x y) y x))")
    table.insert(z3str,"(set-option :produce-models true)")
    local smtexpr, smtstats = self:applySimplifications():toSMT()
    table.insert(z3str,smtstats)
    table.insert(z3str,"(assert (<= MAXIMUSVAR "..smtexpr.."))")
    table.insert(z3str, "(maximize MAXIMUSVAR)")
    table.insert(z3str, "(check-sat)")
    table.insert(z3str, "(get-objectives)")
    --table.insert(z3str, "(get-model)")
    z3str = table.concat(z3str,"\n")
    local z3call = [[echo "]]..z3str..[[" | z3 -in -smt2]]

    --print("Z3CALL")
    --print(z3call)

    local f = assert (io.popen (z3call))

    local res = ""
    for line in f:lines() do
      res = res..line
    end

    f:close()

    --print("Z3RESULT:"..res.."END")

    if string.match(res,"sat") then
      local num = string.match (res, "%d+")
      --print("Z3MAX:",num)
      J.err(num~=nil and type(tonumber(num))=="number","failed to find maximum value of expr? "..tostring(self))
      return tonumber(num)
    else
      assert(false)
    end
  end

  assert(false)
end

local opToInfix = {mul="*",eq="==",mod="%",lt="<",gt=">",ge=">=",le="<=",max="max",div="/",sub="-",add="+",["and"]="&",["or"]="|",lshift="<<",rshift=">>",["^"]="^"}
function UniformMT.__tostring(tab)
  local function tostringInner(t)
    if t.kind=="const" then
      if false and type(t.value)=="number" then
        return tostring(t.value).."/0x"..string.format("%x",t.value)
      else
        return tostring(t.value)
      end
    elseif t.kind=="apply" then
      return t.instance.module.name.."()"
    elseif t.kind=="binop" and t.op=="max" then
      return "max("..tostringInner(t.inputs[1])..","..tostringInner(t.inputs[2])..")"
    elseif t.kind=="binop" then
      if opToInfix[t.op]==nil then print("OP",t.op) end
      return "("..tostringInner(t.inputs[1])..opToInfix[t.op]..tostringInner(t.inputs[2])..")"
    elseif t.kind=="unary" then
      return t.op.."("..tostringInner(t.inputs[1])..")"
    elseif t.kind=="addMSBs" then
      return tostringInner(t.inputs[1])..":"..tostring(t.type)
    elseif t.kind=="sel" then
      return "("..tostringInner(t.inputs[1])..")?("..tostringInner(t.inputs[2]).."):("..tostringInner(t.inputs[3])..")"
    elseif t.kind=="var" then
      return t.name
    else
      J.err(false,"Uniform tostring() NYI - "..t.kind)
    end
  end
  return "Uni("..tostringInner(tab)..")"
end

-- returns a string that can be dumped into a lua file
function UniformFunctions:toEscapedString()
  if self.kind=="const" then
    return tostring(self.value)
  elseif self.kind=="apply" then
    return [["]]..self.instance.module.name..[["]]
  elseif self.kind=="binop" then
    return self.inputs[1]:toEscapedString()..self.op..self.inputs[2]:toEscapedString()
  else
    J.err(false,"Uniform toEscapedString() NYI - "..self.kind)
  end
end

function UniformFunctions:toUnescapedString()
  if self.kind=="const" then
    return self.value
  elseif self.kind=="global" then
    return self.global.name
  else
    J.err(false,"Uniform toEscapedString() NYI - "..self.kind)
  end
end

-- return map of rigel instances needed to implement this uniform
function UniformFunctions:getInstances()
  local instanceMap = {}
  self:visitEach(
    function(n)
      if n.kind=="apply" then
        instanceMap[n.instance] = 1
      end
    end)
  return instanceMap
end

function UniformFunctions:appendRequires(requires)
  self:visitEach(
    function(n)
      if n.kind=="apply" then
        for inst,fnmap in pairs(n.instance.module.requires) do
          if requires[inst]==nil then requires[inst]={} end
          for fnname,_ in pairs(fnmap) do
            requires[inst][fnname] = 1
          end
        end
      end
    end)
end

function UniformFunctions:appendProvides(provides)
  self:visitEach(
    function(n)
      if n.kind=="apply" then
        for inst,fnmap in pairs(n.instance.module.provides) do
          if provides[inst]==nil then provides[inst]={} end
          for fnname,_ in pairs(fnmap) do
            provides[inst][fnname] = 1
          end
        end
      end
    end)
end

-- convert to a verilog string for the value
function UniformFunctions:toVerilog(ty)
  J.err( types.isType(ty),"Uniform:toVerilog(): input must be type" )
  J.err( types.isBasic(ty),"Uniform:toVerilog(): input must be basic type, but is: "..tostring(ty) )
  J.err( self:canRepresentUsing(ty), "Uniform:toVerilog() can't represent uniform '"..tostring(self).."' using type '"..tostring(ty).."'")

  if self.kind=="apply" then
    return self.instance.name.."_process_output"
  elseif self.kind=="const" then
    return S.valueToVerilog( self.value, ty )
  elseif self.kind=="binop" then
    return self.inputs[1]:toVerilog(ty)..opToInfix[self.op]..self.inputs[2]:toVerilog(ty)
  else
    J.err(false,"Uniform:toVerilog() NYI - "..self.kind)
  end
end

function UniformFunctions:toVerilogInstance()
  if self.kind=="apply" then
    return self.instance:toVerilog()
  end
  return ""
end

local opToSystolic={mul="*",rshift=">>",lshift="<<",sub="-"}
-- systolicModule: we can automatically append instance list fo a systolic module constructor if this is given
function UniformFunctions:toSystolic( ty, systolicModule, X )
  J.err( types.isType(ty),"Uniform:toSystolic(): input must be type" )
  J.err(self:canRepresentUsing(ty),":toSystolic() Error: "..tostring(self).." can't be represented using type "..tostring(ty))
  J.err( systolicModule==nil or Ssugar.isModuleConstructor(systolicModule), ":toSystolic() second arg should be module constructor" )
  assert(X==nil)
  
  return self:visitEach(
    function(n,inputs)

      if n.kind=="apply" then
        local sinst = (n.instance:toSystolicInstance())

        if systolicModule~=nil then
          systolicModule:add(sinst)

          for inst,fnmap in pairs(sinst.module.externalInstances) do
            for fnname,_ in pairs(fnmap) do
              systolicModule:addExternalFn(inst,fnname)
            end
          end
        end
        
        return sinst:process()
      elseif n.kind=="const" then
        return S.constant( n.value, types.valueToType(n.value) )
      elseif n.kind=="binop" then
        J.err(opToSystolic[n.op]~=nil, "Uniform:toSystolic(): missing op "..n.op.." needed for: "..tostring(self))
        return S.binop(inputs[1],inputs[2],opToSystolic[n.op])
      else
        J.err(false,"Uniform:toSystolic() NYI - "..n.kind)
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
    elseif n.kind=="apply" then
      assert(n.instance.module.outputType:isS())
      assert(n.instance.module.outputType.over:is("Par"))
      return n.instance.module.outputType.over.over:canSafelyConvertTo(ty)
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

local UniformTopMT = {}
setmetatable(Uniform,UniformTopMT)

Uniform.const = J.memoize(
  function( value, X )
    assert( X==nil )
    return Uniform.new{kind="const",value=value,inputs={}}
  end)
  
UniformTopMT.__call = J.memoize(function(tab,arg,X)
  J.err(X==nil,"Uniform(): too many args")

  if Uniform.isUniform(arg) then
return arg
  elseif R.isPlainFunction(arg) then
    J.err(arg.inputType==types.Interface(),"Error creating uniform from function, input type is '"..tostring(arg.inputType).."', but should be Inil")
return Uniform.new{kind="apply",instance=arg:instantiate(),inputs={}}
  elseif type(arg)=="number" then
    J.err(arg~=math.inf,"Attempting to create a uniform out of an inf?")
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
