-- this is the base class for all our compiler IR

darkroom.IR = {}

IRFunctions = {}

function IRFunctions:visitEach(func)
  local seen = {}
  local value = {}

  local function trav(node)
    if seen[node]~=nil then return value[node] end

    local argList = {}
    for k,v in node:inputs() do
      argList[k]=trav(v)
    end

    value[node] = func( node, argList )
    seen[node] = 1
    return value[node]
  end

  return trav(self)
end

-- this basically only copies the actual entires of the table,
-- but doesn't copy children/parents, so 
-- you still have to call darkroom.ast.new on it
function IRFunctions:shallowcopy()
  local newir = {}

  for k,v in pairs(self) do
    newir[k]=v
  end

  return newir
end

-- like pairs(), but only return the k,v pairs where the v is another IR node
-- by defn, this function only returns v's that have the same metatable as self
-- note that this can return the same value under different keys!
function IRFunctions:inputs()
  local f, s, varr = pairs(self)

  local function filteredF(s,varr)
    while 1 do
      local k,v = f(s,varr)
      varr = k
      if k==nil then return nil,nil end
      if darkroom.IR.isIR(v) and getmetatable(self)==getmetatable(v) then return k,v end
    end
  end

  return filteredF,s,varr
end

darkroom.IR._parentsCache=setmetatable({}, {__mode="k"})
function darkroom.IR.buildParentCache(root)
  assert(darkroom.IR._parentsCache[root]==nil)
  darkroom.IR._parentsCache[root]=setmetatable({}, {__mode="k"})
  darkroom.IR._parentsCache[root][root]=setmetatable({}, {__mode="k"})

  local visited={}
  local function build(node)
    if visited[node]==nil then
      for k,child in node:inputs() do
        if darkroom.IR._parentsCache[root][child]==nil then
          darkroom.IR._parentsCache[root][child]={}
        end

        -- notice that this is a multimap: node can occur
        -- multiple times with different keys
        table.insert(darkroom.IR._parentsCache[root][child],setmetatable({node,k},{__mode="v"}))
        build(child)
      end
      visited[node]=1
    end
  end
  build(root)
end

-- this node's set of parents is always relative to some root
-- returns k,v in this order:  parentNode, key in parentNode to access self
-- NOTE: there may be multiple keys per parentNode! A node can hold
-- the same AST multiple times with different keys.
function IRFunctions:parents(root)
  assert(darkroom.IR.isIR(root))

  if darkroom.IR._parentsCache[root]==nil then
    -- need to build cache
    darkroom.IR.buildParentCache(root)
  end

  -- maybe this node isn't reachable from the root?
  assert(type(darkroom.IR._parentsCache[root][self])=="table")

  -- fixme: I probably didn't implement this correctly

  local list = darkroom.IR._parentsCache[root][self]

  local function filteredF(s)
    assert(type(s)=="table")
    assert(type(s.i)=="number")

    if s.i>#list then return nil,nil end
    s.i = s.i+1
    return list[s.i-1][1],list[s.i-1][2]
  end

  return filteredF,{i=1},1

end

function IRFunctions:inputCount()
  local cc=0
  for k,v in self:inputs() do cc=cc+1 end
  return cc
end

function IRFunctions:parentCount(root)
  local pc=0
  for k,v in self:parents(root) do pc=pc+1 end
  return pc
end

darkroom.IR._original=setmetatable({}, {__mode="k"})

function darkroom.IR.new(node)
  assert(getmetatable(node)==nil)

  darkroom.IR._original[node]=setmetatable({}, {__mode="kv"})
  for k,v in pairs(node) do
    darkroom.IR._original[node][k]=v
  end

end

function darkroom.IR.isIR(v)
  local mt = getmetatable(v)
  if type(mt)~="table" then return false end
  if type(mt.__index)~="table" then return false end
  local mmt = getmetatable(mt.__index)
  if type(mmt)~="table" then return false end

  local t = mmt.__index

  return t==IRFunctions
end