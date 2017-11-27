local R = require "rigelSimple"
local f = require "fixed_new"
local types = require "types"


local configs = {}

configs.addConst = ( f.parameter("inp",types.uint(8)):addMSBs(2) + f.constant(528) )
-----------------------------
local inp = f.parameter("inp",types.uint(8))
configs.tuple = f.tuple{ inp }
----------------------------
local inp = f.parameter("inp",types.uint(8))
local tp  = f.tuple{ inp, inp }
configs.tupleidx = tp:index(1)
-------------------
local inp = f.parameter("inp",types.uint(8))
local tp  = f.array2d({ inp, inp, inp, inp },2,2)
configs.arrayidx = tp:index(1,1)
-------------------
local inp = f.parameter("inp",types.uint(8))
configs.writepx = ( inp:lshift(3):writePixel("writePixelTest",{64,32}) )
-------------------
local inp = f.parameter("inp",types.uint(8))
configs.writepxshift = inp:toSigned():lshift(3):writePixel("writePixelShiftTest",{64,32}):addLSBs(3)
-------------------
local inp = f.parameter("inp",types.uint(8))
configs.gt = inp:gt(f.constant(200)):writePixel("gt",{64,32})
-------------------
local inp = f.parameter("inp",types.uint(8))
configs.removelsbs = inp:removeLSBs(4):writePixel("removelsbs",{64,32})
-------------------
local inp = f.parameter("inp",types.uint(8))
configs.removemsbs = inp:removeMSBs(4):writePixel("removemsbs",{64,32})
-------------------

for k,v in pairs(configs) do
  print("do config",k)
  
  local mod = R.HS(v:toRigelModule(k))

  local inputImageSize={64,32}
  local outputImageSize={64,32}

  local targets = {"verilog","terra","metadata"}
  
  for _,bk in pairs(targets) do
    R.harness{ outFile="fixed_test"..k, fn=mod, inFile="../examples/frame_64.raw", inSize=inputImageSize, outSize=outputImageSize, backend=bk }
  end
end

file = io.open("out/fixedtest.compiles.txt", "w")
file:write("Hello World")
file:close()
