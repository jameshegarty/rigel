local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
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
inp = d.input( ITYPE )
out = d.apply( "inv", d.map( d.lut(types.uint(8), types.uint(8), invtable), T ), inp )
fn = d.lambda( "pointwise_wide", inp, out )
------------
--ITYPE = d.StatefulHandshake(ITYPE)
--inp = d.input( ITYPE )
--out = d.apply( "hs", d.makeHandshake(d.makeStateful(fn)), inp)
--hsfn = d.lambda( "pointwise_wide_hs", inp, out )
hsfn = d.makeHandshake(fn)

harness.axi( "inv_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)