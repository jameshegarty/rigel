local R = require "rigel"
local rigel = R
local RM = require "generators.modules"
local types = require "types"
local S = require "systolic"
local Ssugar = require "systolicsugar"
local modules = RM
local J = require "common"
local memoize = J.memoize
local err = J.err
local f = require "fixed_new"
local SDF = require "sdf"
local Uniform = require "uniform"

if terralib~=nil then CT=require("generators.examplescommonTerra") end

local C = {}

C.identity = memoize(function( A, name )
  err( A:isSchedule(),"C.identity: type should be schedule type, but is: "..tostring(A) )

  if name==nil then
    name = "identity_"..J.verilogSanitize(tostring(A))
  end
  
  local identity = RM.lift( name, A:lower(), A:lower(), 0, function(sinp) return sinp end, function() return CT.identity(A) end, "C.identity")

  assert( identity.inputType == types.rv(A:lower()) )
  assert( identity.outputType == types.rv(A:lower()) )
  identity.inputType = types.rv(A)
  identity.outputType = types.rv(A)
  return identity
end)

C.fassert = memoize(function(filename,A)
  err(types.isBasic(A),"C.fassert: type should be basic, but is: "..tostring(A) )

  local fassert = {name=J.verilogSanitize("fassert_"..tostring(A).."_file"..tostring(filename))}
  fassert.inputType = A
  fassert.outputType = A
  fassert.sdfInput=SDF{1,1}
  fassert.sdfOutput=SDF{1,1}
  fassert.stateful=true
  fassert.delay=0
  function fassert.makeTerra() return CT.fassert(filename,A) end

  function fassert.makeSystolic()
    local sm = Ssugar.moduleConstructor(fassert.name)
    local inp = S.parameter( "process_input", rigel.lower(fassert.inputType) )
    sm:addFunction( S.lambda("process", inp, inp, "process_output", nil,nil,S.CE("process_CE")) )
    sm:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "reset_out") )
    return sm
  end
  return rigel.newFunction(fassert)
end)

-- showIfInvalid: display data, even if it's invalid
C.print = memoize(function( A, str, showIfInvalid, X )
  err(types.isBasic(A),"C.print: type should be basic, but is: "..tostring(A) )
  assert(X==nil)

  if showIfInvalid==nil then showIfInvalid=false end
  
  local function constructPrint(A,symb)

    if A:isUint() or A:isInt() or A:isBits() then
      return {A}, "%0d", {symb}
    elseif A:isFloat() then
      -- $bitstoreal could maybe be used?
      return {A}, "%0d", {symb}
    elseif A:isArray() then
      local resTypes={}
      local resStr="["
      local resValues={}
      for y=0,A.size[2]-1 do
        for x=0,A.size[1]-1 do
          local tT,tS,tV = constructPrint(A:arrayOver(),S.index(symb,x,y))
          resStr = resStr..tS..","
          table.insert(resTypes,tT)
          table.insert(resValues,tV)
        end
      end
      return J.flatten(resTypes), resStr.."]", J.flatten(resValues)
    elseif A:isTuple() then
      local resTypes={}
      local resStr="{"
      local resValues={}
      for i=1,#A.list do
        local tT,tS,tV = constructPrint(A.list[i],S.index(symb,i-1))
        resStr = resStr..tS..","
        table.insert(resTypes,tT)
        table.insert(resValues,tV)
      end
      return J.flatten(resTypes), resStr.."}", J.flatten(resValues)
    else
      err(false,"C.print NYI - type: "..tostring(A))
    end
  end
  
  --local identity = RM.lift( , A, A, 0, function(sinp) return sinp end, function() return CT.print(A,str) end, "C.print")
  local res = {name = J.verilogSanitize("print_"..tostring(A).."_STR"..tostring(str)),inputType=A,outputType=A,sdfInput=SDF{1,1}, sdfOutput=SDF{1,1} }
  res.stateful=true
  res.delay=0
  function res.makeSystolic()
    local sm = Ssugar.moduleConstructor(res.name)
    local inp = S.parameter( "process_input", rigel.lower(res.inputType) )

    local typelist, printStr, valuelist = constructPrint(A,inp)
    if str~=nil then printStr = str.." "..printStr end
    local printInst = sm:add( S.module.print( types.tuple(typelist), printStr, true, showIfInvalid ):instantiate("printInst") )
    local pipelines = {printInst:process( S.tuple(valuelist) )}
    sm:addFunction( S.lambda("process", inp, inp, "process_output", pipelines,nil,S.CE("process_CE")) )
    sm:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "reset_out",{printInst:reset()}) )
    return sm
  end
  
  function res.makeTerra() return CT.print(res,A,str) end
  
  return rigel.newFunction(res)
end)

C.cast = memoize(function(A,B)
  err(types.isType(A),"cast: A should be type")
  err(types.isType(B),"cast: B should be type")
  err( R.isBasic(A), "cast: A should be basic type. casting "..tostring(A).." to "..tostring(B) )
  err( R.isBasic(B), "cast: B should be basic type. casting "..tostring(A).." to "..tostring(B) )
  if terralib~=nil then
    err(A:isTuple()==false, "C.cast: NYI - terra cast from '"..tostring(A).."' to '"..tostring(B).."'") -- not supported by terra
  end
  
  local docast = RM.lift( J.sanitize("cast_"..tostring(A).."_"..tostring(B)), A, B, 0, function(sinp) return S.cast(sinp,B) end, function() return CT.cast(A,B) end, "C.cast" )
  return docast
end)

C.bitSlice = memoize(
  function(A,low,high)
    local bitslice = RM.lift( J.sanitize("bitslice_"..tostring(A).."_"..tostring(low).."_"..tostring(high)), A, types.bits(high-low+1), 0,
                          function(sinp)
                            return S.bitSlice(sinp,low,high)
                          end)
    return bitslice
  end)

C.bitcast = memoize(function( A, B, X)
  err( X==nil, "C.bitcast: too many args" )
  err( types.isType(A),"cast: A should be type, but is: ",A)
  err( types.isType(B),"cast: B should be type, but is: ",B)
  err( R.isBasic(A), "cast: A should be basic type. casting "..tostring(A).." to "..tostring(B) )
  err( R.isBasic(B), "cast: B should be basic type. casting "..tostring(A).." to "..tostring(B) )

  err(A:verilogBits()==B:verilogBits(), "TYPE SIZE NOT EQ: "..tostring(A).."  - "..tostring(B))
  local docast = RM.lift( J.sanitize("bitcast_"..tostring(A).."_"..tostring(B)), A, B, 0,
                          function(sinp)
                            local tmp = S.cast(sinp,types.bits(A:verilogBits()))
                            return S.cast(tmp,B)
                          end,
                          function() return CT.bitcast(A,B) end, "C.cast" )
  return docast
end)

-- takes bits(N)[M] to bits(N*M)
C.flattenBits = memoize(function(ty)
  if ty:isArray() and ty:arrayOver():isBits() then
    return RM.lift( J.sanitize("FlattenBits_"..tostring(ty)), ty, types.bits(ty:verilogBits()), 0, function(sinp) return S.cast(sinp,types.bits(ty:verilogBits())) end, function() assert(false) end, "C.flattenBits" )
  else
    J.err( "NYI - flattenBits of type "..tostring(ty) )
  end
end)

-- takes bits(N*M) to bits(M)[N]
C.partitionBits = memoize(function(ty, N)
  J.err( type(N)=="number", "C.partitionBits: N must be number")
  J.err( ty:verilogBits()%N==0, "C.partitionBits: N must device type bits")
  if ty:isBits() then
    local otype = types.array2d(types.bits(ty:verilogBits()/N),N)
     return RM.lift( J.sanitize("PartitionBits_"..tostring(ty).."_"..tostring(N)), ty, otype, 0, function(sinp) return S.cast(sinp,otype) end, function() assert(false) end, "C.partitionBits" )
  else
    J.err( "NYI - partitionBits of type "..tostring(ty) )
  end
end)

-- takes {T[N/2],T[N/2]} to T[N]
C.flatten2 = memoize(function(T,N)
  err(types.isType(T),"flatten2: T should be type")
  err(T:isData(),"flatten2: T should be data type, but is: "..tostring(T))
  --assert(T:isTuple()==false) -- not supported by terra
  local AI = types.array2d(T,N/2)
  local docast = RM.lift( J.sanitize("flatten2_"..tostring(T).."_"..tostring(N)), types.tuple{AI,AI}, types.array2d(T,N), 0, function(sinp) return S.cast(sinp,types.array2d(T,N)) end, function() return CT.flatten2(T,N) end, "C.flatten2" )
  return docast
end)

-- flatten nested arrays: take A[V;N}{M} to A[V;N*M}
-- outer array must be fully sequential
C.flatten = memoize(function( innerT, innerSize, innerV, outerSize, X )
  assert( types.isType(innerT ) )
  assert( R.isSize(innerSize))
  assert( R.isSize(innerV))
  assert( R.isSize(outerSize))
  assert( X==nil )
  
  local G = require "generators.core"
    
  local res = G.Function{"Flatten_"..tostring(innerT).."_w"..tostring(innerSize[1]).."_h"..tostring(innerSize[2]).."_VW"..tostring(innerV[1]).."_VH"..tostring(innerV[2]).."_W"..tostring(outerSize[1]).."_H"..tostring(outerSize[2]), types.RV(types.Array2d( types.Array2d(innerT,innerSize,innerV),outerSize,0,0)),SDF{1,1},function(inp) return inp end}

  assert(R.isPlainFunction(res))
  local W,H = outerSize[1]*innerSize[1], outerSize[2]*innerSize[2]
  local newType = types.RV(types.Array2d( innerT, W, H, innerV ))
  assert(res.outputType:lower()==newType:lower())
  res.outputType = newType

  return res
end)

-- converts {A,A,A...} to A[W,H] (input should be tuple of W*H A's)
C.tupleToArray = memoize(function(A,W,H,X)
  err(types.isType(A),"tupleToArray: A should be type")
  err(type(W)=="number","tupleToArray: W must be number")
  if H==nil then H=1 end
  err(type(H)=="number","tupleToArray: H must be number")
  err( X==nil,"tupleToArray: too many arguments")
  
  local atup = types.tuple(J.broadcast(A,W*H))
  local B = types.array2d(A,W,H)

  local docast = RM.lift( J.sanitize("tupleToArray_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H)), atup, B, 0,
    function(sinp) return S.cast(sinp,B) end,
    function() return CT.tupleToArray(A,W,H,atup,B) end, "C.tupleToArray")

  return docast
end)

-- converts T[W,H] to {T,T,T,T...}
C.ArrayToTuple = memoize(function(T,W,H,X)
  err(types.isType(T),"ArrayToTuple: A should be type")
  err(type(W)=="number","ArrayToTuple: W must be number")
  if H==nil then H=1 end
  err(type(H)=="number","ArrayToTuple: H must be number")
  err( X==nil,"ArrayToTuple: too many arguments")
  err( W*H>0, "ArrayToTuple: W*H must be >0, but is W:",W," H:",H)
  
  local G = require "generators.core"
  return G.Function{"ArrayToTuple_"..tostring(T).."_W"..tostring(W).."_H"..tostring(H), types.rv(types.Par(types.array2d(T,W,H))),
    function(inp)
      local res = {}
      for y=0,H-1 do
        for x=0,W-1 do
          table.insert(res,G.Index{{x,y}}(inp))
        end
      end
      return R.concat(res)
    end}
end)

------------
-- return A*B as a darkroom FN. A,B are types
-- returns something of type outputType
C.multiply = memoize(function(A,B,outputType)
  err( types.isType(A), "C.multiply: A must be type")
  assert( A:isData() )
  err( types.isType(B), "C.multiply: B must be type")
  assert( B:isData() )
  err( types.isType(outputType), "C.multiply: outputType must be type")
  assert( outputType:isData() )
  
  local bits 
  local partial = RM.lift( J.sanitize("mult_A"..tostring(A).."_B"..tostring(B).."_"..tostring(outputType)), types.tuple {A,B}, outputType, nil, --S.interp(S.delayTable["*"],outputType:verilogBits()),
    function(sinp) return S.cast(S.index(sinp,0),outputType)*S.cast(S.index(sinp,1),outputType) end,
    function() return CT.multiply(A,B,outputType) end,
    "C.multiply" )

  return partial
end)

C.multiplyE = memoize(function( A, B, X )
  err( types.isType(A), "C.multiplyE: lhs type must be type")
  assert( A:isData() )
  err( A:isUint() or A:isInt(), "C.multiplyE: lhs must be uint or int, but is: ",A )
  err( types.isType(B), "C.multiplyE: rhs must be type")
  assert( B:isData() )
  err( B:isUint() or B:isInt(), "C.multiplyE: rhs must be uint or int, but is: ",B )
  assert( X==nil )
  assert( A:isUint()==B:isUint() )

  local outputType = A:replaceVar("precision",A.precision+B.precision):replaceVar("exp",A.exp+B.exp)
  local outL = A:replaceVar("precision",A.precision+B.precision)
  local outR = B:replaceVar("precision",A.precision+B.precision)

  local partial = RM.lift( J.sanitize("multE_A"..tostring(A).."_B"..tostring(B)), types.tuple {A,B}, outputType, nil,
    function(sinp)
      local i0 = S.index(sinp,0)
      local lhs = S.cast(i0,outL)
      local i1 = S.index(sinp,1)
      local rhs = S.cast(i1,outR)
      local res = lhs*rhs
      print("i0",i0.type,lhs.type,i1.type,rhs.type,res.type)
      return res
    end)

  return partial
end)

------------
-- return A*B as a darkroom FN. A,B are types
-- returns something of type outputType
C.multiplyConst = memoize(function( A, constValue, outputType, X )
  err( types.isType(A), "C.multiply: A must be type")
  err( type(constValue)=="number","C.multiplyConst: value must be number, but is: "..tostring(constValue) )
  err(X==nil,"C.multiplyConst: too many arguments" )

  if outputType==nil then outputType = A end
  assert( types.isType(outputType) )
  
  local partial = RM.lift( J.sanitize("mult_const_A"..tostring(A).."_value"..tostring(constValue).."_OT"..tostring(outputType)), A, outputType, nil,
                           function(sinp) return S.cast(sinp,outputType)*S.constant(constValue,outputType:replaceVar("exp",0)) end,
    function() return CT.multiplyConst(A,constValue,outputType) end,
    "C.multiplyConst" )

  return partial
end)

------------------------------
C.Abs = memoize(function(A,X)
  err( types.isType(A), "C.Abs: A must be type")
  assert(X==nil)

  local partial = RM.lift( J.sanitize("Abs_A"..tostring(A)), A, A, 1,
    function(sinp) return S.abs(sinp) end )

  return partial
end)

------------------------------
C.GT = memoize(function(A,B)
  err( types.isType(A), "C.GT: A must be type")
  err( types.isType(B), "C.GT: B must be type")

  local partial = RM.lift( J.sanitize("GT_A"..tostring(A).."_B"..tostring(B)), types.tuple {A,B}, types.bool(), 0,
    function(sinp) return S.gt(S.index(sinp,0),S.index(sinp,1)) end )

  return partial
end)

------------------------------
C.LT = memoize(function(A,B)
  err( types.isType(A), "C.LT: A must be type")
  err( types.isType(B), "C.LT: B must be type")

  local partial = RM.lift( J.sanitize("LT_A"..tostring(A).."_B"..tostring(B)), types.tuple {A,B}, types.bool(), 0,
    function(sinp) return S.lt(S.index(sinp,0),S.index(sinp,1)) end )

  return partial
end)

------------
-- return A*B as a darkroom FN. A,B are types
-- returns something of type outputType
C.GTConst = memoize(function(A,constValue)
  err( types.isType(A), "C.GTConst: A must be type")
  
  local partial = RM.lift( J.sanitize("GT_const_A"..tostring(A).."_value"..tostring(constValue)), A, types.bool(), 0,
                           function(sinp) return S.gt(sinp,S.constant(constValue,A)) end )

  return partial
end)

C.LTConst = memoize(function(A,constValue)
  err( types.isType(A), "C.LTConst: A must be type")
  
  local partial = RM.lift( J.sanitize("LT_const_A"..tostring(A).."_value"..tostring(constValue)), A, types.bool(), 1,
                           function(sinp) return S.lt(sinp,S.constant(constValue,A)) end )

  return partial
end)

C.Not = RM.lift( "Not", types.bool(), types.bool(), 0, function(sinp) return S.__not(sinp) end )
C.And = RM.lift( "And", types.tuple{types.bool(),types.bool()}, types.bool(), 0, function(sinp) return S.__and(S.index(sinp,0),S.index(sinp,1)) end )

C.AndUint = memoize(function(bits)
  assert(type(bits)=="number")
  return RM.lift( "AndUint_"..tostring(bits), types.tuple{types.Uint(bits),types.Uint(bits)}, types.Uint(bits), 0, function(sinp) return S.__and(S.index(sinp,0),S.index(sinp,1)) end )
end)

C.neg = memoize(function( bits, exp )
  assert(type(bits)=="number")
  if exp==nil then exp=0 end
  return RM.lift( "Neg_"..tostring(bits), types.Int(bits,exp), types.Int(bits,exp), 1, function(sinp) return S.neg(sinp) end )
end)

C.tokenCounter = memoize(function(A,str,X)
  err( types.isType(A), "C.tokenCounter: A must be type")
  err( types.isHandshake(A),"C.tokenCounter: A must be handshake")
  assert(X==nil)

  if str==nil then str="" end
  assert(type(str)=="string")

--  print("TC",str)
--  assert(false)
  
  local partial = RM.lift( J.sanitize("tokencounter_A"..tostring(A)).."_"..str, A, A, 1,
                           function(sinp) assert(false) end,
                           function() return CT.tokenCounter(A,str) end,
    "C.tokenCounter" )

  if terralib~=nil then
    partial.terraModule = CT.tokenCounter(A,str)
  end
  
  return partial
end)

------------
-- return A+B as a darkroom FN. A,B are types
-- returns something of type outputType
C.sum = memoize(function( A, B, outputType, async )
  err( types.isType(A), "C.sum: A must be type")
  err( types.isType(B), "C.sum: B must be type")
  err( types.isType(outputType), "C.sum: outputType must be type")

  err( A:isInt()==B:isInt() and A:isInt()==outputType:isInt(),"C.sum NYI: all types must have same signedness" )
  err( A.exp==B.exp and A.exp==outputType.exp,"C.sum NYI: all type must have same exponant")
  
  if async==nil then return C.sum(A,B,outputType,false) end

  err(type(async)=="boolean","C.sum: async must be boolean, but is: "..tostring(async))

  local delay

  if async then
    delay = 0
  else
    local tab = S.delayTable["+"]
    delay = math.floor(S.interp(tab,outputType:verilogBits())*S.delayScale)
  end

  local partial = RM.lift(
    J.sanitize("sum_"..tostring(A)..tostring(B)..tostring(outputType).."_async_"..tostring(async)), types.tuple {A,B}, outputType, delay,
    function(sinp)
      local sout = S.cast(S.index(sinp,0),outputType)+S.cast(S.index(sinp,1),outputType)
      if async then sout = sout:disablePipelining() end
      return sout
    end,
    function()
      return CT.sum(A,B,outputType,async)
    end,
    "C.sum")
  
  return partial
end)

------------
-- return A-B as a darkroom FN. A,B are types
-- returns something of type outputType
C.sub = memoize(function( A, B, outputType, async )
  err( types.isType(A), "C.sub: A must be type")
  err( types.isType(B), "C.sub: B must be type")
  err( types.isType(outputType), "C.sub: outputType must be type")

  if async==nil then return C.sub(A,B,outputType,false) end

  local delay
  if async then delay = 0 else delay = 1 end

  local partial = RM.lift( J.sanitize("sub_"..tostring(A)..tostring(B)..tostring(outputType).."_async_"..tostring(async)), types.tuple {A,B}, outputType, delay,
    function(sinp)
      local sout = S.cast(S.index(sinp,0),outputType)-S.cast(S.index(sinp,1),outputType)
      if async then sout = sout:disablePipelining() end
      return sout
    end,nil,
    "C.sub")

  return partial
end)

C.subConst = memoize(function( ty, value_orig, async, outputType )
  err(types.isType(ty),"subConst: first argument should be type, but is: ",ty)

  if async==nil then async=false end
  assert( type(async)=="boolean" )

  if outputType==nil then outputType = ty end
  assert( types.isType(outputType) )

  assert( ty.exp==outputType.exp )

  local value = Uniform(value_orig)
  err( value:isNumber(),"subConst expected numeric input")
  value = value * math.pow(2,math.max(-ty.exp,0))  -- rescale by exp, to be in right scale

  print("VALUE",value_orig,value)
  
  local instanceMap = value:getInstances()
  
  local plus100mod = RM.lift( J.sanitize("sub_"..tostring(ty).."_"..tostring(value)), ty, outputType , J.sel(async==true,0,1) ,
    function(plus100inp)
      local res = S.cast(plus100inp,outputType) - S.cast(value:toSystolic(ty),outputType)
      if async==true then res = res:disablePipelining() end
      return res
    end,
    function() return CT.subConsttfn( ty, value, outputType ) end, nil,nil, instanceMap )

  return plus100mod
end)

-----------------------------
C.rshiftConst = memoize(function(A,const)
  err( types.isType(A),"C.rshift: type should be rigel type")
  err( type(const)=="number" or const==nil,"C.rshift: const should be number or value")
  
  -- shift by a const
  J.err( A:isUint() or A:isInt(), "generators.Rshift: type should be int or uint, but is: "..tostring(A) )
  local mod = RM.lift(J.sanitize("generators_rshift_const"..tostring(const).."_"..tostring(A)), A,A,0,
                      function(inp) return S.rshift(inp,S.constant(const,A)) end)
  return mod
end)

-- rshift while keeping all bits is a noop! only type changes
C.rshiftEConst = memoize(function( A, const )
  J.err( A:isInt() or A:isUint(),"RshiftE only works on int or uint" )

  local outA = A:replaceVar("exp",A.exp-const)
  local res = RM.lift(J.sanitize("RshiftE_"..tostring(A).."_"..tostring(const)), A, outA, 0,
                                 function(inp) return S.rshiftE(inp,const) end)
  return res
end)

-----------------------------
C.rshift = memoize(function(A,B,X)
  err( types.isType(A),"C.rshift: type should be rigel type")
  err( types.isType(B),"C.rshift: type should be rigel type")
  assert(X==nil)

    -- shift by a const
  J.err( A:isUint() or A:isInt(), "generators.Rshift: type should be int or uint, but is: "..tostring(A) )
  J.err( B:isUint() or B:isInt(), "generators.Rshift: type should be int or uint, but is: "..tostring(A) )
  local mod = RM.lift(J.sanitize("generators_rshift_"..tostring(A).."_"..tostring(B)), types.Tuple{A,B},A,0,
                      function(inp) return S.rshift(S.index(inp,0),S.index(inp,1)) end)
  return mod
end)

-----------------------------
C.addMSBs = memoize(function(A,bits)
  err( types.isType(A),"C.addMSBs: type should be rigel type")
  err( type(bits)=="number","C.addMSBs: bits should be number or value")

  local otype
  if A:isUint() then
    otype = types.uint(A.precision+bits)
  elseif A:isInt() then
    otype = types.int(A.precision+bits)
  else
    J.err( A:isUint() or A:isInt(), "generators.addMSBs: type should be int or uint, but is: "..tostring(A) )
  end
  
  local mod = RM.lift(J.sanitize("generators_addMSBs_"..tostring(bits).."_"..tostring(A)), A,otype,0,
                      function(inp) return S.cast(inp,otype) end)
  return mod
end)

-----------------------------
C.removeMSBs = memoize(function(A,bits,X)
  err( types.isType(A),"C.removeMSBs: type should be rigel type")
  err( type(bits)=="number","C.removeMSBs: bits should be number or value")
  assert(X==nil)
  
  local otype
  if A:isUint() then
    J.err(A.precision>bits,"removeMSBs: can't remove all the bits! attempting to remove "..bits.." bits from "..tostring(A))
    otype = types.uint( A.precision-bits, A.exp )
  elseif A:isInt() then
    J.err(A.precision>bits,"removeMSBs: can't remove all the bits! attempting to remove "..bits.." bits from "..tostring(A))
    otype = types.int( A.precision-bits, A.exp )
  else
    J.err( A:isUint() or A:isInt(), "generators.removeMSBs: type should be int or uint, but is: "..tostring(A) )
  end
  
  local mod = RM.lift(J.sanitize("generators_removeMSBs_"..tostring(bits).."_"..tostring(A)), A,otype, 0,
                      function(inp) return S.cast(inp,otype) end,
                      function() return CT.removeMSBs(A,bits,otype) end )
  return mod
end)

-----------------------------
-- keepMagnitude: adjust the exp to keep magnitude of value the same
C.removeLSBs = memoize(function( A, bits, keepMagnitude, X )
  err( types.isType(A),"C.removeLSBs: type should be rigel type")
  err( type(bits)=="number","C.removeLSBs: bits should be number or value")
  if keepMagnitude==nil then keepMagnitude=false end
  assert( X==nil )
  
  local otype
  if A:isUint() then
    J.err(A.precision>bits,"removeLSBs: can't remove all the bits! attempting to remove "..bits.." bits from "..tostring(A))
    local exp = A.exp
    if keepMagnitude then exp=exp+bits end
    otype = types.uint( A.precision-bits, exp )
  elseif A:isInt() then
    J.err(A.precision>bits,"removeLSBs: can't remove all the bits! attempting to remove "..bits.." bits from "..tostring(A))
    local exp = A.exp
    if keepMagnitude then exp = exp+bits end
    otype = types.int( A.precision-bits, exp )
  else
    J.err( A:isUint() or A:isInt(), "generators.removeLSBs: type should be int or uint, but is: "..tostring(A) )
  end
  
  local mod = RM.lift(J.sanitize("generators_removeLSBs_"..tostring(bits).."_"..tostring(A)), A,otype,0,
                      function(inp) return S.cast(S.rshift(inp,S.constant(bits,A)),otype) end,
                      function() return CT.removeLSBs(A,bits,otype) end)
  return mod
end)

-----------------------------
C.select = memoize(function(ty, X)
  assert( X==nil )
  err(types.isType(ty), "C.select error: input must be type")
  local ITYPE = types.tuple{types.bool(),ty,ty}

  local selm = RM.lift( J.sanitize("C_select_"..tostring(ty)), ITYPE, ty, 0,
    function(sinp) return S.select(S.index(sinp,0), S.index(sinp,1), S.index(sinp,2)) end,nil,
    "C.select" )

  return selm
end)
-----------------------------
C.eq = memoize(function( ty, X )
  assert( X==nil )
  err(types.isType(ty), "C.eq error: input must be type")
  local ITYPE = types.tuple{ty,ty}

  local selm = RM.lift( J.sanitize("C_eq_"..tostring(ty)), ITYPE, types.bool(), 0,
    function(sinp) return S.eq(S.index(sinp,0), S.index(sinp,1)) end, nil,
    "C.eq" )

  return selm
end)

-----------------------------------------
C.NE = memoize(function(ty, X)
  assert( X==nil )
  err(types.isType(ty) and ty:isData(), "C.ne error: input must be data type")
  local ITYPE = types.tuple{ty,ty}

  local selm = RM.lift( J.sanitize("C_ne_"..tostring(ty)), ITYPE, types.bool(), 0,
    function(sinp) return S.__not(S.eq(S.index(sinp,0), S.index(sinp,1))) end, nil,
    "C.ne" )

  return selm
end)

------------------------------------
C.NEConst = memoize(function(ty,const)
  err(types.isType(ty) and ty:isData(), "C.ne error: input must be data type")
  err(ty:checkLuaValue(const),"C.neConst: lua value isn't what was expected")
  
  local selm = RM.lift( J.sanitize("C_ne_const_"..tostring(ty).."_value"..tostring(const)), ty, types.bool(), 0,
    function(sinp) return S.__not(S.eq(sinp, S.constant(const,ty))) end, nil,
    "C.NEConst" )

  return selm
end)

-----------------------------
C.readTap = memoize(function(global)
  local G = {}
  G[global]=1
  local out = RM.lift( "ReadTap_"..global.name, types.null(), global.type, 0,
    function(sinp) return S.readSideChannel(global.systolicValue) end, nil, "C.readTap",nil,G)
  return out
end)

-----------------------------
C.valueToTrigger = memoize(function(ty)
  err( R.isBasic(ty), "C.valueToTrigger: input type should be basic, but is: "..tostring(ty))
  return RM.lift( "ValueToTrigger_"..tostring(ty), ty, types.Trigger, 0,
    function(sinp) return S.trigger end, nil,"C.valueToTrigger")
end)

-----------------------------
C.triggerToConstant = memoize(function( ty, value )
  J.err( types.isType(ty), "C.triggerToConstant: type must be type")
  return RM.lift( "TriggerToConstant_"..tostring(ty).."_"..tostring(value), types.Trigger, ty, 0,
    function(sinp) return S.constant(value,ty) end, nil,"C.triggerToConstant")
end)

C.const = C.triggerToConstant
-----------------------------
-- take in 1 trigger, and write out N triggers (aka trigger upsample)
C.triggerUp = memoize(function(N_orig)
    --J.err(type(N)=="number","triggerUp: input must be number")
  local N = Uniform(N_orig)
  err( N:isNumber(),"triggerUp: input must be number")
  
  local inp = R.input(R.HandshakeTrigger)
  local val = RM.makeHandshake( RM.constSeq({0},types.uint(8),1,1,1), nil, true )(inp)
  val = RM.upsampleXSeq(types.uint(8),1,N)(val)
  val = RM.makeHandshake(C.valueToTrigger(types.array2d(types.uint(8),1)),nil,true)(val)
  return RM.lambda("TriggerUp_"..tostring(N), inp,val)
end)

-----------------------------
C.packTap = memoize(function(A,ty,global)
  return RM.lift( "PackTap_"..tostring(A).."_"..tostring(ty), A, types.tuple{A,ty}, 0,
    function(sinp) return S.tuple{sinp,S.readSideChannel(global.systolicValue)} end, nil,"C.packTap")
end)

-----------------------------
C.packTapBroad = memoize(function( A, ty, tap, N, X )
  assert(types.isType(A) and A:isData())
  assert(types.isType(ty) and ty:isData())
  assert(type(N)=="number")
  assert(R.isFunction(tap))
  assert(X==nil)
  
  local G = require "generators.core"
  return G.Function{"PackTap_"..tostring(A).."_"..tostring(ty),types.rv(types.Par(A)),SDF{1,1},function(i)
                    return R.concat{i,G.Broadcast{{N,1}}(RM.Storv(tap)(G.ValueToTrigger(i)))} end}
end)

-----------------------------
C.rcp = memoize(function(ty)
  err(types.isType(ty), "C.rcp error: input must be type")
  return f.parameter("finp",ty):rcp():toRigelModule("rcp_"..tostring(ty))
end)

-------------
-- {{idxType,vType},{idxType,vType}} -> {idxType,vType}
-- async: 0 cycle delay
C.argmin = memoize(function(idxType,vType, async, domax)
  local ATYPE = types.tuple {idxType,vType}
  local ITYPE = types.tuple{ATYPE,ATYPE}
  local sinp = S.parameter( "inp", ITYPE )

  local delay

  if async==true then
    delay = 0
  else
    delay = 0
  end

  local name = "argmin"
  if domax then name="argmax" end
  if async then name=name.."_async" end
  name = name.."_"..J.verilogSanitize(tostring(idxType))
  name = name.."_"..J.verilogSanitize(tostring(vType))

  local partial = RM.lift( J.sanitize(name), ITYPE, ATYPE, delay,
    function(sinp)
      local a0 = S.index(sinp,0)
      local a0v = S.index(a0,1)
      local a1 = S.index(sinp,1)
      local a1v = S.index(a1,1)
      local out
      if domax then
        out = S.select(S.ge(a0v,a1v),a0,a1)
      else
        out = S.select(S.le(a0v,a1v),a0,a1)
      end

      if async==true then
        out = out:disablePipelining()
      end
      return out
    end,
    function()
      return CT.argmin(ITYPE,ATYPE,domax)
    end,
    "C.argmin" )

  return partial
end)

------------
-- this returns a function from A[2]->A
-- return |A[0]-A[1]| as a darkroom FN.
-- The largest absolute difference possible is the max value of A - min value, so returning type A is always fine.
-- we fuse this with a cast to 'outputType' just for convenience.
C.absoluteDifference = memoize(function(A,outputType,X)
  err(types.isType(A), "C.absoluteDifference: A must be type")
  err(types.isType(outputType), "C.absoluteDifference: outputType must be type")
  err(X==nil, "C.absoluteDifference: too many arguments")

  local TY = types.array2d(A,2)

  local internalType, internalType_uint
  local internalType_terra

  if A==types.uint(8) then
    -- make sure this doesn't overflow when we add sign bit
    internalType = types.int(9)
    internalType_uint = types.uint(9)
    internalType_terra = int16 -- should yield equivilant output
  else
    assert(false)
  end

  local partial = RM.lift( J.sanitize("absoluteDifference_"..tostring(A).."_"..tostring(outputType)), TY, outputType, 2,
    function(sinp)
      local subabs = S.abs(S.cast(S.index(sinp,0),internalType)-S.cast(S.index(sinp,1),internalType))
      local out = S.cast(subabs, internalType_uint)
      local out = S.cast(out, outputType)
      return out
    end,
    function() return CT.absoluteDifference(A,outputType,internalType_terra) end,
    "C.absoluteDifference")

  return partial
end)

------------
-- returns a darkroom FN that casts type 'from' to type 'to'
-- performs [to](from >> shift)
C.shiftAndCast = memoize(function(from, to, shift)
  err( types.isType(from), "C.shiftAndCast: from type must be type")
  err( types.isType(to), "C.shiftAndCast: to type must be type")
  err( type(shift)=="number", "C.shiftAndCast: shift must be number")

  if shift >= 0 then
    local touint8 = RM.lift( J.sanitize("shiftAndCast_uint" .. from.precision .. "to_uint" .. to.precision.."_shift"..tostring(shift)), from, to, 0,
      function(touint8inp) return S.cast(S.rshift(touint8inp,S.constant(shift,from)), to) end,
      function() return CT.shiftAndCast(from,to,shift) end,
      "C.shiftAndCast")
    return touint8
  else
    local touint8 = RM.lift( J.sanitize("shiftAndCast_uint" .. from.precision .. "to_uint" .. to.precision.."_shift"..tostring(shift)), from, to, 0,
      function(touint8inp) return S.cast(S.lshift(touint8inp,S.constant(-shift,from)), to) end,
      function() return CT.shiftAndCast(from,to,shift) end,
      "C.shiftAndCast")
    return touint8
  end
end)

C.shiftAndCastSaturate = memoize(function(from, to, shift)
  err( types.isType(from), "C.shiftAndCastSaturate: from type must be type")
  err( types.isType(to), "C.shiftAndCastSaturate: to type must be type")
  err( type(shift)=="number", "C.shiftAndCastSaturate: shift must be number")

  local touint8 = RM.lift( J.sanitize("shiftAndCastSaturate_"..tostring(from).."_to_"..tostring(to).."_shift_"..tostring(shift)), from, to, 0,
    function(touint8inp)
      local OT = S.rshift(touint8inp,S.constant(shift,from))
      return S.select(S.gt(OT,S.constant(255,from)),S.constant(255,types.uint(8)), S.cast(OT,to))
    end,
    function() return CT.shiftAndCastSaturate(from,to,shift) end,
    "C.shiftAndCastSaturate")

  return touint8
end)

-------------
-- returns a function of type {A[ConvWidth,ConvWidth], A_const[ConvWidth,ConvWidth]}
-- that convolves the two arrays
C.convolveTaps = memoize(function( A, ConvWidth, shift )
  assert( types.isType(A) )
  assert( A:isData() )
  if shift==nil then shift=7 end

  local TAP_TYPE = types.array2d( A, ConvWidth, ConvWidth )
  local TAP_TYPE_CONST = TAP_TYPE

  local INP_TYPE = types.tuple{types.array2d( A, ConvWidth, ConvWidth ),TAP_TYPE_CONST}
  local inp = R.input( types.rv(types.Par(INP_TYPE)) )

  local packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth,ConvWidth,{A,A}), inp )
  local conv = R.apply( "partial", RM.map( C.multiply(A,A, types.uint(32)), ConvWidth, ConvWidth ), packed )
  local conv = R.apply( "sum", RM.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth, ConvWidth ), conv )
  local conv = R.apply( "touint8", C.shiftAndCast(types.uint(32),A,shift), conv )

  local convolve = RM.lambda( "convolveTaps", inp, conv )
  return convolve
end)

------------
-- returns a function from A[ConvWidth,ConvHeight]->A
C.convolveConstant = memoize(function( A, ConvWidth, ConvHeight, tab, shift, X )
  assert(type(ConvWidth)=="number")
  assert(type(ConvHeight)=="number")
  assert(type(tab)=="table")
  assert(type(shift)=="number")
  assert(X==nil)

  local inp = R.input( types.rv(types.Par(types.array2d( A, ConvWidth, ConvHeight ))) )
  local r = R.constant( "convkernel", tab, types.array2d( A, ConvWidth, ConvHeight) )

  local packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth,ConvHeight,{A,A}), R.concat("ptup", {inp,r}) )
  local conv = R.apply( "partial", RM.map( C.multiply(A,A,types.uint(32)), ConvWidth, ConvHeight ), packed )
  local conv = R.apply( "sum", RM.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth, ConvHeight ), conv )
  local conv = R.apply( "touint8", C.shiftAndCast( types.uint(32), A, shift ), conv )

  local convolve = RM.lambda( "convolveConstant_W"..tostring(ConvWidth).."_H"..tostring(ConvHeight), inp, conv )
  return convolve
end)

------------
-- returns a function from A[ConvWidth*T,ConvWidth]->A, with throughput T
C.convolveConstantTR = memoize(function( A, ConvWidth, ConvHeight, T, tab, shift, X )
  assert(type(shift)=="number")
  assert(type(T)=="number")
  assert(T>=1)
  assert(ConvWidth%T==0)
  assert(type(shift)=="number")
  assert(X==nil)

  local G = require "generators.core"
  
  local inp = R.input( types.rv(types.Par(types.array2d( A, ConvWidth/T, ConvHeight ))) )
  local r = R.apply( "convKernel", RM.constSeq( tab, A, ConvWidth, ConvHeight, T ), G.ValueToTrigger(inp) )

  local packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth/T,ConvHeight,{A,A}), R.concat("ptup", {inp,r}) )
  local conv = R.apply( "partial", RM.map( C.multiply(A,A,types.uint(32)), ConvWidth/T, ConvHeight ), packed )
  local conv = R.apply( "sum", RM.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth/T, ConvHeight ), conv )

  local convseq = RM.lambda( "convseq_T"..tostring(1/T), inp, conv )
------------------
  inp = R.input( types.rV(types.Par(types.array2d( A, ConvWidth/T, ConvHeight ))) )
  conv = R.apply( "convseqapply", RM.liftDecimate(RM.liftBasic(convseq)), inp)
  conv = R.apply( "sumseq", RM.RPassthrough(RM.liftDecimate(RM.reduceSeq( C.sum(types.uint(32),types.uint(32),types.uint(32),true), T ))), conv )
  conv = R.apply( "touint8", C.RVPassthrough(C.shiftAndCast( types.uint(32), A, shift )), conv )
  conv = R.apply( "arrayop", C.RVPassthrough(C.arrayop( types.uint(8), 1, 1)), conv)

  local convolve = RM.lambda( "convolve_tr_T"..tostring(T), inp, conv )

  return convolve
end)

------------
-- returns a function from A[2][Width,Width]->reduceType
-- 'reduceType' is the precision we do the sum
C.SAD = memoize(function( A, reduceType, Width, X )
  err( types.isType(A) and A:isData(),"SAD: type must be data type, but is: ", A)
  assert(X==nil)

  local inp = R.input( types.rv(types.Par(types.array2d( types.array2d(A,2) , Width, Width ))) )

  local conv = R.apply( "partial", RM.map( C.absoluteDifference(A,reduceType), Width, Width ), inp )
  local conv = R.apply( "sum", RM.reduce( C.sum(reduceType, reduceType, reduceType), Width, Width ), conv )

  local convolve = RM.lambda( J.sanitize("SAD_"..tostring(A).."_reduceType"..tostring(reduceType).."_Width"..tostring(Width)), inp, conv, nil, "C.SAD" )
  return convolve
end)


C.SADFixed = memoize(function( A, reduceType, Width, X )
  err( types.isType(A) and A:isData(),"SADFixed: type should be data type")

  local fixed = require "fixed"
  assert(X==nil)
  fixed.expectFixed(reduceType)
  assert(fixed.extractSigned(reduceType)==false)
  assert(fixed.extractExp(reduceType)==0)

  local inp = R.input( types.rv(types.Par(types.array2d( types.array2d(A,2) , Width, Width ))) )

  -------
  local ABS_inp = fixed.parameter("abs_inp", types.array2d(A,2))
  local ABS_l, ABS_r = ABS_inp:index(0):lift(0):toSigned(), ABS_inp:index(1):lift(0):toSigned()
  local ABS = (ABS_l-ABS_r):abs():pad(fixed.extractPrecision(reduceType),0)
  ------
  local SUM_inp = fixed.parameter("sum_inp", types.tuple{reduceType,reduceType})
  local SUM_l, SUM_r = SUM_inp:index(0), SUM_inp:index(1)
  local SUM = (SUM_l+SUM_r)

  SUM = SUM:truncate(fixed.extractPrecision(reduceType))
  ------

  local conv = R.apply( "partial", RM.map( ABS:toRigelModule("absoluteDiff"), Width, Width ), inp )
  local conv = R.apply( "sum", RM.reduce( SUM:toRigelModule("ABS_SUM"), Width, Width ), conv )

  local convolve = RM.lambda( "SAD", inp, conv, nil, "C.SADFixed" )
  return convolve
end)


C.SADFixed4 = memoize(function( A, reduceType, Width, X )
  local fixed = require "fixed"
  assert(X==nil)
  fixed.expectFixed(reduceType)
  assert(fixed.extractSigned(reduceType)==false)
  assert(fixed.extractExp(reduceType)==0)

  local inp = R.input( types.rv(types.Par(types.array2d( types.array2d(A,2) , Width, Width ))) )

  -------
  local ABS_inp = fixed.parameter("abs_inp", types.array2d(A,2))

  local ABSt = {}
  for i=1,4 do
    local ABS_l, ABS_r = ABS_inp:index(0):index(i-1):lift(0):toSigned(), ABS_inp:index(1):index(i-1):lift(0):toSigned()
    ABSt[i] = (ABS_l-ABS_r):abs()
  end

  local ABS = (ABSt[1]+ABSt[2])+(ABSt[3]+ABSt[4])
  ABS = ABS:pad(fixed.extractPrecision(reduceType),0)
  ------
  local SUM_inp = fixed.parameter("sum_inp", types.tuple{reduceType,reduceType})
  local SUM_l, SUM_r = SUM_inp:index(0), SUM_inp:index(1)
  local SUM = (SUM_l+SUM_r)

  SUM = SUM:truncate(fixed.extractPrecision(reduceType))

  ------

  local conv = R.apply( "partial", RM.map( ABS:toRigelModule("absoluteDiff"), Width, Width ), inp )
  local conv = R.apply( "sum", RM.reduce( SUM:toRigelModule("ABS_SUM"), Width, Width ), conv )

  local convolve = RM.lambda( "SAD", inp, conv )
  return convolve
end)

------------
-- takes a function f:A[StencilW,stencilH]->B
-- returns a function from A[T]->B[T]
C.stencilKernel = memoize(function( A, T, imageW, imageH, stencilW, stencilH, f)
  err( types.isType(A) and A:isData(),"stencilKernel: input should be data type")
    
  local BASE_TYPE = types.array2d( A, T )
  local inp = R.input( types.rv(types.Par(BASE_TYPE)) )

  local convLB = R.apply( "convLB", C.stencilLinebuffer( A, imageW, imageH, T, -stencilW+1, 0, -stencilH+1, 0 ), inp)
  local convstencils = R.apply( "convstencils", C.unpackStencil( A, stencilW, stencilH, T ), convLB )
  local convpipe = R.apply( "conv", RM.map( f, T ), convstencils )

  local convpipe = RM.lambda( "convpipe_"..f.name.."_W"..tostring(stencilW).."_H"..tostring(stencilH), inp, convpipe, nil,"C.stencilKernel" )
  return convpipe
end)

------------
-- takes a function f:{A[StencilW,StencilH],tapType}->B
-- returns a function that goes from A[T]->B[T]. Applies f using a linebuffer
C.stencilKernelTaps = memoize(function( A, T, tapType, imageW, imageH, stencilW, stencilH, f )
  assert(type(stencilW)=="number")
  assert(type(stencilH)=="number")

  local BASE_TYPE = types.array2d( A, T )
  local ITYPE = types.tuple{BASE_TYPE, tapType}
  local rawinp = R.input( types.rv(types.Par(ITYPE)) )

  local inp = R.apply("idx0",C.index(ITYPE,0),rawinp)
  local taps = R.apply("idx1",C.index(ITYPE,1),rawinp)

  local convLB = R.apply( "convLB", C.stencilLinebuffer( A, imageW, imageH, T, -stencilW+1, 0, -stencilH+1, 0 ), inp)
  local convstencils = R.apply( "convstencils", C.unpackStencil( A, stencilW, stencilH, T ) , convLB )

  local st_tap_inp = R.apply( "broad", C.broadcast(tapType,T), taps )
  st_tap_inp = R.concat("sttapinp",{convstencils,st_tap_inp})
  local ST_TYPE = types.array2d( A, stencilW, stencilH )
  st_tap_inp = R.apply("ST",C.SoAtoAoS(T,1,{ST_TYPE,tapType}),st_tap_inp)
  local convpipe = R.apply( "conv", RM.map( f, T ), st_tap_inp )

  local convpipe = RM.lambda( "convpipe", rawinp, convpipe )
  return convpipe
end)
-------------
-- f should be a _lua_ function that takes two arguments, (internalW,internalH), and returns the
-- inner function based on this W,H. We have to do this for alignment reasons.
-- f should return a handshake function
-- timingFifo: include a fifo to improve timing. true by default
C.padcrop = memoize(function( A, W, H, T, L, Right, B, Top, borderValue, f, timingFifo, X )
  err( type(W)=="number", "padcrop: W should be number")
  err( type(H)=="number", "padcrop: H should be number")
  err( type(T)=="number", "padcrop: T should be number")
  err( type(L)=="number", "padcrop: L should be number")
  err( type(Right)=="number", "padcrop: Right should be number")
  err( type(B)=="number", "padcrop: B should be number")
  err( type(Top)=="number", "padcrop: Top should be number")
  err( type(f)=="function", "padcrop: f should be lua function")

  err( X==nil, "padcrop: too many arguments" )
  err( timingFifo==nil or type(timingFifo)=="boolean", "padcrop: timingFIFO must be nil or boolean" )
  if timingFifo==nil then timingFifo=true end

  local RW_TYPE = types.array2d( A, T ) -- simulate axi bus
  local hsfninp = R.input( R.Handshake(RW_TYPE) )

  local internalL = J.upToNearest(T,L)
  local internalR = J.upToNearest(T,Right)

  local fifos = {}
  local statements = {}

  local internalW, internalH = W+internalL+internalR,H+B+Top

  local out = R.apply("pad", RM.liftHandshake(RM.padSeq(A, W, H, T, internalL, internalR, B, Top, borderValue)), hsfninp)

  if timingFifo then
    -- this FIFO is only for improving timing
    --table.insert( fifos, R.instantiateRegistered("f1",RM.fifo(types.array2d(A,T),128)) )
    --table.insert( statements, R.applyMethod("s3",fifos[#fifos],"store",out) )
    --out = R.applyMethod("l13",fifos[#fifos],"load")
    out = C.fifo(types.array2d(A,T),128)(out)
  end

  -----------------
  local internalFn = f(internalW, internalH)
  local out = R.apply("HH",internalFn, out)
  local padL = internalL-L
  local padR = internalR-Right
  local fnOutType = R.extractData(internalFn.outputType):arrayOver()
  local out = R.apply("crop",C.cropHelperSeq(fnOutType, internalW, internalH, T, padL+Right+L, padR, B+Top, 0), out)

  if timingFifo then
    -- this FIFO is only for improving timing
    --table.insert( fifos, R.instantiateRegistered("f2",RM.fifo(types.array2d(fnOutType,T),128)) )
    --table.insert( statements, R.applyMethod("s2",fifos[#fifos],"store",out) )
    --out = R.applyMethod("l2",fifos[#fifos],"load")
    out = C.fifo(types.array2d(fnOutType,T),128)(out)
  end
  -----------------

  table.insert(statements,1,out)

  local name = J.sanitize("padcrop_"..tostring(A).."L"..tostring(L).."_R"..tostring(Right).."_B"..tostring(B).."_T"..tostring(Top).."_W"..tostring(W).."_H"..tostring(H)..internalFn.name)

  local hsfn
  if timingFifo then
    hsfn = RM.lambda(name, hsfninp, R.statements(statements), fifos )
  else
    hsfn = RM.lambda(name, hsfninp, out)
  end

  return hsfn
end)

--------
function C.stencilKernelPadcrop(A,W,H,T,L,Right,B,Top,borderValue,f,timingFifo,X)
  local function finternal(IW,IH)
    return RM.makeHandshake(C.stencilKernel(A,T,IW,IH,Right+L+1,Top+B+1,f))
  end
  return C.padcrop(A,W,H,T,L,Right,B,Top,borderValue,finternal,timingFifo)
end

-- f should take (internalW,internalH) parameters
function C.stencilKernelPadcropUnpure(A,W,H,T,L,Right,B,Top,borderValue,f,timingFifo,X)
  local function finternal(IW,IH)
    return RM.makeHandshake(C.stencilKernel(A,T,IW,IH,Right+L+1,Top+B+1,f(IW,IH)))
  end
  return C.padcrop(A,W,H,T,L,Right,B,Top,borderValue,finternal,timingFifo)
end
-------------
local function invtable(bits)
  local out = {}
--[=[  local terra inv(a:uint32)
    if a==0 then
      return 0
    else
      var o = ([math.pow(2,17)]/([uint32](255)+a))-[uint32](256)
      if o>255 then return 255 end
      return o
    end
end]=]

  local function round(x) if (x%1>=0.5) then return math.ceil(x) else return math.floor(x) end end

  for i=0,math.pow(2,bits)-1 do
    local v = (math.pow(2,17)/(256+i)) - 256
    if v>255 then v = 255 end
    v = round(v)
    table.insert(out, v)
  end
  return out
end

function stripMSB(totalbits)
  local ITYPE = types.uint(totalbits)
  return RM.lift("stripMSB",ITYPE,types.uint(totalbits-1),0,
    function(sinp) return S.cast(sinp,types.uint(totalbits-1)) end,
    function() return CT.stripMSB(totalbits) end)
end

-- We want to calculate 1/x
--
-- we take the input x, and convert it to the floating point representation 1.ffffffff * 2^n
-- where f is the fractional component.
--
-- observe that (1/(1+fffff)) is between 0.5 and 1
--
-- in integer form, we have input 9 bit input in form (2^8+ffffffff) * 2^n
-- So we compute 2^9/((2^8+ffffffff)*2^n) = 2^(-n) * (2^9 / (2^8+ffffffff) )
--
-- put the (2^9 / (2^8+ffffffff) ) part in a lookup table. Since this is from 0.5 to 1,
-- we normalize to make good use of the bits in the LUT:
-- (2^17 / (2^8 + ffffffff)) - 256, which goes from 0 to 255
--
-- Plug this back in, and to find the real value, we have:
-- LUT(ffffffff) + 256, which has exponant n-17
C.lutinvert = J.memoize(function( ty, X )
  assert(X==nil)
  assert(types.isType(ty))
  err( ty:isData(), "lutinvert: input type must be data type, but is: ",ty)
  local fixed = require "fixed"
  --fixed.expectFixed(ty)
  local signed = false
  if ty:isInt() then signed = true end
  if fixed.isFixedType(ty) and fixed.extractSigned(ty) then signed=true end

  --------------------
  local ainp = fixed.parameter("ainp",ty)
  local a = ainp
  if fixed.isFixedType(ty)==false then
    a = ainp:lift()
  end
  a = a:hist("lutinvert_input")
  local a_sign
  if signed then
    a_sign = a:sign()
    a = a:abs()
  end
  local a_exp = a:msb(9)
  local a_float, a_min, a_max = a:float(a_exp,9)
  local aout
  if signed then
    aout = fixed.tuple({a_float,a_exp,a_sign})
  else
    aout = fixed.tuple({a_float,a_exp})
  end
  local afn = aout:toRigelModule("lutinvert_a")
  --------------------
  local lutbits = 8
  ------------
  local binp
  if signed then
    binp = fixed.parameter("binp", types.tuple{types.uint(8),types.int(8),types.bool()} )
  else
    binp = fixed.parameter("binp", types.tuple{types.uint(8),types.int(8)} )
  end
  local b_inv = binp:index(0)
  local b_exp = binp:index(1)
  local b = (b_inv:cast(types.uint(9))+fixed.plainconstant(256,types.uint(9))):liftFloat(-a_max-17,-a_min-17+8, b_exp:neg()-fixed.plainconstant(17, types.int(8)) )
  if signed then b = b:addSign(binp:index(2)) end
  b = b:hist("lutinvert_output")

  if fixed.isFixedType(ty)==false then
    -- convert back
    b = b:lowerWithExp()
  end
  local bfn = b:toRigelModule("lutinvert_b")
  ---------------

  local inp = R.input( types.rv(types.Par(ty)) )
  local aout = R.apply( "a", afn, inp )
  local aout_float = R.apply("aout_float", C.index(afn.outputType:extractData(),0), aout)
  local aout_exp = R.apply("aout_exp", C.index(afn.outputType:extractData(),1), aout)
  local aout_sign
  if signed then aout_sign = R.apply("aout_sign", C.index(afn.outputType:extractData(),2), aout) end

  local aout_float_lsbs = R.apply("aout_float_lsbs", stripMSB(9), aout_float)

  local inv = R.apply("inv", RM.lut(types.uint(lutbits), types.uint(8), invtable(lutbits)), aout_float_lsbs)
  local out = R.apply( "b", bfn, R.concat("binp",{inv,aout_exp,aout_sign}) )
  print("LUTINVOUT",out.type)
  local fn = RM.lambda( "lutinvert", inp, out )

  return fn, fn.outputType
end)

-------------
-- V: vector width of input. should be 0 or 1
C.stencilLinebufferPartialOffsetOverlap = memoize(function( A, w_orig, h, T, xmin, xmax, ymin, ymax, offset, overlap, V )
    --J.map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  err( type(T)=="number","stencilLinebufferPartialOffsetOverlap: T must be number, but is:", T)
  err( Uniform.isUniform(w_orig) or type(w_orig)=="number","stencilLinebufferPartialOffsetOverlap: w must be number, but is:", w_orig)
  local w = Uniform(w_orig):toNumber()
  err( type(h)=="number","stencilLinebufferPartialOffsetOverlap: h must be number, but is:", h)
  err( type(xmin)=="number","stencilLinebufferPartialOffsetOverlap: xmin must be number, but is:", xmin)
  err( type(xmax)=="number","stencilLinebufferPartialOffsetOverlap: xmax must be number, but is:", xmax)
  err( type(ymin)=="number","stencilLinebufferPartialOffsetOverlap: ymin must be number, but is:", ymin)
  err( type(ymax)=="number","stencilLinebufferPartialOffsetOverlap: ymax must be number, but is:", ymax)
  assert(T>=1);
  assert(w>0);
  assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  if V==nil then V=1 end
  assert( type(V)=="number" and V==0 or V==1 )
  
  local ST_W = -xmin+1
  local ssr_region = ST_W - offset - overlap
  local stride = ssr_region/T
  assert(stride==math.floor(stride))

  local LB = RM.makeHandshake(RM.linebuffer( A, w_orig, h, V, ymin ))
  local SSR = RM.liftHandshake(RM.waitOnInput(RM.SSRPartial( A, T, xmin, ymin, stride, true )))

  local inp = R.input( LB.inputType )
  local out = R.apply("LB", LB, inp)
  out = R.apply("SSR", SSR, out)
  out = R.apply("slice", RM.makeHandshake(C.slice(types.array2d(A,ST_W,-ymin+1), 0, stride+overlap-1, 0,-ymin)), out)

  return RM.lambda("stencilLinebufferPartialOverlap",inp,out)
end)

-- for 0-size FIFOs, we always drive upstream ready=false, to not stall upstream modules, but we may
-- not ACTUALLY be ready! Check that we only recieve an input when we expected one
local function errorUnexpectedInput( res, size, delay, name, fnName, topFnName )
  return [[  if( (monitorStarted || startMonitorTrigger) && ]]..res:vInputValid()..[[ && ]]..res:vOutputReady()..[[==1'b0 ) begin
  $display("CRITICAL ERROR: I ]]..topFnName..[[ ]]..name..[[ of ]]..fnName..[[ fifoSz:]]..size..[[ recieved an input when it didn't expect one! Which will get dropped on the ground in cycle %d inputValid:%d throttle:%d\n", cyclesSinceStart,]]..res:vInputValid()..[[,throttle);
  killNextCyc <= 1'b1;
end

if( (monitorStarted || startMonitorTrigger) && throttle==1'b1 && ]]..res:vOutputReady()..[[==1'b0 ) begin
  $display("CRITICAL ERROR: I ]]..topFnName..[[ ]]..name..[[ of ]]..fnName..[[ fifoSz:]]..size..[[ downstream ready was false when throttle was true! This will means tokens could get dropped cyclesSinceStart:%d\n",cyclesSinceStart);
  killAtEnd <= 1'b1;
end
]]
  
end

-- check that the input FIFO isn't full, when we need to write into it
local function errorInputFIFOClogged( res, size, delay, name, fnName, topFnName )
  return [[  if ( (monitorStarted || startMonitorTrigger) && ]]..res:vInputReady()..[[==1'b0 && throttle==1'b1 && errorInputClogged==2'd0) begin
    errorInputClogged <= 2'd1;
    errorInputCloggedReadyDownstream <= ]]..res:vOutputReady()..[[;
  end else if (errorInputClogged==2'd1 && ]]..res:vInputValid()..[[) begin
    $display("\n]]..J.sel(size>0,"* ","")..topFnName..[[ ]]..name..[[ of ]]..fnName..[[ fifoSz:]]..size..[[ input CLOGGED in cycle %d fifoSize:%d/]]..size..[[ delay:]]..delay..[[ throttle:%d dsReady:%d\n", cyclesSinceStart, fifoSize, throttle, errorInputCloggedReadyDownstream );
    errorInputClogged <= 2'd2;
    killAtEnd <= 1'b1;
  end
]]
end

--[===[
-- it seems like this error is redundant with the token check?
local function errorOutputClogged( res, size, delay, name, fnName, topFnName )
  return [[  if ( (monitorStarted || startMonitorTrigger) && ]]..res:vOutputReady()..[[==1'b0 && throttle==1'b1) begin
    errorOutputClogged <= 1'b1; 
    errorOutputCloggedReadyDownstream <= ]]..res:vOutputReady()..[[;
  end

  if (errorOutputClogged && (]]..res:vInputValid()..[[||]]..res:vOutputValid()..[[)) begin
    $display("\n]]..J.sel(size>0,"* ","")..topFnName..[[ ]]..name..[[ of ]]..fnName..[[ fifoSz:%0d/]]..size..[[ output CLOGGED in cycle:%0d throttle:%0d dsReady:%0d expected:%0d inputsSeen:%0d outputsSeen:%0d\n", fifoSize, cyclesSinceStart, throttle, errorOutputCloggedReadyDownstream, monitorReferenceCount, monitorInputCount, monitorOutputCount );
  end
]]
end
]===]

-- for the output side, with non-zero FIFO size, check that the FIFO is never drained when we try to read from it!
-- (that would mean fifo was too small, or delay was messed up)
local function errorFIFODrained( res, internalFIFO, size, delay, name, fnName, topFnName )
return [[
  if ( (monitorStarted || startMonitorTrigger) && ]]..internalFIFO:vOutputValid()..[[==1'b0 && throttle==1'b1 && errorOutputDrained==2'd0) begin
    errorOutputDrained <= 2'd1;
    errorOutputDrainedFifoSize <= fifoSize;
    errorOutputDrainedMonitorReferenceCount <= monitorReferenceCount;
    errorOutputDrainedMonitorOutputCount <= monitorOutputCount;
    errorOutputDrainedCyclesSinceStart <= cyclesSinceStart;
  end else if ( errorOutputDrained==2'd1 && (]]..res:vInputValid()..[[||]]..res:vOutputValid()..[[)) begin
    $display("\n* ]]..topFnName..[[ ]]..name..[[ of ]]..fnName..[[ fifoSz:]]..size..[[ OUTPUT FIFO Drained? (probably means delay is too small!) in cycle %d fifoSize:%d/]]..size..[[ delay:]]..delay..[[  expected:%d seen:%d\n",  errorOutputDrainedCyclesSinceStart,  errorOutputDrainedFifoSize,  errorOutputDrainedMonitorReferenceCount,  errorOutputDrainedMonitorOutputCount );
    killAtEnd <= 1'b1;
    errorOutputDrained <= 2'd2;
  end
]]
end

-- this is the main error function: we check that the externally-visible output/input rate is as expected
-- Note that this is error is defered until the next input/output seen, because at the end of time, we will obviously
-- not have the token count we expect! We also only display the error once, even if it keeps happening.
local function errorIncorrectCount( res, size, delay, internalDelay, rate, inputSide, name, fnName, topFnName )
  local D = Uniform(rate[1][2]):toNumber()
  
  return [[  if ( ]]..J.sel(inputSide,"monitorInputCount","monitorOutputCount")..[[ != monitorReferenceCount && errorQ==2'd0) begin
    errorQ <= 2'd1;
    errorMonitorOutputCount <= monitorOutputCount;
    errorMonitorInputCount <= monitorInputCount;
    errorMonitorReferenceCount <= monitorReferenceCount;
    errorCyclesSinceStart <= cyclesSinceStart;
    errorThrottle <= throttle;
    errorFifoSize <= fifoSize;
    errorMonitorNCount <= monitorNCount;
    errorReadyDownstream <= ]]..res:vOutputReady()..[[;
    errorValidDownstream <= ]]..res:vOutputValid()..[[;
  end else if (errorQ==2'd1 && ]]..J.sel(inputSide,res:vInputValid(),res:vOutputValid())..[[ ) begin
    // only display the first warning!
    $display("\n]]..J.sel(size>0,"* ","")..J.sel(inputSide,"I ","O ")..topFnName..[[ ]]..name..[[ of ]]..fnName..[[ didn't match expected number of ]]..J.sel(inputSide,"INPUTS","OUTPUTS")..[[! delay:]]..delay..[[ internalDelay:]]..internalDelay..[[ rate:]]..tostring(rate)..[[ fifoSz@error:%0d/]]..size..[[ expected:%0d outputCount:%0d inputCount:%0d validDownstream@error:%0d readyDownstream@error:%0d cyclesSinceStart@error:%0d cyclesSinceStartNow:%0d monitorNCount@error:%0d/]]..D..[[ throttle@error:%0d \n", errorFifoSize, errorMonitorReferenceCount, errorMonitorOutputCount, errorMonitorInputCount, errorValidDownstream, errorReadyDownstream, errorCyclesSinceStart, cyclesSinceStart,  errorMonitorNCount, errorThrottle );
    // this isn't a critical warning (just a perf warning), so wait until end
    killAtEnd <= 1'b1;
    errorQ <= 2'd2;
  end
]]

end

-------------
-- inputSide: if true, monitor the input interface. if false, monitor the output.
C.fifoWithMonitor = memoize(function( ty, size, delay, internalDelay, rate, inputSide, name, fnName, topFnName, X)
  err( ty==nil or types.isType(ty), "C.fifoWithMonitor: type must be a type" )
  err( ty==nil or ty:isData() or ty:isSchedule(), "C.fifoWithMonitor: type must be data type or schedule type, but is: "..tostring(ty) )
  err( type(size)=="number" and size>=0, "C.fifoWithMonitor: size must be number >= 0" )
  err( type(inputSide)=="boolean" )
  err( SDF.isSDF(rate), "rateMonitor: rate must be SDF rate, but is: ", rate)
  err( type(topFnName)=="string" )
  err( type(fnName)=="string" )
  err( type(name)=="string" )
  err( X==nil, "C.fifo: too many arguments" )

  local internalFIFOMod
  local internalFIFO
  local inst = {}

  if size>0 then
    internalFIFOMod = C.fifo( ty, size )
    internalFIFO = internalFIFOMod:instantiate("internalFIFO")
    inst[internalFIFO] = 1
  end

  local res = R.newFunction{ name=J.sanitize("FIFOWithMonitor_"..tostring(ty).."_size"..tostring(size).."_delay"..tostring(delay).."_rate"..tostring(rate).."_inputSide"..tostring(inputSide).."_"..name.."_"..fnName.."_"..topFnName), inputType = types.RV(ty), outputType=types.RV(ty), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=true, instanceMap=inst, delay=0, fifoed=true }

  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)
    s:addFunction(S.lambdaTab{name="startMonitorTrigger", input=S.parameter("startMonitorTrigger",types.bool()) })
                                             
    local N = Uniform(rate[1][1]):toNumber()
    local D = Uniform(rate[1][2]):toNumber()
    
    local verilog = "module "..res.name.." (input wire CLK, input wire reset"
    verilog = verilog..res:vHeaderInOut()..", input startMonitorTrigger);\n"
    verilog = verilog..[[parameter INSTANCE_NAME="INST";
]]
    verilog = verilog..res:vInstances()

    verilog = verilog..[[reg monitorStarted;
reg [31:0] cyclesSinceStart;
reg signed [31:0] monitorNCountReg;
wire signed [31:0] monitorNCount;
assign monitorNCount = $signed(monitorNCountReg) + (( startMonitorTrigger || monitorStarted )?(32'd]]..N..[[):(32'd0));
reg [31:0] monitorReferenceCountReg;
wire [31:0] monitorReferenceCount;
reg [31:0] monitorReferenceCountLast;
assign monitorReferenceCount = monitorReferenceCountReg + (($signed(monitorNCount)>32'sd0)?( (($signed(monitorNCount)>32'sd]]..D..[[)?(32'd2):(32'd1)) ):(32'd0));
reg [31:0] monitorOutputCountReg;
wire [31:0] monitorOutputCount;
reg [31:0] monitorInputCountReg;
wire [31:0] monitorInputCount;
assign monitorInputCount = monitorInputCountReg + (( ]]..res:vInputReady().." && "..res:vInputValid()..[[)?(32'd1):(32'd0));
assign monitorOutputCount = monitorOutputCountReg + (( ]]..res:vOutputReady().." && "..res:vOutputValid()..[[)?(32'd1):(32'd0));

reg [31:0] cyclesSinceValid = 32'd0;

// hack: we don't know whether an error is a real error, or the end of time.
// so: buffer errors, and don't print them until we see another input. If it's the last token, error is surpressed
reg [1:0] errorQ;
reg [31:0] errorCyclesSinceStart = 32'd0;
reg [31:0] errorMonitorReferenceCount = 32'd0;
reg [31:0] errorMonitorOutputCount = 32'd0;
reg [31:0] errorMonitorInputCount = 32'd0;
reg [31:0] errorFifoSize = 32'd0;
reg errorThrottle = 1'b0;
reg errorThrottleLast = 1'b0;
reg errorReadyDownstream = 1'b0;
reg errorValidDownstream = 1'b0;
reg signed [31:0] errorMonitorNCount;

reg [1:0] errorInputClogged;
reg errorInputCloggedReadyDownstream;

reg errorOutputClogged;
reg errorOutputCloggedReadyDownstream;

reg [1:0] errorOutputDrained;
reg [31:0] errorOutputDrainedFifoSize;
reg [31:0] errorOutputDrainedMonitorReferenceCount;
reg [31:0] errorOutputDrainedMonitorOutputCount;
reg [31:0] errorOutputDrainedCyclesSinceStart;

// hack: verilator won't write out all the errors if we do $finish, so delay calling $finish
reg killNextCyc =  1'b0;
reg killAtEnd =  1'b0;

reg [31:0] fifoSize;
reg [31:0] fifoMax;
reg anyValidsSeen = 1'b0;

// we always start ready
wire throttle;

// synopsys translate_off
integer f;

initial begin
  f = $fopen("out/TRACE_]]..fnName..J.sel(inputSide,"_I","_O")..[[.csv","w");
  $fwrite(f,"#]]..tostring(rate)..[[ size:]]..tostring(size)..[[ delay:]]..tostring(delay)..[[\n");
  $fwrite(f,"cyclesSinc,   RefCount,  mon]]..J.sel(inputSide,"I","O")..[[Cont,  mon]]..J.sel(inputSide,"O","I")..[[Cont,  fifoSize, throttle,  readyUS,    valIn,  readyDS, vaOut, error\n");
end

always @(posedge CLK) begin
  if (monitorStarted || startMonitorTrigger) begin
    $fwrite(f,"%d, %d,%d,%d,%d,        %d,        %d,        %d,        %d,      %d,        %d\n",cyclesSinceStart, monitorReferenceCount, monitor]]..J.sel(inputSide,"In","Out")..[[putCount, monitor]]..J.sel(inputSide,"Out","In")..[[putCount, fifoSize,throttle,]]..res:vInputReady()..","..res:vInputValid()..","..res:vOutputReady()..","..res:vOutputValid()..","..J.sel(inputSide,"monitorReferenceCount!=monitorInputCount","monitorReferenceCount!=monitorOutputCount")..[[);
  end
end
// synopsys translate_on

]]

    if rigel.THROTTLE_FIFOS==false then
      verilog = verilog.."assign throttle = 1'b1;\n"
    else
      if inputSide then
        verilog = verilog.."assign throttle = (monitorReferenceCount!=monitorReferenceCountLast)  || monitorReferenceCount==32'd0;\n"
      else
        verilog = verilog.."assign throttle = monitorReferenceCount!=monitorReferenceCountLast;\n"
      end
    end

    -- the ready bit calculation is tricky! we need to drive the upstream valid to true, always!
    -- b/c there may be a 0-fifo module upstream, and we don't want to choke it out (it may need to make progress even when
    -- it doesn't produce any tokens). So, we basicaly always drive upstream ready true.
    -- BUT: we need to then check later that we didn't accept a token we didn't expcect!! (IE: downstream ready is actually FALSE!
    -- which would mean we drop a token). So drive upstrem ready to true, but check that we only get tokens when we expect them.
    if size==0 then
      if inputSide then
        verilog = verilog.."assign "..res:vInputReady().." = 1'b1;\n"
      else
        verilog = verilog.."assign "..res:vInputReady().." = "..res:vOutputReady()..";\n"
      end
      verilog = verilog.."assign "..res:vOutput().." = "..res:vInput()..";\n"
    else
      if inputSide then
        verilog = verilog.."assign "..internalFIFO:vOutputReady().." = "..res:vOutputReady()..";\n"
        verilog = verilog.."assign "..res:vInputReady().." = "..internalFIFO:vInputReady()..";\n" -- SHOULD ALWAYS BE TRUE! If FIFO is correct size
        verilog = verilog.."assign "..res:vOutput().." = "..internalFIFO:vOutput()..";\n"
        if ty~=types.Trigger then
          verilog = verilog.."assign "..internalFIFO:vInputData().." = "..res:vInputData()..";\n"
        end
        verilog = verilog.."assign "..internalFIFO:vInputValid().." = "..res:vInputValid()..";\n"
      else
        -- output side: only dispense tokens at expected rate (throtte=true)
        verilog = verilog.."assign "..internalFIFO:vOutputReady().." = "..res:vOutputReady().." && throttle;\n"
        verilog = verilog.."assign "..res:vInputReady().." = "..internalFIFO:vInputReady()..";\n"
        if ty~=types.Trigger then
          verilog = verilog.."assign "..res:vOutputData().." = "..internalFIFO:vOutputData()..";\n"
          verilog = verilog.."assign "..internalFIFO:vInputData().." = "..res:vInputData()..";\n"
        end
        verilog = verilog.."assign "..res:vOutputValid().." = "..internalFIFO:vOutputValid().." && throttle;\n"
        verilog = verilog.."assign "..internalFIFO:vInputValid().." = "..res:vInputValid()..";\n"
      end
    end
    
    verilog = verilog..[[
always @(posedge CLK) begin
  if (startMonitorTrigger) begin 
    monitorStarted <= 1'b1; 
  end

//   $display("]]..J.sel(inputSide,"I","O")..[[ FIFO cyclesSinceStart:%0d MonitorReferenceCount:%0d monitor]]..J.sel(inputSide,"Input","Output")..[[Count:%0d MonitorNCount:%0d/]]..D..[[ throttle:%0d startMonitorTrigger:%0d fifoSz:%0d/]]..size..[[ iv:%0d ir:%0d ov:%0d or:%0d\n",cyclesSinceStart, monitorReferenceCount, monitor]]..J.sel(inputSide,"Input","Output")..[[Count, monitorNCount, throttle, startMonitorTrigger, fifoSize, ]]..res:vInputValid()..","..res:vInputReady()..","..res:vOutputValid()..","..res:vOutputReady()..[[ );

if (]]..res:vInputValid()..[[ && ]]..res:vInputReady()..[[) begin
  monitorInputCountReg <= monitorInputCountReg+32'd1;
end

if (]]..res:vOutputValid()..[[ && ]]..res:vOutputReady()..[[) begin
  monitorOutputCountReg <= monitorOutputCountReg+32'd1;
end

  if (monitorStarted || startMonitorTrigger) begin
    if (monitorNCount>=32'sd]]..tostring(D)..[[ ) begin
      monitorReferenceCountReg <= monitorReferenceCountReg + 32'd1;
      monitorNCountReg <= $signed(monitorNCount)-32'sd]]..tostring(D)..[[;
    end else begin
      monitorNCountReg <= monitorNCount;
    end
  end

  monitorReferenceCountLast <= monitorReferenceCount;
]]

    if inputSide then
      if size>0 then
        verilog = verilog..errorInputFIFOClogged( res, size, delay, name, fnName, topFnName )
      else
        verilog = verilog..errorUnexpectedInput( res, size, delay, name, fnName, topFnName )
      end
    else
--  verilog = verilog..errorOutputClogged( res, size, delay, name, fnName, topFnName )

      if size>0 then
        verilog = verilog.. errorFIFODrained( res, internalFIFO, size, delay, name, fnName, topFnName )
      end
    end

verilog = verilog.. errorIncorrectCount( res, size, delay, internalDelay, rate, inputSide, name, fnName, topFnName )

verilog = verilog..[[

  if( reset ) begin
    monitorStarted <= 1'b0;
    cyclesSinceStart <= 32'd0;
    monitorNCountReg <= -32'sd]]..tostring(N*math.max(delay,0))..[[;
    monitorReferenceCountReg <= 32'd0;
    monitorOutputCountReg <= 32'd0;
    monitorInputCountReg <= 32'd0;
    cyclesSinceValid <= 32'd0;
    errorQ <= 2'd0;
    errorInputClogged <= 2'd0;
    errorOutputClogged <= 1'b0;
    errorOutputDrained <= 2'd0;
    fifoSize <= 32'd0;
    fifoMax <= 32'd0;
// synopsys translate_off
    if( killAtEnd ) begin $finish(); end
// synopsys translate_on
  end else begin
    if( monitorStarted || startMonitorTrigger ) begin
      cyclesSinceStart <= cyclesSinceStart+32'd1;
    end
  end

// synopsys translate_off
  if( killNextCyc ) begin $finish(); end
// synopsys translate_on

  if (]]..res:vInputValid()..[[) begin
    cyclesSinceValid <= 32'd0;
  end else begin
    cyclesSinceValid <= cyclesSinceValid + 32'd1;
  end

]]
if inputSide and delay>0 and false then
  verilog = verilog..[[  
// synopsys translate_off
  if (monitor_started && ]]..res:vInputReady()..[[==1'b0 && cyclesSinceStart>=]]..delay..[[) begin
    $display("]]..topFnName..[[ ]]..name..[[ of ]]..fnName..[[ input CLOGGED in cycle %d",cyclesSinceStart);
    $finish();
  end
// synopsys translate_on
]]
end



verilog = verilog..[[

  if( ]]..res:vInputReady().." && "..res:vInputValid().." && ("..res:vOutputReady().."==1'b0 || "..res:vOutputValid()..[[==1'b0) ) begin
    fifoSize <= fifoSize + 32'd1;
  end else if ( ]]..res:vOutputReady().." && "..res:vOutputValid().." && ("..res:vInputReady().."==1'b0 || "..res:vInputValid()..[[==1'b0) ) begin
    fifoSize <= fifoSize - 32'd1;
  end else if ( ]]..res:vOutputReady().." && "..res:vOutputValid().." && "..res:vInputReady().." && "..res:vInputValid()..[[ ) begin
  end else if ( (]]..res:vOutputReady().."==1'b0 || "..res:vOutputValid().."==1'b0) && ("..res:vInputReady().."==1'b0 || "..res:vInputValid()..[[==1'b0) ) begin
  end else begin
    $display("FIFO INTERNAL ERROR! %d %d %d %d \n",]]..res:vInputValid()..","..res:vInputReady()..","..res:vOutputValid()..","..res:vOutputReady()..[[);
  end

  if( fifoSize>fifoMax ) begin 
    fifoMax<=fifoSize; 
  end

  if( reset==1'b0 && ]]..res:vInputValid()..[[ && ]]..res:vInputReady()..[[ ) begin anyValidsSeen<=1'b1; end
]]
if size>10 then
  verilog = verilog..[[
  if( reset && anyValidsSeen ) begin
    if( fifoMax<]]..math.floor(size*0.9)..[[ ) begin
      $display("\n]]..topFnName..[[ ]]..name..[[ of ]]..fnName..[[ FIFO way too big! Max:%d/]]..size..[[\n",fifoMax);
    end
  end
]]
end

verilog = verilog..[[
end  // always @ (CLK)
]]

    verilog = verilog.."endmodule\n\n"
    s:verilog(verilog)
    return s
  end


  function res.makeTerra()
    if size==0 then
      local mod = RM.makeHandshake(C.identity(ty))
      return mod.terraModule
    else
      return internalFIFOMod.terraModule
    end
  end
  
  return res
end)

-------------
-- VRLoad: if true, make the load function be HandshakeVR
-- includeSizeFn: should module have a size fn?
C.fifo = memoize(function( ty, size, nostall, csimOnly, VRLoad, includeSizeFn, name, X)
  err( ty==nil or types.isType(ty), "C.fifo: type must be a type" )
  err( ty==nil or ty:isData() or ty:isSchedule(), "C.fifo: type must be data type or schedule type, but is: "..tostring(ty) )
  err( type(size)=="number" and size>0, "C.fifo: size must be number > 0" )
  err( nostall==nil or type(nostall)=="boolean", "C.fifo: nostall must be boolean")
  err( csimOnly==nil or type(csimOnly)=="boolean", "C.fifo: csimOnly must be boolean")
  err( VRLoad==nil or type(VRLoad)=="boolean","C.fifo: VRLoad should be boolean")
  err( X==nil, "C.fifo: too many arguments" )
  --err( ty~=types.null(), "C.fifo: NYI - FIFO of 0 bit type" )

  if includeSizeFn==nil then includeSizeFn=false end
  
  local inp, regs
  if ty==nil or ty:extractData():verilogBits()==0 then
    if ty==nil then
      inp = R.input(types.HandshakeTrigger)
    else
      inp = R.input(types.RV(ty))
    end
    
    regs = {R.instantiate("f1",RM.triggerFIFO(ty))}
  else
    inp = R.input(R.Handshake(ty))
    local FIFOMod = RM.fifo( ty, size, nostall, nil, nil, nil, csimOnly, VRLoad, nil, nil, nil, name )
    regs = {R.instantiate("f1",FIFOMod)}
  end
  
  local st = R.applyMethod("s1",regs[1],"store",inp)
  local ld = R.applyMethod("l1",regs[1],"load")

  local bts = Uniform(ty:lower():verilogBits()):toNumber()
  local KBs = math.floor((size*bts)/(8*1024))
  local res = RM.lambda("C_FIFO_KB"..tostring(KBs).."_size_"..tostring(size).."_bits"..tostring(bts).."_ty"..tostring(ty).."_nostall"..tostring(nostall).."_VR"..tostring(VRLoad).."_SZFN"..tostring(includeSizeFn).."_CSIMONLY"..tostring(csimOnly).."_DBGNAME"..tostring(name), inp, R.statements{ld,st}, regs, "C.fifo", {size=size} )
  res.fifoed = true
  
  return res
end)

-------------
-- FIFO with loop support
function C.fifoLoop(fifos,statements,A,inp,size,name, csimOnly, X)
  assert(type(name)=="string")
  assert(X==nil)

  table.insert( fifos, R.instantiateRegistered(name, RM.fifo(A,size,nil,nil,nil,nil,csimOnly)) )
  table.insert( statements, R.applyMethod("s"..tostring(#fifos),fifos[#fifos],"store",inp) )
  return R.applyMethod("l"..tostring(#fifos),fifos[#fifos],"load")
end
-------------

-- HACK: this should really be in this file, but it needs to be in the other file to satisfy dependencies in old code
C.compose = RM.compose
C.SoAtoAoS = RM.SoAtoAoS

-- takes {Handshake(a[W,H]), Handshake(b[W,H]),...} to Handshake( {a,b}[W,H] )
-- typelist should be a table of data types
C.SoAtoAoSHandshake = memoize(function( W, H, typelist, X )
  assert(X==nil)
  
  local f = modules.SoAtoAoS(W,H,typelist)
  f = modules.makeHandshake(f)

  return C.compose( J.sanitize("SoAtoAoSHandshake_W"..tostring(W).."_H"..tostring(H).."_"..tostring(typelist)), f, modules.packTuple( J.map(typelist, function(t) return types.RV(types.Par(types.array2d(t,W,H))) end) ) )
end)

-- Takes A[W,H] to A[W,H], but with a border around the edges determined by L,R,B,T
function C.border(A,W,H,L,R,B,T,value)
  J.map({W,H,L,R,T,B,value},function(n) assert(type(n)=="number") end)
  local res = {kind="border",generator="C.border",L=L,R=R,T=T,B=B,value=value}
  res.inputType = types.array2d(A,W,H)
  res.outputType = res.inputType
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
  res.delay = 0

  if terralib~=nil then res.terraModule = CT.border(res,A,W,H,L,R,B,T,value) end
  return rigel.newFunction(res)
end


-- takes basic->basic to RV->RV
function C.RVPassthrough(f)
  return modules.RPassthrough(modules.liftDecimate(modules.liftBasic(f)))
end

-- fully parallel up/down scale
-- if scaleX,Y > 1 then this is upsample
-- if scaleX,Y < 1 then this is downsample
C.scale = memoize(function( A, w, h, scaleX, scaleY )
  assert(types.isType(A))
  assert(type(w)=="number")
  assert(type(h)=="number")
  assert(type(scaleX)=="number")
  assert(type(scaleY)=="number")

  local res = { kind="scale", scaleX=scaleX, scaleY=scaleY}
  res.inputType = types.array2d( A, w, h )
  res.outputType = types.array2d( A, w*scaleX, h*scaleY )
  res.delay = 0

  if terralib~=nil then res.terraModule = CT.scale(res, A, w, h, scaleX, scaleY ) end

  return rigel.newFunction(res)
end)


-- V -> RV
C.downsampleSeq = memoize(function( A, W_orig, H_orig, T, scaleX, scaleY, framed, X )
  err( types.isType(A) and A:isData(), "C.downsampleSeq: A must be data type")

  err( type(T)=="number", "C.downsampleSeq: T must be number")
  err( T>0, "C.downsampleSeq: T must be >0")
  err( type(scaleX)=="number", "C.downsampleSeq: scaleX must be number")
  err( type(scaleY)=="number", "C.downsampleSeq: scaleY must be number")
  err( scaleX>=1, "C.downsampleSeq: scaleX must be >=1")
  err( scaleY>=1, "C.downsampleSeq: scaleY must be >=1")
  err( X==nil, "C.downsampleSeq: too many arguments" )

  err( (Uniform(W_orig)%Uniform(scaleX)):eq(0):assertAlwaysTrue(),"C.downsampleSeq: NYI - scaleX does not divide W")
  err( (Uniform(H_orig)%Uniform(scaleY)):eq(0):assertAlwaysTrue(),"C.downsampleSeq: NYI - scaleY does not divide H")
  
  if framed==nil then framed=false end
  err( type(framed)=="boolean", "C.donwsampleSeq: framed must be boolean" )
    
  if scaleX==1 and scaleY==1 then
    return C.identity(A)
  end

  local inp = rigel.input( types.RV(types.Par(types.array2d(A,T))) )
  local out = inp
  if scaleY>1 then
    out = rigel.apply("downsampleSeq_Y", modules.liftHandshake(modules.liftDecimate(modules.downsampleYSeq( A, W_orig, H_orig, T, scaleY ))), out)
  end
  if scaleX>1 then
    local mod = modules.liftHandshake(modules.liftDecimate(modules.downsampleXSeq( A, W_orig, H_orig, T, scaleX )))

    out = rigel.apply("downsampleSeq_X", mod, out)
    local downsampleT = math.max(T/scaleX,1)
    if downsampleT<T then
      -- technically, we shouldn't do this without lifting to a handshake - but we know this can never stall, so it's ok
      out = rigel.apply("downsampleSeq_incrate", modules.liftHandshake(modules.changeRate(A,1,downsampleT,T)), out )
    elseif downsampleT>T then
      assert(false)
    end
  end

  local res = modules.lambda( J.sanitize("downsampleSeq_"..tostring(A).."_W"..tostring(W_orig).."_H"..tostring(H_orig).."_T"..tostring(T).."_scaleX"..tostring(scaleX).."_scaleY"..tostring(scaleY).."_framed"..tostring(framed)), inp, out,nil,"C.downsampleSeq")
  
  if framed then
    print("FRAMED",A,T,res.inputType,res.outputType)
    local W,H = Uniform(W_orig):toNumber(), Uniform(H_orig):toNumber()
    local itype = types.RV(types.Array2d(A,W_orig,H_orig,T,1))
    local otype = types.RV(types.Array2d(A,math.ceil(W/scaleX),math.ceil(H/scaleY),T,1 ))

    err( itype:lower()==res.inputType:lower(), "internal error, downsampleSeq framed. Module input type:",res.inputType, " lowered: ",res.inputType:lower()," framed type:",itype, " lowered:",itype:lower() )
    err( otype:lower()==res.outputType:lower() )
    
    res.inputType = itype
    res.outputType = otype
  end

  return res
end)


-- this is always Handshake
-- always has type A[T]->A[T]
C.upsampleSeq = memoize(function( A, W, H, T, scaleX, scaleY, X )
  err( types.isType(A), "C.upsampleSeq: A must be type")
  err( type(W)=="number", "C.upsampleSeq: W must be number")
  err( type(H)=="number", "C.upsampleSeq: H must be number")
  err( type(T)=="number", "C.upsampleSeq: T must be number")
  err( type(scaleX)=="number", "C.upsampleSeq: scaleX must be number")
  err( type(scaleY)=="number", "C.upsampleSeq: scaleY must be number")
  err( scaleX>=1, "C.upsampleSeq: scaleX must be >=1")
  err( scaleY>=1, "C.upsampleSeq: scaleY must be >=1")
  err( X==nil, "C.upsampleSeq: too many arguments" )

  if scaleX==1 and scaleY==1 then
    return C.identity(types.array2d(A,T))
  end

  local inner
  if scaleY>1 and scaleX==1 then
    inner = modules.liftHandshake(modules.upsampleYSeq( A, W, H, T, scaleY ))
  elseif scaleX>1 and scaleY==1 then
    inner = modules.upsampleXSeq( A, T, scaleX )
  else
    local f = modules.upsampleXSeq( A, T, scaleX )
    inner = C.compose( J.sanitize("upsampleSeq_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_scaleX"..tostring(scaleX).."_scaleY"..tostring(scaleY)), f, modules.liftHandshake(modules.upsampleYSeq( A, W, H, T, scaleY )),"C.upsampleSeq")
  end

    return inner
end)


-- takes A to A[T] by duplicating the input
C.broadcast = memoize(function( A, W, H, X )
  err( types.isType(A), "C.broadcast: A must be type A")
  err( types.isBasic(A), "C.broadcast: type should be basic, but is: "..tostring(A))
  err( type(W)=="number", "broadcast: W should be number, but is: ",W)
  if H==nil then return C.broadcast(A,W,1) end
  err( type(H)=="number", "broadcast: H should be number, but is: ",H)
  assert(X==nil)
  
  local OT = types.array2d(A, W, H)

  return modules.lift( J.sanitize("Broadcast_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H)),A,OT,0,
    function(sinp) return S.cast(S.tuple(J.broadcast(sinp,W*H)),OT) end,
    function() return CT.broadcast(A,W,H,OT) end,
    "C.broadcast")
end)
C.arrayop=C.broadcast

-- broadcast to a suple
C.broadcastTuple = memoize(function( A, N, X )
  err( types.isType(A), "C.broadcast: A must be type A")
  err( A:isSchedule(), "C.broadcast: type should be basic, but is: "..tostring(A))
  err( type(N)=="number", "broadcast: N should be number, but is: ",N)
  assert(X==nil)
  
  local OT = types.tuple(J.broadcast(A,N))

  local res = modules.lift( J.sanitize("Broadcast_"..tostring(A).."_N"..tostring(N)), A:lower(), OT:lower(), 0,
    function(sinp) return S.tuple(J.broadcast(sinp,N)) end,
    function() return CT.broadcastTuple(A,OT,N) end,
    "C.broadcastTuple")

  --print( res.inputType, types.rv(A), types.rv(A):lower() )
  assert( res.inputType:lower()==types.rv(A):lower() )
  assert( res.outputType:lower()==types.rv(OT):lower() )

  res.inputType = types.rv(A)
  res.outputType = types.rv(OT)
  
  return res
end)

-- extractStencils : A[w,h] -> A[(xmax-xmin+1)*(ymax-ymin+1)][w,h]
-- min, max ranges are inclusive
C.stencil = memoize(function( A, w, h, xmin, xmax, ymin, ymax )
  assert( type(xmin)=="number" )
  assert( type(xmax)=="number" )
  assert( xmax>=xmin )
  assert( type(ymin)=="number" )
  assert( type(ymax)=="number" )
  assert( ymax>=ymin )

  rigel.expectBasic(A)
  if A:isArray() then error("Input to extract stencils must not be array") end

  local res = {kind="stencil", type=A, w=w, h=h, xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax, generator="C.stencil" }
  res.delay=0
  res.inputType = types.array2d(A,w,h)
  res.outputType = types.array2d(types.array2d(A,xmax-xmin+1,ymax-ymin+1),w,h)
  res.sdfInput, res.sdfOutput = SDF{1,1}, SDF{1,1}
  res.name = J.sanitize("Stencil_"..tostring(A).."_w"..tostring(w).."_h"..tostring(h).."_xmin"..tostring(xmin).."_xmax"..tostring(xmax).."_ymin"..tostring(ymin).."_ymax"..tostring(ymax))
  res.stateful=false

  if terralib~=nil then res.terraModule = CT.stencil(res, A, w, h, xmin, xmax, ymin, ymax ) end

  return rigel.newFunction(res)
end)

-- this applies a border around the image. Takes A[W,H] to A[W,H], but with a border. Sequentialized to throughput T.
C.borderSeq = memoize(function( A, W, H, T, L, R, B, Top, Value, X )
  err( types.isType(A), "borderSeq: type must be type")
  J.map({W=W or "W",H = H or "H",T = T or "T",L = L or "L",R=R or "R",B = B or "B",Top = Top or "Top",Value = Value or "Value"},function(n,k) err(type(n)=="number","borderSeq: "..k.." must be number") end)
  err( X==nil, "borderSeq: too many arguments")

  local inpType = types.tuple{types.tuple{types.uint(16),types.uint(16)},A}

  local modname = "BorderSeq_"..J.verilogSanitize(tostring(A)).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_L"..tostring(L).."_R"..tostring(R).."_B"..tostring(B).."_Top"..tostring(Top).."_Value"..tostring(Value)

  local f = modules.lift( modname, inpType, A, 0,
    function(inp)
      local inpx, inpy = S.index(S.index(inp,0),0), S.index(S.index(inp,0),1)

      local lcheck = S.constant(false,types.bool())
      if L~=0 then lcheck = S.lt(inpx,S.constant(L,types.uint(16))) end -- verilator lint workaround

      local horizontal = S.__or(lcheck,S.ge(inpx,S.constant(W-R,types.uint(16))))

      local bcheck = S.constant(false,types.bool())
      if B~=0 then bcheck = S.lt(inpy,S.constant(B,types.uint(16))) end -- verilator lint workaround

      local vert = S.__or(bcheck,S.ge(inpy,S.constant(H-Top,types.uint(16))))
      local outside = S.__or(horizontal,vert)
      return S.select(outside,S.constant(Value,A), S.index(inp,1) )
    end,
    function() return CT.borderSeq( A, W, H, T, L, R, B, Top, Value, inpType ) end)

  return modules.liftXYSeqPointwise( modname, "C.borderSeq", f, W, H, T )
end)

-- This is the same as CropSeq, but lets you have L,R not be T-aligned
-- All it does is throws in a shift register to alter the horizontal phase
C.cropHelperSeq = memoize(function( A, W_orig, H, T, L, R, B, Top, framed, X )
  err(X==nil, "cropHelperSeq, too many arguments")
  err(type(T)=="number","T must be number")
  local W = Uniform(W_orig):toNumber()
  err( type(H)=="number", "H must be number")
  err( type(L)=="number", "L must be number")
  err( type(R)=="number", "R must be number")
  err( type(B)=="number", "B must be number")
  err( type(Top)=="number", "Top must be number")
  
  if T==0 or (L%T==0 and R%T==0) then return modules.liftHandshake(modules.liftDecimate(modules.cropSeq( A, W_orig, H, T, L, R, B, Top, framed ))) end
  if framed==nil then framed=false end
  
  err( T==0 or (W-L-R)%T==0, "cropSeqHelper, (W-L-R)%T~=0, W="..tostring(W)..", L="..tostring(L)..", R="..tostring(R)..", T="..tostring(T))

  local RResidual = R%T
  local inp = rigel.input( types.RV(types.array2d( A, T )) )
  local out = rigel.apply( "SSR", modules.makeHandshake(modules.SSR( A, T, -RResidual, 0 )), inp)
  out = rigel.apply( "slice", modules.makeHandshake(C.slice( types.array2d(A,T+RResidual), 0, T-1, 0, 0)), out)
  out = rigel.apply( "crop", modules.liftHandshake(modules.liftDecimate(modules.cropSeq(A,W,H,T,L+RResidual,R-RResidual,B,Top))), out )

  local res = modules.lambda( J.sanitize("cropHelperSeq_"..tostring(A).."_W"..tostring(W_orig).."_H"..H.."_T"..T.."_L"..L.."_R"..R.."_B"..B.."_Top"..Top.."_framed"..tostring(framed)), inp, out )

  local niType, noType
  if framed then
    if T==0 then
      niType = types.RV(types.Seq(types.Par(res.inputType:extractData()),W_orig,H))
      noType = types.RV(types.Seq(types.Par(res.outputType:extractData()),W_orig-L-R,H-B-Top))
    else
      niType = types.RV(types.ParSeq(res.inputType:extractData(),W_orig,H))
      noType = types.RV(types.ParSeq(res.outputType:extractData(),W_orig-L-R,H-B-Top))
    end

    assert(res.inputType:lower()==niType:lower())
    assert(res.outputType:lower()==noType:lower())

    res.inputType = niType
    res.outputType = noType
  end

  return res
end)


C.stencilLinebuffer = memoize(function( A, w_orig, h_orig, T, xmin, xmax, ymin, ymax, framed, X )
  err(types.isType(A), "stencilLinebuffer: A must be type, but is: "..tostring(A))

  err(type(T)=="number","stencilLinebuffer: T must be number")

  err(type(xmin)=="number","stencilLinebuffer: xmin must be number")
  err(type(xmax)=="number","stencilLinebuffer: xmax must be number")
  err(type(ymin)=="number","stencilLinebuffer: ymin must be number")
  err(type(ymax)=="number","stencilLinebuffer: ymax must be number")

  err(T>=0, "stencilLinebuffer: T must be >=0");
  err(Uniform(w_orig):toNumber()>0,"stencilLinebuffer: w must be >0");
  err(Uniform(h_orig):toNumber()>0,"stencilLinebuffer: h must be >0");

  err(xmin<=xmax,"stencilLinebuffer: xmin("..tostring(xmin)..")>xmax("..tostring(xmax)..")")
  err(ymin<=ymax,"stencilLinebuffer: ymin("..tostring(ymin)..") must be <= ymax("..tostring(ymax)..")")

  err( xmax<=0,"stencilLinebuffer: NYI - xmax must be <=0")
  err( ymax<=0,"stencilLinebuffer: NYI - ymax must be <=0")

  err(X==nil,"C.stencilLinebuffer: Too many arguments")

  local fns = {modules.linebuffer( A, w_orig, h_orig, T, ymin, framed )}

  table.insert( fns, modules.SSR( A, T, xmin, ymin, framed, w_orig, h_orig) )

  if xmax~=0 or ymax~=0 then
    -- not supported by stencil generator, but we can hack around this with a slice
    assert( framed )
    local G = require "generators.core"
    table.insert( fns, G.Map{G.Slice{{0, xmax-xmin, 0, ymax-ymin}} } )
  end
  

  return C.linearPipeline( fns, J.sanitize("stencilLinebuffer_A"..tostring(A).."_w"..tostring(w_orig).."_h"..tostring(h_orig).."_T"..tostring(T).."_xmin"..tostring(math.abs(xmin)).."_xmax"..tostring(math.abs(xmax)).."_ymin"..tostring(math.abs(ymin)).."_ymax"..tostring(math.abs(ymax))) )
end)

-- this is basically the same as a stencilLinebuffer, but implemend using a register chain instead of rams
C.stencilLinebufferRegisterChain = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax )
  err(types.isType(A), "stencilLinebufferRegisterChain: A must be type")
  err(A:isData(), "stencilLinebufferRegisterChain: A must be datatype")

  err(type(T)=="number","stencilLinebufferRegisterChain: T must be number")
  err(type(w)=="number","stencilLinebufferRegisterChain: w must be number")
  err(type(h)=="number","stencilLinebufferRegisterChain: h must be number")
  err(type(xmin)=="number","stencilLinebufferRegisterChain: xmin must be number")
  err(type(xmax)=="number","stencilLinebufferRegisterChain: xmax must be number")
  err(type(ymin)=="number","stencilLinebufferRegisterChain: ymin must be number")
  err(type(ymax)=="number","stencilLinebufferRegisterChain: ymax must be number")

  err(T>=1, "stencilLinebufferRegisterChain: T must be >=1");
  err(w>0,"stencilLinebufferRegisterChain: w must be >0");
  err(h>0,"stencilLinebufferRegisterChain: h must be >0");
  err(xmin<=xmax,"stencilLinebufferRegisterChain: xmin>xmax")
  err(ymin<=ymax,"stencilLinebufferRegisterChain: ymin>ymax")
  err(xmax==0,"stencilLinebufferRegisterChain: xmax must be 0")
  err(ymax==0,"stencilLinebufferRegisterChain: ymax must be 0")

  local I = R.input( types.rv(types.Par(types.array2d(A,T))) )
  local SSRSize = w*(-ymin)-xmin+1
  local lb = modules.SSR(A,T,-SSRSize,0)(I)

  local tab = {}
  for y=ymin,0 do
    for x=xmin,0 do
      local idx = y*w+x
      -- SSR module stores values in opposite order of what we want
      local ridx = SSRSize+idx
      table.insert(tab, C.index(lb.type.over.over,ridx,0)(lb) )
    end
  end
  
  local out = C.tupleToArray(A,-xmin+1,-ymin+1)(R.concat("srtab",tab))

  return modules.lambda( J.sanitize("StencilLinebufferRegisterChain_A"..tostring(A).."_w"..w.."_h"..h.."_T"..T.."_xmin"..tostring(math.abs(xmin)).."_ymin"..tostring(math.abs(ymin)) ), I, out )
end)

-- T is the number of cycles over which this should take. T=4 -> takes 4 cycles
C.stencilLinebufferPartial = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax, framed_orig, X )
  J.err(Uniform.isUniform(w) or type(w)=="number","C.stencilLinebufferPartial: w must be number, but is:",w)
  J.err(Uniform.isUniform(h) or type(h)=="number","C.stencilLinebufferPartial: h must be number, but is:",h)
  J.err(Uniform.isUniform(T) or type(T)=="number","C.stencilLinebufferPartial: T must be number, but is:",T)
    
  assert(T>=1);
  assert(Uniform(w):gt(0):assertAlwaysTrue())
  assert(h>0);
  J.err(xmin<=xmax,"C.stencilLinebufferPartial: xmin must be less than or equal to xmax, but is xmin=",xmin," xmax=",xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)
  assert(X==nil)

  local framed = framed_orig
  if framed==nil then framed=false end
  assert(type(framed)=="boolean")

  -- SSRPartial need to be able to stall the linebuffer, so we must do this with handshake interfaces. Systolic pipelines can't stall each other
  return C.compose( J.sanitize("stencilLinebufferPartial_A"..tostring(A).."_W"..tostring(w).."_H"..tostring(h).."_L"..tostring(xmin).."_R"..tostring(xmax).."_B"..tostring(ymin).."_Top"..tostring(ymax).."_framed"..tostring(framed)), modules.liftHandshake(modules.waitOnInput(modules.SSRPartial( A, T, xmin, ymin,nil,nil,framed,w,h ))), modules.makeHandshake(modules.linebuffer( A, w, h, 1, ymin, framed )), "C.stencilLinebufferPartial" )
end)


-- purely wiring. This should really be implemented as a lift.
-- framed: this fn is a bit strange (actually introduces a new dimension), so can't use mapFramed
-- instead, special case this
C.unpackStencil = memoize(function( A, stencilW, stencilH, T, arrHeight, framed, framedW_orig, framedH_orig, X )
  assert(types.isType(A))
  assert(type(stencilW)=="number")
  err(stencilW>0,"unpackStencil: stencilW must be >0, but is:"..tostring(stencilW))
  assert(type(stencilH)=="number")
  err(stencilH>0,"unpackStencil: stencilH must be >0, but is:"..tostring(stencilH))
  err(type(T)=="number","unpackStencil: vector width should be number, but is: "..tostring(T))
  err( T>=0, "unpackStencil: T must be >=0, but is: ",T)
  err(arrHeight==nil, "Error: NYI - unpackStencil on non-height-1 arrays")
  err( framed==nil or type(framed)=="boolean", "unpackStencil: framed must be nil or bool")
  if framed==nil then framed=false end
  assert(X==nil)

  local res = {kind="unpackStencil", stencilW=stencilW, stencilH=stencilH,T=T,generator="C.unpackStencil"}
  res.inputType = types.array2d( A, stencilW+math.max(T,1)-1, stencilH)

  if T==0 then
    res.outputType = types.array2d( A, stencilW, stencilH)
  else
    res.outputType = types.array2d( types.array2d( A, stencilW, stencilH), T )
  end
  
  if framed then
    --local framedW, framedH = Uniform(framedW_orig):toNumber(), Uniform(framedH_orig):toNumber()
    --err( type(framedW)=="number", "unpackStencil: framedW must be number, but is: "..tostring(framedW))
    --err( type(framedH)=="number", "unpackStencil: framedH must be  number")
    
    res.inputType = types.rv(types.Seq( res.inputType, framedW_orig, framedH_orig ))
    res.outputType = types.rv(types.Seq( res.outputType, framedW_orig, framedH_orig ))
  else
  end
  
  res.sdfInput, res.sdfOutput = SDF{1,1}, SDF{1,1}
  res.stateful = false
  res.delay=0
  res.name = J.sanitize("unpackStencil_"..tostring(A).."_W"..tostring(stencilW).."_H"..tostring(stencilH).."_T"..tostring(T).."_framed"..tostring(framed).."_framedW"..tostring(framedW_orig).."_framedH"..tostring(framedH_orig) )

  if terralib~=nil then res.terraModule = CT.unpackStencil(res, A, stencilW, stencilH, T, arrHeight) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    
    local sinp = S.parameter("inp", rigel.extractData(res.inputType) )
    local out = {}
    for i=1,math.max(T,1) do
      out[i] = {}
      for y=0,stencilH-1 do
        for x=0,stencilW-1 do
          out[i][y*stencilW+x+1] = S.index( sinp, x+i-1, y )
        end
      end
    end


    local stencils = J.map(out,function(n) return S.cast( S.tuple(n), types.array2d(A,stencilW,stencilH) ) end)

    local fin
    if T==0 then
      fin = stencils[1]
    else
      fin = S.cast( S.tuple(stencils), rigel.extractData(res.outputType) )
    end
    
    systolicModule:addFunction( S.lambda("process", sinp, fin, "process_output", nil, nil, nil ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

C.StencilOfStencils = memoize(function( A, w_orig, h_orig, T, xmin, xmax, ymin, ymax, innerW, innerH, framed, X )

end)
  
-- if index==true, then we return a value, not an array
-- indices are inclusive
C.slice = memoize(function( inputType, idxLow, idxHigh, idyLow, idyHigh, index, X )
  err( types.isType(inputType),"slice first argument must be type" )
  err( inputType:isSchedule() ,"C.slice: type must be schedule type, but is:"..tostring(inputType) )
  err( type(idxLow)=="number", "slice idxLow must be number")
  err( type(idxHigh)=="number", "slice idxHigh must be number")
  err( index==nil or type(index)=="boolean", "index must be bool")
  err( X==nil, "C.slice: too many arguments")

  if inputType:isTuple() then
    err( idxLow < #inputType.list, "slice: idxLow=",idxLow," is out of bounds for type: ",inputType )
    assert( idxHigh < #inputType.list )
    --assert( idxLow == idxHigh ) -- NYI
    --assert( index )
    assert( index==false or idxLow==idxHigh )
    local OT = {}
    for i=idxLow,idxHigh do
      table.insert( OT, inputType.list[i+1] )
    end

    OT = types.tuple(OT)
    if index then OT = OT.list[1] end
    
    local res = modules.lift( J.sanitize("index_"..tostring(inputType).."_"..idxLow.."_"..idxHigh.."_"..tostring(index)), inputType:extractData(), OT:extractData(), 0,
      function(systolicInput)
        local lst = {}
        for i=idxLow,idxHigh do
          table.insert(lst, S.index( systolicInput, i ) )
        end

        if index then
          return lst[1]
        else
          return S.tuple(lst)
        end
      end,
      function() return CT.sliceTup( inputType, OT, idxLow, idxHigh, index ) end,
      "C.slice")

    -- hack: type may be a schedule type
    res.inputType = types.rv(inputType)
    res.outputType = types.rv(OT)
    
    return res
  elseif inputType:isArray() then
    local W = (inputType:arrayLength())[1]
    local H = (inputType:arrayLength())[2]
    err(idxLow<W,"slice: idxLow>=W, idxLow="..tostring(idxLow)..",W="..tostring(W)," inputType:",inputType)
    err(idxHigh<W, "slice: idxHigh>=W")
    err(type(idyLow)=="number", "slice:idyLow must be number")
    err(type(idyHigh)=="number","slice:idyHigh must be number")
    err(idyLow<H, "slice: idyLow must be < array H")
    err(idyHigh<H, "slice: idyHigh must be < array H, but input type is: ",inputType," idyHigh:",idyHigh)
    assert(idxLow<=idxHigh)
    assert(idyLow<=idyHigh)
    local OT

    if index then
      OT = inputType:arrayOver()
    else
      OT = types.array2d( inputType:arrayOver(), idxHigh-idxLow+1, idyHigh-idyLow+1 )
    end

    local nam = J.sanitize("slice_type"..tostring(inputType).."_xl"..idxLow.."_xh"..idxHigh.."_yl"..idyLow.."_yh"..idyHigh.."_index"..tostring(index))
    local res = modules.lift( nam, inputType:extractData(), OT:extractData(), 0,
      function(systolicInput)
        local systolicOutput = S.tuple( J.map( J.range2d(idxLow,idxHigh,idyLow,idyHigh), function(i) return S.index( systolicInput, i[1], i[2] ) end ) )
        systolicOutput = S.cast( systolicOutput, OT )

        if index then
          systolicOutput = S.index( systolicInput, idxLow, idyLow )
        end
        return systolicOutput
      end,
      function()
        if index then
          local OT = inputType:arrayOver()
          return CT.sliceArrIdx(inputType,OT,idxLow,idyLow,idxHigh,idyHigh,W)
        else
          return CT.sliceArr(inputType,OT,idxLow,idyLow,idxHigh,idyHigh,W)
        end
      end,
      "C.slice")

    -- hack: type may be a schedule type
    res.inputType = types.rv(inputType)
    res.outputType = types.rv(OT)
    
    return res
  else
    err(false, "C.index input must be tuple or array but is "..tostring(inputType))
  end
end)

function C.index( inputType, idx, idy, X )
  err( types.isType(inputType), "first input to index must be a type, but is: "..tostring(inputType) )
  err( inputType:isSchedule(),"C.index: type must be schedule type, but is: "..tostring(inputType) )
  err( type(idx)=="number", "index idx must be number")
  assert(X==nil)
  if idy==nil then idy=0 end
  local res = C.slice( inputType, idx, idx, idy, idy, true )
  return res
end


-- returns a module of type HS(bits(inputBitsPerCyc))->HS(bits(outputBitsPerCyc)),
-- which will take in a stream of tokens of input size, concat them, and output them at output size rate.
-- Runs at full throughput.
-- You give the min # of total bits that need to be read/written over a full transaction
--    -> returns the # of total bits that actually need to be read/written for a full transaction (will be >= minimums)
--    -> in format totalInputBits,totalOutputBits
-- returned input/output bytes must have input/output factor as a factor
--   i.e. inoutBits % inputFactor==0 and inoutBits % outputFactor==0
C.generalizedChangeRate = memoize(function(inputBitsPerCyc, minTotalInputBits_orig, inputFactor, outputBitsPerCyc, minTotalOutputBits_orig, outputFactor, X)
  assert(type(inputBitsPerCyc)=="number")
  assert(type(outputBitsPerCyc)=="number")

  local minTotalInputBits = Uniform(minTotalInputBits_orig)
  local minTotalOutputBits = Uniform(minTotalOutputBits_orig)
  
  assert(type(inputFactor)=="number")
  assert(type(outputFactor)=="number")
  err( (minTotalInputBits%Uniform(inputBitsPerCyc)):eq(0):assertAlwaysTrue(),"generalizedChangeRate: inputBitsPerCycle ("..inputBitsPerCyc..") must divide minTotalInputBits ("..tostring(minTotalInputBits)..")")
  err( (minTotalOutputBits%Uniform(outputBitsPerCyc)):eq(0):assertAlwaysTrue(), "generalizedChangeRate: outputBitsPerCycle ("..outputBitsPerCyc..") must divide minTotalOutputBits ("..tostring(minTotalOutputBits)..")")
  assert(X==nil)

  local name = J.sanitize("GeneralizedChangeRate_inputBitsPerCyc"..tostring(inputBitsPerCyc).."_outputBitsPerCyc"..tostring(outputBitsPerCyc).."_minTotalInputBits"..tostring(minTotalInputBits_orig).."_minTotalOutputBits"..tostring(minTotalOutputBits_orig))

  local res
  if inputBitsPerCyc==outputBitsPerCyc then
    local bts = minTotalInputBits:max(minTotalOutputBits)

    bts = Uniform.upToNearest(inputFactor,bts)
    bts = Uniform.upToNearest(outputFactor,bts)

    assert( (bts%inputFactor):eq(0):assertAlwaysTrue() )
    assert( (bts%outputFactor):eq(0):assertAlwaysTrue() )
    
    res={RM.makeHandshake(C.identity(types.bits(inputBitsPerCyc))),bts}
  elseif outputBitsPerCyc<inputBitsPerCyc then
    if inputBitsPerCyc%outputBitsPerCyc==0 then
      local inp = R.input(R.Handshake(types.bits(inputBitsPerCyc)))
      local N = inputBitsPerCyc/outputBitsPerCyc
      local out = RM.makeHandshake(C.cast(types.bits(inputBitsPerCyc),types.array2d(types.bits(outputBitsPerCyc),N)))(inp)
      out = RM.liftHandshake(RM.changeRate(types.bits(outputBitsPerCyc),1,N,1))(out)
      out = RM.makeHandshake(C.index(types.array2d(types.bits(outputBitsPerCyc),1),0))(out)

      local inoutBits = minTotalInputBits:max(minTotalOutputBits)
      local bts
      if (inoutBits%Uniform(inputBitsPerCyc)):eq(0):assertAlwaysTrue() then
        bts = inoutBits
      else
        bts = Uniform.upToNearest(inputBitsPerCyc,inoutBits)
      end

      if (inoutBits%Uniform(inputFactor)):eq(0):assertAlwaysTrue() then
      else
        bts = Uniform.upToNearest(inputFactor,bts)
      end

      if (inoutBits%Uniform(outputFactor)):eq(0):assertAlwaysTrue() then
      else
        bts = Uniform.upToNearest(outputFactor,bts)
      end

      assert( (Uniform(bts)%inputFactor):eq(0):assertAlwaysTrue() )
      assert( (Uniform(bts)%outputFactor):eq(0):assertAlwaysTrue() )

      res = {RM.lambda(name,inp,out),bts}
    else
      --assert(J.isPowerOf2(outputBitsPerCyc)) -- NYI
      --local shifterBits = inputBitsPerCyc
      --while shifterBits%outputBitsPerCyc~=0 do shifterBits = shifterBits*2 end

      local shifterBits = J.lcm(inputBitsPerCyc,outputBitsPerCyc)
            
      assert(shifterBits%outputBitsPerCyc==0)
      assert(shifterBits%inputBitsPerCyc==0)
      
      local inp = R.input(R.Handshake(types.bits(inputBitsPerCyc)))
      local out = RM.makeHandshake(C.cast(types.bits(inputBitsPerCyc),types.array2d(types.bits(inputBitsPerCyc),1)))(inp)
      out = RM.liftHandshake(RM.changeRate(types.bits(inputBitsPerCyc),1,1,shifterBits/inputBitsPerCyc))(out)
      out = RM.makeHandshake(C.cast(types.array2d(types.bits(inputBitsPerCyc),shifterBits/inputBitsPerCyc),types.bits(shifterBits)))(out)
      out = RM.makeHandshake(C.cast(types.bits(shifterBits),types.array2d(types.bits(outputBitsPerCyc),shifterBits/outputBitsPerCyc)))(out)
      out = RM.liftHandshake(RM.changeRate(types.bits(outputBitsPerCyc),1,shifterBits/outputBitsPerCyc,1))(out)
      out = RM.makeHandshake(C.index(types.array2d(types.bits(outputBitsPerCyc),1),0))(out)

      local bts = Uniform.upToNearest(outputBitsPerCyc,Uniform(minTotalInputBits):max(minTotalOutputBits))

      bts = Uniform.makeDivisible(bts,{inputFactor,outputFactor,shifterBits})
      
      assert( (bts%inputFactor):eq(0):assertAlwaysTrue() )
      assert( (bts%outputFactor):eq(0):assertAlwaysTrue() )

      res = {RM.lambda(name,inp,out),bts}
    end
  elseif outputBitsPerCyc>inputBitsPerCyc then
    if outputBitsPerCyc%inputBitsPerCyc==0 then
      -- ez case

      local inp = R.input(R.Handshake(types.bits(inputBitsPerCyc)))
      local N = outputBitsPerCyc/inputBitsPerCyc
      local out = RM.makeHandshake(C.arrayop(types.bits(inputBitsPerCyc),1))(inp)
      out = RM.liftHandshake(RM.changeRate(types.bits(inputBitsPerCyc),1,1,N))(out)
      out = RM.makeHandshake(C.cast(types.array2d(types.bits(inputBitsPerCyc),N),types.bits(outputBitsPerCyc)))(out)

      local bts = Uniform.upToNearest(inputBitsPerCyc,Uniform(minTotalInputBits):max(minTotalOutputBits))
      bts = Uniform.upToNearest(inputFactor,bts)
      bts = Uniform.upToNearest(outputFactor,bts)

      assert( (bts%inputFactor):eq(0):assertAlwaysTrue() )
      assert( (bts%outputFactor):eq(0):assertAlwaysTrue() )

      res = {RM.lambda(name,inp,out),bts}
    else
      local shifterBits = J.lcm(inputBitsPerCyc,outputBitsPerCyc)

      assert(shifterBits%inputBitsPerCyc==0)
      assert(shifterBits%outputBitsPerCyc==0)
      
      local inp = R.input(R.Handshake(types.bits(inputBitsPerCyc)))
      local out = RM.makeHandshake(C.cast(types.bits(inputBitsPerCyc),types.array2d(types.bits(inputBitsPerCyc),1)))(inp)
      out = RM.liftHandshake(RM.changeRate(types.bits(inputBitsPerCyc),1,1,shifterBits/inputBitsPerCyc))(out)
      out = RM.makeHandshake(C.cast(types.array2d(types.bits(inputBitsPerCyc),shifterBits/inputBitsPerCyc),types.bits(shifterBits)))(out)
      out = RM.makeHandshake(C.cast(types.bits(shifterBits),types.array2d(types.bits(outputBitsPerCyc),shifterBits/outputBitsPerCyc)))(out)
      out = RM.liftHandshake(RM.changeRate(types.bits(outputBitsPerCyc),1,shifterBits/outputBitsPerCyc,1))(out)
      out = RM.makeHandshake(C.index(types.array2d(types.bits(outputBitsPerCyc),1),0))(out)

      local bts = Uniform.upToNearest(inputBitsPerCyc,Uniform(minTotalInputBits):max(minTotalOutputBits))
      bts = Uniform.makeDivisible(bts,{inputFactor,outputFactor,shifterBits})

      assert( (bts%inputFactor):eq(0):assertAlwaysTrue() )
      assert( (bts%outputFactor):eq(0):assertAlwaysTrue() )

      res = {RM.lambda(name,inp,out),bts}
    end
  else
    print("NYI GENERALIZE CHANGE RATE", inputBitsPerCyc,outputBitsPerCyc)
    assert(false)
  end

  if terralib~=nil then
    res[1].terraModule = CT.generalizedChangeRate( res[1], inputBitsPerCyc, minTotalInputBits_orig, inputFactor, outputBitsPerCyc, minTotalOutputBits_orig, outputFactor, res[2], X)
  end
  
  return res
end)

function C.gaussian(W,sigma)
  local center = math.floor(W/2)
  local tab = {}
  local sum = 0
  for y=0,W-1 do
    for x=0,W-1 do
      local a = 1/(sigma*math.sqrt(2*math.pi))
      local dist = math.sqrt(math.pow(x-center,2)+math.pow(y-center,2))
      local v = a*math.exp(-(dist*dist)/(2*sigma*sigma))
      sum = sum + v
      table.insert(tab,v)
    end
  end

  local newsum = 0
  for i=1,#tab do
    tab[i] = math.floor((tab[i]*64/sum)+0.4)
    newsum = newsum + tab[i]
  end

  tab[center*W+center] = tab[center*W+center] + (64-newsum)

  return tab
end

-- remove fractional component
C.denormalize = memoize(function( ty )
  err(types.isType(ty),"denormalize: first argument should be type, but is: ",ty)
  err( ty:isInt() or ty:isUint(),"denormalize: must be int or uint, but is: ",ty )

  local outbits = ty.precision+ty.exp
  err( outbits>0,"denormalize: this type is fully fractional, so would disappear! ",ty )

  local outType = ty:replaceVar("precision",outbits):replaceVar("exp",0)

  if ty.exp==0 then
    -- do nothing
    return C.identity( ty, J.sanitize("Denormalize_"..tostring(ty) ) )
  elseif ty.exp>0 then
    -- make larger
    local res = RM.lift( J.sanitize("Denormalize_"..tostring(ty)), ty, outType, 0,
                         function(inp) return S.lshift(S.cast(inp,outType),S.constant(ty.exp,outType)) end)
    return res
  else -- ty.exp <0
    local res = RM.lift( J.sanitize("Denormalize_"..tostring(ty)), ty, outType, 0,
                         function(inp) return S.cast(S.rshift(inp,S.constant(-ty.exp,ty)), outType) end,
                         function() return CT.denormalize(ty) end)
    return res
  end
  
  return res
end)

C.plusConst = memoize(function( ty, value_orig, async, outputType )
  err(types.isType(ty),"plus100: first argument should be type, but is: ",ty)

  if async==nil then async=false end
  assert( type(async)=="boolean" )

  if outputType==nil then outputType = ty end
  assert( types.isType(outputType) )

  assert( ty.exp==outputType.exp )

  local value = Uniform(value_orig)
  err( value:isNumber(),"plusConst expected numeric input")
  value = value * math.pow(2,math.max(-ty.exp,0))  -- rescale by exp, to be in right scale

  print("VALUE",value_orig,value)
  
  local instanceMap = value:getInstances()
  
  local plus100mod = RM.lift( J.sanitize("plus_"..tostring(ty).."_"..tostring(value)), ty, outputType , J.sel(async==true,0,1) ,
                              function(plus100inp)
                                local res = S.cast(plus100inp,outputType) + S.cast(value:toSystolic(ty),outputType)
                                if async==true then res = res:disablePipelining() end
                                return res
                              end,
                              function() return CT.plusConsttfn( ty, value, outputType ) end, nil,nil, instanceMap )
  return plus100mod
end)

function C.plus100(ty) return C.plusConst(ty,100) end

__linearpipelinecnt = 0
-- convert an array of rigel modules into a straight pipeline
-- pipeline starts at index 1, ends at index N
function C.linearPipeline( t, modulename, rate, instances, X )
  err(modulename==nil or type(modulename)=="string","linearPipeline: modulename must be string")
  err( rate==nil or SDF.isSDF(rate),"linearPipeline: rate should be nil or SDF" )
  assert(X==nil)
  
  if modulename==nil then
    modulename="linearpipeline"..tostring(__linearpipelinecnt)
    __linearpipelinecnt = __linearpipelinecnt+1
  end

  err(type(t)=="table" and J.keycount(t)==#t, "C.linearPipeline: input must be array")
  for k,v in ipairs(t) do err(R.isFunction(v), "C.linearPipeline: input must be table of Rigel modules (idx "..k..")") end

  err( R.isPlainFunction(t[1]),"C.linearPipeline: first function in pipe must have known type (ie must not be a generator). fn: ",t[1] )

  if rate==nil then
    rate = t[1].sdfInput
  end
  
  local inp = R.input( t[1].inputType, rate )
  local out = inp

  for k,v in ipairs(t) do
    out = R.apply("linearPipe"..k,v,out)
  end

  return RM.lambda( modulename, inp, out, instances )
end

-- if ser==true, takes A[W,H]->A[W*H/ratio,W,H}
-- if ser==false, takes A[W*H/ratio,W,H}->A[W,H]
C.changeRateFramed = memoize(function(A, W, H, ratio, ser, X)
  local name = J.sanitize("ChangeRateFramed_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_ratio"..tostring(ratio).."_ser"..tostring(ser))
                               
  if ser then
    local TYO = types.array2d(A,W,H)
    local ty = R.V(TYO)

    local I = R.input(ty)
    local o = RM.liftDecimate(RM.liftBasic(C.cast(TYO, types.array2d(A,W*H))))(I)
    o = RM.RPassthrough(RM.changeRate(A,1,W*H,W*H/ratio,true,W,H))(o)
    return RM.lambda(name,I,o)
  else
    assert(false)
  end

  assert(false)
end)

-- given a comparison operator (op:{A,A}->bool), returns a function
-- of type A[2]->A[2]
C.sortCompare = memoize(
  function(A,op)
    local G = require "generators.core"
    return G.Function{"SortCompare_"..tostring(A).."_op"..tostring(op.name), types.rv(types.Par(types.array2d(A,2))), SDF{1,1},
      function(inp)
        local res = op(inp[0],inp[1])
        return G.Sel(res,inp,G.TupleToArray(inp[1],inp[0]))
      end}
  end)

-- takes in an array whose two halves are sorted. Returns full array sorted.
-- see http://www.iti.fh-flensburg.de/lang/algorithmen/sortieren/networks/oemen.htm
C.oddEvenMerge = memoize(
  function(A,N,op)
    local G = require "generators.core"
    assert(N>=2)
    assert(J.isPowerOf2(N))
    if N==2 then
      return C.sortCompare(A,op)
    else
      return G.Function{ "OddEvenMerge_"..tostring(A).."_N"..tostring(N).."_op"..tostring(op.name), types.rv(types.Par(types.array2d(A,N))), SDF{1,1}, 
        function(inp)
          local even,odd = {},{}
          for i=0,(N/2)-1 do
            table.insert(even,inp[i*2])
            table.insert(odd,inp[i*2+1])
          end
          local rEven, rOdd = G.TupleToArray(R.concat(even)), G.TupleToArray(R.concat(odd))
          local Rec = C.oddEvenMerge(A,N/2,op)
          local oEven, oOdd = Rec(rEven), Rec(rOdd)

          local res = {oEven[0]}
          for i=0,(N/2)-2 do
            local o = C.sortCompare(A,op)(G.TupleToArray(oOdd[i],oEven[i+1]))
            table.insert(res,o[0])
            table.insert(res,o[1])
          end
          table.insert(res,oOdd[(N/2)-1])
          local res = G.TupleToArray(R.concat(res))
          return res
        end}
    end
  end)

C.oddEvenMergeSort = memoize(
  function(A,N,op)
    local G = require "generators.core"
    assert(N>0)
    assert(J.isPowerOf2(N))
    if N==1 then
      return G.Identity --{types.array2d(A,N)}
    else
      return G.Function{"OddEvenMergeSort_"..tostring(A).."_N"..tostring(N).."_op"..tostring(op.name), types.rv(types.Par(types.array2d(A,N))), SDF{1,1},
        function(inp)
          local l,r = G.Slice{{0,(N/2)-1}}(inp), G.Slice{{N/2,N-1}}(inp)
          l,r = C.oddEvenMergeSort(A,N/2,op)(l), C.oddEvenMergeSort(A,N/2,op)(r)
          local res = C.flatten2(A,N)(l,r)
          res = C.oddEvenMerge(A,N,op)(res)
          return res
        end}
    end
  end)

C.StridedReader = memoize(
  function( filename, totalBytes, itemBytes, stride, offset, readPort, readAddr, readFn, X )
    -- stride,offset is given as # of items
    local G = require "generators.core"
    local SOC = require "generators.soc"
    assert(totalBytes%(itemBytes*stride)==0)
    assert(itemBytes%8==0)
    assert( R.isFunction(readFn) )
    assert(X==nil)
    
    local Nreads = (totalBytes/(itemBytes*stride))
    local res = G.Function{"StridedReader_totalBytes"..tostring(totalBytes).."_itemBytes"..tostring(itemBytes).."_stride"..tostring(stride).."_offset"..tostring(offset),
                         types.HandshakeTrigger, SDF{1,1},
      function(inp)

        local cnt = C.triggerUp(Nreads)(inp)
        local cnt = G.Fmap{RM.counter(types.uint(32), Nreads)}(cnt)
        cnt = G.Mul{stride*itemBytes}(cnt)
        local addr = G.Add{offset*itemBytes}(cnt)

        return SOC.axiReadBytes(filename,itemBytes,readPort,readAddr,readFn)(addr)
      end}

    return res
  end)

-- generate N DMA controllers to be able to read things with higher BW than a single axi port can
C.AXIReadPar = memoize(
  function(filename,W,H,ty,V,noc,X) -- Nbits: # of bits to read in parallel
    J.err( R.isInstance(noc),"AXIReadPar: noc should be module instance, but is: ",noc )
    J.err(X==nil,"AXIReadPar: too many arguments")
    local G = require "generators.core"
    local SOC = require "generators.soc"
    assert( (ty:verilogBits()*V)%64==0)
    local N = (ty:verilogBits()*V)/64
    assert((W*H)%N==0)

    local startAddr = SOC.currentAddr

    local totalBytes = W*H*(ty:verilogBits()/8)
    local res = G.Function{"AXIReadPar_"..tostring(W), types.HandshakeTrigger, SDF{1,1},
      function(inp)
        local inpb = G.FanOut{N}(inp)
        local out = {}
        for i=0,N-1 do
          local readFnName = "read"..J.sel(i==0,"",tostring(i))
          J.err(noc[readFnName]~=nil,"AXIReadPar: noc is missing function '",readFnName,"'")
          local tmp = C.StridedReader(filename,totalBytes,8,N,i,SOC.currentMAXIReadPort,SOC.currentAddr,noc[readFnName])(inpb[i])
          tmp = G.FIFO{128}(tmp)
          table.insert(out, tmp)
          SOC.currentMAXIReadPort = SOC.currentMAXIReadPort+1
        end
        SOC.currentAddr = SOC.currentAddr+totalBytes

        out = G.FanIn(unpack(out))

        return G.Fmap{ C.bitcast( out.type:deInterface(), types.array2d(ty,V) ) }(out)
      end}

    res.globalMetadata[noc.read.name.."_read_W"] = W
    res.globalMetadata[noc.read.name.."_read_H"] = H
    res.globalMetadata[noc.read.name.."_read_V"] = V
    res.globalMetadata[noc.read.name.."_read_type"] = tostring(ty)
    res.globalMetadata[noc.read.name.."_read_bitsPerPixel"] = ty:verilogBits()
    res.globalMetadata[noc.read.name.."_read_address"] = startAddr

    -- avoid double loading the image
    for i=1,N-1 do
      res.globalMetadata[noc.read1.name.."_read_filename"] = nil
    end
    
    return res
  end)

-- collect the number of tokens seen, and write it to a global
-- N: counts up to this number and then resets?
C.tokenCounterReg = memoize(
  function( A, regGlobal, N, X )
    J.err( types.isType(A),"tokenCounterReg: a must be type" )
    J.err( A:isRV(),"tokenCounterReg: input should be handshaked, but is: "..tostring(A))
    J.err( N==nil or type(N)=="number","tokenCounterReg: N must be number" )
    J.err( R.isFunction(regGlobal),"tokenCounterReg: reg should be fn")
    J.err( X==nil, "tokenCounterReg: too many args" )
    
    if N==nil then
      N = math.pow(2,32)-1
    end
      
    local G = require "generators.core"

    local res = G.Function{ "TokenCounterReg_"..tostring(A).."_"..tostring(regGlobal).."_"..tostring(N), A, SDF{1,1},
      function(inp)
        local inpb = G.FanOut{2}(inp)
        local ct = G.Fmap{C.valueToTrigger(A:deInterface())}(inpb[1])
        local cnt = G.Fmap{RM.counter(types.uint(32),N)}(ct)
        cnt = G.Add{1}(cnt)
        return R.statements{inpb[0],regGlobal(cnt)}
      end}

    return res
  end)

-- name: name of new (renamed) module
-- renameTable: hash map from port_on_Mod->port_on_new_module.
--   port_on_new_module can either be a string (add port automatically), or {"SV","NEW_NAME"}, which will not introduce a port (allows for wiring to SV interfaces. then you need to add the port manually)
C.rename = function( Mod, name, renameTable, extraPortDefString, extraDefs )

  local portlist = {}
  local modinst = {}

  local globalRename = {}
  for k,v in pairs(renameTable) do
    if k=="CLK" or k=="reset" or k=="ready_downstream" then
      if type(v)=="string" then
        table.insert(portlist,"input wire "..v)
        table.insert(modinst,"."..k.."("..v..")")
      else
        table.insert(modinst,"."..k.."("..v[2]..")")
      end
    elseif k=="process_input" then
      local ty = types.lower(Mod.inputType)
      if ty:verilogBits()==1 then
        table.insert(portlist,"input wire "..v)
      else
        assert(false)
      end
      table.insert(modinst,"."..k.."("..v..")")
    elseif k=="process_output" then
      local ty = types.lower(Mod.outputType)
      if ty:verilogBits()==1 then
        table.insert(portlist,"output wire "..v)
      else
        assert(false)
      end
      table.insert(modinst,"."..k.."("..v..")")
    elseif k=="process_output_valid" then
      assert(types.isHandshake(Mod.outputType))
      local ty = types.lower(Mod.outputType)
      table.insert(portlist,"output wire "..v)
      table.insert(portlist,"output wire ["..tostring(ty:verilogBits()-2)..":0] "..renameTable.process_output_data)
      table.insert(modinst,".process_output({"..v..","..renameTable.process_output_data.."})")
    elseif k=="process_input_valid" then
      J.err(types.isHandshakeAny(Mod.inputType),"NYIII - "..tostring(Mod.inputType))
      local ty = types.lower(Mod.inputType)

      if type(v)=="string" then
        table.insert(portlist,"input wire "..v)
        table.insert(portlist,"input wire ["..tostring(ty:verilogBits()-2)..":0] "..renameTable.process_input_data)
        table.insert(modinst,".process_input({"..v..","..renameTable.process_input_data.."})")
      else
        table.insert(modinst,".process_input({"..v[2]..","..renameTable.process_input_data[2].."})")
      end
    elseif k=="process_input_data" then
    elseif k=="process_output_data" then
    elseif k=="ready" then
      J.err(types.isHandshakeAny(Mod.inputType),"NYIII - "..tostring(Mod.inputType))

      if type(v)=="string" then
        assert(false)
      else
        table.insert(modinst,".ready("..v[2]..")")
      end
    elseif k:sub(#k-4,#k)=="valid" then
      k = k:sub(1,#k-6)
      J.err(Mod:getGlobal(k)~=nil,k.." is not a global")
      globalRename[k] = {"sv","{"..renameTable[k.."_valid"][2]..","..renameTable[k.."_data"][2].."}"}
    elseif k:sub(#k-3,#k)=="data" then
      J.err(Mod:getGlobal(k:sub(1,#k-5))~=nil,k.." is not a global")
    else
      J.err(Mod:getGlobal(k)~=nil,k.." is not a global")
      globalRename[k] = v
    end
  end

  for k,v in pairs(Mod.globals) do
    local ty = types.lower(k.type)

    local portname = k.name
    if type(globalRename[k.name])=="string" then portname=globalRename[k.name] end
    if type(globalRename[k.name])=="table" then portname=globalRename[k.name][2] end

    if type(globalRename[k.name])~="table" then 
      if ty:verilogBits()==1 then
        table.insert(portlist,k.direction.." wire "..k.name)
      else
        table.insert(portlist,k.direction.." wire ["..tostring(ty:verilogBits()-1)..":0] "..k.name)
      end
    end
    
    table.insert(modinst,"."..k.name.."("..portname..")")
  end

  if extraPortDefString~=nil then table.insert(portlist,extraPortDefString) end
  
  local vstr = [[module ]]..name..[[(]]..table.concat(portlist,", ")..[[);
]]

  if extraDefs~=nil then vstr = vstr..extraDefs.."\n" end

vstr = vstr..Mod.name.." inst("..table.concat(modinst,", ")..[[);

]]
  
  vstr = vstr..[[

endmodule

]]

  return RM.liftVerilog(name,Mod.inputType,Mod.outputType,vstr,Mod.globals,Mod.globalMetadata,Mod.sdfInput,Mod.sdfOutput, {Mod})
end

-- given a rigel module, create a systolic stub for it
function C.automaticSystolicStub( mod )
  local fns = {}
  local delays = {}

  local modFunctions
  if R.isModule(mod) then
    modFunctions = mod.functions
  elseif R.isFunction(mod) then
    modFunctions = {process=mod}
  else
    assert(false)
  end

  for fnname,fn in pairs(modFunctions) do
    fns[fnname] = Ssugar.lambdaConstructor(fnname,types.lower(fn.inputType),fnname.."_input")
    if fn.outputType~=types.Interface() then
      fns[fnname]:setOutput(S.constant(types.lower(fn.outputType):fakeValue(),types.lower(fn.outputType)),fnname.."_output")
    end
    delays[fnname]=fn.delay


    if types.isHandshakeAny(fn.inputType) or types.isHandshakeAny(fn.outputType) then
      local inp
      local readyDownstreamFnName = fnname.."_ready_downstream"
      if R.isFunction(mod) then readyDownstreamFnName = "ready_downstream" end -- hack for historic reasons
      
      if fn.outputType==types.Interface() then
        inp = S.parameter(readyDownstreamFnName,types.null() )
      else
        inp = S.parameter(readyDownstreamFnName,types.extractReady(fn.outputType) )
      end

      local out
      if fn.inputType~=types.Interface() then
        out = S.constant(types.extractReady(fn.inputType):fakeValue(),types.extractReady(fn.inputType))
      end

      local readyFnName = fnname.."_ready"
      if R.isFunction(mod) then readyFnName = "ready" end -- hack for historic reasons
      --      fns[readyFnName] = S.lambda(readyFnName,inp,out,readyFnName)
      fns[readyFnName] = Ssugar.lambdaConstructor(readyFnName,inp.type,readyFnName.."_downstream")
      if out~=nil then fns[readyFnName]:setOutput(out,readyFnName) end
      delays[readyFnName]=0
    else
      J.err(fn.delay~=nil,"Fn is missing delay? "..mod.name.." "..fnname)
      if fn.stateful or fn.delay>0 then
        fns[fnname]:setCE(S.CE(fnname.."_CE"))
      end
      if fn.stateful then
        fns[fnname]:setValid(fnname.."_valid")
      end
    end

    fns[fnname]:setPure( fn.stateful==false )
  end
  
  local res = Ssugar.moduleConstructor(mod.name)
  
  local instances = {}
  local externalInstances = {}
  for inst,fnlist in pairs(mod.requires) do
    local sinst = inst:toSystolicInstance()

    for fnname,_ in pairs(fnlist) do
      res:addExternalFn(sinst,fnname)
      
      local fn = inst.module.functions[fnname]
      if types.isHandshakeAny(fn.inputType) or types.isHandshakeAny(fn.outputType) then
        res:addExternalFn(sinst,fnname.."_ready")
      end
    end
  end

  if mod.instanceMap~=nil then
    for inst,_ in pairs(mod.instanceMap) do
      assert(R.isInstance(inst))

      if R.isModule(inst.module) or R.isPlainFunction(inst.module) then
        local sinst = inst:toSystolicInstance()
        instances[sinst]=1
        
        for _,fn in pairs(sinst.module.functions) do
          if S.isFunction(fn) then

            local defaultFn
            for _,v in pairs(fns) do defaultFn=v end

            local CE
            local VALID
            if fn.CE~=nil then
              CE=S.constant(true,types.Bool)
            end
            if fn.valid~=nil then
              VALID=S.constant(true,types.Bool)
            end

            if fn.inputParameter.type==types.null() then
              defaultFn:addPipeline(sinst[fn.name](sinst,nil,S.constant(false,types.bool()),CE))
            else
              defaultFn:addPipeline(sinst[fn.name](sinst,S.constant(fn.inputParameter.type:fakeValue(),fn.inputParameter.type),VALID,CE))
            end
          else
            print("NYI - fn of type "..tostring(fn))
            assert(false) -- NYI
          end
        end
      else
        print("NYI - instance of "..tostring(inst.module))
        assert(false)
      end
    end
  end
  
  if mod.stateful then
    fns.reset = Ssugar.lambdaConstructor("reset",types.null(),"rnil","reset")
    fns.reset:setPure(false)
    delays.reset = 0
  end

  res:onlyWire(true)
  for inst,_ in pairs(instances) do res:add(inst) end
  for k,v in pairs(fns) do res:addFunction(v) end
  for k,v in pairs(delays) do res:setDelay(k,v) end

  assert( Ssugar.isModuleConstructor(res) )
  return res
end

-- this will import a Verilog file as a module... the module is basically a stub,
-- this basically only serves to include the source when we lower to verilog
-- dependencyList is a list of modules we depend on
C.VerilogFile = J.memoize(function( filename, ... )
    --if dependencyList==nil then dependencyList={} end
  local dependencyList = {...}
    
  local res = {inputType=types.null(), outputType=types.null(), stateful=false, sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, name = J.sanitize(filename), delay=0 }
  res.instanceMap={}
  for _,d in pairs(dependencyList) do
    J.err( R.isModule(d),"dependency should be Rigel module, but is:",d)
    res.instanceMap[d:instantiate()]=1
  end
  
  res = R.newFunction(res)
  
  local function makeSystolic()
    local s = C.automaticSystolicStub(res)
    local verilog = J.fileToString(R.path..filename)
    verilog = verilog:gsub([[`include "[%w_\.]*"]],"")
    verilog = "/* verilator lint_off WIDTH */\n/* verilator lint_off CASEINCOMPLETE */\n"..verilog.."\n/* verilator lint_on CASEINCOMPLETE */\n/* verilator lint_on WIDTH */\n\n"
    s:verilog(verilog)
    return s
  end

  return R.newModule{name=J.sanitize(filename),functions={process=res},stateful=false,makeSystolic=makeSystolic}
end)
 
-- you should only use this if it's safe! (on the output of fns)
C.VRtoRVRaw = J.memoize(function(A)
  err( types.isBasic(A), "expected basic type" )
  local res = { inputType=types.HandshakeVR(A), outputType=types.Handshake(A), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, delay=0}
  res.name = J.sanitize("VRtoRVRaw_"..tostring(A))

  function res.makeSystolic()
    local sm = Ssugar.moduleConstructor(res.name):onlyWire(true)
    local r = S.parameter("ready_downstream",types.bool())
    sm:addFunction( S.lambda("ready", r, r, "ready") )
    local I = S.parameter("process_input", R.lower(types.Handshake(A)) )
    sm:addFunction( S.lambda("process",I,I,"process_output") )
    return sm
  end

  res = rigel.newFunction(res)
  
  function res.makeTerra() return CT.VRtoRVRaw( res, A ) end
  
  return res
end)

-- fn should be HSVR, and this wraps to return a plain HS function
C.ConvertVRtoRV = J.memoize(function(fn)
  err( types.isHandshakeVR(fn.inputType), "ConvertVRtoRV: fn input should be HandshakeVR, but is: "..tostring(fn.inputType) )
  err( types.isHandshakeVR(fn.outputType), "ConvertVRtoRV: fn output should be HandshakeVR" )
  return C.linearPipeline({C.fifo(types.extractData(fn.inputType),1,nil,nil,true),fn,C.VRtoRVRaw(types.extractData(fn.outputType))},"ConvertVRtoRV_"..fn.name)
end)

-- placed at the front of a pipeline to feed it invalid input
C.Invalid = J.memoize(function(A,VR)
  err( types.isType(A), "C.Invalid: input should be type, but is: "..tostring(A) )
  err( types.isBasic(A), "C.Stall: expected basic type" )
  local otype = types.Handshake(A)
  if VR==true then otype = types.HandshakeVR(A) end
  local res = R.newFunction{ name=J.sanitize("Invalid_"..tostring(A)), inputType=types.null(), outputType=otype, sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false}
  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)
    local verilog = res:vHeader()
    verilog = verilog.."  assign process_output["..A:verilogBits().."] = 1'b0;\n"
    verilog = verilog.."endmodule\n\n"
    s:verilog(verilog)
    return s
  end
  return res
end)

-- this is placed at the output of a pipeline to stall it (sets ready=false)
C.Stall = J.memoize(function(A,VR)
  err( types.isType(A), "C.Stall: input should be type, but is: "..tostring(A) )
  err( types.isBasic(A), "C.Stall: expected basic type" )
  local itype = types.Handshake(A)
  if VR==true then itype = types.HandshakeVR(A) end
  local res = R.newFunction{ name=J.sanitize("Stall_"..tostring(A)), inputType=itype, outputType=types.null(), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false}
  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)
    local verilog = res:vHeader()
    verilog = verilog.."  assign ready = 1'b0;\n"
    verilog = verilog.."endmodule\n\n"
    s:verilog(verilog)
    return s
  end
  return res
end)

local IdxGT = J.memoize(function()
    local G = require "generators.core"
    return G.Module{"IdxGT",function(i) return G.GT(i[0][1],i[1][1]) end}
end)

-- input type: {{A,bool},u8} -> {A,u8}
local IDXBTS = 32
local BoolToIdxInner = J.memoize(function(A,X)
  assert(X==nil)
  local G = require "generators.core"
  local res = G.Module{"BoolToIdxInner", SDF{1,1}, types.rv(types.Par(types.tuple{types.Tuple{A,types.Bool},types.Uint(IDXBTS)})),
                  function(i) return R.concat{i[0][0],G.Sel(i[0][1],i[1],R.c(0,types.uint(IDXBTS)))} end}
  assert(R.isPlainFunction(res))
  return res
end)

local BoolToIdx = J.memoize(function (A,P,X)
  assert(types.isType(A))
  assert(type(P)=="number")
  assert(X==nil)
  local G = require "generators.core"
  
  local res = G.Module{"BoolToIdx",SDF{1,1},types.rv(types.Par(types.Array2d(types.Tuple{A,types.Bool},P))),
                  function(i)
                    local tmp = R.c(J.reverse(J.range(1,P)),types.array2d(types.uint(IDXBTS),P))
                    tmp = G.Zip(i,tmp)
                    return G.Map{BoolToIdxInner(A)}(tmp)
                  end}
  assert(R.isPlainFunction(res))
  return res
end)

-- {A,u8}->{A,bool} (if u8>0)
local IdxToBool = J.memoize(function(A,X)
  assert(X==nil)
  local G = require "generators.core"
  local res = G.Module{"IdxToBool", SDF{1,1}, types.rv(types.Par(types.Tuple{A,types.Uint(IDXBTS)})), function(i) return R.concat{i[0],G.GT{0}(i[1])} end }
  assert(R.isPlainFunction(res))
  return res
end)

-- do the sorting nonsense needed for FilterSeqPar
C.FilterSeqPar = J.memoize(function( ty, N, rate, framed, framedW, framedH, X )
  local G = require "generators.core"

  local res = G.Module{"C_FilterSeqPar", types.RV(types.Par(types.Array2d(types.Tuple{ty,types.Bool},N))), SDF{1,1},
    function(i)                   
      local o = G.Map{BoolToIdx(ty,N)}(i)
      o = G.Sort{IdxGT()}(o)
      --print("IDXTOB",o.type)
      o = G.Map{IdxToBool(ty)}(o)
      o = G.Map{RM.filterSeqPar(ty,N,SDF(rate))}(o)
      return o
    end}

  assert(R.isPlainFunction(res))

  if framed then
    local inputType = types.RV(types.ParSeq(types.array2d( types.tuple{ty,types.bool()}, N ),framedW,framedH) )
    local outputType = types.RV(types.VarSeq(types.Par(ty),framedW,framedH))
    assert(res.inputType:lower()==inputType:lower())
    assert(res.outputType:lower()==outputType:lower())
    res.inputType = inputType
    res.outputType = outputType
  end
  
  return res
end)

C.SerToWidthArrayToScalar = J.memoize(function(ty,size)
  local generators = require "generators.core"
  
  local res = generators.Function{
    "SerToWidth_Convert_Array_to_scalar_"..tostring(ty).."_"..tostring(size), SDF{1,1},
    types.rV(types.Par(types.array2d(ty,1,1))),
    function(inp)
      return generators.Index{0}(inp)
  end}
  assert(R.isPlainFunction(res))

  res.inputType = types.rV(types.ParSeq(types.array2d(ty,1,1),size))
  res.outputType = types.rRV(types.Seq(types.Par(ty),size))

  return res
end)

-- for legacy reasons, changerate returns stuff in column major order.
-- instead, do row major
-- takes ty[Vw,Vh;W,H} to ty[V2w,V2h;W,H} where V2w*V2h==outputItemsPerCyc
C.ChangeRateRowMajor = J.memoize(function(ty, Vw, Vh, outputItemsPerCyc, W_orig, H, X )
  J.err( type(outputItemsPerCyc)=="number", "ChangeRateRowMajor: outputItermsPerCyc should be number, but is: ",outputItemsPerCyc )
  J.err( math.floor(outputItemsPerCyc)==outputItemsPerCyc, "ChangeRateRowMajor outputItemsPerCyc is not integer, is: ",outputItemsPerCyc )
  --J.err( type(W)=="number", "ChangeRateRowMajor: W should be number, but is: ",W)
  local W = Uniform(W_orig)
  J.err( type(H)=="number", "ChangeRateRowMajor: H should be number, but is: ",H)
  
  local generators = require "generators.core"
    
  local cr = RM.changeRate( ty, 1, Vw*Vh, outputItemsPerCyc )

  J.err( outputItemsPerCyc==0 or (Uniform(W):toNumber()*Uniform(H):toNumber())%outputItemsPerCyc==0, "ChangeRateRowMajor: outputItemsPerCyc does not divide array size? W=",W," H=",H," outputItemsPerCyc=",outputItemsPerCyc)
  assert( outputItemsPerCyc<Uniform(W):toNumber() or outputItemsPerCyc%Uniform(W):toNumber()==0 )

  local V2w, V2h = outputItemsPerCyc, 1
  if outputItemsPerCyc==0 then V2h = 0 end
  if outputItemsPerCyc>Uniform(W):toNumber() then
    V2w, V2h = Uniform(W):toNumber(), outputItemsPerCyc/Uniform(W):toNumber()
  end
    
  local inputType, outputType
  if Vw==W and Vh==H then
    inputType = types.RV( types.Array2d(ty,Vw,Vh) )
  else
    inputType = types.RV( types.Array2d( ty, W_orig, H, Vw, Vh ) )
  end
  
  outputType = types.RV( types.Array2d( ty, W_orig, H, V2w, V2h ) )

  local res = generators.Function{
    "ChangeRateRowMajor_"..tostring(ty).."_Vw"..tostring(Vw).."_Vh"..tostring(Vh).."_OIPC"..tostring(outputItemsPerCyc).."_W"..tostring(W_orig).."_H"..tostring(H), types.RV(inputType:extractData()),
    function(inp)
      local inprs
      if Vw==0 and Vh==0 then
        inprs = inp
      else
        inprs = generators.ReshapeArray{{Vw*Vh,1}}(inp)
      end

      local out = RM.liftHandshake(cr)(inprs)
      
      if outputItemsPerCyc>0 then
        local res = RM.makeHandshake( C.cast( out.type:deInterface(), types.Array2d( out.type:deInterface().over, V2w, V2h )) )(out)
        return res
      else
        return out
      end
    end}

  assert( R.isPlainFunction(res) )
  assert( res.outputType:lower()==outputType:lower() )
  assert( res.inputType:lower()==inputType:lower() )
  res.inputType = inputType
  res.outputType = outputType
  
  return res
end)

-- FloatRec to ieee Float
C.Float = J.memoize(function( exp, sig, X )
  err( type(exp)=="number" )
  err( type(sig)=="number" )
  err( X==nil )


  local HardFloat_localFuncs = C.VerilogFile("generators/hardfloat/source/HardFloat_localFuncs.vi")
  local HardFloat_consts = C.VerilogFile("generators/hardfloat/source/HardFloat_consts.vi")
  local HardFloat_primitives = C.VerilogFile("generators/hardfloat/source/HardFloat_primitives.v")
  local HardFloat_specialize = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.vi")
  local HardFloat_rawFN = C.VerilogFile("generators/hardfloat/source/HardFloat_rawFN.v", HardFloat_specialize, HardFloat_consts )
  local recFNToFN = C.VerilogFile("generators/hardfloat/source/recFNToFN.v", HardFloat_consts, HardFloat_localFuncs, HardFloat_primitives, HardFloat_rawFN )

  local inst = {}
  local floatRecToFloat = recFNToFN:instantiate("floatRecToFloat")
  inst[floatRecToFloat] = 1
  
  local res = R.newFunction{ name=J.sanitize("FloatRecToFloat_"..tostring(exp).."_"..tostring(sig)), inputType = types.rv(types.FloatRec(exp,sig)), outputType=types.rv(types.Float(exp,sig)), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, instanceMap=inst, delay=0 }

  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)

    local verilog = res:vHeader()

    verilog = verilog..[[
recFNToFN #(.expWidth(]]..exp..[[),.sigWidth(]]..sig..[[)) conv (.in(process_input),.out(process_output));
endmodule

]]
    s:verilog(verilog)
    return s
  end

  function res.makeTerra()
    return CT.Float( res, exp, sig )
  end

  return res
end)

C.FloatRec = J.memoize(function( inputType, exp, sig, X )
  err( inputType:isUint() or inputType:isInt() )
  err( type(exp)=="number","C.FloatRec: exp should be number, but is: ",exp )
  err( type(sig)=="number" ,"C.FloatRec: sig should be number, but is: ",sig )
  err( X==nil )

  local HardFloat_localFuncs = C.VerilogFile("generators/hardfloat/source/HardFloat_localFuncs.vi")
  local HardFloat_specialize = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.vi")
  local HardFloat_consts = C.VerilogFile("generators/hardfloat/source/HardFloat_consts.vi")
  local HardFloat_primitives = C.VerilogFile("generators/hardfloat/source/HardFloat_primitives.v")
  local iNToRecFN = C.VerilogFile("generators/hardfloat/source/iNToRecFN.v",HardFloat_consts,HardFloat_specialize,HardFloat_localFuncs,HardFloat_primitives)

  local inst = {}
  local intToFloat = iNToRecFN:instantiate("intToFloat")
  inst[intToFloat] = 1
  
  local res = R.newFunction{ name=J.sanitize("FloatRec_"..tostring(inputType).."_exp"..tostring(exp).."_"..tostring(sig)), inputType = types.rv(inputType), outputType=types.rv(types.FloatRec(exp,sig)), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, instanceMap=inst, delay=0 }

  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)

    local verilog = res:vHeader()

    local signed = "1'b0"
    if inputType:isInt() then signed="1'b1" end
    
    verilog = verilog..[[
wire [4:0] exception;
iNToRecFN #(.intWidth(]]..inputType:verilogBits()..[[),.expWidth(]]..exp..[[),.sigWidth(]]..sig..[[)) conv (.control(`flControl_default),.signedIn(]]..signed..[[),.in(process_input),.roundingMode(`round_near_even),.out(process_output),.exceptionFlags(exception));
endmodule

]]
    s:verilog(verilog)
    return s
  end

  function res.makeTerra()
    return CT.FloatRec( res, inputType, exp, sig )
  end
  
  return res
end)

C.FloatToFloatRec = J.memoize(function( exp, sig, X )
  err( type(exp)=="number","C.FloatToFloatRec: exp should be number, but is: ",exp )
  err( type(sig)=="number" ,"C.FloatToFloatRec: sig should be number, but is: ",sig )
  err( X==nil )

  local HardFloat_localFuncs = C.VerilogFile("generators/hardfloat/source/HardFloat_localFuncs.vi")
  --local HardFloat_specialize = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.vi")
  --local HardFloat_consts = C.VerilogFile("generators/hardfloat/source/HardFloat_consts.vi")
  --local HardFloat_primitives = C.VerilogFile("generators/hardfloat/source/HardFloat_primitives.v")
  local fNToRecFN = C.VerilogFile("generators/hardfloat/source/fNToRecFN.v", HardFloat_localFuncs)

  local inst = {}
  local ftof = fNToRecFN:instantiate("ftof")
  inst[ftof] = 1
  
  local res = R.newFunction{ name=J.sanitize("FloatToFloatRec_".."_exp"..tostring(exp).."_"..tostring(sig)), inputType = types.rv(types.Float(exp,sig)), outputType=types.rv(types.FloatRec(exp,sig)), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, instanceMap=inst, delay=0 }

  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)

    local verilog = res:vHeader()
    
    verilog = verilog..[[

fNToRecFN #(.expWidth(]]..exp..[[),.sigWidth(]]..sig..[[)) ftof (.in(process_input),.out(process_output));
endmodule

]]
    s:verilog(verilog)
    return s
  end

  function res.makeTerra()
    return CT.FloatToFloatRec( res, exp, sig )
  end
  
  return res
end)

C.FloatToInt = J.memoize(function( exp, sig, signed, intWidth, X )
  err( type(exp)=="number","C.FloatToInt: exp should be number, but is: ",exp )
  err( type(sig)=="number" ,"C.FloatToInt: sig should be number, but is: ",sig )
  err( X==nil )

  local HardFloat_localFuncs = C.VerilogFile("generators/hardfloat/source/HardFloat_localFuncs.vi")
  local HardFloat_specialize = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.vi")
  local HardFloat_consts = C.VerilogFile("generators/hardfloat/source/HardFloat_consts.vi")
  local HardFloat_rawFN = C.VerilogFile("generators/hardfloat/source/HardFloat_rawFN.v", HardFloat_specialize, HardFloat_consts )
  local HardFloat_specializev = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.v", HardFloat_consts)
  local HardFloat_primitives = C.VerilogFile("generators/hardfloat/source/HardFloat_primitives.v")
  local recFNToIN = C.VerilogFile("generators/hardfloat/source/recFNToIN.v", HardFloat_consts, HardFloat_specialize, HardFloat_localFuncs, HardFloat_rawFN, HardFloat_specializev, HardFloat_primitives )

  local inst = {}
  local ftoi = recFNToIN:instantiate("ftof")
  inst[ftoi] = 1
  
  local res = R.newFunction{ name=J.sanitize("FloatToInt_".."_exp"..tostring(exp).."_"..tostring(sig).."_signed"..tostring(signed).."_"..tostring(intWidth)), inputType = types.rv(types.FloatRec(exp,sig)), outputType=types.rv( J.sel(signed, types.int(intWidth), types.uint(intWidth)) ), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, instanceMap=inst, delay=0 }

  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)

    local verilog = res:vHeader()
    
    verilog = verilog..[[

wire [2:0] exception;
recFNToIN #(.expWidth(]]..exp..[[),.sigWidth(]]..sig..[[),.intWidth(]]..intWidth..[[)) ftoi (.control(`flControl_default),
.in(process_input),
.roundingMode(`round_minMag),
.signedOut(]]..J.sel(signed,"1'b1","1'b0")..[[),
.out(process_output),
.intExceptionFlags(exception));
endmodule

]]
    s:verilog(verilog)
    return s
  end

  function res.makeTerra()
    return CT.FloatToInt( res, exp, sig, signed, intWidth )
  end
  
  return res
end)

-- floating point add
-- subtract: do a subtract instead
C.sumF = J.memoize(function( exp, sig, subtract, X )
  err( type(exp)=="number","C.FloatRec: exp should be number, but is: ",exp )
  err( type(sig)=="number" ,"C.FloatRec: sig should be number, but is: ",sig )
  err( type(subtract)=="boolean" )
  err( X==nil )

  local HardFloat_localFuncs = C.VerilogFile("generators/hardfloat/source/HardFloat_localFuncs.vi")
  local HardFloat_consts = C.VerilogFile("generators/hardfloat/source/HardFloat_consts.vi")
  local HardFloat_specialize = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.vi")
  local HardFloat_specializev = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.v", HardFloat_consts)

  --  local HardFloat_primitives = C.VerilogFile("generators/hardfloat/source/HardFloat_primitives.v")
  local isSigNaNRecFN = C.VerilogFile("generators/hardfloat/source/isSigNaNRecFN.v", HardFloat_specialize)
  local addRecFN = C.VerilogFile("generators/hardfloat/source/addRecFN.v", HardFloat_consts, HardFloat_specialize, HardFloat_specializev, isSigNaNRecFN, HardFloat_localFuncs )

  local inst = {}
  local intToFloat = addRecFN:instantiate("add")
  inst[intToFloat] = 1
  
  local res = R.newFunction{ name=J.sanitize("Float"..J.sel(subtract,"Sub","Add").."_"..tostring(exp).."_"..tostring(sig)), inputType = types.rv(types.Tuple{types.FloatRec(exp,sig),types.FloatRec(exp,sig)}), outputType=types.rv(types.FloatRec(exp,sig)), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, instanceMap=inst, delay=6 }

  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)

    local verilog = res:vHeader()

    local bts = exp+sig+1
    verilog = verilog..[[
wire [4:0] exception;
wire [32:0] out;

(*retiming_forward = 1 *) reg [65:0] in1;
(*retiming_forward = 1 *) reg [65:0] in2;
(*retiming_forward = 1 *) reg [65:0] in3;
always @(posedge CLK) begin
  if( process_CE) begin
    in3 <= process_input;
    in2 <= in3;
    in1 <= in2;
  end
end

addRecFN #(.expWidth(]]..exp..[[),.sigWidth(]]..sig..[[)) add (.control(`flControl_default),
.subOp(]]..J.sel(subtract,"1'b1","1'b0")..[[),
.a(in1[]]..(bts-1)..[[:0]),
.b(in1[]]..(bts*2-1)..[[:]]..(bts)..[[]),
.roundingMode(`round_near_even),
.out(out),
.exceptionFlags(exception));

(*retiming_backward = 1 *) reg [32:0] tmp1;
(*retiming_backward = 1 *) reg [32:0] tmp2;
(*retiming_backward = 1 *) reg [32:0] tmp3;

always @(posedge CLK) begin
  if( process_CE) begin
    tmp1 <= out;
    tmp2 <= tmp1;
    tmp3 <= tmp2;
  end
end

assign process_output = tmp3;
endmodule

]]
    s:verilog(verilog)
    return s
  end

  function res.makeTerra()
    if subtract then
      return CT.SubF( res, exp, sig )
    else
      return CT.SumF( res, exp, sig )
    end
  end

  return res
end)

-- floating point add
C.mulF = J.memoize(function( exp, sig, X )
  err( type(exp)=="number","C.mulF: exp should be number, but is: ",exp )
  err( type(sig)=="number" ,"C.mulF: sig should be number, but is: ",sig )
  err( X==nil )

  --  local HardFloat_localFuncs = C.VerilogFile("generators/hardfloat/source/HardFloat_localFuncs.vi")
  local HardFloat_consts = C.VerilogFile("generators/hardfloat/source/HardFloat_consts.vi")
    
  local HardFloat_specialize = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.vi")
  local HardFloat_specializev = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.v", HardFloat_consts)
  --  local HardFloat_primitives = C.VerilogFile("generators/hardfloat/source/HardFloat_primitives.v")
  local isSigNaNRecFN = C.VerilogFile("generators/hardfloat/source/isSigNaNRecFN.v", HardFloat_specialize)
  local mulRecFN = C.VerilogFile("generators/hardfloat/source/mulRecFN.v", HardFloat_consts, isSigNaNRecFN, HardFloat_specializev  )

  local inst = {}
  local mf = mulRecFN:instantiate("mul")
  inst[mf] = 1
  
  local res = R.newFunction{ name=J.sanitize("FloatMul_"..tostring(exp).."_"..tostring(sig)), inputType = types.rv(types.Tuple{types.FloatRec(exp,sig),types.FloatRec(exp,sig)}), outputType=types.rv(types.FloatRec(exp,sig)), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, instanceMap=inst, delay=6 }

  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)

    local verilog = res:vHeader()

    local bts = exp+sig+1
    verilog = verilog..[[
wire [4:0] exception;
wire [32:0] out;

(*retiming_forward = 1 *) reg [65:0] in1;
(*retiming_forward = 1 *) reg [65:0] in2;
(*retiming_forward = 1 *) reg [65:0] in3;
always @(posedge CLK) begin
  if(process_CE) begin
    in3 <= process_input;
    in2 <= in3;
    in1 <= in2;
  end
end

mulRecFN #(.expWidth(]]..exp..[[),.sigWidth(]]..sig..[[)) mulinst (.control(`flControl_default),.a(in1[]]..(bts-1)..[[:0]),.b(in1[]]..(bts*2-1)..[[:]]..(bts)..[[]),.roundingMode(`round_near_even),.out(out),.exceptionFlags(exception));

(*retiming_backward = 1 *) reg [32:0] tmp1;
(*retiming_backward = 1 *) reg [32:0] tmp2;
(*retiming_backward = 1 *) reg [32:0] tmp3;

always @(posedge CLK) begin
  if(process_CE) begin
    tmp1 <= out;
    tmp2 <= tmp1;
    tmp3 <= tmp2;
  end
end

assign process_output = tmp3;
endmodule

]]
    s:verilog(verilog)
    return s
  end

  function res.makeTerra()
    return CT.MulF( res, exp, sig )
  end

  return res
end)

C.mulFConst = J.memoize(function( exp, sig, value, X )
  err( type(exp)=="number" )
  err( exp==8 )
  err( type(sig)=="number" )
  err( sig==24 )
  err( X==nil )

  local G = require "generators.core"
  return G.Function{"MulFConst_"..tostring(exp).."_"..tostring(sig).."_"..tostring(value), types.rv(types.FloatRec(exp,sig)),
    function(i)
      return G.MulF(i,G.FloatRec{32}(R.c(types.Float32,value)))
    end}
end)

-- doDiv: do a division instead of a sqrt
C.SqrtF = J.memoize(function( exp, sig, doDiv, X )
  err( type(exp)=="number" )
  err( type(sig)=="number" )
  err( X==nil )

  if doDiv==nil then doDiv = false end
  
  local HardFloat_localFuncs = C.VerilogFile("generators/hardfloat/source/HardFloat_localFuncs.vi")
  local HardFloat_consts = C.VerilogFile("generators/hardfloat/source/HardFloat_consts.vi")
  --local HardFloat_primitives = C.VerilogFile("generators/hardfloat/source/HardFloat_primitives.v")
  local HardFloat_specialize = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.vi")
  local HardFloat_specializev = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.v", HardFloat_consts)
  --local HardFloat_rawFN = C.VerilogFile("generators/hardfloat/source/HardFloat_rawFN.v", HardFloat_specialize, HardFloat_consts )
  local isSigNaNRecFN = C.VerilogFile("generators/hardfloat/source/isSigNaNRecFN.v", HardFloat_specialize)
  local divSqrtRecFN_small = C.VerilogFile("generators/hardfloat/source/divSqrtRecFN_small.v", HardFloat_consts, HardFloat_specialize, HardFloat_specializev, isSigNaNRecFN, HardFloat_localFuncs )

  local inst = {}
  local sqrt = divSqrtRecFN_small:instantiate("sqrt")
  inst[sqrt] = 1

  -- depends on input, but this is what it approximatley is according to the docs
  local approxCycles = sig+3

  local inpty = types.RV(types.FloatRec(exp,sig))
  if doDiv then inpty = types.RV(types.tuple{types.FloatRec(exp,sig),types.FloatRec(exp,sig)}) end
  local res = R.newFunction{ name=J.sanitize("Float"..J.sel(doDiv,"Div_","Sqrt_")..tostring(exp).."_"..tostring(sig)), inputType = inpty, outputType=types.RV(types.FloatRec(exp,sig)), sdfInput=SDF{1,approxCycles}, sdfOutput=SDF{1,approxCycles}, stateful=true, instanceMap=inst, delay=0 }

  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)

    local verilog = res:vHeader()

    verilog = verilog..[[

reg bufferEmpty;
reg [32:0] buffer;

wire unitReady;
wire outValid;
wire [32:0] out;

wire validIn;
assign validIn = ]]..res:vInputValid()..[[;

wire unitValid;
assign unitValid = validIn && (bufferEmpty==1'b1);

assign ]]..res:vOutputData()..[[ = buffer;
assign ]]..res:vOutputValid()..[[ = (bufferEmpty==1'b0);

// only accept an input if there is already space available
assign ]]..res:vInputReady()..[[ = bufferEmpty && unitReady;

always @(posedge CLK) begin
  if ( reset ) begin
    bufferEmpty <= 1'b1;
  end else begin
    if( outValid ) begin
      // note: we should never have initiated a sqrt unless the buffer was already empty!
      // so, we shouldn't have to worry about reads and writes into the buffer overlapping!! hopefully
      bufferEmpty <= 1'b0;
      buffer <= out;

      if (bufferEmpty==1'b0) begin
//        $display("Critical error: there is already something in the sqrt output buffer???\n");
      end
    end else if( ]]..res:vOutputReady()..[[ && bufferEmpty==1'b0 ) begin
      bufferEmpty <= 1'b1;
    end
  end
//  $display("unitValid %d dataIn %d bufferEmpty %d unitReady %d  readyUS %d |  out %d | unitOutValid %d buffer %d readyDS %d validOut %d",unitValid,]]..res:vInputData()..[[, bufferEmpty, unitReady, ready, out, outValid, buffer, ready_downstream, ]]..res:vOutputValid()..[[ );
end


wire sqrtOpOut;
wire [4:0] exceptionFlags;

divSqrtRecFN_small #(.expWidth(]]..exp..[[),.sigWidth(]]..sig..[[)) divsqrtunit (.nReset(!reset),
.clock(CLK),
.control(`flControl_default),
.sqrtOp(]]..J.sel(doDiv,"1'b0","1'b1")..[[),
.inReady( unitReady ),
.inValid( unitValid ),
.a( process_input[32:0] ),
.b( ]]..J.sel(doDiv,"process_input[65:33]","33'd0")..[[ ),
.roundingMode( `round_near_even ),
.outValid( outValid ),
.sqrtOpOut( sqrtOpOut ),
.out( out ),
.exceptionFlags( exceptionFlags )
);


endmodule

]]
    s:verilog(verilog)
    return s
  end

  function res.makeTerra() return CT.Sqrt( res, exp, sig, doDiv ) end
  
  return res
end)

C.CMPF = J.memoize(function( exp, sig, op, X )
  err( type(exp)=="number","C.mulF: exp should be number, but is: ",exp )
  err( type(sig)=="number" ,"C.mulF: sig should be number, but is: ",sig )
  err( type(op)=="string" )
  err( X==nil )

  --  local HardFloat_localFuncs = C.VerilogFile("generators/hardfloat/source/HardFloat_localFuncs.vi")
  local HardFloat_consts = C.VerilogFile("generators/hardfloat/source/HardFloat_consts.vi")
    
  local HardFloat_specialize = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.vi")
--  local HardFloat_specializev = C.VerilogFile("generators/hardfloat/source/8086-SSE/HardFloat_specialize.v", HardFloat_consts)
  --  local HardFloat_primitives = C.VerilogFile("generators/hardfloat/source/HardFloat_primitives.v")
  local isSigNaNRecFN = C.VerilogFile("generators/hardfloat/source/isSigNaNRecFN.v", HardFloat_specialize)
  local HardFloat_rawFN = C.VerilogFile("generators/hardfloat/source/HardFloat_rawFN.v", HardFloat_specialize, HardFloat_consts )
  local compareRecFN = C.VerilogFile("generators/hardfloat/source/compareRecFN.v", HardFloat_rawFN, isSigNaNRecFN )

  local inst = {}
  local cf = compareRecFN:instantiate("cmp")
  inst[cf] = 1

  local ops
  if op==">" then ops="gt"
  elseif op==">=" then ops="ge"
  elseif op=="<" then ops="lt"
  else assert(false) end
  
  local res = R.newFunction{ name=J.sanitize("FloatCMP_"..tostring(exp).."_"..tostring(sig).."_"..ops), inputType = types.rv(types.Tuple{types.FloatRec(exp,sig),types.FloatRec(exp,sig)}), outputType=types.rv(types.Bool), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, instanceMap=inst, delay=0 }

  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)

    local verilog = res:vHeader()

    local bts = exp+sig+1
    
    verilog = verilog..[[
wire [4:0] exception;
wire [32:0] out;

wire lt;
wire eq;
wire gt;
wire unordered;

compareRecFN #(.expWidth(]]..exp..[[),.sigWidth(]]..sig..[[)) cmpinst (.a(process_input[]]..(bts-1)..[[:0]),
.b(process_input[]]..(bts*2-1)..[[:]]..(bts)..[[]),
.signaling(1'b0), // should it signal exceptions?
.lt(lt),
.eq(eq),
.gt(gt),
.unordered(unordered),
.exceptionFlags(exception));

]]

    if op==">" then
      verilog = verilog.."assign process_output = gt;\n"
    elseif op==">=" then
      verilog = verilog.."assign process_output = gt || eq;\n"
    elseif op=="<" then
      verilog = verilog.."assign process_output = lt;\n"
    else
      assert(false)
    end
    
verilog = verilog..[[    
endmodule

]]
    s:verilog(verilog)
    return s
  end

  function res.makeTerra()
    return CT.CMPF( res, exp, sig, op )
  end

  return res
end)

C.NegF = J.memoize(function()
    local G = require "generators.core"
    return G.Function{"NegF",types.rv(types.FloatRec32),
      function(i) return G.SubF(R.c(0,types.FloatRec32),i) end}
end)

C.ConcatConst = J.memoize(function( ty, constTy, constValue)
    local G = require "generators.core"
    return G.Function{"ConcatConst_"..tostring(ty).."_"..tostring(constTy).."_"..tostring(constValue),
      types.rv(ty),
      function(i) return R.concat{i,R.c(constTy,constValue)} end}

end)

C.ApplyTo = J.memoize(function( ty, fn, stream )
    local G = require "generators.core"
    return G.Function{"ApplyTo_"..tostring(ty).."_"..tostring(fn.name).."_"..tostring(stream),
      types.rv(ty),
      function(i)
        local tmp = fn(i[stream])
        local out = {}
        for j=1,#ty.list do
          if j-1==stream then
            table.insert( out, tmp )
          else
            table.insert( out, i[j-1] )
          end
        end
        return R.concat(out)
    end}
end)

C.Tile = J.memoize(function( A, W, H, TileW, TileH, X )
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(TileW)=="number")
  assert(type(TileH)=="number")
  assert(W%TileW==0)
  assert(H%TileH==0)

  local ITYPE = types.array2d(A,W,H)
  local inp = R.input(types.rv(types.Par(ITYPE)))

  local tab = {}
  for y=0,H-1 do
    tab[y] = {}
    for x=0,W-1 do
      tab[y][x] = R.apply("idx_"..y.."_"..x, C.index( ITYPE, x, y ), inp)
    end
  end

  local outarr = {}
  for ty=0,(H/TileH)-1 do
    for tx=0,(W/TileW)-1 do
      local out = {}
      for y=0,TileH-1 do
        for x=0,TileW-1 do
          table.insert(out, tab[ty*TileH+y][tx*TileW+x])
        end
      end
      table.insert(outarr, R.concatArray2d("AR_"..ty.."_"..tx,out,TileW,TileH) )
    end
  end

  local fin = R.concatArray2d("fin",outarr,(W/TileW),(H/TileH))

  return RM.lambda("tile", inp, fin )
end)

return C
