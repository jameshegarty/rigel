local R = require "rigel"
local J = require "common"
local types = require "types"
local RM = require "modules"
local RS = require "rigelSimple"
local C = require "examplescommon"
local S = require "systolic"

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

generators.FlattenBits = R.newGenerator("generators","FlattenBits",{"type"},{},function(args) return C.flattenBits(args.type) end)
generators.PartitionBits = R.newGenerator("generators","PartitionBits",{"type","number"},{},function(args) return C.partitionBits(args.type,args.number) end)
generators.Rshift = R.newGenerator("generators","Rshift",{"type"},{"number"}, function(args) return C.rshift(args.type,args.number) end)
generators.AddMSBs = R.newGenerator("generators","AddMSBs",{"type"},{"number"}, function(args) return C.addMSBs(args.type,args.number) end)
generators.RemoveMSBs = R.newGenerator("generators","RemoveMSBs",{"type"},{"number"}, function(args) return C.removeMSBs(args.type,args.number) end)
generators.Index = R.newGenerator("generators","Index",{"type","number"},{}, function(args) return C.index(args.type,args.number) end)
generators.ValueToTrigger = R.newGenerator("generators","ValueToTrigger",{"type"},{}, function(args) return C.valueToTrigger(args.type) end)

generators.Add = R.newGenerator("generators","Add",{"type"},{"bool"},
function(args)
  J.err( args.type:isTuple(), "generators.Add: type should be tuple, but is: "..tostring(args.type) )
  J.err( args.type.list[1]==args.type.list[2], "generators.Add: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )
  return C.sum( args.type.list[1], args.type.list[1], args.type.list[1], args.bool )
end)

generators.Sub = R.newGenerator("generators","Sub",{"type"},{"bool"},
function(args)
  J.err( args.type:isTuple(), "generators.Sub: type should be tuple, but is: "..tostring(args.type) )
  J.err( args.type.list[1]==args.type.list[2], "generators.Sub: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )
  return C.sub( args.type.list[1], args.type.list[1], args.type.list[1], args.bool )
end)

generators.Mul = R.newGenerator("generators","Mul",{"type"},{},
function(args)
  J.err( args.type:isTuple(), "generators.Mul: type should be tuple, but is:"..tostring(args.type) )
  J.err( args.type.list[1]==args.type.list[2], "generators.Mul: lhs type ("..tostring(args.type.list[1])..") must match rhs type ("..tostring(args.type.list[2])..")" )
  return C.multiply( args.type.list[1], args.type.list[1], args.type.list[1], args.bool )
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
  if R.isGenerator(args.rigelFunction) then
    mod = args.rigelFunction{R.extractData(args.type)}
  else
    mod = args.rigelFunction
  end
  J.err( R.isModule(mod), "generators.HS: input Rigel function didn't yield a Rigel module?" )

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

generators.Pad = R.newGenerator("generators","Pad",{"type","size","number","bounds"},{},
function(args)
  J.err(args.number>0,"NYI - V<=0")
  local A = args.type:arrayOver()
  return RM.padSeq(A,args.size[1],args.size[2],args.number,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4],0)
end)

generators.Crop = R.newGenerator("generators","Crop",{"type","size","number","bounds"},{},
function(args)
  J.err(args.number>0,"NYI - V<=0")
  local A = args.type:arrayOver()
  return RM.cropSeq(A,args.size[1],args.size[2],args.number,args.bounds[1],args.bounds[2],args.bounds[3],args.bounds[4])
end)

generators.PosSeq = R.newGenerator("generators","PosSeq",{"size","number"},{},
function(args)
  J.err(args.number>0,"NYI - V<=0")
  return RM.posSeq(args.size[1],args.size[2],args.number)
end)

generators.Map = R.newGenerator("generators","Map",{"type","rigelFunction"},{},
function(args)
  J.err( args.type:isArray(), "generators.Map: type should be array, but is: "..tostring(args.type) )
  local mod = args.rigelFunction
  if R.isGenerator(mod) then
    mod = mod{args.type:arrayOver()}
  end
  J.err( R.isModule(mod), "generators.Map: input didn't yield a rigel module?")
  
  return RM.map( mod, args.type.size[1], args.type.size[2] )
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

function generators.export(t)
  if t==nil then t=_G end
  for k,v in pairs(generators) do rawset(t,k,v) end
end

return generators
