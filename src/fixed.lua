local RM = require "modules"
local IR = require("ir")
local types = require("types")
local S = require("systolic")
local fpgamodules = require("fpgamodules")
local J = require "common"
local err = J.err

local fixed={}

local fixedTerra
if terralib~=nil then fixedTerra=require("fixed_terra") end

--local fixed = {}
-- use Xilinx deeply pipelined multipliers instead of regular multipliers
fixed.DEEP_MULTIPLY = false

local function getloc()
--  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline
  return debug.traceback()
end

function fixed.isFixedType(ty)
  assert(types.isType(ty))
  return ty:isNamed() and ty.generator=="fixed"
end

function fixed.expectFixed(ty)
  err( fixed.isFixedType(ty), "Expected fixed point type but was "..tostring(ty))
end

function fixed.extract(ty)
  if fixed.isFixedType(ty) then
    return ty.structure
  end
  return ty
end

function fixed.extractExp(ty)
  fixed.expectFixed(ty)
  return ty.params.exp
end

function fixed.extractPrecision(ty)
  fixed.expectFixed(ty)
  return ty.params.precision
end

function fixed.extractSigned(ty)
  fixed.expectFixed(ty)
  return ty.params.signed
end

fixed.type = J.memoize(function( signed, precision, exp )
  assert(type(signed)=="boolean")
  assert(type(precision)=="number")
  assert(type(exp)=="number")
  err(precision>=0, "precision should be >=0")

  local params = {signed=signed, precision=precision,exp=exp}
  local name = "uint"..tostring(precision).."_"..tostring(exp)
  local struct = types.uint(precision)
  if signed then
    name = "int"..tostring(precision).."_"..tostring(exp)
    struct = types.int(precision)
  end
  
  return types.named( name, struct, "fixed", params )
end)

local fixedASTFunctions = {}
setmetatable(fixedASTFunctions,{__index=IR.IRFunctions})

fixedASTMT={__index = fixedASTFunctions,
__add=function(l,r)
  if (l.type:isInt() or l.type:isUint()) and (r.type:isInt() or r.type:isUint()) then
    local ty
    if l.type==r.type then ty=l.type -- keep constness
    elseif l.type:stripConst()==r.type:stripConst() then ty=l.type:stripConst() 
    else assert(false) end
    return fixed.new({kind="binop",op="+",inputs={l,r}, type=ty, loc=getloc()})
  else
    err(l:isSigned()==r:isSigned(), "+: sign must match")

    if l:exp()>r:exp() then
      l = l:pad(l:precision()+(l:exp()-r:exp()),r:exp())
    elseif r:exp()>l:exp() then
      r = r:pad(r:precision()+(r:exp()-l:exp()),l:exp())
    end

    err(l:exp()==r:exp(), "+: exp must match")

    local p = math.max(l:precision(),r:precision())+1
    return fixed.new({kind="binop",op="+",inputs={l,r}, type=fixed.type( l:isSigned(), p, l:exp() ), loc=getloc()})
  end
end, 
__sub=function(l,r) 
  if l.type:isInt() and r.type:isInt() then
    local ty
    if l.type==r.type then ty=l.type -- keep constness
    elseif l.type:stripConst()==r.type:stripConst() then ty=l.type:stripConst() 
    else assert(false) end

    return fixed.new({kind="binop",op="-",inputs={l,r}, type=ty, loc=getloc()})
  else
    err(l:isSigned() and r:isSigned(), "-: must be signed")
    err(l:exp()==r:exp(), "-: exp must match")

    if l:exp()>r:exp() then
      l = l:pad(l:precision()+(l:exp()-r:exp()),r:exp())
    elseif r:exp()>l:exp() then
      r = r:pad(r:precision()+(r:exp()-l:exp()),l:exp())
    end

    local p = math.max(l:precision(),r:precision())+1
    return fixed.new({kind="binop",op="-",inputs={l,r}, type=fixed.type( true, p, l:exp() ), loc=getloc()})
  end
 end,
__mul=function(l,r) 
  err(l:isSigned() == r:isSigned(), "*: lhs/rhs sign must match but is ("..tostring(l:isSigned())..","..tostring(r:isSigned())..")")
  local exp = l:exp() + r:exp()

  local p = l:precision() + r:precision()
  local ty = fixed.type( l:isSigned(), p, l:exp()+r:exp() )
  return fixed.new({kind="binop",op="*",inputs={l,r}, type=ty, loc=getloc()})
 end,
  __newindex = function(table, key, value)
                    error("Attempt to modify systolic AST node")
                  end}

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

function fixed.parameter( name, ty )
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
  assert(a.type:stripConst()==b.type:stripConst())
  return fixed.new{kind="select", inputs={cond,a,b}, type=a.type:stripConst(), loc=getloc()}
end

function fixed.array2d( tab, w, h )
  local inps = {}
  for k,v in pairs(tab) do 
    table.insert(inps,v) 
    err(v.type:stripConst()==tab[1].type:stripConst(),"array2d: types don't match, "..tostring(v.type).." and "..tostring(tab[1].type))
  end
  return fixed.new{kind="array2d", inputs=inps, type=types.array2d(tab[1].type,w,h), loc=getloc()}
end

function fixed.constant( value, signed, precision, exp )
  assert(type(value)=="number")
  assert(value==math.floor(value))

  if signed==nil then 
    signed = (value<0) 
  end

  if precision==nil then 
    precision = math.ceil(math.log(value)/math.log(2))+1 
    if signed then precision = precision + 1 end
  end

  if exp==nil then exp=0 end

  err(value < math.pow(2,precision-J.sel(signed,1,0)), "const value out of range, "..tostring(value).." in precision "..tostring(precision).." signed:"..tostring(signed))

  return fixed.new{kind="constant", value=value, type=fixed.type(signed,precision,exp):makeConst(),inputs={},loc=getloc()}
end

function fixed.plainconstant( value, ty )
  err(types.isType(ty), "second argument to plainconstant must be a type")
  return fixed.new{kind="plainconstant", value=value, type=ty:makeConst(),inputs={},loc=getloc()}
end

function fixedASTFunctions:lift(exponant)
  err(fixed.isFixedType(self.type)==false, "expected non-fixed type: "..self.loc)
  if self.type:isUint() then
    local ty = fixed.type(false,self.type.precision,exponant)
    return fixed.new{kind="lift",type=ty,inputs={self},loc=getloc()}
  else
    print("Could not lift type "..tostring(self.type))
    assert(false)
  end
end

-- Throws out OR adds information, to the LSBs
function fixedASTFunctions:normalize(precision)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  local expshift = self:precision()-precision
  local ty = fixed.type(self:isSigned(), precision, self:exp()+expshift)
  return fixed.new{kind="normalize", type=ty,inputs={self},loc=getloc()}
end

-- throw out information! from the MSBs
function fixedASTFunctions:truncate(precision)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  local ty = fixed.type(self:isSigned(), precision, self:exp())
  return fixed.new{kind="truncate", type=ty,inputs={self},loc=getloc()}
end

-- pad to a target precision and exp
function fixedASTFunctions:pad(precision,exp)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  err( exp<=self:exp(), "pad shouldn't make exp larger") -- making exponant larger => bits shift right
  err( precision>=self:precision()+(self:exp()-exp), "pad shouldn't throw out data")
  local ty = fixed.type(self:isSigned(), precision, exp)
  return fixed.new{kind="pad", type=ty,inputs={self},loc=getloc()}
end

-- removes exponant.
-- this may throw out data! if exp<0
function fixedASTFunctions:denormalize()
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  local prec = self:precision()+self:exp()
  err( prec>0, "denormalize: this value is purely fractional! all data will be lost")
  return fixed.new{kind="denormalize", type=fixed.type(self:isSigned(), prec, 0),inputs={self},loc=getloc()}
end

-- remove 'msbs' bits of the MSBs, 'lsbs' bits of the LSBs
function fixedASTFunctions:reduceBits(msbs,lsbs)
  assert(type(msbs)=="number")
  assert(type(lsbs)=="number")
  if msbs >= self:precision() then msbs = self:precision()-1 end
  if msbs+lsbs >= self:precision() then lsbs = self:precision()-msbs-1 end

  assert(msbs+lsbs<self:precision())

  local OT = self:normalize(self:precision()-lsbs):truncate(self:precision()-lsbs-msbs)
  assert(OT:precision()==self:precision()-lsbs-msbs)
  return OT
end

function fixedASTFunctions:hist(name)
  assert(type(name)=="string")
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)

  return fixed.new{kind="hist", type=self.type, name=name,inputs={self},loc=getloc()}
end

-- allowExp: should we allow you to lower something with a non-zero exp? or throw an error
function fixedASTFunctions:lower(allowExp)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)

  if allowExp~=true then err( self:exp()==0, "attempting to lower a value with nonzero exp") end

  return fixed.new{kind="lower", type=fixed.extract(self.type),inputs={self},loc=getloc()}
end

function fixedASTFunctions:disablePipelining()
  return fixed.new{kind="disablePipelining", type=self.type,inputs={self},loc=getloc()}
end

function fixedASTFunctions:toSigned()
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  if self:isSigned() then
return self
  end

  local ty = fixed.type( true, self:precision()+1, self:exp() )
  return fixed.new{kind="toSigned", type=ty, inputs={self}, loc=getloc() }
end

function fixedASTFunctions:rshift(N)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  err( type(N)=="number", "rshift input must be number" )
  err( N>0, "rshift input must be >0")
  
  return fixed.new{kind="rshift", type=fixed.type(self:isSigned(), self:precision(), self:exp()-N),shift=N,inputs={self},loc=getloc()}
end

function fixedASTFunctions:lshift(N)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  return fixed.new{kind="lshift", type=fixed.type(self:isSigned(), self:precision(), self:exp()+N),shift=N,inputs={self},loc=getloc()}
end

-- cast to INTEGER.FRACTIONAL format
-- extends or clamps as necessary
-- precision = INTEGER+FRACTIONAL
function fixedASTFunctions:castToIF(INT,FRAC)
  err( fixed.isFixedType(self.type), "NYI - castToIF only works on fixed types" )
  err(type(INT)=="number","INT input to castToIF must be number")
  err(type(FRAC)=="number","FRAC input to castToIF must be number")
  err(INT>=0,"INT input to castToIF must be >=0")
  err(FRAC>=0,"FRAC input to castToIF must be >=0")
  
  local out
  
  -- first deal with MSBs
  local currentINT = self:precision()+self:exp()
  print("castToIF: currentINT",currentINT,"currentFRAC",-self:exp(),"targetINT",INT,"targetFRAC",FRAC)
  
  if currentINT<INT then
    out = self:pad(self:precision()+INT-currentINT,self:exp())
    -- no reason to add more bits than we need
    --out = self
  elseif currentINT>INT then
    --assert(false)
    out = self:reduceBits(currentINT-INT,0)
  end

  local currentINT = out:precision()+out:exp()
  print("CURRENTINT",currentINT,"CURRENTFRAC",-out:exp())

  local currentFRAC = -out:exp()

  if currentFRAC<FRAC then
    assert(false)
    --print("IF",INT,FRAC,out:precision())
    --out = out:pad(INT+FRAC,-FRAC)
  elseif currentFRAC>FRAC then
    --assert(false)
    print("REDFRAC",out:exp())
    out = out:reduceBits(0,currentFRAC-FRAC)
    print("REDFRAC",out:exp())
  end

  assert(out:precision()==INT+FRAC)
  assert(out:exp()==-FRAC)
  --local currentINT = out:precision()+out:exp()
  --assert(currentINT<=INT)

  return out
end

function fixedASTFunctions:cast(to)
  assert( fixed.isFixedType(self.type)==false )
  assert(types.isType(to))
  return fixed.new{kind="cast",type=to, inputs={self}, loc=getloc()}
end

--[=[
function fixedASTFunctions:cast(to)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  err( fixed.isFixedType(to), "expected cast to fixed type: "..self.loc)

  err( self:isSigned()==fixed.extractSigned(to), "sign must match")
  
  print("CAST",self.type, to)

  local res = self
  if fixed.extractExp(to)<res:exp() then
    res = res:rshift( res:exp() - fixed.extractExp(to) )
  end

  assert( res:exp() == fixed.extractExp(to) )
 
  if fixed.extractPrecision(to) < res:precision() then
    res = res:truncate(fixed.extractPrecision(to))
  elseif fixed.extractPrecision(to) > res:precision() then
    res = res:pad(fixed.extractPrecision(to),)
  end
  
  err( res.type==to, "fixed cast failed, from "..tostring(self.type).." to "..tostring(to))

  return res
end
]=]

local function boolbinop(op,l,r)
  if (l.type:isInt() or l.type:isUint()) and (r.type:isInt() or r.type:isUint()) then
    local ty
    if l.type==r.type then ty=l.type -- keep constness
    elseif l.type:stripConst()==r.type:stripConst() then ty=l.type:stripConst() 
    else assert(false) end
    return fixed.new({kind="binop",op=op,inputs={l,r}, type=types.bool(), loc=getloc()})
  else
    err(l:isSigned()==r:isSigned(), op..": sign must match")

    if l:exp()>r:exp() then
      l = l:pad(l:precision()+(l:exp()-r:exp()),r:exp())
    elseif r:exp()>l:exp() then
      r = r:pad(r:precision()+(r:exp()-l:exp()),l:exp())
    end

    err(l:exp()==r:exp(), op..": exp must match")

    local p = math.max(l:precision(),r:precision())+1
    return fixed.new({kind="binop",op=op,inputs={l,r}, type=types.bool(), loc=getloc()})
  end

end

function fixedASTFunctions:gt(r) return boolbinop(">",self,r) end
function fixedASTFunctions:ge(r) return boolbinop(">=",self,r) end
function fixedASTFunctions:lt(r) return boolbinop("<",self,r) end
function fixedASTFunctions:le(r) return boolbinop("<=",self,r) end

local function boolboolbinop(op,l,r)
  err(l.type:isBool() and r.type:isBool(), "bool-bool binop "..op.." expects bool input")

  return fixed.new{kind="binop",op=op,inputs={l,r}, type=types.bool(), loc=getloc()}
end


function fixedASTFunctions:__and(r) return boolboolbinop("and",self,r) end
function fixedASTFunctions:__or(r) return boolboolbinop("or",self,r) end

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
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  err( self:isSigned(), "getting the sign of a unsigned type is futile")
  return fixed.new{kind="sign", type=types.bool(), inputs={self}, loc=getloc()}
end

function fixedASTFunctions:addSign(inp)
  err( fixed.isAST(inp), "input must be fixed AST" )
  err( inp.type==types.bool(), "input must be bool")
  err( self:isSigned()==false, "attempting to add sign to something that alreayd has a sign")
  return fixed.new{kind="addSign", type=fixed.type(true,self:precision()+1,self:exp()), inputs={self,inp}, loc=getloc()}
end

function fixedASTFunctions:abs()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  err( self:isSigned(), "abs value of a non-signed type is futile")

  -- we actually _CANT_ throw out data here. signed number lose one value
  -- (either the max or the min). But since one of the max or min remain,
  -- we can't represent this without the full # of bits.
  local ty = fixed.type(false, self:precision(), self:exp())
  return fixed.new{kind="abs", type=ty, inputs={self}, loc=getloc()}
end


function fixedASTFunctions:__not()
  err( self.type==types.bool(), "input to not must be bool" )
  return fixed.new{kind="not",type=types.bool(),inputs={self},loc=getloc()}
end

function fixedASTFunctions:neg()
  --err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  err( self.type:isInt() or self:isSigned(), "neg value of a non-signed type is futile")
  return fixed.new{kind="neg", type=self.type, inputs={self}, loc=getloc()}
end

-- returns a floating exponant for this value, where the mantissa is stored in 'prec' bits.
function fixedASTFunctions:msb(prec)
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  err( self:isSigned()==false, "msb with signed value")

  return fixed.new{kind="msb", type=types.int(8), precision = prec, inputs={self}, loc=getloc()}
end

function fixedASTFunctions:float(floatexp, prec)
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  err( floatexp.type==types.int(8), "float exp should be int8")
  err( type(prec)=="number", "prec should be number" )
  assert(prec>0)

  local maxexp = self:exp()+self:precision()-prec
  local minexp = self:exp()
  assert(maxexp>minexp)

  local res = fixed.new{kind="float", type=types.uint(prec), inputs={self,floatexp}, minexp=minexp, maxexp=maxexp, loc=getloc()}
  return res, minexp, maxexp
end

function fixedASTFunctions:liftFloat(minExp, maxExp, floatExp)
  err( floatExp.type==types.int(8), "float exp should be int8")
  assert(maxExp>minExp)
  assert(self.type:isUint())
  local ty = fixed.type(false,self.type.precision+maxExp-minExp,minExp)
  local res = fixed.new{kind="liftFloat", type=ty, inputs={self,floatExp}, loc=getloc(), minexp = minExp, maxexp = maxExp}
  return res
end

function fixedASTFunctions:isSigned()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return self.type.params.signed
end

function fixedASTFunctions:exp()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return self.type.params.exp
end

function fixedASTFunctions:precision()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return self.type.params.precision
end

function fixedASTFunctions:cost()
  local totalCost = 0
  self:visitEach(
    function( n, args )
      local cost
      if n.kind=="parameter" or n.kind=="rshift"  or n.kind=="truncate"  or n.kind=="lift"  or n.kind=="lower"  or n.kind=="constant" or n.kind=="plainconstant" or n.kind=="normalize" or n.kind=="denormalize" or n.kind=="hist" or n.kind=="index" or n.kind=="toSigned" or n.kind=="tuple" or n.kind=="array2d" or n.kind=="pad" or n.kind=="disablePipelining" then
        cost = 0
      elseif n.kind=="abs" or n.kind=="neg" or n.kind=="sign" or n.kind=="addSign" or n.kind=="select" then
        cost = n:precision()
      elseif n.kind=="msb" or n.kind=="float" or n.kind=="liftFloat" then
        cost = n:precision()*2
      elseif n.kind=="binop" then
        if n.op=="+" or n.op=="-" then
          cost = n:precision()
        elseif n.op=="*" then
          cost = 2*n:precision()
        else
          assert(false)
        end
      else
        print(n.kind)
        assert(false)
      end

      assert(type(cost)=="number")
      totalCost = totalCost + cost
    end)

  return totalCost
end

function fixedASTFunctions:toSystolic(inp)
  local instances = {}
  --local inp
  local res = self:visitEach(
    function( n, args )
      local res
      if n.kind=="parameter" then
        --inp = S.parameter(n.name, n.type)
        res = inp
        if fixed.isFixedType(n.type) then
          -- remove wrapper
          --res = S.index(res,0)
          res = S.cast(res,n.type.structure)
        end
      elseif n.kind=="binop" then

        if fixed.DEEP_MULTIPLY and fixed.isFixedType(n.type) and n:precision()>=20 and n.op=="*" and 
          n.inputs[1].type:const()==false and
          n.inputs[2].type:const()==false then
          local I = fpgamodules.multiply(fixed.extract(n.inputs[1].type),fixed.extract(n.inputs[2].type),fixed.extract(n.type)):instantiate("UNNAMEDINST"..tostring(#instances))
          table.insert(instances,I)
          res = I:process(S.tuple{args[1],args[2]})
        else
          if n.op==">" then
            res = S.gt(args[1],args[2])
          elseif n.op==">=" then
            res = S.ge(args[1],args[2])
          elseif n.op=="<" then
            res = S.lt(args[1],args[2])
          elseif n.op=="<=" then
            res = S.le(args[1],args[2])
          elseif n.op=="and" then
            res = S.__and(args[1],args[2])
          elseif n.op=="or" then
            res = S.__or(args[1],args[2])
          elseif n.op=="+" or n.op=="-" or n.op=="*" then
            local l = S.cast(args[1], fixed.extract(n.type))
            local r = S.cast(args[2], fixed.extract(n.type))
            
            if n.op=="+" then res = l+r
            elseif n.op=="-" then res = l-r
            elseif n.op=="*" then res = l*r
            else
              assert(false)
            end
            
            if fixed.isFixedType(n.type) and n:precision()>20 then
              --print("riduclous binop "..tostring(n.inputs[1].type).." "..tostring(n.inputs[2].type).." "..tostring(n.type)..n.loc)
            end
          else
            err(false,"internal error, fixed.lua, unknown binop "..n.op)
          end
        end

      elseif n.kind=="rshift" or n.kind=="lshift" then
        --res = S.rshift(args[1],S.constant( n.shift, fixed.extract(n.inputs[1].type)))
        res = args[1]
      elseif n.kind=="truncate" then
      	assert(fixed.extract(n.type):verilogBits()<=fixed.extract(n.inputs[1].type):verilogBits())
        res = S.cast(args[1],fixed.extract(n.type))
      elseif n.kind=="lift" or n.kind=="lower" then
        -- don't actually do anything: we only add the wrapper at the very end
        res = args[1]
      elseif n.kind=="constant" then
        res = S.constant( n.value, fixed.extract(n.type) )
      elseif n.kind=="plainconstant" then
        res = S.constant( n.value, n.type )
      elseif n.kind=="normalize" or n.kind=="denormalize" then
        local dp = n.inputs[1]:precision()-n:precision()
        assert(math.abs(dp)<255) -- for the rshift
        if dp==0 then
          res = args[1]
        elseif dp>0 then
           res = S.rshift(args[1], S.constant(dp, types.uint(8)) )
          res = S.cast(res,fixed.extract(n.type))
        elseif dp<0 then
          -- make larger
          res = S.cast( args[1], fixed.extract(n.type) )
          res = S.lshift( res, S.constant(-dp, types.uint(8)) )
        else
          assert(false)
        end
      elseif n.kind=="hist" then
        res = args[1] -- cpu only
      elseif n.kind=="index" then
        res = S.index( args[1], n.ix, n.iy)
        if fixed.isFixedType(n.type) then
          -- remove wrapper
          --res = S.index(res,0)
          res = S.cast(res,n.type.structure)
        end
      elseif n.kind=="toSigned" then
        res = S.cast( args[1], fixed.extract(n.type) )
      elseif n.kind=="abs" then
        res = S.abs( args[1] )
        res = S.cast( res, fixed.extract(n.type) )
      elseif n.kind=="not" then
        res = S.__not(args[1])
      elseif n.kind=="neg" then
        res = S.neg(args[1])
      elseif n.kind=="sign" then
        res = S.ge(args[1],S.constant(0,fixed.extract(n.inputs[1].type)))
      elseif n.kind=="tuple" then
        res = S.tuple(args)
      elseif n.kind=="array2d" then
        local inp = args
        if fixed.isFixedType(n.inputs[1].type) then
          for k,v in pairs(args) do
            --inp[k] = S.tuple{v,S.constant(0, self.inputs[1].type.list[2])}
            inp[k] = S.cast(v,self.inputs[1].type)
          end
        end

        res = S.cast(S.tuple(inp),n.type)
      elseif n.kind=="addSign" then
        --local tsign = S.ge(args[1],S.constant(0,fixed.extract(n.inputs[1].type)))
        res = S.cast(args[1], fixed.extract(n.type) )
        --res = S.select(S.eq(tsign,args[2]),res,S.neg(res))
        res = S.select(args[2],res,S.neg(res))
      elseif n.kind=="msb" then
        local bits = n.inputs[1]:precision()
        local minexp = n.inputs[1]:exp()
        local tab = {}
        for i=0,bits-1 do
          local bittrue = S.bitSlice(args[1],i,i)
          bittrue = S.cast(bittrue,types.bool())
          table.insert(tab, S.tuple{bittrue,S.constant(i+minexp-n.precision+1,types.int(8))} )
        end

        local out = J.foldt(tab,function(l,r) return S.select(S.index(r,0),r,l) end, 'X')

        res = S.select(S.eq(args[1],S.constant(0,fixed.extract(n.inputs[1].type))),S.constant(minexp,types.int(8)),S.index(out,1))
      elseif n.kind=="float" then
        local lshiftamt = S.cast(S.constant(n.minexp,types.int(8))-args[2],types.uint(8))
        local lshift = S.lshift(args[1],lshiftamt)

        local rshiftamt = S.cast(args[2]-S.constant(n.minexp,types.int(8)), types.uint(8))
        local rshift = S.rshift(args[1],rshiftamt)

        res = S.select(S.lt(args[2],S.constant(n.minexp,types.int(8))),lshift,rshift)
        --res = S.select(S.eq(args[2],S.constant(0,types.int(8))),args[1],res)
        res = S.cast(res,n.type)
      elseif n.kind=="liftFloat" then
        res = S.cast(args[1], fixed.extract(n.type))
        local lshiftamt = S.cast(args[2]-S.constant(n.minexp,types.int(8)), types.uint(8))
        res = S.lshift(res, lshiftamt)
      elseif n.kind=="pad" then
        local lshift = n.inputs[1]:exp() - n:exp()
        assert(lshift>=0)
        res = S.lshift(S.cast(args[1],fixed.extract(n.type)),S.constant(lshift,fixed.extract(n.type)))
      elseif n.kind=="select" then
        res = S.select(args[1],args[2],args[3])
      elseif n.kind=="cast" then
        res = S.cast(args[1],n.type)
      elseif n.kind=="disablePipelining" then
        res = args[1]:disablePipelining()
      else
        print(n.kind)
        assert(false)
      end

      return res
    end)

  if fixed.isFixedType(self.type) then
    --local c = S.constant(0, self.type.list[2])
    --res = S.tuple{res,c}
    res = S.cast(res,self.type)
  end

  return res, instances
end

fixed.hists = {}
function fixed.printHistograms()
  for k,v in pairs(fixed.hists) do v() end
end


function fixedASTFunctions:toRigelModule(name,X)
  assert(type(name)=="string")
  assert(X==nil)

  local inpType
  self:visitEach( function( n, args ) if n.kind=="parameter" then inpType=n.type end end)

  return RM.lift( name, inpType, self.type, 0, 
    function(inp)
      local out, instances = self:toSystolic(inp)
      return out, instances
    end,
    function()
      return fixedTerra.toDarkroom(self)
    end)
end

return fixed
