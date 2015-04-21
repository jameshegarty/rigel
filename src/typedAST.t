typedASTFunctions={}
setmetatable(typedASTFunctions,{__index=IRFunctions})
typedASTMT={__index=typedASTFunctions,
  __newindex = function(table, key, value)
                    darkroom.error("Attempt to modify typed AST node")
                  end}

darkroom.typedAST = {}
CTABMODE = ""
-- This function tracks in what basic blocks each value
-- is needed. This does not necessary say that they need to be
-- computed in that block, but their value is needed.
darkroom.typedAST._bbDependenciesCache=setmetatable({}, {__mode=CTABMODE})
darkroom.typedAST._topbb = {level=0,parents={},controlDep={}}
function typedASTFunctions:bbDependencies(root)
  if darkroom.typedAST._bbDependenciesCache[root]==nil then
    darkroom.typedAST._bbDependenciesCache[root]=setmetatable({}, {__mode=CTABMODE})
  end

  if darkroom.typedAST._bbDependenciesCache[root][self]==nil then
    darkroom.typedAST._bbDependenciesCache[root][self] = setmetatable({},{__mode=CTABMODE})

    if self==root then
      darkroom.typedAST._bbDependenciesCache[root][self][darkroom.typedAST._topbb] = 1
    else
      assert(self:parentCount(root)>0)
      for parentNode, key in self:parents(root) do
        if (parentNode.kind=="mapreduce" and key=="expr") or parentNode.kind=="filter" or (parentNode.kind=="iterate" and key=="expr") then
          assert(self:parentCount(root)==1) -- theoretically possible this is false?
          -- generate a new block for this MR
          local newbb = {level=0,parents={},controlDep={}}
          if parentNode.kind=="filter" then newbb.controlDep[newbb]=1 end -- filter ifelse has control dep on itself
          for bb,_ in pairs(parentNode:bbDependencies(root)) do
            newbb.level = math.max(bb.level+1, newbb.level)
            newbb.parents[bb] = 1
            for cd,_ in pairs(bb.controlDep) do
              newbb.controlDep[cd] = 1
            end
          end
          darkroom.typedAST._bbDependenciesCache[root][self][newbb] = 1
        else
          -- this node is in all the basic blocks that read it
          for bb,_ in pairs(parentNode:bbDependencies(root)) do
            darkroom.typedAST._bbDependenciesCache[root][self][bb] = 1
          end
        end
      end
    end
    assert(type(darkroom.typedAST._bbDependenciesCache[root][self])=="table")
  end

  return darkroom.typedAST._bbDependenciesCache[root][self]
end

-- return the basic block in which we should calculate this
-- node. This should be as shallow as possible w/o leaving
-- the correct scope.
darkroom.typedAST._calculateBBCache=setmetatable({}, {__mode=CTABMODE})
function typedASTFunctions:calculateBB(root)
  if darkroom.typedAST._calculateBBCache[root]==nil then
    darkroom.typedAST._calculateBBCache[root]=setmetatable({}, {__mode=CTABMODE})
  end

  if darkroom.typedAST._calculateBBCache[root][self]==nil then
    darkroom.typedAST._calculateBBCache[root][self]=setmetatable({}, {__mode=CTABMODE})

    if self.kind=="mapreducevar" then
      local MR = root:lookup(self.mapreduceNodeKey)

      local dep = MR.expr:bbDependencies(root)
      assert(keycount(dep)==1)
      for k,v in pairs(dep) do
        darkroom.typedAST._calculateBBCache[root][self][k] = 1
      end
    elseif self.kind=="iterationvar" then
      local I = root:lookup(self.iterateNode)

      local dep = I.expr:bbDependencies(root)
      assert(keycount(dep)==1)
      for k,v in pairs(dep) do
        darkroom.typedAST._calculateBBCache[root][self][k] = 1
      end
    elseif self.kind=="lifted" then
      local mrcnt = 1
      while self["mapreduceNode"..mrcnt]~=nil do
        local MR = root:lookup(self["mapreduceNode"..mrcnt])
        
        local dep = MR.expr:bbDependencies(root)
        assert(keycount(dep)==1)
        for k,v in pairs(dep) do
          darkroom.typedAST._calculateBBCache[root][self][k] = 1
        end
        mrcnt = mrcnt + 1
      end
    elseif self.kind=="mapreduce" or self.kind=="iterate" then
      -- mapreduce itself should belong to a bb one level above
      -- where its input is
      local dep = self.expr:bbDependencies(root)
      assert(keycount(dep)==1)
      local thisbb
      for k,v in pairs(dep) do thisbb=k end

      local t = {"expr"}
      if self.kind=="mapreduce" then 
        for k,v in pairs(self) do 
          if k:sub(0,6)=="lifted" then table.insert(t,k) end 
        end 
      end

      for _,key in pairs(t) do
        local cb = self[key]:calculateBB(root)
        for k,v in pairs(cb) do
          if k~=thisbb then darkroom.typedAST._calculateBBCache[root][self][k]=1 end
        end
      end
    else
      darkroom.typedAST._calculateBBCache[root][self][darkroom.typedAST._topbb] = 1
      for k,v in self:inputs() do
        local cb = v:calculateBB(root)
        for kk,__ in pairs(cb) do
          darkroom.typedAST._calculateBBCache[root][self][kk] = 1
        end
      end
    end
    assert(type(darkroom.typedAST._calculateBBCache[root][self])=="table")
  end

  return darkroom.typedAST._calculateBBCache[root][self]
end

function typedASTFunctions:calculateMinBB(root)
  ------------------
  -- for control dependencies, we want it to be as deep as possible,
  -- but it still needs to be above its control dependencies.
  -- eg (if a+1 then a+3 end), a has to be above the if
  -- (if 3+4 then a+3 end), a can be in the expr block

  local shallowest
  for bb,_ in pairs(self:bbDependencies(root)) do
    for cb,_ in pairs(bb.controlDep) do
      if shallowest==nil or cb.level<shallowest.level then
        shallowest = cb
      elseif shallowest.level==cb.level then
        assert(keycount(cb.parents)==1)
        for k,_ in pairs(cb.parents) do
          shallowest = k
        end
      end
    end
  end

  ------------------
  -- consider map i=-1,1 reduce(sum) map j=-1,1 reduce(sum) i+j end end
  -- we must place (i+j) at the deepest level (inside the second MR), or else
  -- we will not have all the data we need. This is why we place stuff in the deepest level.
  local cb = self:calculateBB(root)
  local deepest = darkroom.typedAST._topbb
  for k,v in pairs(cb) do
    if k.level > deepest.level then deepest = k end
  end

  -- consider map i=-1,1 reduce(sum) map j=-1,1 reduce(sum) (i+j)+(iterate w=-1-1 reduce(sum) (i+j) end) end end
  -- We want to put the (i+j) above the control dependency, b/c we only pass data down into deeper scopes.
  -- OTOH, with map i=-1,1 reduce(sum) map j=-1,1 reduce(sum) (iterate w=-1-1 reduce(sum) (i+j) end) end end
  -- it's ok to put it in the control dependency
  if shallowest~=nil and shallowest.level>deepest.level then
    return shallowest
  else
    return deepest
  end
end

function darkroom.typedAST.checkConstantExpr(expr, coord)

  -- no x+x allowed
  if coord~=nil and expr:S("position"):count() ~= 1 then
return false
  end

  expr:S("*"):traverse( 
    function(n)
      if expr.kind=="binop" then
        if expr.op~="+" and expr.op~="-" and expr.op~="*" and expr.op~="/" then
          darkroom.error("binop '"..expr.op.."' is not supported in an constant expr")
        end
      elseif expr.kind=="value" then
        if type(expr.value)~="number" then
          darkroom.error("type "..type(expr.value).." is not supported in constant expr")
        end
      elseif coord~=nil and expr.kind=="position" then
        if expr.coord~=coord then
          darkroom.error("you can't use coord "..expr.coord.." in expression for coord "..coord)
        end
      elseif expr.kind=="cast" then
      elseif expr.kind=="mapreducevar" then
      elseif expr.kind=="iterationvar" then
      else
        darkroom.error(expr.kind.." is not supported in constant expr")    
      end
    end)

  return true
end

-- take the ast input that's an offset expr for coord 'coord'
-- and convert it into a translate,scale. returns nil if there was an error.
function darkroom.typedAST.synthOffset(ast, zeroedarg, coord)
  assert(darkroom.typedAST.isTypedAST(ast))
  assert(darkroom.typedAST.isTypedAST(zeroedarg))

  -- first check that there isn't anything in the expression that's definitely not allowed...
  if darkroom.typedAST.checkConstantExpr(ast,coord)==false then
return nil
  end

  -- now distribute the multiplies until they can't be distributed any more. ((x+i)+j) * 2 => (x*2 + i*2)+j*2
  
  -- now, the path up the tree from the position to the root should only have 1 multiply and >=0 adds
  -- note that this thing must be a tree!
  local pos
  local mulCount = 0
  local addCount = 0

  local multN = 1
  local multD = 1
  ast:S("position"):traverse(function(n) assert(pos==nil); pos = n end)

  for n,k in pos:parents(ast) do 
    if n.kind=="binop" and (n.op=="+" or n.op=="-") then addCount = addCount+1
    elseif n.kind=="binop" and (n.op=="*" or n.op=="/") then
      assert(mulCount==0); mulCount=1
      if n.op=="*" and k=="lhs" then assert(n.rhs.kind=="value"); multN = n.rhs.value 
      elseif n.op=="*" and k=="rhs" then assert(n.lhs.kind=="value"); multN = n.lhs.value 
      elseif n.op=="/" and k=="lhs" then assert(n.rhs.kind=="value"); multD = n.rhs.value 
      elseif n.op=="/" and k=="rhs" then assert(n.lhs.kind=="value"); multD = n.lhs.value 
      else assert(false) end
    else print(n.kind,n.op);assert(false) end
  end

  -- cheap hack, since the path from the position to the root is just a bunch of adds,
  -- we can get the translation by setting the position to 0
  local translate = zeroedarg
  assert(translate:S("position"):count()==0)
  translate:S("*"):process(function(n) assert(type(n.constLow_1)=="number"); assert(darkroom.type.isType(n.type)) end)

  return translate, multN, multD
end

-- returns the stencil with (0,0,0) at the origin
-- if input isn't null, only calculate stencil for this input (a kernelGraph node)
function typedASTFunctions:stencil(input, typedASTRoot)
  assert(type(typedASTRoot)=="table")

  if self.kind=="binop" then
    return self.lhs:stencil(input,typedASTRoot):unionWith(self.rhs:stencil(input,typedASTRoot))
  elseif self.kind=="multibinop" then
    local res = Stencil.new()

    for i=1,self:arraySize("lhs") do
      res = res:unionWith(self["lhs"..i]:stencil(input,typedASTRoot))
    end

    for i=1,self:arraySize("rhs") do
      res = res:unionWith(self["rhs"..i]:stencil(input,typedASTRoot))
    end

    return res
  elseif self.kind=="multiunary" then
    local res = Stencil.new()

    for i=1,self:arraySize("expr") do
      res = res:unionWith(self["expr"..i]:stencil(input, typedASTRoot))
    end

    return res
  elseif self.kind=="unary" then
    return self.expr:stencil(input, typedASTRoot)
  elseif self.kind=="assert" then
    return self.cond:stencil(input, typedASTRoot):unionWith(self.expr:stencil(input, typedASTRoot))
  elseif self.kind=="cast" then
    return self.expr:stencil(input, typedASTRoot)
  elseif self.kind=="select" or self.kind=="vectorSelect" then
    return self.cond:stencil(input, typedASTRoot)
    :unionWith(self.a:stencil(input, typedASTRoot)
               :unionWith(self.b:stencil(input, typedASTRoot)
                          ))
  elseif self.kind=="position" or self.kind=="tap" or self.kind=="value" then
    return Stencil.new()
  elseif self.kind=="tapLUTLookup" then
    return self.index1:stencil(input, typedASTRoot)
  elseif self.kind=="load" then
    if type(self.relX.constLow_1)~="number" or type(self.relY.constLow_1)~="number" then
      -- this is a gather
      -- make sure to count the accesses that happen in the address calculation
      local s = self.relX:stencil(input, typedASTRoot):unionWith(self.relY:stencil(input, typedASTRoot))
      if input~=nil and self.from~=input then
        return s -- not the input we're interested in
      end
      return Stencil.new():add(self.minX.constLow_1,self.minY.constLow_1,0):add(self.maxX.constLow_1,self.maxY.constLow_1,0):unionWith(s)
    else
      local s = Stencil.new()
      if input==nil or input==self.from then s = Stencil.newSquare( self.relX.constLow_1, self.relX.constHigh_1, self.relY.constLow_1, self.relY.constHigh_1 ) end
      return s
    end
  elseif self.kind=="array" then
    local exprsize = self:arraySize("expr")
    local s = Stencil.new()
    for i=1,exprsize do
      s = s:unionWith(self["expr"..i]:stencil(input, typedASTRoot))
    end

    return s
  elseif self.kind=="reduce" then
    local s = Stencil.new()
    local i=1
    while self["expr"..i] do
      s = s:unionWith(self["expr"..i]:stencil(input, typedASTRoot))
      i=i+1
    end
    return s
  elseif self.kind=="index" then
    return self.expr:stencil(input, typedASTRoot)
  elseif self.kind=="crop" then
    return self.expr:stencil(input, typedASTRoot)
  elseif self.kind=="transformBaked" then
    return self.expr:stencil(input, typedASTRoot):sum(Stencil.newSquare( self.translate1.constLow_1, self.translate1.constHigh_1, self.translate2.constLow_1, self.translate2.constHigh_1))
  elseif self.kind=="mapreduce" then
    local s = Stencil.new()
    -- HW: if this has lifted values, include their stencil
    for k,v in pairs(self) do
      if k:sub(0,6)=="lifted" then s = s:unionWith(v:stencil(input, typedASTRoot)) end
    end
    return s:unionWith(self.expr:stencil(input, typedASTRoot))
  elseif self.kind=="iterate" then
    local s = Stencil.new()

    s = s:unionWith(self.expr:stencil(input, typedASTRoot))

    local i=1
    while self["loadname"..i] do
      s = s:unionWith(self["_loadexpr"..i]:stencil(input, typedASTRoot))
      i = i + 1
    end

    return s
  elseif self.kind=="mapreducevar" then
    return Stencil.new()
  elseif self.kind=="iterationvar" then
    return Stencil.new()
  elseif self.kind=="iterateload" then
    return Stencil.new()
  elseif self.kind=="gatherColumn" then
    assert(self._input.kind=="load")

    local s = self.x:stencil(input, typedASTRoot)

    if input~=nil and self._input.from~=input then
      return s -- not the input we're interested in
    else
      -- note the kind of nasty hack we're doing here: gathers read from loads, and loads can be shifted.
      -- so we need to shift this the same as the load
      return darkroom.typedAST.transformArea(self._input.relX, self._input.relY, typedASTRoot):sum( Stencil.new():add(self.columnStartX,self.columnStartY,0):add(self.columnEndX,self.columnEndY,0)):unionWith(s)
    end

  elseif self.kind=="filter" then
    return self.expr:stencil(input, typedASTRoot):unionWith(self.cond:stencil(input, typedASTRoot))
  elseif self.kind=="lifted" then
    return Stencil.new() -- stencil will come from mapreduce node
  end

  print("unknown stencil kind",self.kind, debug.traceback())
  assert(false)
end

function typedASTFunctions:irType()
  return "typedAST"
end

function darkroom.typedAST.typecheckAST( origast, inputs, newNodeFn )
  assert(darkroom.ast.isAST(origast))
  if newNodeFn==nil then newNodeFn = darkroom.typedAST.new end
  assert(type(newNodeFn)=="function") -- this is either darkroom.typedAST.new or systolicAST.new
  local ast = origast:shallowcopy()
  
  if ast.kind~="transform" and ast.kind~="outputs" then
    for k,v in pairs(inputs) do
      for i=1,2 do
        if ast["scaleN"..i]==nil or ast["scaleN"..i]==0 then ast["scaleN"..i] = v["scaleN"..i] end
        if ast["scaleD"..i]==nil or ast["scaleD"..i]==0 then ast["scaleD"..i] = v["scaleD"..i] end
        local n1,d1 = ratioFactor(ast["scaleN"..i],ast["scaleD"..i])
        local n2,d2 = ratioFactor(v["scaleN"..i],v["scaleD"..i])
        if (n1~=n2 or d1~=d2) and v["scaleN"..i]~=0 then
          print("kind",ast.kind,"i",i,"key",k,"scaleN_this",ast["scaleN"..i],"scaleN_input",v["scaleN"..i],ast["scaleD"..i],v["scaleD"..i])
          darkroom.error("Operations can only be applied to images that are the same size.",origast:linenumber(), origast:offset(), origast:filename())
        end
      end
    end
  end
  
  if ast.kind~="outputs" then
    for k,v in pairs(inputs) do
      if v.kind=="filter" then
        darkroom.error("Operations can not be performed on sparse (filtered) images",origast:linenumber(), origast:offset(), origast:filename())
      end
    end
  end
  
  if ast.kind=="value" then
    if ast.type==nil then ast.type=darkroom.type.valueToType(ast.value) end
    if ast.type==nil then
      darkroom.error("Internal error, couldn't convert "..tostring(ast.value).." to orion type", origast:linenumber(), origast:offset(), origast:filename() )
    end
    ast.scaleN1 = 0; ast.scaleN2 = 0; ast.scaleD1 = 0; ast.scaleD2 = 0; -- meet with any rate
    ast.constLow_1 = ast.value; ast.constHigh_1 = ast.value
  elseif ast.kind=="unary" then
    ast.expr = inputs["expr"]
    
    if ast.op=="-" then
      if ast.expr.type:isUint() then
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
      if ast.expr.type:baseType()==darkroom.type.float(32) then
        ast.type = ast.expr.type
      elseif ast.expr.type:baseType()==darkroom.type.float(64) then
        ast.type = ast.expr.type
      elseif ast.expr.type:baseType():isInt() or ast.expr.type:baseType():isUint() then
        -- obv can't make it any bigger
        ast.type = ast.expr.type
      else
        ast.expr.type:print()
        assert(false)
      end
    elseif ast.op=="not" then
      if ast.expr.type:baseType():isBool() or ast.expr.type:baseType():isInt() or ast.expr.type:baseType():isUint() then
        ast.type = ast.expr.type
      else
        darkroom.error("not only works on bools and integers",origast:linenumber(), origast:offset())
        assert(false)
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
    else
      print(ast.op)
      assert(false)
    end
    
  elseif ast.kind=="binop" then
    
    local lhs = inputs["lhs"]
    local rhs = inputs["rhs"]
    
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

    local thistype, lhscast, rhscast = darkroom.type.meet( lhs.type, rhs.type, ast.op, origast )
    
    if thistype==nil then
      darkroom.error("Type error, inputs to "..ast.op,origast:linenumber(), origast:offset(), origast:filename())
    end
    
    if lhs.type~=lhscast then lhs = newNodeFn({kind="cast",expr=lhs,type=lhscast}):copyMetadataFrom(origast) end
    if rhs.type~=rhscast then rhs = newNodeFn({kind="cast",expr=rhs,type=rhscast}):copyMetadataFrom(origast) end
    
    ast.type = thistype
    ast.lhs = lhs
    ast.rhs = rhs
    
  elseif ast.kind=="position" then
    -- if position is still in the tree at this point, it means it's being used in an expression somewhere
    -- choose a reasonable type...
    ast.type=darkroom.type.int(32)
    ast.scaleN1 = 0; ast.scaleN2 = 0; ast.scaleD1 = 0; ast.scaleD2 = 0; -- meet with any rate
  elseif ast.kind=="select" or ast.kind=="vectorSelect" then
    local cond = inputs["cond"]
    local a = inputs["a"]
    local b = inputs["b"]

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
      if cond.type ~= darkroom.type.bool() then
        darkroom.error("Error, condition of select must be scalar boolean. Use vectorSelect",origast:linenumber(),origast:offset(),origast:filename())
        return nil
      end

      if a.type:isArray()~=b.type:isArray() then
        darkroom.error("Error, if any results of select are arrays, all results must be arrays",origast:linenumber(),origast:offset())
        return nil
      end
      
      if a.type:isArray() and
        a.type:arrayLength()~=b.type:arrayLength() then
        darkroom.error("Error, array arguments to select must be the same length", origast:linenumber(), origast:offset(), origast:filename() )
        return nil
      end
    end

    local thistype, lhscast, rhscast =  darkroom.type.meet(a.type,b.type, ast.kind, origast)

    if a.type~=lhscast then a = newNodeFn({kind="cast",expr=a,type=lhscast}):copyMetadataFrom(origast) end
    if b.type~=rhscast then b = newNodeFn({kind="cast",expr=b,type=rhscast}):copyMetadataFrom(origast) end
    
    ast.type = thistype
    ast.cond = cond
    ast.a = a
    ast.b = b
    
  elseif ast.kind=="index" then
    local expr = inputs["expr"]
    
    if expr.type:isArray()==false and expr.type:isUint()==false and expr.type:isInt()==false then
      darkroom.error("Error, you can only index into an array type! Type is "..tostring(expr.type),origast:linenumber(),origast:offset(), origast:filename())
      os.exit()
    end
    
    ast.expr = expr
    
    if (expr.type:isUint()==false and expr.type:isInt()==false) and origast:arraySize("index")~= #expr.type:arrayLength() then
      darkroom.error("Error, indexing into array with the wrong number of dimensions. Type "..tostring(expr.type),origast:linenumber(),origast:offset(), origast:filename())
    end

    local i = 1
    while inputs["index"..i] do
      ast["index"..i] = inputs["index"..i]

      if ast["index"..i].constLow_1==nil then
        darkroom.error( "index "..i.." must be a constant expression", origast:linenumber(), origast:offset(), origast:filename() )
      end

      local lowValue = 0
      local highValue 
      if expr.type:isUint() or expr.type:isInt() then 
        highValue = expr.type.precision 
      else
        highValue = expr.type:arrayLength()[i]
      end

      if ast["index"..i].constLow_1 < lowValue or ast["index"..i].constHigh_1 >= highValue then
        darkroom.error( "index "..i.." value out of range. It is ["..ast["index"..i].constLow_1..","..ast["index"..i].constHigh_1.."] but should be within [0,"..(highValue-1).."]", origast:linenumber(), origast:offset(), origast:filename() )
      end
      
      i = i + 1
    end
    
    if expr.type:isUint() or expr.type:isInt() then
      ast.type = darkroom.type.bool()
    else
      ast.type = expr.type:arrayOver()
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

  elseif ast.kind=="struct" then
    local ty = {}

    local cnt = 1
    while ast["key"..cnt] do
      ast["expr"..ast["key"..cnt]] = inputs["value"..cnt]
      ty[ast["key"..cnt]] = inputs["value"..cnt].type
      cnt = cnt + 1
    end
    assert(cnt>1)

    ast.type = darkroom.type.structure(ty)
  elseif ast.kind=="array" then
    
    local cnt = 1
    while ast["expr"..cnt] do
      ast["expr"..cnt] = inputs["expr"..cnt]
      ast["constLow_"..cnt] = inputs["expr"..cnt].constLow_1
      ast["constHigh_"..cnt] = inputs["expr"..cnt].constHigh_1
      cnt = cnt + 1
    end
    
    local mtype = ast.expr1.type
    local atype, btype
    
    if mtype:isArray() then
      darkroom.error("You can't have nested arrays (index 0 of vector)", origast:linenumber(), origast:offset(), origast:filename() )
    end
    
    local cnt = 2
    while ast["expr"..cnt] do
      if ast["expr"..cnt].type:isArray() then
        darkroom.error("You can't have nested arrays (index "..(i-1).." of vector)")
      end
      
      mtype, atype, btype = darkroom.type.meet( mtype, ast["expr"..cnt].type, "array", origast )
      
      if mtype==nil then
        darkroom.error("meet error")      
      end
      
      -- our type system should have guaranteed this...
      assert(mtype==atype)
      assert(mtype==btype)
      
      cnt = cnt + 1
    end
    
    -- now we've figured out what the type of the array should be
    
    -- may need to insert some casts
    local cnt = 1
    while ast["expr"..cnt] do
      -- meet should have failed if this isn't possible...
      local from = ast["expr"..cnt].type

      if from~=mtype then
        if darkroom.type.checkImplicitCast(from, mtype,origast)==false then
          darkroom.error("Error, can't implicitly cast "..from:str().." to "..mtype:str(), origast:linenumber(), origast:offset())
        end
        
        ast["expr"..cnt] = newNodeFn({kind="cast",expr=ast["expr"..cnt], type=mtype}):copyMetadataFrom(ast["expr"..cnt])
      end

      cnt = cnt + 1
    end
    
    local arraySize = cnt - 1
    ast.type = darkroom.type.array(mtype, arraySize)
    

  elseif ast.kind=="cast" then

    -- note: we don't eliminate these cast nodes, because there's a difference
    -- between calculating a value at a certain precision and then downsampling,
    -- and just calculating the value at the lower precision.
    ast.expr = inputs["expr"]

    local c = 1
    while inputs.expr["constLow_"..c] do
      ast["constLow_"..c] = inputs.expr["constLow_"..c];
      ast["constHigh_"..c] = inputs.expr["constHigh_"..c];
      c = c + 1
    end

    if darkroom.type.checkExplicitCast(ast.expr.type,ast.type,origast)==false then
      darkroom.error("Casting from "..ast.expr.type:str().." to "..ast.type:str().." isn't allowed!",origast:linenumber(),origast:offset())
    end
  elseif ast.kind=="assert" then

    ast.cond = inputs["cond"]
    ast.expr = inputs["expr"]
    ast.printval = inputs["printval"]

    if darkroom.type.astIsBool(ast.cond)==false then
      darkroom.error("Error, condition of assert must be boolean",origast:linenumber(),origast:offset(), origast:filename())
      return nil
    end

    ast.type = ast.expr.type

  elseif ast.kind=="mapreducevar" then
    ast.type = darkroom.type.int(32)
    ast.scaleN1 = 0; ast.scaleN2 = 0; ast.scaleD1 = 0; ast.scaleD2 = 0; -- meet with any rate

    if type(inputs.low.constLow_1)~="number" or inputs.low.constLow_1~=inputs.low.constHigh_1 then
      darkroom.error("Map reduce var range low must be a constant",origast:linenumber(),origast:offset(), origast:filename())
    end

    if type(inputs.high.constLow_1)~="number" or inputs.high.constLow_1~=inputs.high.constHigh_1 then
      darkroom.error("Map reduce var range low must be a constant",origast:linenumber(),origast:offset(), origast:filename())
    end

    ast.low = inputs.low
    ast.high = inputs.high
    ast.constLow_1 = inputs.low.constLow_1
    ast.constHigh_1 = inputs.high.constLow_1
  elseif ast.kind=="iterateload" then
    ast.type = inputs._expr.type
    ast._expr = nil
  elseif ast.kind=="tap" then
    -- taps should be tagged with type already
    ast.scaleN1 = 0; ast.scaleN2 = 0; ast.scaleD1 = 0; ast.scaleD2 = 0; -- meet with any rate
  elseif ast.kind=="tapLUTLookup" then
    ast.index1 = inputs["index1"]
    
    -- tapLUTs should be tagged with type already
    assert(darkroom.type.isType(ast.type))
    
    if ast.index1.type:isUint()==false and ast.index1.type:isInt()==false then
      darkroom.error("Error, index into tapLUT must be integer", origast:linenumber(), origast:offset(), origast:filename())
      return nil
    end
  elseif ast.kind=="crop" then
    ast.expr = inputs["expr"]
    ast.type = ast.expr.type
  elseif ast.kind=="reduce" then
    local i=1
    local typeSet = {}

    while ast["expr"..i] do
      ast["expr"..i] = inputs["expr"..i]
      table.insert(typeSet,ast["expr"..i].type)
      
      i=i+1
    end

    ast.type = darkroom.type.reduce( ast.op, typeSet)
  elseif ast.kind=="outputs" then
    -- doesn't matter, this is always the root and we never need to get its type
    ast.type = inputs.expr1.type
    ast.scaleN1 = 0
    ast.scaleD1 = 0
    ast.scaleN2 = 0
    ast.scaleD2 = 0
    
    local i=1
    while ast["expr"..i] do
      ast["expr"..i] = inputs["expr"..i]
      i=i+1
    end

  elseif ast.kind=="type" then
    -- ast.type is already a type, so don't have to do anything
    -- shouldn't matter, but need to return something
  elseif ast.kind=="gather" then
    ast.type = inputs._input.type
    ast._input = inputs._input
    ast.x = inputs.x
    ast.y = inputs.y

    for _,v in pairs({"minX","maxX","minY","maxY"}) do
      local res = inputs[v]
      if type(res.constLow_1)~="number" or res.constLow_1~=res.constHigh_1 then
        darkroom.error("Argument "..v.." to gather must be a constant", origast:linenumber(), origast:offset(), origast:filename())
      end
      ast[v] = res
    end

    if ast.x.type:isInt()==false then
      darkroom.error("Error, x argument to gather must be int but is "..ast.x.type:str(), origast:linenumber(), origast:offset())
    end

    if ast.y.type:isInt()==false then
      darkroom.error("Error, y argument to gather must be int but is "..ast.y.type:str(), origast:linenumber(), origast:offset())
    end
  elseif ast.kind=="gatherColumn" then
    ast.type = inputs._input.type
    ast._input = inputs._input
    ast.x = inputs.x

    for _,v in pairs({"rowWidth","columnStartX","columnEndX","columnStartY","columnEndY"}) do
      if ast[v]==nil then 
        darkroom.error("Argument "..v.." to gatherColumn missing",origast:linenumber(),origast:offset(),origast:filename())
      end

      local res = ast[v]:eval(1,newNodeFn({}):copyMetadataFrom(origast))
      if res:area()~=1 then
        darkroom.error("Argument "..v.." to gatherColumn must be a constant",origast:linenumber(),origast:offset(),origast:filename())
      end
      ast[v] = res:min(1)
    end

    if ast.columnStartY>ast.columnEndY then
      darkroom.error("gatherColumn startY should not be larger than endY",origast:linenumber(),origast:offset(),origast:filename())
    end

    if ast.type:isArray() then
      assert(false)
    else
      ast.type = darkroom.type.array(ast.type,ast.rowWidth*(ast.columnEndY-ast.columnStartY+1))
    end

  elseif ast.kind=="load" then
    -- already has a type
    ast.scaleN1=1; ast.scaleD1=1; ast.scaleN2=1; ast.scaleD2=1;
    assert(inputs.relX~=nil)
    assert(inputs.relY~=nil)
    ast.relX = inputs.relX
    ast.relY = inputs.relY
  elseif ast.kind=="mapreduce" then

    origast:map("varnode", function(n,i) ast["varnode"..i] = inputs["varnode"..i] end)

    if ast.reduceop=="sum" or ast.reduceop=="max" or ast.reduceop=="min" then
      ast.type = inputs.expr.type
    elseif ast.reduceop=="argmin" or ast.reduceop=="argmax" then
      if inputs.expr.type:isArray()==true then
        darkroom.error("argmin and argmax can only be applied to scalar quantities", origast:linenumber(), origast:offset(), origast:filename())
      end

      ast.type = darkroom.type.array(darkroom.type.int(32),origast:arraySize("varname")+1)
    elseif ast.reduceop=="none" then
      if origast:arraySize("varname")~=1 then
        darkroom.error("Pure map can only be one dimensional", origast:linenumber(), origast:offset(), origast:filename())
      end

      if ast.varnode1.low.constLow_1~=0 or ast.varnode1.low.constLow_1~=ast.varnode1.low.constHigh_1 or ast.varnode1.high.constLow_1~=ast.varnode1.high.constHigh_1 then
        darkroom.error("Pure map can only have range 0 to N", origast:linenumber(), origast:offset(), origast:filename())
      end

      if inputs.expr.type:isArray()==true then
        darkroom.error("pure map can only be applied to scalar quantities", origast:linenumber(), origast:offset(), origast:filename())
      end

      ast.type = darkroom.type.array(inputs.expr.type,ast.varnode1.high.constLow_1+1)
    else
      darkroom.error("Unknown reduce operator '"..ast.reduceop.."'")
    end

    ast.expr = inputs.expr
  elseif ast.kind=="iterate" then
    ast.iterationSpaceLow = ast.iterationSpaceLow:eval(1,newNodeFn({}):copyMetadataFrom(origast))
    if ast.iterationSpaceLow:area()~=1 then
      darkroom.error("iteration range must be a constant",ast:linenumber(),ast:offset(),ast:filename())
    end
    ast.iterationSpaceLow = ast.iterationSpaceLow:min(1)

    ast.iterationSpaceHigh = ast.iterationSpaceHigh:eval(1,newNodeFn({}):copyMetadataFrom(origast))
    if ast.iterationSpaceHigh:area()~=1 then
      darkroom.error("iteration range must be a constant",ast:linenumber(),ast:offset(),ast:filename())
    end
    ast.iterationSpaceHigh = ast.iterationSpaceHigh:min(1)

    if ast.reduceop=="sum" or ast.reduceop=="max" or ast.reduceop=="min" then
      ast.type = inputs.expr.type
    elseif ast.reduceop=="none" then
      if ast.iterationSpaceLow~=0 or ast.iterationSpaceHigh<=0 then
        darkroom.error("Pure iterate can only have range 0 to N", origast:linenumber(), origast:offset(), origast:filename())
      end

      ast.type = darkroom.type.array(inputs.expr.type,ast.iterationSpaceHigh-ast.iterationSpaceLow+1)
    else
      darkroom.error("Unknown reduce operator '"..ast.reduceop.."'")
    end

    ast._iterationvar = inputs._iterationvar
    ast.expr = inputs.expr

    local i = 1
    while ast["loadname"..i] do
      ast["_loadexpr"..i] = inputs["_loadexpr"..i]
      i = i + 1
    end

  elseif ast.kind=="filter" then
    ast.cond = inputs.cond
    ast.expr = inputs.expr
    ast.type = ast.expr.type

    if ast.cond.type:isBool()==false then
      darkroom.error("condition of filter must be a scalar boolean", origast:linenumber(), origast:offset(), origast:filename())
    end
  elseif ast.kind=="iterationvar" then
    ast.type = darkroom.type.int(32)
    ast.scaleN1 = 0; ast.scaleN2 = 0; ast.scaleD1 = 0; ast.scaleD2 = 0; -- meet with any rate
  else
    darkroom.error("Internal error, typechecking for "..ast.kind.." isn't implemented!",ast.line,ast.char)
    return nil
  end

  if darkroom.type.isType(ast.type)==false then print(ast.kind) end
  ast = newNodeFn(ast):copyMetadataFrom(origast)
  assert(darkroom.type.isType(ast.type))
  if type(ast.constLow_1)=="number" then assert(ast.constLow_1<=ast.constHigh_1) end

  for i=1,2 do 
    if type(ast["scaleN"..i])~="number" or type(ast["scaleD"..i])~="number" then print("missingrate",ast.kind); assert(false) end 
  end

  return ast
end

function darkroom.typedAST._toTypedAST(inast)

  local largestScaleN = {1,1}
  local largestScaleD = {1,1}
  local smallestScaleN = {1,1}
  local smallestScaleD = {1,1}

  local res = inast:visitEach(
    function(origast,inputs)
      local res = darkroom.typedAST.typecheckAST(origast, inputs)

      -- rules for finding the largest scale:
      -- (1/1), (2/1), (4/1) => 4 (even if they have common factors, largest number is chosen)
      -- (1/1), (2/1), (4/2) => 2 (need to factor the scale)
      -- (1/1), (1/3), (1/7) => 1 (denom is irrelevant)
      -- (1/1), (7/1), (3/1) => 21 (numerators must have common factors)
      -- (1/1), (1/3), (7/3) => 7 (denom is irrelevant)

      for i=1,2 do 
        if res["scaleN"..i]~=0 and res["scaleD"..i]~=0 then
          local N = res["scaleN"..i]/gcd(res["scaleN"..i],res["scaleD"..i]) -- eg (4/2) => (2/1)
          assert(math.floor(N)==N)
          local lcdN = (N*largestScaleN[i])/gcd(N,largestScaleN[i])
          if lcdN>largestScaleN[i] then largestScaleN[i] = lcdN 
          elseif N>largestScaleN[i] then largestScaleN[i] = N end
        end
        
        if res["scaleN"..i]/res["scaleD"..i] < smallestScaleN[i]/smallestScaleD[i] then
          smallestScaleN[i] = res["scaleN"..i]
          smallestScaleD[i] = res["scaleD"..i]
        end
      end

      return res
    end)

  assert(smallestScaleN[1]==1)
  assert(smallestScaleN[2]==1)
  return res, largestScaleN[1], largestScaleN[2], smallestScaleD[1], smallestScaleD[2]
end

function darkroom.typedAST.astToTypedAST(ast, options)
  assert(darkroom.ast.isAST(ast))
  assert(type(options)=="table")

  -- first we run CSE to clean up the users code
  -- this will save us a lot of time/memory later on
  ast = darkroom.optimize.CSE(ast,{})

  if options.verbose or options.printstage then 
    print("toTyped") 
    print("nodecount",ast:S("*"):count())
    print("maxDepth",ast:maxDepth())
  end

  if darkroom.verbose or darkroom.printstage then 
    print("desugar")
  end

  -- desugar mapreduce expressions etc
  -- we can't do this in _toTypedAST, b/c mapreducevar's aren't
  -- allowed anywhere (so these expressions are technically invalid)
  -- so we do this first as a preprocessing step.
  --
  -- we also don't want to do these desugaring in compileTimeProcess,
  -- b/c that will potentially grow memory usage exponentially
  ast = ast:S(function(n) 
                return n.kind=="let" or 
                  n.kind=="switch" end):process(
    function(node)
      if node.kind=="let" then
        local cnt = 1
        local namemap = {}

        local function removeLet( expr, namemap )
          return expr:S("letvar"):process(
            function(n)
              if namemap[n.variable]~=nil then
                return namemap[n.variable]
              end
              return n
            end)
        end

        while node["expr"..cnt] do
          namemap[node["exprname"..cnt]] = removeLet(node["expr"..cnt],namemap)
          cnt = cnt + 1
        end

        return removeLet(node.res, namemap)
      elseif node.kind=="switch" then
        local cnt = node:arraySize("expr")
        
        local cond = darkroom.ast.new({kind="binop",op="==",lhs=node.controlExpr,rhs=node["val"..cnt]}):copyMetadataFrom(node)
        local select = darkroom.ast.new({kind="select",cond=cond,a=node["expr"..cnt],b=node.default}):copyMetadataFrom(node)
        
        cnt = cnt-1
        while cnt > 0 do
          cond = darkroom.ast.new({kind="binop",op="==",lhs=node.controlExpr,rhs=node["val"..cnt]}):copyMetadataFrom(node)
          select = darkroom.ast.new({kind="select",cond=cond,a=node["expr"..cnt],b=select}):copyMetadataFrom(node)
          cnt = cnt - 1
        end
        
        return select

      end
    end)

  if options.verbose then
    print("desugar done")
  end

  -- should have been eliminated
  if darkroom.debug then assert(ast:S(function(n) return n.kind=="letvar" or n.kind=="switch" end):count()==0) end

  if options.printstage then
    print("_toTypedAST",collectgarbage("count"))
  end

  local typedAST, largestScaleX, largestScaleY, smallestScaleX, smallestScaleY = darkroom.typedAST._toTypedAST(ast)

  if options.verbose or options.printstage then
    print("largestScaleX",largestScaleX,"largestScaleY",largestScaleY)
    print("conversion to typed AST done ------------")
  end

  return typedAST, largestScaleX, largestScaleY, smallestScaleX, smallestScaleY
end


function darkroom.typedAST.isTypedAST(ast) return getmetatable(ast)==typedASTMT end

-- kind of a hack - so that the IR library can shallowcopy and then
-- modify an ast node without having to know its exact type
function typedASTFunctions:init()
  setmetatable(self,nil)
  darkroom.typedAST.new(self)
end

function darkroom.typedAST.new(tab)
  assert(type(tab)=="table")
  darkroom.IR.new(tab)
  return setmetatable(tab,typedASTMT)
end

