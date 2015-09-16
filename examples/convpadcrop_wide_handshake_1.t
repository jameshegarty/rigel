local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

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

local TAP_TYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth ):makeConst()
-------------
-------------
local convKernel = C.convolveTaps( types.uint(8), ConvWidth)
local kernel = C.stencilKernelTaps( types.uint(8), T, TAP_TYPE, internalW, internalH, ConvWidth, ConvWidth, convKernel)
-------------
local BASE_TYPE = types.array2d( types.uint(8), T )
local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus
local HST = types.tuple{RW_TYPE,TAP_TYPE}
local hsfninp_raw = d.input( d.Handshake(HST) )
local hsfninp = d.apply( "idx0", d.makeHandshake(d.index(HST,0)), hsfninp_raw )
local hsfn_taps = d.apply( "idx1", d.makeHandshake(d.index(HST,1)), hsfninp_raw )
local out = hsfninp

local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,T)), out )
--local out = d.apply("FW",d.makeHandshake(d.fwriteSeq("KERNOUT.raw",types.array2d(types.uint(8),T))), out)
local out = d.apply("pad", d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, T, PadRadius, PadRadius, ConvRadius, ConvRadius, 0)), out)

local convpipeinp = d.apply("CPI", darkroom.packTuple({BASE_TYPE,TAP_TYPE}), d.tuple("CONVPIPEINP",{out,hsfn_taps},false))
local out = d.apply("HH",d.makeHandshake(kernel), convpipeinp)
local out = d.apply("crop",d.liftHandshake(d.liftDecimate(d.cropHelperSeq(types.uint(8), internalW, internalH, T, PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0))), out)
local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,T,8)), out )
local hsfn = d.lambda("hsfn", hsfninp_raw, out)

harness.axi( "convpadcrop_wide_handshake_"..T, hsfn, "frame_128.raw", TAP_TYPE, range(ConvWidth*ConvWidth), RW_TYPE, 8, inputW, inputH, RW_TYPE, 8, outputW, outputH )
--harness.axi( "convpadcrop_wide_handshake_"..T, hsfn, RW_TYPE, inputW, inputH, types.array2d( types.uint(8), 4 ), outputW, outputH )
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
MAKE(tonumber(t))
