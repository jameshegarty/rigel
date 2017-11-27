local common = {}

function common.table_print (tt, indent, done)
  done = done or {}
  indent = indent or 0
  if type(tt) == "table" then
    local sb = {}
    local first = true
    for key, value in pairs (tt) do
      table.insert(sb, string.rep (" ", indent)) -- indent it
      if type (value) == "table" then
        done [value] = true
	table.insert(sb, key);
	table.insert(sb, "=");
--        table.insert(sb, "{"..tostring(value).."\n");
--        if first then comma="";first=false end
        table.insert(sb, "{\n");
        table.insert(sb, common.table_print (value, indent + 2, done))
        table.insert(sb, string.rep (" ", indent)) -- indent it
        local comma = ","
        table.insert(sb, "}");
      elseif "number" == type(key) then
        table.insert(sb, string.format("\"%s\"", tostring(value)))
      else
        table.insert(sb, string.format(
            "%s = %s", tostring (key), tostring(value)))
      end
      table.insert(sb,",\n")
    end
    sb[#sb] = nil -- delete comma
    return table.concat(sb)
  else
    return tostring(tt) .. "\n"
  end
end

function common.to_string( tbl )
    if  "nil"       == type( tbl ) then
        return tostring(nil)
    elseif  "table" == type( tbl ) then
        return common.table_print(tbl)
    elseif  "string" == type( tbl ) then
        return tbl
    else
        return tostring(tbl)
    end
end

function common.serialize(tbl) print(to_string(tbl)) end


function common.deepcopy(object)
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end


function common.explode(div,str) -- credit: http://richard.warburton.it
  if (div=='') then return false end
  local pos,arr = 0,{}
  -- for each divider found
  for st,sp in function() return string.find(str,div,pos,true) end do
    table.insert(arr,string.sub(str,pos,st-1)) -- Attach chars left of current divider
    pos = sp + 1 -- Jump past current divider
  end
  table.insert(arr,string.sub(str,pos)) -- Attach chars right of last divider
  return arr
end

-- append elements in 'src' to 'dest'
-- both have to have only numeric keys
function common.appendTable(dest,src)
  for k,v in ipairs(src) do
    assert(type(k)=="number")
    table.insert(dest,v)
  end
end

function common.appendSet(dest,src)
  for k,v in pairs(src) do
    dest[k]=v
  end
end

function common.joinSet(dest,src)
  local t = {}

  for k,v in pairs(dest) do
    t[k]=v
  end

  for k,v in pairs(src) do
    if t[k]~=nil then
      print("duplicate",k)
      assert(false)
    end
    t[k]=v
  end

  return t
end

function common.joinTables(A,B)
  local T = {}
  for k,v in ipairs(A) do table.insert(T,v) end
  for k,v in ipairs(B) do table.insert(T,v) end
  return T
end

function common.keycount(t)
  assert(type(t)=="table")
  local tot = 0
  for k,v in pairs(t) do tot=tot+1 end
  return tot
end

-- takes an array of values to a hash where the values are keys
function common.invertTable(t)
--  for k,v in pairs(t) do assert(type(k)=="number") end

  local out = {}
  for k,v in pairs(t) do
    assert(out[v]==nil)  -- no duplicates
    out[v]=k
  end

  return out
end

-- dedup t. no guarantee on the behavior of the keys
function common.dedup(t)
  local invT = {}
  for k,v in pairs(t) do 
    assert(type(k)=="number") 
    invT[v] = 1
  end

  local res = {}
  for k,_ in pairs(invT) do
    res[#res+1]=k
  end

  return res
end

function common.pack(...)
  local arg = {...}
  return arg
end


function common.explode(div,str) -- credit: http://richard.warburton.it
 if (div=='') then return false end
  local pos,arr = 0,{}
  -- for each divider found
  for st,sp in function() return string.find(str,div,pos,true) end do
    table.insert(arr,string.sub(str,pos,st-1)) -- Attach chars left of current divider
    pos = sp + 1 -- Jump past current divider
  end
  table.insert(arr,string.sub(str,pos)) -- Attach chars right of last divider
  return arr
end

-- round x up to the next largest number that has 'roundto' as a factor
function common.upToNearest(roundto,x)
  assert(type(x)=="number")

  if x % roundto == 0 or roundto==0 then return x end
  
  local ox

  ox = x + (roundto-x%roundto)

  assert(ox > x)
  assert( (ox % roundto) == 0)
  return ox
end

function common.downToNearest(roundto,x)
  assert(type(x)=="number")
  assert(roundto>=0)
  --assert(x>=0)

  if x % roundto == 0 or roundto == 0 then return x end

  local ox
  if x < 0 then
    ox = x - x%roundto
  else
    ox = x - x%roundto 
  end
  assert(ox < x and ox % roundto == 0 and math.abs(x-ox)<=roundto)
  return ox
end



function common.isModuleAvailable(name)
  if package.loaded[name] then
    return true
  else
    for _, searcher in ipairs(package.searchers or package.loaders) do
      local loader = searcher(name)
      if type(loader) == 'function' then
        package.preload[name] = loader
        return true
      end
    end
    return false
  end
end

function common.isPowerOf2(x)
  local r = math.log(x)/math.log(2)
  return r==math.floor(r)
end

-- nearestPowerOf2(x) >= x
function common.nearestPowerOf2(x)
  local r = math.pow(2, math.ceil(math.log(x)/math.log(2)))
  assert(r>=x)
  assert(math.log(r)/math.log(2) == math.ceil(math.log(r)/math.log(2)))
  return r
end

function common.gcd(a,b)
  assert(type(a)=="number")
  assert(type(b)=="number")
  if b ~= 0 then
    return common.gcd(b, a % b)
  else
    return math.abs(a)
  end
end

function common.ratioFactor(a,b)
  local g = common.gcd(a,b)
  return a/g, b/g
end
common.simplify = common.ratioFactor

function common.map(t,f)
  assert(type(t)=="table")
  assert(type(f)=="function")
  local res = {}
  for k,v in pairs(t) do res[k] = f(v,k) end
  return res
end

-- if idx={a,b,c} this does
-- t[a][b][c] = t[a][b][c] or value
-- returns t[a][b][c]
-- (and also makes the intermediate tables if necessary)
-- This function has a weakness - we can't detect if we provided insufficient indices! That will still return something.
function common.deepsetweak( t, idx, value )
  assert(type(t)=="table")
  assert(type(idx)=="table")
  assert(#idx>0)

  local T = t
  for k,v in ipairs(idx) do
    if #idx==k then
      T[v] = T[v] or value
      return T[v]
    else
      T[v] = T[v] or {}
      T = T[v]
    end
  end

  assert(common.keycount(idx)==#idx)
  error("deepsetweak?")
end

-- if idx={a,b,c} this does
-- return t[a][b][c]
-- but returns nil if any of the indexing fails, doesn't error out
function common.index(t,idx)
  common.err( type(t)=="table", "common.index: t must be table")
  assert(type(idx)=="table")
  assert(common.keycount(idx)==#idx)
  assert(#idx>0)

  local T = t
  for k,v in ipairs(idx) do
    T = T[v]
    if type(T)~="table" then return nil end
  end
  return T
end

function common.concat(t1,t2)
  assert(type(t1)=="table")
  assert(type(t2)=="table")
  local t = {}
  for k,v in ipairs(t1) do table.insert(t,v) end
  for k,v in ipairs(t2) do table.insert(t,v) end
  return t
end

function common.reverse(t)
  assert( common.keycount(t)==#t )
  local r = {}
  for k,v in ipairs(t) do r[#t-k+1] = v end
  return r
end

-- t[k] is removed from array if f([t[k])==false
function common.filter(t,f)
  local r = {}
  for k,v in pairs(t) do
    if f(v,k) then table.insert(r, v) end
  end
  return r
end

-- works on lua arrays. Compare to filter (above)
function common.ifilter( t, f )
  common.err( common.keycount(t)==#t, "ifilter: t must be table" )
  local r = {}
  for k,v in ipairs(t) do
    if f(v,k) then table.insert(r, v) end
  end
  return r
end

-- f must obey the property that:
-- f(nil,nil) = base
-- f(a,nil) = a
-- (you don't need to specify these cases in f, but this is how it will behave)
-- the f(nil,nil) case will only happen if the uses passes in an empty array
function common.foldt(t, f, base)
  assert(#t==common.keycount(t))
  if #t==0 then return base end
  if #t==1 then return t[1] end
  if #t==2 then return f(t[1],t[2]) end

  local res = {}
  local i=2
  while t[i]~=nil do
    table.insert(res, f(t[i-1],t[i]))
    i = i + 2
  end
  -- if we have an odd # of elements
  if t[i-1]~=nil then table.insert(res, t[i-1]) end

  assert(#res>0)
  if #res==1 then return res[1] end
  return common.foldt( res, f, base )
end

-- returns a table of values from a to b, inclusive
function common.range(a,b)
  assert(type(a)=="number" and (a==math.floor(a)))
  assert(type(b)=="number" or b==nil)
  if b==nil then a,b = 1,a end
  local t = {}
  if a<=b then
    for i=a,b do table.insert(t,i) end
  else -- b<a
    for i=a,b,-1 do table.insert(t,i) end
  end

  return t
end

-- row major order
function common.range2d(xlow,xhigh,ylow,yhigh)
  assert(type(xlow)=="number")
  assert(type(xhigh)=="number")
  assert(type(ylow)=="number")
  assert(type(yhigh)=="number")

  local t = {}
  for y=ylow,yhigh do
    for x=xlow,xhigh do 
      table.insert(t,{x,y})
    end
  end

  return t
end

-- takes table m this is a key,value table,
-- removes the keys and turns it into an array
function common.mapToArray(m)
  local t = {}
  for k,v in pairs(m) do
    table.insert(t,v)
  end
  return t
end

common.stripkeys = common.mapToArray

function common.invertAndStripKeys(t)
  local r = {}
  for k,v in pairs(t) do table.insert(r,k) end
  return r
end

function common.sel(cond,a,b)
  if cond then return a else return b end
end

-- unlike lua's in place sort, this returns the sorted table
function common.sort( a, f )
  assert(type(a)=="table")
  local t = {}
  for k,v in pairs(a) do t[k] = v end
  table.sort( t, f )
  return t
end

-- fn(a,b)
function common.foldl( fn, base, t )
  common.err(type(fn)=="function","foldl: first argument must be function")
  common.err( type(t)=="table", "foldl: input must be table")
  common.err( #t==common.keycount(t), "foldl: table must be lua array" ) -- should be only numeric keys
  
  if #t==0 then return base end

--  assert(type(base)==type(t[1]))

  local res = base
  for k,v in ipairs(t) do
    res = fn(res,v)
  end

  return res
end

function common.andop(a,b) return a and b end
function common.orop(a,b) return a or b end

-- returns first i elements of the list t
function common.take(t,i)
  assert(type(t)=="table")
  local r = {}
  for k,v in ipairs(t) do
    if k<=i then table.insert( r, v ) end
  end
  return r
end



local __memoized = {}
local __memoizedNilHack = {}

local function makeDense(t)
  local max = 0
  for k,v in pairs(t) do assert(type(k)=="number"); max=math.max(max,k) end
  for k=1,max do if t[k]==nil then t[k]=__memoizedNilHack end end
end

function common.memoize(f)
  assert(type(f)=="function")
  return function(...)
    local idx = common.map({...}, function(v) 
                      -- hack: tables can't have nil keys. To accommodate this, we make a fake table to represent nils, and replace nils with that
                      -- (remember, we use the values of this table as keys for the hash later)
                      if v==nil then return __memoizedNilHack end
                      common.err(type(v)=="number" or type(v)=="table" or type(v)=="string" or type(v)=="boolean" or type(v)=="function","deepsetweak type was "..type(v)) 
                      return v
                           end)

    -- since some values of {...} may be nil, we need to densify it (fill in all keys from min to max)
    makeDense(idx)

    assert(common.keycount(idx)==#idx)
    local cnt = #idx
    __memoized[f] = __memoized[f] or {}
    if cnt==0 then
      if __memoized[f][0]==nil then __memoized[f][0]=f(...) end
      return __memoized[f][0]
    else
      __memoized[f][cnt] = __memoized[f][cnt] or {}
      local t = common.index(__memoized[f][cnt],idx)
      if t~=nil then return t end -- early out, so that we don't call f multiple times w/ same arguments
      return common.deepsetweak( __memoized[f][cnt], idx, f(...) )
    end
  end
end

-- this take [a,b,c,d,e,f] to [[a,b],[c,d],[e,f]] (for n==2)
function common.split(t,n)
  assert(#t % n == 0)
  local r = {}
  for k,v in ipairs(t) do 
    local i = math.floor((k-1)/n)+1
    r[i] = r[i] or {}
    table.insert(r[i], v) 
  end
  return r
end

function common.err(asst, str)
  if str==nil then str="MISSING ERROR!" end
  if asst==false then error(str) end
end

function common.broadcast(v,n)
  return common.map( common.range(n), function(i) return v end )
end

-- low, high are inclusive
function common.slice(t,low,high) 
  assert( type(t)=="table" )
  assert( type(low)=="number" )
  assert( type(high)=="number" )
  assert( low<=high )
  return common.map( common.range(low,high), function(i) return t[i] end )
end

function common.shallowCopy(t)
  common.err(type(t)=="table","shallowCopy: input must be table")
  local n = {}
  for k,v in pairs(t) do n[k] = v end
  return n
end

-- choose a key out of table
function common.choose(t)
  for k,v in pairs(t) do return k end
end

-- given t = {k1={a,b}, k2={c,d}}, this will return
-- [ {k1=a,k2=c},{k1=a,k2=d},{k1=b,k2=c},{k1=b,k2=d} ]
function common.cartesian(t)
  -- base case
  if common.keycount(t)==1 then
    local tmp = {}
    local k = common.choose(t)
    local v = t[k]

    for __,vv in ipairs(v) do 
      local ttmp = {}
      ttmp[k] = vv
      table.insert(tmp,ttmp)
    end
    return tmp
  end

  local tmpt = common.shallowCopy(t)
  local k = common.choose(t)
  print("CHOOSE",k)
  local v = t[k]
  tmpt[k] = nil
  local list = common.cartesian(tmpt)
  print("LIST",#list)

  -- form product
  local out = {}
  for _,thisv in ipairs(v) do
    for __,vv in ipairs(list) do
      local tt = {}
      tt[k] = thisv

      for kkk,vvv in pairs(vv) do
        tt[kkk] = vvv
      end
      
      table.insert(out,tt)
    end
  end

  return out
end

-- is this an array of identical elements?
function common.allTheSame(t)
  local allTheSame = true

  for k,v in ipairs(t) do
    if v~=t[1] then allTheSame=false end
  end

  return allTheSame
end

if terralib~=nil then require "commonTerra".export(common) end

function common.export(t)
  if t==nil then t=_G end
  for k,v in pairs(common) do rawset(t,k,v) end
end

function common.verilogCheckReserved(k)
  if k=="input" or k=="output" or k=="reg" or k=="edge" or k=="final" or k=="solve" then
    print("Error, variable name ",k," is a reserved keyword in verilog")
    assert(false)
  end

  if tonumber(k:sub(1,1))~=nil then
    common.err(false, "verilog variables cant start with numbers ("..k..")")
  end
end

function common.verilogSanitizeInner(s)
  --local s = s:gsub('%W','_')
  local s = s:gsub("%[","_OB_")
  s = s:gsub("%]","_CB_")
  s = s:gsub("%(","_OP_")
  s = s:gsub("%)","_CP_")
  s = s:gsub("%{","_OC_")
  s = s:gsub("%}","_CC_")
  s = s:gsub("%,","_CO_")
  s = s:gsub("%.","_P_")
  s = s:gsub("%W","_")
  s = s:gsub('%__','_')

  return s
end

-- hack: running only one round of sanitize may leave unsanitized stuff
function common.verilogSanitize(s)
  local a = common.verilogSanitizeInner(s)

  while(true) do
    local b = common.verilogSanitizeInner(a)
    if(a==b) then return b end
    a=b
  end
end

common.sanitize = common.verilogSanitize

function common.fileExists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

-- uniquify a table
local __uniqCache = {}
function common.uniq(t)
  if type(t)=="number" or type(t)=="string" then
    return t
  elseif type(t)=="table" then
    local out = {}
    assert(#t==common.keycount(t))
    for _,v in ipairs(t) do table.insert(out,common.uniq(v)) end
    if __uniqCache[#t]==nil then __uniqCache[#t]={} end
    return common.deepsetweak(__uniqCache[#t],out,out)
  else
    assert(false)
  end
end

return common
