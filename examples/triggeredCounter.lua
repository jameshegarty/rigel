local RHLL = require "rigelhll"
RHLL.importt()

local W,H = 128,64

function top(inp)
  local N = 4
  local pos = HS(posSeq{size={W/N,H},V=1})()
  print("POSDONE")
  local start = liftMath(function(x) return x:index(1):index(0):index(0) end)(inp,pos)
  print("LIFTDONE")
  return triggeredCounter(N)(start)
--  return start
end


harness{ inFile="frame_128.raw", outFile="triggeredCounter", fn=top, inSize={W,H}, outSize={W,H}, inType=HS(uint8), sdfInputRate={{1,4}}}
