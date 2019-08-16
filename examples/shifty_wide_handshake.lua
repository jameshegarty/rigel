local R = require "rigel"
local RM = require "generators.modules"
local C = require "generators.examplescommon"
local types = require "types"
local harness = require "generators.harness"

W = 128
H = 64
T = 8

-------------
RAWTYPE = types.array2d( types.uint(8), T )
inp = R.input( types.rv(types.Par(RAWTYPE)) )
convLB = R.apply( "convLB", RM.linebuffer( types.uint(8), W,H, T, -4 ), inp)
convpipe = R.apply( "slice", C.slice( types.array2d(types.uint(8),T,5), 0, T-1, 0, 0 ), convLB)
convpipe = R.apply( "border", C.borderSeq( types.uint(8), W, H, T, 0, 0, 4, 0, 0 ), convpipe ) -- cut off the junk
convpipe = RM.lambda( "convpipe", inp, convpipe )
hsfn = RM.makeHandshake(convpipe)

harness{ outFile="shifty_wide_handshake", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
