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
    
    local res = C.compose(J.verilogSanitize("Generators_Broadcast_Parseq_"..tostring(args.size)),RM.upsampleXSeq(inputType,V[1],seq),RM.makeHandshake(C.broadcast(inputType,V[1],1)))
    
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
  local res = generators.Function{"ClampToSize_W"..tostring(args.size[1]).."_H"..tostring(args.size[2]),T.RV(T.VarSeq(T.Par(args.T),args.InSize[1],args.InSize[2])),SDF{1,1},function(inp) return inp end}

  assert(R.isPlainFunction(res))
  local newType = T.RV(T.Seq(T.Par(args.T),args.size[1],args.size[2]))
  assert(res.outputType:lower()==newType:lower())
  res.outputType = newType
  
  return res
end,
T.VarSeq(T.Par(P.DataType("T")),P.SizeValue("InSize")) )



-- bits to unsigned
generators.BtoU = R.FunctionGenerator("core.BtoU",{},{},
function(args)
  return C.cast(args.T,types.uint(args.T.precision))
end,
T.rv(T.Par(P.BitsType("T")) ) )


-- convert Uint to Int
generators.UtoI = R.FunctionGenerator("core.UtoI",{},{},
function(args)
  return C.cast(args.T,types.Int(args.T.precision))
end,
T.rv(T.Par(P.UintType("T"))) )


-- convert Int to Uint
generators.ItoU = R.FunctionGenerator("core.ItoU",{},{},
function(args)
  return C.cast(args.T,types.Uint(args.T.precision))
end,
T.rv(T.Par(P.IntType("T"))) )


generators.LUT = R.FunctionGenerator("core.LUT",{"type1","luaFunction"},{},
function(args)
  local vals = J.map(J.range(0,math.pow(2,args.T:verilogBits())-1),args.luaFunction)
  return RM.lut(args.T,args.type1,vals)
end,
T.rv(T.Par(P.UintType("T"))) )



generators.Print = R.FunctionGenerator("core.Print",{"type","rate"},{"string"},
function(args)
  return C.print( args.T, args.string )
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

generators.AddMSBs = R.FunctionGenerator("core.AddMSBs",{},{"number"}, function(args) return C.addMSBs(args.T,args.number) end, P.NumberType("T") )
generators.RemoveMSBs = R.FunctionGenerator("core.RemoveMSBs",{"number"},{}, function(args) return C.removeMSBs(args.T,args.number) end, P.NumberType("T") )
generators.RemoveLSBs = R.FunctionGenerator("core.RemoveLSBs",{"type","rate"},{"number"}, function(args) return C.removeLSBs(args.T,args.number) end, T.rv(T.Par(P.NumberType("T"))) )

generators.Index = R.FunctionGenerator("core.Index",{"type","rate"},{"number","size"},
function(a)
  local ty = a.type:deInterface()
  J.err( ty:isData(),"Index: input should be parallel type, but is: ", a.type )
  
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
end)

generators.ValueToTrigger = R.FunctionGenerator("core.ValueToTrigger",{"type","rate"},{},
function(args) return C.valueToTrigger(args.D) end,
P.DataType("D") )

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
  
  return RM.broadcastStream( args.type:deInterface(), size[1], size[2] )
end)

generators.FanIn = R.FunctionGenerator("core.FanIn",{"type","rate"},{"bool"},
function(args)
  if args.type:isTuple() then
    return RM.packTuple( args.type.list, args.bool )
  elseif args.type:isArray() then
    return RM.packTuple( args.type, args.bool, args.type.size )
  else
    J.err(false, "FanIn: expected handshaked tuple or array input, but is: "..tostring(args.type))
  end
end)

generators.FIFO = R.FunctionGenerator("core.FIFO",{"number","type"},{"bool","string"},
function(args)
  return C.fifo( args.type:deInterface(), args.number, args.bool, nil, nil, nil, args.string )
end )
  
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

generators.Add = R.FunctionGenerator("core.Add",{"type","rate"},{"async","number"},
function(args)
  
  local res = {}
  if args.number~=nil then
    -- add a const (unary op)
    return R.FunctionGenerator( "core.AddConst", {}, {"async","number"}, function(a) return C.plusConst( a.T, args.number ) end, P.NumberType("T") ):complete(args)
  else
    return R.FunctionGenerator("core.AddNonconst", {}, {"async","number"}, function(a) return C.sum( a.T, a.T, a.T, args.async ) end, T.tuple{P.NumberType("T"),P.NumberType("T")} ):complete(args)
  end
end)

-- {{idxType,vType},{idxType,vType}} -> {idxType,vType}
-- async: 0 cycle delay
generators.ArgMax = R.FunctionGenerator("core.ArgMax", {}, {"async"},
function(a) return C.argmin( a.idx, a.T, a.async, true ) end,
T.rv(T.Par(T.tuple{T.tuple{P.DataType("idx"),P.NumberType("T")},T.tuple{P.DataType("idx"),P.NumberType("T")}})) )


generators.ArgMin = R.FunctionGenerator("core.ArgMin", {}, {"async"},
function(a) return C.argmin( a.idx, a.T, a.async, true ) end,
T.rv(T.Par(T.tuple{T.tuple{P.DataType("idx"),P.NumberType("T")},T.tuple{P.DataType("idx"),P.NumberType("T")}})) )


generators.Neg = R.FunctionGenerator("core.Neg", {}, {"async"},
function(a) return C.neg( a.T.precision ) end,
T.rv(T.Par(P.IntType("T"))) )


generators.Sub = R.FunctionGenerator("core.Sub",{},{"async"},
function(args)
  return C.sub( args.T, args.T, args.T, args.async )
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

generators.Abs = R.FunctionGenerator("core.Abs",{},{"async"},
function(a) return C.Abs( a.T, a.async ) end,
T.rv(T.Par(P.NumberType("T"))) )

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
           types.rv(types.Par(types.tuple{P.UintType("T"),P.UintType("T")}))}) )

generators.Not = R.FunctionGenerator("core.Not",{"type","rate"},{"bool"},
function(args)
  J.err( args.type==types.bool(), "generators.Not: input type should be bool, but is: "..tostring(args.type) )
  return C.Not
end)

generators.Zip = R.FunctionGenerator("core.Zip",{"type"},{},
function(args)
  local typelist = {}
  for k,v in ipairs(args.list) do
    typelist[k] = v:arrayOver()
  end

  if args.V:eq(0,0) then
    return RM.ZipSeq( false, typelist, args.size[1], args.size[2] )
  else
    return RM.SoAtoAoS( args.V[1], args.V[2], typelist, nil, args.size[1], args.size[2] )
  end
end,
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

generators.Stencil = R.FunctionGenerator("core.Stencil",{"bounds","rate"},{},
function(a)
  J.err( a.size:eq(a.V) or a.V:eq(0,0) or a.V[2]==1 ,"Stencil: NYI, vector can only be 1D, but is: ",a.V ) -- NYI
  return C.stencilLinebuffer( a.T, a.size[1], a.size[2], a.V[1], a.bounds[1], a.bounds[2], a.bounds[3], a.bounds[4], true )
end,
types.ParSeq(types.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size")) )

generators.Pad = R.FunctionGenerator("core.Pad",{"bounds"},{},
function(a)
  J.err( a.size:eq(a.V) or a.V:eq(0,0) or a.V[2]==1 ,"Pad: NYI, vector can only be 1D, but is: ",a.V ) -- NYI
  return RM.padSeq(a.T,a.size[1],a.size[2],a.V[1],a.bounds[1],a.bounds[2],a.bounds[3],a.bounds[4],0,true)
end,
T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size")) )

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
  return C.cropHelperSeq(a.T,a.size[1],a.size[2],a.V[1],a.bounds[1],a.bounds[2],a.bounds[3],a.bounds[4],true)
end,
T.ParSeq(T.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size")) )

generators.Downsample = R.FunctionGenerator("core.Downsample",{"size"},{},
function(a)
  J.err( a.size:eq(a.V) or a.V:eq(0,0) or a.V[2]==1 ,"Downsample: NYI, vector can only be 1D, but is: ",a.V ) -- NYI
  print("DOWNSAMPLE",a.T,a.V,a.imsize)
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
generators.PosCounter = R.FunctionGenerator("core.PosCounter",{},{},
function(args)
  local V = 0
  if args.opt==0 then assert(args.V[2]==1);V=args.V[1] end
  return RM.posSeq(args.size[1],args.size[2],V,nil,true,true)
end,
P.SumType("opt",{types.rv(T.ParSeq(T.Array2d(T.Trigger,P.SizeValue("V")),P.SizeValue("size"))),
                 types.rv(T.Seq(T.Par(T.Trigger),P.SizeValue("size")))}) )

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
T.Seq(T.Par(T.Array2d(P.DataType("D"),P.SizeValue("inner"))),P.SizeValue("outer"))  )

generators.Fmap = R.FunctionGenerator("core.Fmap",{"rigelFunction","type","rate"},{},
function(args)
  J.err(R.isPlainFunction(args.rigelFunction),"core.FMap should only work on plain functions")

  return R.FunctionGenerator("core.FMap_internal",{"rigelFunction"},{},function(a) return args.rigelFunction end,
                             args.rigelFunction.inputType:deInterface() ):complete(args)
end)

-- bool: allow stateful
generators.Map = R.FunctionGenerator("core.Map",{"rigelFunction","type","rate"},{"bool"},
function(args)

  local fn = args.rigelFunction:specializeToType( types.rv(args.S), args.rate )
  J.err( fn~=nil, "Map: failed to specialize mapped function ",args.rigelFunction.name," to type:",args.D)

  if args.size==args.V then
    return RM.map( fn, args.size[1], args.size[2], args.bool )
  elseif args.V:eq(R.Size(0,0)) then
    return RM.mapSeq( fn, args.size[1], args.size[2] )
  else -- parseq
    return RM.mapParSeq( fn, args.V[1], args.V[2], args.size[1], args.size[2], args.bool )
  end

  assert(false)
end,
T.Array2d(P.ScheduleType("S"),P.SizeValue("size"),P.SizeValue("V")))

generators.Reduce = R.FunctionGenerator("core.Reduce",{"rigelFunction"},{},
function(args)
  local fn = args.rigelFunction:specializeToType( T.rv(types.Tuple{args.T,args.T}), SDF{1,1} )

  J.err( fn.inputType:isrv() and fn.outputType:isrv(),"Reduce: error, reduce can only operator over rv functions, but fn had type: ",fn.inputType,"->",fn.outputType)
  
  if args.V[1]==0 and args.V[2]==0 then
    return RM.reduceSeq( fn, args.size[1], args.size[2], true)
  elseif args.V[1]<args.size[1] or args.V[2]<args.size[2] then
    return RM.reduceParSeq( fn, args.V[1], args.V[2], args.size[1], args.size[2] )
  else
    return RM.reduce( fn, args.size[1],args.size[2])
  end
end,
T.Array2d(P.DataType("T"),P.SizeValue("size"),P.SizeValue("V")))

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
      print("CR1",a.V,a.size)
      return RM.changeRate( a.T, a.V[2], a.V[1], args.number, true, a.size[1], a.size[2] )
    end
  else
    return R.FunctionGenerator("core.SerToWidth",{"number","type","rate"},{},
      function(a)
        return ChangeRateRowMajor( a.T, a.V[1], a.V[2], args.number, a.size[1], a.size[2] )
      end):complete(args)
  end
end)

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


generators.Fwrite = R.FunctionGenerator("core.Fwrite",{"string"},{"filenameVerilog"},
function(args)
  --return RS.modules.fwriteSeq({type=args.type,filename=args.string})
  return RM.fwriteSeq(args.string,args.T,args.filenameVerilog,true)
end,
T.rv(T.Par(P.DataType("T"))) )


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
  J.err( R.isIR(out), "Module: user function returned something other than a Rigel value? "..tostring(out))
  
  return RM.lambda( args.string, input, out, args.instanceList )
end,nil,false)

-- string is name
generators.SchedulableFunction = R.FunctionGenerator("core.Function",{"luaFunction","type","type1"},{"string","rate"},
function(args)
  print("Scheculed SchedulableFunction ",args.type,args.type1)
  
  if args.string==nil then
    args.string = "unnamedSchedulableFunction"..__unnamedID
    __unnamedID = __unnamedID+1
  end

  J.err( args.type1:isData(),"SchedulableFunction declared input type should be data type, but is: ",args.type1 )
  J.err( args.type1:isSupertypeOf(args.type:deSchedule(),{},""),"SchedulableFunction was passed an input type that can't be converted to declared type! declared:", args.type1, " passed:", args.type )

  local schedulePassInput = R.input( types.rv(args.type:deInterface()), args.rate, true )
  local scheduleOut = args.luaFunction(schedulePassInput)
  J.err( R.isIR(scheduleOut), "SchedulableFunction: user function returned something other than a Rigel value? ",scheduleOut)
  J.err( type(scheduleOut.scheduleConstraints)=="table","Internal Error, schedule pass didn't return constraints?")
  J.err( type(scheduleOut.scheduleConstraints.RV)=="boolean","Internal Error, schedule pass didn't return RV constraint?")
  
  print("Schedule Pass result, RV:", scheduleOut.scheduleConstraints.RV )
  
  local input
  if scheduleOut.scheduleConstraints.RV then
    -- this needs an RV interface
    input = R.input( types.RV(args.type:deInterface()), args.rate )
  else
    input = R.input( types.rv(args.type:deInterface()), args.rate )
  end

  print("Schedulable input type:",input.type)
  
  local out = args.luaFunction(input)
  J.err( R.isIR(out), "SchedulableFunction: user function returned something other than a Rigel value? "..tostring(out))

  return RM.lambda( args.string, input, out )
end,nil,true)

--generators.Function = generators.Module

--[=[
generators.Generator = R.FunctionGenerator("core.Generator",{"luaFunction","type","type1"},{"string","rate1","instanceList"},
function(args)
  if args.string==nil then
    args.string = "unnamedModuleGen"..__unnamedID
    __unnamedID = __unnamedID+1
  end

  return R.FunctionGenerator( args.string,{"type","luaFunction","type1"},{"string","instanceList","rate"},
    function(a)
      local input = R.input( a.type, args.rate )
      local out = args.luaFunction(input)
      J.err( R.isIR(out), "Module: user function returned something other than a Rigel value? "..tostring(out))
  
      return RM.lambda( args.string, input, out, args.instanceList )
    end,args.type1:deInterface()):complete(args)
  end)]=]

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
  return SOC.writeBurst( a.string, a.size[1], a.size[2], a.T, a.V[1], a.V[2], true, a.rigelFunction, a.address )
end,
types.ParSeq(types.array2d(P.DataType("T"),P.SizeValue("V")),P.SizeValue("size")) )

--[=[
generators.Reshape = R.FunctionGenerator("core.Reshape",{"type","rate"},{},
function(args)
  local ratio = Uniform(args.rate[1][1]):toNumber()/Uniform(args.rate[1][2]):toNumber()

  if ratio<=1 then
    if args.type:isRV() then

      local function reduceRatio(ty)
        if ty:isArray() then
          if ty.V:eq(0,0) then
            -- recurse until we find something we can devectorize
            return generators.Map{reduceRatio(ty:arrayOver())}
          else
            local chan = canonicalV( args.rate, ty.V )
            return generators.SerToWidth{chan}
          end
        else
          -- Not an array, so can't do anything, just do a passthrough
          return generators.Identity
        end
      end
      
      return reduceRatio( args.type:deInterface(), ratio ):complete(args)
    else
      print("Reshape: upsupported type ",args.type)
      assert(false)
    end
  end

  -- even if ratio==1, we still want it to break T[1;W,H} into T{W,H} canonical form
--  if ratio==1 and args.type:deInterface():isArray() and
--    Uniform(args.type:deInterface().V[1]):toNumber()==1 and
--    Uniform(args.type:deInterface().V[2]):toNumber()==1 
--  then
--    return generators.SerToWidth{0}:complete(args)
--  end
  
  -- if ratio >=1, don't do anything:
  return generators.Identity:complete(args)
end)
]=]

-- change dims of array
generators.ReshapeArray = R.FunctionGenerator("core.ReshapeArray",{"size"},{},
function(args)
  J.err( args.size[1]*args.size[2]==args.insize[1]*args.insize[2], "ReshapeArray: total number of items must not change. Input size: ",args.insize," requested reshape: ",args.size )
  return C.cast( T.Array2d(args.T,args.insize), T.Array2d(args.T,args.size) )
end,
types.array2d(P.DataType("T"),P.SizeValue("insize")) )


generators.Sort = R.FunctionGenerator("core.Sort",{"rigelFunction"},{},
function(args)
  J.err( args.size[2]==1,"generators.Sort: must be 1d array" )
  return C.oddEvenMergeSort( args.T, args.size[1], args.rigelFunction )
end,
types.array2d(P.DataType("T"),P.SizeValue("size")) )


generators.Identity = R.FunctionGenerator("core.Identity",{},{},
function(args) return C.identity(args.T) end,
P.DataType("T") )


generators.Sel = R.FunctionGenerator("core.Sel",{},{},
function(args)
  return C.select(args.T)
end,
types.tuple{types.bool(),P.DataType("T"),P.DataType("T")} )


generators.Slice = R.FunctionGenerator("core.Slice",{"size"},{},
function(args)
  J.err( args.arsize[2]==1, "generators.Slice: NYI - only 1d arrays supported" )
  return C.slice( types.array2d(args.T,args.arsize), args.size[1], args.size[2], 0, 0)
end,
types.array2d(P.DataType("T"),P.SizeValue("arsize")) )


generators.TupleToArray = R.FunctionGenerator("core.TupleToArray",{},{},
function(a)
  return C.tupleToArray( a.T.list[1], #a.T.list )
end,
P.TupleType("T") )

generators.ArrayToTuple = R.FunctionGenerator("core.ArrayToTuple",{},{},
function(a)
  local C = require "generators.examplescommon"
  return C.ArrayToTuple( a.D, a.size[1], a.size[2] )
end,
T.Array2d(P.DataType("D"),P.SizeValue("size")) )

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


generators.Const = R.FunctionGenerator("core.Const",{"type1","number"},{},
function(args)
  return C.triggerToConstant(args.type1,args.number)
end,
T.Trigger )


function generators.export(t)
  if t==nil then t=_G end
  for k,v in pairs(generators) do rawset(t,k,v) end
end

return generators
