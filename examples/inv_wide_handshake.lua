local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"

W = 128
H = 64
T = 8

local invtable = {}
--terra inv(a:uint32) 
function inv(a)
  if a==0 then 
    return 0 
  else
    local o = math.floor(2048/a)
    if o>255 then return 255 end
    return o
  end 
end

for i=0,255 do table.insert(invtable, inv(i)) end

------------
ITYPE = types.array2d( types.uint(8), T )
inp = R.input( types.rv(types.Par(ITYPE)) )
out = R.apply( "inv", RM.map( RM.lut(types.uint(8), types.uint(8), invtable), T ), inp )
fn = RM.lambda( "pointwise_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

harness{ outFile="inv_wide_handshake", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
