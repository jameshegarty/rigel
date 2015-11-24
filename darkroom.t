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

struct EmptyState {}
terra EmptyState:init() end

darkroom.data = macro(function(i) return `i._0 end)
local data = darkroom.data
darkroom.valid = macro(function(i) return `i._1 end)
local valid = darkroom.valid
darkroom.ready = macro(function(i) return `i._2 end)
local ready = darkroom.ready


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

-- t should be format {{number,number},{number,number},...}
function darkroom.isSDFRate(t)
  if type(t)~="table" then return false end
  if keycount(t)~=#t then return false end
  for _,v in pairs(t) do
    if v=="x" then
      -- ok
    else
      if type(v)~="table" then return false end
      if (type(v[1])~="number" or type(v[2])~="number") then return false end
    end
  end
  return true
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

-- takes SDF input rate I and returns output rate after I is processed by this function
-- I is the format: {{A_sdfrate,B_sdfrate},{A_converged,B_converged}}
function darkroomFunctionFunctions:sdfTransfer( I, loc )
  assert(type(I)=="table")
  assert( darkroom.isSDFRate(I[1]) )
  assert(type(I[2][1])=="boolean")
  assert( type(loc)=="string" )

  -- a few things can happen here:
  -- (1) inputs are converged, but ratio is inconsistant. Return unconverged
  -- (2) ratio is consistant, but some inputs are unconverged. Return unconverged.

  err( darkroom.isSDFRate(self.sdfInput), "Missing SDF rate for fn "..self.kind)
  err( darkroom.isSDFRate(self.sdfOutput), "Missing SDF output rate for fn "..self.kind)

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
      --    if consistantRatio==false then  print("RATIO",R[1],R[2],thisR[1],thisR[2])   end
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
  assert( darkroom.isSDFRate(res) )
  map( resConverged, function(n) assert(type(n)=="boolean") end )

  return { res, resConverged }
end

function darkroomFunctionFunctions:compile() return self.terraModule end
function darkroomFunctionFunctions:toVerilog() return self.systolicModule:getDependencies()..self.systolicModule:toVerilog() end

function darkroom.newFunction(tab)
  assert( type(tab) == "table" )

  assert(darkroom.isSDFRate(tab.sdfInput))
  assert(darkroom.isSDFRate(tab.sdfOutput))
  assert(tab.sdfInput[1][1]/tab.sdfInput[1][2]<=1)
  assert(tab.sdfOutput[1][1]/tab.sdfOutput[1][2]<=1)

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
          err(darkroom.isSDFRate(n.sdfRate),"sdf rate not an sdf rate? "..n.kind..n.loc)
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
          assert(darkroom.isSDFRate(args[1][1]))
          assert(type(args[1][2][1])=="boolean")
          res = {args[1][1],args[1][2]}
        else
          assert(false)
        end
      elseif n.kind=="apply" then
        if #n.inputs==0 then
          assert(darkroom.isSDFRate(n.fn.sdfOutput))
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

      assert( darkroom.isSDFRate(res[1]) )
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
    local res = fracMultiply({total[1][1],total[1][2]},{self.fn.sdfOutput[1][2],self.fn.sdfOutput[1][1]})
    if DARKROOM_VERBOSE then print("SDF RATE",self.name,res[1],res[2],"sdfINP",self.fn.sdfInput[1][1],self.fn.sdfInput[1][2],"SDFOUT",self.fn.sdfOutput[1][1],self.fn.sdfOutput[1][2]) end
    return res
  else
    --print("sdfUtilization",self.kind)
    --assert(false)
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
        assert(isFrac(r) or r==nil)
        
        local res 
--        for _,v in pairs(args) do
--          if v~=nil then
        if __sdfExtremeRateCache[self][highest]==nil and r~=nil then
          __sdfExtremeRateCache[self][highest] = {r,n.loc}
        elseif highest and r~=nil and fracToNumber(r)>=fracToNumber(__sdfExtremeRateCache[self][highest][1]) then
          __sdfExtremeRateCache[self][highest] = {r,n.loc}
        elseif highest==false and r~=nil and fracToNumber(r)<=fracToNumber(__sdfExtremeRateCache[self][highest][1]) then
          __sdfExtremeRateCache[self][highest] = {r,n.loc}
        end
--              res = v
--            end
--          end
--        end
--        if res==nil and r~=nil then res = {r,n.loc} end -- no inputs

--        assert(res==nil or isFrac(res[1]))
--        assert(res==nil or type(res[2])=="string")
--        return res
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
  assert(systolic.isModuleConstructor(module))
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

-- This converts SoA to AoS
-- ie {Arr2d(a,W,H),Arr2d(b,W,H),...} to Arr2d({a,b,c},W,H)
-- if asArray==true then converts {Arr2d(a,W,H),Arr2d(b,W,H),...} to Arr2d(a[N],W,H). This requires a,b,c be the same...
function darkroom.SoAtoAoS( W, H, typelist, asArray )
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(typelist)=="table")
  if asArray==nil then asArray=false end

  local res = { kind="SoAtoAoS", W=W, H=H, asArray = asArray }

  res.inputType = types.tuple( map(typelist, function(t) return types.array2d(t,W,H) end) )
  if asArray then
    map( typelist, function(n) err(n==typelist[1], "if asArray==true, all elements in typelist must match") end )
    res.outputType = types.array2d(types.array2d(typelist[1],#typelist),W,H)
  else
    res.outputType = types.array2d(types.tuple(typelist),W,H)
  end

  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 0
  res.stateful=false

  local struct PackTupleArrays { }
  terra PackTupleArrays:reset() end

  terra PackTupleArrays:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    for c = 0, [W*H] do
      escape
      if asArray then
        emit quote (@out)[c] = array( [map(range(0,#typelist-1), function(i) return `(inp.["_"..i])[c] end ) ] ) end
      else
        --        emit quote (@out)[c] = { [map(range(0,#typelist-1), function(i) return `(inp.["_"..i])[c] end ) ] } end
        -- terra doesn't like us copying large structs by value
        map(typelist, function(t,k) emit quote cstring.memcpy( &(@out)[c].["_"..(k-1)], &(inp.["_"..(k-1)])[c], [t:sizeof()]) end end )
      end
      end
    end
  end
  res.terraModule = PackTupleArrays

  res.systolicModule = S.moduleConstructor("packTupleArrays_"..(tostring(typelist):gsub('%W','_')))
  local sinp = S.parameter("process_input", res.inputType )
  local arrList = {}
  for y=0,H-1 do
    for x=0,W-1 do
      table.insert( arrList, S.tuple(map(range(0,#typelist-1), function(i) return S.index(S.index(sinp,i),x,y) end)) )
    end
  end
  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast(S.tuple(arrList),darkroom.lower(res.outputType)), "process_output",nil,nil,S.CE("process_CE")) )
  --res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro") )

  return darkroom.newFunction(res)
end

-- Converst {Handshake(a), Handshake(b)...} to Handshake{a,b}
-- typelist should be a table of pure types
-- WARNING: ready depends on ValidIn
function darkroom.packTuple( typelist, X )
  assert(type(typelist)=="table")
  assert(X==nil)
  
  local res = {kind="packTuple"}
  
  map(typelist, function(t) darkroom.expectBasic(t) end )
  res.inputType = types.tuple( map(typelist, function(t) return darkroom.Handshake(t) end) )
  res.outputType = darkroom.Handshake( types.tuple(typelist) )
  res.stateful = false
  res.sdfOutput = {{1,1}}
  res.sdfInput = map(typelist, function(n) if n:const() then return "x" else return {1,1} end end)
    
  res.delay = 0
  local struct PackTuple { ready:bool[#typelist], readyDownstream:bool, outputCount:uint32}
    
  terra PackTuple:stats(name:&int8) self.outputCount=0 end
  
  -- ignore the valid bit on const stuff: it is always considered valid
  local activePorts = {}
  for k,v in ipairs(typelist) do if v:const()==false then table.insert(activePorts, k) end end
    
  -- the simulator doesn't have true bidirectional dataflow, so fake it with a FIFO
  map( activePorts, function(k) table.insert(PackTuple.entries,{field="FIFO"..k, type=simmodules.fifo( typelist[k]:toTerraType(), 8, "PackTuple"..k)}) end )
  terra PackTuple:reset() [map(activePorts, function(i) return quote self.["FIFO"..i]:reset() end end)] end
  terra PackTuple:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    [map(activePorts, function(i) return quote 
             if valid(inp.["_"..(i-1)]) and self.ready[i-1] then 
               self.["FIFO"..i]:pushBack(&data(inp.["_"..(i-1)])) 
             end 
                      end end )]

    if self.readyDownstream then
        var hasData = [foldt(map(activePorts, function(i) return `self.["FIFO"..i]:hasData() end ), andopterra, true )]

        escape if DARKROOM_VERBOSE then map( typelist, function(t,k) 
                      if t:const() then emit quote cstdio.printf("PackTuple FIFO %d valid:%d (const)\n",k-1,1) end 
               else emit quote cstdio.printf("PackTuple FIFO %d valid:%d (size %d)\n", k-1, self.["FIFO"..k]:hasData(),self.["FIFO"..k]:size()) end end end) end end

        --var hasData = [foldt(map(activePorts, function(i) return `valid(inp.["_"..(i-1)]) end ), andopterra, true )]
        if hasData then
--          data(out) = { [map( typelist, function(t,k) if t:const() then print("CONST",k);return `data(inp.["_"..(k-1)]) else return `@(self.["FIFO"..k]:popFront()) end end ) ] }
--          data(out) = { [map( typelist, function(t,k) return `data(inp.["_"..(k-1)]) end ) ] }
          -- terra doesn't like us copying large structs by value
          escape map( typelist, function(t,k) 
                        if t:const() then emit quote cstring.memcpy( &data(out).["_"..(k-1)], &data(inp.["_"..(k-1)]), [t:sizeof()] ) end 
        else emit quote cstring.memcpy( &data(out).["_"..(k-1)], self.["FIFO"..k]:popFront(), [t:sizeof()] ) end end
        end ) end
          valid(out) = true
          
          self.outputCount = self.outputCount+1
          if DARKROOM_VERBOSE then cstdio.printf("PackTuple Handshake Output Count:%d\n",self.outputCount) end
        else
          if DARKROOM_VERBOSE then cstdio.printf("PackTuple Handshake INVALID_OUTPUT Output Count:%d\n",self.outputCount) end
          valid(out) = false
        end
      else
        if DARKROOM_VERBOSE then cstdio.printf("PackTuple Handshake NOT READY DOWNSTREAM Output Count:%d\n",self.outputCount) end
      end
  end
  terra PackTuple:calculateReady(readyDownstream:bool) 
      self.readyDownstream = readyDownstream; 

      escape
        for i=1,#typelist do 
          if typelist[i]:const() then
            emit quote self.ready[i-1] = true end 
          else
            emit quote self.ready[i-1] = (self.["FIFO"..i]:full()==false) end 
          end
        end
      end
  end

  res.terraModule = PackTuple

  res.systolicModule = S.moduleConstructor("packTuple_"..tostring(typelist))
  local CE
  local sinp = S.parameter("process_input", darkroom.lower(res.inputType) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro",nil,nil,CE) )

  res.systolicModule:onlyWire(true)

  local printStr = "IV ["..table.concat(broadcast("%d",#typelist),",").."] OV %d ready ["..table.concat(broadcast("%d",#typelist),",").."] readyDownstream %d"
  local printInst 
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple(broadcast(types.bool(),(#typelist)*2+2)), printStr):instantiate("printInst") ) end
  
  local activePorts={}
  for k,v in pairs(typelist) do if v:const()==false then table.insert(activePorts,k) end end

  if #activePorts>1 then
    print("WARNING: NYI - packTuple with multiple active ports! This needs a fifo along all but one of the edges")
  end
    
  local outv = S.tuple(map(range(0,#typelist-1), function(i) return S.index(S.index(sinp,i),0) end))

  -- valid bit is the AND of all the inputs
  --local valid = foldt(map(range(0,#typelist-1),function(i) return S.index(S.index(sinp,i),1) end),function(a,b) return S.__and(a,b) end,"X")
  local validInList = map(activePorts,function(i) return S.index(S.index(sinp,i-1),1) end)
  local validInFullList = map(typelist,function(i,k) return S.index(S.index(sinp,k-1),1) end)
  local validOut = foldt(validInList,function(a,b) return S.__and(a,b) end,"X")
  --local valid = S.index(S.index(sinp,activePorts[1]-1),1)
  
  local pipelines={}
  
  local downstreamReady = S.parameter("ready_downstream", types.bool())
  
  -- we only want this module to be ready if _all_ streams have data.
  -- WARNING: this makes ready depend on ValidIn
  local readyOutList = {}
  for i=1,#typelist do
    if typelist[i]:const() then
      table.insert( readyOutList, S.constant(true, types.bool()) )
    else
      -- if this stream doesn't have data, let it run regardless.
      local valid_i = S.index(S.index(sinp,i-1),1)
      table.insert( readyOutList, S.__or(S.__and( downstreamReady, validOut), S.__not(valid_i) ) )
    end
  end
  
  local readyOut = S.tuple(readyOutList)
  
  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple(concat(concat(validInFullList,{validOut}),concat(readyOutList,{downstreamReady})))) ) end
  
  local out = S.tuple{outv, validOut}
  res.systolicModule:addFunction( S.lambda("process", sinp, out, "process_output", pipelines) )
  
  res.systolicModule:addFunction( S.lambda("ready", downstreamReady, readyOut, "ready" ) )
  
  return darkroom.newFunction(res)
end

-- takes {Handshake(a[W,H]), Handshake(b[W,H]),...} to Handshake( {a,b}[W,H] )
-- typelist should be a table of pure types
darkroom.SoAtoAoSHandshake = memoize(function( W, H, typelist, X )
  assert(X==nil)
  local f = darkroom.SoAtoAoS(W,H,typelist)
  f = darkroom.makeHandshake(f)
  
  return darkroom.compose("SoAtoAoSHandshake_W"..tostring(W).."_H"..tostring(H).."_"..(tostring(typelist):gsub('%W','_')), f, darkroom.packTuple( map(typelist, function(t) return types.array2d(t,W,H) end) ) ) 
                                     end)

-- Takes A[W,H] to A[W,H], but with a border around the edges determined by L,R,B,T
function darkroom.border(A,W,H,L,R,B,T,value)
  map({W,H,L,R,T,B,value},function(n) assert(type(n)=="number") end)
  local res = {kind="border",L=L,R=R,T=T,B=B,value=value}
  res.inputType = types.array2d(A,W,H)
  res.outputType = res.inputType
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
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

darkroom.liftBasic = memoize(function(f)
  err(darkroom.isFunction(f),"liftBasic argument should be darkroom function")
  local res = {kind="liftBasic", fn = f}
  darkroom.expectBasic(f.inputType)
  darkroom.expectBasic(f.outputType)
  res.inputType = f.inputType
  res.outputType = darkroom.V(f.outputType)
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = f.delay
  res.stateful = f.stateful
  local struct LiftBasic { inner : f.terraModule}
  terra LiftBasic:reset() self.inner:reset() end
  terra LiftBasic:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    self.inner:process(inp,&data(out))
    valid(out) = true
  end
  res.terraModule = LiftBasic
  res.systolicModule = S.moduleConstructor("LiftBasic_"..f.systolicModule.name)
  local inner = res.systolicModule:add( f.systolicModule:instantiate("LiftBasic_inner") )
  local sinp = S.parameter("process_input", darkroom.lower(res.inputType) )
  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ inner:process(sinp), S.constant(true, types.bool())}, "process_output", nil, nil, CE ) )
  if f.stateful then res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {},S.parameter("reset",types.bool()),CE) ) end
  res.systolicModule:complete()
  return darkroom.newFunction(res)
                             end)

local function passthroughSystolic( res, systolicModule, inner, passthroughFns, onlyWire )
  assert(type(passthroughFns)=="table")

  for _,fnname in pairs(passthroughFns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    res:addFunction( S.lambda(fnname, srcFn:getInput(), inner[fnname]( inner, srcFn:getInput() ), srcFn:getOutputName(), nil, sel(onlyWire,nil,srcFn:getValid()), srcFn:getCE() ) )

    local readySrcFn = systolicModule:lookupFunction(fnname.."_ready")
    if readySrcFn~=nil then
      res:addFunction( S.lambda(fnname.."_ready", readySrcFn:getInput(), inner[fnname.."_ready"]( inner, readySrcFn:getInput() ), readySrcFn:getOutputName(), nil, readySrcFn:getValid(), readySrcFn:getCE() ) )
    end

    local resetSrcFn = systolicModule:lookupFunction(fnname.."_reset")
    if resetSrcFn~=nil then
      res:addFunction( S.lambda(fnname.."_reset", resetSrcFn:getInput(), inner[fnname.."_reset"]( inner, resetSrcFn:getInput() ), resetSrcFn:getOutputName(), nil, resetSrcFn:getValid(), resetSrcFn:getCE() ) )
    end

  end
end

-- This takes a basic->R to V->RV
-- Compare to waitOnInput below: runIffReady is used when we want to take control of the ready bit purely for performance reasons, but don't want to amplify or decimate data.
local function runIffReadySystolic( systolicModule, fns, passthroughFns )
  local res = S.moduleConstructor("RunIffReady_"..systolicModule.name)
  local inner = res:add( systolicModule:instantiate("RunIffReady") )

  for _,fnname in pairs(fns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    err( systolicModule:getDelay(prefix.."ready")==0, "ready bit should not be pipelined")

    local sinp = S.parameter(fnname.."_input", darkroom.lower(darkroom.V(srcFn:getInput().type)) )

    local svalid = S.parameter(fnname.."_valid", types.bool())
    local runable = S.__and(inner[prefix.."ready"](inner), S.index(sinp,1) ):disablePipelining()

    local out = inner[fnname]( inner, S.index(sinp,0), runable )

    local RST = S.parameter(prefix.."reset",types.bool())
    if systolicModule:lookupFunction(prefix.."reset"):isPure() then RST=S.constant(false,types.bool()) end

    local pipelines = {}

    local CE = S.CE("CE")
    res:addFunction( S.lambda(fnname, sinp, S.tuple{ out, S.__and( runable,svalid ):disablePipelining() }, fnname.."_output", pipelines, svalid, CE ) )
    res:addFunction( S.lambda(prefix.."reset", S.parameter(prefix.."r",types.null()), inner[prefix.."reset"](inner), "ro", {}, RST, CE) )
    res:addFunction( S.lambda(prefix.."ready", S.parameter(prefix.."readyinp",types.null()), inner[prefix.."ready"](inner), prefix.."ready", {} ) )
  end

  passthroughSystolic( res, systolicModule, inner, passthroughFns )
  return res
end

local function waitOnInputSystolic( systolicModule, fns, passthroughFns )
  local res = S.moduleConstructor("WaitOnInput_"..systolicModule.name)
  local inner = res:add( systolicModule:instantiate("WaitOnInput_inner") )

  for _,fnname in pairs(fns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    err( systolicModule:getDelay(prefix.."ready")==0, "ready bit should not be pipelined")

    local asstInst = res:add( S.module.assert( "waitOnInput valid bit doesn't match ready bit", true ):instantiate("asstInst") )
    local printInst
    if DARKROOM_VERBOSE then printInst = res:add( S.module.print( types.tuple{types.bool(),types.bool(),types.bool(),types.bool()}, "WaitOnInput "..systolicModule.name.." ready %d validIn %d runable %d RST %d", true ):instantiate(prefix.."printInst") ) end

    local sinp = S.parameter(fnname.."_input", darkroom.lower(darkroom.V(srcFn:getInput().type)) )

    local svalid = S.parameter(fnname.."_valid", types.bool())
    local runable = S.__or(S.__not(inner[prefix.."ready"](inner)), S.index(sinp,1) ):disablePipelining()

    local out = inner[fnname]( inner, S.index(sinp,0), runable )

    local RST = S.parameter(prefix.."reset",types.bool())
    if systolicModule:lookupFunction(prefix.."reset"):isPure() then RST=S.constant(false,types.bool()) end

    local pipelines = {}
    -- Actually, it's ok for (ready==false and valid(inp)==true) to be true. We do not have to read when ready==false, we can just ignore it.
    --  table.insert( pipelines, asstInst:process(S.__not(S.__and(S.eq(inner:ready(),S.constant(false,types.bool())),S.index(sinp,1)))):disablePipelining() )
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple{inner[prefix.."ready"](inner),S.index(sinp,1), runable, RST} ) ) end

    local CE = S.CE("CE")
    res:addFunction( S.lambda(fnname, sinp, S.tuple{ S.index(out,0), S.__and(S.index(out,1),S.__and(runable,svalid):disablePipelining()):disablePipeliningSingle() }, fnname.."_output", pipelines, svalid, CE ) )
    res:addFunction( S.lambda(prefix.."reset", S.parameter(prefix.."r",types.null()), inner[prefix.."reset"](inner), "ro", {}, RST, CE) )
    res:addFunction( S.lambda(prefix.."ready", S.parameter(prefix.."readyinp",types.null()), inner[prefix.."ready"](inner), prefix.."ready", {} ) )
  end

  passthroughSystolic( res, systolicModule, inner, passthroughFns )
  return res
end

-- This is basically just for testing: artificially reduces the throughput along a path
function darkroom.reduceThroughput(A,factor)
  assert(type(factor)=="number")
  assert(factor>1)
  assert(math.floor(factor)==factor)
  local res = {kind="reduceThroughput",factor=factor}
  res.inputType = A
  res.outputType = darkroom.RV(A)
  res.sdfInput = {{1,factor}}
  res.sdfOutput = {{1,factor}}
  res.stateful = true
  res.delay = 0
  local struct ReduceThroughput {ready:bool; phase:int}
  terra ReduceThroughput:reset() self.phase=0 end
  terra ReduceThroughput:stats(inp:&int8)  end
  terra ReduceThroughput:process(inp:&A:toTerraType(),out:&darkroom.lower(res.outputType):toTerraType()) 
    data(out) = @inp
    valid(out) = self.ready
    self.phase = self.phase+1
    if self.phase==factor then self.phase=0 end
  end
  terra ReduceThroughput:calculateReady() 
    self.ready = (self.phase==0) 
  end
  res.terraModule = ReduceThroughput
  res.systolicModule = S.moduleConstructor("ReduceThroughput_"..factor)

  local phase = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), factor-1, 1 ) ):CE(true):setInit(0):instantiate("phase") ) 

  local reading = S.eq( phase:get(), S.constant(0,types.uint(16)) ):disablePipelining()

  local sinp = S.parameter( "inp", A )

  local pipelines = {}
  table.insert(pipelines, phase:setBy(S.constant(true,types.bool())))

  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{sinp,reading}, "process_output", pipelines, nil, CE) )
  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()),CE) )

  return darkroom.waitOnInput( darkroom.newFunction(res) )
end

-- f should be basic->RV
-- You should never use basic->RV directly! S->SRV's input should be valid iff ready==true. This is not the case with normal Stateful functions!
-- if inner:ready()==true, inner will run iff valid(input)==true
-- if inner:ready()==false, inner will run always. Input will be garbage, but inner isn't supposed to be reading from it! (this condition is used for upsample, for example)
darkroom.waitOnInput = memoize(function(f)
  err(darkroom.isFunction(f),"waitOnInput argument should be darkroom function")
  local res = {kind="waitOnInput", fn = f}
  darkroom.expectBasic(f.inputType)
  darkroom.expectRV(f.outputType)
  res.inputType = darkroom.V(f.inputType)
  res.outputType = f.outputType

  err( type(f.sdfInput)=="table", "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  err( type(f.stateful)=="boolean", "Missing stateful annotation for fn "..f.kind)
  res.stateful = f.stateful
  res.delay = f.delay
  local struct WaitOnInput { inner : f.terraModule, ready:bool }
  terra WaitOnInput:reset() self.inner:reset() end
  terra WaitOnInput:stats(name:&int8) self.inner:stats(name) end
  terra WaitOnInput:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    if self.inner.ready==false or valid(inp) then
      -- inner should just ignore the input if inner:ready()==false. We don't have to check for this
--      if xor(self.inner:ready(),valid(inp)) then 
--        cstdio.printf("XOR %d %d\n",self.inner:ready(),valid(inp))
--        darkroomAssert(false,"waitOnInput valid bit doesnt match ready bit") 
--      end

      self.inner:process(&data(inp),out)
    else
      valid(out) = false
    end
  end
  terra WaitOnInput:calculateReady() self.inner:calculateReady(); self.ready = self.inner.ready end
  res.terraModule = WaitOnInput
  res.systolicModule = waitOnInputSystolic( f.systolicModule, {"process"},{})

  return darkroom.newFunction(res)
                               end)

local function liftDecimateSystolic( systolicModule, liftFns, passthroughFns )
  local res = S.moduleConstructor("LiftDecimate_"..systolicModule.name)
  local inner = res:add( systolicModule:instantiate("LiftDecimate") )

  for _,fnname in pairs(liftFns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    local sinp = S.parameter(fnname.."_input", darkroom.lower(darkroom.V(srcFn.inputParameter.type)) )
    local pout = inner[fnname]( inner, S.index(sinp,0), S.index(sinp,1) )
    local pout_data = S.index(pout,0)
    local pout_valid = S.index(pout,1)
    
    local CE = S.CE(prefix.."CE")
    res:addFunction( S.lambda(fnname, sinp, S.tuple{pout_data, S.__and(pout_valid,S.index(sinp,1))}, fnname.."_output",nil,nil,CE ) )
    if systolicModule:lookupFunction(prefix.."reset")~=nil then
      -- stateless modules don't have a reset
      res:addFunction( S.lambda(prefix.."reset", S.parameter("r",types.null()), inner[prefix.."reset"](inner), "ro", {},S.parameter(prefix.."reset",types.bool()), CE) )
    end
    res:addFunction( S.lambda(prefix.."ready", S.parameter(prefix.."readyinp",types.null()), S.constant(true,types.bool()), prefix.."ready", {} ) )
  end

  passthroughSystolic( res, systolicModule, inner, passthroughFns )

  return res
end

-- takes basic->V to V->RV
darkroom.liftDecimate = memoize(function(f)
  assert(darkroom.isFunction(f))
  local res = {kind="liftDecimate", fn = f}
  darkroom.expectBasic(f.inputType)
  res.inputType = darkroom.V(f.inputType)

  if darkroom.isV(f.outputType) then
    res.outputType = darkroom.RV(darkroom.extractData(f.outputType))
  elseif f.outputType:isTuple() and #f.outputType.list==2 and f.outputType.list[2]==types.bool() then
    -- "looks like" a V
    res.outputType = darkroom.RV(f.outputType.list[1])
  else
    err(false, "expected V output type")
  end

  err(type(f.stateful)=="boolean", "Missing stateful annotation for "..f.kind)
  res.stateful = f.stateful

  err( darkroom.isSDFRate(f.sdfInput), "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput

  res.delay = f.delay
  local struct LiftDecimate { inner : f.terraModule; idleCycles:int, activeCycles:int, ready:bool}
  terra LiftDecimate:reset() self.inner:reset(); self.idleCycles = 0; self.activeCycles=0; end
  terra LiftDecimate:stats(name:&int8) cstdio.printf("LiftDecimate %s utilization %f\n",name,[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end
  terra LiftDecimate:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    if valid(inp) then
      self.inner:process(&data(inp),[&darkroom.lower(f.outputType):toTerraType()](out))
      self.activeCycles = self.activeCycles + 1
    else
      valid(out) = false
      self.idleCycles = self.idleCycles + 1
    end
  end
  terra LiftDecimate:calculateReady() self.ready=true end
  res.terraModule = LiftDecimate

  err( f.systolicModule~=nil, "Missing systolic for "..f.kind )
  res.systolicModule = liftDecimateSystolic( f.systolicModule, {"process"},{})

  return darkroom.newFunction(res)
                                end)

-- converts V->RV to RV->RV
darkroom.RPassthrough = memoize(function(f)
  local res = {kind="RPassthrough", fn = f}
  darkroom.expectV(f.inputType)
  darkroom.expectRV(f.outputType)
  res.inputType = darkroom.RV(darkroom.extractData(f.inputType))
  res.outputType = darkroom.RV(darkroom.extractData(f.outputType))
  err( type(f.sdfInput)=="table", "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  err( type(f.stateful)=="boolean", "Missing stateful annotation for "..f.kind)
  res.stateful = f.stateful
  res.delay = f.delay
  local struct RPassthrough { inner : f.terraModule, readyDownstream:bool, ready:bool}
  terra RPassthrough:reset() self.inner:reset() end
  terra RPassthrough:stats( name : &int8 ) self.inner:stats(name) end
  terra RPassthrough:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    self.inner:process([&darkroom.lower(f.inputType):toTerraType()](inp),out)
  end
  terra RPassthrough:calculateReady( readyDownstream:bool ) 
    self.readyDownstream = readyDownstream
    self.inner:calculateReady()
    self.ready = readyDownstream and self.inner.ready
  end
  res.terraModule = RPassthrough

  err( f.systolicModule~=nil, "RPassthrough null module "..f.kind)
  res.systolicModule = S.moduleConstructor("RPassthrough_"..f.systolicModule.name)
  local inner = res.systolicModule:add( f.systolicModule:instantiate("RPassthrough_inner") )
  local sinp = S.parameter("process_input", darkroom.lower(res.inputType) )

  -- this is dumb: we don't actually use the 'ready' bit in the struct (it's provided by the ready function).
  -- but we include it to distinguish the types.
  local out = inner:process( S.tuple{ S.index(sinp,0), S.index(sinp,1)} )
  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ S.index(out,0), S.index(out,1) }, "process_output", nil, nil, CE ) )
  if f.stateful then
    res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {}, S.parameter("reset",types.bool()), CE) )
  end
  local rinp = S.parameter("ready_input", types.bool() )
  res.systolicModule:addFunction( S.lambda("ready", rinp, S.__and(inner:ready(),rinp):disablePipelining(), "ready", {} ) )

  return darkroom.newFunction(res)
                                end)

-- takes basic->basic to RV->RV
function darkroom.RVPassthrough(f)
  return darkroom.RPassthrough(darkroom.liftDecimate(darkroom.liftBasic(f)))
end

local function liftHandshakeSystolic( systolicModule, liftFns, passthroughFns )
  local res = S.moduleConstructor( "LiftHandshake_"..systolicModule.name ):onlyWire(true):parameters({INPUT_COUNT=0, OUTPUT_COUNT=0})
  local inner = res:add(systolicModule:instantiate("inner_"..systolicModule.name))

  systolicModule:complete()

  for _,fnname in pairs(liftFns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    local printInst 
    if DARKROOM_VERBOSE then printInst = res:add( S.module.print( types.tuple{types.bool(), srcFn:getInput().type.list[1],types.bool(),srcFn:getOutput().type.list[1],types.bool(),types.bool(),types.bool(),types.uint(16), types.uint(16)}, fnname.." RST %d I %h IV %d O %h OV %d readyDownstream %d ready %d outputCount %d expectedOutputCount %d"):instantiate(prefix.."printInst") ) end

    local outputCount
    if STREAMING==false and DARKROOM_VERBOSE then outputCount = res:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIf() ):CE(true):instantiate(prefix.."outputCount"):setCoherent(false) ) end


    local pinp = S.parameter(fnname.."_input", srcFn:getInput().type )

    local rst = S.parameter(prefix.."reset",types.bool())

    local downstreamReady = S.parameter(prefix.."ready_downstream", types.bool())
    local CE = S.__or(rst,downstreamReady)

    local pout = inner[fnname](inner,pinp,S.__not(rst), CE )

    -- not blocked downstream: either downstream is ready (downstreamReady), or we don't have any data anyway (pout[1]==false), so we can work on clearing the pipe
    -- Actually - I don't think this is legal. We can't have our stall signal depend on our own output. We would have to register it, etc
    --local notBlockedDownstream = S.__or(downstreamReady, S.eq(S.index(pout,1),S.constant(false,types.bool()) ))
  --local CE = notBlockedDownstream
    
    -- the point of the shift register: systolic doesn't have an output valid bit, so we have to explicitly calculate it.
    -- basically, for the first N cycles the pipeline is executed, it will have garbage in the pipe (valid was false at the time those cycles occured). So we need to gate the output by the delayed valid bits. This is a little big goofy here, since process_valid is always true, except for resets! It's not true for the first few cycles after resets! And if we ignore that the first few outputs will be garbage!
    local SR = res:add( fpgamodules.shiftRegister( types.bool(), systolicModule:getDelay(fnname), false, true ):instantiate(prefix.."validBitDelay_"..systolicModule.name) )
    
    local srvalue = SR:pushPop(S.constant(true,types.bool()), S.__not(rst), CE )
    local outvalid = S.__and(S.index(pout,1), srvalue )
    local outvalidRaw = outvalid
    --if STREAMING==false then outvalid = S.__and( outvalid, S.lt(outputCount:get(),S.instanceParameter("OUTPUT_COUNT",types.uint(16)))) end
    local out = S.tuple{ S.index(pout,0), outvalid }
    
    local readyOut = systolic.__and(inner[prefix.."ready"](inner),downstreamReady)
    local pipelines = {}
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple{ rst, S.index(pinp,0), S.index(pinp,1), S.index(out,0), S.index(out,1), downstreamReady, readyOut, outputCount:get(), S.instanceParameter("OUTPUT_COUNT",types.uint(16)) } ) ) end
    if STREAMING==false and DARKROOM_VERBOSE then table.insert(pipelines,  outputCount:setBy(outvalid, S.__not(rst), CE) ) end
    
    local asstInst = res:add( S.module.assert( "LiftHandshake: output valid bit should not be X!" , false, false):instantiate(prefix.."asstInst") )
    table.insert(pipelines, asstInst:process(S.__not(S.isX(S.index(out,1))), S.constant(true,types.bool()) ) )
    
    local asstInst2 = res:add( S.module.assert( "LiftHandshake: input valid bit should not be X!" , false, false):instantiate(prefix.."asstInst2") )
    table.insert(pipelines, asstInst2:process(S.__not(S.isX(S.index(pinp,1))), S.constant(true,types.bool()) ) )
    
    res:addFunction( S.lambda(fnname, pinp, out, fnname.."_output", pipelines ) ) 
    
    local resetPipelines = {}
    resetPipelines[1] = SR:reset( nil, rst, CE )
    if STREAMING==false and DARKROOM_VERBOSE then table.insert(resetPipelines, outputCount:set(S.constant(0,types.uint(16)),rst,CE) ) end
    
    res:addFunction( S.lambda(prefix.."reset", S.parameter(prefix.."r",types.null()), inner[prefix.."reset"]( inner, nil, rst, CE ), prefix.."reset_out", resetPipelines, rst ) )
    
    assert( systolicModule:getDelay(prefix.."ready")==0 ) -- ready bit calculation can't be pipelined! That wouldn't make any sense
    
    res:addFunction( S.lambda(prefix.."ready", downstreamReady, readyOut, prefix.."ready" ) )
  end
  
  assert(#passthroughFns==0)

  return res
end

-- takes V->RV to Handshake->Handshake
darkroom.liftHandshake = memoize(function(f)
  local res = {kind="liftHandshake", fn=f}
  darkroom.expectV(f.inputType)
  darkroom.expectRV(f.outputType)
  res.inputType = darkroom.Handshake(darkroom.extractData(f.inputType))
  res.outputType = darkroom.Handshake(darkroom.extractData(f.outputType))

  err( darkroom.isSDFRate(f.sdfInput), "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  err(type(f.stateful)=="boolean", "Missing stateful annotation, "..f.kind)
  res.stateful = f.stateful

  local delay = math.max(1, f.delay)

  local struct LiftHandshake{ delaysr: simmodules.fifo( darkroom.lower(f.outputType):toTerraType(), delay, "liftHandshake"),
                              inner: f.terraModule, ready:bool, readyDownstream:bool}
  terra LiftHandshake:reset() self.delaysr:reset(); self.inner:reset() end
  terra LiftHandshake:stats(name:&int8) 
--    cstdio.printf("LiftHandshake %s, Max input fifo size: %d\n", name, self.fifo:maxSizeSeen())
    self.inner:stats(name) 
  end

  terra LiftHandshake:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    if self.readyDownstream then
      if DARKROOM_VERBOSE then cstdio.printf("LIFTHANDSHAKE %s READY DOWNSTRAM = true. ready this = %d\n", f.kind,self.inner.ready) end
--     if valid(inp) and self.inner:ready() then
--        self.fifo:pushBack(&data(inp))
--      end

      if self.delaysr:size()==delay then
        var ot = self.delaysr:popFront()
        valid(out) = valid(ot)
        data(out) = data(ot)
      else
        valid(out) = false
      end

      var tout : darkroom.lower(f.outputType):toTerraType()

      self.inner:process(inp,&tout)
      self.delaysr:pushBack(&tout)
    end
  end
  terra LiftHandshake:calculateReady(readyDownstream:bool) 
    self.readyDownstream = readyDownstream
    self.inner:calculateReady()
    self.ready = readyDownstream and self.inner.ready 
  end
--  terra LiftHandshake:ready(readyDownstream:bool) return readyDownstream  end
  res.terraModule = LiftHandshake
  res.systolicModule = liftHandshakeSystolic( f.systolicModule, {"process"},{} )

  return darkroom.newFunction(res)
                                 end)

-- arrays: A[W][H]. Row major
-- array index A[y] yields type A[W]. A[y][x] yields type A

-- f : ( A, B, ...) -> C (darkroom function)
-- map : ( f, A[n], B[n], ...) -> C[n]
darkroom.map = memoize(function( f, W, H )
  assert( darkroom.isFunction(f) )
  assert(type(W)=="number")
  assert(type(H)=="number" or H==nil)
  if H==nil then H=1 end

  local res = { kind="map", fn = f, W=W, H=H }

  res.inputType = types.array2d( f.inputType, W, H )
  res.outputType = types.array2d( f.outputType, W, H )
  err(type(f.stateful)=="boolean", "Missing stateful annotation "..f.kind)
  res.stateful = f.stateful
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = f.delay
  local struct MapModule {fn:f.terraModule}
  terra MapModule:reset() self.fn:reset() end
  terra MapModule:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for i=0,W*H do self.fn:process( &((@inp)[i]), &((@out)[i])  ) end
  end
  res.terraModule = MapModule
  res.systolicModule = S.moduleConstructor("map_"..f.systolicModule.name.."_W"..tostring(W).."_H"..tostring(H))
  local inp = S.parameter("process_input", res.inputType )
  local out = {}
  local resetPipelines={}
  for y=0,H-1 do
    for x=0,W-1 do 
      local inst = res.systolicModule:add(f.systolicModule:instantiate("inner"..x.."_"..y))
      table.insert( out, inst:process( S.index( inp, x, y ) ) )
      if f.stateful then
        table.insert( resetPipelines, inst:reset() ) -- no reset for pure functions
      end
    end 
  end
  local CE = S.CE("process_CE")
  res.systolicModule:addFunction( S.lambda("process", inp, S.cast( S.tuple( out ), res.outputType ), "process_output", nil, nil, CE ) )
  if f.stateful then
    res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, S.parameter("reset",types.bool()),CE ) )
  end

  return darkroom.newFunction(res)
end)

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
  terra FilterStateful:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    var bout : bool[T]
    var fakeinp : darkroom.lower(f.inputType):toTerraType()
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
  terra Densify:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
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
-- basic -> V
darkroom.downsampleYSeq = memoize(function( A, W, H, T, scale )
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

  local f = darkroom.lift( "DownsampleYSeq_W"..tostring(W).."_H"..tostring(H).."_scale"..tostring(scale), innerInputType, outputType, 0, 
                           terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
                             var y = (inp._0)[0]._1
                             data(out) = inp._1
                             valid(out) = (y%scale==0)
                           end, sinp, S.tuple{sdata,svalid}, nil, {{1,scale}})

  return darkroom.liftXYSeq( f, W, H, T )
                                  end)

-- takes A[W,H] to A[W/scale,H]
-- lines where xcoord%scale==0 are kept
-- basic -> V
-- 
-- This takes A[T] to A[T/scale], except in the case where scale>T. Then it goes from A[T] to A[1]. If you want to go from A[T] to A[T], use changeRate.
darkroom.downsampleXSeq = memoize(function( A, W, H, T, scale )
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

  if scale>T then -- A[T] to A[1]
    sdfOverride = {{1,scale}}
    svalid = S.eq(S.cast(S.bitSlice(sy,0,sbits-1),types.uint(sbits)),S.constant(0,types.uint(sbits)))
    sdata = S.index(sinp,1)
    tfn = terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
                             var x = (inp._0)[0]._0
                             data(out) = inp._1
                             valid(out) = (x%scale==0)
                           end
  else
    sdfOverride = {{1,1}}
    svalid = S.constant(true,types.bool())
    local datavar = S.index(sinp,1)
    sdata = map(range(0,outputT-1), function(i) return S.index(datavar, i*scale) end)
    sdata = S.cast(S.tuple(sdata), types.array2d(A,outputT))
    tfn = terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
      for i=0,outputT do (data(out))[i] = (inp._1)[i*scale] end
      valid(out) = true
    end
  end

  local f = darkroom.lift( "DownsampleXSeq_W"..tostring(W).."_H"..tostring(H), innerInputType, outputType, 0, tfn, sinp, S.tuple{sdata,svalid},nil,sdfOverride)

  return darkroom.liftXYSeq( f, W, H, T )
                                  end)

-- V -> RV
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
  
  local inp = darkroom.input( darkroom.V(types.array2d(A,T)) )
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
-- like this: [A[0],A[0],A[1],A[1],A[2],A[2],...]
function darkroom.broadcastWide( A, T, scale )
  local ITYPE, OTYPE = types.array2d(A,T), types.array2d(A,T*scale)
  local sinp = S.parameter("inp",types.array2d(A,T))
  local out = {}
  for t=0,T-1 do
    for s=0,scale-1 do
      table.insert(out, S.index(sinp,t) )
    end
  end
  out = S.cast(S.tuple(out), OTYPE)
  return darkroom.lift("broadcastWide", ITYPE, OTYPE, 0,
                       terra(inp : &ITYPE:toTerraType(), out:&OTYPE:toTerraType())
                         for t=0,T do
                           for s=0,scale do
                             (@out)[t*scale+s] = (@inp)[t]
                           end
                         end
                       end, sinp, out)
end

-- this has type V->RV
function darkroom.upsampleXSeq( A, T, scale, X )
  assert(X==nil)

  if T==1 then
    -- special case the EZ case of taking one value and writing it out N times
    local res = {kind="upsampleXSeq",sdfInput={{1,scale}}, sdfOutput={{1,1}}, stateful=true}

    local ITYPE = types.array2d(A,T)
    res.inputType = ITYPE
    res.outputType = darkroom.RV(types.array2d(A,T))
    res.delay=0

    local struct UpsampleXSeq { buffer : ITYPE:toTerraType(), phase:int, ready:bool }
    terra UpsampleXSeq:reset() self.phase=0; end
    terra UpsampleXSeq:stats(name:&int8)  end
    terra UpsampleXSeq:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
      valid(out) = true
      if self.phase==0 then
        self.buffer = @(inp)
        data(out) = @(inp)
      else
        data(out) = self.buffer
      end

      self.phase = self.phase + 1
      if self.phase==scale then self.phase=0 end
    end
    terra UpsampleXSeq:calculateReady()  self.ready = (self.phase==0) end

    res.terraModule = UpsampleXSeq

    -----------------
    res.systolicModule = S.moduleConstructor("UpsampleXSeq")
    local sinp = S.parameter( "inp", ITYPE )

    local sPhase = res.systolicModule:add( S.module.regByConstructor( types.uint(8), fpgamodules.sumwrap(types.uint(8),scale-1) ):CE(true):instantiate("phase") )
    local reg = res.systolicModule:add( S.module.reg( ITYPE,true ):instantiate("buffer") )

    local reading = S.eq(sPhase:get(),S.constant(0,types.uint(8))):disablePipelining()
    local out = S.select( reading, sinp, reg:get() ) 

    local pipelines = {}
    table.insert(pipelines, reg:set( sinp, reading ) )
    table.insert( pipelines, sPhase:setBy( S.constant(1,types.uint(8)) ) )

    local CE = S.CE("CE")
    res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines, nil, CE) )
    res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
    res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:set(S.constant(0,types.uint(8)))},S.parameter("reset",types.bool()),CE) )

    return darkroom.liftHandshake(darkroom.waitOnInput( darkroom.newFunction(res) ))
  else
    return darkroom.compose("upsampleXSeq_"..T, darkroom.liftHandshake(darkroom.changeRate(A,1,T*scale,T)), darkroom.makeHandshake(darkroom.broadcastWide(A,T,scale)))
  end
end

-- V -> RV
function darkroom.upsampleYSeq( A, W, H, T, scale )
  err( W%T==0,"W%T~=0")
  err( isPowerOf2(scale), "scale must be power of 2")
  err( isPowerOf2(W), "W must be power of 2")

  local res = {kind="upsampleYSeq", sdfInput={{1,scale}}, sdfOutput={{1,1}}}
  local ITYPE = types.array2d(A,T)
  res.inputType = ITYPE
  res.outputType = darkroom.RV(types.array2d(A,T))
  res.delay=0
  res.stateful = true

  local struct UpsampleYSeq { buffer : (ITYPE:toTerraType())[W/T], phase:int, xpos: int, ready:bool }
  terra UpsampleYSeq:reset() self.phase=0; self.xpos=0; end
  terra UpsampleYSeq:stats(name:&int8)  end
  terra UpsampleYSeq:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
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
  terra UpsampleYSeq:calculateReady()  self.ready = (self.phase==0) end

  res.terraModule = UpsampleYSeq

  -----------------
  res.systolicModule = S.moduleConstructor("UpsampleYSeq")
  local sinp = S.parameter( "inp", ITYPE )

  -- we currently don't have a way to make a posx counter and phase counter coherent relative to each other. So just use 1 counter for both. This restricts us to only do power of two however!
  local sPhase = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.sumwrap(types.uint(16),(W/T)*scale-1) ):CE(true):instantiate("xpos") )

  local addrbits = math.log(W/T)/math.log(2)
  assert(addrbits==math.floor(addrbits))
  
  local xpos = S.cast(S.bitSlice( sPhase:get(), 0, addrbits-1), types.uint(addrbits))

  local phasebits = (math.log(scale)/math.log(2))
  local phase = S.cast(S.bitSlice( sPhase:get(), addrbits, addrbits+phasebits-1 ), types.uint(phasebits))

  local sBuffer = res.systolicModule:add( S.module.bramSDP( true, (A:verilogBits()*W)/8, ITYPE:verilogBits()/8, ITYPE:verilogBits()/8,nil,true ):instantiate("buffer"):setCoherent(true) )
  local reading = S.eq( phase, S.constant(0,types.uint(phasebits)) ):disablePipelining()

  local pipelines = {sBuffer:writeAndReturnOriginal(S.tuple{xpos,S.cast(sinp,types.bits(ITYPE:verilogBits()))}, reading), sPhase:setBy( S.constant(1, types.uint(16)) )}
  local out = S.select( reading, sinp, S.cast(sBuffer:read(xpos),ITYPE) ) 
  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines, nil, CE) )
  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()),CE) )

  return darkroom.waitOnInput( darkroom.newFunction(res) )
end

-- this is always Handshake
function darkroom.upsampleSeq( A, W, H, T, scaleX, scaleY )
  assert(scaleX>=1)
  assert(scaleY>=1)

  local inner
  if scaleY>1 and scaleX==1 then
    inner = darkroom.liftHandshake(darkroom.upsampleYSeq( A, W, H, T, scaleY ))
  elseif scaleX>1 and scaleY==1 then
    inner = darkroom.upsampleXSeq( A, T, scaleX )
  else
    local f = darkroom.upsampleXSeq( A, T, scaleX )
    inner = darkroom.compose("upsampleSeq", f, darkroom.liftHandshake(darkroom.upsampleYSeq( A, W, H, T, scaleY )))
  end

--  if scaleX>1 then
--    return darkroom.compose("upsampleSeqCorrectRate",darkroom.liftHandshake(darkroom.changeRate(A,1,T*scaleX,T)), inner)
--  else
    return inner
--  end
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
    table.insert( typelist, darkroom.Handshake(types.array2d(A, T)))
  end

  local res = { kind="packPyramid", levels=levels}
  res.inputType = types.tuple(typelist)
  res.outputType = darkroom.Handshake(types.array2d( A, T ))
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
  local insymb = symbol(&darkroom.lower(res.inputType):toTerraType(),"inp")
  local outsymb = symbol(&darkroom.lower(res.outputType):toTerraType(),"out")
  
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

-- Stateful{uint8,uint8,uint8...} -> Stateful(uint8)
-- Ignores the counts. Just interleaves between streams.
-- N: number of streams.
-- period==0: ABABABAB, period==1: AABBAABBAABB, period==2: AAAABBBB
function darkroom.interleveSchedule( N, period )
  err(type(N)=="number", "N must be number")
  err( isPowerOf2(N), "N must be power of 2")
  err(type(period)=="number", "period must be number")
  local res = {kind="interleveSchedule", N=N, period=period, delay=0, inputType=types.null(), outputType=types.uint(8), sdfInput={{1,1}}, sdfOutput={{1,1}}, stateful=true }
  local struct InterleveSchedule { phase: uint8 }
  terra InterleveSchedule:reset() self.phase=0 end
  terra InterleveSchedule:process( out : &uint8 )
    @out = (self.phase >> period) % N
    self.phase = self.phase+1
  end
  res.terraModule = InterleveSchedule

  res.systolicModule = S.moduleConstructor("InterleveSchedule_"..N.."_"..period)
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.uint(8), "interleve schedule phase %d", true):instantiate("printInst") ) end

  local inp = S.parameter("process_input", darkroom.lower(res.inputType) )
  local phase = res.systolicModule:add( S.module.regByConstructor( types.uint(8), fpgamodules.incIfWrap( types.uint(8), 255, 1 ) ):setInit(0):CE(true):instantiate("interlevePhase") )
  local log2N = math.log(N)/math.log(2)

  local CE = S.CE("CE")
  local pipelines = {phase:setBy( S.constant(true,types.bool()))}
  if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(phase:get())) end

  res.systolicModule:addFunction( S.lambda("process", inp, S.cast(S.cast(S.bitSlice(phase:get(),period,period+log2N-1),types.uint(log2N)), types.uint(8)), "process_output", pipelines, nil, CE ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(8)))}, S.parameter("reset",types.bool()),CE) )

  return darkroom.newFunction(res)
end

-- wtop is the width of the largest (top) pyramid level
function darkroom.pyramidSchedule( depth, wtop, T )
  err(type(depth)=="number", "depth must be number")
  err(type(wtop)=="number", "wtop must be number")
  err(type(T)=="number", "T must be number")
  local res = {kind="pyramidSchedule", wtop=wtop, depth=depth, delay=0, inputType=types.null(), outputType=types.uint(8), sdfInput={{1,1}}, sdfOutput={{1,1}}, stateful=true }
  local struct PyramidSchedule { depth: uint8; w:uint }
  terra PyramidSchedule:reset() self.depth=0; self.w=0 end
  terra PyramidSchedule:process( out : &uint8 )
    @out = self.depth
    var targetW : int = (wtop*cmath.pow(2,depth-1))/cmath.pow(4,self.depth)
    if targetW<T then
      cstdio.printf("Error, targetW < T\n")
      cstdlib.exit(1)
    end
    targetW = targetW/T
    
--    cstdio.printf("PS depth %d w %d targetw %d\n",self.depth,self.w,targetW)
    self.w = self.w + 1
    if self.w==targetW then
--      cstdio.printf("INCD %d %d\n",self.depth,[depth])
      self.w=0
      self.depth = self.depth+1
      if self.depth==[depth] then
        self.depth=0
      end
    else
--      cstdio.printf("NOINC %d %d\n",self.w,targetW)
    end
  end
  res.terraModule = PyramidSchedule

  --------------------
  local pattern = {}
  local minTargetW = math.pow(2,depth-1)/math.pow(4,depth-1)
  local totalW = 0
  for d=0,depth-1 do
    local targetW = math.pow(2,depth-1)/math.pow(4,d)
    targetW = targetW/minTargetW

    for t=1,targetW do
      table.insert(pattern,d)
    end
  end
  --------------------
  assert(#pattern<=128)
  local patternTotal = #pattern
  while #pattern<128 do table.insert(pattern,0) end

  local log2N = math.ceil(math.log(depth)/math.log(2))

  res.systolicModule = S.moduleConstructor("PyramidSchedule_"..depth.."_"..wtop)
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(8), types.uint(16),types.uint(log2N)}, "pyramid schedule addr %d wcnt %d out %d", true):instantiate("printInst") ) end

  local tokensPerAddr = (wtop*minTargetW)/T

  local inp = S.parameter("process_input", darkroom.lower(res.inputType) )
  local addr = res.systolicModule:add( S.module.regByConstructor( types.uint(8), fpgamodules.incIfWrap( types.uint(8), patternTotal-1, 1 ) ):setInit(0):CE(true):instantiate("patternAddr") )
  local wcnt = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), tokensPerAddr-1, 1 ) ):setInit(0):CE(true):instantiate("wcnt") )
  local patternRam = res.systolicModule:add(fpgamodules.ram128(types.uint(log2N), pattern):instantiate("patternRam"))


  local CE = S.CE("CE")
  local pipelines = {addr:setBy( S.eq(wcnt:get(),S.constant(tokensPerAddr-1,types.uint(16))):disablePipelining() )}
  table.insert(pipelines, wcnt:setBy( S.constant(true,types.bool()) ) )

  local out = patternRam:read(addr:get())

  if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(S.tuple{addr:get(),wcnt:get(),out})) end

  res.systolicModule:addFunction( S.lambda("process", inp, out, "process_output", pipelines, nil, CE ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {addr:set(S.constant(0,types.uint(8))), wcnt:set(S.constant(0,types.uint(16)))}, S.parameter("reset",types.bool()),CE) )

  return darkroom.newFunction(res)
end

-- normalizes a table of SDF rates so that they sum to 1
function darkroom.sdfNormalize( tab )
  assert( darkroom.isSDFRate(tab) )

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
    local n,d = simplify(nn,dd)
    res[i] = {n,d}
  end
  
  return res
end

function isFrac(a)
  return type(a)=="table" and type(a[1])=="number" and type(a[2])=="number"
end

function fracToNumber(a)
  assert(isFrac(a))
  return a[1]/a[2]
end

function fracInvert(a)
  assert(isFrac(a))
  return {a[2],a[1]}
end

-- format {n,d}
local function fracSum(a,b)
  local denom = a[2]*b[2]
  local num = a[1]*b[2]+b[1]*a[2]
  local n,d=simplify(num,denom)
  return {n,d}
end

function fracMultiply(a,b)
  local n,d = simplify(a[1]*b[1],a[2]*b[2])
  return {n,d}
end

function sdfSum(tab)
  assert( darkroom.isSDFRate(tab) )
  
  local sum = {0,1}
  for k,v in pairs(tab) do 
    if v~="x" then sum = fracSum(sum,v) end
  end

  return sum
end

function sdfMultiply(tab,n,d)
  assert(type(n)=="number")
  assert(type(d)=="number")

  local res = {}
  for k,v in pairs(tab) do
    if v=="x" then
      table.insert(res,v)
    else
      table.insert(res, fracMultiply(v,{n,d}))
    end
  end
  return res
end

local function mergeStores( module, N )
  local res = S.moduleConstructor("MergeStores_"..module.name):onlyWire(true)
  local inner = res:add( module:instantiate("inner") )

  local srcFn = module:lookupFunction("store_1")
  local inputType = types.array2d(srcFn:getInput().type, N)
  local inp = S.parameter( "store_input", inputType )
  local sout = S.tuple( map(range(N), function(i) return inner["store_"..i](inner, S.index( inp,i-1) ) end ) )

  res:addFunction( S.lambda("store", inp, sout, "store_output" ) )

  res:addFunction( S.lambda("store_reset", S.parameter("store_reset_input",types.null()), nil, "store_reset_output", map( range(N), function(i) return inner["store_"..i.."_reset"](inner) end ) ) )

  local readyinp = S.parameter( "store_ready_downstream", types.bool() )
  local readyout = S.tuple( map(range(N), function(i) return inner["store_"..i.."_ready"](inner, readyinp) end ) )
  res:addFunction( S.lambda("store_ready", readyinp, readyout, "store_ready_output" ) )

  passthroughSystolic( res, module, inner, {"load"}, true )
  return res
end

-- WARNING: validOut depends on readyDownstream
function darkroom.toHandshakeArray( A, inputRates )
  err( types.isType(A), "A must be type" )
  darkroom.expectBasic(A)
  err( type(inputRates)=="table", "inputRates must be table")
  assert(darkroom.isSDFRate(inputRates))

  local res = {kind="toHandshakeArray", A=A, inputRates = inputRates}
  res.inputType = types.array2d( darkroom.Handshake(A), #inputRates )
  res.outputType = darkroom.HandshakeArray( A, #inputRates )
  res.sdfInput = inputRates
  res.sdfOutput = inputRates
  res.stateful = false
  function res:sdfTransfer( I, loc ) 
    err(#I[1]==#inputRates, "toHandshakeArray: incorrect number of input streams. Is "..(#I[1]).." but expected "..(#inputRates) )
    return I 
  end
  
  local struct ToHandshakeArray {ready:bool[#inputRates], readyDownstream:uint8}
  terra ToHandshakeArray:reset()  end
  terra ToHandshakeArray:stats( name: &int8 ) end
  terra ToHandshakeArray:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    if self.readyDownstream < [#inputRates] then -- is ready bit true?
      if valid((@inp)[self.readyDownstream]) then
        valid(out) = true
        data(out) = data((@inp)[self.readyDownstream])
      else
        if DARKROOM_VERBOSE then 
          cstdio.printf("TOHANDSHAKE FAIL: invalid input. readyDownstream=%d/%d\n", self.readyDownstream,[#inputRates-1]) 
          for i=0,[#inputRates] do cstdio.printf("TOHANDSHAKE ready[%d] = %d\n",i,valid((@inp)[i]) ) end
        end
        
        valid(out) = false
      end
    else
      if DARKROOM_VERBOSE then cstdio.printf("TOHANDSHAKE FAIL: not ready downstream\n") end
    end
  end
  terra ToHandshakeArray:calculateReady( readyDownstream : uint8 )
    self.readyDownstream = readyDownstream
    for i=0,[#inputRates] do 
      self.ready[i] = (i == readyDownstream ) 
      if DARKROOM_VERBOSE then cstdio.printf("HANDSHAKE ARRAY READY DS %d I %d %d\n", readyDownstream,i, self.ready[i] ) end
    end
  end
  
  res.terraModule = ToHandshakeArray

  res.systolicModule = S.moduleConstructor("ToHandshakeArray_"..#inputRates):onlyWire(true)
  local printStr = "IV ["..table.concat(broadcast("%d",#inputRates),",").."] OV %d readyDownstream %d/"..(#inputRates-1)
  local printInst
    if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple(concat(broadcast(types.bool(),#inputRates+1),{types.uint(8)})), printStr):instantiate("printInst") ) end

  local inp = S.parameter( "process_input", darkroom.lower(res.inputType) )

  local inpData = {}
  local inpValid = {}

  for i=1,#inputRates do
    table.insert( inpData, S.index(S.index(inp,i-1),0) )
    table.insert( inpValid, S.index(S.index(inp,i-1),1) )
  end

  local readyDownstream = S.parameter( "ready_downstream", types.uint(8) )

  local validList = {}
  for i=1,#inputRates do
    table.insert( validList, S.__and(inpValid[i], S.eq(readyDownstream, S.constant(i-1,types.uint(8))) ) )
  end

  local validOut = foldt( validList, function(a,b) return S.__or(a,b) end, "X" )

  local pipelines = {}
  local tab = concat(concat(inpValid,{validOut}), {readyDownstream})
  assert(#tab==(#inputRates+2))
  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple(tab) ) ) end

  local dataOut = fpgamodules.wideMux( inpData, readyDownstream )
  res.systolicModule:addFunction( S.lambda("process", inp, S.tuple{dataOut,validOut} , "process_output", pipelines) )

  local readyOut = map(range(#inputRates), function(i) return S.eq(S.constant(i-1,types.uint(8)), readyDownstream) end )
  res.systolicModule:addFunction( S.lambda("ready", readyDownstream, S.cast(S.tuple(readyOut),types.array2d(types.bool(),#inputRates)), "ready" ) )

  return darkroom.newFunction( res )
end

-- inputRates is a list of SDF rates
-- {StatefulHandshakRegistered(A),StatefulHandshakRegistered(A),...} -> StatefulHandshakRegistered({A,stream:uint8}),
-- where stream is the ID of the input that corresponds to the output
function darkroom.serialize( A, inputRates, Schedule, X )
  err( types.isType(A), "A must be type" )
  err( type(inputRates)=="table", "inputRates must be table")
  assert( darkroom.isSDFRate(inputRates) )
  err( darkroom.isFunction(Schedule), "schedule must be darkroom function")
  err( darkroom.lower(Schedule.outputType)==types.uint(8), "schedule function has incorrect output type, "..tostring(Schedule.outputType))
  darkroom.expectBasic(A)
  assert(X==nil)

  local res = {kind="serialize", A=A, inputRates=inputRates, schedule=Schedule}
  res.inputType = darkroom.HandshakeArray( A, #inputRates )
  res.outputType = darkroom.HandshakeTmuxed( A, #inputRates )
  err( type(Schedule.stateful)=="boolean", "Schedule missing stateful annotation")
  res.stateful = Schedule.stateful

  local sdfSum = inputRates[1][1]/inputRates[1][2]
  for i=2,#inputRates do sdfSum = sdfSum + (inputRates[i][1]/inputRates[i][2]) end
  err(sdfSum==1, "inputRates must sum to 1")

  -- the output rates had better be the same as the inputs!
  res.sdfInput = inputRates
  res.sdfOutput = inputRates

  function res:sdfTransfer( I, loc ) 
    err(#I[1]==#inputRates, "serialize: incorrect number of input streams. Is "..(#I[1]).." but expected "..(#inputRates) )
    return I 
  end

  local struct Serialize { schedule: Schedule.terraModule; nextId : uint8, ready:uint8, readyDownstream:bool}
  terra Serialize:reset() self.schedule:reset(); self.schedule:process(&self.nextId) end
  terra Serialize:stats( name: &int8 ) end
  terra Serialize:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    if self.readyDownstream then
      if valid(inp) then
        valid(out) = self.nextId
        data(out) = data(inp)
        -- step the schedule
        if DARKROOM_VERBOSE then cstdio.printf("STEPSCHEDULE\n") end
        self.schedule:process( &self.nextId)
      else
        if DARKROOM_VERBOSE then cstdio.printf("STEPSCHEDULE FAIL: invalid input\n") end
        valid(out) = [#inputRates]
      end
    else
        if DARKROOM_VERBOSE then cstdio.printf("STEPSCHEDULE FAIL: blocked downstream\n") end
    end
  end
  terra Serialize:calculateReady( readyDownstream : bool) 
    self.readyDownstream = readyDownstream
    if readyDownstream==false then 
      self.ready = [#inputRates] -- intentionally out of bounds
    else 
      self.ready = self.nextId 
    end
  end

  res.terraModule = Serialize

  res.systolicModule = S.moduleConstructor("Serialize_"..#inputRates):onlyWire(true)
  local scheduler = res.systolicModule:add( Schedule.systolicModule:instantiate("Scheduler") )
  local printInst
  if DARKROOM_VERBOSE then printInst= res.systolicModule:add( S.module.print( types.tuple{types.uint(8),types.bool(),types.uint(8),types.bool()}, "Serialize OV %d/"..(#inputRates-1).." readyDownstream %d ready %d/"..(#inputRates-1).." stepSchedule %d"):instantiate("printInst") ) end
  local resetValid = S.parameter("reset_valid", types.bool() )

  local inp = S.parameter( "process_input", darkroom.lower(res.inputType) )
  local inpData = S.index(inp,0)
  local inpValid = S.index(inp,1)
  local readyDownstream = S.parameter( "ready_downstream", types.bool() )

  local pipelines = {}
  local resetPipelines = {}

  local stepSchedule = S.__and( S.__and(inpValid, readyDownstream), S.__not(resetValid) )

  assert( Schedule.systolicModule:getDelay("process")==0 )
  local schedulerCE = S.__or(resetValid, readyDownstream)
  local nextFIFO = scheduler:process(nil,stepSchedule, schedulerCE)

  table.insert( resetPipelines, scheduler:reset(nil, resetValid, schedulerCE ) )

  local validOut = S.select(inpValid,nextFIFO,S.constant(#inputRates,types.uint(8)))

  local readyOut = S.select( readyDownstream, nextFIFO, S.constant(#inputRates,types.uint(8)))
  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple{validOut, readyDownstream, readyOut, stepSchedule} ) ) end

  res.systolicModule:addFunction( S.lambda("process", inp, S.tuple{ inpData, validOut } , "process_output", pipelines ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, resetValid ) )

  res.systolicModule:addFunction( S.lambda("ready", readyDownstream, readyOut, "ready" ) )

  return darkroom.newFunction(res)
end

-- WARNING: ready depends on ValidIn
function darkroom.demux( A, rates, X )
  err( types.isType(A), "A must be type" )
  err( type(rates)=="table", "rates must be table")
  assert( darkroom.isSDFRate(rates) )
  darkroom.expectBasic(A)
  assert(X==nil)

  local res = {kind="demux", A=A, rates=rates}

  res.inputType = darkroom.HandshakeTmuxed( A, #rates )
  res.outputType = types.array2d(darkroom.Handshake(A), #rates)
  res.stateful = false

  local sdfSum = rates[1][1]/rates[1][2]
  for i=2,#rates do sdfSum = sdfSum + (rates[i][1]/rates[i][2]) end
  err(sdfSum==1, "rates must sum to 1")

  res.sdfInput = rates
  res.sdfOutput = rates

  function res:sdfTransfer( I, loc ) 
    err(#I[1]==#rates, "demux: incorrect number of input streams. Is "..(#I[1]).." but expected "..(#rates) )
    return I 
  end

  -- HACK: we don't have true bidirectional data transfer in the simulator, so fake it with a FIFO
  local struct Demux { fifo: simmodules.fifo( darkroom.lower(res.inputType):toTerraType(), 8, "makeHandshake"), ready:bool, readyDownstream:bool[#rates]}
  terra Demux:reset() self.fifo:reset() end
  terra Demux:stats( name: &int8 ) end
  terra Demux:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    if self.ready then
      if DARKROOM_VERBOSE then cstdio.printf("DMUX: push to internal fifo\n") end
      self.fifo:pushBack(inp)
    else
      if DARKROOM_VERBOSE then cstdio.printf("DMUX: push to internal fifo fail, not ready\n") end
    end

    var ot = self.fifo:peekFront(0)
    if valid(ot)>=[#rates] and self.fifo:hasData() then
      for i=0,[#rates] do
        valid((@out)[i]) = false
      end
      self.fifo:popFront()
      if DARKROOM_VERBOSE then cstdio.printf("DMUX: invalid input\n") end
    elseif valid(ot)<[#rates] and self.readyDownstream[valid(ot)] and self.fifo:hasData() then
      self.fifo:popFront()
      for i=0,[#rates] do
        valid((@out)[i]) = (i==valid(ot))
        data((@out)[i]) = data(ot)
      end
      if DARKROOM_VERBOSE then cstdio.printf("DMUX: valid input, readyDownstream\n") end
    else
      if DARKROOM_VERBOSE then 
        cstdio.printf("DMUX: not ready downstream IV:%d fifo_full:%d fifo_size:%d\n",valid(ot),self.fifo:full(), self.fifo:size() ) 
        for i=0,[#rates] do cstdio.printf("DMUX readyDownstream[%d] = %d\n",i,self.readyDownstream[i]) end
      end
    end
  end
  terra Demux:calculateReady( readyDownstream : bool[#rates])
    self.readyDownstream = readyDownstream
    self.ready = (self.fifo:full()==false)
  end

  res.terraModule = Demux

  res.systolicModule = S.moduleConstructor("Demux_"..#rates):onlyWire(true)

  local printInst
  if DARKROOM_VERBOSE then printInst= res.systolicModule:add( S.module.print( types.tuple(concat({types.uint(8)},broadcast(types.bool(),#rates+1))), "Demux IV %d readyDownstream ["..table.concat(broadcast("%d",#rates),",").."] ready %d"):instantiate("printInst") ) end
  local resetValid = S.parameter("reset_valid", types.bool() )

  local inp = S.parameter( "process_input", darkroom.lower(res.inputType) )
  local inpData = S.index(inp,0)
  local inpValid = S.index(inp,1)  -- uint8
  local readyDownstream = S.parameter( "ready_downstream", types.array2d( types.bool(), #rates ) )

  local pipelines = {}
  local resetPipelines = {}

  local out = {}
  local readyOut = {}
  for i=1,#rates do
    table.insert( out, S.tuple{inpData, S.eq(inpValid,S.constant(i-1,types.uint(8))) } )
    table.insert( readyOut, S.__and( S.index(readyDownstream,i-1),  S.eq(inpValid,S.constant(i-1,types.uint(8)))) )
  end

  local readyOut = foldt( readyOut, function(a,b) return S.__or(a,b) end, "X" )
  readyOut = S.__or(readyOut, S.eq(inpValid, S.constant(#rates, types.uint(8)) ) )

  local printList = {}
  table.insert(printList,inpValid)
  for i=1,#rates do table.insert( printList, S.index(readyDownstream,i-1) ) end
  table.insert(printList,readyOut)
  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple(printList) ) ) end

  res.systolicModule:addFunction( S.lambda("process", inp, S.cast(S.tuple(out),darkroom.lower(res.outputType)) , "process_output", pipelines ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, resetValid ) )

  res.systolicModule:addFunction( S.lambda("ready", readyDownstream, readyOut, "ready" ) )

  return darkroom.newFunction(res)
end

function darkroom.flattenStreams( A, rates, X )
  err( types.isType(A), "A must be type" )
  err( type(rates)=="table", "rates must be table")
  assert( darkroom.isSDFRate(rates) )
  darkroom.expectBasic(A)
  assert(X==nil)

  local res = {kind="flattenStreams", A=A, rates=rates}

  res.inputType = darkroom.HandshakeTmuxed( A, #rates )
  res.outputType = darkroom.Handshake(A)
  res.stateful = false

  local sdfSum = rates[1][1]/rates[1][2]
  for i=2,#rates do sdfSum = sdfSum + (rates[i][1]/rates[i][2]) end
  err(sdfSum==1, "rates must sum to 1")

  for i=1,#rates do
    print("flattenStreams",i,rates[i][1],rates[i][2])
  end

  res.sdfInput = rates
  res.sdfOutput = {{1,1}}

  local struct FlattenStreams { ready:bool, readyDownstream:bool}
  terra FlattenStreams:reset()  end
  terra FlattenStreams:stats( name: &int8 ) end
  terra FlattenStreams:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    valid(out) = (valid(inp)<[#rates])
    data(out) = data(inp)
  end
  terra FlattenStreams:calculateReady( readyDownstream : bool )
    self.readyDownstream = readyDownstream
    self.ready = readyDownstream
  end

  res.terraModule = FlattenStreams

  res.systolicModule = S.moduleConstructor("FlattenStreams_"..#rates):onlyWire(true)

  local resetValid = S.parameter("reset_valid", types.bool() )

  local inp = S.parameter( "process_input", darkroom.lower(res.inputType) )
  local inpData = S.index(inp,0)
  local inpValid = S.index(inp,1)
  local readyDownstream = S.parameter( "ready_downstream", types.bool() )

  local pipelines = {}
  local resetPipelines = {}

  res.systolicModule:addFunction( S.lambda("process", inp, S.tuple{inpData,S.__not(S.eq(inpValid,S.constant(#rates,types.uint(8))))} , "process_output", pipelines ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, resetValid ) )

  res.systolicModule:addFunction( S.lambda("ready", readyDownstream, readyDownstream, "ready" ) )

  return darkroom.newFunction(res)
end

-- takes A to A[T] by duplicating the input
function darkroom.broadcast(A,T)
  darkroom.expectBasic(A)
  err( type(T)=="number", "T should be number")
  local OT = types.array2d(A,T)
  local sinp = S.parameter("inp",A)
  return darkroom.lift("Broadcast_"..T,A,OT,0,
                       terra(inp : &A:toTerraType(), out:&OT:toTerraType() )
                         for i=0,T do (@out)[i] = @inp end
                         end, sinp, S.cast(S.tuple(broadcast(sinp,T)),OT) )
end

-- Takes StatefulHandshake(A) to (StatefulHandshake(A))[N]
-- HACK(?!): when we fan-out a handshake stream, we need to synchronize the downstream modules.
-- (IE if one is ready but the other isn't, we need to stall both).
-- We do that here by modifying the valid bit combinationally!! This could potentially
-- cause a combinationaly loop (validOut depends on readyDownstream) if another later unit does the opposite
-- (readyUpstream depends on validIn). But I don't think we will have any units that do that??
darkroom.broadcastStream = memoize(function(A,N)
  err( types.isType(A), "A must be type")
  darkroom.expectBasic(A)
  err( type(N)=="number", "N must be number")

  local res = {kind="broadcastStream", A=A, N=N, inputType = darkroom.Handshake(A), outputType = types.array2d( darkroom.Handshake(A), N), stateful=false}

  res.sdfInput = {{1,1}}
  res.sdfOutput = broadcast({1,1},N)

  local struct BroadcastStream {ready:bool, readyDownstream:bool[N]}
  terra BroadcastStream:reset() end
  terra BroadcastStream:stats( name: &int8) end
  terra BroadcastStream:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    for i=0,N do
      if self.ready then -- all of readyDownstream are true
        data((@out)[i]) = data(inp)
        valid((@out)[i]) = valid(inp)
      else
        valid((@out)[i]) = false
      end
    end
  end
  terra BroadcastStream:calculateReady( readyDownstream : bool[N] )
    self.ready = true
    for i=0,N do
      self.readyDownstream[i] = readyDownstream[i]
      self.ready = self.ready and readyDownstream[i]
    end
  end
  res.terraModule = BroadcastStream

  res.systolicModule = S.moduleConstructor("BroadcastStream_"..tostring(A):gsub('%W','_').."_"..N):onlyWire(true)


  local printStr = "IV %d readyDownstream ["..table.concat(broadcast("%d",N),",").."] ready %d"
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple(broadcast(types.bool(),N+2)), printStr):instantiate("printInst") ) end

  local inp = S.parameter( "process_input", darkroom.lower(res.inputType) )
  local inpData = S.index(inp,0)
  local inpValid = S.index(inp,1)
  local readyDownstream = S.parameter( "ready_downstream", types.array2d(types.bool(),N) )
  local readyDownstreamList = map(range(N), function(i) return S.index(readyDownstream,i-1) end )

  local allReady = foldt( readyDownstreamList, function(a,b) return S.__and(a,b) end, "X" )
  local validOut = S.__and(inpValid,allReady)
  local out = S.tuple(broadcast(S.tuple{inpData, validOut}, N))
  out = S.cast(out, darkroom.lower(res.outputType) )

  local pipelines = {}

  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple( concat(concat({inpValid}, readyDownstreamList),{allReady}) ) ) ) end

  res.systolicModule:addFunction( S.lambda("process", inp, out, "process_output", pipelines ) )

  local resetValid = S.parameter("reset_valid", types.bool() )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", nil, resetValid ) )

  res.systolicModule:addFunction( S.lambda("ready", readyDownstream, allReady, "ready" ) )

  return darkroom.newFunction(res)
                                   end)

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

  darkroom.expectBasic(A)
  if A:isArray() then error("Input to extract stencils must not be array") end

  local res = {kind="extractStencils", type=A, w=w, h=h, xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax }
  res.delay=0
  res.inputType = types.array2d(A,w,h)
  res.outputType = types.array2d(types.array2d(A,xmax-xmin+1,ymax-ymin+1),w,h)
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}

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
  local inp = darkroom.input( g.inputType, g.sdfInput )
  local gvalue = darkroom.apply(name.."_g",g,inp)
  return darkroom.lambda(name,inp,darkroom.apply(name.."_f",f,gvalue))
end

-- output type: {uint16,uint16}[T]
darkroom.posSeq = memoize(function( W, H, T )
  assert(W>0); assert(H>0); assert(T>=1);
  local res = {kind="posSeq", T=T, W=W, H=H }
  res.inputType = types.null()
  res.outputType = types.array2d(types.tuple({types.uint(16),types.uint(16)}),T)
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 0
  local struct PosSeq { x:uint16, y:uint16 }
  terra PosSeq:reset() self.x=0; self.y=0 end
  terra PosSeq:process( out : &darkroom.lower(res.outputType):toTerraType() )
    for i=0,T do 
      (@out)[i] = {self.x,self.y}
      self.x = self.x + 1
      if self.x==W then self.x=0; self.y=self.y+1 end
    end
  end
  res.terraModule = PosSeq

  res.systolicModule = S.moduleConstructor("PosSeq_W"..W.."_H"..H.."_T"..T)
  local posX = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), W-T, T ) ):setInit(0):CE(true):instantiate("posX_posSeq") )
  local posY = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), H-1 ) ):setInit(0):CE(true):instantiate("posY_posSeq") )
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(16),types.uint(16)}, "x %d y %d", true):instantiate("printInst") ) end

  local incY = S.eq( posX:get(), S.constant(W-T,types.uint(16))  ):disablePipelining()

  local out = {S.tuple{posX:get(),posY:get()}}
  for i=1,T-1 do
    table.insert(out, S.tuple{posX:get()+S.constant(i,types.uint(16)),posY:get()})
  end

  local CE = S.CE("CE")
  local pipelines = {}
  table.insert( pipelines, posX:setBy( S.constant(true, types.bool() ) ) )
  table.insert( pipelines, posY:setBy( incY ) )
  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple{posX:get(),posY:get()}) ) end

  res.systolicModule:addFunction( S.lambda("process", S.parameter("pinp",types.null()), S.cast(S.tuple(out),types.array2d(types.tuple{types.uint(16),types.uint(16)},T)), "process_output", pipelines, nil, CE ) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {posX:set(S.constant(0,types.uint(16))), posY:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()), CE) )
  res.systolicModule:complete()

  return darkroom.newFunction(res)
                          end)

-- this takes a pure function f : {{int32,int32}[T],inputType} -> outputType
-- and drives the first tuple with (x,y) coord
-- returns a function with type Stateful(inputType)->Stateful(outputType)
-- sdfOverride: we can use this to define stateful->StatefulV interfaces etc, so we may want to override the default SDF rate
darkroom.liftXYSeq = memoize(function( f, W, H, T, X )
  assert(darkroom.isFunction(f))
  map({W,H,T},function(n) assert(type(n)=="number") end)
  assert(X==nil)

  local inputType = f.inputType.list[2]

  local inp = darkroom.input( inputType )

  local p = darkroom.apply("p", darkroom.posSeq(W,H,T) )
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)
  --local packed = darkroom.apply( "packedtup", darkroom.packTuple({xyType,inputType}), darkroom.tuple("ptup", {p,inp}) )
  local out = darkroom.apply("m", f, darkroom.tuple("ptup", {p,inp}) )
  return darkroom.lambda( "liftXYSeq_"..f.kind, inp, out )
end)

-- this takes a function f : {{uint16,uint16},inputType} -> outputType
-- and returns a function of type inputType[T]->outputType[T]
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
darkroom.cropSeq = memoize(function( A, W, H, T, L, R, B, Top )
  map({W,H,T,L,R,B,Top},function(n) assert(type(n)=="number");err(n>=0,"n<0") end)
  err(T>=1,"cropSeq T<1")

  err( L>=0, "cropSeq, L<0")
  err( R>=0, "cropSeq, R<0")
  err( W%T==0, "cropSeq, W%T~=0")
  err( L%T==0, "cropSeq, L%T~=0")
  err( R%T==0, "cropSeq, R%T~=0")
  err( (W-L-R)%T==0, "cropSeq, (W-L-R)%T~=0")

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

  local f = darkroom.lift( "CropSeq_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T), innerInputType, outputType, 0, 
                           terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
                             var x,y = (inp._0)[0]._0, (inp._0)[0]._1
                             data(out) = inp._1
                             valid(out) = (x>=L and y>=B and x<W-R and y<H-Top)
                             if DARKROOM_VERBOSE then cstdio.printf("CROP x %d y %d VO %d\n",x,y,valid(out)) end
                           end, sinp, S.tuple{sdata,svalid}, nil, {{((W-L-R)*(H-B-Top))/T,(W*H)/T}})

  return darkroom.liftXYSeq( f, W, H, T  )
                           end)

-- This is the same as CropSeq, but lets you have L,R not be T-aligned
-- All it does is throws in a shift register to alter the horizontal phase
darkroom.cropHelperSeq = memoize(function( A, W, H, T, L, R, B, Top, X )
  err(X==nil, "cropHelperSeq, too many arguments")
  if L%T==0 and R%T==0 then return darkroom.cropSeq( A, W, H, T, L, R, B, Top ) end

  err( (W-L-R)%T==0, "cropSeqHelper, (W-L-R)%T~=0")

  local RResidual = R%T
  local inp = darkroom.input( types.array2d( A, T ) )
  local out = darkroom.apply( "SSR", darkroom.SSR( A, T, -RResidual, 0 ), inp)
  out = darkroom.apply( "slice", darkroom.slice( types.array2d(A,T+RResidual), 0, T-1, 0, 0), out)
  out = darkroom.apply( "crop", darkroom.cropSeq(A,W,H,T,L+RResidual,R-RResidual,B,Top), out )
  return darkroom.lambda( "cropHelperSeq_W"..W.."_H"..H.."_L"..L.."_R"..R, inp, out )
                                 end)

-- takes an image of size A[W,H] to size A[W+L+R,H+B+Top]. Fills the new pixels with value 'Value'
-- sequentialized to throughput T
darkroom.padSeq = memoize(function( A, W, H, T, L, R, B, Top, Value )
  err( types.isType(A), "A must be a type")
  map({W=W,H=H,T=T,L=L,R=R,B=B,Top=Top},function(n,k) assert(type(n)=="number"); err(n==math.floor(n),"PadSeq non-integer argument "..k..":"..n); err(n>=0,"n<0") end)
  err( A:toLuaType()==type(Value), "Value is incorrect lua type")
  err(T>=1, "padSeq, T<1")

  err( W%T==0, "padSeq, W%T~=0")
  err( L==0 or (L>=T and L%T==0), "padSeq, L<T or L%T~=0 (L="..tostring(L)..",T="..tostring(T)..")")
  err( R==0 or (R>=T and R%T==0), "padSeq, R<T or R%T~=0")
  err( (W+L+R)%T==0, "padSeq, (W+L+R)%T~=0")

  local res = {kind="padSeq", type=A, T=T, L=L, R=R, B=B, Top=Top, value=Value}
  res.inputType = types.array2d(A,T)
  res.outputType = darkroom.RV(types.array2d(A,T))
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{ (W*H)/T, ((W+L+R)*(H+B+Top))/T}}, {{1,1}}
  res.delay=0

  local struct PadSeq {posX:int; posY:int, ready:bool}
  terra PadSeq:reset() self.posX=0; self.posY=0; end
  terra PadSeq:stats(name:&int8) end -- not particularly interesting
  terra PadSeq:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    var interior : bool = (self.posX>=L and self.posX<(L+W) and self.posY>=B and self.posY<(B+H))

    valid(out) = true
    if interior then
      data(out) = @inp
    else
      data(out) = arrayof([A:toTerraType()],[rep(A:valueToTerra(Value),T)])
    end
    
    self.posX = self.posX+T;
    if self.posX==(W+L+R) then
      self.posX=0;
      self.posY = self.posY+1;
    end
--    cstdio.printf("PAD x %d y %d inner %d\n",self.posX,self.posY,inner)
  end
  terra PadSeq:calculateReady()  self.ready = (self.posX>=L and self.posX<(L+W) and self.posY>=B and self.posY<(B+H)) end
  res.terraModule = PadSeq

  res.systolicModule = S.moduleConstructor("PadSeq_W"..W.."_H"..H.."_L"..L.."_R"..R.."_B"..B.."_Top"..Top.."_T"..T..T)


  local posX = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), W+L+R-T, T ) ):CE(true):setInit(0):instantiate("posX_padSeq") ) 
  local posY = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), H+Top+B-1) ):CE(true):setInit(0):instantiate("posY_padSeq") ) 
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(16),types.uint(16),types.bool()}, "x %d y %d ready %d", true ):instantiate("printInst") ) end

  local pinp = S.parameter("process_input", darkroom.lower(res.inputType) )
  local pvalid = S.parameter("process_valid", types.bool() )

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

  local ValueBroadcast = S.cast( S.tuple(broadcast(S.constant(Value,A),T)) ,types.array2d(A,T))
  local ConstTrue = S.constant(true,types.bool())
  --local ConstFalse = S.constant(false,types.bool())
  --local border = S.select(S.ge(posY:get(),S.constant(H+Top+B,types.uint(16))),S.tuple{ValueBroadcast,ConstFalse},S.tuple{ValueBroadcast,ConstTrue})
  local out = S.select( readybit, pinp, ValueBroadcast )

  if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process( S.tuple{ posX:get(), posY:get(), readybit } ) ) end

  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", pinp, S.tuple{out,ConstTrue}, "process_output", pipelines, pvalid, CE) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {posX:set(S.constant(0,types.uint(16))), posY:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()), CE) )

  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), readybit, "ready", {} ) )

  return darkroom.waitOnInput(darkroom.newFunction(res))
                          end)


--StatefulRV. Takes A[inputRate,H] in, and buffers to produce A[outputRate,H]
darkroom.changeRate = memoize(function(A, H, inputRate, outputRate, X)
  err( types.isType(A), "A should be a type")
  err( type(H)=="number", "H should be number")
  err( type(inputRate)=="number", "inputRate should be number")
  err( inputRate==math.floor(inputRate), "inputRate should be integer")
  err( type(outputRate)=="number", "outputRate should be number")
  err( outputRate==math.floor(outputRate), "outputRate should be integer")
  assert(X==nil)

  local maxRate = math.max(inputRate,outputRate)

  err( maxRate % inputRate == 0, "maxRate % inputRate ~= 0")
  err( maxRate % outputRate == 0, "maxRate % outputRate ~=0")
  darkroom.expectBasic(A)

  local inputCount = maxRate/inputRate
  local outputCount = maxRate/outputRate

  local res = {kind="changeRate", type=A, inputRate=inputRate, outputRate=outputRate}
  res.inputType = types.array2d(A,inputRate,H)
  res.outputType = darkroom.RV(types.array2d(A,outputRate,H))
  res.stateful = true
  res.delay = (math.log(maxRate/inputRate)/math.log(2)) + (math.log(maxRate/outputRate)/math.log(2))

  if inputRate>outputRate then -- 8 to 4
    res.sdfInput, res.sdfOutput = {{outputRate,inputRate}},{{1,1}}
  else -- 4 to 8
    res.sdfInput, res.sdfOutput = {{1,1}},{{inputRate,outputRate}}
  end

  local struct ChangeRate { buffer : (A:toTerraType())[maxRate*H]; phase:int, ready:bool}

  terra ChangeRate:stats(name:&int8) end
  res.systolicModule = S.moduleConstructor("ChangeRate_"..tostring(A).."_from"..inputRate.."_to"..outputRate.."_H"..H)
  local svalid = S.parameter("process_valid", types.bool() )
  local rvalid = S.parameter("reset", types.bool() )
  local pinp = S.parameter("process_input", darkroom.lower(res.inputType) )

  local regs = map( range(maxRate), function(i) return res.systolicModule:add(S.module.reg(A,true):instantiate("Buffer_"..i)) end )

  if inputRate>outputRate then
    terra ChangeRate:reset() self.phase = 0; end
    terra ChangeRate:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
      if DARKROOM_VERBOSE then cstdio.printf("CHANGE_DOWN phase %d\n", self.phase) end
      if self.phase==0 then
        for y=0,H do
          for i=0,inputRate do self.buffer[i+y*inputRate] = (@inp)[i+y*inputRate] end
        end
      end

      for y=0,H do
        for i=0,outputRate do (data(out))[i+y*outputRate] = self.buffer[i+self.phase*outputRate+y*inputRate] end
      end
      valid(out) = true

      self.phase = self.phase + 1
      if  self.phase>=outputCount then self.phase=0 end

      if DARKROOM_VERBOSE then cstdio.printf("CHANGE_DOWN OUT validOut %d\n",valid(out)) end
    end
    terra ChangeRate:calculateReady()  self.ready = (self.phase==0) end

    -- 8 to 4
    local shifterReads = {}
    for i=0,outputCount-1 do
      table.insert(shifterReads, S.slice( pinp, i*outputRate, (i+1)*outputRate-1, 0, H-1 ) )
    end
    local out, pipelines, resetPipelines, ready = fpgamodules.addShifterSimple( res.systolicModule, shifterReads, DARKROOM_VERBOSE )

    local CE = S.CE("CE")
    res.systolicModule:addFunction( S.lambda("process", pinp, S.tuple{ out, S.constant(true,types.bool()) }, "process_output", pipelines, svalid, CE) )
    res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, rvalid, CE ) )
    res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), ready, "ready", {} ) )

  else -- inputRate <= outputRate. 4 to 8
    assert(H==1) -- NYI
    terra ChangeRate:reset() self.phase = 0; end
    terra ChangeRate:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
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

      if DARKROOM_VERBOSE then cstdio.printf("CHANGE RATE RET validout %d inputPhase %d\n",valid(out),self.phase) end
    end
    terra ChangeRate:calculateReady()  self.ready = true end

    local sPhase = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), inputCount-1) ):CE(true):instantiate("phase_changerateup") )
    local printInst
    if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(16),types.array2d(A,outputRate)}, "phase %d buffer %h", true ):instantiate("printInst") ) end
    local ConstTrue = S.constant(true,types.bool())
    local CE = S.CE("CE")
    res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", { sPhase:set(S.constant(0,types.uint(16))) }, rvalid, CE ) )

    -- in the first cycle (first time inputPhase==0), we don't have any data yet. Use the sWroteLast variable to keep track of this case
    local validout = S.eq(sPhase:get(),S.constant(inputCount-1,types.uint(16))):disablePipelining()

    local out = concat2dArrays(map(range(inputCount-1,0), function(i) return pinp(i) end))
    local pipelines = {sPhase:setBy(ConstTrue)} 
    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(S.tuple{sPhase:get(),out})) end

    res.systolicModule:addFunction( S.lambda("process", pinp, S.tuple{out,validout}, "process_output", pipelines, svalid, CE) )
    res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), ConstTrue, "ready" ) )
  end

  res.terraModule = ChangeRate

  return darkroom.waitOnInput(darkroom.newFunction(res))
end)

darkroom.linebuffer = memoize(function( A, w, h, T, ymin )
  assert(w>0); assert(h>0);
  assert(ymin<=0)
  
  -- if W%T~=0, then we would potentially have to do two reads on wraparound. So don't allow this case.
  err( w%T==0, "Linebuffer error, W%T~=0")

  local res = {kind="linebuffer", type=A, T=T, w=w, h=h, ymin=ymin }
  darkroom.expectBasic(A)
  res.inputType = types.array2d(A,T)
  res.outputType = types.array2d(A,T,-ymin+1)
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 0
  local struct Linebuffer { SR: simmodules.shiftRegister( A:toTerraType(), w*(-ymin)+T, "linebuffer")}
  terra Linebuffer:reset() self.SR:reset() end
  terra Linebuffer:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    -- pretend that this happens in one cycle (delays are added later)
    for i=0,[T] do
      self.SR:pushBack( &(@inp)[i] )
    end

    for y=[ymin],1 do
      for x=[-T+1],1 do
        var outIdx = (y-ymin)*T+(x+T-1)
        var peekIdx = x+y*[w]
        --cstdio.printf("ASSN x %d  y %d outidx %d peekidx %d size %d\n",x,y,outIdx,peekIdx,w*(-ymin)+T)
        (@out)[outIdx] = @(self.SR:peekBack(peekIdx))
      end
    end

  end
  res.terraModule = Linebuffer

  res.systolicModule = S.moduleConstructor("linebuffer_w"..w.."_h"..h.."_T"..T.."_ymin"..ymin.."_A"..tostring(A))
  local sinp = S.parameter("process_input", darkroom.lower(res.inputType) )
  local addr = res.systolicModule:add( S.module.regBy( types.uint(16), fpgamodules.incIfWrap( types.uint(16), (w/T)-1), true, nil ):instantiate("addr") )

  local outarray = {}
  local evicted

  local bits = darkroom.lower(res.inputType):verilogBits()
  local bytes = nearestPowerOf2(upToNearest(8,bits)/8)
  local sizeInBytes = nearestPowerOf2((w/T)*bytes)
  --local init = map(range(0,sizeInBytes-1), function(i) return i%256 end)  
  local bramMod = S.module.bramSDP( true, sizeInBytes, bytes, nil, nil, true )
  local addrbits = math.log(sizeInBytes/bytes)/math.log(2)

  for y=0,-ymin do
    local lbinp = evicted
    if y==0 then lbinp = sinp end
    for x=1,T do outarray[x+(-ymin-y)*T] = S.index(lbinp,x-1) end

    if y<-ymin then
      -- last line doesn't need a ram
      local BRAM = res.systolicModule:add( bramMod:instantiate("lb_m"..math.abs(y)) )

      local upcast = S.cast(lbinp,types.bits(bits))
      upcast = S.cast(upcast,types.bits(bytes*8))

      evicted = BRAM:writeAndReturnOriginal( S.tuple{ S.cast(addr:get(),types.uint(addrbits)), upcast} )
      evicted = S.bitSlice(evicted,0,bits-1)
      evicted = S.cast( evicted, darkroom.lower(res.inputType) )
    end
  end

  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple( outarray ), darkroom.lower(res.outputType) ), "process_output", {addr:setBy(S.constant(true, types.bool()))}, nil, CE ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {addr:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()),CE) )

  return darkroom.newFunction(res)
end)

-- xmin, ymin are inclusive
darkroom.SSR = memoize(function( A, T, xmin, ymin )
  map({T,xmin,ymin}, function(i) assert(type(i)=="number") end)
  assert(ymin<=0)
  assert(xmin<=0)
  assert(T>0)
  local res = {kind="SSR", type=A, T=T, xmin=xmin, ymin=ymin }
  res.inputType = types.array2d(A,T,-ymin+1)
  res.outputType = types.array2d(A,T-xmin,-ymin+1)
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay=0
  local struct SSR {SR:(A:toTerraType())[-xmin+T][-ymin+1]}
  terra SSR:reset() end
  terra SSR:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
    for y=0,-ymin+1 do for x=0,-xmin do self.SR[y][x] = self.SR[y][x+T] end end
    for y=0,-ymin+1 do for x=-xmin,-xmin+T do self.SR[y][x] = (@inp)[y*T+(x+xmin)] end end

    -- write to output
    for y=0,-ymin+1 do for x=0,-xmin+T do (@out)[y*(-xmin+T)+x] = self.SR[y][x] end end
  end
  res.terraModule = SSR

  res.systolicModule = S.moduleConstructor("SSR_W"..(-xmin+1).."_H"..(-ymin+1).."_T"..T.."_A"..tostring(A))
  local sinp = S.parameter("inp", darkroom.lower(res.inputType))
  local pipelines = {}
  local SR = {}
  local out = {}
  for y=0,-ymin do 
    SR[y]={}
    local x = -xmin+T-1
    while(x>=0) do
      if x<-xmin-T then
        SR[y][x] = res.systolicModule:add( S.module.reg(A,true):instantiate("SR_x"..x.."_y"..y ) )
        table.insert( pipelines, SR[y][x]:set(SR[y][x+T]:get()) )
        out[y*(-xmin+T)+x+1] = SR[y][x]:get()
      elseif x<-xmin then
        SR[y][x] = res.systolicModule:add( S.module.reg(A,true):instantiate("SR_x"..x.."_y"..y ) )
        table.insert( pipelines, SR[y][x]:set(S.index(sinp,x+(T+xmin),y ) ) )
        out[y*(-xmin+T)+x+1] = SR[y][x]:get()
      else -- x>-xmin
        out[y*(-xmin+T)+x+1] = S.index(sinp,x+xmin,y)
      end

      x = x - 1
    end
  end

  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple( out ), darkroom.lower(res.outputType)), "process_output", pipelines, nil, S.CE("process_CE") ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro" ) )

  return darkroom.newFunction(res)
end)

darkroom.SSRPartial = memoize(function( A, T, xmin, ymin, stride, fullOutput, X )
  assert(T<=1); 
  assert(X==nil)

  if stride==nil then
    local Weach = (-xmin+1)*T
    assert(Weach==math.floor(Weach))
    stride=Weach
  end

  if fullOutput==nil then fullOutput=false end 

  local res = {kind="SSRPartial", type=A, T=T, xmin=xmin, ymin=ymin, stride=stride, fullOutput=fullOutput }
  res.inputType = types.array2d(A,1,-ymin+1)
  res.stateful = true

  if fullOutput then
    res.outputType = darkroom.RV(types.array2d(A,(-xmin+1),-ymin+1))
  else
    res.outputType = darkroom.RV(types.array2d(A,(-xmin+1)*T,-ymin+1))
  end

  res.sdfInput, res.sdfOutput = {{1,1/T}},{{1,1}}
  res.delay=0
  local struct SSRPartial {phase:int; SR:(A:toTerraType())[-xmin+1][-ymin+1]; activeCycles:int; idleCycles:int, ready:bool}
  terra SSRPartial:reset() self.phase=0; self.activeCycles=0;self.idleCycles=0; end
  terra SSRPartial:stats(name:&int8) cstdio.printf("SSRPartial %s T=%f utilization:%f\n",name,[float](T),[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end
  terra SSRPartial:process( inp : &darkroom.lower(res.inputType):toTerraType(), out : &darkroom.lower(res.outputType):toTerraType() )
    var phaseAtStart = self.phase
    --cstdio.printf("SSRPARTIAL phase %d inpValid %d red %d\n",self.phase, valid(inp),self:ready())
    if self.ready then
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

    var W : int = [(-xmin+1)*T]
    var Wtotal = -xmin+1
    if fullOutput then W = Wtotal end
    for y=0,-ymin+1 do for x=0,W do data(out)[y*W+x] = self.SR[y][fixedModulus(x+phaseAtStart*stride,Wtotal)] end end
    valid(out)=true
  end
  terra SSRPartial:calculateReady()  self.ready = (self.phase==0) end
  res.terraModule = SSRPartial

  res.systolicModule = S.moduleConstructor("SSRPartial_"..tostring(A):gsub('%W','_').."_T"..tostring(T))
  local sinp = S.parameter("process_input", darkroom.lower(res.inputType) )
  local P = 1/T

  local shiftValues = {}
  local Weach = (-xmin+1)/P -- number of columns in each output

--  for p=P-1,0,-1 do
--    table.insert(shiftValues, concat2dArrays( map( range(Weach-1,0), function(i) return sinp( (p*Weach + i)*P ) end )) )
    --  end

  local W = -xmin+1
  for x=0,W-1 do
    table.insert( shiftValues, sinp( (W-1-x)*P) )
  end

  local shifterOut, shifterPipelines, shifterResetPipelines, shifterReading = fpgamodules.addShifter( res.systolicModule, shiftValues, stride, P, DARKROOM_VERBOSE )

  if fullOutput then
    shifterOut = concat2dArrays( shifterOut )
  else
    shifterOut = concat2dArrays( slice( shifterOut, 1, Weach) )
  end

  local processValid = S.parameter("process_valid",types.bool())
  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ shifterOut, processValid }, "process_output", shifterPipelines, processValid, CE) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", shifterResetPipelines,S.parameter("reset",types.bool()), CE) )
  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), shifterReading, "ready", {} ) )

  return darkroom.newFunction(res)
end)

darkroom.stencilLinebuffer = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax )
  assert(types.isType(A))
  map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T>=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  return darkroom.compose("stencilLinebuffer_A"..(tostring(A):gsub('%W','_')).."_w"..w.."_h"..h.."_xmin"..tostring(math.abs(xmin)).."_ymin"..tostring(math.abs(ymin)), darkroom.SSR( A, T, xmin, ymin), darkroom.linebuffer( A, w, h, T, ymin ) )
end)

darkroom.stencilLinebufferPartial = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax )
  map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T<=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  -- SSRPartial need to be able to stall the linebuffer, so we must do this with handshake interfaces. Systolic pipelines can't stall each other
  return darkroom.compose("stencilLinebufferPartial_A"..tostring(A):gsub('%W','_').."_W"..tostring(w).."_H"..tostring(h), darkroom.liftHandshake(darkroom.waitOnInput(darkroom.SSRPartial( A, T, xmin, ymin ))), darkroom.makeHandshake(darkroom.linebuffer( A, w, h, 1, ymin )) )
                                            end)

-- purely wiring
darkroom.unpackStencil = memoize(function( A, stencilW, stencilH, T )
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
  res.sdfInput, res.sdfOutput = {{1,1}}, {{1,1}}
  res.stateful = false
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

  res.systolicModule = S.moduleConstructor("unpackStencil_W"..tostring(stencilW).."_H"..tostring(stencilH).."_T"..tostring(T))
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

  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple(map(out,function(n) return S.cast( S.tuple(n), types.array2d(A,stencilW,stencilH) ) end)), res.outputType ), "process_output", nil, nil, S.CE("process_CE") ) )
  --res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro" ) )

  return darkroom.newFunction(res)
                                 end)

-- we could construct this out of liftHandshake, but this is a special case for when we don't need a fifo b/c this is always ready
darkroom.makeHandshake = memoize(function( f, tmuxRates )
  assert( darkroom.isFunction(f) )
  local res = { kind="makeHandshake", fn = f, tmuxRates = tmuxRates }

  if tmuxRates~=nil then
    darkroom.expectBasic(f.inputType)
    darkroom.expectBasic(f.outputType)
    res.inputType = darkroom.HandshakeTmuxed( f.inputType, #tmuxRates )
    res.outputType = darkroom.HandshakeTmuxed (f.outputType, #tmuxRates )
    assert( darkroom.isSDFRate(tmuxRates) )
    res.sdfInput, res.sdfOutput = tmuxRates, tmuxRates

    function res:sdfTransfer( I, loc ) 
      err(#I[1]==#tmuxRates, "MakeHandshake: incorrect number of input streams. Is "..(#I[1]).." but expected "..(#tmuxRates) )
      return I 
    end

  else
    darkroom.expectBasic(f.inputType)
    darkroom.expectBasic(f.outputType)
    res.inputType = darkroom.Handshake(f.inputType)
    res.outputType = darkroom.Handshake(f.outputType)
    res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  end

  res.stateful = f.stateful

  local delay = math.max( 1, f.delay )
  --assert(delay>0)
  -- we don't need an input fifo here b/c ready is always true
  local struct MakeHandshake{ delaysr: simmodules.fifo( darkroom.lower(res.outputType):toTerraType(), delay, "makeHandshake"),
                              inner: f.terraModule,
                            ready:bool, readyDownstream:bool}
  terra MakeHandshake:reset() self.delaysr:reset(); self.inner:reset() end
  terra MakeHandshake:stats( name : &int8 )  end
  
  -- if inner function is const, consider input to always be valid
  local innerconst = false
  if tmuxRates==nil then innerconst = f.outputType:const() end

  local validFalse = false
  if tmuxRates~=nil then validFalse = #tmuxRates end

  terra MakeHandshake:process( inp : &darkroom.lower(res.inputType):toTerraType(), 
                               out : &darkroom.lower(res.outputType):toTerraType())

    if self.readyDownstream then
      if DARKROOM_VERBOSE then cstdio.printf("MakeHandshake %s IV %d readyDownstream=true\n",f.kind,valid(inp)) end
      if self.delaysr:size()==delay then
        var ot = self.delaysr:popFront()
        valid(out) = valid(ot)
--        data(out) = data(ot)
        cstring.memcpy( &data(out), &data(ot), [darkroom.lower(f.outputType):sizeof()])
      else
        valid(out)=validFalse
      end

      var tout : darkroom.lower(res.outputType):toTerraType()
      valid(tout) = valid(inp)
      if (valid(inp)~=validFalse) or innerconst then self.inner:process(&data(inp),&data(tout)) end -- don't bother if invalid
      self.delaysr:pushBack(&tout)
    end

  end
  terra MakeHandshake:calculateReady( readyDownstream: bool ) self.ready = readyDownstream; self.readyDownstream = readyDownstream end
  res.terraModule = MakeHandshake

  -- We _NEED_ to set an initial value for the shift register output (invalid), or else stuff downstream can get strange values before the pipe is primed
  res.systolicModule = S.moduleConstructor( "MakeHandshake_"..f.systolicModule.name):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

  local outputCount
  if DARKROOM_VERBOSE then outputCount = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.incIf() ):CE(true):instantiate("outputCount"):setCoherent(false) ) end

  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.bool(),darkroom.extractValid(res.inputType),darkroom.lower(f.outputType), darkroom.extractValid(res.outputType), types.bool(), types.bool(), types.uint(16), types.uint(16)}, "RST %d IV %d O %h OV %d readyDownstream %d ready %d outputCount %d expectedOutput %d"):instantiate("printInst") ) end

  local SRdefault = false
  if tmuxRates~=nil then SRdefault = #tmuxRates end
  local SR = res.systolicModule:add( fpgamodules.shiftRegister( darkroom.extractValid(res.inputType), f.systolicModule:getDelay("process"), SRdefault, true ):instantiate("validBitDelay_"..f.systolicModule.name):setCoherent(false) )
  local inner = res.systolicModule:add(f.systolicModule:instantiate("inner"))
  local pinp = S.parameter("process_input", darkroom.lower(res.inputType) )
  local rst = S.parameter("reset",types.bool())

  local pipelines = {}
  local asstInst = res.systolicModule:add( S.module.assert( "MakeHandshake: input valid bit should not be X!" ,false, false):instantiate("asstInst") )
  pipelines[1] = asstInst:process(S.__not(S.isX(S.index(pinp,1))), S.constant(true,types.bool()) )

  local pready = S.parameter("ready_downstream", types.bool())
  local CE = S.__or(pready,rst)

  local outvalid = SR:pushPop(S.index(pinp,1), S.__not(rst), CE)
  local out = S.tuple({inner:process(S.index(pinp,0),S.index(pinp,1), CE), outvalid})
  if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process( S.tuple{ rst, S.index(pinp,1), S.index(out,0), S.index(out,1), pready, pready, outputCount:get(), S.instanceParameter("OUTPUT_COUNT",types.uint(16)) } ) ) end

  if tmuxRates~=nil then
    if DARKROOM_VERBOSE then table.insert(pipelines,  outputCount:setBy(S.lt(outvalid,S.constant(#tmuxRates,types.uint(8))), S.__not(rst), CE) ) end
  else
    if DARKROOM_VERBOSE then table.insert(pipelines,  outputCount:setBy(outvalid, S.__not(rst), CE) ) end
  end

  res.systolicModule:addFunction( S.lambda("process", pinp, out, "process_output", pipelines) ) 

  local resetOutput
  if f.stateful then resetOutput = inner:reset(nil,rst,CE) end

  local resetPipelines = {}
  table.insert( resetPipelines, SR:reset(nil,rst,CE) )
  if DARKROOM_VERBOSE then table.insert( resetPipelines, outputCount:set(S.constant(0,types.uint(16)),rst,CE) ) end

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), resetOutput, "reset_out", resetPipelines,rst) )

  res.systolicModule:addFunction( S.lambda("ready", pready, pready, "ready" ) )

  return darkroom.newFunction(res)
                                 end)

-- promotes FIFO systolic module to handshake type.
-- In the future, we'd like to make our type system powerful enough to be able to do this...
local function promoteFifo(systolicModule)
  
end

-- nostall: unsafe -> ready always set to true
-- W,H,T: used for debugging (calculating last cycle)
darkroom.fifo = memoize(function( A, size, nostall, W, H, T )
  darkroom.expectBasic(A)
  err( type(size)=="number", "size must be number")
  err( size >0,"size<=0")
  err(nostall==nil or type(nostall)=="boolean", "nostall should be nil or boolean")
  err(W==nil or type(W)=="number", "W should be nil or number")
  err(H==nil or type(H)=="number", "H should be nil or number")
  err(T==nil or type(T)=="number", "T should be nil or number")
  
  local res = {kind="fifo", inputType=darkroom.Handshake(A), outputType=darkroom.Handshake(A), registered=true, sdfInput={{1,1}}, sdfOutput={{1,1}}, stateful=true}

  local struct Fifo { fifo : simmodules.fifo(A:toTerraType(),size,"fifofifo"), ready:bool, readyDownstream:bool }
  terra Fifo:reset() self.fifo:reset() end
  terra Fifo:stats(name:&int8)  end
  terra Fifo:store( inp : &darkroom.lower(res.inputType):toTerraType())
    if DARKROOM_VERBOSE then cstdio.printf("FIFO STORE ready:%d valid:%d\n",self.ready,valid(inp)) end
    -- if ready==false, ignore then input (if it's behaving correctly, the input module will be stalled)
    -- 'ready' argument was the ready value we agreed on at start of cycle. Note this this may change throughout the cycle! That's why we can't just call the :storeReady() method
    if valid(inp) and self.ready then 
      if DARKROOM_VERBOSE then cstdio.printf("FIFO STORE, valid input\n") end
      self.fifo:pushBack(&data(inp)) 
    end
  end
  terra Fifo:load( out : &darkroom.lower(res.outputType):toTerraType())
    if self.readyDownstream then
      if self.fifo:hasData() then
        if DARKROOM_VERBOSE then cstdio.printf("FIFO %d LOAD, hasData. size=%d\n", size, self.fifo:size()) end
        valid(out) = true
        data(out) = @(self.fifo:popFront())
      else
        if DARKROOM_VERBOSE then cstdio.printf("FIFO %d LOAD, no data. sizee=%d\n", size, self.fifo:size()) end
        valid(out) = false
      end
    else
      if DARKROOM_VERBOSE then cstdio.printf("FIFO %d LOAD, not ready. FIFO size: %d\n", size, self.fifo:size()) end
    end
  end
  terra Fifo:calculateStoreReady() self.ready = (self.fifo:full()==false) end
  terra Fifo:calculateLoadReady(readyDownstream:bool) self.readyDownstream = readyDownstream end
  res.terraModule = Fifo

  res.systolicModule = S.moduleConstructor("fifo_"..size.."_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T))

  local fifo = res.systolicModule:add( fpgamodules.fifo(A,size,DARKROOM_VERBOSE):instantiate("FIFO") )
  --------------
  -- basic -> R
  local store = res.systolicModule:addFunction( S.lambdaConstructor( "store", A, "store_input" ) )
  local storeCE = S.CE("store_CE")
  store:setCE(storeCE)
  store:addPipeline( fifo:pushBack( store:getInput() ) )
  --store:setOutput(S.tuple{S.null(),S.constant(true,types.bool(true))}, "store_output")
  local storeReady = res.systolicModule:addFunction( S.lambdaConstructor( "store_ready" ) )
  storeReady:setOutput( fifo:ready(), "store_ready" )
  local storeReset = res.systolicModule:addFunction( S.lambdaConstructor( "store_reset" ) )
  storeReset:setCE(storeCE)
  storeReset:addPipeline(fifo:pushBackReset())
  --------------
  -- basic -> V
  local load = res.systolicModule:addFunction( S.lambdaConstructor( "load", types.null(), "process_input" ) )
  local loadCE = S.CE("load_CE")
  load:setCE(loadCE)
  load:setOutput( S.tuple{fifo:popFront( nil, fifo:hasData() ), fifo:hasData() }, "load_output" )
  local loadReset = res.systolicModule:addFunction( S.lambdaConstructor( "load_reset" ) )
  loadReset:setCE(loadCE)
  loadReset:addPipeline(fifo:popFrontReset())
  --------------
  -- debug
  if W~=nil then
    local outputCount = res.systolicModule:add( S.module.regByConstructor( types.uint(32), fpgamodules.incIfWrap(types.uint(32),((W*H)/T)-1,1) ):CE(true):setInit(0):instantiate("outputCount") )
    load:addPipeline(outputCount:setBy(fifo:hasData()))
    loadReset:addPipeline(outputCount:set(S.constant(0,types.uint(32))))

    local maxSize = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.max(types.uint(16),true) ):CE(true):setInit(0):instantiate("maxSize") ) 
    local printInst = res.systolicModule:add( S.module.print( types.uint(16), "max size %d/"..size, nil, false):instantiate("printInst") )
    load:addPipeline(maxSize:setBy(S.cast(fifo:size(),types.uint(16))))
    local lastCycle = S.eq(outputCount:get(), S.constant(((W*H)/T)-1, types.uint(32))):disablePipelining()
    load:addPipeline(printInst:process(maxSize:get(), lastCycle))
    loadReset:addPipeline(maxSize:set(S.constant(0,types.uint(16))))
  end
  --------------

  res.systolicModule = liftDecimateSystolic(res.systolicModule,{"load"},{"store"})
  res.systolicModule = runIffReadySystolic( res.systolicModule,{"store"},{"load"})
  res.systolicModule = liftHandshakeSystolic( res.systolicModule,{"load","store"},{})

  return darkroom.newFunction(res)
                        end)

function darkroom.lut( inputType, outputType, values )
  err( types.isType(inputType), "inputType must be type")
  darkroom.expectBasic( inputType )
  err( types.isType(outputType), "outputType must be type")
  darkroom.expectBasic( outputType )

  local inputCount = math.pow(2, inputType:verilogBits())
  err( inputCount==#values, "values array has insufficient entries, has "..tonumber(#values).." but should have "..tonumber(inputCount))

  local res = {kind="lut", inputType=inputType, outputType=outputType, values=values, stateful=false }
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 1

  local struct LUTModule { lut : (outputType:toTerraType())[inputCount] }
  terra LUTModule:reset() self.lut = arrayof([outputType:toTerraType()], values) end
  terra LUTModule:process( inp:&inputType:toTerraType(), out:&outputType:toTerraType())
    @out = self.lut[@inp]
  end
  res.terraModule = LUTModule

  res.systolicModule = S.moduleConstructor("LUT")
  local lut = res.systolicModule:add( systolic.module.bramSDP(true, inputCount*(outputType:verilogBits()/8), inputType:verilogBits()/8, outputType:verilogBits()/8, values, true ):instantiate("LUT") )

  local sinp = S.parameter("process_input", res.inputType )

  local pipelines = {}
  table.insert(pipelines, lut:writeAndReturnOriginal( S.tuple{sinp,S.constant(0,types.bits(inputType:verilogBits()))},S.constant(false,types.bool())) ) -- needs to be driven, but set valid==false
  res.systolicModule:addFunction( S.lambda("process",sinp, S.cast(lut:read(sinp),outputType), "process_output", pipelines, nil, S.CE("process_CE") ) )

  return darkroom.newFunction(res)
end

darkroom.reduce = memoize(function( f, W, H )
  if darkroom.isFunction(f)==false then error("Argument to reduce must be a darkroom function") end
  err(type(W)=="number", "reduce W must be number")
  err(type(H)=="number", "reduce H must be number")

  local res = {kind="reduce", fn = f}
  darkroom.expectBasic(f.inputType)
  darkroom.expectBasic(f.outputType)
  if f.inputType:isTuple()==false or f.inputType~=types.tuple({f.outputType,f.outputType}) then
    err("Reduction function f must be of type {A,A}->A, but is "..tostring(f.inputType).." -> "..tostring(f.outputType))
  end
  res.inputType = types.array2d( f.outputType, W, H )
  res.outputType = f.outputType
  res.stateful = f.stateful
  if f.stateful then print("WARNING: reducing with a stateful function - are you sure this is what you want to do?") end

  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = math.ceil(math.log(res.inputType:channels())/math.log(2))*f.delay
  local struct ReduceModule { inner: f.terraModule }
  terra ReduceModule:reset() self.inner:reset() end

  -- the execution order needs to match the hardware
  local inp = symbol( &res.inputType:toTerraType() )
  local mself = symbol( &ReduceModule )
  local t = map(range(0,W*H-1), function(i) return `(@inp)[i] end )

  local foldout = foldt(t, function(a,b) return quote 
    var tinp : f.inputType:toTerraType() = {a,b}
    var tout : f.outputType:toTerraType()
    mself.inner:process(&tinp,&tout)
    in tout end end )

  ReduceModule.methods.process = terra( [mself], [inp], out : &res.outputType:toTerraType() )
--      var res : res.outputType:toTerraType() = (@inp)[0]
--      for i=1,W*H do
--        var tinp : f.inputType:toTerraType() = {res, (@inp)[i]}
--        self.inner:process( &tinp, &res  )
--      end
--      @out = res
    @out = foldout
  end
  res.terraModule = ReduceModule

  res.systolicModule = S.moduleConstructor("reduce_"..f.systolicModule.name.."_W"..tostring(W).."_H"..tostring(H))
  local resetPipelines = {}
  local sinp = S.parameter("process_input", res.inputType )
  local t = map( range2d(0,W-1,0,H-1), function(i) return S.index(sinp,i[1],i[2]) end )

  local i=0
  local expr = foldt(t, function(a,b) 
                       local I = res.systolicModule:add(f.systolicModule:instantiate("inner"..i))
                       --table.insert( resetPipelines, I:reset() ) -- no reset for pure functions
                       i = i + 1
                       return I:process(S.tuple{a,b}) end, nil )
  res.systolicModule:addFunction( S.lambda( "process", sinp, expr, "process_output", nil, nil, S.CE("process_CE") ) )

  return darkroom.newFunction( res )
end)


darkroom.reduceSeq = memoize(function( f, T )
  err(T<=1, "reduceSeq T>1")

  if f.inputType:isTuple()==false or f.inputType~=types.tuple({f.outputType,f.outputType}) then
    err("Reduction function f must be of type {A,A}->A, "..loc)
  end

  local res = {kind="reduceSeq", fn=f}
  darkroom.expectBasic(f.outputType)
  res.inputType = f.outputType
  res.outputType = darkroom.V(f.outputType)
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1/T}}
  res.stateful = true
  err( f.delay==0, "reduceSeq, function must be asynchronous (0 cycle delay)")
  res.delay = 0
  local struct ReduceSeq { phase:int; result : f.outputType:toTerraType(); inner : f.terraModule}
  terra ReduceSeq:reset() self.phase=0; self.inner:reset() end
  terra ReduceSeq:process( inp : &f.outputType:toTerraType(), out : &darkroom.lower(res.outputType):toTerraType())
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

  local del = f.systolicModule:getDelay("process")
  err( del == 0, "ReduceSeq function must have delay==0 but instead has delay of "..del )

  res.systolicModule = S.moduleConstructor("ReduceSeq_"..f.systolicModule.name.."_T"..tostring(1/T))
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(16),f.outputType,f.outputType}, "ReduceSeq "..f.systolicModule.name.." phase %d input %d output %d", true):instantiate("printInst") ) end
  local sinp = S.parameter("process_input", f.outputType )
  local svalid = S.parameter("process_valid", types.bool() )
  --local phaseValue, phaseValid, phasePipelines, phaseResetPipelines = fpgamodules.addPhaser( res.systolicModule, 1/T, svalid )
  local phase = res.systolicModule:add( S.module.regByConstructor( types.uint(16), fpgamodules.sumwrap(types.uint(16), (1/T)-1 ) ):CE(true):instantiate("phase") )
  
  local pipelines = {}
  table.insert(pipelines, phase:setBy( S.constant(1,types.uint(16)) ) )

  local out
  
  if T==1 then
    -- hack: Our reduce fn always adds two numbers. If we only have 1 number, it won't work! just return the input.
    out = sinp
  else
    local sResult = res.systolicModule:add( S.module.regByConstructor( f.outputType, f.systolicModule ):CE(true):instantiate("result") )
    table.insert( pipelines, sResult:set( sinp, S.eq(phase:get(), S.constant(0, types.uint(16) ) ):disablePipelining() ) )
    out = sResult:setBy( sinp, S.__not(S.eq(phase:get(), S.constant(0, types.uint(16) ) )):disablePipelining() )
  end

  if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process( S.tuple{phase:get(),sinp,out} ) ) end

  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ out, S.eq(phase:get(), S.constant( (1/T)-1, types.uint(16))) }, "process_output", pipelines, svalid, CE) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(16)))}, S.parameter("reset",types.bool()),CE) )

  return darkroom.newFunction( res )
    end)

-- surpresses output if we get more then _count_ inputs
darkroom.overflow = memoize(function( A, count )
  darkroom.expectBasic(A)

  assert(count<2^32-1)

  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="overflow", A=A, inputType=A, outputType=darkroom.V(A), stateful=true, count=count, sdfInput={{1,1}}, sdfOutput={{1,1}}, delay=0}
  local struct Overflow {cnt:int}
  terra Overflow:reset() self.cnt=0 end
  terra Overflow:process( inp : &A:toTerraType(), out:&darkroom.lower(res.outputType):toTerraType())
    data(out) = @inp
    valid(out) = (self.cnt<count)
    self.cnt = self.cnt+1
  end
  res.terraModule = Overflow
  res.systolicModule = S.moduleConstructor("Overflow_"..count)
  local cnt = res.systolicModule:add( S.module.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32))):CE(true):instantiate("cnt") )

  local sinp = S.parameter("process_input", A )
  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ sinp, S.lt(cnt:get(), S.constant( count, types.uint(32))) }, "process_output", {cnt:setBy(S.constant(true,types.bool()))}, nil, CE ) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {cnt:set(S.constant(0,types.uint(32)))}, S.parameter("reset",types.bool()), CE) )

  return darkroom.newFunction( res )
                            end)

-- provides fake output if we get less then _count_ inputs after _cyclecount_ cycles
-- if thing thing is done before tooSoonCycles, throw an assert
darkroom.underflow = memoize(function( A, count, cycles, upstream, tooSoonCycles )
  darkroom.expectBasic(A)
  assert(type(count)=="number")
  assert(type(cycles)=="number")
  err(cycles==math.floor(cycles),"cycles must be an integer")
  assert(type(upstream)=="boolean")

  assert(count<2^32-1)
  err(cycles<2^32-1,"cycles >32 bit:"..tostring(cycles))

  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="underflow", A=A, inputType=darkroom.Handshake(A), outputType=darkroom.Handshake(A), stateful=true, count=count, sdfInput={{1,1}}, sdfOutput={{1,1}}, delay=0}

  local struct Underflow {ready:bool; readyDownstream:bool;cycles:uint32; outputCount:uint32}
  terra Underflow:reset() self.cycles=0; self.outputCount=0 end
  terra Underflow:process( inp : &darkroom.lower(res.inputType):toTerraType(), out:&darkroom.lower(res.outputType):toTerraType())
    @out = @inp
  end
  terra Underflow:calculateReady(readyDownstream:bool) self.ready = readyDownstream; self.readyDownstream=readyDownstream end
  terra Underflow:stats(name:&int8) end
  res.terraModule = Underflow

  res.systolicModule = S.moduleConstructor( "Underflow_A"..tostring(A).."_count"..count.."_cycles"..cycles.."_toosoon"..tostring(tooSoonCycles).."_US"..tostring(upstream)):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(32),types.uint(32),types.bool()}, "outputCount %d cycleCount %d outValid"):instantiate("printInst") ) end

  local outputCount = res.systolicModule:add( S.module.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32)) ):CE(true):instantiate("outputCount"):setCoherent(false) )

  -- NOTE THAT WE Are counting cycles where downstream_ready == true
  local cycleCount = res.systolicModule:add( S.module.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32)) ):CE(true):instantiate("cycleCount"):setCoherent(false) )

  local rst = S.parameter("reset",types.bool())

  local pinp = S.parameter("process_input", darkroom.lower(res.inputType) )
  local pready = S.parameter("ready_downstream", types.bool())
  local pvalid = S.index(pinp,1)
  local pdata = S.index(pinp,0)

  local fixupMode = S.gt(cycleCount:get(),S.constant(cycles,types.uint(32)))

  local CE = S.__or(pready,rst)
  local CE_cycleCount = CE  
  if upstream then  
    CE = S.__or(CE,fixupMode) 
    CE_cycleCount = S.constant(true,types.bool())
  end

  local pipelines = {}
  table.insert( pipelines, outputCount:setBy(S.__and(pready,S.__or(pvalid,fixupMode)), S.__not(rst), CE) )
  table.insert( pipelines, cycleCount:setBy(S.constant(true,types.bool()), S.__not(rst), CE_cycleCount) )

  local outData
  if A:verilogBits()==0 then
    outData = pdata
  else
    outData = S.select(fixupMode,S.cast(S.constant(math.min(3735928559,math.pow(2,A:verilogBits())-1),types.bits(A:verilogBits())),A),pdata)
  end

  local outValid = S.__or(S.__and(fixupMode,S.lt(outputCount:get(),S.constant(count,types.uint(32)))),S.__and(S.__not(fixupMode),pvalid))
  outValid = S.__and(outValid,S.__not(rst))

  if tooSoonCycles~=nil then
    local asstInst = res.systolicModule:add( S.module.assert( "pipeline completed eariler than expected", true, false ):instantiate("asstInst") )
    local tooSoon = S.eq(cycleCount:get(),S.constant(tooSoonCycles,types.uint(32)))
    tooSoon = S.__and(tooSoon,S.ge(outputCount:get(),S.constant(count,types.uint(32))))
    table.insert( pipelines, asstInst:process(S.__not(tooSoon),S.__not(rst),CE) )

    -- ** throw in valids to mess up result
    -- just raising an assert doesn't work b/c verilog is dumb
    outValid = S.__or(outValid,tooSoon)
  end

  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple{outputCount:get(),cycleCount:get(),outValid}) ) end

  res.systolicModule:addFunction( S.lambda("process", pinp, S.tuple{outData,outValid}, "process_output", pipelines) ) 

  local resetPipelines = {}
  table.insert( resetPipelines, outputCount:set(S.constant(0,types.uint(32)),rst,CE) )
  table.insert( resetPipelines, cycleCount:set(S.constant(0,types.uint(32)),rst,CE_cycleCount) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "reset_out", resetPipelines,rst) )

  local readyOut = pready
  if upstream then
    readyOut = S.__or(pready,fixupMode)
  end

  res.systolicModule:addFunction( S.lambda("ready", pready, readyOut, "ready" ) )

  return darkroom.newFunction( res )
    end)


-- record the # of cycles needed to complete the computation, and write it into the last axi burst
darkroom.cycleCounter = memoize(function( A, count )
  darkroom.expectBasic(A)
  assert(type(count)=="number")

  assert(count<2^32-1)

    -- # of cycles we need to write out metadata
  local padCount = (128*8) / A:verilogBits()

  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="cycleCounter", A=A, inputType=darkroom.Handshake(A), outputType=darkroom.Handshake(A), stateful=true, count=count, sdfInput={{count,count+padCount}}, sdfOutput={{1,1}}, delay=0}

  local struct CycleCounter {ready:bool; readyDownstream:bool; cycles:uint32; outputCount:uint32}
  terra CycleCounter:reset() self.cycles=0; self.outputCount=0 end
  terra CycleCounter:process( inp : &darkroom.lower(res.inputType):toTerraType(), out:&darkroom.lower(res.outputType):toTerraType())
    @out = @inp
  end
  terra CycleCounter:calculateReady(readyDownstream:bool) self.ready = readyDownstream; self.readyDownstream=readyDownstream end
  terra CycleCounter:stats(name:&int8) end
  res.terraModule = CycleCounter

  res.systolicModule = S.moduleConstructor( "CycleCounter_A"..tostring(A).."_count"..count ):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(32),types.uint(32),types.bool(),types.bool()}, "cycleCounter outputCount %d cycleCount %d outValid %d metadataMode %d"):instantiate("printInst") ) end

  local outputCount = res.systolicModule:add( S.module.regByConstructor( types.uint(32), fpgamodules.incIfWrap(types.uint(32),count+padCount-1,1) ):CE(true):instantiate("outputCount"):setCoherent(false) )
  local cycleCount = res.systolicModule:add( S.module.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32),false) ):CE(false):instantiate("cycleCount"):setCoherent(false) )

  local rst = S.parameter("reset",types.bool())

  local pinp = S.parameter("process_input", darkroom.lower(res.inputType) )
  local pready = S.parameter("ready_downstream", types.bool())
  local pvalid = S.index(pinp,1)
  local pdata = S.index(pinp,0)

  local done = S.ge(outputCount:get(),S.constant(count,types.uint(32)))
--  assert( (128*8) / A:verilogBits() == 16 )
--  local metadataNotDone = S.lt(outputCount:get(),S.constant(count+32,types.uint(32)))
--  local metadataMode = S.__and(done,metadataNotDone)
  local metadataMode = done

  local CE = S.__or(pready,rst)

  local pipelines = {}
  table.insert( pipelines, outputCount:setBy(S.__and(pready,S.__or(pvalid,metadataMode)), S.__not(rst), CE) )
  table.insert( pipelines, cycleCount:setBy(S.__not(done), S.__not(rst)) )

  local outData

  if padCount == 16 then
    local cycleOutput = S.tuple{cycleCount:get(),cycleCount:get()}
    cycleOutput = S.cast(cycleOutput, types.bits(A:verilogBits()))
    outData = S.select(metadataMode,S.cast(cycleOutput,A),pdata)
  else
    -- degenerate case: not axi bus size. Just return garbage
    outData = S.select(metadataMode,S.cast(S.constant(0,types.bits(A:verilogBits())),A),pdata)
  end

  local outValid = S.__or(metadataMode,pvalid)
  outValid = S.__and(outValid,S.__not(rst))

  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple{outputCount:get(),cycleCount:get(),outValid,metadataMode}) ) end

  res.systolicModule:addFunction( S.lambda("process", pinp, S.tuple{outData,outValid}, "process_output", pipelines) ) 

  local resetPipelines = {}
  table.insert( resetPipelines, outputCount:set(S.constant(0,types.uint(32)),rst,CE) )
  table.insert( resetPipelines, cycleCount:set(S.constant(0,types.uint(32)),rst) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "reset_out", resetPipelines,rst) )

  local readyOut = S.__and(pready,S.__not(metadataMode))

  res.systolicModule:addFunction( S.lambda("ready", pready, readyOut, "ready" ) )

  return darkroom.newFunction( res )
    end)

-- function argument
function darkroom.input( type, sdfRate )
  err( types.isType( type ), "darkroom.input: first argument should be type" )
  assert( sdfRate==nil or darkroom.isSDFRate(sdfRate))
  if sdfRate==nil then sdfRate={{1,1}} end
  return darkroom.newIR( {kind="input", type = type, name="input", id={}, inputs={}, sdfRate=sdfRate, loc=getloc()} )
end

function callOnEntries( T, fnname )
  local TS = symbol(&T,"self")
  local ssStats = {}
  for k,v in pairs( T.entries ) do if v.type:isstruct() then table.insert( ssStats, quote TS.[v.field]:[fnname]() end) end end
  T.methods[fnname] = terra([TS]) [ssStats] end
end

-- this takes in a darkroom IR graph and normalizes the input SDF rate so that
-- it obeys our constraints: (1) neither input or output should have bandwidth (token count) > 1
-- and (2) no node should have SDF rate > 1
local function lambdaSDFNormalize(input,output)
  local sdfMaxRate = output:sdfExtremeRate(true)
  err(fracToNumber(sdfMaxRate)>=1, "sdf max rate is <1?")

  if input.sdfRate~=nil then
    err(darkroom.isSDFRate(input.sdfRate),"SDF input rate is not a valid SDF rate")
    --local sdfInputSum = sdfSum(input.sdfRate)
    for k,v in pairs(input.sdfRate) do
      err(v=="x" or v[1]/v[2]<=1, "error, lambda declared with input BW > 1")
    end
  end

  local outputBW = output:sdfTotal(output)
  local outputBW = sdfSum(outputBW)

  -- we will be limited by either the output BW, or max rate. Normalize to the largest of these.
  -- we already checked that the input is <1, so that won't limit us.
  local scaleFactor

  if fracToNumber(sdfMaxRate) > fracToNumber(outputBW) then
    scaleFactor = fracInvert(sdfMaxRate)
  else
    scaleFactor = fracInvert(outputBW)
  end

  if DARKROOM_VERBOSE then print("NORMALIZE, sdfMaxRate",fracToNumber(sdfMaxRate),"outputBW", fracToNumber(outputBW), "scaleFactor",fracToNumber(scaleFactor)) end

  local newInput
  local newOutput = output:process(
    function(n,orig)
      if n.kind=="input" then
        assert(n.id==input.id)
        n.sdfRate = sdfMultiply(n.sdfRate,scaleFactor[1],scaleFactor[2])
        assert(darkroom.isSDFRate(n.sdfRate))
        newInput = darkroom.newIR(n)
        return newInput
      end
      end)

  return newInput, newOutput
end

-- function definition
-- output, inputs
function darkroom.lambda( name, input, output, instances, pipelines, X )
  if DARKROOM_VERBOSE then print("lambda start '"..name.."'") end

  assert(X==nil)
  assert( type(name) == "string" )
  assert( darkroom.isIR( input ) )
  assert( input.kind=="input" )
  assert( darkroom.isIR( output ) )
  assert( instances==nil or type(instances)=="table")
  if instances~=nil then map( instances, function(n) assert(darkroom.isInstance(n)) end ) end
  assert( pipelines==nil or type(pipelines)=="table")
  if pipelines~=nil then map( pipelines, function(n) assert(darkroom.isIR(n)) end ) end


  local output = output:typecheck()

  input, output = lambdaSDFNormalize(input,output)

  local res = {kind = "lambda", name=name, input = input, output = output, instances=instances, pipelines=pipelines }
  res.inputType = input.type
  res.outputType = output.type

  res.stateful=false
  output:visitEach(
    function(n)
      if n.kind=="apply" then
        err( type(n.fn.stateful)=="boolean", "Missing stateful annotation, fn "..n.fn.kind )
        res.stateful = res.stateful or n.fn.stateful
      elseif n.kind=="applyMethod" then
        err( type(n.inst.fn.stateful)=="boolean", "Missing stateful annotation, fn "..n.inst.fn.kind )
        res.stateful = res.stateful or n.inst.fn.stateful
      end
    end)

  if darkroom.isHandshake( input.type ) == false and darkroom.isHandshake(output.type)==false then
  res.delay = output:visitEach(
    function(n, inputs)
      if n.kind=="input" or n.kind=="constant" then
        return 0
      elseif n.kind=="tuple" or n.kind=="array2d" then
        return math.max(unpack(inputs))
      elseif n.kind=="apply" then
        if n.fn.inputType==types.null() then return n.fn.delay
        else return inputs[1] + n.fn.delay end
      else
        print(n.kind)
        assert(false)
      end
    end)
  end

  local function docompile( fn )
    local inputSymbol = symbol( &darkroom.lower(fn.input.type):toTerraType(), "lambdainput" )
    local outputSymbol = symbol( &darkroom.lower(fn.output.type):toTerraType(), "lambdaoutput" )

    local stats = {}
    local resetStats = {}
    local readyStats = {}
    local statStats = {}

    local Module = terralib.types.newstruct("lambda"..fn.name.."_module")
    Module.entries = terralib.newlist( {} )

    local readyInput
    if darkroom.hasReady(fn.output.type) then 
      readyInput = symbol(darkroom.extractReady(fn.output.type):toTerraType(), "readyinput")
      table.insert( Module.entries, {field="ready", type=darkroom.extractReady(fn.input.type):toTerraType()} )
      table.insert( Module.entries, {field="readyDownstream", type=darkroom.extractReady(fn.output.type):toTerraType()} )
    end

    local mself = symbol( &Module, "module self" )

    if fn.instances~=nil then for k,v in pairs(fn.instances) do 
        err(v.fn.terraModule~=nil, "Missing terra module for "..v.fn.kind)
        table.insert( Module.entries, {field=v.name, type=v.fn.terraModule} ) end 
    end

    local readyOutput
    
    -- build ready calculation
    if darkroom.isBasic(fn.output.type)==false then
      fn.output:visitEachReverse(
      function(n, inputs)
        local inputList = {}
        for parentNode,v in pairs(inputs) do
          if parentNode.kind=="selectStream" then
              assert(inputList[parentNode.i+1]==nil)
              inputList[parentNode.i+1] = v[1]
          elseif #parentNode.inputs==1 or (parentNode.kind=="tuple" and parentNode.packStreams==true) then
            table.insert( inputList, v[1] )
          elseif ((parentNode.kind=="array2d" or parentNode.kind=="tuple") and parentNode.packStreams==false) or parentNode.kind=="statements" then
            local idx = v[2]-1
            table.insert( inputList, `[v[1]][idx] )
          else
            -- is there some other way to cross the streams?
            print("KIND",parentNode.kind, parentNode.packStreams)
            assert(false)
          end
        end

        if #inputList~=keycount(inputList) then
          print("Strange downstream list ",n.name)
          for k,v in pairs(inputList) do print("K",k,"V",v) end
          assert(false)
        end

        -- ready bit for this node is AND of all consumers
        local input = foldt( inputList, function(a,b) return `(a and b) end, readyInput )

        local res
        if n.kind=="input" then
          assert(readyOutput==nil)
          readyOutput = input
        elseif n.kind=="apply" then
--          print("systolic ready APPLY",n.fn.kind)
          if darkroom.isHandshake(n.fn.outputType) or  darkroom.isRV(n.fn.inputType) or darkroom.isHandshakeArray(n.fn.outputType) or darkroom.isHandshakeTmuxed(n.fn.outputType) then
            table.insert( readyStats, quote mself.[n.name]:calculateReady(input) end )
            res = `mself.[n.name].ready
          elseif n.fn.outputType:isArray() and darkroom.isHandshake(n.fn.outputType:arrayOver()) then
            table.insert( readyStats, quote mself.[n.name]:calculateReady(array(inputList)) end )
            res = `mself.[n.name].ready
          else
            table.insert( readyStats, quote mself.[n.name]:calculateReady() end )
            res = `mself.[n.name].ready
          end
        elseif n.kind=="applyMethod" then
          if n.fnname=="load" then 
            -- load has nothing upstream, so whatever
            table.insert( readyStats, quote mself.[n.inst.name]:calculateLoadReady(input) end ) 
          elseif n.fnname=="store" then
            -- ready value may change throughout the cycle (as loads happen etc). So we store the agreed upon value and use that
            table.insert( readyStats, quote mself.[n.inst.name]:calculateStoreReady() end ) 
            res = `mself.[n.inst.name].ready
          else
            assert(false)
          end
        elseif n.kind=="tuple" or n.kind=="array2d" then
          if n.packStreams then
            res = input
          else
            assert( keycount(inputs)== 1) -- NYI - multiple consumers - we would need to AND them together for each component
            res = inputList[1]
          end
        elseif n.kind=="statements" then
          local L = {readyInput}
          for i=2,#n.inputs do 
            table.insert( L, `true )
          end
          res = `array(L)
        elseif n.kind=="constant" or n.kind=="extractState" then
        elseif n.kind=="selectStream" then
          res = input
        else
          print(n.kind)
          assert(false)
        end

        return res
      end, true)
    end

    if darkroom.isRV(res.inputType) then
      assert(readyOutput~=nil)
      terra Module.methods.calculateReady( [mself], [readyInput] ) mself.readyDownstream = readyInput; [readyStats]; mself.ready = readyOutput end
    elseif darkroom.isRV(res.outputType) then
      assert(readyOutput~=nil)
      -- notice that we set readyInput to true here. This is kind of a hack to make the code above simpler. This should never actually be read from.
      terra Module.methods.calculateReady( [mself] ) var [readyInput] = true; [readyStats]; mself.ready = readyOutput end
    elseif darkroom.isHandshake(res.outputType) then
      terra Module.methods.calculateReady( [mself], [readyInput] ) mself.readyDownstream = readyInput; [readyStats]; mself.ready = [readyOutput] end
    end

    local out = fn.output:visitEach(
      function(n, inputs)

        --if true then table.insert( stats, quote cstdio.printf([n.name.."\n"]) end ) end

        local out

        if n==fn.output then
          out = outputSymbol
        elseif n.kind=="applyRegStore" then
        elseif n.kind~="input" then
          table.insert( Module.entries, {field="simstateoutput_"..n.name, type=darkroom.lower(n.type):toTerraType()} )
          out = `&mself.["simstateoutput_"..n.name]
        end

        if n.kind=="input" then

          if n.id~=fn.input.id then error("Input node is not the specified input to the lambda") end
          return inputSymbol
        elseif n.kind=="apply" then
          --print("APPLY",n.fn.kind, n.inputs[1].type, n.type)
          --print("APP",n.name, n.fn.terraModule, "inputtype",n.fn.inputType,"outputtype",n.fn.outputType)
          table.insert( Module.entries, {field=n.name, type=n.fn.terraModule} )
          table.insert( resetStats, quote mself.[n.name]:reset() end )
          table.insert( statStats, quote mself.[n.name]:stats([n.name]) end )

          if n.fn.inputType==types.null() then
            table.insert( stats, quote mself.[n.name]:process( out ) end )
          else
            table.insert( stats, quote mself.[n.name]:process( [inputs[1]], out ) end )
          end

          if DARKROOM_VERBOSE then
            if n.type:isArray() and darkroom.isHandshake(n.type:arrayOver()) then
            elseif #n.inputs>0 and darkroom.isHandshake(n.inputs[1].type) then
              table.insert( Module.entries, {field=n.name.."CNT", type=int} )
              table.insert( resetStats, quote mself.[n.name.."CNT"]=0 end )

              table.insert( Module.entries, {field=n.name.."ICNT", type=int} )
              table.insert( resetStats, quote mself.[n.name.."ICNT"]=0 end )

              local readyDownstream = `mself.[n.name].readyDownstream
              local readyThis = `mself.[n.name].ready

              table.insert( stats, quote 
                cstdio.printf("APPLY %s inpvalid %d outvalid %d cnt %d icnt %d ready %d readydownstream %d\n",n.name, valid([inputs[1]]), valid(out), mself.[n.name.."CNT"],mself.[n.name.."ICNT"] , readyThis, readyDownstream);

                if valid(out) and readyDownstream then mself.[n.name.."CNT"]=mself.[n.name.."CNT"]+1 end
                if valid([inputs[1]]) and readyDownstream and readyThis then mself.[n.name.."ICNT"]=mself.[n.name.."ICNT"]+1 end
              end )
            elseif  darkroom.isHandshake(n.type) then
              -- input is not stateful handshake (some type of aggregate)... so we know less stuff
              table.insert( Module.entries, {field=n.name.."CNT", type=int} )
              table.insert( resetStats, quote mself.[n.name.."CNT"]=0 end )

              local readyDownstream = `mself.[n.name].readyDownstream

              table.insert( stats, quote 
                cstdio.printf("APPLY %s inpvalid ? outvalid %d cnt %d icnt ? ready ? readydownstream %d\n",n.name, valid(out), mself.[n.name.."CNT"], readyDownstream);
                if valid(out) and readyDownstream then mself.[n.name.."CNT"]=mself.[n.name.."CNT"]+1 end
              end)
            end
          end

          return out
        elseif n.kind=="applyMethod" then
          if n.fnname=="load" then
            table.insert( statStats, quote mself.[n.inst.name]:stats([n.name]) end )
            table.insert( stats, quote mself.[n.inst.name]:load( out ) end)

            if DARKROOM_VERBOSE then table.insert( stats, quote cstdio.printf("LOAD OUTPUT %s valid:%d readyDownstream:%d\n",n.name, valid(out), mself.[n.inst.name].readyDownstream ) end ) end

            return out
          elseif n.fnname=="store" then
            table.insert( resetStats, quote mself.[n.inst.name]:reset() end )
            if DARKROOM_VERBOSE then table.insert( stats, quote cstdio.printf("STORE INPUT %s valid:%d ready:%d\n",n.name,valid([inputs[1]]), mself.[n.inst.name].ready) end ) end
            table.insert(stats, quote  mself.[n.inst.name]:store( [inputs[1]] ) end )
            return `nil
          else
            assert(false)
          end
        elseif n.kind=="constant" then
          if n.type:isArray() then
            map( n.value, function(m,i) table.insert( stats, quote (@out)[i-1] = m end ) end )
          elseif n.type:isInt() or n.type:isUint() then
            table.insert( stats, quote (@out) = n.value end)
          else
            assert(false)
          end

          return out
        elseif n.kind=="tuple" then
          map(inputs, function(m,i) local ty = darkroom.lower(darkroom.lower(n.type).list[i])
              table.insert(stats, quote cstring.memcpy(&(@out).["_"..(i-1)],[m],[ty:sizeof()]) end) end)
          return out
        elseif n.kind=="array2d" then
          local ty = darkroom.lower(n.type):arrayOver()
          map(inputs, function(m,i) table.insert(stats, quote cstring.memcpy(&((@out)[i-1]),[m],[ty:sizeof()]) end) end)
--table.insert(stats, quote cstdio.printf("VAL %d %d\n",(@out)[0]._1,out[1]._1) end)
          return out
        elseif n.kind=="extractState" then
          return `nil
        elseif n.kind=="catState" then
          table.insert( stats, quote @out = @[inputs[1]] end)
          return out
        elseif n.kind=="statements" then
          table.insert( stats, quote @out = @[inputs[1]] end)
          return inputs[1]
        elseif n.kind=="selectStream" then
          return `&((@[inputs[1]])[n.i])
        else
          print(n.kind)
          assert(false)
        end
      end)

    terra Module.methods.process( [mself], [inputSymbol], [outputSymbol] ) [stats] end
    terra Module.methods.reset( [mself] ) [resetStats] end
    terra Module.methods.stats( [mself], name:&int8 ) [statStats] end

    --if DARKROOM_VERBOSE then Module.methods.process:printpretty(true,false) end
    --if Module.methods.calculateReady~=nil then Module.methods.calculateReady:printpretty(true,false) end

    return Module
  end

  res.terraModule = docompile(res)

  assert(darkroom.isSDFRate(input.sdfRate))
  res.sdfInput = input.sdfRate
  res.sdfOutput = output:sdfTotal(output)

  local isum = sdfSum(res.sdfInput)
  local osum = sdfSum(res.sdfOutput)

  if DARKROOM_VERBOSE then print("LAMBDA",name,"SDF INPUT",res.sdfInput[1][1],res.sdfInput[1][2],"SDF OUTPUT",res.sdfOutput[1][1],res.sdfOutput[1][2]) end

  if (isum[1]/isum[2]<=1 and osum[1]/osum[2]<=1)  then
    -- normal. it is possible for a function to have input AND output rate <1.
    -- for example: pad->decimate. pad won't read every cycle, decimate won't write every cycle
  elseif (isum[1]/isum[2])*#res.sdfOutput == (osum[1]/osum[2])*#res.sdfInput then
    -- this is OK. This is like a packTuple. it takes in 2 streams at rate 1 (sum=2), and produces 1 stream of rate 1 (sum=1)
    -- we normalize by the number of streams. 
--  elseif (osum[1]/osum[2]>1) then
    -- it's impossible to produce more than one output per cycle
--    res.sdfInput = sdfMultiply(res.sdfInput,osum[2],osum[1])
--    res.sdfOutput = sdfMultiply(res.sdfOutput,osum[2],osum[1])
  else
    print("INP",#res.sdfInput,res.sdfInput[1][1],res.sdfInput[1][2])
    print("out",#res.sdfOutput,res.sdfOutput[1][1],res.sdfOutput[1][2])
    err(false, "lambda '"..name.."' has strange SDF rate")
  end

  local function makeSystolic( fn )
    local module = S.moduleConstructor( fn.name ):onlyWire(darkroom.isHandshake(fn.inputType) or darkroom.isHandshake(fn.outputType))

    if darkroom.isHandshake(fn.outputType) then
      module:parameters{INPUT_COUNT=0, OUTPUT_COUNT=0}
    end

    local process = module:addFunction( systolic.lambdaConstructor( "process", darkroom.lower(fn.inputType), "process_input") )
    local reset = module:addFunction( systolic.lambdaConstructor( "reset", types.null(), "resetNILINPUT", "reset") )

    if darkroom.isHandshake(fn.inputType)==false and darkroom.isHandshake(fn.outputType)==false then 
      local CE = S.CE("CE")
      process:setCE(CE)
      reset:setCE(CE)
    end

    if fn.instances~=nil then
      for k,v in pairs(fn.instances) do
        err( systolic.isModule(v.fn.systolicModule), "Missing systolic module for "..v.fn.kind)
        module:add( v.fn.systolicModule:instantiate(v.name) )
      end
    end

    local out = fn.output:codegenSystolic( module )

    assert(systolic.isAST(out[1]))

    err( out[1].type:constSubtypeOf(darkroom.lower(res.outputType)), "Internal error, systolic type is "..tostring(out[1].type).." but should be "..tostring(darkroom.lower(res.outputType)).." function "..name )

    assert(systolic.isFunctionConstructor(process))
    process:setOutput( out[1], "process_output" )

    -- for the non-handshake (purely systolic) modules, the ready bit doesn't flow from outputs to inputs,
    -- it flows from inputs to outputs. The reason is that upstream things can't stall downstream things anyway, so there's really no point of doing it the 'right' way.
    -- this is kind of messed up!
    if darkroom.isRV( fn.inputType ) then
      assert( S.isAST(out[2]) )
      local readyfn = module:addFunction( S.lambda("ready", readyInput, out[2], "ready", {} ) )
    elseif darkroom.isRV( fn.outputType ) then
      local readyfn = module:addFunction( S.lambda("ready", S.parameter("RINIL",types.null()), out[2], "ready", {} ) )
    elseif darkroom.isHandshake( fn.inputType ) or darkroom.isHandshake( fn.outputType )  then
      local readyinp = S.parameter( "ready_downstream", types.bool() )
      local readyout
      local readyPipelines={}
      fn.output:visitEachReverse(
        function(n, inputs)
          local inputList = {}
          for parentNode,v in pairs(inputs) do
            if parentNode.kind=="selectStream" then
              assert(inputList[parentNode.i+1]==nil)
              inputList[parentNode.i+1] = v[1]
            elseif #parentNode.inputs==1 then
              assert(v[2]==1)
              table.insert( inputList, v[1] )
            else
              -- for operators that take in multiple inputs (array, tuple), we force them
              -- to provide an array of valid bits, one per input.
              table.insert( inputList, S.index(v[1],v[2]-1) )
            end
          end

          assert(#inputList==keycount(inputList))
          -- ready bit for this node is AND of all consumers
          local input = foldt( inputList, function(a,b) return S.__and(a,b) end, readyinp )

          if n.kind=="input" then
            assert(readyout==nil)
            readyout = input
            return nil
          elseif n.kind=="apply" then
            --print("systolic ready APPLY",n.fn.kind)
            if n.fn.outputType:isArray() and darkroom.isHandshake(n.fn.outputType:arrayOver()) then
              return module:lookupInstance(n.name):ready(S.cast(S.tuple(inputList),types.array2d(types.bool(),n.fn.outputType:channels())))
            else
              return module:lookupInstance(n.name):ready(input)
            end
          elseif n.kind=="applyMethod" then
            if n.fnname=="load" then
              -- "hack": systolic requires all function to be driven. We don't actually care about load fn ready bit, but drive it anyway
              local inst = module:lookupInstance(n.inst.name)
              local R = inst[n.fnname.."_ready"](inst, input)
              table.insert(readyPipelines,R)
              return R
            elseif n.fnname=="store" then
              local inst = module:lookupInstance(n.inst.name)
              return inst[n.fnname.."_ready"](inst, input)
            else
              assert(false)
            end
          elseif n.kind=="tuple" or n.kind=="array2d" then
            if n.packStreams then
              return input
            else
              -- if packStreams==false, then every thing downstream should expect #n.inputs valid bits
              -- (since we're in reverse, then means that our input is #n.inputs valid bits)
              
              assert( keycount(inputs)== 1) -- NYI - multiple consumers - we would need to AND them together for each component
              return inputList[1]
            end
          elseif n.kind=="statements" then
            local L = {readyinp}
            for i=2,#n.inputs do table.insert(L,S.constant(true,types.bool())) end
            return S.tuple(L)
          elseif n.kind=="selectStream" then
            return input
          else
            print(n.kind)
            assert(false)
          end
        end, true)

      local readyfn = module:addFunction( S.lambda("ready", readyinp, readyout, "ready", readyPipelines ) )
    end

    return module
  end
  res.systolicModule = makeSystolic(res)
  res.systolicModule:toVerilog()

  if DARKROOM_VERBOSE then print("lambda done '"..name.."', size:"..terralib.sizeof(res.terraModule)) end
  return darkroom.newFunction( res )
end

function darkroom.lift( name, inputType, outputType, delay, terraFunction, systolicInput, systolicOutput, systolicInstances, sdfOutput, X )
  err( type(name)=="string", "lift name must be string" )
  assert( types.isType(inputType ) )
  assert( types.isType(outputType ) )
  assert( type(delay)=="number" )
  err( systolic.isAST(systolicOutput), "missing systolic output")
  err(sdfOutput==nil or darkroom.isSDFRate(sdfOutput),"SDF output must be SDF")
  assert(X==nil)

  if sdfOutput==nil then sdfOutput = {{1,1}} end

  local struct LiftModule {}
  terra LiftModule:reset() end
  terra LiftModule:stats( name : &int8 )  end
  terra LiftModule:process(inp:&darkroom.lower(inputType):toTerraType(),out:&darkroom.lower(outputType):toTerraType()) terraFunction(inp,out) end

  err( systolicOutput.type:constSubtypeOf(outputType), "lifted systolic output type does not match. Is "..tostring(systolicOutput.type).." but should be "..tostring(outputType) )

  local systolicModule = S.moduleConstructor(name)

  if systolicInstances~=nil then
    for k,v in pairs(systolicInstances) do systolicModule:add(v) end
  end

  systolicModule:addFunction( S.lambda("process", systolicInput, systolicOutput, "process_output",nil,nil,S.CE("process_CE")) )
  local nip = S.parameter("nip",types.null())
  --systolicModule:addFunction( S.lambda("reset", nip, nil,"reset_output") )
  systolicModule:complete()
  local res = { kind="lift_"..name, inputType = inputType, outputType = outputType, delay=delay, terraModule=LiftModule, systolicModule=systolicModule, sdfInput={{1,1}}, sdfOutput=sdfOutput, stateful=false }
  return darkroom.newFunction( res )
end

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


darkroom.constSeq = memoize(function( value, A, w, h, T, X )
  assert(type(value)=="table")
  assert(type(value[1])=="number")
  assert(#value==w*h)
  assert(X==nil)

--  assert(type(value[1][1])=="number")
  assert(T<=1)
  assert( types.isType(A) )
  assert(type(w)=="number")
  assert(type(h)=="number")

  local res = { kind="constSeq", A = A, w=w, h=h, value=value, T=T}
  res.inputType = types.null()
  local W = w*T
  if W ~= math.floor(W) then error("constSeq T must divide array size, "..loc) end
  res.outputType = types.array2d(A,W,h)
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{1,1}}, {{1,1}}  -- well, technically this produces 1 output for every (nil) input

  res.delay = 0
  local struct ConstSeqState {phase : int; data : (A:toTerraType())[h*W][1/T] }
  local mself = symbol(&ConstSeqState,"mself")
  local initstats = {}
--  map( value, function(m,i) table.insert( initstats, quote mself.data[[(i-1)]][] = m end ) end )
  for C=0,(1/T)-1 do
    for y=0,h-1 do
      for x=0,W-1 do
        table.insert( initstats, quote mself.data[C][y*W+x] = [value[x+y*w+C*W+1]] end )
      end
    end
  end
  terra ConstSeqState.methods.reset([mself]) mself.phase = 0; [initstats] end
  terra ConstSeqState:process( out : &darkroom.lower(res.outputType):toTerraType() )
    @out = self.data[self.phase]
    self.phase = self.phase + 1
    if self.phase == [1/T] then self.phase = 0 end
  end
  res.terraModule = ConstSeqState
  res.systolicModule = S.moduleConstructor("constSeq_"..tostring(value):gsub('%W','_').."_T"..tostring(1/T))
  local sconsts = map(range(1/T), function() return {} end)
  for C=0, (1/T)-1 do
    for y=0, h-1 do
      for x=0, W-1 do
        table.insert(sconsts[C+1], value[y*w+C*W+x+1])
      end
    end
  end
  local shiftOut, shiftPipelines = fpgamodules.addShifterSimple( res.systolicModule, map(sconsts, function(n) return S.constant(n,types.array2d(A,W,h)) end), DARKROOM_VERBOSE )

  if shiftOut.type:const() then
    -- this happens if we have an array of size 1, for example (becomes a passthrough). Strip the const-ness so that the module returns a consistant type with different parameters.
    shiftOut = S.cast(shiftOut, shiftOut.type:stripConst())
  end

  local inp = S.parameter("process_input", types.null() )

  res.systolicModule:addFunction( S.lambda("process", inp, shiftOut, "process_output", shiftPipelines, nil, S.CE("process_CE") ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("process_nilinp", types.null() ), nil, "process_reset", {}, S.parameter("reset", types.bool() ) ) )

  return darkroom.newFunction( res )
end)

function darkroom.constant( name, value, ty )
  assert( type(name) == "string" )
  assert( types.isType(ty) )

  return darkroom.newIR( {kind="constant", name=name, value=value, type=ty, inputs = {}} )
end

-- packStreams: do we consider the output of this to be 1 SDF stream, or N?
function darkroom.tuple( name, t, packStreams )
  err( type(name)=="string", "first tuple input should be name")
  err( type(t)=="table", "tuple input should be table of darkroom values" )
  if packStreams==nil then packStreams=true end

  local r = {kind="tuple", name=name, loc=getloc(), inputs={}, packStreams = packStreams}
  map(t, function(n,k) assert(darkroom.isIR(n)); table.insert(r.inputs,n) end)
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

-- if index==true, then we return a value, not an array
darkroom.slice = memoize(function( inputType, idxLow, idxHigh, idyLow, idyHigh, index, X )
  err( types.isType(inputType),"slice first argument must be type" )
  err(type(idxLow)=="number", "slice idxLow must be number")
  err(type(idxHigh)=="number", "slice idxHigh must be number")
  err(index==nil or type(index)=="boolean", "index must be bool")
  assert(X==nil)

  if inputType:isTuple() then
    assert( idxLow < #inputType.list )
    assert( idxHigh < #inputType.list )
    assert( idxLow == idxHigh ) -- NYI
    assert( index )
    local OT = inputType.list[idxLow+1]
    local systolicInput = S.parameter("inp", inputType)
    local systolicOutput = S.index( systolicInput, idxLow )
    local tfn = terra( inp:&darkroom.lower(inputType):toTerraType(), out:&darkroom.lower(OT):toTerraType()) @out = inp.["_"..idxLow] end
    return darkroom.lift( "index_"..tostring(inputType):gsub('%W','_').."_"..idxLow, inputType, OT, 0, tfn, systolicInput, systolicOutput )
  elseif inputType:isArray() then
    local W = (inputType:arrayLength())[1]
    local H = (inputType:arrayLength())[2]
    assert(idxLow<W)
    err(idxHigh<W, "idxHigh>=W")
    assert(type(idyLow)=="number")
    assert(type(idyHigh)=="number")
    assert(idyLow<H)
    err(idyHigh<H, "idyHigh>=H")
    assert(idxLow<=idxHigh)
    assert(idyLow<=idyHigh)
    local OT = types.array2d( inputType:arrayOver(), idxHigh-idxLow+1, idyHigh-idyLow+1 )
    local systolicInput = S.parameter("inp",inputType)

    local systolicOutput = S.tuple( map( range2d(idxLow,idxHigh,idyLow,idyHigh), function(i) return S.index( systolicInput, i[1], i[2] ) end ) )
    systolicOutput = S.cast( systolicOutput, OT )
    local tfn = terra(inp:&darkroom.lower(inputType):toTerraType(), out:&darkroom.lower(OT):toTerraType()) 
      for iy = idyLow,idyHigh+1 do
        for ix = idxLow, idxHigh+1 do
          (@out)[(iy-idyLow)*(idxHigh-idxLow+1)+(ix-idxLow)] = (@inp)[ix+iy*W] 
        end
      end
    end

    if index then
      OT = inputType:arrayOver()
      systolicOutput = S.index( systolicInput, idxLow, idyLow )
      tfn = terra(inp:&darkroom.lower(inputType):toTerraType(), out:&darkroom.lower(OT):toTerraType()) @out = (@inp)[idxLow+idyLow*W] end
    end

    return darkroom.lift( "slice_type"..tostring(inputType).."_xl"..idxLow.."_xh"..idxHigh.."_yl"..idyLow.."_yh"..idyHigh, inputType, OT, 0, tfn, systolicInput, systolicOutput )
  else
    assert(false)
  end
                         end)

function darkroom.index( inputType, idx, idy, X )
  err( types.isType(inputType), "first input to index must be a type" )
  err( type(idx)=="number", "index idx must be number")
  assert(X==nil)
  if idy==nil then idy=0 end
  return darkroom.slice( inputType, idx, idx, idy, idy, true )
end

darkroom.freadSeq = memoize(function( filename, ty )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  darkroom.expectBasic(ty)
  local filenameVerilog=filename
  local res = {kind="freadSeq", filename=filename, filenameVerilog=filenameVerilog, type=ty, inputType=types.null(), outputType=ty, stateful=true, delay=0}
  res.sdfInput={{1,1}}
  res.sdfOutput={{1,1}}
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
  res.systolicModule = S.moduleConstructor("freadSeq_"..filename:gsub('%W','_'))
  local sfile = res.systolicModule:add( S.module.file( filenameVerilog, ty, true ):instantiate("freadfile") )
  local inp = S.parameter("process_input", types.null() )
  local nilinp = S.parameter("process_nilinp", types.null() )
  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", inp, sfile:read(), "process_output", nil, nil, CE ) )
  res.systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", {sfile:reset()}, S.parameter("reset", types.bool() ), CE ) )

  return darkroom.newFunction(res)
                            end)

function darkroom.fwriteSeq( filename, ty )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  darkroom.expectBasic(ty)
  local filenameVerilog=filename
    local res = {kind="fwriteSeq", filename=filename, filenameVerilog=filenameVerilog, type=ty, inputType=ty, outputType=ty, stateful=true, delay=0, sdfInput={{1,1}}, sdfOutput={{1,1}} }
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
  res.systolicModule = S.moduleConstructor("fwriteSeq_"..filename:gsub('%W','_'))
  local sfile = res.systolicModule:add( S.module.file( filenameVerilog, ty, true ):instantiate("fwritefile") )
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( ty, "fwrite O %h", true):instantiate("printInst") ) end

  local inp = S.parameter("process_input", ty )
  local nilinp = S.parameter("process_nilinp", types.null() )
  local CE = S.CE("CE")

  local pipelines = {sfile:write(inp)}
  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(inp) ) end

  res.systolicModule:addFunction( S.lambda("process", inp, inp, "process_output", pipelines, nil,CE ) )
  res.systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", {sfile:reset()}, S.parameter("reset", types.bool() ), CE ) )

  return darkroom.newFunction(res)
end

function darkroom.seqMap( f, W, H, T )
  err( darkroom.isFunction(f), "fn must be a function")
  err( type(W)=="number", "W must be a number")
  err( type(H)=="number", "H must be a number")
  err( type(T)=="number", "T must be a number")
  darkroom.expectBasic(f.inputType)
  darkroom.expectBasic(f.outputType)
  local res = {kind="seqMap", W=W,H=H,T=T,inputType=types.null(),outputType=types.null()}
  local struct SeqMap { inner: f.terraModule}
  terra SeqMap:reset() self.inner:reset() end
  terra SeqMap:stats() self.inner:stats("TOP") end
  terra SeqMap:process( inp:&types.null():toTerraType(), out:&types.null():toTerraType())
    var o : darkroom.lower(f.outputType):toTerraType()
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

function darkroom.seqMapHandshake( f, inputType, tapInputType, tapValue, inputCount, outputCount, axi, readyRate, X )
  err( darkroom.isFunction(f), "fn must be a function")
  err( types.isType(inputType), "inputType must be a type")
  err( tapInputType==nil or types.isType(tapInputType), "tapInputType must be a type")
  err( tapInputType==nil or type(tapValue)==tapInputType:toLuaType(), "tapValue must match tapInputType")
  err( type(inputCount)=="number", "inputCount must be a number")
  err( type(outputCount)=="number", "outputCount must be a number")
  err( type(axi)=="boolean", "axi should be a bool")
  assert(X==nil)

  darkroom.expectHandshake(f.inputType)
  darkroom.expectHandshake(f.outputType)

  local expectedOutputCount = (inputCount*f.sdfOutput[1][1]*f.sdfInput[1][2])/(f.sdfOutput[1][2]*f.sdfInput[1][1])
  err(expectedOutputCount==outputCount, "Error, seqMapHandshake, SDF output tokens ("..tostring(expectedOutputCount)..") does not match stated output tokens ("..tostring(outputCount)..")")

  local res = {kind="seqMapHandshake", inputCount=inputCount, outputCount=outputCount, inputType=types.null(),outputType=types.null()}
  res.sdfInput = f.sdfInput
  res.sdfOutput = f.sdfOutput
  local struct SeqMap { inner: f.terraModule}
  terra SeqMap:reset() self.inner:reset() end
  terra SeqMap:stats() self.inner:stats("TOP") end

  local innerinp = symbol(darkroom.lower(f.inputType):toTerraType(), "innerinp")
  local assntaps = quote end
  if tapInputType~=nil then assntaps = quote data(innerinp) = {nil,[tapInputType:valueToTerra(tapValue)]} end end

  if readyRate==nil then readyRate=1 end

  terra SeqMap:process( inp:&types.null():toTerraType(), out:&types.null():toTerraType())
    var [innerinp]
    [assntaps]

    var o : darkroom.lower(f.outputType):toTerraType()
    var inpAddr = 0
    var outAddr = 0
    var downstreamReady = 0

    while inpAddr<inputCount or outAddr<outputCount do
      valid(innerinp)=(inpAddr<inputCount)
      self.inner:calculateReady(downstreamReady==0)
      if DARKROOM_VERBOSE then cstdio.printf("---------------------------------- RUNPIPE inpAddr %d/%d outAddr %d/%d ready %d downstreamReady %d\n", inpAddr, inputCount, outAddr, outputCount, self.inner.ready, downstreamReady==0) end
      self.inner:process(&innerinp,&o)
      if self.inner.ready then inpAddr = inpAddr + 1 end
      if valid(o) and (downstreamReady==0) then outAddr = outAddr + 1 end
      downstreamReady = downstreamReady+1
      if downstreamReady==readyRate then downstreamReady=0 end
    end
  end
  res.terraModule = SeqMap

  local verilogStr

  if axi then
    local baseTypeI = inputType
    local baseTypeO = darkroom.extractData(f.outputType)
    err(baseTypeI:verilogBits()==64, "axi input must be 64 bits but is "..baseTypeI:verilogBits())
    err(baseTypeO:verilogBits()==64, "axi output must be 64 bits")

    local axiv = readAll("../extras/helloaxi/axi.v")
    axiv = string.gsub(axiv,"___PIPELINE_MODULE_NAME",f.systolicModule.name)
    axiv = string.gsub(axiv,"___PIPELINE_INPUT_COUNT",inputCount)
    axiv = string.gsub(axiv,"___PIPELINE_OUTPUT_COUNT",outputCount)

    -- input/output tokens are one axi bus transaction => they are 8 bytes
    local inputBytes = upToNearest(128,inputCount*8)
    local outputBytes = upToNearest(128,outputCount*8)
    axiv = string.gsub(axiv,"___PIPELINE_INPUT_BYTES",inputBytes)
    -- extra 128 is for the extra AXI burst that contains metadata
    axiv = string.gsub(axiv,"___PIPELINE_OUTPUT_BYTES",outputBytes)

    -- Our architecture can't have units with a utilization>1, so the 'maxUtilization' here will limit the throughput of the pipeline
    --local maxUtilization,LL = f.output:sdfExtremeUtilization(true)
    --print("MAX UTILIZATION",maxUtilization,LL)

    --local minUtilization, MLL = f.output:sdfExtremeUtilization(false)
    --print("MIN UTILIZATION",minUtilization,MLL)
    
    -- this is the worst utilization of a unit, accounting for the fact that all units must have utilization < 1
    --local totalMinUtilization = minUtilization/maxUtilization
    --print("TOTAL MIN UTILIZATION",totalMinUtilization)
    local maxUtilization = 1

    axiv = string.gsub(axiv,"___PIPELINE_WAIT_CYCLES",math.ceil(inputCount*maxUtilization)+1024) -- just give it 1024 cycles of slack
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
reg [31:0] totalClocks = 0;
]]..tapreg..[[
]]..S.declareWire( darkroom.lower(f.outputType), "process_output" )..[[

]]..f.systolicModule.name..[[ #(.INPUT_COUNT(]]..inputCount..[[),.OUTPUT_COUNT(]]..outputCount..[[)) inst (.CLK(CLK),.process_input(]]..sel(tapInputType~=nil,"{valid,taps}","valid")..[[),.reset(RST),.ready(ready),.ready_downstream(]]..readybit..[[),.process_output(process_output));
   initial begin
      // clock in reset bit
      while(i<100) begin CLK = 0; #10; CLK = 1; #10; i = i + 1; end

      RST = 0;
      //valid = 1;
      totalClocks = 0;
      while(1) begin CLK = 0; #10; CLK = 1; #10; end
   end

  reg [31:0] validInCnt = 0; // we should only drive W*H valid bits in
  reg [31:0] validCnt = 0;

  assign valid = (RST==0 && validInCnt < ]]..inputCount..[[);

  always @(posedge CLK) begin
    ]]..sel(DARKROOM_VERBOSE,[[$display("------------------------------------------------- RST %d totalClocks %d validOutputs %d/]]..outputCount..[[ ready %d readyDownstream %d validInCnt %d/]]..inputCount..[[",RST,totalClocks,validCnt,ready,]]..readybit..[[,validInCnt);]],"")..[[
    // we can't send more than W*H valid bits, or the AXI bus will lock up. Once we have W*H valid bits,
    // keep simulating for N cycles to make sure we don't send any more
]]..tapRST..[[
    if(validCnt> ]]..outputCount..[[ ) begin $display("Too many valid bits!"); end // I think we have this _NOT_ finish so that it outputs an invalid file
    if(validCnt>= ]]..outputCount..[[ && doneCnt==1024 ) begin $finish(); end
    if(validCnt>= ]]..outputCount..[[ && ]]..readybit..[[) begin doneCnt <= doneCnt+1; end
    if(RST==0 && ready) begin validInCnt <= validInCnt + 1; end
    
    // ignore the output when we're in reset mode - output is probably bogus
    if(]]..readybit..[[ && process_output[]]..(darkroom.lower(f.outputType):verilogBits()-1)..[[] && RST==1'b0) begin validCnt = validCnt + 1; end
    ready_downstream <= ready_downstream + 1;
    totalClocks <= totalClocks + 1;
  end
endmodule
]]
  end

  res.systolicModule = S.moduleConstructor("SeqMapHandshake_"..f.systolicModule.name.."_"..inputCount.."_"..outputCount.."_rr"..readyRate):verilog(verilogStr)
  res.systolicModule:add(f.systolicModule:instantiate("inst"))

  return darkroom.newFunction(res)
end

function darkroom.writeMetadata(filename, inputBytesPerPixel, inputWidth, inputHeight, outputBytesPerPixel, outputWidth, outputHeight, inputImage, X)
  assert(type(inputImage)=="string")
  assert(type(inputBytesPerPixel)=="number")
  assert(type(inputWidth)=="number")
  assert(type(inputHeight)=="number")
  assert(type(outputBytesPerPixel)=="number")
  assert(type(outputWidth)=="number")
  assert(type(outputHeight)=="number")
  assert(X==nil)

  local scaleX = {outputWidth,inputWidth}
  local scaleY = {outputHeight,inputHeight}
  local scale = fracMultiply(scaleX,scaleY)

  io.output(filename)
    io.write("return {inputWidth="..inputWidth..",inputHeight="..inputHeight..",outputWidth="..outputWidth..",outputHeight="..outputHeight..",scaleN="..scale[1]..",scaleD="..scale[2]..",inputBytesPerPixel="..inputBytesPerPixel..",outputBytesPerPixel="..outputBytesPerPixel..",inputImage='"..inputImage.."'}")
  io.close()
end

return darkroom