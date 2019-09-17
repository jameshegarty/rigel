local R = require "rigel"
local RM = require "generators.modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"
require "common".export()

W = 128
H = 64
T = 8

local f1080p = string.find(arg[0],"1080p")

if f1080p~=nil then
  W=1920
  H=1080
end

--inp = S.parameter("inp",types.uint(8))
--plus100 = RM.lift( "plus100", types.uint(8), types.uint(8) , 10, terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, inp, inp + S.constant(100,types.uint(8)) )

------------
inp = R.input( types.rv(types.Par(types.uint(8))) )
a = R.apply("a", C.plus100(types.uint(8)), inp)
b = R.apply("b", C.plus100(types.uint(8)), a)
p200 = RM.lambda( "p200", inp, b )
------------
ITYPE = types.array2d( types.uint(8), T )
inp = R.input( types.rv(types.Par(ITYPE)) )
out = R.apply( "plus100", RM.map( p200, T ), inp )
fn = RM.lambda( "pointwise_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

harness{ outFile="pointwise_wide_handshake"..sel(f1080p~=nil,"_1080p",""), fn=hsfn, inFile=sel(f1080p~=nil,"1080p.raw","frame_128.raw"), inSize={W,H}, outSize={W,H} }
