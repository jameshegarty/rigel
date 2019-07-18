local J = require "common"
local params = {}

local ParamFunctions = {}
local ParamMT = {__index=ParamFunctions,__tostring=function(p)
                   return p.name..":"..p.kind --"Param_"..p.kind
end
                }

local function makeParam( kind, isValue, super )
  assert(type(kind)=="string")
  assert(type(isValue)=="boolean")
  assert(super==nil or params.isParam(super))
  return J.memoize(function(name,X)
      assert(type(name)=="string")
      assert(X==nil)
    return setmetatable({kind=kind,name=name,isValue=isValue,super=super},ParamMT)
  end)
end

function params.isParam(t) return getmetatable(t)==ParamMT end
function params.isParamType(t) return getmetatable(t)==ParamMT and (t.isValue==false) end
function params.isParamValue(t) return getmetatable(t)==ParamMT and t.isValue end

params.UintValue = makeParam("UintValue",true)
params.SizeValue = makeParam("SizeValue",true)

params.DataType = makeParam("DataType",false)
params.NumberType = makeParam("NumberType",false,params.DataType("tmp"))
params.UintType = makeParam("UintType",false,params.NumberType("tmp"))

params.ScheduleType = makeParam("ScheduleType",false)
params.ParSeqType = makeParam("ParSeqType",false,params.ScheduleType("tmp"))
params.ParType = makeParam("ParType",false,params.ScheduleType("tmp"))

-- is this param a superclass of P?
function ParamFunctions:isSuper(P)
  J.err( params.isParam(P), ":isSuper(), arg is not a param: "..tostring(P) )
  if self.kind==P.kind then return true end
  if P.super==nil then return false end -- this kind has no super, and doesn't match self
  return self:isSuper(P.super)
end

local function valueToParam(V)
  local function firstToUpper(str)
    return (str:gsub("^%l", string.upper))
  end

  local types = require "types"
  if types.isType(V)==false then
    V = types.valueToType(V)
  end
  
  local p = params[firstToUpper(V.kind).."Type"]
  J.err(p~=nil,"No corresponding param for type "..V.kind)
  return p("tmp")
end

-- is V an instance of this param?
function ParamFunctions:isInstance(V)
  print(V,"Is instance of?",self)
  return self:isSuper(valueToParam(V))
end

return params
