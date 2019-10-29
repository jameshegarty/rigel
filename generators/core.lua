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
generators.Broadcast = R.FunctionGenerator("core.Broadcast",{"size","rate"},{},
function(args)
  if args.opt==2 then
    return C.broadcast(args.T,args.size[1],args.size[2])
  elseif args.opt==0 then
    J.err(args.size[2]==1,"Broadcast NYI: height>1")

    if (args.rate[1][1]:toNumber()*args.size[1]*args.size[2])/args.rate[1][2]:toNumber() > 1 then
      --assert(false)
      -- going fully sequential is too slow!
      local seq = args.rate[1][2]:toNumber()/args.rate[1][1]:toNumber()
      local V = (args.size[1]*args.size[2])/seq
      
      V = math.ceil(V)
      while (args.size[1]*args.size[2])%V~=0 do
        V = V + 1
      end
      seq = (args.size[1]*args.size[2])/V
      
      local res = C.compose("Generators_Broadcast_Parseq_"..tostring(args.size[1]),RM.upsampleXSeq(args.T,V,seq),RM.makeHandshake(C.broadcast(args.T,V,1)))

      -- hackity hack
      res.outputType = T.RV(T.ParSeq(T.Array2d(args.T,V),args.size))

      return res
    else
      return RM.upsampleXSeq(args.T,0,args.size[1],true)
    end
  elseif args.opt==1 then
    assert(false)
  else
    print("OPT",args.opt)
    assert(false)
  end
end,
P.SumType("opt",{
            T.RV(T.Par(P.DataType("T"))),
            T.RV(T.Par(P.DataType("T"))),
            T.rv(T.Par(P.DataType("T")))}),
P.SumType("opt",{
            T.RV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("outSize"))),
            T.RV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("outSize"))),
            T.rv(T.Par(T.array2d(P.DataType("T"),P.SizeValue("outSize"))))}))


-- Hack! clamp a variable sized array to a particular size
generators.ClampToSize = R.FunctionGenerator("core.ClampToSize",{"size"},{},
function(args)
  local res = generators.Function{"ClampToSize_W"..tostring(args.size[1]).."_H"..tostring(args.size[2]),T.RV(T.VarSeq(T.Par(args.T),args.InSize[1],args.InSize[2])),SDF{1,1},function(inp) return inp end}
  --print("CLAMPTO",res.inputType,res.outputType,types.isHandshakeAny(res.outputType))
  assert(R.isPlainFunction(res))
  local newType = T.RV(T.Seq(T.Par(args.T),args.size[1],args.size[2]))
  assert(res.outputType:lower()==newType:lower())
  res.outputType = newType

  --print("CLAMPSIZE",res.terraModule)
  --res.terraModule.methods.process:printpretty()
  
  return res
end,
T.RV(T.VarSeq(T.Par(P.DataType("T")),P.SizeValue("InSize"))),
T.RV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("OutSize"))))


-- bits to unsigned
generators.BtoU = R.FunctionGenerator("core.BtoU",{},{},
function(args)
  --J.err( args.type:isBits(), "BtoU input type should be Bits, but is: "..tostring(args.type))
  return C.cast(args.T,types.uint(args.T.precision))
end,
T.rv(T.Par(P.BitsType("T"))),
T.rv(T.Par(P.UintType("TypeOut"))))

-- convert Uint to Int
generators.UtoI = R.FunctionGenerator("core.UtoI",{},{},
function(args)
  return C.cast(args.T,types.Int(args.T.precision))
end,
T.rv(T.Par(P.UintType("T"))),
T.rv(T.Par(P.IntType("TypeOut"))))

-- convert Int to Uint
generators.ItoU = R.FunctionGenerator("core.ItoU",{},{},
function(args)
  return C.cast(args.T,types.Uint(args.T.precision))
end,
T.rv(T.Par(P.IntType("T"))),
T.rv(T.Par(P.UintType("TypeOut"))))

generators.LUT = R.FunctionGenerator("core.LUT",{"type1","luaFunction"},{},
function(args)
  --return C.cast(args.T,types.Uint(args.T.precision))
  --local function fnRounded(x) return math.floor(args.luaFunction(x)+0.5) end
  local vals = J.map(J.range(0,math.pow(2,args.T:verilogBits())-1),args.luaFunction)
  return RM.lut(args.T,args.type1,vals)
end,
T.rv(T.Par(P.UintType("T"))),
T.rv(T.Par(P.DataType("TypeOut"))))


generators.Print = R.FunctionGenerator("core.Print",{"type","rate"},{"string"},
function(args)
  if args.opt==1 then
    return C.print( args.T, args.string )
  elseif args.opt==0 then
    return C.print( T.Array2d(args.T,args.size), args.string )
  else
    assert(false)
  end
end,
P.SumType("opt",{T.rv(T.Par(T.array2d(P.NumberType("T"),P.SizeValue("size")))),
            T.rv(T.Par(P.NumberType("T")))}),
P.SumType("opt",{T.rv(T.Par(T.array2d(P.NumberType("T"),P.SizeValue("size")))),
                 T.rv(T.Par(P.NumberType("T")))}))

generators.FlattenBits = R.FunctionGenerator("core.FlattenBits",{"type"},{},function(args) return C.flattenBits(args.type) end)

generators.PartitionBits = R.FunctionGenerator("core.PartitionBits",{"type","number"},{},function(args) return C.partitionBits(args.type,args.number) end)

generators.Rshift = R.FunctionGenerator("core.Rshift",{},{"number"}, function(args)
  if args.number~=nil then
    return R.FunctionGenerator("core.Rshift",{},{},function(a) return C.rshiftConst(a.T,args.number) end,T.rv(T.Par(P.NumberType("T"))),T.rv(T.Par(P.NumberType("T"))) )
  else
    return R.FunctionGenerator("core.Rshift",{},{},function(a) return C.rshift(a.T1,a.T2) end,T.rv(T.Par(types.Tuple{P.NumberType("T1"),P.NumberType("T2")})),T.rv(T.Par(P.NumberType("T1"))) )
  end
end)

generators.AddMSBs = R.FunctionGenerator("core.AddMSBs",{},{"number"}, function(args) return C.addMSBs(args.T,args.number) end,T.rv(T.Par(P.NumberType("T"))),T.rv(T.Par(P.NumberType("T"))))
generators.RemoveMSBs = R.FunctionGenerator("core.RemoveMSBs",{"number"},{}, function(args) return C.removeMSBs(args.T,args.number) end, T.rv(T.Par(P.NumberType("T"))), T.rv(T.Par(P.NumberType("T"))) )
generators.RemoveLSBs = R.FunctionGenerator("core.RemoveLSBs",{"type","rate"},{"number"}, function(args) return C.removeLSBs(args.T,args.number) end, T.rv(T.Par(P.NumberType("T"))), T.rv(T.Par(P.NumberType("T"))) )

generators.Index = R.FunctionGenerator("core.Index",{},{"number","size"},
function(a)
  local ity
  if a.opt==0 then
    ity = T.array2d(a.T,a.V)
  else
    ity = T.tuple(a.list)
  end
  
  if a.size~=nil then
    return C.index(ity,a.size[1],a.size[2])
  else
    return C.index(ity,a.number)
  end
end,
P.SumType("opt",{
            T.rv(T.Par(T.array2d(P.DataType("T"),P.SizeValue("V")))),
            T.rv(T.Par(T.tuple(P.TypeList("list",P.DataType("T")))))
}),
P.SumType("opt",{
            T.rv(T.Par(P.DataType("T"))),
            T.rv(T.Par(P.DataType("T")))
}))

generators.ValueToTrigger = R.FunctionGenerator("core.ValueToTrigger",{"type","rate"},{}, function(args) return C.valueToTrigger(args.D) end,T.rv(T.Par(P.DataType("D"))),T.Interface())

generators.TriggerCounter = R.FunctionGenerator("core.TriggerCounter",{"number"},{},
function(args)
  --J.err( R.isHandshakeTrigger(args.type), "TriggerCounter: input should be HandshakeTrigger" )
  return RM.triggerCounter(args.number)
end,
types.RV(),
types.RV())

generators.TriggeredCounter = R.FunctionGenerator("core.TriggeredCounter",{"number"},{},
function(args)
  return RM.triggeredCounter( args.T, args.number, nil, true )
end,
types.RV(types.Par(P.DataType("T"))),
types.RV(types.Seq(types.Par(P.DataType("T")),P.SizeValue("size") )) )

generators.TriggerBroadcast = R.FunctionGenerator("core.TriggerBroadcast",{"number"},{},
function(args)
--  J.err( R.isHandshakeTrigger(args.type), "TriggerBroadcast: input should be HandshakeTrigger" )
  return C.triggerUp(args.number)
end,
types.RV(),
types.RV())

generators.FanOut = R.FunctionGenerator("core.FanOut",{},{"number","size"},
function(args)
  --J.err( R.isHandshake(args.type) or args.type:is("HandshakeFramed") or args.type:is("HandshakeTrigger"),"FanOut: expected handshake input, but is: "..tostring(args.type))
  --local mixed, dims
  --if args.type:is("HandshakeFramed") then mixed,dims=args.type.params.mixed,args.type.params.dims end
  local size = args.size
  if args.number~=nil then size={args.number,1} end
  
  return R.FunctionGenerator("core.FanOut",{},{},
    function(a)
      return RM.broadcastStream( a.S, size[1], size[2] )
    end,
    P.SumType("opt",{types.RV(P.ScheduleType("S")),
                     types.HandshakeTrigger}),
    P.SumType("opt",{types.array2d(types.RV(P.ScheduleType("S")),size[1],size[2]),
                     types.array2d(types.HandshakeTrigger,size[1],size[2])}))
end)

generators.FanIn = R.FunctionGenerator("core.FanIn",{},{"bool"},
function(args)
--  for k,v in ipairs(args.list) do
--    err(v:isRV(),"FanIn: error, NYI - FanIn should only get an InterfaceTuple of RV interfaces")
--  end
  
  --if R.isHandshakeTuple(args.type) then
  --print("FANIN",args.opt,args.list)
  
  if args.opt==0 then
    return RM.packTuple(args.list,args.bool)
    --elseif R.isHandshakeTriggerArray(args.type) then
  elseif args.opt==1 or args.opt==2 then
    return RM.packTuple(args.list,args.bool,args.size)
  else
    J.err(false, "FanIn: expected handshake tuple input, but is: "..tostring(args.type))
  end
end,
P.SumType("opt",{types.tuple(P.TypeList("list",types.RV(P.ScheduleType("S")))),
                 types.array2d(T.RV(P.ScheduleType("S")),P.SizeValue("size")),
                 types.tuple(P.TypeList("list",types.RV()))}),
P.SumType("opt",{types.RV(types.tuple(P.TypeList("list",P.ScheduleType("S")))),
                 types.RV(P.ScheduleType("S"),P.SizeValue("size")),
                 types.RV()})
)

generators.FIFO = R.FunctionGenerator("core.FIFO",{"number"},{"bool"},
function(args)
  --J.err( R.isHandshake(args.type) or R.isHandshakeTrigger(args.type),"FIFO: expected handshake input, but is: "..tostring(args.type))
  --local ty = R.extractData(args.type)
  if args.opt==0  then
    return C.fifo( args.S, args.number, args.bool )
  else
    return C.fifo( nil, args.number, args.bool )
  end
end,
P.SumType("opt",{types.RV(P.ScheduleType("S")),types.RV()}),
P.SumType("opt",{types.RV(P.ScheduleType("S")),types.RV()}))
  
--[=[generators.Add = R.FunctionGenerator("core.Add",{"type","rate"},{"bool","number"},
function(args)
  if args.number~=nil then
    -- add a const (unary op)
    return C.plusConst(args.type,args.number)
  else
    J.err( args.type:isTuple(), "generators.Add: type should be tuple, but is: "..tostring(args.type) )
    J.err( args.type.list[1]==args.type.list[2], "generators.Add: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )
    return C.sum( args.type.list[1], args.type.list[1], args.type.list[1], args.bool )
  end
  end)]=]

generators.NE = R.FunctionGenerator("core.NE",{},{"async","number"},
function(args)
  
  local res = {}
  if args.number~=nil then
    -- add a const (unary op)
    return R.FunctionGenerator( "core.NE", {}, {}, function(a) return C.NEConst(a.T,args.number) end, T.rv(T.Par(P.DataType("T"))), T.rv(T.Par(types.bool()) ) )
  else
    return R.FunctionGenerator("core.NE", {}, {}, function(a) return C.NE( a.T, args.async ) end, T.rv(T.Par(T.tuple{P.DataType("T"),P.DataType("T")})),T.rv(T.Par(types.bool())) )
  end
end)


generators.Add = R.FunctionGenerator("core.Add",{},{"async","number"},
function(args)
  
  local res = {}
  if args.number~=nil then
    -- add a const (unary op)
    return R.FunctionGenerator( "core.Add", {}, {}, function(a) return C.plusConst(a.T,args.number) end, T.rv(T.Par(P.NumberType("T"))), T.rv(T.Par(P.NumberType("T")) ) )
  else
    return R.FunctionGenerator("core.Add", {}, {}, function(a) return C.sum( a.T, a.T, a.T, args.async ) end, T.rv(T.Par(T.tuple{P.NumberType("T"),P.NumberType("T")})),T.rv(T.Par(P.NumberType("T"))) )
  end
end)

-- {{idxType,vType},{idxType,vType}} -> {idxType,vType}
-- async: 0 cycle delay
generators.ArgMax = R.FunctionGenerator("core.ArgMax", {}, {"async"},
function(a) return C.argmin( a.idx, a.T, a.async, true ) end,
T.rv(T.Par(T.tuple{T.tuple{P.DataType("idx"),P.NumberType("T")},T.tuple{P.DataType("idx"),P.NumberType("T")}})),
T.rv(T.Par(T.tuple{P.DataType("idx"),P.NumberType("T")})) )

generators.ArgMin = R.FunctionGenerator("core.ArgMin", {}, {"async"},
function(a) return C.argmin( a.idx, a.T, a.async, true ) end,
T.rv(T.Par(T.tuple{T.tuple{P.DataType("idx"),P.NumberType("T")},T.tuple{P.DataType("idx"),P.NumberType("T")}})),
T.rv(T.Par(T.tuple{P.DataType("idx"),P.NumberType("T")})) )

generators.Neg = R.FunctionGenerator("core.Neg", {}, {"async"},
function(a) return C.neg( a.T.precision ) end,
T.rv(T.Par(P.IntType("T"))),
T.rv(T.Par(P.IntType("T"))) )

generators.Sub = R.FunctionGenerator("core.Sub",{},{"async"},
function(args)
  return C.sub( args.T, args.T, args.T, args.async )
end, T.rv(T.Par(T.tuple{P.NumberType("T"),P.NumberType("T")})),T.rv(T.Par(P.NumberType("T"))))

generators.Mul = R.FunctionGenerator("core.Mul",{},{"number","async"},
function(args)
  if args.number~=nil then
    return R.FunctionGenerator("core.Mul",{},{"async"},
      function(a) return C.multiplyConst( a.T, args.number, a.async ) end,
      T.rv(T.Par(P.NumberType("T"))), T.rv(T.Par(P.NumberType("T"))))
  else
    return R.FunctionGenerator("core.Mul",{},{"bool"},function(args) return C.multiply( args.T, args.T, args.T, args.async ) end, T.rv(T.Par(T.tuple{P.NumberType("T"),P.NumberType("T")})), T.rv(T.Par(P.NumberType("T"))))
  end
end)

generators.GT = R.FunctionGenerator("core.GT",{},{"number"},
function(args)
  if args.number~=nil then
    return R.FunctionGenerator("core.GT",{},{"async"},
      function(a) return C.GTConst( a.T, args.number, a.async ) end,
      T.rv(T.Par(P.NumberType("T"))), T.rv(T.Par(types.bool())))
  else
    return R.FunctionGenerator("core.GT",{},{"async"},function(args) return C.GT( args.T, args.T, args.T, args.async ) end, T.rv(T.Par(T.tuple{P.NumberType("T"),P.NumberType("T")})), T.rv(T.Par(types.bool())))
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

generators.Abs = R.FunctionGenerator("core.Abs",{},{"async"},
function(a) return C.Abs( a.T, a.async ) end,
T.rv(T.Par(P.NumberType("T"))), T.rv(T.Par(P.NumberType("T"))))

    
--[=[
generators.LT = R.FunctionGenerator("core.LT",{"type","rate"},{"number"},
function(args)
  if args.number~=nil then
    J.err( args.type:isUint() or args.type:isInt(), "generators.LT: type should be int or uint, but is: "..tostring(args.type) )
    return C.LTConst(args.type, args.number )
  else
    J.err( args.type:isTuple(), "generators.LT: type should be tuple, but is:"..tostring(args.type) )
    J.err( args.type.list[1]==args.type.list[2], "generators.LT: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )

    return C.LT( args.type.list[1], args.type.list[1] )
  end
  end)]=]

generators.And = R.FunctionGenerator("core.And",{"type","rate"},{"async"},
function(args)
  if args.opt==0 then
    return C.And
  elseif args.opt==1 then
    return C.AndUint(args.T.precision)
  else
    assert(false)
  end
end,
P.SumType("opt",
          {types.rv(types.Par(types.tuple{types.bool(),types.bool()})),
           types.rv(types.Par(types.tuple{P.UintType("T"),P.UintType("T")}))}),
P.SumType("opt",
          {types.rv(types.Par(types.bool())),
           types.rv(types.Par(P.UintType("T")))}) )

generators.Not = R.FunctionGenerator("core.Not",{"type","rate"},{"bool"},
function(args)
  J.err( args.type==types.bool(), "generators.Not: input type should be bool, but is: "..tostring(args.type) )
  return C.Not
end)

generators.Zip = R.FunctionGenerator("core.Zip",{},{},
function(args)
--  J.err( args.D:isTuple(), "generators.Zip: type should be tuple, but is: "..tostring(args.type) )

  if args.opt==0 then
    local typelist = {}
    for k,v in ipairs(args.list) do
      typelist[k] = v:arrayOver()
    end
  
    return RM.SoAtoAoS( args.size[1], args.size[2], typelist )
  elseif args.opt==1 or args.opt==2 or args.opt==3 then

    local mode = "Seq"
    if args.opt==2 then mode="VarSeq" end
    if args.opt==3 then mode="ParSeq" end

    if args.opt==3 then
      --return RM.ZipSchedules( mode, schedulelist, args.size[1], args.size[2], args.V[1], args.V[2] )
      local schedulelist = {}
      for k,v in ipairs(args.list) do
        schedulelist[k] = v.over.over
      end

      return RM.SoAtoAoS( args.V[1], args.V[2], schedulelist, nil, args.size[1], args.size[2] )
    else
      local schedulelist = {}
      for k,v in ipairs(args.list) do
        schedulelist[k] = v.over
      end

      return RM.ZipSeq( mode, schedulelist, args.size[1], args.size[2] )
    end
  else
    assert(false)
  end
end,
P.SumType("opt",
          {T.rv(T.Par(T.tuple(P.TypeList("list",T.array2d(P.DataType("D"),P.SizeValue("size")))))),
           T.rv(T.tuple(P.TypeList("list",T.Seq(P.ScheduleType("S"),P.SizeValue("size") )))),
           T.rv(T.tuple(P.TypeList("list",T.VarSeq(P.ScheduleType("S"),P.SizeValue("size") )))),
           T.rv(T.tuple(P.TypeList("list",T.ParSeq(T.Array2d(P.DataType("D"),P.SizeValue("V")),P.SizeValue("size") ))))}),
P.SumType("opt",
          {T.rv(T.Par(P.DataType("D"))),
           T.rv(T.Seq(P.ScheduleType("S"),P.SizeValue("size"))),
           T.rv(T.VarSeq(P.ScheduleType("S"),P.SizeValue("size"))),
           T.rv(T.ParSeq(T.Array2d(P.DataType("out"),P.SizeValue("V")),P.SizeValue("size")))})
)

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

generators.Stencil = R.FunctionGenerator("core.Stencil",{"bounds"},{},
function(a)
  if a.opt==0 then
    assert(a.V[2]==1)
    return C.stencilLinebuffer( a.T, a.size[1], a.size[2], a.V[1], a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], true )
  elseif a.opt==1 then
    return C.stencilLinebuffer( a.T, a.size[1], a.size[2], 0, a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], true )
  else
    assert(false)
  end
end,
P.SumType("opt",{types.rv(types.ParSeq(types.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size"))),
                 types.rv(types.Seq(types.Par(P.DataType("T")),P.SizeValue("size")))}),
P.SumType("opt",{
  types.rv(types.ParSeq(types.array2d(types.array2d(P.DataType("T"),P.SizeValue("stSize")),P.SizeValue("V")),P.SizeValue("size"))),
  types.rv(types.Seq(types.Par(types.array2d(P.DataType("T"),P.SizeValue("stSize"))),P.SizeValue("size")))}) 
)

generators.Pad = R.FunctionGenerator("core.Pad",{"bounds"},{},
function(a)
  if a.opt==0 then
    assert(a.V[2]==1)
    return RM.padSeq(a.T,a.size[1],a.size[2],a.V[1],a.bounds[1],a.bounds[2],a.bounds[3],a.bounds[4],0,true)
  else
    return RM.padSeq(a.T,a.size[1],a.size[2],0,a.bounds[1],a.bounds[2],a.bounds[3],a.bounds[4],0,true)
  end
end,
P.SumType("opt",
          {types.rV( T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size")) ),
           T.rV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("size")))}),
P.SumType("opt",{
            types.rRV( T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("sizeOut"))),
            T.rRV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("sizeOut")))})
)


generators.CropSeq = R.FunctionGenerator("core.CropSeq",{"type","size","number","bounds","rate"},{},
function(args)
  local A = args.type.over.over
  if args.number>0 then A  = args.type.over.over:arrayOver() end
  
  return RM.cropSeq(A,args.size[1],args.size[2],args.number,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4])
end)

generators.Crop = R.FunctionGenerator("core.Crop",{"bounds"},{},
function(a)
  if a.opt==0 then
    assert(a.V[2]==1)
    return RM.cropSeq(a.T,a.size[1],a.size[2],a.V[1],a.bounds[1],a.bounds[2],a.bounds[3],a.bounds[4],true)
  elseif a.opt==1 then
    return RM.cropSeq(a.T,a.size[1],a.size[2],0,a.bounds[1],a.bounds[2],a.bounds[3],a.bounds[4],true)
  else
    print("OPT",a.opt)
    assert(false)
  end
end,
P.SumType("opt",{
            T.rv(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size"))),
            T.rv(T.Seq(T.Par(P.DataType("T")),P.SizeValue("size")))}),
P.SumType("opt",{
            T.rvV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("sizeOut"))),
            T.rvV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("sizeOut")))})
)

generators.Downsample = R.FunctionGenerator("core.Downsample",{"size"},{},
function(args)
  if args.opt==0 then
    assert(args.V[2]==1)
    return C.downsampleSeq( args.T, args.imsize[1], args.imsize[2], args.V[1], args.size[1], args.size[2], true )
  elseif args.opt==1 then
    return C.downsampleSeq( args.T, args.imsize[1], args.imsize[2], 0, args.size[1], args.size[2], true )
  else
    assert(false)
  end
end,
P.SumType("opt",{
            T.rV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("imsize"))),
            T.rV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("imsize")))}),
P.SumType("opt",{
            T.rRV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("sizeOut"))),
            T.rRV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("sizeOut")))})
)

generators.Upsample = R.FunctionGenerator("core.Upsample",{"size"},{},
function(args)
  if args.opt==0 then
    assert(args.V[2]==1)
    return C.upsampleSeq( args.T, args.imsize[1], args.imsize[2], args.V[1], args.size[1], args.size[2], true )
  elseif args.opt==1 then
    return C.upsampleSeq( args.T, args.imsize[1], args.imsize[2], 0, args.size[1], args.size[2], true )
  else
    assert(false)
  end
end,
P.SumType("opt",{
            T.rV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("imsize"))),
            T.rV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("imsize")))}),
P.SumType("opt",{
            T.rRV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("sizeOut"))),
            T.rRV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("sizeOut")))})
)

generators.PosSeq = R.FunctionGenerator("core.PosSeq",{"size","number"},{},
function(args)
  --if args.type~=nil then
  --  J.err( args.type==types.null(), "PosSeq: expected null input")
  --end
  return RM.posSeq(args.size[1],args.size[2],args.number)
end,
types.Interface(),
types.rv(types.Par(P.DataType("D"))))

generators.Pos = R.FunctionGenerator("core.PosSeq",{"size","rate"},{},
function(args)
  local V = (args.size[1]*args.size[2]*args.rate[1][1]:toNumber())/args.rate[1][2]:toNumber()
  local V0 = V
  if V<1 then V=0;V0=1 end
  local res = generators.Function{"Pos_With_Trig",T.RV(),SDF{1,args.size[1]*args.size[2]/V0},
    function(inp) return generators.Map{RM.posSeq(args.size[1],args.size[2],V,nil,true,true)}(generators.TriggerBroadcast{args.size[1]*args.size[2]/V0}(inp)) end}

  return res
--  return RM.posSeq( args.size[1], args.size[2], V, nil, true, true )
end,
types.RV(),
types.RV(P.ScheduleType("D")))

generators.Flatten = R.FunctionGenerator("core.Flatten",{},{},
function(args)
  local res = generators.Function{"Flatten_VW"..tostring(args.inner[1]).."_VH"..tostring(args.inner[2]).."_W"..tostring(args.outer[1]).."_H"..tostring(args.outer[2]),T.RV(T.Seq(T.Par(T.Array2d(args.D,args.inner)),args.outer)),SDF{1,1},function(inp) return inp end}

  assert(R.isPlainFunction(res))
  local newType = T.RV(T.ParSeq(T.Array2d(args.D,args.inner),args.outer[1]*args.inner[1],args.outer[2]*args.inner[2]))
  assert(res.outputType:lower()==newType:lower())
  res.outputType = newType

  return res
end,
T.RV(T.Seq(T.Par(T.Array2d(P.DataType("D"),P.SizeValue("inner"))),P.SizeValue("outer"))),
T.RV(T.ParSeq(T.Array2d(P.DataType("D"),P.SizeValue("inner")),P.SizeValue("outer"))))

generators.Map = R.FunctionGenerator("core.Map",{"rigelFunction"},{},
function(args)
  J.err(R.isPlainFunction(args.rigelFunction),"core.Map should only work on plain functions")

  return R.FunctionGenerator("core.Map",{},{},function(a) return args.rigelFunction end,
                             args.rigelFunction.inputType,
                             args.rigelFunction.outputType)
end)
                                        
generators.Reduce = R.FunctionGenerator("core.Reduce",{"rigelFunction"},{},
function(args)

  local fnVars = {}
  local fnType = T.rv(T.Par(types.tuple{P.DataType("T"),P.DataType("T")}))
  
  J.err( fnType:isSupertypeOf(args.rigelFunction.inputType,fnVars), "Reduce: input fn should have type: "..tostring(fnType)..", but instead has type: "..tostring(args.rigelFunction.inputType) )

  --for k,v in pairs(fnVars) do print("FNVARS",k,v) end
  return R.FunctionGenerator("core.Reduce",{"rate"},{},
    function(a)

      local joinset = J.joinSet(fnVars,a,true)
      --for k,v in pairs(joinset) do print("A",k,v) end
      local spType = R.specialize(args.rigelFunction.inputType, joinset )

      local fn = args.rigelFunction{spType,SDF{1,1}}
      assert(R.isPlainFunction(fn))
        
      if a.opt==0 then
        --print("RSOPT0",a.size[1],a.size[2])
        return RM.reduceSeq( fn, a.size[1], a.size[2], true)
      elseif a.opt==1 then
        return RM.reduceParSeq( fn, a.V[1], a.V[2], a.size[1], a.size[2] )
      elseif a.opt==2 then
        return RM.reduce( fn, a.size[1],a.size[2])
      else
        assert(false)
      end
    end,
    P.SumType("opt",{
                types.rv(types.Seq(T.Par(fnVars.T),P.SizeValue("size"))),
                types.rv(types.ParSeq(T.array2d(fnVars.T,P.SizeValue("V")),P.SizeValue("size"))),
                types.rv(types.Par(types.array2d(fnVars.T,P.SizeValue("size"))))}),
    P.SumType("opt",{
                types.rvV(types.Par(fnVars.T)),
                types.rvV(types.Par(fnVars.T)),
                types.rv(types.Par(fnVars.T))}))
end)

--[=[
generators.Reduce = R.FunctionGenerator("core.Reduce",{"type","rigelFunction","rate"},{},
function(args)

  local arrayOver
  if args.type:is("StaticFramed") then
    arrayOver = args.type:framedOver()
  else
    J.err( args.type:isArray(), "generators.Reduce: type should be array, but is: "..tostring(args.type) )
    arrayOver = args.type:arrayOver()
  end
  
  local mod
  if R.isFunctionGenerator(args.rigelFunction) then
    mod = args.rigelFunction{types.tuple{arrayOver,arrayOver},args.rate}
    assert( R.isPlainFunction(mod) )
  else
    assert(false)
  end

  if args.type:is("StaticFramed") then
    local seq = RM.reduceSeq( mod, args.type:FV()/(args.type:FW()*args.type:FH()), true )

    if args.type:FV()>1 then
      local RED = RM.reduce( mod, args.type:FV(), 1 )

      local par = RM.mapFramed(RED,args.type:FW(),args.type:FH(),true,(args.type:FW()*args.type:FH())/args.type:FV(),1,false)
      local res = C.compose("Generators_Reduce_"..seq.name.."_"..par.name,seq,par)

      return res
    else
      return seq
    end
  else
    return RM.reduce( mod, args.type.size[1], args.type.size[2] )
  end
  end)]=]

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
P.SumType("opt",{T.rV(T.Par(T.Array2d(P.DataType("T"),P.SizeValue("size"))))}),
P.SumType("opt",{T.rRV(P.ScheduleType("S"))}))

-- serialize to a particular vector width ("number")
generators.SerToWidth = R.FunctionGenerator("core.SerToWidth",{"number"},{},
function(args)
  if args.number==0 then

    return R.FunctionGenerator("core.SerToWidth",{},{},
      function(a)
        if a.opt==0 then
          return RM.changeRate( a.T, a.size[2], a.size[1], args.number, true, a.size[1], a.size[2] )
        elseif a.opt==1 then

          if a.V[1]*a.V[2]==1 and args.number==0 then
            -- special case of taking [1,1;w,h} to {w,h} (not really a changerate)

            local res = generators.Module{
              "SerToWidth_Convert_Array_to_scalar_"..tostring(a.T), SDF{1,1},
              T.rV(T.Par(T.array2d(a.T,1,1))),
              function(inp)
                return generators.Index{0}(inp)
            end}
            assert(R.isPlainFunction(res))

            res.inputType = types.rV(types.ParSeq(T.array2d(a.T,1,1),a.size))
            res.outputType = types.rRV(types.Seq(T.Par(a.T),a.size))

            return res
          else
           return RM.changeRate( a.T, a.V[2], a.V[1], args.number, true, a.size[1], a.size[2] )
          end
        else
          assert(false)
        end
      end,
      P.SumType("opt",{
                  T.rV(T.Par(T.array2d(P.DataType("T"),P.SizeValue("size")))),
                  T.rV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size")))}),
      P.SumType("opt",{
                  T.rRV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("sizeOut"))),
                  T.rRV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("sizeOut")))}) )

  else
    return R.FunctionGenerator("core.SerToWidth",{},{},
      function(a)
        if a.opt==0 then
          return RM.changeRate( a.T, a.size[2], a.size[1], args.number, true, a.size[1], a.size[2] )
        elseif a.opt==1 then                
          return RM.changeRate( a.T, a.V[2], a.V[1], args.number, true, a.size[1], a.size[2] )
        else
          assert(false)
        end
      end,
      P.SumType("opt",{
            T.rV(T.Par(T.array2d(P.DataType("T"),P.SizeValue("size")))),
            T.rV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size")))}),
      P.SumType("opt",{
            T.rRV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("VOut")),P.SizeValue("sizeOut"))),
            T.rRV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("VOut")),P.SizeValue("sizeOut")))}) )
  end
end)

generators.SerSeq = R.FunctionGenerator("core.SerSeq",{"type","number","rate"},{},
function(args)
  --J.err( args.type:isArray(), "generators.SerSeq: type should be array, but is: "..tostring(args.type) )

  J.err(args.size[1]%args.number==0,"G.SerSeq: number of cycles must divide array size")
  return RM.changeRate( args.T, args.size[2], args.size[1], args.size[1]/args.number )
end,
types.rV(types.Par(types.array2d(P.DataType("T"),P.SizeValue("size")))),
types.rRV(types.Par(types.array2d(P.DataType("T"),P.SizeValue("size")))) )


generators.DeserSeq = R.FunctionGenerator("core.DeserSeq",{"number"},{},
function(args)
--  if args.opt==0 then
    -- change T{W,H} to T[W,H]
    --assert(args.totalSize[2]==1)
    --assert(args.totalSize[1]*args.totalSize[2]==args.number)
  --J.err( args.type:isArray(), "generators.Deser: type should be array, but is: "..tostring(args.type) )
  return RM.changeRate( args.T, args.size[2], args.size[1], args.size[1]*args.number )
--  else
--    assert(false)
--  end
  --return C.changeRateFramed( args.type:arrayOver(), args.type:arrayLength()[2], args.type:arrayLength()[1], args.number, false )
end,
types.rV(types.Par(types.array2d(P.DataType("T"),P.SizeValue("size")))),
types.rRV(types.Par(types.array2d(P.DataType("T"),P.SizeValue("size")))) )

-- Number: this is the factor of # of parallel tokens we should concat.
-- so [1,4;4,4} with factor 2 would end up [2,4;4,4}
-- [1,4;4,4} with factor 4 would end up [4,4]
generators.Deser = R.FunctionGenerator("core.Deser",{"number"},{},
function(args)
  if args.opt==0 then
    -- change T{W,H} to T[W,H]
    assert(args.totalSize[2]==1)
    assert(args.totalSize[1]*args.totalSize[2]==args.number)
  --J.err( args.type:isArray(), "generators.Deser: type should be array, but is: "..tostring(args.type) )
    return RM.changeRate( args.T, 1, 0, args.number, true, args.totalSize[1], args.totalSize[2] )
  else
    assert(false)
  end
  --return C.changeRateFramed( args.type:arrayOver(), args.type:arrayLength()[2], args.type:arrayLength()[1], args.number, false )
end,
P.SumType("opt",{types.rV(types.Seq(types.Par(P.DataType("T")),P.SizeValue("totalSize")))}),
P.SumType("opt",{types.rRV(types.Par(types.array2d(P.DataType("T"),P.SizeValue("totalSize"))))}))

generators.Fwrite = R.FunctionGenerator("core.Fwrite",{"string"},{"filenameVerilog"},
function(args)
  --return RS.modules.fwriteSeq({type=args.type,filename=args.string})
  return RM.fwriteSeq(args.string,args.T,args.filenameVerilog,true)
end,
T.rv(T.Par(P.DataType("T"))),
T.rv(T.Par(P.DataType("T"))))

generators.Fread = R.FunctionGenerator("core.Fread",{"string","type","type1"},{"filenameVerilog"},
function(args)
  --return RS.modules.fwriteSeq({type=args.type,filename=args.string})
  return RM.freadSeq( args.string, args.type1, true )
end,
T.rv(T.Par(T.Uint(32))),
T.rv(T.Par(P.DataType("T"))))

-- assert that the input stream is the same as the file. Early out on errors.
generators.Fassert = R.FunctionGenerator("core.Fassert",{"type","string"},{},
function(args)
  return C.fassert(args.string,args.type)
end)

generators.AXIReadBurstSeq = R.FunctionGenerator("core.AXIReadBurstSeq",{"type","string","size","rate","number","rigelFunction"},{},
function(args)
  -- note: type here should be explicitly passed by the user! This is the type of data we want
  return SOC.readBurst(args.string, args.size[1], args.size[2], args.type, args.number, false, nil, args.rigelFunction )
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

generators.Module = R.FunctionGenerator("core.Module",{"luaFunction","type"},{"string","rate","instanceList"},
function(args)
  if args.string==nil then
    args.string = "unnamedModuleGen"..__unnamedID
    __unnamedID = __unnamedID+1
  end

  local input = R.input( args.type, args.rate )
  local out = args.luaFunction(input)
  J.err( R.isIR(out), "Module: user function returned something other than a Rigel value? "..tostring(out))
  
  return RM.lambda( args.string, input, out, args.instanceList )
end)

generators.Function = generators.Module

generators.Generator = R.FunctionGenerator("core.Module",{"luaFunction","type","type1"},{"string","rate","instanceList"},
function(args)
  if args.string==nil then
    args.string = "unnamedModuleGen"..__unnamedID
    __unnamedID = __unnamedID+1
  end

  return R.FunctionGenerator(args.string,{"type","rate"},{},
    function(a)
      local input = R.input( a.type, args.rate )
      local out = args.luaFunction(input)
      J.err( R.isIR(out), "Module: user function returned something other than a Rigel value? "..tostring(out))
  
      return RM.lambda( args.string, input, out, args.instanceList )
    end,args.type,args.type1)
end)

--generators.Generator = generators.Module

-- rigelFunction: the fn to call to perform the AXI read
generators.AXIReadBurst = R.FunctionGenerator("core.AXIReadBurst",{"string","size","type","rate","rigelFunction"},{"number","address"},
function(args)
  local numb = args.number
  if numb==nil then
    numb = math.ceil((args.size[1]*args.size[2]*Uniform(args.rate[1][1]):toNumber())/Uniform(args.rate[1][2]):toNumber())
  end
  return SOC.readBurst( args.string, args.size[1], args.size[2], args.type, numb, true, args.address, args.rigelFunction )
end)

generators.AXIRead = R.FunctionGenerator("core.AXIRead",{"string","number","rigelFunction","type1"},{},
function(args)
  return SOC.read( args.string, args.number, args.type1, args.rigelFunction )
end,
types.RV(types.Par(types.uint(32))),
types.RV(types.Par(P.DataType("outtype"))))

generators.AXIWriteBurst = R.FunctionGenerator("core.AXIWriteBurst",{"string","rigelFunction"},{"address"},
function(a)
  if a.opt==0 then
    return SOC.writeBurst( a.string, a.size[1], a.size[2], a.T, a.V[1], a.V[2], true, a.rigelFunction, a.address )
  elseif a.opt==1 then
    return SOC.writeBurst( a.string, a.size[1], a.size[2], a.T, 0, 0, true, a.rigelFunction, a.address )
  else
    assert(false)
  end
end,
P.SumType("opt",{
            types.Handshake(types.ParSeq(types.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size"))),
            types.Handshake(types.Seq(T.Par(P.DataType("T")),P.SizeValue("size")))}),
P.SumType("opt",{types.HandshakeTrigger,types.HandshakeTrigger}) )

generators.Reshape = R.FunctionGenerator("core.Reshape",{"type","rate"},{},
function(args)

  local ratio = Uniform(args.rate[1][1]):toNumber()/Uniform(args.rate[1][2]):toNumber()


  if ratio<1 then
    if args.type:isRV() then

      local function reduceRatio(ty)
        --print("ReduceRatio",ty,ratio)
        if ty:is("Par") or ty:is("ParSeq") then
          if ty.over:isArray() then
            -- if not an array, can't really do anything

            local chan = ty.over.size[1]*ratio -- NYI, 2d
            if chan<1 then chan=0 end
            local res = generators.SerToWidth{chan}
            --print("ReduceRationFN","CHAN",chan,res)
            return res
          else
            assert(false)
          end
        elseif ty:is("Seq") then
            -- already fully sequential, try to apply to inner dim?
          return reduceRatio(ty.over)
        else
          J.err(false,"Reshape: upsupported type "..tostring(ty)) 
        end
      end
      return reduceRatio(args.type.over,ratio)
    else
      print("Reshape: upsupported type ",args.type)
      assert(false)
    end
  end

  -- if ratio >=1, don't do anything:
  return generators.Identity
end)

-- change dims of array
generators.ReshapeArray = R.FunctionGenerator("core.ReshapeArray",{"size"},{},
function(args)
  J.err( args.size[1]*args.size[2]==args.insize[1]*args.insize[2], "ReshapeArray: total number of items must not change. Input size: "..tostring(args.insize).." requested reshape: "..tostring(args.size[1])..","..tostring(args.size[2]) )
  return C.cast(T.Array2d(args.T,args.insize),T.Array2d(args.T,args.size))
  --return C.oddEvenMergeSort( args.T, args.size[1], args.rigelFunction )
end,
types.rv(types.Par(types.array2d(P.DataType("T"),P.SizeValue("insize")))),
types.rv(types.Par(types.array2d(P.DataType("T"),P.SizeValue("outsize")))) )

generators.Sort = R.FunctionGenerator("core.Sort",{"rigelFunction"},{},
function(args)
--  J.err( args.type:isArray(),"generators.Sort: input must be array, but is: "..tostring(args.type) )
  J.err( args.size[2]==1,"generators.Sort: must be 1d array" )
  return C.oddEvenMergeSort( args.T, args.size[1], args.rigelFunction )
end,
types.rv(types.Par(types.array2d(P.DataType("T"),P.SizeValue("size")))),
types.rv(types.Par(types.array2d(P.DataType("T"),P.SizeValue("size")))) )

generators.Identity = R.FunctionGenerator("core.Identity",{},{},
function(args) return C.identity(args.T) end,
T.rv(T.Par(P.DataType("T"))),
T.rv(T.Par(P.DataType("T"))))

generators.Sel = R.FunctionGenerator("core.Sel",{},{},
function(args)
  --J.err( args.type:isTuple(), "generators.Sel: input should be tuple" )
  return C.select(args.T)
end,
T.rv(T.Par(types.tuple{types.bool(),P.DataType("T"),P.DataType("T")})),
T.rv(T.Par(P.DataType("T"))) )


generators.Slice = R.FunctionGenerator("core.Slice",{"size"},{},
function(args)
  --J.err( args.type:isArray(), "generators.Slice: input must be array" )
  J.err( args.arsize[2]==1, "generators.Slice: NYI - only 1d arrays supported" )
  return C.slice( types.array2d(args.T,args.arsize), args.size[1], args.size[2], 0, 0)
end,
types.rv(types.Par(types.array2d(P.DataType("T"),P.SizeValue("arsize")))),
types.rv(types.Par(types.array2d(P.DataType("T"),P.SizeValue("arsize")))) )

generators.TupleToArray = R.FunctionGenerator("core.TupleToArray",{},{},
function(a)
  return C.tupleToArray( a.T.list[1], #a.T.list )
end,
types.rv(types.Par(P.TupleType("T"))),
types.rv(types.Par(P.DataType("D"))) )

generators.ArrayToTuple = R.FunctionGenerator("core.ArrayToTuple",{},{},
function(a)
  local C = require "generators.examplescommon"
  return C.ArrayToTuple( a.D, a.size[1], a.size[2] )
end,
T.rv(T.Par(T.array2d(P.DataType("D"),P.SizeValue("size")))),
T.rv(T.Par(P.DataType("D"))))

generators.Filter = R.FunctionGenerator("core.Filter",{"size"},{},
function(args)
--  J.err( args.type:isTuple(), "generators.FilterSeq: input should be tuple" )
--  J.err( args.type.list[2]:isBool(), "generators.FilterSeq: input should be tuple of type {A,bool}, but is: "..tostring(args.type) )
  return RM.filterSeq( args.T, args.insize[1], args.insize[2], args.size, 0, false, true )
end,
--types.rv(types.Par(types.tuple{P.DataType("T"),types.bool()})),
types.rv( T.Seq( T.Par( T.tuple{P.DataType("T"),T.bool()}),P.SizeValue("insize") )),
--types.rvV(types.Par(P.DataType("T")))
types.rvV( T.VarSeq( T.Par(P.DataType("T")), P.SizeValue("sizeOut") )) )

generators.Arbitrate = R.FunctionGenerator("core.Arbitrate",{"rate"},{},
function(args)
  return RM.arbitrate(args.sched,args.rate)
end,
T.array2d(T.RV(P.ScheduleType("sched")),P.SizeValue("size")),
T.RV(P.ScheduleType("sched")))

generators.Const = R.FunctionGenerator("core.Const",{"type1","number"},{},
function(args)
  return C.triggerToConstant(args.type1,args.number)
end,
T.Interface(),
T.rv(T.Par(P.DataType("T"))))

function generators.export(t)
  if t==nil then t=_G end
  for k,v in pairs(generators) do rawset(t,k,v) end
end

return generators
