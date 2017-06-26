local RHLL = {}
local R = require "rigel"
local RS = require "rigelSimple"
local llharness = require "harness"
local fixed_new = require("fixed_new")
local types = require("types")
local SDFRate = require "sdfrate"

local ccnt = 0

-- a metatable that provides a __call function with some auto converstions for making it easier to connect to modules
-- tab.fn: fn to call to generate the module. Will send a table of 'tab.settings' concated with type
-- tab.wireFn(arg): an optional function that takes in a rigel value as input and returns additional settings
-- tab.settings: settings to send to fn
local SimpleModuleWrapperMT={__call=function(...)

  local args = {...}
  local tab = args[1]

  for i=2,#args do
    err( R.isIR(args[i]), "argument to module must be rigel value")
  end
  
  local settings = shallowCopy(tab.settings)

  print("#ARGS",#args)
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
      arg = RS.fanIn(argtab)
      print("FANIN",arg.type)
    else
      assert(false)
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
    settings.type = R.extractData(arg.type)
  end
  
  local mod = tab.fn(settings)
  err( R.isFunction(mod), "SimpleModuleWrapper: fn must return rigel module")
  
  if tab.forceHandshake or (arg~=nil and R.isHandshake(arg.type)) then
    mod = RS.HS(mod)
  end

  return RS.connect{input=arg,toModule=mod}
end
                      }


function darkroomIRFunctions:selectStream(i)
  err(type(i)=="number",":selectStream expected number")
  ccnt = ccnt + 1
  local res = R.selectStream( "v"..tostring(ccnt), self, i )

  return res
end
  
local fixedid = 0
local function mathWrap(t)
  print("MATHWRAP",t.type)
  local inp = fixed_new.parameter("inp",t.type)
  local out = t.fn(inp)
  fixedid = fixedid+1
  return out:toRigelModule( t.name or "fixed"..tostring(fixedid) )
end


function RHLL.liftMath(fn)
  local tab = {fn=mathWrap,settings={fn=fn},handshake=false}
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
  local tab = {fn=RS.modules.triggeredCounter, settings={N=N}}
  return setmetatable(tab,SimpleModuleWrapperMT)
end

function RHLL.posSeq(t)
  local tab = {fn=RS.modules.posSeq, settings={size=t.size,V=t.V}}
  return setmetatable(tab,SimpleModuleWrapperMT)
end

function RHLL.harness(t)
  err( types.isType(t.inType), "RHLL.harness: inType must be type ")

  local param = R.input(t.inType,t.sdfInputRate)
  t.fn = RS.defineModule{ input=param, output=t.fn(param)}
  llharness(t)
end

function RHLL.HS(tab)
  if types.isType(tab) then
    return R.Handshake(tab)
  elseif getmetatable(tab)==SimpleModuleWrapperMT then
    tab.forceHandshake = true
    return tab
  else
    err(false,"RHLL.HS unknown type")
  end
end

function RHLL.importAll()
  rawset(_G,"liftMath",RHLL.liftMath)
  rawset(_G,"triggeredCounter",RHLL.triggeredCounter)
  rawset(_G,"posSeq", RHLL.posSeq)
  rawset(_G,"harness",RHLL.harness)
  rawset(_G,"HS",RHLL.HS)

  rawset(_G,"uint8",types.uint(8))
  rawset(_G,"array2d",types.array2d)
end

return RHLL
