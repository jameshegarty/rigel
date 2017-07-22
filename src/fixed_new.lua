local RM = require "modules"
local IR = require("ir")
local types = require("types")
local S = require("systolic")
local Ssugar = require("systolicsugar")
local fpgamodules = require("fpgamodules")
local R = require("rigel")
local J = require "common"
local err = J.err
local fixed={}

local fixedTerra
if terralib~=nil then fixedTerra=require("fixed_new_terra") end

--local fixed = {}
-- use Xilinx deeply pipelined multipliers instead of regular multipliers
fixed.DEEP_MULTIPLY = false

local function getloc()
--  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline
  return debug.traceback()
end

--function fixed.isFixedType(ty)
--  assert(types.isType(ty))
--  if ty:isUint()
--end

function fixed.expectFixed(ty)
  err( fixed.isFixedType(ty), "Expected fixed point type")
end

fixed.type = J.memoize(function( signed, precision, exp )
  assert(type(signed)=="boolean")
  assert(type(precision)=="number")
  assert(type(exp)=="number")
  err(precision>=0, "precision should be >=0")

  if exp==0 then
    -- just use regular types
    if signed then
      return types.int(precision)
    else
      return types.uint(precision)
    end
  else
    local params = {signed=signed, precision=precision,exp=exp}
    local name = "uint"..tostring(precision).."_"..tostring(exp)
    local struct = types.uint(precision)
    if signed then
      name = "int"..tostring(precision).."_"..tostring(exp)
      struct = types.int(precision)
    end

    return types.named( name, struct, "fixed", params )
  end
end)

local fixedNewASTFunctions = {}
setmetatable(fixedNewASTFunctions,{__index=IR.IRFunctions})

fixedNewASTMT={__index = fixedNewASTFunctions,
__add=function(l,r)
  if l:isSigned()~=r:isSigned() or
    l:exp() ~= r:exp() or
    l:precision() ~= r:precision() then
    err(false, "Error, fixed add, input types don't match: "..tostring(l.type).." "..tostring(r.type))
  end

  local p = math.max(l:precision(),r:precision())+1
  return fixed.new({kind="binop",op="+",inputs={l,r}, type=fixed.type( l:isSigned(), p, l:exp() ), loc=getloc()})
end, 
__sub=function(l,r) 
  if l:isSigned()~=r:isSigned() or
    l:exp() ~= r:exp() or
    l:precision() ~= r:precision() then
    err(false, "Error, fixed sub, input types don't match: "..tostring(l.type).." "..tostring(r.type))
  end

  local p = math.max(l:precision(),r:precision())+1
  return fixed.new({kind="binop",op="-",inputs={l,r}, type=fixed.type( true, p, l:exp() ), loc=getloc()})
 end,
__mul=function(l,r) 
  err(l:isSigned() == r:isSigned(), "Fixed *: lhs/rhs sign must match but is ("..tostring(l.type)..","..tostring(r.type)..")")
  local exp = l:exp() + r:exp()

  local p = l:precision() + r:precision()
  local ty = fixed.type( l:isSigned(), p, l:exp()+r:exp() )
  return fixed.new({kind="binop",op="*",inputs={l,r}, type=ty, loc=getloc()})
 end,
  __newindex = function(table, key, value)
                    error("Attempt to modify systolic AST node")
                  end}

function fixed.isAST(ast)
  return getmetatable(ast)==fixedNewASTMT
end

__FIXED_NAME_CNT = 0
function fixed.new(tab)
  assert(type(tab)=="table")
  assert(type(tab.inputs)=="table")
  assert(#tab.inputs==J.keycount(tab.inputs))
  assert(type(tab.loc)=="string")
  assert(types.isType(tab.type))

  if tab.name==nil then
    tab.name="fixed"..tostring(__FIXED_NAME_CNT)
    __FIXED_NAME_CNT = __FIXED_NAME_CNT + 1
  end
  
  return setmetatable(tab,fixedNewASTMT)
end

function fixed.parameter( name, ty )
  err(types.isType(ty), "second arg must be type")
  return fixed.new{kind="parameter",name=name, type=ty,inputs={},loc=getloc()}
end

function fixed.constant( value )
  err(type(value)=="number" or type(value)=="boolean","fixed.constant must be number or bool")

  if type(value)=="boolean" then
    return fixed.new{kind="constant", value=value, type=types.bool():makeConst(), inputs={},loc=getloc()}
  else
    err(value==math.floor(value),"fixed.constant: non integer value!")
  
    local signed = (value<0) 
  
    local precision = math.ceil(math.log(math.abs(value))/math.log(2))
    if signed then precision = precision + 1 end
    if value==0 then precision=1 end -- special case
    if signed==false and math.pow(2,precision)==value then
      -- 2^7==128, but 128 needs 8 bits...
      precision = precision + 1
    end

    local exp = 0

    --err(value < math.pow(2,precision-sel(signed,1,0)), "const value out of range, "..tostring(value).." in precision "..tostring(precision).." signed:"..tostring(signed))

    return fixed.new{kind="constant", value=value, type=fixed.type(signed,precision,exp):makeConst(),inputs={},loc=getloc()}
  end
end

--[=[
function fixedNewASTFunctions:toFixed()
  err(fixed.isFixedType(self.type)==false, "expected non-fixed type: "..self.loc)
  if self.type:isUint() then
    local ty = fixed.type(false,self.type.precision,0)
    return fixed.new{kind="lift",type=ty,inputs={self},loc=getloc()}
  else
    print("Could not lift type "..tostring(self.type))
    assert(false)
  end
end

-- allowExp: should we allow you to lower something with a non-zero exp? or throw an error
function fixedNewASTFunctions:toUnfixed()
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)

  err( self:exp()==0, "attempting to lower a value with nonzero exp")

  return fixed.new{kind="lower", type=fixed.extract(self.type),inputs={self},loc=getloc()}
end
]=]

function fixedNewASTFunctions:toSigned()
  --err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  if self:isSigned() then
    return self
  end

  local ty = fixed.type( true, self:precision()+1, self:exp() )
  return fixed.new{kind="toSigned", type=ty, inputs={self}, loc=getloc() }
end

function fixedNewASTFunctions:addLSBs(N)
  err( type(N)=="number", "addLSBs input must be number" )
  err( N>=0, "addLBSs input must be >=0")

  if N==0 then return self end
  
  return fixed.new{kind="addLSBs", type=fixed.type(self:isSigned(), self:precision()+N, self:exp()-N),N=N,inputs={self},loc=getloc()}
end

function fixedNewASTFunctions:removeLSBs(N)
  err( type(N)=="number", "removeLSBs input must be number" )
  err( N>0, "removeLBSs input must be >0")

  return fixed.new{kind="removeLSBs", type=fixed.type(self:isSigned(), self:precision()-N, self:exp()+N),N=N,inputs={self},loc=getloc()}
end

function fixedNewASTFunctions:addMSBs(N)
  --err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  err( type(N)=="number", "addMSBs input must be number" )
  err( N>0, "addMBSs input must be >0")

  return fixed.new{kind="addMSBs", type=fixed.type(self:isSigned(), self:precision()+N, self:exp()),N=N,inputs={self},loc=getloc()}
end

function fixedNewASTFunctions:removeMSBs(N)
  --err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  err( type(N)=="number", "removeMSBs input must be number" )
  err( N>=0, "removeMBSs input must be >=0")

  if N==0 then return self end
  
  return fixed.new{kind="removeMSBs", type=fixed.type(self:isSigned(), self:precision()-N, self:exp()),N=N,inputs={self},loc=getloc()}
end

function fixedNewASTFunctions:rshift(N)
  --err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  err( type(N)=="number", "rshift input must be number" )
  err( N>0, "rshift input must be >0")
  
  return fixed.new{kind="rshift", type=fixed.type(self:isSigned(), self:precision(), self:exp()-N),shift=N,inputs={self},loc=getloc()}
end

function fixedNewASTFunctions:lshift(N)
  --err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  return fixed.new{kind="lshift", type=fixed.type(self:isSigned(), self:precision(), self:exp()+N),shift=N,inputs={self},loc=getloc()}
end

local function boolbinop(op,l,r)
  if l:isSigned()~=r:isSigned() or
    l:exp() ~= r:exp() or
    l:precision() ~= r:precision() then
    err(false, "Error, fixed "..op..", input types don't match: "..tostring(l.type).." "..tostring(r.type))
  end

  return fixed.new({kind="binop",op=op,inputs={l,r}, type=types.bool(), loc=getloc()})
end

function fixedNewASTFunctions:gt(r) return boolbinop(">",self,r) end
function fixedNewASTFunctions:ge(r) return boolbinop(">=",self,r) end
function fixedNewASTFunctions:lt(r) return boolbinop("<",self,r) end
function fixedNewASTFunctions:le(r) return boolbinop("<=",self,r) end
function fixedNewASTFunctions:eq(r) return boolbinop("==",self,r) end
function fixedNewASTFunctions:ne(r) return boolbinop("~=",self,r) end

function fixedNewASTFunctions:abs()
  err( self:isSigned(), "abs value of a non-signed type is futile")

  -- we actually _CANT_ throw out data here. signed number lose one value
  -- (either the max or the min). But since one of the max or min remain,
  -- we can't represent this without the full # of bits.
  local ty = fixed.type(false, self:precision(), self:exp())
  return fixed.new{kind="abs", type=ty, inputs={self}, loc=getloc()}
end


function fixedNewASTFunctions:rcp()
  -- if P is the precision, we actually calculate 1/x * 2^P, which means we have to subtract P from the exp
  -- we have to add 1 to precision. Consider the 8 bit case. 2^P=256. 256/1 = 256, which will overflow 8 bits. So we need 9 bits of output.

  -- int8 range: -128 to 127
  -- int9 range: -256 to 255
  -- 256/1 = 256, 256/-1 = -256
  -- so, int8 rcp won't fit into int9, if we mult by 256
  -- however, if we multiply by 128, it is OK:
  -- 128/1 = 128, 128/-1 = -128, which fits in int9

  local exp = -self:exp()-self:precision()
  if self:isSigned() then exp=exp+1 end -- see note above
  
  return fixed.new{kind="rcp",type=fixed.type(self:isSigned(), self:precision()+1, exp),inputs={self},loc=getloc()}
end

function fixedNewASTFunctions:neg()
  --err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  err( self.type:isInt() or self:isSigned(), "neg value of a non-signed type is futile")
  return fixed.new{kind="neg", type=self.type, inputs={self}, loc=getloc()}
end

-- f should be a rigel module, of type basic->basic
-- outputType: override the output type of the rigel module
--             remember, when we lower, we get rid of the fixed types.
--             The rigel module should operator on the lowered types,
--             but for the fixed representation, we want use the fixed type.
function fixedNewASTFunctions:applyUnaryLiftRigel(f,outputType,operateOnUnderlyingType)
  R.isFunction(f)
  R.expectBasic(f.inputType)
  R.expectBasic(f.outputType)

  if operateOnUnderlyingType==nil then operateOnUnderlyingType=true end

  if outputType==nil then outputType = f.outputType end
  
  return fixed.new{kind="applyUnaryLiftRigel", f=f, inputs={self}, type=outputType, loc=getloc(), operateOnUnderlyingType=operateOnUnderlyingType}
end

-- f should be a unary function that takes in a single systolic value, and returns a systolic value
function fixedNewASTFunctions:applyUnaryLift(f)
  if type(f)=="function" then

    -- hack to get type
    local tmpinp = S.parameter("TMP",self.type)
    local outty = f(tmpinp)
    outty = outty.type
    assert( types.isType(outty) )
    
    return fixed.new{kind="applyUnaryLiftSystolic", f=f, inputs={self}, type=outty, loc=getloc()}
  else
    err(false,"fixed:applyUnaryLift, unknown lift type")
  end
end

-- f should be a unary function that takes in two values, and returns a systolic value
function fixedNewASTFunctions:applyBinaryLift(f,inp)
  if type(f)=="function" then

    -- hack to get type
    local tmpinp0 = S.parameter("TMP0",self.type)
    local tmpinp1 = S.parameter("TMP1",self.type)
    local outty = f(tmpinp0,tmpinp1)
    outty = outty.type
    assert( types.isType(outty) )
    
    return fixed.new{kind="applyBinaryLiftSystolic", f=f, inputs={self,inp}, type=outty, loc=getloc()}
  else
    err(false,"fixed:applyBinaryLift, unknown lift type")
  end
end

-- f should be a function that takes in a single table (array format) of systolic values, and returns a systolic value
function fixed.applyNaryLift(f,tab,X)
  err(X==nil, "fixedNaryLift, too many args")
  err(type(tab)=="table", "applyNaryLift: second argument must be table")
  
  if type(f)=="function" then

    --if operateOnUnderlyingType==nil then operateOnUnderlyingType=true end
    local operateOnUnderlyingType=true
    
    -- hack to get type
    local tmpinp = {}
    for k,v in ipairs(tab) do table.insert(tmpinp,S.parameter("TMP"..k,v.type)) end
    local outty = f(tmpinp)
    outty = outty.type
    assert( types.isType(outty) )
    
    return fixed.new{kind="applyNaryLiftSystolic", f=f, inputs=tab, type=outty, loc=getloc(), operateOnUnderlyingType=operateOnUnderlyingType}    
  else
    err(false,"fixed:applyNaryLift, unknown lift type")
  end
end

-- f should be a function that takes in a single table (array format) of systolic values, and returns a systolic value
function fixed.applyTrinaryLift(f,cond,a,b,X)
  err(X==nil, "applyTrinaryLift too many args")
  
  if type(f)=="function" then
    -- hack to get type
    local tmpinp0 = S.parameter("TMP0",cond.type)
    local tmpinp1 = S.parameter("TMP1",a.type)
    local tmpinp2 = S.parameter("TMP2",b.type)
    local outty = f(tmpinp0,tmpinp1,tmpinp2)
    outty = outty.type
    assert( types.isType(outty) )
    
    return fixed.new{kind="applyTrinaryLiftSystolic", f=f, inputs={cond,a,b}, type=outty, loc=getloc()}
  else
    err(false,"fixed:applyTrinaryLift, unknown lift type")
  end
end

function fixedNewASTFunctions:toSystolic()
  local instances = {}
  local resetStats = {}
  local inp
  local res = self:visitEach(
    function( n, args )
      local res
      if n.kind=="parameter" then
        inp = S.parameter(n.name, n.type)
        res = inp
        --if n.type:isNamed() and n.type.generator=="fixed" then
        -- remove wrapper
	if n.type~=n.type:stripNamed() then
	  res = S.cast(res,n.type:stripNamed())
	end
        --end
      elseif n.kind=="binop" then

        if fixed.DEEP_MULTIPLY and fixed.isFixedType(n.type) and n:precision()>=20 and n.op=="*" and 
          n.inputs[1].type:const()==false and
          n.inputs[2].type:const()==false then
          local I = fpgamodules.multiply(n.inputs[1]:underlyingType(), n.inputs[2]:underlyingType(), n:underlyingType() ):instantiate("UNNAMEDINST"..tostring(#instances))
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
          elseif n.op=="==" then
            res = S.eq(args[1],args[2])
          elseif n.op=="~=" then
            res = S.__not(S.eq(args[1],args[2]))
          elseif n.op=="+" or n.op=="-" or n.op=="*" then
            local l = S.cast(args[1], n:underlyingType() )
            local r = S.cast(args[2], n:underlyingType() )
            
            if n.op=="+" then res = l+r
            elseif n.op=="-" then res = l-r
            elseif n.op=="*" then res = l*r
            else
              assert(false)
            end
            
            --if fixed.isFixedType(n.type) and n:precision()>20 then
              --print("riduclous binop "..tostring(n.inputs[1].type).." "..tostring(n.inputs[2].type).." "..tostring(n.type)..n.loc)
            --end
          else
            err(false,"internal error, fixed.lua, unknown binop "..n.op)
          end
        end

      elseif n.kind=="rshift" or n.kind=="lshift" then
        --res = S.rshift(args[1],S.constant( n.shift, fixed.extract(n.inputs[1].type)))
        res = args[1]
      elseif n.kind=="lift" or n.kind=="lower" then
        -- don't actually do anything: we only add the wrapper at the very end
        res = args[1]
      elseif n.kind=="constant" then
        res = S.constant( n.value, n:underlyingType() )
      elseif n.kind=="toSigned" then
        res = S.cast( args[1], n:underlyingType() )
      elseif n.kind=="abs" then
        res = S.abs( args[1] )
        res = S.cast( res, n:underlyingType() )
      elseif n.kind=="rcp" then

        local numerator, denom, isPositive, uintType
        if n:isSigned() then
          -- signed behavior: basically, remember the sign, take abs, do unsigned div, then add back sign
          
          uintType = n:underlyingType()
          uintType = types.uint(uintType.precision)
          numerator = S.constant(math.pow(2,n.inputs[1]:precision()-1),uintType)
          denom = S.cast(args[1], types.int(uintType.precision) )
          denom = S.cast(S.abs(denom), uintType)

          isPositive = S.ge(args[1],S.constant(0,types.int(2)))
        else
          uintType = n:underlyingType()
          numerator = S.constant(math.pow(2,n.inputs[1]:precision()),uintType)
          denom = S.cast( args[1], uintType )
        end
        
        local inst = fpgamodules.div(uintType):instantiate(n.name.."_DIVINST")
        table.insert(instances,inst)
        
        res = inst:process(S.tuple{numerator,denom})

        res = S.cast(res,n:underlyingType())

        if isPositive~=nil then
          res = S.select(isPositive,res,S.neg(res))
        end
      elseif n.kind=="neg" then
        res = S.neg(args[1])
      elseif n.kind=="applyUnaryLiftRigel" then
        local I = n.f.systolicModule:instantiate(n.name)
        table.insert(instances,I)
        res = I:process(args[1])
        if n.f.stateful then table.insert(resetStats,I:reset()) end
      elseif n.kind=="applyUnaryLiftSystolic" then
        res = n.f(args[1])
        assert(systolicAST.isSystolicAST(res))
      elseif n.kind=="applyBinaryLiftSystolic" then
        res = n.f(args[1],args[2])
        assert(systolicAST.isSystolicAST(res))
      elseif n.kind=="applyTrinaryLiftSystolic" then
        res = n.f(args[1],args[2],args[3])
        assert(systolicAST.isSystolicAST(res))
      elseif n.kind=="applyNaryLiftSystolic" then
        local tmp = args
        if n.operateOnUnderlyingType==false then
          tmp = {}
          for k,v in pairs(args) do
            if v.type~=n.inputs[k].type then
              tmp[k] = S.cast(v,n.inputs[k].type)
            else
              tmp[k] = v
            end
          end
        end
        
        res = n.f(tmp)

        assert(systolicAST.isSystolicAST(res))
      elseif n.kind=="addLSBs" then
        res = S.cast(args[1], n:underlyingType() )
        res = S.lshift(res,S.constant(n.N,types.uint(8)))
      elseif n.kind=="removeLSBs" then
        res = S.rshift(args[1],S.constant(n.N,types.uint(8)))
        res = S.cast(res, n:underlyingType() )
      elseif n.kind=="addMSBs" or n.kind=="removeMSBs" then
        res = S.cast(args[1], n:underlyingType() )
      else
        print(n.kind)
        assert(false)
      end

      return res
    end)

  --if self.type:isNamed() and self.type.generator=="fixed" then
    -- we want the exterior interface for this module to be an actual fixed type, not the underlying type
    --local c = S.constant(0, self.type.list[2])
  --res = S.tuple{res,c}
  if self.type~=self:underlyingType() then
    res = S.cast(res,self.type)
  end
  --end

  return res, inp, instances, resetStats
end

fixed.hists = {}
function fixed.printHistograms()
  for k,v in pairs(fixed.hists) do v() end
end


function fixedNewASTFunctions:toRigelModule(name,X)
  assert(type(name)=="string")
  assert(X==nil)

  local out, inp, instances, resetStats = self:toSystolic()

  err(out.type==self.type,"toRigelModule type mismatch "..tostring(out.type).." "..tostring(self.type))
  
  local tfn

  local res = {kind="fixed", inputType=inp.type, outputType=out.type,delay=0, sdfInput={{1,1}},sdfOutput={{1,1}}}
  if terralib~=nil then res.terraModule=fixedTerra.toDarkroom(self,name) end
  res.name = name

  local sys = Ssugar.moduleConstructor(name)
  for _,v in ipairs(instances) do sys:add(v) end
  local CE = S.CE("process_CE")
  sys:addFunction( S.lambda("process",inp,out,"process_output",nil,nil,CE ) )

  if #resetStats>0 then
    res.stateful=true
    sys:addFunction( S.lambda("reset",S.parameter("r",types.null()),nil,"ro",resetStats,S.parameter("reset",types.bool()),CE) )
  else
    res.stateful=false
  end

  sys:complete()

  res.systolicModule = sys
  
  return R.newFunction(res)
end

--------------------------------------------------------
-- convenient syntax
function fixedNewASTFunctions:__and(b) return self:applyBinaryLift( S.__and, b ) end
function fixedNewASTFunctions:index(x,y) return self:applyUnaryLift( function(expr) return S.index(expr,x,y) end ) end
function fixed.array2d(tab,w,h) return fixed.applyNaryLift(
    function(tabi) return S.cast(S.tuple(tabi),types.array2d(tabi[1].type,w,h)) end, tab )
end

function fixed.tuple(tab) return fixed.applyNaryLift(S.tuple,tab) end
function fixed.select(cond,a,b) return fixed.applyTrinaryLift(S.select,cond,a,b) end

function fixedNewASTFunctions:mod(b) 
  err( J.isPowerOf2(b), "NYI, fixed mod by non power of 2" )
  local bits = math.log(b)/math.log(2)

  local ty
  if self.type:isUint() then
    ty = types.uint(bits)
  else
    assert(false)
  end

  return self:applyUnaryLift( function(expr) return S.cast(S.bitSlice(expr,0,bits-1),ty) end ) 
end

function fixedNewASTFunctions:writePixel(id,imageSize)
  local file = io.open("out/dbg_"..id..".metadata.lua", "w")
  file:write("return {width="..tostring(imageSize[1])..",height="..tostring(imageSize[2])..",type='"..tostring(self.type).."'}")
  file:close()

  -- internally, we don't actually used the fixed types...
  local stripType = self.type
  if stripType:isNamed() and stripType.generator=="fixed" then stripType=stripType.structure end
  
  -- nasty hack to get around require circular dependencies
  local RS = require("rigelSimple")

  return self:applyUnaryLiftRigel(RS.modules.fwriteSeq{type=stripType, filename="out/dbg_terra_"..id..".raw", filenameVerilog="out/dbg_verilog_"..id..".raw"}, self.type)
end

function fixedNewASTFunctions:isSigned()
  --err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  --return self.type.list[1]:isInt()
  if self.type:isUint() then return false end
  if self.type:isInt() then return true end
  if self.type:isNamed() and self.type.generator=="fixed" then return self.type.params.signed end
  err(false,":isSigned(), not a numeric type!")
end

function fixedNewASTFunctions:exp()
  --err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  --local op = self.type.list[2]
  --return tonumber(op.str:sub(6))
  if self.type:isUint() then return 0 end
  if self.type:isInt() then return 0 end
  if self.type:isNamed() and self.type.generator=="fixed" then return self.type.params.exp end
  err(false,":exp(), not a numeric type!")
end

function fixedNewASTFunctions:precision()
  --err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  --return self.type.list[1].precision
  if self.type:isUint() then return self.type.precision end
  if self.type:isInt() then return self.type.precision end
  if self.type:isNamed() and self.type.generator=="fixed" then return self.type.params.precision end
  err(false,":precision(), not a numeric type!")
end

function fixedNewASTFunctions:underlyingType() return self.type:stripNamed() end

return fixed
