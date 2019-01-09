local J = require("common")
local IR = require("ir")
local err = J.err

local types = {}

TypeFunctions = {}
TypeMT = {__index=TypeFunctions, __tostring=function(ty)
  if ty.kind=="bool" then
    return "bool"
  elseif ty.kind=="null" then
    return "null"
  elseif ty.kind=="int" then
    return "int"..ty.precision
  elseif ty.kind=="uint" then
    return "uint"..ty.precision
  elseif ty.kind=="bits" then
    return "bits"..ty.precision
  elseif ty.kind=="float" then
    return "float"..ty.precision
  elseif ty.kind=="array" then
    return tostring(ty.over).."["..table.concat(ty.size,",").."]"
  elseif ty.kind=="tuple" then
    return "{"..table.concat(J.map(ty.list, function(n) return tostring(n) end), ",").."}"
  elseif ty.kind=="named" then
    return ty.name
  end

  print("Error, typeToString input doesn't appear to be a type, ",ty.kind)
  assert(false)
end}

types._bool=setmetatable({kind="bool"}, TypeMT)
function types.bool() return types._bool end

types._null=setmetatable({kind="null"}, TypeMT)
function types.null() return types._null end

types._named={}
function types.named( name, structure, generator, params, X )
  err( type(name)=="string","types.named: name must be string")
  err( types.isType(structure),"types.named: structure must be rigel type")
  err( type(generator)=="string","types.named: generator must be string")
  err( type(params)=="table","types.named: params must be table")
  
  if types._named[name]==nil then
    local ty = {kind="named",name=name, structure=structure, generator=generator,params=params}
    types._named[name] = setmetatable(ty,TypeMT)
  else
    err( types._named[name].structure==structure,"types.named: attempted to make new type with same name ("..name.."), but different structure ("..tostring(structure).." vs old: "..tostring(types._named[name].structure)..")" )
  end
  
  return types._named[name]
end

types._bits={}
function types.bits( prec, X )
  err( X==nil, "types.bits: too many arguments" )
--  assert(prec<512)
  assert(prec==math.floor(prec))
  err(prec>0,"types.bits precision needs to be >0")
  types._bits[prec] = types._bits[prec] or setmetatable({kind="bits",precision=prec},TypeMT)
  return types._bits[prec]
end

types._uint={}
function types.uint( prec, X )
  err(type(prec)=="number", "precision argument to types.uint must be number")
  err(prec==math.floor(prec), "uint precision should be integer, but is "..tostring(prec) )
  err(prec>0,"types.uint precision needs to be >0")
  err( X==nil, "types.uint: too many arguments" )
  types._uint[prec] = types._uint[prec] or setmetatable({kind="uint",precision=prec},TypeMT)
  return types._uint[prec]
end

types._int={}
function types.int( prec, X )
  assert(prec==math.floor(prec))
  err( X==nil, "types.int: too many arguments" )
  err(prec>0,"types.int precision needs to be >0")
  types._int[prec] = types._int[prec] or setmetatable({kind="int",precision=prec},TypeMT)
  return types._int[prec]
end

types._float={}
function types.float( prec, X )
  assert(prec==math.floor(prec))
  err( X==nil, "types.float: too many arguments" )
  types._float[prec] = types._float[prec] or setmetatable({kind="float",precision=prec},TypeMT)
  return types._float[prec]
end

types._array={}

function types.array2d( _type, w, h )
  err( types.isType(_type), "first index to array2d must be Rigel type" )
  err( types.isBasic(_type), "array2d: input type must be basic, but is: "..tostring(_type) )
  err( type(w)=="number", "types.array2d: second argument must be numeric width but is "..tostring(type(w)) )
  err( type(h)=="number" or h==nil, "array2d h must be nil or number, but is:"..type(h))
  if h==nil then h=1 end -- by convention, 1d arrays are 2d arrays with height=1
  err(w==math.floor(w), "non integer array width "..tostring(w))
  assert(h==math.floor(h))
  err( _type:verilogBits()>0, "types.array2d: array type must have >0 bits" )
  err( w*h>0,"types.array2d: w*h must be >0" )
  
  -- dedup the arrays
  local ty = setmetatable( {kind="array", over=_type, size={w,h}}, TypeMT )
  return J.deepsetweak(types._array, {_type,w,h}, ty)
end

types._tuples = {}

function types.tuple( list )
  err(type(list)=="table","input to types.tuple must be table")
  err(J.keycount(list)==#list,"types.tuple: input table is not an array")
  err(#list>0, "no empty tuple types!")

  for k,v in ipairs(list) do
    err( types.isType(v), "types.tuple: all items in list must be types, but item "..tostring(k).." is :"..tostring(v))
    err( types.isBasic(v), "types.tuple: input type must be basic, but is: "..tostring(v) )
    err(v:verilogBits()>0,"types.tuple: all types in list must have >0 bits")
  end
  
  -- we want to allow a tuple with one item to be a real type, for the same reason we want there to be an array of size 1.
  -- This means we can parameterize a design from tuples with 1->N items and it will work the same way.
  --if #list==1 and types.isType(list[1]) then return list[1] end

  types._tuples[#list] = types._tuples[#list] or {}
  local tup = setmetatable( {kind="tuple", list = list }, TypeMT )
  assert(types.isType(tup))
  local res = J.deepsetweak( types._tuples[#list], list, tup )
  assert(types.isType(res))
  assert(#res.list==#list)
  return res
end

local boolops = {["or"]=1,["and"]=1,["=="]=1,["xor"]=1,["select"]=1} -- bool -> bool -> bool
local cmpops = {["=="]=1,["~="]=1,["<"]=1,[">"]=1,["<="]=1,[">="]=1} -- number -> number -> bool
local binops = {["|"]=1,["^"]=1,["&"]=1,["+"]=1,["-"]=1,["%"]=1,["*"]=1,["/"]=1}
-- these binops only work on ints
local intbinops = {["<<"]=1,[">>"]=1,["and"]=1,["or"]=1,["^"]=1}
-- ! does a logical not in C, use 'not' instead
-- ~ does a bitwise not in C
local unops = {["not"]=1,["-"]=1}
J.appendSet(binops,boolops)
J.appendSet(binops,cmpops)

-- returns resultType, lhsType, rhsType
-- ast is used for error reporting
function types.meet( a, b, op, loc)
  assert(types.isType(a))
  assert(types.isType(b))
  assert(type(op)=="string")
  assert(type(loc)=="string") -- code location of op, in case there is an error
  
  assert(getmetatable(a)==TypeMT)
  assert(getmetatable(b)==TypeMT)

  local treatedAsBinops = {["select"]=1, ["vectorSelect"]=1,["array"]=1, ["mapreducevar"]=1, ["dot"]=1, ["min"]=1, ["max"]=1}

  if a:isTuple() and b:isTuple() then
    err(a==b,"NYI - type meet tuple "..tostring(a).." and "..tostring(b).." op:"..op)
    return a,a,a
  elseif a:isArray() and b:isArray() then
    if a:arrayLength() ~= b:arrayLength() then
      print("Type error, array length mismatch")
      return nil
    end
    
    if op=="dot" then
      local rettype,at,bt = types.meet(a.over,b.over,op,loc)
      local convtypea = types.array( at, a:arrayLength() )
      local convtypeb = types.array( bt, a:arrayLength() )
      return rettype, convtypea, convtypeb
    elseif cmpops[op] then
      -- cmp ops are elementwise
      local rettype,at,bt = types.meet(a.over,b.over,op,loc)
      local convtypea = types.array( at, a:arrayLength() )
      local convtypeb = types.array( bt, a:arrayLength() )
      
      local thistype = types.array( types.bool(), a:arrayLength() )
      return thistype, convtypea, convtypeb
    elseif binops[op] or treatedAsBinops[op] then
      -- do it pointwise
      local thistype = types.array2d( types.meet( a.over, b.over, op, loc ), (a:arrayLength())[1], (a:arrayLength())[2] )
      return thistype, thistype, thistype
    elseif op=="<<" or op==">>" then
       -- don't cast shifts - the rhs leads to 2^n shift options!
       return a, a, b
    elseif op=="pow" then
      local thistype = types.array(types.float(32), a:arrayLength() )
      return thistype, thistype, thistype
    else
      print("OP",op)
      assert(false)
    end
      
  elseif a.kind=="int" and b.kind=="int" then
    local prec = math.max(a.precision,b.precision)
    local thistype = types.int(prec)
    
    if cmpops[op] then
      return types.bool(), thistype, thistype
    elseif binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="<<" or op==">>" then
       -- don't cast shifts - the rhs leads to 2^n shift options!
       return a, a, b
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP",op)
      assert(false)
    end
  elseif a.kind=="uint" and b.kind=="uint" then
    local prec = math.max(a.precision,b.precision)
    local thistype = types.uint(prec)
    
    if cmpops[op] then
      return types.bool(), thistype, thistype
    elseif binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="<<" or op==">>" then
       -- don't cast shifts - the rhs leads to 2^n shift options!
       return a, a, b
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP2",op)
      assert(false)
    end
  elseif (a.kind=="uint" and b.kind=="int") or (a.kind=="int" and b.kind=="uint") then

    if op=="<<" or op==">>" then
       -- don't cast shifts - the rhs leads to 2^n shift options!
       return a, a, b
    else
      local ut = a
      local t = b
      if a.kind=="int" then ut,t = t,ut end
      
      local prec
      if ut.precision==t.precision and t.precision < 64 then
        prec = t.precision * 2
      elseif ut.precision<t.precision then
        prec = math.max(a.precision,b.precision)
      else
        error("Can't meet a "..tostring(ut).." and a "..tostring(t))
      end
      
      local thistype = types.int(prec)
      
      if cmpops[op] then
        return types.bool(), thistype, thistype
      elseif binops[op] or treatedAsBinops[op] then
        return thistype, thistype, thistype
      elseif op=="pow" then
        return thistype, thistype, thistype
      else
        print( "operation " .. op .. " is not implemented for aType:" .. a.kind .. " bType:" .. b.kind .. " " )
        assert(false)
      end
    end
  elseif (a.kind=="float" and (b.kind=="uint" or b.kind=="int")) or 
    ((a.kind=="uint" or a.kind=="int") and b.kind=="float") then
    
    local thistype
    local ftype = a
    local itype = b
    if b.kind=="float" then ftype,itype=itype,ftype end
    
    if ftype.precision==32 and itype.precision<32 then
      thistype = types.float(32)
    elseif ftype.precision==32 and itype.precision==32 then
      thistype = types.float(32)
    elseif ftype.precision==64 and itype.precision<64 then
      thistype = types.float(64)
    else
      assert(false) -- NYI
    end
    
    if cmpops[op] then
      return types.bool(), thistype, thistype
    elseif intbinops[op] then
      error("Passing a float to an integer binary op "..op)
    elseif binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="<<" or op==">>" then
       -- don't cast shifts - the rhs leads to 2^n shift options!
       return a, a, b
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP4",op)
      assert(false)
    end
    
  elseif a.kind=="float" and b.kind=="float" then
    
    local prec = math.max(a.precision,b.precision)
    local thistype = types.float(prec)
    
    if cmpops[op] then
      return types.bool(), thistype, thistype
    elseif intbinops[op] then
      error("Passing a float to an integer binary op "..op)
    elseif binops[op] or treatedAsBinops[op] then
      return thistype, thistype, thistype
    elseif op=="<<" or op==">>" then
       -- don't cast shifts - the rhs leads to 2^n shift options!
       return a, a, b
    elseif op=="pow" then
      local thistype = types.float(32)
      return thistype, thistype, thistype
    else
      print("OP3",op)
      assert(false)
    end
    
  elseif a.kind=="bool" and b.kind=="bool" then
    -- you can combine two bools into an array of bools
    if boolops[op]==nil and op~="array" then
      error("Internal error, attempting to meet two booleans on a non-boolean op: "..op)
      return nil
    end
    
    local thistype = types.bool()
    return thistype, thistype, thistype
  elseif a:isArray() and b:isArray()==false then
    -- we take scalar constants and duplicate them out to meet the other arguments array length
    local thistype, lhstype, rhstype = types.meet( a, types.array2d( b, a:arrayLength()[1], a:arrayLength()[2]), op, loc )
    return thistype, lhstype, rhstype
  elseif a:isArray()==false and b:isArray() then
    local thistype, lhstype, rhstype = types.meet( types.array2d(a, b:arrayLength()[1], b:arrayLength()[2] ), b, op, loc )
    return thistype, lhstype, rhstype
  elseif a:isNamed() and b:isNamed() then
    if op=="select" and a==b then
      return a,a,a
    else
      err(false,"NYI - meet of two named types "..tostring(a).." "..tostring(b))
    end
  elseif a:isBits() and b:isBits() then
    if op=="select" then
      err(a==b,"Select with bits must match precision")
      return a,a,a
    else
      error("NYI - bit meet "..op)
    end
  else
    error("Type error, meet not implemented for "..tostring(a).." and "..tostring(b)..", op "..op..", "..loc)
  end
  
  assert(false)
  return nil
end

-- check if type 'from' can be converted to 'to' (explicitly)
function types.checkExplicitCast(from, to, ast)
  assert(from~=nil)
  assert(to~=nil)

  if from==to then
    -- obvously can return true...
    return true
  elseif to.kind=="bits" and from.kind=="bits" and to:verilogBits()>from:verilogBits() then
    return true -- allow padding
  elseif to.kind=="bits" or from.kind=="bits" then
    -- we can basically cast anything to/from raw bits. Type Safety?!?!?!
    err( from:verilogBits()==to:verilogBits(), "Error, casting "..tostring(from).." to "..tostring(to)..", types must have same number of bits")
    return true
  elseif from:isArray() and to:isArray() and from:arrayOver()==to:arrayOver() then
    -- we do allow you to explicitly cast arrays of different shapes but the same total size
    if from:channels()~=to:channels() then
      error("Can't change array length when casting "..tostring(from).." to "..tostring(to) )
    end

    return types.checkExplicitCast(from.over, to.over,ast)
  elseif from:isTuple() then
    local allbits = J.foldt( J.map(from.list, function(n) return n:isBits() end), J.andop, 'X')

    if allbits then
      -- we let you cast a tuple of bits {bits(a),bits(b),...} to whatever
      err(from:verilogBits() == to:verilogBits(), "tuple of bits size fail from:"..tostring(from).." to "..tostring(to))
      return true
    elseif #from.list==1 and from.list[1]==to then
      -- casting {A} to A
      return true
    elseif to:isArray() then
      local allSubtype = true
      for k,v in pairs(from.list) do if v~=to:arrayOver() then allSubtype=false end end

      if allSubtype and #from.list == to:channels() then
        -- casting {A,A,A,A} to A[4]
        return true
      elseif from.list[1]:isArray() then
        -- we can cast {A[a],A[b],A[c]..} to A[a+b+c]
        local ty, channels = from.list[1]:arrayOver(), 0
        J.map(from.list, function(t) assert(t:arrayOver()==ty); channels = channels + t:channels() end )
        err( channels==to:channels(), "channels don't match") 
        return true
      end
    elseif to:isTuple() and #from.list==#to.list then
      for k,v in pairs(from.list) do
        local r = types.checkExplicitCast(from.list[k],to.list[k],ast)
        err(r, "Could not cast tuple "..tostring(from).." to "..tostring(to).." because index "..tostring(k-1).." could not be casted")
      end
      return true
    end

    error("unknown tuple cast? "..tostring(from).." to "..tostring(to))

  elseif to:isArray() and from==to.over then
    -- broadcast
    return types.checkExplicitCast(from, to.over, ast )
  elseif from:isArray() then
    if from:arrayOver():isBool() and from:channels()==to:verilogBits() then
      -- casting an array of bools to a type with the same number of bits is OK
      return true
    elseif from:channels()==1 and types.checkExplicitCast(from:arrayOver(),to,ast) then
      -- can explicitly cast an array of size 1 to a compatible type
      return true
    elseif to:isArray() then
      local fsz = from:arrayLength()
      local tsz = to:arrayLength()
      if fsz[1]==tsz[1] and fsz[2]==tsz[2] and types.checkExplicitCast(from:arrayOver(),to:arrayOver(),ast) then
        return true
      elseif fsz[1] == 1 and fsz[2] == 1 and types.checkExplicitCast(from:arrayOver(), to, ast) then
        -- if from is array[1,1] then unwrap it and try again
        return true
      elseif tsz[1] == 1 and tsz[2] == 1 and types.checkExplicitCast(from, to:arrayOver(), ast) then
        -- if to is array[1,1] then unwrap it and try again
        return true
      else
        err(false,"Can't cast array to array due to mismatch size or base type: "..tostring(from).." to "..tostring(to))
      end
    end

    error("Can't cast an array type to a non-array type. "..tostring(from).." to "..tostring(to)..ast.loc)
    return false
  elseif from.kind=="uint" and to.kind=="uint" then
    return true
  elseif from.kind=="int" and to.kind=="int" then
    return true
  elseif from.kind=="uint" and to.kind=="int" then
    return true
  elseif from.kind=="float" and to.kind=="uint" then
    return true
  elseif from.kind=="uint" and to.kind=="float" then
    return true
  elseif from.kind=="int" and to.kind=="float" then
    return true
  elseif from.kind=="int" and to.kind=="uint" then
    return true
  elseif from.kind=="int" and to.kind=="bool" then
    darkroom.error("converting an int to a bool will result in incorrect behavior! C makes sure that bools are always either 0 or 1. Terra does not.",ast:linenumber(),ast:offset())
    return false
  elseif from.kind=="bool" and (to.kind=="int" or to.kind=="uint") then
    darkroom.error("converting a bool to an int will result in incorrect behavior! C makes sure that bools are always either 0 or 1. Terra does not.",ast:linenumber(),ast:offset())
    return false
  elseif from.kind=="float" and to.kind=="int" then
    return true
  elseif from.kind=="float" and to.kind=="float" then
    return true
  elseif from.kind=="named" and to.kind~="named" then
    return types.checkExplicitCast(from.structure,to)
  elseif from.kind~="named" and to.kind=="named" then
    return types.checkExplicitCast(from,to.structure)
  else
    print("from",from,"to",to)
    assert(false) -- NYI
  end

  return false
end

---------------------------------------------------------------------
-- 'externally exposed' functions

function types.isType(ty)
  return getmetatable(ty)==TypeMT
end

-- convert all named types in this type to their equivalent structural type
function TypeFunctions:stripNamed()
  if self:isNamed() then
    return self.structure
  elseif self:isTuple() then
    local typelist = J.map(self.list, function(t) return t:stripNamed() end)
    return types.tuple(typelist)
  elseif self:isArray() then
    local L = self:arrayLength()
    return types.array2d( self:arrayOver():stripNamed(),L[1],L[2])
  elseif self:isUint() or self:isInt() or self:isBool() then
    return self
  else
    err(false,":stripNamed(), NYI "..tostring(self))
    
  end
end

function TypeFunctions:isArray()  return self.kind=="array" end

function TypeFunctions:arrayOver()
  err(self.kind=="array","arrayOver type was not an array, but is: "..tostring(self))
  return self.over
end

function TypeFunctions:baseType()
  if self.kind~="array" then return self end
  assert(type(self.over)~="array")
  return self.over
end


-- returns 0 if not an array
function TypeFunctions:arrayLength()
  if self.kind~="array" then return 0 end
  return self.size
end

function TypeFunctions:channels()
  if self.kind~="array" then return 1 end
  local chan = 1
  for k,v in ipairs(self.size) do chan = chan*v end
  return chan
end

function TypeFunctions:isTuple()  return self.kind=="tuple" end

function TypeFunctions:tupleList()
  if self.kind~="tuple" then return {self} end
  return self.list
end

function TypeFunctions:verilogBits()
  if self:isBool() then 
    return 1
  elseif self==types.null() then
    return 0
  elseif self:isTuple() then
    local sz = 0
    for _,v in pairs(self.list) do sz = sz + v:verilogBits() end
    return sz
  elseif self:isArray() then
    return self:arrayOver():verilogBits()*self.size[1]*self.size[2]
  elseif self:isInt() or self:isUint() then
    return self.precision
  elseif self:isBits() then
    return self.precision
  elseif self:isFloat() then
    return self.precision
  elseif self:isNamed() then
    return self.structure:verilogBits()
  else
    print(self)
    assert(false)
  end
end

function TypeFunctions:isFloat() return self.kind=="float" end
function TypeFunctions:isBool() return self.kind=="bool" end
function TypeFunctions:isInt() return self.kind=="int" end
function TypeFunctions:isUint() return self.kind=="uint" end
function TypeFunctions:isBits() return self.kind=="bits" end
function TypeFunctions:isNull() return self.kind=="null" end
function TypeFunctions:isNamed() return self.kind=="named" end
function TypeFunctions:is(str)
  if self.kind=="named" then return self.generator==str
  else return self.kind==str end
end

function TypeFunctions:isNumber()
  return self.kind=="float" or self.kind=="uint" or self.kind=="int"
end

function TypeFunctions:fakeValue()
  if self:isInt() or self:isUint() or self:isFloat() or self:isBits() then
    return 0
  elseif self:isArray() then
    local t = {}
    for i=1,self:channels() do table.insert(t,self:arrayOver():fakeValue()) end
    return t
  elseif self:isTuple() then
    local t = {}
    for k,v in ipairs(self.list) do
      table.insert(t,v:fakeValue())
    end
    return t
  elseif self:isBool() then
    return false
  elseif self:isNamed() then
    return self.structure:fakeValue()
  else
    err(false, "could not create fake value for "..tostring(self))
  end
end

-- check that v is a lua value convertable to this type
function TypeFunctions:checkLuaValue(v)
  if self:isArray() then
    err( type(v)=="table", "CheckLuaValue: if type is an array ("..tostring(self).."), value must be a table")
    err( #v==J.keycount(v), "CheckLuaValue: lua table is not an array (unstructured keys)")
    err( #v==self:channels(), "CheckLuaValue: incorrect number of channels, is "..(#v).." but should be "..self:channels() )
    for i=1,#v do
      self:arrayOver():checkLuaValue(v[i])
    end
  elseif self:isTuple() then
    err( type(v)=="table", "if type is "..tostring(self)..", value must be a table")
    err( #v==#self.list, "incorrect number of channels, is "..(#v).." but should be "..#self.list )
    J.map( v, function(n,k) self.list[k]:checkLuaValue(n) end )
  elseif self:isFloat() then
    err( type(v)=="number", "float must be number")
  elseif self:isInt() then
    err( type(v)=="number", "int must be number")
    err( v==math.floor(v), "integer systolic constant must be integer")
  elseif self:isUint() or self:isBits() then
    err( type(v)=="number", "checkLuaValue: uint/bits must be number but is "..type(v).." "..tostring(v))
    err( v>=0, "uint/bits const must be positive, but value is: "..tostring(v))
    err( v<math.pow(2,self:verilogBits()), "Constant value "..tostring(v).." out of range for type "..tostring(self))
    err( v==math.floor(v), "uint constant must be integer, but is: "..tostring(v) )
  elseif self:isBool() then
    err( type(v)=="boolean", "bool must be lua bool")
  elseif self:isNamed() then
    return self.structure:checkLuaValue(v)
  else
    print("NYI - :checkLuaValue with type ",self)
    assert(false)
  end

end

function TypeFunctions:valueToHex(v)
  if self:isArray() then
    local tab = {}
    for i=#v,1,-1 do
      table.insert(tab,self:arrayOver():valueToHex(v[i]))
    end
    return table.concat(tab,"")
  elseif self:isUint() then
    local res = string.format("%0"..tostring(self.precision/4).."x",v)
    return res
  elseif self:isInt() then
    err(v>=0,"NYI - signed int <0")
    local res = string.format("%0"..tostring(self.precision/4).."x",v)
    return res
  else
    err(false,":valueToHex NYI - "..tostring(self))
  end
end

-- convert a terra type into a rigel type
function types.fromTerraType(ty)
  if ty==uint16 then
    return types.uint(16)
  else
    err(false, "types.fromTerraType NYI"..tostring(ty))
  end
end


-- CPUs only support certain bit widths. Convert our arbitrary precision types to the nearest CPU that
-- which doesn't loose precision
--
-- why do we need this when we have :toTerraType()? B/C we want to support pure-luajit implementations (w/o terra installed)
function TypeFunctions:toCPUType()
  if self:isUint() then
    if self:verilogBits()<=8 then
      return types.uint(8)
    elseif self:verilogBits()<=16 then
      return types.uint(16)
    elseif self:verilogBits()<=32 then
      return types.uint(32)
    elseif self:verilogBits()<=64 then
      return types.uint(64)
    else
      err(false, "Type:toCPUType() uint NYI "..tostring(self))
    end
  elseif self:isBits() then
    if self:verilogBits()<=8 then
      return types.bits(8)
    elseif self:verilogBits()<=16 then
      return types.bits(16)
    elseif self:verilogBits()<=32 then
      return types.bits(32)
    elseif self:verilogBits()<=64 then
      return types.bits(64)
    else
      err(false, "Type:toCPUType() bits NYI "..tostring(self))
    end
  elseif self:isInt() then
    if self:verilogBits()<=8 then
      return types.int(8)
    elseif self:verilogBits()<=16 then
      return types.int(16)
    elseif self:verilogBits()<=32 then
      return types.int(32)
    elseif self:verilogBits()<=64 then
      return types.int(64)
    else
      err(false, "Type:toCPUType() int NYI "..tostring(self))
    end
  elseif self:isArray() then
    local sz = self:arrayLength()
    return types.array2d(self:arrayOver():toCPUType(),sz[1],sz[2])
  elseif self:isTuple() then
    local l = {}
    for _,v in pairs(self.list) do table.insert(l, v:toCPUType()) end
    return types.tuple(l)
  elseif self:isNamed() then
    return self.structure:toCPUType()
  else
    err(false, "Type:toCPUType() NYI "..tostring(self))
  end
end

function TypeFunctions:maxValue()
  if self:isUint() then
    return math.pow(2,self.precision)-1
  elseif self:isInt() then
    return math.pow(2,self.precision-1)-1
  else
    assert(false)
  end
end

function TypeFunctions:minValue()
  if self:isUint() then
    return 0
  elseif self:isInt() then
    return -math.pow(2,self.precision-1)
  else
    print("NYI - minValue of "..tostring(self))
    assert(false)
  end
end

-- can this type be converted to 'ty' without losing any data?
function TypeFunctions:canSafelyConvertTo(ty)
  if self==ty then -- trivial case
return true
  end

  if (self:isInt() or self:isUint()) and (ty:isInt() or ty:isUint()) then
    local minv, maxv = self:minValue(), self:maxValue()
    local tyminv, tymaxv = ty:minValue(), ty:maxValue()
    return (tyminv<=minv) and (tymaxv>=maxv)
  end

  return false
end

-- tries to find the most restrictive type that can represent lua value 'v'
function types.valueToType(v)
  if type(v)=="boolean" then
    return types.bool()
  elseif type(v)=="number" then
    if v==math.floor(v) then
      if v>=0 then
        local bts = math.max(math.ceil(math.log(v+1)/math.log(2)),1)
        local ty = types.uint(bts)
        J.err(v<=ty:maxValue(),"bad type? "..tostring(v).." in type: "..tostring(ty))
        assert(bts>0 or v>types.uint(bts-1):maxValue())
        return ty
      else
        assert(false)
      end
    else
      assert(false)
      return types.float(64)
    end
  else
    J.err(false,"types.valueToType: no rigel type that can represent '"..tostring(v).."'")
  end
end

function types.isBasic(A)
  assert(types.isType(A))
  if A:isArray() then
    return types.isBasic(A:arrayOver()) 
  elseif A:isTuple() then
    for _,v in ipairs(A.list) do
      if types.isBasic(v)==false then
        return false
      end
    end
    return true
  elseif A:isNamed() and A.generator=="fixed" then
    return true -- COMPLETE HACK, REMOVE
  elseif A:isNamed() then
    return false
  end

  return true
end

-- by default, this is ready-valid (RV), ie, ready_downstream has to be asserted before valid
-- if VR==true, this is instead valid-ready (VR), which allows valid to be asserted _before_ ready_downstream (optionally)
function types.Handshake(A,VR,X)
  err(types.isType(A),"Handshake: argument should be type")
  err(types.isBasic(A),"Handshake: argument should be basic type, but is: "..tostring(A))
  err(X==nil,"Handshake: too many arguments")
  if VR==nil then VR=false end
  local name = "Handshake("..tostring(A)..")"
  if VR then name = "HandshakeVR("..tostring(A)..")" end
  return types.named(name, types.tuple{A,types.bool()}, "Handshake", {A=A,VR=VR} )
end

function types.HandshakeVR(A,X)
  err(X==nil,"HandshakeVR: too many arguments")
  return types.Handshake(A,true)
end

function types.HandshakeVarlen(A)
  err(types.isType(A),"HandshakeVarlen: argument should be type")
  err(types.isBasic(A),"HandshakeVarlen: argument should be basic type, but is: "..tostring(A))
  return types.named("HandshakeVarlen("..tostring(A)..")", types.tuple{A,types.bool(),types.bool()}, "Handshake", {A=A} )
end

-- dims goes from innermost (idx 1) to outermost (idx n)
local function makeFramedType(kind,A,mixed,dims,extra0,extra1,X)
  err(types.isType(A),kind.."Framed: argument should be type, but is: "..tostring(A))
  err(types.isBasic(A),kind.."Framed: argument should be basic type, but is: "..tostring(A))
  err( type(mixed)=="boolean", kind.."Framed: mixed should be boolean, but is: "..tostring(mixed))
  err( type(dims)=="table", kind.."Framed: dims should be table")
  err( X==nil, kind.."Framed: too many arguments")

  -- make a deep copy, just in case
  local ldims = {}
  for i=1,#dims do
    err( type(dims[i])=="table", kind.."Framed: each entry of dims should be a table of size 2")
    err( #dims[i]==2, kind.."Framed: each entry of dims should be a table of size 2")

    local Uniform = require "uniform"
    
    if Uniform.isUniform(dims[i][1]) and dims[i][1].kind=="const" then dims[i][1]=dims[i][1].value end
    if Uniform.isUniform(dims[i][2]) and dims[i][2].kind=="const" then dims[i][2]=dims[i][2].value end
    
    err(type(dims[i][1])=="number", kind.."Framed: dim must be number")
    err(math.floor(dims[i][1])==dims[i][1], kind.."Framed: dim must be integer, but is: "..tostring(dims[i][1]))
    err(type(dims[i][2])=="number", kind.."Framed: dim must be number")
    err(math.floor(dims[i][2])==dims[i][2], kind.."Framed: dim must be integer, but is: "..tostring(dims[i][2]))
    table.insert(ldims,{dims[i][1],dims[i][2]})
  end

  err( mixed==false or A:isArray(),kind.."Framed: if mixed, input type must be an array, but is: "..tostring(A))
  
  if mixed then
    err(A.size[2]==1,kind.."Framed: NYI - mixed H~=1")

    err(A.size[1]<dims[1][1]*dims[1][2],kind.."Framed: when mixed, innermost serial dim must be larger than outermost parallel dim")
  end

  local str = kind.."Framed("

  local i
  if mixed then
    str = str..tostring(A:arrayOver()).."["..tostring(A.size[1])..";"..tostring(dims[1][1])..","..tostring(dims[1][2]).."}"
    i=2
  else
    str = str..tostring(A)
    i=1
  end

  for j=i,#dims do
    str = str.."{"..tostring(dims[j][1])..","..tostring(dims[j][2]).."}"
  end

  local structure
  local params = {A=A,dims=ldims,mixed=mixed}
  if kind=="Handshake" or kind=="V" or kind=="RV" then
    structure = types.tuple{A,types.bool()}
  elseif kind=="Static" then
    structure = A
  elseif kind=="HandshakeArray" then
    structure = types.array2d(types.tuple{A,types.bool()},extra0,extra1)
    if extra1==nil then extra1=1 end
    params.W, params.H = extra0, extra1
    str = str..","..tostring(extra0)..","..tostring(extra1)
  else
    assert(false)
  end
  
  return types.named(str..")", structure, kind.."Framed", params )
end

-- if A is an array, this specifies parallel dimensions (dimensions computed in parallel)
-- dims specifies _all_ dimensions, some of which may be in serial
-- dims should be in format {{4,2},{7,1},{1920,1080}}. Goes from innermost->outermost
function types.HandshakeFramed(A,mixed,dims) return makeFramedType("Handshake",A,mixed,dims) end
function types.HandshakeArrayFramed(A,mixed,dims,W,H) return makeFramedType("HandshakeArray",A,mixed,dims,W,H) end
function types.StaticFramed(A,mixed,dims) return makeFramedType("Static",A,mixed,dims) end
function types.VFramed(A,mixed,dims) return makeFramedType("V",A,mixed,dims) end
function types.RVFramed(A,mixed,dims) return makeFramedType("RV",A,mixed,dims) end

-- Add an extra outermost dim (loop) to the type
-- mixed: optional, perhaps this is adding dims to a type that already has sequential dimensions
function TypeFunctions:addDim(w,h,mixed)
  local Uniform = require "uniform"

  w = Uniform(w):toNumber()
  
  err( type(w)=="number", ":addDim w should be number")
  err( type(h)=="number", ":addDim h should be number")
  --err( type(mixed)=="boolean", ":addDim mixed should be boolean")
  if mixed==nil then mixed=false end
  err( mixed==false or types.isBasic(self) or self:is("V") or self:is("RV") or self:is("Handshake"), "addDim: if mixed, this must not have any sequential dimensions (would make no sense), but type is: "..tostring(self) )

  local ldims = {}
  local A
  local omixed = mixed
  if self:is("StaticFramed") or self:is("HandshakeFramed") then
    for i=1,#self.params.dims do
      table.insert(ldims,{self.params.dims[i][1],self.params.dims[i][2]})
    end
    A = self.params.A
    omixed = self.params.mixed
  elseif self:is("V") or self:is("RV") or self:is("Handshake") then
    A = self.params.A
  else
    A = self
    err(types.isBasic(self),":addDim - "..tostring(self))
  end

  table.insert(ldims,{w,h})

  if self:is("StaticFramed") or types.isBasic(self) then
    return types.StaticFramed(A,omixed,ldims)
  elseif self:is("HandshakeFramed") or self:is("Handshake") then
    return types.HandshakeFramed(A,omixed,ldims)
  elseif self:is("V") then
    return types.VFramed(A,omixed,ldims)
  elseif self:is("RV") then
    return types.RVFramed(A,omixed,ldims)
  else
    print("COULD NOT ADDDIM "..tostring(self))
    assert(false)
  end
end

-- figure out 'V' vector width setting from HandshakeFramed
-- 'V' is basically the last parallel dimension
function types.HSFV(A)
  assert(types.isType(A))
  err( A:is("HandshakeFramed") or A:is("StaticFramed") or A:is("HandshakeArrayFramed"), "calling HSFV on unsupported type: "..tostring(A) )

  assert(#A.params.dims==1)
  --  err(A.params.mixed, "HSFV: NYI - "..tostring(A))
  if A.params.mixed then
    assert(A.params.A.size[2]==1)
    return A.params.A.size[1]
  else
    return 0
  end
end

function types.HSFSize(A)
  assert(types.isType(A))
  J.err(A:is("HandshakeFramed") or A:is("StaticFramed") or A:is("HandshakeArrayFramed"), "HSFSize: should be framed but is "..tostring(A) )

  --assert(#A.params.dims==1)
  return {A.params.dims[#A.params.dims][1],A.params.dims[#A.params.dims][2]}
end

-- if we have HandshakeFramed(u8[8;640,480}), this will return u8
-- if we have HandshakeFramed(u8{640,480}), this will return u8
function types.HSFPixelType(A)
  assert(types.isType(A))
  J.err( A:is("HandshakeFramed") or A:is("StaticFramed") or A:is("HandshakeArrayFramed"), "HSFPixelType: should be framed, but is: "..tostring(A) )
--  local Adims,innerType = types.FramedCollectParallelDims(A.params.A)

  if A.params.mixed then
    return A.params.A:arrayOver()
  else
    return A.params.A
  end
end

function TypeFunctions:FV() return types.HSFV(self) end
function TypeFunctions:FW() return types.HSFSize(self)[1] end
function TypeFunctions:FH() return types.HSFSize(self)[2] end
function TypeFunctions:FPixelType() return types.HSFPixelType(self) end

-- this is sort of like arrayOver but for framed types
-- IE A[4,5]{1;3,4} would return A[4,5]
function TypeFunctions:framedOver()
  --assert(#self.params.dims==1) -- NYI

  local A = self.params.A
  if self.params.mixed then A = A:arrayOver() end
  
  if self:is("StaticFramed") and #self.params.dims==1 then
    return A
  elseif self:is("StaticFramed") and #self.params.dims>1 then
    return types.StaticFramed(self.params.A,self.params.mixed,J.slice(self.params.dims,1,#self.params.dims-1) )
  elseif self:is("HandshakeFramed") and #self.params.dims==1 then
    return types.Handshake(A)
  else
    print("framedOver NYI - "..tostring(self))
    assert(false)
  end
  
end

types.VTrigger = types.named("VTrigger", types.bool(), "VTrigger",{})
types.RVTrigger = types.named("RVTrigger", types.bool(), "RVTrigger",{})
types.HandshakeTrigger = types.named("HandshakeTrigger", types.bool(), "HandshakeTrigger",{})

function types.V(A) 
  err(types.isType(A),"V: argument should be type"); 
  err(types.isBasic(A), "V: argument should be basic type"); 
  return types.named("V("..tostring(A)..")", types.tuple{A,types.bool()}, "V", {A=A}) 
end

function types.RV(A) 
  err(types.isType(A), "RV: argument should be type"); 
  err(types.isBasic(A), "RV: argument should be basic type"); 
  return types.named("RV("..tostring(A)..")",types.tuple{A,types.bool()}, "RV", {A=A})  
end

function types.HandshakeArray(A,W,H)
  err(types.isType(A),"HandshakeArray: argument should be type")
  err(types.isBasic(A),"HandshakeArray: argument should be basic type")
  err(type(W)=="number" and W>0,"HandshakeArray: W should be number > 0")
  if H==nil then H=1 end
  err(type(H)=="number" and H>0,"HandshakeArray: H should be number > 0")
  return types.named("HandshakeArray("..tostring(A)..","..tostring(W)..","..tostring(H)..")", types.array2d(types.tuple{A,types.bool()},W,H), "HandshakeArray", {A=A,W=W,H=H} )
end

function types.HandshakeTriggerArray(W,H)
  err(type(W)=="number" and W>0,"HandshakeTriggerArray: W should be number > 0")
  if H==nil then H=1 end
  err(type(H)=="number" and H>0,"HandshakeTriggerArray: H should be number > 0")
  return types.named("HandshakeTriggerArray("..tostring(W)..","..tostring(H)..")", types.array2d(types.bool(),W,H), "HandshakeTriggerArray", {W=W,H=H} )
end

function types.HandshakeTuple(tab)
  err( type(tab)=="table" and J.keycount(tab)==#tab,"HandshakeTuple: argument should be table of types")

  local s = {}
  local ty = {}
  for k,v in ipairs(tab) do
    err(types.isType(v) and types.isBasic(v),"HandshakeTuple: type list must all be basic types, but index "..tostring(k).." is "..tostring(v))
    table.insert(s,tostring(v))
    table.insert(ty,types.tuple{v,types.bool()})
  end

  return types.named("HandshakeTuple("..table.concat(s,",")..")", types.tuple(ty), "HandshakeTuple", {list=tab} )
end

-- HandshakeArrayOneHot: upstream ready is a uint8 (idenfitying which stream should be read this cycle)
-- input is valid (is the stream requested by ready valid this cycle?)
function types.HandshakeArrayOneHot(A,N)
  err(types.isType(A),"HandshakeArrayOneHot: first argument should be type")
  err(types.isBasic(A),"HandshakeArrayOneHot: first argument should be basic type")
  err(type(N)=="number","HandshakeArrayOneHot: second argument should be number")
  return types.named("HandshakeArrayOneHot("..tostring(A)..","..tostring(N)..")", types.tuple{A,types.bool()}, "HandshakeArrayOneHot", {A=A,N=N} )
end

-- serialize N Handshake streams into 1. The valid bit is a unint8 which indicates which stream was chosen.
-- ready bit is a single bool
function types.HandshakeTmuxed(A,N)
  err(types.isType(A),"HandshakeTmuxed: first argument should be type")
  err(types.isBasic(A),"HandshakeTmuxed: first argument should be basic type")
  err(type(N)=="number","HandshakeTmuxed: second argument should be number")
  err(N<256,"HandshakeTmuxed: NYI - more than 255 streams not supported")
  return types.named("HandshakeTmuxed("..tostring(A)..","..tostring(N)..")", types.tuple{A,types.uint(8)}, "HandshakeTmuxed",{A=A,N=N} )
end


function types.isHandshakeArrayOneHot(a)
  err(types.isType(a),"isHandshakeArrayOneHot: argument must be a type")
  return a:isNamed() and a.generator=="HandshakeArrayOneHot"
end
function types.isHandshakeTmuxed(a)
  return a:isNamed() and a.generator=="HandshakeTmuxed"
end

function types.isHandshake( a ) return a:isNamed() and a.generator=="Handshake" end
function types.isHandshakeTrigger( a ) return a:isNamed() and a.generator=="HandshakeTrigger" end
function types.isHandshakeArray( a ) return a:isNamed() and a.generator=="HandshakeArray" end
function types.isHandshakeTriggerArray( a ) return a:isNamed() and a.generator=="HandshakeTriggerArray" end
function types.isHandshakeTuple( a ) return a:isNamed() and a.generator=="HandshakeTuple" end

-- is this any of the handshaked types?
function types.isHandshakeAny( a ) return types.isHandshake(a) or types.isHandshakeTrigger(a) or types.isHandshakeTuple(a) or types.isHandshakeArray(a) or types.isHandshakeTmuxed(a) or types.isHandshakeArrayOneHot(a) or a:is("HandshakeFramed") end

function types.isV( a ) return a:isNamed() and a.generator=="V" end
function types.isVTrigger( a ) return a:isNamed() and a.generator=="VTrigger" end
function types.isRV( a ) return a:isNamed() and a.generator=="RV" end
function types.isRVTrigger( a ) return a:isNamed() and a.generator=="RVTrigger" end
function types.expectBasic( A ) err( types.isBasic(A), "type should be basic but is "..tostring(A) ) end
function types.expectV( A, er ) if types.isV(A)==false then error(er or "type should be V but is "..tostring(A)) end end
function types.expectRV( A, er ) if types.isRV(A)==false then error(er or "type should be RV") end end
function types.expectHandshake( A, er ) if types.isHandshake(A)==false then error(er or "type should be handshake") end end

-- extract takes the darkroom, and returns the type that should be used by the terra/systolic process function
-- ie V(A) => {A,bool}
-- RV(A) => {A,bool}
-- Handshake(A) => {A,bool}
function types.lower( a, loc )
  err( types.isType(a), "lower: input is not a type. is: "..tostring(a))
  if types.isHandshake(a) or types.isHandshakeTrigger(a) or types.isVTrigger(a) or types.isRVTrigger(a) or types.isRV(a) or types.isV(a) or types.isHandshakeArray(a) or types.isHandshakeArrayOneHot(a) or types.isHandshakeTmuxed(a) or types.isHandshakeTuple(a) or types.isHandshakeTriggerArray(a) or a:is("StaticFramed") or a:is("HandshakeFramed") or a:is("VFramed") or a:is("RVFramed") or a:is("HandshakeArrayFramed") then
    return a.structure
  elseif types.isBasic(a) then 
    return a 
  end
  print("rigel.lower: unknown type? ",a)
  assert(false)
end

-- extract underlying actual data type.
-- V(A) => A
-- RV(A) => A
-- Handshake(A) => A
function types.extractData(a)
  if types.isHandshake(a) or types.isV(a) or types.isRV(a) or a:is("StaticFramed") or a:is("HandshakeFramed") or a:is("VFramed") or a:is("RVFramed") then return a.params.A end
  if types.isHandshakeTrigger(a) or types.isVTrigger(a) or types.isRVTrigger(a) then return types.null() end
  if types.isHandshakeArray(a) then return types.array2d(a.params.A,a.params.N) end
  return a -- pure
end

function types.hasReady(a)
  if types.isHandshake(a) or types.isHandshakeTrigger(a) or types.isRV(a) or types.isHandshakeArray(a) or types.isHandshakeTuple(a) or types.isHandshakeArrayOneHot(a) or types.isHandshakeTmuxed(a) or a:is("HandshakeFramed") or a:is("RVFramed") then
    return true
  elseif types.isBasic(a) or types.isV(a) or a:is("StaticFramed") or a:is("VFramed") then
    return false
  else
    print("UNKNOWN READY",a)
    assert(false)
  end
end

function types.extractReady(a)
  if types.isHandshake(a) or types.isHandshakeTrigger(a) or types.isV(a) or types.isRV(a) or a:is("HandshakeFramed") or a:is("RVFramed") then return types.bool()
  elseif types.isHandshakeTuple(a) then
    return types.array2d(types.bool(),#a.params.list) -- we always use arrays for ready bits. no reason not to.
  elseif types.isHandshakeArray(a) then
    return types.array2d(types.bool(),a.params.W*a.params.H)
  elseif types.isHandshakeArrayOneHot(a) then
    return types.uint(8)
  else 
    print("COULD NOT EXTRACT READY",a)
    assert(false) 
  end
end

function types.extractValid(a)
  if types.isHandshakeTmuxed(a) then
    return types.uint(8)
  end
  return types.bool()
end

function types.streamCount(A)
  if types.isBasic(A) or types.isV(A) or types.isRV(A) or A:is("StaticFramed") or A:is("VFramed") or A:is("RVFramed") then
    return 0
  elseif types.isHandshake(A) or A:is("HandshakeFramed") or types.isHandshakeTrigger(A) then
    return 1
  elseif types.isHandshakeArray(A) or types.isHandshakeTriggerArray(A) or A:is("HandshakeArrayFramed") then
    return A.params.W*A.params.H
  elseif types.isHandshakeTuple(A) then
    return #A.params.list
  elseif types.isHandshakeTmuxed(A) or types.isHandshakeArrayOneHot(A) then
    return A.params.N
  else
    err(false, "NYI streamCount "..tostring(A))
  end
end

-- is this type any type of handshake type?
function types.isStreaming(A)
  if types.isHandshake(A) or types.isHandshakeTrigger(A) or types.isHandshakeArray(A) or types.isHandshakeTuple(A) or  types.isHandshakeTmuxed(A) or types.isHandshakeArrayOneHot(A) or A:is("HandshakeFramed") then
    return true
  end
  return false
end

if terralib~=nil then require("typesTerra") end

for i=1,32 do
  types["u"..tostring(i)] = types.uint(i)
end

function types.export(t)
  if t==nil then t=_G end

  rawset(t,"u",types.uint)

  for i=1,32 do
    rawset(t,"u"..i,types["u"..i])
  end
  
  rawset(t,"i",types.int)
  rawset(t,"b",types.bits)
--  rawset(t,"bool",types.bool(false)) -- used in terra!!
  rawset(t,"ar",types.array2d)
  rawset(t,"tup",types.tuple)
  rawset(t,"Handshake",types.Handshake)
end

return types
