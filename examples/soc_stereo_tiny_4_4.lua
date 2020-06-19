local G = require "generators.core"
local SOC = require "generators.soc"
local RM = require "generators.modules"
local T = require "types"
local R = require "rigel"
local SDF = require "sdf"
local Zynq = require "generators.zynq"
local harness = require "generators.harnessSOC"
local Uniform = require "uniform"
local J = require "common"

local AUTOFIFO = string.find(arg[0],"autofifo")
AUTOFIFO = (AUTOFIFO~=nil)

if AUTOFIFO then
  R.AUTO_FIFOS = true
  R.Z3_FIFOS = true
else
  R.AUTO_FIFOS = false
end

local test = string.sub(arg[0],12,15)

local first,flen = string.find(arg[0],"%d+")
local SW = tonumber(string.sub(arg[0],first,flen))
local invV = tonumber(string.sub(arg[0], string.find(arg[0],"%d+",flen+1)))

local OffsetX = 20 -- we search the range [-OffsetX-SearchWindow, -OffsetX]
local SADWidth = 8
local W,H, infile, SearchWindow
local THRESH = 0
if test=="tiny" then
  -- fast version for automated testing
  W,H = 128,16
  SearchWindow = 4
  infile = "stereo_tiny.raw"
elseif test=="medi" then
  W,H = 352,200
  SearchWindow = 64
  infile = "stereo_medi.raw"
elseif test=="full" then
  W, H = 720, 400
  SearchWindow = 64
  infile = "stereo0000.raw"
  THRESH = 1000
else
  print("UNKNOWN TEST "..test)
  assert(false)
end

assert(SW==SearchWindow)

local outfile = "soc_stereo_"..test.."_"..tostring(SearchWindow).."_"..tostring(invV)..J.sel(AUTOFIFO,"_autofifo","")
io.output("out/"..outfile..".design.txt"); io.write("Stereo "..SearchWindow.." "..SADWidth.."x"..SADWidth.." "..test); io.close()
io.output("out/"..outfile..".designT.txt"); io.write( invV/SearchWindow ); io.close()
io.output("out/"..outfile..".dataset.txt"); io.write("SIG20_zu9"..J.sel(AUTOFIFO,"_autofifo","")); io.close()

local cycles = ((W+OffsetX+SearchWindow)*(H+7))*(SearchWindow/invV)
print("CYCLES",cycles)

local regs = SOC.axiRegs({},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

local DisplayOutput = G.SchedulableFunction{ "DisplayOutput", T.Tuple{T.Uint(8),T.Uint(16)},
  function(i)
    if THRESH>0 then
      local th = G.Const{T.Uint(16),THRESH}(G.ValueToTrigger(i))
      local zero = G.Const{T.Uint(8),0}(G.ValueToTrigger(i))
      return G.Sel( G.GT(i[1],th), zero, i[0])
    else
      return i[0] -- don't filter
    end
  end}

local FindBestMatch = G.SchedulableFunction{ "FindBestMatch", T.Array2d( T.Array2d( T.Array2d(T.Uint(8),2), SADWidth, SADWidth ), SearchWindow ),
  function(i)
    local inp = G.FanOut{2}(i):setName("FindBestInpFanOut")

    local inp0, inp1 = (inp[0]):setName("inp0"), (inp[1]):setName("inp1")
    
    local idx = {} -- build indices for the argmin
    for i=1,SearchWindow do
      -- index gives us the distance to the right hand side of the window
      idx[i] = SearchWindow+OffsetX-(i-1)
    end

    local indices = G.Const{T.Array2d(T.U(8),SearchWindow),value=idx}(G.ValueToTrigger(inp0):setName("valueToTrigger")):setName("indices")
    local SADOut = G.Map{G.SAD{T.Uint(16)}}(inp1):setName("SADOut")

    indices = G.NAUTOFIFO{128}(indices)
    SADOut = G.NAUTOFIFO{128}(SADOut)
    local argminInp = G.Zip(G.FanIn(indices,SADOut):setName("fanIn")) --{u8,u16}[SearchWindow]

    local res = G.Reduce{G.ArgMin}(argminInp)

    return res
  end}

local StereoModule = G.SchedulableFunction{ "StereoModule", T.Trigger,
  function(i)
    local readStream = G.AXIReadBurst{ infile, {W,H}, T.Tuple{T.Uint(8),T.Uint(8)}, 4, noc.read }(i)
    local inp = G.Pad{{OffsetX+SearchWindow,0,3,4}}(readStream)

    inp = G.FanOut{2}(inp)

    local left = G.Map{G.Index{0}}(inp[0])
    left = G.NAUTOFIFO{128,"left"}(left)
    left = G.StencilOfStencils{{-(SearchWindow+SADWidth+OffsetX)+2,-(OffsetX), -SADWidth+1, 0},{SADWidth,SADWidth}}(left)

    local right = G.Map{G.Index{1}}(inp[1])
    right = G.NAUTOFIFO{128,"right"}(right)

    -- override the default rate of this stencil op to 100%:
    -- input rate is actually 25%, but since we are broadcasting after,
    -- if we throughput reduce the stencil, it will actually lead to double buffering
    right = G.Stencil{{-SADWidth+1,0,-SADWidth+1,0},SDF{1,1}}(right)

    right = G.Map{G.Broadcast{{SearchWindow,1}}}(right)
    
    local merged = G.Zip(G.FanIn(left,right)) -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]}[SearchWindow]
    merged = G.Map{G.Zip}(merged)
    merged = G.Map{G.Map{G.ZipToArray}}(merged) -- {A,A}[SADWidth, SADWidth][SearchWindow]
    
    local min = G.Map{FindBestMatch}(merged) -- do the stereo match!
    min = G.NAUTOFIFO{128,"FindBestMatch"}(min)
    local res = G.Map{DisplayOutput}(min)
    res = G.Crop{{ OffsetX+SearchWindow, 0, SADWidth-1, 0 }}(res)
    
    return G.AXIWriteBurst{"out/"..outfile,noc.write}(res)
  end}

local SM = StereoModule:complete({type=T.Trigger,rate=SDF{1,cycles}})

print("EXPECTED CYCLES:", Uniform(SM.sdfInput[1][2]/SM.sdfInput[1][1]):toNumber()+SM.delay)
harness({regs.start, SM, regs.done},nil,{regs})
