local IR = require("ir")
local types = require("types")
--local simmodules = require("simmodules")
--local cstdio = terralib.includec("stdio.h")
local ffi = require("ffi")
local S = require("systolic")
local Ssugar = require("systolicsugar")
local SDFRate = require "sdfrate"

-- We can operate in 2 different modes: either we stream frames continuously (STREAMING==true), or we only do one frame (STREAMING==false). 
-- If STREAMING==false, we artificially cap the output once the expected number of pixels is reached. This is needed for some test harnesses
STREAMING = false

darkroom = {}

DEFAULT_FIFO_SIZE = 2048*16*16

if os.getenv("v") then
  DARKROOM_VERBOSE = true
else
  DARKROOM_VERBOSE = false
end

local function getloc()
  return debug.getinfo(3).source..":"..debug.getinfo(3).currentline.."\n"..debug.traceback()
end


darkroom.VToken = types.opaque("V")
darkroom.RVToken = types.opaque("RV")
darkroom.HandshakeToken = types.opaque("handshake")
function darkroom.V(A) assert(types.isType(A)); assert(darkroom.isBasic(A)); return types.tuple{A, darkroom.VToken} end
function darkroom.RV(A) assert(types.isType(A)); assert(darkroom.isBasic(A)); return types.tuple{A, darkroom.RVToken} end
function darkroom.Handshake(A) assert(types.isType(A)); assert(darkroom.isBasic(A)); return types.tuple({ A, darkroom.HandshakeToken }) end
function darkroom.HandshakeArray(A,N) assert(types.isType(A)); assert(darkroom.isBasic(A)); return types.tuple({A,types.opaque("HandshakeArray"..N)}) end
function darkroom.HandshakeTmuxed(A,N) assert(types.isType(A)); assert(darkroom.isBasic(A)); return types.tuple({A,types.opaque("HandshakeTmuxed"..N)}) end
function darkroom.Sparse(A,W,H) return types.array2d(types.tuple({A,types.bool()}),W,H) end



function darkroom.isHandshakeArray(a) return a:isTuple() and a.list[2].kind=="opaque" and a.list[2].str:sub(1,#"HandshakeArray")=="HandshakeArray" end
function darkroom.isHandshakeTmuxed(a) return a:isTuple() and a.list[2].kind=="opaque" and a.list[2].str:sub(1,#"HandshakeTmuxed")=="HandshakeTmuxed" end
function darkroom.isHandshake( a ) return a:isTuple() and a.list[2]==darkroom.HandshakeToken end
function darkroom.isV( a ) return a:isTuple() and a.list[2]==darkroom.VToken end
function darkroom.isRV( a ) return a:isTuple() and a.list[2]==darkroom.RVToken end
function darkroom.isBasic(A) return darkroom.isV(A)==false and darkroom.isRV(A)==false and darkroom.isHandshake(A)==false and darkroom.isHandshakeArray(A)==false and darkroom.isHandshakeTmuxed(A)==false end
function darkroom.expectBasic( A ) err( darkroom.isBasic(A), "type should be basic but is "..tostring(A) ) end
function darkroom.expectV( A, er ) if darkroom.isV(A)==false then error(er or "type should be V but is "..tostring(A)) end end
function darkroom.expectRV( A, er ) if darkroom.isRV(A)==false then error(er or "type should be RV") end end
function darkroom.expectHandshake( A, er ) if darkroom.isHandshake(A)==false then error(er or "type should be handshake") end end


-- extract takes the darkroom, and returns the type that should be used by the terra/systolic process function
-- ie V(A) => {A,bool}
-- RV(A) => {A,bool}
-- Handshake(A) => {A,bool}
function darkroom.lower( a, loc )
  assert(types.isType(a))
  if darkroom.isHandshake(a) or darkroom.isHandshakeArray(a) then
    return types.tuple({a.list[1],types.bool()})
  elseif darkroom.isHandshakeTmuxed(a) then
    return types.tuple{a.list[1],types.uint(8)}
  elseif darkroom.isRV(a) or darkroom.isV(a) then 
    return types.tuple{a.list[1],types.bool()}
  elseif a:isArray() and darkroom.isBasic(a:arrayOver())==false then
    return types.array2d( darkroom.lower(a:arrayOver()), (a:arrayLength())[1], (a:arrayLength())[2] )
  elseif a:isTuple() and darkroom.isBasic(a.list[1])==false then
    return types.tuple(map(a.list, function(t) return darkroom.lower(t) end ))
  elseif darkroom.isBasic(a) then 
    return a 
  end
  assert(false)
end

-- extract underlying actual data type.
-- V(A) => A
-- RV(A) => A
-- Handshake(A) => A
function darkroom.extractData(a)
  if darkroom.isHandshake(a) then return a.list[1]
  elseif darkroom.isV(a) then return a.list[1]
  elseif darkroom.isRV(a) then return a.list[1]
  end
  return a -- pure
end

function darkroom.hasReady(a)
  if darkroom.isHandshake(a) then return true
  elseif darkroom.isRV(a) then return true
  elseif a:isTuple() and darkroom.isHandshake(a.list[1]) then
    return true
  elseif darkroom.isHandshakeArray(a) then
    return true
  elseif darkroom.isBasic(a) or darkroom.isV(a) then
    return false
  else
    print("UNKNOWN READY",a)
    assert(false)
  end
end

function darkroom.extractReady(a)
  if darkroom.isHandshake(a) then return types.bool()
  elseif darkroom.isV(a) then return types.bool()
  elseif darkroom.isRV(a) then return types.bool()
  elseif a:isTuple() and darkroom.isHandshake(a.list[1]) then
    map(a.list,function(i) assert(darkroom.isHandshake(i)); end )
    return types.array2d(types.bool(),#a.list) -- we always use arrays for ready bits. no reason not to.
  elseif darkroom.isHandshakeArray(a) then
    return types.uint(8)
  else 
    print("COULD NOT EXTRACT READY",a)
    assert(false) 
  end
end

function darkroom.extractValid(a)
  if darkroom.isHandshakeTmuxed(a) then
    return types.uint(8)
  end
  return types.bool()
end

--[=[
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
   --]=]

darkroomFunctionFunctions = {}
darkroomFunctionMT={__index=darkroomFunctionFunctions}

-- takes SDF input rate I and returns output rate after I is processed by this function
-- I is the format: {{A_sdfrate,B_sdfrate},{A_converged,B_converged}}
function darkroomFunctionFunctions:sdfTransfer( I, loc )
  assert(type(I)=="table")
  assert( SDFRate.isSDFRate(I[1]) )
  assert(type(I[2][1])=="boolean")
  assert( type(loc)=="string" )

  -- a few things can happen here:
  -- (1) inputs are converged, but ratio is inconsistant. Return unconverged
  -- (2) ratio is consistant, but some inputs are unconverged. Return unconverged.

  err( SDFRate.isSDFRate(self.sdfInput), "Missing SDF rate for fn "..self.kind)
  err( SDFRate.isSDFRate(self.sdfOutput), "Missing SDF output rate for fn "..self.kind)

  -- if we're going from N->N, we don't know how stuff maps so we can't do it automatically
  err( #self.sdfInput==1 or #self.sdfOutput==1, "sdf rate with no default behavior "..loc )

  local allConverged, consistantRatio = true, true

  local Isdf, Iconverged = I[1], I[2]

  err( #self.sdfInput == #Isdf, "# of SDF streams doesn't match. Was "..(#Isdf).." but expected "..(#self.sdfInput)..", "..loc )

  local R
  for i=1,#self.sdfInput do
    if self.sdfInput[i]=="x" then
      -- don't care
    else
      local thisR = { Isdf[i][1]*self.sdfInput[i][2], Isdf[i][2]*self.sdfInput[i][1] } -- I/self.sdfInput ratio
      thisR[1],thisR[2] = simplify(thisR[1],thisR[2])
      if R==nil then R=thisR end
      consistantRatio = consistantRatio and (R[1]==thisR[1] and R[2]==thisR[2])

      assert(type(Iconverged[i])=="boolean")
      allConverged = allConverged and Iconverged[i]
    end
  end

  local res, resConverged = {},{}
  for i=1,#self.sdfOutput do
    local On, Od = simplify(self.sdfOutput[i][1]*R[1], self.sdfOutput[i][2]*R[2])

    table.insert( res, {On,Od} )
    table.insert( resConverged, allConverged and consistantRatio )
  end

  assert(#res==#resConverged)
  assert( SDFRate.isSDFRate(res) )
  map( resConverged, function(n) assert(type(n)=="boolean") end )

  return { res, resConverged }
end

function darkroomFunctionFunctions:compile() return self.terraModule end
function darkroomFunctionFunctions:toVerilog() return self.systolicModule:getDependencies()..self.systolicModule:toVerilog() end

function darkroom.newFunction(tab)
  assert( type(tab) == "table" )

  assert( SDFRate.isSDFRate(tab.sdfInput) )
  assert( SDFRate.isSDFRate(tab.sdfOutput) )
  assert( tab.sdfInput[1][1]/tab.sdfInput[1][2]<=1 )
  assert( tab.sdfOutput[1][1]/tab.sdfOutput[1][2]<=1 )

  return setmetatable( tab, darkroomFunctionMT )
end

darkroomIRFunctions = {}
setmetatable( darkroomIRFunctions,{__index=IR.IRFunctions})
darkroomIRMT = {__index = darkroomIRFunctions }
darkroomInstanceMT = {}

function darkroom.isInstance(t) return getmetatable(t)==darkroomInstanceMT end
function darkroom.newIR(tab)
  assert( type(tab) == "table" )
  IR.new( tab )
  return setmetatable( tab, darkroomIRMT )
end

local __sdfTotalCache = {}
-- assume that inputs have SDF rate {1,1}, then what is the rate of this node?
function darkroomIRFunctions:sdfTotalInner( registeredInputRates )
  assert( type(registeredInputRates)=="table" )

  local res = self:visitEach( 
    function( n, args )
      local res
      if n.kind=="input" or n.kind=="constant" then
        local rate = {{1,1}}
        if n.kind=="input" and n.sdfRate~=nil then 
          err( SDFRate.isSDFRate(n.sdfRate),"sdf rate not an sdf rate? "..n.kind..n.loc)
          rate=n.sdfRate; 
        end
        res = {rate,broadcast(true,#rate)}
      elseif n.kind=="extractState" then
        res = args[1]
      elseif n.kind=="applyMethod" then
        if n.fnname=="load" then
          if registeredInputRates[n.inst]==nil then
            res = {{{1,1}},{false}} -- just give it an arbitrary rate (we have no info at this point)
          else
            res = n.inst.fn:sdfTransfer(registeredInputRates[n.inst], "APPLY LOAD "..n.loc)
          end
        elseif n.fnname=="store" then
          registeredInputRates[n.inst] = args[1]
          -- rate doesn't matter
          assert( SDFRate.isSDFRate(args[1][1]))
          assert(type(args[1][2][1])=="boolean")
          res = {args[1][1],args[1][2]}
        else
          assert(false)
        end
      elseif n.kind=="apply" then
        if #n.inputs==0 then
          assert( SDFRate.isSDFRate(n.fn.sdfOutput))
          res = {n.fn.sdfOutput,broadcast(true,#n.fn.sdfOutput)}
        elseif #n.inputs==1 then
          res =  n.fn:sdfTransfer(args[1], "APPLY "..n.name.." "..n.loc)
          if DARKROOM_VERBOSE then print("APPLY",n.name,"converged=",res[2][1],"RATE",res[1][1][1],res[1][1][2]) end
        else
          assert(false)
        end
      elseif n.kind=="tuple" or n.kind=="array2d" then
        if n.packStreams then
          local IR, allConverged, ratesMatch
          -- all input rates must match!
          for key,i in pairs(n.inputs) do
            assert(#args[key][1]==1)
            local isdf = args[key][1][1]
            local iconverged = args[key][2][1]

            if darkroom.extractData( i.type ):const() then
              -- we don't care about SDF rates on constants
            else
              if IR==nil then IR=isdf; allConverged = iconverged; ratesMatch=true end
              if isdf[1]~=IR[1] or isdf[2]~=IR[2] then
                ratesMatch=false
                print("SDF "..n.kind.." rate mismatch "..n.loc)
              end
            end
          end
          res = {{IR},{allConverged and ratesMatch}}
        else
          res = {{},{}}
          for k,v in ipairs(args) do
            assert( #v[1] == 1 )
            table.insert(res[1], v[1][1])
            table.insert(res[2], v[2][1])
          end
        end
      elseif n.kind=="statements" then
        local allConverged = true
        for _,arg in pairs(args) do
          for k,v in pairs(arg[2]) do 
            assert(type(v)=="boolean"); 
            allConverged=allConverged and v 
          end
        end
        res = { args[1][1], { allConverged } }
      elseif n.kind=="selectStream" then
        assert( #args==1 )
        res = { {args[1][1][n.i+1]}, {args[1][2][n.i+1]} }
      else
        print("sdftotal",n.kind)
        assert(false)
      end

      assert( SDFRate.isSDFRate(res[1]) )
      map( res[2], function(n) assert(type(n)=="boolean") end )

      __sdfTotalCache[n] = res[1]
      return res
    end)

  -- output is format {{sdfRateInput1,...}, {convergedInput1,...} }
  assert(#res[2]==1)
  assert( type(res[2][1])=="boolean")
  return res[2][1]
end

local __sdfConverged = {}
function darkroomIRFunctions:sdfTotal(root)
  assert(darkroom.isIR(root))
  if __sdfConverged[root]==nil then
    local iter, converged = 10, false
    local registeredInputRates = {} -- hold the rate of back edges between iterations
    while iter>=0 and converged==false do
      if DARKROOM_VERBOSE then print("SDF ITER", iter) end
      converged = root:sdfTotalInner( registeredInputRates )
      iter = iter - 1
    end
    err( converged==true, "Error, SDF solve failed to converge. Do you have a feedback loop?" )
    __sdfConverged[root] = converged
  end

  assert( type(__sdfTotalCache[self])=="table" )
  return __sdfTotalCache[self]
end

-- This converts our stupid internal represention into the SDF 'rate' used in the SDF paper
-- i.e. the number you multiply the input/output rate by to make the rates match.
-- Meaning for us: if < 1, then not is underutilized (sits idle). If >1, then node is
-- oversubscribed (will limit speed)
function darkroomIRFunctions:calcSdfRate(root)
  assert(darkroom.isIR(root))

  if self.kind=="apply" then
    assert(#self.inputs<=1)
    local total = self:sdfTotal(root)
    local res = SDFRate.fracMultiply({total[1][1],total[1][2]},{self.fn.sdfOutput[1][2],self.fn.sdfOutput[1][1]})
    if DARKROOM_VERBOSE then print("SDF RATE",self.name,res[1],res[2],"sdfINP",self.fn.sdfInput[1][1],self.fn.sdfInput[1][2],"SDFOUT",self.fn.sdfOutput[1][1],self.fn.sdfOutput[1][2]) end
    return res
  else
    return nil
  end
end

-- assuming that the inputs are running at {1,1}, wht is the lowest/highest SDF utilization in this DAG?
-- (this will limit the speed of the whole pipe)
-- In our implementaiton, the utilization of any node can't be >1, so if the highest utilization is >1, we need to scale the throughput of the whole pipe
local __sdfExtremeRateCache = {}
function darkroomIRFunctions:sdfExtremeRate( highest )
  assert(type(highest)=="boolean")

  __sdfExtremeRateCache[self] = __sdfExtremeRateCache[self] or {}

  if __sdfExtremeRateCache[self][highest]==nil then

    self:visitEach(
      function( n, args )
        local r = n:calcSdfRate(self)
        assert( SDFRate.isFrac(r) or r==nil )
        
        local res 

        if __sdfExtremeRateCache[self][highest]==nil and r~=nil then
          __sdfExtremeRateCache[self][highest] = {r,n.loc}
        elseif highest and r~=nil and SDFRate.fracToNumber(r)>=SDFRate.fracToNumber(__sdfExtremeRateCache[self][highest][1]) then
          __sdfExtremeRateCache[self][highest] = {r,n.loc}
        elseif highest==false and r~=nil and SDFRate.fracToNumber(r)<=SDFRate.fracToNumber(__sdfExtremeRateCache[self][highest][1]) then
          __sdfExtremeRateCache[self][highest] = {r,n.loc}
        end

      end)

    if __sdfExtremeRateCache[self][highest]==nil then
      -- no function calls => no changes to rate. (none of our other operators change rate)
      return {1,1},"NO_APPLIES"
    end
  end


  return __sdfExtremeRateCache[self][highest][1], __sdfExtremeRateCache[self][highest][2]
end

function darkroomIRFunctions:typecheck()
  return self:process(
    function(n)
      if n.kind=="apply" then
        err( n.fn.registered==false or n.fn.registered==nil, "Error, applying registered type! "..n.fn.kind)
        if #n.inputs==0 then
          err( n.fn.inputType==types.null(), "Missing function argument, "..n.loc)
        else
          assert( types.isType( n.inputs[1].type ) )
          err( n.inputs[1].type:constSubtypeOf(n.fn.inputType), "Input type mismatch. Is "..tostring(n.inputs[1].type).." but should be "..tostring(n.fn.inputType)..", "..n.loc)
        end
        n.type = n.fn.outputType
        return darkroom.newIR( n )
      elseif n.kind=="applyMethod" then
        err( n.inst.fn.registered==true, "Error, calling method "..n.fnname.." on a non-registered type! "..n.loc)

        if n.fnname=="load" then
          n.type = n.inst.fn.outputType
        elseif n.fnname=="store" then
          if n.inputs[1].type~=n.inst.fn.inputType then error("input to reg store has incorrect type, should be "..tostring(n.inst.fn.inputType).." but is "..tostring(n.inputs[1].type)..", "..n.loc) end
          n.type = types.null()
        else
          err(false,"Unknown method "..n.fnname)
        end

        return darkroom.newIR( n )
      elseif n.kind=="input" then
      elseif n.kind=="constant" then
      elseif n.kind=="tuple" then
        n.type = types.tuple( map(n.inputs, function(v) return v.type end) )
        return darkroom.newIR(n)
      elseif n.kind=="array2d" then
        map( n.inputs, function(i) err(i.type==n.inputs[1].type, "All inputs to array2d must have same type!") end )
        n.type = types.array2d( n.inputs[1].type, n.W, n.H )
        return darkroom.newIR(n)
      elseif n.kind=="statements" then
        n.type = n.inputs[1].type
        return darkroom.newIR(n)
      elseif n.kind=="selectStream" then
        err(n.inputs[1].type:isArray(), "selectStream input must be array of handshakes, but is "..tostring(n.inputs[1].type) )
        err( darkroom.isHandshake(n.inputs[1].type:arrayOver()), "selectStream input must be array of handshakes")
        err( n.i < n.inputs[1].type:channels(), "selectStream index out of bounds")
        n.type = n.inputs[1].type:arrayOver()
        return darkroom.newIR(n)
      else
        print(n.kind)
        assert(false)
      end
    end)
end

function darkroomIRFunctions:codegenSystolic( module )
  assert(Ssugar.isModuleConstructor(module))
  return self:visitEach(
    function(n, inputs)
      if n.kind=="input" then
        local res = {module:lookupFunction("process"):getInput()}
        if darkroom.isRV(n.type) then res[2] = module:lookupFunction("ready"):getInput() end
        return res
      elseif n.kind=="applyMethod" then
        assert( n.inst.fn.registered )
        local I = module:lookupInstance(n.inst.name)
        if n.fnname=="load" then 
          module:lookupFunction("reset"):addPipeline( I:load_reset(nil,module:lookupFunction("reset"):getValid()) )
          return {I:load(S.tuple{S.null(),S.constant(true,types.bool())})}
        elseif n.fnname=="store" then
          module:lookupFunction("reset"):addPipeline( I:store_reset(nil,module:lookupFunction("reset"):getValid()) )
          return {I:store(inputs[1][1])}
        else
          assert(false)
        end
      elseif n.kind=="apply" then
        err( n.fn.systolicModule~=nil, "Error, missing systolic module for "..n.fn.kind)
        err( n.fn.systolicModule:lookupFunction("process"):getInput().type==darkroom.lower(n.fn.inputType), "Systolic type doesn't match fn type, fn '"..n.fn.kind.."', is "..tostring(n.fn.systolicModule:lookupFunction("process"):getInput().type).." but should be "..tostring(darkroom.lower(n.fn.inputType)) )
        err( n.fn.systolicModule.functions.process.output.type:constSubtypeOf(darkroom.lower(n.fn.outputType)), "Systolic output type doesn't match fn type, fn '"..n.fn.kind.."', is "..tostring(n.fn.systolicModule.functions.process.output.type).." but should be "..tostring(darkroom.lower(n.fn.outputType)) )
        
        local params
        if darkroom.isHandshake( n.fn.inputType ) then
          local IC = n.inputs[1]:sdfTotal(self)
          local OC = n:sdfTotal(self)
          params={INPUT_COUNT="(INPUT_COUNT*"..IC[1][1]..")/"..IC[1][2],OUTPUT_COUNT="(INPUT_COUNT*"..OC[1][1]..")/"..OC[1][2]}
        end
        
        err(type(n.fn.stateful)=="boolean", "Missing stateful annotation "..n.fn.kind)

        local I = module:add( n.fn.systolicModule:instantiate(n.name,nil,nil,nil,params) )
        if darkroom.isHandshake( n.fn.inputType ) or darkroom.isHandshakeArray( n.fn.inputType ) or darkroom.isHandshakeTmuxed( n.fn.inputType ) or darkroom.isHandshake(n.fn.outputType) then
          module:lookupFunction("reset"):addPipeline( I:reset(nil,module:lookupFunction("reset"):getValid()) )
        elseif n.fn.stateful then
          module:lookupFunction("reset"):addPipeline( I:reset() )
        end
                
        if n.fn.inputType==types.null() then
          return { I:process() }
        elseif darkroom.isV(n.inputs[1].type) then
          return { I:process(inputs[1][1]), I:ready() }
        elseif darkroom.isRV(n.inputs[1].type) then
          return { I:process(inputs[1][1]), I:ready(inputs[1][2]) }
        elseif darkroom.isRV(n.type) then
          -- the strange basic->RV case
          err( false, "You shouldn't use Basic->RV directly, loc "..n.loc )
        else
          return {I:process(inputs[1][1])}
        end
      elseif n.kind=="constant" then
        return {S.constant( n.value, n.type )}
      elseif n.kind=="tuple" then
        return {S.tuple( map(inputs,function(i) return i[1] end) ) }
      elseif n.kind=="array2d" then
        local outtype = types.array2d(darkroom.lower(n.type:arrayOver()),n.W,n.H)
        return {S.cast(S.tuple( map(inputs,function(i) return i[1] end) ), outtype) }
      elseif n.kind=="statements" then
        for i=2,#inputs do
          module:lookupFunction("process"):addPipeline( inputs[i][1] )
        end
        return inputs[1]
      elseif n.kind=="selectStream" then
        return {S.index(inputs[1][1],n.i)}
      else
        print(n.kind)
        assert(false)
      end
    end)
end


function darkroom.isFunction(t) return getmetatable(t)==darkroomFunctionMT end
function darkroom.isIR(t) return getmetatable(t)==darkroomIRMT end

-- function argument
function darkroom.input( type, sdfRate )
  err( types.isType( type ), "darkroom.input: first argument should be type" )
  assert( sdfRate==nil or SDFRate.isSDFRate(sdfRate))
  if sdfRate==nil then sdfRate={{1,1}} end
  return darkroom.newIR( {kind="input", type = type, name="input", id={}, inputs={}, sdfRate=sdfRate, loc=getloc()} )
end

--[=[
function callOnEntries( T, fnname )
  local TS = symbol(&T,"self")
  local ssStats = {}
  for k,v in pairs( T.entries ) do if v.type:isstruct() then table.insert( ssStats, quote TS.[v.field]:[fnname]() end) end end
  T.methods[fnname] = terra([TS]) [ssStats] end
end
]=]

function darkroom.instantiateRegistered( name, fn )
  err( type(name)=="string", "name must be string")
  err( darkroom.isFunction(fn), "fn must be function" )
  err( fn.registered, "fn must be registered")
  local t = {name=name, fn=fn}
  return setmetatable(t, darkroomInstanceMT)
end

function darkroom.apply( name, fn, input )
  err( type(name) == "string", "first argument to apply must be name" )
  err( darkroom.isFunction(fn), "second argument to apply must be a darkroom function" )
  err( input==nil or darkroom.isIR( input ), "last argument to apply must be darkroom value or nil" )

  return darkroom.newIR( {kind = "apply", name = name, loc=getloc(), fn = fn, inputs = {input} } )
end

function darkroom.applyMethod( name, inst, fnname, input )
  err( type(name)=="string", "name must be string")
  assert( darkroom.isInstance(inst) )
  err( type(fnname)=="string", "fnname must be string")
  assert( input==nil or darkroom.isIR( input ) )

  return darkroom.newIR( {kind = "applyMethod", name = name, fnname=fnname, loc=getloc(), inst = inst, inputs = {input} } )
end

function darkroom.constant( name, value, ty )
  err( type(name) == "string", "constant name must be string" )
  err( types.isType(ty), "constant type must be rigel type" )
  ty:checkLuaValue(value)

  return darkroom.newIR( {kind="constant", name=name, value=value, type=ty, inputs = {}} )
end

-- packStreams: do we consider the output of this to be 1 SDF stream, or N?
function darkroom.tuple( name, t, packStreams )
  err( type(name)=="string", "first tuple input should be name")
  err( type(t)=="table", "tuple input should be table of darkroom values" )
  if packStreams==nil then packStreams=true end

  local r = {kind="tuple", name=name, loc=getloc(), inputs={}, packStreams = packStreams}
  map(t, function(n,k) err(darkroom.isIR(n),"tuple input is not a darkroom value"); table.insert(r.inputs,n) end)
  return darkroom.newIR( r )
end

-- packStreams: do we consider the output of this to be 1 SDF stream, or N?
function darkroom.array2d( name, t, W, H, packStreams )
  err( type(t)=="table", "array2d input should be table of darkroom values" )
  if packStreams==nil then packStreams=true end

  err( type(W)=="number", "W must be number")
  if H==nil then H=1 end
  err( type(H)=="number", "H must be number")

  local r = {kind="array2d", name=name, loc=getloc(), inputs={}, W=W,H=H, packStreams=packStreams}
  map(t, function(n,k) assert(darkroom.isIR(n)); table.insert(r.inputs,n) end)
  return darkroom.newIR( r )
end

function darkroom.selectStream( name, input, i, X )
  err( type(i)=="number", "i must be number")
  err( darkroom.isIR(input), "input must be IR")
  assert(X==nil)
  return darkroom.newIR({kind="selectStream", name=name, i=i, loc=getloc(), inputs={input}})
end

function darkroom.statements( t )
  assert( type(t)=="table" )
  assert(#t>0 and keycount(t)==#t)
  map(t, function(i) assert(darkroom.isIR(i)) end )
  return darkroom.newIR{kind="statements",inputs=t,loc=getloc()}
end



return darkroom