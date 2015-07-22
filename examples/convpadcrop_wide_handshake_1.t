local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

--T = 8 -- throughput
function MAKE(T)
--ConvRadius = 1
local ConvRadius = 2
local ConvWidth = ConvRadius*2
local ConvArea = math.pow( ConvWidth, 2 )

local inputW = 128
local inputH = 64

local PadRadius = upToNearest(T, ConvRadius)

-- expand to include crop region
--W = upToNearest(T,128+ConvWidth-1)
--H = 64+ConvWidth-1

local internalW = inputW+PadRadius*2
local internalH = inputH+ConvRadius*2

--outputW = internalW
--outputH = internalH

local outputW = inputW
local outputH = inputH

local TAP_TYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth )
local TAP_TYPE_CONST = TAP_TYPE:makeConst()

-------------
local sinp = S.parameter( "inp", types.tuple {types.uint(8),types.uint(8):makeConst()} )
local partial = d.lift( "partial", types.tuple {types.uint(8),types.uint(8):makeConst()}, types.int(32), 1,
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end, sinp, S.cast(S.index(sinp,0),types.int(32))*S.cast(S.index(sinp,1),types.int(32)) )
-------------
local touint8inp = S.parameter("inp", types.int(32))
local touint8 = d.lift( "touint8", types.int(32), types.uint(8), 1, terra( a : &int32, out : &uint8 ) @out = [uint8](@a >> 5) end, touint8inp, S.cast(S.rshift(touint8inp,S.constant(5,types.int(32))), types.uint(8)) )
-------------
local rsinp = S.parameter( "inp", types.tuple { types.int(32), types.int(32) } )
local reduceSumInt32 = d.lift( "reduceSumInt32", types.tuple { types.int(32), types.int(32) }, types.int(32), 1, terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, rsinp, S.index(rsinp,0)+S.index(rsinp,1) )
-------------
local INP_TYPE = types.tuple{types.array2d( types.uint(8), ConvWidth, ConvWidth ),TAP_TYPE_CONST}
local inp = d.input( INP_TYPE )
--local stinp = d.apply("idx0",d.index(INP_TYPE,0),inp)
--local taps = d.apply("idx1",d.index(INP_TYPE,1),inp)

local packed = d.apply( "packedtup", d.SoAtoAoS(ConvWidth,ConvWidth,{types.uint(8),types.uint(8):makeConst()}), inp )
local conv = d.apply( "partial", d.map( partial, ConvWidth, ConvWidth ), packed )
local conv = d.apply( "sum", d.reduce( reduceSumInt32, ConvWidth, ConvWidth ), conv )
local conv = d.apply( "touint8", touint8, conv )

local convolve = d.lambda( "convolve", inp, conv )
-------------
local BASE_TYPE = types.array2d( types.uint(8), T )
local ITYPE_RAW = types.tuple{BASE_TYPE,TAP_TYPE_CONST}
local ITYPE = d.Stateful( ITYPE_RAW )
local rawinp = d.input( ITYPE )

local inp = d.apply("idx0",d.makeStateful(d.index(ITYPE_RAW,0)),rawinp)
local taps = d.apply("idx1",d.makeStateful(d.index(ITYPE_RAW,1)),rawinp)

local convLB = d.apply( "convLB", d.stencilLinebuffer( types.uint(8), internalW, internalH, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inp)
local convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T ) ), convLB )

local st_tap_inp = d.apply( "broad", d.makeStateful(d.broadcast(TAP_TYPE_CONST,T)), taps )
st_tap_inp = d.tuple("sttapinp",{convstencils,st_tap_inp})
local ST_TYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth )
st_tap_inp = d.apply("ST",d.SoAtoAoSStateful(T,1,{ST_TYPE,TAP_TYPE_CONST}),st_tap_inp)
local convpipe = d.apply( "conv", d.makeStateful( d.map( convolve, T ) ), st_tap_inp )

local convpipe = d.lambda( "convpipe", rawinp, convpipe )
-------------
local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus
local HST = types.tuple{RW_TYPE,TAP_TYPE_CONST}
local hsfninp_raw = d.input( d.StatefulHandshake(HST) )
local hsfninp = d.apply( "idx0", d.makeHandshake(d.makeStateful(d.index(HST,0))), hsfninp_raw )
local hsfn_taps = d.apply( "idx1", d.makeHandshake(d.makeStateful(d.index(HST,1))), hsfninp_raw )
local out = hsfninp

local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,T)), out )
--local out = d.apply("FW",d.makeHandshake(d.fwriteSeq("KERNOUT.raw",types.array2d(types.uint(8),T))), out)
local out = d.apply("pad", d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, T, PadRadius, PadRadius, ConvRadius, ConvRadius, 0)), out)

local convpipeinp = d.tuple("CONVPIPEINP",{out,hsfn_taps})
convpipeinp = d.apply("CPI", darkroom.packTuple({BASE_TYPE,TAP_TYPE_CONST},true), convpipeinp)
local out = d.apply("HH",d.makeHandshake(convpipe), convpipeinp)
local out = d.apply("crop",d.liftHandshake(d.liftDecimate(d.cropHelperSeq(types.uint(8), internalW, internalH, T, PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0, 0))), out)
local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,T,8)), out )
local hsfn = d.lambda("hsfn", hsfninp_raw, out)

harness.axi( "convpadcrop_wide_handshake_"..T, hsfn, RW_TYPE,  TAP_TYPE_CONST, rep(1,ConvWidth*ConvWidth), inputW, inputH, RW_TYPE, outputW, outputH )
--harness.axi( "convpadcrop_wide_handshake_"..T, hsfn, RW_TYPE, inputW, inputH, types.array2d( types.uint(8), 4 ), outputW, outputH )
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
MAKE(tonumber(t))
