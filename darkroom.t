local IR = require("ir")
local types = require("types")
local simmodules = require("simmodules")
local fpgamodules = require("fpgamodules")
local cstring = terralib.includec("string.h")
local cstdlib = terralib.includec("stdlib.h")
local cstdio = terralib.includec("stdio.h")
local cmath = terralib.includec("math.h")
local ffi = require("ffi")
local S = require("systolic")

-- We can operate in 2 different modes: either we stream frames continuously (STREAMING==true), or we only do one frame (STREAMING==false). 
-- If STREAMING==false, we artificially cap the output once the expected number of pixels is reached. This is needed for some test harnesses
STREAMING = false

darkroom = {}

DEFAULT_FIFO_SIZE = 2048*16*16

darkroom.State = types.opaque("state")
darkroom.StateR = types.opaque("stateR")
darkroom.Handshake = types.opaque("handshake")
darkroom.Registered = types.opaque("registered")
function darkroom.Stateful(A) return types.tuple({A,darkroom.State}) end
function darkroom.StatefulV(A) return types.tuple({types.tuple({A, types.bool()}), darkroom.State}) end
function darkroom.StatefulRV(A) return types.tuple({types.tuple({A, types.bool()}),darkroom.StateR}) end
function darkroom.StatefulHandshake(A) return types.tuple({ A, darkroom.State, darkroom.Handshake }) end
function darkroom.StatefulHandshakeRegistered(A) return types.tuple({ A, darkroom.State, darkroom.Handshake, darkroom.Registered }) end
function darkroom.Sparse(A,W,H) return types.array2d(types.tuple({A,types.bool()}),W,H) end

struct EmptyState {}
terra EmptyState:init() end

darkroom.data = macro(function(i) return `i._0 end)
local data = darkroom.data
darkroom.valid = macro(function(i) return `i._1 end)
local valid = darkroom.valid
darkroom.ready = macro(function(i) return `i._2 end)
local ready = darkroom.ready


function darkroom.isStateful( a ) return (a==darkroom.State or a==darkroom.StateR) or (a:isTuple() and (a.list[2]==darkroom.State or a.list[2]==darkroom.StateR or darkroom.isStateful(a.list[1]))) end
function darkroom.isStatefulHandshake( a ) return a:isTuple() and a.list[2]==darkroom.State and a.list[3]==darkroom.Handshake end
function darkroom.isStatefulHandshakeRegistered( a ) return a:isTuple() and a.list[2]==darkroom.State and a.list[3]==darkroom.Handshake and a.list[4]==darkroom.Registered end
function darkroom.isStatefulV( a ) return a:isTuple() and a.list[1]:isTuple() and a.list[2]==darkroom.State and a.list[1].list[2]==types.bool() and a.list[1].list[3]==nil end
function darkroom.isStatefulRV( a ) return a:isTuple() and a.list[1]:isTuple() and a.list[2]==darkroom.StateR and a.list[1].list[2]==types.bool() end
function darkroom.isPure( a ) return darkroom.isStateful(a)==false and darkroom.isStatefulHandshake(a)==false end
function darkroom.expectPure( A, er ) if darkroom.isPure(A)==false then error(er or "type should be pure but is "..tostring(A)) end end
function darkroom.expectStateful( A, er ) if darkroom.isStateful(A)==false or darkroom.isStatefulV(A) or darkroom.isStatefulRV(A) then error(er or "type should be stateful") end end
function darkroom.expectStatefulV( A, er ) if darkroom.isStatefulV(A)==false then error(er or "type should be statefulV") end end
function darkroom.expectStatefulRV( A, er ) if darkroom.isStatefulRV(A)==false then error(er or "type should be statefulRV") end end
function darkroom.expectStatefulHandshake( A, er ) if darkroom.isStatefulHandshake(A)==false then error(er or "type should be stateful handshake") end end

-- takes StatefulHandshakeRegistered to StatefulHandshake
function darkroom.stripRegistered( a, loc )
  if a:isTuple() then
    return types.tuple( map(a.list, function(t) assert(darkroom.isStatefulHandshakeRegistered(t)); return darkroom.StatefulHandshake(t.list[1]) end ) )
  end
  assert(false)
end

function darkroom.extractStateful( a, loc )
  if darkroom.isStateful(a)==false then error("Not a stateful input, "..loc) end
  return a.list[1]
end

-- extractV(StatefulV(A)) == A
function darkroom.extractV( a, loc )
  if darkroom.isStatefulV(a)==false then error("Not a statefulV input, ") end
  return a.list[1].list[1]
end

-- extractRV(StatefulRV(A)) == A
function darkroom.extractRV( a, loc )
  if darkroom.isStatefulRV(a)==false then error("Not a statefulRV input, ") end
  return a.list[1].list[1]
end

-- extract takes the darkroom, and returns the type that should be used by the terra/systolic process function
-- ie Stateful(A) => A
-- StatefulV(A) => {A,bool}
-- StatefulRV(A) => {A,bool}
-- StatefulHandshake(A) => {A,bool}
function darkroom.extract( a, loc )
  if a==darkroom.State then return types.null() end
  if darkroom.isStatefulHandshake(a) or darkroom.isStatefulHandshakeRegistered(a) then
    return types.tuple({a.list[1],types.bool()})
  end
  if a:isTuple() and darkroom.isStateful(a.list[1]) then
    return types.tuple(map(a.list, function(n) assert(darkroom.isStateful(n)); return darkroom.extract(n) end))
  end
  if darkroom.isStateful(a)==false and darkroom.isStatefulHandshake(a)==false then return a end

  return a.list[1]
end

-- extract underlying actual data type.
-- ie Stateful(A) => A
-- StatefulV(A) => A
-- StatefulRV(A) => A
-- StatefulHandshake(A) => A
function darkroom.extractData(a)
  if darkroom.isStatefulHandshake(a) then return a.list[1]
  elseif darkroom.isStatefulV(a) then return darkroom.extractV(a)
  elseif darkroom.isStatefulRV(a) then return darkroom.extractRV(a)
  elseif darkroom.isStateful(a) then return darkroom.extract(a)
  elseif darkroom.isPure(a) then return a
  else print("extractdata",a); assert(false) end
end

function darkroom.extractStatefulHandshake( a, loc )
  if darkroom.isStatefulHandshake(a)==false then error("Not a stateful handshake input, ") end
  return a.list[1]
end


-- tab should be a table of systolic ASTs, all type array2d. Heights should match
function concat2dArrays(tab)
  assert(type(tab)=="table")
  assert(#tab>0)
  assert( systolic.isAST(tab[1]))
  local H, ty = (tab[1].type:arrayLength())[2], tab[1].type:arrayOver()
  local totalW = 0
  local res = {}

  for y=0,H-1 do
    for _,v in ipairs(tab) do
      assert( systolic.isAST(v) )
      assert( v.type:isArray() )
      assert( H==(v.type:arrayLength())[2] )
      assert( ty==v.type:arrayOver() )
      local w = (v.type:arrayLength())[1]
      if y==0 then totalW = totalW + w end
      table.insert(res, S.slice( v, 0, w-1, y, y ) )
    end
  end

  return S.cast( S.tuple(res), types.array2d(ty,totalW,H) )
end

function darkroom.print(TY,inp)
  local stats = {}
  local TY = darkroom.extract(TY)
  if TY:isTuple() then
    table.insert(stats,quote cstdio.printf("{") end)
    for i=1,#TY.list do
      table.insert(stats,darkroom.print(TY.list[i],`&inp.["_"..(i-1)]))
      table.insert(stats,quote cstdio.printf(",") end)
    end
    table.insert(stats,quote cstdio.printf("}") end)
  elseif TY:isArray() then
    table.insert(stats,quote cstdio.printf("[") end)
    for i=0,TY:channels()-1 do
      table.insert(stats,darkroom.print(TY:arrayOver(),`&(@inp)[i]))
      table.insert(stats,quote cstdio.printf(",") end)
    end
    table.insert(stats,quote cstdio.printf("]") end)
  elseif TY:isBool() then
    table.insert(stats,quote if @inp then cstdio.printf("true") else cstdio.printf("false") end end)
  elseif TY:isInt() or TY:isUint() then
    table.insert(stats,quote cstdio.printf("%d",@inp) end)
  elseif TY==types.null() then
  else
    print(TY)
    assert(false)
  end
  return quote stats; end
end

darkroomFunctionFunctions = {}
darkroomFunctionMT={__index=darkroomFunctionFunctions}

function darkroomFunctionFunctions:compile() return self.terraModule end
function darkroomFunctionFunctions:toVerilog() return self.systolicModule:getDependencies()..self.systolicModule:toVerilog() end

function darkroom.newFunction(tab)
  assert( type(tab) == "table" )
  return setmetatable( tab, darkroomFunctionMT )
end

darkroomIRFunctions = {}
setmetatable( darkroomIRFunctions,{__index=IR.IRFunctions})
darkroomIRMT = {__index = darkroomIRFunctions }

function darkroom.newIR(tab)
  assert( type(tab) == "table" )
  IR.new( tab )
  return setmetatable( tab, darkroomIRMT )
end

local __sdfTotalCache = {}
-- assume that inputs have SDF rate {1,1}, then what is the rate of this node?
function darkroomIRFunctions:sdfTotal()
  if __sdfTotalCache[self]==nil then
    local res
    if self.kind=="input" or self.kind=="constant" then
      res = {1,1}
    elseif self.kind=="extractState" then
      res = self.inputs[1]:sdfTotal()
    elseif self.kind=="apply" then
      assert(#self.inputs==1)
      local I = self.inputs[1]:sdfTotal()
      err( type(self.fn.sdfInput)=="table", "Missing SDF rate for fn "..self.fn.kind)
      local R = { self.fn.sdfOutput[1]*self.fn.sdfInput[2], self.fn.sdfOutput[2]*self.fn.sdfInput[1] } -- output/input ratio
      local On, Od = simplify(I[1]*R[1], I[2]*R[2])
      res = {On,Od}
    elseif self.kind=="tuple" then
      local IR
      -- all input rates must match!
      for key,i in pairs(self.inputs) do
        if darkroom.extractData(i.type ):const() then
          -- we don't care about SDF rates on constants
        else
          local isdf = i:sdfTotal(); 
          if IR==nil then IR=isdf end
          err(isdf[1]==IR[1] and isdf[2]==IR[2], "tuple mismatched SDF rate. [1]="..isdf[1].."/"..isdf[2].." ["..key.."]="..IR[1].."/"..IR[2]..", loc"..self.loc)
        end
      end

      res = IR
    else
      print("sdftotal",self.kind)
      assert(false)
    end
    __sdfTotalCache[self]=res
  end
  return __sdfTotalCache[self]
end

-- assuming that the inputs are running at {1,1}, what is the utilization of this node?
-- 0.5: only active every other cycle. 2: somehow active twice a cycle? (a bug)
function darkroomIRFunctions:sdfUtilization()
  if self.kind=="apply" then
    local total = self:sdfTotal()

    -- by convention, either input or output (or both) are running at a rate of 1.
    -- (we don't intentially design modules that sit idle)
    -- we can then look at the rate on the end with rate==1 to find the utilization
    -- 1-> (1/N): a downsample
    -- (1/N) -> 1 : a upsample
    -- 1->1 no rate change

    if   (self.fn.sdfOutput[1]/self.fn.sdfOutput[2])==1 then
      -- this also covers the case where inputRate==1/1
      return total[1]/total[2]
    elseif (self.fn.sdfInput[1]/self.fn.sdfInput[2])==1 then
      local tot = self.inputs[1]:sdfTotal()
      return tot[1]/tot[2]
    else
      assert(false)
    end
  else
    assert(false)
  end
end

-- assuming that the inputs are running at {1,1}, wht is the lowest/highest SDF utilization in this DAG?
-- (this will limit the speed of the whole pipe)
-- In our implementaiton, the utilization of any node can't be >1, so if the highest utilization is >1, we need to scale the throughput of the whole pipe
local __sdfExtremeUtilizationCache = {}
function darkroomIRFunctions:sdfExtremeUtilization(highest)
  assert(type(highest)=="boolean")

  if __sdfExtremeUtilizationCache[self]==nil then
    __sdfExtremeUtilizationCache[self]={}
  end

  if __sdfExtremeUtilizationCache[self][highest]==nil then
    if self.kind=="apply" then
      --print("WORST",self.fn.kind)
      local r = self:sdfUtilization()

      -- leaf functions can't have a worse utilization than their input/output rate.
      -- lambdas however can: (you can run something slow in the middle)
      local fnloc = ""
      if self.fn.kind=="lambda" then
        r = r*self.fn.output:sdfExtremeUtilization(highest)
        local a,b = self.fn.output:sdfExtremeUtilization(highest)
        fnloc = b
      end

      --local res = math.min(self.inputs[1]:sdfExtremeUtilization(highest), r)
      --if highest then res=math.max(self.inputs[1]:sdfExtremeUtilization(highest),r) end

      --__sdfExtremeUtilizationCache[self][highest] = {res
      if highest and r>=self.inputs[1]:sdfExtremeUtilization(highest) then
        __sdfExtremeUtilizationCache[self][highest] = {r,self.loc.."; "..fnloc}
      elseif highest==false and r<=self.inputs[1]:sdfExtremeUtilization(highest) then
        __sdfExtremeUtilizationCache[self][highest] = {r,self.loc..";"..fnloc}
      else
        local a,b = self.inputs[1]:sdfExtremeUtilization(highest)
        __sdfExtremeUtilizationCache[self][highest] = {a,b}
      end
    else
      -- don't care. just set it to default value
      __sdfExtremeUtilizationCache[self][highest] = {1,"NONE"}
    end
  end
  return __sdfExtremeUtilizationCache[self][highest][1], __sdfExtremeUtilizationCache[self][highest][2]
end

function darkroomIRFunctions:typecheck()
  return self:process(
    function(n)
      if n.kind=="apply" then
        assert( types.isType( n.inputs[1].type ) )
        if n.fn.inputType~=n.inputs[1].type then error("Input type mismatch. Is "..tostring(n.inputs[1].type).." but should be "..tostring(n.fn.inputType)..", "..n.loc) end
        n.type = n.fn.outputType
        return darkroom.newIR( n )
      elseif n.kind=="applyRegLoad" then
        if n.inputs[1].type~=darkroom.State then error("input to reg load must be state, "..n.loc) end
        n.type = darkroom.stripRegistered(n.fn.outputType)
        return darkroom.newIR( n )
      elseif n.kind=="applyRegStore" then
        if n.inputs[1].type~=darkroom.stripRegistered(n.fn.inputType) then error("input to reg store has incorrect type, should be "..tostring(darkroom.stripRegistered(n.fn.inputType)).." but is "..tostring(n.inputs[1].type)..", "..n.loc) end
        n.type = darkroom.State
        return darkroom.newIR( n )
      elseif n.kind=="input" then
      elseif n.kind=="constant" then
      elseif n.kind=="extractState" then
        if darkroom.isStateful(n.inputs[1].type)==false then error("input to extractState must be stateful") end
      elseif n.kind=="catState" then
        n.type = n.inputs[1].type
        return darkroom.newIR(n)
      elseif n.kind=="tuple" then
        n.type = types.tuple( map(n.inputs, function(v) return v.type end) )
        return darkroom.newIR(n)
      else
        print(n.kind)
        assert(false)
      end
    end)
end

function darkroom.isFunction(t) return getmetatable(t)==darkroomFunctionMT end
function darkroom.isIR(t) return getmetatable(t)==darkroomIRMT end

-- This converts SoA to AoS
-- ie {Arr2d(a,W,H),Arr2d(b,W,H),...} to Arr2d({a,b,c},W,H)
function darkroom.SoAtoAoS( W, H, typelist )
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(typelist)=="table")

  local res = {kind="SoAtoAoS", W=W,H=H}

  res.inputType = types.tuple( map(typelist, function(t) return types.array2d(t,W,H) end) )
  res.outputType = types.array2d(types.tuple(typelist),W,H)
  res.sdfInput, res.sdfOutput = {1,1},{1,1}
  res.delay = 0
  local struct PackTupleArrays { }
  terra PackTupleArrays:reset() end
  print("IP",res.inputType,darkroom.extract(res.inputType))
  print("oP",res.outputType,darkroom.extract(res.outputType))
  terra PackTupleArrays:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    for c = 0, [W*H] do
      (@out)[c] = { [map(range(0,#typelist-1), function(i) return `(inp.["_"..i])[c] end ) ] }
    end
  end
  res.terraModule = PackTupleArrays

  res.systolicModule = S.moduleConstructor("packTupleArrays_"..(tostring(typelist):gsub('%W','_'))):CE(true)
  local sinp = S.parameter("process_input", res.inputType )
  local arrList = {}
  for y=0,H-1 do
    for x=0,W-1 do
      table.insert( arrList, S.tuple(map(range(0,#typelist-1), function(i) return S.index(S.index(sinp,i),x,y) end)) )
    end
  end
  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast(S.tuple(arrList),darkroom.extract(res.outputType)), "process_output") )
  --res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro") )

  return darkroom.newFunction(res)
end

-- converts {Stateful(a), Stateful(b)...} to Stateful{a,b}
-- Also {StatefulHandshake(a), StatefulHandshake(b)...} to StatefulHandshake{a,b}
-- typelist should be a table of pure types
function darkroom.packTuple( typelist, handshake )
  assert(type(typelist)=="table")
  err( handshake==nil or type(handshake)=="boolean", "handshake argument should be bool")

  local res = {kind="packTuple", handshake=handshake}

  map(typelist, function(t) darkroom.expectPure(t) end )
  res.inputType = types.tuple( map(typelist, function(t) return sel( handshake, darkroom.StatefulHandshake(t), darkroom.Stateful(t) ) end) )
  res.outputType = darkroom.Stateful( types.tuple(typelist) )
  if handshake then res.outputType = darkroom.StatefulHandshake( types.tuple(typelist) ) end
  res.sdfInput,res.sdfOutput = {1,1},{1,1}
  res.delay = 0
  local struct PackTuple { }

  terra PackTuple:stats(name:&int8)  end
  print("IP",res.inputType,darkroom.extract(res.inputType))
  print("oP",res.outputType,darkroom.extract(res.outputType))
  
  if handshake then
    -- ignore the valid bit on const stuff: it is always considered valid
    local activePorts = {}
    for k,v in ipairs(typelist) do if v:const()==false then table.insert(activePorts, k) end end
      for k,v in ipairs(activePorts) do print("ACTIVEPORT",k,v) end

    map( activePorts, function(k) table.insert(PackTuple.entries,{field="FIFO"..k, type=simmodules.fifo( typelist[k]:toTerraType(), DEFAULT_FIFO_SIZE, "makeHandshake")}) end )
    terra PackTuple:reset() [map(activePorts, function(i) return quote self.["FIFO"..i]:reset() end end)] end
    terra PackTuple:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
      [map(activePorts, function(i) return quote if valid(inp.["_"..(i-1)]) then self.["FIFO"..i]:pushBack(&data(inp.["_"..(i-1)])) end end end )]

      var hasData = [foldt(map(activePorts, function(i) return `self.["FIFO"..i]:hasData() end ), andopterra, true )]
      if hasData then
        data(out) = { [map( typelist, function(t,k) if t:const() then print("CONST",k);return `data(inp.["_"..(k-1)]) else print("NOTCONST",k);return `@(self.["FIFO"..k]:popFront()) end end ) ] }
        valid(out) = true
      else
        valid(out) = false
      end
    end
  else
    terra PackTuple:reset() end
    terra PackTuple:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
      @out = { [map(range(0,#typelist-1), function(i) return `inp.["_"..i] end ) ] }
    end
  end

  res.terraModule = PackTuple

  res.systolicModule = S.moduleConstructor("packTuple_"..tostring(typelist))
  local sinp = S.parameter("process_input", darkroom.extract(res.inputType) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro") )

  if handshake then
    res.systolicModule:onlyWire(true)
    res.systolicModule:CE(false) -- nothing to stall

    local activePorts={}
    for k,v in pairs(typelist) do if v:const()==false then table.insert(activePorts,k) end end
    --local activePorts = filter(typelist, function(t,k) activePort=k; return t:const()==false end )
    err(#activePorts<=1, "NYI - packTuple with multiple active ports! This needs a fifo along all but one of the edges")

    local outv = S.tuple(map(range(0,#typelist-1), function(i) return S.index(S.index(sinp,i),0) end))

    -- valid bit is the AND of all the inputs
    --local valid = foldt(map(range(0,#typelist-1),function(i) return S.index(S.index(sinp,i),1) end),function(a,b) return S.__and(a,b) end,"X")
    local valid = S.index(S.index(sinp,activePorts[1]-1),1)
    print("VALID",systolic.isAST(valid),valid)
    local out = S.tuple{outv, valid}
    res.systolicModule:addFunction( S.lambda("process", sinp, out:disablePipelining(), "process_output") )

    -- built-in behavior with ready bits is to AND all the downstreams together. So we don't actully have to do anything
    local downstreamReady = S.parameter("ready_downstream", types.bool())
    res.systolicModule:addFunction( S.lambda("ready", downstreamReady, downstreamReady, "ready" ) )
  else
    res.systolicModule:CE(true)
    local outv = S.tuple(map(range(0,#typelist-1), function(i) return S.index(sinp,i) end))
    res.systolicModule:addFunction( S.lambda("process", sinp, outv, "process_output") )
  end

  return darkroom.newFunction(res)
end

-- takes {Stateful(a[W,H]), Stateful(b[W,H]),...} to Stateful( {a,b}[W,H] )
-- typelist should be a table of pure types
function darkroom.SoAtoAoSStateful( W,H, typelist) return darkroom.compose("SoAtoAoSStateful", darkroom.makeStateful(darkroom.SoAtoAoS(W,H,typelist)), darkroom.packTuple( map(typelist, function(t) return types.array2d(t,W,H) end) ) ) end

-- Takes A[W,H] to A[W,H], but with a border around the edges determined by L,R,B,T
function darkroom.border(A,W,H,L,R,B,T,value)
  map({W,H,L,R,T,B,value},function(n) assert(type(n)=="number") end)
  local res = {kind="border",L=L,R=R,T=T,B=B,value=value}
  res.inputType = types.array2d(A,W,H)
  res.outputType = res.inputType
  res.sdfInput, res.sdfOutput = {1,1},{1,1}
  res.delay = 0
  local struct Border {}
  terra Border:reset() end
  terra Border:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for y=0,H do for x=0,W do 
        if x<L or y<B or x>=W-R or y>=H-T then
          (@out)[y*W+x] = [value]
        else
          (@out)[y*W+x] = (@inp)[y*W+x]
        end
    end end
  end
  res.terraModule = Border
  return darkroom.newFunction(res)
end

function darkroom.liftStateful(f)
  local res = {kind="liftStateful", fn = f}
  darkroom.expectStateful(f.inputType)
  darkroom.expectStateful(f.outputType)
  res.inputType = darkroom.Stateful(darkroom.extract(f.inputType))
  res.outputType = darkroom.StatefulV(darkroom.extract(f.outputType))
  res.sdfInput, res.sdfOutput = {1,1},{1,1}
  res.delay = f.delay
  local struct LiftStateful { inner : f.terraModule}
  terra LiftStateful:reset() self.inner:reset() end
  terra LiftStateful:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    self.inner:process(inp,&data(out))
    valid(out) = true
  end
  res.terraModule = LiftStateful
  res.systolicModule = S.moduleConstructor("LiftStateful_"..f.systolicModule.name):CE(true)
  local inner = res.systolicModule:add( f.systolicModule:instantiate("LiftStateful_inner") )
  local sinp = S.parameter("process_input", darkroom.extract(res.inputType) )
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ inner:process(sinp), S.constant(true, types.bool())}, "process_output" ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {},S.parameter("reset",types.bool())) )
  res.systolicModule:complete()
  return darkroom.newFunction(res)
end

-- f should be Stateful->StatefulRV
-- You should never use Stateful->StatefulRV directly! S->SRV's input should be valid iff ready==true. This is not the case with normal Stateful functions!
function darkroom.waitOnInput(f)
  local res = {kind="waitOnInput", fn = f}
  darkroom.expectStateful(f.inputType)
  darkroom.expectStatefulRV(f.outputType)
  res.inputType = darkroom.StatefulV(darkroom.extract(f.inputType))
  res.outputType = f.outputType

  err( type(f.sdfInput)=="table", "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput

  res.delay = f.delay
  local struct WaitOnInput { inner : f.terraModule }
  terra WaitOnInput:reset() self.inner:reset() end
  terra WaitOnInput:stats(name:&int8) self.inner:stats(name) end
  terra WaitOnInput:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    if self.inner:ready()==false or valid(inp) then
      if xor(self.inner:ready(),valid(inp)) then 
        cstdio.printf("XOR %d %d\n",self.inner:ready(),valid(inp))
        darkroomAssert(false,"waitOnInput valid bit doesnt match ready bit") 
      end

      self.inner:process(&data(inp),out)
    else
      valid(out) = false
    end
  end
  terra WaitOnInput:ready() return self.inner:ready() end
  res.terraModule = WaitOnInput

  err( f.systolicModule:getDelay("ready")==0, "ready bit should not be pipelined")
  res.systolicModule = S.moduleConstructor("WaitOnInput_"..f.systolicModule.name):CE(true)
  local inner = res.systolicModule:add( f.systolicModule:instantiate("WaitOnInput_inner") )
  local asstInst = res.systolicModule:add( S.module.assert( "waitOnInput valid bit doesn't match ready bit"):instantiate("asstInst") )
  local printInst = res.systolicModule:add( S.module.print( types.tuple{types.bool(),types.bool(),types.bool(),types.bool()}, "WaitOnInput "..f.systolicModule.name.." ready %d validIn %d runable %d RST %d", true ):instantiate("printInst") )

  local sinp = S.parameter("process_input", darkroom.extract(res.inputType) )
  local svalid = S.parameter("process_valid", types.bool())
  local runable = S.__or(S.__not(inner:ready()), S.index(sinp,1) ):disablePipelining()
--  local runable = inner:ready():disablePipelining()
  local out = inner:process( S.index(sinp,0), runable )
  local RST = S.parameter("reset",types.bool())
  if f.systolicModule.functions.reset:isPure() then RST=S.constant(false,types.bool()) end

  local pipelines = {}
  -- Actually, it's ok for (ready==false and valid(inp)==true) to be true. We do not have to read when ready==false, we can just ignore it.
--  table.insert( pipelines, asstInst:process(S.__not(S.__and(S.eq(inner:ready(),S.constant(false,types.bool())),S.index(sinp,1)))):disablePipelining() )
  table.insert( pipelines, printInst:process( S.tuple{inner:ready(),S.index(sinp,1), runable, RST} ) )

  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ S.index(out,0), S.__and(S.index(out,1),S.__and(runable,svalid):disablePipelining()) }, "process_output", pipelines, svalid ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {}, RST) )
  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), inner:ready(), "ready", {} ) )

  return darkroom.newFunction(res)
end


darkroom.liftDecimate = memoize(function(f)
  assert(darkroom.isFunction(f))
  local res = {kind="liftDecimate", fn = f}
  darkroom.expectStateful(f.inputType)
  darkroom.expectStatefulV(f.outputType)
  res.inputType = darkroom.StatefulV(darkroom.extract(f.inputType))
  res.outputType = darkroom.StatefulRV(darkroom.extractV(f.outputType))

  err( type(f.sdfInput)=="table", "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput

  res.delay = f.delay
  local struct LiftDecimate { inner : f.terraModule; idleCycles:int, activeCycles:int}
  terra LiftDecimate:reset() self.inner:reset(); self.idleCycles = 0; self.activeCycles=0; end
  terra LiftDecimate:stats(name:&int8) cstdio.printf("LiftDecimate %s utilization %f\n",name,[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end
  terra LiftDecimate:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    if valid(inp) then
      self.inner:process(&data(inp),[&darkroom.extract(f.outputType):toTerraType()](out))
      self.activeCycles = self.activeCycles + 1
    else
      valid(out) = false
      self.idleCycles = self.idleCycles + 1
    end
  end
  terra LiftDecimate:ready() return true end
  res.terraModule = LiftDecimate

  err( f.systolicModule~=nil, "Missing systolic for "..f.kind )
  res.systolicModule = S.moduleConstructor("LiftDecimate_"..f.systolicModule.name):CE(true)
  local inner = res.systolicModule:add( f.systolicModule:instantiate("LiftDecimate_inner_"..f.systolicModule.name) )
  local sinp = S.parameter("process_input", darkroom.extract(res.inputType) )
  local pout = inner:process(S.index(sinp,0),S.index(sinp,1))
  local pout_data = S.index(pout,0)
  local pout_valid = S.index(pout,1)

  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{pout_data, S.__and(pout_valid,S.index(sinp,1))}, "process_output" ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {},S.parameter("reset",types.bool())) )
  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), S.constant(true,types.bool()), "ready", {} ) )

  return darkroom.newFunction(res)
                                end)

function darkroom.RPassthrough(f)
  local res = {kind="RPassthrough", fn = f}
  darkroom.expectStatefulV(f.inputType)
  darkroom.expectStatefulRV(f.outputType)
  res.inputType = darkroom.StatefulRV(darkroom.extractV(f.inputType))
  res.outputType = darkroom.StatefulRV(darkroom.extractRV(f.outputType))
  err( type(f.sdfInput)=="table", "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  res.delay = f.delay
  local struct RPassthrough { inner : f.terraModule}
  terra RPassthrough:reset() self.inner:reset() end
  terra RPassthrough:stats( name : &int8 ) self.inner:stats(name) end
  terra RPassthrough:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    self.inner:process([&darkroom.extract(f.inputType):toTerraType()](inp),out)
  end
  terra RPassthrough:ready( inp:bool ) return inp and self.inner:ready() end
  res.terraModule = RPassthrough

  err( f.systolicModule~=nil, "RPassthrough null module "..f.kind)
  res.systolicModule = S.moduleConstructor("RPassthrough_"..f.systolicModule.name):CE(true)
  local inner = res.systolicModule:add( f.systolicModule:instantiate("RPassthrough_inner") )
  local sinp = S.parameter("process_input", darkroom.extract(res.inputType) )

  -- this is dumb: we don't actually use the 'ready' bit in the struct (it's provided by the ready function).
  -- but we include it to distinguish the types.
  local out = inner:process( S.tuple{ S.index(sinp,0), S.index(sinp,1)} )
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ S.index(out,0), S.index(out,1) }, "process_output" ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {}, S.parameter("reset",types.bool())) )
  local rinp = S.parameter("ready_input", types.bool() )
  res.systolicModule:addFunction( S.lambda("ready", rinp, S.__and(inner:ready(),rinp):disablePipelining(), "ready", {} ) )

  return darkroom.newFunction(res)
end

function darkroom.RVPassthrough(f)
  return darkroom.RPassthrough(darkroom.liftDecimate(darkroom.liftStateful(f)))
end

darkroom.liftHandshake = memoize(function(f)
  local res = {kind="liftHandshake", fn=f}
  darkroom.expectStatefulV(f.inputType)
  darkroom.expectStatefulRV(f.outputType)
  res.inputType = darkroom.StatefulHandshake(darkroom.extractV(f.inputType))
  res.outputType = darkroom.StatefulHandshake(darkroom.extractRV(f.outputType))
  print("LIFT HANDSHAKE",f.outputType,res.outputType)

  err(type(f.sdfInput)=="table", "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput

  --assert(f.delay>0)
  local delay = math.max(1, f.delay)

  local struct LiftHandshake{ delaysr: simmodules.fifo( darkroom.extract(f.outputType):toTerraType(), delay, "liftHandshake"),
                              fifo: simmodules.fifo( darkroom.extractStatefulHandshake(res.inputType):toTerraType(), DEFAULT_FIFO_SIZE, "liftHandshakefifo"),
                              inner: f.terraModule}
  terra LiftHandshake:reset() self.delaysr:reset(); self.fifo:reset(); self.inner:reset() end
  terra LiftHandshake:stats(name:&int8) 
    cstdio.printf("LiftHandshake %s, Max input fifo size: %d\n", name, self.fifo:maxSizeSeen())
    self.inner:stats(name) 
  end

  terra LiftHandshake:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    if valid(inp) then
      self.fifo:pushBack(&data(inp))
    end

    if self.delaysr:size()==delay then
      var ot = self.delaysr:popFront()
      valid(out) = valid(ot)
      data(out) = data(ot)
    else
      valid(out) = false
    end

    var tinp : darkroom.extract(f.inputType):toTerraType()
    var tout : darkroom.extract(f.outputType):toTerraType()
    valid(tinp) = false
    if self.fifo:hasData() and self.inner:ready() then
      data(tinp) = @(self.fifo:popFront())
      valid(tinp) = true
    end
    self.inner:process(&tinp,&tout)
    self.delaysr:pushBack(&tout)
  end
  res.terraModule = LiftHandshake

  res.systolicModule = S.moduleConstructor( "LiftHandshake_"..f.systolicModule.name ):onlyWire(true):parameters({INPUT_COUNT=0, OUTPUT_COUNT=0})
  local printInst = res.systolicModule:add( S.module.print( types.tuple{types.bool(),darkroom.extractV(f.inputType),types.bool(),darkroom.extractRV(f.outputType),types.bool(),types.bool(),types.bool(),types.uint(16), types.uint(16)}, "RST %d I %h IV %d O %h OV %d DS %d ready %d outputCount %d expectedOutputCount %d", true):instantiate("printInst") )
  local outputCount
  local iif = fpgamodules.incIf()
  assert(S.isModule(iif))
  if STREAMING==false then outputCount = res.systolicModule:add( S.module.regByConstructor( types.uint(16), iif ):includeCE():instantiate("outputCount"):setCoherent(false) ) end

  local inner = res.systolicModule:add(f.systolicModule:instantiate("inner_"..f.systolicModule.name))
  local pinp = S.parameter("process_input", darkroom.extract(res.inputType) )

  local rst = S.parameter("reset",types.bool())
  local pout = inner:process(pinp,S.__not(rst))

  local downstreamReady = S.parameter("ready_downstream", types.bool())
  -- not blocked downstream: either downstream is ready (downstreamReady), or we don't have any data anyway (pout[1]==false), so we can work on clearing the pipe
  local notBlockedDownstream = S.__or(downstreamReady, S.eq(S.index(pout,1),S.constant(false,types.bool()) ))
  local CE = notBlockedDownstream

  -- the point of the shift register: systolic doesn't have an output valid bit, so we have to explicitly calculate it.
  -- basically, for the first N cycles the pipeline is executed, it will have garbage in the pipe (valid was false at the time those cycles occured). So we need to gate the output by the delayed valid bits. This is a little big goofy here, since process_valid is always true, except for resets! It's not true for the first few cycles after resets! And if we ignore that the first few outputs will be garbage!
  local SR = res.systolicModule:add( fpgamodules.shiftRegister( types.bool(), f.systolicModule:getDelay("process"), "LiftHandshakeValidBitDelay_"..f.systolicModule.name.."_"..f.systolicModule:getDelay("process"), false ):CE(true):instantiate("validBitDelay_"..f.systolicModule.name) )
  
  local srvalue = SR:pushPop(S.constant(true,types.bool()), S.__not(rst))
  local outvalid = S.__and(S.index(pout,1), srvalue )
  local outvalidRaw = outvalid
  --if STREAMING==false then outvalid = S.__and( outvalid, S.lt(outputCount:get(),S.instanceParameter("OUTPUT_COUNT",types.uint(16)))) end
  local out = S.tuple{ S.index(pout,0), outvalid }

  local pipelines = {}
  pipelines[1] = printInst:process( S.tuple{ rst, S.index(pinp,0), S.index(pinp,1), S.index(out,0), S.index(out,1), notBlockedDownstream, inner:ready(), outputCount:get(), S.instanceParameter("OUTPUT_COUNT",types.uint(16)) } )
  if STREAMING==false then table.insert(pipelines,  outputCount:setBy(outvalid, S.__not(rst)) ) end

  local asstInst = res.systolicModule:add( S.module.assert( "LiftHandshake: output valid bit should not be X!" ,false):instantiate("asstInst") )
  table.insert(pipelines, asstInst:process(S.__not(S.isX(S.index(out,1))), S.constant(true,types.bool()) ) )

  local asstInst2 = res.systolicModule:add( S.module.assert( "LiftHandshake: input valid bit should not be X!" ,false):instantiate("asstInst2") )
  table.insert(pipelines, asstInst2:process(S.__not(S.isX(S.index(pinp,1))), S.constant(true,types.bool()) ) )

  res.systolicModule:addFunction( S.lambda("process", pinp, out, "process_output", pipelines ) ) 

  local resetPipelines = {}
  resetPipelines[1] = SR:reset(nil,rst)
  if STREAMING==false then table.insert(resetPipelines, outputCount:set(S.constant(0,types.uint(16)),rst) ) end

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(nil,rst), "reset_out", resetPipelines, rst ) )

  assert( f.systolicModule:getDelay("ready")==0 ) -- ready bit calculation can't be pipelined! That wouldn't make any sense

  local readyPipelines = {inner:CE(S.__or(rst,CE)), SR:CE(S.__or(rst,notBlockedDownstream))}
  if STREAMING==false then table.insert(readyPipelines, outputCount:CE(S.__or(rst,CE) ) ) end

  res.systolicModule:addFunction( S.lambda("ready", downstreamReady, systolic.__and(inner:ready(),notBlockedDownstream), "ready", readyPipelines ) )

  return darkroom.newFunction(res)
                                 end)

-- arrays: A[W][H]. Row major
-- array index A[y] yields type A[W]. A[y][x] yields type A

-- f : ( A, B, ...) -> C (darkroom function)
-- map : ( f, A[n], B[n], ...) -> C[n]
function darkroom.map( f, W, H )
  assert( darkroom.isFunction(f) )
  assert(type(W)=="number")
  assert(type(H)=="number" or H==nil)
  if H==nil then H=1 end

  local res = { kind="map", fn = f, W=W, H=H }
  darkroom.expectPure( f.inputType, "mapped function must be a pure function")
  darkroom.expectPure( f.outputType, "mapped function must be a pure function")
  res.inputType = types.array2d( f.inputType, W, H )
  res.outputType = types.array2d( f.outputType, W, H )
  res.sdfInput, res.sdfOutput = {1,1},{1,1}
  res.delay = f.delay
  local struct MapModule {fn:f.terraModule}
  terra MapModule:reset() self.fn:reset() end
  terra MapModule:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for i=0,W*H do self.fn:process( &((@inp)[i]), &((@out)[i])  ) end
  end
  res.terraModule = MapModule
  res.systolicModule = S.moduleConstructor("map_"..f.systolicModule.name):CE(true)
  local inp = S.parameter("process_input", res.inputType )
  local out = {}
  local resetPipelines={}
  for x=0,W-1 do for y=0,H-1 do
    local inst = res.systolicModule:add(f.systolicModule:instantiate("inner"..x.."_"..y))
    table.insert( out, inst:process( S.index( inp, x, y ) ) )
    --table.insert( resetPipelines, inst:reset() ) -- no reset for pure functions
  end end
  res.systolicModule:addFunction( S.lambda("process", inp, S.cast( S.tuple( out ), res.outputType ), "process_output" ) )
  --res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, S.parameter("reset",types.bool()) ) )

  return darkroom.newFunction(res)
end

-- if scaleX,Y > 1 then this is upsample
-- if scaleX,Y < 1 then this is downsample
function darkroom.scale( A, w, h, scaleX, scaleY )
  assert(types.isType(A))
  assert(type(w)=="number")
  assert(type(h)=="number")
  assert(type(scaleX)=="number")
  assert(type(scaleY)=="number")

  local res = { kind="scale", scaleX=scaleX, scaleY=scaleY}
  res.inputType = types.array2d( A, w, h )
  res.outputType = types.array2d( A, w*scaleX, h*scaleY )
  res.delay = 0
  local struct ScaleModule {}
  terra ScaleModule:reset() end
  terra ScaleModule:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for y=0,[h*scaleY] do 
      for x=0,[w*scaleX] do
        var idx = [int](cmath.floor([float](x)/[float](scaleX)))
        var idy = [int](cmath.floor([float](y)/[float](scaleY)))
--        cstdio.printf("SCALE outx %d outy %d, inx %d iny %d\n",x,y,idx,idy)
        (@out)[y*[w*scaleX]+x] = (@inp)[idy*w+idx]
      end
    end
  end
  res.terraModule = ScaleModule

  return darkroom.newFunction(res)
end

-- this expects f to be a stateful function
function darkroom.filterStateful( A, T, f )
  assert(types.isType(A))
  assert(type(T)=="number")
  assert(T>=1)
  assert( darkroom.isFunction(f) )

  local res = { kind="filterStateful", A=A,T=T,f=f}
  if f.inputType ~= darkroom.Stateful(types.array2d(types.null(),T)) then error("filter function input type should be nil array") end
  if f.outputType ~= darkroom.Stateful(types.array2d(types.bool(),T)) then error("filter function output type should be bool array") end
  res.inputType = darkroom.Stateful(types.array2d( A, T ))
  res.outputType = darkroom.Stateful(darkroom.Sparse(A,T))
  res.delay = 0
  local struct FilterStateful { inner: f.terraModule}
  terra FilterStateful:reset() self.inner:reset() end
  terra FilterStateful:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    var bout : bool[T]
    var fakeinp : darkroom.extract(f.inputType):toTerraType()
    self.inner:process(&fakeinp, &bout)
    for i=0,T do data((@out)[i]) = (@inp)[i]; valid((@out)[i]) = bout[i] end
    
  end
  res.terraModule = FilterStateful

  return darkroom.newFunction(res)
end

function darkroom.densify( A, T )
  assert(T>=1);
  local res = {kind="densify", T=T }
  res.inputType = darkroom.Stateful(darkroom.Sparse(A,T))
  res.outputType = darkroom.StatefulV(types.array2d(A,T))
  res.delay = 0
  local struct Densify { fifo : simmodules.fifo( A:toTerraType(), T*2, "densifyfifo") }
  terra Densify:reset() self.fifo:reset() end
  terra Densify:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    for i=0,T do 
      if valid((@inp)[i]) then self.fifo:pushBack(&data((@inp)[i])) end
    end

    if self.fifo:size()>=T then
      valid(out)=true
      for i=0,T do (data(out))[i] = @(self.fifo:popFront()) end
    else
      valid(out) = false
    end
  end
  res.terraModule = Densify
  return darkroom.newFunction(res)
end

-- takes A[W,H] to A[W,H/scale]
-- lines where ycoord%scale==0 are kept
-- Stateful -> StatefulV
function darkroom.downsampleYSeq( A, W, H, T, scale )
  assert( types.isType(A) )
  map({W,H,T,scale},function(n) assert(type(n)=="number") end)
  assert(scale>=1)
  err( W%T==0, "downsampleYSeq, W%T~=0")
  err( isPowerOf2(scale), "scale must be power of 2")
  local sbits = math.log(scale)/math.log(2)

  local inputType = types.array2d(A,T)
  local outputType = types.tuple{inputType,types.bool()}
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)
  local innerInputType = types.tuple{xyType, inputType}

  local sinp = S.parameter( "process_input", innerInputType )
  local sdata = S.index(sinp,1)
  local sy = S.index(S.index(S.index(sinp,0),0),1)
  local svalid = S.eq(S.cast(S.bitSlice(sy,0,sbits-1),types.uint(sbits)),S.constant(0,types.uint(sbits)))

  local f = darkroom.lift( "DownsampleYSeq", innerInputType, outputType, 0, 
                           terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
                             var y = (inp._0)[0]._1
                             data(out) = inp._1
                             valid(out) = (y%scale==0)
                           end, sinp, S.tuple{sdata,svalid})

  return darkroom.liftXYSeq( f, W, H, T, {1,scale} )
end

-- takes A[W,H] to A[W/scale,H]
-- lines where xcoord%scale==0 are kept
-- Stateful -> StatefulV
-- 
-- This takes A[T] to A[T/scale], except in the case where scale>T. Then it goes from A[T] to A[1]. If you want to go from A[T] to A[T], use changeRate.
function darkroom.downsampleXSeq( A, W, H, T, scale )
  assert( types.isType(A) )
  map({W,H,T,scale},function(n) assert(type(n)=="number") end)
  assert(scale>=1)
  err( W%T==0, "downsampleXSeq, W%T~=0")
  err( isPowerOf2(scale), "NYI - scale must be power of 2")
  local sbits = math.log(scale)/math.log(2)

  local outputT
  if scale>T then outputT = 1
  elseif T%scale==0 then outputT = T/scale
  else err(false,"T%scale~=0 and scale<T") end

  local inputType = types.array2d(A,T)
  local outputType = types.tuple{types.array2d(A,outputT),types.bool()}
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)
  local innerInputType = types.tuple{xyType, inputType}

  local sinp = S.parameter( "process_input", innerInputType )
--  local sdata = S.index(sinp,1)
  local sy = S.index(S.index(S.index(sinp,0),0),0)
  local svalid, sdata, tfn, sdfOverride
  if scale>T then
    sdfOverride = {1,scale}
    svalid = S.eq(S.cast(S.bitSlice(sy,0,sbits-1),types.uint(sbits)),S.constant(0,types.uint(sbits)))
    sdata = S.index(sinp,1)
    tfn = terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
                             var x = (inp._0)[0]._0
                             data(out) = inp._1
                             valid(out) = (x%scale==0)
                           end
  else
    sdfOverride = {1,1}
    svalid = S.constant(true,types.bool())
    local datavar = S.index(sinp,1)
    sdata = map(range(0,outputT-1), function(i) return S.index(datavar, i*scale) end)
    sdata = S.cast(S.tuple(sdata), types.array2d(A,outputT))
    tfn = terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
      for i=0,outputT do (data(out))[i] = (inp._1)[i*scale] end
      valid(out) = true
    end
  end

  local f = darkroom.lift( "DownsampleXSeq", innerInputType, outputType, 0, tfn, sinp, S.tuple{sdata,svalid})

  return darkroom.liftXYSeq( f, W, H, T, sdfOverride )
end

-- StatefulV -> StatefulRV
function darkroom.downsampleSeq( A, W, H, T, scaleX, scaleY )
  --[=[
  map({W,H,T,scaleX,scaleY},function(n) assert(type(n)=="number") end)
  assert(scaleX<=1)
  assert(scaleY<=1)
  local f = darkroom.liftXYSeq( types.null(), types.bool(), W,H,T,
                                terra(x:int,y:int,a:&(types.null():toTerraType()), b:&bool)
                                  @b = (x%[1/scaleX])==0 and (y%[1/scaleY])==0
                                end, 0)
  return darkroom.compose("downsampleSeq",darkroom.densify(A,T),darkroom.filterStateful( A,T,f))
  ]=]
  
  local inp = darkroom.input( darkroom.StatefulV(types.array2d(A,T)) )
  local out = inp
  if scaleY>1 then
    out = darkroom.apply("downsampleSeq_Y", darkroom.liftDecimate(darkroom.downsampleYSeq( A, W, H, T, scaleY )), out)
  end
  if scaleX>1 then
    out = darkroom.apply("downsampleSeq_X", darkroom.RPassthrough(darkroom.liftDecimate(darkroom.downsampleXSeq( A, W, H, T, scaleX ))), out)
    local downsampleT = math.max(T/scaleX,1)
    if downsampleT<T then
      -- technically, we shouldn't do this without lifting to a handshake - but we know this can never stall, so it's ok
      out = darkroom.apply("downsampleSeq_incrate", darkroom.RPassthrough(darkroom.changeRate(types.uint(8),1,downsampleT,T)), out )
    elseif downsampleT>T then assert(false) end
  end
  return darkroom.lambda("downsampleSeq", inp, out)
end

-- This is actually a pure function
-- takes A[T] to A[T*scale]
function darkroom.upsampleXSeq( A, W, H, T, scale )
  local ITYPE, OTYPE = types.array2d(A,T), types.array2d(A,T*scale)
  local sinp = S.parameter("inp",types.array2d(A,T))
  local out = {}
  for t=0,T-1 do
    for s=0,scale-1 do
      table.insert(out, S.index(sinp,t) )
    end
  end
  out = S.cast(S.tuple(out), OTYPE)
  return darkroom.lift("upsampleX", ITYPE, OTYPE, 0,
                       terra(inp : &ITYPE:toTerraType(), out:&OTYPE:toTerraType())
                         for t=0,T do
                           for s=0,scale do
                             (@out)[t*scale+s] = (@inp)[t]
                           end
                         end
                       end, sinp, out)
end

-- StatefulV -> StatefulRV
function darkroom.upsampleYSeq( A, W, H, T, scale )
  err( W%T==0,"W%T~=0")
  err( isPowerOf2(scale), "scale must be power of 2")
  err( isPowerOf2(W), "W must be power of 2")

  local res = {kind="upsampleYSeq", sdfInput={1,scale}, sdfOutput={1,1}}
  local ITYPE = types.array2d(A,T)
  res.inputType = darkroom.Stateful(ITYPE)
  res.outputType = darkroom.StatefulRV(types.array2d(A,T))
  res.delay=0

  local struct UpsampleYSeq { buffer : (ITYPE:toTerraType())[W/T], phase:int, xpos: int}
  terra UpsampleYSeq:reset() self.phase=0; self.xpos=0; end
  terra UpsampleYSeq:stats(name:&int8)  end
  terra UpsampleYSeq:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    valid(out) = true
    if self.phase==0 then
      self.buffer[self.xpos] = @(inp)
      data(out) = @(inp)
    else
      data(out) = self.buffer[self.xpos]
    end

    self.xpos = self.xpos + 1
    if self.xpos==W/T then self.xpos = 0; self.phase = self.phase+1 end
    if self.phase==scale then self.phase=0 end
  end
  terra UpsampleYSeq:ready()  return self.phase==0 end

  res.terraModule = UpsampleYSeq

  -----------------
  res.systolicModule = S.moduleConstructor("UpsampleYSeq"):CE(true)
  local sinp = S.parameter( "inp", ITYPE )

  -- we currently don't have a way to make a posx counter and phase counter coherent relative to each other. So just use 1 counter for both. This restricts us to only do power of two however!
  local sPhase = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.sumwrap((W/T)*scale-1) ):includeCE():instantiate("xpos") )

  local addrbits = math.log(W/T)/math.log(2)
  assert(addrbits==math.floor(addrbits))
  
  local xpos = S.cast(S.bitSlice( sPhase:get(), 0, addrbits-1), types.uint(addrbits))

  local phasebits = (math.log(scale)/math.log(2))
  local phase = S.cast(S.bitSlice( sPhase:get(), addrbits, addrbits+phasebits-1 ), types.uint(phasebits))

  local sBuffer = res.systolicModule:add( S.module.bramSDP( true, (A:verilogBits()*W)/8, ITYPE:verilogBits(), ITYPE:verilogBits() ):CE(true):instantiate("buffer"):setCoherent(true) )
  local reading = S.eq( phase, S.constant(0,types.uint(phasebits)) ):disablePipelining()



  local pipelines = {sBuffer:writeAndReturnOriginal(S.tuple{xpos,S.cast(sinp,types.bits(ITYPE:verilogBits()))}, reading), sPhase:setBy( S.constant(1, types.uint(16)) )}
  local out = S.select( reading, sinp, S.cast(sBuffer:read(xpos),ITYPE) ) 
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines) )
  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool())) )

  return darkroom.waitOnInput( darkroom.newFunction(res) )
end

function darkroom.packPyramid( A, w, h, levels, human )
  assert(types.isType(A))
  assert(type(w)=="number")
  assert(type(h)=="number")
  assert(type(levels)=="number")
  assert(type(human)=="boolean")

  local totalW = 0
  local typelist = {}
  if human then
    for i=1,levels do 
      totalW = totalW + w/math.pow(2,i-1) 
      table.insert( typelist, types.array2d(A, w/math.pow(2,i-1), h/math.pow(2,i-1)))
    end
  else
    assert(false)
  end

  local res = { kind="packPyramid", levels=levels}
  res.inputType = types.tuple(typelist)
  res.outputType = types.array2d( A, totalW, h)
  res.delay = 0
  local struct PackPyramidModule {}
  terra PackPyramidModule:reset() end
  local stats = {}
  local insymb = symbol(&res.inputType:toTerraType(),"inp")
  local outsymb = symbol(&res.outputType:toTerraType(),"out")
  local X = 0
  for l=1,levels do
    local thisW = w/math.pow(2,l-1)
    table.insert(stats, quote for y=0,[h/math.pow(2,l-1)] do for x=0,thisW do
                       (@outsymb)[y*totalW+x+X] = ((@insymb).["_"..(l-1)])[y*thisW+x]
                                                             end end end)
    X = X + thisW
  end
  terra PackPyramidModule:process( [insymb], [outsymb] ) cstring.memset(outsymb,0,[res.outputType:sizeof()]); stats end
  res.terraModule = PackPyramidModule

  return darkroom.newFunction(res)
end

function darkroom.packPyramidSeq( A, W,H,T, levels, human )
  assert(types.isType(A))
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(T)=="number")
  assert(type(levels)=="number")
  assert(type(human)=="boolean")

  local typelist = {}

  for i=1,levels do 
    table.insert( typelist, darkroom.StatefulHandshake(types.array2d(A, T)))
  end

  local res = { kind="packPyramid", levels=levels}
  res.inputType = types.tuple(typelist)
  res.outputType = darkroom.StatefulHandshake(types.array2d( A, T ))
  res.delay = 0
  local struct PackPyramidSeq { fifos : (simmodules.fifo( types.array2d(A,T):toTerraType(), DEFAULT_FIFO_SIZE, "packPyramidfifo"))[levels]; 
                                sm:int[2];
                                activeCycles:int;
                                idleCycles:int}

--  for i=1,levels do 
--    table.insert(PackPyramidSeq.entries, {field="fifo"..i, type = simmodules.fifo( types.array2d(A,T), DEFAULT_FIFO_SIZE, "packPyramidfifo"..i)})
--  end
  
  assert(W%(T*math.pow(2,levels-1))==0)
  local SM = coroutine.wrap(function()
                              while true do
                              for y=0,H-1 do for i=0,levels-1 do
                                  for x=0,(W/math.pow(2,i))-1,T do coroutine.yield(ffi.new("int[2]",{i,sel(y>H/math.pow(2,i),1,0)})) end
                                             end end end end)

  if human==false then
    SM = coroutine.wrap(function()
                              while true do
                                for l=0,levels-1 do
                                  for y=0,math.pow(2,levels-1-l)-1 do 
                                    for x=0,(W/math.pow(2,l))-1,T do coroutine.yield(ffi.new("int[2]",{l,0})) end
                                  end 
                                end end end)
  end

  SM = terralib.cast({}->&int, SM)

  terra PackPyramidSeq:reset() for i=0,levels do self.fifos[i]:reset() end; self.sm=@([&int32[2]](SM())); self.activeCycles=0; self.idleCycles=0; end
  terra PackPyramidSeq:stats(name:&int8) 
    cstdio.printf("PackPyramidSeq %s utilization %f\n",name,[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles))
    for i=0,levels do cstdio.printf("PackPyramidSeq %s fifo %d max: %d\n",name,i,self.fifos[i]:maxSizeSeen()) end
  end

  local stats = {}
  local mself = symbol(&PackPyramidSeq,"self")
  local insymb = symbol(&darkroom.extract(res.inputType):toTerraType(),"inp")
  local outsymb = symbol(&darkroom.extract(res.outputType):toTerraType(),"out")
  
  for i=0,levels-1 do
    table.insert(stats, quote if valid(insymb.["_"..i]) then mself.fifos[i]:pushBack(&data(insymb.["_"..i])) end end)
  end

  terra PackPyramidSeq.methods.process( [mself], [insymb], [outsymb] ) 
    escape
      for i=0,levels-1 do
        emit quote if valid(insymb.["_"..i]) then cstdio.printf("PackPyramid Validin %d\n",i) end end
      end
    end

    stats;
    cstdio.printf("PP %d %d\n",mself.sm[0],mself.sm[1])
    if mself.sm[1]==1 then -- zero fill
      mself.activeCycles = mself.activeCycles + 1
      valid(outsymb) = true
      for i=0,T do data(outsymb)[i] = 0 end
      mself.sm = @([&int32[2]](SM()))
    elseif mself.fifos[mself.sm[0]]:size()>=T then
      -- we have enough data to proceed
      cstdio.printf("PackPyramidValidOut\n")
      mself.activeCycles = mself.activeCycles + 1
      valid(outsymb) = true
      data(outsymb) = @(mself.fifos[mself.sm[0]]:popFront())
      mself.sm = @([&int32[2]](SM()))
    else
      cstdio.printf("PackPyramidInvalid waiting on %d\n",mself.sm[0])
      mself.idleCycles = mself.idleCycles + 1
      valid(outsymb) = false
    end
  end

  res.terraModule = PackPyramidSeq

  return darkroom.newFunction(res)
  
end

function darkroom.tmux( f, inputList )
  assert( darkroom.isFunction(f))
  darkroom.expectPure(f.inputType)
  darkroom.expectPure(f.outputType)
  local res = { kind="tmux", inputList=inputList }
  local itypelist = map( inputList, function(n) return darkroom.StatefulHandshakeRegistered(f.inputType) end )
  local otypelist = map( inputList, function(n) return darkroom.StatefulHandshakeRegistered(f.outputType) end )
  res.inputType = types.tuple( itypelist )
  res.outputType = types.tuple( otypelist )

  local struct Tmux { fifos : (simmodules.fifo( f.inputType:toTerraType(), DEFAULT_FIFO_SIZE, "tmuxfifo"))[#inputList]; 
                    inner : f.terraModule; idleCycles:int, activeCycles:int}
  terra Tmux:reset() for i=0,[#inputList] do self.fifos[i]:reset() end;
    self.idleCycles = 0; self.activeCycles=0; end
  terra Tmux:stats(name:&int8) cstdio.printf("Tmux %s utilization %f\n",name,[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) 
    for i=0,[#inputList] do cstdio.printf("Tmux %s fifo %d max: %d\n",name,i,self.fifos[i]:maxSizeSeen()) end end

  terra Tmux:store( inp : &darkroom.extract(res.inputType):toTerraType() )
--    cstdio.printf("TMUXSTORE\n")
    escape for i=0,#inputList-1 do
      emit quote if valid(inp.["_"..i]) then 
    cstdio.printf("TMUXSTORE %d\n",i)
self.fifos[i]:pushBack(&data(inp.["_"..i])) end end
    end end
  end

  terra Tmux:load( out : &darkroom.extract(res.outputType):toTerraType() )

    escape for i=0,#inputList-1 do
      emit quote 
--        cstdio.printf("TMUXCLEAR %d\n",i)
valid(out.["_"..i]) = false end
    end end
    escape --for i=0,#inputList-1 do
      local i=#inputList-1
      while i>=0 do
      emit quote if self.fifos[i]:hasData() then 
--          cstdio.printf("TMUXLOAD %d %d\n",i,[#inputList-1])
          valid(out.["_"..i])=true; 
          self.inner:process(self.fifos[i]:popFront(), &data(out.["_"..i]) );
          self.activeCycles = self.activeCycles + 1
          return
--                 else
--            cstdio.printf("TMUXLOAD NODATA %d\n",i)
                 end end
      i=i-1
      end 
    end
          self.idleCycles = self.idleCycles + 1
--    [darkroom.print(res.outputType, out)]
  end
--Tmux.methods.load:printpretty()
--assert(false)
  res.terraModule = Tmux

  return darkroom.newFunction(res)
end

-- takes A to A[T] by duplicating the input
function darkroom.broadcast(A,T)
  darkroom.expectPure(A)
  err( type(T)=="number", "T should be number")
  local OT = types.array2d(A,T)
  local sinp = S.parameter("inp",A)
  return darkroom.lift("Broadcast_"..T,A,OT,0,
                       terra(inp : &A:toTerraType(), out:&OT:toTerraType() )
                         for i=0,T do (@out)[i] = @inp end
                         end, sinp, S.cast(S.tuple(broadcast(sinp,T)),OT) )
end

-- broadcast : ( v : A , n : number ) -> A[n]
--darkroom.broadcast = darkroom.newDarkroomFunction( { kind = "broadcast" } )

-- extractStencils : A[n] -> A[(xmax-xmin+1)*(ymax-ymin+1)][n]
-- min, max ranges are inclusive
function darkroom.stencil( A, w, h, xmin, xmax, ymin, ymax )
  assert( type(xmin)=="number" )
  assert( type(xmax)=="number" )
  assert( xmax>=xmin )
  assert( type(ymin)=="number" )
  assert( type(ymax)=="number" )
  assert( ymax>=ymin )

  darkroom.expectPure(A)
  if A:isArray() then error("Input to extract stencils must not be array") end

  local res = {kind="extractStencils", type=A, w=w, h=h, xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax }
  res.delay=0
  res.inputType = types.array2d(A,w,h)
  res.outputType = types.array2d(types.array2d(A,xmax-xmin+1,ymax-ymin+1),w,h)
  res.sdfInput, res.sdfOutput = {1,1},{1,1}

  local struct Stencil {}
  terra Stencil:reset() end
  terra Stencil:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for i=0,[w*h] do
      for y = ymin, ymax+1 do
        for x = xmin, xmax+1 do
          ((@out)[i])[(y-ymin)*(xmax-xmin+1)+(x-xmin)] = (@inp)[i+x+y*w]
        end
      end
    end
  end
  res.terraModule = Stencil

  return darkroom.newFunction(res)
end

-- f(g())
function darkroom.compose(name,f,g)
  assert(type(name)=="string")
  assert(darkroom.isFunction(f))
  assert(darkroom.isFunction(g))
  local inp = darkroom.input( g.inputType )
  local gvalue = darkroom.apply(name.."_g",g,inp)
  return darkroom.lambda(name,inp,darkroom.apply(name.."_f",f,gvalue))
end

-- output type: {uint16,uint16}[T]
darkroom.posSeq = memoize(function( W, H, T )
  assert(W>0); assert(H>0); assert(T>=1);
  local res = {kind="posSeq", T=T, W=W, H=H }
  res.inputType = darkroom.State
  res.outputType = darkroom.Stateful(types.array2d(types.tuple({types.uint(16),types.uint(16)}),T))
  res.sdfInput, res.sdfOutput = {1,1},{1,1}
  res.delay = 0
  local struct PosSeq { x:uint16, y:uint16 }
  terra PosSeq:reset() self.x=0; self.y=0 end
  terra PosSeq:process( inp : &res.inputType:toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    for i=0,T do 
      (@out)[i] = {self.x,self.y}
      self.x = self.x + 1
      if self.x==W then self.x=0; self.y=self.y+1 end
    end
  end
  res.terraModule = PosSeq

  res.systolicModule = S.moduleConstructor("PosSeq_W"..W.."_H"..H.."_T"..T):CE(true)
  local posX = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap(W-T,T) ):setInit(0):includeCE():instantiate("posX_posSeq") )
  local posY = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap(H-1)):setInit(0):includeCE():instantiate("posY_posSeq") )
  local printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(16),types.uint(16)}, "x %d y %d", true):instantiate("printInst") )

  local incY = S.eq( posX:get(), S.constant(W-T,types.uint(16))  ):disablePipelining()

  local out = {S.tuple{posX:get(),posY:get()}}
  for i=1,T-1 do
    table.insert(out, S.tuple{posX:get()+S.constant(i,types.uint(16)),posY:get()})
  end

  res.systolicModule:addFunction( S.lambda("process", S.parameter("pinp",types.null()), S.cast(S.tuple(out),types.array2d(types.tuple{types.uint(16),types.uint(16)},T)), "process_output", {posX:setBy( S.constant(true, types.bool() ) ),  posY:setBy( incY ),printInst:process( S.tuple{posX:get(),posY:get()})}) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {posX:set(S.constant(0,types.uint(16))), posY:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool())) )
  res.systolicModule:complete()

  return darkroom.newFunction(res)
                          end)

-- this takes a function f : {{int32,int32}[T],inputType[T]} -> outputType[T]
-- and drives the first tuple with (x,y) coord
-- returns a function with type Stateful(inputType)->Stateful(outputType)
-- sdfOverride: we can use this to define stateful->StatefulV interfaces etc, so we may want to override the default SDF rate
darkroom.liftXYSeq = memoize(function( f, W, H, T, sdfOverride )
  assert(darkroom.isFunction(f))
  map({W,H,T},function(n) assert(type(n)=="number") end)

  darkroom.expectPure(f.inputType)
  darkroom.expectPure(f.outputType)

  local inputType = f.inputType.list[2]
  print("liftXYseqIT",inputType)
  local inp = darkroom.input( darkroom.Stateful( inputType ) )

  local p = darkroom.apply("p", darkroom.posSeq(W,H,T), darkroom.extractState("e",inp) )
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)
  local packed = darkroom.apply( "packedtup", darkroom.packTuple({xyType,inputType}), darkroom.tuple("ptup", {p,inp}) )
  local out = darkroom.apply("m", darkroom.makeStateful(f), packed )
  return darkroom.lambda( "liftXYSeq_"..f.kind, inp, out, sdfOverride )
end)

-- this takes a function f : {{int32,int32},inputType} -> outputType
function darkroom.liftXYSeqPointwise( f, W, H, T )
  assert(f.inputType:isTuple())
  local fInputType = f.inputType.list[2]
  local inputType = types.array2d(fInputType,T)
  local xyinner = types.tuple{types.uint(16),types.uint(16)}
  local xyType = types.array2d(xyinner,T)
  local innerInputType = types.tuple{xyType, inputType}

  local inp = darkroom.input( innerInputType )
  local unpacked = darkroom.apply("unp", darkroom.SoAtoAoS(T,1,{xyinner,fInputType}), inp) -- {{uint16,uint16},A}[T]
  local out = darkroom.apply("f",darkroom.map(f,T),unpacked)
  local ff = darkroom.lambda("liftXYSeqPointwise_"..f.kind, inp, out )
  return darkroom.liftXYSeq(ff,W,H,T)
end

-- this applies a border around the image. Takes A[W,H] to A[W,H], but with a border. Sequentialized to throughput T.
function darkroom.borderSeq( A, W, H, T, L, R, B, Top, Value )
  map({W,H,T,L,R,B,Top,Value},function(n) assert(type(n)=="number") end)

  local inpType = types.tuple{types.tuple{types.uint(16),types.uint(16)},A}
  local inp = S.parameter( "process_input", inpType )
  local inpx, inpy = S.index(S.index(inp,0),0), S.index(S.index(inp,0),1)
  local horizontal = S.__or(S.lt(inpx,S.constant(L,types.uint(16))),S.ge(inpx,S.constant(W-R,types.uint(16))))
  local vert = S.__or(S.lt(inpy,S.constant(B,types.uint(16))),S.ge(inpy,S.constant(H-Top,types.uint(16))))
  local outside = S.__or(horizontal,vert)
  local out = S.select(outside,S.constant(Value,A), S.index(inp,1) )

  local f = darkroom.lift( "BorderSeq", inpType, A, 0, 
                           terra( inp :&inpType:toTerraType(), out : &A:toTerraType() )
                             var x,y, inpvalue = inp._0._0, inp._0._1, inp._1
                                  if x<L or y<B or x>=W-R or y>=H-Top then @out = [Value]
                                  else @out = inpvalue end
                                end, inp, out )
  return darkroom.liftXYSeqPointwise( f, W, H, T )
end

-- takes an image of size A[W,H] to size A[W-L-R,H-B-Top]
function darkroom.cropSeq( A, W, H, T, L, R, B, Top )
  map({W,H,T,L,R,B,Top},function(n) assert(type(n)=="number");err(n>=0,"n<0") end)
  err(T>=1,"cropSeq T<1")

  err( L>=0, "cropSeq, L<0")
  err( R>=0, "cropSeq, R<0")
  err( W%T==0, "cropSeq, W%T~=0")
  err( L%T==0, "cropSeq, L%T~=0")
  err( R%T==0, "cropSeq, R%T~=0")

  local inputType = types.array2d(A,T)
  local outputType = types.tuple{inputType,types.bool()}
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)
  local innerInputType = types.tuple{xyType, inputType}

  local sinp = S.parameter( "process_input", innerInputType )
  local sdata = S.index(sinp,1)
  local sx, sy = S.index(S.index(S.index(sinp,0),0),0), S.index(S.index(S.index(sinp,0),0),1)
  local sL,sB = S.constant(L,types.uint(16)),S.constant(B,types.uint(16))
  local sWmR,sHmTop = S.constant(W-R,types.uint(16)),S.constant(H-Top,types.uint(16))
  local svalid = S.__and(S.__and(S.ge(sx,sL),S.ge(sy,sB)),S.__and(S.lt(sx,sWmR),S.lt(sy,sHmTop)))

  local f = darkroom.lift( "CropSeq", innerInputType, outputType, 0, 
                           terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
                             var x,y = (inp._0)[0]._0, (inp._0)[0]._1
                             data(out) = inp._1
                             valid(out) = (x>=L and y>=B and x<W-R and y<H-Top)
                             cstdio.printf("CROP x %d y %d VO %d\n",x,y,valid(out))
                           end, sinp, S.tuple{sdata,svalid})

  return darkroom.liftXYSeq( f, W, H, T, {((W-L-R)*(H-B-Top))/T,(W*H)/T} )
end

-- This is the same as CropSeq, but lets you have L,R not be T-aligned
-- All it does is throws in a shift register to alter the horizontal phase
function darkroom.cropHelperSeq( A, W, H, T, L, R, B, Top )
  if L%T==0 and R%T==0 then return darkroom.cropSeq( A, W, H, T, L, R, B, Top ) end

  local RResidual = R%T
  local inp = darkroom.input( darkroom.Stateful(types.array2d( A, T )) )
  local out = darkroom.apply( "SSR", darkroom.SSR( A, T, -RResidual, 0 ), inp)
  out = darkroom.apply( "slice", darkroom.makeStateful(darkroom.slice( types.array2d(A,T+RResidual), 0, T-1, 0, 0)), out)
  out = darkroom.apply( "crop", darkroom.cropSeq(A,W,H,T,L+RResidual,R-RResidual,B,Top), out )
  return darkroom.lambda( "cropHelperSeq", inp, out )
end

-- takes an image of size A[W,H] to size A[W+L+R,H+B+Top]. Fills the new pixels with value 'Value'
-- sequentialized to throughput T
function darkroom.padSeq( A, W, H, T, L, R, B, Top, Value )
  err( types.isType(A), "A must be a type")
  map({W,H,T,L,R,B,Top,Value},function(n) assert(type(n)=="number"); err(n>=0,"n<0") end)
  err(T>=1, "padSeq, T<1")

  err( W%T==0, "padSeq, W%T~=0")
  err( (W+L+R)%T==0, "padSeq, (W+L+R)%T~=0")

  local res = {kind="padSeq", type=A, T=T, L=L, R=R, B=B, Top=Top, value=Value}
  res.inputType = darkroom.Stateful(types.array2d(A,T))
  res.outputType = darkroom.StatefulRV(types.array2d(A,T))
  res.sdfInput, res.sdfOutput = { (W*H)/T, ((W+L+R)*(H+B+Top))/T}, {1,1}
  res.delay=0

  local struct PadSeq {posX:int; posY:int}
  terra PadSeq:reset() self.posX=0; self.posY=0; end
  terra PadSeq:stats(name:&int8) end -- not particularly interesting
  terra PadSeq:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    var interior : bool = (self.posX>=L and self.posX<(L+W) and self.posY>=B and self.posY<(B+H))

    valid(out) = true
    if interior then
      data(out) = @inp
    else
      data(out) = arrayof([A:toTerraType()],[rep(Value,T)])
    end
    
    self.posX = self.posX+T;
    if self.posX==(W+L+R) then
      self.posX=0;
      self.posY = self.posY+1;
    end
--    cstdio.printf("PAD x %d y %d inner %d\n",self.posX,self.posY,inner)
  end
  terra PadSeq:ready()  return (self.posX>=L and self.posX<(L+W) and self.posY>=B and self.posY<(B+H)) end
  res.terraModule = PadSeq

  res.systolicModule = S.moduleConstructor("PadSeq_W"..W.."_H"..H.."_L"..L.."_R"..R.."_B"..B.."_Top"..Top.."_T"..T..T):CE(true)


  local posX = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap( W+L+R-T, T ) ):includeCE():setInit(0):instantiate("posX_padSeq") ) 
  local posY = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap(H+Top+B) ):includeCE():setInit(0):instantiate("posY_padSeq") ) 
  local printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(16),types.uint(16),types.bool()}, "x %d y %d ready %d", true ):instantiate("printInst") )
--  local asstInst = res.systolicModule:add( S.module.assert( "padSeq input ins't valid when it should be", {CE=true}):instantiate("asstInst") )

  local pinp = S.parameter("process_input", darkroom.extract(res.inputType) )
  local pvalid = S.parameter("process_valid", types.bool() )
  --local pinp_data = S.index(pinp,0)
  --local pinp_valid = S.index(pinp,1)

  local C1 = S.ge( posX:get(), S.constant(L,types.uint(16)))
  local C2 = S.lt( posX:get(), S.constant(L+W,types.uint(16)))
  local C3 = S.ge( posY:get(), S.constant(B,types.uint(16)))
  local C4 = S.lt( posY:get(), S.constant(B+H,types.uint(16)))
  local xcheck = S.__and(C1,C2)
  local ycheck = S.__and(C3,C4)
  local isInside = S.__and(xcheck,ycheck)
  local readybit = isInside:disablePipelining()

  local pipelines={}
  --local stepPipe = S.__or( pinp_valid, S.__not(readybit) )
  local incY = S.eq( posX:get(), S.constant(W+L+R-T,types.uint(16))  ):disablePipelining()
  pipelines[1] = posY:setBy( incY )
  pipelines[2] = posX:setBy( S.constant(true,types.bool()) )

--  pipelines[4] = asstInst:process( S.__or(pinp_valid,S.eq(readybit,S.constant(false,types.bool()) ) ) )

  local ValueBroadcast = S.cast(S.constant(Value,A),types.array2d(A,T))
  local ConstTrue = S.constant(true,types.bool())
  --local ConstFalse = S.constant(false,types.bool())
  --local border = S.select(S.ge(posY:get(),S.constant(H+Top+B,types.uint(16))),S.tuple{ValueBroadcast,ConstFalse},S.tuple{ValueBroadcast,ConstTrue})
  local out = S.select( readybit, pinp, ValueBroadcast )

  table.insert(pipelines, printInst:process( S.tuple{ posX:get(), posY:get(), readybit } ) )

  res.systolicModule:addFunction( S.lambda("process", pinp, S.tuple{out,ConstTrue}, "process_output", pipelines, pvalid) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {posX:set(S.constant(0,types.uint(16))), posY:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool())) )

  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), readybit, "ready", {} ) )

  return darkroom.waitOnInput(darkroom.newFunction(res))
end


--StatefulRV. Takes A[inputRate,H] in, and buffers to produce A[outputRate,H]
darkroom.changeRate = memoize(function(A, H, inputRate, outputRate)
  err( types.isType(A), "A should be a type")
  err( type(H)=="number", "H should be number")
  err( type(inputRate)=="number", "inputRate should be number")
  err( inputRate==math.floor(inputRate), "inputRate should be integer")
  err( type(outputRate)=="number", "outputRate should be number")
  err( outputRate==math.floor(outputRate), "outputRate should be integer")

  local maxRate = math.max(inputRate,outputRate)
  print("IR",inputRate,"OR",outputRate,"MR",maxRate)
  err( maxRate % inputRate == 0, "maxRate % inputRate ~= 0")
  err( maxRate % outputRate == 0, "maxRate % outputRate ~=0")
  darkroom.expectPure(A)

  local inputCount = maxRate/inputRate
  local outputCount = maxRate/outputRate

  local res = {kind="changeRate", type=A, inputRate=inputRate, outputRate=outputRate}
  res.inputType = darkroom.Stateful(types.array2d(A,inputRate))
  res.outputType = darkroom.StatefulRV(types.array2d(A,outputRate))
  res.delay = (math.log(maxRate/inputRate)/math.log(2)) + (math.log(maxRate/outputRate)/math.log(2))

  if inputRate>outputRate then -- 8 to 4
    res.sdfInput, res.sdfOutput = {outputRate,inputRate},{1,1}
  else -- 4 to 8
    res.sdfInput, res.sdfOutput = {1,1},{inputRate,outputRate}
  end

  local struct ChangeRate { buffer : (A:toTerraType())[maxRate]; phase:int}

  terra ChangeRate:stats(name:&int8) end
  res.systolicModule = S.moduleConstructor("ChangeRate_"..inputRate.."_to"..outputRate):CE(true)
  local svalid = S.parameter("process_valid", types.bool() )
  local rvalid = S.parameter("reset", types.bool() )
  local pinp = S.parameter("process_input", darkroom.extract(res.inputType) )

  local regs = map( range(maxRate), function(i) return res.systolicModule:add(S.module.reg(A):instantiate("Buffer_"..i)) end )

  if inputRate>outputRate then
    terra ChangeRate:reset() self.phase = 0; end
    terra ChangeRate:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
      cstdio.printf("CHANGE_DOWN phase %d\n", self.phase)
      if self.phase==0 then
        for i=0,inputRate do self.buffer[i] = (@inp)[i] end
      end

      for i=0,outputRate do (data(out))[i] = self.buffer[i+self.phase*outputRate] end
      valid(out) = true

      self.phase = self.phase + 1
      if  self.phase>=outputCount then self.phase=0 end

      cstdio.printf("CHANGE_DOWN OUT validOut %d\n",valid(out))
    end
    terra ChangeRate:ready()  return self.phase==0 end

    -- 8 to 4
    local shifterReads = {}
    for i=0,outputCount-1 do
      table.insert(shifterReads, S.slice( pinp, i*outputRate, (i+1)*outputRate-1, 0, H-1 ) )
    end
    local out, pipelines, resetPipelines, ready = fpgamodules.addShifter( res.systolicModule, shifterReads )

    res.systolicModule:addFunction( S.lambda("process", pinp, S.tuple{ out, S.constant(true,types.bool()) }, "process_output", pipelines, svalid) )
    res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), ready, "ready", {} ) )
    res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, rvalid ) )

  else -- inputRate <= outputRate. 4 to 8
    terra ChangeRate:reset() self.phase = 0; end
    terra ChangeRate:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
      for i=0,inputRate do self.buffer[i+self.phase*inputRate] = (@(inp))[i] end

      if self.phase >= inputCount-1 then
        valid(out) = true
        data(out) = self.buffer
      else
        valid(out) = false
      end

      self.phase = self.phase + 1
      if self.phase>=inputCount then
        self.phase = 0
      end

      cstdio.printf("CHANGE RATE RET validout %d inputPhase %d\n",valid(out),self.phase)
    end
    terra ChangeRate:ready()  return true end

    local sPhase = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap(inputCount-1) ):includeCE():instantiate("phase_changerateup") )
    local printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(16),types.array2d(A,outputRate)}, "phase %d buffer %h", true ):instantiate("printInst") )
    local ConstTrue = S.constant(true,types.bool())
    res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", { sPhase:set(S.constant(0,types.uint(16))) }, rvalid ) )

    -- in the first cycle (first time inputPhase==0), we don't have any data yet. Use the sWroteLast variable to keep track of this case
    local validout = S.eq(sPhase:get(),S.constant(inputCount-1,types.uint(16))):disablePipelining()

    local out = concat2dArrays(map(range(inputCount-1,0), function(i) return pinp(i) end))
    local pipelines = {sPhase:setBy(ConstTrue), printInst:process(S.tuple{sPhase:get(),out}) }

    res.systolicModule:addFunction( S.lambda("process", pinp, S.tuple{out,validout}, "process_output", pipelines, svalid) )
    res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), ConstTrue, "ready", {} ) )
  end

  res.terraModule = ChangeRate

  return darkroom.waitOnInput(darkroom.newFunction(res))
end)

function darkroom.linebuffer( A, w, h, T, ymin )
  assert(w>0); assert(h>0);
  assert(ymin<=0)
  
  -- if W%T~=0, then we would potentially have to do two reads on wraparound. So don't allow this case.
  err( w%T==0, "Linebuffer error, W%T~=0")

  local res = {kind="linebuffer", type=A, T=T, w=w, h=h, ymin=ymin }
  darkroom.expectPure(A)
  res.inputType = darkroom.Stateful(types.array2d(A,T))
  res.outputType = darkroom.Stateful(types.array2d(A,T,-ymin+1))
  res.sdfInput, res.sdfOutput = {1,1},{1,1}
  res.delay = 0
  local struct Linebuffer { SR: simmodules.shiftRegister( A:toTerraType(), w*(-ymin)+T, "linebuffer")}
  terra Linebuffer:reset() self.SR:reset() end
  terra Linebuffer:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    -- pretend that this happens in one cycle (delays are added later)
    for i=0,[T] do
      self.SR:pushBack( &(@inp)[i] )
    end

    for y=[ymin],1 do
      for x=[-T+1],1 do
        (@out)[(y-ymin)*T+(x+T-1)] = @(self.SR:peekBack(x+y*[w]))
--        cstdio.printf("ASSN x %d  y %d outidx %d peekidx %d\n",x,y,(y-ymin)*T+(x+T-1),x+y*[w])
      end
    end

  end
  res.terraModule = Linebuffer

  res.systolicModule = S.moduleConstructor("linebuffer"):CE(true)
  local sinp = S.parameter("process_input", darkroom.extract(res.inputType) )
  local addr = res.systolicModule:add( S.module.regBy( types.uint(16), fpgamodules.incIfWrap((w/T)-1), true, nil ):instantiate("addr") )

  local outarray = {}
  local evicted

  local bits = darkroom.extract(res.inputType):verilogBits()
  local sizeInBytes = nearestPowerOf2((w/T)*darkroom.extract(res.inputType):verilogBits()/8)
  local init = map(range(0,sizeInBytes-1), function(i) return i%256 end)  
  local bramMod = S.module.bramSDP( true, sizeInBytes, bits, nil, init ):CE(true)
  local addrbits = math.log((sizeInBytes*8)/bits)/math.log(2)

  for y=0,-ymin do
    local lbinp = evicted
    if y==0 then lbinp = sinp end
    for x=1,T do outarray[x+(-ymin-y)*T] = S.index(lbinp,x-1) end

    if y<-ymin then
      -- last line doesn't need a ram
      local BRAM = res.systolicModule:add( bramMod:instantiate("lb_m"..math.abs(y)) )

--      local BRAM = res.systolicModule:add( S.module.bram2KSDP( true, darkroom.extract(res.inputType), init ):instantiate("lb_m"..math.abs(y)))

      evicted = BRAM:writeAndReturnOriginal( S.tuple{ S.cast(addr:get(),types.uint(addrbits)), S.cast(lbinp,types.bits(bits))} )
      evicted = S.cast( evicted, darkroom.extract(res.inputType) )
    end
  end

  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple( outarray ), darkroom.extract(res.outputType) ), "process_output", {addr:setBy(S.constant(true, types.bool()))} ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {addr:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool())) )

  return darkroom.newFunction(res)
end

-- xmin, ymin are inclusive
function darkroom.SSR( A, T, xmin, ymin )
  map({T,xmin,ymin}, function(i) assert(type(i)=="number") end)
  assert(ymin<=0)
  assert(xmin<=0)
  assert(T>0)
  local res = {kind="SSR", type=A, T=T, xmin=xmin, ymin=ymin }
  res.inputType = darkroom.Stateful(types.array2d(A,T,-ymin+1))
  res.outputType = darkroom.Stateful(types.array2d(A,T-xmin,-ymin+1))
  res.sdfInput, res.sdfOutput = {1,1},{1,1}
  res.delay=0
  local struct SSR {SR:(A:toTerraType())[-xmin+T][-ymin+1]}
  terra SSR:reset() end
  terra SSR:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
    for y=0,-ymin+1 do for x=0,-xmin do self.SR[y][x] = self.SR[y][x+T] end end
    for y=0,-ymin+1 do for x=-xmin,-xmin+T do self.SR[y][x] = (@inp)[y*T+(x+xmin)] end end

    -- write to output
    for y=0,-ymin+1 do for x=0,-xmin+T do (@out)[y*(-xmin+T)+x] = self.SR[y][x] end end
  end
  res.terraModule = SSR

  res.systolicModule = S.moduleConstructor("SSR_W"..(-xmin+1).."_H"..(-ymin+1).."_T"..T):CE(true)
  local sinp = S.parameter("inp", darkroom.extract(res.inputType))
  local pipelines = {}
  local SR = {}
  local out = {}
  for y=0,-ymin do 
    SR[y]={}
    local x = -xmin+T-1
    while(x>=0) do


      if x<-xmin-T then
        SR[y][x] = res.systolicModule:add( S.module.reg(A):instantiate("SR_x"..x.."_y"..y ) )
        table.insert( pipelines, SR[y][x]:set(SR[y][x+T]:get()) )
        out[y*(-xmin+T)+x+1] = SR[y][x]:get()
      elseif x<-xmin then
        SR[y][x] = res.systolicModule:add( S.module.reg(A):instantiate("SR_x"..x.."_y"..y ) )
--        table.insert( pipelines, SR[y][x]:set(SR[y][x+T]:get()) )
        table.insert( pipelines, SR[y][x]:set(S.index(sinp,x+(T+xmin),y ) ) )
        out[y*(-xmin+T)+x+1] = SR[y][x]:get()
      else -- x>-xmin
        out[y*(-xmin+T)+x+1] = S.index(sinp,x+xmin,y)
        --table.insert( pipelines, SR[y][x]:set(S.index(sinp,x+xmin,y)) )
      end



      x = x - 1
    end
  end

  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple( out ), darkroom.extract(res.outputType)), "process_output", pipelines ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro" ) )

  return darkroom.newFunction(res)
end

function darkroom.SSRPartial( A, T, xmin, ymin )
  assert(T<=1); 
  assert((-xmin+1)*T==math.floor((-xmin+1)*T))
  local res = {kind="SSRPartial", type=A, T=T, xmin=xmin, ymin=ymin }
  res.inputType = darkroom.Stateful(types.array2d(A,1,-ymin+1))
  res.outputType = darkroom.StatefulRV(types.array2d(A,(-xmin+1)*T,-ymin+1))
  res.sdfInput, res.sdfOutput = {1,1/T},{1,1}
  res.delay=0
  local struct SSRPartial {phase:int; SR:(A:toTerraType())[-xmin+1][-ymin+1]; activeCycles:int; idleCycles:int}
  terra SSRPartial:reset() self.phase=0; self.activeCycles=0;self.idleCycles=0; end
  terra SSRPartial:stats(name:&int8) cstdio.printf("SSRPartial %s T=%f utilization:%f\n",name,[float](T),[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end
  terra SSRPartial:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )

    var phaseAtStart = self.phase
    --cstdio.printf("SSRPARTIAL phase %d inpValid %d red %d\n",self.phase, valid(inp),self:ready())
    if self:ready() then
      --darkroomAssert( self.phase==[1/T]-1, "SSRPartial set when not in right phase" )
--      darkroomAssert( self.wroteLastColumn, "SSRPartial set when not in right phase" )
--      self.activeCycles = self.activeCycles + 1
--      self.wroteLastColumn=false
      -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
      var SStride = 1
      for y=0,-ymin+1 do for x=0,-xmin do self.SR[y][x] = self.SR[y][x+SStride] end end
      for y=0,-ymin+1 do for x=-xmin,-xmin+SStride do self.SR[y][x] = (@inp)[y*SStride+(x+xmin)] end end
      self.phase = terralib.select([T==1],0,1)
    else
      if self.phase<[1/T]-1 then 
        self.phase = self.phase + 1 
--        self.activeCycles = self.activeCycles + 1
      else
        self.phase = 0
--        self.idleCycles = self.idleCycles + 1
      end
    end

    var W = [(-xmin+1)*T]
    for y=0,-ymin+1 do for x=0,W do data(out)[y*W+x] = self.SR[y][x+phaseAtStart*W] end end
    valid(out)=true
  end
  terra SSRPartial:ready()  return self.phase==0 end
  res.terraModule = SSRPartial

  res.systolicModule = S.moduleConstructor("SSRPartial"):CE(true)
  local sinp = S.parameter("process_input", darkroom.extract(res.inputType) )
  local P = 1/T

  local shiftValues = {}
  local Weach = (-xmin+1)/P -- number of columns in each output

  for p=P-1,0,-1 do
    table.insert(shiftValues, concat2dArrays( map( range(Weach-1,0), function(i) return sinp( (p*Weach + i)*P ) end )) )
  end

  local shifterOut, shifterPipelines, shifterResetPipelines, shifterReading = fpgamodules.addShifter( res.systolicModule, shiftValues )

  local processValid = S.parameter("process_valid",types.bool())
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ shifterOut, processValid }, "process_output", shifterPipelines, processValid) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", shifterResetPipelines,S.parameter("reset",types.bool())) )

  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), shifterReading, "ready", {} ) )

  return darkroom.newFunction(res)
end

function darkroom.stencilLinebuffer( A, w, h, T, xmin, xmax, ymin, ymax )
  assert(types.isType(A))
  map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T>=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  return darkroom.compose("stencilLinebuffer", darkroom.SSR( A, T, xmin, ymin), darkroom.linebuffer( A, w, h, T, ymin ) )
end

-- this has type StatefulV -> StatefulRV
function darkroom.stencilLinebufferPartial( A, w, h, T, xmin, xmax, ymin, ymax )
  map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T<=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  -- SSRPartial need to be able to stall the linebuffer, so we must do this with handshake interfaces. Systolic pipelines can't stall each other
  return darkroom.compose("stencilLinebufferPartial", darkroom.liftHandshake(darkroom.waitOnInput(darkroom.SSRPartial( A, T, xmin, ymin ))), darkroom.makeHandshake(darkroom.linebuffer( A, w, h, 1, ymin )) )
end

-- purely wiring
function darkroom.unpackStencil( A, stencilW, stencilH, T )
  assert(types.isType(A))
  assert(type(stencilW)=="number")
  assert(stencilW>0)
  assert(type(stencilH)=="number")
  assert(stencilH>0)
  assert(type(T)=="number")
  assert(T>=1)

  local res = {kind="unpackStencil", stencilW=stencilW, stencilH=stencilH,T=T}
  res.inputType = types.array2d( A, stencilW+T-1, stencilH)
  res.outputType = types.array2d( types.array2d( A, stencilW, stencilH), T )
  res.delay=0
  local struct UnpackStencil {}
  terra UnpackStencil:reset() end
  terra UnpackStencil:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for i=0,[T] do
      for y=0,[stencilH] do
        for x=0,[stencilW] do
          (@out)[i][y*stencilW+x] = (@inp)[y*(stencilW+T-1)+x+i]
        end
      end
    end
  end
  res.terraModule = UnpackStencil

  res.systolicModule = S.moduleConstructor("unpackStencil"):CE(true)
  local sinp = S.parameter("inp", res.inputType)
  local out = {}
  for i=1,T do
    out[i] = {}
    for y=0,stencilH-1 do
      for x=0,stencilW-1 do
        out[i][y*stencilW+x+1] = S.index( sinp, x+i-1, y )
      end
    end
  end

  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple(map(out,function(n) return S.cast( S.tuple(n), types.array2d(A,stencilW,stencilH) ) end)), res.outputType ), "process_output" ) )
  --res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro" ) )

  return darkroom.newFunction(res)
end

darkroom.makeStateful = memoize(function( f )
  assert( darkroom.isFunction(f) )
  local res = { kind="makeStateful", fn = f }
  darkroom.expectPure(f.inputType)
  darkroom.expectPure(f.outputType)
  res.inputType = darkroom.Stateful(f.inputType)
  res.outputType = darkroom.Stateful(f.outputType)
  res.sdfInput, res.sdfOutput = {1,1},{1,1}
  assert(types.isType(res.inputType))
  res.delay = f.delay
  res.terraModule = f.terraModule
  assert(S.isModule(f.systolicModule))
  res.systolicModule = S.moduleConstructor("MakeStateful_"..f.systolicModule.name):CE(true)
  local inner = res.systolicModule:add( f.systolicModule:instantiate("MakeStateful_inner") )
  local sinp = S.parameter("process_input", f.inputType )
  res.systolicModule:addFunction( S.lambda("process", sinp, inner:process(sinp), "process_output") )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {},S.parameter("reset",types.bool())) )

  return darkroom.newFunction(res)
                                end)

-- we could construct this out of liftHandshake, but this is a special case for when we don't need a fifo b/c this is always ready
darkroom.makeHandshake = memoize(function( f )
  assert( darkroom.isFunction(f) )
  local res = { kind="makeHandshake", fn = f }
  darkroom.expectStateful(f.inputType)
  darkroom.expectStateful(f.outputType)
  res.inputType = darkroom.StatefulHandshake(darkroom.extractStateful(f.inputType))
  res.outputType = darkroom.StatefulHandshake(darkroom.extractStateful(f.outputType))
  res.sdfInput, res.sdfOutput = {1,1},{1,1}

  local delay = math.max( 1, f.delay )
  --assert(delay>0)
  -- we don't need an input fifo here b/c ready is always true
  local struct MakeHandshake{ delaysr: simmodules.fifo( darkroom.extract(res.outputType):toTerraType(), delay, "makeHandshake"),
--                              fifo: simmodules.fifo( darkroom.extract(f.outputType):toTerraType(), DEFAULT_FIFO_SIZE),
                              inner: f.terraModule}
  terra MakeHandshake:reset() self.delaysr:reset(); self.inner:reset() end
  terra MakeHandshake:stats( name : &int8 )  end
  
  -- if inner function is const, consider input to always be valid
  local innerconst = darkroom.extractStateful(f.outputType):const()
  terra MakeHandshake:process( inp : &darkroom.extract(res.inputType):toTerraType(), 
                               out : &darkroom.extract(res.outputType):toTerraType())
    
    if self.delaysr:size()==delay then
      var ot = self.delaysr:popFront()
      valid(out) = valid(ot)
      data(out) = data(ot)
    else
      valid(out)=false
    end

    var tout : darkroom.extract(res.outputType):toTerraType()
    valid(tout) = valid(inp)
    if valid(inp) or innerconst then self.inner:process(&data(inp),&data(tout)) end -- don't bother if invalid
    self.delaysr:pushBack(&tout)
  end
  res.terraModule = MakeHandshake

  -- We _NEED_ to set an initial value for the shift register output (invalid), or else stuff downstream can get strange values before the pipe is primed
  res.systolicModule = S.moduleConstructor( "MakeHandshake_"..f.systolicModule.name):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

  local printInst = res.systolicModule:add( S.module.print( types.tuple{types.bool(),types.bool(),darkroom.extractStateful(f.outputType),types.bool(),types.bool(),types.uint(16)}, "RST %d IV %d O %h OV %d ready %d expectedOutput %d", true):instantiate("printInst") )

  local SR = res.systolicModule:add( fpgamodules.shiftRegister( types.bool(), f.systolicModule:getDelay("process"), "MakeHandshakeValidBitDelay_"..f.systolicModule.name.."_"..f.systolicModule:getDelay("process"), false ):CE(true):instantiate("validBitDelay_"..f.systolicModule.name):setCoherent(false) )
  local inner = res.systolicModule:add(f.systolicModule:instantiate("inner"))
  local pinp = S.parameter("process_input", darkroom.extract(res.inputType) )
  local rst = S.parameter("reset",types.bool())
  if f.systolicModule.functions.reset:isPure() then rst = S.constant(false, types.bool()) end

  local pipelines = {}
  local asstInst = res.systolicModule:add( S.module.assert( "MakeHandshake: input valid bit should not be X!" ,false):instantiate("asstInst") )
  pipelines[1] = asstInst:process(S.__not(S.isX(S.index(pinp,1))), S.constant(true,types.bool()) )

  local pready = S.parameter("ready_downstream", types.bool())
  local out = S.tuple({inner:process(S.index(pinp,0),S.index(pinp,1)), SR:pushPop(S.index(pinp,1), S.__not(rst))})
  table.insert(pipelines, printInst:process( S.tuple{ rst, S.index(pinp,1), S.index(out,0), S.index(out,1), pready, S.instanceParameter("OUTPUT_COUNT",types.uint(16)) } ) )

  res.systolicModule:addFunction( S.lambda("process", pinp, out, "process_output", pipelines) ) 
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(nil,rst), "reset_out",{SR:reset(nil,rst)},rst) )

  res.systolicModule:addFunction( S.lambda("ready", pready, pready, "ready", {inner:CE(S.__or(pready,rst)),SR:CE(S.__or(pready,rst))} ) )

  return darkroom.newFunction(res)
                                 end)

function darkroom.reduce( f, W, H )
  if darkroom.isFunction(f)==false then error("Argument to reduce must be a darkroom function") end
  assert(type(W)=="number")
  assert(type(H)=="number")

  local res = {kind="reduce", fn = f}
  darkroom.expectPure(f.inputType)
  darkroom.expectPure(f.outputType)
  if f.inputType:isTuple()==false or f.inputType~=types.tuple({f.outputType,f.outputType}) then
    error("Reduction function f must be of type {A,A}->A, "..loc)
  end
  res.inputType = types.array2d( f.outputType, W, H )
  res.outputType = f.outputType
  res.sdfInput, res.sdfOutput = {1,1},{1,1}
  res.delay = math.ceil(math.log(res.inputType:channels())/math.log(2))*f.delay
  local struct ReduceModule { inner: f.terraModule }
  terra ReduceModule:reset() self.inner:reset() end
  terra ReduceModule:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
      var res : res.outputType:toTerraType() = (@inp)[0]
      for i=1,W*H do
        var tinp : f.inputType:toTerraType() = {res, (@inp)[i]}
        self.inner:process( &tinp, &res  )
      end
      @out = res
  end
  res.terraModule = ReduceModule

  res.systolicModule = S.moduleConstructor("reduce_"..f.systolicModule.name):CE(true)
  local resetPipelines = {}
  local sinp = S.parameter("process_input", res.inputType )
  local t = map( range2d(0,W-1,0,H-1), function(i) return S.index(sinp,i[1],i[2]) end )
  local i=0
  local expr = foldt(t, function(a,b) 
                       local I = res.systolicModule:add(f.systolicModule:instantiate("inner"..i))
                       --table.insert( resetPipelines, I:reset() ) -- no reset for pure functions
                       i = i + 1
                       return I:process(S.tuple{a,b}) end, nil )
  res.systolicModule:addFunction( S.lambda( "process", sinp, expr, "process_output" ) )
  --res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, S.parameter("reset",types.bool())) )

  return darkroom.newFunction( res )
end


function darkroom.reduceSeq( f, T )
  assert(T<=1)

  if f.inputType:isTuple()==false or f.inputType~=types.tuple({f.outputType,f.outputType}) then
    error("Reduction function f must be of type {A,A}->A, "..loc)
  end

  local res = {kind="reduceSeq", fn=f}
  darkroom.expectPure(f.outputType)
  res.inputType = darkroom.Stateful(f.outputType)
  res.outputType = darkroom.StatefulV(f.outputType)
  res.sdfInput, res.sdfOutput = {1/T,1},{1,1}
  assert(f.delay==0)
  res.delay = 0
  local struct ReduceSeq { phase:int; result : f.outputType:toTerraType(); inner : f.terraModule}
  terra ReduceSeq:reset() self.phase=0; self.inner:reset() end
  terra ReduceSeq:process( inp : &f.outputType:toTerraType(), out : &darkroom.extract(res.outputType):toTerraType())
    if self.phase==0 and T==1 then -- T==1 mean this is a noop, passthrough
      self.phase = 0
      valid(out) = true
      data(out) = @inp
    elseif self.phase==0 then 
      self.result = @inp
      self.phase = self.phase + 1
      valid(out) = false
    else
      var v = {self.result, @inp}
      self.inner:process(&v,&self.result)
      
      if self.phase==[1/T]-1 then
        self.phase = 0
        valid(out) = true
        data(out) = self.result
      else
        self.phase = self.phase + 1
        valid(out) = false
      end
    end
  end
  res.terraModule = ReduceSeq

  err( f.systolicModule:getDelay("process") == 0, "ReduceSeq function must have delay==0" )

  res.systolicModule = S.moduleConstructor("ReduceSeq_"..f.systolicModule.name):CE(true)
  local printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(16),f.outputType,f.outputType}, "ReduceSeq "..f.systolicModule.name.." phase %d input %d output %d", true):instantiate("printInst") )
  local sinp = S.parameter("process_input", f.outputType )
  local svalid = S.parameter("process_valid", types.bool() )
  --local phaseValue, phaseValid, phasePipelines, phaseResetPipelines = fpgamodules.addPhaser( res.systolicModule, 1/T, svalid )
  local phase = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.sumwrap( (1/T)-1 ) ):includeCE():instantiate("phase") )
  
  local pipelines = {}
  table.insert(pipelines, phase:setBy( S.constant(1,types.uint(16)) ) )

  local out
  
  if T==1 then
    -- hack: Our reduce fn always adds two numbers. If we only have 1 number, it won't work! just return the input.
    out = sinp
  else
    local sResult = res.systolicModule:add( S.module.regByConstructor( f.outputType, f.systolicModule ):includeCE():instantiate("result") )
    table.insert( pipelines, sResult:set( sinp, S.eq(phase:get(), S.constant(0, types.uint(16) ) ):disablePipelining() ) )
    out = sResult:setBy( sinp, S.__not(S.eq(phase:get(), S.constant(0, types.uint(16) ) )):disablePipelining() )
  end

  table.insert(pipelines, printInst:process( S.tuple{phase:get(),sinp,out} ) )

  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ out, S.eq(phase:get(), S.constant( (1/T)-1, types.uint(16))) }, "process_output", pipelines, svalid) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(16)))}, S.parameter("reset",types.bool())) )

  return darkroom.newFunction( res )
end

-- surpresses output if we get more then _count_ inputs
darkroom.overflow = memoize(function( A, count )
  darkroom.expectPure(A)
  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="overflow", A=A, inputType=darkroom.Stateful(A), outputType=darkroom.StatefulV(A), count=count, sdfInput={1,1}, sdfOutput={1,1}, delay=0}
  local struct Overflow {cnt:int}
  terra Overflow:reset() self.cnt=0 end
  terra Overflow:process( inp : &A:toTerraType(), out:&darkroom.extract(res.outputType):toTerraType())
    data(out) = @inp
    valid(out) = (self.cnt<count)
    self.cnt = self.cnt+1
  end
  res.terraModule = Overflow
  res.systolicModule = S.moduleConstructor("Overflow_"..count):CE(true)
  local cnt = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIf()):includeCE():instantiate("cnt") )

  local sinp = S.parameter("process_input", A )
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ sinp, S.lt(cnt:get(), S.constant( count, types.uint(16))) }, "process_output", {cnt:setBy(S.constant(true,types.bool()))} ) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {cnt:set(S.constant(0,types.uint(16)))}, S.parameter("reset",types.bool())) )

  return darkroom.newFunction( res )
                            end)

function darkroom.cat2d( A,T,w,h )
  assert(types.isType(A))
  assert(A:isArray()==false)
  assert(T<1)
  assert(type(w)=="number")
  assert(type(h)=="number")
  local res = {kind="cat2d"}
  res.inputType=darkroom.Stateful(types.array2d(A,w*T,h))
  res.outputType=darkroom.StatefulV(types.array2d(A,w,h))
  res.delay=0
  local struct Cat2d { phase:int; result: (A:toTerraType())[w*h] }
  terra Cat2d:reset() self.phase=0 end
  local W = w*T
  terra Cat2d:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType())
    for y=0,h do
      for X=0,W do
        var x = X+self.phase*W
        self.result[y*w+x] = (@inp)[y*W+X]
      end
    end

    if self.phase==[1/T]-1 then
      data(out) = self.result
      valid(out) = true
      self.phase=-1
    else
      valid(out) = false
    end

    self.phase = self.phase+1
  end
  res.terraModule = Cat2d
  return darkroom.newFunction( res )
end

-- function argument
function darkroom.input( type )
  assert( types.isType( type ) )
  return darkroom.newIR( {kind="input", type = type, name="input", id={}, inputs={}} )
end

function callOnEntries( T, fnname )
  local TS = symbol(&T,"self")
  local ssStats = {}
  for k,v in pairs( T.entries ) do if v.type:isstruct() then table.insert( ssStats, quote TS.[v.field]:[fnname]() end) end end
  T.methods[fnname] = terra([TS]) [ssStats] end
end

-- function definition
-- output, inputs
function darkroom.lambda( name, input, output, sdfOverride, X )
  assert(X==nil)
  assert( type(name) == "string" )
  assert( darkroom.isIR( input ) )
  assert( input.kind=="input" )
  assert( darkroom.isIR( output ) )

  local output = output:typecheck()
  local res = {kind = "lambda", name=name, input = input, output = output }
  res.inputType = input.type
  res.outputType = output.type

  if darkroom.isStatefulHandshake( input.type ) == false then
  res.delay = output:visitEach(
    function(n, inputs)
      if n.kind=="input" or n.kind=="constant" then
        return 0
      elseif n.kind=="extractState" then
        print("DIDX",inputs[1])
        return inputs[1]
      elseif n.kind=="tuple" then
        print("DTUP",math.max(unpack(inputs)))
        return math.max(unpack(inputs))
      elseif n.kind=="apply" then
        return inputs[1] + n.fn.delay
      else
        print(n.kind)
        assert(false)
      end
    end)
  end

  local function docompile( fn )
    local inputSymbol = symbol( &darkroom.extract(fn.input.type):toTerraType(), "lambdainput" )
    local outputSymbol = symbol( &darkroom.extract(fn.output.type):toTerraType(), "lambdaoutput" )

    local stats = {}
    local resetStats = {}
    local readyStats = {}
    local statStats = {}
    local readyInput = symbol(bool, "readyinput")
    local Module = terralib.types.newstruct("lambda"..fn.name.."_module")
    Module.entries = terralib.newlist( {} )
    local mself = symbol( &Module, "module self" )

    local usedNames = {}

    local out = fn.output:visitEach(
      function(n, inputs)

        --if true then table.insert( stats, quote cstdio.printf([n.name.."\n"]) end ) end

        local out

        if n==fn.output then
          out = outputSymbol
        elseif n.kind=="applyRegStore" then
        elseif n.kind~="input" then
          table.insert( Module.entries, {field="simstateoutput_"..n.name, type=darkroom.extract(n.type):toTerraType()} )
          out = `&mself.["simstateoutput_"..n.name]
        end

        if n.kind=="input" then
          print("N",n,n.type,"FNINP",fn.input,fn.input.type)
          if n.id~=fn.input.id then error("Input node is not the specified input to the lambda") end
          return {inputSymbol, readyInput}
        elseif n.kind=="apply" then
          print("APPLY",n.fn.kind, n.inputs[1].type, n.type)
          print("APP",n.name, n.fn.terraModule, "inputtype",n.fn.inputType,"outputtype",n.fn.outputType)
          table.insert( Module.entries, {field=n.name, type=n.fn.terraModule} )
          table.insert( resetStats, quote mself.[n.name]:reset() end )
          table.insert( statStats, quote mself.[n.name]:stats([n.name]) end )

          local readyOut = symbol( bool, "ready_"..n.name )
          if darkroom.isStatefulV(n.inputs[1].type) then table.insert( readyStats, quote var [readyOut] = mself.[n.name]:ready() end) 
          elseif darkroom.isStatefulRV(n.inputs[1].type) then table.insert( readyStats, quote var [readyOut] = mself.[n.name]:ready([inputs[1][2]]) end) end

          table.insert( stats, quote mself.[n.name]:process( [inputs[1][1]], out ) end )

if darkroom.isStatefulHandshake(n.inputs[1].type) or darkroom.isStatefulHandshake(n.type) then
  table.insert( Module.entries, {field=n.name.."CNT", type=int} )
  table.insert( resetStats, quote mself.[n.name.."CNT"]=0 end )

  table.insert( Module.entries, {field=n.name.."ICNT", type=int} )
  table.insert( resetStats, quote mself.[n.name.."ICNT"]=0 end )

local Q = quote end
                if darkroom.isStatefulHandshake(n.inputs[1].type) then Q = quote if valid([inputs[1][1]]) then mself.[n.name.."ICNT"]=mself.[n.name.."ICNT"]+1 end end
end
table.insert( stats, quote cstdio.printf("APPLY %s inpv %d outv %d cnt %d icnt %d\n",n.name, valid([inputs[1][1]]), valid(out),mself.[n.name.."CNT"],mself.[n.name.."ICNT"] );
                Q
                if valid(out) then mself.[n.name.."CNT"]=mself.[n.name.."CNT"]+1 end
 end )
end
          return {out,readyOut}
        elseif n.kind=="applyRegLoad" then
          if usedNames[n.name]==nil then
            table.insert( Module.entries, {field=n.name, type=n.fn.terraModule} )
          end
          usedNames[n.name] = 1
          table.insert( statStats, quote mself.[n.name]:stats([n.name]) end )
          table.insert( stats, quote mself.[n.name]:load( out ) end )
          return {out}
        elseif n.kind=="applyRegStore" then
          if usedNames[n.name]==nil then
            table.insert( Module.entries, {field=n.name, type=n.fn.terraModule} )
          end
          usedNames[n.name] = 1
          table.insert( resetStats, quote mself.[n.name]:reset() end )
          table.insert( stats, quote mself.[n.name]:store( [inputs[1][1]] ) end )
          return {`nil}
        elseif n.kind=="constant" then
          if n.type:isArray() then
            map( n.value, function(m,i) table.insert( stats, quote (@out)[i-1] = m end ) end )
          else
            assert(false)
          end

          return {out}
        elseif n.kind=="tuple" then
          map(inputs, function(m,i) local ty = darkroom.extract(darkroom.extract(n.type).list[i])
              table.insert(stats, quote cstring.memcpy(&(@out).["_"..(i-1)],[m[1]],[ty:sizeof()]) end) end)
          return {out}
--        elseif n.kind=="index" then
--          table.insert( stats, quote @out = [inputs[1][1]].["_"..n.idx] end)
--          return {out}
        elseif n.kind=="extractState" then
          return {`nil}
        elseif n.kind=="catState" then
          table.insert( stats, quote @out = @[inputs[1][1]] end)
          return {out,inputs[1][2]}
        else
          print(n.kind)
          assert(false)
        end
      end)

--    callOnEntries(Module,"reset")

    terra Module.methods.process( [mself], [inputSymbol], [outputSymbol] )
--        cstdio.printf([fn.name.."\n"])
      [stats]
    end
    terra Module.methods.reset( [mself] ) [resetStats] end
    terra Module.methods.stats( [mself], name:&int8 ) [statStats] end
    if darkroom.isStatefulRV(res.inputType) then
      assert(out[2]~=nil)
      terra Module.methods.ready( [mself], [readyInput] ) [readyStats]; return [out[2]] end
    elseif darkroom.isStatefulRV(res.outputType) then
      assert(out[2]~=nil)
      terra Module.methods.ready( [mself] ) [readyStats]; return [out[2]] end
    else
      --terra Module.methods.ready( [mself] ) [readyStats]; return [out[2]] end
    end
    --Module:printpretty()
    --Module.methods.process:printpretty(false)
    --print("PP")
    --Module.methods.process:printpretty()
    --print("PPDONE")
    return Module
  end

  res.terraModule = docompile(res)
  
  res.sdfInput = {1,1}
  if sdfOverride~=nil then
    res.sdfOutput = sdfOverride
  else
    res.sdfOutput = output:sdfTotal()
  end

  local function makeSystolic( fn )
    local module = S.moduleConstructor( fn.name ):CE( not darkroom.isStatefulHandshake(fn.inputType) ):onlyWire(darkroom.isStatefulHandshake(fn.inputType))

    if darkroom.isStatefulHandshake(fn.outputType) then
      module:parameters{INPUT_COUNT=0, OUTPUT_COUNT=0}
    end

    local inp = S.parameter( "process_input", darkroom.extract(fn.inputType) )
    local rst = S.parameter( "reset", types.bool() )
    local readyInput = S.parameter( "ready_input", types.bool() )
    local resetPipelines = {}

    local instanceMap = {}
    local out = fn.output:visitEach(
      function(n, inputs)
        if n.kind=="input" then
          return {inp, sel(darkroom.isStatefulRV(n.type), readyInput, nil) }
        elseif n.kind=="apply" then
          print("systolic APPLY",n.fn.kind)
          err( n.fn.systolicModule~=nil, "Error, missing systolic module for "..n.fn.kind)
          print("APPLY",n.fn.systolicModule.functions.process.input.type,n.fn.systolicModule.functions.process.output.type)
          err( n.fn.systolicModule.functions.process.input.type==darkroom.extract(n.fn.inputType), "Systolic type doesn't match fn type, fn '"..n.fn.kind.."', is "..tostring(n.fn.systolicModule.functions.process.input.type).." but should be "..tostring(darkroom.extract(n.fn.inputType)) )
          err( n.fn.systolicModule.functions.process.output.type:constSubtypeOf(darkroom.extract(n.fn.outputType)), "Systolic output type doesn't match fn type, fn '"..n.fn.kind.."', is "..tostring(n.fn.systolicModule.functions.process.output.type).." but should be "..tostring(darkroom.extract(n.fn.outputType)) )

          local params
          if darkroom.isStatefulHandshake( n.fn.inputType ) then
            local IC = n.inputs[1]:sdfTotal()
            local OC = n:sdfTotal()
            params={INPUT_COUNT="(INPUT_COUNT*"..IC[1]..")/"..IC[2],OUTPUT_COUNT="(INPUT_COUNT*"..OC[1]..")/"..OC[2]}
            print("PARAMS")
          end

          local I = n.fn.systolicModule:instantiate(n.name,nil,nil,nil,params)
          instanceMap[n] = I
          module:add(I)
          if darkroom.isStatefulHandshake( n.fn.inputType ) then
            table.insert( resetPipelines, I:reset(nil,rst) )
          elseif darkroom.isPure( n.fn.inputType )==false then
            print("CALLRESET",n.fn.kind)
            table.insert( resetPipelines, I:reset() )
          end


          if darkroom.isStatefulV(n.inputs[1].type) then
            return { I:process(inputs[1][1]), I:ready() }
          elseif darkroom.isStatefulRV(n.inputs[1].type) then
            return { I:process(inputs[1][1]), I:ready(inputs[1][2]) }
          elseif darkroom.isStatefulRV(n.type) then
            -- the strange Stateful->StatefulRV case
            err( false, "You shouldn't use Stateful->StatefulRV directly, loc "..n.loc )
          else
            return {I:process(inputs[1][1])}
          end
        elseif n.kind=="constant" then
          return {S.constant( n.value, n.type )}
        elseif n.kind=="tuple" then
          return {S.tuple( map(inputs,function(i) return i[1] end) ) }
        elseif n.kind=="extractState" then
          return {S.null()}
        else
          print(n.kind)
          assert(false)
        end
      end)

    err( out[1].type:constSubtypeOf(darkroom.extract(res.outputType)), "Internal error, systolic type is "..tostring(out[1].type).." but should be "..tostring(darkroom.extract(res.outputType)).." function "..name )

    local processfn = S.lambda( "process", inp, out[1], "process_output" )
    local process = module:addFunction( processfn )

    if darkroom.isStatefulHandshake( fn.inputType ) then
      module:addFunction( S.lambda("reset", S.parameter("ri",types.null()), nil, "reset_out", resetPipelines, rst) )
    elseif darkroom.isStateful( fn.inputType) then -- pure fns don't have a reset
      module:addFunction( S.lambda("reset", S.parameter("nip",types.null()), nil, "reset_out", resetPipelines, S.parameter("reset", types.bool() ) ) )
    end

    if darkroom.isStatefulRV( fn.inputType ) then
      assert( S.isAST(out[2]) )
      local readyfn = module:addFunction( S.lambda("ready", readyInput, out[2], "ready", {} ) )
    elseif darkroom.isStatefulRV( fn.outputType ) then
      local readyfn = module:addFunction( S.lambda("ready", S.parameter("RINIL",types.null()), out[2], "ready", {} ) )
    elseif darkroom.isStatefulHandshake( fn.inputType ) then
      local readyinp = S.parameter( "ready_downstream", types.bool() )
      local readyout
      fn.output:visitEachReverse(
        function(n, inputs)
          local input = foldt( stripkeys(inputs), function(a,b) return S.__and(a,b) end, readyinp )

          if n.kind=="input" then
            assert(readyout==nil)
            readyout = input
            return nil
          elseif n.kind=="apply" then
            print("systolic ready APPLY",n.fn.kind)
            return instanceMap[n]:ready(input)
          elseif n.kind=="tuple" then
            return input
          else
            print(n.kind)
            assert(false)
          end
        end)

      local readyfn = module:addFunction( S.lambda("ready", readyinp, readyout, "ready", {} ) )
      --assert( readyfn:isPure() )
    end

    return module
  end
  res.systolicModule = makeSystolic(res)
  res.systolicModule:toVerilog()

  return darkroom.newFunction( res )
end

function darkroom.lift( name, inputType, outputType, delay, terraFunction, systolicInput, systolicOutput )
  err( type(name)=="string", "lift name must be string" )
  assert( types.isType(inputType ) )
  assert( types.isType(outputType ) )
  assert( type(delay)=="number" )
  err( systolic.isAST(systolicOutput), "missing systolic output")

  local struct LiftModule {}
  terra LiftModule:reset() end
  terra LiftModule:stats( name : &int8 )  end
  terra LiftModule:process(inp:&darkroom.extract(inputType):toTerraType(),out:&darkroom.extract(outputType):toTerraType()) terraFunction(inp,out) end

  err( systolicOutput.type:constSubtypeOf(outputType), "lifted systolic output type does not match. Is "..tostring(systolicOutput.type).." but should be "..tostring(outputType) )

  local systolicModule = S.moduleConstructor(name):CE(true)
  systolicModule:addFunction( S.lambda("process", systolicInput, systolicOutput, "process_output") )
  local nip = S.parameter("nip",types.null())
  --systolicModule:addFunction( S.lambda("reset", nip, nil,"reset_output") )
  systolicModule:complete()
  local res = { kind="lift_"..name, inputType = inputType, outputType = outputType, delay=delay, terraModule=LiftModule, systolicModule=systolicModule, sdfInput={1,1}, sdfOutput={1,1} }
  return darkroom.newFunction( res )
end

local function getloc()
  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline
end

function darkroom.apply( name, fn, input )
  assert( type(name) == "string" )
  assert( darkroom.isFunction(fn) )
  assert( darkroom.isIR( input ) )

  return darkroom.newIR( {kind = "apply", name = name, loc=getloc(), fn = fn, inputs = {input} } )
end

function darkroom.applyRegLoad( name, fn, input )
  return darkroom.newIR( {kind = "applyRegLoad", name = name, loc=getloc(), fn = fn, inputs = {input} } )
end

function darkroom.applyRegStore( name, fn, input )
  return darkroom.newIR( {kind = "applyRegStore", name = name, loc=getloc(), fn = fn, inputs = {input} } )
end

function darkroom.constSeq( value, A, w, h, T )
  assert(type(value)=="table")
  assert(type(value[1])=="number")
  assert(#value==w*h)


--  assert(type(value[1][1])=="number")
  assert(T<=1)
  assert( types.isType(A) )
  assert(type(w)=="number")
  assert(type(h)=="number")

  local res = { kind="constSeq", A = A, w=w, h=h, value=value, T=T}
  res.inputType = darkroom.State
  local W = w*T
  if W ~= math.floor(W) then error("constSeq T must divide array size, "..loc) end
  res.outputType = darkroom.Stateful(types.array2d(A,W,h))
  res.sdfInput, res.sdfOutput = {1,1}, {1,1}  -- well, technically this produces 1 output for every (nil) input

  res.delay = 0
  local struct ConstSeqState {phase : int; data : (A:toTerraType())[h*W][1/T] }
  local mself = symbol(&ConstSeqState,"mself")
  local initstats = {}
--  map( value, function(m,i) table.insert( initstats, quote mself.data[[(i-1)]][] = m end ) end )
  for C=0,(1/T)-1 do
    for y=0,h-1 do
      for x=0,W-1 do
        print("C",C,"X",x,"Y",y,"w",w,"h",h,"#",#value,value[x+y*w+C*W+1])
--        local I = 
        table.insert( initstats, quote mself.data[C][y*W+x] = [value[x+y*w+C*W+1]] end )
      end
    end
  end
  terra ConstSeqState.methods.reset([mself]) mself.phase = 0; [initstats] end
  terra ConstSeqState:process( inp : &res.inputType:toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    @out = self.data[self.phase]
    self.phase = self.phase + 1
    if self.phase == [1/T] then self.phase = 0 end
  end
  res.terraModule = ConstSeqState
  res.systolicModule = S.moduleConstructor("constSeq"):CE(true)
  local sconsts = map(range(1/T), function() return {} end)
  for C=0, (1/T)-1 do
    for y=0, h-1 do
      for x=0, W-1 do
        table.insert(sconsts[C+1], value[y*w+C*W+x+1])
      end
    end
  end
  local shiftOut, shiftPipelines = fpgamodules.addShifter( res.systolicModule, map(sconsts, function(n) return S.constant(n,types.array2d(A,W,h)) end) )

  if shiftOut.type:const() then
    -- this happens if we have an array of size 1, for example (becomes a passthrough). Strip the const-ness so that the module returns a consistant type with different parameters.
    shiftOut = S.cast(shiftOut, shiftOut.type:stripConst())
  end

  local inp = S.parameter("process_input", types.null() )

  res.systolicModule:addFunction( S.lambda("process", inp, shiftOut, "process_output", shiftPipelines ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("process_nilinp", types.null() ), nil, "process_reset", {}, S.parameter("reset", types.bool() ) ) )

  return darkroom.newFunction( res )
end

function darkroom.constant( name, value, ty )
  assert( type(name) == "string" )
  assert( types.isType(ty) )

  return darkroom.newIR( {kind="constant", name=name, value=value, type=ty, inputs = {}} )
end

function darkroom.tuple( name, t )
  assert( type(t)=="table" )
  local r = {kind="tuple", name=name, loc=getloc(), inputs={}}
  map(t, function(n,k) assert(darkroom.isIR(n)); table.insert(r.inputs,n) end)
  return darkroom.newIR( r )
end

-- if index==true, then we return a value, not an array
darkroom.slice = memoize(function( inputType, idxLow, idxHigh, idyLow, idyHigh, index )
  assert( types.isType(inputType) )
  assert(type(idxLow)=="number")
  assert(type(idxHigh)=="number")

  if inputType:isTuple() then
    assert( idxLow < #inputType.list )
    assert( idxHigh < #inputType.list )
    assert( idxLow == idxHigh ) -- NYI
    assert( index )
    local OT = inputType.list[idxLow+1]
    local systolicInput = S.parameter("inp", inputType)
    local systolicOutput = S.index( systolicInput, idxLow )
    local tfn = terra( inp:&darkroom.extract(inputType):toTerraType(), out:&darkroom.extract(OT):toTerraType()) @out = inp.["_"..idxLow] end
    return darkroom.lift( "index_"..tostring(inputType):gsub('%W','_').."_"..idxLow, inputType, OT, 0, tfn, systolicInput, systolicOutput )
  elseif inputType:isArray() then
    local W = (inputType:arrayLength())[1]
    local H = (inputType:arrayLength())[2]
    assert(idxLow<W)
    assert(idxHigh<W)
    assert(type(idyLow)=="number")
    assert(type(idyHigh)=="number")
    assert(idyLow<H)
    assert(idyHigh<H)
    assert(idxLow<=idxHigh)
    assert(idyLow<=idyHigh)
    local OT = types.array2d( inputType:arrayOver(), idxHigh-idxLow+1, idyHigh-idyLow+1 )
    local systolicInput = S.parameter("inp",inputType)

    local systolicOutput = S.tuple( map( range2d(idxLow,idxHigh,idyLow,idyHigh), function(i) return S.index( systolicInput, i[1], i[2] ) end ) )
    systolicOutput = S.cast( systolicOutput, OT )
    local tfn = terra(inp:&darkroom.extract(inputType):toTerraType(), out:&darkroom.extract(OT):toTerraType()) 
      for iy = idyLow,idyHigh+1 do
        for ix = idxLow, idxHigh+1 do
          (@out)[(iy-idyLow)*(idxHigh-idxLow+1)+(ix-idxLow)] = (@inp)[ix+iy*W] 
        end
      end
    end

    if index then
      OT = inputType:arrayOver()
      systolicOutput = S.index( systolicInput, idxLow, idyLow )
      tfn = terra(inp:&darkroom.extract(inputType):toTerraType(), out:&darkroom.extract(OT):toTerraType()) @out = (@inp)[idxLow+idyLow*W] end
    end

    return darkroom.lift( "slice_"..idxLow, inputType, OT, 0, tfn, systolicInput, systolicOutput )
  else
    assert(false)
  end
                         end)

function darkroom.index( inputType, idx, idy )
  err( types.isType(inputType), "first input to index must be a type" )
  return darkroom.slice( inputType, idx, idx, idy, idy, true )
end

-- this is for driving stateful functions with no input
function darkroom.extractState( name, input )
  assert(type(name)=="string")
  assert(darkroom.isIR( input ) )
  return darkroom.newIR( {kind="extractState", name=name, loc=getloc(), inputs={input}, type=darkroom.State} )
end

function darkroom.catState( name, input, state )
  assert(type(name)=="string")
  assert(darkroom.isIR( input ) )
  assert(darkroom.isIR( state ) )
  return darkroom.newIR( {kind="catState", name=name, loc=getloc(), inputs={input,state}} )
end

darkroom.freadSeq = memoize(function( filename, ty )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  darkroom.expectPure(ty)
  local filenameVerilog=filename
  local res = {kind="freadSeq", filename=filename, filenameVerilog=filenameVerilog, type=darkroom.Stateful(ty), inputType=darkroom.Stateful(types.null()), outputType=darkroom.Stateful(ty), delay=0}
  local struct FreadSeq { file : &cstdio.FILE }
  terra FreadSeq:reset() 
    self.file = cstdio.fopen(filename, "rb") 
    darkroomAssert(self.file~=nil, ["file "..filename.." doesnt exist"])
  end
  terra FreadSeq:process(inp : &types.null():toTerraType(), out : &ty:toTerraType())
    var outBytes = cstdio.fread(out,1,[ty:sizeof()],self.file)
    darkroomAssert(outBytes==[ty:sizeof()], "Error, freadSeq failed, probably end of file?")
  end
  res.terraModule = FreadSeq
  res.systolicModule = S.moduleConstructor("freadSeq_"..filename:gsub('%W','_')):CE(true)
  local sfile = res.systolicModule:add( S.module.file( filenameVerilog, ty ):instantiate("freadfile") )
  local inp = S.parameter("process_input", types.null() )
  local nilinp = S.parameter("process_nilinp", types.null() )
  res.systolicModule:addFunction( S.lambda("process", inp, sfile:read(), "process_output" ) )
  res.systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", {sfile:reset()}, S.parameter("reset", types.bool() ) ) )

  return darkroom.newFunction(res)
                            end)

function darkroom.fwriteSeq( filename, ty )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  darkroom.expectPure(ty)
  local filenameVerilog=filename
  local res = {kind="fwriteSeq", filename=filename, filenameVerilog=filenameVerilog, type=ty, inputType=darkroom.Stateful(ty), outputType=darkroom.Stateful(ty), delay=0}
  local struct FwriteSeq { file : &cstdio.FILE }
  terra FwriteSeq:reset() 
    self.file = cstdio.fopen(filename, "wb") 
    darkroomAssert( self.file~=nil, ["Error opening "..filename.." for writing"] )
  end
  terra FwriteSeq:process(inp : &ty:toTerraType(), out : &ty:toTerraType())
    cstdio.fwrite(inp,[ty:sizeof()],1,self.file)
    @out = @inp
  end
  res.terraModule = FwriteSeq
  res.systolicModule = S.moduleConstructor("fwriteSeq_"..filename:gsub('%W','_')):CE(true)
  local sfile = res.systolicModule:add( S.module.file( filenameVerilog, ty ):instantiate("fwritefile") )
  local printInst = res.systolicModule:add( S.module.print( ty, "fwrite O %h", true):instantiate("printInst") )

  local inp = S.parameter("process_input", ty )
  local nilinp = S.parameter("process_nilinp", types.null() )
  res.systolicModule:addFunction( S.lambda("process", inp, inp, "process_output", {sfile:write(inp),printInst:process(inp)} ) )
  res.systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", {sfile:reset()}, S.parameter("reset", types.bool() ) ) )

  return darkroom.newFunction(res)
end

function darkroom.seqMap( f, W, H, T )
  err( darkroom.isFunction(f), "fn must be a function")
  err( type(W)=="number", "W must be a number")
  err( type(H)=="number", "H must be a number")
  err( type(T)=="number", "T must be a number")
  darkroom.expectStateful(f.inputType)
  darkroom.expectStateful(f.outputType)
  local res = {kind="seqMap", W=W,H=H,T=T,inputType=types.null(),outputType=types.null()}
  local struct SeqMap { inner: f.terraModule}
  terra SeqMap:reset() self.inner:reset() end
  terra SeqMap:stats() self.inner:stats("TOP") end
  terra SeqMap:process( inp:&types.null():toTerraType(), out:&types.null():toTerraType())
    var o : darkroom.extract(f.outputType):toTerraType()
    for i=0,W*H do self.inner:process(nil,&o) end
  end
  res.terraModule = SeqMap

  res.systolicModule = S.module.new("SeqMap_"..W.."_"..H,{},{f.systolicModule:instantiate("inst")},{verilog = [[module sim();
reg CLK = 0;
integer i = 0;
reg RST = 1;
reg valid = 0;
]]..f.systolicModule.name..[[ inst(.CLK(CLK),.CE(1'b1),.process_valid(valid),.reset(RST));
   initial begin
      // clock in reset bit
      while(i<100) begin
        CLK = 0; #10; CLK = 1; #10;
        i = i + 1;
      end

      RST = 0;
      valid = 1;

      i=0;
      while(i<]]..((W*H/T)+f.systolicModule:getDelay("process"))..[[) begin
         CLK = 0; #10; CLK = 1; #10;
         i = i + 1;
      end
      $finish();
   end
endmodule
]]})

  return darkroom.newFunction(res)
end

local function readAll(file)
    local f = io.open(file, "rb")
    local content = f:read("*all")
    f:close()
    return content
end

function darkroom.seqMapHandshake( f, inputType, tapInputType, tapValue, inputW, inputH, inputT, outputW, outputH, outputT, axi, readyRate )
  err( darkroom.isFunction(f), "fn must be a function")
  err( types.isType(inputType), "inputType must be a type")
  err( tapInputType==nil or types.isType(tapInputType), "tapInputType must be a type")
  err( tapInputType==nil or type(tapValue)==tapInputType:toLuaType(), "tapValue must match tapInputType")
  err( type(inputW)=="number", "inputW must be a number")
  err( type(inputH)=="number", "inputH must be a number")
  err( type(outputW)=="number", "outputW must be a number")
  err( type(outputH)=="number", "outputH must be a number")
  err( type(inputT)=="number", "inputT must be a number")
  err( type(outputT)=="number", "outputT must be a number")
  err( type(axi)=="boolean", "axi should be a bool")

  darkroom.expectStatefulHandshake(f.inputType)
  darkroom.expectStatefulHandshake(f.outputType)

  local inputTokens = (inputW*inputH)/inputT
  local expectedOutputTokens = (outputW*outputH)/outputT
  local outputTokens = (inputTokens*f.sdfOutput[1]*f.sdfInput[2])/(f.sdfOutput[2]*f.sdfInput[1])
  err(outputTokens==expectedOutputTokens, "Error, seqMapHandshake, SDF output tokens ("..tostring(outputTokens)..") does not match stated output tokens ("..tostring(expectedOutputTokens)..")")

  local res = {kind="seqMapHandshake", inputW=inputW, inputH=inputH, outputW=outputW, outputH=outputH, inputT=inputT, outputT=outputT,inputType=types.null(),outputType=types.null()}
  local struct SeqMap { inner: f.terraModule}
  terra SeqMap:reset() self.inner:reset() end
  terra SeqMap:stats() self.inner:stats("TOP") end

  local innerinp = symbol(darkroom.extract(f.inputType):toTerraType(), "innerinp")
  local assntaps = quote end
  if tapInputType~=nil then assntaps = quote data(innerinp) = {nil,[tapInputType:valueToTerra(tapValue)]} end end

  terra SeqMap:process( inp:&types.null():toTerraType(), out:&types.null():toTerraType())
    var [innerinp]
    [assntaps]

    var o : darkroom.extract(f.outputType):toTerraType()
    var inpAddr = 0
    var outAddr = 0
    while inpAddr<inputW*inputH or outAddr<outputW*outputH do
      cstdio.printf("---------------------------------- RUNPIPE inpAddr %d outAddr %d\n", inpAddr, outAddr)
      valid(innerinp)=(inpAddr<inputW*inputH)
      self.inner:process(&innerinp,&o)
      inpAddr = inpAddr + inputT -- in simulator, ready==true always, so we can always increment.
      if valid(o) then outAddr = outAddr + outputT end
    end
  end
  res.terraModule = SeqMap

  local verilogStr

  if readyRate==nil then readyRate=1 end

  if axi then
    local baseTypeI = inputType
    local baseTypeO = darkroom.extractStatefulHandshake(f.outputType)
    err(baseTypeI:verilogBits()==64, "axi input must be 64 bits but is "..baseTypeI:verilogBits())
    err(baseTypeO:verilogBits()==64, "axi output must be 64 bits")

    local axiv = readAll("../extras/helloaxi/axi.v")
    axiv = string.gsub(axiv,"___PIPELINE_MODULE_NAME",f.systolicModule.name)
    axiv = string.gsub(axiv,"___PIPELINE_INPUT_COUNT",inputTokens)
    axiv = string.gsub(axiv,"___PIPELINE_OUTPUT_COUNT",outputTokens)

    -- Our architecture can't have units with a utilization>1, so the 'maxUtilization' here will limit the throughput of the pipeline
    local maxUtilization,LL = f.output:sdfExtremeUtilization(true)
    print("MAX UTILIZATION",maxUtilization,LL)

    local minUtilization, MLL = f.output:sdfExtremeUtilization(false)
    print("MIN UTILIZATION",minUtilization,MLL)
    
    -- this is the worst utilization of a unit, accounting for the fact that all units must have utilization < 1
    local totalMinUtilization = minUtilization/maxUtilization
    print("TOTAL MIN UTILIZATION",totalMinUtilization)

    axiv = string.gsub(axiv,"___PIPELINE_WAIT_CYCLES",math.ceil(inputTokens*maxUtilization)+1024) -- just give it 1024 cycles of slack
    if tapInputType~=nil then
      local tv = map(range(tapInputType:verilogBits()),function(i) return sel(math.random()>0.5,"1","0") end )
      local tapreg = "reg ["..(tapInputType:verilogBits()-1)..":0] taps = "..tostring(tapInputType:verilogBits()).."'b"..table.concat(tv,"")..";\n"

--      axiv = string.gsub(axiv,"___PIPELINE_TAPS",S.declareReg( tapInputType, "taps").."\nalways @(posedge FCLK0) begin if(CONFIG_READY) taps <= "..S.valueToVerilog(tapValue,tapInputType).."; end\n")
      axiv = string.gsub(axiv,"___PIPELINE_TAPS", tapreg.."\nalways @(posedge FCLK0) begin if(CONFIG_READY) taps <= "..S.valueToVerilog(tapValue,tapInputType).."; end\n")
      axiv = string.gsub(axiv,"___PIPELINE_INPUT","{taps,pipelineInput}")
    else
      axiv = string.gsub(axiv,"___PIPELINE_TAPS","")
      axiv = string.gsub(axiv,"___PIPELINE_INPUT","pipelineInput")
    end

    verilogStr = readAll("../extras/helloaxi/ict106_axilite_conv.v")..readAll("../extras/helloaxi/conf.v")..readAll("../extras/helloaxi/dramreader.v")..readAll("../extras/helloaxi/dramwriter.v")..axiv
  else
    local rrlog2 = math.log(readyRate)/math.log(2)

    local readybit = "1'b1"
    if rrlog2>0 then readybit = "ready_downstream==1" end

    local tapreg, tapRST = "",""
    if tapInputType~=nil then 
      tapreg = S.declareReg( tapInputType, "taps").."\n" 
      tapRST = "if (RST) begin taps <= "..S.valueToVerilog(tapValue,tapInputType).."; end\n"
    end

    verilogStr = [[module sim();
reg CLK = 0;
integer i = 0;
reg RST = 1;
wire valid;
reg []]..rrlog2..[[:0] ready_downstream = 1;
reg [15:0] doneCnt = 0;
wire ready;
]]..tapreg..[[
]]..S.declareWire( darkroom.extract(f.outputType), "process_output" )..[[

]]..f.systolicModule.name..[[ #(.INPUT_COUNT(]]..inputTokens..[[),.OUTPUT_COUNT(]]..outputTokens..[[)) inst (.CLK(CLK),.process_input(]]..sel(tapInputType~=nil,"{valid,taps}","valid")..[[),.reset(RST),.ready(ready),.ready_downstream(]]..readybit..[[),.process_output(process_output));
   initial begin
      // clock in reset bit
      while(i<100) begin CLK = 0; #10; CLK = 1; #10; i = i + 1; end

      RST = 0;
      //valid = 1;

      while(1) begin CLK = 0; #10; CLK = 1; #10; end
   end

  reg [31:0] validInCnt = 0; // we should only drive W*H valid bits in
  reg [31:0] validCnt = 0;

  assign valid = (RST==0 && validInCnt < ]]..((inputW*inputH)/inputT)..[[);

  always @(posedge CLK) begin
    $display("------------------------------------------------- validOutputs %d ready %d validInCnt",validCnt,]]..readybit..[[,validInCnt);
    // we can't send more than W*H valid bits, or the AXI bus will lock up. Once we have W*H valid bits,
    // keep simulating for N cycles to make sure we don't send any more
]]..tapRST..[[
    if(validCnt> ]]..((outputW*outputH)/outputT)..[[ ) begin $display("Too many valid bits!"); end
    if(validCnt>= ]]..((outputW*outputH)/outputT)..[[ && doneCnt==1024 ) begin $finish(); end
    if(validCnt>= ]]..((outputW*outputH)/outputT)..[[ ) begin doneCnt <= doneCnt+1; end
    if(RST==0 && ready) begin validInCnt <= validInCnt + 1; end
    
    // ignore the output when we're in reset mode - output is probably bogus
    if(]]..readybit..[[ && process_output[]]..(darkroom.extract(f.outputType):verilogBits()-1)..[[] && RST==1'b0) begin validCnt = validCnt + 1; end
    ready_downstream <= ready_downstream + 1;
  end
endmodule
]]
  end

  res.systolicModule = S.moduleConstructor("SeqMapHandshake_"..f.systolicModule.name.."_"..inputW.."_"..inputH.."_rr"..readyRate):verilog(verilogStr)
  res.systolicModule:add(f.systolicModule:instantiate("inst"))

  return darkroom.newFunction(res)
end

function darkroom.writeMetadata(filename, width, height, channels, bytesPerChannel,inputImage)
  assert(type(inputImage)=="string")
  io.output(filename)
  io.write("return {width="..width..",height="..height..",channels="..channels..",bytesPerChannel="..bytesPerChannel..",inputImage='"..inputImage.."'}")
  io.close()
end

return darkroom