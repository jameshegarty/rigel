local SDFRate = {}
local J = require "common"
local err = J.err

function SDFRate.simplify(a,b)
  local Uniform = require "uniform"

  local res = Uniform(a)/Uniform(b)
  res = res:simplify()

  if res.kind=="binop" and res.op=="div" then
    return res.inputs[1], res.inputs[2]
  else
    -- this is >=1, maybe?
    assert( res:isNumber() )
    assert( res:ge(0):assertAlwaysTrue() )
    return res,Uniform(1)
  end
end

-- t should be format {{number,number},{number,number},...}
function SDFRate.isSDFRate(t)
  if type(t)~="table" then return false end
  if J.keycount(t)~=#t then return false end
  for _,v in pairs(t) do
    return SDFRate.isFrac(v)
  end
  return true
end

function SDFRate.tostring(t)
  err(SDFRate.isSDFRate(t), "SDFRate.tostring: not an SDF rate?")
  local str = "{"
  for k,v in ipairs(t) do
    if v=='x' then
      str = str.."x,"
    else
      str = str..tostring(v[1]).."/"..tostring(v[2])
      if k~=#t then str = str.."," end
    end
  end
  str = str.."}"
  return str
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
    local n,d = SDFRate.simplify(nn,dd)
    res[i] = {n,d}
  end
  
  return res
end

function SDFRate.isFrac(a)
  if type(a)~="table" then
    return false
  end

  if type(a[1])=="number" and type(a[2])=="number" then
    return math.floor(a[1])==a[1] and math.floor(a[2])==a[2] and a[1]>=0 and a[2]>0
  end

  local Uniform = require "uniform"
  
  if Uniform.isUniform(a[1]) or Uniform.isUniform(a[2]) then
    local a1,a2=Uniform(a[1]), Uniform(a[2])
    local n,d = SDFRate.simplify(a1,a2)

    if n:isNumber() and d:isNumber() and d:gt(0):assertAlwaysTrue() then
      return true
    else
      print("Error: input is not a valid fraction, because N or D are not integer, or D is 0: "..tostring(a1).."/"..tostring(a2))
      return false
    end
  end

  print("Not a frac?",a[1],a[2],type(a[1]),type(a[2]))
  return false
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
  assert(SDFRate.isFrac(a))
  assert(SDFRate.isFrac(b))
  local d = a[2]*b[2]
  local n = a[1]*b[2]+b[1]*a[2]
  local n,d = SDFRate.simplify(n,d)
  return {n,d}
end

function SDFRate.fracMultiply(a,b)
  err( SDFRate.isFrac(a), "SDFRate.fracMultiple a is not frac: "..tostring(a[1]).." "..tostring(a[2]) )
  err( SDFRate.isFrac(b), "SDFRate.fracMultiple b is not frac: "..tostring(b[1]).." "..tostring(b[2]) )

  local a1,a2 = SDFRate.simplify(a[1],a[2])
  a={a1,a2}

  local b1,b2 = SDFRate.simplify(b[1],b[2])
  b={b1,b2}

  local Uniform = require "uniform"
  
  local n,d = a[1]*b[1],a[2]*b[2]
  assert( Uniform(n):isUint() )
  assert( Uniform(d):isUint() )
  local n,d = SDFRate.simplify(n,d)
  local res = {n,d}

  assert(SDFRate.isFrac(res))
  return res
end

-- format {n,d}
function SDFRate.fracEq(a,b)
  assert(SDFRate.isFrac(a))
  assert(SDFRate.isFrac(b))

  local a1,a2 = SDFRate.simplify(a[1],a[2])
  local b1,b2 = SDFRate.simplify(b[1],b[2])

  local n,d = a1*b2, a2*b1
  --assert( Uniform(n):isUint() )
  --assert( Uniform(d):isUint() )

  return n:eq(d):assertAlwaysTrue()
  -- never do non-integer comparisons! (0.07*300 ~= 21)!
  --local n,d = a[1]*b[2], a[2]*b[1]
  --return n==d
end

function SDFRate.sum(tab)
  assert( SDFRate.isSDFRate(tab) )
  
  local sum = nil
  for k,v in pairs(tab) do 
    if sum==nil then
      sum = v
    else
      sum = fracSum(sum,v)
    end
  end

  return sum
end

function SDFRate.multiply(tab,n,d)
  assert(SDFRate.isSDFRate(tab))

  local Uniform = require "uniform"
  
  n=Uniform(n)
  d=Uniform(d)
  assert(n:isUint())
  assert(d:isUint())

  local res = {}
  for k,v in pairs(tab) do
    table.insert(res, SDFRate.fracMultiply(v,{n,d}))
  end
  return res
end


return SDFRate
