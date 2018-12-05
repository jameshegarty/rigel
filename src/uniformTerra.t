-- uniform:toTerra()
return function(slf)
  return slf:visitEach(
    function(n,inputs)
      if n.kind=="const" then
        return `n.value
      elseif n.kind=="global" then
        return n.global:terraValue()
      elseif n.kind=="binop" then
        if n.op=="mul" then
          return `[inputs[1]]*[inputs[2]]
        elseif n.op=="sub" then
          return `[inputs[1]]-[inputs[2]]
        else
          print("Uniform:toTerra() NYI - op "..n.op)
          assert(false)
        end
      else
        print("Uniform:toTerra() NYI - "..n.kind)
        assert(false)
      end
    end)
end
                
