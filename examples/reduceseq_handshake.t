local R = require "rigel"
local RM = require "modules"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

inputW = 128
inputH = 64

DOWNSAMP = 4

BASE_TYPE = types.uint(8)

local toint32inp = S.parameter("inp", types.uint(8))
local toint32 = RM.lift( "toint32", types.uint(8), types.int(32), 1, terra( a : &uint8, out : &int32 ) @out = [int32](@a) end, toint32inp, S.cast(toint32inp, types.int(32)) )

local touint8inp = S.parameter("inp", types.int(32))
local touint8 = RM.lift( "touint8", types.int(32), types.uint(8), 1, terra( a : &int32, out : &uint8 ) @out = [uint8](@a >> 2) end, touint8inp, S.cast(S.rshift(touint8inp,S.constant(2,types.int(32))), types.uint(8)) )

local rsinp = S.parameter( "inp", types.tuple { types.int(32), types.int(32) } )
local reduceSumInt32_0cyc = RM.lift( "reduceSumInt32_0cyc", types.tuple { types.int(32), types.int(32) }, types.int(32), 0, terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, rsinp, (S.index(rsinp,0)+S.index(rsinp,1)):disablePipelining() )

local inp = R.input( darkroom.Handshake( types.uint(8) ) )
local out = R.apply("toint32", RM.makeHandshake(toint32), inp)
local out = R.apply("rseq", RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(reduceSumInt32_0cyc,1/DOWNSAMP)) ), out )
local out = R.apply("touint8", RM.makeHandshake(touint8), out)
local hsfn = RM.lambda( "hsfn", inp, out )

harness{ outFile="reduceseq_handshake", fn=hsfn, inFile="frame_128.raw", inSize={inputW,inputH}, inType=types.uint(8), inP=1, outType=types.uint(8), outP=1, outSize={inputW/DOWNSAMP, inputH} }
