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
--                    inputValid=input:valid(); 
--                    if this:ready() and input:valid() then input:pop(&inputValue) end
--                    this:push(inputValid, inputValue) end -- assert(inputValid==false or this:ready())
--                    :push does the actual computation, and dumps into the internal fifo. :pop just accesses the internal fifo
-----------------------

darkroom = {}

DEFAULT_FIFO_SIZE = 2048

darkroom.State = types.opaque("state")
function darkroom.Stateful(A) return types.tuple({A,darkroom.State}) end
function darkroom.StatefulHandshake(A) return types.tuple({ A, darkroom.State, types.bool(), types.bool() }) end

struct EmptyState {}
terra EmptyState:init() end

darkroom.data = macro(function(i) return `i._0 end)
local data = darkroom.data
darkroom.valid = macro(function(i) return `i._2 end)
local valid = darkroom.valid
darkroom.ready = macro(function(i) return `i._3 end)
local ready = darkroom.ready
darkroom.state = macro(function(i) return `i._1 end)
local state = darkroom.state

local function getData(i, ty) if darkroom.isStatefulHandshake(ty) or darkroom.isStateful(ty) then return `data(i) else return i end end
local function getValid(i, ty) if darkroom.isStatefulHandshake(ty) then return `valid(i) else return true end end 
local function setValid(i, ty, value) if darkroom.isStatefulHandshake(ty) then return quote valid(i) = value end else return quote end end end
local function setState(i, ty, value) if darkroom.isStatefulHandshake(ty) or darkroom.isStateful(ty) then return quote state(i) = value end else return quote end end end

function darkroom.isStateful( a ) return a:isTuple() and a.list[2]==darkroom.State end
function darkroom.isStatefulHandshake( a ) return a:isTuple() and a.list[2]==darkroom.State and a.list[3]==types.bool() end
function darkroom.expectPure( A, er ) if darkroom.isStateful(A) or darkroom.isStatefulHandshake(A) then error(er or "type should be pure") end end
function darkroom.expectStateful( A, er ) if darkroom.isStateful(A)==false then error(er or "type should be stateful") end end

function darkroom.extractStateful( a, loc )
  if darkroom.isStateful(a)==false then error("Not a stateful input, "..loc) end
  return a.list[1]
end

function darkroom.extract( a, loc )
  assert(darkroom.isStatefulHandshake(a)==false)
  if darkroom.isStateful(a)==false then return a end
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
        if n.fn.inputType~=n.inputs[1].type then error("Input type mismatch. Is "..n.inputs[1].type.." but should be "..n.fn.inputType..", "..n.loc) end
        n.type = n.fn.outputType
        return darkroom.newIR( n )
      elseif n.kind=="input" then
      elseif n.kind=="index" then
        if n.inputs[1].type:isTuple()==false then error("input to index must be a tuple but is "..tostring(n.inputs[1].type)..", "..n.loc) end
        if n.idx>=#n.inputs[1].type.list then error("index to tuple goes over end of tuple, "..n.loc) end
        n.type = n.inputs[1].type.list[n.idx+1]
        return darkroom.newIR(n)
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
function darkroom.extractStencils( A, w, h, xmin, xmax, ymin, ymax )
  assert( type(xmin)=="number" )
  assert( type(xmax)=="number" )
  assert( xmax>=xmin )
  assert( type(ymin)=="number" )
  assert( type(ymax)=="number" )
  assert( ymax>=ymin )

  darkroom.expectPure(A)
  if A:isArray()==false then error("Input to extract stencils must be array") end

  local res = {kind="extractStencils", type=A, w=w, h=h, xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax }
  res.inputType = types.array2d(A,w,h)
  res.outputType = types.array2d(types.array2d(A,xmax-xmin+1,ymax-ymin+1),w,h)
  local terra stencil( inp : res.inputType, out : res.outputType )
    for i=0,[w*h] do
      for y = ymin, ymax+1 do
        for x = xmin, xmax+1 do
          ((@out)[i])[(y-ymin)*(xmax-xmin+1)+(x-xmin)] = (@inp)[i+x+y*w]
        end
      end
    end
  end
  res.terraFn = stencil

  return darkroom.newFunction(res)
end

function darkroom.linebuffer( A, w, h, T, ymin )
  assert(w>0); assert(h>0);
  assert(ymin<0)

  local res = {kind="linebuffer", type=A, T=T, w=w, h=h, xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax }
  darkroom.expectPure(A)
  res.inputType = darkroom.Stateful(types.array2d(A,T))
  res.outputType = darkroom.Stateful(types.array2d(types.array2d(A,xmax-xmin+1,ymax-ymin+1),w,h))
  res.State = simmodules.shiftRegister( over:toTerraType(), self.w*(-self.b+1))
  local W = -xmin+T
  local terra linebuffer ( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    var state = [&State](state(inp))

    -- pretend that this happens in one cycle (delays are added later)
    for i=0,[T] do
      state:pushBack( &data(inp)[i] )
    end

    for y=[ymin],1 do
      for x=[xmin-T+1],1 do
        data(out)[(y-ymin)*W+(x-xmin+T-1)] = @(state:peekBack(x+y*[w]))
      end
    end

  end
  res.terraFn = linebuffer

  return darkroom.newFunction(res)
end

function darkroom.SSR( A, T, xmin, ymin )
  local res = {kind="SSR", type=A, T=T, xmin=xmin, ymin=ymin }
  res.inputType = darkroom.Stateful(types.array2d(A,T,-ymin+1))
  res.outputType = darkroom.Stateful(types.array2d(A,T-xmin,-ymin+1))
  return darkroom.newFunction(res)
end

function darkroom.SSRPartial( A, T, xmin, ymin )
  assert(T<1); 
  assert((-xmin+1)*T==math.floor((-xmin+1)*T))
  local res = {kind="SSRPartial", type=A, T=T, xmin=xmin, ymin=ymin }
  res.inputType = darkroom.StatefulHandshake(types.array2d(A,1,-ymin+1))
  res.outputType = darkroom.StatefulHandshake(types.array2d(A,(-xmin+1)*T,-ymin+1))
  return darkroom.newFunction(res)
end

function darkroom.stencilLinebuffer( A, w, h, T, xmin, xmax, ymin, ymax )
  map({A,T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T>=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  return darkroom.compose("stencilLinebuffer", darkroom.SSR( A, T, xmin, ymin), darkroom.linebuffer( A, w, h, T, ymin ) )
end

function darkroom.stencilLinebufferPartial( A, w, h, T, xmin, xmax, ymin, ymax )
  map({A,T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T<1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  return darkroom.compose("stencilLinebuffer", darkroom.SSRPartial( A, T, xmin, ymin), darkroom.linebuffer( A, w, h, 1, ymin ) )
end

function darkroom.unpackStencil( stencilW, stencilH, T )
  assert(type(stencilW)=="number")
  assert(stencilW>0)
  assert(type(stencilH)=="number")
  assert(stencilH>0)
  assert(type(T)=="number")
  assert(T>0)

  local res = {kind="unpackStencil", stencilW=stencilW, stencilH=stencilH,T=T}
  res.typecheck = function( self, inputType, loc )
    if inputType:isArray()==false or (inputType:arrayLength())[1]~=self.stencilW+self.T-1 or (inputType:arrayLength())[1]~=self.stencilW+self.T-1 then
      error("unpackStencil input type should be A[stencilW+T-1,stencilH] but is "..tostring(inputType)..", "..loc) end
    local ty = types.array2d( inputType:arrayOver(), self.stencilW, self.stencilH )
    return types.array2d( ty, T )
  end

  res.compile = function( self, inputType, outputType )
    local terra unpackStencil( ss : &opaque, inp : &inputType:toTerraType(), out : &outputType:toTerraType() )
      for i=0,[self.T] do
        for y=0,[self.stencilH] do
          for x=0,[self.stencilW] do
            (@out)[i][y*self.stencilH+x] = (@inp)[y*(self.stencilW+self.T-1)+x+i]
          end
        end
      end
    end
    unpackStencil:printpretty()
    return unpackStencil, EmptyState
  end

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
  local struct MakeHandshake{ delaysr = simmodules.fifo( res.outputType:toTerraType(), delay)),
                              fifo: simmodules.fifo( darkroom.extract(res.outputType):toTerraType(), DEFAULT_FIFO_SIZE),
                              inner: f.terraModule}

  terra MakeHandshake:reset() self.fifo:init(); self.inner:init() end
  local terra makeHandshakefn( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    var st = [&res.State](state(inp))
    if ready(out)==false then
      darkroomAssert(valid(inp)==false, "makeHandshake: input should be invald when stalled")
      valid(out) = false
    else
      if st.fifo:size()==delay then
        var I = st.fifo:popFront()
        if valid(I) then
          state(I) = &st.inner -- this is just a pointer
          [f.terraFn]( [&f.inputType:toTerraType()](I), [&f.outputType:toTerraType()](out) ); 
          valid(out) = true; 
        else
          valid(out) = false
        end
      else
        valid(out) = false
      end
      st.fifo:pushBack(inp)
    end
  end
  res.terraFn = makeHandshakefn
  res.terraFnBackwards = terra( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    ready(inp) = ready(out)
  end

  return darkroom.newFunction(res)
end

function darkroom.reduce( f )
  if darkroom.isFunction(f)==false then error("Argument to reduce must be a darkroom function") end
  
  local res = {kind="reduce", fn = f}

  res.typecheck = function( self, inputType, loc )
    if inputType:isArray()==false then error("Reduce input must be an array but is "..tostring(inputType)..", "..loc) end
    local finput = types.tuple({inputType:arrayOver(),inputType:arrayOver()})
    print("FINPT",finput,inputType)
    local foutput = self.fn:typecheck( finput, loc )
    if foutput~=inputType:arrayOver() then error("Reduction function f must be of type {A,A}->A, "..loc) end
    return inputType:arrayOver()
  end
  res.delay = function( self, inputType ) print("DIT",inputType);return math.ceil(math.log(inputType:channels())/math.log(2))*self.fn:delay(inputType:arrayOver()) end
  res.compile = function ( self, inputType, outputType )
    local fninptype = types.tuple({outputType,outputType})
    local f, fSimState = self.fn:compile( fninptype, outputType )
    local N = inputType:channels()
    local SimState = fSimState[N]
    local inp = symbol( &inputType:toTerraType(), "input" )
    local out = symbol( &outputType:toTerraType(), "output" )

    local terra reduce( simstate : &opaque, [inp], [out] )
      var ss = [&SimState](simstate)
      var res : outputType:toTerraType() = (@inp)[0]
      for i=1,N do
        var tinp : fninptype:toTerraType() = {res, (@inp)[i]}
        f( &((@ss)[i]), &tinp, &res  )
      end
      @out = res
    end
    return reduce, SimState
  end

  return darkroom.newFunction( res )
end


function darkroom.reduceSeq( f, T )
  assert(T<1)

  local res = {kind="reduceSeq", fn=f}
  function res:typecheck( inputType, loc )
    local o = darkroom.extractStateful( inputType )
    if o:isArray() then error("ReduceSeq input must be a scalar but is "..tostring(o)..", "..loc) end
    return darkroom.StatefulHandshake(o)
  end
  res.delay=function() return 0 end
  function res:compile( inputType, outputType )
    local OT = darkroom.extractStatefulHandshake(outputType)
    local finput = types.tuple({OT,OT})
    local f = self.fn:compile( finput, OT )
    local struct ReduceSeqState {phase : int; data : OT:toTerraType()}
    terra ReduceSeqState:init() self.phase=0 end
    local terra reduceSeq(ss : &opaque, inp : &inputType:toTerraType(), out : &outputType:toTerraType() )
      var s = [&ReduceSeqState](state(inp))
      valid(out) = false
      if s.phase==0 then 
        s.data = data(inp)
        s.phase = s.phase + 1
      else
        var v = {s.data, data(inp)}
        f( nil, &v, &s.data )

        if s.phase==[1/T] then
          s.phase = 0
          valid(out) = true
          data(out) = s.data
        else
          s.phase = s.phase + 1
        end
      end

    end
    return reduceSeq, EmptyState, ReduceSeqState
  end

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
  for k,v in pairs( T.entries ) do table.insert( ssStats, quote TS.[v.field]:[fnname]() end) end
  terra T.methods.init([TS]) [ssStats] end
end

-- function definition
-- output, inputs
function darkroom.lambda( name, input, output )
  assert( type(name) == "string" )
  assert( darkroom.isIR( input ) )
  assert( input.kind=="input" )
  assert( darkroom.isIR( output ) )

  assert(darkroom.isStatefulHandshake(input.type)==false)

  local output = output:typecheck()
  local res = {kind = "lambda", name=name, input = input, output = output }
  res.inputType = input.type
  res.outputType = output.type

  res.delay = output:visitEach(
    function(n, inputs)
      if n.kind=="input" or n.kind=="constant" then
        return 0
      elseif n.kind=="index" then
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
          return inputSymbol
        elseif n.kind=="apply" then
          print("APPLY",n.fn.kind, n.inputs[1].type, n.type)
          print("APP",n.name, n.fn.terraModule)
          table.insert( Module.entries, {field=n.name, type=n.fn.terraModule} )
          table.insert(stats, quote mself.[n.name]:process( [inputs[1]], out ) end )
          return out
        elseif n.kind=="constant" then
          if n.type:isArray() then
            map( n.value, function(m,i) table.insert( stats, quote (@out)[i-1] = m end ) end )
          else
            assert(false)
          end

          return out
        elseif n.kind=="tuple" then
          table.insert( stats, quote for i=0,[n.type:channels()] do (@out)[i] = {[map(inputs, function(m) return `(@m)[i] end)]} end end)
          return out
        elseif n.kind=="index" then
          table.insert( state, quote @out = @([inputs[1]]).["_"..n.idx] end)
          return out
        else
          print(n.kind)
          assert(false)
        end
      end)

    callOnEntries(Module,"reset")

    terra Module.methods.process( [mself], [inputSymbol], [outputSymbol] )
--        cstdio.printf([fn.name.."\n"])
      [stats]
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

function darkroom.constSeq( value, ty, T )
  assert(type(value)=="table")
  assert(type(value[1])=="table")
  assert(type(value[1][1])=="number")
  assert(ty:isArray())
  assert(T<1)

  local res = { kind="constSeq", type = ty, value=value, T=T}
  function res:typecheck( inputType, loc )
    if inputType~=darkroom.State then error("constSeq should be State, but has input type "..tostring(inputType)..", "..loc) end
    local W = (self.type:arrayLength())[1] * self.T
    if W ~= math.floor(W) then error("constSeq T must divide array size, "..loc) end
    return darkroom.Stateful(types.array2d(self.type:arrayOver(),W, (self.type:arrayLength())[2] ))
  end
  res.delay = function() return 0 end
  function res:compile( inputType, outputType )
    local OT = darkroom.extractStateful(outputType)
    local struct ConstSeqState {phase : int; data : (OT:arrayOver():toTerraType())[OT:channels()][1/T] }
    terra ConstSeqState:init()
      self.phase = 0
    end

    local terra constSeq(ss : &opaque, inp : &inputType:toTerraType(), out : &outputType:toTerraType() )
      var s = [&ConstSeqState](inp)
      var res = s.data[s.phase]
      s.phase = s.phase + 1
      if s.phase == [1/T] then s.phase = 0 end
      return res
    end
    return constSeq, EmptyState, ConstSeqState
  end

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
  assert(terralib.isfunction(tfn))
  assert(terralib.types.istype(SimState))
  assert(terralib.types.istype(State))
  assert(type(T)=="number")

  return terra()
    cstdio.printf("DOIT\n")
    var imIn : Im
    imIn:load( inputFilename )
    var imOut : Im
    imOut:allocateDarkroomFormat(outputWidth, outputHeight, 1, 1, 8, false, false, false)

    var inp : inputType:toTerraType()
    [setValid(inp, inputType, true)]
    [setState(inp, inputType, quote var s = [&State](cstdlib.malloc(sizeof(State))); s:init() in s end)]
    var out : outputType:toTerraType()

    var delayCycles : int = 0
    var inpAddr = 0
    var outAddr = 0
    
    while inpAddr<inputWidth*inputHeight and outAddr<outputWidth*outputHeight do
      cstdio.printf("ITER %d %d\n",inpAddr,outAddr)
      cstring.memcpy(&[getData(inp, inputType)], [&uint8](imIn.data)+inpAddr, T)
      inpAddr = inpAddr + T
      tfn( &inp, &out )
      
      if [getValid(out, outputType)] then 
        cstring.memcpy([&uint8](imOut.data)+outAddr, &[getData(out, outputType)], T)
        outAddr = outAddr+T; 
      else
        delayCycles = delayCycles + 1
      end
    end

    imOut:save( outputFilename )

    cstdio.printf("Delay Cycles %d\n", delayCycles)
  end
end

return darkroom