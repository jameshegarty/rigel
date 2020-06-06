local R = require "rigel"
local J = require "common"
local types = require "types"
local T = types
local P = require "params"
local RM = require "generators.modules"
local RS = require "rigelSimple"
local C = require "generators.examplescommon"
local S = require "systolic"
local SOC = require "generators.soc"
local Uniform = require "uniform"
local SDF  = require "sdf"

local __unnamedID = 0

local generators = {}

-- takes A to A[N]
-- to simplify things, we only take in fully parallel types
generators.Broadcast = R.FunctionGenerator("core.Broadcast",{"type","rate","size"},{},
function(args)
  local V = J.canonicalV( args.rate, args.size )

  local inputType = args.type:deSchedule()
  
  if V==args.size then
    return C.broadcast( inputType, args.size[1], args.size[2] )
  elseif V:eq(0,0)==false then
    local sizeW, sizeH = Uniform(args.size[1]):toNumber(), Uniform(args.size[2]):toNumber()
    
    local seq = (sizeW*sizeH)/(V[1]*V[2])
    assert( type(seq)=="number")
    assert( type(V[2])=="number" and V[2]==1 ) -- NYI

    local res = C.compose(J.verilogSanitize("Generators_Broadcast_Parseq_"..tostring(args.size)),RM.makeHandshake(C.broadcast(inputType,V[1],1)), RM.upsampleXSeq(inputType,0,seq) )
    
    -- hackity hack
    res.outputType = T.RV(T.ParSeq(T.Array2d(inputType,V),args.size))
    
    return res
  elseif V:eq(0,0) then
    -- hack: convert upsampleXSeq to write out a W,H size
    local res = generators.Function{
      "UpsampleXSeq_HACK_"..tostring(args.T).."_X"..tostring(args.size[1]).."_Y"..tostring(args.size[2]), SDF{1,1},
      T.RV(inputType),function(inp) return RM.upsampleXSeq(inputType,0,args.size[1]*args.size[2],true)(inp) end}
    
    local ot = T.RV(T.Seq(T.Par(inputType),args.size))
    assert(ot:lower()==res.outputType:lower())
    res.outputType = ot
    return res
  else
    print("OPT",args.opt)
    assert(false)
  end
end,nil,false)


generators.BroadcastSeq = R.FunctionGenerator("core.BroadcastSeq",{"type","rate","size","number"},{},
function(args)
  assert(args.size[2]==1)
  if args.number==0 then
    return R.FunctionGenerator("core.BroadcastSeq_internal",{"type","rate","size","number"},{},
                               function(a) return RM.upsampleXSeq(a.T,0,args.size[1],true) end,
      P.DataType("T") ):complete(args)
  else
    assert(false)
  end
end)

-- Hack! clamp a variable sized array to a particular size
generators.ClampToSize = R.FunctionGenerator("core.ClampToSize",{"size"},{},
function(args)
  local res = generators.Function{"ClampToSize_W"..tostring(args.size[1]).."_H"..tostring(args.size[2]), T.RV(T.Array2d(args.S,args.InSize[1],args.InSize[2],0,0,true)),SDF{1,1},function(inp) return inp end}

  assert(R.isPlainFunction(res))
  local newType = T.RV(T.Array2d(args.S,args.size[1],args.size[2],0,0))
  assert(res.outputType:lower()==newType:lower())
  res.outputType = newType
  
  return res
end,
T.Array2d( P.ScheduleType("S"),P.SizeValue("InSize"),R.Size(0,0),true) )

-- bits to unsigned
generators.BtoU = R.FunctionGenerator("core.BtoU",{},{},
function(args)
  return C.cast( args.T, types.uint( args.T.precision ))
end, P.BitsType("T") )


-- convert Uint to Int
generators.UtoI = R.FunctionGenerator("core.UtoI",{},{},
function(args)
  return C.cast( args.T, types.Int( args.T.precision, args.T.exp ))
end, P.UintType("T") )


-- convert Int to Uint
generators.ItoU = R.FunctionGenerator("core.ItoU",{},{},
function(args)
  return C.cast( args.T, types.Uint( args.T.precision, args.T.exp ))
end, P.IntType("T") )

generators.Bitcast = R.FunctionGenerator("core.Bitcast",{"type","rate","type1"},{},
function(args)
  return C.bitcast( args.type:deInterface(), args.type1)
end, nil, false )


generators.LUT = R.FunctionGenerator("core.LUT",{"type1","luaFunction"},{},
function(args)
  local vals = J.map(J.range(0,math.pow(2,args.T:verilogBits())-1),args.luaFunction)
  return RM.lut(args.T,args.type1,vals)
end, P.UintType("T") )

generators.Print = R.FunctionGenerator("core.Print",{"type","rate"},{"string","bool"},
function(args)
  return C.print( args.T, args.string, args.bool )
end,
P.DataType("T") )

generators.FlattenBits = R.FunctionGenerator("core.FlattenBits",{"type"},{},function(args) return C.flattenBits(args.type) end)

generators.PartitionBits = R.FunctionGenerator("core.PartitionBits",{"type","number"},{},function(args) return C.partitionBits(args.type,args.number) end)

generators.Rshift = R.FunctionGenerator("core.Rshift",{"type","rate"},{"number"}, function(args)
  if args.number~=nil then
    return R.FunctionGenerator("core.Rshift",{},{"number"},function(a) return C.rshiftConst( a.T, args.number ) end, P.NumberType("T") ):complete(args)
  else
    return R.FunctionGenerator("core.Rshift",{},{},function(a) return C.rshift( a.T1, a.T2 ) end, types.Tuple{P.NumberType("T1"),P.NumberType("T2")} ):complete(args)
  end
end)

generators.RshiftE = R.FunctionGenerator("core.Rshift",{"type","rate"},{"number"}, function(args)
  if args.number~=nil then
    return C.rshiftEConst( args.type:deInterface(), args.number )
  else
    assert(false)
  end
end)

generators.AddMSBs = R.FunctionGenerator("core.AddMSBs",{},{"number"}, function(args) return C.addMSBs(args.T,args.number) end, P.NumberType("T") )
generators.RemoveMSBs = R.FunctionGenerator("core.RemoveMSBs",{"number"},{}, function(args) return C.removeMSBs(args.T,args.number) end, P.NumberType("T") )

generators.RemoveLSBs = R.FunctionGenerator("core.RemoveLSBs",{"type","rate"},{"number"},
   function(args) return C.removeLSBs(args.T,args.number) end, P.NumberType("T") )

generators.RemoveLSBsE = R.FunctionGenerator("core.RemoveLSBsE",{"type","rate"},{"number"},
   function(args) return C.removeLSBs(args.T,args.number,true) end, P.NumberType("T") )

generators.Index = R.FunctionGenerator("core.Index",{"type","rate"},{"number","size"},
function(a)
  local ty = a.type:deInterface()
  --J.err( ty:isData(),"Index: input should be parallel type, but is: ", a.type )

  if ty:isData() or ty:isTuple() then
    -- if this is a tuple, it may be a tuple of schedules, but that's ok - we can support that
    
    local ity
    if ty:isArray() then
      ity = T.array2d(ty:arrayOver(),ty.size)
    elseif ty:isTuple() then
      ity = T.tuple(ty.list)
    else
      J.err( false, "Index: unsupported type: ",a.type )
    end
    
    if a.size~=nil then
      return C.index(ity,a.size[1],a.size[2])
    else
      return C.index(ity,a.number)
    end
  else
    -- perhaps this is a Seq or ParSeq?
    J.err( ty:isArray(),"Index: schedule type input is not an array? what could it be? ",ty)
    --J.err( ty.V:eq(R.Size(0,0)) or ty.V:eq(R.Size(1,1)),"Index: array vector size must be 0 or 1, but type is: ",ty)
    J.err( ty.V[2]==1 or ty.V[2]==0,"Index: NYI - array vector size must have height=1 or height=0, but type is: ",ty)

    local x,y
    if a.size~=nil then
      x = a.size[1]
      y = a.size[2]
    else
      x=a.number
      y=0
    end
    if ty.V[1]>1 then
      -- we can't use cropseq, if V is >1 (makes no sense, can't select 1 element)
      -- so, as a workaround, just convert to full size array
      return C.index( types.Array2d(ty:arrayOver(),ty.size), x, y )
    else
      return RM.cropSeq( ty:arrayOver(), ty.size[1], ty.size[2], ty.V[1], math.max(x-1,0), math.min(ty.size[1]-x,ty.size[1]-1), math.max(y-1,0), math.min(ty.size[2]-y,ty.size[2]-1), true, true )
    end
  end
end)

generators.ValueToTrigger = R.FunctionGenerator("core.ValueToTrigger",{"type","rate"},{},
function(args)

  if args.type:deInterface():isData() then
    return C.valueToTrigger(args.type:deInterface())
  elseif args.type:deInterface():isArray() then
    local ty = args.type:deInterface()
    -- a non-parallel array
--    J.err( ty.size:eq(ty.V) or ty.V:eq(0,0) or ty.V[2]==1 ,"ValueToTrigger: NYI, vector can only be 1D, but is: ",ty.V ) -- NYI

    local pipe={}
    table.insert( pipe, generators.Map{generators.ValueToTrigger}:complete({type=T.RV(args.type:deInterface()),rate=args.rate}) )
    assert( R.isPlainFunction(pipe[#pipe]) )


    if ty.V[1]~=0 then
      -- we don't care that we are passed a tile of triggers - we just want to get the first trigger
      table.insert( pipe, RM.makeHandshake(RM.flatmap(C.valueToTrigger( T.Array2d(T.Trigger,ty.V[1],ty.V[2]) ), ty.V[1], ty.V[2], ty.size[1], ty.size[2], 0, 0, ty.size[1]/ty.V[1], ty.size[2]/ty.V[2])) )
    end

    local crpX, crpY
    if ty.V[1]~=0 then
      crpX, crpY = (ty.size[1]/ty.V[1])-1, (ty.size[2]/ty.V[2])-1
    else
      crpX, crpY = ty.size[1]-1, ty.size[2]-1
    end
    
    table.insert( pipe, RM.liftHandshake(RM.liftDecimate(RM.cropSeq( T.Trigger, ty.size[1]/math.max(ty.V[1],1), ty.size[2]/math.max(ty.V[2],1), 0, 0, crpX, 0, crpY, true, true )) ) )

--    if ty.V[1]~=0 then
--      table.insert( pipe, RM.makeHandshake(C.valueToTrigger( T.Array2d(T.Trigger,ty.V[1])) ) )
--    end
    
    return C.linearPipeline(pipe,J.verilogSanitize("ValueToTriggerParseq_"..tostring(args.type:deInterface())))
  else
    J.err(false,"NYI - ValueToTrigger on input type: ",args.type)
  end
end)

generators.TriggerCounter = R.FunctionGenerator("core.TriggerCounter",{"number"},{},
function(args)
  return RM.triggerCounter(args.number)
end,
types.Trigger )


generators.TriggeredCounter = R.FunctionGenerator("core.TriggeredCounter",{"number"},{},
function(args)
  return RM.triggeredCounter( args.T, args.number, nil, true )
end,
types.RV(types.Par(P.DataType("T"))) )


generators.TriggerBroadcast = R.FunctionGenerator("core.TriggerBroadcast",{"number"},{},
function(args)
  return C.triggerUp(args.number)
end,
types.Trigger )

generators.FanOut = R.FunctionGenerator("core.FanOut",{"type","rate"},{"number","size"},
function(args)
  local size = args.size
  if args.number~=nil then size={args.number,1} end

  if args.type:isrv() then
    -- trivial case!
    assert(size[2]==1)
    return C.broadcastTuple( args.type:deInterface(), size[1] )
  else
    return RM.broadcastStream( args.type:deInterface(), size[1], size[2] )
  end
end)

generators.FanIn = R.FunctionGenerator("core.FanIn",{"type","rate"},{"bool"},
function(args)

  --print("FANIN",args.type,args.rate)
  
  local ty, rate = args.type:optimize( args.rate )

  --print("FANINopt",ty,rate)
  
  -- every stream going into packtuple needs to have the same rate! (rates have to match)
  -- So: we need to find the lowest rate from the optimized type, and make sure everything matches this
  -- (we can always serialize streams to DECREASE rate, but we can't necessarily increase rate)

  local lowestRate
  for k,v in ipairs(rate) do
    if lowestRate==nil or Uniform(v[1]):toNumber()/Uniform(v[2]):toNumber() < Uniform(lowestRate[1]):toNumber()/Uniform(lowestRate[2]):toNumber() then
      lowestRate = v
    end
  end

  --print("FAN IN LOWEST",lowestRate[1],lowestRate[2])
  
  local targetRate = rate*SDF{lowestRate[2],lowestRate[1]}

  --print("FAN IN target",targetRate)
  
  ty, rate = ty:optimize( targetRate )

  --print("FAN IN ROUND2 ",ty,rate)
  
  if ty:isrv() then
    -- trivial case: do nothing!
    return C.identity( ty:deInterface() )
  else
    if ty:isTuple() then
      local fn =  RM.packTuple( ty.list, args.bool )
      return fn
    elseif ty:isArray() then
      return RM.packTuple( ty, args.bool, ty.size )
    else
      J.err(false, "FanIn: expected handshaked tuple or array input, but is: "..tostring(ty))
    end
  end
end,nil,false)

-- bool: nostall
generators.FIFO = R.FunctionGenerator("core.FIFO",{"number","type"},{"bool","string"},
function(args)
  return C.fifo( args.type:deInterface(), args.number, args.bool, nil, nil, nil, args.string )
end )

-- add a fifo, but only if input is RV!!
generators.RVFIFO = R.FunctionGenerator("core.FIFO",{"number","type"},{"bool","string"},
function(args)
  if args.type:isRV() then
    return C.fifo( args.type:deInterface(), args.number, args.bool, nil, nil, nil, args.string )
  else
    return C.identity( args.type:deInterface() )
  end
end )

generators.NE = R.FunctionGenerator("core.NE",{},{"async","number"},
function(args)
  if args.number~=nil then
    -- add a const (unary op)
    return R.FunctionGenerator( "core.NE", {}, {}, function(a) return C.NEConst(a.T,args.number) end, T.rv(T.Par(P.DataType("T"))), T.rv(T.Par(types.bool()) ) )
  else
    return R.FunctionGenerator("core.NE", {}, {}, function(a) return C.NE( a.T, args.async ) end, T.rv(T.Par(T.tuple{P.DataType("T"),P.DataType("T")})),T.rv(T.Par(types.bool())) )
  end
end)

generators.Add = R.FunctionGenerator("core.Add",{"type","rate"},{"async","number"},
function(args)
  if args.number~=nil then
    -- add a const (unary op)
    return R.FunctionGenerator( "core.AddConst", {}, {"async","number"}, function(a) return C.plusConst( a.T, args.number ) end, P.NumberType("T") ):complete(args)
  else
    return R.FunctionGenerator("core.AddNonconst", {}, {"async","number"}, function(a) return C.sum( a.T, a.T, a.T, args.async ) end, T.tuple{P.NumberType("T"),P.NumberType("T")} ):complete(args)
  end
end)

generators.AddE = R.FunctionGenerator("core.Add",{"type","rate"},{"async","number"},
function(args)
  local res = {}
  if args.number~=nil then
    
    return R.FunctionGenerator( "core.AddConst", {}, {"async","number"},
                                function(a)
                                  local bts = math.ceil(math.log(args.number)/math.log(2))+math.max(-a.T.exp,0)
                                  local bb = math.max(a.T.precision,bts)+1
                                  return C.plusConst( a.T, args.number, args.async, a.T:replaceVar("precision",bb) )
                                end,
                                P.NumberType("T") ):complete(args)
  else
    return R.FunctionGenerator("core.AddENonconst", {}, {"async","number"},
                               function(a)
                                 local OT = a.T:replaceVar("precision",a.T.precision+1)
                                 return C.sum( a.T, a.T, OT, args.async )
                               end,
      T.tuple{P.NumberType("T"),P.NumberType("T")} ):complete(args)
  end
end)

-- {{idxType,vType},{idxType,vType}} -> {idxType,vType}
-- async: 0 cycle delay
generators.ArgMax = R.FunctionGenerator("core.ArgMax", {}, {"async"},
function(a) return C.argmin( a.idx, a.T, a.async, true ) end,
T.tuple{T.tuple{P.DataType("idx"),P.NumberType("T")},T.tuple{P.DataType("idx"),P.NumberType("T")}} )


generators.ArgMin = R.FunctionGenerator("core.ArgMin", {}, {"async"},
function(a) return C.argmin( a.idx, a.T, a.async, false ) end,
T.tuple{T.tuple{P.DataType("idx"),P.NumberType("T")},T.tuple{P.DataType("idx"),P.NumberType("T")}} )


generators.Neg = R.FunctionGenerator("core.Neg", {}, {"async"},
function(a) return C.neg( a.T.precision, a.T.exp ) end,
P.IntType("T") )

generators.Sub = R.FunctionGenerator("core.Sub",{"type","rate"},{"async","number"},
function(args)
  if args.number~=nil then
    -- add a const (unary op)
    return R.FunctionGenerator( "core.SubConst", {}, {"async","number"}, function(a) return C.subConst( a.T, args.number ) end, P.NumberType("T") ):complete(args)
  else
    return R.FunctionGenerator("core.SubNonconst", {}, {"async","number"}, function(a) return C.sub( a.T, a.T, a.T, args.async ) end, T.tuple{P.NumberType("T"),P.NumberType("T")} ):complete(args)
  end

--  return C.sub( args.T, args.T, args.T, args.async )
end) --,
--T.tuple{P.NumberType("T"),P.NumberType("T")} )

-- extend out bitwidth
generators.SubE = R.FunctionGenerator("core.SubE",{},{"async"},
function(args)
  assert( args.T:isUint() or args.T:isInt() )
  return C.sub( args.T, args.T, args.T:replaceVar("precision",args.T.precision+1), args.async )
end,
T.tuple{P.NumberType("T"),P.NumberType("T")} )

generators.Mul = R.FunctionGenerator("core.Mul",{"type","rate"},{"number","async"},
function(args)
  if args.number~=nil then
    return R.FunctionGenerator("core.Mul",{},{"async","number"},
      function(a) return C.multiplyConst( a.T, args.number, a.async ) end, P.NumberType("T") ):complete(args)
  else
    return R.FunctionGenerator("core.Mul",{},{"async","number"},function(a) return C.multiply( a.T, a.T, a.T, args.async ) end, T.tuple{P.NumberType("T"),P.NumberType("T")}):complete(args)
  end
end)

generators.MulE = R.FunctionGenerator("core.MulE",{"type","rate"},{"number","async"},
function(args)
  if args.number~=nil then
    local bts = math.ceil(math.log(args.number)/math.log(2))

      return R.FunctionGenerator("core.MulEConst",{},{"async","number"},
                                 function(a)
                                   local OT = a.L:replaceVar("precision",a.L.precision+bts)
                                   return C.multiplyConst( a.L, args.number, OT )
                                 end,
                                 P.NumberType("L")):complete(args)
  else
    return R.FunctionGenerator("core.MulE",{},{"async","number"},function(a) return C.multiplyE( a.L, a.R, args.async ) end, T.tuple{P.NumberType("L"),P.NumberType("R")}):complete(args)
  end
end)

generators.GT = R.FunctionGenerator("core.GT",{"type","rate"},{"number","async"},
function(args)
  if args.number~=nil then
    return R.FunctionGenerator("core.GTConstInner",{},{"async","number"},
             function(a) return C.GTConst( a.T, args.number, a.async ) end, P.NumberType("T") ):complete(args)
  else
    return R.FunctionGenerator("core.GTInner",{},{"async","number"},
             function(args) return C.GT( args.T, args.T, args.T, args.async ) end, T.tuple{P.NumberType("T"),P.NumberType("T")} ):complete(args)
  end
end)

generators.LT = R.FunctionGenerator("core.LT",{},{"number"},
function(args)
  if args.number~=nil then
    return R.FunctionGenerator("core.LT",{},{"async"},
      function(a) return C.LTConst( a.T, args.number, a.async ) end,
      T.rv(T.Par(P.NumberType("T"))), T.rv(T.Par(types.Bool)))
  else
    return R.FunctionGenerator("core.LT",{},{"async"},function(args) return C.LT( args.T, args.T, args.T, args.async ) end, T.rv(T.Par(T.tuple{P.NumberType("T"),P.NumberType("T")})), T.rv(T.Par(types.Bool)))
  end
end)

generators.EQ = R.FunctionGenerator("core.EQ",{"type","rate"},{"number"},
function(args)
  if args.number~=nil then
    return R.FunctionGenerator("core.EQConst",{},{"async"},
      function(a) return C.EQConst( a.T, args.number, a.async ) end, P.NumberType("T") ):complete(args)
  else
    return R.FunctionGenerator("core.EQ",{},{"async"},function(args) return C.eq( args.T, args.async ) end, T.tuple{P.NumberType("T"),P.NumberType("T")} ):complete(args)
  end
end)

generators.Abs = R.FunctionGenerator("core.Abs",{},{"async"},
function(a) return C.Abs( a.T, a.async ) end,
P.NumberType("T") )

-- remove fractional component
generators.Denormalize = R.FunctionGenerator("core.Denormalize",{},{},
function(a) return C.denormalize( a.T ) end,
P.NumberType("T") )

generators.And = R.FunctionGenerator("core.And",{"type","rate"},{"async"},
function(args)
  J.err( args.type:deInterface():isTuple() )
  local ty = args.type:deInterface().list[1]
  if ty:isBool() then
    return C.And
  elseif ty:isUint() then
    return C.AndUint(args.T.precision)
  else
    assert(false)
  end
end)

generators.Not = R.FunctionGenerator("core.Not",{"type","rate"},{"bool"},
function(args)
  --J.err( args.type==types.bool(), "generators.Not: input type should be bool, but is: "..tostring(args.type) )
  return C.Not
end,T.Bool)

local function zipfn(asArray)
  return function(args)
    local typelist = {}
    for k,v in ipairs(args.list) do
      typelist[k] = v:arrayOver()
      J.err( v.size:eq(args.list[1].size),"Zip: all input arrays  that you are zipping must have same size! item0 size:",args.list[1].size," item",k-1,"size:",v.size," inputType:",args.type)
    end

    if args.V:eq(0,0) then
      assert(asArray==false) -- NYI
      return RM.ZipSeq( false, args.size[1], args.size[2], unpack(typelist) )
    else
      return RM.SoAtoAoS( args.V[1], args.V[2], typelist, asArray, args.size[1], args.size[2] )
    end
  end
end

generators.Zip = R.FunctionGenerator("core.Zip",{"type"},{},zipfn(false),
T.tuple(P.TypeList("list",T.array2d( P.ScheduleType("S$"), P.SizeValue("size"), P.SizeValue("V") ))) )

-- zipToArray could actually be implemented as Zip + TupleToArray...
generators.ZipToArray = R.FunctionGenerator("core.ZipToArray",{"type"},{},zipfn(true),
T.tuple(P.TypeList("list",T.array2d( P.ScheduleType("S$"), P.SizeValue("size"), P.SizeValue("V") ))) )

generators.Linebuffer = R.FunctionGenerator("core.Linebuffer",{"type","size","number","bounds","rate"},{},
function(args)
  local itype
  if args.number==0 then
    itype = args.type
  else
    J.err( args.type:isArray(), "generators.Linebuffer: expected array input, but is: "..tostring(args.type) )
    itype = args.type:arrayOver()
  end
  
  local a = C.stencilLinebuffer( itype, args.size[1], args.size[2], math.max(args.number,1), -args.bounds[1], args.bounds[2], -args.bounds[3], args.bounds[4] )
  local b = C.unpackStencil( itype, args.bounds[1]+1,args.bounds[3]+1, math.max(args.number,1) )
  local mod = C.compose("generators_Linebuffer_"..a.name.."_"..b.name,b,a)
  
  if args.number==0 then
    mod = C.linearPipeline({C.arrayop(itype,1,1),mod,C.index(mod.outputType,0)},"generators_Linebuffer_0wrap_"..mod.name)
  end
  
  return mod
end)

generators.Stencil = R.FunctionGenerator("core.Stencil",{"bounds","rate","type"},{},
function(a)
  J.err( a.size:eq(a.V) or a.V:eq(0,0) or a.V[2]==1 ,"Stencil: NYI, vector can only be 1D, but is: ",a.V," inputType:",a.type ) -- NYI

  local STW = a.bounds[2]-a.bounds[1]+1
  local V = J.canonicalV( a.rate, R.Size(STW,1) )
  J.err( V[2]==1 or V[2]==0, "Stencil NYI: input array with tiled vector. inputType:",a.type)
  
  if STW~=V[1]*V[2] and V[2]==1 then
    assert(a.V:eq(0,0))
    return C.stencilLinebufferPartial( a.T, a.size[1], a.size[2], STW/V[1], a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], true )
  else
    return C.stencilLinebuffer( a.T, a.size[1], a.size[2], a.V[1], a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], true )
  end
end,
types.array2d( P.DataType("T"),P.SizeValue("size"),P.SizeValue("V")) )

-- make a stencil with its interior filled with stencils
-- "bounds" is for the outer stencil, "size" is for the inner stencil.
--     since the inner stencil is all overlap regions fully contained in the outer stencil, this makes sense...
generators.StencilOfStencils = R.FunctionGenerator("core.StencilOfStencils",{"bounds","rate","size","type"},{},
function(a)
  J.err( a.imsize:eq(a.V) or a.V:eq(0,0) or a.V[2]==1 ,"Stencil: NYI, vector can only be 1D, but is: ",a.V ) -- NYI

  if a.rate:lt(SDF{1,1}) then
    
    local f = C.stencilLinebufferPartialOffsetOverlap( a.T, a.imsize[1], a.imsize[2], a.rate[1][2]:toNumber()/a.rate[1][1]:toNumber(), a.bounds[1], 0, a.bounds[3], a.bounds[4], -a.bounds[2], -a.bounds[3], a.V[1])

    local stCount = (Uniform(a.bounds[2]):toNumber()-Uniform(a.bounds[1]):toNumber()+1-(a.size[1]-1))
    local perCycleSearch = stCount*(a.rate[1][1]:toNumber()/a.rate[1][2]:toNumber())
    local g = RM.makeHandshake(C.unpackStencil( a.T, a.size[1], a.size[2], perCycleSearch ))

    local res = C.compose("StencilOfStencils",g,f)

    assert(res.inputType:isRV())
    assert( res.inputType:lower()==a.type:lower() )
    res.inputType = a.type

    local vtype = res.outputType:deInterface()
    local vtype = T.Array2d(vtype:arrayOver(),stCount,1,vtype.size)

    local OT = types.RV(a.type:deInterface():replaceVar("over",vtype))
    assert( res.outputType:lower()==OT:lower() )
    res.outputType = OT

    return res
  else
    local f = C.stencilLinebuffer( a.T, a.imsize[1], a.imsize[2], a.V[1], a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], true )
    local stencilW = a.bounds[2]-a.bounds[1]+1
    local stencilH = a.bounds[4]-a.bounds[3]+1

    J.err( a.size[2]==stencilH, "NYI - StencilOfStencils, height of inner stencil must be height of outer stencil")
  
--  local g = C.unpackStencil( a.T, a.size[1], a.size[2], stencilW-a.size[1]+1, nil, true, a.imsize[1], a.imsize[2])
    local g = generators.Map{C.unpackStencil( a.T, a.size[1], a.size[2], stencilW-a.size[1]+1)}

    return C.compose("StencilOfStencils",g,f)
  end
end,
types.ParSeq(types.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("imsize")) )

generators.Pad = R.FunctionGenerator("core.Pad",{"bounds"},{},
function(a)
  J.err( a.size:eq(a.V) or a.V:eq(0,0) or a.V[2]==1 ,"Pad: NYI, vector can only be 1D, but is: ",a.V ) -- NYI
  return RM.padSeq( a.T:deSchedule(), a.size[1], a.size[2], a.V[1], a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], a.T:fakeValue(), true, true )
end,
T.array2d( P.ScheduleType("T"), P.SizeValue("size"), P.SizeValue("V") ) )

-- we disable optimization for this! Since it's really just a wrapper around the raw generator
generators.CropSeq = R.FunctionGenerator("core.CropSeq",{"type","size","number","bounds","rate"},{},
function(args)
  local A = args.type:deInterface()
  if args.number>0 then A  = args.type:deInterface():arrayOver() end
  
  return RM.cropSeq(A,args.size[1],args.size[2],args.number,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4])
end,nil,false)

generators.Crop = R.FunctionGenerator("core.Crop",{"bounds"},{},
function(a)
  J.err( a.size:eq(a.V) or a.V:eq(0,0) or a.V[2]==1 ,"Crop: NYI, vector can only be 1D, but is: ",a.V ) -- NYI
  return C.cropHelperSeq( a.S:deSchedule(), a.size[1], a.size[2], a.V[1], a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], true )
end,
T.array2d(P.ScheduleType("S"),P.SizeValue("size"),P.SizeValue("V")) )

generators.Downsample = R.FunctionGenerator("core.Downsample",{"size"},{},
function(a)
  J.err( a.size:eq(a.V) or a.V:eq(0,0) or a.V[2]==1 ,"Downsample: NYI, vector can only be 1D, but is: ",a.V ) -- NYI
  return C.downsampleSeq( a.T, a.imsize[1], a.imsize[2], a.V[1], a.size[1], a.size[2], true )
end,
T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("imsize")) )

generators.Upsample = R.FunctionGenerator("core.Upsample",{"size"},{},
function(a)
  J.err( a.size:eq(a.V) or a.V:eq(0,0) or a.V[2]==1 ,"Upsample: NYI, vector can only be 1D, but is: ",a.V ) -- NYI
  return C.upsampleSeq( a.T, a.imsize[1], a.imsize[2], a.V[1], a.size[1], a.size[2], true )
end,
T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("imsize")) )

generators.PosSeq = R.FunctionGenerator("core.PosSeq",{"size","number"},{},
function(args)
  return RM.posSeq(args.size[1],args.size[2],args.number)
end,
T.Trigger)

generators.Pos = R.FunctionGenerator("core.Pos",{"size","rate","type"},{},
function(args)
  local V = J.canonicalV( args.rate, args.size )

  J.err( (V[1]==0 and V[2]==0) or V[2]==1, "NYI - Pos, vector width is not supported, V: ",V," inputType:",args.type," inputRate:",args.rate)
  local res = generators.Function{"Pos_With_Trig",T.RV(T.Par(T.Trigger)),args.rate,
    function(inp)
      local PS = RM.posSeq(args.size[1],args.size[2],V[1],nil,true,true)
      local trig = generators.Broadcast{{args.size[1],args.size[2]}}(inp)
      return generators.Fmap{PS}(trig)
    end}
  
  return res
end,
T.Trigger )

-- unlike Pos above, this expects a trigger for every pixel
-- this means we don't have to explicitly give the image dimensions
-- bool: if true, return as tuple instead of array
generators.PosCounter = R.FunctionGenerator("core.PosCounter",{},{"bool"},
function(args)
  J.err(args.V[2]==1 or args.V[2]==0,"PosCounter: V")
  print("POSCOUNTER",args.bool)
  return RM.posSeq(args.size[1],args.size[2],args.V[1],nil,true,args.bool~=true)
end,
T.Array2d( T.Trigger, P.SizeValue("size"), P.SizeValue("V") ) )

-- this takes an Seq of arrays, and flattens it into a parseq
generators.Flatten = R.FunctionGenerator("core.Flatten",{"type","rate"},{},
function(args)
  J.err( args.outerV:eq(0,0), "Flatten NYI - outer array must be fully sequential, but outer V was:",args.outerV," and input type was: ", args.type)
  return C.flatten( args.innerT, args.innerSize, args.innerV, args.outerSize )
end,
T.Array2d( T.Array2d(P.DataType("innerT"),P.SizeValue("innerSize"),P.SizeValue("innerV")), P.SizeValue("outerSize"), P.SizeValue("outerV") )  )

generators.Fmap = R.FunctionGenerator("core.Fmap",{"rigelFunction","type","rate"},{},
function(args)
  J.err(R.isPlainFunction(args.rigelFunction),"core.FMap should only work on plain functions")

  -- this is subtle, but we want to not optimize the type: just take whatever type was passed in, and do necessary conversions
  -- this prevents a double conversion
  return R.FunctionGenerator("core.FMap_internal",{"rigelFunction","type","rate"},{},function(a) return args.rigelFunction end,nil,false ):complete(args)
--                             args.rigelFunction.inputType:deInterface(),false ):complete(args)
end,nil,false)

-- bool: allow stateful
generators.Map = R.FunctionGenerator("core.Map",{"rigelFunction","type","rate"},{"bool","unoptimized"},
function(args)

  J.err( args.type:deInterface():isArray(),"Error, Map must operate on an array! but input type was: ",args.type)

  -- NOTE: we send the fn we are mapping over the original (non-optimized) type, b/c it may not
  -- want to optimize the type!
  local S = args.type:deInterface():arrayOver()

  --print( "MAP:SPECIALIZE TO TYPE", args.rigelFunction.name,types.rv(S))
  local fn = args.rigelFunction:specializeToType( types.rv(S), args.rate )
  J.err( fn~=nil, "Map: failed to specialize mapped function ",args.rigelFunction.name," to type:",types.rv(S))

  if ((fn.inputType:isrv() and fn.outputType:isrv()) or (fn.inputType:isRV() and fn.outputType:isRV()))==false then
    --print("Map: fn returned unsupported types",fn.inputType,fn.outputType," - trying again with RV...")
    -- NYI - we basically only support rv or RV (ie no rvV etc), so if it can't be rv, ask for RV
    fn = args.rigelFunction:specializeToType( types.RV(S), args.rate )
    J.err( fn~=nil, "Map: failed to specialize mapped function ",args.rigelFunction.name," to type:",types.RV(S))
  end

  local ty, rate
  if args.unoptimized==true then
    ty,rate = args.type,args.rate
  else
    ty,rate = args.type:optimize(args.rate)
  end
  
  local S, size, V, var = ty:deInterface():arrayOver(), ty:deInterface().size, ty:deInterface().V, ty:deInterface().var

  if var then
    if V:eq(R.Size(0,0)) then
      return RM.mapVarSeq(fn, size[1], size[2] )
    else
      assert(false)
    end
  else
    if size==V then
      return RM.map( fn, size[1], size[2], args.bool )
    elseif V:eq(R.Size(0,0)) then
      return RM.mapSeq( fn, size[1], size[2] )
    else -- parseq
      return RM.mapParSeq( fn, V[1], V[2], size[1], size[2], args.bool )
    end
  end
  
  assert(false)
end,
nil,false)

-- This only works if the array size doesn't change!!
generators.Flatmap = R.FunctionGenerator("core.Flatmap",{"rigelFunction","type","rate"},{},
function(args)

  local ty,rate

  if R.isFunctionGenerator(args.rigelFunction) and args.rigelFunction.optimized==false then
    ty, rate = args.type, args.rate
  else
    ty, rate = args.type:optimize(args.rate)
  end

  J.err( ty:deInterface():isArray(),"Error, Flatmap must operate on an array! but input type was: ",args.type)
  local S, size, V = ty:deInterface():arrayOver(), ty:deInterface().size, ty:deInterface().V

  local fn = args.rigelFunction:specializeToType( types.rv(S), rate )
  J.err( fn~=nil, "Flatmap: failed to specialize mapped function ",args.rigelFunction.name," to type:",types.rv(S))

  return RM.flatmap( fn, args.V[1], args.V[2], args.size[1], args.size[2], args.V[1], args.V[2], args.size[1], args.size[2] )
end,
T.Array2d(P.ScheduleType("S"),P.SizeValue("size"),P.SizeValue("V")), false )

generators.Reduce = R.FunctionGenerator("core.Reduce",{"rigelFunction"},{},
function(args)

  -- we don't support non-parallel reduction functions: so just coerce it into a parallel type
  local tyOver = args.S:deSchedule()
  
  local fn = args.rigelFunction:specializeToType( T.rv(types.Tuple{tyOver,tyOver}), SDF{1,1} )

  J.err( fn.inputType:isrv() and fn.outputType:isrv(),"Reduce: error, reduce can only operator over rv functions, but fn had type: ",fn.inputType,"->",fn.outputType)
  
  if args.V[1]==0 and args.V[2]==0 then
    return RM.reduceSeq( fn, args.size[1], args.size[2], true)
  elseif args.V[1]<args.size[1] or args.V[2]<args.size[2] then
    return RM.reduceParSeq( fn, args.V[1], args.V[2], args.size[1], args.size[2] )
  else
    return RM.reduce( fn, args.size[1],args.size[2])
  end
end,
T.Array2d(P.ScheduleType("S"),P.SizeValue("size"),P.SizeValue("V")))

generators.ReduceSeq = R.FunctionGenerator("core.ReduceSeq",{"type","rigelFunction","number","rate"},{},
function(args)

  local mod
  if R.isFunctionGenerator(args.rigelFunction) then
    mod = args.rigelFunction{types.tuple{args.type,args.type},args.rate}
    assert( R.isPlainFunction(mod) )
  else
    assert(false)
  end
  
  return RM.reduceSeq( mod, 1/args.number )
end)

-- number is the number of cycles over which to ser
generators.Ser = R.FunctionGenerator("core.Ser",{"number"},{},
function(args)
  return RM.changeRate( args.T, args.size[2], args.size[1], args.number, true, args.size[1], args.size[2] )
end,
P.SumType("opt",{T.rV(T.Par(T.Array2d(P.DataType("T"),P.SizeValue("size"))))}) )


-- serialize to a particular vector width ("number")
-- width is the number of items to produce per cycle (not literally the width)
generators.SerToWidth = R.FunctionGenerator("core.SerToWidth",{"number","type","rate"},{},
function(args)
  J.err( math.floor(args.number)==args.number, "SerToWidth: width is not an integer, is: ",args.number)

  -- b/c we are doing explicit reshapes here, we can't use default behavior of class
  local Tparam = T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size"))
  local a = {}
  assert( Tparam:isSupertypeOf( args.type:deInterface(), a, "" ) )

  if args.number==0 then
    if a.V[1]*a.V[2]==1 and args.number==0 then
      -- special case of taking [1,1;w,h} to {w,h} (not really a changerate)
      return SerToWidthArrayToScalar( a.T, a.size )
    else
      return RM.changeRate( a.T, a.V[2], a.V[1], args.number, true, a.size[1], a.size[2] )
    end
  else
    return R.FunctionGenerator("core.SerToWidth",{"number","type","rate"},{},
      function(a)
        return ChangeRateRowMajor( a.T, a.V[1], a.V[2], args.number, a.size[1], a.size[2] )
      end):complete(args)
  end
end)

-- explicit reshape to column-wise
generators.ToColumns = R.FunctionGenerator("core.ToColumns",{"type","rate"},{},
function(args)
  local V = J.canonicalV( args.rate, args.size, true)
  
  if args.size[1] == V[1] then
    -- hack around broken changerate!! fix
    return C.identity( args.type:deInterface() )
  else
    assert(V[2]==args.size[2])
    return RM.changeRate( args.T, args.size[2], args.size[1], V[1], true, args.size[1], args.size[2] )
  end
end,
types.array2d(P.DataType("T"),P.SizeValue("size")), false )

-- we disable optimization for this! Since it's really just a wrapper around the raw generator
generators.SerSeq = R.FunctionGenerator("core.SerSeq",{"type","number","rate"},{},
function(args)
  J.err( args.size[1]%args.number==0,"G.SerSeq: number of cycles must divide array size. size:",args.size," cycles:",args.number)
  return RM.changeRate( args.T, args.size[2], args.size[1], args.size[1]/args.number )
end,
types.array2d(P.DataType("T"),P.SizeValue("size")), false )

-- we disable optimization for this! Since it's really just a wrapper around the raw generator
generators.DeserSeq = R.FunctionGenerator("core.DeserSeq",{"number"},{},
function(args)
  return RM.changeRate( args.T, args.size[2], args.size[1], args.size[1]*args.number )
end,
types.rV(types.Par(types.array2d(P.DataType("T"),P.SizeValue("size")))), false )


-- Number: this is the factor of # of parallel tokens we should concat.
-- so [1,4;4,4} with factor 2 would end up [2,4;4,4}
-- [1,4;4,4} with factor 4 would end up [4,4]
generators.Deser = R.FunctionGenerator("core.Deser",{"number"},{},
function(args)
  if args.V:eq(0,0) then
    -- change T{W,H} to T[W,H]
    assert(args.size[2]==1)
    assert(args.size[1]*args.size[2]==args.number)

    return RM.changeRate( args.T, 1, 0, args.number, true, args.size[1], args.size[2] )
  else
    print( "NYI - deser on type: ", args.type )
    assert(false)
  end
end,
types.Array2d( P.DataType("T"), P.SizeValue("size"), P.SizeValue("V") ) )


generators.Fwrite = R.FunctionGenerator("core.Fwrite",{"string"},{"filenameVerilog","header"},
function(args)
  --return RS.modules.fwriteSeq({type=args.type,filename=args.string})
  return RM.fwriteSeq( args.string, args.S:deSchedule(), args.filenameVerilog, true, nil,nil,nil,args.header )
end,
P.ScheduleType("S") )

-- convenience function to write PGM
-- If passed an array: treat this array as an image, and write it out (W/H are size of array)
-- if passed a size: treat this size as the image size, and expect a stream of pixels
--                   ie: we may be inside a mapped function
generators.FwritePGM = R.FunctionGenerator("core.FwritePGM",{"string","type","rate"},{"size"},
function(args)

  if args.size~=nil then
    local W = args.size[1] * (args.type:deSchedule():verilogBits()/8)
    local H = args.size[2]
    return generators.Fwrite{args.string,header="P5 "..W.." "..H.." 255 "}:complete({type=args.type,rate=args.rate})
  else
    J.err( args.type:deInterface():isArray() )
    local S, size, V = args.type:deInterface():arrayOver(), args.type:deInterface().size, args.type:deInterface().V
    print("WRITEPGM",size)
    assert( S:deSchedule():verilogBits()%8 == 0)
    assert( V:eq(0,0) )
    local W = Uniform(size[1]):toNumber() * (S:deSchedule():verilogBits()/8)
    local H = Uniform(size[2]):toNumber()
    return generators.Map{generators.Fwrite{args.string,header="P5 "..W.." "..H.." 255 "}}:complete({type=args.type,rate=args.rate})
  end
end)
--types.Array2d(P.ScheduleType("S"),P.SizeValue("size"),P.SizeValue("V")) )

generators.Fread = R.FunctionGenerator( "core.Fread",{"string","type","type1"},{"filenameVerilog"},
function(args)
  return RM.freadSeq( args.string, args.type1, true )
end,
T.Uint(32) )


-- assert that the input stream is the same as the file. Early out on errors.
generators.Fassert = R.FunctionGenerator("core.Fassert",{"type","string"},{},
function(args)
  return C.fassert(args.string,args.type)
end)

generators.AXIReadBurstSeq = R.FunctionGenerator("core.AXIReadBurstSeq",{"type1","string","size","rate","number","rigelFunction"},{},
function(args)
  -- note: type here should be explicitly passed by the user! This is the type of data we want
  return SOC.readBurst(args.string, args.size[1], args.size[2], args.type1, args.number, false, nil, args.rigelFunction )
end)

generators.AXIWriteBurstSeq = R.FunctionGenerator("core.AXIWriteBurstSeq",{"type","string","size","rate","number","rigelFunction"},{},
function(args)
  J.err( R.isHandshake(args.type), "AXIWriteBurstSeq: input must be handshaked, but is: "..tostring(args.type))
  local ty
  if args.number>0 then
    ty = R.extractData(args.type):arrayOver()
  else
    ty = R.extractData(args.type)
  end
  
  return SOC.writeBurst(args.string, args.size[1], args.size[2], ty, args.number, 1, false, args.rigelFunction )
end)

-- string is name
generators.Function = R.FunctionGenerator("core.Function",{"luaFunction","type"},{"string","rate","instanceList"},
function(args)
  if args.string==nil then
    args.string = "unnamedModuleGen"..__unnamedID
    __unnamedID = __unnamedID+1
  end

  local input = R.input( args.type, args.rate )
  local out = args.luaFunction(input)
  J.err( R.isIR(out), "Module: user function returned something other than a Rigel value? ",out)
  
  return RM.lambda( args.string, input, out, args.instanceList )
end,nil,false)

-- string is name
-- bool: force rv no matter what
generators.SchedulableFunction = R.FunctionGenerator("core.SchedulableFunction",{"luaFunction","type","type1"},{"string","rate","bool","unoptimized"},
function(args)
  --print("Schecule SchedulableFunction ",args.string,args.type,args.type1)
  
  if args.string==nil then
    args.string = "unnamedSchedulableFunction"..__unnamedID
    __unnamedID = __unnamedID+1
  end

  J.err( args.type1:isData(),"SchedulableFunction declared input type should be data type, but is: ",args.type1 )
  J.err( args.type1:isSupertypeOf(args.type:deSchedule(),{},""),"SchedulableFunction '",args.string,"' was passed an input type that can't be converted to declared type! declared:", args.type1, " passed:", args.type )

  local input

  local optType, optRate

  if args.unoptimized~=true then
    optType, optRate = args.type:optimize( args.rate )
  else
    optType, optRate = args.type, args.rate
  end
  
  local RVMode

  -- user explicitly forced rv!
  if args.bool==true then
    RVMode = false
    input = R.input( types.rv(optType:deInterface()), optRate )
  end
  
  if RVMode==nil and #optRate>1 then
    -- if we have multiple rates going into the function, and the rates are different, we basically have to do RV mode
    for k,r in ipairs(optRate) do
      if optRate[1]~=r then
        print("!!!!!!!! rate mismatch into SchedulableFunction ",args.string," forcing RV! ",optType,SDF{optRate[1]},SDF{r})
        RVMode = true
        assert( optType:isTuple() or optType:isArray() )
        input = R.input( optType, optRate)
        break
      end
    end
  end
  
  if RVMode==nil then
    local schedulePassInput = R.input( types.rv(optType:deInterface()), optRate, true )
    local scheduleOut = args.luaFunction(schedulePassInput)

    J.err( R.isIR(scheduleOut), "SchedulableFunction: user function returned something other than a Rigel value? ",scheduleOut)
    J.err( type(scheduleOut.scheduleConstraints)=="table","Internal Error, schedule pass didn't return constraints?")
    J.err( type(scheduleOut.scheduleConstraints.RV)=="boolean","Internal Error, schedule pass didn't return RV constraint?")
  
    --print("Schedule Pass result, ",args.string," RV:", scheduleOut.scheduleConstraints.RV )
    RVMode = scheduleOut.scheduleConstraints.RV

    if RVMode then
      -- this needs an RV interface
      input = R.input( types.RV(optType:deInterface()), optRate )
    else
      input = R.input( types.rv(optType:deInterface()), optRate )
    end
  end
  

  --print("Schedulable function ",args.string," input type:",input.type)
  
  local out = args.luaFunction(input)
  J.err( R.isIR(out), "SchedulableFunction: user function returned something other than a Rigel value? "..tostring(out))

  local resFn = RM.lambda( args.string, input, out )

  -- this will enable auto-lifting...
  return generators.Fmap{resFn}:complete{type=args.type,rate=args.rate}
end,nil,false)

-- rigelFunction: the fn to call to perform the AXI read
generators.AXIReadBurst = R.FunctionGenerator("core.AXIReadBurst",{"string","size","type","type1","rate","rigelFunction"},{"number","address"},
function(args)
  local numb = args.number
  if numb==nil then
    numb = math.ceil((args.size[1]*args.size[2]*Uniform(args.rate[1][1]):toNumber())/Uniform(args.rate[1][2]):toNumber())
  end
  return SOC.readBurst( args.string, args.size[1], args.size[2], args.type1, numb, true, args.address, args.rigelFunction )
end)

generators.AXIRead = R.FunctionGenerator("core.AXIRead",{"string","number","rigelFunction","type1"},{},
function(args)
  return SOC.read( args.string, args.number, args.type1, args.rigelFunction )
end,
types.uint(32) )

generators.AXIWriteBurst = R.FunctionGenerator("core.AXIWriteBurst",{"string","rigelFunction"},{"address"},
function(a)
  return SOC.writeBurst( a.string, a.size[1], a.size[2], a.T:deSchedule(), a.V[1], a.V[2], true, a.rigelFunction, a.address )
end,
types.array2d( P.ScheduleType("T"), P.SizeValue("size"), P.SizeValue("V") ) )

-- change dims of array
generators.ReshapeArray = R.FunctionGenerator("core.ReshapeArray",{"size","type"},{},
function(args)
  J.err( args.size[1]*args.size[2]==args.insize[1]*args.insize[2], "ReshapeArray: total number of items must not change. Input size: ",args.insize," requested reshape: ",args.size )

  if args.V:eq(0,0) then
    local tmp = C.identity( args.type:deInterface(), "ReshapeArray_"..tostring(args.type:deInterface()) )

    local IT = types.rv(args.type:deInterface())

    assert( tmp.inputType:lower()==IT:lower() )
    tmp.inputType = IT
    local OT = types.rv( types.Array2d(args.T, args.size, 0, 0) )
    assert( tmp.outputType:lower()==OT:lower() )
    tmp.outputType = OT
    
    return tmp
  else
    return C.cast( T.Array2d(args.T,args.insize), T.Array2d(args.T,args.size) )
  end
end,
types.array2d(P.DataType("T"),P.SizeValue("insize"),P.SizeValue("V")) )

generators.Reshape = generators.ReshapeArray

generators.Sort = R.FunctionGenerator("core.Sort",{"rigelFunction"},{},
function(args)
  J.err( args.size[2]==1,"generators.Sort: must be 1d array" )
  return C.oddEvenMergeSort( args.T, args.size[1], args.rigelFunction )
end,
types.array2d(P.DataType("T"),P.SizeValue("size")) )

generators.Identity = R.FunctionGenerator("core.Identity",{},{},
function(args) return C.identity(args.T) end,
P.ScheduleType("T") )

generators.Sel = R.FunctionGenerator("core.Sel",{},{},
function(args)
  return C.select(args.T)
end,
types.tuple{types.bool(),P.DataType("T"),P.DataType("T")} )


generators.Slice = R.FunctionGenerator("core.Slice",{"type","rate"},{"bounds","size"},
function(args)
  --print("SLICE",args.type,args.rate,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4])
  if args.type:deInterface():isArray() then
    local TY = args.type:deInterface():arrayOver()
    local arsize = args.type:deInterface().size
    if args.bounds~=nil then
      local res = C.slice( types.array2d(TY,arsize), args.bounds[1], args.bounds[2], args.bounds[3], args.bounds[4] )
      --print("SLICERET",res.inputType,res.outputType)
      return res
    else
      J.err( arsize[2]==1, "generators.Slice: NYI - only 1d arrays supported" )
      return C.slice( types.array2d(TY,arsize), args.size[1], args.size[2], 0, 0)
    end
  elseif args.type:deInterface():isTuple() then
    return C.slice( args.type:deInterface(), args.size[1], args.size[2], 0, 0, false )
  else
    print("Slice: applying to unsupported type: ",args.type)
    assert(false)
  end
end)


generators.TupleToArray = R.FunctionGenerator("core.TupleToArray",{},{},
function(a)
  return C.tupleToArray( a.T.list[1], #a.T.list )
end,
P.TupleType("T") )

generators.ArrayToTuple = R.FunctionGenerator("core.ArrayToTuple",{"type"},{},
function(a)
  J.err( a.V==a.size,"ArrayToTuple: NYI - non fully parallel array: ",a.type)
  
  local C = require "generators.examplescommon"
  return C.ArrayToTuple( a.D, a.size[1], a.size[2] )
end,
T.Array2d(P.DataType("D"),P.SizeValue("size"),P.SizeValue("V")) )

generators.Filter = R.FunctionGenerator("core.Filter",{"size"},{},
function(args)
  if args.opt==1 then
    assert(args.V[2]==1)
    return C.FilterSeqPar( args.T, args.V[1], SDF(args.size), true, args.insize[1], args.insize[2] )
  else
    return RM.filterSeq( args.T, args.insize[1], args.insize[2], args.size, 0, false, true )
  end
end,
T.ParSeq( T.Array2d( T.tuple{P.DataType("T"),T.bool()},P.SizeValue("V")),P.SizeValue("insize") ) )

-- Note: we set optimize=false, because arbiters need to have total rates that are <1!
generators.Arbitrate = R.FunctionGenerator("core.Arbitrate",{"rate"},{},
function(args)
  print("ARBITRATE", args.type, args.sched, args.rate )
  return RM.arbitrate( args.sched, args.rate )
end,
T.array2d(P.ScheduleType("sched"),P.SizeValue("size")), false )


generators.Const = R.FunctionGenerator("core.Const",{"type1"},{"number","value"},
function(args)
  local value = args.value
  if args.number~=nil then value = args.number end
  args.type1:checkLuaValue(value)
  return C.triggerToConstant(args.type1, value )
end,
T.Trigger )

-- this will concat a constant to the RHS
generators.ConcatConst = R.FunctionGenerator("core.ConcatConst",{"type1"},{"number","value"},
function(args)
  local value = args.value
  if args.number~=nil then value = args.number end
  return C.ConcatConst( args.T, args.type1, value )
end,
P.DataType("T") )

-- apply a function to one of the items in a tuple
generators.ApplyTo = R.FunctionGenerator("core.ApplyTo",{"rigelFunction","number","type","rate"},{},
function(args)

  local IT = args.T.list[args.number+1]
  local fn = args.rigelFunction:specializeToType( types.rv(IT), args.rate )
  J.err( fn~=nil, "Map: failed to specialize mapped function ",args.rigelFunction.name," to type:", IT )

  return C.ApplyTo( args.T, fn, args.number )
end,
P.TupleType("T") )

-- type1: type to do reduce at
generators.SAD = R.FunctionGenerator("core.SAD",{"type","rate","type1"},{},
function(args)
  assert( args.size[1]==args.size[2] )
  return C.SAD( args.A, args.type1, args.size[1] )
end,
T.Array2d(T.Array2d(P.DataType("A"),2),P.SizeValue("size")), false )

-- convert to recoded hardfloat
generators.FloatRec = R.FunctionGenerator("core.FloatRec",{"type","rate"},{"number"},
function(args)
  if args.type:deInterface():isFloat() then
    return C.FloatToFloatRec( args.type:deInterface().exp, args.type:deInterface().sig )
  elseif args.type:deInterface():isUint() or args.type:deInterface():isInt() then
    J.err( args.number==32 )
    return C.FloatRec( args.type:deInterface(), 8, 24 )
  else
    J.err(false, "FloatRec: unsupported input type:",args.type)
  end
end)

generators.FtoFR = R.FunctionGenerator("core.FtoFR",{"type","rate"},{"number"},
function(args)
  return C.FloatToFloatRec( args.type:deInterface().exp, args.type:deInterface().sig )
end, types.Float32)

generators.UtoFR = R.FunctionGenerator("core.UtoFR",{"type","rate"},{"number"},
function(args)
  J.err( args.T:isUint() )
  J.err( args.T.exp==0 )
  return C.FloatRec( args.T, 8, 24 )
end, P.NumberType("T"))

generators.ItoFR = R.FunctionGenerator("core.ItoFR",{"type","rate"},{"number"},
function(args)
  J.err( args.T:isInt() )
  J.err( args.T.exp==0 )
  return C.FloatRec( args.T, 8, 24 )
end, P.NumberType("T"))

-- convert to ieee float
generators.Float = R.FunctionGenerator("core.Float",{"type","rate"},{},
function(args)
  J.err( args.type:deInterface():isFloatRec(), "core.Float: input should be FloatRec, but is:",args.type )
  J.err( args.type:deInterface()==types.FloatRec32,"Float: input type should be FloatRec32, but is:",args.type:deInterface() )
  return C.Float( 8, 24 )
end)

generators.FRtoF = generators.Float

generators.FRtoI = R.FunctionGenerator("core.FloatToInt",{"type","rate","number"},{},
function(args)
  J.err( args.type:deInterface():isFloatRec(), "core.Float: input should be FloatRec, but is:",args.type )
  J.err( args.type:deInterface()==types.FloatRec32,"Float: input type should be FloatRec32, but is:",args.type:deInterface() )
  return C.FloatToInt( 8, 24, true, args.number )
end)

generators.FRtoU = R.FunctionGenerator("core.FloatToUint",{"type","rate","number"},{},
function(args)
  J.err( args.type:deInterface():isFloatRec(), "core.Float: input should be FloatRec, but is:",args.type )
  J.err( args.type:deInterface()==types.FloatRec32,"Float: input type should be FloatRec32, but is:",args.type:deInterface() )
  return C.FloatToInt( 8, 24, false, args.number )
end)

generators.SqrtF = R.FunctionGenerator("core.SqrtF",{"type","rate"},{},
function(args)
  J.err( args.type:deInterface():isFloatRec(), "SqrtF: expected FloatRec input, but is: ",args.type )
  J.err( args.type:deInterface()==types.FloatRec32,"SqrtF: input type should be FloatRec32, but is:",args.type:deInterface() )
  return C.SqrtF( 8, 24 )
end)

-- add floats
-- we intentionally named this something different than regular add, to clearly indicate it is float
generators.AddF = R.FunctionGenerator("core.AddF",{"type","rate"},{"async","number"},
function(args)
  
  local res = {}
  if args.number~=nil then
    -- add a const (unary op)
    assert(false)
  else
    J.err( args.type:deInterface():isTuple() )
    J.err( args.type:deInterface().list[1]==args.type:deInterface().list[2] )
    J.err( args.type:deInterface().list[1]:isFloatRec() )
    return C.sumF( args.type:deInterface().list[1].exp, args.type:deInterface().list[1].sig, false )
  end
end)

generators.SubF = R.FunctionGenerator("core.AddF",{"type","rate"},{"async","number"},
function(args)
  
  local res = {}
  if args.number~=nil then
    -- add a const (unary op)
    assert(false)
  else
    J.err( args.type:deInterface():isTuple() )
    J.err( args.type:deInterface().list[1]==args.type:deInterface().list[2] )
    J.err( args.type:deInterface().list[1]:isFloatRec() )
    return C.sumF( args.type:deInterface().list[1].exp, args.type:deInterface().list[1].sig, true )
  end
end)

-- mul floats
-- we intentionally named this something different than regular add, to clearly indicate it is float
generators.MulF = R.FunctionGenerator("core.MulF",{"type","rate"},{"async","number"},
function(args)
  local res = {}
  if args.number~=nil then
    -- mul by a const (unary op)
    J.err( args.type:deInterface():isFloatRec(), "MulF: when passed a constant, expects a FloatRec input, but is:",args.type )
    return C.mulFConst( args.type:deInterface().exp, args.type:deInterface().sig, args.number )
  else
    J.err( args.type:deInterface():isTuple(), "MulF: expected tuple input, but was: ",args.type )
    J.err( args.type:deInterface().list[1]==args.type:deInterface().list[2], "MulF: lhs and rhs must have same types! but input type is: ",args.type )
    J.err( args.type:deInterface().list[1]:isFloatRec(),"MulF: input should be FloatRec, but is: ",args.type )
    return C.mulF( args.type:deInterface().list[1].exp, args.type:deInterface().list[1].sig )
  end
end)

generators.DivF = R.FunctionGenerator("core.DivF",{"type","rate"},{"async","number"},
function(args)
  local res = {}
  if args.number~=nil then
    -- mul by a const (unary op)
    --J.err( args.type:deInterface():isFloatRec(), "MulF: when passed a constant, expects a FloatRec input, but is:",args.type )
    --return C.mulFConst( args.type:deInterface().exp, args.type:deInterface().sig, args.number )
    assert(false)
  else
    J.err( args.type:deInterface():isTuple(), "DivF: expected tuple input, but was: ",args.type )
    J.err( args.type:deInterface().list[1]==args.type:deInterface().list[2], "DivF: lhs and rhs must have same types! but input type is: ",args.type )
    J.err( args.type:deInterface().list[1]:isFloatRec(),"DivF: input must be FloatRec, but is: ",args.type )
    return C.SqrtF( args.type:deInterface().list[1].exp, args.type:deInterface().list[1].sig, true )
  end
end)

generators.GTF = R.FunctionGenerator("core.GTF",{"type","rate"},{"async","number"},
function(args)
  local res = {}
  if args.number~=nil then
    assert(false)
  else
    J.err( args.type:deInterface():isTuple(), "GTF: expected tuple input, but was: ",args.type )
    J.err( args.type:deInterface().list[1]==args.type:deInterface().list[2], "GTF: lhs and rhs must have same types! but input type is: ",args.type )
    J.err( args.type:deInterface().list[1]:isFloatRec() )
    return C.CMPF( args.type:deInterface().list[1].exp, args.type:deInterface().list[1].sig, ">" )
  end
end)

generators.LTF = R.FunctionGenerator("core.LTF",{"type","rate"},{"async","number"},
function(args)
  local res = {}
  if args.number~=nil then
    assert(false)
  else
    J.err( args.type:deInterface():isTuple(), "LTF: expected tuple input, but was: ",args.type )
    J.err( args.type:deInterface().list[1]==args.type:deInterface().list[2], "LTF: lhs and rhs must have same types! but input type is: ",args.type )
    J.err( args.type:deInterface().list[1]:isFloatRec() )
    return C.CMPF( args.type:deInterface().list[1].exp, args.type:deInterface().list[1].sig, "<" )
  end
end)

generators.GEF = R.FunctionGenerator("core.GTF",{"type","rate"},{"async","number"},
function(args)
  local res = {}
  if args.number~=nil then
    assert(false)
  else
    J.err( args.type:deInterface():isTuple(), "GTF: expected tuple input, but was: ",args.type )
    J.err( args.type:deInterface().list[1]==args.type:deInterface().list[2], "GTF: lhs and rhs must have same types! but input type is: ",args.type )
    J.err( args.type:deInterface().list[1]:isFloatRec() )
    return C.CMPF( args.type:deInterface().list[1].exp, args.type:deInterface().list[1].sig, ">=" )
  end
end)

generators.NegF = R.FunctionGenerator("core.NegF",{"type","rate"},{},
function(args) return C.NegF() end,
T.FloatRec32 )

-- size: size of each tile (NOT the number of tiles)
generators.Tile = R.FunctionGenerator("core.Tile",{"type","rate","size"},{},
function(args)
  if args.V~=args.insize then
    print("Warning: NYI - Tile on non-fully parallel array: ",args.type)
  end
  return C.Tile( args.T, args.insize[1], args.insize[2], args.size[1], args.size[2] )
end,
T.Array2d(P.DataType("T"),P.SizeValue("insize"),P.SizeValue("V") ) )

function generators.export(t)
  if t==nil then t=_G end
  for k,v in pairs(generators) do rawset(t,k,v) end
end

return generators
