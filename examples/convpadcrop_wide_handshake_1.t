local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

--T = 8 -- throughput
function MAKE(T)
--ConvRadius = 1
local ConvRadius = 2
local ConvWidth = ConvRadius*2+1
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

-------------
local sinp = S.parameter( "inp", types.tuple {types.uint(8),types.uint(8)} )
local partial = d.lift( "partial", types.tuple {types.uint(8),types.uint(8)}, types.int(32), 1,
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
local inp = d.input( types.array2d( types.uint(8), ConvWidth, ConvWidth ) )
local kernel = rep(1,ConvWidth*ConvWidth)
local r = d.constant( "convkernel", kernel, types.array2d( types.uint(8), ConvWidth, ConvWidth) )

local packed = d.apply( "packedtup", d.SoAtoAoS(ConvWidth,ConvWidth,{types.uint(8),types.uint(8)}), d.tuple("ptup", {inp,r}) )
local conv = d.apply( "partial", d.map( partial, ConvWidth, ConvWidth ), packed )
local conv = d.apply( "sum", d.reduce( reduceSumInt32, ConvWidth, ConvWidth ), conv )
local conv = d.apply( "touint8", touint8, conv )

local convolve = d.lambda( "convolve", inp, conv )
-------------
local BASE_TYPE = types.array2d( types.uint(8), T )
local ITYPE = d.Stateful(BASE_TYPE)
local inp = d.input( ITYPE )

--I = d.apply("crop", d.cropSeq(types.uint(8),W,H,T,ConvWidth,0,ConvWidth,0,0), inp)
local convLB = d.apply( "convLB", d.stencilLinebuffer( types.uint(8), internalW, internalH, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inp)
local convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T ) ), convLB )
local convpipe = d.apply( "conv", d.makeStateful( d.map( convolve, T ) ), convstencils )

local convpipe = d.lambda( "convpipe", inp, convpipe )
-------------
local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus
local hsfninp = d.input( d.StatefulHandshake(RW_TYPE) )
--local out = hsfninp
local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),8,T)), hsfninp )
local out = d.apply("pad", d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, T, PadRadius, PadRadius, ConvRadius, ConvRadius, 0)), out)
local out = d.apply("HH",d.makeHandshake(convpipe), out)
local out = d.apply("crop",d.liftHandshake(d.liftDecimate(d.cropHelperSeq(types.uint(8), internalW, internalH, T, PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0, 0))), out)
local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),T,8)), out )
local hsfn = d.lambda("hsfn", hsfninp, out)

harness.axi( "convpadcrop_wide_handshake_"..T, hsfn, RW_TYPE, inputW, inputH, RW_TYPE, outputW, outputH )
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
MAKE(tonumber(t))
