local SDFRate = {}

-- t should be format {{number,number},{number,number},...}
function SDFRate.isSDFRate(t)
  if type(t)~="table" then return false end
  if keycount(t)~=#t then return false end
  for _,v in pairs(t) do
    if v=="x" then
      -- ok
    else
      if type(v)~="table" then return false end
      if (type(v[1])~="number" or type(v[2])~="number") then return false end
    end
  end
  return true
end


-- normalizes a table of SDF rates so that they sum to 1
function SDFRate.normalize( tab )
  assert( SDFRate.isSDFRate(tab) )

  local sum = {tab[1][1],tab[1][2]}
  for i=2,#tab do
    local b = tab[i]
    -- (a/b)+(c/d) == (a*d/b*d) + (c*b/b*d)
    sum[1] = sum[1]*b[2] + b[1]*sum[2]
    sum[2] = sum[2]*b[2]
  end
  
  local res = {}
  for i=1,#tab do
    local nn,dd = tab[i][1]*sum[2], tab[i][2]*sum[1]
    local n,d = simplify(nn,dd)
    res[i] = {n,d}
  end
  
  return res
end

function SDFRate.isFrac(a)
  return type(a)=="table" and type(a[1])=="number" and type(a[2])=="number"
end

function SDFRate.fracToNumber(a)
  assert(SDFRate.isFrac(a))
  return a[1]/a[2]
end

function SDFRate.fracInvert(a)
  assert(SDFRate.isFrac(a))
  return {a[2],a[1]}
end

-- format {n,d}
local function fracSum(a,b)
  local denom = a[2]*b[2]
  local num = a[1]*b[2]+b[1]*a[2]
  local n,d=simplify(num,denom)
  return {n,d}
end

function SDFRate.fracMultiply(a,b)
  local n,d = simplify(a[1]*b[1],a[2]*b[2])
  return {n,d}
end

function SDFRate.sum(tab)
  assert( SDFRate.isSDFRate(tab) )
  
  local sum = {0,1}
  for k,v in pairs(tab) do 
    if v~="x" then sum = fracSum(sum,v) end
  end

  return sum
end

function SDFRate.multiply(tab,n,d)
  assert(type(n)=="number")
  assert(type(d)=="number")

  local res = {}
  for k,v in pairs(tab) do
    if v=="x" then
      table.insert(res,v)
    else
      table.insert(res, SDFRate.fracMultiply(v,{n,d}))
    end
  end
  return res
end


return SDFRate