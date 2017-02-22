local R = require "rigel"
local RM = require "modules"
local C = require "examplescommon"
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
partial = RM.lift( "partial", types.tuple {types.uint(8),types.uint(8):makeConst()}, types.int(32), 1,
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end, sinp, S.cast(S.index(sinp,0),types.int(32))*S.cast(S.index(sinp,1),types.int(32)) )
-------------
touint8inp = S.parameter("inp", types.int(32))
touint8 = RM.lift( "touint8", types.int(32), types.uint(8), 1, terra( a : &int32, out : &uint8 ) @out = [uint8](@a >> 8) end, touint8inp, S.cast(S.rshift(touint8inp,S.constant(8,types.int(32))), types.uint(8)) )
-------------
rsinp = S.parameter( "inp", types.tuple { types.int(32), types.int(32) } )
reduceSumInt32 = RM.lift( "reduceSumInt32", types.tuple { types.int(32), types.int(32) }, types.int(32), 1, terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, rsinp, S.index(rsinp,0)+S.index(rsinp,1) )
-------------
local STTYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth )
local ITYPE = types.tuple{STTYPE,STTYPE:makeConst()}
inp = R.input( ITYPE )
packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth,ConvWidth,{types.uint(8),types.uint(8):makeConst()}), inp )
conv = R.apply( "partial", RM.map( partial, ConvWidth, ConvWidth ), packed )
conv = R.apply( "sum", RM.reduce( reduceSumInt32, ConvWidth, ConvWidth ), conv )
conv = R.apply( "touint8", touint8, conv )

convolve = RM.lambda( "convolve", inp, conv )
-------------
BASE_TYPE = types.array2d( types.uint(8), T )
ITYPE = types.tuple{BASE_TYPE,STTYPE:makeConst()}
inp = R.input( ITYPE )

local inpdata = R.apply( "i0", C.index(ITYPE,0), inp)
local inptaps = R.apply("idx1",C.index(ITYPE,1), inp)
local st_tap_inp = R.apply( "broad", C.broadcast(STTYPE:makeConst(),T), inptaps )

convLB = R.apply( "convLB", C.stencilLinebuffer( types.uint(8), W,H, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inpdata)
convstencils = R.apply( "convstencils",  C.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T  ), convLB )

st_tap_inp = R.apply("ST",C.SoAtoAoS(T,1,{STTYPE,STTYPE:makeConst()}), R.tuple("Sttap", {convstencils,st_tap_inp}))
convpipe = R.apply( "conv",  RM.map( convolve, T ), st_tap_inp )
convpipe = R.apply( "border", C.borderSeq( types.uint(8), inputW, inputH, T, ConvWidth-1, 0, ConvWidth-1, 0, 0 ), convpipe ) -- cut off junk

convpipe = RM.lambda( "convpipe", inp, convpipe )
-------------
hsfn = RM.makeHandshake(convpipe)

local tapValue = range(ConvArea)

harness{ outFile="conv_wide_handshake_taps", fn=hsfn, inFile="frame_128.raw", tapType=STTYPE:makeConst(), tapValue=tapValue, inSize={inputW,inputH}, outSize={inputW,inputH} }