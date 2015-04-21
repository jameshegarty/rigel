local d = require "darkroom"
local Image = require "image"
local types = require("types")

W = 128
H = 64
T = 1 -- throughput
ConvRadius = 3
ConvWidth = ConvRadius*2+1
ConvArea = math.pow(ConvWidth,2)

-------------
stfn = d.lift( types.array2d(types.uint(8),ConvWidth,ConvWidth), types.array2d(types.uint(8),1), 
               terra( a : &uint8[ConvWidth*ConvWidth], out : &uint8[1] )
                 (@out)[0] = (@a)[0]
               end, 0 )
-------------
ITYPE = d.Stateful(types.array2d( types.uint(8), T ))
inp = d.input( ITYPE )

convLB = d.apply( "convLB", d.linebuffer( T, W,H, -ConvWidth+1, 0, 0, -ConvWidth+1 ), inp)
convpipe = d.apply( "conv", d.statePassthrough( stfn ), convLB )

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------

convolve, SimState, State = convpipe:compile()
convolve:printpretty()
doit = darkroom.scanlHarness( convolve, SimState, State, T, "frame_128.bmp", ITYPE, W, H, "out/lb_wide.bmp", ITYPE, W, H)
doit()
