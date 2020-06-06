local R = require "rigelSimple"
local types = require "types"
local J = require "common"

Type = {types.uint(8), types.array2d(types.uint(8),1,1), types.tuple{types.uint(8)}}
NumP = {1,2,8}
NumPZ = {0,3,8}
Num = {-8,-3,0,2,7}
LRBT = { {0,0,0,0}, {8,3,1,4}, {0,7,34,1} }
IS = {64,32}

local function configToName(t)
  local name = ""

  for k,v in pairs(t) do
    local key = tostring(k).."_"
    if type(k)=="number" then key="" end -- not interesting!

    if type(v)=="number" or type(v)=="boolean" or type(v)=="string" or types.isType(v) then
      name = name..key..J.verilogSanitizeInner(tostring(v)).."_"
    elseif type(v)=="table" then
      local rec = configToName(v)
      if #rec>20 then rec = string.sub(rec,1,20) end
      name = name..key..rec.."_"
    else
      print("CONFIGTONAME",type(v))
      assert(false)
    end
  end

  return name
end

local topcnt = 1
local wrap = J.memoize(function(mod)
  local G = require "generators.core"
  topcnt = topcnt+1
  return G.Function{"Top"..topcnt, mod.inputType, mod.sdfInput, function(inp) return mod(inp) end}
end)

function runTests( configs, meta )
  for k,v in pairs(configs) do
    print("DO configs of ",k)
    
    for configk,config in ipairs(v) do
      local name = k.."_"..configToName(config)
      print("DOCONFIG",name)
      
      local mod = wrap( R.HS(R.modules[k](config),false) )
      
      local met = meta[k][configk]
      
      local targets = {"verilog","terra"}
      
      for _,bk in pairs(targets) do
        R.harness{ outFile=name, fn=mod, inFile="../examples/frame_64.raw", inSize=met.inputImageSize, outSize=met.outputImageSize, backend=bk }
      end
      
    end
  end
end
