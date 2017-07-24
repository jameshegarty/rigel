require "rigelhll".export()

local W,H = 128,64

function top(inp)
  inp.name="INP"
  local N = 4
  local pos = HS(posSeq{size={W,H},V=1})()
  pos.name="POSSEQ"
  pos.sdfRateOverride={{1,1}}
  print("POSDONE")
  local start = liftMath(function(x) return x:index(1):index(0):index(0):removeMSBs(8) end)(inp,pos)
  start.name="START"
  print("LIFTDONE",start.type)
  local tc = triggeredCounter(N)(start)
  tc.name="TC"
  return tc
--  return start
end


harness{ inFile="frame_128.raw", outFile="triggeredCounter", fn=top, inSize={W,H}, outSize={W*4,H}, type=HS(array2d(u8,1)), sdfInputRate={{1,1}}}
