local SDFRate = require "sdfrate"
local J = require "common"

local SDFFunctions = {}
local SDFMT = {__index=SDFFunctions}

local sdf = {}

-- for each N rate, what is the largest? (returned as number)
function SDFFunctions:maxnumber()
  local m
  for _,v in ipairs(self) do
    local val = v[1]/v[2]
    if m==nil or m>val then m=val end
  end
  return m
end

function SDFFunctions:tonumber()
  J.err( #self==1,"Could not convert multi-stream SDF rate to a number: "..tostring(self))
  return self[1][1]/self[1][2]
end

function SDFFunctions:equals(other)
  J.err( sdf.isSDF(other), "SDF:equals(), other table isn't an SDF" )
  if #self ~= #other then return false end
  for k,v in ipairs(self) do
    if v[1]~=other[k][1] or v[2]~=other[k][2] then return false end
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

  -- shorthand: {1,1} instead of {{1,1}}
  if type(arg)=="table" and type(arg[1])=="number" and type(arg[2])=="number" then
    arg={arg}
  end
  
  assert(SDFRate.isSDFRate(arg))
  return setmetatable(arg,SDFMT)
end
  
function sdf.isSDF(tab) return getmetatable(tab)==SDFMT end

return sdf
