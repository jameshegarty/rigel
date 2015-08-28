local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require("harness")

T = 8 -- throughput
--ConvRadius = 1
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)

inputW = 128
inputH = 64

-- expand to include crop region
--W = upToNearest(T,128+ConvWidth-1)
--H = 64+ConvWidth-1

W = inputW
H = inputH

-------------
sinp = S.parameter( "inp", types.tuple {types.uint(8),types.uint(8):makeConst()} )
partial = d.lift( "partial", types.tuple {types.uint(8),types.uint(8):makeConst()}, types.int(32), 1,
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end, sinp, S.cast(S.index(sinp,0),types.int(32))*S.cast(S.index(sinp,1),types.int(32)) )
-------------
touint8inp = S.parameter("inp", types.int(32))
touint8 = d.lift( "touint8", types.int(32), types.uint(8), 1, terra( a : &int32, out : &uint8 ) @out = [uint8](@a >> 8) end, touint8inp, S.cast(S.rshift(touint8inp,S.constant(8,types.int(32))), types.uint(8)) )
-------------
rsinp = S.parameter( "inp", types.tuple { types.int(32), types.int(32) } )
reduceSumInt32 = d.lift( "reduceSumInt32", types.tuple { types.int(32), types.int(32) }, types.int(32), 1, terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, rsinp, S.index(rsinp,0)+S.index(rsinp,1) )
-------------
local STTYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth )
local ITYPE = types.tuple{STTYPE,STTYPE:makeConst()}
inp = d.input( ITYPE )
packed = d.apply( "packedtup", d.SoAtoAoS(ConvWidth,ConvWidth,{types.uint(8),types.uint(8):makeConst()}), inp )
conv = d.apply( "partial", d.map( partial, ConvWidth, ConvWidth ), packed )
conv = d.apply( "sum", d.reduce( reduceSumInt32, ConvWidth, ConvWidth ), conv )
conv = d.apply( "touint8", touint8, conv )

convolve = d.lambda( "convolve", inp, conv )
-------------
BASE_TYPE = types.array2d( types.uint(8), T )
ITYPE = types.tuple{BASE_TYPE,STTYPE:makeConst()}
inp = d.input( d.Stateful(ITYPE) )

local inpdata = d.apply( "i0", d.makeStateful(d.index(ITYPE,0)), inp)
local inptaps = d.apply("idx1",d.makeStateful(d.index(ITYPE,1)), inp)
local st_tap_inp = d.apply( "broad", d.makeStateful(d.broadcast(STTYPE:makeConst(),T)), inptaps )

convLB = d.apply( "convLB", d.stencilLinebuffer( types.uint(8), W,H, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inpdata)
convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T ) ), convLB )

st_tap_inp = d.apply("ST",d.SoAtoAoSStateful(T,1,{STTYPE,STTYPE:makeConst()}), d.tuple("Sttap", {convstencils,st_tap_inp}))
convpipe = d.apply( "conv", d.makeStateful( d.map( convolve, T ) ), st_tap_inp )
convpipe = d.apply( "border", darkroom.borderSeq( types.uint(8), inputW, inputH, T, ConvWidth-1, 0, ConvWidth-1, 0, 0 ), convpipe ) -- cut off junk

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------
hsfn = d.makeHandshake(convpipe)

local tapValue = range(ConvArea)
harness.axi( "conv_wide_handshake_taps", hsfn, "frame_128.raw", STTYPE:makeConst(), tapValue, BASE_TYPE, T, inputW, inputH, BASE_TYPE, T, inputW, inputH )