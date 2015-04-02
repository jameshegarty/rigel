IR = require("IR")
types = require("types")
cstring = terralib.includec("string.h")
cstdlib = terralib.includec("stdlib.h")
cstdio = terralib.includec("stdio.h")
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
        for _,v in pairs(n.inputs) do
          if v.type:isArray()==false then error("input to tuple must be an array, "..n.loc) end
          if sz==nil then sz=v.type:arrayLength() 
          elseif sz~=v.type:arrayLength() then error("inputs to tuple must have same size,"..n.loc) end
          table.insert( tt, v.type:arrayOver() )
        end

        n.type = types.array2d( types.tuple(tt), sz[1], sz[2] )
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
    if inputType:isArray()==false then error("Map input must be array, "..loc) end
    local res = self.fn:typecheck( inputType:arrayOver(), loc )
    return types.array2d( res, (inputType:arrayLength())[1], (inputType:arrayLength())[2] )
  end

  res.compile = function( self, inputType, outputType )
    local f = self.fn:compile( inputType:arrayOver(), outputType:arrayOver() )
    local N = inputType:channels()
    local inp = symbol( &inputType:toTerraType(), "input" )
    local out = symbol( &outputType:toTerraType(), "output" )
    local terra mapf( [inp], [out] )
      for i=0,N do 
        f( &((@inp)[i]), &((@out)[i])  )
      end
    end
    mapf:printpretty()
    return mapf
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

    local terra stencil( [inp], [out] )
      for i=0,N do
        for y = self.ymin, self.ymax+1 do
          for x = self.xmin, self.xmax+1 do
            ((@out)[i])[(y-self.ymin)*(self.xmax-self.xmin+1)+(x-self.xmin)] = (@inp)[i+x+y*W]
          end
        end
      end
    end
    stencil:printpretty()
    return stencil
  end

  return darkroom.newFunction(res)
end

function darkroom.reduce( f )
  if darkroom.isFunction(f)==false then error("Argument to reduce must be a darkroom function") end
  
  local res = {kind="reduce", fn = f}

  res.typecheck = function( self, inputType )
    if inputType:isArray()==false then error("Reduce input must be an array") end
    local finput = types.tuple({inputType:arrayOver(),inputType:arrayOver()})
    local foutput = self.fn:typecheck( finput )
    if foutput~=inputType:arrayOver() then error("Reduction function f must be of type {A,A}->A") end
    return inputType:arrayOver()
  end

  res.compile = function ( self, inputType, outputType )
    local fninptype = types.tuple({outputType,outputType})
    local f = self.fn:compile( fninptype, outputType )
    local N = inputType:channels()
    local inp = symbol( &inputType:toTerraType(), "input" )
    local out = symbol( &outputType:toTerraType(), "output" )

    local terra reduce( [inp], [out] )
      var res : outputType:toTerraType() = (@inp)[0]
      for i=1,N do
        var tinp : fninptype:toTerraType() = {res, (@inp)[i]}
        f( &tinp, &res  )
      end
      @out = res
    end
    return reduce
  end

  return darkroom.newFunction( res )
end

-- function argument
function darkroom.input( type )
  assert( types.isType( type ) )
  return darkroom.newIR( {kind="input", type = type, name="input", inputs={}} )
end

-- function definition
-- output, inputs
function darkroom.lambda( input, output )
  assert( darkroom.isIR( input ) )
  assert( input.kind=="input" )
  assert( darkroom.isIR( output ) )

  local output = output:typecheck()
  local res = {kind = "function", input = input, output = output }
  res.typecheck = function( self, inputType, loc )
    if inputType~=self.input.type then error("lambda input type doesn't match. Should be "..tostring(self.input.type).." but is "..tostring(inputType)..", "..loc) end
    return self.output.type
  end
  
  local function docompile( fn )
    local stats = {}
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
          local fn = n.fn:compile( n.inputs[1].type, n.type )
          map(inputs,print)
          table.insert(stats, quote fn( [inputs[1]], out ) end )
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
        else
          print(n.kind)
          assert(false)
        end
      end)

    return terra( [inputSymbol], [outputSymbol] )
--        cstdio.printf([fn.name.."\n"])
      [stats]
    end
  end

  local compiledfn = docompile(res)
  print("FN")
  compiledfn:printpretty()
  res.compile = function() return compiledfn end

  return darkroom.newFunction( res )
end

function darkroom.lift( inputType, outputType, terraFunction )
  assert( types.isType(inputType ) )
  assert( types.isType(outputType ) )
  local res = { kind="lift", inputType = inputType, outputType = outputType, terraFunction = terraFunction }
  res.typecheck = function( self, inputType, loc )
    if inputType~=self.inputType then error("lifted function input type doesn't match. Should be "..tostring(self.inputType).." but is "..tostring(inputType)..", "..loc) end
    return self.outputType
  end
  res.compile = function() return terraFunction end

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

return darkroom