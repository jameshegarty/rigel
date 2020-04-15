local modules = require "generators.modules"
local IR = require("ir")
local types = require("types")
local S = require("systolic")
local J = require "common"
local err = J.err
local fpgamodules = require("fpgamodules")

local fixed = {}

local fixedFloatTerra
if terralib~=nil then fixedFloatTerra=require("fixed_float_terra") end

fixed.FLOAT = true 
fixed.DISABLE_SYNTH = false

local function getloc()
--  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline
  return debug.traceback()
end

function fixed.isFixedType(ty)
  return ty==types.float(32)
end

function fixed.expectFixed(ty)
  err( fixed.isFixedType(ty), "Expected fixed point type")
end

function fixed.extract(ty)
  return ty
end

local fixedASTFunctions = {}
setmetatable(fixedASTFunctions,{__index=IR.IRFunctions})

local fixedASTMT={__index = fixedASTFunctions,
__add=function(l,r)
  assert(fixed.isFixedType(l.type))
  assert(fixed.isFixedType(r.type))
  return fixed.new({kind="binop",op="+",inputs={l,r}, type=types.float(32), loc=getloc()})
end, 
__sub=function(l,r) 
  return fixed.new({kind="binop",op="-",inputs={l,r}, type=types.float(32), loc=getloc()})
 end,
__mul=function(l,r)
  --print("FLOAT_MUL",l,r)
  return fixed.new({kind="binop",op="*",inputs={l,r}, type=types.float(32), loc=getloc()})
 end,
__div=function(l,r) 
  return fixed.new({kind="binop",op="/",inputs={l,r}, type=types.float(32), loc=getloc()})
 end,
  __newindex = function(table, key, value)
                    error("Attempt to modify systolic AST node")
                  end}

local function boolbinop(op,l,r)
  return fixed.new({kind="binop",op=op,inputs={l,r}, type=types.bool(), loc=getloc()})
end

function fixedASTFunctions:gt(r)
  return boolbinop(">",self,r)
end

function fixedASTFunctions:lt(r)
  return boolbinop("<",self,r)
end

function fixedASTFunctions:ge(r)
  return boolbinop(">=",self,r)
end

function fixedASTFunctions:__and(r)
  err(self.type==types.bool(), "LHS should be bool")
  err(r.type==types.bool(), "RHS should be bool")

  return boolbinop("and",self,r)
end

function fixed.isAST(ast)
  return getmetatable(ast)==fixedASTMT
end

function fixed.new(tab)
  assert(type(tab)=="table")
  assert(type(tab.inputs)=="table")
  assert(#tab.inputs==J.keycount(tab.inputs))
  assert(type(tab.loc)=="string")
  assert(types.isType(tab.type))
  return setmetatable(tab,fixedASTMT)
end

function fixed.parameter( name, ty, X )
  assert(X==nil)
  err(types.isType(ty), "second arg must be type")
  return fixed.new{kind="parameter",name=name, type=ty,inputs={},loc=getloc()}
end

function fixed.tuple( tab )
  local inps = {}
  local ty = {}
  for k,v in pairs(tab) do 
    table.insert(inps,v) 
    table.insert(ty,v.type)
  end
  return fixed.new{kind="tuple", inputs=inps, type=types.tuple(ty), loc=getloc()}
end

function fixed.select( cond,a,b )
  err( cond.type==types.bool(), "cond should be bool")
  assert(a.type==b.type)
  return fixed.new{kind="select", inputs={cond,a,b}, type=a.type, loc=getloc()}
end

function fixed.array2d( tab, w, h )
  assert(type(w)=="number")
  assert(type(h)=="number" or h==nil)
  local inps = {}
  for k,v in pairs(tab) do 
    table.insert(inps,v) 
    assert(types.isType(v.type))
    assert(v.type==tab[1].type)
  end
  return fixed.new{kind="array2d", inputs=inps, type=types.array2d(tab[1].type,w,h), loc=getloc()}
end

function fixed.constant( value, signed, precision, exp )
  assert(exp==nil or exp==0)
  return fixed.new{kind="constant", value=value, type=types.float(32),inputs={},loc=getloc()}
end

function fixed.plainconstant( value, ty )
  assert(types.isType(ty))
  return fixed.new{kind="plainconstant", value=value, type=ty,inputs={},loc=getloc()}
end

function fixedASTFunctions:lift(exponant)
  err(fixed.isFixedType(self.type)==false, "expected non-fixed type: "..self.loc)
  return fixed.new{kind="lift",type=types.float(32), exp=exponant,inputs={self},loc=getloc()}
end

function fixedASTFunctions:normalize(precision)
  return self
end

-- throw out information!
function fixedASTFunctions:truncate(precision)
  return self
end

function fixedASTFunctions:pad(precision,exp)
  return self
end

-- removes exponant.
-- this may throw out data! if exp<0
function fixedASTFunctions:denormalize()
  return self
end

function fixedASTFunctions:reduceBits(msbs,lsbs)
  return self
end

function fixedASTFunctions:hist(name)
  return self
end

-- allowExp: should we allow you to lower something with a non-zero exp? or throw an error
function fixedASTFunctions:lower(ty)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  err( types.isType(ty) and fixed.isFixedType(ty)==false, "expected non-fixed type")

  return fixed.new{kind="lower", type=ty,inputs={self},loc=getloc()}
end

function fixedASTFunctions:toSigned()
  return self
end

function fixedASTFunctions:rshift(N)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  return fixed.new{kind="rshift", type=types.float(32),shift=N,inputs={self},loc=getloc()}
end

function fixedASTFunctions:lshift(N)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  return fixed.new{kind="lshift", type=types.float(32),shift=N,inputs={self},loc=getloc()}
end

function fixedASTFunctions:cast(to)
  assert( fixed.isFixedType(self.type)==false )
  assert(types.isType(to))
  return fixed.new{kind="cast",type=to, inputs={self}, loc=getloc()}
end

function fixedASTFunctions:disablePipelining()
  return fixed.new{kind="disablePipelining", type=self.type,inputs={self},loc=getloc()}
end

function fixedASTFunctions:index(ix,iy)
  err(self.type:isTuple() or self.type:isArray(), "attempting to index into something other than an array or tuple")
  err( type(ix)=="number", "ix must be number")
  err( iy==nil or type(iy)=="number", "iy must be number")

  local ty
  if self.type:isTuple() then
    assert(ix>=0 and ix<#self.type.list)
    ty = self.type.list[ix+1]
  elseif self.type:isArray() then
    err(ix>=0 and ix<(self.type:arrayLength())[1], "array idx out of bounds. is "..tostring(ix).." but should be < "..tostring((self.type:arrayLength())[1]))
    
    if iy==nil then iy=0 end
    assert(iy>=0 and iy<(self.type:arrayLength())[2])

    ty = self.type:arrayOver()
  end

  return fixed.new{kind="index", type=ty, ix=ix, iy=iy,inputs={self},loc=getloc()}
end

-- return the sign bit. true: positive (>=0), false: negative
function fixedASTFunctions:sign()
  return fixed.new{kind="sign", type=types.bool(), inputs={self}, loc=getloc()}
end

function fixedASTFunctions:addSign(inp)
  assert(false)
end

function fixedASTFunctions:abs()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return fixed.new{kind="abs", type=types.float(32), inputs={self}, loc=getloc()}
end

function fixedASTFunctions:neg()
  err(fixed.isFixedType(self.type), "expected fixed point type but is "..tostring(self.type)..": "..self.loc)
  return fixed.new{kind="neg", type=self.type, inputs={self}, loc=getloc()}
end

function fixedASTFunctions:invert()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return fixed.new{kind="invert", type=self.type, inputs={self}, loc=getloc()}
end

function fixedASTFunctions:sqrt()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return fixed.new{kind="sqrt", type=self.type, inputs={self}, loc=getloc()}
end

function fixedASTFunctions:__not()
  assert(self.type==types.bool())
  return fixed.new{kind="not", type=types.bool(), inputs={self}, loc=getloc()}
end

function fixedASTFunctions:isSigned()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return self.type.list[1]:isInt()
end

function fixedASTFunctions:exp()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return 32
end

function fixedASTFunctions:precision()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return 32
end

function fixedASTFunctions:cost() return 0 end

function fixedASTFunctions:toSystolic(inp)
  local instances = {}
  local res

  if fixed.DISABLE_SYNTH==false then
  res = self:visitEach(
    function( n, args )
      local res
      if n.kind=="parameter" then
        res = inp
      elseif n.kind=="lift" then
        if (n.inputs[1].type:isInt() and n.inputs[1].type.precision<=32) or (n.inputs[1].type:isUint() and n.inputs[1].type.precision<32) then

          local inparg = args[1]
          if n.inputs[1].type:isUint() then
            inparg = S.cast(inparg,types.int(32))
          elseif n.inputs[1].type:isInt() and n.inputs[1].type.precision<32 then
            inparg = S.cast(inparg,types.int(32))
          end

          local I = fpgamodules.intToFloat:instantiate("INTTOFLOAT"..tostring(#instances))
          table.insert(instances,I)
          res = I:process(inparg)
        else
          print("LIFT"..tostring(n.inputs[1].type))
          assert(false)
        end
      elseif n.kind=="rshift" then
        if n.type:isUint() then
          res = S.rshift(arg[1],n.shift)
        elseif n.type:isFloat() then
          local I = fpgamodules.multiply(types.float(32),types.float(32),types.float(32)):instantiate("MUL_FLOAT"..tostring(#instances))
          table.insert(instances,I)
          res = I:process(S.tuple{args[1],S.constant(1/math.pow(2,n.shift),types.float(32))})
        else
          print("TY",n.type)
          assert(false)
        end
      elseif n.kind=="binop" then
        if n.inputs[1].type==types.float(32) and n.inputs[2].type==types.float(32) and (n.type==types.float(32)  or n.type==types.bool()) then

          local opremap={["*"]="mul",["+"]="add",["-"]="sub",[">"]="gt",["<"]="lt",["<="]="lte",[">="]="gte"}

          if opremap[n.op]~=nil then
            local I = fpgamodules.binop(opremap[n.op],types.float(32),types.float(32),n.type):instantiate(opremap[n.op].."_FLOAT"..tostring(#instances))
            table.insert(instances,I)
            res = I:process(S.tuple{args[1],args[2]})
          else
            print("<MOP",n.op)
            assert(false)
          end
        elseif n.inputs[1].type==types.bool() and n.inputs[2].type==types.bool() then
          if n.op=="and" then
            return S.__and(args[1],args[2])
          else
            assert(false)
          end
        else
          print("OP",n.op)
          assert(false)
        end
      elseif n.kind=="index" then
        res = S.index( args[1], n.ix, n.iy)
      elseif n.kind=="sqrt" then
        local I = fpgamodules.floatSqrt:instantiate("FLOAT_SQRT"..tostring(#instances))
        table.insert(instances,I)
        res = I:process(args[1])
      elseif n.kind=="not" then
        res = S.__not(args[1])
      elseif n.kind=="neg" then
        local I = fpgamodules.binop("sub",types.float(32),types.float(32),n.type):instantiate("neg_FLOAT"..tostring(#instances))
        table.insert(instances,I)
        res = I:process(S.tuple{S.constant(0,types.float(32)),args[1]})
      elseif n.kind=="invert" then
        local I = fpgamodules.floatInvert:instantiate("FLOAT_INV"..tostring(#instances))
        table.insert(instances,I)
        res = S.select(S.eq(args[1],S.constant(0,types.float(32))),S.constant(0,types.float(32)),I:process(args[1]))
      elseif n.kind=="tuple" then
        res = S.tuple(args)
      elseif n.kind=="constant" then
        res = S.constant( n.value, fixed.extract(n.type) )
      elseif n.kind=="plainconstant" then
        res = S.constant( n.value, n.type )
      elseif n.kind=="select" then
        res = S.select(args[1],args[2],args[3])
      elseif n.kind=="lower" then
        if (n.type:isUint() and n.type.precision<32) or (n.type:isInt() and n.type.precision<=32) then
          local I = fpgamodules.floatToInt:instantiate("FLOATTOINT"..tostring(#instances))
          table.insert(instances,I)
          res = I:process(args[1])

          if n.type:isUint() and n.type.precision<32 then
            res = S.cast(res,n.type)
          elseif n.type:isInt() and n.type.precision<32 then
            res = S.cast(res,n.type)
          end
        else
          assert(false)
        end
      elseif n.kind=="array2d" then
        local inp = {}
        for k,v in pairs(args) do inp[k] = v end
        res = S.cast(S.tuple(inp),n.type)
      elseif n.kind=="cast" then
        res = S.cast(args[1],n.type)
      elseif n.kind=="disablePipelining" then
        res = args[1]:disablePipelining()
        --res = args[1]
      else
        err(false,"missing? "..n.kind)
      end

      return res
    end)
  else
    self:visitEach(
      function( n, args )
        local res
        if n.kind=="parameter" then
          inp = S.parameter(n.name, n.type)
          res = inp
        end
      end)
  end

  if res==nil then
    if self.type:isArray() then
      res = S.constant(J.broadcast(0,self.type:channels()),self.type)
    elseif self.type:isTuple() then
      res = S.constant(J.broadcast(0,#self.type.list),self.type)
    elseif self.type:isBool() then
      res = S.constant(false,self.type)
    else
      res = S.constant(0,self.type)
    end
  end

  return res, instances
end

local hists = {}
function fixed.printHistograms()
  for k,v in pairs(hists) do v() end
end

function fixedASTFunctions:toRigelModule(name,X)
  assert(type(name)=="string")
  assert(X==nil)

  local inpType
  self:visitEach( function( n, args ) if n.kind=="parameter" then inpType=n.type end end)

  local res = modules.lift( name, inpType, self.type, nil, 
    function(inp)
      local out, instances = self:toSystolic(inp)
      return out, instances
    end,
    function() return fixedFloatTerra.tfn(self) end)

  return res
end

return fixed
