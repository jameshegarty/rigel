local R = require "rigel"
local RM = require "modules"
local ffi = require("ffi")
local types = require("types")
types.export()
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"
require "common".export()

W = 15
H = 15
T = 1


harness{ outFile="1pxout", fn=RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(C.sum(u(8),u(8),u(8),true),1/(W*H)))), inFile="15x15.raw", inSize={W,H}, outSize={1,1} }
