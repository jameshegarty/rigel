local cmath = terralib.includec("math.h")
local cstdlib = terralib.includec("stdlib.h")
local types = require("types")

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
--        if fixed.isFixedType(n.type) then
--          res = `res._0
--        end
      elseif n.kind=="binop" then
        if n.op==">" then
          res = `[args[1]]>[args[2]]
        elseif n.op==">=" then
          res = `[args[1]]>=[args[2]]
        elseif n.op=="<" then
          res = `[args[1]]<[args[2]]
        elseif n.op=="<=" then
          res = `[args[1]]<=[args[2]]
        elseif n.op=="and" then
          res = `[args[1]] and [args[2]]
        elseif n.op=="or" then
          res = `[args[1]] or [args[2]]
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
      elseif n.kind=="plainconstant" then
        --res = `[n.type:toTerraType()](n.value)
        res = n.type:valueToTerra(n.value)
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
        table.insert(fixed.hists, tfn)
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

--        if fixed.isFixedType(n.type) then
--          res = `res._0
--        end
      elseif n.kind=="toSigned" then
        res = `[fixed.extract(n.type):toTerraType()]([args[1]])
      elseif n.kind=="abs" then
        res = `terralib.select([args[1]]>=0,[args[1]], -[args[1]])
        res = `[fixed.extract(n.type):toTerraType()](res)
      elseif n.kind=="not" then
        res = `not [args[1]]
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
--        if fixed.isFixedType(n.inputs[1].type) then
--          for k,v in pairs(args) do
--            inp[k] = `{v,nil}
--          end
--        end

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
        --print("LIFTFLOAT",n.type)
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
      elseif n.kind=="disablePipelining" then
        res = args[1]
      else
        print(n.kind)
        assert(false)
      end

      assert(terralib.isquote(res) or terralib.issymbol(res))
      return res
    end)

--  if fixed.isFixedType(self.type) then
--    res = `{res,nil}
--  end

  return res, inp
end

function fixedTerra.toDarkroom(ast)
  local terraout, terrainp = toTerra(ast)

  local terra tfn([terrainp], out:&ast.type:toTerraType())
    @out = terraout
  end

  return tfn
end

return fixedTerra
