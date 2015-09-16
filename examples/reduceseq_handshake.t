local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

inputW = 128
inputH = 64

DOWNSAMP = 4

BASE_TYPE = types.uint(8)

local toint32inp = S.parameter("inp", types.uint(8))
local toint32 = d.lift( "toint32", types.uint(8), types.int(32), 1, terra( a : &uint8, out : &int32 ) @out = [int32](@a) end, toint32inp, S.cast(toint32inp, types.int(32)) )

local touint8inp = S.parameter("inp", types.int(32))
local touint8 = d.lift( "touint8", types.int(32), types.uint(8), 1, terra( a : &int32, out : &uint8 ) @out = [uint8](@a >> 2) end, touint8inp, S.cast(S.rshift(touint8inp,S.constant(2,types.int(32))), types.uint(8)) )

local rsinp = S.parameter( "inp", types.tuple { types.int(32), types.int(32) } )
local reduceSumInt32_0cyc = d.lift( "reduceSumInt32_0cyc", types.tuple { types.int(32), types.int(32) }, types.int(32), 0, terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, rsinp, (S.index(rsinp,0)+S.index(rsinp,1)):disablePipelining() )

local inp = d.input( darkroom.Handshake( types.uint(8) ) )
local out = d.apply("toint32", d.makeHandshake(toint32), inp)
local out = d.apply("rseq", d.liftHandshake(d.liftDecimate(d.reduceSeq(reduceSumInt32_0cyc,1/DOWNSAMP)) ), out )
local out = d.apply("touint8", d.makeHandshake(touint8), out)
local hsfn = d.lambda( "hsfn", inp, out )

harness.sim( "reduceseq_handshake", hsfn, "frame_128.raw", nil, nil, types.uint(8), 1,inputW, inputH, types.uint(8), 1,inputW/DOWNSAMP, inputH)
