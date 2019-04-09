local types = require "types"
local C = require "examplescommon"
local R = require "rigel"
import "state"

state counter(I:types.uint(32),O:types.uint(32))
--1
--  while R.c(true) do
  while C.GTConst(types.uint(32),16)(I) do
    if C.eq(types.uint(32))(I,R.c(0,types.u32)) then
      yield R.c(255,types.u32) --2

      --while R.c(true) do [R.c(128,types.u32)] end
      
      if R.c("mytrue",true,types.bool()) then
        yield R.c(128,types.u32) --3
      else
        yield R.c(64,types.u32) --4 
      end
    else
      yield R.c(0,types.u32) --5
    end
  end
end

print("COUNTER",counter)

print("counter",counter:toVerilog())
