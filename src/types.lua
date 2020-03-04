local J = require("common")
local IR = require("ir")
local P = require "params"
local err = J.err

local types = {}

TypeFunctions = {}
TypeMT = {__index=TypeFunctions, __tostring=function(ty)
  local res
  if ty.kind=="bool" then
    res = "bool"
  elseif ty.kind=="null" then
    res = "null"
  elseif ty.kind=="Trigger" then
    res = "Trigger"
  elseif ty.kind=="unknown" then
    res = "UnknownType"
  elseif ty.kind=="int" then
    res = "int"..ty.precision
  elseif ty.kind=="uint" then
    res = "uint"..ty.precision
  elseif ty.kind=="bits" then
    res = "bits"..ty.precision
  elseif ty.kind=="float" then
    res = "float"..ty.precision
  elseif ty.kind=="array" then
    res = tostring(ty.over).."["..tostring(ty.size).."]"
  elseif ty.kind=="tuple" then
    local o,c="{","}"
    if ty:isInterface() then o,c="<",">" end
    if ty:isSchedule() then o,c="ScheduleTuple{","}" end
    
    if P.isParam(ty.list) or types.isType(ty.list) then
      res = o..tostring(ty.list)..c
    else
      res = o
      for k,v in ipairs(ty.list) do
        res = res..tostring(v)
        if k<#ty.list then res = res.."," end
      end
      res = res..c
    end
  elseif ty.kind=="Par" then
    res = "Par("..tostring(ty.over)..")"
  elseif ty.kind=="ParSeq" then
    res = tostring(ty.over.over).."["..tostring(ty.over.size)..";"..tostring(ty.size).."}"
  elseif ty.kind=="Seq" then
    res = tostring(ty.over).."{"..tostring(ty.size).."}"
  elseif ty.kind=="VarSeq" then
    res = tostring(ty.over).."{<="..tostring(ty.size).."}"
  elseif ty.kind=="Interface" then
    local pre = ""
    if ty.I~=nil then pre=pre.."I" end

    local v,r = "",""
    if ty.v~=nil then v=v.."v" end
    if ty.V==types.bool() then v=v.."V"
    elseif ty.V~=nil then v=v.."V="..tostring(ty.V).."," end

    if ty.r~=nil then r=r.."r" end
    if ty.R==types.bool() then r=r.."R"
    elseif ty.R~=nil then r=r.."R="..tostring(ty.R).."," end

    if ty.VRmode==true then
      pre = pre..v..r
    else
      pre = pre..r..v
    end

    if pre=="" then pre="S" end

    if ty.over==nil and pre=="S" then
      res = "Inil"
    else
      res = pre.."("..tostring(ty.over)..")"
    end
  elseif ty.kind=="named" then
    res = "NAMED"..ty.name
  else
    print("Error, typeToString input doesn't appear to be a type, ",ty.kind)
    assert(false)
  end

  --local mt = getmetatable(ty)
  --setmetatable(ty,nil)
  --res = res..tostring(ty)
  --setmetatable(ty,mt)
  
  return res
end}

types._bool=setmetatable({kind="bool"}, TypeMT)
function types.bool() return types._bool end
types.Bool = types.bool()

types._null=setmetatable({kind="null"}, TypeMT)
function types.null() return types._null end

types.Trigger = setmetatable({kind="Trigger"}, TypeMT)

types.Unknown = setmetatable({kind="unknown"},TypeMT)

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
types.Bits = types.bits

types._uint={}
function types.uint( prec, X )
  err(type(prec)=="number", "precision argument to types.uint must be number")
  err(prec==math.floor(prec), "uint precision should be integer, but is "..tostring(prec) )
  err(prec>0,"types.uint precision needs to be >0")
  err( X==nil, "types.uint: too many arguments" )
  types._uint[prec] = types._uint[prec] or setmetatable({kind="uint",precision=prec},TypeMT)
  return types._uint[prec]
end
types.u = types.uint
types.U = types.uint
types.Uint=types.uint

types._int={}
function types.int( prec, X )
  assert(prec==math.floor(prec))
  err( X==nil, "types.int: too many arguments" )
  err(prec>0,"types.int precision needs to be >0")
  types._int[prec] = types._int[prec] or setmetatable({kind="int",precision=prec},TypeMT)
  return types._int[prec]
end
types.I = types.int
types.Int=types.int

types._float={}
function types.float( prec, X )
  assert(prec==math.floor(prec))
  err( X==nil, "types.float: too many arguments" )
  types._float[prec] = types._float[prec] or setmetatable({kind="float",precision=prec},TypeMT)
  return types._float[prec]
end

types._array={}

function types.array2d( _type, w, h, X )
  err( types.isType(_type) or P.isParamType(_type), "first index to array2d must be Rigel type, but is: ",_type )

  local Uniform = require "uniform"
  if type(w)=="table" and Uniform.isUniform(w)==false and P.isParam(w)==false then
    assert(h==nil)
    assert(X==nil)
    return types.array2d(_type,w[1],w[2])
  end
  
  local size
  if P.isParamValue(w) then
    err( w.kind=="SizeValue", "array2d parametric argument must be size, but is: "..tostring(w))
    assert(h==nil)
    size = w
  else

    err( type(w)=="number", "types.array2d: second argument must be numeric width but is ",w,",",type(w) )
    err( type(h)=="number" or h==nil, "array2d h must be nil or number, but is:"..tostring(h),",",type(h) )
    if h==nil then h=1 end -- by convention, 1d arrays are 2d arrays with height=1

    err( w==math.floor(w), "non integer array width "..tostring(w))
    err( h==math.floor(h), "non integer array height "..tostring(h))
  
    err( w*h>0,"types.array2d: w*h must be >0, but is w:",w," h:",h )

    local R = require "rigel"
    size = R.Size(w,h)
  end

  --err( _type:verilogBits()>0, "types.array2d: array type must have >0 bits" )
  
  err( X==nil, "types.array2d: too many arguments" )
  
  -- dedup the arrays
  local ty = setmetatable( {kind="array", over=_type, size=size}, TypeMT )
  return J.deepsetweak(types._array, {_type,w,h}, ty)
end
types.Array2d = types.array2d

types._tuples = {}
types._tuplesParam = {}

function types.tuple( list, X )
  err( X==nil, "types.tuple: too many arguments" )

  if P.isParam(list) and list.kind=="TypeList" then -- parameterized
    if types._tuplesParam[list]~=nil then
      return types._tuplesParam[list]
    else
      types._tuplesParam[list] = setmetatable( {kind="tuple", list = list }, TypeMT )
      return types._tuplesParam[list]
    end
  end
    
  err(type(list)=="table","input to types.tuple must be table")
  err(J.keycount(list)==#list,"types.tuple: input table is not an array")
  err(#list>0, "no empty tuple types!")

  --[=[
  for k,v in ipairs(list) do
    if P.isParam(v) then
      err( P.DataType("tmp"):isSupertypeOf(v), "types.tuple: all items in list must be data types, but item "..tostring(k).." is: "..tostring(v))
    else
      err( types.isType(v), "types.tuple: all items in list must be types, but item "..tostring(k).." is :"..tostring(v))
      err( types.isBasic(v), "types.tuple: input type must be basic, but is: "..tostring(v) )
      --err(v:verilogBits()>0,"types.tuple: all types in list must have >0 bits")
    end
    end]=]
  
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
types.Tuple = types.tuple

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
  elseif a==b then
    return a,a,a
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
      err(from:verilogBits() == to:verilogBits(), "tuple of bits size fail from:",from," to ",to)
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

function types.checkAndSetVar(vars,k,v,varContext,X)
  assert(X==nil)
  assert(type(varContext)=="string")
  if varContext~="" then
    local oldK = k
    k = k:gsub("%$",varContext)
    --print("VARCONTEXT",varContext,oldK,k)
  end
  
  if vars[k]~=nil and vars[k]~=v then
    print("isSupertypeOf error: value of '",k,"' inconsistant! previous:",vars[k]," new:",v)
    return false
  end

  vars[k] = v
  return true
end

-- varContext: within a tuple list, we allow you to have things that vary per item (with $) and those that shouldn't. varContext is the string that $ gets replaced with.
function TypeFunctions:isSupertypeOf(ty,vars,varContext,X)
  assert(type(vars)=="table")
  assert(X==nil)
  local params = require "params"

  err( types.isType(ty) or params.isParam(ty), tostring(self)..":isSubtypeOf("..tostring(ty).."): input should be type or param, but is: "..tostring(ty) )

  assert(type(varContext)=="string")

  if self==ty then
    return true
  elseif types.isType(ty) then
    -- do the params of these types match?
    if J.keycount(self)~=J.keycount(ty) then -- might be optional things
      return false
    end
    
    for k,v in pairs(self) do
      if ty[k]==nil then
        --print(":isSupertypeOf(): Key '"..tostring(k).."' missing from ty '"..tostring(ty).."'?")
        return false
      end

      local R = require "rigel" 
      if type(v)=="string" or type(v)=="number" or R.isSize(v) then
        if ty[k]~=v then return false end
      elseif k=="list" then
        -- special case for parmaeterized tuple list
        if P.isParam(self.list) and self.list.kind=="TypeList" then

          -- this is used by specialize
          if types.checkAndSetVar(vars,self.list.name,{},varContext)==false then
return false end
          
          for kk,vv in ipairs(ty.list) do
            if self.list.constraint:isSupertypeOf(ty.list[kk],vars,tostring(kk)) then
              vars[self.list.name][kk]=vv
            else
              return false
            end
          end
        else
          -- this is a non-parameterized list - just check everything is OK
          for kk,vv in ipairs(v) do
            if vv:isSupertypeOf(ty[k][kk],vars,varContext) then
              if params.isParam(vv) then
                --print("SET VAR",vv.name,ty[k][kk])
                if types.checkAndSetVar(vars,vv.name,ty[k][kk],varContext)==false then
return false end
              end
            else
              return false
            end
          end
        end
      elseif types.isType(v) or params.isParam(v) then
        --print("CHECKSUPERTYPE",v,k,ty[k],self,ty)
        if v:isSupertypeOf(ty[k],vars,varContext) then
          if params.isParam(v) then
            --print("SET VAR",v.name,ty[k])
            if types.checkAndSetVar(vars,v.name,ty[k],varContext)==false then
return false end
          end
        else
          return false
        end
      else
        print("did not know how to handle type k,v:",k,v,"on type",self)
        assert(false)
      end
    end

    return true
--    err( self.over~=nil and ty.over~=nil, "Could not recurse into type? "..tostring(self).." "..tostring(ty).." "..tostring(self.over).." "..tostring(ty.over) )
    -- recurse into it. Ie it's Array(T)
    --    return self.over:isSupertypeOf(ty.over,vars)
  elseif params.isParam(ty) and ty.kind=="SumType" then
    --assert(#ty.list==1) -- NYI
    --vars[ty.name]=0 -- we chose index 0
    --print("RECURSE INTO SUMTYPE",ty,ty.list[1])
    for k,v in ipairs(ty.list) do
      if self:isSupertypeOf(v,vars,varContext) then
        if types.checkAndSetVar(vars,ty.name,k-1,varContext) then
return true end          
      end
    end
    return false
  elseif params.isParam(ty) then
    -- params always more general than specific types
    return false
  else
    assert(false)
  end
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

-- take the key 'k' in this types table, and replace it with value 'v',
-- and return a new valid type
function TypeFunctions:replaceVar(k,v)
  assert(k~="kind")

  local cpy = {}
  for kk,vv in pairs(self) do cpy[kk]=vv end
  cpy[k]=v

  local res
  if self:isUint() then
    res = types.uint(cpy.precision)
  elseif self:is("Interface") then
    res = types.Interface(cpy.over,cpy.R,cpy.V,cpy.I,cpy.r,cpy.v,cpy.VRmode)
  elseif self:is("ParSeq") then
    res = types.ParSeq(cpy.over,cpy.size)
  elseif self:is("Par") then
    res = types.Par(cpy.over)
  elseif self:is("Seq") then
    res = types.Seq(cpy.over,cpy.size)
  elseif self:is("VarSeq") then
    res = types.VarSeq(cpy.over,cpy.size)
  elseif self:is("array") then
    res = types.array2d(cpy.over,cpy.size)
  elseif self:isNamed() then
    res = types.named(cpy.name,cpy.structure,cpy.generator,cpy.params)
  else
    print(":replaceVar() NYI",self.kind)
    assert(false)
  end

  err(J.keycount(res)==J.keycount(self),"internal error: replaceVar on "..tostring(self))
  for kk,vv in pairs(self) do err(k==kk or res[kk]==vv,"internal error: replaceVar on ",self," key ",kk," is ",res[kk]," but should be:",vv) end

  return res
end

function TypeFunctions:isArray()  return self.kind=="array" end

function TypeFunctions:arrayOver()
  err(self.kind=="array","arrayOver type was not an array, but is: ",self)
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
  elseif self==types.null() or self==types.Trigger then
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
  elseif self:is("Par") or self:is("Seq") or self:is("ParSeq") or self:is("VarSeq") then
    return self.over:verilogBits()
  else
    err(false,":verilogBits() not implemented for: "..tostring(self))
  end
end

function TypeFunctions:isInil() return self.kind=="Interface" and self.R==nil and self.V==nil and self.I==nil and self.v==nil and self.r==nil and self.over==nil end
function TypeFunctions:isS() return self.kind=="Interface" and self.R==nil and self.V==nil and self.I==nil and self.v==nil and self.r==nil end
function TypeFunctions:isrV() return self.kind=="Interface" and self.R==nil and self.V==types.bool() and self.I==nil and self.v==nil and self.r==types.bool() end
function TypeFunctions:isrv() return self.kind=="Interface" and self.R==nil and self.v==types.bool() and self.I==nil and self.V==nil and self.r==types.bool() end
function TypeFunctions:isRv() return self.kind=="Interface" and self.r==nil and self.v==types.bool() and self.I==nil and self.V==nil and self.R==types.bool() end
function TypeFunctions:isrRv() return self.kind=="Interface" and self.r==types.bool() and self.v==types.bool() and self.I==nil and self.V==nil and self.R==types.bool() end
function TypeFunctions:isrvV() return self.kind=="Interface" and self.r==types.bool() and self.v==types.bool() and self.I==nil and self.V==types.bool() and self.R==nil end
function TypeFunctions:isrRV() return self.kind=="Interface" and self.r==types.bool() and self.v==nil and self.I==nil and self.V==types.bool() and self.R==types.bool() end
function TypeFunctions:isrRvV() return self.kind=="Interface" and self.r==types.bool() and self.v==types.bool() and self.I==nil and self.V==types.bool() and self.R==types.bool() end
function TypeFunctions:isRV() return self.kind=="Interface" and self.r==nil and self.v==nil and self.I==nil and self.V~=nil and self.R~=nil end
function TypeFunctions:isV() return self.kind=="Interface" and self.r==nil and self.v==nil and self.I==nil and self.V==types.bool() and self.R==nil end
function TypeFunctions:isrVTrigger() return self.kind=="Interface" and self.r==types.bool() and self.v==nil and self.I==nil and self.V==types.bool() and self.R==nil and self.over==nil end
function TypeFunctions:isrRVTrigger() return self.kind=="Interface" and self.r==types.bool() and self.v==nil and self.I==nil and self.V==types.bool() and self.R==types.bool() and self.over==nil end
function TypeFunctions:isData() return types.isBasic(self) end
--function TypeFunctions:isStatic() return self.kind=="Interface" and self.R==nil and self.V==nil and self.I==nil and selfend
function TypeFunctions:isInterface()
  if self.kind=="tuple" and (types.isType(self.list) or P.isParam(self.list)) then
    return self.list:isInterface()
  elseif self.kind=="tuple" then
    for k,v in ipairs(self.list) do
      if v:isInterface()==false then return false end
    end
    return true
  elseif self.kind=="array" then
    return self.over:isInterface()
  end

  return self.kind=="Interface"
end
--function TypeFunctions:isInterfaceType() return self.kind=="Interface" or self.kind=="InterfaceTuple" end
function TypeFunctions:isSchedule()
  if self.kind=="tuple" and (types.isType(self.list) or P.isParam(self.list)) then
    return self.list:isSchedule()
  elseif self.kind=="tuple" then
    for k,v in ipairs(self.list) do
      if v:isSchedule()==false then return false end
    end
    return true
  elseif self.kind=="array" then
    return self.over:isSchedule()
  end
    
  return self.kind=="Par" or self.kind=="Seq" or self.kind=="ParSeq" or self.kind=="VarSeq"
end
--function TypeFunctions:isScheduleType() return types.isScheduleType(self) end
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

types.TriggerFakeValue = {} -- table indices can't be nil
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
  elseif self==types.null() then
    return nil
  elseif self==types.Trigger then
    return types.TriggerFakeValue
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
    err( type(v)=="table", "if type is "..tostring(self)..", value must be a table, but is: "..tostring(v))
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
    err( type(v)=="boolean", "bool must be lua bool, but is '"..tostring(v).."'")
  elseif self:isNamed() then
    return self.structure:checkLuaValue(v)
  elseif self==types.null() then
    return v==nil
  elseif self==types.Trigger then
    return v==types.TriggerFakeValue
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
  if P.isParam(A) and (A.kind=="DataType" or A.kind=="NumberType" or A.kind=="BitsType" or A.kind=="UintType" or A.kind=="IntType") then return true end
  if P.isParam(A) then
    return P.DataType("tmp"):isSupertypeOf(A)
  end
  
  err(types.isType(A),"isBasic: input should be type, but is: "..tostring(A))
  if A:isArray() then
    return types.isBasic(A:arrayOver()) 
  elseif A:isTuple() then
    for _,v in ipairs(A.list) do
      if types.isBasic(v)==false then
        return false
      end
    end
    return true
  elseif A:is("uint") or A:is("bool") or A:is("int") or A:is("float") or A:is("bits") or A:is("null") then
    return true
  elseif A:is("null") then
    return false
  elseif A:is("Trigger") then
    return true
  elseif A:isInterface() then
    return false
  elseif A:is("Par") or A:is("ParSeq") or A:is("Seq") or A:is("VarSeq") then
    return false
  elseif A:isNamed() and A.generator=="fixed" then
    return true -- COMPLETE HACK, REMOVE
  elseif A:isNamed() then
    return false
  end

  print("NYI - isBasic",A)
  assert(false)
end

types.Par = J.memoize(function(D,X)
  err(X==nil, "types.Par: too many arguments")

  err( (types.isType(D) or P.isParam(D)) and D:isData(), "types.Par: input to schedule type should be a data type, but is: "..tostring(D) )
  err(D~=types.null(),"types.Par: input should not be null")

  return setmetatable({kind="Par",over=D},TypeMT)
end)

types.Seq = J.memoize(function(D,w,h,X)
  local Uniform = require "uniform"
  err( types.isType(D) or P.isParam(D),"types.Seq must be over a type, but is: "..tostring(D))
  err( D:isSchedule(), "types.Seq: input to Seq should be a schedule type, but is: "..tostring(D) )
  err(X==nil,"Seq: too many arguments")
  --print("MakeSeq",D,w,h,type(w),type(h))
  -- were we passed a {w,h} table?
  if type(w)=="table" and Uniform.isUniform(w)==false and P.isParam(w)==false then
    assert(h==nil)
    return types.Seq(D,w[1],w[2])
  end

  local size
  if P.isParamValue(w) then
    err( w.kind=="SizeValue","Seq: parametric size must be size, but is: "..tostring(size))
    assert(h==nil)
    size = w
  else    
    err( Uniform.isUniform(w) or type(w)=="number", "Seq: w must be number, but is: "..tostring(w))
    err( Uniform.isUniform(h) or type(h)=="number", "Seq: h must be number, but is: "..tostring(h))
    local R = require "rigel"
    size=R.Size(w,h)
  end

--  if types.isDataType(D) then
--    D = types.Par(D)
--  end
  
  local res = setmetatable({kind="Seq",over=D,size=size},TypeMT)
--  print("MakeSeq",D,w,h,res)
  return res
end)

types.VarSeq = J.memoize(function(D,w,h,X)
  local Uniform = require "uniform"
  err( types.isType(D) or P.isParam(D),"types.VarSeq must be over a type, but is: "..tostring(D))
  err( D:isSchedule(), "types.VarSeq: input to VarSeq should be a schedule type, but is: "..tostring(D) )
  err(X==nil,"VarSeq: too many arguments")

  if type(w)=="table" and Uniform.isUniform(w)==false and P.isParam(w)==false then
    assert(h==nil)
    return types.VarSeq(D,w[1],w[2])
  end

  local size
  if P.isParamValue(w) then
    err( w.kind=="SizeValue","VarSeq: parametric size must be size, but is: "..tostring(size))
    assert(h==nil)
    size = w
  else    
    err( Uniform.isUniform(w) or type(w)=="number", "VarSeq: w must be number, but is: "..tostring(w))
    err( Uniform.isUniform(h) or type(h)=="number", "VarSeq: h must be number, but is: "..tostring(h))
    local R = require "rigel"
    size=R.Size(w,h)
  end

  local res = setmetatable({kind="VarSeq",over=D,size=size},TypeMT)

  return res
end)

-- overlap: each parallel 'tile' overlaps each other (for stenciling)
--          The reason we want to do this, and not just use Seq, is that it's important that the nesting
--          levels don't change between parallel and sequential processing. 
types.ParSeq = J.memoize(function(D,w,h,X)
  local Uniform = require "uniform"
  err( (types.isType(D) or P.isParam(D)) and D:isData(), "types.ParSeq: input to schedule type should be a data type, but is: "..tostring(D) )
  err( D:isArray(), "types.ParSeq: input to schedule type should be array data type, but is: "..tostring(D) )
  err(X==nil,"ParSeq: too many arguments")
  
  -- were we passed a {w,h} table?
  if type(w)=="table" and Uniform.isUniform(w)==false and P.isParam(w)==false then
    assert(h==nil)
    return types.ParSeq(D,w[1],w[2])
  end

  local size
  if P.isParamValue(w) then
    err( w.kind=="SizeValue","ParSeq: parametric size must be size, but is: "..tostring(size))
    assert(h==nil)
    size = w
  else    
    err( Uniform.isUniform(w) or type(w)=="number", "ParSeq: w must be number, but is: "..tostring(w))
    err( Uniform.isUniform(h) or type(h)=="number", "ParSeq: h must be number, but is: "..tostring(h))
    local R = require "rigel"
    size=R.Size(w,h)
  end
  
  local res = setmetatable({kind="ParSeq",over=D,size=size},TypeMT)
  return res
end)

types.Interface = J.memoize(function(S,R,V,I,r,v,VRmode,X)
  err( S==nil or (types.isType(S) and S:isSchedule()) or (P.isParam(S) and S:isSchedule()), "types.Interface: input to interface type should be a schedule type, but is: "..tostring(S) )
  err( R==nil or types.isType(R), "types.Interface: Ready bit should be type, but is: "..tostring(R) )
  err( r==nil or types.isType(r), "types.Interface: Ready side fn (r) should be type, but is: "..tostring(r) )
  err( v==nil or types.isType(v), "types.Interface: Valid side fn (v) should be type, but is: "..tostring(v) )
  err( VRmode==nil or type(VRmode)=="boolean","Interface: VRmode should be nil or bool")
  assert(X==nil)

  return setmetatable({kind="Interface",over=S,R=R,V=V,I=I,r=r,v=v,VRmode=VRmode},TypeMT)
end)

function types.S(T) return types.Interface(T) end
function types.R(T) return types.Interface(T,types.bool()) end
function types.rV(T) return types.Interface(T,nil,types.bool(),nil,types.bool()) end
-- for old S->RV type, now rRv->rvV
function types.rRv(T) return types.Interface(T,types.bool(),nil,nil,types.bool(),types.bool()) end
function types.rRV(T) return types.Interface(T,types.bool(),types.bool(),nil,types.bool()) end
function types.rRvV(T) return types.Interface(T,types.bool(),types.bool(),nil,types.bool(),types.bool()) end
function types.rvV(T) return types.Interface(T,nil,types.bool(),nil,types.bool(),types.bool()) end
function types.rvV(T) return types.Interface(T,nil,types.bool(),nil,types.bool(),types.bool()) end
function types.Rv(T) return types.Interface(T,types.bool(),nil,nil,nil,types.bool()) end
function types.V(T) return types.Interface(T,nil,types.bool()) end
function types.RV(T) return types.Interface(T,types.bool(),types.bool()) end
function types.rv(T) return types.Interface(T,nil,nil,nil,types.bool(),types.bool()) end

-- by default, this is ready-valid (RV), ie, ready_downstream has to be asserted before valid
-- if VR==true, this is instead valid-ready (VR), which allows valid to be asserted _before_ ready_downstream (optionally)
function types.Handshake(A,VR,X)
  err(X==nil,"Handshake: too many arguments")
  -- legacy
  if types.isBasic(A) then A=types.Par(A) end
  return types.Interface(A,types.bool(),types.bool(),nil,nil,nil,VR)
end

function types.HandshakeVR(A,X)
  err(X==nil,"HandshakeVR: too many arguments")
  -- legacy
  if types.isBasic(A) then A=types.Par(A) end
  return types.Interface(A,types.bool(),types.bool(),nil,nil,nil,true)
end

function types.HandshakeVarlen(A)
  err(types.isType(A),"HandshakeVarlen: argument should be type")
  err(types.isBasic(A),"HandshakeVarlen: argument should be basic type, but is: "..tostring(A))
  return types.named("HandshakeVarlen("..tostring(A)..")", types.tuple{A,types.bool(),types.bool()}, "Handshake", {A=A} )
end


-- if A is an array, this specifies parallel dimensions (dimensions computed in parallel)
-- dims specifies _all_ dimensions, some of which may be in serial
-- dims should be in format {{4,2},{7,1},{1920,1080}}. Goes from innermost->outermost
function types.HandshakeFramed(A,mixed,dims)
  assert(#dims==1)
  if mixed then
    return types.RV(types.ParSeq(A,dims[1][1],dims[1][2]))
  end
  assert(false)
end
function types.HandshakeArrayFramed(A,mixed,dims,W,H) return makeFramedType("HandshakeArray",A,mixed,dims,W,H) end
--function types.StaticFramed(A,mixed,dims) return makeFramedType("Static",A,mixed,dims) end
--function types.VFramed(A,mixed,dims) return makeFramedType("V",A,mixed,dims) end
--function types.RVFramed(A,mixed,dims) return makeFramedType("RV",A,mixed,dims) end

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

types.HandshakeTrigger = types.Interface(types.Par(types.Trigger),types.bool(),types.bool())
--[=[
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
]=]
--types.VTrigger = types.named("VTrigger", types.bool(), "VTrigger",{})
--types.RVTrigger = types.named("RVTrigger", types.bool(), "RVTrigger",{})
--

--function types.V(A)
--  return types.Interface(A,nil,types.bool())
--end

--function types.RV(A)
--  return types.Interface(A,types.bool(),types.bool())
--end
--[=[
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
  end]=]

function types.HandshakeTuple(tab,VR,X)
  assert(X==nil)
  local t = {}
  for k,v in ipairs(tab) do table.insert(t,types.Handshake(v,VR)) end
  return types.tuple(t)
end

function types.HandshakeVRTuple(tab,X)
  assert(X==nil)
  return types.HandshakeTuple(tab,true)
end

-- HandshakeArrayOneHot: upstream ready is a uint8 (idenfitying which stream should be read this cycle)
-- input is valid (is the stream requested by ready valid this cycle?)
function types.HandshakeArrayOneHot(A,N)
  err(types.isType(A),"HandshakeArrayOneHot: first argument should be type")
  err(A:isSchedule(),"HandshakeArrayOneHot: first argument should be schedule type")
  err(type(N)=="number","HandshakeArrayOneHot: second argument should be number")

  return types.Interface(A,types.uint(8),types.bool())
end

-- serialize N Handshake streams into 1. The valid bit is a unint8 which indicates which stream was chosen.
-- ready bit is a single bool
function types.HandshakeTmuxed(A,N)
  err(types.isType(A),"HandshakeTmuxed: first argument should be type")
  err( A:isSchedule(),"HandshakeTmuxed: first argument should be schedule type, but is: "..tostring(A))
  err(type(N)=="number","HandshakeTmuxed: second argument should be number")
  err(N<256,"HandshakeTmuxed: NYI - more than 255 streams not supported")
  return types.Interface(A,types.bool(),types.uint(8))
end

function types.isHandshakeArrayOneHot(a)
  err(types.isType(a),"isHandshakeArrayOneHot: argument must be a type")
  return a:isNamed() and a.generator=="HandshakeArrayOneHot"
end
function types.isHandshakeTmuxed(a)
  return a:isNamed() and a.generator=="HandshakeTmuxed"
end

function types.isHandshake( a ) return a:is("Interface") and a.R~=nil and a.V~=nil end
function types.isHandshakeVR( a ) return a:is("Interface") and a.R~=nil and a.V~=nil and a.VRmode end
function types.isHandshakeTrigger( a ) return a:is("Interface") and a.R==types.bool() and a.V==types.bool() and a.v==nil and a.r==nil and a.I==nil and a.over==nil end
function types.isHandshakeArray( a ) return a:isArray() and types.isHandshake(a.over) end
function types.isHandshakeTriggerArray( a ) return a:isArray() and types.isHandshakeTrigger(a.over) end
function types.isHandshakeTuple( a )
  if a:isTuple()==false then return false end
  for k,v in ipairs(a.list) do if v:isRV()==false then return false end end
  return true
end

-- is this any of the handshaked types?
function types.isHandshakeAny( a )
  if a:is("Interface") then
    return a:isRV()
  elseif a:isTuple() then
    for _,v in ipairs(a.list) do if types.isHandshakeAny(v) then return true end end
    return false
  elseif a:isArray() then
    return types.isHandshakeAny(a.over)
  else
    print("isHandshakeAny NYI:",a)
    assert(false)
  end
end

--function types.isV( a ) return a:isNamed() and a.generator=="V" end
--function types.isVTrigger( a ) return a:isNamed() and a.generator=="VTrigger" end
--function types.isRV( a ) return a:isNamed() and a.generator=="RV" end
--function types.isRVTrigger( a ) return a:isNamed() and a.generator=="RVTrigger" end
function types.expectBasic( A ) err( types.isBasic(A), "type should be basic but is "..tostring(A) ) end
function types.expectV( A, er ) if types.isV(A)==false then error(er or "type should be V but is "..tostring(A)) end end
function types.expectRV( A, er ) if types.isRV(A)==false then error(er or "type should be RV") end end
function types.expectHandshake( A, er ) if types.isHandshake(A)==false then error(er or "type should be handshake") end end

function TypeFunctions:lower() return types.lower(self) end

-- extract takes the darkroom, and returns the type that should be used by the terra/systolic process function
-- ie V(A) => {A,bool}
-- RV(A) => {A,bool}
-- Handshake(A) => {A,bool}
function types.lower( a )
  err( types.isType(a), "lower: input is not a type. is: "..tostring(a))

  if a:isTuple() then
    local res = {}
    for _,v in ipairs(a.list) do table.insert(res,types.lower(v)) end
    return types.tuple(res)
  elseif a:isArray() then
    return types.array2d(types.lower(a.over),a.size)
  elseif a:is("Interface") then
    if a==types.Interface() then
      return types.null()
    else
      --local over = a.over
      --if over~=nil then over = types.lower(a.over) end
      
      if a.over~=nil and a.V~=nil then return types.tuple{a.over:lower(),a.V} end
      if a.over~=nil then return a.over:lower() end
      if a.V~=nil then return a.V end
      print("COULD NOT LOWER ",a,over,over:lower(),over:lower():verilogBits(),a.V)
      assert(false)
    end
  elseif a:isSchedule() then
    --if a:is("Par") or a:is("ParSeq") then
    return types.lower(a.over)
    --end
  elseif types.isBasic(a) then
    return a
  end
  
  print("rigel.lower: unknown type? ",a)
  assert(false)
end

function TypeFunctions:extractSchedule()
  if self:isSchedule() then
    return self
  elseif self:isInterface() and self:isInil()==false then
    if self:is("Interface") then
      return self.over:extractSchedule()
    else
      print("Could not extract schedule from ",self)
      assert(false)
    end
  else
    err(false,":extractSchedule: type doesn't not contain a schedule type? "..tostring(self) )
  end
end

function TypeFunctions:extractData()
  return types.extractData(self)
end

-- extract underlying actual data type.
-- V(A) => A
-- RV(A) => A
-- Handshake(A) => A
function types.extractData(a)
  assert(types.isType(a))
  if a:is("Interface") or a:isSchedule() then
    if a.over==nil then return types.null() end
    return types.extractData(a.over)
  elseif a:isData() then
    return a
  elseif a:isTuple() or a:isArray() then
    assert(false)
  end
  print("extractData: unsupported: "..tostring(a))
  assert(false)
end

function types.hasReady(a)
  if types.isHandshake(a) or types.isHandshakeTrigger(a) or a:isRV() or types.isHandshakeArray(a) or types.isHandshakeTuple(a) or types.isHandshakeArrayOneHot(a) or types.isHandshakeTmuxed(a) or a:is("HandshakeFramed") or a:is("RVFramed") then
    return true
  elseif types.isBasic(a) or a:isS() or a:isV() or a:isrv() or a:isrV() or a:isrvV() or a==types.Interface() then
    return false
  elseif a:isTuple() then
    for _,v in pairs(a.list) do if types.hasReady(v) then return true end end
    return false
  else
    print("UNKNOWN READY",a)
    assert(false)
  end
end

function TypeFunctions:extractReady()
  return types.extractReady(self)
end

function types.extractReady(a)
  assert(a:isInterface())

  if a:isTuple() then
    local res = {}
    for _,v in ipairs(a.list) do table.insert(res,types.extractReady(v)) end
    return types.tuple(res)
  elseif a:isArray() then
    return types.array2d(types.extractReady(a.over),a.size)
  elseif a:is("Interface") then
    if a.R~=nil then
      return a.R
    else
      return a.r
    end
  else
    print("extractReady NYI on "..tostring(a))
    assert(false)
  end
end

function types.extractValid(a)
  if a:is("Interface") then
    if a.V~=nil then
      return a.V
    else
      return a.v
    end
  else
    print("extractValid NYI on "..tostring(a))
    assert(false)
  end
  
  --if types.isHandshakeTmuxed(a) then
--    return types.uint(8)
--  end
--  return types.bool()
end

function types.streamCount(A)
  if A:is("Interface") then
    if A.R~=nil and A.V~=nil then
      return 1
    else
      return 0
    end
  elseif A:isTuple() then
    local cnt = 0
    for _,v in ipairs(A.list) do
      cnt = cnt + types.streamCount(v)
    end
    return cnt
  elseif A:isArray() then
    return types.streamCount(A.over)*A.size[1]*A.size[2]
  else
    err(false, "NYI streamCount "..tostring(A))
  end
end

-- is this type any type of handshake type?
function types.isStreaming(A)
  if A:is("Interface") then
    if A:isRV() then
      return true
    else
      return false
    end
  elseif A:isTuple() then
    local res = false
    for _,v in ipairs(A.list) do
      res = res or types.isStreaming(v)
    end
    return res
  else
    err(false, "NYI isStreaming "..tostring(A))
  end
end

if terralib~=nil then require("typesTerra") end

for i=1,64 do
  types["u"..tostring(i)] = types.uint(i)
end

function types.export(t)
  if t==nil then t=_G end

  rawset(t,"u",types.uint)

  for i=1,64 do
    rawset(t,"u"..i,types["u"..i])
  end
  
  rawset(t,"i",types.int)
  rawset(t,"b",types.bits)
--  rawset(t,"bool",types.bool(false)) -- used in terra!!
  rawset(t,"ar",types.array2d)
  rawset(t,"tup",types.tuple)
  rawset(t,"Handshake",types.Handshake)
  rawset(t,"HandshakeTrigger",types.HandshakeTrigger)
end

return types
