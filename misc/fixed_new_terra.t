local cmath = terralib.includec("math.h")
local cstdlib = terralib.includec("stdlib.h")
local cstdio = terralib.includec("stdio.h")
local types = require("types")
local S = require("systolic")
local MT = require("modulesTerra")

local fixedNewTerra={}

local function toTerra(self,name)
  assert(type(name)=="string")
  
  local inp
  local stats = {}
  local resetStats = {}
  local initStats = {}
  local freeStats = {}

  local Module = terralib.types.newstruct(name)
  Module.entries = terralib.newlist( {} )

  local res = self:visitEach(
    function( n, args )
      if n.kind=="applyUnaryLiftRigel" then
        table.insert( Module.entries, {field=n.name, type=n.f.terraModule})
      end
    end)
    
  local mself = symbol(&Module, "moduleself")
  
  local res = self:visitEach(
    function( n, args )
      local res
      if n.kind=="parameter" then
        inp = symbol(&n.type:toTerraType(), n.name)
        --res = `@inp
        res = symbol(n.type:toTerraType())
        table.insert(stats, quote var[res] = @[inp] end)
        --if n.type:isNamed() and n.type.generator=="fixed" then
        --  res = `res._0
        --end
      elseif n.kind=="binop" then
        if n.op==">" then
          res = `[args[1]]>[args[2]]
        elseif n.op==">=" then
          res = `[args[1]]>=[args[2]]
        elseif n.op=="<" then
          res = `[args[1]]<[args[2]]
        elseif n.op=="<=" then
          res = `[args[1]]<=[args[2]]
        elseif n.op=="==" then
          res = `[args[1]]==[args[2]]
        elseif n.op=="~=" then
          res = `[args[1]]~=[args[2]]
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
        res = `[n:underlyingType():toTerraType()]([args[1]])
      elseif n.kind=="abs" then
        res = `terralib.select([args[1]]>=0,[args[1]], -[args[1]])
        res = `[n:underlyingType():toTerraType()](res)
      elseif n.kind=="rcp" then

        local numerator, denom, isPositive, uintType
        if n:isSigned() then
          -- signed behavior: basically, remember the sign, take abs, do unsigned div, then add back sign
          uintType = n:underlyingType()
          local intType = types.int(uintType.precision)
          uintType = types.uint(uintType.precision)
          numerator = `[uintType:toTerraType()]([math.pow(2,n.inputs[1]:precision()-1)])

          denom = `[intType:toTerraType()]([args[1]])
          denom = `[uintType:toTerraType()](terralib.select(denom>0,denom,-denom))

          isPositive = `[args[1]]>=0
        else
          uintType = n:underlyingType()

          numerator = `[uintType:toTerraType()]([math.pow(2,n.inputs[1]:precision())])

          denom = `[uintType:toTerraType()]([args[1]])
        end
        

        -- need to prevent divides by 0
        local origdenom = denom
        denom = `terralib.select(denom==0,[uintType:toTerraType()](1),denom)
        res = `numerator/denom

        -- if denom==0, the HW module returns all 1's?
        local MAXV = math.pow(2,n:precision())-1

        res = `terralib.select(origdenom==0,[uintType:toTerraType()](MAXV),res)

        if isPositive~=nil then
          --          res = S.select(isPositive,res,S.neg(res))
          res = `terralib.select(isPositive,res,-res)
        end
      elseif n.kind=="neg" then
        res = `-[args[1]]
      elseif n.kind=="applyUnaryLiftRigel" then
        res = symbol(n.type:toTerraType())
        table.insert(stats,quote var[res];
                     var tmp : n.inputs[1].type:toTerraType() = [args[1]] -- input must be lvalue
                     mself.[n.name]:process( &tmp, &res )
                     end)
        if n.f.stateful then
          table.insert(resetStats, quote mself.[n.name]:reset() end )
        end

        table.insert(initStats, quote mself.[n.name]:init() end )
        table.insert(freeStats, quote mself.[n.name]:free() end )
      elseif n.kind=="applyUnaryLiftSystolic" then
        local si = S.parameter("inp",n.inputs[1].type)
        res = symbol(n.type:toTerraType())
        
        local svalue = n.f(si)
        table.insert(stats, quote var [res] =  [svalue:toTerra{inp=args[1]}] end )
      elseif n.kind=="applyBinaryLiftSystolic" then
        local si0 = S.parameter("inp0",n.inputs[1].type)
        local si1 = S.parameter("inp1",n.inputs[2].type)
        res = symbol(n.type:toTerraType())
        
        local svalue = n.f(si0,si1)
        table.insert(stats, quote var [res] =  [svalue:toTerra{inp0=args[1],inp1=args[2]}] end )
      elseif n.kind=="applyTrinaryLiftSystolic" then
        local si0 = S.parameter("inp0",n.inputs[1].type)
        local si1 = S.parameter("inp1",n.inputs[2].type)
        local si2 = S.parameter("inp2",n.inputs[3].type)
        res = symbol(n.type:toTerraType())
        
        local svalue = n.f(si0,si1,si2)
        table.insert(stats, quote var [res] =  [svalue:toTerra{inp0=args[1],inp1=args[2],inp2=args[3]}] end )
      elseif n.kind=="applyNaryLiftSystolic" then
        local si = {}
        local symbols = {}
        for k,v in ipairs(n.inputs) do
          table.insert( si, S.parameter("inp"..k,v.type) )
          symbols["inp"..k] = args[k]
        end

        res = symbol(n.type:toTerraType())
        
        local svalue = n.f(si)
        table.insert(stats, quote var [res] = [svalue:toTerra(symbols)] end)
      elseif n.kind=="addLSBs" then
        --print("ADDLSBS",n.type,n.N)
        res = `[n.type:toTerraType()]([args[1]])
        res = `res << n.N
      elseif n.kind=="removeLSBs" then
        res = `[args[1]] >> n.N
        res = `[n.type:toTerraType()](res)
      elseif n.kind=="addMSBs" then
        res = `[n.type:toTerraType()]([args[1]])
      elseif n.kind=="removeMSBs" then
        if n:isSigned() then
          local outbits = n:precision()

          local usInputType = types.uint(n.inputs[1]:precision())
          
          res = quote
            var mask = ([usInputType:toTerraType()](1) << outbits) - 1
            var msb = [usInputType:toTerraType()](1) << (outbits-1)
            var notmask = not mask

            var inpuint = [usInputType:toTerraType()]([args[1]])
            var masked = inpuint and mask

            -- extend the sign bit so that the CPU thinks this number has the correct sign
            -- note that we set the sign bit based on the MSB of the _masked_ portion. This is what verilog will do.
            -- DO NOT set sign bit based on sign bit of (unmaked) input.
            if (masked and msb) ~=0 then
              masked = masked or notmask
            end

            var r = [n.type:toTerraType()](masked)
            in r end
        else
          local outbits = n:precision()
          res = quote
            var mask = ([n.inputs[1].type:toTerraType()](1) << outbits) - 1
            var r = [n.type:toTerraType()]([args[1]] and mask)
            in r end
        end
      elseif n.kind=="readGlobal" then
        res = `[n.global:terraValue()]
      else
        print(n.kind)
        assert(false)
      end

      assert(terralib.isquote(res) or terralib.issymbol(res))
      return res
    end)

  return res,stats, inp, Module, mself, resetStats, initStats, freeStats
end

function fixedNewTerra.toDarkroom(ast,name)
  local terraout, stats,terrainp, Module, mself, resetStats, initStats, freeStats = toTerra(ast,name)

  terra Module.methods.process([mself],[terrainp], out:&ast.type:toTerraType() )
    [stats]
    @out = terraout
  end

  --Module.methods.process:printpretty(true)

  terra Module.methods.reset( [mself] ) [resetStats] end
  terra Module.methods.init( [mself] ) [initStats] end
  terra Module.methods.free( [mself] ) [freeStats] end

  return MT.new(Module)
end

return fixedNewTerra
