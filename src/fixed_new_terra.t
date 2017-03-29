local cmath = terralib.includec("math.h")
local cstdlib = terralib.includec("stdlib.h")
local types = require("types")
local S = require("systolic")

local fixedTerra={}

local function toTerra(self)
  -- shenanigans: prevent circular dependency between files by not calling require until done with loading
  local fixed = require("fixed")

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
        if n.op==">" then
          res = `[args[1]]>[args[2]]
        elseif n.op==">=" then
          res = `[args[1]]>=[args[2]]
        elseif n.op=="<" then
          res = `[args[1]]<[args[2]]
        elseif n.op=="<=" then
          res = `[args[1]]<=[args[2]]
        else
          local l = `[fixed.extract(n.type):toTerraType()]([args[1]])
          local r = `[fixed.extract(n.type):toTerraType()]([args[2]])
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
        res = `[fixed.extract(n.type):toTerraType()](n.value)
      elseif n.kind=="rshift" or n.kind=="lshift" then
        --res = `[fixed.extract(n.type):toTerraType()]([args[1]]>>n.shift)
        res = args[1]
      elseif n.kind=="truncate" then
        -- "in theory" we may be able to avoid doing the bitmask here, if all the ops that inspect the number are
        -- aware that they should ignore the upper bits (abs, msb, float, etc).
        -- for simplicity, just do the bitmask.

        if n:isSigned() then
          local outbits = n:precision()
          res = quote
            var mask = ([fixed.extract(types.uint(n.inputs[1]:precision())):toTerraType()](1) << outbits) - 1
            var msb = [fixed.extract(types.uint(n.inputs[1]:precision())):toTerraType()](1) << (outbits-1)
            var notmask = not mask

            var inpuint = [fixed.extract(types.uint(n.inputs[1]:precision())):toTerraType()]([args[1]])
            var masked = inpuint and mask

            -- extend the sign bit so that the CPU thinks this number has the correct sign
            -- note that we set the sign bit based on the MSB of the _masked_ portion. This is what verilog will do.
            -- DO NOT set sign bit based on sign bit of (unmaked) input.
            if (masked and msb) ~=0 then
              masked = masked or notmask
            end

            var r = [fixed.extract(n.type):toTerraType()](masked)
            in r end
        else
          local outbits = n:precision()
          res = quote
            var mask = ([fixed.extract(n.inputs[1].type):toTerraType()](1) << outbits) - 1
            var r = [fixed.extract(n.type):toTerraType()]([args[1]] and mask)
            in r end
    end

--          res = `[fixed.extract(n.type):toTerraType()]([args[1]])
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

  if fixed.isFixedType(self.type) then
    res = `{res,nil}
  end

  return res, inp
end

function fixedTerra.toDarkroom(ast,out)
  local terraout, terrainp = toTerra(ast)

  local terra tfn([terrainp], out:&out.type:toTerraType())
    @out = terraout
  end

  return tfn
end

return fixedTerra
