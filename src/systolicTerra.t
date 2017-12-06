local J = require "common"
local cstdlib = terralib.includec("stdlib.h")
local err = J.err

-- return a terra quote
-- symbols: this is a map of parameter names to terra values
function systolicASTFunctions:toTerra( symbols )

  local stats = {}
  
  local finalOut = self:visitEach(
    function(n,args)
      local res
      
      if n.kind=="parameter" then
        res = symbols[n.name]
      elseif n.kind=="constant" then
        res = self.type:valueToTerra(n.value)
      elseif n.kind=="binop" then
        if n.op=="and" then
          res = `[args[1]] and [args[2]]
        elseif n.op=="==" then
          res = `[args[1]] == [args[2]]
        elseif n.op=="+" then
          res = `[args[1]] + [args[2]]
        elseif n.op=="-" then
          res = `[args[1]] - [args[2]]
        elseif n.op=="*" then
          res = `[args[1]] * [args[2]]
        elseif n.op==">>" then
          res = `[args[1]] >> [args[2]]
        elseif n.op=="<<" then
          res = `[args[1]] << [args[2]]
        elseif n.op=="<" then
          res = `[args[1]] < [args[2]]
        else
          err(false,"systolicAST:toTerra Binop NYI: "..n.op)
        end
      elseif n.kind=="unary" then
        if n.op=="abs" then
          if n.inputs[1].type:isInt() then
            res = `cstdlib.abs([args[1]])
          else
            err(false,"systolicAST:toTerra NYI abs with type "..tostring(n.inputs[1].type))
          end
        elseif n.op=="-" then
          res = `-[args[1]]
        else
          err(false,"systolicAST:toTerra unary NYI: "..n.op)
        end
      elseif n.kind=="select" then
        res = `terralib.select([args[1]], [args[2]], [args[3]] )
      elseif n.kind=="slice" then
        if n.inputs[1].type:isArray() then
          local iSz = n.inputs[1].type:arrayLength()
          local inW = iSz[1]
          local outW = n.idyHigh-n.idyLow+1

          res = symbol(n.type:toTerraType())
          table.insert(stats, quote
            var [res]

            for y=n.idyLow,n.idyHigh+1 do
              for x=n.idxLow,n.idxHigh+1 do
                res[(x-n.idxLow)+(y-n.idyLow)*outW] = [args[1]][x+y*inW]
              end
            end
          end)
        elseif n.inputs[1].type:isTuple() then
          res = symbol(n.type:toTerraType())
          table.insert(stats, quote var [res] end)

          for i=n.idxLow,n.idxHigh do
            table.insert(stats, quote res.["_"..(i-n.idxLow)] = [args[1]].["_"..i] end)
          end
        else
          assert(false)
        end
      elseif n.kind=="cast" then

        if n.inputs[1].type:isArray() and n.type:isArray()==false then
          -- casting array to something not an array
          
          if n.inputs[1].type:channels()==1 and n.inputs[1].type:arrayOver()==n.type then
            -- casting [A] to A
            res = `[args[1]][0]
          else
            err(false, ":toTerra CAST NYI: "..tostring(n.inputs[1].type).." to "..tostring(n.type).." "..n.loc)
          end
        elseif n.inputs[1].type:isTuple() and n.type:isArray() and #n.inputs[1].type.list==n.type:channels() and n.inputs[1].type.list[1]==n.type:arrayOver() and J.allTheSame(n.inputs[1].type.list) then
          -- cast tuple to array of same size
	  -- ie {A,A,A} to A[3]
          local s = symbol(n.type:toTerraType())
	  print("TARGET",s,n.type:toTerraType(),n.type,n.inputs[1].type)
          table.insert(stats,quote var [s] end)
          for k=0,n.type:channels()-1 do
            table.insert(stats, quote s[k] = [args[1]].["_"..k] end)
          end

          res = s
        elseif n.inputs[1].type:isTuple() and #n.inputs[1].type.list==1 and n.type==n.inputs[1].type.list[1] then
          -- cast {A} to A
          res = symbol(n.type:toTerraType())
          table.insert(stats,quote var [res]; res = [args[1]]._0 end)
        elseif n.inputs[1].type:isBits() and n.type:isUint() and n.inputs[1].type.precision==n.type.precision then
          res = args[1]
        elseif (n.inputs[1].type:isInt() or n.inputs[1].type:isUint()) and (n.type:isInt() or n.type:isUint()) then
          err( n.inputs[1].type:isUint() or n.inputs[1].type:verilogBits()==8 or n.inputs[1].type:verilogBits()==16 or n.inputs[1].type:verilogBits()==32, "NYI cast "..tostring(n.inputs[1].type) )
          assert( n.type:verilogBits()==8 or n.type:verilogBits()==16 or n.type:verilogBits()==32 )
          
          res = `[n.type:toTerraType()]([args[1]])
        else
          err(false, ":toTerra CAST NYI: "..tostring(n.inputs[1].type).." to "..tostring(n.type).." "..n.loc)
        end
      elseif n.kind=="tuple" then
        local s = symbol(n.type:toTerraType())
        --local stats = {}
        table.insert(stats,quote var [s] end)
        for k,v in ipairs(args) do
          table.insert(stats, quote s.["_"..(k-1)] = [v] end)
        end

        res = s
      elseif n.kind=="bitSlice" then
        local s = symbol(n.type:toTerraType())
        local q = quote
          var sft = [args[1]] >> [n.low]
          var mask : n.inputs[1].type:toTerraType() = 1
          mask = (mask << [n.high-n.low+1]) - 1
          var [s] = sft and mask
        end
        table.insert(stats,q)
        res = s
      else
        err(false,"Error, systolicAST:toTerra NYI:"..n.kind)
      end

      assert(terralib.isquote(res) or terralib.issymbol(res))
      return res
    end)

  local out = quote [stats] in finalOut end
--  out:printpretty()
  return out
end
