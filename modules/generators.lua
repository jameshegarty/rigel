local R = require "rigel"
local J = require "common"
local types = require "types"
local RM = require "modules"
local RS = require "rigelSimple"
local C = require "examplescommon"
local S = require "systolic"
local SOC = require "soc"
local Uniform = require "uniform"

local __unnamedID = 0

local generators = {}

-- takes A to A[N]
generators.Broadcast = R.newGenerator("generators","Broadcast",{"type","number","rate"},{"size"},
function(args)
  local W,H

  if args.size~=nil then
    W,H = args.size[1], args.size[2]
  else
    W = args.number
  end

  if types.isBasic(args.type) then
    return C.broadcast(args.type,W,H)
  else
    J.err(false, "Broadcast: NYI on type: "..tostring(args.type) )
  end
end)

-- a broadcast is basically the same as a upsample, but has no W,H
generators.BroadcastSeq = R.newGenerator("generators","BroadcastSeq",{"type","number","size","rate"},{},
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

generators.Print = R.newGenerator("generators","Print",{"type","rate"},{"string"},function(args) return C.print(args.type,args.string) end)
generators.FlattenBits = R.newGenerator("generators","FlattenBits",{"type"},{},function(args) return C.flattenBits(args.type) end)
generators.PartitionBits = R.newGenerator("generators","PartitionBits",{"type","number"},{},function(args) return C.partitionBits(args.type,args.number) end)
generators.Rshift = R.newGenerator("generators","Rshift",{"type","rate"},{"number"}, function(args) return C.rshift(args.type,args.number) end)
generators.AddMSBs = R.newGenerator("generators","AddMSBs",{"type","rate"},{"number"}, function(args) return C.addMSBs(args.type,args.number) end)
generators.RemoveMSBs = R.newGenerator("generators","RemoveMSBs",{"type","rate"},{"number"}, function(args) return C.removeMSBs(args.type,args.number) end)
generators.RemoveLSBs = R.newGenerator("generators","RemoveLSBs",{"type","rate"},{"number"}, function(args) return C.removeLSBs(args.type,args.number) end)
generators.Index = R.newGenerator("generators","Index",{"type","rate"},{"number","size"},
                                  function(args)
                                    if args.size~=nil then
                                      return C.index(args.type,args.size[1],args.size[2])
                                    else
                                      return C.index(args.type,args.number)
                                    end
                                  end)
generators.ValueToTrigger = R.newGenerator("generators","ValueToTrigger",{"type","rate"},{}, function(args) return C.valueToTrigger(args.type) end)

generators.TriggerCounter = R.newGenerator("generators","TriggerCounter",{"type","number","rate"},{},
function(args)
  J.err( R.isHandshakeTrigger(args.type), "TriggerCounter: input should be HandshakeTrigger" )
  return RM.triggerCounter(args.number)
end)

generators.TriggerBroadcast = R.newGenerator("generators","TriggerBroadcast",{"type","number","rate"},{},
function(args)
  J.err( R.isHandshakeTrigger(args.type), "TriggerBroadcast: input should be HandshakeTrigger" )
  return C.triggerUp(args.number)
end)

generators.FanOut = R.newGenerator("generators","FanOut",{"type","number","rate"},{},
function(args)
  J.err( R.isHandshake(args.type) or args.type:is("HandshakeFramed") or args.type:is("HandshakeTrigger"),"FanOut: expected handshake input, but is: "..tostring(args.type))
  local mixed, dims
  if args.type:is("HandshakeFramed") then mixed,dims=args.type.params.mixed,args.type.params.dims end
  return RM.broadcastStream( R.extractData(args.type), args.number, args.type:is("HandshakeFramed"), mixed, dims )
end)

generators.FanIn = R.newGenerator("generators","FanIn",{"type","rate"},{"bool"},
function(args)
  J.err( R.isHandshakeTuple(args.type), "FanIn: expected handshake tuple input, but is: "..tostring(args.type))
  return RM.packTuple(args.type.params.list,args.bool)
end)

generators.FIFO = R.newGenerator("generators","FIFO",{"type","number","rate"},{"bool"},
function(args)
  J.err( R.isHandshake(args.type) or R.isHandshakeTrigger(args.type),"FIFO: expected handshake input, but is: "..tostring(args.type))
  local ty = R.extractData(args.type)
  return C.fifo( ty, args.number, args.bool )
end)
  
generators.Add = R.newGenerator("generators","Add",{"type","rate"},{"bool","number"},
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

generators.Sub = R.newGenerator("generators","Sub",{"type","rate"},{"bool"},
function(args)
  J.err( args.type:isTuple(), "generators.Sub: type should be tuple, but is: "..tostring(args.type) )
  J.err( args.type.list[1]==args.type.list[2], "generators.Sub: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )
  return C.sub( args.type.list[1], args.type.list[1], args.type.list[1], args.bool )
end)

generators.Mul = R.newGenerator("generators","Mul",{"type","rate"},{"number"},
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

generators.GT = R.newGenerator("generators","GT",{"type","rate"},{"number"},
function(args)
  if args.number~=nil then
    J.err( args.type:isUint() or args.type:isInt(), "generators.GT: type should be int or uint, but is: "..tostring(args.type) )
    return C.GTConst(args.type, args.number )
  else
    J.err( args.type:isTuple(), "generators.GT: type should be tuple, but is:"..tostring(args.type) )
    J.err( args.type.list[1]==args.type.list[2], "generators.GT: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )

    return C.GT( args.type.list[1], args.type.list[1] )
  end
end)

generators.And = R.newGenerator("generators","And",{"type","rate"},{"bool"},
function(args)
  J.err( args.type:isTuple(), "generators.And: type should be tuple, but is: "..tostring(args.type) )
  J.err( args.type.list[1]==types.bool() and args.type.list[2]==types.bool(), "generators.And: both inputs should be bool" )
  return C.And
end)

generators.Not = R.newGenerator("generators","Not",{"type","rate"},{"bool"},
function(args)
  J.err( args.type==types.bool(), "generators.Not: input type should be bool, but is: "..tostring(args.type) )
  return C.Not
end)

generators.Zip = R.newGenerator("generators","Zip",{"type","rate"},{},
function(args)
  J.err( args.type:isTuple(), "generators.Zip: type should be tuple, but is: "..tostring(args.type) )

  local typelist = {}
  for k,v in ipairs(args.type.list) do
    typelist[k] = v:arrayOver()
  end
  
  return RM.SoAtoAoS( args.type.list[1].size[1], args.type.list[1].size[2], typelist )
end)

generators.HS = R.newGenerator("generators","HS",{"rigelFunction","type","rate"},{},
function(args)

  local mod
  if R.isGenerator(args.rigelFunction) and args.type:is("HandshakeFramed") then
    -- fill in args from HSF
    --mod = args.rigelFunction{args.type.params.A,types.HSFV(args.type),types.HSFSize(args.type)}
    mod = args.rigelFunction{ types.StaticFramed( args.type.params.A, args.type.params.mixed, args.type.params.dims ), args.rate }
  elseif R.isGenerator(args.rigelFunction) then
    local r
    if args.rigelFunction:requiresArg("rate") then r = args.rate end
    mod = args.rigelFunction{R.extractData(args.type), r}
  else
    mod = args.rigelFunction
  end
  
  J.err( R.isGenerator(mod)==false, "generators.HS: input rigel function is a generator, not a module (arguments must be missing)" )
  J.err( R.isModule(mod), "generators.HS: input Rigel function didn't yield a Rigel module? (is "..tostring(mod)..")" )
    
  return RS.HS(mod)
end)

generators.Linebuffer = R.newGenerator("generators","Linebuffer",{"type","size","number","bounds","rate"},{},
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

generators.Stencil = R.newGenerator("generators","Stencil",{"type","bounds","rate"},{},
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
end)

generators.Pad = R.newGenerator("generators","Pad",{"type","size","number","bounds","rate"},{},
function(args)
  J.err(args.number>0,"NYI - V<=0")
  local A = args.type:arrayOver()
  return RM.padSeq(A,args.size[1],args.size[2],args.number,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4],0)
end)


generators.CropSeq = R.newGenerator("generators","CropSeq",{"type","size","number","bounds","rate"},{},
function(args)
  local A = args.type
  if args.number>0 then A  = args.type:arrayOver() end
  
  return RM.cropSeq(A,args.size[1],args.size[2],args.number,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4])
end)

generators.Crop = R.newGenerator("generators","Crop",{"type","bounds","rate"},{},
function(args)
  if args.type:is("StaticFramed") then
    local pixelType = types.HSFPixelType(args.type)
    local size = types.HSFSize(args.type)
    local V = types.HSFV(args.type)

    return RM.cropSeq(pixelType,size[1],size[2],V,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4],true)
  else
    J.err(false,"generators.Crop: unsupported input type: "..tostring(args.type))
  end
end)

generators.Downsample = R.newGenerator("generators","Downsample",{"type","size","rate"},{},
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
generators.Map = R.newGenerator("generators","Map",{"type","rigelFunction","rate"},{"size","bool"},
function(args)
  if args.type:is("StaticFramed") then

    if args.type.params.mixed and #args.type.params.dims==1 then
      local mod = args.rigelFunction
      if R.isGenerator(mod) then
        mod = mod{args.type.params.A:arrayOver(),args.rate}
      end
      J.err( R.isModule(mod), "generators.Map: input didn't yield a rigel module? "..tostring(mod))
      
      assert( args.type.params.A.size[2]==1 )
      local res = RM.map( mod, args.type.params.A.size[1], args.type.params.A.size[2] )
      return RM.mapFramed( res, args.type.params.dims[1][1], args.type.params.dims[1][2], true )
    else
      local size = types.HSFSize(args.type)
      local mod = args.rigelFunction
      if R.isGenerator(mod) then
        mod = mod{args.type:framedOver(),args.rate}
      end
      J.err( R.isModule(mod), "generators.Map: input didn't yield a rigel module? "..tostring(mod))

      -- fully serial
      return RM.mapFramed( mod, size[1], size[2], false )
    end
  elseif args.type:is("HandshakeFramed") then
    if (args.type.params.mixed==false and #args.type.params.dims==1) or (args.type.params.mixed and args.type:FV()==1) then
      -- this is basically just applying a HSF wrapper
      local size = types.HSFSize(args.type)
      local mod = args.rigelFunction
      if R.isGenerator(mod) then
        mod = mod{args.type:framedOver(),args.rate}
      end
      J.err( R.isModule(mod), "generators.Map: function didn't yield a rigel module? "..tostring(mod))

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

      J.err( R.isModule(mod), "generators.Map: input didn't yield a rigel module? (2)")
--      ]=]
      
      -- fully serial
      return RM.mapFramed( mod, size[1], size[2], args.type.params.mixed, ow, oh, omixed )
    else
      J.err(false, "generators.Map: attempted to apply to value with unsupported type: "..tostring(args.type))
    end
  elseif args.type:isArray() then
    local mod = args.rigelFunction
    if R.isGenerator(mod) then
      local r
      if mod:requiresArg("rate") then r = args.rate end

      mod = mod{args.type:arrayOver(),r}
    end
    J.err( R.isModule(mod), "generators.Map: input didn't yield a rigel module? "..tostring(mod))
    
    return RM.map( mod, args.type.size[1], args.type.size[2] )
  else
    J.err(false, "generators.Map: attempted to apply to value with unsupported type: "..tostring(args.type))
  end
end)

generators.Reduce = R.newGenerator("generators","Reduce",{"type","rigelFunction","rate"},{},
function(args)

  local arrayOver
  if args.type:is("StaticFramed") then
    arrayOver = args.type:framedOver()
  else
    J.err( args.type:isArray(), "generators.Reduce: type should be array, but is: "..tostring(args.type) )
    arrayOver = args.type:arrayOver()
  end
  
  local mod
  if R.isGenerator(args.rigelFunction) then
    mod = args.rigelFunction{types.tuple{arrayOver,arrayOver},args.rate}
    assert( R.isModule(mod) )
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
end)

generators.ReduceSeq = R.newGenerator("generators","ReduceSeq",{"type","rigelFunction","number","rate"},{},
function(args)

  local mod
  if R.isGenerator(args.rigelFunction) then
    mod = args.rigelFunction{types.tuple{args.type,args.type},args.rate}
    assert( R.isModule(mod) )
  else
    assert(false)
  end
  
  return RM.reduceSeq( mod, 1/args.number )
end)

-- number is the number of cycles over which to ser
generators.Ser = R.newGenerator("generators","Ser",{"type","number","rate"},{},
function(args)
  J.err( args.type:isArray(), "generators.Ser: type should be array, but is: "..tostring(args.type) )
  --return RM.changeRate( args.type:arrayOver(), args.type:arrayLength()[2], args.type:arrayLength()[1], args.type:arrayLength()[1]/args.number )
  return C.changeRateFramed( args.type:arrayOver(), args.type:arrayLength()[2], args.type:arrayLength()[1], args.number, true )
end)

generators.Deser = R.newGenerator("generators","Deser",{"type","number","rate"},{},
function(args)
  J.err( args.type:isArray(), "generators.Deser: type should be array, but is: "..tostring(args.type) )
  return RM.changeRate( args.type:arrayOver(), args.type:arrayLength()[2], args.type:arrayLength()[1], args.type:arrayLength()[1]*args.number )
  --return C.changeRateFramed( args.type:arrayOver(), args.type:arrayLength()[2], args.type:arrayLength()[1], args.number, false )
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

generators.AXIReadBurstSeq = R.newGenerator("generators","AXIReadBurstSeq",{"type","string","size","rate","number"},{},
function(args)
  -- note: type here should be explicitly passed by the user! This is the type of data we want
  return SOC.readBurst(args.string, args.size[1], args.size[2], args.type, args.number, false)
end)

generators.AXIWriteBurstSeq = R.newGenerator("generators","AXIWriteBurstSeq",{"type","string","size","rate","number"},{},
function(args)
  J.err( R.isHandshake(args.type), "AXIWriteBurstSeq: input must be handshaked, but is: "..tostring(args.type))
  local ty
  if args.number>0 then
    ty = R.extractData(args.type):arrayOver()
  else
    ty = R.extractData(args.type)
  end
  
  return SOC.writeBurst(args.string, args.size[1], args.size[2], ty, args.number, false)
end)

generators.Module = R.newGenerator("generators","Module",{"luaFunction","type"},{"string","rate"},
function(args)
  if args.string==nil then
    args.string = "unnamedModuleGen"..__unnamedID
    __unnamedID = __unnamedID+1
  end

  local input = R.input( args.type, args.rate )
  local out = args.luaFunction(input)
  J.err( R.isIR(out), "Module: user function returned something other than a Rigel value? "..tostring(out))
  
  return RM.lambda( args.string, input, out )
end)

generators.Generator = generators.Module

generators.AXIReadBurst = R.newGenerator("generators","AXIReadBurst",{"string","size","type","rate"},{"number"},
function(args)
  local numb = args.number
  if numb==nil then
    numb = math.ceil((args.size[1]*args.size[2]*Uniform(args.rate[1][1]):toNumber())/Uniform(args.rate[1][2]):toNumber())
    print("AXIReadBurst V:",numb)
  end
  
  return SOC.readBurst( args.string, args.size[1], args.size[2], args.type, numb, true )
end)

generators.AXIRead = R.newGenerator("generators","AXIRead",{"string","type","number","rate"},{},
function(args)
  if args.type:is("Handshake") then
    return SOC.read( args.string, args.number, types.uint(8) )
  else
    J.err( false, "AXIRead: unsupported input type: "..tostring(args.type))
  end
end)

generators.AXIWriteBurst = R.newGenerator("generators","AXIWriteBurst",{"string","type","rate"},{"size","number"},
function(args)
  if args.type:is("HandshakeFramed") then
    return SOC.writeBurst( args.string, args.type:FW(), args.type:FH(), args.type:FPixelType(), args.type:FV(), true )
  else
    J.err( false, "AXIWriteBurst: only framed types supported. unsupported input type: "..tostring(args.type))
  end
end)

generators.WriteGlobal = R.newGenerator("generators","WriteGlobal",{"global"},{},
function(args)
  local WG = generators.Module{"WG",function(i) return R.writeGlobal("go",args.global,i) end}
  WG = WG{args.global.type}
  assert(R.isModule(WG))
  return WG
end)

generators.Reshape = R.newGenerator("generators","Reshape",{"type","rate"},{},
function(args)

  local ratio = Uniform(args.rate[1][1]):toNumber()/Uniform(args.rate[1][2]):toNumber()
  if ratio<1 then

    if args.type:is("HandshakeFramed") and #args.type.params.dims==1 then
      if args.type:FV()*ratio < 1 then
        return generators.Module{function(i) return generators.Map{generators.Reshape}(i) end,args.type,args.rate}
      else
        assert(false)
      end
    elseif args.type:is("Handshake") then
      if args.type.params.A:channels()*ratio < 1 then
        assert(false)
      else
        local res = generators.HS{generators.Ser{args.rate[1][2]/args.rate[1][1]},args.type,args.rate}
        return res
      end
    else
      assert(false)
    end
  elseif ratio>1 then
    assert(false)
  end

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
  end
end)

generators.Sort = R.newGenerator("generators","Sort",{"type","rate","rigelFunction"},{},
function(args)
  J.err( args.type:isArray(),"generators.Sort: input must be array, but is: "..tostring(args.type) )
  J.err( args.type.size[2]==1,"generators.Sort: must be 1d array" )
  return C.oddEvenMergeSort( args.type:arrayOver(), args.type:channels(), args.rigelFunction )
end)

generators.Identity = R.newGenerator("generators","Identity",{"type","rate"},{},
function(args)
  return C.identity(args.type)
end)

generators.Sel = R.newGenerator("generators","Sel",{"type","rate"},{},
function(args)
  J.err( args.type:isTuple(), "generators.Sel: input should be tuple" )
  return C.select(args.type.list[2])
end)

generators.Slice = R.newGenerator("generators","Slice",{"type","rate","size"},{},
function(args)
  J.err( args.type:isArray(), "generators.Slice: input must be array" )
  J.err( args.type.size[2]==1, "generators.Slice: NYI - only 1d arrays supported" )
  return C.slice( args.type, args.size[1], args.size[2], 0, 0)
end)

generators.TupleToArray = R.newGenerator("generators","TupleToArray",{"type","rate"},{},
function(args)
  J.err( args.type:isTuple(), "generators.TupleToArray: input should be tuple" )
  return C.tupleToArray( args.type.list[1], #args.type.list )
end)

generators.FilterSeq = R.newGenerator("generators","FilterSeq",{"type","rate","size"},{},
function(args)
  J.err( args.type:isTuple(), "generators.FilterSeq: input should be tuple" )
  J.err( args.type.list[2]:isBool(), "generators.FilterSeq: input should be tuple of type {A,bool}, but is: "..tostring(args.type) )
  return RM.filterSeq( args.type.list[1], 1, 1, args.size, 0, false )
end)

generators.Arbitrate = R.newGenerator("generators","Arbitrate",{"type","rate"},{},
function(args)
  J.err( types.isHandshakeArray(args.type), "generators.Arbitrate: input should be HandshakeArray, but is: "..tostring(args.type) )
  return RM.arbitrate(args.type.params.A,args.rate)
end)

generators.StripFramed = R.newGenerator("generators","StripFramed",{"type","rate"},{},
function(args)
  return C.stripFramed(args.type)
end)

function generators.export(t)
  if t==nil then t=_G end
  for k,v in pairs(generators) do rawset(t,k,v) end
end

return generators
