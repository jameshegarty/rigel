local R = require "rigel"
local J = require "common"
local types = require "types"
local RM = require "modules"
local RS = require "rigelSimple"
local C = require "examplescommon"
local S = require "systolic"
local SOC = require "soc"

local __unnamedID = 0

local generators = {}

generators.Broadcast = R.newGenerator("generators","Broadcast",{"type","number"},{"size"},
function(args)
  print("BROADCAST",args.size,args.number)
  if args.size~=nil then
    return C.broadcast(args.type,args.size[1], args.size[2])
  else
    return C.broadcast(args.type,args.number)
  end
end)

-- a broadcast is basically the same as a upsample, but has no W,H
generators.BroadcastSeq = R.newGenerator("generators","BroadcastSeq",{"type","number","size"},{},
function(args)
  J.err( types.isBasic(args.type),"generators.BroadcastSeq: unsupported type: "..tostring(args.type))
  return RM.upsampleXSeq(args.type,args.number,args.size[1]*args.size[2])
end)

-- bits to unsigned
generators.BtoU = R.newGenerator("generators","BtoU",{"type"},{},
function(args)
  J.err( args.type:isBits(), "BtoU input type should be Bits, but is: "..tostring(args.type))
  return C.cast(args.type,types.uint(args.type.precision))
end)

generators.Print = R.newGenerator("generators","Print",{"type"},{"string"},function(args) return C.print(args.type,args.string) end)
generators.FlattenBits = R.newGenerator("generators","FlattenBits",{"type"},{},function(args) return C.flattenBits(args.type) end)
generators.PartitionBits = R.newGenerator("generators","PartitionBits",{"type","number"},{},function(args) return C.partitionBits(args.type,args.number) end)
generators.Rshift = R.newGenerator("generators","Rshift",{"type"},{"number"}, function(args) return C.rshift(args.type,args.number) end)
generators.AddMSBs = R.newGenerator("generators","AddMSBs",{"type"},{"number"}, function(args) return C.addMSBs(args.type,args.number) end)
generators.RemoveMSBs = R.newGenerator("generators","RemoveMSBs",{"type"},{"number"}, function(args) return C.removeMSBs(args.type,args.number) end)
generators.Index = R.newGenerator("generators","Index",{"type"},{"number","size"},
                                  function(args)
                                    if args.size~=nil then
                                      return C.index(args.type,args.size[1],args.size[2])
                                    else
                                      return C.index(args.type,args.number)
                                    end
                                  end)
generators.ValueToTrigger = R.newGenerator("generators","ValueToTrigger",{"type"},{}, function(args) return C.valueToTrigger(args.type) end)

generators.TriggerCounter = R.newGenerator("generators","TriggerCounter",{"type","number"},{},
function(args)
  J.err( R.isHandshakeTrigger(args.type), "TriggerCounter: input should be HandshakeTrigger" )
  return RM.triggerCounter(args.number)
end)

generators.TriggerBroadcast = R.newGenerator("generators","TriggerBroadcast",{"type","number"},{},
function(args)
  J.err( R.isHandshakeTrigger(args.type), "TriggerBroadcast: input should be HandshakeTrigger" )
  return C.triggerUp(args.number)
end)

generators.FanOut = R.newGenerator("generators","FanOut",{"type","number"},{},
function(args)
  J.err( R.isHandshake(args.type) or args.type:is("HandshakeFramed"),"FanOut: expected handshake input, but is: "..tostring(args.type))
  local mixed, dims
  if args.type:is("HandshakeFramed") then mixed,dims=args.type.params.mixed,args.type.params.dims end
  print("FO",mixed,dims)
  return RM.broadcastStream( R.extractData(args.type), args.number, args.type:is("HandshakeFramed"), mixed, dims )
end)

generators.FIFO = R.newGenerator("generators","FIFO",{"type","number"},{},
function(args)
  J.err( R.isHandshake(args.type) or R.isHandshakeTrigger(args.type),"FIFO: expected handshake input, but is: "..tostring(args.type))
  local ty = R.extractData(args.type)
  return C.fifo( ty, args.number )
end)
  
generators.Add = R.newGenerator("generators","Add",{"type"},{"bool","number"},
function(args)
  if args.number~=nil then
    -- add a const (unary op)
    return C.plusConst(args.type,args.number)
  else
    J.err( args.type:isTuple(), "generators.Add: type should be tuple, but is: "..tostring(args.type) )
    J.err( args.type.list[1]==args.type.list[2], "generators.Add: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )
    return C.sum( args.type.list[1], args.type.list[1], args.type.list[1], args.bool )
  end
end)

generators.Sub = R.newGenerator("generators","Sub",{"type"},{"bool"},
function(args)
  J.err( args.type:isTuple(), "generators.Sub: type should be tuple, but is: "..tostring(args.type) )
  J.err( args.type.list[1]==args.type.list[2], "generators.Sub: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )
  return C.sub( args.type.list[1], args.type.list[1], args.type.list[1], args.bool )
end)

generators.Mul = R.newGenerator("generators","Mul",{"type"},{"number"},
function(args)
  if args.number~=nil then
    J.err( args.type:isUint() or args.type:isInt(), "generators.Mul: type should be int or uint, but is: "..tostring(args.type) )
    return C.multiplyConst(args.type, args.number )
  else
    J.err( args.type:isTuple(), "generators.Mul: type should be tuple, but is:"..tostring(args.type) )
    J.err( args.type.list[1]==args.type.list[2], "generators.Mul: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )

    return C.multiply( args.type.list[1], args.type.list[1], args.type.list[1], args.bool )
  end
end)

generators.Zip = R.newGenerator("generators","Zip",{"type"},{},
function(args)
  J.err( args.type:isTuple(), "generators.Zip: type should be tuple, but is: "..tostring(args.type) )

  local typelist = {}
  for k,v in ipairs(args.type.list) do
    typelist[k] = v:arrayOver()
  end
  
  return RM.SoAtoAoS( args.type.list[1].size[1], args.type.list[1].size[2], typelist )
end)

generators.HS = R.newGenerator("generators","HS",{"rigelFunction","type"},{},
function(args)

  local mod
  if R.isGenerator(args.rigelFunction) and args.type:is("HandshakeFramed") then
    -- fill in args from HSF
    --mod = args.rigelFunction{args.type.params.A,types.HSFV(args.type),types.HSFSize(args.type)}
    mod = args.rigelFunction{ types.StaticFramed( args.type.params.A, args.type.params.mixed, args.type.params.dims ) }
  elseif R.isGenerator(args.rigelFunction) then
    mod = args.rigelFunction{R.extractData(args.type)}
  else
    mod = args.rigelFunction
  end
  
  J.err( R.isGenerator(mod)==false, "generators.HS: input rigel function is a generator, not a module (arguments must be missing)" )
  J.err( R.isModule(mod), "generators.HS: input Rigel function didn't yield a Rigel module? (is "..tostring(mod)..")" )
    
  return RS.HS(mod)
end)

generators.Linebuffer = R.newGenerator("generators","Linebuffer",{"type","size","number","bounds"},{},
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

generators.Stencil = R.newGenerator("generators","Linebuffer",{"type","bounds"},{},
function(args)

  if args.type:is("StaticFramed") then
    local pixelType = types.HSFPixelType(args.type)
    local size = types.HSFSize(args.type)
    local V = types.HSFV(args.type)
    print("ST",pixelType,size[1],size[2],V)
    
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
end)

generators.Pad = R.newGenerator("generators","Pad",{"type","size","number","bounds"},{},
function(args)
  J.err(args.number>0,"NYI - V<=0")
  local A = args.type:arrayOver()
  return RM.padSeq(A,args.size[1],args.size[2],args.number,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4],0)
end)


generators.CropSeq = R.newGenerator("generators","Crop",{"type","size","number","bounds"},{},
function(args)
  J.err(args.number>0,"NYI - V<=0")
  local A = args.type:arrayOver()
  return RM.cropSeq(A,args.size[1],args.size[2],args.number,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4])
end)

generators.Crop = R.newGenerator("generators","Crop",{"type","bounds"},{},
function(args)
  if args.type:is("StaticFramed") then
    local pixelType = types.HSFPixelType(args.type)
    local size = types.HSFSize(args.type)
    local V = types.HSFV(args.type)

    return RM.cropSeq(pixelType,size[1],size[2],V,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4],true)
  else
    err(false,"generators.Crop: unsupported input type: "..tostring(args.type))
  end
end)

generators.Downsample = R.newGenerator("generators","Downsample",{"type","size"},{},
function(args)
  if args.type:is("StaticFramed") then
    local size = types.HSFSize(args.type)
    local V = types.HSFV(args.type)

    return C.downsampleSeq( args.type:FPixelType(), args.type:FW(), args.type:FH(), args.type:FV(), args.size[1], args.size[2], true )
  else
    err(false,"generators.Downsample: unsupported input type: "..tostring(args.type))
  end
end)

generators.PosSeq = R.newGenerator("generators","PosSeq",{"size","number"},{"type"},
function(args)
  if args.type~=nil then
    J.err( args.type==types.null(), "PosSeq: expected null input")
  end
  return RM.posSeq(args.size[1],args.size[2],args.number)
end)

generators.Pos = R.newGenerator("generators","PosSeq",{"size","number"},{"type"},
function(args)
  if args.type~=nil then
    J.err( args.type==types.null(), "PosSeq: expected null input")
  end
  return RM.posSeq( args.size[1], args.size[2], args.number, nil, true, true )
end)

-- size/bool: output size/mixed for framed types (needed if vector width/ SDF rate changes...)
--       think of this like a combined map&flatten
generators.Map = R.newGenerator("generators","Map",{"type","rigelFunction"},{"size","bool"},
function(args)
  if args.type:is("StaticFramed") then

    if args.type.params.mixed and #args.type.params.dims==1 then
      local mod = args.rigelFunction
      if R.isGenerator(mod) then
        mod = mod{args.type.params.A:arrayOver()}
      end
      J.err( R.isModule(mod), "generators.Map: input didn't yield a rigel module?")

      assert( args.type.params.A.size[2]==1 )
      local res = RM.map( mod, args.type.params.A.size[1], args.type.params.A.size[2] )
      return RM.mapFramed( res, args.type.params.dims[1][1], args.type.params.dims[1][2], true )
    else
      local size = types.HSFSize(args.type)
      local mod = args.rigelFunction
      if R.isGenerator(mod) then
        mod = mod{args.type:framedOver()}
      end
      J.err( R.isModule(mod), "generators.Map: input didn't yield a rigel module?")

      -- fully serial
      return RM.mapFramed( mod, size[1], size[2], false )
    end
  elseif args.type:is("HandshakeFramed") then
    if args.type.params.mixed==false and #args.type.params.dims==1 then
      -- this is basically just applying a HSF wrapper
      local size = types.HSFSize(args.type)
      local mod = args.rigelFunction
      if R.isGenerator(mod) then
        mod = mod{args.type:framedOver()}
      end
      J.err( R.isModule(mod), "generators.Map: input didn't yield a rigel module?")

      local ow,oh
      if args.size~=nil then ow,oh=args.size[1],args.size[2] end
      
      -- fully serial
      return RM.mapFramed( mod, size[1], size[2], false, ow, oh, args.bool )
    else
      J.err(false, "generators.Map: attempted to apply to value with unsupported type: "..tostring(args.type))
    end
  elseif args.type:isArray() then
    local mod = args.rigelFunction
    if R.isGenerator(mod) then
      mod = mod{args.type:arrayOver()}
    end
    J.err( R.isModule(mod), "generators.Map: input didn't yield a rigel module?")
    
    return RM.map( mod, args.type.size[1], args.type.size[2] )
  else
    J.err(false, "generators.Map: attempted to apply to value with unsupported type: "..tostring(args.type))
  end
end)

generators.Reduce = R.newGenerator("generators","Reduce",{"type","rigelFunction"},{},
function(args)
  J.err( args.type:isArray(), "generators.Reduce: type should be array" )
  local mod
  if R.isGenerator(args.rigelFunction) then
    mod = args.rigelFunction{types.tuple{args.type:arrayOver(),args.type:arrayOver()}}
    assert( R.isModule(mod) )
  else
    assert(false)
  end
  
  return RM.reduce( mod, args.type.size[1], args.type.size[2] )
end)

generators.ReduceSeq = R.newGenerator("generators","Reduce",{"type","rigelFunction","number"},{},
function(args)

  local mod
  if R.isGenerator(args.rigelFunction) then
    mod = args.rigelFunction{types.tuple{args.type,args.type}}
    assert( R.isModule(mod) )
  else
    assert(false)
  end
  
  return RM.reduceSeq( mod, 1/args.number )
end)

-- number is the number of cycles over which to ser
generators.Ser = R.newGenerator("generators","Ser",{"type","number"},{},
function(args)
  J.err( args.type:isArray(), "generators.Ser: type should be array" )
  return RM.changeRate( args.type:arrayOver(), args.type:arrayLength()[2], args.type:arrayLength()[1], args.type:arrayLength()[1]/args.number )
end)

generators.Deser = R.newGenerator("generators","Deser",{"type","number"},{},
function(args)
  J.err( args.type:isArray(), "generators.Deser: type should be array" )
  return RM.changeRate( args.type:arrayOver(), args.type:arrayLength()[2], args.type:arrayLength()[1], args.type:arrayLength()[1]*args.number )
end)

generators.Fwrite = R.newGenerator("generators","Fwrite",{"type","string"},{"size"},
function(args)
  --return RS.modules.fwriteSeq({type=args.type,filename=args.string})
  return RM.fwriteSeq(args.string,args.type,args.string..".verilog.raw",true)
end)

-- assert that the input stream is the same as the file. Early out on errors.
generators.Fassert = R.newGenerator("generators","Fassert",{"type","string"},{},
function(args)
  return C.fassert(args.string,args.type)
end)

generators.WriteBurst = R.newGenerator("generators","WriteBurst",{"type","string","size"},{},
function(args)
  J.err( R.isHandshake(args.type), "WriteBurst: input must be handshaked")
  return SOC.writeBurst(args.string, args.size[1], args.size[2], R.extractData(args.type), 0)
end)

generators.Module = R.newGenerator("generators","Module",{"luaFunction","type"},{"string"},
function(args)
  if args.string==nil then
    args.string = "unnamedModuleGen"..__unnamedID
    __unnamedID = __unnamedID+1
  end

  local input = R.input( args.type )
  local out = args.luaFunction(input)
  J.err( R.isIR(out), "Module: user function returned something other than a Rigel value")
  
  return RM.lambda( args.string, input, out )
end)

generators.Generator = generators.Module

generators.AXIReadBurst = R.newGenerator("generators","AXIReadBurst",{"string","size","type","number"},{},
function(args)
  return SOC.readBurst( args.string, args.size[1], args.size[2], args.type, args.number, true )
end)

generators.AXIRead = R.newGenerator("generators","AXIRead",{"string","type","number"},{},
function(args)
  if args.type:is("Handshake") then
    return SOC.read( args.string, args.number, types.uint(8) )
  else
    J.err( false, "AXIRead: unsupported input type: "..tostring(args.type))
  end
end)

generators.AXIWriteBurst = R.newGenerator("generators","AXIWriteBurst",{"string","type"},{"size","number"},
function(args)
  if args.type:is("HandshakeFramed") then
    return SOC.writeBurst( args.string, args.type:FW(), args.type:FH(), args.type:FPixelType(), args.type:FV(), true )
  else
    J.err( false, "AXIWriteBurst: unsupported input type: "..tostring(args.type))
  end
end)

generators.WriteGlobal = R.newGenerator("generators","WriteGlobal",{"global"},{},
function(args)
  local WG = generators.Module{"WG",function(i) return R.writeGlobal("go",args.global,i) end}
  WG = WG{args.global.type}
  assert(R.isModule(WG))
  return WG
end)
                                        
function generators.export(t)
  if t==nil then t=_G end
  for k,v in pairs(generators) do rawset(t,k,v) end
end

return generators
