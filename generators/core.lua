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

local function canonicalV( rate, size, X )
  J.err(R.isSize(size),"canonicalV: expected size, but is: ",size)
  local sizeW, sizeH = Uniform(size[1]):toNumber(), Uniform(size[2]):toNumber()
  local seq = rate[1][2]:toNumber()/rate[1][1]:toNumber()
  local V = (sizeW*sizeH)/seq
  
  if V<=1 then
    return 0
  else
    V = math.ceil(V)
    while (sizeW*sizeH)%V~=0 do
      V = V + 1
    end
    
    return V
  end
end

-- takes A to A[N]
generators.Broadcast = R.FunctionGenerator("core.Broadcast",{"size"},{},
function(a)                                           

  return R.FunctionGenerator("core.Broadcast",{"rate"},{},
  function(args)
    local V = canonicalV( args.rate, R.Size(a.size) )

    if args.opt==2 then
      return C.broadcast(args.T,a.size[1],a.size[2])
    elseif args.opt==1 then
      local sizeW, sizeH = Uniform(a.size[1]):toNumber(), Uniform(a.size[2]):toNumber()
      
      J.err(V>=1,"BROADCAST RT ",args.rate,a.size)
      --if V==0 then V=1 end
      local seq = (sizeW*sizeH)/V

      local res = C.compose(J.verilogSanitize("Generators_Broadcast_Parseq_"..tostring(a.size)),RM.upsampleXSeq(args.T,V,seq),RM.makeHandshake(C.broadcast(args.T,V,1)))
        
      -- hackity hack
      res.outputType = T.RV(T.ParSeq(T.Array2d(args.T,V),a.size))
        
      return res
      
    elseif args.opt==0 then
      assert(V==0)

      -- hack: convert upsampleXSeq to write out a W,H size
      local res = generators.Module{
        "UpsampleXSeq_HACK_"..tostring(args.T).."_X"..tostring(a.size[1]).."_Y"..tostring(a.size[2]), SDF{1,1},
        T.RV(T.Par(args.T)),function(inp) return RM.upsampleXSeq(args.T,0,a.size[1]*a.size[2],true)(inp) end}

      local ot = T.RV(T.Seq(T.Par(args.T),a.size))
      assert(ot:lower()==res.outputType:lower())
      res.outputType = ot
      return res
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
              T.RV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("outSize"))),
              T.RV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("outSize"))),
              T.rv(T.Par(T.array2d(P.DataType("T"),P.SizeValue("outSize"))))}),
  {{SDF{0,1},SDF{1,a.size[1]*a.size[2]},true},
    {SDF{1,a.size[1]*a.size[2]},SDF{1,1}},
    {SDF{1,1},SDF{math.huge,1}}})
end)


generators.BroadcastSeq = R.FunctionGenerator("core.BroadcastSeq",{"size","number"},{},
function(args)
  assert(args.size[2]==1)
  if args.number==0 then
    return R.FunctionGenerator("core.BroadcastSeq",{"type","rate"},{},
      function(a)
        return RM.upsampleXSeq(a.T,0,args.size[1],true)
      end,
      T.RV(T.Par(P.DataType("T"))),
      T.RV(T.Seq(T.Par(P.DataType("T")),args.size)) )
  else
    assert(false)
  end
end)

-- Hack! clamp a variable sized array to a particular size
generators.ClampToSize = R.FunctionGenerator("core.ClampToSize",{"size"},{},
function(args)
  local res = generators.Function{"ClampToSize_W"..tostring(args.size[1]).."_H"..tostring(args.size[2]),T.RV(T.VarSeq(T.Par(args.T),args.InSize[1],args.InSize[2])),SDF{1,1},function(inp) return inp end}

  assert(R.isPlainFunction(res))
  local newType = T.RV(T.Seq(T.Par(args.T),args.size[1],args.size[2]))
  assert(res.outputType:lower()==newType:lower())
  res.outputType = newType
  
  return res
end,
T.RV(T.VarSeq(T.Par(P.DataType("T")),P.SizeValue("InSize"))),
T.RV(T.Seq(T.Par(P.DataType("T")),P.SizeValue("OutSize"))))


-- bits to unsigned
generators.BtoU = R.FunctionGenerator("core.BtoU",{},{},
function(args)
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
  local vals = J.map(J.range(0,math.pow(2,args.T:verilogBits())-1),args.luaFunction)
  return RM.lut(args.T,args.type1,vals)
end,
T.rv(T.Par(P.UintType("T"))),
T.rv(T.Par(P.DataType("TypeOut"))))


generators.Print = R.FunctionGenerator("core.Print",{"type","rate"},{"string"},
function(args)
  return C.print( args.T, args.string )
end,
T.rv(T.Par(P.DataType("T"))),
T.rv(T.Par(P.DataType("T"))))
--[=[
generators.PrintArray = R.FunctionGenerator("core.PrintArray",{"type","rate"},{"string"},
function(args)
  return C.print( T.Array2d(args.T,args.size), args.string )
end,
T.rv(T.Par(T.Array2d(P.DataType("T"),P.SizeValue("size")))),
T.rv(T.Par(T.Array2d(P.DataType("T"),P.SizeValue("size")))))
]=]

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

generators.ValueToTrigger = R.FunctionGenerator("core.ValueToTrigger",{"type","rate"},{},
function(args) return C.valueToTrigger(args.D) end,
T.rv(T.Par(P.DataType("D"))),
T.rv(T.Par(T.Trigger)))

generators.TriggerCounter = R.FunctionGenerator("core.TriggerCounter",{"number"},{},
function(args)
  return RM.triggerCounter(args.number)
end,
types.RV(types.Par(types.Trigger)),
types.RV(types.Par(types.Trigger)))

generators.TriggeredCounter = R.FunctionGenerator("core.TriggeredCounter",{"number"},{},
function(args)
  return RM.triggeredCounter( args.T, args.number, nil, true )
end,
types.RV(types.Par(P.DataType("T"))),
types.RV(types.Seq(types.Par(P.DataType("T")),P.SizeValue("size") )) )

generators.TriggerBroadcast = R.FunctionGenerator("core.TriggerBroadcast",{"number"},{},
function(args)
  return C.triggerUp(args.number)
end,
types.RV(types.Par(types.Trigger)),
types.RV(types.Par(types.Trigger)))

generators.FanOut = R.FunctionGenerator("core.FanOut",{},{"number","size"},
function(args)
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
  if args.opt==0 then
    return RM.packTuple(args.list,args.bool)
  elseif args.opt==1 or args.opt==2 then
    return RM.packTuple(args.list,args.bool,args.size)
  else
    J.err(false, "FanIn: expected handshake tuple input, but is: "..tostring(args.type))
  end
end,
P.SumType("opt",{types.tuple(P.TypeList("list",types.RV(P.ScheduleType("S")))),
                 types.array2d(T.RV(P.ScheduleType("S")),P.SizeValue("size")),
                 types.tuple(P.TypeList("list",types.RV()))}),
P.SumType("opt",{types.RV(P.ScheduleType("S")),
                 types.RV(P.ScheduleType("S")),
                 types.RV()})
)

generators.FIFO = R.FunctionGenerator("core.FIFO",{"number"},{"bool"},
function(args)
  if args.opt==0  then
    return C.fifo( args.S, args.number, args.bool )
  else
    return C.fifo( nil, args.number, args.bool )
  end
end,
P.SumType("opt",{types.RV(P.ScheduleType("S")),types.RV()}),
P.SumType("opt",{types.RV(P.ScheduleType("S")),types.RV()}))
  
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

generators.Zip = R.FunctionGenerator("core.Zip",{"type"},{},
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
          {T.rv(T.Par(T.tuple(P.TypeList("list",T.array2d(P.DataType("D$"),P.SizeValue("size")))))),
           T.rv(T.tuple(P.TypeList("list",T.Seq(P.ScheduleType("S"),P.SizeValue("size") )))),
           T.rv(T.tuple(P.TypeList("list",T.VarSeq(P.ScheduleType("S"),P.SizeValue("size") )))),
           T.rv(T.tuple(P.TypeList("list",T.ParSeq(T.Array2d(P.DataType("D$"),P.SizeValue("V")),P.SizeValue("size") ))))}),
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

generators.Stencil = R.FunctionGenerator("core.Stencil",{"bounds","rate"},{},
function(a)

  if a.opt==0 then
    assert(Uniform(a.V[1]):toNumber()==1)
    assert(Uniform(a.V[2]):toNumber()==1)
    return C.stencilLinebufferPartial( a.T, a.size[1], a.size[2], a.rate[1][2]:toNumber()/a.rate[1][1]:toNumber(), a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], true )
  else
    if a.opt==1 then
      assert(a.V[2]==1)
      return C.stencilLinebuffer( a.T, a.size[1], a.size[2], a.V[1], a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], true )
    elseif a.opt==2 then
      return C.stencilLinebuffer( a.T, a.size[1], a.size[2], 0, a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], true )
    else
      assert(false)
    end
  end
end,
P.SumType("opt",{types.RV(types.ParSeq(types.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size"))),
                 types.rv(types.ParSeq(types.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size"))),
                 types.rv(types.Seq(types.Par(P.DataType("T")),P.SizeValue("size")))}),
P.SumType("opt",{
  types.RV(types.Seq(types.ParSeq(types.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("stSize")),P.SizeValue("size"))),
  types.rv(types.ParSeq(types.array2d(types.array2d(P.DataType("T"),P.SizeValue("stSize")),P.SizeValue("V")),P.SizeValue("size"))),
  types.rv(types.Seq(types.Par(types.array2d(P.DataType("T"),P.SizeValue("stSize"))),P.SizeValue("size")))}),
{{SDF{0,1},SDF{0,1}},
  {SDF{0,1},SDF{math.huge,1}},
  {SDF{0,1},SDF{math.huge,1}}}
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
    local res = C.cropHelperSeq(a.T,a.size[1],a.size[2],a.V[1],a.bounds[1],a.bounds[2],a.bounds[3],a.bounds[4],true)
    return res
  elseif a.opt==1 then
    local res = C.cropHelperSeq(a.T,a.size[1],a.size[2],0,a.bounds[1],a.bounds[2],a.bounds[3],a.bounds[4],true)
    return res
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
  return RM.posSeq(args.size[1],args.size[2],args.number)
end,
types.rv(types.Par(T.Trigger)),
types.rv(types.Par(P.DataType("D"))))

generators.Pos = R.FunctionGenerator("core.Pos",{"size","rate"},{},
function(args)
  local V = canonicalV( args.rate, R.Size(args.size) )
  local res = generators.Function{"Pos_With_Trig",T.RV(T.Par(T.Trigger)),args.rate,
                                  function(inp)
      local PS = RM.posSeq(args.size[1],args.size[2],V,nil,true,true)
      local trig = generators.Broadcast{{args.size[1],args.size[2]}}(inp)
      return generators.Map{PS}(trig)
    end}
  
  return res
end,
types.RV(T.Par(T.Trigger)),
types.RV(P.ScheduleType("D")))

-- unlike Pos above, this expects a trigger for every pixel
generators.PosCounter = R.FunctionGenerator("core.PosCounter",{},{},
function(args)
  local V = 0
  if args.opt==0 then assert(args.V[2]==1);V=args.V[1] end
  return RM.posSeq(args.size[1],args.size[2],V,nil,true,true)
end,
P.SumType("opt",{types.rv(T.ParSeq(T.Array2d(T.Trigger,P.SizeValue("V")),P.SizeValue("size"))),
                 types.rv(T.Seq(T.Par(T.Trigger),P.SizeValue("size")))}),
P.SumType("opt",{types.rv(T.ParSeq(T.Array2d(T.Array2d(T.Uint(16),2),P.SizeValue("V")),P.SizeValue("size"))),
                 types.rv(T.Seq(T.Par(T.Array2d(T.Uint(16),2)),P.SizeValue("size")))})
)

-- this takes an Seq of arrays, and flattens it into a parseq
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
  
  J.err( fnType:isSupertypeOf(args.rigelFunction.inputType,fnVars,""), "Reduce: input fn should have type: "..tostring(fnType)..", but instead has type: "..tostring(args.rigelFunction.inputType) )

  return R.FunctionGenerator("core.Reduce",{"rate"},{},
    function(a)

      local joinset = J.joinSet(fnVars,a,true)

      local spType = R.specialize(args.rigelFunction.inputType, joinset )

      local fn = args.rigelFunction{spType,SDF{1,1}}
      assert(R.isPlainFunction(fn))
        
      if a.opt==0 then

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

local SerToWidthArrayToScalar = J.memoize(function(ty,size)
    local res = generators.Module{
      "SerToWidth_Convert_Array_to_scalar_"..tostring(ty), SDF{1,1},
      T.rV(T.Par(T.array2d(ty,1,1))),
      function(inp)
        return generators.Index{0}(inp)
    end}
    assert(R.isPlainFunction(res))

    res.inputType = types.rV(types.ParSeq(T.array2d(ty,1,1),size))
    res.outputType = types.rRV(types.Seq(T.Par(ty),size))

    return res
end)

-- for legacy reasons, changerate returns stuff in column major order.
-- instead, do row major
-- takes ty[Vw,Vh;W,H} to ty[V2w,V2h;W,H} where V2w*V2h==outputItemsPerCyc
local ChangeRateRowMajor = J.memoize(function(ty, Vw, Vh, outputItemsPerCyc, W,H )
  J.err( math.floor(outputItemsPerCyc)==outputItemsPerCyc, "ChangeRateRowMajor outputItemsPerCyc is not integer, is: ",outputItemsPerCyc )
  local cr = RM.changeRate( ty, 1, Vw*Vh, outputItemsPerCyc )

  J.err( (Uniform(W):toNumber()*Uniform(H):toNumber())%outputItemsPerCyc==0, "ChangeRateRowMajor: outputItemsPerCyc does not divide array size? W=",W," H=",H," outputItemsPerCyc=",outputItemsPerCyc)
  assert( outputItemsPerCyc<Uniform(W):toNumber() or outputItemsPerCyc%Uniform(W):toNumber()==0 )

  local V2w, V2h = outputItemsPerCyc, 1
  if outputItemsPerCyc>Uniform(W):toNumber() then
    V2w, V2h = Uniform(W):toNumber(), outputItemsPerCyc/Uniform(W):toNumber()
  end

  local inputType, outputType
  if Vw==W and Vh==H then
    inputType = types.RV(types.Par(T.array2d(ty,Vw,Vh)))
  else
    inputType = types.RV(types.ParSeq(T.array2d(ty,Vw,Vh),W,H))
  end
  
  outputType = types.RV(types.ParSeq(T.array2d(ty,V2w,V2h),W,H))

  local res = generators.Module{
    "ChangeRateRowMajor_"..tostring(ty).."_Vw"..tostring(Vw).."_Vh"..tostring(Vh), types.RV(types.Par(T.array2d(ty,Vw,Vh))),
      function(inp)
        return generators.ReshapeArray{{V2w,V2h}}(generators.Map{cr}(generators.ReshapeArray{{Vw*Vh,1}}(inp)))
  end}
  assert(R.isPlainFunction(res))
  assert( res.outputType:lower()==outputType:lower() )
  assert( res.inputType:lower()==inputType:lower() )
  res.inputType=inputType
  res.outputType=outputType
  
  return res
end)

-- serialize to a particular vector width ("number")
-- width is the number of items to produce per cycle (not literally the width)
generators.SerToWidth = R.FunctionGenerator("core.SerToWidth",{"number"},{},
function(args)
  J.err( math.floor(args.number)==args.number, "SerToWidth: width is not an integer, is: ",args.number) 
  if args.number==0 then
    return R.FunctionGenerator("core.SerToWidth",{},{},
      function(a)
        if a.opt==0 then
          return RM.changeRate( a.T, a.size[2], a.size[1], args.number, true, a.size[1], a.size[2] )
        elseif a.opt==1 then

          if a.V[1]*a.V[2]==1 and args.number==0 then
            -- special case of taking [1,1;w,h} to {w,h} (not really a changerate)

            return SerToWidthArrayToScalar( a.T, a.size )
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
          return ChangeRateRowMajor( a.T, a.size[1], a.size[2], args.number, a.size[1], a.size[2] )
        elseif a.opt==1 then
          return ChangeRateRowMajor( a.T, a.V[1], a.V[2], args.number, a.size[1], a.size[2] )
        else
          assert(false)
        end
      end,
      P.SumType("opt",{
            T.RV(T.Par(T.array2d(P.DataType("T"),P.SizeValue("size")))),
            T.RV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size")))}),
      P.SumType("opt",{
            T.RV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("VOut")),P.SizeValue("sizeOut"))),
            T.RV(T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("VOut")),P.SizeValue("sizeOut")))}) )
  end
end)

generators.SerSeq = R.FunctionGenerator("core.SerSeq",{"type","number","rate"},{},
function(args)
  J.err(args.size[1]%args.number==0,"G.SerSeq: number of cycles must divide array size")
  return RM.changeRate( args.T, args.size[2], args.size[1], args.size[1]/args.number )
end,
types.rV(types.Par(types.array2d(P.DataType("T"),P.SizeValue("size")))),
types.rRV(types.Par(types.array2d(P.DataType("T"),P.SizeValue("size")))) )


generators.DeserSeq = R.FunctionGenerator("core.DeserSeq",{"number"},{},
function(args)
  return RM.changeRate( args.T, args.size[2], args.size[1], args.size[1]*args.number )
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

--[=[
generators.FwriteArray = R.FunctionGenerator("core.Fwrite",{"string"},{"filenameVerilog"},
function(args)
  --return RS.modules.fwriteSeq({type=args.type,filename=args.string})
  return RM.fwriteSeq(args.string,T.Array2d(args.T,args.size),args.filenameVerilog,true)
end,
T.rv(T.Par(T.Array2d(P.DataType("T"),P.SizeValue("size")))),
T.rv(T.Par(T.Array2d(P.DataType("T"),P.SizeValue("size")))))
]=]

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

-- string is name
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

        if ty:is("Par") or ty:is("ParSeq") then
          if ty.over:isArray() then
            -- if not an array, can't really do anything

            local chan = canonicalV( args.rate, ty.over.size )
            local res = generators.SerToWidth{chan}

            return res
          else
            -- cant' do anything
            return generators.Identity
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

  -- even if ratio==1, we still want it to break T[1;W,H} into T{W,H} canonical form
  if ratio==1 and args.type:extractSchedule():is("ParSeq") and
    args.type:extractSchedule().over:isArray() and
    Uniform(args.type:extractSchedule().over.size[1]):toNumber()==1 and
    Uniform(args.type:extractSchedule().over.size[2]):toNumber()==1 
  then
    return generators.SerToWidth{0}
  end
  
  -- if ratio >=1, don't do anything:
  return generators.Identity
end)

-- change dims of array
generators.ReshapeArray = R.FunctionGenerator("core.ReshapeArray",{"size"},{},
function(args)
  J.err( args.size[1]*args.size[2]==args.insize[1]*args.insize[2], "ReshapeArray: total number of items must not change. Input size: "..tostring(args.insize).." requested reshape: "..tostring(args.size[1])..","..tostring(args.size[2]) )
  return C.cast(T.Array2d(args.T,args.insize),T.Array2d(args.T,args.size))
end,
types.rv(types.Par(types.array2d(P.DataType("T"),P.SizeValue("insize")))),
types.rv(types.Par(types.array2d(P.DataType("T"),P.SizeValue("outsize")))) )

generators.Sort = R.FunctionGenerator("core.Sort",{"rigelFunction"},{},
function(args)
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
  if args.opt==1 then
    assert(args.V[2]==1)
    return C.FilterSeqPar( args.T, args.V[1], SDF(args.size), true, args.insize[1], args.insize[2] )
  else
    return RM.filterSeq( args.T, args.insize[1], args.insize[2], args.size, 0, false, true )
  end
end,
P.SumType("opt",{types.rv( T.Seq( T.Par( T.tuple{P.DataType("T"),T.bool()}),P.SizeValue("insize") )),
                 types.RV( T.ParSeq( T.Array2d( T.tuple{P.DataType("T"),T.bool()},P.SizeValue("V")),P.SizeValue("insize") ))}),
P.SumType("opt",{types.rvV( T.VarSeq( T.Par(P.DataType("T")), P.SizeValue("sizeOut") )),
                 types.RV( T.VarSeq( T.Par(P.DataType("T")), P.SizeValue("sizeOut") ))}) )

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
T.rv(T.Par(T.Trigger)),
T.rv(T.Par(P.DataType("T"))))

function generators.export(t)
  if t==nil then t=_G end
  for k,v in pairs(generators) do rawset(t,k,v) end
end

return generators
