local R = require "rigel"
local RM = require "modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"
local RS = require "rigelSimple"
local f = require "fixed_new"

W = 128
H = 64


------------
inp = f.parameter("finp",RS.uint8)
local out = inp:rcp():removeMSBs(1)
print("OUTTYPE",out.type)
------------
hsfn = RM.makeHandshake(out:toRigelModule("rcp"))

harness{ outFile="rcp", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }

file = io.open("out/rcp.compiles.txt", "w")
file:write("Hello World")
file:close()
