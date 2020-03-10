local J = require "common"
local params = {}

local ParamFunctions = {}
local ParamMT = {__index=ParamFunctions,__tostring=function(p)
                   if p.kind=="SumType" then
                     local res = ""
                     for k,v in ipairs(p.list) do
                       res = res.."|\n"..tostring(v)
                     end
                     return res
                   elseif p.kind=="TypeList" then
                     return "TypeList:"..p.name.."("..tostring(p.constraint)..")"
                   else
                     local over = ""
                     if p.over~=nil then over="("..tostring(p.over)..")" end
                     return p.name..":"..p.kind..over --"Param_"..p.kind
                   end
end
                }

function ParamFunctions:isSchedule()
  if self.kind=="TypeList" then return self.constraint:isSchedule() end
  return self.kind=="ScheduleType"
end
function ParamFunctions:isInterface()
  if self.kind=="TypeList" then return self.constraint:isInterface() end
  return self.kind=="InterfaceType"
end

function ParamFunctions:isData()
  -- "TupleType" seems wrong here (could contain a interface or schedule?)    
  return self.kind=="DataType" or self.kind=="NumberType" or self.kind=="BitsType" or self.kind=="UintType" or self.kind=="IntType" or self.kind=="TupleType"
end

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


-- over can be nil: means any schedule
params.ScheduleType = function(name,over,X)
  assert(X==nil)
  assert(type(name)=="string")
  return setmetatable({kind="ScheduleType",name=name,over=over,isValue=false},ParamMT)
end

params.DataType = makeParam("DataType",false,params.ScheduleType("tmp"))
params.TriggerType = makeParam("TriggerType",false,params.DataType("tmp"))
params.NumberType = makeParam("NumberType",false,params.DataType("tmp"))
params.IntType = makeParam("IntType",false,params.NumberType("tmp"))
params.UintType = makeParam("UintType",false,params.NumberType("tmp"))
params.FloatType = makeParam("FloatType",false,params.NumberType("tmp"))
params.BoolType = makeParam("BoolType",false,params.NumberType("tmp"))
params.BitsType = makeParam("BitsType",false,params.DataType("tmp"))
params.ArrayType = makeParam("ArrayType",false,params.DataType("tmp"))
params.TupleType = makeParam("TupleType",false,params.DataType("tmp"))

-- over can be nil: means any interface
params.InterfaceType = function(name,over,X)
  assert(X==nil)
  assert(type(name)=="string")
  return setmetatable({kind="InterfaceType",name=name,over=over,isValue=false},ParamMT)
end


params.ParSeqType = makeParam("ParSeqType",false,params.ScheduleType("tmp"))
params.ParType = makeParam("ParType",false,params.ScheduleType("tmp"))
params.SeqType = makeParam("SeqType",false,params.ScheduleType("tmp"))

-- a list of types (for tuples)
params.TypeList = function(name,constraint,X)
  assert(constraint~=nil)
  return setmetatable({kind="TypeList",name=name,constraint=constraint,isValue=false},ParamMT)
end

params.SumType = function(name,list,X)
  assert(type(list)=="table")
  assert(X==nil)
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
  
  local p
  if V.kind=="named" then
    -- legacy hack
    p = params[firstToUpper(V.structure.kind).."Type"]
  else
    p = params[firstToUpper(V.kind).."Type"]
  end
  J.err(p~=nil,"No corresponding param for type "..V.kind.." "..tostring(V))
  return p("tmp")
end

-- is this param a supertype of P?
function ParamFunctions:isSupertypeOf( P, vars, varContext )
  local types = require "types"
  local uniform = require "uniform"
  local R = require "rigel"

  J.err(P~=nil,":isSupertypeOf: type must not be nil")
  assert(type(varContext)=="string")
  
  if self.kind=="SumType" then
    --assert(false)
    -- hack
    --assert(#self.list==1)
    --vars[P.name]=0
    --return self.list[1]:isSupertypeOf(P,vars)
    for k,v in ipairs(self.list) do
      if v:isSupertypeOf(P,vars,varContext) then
        vars[self.name]=k-1
        return true
      end
    end
    return false
  elseif params.isParam(P) then
    if self.kind==P.kind then return true end
    if P.super==nil then return false end -- this kind has no super, and doesn't match self
    return self:isSupertypeOf(P.super,vars,varContext)
  elseif self.kind=="InterfaceType" then
    if P:isInterface()==false then return false end
    if P:isArray() or P:isTuple() then return false end
    
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
    elseif P:isrRvV() then
      vars[self.name] = types.rRvV
    elseif P:isS() then
      vars[self.name] = types.Interface
    else
      print("NYI interf - "..tostring(P))
      assert(false)
    end
    if self.over==nil or P.over==nil then
      -- one of them is a trigger - they must match
      return self.over==P.over
    end
    
    local res = self.over:isSupertypeOf(P.over,vars,varContext)
    --print("Param interface here",self.over,P.over,res)
    return res
  elseif self.kind=="ScheduleType" then
    if P:isSchedule()==false and P:isData()==false then return false end

    if self.over==nil then
      vars[self.name] = P
      return true
    else
      if P:isTuple() or P:isArray() then
        -- not sure what to do here... we want a schedule type matching a particular
        -- pattern, but the user gave us a tuple/array? (which doesn't match pattern, sort of?)
        return false
      end
      
      local res = self.over:isSupertypeOf(P.over,vars,varContext)
      if res==false then return false end
      
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
      return true
    end
  elseif types.isType(P) or type(P)=="number" or R.isSize(P) then
    if self.kind=="DataType" and types.isType(P) and P:isArray() and P.size~=P.V then
      -- detect scheduled arrays
      -- errr, we should really deal with this better
      return false
    elseif self:isSupertypeOf( valueOrTypeToParam(P), vars, varContext ) then
      vars[self.name] = P
      return true
    else
      return false
    end
  end

  print("Error, checking "..tostring(self)..":isSupertypeOf("..tostring(P)..")")
  assert(false)
end

function ParamFunctions:specialize( vars )
  J.err(vars[self.name]~=nil,"specialize: looking for var '"..self.name.."', but wasn't found in table")
  
  if type(vars[self.name])=="function" then
    -- for InterfaceType, ScheduleType
    return vars[self.name](self.over:specialize(vars))
  else
    return vars[self.name]
  end

end

return params
