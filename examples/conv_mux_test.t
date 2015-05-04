local d = require "darkroom"
local Image = require "image"
local types = require("types")

W = 128
H = 64
--ConvRadius = 3
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)
T = 1/ConvWidth

-------------
ITYPE = types.array2d(types.uint(8),1)
inp = d.input( darkroom.Stateful(ITYPE) )

--convstencils = d.apply( "convtencils", d.stencilLinebufferPartial( types.uint(8), W, H, T, -ConvWidth+1, 0, -ConvWidth+1, 0), inp) -- RV


local V = range(ConvArea)
for i=1,ConvArea do V[i] = 0 end
V[2] = 120
convstencils = d.apply( "convKernel", d.constSeq( V, types.uint(8), ConvWidth, ConvWidth, T ), d.extractState("inext", inp) )

convpipe = d.apply( "conv", d.cat2d(types.uint(8),T,ConvWidth,ConvWidth), convstencils )


convpipe = d.lambda( "convpipe", inp, convpipe )
-------------
ITYPE = darkroom.StatefulHandshake(ITYPE)
convpipeHS = d.liftHandshake(d.liftDecimate(convpipe))
OTYPE = convpipeHS.outputType

Module = convpipeHS:compile()
doit = d.scanlHarnessHandshake( Module, T, "frame_128.bmp", ITYPE,W,H, "out/conv_mux_test.bmp", OTYPE, W*ConvWidth, H*ConvWidth,0,0,0,0)
doit()