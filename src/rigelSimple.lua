local R = require "rigel"
local types = require("types")
local RM = require "modules"
local C = require "examplescommon"
local harness = require "harness"
local fRS = require "fixed_float"
local S = require("systolic")
local SDFRate = require("sdfrate")
local fixed_new = require("fixed_new")
local J = require "common"
local err = J.err
local RST
if terralib~=nil then RST=require "rigelSimpleTerra" end

local RS = {}

local ccnt = 0

RS.uint8 = types.uint(8)
RS.int8 = types.int(8)
RS.uint32 = types.uint(32)
RS.int32 = types.int(32)
RS.uint16 = types.uint(16)
RS.float = types.float(32)
--RS.uint8[1] = types.array2d(RS.uint8,1)
--RS.uint8[25] = types.array2d(RS.uint8,25)
RS.input = R.input

function RS.array(t,x,y) return types.array2d(t,x,y) end
RS.array2d = RS.array
RS.tuple = types.tuple

RS.modules = {}
function RS.modules.pad(t)
  return RM.pad( t.type, t.size[1], t.size[2], t.pad[1], t.pad[2], t.pad[3], t.pad[4], t.value )
end

function RS.modules.padSeq(t)
  return RM.liftHandshake(RM.padSeq( t.type, t.size[1], t.size[2], t.V, t.pad[1], t.pad[2], t.pad[3], t.pad[4], t.value ))
end

function RS.modules.crop(t)
  return RM.crop( t.type, t.size[1], t.size[2], t.crop[1], t.crop[2], t.crop[3], t.crop[4])
end

function RS.modules.cropSeq(t)
  return C.cropHelperSeq( t.type, t.size[1], t.size[2], t.V, t.crop[1], t.crop[2], t.crop[3], t.crop[4] )
--  return RM.cropSeq( t.type, t.size[1], t.size[2], t.P, t.crop[1], t.crop[2], t.crop[3], t.crop[4] )
end

function RS.modules.changeRate(t)
  return RM.changeRate( t.type, t.H, t.inW, t.outW )
end

function RS.modules.vectorize(t)
  local H = t.H
  if H==nil then H=1 end
  return RM.changeRate( t.type, H, 1, t.V )
end

function RS.modules.devectorize(t)
  local H = t.H
  if H==nil then H=1 end
  return RM.changeRate( t.type, H, t.V, 1 )
end

function RS.modules.upsampleSeq(t)
  return C.upsampleSeq( t.type, t.size[1], t.size[2], t.V, t.scale[1], t.scale[2] )
end

function RS.modules.upsample(t)
  return RM.upsample( t.type, t.size[1], t.size[2], t.scale[1], t.scale[2] )
end

function RS.modules.downsampleSeq(t)
  return C.downsampleSeq( t.type, t.size[1], t.size[2], t.V, t.scale[1], t.scale[2] )
end

function RS.modules.downsample(t)
  return RM.downsample( t.type, t.size[1], t.size[2], t.scale[1], t.scale[2] )
end

function RS.modules.posSeq(t)
  return RM.posSeq(t.size[1],t.size[2],t.V)
end

function RS.modules.LUT(t)
  return RM.lut(t.type,t.outputType,t.values)
end

function RS.modules.linebuffer(t)
  local A = C.stencilLinebuffer( t.type, t.size[1], t.size[2], t.V, t.stencil[1], t.stencil[2], t.stencil[3], t.stencil[4] )
  local B = C.unpackStencil( t.type, -t.stencil[1]+1, -t.stencil[3]+1, t.V )
  ccnt = ccnt + 1
  return RM.makeHandshake(C.compose("v"..ccnt,B,A))
end

function RS.modules.columnLinebuffer(t)
  return RM.linebuffer(t.type,t.size[1],t.size[2],t.V,t.stencil)
end

function RS.modules.stencilShiftRegister(t)
  return RM.SSR( t.type, t.P, t.stencil[1], t.stencil[2] )
end

function RS.modules.SoAtoAoS(t)
  if t.size[2]==nil then t.size[2]=1 end
  return RM.SoAtoAoS( t.size[1], t.size[2], t.type )
end

function RS.modules.reduce(t)
  return RM.reduce( t.fn, t.size[1], t.size[2] )
end

function RS.modules.reduceSeq(t)
  err( type(t.V)=="number", "reduceSeq: V must be number ")
  return RM.reduceSeq( t.fn, 1/t.V )
end

function RS.modules.map(t)
  local X,Y
  if type(t.size)=="table" then X,Y = t.size[1],t.size[2] end
  if type(t.size)=="number" then X,Y = t.size,nil end

  return RM.map( t.fn, X,Y )
end

function RS.modules.sum(t)
  return C.sum(t.inType, t.inType, t.outType)
end

function RS.modules.sub(t)
  return C.sub(t.inType, t.inType, t.outType)
end

function RS.modules.rcp(t)
  return C.rcp(t.type)
end

function RS.modules.sumAsync(t)
  return C.sum( t.inType, t.inType, t.outType, true )
end


function RS.modules.serialize(t)
  return RM.serialize( t.type, t.inputRates, t.order )
end

function RS.modules.interleveOrder(t)
  return RM.interleveSchedule( t.streamCount, t.period )
end

function RS.modules.pyramidOrder(t)
  return RM.pyramidSchedule( t.depth, t.finestWidth, t.P)
end


local fixedSqrt = J.memoize(function(A)
  assert(types.isType(A))
  local inp = fRS.parameter("II",A)
  local out = inp:sqrt()
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toRigelModule("fixedSqrtRS")
                   end)

local fixedLift = J.memoize(function(A)
  assert(types.isType(A))
  local inp = fRS.parameter("IIlift",A)
  local out = inp:lift()
--  out = out:disablePipelining()
--  out = out:cast(A)
  return out:toRigelModule("fixedLiftRS_"..tostring(A):gsub('%W','_'))
                   end)


function RS.modules.sqrt(t)
  return C.compose("RSSQRT",fixedSqrt(t.outputType),fixedLift(t.inputType))
end

local sumPow2 = function(A,B,outputType)
  local partial = RM.lift( "RSsumpow2", types.tuple {A,B}, outputType, 0, 
    function(sinp)
      local sout = S.cast(S.index(sinp,0),outputType)+(S.cast(S.index(sinp,1),outputType)*S.cast(S.index(sinp,1),outputType))
      sout = sout:disablePipelining()
      return sout
    end,
    function() return RST.sumPow2(A,B,outputType) end )

  return partial
end

function RS.modules.sumPow2(t)
  return sumPow2(t.inType,t.inType,t.outType)
end

function RS.modules.mult(t)
  return C.multiply(t.inType, t.inType, t.outType)
end

function RS.modules.shiftAndCast(t)
  return C.shiftAndCast(t.inType, t.outType, t.shift)
end

function RS.modules.constSeq(t)
  local size = t.type:arrayLength()
  return RM.constSeq(t.value, t.type:arrayOver(), size[1], size[2], t.P )
end

function RS.modules.filterSeq(t)
  
  local rate
  if SDFRate.isFrac(t.rate) then
    rate=t.rate
  elseif type(t.rate)=="number" then
    rate = {1,1/t.rate}
    err( SDFRate.isFrac(rate),"rigelSimple filterSeq, rate did not convert to frac, "..tostring(t.rate))
  else
    err("rigelSimple filterSeq rate is invalid format")
  end
  
  return RM.filterSeq( t.type, t.size[1], t.size[2], rate, t.fifoSize, t.coerce )
end

function RS.modules.fifo(t)
  return C.fifo( t.type, t.size )
end

function RS.connect(t)
  err( R.isFunction(t.toModule), "RigelSimple.connect: toModule must be rigel module")
  
  local inp = t.input

  if t.input~=nil then
    if R.isHandshake(t.input.type) and R.isHandshake(t.toModule.inputType) then
      local btype = R.extractData(t.input.type)
      local itype = R.extractData(t.toModule.inputType)
      
      if btype==types.array2d(itype,1) then
        ccnt = ccnt + 1
        inp = R.apply( t.name or "v"..tostring(ccnt), RS.HS(C.index(btype,0)), inp )
      elseif types.array2d(btype,1)==itype then
        ccnt = ccnt + 1
        inp = R.apply( t.name or "v"..tostring(ccnt), RS.HS(C.arrayop(btype,1,1)), inp )
      end
    elseif R.isBasic(t.input.type) and R.isBasic(t.toModule.inputType) then
      if types.array2d(t.input.type,1)==t.toModule.inputType then
        ccnt = ccnt + 1
        inp = R.apply( t.name or "v"..tostring(ccnt), C.arrayop(t.input.type,1,1), inp )
      end
    end
  end

  ccnt = ccnt + 1
  return R.apply( t.name or "v"..tostring(ccnt), t.toModule, inp, t.util )
end

function RS.constant(t)
  ccnt = ccnt + 1
  return R.constant( "v"..tostring(ccnt), t.value, t.type )
end

function RS.concat(t)
  ccnt = ccnt + 1
  return R.concat( "v"..tostring(ccnt), t )
end

function RS.selectStream(t)
  ccnt = ccnt + 1
  return R.selectStream( "v"..tostring(ccnt), t.input, t.index )
end

function RS.fifoLoop(t)
  local ty = t.input.type
  assert( R.isHandshake(ty))
  ty = R.extractData(ty)

  t.fifoList.fifos = t.fifoList.fifos or {}
  t.fifoList.statements = t.fifoList.statements or {}

  ccnt = ccnt + 1
  return C.fifoLoop( t.fifoList.fifos, t.fifoList.statements, ty, t.input, t.depth, "v"..tostring(ccnt), false )
end

function RS.index(t)
  local ty=t.input.type
  
  if R.isHandshake(ty) then
    ty = R.extractData(ty)
    ccnt = ccnt + 1
    return R.apply("v"..tostring(ccnt), RM.makeHandshake(C.index(ty,t.key)), t.input )
  else
    ccnt = ccnt + 1
    return R.apply("v"..tostring(ccnt), C.index(ty,t.key), t.input )
  end
end


function RS.fanOut(t)
  local ty = t.input.type

  err( R.isHandshake(ty), "calling fanOut on a non handshake type "..tostring(t.input.type))
  ty = R.extractData(ty)
  ccnt = ccnt + 1
  local out = R.apply("v"..tostring(ccnt),RM.broadcastStream(ty,t.branches), t.input )
  
  local res = {}
  for i=1,t.branches do
    ccnt = ccnt + 1
    table.insert(res, R.selectStream("v"..tostring(ccnt), out, i-1) )
  end
  return unpack(res)
end

function RS.fanIn(t)
  local typelist = {}
  for _,v in ipairs(t) do
    local ty = v.type
    err( R.isHandshake(ty), "rigelSimple.fanIn: expected all inputs to be handshake")
    ty = R.extractData(ty)

    table.insert(typelist,ty)
  end
  
  ccnt = ccnt + 1
  ccnt = ccnt + 1
  return R.apply("v"..tostring(ccnt-1), RM.packTuple(typelist), R.concat("v"..tostring(ccnt),t) )
end

function RS.defineModule(t)
  ccnt = ccnt + 1
  local out = t.output
  local fifoList

  if t.fifoList~=nil then
    local stats = {t.output}
    for k,v in ipairs(t.fifoList.statements) do table.insert(stats,v) end
    out = R.statements(stats)
    fifoList = t.fifoList.fifos
  end

  return RM.lambda(t.name or "v"..tostring(ccnt), t.input, out, fifoList )
end

function RS.HS(t) 
  if types.isType(t) then
    return R.Handshake(t) 
  elseif R.isFunction(t) then
    --print("LIFT",t.name,t.kind,t.inputType,t.outputType)
    if R.isV(t.inputType) and R.isRV(t.outputType) then
      --print("LIFTHANDSHAKE")
      return RM.liftHandshake(t)
    elseif R.isHandshake(t.inputType) then
      --print("ISHANDSHAKE")
      return t
    elseif (R.isBasic(t.inputType) and R.isV(t.outputType)) or (t.outputType:isTuple() and #t.outputType.list>1 and t.outputType.list[2]:isBool()) then
      --print("LIFTDECIM")
      return RM.liftHandshake(RM.liftDecimate(t))
    elseif R.isBasic(t.inputType) and R.isBasic(t.outputType) then
      --print("MAKEHANDSHAKE")
      return RM.makeHandshake(t)
    else
      print(t.inputType, t.outputType)
      assert(false)
    end
  else
    assert(false)
  end
end

function RS.harness(t) return harness(t) end

function RS.modules.fwriteSeq(t)
  -- file write only support byte aligned, so make a wrapper that casts up
  if t.type:isBool() then
      -- special case: write out bools as 255 or 0 to make it easy to look @ the file
      local inp = RS.input(types.bool())
      local out = RS.connect{input=RS.concat{inp,RS.constant{value=255,type=RS.uint8},RS.constant{value=0,type=RS.uint8}}, toModule=C.select(RS.uint8)}
      local out = RS.connect{input=out,toModule=RM.fwriteSeq(t.filename,RS.uint8,t.filenameVerilog)}
      local out = RS.connect{input=RS.concat{out,RS.constant{value=255,type=RS.uint8}}, toModule=C.eq(RS.uint8)}
      return RS.defineModule{input=inp,output=out}
  elseif t.type:toCPUType()~=t.type then
    local inp = RS.input(t.type)

    local out, fwritetype

    local fwritetype = t.type:toCPUType()
    
    out = RS.connect{input=inp,toModule=C.cast(t.type,fwritetype)}
    out = RS.connect{input=out,toModule=RM.fwriteSeq(t.filename,fwritetype,t.filenameVerilog)}
    out = RS.connect{input=out,toModule=C.cast(fwritetype,t.type)}
    return RS.defineModule{input=inp,output=out}
  else
    return RM.fwriteSeq(t.filename,t.type,t.filenameVerilog)
  end
end

function RS.writePixels(input,id,imageSize,V)
  err(V==nil or V==1, "rigelSimple writePixels NYI: non unit vector widths "..tostring(V))
  
  --local IT = input:typecheck()
  --print("WRITEPX",IT.type)

  local TY
  if R.isHandshake(input.type) then
    TY = R.extractData(input.type)
  else
    TY = input.type
  end

--  local TYY = TY
--  if TY:isArray() then
--    TYY = TY:arrayOver()
--  end
    
  local mod = RS.modules.fwriteSeq{type=TY, filename="out/dbg_terra_"..id..".raw", filenameVerilog="out/dbg_verilog_"..id..".raw"}

--  if TY:isArray() then
--    mod = C.linearPipeline{C.index(TY,0),mod,C.arrayop(TYY,1)}
--  end
  
  if R.isHandshake(input.type) then
     mod = RS.HS(mod)
  end

  --
  local file = io.open("out/dbg_"..id..".metadata.lua","w")
  file:write("return {width="..tostring(imageSize[1])..",height="..tostring(imageSize[2])..",type='"..tostring(TY).."'}")
  file:close()
  --
  
  return RS.connect{input=input, toModule=mod}
end

function RS.modules.readMemory(t)
  return RM.readMemory(t.type)
end

function RS.modules.triggeredCounter(t)
  return RM.triggeredCounter(t.type, t.N)
end

function RS.modules.lift(t)
  ccnt = ccnt + 1
  return RM.lift("v"..tostring(ccnt), t.type, nil, nil, t.fn )
end

return RS
