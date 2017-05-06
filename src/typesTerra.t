-- if pointer is true, generate a pointer instead of a value
-- vectorN = width of the vector [optional]
function TypeFunctions:toTerraType(pointer, vectorN)
  local ttype

  if self.kind=="named" then
    return self.structure:toTerraType(pointer,vectorN)
  end
  
  if self:isFloat() and self.precision==32 then
    ttype = float
  elseif self:isFloat() and self.precision==64 then
    ttype = double
  elseif (self:isUint() or self:isBits()) and self.precision<=8 then
    ttype = uint8
  elseif self:isInt() and self.precision<=8 then
    ttype = int8
  elseif self:isBool() then
    ttype = bool
  elseif self:isInt() and self.precision>16 and self.precision<=32 then
    ttype = int32
  elseif self:isInt() and self.precision>32 and self.precision<=64 then
    ttype = int64
  elseif (self:isUint() or self:isBits()) and self.precision>32 and self.precision<=64 then
    ttype = uint64
  elseif (self:isUint() or self:isBits()) and self.precision>16 and self.precision<=32 then
    ttype = uint32
  elseif (self:isUint() or self:isBits()) and self.precision>8 and self.precision<=16 then
    ttype = uint16
  elseif self:isInt() and self.precision>8 and self.precision<=16 then
    ttype = int16
  elseif self:isArray() then
    assert(vectorN==nil)
    ttype = (self.over:toTerraType())[self:channels()]
  elseif self.kind=="tuple" then
    ttype = tuple( unpack(map(self.list, function(n) return n:toTerraType(pointer, vectorN) end)) )
  elseif self.kind=="opaque" then
    ttype = &opaque
  elseif self.kind=="null" then
    ttype = &opaque
  else
    print(":toTerraType",self)
    print(debug.traceback())
    assert(false)
  end

  if vectorN then
    if pointer then return &vector(ttype,vectorN) end
    return vector(ttype,vectorN)
  else
    if pointer then return &ttype end
    return ttype
  end

  print(types.typeToString(_type))
  assert(false)

  return nil
end

function TypeFunctions:valueToTerra(value)
  if self:isUint() or self:isFloat() or self:isInt() then
    assert(type(value)=="number")
    return `[self:toTerraType()](value)
  elseif self:isBool() then
    assert(type(value)=="boolean")
    return `[self:toTerraType()](value)
  elseif self:isArray() then
    assert(type(value)=="table")
    assert(#value==self:channels())
    local tup = map( value, function(v) return self:arrayOver():valueToTerra(v) end )
    return `[self:toTerraType()](array(tup))
  elseif self:isTuple() then
    assert(type(value)=="table")
    assert(#value==#self.list)
    local tup = map( value, function(v,k) return self.list[k]:valueToTerra(v) end )
    return `[self:toTerraType()]({tup})
  elseif self:isNamed() then
    return self.structure:valueToTerra(value)
  else
    print("TypeFunctions:valueToTerra",self)
    assert(false)
  end
end

function TypeFunctions:sizeof()
  return terralib.sizeof(self:toTerraType())
end

