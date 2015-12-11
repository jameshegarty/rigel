local f = require "fixed"
local d = require "darkroom"
local modules = require "fpgamodules"
local C = require "examplescommon"
local CC = {}

function CC.blackLevel( pedestal )
  local blackLevelInput = f.parameter("blInput",types.uint(8))
  local bli = blackLevelInput:lift(0)
  local res = 128*(255/(255-pedestal))
  res = math.floor(res)
  print("RESCALE",res)
  local rescale = f.constant(res,false,8,-7)
  local out = (bli:toSigned()-f.constant(pedestal,false,8,0):toSigned())*rescale:toSigned()
  out = out:abs():denormalize()
  local a = f.constant(255,false,out:precision(),0)
  print(a.type,out.type)
  out = f.select(out:gt(f.constant(255,false,8)),a,out)
  return out:truncate(8):lower():toDarkroom("blackLevel")
end

function CC.demosaic(internalW,internalH,DEMOSAIC_W,DEMOSAIC_H,DEMOSAIC_R,DEMOSAIC_G,DEMOSAIC_B)
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
    local kernelSelectInput = S.parameter("ksi",ITYPE)

    local x = S.cast(S.index(kernelSelectInput,0),types.uint(16)) + S.constant(phaseX,types.uint(16))
    x = S.__and(x,S.constant(1,types.uint(16)))
    local y = S.cast(S.index(kernelSelectInput,1),types.uint(16)) + S.constant(phaseY,types.uint(16))
    y = S.__and(y,S.constant(1,types.uint(16)))
    local phase = x+(y*S.constant(2,types.uint(16)))

    local tt = {}
    local ATYPE = types.array2d(types.uint(8),DEMOSAIC_W,DEMOSAIC_H)
    for k,v in ipairs(tab) do table.insert(tt,S.constant(v,ATYPE)) end
    local kernelSelectOut = modules.wideMux( tt, phase )
    return darkroom.lift(name, ITYPE, ATYPE, 5,
                         terra(inp:&tuple(uint16,uint16),out:&uint8[DEMOSAIC_W*DEMOSAIC_H])
                           var x,y = inp._0,inp._1
                           var phase = ((x+phaseX)%2)+((y+phaseY)%2)*2
                           var ot : int32[DEMOSAIC_W*DEMOSAIC_H]
                           if phase==0 then ot = array([tab[1]])
                           elseif phase==1 then ot = array([tab[2]])
                           elseif phase==2 then ot = array([tab[3]])
                           else ot = array([tab[4]]) end
                           for i=0,DEMOSAIC_W*DEMOSAIC_H do (@out)[i] = ot[i] end
                         end, kernelSelectInput, kernelSelectOut)
  end
  -----------

  local XYTYPE = types.tuple{types.uint(16),types.uint(16)}
  local DTYPE = types.tuple{XYTYPE,types.array2d(types.uint(8),DEMOSAIC_W,DEMOSAIC_H)}
  local deminp = d.input(DTYPE)
  local xy = d.apply("xy",d.index(DTYPE,0),deminp)
  local st = d.apply("dat",d.index(DTYPE,1),deminp)

  local out = {}
  for i=1,3 do
    local kern = d.apply("k"..i,KSI(kerns[i],"kern"..i,phaseX,phaseY),xy)

    --local ConvWidth = 3
    local A = types.uint(8)
    local packed = d.apply( "packedtup"..i, d.SoAtoAoS(DEMOSAIC_W,DEMOSAIC_H,{A,A}), d.tuple("ptup"..i, {st,kern}) )
    local conv = d.apply( "partialll"..i, d.map( C.multiply(A,A,types.uint(16)), DEMOSAIC_W, DEMOSAIC_H ), packed )
    local conv = d.apply( "sum"..i, d.reduce( C.sum(types.uint(16),types.uint(16),types.uint(16)), DEMOSAIC_W, DEMOSAIC_H ), conv )
    local conv = d.apply( "touint8"..i, C.shiftAndCastSaturate( types.uint(16), A, 2 ), conv )

    out[i] = conv
  end

  local dem = d.lambda("dem", deminp, d.array2d("ot",out,3))
  dem = darkroom.liftXYSeqPointwise(dem,internalW,internalH,T)

  ---------------
  local demtop = d.input(types.array2d(types.uint(8),T))
  local st = d.apply( "st", d.stencilLinebuffer(types.uint(8),internalW,internalH,T,-DEMOSAIC_W+1,0,-DEMOSAIC_H+1,0), demtop)
  local st = d.apply( "convstencils", d.unpackStencil( types.uint(8), DEMOSAIC_W, DEMOSAIC_H, T ) , st )
  local demtopout = d.apply("dem",dem,st)

  return d.lambda("demtop",demtop,demtopout)
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
  return res:toDarkroom("ccm")
end

function CC.addchan()
  local inp = f.parameter("inp",types.array2d(types.uint(8),3))
  local out={}
  for c=0,2 do
    out[c] = inp:index(c)
  end
  out[3] = f.plainconstant(0,types.uint(8))
  return f.array2d(out,4):toDarkroom("addChan")
end

function CC.makeGamma(g)
  local gamma = {}
  for i=0,255 do table.insert(gamma, math.pow(i/255,g)*255) end
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
  for k,v in ipairs(t) do print(v) end

  local out = {}
  for y=0,H-1 do
    for x=0,W-1 do
      local rx = (x+xs)%W
      local ry = (y+ys)%H
      table.insert(out, t[ry*W+rx+1])
    end
  end

  for k,v in ipairs(out) do print("OUT",v) end
  return out
end

return CC