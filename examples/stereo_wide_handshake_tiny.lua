local C = require "generators.examplescommon"
local harness = require "generators.harness"
local types = require "types"
local makeStereo = require "stereo_core"
require "common".export()

--local SADRadius = 4
local SADWidth = 8
--local SearchWindow = 64
local OffsetX = 20 -- we search the range [-OffsetX-SearchWindow, -OffsetX]
local A = types.uint(8)

local NOSTALL = string.find(arg[0],"nostall")
NOSTALL = (NOSTALL~=nil)


function make(filename)
  -- input is in the format A[2]. [left,right]. We need to break this up into 2 separate streams,
  -- linebuffer them differently, then put them back together and run argmin on them.
  -- 'left' means that the objects we're searching for are to the left of things in channel 'right', IN IMAGE SPACE.
  -- we only search to the left.

  -- full size is 720x405
  local W = 360
  local H = 203
  local SearchWindow = 64

  local infile
  local THRESH = 0
  if filename=="tiny" then
    -- fast version for automated testing
    W,H = 128,16
    SearchWindow = 4
    infile = "stereo_tiny.raw"
  elseif filename=="medi" then
    W,H = 352,200
    SearchWindow = 64
    infile = "stereo_medi.raw"
  elseif filename=="full" then
    W,H = 720,400
    SearchWindow = 64
    infile = "stereo0000.raw"
    THRESH = 1000
  else
    print("UNKNOWN FILENAME "..filename)
    assert(false)
  end

  local hsfn = makeStereo(W,H,OffsetX,SearchWindow,SADWidth,NOSTALL,THRESH)

--  local OUT_TYPE = types.array2d(types.tuple{types.uint(8),types.uint(16)},4)
  local ITYPE = types.array2d(types.array2d(types.uint(8),2),4)
  local OUT_TYPE = types.array2d(types.uint(8),8)
  -- output rate is half input rate, b/c we remove one channel.
  local outfile = "stereo_wide_handshake_"..sel(NOSTALL,"nostall_","")..filename

  harness{ inFile=infile, outFile=outfile, fn=hsfn, inSize={W,H}, outSize={W,H} }

  io.output("out/"..outfile..".design.txt"); io.write("Stereo "..SearchWindow.." "..SADWidth.."x"..SADWidth.." "..filename); io.close()
  io.output("out/"..outfile..".designT.txt"); io.write(1); io.close()
end

make(string.sub(arg[0],#arg[0]-7,#arg[0]-4))
