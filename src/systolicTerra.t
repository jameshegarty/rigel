
-- return a terra quote
-- symbols: this is a map of parameter names to terra values
function systolicASTFunctions:toTerra( symbols )

  local stats = {}
  
  local finalOut = self:visitEach(
    function(n,args)
      local res
      
      if n.kind=="parameter" then
        res = symbols[n.name]
      elseif n.kind=="slice" then
        if n.inputs[1].type:isArray() then
          local iSz = n.inputs[1].type:arrayLength()
          local inW = iSz[1]
          local outW = n.idyHigh-n.idyLow+1

          local out = symbol(n.type:toTerraType())
          table.insert(stats, quote
            var [out]

            for y=n.idyLow,n.idyHigh+1 do
              for x=n.idxLow,n.idxHigh+1 do
                out[x+y*outW] = [args[1]][x+n.idxLow+(y+n.idyLow)*inW]
              end
            end
          end)

          return out
        elseif n.inputs[1].type:isTuple() then
          local out = symbol(n.type:toTerraType())

          table.insert(stats, quote var [out] end)

          return out
        else
          assert(false)
        end
      elseif n.kind=="cast" then

        if n.inputs[1].type:isArray() and n.type:isArray()==false then
          if n.inputs[1].type:channels()==1 and n.inputs[1].type:arrayOver()==n.type then
            res = `[args[1]][0]
          else
            print("CAST NYI:",n.inputs[1].type, n.type,n.loc)
            os.exit()
          end
        elseif n.inputs[1].type:isTuple() and n.type:isArray() and #n.inputs[1].type.list==n.type:channels() then
          --assert(false)
          local s = symbol(n.type:toTerraType())
          local stats = {}
          for k=0,n.type:channels()-1 do
            table.insert(stats, quote s[k] = [args[1]].["_"..k] end)
          end

          res = quote var [s]; [stats] in s end
        else
          print("CAST NYI:",n.inputs[1].type, n.type,n.loc)
          os.exit()
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
        print("Error, systolicAST:toTerra NYI:"..n.kind)
        os.exit(1)
      end

      assert(terralib.isquote(res) or terralib.issymbol(res))
      return res
    end)

  return quote [stats] in finalOut end
end
