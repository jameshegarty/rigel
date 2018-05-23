local R = require "rigel"
R.export()
local SOC = require "soc"
local harness = require "harnessSOC"
local RS = require "rigelSimple"
local C = require "examplescommon"
require "generators".export()
require "types".export()

local convPar = Module{ ar(ar(u(8),2,2),8),
function(inp)
  inp = Map{Map{Rshift{4}}}(inp)
  local coeff = c{{1,2,3,4},ar(u(8),2,2)}
  print("COEFF ",R.isIR(coeff))
  coeff = Broadcast{8}(coeff)
  local z = Zip(inp,coeff)
  local out = Map{Mul}(z)
  return Map{Reduce{Add}}(out)
end}

local conv = Module{ ar(u(8),2,2),
function(inp)
  inp = Map{Rshift{4}}(inp)
  local coeff = c{{1,2,3,4},ar(u(8),2,2)}
  print("COEFF ",R.isIR(coeff))
--  coeff = Broadcast{8}(coeff)
  local z = Zip(inp,coeff)
  local out = Map{Mul}(z)
  return Reduce{Add}(out)
end}

--local LBGEN = Linebuffer{{128,64},8,{1,0,1,0}}
--assert(R.isGenerator(LBGEN))

harness{
  SOC.readBurst("frame_128.raw",128,64,u(8),0),
--  RS.HS(C.cast(b(64),ar(u(8),8))),
  HS{Linebuffer{{128,64},0,{1,0,1,0}}},
  HS{conv},
--  RS.HS(C.cast(ar(u(8),8),b(64))),
  SOC.writeBurst("out/convgen",128,64,u(8),0)}
