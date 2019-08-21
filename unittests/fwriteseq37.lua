local R = require "rigel"
local RM = require "generators.modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"
local RS = require "rigelSimple"

W = 128
H = 64


------------
inp = R.input( types.rv(types.Par(types.uint(8))) )
a = R.apply("a", C.cast(types.uint(8),types.uint(37)), inp)
a = R.apply("AA", C.plus100(types.uint(37)), a)
--b = R.apply("b", RM.fwriteSeq("out/fwriteseq12test.raw",types.uint(12),"out/fwriteseq12testVerilog.raw"),a)
b = RS.writePixels(a,"fwriteseq37",{W,H},1)
p200 = RM.lambda( "p200", inp, b )
------------
hsfn = RM.makeHandshake(p200)

harness{ outFile="fwriteseq37", fn=hsfn, inFile="../examples/frame_128.raw", inSize={W,H}, outSize={W,H} }

file = io.open("out/fwriteseq37.compiles.txt", "w")
file:write("Hello World")
file:close()
