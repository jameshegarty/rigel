local cmath = terralib.includec("math.h")

local fixedFloatTerra={}

local function fixed_extract(ty) return ty end

local function toTerra(self)
  local inp
  local res = self:visitEach(
    function( n, args )
      local res
      if n.kind=="parameter" then
        inp = symbol(&n.type:toTerraType(), n.name)
        res = `@inp
      elseif n.kind=="binop" then
        if n.op==">" then
          res = `[args[1]]>[args[2]]
        elseif n.op=="<" then
          res = `[args[1]]<[args[2]]
        elseif n.op==">=" then
          res = `[args[1]]>=[args[2]]
        elseif n.op=="and" then
          res = `[args[1]] and [args[2]]
        else
          local l = `[fixed_extract(n.type):toTerraType()]([args[1]])
          local r = `[fixed_extract(n.type):toTerraType()]([args[2]])
          if n.op=="+" then res = `l+r
          elseif n.op=="-" then res = `l-r
          elseif n.op=="*" then res = `l*r
          elseif n.op=="/" then res = `l/r
          else
            print("OP",n.op)
            assert(false)
          end
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
      elseif n.kind=="plainconstant" then
        res = n.type:valueToTerra(n.value)
      elseif n.kind=="rshift" then
        res = `[args[1]]/cmath.pow(2,n.shift)
      elseif n.kind=="lshift" then
        res = `[args[1]]*cmath.pow(2,n.shift)
      elseif n.kind=="truncate" or n.kind=="hist" or n.kind=="normalize" or n.kind=="denormalize" or n.kind=="toSigned" then
        res = args[1]
      elseif n.kind=="abs" then
        res = `terralib.select([args[1]]>=0,[args[1]], -[args[1]])
      elseif n.kind=="sign" then
        res = `[args[1]]>=0
      elseif n.kind=="addSign" then
        assert(false)
      elseif n.kind=="neg" then
        res = `-[args[1]]
      elseif n.kind=="not" then
        res = `not [args[1]]
      elseif n.kind=="tuple" then
        res = `{args}
      elseif n.kind=="array2d" then
        res = `arrayof([n.type:arrayOver():toTerraType()], args)
      elseif n.kind=="invert" then
        res = `terralib.select([args[1]]==0,[float](0),1.f/[args[1]])
      elseif n.kind=="sqrt" then
        res = `[float](cmath.sqrt([args[1]]))
      elseif n.kind=="select" then
        res = `terralib.select([args[1]],[args[2]],[args[3]])
      elseif n.kind=="cast" then
        res = `[n.type:toTerraType()]([args[1]])
      elseif n.kind=="disablePipelining" then        
        res = args[1]
      else
        print(n.kind)
        assert(false)
      end

      assert(terralib.isquote(res) or terralib.issymbol(res))
      return res
    end)

  return res, inp
end

function fixedFloatTerra.tfn(ast)
  local terraout, terrainp = toTerra(ast)

  local terra tfn([terrainp], out:&ast.type:toTerraType())
    @out = terraout
  end

  return tfn
end

return fixedFloatTerra