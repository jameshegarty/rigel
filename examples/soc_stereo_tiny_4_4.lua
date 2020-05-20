local G = require "generators.core"
local SOC = require "generators.soc"
local T = require "types"
local R = require "rigel"
local SDF = require "sdf"
local Zynq = require "generators.zynq"
local harness = require "generators.harnessSOC"

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

local outfile = "soc_stereo_"..test.."_"..tostring(SearchWindow).."_"..tostring(invV)
io.output("out/"..outfile..".design.txt"); io.write("Stereo "..SearchWindow.." "..SADWidth.."x"..SADWidth.." "..test); io.close()
io.output("out/"..outfile..".designT.txt"); io.write( invV/SearchWindow ); io.close()
io.output("out/"..outfile..".dataset.txt"); io.write("SIG20_zu9"); io.close()

local cycles = ((W+OffsetX+SearchWindow)*(H+7)*SearchWindow)/invV
print("CYCLES",cycles)

local regs = SOC.axiRegs({},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

local DisplayOutput = G.SchedulableFunction{ "DisplayOutput", T.Tuple{T.Uint(8),T.Uint(16)},
  function(i)
    if THRESH>0 then
      local th = G.Const{T.Uint(16),THRESH}(G.ValueToTrigger(i))
      local zero = G.Const{T.Uint(8),0}(G.ValueToTrigger(i))
--      return G.Sel( G.GT(i[1],R.constant(THRESH,T.Uint(16))), R.Constant(0,T.Uint(8)), i[0])
      return G.Sel( G.GT(i[1],th), zero, i[0])
    else
      return i[0] -- don't filter
    end
  end}

local FindBestMatch = G.SchedulableFunction{ "FindBestMatch", T.Array2d( T.Array2d( T.Array2d(T.Uint(8),2), SADWidth, SADWidth ), SearchWindow ),
  function(i)

    local inp = G.FanOut{2}(i)

    print("BEST",inp.type)
    local idx = {} -- build indices for the argmin
    for i=1,SearchWindow do
      -- index gives us the distance to the right hand side of the window
      idx[i] = SearchWindow+OffsetX-(i-1)
    end

    local indices = G.Const{T.Array2d(T.U(8),SearchWindow),value=idx}(G.ValueToTrigger(inp[0]))
    print("IDX",indices.type)
    --local casted = G.Map{G.Map{G.Map{G.AddMSBs{8}}}}(inp[1])
    local SADOut = G.Map{G.SAD{T.Uint(16)}}(inp[1])
    print("SAD",SADOut.type)
    local argminInp = G.Zip(G.FanIn(indices,SADOut)) --{u8,u16}[SearchWindow]
    print("ARGMININP",argminInp.type)
    local res = G.Reduce{G.ArgMin}(argminInp)
    print("RES",res.type)
    return res
  end}

local StereoModule = G.SchedulableFunction{ "StereoModule", T.Trigger,
  function(i)
    print("STEREO",i.type,i.rate)
    local readStream = G.AXIReadBurst{ infile, {W,H}, T.Array2d(T.Uint(8),2), 4, noc.read }(i)
    local inp = G.Pad{{OffsetX+SearchWindow,0,3,4}}(readStream)
    print("INP",inp.type,inp.rate)
    inp = G.FanOut{2}(inp)

    print("A",inp.type,inp.rate)
    ----
    local left = G.Map{G.Index{0}}(inp[0])
    print("L",left.type)
    left = G.StencilOfStencils{{-(SearchWindow+SADWidth+OffsetX)+2,-(OffsetX), -SADWidth+1, 0},{SADWidth,SADWidth}}(left)
    print("L",left.type)
    ----
    local right = G.Map{G.Index{1}}(inp[1])
    print("R",right.type, right.rate)
    right = G.Stencil{{-SADWidth+1,0,-SADWidth+1,0}}(right)
    print("R",right.type, right.rate)
    right = G.Map{G.Broadcast{{SearchWindow,1}}}(right)
    print("R",right.type)
    ---
--    local mergei = R.concat{left,right}
    --    print("MERI",mergei.type)
    left = G.FIFO{128}(left)
    right = G.FIFO{128}(right)
    
    local merged = G.Zip(G.FanIn(left,right)) -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]}[SearchWindow]
    print("MERGG",merged.type)
    merged = G.Map{G.Zip}(merged)
    print("MERGG",merged.type)
    merged = G.Map{G.Map{G.ZipToArray}}(merged) -- {A,A}[SADWidth, SADWidth][SearchWindow]
    print("MERGG",merged.type)
    
    print("MERG",merged.type)
    local min = G.Map{FindBestMatch}(merged) -- do the stereo match!
    local res = G.Map{DisplayOutput}(min)
    res = G.Crop{{ OffsetX+SearchWindow, 0, SADWidth-1, 0 }}(res)
    
    return G.AXIWriteBurst{"out/soc_stereo_"..test.."_"..tostring(SearchWindow).."_"..tostring(invV),noc.write}(res)
  end}

harness({regs.start, StereoModule, regs.done},nil,{regs})
