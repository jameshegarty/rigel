local IR = require("ir")
local types = require("types")
local cmath = terralib.includec("math.h")

local fixed = {}
fixed.FLOAT = true 

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

fixedASTFunctions = {}
setmetatable(fixedASTFunctions,{__index=IR.IRFunctions})

fixedASTMT={__index = fixedASTFunctions,
__add=function(l,r)
  return fixed.new({kind="binop",op="+",inputs={l,r}, type=types.float(32), loc=getloc()})
end, 
__sub=function(l,r) 
  return fixed.new({kind="binop",op="-",inputs={l,r}, type=types.float(32), loc=getloc()})
 end,
__mul=function(l,r) 
  return fixed.new({kind="binop",op="*",inputs={l,r}, type=types.float(32), loc=getloc()})
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

function fixedASTFunctions:cast(to)
  return self
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
  assert(false)
end

function fixedASTFunctions:addSign(inp)
  assert(false)
end

function fixedASTFunctions:abs()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return fixed.new{kind="abs", type=types.float(32), inputs={self}, loc=getloc()}
end

function fixedASTFunctions:neg()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return fixed.new{kind="neg", type=self.type, inputs={self}, loc=getloc()}
end

function fixedASTFunctions:invert()
  err(fixed.isFixedType(self.type), "expected fixed point type: "..self.loc)
  return fixed.new{kind="invert", type=self.type, inputs={self}, loc=getloc()}
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
        res = args[1]
      elseif n.kind=="truncate" then
        res = args[1]
      elseif n.kind=="lift" then
        res = S.cast(args[1],types.float(32))
      elseif n.kind=="lower" then
        res = S.cast(args[1],n.type)
      elseif n.kind=="constant" then
        res = S.constant( n.value, fixed.extract(n.type) )
      elseif n.kind=="normalize" or n.kind=="denormalize" or n.kind=="invert" then
        res = args[1]
      elseif n.kind=="hist" then
        res = args[1] -- cpu only
      elseif n.kind=="index" then
        res = S.index( args[1], n.ix, n.iy)
      elseif n.kind=="toSigned" then
        res = args[1]
      elseif n.kind=="abs" then
        res = args[1]
      elseif n.kind=="neg" then
        res = S.neg(args[1])
      elseif n.kind=="sign" then
        res = S.ge(args[1],S.constant(0,fixed.extract(n.inputs[1].type)))
      elseif n.kind=="tuple" then
        res = S.tuple(args)
      elseif n.kind=="array2d" then
        res = S.cast(S.tuple(args),n.type)
      elseif n.kind=="addSign" then
        res = args[1]
      else
        print(n.kind)
        assert(false)
      end

      assert(systolic.isAST(res))
      return res
    end)

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
      elseif n.kind=="index" then
        if n.inputs[1].type:isArray() then
          local W = (n.inputs[1].type:arrayLength())[1]
          res = `[args[1]][n.iy*W+n.ix]
        elseif n.inputs[1].type:isTuple() then
          res = `[args[1]].["_"..n.ix]
        else
          assert(false)
        end
      elseif n.kind=="lift" then
        res = `[float]([args[1]])
      elseif n.kind=="lower" then
        res = `[n.type:toTerraType()]([args[1]])
      elseif n.kind=="constant" then
        res = `[n.type:toTerraType()](n.value)
      elseif n.kind=="rshift" then
        res = `[args[1]]/cmath.pow(2,n.shift)
      elseif n.kind=="truncate" or n.kind=="hist" or n.kind=="normalize" or n.kind=="denormalize" or n.kind=="toSigned" then
        res = args[1]
      elseif n.kind=="abs" then
        res = `terralib.select([args[1]]>=0,[args[1]], -[args[1]])
      elseif n.kind=="sign" or n.kind=="addSign" then
        assert(false)
      elseif n.kind=="neg" then
        res = `-[args[1]]
      elseif n.kind=="tuple" then
        res = `{args}
      elseif n.kind=="array2d" then
        res = `arrayof([n.type:arrayOver():toTerraType()], args)
      elseif n.kind=="invert" then
        res = `terralib.select([args[1]]==0,[float](0),1.f/[args[1]])
      else
        print(n.kind)
        assert(false)
      end

      assert(terralib.isquote(res) or terralib.issymbol(res))
      return res
    end)

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