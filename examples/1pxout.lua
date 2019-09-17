local R = require "rigel"
local RM = require "generators.modules"
local ffi = require("ffi")
local types = require("types")
types.export()
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"
require "common".export()

W = 15
H = 15
T = 1


harness{ outFile="1pxout", fn=RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(C.sum(u(8),u(8),u(8),true),(W*H)))), inFile="15x15.raw", inSize={W,H}, outSize={1,1} }
