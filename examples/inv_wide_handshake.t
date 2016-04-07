local R = require "rigel"
local RM = require "modules"
local types = require("types")
local harness = require "harness"

W = 128
H = 64
T = 8

local invtable = {}
terra inv(a:uint32) 
  if a==0 then 
    return 0 
  else
    var o = 2048/a
    if o>255 then return 255 end
    return o
  end 
end

for i=0,255 do table.insert(invtable, inv(i)) end

------------
ITYPE = types.array2d( types.uint(8), T )
inp = R.input( ITYPE )
out = R.apply( "inv", RM.map( RM.lut(types.uint(8), types.uint(8), invtable), T ), inp )
fn = RM.lambda( "pointwise_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

harness.axi( "inv_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)