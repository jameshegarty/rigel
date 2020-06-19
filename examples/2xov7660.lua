local RM = require "generators.modules"
local C = require "generators.examplescommon"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"

W = 640
H = 480
T = 4

local ITYPE = types.array2d(types.uint(8),2)
local OTYPE = types.array2d(types.uint(8),4) -- RGB

local SPLIT_TYPE = types.tuple{types.tuple{types.uint(16),types.uint(16)}, ITYPE}
--inp = S.parameter("inp",SPLIT_TYPE)


local tfn
if terralib~=nil then
  local ovt = require("2xov7660_terra")
  tfn = ovt(SPLIT_TYPE,OTYPE)
end

splitfn = RM.lift( "split", SPLIT_TYPE, OTYPE , 0, 
  function(inp) 
local sout = S.select(S.lt(S.index(S.index(inp,0),0),S.constant(320,types.uint(16))),S.index(S.index(inp,1),0),S.index(S.index(inp,1),1))
sout = S.tuple{sout,sout,sout,S.constant(0,types.uint(8))}
sout = S.cast(sout,OTYPE)
return sout end, function() return tfn end )

cr = RM.changeRate(ITYPE,1,4,2)
sfn = RM.makeHandshake(RM.liftXYSeqPointwise("splitfn","split",splitfn,W,H,2))

hsfn = C.compose("hsfn",sfn,cr)

harness{ outFile="2xov7660", fn=hsfn, inFile="2xov7660.raw", inSize={W,H}, outSize={W,H} }
