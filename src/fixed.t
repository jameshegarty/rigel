local IR = require("ir")
local types = require("types")
local cmath = terralib.includec("math.h")
local cstdlib = terralib.includec("stdlib.h")

local fixed = {}

local function getloc()
--  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline
  return debug.traceback()
end

function fixed.isFixedType(ty)
  assert(types.isType(ty))
  if ty:isTuple()==false or ty.list[2]:isOpaque()==false then return false end
  local str = ty.list[2].str:sub(1,5)
  if str=="fixed" then return true end
  return false
end

function fixed.expectFixed(ty)
  err( fixed.isFixedType(ty), "Expected fixed point type")
end

function fixed.extract(ty)
  if fixed.isFixedType(ty) then
    return ty.list[1]
  end
  return ty
end

function fixed.extractExp(ty)
  fixed.expectFixed(ty)
  local str = ty.list[2].str:sub(6)
  return tonumber(str)
end

function fixed.extractPrecision(ty)
  fixed.expectFixed(ty)
  return ty.list[1].precision
end

function fixed.extractSigned(ty)
  fixed.expectFixed(ty)
  return ty.list[1]:isInt()
end

function fixed.type( signed, precision, exp )
  assert(type(signed)=="boolean")
  assert(type(precision)=="number")
  assert(type(exp)=="number")
  local name = "fixed"..tonumber(exp)
  if signed then
    return types.tuple{types.int(precision),types.opaque(name)}
  else
    return types.tuple{types.uint(precision),types.opaque(name)}
  end
end

fixedASTFunctions = {}
setmetatable(fixedASTFunctions,{__index=IR.IRFunctions})

fixedASTMT={__index = fixedASTFunctions,
__add=function(l,r)
  if (l.type:isInt() or l.type:isUint()) and (r.type:isInt() or r.type:isUint()) then
    assert(l.type==r.type)
    return fixed.new({kind="binop",op="+",inputs={l,r}, type=l.type, loc=getloc()})
  else
    err(l:isSigned()==r:isSigned(), "+: sign must match")
    err(l:exp()==r:exp(), "+: exp must match")
    local p = math.max(l:precision(),r:precision())+1
    return fixed.new({kind="binop",op="+",inputs={l,r}, type=fixed.type( l:isSigned(), p, l:exp() ), loc=getloc()})
  end
end, 
__sub=function(l,r) 
  if l.type:isInt() and r.type:isInt() then
    assert(l.type==r.type)
    return fixed.new({kind="binop",op="-",inputs={l,r}, type=l.type, loc=getloc()})
  else
    err(l:isSigned() and r:isSigned(), "-: must be signed")
    err(l:exp()==r:exp(), "-: exp must match")
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
  assert(#tab.inputs==keycount(tab.inputs))
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
  assert(a.type==b.type)
  return fixed.new{kind="select", inputs={cond,a,b}, type=a.type, loc=getloc()}
end

function fixed.array2d( tab, w, h )
  local inps = {}
  for k,v in pairs(tab) do 
    table.insert(inps,v) 
    assert(v.type==tab[1].type)
  end
  return fixed.new{kind="array2d", inputs=inps, type=types.array2d(tab[1].type,w,h), loc=getloc()}
end

function fixed.constant( value, signed, precision, exp )
  if signed==nil then 
    signed = (value<0) 
  end

  if precision==nil then 
    precision = math.ceil(math.log(value)/math.log(2))+1 
    if signed then precision = precision + 1 end
  end

  if exp==nil then exp=0 end

  err(value < math.pow(2,precision-sel(signed,1,0)), "const value out of range, "..tostring(value).." in precision "..tostring(precision).." signed:"..tostring(signed))

  return fixed.new{kind="constant", value=value, type=fixed.type(signed,precision,exp),inputs={},loc=getloc()}
end

function fixed.plainconstant( value, ty )
  assert(types.isType(ty))
  return fixed.new{kind="plainconstant", value=value, type=ty,inputs={},loc=getloc()}
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

function fixedASTFunctions:normalize(precision)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  local expshift = self:precision()-precision
  local ty = fixed.type(self:isSigned(), precision, self:exp()+expshift)
  return fixed.new{kind="normalize", type=ty,inputs={self},loc=getloc()}
end

-- throw out information!
function fixedASTFunctions:truncate(precision)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  local ty = fixed.type(self:isSigned(), precision, self:exp())
  return fixed.new{kind="truncate", type=ty,inputs={self},loc=getloc()}
end

function fixedASTFunctions:pad(precision,exp)
  err( fixed.isFixedType(self.type), "expected fixed type: "..self.loc)
  err( precision>=self:precision(), "pad shouldn't make precision smaller")
  err( exp<=self:exp(), "pad shouldn't make exp larger") -- making exponant larger => bits shift right
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
  return fixed.new{kind="rshift", type=fixed.type(self:isSigned(), self:precision(), self:exp()-N),shift=N,inputs={self},loc=getloc()}
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
  return self.type.list[1]:isInt()
end

function fixedASTFunctions:exp()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  local op = self.type.list[2]
  return tonumber(op.str:sub(6))
end

function fixedASTFunctions:precision()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return self.type.list[1].precision
end

function fixedASTFunctions:toSystolic()
  local inp
  local res = self:visitEach(
    function( n, args )
      local res
      if n.kind=="parameter" then
        inp = S.parameter(n.name, n.type)
        res = inp
        if fixed.isFixedType(n.type) then
          -- remove wrapper
          res = S.index(res,0)
        end
      elseif n.kind=="binop" then
        local l = S.cast(args[1], fixed.extract(n.type))
        local r = S.cast(args[2], fixed.extract(n.type))
        if n.op=="+" then res = l+r
        elseif n.op=="-" then res = l-r
        elseif n.op=="*" then res = l*r
        else
          assert(false)
        end
        --res = S.ast.new({kind="binop",op=n.op,inputs={args[1],args[2]},loc=n.loc,type=fixed.extract(n.type)})
      elseif n.kind=="rshift" then
        --res = S.rshift(args[1],S.constant( n.shift, fixed.extract(n.inputs[1].type)))
        res = args[1]
      elseif n.kind=="truncate" then
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
        if dp==0 then
          res = args[1]
        elseif dp>0 then
          res = S.rshift(args[1], S.constant(dp, fixed.extract(n.inputs[1].type)) )
          res = S.cast(res,fixed.extract(n.type))
        elseif dp<0 then
          -- make larger
          res = S.cast( args[1], fixed.extract(n.type) )
          res = S.lshift( res, S.constant(-dp, fixed.extract(n.inputs[1].type)) )
        else
          assert(false)
        end
      elseif n.kind=="hist" then
        res = args[1] -- cpu only
      elseif n.kind=="index" then
        res = S.index( args[1], n.ix, n.iy)
        if fixed.isFixedType(n.type) then
          -- remove wrapper
          res = S.index(res,0)
        end
      elseif n.kind=="toSigned" then
        res = S.cast( args[1], fixed.extract(n.type) )
      elseif n.kind=="abs" then
        res = S.abs( args[1] )
        res = S.cast( args[1], fixed.extract(n.type) )
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
            inp[k] = S.tuple{v,S.constant(0, self.inputs[1].type.list[2])}
          end
        end

        res = S.cast(S.tuple(inp),n.type)
      elseif n.kind=="addSign" then
        local tsign = S.ge(args[1],S.constant(0,fixed.extract(n.inputs[1].type)))
        res = S.cast(args[1], fixed.extract(n.type) )
        res = S.select(S.eq(tsign,args[2]),res,S.neg(res))
      elseif n.kind=="msb" then
        local bits = n.inputs[1]:precision()
        local minexp = n.inputs[1]:exp()
        local tab = {}
        for i=0,bits-1 do
          local bittrue = S.bitSlice(args[1],i,i)
          bittrue = S.cast(bittrue,types.bool())
          table.insert(tab, S.tuple{bittrue,S.constant(i-minexp-n.precision,types.int(8))} )
        end

        local out = foldt(tab,function(l,r) return S.select(S.index(l,0),l,r) end, 'X')

        res = S.select(S.eq(args[1],S.constant(0,fixed.extract(n.inputs[1].type))),S.constant(minexp,types.int(8)),S.index(out,1))
      elseif n.kind=="float" then
        local lshiftamt = S.cast(S.constant(n.minexp,types.int(8))-args[2],types.uint(8))
        local lshift = S.lshift(args[1],lshiftamt)
        local rshiftamt = S.cast(args[2]-S.constant(n.minexp,types.int(8)), types.uint(8))
        local rshift = S.rshift(args[1],rshiftamt)
        res = S.select(S.lt(args[2],S.constant(n.minexp,types.int(8))),lshift,rshift)
        res = S.cast(res,n.type)
      elseif n.kind=="liftFloat" then
        res = S.cast(args[1], fixed.extract(n.type))
        local lshiftamt = S.cast(args[2]-S.constant(n.minexp,types.int(8)), types.uint(8))
        res = S.lshift(res, lshiftamt)
      elseif n.kind=="pad" then
        local lshift = n.inputs[1]:exp() - n:exp()
        assert(lshift>=0)
        res = S.lshift(S.cast(args[1],fixed.extract(n.type)),lshift)
      elseif n.kind=="select" then
        res = S.select(args[1],args[2],args[3])
      elseif n.kind=="cast" then
        res = S.cast(args[1],n.type)
      else
        print(n.kind)
        assert(false)
      end

      return res
    end)

  if fixed.isFixedType(self.type) then
    local c = S.constant(0, self.type.list[2])
    res = S.tuple{res,c}
  end

  return res, inp
end

local hists = {}
function fixed.printHistograms()
  for k,v in pairs(hists) do v() end
end

function fixedASTFunctions:toTerra()
  local inp
  local res = self:visitEach(
    function( n, args )
      local res
      if n.kind=="parameter" then
        inp = symbol(&n.type:toTerraType(), n.name)
        res = `@inp
        if fixed.isFixedType(n.type) then
          res = `res._0
        end
      elseif n.kind=="binop" then
        local l = `[fixed.extract(n.type):toTerraType()]([args[1]])
        local r = `[fixed.extract(n.type):toTerraType()]([args[2]])
        if n.op=="+" then res = `l+r
        elseif n.op=="-" then res = `l-r
        elseif n.op=="*" then res = `l*r
        else
          print("OP",n.op)
          assert(false)
        end
      elseif n.kind=="lift" or n.kind=="lower" then
        -- noop: we only add wrapper at very end
        res = args[1]
      elseif n.kind=="constant" then
        res = `[fixed.extract(n.type):toTerraType()](n.value)
      elseif n.kind=="plainconstant" then
        --res = `[n.type:toTerraType()](n.value)
        res = n.type:valueToTerra(n.value)
      elseif n.kind=="rshift" then
        --res = `[fixed.extract(n.type):toTerraType()]([args[1]]>>n.shift)
        res = args[1]
      elseif n.kind=="truncate" then
        -- notice that we don't bother bitmasking here.
        -- "in theory" all of the ops in this language _never_ lose precision. So the ops themselves can't overflow.
        -- We will have extra garbage in the upper bits compared to HW, but as long as we don't intentially examine it,
        -- it should stay in the upper bits and never affect the result.
        res = `[fixed.extract(n.type):toTerraType()]([args[1]])
      elseif n.kind=="normalize" or n.kind=="denormalize" then
        local dp = n.inputs[1]:precision()-n:precision()
        if dp==0 then return args[1]
        elseif dp > 0 then res = `[fixed.extract(n.type):toTerraType()]([args[1]]>>dp)
        else res = `[fixed.extract(n.type):toTerraType()]([args[1]]<<[-dp]) end
      elseif n.kind=="hist" then
        local gpos = global(uint[n:precision()])
        local gneg = global(uint[n:precision()])
        local gbits = global(uint[n:precision()])
        local terra tfn()
          cstdio.printf("--------------------- %s, exp %d, prec %d\n",n.name, [n:exp()],[n:precision()])
          for i=0,[n:precision()] do
            var r = i+[n:exp()]
            if i==0 then
              -- this always includes 0, and things less than smallest type
              cstdio.printf("0+: %d\n", gpos[i])
            elseif r<0 then
              cstdio.printf("1/%d: +%d, -%d\n", i, gpos[i], gneg[i])
            else
              cstdio.printf("%d-%d: +%d, -%d\n", [uint](cmath.pow(2,r)), [uint](cmath.pow(2,r+1)-1), gpos[i], gneg[i])
            end
          end

          cstdio.printf("--------------------- %s BITS\n",n.name)
          for i=0,[n:precision()] do
            cstdio.printf("%d: %d\n", i, gbits[i])
          end
        end
        table.insert(hists, tfn)
        res = quote 
          if [args[1]]>0 then 
            var v : uint = [uint](cmath.floor(cmath.log([args[1]])/cmath.log(2.f))) 
            gpos[v] = gpos[v] + 1
          elseif [args[1]]<0 then
            var v : uint = [uint](cmath.floor(cmath.log(-[args[1]])/cmath.log(2.f))) 
            gneg[v] = gneg[v] + 1
          elseif [args[1]]==0 then
            gneg[0] = gneg[0] + 1
            gpos[0] = gpos[0] + 1
          end

          --cstdio.printf("%d %d\n",[args[1]],v)
          ------
          for i=0,[n:precision()] do
            var mask = [fixed.extract(n.type):toTerraType()](1) << i
            var inp = [args[1]]
            if inp<0 then inp = -inp end -- deal with negative numbers
            if (inp and mask) ~= 0 then
              gbits[i] = gbits[i] + 1
            end
          end
          in [args[1]] end
      elseif n.kind=="index" then
        if n.inputs[1].type:isArray() then
          local W = (n.inputs[1].type:arrayLength())[1]
          res = `[args[1]][n.iy*W+n.ix]
        elseif n.inputs[1].type:isTuple() then
          res = `[args[1]].["_"..n.ix]
        else
          assert(false)
        end

        if fixed.isFixedType(n.type) then
          res = `res._0
        end
      elseif n.kind=="toSigned" then
        res = `[fixed.extract(n.type):toTerraType()]([args[1]])
      elseif n.kind=="abs" then
        res = `terralib.select([args[1]]>=0,[args[1]], -[args[1]])
        res = `[fixed.extract(n.type):toTerraType()](res)
      elseif n.kind=="sign" then
        --res = `[args[1]]<0
        res = quote
          var r:bool = [args[1]]>=0
--          cstdio.printf("SIGN inp %d res %d\n",[args[1]],r)
          in r end
      elseif n.kind=="addSign" then
        res = `[fixed.extract(n.type):toTerraType()]([args[1]])
        res = quote
          var r = terralib.select([args[2]],res,-res)
--          cstdio.printf("ADDSIGN inp %d inpsign %d res %d\n",[args[1]],[args[2]],r)
                        in r end
      elseif n.kind=="neg" then
        res = `-[args[1]]
      elseif n.kind=="tuple" then
        res = `{args}
      elseif n.kind=="array2d" then
        local inp = args
        if fixed.isFixedType(n.inputs[1].type) then
          for k,v in pairs(args) do
            inp[k] = `{v,nil}
          end
        end

        res = `arrayof([n.type:arrayOver():toTerraType()], inp)
      elseif n.kind=="msb" then
        local minexp = n.inputs[1]:exp()
        local maxexp = n.inputs[1]:exp()+n.inputs[1]:precision()-n.precision
        res = quote
          var msb : int8 = minexp-[n.precision]
          var tmp = [args[1]] and ( (1 << [n.inputs[1]:precision()])-1)
          var orig = tmp

          if orig==0 then
            msb = minexp
          else
            while tmp>0 do tmp = tmp >> 1; msb=msb+1; end
--          if msb<minexp then msb = minexp end
            --          if msb<[minexp] then cstdio.printf("msb below minexp\n");cstdlib.exit(1); end
          end
          if msb>[maxexp] then cstdio.printf("msb above maxexp, msb %d max %d prec %d\n",msb,maxexp,[n.inputs[1]:precision()]);cstdlib.exit(1); end
          
          --[=[ -- debugging
          var flt : fixed.extract(n.inputs[1].type):toTerraType()
          if msb < minexp then
            flt = [args[1]] << ([minexp]-msb)
          elseif msb > minexp then
            flt = [args[1]] >> (msb-[minexp])
          end
          var recovered = flt << (msb-[minexp])
          cstdio.printf("MSB inp %d, realinp %d, inp_precision %d, msb %d flt %d reconstructed %d\n",orig, [args[1]], [n.inputs[1]:precision()], msb,flt, recovered)
          cstdio.printf("MSB value:%d msb:%d min %d max %d\n",[args[1]],msb,minexp,maxexp)
          ]=]
          in msb end
      elseif n.kind=="float" then
        res = quote
          --if [args[2]]<[n.minexp] then cstdio.printf("Float below minexp\n");cstdlib.exit(1); end
          if [args[2]]>[n.maxexp] then cstdio.printf("Float above maxexp\n");cstdlib.exit(1); end
          var r : n.type:toTerraType() = [args[1]]
          if [args[2]]<[n.minexp] then
            r = [args[1]]<<([n.minexp] - [args[2]])
          elseif [args[2]]>[n.minexp] then
            r = [args[1]]>>([args[2]]-[n.minexp])
          end

          in [n.type:toTerraType()](r) end
      elseif n.kind=="liftFloat" then
        print("LIFTFLOAT",n.type)
        res = quote
          if [args[2]]<[n.minexp] then cstdio.printf("LiftFloat below minexp is:%d expected%d\n",[args[2]],[n.minexp]);cstdlib.exit(1); end
          if [args[2]]>[n.maxexp] then cstdio.printf("LiftFloat exp %d above maxexp %d\n",[args[2]],[n.maxexp]);cstdlib.exit(1); end
          var inp : fixed.extract(n.type):toTerraType() = [args[1]]
          var r = inp<<([args[2]]-[n.minexp])
          --cstdio.printf("liftFloat v %d exp %d minexp %d out %d\n",[args[1]], [args[2]], [n.minexp], r)
          in [fixed.extract(n.type):toTerraType()](r) end
      elseif n.kind=="pad" then
        local lshift = n.inputs[1]:exp() - n:exp()
        assert(lshift>=0)
--        print("PADLSHIFT",lshift)
        res = `([fixed.extract(n.type):toTerraType()]([args[1]])) << lshift
      elseif n.kind=="select" then
        res = `terralib.select([args[1]],[args[2]],[args[3]])
      elseif n.kind=="cast" then
        res = `[n.type:toTerraType()]([args[1]])
      else
        print(n.kind)
        assert(false)
      end

      assert(terralib.isquote(res) or terralib.issymbol(res))
      return res
    end)

  if fixed.isFixedType(self.type) then
    res = `{res,nil}
  end

  return res, inp
end

function fixedASTFunctions:toDarkroom(name,X)
  assert(type(name)=="string")
  assert(X==nil)

  local out, inp = self:toSystolic()
  local terraout, terrainp = self:toTerra()

  local terra tfn([terrainp], out:&out.type:toTerraType())
    @out = terraout
  end
  --tfn:printpretty(true,false)
  return darkroom.lift( name, inp.type, out.type, 1, tfn, inp, out )
end

return fixed