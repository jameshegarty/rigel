local R = require "rigel"
local RM = require "generators.modules"
local C = require "generators.examplescommon"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"

function MAKE(T)
  assert(T<=1)


  local ConvWidth = 4


  --local sinp = S.parameter( "inp", types.array2d(types.uint(8),ConvWidth*T,ConvWidth) )
  --local extract = RM.lift( "extract", types.array2d(types.uint(8),ConvWidth*T,ConvWidth), types.array2d(types.uint(8),1,1), 1,
  --                        terra( a : &uint8[ConvWidth*T*ConvWidth], out : &uint8[1] )
  --                          (@out)[0] = (@a)[0]
  --                        end, sinp, S.slice(sinp,0,0,0,0) )
  local extract = C.index( types.array2d(types.uint(8),ConvWidth*T,ConvWidth), 0, 0 )
  extract = C.compose("extract",C.arrayop(types.uint(8),1,1),extract)

  local inputW = 128
  local inputH = 64


  local BASE_TYPE = types.array2d( types.uint(8), 1 )

  local ITYPE = R.Handshake(BASE_TYPE)
  local inp = R.input( ITYPE )
  
  local out = R.apply( "convLB", C.stencilLinebufferPartial( types.uint(8), inputW, inputH, 1/T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inp)
  out = R.apply("extract",RM.makeHandshake(extract),out)
  out = R.apply( "border", RM.makeHandshake( C.borderSeq( types.uint(8), inputW/T, inputH, 1, (ConvWidth-1)/T, 0, ConvWidth-1, 0, 0 )), out ) -- cut off the junk (undefined region)
  local hsfn = RM.lambda("lbp", inp, out)
  
  harness{ outFile="linebufferpartial_handshake_"..(1/T), fn=hsfn, inFile="frame_128.raw", inSize={inputW,inputH}, outSize={inputW/T,inputH} }
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
MAKE(tonumber(1/t))
