local IR = require("IR")
local types = require("types")
local simmodules = require("simmodules")
local cstring = terralib.includec("string.h")
local cstdlib = terralib.includec("stdlib.h")
local cstdio = terralib.includec("stdio.h")
local ffi = require("ffi")

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

DEFAULT_FIFO_SIZE = 2048

darkroom.State = types.opaque("state")
darkroom.Handshake = types.opaque("handshake")
function darkroom.Stateful(A) return types.tuple({A,darkroom.State}) end
function darkroom.StatefulV(A) return types.tuple({types.tuple({A, types.bool()}), darkroom.State}) end
function darkroom.StatefulRV(A) return types.tuple({types.tuple({A, types.bool(), types.bool()}),darkroom.State}) end
function darkroom.StatefulHandshake(A) return types.tuple({ A, darkroom.State, darkroom.Handshake }) end

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
function darkroom.isStatefulV( a ) return a:isTuple() and a.list[1]:isTuple() and a.list[2]==darkroom.State and a.list[1].list[2]==types.bool() and a.list[1].list[3]==nil end
function darkroom.isStatefulRV( a ) return a:isTuple() and a.list[1]:isTuple() and a.list[2]==darkroom.State and a.list[1].list[2]==types.bool() and a.list[1].list[3]==types.bool() end
function darkroom.expectPure( A, er ) if darkroom.isStateful(A) or darkroom.isStatefulHandshake(A) then error(er or "type should be pure") end end
function darkroom.expectStateful( A, er ) if darkroom.isStateful(A)==false then error(er or "type should be stateful") end end
function darkroom.expectStatefulV( A, er ) if darkroom.isStatefulV(A)==false then error(er or "type should be statefulV") end end
function darkroom.expectStatefulRV( A, er ) if darkroom.isStatefulRV(A)==false then error(er or "type should be statefulRV") end end

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
  if darkroom.isStateful(a)==false and darkroom.isStatefulHandshake(a)==false then return a end
  return a.list[1]
end

function darkroom.extractStatefulHandshake( a, loc )
  if darkroom.isStatefulHandshake(a)==false then error("Not a stateful handshake input, "..loc) end
  return a.list[1]
end

darkroomFunctionFunctions = {}
darkroomFunctionMT={__index=darkroomFunctionFunctions}

function darkroomFunctionFunctions:compile() return self.terraModule end

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
      elseif n.kind=="input" then
      elseif n.kind=="constant" then
      elseif n.kind=="index" then
        if n.inputs[1].type:isTuple()==false then error("input to index must be a tuple but is "..tostring(n.inputs[1].type)..", "..n.loc) end
        if n.idx>=#n.inputs[1].type.list then error("index to tuple goes over end of tuple, "..n.loc) end
        n.type = n.inputs[1].type.list[n.idx+1]
        return darkroom.newIR(n)
      elseif n.kind=="extractState" then
        if darkroom.isStateful(n.inputs[1].type)==false then error("input to extractState must be stateful") end
      elseif n.kind=="tuple" then
        local tt = {}
        local sz
        local isStateful
        for _,v in pairs(n.inputs) do
          print("TUPLEINPT",v.type)
          local o = v.type
          if darkroom.isStateful(v.type) then
            isStateful = true
            o = darkroom.extractStateful( v.type, n.loc)
          else
            if isStateful==true then error("Either all or none of the inputs to tuple must be stateful, "..n.loc) end
          end
          if o:isArray()==false then error("input to tuple must be an array, "..n.loc) end
          if sz==nil then sz=o:arrayLength() 
          elseif sz~=o:arrayLength() then error("inputs to tuple must have same size,"..n.loc) end
          table.insert( tt, o:arrayOver() )
        end

        n.type = types.array2d( types.tuple(tt), sz[1], sz[2] )
        if isStateful==true then n.type = darkroom.Stateful(n.type) end
        print("TUPLEOUT",n.type)
        return darkroom.newIR(n)
      else
        print(n.kind)
        assert(false)
      end
    end)
end

function darkroom.isFunction(t) return getmetatable(t)==darkroomFunctionMT end
function darkroom.isIR(t) return getmetatable(t)==darkroomIRMT end

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
  local struct LiftDecimate { inner : f.terraModule}
  terra LiftDecimate:reset() self.inner:reset() end
  terra LiftDecimate:process( inp : &darkroom.extract(res.inputType):toTerraType(), out : &darkroom.extract(res.outputType):toTerraType() )
    if valid(inp) then
--      var inpp : darkroom.extract(f.inputType):toTerraType() = data(inp)
      self.inner:process(&data(inp),[&darkroom.extract(f.outputType):toTerraType()](out))
    else
      valid(out) = false
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
                              fifo: simmodules.fifo( darkroom.extract(res.inputType):toTerraType(), DEFAULT_FIFO_SIZE, "liftHandshakefifo"),
                              inner: f.terraModule}
  terra LiftHandshake:reset() self.delaysr:reset(); self.fifo:reset(); self.inner:reset() end
  terra LiftHandshake:process( inp : &darkroom.extract(res.inputType):toTerraType(), inpValid : bool, 
                               out : &darkroom.extract(res.outputType):toTerraType(), outValid : &bool)
    if inpValid then
      self.fifo:pushBack(inp)
    end

    if self.delaysr:size()==delay then
      var ot = self.delaysr:popFront()
      @outValid = valid(ot)
      @out = data(ot)
    else
      @outValid=false
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
function darkroom.map( f, w, h )
  assert( darkroom.isFunction(f) )
  assert(type(w)=="number")
  assert(type(h)=="number" or h==nil)
  if h==nil then h=1 end

  local res = { kind="map", fn = f, w=w, h=h }
  darkroom.expectPure( f.inputType, "mapped function must be a pure function")
  darkroom.expectPure( f.outputType, "mapped function must be a pure function")
  res.inputType = types.array2d( f.inputType, w, h )
  res.outputType = types.array2d( f.outputType, w, h )
  res.delay = f.delay
  local struct MapModule {fn:f.terraModule}
  terra MapModule:reset() self.fn:reset() end
  terra MapModule:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    cstdio.printf("MAP\n")
    for i=0,w*h do self.fn:process( &((@inp)[i]), &((@out)[i])  ) end
  end
  res.terraModule = MapModule

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
  assert(T<1); 
  assert((-xmin+1)*T==math.floor((-xmin+1)*T))
  local res = {kind="SSRPartial", type=A, T=T, xmin=xmin, ymin=ymin }
  res.inputType = darkroom.StatefulV(types.array2d(A,1,-ymin+1))
  res.outputType = darkroom.StatefulRV(types.array2d(A,(-xmin+1)*T,-ymin+1))
  res.delay=0
  local struct SSRPartial {phase:int; wroteLastColumn:bool; SR:(A:toTerraType())[-xmin+1][-ymin+1]}
  terra SSRPartial:reset() self.phase=[1/T]-1; self.wroteLastColumn=true end
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
      self.wroteLastColumn=false
      -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
      var SStride = 1
      for y=0,-ymin+1 do for x=0,-xmin do self.SR[y][x] = self.SR[y][x+SStride] end end
      for y=0,-ymin+1 do for x=-xmin,-xmin+SStride do self.SR[y][x] = data(inp)[y*SStride+(x+xmin)] end end
      self.phase = 0
    else
      if self.phase<[1/T]-1 then self.phase = self.phase + 1 end
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
  assert(T<1); assert(w>0); assert(h>0);
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
  return darkroom.newFunction(res)
end

function darkroom.makeHandshake( f )
  assert( darkroom.isFunction(f) )
  local res = { kind="makeHandshake", fn = f }
  darkroom.expectStateful(f.inputType)
  darkroom.expectStateful(f.outputType)
  res.inputType = darkroom.StatefulHandshake(darkroom.extractStateful(f.inputType))
  res.outputType = darkroom.StatefulHandshake(darkroom.extractStateful(f.outputType))

  local delay = f.delay
  assert(delay>0)
  -- we don't need an input fifo here b/c ready is always true
  local struct MakeHandshake{ delaysr: simmodules.fifo( tuple(darkroom.extract(res.outputType):toTerraType(),bool), delay, "makeHandshake"),
--                              fifo: simmodules.fifo( darkroom.extract(f.outputType):toTerraType(), DEFAULT_FIFO_SIZE),
                              inner: f.terraModule}
  terra MakeHandshake:reset() self.delaysr:reset(); self.inner:reset() end
  terra MakeHandshake:process( inp : &darkroom.extract(f.inputType):toTerraType(), inpValid : bool, 
                               out : &darkroom.extract(f.outputType):toTerraType(), outValid : &bool)
    
    if self.delaysr:size()==delay then
      var ot = self.delaysr:popFront()
      @outValid = valid(ot)
      @out = data(ot)
    else
      @outValid=false
    end

    var tout : tuple(darkroom.extract(res.outputType):toTerraType(),bool)
    valid(tout) = inpValid
    if inpValid then self.inner:process(inp,&data(tout)) end -- don't bother if invalid
    self.delaysr:pushBack(&tout)
  end
  res.terraModule = MakeHandshake

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
  assert(T<1)

  local res = {kind="reduceSeq", fn=f}
  darkroom.expectPure(f.outputType)
  res.inputType = darkroom.Stateful(f.outputType)
  res.outputType = darkroom.StatefulV(f.outputType)
  assert(f.delay==0)
  res.delay = 0
  local struct ReduceSeq { phase:int; result : f.outputType:toTerraType(); inner : f.terraModule}
  terra ReduceSeq:reset() self.phase=0; self.inner:reset() end
  terra ReduceSeq:process( inp : &f.outputType:toTerraType(), out : &darkroom.extract(res.outputType):toTerraType())
    if self.phase==0 then 
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
  return darkroom.newIR( {kind="input", type = type, name="input", inputs={}} )
end

function callOnEntries( T, fnname )
  local TS = symbol(&T,"self")
  local ssStats = {}
  for k,v in pairs( T.entries ) do if v.type:isstruct() then table.insert( ssStats, quote TS.[v.field]:[fnname]() end) end end
  T.methods[fnname] = terra([TS]) [ssStats] end
end

function darkroom.lambdaHandshake( name, input, output )
  local output = output:typecheck()
  local res = {kind = "lambda", name=name, input = input, output = output }
  res.inputType = input.type
  res.outputType = output.type

  local Module = terralib.types.newstruct("lambda"..name.."_module")
--  Module.entries = terralib.newlist( {{field="__input",type=simmodules.HandshakeStub(darkroom.extract(input.type):toTerraType())}} )
  Module.entries = terralib.newlist({})

  local function docompile( fn )
    local inputSymbol = symbol( &darkroom.extract(fn.input.type):toTerraType(), "lambdainput" )
    local inputValidSymbol = symbol(bool, "lambdainputvalid")
    local outputSymbol = symbol( &darkroom.extract(fn.output.type):toTerraType(), "lambdaoutput" )
    local outputValidSymbol = symbol(&bool, "lambdaoutputvalid")
    local stats = {}
    local mself = symbol( &Module, "module self" )

    local out = fn.output:visitEach(
      function(n, inputs)
        if n.kind=="input" then
          return {`@inputSymbol, inputValidSymbol}
        elseif n.kind=="apply" then
          print("APPLYHS",n.fn.terraModule)
          table.insert( Module.entries, {field=n.name, type=n.fn.terraModule} )
          local I = inputs[1][1]
          local Ivalid = inputs[1][2]
          local O = symbol( darkroom.extract(n.type):toTerraType(), "output_"..n.name)
          local Ovalid = symbol( bool, "outputvalid_"..n.name )
          local this = `mself.[n.name]
          table.insert(stats, quote var [O]; var [Ovalid]; this:process( &I, Ivalid, &O, &Ovalid) end)
          return {O,Ovalid}
        else
          print(n.kind)
          assert(false)
        end
      end)

      table.insert( stats, quote @outputSymbol=[out[1]]; @outputValidSymbol = [out[2]]; end )
      return terra( [mself], [inputSymbol], [inputValidSymbol], [outputSymbol], [outputValidSymbol] ) [stats] end
  end
                                     
  Module.methods.process = docompile( res )

  callOnEntries( Module, "reset" )

  res.terraModule = Module

  return darkroom.newFunction( res )
end

-- function definition
-- output, inputs
function darkroom.lambda( name, input, output )
  assert( type(name) == "string" )
  assert( darkroom.isIR( input ) )
  assert( input.kind=="input" )
  assert( darkroom.isIR( output ) )

  print("LAMBDA",name)

  if darkroom.isStatefulHandshake(input.type) then
    return darkroom.lambdaHandshake( name, input, output )
  end

  local output = output:typecheck()
  local res = {kind = "lambda", name=name, input = input, output = output }
  res.inputType = input.type
  res.outputType = output.type

  res.delay = output:visitEach(
    function(n, inputs)
      if n.kind=="input" or n.kind=="constant" then
        return 0
      elseif n.kind=="index" or n.kind=="extractState" then
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

  local function docompile( fn )
    local inputSymbol = symbol( &darkroom.extract(fn.input.type):toTerraType(), "lambdainput" )
    local outputSymbol = symbol( &darkroom.extract(fn.output.type):toTerraType(), "lambdaoutput" )

    local stats = {}
    local resetStats = {}
    local readyStats = {}
    local readyInput = symbol(bool, "readyinput")
    local Module = terralib.types.newstruct("lambda"..fn.name.."_module")
    Module.entries = terralib.newlist( {} )
    local mself = symbol( &Module, "module self" )

    local out = fn.output:visitEach(
      function(n, inputs)

        if true then table.insert( stats, quote cstdio.printf([n.name.."\n"]) end ) end

        local out

        if n==fn.output then
          out = outputSymbol
        elseif n.kind~="input" then
          table.insert( Module.entries, {field="simstateoutput_"..n.name, type=darkroom.extract(n.type):toTerraType()} )
          out = `&mself.["simstateoutput_"..n.name]
        end

        if n.kind=="input" then
          return {inputSymbol, readyInput}
        elseif n.kind=="apply" then
          print("APPLY",n.fn.kind, n.inputs[1].type, n.type)
          print("APP",n.name, n.fn.terraModule)
          table.insert( Module.entries, {field=n.name, type=n.fn.terraModule} )
          table.insert( resetStats, quote mself.[n.name]:reset() end )
          local readyOut = symbol( bool, "ready_"..n.name )
          if darkroom.isStatefulV(n.inputs[1].type) then table.insert( readyStats, quote var [readyOut] = mself.[n.name]:ready() end) 
          elseif darkroom.isStatefulRV(n.inputs[1].type) then table.insert( readyStats, quote var [readyOut] = mself.[n.name]:ready([inputs[1][2]]) end) end
          table.insert( stats, quote mself.[n.name]:process( [inputs[1][1]], out ) end )
          return {out,readyOut}
        elseif n.kind=="constant" then
          if n.type:isArray() then
            map( n.value, function(m,i) table.insert( stats, quote (@out)[i-1] = m end ) end )
          else
            assert(false)
          end

          return {out}
        elseif n.kind=="tuple" then
          table.insert( stats, quote for i=0,[darkroom.extract(n.type):channels()] do (@out)[i] = {[map(inputs, function(m) return `(@[m[1]])[i] end)]} end end)
          return {out}
        elseif n.kind=="index" then
          table.insert( stats, quote @out = @([inputs[1][1]]).["_"..n.idx] end)
          return {out}
        elseif n.kind=="extractState" then
          return {`nil}
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
    if darkroom.isStatefulRV(res.inputType) then
      terra Module.methods.ready( [mself], [readyInput] ) [readyStats]; return [out[2]] end
    else
      terra Module.methods.ready( [mself] ) [readyStats]; return [out[2]] end
    end

    Module.methods.process:printpretty()
    return Module
  end

  res.terraModule = docompile(res)

  return darkroom.newFunction( res )
end

function darkroom.lift( inputType, outputType, terraFunction, delay )
  assert( types.isType(inputType ) )
  assert( types.isType(outputType ) )
  assert( type(delay)=="number" )
  local struct LiftModule {}
  terra LiftModule:reset() end
  terra LiftModule:process(inp:&inputType:toTerraType(),out:&outputType:toTerraType()) terraFunction(inp,out) end
  local res = { kind="lift", inputType = inputType, outputType = outputType, delay=delay, terraModule=LiftModule }
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

function darkroom.constSeq( value, A, w, h, T )
  assert(type(value)=="table")
  assert(type(value[1])=="number")
--  assert(type(value[1][1])=="number")
  assert(T<1)
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

function darkroom.index( name, input, idx )
  assert(type(idx)=="number")
  assert(type(name)=="string")
  assert(darkroom.isIR( input ) )
  return darkroom.newIR( {kind="index", name=name, loc=getloc(), idx=idx, inputs={input}} )
end

function darkroom.extractState( name, input )
  assert(darkroom.isIR( input ) )
  return darkroom.newIR( {kind="extractState", name=name, loc=getloc(), inputs={input}, type=darkroom.State} )
end

local Im = require "image"

function darkroom.scanlHarness( Module, T,
                                inputFilename, inputType, inputWidth, inputHeight, 
                                outputFilename, outputType, outputWidth, outputHeight )
  assert(terralib.types.istype(Module))
  assert(type(T)=="number")
  assert(darkroom.isStatefulHandshake(inputType)==false)
  assert(type(inputFilename)=="string")
  assert(type(outputFilename)=="string")

  return terra()
    cstdio.printf("DOIT\n")
    var imIn : Im
    imIn:load( inputFilename )
    var imOut : Im
    imOut:allocateDarkroomFormat(outputWidth, outputHeight, 1, 1, 8, false, false, false)

--    var inp : inputType:toTerraType()
--    var out : outputType:toTerraType()

    var module : Module
    module:reset()

    for i=0,inputWidth*inputHeight,T do
      cstdio.printf("ITER %d\n",i)
      module:process( [&uint8[T]]([&uint8](imIn.data)+i), [&uint8[T]]([&uint8](imOut.data)+i) )
--      module:process( [&uint8[T]](imIn.data), [&uint8[T]](imOut.data) )
    end

    imOut:save( outputFilename )
  end
end


function darkroom.scanlHarnessHandshake( Module, T,
                                inputFilename, inputType, inputWidth, inputHeight, 
                                outputFilename, outputType, outputWidth, outputHeight )
  assert(terralib.types.istype(Module))
  assert(type(T)=="number")
  assert(darkroom.isStatefulHandshake(inputType))

  local throttle = 1
  if T<1 then throttle=1/T;T=1 end

  print("OUTPUTTYPE",outputType)
  assert(darkroom.extract(outputType):isArray())
  local outputTileW = (darkroom.extract(outputType):arrayLength())[1]
  local outputTileH = (darkroom.extract(outputType):arrayLength())[2]

  return terra()
    cstdio.printf("DOIT\n")
    var imIn : Im
    imIn:load( inputFilename )
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

    var inputValid = true
    var outputValid = true

    var TH : int = 0
    while inpAddr<inputWidth*inputHeight or outAddrY<outputHeight do
      cstdio.printf("ITER %d outX %d outY %d\n",inpAddr,outAddrX, outAddrY)
      
      if TH==0 then
        module:process( [&uint8[T]]([&uint8](imIn.data)+inpAddr), inputValid, &output, &outputValid)
        inpAddr = inpAddr + T
      else
        module:process( [&uint8[T]](nil), false, &output, &outputValid)
      end
      TH = TH + 1
      if TH>=throttle then TH=0 end

      if outputValid then
--        @[&uint8[T]]([&uint8](imOut.data)+outAddr) = output
        for y=0,outputTileH do
          for x=0,outputTileW do
            @([&uint8](imOut.data)+outAddrX+x+(outAddrY+y)*outputWidth) = output[y*outputTileW+x]
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

    imOut:save( outputFilename )

    cstdio.printf("Delay Cycles %d\n", delayCycles)
    cstdio.printf("valid percent: %f\n",[float](validCycles*100)/[float](invalidCycles+validCycles))
  end
end

return darkroom