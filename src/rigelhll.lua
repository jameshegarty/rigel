local RHLL = {}
local R = require "rigel"
local C = require "examplescommon"
local RS = require "rigelSimple"
local llharness = require "harness"
local fixed_new = require("fixed_new")
local types = require("types")
local SDFRate = require "sdfrate"
local J = require "common"
local S = require "systolic"
local err = J.err

local function devec(t)
  for k,v in pairs(t) do
    if v.vectorized then
      err(v.type:channels()==1,"NYI - concat of vectors > 1")
      t[k] = v:index(0)
    end
  end
  return t
end

RHLL.fanIn =function(t) return RS.fanIn(devec(t)) end
RHLL.fanOut = RS.fanOut
RHLL.concat = function(t) return RS.concat(devec(t)) end

-- a metatable that provides a __call function with some auto converstions for making it easier to connect to modules
-- tab.fn: fn to call to generate the module. Will send a table of 'tab.settings' concated with type
-- tab.wireFn(arg): an optional function that takes in a rigel value as input and returns additional settings
-- tab.settings: settings to send to fn
-- tab.forceHandshake: this module is static, but force it to become HS when we wire it. Useful for nullary modules, lambdas
-- tab.vectorized: is this module vectorized? ie, wraps input/output in an array of N. Track this as aux data in the rigel IR ("vectorized") and apply correct wrappers
local SimpleModuleWrapperMT={__call=function(...)

  local args = {...}
  local tab = args[1]

  for i=2,#args do
    err( R.isIR(args[i]), "argument "..tostring(i-2).." to module must be rigel value, but is "..tostring(args[i]))
  end
  
  local settings

  if tab.settings==nil then
    settings = {}
  else
    settings = J.shallowCopy(tab.settings)
  end
  
  local arg
  if #args==1 then
  elseif #args==2 then
    arg = args[2]
  elseif #args>2 then
    local argtab = {}
    for i=2,#args do
      assert( R.isHandshake(args[2].type)==R.isHandshake(args[3].type) )
      table.insert(argtab, args[i] )
    end

    if R.isHandshake(args[2].type) then
      arg = RHLL.fanIn(argtab)
    else
      arg = RHLL.concat(argtab)
    end
  else
    assert(false)
  end
  
  if tab.wireFn~=nil then
    local set2 = tab.wireFn(arg)
    for k,v in pairs(set2) do
      err(settings[k]==nil, "SimpleModuleWrapper: "..k.." was already set!")
      settings[k] = v
    end
  elseif #args>1 then
    err(settings.type==nil, "SimpleModuleWrapper: type was already set!")
    --settings.type = R.extractData(arg.type)
    settings.type = arg.type
  end

  if tab.vectorized~=nil then
    err( settings.V==nil, "simpleModuleWrapper: V was already set on vectorized module")
    if arg.vectorized then
      local ty = R.extractData(arg.type)
      settings.V = ty:channels()
    else
      settings.V = 1
    end
  end
  
  local mod = tab.fn(settings)
  err( R.isFunction(mod), "SimpleModuleWrapper: fn must return rigel module")
  
  if tab.forceHandshake or (arg~=nil and R.isHandshake(arg.type)) then
    mod = RS.HS(mod)
  end

  local con = RS.connect{input=arg,toModule=mod}

  if tab.vectorized~=nil then
    con.vectorized=true
  end
  
  return con
end
                      }


local function stripHS(arg)
  if arg==nil then return {} end -- nullary fn
  
  if R.isHandshake(arg.type) then
    return {type=R.extractData(arg.type)}
  end
  return {type=arg.type}
end

function darkroomIRFunctions:selectStream(i)
  err(type(i)=="number",":selectStream expected number")
  return RS.selectStream{input=self, index=i}
end

function darkroomIRFunctions:index(i)
  return RS.index{input=self,key=i}
end

function RHLL.map(fn)
  err( getmetatable(fn)==SimpleModuleWrapperMT, "NYI - HLL map expects HLL module " )
  local tab = {fn=RS.modules.map}
  function tab.wireFn(arg)
    local ty = arg.type
    if R.isHandshake(ty) then ty = R.extractData(ty) end
    err( ty:isArray(), "map expects an array type as input" )
    local conn = fn(arg:index(0))
    return {fn=conn.fn, size={arg.type:arrayLength()[1],arg.type:arrayLength()[2]}}
  end
  return setmetatable(tab,SimpleModuleWrapperMT)
end

function RHLL.reduce(fn)
  err( getmetatable(fn)==SimpleModuleWrapperMT, "NYI - HLL reduce expects HLL module " )
  local tab = {fn=RS.modules.reduce}
  function tab.wireFn(arg)
    local ty = arg.type
    if R.isHandshake(ty) then ty = R.extractData(ty) end
    err( ty:isArray(), "reduce expects an array type as input" )
    local conn = fn(RS.concat{arg:index(0),arg:index(1)})
    return {fn=conn.fn, size={arg.type:arrayLength()[1],arg.type:arrayLength()[2]}}
  end
  return setmetatable(tab,SimpleModuleWrapperMT)
end

function RHLL.reduceSeq(fn,N)
  err( type(N)=="number", "rigelHLL.reduceSeq: N must be number")
  err( getmetatable(fn)==SimpleModuleWrapperMT, "NYI - HLL reduceSeq expects HLL module " )
  local tab = {fn=RS.modules.reduceSeq,settings={V=N}}
  function tab.wireFn(arg)
    print("REDUCESEQ",arg.type)
    local ty = R.extractData(arg.type)
    local conn = fn(RS.concat{R.constant("LOL0",ty:fakeValue(),ty),R.constant("LOL1",ty:fakeValue(),ty)})
    return {fn=conn.fn}
  end
  return setmetatable(tab,SimpleModuleWrapperMT)
end

local fixedid = 0
local function mathWrap(t)
  local inp = fixed_new.parameter("inp",t.type)
  local out = t.fn(inp)
  fixedid = fixedid+1
  return out:toRigelModule( t.name or "fixed"..tostring(fixedid) )
end


function RHLL.liftMath(fn)
  local tab = {fn=mathWrap,settings={fn=fn},wireFn=stripHS}
  return setmetatable(tab,SimpleModuleWrapperMT)
end

local readMemoryTab = {fn=RS.modules.readMemory,settings={}}
readMemoryTab.wireFn = function(arg)
  err( arg.type:isTuple() and #arg.type.list==2 and R.isHandshake(arg.type.list[1]) and R.isHandshake(arg.type.list[2]), "readMemory wrapper: input must be two handshake streams but is "..tostring(arg.type))
  return {type=R.extractData(arg.type.list[2])}
end

setmetatable( readMemoryTab, SimpleModuleWrapperMT )

RHLL.readMemory = readMemoryTab

function RHLL.triggeredCounter(N)
  local tab = {fn=RS.modules.triggeredCounter, settings={N=N}, wireFn=stripHS}
  return setmetatable(tab,SimpleModuleWrapperMT)
end

function RHLL.posSeq(t)
  local tab = {fn=RS.modules.posSeq, settings=t}
  return setmetatable(tab,SimpleModuleWrapperMT)
end

function RHLL.broadcast(W,H)
  return setmetatable({fn=function(t) return C.broadcast(t.type,t.W,t.H) end, settings={W=W,H=H}}, SimpleModuleWrapperMT)
end

function RHLL.cast(ty)
  return setmetatable({fn=function(t) return C.cast(t.type,ty) end, wireFn=stripHS}, SimpleModuleWrapperMT)
end

function RHLL.linebuffer(t)
  return setmetatable({fn=RS.modules.linebuffer, settings=t, wireFn=stripHS, vectorized=true}, SimpleModuleWrapperMT)
end

function RHLL.filterSeq(t)
  local tab = {fn=RS.modules.filterSeq, settings=t}
  function tab.wireFn(arg)
    err( R.isHandshake(arg.type), "filterSeq: expected handshake input ")
    local ty = R.extractData(arg.type)
    err( ty:isTuple(),"filterSeq: expected tuple input of type {A,bool}" )
    err( ty.list[2]:isBool(),"filterSeq: expected tuple input of type {A,bool}" )
    return {type=ty.list[1]}
  end
  return setmetatable(tab, SimpleModuleWrapperMT)
end

function RHLL.LUT(fn,outputType)
  local tab = {fn=RS.modules.LUT, settings={outputType=outputType}}
  function tab.wireFn(arg)
    local ty = R.extractData(arg.type)
    err( ty:isUint(), "LUT: expected uint type")
    local vals = J.map(J.range(0,math.pow(2,arg.type:verilogBits())-1),fn)
    return {type=ty, values=vals}
  end
  return setmetatable(tab, SimpleModuleWrapperMT)
end

local ziptab = {fn=RS.modules.SoAtoAoS}
function ziptab.wireFn(arg)
  local ty = R.extractData(arg.type)
  err( ty:isTuple(),"zip: expected tuple input" )
  err( ty.list[1]:isArray(), "zip: expected tuple of arrays")

  local tyl = {}
  for k,v in ipairs(ty.list) do
    table.insert(tyl, v:arrayOver() )
  end
  
  return {type=tyl,size={ty.list[1]:arrayLength()[1],ty.list[1]:arrayLength()[2]}}
end
RHLL.zip = setmetatable(ziptab, SimpleModuleWrapperMT)


function RHLL.upsampleSeq(t)
  return setmetatable({fn=RS.modules.upsampleSeq, settings={scale=t.scale, size=t.size}, wireFn=stripHS, vectorized=true }, SimpleModuleWrapperMT)
end

function RHLL.harness(t)
  err( types.isType(t.type), "RHLL.harness: type must be type ")

  --err( R.isBasic(t.type), "RHLL.harness: type should be basic" )
  
  --local inpty = RS.HS(t.type)
  local inpty = t.type

  if t.harness==2 then
    -- HACK
    err( R.isBasic(t.ramType), "RHLL.harness 2ram hack: ramType should be basic" )
    err( R.isBasic(t.type), "RHLL.harness 2ram hack: type should be basic" )
    inpty = types.tuple{RS.HS(inpty),RS.HS(t.ramType)}

    t.inType=t.type
    t.inP=1
  else
    t.inType=t.type
  end
  
  local param = R.input(inpty,t.sdfInputRate)
  local out = t.fn(param)
  print("HARNESS OUT",out.type)
  t.fn = RS.defineModule{ input=param, output=out, name="RHLLharness"}

  if t.harness==2 then
    -- HACK
    assert( t.fn.outputType:isTuple() )
    assert( R.isHandshake(t.fn.outputType.list[1]) )
    err( R.isHandshake(t.fn.outputType.list[2]),"RHLL.harness 2ram hack expected second tup to be handshake but was:"..tostring(t.fn.outputType) )
    err( R.extractData(t.fn.outputType.list[2]) == types.uint(32), "RHLL.harness 2ram hack: output addr type should be uint32")
    
    t.outP=1
    t.outType = R.extractData(t.fn.outputType.list[1])
  end
    
  print("RHLLHARNESS",t.inType)
  llharness(t)
end

function RHLL.HS(tab)
  if types.isType(tab) then
    return R.Handshake(tab)
  elseif getmetatable(tab)==SimpleModuleWrapperMT then
    tab.forceHandshake = true
    err(tab.wireFn==nil,"NYI wire fn composition")
    tab.wireFn=stripHS
    return tab
  else
    err(false,"RHLL.HS unknown type")
  end
end

function RHLL.c(ty,value)
  return RS.constant{type=ty,value=value}
end

function RHLL.lambda(fn,settings)
  local tab = {settings=settings}
  function tab.fn(t)
    local sdf
    if settings~=nil then sdf=settings.sdfRate end
    --local inp = R.input(t.type, sdf)
    --local out = fn(inp)
    t.input = R.input(t.type,sdf)
    t.output = fn(t.input)
    return RS.defineModule(t)
  end
  return setmetatable( tab, SimpleModuleWrapperMT )
end

local function HLLLift(fn)
  return setmetatable({fn=RS.modules.lift, settings={fn=fn}}, SimpleModuleWrapperMT )
end

RHLL.sel = HLLLift(function(x) return S.select(S.index(x,0),S.index(x,1),S.index(x,2)) end )
RHLL.lt = HLLLift(function(x) return S.lt(S.index(x,0),S.index(x,1)) end )
RHLL.sum = HLLLift(function(x) return S.index(x,0)+S.index(x,1) end )
RHLL.sub = HLLLift(function(x) return S.index(x,0)-S.index(x,1) end )
RHLL.andop = HLLLift(function(x) return S.__and(S.index(x,0),S.index(x,1)) end )
RHLL.mult = HLLLift(function(x) return S.index(x,0)*S.index(x,1) end )
RHLL.rshift = HLLLift(function(x) return S.rshift(S.index(x,0),S.index(x,1)) end )
RHLL.lshift = HLLLift(function(x) return S.lshift(S.index(x,0),S.index(x,1)) end )
RHLL.abs = HLLLift(function(x) return S.abs(x) end )
RHLL.neg = HLLLift(function(x) return S.neg(x) end )

RHLL.argmax = setmetatable({fn=function(t)
                              print("ARGMAX",t.type)
                              return C.argmin(t.type.list[1].list[1],t.type.list[1].list[2],false,true)
end}, SimpleModuleWrapperMT)

RHLL.argmin = setmetatable({fn=function(t)
                              print("ARGMin",t.type)
                              return C.argmin(t.type.list[1].list[1],t.type.list[1].list[2],false,false)
end}, SimpleModuleWrapperMT)

RHLL.argminAsync = setmetatable({fn=function(t)
                              print("ARGMin",t.type)
                              return C.argmin(t.type.list[1].list[1],t.type.list[1].list[2],true,false)
end}, SimpleModuleWrapperMT)

RHLL.msb = RHLL.lambda(function(x)
  err( x.type:isUint(), "msb: type must be uint but is "..tostring(x.type))
  local outbits = math.ceil(math.log(x.type:verilogBits())/math.log(2))
  local idx = RHLL.c(types.array2d(RHLL.u(outbits),x.type:verilogBits()), J.range(0,x.type:verilogBits()-1))
  local pow = RHLL.c(types.array2d(x.type,x.type:verilogBits()), J.map(J.range(0,x.type:verilogBits()-1),function(y) return math.pow(2,y) end) )
  local dat = RHLL.map(andop)(zip(RHLL.broadcast(x.type:verilogBits())(x),pow) )
  return RHLL.reduce(RHLL.argmax)(zip(idx,dat)):index(0)
end)

RHLL.b = types.bool()
RHLL.u8 = types.uint(8)
RHLL.u16 = types.uint(16)
RHLL.u32 = types.uint(32)
RHLL.u = types.uint
RHLL.i32 = types.int(32)
RHLL.tup = types.tuple
RHLL.array2d = types.array2d

function RHLL.export(t)
  if t==nil then t=_G end
  for k,v in pairs(RHLL) do rawset(t,k,v) end
end

return RHLL
