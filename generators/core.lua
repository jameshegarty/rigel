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
generators.Broadcast = R.FunctionGenerator("core.Broadcast",{"size"},{},
function(args)
  if args.opt==2 then
--    local W,H
--    if args.size~=nil then
--      W,H = args.size[1], args.size[2]
--    elseif args.number~=nil then
--      W = args.number
--      H = 1
--    else
--      assert(false)
--    end
    
    return C.broadcast(args.T,args.size[1],args.size[2])
  elseif args.opt==0 then
--    local chans
--    if args.number~=nil then
--      chans = args.number
--    else
--      assert(args.size~=nil)
--      chans = args.size[1]*args.size[2]
--    end
    J.err(args.size[2]==1,"Broadcast NYI: height>1")
    return RM.upsampleXSeq(args.T,0,args.size[1],true)
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

-- a broadcast is basically the same as a upsample, but has no W,H
-- number: vector width
--[=[generators.BroadcastSeq = R.FunctionGenerator("core.BroadcastSeq",{"number","size"},{},
function(args)
  --J.err( types.isBasic(args.type),"generators.BroadcastSeq: unsupported type: "..tostring(args.type))
  return RM.upsampleXSeq(args.type,args.number,args.size[1]*args.size[2])
end,
types.RV(types.Par()
]=]
-- bits to unsigned
generators.BtoU = R.FunctionGenerator("core.BtoU",{"type"},{},
function(args)
  J.err( args.type:isBits(), "BtoU input type should be Bits, but is: "..tostring(args.type))
  return C.cast(args.type,types.uint(args.type.precision))
end)

generators.Print = R.FunctionGenerator("core.Print",{"type","rate"},{"string"},function(args) return C.print(args.type,args.string) end)
generators.FlattenBits = R.FunctionGenerator("core.FlattenBits",{"type"},{},function(args) return C.flattenBits(args.type) end)
generators.PartitionBits = R.FunctionGenerator("core.PartitionBits",{"type","number"},{},function(args) return C.partitionBits(args.type,args.number) end)
generators.Rshift = R.FunctionGenerator("core.Rshift",{},{"number"}, function(args)
  if args.number~=nil then
    return R.FunctionGenerator("core.Rshift",{},{},function(a) return C.rshift(a.T,args.number) end,T.rv(T.Par(P.NumberType("T"))),T.rv(T.Par(P.NumberType("T"))) )
  else
    assert(false)
  end
end)
generators.AddMSBs = R.FunctionGenerator("core.AddMSBs",{},{"number"}, function(args) return C.addMSBs(args.T,args.number) end,T.rv(T.Par(P.NumberType("T"))),T.rv(T.Par(P.NumberType("T"))))
generators.RemoveMSBs = R.FunctionGenerator("core.RemoveMSBs",{"number"},{}, function(args) return C.removeMSBs(args.T,args.number) end, T.rv(T.Par(P.NumberType("T"))), T.rv(T.Par(P.NumberType("T"))) )
generators.RemoveLSBs = R.FunctionGenerator("core.RemoveLSBs",{"type","rate"},{"number"}, function(args) return C.removeLSBs(args.type,args.number) end)

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
  print("FANIN",args.opt,args.list)
  
  if args.opt==0 then
    return RM.packTuple(args.list,args.bool)
    --elseif R.isHandshakeTriggerArray(args.type) then
  elseif args.opt==1 then
    return RM.packTuple(args.list,args.bool,args.size)
  else
    J.err(false, "FanIn: expected handshake tuple input, but is: "..tostring(args.type))
  end
end,
P.SumType("opt",{types.tuple(P.TypeList("list",types.RV(P.ScheduleType("S")))),
                 types.array2d(T.RV(P.ScheduleType("S")),P.SizeValue("size"))}),
P.SumType("opt",{types.RV(types.tuple(P.TypeList("list",P.ScheduleType("S")))),
                 types.RV(P.ScheduleType("S"),P.SizeValue("size"))})
)

generators.FIFO = R.FunctionGenerator("core.FIFO",{"number"},{"bool"},
function(args)
  --J.err( R.isHandshake(args.type) or R.isHandshakeTrigger(args.type),"FIFO: expected handshake input, but is: "..tostring(args.type))
  --local ty = R.extractData(args.type)
  return C.fifo( args.T, args.number, args.bool )
end,
types.RV(types.Par(P.DataType("T"))),
types.RV(types.Par(P.DataType("T"))))
  
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

generators.Sub = R.FunctionGenerator("core.Sub",{},{"async"},
function(args)
  --J.err( args.type:isTuple(), "generators.Sub: type should be tuple, but is: "..tostring(args.type) )
  --J.err( args.type.list[1]==args.type.list[2], "generators.Sub: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )
  return C.sub( args.T, args.T, args.T, args.async )
end, T.rv(T.Par(T.tuple{P.NumberType("T"),P.NumberType("T")})),T.rv(T.Par(P.NumberType("T"))))

generators.Mul = R.FunctionGenerator("core.Mul",{},{"number","async"},
function(args)
  if args.number~=nil then
    --J.err( args.type:isUint() or args.type:isInt(), "generators.Mul: type should be int or uint, but is: "..tostring(args.type) )
    --return C.multiplyConst(args.type, args.number )
    return R.FunctionGenerator("core.Mul",{},{"async"},
      function(a) return C.multiplyConst( a.T, args.number, a.async ) end,
      T.rv(T.Par(P.NumberType("T"))), T.rv(T.Par(P.NumberType("T"))))
  else
    --J.err( args.type:isTuple(), "generators.Mul: type should be tuple, but is:"..tostring(args.type) )
    --J.err( args.type.list[1]==args.type.list[2], "generators.Mul: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )

    return R.FunctionGenerator("core.Mul",{},{"bool"},function(args) return C.multiply( args.T, args.T, args.T, args.async ) end, T.rv(T.Par(T.tuple{P.NumberType("T"),P.NumberType("T")})), T.rv(T.Par(P.NumberType("T"))))
  end
end)

generators.GT = R.FunctionGenerator("core.GT",{},{"number"},
function(args)
  if args.number~=nil then
--    J.err( args.type:isUint() or args.type:isInt(), "generators.GT: type should be int or uint, but is: "..tostring(args.type) )
    --    return C.GTConst(args.type, args.number )
    return R.FunctionGenerator("core.GT",{},{"async"},
      function(a) return C.GTConst( a.T, args.number, a.async ) end,
      T.rv(T.Par(P.NumberType("T"))), T.rv(T.Par(types.bool())))

  else
--    J.err( args.type:isTuple(), "generators.GT: type should be tuple, but is:"..tostring(args.type) )
--    J.err( args.type.list[1]==args.type.list[2], "generators.GT: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )

--    return C.GT( args.type.list[1], args.type.list[1] )

    return R.FunctionGenerator("core.GT",{},{"async"},function(args) return C.GT( args.T, args.T, args.T, args.async ) end, T.rv(T.Par(T.tuple{P.NumberType("T"),P.NumberType("T")})), T.rv(T.Par(types.bool())))
  end
end)

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
end)

generators.And = R.FunctionGenerator("core.And",{"type","rate"},{"bool"},
function(args)
  J.err( args.type:isTuple(), "generators.And: type should be tuple, but is: "..tostring(args.type) )
  J.err( args.type.list[1]==types.bool() and args.type.list[2]==types.bool(), "generators.And: both inputs should be bool" )
  return C.And
end)

generators.Not = R.FunctionGenerator("core.Not",{"type","rate"},{"bool"},
function(args)
  J.err( args.type==types.bool(), "generators.Not: input type should be bool, but is: "..tostring(args.type) )
  return C.Not
end)

generators.Zip = R.FunctionGenerator("core.Zip",{},{},
function(args)
  J.err( args.D:isTuple(), "generators.Zip: type should be tuple, but is: "..tostring(args.type) )

  local typelist = {}
  for k,v in ipairs(args.D.list) do
    typelist[k] = v:arrayOver()
  end
  
  return RM.SoAtoAoS( args.D.list[1].size[1], args.D.list[1].size[2], typelist )
end,
types.rv(T.Par(P.DataType("D"))),
types.rv(T.Par(P.DataType("D"))))

-- bool is "HandshakeTrigger" option
--[=[generators.HS = R.FunctionGenerator("core.HS",{"rigelFunction","type","rate"},{"bool"},
function(args)

  local mod
  if R.isFunctionGenerator(args.rigelFunction) and args.type:is("HandshakeFramed") then
    -- fill in args from HSF
    --mod = args.rigelFunction{args.type.params.A,types.HSFV(args.type),types.HSFSize(args.type)}
    mod = args.rigelFunction{ types.StaticFramed( args.type.params.A, args.type.params.mixed, args.type.params.dims ), args.rate }
  elseif R.isFunctionGenerator(args.rigelFunction) then
    local r
    if args.rigelFunction:requiresArg("rate") then r = args.rate end
    mod = args.rigelFunction{R.extractData(args.type), r}
  else
    mod = args.rigelFunction
  end
  
  J.err( R.isFunctionGenerator(mod)==false, "generators.HS: input rigel function is a generator, not a module (arguments must be missing)" )
  J.err( R.isPlainFunction(mod), "generators.HS: input Rigel function didn't yield a plain Rigel function? (is "..tostring(mod)..")" )
    
  return RS.HS(mod,args.bool)
  end)]=]

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

--[=[
generators.Stencil = R.FunctionGenerator("core.Stencil",{"type","bounds","rate"},{},
function(args)

  if args.type:is("StaticFramed") then
    local pixelType = types.HSFPixelType(args.type)
    local size = types.HSFSize(args.type)
    local V = types.HSFV(args.type)

    for _,v in ipairs(args.bounds) do J.err(v>=0,"Stencil bounds must be >=0") end
    
    local a = C.stencilLinebuffer( pixelType, size[1], size[2], V, -args.bounds[1], args.bounds[2], -args.bounds[3], args.bounds[4], true )
    local b = C.unpackStencil( pixelType, args.bounds[1]+1,args.bounds[3]+1, V, nil, true, size[1], size[2] )
    local mod = C.compose("generators_Linebuffer_"..a.name.."_"..b.name,b,a)
    
    if args.number==0 then
      mod = C.linearPipeline({C.arrayop(itype,1,1),mod,C.index(mod.outputType,0)},"generators_Linebuffer_0wrap_"..mod.name)
    end
    
    return mod
  elseif types.isBasic(args.type) then
    -- fully parallel
    assert(false)
  else
    err(false,"generators.Stencil: unsupported input type: "..tostring(args.type))
  end
  end)]=]

generators.Stencil = R.FunctionGenerator("core.Stencil",{"bounds"},{},
function(args)
  return R.FunctionGenerator("core.Stencil",{},{},
    function(a)
      assert(a.V[2]==1)
      return C.stencilLinebuffer( a.T, a.size[1], a.size[2], a.V[1], args.bounds[1], args.bounds[2], args.bounds[3], args.bounds[4], true )
    end,
    types.rv(types.ParSeq(types.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size"))),
    types.rv(types.ParSeq(types.array2d(types.array2d(P.DataType("T"),args.bounds[2]-args.bounds[1]+1,args.bounds[4]-args.bounds[3]+1),P.SizeValue("V")),P.SizeValue("size"))))
end)

generators.Pad = R.FunctionGenerator("core.Pad",{"bounds"},{},
function(a)
  J.err(a.V[2]==1,"Pad NYI - Vh >1")
  --local A = args.type:arrayOver()
  return RM.padSeq(a.T,a.size[1],a.size[2],a.V[1],a.bounds[1],a.bounds[2],a.bounds[3],a.bounds[4],0,true)
end,
types.rV( T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size")) ),
types.rRV( T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("sizeOut")) ))


generators.CropSeq = R.FunctionGenerator("core.CropSeq",{"type","size","number","bounds","rate"},{},
function(args)
  local A = args.type.over.over
  if args.number>0 then A  = args.type.over.over:arrayOver() end
  
  return RM.cropSeq(A,args.size[1],args.size[2],args.number,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4])
end)

generators.Crop = R.FunctionGenerator("core.Crop",{"bounds"},{},
function(a)
  --print("CROP")
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
                                       
generators.PosSeq = R.FunctionGenerator("core.PosSeq",{"size","number"},{},
function(args)
  --if args.type~=nil then
  --  J.err( args.type==types.null(), "PosSeq: expected null input")
  --end
  return RM.posSeq(args.size[1],args.size[2],args.number)
end,
types.Interface(),
types.rv(types.Par(P.DataType("D"))))

generators.Pos = R.FunctionGenerator("core.PosSeq",{"size","number"},{},
function(args)
--  if args.type~=nil then
--    J.err( args.type==types.null(), "PosSeq: expected null input")
--  end
  return RM.posSeq( args.size[1], args.size[2], args.number, nil, true, true )
end,
types.Interface(),
types.rv(types.Par(P.DataType("D"))))


-- take a regular Handshake module and lift to HandshakeFramed type
generators.MapFramed = R.FunctionGenerator("core.MapFramed",{"type","rigelFunction","rate"},{},
function(args)
  assert(args.type:is("HandshakeFramed"))

  local fn = args.rigelFunction
  if R.isFunctionGenerator(fn) then
    fn = fn{types.Handshake(args.type.params.A),args.rate}
  else
    assert(false)
  end

  J.err( R.isPlainFunction(fn), "generators.MapFramed: input didn't yield a plain rigel function? "..tostring(fn))

  return RM.mapFramed( fn, args.type.params.dims[1][1], args.type.params.dims[1][2], true )
end)

-- size/bool: output size/mixed for framed types (needed if vector width/ SDF rate changes...)
--       think of this like a combined map&flatten
--[=[generators.Map = R.FunctionGenerator("core.Map",{"type","rigelFunction","rate"},{"size","bool"},
function(args)
  if args.type:is("StaticFramed") then

    if args.type.params.mixed and #args.type.params.dims==1 then
      local mod = args.rigelFunction
      if R.isFunctionGenerator(mod) then
        mod = mod{args.type.params.A:arrayOver(),args.rate}
      end
      J.err( R.isPlainFunction(mod), "generators.Map: input didn't yield a plain rigel function? "..tostring(mod))
      
      assert( args.type.params.A.size[2]==1 )
      local res = RM.map( mod, args.type.params.A.size[1], args.type.params.A.size[2] )
      return RM.mapFramed( res, args.type.params.dims[1][1], args.type.params.dims[1][2], true )
    else
      local size = types.HSFSize(args.type)
      local mod = args.rigelFunction
      if R.isFunctionGenerator(mod) then
        mod = mod{args.type:framedOver(),args.rate}
      end
      J.err( R.isPlainFunction(mod) or R.isInstanceCallsite(mod), "generators.Map: input didn't yield a plain Rigel function? "..tostring(mod))

      -- fully serial
      return RM.mapFramed( mod, size[1], size[2], false )
    end
  elseif args.type:is("HandshakeFramed") then
    if (args.type.params.mixed==false and #args.type.params.dims==1) or (args.type.params.mixed and args.type:FV()==1) then
      -- this is basically just applying a HSF wrapper
      local size = types.HSFSize(args.type)
      local mod = args.rigelFunction
      if R.isFunctionGenerator(mod) then
        mod = mod{args.type:framedOver(),args.rate}
      end
      J.err( R.isPlainFunction(mod) or R.isInstanceCallsite(mod), "generators.Map: function didn't yield a plain Rigel function? "..tostring(mod))

      local omixed = args.bool
      local ow,oh
      -- optionally allow user to override output size
      if args.size~=nil then ow,oh=args.size[1],args.size[2] end
      
      if args.type.params.mixed and args.type:FV()==1 then
         -- hack: lift mod to work on an array of size 1
         mod = generators.Module{R.Handshake(args.type.params.A),args.rate,
                                function(i)
                                  local o = generators.HS{generators.Index{0}}(i)
                                  --o = mod(o)
                                  --return generators.Map{mod}(o)
                                  return mod(o)
                                end}

        assert(omixed==nil)
        omixed=nil
        assert(ow==nil)
        assert(oh==nil)
        ow=128
        oh=64
      end

      J.err( R.isPlainFunction(mod) or R.isInstanceCallsite(mod), "generators.Map: input didn't yield a plain rigel function? (2)")
      
      -- fully serial
      return RM.mapFramed( mod, size[1], size[2], args.type.params.mixed, ow, oh, omixed )
    else
      J.err(false, "generators.Map: attempted to apply to HandshakeFramed value with unsupported type: "..tostring(args.type))
    end
  elseif args.type:isArray() then
    local mod = args.rigelFunction
    if R.isFunctionGenerator(mod) then
      local r
      if mod:requiresArg("rate") then r = args.rate end

      mod = mod{args.type:arrayOver(),r}
    end
    J.err( R.isPlainFunction(mod), "generators.Map: input didn't yield a plain rigel function? "..tostring(mod))
    
    return RM.map( mod, args.type.size[1], args.type.size[2] )
  else
    J.err(false, "generators.Map: attempted to apply to value with unsupported type: "..tostring(args.type))
  end
  end)]=]

generators.Map = R.FunctionGenerator("core.Map",{"rigelFunction"},{},
function(args)
  J.err(R.isPlainFunction(args.rigelFunction),"core.Map should only work on plain functions")
--  return generators.Generator{"core_Map_"..args.rigelFunction.name,
--                              args.rigelFunction.inputType,args.rigelFunction.outputType,
  --                              args.rigelFunction}
  return R.FunctionGenerator("core.Map",{},{},function(a) return args.rigelFunction end,
                             args.rigelFunction.inputType,
                             args.rigelFunction.outputType)
--    function(inp)
--      print("MAKE CORE MAP",args.rigelFunction.name,inp.type)
--      return args.rigelFunction(inp) end}
end)
                                        
generators.Reduce = R.FunctionGenerator("core.Reduce",{"rigelFunction"},{},
function(args)
  --assert(args.rigelFunction.inputType:isStatic())
  --assert(args.rigelFunction.inputType.over:is("Par"))

  --
  --
  --local fn = args.rigelFunction:checkTypeAndSpecialize( fnType, fnVars)

  local fnVars = {}
  local fnType = T.rv(T.Par(types.tuple{P.DataType("T"),P.DataType("T")}))
  
  print("FNTY:E",fnType,args.rigelFunction.inputType,rigelFunction)
  J.err( fnType:isSupertypeOf(args.rigelFunction.inputType,fnVars), "Reduce: input fn should have type: "..tostring(fnType)..", but instead has type: "..tostring(args.rigelFunction.inputType) )

  print("FNVARS")
  for k,v in pairs(fnVars) do print("FNVARS",k,v) end
  return R.FunctionGenerator("core.Reduce",{},{},
    function(a)

      print("TryToSpecial",args.rigelFunction.inputType)
      local joinset = J.joinSet(fnVars,a,true)
      for k,v in pairs(joinset) do print("A",k,v) end
      local spType = R.specialize(args.rigelFunction.inputType, joinset )
      print("SPTYPE",spType)
      local fn = args.rigelFunction{spType,SDF{1,1}}
      assert(R.isPlainFunction(fn))
        
      if a.opt==0 then
        return RM.reduceSeq( fn, 1/(a.size[1]*a.size[2]),true)
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
generators.Ser = R.FunctionGenerator("core.Ser",{"type","number","rate"},{},
function(args)
  J.err( args.type:isArray(), "generators.Ser: type should be array, but is: "..tostring(args.type) )
  return C.changeRateFramed( args.type:arrayOver(), args.type:arrayLength()[2], args.type:arrayLength()[1], args.number, true )
end)

-- serialize to a particular vector width ("number")
generators.SerToWidth = R.FunctionGenerator("core.SerToWidth",{"number"},{},
function(args)
  if args.number==0 then
--    print("SERTOWIDTH0")
    return R.FunctionGenerator("core.SerToWidth",{},{},
      function(a)
        if a.opt==0 then
          return RM.changeRate( a.T, a.size[2], a.size[1], args.number, true, a.size[1], a.size[2] )
        elseif a.opt==1 then
          print("OPT1 H",a.V[2],"inputRate",a.V[1],"outputRate",args.number,"parseqx",a.size[1])
          if a.V[1]*a.V[2]==1 and args.number==0 then
            -- special case of taking [1,1;w,h} to {w,h} (not really a changerate)

--            print("Special case [1,1;w,h}")
            local res = generators.Module{
              "SerToWidth_Convert_Array_to_scalar_"..tostring(a.T), SDF{1,1},
--              T.rV(T.ParSeq(T.array2d(a.T,1,1),a.size[1],a.size[2])),
              T.rV(T.Par(T.array2d(a.T,1,1))),
              function(inp)
                --print("CALL INDEX",inp.type)
                return generators.Index{0}(inp)
            end}
            assert(R.isPlainFunction(res))
            --print("SSSER",res,res.systolicModule)
            res.inputType = types.rV(types.ParSeq(T.array2d(a.T,1,1),a.size))
            res.outputType = types.rRV(types.Seq(T.Par(a.T),a.size))
            --print(res)
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
  J.err( args.type:isArray(), "generators.SerSeq: type should be array, but is: "..tostring(args.type) )

  J.err(args.type:arrayLength()[1]%args.number==0,"G.SerSeq: number of cycles must divide array size")
  return RM.changeRate( args.type:arrayOver(), args.type:arrayLength()[2], args.type:arrayLength()[1], args.type:arrayLength()[1]/args.number )
end)

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

generators.Fwrite = R.FunctionGenerator("core.Fwrite",{"type","string"},{"size"},
function(args)
  --return RS.modules.fwriteSeq({type=args.type,filename=args.string})
  return RM.fwriteSeq(args.string,args.type,args.string..".verilog.raw",true)
end)

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

generators.Generator = R.FunctionGenerator("core.Module",{"luaFunction","type","type1"},{"string","rate","instanceList"},
function(args)
  if args.string==nil then
    args.string = "unnamedModuleGen"..__unnamedID
    __unnamedID = __unnamedID+1
  end

  return R.FunctionGenerator(args.string,{"type","rate"},{},
    function(a)
      print("FNGEN",a.type,args.rate)
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
  print("AXIREADBURST",args.type)
  local numb = args.number
  if numb==nil then
    numb = math.ceil((args.size[1]*args.size[2]*Uniform(args.rate[1][1]):toNumber())/Uniform(args.rate[1][2]):toNumber())
    print("AXIReadBurst V:",numb)
  end
  return SOC.readBurst( args.string, args.size[1], args.size[2], args.type, numb, true, args.address, args.rigelFunction )
end)

generators.AXIRead = R.FunctionGenerator("core.AXIRead",{"string","number","rigelFunction"},{},
function(args)
  return SOC.read( args.string, args.number, types.uint(8), args.rigelFunction )
end,
types.RV(types.Par(types.uint(32))),
types.RV(types.Par(types.uint(8))))

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

  print("Reshape",ratio)
  if ratio<1 then

--[=[    if args.type:is("HandshakeFramed") and #args.type.params.dims==1 then
      if args.type:FV()*ratio < 1 then
        return generators.Module{function(i) return generators.Map{generators.Reshape}(i) end,args.type,args.rate}
      else
        assert(false)
      end
    elseif args.type:is("Handshake") then
      if args.type.params.A:channels()*ratio < 1 then
        print("RESHAPE",args.type,args.rate)
        assert(false)
      else
        local res = generators.HS{generators.Ser{args.rate[1][2]/args.rate[1][1]},args.type,args.rate}
        return res
  end]=]
    if args.type:isRV() then

      local function reduceRatio(ty)
        print("ReduceRatio",ty,ratio)
        if ty:is("Par") or ty:is("ParSeq") then
          if ty.over:isArray() then
            -- if not an array, can't really do anything
--            local chan = ty.over.size[1]*ty.over.size[2]*ratio
            local chan = ty.over.size[1]*ratio -- NYI, 2d
            if chan<1 then chan=0 end
            local res = generators.SerToWidth{chan}
            print("ReduceRationFN","CHAN",chan,res)
            return res
          else
            assert(false)
          end
        elseif ty:is("Seq") then
            -- already fully sequential, try to apply to inner dim?
            --assert(false)
            --return generators.Map{generator.Reshape}
          print("Recurse into REDU",chan)
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
--[=[  
  -- ratio==1
  if args.type:is("HandshakeFramed") then
    local ID = C.identity( args.type.params.A )
    ID = RM.mapFramed(ID,args.type:FW(),args.type:FH(),args.type:FV()>0)
    local res = generators.HS{ID,args.type,args.rate}
    return res
  elseif types.isBasic(args.type) then
    return C.identity(args.type)
  else
    assert(false)
  end]=]
end)

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

generators.FilterSeq = R.FunctionGenerator("core.FilterSeq",{"size"},{},
function(args)
--  J.err( args.type:isTuple(), "generators.FilterSeq: input should be tuple" )
--  J.err( args.type.list[2]:isBool(), "generators.FilterSeq: input should be tuple of type {A,bool}, but is: "..tostring(args.type) )
  return RM.filterSeq( args.T, 1, 1, args.size, 0, false )
end,
types.rv(types.Par(types.tuple{P.DataType("T"),types.bool()})),
types.rvV(types.Par(P.DataType("T"))) )

generators.Arbitrate = R.FunctionGenerator("core.Arbitrate",{"rate"},{},
function(args)
  --J.err( types.isHandshakeArray(args.type), "generators.Arbitrate: input should be HandshakeArray, but is: "..tostring(args.type) )
  --  print("ARB",args.sched
  print("ARB",args.rate)
  return RM.arbitrate(args.sched,args.rate)
end,
T.array2d(T.RV(P.ScheduleType("sched")),P.SizeValue("size")),
T.RV(P.ScheduleType("sched")))

--generators.StripFramed = R.FunctionGenerator("core.StripFramed",{"type","rate"},{},
--function(args)
--  return C.stripFramed(args.type)
--end)

function generators.export(t)
  if t==nil then t=_G end
  for k,v in pairs(generators) do rawset(t,k,v) end
end

return generators
