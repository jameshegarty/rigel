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
-----------------------

darkroom = {}

darkroom.State = types.opaque("state")
function darkroom.Handshake(A) return types.tuple({A,types.bool()}) end
function darkroom.Stateful(A) return types.tuple({A,darkroom.State}) end
function darkroom.StatefulHandshake(A) return darkroom.Stateful(darkroom.Handshake(A)) end

struct EmptyState {}
terra EmptyState:init() end

darkroom.data = macro(function(i) return `i._0 end)
local data = darkroom.data
darkroom.valid = macro(function(i) return `i._1 end)
local valid = darkroom.valid
darkroom.state = macro(function(i) return `i._1 end)
local state = darkroom.state

local function getData(i, ty)
  if darkroom.isStatefulHandshake(ty) then return `i._0._0 
  elseif darkroom.isStateful(ty) then return `i._0
  elseif darkroom.isHandshake(ty) then return `i._0
  else return i end
end

local function getValid(i, ty)
  if darkroom.isStatefulHandshake(ty) then return `i._0._1
  elseif darkroom.isStateful(ty) then return `true
  elseif darkroom.isHandshake(ty) then return `i._1
  else return `true end
end

local function setValid( i, ty, value )
  if darkroom.isStatefulHandshake(ty) then return quote valid(data(i)) = value end
  elseif darkroom.isStateful(ty) then return quote end
  elseif darkroom.isHandshake(ty) then return quote valid(i) = value end
  else return quote end end
end

local function setState( i, ty, value )
  if darkroom.isStateful(ty) then return quote state(i) = value end
  else return quote end end
end

local dataOptional = function (v, ty) if darkroom.isHandshake(ty) then return `data(v) else return `@v end end
local validOptional = function (v, ty) if darkroom.isHandshake(ty) then return `valid(v) else return `true end end


function darkroom.isHandshake( a )
  if a:isTuple()==false then return false end
  if a.list[2]~=types.bool() then return false end
  return true
end

function darkroom.isStateful( a )
  if a:isTuple()==false then return false end
  if a.list[2]~=darkroom.State then return false end
  return true
end

function darkroom.isStatefulHandshake( a ) return darkroom.isStateful(a) and darkroom.isHandshake(a.list[1]) end

function darkroom.extractHandshake( a, loc )
  if darkroom.isHandshake(a)==false then error("Not a handshake input, "..loc) end
  return a.list[1]
end

function darkroom.extractStateful( a, loc )
  if darkroom.isStateful(a)==false then error("Not a stateful input, "..loc) end
  return a.list[1]
end

function darkroom.extractStatefulHandshake( a, loc )
  return darkroom.extractHandshake( darkroom.extractStateful(a), loc )
end

darkroomFunctionFunctions = {}
darkroomFunctionMT={__index=darkroomFunctionFunctions}

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
        n.type = n.fn:typecheck( n.inputs[1].type, n.loc )
        return darkroom.newIR( n )
      elseif n.kind=="input" then
      elseif n.kind=="constant" then
      elseif n.kind=="tuple" then
        local tt = {}
        local sz
        local wasHandshook = false
        for _,v in pairs(n.inputs) do
          print("TUPLEINPT",v.type)
          local o = v.type
          if darkroom.isHandshake(v.type) then
            wasHandshook = true
            o = darkroom.extractHandshake( v.type, n.loc)
          end
          if o:isArray()==false then error("input to tuple must be an array, "..n.loc) end
          if sz==nil then sz=o:arrayLength() 
          elseif sz~=o:arrayLength() then error("inputs to tuple must have same size,"..n.loc) end
          table.insert( tt, o:arrayOver() )
        end

        n.type = types.array2d( types.tuple(tt), sz[1], sz[2] )
        if wasHandshook then n.type = darkroom.Handshake(n.type) end
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
function darkroom.map( f )
  assert( darkroom.isFunction(f) )

  local res = { kind="map", fn = f }
  res.typecheck = function( self, inputType, loc )
    if inputType:isArray()==false then error("Map input must be array but is "..tostring(inputType)..", "..loc) end
    local res = self.fn:typecheck( inputType:arrayOver(), loc )
    local r = types.array2d( res, (inputType:arrayLength())[1], (inputType:arrayLength())[2] )
    return r
  end
  res.delay = function( self, inputType ) return self.fn:delay(inputType) end
  res.compile = function( self, inputType, outputType )
    local f, fSimState, fState = self.fn:compile( inputType:arrayOver(), outputType:arrayOver() )
    local N = inputType:channels()
    local inp = symbol( &inputType:toTerraType(), "input" )
    local out = symbol( &outputType:toTerraType(), "output" )
    local terra mapf( simstate : &opaque, [inp], [out] )
      cstdio.printf("MAP\n")
      for i=0,N do f( nil, &((@inp)[i]), &((@out)[i])  ) end
    end
    mapf:printpretty()
    return mapf, EmptyState
  end

  return darkroom.newFunction(res)
end

-- broadcast : ( v : A , n : number ) -> A[n]
--darkroom.broadcast = darkroom.newDarkroomFunction( { kind = "broadcast" } )

-- extractStencils : A[n] -> A[(xmax-xmin+1)*(ymax-ymin+1)][n]
-- min, max ranges are inclusive
function darkroom.extractStencils( xmin, xmax, ymin, ymax )
  assert( type(xmin)=="number" )
  assert( type(xmax)=="number" )
  assert( xmax>=xmin )
  assert( type(ymin)=="number" )
  assert( type(ymax)=="number" )
  assert( ymax>=ymin )

  local res = {kind="extractStencils", xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax }
  res.typecheck = function( self, inputType )
    if inputType:isArray()==false then error("Input to extract stencils must be array") end
    local sz = inputType:arrayLength()
    return types.array2d( types.array2d( inputType:arrayOver(), self.xmax - self.xmin + 1, self.ymax - self.ymin + 1 ), sz[1], sz[2])
  end

  res.compile = function( self, inputType, outputType )
    local N = inputType:channels()
    local W = (inputType:arrayLength())[1]
    local inp = symbol( &inputType:toTerraType(), "input" )
    local out = symbol( &outputType:toTerraType(), "output" )

    local terra stencil( simstate : &opaque, [inp], [out] )
      for i=0,N do
        for y = self.ymin, self.ymax+1 do
          for x = self.xmin, self.xmax+1 do
            ((@out)[i])[(y-self.ymin)*(self.xmax-self.xmin+1)+(x-self.xmin)] = (@inp)[i+x+y*W]
          end
        end
      end
    end
    stencil:printpretty()
    return stencil, EmptyState
  end

  return darkroom.newFunction(res)
end

function darkroom.linebuffer( T, w, h, l, r, t, b )
  map({T,w,h,l,r,t,b}, function(i) assert(type(i)=="number") end)
  assert(T>=1); assert(w>0); assert(h>0);
  assert(l<r)
  assert(b<t)
  assert(r==0)
  assert(t==0)

  local res = {kind="linebuffer", T=T, w=w, h=h, l=l,r=r,t=t,b=b}

  res.typecheck = function( self, inputType, loc )
    local over = darkroom.extractStateful( inputType, loc )
    -- over should be type A[T]
    if over:isArray()==false or (over:arrayLength())[1]~=T or (over:arrayLength())[2]~=1 then error("input to linebuffer must be type A[T], "..loc) end

    local ty = types.array2d( over:arrayOver(), -self.l+self.T, -self.b+1 )
    return darkroom.Stateful( ty )
  end

  res.compile = function( self, inputType, outputType )
    local over = darkroom.extractStateful( inputType ):arrayOver()
    local State = simmodules.shiftRegister( over:toTerraType(), self.w*(-self.b+1))
    local W = -self.l+self.T
    local terra linebuffer ( simstate : &opaque, inp : &inputType:toTerraType(), out : &outputType:toTerraType() )
      var state = [&State](state(inp))

      -- pretend that this happens in one cycle (delays are added later)
      for i=0,[self.T] do
        state:pushBack( &data(inp)[i] )
      end

      for y=[self.b],1 do
        for x=[self.l-self.T+1],1 do
          data(out)[(y-self.b)*W+(x-self.l+self.T-1)] = @(state:peekBack(x+y*[self.w]))
        end
      end

    end
    return linebuffer, EmptyState, State
  end

  return darkroom.newFunction(res)
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

function darkroom.statePassthrough( f )
  assert( darkroom.isFunction(f) )
  local res = { kind="statePassthrough", fn = f }
  res.typecheck = function( self, inputType, loc )
    print("TS",inputType)
    local o = darkroom.extractStateful( inputType, loc )
    local r = self.fn:typecheck( o, loc )
    return darkroom.Stateful(r)
  end
  res.compile = function( self, inputType, outputType )
    local tfn = self.fn:compile( darkroom.extractStateful(inputType), darkroom.extractStateful(outputType) )
    local terra statePassthrough( ss : &opaque, inp : &inputType:toTerraType(), out : &outputType:toTerraType() )
      tfn( ss, &data(inp), &data(out) )
    end
    statePassthrough:printpretty()
    return statePassthrough, EmptyState
  end
  return darkroom.newFunction(res)
end

function darkroom.makeHandshake( f )
  assert( darkroom.isFunction(f) )
  local res = { kind="makeHandshake", fn = f }
  res.typecheck = function( self, inputType, loc )
    local ty = darkroom.extractHandshake( inputType )
    local r = self.fn:typecheck( ty, loc )
    if darkroom.isHandshake(r)==false then r=darkroom.Handshake(r) end
    return r
  end
  res.simState = function( self, inputType )
    return 
  end
  res.compile = function( self, inputType, outputType ) 
    local tfn = self.fn:compile( darkroom.extractHandshake(inputType), darkroom.extractHandshake(outputType) )
    local delay = self.fn:delay( darkroom.extractHandshake(inputType) )
    local SimState = simmodules.fifo( inputType:toTerraType(), delay )
    local terra makeHandshakefn( simstate : &opaque, inp : &inputType:toTerraType(), out : &outputType:toTerraType() )
      var simst = [&SimState](simstate)
      if simst:size()==delay then
        var I = simst:popFront()
        if valid(I) then
          tfn( nil, &data(I), &data(out) )
          valid(out) = true
        else
          valid(out) = false
        end
      end
      simst:pushBack(inp)
    end
    return makeHandshakefn, SimState
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

  local output = output:typecheck()
  local res = {kind = "function", name=name, input = input, output = output }
  res.typecheck = function( self, inputType, loc )
    if inputType~=self.input.type then error("lambda input type doesn't match. Should be "..tostring(self.input.type).." but is "..tostring(inputType)..", "..loc) end
    return self.output.type
  end

  res.delay = function( self, inputType )
    assert( darkroom.isHandshake(inputType) == false )
    return self.output:visitEach(
      function(n, inputs)
        if n.kind=="input" or n.kind=="constant" then
          return 0
        elseif n.kind=="apply" then
          return inputs[1] + n.fn:delay( n.inputs[1].type )
        else
          assert(false)
        end
      end)
  end
  
  local function docompile( fn )
    local stats = {}

    local State = terralib.types.newstruct("State_"..fn.name)
    local SimState = terralib.types.newstruct("SimState_"..fn.name)
    local simStateSymbol = symbol( &SimState, "simstate")
    local stateSymbol = symbol( &State, "state")

    local inputSymbol = symbol( &fn.input.type:toTerraType(), "lambdainput" )
    local outputSymbol = symbol( &fn.output.type:toTerraType(), "lambdaoutput" )

    local out = fn.output:visitEach(
      function(n, inputs)

        if true then table.insert( stats, quote cstdio.printf([n.name.."\n"]) end ) end

        local out

        if n==fn.output then
          out = outputSymbol
        elseif n.kind=="apply" or n.kind=="tuple" or n.kind=="constant" then
          out = symbol( &n.type:toTerraType(), n.name.."_out" )
          table.insert(stats, 
                       quote var [out] = [&n.type:toTerraType()](cstdlib.malloc(sizeof([n.type:toTerraType()]))) 
                         defer cstdlib.free(out)
                       end)
        end


        if n.kind=="input" then
          return inputSymbol
        elseif n.kind=="apply" then
          print("APPLY",n.fn.kind, n.inputs[1].type, n.type)
          local fn, aSimState, aState = n.fn:compile( n.inputs[1].type, n.type )
          if aSimState~=nil then table.insert( SimState.entries, {field=n.name, type=aSimState} ) end
          if aState~=nil then table.insert( State.entries, {field=n.name, type=aState} ) end
          table.insert(stats, quote fn( &simStateSymbol.[n.name], [inputs[1]], out ) end )
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
        elseif n.kind=="tupleHandshake" then
          table.insert( stats, 
                        quote
                          for i=0,[darkroom.extractHandshake(n.type):channels()] do 
                            data(out)[i] = {[map(n.inputs, function(m,k) return `([dataOptional(inputs[k],m.type)])[i] end)]} 
                          end
                          valid(out) = [foldl(andopterra, true, map(n.inputs, function(m,k) return validOptional(inputs[k],m.type) end) ) ]
                        end)
          return out
        else
          print(n.kind)
          assert(false)
        end
      end)

    callOnEntries(SimState,"init")
    callOnEntries(State,"init")

    return terra( simstate : &opaque, [inputSymbol], [outputSymbol] )
--        cstdio.printf([fn.name.."\n"])
      var [simStateSymbol] = [&SimState](simstate)
      [stats]
           end, SimState, State
  end

  local compiledfn, SimState, State= docompile(res)
  print("FN")
  compiledfn:printpretty()
  res.compile = function() return compiledfn, SimState, State end

  return darkroom.newFunction( res )
end

function darkroom.lift( inputType, outputType, terraFunction, delay )
  assert( types.isType(inputType ) )
  assert( types.isType(outputType ) )
  assert( type(delay)=="number" )
  local res = { kind="lift", inputType = inputType, outputType = outputType, terraFunction = terraFunction }
  res.typecheck = function( self, inputType, loc )
    if inputType~=self.inputType then error("lifted function input type doesn't match. Should be "..tostring(self.inputType).." but is "..tostring(inputType)..", "..loc) end
    return self.outputType
  end
  res.delay = function( self, inputType ) return delay end
  res.compile = function( self, inputType, outputType ) 
    return terra(ss:&opaque, inp : &inputType:toTerraType(), out : &outputType:toTerraType())
      terraFunction(inp,out)
           end, EmptyState
  end

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

local Im = require "image"

function darkroom.scanlHarness( tfn, SimState, State, T,
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

    var simState : SimState
    simState:init()

    var inp : inputType:toTerraType()
    [setValid(inp, inputType, true)]
    [setState(inp, inputType, quote var s = [&State](cstdlib.malloc(sizeof(State))); s:init() in s end)]
    var out : outputType:toTerraType()

    var delayCycles : int = 0
    var inpAddr = 0
    var outAddr = 0
    
    while inpAddr<inputWidth*inputHeight and outAddr<outputWidth*outputHeight do
      cstring.memcpy(&[getData(inp, inputType)], [&uint8](imIn.data)+inpAddr, T)
      inpAddr = inpAddr + T
      tfn( &simState, &inp, &out )
      
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