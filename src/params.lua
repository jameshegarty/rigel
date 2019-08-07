local J = require "common"
local params = {}

local ParamFunctions = {}
local ParamMT = {__index=ParamFunctions,__tostring=function(p)
                   if p.kind=="SumType" then
                     local res = ""
                     for k,v in ipairs(p.list) do
                       res = res.."|"..tostring(v)
                     end
                     return res
                   else
                     local over = ""
                     if p.over~=nil then over="("..tostring(p.over)..")" end
                     return p.name..":"..p.kind..over --"Param_"..p.kind
                   end
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
--params.InterfaceType = makeParam("InterfaceType",false)

params.ScheduleType = makeParam("ScheduleType",false)
params.ParSeqType = makeParam("ParSeqType",false,params.ScheduleType("tmp"))
params.ParType = makeParam("ParType",false,params.ScheduleType("tmp"))
params.SeqType = makeParam("SeqType",false,params.ScheduleType("tmp"))

params.SumType = function(name,list)
  return setmetatable({kind="SumType",name=name,isValue=false,list=list},ParamMT)
end

params.InterfaceType = function(name,over,X)
  assert(X==nil)
  assert(type(name)=="string")
  local types = require "types"
  assert(types.isType(over) or params.isParam(over))
  return setmetatable({kind="InterfaceType",name=name,over=over,isValue=false,list=list},ParamMT)
end

params.ScheduleTypeOver = function(name,over,X)
  assert(X==nil)
  assert(type(name)=="string")
  local types = require "types"
  assert(types.isType(over) or params.isParam(over))
  return setmetatable({kind="ScheduleType",name=name,over=over,isValue=false,list=list},ParamMT)
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
    assert(false)
    -- hack
    assert(#self.list==1)
    vars[P.name]=0
    return self.list[1]:isSupertypeOf(P,vars)
  elseif self.kind=="InterfaceType" then
    --print("Param interface type",P)
    if P:isInterfaceType()==false then return false end
    if P:isRV() then
      vars[self.name] = types.RV
    elseif P:isrV() then
      vars[self.name] = types.rV
    elseif P:isrRV() then
      vars[self.name] = types.rRV
    elseif P:isrv() then
      vars[self.name] = types.rv
    elseif P:isrvV() then
      vars[self.name] = types.rvV
    else
      print("NYI interf - "..tostring(P))
      assert(false)
    end
    local res = self.over:isSupertypeOf(P.over,vars)
    --print("Param interface here",self.over,P.over,res)
    return res
  elseif self.kind=="ScheduleType" then
    --J.err(types.isType(P),"Schedule Type match should be type, but is: "..tostring(P).." self:"..tostring(self))
    if P==nil then -- this can happen if we're mapping against a RVTrigger for example
return false
    end
    
    if P:isScheduleType()==false then return false end
    if P:is("Par") then
      vars[self.name] = types.Par
    elseif P:is("ParSeq") then
      vars[self.name] = function(o) return types.ParSeq(o,P.size[1],P.size[2]) end
    elseif P:is("Seq") then
      vars[self.name] = function(o) return types.Seq(o,P.size[1],P.size[2]) end
    else
      print("NYI - "..tostring(P))
      assert(false)
    end
    if self.over==nil then
      return true
    else
      local res = self.over:isSupertypeOf(P.over,vars)
      --print("Param interface here",self.over,P.over,res)
      return res
    end
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
