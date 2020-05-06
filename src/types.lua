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
    if ty.exp==0 then
      res = "int"..ty.precision
    else
      res = "int"..ty.precision.."_"..ty.exp
    end
  elseif ty.kind=="uint" then
    if ty.exp==0 then
      res = "uint"..ty.precision
    else
      res = "uint"..ty.precision.."_"..ty.exp
    end
  elseif ty.kind=="bits" then
    res = "bits"..ty.precision
  elseif ty.kind=="float" then
    if ty==types.Float32 then
      res = "Float32"
    else
      res = "float_"..ty.exp.."_"..ty.sig
    end
  elseif ty.kind=="floatRec" then
    if ty==types.FloatRec32 then
      res = "FloatRec32"
    else
      res = "floatRec_"..ty.exp.."_"..ty.sig
    end
  elseif ty.kind=="array" then
    if ty.size==ty.V then
      res = tostring(ty.over).."["..J.sel(ty.var,"<=","")..tostring(ty.size).."]"
    elseif ty.V[1]==0 and ty.V[2]==0 then
      res = tostring(ty.over).."{"..J.sel(ty.var,"<=","")..tostring(ty.size).."}"
    else
      res = tostring(ty.over).."["..tostring(ty.V)..";"..J.sel(ty.var,"<=","")..tostring(ty.size).."}"
    end
  elseif ty.kind=="tuple" then
    local o,c="{","}"
    if ty:isInterface() then o,c="<",">" end
    
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

--types._uint={}
types.uint = J.memoize(function( prec, exp, X )
  if exp==nil then return types.uint( prec, 0 ) end

  err(type(prec)=="number", "precision argument to types.uint must be number")
  err(prec==math.floor(prec), "uint precision should be integer, but is "..tostring(prec) )
  err(prec>0,"types.uint precision needs to be >0")

  err(type(exp)=="number", "exp argument to types.uint must be number")
  err(exp==math.floor(exp), "uint exp should be integer, but is "..tostring(exp) )

  err( X==nil, "types.uint: too many arguments" )

  return setmetatable({kind="uint", precision=prec, exp=exp },TypeMT)
end)
types.u = types.uint
types.U = types.uint
types.Uint=types.uint

types.int = J.memoize(function( prec, exp, X )
  if exp==nil then return types.int( prec, 0 ) end
  
  err(type(prec)=="number", "int: precision argument must be number")
  err(prec==math.floor(prec), "int precision should be integer, but is "..tostring(prec) )
  err( X==nil, "types.int: too many arguments" )
  err(prec>0,"types.int precision needs to be >0")

  err(type(exp)=="number", "int: exp argument  must be number")
  err(exp==math.floor(exp), "int: exp should be integer, but is "..tostring(exp) )

  return setmetatable({kind="int",precision=prec,exp=exp},TypeMT)
end)
types.I = types.int
types.Int=types.int

types.Float = J.memoize(function( exp, sig, X )
  err( type(exp)=="number", "Float: exp must be number" )
  err( type(sig)=="number", "Float: sig must be number" )
  err( exp==math.floor(exp) )
  err( sig==math.floor(sig) )
  err( X==nil, "types.Float: too many arguments" )
  
  return setmetatable({kind="float", exp=exp, sig=sig },TypeMT)
end)
types.Float32 = types.Float( 8, 24 )
types.Float16 = types.Float( 5, 11 )

types.FloatRec = J.memoize(function( exp, sig, X )
  err( type(exp)=="number", "types.FloatRec: exp must be number" )
  err( type(sig)=="number", "types.FloatRec: sig must be number" )
  err( exp==math.floor(exp) )
  err( sig==math.floor(sig) )
  err( X==nil, "types.FloatRec: too many arguments" )
  
  return setmetatable({kind="floatRec", exp=exp, sig=sig },TypeMT)
end)
types.FloatRec32 = types.FloatRec( 8, 24 )
types.FloatRec16 = types.FloatRec( 5, 11 )


types._array={}

local function parsePolyArgs( args, i )
  local Uniform = require "uniform"
  local R = require "rigel"
  
  if R.isSize(args[i]) then
    return args[i], i+1
  elseif P.isParamValue(args[i]) then
    err( args[i].kind=="SizeValue", "array2d parametric argument must be size, but is: "..tostring(args[i]))
    return args[i], i+1
  else
    err( type(args[i])=="number" or Uniform.isUniform(args[i]), "types.array2d: second argument must be numeric width or uniform but is ",args[i],",",type(args[i]) )
    err( type(args[i+1])=="number" or args[i+1]==nil or Uniform.isUniform(args[i+1]), "array2d h must be nil or number or Uniform, but is:",args[i+1],",",type(args[i+1]) )
    
    local w,h = args[i], args[i+1]
    if h==nil then h=1 end -- by convention, 1d arrays are 2d arrays with height=1
    
    err( Uniform(w):isInteger(), "non integer array width "..tostring(w))
    err( Uniform(h):isInteger(), "non integer array height "..tostring(h))
    
    return R.Size(w,h), i+2
  end

  assert(false)
end

-- highly polymorphic: this can either take 2 numbers, a param, or a size
-- Vector width is optional: by default, vector width equals size
-- if size and V are passed as numbers: both dimensions must be given
-- however, in the end, we store size and V as a rigel.Size
-- last argument, var:bool, indicates that this is variable sized
function types.array2d( _type, ... )
  local Uniform = require "uniform"
  err( types.isType(_type) or P.isParamType(_type), "first argument to array2d must be Rigel type, but is: ",_type )

  local args = {...}

  local size, nexti = parsePolyArgs( args, 1 )

  local R = require "rigel"
  err( P.isParamValue(size) or (Uniform(size[1])*Uniform(size[2])):gt(0):assertAlwaysTrue(),"types.array2d: w*h must be >0, but is w:",size[1]," h:",size[2] )

  local V
  if args[nexti]==nil then
    V = size -- by default: make plain array
  else
    V, nexti = parsePolyArgs( args, nexti )
    --err( args[nexti]==nil, "types.array2d: too many arguments" )
  end

  if R.isSize(size) and R.isSize(V) then
    err( (Uniform(size[1])*Uniform(size[2])):ge(Uniform(V[1])*Uniform(V[2])):assertAlwaysTrue(),"types.array2d: Vector size must be smaller than array size! size:",size," V:",V)

    local veq0 = (Uniform(V[1]):eq(0)):And(Uniform(V[2]):eq(0))
    local vmulgt0 = (Uniform(V[1])*Uniform(V[2])):gt(0)
    err( (veq0:Or(vmulgt0)):assertAlwaysTrue(), "types.array2d, Vw*Vh must be >0, or Vw and Vh must both be 0, but are: ", V )
  end

  local var = false
  if args[nexti]~=nil and type(args[nexti])=="boolean" then
    var = args[nexti]
    nexti = nexti+1
  end

  J.err( args[nexti]==nil, "array2d: too many args!" )
  
  -- dedup the arrays
  local ty = setmetatable( {kind="array", over=_type, size=size, V=V, var=var}, TypeMT )
  return J.deepsetweak(types._array, {_type,size,V,var}, ty)
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
    elseif op=="*" then
      local lhstype = types.int(prec,a.exp)
      local rhstype = types.int(prec,b.exp)
      local outtype = types.int(prec,a.exp+b.exp)
      return outtype, lhstype, rhstype
    elseif op=="+" or op=="-" then
      err( a.exp==b.exp, "NYI - ",op," with mismatched exponants! lhs:",a," rhs:",b)
      local outtype = types.int( prec, a.exp )
      return outtype, outtype, outtype
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
    elseif op=="*" then
      local lhstype = types.uint(prec,a.exp)
      local rhstype = types.uint(prec,b.exp)
      local outtype = types.uint(prec,a.exp+b.exp)
      return outtype, lhstype, rhstype
    elseif op=="+" or op=="-" then
      err( a.exp==b.exp, "NYI - ",op," with mismatched exponants! lhs:",a," rhs:",b)
      local outtype = types.uint( prec, a.exp )
      return outtype, outtype, outtype
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
    
    --local prec = math.max(a.precision,b.precision)
    err( a==b, "NYI - float type meet, lhs and rhs must be same type" )
    local thistype = a
    
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
    err( from:verilogBits()==to:verilogBits(), "Error, casting ",from," to ",to,", types must have same number of bits")
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
    --print("isSupertypeOf error: value of '",k,"' inconsistant! previous:",vars[k]," new:",v)
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
      if type(v)=="string" or type(v)=="number" or R.isSize(v) or type(v)=="boolean" then
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
        if v:isSupertypeOf(ty[k],vars,varContext) then
          if params.isParam(v) then
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
  elseif params.isParam(ty) and ty.kind=="SumType" then
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
    res = types.uint( cpy.precision, cpy.exp )
  elseif self:isInt() then
    res = types.int( cpy.precision, cpy.exp )
  elseif self:is("Interface") then
    res = types.Interface(cpy.over,cpy.R,cpy.V,cpy.I,cpy.r,cpy.v,cpy.VRmode)
  elseif self:is("array") then
    res = types.array2d( cpy.over, cpy.size, cpy.V, cpy.var )
  elseif self:isNamed() then
    res = types.named(cpy.name,cpy.structure,cpy.generator,cpy.params)
  else
    print(":replaceVar() NYI",self.kind)
    assert(false)
  end

  err(J.keycount(res)==J.keycount(self),"internal error: replaceVar on "..tostring(self))
  for kk,vv in pairs(self) do err(k==kk or res[kk]==vv,"internal error: replaceVar on ",self," key ",kk," is ",res[kk]," but should be:",vv," this means the type constructor changed and you need to update the call in this function.") end

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
    return self.exp+self.sig
  elseif self:isFloatRec() then
    return self.exp+self.sig+1
  elseif self:isNamed() then
    return self.structure:verilogBits()
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

-- schedule => this is a scheduled data type
-- if this is a plain data type, this returns false
-- if this is an interface data type, this returns false
function TypeFunctions:isSchedule()
  if self:isData() then return true end
  if self:isInterface() then return false end
  
  if self:isArray() then
    return self.V~=self.size or self.over:isSchedule()
  elseif self.kind=="tuple" then
    for k,v in ipairs(self.list) do
      if v:isSchedule() then return true end
    end    
  end
  
  return false
end

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

function TypeFunctions:isFloat() return self.kind=="float" end
function TypeFunctions:isFloatRec() return self.kind=="floatRec" end
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
  if self:isInt() or self:isUint() or self:isFloat() or self:isFloatRec() or self:isBits() then
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
    err( type(v)=="table", "CheckLuaValue: if type is an array (",self,"), value must be a table, but is: ",v)
    err( #v==J.keycount(v), "CheckLuaValue: lua table is not an array (unstructured keys)")
    err( #v==self:channels(), "CheckLuaValue: incorrect number of channels, is "..(#v).." but should be "..self:channels() )
    for i=1,#v do
      self:arrayOver():checkLuaValue(v[i])
    end
  elseif self:isTuple() then
    err( type(v)=="table", "if type is "..tostring(self)..", value must be a table, but is: "..tostring(v))
    err( #v==#self.list, "incorrect number of channels, is "..(#v).." but should be "..#self.list )
    J.map( v, function(n,k) self.list[k]:checkLuaValue(n) end )
  elseif self:isFloat() or self:isFloatRec() then
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
    return types.isBasic(A:arrayOver()) and A.size==A.V
  elseif A:isTuple() then
    for _,v in ipairs(A.list) do
      if types.isBasic(v)==false then
        return false
      end
    end
    return true
  elseif A:is("uint") or A:is("bool") or A:is("int") or A:is("float") or A:is("floatRec") or A:is("bits") or A:is("null") then
    return true
  elseif A:is("null") then
    return false
  elseif A:is("Trigger") then
    return true
  elseif A:isInterface() then
    return false
  elseif A:isNamed() and A.generator=="fixed" then
    return true -- COMPLETE HACK, REMOVE
  elseif A:isNamed() then
    return false
  end

  print("NYI - isBasic",A)
  assert(false)
end

types.Par = function(D,X)
  err(X==nil, "types.Par: too many arguments")

  err( (types.isType(D) or P.isParam(D)) and D:isData(), "types.Par: input to schedule type should be a data type, but is: "..tostring(D) )
  err(D~=types.null(),"types.Par: input should not be null")

  return D
end

types.Seq = function(D, ...)
  local Uniform = require "uniform"
  err( types.isType(D) or P.isParam(D),"types.Seq must be over a type, but is: "..tostring(D))
  err( D:isData() or D:isSchedule(), "types.Seq: input to Seq should be a basic or schedule type, but is: "..tostring(D) )

  local args = {...}

  local size, nexti = parsePolyArgs( args, 1 )
  err( args[nexti]==nil,"Seq: too many arguments")
  
  return types.Array2d( D, size, 0,0 )
end

types.VarSeq = J.memoize(function(D, ...)
  local Uniform = require "uniform"
  err( types.isType(D) or P.isParam(D),"types.VarSeq must be over a type, but is: "..tostring(D))
  err( D:isData(), "types.VarSeq: input to VarSeq should be a data type, but is: "..tostring(D) )

  local args = {...}

  local size, nexti = parsePolyArgs( args, 1 )
  err( args[nexti]==nil,"VarSeq: too many arguments")

  return types.Array2d( D, size, 0, 0, true )
end)

types.ParSeq = function( D, ... )
  local Uniform = require "uniform"
  err( (types.isType(D) or P.isParam(D)) and D:isData(), "types.ParSeq: input to schedule type should be a data type, but is: "..tostring(D) )
  err( D:isArray(), "types.ParSeq: input to schedule type should be array data type, but is: "..tostring(D) )

  local args = {...}

  local V, nexti = parsePolyArgs( args, 1 )
  err( args[nexti]==nil,"ParSeq: too many arguments")

  return types.Array2d( D.over, V, D.size )
end

types.Interface = J.memoize(function(S,R,V,I,r,v,VRmode,X)
  err( S==nil or ( (types.isType(S) or P.isParam(S)) and S:isInterface()==false), "types.Interface: input to interface type should be a schedule type, but is: "..tostring(S) )
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

function types.expectBasic( A ) err( types.isBasic(A), "type should be basic but is "..tostring(A) ) end
function types.expectV( A, er ) if types.isV(A)==false then error(er or "type should be V but is "..tostring(A)) end end
function types.expectRV( A, er ) if types.isRV(A)==false then error(er or "type should be RV") end end
function types.expectHandshake( A, er ) if types.isHandshake(A)==false then error(er or "type should be handshake") end end

function TypeFunctions:optimize( rates )
  local SDF = require "sdf"

  err( SDF.isSDF(rates), "type: optimize, rates should be SDF but is: ",rates )

  if self:isInil() then
    return self, rates -- nothing to do
  elseif self:is("Interface") then
    local recTy, recRates = self.over:optimize(rates)
    return self:replaceVar( "over", recTy ), recRates
  elseif self:isArray() then
    if self:isInterface() then
      for k,v in ipairs(rates) do
        err( SDF(v)==SDF(rates[1]),"Optimize an array of interfaces: all input rates must be the same! is:",v," but other is:",rates[1] )
      end

      local tty, trate = self.over:optimize(SDF(rates[1]))
      local res = self:replaceVar("over", tty )

      assert( self:deSchedule()==res:deSchedule() )

      local rr = SDF(J.broadcast(trate[1],#rates))

      return res, rr
    else
      if rates:allGE1() then
        -- we're already at 100%, nothing we can do, just return
        return self, rates
      else
        if self.V:eq(0,0) then
          -- we've done all we can here, try to recurse
          local recTy, recRates = self.over:optimize( rates )
          return self:replaceVar( "over", recTy ), recRates
        else
          J.err( #rates==1,"NYI - optimize with multiple rates!, type:",self," rates:",rates)
                 
          -- try to optimize
          local V = J.canonicalV( rates*SDF{ self.V[1]*self.V[2],self.size[1]*self.size[2]}, self.size )

          if V:eq(0,0) then
            -- remainder was <1, so try to recurse
            local tmp = self:replaceVar( "V", V )
            -- this is safe, b/c we know self.V>0 from branch above!
            local recTy, recRate = tmp.over:optimize( rates*SDF{self.V[1]*self.V[2],1} )
            return tmp:replaceVar( "over", recTy ), recRate
          else
            -- we're done, we've bottomed out
            return self:replaceVar( "V", V ), SDF{1,1}
          end
        end
      end
    end
  elseif self:isTuple() then
--    if self:isInterface() then
--      assert(false) -- NYI
--    else
    local newlist = {}
    local rout = {}
    
    for k,v in ipairs(self.list) do
      local rte = rates
      if self:isInterface() then
        rte = rates[k]
      end
      
      local recTy, recRate = v:optimize( SDF(rte) )
      table.insert( rout, recRate[1] )
      table.insert( newlist, recTy )
    end
    
    if self:isInterface()==false then
      rout = rout[1]
    end
      
    return types.tuple(newlist), SDF(rout)
  end

  return self, rates
end

function TypeFunctions:lower() return types.lower(self) end

-- extract takes the darkroom, and returns the type that should be used by the terra/systolic process function
-- ie V(A) => {A,bool}
-- RV(A) => {A,bool}
-- Handshake(A) => {A,bool}
function types.lower( a )
  err( types.isType(a), "lower: input is not a type. is: "..tostring(a))
  local Uniform = require "uniform"
  
  if a:isTuple() then
    local res = {}
    for _,v in ipairs(a.list) do table.insert(res,types.lower(v)) end
    return types.tuple(res)
  elseif a:isArray() then
    if Uniform(a.V[1]):eq(0):assertAlwaysTrue() and Uniform(a.V[2]):eq(0):assertAlwaysTrue() then
      return types.lower(a:arrayOver())
    else
      return types.array2d(types.lower(a:arrayOver()),a.V)
    end
  elseif a:is("Interface") then
    if a==types.Interface() then
      return types.null()
    else
      if a.over~=nil and a.V~=nil then return types.tuple{a.over:lower(),a.V} end
      if a.over~=nil then return a.over:lower() end
      if a.V~=nil then return a.V end
      print("COULD NOT LOWER ",a,over,over:lower(),over:lower():verilogBits(),a.V)
      assert(false)
    end
  elseif types.isBasic(a) then
    return a
  end
  
  print("rigel.lower: unknown type? ",a)
  assert(false)
end

function TypeFunctions:extractData()
  return types.extractData(self)
end

-- extract underlying actual data type.
-- this is the type of the data portion of the HW interface
-- note the difference with 'lower': lower returns data+control signals (like valid).
--   extractData just returns the data
-- this removes (lowers) schedule types
-- V(A) => A
-- RV(A) => A
-- Handshake(A) => A
types.extractData = J.memoize(function(a)
  assert(types.isType(a))
  local Uniform = require "uniform"

  local res
  if a:is("Interface") then
    if a.over==nil then return types.null() end
    res = types.extractData(a.over)
  elseif a:isData() then
    res = a
  elseif a:isArray() then
    -- this is a scheduled array - we need to return type of data bus
    assert(a:isSchedule())
    if Uniform(a.V[1]):eq(0):assertAlwaysTrue() and Uniform(a.V[2]):eq(0):assertAlwaysTrue() then
      res = a:arrayOver():extractData() -- special case for not vectorized
    else
      res = types.array2d( a:arrayOver():extractData(), a.V )
    end
  elseif a:isTuple() then
    local newlist = {}
    for k,v in ipairs(a.list) do newlist[k] = v:extractData() end
    res = types.Tuple(newlist)    
  else
    print("extractData: unsupported: "..tostring(a))
    assert(false)
  end

  err( res:isData(), "internal error: extractData() did not return a data type. type:", a, " returned: ", res )
  return res
end)

function TypeFunctions:deInterface() return types.deInterface(self) end

-- strip out any interface bits
types.deInterface = J.memoize(function(ty)
  assert( types.isType(ty) )

  local res
  if ty:isInterface()==false then
    res = ty
  elseif ty:is("Interface") then
    res = ty.over

    if res==nil then res = types.null() end -- inil
  elseif ty:isTuple() then -- InterfaceTuple
    local newlist = {}
    for k,v in ipairs(ty.list) do newlist[k] = v:deInterface() end
    res = types.Tuple(newlist)
  elseif ty:isArray() then
    res = ty:replaceVar( "over", ty.over:deInterface() )
  else
    print("deInterface NYI - ",ty)
    assert(false)
  end

  J.err( res:isSchedule() or res:isData(), "Internal error, deinterface failed of type: ",ty," which returned: ",res )
  return res
end)

function TypeFunctions:deSchedule() return types.deSchedule(self) end

-- strip out any schedule bits
-- NOT THE SAME AS extractData/lower! This returns the fully parallel arrays, not vector-width arrays
-- deSchedule strips out interface stuff as well
types.deSchedule = J.memoize(function(ty)
  ty = ty:deInterface()

  local res
  if ty:isData() then
    res = ty
  elseif ty:isArray() then
    res = ty:replaceVar("over", ty.over:deSchedule() )
    res = res:replaceVar("V", ty.size )
  elseif ty:isTuple() then
    local reslist = {}
    for _,v in ipairs(ty.list) do
      table.insert( reslist, v:deSchedule() )
    end
    res = types.tuple(reslist)
  else
    print("NYI: deSchedule of type ", ty)
    assert(false)
  end

  assert( res:isData() )
  return res
end)

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
    elseif a.v~=nil then
      return a.v
    else
      err(false,"extractValid: type doesn't have a valid bit: ",a)
    end
  end

  print("extractValid NYI on "..tostring(a))
  assert(false)
end

function TypeFunctions:streamCount()
  return types.streamCount(self)
end

function types.streamCount(A)
  if A:is("Interface") then
    if A:isRV() then
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

function TypeFunctions:specialize( vars )
  if self:isTuple() then
    -- special case for tuples (!)
    local lst = self.list
    if P.isParam(self.list) and self.list.kind=="TypeList" then
      lst = vars[self.list.name]
    end
    
    local newList = {}
    for k,v in ipairs(lst) do
      table.insert( newList, v:specialize(vars) )
    end
    return types.tuple(newList)
  else
    local newT = self
    for k,v in pairs(self) do
      if P.isParam(v) or types.isType(v) then
        newT = newT:replaceVar( k, v:specialize( vars ) )
      end
    end
    
    return newT
  end

  assert(false)
end

if terralib~=nil then require("typesTerra") end

for i=1,64 do
  types["u"..tostring(i)] = types.uint(i)
  types["U"..tostring(i)] = types.uint(i)
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
