-- NOTE: does typechecking in place! ast must be a table that's going to be thrown away!
local function typecheck_inner( ast, newNodeFn )
  assert(type(newNodeFn)=="function")
  
  if ast.kind=="constant" then
    err( types.isType(ast.type), "missing type for constant, "..ast.loc)
    ast.constLow_1 = ast.value; ast.constHigh_1 = ast.value
  elseif ast.kind=="unary" then
    local expr = ast.inputs[1]
    
    if ast.op=="-" then
      if expr.type:isUint() then
        darkroom.warning("You're negating a uint, this is probably not what you want to do!", origast:linenumber(), origast:offset(), origast:filename())
      end
      
      ast.type = ast.expr.type
      if type(ast.expr.constLow_1)=="number" then 
        ast.constLow_1 = -ast.expr.constLow_1; ast.constHigh_1 = -ast.expr.constHigh_1; 
        if ast.constLow_1 > ast.constHigh_1 then ast.constLow_1, ast.constHigh_1 = ast.constHigh_1, ast.constLow_1 end
      end
    elseif ast.op=="floor" or ast.op=="ceil" then
      ast.type = darkroom.type.float(32)
    elseif ast.op=="abs" then
      if expr.type:baseType():isFloat() or expr.type:baseType():isInt() or expr.type:baseType():isUint() then
        -- obv can't make it any bigger
        ast.type = expr.type
      else
        expr.type:print()
        assert(false)
      end
    elseif ast.op=="not" then
      if expr.type:baseType():isBool() or expr.type:baseType():isInt() or expr.type:baseType():isUint() then
        ast.type = expr.type
      else
        error("not only works on bools and integers, "..ast.loc)
      end
    elseif ast.op=="sin" or ast.op=="cos" or ast.op=="exp" or ast.op=="arctan" or ast.op=="ln" or ast.op=="sqrt" then
      if ast.expr.type==darkroom.type.float(32) then
        ast.type = darkroom.type.float(32)
      elseif ast.expr.type==darkroom.type.float(64) then
        ast.type = darkroom.type.float(64)
      else
        darkroom.error("sin, cos, arctan, ln and exp only work on floating point types, not "..ast.expr.type:str(), origast:linenumber(), origast:offset(), origast:filename() )
      end
    elseif ast.op=="arrayAnd" then
      if ast.expr.type:isArray() and ast.expr.type:arrayOver():isBool() then
        ast.type = darkroom.type.bool()
      else
        darkroom.error("vectorAnd only works on arrays of bools", origast:linenumber(), origast:offset(), origast:filename() )
      end
    elseif ast.op=="print" then
      ast.type = ast.expr.type
    elseif ast.op=="isX" then
      ast.type = types.bool()
    else
      print(ast.op)
      assert(false)
    end
    
  elseif ast.kind=="binop" then
    local lhs = ast.inputs[1]
    local rhs = ast.inputs[2]
    
    assert(lhs.type~=nil)
    assert(rhs.type~=nil)
    
    if type(lhs.constLow_1)=="number" and type(rhs.constLow_1)=="number" then
      local function applyop(lhslow, lhshigh, rhslow, rhshigh, op)
        local a = op(lhslow,rhslow)
        local b = op(lhslow,rhshigh)
        local c = op(lhshigh,rhslow)
        local d = op(lhshigh,rhshigh)
        return math.min(a,b,c,d), math.max(a,b,c,d)
      end

      if ast.op=="+" then
        ast.constLow_1, ast.constHigh_1 = applyop( lhs.constLow_1, lhs.constHigh_1, rhs.constLow_1, rhs.constHigh_1, function(l,r) return l+r end)
      elseif ast.op=="-" then
        ast.constLow_1, ast.constHigh_1 = applyop( lhs.constLow_1, lhs.constHigh_1, rhs.constLow_1, rhs.constHigh_1, function(l,r) return l-r end)
      elseif ast.op=="*" then
        ast.constLow_1, ast.constHigh_1 = applyop( lhs.constLow_1, lhs.constHigh_1, rhs.constLow_1, rhs.constHigh_1, function(l,r) return l*r end)
      elseif ast.op=="/" then
        ast.constLow_1, ast.constHigh_1 = applyop( lhs.constLow_1, lhs.constHigh_1, rhs.constLow_1, rhs.constHigh_1, function(l,r) return l/r end)
      end
    end

    local thistype, lhscast, rhscast = types.meet( lhs.type, rhs.type, ast.op, ast.loc )
    
    if thistype==nil then
      darkroom.error("Type error, inputs to "..ast.op,origast:linenumber(), origast:offset(), origast:filename())
    end
    
    if lhs.type~=lhscast then lhs = newNodeFn({kind="cast",inputs={lhs},type=lhscast,loc=debug.traceback()}) end
    if rhs.type~=rhscast then rhs = newNodeFn({kind="cast",inputs={rhs},type=rhscast,loc=debug.traceback()}) end
    
    ast.type = thistype
    ast.inputs = {lhs,rhs}
    
  elseif ast.kind=="select" or ast.kind=="vectorSelect" then
    local cond = ast.inputs[1]
    local a = ast.inputs[2]
    local b = ast.inputs[3]

    if ast.kind=="vectorSelect" then
      if cond.type:arrayOver()~=darkroom.type.bool() then
        print("IB",cond.type:arrayOver())
        darkroom.error("Error, condition of vectorSelect must be array of booleans. ", origast:linenumber(), origast:offset(), origast:filename() )
        return nil
      end

      if cond.type:isArray()==false or
        a.type:isArray()==false or
        b.type:isArray()==false or
        a.type:arrayLength()~=b.type:arrayLength() or
        cond.type:arrayLength()~=a.type:arrayLength() then
        darkroom.error("Error, all arguments to vectorSelect must be arrays of the same length", origast:linenumber(), origast:offset(), origast:filename() )
        return nil            
      end
    else
      err( cond.type == types.bool(), "Error, condition of select must be scalar boolean. Use vectorSelect" )
      err( a.type:isArray()==b.type:isArray(), "Error, if any results of select are arrays, all results must be arrays")
      err( a.type:isArray()==false or (a.type:arrayLength()==b.type:arrayLength()), "Error, array arguments to select must be the same length")
    end

    local thistype, lhscast, rhscast =  types.meet( a.type, b.type, ast.kind, ast.loc )

    if a.type~=lhscast then a = newNodeFn({kind="cast",inputs={a},type=lhscast,loc=debug.traceback()}) end
    if b.type~=rhscast then b = newNodeFn({kind="cast",inputs={b},type=rhscast,loc=debug.traceback()}) end
    
    ast.type = thistype
    ast.inputs[1] = cond
    ast.inputs[2] = a
    ast.inputs[3] = b
    
  elseif ast.kind=="bitSlice" then
    local expr = ast.inputs[1]
    local max = expr.type:verilogBits()

    err( ast.low>=0 and ast.high>=0, "bitslice low/high must be >=0")
    err( ast.low<max and ast.high<max, "bitslice low("..ast.low..")/high("..ast.high..") must be < type size ("..max..")")
    err( ast.low<=ast.high, "bitslice low must be <= high")
    
    ast.type = types.bits(ast.high-ast.low+1)
  elseif ast.kind=="slice" then
    local expr = ast.inputs[1]

    err(expr.type:isArray() or expr.type:isTuple(), "Error, you can not index into an this type! Type is "..tostring(expr.type)..ast.loc)    
    err( ast.idxLow<=ast.idxHigh, "idxLow>idxHigh")
    err( ast.idyLow<=ast.idyHigh, "idyLow>idyHigh")
    
    if expr.type:isArray() then
      err( ast.idxLow < (expr.type:arrayLength())[1] and ast.idxLow>=0, "idxLow is out of bounds, "..tostring(ast.idxLow).." but should be <"..tostring((expr.type:arrayLength())[1])..", "..ast.loc)
      err( ast.idxHigh < (expr.type:arrayLength())[1] and ast.idxHigh>=0, "idxHigh is out of bounds, "..tostring(ast.idxHigh).." but should be <"..tostring((expr.type:arrayLength())[1])..", "..ast.loc)
      err( ast.idyLow==nil or ast.idyLow < (expr.type:arrayLength())[2] and ast.idyLow>=0, "idy is out of bounds, is "..tostring(ast.idyLow).." but should be <"..tostring((expr.type:arrayLength())[2]))
      err( ast.idyHigh==nil or ast.idyHigh < (expr.type:arrayLength())[2] and ast.idyHigh>=0, "idy is out of bounds, is "..tostring(ast.idyHigh).." but should be <"..tostring((expr.type:arrayLength())[2])..", "..ast.loc)
      ast.type = types.array2d(expr.type:arrayOver(), ast.idxHigh-ast.idxLow+1, ast.idyHigh-ast.idyLow+1 )
    elseif expr.type:isTuple() then
      err( ast.idxLow < #expr.type.list, "idxLow is out of bounds of tuple. Index is "..ast.idxLow.." but should be < "..#expr.type.list.." "..ast.loc)
      err( ast.idxHigh < #expr.type.list, "idxHigh is out of bounds of tuple. Index is "..ast.idxHigh.." but should be < "..#expr.type.list.." "..ast.loc)
      err( ast.idyLow==nil or ast.idyLow==0, "idyLow should be nil "..ast.loc)
      err( ast.idyHigh==nil or ast.idyHigh==0, "idyHigh should be nil "..ast.loc)

      local outlist = slice(expr.type.list, ast.idxLow+1, ast.idxHigh+1)

      ast.type = types.tuple( outlist )
    else
      assert(false)
    end
    
  elseif ast.kind=="transform" then
    ast.expr = inputs["expr"]
    
    -- this just gets the value of the thing we're translating
    ast.type = ast.expr.type
    
    local i=1
    while ast["arg"..i] do
      ast["arg"..i] = inputs["arg"..i] 
      i=i+1
    end
    
    -- now make the new transformBaked node out of this
    local newtrans = {kind="transformBaked",expr=ast.expr,type=ast.expr.type}
    
    local noTransform = true

    local i=1
    while ast["arg"..i] do
      -- if we got here we can assume it's valid
      local translate, multN, multD = darkroom.typedAST.synthOffset( inputs["arg"..i], inputs["zeroedarg"..i], darkroom.dimToCoord[i])

      if translate==nil then
        darkroom.error("Error, non-stencil access pattern", origast:linenumber(), origast:offset(), origast:filename())
      end

      assert(type(translate.constLow_1)=="number")
      assert(type(translate.constHigh_1)=="number")
      assert(translate.type:isInt() or translate.type:isUint())

      newtrans["translate"..i]=translate
      newtrans["scaleN"..i]=multD*ast.expr["scaleN"..i]
      newtrans["scaleD"..i]=multN*ast.expr["scaleD"..i]

      if translate~=0 or multD~=1 or multN~=1 then noTransform = false end
      i=i+1
    end
    
    -- at least 2 arguments must be specified. 
    -- the parser was supposed to guarantee this.
    assert(i>2)

    if noTransform then -- eliminate unnecessary transforms early
      ast=ast.expr:shallowcopy()
    else
      ast=newtrans
    end

  elseif ast.kind=="tuple" then
    err( #ast.inputs>0, "no inputs to tuple? "..ast.loc )
    local ty = map(ast.inputs, function(t) assert(types.isType(t.type)); return t.type end )
    ast.type = types.tuple(ty)
  elseif ast.kind=="array" then
    local typeOver
    for k,v in pairs(ast.inputs) do
      if typeOver~=nil then err( v.type==typeOver, "input type to array operator doesn't match, is "..tostring(v.type).." but should be "..tostring(typeOver)..", "..ast.loc) end
      typeOver = v.type
    end
    ast.type = types.array2d( typeOver, ast.W, ast.H )
  elseif ast.kind=="cast" then
    if types.checkExplicitCast( ast.inputs[1].type, ast.type, ast)==false then
      error("Casting from "..tostring(ast.inputs[1].type).." to "..tostring(ast.type).." isn't allowed! "..ast.loc)
    end
  else
    error("Internal error, typechecking for "..ast.kind.." isn't implemented! "..ast.loc)
    return nil
  end

  if types.isType(ast.type)==false then print("missing type",ast.kind) end
  assert(types.isType(ast.type))
  if type(ast.constLow_1)=="number" then assert(ast.constLow_1<=ast.constHigh_1) end

  return ast
end

return function( ast, newNodeFn )
  local out = typecheck_inner( ast, newNodeFn )

  local allConstInput = true

  for k,v in pairs(ast.inputs) do if v.type:const()==false then allConstInput=false end end

  -- sanity check: out is const <=> inputs are all const
  if (ast.type:const() and allConstInput==false) then
    if ast.kind~="slice" then
      print("Inputs aren't const, but output is!",ast.kind)
      assert(false)
    end
  end

  if (ast.type:const()==false and allConstInput) then
    if ast.kind~="cast" then
      print("Lost constness?",ast.kind)
      assert(false)
    end
  end

  return out
end