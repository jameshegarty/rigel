local f = require "fixed"
local R = require "rigel"
local types = require "types"
local RM = require "modules"
local S = require "systolic"
local modules = require "fpgamodules"
local C = require "examplescommon"
local CC = {}

local campipeCoreTerra
if terralib~=nil then campipeCoreTerra=require("campipe_core_terra") end

function CC.blackLevel( pedestal )
  local blackLevelInput = f.parameter("blInput",types.uint(8))
  local bli = blackLevelInput:lift(0)
  local res = 128*(255/(255-pedestal))
  res = math.floor(res)
  --print("RESCALE",res)
  local rescale = f.constant(res,false,8,-7)
  local out = (bli:toSigned()-f.constant(pedestal,false,8,0):toSigned())*rescale:toSigned()
  out = out:abs():denormalize()
  local a = f.constant(255,false,out:precision(),0)
  --print(a.type,out.type)
  out = f.select(out:gt(f.constant(255,false,8)),a,out)
  return out:truncate(8):lower():toRigelModule("blackLevel")
end

function CC.demosaic(internalW,internalH,internalT,DEMOSAIC_W,DEMOSAIC_H,DEMOSAIC_R,DEMOSAIC_G,DEMOSAIC_B)
  assert(type(internalW)=="number")
  assert(type(internalH)=="number")
  assert(type(internalT)=="number")

  assert(type(DEMOSAIC_W)=="number")
  assert(type(DEMOSAIC_H)=="number")
  assert(type(DEMOSAIC_R)=="table")
  assert(type(DEMOSAIC_G)=="table")
  assert(type(DEMOSAIC_B)=="table")

  -- BG
  -- GR

  local kerns = { DEMOSAIC_R, DEMOSAIC_G, DEMOSAIC_B }

  -----------
  local function KSI(tab,name,phaseX,phaseY)
    local ITYPE = types.tuple{types.uint(16),types.uint(16)}

    local ATYPE = types.array2d(types.uint(8),DEMOSAIC_W,DEMOSAIC_H)

    return RM.lift(name, ITYPE, ATYPE, 5,
      function(kernelSelectInput)
        local x = S.cast(S.index(kernelSelectInput,0),types.uint(16)) + S.constant(phaseX,types.uint(16))
        x = S.__and(x,S.constant(1,types.uint(16)))
        local y = S.cast(S.index(kernelSelectInput,1),types.uint(16)) + S.constant(phaseY,types.uint(16))
        y = S.__and(y,S.constant(1,types.uint(16)))
        local phase = x+(y*S.constant(2,types.uint(16)))
        
        local tt = {}

        for k,v in ipairs(tab) do table.insert(tt,S.constant(v,ATYPE)) end
        local kernelSelectOut = modules.wideMux( tt, phase )
        return kernelSelectOut
      end, 
      function() return campipeCoreTerra.demosaic(DEMOSAIC_W,DEMOSAIC_H,phaseX,phaseY,tab) end)
  end
  -----------

  local XYTYPE = types.tuple{types.uint(16),types.uint(16)}
  local DTYPE = types.tuple{XYTYPE,types.array2d(types.uint(8),DEMOSAIC_W,DEMOSAIC_H)}
  local deminp = R.input(DTYPE)
  local xy = R.apply("xy",C.index(DTYPE,0),deminp)
  local st = R.apply("dat",C.index(DTYPE,1),deminp)

  local out = {}
  for i=1,3 do
    local kern = R.apply("k"..i,KSI(kerns[i],"kern"..i,phaseX,phaseY),xy)

    --local ConvWidth = 3
    local A = types.uint(8)
    local packed = R.apply( "packedtup"..i, C.SoAtoAoS(DEMOSAIC_W,DEMOSAIC_H,{A,A}), R.concat("ptup"..i, {st,kern}) )
    local conv = R.apply( "partialll"..i, RM.map( C.multiply(A,A,types.uint(16)), DEMOSAIC_W, DEMOSAIC_H ), packed )
    local conv = R.apply( "sum"..i, RM.reduce( C.sum(types.uint(16),types.uint(16),types.uint(16)), DEMOSAIC_W, DEMOSAIC_H ), conv )
    local conv = R.apply( "touint8"..i, C.shiftAndCastSaturate( types.uint(16), A, 2 ), conv )

    out[i] = conv
  end

  local dem = RM.lambda("dem", deminp, R.concatArray2d("ot",out,3))
  dem = RM.liftXYSeqPointwise("dem","dem",dem,internalW,internalH,internalT)

  ---------------
  local demtop = R.input(types.array2d(types.uint(8),internalT))
  local st = R.apply( "st", C.stencilLinebuffer(types.uint(8),internalW,internalH,internalT,-DEMOSAIC_W+1,0,-DEMOSAIC_H+1,0), demtop)
  local st = R.apply( "convstencils", C.unpackStencil( types.uint(8), DEMOSAIC_W, DEMOSAIC_H, internalT ) , st )
  local demtopout = R.apply("dem",dem,st)

  return RM.lambda("demtop",demtop,demtopout)
end

function CC.makeCCM(tab)
  local ccminp = f.parameter("ccminp",types.array2d(types.uint(8),3))
  local out = {}
  for c=1,3 do
    out[c] = f.constant(math.floor(tab[c][1]*128),false,8,-7)*ccminp:index(0):lift(0)
    for i=2,3 do
      out[c] = out[c] + f.constant(math.floor(tab[c][i]*128),false,8,-7)*ccminp:index(i-1):lift(0)
    end
    out[c] = out[c]:denormalize()
    local a = f.constant(255,false,out[c]:precision(),0)
    out[c] = f.select(out[c]:gt(f.constant(255,false,8)),a,out[c])
    out[c] = out[c]:truncate(8):lower()
  end

  local res = f.array2d(out,3)
  return res:toRigelModule("ccm")
end

function CC.addchan()
  local inp = f.parameter("inp",types.array2d(types.uint(8),3))
  local out={}
  for c=0,2 do
    out[c] = inp:index(c)
  end
  out[3] = f.plainconstant(0,types.uint(8))
  return f.array2d(out,4):toRigelModule("addChan")
end

function CC.makeGamma(g)
  local gamma = {}
  for i=0,255 do
    local v= math.pow(i/255,g)*255
    table.insert(gamma, math.floor(v))
  end
  return gamma
end

-- pad 3x3 to 5x5
function CC.kernelPad(t)
  local out = {}
  for y=0,2 do
    for x=0,6 do
      if x>=2 and x<=4 then
        table.insert(out,t[y*3+(x-2)+1])
      else
        table.insert(out,0)
      end
    end
  end

  return out
end

function CC.shiftKernel(t,W,H,xs,ys)
  --for k,v in ipairs(t) do print(v) end

  local out = {}
  for y=0,H-1 do
    for x=0,W-1 do
      local rx = (x+xs)%W
      local ry = (y+ys)%H
      table.insert(out, t[ry*W+rx+1])
    end
  end

  --for k,v in ipairs(out) do print("OUT",v) end
  return out
end

local R = require "rigel"
local RM = require "modules"

rigelInput = R.input

rigelPipeline = function(tab)
  return RM.lambda("campipe", tab.input, tab.output)
end

local conc = 1
function connect(tab)
  conc = conc+1
  return R.apply("autoconnect"..tostring(conc), tab.tomodule, tab.input)
end

local types=require("types")
grayscale_uint8 = types.array2d(types.uint(8),2)

return CC
