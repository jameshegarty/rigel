local R = require "rigel"
local rigel = R
local RM = require "modules"
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

if terralib~=nil then CT=require("examplescommonTerra") end

local C = {}

C.identity = memoize(function(A)
  err( types.isBasic(A),"C.identity: type should be basic, but is: "..tostring(A) )
  local identity = RM.lift( "identity_"..J.verilogSanitize(tostring(A)), A, A, 0, function(sinp) return sinp end, function() return CT.identity(A) end, "C.identity")
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

C.print = memoize(function(A,str)
  err(types.isBasic(A),"C.print: type should be basic, but is: "..tostring(A) )
  
  local function constructPrint(A,symb)
    if A:isUint() or A:isInt() or A:isBits() then
      return {A}, "%d", {symb}
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
        local tT,tS,tV = constructPrint(A.list[1],S.index(symb,i-1))
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
    local printInst = sm:add( S.module.print( types.tuple(typelist), printStr, true):instantiate("printInst") )
    local pipelines = {printInst:process( S.tuple(valuelist) )}
    sm:addFunction( S.lambda("process", inp, inp, "process_output", pipelines,nil,S.CE("process_CE")) )
    sm:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "reset_out") )
    return sm
  end
  
  function res.makeTerra() return CT.print(A,str) end
  
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

C.bitcast = memoize(function(A,B)
  err(types.isType(A),"cast: A should be type")
  err(types.isType(B),"cast: B should be type")
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
  err(types.isType(T),"cast: T should be type")
  --assert(T:isTuple()==false) -- not supported by terra
  local AI = types.array2d(T,N/2)
  local docast = RM.lift( J.sanitize("flatten2_"..tostring(T).."_"..tostring(N)), types.tuple{AI,AI}, types.array2d(T,N), 0, function(sinp) return S.cast(sinp,types.array2d(T,N)) end, function() return CT.flatten2(T,N) end, "C.flatten2" )
  return docast
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

------------
-- return A*B as a darkroom FN. A,B are types
-- returns something of type outputType
C.multiply = memoize(function(A,B,outputType)
  err( types.isType(A), "C.multiply: A must be type")
  err( types.isType(B), "C.multiply: B must be type")
  err( types.isType(outputType), "C.multiply: outputType must be type")

  local partial = RM.lift( J.sanitize("mult_A"..tostring(A).."_B"..tostring(B).."_"..tostring(outputType)), types.tuple {A,B}, outputType, 1,
    function(sinp) return S.cast(S.index(sinp,0),outputType)*S.cast(S.index(sinp,1),outputType) end,
    function() return CT.multiply(A,B,outputType) end,
    "C.multiply" )

  return partial
end)

------------
-- return A*B as a darkroom FN. A,B are types
-- returns something of type outputType
C.multiplyConst = memoize(function(A,constValue)
  err( types.isType(A), "C.multiply: A must be type")

  local partial = RM.lift( J.sanitize("mult_const_A"..tostring(A).."_value"..tostring(constValue)), A, A, 1,
    function(sinp) return sinp*S.constant(constValue,A) end,
    function() return CT.multiplyConst(A,constValue) end,
    "C.multiplyConst" )

  return partial
end)

------------------------------
C.GT = memoize(function(A,B)
  err( types.isType(A), "C.GT: A must be type")
  err( types.isType(B), "C.GT: B must be type")

  local partial = RM.lift( J.sanitize("GT_A"..tostring(A).."_B"..tostring(B)), types.tuple {A,B}, types.bool(), 1,
    function(sinp) return S.gt(S.index(sinp,0),S.index(sinp,1)) end )

  return partial
end)

------------
-- return A*B as a darkroom FN. A,B are types
-- returns something of type outputType
C.GTConst = memoize(function(A,constValue)
  err( types.isType(A), "C.GTConst: A must be type")
  
  local partial = RM.lift( J.sanitize("GT_const_A"..tostring(A).."_value"..tostring(constValue)), A, types.bool(), 1,
                           function(sinp) return S.gt(sinp,S.constant(constValue,A)) end )

  return partial
end)

C.Not = RM.lift( "Not", types.bool(), types.bool(), 0, function(sinp) return S.__not(sinp) end )
C.And = RM.lift( "And", types.tuple{types.bool(),types.bool()}, types.bool(), 0, function(sinp) return S.__and(S.index(sinp,0),S.index(sinp,1)) end )

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

  if async==nil then return C.sum(A,B,outputType,false) end

  err(type(async)=="boolean","C.sum: async must be boolean")

  local delay
  if async then delay = 0 else delay = 1 end

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

-----------------------------
C.rshift = memoize(function(A,const)
  err( types.isType(A),"C.rshift: type should be rigel type")
  err( type(const)=="number" or const==nil,"C.rshift: const should be number or value")
  
  if const~=nil then
    -- shift by a const
    J.err( A:isUint() or A:isInt(), "generators.Rshift: type should be int or uint, but is: "..tostring(A) )
    local mod = RM.lift(J.sanitize("generators_rshift_const"..tostring(const).."_"..tostring(A)), A,A,0,
                        function(inp) return S.rshift(inp,S.constant(const,A)) end)
    return mod
  else
    assert(false)
  end
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
C.removeMSBs = memoize(function(A,bits)
  err( types.isType(A),"C.removeMSBs: type should be rigel type")
  err( type(bits)=="number","C.removeMSBs: bits should be number or value")

  local otype
  if A:isUint() then
    J.err(A.precision>bits,"removeMSBs: can't remove all the bits! attempting to remove "..bits.." bits from "..tostring(A))
    otype = types.uint(A.precision-bits)
  elseif A:isInt() then
    J.err(A.precision>bits,"removeMSBs: can't remove all the bits! attempting to remove "..bits.." bits from "..tostring(A))
    otype = types.int(A.precision-bits)
  else
    J.err( A:isUint() or A:isInt(), "generators.removeMSBs: type should be int or uint, but is: "..tostring(A) )
  end
  
  local mod = RM.lift(J.sanitize("generators_removeMSBs_"..tostring(bits).."_"..tostring(A)), A,otype, 0,
                      function(inp) return S.cast(inp,otype) end)
  return mod
end)

-----------------------------
C.removeLSBs = memoize(function(A,bits)
  err( types.isType(A),"C.removeLSBs: type should be rigel type")
  err( type(bits)=="number","C.removeLSBs: bits should be number or value")

  local otype
  if A:isUint() then
    J.err(A.precision>bits,"removeLSBs: can't remove all the bits! attempting to remove "..bits.." bits from "..tostring(A))
    otype = types.uint(A.precision-bits)
  elseif A:isInt() then
    J.err(A.precision>bits,"removeLSBs: can't remove all the bits! attempting to remove "..bits.." bits from "..tostring(A))
    otype = types.int(A.precision-bits)
    assert(false) -- NYI
  else
    J.err( A:isUint() or A:isInt(), "generators.removeLSBs: type should be int or uint, but is: "..tostring(A) )
  end
  
  local mod = RM.lift(J.sanitize("generators_removeLSBs_"..tostring(bits).."_"..tostring(A)), A,nil,nil,
                      function(inp) return S.cast(S.rshift(inp,S.constant(bits,A)),otype) end)
  return mod
end)

-----------------------------
C.select = memoize(function(ty)
  err(types.isType(ty), "C.select error: input must be type")
  local ITYPE = types.tuple{types.bool(),ty,ty}

  local selm = RM.lift( J.sanitize("C_select_"..tostring(ty)), ITYPE, ty, 1,
    function(sinp) return S.select(S.index(sinp,0), S.index(sinp,1), S.index(sinp,2)) end,nil,
    "C.select" )

  return selm
end)
-----------------------------
C.eq = memoize(function(ty)
  err(types.isType(ty), "C.eq error: input must be type")
  local ITYPE = types.tuple{ty,ty}

  local selm = RM.lift( J.sanitize("C_eq_"..tostring(ty)), ITYPE, types.bool(), 1,
    function(sinp) return S.eq(S.index(sinp,0), S.index(sinp,1)) end, nil,
    "C.eq" )

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
  return RM.lift( "ValueToTrigger_"..tostring(ty), ty, types.null(), 0,
    function(sinp) end, nil,"C.valueToTrigger")
end)

-----------------------------
C.triggerToConstant = memoize(function(ty,value)
  J.err( types.isType(ty), "C.triggerToConstant: type must be type")
  return RM.lift( "TriggerToConstant_"..tostring(ty), types.null(), ty, 0,
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
C.packTapBroad = memoize(function(A,ty,tap,N)
  assert(types.isType(A))
  assert(types.isType(ty))
  assert(type(N)=="number")
  assert(R.isFunction(tap))

  local G = require "generators"
  return G.Module{"PackTap_"..tostring(A).."_"..tostring(ty),A,SDF{1,1},function(i)
                    return R.concat{i,G.Broadcast{N}(tap())} end}
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
    delay = 2
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

  local partial = RM.lift( J.sanitize("absoluteDifference_"..tostring(A).."_"..tostring(outputType)), TY, outputType, 1,
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
    local touint8 = RM.lift( J.sanitize("shiftAndCast_uint" .. from.precision .. "to_uint" .. to.precision.."_shift"..tostring(shift)), from, to, 1,
      function(touint8inp) return S.cast(S.rshift(touint8inp,S.constant(shift,from)), to) end,
      function() return CT.shiftAndCast(from,to,shift) end,
      "C.shiftAndCast")
    return touint8
  else
    local touint8 = RM.lift( J.sanitize("shiftAndCast_uint" .. from.precision .. "to_uint" .. to.precision.."_shift"..tostring(shift)), from, to, 1,
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

  local touint8 = RM.lift( J.sanitize("shiftAndCastSaturate_"..tostring(from).."_to_"..tostring(to).."_shift_"..tostring(shift)), from, to, 1,
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
  if shift==nil then shift=7 end

  local TAP_TYPE = types.array2d( A, ConvWidth, ConvWidth )
---  local TAP_TYPE_CONST = TAP_TYPE:makeConst() XXX
  local TAP_TYPE_CONST = TAP_TYPE

  local INP_TYPE = types.tuple{types.array2d( A, ConvWidth, ConvWidth ),TAP_TYPE_CONST}
  local inp = R.input( INP_TYPE )

---  local packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth,ConvWidth,{A,A:makeConst()}), inp ) XXX
  local packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth,ConvWidth,{A,A}), inp )
---  local conv = R.apply( "partial", RM.map( C.multiply(A,A:makeConst(), types.uint(32)), ConvWidth, ConvWidth ), packed ) XXX
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

  local inp = R.input( types.array2d( A, ConvWidth, ConvHeight ) )
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
  assert(T<=1)
  assert(type(shift)=="number")
  assert(X==nil)

  local inp = R.input( types.array2d( A, ConvWidth*T, ConvHeight ) )
  local r = R.apply( "convKernel", RM.constSeq( tab, A, ConvWidth, ConvHeight, T ) )

  local packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth*T,ConvHeight,{A,A}), R.concat("ptup", {inp,r}) )
  local conv = R.apply( "partial", RM.map( C.multiply(A,A,types.uint(32)), ConvWidth*T, ConvHeight ), packed )
  local conv = R.apply( "sum", RM.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth*T, ConvHeight ), conv )

  local convseq = RM.lambda( "convseq_T"..tostring(1/T), inp, conv )
------------------
  inp = R.input( R.V(types.array2d( A, ConvWidth*T, ConvHeight )) )
  conv = R.apply( "convseqapply", RM.liftDecimate(RM.liftBasic(convseq)), inp)
  conv = R.apply( "sumseq", RM.RPassthrough(RM.liftDecimate(RM.reduceSeq( C.sum(types.uint(32),types.uint(32),types.uint(32),true), T ))), conv )
  conv = R.apply( "touint8", C.RVPassthrough(C.shiftAndCast( types.uint(32), A, shift )), conv )
  conv = R.apply( "arrayop", C.RVPassthrough(C.arrayop( types.uint(8), 1, 1)), conv)

  local convolve = RM.lambda( "convolve_tr_T"..tostring(1/T), inp, conv )

  return convolve
end)

------------
-- returns a function from A[2][Width,Width]->reduceType
-- 'reduceType' is the precision we do the sum
C.SAD = memoize(function( A, reduceType, Width, X )
  assert(X==nil)

  local inp = R.input( types.array2d( types.array2d(A,2) , Width, Width ) )

  local conv = R.apply( "partial", RM.map( C.absoluteDifference(A,reduceType), Width, Width ), inp )
  local conv = R.apply( "sum", RM.reduce( C.sum(reduceType, reduceType, reduceType), Width, Width ), conv )

  local convolve = RM.lambda( J.sanitize("SAD_"..tostring(A).."_reduceType"..tostring(reduceType).."_Width"..tostring(Width)), inp, conv, nil, "C.SAD" )
  return convolve
end)


C.SADFixed = memoize(function( A, reduceType, Width, X )
  local fixed = require "fixed"
  assert(X==nil)
  fixed.expectFixed(reduceType)
  assert(fixed.extractSigned(reduceType)==false)
  assert(fixed.extractExp(reduceType)==0)

  local inp = R.input( types.array2d( types.array2d(A,2) , Width, Width ) )

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

  local inp = R.input( types.array2d( types.array2d(A,2) , Width, Width ) )

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
  local BASE_TYPE = types.array2d( A, T )
  local inp = R.input( BASE_TYPE )

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
  local rawinp = R.input( ITYPE )

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
  local out = R.apply("crop",RM.liftHandshake(RM.liftDecimate(C.cropHelperSeq(fnOutType, internalW, internalH, T, padL+Right+L, padR, B+Top, 0))), out)

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
function C.lutinvert(ty)
  local fixed = require "fixed"
  fixed.expectFixed(ty)
  local signed = fixed.extractSigned(ty)

  --------------------
  local ainp = fixed.parameter("ainp",ty)
  local a = ainp:hist("lutinvert_input")
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
  local bfn = b:toRigelModule("lutinvert_b")
  ---------------

  local inp = R.input( ty )
  local aout = R.apply( "a", afn, inp )
  local aout_float = R.apply("aout_float", C.index(afn.outputType,0), aout)
  local aout_exp = R.apply("aout_exp", C.index(afn.outputType,1), aout)
  local aout_sign
  if signed then aout_sign = R.apply("aout_sign", C.index(afn.outputType,2), aout) end

  local aout_float_lsbs = R.apply("aout_float_lsbs", stripMSB(9), aout_float)

  local inv = R.apply("inv", RM.lut(types.uint(lutbits), types.uint(8), invtable(lutbits)), aout_float_lsbs)
  local out = R.apply( "b", bfn, R.concat("binp",{inv,aout_exp,aout_sign}) )
  local fn = RM.lambda( "lutinvert", inp, out )

  return fn, fn.outputType
end
-------------
C.stencilLinebufferPartialOffsetOverlap = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax, offset, overlap )
  J.map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T<=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  local ST_W = -xmin+1
  local ssr_region = ST_W - offset - overlap
  local stride = ssr_region*T
  assert(stride==math.floor(stride))

  local LB = RM.makeHandshake(RM.linebuffer( A, w, h, 1, ymin ))
  local SSR = RM.liftHandshake(RM.waitOnInput(RM.SSRPartial( A, T, xmin, ymin, stride, true )))

  local inp = R.input( LB.inputType )
  local out = R.apply("LB", LB, inp)
  out = R.apply("SSR", SSR, out)
  out = R.apply("slice", RM.makeHandshake(C.slice(types.array2d(A,ST_W,-ymin+1), 0, stride+overlap-1, 0,-ymin)), out)

  return RM.lambda("stencilLinebufferPartialOverlap",inp,out)
end)

-------------
-- VRLoad: if true, make the load function be HandshakeVR
C.fifo = memoize(function(ty,size,nostall,csimOnly,VRLoad,X)
  err( types.isType(ty), "C.fifo: type must be a type" )
  err( R.isBasic(ty), "C.fifo: type must be basic type, but is: "..tostring(ty) )
  err( type(size)=="number" and size>0, "C.fifo: size must be number > 0" )
  err( nostall==nil or type(nostall)=="boolean", "C.fifo: nostall must be boolean")
  err( csimOnly==nil or type(csimOnly)=="boolean", "C.fifo: csimOnly must be boolean")
  err( VRLoad==nil or type(VRLoad)=="boolean","C.fifo: VRLoad should be boolean")
  err( X==nil, "C.fifo: too many arguments" )
  --err( ty~=types.null(), "C.fifo: NYI - FIFO of 0 bit type" )

  local inp, regs
  if ty:verilogBits()==0 then
    inp = R.input(types.HandshakeTrigger)
    regs = {R.instantiate("f1",RM.triggerFIFO())}
  else
    inp = R.input(R.Handshake(ty))
    regs = {R.instantiate("f1",RM.fifo(ty,size,nostall,nil,nil,nil,csimOnly,VRLoad))}
  end
  
  local st = R.applyMethod("s1",regs[1],"store",inp)
  local ld = R.applyMethod("l1",regs[1],"load")
  return RM.lambda("C_FIFO_"..tostring(ty).."_size"..tostring(size).."_nostall"..tostring(nostall).."_VR"..tostring(VRLoad), inp, R.statements{ld,st}, regs, "C.fifo", {size=size} )
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
-- typelist should be a table of pure types
C.SoAtoAoSHandshake = memoize(function( W, H, typelist, X )
  assert(X==nil)
  local f = modules.SoAtoAoS(W,H,typelist)
  f = modules.makeHandshake(f)

  return C.compose( J.sanitize("SoAtoAoSHandshake_W"..tostring(W).."_H"..tostring(H).."_"..tostring(typelist)), f, modules.packTuple( J.map(typelist, function(t) return types.array2d(t,W,H) end) ) )
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
C.downsampleSeq = memoize(function( A, W, H, T, scaleX, scaleY, framed, X )
  err( types.isType(A), "C.downsampleSeq: A must be type")
  err( type(W)=="number", "C.downsampleSeq: W must be number")
  err( type(H)=="number", "C.downsampleSeq: H must be number")
  err( type(T)=="number", "C.downsampleSeq: T must be number")
  err( T>0, "C.downsampleSeq: T must be >0")
  err( type(scaleX)=="number", "C.downsampleSeq: scaleX must be number")
  err( type(scaleY)=="number", "C.downsampleSeq: scaleY must be number")
  err( scaleX>=1, "C.downsampleSeq: scaleX must be >=1")
  err( scaleY>=1, "C.downsampleSeq: scaleY must be >=1")
  err( X==nil, "C.downsampleSeq: too many arguments" )

  err( W%scaleX==0,"C.downsampleSeq: NYI - scaleX does not divide W")
  err( H%scaleY==0,"C.downsampleSeq: NYI - scaleY does not divide H")
  
  if framed==nil then framed=false end
  err( type(framed)=="boolean", "C.donwsampleSeq: framed must be boolean" )
    
  if scaleX==1 and scaleY==1 then
    return C.identity(A)
  end

  local inp = rigel.input( rigel.V(types.array2d(A,T)) )
  local out = inp
  if scaleY>1 then
    out = rigel.apply("downsampleSeq_Y", modules.liftDecimate(modules.downsampleYSeq( A, W, H, T, scaleY )), out)
  end
  if scaleX>1 then
    local mod = modules.liftDecimate(modules.downsampleXSeq( A, W, H, T, scaleX ))

    if scaleY>1 then mod=modules.RPassthrough(mod) end

    out = rigel.apply("downsampleSeq_X", mod, out)
    local downsampleT = math.max(T/scaleX,1)
    if downsampleT<T then
      -- technically, we shouldn't do this without lifting to a handshake - but we know this can never stall, so it's ok
      out = rigel.apply("downsampleSeq_incrate", modules.RPassthrough(modules.changeRate(A,1,downsampleT,T)), out )
    elseif downsampleT>T then assert(false) end
  end
  local res = modules.lambda( J.sanitize("downsampleSeq_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_scaleX"..tostring(scaleX).."_scaleY"..tostring(scaleY).."_framed"..tostring(framed)), inp, out,nil,"C.downsampleSeq")

  if framed then
    res.inputType = res.inputType:addDim(W,H,true)
    res.outputType = res.outputType:addDim(math.ceil(W/scaleX),math.ceil(H/scaleY),true)
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
    inner = C.compose( J.sanitize("upsampleSeq_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_scaleX"..tostring(scaleX).."_scaleY"..tostring(scaleY)), f, modules.liftHandshake(modules.upsampleYSeq( A, W, H, T, scaleY )),nil,"C.upsampleSeq")
  end

    return inner
end)


-- takes A to A[T] by duplicating the input
C.broadcast = memoize(function(A,W,H)
  err( types.isType(A), "C.broadcast: A must be type A")
  err( types.isBasic(A), "C.broadcast: type should be basic, but is: "..tostring(A))
  err( type(W)=="number", "broadcast: W should be number")
  if H==nil then return C.broadcast(A,W,1) end
  err( type(H)=="number", "broadcast: H should be number")

  local OT = types.array2d(A, W, H)

  return modules.lift( J.sanitize("Broadcast_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H)),A,OT,0,
    function(sinp) return S.cast(S.tuple(J.broadcast(sinp,W*H)),OT) end,
    function() return CT.broadcast(A,W,H,OT) end,
    "C.broadcast")
end)
C.arrayop=C.broadcast

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
C.cropHelperSeq = memoize(function( A, W, H, T, L, R, B, Top, X )
  err(X==nil, "cropHelperSeq, too many arguments")
  err(type(T)=="number","T must be number")
  if L%T==0 and R%T==0 then return modules.cropSeq( A, W, H, T, L, R, B, Top ) end

  err( (W-L-R)%T==0, "cropSeqHelper, (W-L-R)%T~=0, W="..tostring(W)..", L="..tostring(L)..", R="..tostring(R)..", T="..tostring(T))

  local RResidual = R%T
  local inp = rigel.input( types.array2d( A, T ) )
  local out = rigel.apply( "SSR", modules.SSR( A, T, -RResidual, 0 ), inp)
  out = rigel.apply( "slice", C.slice( types.array2d(A,T+RResidual), 0, T-1, 0, 0), out)
  out = rigel.apply( "crop", modules.cropSeq(A,W,H,T,L+RResidual,R-RResidual,B,Top), out )

  return modules.lambda( J.sanitize("cropHelperSeq_"..tostring(A).."_W"..W.."_H"..H.."_T"..T.."_L"..L.."_R"..R.."_B"..B.."_Top"..Top), inp, out )
end)


C.stencilLinebuffer = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax, framed, X )
  err(types.isType(A), "stencilLinebuffer: A must be type, but is: "..tostring(A))

  err(type(T)=="number","stencilLinebuffer: T must be number")
  err(type(w)=="number","stencilLinebuffer: w must be number, but is: "..tostring(w))
  err(type(h)=="number","stencilLinebuffer: h must be number")
  err(type(xmin)=="number","stencilLinebuffer: xmin must be number")
  err(type(xmax)=="number","stencilLinebuffer: xmax must be number")
  err(type(ymin)=="number","stencilLinebuffer: ymin must be number")
  err(type(ymax)=="number","stencilLinebuffer: ymax must be number")

  err(T>=1, "stencilLinebuffer: T must be >=1");
  err(w>0,"stencilLinebuffer: w must be >0");
  err(h>0,"stencilLinebuffer: h must be >0");
  err(xmin<=xmax,"stencilLinebuffer: xmin("..tostring(xmin)..")>xmax("..tostring(xmax)..")")
  err(ymin<=ymax,"stencilLinebuffer: ymin("..tostring(ymin)..") must be <= ymax("..tostring(ymax)..")")
  err(xmax==0,"stencilLinebuffer: xmax must be 0")
  err(ymax==0,"stencilLinebuffer: ymax must be 0")

  err(X==nil,"C.stencilLinebuffer: Too many arguments")
  
  local SSRFn = modules.SSR( A, T, xmin, ymin)

  if framed then
    SSRFn = modules.mapFramed(SSRFn,w/T,h,false)
  end
  
  return C.compose( J.sanitize("stencilLinebuffer_A"..tostring(A).."_w"..w.."_h"..h.."_T"..T.."_xmin"..tostring(math.abs(xmin)).."_ymin"..tostring(math.abs(ymin))), SSRFn, modules.linebuffer( A, w, h, T, ymin, framed ), "C.stencilLinebuffer" )
end)

-- this is basically the same as a stencilLinebuffer, but implemend using a register chain instead of rams
C.stencilLinebufferRegisterChain = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax )
  err(types.isType(A), "stencilLinebufferRegisterChain: A must be type")

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

  local I = R.input( types.array2d(A,T) )
  local SSRSize = w*(-ymin)-xmin+1
  local lb = modules.SSR(A,T,-SSRSize,0)(I)

  local tab = {}
  for y=ymin,0 do
    for x=xmin,0 do
      local idx = y*w+x
      -- SSR module stores values in opposite order of what we want
      local ridx = SSRSize+idx
      table.insert(tab, C.index(lb.type,ridx,0)(lb) )
    end
  end
  
  local out = C.tupleToArray(A,-xmin+1,-ymin+1)(R.concat("srtab",tab))

  return modules.lambda( J.sanitize("StencilLinebufferRegisterChain_A"..tostring(A).."_w"..w.."_h"..h.."_T"..T.."_xmin"..tostring(math.abs(xmin)).."_ymin"..tostring(math.abs(ymin)) ), I, out )
end)

C.stencilLinebufferPartial = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax )
  J.map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T<=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  -- SSRPartial need to be able to stall the linebuffer, so we must do this with handshake interfaces. Systolic pipelines can't stall each other
  return C.compose( J.sanitize("stencilLinebufferPartial_A"..tostring(A).."_W"..tostring(w).."_H"..tostring(h)), modules.liftHandshake(modules.waitOnInput(modules.SSRPartial( A, T, xmin, ymin ))), modules.makeHandshake(modules.linebuffer( A, w, h, 1, ymin )), "C.stencilLinebufferPartial" )
end)


-- purely wiring. This should really be implemented as a lift.
-- framed: this fn is a bit strange (actually introduces a new dimension), so can't use mapFramed
-- instead, special case this
C.unpackStencil = memoize(function( A, stencilW, stencilH, T, arrHeight, framed, framedW, framedH, X )
  assert(types.isType(A))
  assert(type(stencilW)=="number")
  err(stencilW>0,"unpackStencil: stencilW must be >0, but is:"..tostring(stencilW))
  assert(type(stencilH)=="number")
  err(stencilH>0,"unpackStencil: stencilH must be >0, but is:"..tostring(stencilH))
  assert(type(T)=="number")
  assert(T>=1)
  err(arrHeight==nil, "Error: NYI - unpackStencil on non-height-1 arrays")
  err( framed==nil or type(framed)=="boolean", "unpackStencil: framed must be nil or bool")
  if framed==nil then framed=false end
  assert(X==nil)

  local res = {kind="unpackStencil", stencilW=stencilW, stencilH=stencilH,T=T,generator="C.unpackStencil"}
  res.inputType = types.array2d( A, stencilW+T-1, stencilH)
  res.outputType = types.array2d( types.array2d( A, stencilW, stencilH), T )

  if framed then
    err( type(framedW)=="number", "unpackStencil: framedW must be nil or number")
    err( type(framedH)=="number", "unpackStencil: framedH must be nil or number")
    
    res.inputType = res.inputType:addDim(framedW/T,framedH,false)
    res.outputType = res.outputType:addDim(framedW,framedH,true)
  end
  
  res.sdfInput, res.sdfOutput = SDF{1,1}, SDF{1,1}
  res.stateful = false
  res.delay=0
  res.name = J.sanitize("unpackStencil_"..tostring(A).."_W"..tostring(stencilW).."_H"..tostring(stencilH).."_T"..tostring(T))

  if terralib~=nil then res.terraModule = CT.unpackStencil(res, A, stencilW, stencilH, T, arrHeight) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    
    local sinp = S.parameter("inp", rigel.extractData(res.inputType) )
    local out = {}
    for i=1,T do
      out[i] = {}
      for y=0,stencilH-1 do
        for x=0,stencilW-1 do
          out[i][y*stencilW+x+1] = S.index( sinp, x+i-1, y )
        end
      end
    end
    
    systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple(J.map(out,function(n) return S.cast( S.tuple(n), types.array2d(A,stencilW,stencilH) ) end)), rigel.extractData(res.outputType) ), "process_output", nil, nil, S.CE("process_CE") ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)


-- if index==true, then we return a value, not an array
-- indices are inclusive
C.slice = memoize(function( inputType, idxLow, idxHigh, idyLow, idyHigh, index, X )
  err( types.isType(inputType),"slice first argument must be type" )
  err( type(idxLow)=="number", "slice idxLow must be number")
  err( type(idxHigh)=="number", "slice idxHigh must be number")
  err( index==nil or type(index)=="boolean", "index must be bool")
  err( X==nil, "C.slice: too many arguments")

  if inputType:isTuple() then
    assert( idxLow < #inputType.list )
    assert( idxHigh < #inputType.list )
    assert( idxLow == idxHigh ) -- NYI
    assert( index )
    local OT = inputType.list[idxLow+1]

    return modules.lift( J.sanitize("index_"..tostring(inputType).."_"..idxLow), inputType, OT, 0,
      function(systolicInput) return S.index( systolicInput, idxLow ) end,
      function() return CT.sliceTup(inputType,OT,idxLow) end,
      "C.slice")

  elseif inputType:isArray() then
    local W = (inputType:arrayLength())[1]
    local H = (inputType:arrayLength())[2]
    err(idxLow<W,"slice: idxLow>=W, idxLow="..tostring(idxLow)..",W="..tostring(W))
    err(idxHigh<W, "slice: idxHigh>=W")
    err(type(idyLow)=="number", "slice:idyLow must be number")
    err(type(idyHigh)=="number","slice:idyHigh must be number")
    err(idyLow<H, "slice: idyLow must be <H")
    err(idyHigh<H, "slice: idyHigh must be <H")
    assert(idxLow<=idxHigh)
    assert(idyLow<=idyHigh)
    local OT

    if index then
      OT = inputType:arrayOver()
    else
      OT = types.array2d( inputType:arrayOver(), idxHigh-idxLow+1, idyHigh-idyLow+1 )
    end

    return modules.lift( J.sanitize("slice_type"..tostring(inputType).."_xl"..idxLow.."_xh"..idxHigh.."_yl"..idyLow.."_yh"..idyHigh.."_index"..tostring(index)), inputType, OT, 0,
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
  else
    err(false, "C.index input must be tuple or array but is "..tostring(inputType))
  end
end)

function C.index( inputType, idx, idy, X )
  err( types.isType(inputType), "first input to index must be a type" )
  err( type(idx)=="number", "index idx must be number")
  assert(X==nil)
  if idy==nil then idy=0 end
  return C.slice( inputType, idx, idx, idy, idy, true )
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

  local name = J.sanitize("GeneralizedChangeRate_"..tostring(inputBitsPerCyc).."_"..tostring(outputBitsPerCyc).."_"..tostring(minTotalInputBits_orig).."_"..tostring(minTotalOutputBits_orig))

  if inputBitsPerCyc==outputBitsPerCyc then
    local bts = minTotalInputBits:max(minTotalOutputBits)

    bts = Uniform.upToNearest(inputFactor,bts)
    bts = Uniform.upToNearest(outputFactor,bts)

    assert( (bts%inputFactor):eq(0):assertAlwaysTrue() )
    assert( (bts%outputFactor):eq(0):assertAlwaysTrue() )
    
    return {RM.makeHandshake(C.identity(types.bits(inputBitsPerCyc))),bts}
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

      return {RM.lambda(name,inp,out),bts}
    else
      assert(J.isPowerOf2(outputBitsPerCyc)) -- NYI
      local shifterBits = inputBitsPerCyc
      while shifterBits%outputBitsPerCyc~=0 do shifterBits = shifterBits*2 end

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

      return {RM.lambda(name,inp,out),bts}
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

      return {RM.lambda(name,inp,out),bts}
    else
      assert(J.isPowerOf2(inputBitsPerCyc)) -- NYI
      local shifterBits = outputBitsPerCyc
      while shifterBits%inputBitsPerCyc~=0 do shifterBits = shifterBits*2 end
      print("SHIFTBITS",shifterBits)
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

      return {RM.lambda(name,inp,out),bts}
    end
  end
  print(inputBitsPerCyc,outputBitsPerCyc)
  assert(false)
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

C.plusConst = memoize(function(ty, value_orig)
  err(types.isType(ty),"plus100: expected type input")
  local value = Uniform(value_orig)
  err( value:isNumber(),"plusConst expected numeric input")

  local globals = {}
  value:appendRequires(globals)
  
  local plus100mod = RM.lift( J.sanitize("plus_"..tostring(ty).."_"..tostring(value)), ty,ty , 10, function(plus100inp) return plus100inp + value:toSystolic(ty) end, function() return CT.plusConsttfn(ty,value) end, nil,nil,globals )
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

  err( R.isPlainFunction(t[1]) or R.isInstanceCallsite(t[1]),"C.linearPipeline: first function in pipe must have known type (ie must not be a generator). fn: "..tostring(t[1]) )
  local inp = R.input( t[1].inputType, rate )
  local out = inp

  for k,v in ipairs(t) do
    out = R.apply("linearPipe"..k,v,out)
  end

  return RM.lambda( modulename, inp, out, instances )
end

-- Hacky module for internal use: just convert a Handshake to a HandshakeFramed
C.handshakeToHandshakeFramed = memoize(
  function( A, mixed, dims, X )
    err( type(dims)=="table", "handshakeToHandshakeFramed: dims should be table")
    err( type(mixed)=="boolean", "handshakeToHandshakeFramed: mixed should be bool")
    assert(X==nil)
    err(R.isHandshake(A),"handshakeToHandshakeFramed: input should be handshake")
    local res = {inputType=A,outputType=types.HandshakeFramed(A.params.A,mixed,dims),sdfInput=SDF{1,1},sdfOutput=SDF{1,1},stateful=false}
    local nm = "HandshakeToHandshakeFramed_"..tostring(A).."_mixed"..tostring(mixed).."_dims"..tostring(dims)
    res.name=J.sanitize(nm)

    function res.makeSystolic()
      local sm = Ssugar.moduleConstructor(res.name):onlyWire(true)
      local r = S.parameter("ready_downstream",types.bool())
      sm:addFunction( S.lambda("ready", r, r, "ready") )
      local I = S.parameter("process_input", R.lower(A) )
      sm:addFunction( S.lambda("process",I,I,"process_output") )
      --sm:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "reset_out") )
      return sm
    end
    function res.makeTerra()
      return CT.handshakeToHandshakeFramed(res,A,mixed,dims)
    end
    
    return rigel.newFunction(res)
  end)

C.stripFramed = memoize(
  function( A, X)
    err(A:is("HandshakeFramed") or A:is("HandshakeArrayFramed"),"StripFramed: input should be framed, but is: "..tostring(A) )
    assert(X==nil)

    
    local res = {inputType=A,sdfInput=SDF{1,1},sdfOutput=SDF{1,1},stateful=false}

    if A:is("HandshakeFramed") then
      res.outputType = types.Handshake(A.params.A)
    elseif A:is("HandshakeArrayFramed") then
      res.outputType = types.HandshakeArray(A.params.A,A.params.W,A.params.H)
    else
      assert(false)
    end
    
    res.name=J.sanitize("StripFramed_"..tostring(A))
    
    function res.makeSystolic()
      local sm = Ssugar.moduleConstructor(res.name):onlyWire(true)
      local r = S.parameter("ready_downstream",types.bool())
      sm:addFunction( S.lambda("ready", r, r, "ready") )
      local I = S.parameter("process_input", R.lower(A) )
      sm:addFunction( S.lambda("process",I,I,"process_output") )

      return sm
    end
    function res.makeTerra()
      return CT.stripFramed(res,A)
    end
    
    return rigel.newFunction(res)

  end)

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
    local G = require "generators"
    return G.Module{"SortCompare_"..tostring(A).."_op"..tostring(op.name), types.array2d(A,2),
      function(inp)
        local res = op(inp[0],inp[1])
        return G.Sel(res,inp,G.TupleToArray(inp[1],inp[0]))
      end}
  end)

-- takes in an array whose two halves are sorted. Returns full array sorted.
-- see http://www.iti.fh-flensburg.de/lang/algorithmen/sortieren/networks/oemen.htm
C.oddEvenMerge = memoize(
  function(A,N,op)
    local G = require "generators"
    assert(N>=2)
    assert(J.isPowerOf2(N))
    if N==2 then
      return C.sortCompare(A,op)
    else
      return G.Module{"OddEvenMerge_"..tostring(A).."_N"..tostring(N).."_op"..tostring(op.name), types.array2d(A,N),
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
    local G = require "generators"
    assert(N>0)
    assert(J.isPowerOf2(N))
    if N==1 then
      return G.Identity{types.array2d(A,N)}
    else
      return G.Module{"OddEvenMergeSort_"..tostring(A).."_N"..tostring(N).."_op"..tostring(op.name), types.array2d(A,N),
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
  function(filename,totalBytes,itemBytes,stride,offset,readPort,readAddr,readFn)
    -- stride,offset is given as # of items
    local G = require "generators"
    local SOC = require "soc"
    assert(totalBytes%(itemBytes*stride)==0)
    assert(itemBytes%8==0)
    assert( R.isFunction(readFn) )
    
    local Nreads = (totalBytes/(itemBytes*stride))
    local res = G.Module{"StridedReader_totalBytes"..tostring(totalBytes).."_itemBytes"..tostring(itemBytes).."_stride"..tostring(stride).."_offset"..tostring(offset), types.HandshakeTrigger,
      function(inp)
        print("MAKESTRIDED",stride,offset)
        local cnt = C.triggerUp(Nreads)(inp)
        local cnt = G.HS{RM.counter(types.uint(32), Nreads)}(cnt)
        cnt = G.HS{G.Mul{stride*itemBytes}}(cnt)
        local addr = G.HS{G.Add{offset*itemBytes}}(cnt)
        --return SOC.read(filename,totalBytes,types.bits(itemBytes*8))(addr)
        return SOC.axiReadBytes(filename,itemBytes,readPort,readAddr,readFn)(addr)
      end}

    return res
  end)

-- generate N DMA controllers to be able to read things with higher BW than a single axi port can
C.AXIReadPar = memoize(
  function(filename,W,H,ty,V,noc) -- Nbits: # of bits to read in parallel
    local G = require "generators"
    local SOC = require "soc"
    assert( (ty:verilogBits()*V)%64==0)
    local N = (ty:verilogBits()*V)/64
    assert((W*H)%N==0)

    local startAddr = SOC.currentAddr
    local startPort = SOC.currentMAXIReadPort
    
    local totalBytes = W*H*(ty:verilogBits()/8)
    local res = G.Module{"AXIReadPar_"..tostring(W), types.HandshakeTrigger,
      function(inp)
        local inpb = G.FanOut{N}(inp)
        local out = {}
        for i=0,N-1 do
          print("IMPBI",inpb[i],i,inpb)
          local tmp = C.StridedReader(filename,totalBytes,8,N,i,SOC.currentMAXIReadPort,SOC.currentAddr,noc["read"..J.sel(i==0,"",tostring(i))])(inpb[i])
          tmp = G.FIFO{128}(tmp)
          table.insert(out, tmp)
          SOC.currentMAXIReadPort = SOC.currentMAXIReadPort+1
        end
        SOC.currentAddr = SOC.currentAddr+totalBytes

        out = G.FanIn(unpack(out))
        print("OUTT",out.type)
        return G.HS{C.bitcast(out.type.params.A,types.array2d(ty,V))}(out)
      end}

    res.globalMetadata["MAXI"..startPort.."_read_W"] = W
    res.globalMetadata["MAXI"..startPort.."_read_H"] = H
    res.globalMetadata["MAXI"..startPort.."_read_V"] = V
    res.globalMetadata["MAXI"..startPort.."_read_type"] = tostring(ty)
    res.globalMetadata["MAXI"..startPort.."_read_bitsPerPixel"] = ty:verilogBits()
    res.globalMetadata["MAXI"..startPort.."_read_address"] = startAddr

    -- avoid double loading the image
    for i=1,N-1 do
      res.globalMetadata["MAXI"..i.."_read_filename"] = nil
    end
    
    return res
  end)

-- collect the number of tokens seen, and write it to a global
C.tokenCounterReg = memoize(
  function( A, regGlobal, N)
    J.err( types.isType(A),"tokenCounterReg: a must be type" )
    J.err( A:is("Handshake"),"tokenCounterReg: input should be handshaked, but is: "..tostring(A))
    J.err( N==nil or type(N)=="number","tokenCounterReg: N must be number" )
    J.err( R.isFunction(regGlobal),"tokenCounterReg: reg should be fn")
    
    if N==nil then
      N = math.pow(2,32)-1
    end
      
    local G = require "generators"

    local res = G.Module{"TokenCounterReg_"..tostring(A).."_"..tostring(regGlobal).."_"..tostring(N),A,
      function(inp)
        local inpb = G.FanOut{2}(inp)
        local ct = G.HS{C.valueToTrigger(A.params.A)}(inpb[1])
        local cnt = G.HS{RM.counter(types.uint(32),N)}(ct)
        cnt = G.HS{G.Add{1}}(cnt)
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
    
    --fns[fnname] = S.lambda(fnname,inp,out,J.sel(R.isFunction(mod),fnname.."_output",fnname))
    fns[fnname] = Ssugar.lambdaConstructor(fnname,types.lower(fn.inputType),fnname.."_input")
    if fn.outputType~=types.null() then
      fns[fnname]:setOutput(S.constant(types.lower(fn.outputType):fakeValue(),types.lower(fn.outputType)),J.sel(R.isFunction(mod),fnname.."_output",fnname))
    end
    delays[fnname]=0

    if types.isHandshakeAny(fn.inputType) or types.isHandshakeAny(fn.outputType) then
      local inp
      local readyDownstreamFnName = fnname.."_ready_downstream"
      if R.isFunction(mod) then readyDownstreamFnName = "ready_downstream" end -- hack for historic reasons
      
      if fn.outputType==types.null() then
        inp = S.parameter(readyDownstreamFnName,types.null() )
      else
        inp = S.parameter(readyDownstreamFnName,types.extractReady(fn.outputType) )
      end

      local out
      if fn.inputType~=types.null() then
        out = S.constant(types.extractReady(fn.inputType):fakeValue(),types.extractReady(fn.inputType))
      end

      local readyFnName = fnname.."_ready"
      if R.isFunction(mod) then readyFnName = "ready" end -- hack for historic reasons
      fns[readyFnName] = S.lambda(readyFnName,inp,out,readyFnName)
      delays[readyFnName]=0
    end
  end

  local instances = {}
  local externalInstances = {}
  for ic,_ in pairs(mod.requires) do
    local inst = ic.instance:toSystolicInstance()
    if externalInstances[inst]==nil then externalInstances[inst]={} end
    externalInstances[inst][ic.functionName]=1
    --instances[inst]=1

    local fn = ic.instance.module.functions[ic.functionName]
    if types.isHandshakeAny(fn.inputType) or types.isHandshakeAny(fn.outputType) then
      externalInstances[inst][ic.functionName.."_ready"]=1
    end
  end

  if mod.instanceMap~=nil then
    for inst,_ in pairs(mod.instanceMap) do
      assert(R.isInstance(inst))

      local sinst = inst:toSystolicInstance()
      instances[sinst]=1

      for _,fn in pairs(sinst.module.functions) do
        if R.isFunction(mod) then
          fns.process:addPipeline(sinst[fn.name](sinst,S.constant(fn.inputParameter.type:fakeValue(),fn.inputParameter.type)))
        else
          assert(false) -- NYI
        end
      end
    end
  end
  
  if mod.stateful then
    fns.reset = S.lambda("reset",S.parameter("rnil",types.null()),nil,"reset_out",{},S.parameter("reset",types.bool()))
  end

  for k,v in pairs(fns) do
    if Ssugar.isFunctionConstructor(v) then
      fns[k] = v:complete()
    end
  end
  
  return S.module.new( mod.name,fns,J.invertAndStripKeys(instances),true,nil,"",delays, externalInstances)
end

-- this will import a Verilog file as a module... the module is basically a stub,
-- this basically only serves to include the source when we lower to verilog
-- dependencyList is a list of modules we depend on
C.VerilogFile = J.memoize(function(filename,dependencyList)
  if dependencyList==nil then dependencyList={} end
    
  local res = {inputType=types.null(), outputType=types.null(), stateful=false, sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, name = J.sanitize(filename) }
  res.instanceMap={}
  for _,d in pairs(dependencyList) do
    assert(R.isModule(d))
    res.instanceMap[d:instantiate()]=1
  end
  
  res = R.newFunction(res)
  
  local function makeSystolic()
    local s = C.automaticSystolicStub(res)
    s.verilog = J.fileToString(R.path..filename)
    s.verilog = s.verilog:gsub([[`include "[%w_\.]*"]],"")
    s.verilog = "/* verilator lint_off WIDTH */\n/* verilator lint_off CASEINCOMPLETE */\n"..s.verilog.."\n/* verilator lint_on CASEINCOMPLETE */\n/* verilator lint_on WIDTH */"
    return s
  end

  return R.newModule(J.sanitize(filename),{process=res},false,makeSystolic,nil)
end)
 
-- you should only use this if it's safe! (on the output of fns)
C.VRtoRVRaw = J.memoize(function(A)
  err( types.isBasic(A), "expected basic type" )
  local res = {inputType=types.HandshakeVR(A),outputType=types.Handshake(A),sdfInput=SDF{1,1},sdfOutput=SDF{1,1},stateful=false}
  res.name = J.sanitize("VRtoRVRaw_"..tostring(A))

  function res.makeSystolic()
    local sm = Ssugar.moduleConstructor(res.name):onlyWire(true)
    local r = S.parameter("ready_downstream",types.bool())
    sm:addFunction( S.lambda("ready", r, r, "ready") )
    local I = S.parameter("process_input", R.lower(types.Handshake(A)) )
    sm:addFunction( S.lambda("process",I,I,"process_output") )
    return sm
  end

  return rigel.newFunction(res)
end)

-- fn should be HSVR, and this wraps to return a plain HS function
C.LiftVRtoRV = J.memoize(function(fn)
  err( types.isHandshakeVR(fn.inputType), "LiftVRtoRV: fn input should be HandshakeVR, but is: "..tostring(fn.inputType) )
  err( types.isHandshakeVR(fn.outputType), "LiftVRtoRV: fn output should be HandshakeVR" )
  return C.linearPipeline({C.fifo(types.extractData(fn.inputType),128,nil,nil,true),fn,C.VRtoRVRaw(types.extractData(fn.outputType))},"LiftVRtoRV_"..fn.name)
end)

return C
