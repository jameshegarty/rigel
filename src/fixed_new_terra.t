local cmath = terralib.includec("math.h")
local cstdlib = terralib.includec("stdlib.h")
local types = require("types")
local S = require("systolic")

local fixedNewTerra={}

local function toTerra(self)
  local inp
  local res = self:visitEach(
    function( n, args )
      local res
      if n.kind=="parameter" then
        inp = symbol(&n.type:toTerraType(), n.name)
        res = `@inp
        if n.type:isNamed() and n.type.generator=="fixed" then
          res = `res._0
        end
      elseif n.kind=="binop" then
        if n.op==">" then
          res = `[args[1]]>[args[2]]
        elseif n.op==">=" then
          res = `[args[1]]>=[args[2]]
        elseif n.op=="<" then
          res = `[args[1]]<[args[2]]
        elseif n.op=="<=" then
          res = `[args[1]]<=[args[2]]
        else
          local l = `[n:underlyingType():toTerraType()]([args[1]])
          local r = `[n:underlyingType():toTerraType()]([args[2]])
          if n.op=="+" then res = `l+r
          elseif n.op=="-" then res = `l-r
          elseif n.op=="*" then res = `l*r
          else
            print("OP",n.op)
            assert(false)
          end
        end
      elseif n.kind=="lift" or n.kind=="lower" then
        -- noop: we only add wrapper at very end
        res = args[1]
      elseif n.kind=="constant" then
        res = `[n:underlyingType():toTerraType()](n.value)
      elseif n.kind=="rshift" or n.kind=="lshift" then
        res = args[1]
      elseif n.kind=="toSigned" then
        res = `[fixed.extract(n.type):toTerraType()]([args[1]])
      elseif n.kind=="abs" then
        res = `terralib.select([args[1]]>=0,[args[1]], -[args[1]])
        res = `[fixed.extract(n.type):toTerraType()](res)
      elseif n.kind=="neg" then
        res = `-[args[1]]
      elseif n.kind=="applyUnaryLiftSystolic" then
        local si = S.parameter("inp",n.inputs[1].type)
        res = n.f(si)
        res = res:toTerra{inp=args[1]}
      elseif n.kind=="applyNaryLiftSystolic" then
        local si = {}
        local symbols = {}
        for k,v in ipairs(n.inputs) do
          table.insert( si, S.parameter("inp"..k,v.type) )
          symbols["inp"..k] = args[k]
        end
        
        res = n.f(si)
        res = res:toTerra(symbols)
      elseif n.kind=="addLSBs" then
        res = `[n.type:toTerraType()]([args[1]])
        res = `res << n.N
      elseif n.kind=="addMSBs" then
        res = `[n.type:toTerraType()]([args[1]])
      else
        print(n.kind)
        assert(false)
      end

      assert(terralib.isquote(res) or terralib.issymbol(res))
      return res
    end)

  if self.type:isNamed() and self.type.generator=="fixed" then
    res = `{res,nil}
  end

  return res, inp
end

function fixedNewTerra.toDarkroom(ast,out)
  local terraout, terrainp = toTerra(ast)

  local terra tfn([terrainp], out:&out.type:toTerraType())
    @out = terraout
  end

  return tfn
end

return fixedNewTerra
