d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
C = require "examplescommon"
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"

if string.find(arg[0],"float") then
  f = require "fixed_float"
else
  f = require "fixed"
  if string.find(arg[0],"axi") then
    -- don't use this multiplier in simulator - too slow!
    f.DEEP_MULTIPLY = true
  end
end

function makeLK(T,window)
  assert(T<=4)

  local W = 64
  local H = 64

  if window==6 then
    W,H = 128,128
  elseif window==12 then
    W,H = 1920,1080
  end
  
--T = 8

-- lk_full is 584x388, 2 channel

--local window = 4

--local T = 4
  local RW_TYPE = types.array2d(types.array2d(types.uint(8),2),4)


  require "lk_core"

  local bits = {
    inv22={15,26,0},
    inv22inp={5,5,0}, -- NOTICE THIS IS DIFFERENT THAN WINDOW=6 VERSION
    d={0,0,0},
    Apartial={0,0,0},
    Bpartial={0,0,0},
    solve={0,0,0}
  }

  if window==6 then
    bits.inv22inp={0,10,0}
  elseif window==12 then
    bits.inv22inp={0,10,0}
  end

  local inputFilename = "trivial_64.raw"
  if window==6 then
    inputFilename = "trivial_128.raw"
  elseif window==12 then
    inputFilename = "packed_v0000.raw"
  end

  local externalT = 4

  if f.FLOAT then
    harness.terraOnly( "lk_wide_handshake_"..tostring(window).."_"..tostring(T).."_float", LKTop(T,W,H,window,bits), inputFilename, nil, nil, RW_TYPE, externalT,W,H, RW_TYPE,externalT,W,H)
  else
    local outfile = "lk_wide_handshake_"..tostring(window).."_"..tostring(T)..sel(f.DEEP_MULTIPLY,"_axi","")
    harness.axi( outfile, LKTop(T,W,H,window,bits), inputFilename, nil, nil, RW_TYPE,externalT,W,H, RW_TYPE,externalT,W,H)
    
    io.output("out/"..outfile..".design.txt"); io.write("Lucas Kanade "..window.."x"..window); io.close()
    io.output("out/"..outfile..".designT.txt"); io.write(T); io.close()
  end
end

local first,flen = string.find(arg[0],"%d+")
local convwidth = string.sub(arg[0],first,flen)
local t = string.sub(arg[0], string.find(arg[0],"%d+",flen+1))
print("Width",convwidth,"T",t)

makeLK(tonumber(t),tonumber(convwidth))
