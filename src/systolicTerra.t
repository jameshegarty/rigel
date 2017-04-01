
-- return a terra quote
-- symbols: this is a map of parameter names to terra values
function systolicASTFunctions:toTerra( symbols )

  local stats = {}
  
  local finalOut = self:visitEach(
    function(n,args)
      local res
      
      if n.kind=="parameter" then
        res = symbols[n.name]
      elseif n.kind=="binop" then
        if n.op=="and" then
          res = `[args[1]] and [args[2]]
        elseif n.op=="==" then
          res = `[args[1]] == [args[2]]
        else
          err(false,"systolicAST:toTerra Binop NYI: "..n.op)
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
        elseif n.inputs[1].type:isTuple() and n.type:isArray() and #n.inputs[1].type.list==n.type:channels() then
          -- cast tuple to array of same size
          local s = symbol(n.type:toTerraType())
          table.insert(stats,quote var [s] end)
          for k=0,n.type:channels()-1 do
            table.insert(stats, quote s[k] = [args[1]].["_"..k] end)
          end

          res = s
        elseif n.inputs[1].type:isTuple() and #n.inputs[1].type.list==1 and n.type==n.inputs[1].type.list[1] then
          -- cast {A} to A
          res = symbol(n.type:toTerraType())
          table.insert(stats,quote var [res]; res = [args[1]]._0 end)

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
