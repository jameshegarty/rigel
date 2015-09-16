local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

--T = 8 -- throughput
function MAKE(T)
  assert(T<=1)
--ConvRadius = 1
local ConvRadius = 2
-- put center at (ConvRadius,ConvRadius)
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

-------------
local sinp = S.parameter( "inp", types.tuple {types.uint(8),types.uint(8)} )
local partial = d.lift( "partial", types.tuple {types.uint(8),types.uint(8)}, types.uint(32), 1,
                  terra( a : &tuple(uint8,uint8), out : &uint32 )
                    @out = [uint32](a._0)*[uint32](a._1)
                  end, sinp, S.cast(S.index(sinp,0),types.uint(32))*S.cast(S.index(sinp,1),types.uint(32)) )
-------------
local touint8inp = S.parameter("inp", types.uint(32))
local touint8 = d.lift( "touint8", types.uint(32), types.uint(8), 1, terra( a : &uint32, out : &uint8 ) @out = [uint8](@a >> 7) end, touint8inp, S.cast(S.rshift(touint8inp,S.constant(7,types.uint(32))), types.uint(8)) )
local touint8Array1 = d.lift( "touint8Array1", types.uint(32), types.array2d(types.uint(8),1), 1, terra( a : &uint32, out : &uint8[1] ) @out = arrayof(uint8,(@a >> 7)) end, touint8inp, S.cast(S.rshift(touint8inp,S.constant(7,types.uint(32))), types.array2d(types.uint(8),1) ) )
-------------
local rsinp = S.parameter( "inp", types.tuple { types.uint(32), types.uint(32) } )
local reduceSumUint32 = d.lift( "reduceSumUint32", types.tuple { types.uint(32), types.uint(32) }, types.uint(32), 1, terra( inp : &tuple(uint32,uint32), out : &uint32 ) @out = inp._0 + inp._1 end, rsinp, S.index(rsinp,0)+S.index(rsinp,1) )
local reduceSumUint32_0cyc = d.lift( "reduceSumUint32_0cyc", types.tuple { types.uint(32), types.uint(32) }, types.uint(32), 0, terra( inp : &tuple(uint32,uint32), out : &uint32 ) @out = inp._0 + inp._1 end, rsinp, (S.index(rsinp,0)+S.index(rsinp,1)):disablePipelining() )
-------------
local inp = d.input( types.array2d( types.uint(8), ConvWidth*T, ConvWidth ) )
local kernel = range(ConvWidth*ConvWidth)
local r = d.apply( "convKernel", d.constSeq( kernel, types.uint(8), ConvWidth, ConvWidth, T ) )

local packed = d.apply( "packedtup", d.SoAtoAoS(ConvWidth*T,ConvWidth,{types.uint(8),types.uint(8)}), d.tuple("ptup", {inp,r}) )
local conv = d.apply( "partial", d.map( partial, ConvWidth*T, ConvWidth ), packed )
local conv = d.apply( "sum", d.reduce( reduceSumUint32, ConvWidth*T, ConvWidth ), conv )

local convseq = d.lambda( "convseq", inp, conv )
------------------
inp = d.input( darkroom.V(types.array2d( types.uint(8), ConvWidth*T, ConvWidth )) )
conv = d.apply( "convseqapply", d.liftDecimate(d.liftBasic(convseq)), inp)
conv = d.apply( "sumseq", d.RPassthrough(d.liftDecimate(d.reduceSeq( reduceSumUint32_0cyc, T ))), conv )
conv = d.apply( "touint8", d.RVPassthrough(touint8Array1), conv )
conv = d.apply("FW",d.RVPassthrough(d.fwriteSeq("REDUCEOUT.raw",types.array2d(types.uint(8),1))), conv)
local convolve = d.lambda( "convolve", inp, conv )
-------------
local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus
local hsfninp = d.input( d.Handshake(RW_TYPE) )
--local out = hsfninp
local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,1)), hsfninp )
local out = d.apply("pad", d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, 1, PadRadius, PadRadius, ConvRadius, ConvRadius, 0)), out)
--local out = d.apply("HH",d.liftHandshake(convpipe), out)
local out = d.apply( "convLB", d.stencilLinebufferPartial( types.uint(8), internalW, internalH, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), out)
local out = d.apply( "conv", d.liftHandshake(convolve), out )

local out = d.apply("crop",d.liftHandshake(d.liftDecimate(d.cropHelperSeq(types.uint(8), internalW, internalH, 1, PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0))), out)
local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,1,8)), out )
local hsfn = d.lambda("hsfn", hsfninp, out)

harness.axi( "conv_tr_handshake_"..(1/T), hsfn, "frame_128.raw", nil, nil, RW_TYPE, 8,inputW, inputH, RW_TYPE, 8,outputW, outputH )
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
MAKE(tonumber(1/t))
