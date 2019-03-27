local SDFRate = require "sdfrate"
local J = require "common"

local SDFFunctions = {}
local SDFMT = {__index=SDFFunctions}

local sdf = {}

-- return true if all ratios in this rate are <= 1
function SDFFunctions:allLE1()
  for _,v in ipairs(self) do
    local res = v[1]:le(v[2]):assertAlwaysTrue()

    if res==false then
      return false
    end
  end

  return true
end

function SDFFunctions:tonumber()
  J.err( #self==1,"Could not convert multi-stream SDF rate to a number: "..tostring(self))
  return self[1][1]/self[1][2]
end

function SDFFunctions:equals(other)
  J.err( sdf.isSDF(other), "SDF:equals(), other table isn't an SDF" )
  if #self ~= #other then return false end
  for k,v in ipairs(self) do
    local Uniform = require "uniform"

    -- given A/B==C/D, check (A*D)==(B*C) (it's simpler?)

    if (Uniform(v[1])*Uniform(other[k][2])):eq(Uniform(v[2])*Uniform(other[k][1])):assertAlwaysTrue()==false then
      return false
    end
    --if type(v[1])~="number" or type(other[k][1])~="number" then
    --  print("SDF EQ",v[1],v[2],other[k][1],other[k][2])
    --end
    
    --if v[1]~=other[k][1] or v[2]~=other[k][2] then return false end
  end
  return true
end

function SDFMT.__tostring(tab)
  return SDFRate.tostring(tab)
end


local SDFTOPMT = {} -- this is just a hack so that we can call apply on the thing we return from the file
setmetatable(sdf,SDFTOPMT)

SDFTOPMT.__call = function(tab,arg,X)
  assert(X==nil)

  local Uniform = require "uniform"

  -- shorthand: {1,1} instead of {{1,1}}
  if type(arg)=="table" and (type(arg[1])=="number" or Uniform.isUniform(arg[1])) and (type(arg[2])=="number" or Uniform.isUniform(arg[2])) then
    arg={arg}
  end
  
  assert(SDFRate.isSDFRate(arg))
  
  local uarg = {}
  for _,v in ipairs(arg) do
    local n,d = SDFRate.simplify(Uniform(v[1]),Uniform(v[2]))
    table.insert(uarg,{n,d})
  end
  
  return setmetatable(uarg,SDFMT)
end
  
function sdf.isSDF(tab) return getmetatable(tab)==SDFMT end

return sdf
