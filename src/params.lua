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
params.ArrayType = makeParam("ArrayType",false,params.DataType("tmp"))
params.TupleType = makeParam("TupleType",false,params.DataType("tmp"))
params.InterfaceType = makeParam("InterfaceType",false)

params.ScheduleType = makeParam("ScheduleType",false)
params.ParSeqType = makeParam("ParSeqType",false,params.ScheduleType("tmp"))
params.ParType = makeParam("ParType",false,params.ScheduleType("tmp"))
params.SeqType = makeParam("SeqType",false,params.ScheduleType("tmp"))

params.SumType = function(name,list)
  return setmetatable({kind="SumType",name=name,isValue=false,list=list},ParamMT)
end

local function valueOrTypeToParam(V)
  local function firstToUpper(str)
    return (str:gsub("^%l", string.upper))
  end

  local R = require "rigel"
  if R.isSize(V) then return params.SizeValue("tmp") end
  
  local types = require "types"
  if types.isType(V)==false then
    V = types.valueToType(V)
  end
  
  local p = params[firstToUpper(V.kind).."Type"]
  J.err(p~=nil,"No corresponding param for type "..V.kind)
  return p("tmp")
end

-- is this param a supertype of P?
function ParamFunctions:isSupertypeOf(P,vars)
  local types = require "types"
  local uniform = require "uniform"
  if self.kind=="SumType" then
    -- hack
    assert(#self.list==1)
    vars[P.name]=0
    return self.list[1]:isSupertypeOf(P,vars)
  elseif params.isParam(P) then
    if self.kind==P.kind then return true end
    if P.super==nil then return false end -- this kind has no super, and doesn't match self
    return self:isSupertypeOf(P.super,vars)
  else
    return self:isSupertypeOf(valueOrTypeToParam(P),vars)
    --print(tostring(self)..":isSupertypeOf() could not deal with ",P)
    --assert(false)

  end
end

return params
