local J = require "common"
local cstdio = terralib.includec("stdio.h", {"-Wno-nullability-completeness"})
      
-- if pointer is true, generate a pointer instead of a value
-- vectorN = width of the vector [optional]
function TypeFunctions:toTerraType(pointer, vectorN)
  local ttype

  if self.kind=="named" then
    return self.structure:toTerraType(pointer,vectorN)
  end
  
  if self:isFloat() and self.precision==32 then
    ttype = terralib.types.float
  elseif self:isFloat() and self.precision==64 then
    ttype = terralib.types.double
  elseif (self:isUint() or self:isBits()) and self.precision<=8 then
    ttype = terralib.types.uint8
  elseif self:isInt() and self.precision<=8 then
    ttype = terralib.types.int8
  elseif self:isBool() then
    ttype = terralib.types.bool
  elseif self:isInt() and self.precision>16 and self.precision<=32 then
    ttype = terralib.types.int32
  elseif self:isInt() and self.precision>32 and self.precision<=64 then
    ttype = terralib.types.int64
  elseif (self:isUint() or self:isBits()) and self.precision>32 and self.precision<=64 then
    ttype = terralib.types.uint64
  elseif (self:isUint() or self:isBits()) and self.precision>16 and self.precision<=32 then
    ttype = terralib.types.uint32
  elseif (self:isUint() or self:isBits()) and self.precision>8 and self.precision<=16 then
    ttype = terralib.types.uint16
  elseif (self:isUint() or self:isBits()) and self.precision>64 then
    local cnt = self.precision/8
    assert(cnt==math.floor(cnt))
    ttype = terralib.types.uint8[cnt]
  elseif self:isInt() and self.precision>8 and self.precision<=16 then
    ttype = terralib.types.int16
  elseif self:isArray() then
    assert(vectorN==nil)
    local chan = self:channels()
    local Uniform = require "uniform"
    if Uniform.isUniform(chan) then chan = chan:toNumber() end
    ttype = (self.over:toTerraType())[chan]
  elseif self.kind=="tuple" then
    ttype = terralib.types.tuple( unpack(J.map(self.list, function(n) return n:toTerraType(pointer, vectorN) end)) )
  elseif self.kind=="opaque" then
    ttype = &terralib.types.opaque
  elseif self.kind=="null" or self.kind=="Trigger" then
    ttype = &terralib.types.opaque
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
  if self:isUint() or self:isFloat() or self:isInt() or self:isBits() then
    if self.precision>64 then
      local cnt = self.precision/8
      assert(cnt==math.floor(cnt))
      assert(value==0) -- NYI
      local tup = {}
      for i=1,cnt do table.insert(tup,`[uint8](0)) end
      return `[uint8[cnt]](array(tup))
    else
      assert(type(value)=="number")
      return `[self:toTerraType()](value)
    end
  elseif self:isBool() then
    J.err(type(value)=="boolean","value '"..tostring(value).."' should be boolean")
    return `[self:toTerraType()](value)
  elseif self:isArray() then
    assert(type(value)=="table")
    assert(#value==self:channels())
    local tup = J.map( value, function(v) return self:arrayOver():valueToTerra(v) end )
    return `[self:toTerraType()](array(tup))
  elseif self:isTuple() then
    assert(type(value)=="table")
    assert(#value==#self.list)
    local tup = J.map( value, function(v,k) return self.list[k]:valueToTerra(v) end )
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

-- return code quote to print terra value of this type
-- terraValue should be pointer
function TypeFunctions:terraPrint(terraValue)
  if self:isArray() then
    local Q = {quote cstdio.printf("[") end}
    for i=1,self:channels() do
      table.insert(Q,self:arrayOver():terraPrint(`&(@terraValue)[i-1]))
      table.insert(Q,quote cstdio.printf(",") end)
    end
    table.insert(Q,quote cstdio.printf("]") end)
    return quote Q end
  elseif self:isTuple() then
    local Q = {quote cstdio.printf("{") end}
    for k,ty in ipairs(self.list) do
      table.insert(Q,ty:terraPrint(`&(@terraValue).["_"..(k-1)]))
      table.insert(Q,quote cstdio.printf(",") end)
    end
    table.insert(Q,quote cstdio.printf("}") end)
    return quote Q end
  elseif self:isInt() then
    return quote cstdio.printf("%d",@terraValue) end
  elseif self:isBool() then
    return quote if @terraValue then cstdio.printf("true") else cstdio.printf("false") end end
  elseif self:isUint() or self:isBits() then
    if self:verilogBits()==64 then
      return quote cstdio.printf("%lu/0x%xu",@terraValue,@terraValue) end
    else
      return quote cstdio.printf("%u",@terraValue) end
    end
  else
    print("NYI - terra Print "..tostring(self))
    assert(false)
  end
end
