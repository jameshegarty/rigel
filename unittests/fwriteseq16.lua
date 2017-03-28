local R = require "rigel"
local RM = require "modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

W = 128
H = 64


------------
inp = R.input( types.uint(8) )
a = R.apply("a", C.cast(types.uint(8),types.uint(16)), inp)
a = R.apply("AA", C.plus100(types.uint(16)), a)
b = R.apply("b", RM.fwriteSeq("out/fwriteseq16test.raw",types.uint(16),"out/fwriteseq16testVerilog.raw"),a)
p200 = RM.lambda( "p200", inp, b )
------------
hsfn = RM.makeHandshake(p200)

harness{ outFile="fwriteseq16", fn=hsfn, inFile="../examples/frame_128.raw", inSize={W,H}, outSize={W,H} }

file = io.open("out/fwriteseq16.compiles.txt", "w")
file:write("Hello World")
file:close()