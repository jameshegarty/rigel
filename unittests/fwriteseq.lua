local R = require "rigel"
local RM = require "generators.modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"

W = 128
H = 64


------------
inp = R.input( types.rv(types.Par(types.uint(8))) )
a = R.apply("a", C.plus100(types.uint(8)), inp)
b = R.apply("b", RM.fwriteSeq("out/fwriteseqtest.raw",types.uint(8),"out/fwriteseqtestVerilog.raw"),a)
p200 = RM.lambda( "p200", inp, b )
------------
hsfn = RM.makeHandshake(p200)

harness{ outFile="fwriteseq", fn=hsfn, inFile="../examples/frame_128.raw", inSize={W,H}, outSize={W,H} }

file = io.open("out/fwriteseq.compiles.txt", "w")
file:write("Hello World")
file:close()
