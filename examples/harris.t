local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"
local harris = require "harris_core"

W = 256
H = 256

T = 8
ITYPE = types.array2d(types.uint(8),T)

local inpraw = d.input(d.Handshake(ITYPE))
local inp = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,1)), inpraw )
local harrisFn = harris(W,H,false)
local out = d.apply("filterfn", harrisFn, inp )
local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,1,8)), out )
fn = d.lambda( "harris", inpraw, out )

harness.axi( "harris", fn, "box_256.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)