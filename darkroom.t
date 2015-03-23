cstring = terralib.includec("string.h")
local ffi = require("ffi")

darkroom = {}

darkroomFunctionFunctions = {}
darkroomFunctionMT={__index=darkroomFunctionFunctions}

function darkroom.newFunction(tab)
  assert( type(tab) == "table" )
  return setmetatable( tab, darkroomFunctionMT )
end

darkroomIRFunctions = {}
setmetatable( darkroomIRFunctions,{__index=IRFunctions})
darkroomIRMT = {__index = darkroomIRFunctions }

function darkroom.newDarkroomIR(tab)
  assert( type(tab) == "table" )
  darkroom.IR.new( tab )
  return setmetatable( tab, darkroomIRMT )
end

function darkroom.isFunction(t) return getmetatable(t)==darkroomFunctionMT end
function darkroom.isDarkroomIR(t) return getmetatable(t)==darkroomIRMT end

-- arrays: A[W][H]. Row major
-- array index A[y] yields type A[W]. A[y][x] yields type A

-- f : ( A, B, ...) -> C (darkroom function)
-- map : ( f, A[n], B[n], ...) -> C[n]
function darkroom.map( f )
  assert( type(name)=="string" )
  assert( isDarkroomFunction(f) )

  local res = { kind="map", fn = f }
  res.typecheck = function( self, inputType )
    local calltype = {}
    local size
    for _,v in pairs( inputType:tupleList() ) do
      if v:isArray()==false then error("Map inputs must be arrays") end
      if size==nil then 
        size = v:arrayLength() 
      elseif size[1]~=(v:arrayLength())[1] or size[2]~=(v:arrayLength())[2] then
        error("Map inputs must have same size")
      end
      table.insert( calltype:arrayOver() )
    end
    local res = self.fn:typecheck( darkroom.type.tuple( calltype ) )
    return darkroom.type.array2d( res, w, h )
  end
  
  return darkroom.newDarkroomFunction(res)
end

-- broadcast : ( v : A , n : number ) -> A[n]
darkroom.broadcast = darkroom.newDarkroomFunction( { kind = "broadcast" } )

-- extractStencils : A[n] -> A[(xmax-xmin+1)*(ymax-ymin+1)][n]
-- min, max ranges are inclusive
function d.extractStencils( xmin, xmax, ymin, ymax )
  assert( type(xmin)=="number" )
  assert( type(xmax)=="number" )
  assert( xmax>=xmin )
  assert( type(ymin)=="number" )
  assert( type(ymax)=="number" )
  assert( ymax>=ymin )

  local res = {kind="extractStencils", xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax }
  res.typecheck = function( self, inputType )
    if inputType:isArray()==false then error("Input to extract stencils must be array") end
    return darkroom.type.array2d( inp.type:arrayOver(), self.xmax - self.xmin + 1, self.ymax - self.ymin + 1 )
  end
  
  return darkroom.newFunction(res)
end

-- slice : A[n] -> A[ (r-l+1) * (t-b+1) ]
-- l,r,t,b are inclusive
function d.slice( A, arrayWidth, l, r, t, b )
  assert( l>=0 ); assert( r>=0 ); assert( t>=0 ); assert( b>=0 )
  assert(l<=r)
  assert(b<=t)
  assert( type(arrayWidth)=="number" )
  assert( arrayWidth > 0 )
  local ty = darkroom.type.array( A.type:peel(), {(r-l+1)*(t-b+1)} )
  return newDAST({kind="slice", expr=A, arrayWidth=arrayWidth, l=l,r=r,t=t,b=b, type = ty } ):setEmptyMetadata()
end

-- reduce : A[n] -> A
-- this is just a special case of function application
function d.reduce( op, expr1, expr2 )
  assert( type(op)=="string" )

  local restype = expr1.type:peel()
  if op=="argmin" then assert( expr1.type:outermostLength() == expr2.type:outermostLength() ) end
  if op=="argmin" then restype = expr2.type:peel() end

  return newDAST({kind="reduce", op=op, expr1=expr1, expr2=expr2, type = restype} ):setEmptyMetadata()
end

-- function argument
function d.input( type )
  assert( darkroom.type.isType( type ) )
  return newDarkroomIR( {kind="input", type = type} )
end

-- function definition
-- output, inputs
function d.fn( name, output, ... )
  assert(type(name)=="string")
  assert( isDAST(output) )
  map( {...}, function(n) assert(isDAST(n)); assert(n.kind=="input") end )
  local t = {output=output, inputs = {...}, name=name }
  return setmetatable( t, dFunctionMT )
end

function d.leaf( fn, outputType, ... )
  assert( darkroom.type.isType(outputType) )
  map( {...}, function(n) assert(isDAST(n)) end )
  return setmetatable( {kind="terra", fn=fn, output={type=outputType},inputs={...} }, dFunctionMT )
end

function d.range( v, ty )
  assert(type(v)=="number")
  assert( darkroom.type.isType(ty) )
  return newDAST( {kind="range", value=v, type=darkroom.type.array(ty,{v})} ):setEmptyMetadata()
end

function d.apply( fn, ... )
  assert(isDFn(fn))
  for k,v in ipairs({...}) do if v.type~=fn.inputs[k].type then print("Apply type error. formal=",fn.inputs[k].type,"actual=",v.type); assert(false) end end
  local t = {kind="apply", fn=fn, type = fn.output.type}
  for k,v in ipairs({...}) do t["input"..k] = v end
  return newDAST( t ):setEmptyMetadata()
end

local __compileCache = {}
function d.compile( fn )
  assert(isDFn(fn))

  if __compileCache[fn]==nil then
    if fn.kind=="terra" then
      __compileCache[fn] = fn.fn
    else
      assert( isDAST(fn.output) )

      local stats = {}
      local inputSymbols = map( fn.inputs, function(n) return symbol( &n.type:toTerraType() ) end )

      local out = fn.output:visitEach(
        function(n, inputs)
          local out = symbol( &n.type:toTerraType(), n:name().."_out" )
          table.insert(stats, quote var [out] = [&n.type:toTerraType()](cstdlib.malloc(sizeof([n.type:toTerraType()]))) 
                         defer cstdlib.free(out)
        end)

          if true then table.insert( stats, quote cstdio.printf([n:name().."\n"]) end ) end
          if n.kind=="map" then
            local orderedInputs = n:map( "input", function(_,i) return inputs["input"..i] end )
            local f = d.compile(n.fn)
            local N = n.type:outermostLength()
            table.insert( stats, quote
              for i=0,N do 
                f( &((@out)[i]), [ map( orderedInputs, function(v) return `&((@v)[i]) end )] )
              end
          end)

            return out
          elseif n.kind=="input" then
            local inpinv = invertTable( fn.inputs )
            local i = inpinv[n]
            assert(type(i)=="number")
            return inputSymbols[i]
          elseif n.kind=="extractStencils" then

            local N = n.type:outermostLength()
            local stencilW = -n.stencilWidth+1
            table.insert( stats, quote
                for i=0,N do
                  for y=n.stencilHeight,1 do
                    for x=n.stencilWidth,1 do
                      (@out)[i][(y-n.stencilHeight)*stencilW+(x-n.stencilWidth)] = (@[inputs.expr])[i+x+y*n.arrayWidth]
                    end
                  end
                end
              end)

            return out
          elseif n.kind=="range" then
            table.insert( stats, quote
                            for i=0,n.value do
                              (@out)[i] = i
                            end
                            end )
            return out
          elseif n.kind=="reduce" then

            if n.op=="sum" then
              table.insert(stats, quote
                             @out = 0
                             for i=0,[n.expr1.type:outermostLength()] do @out = @out + (@[inputs.expr1])[i] end
                end )
              return out
            elseif n.op=="argmin" then
              table.insert( stats, quote
                              var set = false
                              var resV : n.expr1.type:peel():toTerraType() = 0
                              for i=0,[n.expr1.type:outermostLength()] do 
                                if set==false or (@[inputs.expr1])[i] < resV then
                                  resV = (@[inputs.expr1])[i]
                                  @out = (@[inputs.expr2])[i]
                                  set = true
                                end
                              end
                              end)
                return out
            else
              assert(false)
            end
          elseif n.kind=="apply" then
            local f = d.compile( n.fn )
            local orderedInputs = n:map( "input", function(_,i) return inputs["input"..i] end )
            table.insert( stats, quote f(out,[orderedInputs]) end )
            return out
          elseif n.kind=="slice" then
            table.insert( stats, quote
                            var i = 0
              for y = n.b, n.t+1 do
                for x = n.l, n.r+1 do
                  (@out)[i] = (@[inputs.expr])[y*n.arrayWidth+x] 
            i = i + 1
                end
              end
              end)

            return out
          elseif n.kind=="dup" then
            table.insert( stats, quote
                            for i=0,n.n do (@out)[i] = @[inputs.expr] end
              end)
            return out
          else
            print(n.kind)
            assert(false)
          end
        end)

      local finout = symbol( &fn.output.type:toTerraType() )
      local res = terra( [finout],[inputSymbols] )
--        cstdio.printf([fn.name.."\n"])
        [stats]
        cstring.memcpy( finout, out, sizeof([fn.output.type:toTerraType()]) )
      end
      
      print("Kernel", fn.name)
      res:printpretty()

      return res
    end
  end

  return __compileCache[fn]
end
------------------------

-- extracts stencils of size (stencilWidth x stencilHeight) from 0 ... down to -stencilCount
function d.extractStencilArray( name, A, arrayWidth, stencilWidth, stencilHeight, stencilCount)
  assert( type(name) == "string" )
  assert(type(arrayWidth)=="number")
  assert(type(stencilWidth)=="number")
  assert( stencilWidth < 0)
  assert(type(stencilHeight)=="number")
  assert( stencilHeight < 0)
  assert(type(stencilCount)=="number")
  assert(stencilCount>0)
  local largeStencilWidth = stencilWidth-stencilCount+1
  local s1 = d.extractStencils( name.."_ext", A, arrayWidth, largeStencilWidth, stencilHeight )
  
  ------------
  local subinput = d.input( s1.type:peel() )
  local stencils = d.extractStencils( name.."_ext2", subinput, largeStencilWidth, stencilWidth, stencilHeight )
  local slice = d.slice( stencils, -largeStencilWidth, -stencilWidth-1, -stencilWidth-1+stencilCount-1, -stencilHeight-1, -stencilHeight-1)
  local substencils = d.fn( name.."_fn", slice, subinput )
  -----------

  local fin = d.map( name.."_map", substencils, s1 )
  return fin
end

return d