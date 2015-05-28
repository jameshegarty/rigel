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

-----------------------
-- Semantics of the simulator:
-- we visit nodes in order from inputs to outputs. If in a step function, you assign directly from an input to an output, this means the calculation is happening _within_ a clock cycle.
-- If you call two functions that both assign directly to outputs, this means both functions are happening within the same clock cycle. To simulate pipelining, you have to
-- actually allocate a buffer and write to that etc.
--
-- Stateful functions take a pointer to the state object as their first argument. You modify this object directly: its value at the end of the function is its value at the end of the cycle (start of next cycle). You can modify it directly b/c multiple objects don't access the state (except in the case of the tmux).


-- stateful: State struct with :process(&input, &output) method, :reset() method
-- pure: same as stateful (State struct holds simulator state only, not architectural state)
-- StatefulHandshake: struct with :reset(), :ready(), :push(&input), valid=:pop(&output), that follows rules:
--                    inputValid=this:ready() and input:valid(); 
--                    if this:ready() and input:valid() then input:pop(&inputValue) end
--                    this:push( inputValue, inputValid ) end -- assert(inputValid==false or this:ready())
--                    :push does the actual computation, and dumps into the internal fifo. :pop just accesses the internal fifo
--
--                    if inputValid then this:push(inputValue) end
--                    var thisValid = this:pop(&thisValue) -- pop does the actual computation
--
--                    outputValid = :process( inputValue, inputValid, outputValue, outputValid )
-----------------------

darkroom = {}

DEFAULT_FIFO_SIZE = 2048*16

darkroom.State = types.opaque("state")
darkroom.Handshake = types.opaque("handshake")
darkroom.Registered = types.opaque("registered")
function darkroom.Stateful(A) return types.tuple({A,darkroom.State}) end
function darkroom.StatefulV(A) return types.tuple({types.tuple({A, types.bool()}), darkroom.State}) end
function darkroom.StatefulRV(A) return types.tuple({types.tuple({A, types.bool(), types.bool()}),darkroom.State}) end
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

function darkroom.isStateful( a ) return a:isTuple() and a.list[2]==darkroom.State end
function darkroom.isStatefulHandshake( a ) return a:isTuple() and a.list[2]==darkroom.State and a.list[3]==darkroom.Handshake end
function darkroom.isStatefulHandshakeRegistered( a ) return a:isTuple() and a.list[2]==darkroom.State and a.list[3]==darkroom.Handshake and a.list[4]==darkroom.Registered end
function darkroom.isStatefulV( a ) return a:isTuple() and a.list[1]:isTuple() and a.list[2]==darkroom.State and a.list[1].list[2]==types.bool() and a.list[1].list[3]==nil end
function darkroom.isStatefulRV( a ) return a:isTuple() and a.list[1]:isTuple() and a.list[2]==darkroom.State and a.list[1].list[2]==types.bool() and a.list[1].list[3]==types.bool() end
function darkroom.expectPure( A, er ) if darkroom.isStateful(A) or darkroom.isStatefulHandshake(A) then error(er or "type should be pure") end end
function darkroom.expectStateful( A, er ) if darkroom.isStateful(A)==false then error(er or "type should be stateful") end end
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

function darkroom.extractV( a, loc )
  if darkroom.isStatefulV(a)==false then error("Not a statefulV input, ") end
  return a.list[1].list[1]
end

function darkroom.extractRV( a, loc )
  if darkroom.isStatefulRV(a)==false then error("Not a statefulRV input, ") end
  return a.list[1].list[1]
end

function darkroom.extract( a, loc )
  if darkroom.isStatefulHandshake(a) or darkroom.isStatefulHandshakeRegistered(a) then
    return types.tuple({a.list[1],types.bool()})
  end
  if a:isTuple() and darkroom.isStateful(a.list[1]) then
    return types.tuple(map(a.list, function(n) assert(darkroom.isStateful(n)); return darkroom.extract(n) end))
  end
  if darkroom.isStateful(a)==false and darkroom.isStatefulHandshake(a)==false then return a end

  return a.list[1]
end

function darkroom.extractStatefulHandshake( a, loc )
  if darkroom.isStatefulHandshake(a)==false then error("Not a stateful handshake input, "..loc) end
  return a.list[1]
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

function darkroom.packTupleArrays(W,H, typelist, stateful)
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(typelist)=="table")
  assert(stateful==nil or type(stateful)=="boolean")

  local res = {kind="packTupleArrays", W=W,H=H}

  res.inputType = types.tuple( map(typelist, function(t) return sel( stateful, darkroom.Stateful(types.array2d(t,W,H)), types.array2d(t,W,H) ) end) )
  res.outputType = types.array2d(types.tuple(typelist),W,H)
  if stateful then res.outputType = darkroom.Stateful(res.outputType) end
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
  return darkroom.newFunction(res)
end

function darkroom.packTupleArraysStateful(W,H, typelist) return darkroom.packTupleArrays(W,H,typelist,true) end

function darkroom.crop(A,W,H,L,R,B,T,value)
  map({W,H,L,R,T,B,value},function(n) assert(type(n)=="number") end)
  local res = {kind="crop",L=L,R=R,T=T,B=B,value=value}
  res.inputType = types.array2d(A,W,H)
  res.outputType = res.inputType
  res.delay = 0
  local struct Crop {}
  terra Crop:reset() end
  terra Crop:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for y=0,H do for x=0,W do 
        if x<L or y<B or x>=W-R or y>=H-T then
          (@out)[y*W+x] = [value]
        else
          (@out)[y*W+x] = (@inp)[y*W+x]
        end
    end end
  end
  res.terraModule = Crop
  return darkroom.newFunction(res)
end

function darkroom.liftStateful(f)
  local res = {kind="liftStateful", fn = f}
  darkroom.expectStateful(f.inputType)
  darkroom.expectStateful(f.outputType)
  res.inputType = darkroom.Stateful(darkroom.extract(f.inputType))
  res.outputType = darkroom.StatefulV(darkroom.extract(f.outputType))
  res.delay = f.delay
  local struct LiftStateful { inner : f.terraModule}
  terra LiftStateful:reset() self.inner:reset() end
  terra LiftStateful:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    self.inner:process(inp,&data(out))
    valid(out) = true
  end
  res.terraModule = LiftStateful
  return darkroom.newFunction(res)
end

function darkroom.liftDecimate(f)
  assert(darkroom.isFunction(f))
  local res = {kind="liftDecimate", fn = f}
  darkroom.expectStateful(f.inputType)
  darkroom.expectStatefulV(f.outputType)
  res.inputType = darkroom.StatefulV(darkroom.extract(f.inputType))
  res.outputType = darkroom.StatefulRV(darkroom.extractV(f.outputType))
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
  return darkroom.newFunction(res)
end

function darkroom.RPassthrough(f)
  local res = {kind="RPassthrough", fn = f}
  darkroom.expectStatefulV(f.inputType)
  darkroom.expectStatefulRV(f.outputType)
  res.inputType = darkroom.StatefulRV(darkroom.extractV(f.inputType))
  res.outputType = darkroom.StatefulRV(darkroom.extractRV(f.outputType))
  res.delay = f.delay
  local struct RPassthrough { inner : f.terraModule}
  terra RPassthrough:reset() self.inner:reset() end
  terra RPassthrough:stats( name : &int8 ) self.inner:stats(name) end
  terra RPassthrough:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    self.inner:process([&darkroom.extract(f.inputType):toTerraType()](inp),out)
  end
  terra RPassthrough:ready( inp:bool ) return inp and self.inner:ready() end
  res.terraModule = RPassthrough
  return darkroom.newFunction(res)
end

function darkroom.RVPassthrough(f)
  return darkroom.RPassthrough(darkroom.liftDecimate(darkroom.liftStateful(f)))
end

function darkroom.liftHandshake(f)
  local res = {kind="liftHandshake", fn=f}
  darkroom.expectStatefulV(f.inputType)
  darkroom.expectStatefulRV(f.outputType)
  res.inputType = darkroom.StatefulHandshake(darkroom.extractV(f.inputType))
  res.outputType = darkroom.StatefulHandshake(darkroom.extractRV(f.outputType))
  print("LIFT HANDSHAKE",f.outputType,res.outputType)
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
    cstdio.printf("CALLINNER %d\n",valid(tinp))
    self.inner:process(&tinp,&tout)
    self.delaysr:pushBack(&tout)
  end
  res.terraModule = LiftHandshake

  return darkroom.newFunction(res)

end

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
  res.delay = f.delay
  local struct MapModule {fn:f.terraModule}
  terra MapModule:reset() self.fn:reset() end
  terra MapModule:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    cstdio.printf("MAP\n")
    for i=0,W*H do self.fn:process( &((@inp)[i]), &((@out)[i])  ) end
  end
  res.terraModule = MapModule
  res.systolicModule = S.moduleConstructor("map_"..f.systolicModule.name,{CE=true})
  local inp = S.parameter("process_input", res.inputType )
  local out = {}
  local resetPipelines={}
  for i=0,W*H-1 do 
    local inst = res.systolicModule:add(f.systolicModule:instantiate("inner"..i))
    table.insert( out, inst:process( S.index( inp, i ) ) )
    table.insert( resetPipelines, inst:reset() )
  end
  res.systolicModule:addFunction( S.lambda("process", inp, S.cast( S.tuple( out ), res.outputType ), "process_output" ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, S.parameter("reset",types.bool()) ) )

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

function darkroom.downsampleSeq( A, W, H, T, scaleX, scaleY )
  map({W,H,T,scaleX,scaleY},function(n) assert(type(n)=="number") end)
  assert(scaleX<=1)
  assert(scaleY<=1)
  local f = darkroom.liftXYSeq( types.null(), types.bool(), W,H,T,
                                terra(x:int,y:int,a:&(types.null():toTerraType()), b:&bool)
                                  @b = (x%[1/scaleX])==0 and (y%[1/scaleY])==0
                                end, 0)
  return darkroom.compose("downsampleSeq",darkroom.densify(A,T),darkroom.filterStateful( A,T,f))
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

function darkroom.compose(name,f,g)
  assert(type(name)=="string")
  assert(darkroom.isFunction(f))
  assert(darkroom.isFunction(g))
  local inp = darkroom.input( g.inputType )
  return darkroom.lambda(name,inp,darkroom.apply(name.."_f",f,darkroom.apply(name.."_g",g,inp)))
end

function darkroom.posSeq( W, H, T )
  assert(W>0); assert(H>0); assert(T>=1);
  local res = {kind="posSeq", T=T, W=W, H=H }
  res.inputType = darkroom.State
  res.outputType = darkroom.Stateful(types.array2d(types.tuple({types.int(32),types.int(32)}),T))
  res.delay = 0
  local struct PosSeq { x:int, y:int }
  terra PosSeq:reset() self.x=0; self.y=0 end
  terra PosSeq:process( inp : &res.inputType:toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    for i=0,T do 
      (@out)[i] = {self.x,self.y}
      self.x = self.x + 1
      if self.x==W then self.x=0; self.y=self.y+1 end
    end
  end
  res.terraModule = PosSeq
  return darkroom.newFunction(res)
end

function darkroom.liftXYSeq( inpType, outType, W, H, T, tfn, delay )
  map({W,H,delay},function(n) assert(type(n)=="number") end)

  local inp = darkroom.input( darkroom.Stateful( types.array2d(inpType,T) ) )

  local twrap = darkroom.lift( types.tuple( {inpType, types.tuple({types.int(32),types.int(32)})} ), outType,
                                terra( a :&tuple(inpType:toTerraType(),tuple(int,int)), out : &outType:toTerraType() )
                                  var x,y = a._1._0, a._1._1
                                  tfn(x,y, &a._0, out)
                                end,delay )

  local p = darkroom.apply("p", darkroom.posSeq(W,H,T), darkroom.extractState("e",inp) )
  local packed = darkroom.apply( "packedtup", darkroom.packTupleArraysStateful(T,1,{inpType,types.tuple({types.int(32),types.int(32)})}), darkroom.tuple("ptup", {inp,p}) )
  local out = darkroom.apply("m", darkroom.makeStateful(darkroom.map( twrap, T )), packed )
  return darkroom.lambda( "cropSeq", inp, out )
end

function darkroom.cropSeq( A, W, H, T, L, R, B, Top, Value )
  map({W,H,L,R,B,Top,Value},function(n) assert(type(n)=="number") end)

  return darkroom.liftXYSeq( A, A, W, H, T,
                                terra( x:int, y:int, a :&A:toTerraType(), out : &A:toTerraType() )
                                  if x<L or y<B or x>=W-R or y>=H-Top then @out = [Value]
                                  else @out = @a end
                                end, 1 )

end

function darkroom.linebuffer( A, w, h, T, ymin )
  assert(w>0); assert(h>0);
  assert(ymin<=0)
  local res = {kind="linebuffer", type=A, T=T, w=w, h=h, ymin=ymin }
  darkroom.expectPure(A)
  res.inputType = darkroom.Stateful(types.array2d(A,T))
  res.outputType = darkroom.Stateful(types.array2d(A,T,-ymin+1))
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
  return darkroom.newFunction(res)
end

function darkroom.SSRPartial( A, T, xmin, ymin )
  assert(T<=1); 
  assert((-xmin+1)*T==math.floor((-xmin+1)*T))
  local res = {kind="SSRPartial", type=A, T=T, xmin=xmin, ymin=ymin }
  res.inputType = darkroom.StatefulV(types.array2d(A,1,-ymin+1))
  res.outputType = darkroom.StatefulRV(types.array2d(A,(-xmin+1)*T,-ymin+1))
  res.delay=0
  local struct SSRPartial {phase:int; wroteLastColumn:bool; SR:(A:toTerraType())[-xmin+1][-ymin+1]; activeCycles:int; idleCycles:int}
  terra SSRPartial:reset() self.phase=[1/T]-1; self.wroteLastColumn=true;self.activeCycles=0;self.idleCycles=0; end
  terra SSRPartial:stats(name:&int8) cstdio.printf("SSRPartial %s T=%f utilization:%f\n",name,[float](T),[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end
  terra SSRPartial:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    if self.wroteLastColumn==false then
      var W = [(-xmin+1)*T]
      for y=0,-ymin+1 do for x=0,W do data(out)[y*W+x] = self.SR[y][x+self.phase*W] end end
      valid(out)=true
      if self.phase==[1/T]-1 then self.wroteLastColumn=true end
    else
      valid(out)=false
    end

    --cstdio.printf("SSRPARTIAL phase %d inpValid %d red %d\n",self.phase, valid(inp),self:ready())
    if valid(inp) then
      darkroomAssert( self.phase==[1/T]-1, "SSRPartial set when not in right phase" )
      darkroomAssert( self.wroteLastColumn, "SSRPartial set when not in right phase" )
      self.activeCycles = self.activeCycles + 1
      self.wroteLastColumn=false
      -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
      var SStride = 1
      for y=0,-ymin+1 do for x=0,-xmin do self.SR[y][x] = self.SR[y][x+SStride] end end
      for y=0,-ymin+1 do for x=-xmin,-xmin+SStride do self.SR[y][x] = data(inp)[y*SStride+(x+xmin)] end end
      self.phase = 0
    else
      if self.phase<[1/T]-1 then 
        self.phase = self.phase + 1 
        self.activeCycles = self.activeCycles + 1
      else
        self.idleCycles = self.idleCycles + 1
      end
    end
  end
  terra SSRPartial:ready()  return self.phase==[1/T]-1 end
  res.terraModule = SSRPartial
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

function darkroom.stencilLinebufferPartial( A, w, h, T, xmin, xmax, ymin, ymax )
  map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T<=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  return darkroom.compose("stencilLinebufferPartial", darkroom.RPassthrough(darkroom.SSRPartial( A, T, xmin, ymin)), darkroom.liftDecimate(darkroom.liftStateful(darkroom.linebuffer( A, w, h, 1, ymin ))) )
end

-- purely wiring
function darkroom.unpackStencil( A, stencilW, stencilH, T )
  assert(types.isType(A))
  assert(type(stencilW)=="number")
  assert(stencilW>0)
  assert(type(stencilH)=="number")
  assert(stencilH>0)
  assert(type(T)=="number")
  assert(T>0)

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

  return darkroom.newFunction(res)
end

function darkroom.makeStateful( f )
  assert( darkroom.isFunction(f) )
  local res = { kind="makeStateful", fn = f }
  darkroom.expectPure(f.inputType)
  darkroom.expectPure(f.outputType)
  res.inputType = darkroom.Stateful(f.inputType)
  res.outputType = darkroom.Stateful(f.outputType)
  assert(types.isType(res.inputType))
  res.delay = f.delay
  res.terraModule = f.terraModule
  res.systolicModule = f.systolicModule
  return darkroom.newFunction(res)
end

-- we could construct this out of liftHandshake, but this is a special case for when we don't need a fifo b/c this is always ready
function darkroom.makeHandshake( f )
  assert( darkroom.isFunction(f) )
  local res = { kind="makeHandshake", fn = f }
  darkroom.expectStateful(f.inputType)
  darkroom.expectStateful(f.outputType)
  res.inputType = darkroom.StatefulHandshake(darkroom.extractStateful(f.inputType))
  res.outputType = darkroom.StatefulHandshake(darkroom.extractStateful(f.outputType))

  local delay = math.max( 1, f.delay )
  --assert(delay>0)
  -- we don't need an input fifo here b/c ready is always true
  local struct MakeHandshake{ delaysr: simmodules.fifo( darkroom.extract(res.outputType):toTerraType(), delay, "makeHandshake"),
--                              fifo: simmodules.fifo( darkroom.extract(f.outputType):toTerraType(), DEFAULT_FIFO_SIZE),
                              inner: f.terraModule}
  terra MakeHandshake:reset() self.delaysr:reset(); self.inner:reset() end
  terra MakeHandshake:stats( name : &int8 )  end
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
    if valid(inp) then self.inner:process(&data(inp),&data(tout)) end -- don't bother if invalid
    self.delaysr:pushBack(&tout)
  end
  res.terraModule = MakeHandshake

  res.systolicModule = S.moduleConstructor( "MakeHandshake_"..f.systolicModule.name, {onlyWire=true} )
  local SR = res.systolicModule:add( fpgamodules.shiftRegister( types.bool(), f.systolicModule:getDelay("process"), "MakeHandshakeSR_"..f.systolicModule:getDelay("process"), {CE=true} ):instantiate("validBitDelay") )
  local inner = res.systolicModule:add(f.systolicModule:instantiate("inner"))
  local pvalid = S.parameter("valid", types.bool())
  local pinp = S.parameter("process_input", darkroom.extract(f.inputType) )
  res.systolicModule:addFunction( S.lambda("process", pinp, S.tuple({inner:process(pinp), SR:pushPop(pvalid, S.constant(true,types.bool()))}), "process_output",{},pvalid) ) 
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "reset_out", {}, S.parameter("reset",types.bool()) ) )
  local pready = S.parameter("ready_downstream", types.bool())
  res.systolicModule:addFunction( S.lambda("ready", pready, pready, "ready_out", {inner:CE(pready),SR:CE(pready)} ) )

  return darkroom.newFunction(res)
end

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

  return darkroom.newFunction( res )
end


function darkroom.reduceSeq( f, T )
  assert(T<=1)

  local res = {kind="reduceSeq", fn=f}
  darkroom.expectPure(f.outputType)
  res.inputType = darkroom.Stateful(f.outputType)
  res.outputType = darkroom.StatefulV(f.outputType)
  assert(f.delay==0)
  res.delay = 0
  local struct ReduceSeq { phase:int; result : f.outputType:toTerraType(); inner : f.terraModule}
  terra ReduceSeq:reset() self.phase=0; self.inner:reset() end
  terra ReduceSeq:process( inp : &f.outputType:toTerraType(), out : &darkroom.extract(res.outputType):toTerraType())
    if self.phase==0 and T==1 then -- passthrough
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

  return darkroom.newFunction( res )
end


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
function darkroom.lambda( name, input, output )
  assert( type(name) == "string" )
  assert( darkroom.isIR( input ) )
  assert( input.kind=="input" )
  assert( darkroom.isIR( output ) )

  print("LAMBDA",name)

--  if darkroom.isStatefulHandshake(input.type) then
--    return darkroom.lambdaHandshake( name, input, output )
--  end

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

        if true then table.insert( stats, quote cstdio.printf([n.name.."\n"]) end ) end

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
      terra Module.methods.ready( [mself], [readyInput] ) [readyStats]; return [out[2]] end
    else
      terra Module.methods.ready( [mself] ) [readyStats]; return [out[2]] end
    end
    --Module:printpretty()
    --Module.methods.process:printpretty(false)
    --print("PP")
    --Module.methods.process:printpretty()
    --print("PPDONE")
    return Module
  end

  res.terraModule = docompile(res)

  local function makeSystolic( fn )
    local module = S.moduleConstructor( fn.name, {CE=sel(darkroom.isStatefulHandshake(fn.inputType),false,true), onlyWire=sel(darkroom.isStatefulHandshake(fn.inputType),true,false)} )
    local inp = S.parameter( "process_input", darkroom.extract(fn.inputType) )
    local resetPipelines = {}

    local instanceMap = {}
    local out = fn.output:visitEach(
      function(n, inputs)
        if n.kind=="input" then
          return {inp}
        elseif n.kind=="apply" then
          print("systolic APPLY",n.fn.kind)
          local I = n.fn.systolicModule:instantiate(n.name)
          instanceMap[n] = I
          module:add(I)
          table.insert( resetPipelines, I:reset() )
          if darkroom.isStatefulHandshake(n.fn.inputType) then
            return {I:process( S.index(inputs[1][1],0), S.index(inputs[1][1],1) )}
          else
            return {I:process(inputs[1][1])}
          end
        else
          print(n.kind)
          assert(false)
        end
      end)


    local processfn = S.lambda( "process", inp, out[1], "process_output" )
    local process = module:addFunction( processfn )
    module:addFunction( S.lambda("reset", S.parameter("nip",types.null()), nil, "reset_out", resetPipelines, S.parameter("reset", types.bool() ) ) )

    if darkroom.isStatefulHandshake( fn.inputType ) then
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
          else
            print(n.kind)
            assert(false)
          end
        end)

      local readyfn = module:addFunction( S.lambda("ready", readyinp, readyout, "ready_out", {} ) )
      assert( readyfn:isPure() )
    end

    return module
  end
  res.systolicModule = makeSystolic(res)
  res.systolicModule:toVerilog()

  return darkroom.newFunction( res )
end

function darkroom.lift( name, inputType, outputType, delay, terraFunction, systolicInput, systolicOutput )
  assert( type(name)=="string" )
  assert( types.isType(inputType ) )
  assert( types.isType(outputType ) )
  assert( type(delay)=="number" )
  local struct LiftModule {}
  terra LiftModule:reset() end
  terra LiftModule:stats( name : &int8 )  end
  terra LiftModule:process(inp:&darkroom.extract(inputType):toTerraType(),out:&darkroom.extract(outputType):toTerraType()) terraFunction(inp,out) end

  local systolicModule = S.moduleConstructor(name,{CE=true})
  systolicModule:addFunction( S.lambda("process", systolicInput, systolicOutput, "process_output") )
  local nip = S.parameter("nip",types.null())
  systolicModule:addFunction( S.lambda("reset", nip, nil,"reset_output") )

  local res = { kind="lift", inputType = inputType, outputType = outputType, delay=delay, terraModule=LiftModule, systolicModule=systolicModule }
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

function darkroom.index( inputType, idx )
  assert( types.isType(inputType) )
  assert(type(idx)=="number")

  if inputType:isTuple() then
    assert( idx < #inputType.list )
    local OT = inputType.list[idx+1]
    return darkroom.lift( inputType, OT, terra(inp:&darkroom.extract(inputType):toTerraType(), out:&darkroom.extract(OT):toTerraType()) @out = inp.["_"..idx] end, 0 )
  elseif inputType:isArray() then
    assert(idx<inputType:channels())
    local OT = inputType:arrayOver()
    return darkroom.lift( inputType, OT, terra(inp:&darkroom.extract(inputType):toTerraType(), out:&darkroom.extract(OT):toTerraType()) @out = (@inp)[idx] end, 0 )
  else
    assert(false)
  end
end

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

function darkroom.freadSeq( filename, ty, filenameVerilog)
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  darkroom.expectPure(ty)
  if filenameVerilog==nil then filenameVerilog=filename end
  local res = {kind="freadSeq", filename=filename, filenameVerilog=filenameVerilog, type=darkroom.Stateful(ty), inputType=darkroom.Stateful(types.null()), outputType=darkroom.Stateful(ty), delay=0}
  local struct FreadSeq { file : &cstdio.FILE }
  terra FreadSeq:reset() 
    self.file = cstdio.fopen(filename, "rb") 
    darkroomAssert(self.file~=nil, ["file "..filename.." doesnt exist"])
  end
  terra FreadSeq:process(inp : &types.null():toTerraType(), out : &ty:toTerraType())
    cstdio.fread(out,[ty:sizeof()],1,self.file)
  end
  res.terraModule = FreadSeq
  res.systolicModule = S.moduleConstructor("freadSeq",{CE=true})
  local sfile = res.systolicModule:add( S.module.file( filenameVerilog, ty ):instantiate("freadfile") )
  local inp = S.parameter("process_input", types.null() )
  local nilinp = S.parameter("process_nilinp", types.null() )
  res.systolicModule:addFunction( S.lambda("process", inp, sfile:read(), "process_output" ) )
  res.systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", {sfile:reset()}, S.parameter("reset", types.bool() ) ) )

  return darkroom.newFunction(res)
end

function darkroom.fwriteSeq( filename, ty, filenameVerilog)
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  darkroom.expectPure(ty)
  if filenameVerilog==nil then filenameVerilog=filename end
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
  res.systolicModule = S.moduleConstructor("fwriteSeq",{CE=true})
  local sfile = res.systolicModule:add( S.module.file( filenameVerilog, ty ):instantiate("fwritefile") )
  local inp = S.parameter("process_input", ty )
  local nilinp = S.parameter("process_nilinp", types.null() )
  res.systolicModule:addFunction( S.lambda("process", inp, inp, "process_output", {sfile:write(inp)} ) )
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

function darkroom.seqMapHandshake( f, W, H, T )
  err( darkroom.isFunction(f), "fn must be a function")
  err( type(W)=="number", "W must be a number")
  err( type(H)=="number", "H must be a number")
  err( type(T)=="number", "T must be a number")
  darkroom.expectStatefulHandshake(f.inputType)
  darkroom.expectStatefulHandshake(f.outputType)
  local res = {kind="seqMapHandshake", W=W,H=H,T=T,inputType=types.null(),outputType=types.null()}
  local struct SeqMap { inner: f.terraModule}
  terra SeqMap:reset() self.inner:reset() end
  terra SeqMap:process( inp:&types.null():toTerraType(), out:&types.null():toTerraType())
    var inp : darkroom.extract(f.inputType):toTerraType()
    valid(inp)=true
    var o : darkroom.extract(f.outputType):toTerraType()
    var inpAddr = 0
    var outAddr = 0
    while inpAddr<W*H or outAddr<W*H do
      self.inner:process(&inp,&o)
      inpAddr = inpAddr + T
      if valid(o) then outAddr = outAddr + T end
    end
  end
  res.terraModule = SeqMap

  res.systolicModule = S.module.new("SeqMapHandshake_"..W.."_"..H,{},{f.systolicModule:instantiate("inst")},{verilog = [[module sim();
reg CLK = 0;
integer i = 0;
reg RST = 1;
reg valid = 0;
]]..f.systolicModule.name..[[ inst(.CLK(CLK),.process_valid(valid),.reset(RST));
   initial begin
      // clock in reset bit
      while(i<100) begin
        CLK = 0; #10; CLK = 1; #10;
        i = i + 1;
      end

      RST = 0;
      valid = 1;

      i=0;
      while(i<]]..(W*H/T)..[[) begin
         CLK = 0; #10; CLK = 1; #10;
         i = i + 1;
      end
      $finish();
   end
endmodule
]]})

  return darkroom.newFunction(res)
end

local Im = require "image"

function darkroom.scanlHarness( Module, 
                                inputT, inputFilename, inputType, inputWidth, inputHeight, 
                                outputT, outputFilename, outputType, outputWidth, outputHeight,
                                L,R,B,Top)
  assert(terralib.types.istype(Module))
  assert(type(inputT)=="number")
  assert(darkroom.isStatefulHandshake(inputType)==false)
  assert(type(inputFilename)=="string")
  assert(type(outputFilename)=="string")
  assert(type(Top)=="number")

  return terra()
    cstdio.printf("DOIT\n")
    var imIn : Im
    imIn:load( inputFilename )
    imIn:expand( L,R,B,Top)
    darkroomAssert(imIn.width==inputWidth,"input image width isn't correct")
    darkroomAssert(imIn.height==inputHeight,"input image height isn't correct")

    var imOut : Im
    imOut:allocateDarkroomFormat(outputWidth, outputHeight, 1, 1, 8, false, false, false)

--    var inp : inputType:toTerraType()
--    var out : outputType:toTerraType()

    var module : Module
    module:reset()

    for i=0,inputWidth*inputHeight,inputT do
      cstdio.printf("ITER %d\n",i)
      module:process( [&uint8[inputT]]([&uint8](imIn.data)+i), [&uint8[outputT]]([&uint8](imOut.data)+i) )
--      module:process( [&uint8[T]](imIn.data), [&uint8[T]](imOut.data) )
    end

--    imOut:save( outputFilename )
    imOut:crop(L,R,B,Top):save( outputFilename )
  end
end


function darkroom.scanlHarnessHandshake( Module, 
                                inputT, inputFilename, inputType, inputWidth, inputHeight, 
                                outputT, outputFilename, outputType, outputWidth, outputHeight,
                                L,R,B,Top)
  assert(terralib.types.istype(Module))
  assert(type(inputT)=="number")
  assert(types.isType(outputType))
  assert(darkroom.isStatefulHandshake(inputType))
  assert(type(Top)=="number")

  local throttle = 1
  if inputT<1 then throttle=1/inputT;inputT=1 end

  print("OUTPUTTYPE",outputType)
  assert(darkroom.extractStatefulHandshake(outputType):isArray())
  local outputTileW = (darkroom.extractStatefulHandshake(outputType):arrayLength())[1]
  local outputTileH = (darkroom.extractStatefulHandshake(outputType):arrayLength())[2]

  return terra()
    cstdio.printf("DOIT\n")
    var imIn : Im
    imIn:load( inputFilename )
    imIn:expand( L, R, B, Top)
    var imOut : Im
    imOut:allocateDarkroomFormat(outputWidth, outputHeight, 1, 1, 8, false, false, false)

    var module : Module
    module:reset()

    var delayCycles : int = 0
    var validCycles = 0
    var invalidCycles = 0
    var started = false
    var inpAddr = 0
    var outAddrX = 0
    var outAddrY = 0
    var output : darkroom.extract(outputType):toTerraType()

    var packedInp : darkroom.extract(inputType):toTerraType()
--    var inputValid = true
--    var outputValid = true

    var TH : int = 0
    while inpAddr<inputWidth*inputHeight or outAddrY<outputHeight do
      cstdio.printf("ITER %d outX %d outY %d\n",inpAddr,outAddrX, outAddrY)
      
      if TH==0 then
        data(packedInp) = @[&uint8[inputT]]([&uint8](imIn.data)+inpAddr)
        valid(packedInp) = true
        module:process( &packedInp, &output)
        inpAddr = inpAddr + inputT
      else
        valid(packedInp) = false
        module:process( &packedInp, &output )
      end
      TH = TH + 1
      if TH>=throttle then TH=0 end

      if valid(output) then
--        @[&uint8[T]]([&uint8](imOut.data)+outAddr) = output
        for y=0,outputTileH do
          for x=0,outputTileW do
            @([&uint8](imOut.data)+outAddrX+x+(outAddrY+y)*outputWidth) = data(output)[y*outputTileW+x]
          end
        end

        outAddrX = outAddrX+outputTileW; 
        if outAddrX>=outputWidth then
          outAddrY = outAddrY + outputTileH
          outAddrX = 0
        end

        started = true
        validCycles = validCycles + 1
      elseif started then
        invalidCycles = invalidCycles + 1
      elseif started==false then
        delayCycles = delayCycles + 1
      end
    end

    imOut:crop(L,R,B,Top):save( outputFilename )

    cstdio.printf("Delay Cycles %d\n", delayCycles)
    cstdio.printf("valid percent: %f\n",[float](validCycles*100)/[float](invalidCycles+validCycles))

    module:stats("root")
  end
end

function darkroom.writeMetadata(filename, width, height, channels, bytesPerChannel)
  io.output(filename)
  io.write("return {width="..width..",height="..height..",channels="..channels..",bytesPerChannel="..bytesPerChannel.."}")
  io.close()
end

return darkroom