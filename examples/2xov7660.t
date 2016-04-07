local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

W = 640
H = 480
T = 4

local ITYPE = types.array2d(types.uint(8),2)
local OTYPE = types.array2d(types.uint(8),4) -- RGB

local SPLIT_TYPE = types.tuple{types.tuple{types.uint(16),types.uint(16)}, ITYPE}
inp = S.parameter("inp",SPLIT_TYPE)

local sout = S.select(S.lt(S.index(S.index(inp,0),0),S.constant(320,types.uint(16))),S.index(S.index(inp,1),0),S.index(S.index(inp,1),1))
sout = S.tuple{sout,sout,sout,S.constant(0,types.uint(8))}
sout = S.cast(sout,OTYPE)

splitfn = RM.lift( "split", SPLIT_TYPE, OTYPE , 10, 
                  terra( a : &SPLIT_TYPE:toTerraType(), out : &OTYPE:toTerraType()  ) 
                  if a._0._0<320 then
                    (@out)[0] = (a._1)[0]
                    (@out)[1] = (a._1)[0]
                    (@out)[2] = (a._1)[0]
                    (@out)[3] = 0
                  else
                    (@out)[0] = (a._1)[1]
                    (@out)[1] = (a._1)[1]
                    (@out)[2] = (a._1)[1]
                    (@out)[3] = 0
                  end
                end, inp, sout )

cr = RM.liftHandshake(RM.changeRate(ITYPE,1,4,2))
sfn = RM.makeHandshake(RM.liftXYSeqPointwise(splitfn,W,H,2))

hsfn = RM.compose("hsfn",sfn,cr)

harness.axi( "2xov7660", hsfn, "2xov7660.raw", nil, nil, types.array2d(ITYPE,4), T,W,H, types.array2d(OTYPE,2),2,W,H)