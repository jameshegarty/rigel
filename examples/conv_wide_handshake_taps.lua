local R = require "rigel"
local RM = require "generators.modules"
local C = require "generators.examplescommon"
local types = require("types")
local S = require("systolic")
local harness = require("generators.harness")
require "common".export()
local soc = require "generators.soc"
local G = require "generators.core"

R.SDF=false -- for taps

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

local partial = C.multiply(types.uint(8),types.uint(8),types.int(32))
local touint8 = C.shiftAndCast(types.int(32),types.uint(8),8)
local reduceSumInt32 = C.sum(types.int(32),types.int(32),types.int(32))
-------------
local STTYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth )

local tapValue = range(ConvArea)

--soc.taps = R.newGlobal("taps","input",STTYPE,tapValue)
local regs = soc.regStub{taps={STTYPE,tapValue}}:instantiate("taps")
regs.extern = true

local ITYPE = STTYPE
inp = R.input( types.rv(types.Par(ITYPE)) )
--local tapv = R.readGlobal("tg",regs.coeffs)
packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth,ConvWidth,{types.uint(8),types.uint(8)}), R.concat("tc",{inp,RM.Storv(regs.taps)(G.ValueToTrigger(inp))}) )
conv = R.apply( "partial", RM.map( partial, ConvWidth, ConvWidth ), packed )
conv = R.apply( "sum", RM.reduce( reduceSumInt32, ConvWidth, ConvWidth ), conv )
conv = R.apply( "touint8", touint8, conv )

convolve = RM.lambda( "convolve", inp, conv )

-------------
BASE_TYPE = types.array2d( types.uint(8), T )
ITYPE = BASE_TYPE
inp = R.input( types.rv(types.Par(ITYPE)) )

convLB = R.apply( "convLB", C.stencilLinebuffer( types.uint(8), W,H, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inp)
convstencils = R.apply( "convstencils",  C.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T  ), convLB )

convpipe = R.apply( "conv",  RM.map( convolve, T ), convstencils )
convpipe = R.apply( "border", C.borderSeq( types.uint(8), inputW, inputH, T, ConvWidth-1, 0, ConvWidth-1, 0, 0 ), convpipe ) -- cut off junk

convpipe = RM.lambda( "convpipe", inp, convpipe )
-------------
hsfn = RM.makeHandshake(convpipe)



harness{ outFile="conv_wide_handshake_taps", fn=hsfn, inFile="frame_128.raw", tapType=STTYPE, tapValue=tapValue, inSize={inputW,inputH}, outSize={inputW,inputH} }
