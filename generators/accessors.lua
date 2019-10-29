local R = require "rigel"
local T = require "types"
local SDF = require "sdf"
local RM = require "generators.modules"
local C = require "generators.examplescommon"
local P = require "params"

-- These higher-order generators are access patterns over generic memories
-- They expect to opearate over a generic generator G, which takes in a parameter T.
-- T is the type this reads per cycle. The resulting module should take in a uint
-- which is the address, at the granularity of T.

local A = {}

-- Read arrays at user-provided addresses
-- performs S-T tradeoffs
local function ReadRandomArray(ty,size,gen)

end

A.ReadArrays = R.FunctionGenerator("accessors.ReadArrays",{"rigelFunction","type","type1","rate","size"},{},
function(args)
  local seq = args.rate[1][2]:toNumber()/args.rate[1][1]:toNumber()
  local V = (args.size[1]*args.size[2])/seq
      
  V = math.ceil(V)
  while (args.size[1]*args.size[2])%V~=0 do
    V = V + 1
  end
  seq = (args.size[1]*args.size[2])/V

  local readFn = RM.makeHandshake(args.rigelFunction{T.rv(T.Par(T.uint(32))),T.Array2d(args.type1,V),SDF{1,1}})
  print("READFN",readFn)
  
  local cntr = RM.triggeredCounter(T.uint(32),seq)
  print("CNTR",cntr)
  local res = C.compose("A_ReadArrays",readFn,cntr)

  -- hack
  res.outputType = T.RV(T.ParSeq(T.Array2d(args.type1,V),args.size))
  print("RES",res)
  return res
end,
T.RV(T.Par(T.Uint(32))),
T.RV(T.ParSeq(T.Array2d(P.DataType("D"),P.SizeValue("V")),P.SizeValue("S"))))

return A
