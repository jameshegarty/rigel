local rigel = require "rigel"
local types = require "types"
local S = require "systolic"
local systolic = S
local Ssugar = require "systolicsugar"
local fpgamodules = require("fpgamodules")
local SDFRate = require "sdfrate"
local J = require "common"
local memoize = J.memoize
local err = J.err

local verilogSanitize = J.verilogSanitize
local sanitize = verilogSanitize

local MT
if terralib~=nil then
  MT = require("modulesTerra")
end

local data = rigel.data
local valid = rigel.valid
local ready = rigel.ready

local modules = {}


-- tab should be a table of systolic ASTs, all type array2d. Heights should match
local function concat2dArrays(tab)
  assert( type(tab)=="table")
  assert( #tab>0)
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


-- *this should really be in examplescommon.t
-- f(g())
modules.compose = memoize(function( name, f, g, generatorStr )
  err( type(name)=="string", "first argument to compose must be name of function")
  err( darkroom.isFunction(f), "compose: second argument should be rigel module")
  err( darkroom.isFunction(g), "compose: third argument should be rigel module")

  name = J.verilogSanitize(name)

  local inp = rigel.input( g.inputType, g.sdfInput )
  local gvalue = rigel.apply(name.."_g",g,inp)
  return modules.lambda( name, inp, rigel.apply(name.."_f",f,gvalue), nil, nil, generatorStr )
end)


-- *this should really be in examplescommon.t
-- This converts SoA to AoS
-- ie {Arr2d(a,W,H),Arr2d(b,W,H),...} to Arr2d({a,b,c},W,H)
-- if asArray==true then converts {Arr2d(a,W,H),Arr2d(b,W,H),...} to Arr2d(a[N],W,H). This requires a,b,c be the same...
modules.SoAtoAoS = memoize(function( W, H, typelist, asArray )
  err( type(W)=="number", "SoAtoAoS: first argument should be number (width)")
  err( type(H)=="number", "SoAtoAoS: second argument should be number (height)")
  err( type(typelist)=="table", "SoAtoAoS: typelist must be table")
  err( J.keycount(typelist)==#typelist, "SoAtoAoS: typelist must be lua array")
  err( asArray==nil or type(asArray)=="boolean", "SoAtoAoS: asArray must be bool or nil")
  if asArray==nil then asArray=false end

  for k,v in ipairs(typelist) do
    err(types.isType(v),"SoAtoAoS: typelist index "..tostring(k).." must be rigel type")
  end

  local res = { kind="SoAtoAoS", W=W, H=H, asArray = asArray }

  res.inputType = types.tuple( J.map(typelist, function(t) return types.array2d(t,W,H) end) )
  if asArray then
    J.map( typelist, function(n) err(n==typelist[1], "if asArray==true, all elements in typelist must match") end )
    res.outputType = types.array2d(types.array2d(typelist[1],#typelist),W,H)
  else
    res.outputType = types.array2d(types.tuple(typelist),W,H)
  end

  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 0
  res.stateful=false
  res.name = "SoAtoAoS_"..verilogSanitize(tostring(typelist))

  if terralib~=nil then res.terraModule = MT.SoAtoAoS(res,W,H,typelist,asArray) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local sinp = S.parameter("process_input", res.inputType )
    local arrList = {}
    for y=0,H-1 do
      for x=0,W-1 do
        local r = S.tuple(J.map(J.range(0,#typelist-1), function(i) return S.index(S.index(sinp,i),x,y) end))
        if asArray then r = S.cast(r, types.array2d(typelist[1],#typelist) ) end
        table.insert( arrList, r )
      end
    end
    systolicModule:addFunction( S.lambda("process", sinp, S.cast(S.tuple(arrList),rigel.lower(res.outputType)), "process_output",nil,nil,S.CE("process_CE")) )
    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- Converst {Handshake(a), Handshake(b)...} to Handshake{a,b}
-- typelist should be a table of pure types
-- WARNING: ready depends on ValidIn
modules.packTuple = memoize(function( typelist, X )
  err( type(typelist)=="table", "packTuple: type list must be table" )
  err( X==nil, "packTuple: too many arguments" )
  
  local res = {kind="packTuple"}
  
  J.map(typelist, function(t) rigel.expectBasic(t) end )
  res.inputType = types.tuple( J.map(typelist, function(t) return rigel.Handshake(t) end) )
  res.outputType = rigel.Handshake( types.tuple(typelist) )
  res.stateful = false
  res.sdfOutput = {{1,1}}
  res.sdfInput = J.map(typelist, function(n) if n:const() then return "x" else return {1,1} end end)
  res.name = "packTuple_"..verilogSanitize(tostring(typelist))

  res.delay = 0

  if terralib~=nil then res.terraModule = MT.packTuple(res,typelist) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local CE
    local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro",nil,nil,CE) )
    
    systolicModule:onlyWire(true)
    
    local printStr = "IV ["..table.concat( J.broadcast("%d",#typelist),",").."] OV %d ready ["..table.concat(J.broadcast("%d",#typelist),",").."] readyDownstream %d"
    local printInst 
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple(J.broadcast(types.bool(),(#typelist)*2+2)), printStr):instantiate("printInst") ) end
    
    local activePorts={}
    for k,v in pairs(typelist) do if v:const()==false then table.insert(activePorts,k) end end
      
    local outv = S.tuple(J.map(J.range(0,#typelist-1), function(i) return S.index(S.index(sinp,i),0) end))
      
    -- valid bit is the AND of all the inputs
    local validInList = J.map(activePorts,function(i) return S.index(S.index(sinp,i-1),1) end)
    local validInFullList = J.map(typelist,function(i,k) return S.index(S.index(sinp,k-1),1) end)
    local validOut = J.foldt(validInList,function(a,b) return S.__and(a,b) end,"X")
  
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
  
    local readyOut = S.cast(S.tuple(readyOutList), types.array2d(types.bool(),#typelist) )
    
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple(concat(concat(validInFullList,{validOut}),concat(readyOutList,{downstreamReady})))) ) end
    
    local out = S.tuple{outv, validOut}
    systolicModule:addFunction( S.lambda("process", sinp, out, "process_output", pipelines) )
    
    systolicModule:addFunction( S.lambda("ready", downstreamReady, readyOut, "ready" ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

modules.liftBasic = memoize(function(f)
  err(rigel.isFunction(f),"liftBasic argument should be darkroom function")

  local res = {kind="liftBasic", fn = f}
  rigel.expectBasic(f.inputType)
  rigel.expectBasic(f.outputType)
  res.inputType = f.inputType
  res.outputType = rigel.V(f.outputType)
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = f.delay
  res.stateful = f.stateful
  res.name = "LiftBasic_"..f.name

  if terralib~=nil then res.terraModule = MT.liftBasic(res,f) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local inner = systolicModule:add( f.systolicModule:instantiate("LiftBasic_inner") )
    local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ inner:process(sinp), S.constant(true, types.bool())}, "process_output", nil, nil, CE ) )
    if f.stateful then systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {},S.parameter("reset",types.bool()),CE) ) end
    systolicModule:complete()
    
    return systolicModule
  end

  return rigel.newFunction(res)
                             end)

local function passthroughSystolic( res, systolicModule, inner, passthroughFns, onlyWire )
  assert(type(passthroughFns)=="table")

  for _,fnname in pairs(passthroughFns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    res:addFunction( S.lambda(fnname, srcFn:getInput(), inner[fnname]( inner, srcFn:getInput() ), srcFn:getOutputName(), nil, J.sel(onlyWire,nil,srcFn:getValid()), srcFn:getCE() ) )

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
  local res = Ssugar.moduleConstructor("RunIffReady_"..systolicModule.name)
  local inner = res:add( systolicModule:instantiate("RunIffReady") )

  for _,fnname in pairs(fns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    err( systolicModule:getDelay(prefix.."ready")==0, "ready bit should not be pipelined")

    local sinp = S.parameter(fnname.."_input", rigel.lower(rigel.V(srcFn:getInput().type)) )

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
  local res = Ssugar.moduleConstructor("WaitOnInput_"..systolicModule.name)
  local inner = res:add( systolicModule:instantiate("WaitOnInput_inner") )

  for _,fnname in pairs(fns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    err( systolicModule:getDelay(prefix.."ready")==0, "ready bit should not be pipelined")

    local asstInst = res:add( S.module.assert( "waitOnInput valid bit doesn't match ready bit", true ):instantiate("asstInst") )
    local printInst
    if DARKROOM_VERBOSE then printInst = res:add( S.module.print( types.tuple{types.bool(),types.bool(),types.bool(),types.bool()}, "WaitOnInput "..systolicModule.name.." ready %d validIn %d runable %d RST %d", true ):instantiate(prefix.."printInst") ) end

    local sinp = S.parameter(fnname.."_input", rigel.lower(rigel.V(srcFn:getInput().type)) )

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
modules.reduceThroughput = memoize(function(A,factor)
  err( type(factor)=="number", "reduceThroughput: second argument must be number (reduce factor)" )
  err( factor>1, "reduceThroughput: reduce factor must be >1" )
  err( math.floor(factor)==factor, "reduceThroughput: reduce factor must be an integer" )

  local res = {kind="reduceThroughput",factor=factor}
  res.inputType = A
  res.outputType = rigel.RV(A)
  res.sdfInput = {{1,factor}}
  res.sdfOutput = {{1,factor}}
  res.stateful = true
  res.delay = 0
  res.name = "ReduceThroughput_"..tostring(factor)

  if terralib~=nil then res.terraModule = MT.reduceThroughput(res,A,factor) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local phase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), factor-1, 1 ) ):CE(true):setInit(0):instantiate("phase") ) 

    local reading = S.eq( phase:get(), S.constant(0,types.uint(16)) ):disablePipelining()
    
    local sinp = S.parameter( "inp", A )
    
    local pipelines = {}
    table.insert(pipelines, phase:setBy(S.constant(true,types.bool())))

    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{sinp,reading}, "process_output", pipelines, nil, CE) )
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()),CE) )

    return systolicModule
  end

  return modules.waitOnInput( rigel.newFunction(res) )
end)

-- f should be basic->RV
-- You should never use basic->RV directly! S->SRV's input should be valid iff ready==true. This is not the case with normal Stateful functions!
-- if inner:ready()==true, inner will run iff valid(input)==true
-- if inner:ready()==false, inner will run always. Input will be garbage, but inner isn't supposed to be reading from it! (this condition is used for upsample, for example)
modules.waitOnInput = memoize(function(f)
  err(rigel.isFunction(f),"waitOnInput argument should be darkroom function")
  local res = {kind="waitOnInput", fn = f}
  rigel.expectBasic(f.inputType)
  rigel.expectRV(f.outputType)
  res.inputType = rigel.V(f.inputType)
  res.outputType = f.outputType

  err(f.delay == math.floor(f.delay), "waitOnInput, delay is fractional?")
  err( type(f.sdfInput)=="table", "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  err( type(f.stateful)=="boolean", "Missing stateful annotation for fn "..f.kind)
  res.stateful = f.stateful
  res.delay = f.delay
  res.name = "WaitOnInput_"..f.name

  if terralib~=nil then res.terraModule = MT.waitOnInput(res,f) end

  function res.makeSystolic()
    return waitOnInputSystolic( f.systolicModule, {"process"},{} )
  end

  return rigel.newFunction(res)
                               end)

local function liftDecimateSystolic( systolicModule, liftFns, passthroughFns )
  local res = Ssugar.moduleConstructor("LiftDecimate_"..systolicModule.name)
  local inner = res:add( systolicModule:instantiate("LiftDecimate") )

  for _,fnname in pairs(liftFns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    local sinp = S.parameter(fnname.."_input", rigel.lower(rigel.V(srcFn.inputParameter.type)) )
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
modules.liftDecimate = memoize(function(f)
  err( rigel.isFunction(f), "liftDecimate: input should be rigel module" )

  local res = {kind="liftDecimate", fn = f}
  rigel.expectBasic(f.inputType)
  res.inputType = rigel.V(f.inputType)
  res.name = "LiftDecimate_"..f.name

  if rigel.isV(f.outputType) then
    res.outputType = rigel.RV(rigel.extractData(f.outputType))
  elseif f.outputType:isTuple() and #f.outputType.list==2 and f.outputType.list[2]==types.bool() then
    -- "looks like" a V
    res.outputType = rigel.RV(f.outputType.list[1])
  else
    err(false, "expected V output type")
  end

  err(type(f.stateful)=="boolean", "Missing stateful annotation for "..f.kind)
  res.stateful = f.stateful

  err( rigel.SDF==false or SDFRate.isSDFRate(f.sdfInput), "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput

  res.delay = f.delay

  if terralib~=nil then res.terraModule = MT.liftDecimate(res,f) end

  function res.makeSystolic()
    err( f.systolicModule~=nil, "Missing systolic for "..f.kind )
    return liftDecimateSystolic( f.systolicModule, {"process"},{})
  end

  return rigel.newFunction(res)
                                end)

-- converts V->RV to RV->RV
modules.RPassthrough = memoize(function(f)
  local res = {kind="RPassthrough", fn = f}
  rigel.expectV(f.inputType)
  rigel.expectRV(f.outputType)
  res.inputType = rigel.RV(rigel.extractData(f.inputType))
  res.outputType = rigel.RV(rigel.extractData(f.outputType))
  err( rigel.SDF==false or type(f.sdfInput)=="table", "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  err( type(f.stateful)=="boolean", "Missing stateful annotation for "..f.kind)
  res.stateful = f.stateful
  res.delay = f.delay
  if terralib~=nil then res.terraModule = MT.RPassthrough(res,f) end
  res.name = "RPassthrough_"..f.name

  function res.makeSystolic()
    err( f.systolicModule~=nil, "RPassthrough null module "..f.kind)

    local systolicModule = Ssugar.moduleConstructor(res.name)
    local inner = systolicModule:add( f.systolicModule:instantiate("RPassthrough_inner") )
    local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
    
    -- this is dumb: we don't actually use the 'ready' bit in the struct (it's provided by the ready function).
    -- but we include it to distinguish the types.
    local out = inner:process( S.tuple{ S.index(sinp,0), S.index(sinp,1)} )
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ S.index(out,0), S.index(out,1) }, "process_output", nil, nil, CE ) )
    if f.stateful then
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {}, S.parameter("reset",types.bool()), CE) )
    end
    local rinp = S.parameter("ready_input", types.bool() )
    systolicModule:addFunction( S.lambda("ready", rinp, S.__and(inner:ready(),rinp):disablePipelining(), "ready", {} ) )

    return systolicModule
  end

  return rigel.newFunction(res)
                                end)

local function liftHandshakeSystolic( systolicModule, liftFns, passthroughFns, hasReadyInput )
  assert(type(hasReadyInput)=="table")
  
  local res = Ssugar.moduleConstructor( "LiftHandshake_"..systolicModule.name ):onlyWire(true):parameters({INPUT_COUNT=0, OUTPUT_COUNT=0})
  local inner = res:add(systolicModule:instantiate("inner_"..systolicModule.name))

  systolicModule:complete()

  for K,fnname in pairs(liftFns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    local printInst 
    if DARKROOM_VERBOSE then printInst = res:add( S.module.print( types.tuple{types.bool(), srcFn:getInput().type.list[1],types.bool(),srcFn:getOutput().type.list[1],types.bool(),types.bool(),types.bool(),types.uint(16), types.uint(16)}, fnname.." RST %d I %h IV %d O %h OV %d readyDownstream %d ready %d outputCount %d expectedOutputCount %d"):instantiate(prefix.."printInst") ) end

    local outputCount
    if STREAMING==false and DARKROOM_VERBOSE then outputCount = res:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIf() ):CE(true):instantiate(prefix.."outputCount"):setCoherent(false) ) end

    local pinp = S.parameter(fnname.."_input", srcFn:getInput().type )

    local rst = S.parameter(prefix.."reset",types.bool())

    local downstreamReady
    local CE
    
    if hasReadyInput[K] then
      downstreamReady = S.parameter(prefix.."ready_downstream", types.bool())
      CE = S.__or(rst,downstreamReady)
    else
      downstreamReady = S.parameter(prefix.."ready_downstream", types.null())
      CE = S.constant(true,types.bool())
    end

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
    
    local readyOut
    if hasReadyInput[K] then
      readyOut = systolic.__and(inner[prefix.."ready"](inner),downstreamReady)
    else
      readyOut = inner[prefix.."ready"](inner)
    end
    
    local pipelines = {}
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple{ rst, S.index(pinp,0), S.index(pinp,1), S.index(out,0), S.index(out,1), downstreamReady, readyOut, outputCount:get(), S.instanceParameter("OUTPUT_COUNT",types.uint(16)) } ) ) end
    if STREAMING==false and DARKROOM_VERBOSE then table.insert(pipelines,  outputCount:setBy(outvalid, S.__not(rst), CE) ) end
    
    --local asstInst = res:add( S.module.assert( "LiftHandshake: output valid bit should not be X!" , false, false):instantiate(prefix.."asstInst") )
    --table.insert(pipelines, asstInst:process(S.__not(S.isX(S.index(out,1))), S.constant(true,types.bool()) ) )
    
    --local asstInst2 = res:add( S.module.assert( "LiftHandshake: input valid bit should not be X!" , false, false):instantiate(prefix.."asstInst2") )
    --table.insert(pipelines, asstInst2:process(S.__not(S.isX(S.index(pinp,1))), S.constant(true,types.bool()) ) )
    
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
modules.liftHandshake = memoize(function(f)
  local res = {kind="liftHandshake", fn=f}
  rigel.expectV(f.inputType)
  rigel.expectRV(f.outputType)
  res.inputType = rigel.Handshake(rigel.extractData(f.inputType))
  res.outputType = rigel.Handshake(rigel.extractData(f.outputType))
  res.name = "LiftHandshake_"..f.name

  err( rigel.SDF==false or SDFRate.isSDFRate(f.sdfInput), "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  err(type(f.stateful)=="boolean", "Missing stateful annotation, "..f.kind)
  res.stateful = f.stateful

  local delay = math.max(1, f.delay)
  err(f.delay==math.floor(f.delay),"delay is fractional ?!, "..f.kind)

  if terralib~=nil then res.terraModule = MT.liftHandshake(res,f,delay) end

  function res.makeSystolic()
    return liftHandshakeSystolic( f.systolicModule, {"process"},{},{true} )
  end

  return rigel.newFunction(res)
                                 end)

-- takes an image of size A[W,H] to size A[W+L+R,H+B+Top]. Fills the new pixels with value 'Value'
modules.pad = memoize(function( A, W, H, L, R, B, Top, Value )
	err( types.isType(A), "A must be a type")

  err( A~=nil, "pad A==nil" )
  err( W~=nil, "pad W==nil" )
  err( H~=nil, "pad H==nil" )
  err( L~=nil, "pad L==nil" )
  err( R~=nil, "pad R==nil" )
  err( B~=nil, "pad B==nil" )
  err( Top~=nil, "pad Top==nil" )
  err( Value~=nil, "pad Value==nil" )
  
  J.map({W=W,H=H,L=L,R=R,B=B,Top=Top},function(n,k)
        err(type(n)=="number","pad expected number for argument "..k.." but is "..tostring(n)); 
        err(n==math.floor(n),"pad non-integer argument "..k..":"..n); 
        err(n>=0,"n<0") end)

  A:checkLuaValue(Value)

  local res = {kind="pad", type=A, L=L, R=R, B=B, Top=Top, value=Value, width=W, height=H}
  res.inputType = types.array2d(A,W,H)
  res.outputType = types.array2d(A,W+L+R,H+B+Top)
  res.stateful = false
  res.sdfInput, res.sdfOutput = {{1,1}}, {{1,1}}
  res.delay=0
  res.name = "Pad_"..tostring(A):gsub('%W','_').."_W"..W.."_H"..H.."_L"..L.."_R"..R.."_B"..B.."_Top"..Top.."_Value"..tostring(Value)
--------
  if terralib~=nil then res.terraModule = MT.pad( res, A, W, H, L, R, B, Top, Value ) end

  function res.makeSystolic()
    err(false, "NYI - pad modules systolic version")
	end

  return rigel.newFunction(res)
end)


-- f : ( A, B, ...) -> C (darkroom function)
-- map : ( f, A[n], B[n], ...) -> C[n]
modules.map = memoize(function( f, W, H )
  err( rigel.isFunction(f), "first argument to map must be Rigel module, but is "..tostring(f) )
  err( type(W)=="number", "width must be number")
  err( type(H)=="number" or H==nil, "map: H must be number of nil" )
  if H==nil then H=1 end

  local res = { kind="map", fn = f, W=W, H=H }

  res.inputType = types.array2d( f.inputType, W, H )
  res.outputType = types.array2d( f.outputType, W, H )
  err(type(f.stateful)=="boolean", "Missing stateful annotation "..f.kind)
  res.stateful = f.stateful
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = f.delay
  res.name = sanitize("map_"..f.name.."_W"..tostring(W).."_H"..tostring(H))

  if terralib~=nil then res.terraModule = MT.map(res,f,W,H) end

  function res.makeSystolic()
    local systolicModule= Ssugar.moduleConstructor(res.name)
    local inp = S.parameter("process_input", res.inputType )
    local out = {}
    local resetPipelines={}
    for y=0,H-1 do
      for x=0,W-1 do 
        local inst = systolicModule:add(f.systolicModule:instantiate("inner"..x.."_"..y))
        table.insert( out, inst:process( S.index( inp, x, y ) ) )
        if f.stateful then
          table.insert( resetPipelines, inst:reset() ) -- no reset for pure functions
        end
      end 
    end

    local CE = S.CE("process_CE")

    systolicModule:addFunction( S.lambda("process", inp, S.cast( S.tuple( out ), res.outputType ), "process_output", nil, nil, CE ) )
    if f.stateful then
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, S.parameter("reset",types.bool()),CE ) )
    end
    return systolicModule
  end
  
  return rigel.newFunction(res)
end)

-- type {A,bool}->A
-- rate: {n,d} format frac. If coerce=true, 1/rate must be integer.
-- if rate={1,16}, filterSeq will return W*H/16 pixels
modules.filterSeq = memoize(function( A, W,H, rate, fifoSize, coerce )
  assert(types.isType(A))
  err(type(W)=="number", "W must be number")
  err(type(H)=="number", "H must be number")
  err( SDFRate.isFrac(rate), "filterSeq: rate must be {n,d} format fraction" )
  err(type(fifoSize)=="number", "fifoSize must be number")

  if coerce==nil then coerce=true end


  local res = { kind="filterSeq", A=A }
  -- this has type basic->V (decimate)
  res.inputType = types.tuple{A,types.bool()}
  res.outputType = rigel.V(A)
  res.delay = 0
  res.stateful = true
  res.sdfInput = {{1,1}}
  res.sdfOutput = {rate}
  res.name = sanitize("FilterSeq_"..tostring(A))

  local outTokens = ((W*H)*rate[1])/rate[2]
  err(outTokens==math.ceil(outTokens),"FilterSeq error: number of resulting tokens in non integer ("..tonumber(outTokens)..")")

  if terralib~=nil then res.terraModule = MT.filterSeq( res, A, W,H, rate, fifoSize, coerce ) end


  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    -- hack: get broken systolic library to actually wire valid
    local phase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), 42, 1 ) ):CE(true):setInit(0):instantiate("phase") ) 
    
    local sinp = S.parameter("process_input", res.inputType )
    local CE = S.CE("CE")
    local v = S.parameter("process_valid",types.bool())
    
    if coerce then
      
      local invrate = rate[2]/rate[1]
      err(math.floor(invrate)==invrate,"filterSeq: in coerce mode, 1/rate must be integer but is "..tostring(invrate))
      
      local outputCount = (W*H*rate[1])/rate[2]
      err(math.floor(outputCount)==outputCount,"filterSeq: in coerce mode, outputCount must be integer, but is "..tostring(outputCount))
      
      local vstring = [[
module FilterSeqImpl(input CLK, input process_valid, input reset, input ce, input []]..tostring(res.inputType:verilogBits()-1)..[[:0] inp, output []]..tostring(rigel.lower(res.outputType):verilogBits()-1)..[[:0] out);
parameter INSTANCE_NAME="INST";

  reg [31:0] phase;
  reg [31:0] cyclesSinceOutput;
  reg [31:0] currentFifoSize;
  reg [31:0] remainingInputs;
  reg [31:0] remainingOutputs;

  wire []]..tostring(res.inputType:verilogBits()-2)..[[:0] inpData;
  assign inpData = inp[]]..tostring(res.inputType:verilogBits()-2)..[[:0];

  wire filterCond;
  assign filterCond = inp[]]..tostring(res.inputType:verilogBits()-1)..[[];

  wire underflow;
  assign underflow = (currentFifoSize==0 && cyclesSinceOutput==]]..tostring(invrate)..[[);

  wire fifoHasSpace;
  assign fifoHasSpace = currentFifoSize<]]..tostring(fifoSize)..[[;

  wire outaTime;
  assign outaTime = remainingInputs < (remainingOutputs*]]..tostring(invrate)..[[);

  wire validOut;
  assign validOut = (((filterCond || underflow) && fifoHasSpace) || outaTime);

  assign out = {validOut,inpData};

  always @ (posedge CLK) begin
    if (reset) begin
      phase <= 0;
      cyclesSinceOutput <= 0;
      currentFifoSize <= 0;
      remainingInputs <= ]]..tostring(W*H)..[[;
      remainingOutputs <= ]]..tostring(outputCount)..[[;
    end else if (ce && process_valid) begin
      currentFifoSize <= (validOut && (phase<]]..tostring(invrate-1)..[[))?(currentFifoSize+1):(   (validOut==1'b0 && phase==]]..tostring(invrate-1)..[[ && currentFifoSize>0)? (currentFifoSize-1) : (currentFifoSize) );
      cyclesSinceOutput <= (validOut)?0:cyclesSinceOutput+1;
      remainingOutputs <= validOut?( (remainingOutputs==0)?]]..tostring(outputCount)..[[:(remainingOutputs-1) ):remainingOutputs;
      remainingInputs <= (remainingInputs==0)?]]..tostring(W*H)..[[:(remainingInputs-1);
      phase <= (phase==]]..tostring(invrate)..[[)?0:(phase+1);
    end
  end
]]

    if DARKROOM_VERBOSE then
      vstring = vstring..[[always @(posedge CLK) begin
  $display("FILTER reset:%d process_valid:%d filterCond:%d validOut:%d phase:%d cyclesSinceOutput:%d currentFifoSize:%d remainingInputs:%d remainingOutputs:%d underflow:%d fifoHasSpace:%d outaTime:%d", reset, process_valid, filterCond, validOut, phase, cyclesSinceOutput, currentFifoSize, remainingInputs, remainingOutputs, underflow, fifoHasSpace, outaTime);
  end
]]
    end

  
vstring = vstring..[[endmodule
]]

      local fns = {}
      local inp = S.parameter("inp",res.inputType)
    
      local datat = rigel.extractData(res.outputType)
      local datav = datat:fakeValue()
    
      fns.process = S.lambda("process",inp,S.cast(S.tuple{S.constant(datav,datat),S.constant(true,types.bool())}, rigel.lower(res.outputType)), "out",nil,S.parameter("process_valid",types.bool()),S.CE("ce"))
      fns.reset = S.lambda( "reset", S.parameter("resetinp",types.null()), S.null(), "resetout",nil,S.parameter("reset",types.bool()),S.CE("ce"))
    
      local FilterSeqImpl = systolic.module.new("FilterSeqImpl", fns, {}, true,nil,nil, vstring,{process=0,reset=0})

      local inner = systolicModule:add(FilterSeqImpl:instantiate("filterSeqImplInner"))

      systolicModule:addFunction( S.lambda("process", sinp, inner:process(sinp,v), "process_output", {phase:setBy(S.constant(true,types.bool()))}, v, CE ) )
      local resetValid = S.parameter("reset",types.bool())
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(16))),inner:reset(nil,resetValid)},resetValid,CE) )

    else
      systolicModule:addFunction( S.lambda("process", sinp, sinp, "process_output", {phase:setBy(S.constant(true,types.bool()))}, v, CE ) )
      local resetValid = S.parameter("reset",types.bool())
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(16)))},resetValid,CE) )
    end

    return systolicModule
  end
  
  return rigel.newFunction(res)
end)

modules.readMemory = memoize(function(ty)
  assert( types.isType(ty) )
  err( rigel.isBasic(ty), "readMemory: expected basic type, but was "..tostring(ty) )

  local res = {kind="readMemory", ty=ty }

  local addrType = types.uint(32)
  -- idx 0: address, idx 1: data
  res.inputType = types.tuple{ rigel.Handshake(addrType), rigel.Handshake(ty) }
  -- idx 0: output data, idx 1: addr to ram
  res.outputType = types.tuple{ rigel.Handshake(ty), rigel.Handshake(addrType) }
  res.stateful = true
  res.sdfOutput={ {1,1}, 'x' }
  res.sdfInput={ {1,1},'x'}
  res.delay=10
  res.name = "readMemory_"..tostring(ty)

  function res:sdfTransfer( I, loc )
    err( SDFRate.isSDFRate(I[1]), "Error, readMemory SDF input is not valid ")
    err( #I[1] == #res.sdfInput, "Error, readMemory SDF wrong # of streams")
    return I
  end
  
  function res.makeSystolic()
    local vstring = [[
module readMemory_]]..tostring(ty)..[[(input CLK, input reset, input [1:0] ready_downstream, output [1:0] ready, input []]..tostring(addrType:verilogBits()+ty:verilogBits()-1+2)..[[:0] process_input, output []]..tostring(addrType:verilogBits()+ty:verilogBits()-1+2)..[[:0] process_output);
parameter INSTANCE_NAME="INST";
  assign process_output = {process_input[]]..tostring(addrType:verilogBits())..[[:0], process_input[]]..tostring(addrType:verilogBits()+ty:verilogBits()+1)..":"..tostring(addrType:verilogBits()+1)..[[]};
  assign ready={ready_downstream[0],ready_downstream[1]};
endmodule

]]

    local fns = {}

    local processinp = S.parameter("process_input",rigel.lower(res.inputType))
    fns.process = S.lambda("process",processinp,S.constant(rigel.lower(res.outputType):fakeValue(),rigel.lower(res.outputType)), "process_output")
    fns.reset = S.lambda( "reset", S.parameter("resetinp",types.null()), nil, "resetout",nil, S.parameter("reset",types.bool()))

    local downstreamReady = S.parameter("ready_downstream", types.array2d(types.bool(),2))
    fns.ready = S.lambda("ready", downstreamReady, downstreamReady, "ready" )
  
    return systolic.module.new(res.name, fns, {}, true,nil,nil, vstring,{process=0,reset=0,ready=0})
  end

  return rigel.newFunction(res)
end)

-- takes A[W,H] to A[W,H/scale]
-- lines where ycoord%scale==0 are kept
-- basic -> V
modules.downsampleYSeq = memoize(function( A, W, H, T, scale, X )
  err( types.isType(A), "downsampleYSeq: type must be rigel type")
  err( type(W)=="number", "downsampleYSeq: W must be number" )
  err( type(H)=="number", "downsampleYSeq: H must be number" )
  err( type(T)=="number", "downsampleYSeq: T must be number" )
  err( type(scale)=="number", "downsampleYSeq: scale must be number" )
  err( scale>=1, "downsampleYSeq: scale must be >=1" )
  err( W%T==0, "downsampleYSeq, W%T~=0")
  err( J.isPowerOf2(scale), "scale must be power of 2")
  err( X==nil, "downsampleYSeq: too many arguments" )

  local sbits = math.log(scale)/math.log(2)

  local inputType = types.array2d(A,T)
  local outputType = types.tuple{inputType,types.bool()}
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)
  local innerInputType = types.tuple{xyType, inputType}

  local modname = "DownsampleYSeq_W"..tostring(W).."_H"..tostring(H).."_scale"..tostring(scale).."_"..verilogSanitize(tostring(A)).."_T"..tostring(T)

  local f = modules.lift( modname, innerInputType, outputType, 0, 
    function(sinp)
      local sdata = S.index(sinp,1)
      local sy = S.index(S.index(S.index(sinp,0),0),1)
      local svalid = S.eq(S.cast(S.bitSlice(sy,0,sbits-1),types.uint(sbits)),S.constant(0,types.uint(sbits)))
      return S.tuple{sdata,svalid}
    end, 
    function()
      return MT.downsampleYSeqFn(innerInputType,outputType,scale)
    end, nil, {{1,scale}})

  return modules.liftXYSeq( modname, "rigel.downsampleYSeq", f, W, H, T )
end)

-- takes A[W,H] to A[W/scale,H]
-- lines where xcoord%scale==0 are kept
-- basic -> V
-- 
-- This takes A[T] to A[T/scale], except in the case where scale>T. Then it goes from A[T] to A[1]. If you want to go from A[T] to A[T], use changeRate.
modules.downsampleXSeq = memoize(function( A, W, H, T, scale, X )
  err( types.isType(A), "downsampleXSeq: type must be rigel type" )
  err( type(W)=="number", "downsampleXSeq: W must be number" )
  err( type(H)=="number", "downsampleXSeq: H must be number" )
  err( type(T)=="number", "downsampleXSeq: T must be number" )
  err( type(scale)=="number", "downsampleXSeq: scale must be number" )
  err( scale>=1, "downsampleXSeq: scale must be >=1 ")
  err( W%T==0, "downsampleXSeq, W%T~=0")
  err( J.isPowerOf2(scale), "NYI - scale must be power of 2")
  err( X==nil, "downsampleXSeq: too many arguments" )

  local sbits = math.log(scale)/math.log(2)

  local outputT
  if scale>T then outputT = 1
  elseif T%scale==0 then outputT = T/scale
  else err(false,"T%scale~=0 and scale<T") end

  local inputType = types.array2d(A,T)
  local outputType = types.tuple{types.array2d(A,outputT),types.bool()}
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)
  local innerInputType = types.tuple{xyType, inputType}

  local tfn, sdfOverride

  if scale>T then -- A[T] to A[1]
    sdfOverride = {{1,scale}}
    if terralib~=nil then tfn = MT.downsampleXSeqFn(innerInputType,outputType,scale) end
  else
    sdfOverride = {{1,1}}
    if terralib~=nil then tfn = MT.downsampleXSeqFnShort(innerInputType,outputType,scale,outputT) end
  end

  local modname = "DownsampleXSeq_W"..tostring(W).."_H"..tostring(H).."_"..verilogSanitize(tostring(A)).."_T"..tostring(T).."_scale"..tostring(scale)

  local f = modules.lift( modname, innerInputType, outputType, 0, 
    function(sinp)
      local svalid, sdata
      local sy = S.index(S.index(S.index(sinp,0),0),0)
      if scale>T then -- A[T] to A[1]
        svalid = S.eq(S.cast(S.bitSlice(sy,0,sbits-1),types.uint(sbits)),S.constant(0,types.uint(sbits)))
        sdata = S.index(sinp,1)
      else
        svalid = S.constant(true,types.bool())
        local datavar = S.index(sinp,1)
        sdata = J.map(J.range(0,outputT-1), function(i) return S.index(datavar, i*scale) end)
        sdata = S.cast(S.tuple(sdata), types.array2d(A,outputT))
      end
      return S.tuple{sdata,svalid}
    end,
    function() return tfn end, nil,
    sdfOverride)

  return modules.liftXYSeq( modname, "rigel.downsampleXSeq", f, W, H, T )

end)

-- takes an image of size A[W,H] to size A[W/scaleX,H/scaleY]. Fills the new pixels with value 'Value'
modules.downsample = memoize(function( A, W, H, scaleX, scaleY, X )
	err( types.isType(A), "A must be a type")

  err( A~=nil, "downsample A==nil" )
  err( W~=nil, "downsample W==nil" )
  err( H~=nil, "downsample H==nil" )
  err( scaleX~=nil, "downsample scaleX==nil" )
  err( scaleY~=nil, "downsample scaleY==nil" )
  err( X==nil, "downsample: too many arguments" )
  
  J.map({W=W,H=H,scaleX=scaleX,scaleY=scaleY},function(n,k)
        err(type(n)=="number","downsample expected number for argument "..k.." but is "..tostring(n)); 
        err(n==math.floor(n),"downsample non-integer argument "..k..":"..n); 
        err(n>=0,"n<0") end)

  err( W%scaleX==0, "downsample: scaleX does not divide width evenly")
  err( H%scaleY==0, "downsample: scaleY does not divide height evenly")

  local res = {kind="downsample", type=A, width=W, height=H, scaleX=scaleX, scaleY=scaleY}
  res.inputType = types.array2d( A, W, H )
  res.outputType = types.array2d( A, W/scaleX, H/scaleY )
  res.stateful = false
  res.sdfInput, res.sdfOutput = {{1,1}}, {{1,1}}
  res.delay=0
  res.name = "Downsample_"..tostring(A):gsub('%W','_').."_W"..W.."_H"..H.."_scaleX"..scaleX.."_scaleY"..scaleY
--------
  if terralib~=nil then res.terraModule = MT.downsample( res, A, W, H, scaleX, scaleY ) end

  function res.makeSystolic()
    err(false, "NYI - downsample modules systolic version")
	end

  return rigel.newFunction(res)
end)


-- takes an image of size A[W,H] to size A[W*scaleX,H*scaleY]. Fills the new pixels with value 'Value'
modules.upsample = memoize(function( A, W, H, scaleX, scaleY, X )
	err( types.isType(A), "A must be a type")

  err( A~=nil, "upsample A==nil" )
  err( W~=nil, "upsample W==nil" )
  err( H~=nil, "upsample H==nil" )
  err( scaleX~=nil, "upsample scaleX==nil" )
  err( scaleY~=nil, "upsample scaleY==nil" )
  err( X==nil, "upsample: too many arguments" )
  
  J.map({W=W,H=H,scaleX=scaleX,scaleY=scaleY},function(n,k)
        err(type(n)=="number","upsample expected number for argument "..k.." but is "..tostring(n)); 
        err(n==math.floor(n),"upsample non-integer argument "..k..":"..n); 
        err(n>=0,"n<0") end)

  local res = {kind="upsample", type=A, width=W, height=H, scaleX=scaleX, scaleY=scaleY}
  res.inputType = types.array2d( A, W, H )
  res.outputType = types.array2d( A, W*scaleX, H*scaleY )
  res.stateful = false
  res.sdfInput, res.sdfOutput = {{1,1}}, {{1,1}}
  res.delay=0
  res.name = "Upsample_"..tostring(A):gsub('%W','_').."_W"..W.."_H"..H.."_scaleX"..scaleX.."_scaleY"..scaleY
--------
  if terralib~=nil then res.terraModule = MT.upsample( res, A, W, H, scaleX, scaleY ) end

  function res.makeSystolic()
    err(false, "NYI - upsample modules systolic version")
	end

  return rigel.newFunction(res)
end)

-- This is actually a pure function
-- takes A[T] to A[T*scale]
-- like this: [A[0],A[0],A[1],A[1],A[2],A[2],...]
broadcastWide = memoize(function( A, T, scale )
  local ITYPE, OTYPE = types.array2d(A,T), types.array2d(A,T*scale)

  return modules.lift("broadcastWide_"..J.verilogSanitize(tostring(A)).."_T"..tostring(T).."_scale"..tostring(scale), ITYPE, OTYPE, 0,
    function(sinp)
      local out = {}
      for t=0,T-1 do
        for s=0,scale-1 do
          table.insert(out, S.index(sinp,t) )
        end
      end
      return S.cast(S.tuple(out), OTYPE)
    end,
    function() return MT.broadcastWide(ITYPE,OTYPE,T,scale) end)
end)

-- this has type V->RV
modules.upsampleXSeq = memoize(function( A, T, scale, X )
  err( types.isType(A), "upsampleXSeq: first argument must be rigel type ")
  err( rigel.isBasic(A),"upsampleXSeq: type must be basic type")
  err( type(T)=="number", "upsampleXSeq: vector width must be number")
  err( type(scale)=="number","upsampleXSeq: scale must be number")
  err(X==nil, "upsampleXSeq: too many arguments")

  if T==1 then
    -- special case the EZ case of taking one value and writing it out N times
    local res = {kind="upsampleXSeq",sdfInput={{1,scale}}, sdfOutput={{1,1}}, stateful=true, A=A, T=T, scale=scale}

    local ITYPE = types.array2d(A,T)
    res.inputType = ITYPE
    res.outputType = rigel.RV(types.array2d(A,T))
    res.delay=0
    res.name = verilogSanitize("UpsampleXSeq_"..tostring(A).."_T_"..tostring(T).."_scale_"..tostring(scale))

    if terralib~=nil then res.terraModule = MT.upsampleXSeq(res,A, T, scale, ITYPE ) end

    -----------------
    function res.makeSystolic()
      local systolicModule = Ssugar.moduleConstructor(res.name)
      local sinp = S.parameter( "inp", ITYPE )

      local sPhase = systolicModule:add( Ssugar.regByConstructor( types.uint(8), fpgamodules.sumwrap(types.uint(8),scale-1) ):CE(true):instantiate("phase") )
      local reg = systolicModule:add( S.module.reg( ITYPE,true ):instantiate("buffer") )

      local reading = S.eq(sPhase:get(),S.constant(0,types.uint(8))):disablePipelining()
      local out = S.select( reading, sinp, reg:get() ) 

      local pipelines = {}
      table.insert(pipelines, reg:set( sinp, reading ) )
      table.insert( pipelines, sPhase:setBy( S.constant(1,types.uint(8)) ) )

      local CE = S.CE("CE")
      systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines, nil, CE) )
      systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:set(S.constant(0,types.uint(8)))},S.parameter("reset",types.bool()),CE) )

      return systolicModule
    end

    return modules.liftHandshake(modules.waitOnInput( rigel.newFunction(res) ))
  else
    return modules.compose("upsampleXSeq_"..J.verilogSanitize(tostring(A)).."_T"..tostring(T).."_scale"..tostring(scale), modules.liftHandshake(modules.changeRate(A,1,T*scale,T)), modules.makeHandshake(broadcastWide(A,T,scale)))
  end
end)

-- V -> RV
modules.upsampleYSeq = memoize(function( A, W, H, T, scale )
  err( types.isType(A), "upsampleYSeq: type must be type")
  err( rigel.isBasic(A), "upsampleYSeq: type must be basic type")
  err( type(W)=="number", "upsampleYSeq: W must be number")
  err( type(H)=="number", "upsampleYSeq: H must be number")
  err( type(T)=="number", "upsampleYSeq: T must be number")
  err( type(scale)=="number", "upsampleYSeq: scale must be number")
  err( scale>1, "upsampleYSeq: scale must be > 1 ")
  err( W%T==0,"W%T~=0")
  err( J.isPowerOf2(scale), "scale must be power of 2")
  err( J.isPowerOf2(W), "W must be power of 2")

  local res = {kind="upsampleYSeq", sdfInput={{1,scale}}, sdfOutput={{1,1}}, A=A, T=T, width=W, height=H, scale=scale}
  local ITYPE = types.array2d(A,T)
  res.inputType = ITYPE
  res.outputType = rigel.RV(types.array2d(A,T))
  res.delay=0
  res.stateful = true
  res.name = verilogSanitize("UpsampleYSeq_"..tostring(A).."_T_"..tostring(T).."_scale_"..tostring(scale).."_w_"..tostring(W).."_h_"..tostring(H))

  if terralib~=nil then res.terraModule = MT.upsampleYSeq( res,A, W, H, T, scale, ITYPE ) end

  -----------------
  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local sinp = S.parameter( "inp", ITYPE )

    -- we currently don't have a way to make a posx counter and phase counter coherent relative to each other. So just use 1 counter for both. This restricts us to only do power of two however!
    local sPhase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.sumwrap(types.uint(16),(W/T)*scale-1) ):CE(true):instantiate("xpos") )

    local addrbits = math.log(W/T)/math.log(2)
    assert(addrbits==math.floor(addrbits))
    
    local xpos = S.cast(S.bitSlice( sPhase:get(), 0, addrbits-1), types.uint(addrbits))
    
    local phasebits = (math.log(scale)/math.log(2))
    local phase = S.cast(S.bitSlice( sPhase:get(), addrbits, addrbits+phasebits-1 ), types.uint(phasebits))
    
    local sBuffer = systolicModule:add( fpgamodules.bramSDP( true, (A:verilogBits()*W)/8, ITYPE:verilogBits()/8, ITYPE:verilogBits()/8,nil,true ):instantiate("buffer"):setCoherent(true) )
    local reading = S.eq( phase, S.constant(0,types.uint(phasebits)) ):disablePipelining()
    
    local pipelines = {sBuffer:writeAndReturnOriginal(S.tuple{xpos,S.cast(sinp,types.bits(ITYPE:verilogBits()))}, reading), sPhase:setBy( S.constant(1, types.uint(16)) )}
    local out = S.select( reading, sinp, S.cast(sBuffer:read(xpos),ITYPE) ) 
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines, nil, CE) )
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()),CE) )

    return systolicModule
  end

  return modules.waitOnInput( rigel.newFunction(res) )
end)

-- Stateful{uint8,uint8,uint8...} -> Stateful(uint8)
-- Ignores the counts. Just interleaves between streams.
-- N: number of streams.
-- period==0: ABABABAB, period==1: AABBAABBAABB, period==2: AAAABBBB
modules.interleveSchedule = memoize(function( N, period )
  err( type(N)=="number", "N must be number")
  err( J.isPowerOf2(N), "N must be power of 2")
  err( type(period)=="number", "period must be number")
  local res = {kind="interleveSchedule", N=N, period=period, delay=0, inputType=types.null(), outputType=types.uint(8), sdfInput={{1,1}}, sdfOutput={{1,1}}, stateful=true }
  res.name = "InterleveSchedule_"..N.."_"..period

  if terralib~=nil then res.terraModule = MT.interleveSchedule( N, period ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.uint(8), "interleve schedule phase %d", true):instantiate("printInst") ) end
    
    local inp = S.parameter("process_input", rigel.lower(res.inputType) )
    local phase = systolicModule:add( Ssugar.regByConstructor( types.uint(8), fpgamodules.incIfWrap( types.uint(8), 255, 1 ) ):setInit(0):CE(true):instantiate("interlevePhase") )
    local log2N = math.log(N)/math.log(2)
    
    local CE = S.CE("CE")
    local pipelines = {phase:setBy( S.constant(true,types.bool()))}
    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(phase:get())) end
    
    systolicModule:addFunction( S.lambda("process", inp, S.cast(S.cast(S.bitSlice(phase:get(),period,period+log2N-1),types.uint(log2N)), types.uint(8)), "process_output", pipelines, nil, CE ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(8)))}, S.parameter("reset",types.bool()),CE) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- wtop is the width of the largest (top) pyramid level
modules.pyramidSchedule = memoize(function( depth, wtop, T )
  err(type(depth)=="number", "depth must be number")
  err(type(wtop)=="number", "wtop must be number")
  err(type(T)=="number", "T must be number")
  local res = {kind="pyramidSchedule", wtop=wtop, depth=depth, T=T, delay=0, inputType=types.null(), outputType=types.uint(8), sdfInput={{1,1}}, sdfOutput={{1,1}}, stateful=true }
  res.name = "PyramidSchedule_depth_"..tostring(depth).."_wtop_"..tostring(wtop).."_T_"..tostring(T)

  if terralib~=nil then res.terraModule = MT.pyramidSchedule( depth, wtop, T ) end

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

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(8), types.uint(16),types.uint(log2N)}, "pyramid schedule addr %d wcnt %d out %d", true):instantiate("printInst") ) end
    
    local tokensPerAddr = (wtop*minTargetW)/T
    
    local inp = S.parameter("process_input", rigel.lower(res.inputType) )
    local addr = systolicModule:add( Ssugar.regByConstructor( types.uint(8), fpgamodules.incIfWrap( types.uint(8), patternTotal-1, 1 ) ):setInit(0):CE(true):instantiate("patternAddr") )
    local wcnt = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), tokensPerAddr-1, 1 ) ):setInit(0):CE(true):instantiate("wcnt") )
    local patternRam = systolicModule:add(fpgamodules.ram128(types.uint(log2N), pattern):instantiate("patternRam"))

    
    local CE = S.CE("CE")
    local pipelines = {addr:setBy( S.eq(wcnt:get(),S.constant(tokensPerAddr-1,types.uint(16))):disablePipelining() )}
    table.insert(pipelines, wcnt:setBy( S.constant(true,types.bool()) ) )
    
    local out = patternRam:read(addr:get())

    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(S.tuple{addr:get(),wcnt:get(),out})) end
    
    systolicModule:addFunction( S.lambda("process", inp, out, "process_output", pipelines, nil, CE ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {addr:set(S.constant(0,types.uint(8))), wcnt:set(S.constant(0,types.uint(16)))}, S.parameter("reset",types.bool()),CE) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- WARNING: validOut depends on readyDownstream
modules.toHandshakeArray = memoize(function( A, inputRates )
  err( types.isType(A), "A must be type" )
  rigel.expectBasic(A)
  err( type(inputRates)=="table", "inputRates must be table")
  assert( SDFRate.isSDFRate(inputRates))

  local res = {kind="toHandshakeArray", A=A, inputRates = inputRates}
  res.inputType = types.array2d( rigel.Handshake(A), #inputRates )
  res.outputType = rigel.HandshakeArray( A, #inputRates )
  res.sdfInput = inputRates
  res.sdfOutput = inputRates
  res.stateful = false
  res.name = sanitize("ToHandshakeArray_"..tostring(A).."_"..#inputRates)

  function res:sdfTransfer( I, loc ) 
    err(#I[1]==#inputRates, "toHandshakeArray: incorrect number of input streams. Is "..(#I[1]).." but expected "..(#inputRates) )
    return I 
  end
  
  if terralib~=nil then res.terraModule = MT.toHandshakeArray( res,A, inputRates ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name):onlyWire(true)

    local printStr = "IV ["..table.concat(J.broadcast("%d",#inputRates),",").."] OV %d readyDownstream %d/"..(#inputRates-1)
    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple(J.concat(J.broadcast(types.bool(),#inputRates+1),{types.uint(8)})), printStr):instantiate("printInst") ) end
    
    local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
    
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
    
    local validOut = J.foldt( validList, function(a,b) return S.__or(a,b) end, "X" )
    
    local pipelines = {}
    local tab = J.concat( J.concat(inpValid,{validOut}), {readyDownstream})
    assert(#tab==(#inputRates+2))
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple(tab) ) ) end
    
    local dataOut = fpgamodules.wideMux( inpData, readyDownstream )
    systolicModule:addFunction( S.lambda("process", inp, S.tuple{dataOut,validOut} , "process_output", pipelines) )
    
    local readyOut = J.map(J.range(#inputRates), function(i) return S.eq(S.constant(i-1,types.uint(8)), readyDownstream) end )
    systolicModule:addFunction( S.lambda("ready", readyDownstream, S.cast(S.tuple(readyOut),types.array2d(types.bool(),#inputRates)), "ready" ) )

    return systolicModule
  end

  return rigel.newFunction( res )
end)

-- inputRates is a list of SDF rates
-- {StatefulHandshakRegistered(A),StatefulHandshakRegistered(A),...} -> StatefulHandshakRegistered({A,stream:uint8}),
-- where stream is the ID of the input that corresponds to the output
modules.serialize = memoize(function( A, inputRates, Schedule, X )
  err( types.isType(A), "A must be type" )
  err( type(inputRates)=="table", "inputRates must be table")
  assert( SDFRate.isSDFRate(inputRates) )
  err( rigel.isFunction(Schedule), "schedule must be darkroom function")
  err( rigel.lower(Schedule.outputType)==types.uint(8), "schedule function has incorrect output type, "..tostring(Schedule.outputType))
  rigel.expectBasic(A)
  assert(X==nil)

  local res = {kind="serialize", A=A, inputRates=inputRates, schedule=Schedule}
  res.inputType = rigel.HandshakeArray( A, #inputRates )
  res.outputType = rigel.HandshakeTmuxed( A, #inputRates )
  err( type(Schedule.stateful)=="boolean", "Schedule missing stateful annotation")
  res.stateful = Schedule.stateful
  res.name = sanitize("Serialize_"..tostring(A).."_"..#inputRates)

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

  if terralib~=nil then res.terraModule = MT.serialize( res, A, inputRates, Schedule) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name):onlyWire(true)

    local scheduler = systolicModule:add( Schedule.systolicModule:instantiate("Scheduler") )
    local printInst
    if DARKROOM_VERBOSE then printInst= systolicModule:add( S.module.print( types.tuple{types.uint(8),types.bool(),types.uint(8),types.bool()}, "Serialize OV %d/"..(#inputRates-1).." readyDownstream %d ready %d/"..(#inputRates-1).." stepSchedule %d"):instantiate("printInst") ) end
    local resetValid = S.parameter("reset_valid", types.bool() )
    
    local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
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
    
    systolicModule:addFunction( S.lambda("process", inp, S.tuple{ inpData, validOut } , "process_output", pipelines ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, resetValid ) )
    
    systolicModule:addFunction( S.lambda("ready", readyDownstream, readyOut, "ready" ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- WARNING: ready depends on ValidIn
modules.demux = memoize(function( A, rates, X )
  err( types.isType(A), "A must be type" )
  err( type(rates)=="table", "rates must be table")
  assert( SDFRate.isSDFRate(rates) )
  rigel.expectBasic(A)
  assert(X==nil)

  local res = {kind="demux", A=A, rates=rates}

  res.inputType = rigel.HandshakeTmuxed( A, #rates )
  res.outputType = types.array2d(rigel.Handshake(A), #rates)
  res.stateful = false
  res.name = sanitize("Demux_"..tostring(A).."_"..#rates)

  local sdfSum = rates[1][1]/rates[1][2]
  for i=2,#rates do sdfSum = sdfSum + (rates[i][1]/rates[i][2]) end
  err(sdfSum==1, "rates must sum to 1")

  res.sdfInput = rates
  res.sdfOutput = rates

  function res:sdfTransfer( I, loc ) 
    err(#I[1]==#rates, "demux: incorrect number of input streams. Is "..(#I[1]).." but expected "..(#rates) )
    return I 
  end

  if terralib~=nil then res.terraModule = MT.demux(res,A,rates) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name):onlyWire(true)

    local printInst
    if DARKROOM_VERBOSE then 
      printInst = systolicModule:add( S.module.print( types.tuple( J.concat({types.uint(8)},J.broadcast(types.bool(),#rates+1))), "Demux IV %d readyDownstream ["..table.concat(J.broadcast("%d",#rates),",").."] ready %d"):instantiate("printInst") ) 
    end

    local resetValid = S.parameter("reset_valid", types.bool() )
    
    local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
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
    
    local readyOut = J.foldt( readyOut, function(a,b) return S.__or(a,b) end, "X" )
    readyOut = S.__or(readyOut, S.eq(inpValid, S.constant(#rates, types.uint(8)) ) )
    
    local printList = {}
    table.insert(printList,inpValid)
    for i=1,#rates do table.insert( printList, S.index(readyDownstream,i-1) ) end
    table.insert(printList,readyOut)
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple(printList) ) ) end
    
    systolicModule:addFunction( S.lambda("process", inp, S.cast(S.tuple(out),rigel.lower(res.outputType)) , "process_output", pipelines ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, resetValid ) )
    
    systolicModule:addFunction( S.lambda("ready", readyDownstream, readyOut, "ready" ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

modules.flattenStreams = memoize( function( A, rates, X )
  err( types.isType(A), "A must be type" )
  err( type(rates)=="table", "rates must be table")
  assert( SDFRate.isSDFRate(rates) )
  rigel.expectBasic(A)
  assert(X==nil)

  local res = {kind="flattenStreams", A=A, rates=rates}

  res.inputType = rigel.HandshakeTmuxed( A, #rates )
  res.outputType = rigel.Handshake(A)
  res.stateful = false

  local sdfSum = rates[1][1]/rates[1][2]
  for i=2,#rates do sdfSum = sdfSum + (rates[i][1]/rates[i][2]) end
  err(sdfSum==1, "rates must sum to 1")

  res.sdfInput = rates
  res.sdfOutput = {{1,1}}
  res.name = sanitize("FlattenStreams_"..tostring(A).."_"..#rates)

  if terralib~=nil then res.terraModule = MT.flattenStreams(res,A,rates) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name):onlyWire(true)

    local resetValid = S.parameter("reset_valid", types.bool() )
    
    local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
    local inpData = S.index(inp,0)
    local inpValid = S.index(inp,1)
    local readyDownstream = S.parameter( "ready_downstream", types.bool() )
    
    local pipelines = {}
    local resetPipelines = {}
    
    systolicModule:addFunction( S.lambda("process", inp, S.tuple{inpData,S.__not(S.eq(inpValid,S.constant(#rates,types.uint(8))))} , "process_output", pipelines ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, resetValid ) )
    
    systolicModule:addFunction( S.lambda("ready", readyDownstream, readyDownstream, "ready" ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- Takes StatefulHandshake(A) to (StatefulHandshake(A))[N]
-- HACK(?!): when we fan-out a handshake stream, we need to synchronize the downstream modules.
-- (IE if one is ready but the other isn't, we need to stall both).
-- We do that here by modifying the valid bit combinationally!! This could potentially
-- cause a combinationaly loop (validOut depends on readyDownstream) if another later unit does the opposite
-- (readyUpstream depends on validIn). But I don't think we will have any units that do that??
modules.broadcastStream = memoize(function(A,N,X)
  err( types.isType(A), "A must be type")
  rigel.expectBasic(A)
  err( type(N)=="number", "N must be number")
  assert(X==nil)

  local res = {kind="broadcastStream", A=A, N=N, inputType = rigel.Handshake(A), outputType = types.array2d( rigel.Handshake(A), N), stateful=false}

  res.sdfInput = {{1,1}}
  res.sdfOutput = J.broadcast({1,1},N)
  res.name = sanitize("BroadcastStream_"..tostring(A).."_"..N)

  if terralib~=nil then res.terraModule = MT.broadcastStream(res,A,N) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name):onlyWire(true)

    local printStr = "IV %d readyDownstream ["..table.concat( J.broadcast("%d",N),",").."] ready %d"
    local printInst
    if DARKROOM_VERBOSE then 
      printInst = systolicModule:add( S.module.print( types.tuple( J.broadcast(types.bool(),N+2)), printStr):instantiate("printInst") ) 
    end

    local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
    local inpData = S.index(inp,0)
    local inpValid = S.index(inp,1)
    local readyDownstream = S.parameter( "ready_downstream", types.array2d(types.bool(),N) )
    local readyDownstreamList = J.map(J.range(N), function(i) return S.index(readyDownstream,i-1) end )
    
    local allReady = J.foldt( readyDownstreamList, function(a,b) return S.__and(a,b) end, "X" )
    local validOut = S.__and(inpValid,allReady)
    local out = S.tuple( J.broadcast(S.tuple{inpData, validOut}, N))
    out = S.cast(out, rigel.lower(res.outputType) )
    
    local pipelines = {}
    
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple( J.concat( J.concat({inpValid}, readyDownstreamList),{allReady}) ) ) ) end
    
    systolicModule:addFunction( S.lambda("process", inp, out, "process_output", pipelines ) )

    local resetValid = S.parameter("reset_valid", types.bool() )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", nil, resetValid ) )

    systolicModule:addFunction( S.lambda("ready", readyDownstream, allReady, "ready" ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- output type: {uint16,uint16}[T]
modules.posSeq = memoize(function( W, H, T )
  err(type(W)=="number","posSeq: W must be number")
  err(type(H)=="number","posSeq: H must be number")
  err(type(T)=="number","posSeq: T must be number")
  err(W>0, "posSeq: W must be >0");
  err(H>0, "posSeq: H must be >0");
  err(T>=1, "posSeq: T must be >=1");
                           
  local res = {kind="posSeq", T=T, W=W, H=H }
  res.inputType = types.null()
  res.outputType = types.array2d(types.tuple({types.uint(16),types.uint(16)}),T)
  res.stateful = true
  res.sdfInput, res.sdfOutput = {},{{1,1}}
  res.delay = 0
  res.name = "PosSeq_W"..W.."_H"..H.."_T"..T

  if terralib~=nil then res.terraModule = MT.posSeq(res,W,H,T) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local posX = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), W-T, T ) ):setInit(0):CE(true):instantiate("posX_posSeq") )
    local posY = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), H-1 ) ):setInit(0):CE(true):instantiate("posY_posSeq") )

    local printInst

    if DARKROOM_VERBOSE then 
      printInst = systolicModule:add( S.module.print( types.tuple{types.uint(16),types.uint(16)}, "x %d y %d", true):instantiate("printInst") ) 
    end
    
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

    systolicModule:addFunction( S.lambda("process", S.parameter("pinp",types.null()), S.cast(S.tuple(out),types.array2d(types.tuple{types.uint(16),types.uint(16)},T)), "process_output", pipelines, nil, CE ) )

    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {posX:set(S.constant(0,types.uint(16))), posY:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()), CE) )

    systolicModule:complete()

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- this takes a pure function f : {{int32,int32}[T],inputType} -> outputType
-- and drives the first tuple with (x,y) coord
-- returns a function with type Stateful(inputType)->Stateful(outputType)
-- sdfOverride: we can use this to define stateful->StatefulV interfaces etc, so we may want to override the default SDF rate
modules.liftXYSeq = memoize(function( name, generatorStr, f, W, H, T, X )
  err( type(name)=="string", "liftXYSeq: name must be string" )
  err( type(generatorStr)=="string", "liftXYSeq: generatorStr must be string" )
  err( rigel.isFunction(f), "liftXYSeq: f must be function")
  err( type(W)=="number", "liftXYSeq: W must be number")
  err( type(H)=="number", "liftXYSeq: H must be number")
  err( type(T)=="number", "liftXYSeq: T must be number")
  err( X==nil, "liftXYSeq: too many arguments")

  local inputType = f.inputType.list[2]

  local inp = rigel.input( inputType )

  local p = rigel.apply("p", modules.posSeq(W,H,T) )
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)

  local out = rigel.apply("m", f, rigel.concat("ptup", {p,inp}) )
  return modules.lambda( "liftXYSeq_"..name, inp, out,nil,nil,generatorStr )
end)

-- this takes a function f : {{uint16,uint16},inputType} -> outputType
-- and returns a function of type inputType[T]->outputType[T]
function modules.liftXYSeqPointwise( name, generatorStr, f, W, H, T, X )
  err( type(name)=="string", "liftXYSeqPointwise: name must be string" )
  err( type(generatorStr)=="string", "liftXYSeqPointwise: generatorStr must be string" )
  err( rigel.isFunction(f), "liftXYSeqPointwise: f must be function")
  err( f.inputType:isTuple(), "liftXYSeqPointwise: f input type must be tuple")
  err( type(W)=="number", "liftXYSeqPointwise: W must be number" )
  err( type(H)=="number", "liftXYSeqPointwise: H must be number" )
  err( type(T)=="number", "liftXYSeqPointwise: T must be number" )
  err( X==nil, "liftXYSeqPointwise: too many arguments" )

  local fInputType = f.inputType.list[2]
  local inputType = types.array2d(fInputType,T)
  local xyinner = types.tuple{types.uint(16),types.uint(16)}
  local xyType = types.array2d(xyinner,T)
  local innerInputType = types.tuple{xyType, inputType}

  local inp = rigel.input( innerInputType )
  local unpacked = rigel.apply("unp", modules.SoAtoAoS(T,1,{xyinner,fInputType}), inp) -- {{uint16,uint16},A}[T]
  local out = rigel.apply("f", modules.map(f,T), unpacked )
  local ff = modules.lambda("liftXYSeqPointwise_"..f.kind, inp, out )
  return modules.liftXYSeq(name, generatorStr, ff, W, H, T )
end

-- takes an image of size A[W,H] to size A[W-L-R,H-B-Top]
modules.cropSeq = memoize(function( A, W, H, T, L, R, B, Top, X )
  err( types.isType(A), "cropSeq: type must be rigel type ")
  err( type(W)=="number", "cropSeq: W must be number"); err(W>=0, "cropSeq: W must be >=0")
  err( type(H)=="number", "cropSeq: H must be number"); err(H>=0, "cropSeq: H must be >=0")
  err( type(T)=="number", "cropSeq: T must be number"); err(T>=0, "cropSeq: T must be >=0")
  err( type(L)=="number", "cropSeq: L must be number"); err(L>=0, "cropSeq: L must be >=0")
  err( type(R)=="number", "cropSeq: R must be number"); err(R>=0, "cropSeq: R must be >=0")
  err( type(B)=="number", "cropSeq: B must be number"); err(B>=0, "cropSeq: B must be >=0")
  err( type(Top)=="number", "cropSeq: Top must be number"); err(Top>=0, "cropSeq: Top must be >=0")

  err(T>=1,"cropSeq T must be <1")

  err( L>=0, "cropSeq, L must be <0")
  err( R>=0, "cropSeq, R must be <0")
  err( W%T==0, "cropSeq, W%T must be 0")
  err( L%T==0, "cropSeq, L%T must be 0")
  err( R%T==0, "cropSeq, R%T must be 0")
  err( (W-L-R)%T==0, "cropSeq, (W-L-R)%T must be 0")
  err( X==nil, "cropSeq: too many arguments" )

  local inputType = types.array2d(A,T)
  local outputType = types.tuple{inputType,types.bool()}
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)
  local innerInputType = types.tuple{xyType, inputType}

  local modname = J.verilogSanitize("CropSeq_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_L"..tostring(L).."_R"..tostring(R).."_B"..tostring(B).."_Top"..tostring(Top))

  local f = modules.lift( modname, innerInputType, outputType, 0, 
    function(sinp)
      local sdata = S.index(sinp,1)
      local sx, sy = S.index(S.index(S.index(sinp,0),0),0), S.index(S.index(S.index(sinp,0),0),1)
      local sL,sB = S.constant(L,types.uint(16)),S.constant(B,types.uint(16))
      local sWmR,sHmTop = S.constant(W-R,types.uint(16)),S.constant(H-Top,types.uint(16))
      
      -- verilator lint workaround
      local lbcheck
      if L==0 and B==0 then
        lbcheck = S.constant(true,types.bool())
      elseif L~=0 and B==0 then
        lbcheck = S.ge(sx,sL)
      elseif L==0 and B~=0 then
        lbcheck = S.ge(sy,sB)
      else
        lbcheck = S.__and(S.ge(sx,sL),S.ge(sy,sB))
      end
      
      local trcheck = S.__and(S.lt(sx,sWmR),S.lt(sy,sHmTop))
      
      local svalid = S.__and(lbcheck,trcheck)
      
      return S.tuple{sdata,svalid}
    end, 
    function()
      return MT.cropSeqFn( innerInputType, outputType, A, W, H, T, L, R, B, Top ) 
    end, nil,
    {{((W-L-R)*(H-B-Top))/T,(W*H)/T}})

  return modules.liftXYSeq( modname, "rigel.cropSeq", f, W, H, T  )
end)

-- takes an image of size A[W,H] to size A[W-L-R,H-B-Top].
modules.crop = memoize(function( A, W, H, L, R, B, Top, X )
	err( types.isType(A), "A must be a type")

  err( A~=nil, "crop A==nil" )
  err( W~=nil, "crop W==nil" )
  err( H~=nil, "crop H==nil" )
  err( L~=nil, "crop L==nil" )
  err( R~=nil, "crop R==nil" )
  err( B~=nil, "crop B==nil" )
  err( Top~=nil, "crop Top==nil" )
  err( X==nil, "crop: too many arguments" )
  
  J.map({W=W,H=H,L=L,R=R,B=B,Top=Top},function(n,k)
        err(type(n)=="number","crop expected number for argument "..k.." but is "..tostring(n)); 
        err(n==math.floor(n),"crop non-integer argument "..k..":"..n); 
        err(n>=0,"n<0") end)

  local res = {kind="crop", type=A, L=L, R=R, B=B, Top=Top, width=W, height=H}
  res.inputType = types.array2d(A,W,H)
  res.outputType = types.array2d(A,W-L-R,H-B-Top)
  res.stateful = false
  res.sdfInput, res.sdfOutput = {{1,1}}, {{1,1}}
  res.delay=0
  res.name = "Crop_"..verilogSanitize(tostring(A)).."_W"..W.."_H"..H.."_L"..L.."_R"..R.."_B"..B.."_Top"..Top
--------
  if terralib~=nil then res.terraModule = MT.crop( res, A, W, H, L, R, B, Top ) end

  function res.makeSystolic()
    err(false, "NYI - crop modules systolic version")
	end

  return rigel.newFunction(res)
end)

-- takes an image of size A[W,H] to size A[W+L+R,H+B+Top]. Fills the new pixels with value 'Value'
-- sequentialized to throughput T
modules.padSeq = memoize(function( A, W, H, T, L, R, B, Top, Value )
  err( types.isType(A), "A must be a type")

  err( A~=nil, "padSeq A==nil" )
  err( W~=nil, "padSeq W==nil" )
  err( H~=nil, "padSeq H==nil" )
  err( T~=nil, "padSeq T==nil" )
  err( L~=nil, "padSeq L==nil" )
  err( R~=nil, "padSeq R==nil" )
  err( B~=nil, "padSeq B==nil" )
  err( Top~=nil, "padSeq Top==nil" )
  err( Value~=nil, "padSeq Value==nil" )
  
  J.map({W=W,H=H,T=T,L=L,R=R,B=B,Top=Top},function(n,k)
        err(type(n)=="number","PadSeq expected number for argument "..k.." but is "..tostring(n)); 
        err(n==math.floor(n),"PadSeq non-integer argument "..k..":"..n); 
        err(n>=0,"n<0") end)

  A:checkLuaValue(Value)
  err(T>=1, "padSeq, T<1")

  err( W%T==0, "padSeq, W%T~=0, W="..tostring(W).." T="..tostring(T))
  err( L==0 or (L>=T and L%T==0), "padSeq, L<T or L%T~=0 (L="..tostring(L)..",T="..tostring(T)..")")
  err( R==0 or (R>=T and R%T==0), "padSeq, R<T or R%T~=0")
  err( (W+L+R)%T==0, "padSeq, (W+L+R)%T~=0")

  local res = {kind="padSeq", type=A, T=T, L=L, R=R, B=B, Top=Top, value=Value, width=W, height=H}
  res.inputType = types.array2d(A,T)
  res.outputType = rigel.RV(types.array2d(A,T))
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{ (W*H)/T, ((W+L+R)*(H+B+Top))/T}}, {{1,1}}
  res.delay=0
  res.name = verilogSanitize("PadSeq_"..tostring(A).."_W"..W.."_H"..H.."_L"..L.."_R"..R.."_B"..B.."_Top"..Top.."_T"..T.."_Value"..tostring(Value))

  if terralib~=nil then res.terraModule = MT.padSeq( res, A, W, H, T, L, R, B, Top, Value ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local posX = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap( types.uint(32), W+L+R-T, T ) ):CE(true):setInit(0):instantiate("posX_padSeq") ) 
    local posY = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), H+Top+B-1) ):CE(true):setInit(0):instantiate("posY_padSeq") ) 
    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(16),types.uint(16),types.bool()}, "x %d y %d ready %d", true ):instantiate("printInst") ) end
    
    local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local pvalid = S.parameter("process_valid", types.bool() )
    
    local C1 = S.ge( posX:get(), S.constant(L,types.uint(32)))
    local C2 = S.lt( posX:get(), S.constant(L+W,types.uint(32)))
    local xcheck
    
    if L==0 then
      xcheck = C2 -- verilator lint: C1 always true
    else
      xcheck = S.__and(C1,C2)
    end
    
    local C3 = S.ge( posY:get(), S.constant(B,types.uint(16)))
    local C4 = S.lt( posY:get(), S.constant(B+H,types.uint(16)))
    local ycheck
    
    if B==0 then
      ycheck = C4 -- verilator lint: C1 always true
    else
      ycheck = S.__and(C3,C4)
    end
    
    local isInside = S.__and(xcheck,ycheck)
    local readybit = isInside:disablePipelining()
    
    local pipelines={}

    local incY = S.eq( posX:get(), S.constant(W+L+R-T,types.uint(32))  ):disablePipelining()
    pipelines[1] = posY:setBy( incY )
    pipelines[2] = posX:setBy( S.constant(true,types.bool()) )

    local ValueBroadcast = S.cast( S.tuple( J.broadcast(S.constant(Value,A),T)) ,types.array2d(A,T))
    local ConstTrue = S.constant(true,types.bool())

    local out = S.select( readybit, pinp, ValueBroadcast )
    
    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process( S.tuple{ posX:get(), posY:get(), readybit } ) ) end
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", pinp, S.tuple{out,ConstTrue}, "process_output", pipelines, pvalid, CE) )
    
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {posX:set(S.constant(0,types.uint(32))), posY:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()), CE) )
    
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), readybit, "ready", {} ) )

    return systolicModule
  end

  return modules.waitOnInput(rigel.newFunction(res))
                          end)


--StatefulRV. Takes A[inputRate,H] in, and buffers to produce A[outputRate,H]
modules.changeRate = memoize(function(A, H, inputRate, outputRate, X)
  err( types.isType(A), "A should be a type")
  err( type(H)=="number", "H should be number")
  err( type(inputRate)=="number", "inputRate should be number")
  err( inputRate==math.floor(inputRate), "inputRate should be integer")
  err( type(outputRate)=="number", "outputRate should be number")
  err( outputRate==math.floor(outputRate), "outputRate should be integer")
  err( X==nil, "changeRate: too many arguments")

  local maxRate = math.max(inputRate,outputRate)

  err( maxRate % inputRate == 0, "maxRate % inputRate ~= 0")
  err( maxRate % outputRate == 0, "maxRate % outputRate ~=0")
  rigel.expectBasic(A)

  local inputCount = maxRate/inputRate
  local outputCount = maxRate/outputRate

  local res = {kind="changeRate", type=A, H=H, inputRate=inputRate, outputRate=outputRate}
  res.inputType = types.array2d(A,inputRate,H)
  res.outputType = rigel.RV(types.array2d(A,outputRate,H))
  res.stateful = true
--  res.delay = (math.log(maxRate/inputRate)/math.log(2)) + (math.log(maxRate/outputRate)/math.log(2))
  res.delay = 0
  res.name = J.verilogSanitize("ChangeRate_"..tostring(A).."_from"..inputRate.."_to"..outputRate.."_H"..H)

  if inputRate>outputRate then -- 8 to 4
    res.sdfInput, res.sdfOutput = {{outputRate,inputRate}},{{1,1}}
  else -- 4 to 8
    res.sdfInput, res.sdfOutput = {{1,1}},{{inputRate,outputRate}}
  end

  function res.makeSystolic()
    local systolicModule= Ssugar.moduleConstructor(res.name)

    local svalid = S.parameter("process_valid", types.bool() )
    local rvalid = S.parameter("reset", types.bool() )
    local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
    
    local regs = J.map( J.range(maxRate), function(i) return systolicModule:add(S.module.reg(A,true):instantiate("Buffer_"..i)) end )
    
    if inputRate>outputRate then
      
      -- 8 to 4
      local shifterReads = {}
      for i=0,outputCount-1 do
        table.insert(shifterReads, S.slice( pinp, i*outputRate, (i+1)*outputRate-1, 0, H-1 ) )
      end
      local out, pipelines, resetPipelines, ready = fpgamodules.addShifterSimple( systolicModule, shifterReads, DARKROOM_VERBOSE )
      
      local CE = S.CE("CE")
      systolicModule:addFunction( S.lambda("process", pinp, S.tuple{ out, S.constant(true,types.bool()) }, "process_output", pipelines, svalid, CE) )
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, rvalid, CE ) )
      systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), ready, "ready", {} ) )
      
    else -- inputRate <= outputRate. 4 to 8
      assert(H==1) -- NYI
      
      local sPhase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), inputCount-1) ):CE(true):instantiate("phase_changerateup") )
      local printInst
      if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(16),types.array2d(A,outputRate)}, "phase %d buffer %h", true ):instantiate("printInst") ) end
      local ConstTrue = S.constant(true,types.bool())
      local CE = S.CE("CE")
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", { sPhase:set(S.constant(0,types.uint(16))) }, rvalid, CE ) )
      
      -- in the first cycle (first time inputPhase==0), we don't have any data yet. Use the sWroteLast variable to keep track of this case
      local validout = S.eq(sPhase:get(),S.constant(inputCount-1,types.uint(16))):disablePipelining()
      
      local out = concat2dArrays(J.map(J.range(inputCount-1,0), function(i) return pinp(i) end))
      local pipelines = {sPhase:setBy(ConstTrue)} 
      if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(S.tuple{sPhase:get(),out})) end
      
      systolicModule:addFunction( S.lambda("process", pinp, S.tuple{out,validout}, "process_output", pipelines, svalid, CE) )
      systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), ConstTrue, "ready" ) )
    end

    return systolicModule
  end

  if terralib~=nil then res.terraModule = MT.changeRate(res, A, H, inputRate, outputRate,maxRate,outputCount,inputCount ) end

  return modules.waitOnInput(rigel.newFunction(res))
end)

modules.linebuffer = memoize(function( A, w, h, T, ymin, X )
  assert(w>0); assert(h>0);
  assert(ymin<=0)
  err(X==nil,"linebuffer: too many args!")
  
  -- if W%T~=0, then we would potentially have to do two reads on wraparound. So don't allow this case.
  err( w%T==0, "Linebuffer error, W%T~=0 , W="..tostring(w).." T="..tostring(T))

  local res = {kind="linebuffer", type=A, T=T, w=w, h=h, ymin=ymin }
  rigel.expectBasic(A)
  res.inputType = types.array2d(A,T)
  res.outputType = types.array2d(A,T,-ymin+1)
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 0
  res.name = sanitize("linebuffer_w"..w.."_h"..h.."_T"..T.."_ymin"..ymin.."_A"..tostring(A))

  if terralib~=nil then res.terraModule = MT.linebuffer(res, A, w, h, T, ymin) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local addr = systolicModule:add( S.module.regBy( types.uint(16), fpgamodules.incIfWrap( types.uint(16), (w/T)-1), true, nil ):instantiate("addr") )
    
    local outarray = {}
    local evicted
    
    local bits = rigel.lower(res.inputType):verilogBits()
    local bytes = J.nearestPowerOf2(J.upToNearest(8,bits)/8)
    local sizeInBytes = J.nearestPowerOf2((w/T)*bytes)

    local bramMod = fpgamodules.bramSDP( true, sizeInBytes, bytes, nil, nil, true )
    local addrbits = math.log(sizeInBytes/bytes)/math.log(2)
    
    for y=0,-ymin do
      local lbinp = evicted
      if y==0 then lbinp = sinp end
      for x=1,T do outarray[x+(-ymin-y)*T] = S.index(lbinp,x-1) end
      
      if y<-ymin then
        -- last line doesn't need a ram
        local BRAM = systolicModule:add( bramMod:instantiate("lb_m"..math.abs(y)) )
        
        local upcast = S.cast(lbinp,types.bits(bits))
        upcast = S.cast(upcast,types.bits(bytes*8))
        
        evicted = BRAM:writeAndReturnOriginal( S.tuple{ S.cast(addr:get(),types.uint(addrbits)), upcast} )
        evicted = S.bitSlice(evicted,0,bits-1)
        evicted = S.cast( evicted, rigel.lower(res.inputType) )
      end
    end

    local CE = S.CE("CE")

    systolicModule:addFunction( S.lambdaTab
      { name="process", 
        input=sinp, 
        output=S.cast( S.tuple( outarray ), rigel.lower(res.outputType) ), 
        outputName="process_output", 
        pipelines={addr:setBy(S.constant(true, types.bool()))}, 
        CE=CE } )

    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {addr:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()),CE) )
    
    return systolicModule
  end

  return rigel.newFunction(res)
end)

modules.sparseLinebuffer = memoize(function( A, imageW, imageH, rowWidth, ymin, defaultValue, X )
  err(imageW>0,"sparseLinebuffer: imageW must be >0"); 
  err(imageH>0,"sparseLinebuffer: imageH must be >0");
  err(ymin<=0,"sparseLinebuffer: ymin must be <=0");
  assert(X==nil)
  err(type(rowWidth)=="number","rowWidth must be number")
  A:checkLuaValue(defaultValue)

  local res = {kind="sparseLinebuffer", type=A, imageW=imageW, imageH=imageH, ymin=ymin, rowWidth=rowWidth }
  rigel.expectBasic(A)
  res.inputType = types.tuple{A,types.bool()}
  res.outputType = types.array2d(A,1,-ymin+1)
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 0
  res.name = sanitize("SparseLinebuffer_w"..imageW.."_h"..imageH.."_ymin"..ymin.."_A"..tostring(A).."_rowWidth"..tostring(rowWidth))

  if terralib~=nil then res.terraModule = MT.sparseLinebuffer(A, imageW, imageH, rowWidth, ymin, defaultValue) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
    
    -- index 1 is ymin+1 row, index 2 is ymin+2 row etc
    -- remember ymin is <0
    local fifos = {}
    local xlocfifos = {}
    
    local resetPipelines = {}
    local pipelines = {}
    
    local currentX = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), imageW-1, 1 ) ):CE(true):setInit(0):instantiate("currentX") )
    table.insert( pipelines, currentX:setBy( S.constant(true,types.bool()) ) )
    table.insert( resetPipelines, currentX:set( S.constant( 0, types.uint(16) ) ) )
    
    for i=1,-ymin do
      -- TODO hack: due to our FIFO implementation, it needs to have 3 items of slack to meet timing. Just work around this by expanding our # of items by 3.
      local allocItems = rowWidth+3
      table.insert( fifos, systolicModule:add( fpgamodules.fifo(A,allocItems,false):instantiate("fifo"..tostring(i)) ) )
      table.insert( xlocfifos, systolicModule:add( fpgamodules.fifo(types.uint(16),allocItems,false):instantiate("xloc"..tostring(i)) ) )
      
      table.insert( resetPipelines, fifos[#fifos]:pushBackReset() )
      table.insert( resetPipelines, fifos[#fifos]:popFrontReset() )
      
      table.insert( resetPipelines, xlocfifos[#xlocfifos]:pushBackReset() )
      table.insert( resetPipelines, xlocfifos[#xlocfifos]:popFrontReset() )
    end
    
    local outputArray = {}
    
    for outi=1,-ymin do
      local readyToRead = S.__and( xlocfifos[outi]:hasData(), S.eq(xlocfifos[outi]:peekFront(),currentX:get() ):disablePipeliningSingle() ):disablePipeliningSingle()
      
      local dat = fifos[outi]:popFront(nil,readyToRead)
      local xloc = xlocfifos[outi]:popFront(nil,readyToRead)
      
      if outi>1 then
        table.insert( pipelines, fifos[outi-1]:pushBack( dat, readyToRead ) )
        table.insert( pipelines, xlocfifos[outi-1]:pushBack( xloc, readyToRead ) )
      else
        -- has to appear somewhere
        table.insert( pipelines, xloc )
      end
      
      outputArray[outi] = S.select(readyToRead,dat,S.constant(defaultValue,A)):disablePipeliningSingle()
    end
    
    local inputPx = S.index(sinp,0)
    local inputPxValid = S.index(sinp,1)
    local shouldPush = S.__and(inputPxValid, fifos[-ymin]:ready()):disablePipeliningSingle()
    
    -- if we can't store the pixel, we just thrown it out (even though we could write it out once). We don't want it to appear and disappear.
    -- we don't need to check for overflows later - if it fits into the first FIFO, it'll fit into all of them, I think? Maybe there is some wrap around condition?
    outputArray[-ymin+1] = S.select( shouldPush, inputPx, S.constant( defaultValue, A ) ):disablePipeliningSingle()
    
    table.insert( pipelines, fifos[-ymin]:pushBack( inputPx, shouldPush ) )
    table.insert( pipelines, xlocfifos[-ymin]:pushBack( currentX:get(), shouldPush ) )
    
    local CE = S.CE("CE")
    
    systolicModule:addFunction( S.lambdaTab
      { name="process",
        input=sinp,
        output=S.cast( S.tuple( outputArray ), rigel.lower(res.outputType) ),
        outputName="process_output",
        pipelines=pipelines,
        CE=CE } )
    
    systolicModule:addFunction( S.lambdaTab
      { name="reset",
        input=S.parameter("r",types.null()),
        output=nil,
        outputName="ro",
        pipelines=resetPipelines,
        valid=S.parameter("reset",types.bool()),
        CE=CE } )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- xmin, ymin are inclusive
modules.SSR = memoize(function( A, T, xmin, ymin )
  J.map({T,xmin,ymin}, function(i) assert(type(i)=="number") end)
  assert(ymin<=0)
  assert(xmin<=0)
  assert(T>0)
  local res = {kind="SSR", type=A, T=T, xmin=xmin, ymin=ymin }
  res.inputType = types.array2d(A,T,-ymin+1)
  res.outputType = types.array2d(A,T-xmin,-ymin+1)
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay=0
  res.name = "SSR_W"..(-xmin+1).."_H"..(-ymin+1).."_T"..T.."_A"..verilogSanitize(tostring(A))

  if terralib~=nil then res.terraModule = MT.SSR(res, A, T, xmin, ymin ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local sinp = S.parameter("inp", rigel.lower(res.inputType))
    local pipelines = {}
    local SR = {}
    local out = {}
    for y=0,-ymin do 
      SR[y]={}
      local x = -xmin+T-1
      while(x>=0) do
        if x<-xmin-T then
          SR[y][x] = systolicModule:add( S.module.reg(A,true):instantiate("SR_x"..x.."_y"..y ) )
          table.insert( pipelines, SR[y][x]:set(SR[y][x+T]:get()) )
          out[y*(-xmin+T)+x+1] = SR[y][x]:get()
        elseif x<-xmin then
          SR[y][x] = systolicModule:add( S.module.reg(A,true):instantiate("SR_x"..x.."_y"..y ) )
          table.insert( pipelines, SR[y][x]:set(S.index(sinp,x+(T+xmin),y ) ) )
          out[y*(-xmin+T)+x+1] = SR[y][x]:get()
        else -- x>-xmin
          out[y*(-xmin+T)+x+1] = S.index(sinp,x+xmin,y)
        end

        x = x - 1
      end
    end
    
    local CE = S.CE("process_CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple( out ), rigel.lower(res.outputType)), "process_output", pipelines, nil, CE ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", nil, S.parameter("reset",types.bool()), CE ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

modules.SSRPartial = memoize(function( A, T, xmin, ymin, stride, fullOutput, X )
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
    res.outputType = rigel.RV(types.array2d(A,(-xmin+1),-ymin+1))
  else
    res.outputType = rigel.RV(types.array2d(A,(-xmin+1)*T,-ymin+1))
  end

  res.sdfInput, res.sdfOutput = {{1,1/T}},{{1,1}}
  res.delay=0
  res.name = sanitize("SSRPartial_"..tostring(A).."_T"..tostring(T))

  if terralib~=nil then res.terraModule =  MT.SSRPartial(res,A, T, xmin, ymin, stride, fullOutput) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local P = 1/T
    
    local shiftValues = {}
    local Weach = (-xmin+1)/P -- number of columns in each output

    local W = -xmin+1
    for x=0,W-1 do
      table.insert( shiftValues, sinp( (W-1-x)*P) )
    end
    
    local shifterOut, shifterPipelines, shifterResetPipelines, shifterReading = fpgamodules.addShifter( systolicModule, shiftValues, stride, P, DARKROOM_VERBOSE )
    
    if fullOutput then
      shifterOut = concat2dArrays( shifterOut )
    else
      shifterOut = concat2dArrays( J.slice( shifterOut, 1, Weach) )
    end
    
    local processValid = S.parameter("process_valid",types.bool())
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ shifterOut, processValid }, "process_output", shifterPipelines, processValid, CE) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", shifterResetPipelines,S.parameter("reset",types.bool()), CE) )
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), shifterReading, "ready", {} ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- we could construct this out of liftHandshake, but this is a special case for when we don't need a fifo b/c this is always ready
-- if nilhandshake is true, and f input type is nil, we produce type Handshake(nil)->Handshake(A)
-- if nilhandshake is false or nil, and f input type is nil, we produce type nil->Handshake(A)
-- Handshake(nil) provides a ready bit but no data, vs nil, which provides nothing.
-- (nilhandshake also applies the same way to the output type)
modules.makeHandshake = memoize(function( f, tmuxRates, nilhandshake )
  assert( rigel.isFunction(f) )
  local res = { kind="makeHandshake", fn = f, tmuxRates = tmuxRates }

  if tmuxRates~=nil then
    rigel.expectBasic(f.inputType)
    rigel.expectBasic(f.outputType)
    res.inputType = rigel.HandshakeTmuxed( f.inputType, #tmuxRates )
    res.outputType = rigel.HandshakeTmuxed (f.outputType, #tmuxRates )
    assert( SDFRate.isSDFRate(tmuxRates) )
    res.sdfInput, res.sdfOutput = tmuxRates, tmuxRates

    function res:sdfTransfer( I, loc ) 
      err(#I[1]==#tmuxRates, "MakeHandshake: incorrect number of input streams. Is "..(#I[1]).." but expected "..(#tmuxRates) )
      return I 
    end

  else
    rigel.expectBasic(f.inputType)
    rigel.expectBasic(f.outputType)

    if f.inputType~=types.null() or nilhandshake==true then
      res.inputType = rigel.Handshake(f.inputType)
    else
      res.inputType = types.null()
    end

    if f.outputType~=types.null() or nilhandshake==true then
      res.outputType = rigel.Handshake(f.outputType)
    else
      res.outputType = types.null()
    end
    
    res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  end

  res.stateful = f.stateful
  res.name = "MakeHandshake_"..f.name

  if terralib~=nil then res.terraModule = MT.makeHandshake(res, f, tmuxRates, nilhandshake ) end

  function res.makeSystolic()
    -- We _NEED_ to set an initial value for the shift register output (invalid), or else stuff downstream can get strange values before the pipe is primed
    local systolicModule = Ssugar.moduleConstructor(res.name):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

    local outputCount
    if DARKROOM_VERBOSE then outputCount = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIf() ):CE(true):instantiate("outputCount"):setCoherent(false) ) end
    
    local SRdefault = false
    if tmuxRates~=nil then SRdefault = #tmuxRates end
    local SR = systolicModule:add( fpgamodules.shiftRegister( rigel.extractValid(res.inputType), f.systolicModule:getDelay("process"), SRdefault, true ):instantiate("validBitDelay_"..f.systolicModule.name):setCoherent(false) )
    local inner = systolicModule:add(f.systolicModule:instantiate("inner"))
    local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local rst = S.parameter("reset",types.bool())
    
    local pipelines = {}

    local pready = S.parameter("ready_downstream", types.bool())
    local CE = S.__or(pready,rst)
    
    local outvalid
    local out
    if res.inputType~=types.null() or nilhandshake==true then
      outvalid = SR:pushPop(S.index(pinp,1), S.__not(rst), CE)
      out = S.tuple({inner:process(S.index(pinp,0),S.index(pinp,1), CE), outvalid})
    else
      outvalid = SR:pushPop(S.constant(true,types.bool()), S.__not(rst), CE)
      out = S.tuple({inner:process(nil, S.__not(rst), CE), outvalid})
    end
    
    if DARKROOM_VERBOSE then
      local typelist = {types.bool(),rigel.lower(f.outputType), rigel.extractValid(res.outputType), types.bool(), types.bool(), types.uint(16), types.uint(16)}
      local str = "RST %d O %h OV %d readyDownstream %d ready %d outputCount %d expectedOutput %d"
      local lst = {rst, S.index(out,0), S.index(out,1), pready, pready, outputCount:get(), S.instanceParameter("OUTPUT_COUNT",types.uint(16)) }
      
      if res.inputType~=types.null() then
        table.insert(lst, S.index(pinp,1))
        table.insert(typelist, rigel.extractValid(res.inputType))
        str = str.." IV %d"
      end
      
      local printInst = systolicModule:add( S.module.print( types.tuple(typelist), str):instantiate("printInst") )
      table.insert(pipelines, printInst:process( S.tuple(lst)  ) )
    end
    
    if tmuxRates~=nil then
      if DARKROOM_VERBOSE then table.insert(pipelines,  outputCount:setBy(S.lt(outvalid,S.constant(#tmuxRates,types.uint(8))), S.__not(rst), CE) ) end
    else
      if DARKROOM_VERBOSE then table.insert(pipelines,  outputCount:setBy(outvalid, S.__not(rst), CE) ) end
    end
    
    systolicModule:addFunction( S.lambda("process", pinp, out, "process_output", pipelines) ) 
    
    local resetOutput
    if f.stateful then resetOutput = inner:reset(nil,rst,CE) end
    
    local resetPipelines = {}
    table.insert( resetPipelines, SR:reset(nil,rst,CE) )
    if DARKROOM_VERBOSE then table.insert( resetPipelines, outputCount:set(S.constant(0,types.uint(16)),rst,CE) ) end
    
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), resetOutput, "reset_out", resetPipelines,rst) )
    
    if res.inputType==types.null() and nilhandshake~=true then
      systolicModule:addFunction( S.lambda("ready", pready, nil, "ready" ) )
    elseif res.outputType==types.null() and nilhandshake~=true then
      systolicModule:addFunction( S.lambda("ready", S.parameter("r",types.null()), S.constant(true,types.bool()), "ready" ) )
    else
      systolicModule:addFunction( S.lambda("ready", pready, pready, "ready" ) )
    end

    return systolicModule
  end

  return rigel.newFunction(res)
                                 end)


-- promotes FIFO systolic module to handshake type.
-- In the future, we'd like to make our type system powerful enough to be able to do this...
local function promoteFifo(systolicModule)
  
end

-- nostall: unsafe -> ready always set to true
-- W,H,T: used for debugging (calculating last cycle)
-- csimOnly: hack for large fifos - don't actually allocate hardware
modules.fifo = memoize(function( A, size, nostall, W, H, T, csimOnly, X )
  rigel.expectBasic(A)
  err( type(size)=="number", "size must be number")
  err( size >0,"size<=0")
  err(nostall==nil or type(nostall)=="boolean", "nostall should be nil or boolean")
  err(W==nil or type(W)=="number", "W should be nil or number")
  err(H==nil or type(H)=="number", "H should be nil or number")
  err(T==nil or type(T)=="number", "T should be nil or number")
  assert(csimOnly==nil or type(csimOnly)=="boolean")
  assert(X==nil)

  local res = {kind="fifo", inputType=rigel.Handshake(A), outputType=rigel.Handshake(A), registered=true, sdfInput={{1,1}}, sdfOutput={{1,1}}, stateful=true}

  if terralib~=nil then res.terraModule = MT.fifo(res,A, size, nostall, W, H, T, csimOnly) end

  local bytes = (size*A:verilogBits())/8

  res.name = sanitize("fifo_SIZE"..size.."_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_BYTES"..tostring(bytes))

  local fifo
  if csimOnly then
    res.systolicModule = fpgamodules.fifonoop(A)
    res.stateful = false
  else
    function res.makeSystolic()
      local systolicModule = Ssugar.moduleConstructor(res.name)

      local fifo = systolicModule:add( fpgamodules.fifo(A,size,DARKROOM_VERBOSE):instantiate("FIFO") )

      --------------
      -- basic -> R
      local store = systolicModule:addFunction( Ssugar.lambdaConstructor( "store", A, "store_input" ) )
      local storeCE = S.CE("store_CE")
      store:setCE(storeCE)
      store:addPipeline( fifo:pushBack( store:getInput() ) )

      local storeReady = systolicModule:addFunction( Ssugar.lambdaConstructor( "store_ready" ) )
      if nostall then
        storeReady:setOutput( S.constant(true,types.bool()), "store_ready" )
      else
        storeReady:setOutput( fifo:ready(), "store_ready" )
      end

      local storeReset = systolicModule:addFunction( Ssugar.lambdaConstructor( "store_reset" ) )
      storeReset:setCE(storeCE)
      storeReset:addPipeline(fifo:pushBackReset())

      --------------
      -- basic -> V
      local load = systolicModule:addFunction( Ssugar.lambdaConstructor( "load", types.null(), "process_input" ) )
      local loadCE = S.CE("load_CE")
      load:setCE(loadCE)
      load:setOutput( S.tuple{fifo:popFront( nil, fifo:hasData() ), fifo:hasData() }, "load_output" )
      local loadReset = systolicModule:addFunction( Ssugar.lambdaConstructor( "load_reset" ) )
      loadReset:setCE(loadCE)
      loadReset:addPipeline(fifo:popFrontReset())

      --------------
      -- debug
      if W~=nil then
        local outputCount = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap(types.uint(32),((W*H)/T)-1,1) ):CE(true):setInit(0):instantiate("outputCount") )
        load:addPipeline(outputCount:setBy(fifo:hasData()))
        loadReset:addPipeline(outputCount:set(S.constant(0,types.uint(32))))
        
        local maxSize = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.max(types.uint(16),true) ):CE(true):setInit(0):instantiate("maxSize") ) 
        local printInst = systolicModule:add( S.module.print( types.uint(16), "max size %d/"..size, nil, false):instantiate("printInst") )
        load:addPipeline(maxSize:setBy(S.cast(fifo:size(),types.uint(16))))
        local lastCycle = S.eq(outputCount:get(), S.constant(((W*H)/T)-1, types.uint(32))):disablePipelining()
        load:addPipeline(printInst:process(maxSize:get(), lastCycle))
        loadReset:addPipeline(maxSize:set(S.constant(0,types.uint(16))))
      end
      --------------
      
      systolicModule = liftDecimateSystolic(systolicModule,{"load"},{"store"})
      systolicModule = runIffReadySystolic( systolicModule,{"store"},{"load"})
      systolicModule = liftHandshakeSystolic( systolicModule,{"load","store"},{},{true,false})

      return systolicModule
    end
  end

  return rigel.newFunction(res)
                        end)

modules.lut = memoize(function( inputType, outputType, values )
  err( types.isType(inputType), "LUT: inputType must be type")
  rigel.expectBasic( inputType )
  err( types.isType(outputType), "LUT: outputType must be type")
  rigel.expectBasic( outputType )

  local inputCount = math.pow(2, inputType:verilogBits())
  err( inputCount==#values and J.keycount(values)==inputCount, "values array has insufficient entries, has "..tonumber(#values).." but should have "..tonumber(inputCount))

  for _,v in ipairs(values) do
    outputType:checkLuaValue(v)
  end
  
  local res = {kind="lut", inputType=inputType, outputType=outputType, values=values, stateful=false }
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 1
  res.name = "LUT_"..verilogSanitize(tostring(inputType)).."_"..verilogSanitize(tostring(outputType)).."_"..verilogSanitize(tostring(values))

  if terralib~=nil then res.terraModule = MT.lut(inputType, outputType, values, inputCount) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    -- bram can only read byte aligned?
    local inputBytes = math.ceil(inputType:verilogBits()/8)
    
    local lut = systolicModule:add( fpgamodules.bramSDP( true, inputCount*(outputType:verilogBits()/8), inputBytes, outputType:verilogBits()/8, values, true ):instantiate("LUT") )

    local sinp = S.parameter("process_input", res.inputType )

    local pipelines = {}

    -- needs to be driven, but set valid==false
    table.insert(pipelines, lut:writeAndReturnOriginal( S.tuple{sinp,S.constant(0,types.bits(inputBytes*8))},S.constant(false,types.bool())) )

    systolicModule:addFunction( S.lambda("process",sinp, S.cast(lut:read(sinp),outputType), "process_output", pipelines, nil, S.CE("process_CE") ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

modules.reduce = memoize(function( f, W, H )
  if rigel.isFunction(f)==false then error("Argument to reduce must be a darkroom function") end
  err(type(W)=="number", "reduce W must be number")
  err(type(H)=="number", "reduce H must be number")

  local res = {kind="reduce", fn = f, W=W, H=H}
  rigel.expectBasic(f.inputType)
  rigel.expectBasic(f.outputType)
  if f.inputType:isTuple()==false or f.inputType~=types.tuple({f.outputType,f.outputType}) then
    err("Reduction function f must be of type {A,A}->A, but is "..tostring(f.inputType).." -> "..tostring(f.outputType))
  end
  res.inputType = types.array2d( f.outputType, W, H )
  res.outputType = f.outputType
  res.stateful = f.stateful
  if f.stateful then print("WARNING: reducing with a stateful function - are you sure this is what you want to do?") end

  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = math.ceil(math.log(res.inputType:channels())/math.log(2))*f.delay
  res.name = sanitize("reduce_"..f.name.."_W"..tostring(W).."_H"..tostring(H))

  if terralib~=nil then res.terraModule = MT.reduce(res,f,W,H) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local resetPipelines = {}
    local sinp = S.parameter("process_input", res.inputType )
    local t = J.map( J.range2d(0,W-1,0,H-1), function(i) return S.index(sinp,i[1],i[2]) end )

    local i=0
    local expr = J.foldt(t, function(a,b) 
                         local I = systolicModule:add(f.systolicModule:instantiate("inner"..i))
                         i = i + 1
                         return I:process(S.tuple{a,b}) end, nil )

    systolicModule:addFunction( S.lambda( "process", sinp, expr, "process_output", nil, nil, S.CE("process_CE") ) )

    return systolicModule
  end

  return rigel.newFunction( res )
end)


modules.reduceSeq = memoize(function( f, T, X )
  err(type(T)=="number","T should be number")
  err(T<=1, "reduceSeq T>1")
  assert(X==nil)

  if f.inputType:isTuple()==false or f.inputType~=types.tuple({f.outputType,f.outputType}) then
    error("Reduction function f must be of type {A,A}->A, but is type "..tostring(f.inputType).."->"..tostring(f.outputType))
  end

  local res = {kind="reduceSeq", fn=f, T=T}
  rigel.expectBasic(f.outputType)
  res.inputType = f.outputType
  res.outputType = rigel.V(f.outputType)
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1/T}}
  res.stateful = true
  err( f.delay==0, "reduceSeq, function must be asynchronous (0 cycle delay)")
  res.delay = 0
  res.name = "ReduceSeq_"..f.name.."_T"..tostring(1/T)

  if terralib~=nil then res.terraModule = MT.reduceSeq(res,f,T) end

  function res.makeSystolic()
    local del = f.systolicModule:getDelay("process")
    err( del == 0, "ReduceSeq function must have delay==0 but instead has delay of "..del )

    local systolicModule = Ssugar.moduleConstructor(res.name)

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(16),f.outputType,f.outputType}, "ReduceSeq "..f.systolicModule.name.." phase %d input %d output %d", true):instantiate("printInst") ) end

    local sinp = S.parameter("process_input", f.outputType )
    local svalid = S.parameter("process_valid", types.bool() )

    local phase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.sumwrap(types.uint(16), (1/T)-1 ) ):CE(true):instantiate("phase") )
    
    local pipelines = {}
    table.insert(pipelines, phase:setBy( S.constant(1,types.uint(16)) ) )
    
    local out
    
    if T==1 then
      -- hack: Our reduce fn always adds two numbers. If we only have 1 number, it won't work! just return the input.
      out = sinp
    else
      local sResult = systolicModule:add( Ssugar.regByConstructor( f.outputType, f.systolicModule ):CE(true):instantiate("result") )
      table.insert( pipelines, sResult:set( sinp, S.eq(phase:get(), S.constant(0, types.uint(16) ) ):disablePipelining() ) )
      out = sResult:setBy( sinp, S.__not(S.eq(phase:get(), S.constant(0, types.uint(16) ) )):disablePipelining() )
    end
    
    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process( S.tuple{phase:get(),sinp,out} ) ) end
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ out, S.eq(phase:get(), S.constant( (1/T)-1, types.uint(16))) }, "process_output", pipelines, svalid, CE) )
    
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(16)))}, S.parameter("reset",types.bool()),CE) )
    
    return systolicModule
  end

  return rigel.newFunction( res )
    end)

-- surpresses output if we get more then _count_ inputs
modules.overflow = memoize(function( A, count )
  rigel.expectBasic(A)

  assert(count<2^32-1)

  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="overflow", A=A, inputType=A, outputType=rigel.V(A), stateful=true, count=count, sdfInput={{1,1}}, sdfOutput={{1,1}}, delay=0}
  if terralib~=nil then res.terraModule = MT.overflow(res,A,count) end
  res.name = "Overflow_"..count.."_"..verilogSanitize(tostring(A))

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local cnt = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32))):CE(true):instantiate("cnt") )

    local sinp = S.parameter("process_input", A )
    local CE = S.CE("CE")

    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ sinp, S.lt(cnt:get(), S.constant( count, types.uint(32))) }, "process_output", {cnt:setBy(S.constant(true,types.bool()))}, nil, CE ) )

    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {cnt:set(S.constant(0,types.uint(32)))}, S.parameter("reset",types.bool()), CE) )

    return systolicModule
  end

  return rigel.newFunction( res )
end)

-- provides fake output if we get less then _count_ inputs after _cyclecount_ cycles
-- if thing thing is done before tooSoonCycles, throw an assert
modules.underflow = memoize(function( A, count, cycles, upstream, tooSoonCycles )
  rigel.expectBasic(A)
  assert(type(count)=="number")
  assert(type(cycles)=="number")
  err(cycles==math.floor(cycles),"cycles must be an integer")
  assert(type(upstream)=="boolean")
  err( tooSoonCycles==nil or type(tooSoonCycles)=="number", "tooSoonCycles must be nil or number" )

  assert(count<2^32-1)
  err(cycles<2^32-1,"cycles >32 bit:"..tostring(cycles))

  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="underflow", A=A, inputType=rigel.Handshake(A), outputType=rigel.Handshake(A), stateful=true, count=count, sdfInput={{1,1}}, sdfOutput={{1,1}}, delay=0, upstream = upstream, tooSoonCycles = tooSoonCycles}

  if terralib~=nil then res.terraModule = MT.underflow(res,  A, count, cycles, upstream, tooSoonCycles ) end
  res.name = sanitize("Underflow_A"..tostring(A).."_count"..count.."_cycles"..cycles.."_toosoon"..tostring(tooSoonCycles).."_US"..tostring(upstream))

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor( res.name ):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(32),types.uint(32),types.bool()}, "outputCount %d cycleCount %d outValid"):instantiate("printInst") ) end
    
    local outputCount = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32)) ):CE(true):instantiate("outputCount"):setCoherent(false) )
    
    -- NOTE THAT WE Are counting cycles where downstream_ready == true
    local cycleCount = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32)) ):CE(true):instantiate("cycleCount"):setCoherent(false) )
    
    local rst = S.parameter("reset",types.bool())
    
    local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
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
      local asstInst = systolicModule:add( S.module.assert( "pipeline completed eariler than expected", true, false ):instantiate("asstInst") )
      local tooSoon = S.eq(cycleCount:get(),S.constant(tooSoonCycles,types.uint(32)))
      tooSoon = S.__and(tooSoon,S.ge(outputCount:get(),S.constant(count,types.uint(32))))
      table.insert( pipelines, asstInst:process(S.__not(tooSoon),S.__not(rst),CE) )
      
      -- ** throw in valids to mess up result
      -- just raising an assert doesn't work b/c verilog is dumb
      outValid = S.__or(outValid,tooSoon)
    end
    
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple{outputCount:get(),cycleCount:get(),outValid}) ) end
    
    systolicModule:addFunction( S.lambda("process", pinp, S.tuple{outData,outValid}, "process_output", pipelines) ) 
    
    local resetPipelines = {}
    table.insert( resetPipelines, outputCount:set(S.constant(0,types.uint(32)),rst,CE) )
    table.insert( resetPipelines, cycleCount:set(S.constant(0,types.uint(32)),rst,CE_cycleCount) )
    
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "reset_out", resetPipelines,rst) )
    
    local readyOut = pready
    if upstream then
      readyOut = S.__or(pready,fixupMode)
    end
    
    systolicModule:addFunction( S.lambda("ready", pready, readyOut, "ready" ) )

    return systolicModule
  end

  return rigel.newFunction( res )
    end)


-- record the # of cycles needed to complete the computation, and write it into the last axi burst
modules.cycleCounter = memoize(function( A, count )
  rigel.expectBasic(A)
  assert(type(count)=="number")

  assert(count<2^32-1)

    -- # of cycles we need to write out metadata
  local padCount = (128*8) / A:verilogBits()

  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="cycleCounter", A=A, inputType=rigel.Handshake(A), outputType=rigel.Handshake(A), stateful=true, count=count, sdfInput={{count,count+padCount}}, sdfOutput={{1,1}}, delay=0}
  res.name = sanitize("CycleCounter_A"..tostring(A).."_count"..count)

  if terralib~=nil then res.terraModule = MT.cycleCounter(res,A,count) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor( res.name ):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(32),types.uint(32),types.bool(),types.bool()}, "cycleCounter outputCount %d cycleCount %d outValid %d metadataMode %d"):instantiate("printInst") ) end
    
    local outputCount = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap(types.uint(32),count+padCount-1,1) ):CE(true):instantiate("outputCount"):setCoherent(false) )
    local cycleCount = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32),false) ):CE(false):instantiate("cycleCount"):setCoherent(false) )
    
    local rst = S.parameter("reset",types.bool())
    
    local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local pready = S.parameter("ready_downstream", types.bool())
    local pvalid = S.index(pinp,1)
    local pdata = S.index(pinp,0)
    
    local done = S.ge(outputCount:get(),S.constant(count,types.uint(32)))

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
    
    systolicModule:addFunction( S.lambda("process", pinp, S.tuple{outData,outValid}, "process_output", pipelines) ) 
    
    local resetPipelines = {}
    table.insert( resetPipelines, outputCount:set(S.constant(0,types.uint(32)),rst,CE) )
    table.insert( resetPipelines, cycleCount:set(S.constant(0,types.uint(32)),rst) )
    
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "reset_out", resetPipelines,rst) )
    
    local readyOut = S.__and(pready,S.__not(metadataMode))
    
    systolicModule:addFunction( S.lambda("ready", pready, readyOut, "ready" ) )

    return systolicModule
  end

  return rigel.newFunction( res )
    end)

-- this takes in a darkroom IR graph and normalizes the input SDF rate so that
-- it obeys our constraints: (1) neither input or output should have bandwidth (token count) > 1
-- and (2) no node should have SDF rate > 1
local function lambdaSDFNormalize( input, output )
  local sdfMaxRate = output:sdfExtremeRate(true)
  if SDFRate.fracToNumber(sdfMaxRate) < 1 then
	 print("Warning: SDF Rate < 1, inefficient hardware may be generated")
	 return input, output
  end

  if input~=nil and input.sdfRate~=nil then
    err( SDFRate.isSDFRate(input.sdfRate),"SDF input rate is not a valid SDF rate")

    for k,v in pairs(input.sdfRate) do
      err(v=="x" or v[1]/v[2]<=1, "error, lambda declared with input BW > 1")
    end
  end

  local outputBW = output:sdfTotal(output)
  local outputBW = SDFRate.sum(outputBW)

  -- we will be limited by either the output BW, or max rate. Normalize to the largest of these.
  -- we already checked that the input is <1, so that won't limit us.
  local scaleFactor

  if SDFRate.fracToNumber(sdfMaxRate) > SDFRate.fracToNumber(outputBW) then
    scaleFactor = SDFRate.fracInvert(sdfMaxRate)
  else
    scaleFactor = SDFRate.fracInvert(outputBW)
  end

  if DARKROOM_VERBOSE then print("NORMALIZE, sdfMaxRate", SDFRate.fracToNumber(sdfMaxRate),"outputBW", SDFRate.fracToNumber(outputBW), "scaleFactor", SDFRate.fracToNumber(scaleFactor)) end

  local newInput
  local newOutput = output:process(
    function(n,orig)
      if n.kind=="input" then
        err( n.id==input.id, "lambdaSDFNormalize: unexpected input node. input node is not the declared module input." )
        n.sdfRate = SDFRate.multiply(n.sdfRate,scaleFactor[1],scaleFactor[2])
        assert( SDFRate.isSDFRate(n.sdfRate))
        newInput = rigel.newIR(n)
        return newInput
      elseif n.kind=="apply" and n.sdfRateOverride~=nil then
        -- for nullary modules, we sometimes provide an explicit SDF rate, to get around the fact that we don't solve for SDF rates bidirectionally
        n.sdfRateOverride = SDFRate.multiply(n.sdfRateOverride, scaleFactor[1], scaleFactor[2] )
        return rigel.newIR(n)
      end
    end)

  return newInput, newOutput
end

-- function definition
-- output, inputs
function modules.lambda( name, input, output, instances, pipelines, generatorStr, X )
  if DARKROOM_VERBOSE then print("lambda start '"..name.."'") end

  err( X==nil, "lambda: too many arguments" )
  err( type(name) == "string", "lambda: module name must be string" )
  err( input==nil or rigel.isIR( input ), "lambda: input must be a rigel input value or nil" )
  err( input==nil or input.kind=="input", "lambda: input must be a rigel input or nil" )
  err( rigel.isIR( output ), "modules.lambda: output should be Rigel value" )
  err( instances==nil or type(instances)=="table", "lambda: instances must be nil or a table")
  if instances~=nil then J.map( instances, function(n) err( rigel.isInstance(n), "lambda: instances argument must be an array of instances" ) end ) end
  err( pipelines==nil or type(pipelines)=="table", "lambda: pipelines must be nil or a table" )
  err( generatorStr==nil or type(generatorStr)=="string","lambda: generatorStr must be nil or string")
  if pipelines~=nil then J.map( pipelines, function(n) err( rigel.isIR(n), "lambda: pipelines must be a table of rigel values") end ) end

  if rigel.SDF then input, output = lambdaSDFNormalize(input,output) end

  name = J.verilogSanitize(name)

  local res = {kind = "lambda", name=name, input = input, output = output, instances=instances, pipelines=pipelines, generator=generatorStr }

  if input==nil then
    res.inputType = types.null()
  else
    res.inputType = input.type
  end

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

  if input~=nil and rigel.isStreaming(input.type)==false then
    res.delay = output:visitEach(
      function(n, inputs)
        if n.kind=="input" or n.kind=="constant" then
          return 0
        elseif n.kind=="concat" or n.kind=="concatArray2d" then
          return math.max(unpack(inputs))
        elseif n.kind=="apply" then
          if n.fn.inputType==types.null() then return n.fn.delay
          else return inputs[1] + n.fn.delay end
        else
          print(n.kind,input.type,output.type)
          assert(false)
        end
      end)
  end

  if terralib~=nil then res.terraModule = MT.lambdaCompile(res) end

  if rigel.SDF then
    if input==nil then
      res.sdfInput = {}
    else
      assert( SDFRate.isSDFRate(input.sdfRate) )
      res.sdfInput = input.sdfRate
    end

    res.sdfOutput = output:sdfTotal(output)
    
    local isum = SDFRate.sum(res.sdfInput)
    local osum = SDFRate.sum(res.sdfOutput)
    
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
      print("INP count",#res.sdfInput,"sum",isum[1],isum[2])
      for k,v in ipairs(res.sdfInput) do
        print(res.sdfInput[k][1],res.sdfInput[k][2])
      end
      
      print("out",#res.sdfOutput,"sum",osum[1],osum[2])
      for k,v in ipairs(res.sdfOutput) do
        print(res.sdfOutput[k][1],res.sdfOutput[k][2])
      end
      err(false, "lambda '"..name.."' has strange SDF rate")
    end
  end

  local function makeSystolic( fn )
    local onlyWire = rigel.isHandshake(fn.inputType) or rigel.isHandshake(fn.outputType)
    if fn.inputType:isTuple() and rigel.isHandshake(fn.inputType.list[1]) then onlyWire = true end
    if fn.inputType:isArray() and rigel.isHandshake(fn.inputType:arrayOver()) then onlyWire = true end
    
    local module = Ssugar.moduleConstructor( fn.name ):onlyWire(onlyWire)

    local process = module:addFunction( Ssugar.lambdaConstructor( "process", rigel.lower(fn.inputType), "process_input") )
    local reset = module:addFunction( Ssugar.lambdaConstructor( "reset", types.null(), "resetNILINPUT", "reset") )

    if rigel.isStreaming(fn.inputType)==false and rigel.isStreaming(fn.outputType)==false then 
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

    err( out[1].type:constSubtypeOf(rigel.lower(res.outputType)), "Internal error, systolic type is "..tostring(out[1].type).." but should be "..tostring(rigel.lower(res.outputType)).." function "..name )

    assert(Ssugar.isFunctionConstructor(process))
    process:setOutput( out[1], "process_output" )

    -- for the non-handshake (purely systolic) modules, the ready bit doesn't flow from outputs to inputs,
    -- it flows from inputs to outputs. The reason is that upstream things can't stall downstream things anyway, so there's really no point of doing it the 'right' way.
    -- this is kind of messed up!
    if rigel.isRV( fn.inputType ) then
      assert( S.isAST(out[2]) )
      local readyfn = module:addFunction( S.lambda("ready", readyInput, out[2], "ready", {} ) )
    elseif rigel.isRV( fn.outputType ) then
      local readyfn = module:addFunction( S.lambda("ready", S.parameter("RINIL",types.null()), out[2], "ready", {} ) )
    elseif rigel.streamCount(fn.inputType)>0 then
       
      local readyinp -- = S.parameter( "ready_downstream", types.bool() )
      local readyout

      -- if we have nil->Handshake(A) types, we have to drive these ready chains somehow (and they're not connected to input)
      local readyPipelines={}

      -- remember, we're visiting the graph in reverse here.
      -- if the node takes I inputs, we return a lua array of size I
      -- for each input i in I:
      -- if that input has 1 input stream, we out[i] is a systolic bool value
      -- if that input has N input streams, we out[i] is a systolic array of bool values
      -- if that input is 0 streams, out[i] is nil

      fn.output:visitEachReverse(
        function(n, args)

          local input

          for k,i in pairs(args) do
            local parentKey = i[2]
            local value = i[1]
            local thisi = value[parentKey]

            if rigel.isHandshake(n.type) then
              assert(systolicAST.isSystolicAST(thisi))
              assert(thisi.type:isBool())
              
              if input==nil then
                input = thisi
              else
                input = S.__and(input,thisi)
              end
            elseif n:outputStreams()>1 or (n.type:isArray() and rigel.isHandshake(n.type:arrayOver())) then
              assert(systolicAST.isSystolicAST(thisi))

              if rigel.isHandshakeTmuxed(n.type) or rigel.isHandshakeArray(n.type) then
                assert(J.keycount(args)==1) -- NYI
                input = thisi
              else
                assert(thisi.type:isArray() and thisi.type:arrayOver():isBool())
                
                if input==nil then
                  input = thisi
                else
                  local r = {}
                  for i=0,n:outputStreams()-1 do
                    r[i+1] = S.__and(S.index(input,i),S.index(thisi,i))
                  end
                  input = S.cast(S.tuple(r),types.array2d(types.bool(),n:outputStreams()))
                end
              end
            else
              --err(false,"no output streams? why is this getting a ready bit? "..n.loc)
              -- this is OK - fifo:store() for example has nil output
            end
          end

          if J.keycount(args)==0 then
            -- this is the output of the pipeline
            assert(readyinp==nil)
            
            if n:outputStreams()==1 then
              readyinp = S.parameter( "ready_downstream", types.bool() )
              input = readyinp
            elseif n:outputStreams()>1 then
              readyinp = S.parameter( "ready_downstream", types.array2d(types.bool(),n:outputStreams()) )
              input = readyinp
            else
              print("Input to function had streams, but output has none? type: "..tostring(n.type))
              assert(false)
            end            
          end
          
          local res
          
          if n.kind=="input" then
            assert(readyout==nil)
            readyout = input
          elseif n.kind=="apply" then

            res = {module:lookupInstance(n.name):ready(input)}
            if n.fn.inputType==types.null() then
              table.insert(readyPipelines, res[1])
            end
            
          elseif n.kind=="applyMethod" then
            if n.fnname=="load" then
              -- "hack": systolic requires all function to be driven. We don't actually care about load fn ready bit, but drive it anyway
              local inst = module:lookupInstance(n.inst.name)
              res = {inst[n.fnname.."_ready"](inst, input)}
              table.insert(readyPipelines,res[1])

            elseif n.fnname=="store" then
              local inst = module:lookupInstance(n.inst.name)
              res = {inst[n.fnname.."_ready"](inst, input)}
            else
              assert(false)
            end
          elseif n.kind=="concat" or n.kind=="concatArray2d" then
            err( input.type:isArray() and input.type:arrayOver():isBool(), "Error, tuple should have an input type of array of N ready bits")

            -- tuple has N input streams, N output streams
                
            res = {}
            local i=0
            for i=0,n:outputStreams()-1 do
              table.insert(res, S.index(input,i) )
            end
          elseif n.kind=="statements" then
            res = {input}
            for i=2,#n.inputs do
              if n.inputs[i]:outputStreams()==1 then
                res[i] = S.constant(true,types.bool())
              elseif n.inputs[i]:outputStreams()>1 then
                local r = {}
                for ii=1,n.inputs[i]:outputStreams() do table.insert(r,S.constant(true,types.bool())) end
                res[i] = S.cast(S.concat(r), types.array2d(types.bool(),n.inputs[i]:outputStreams()) ) 
              else
                -- res[i]=nil
              end
            end

          elseif n.kind=="selectStream" then

            res = {}

            res[1] = {}
            for i=1,n.inputs[1]:outputStreams() do
              if i-1==n.i then
                res[1][i] = input
              else
                res[1][i] = S.constant(true,types.bool())
              end
            end

            res[1] = S.cast( S.tuple(res[1]),types.array2d(types.bool(),n.inputs[1]:outputStreams()) )
          else
            print(n.kind)
            assert(false)
          end

          -- now, validate that the output is what we expect
          err( #n.inputs==0 or type(res)=="table","res should be table "..n.kind.." inputs "..tostring(#n.inputs))
              
          for k,i in ipairs(n.inputs) do
            if rigel.isHandshake(i.type) then
              err(systolicAST.isSystolicAST(res[k]), "incorrect output format "..n.kind.." input "..tostring(k)..", not systolic value" )
              err(systolicAST.isSystolicAST(res[k]) and res[k].type:isBool(), "incorrect output format "..n.kind.." input "..tostring(k).." (type "..tostring(i.type)..", name "..i.name..") is "..tostring(res[k].type).." but expected bool, "..n.loc )
            elseif i:outputStreams()>1 or (i.type:isArray() and rigel.isHandshake(i.type:arrayOver())) then

              err(systolicAST.isSystolicAST(res[k]), "incorrect output format "..n.kind.." input "..tostring(k)..", not systolic value" )
              if(rigel.isHandshakeTmuxed(i.type)) then
                err( res[k].type:isBool(),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
              elseif rigel.isHandshakeArray(i.type) then
                err( res[k].type==types.uint(8),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
              else
                err(res[k].type:isArray() and res[k].type:arrayOver():isBool(),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
              end
            elseif i:outputStreams()==0 then
              err(res[k]==nil, "incorrect ready bit output format "..n.kind.." - "..n.loc)
            else
              print("NYI "..tostring(i.type))
              assert(false)
            end
          end
          -- end validate
          
          return res
        end, true)

      local readyfn = module:addFunction( S.lambda("ready", readyinp, readyout, "ready", readyPipelines ) )
    end

    return module
  end

  function res.makeSystolic()
    local systolicModule = makeSystolic(res)
    systolicModule:toVerilog()
    return systolicModule
  end

  if DARKROOM_VERBOSE then
    print("lambda done '"..name.."'")
    if terralib~=nil then print("lambda terra module size:"..terralib.sizeof(res.terraModule)) end
  end
  
  return rigel.newFunction( res )
end

-- makeTerra: a lua function that returns the terra implementation
-- makeSystolic: a lua function that returns the systolic implementation. 
--      Input argument: systolic input value. Output: systolic output value, systolic instances table
-- outputType, delay are optional, but will cause systolic to be built if they are missing!
function modules.lift( name, inputType, outputType, delay, makeSystolic, makeTerra, generatorStr, sdfOutput, X )
  err( type(name)=="string", "modules.lift: name must be string" )
  err( types.isType( inputType ), "modules.lift: inputType must be rigel type" )
  err( outputType==nil or types.isType( outputType ), "modules.lift: outputType must be rigel type" )
  err( delay==nil or type(delay)=="number",  "modules.lift: delay must be number" )
  err( sdfOutput==nil or SDFRate.isSDFRate(sdfOutput),"modules.lift: SDF output must be SDF")
  err( makeTerra==nil or type(makeTerra)=="function", "modules.lift: makeTerra argument must be lua function that returns a terra function" )
  err( type(makeSystolic)=="function", "modules.lift: makeSystolic argument must be lua function that returns a systolic value" )
  err( generatorStr==nil or type(generatorStr)=="string", "generatorStr must be nil or string")
  assert(X==nil)

  if sdfOutput==nil then sdfOutput = {{1,1}} end

  name = J.verilogSanitize(name)

  local res = { kind="lift", name=name, inputType = inputType, outputType = outputType, delay=delay, sdfInput={{1,1}}, sdfOutput=sdfOutput, stateful=false, generator=generatorStr }

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(name)

    local systolicInput = S.parameter( "inp", inputType )

    local systolicOutput, systolicInstances = makeSystolic(systolicInput)
    err( systolicAST.isSystolicAST(systolicOutput), "modules.lift: makeSystolic returned something other than a systolic value (module "..name..")" )

    if outputType~=nil then -- user may not have passed us a type, and is instead using the systolic system to calculate it
      err( systolicOutput.type:constSubtypeOf(outputType), "lifted systolic output type does not match. Is "..tostring(systolicOutput.type).." but should be "..tostring(outputType).." (module "..name..")" )
    end
    
    if systolicInstances~=nil then
      for k,v in pairs(systolicInstances) do systolicModule:add(v) end
    end

    systolicModule:addFunction( S.lambda("process", systolicInput, systolicOutput, "process_output",nil,nil,S.CE("process_CE")) )
    local nip = S.parameter("nip",types.null())

    systolicModule:complete()
    return systolicModule
  end

  local res = rigel.newFunction( res )

  if res.outputType==nil then
    err( S.isModule(res.systolicModule), "modules.lift: outputType is missing, and so is the systolic module?")
    res.outputType = res.systolicModule.functions.process.output.type
    err( types.isType(res.outputType), "modules.lift: systolic module did not return a valid type")
  end

  if res.delay==nil then
    res.delay = res.systolicModule:getDelay("process")
  end

  if terralib~=nil then 
    local terraFunction, systolicInput, systolicOutput

    if makeTerra==nil then
      systolicInput = res.systolicModule.functions.process.inputParameter
      systolicOutput = res.systolicModule.functions.process.output
    else
      terraFunction = makeTerra()
    end

    res.terraModule=MT.lift(inputType,outputType,terraFunction,systolicInput,systolicOutput) 
  end

  return res
end

modules.constSeq = memoize(function( value, A, w, h, T, X )
  err( type(value)=="table", "constSeq: value should be a lua array of values to shift through")
  err( J.keycount(value)==#value, "constSeq: value should be a lua array of values to shift through")
  err( #value==w*h, "constSeq: value array has wrong number of values")
  err( X==nil, "constSeq: too many arguments")
  err( T<=1, "constSeq: T must be <=1")
  err( type(w)=="number", "constSeq: W must be number" )
  err( type(h)=="number", "constSeq: H must be number" )
  err( types.isType(A), "constSeq: type must be type" )

  for k,v in ipairs(value) do
    err( A:checkLuaValue(v), "constSeq value array index "..tostring(k).." cannot convert to the correct systolic type" )
  end

  local res = { kind="constSeq", A = A, w=w, h=h, value=value, T=T}
  res.inputType = types.null()
  local W = w*T
  err( W == math.floor(W), "constSeq T must divide array size")
  res.outputType = types.array2d(A,W,h)
  res.stateful = false
  --if T==1 then res.stateful=false end
  res.sdfInput, res.sdfOutput = {}, {{1,1}}  -- well, technically this produces 1 output for every (nil) input
  res.name = "constSeq_"..verilogSanitize(tostring(value)).."_T"..tostring(1/T).."_w"..tostring(w).."_h"..tostring(h)
  res.delay = 0

  if terralib~=nil then res.terraModule = MT.constSeq(res, value, A, w, h, T,W ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local sconsts = J.map(J.range(1/T), function() return {} end)
    
    for C=0, (1/T)-1 do
      for y=0, h-1 do
        for x=0, W-1 do
          table.insert(sconsts[C+1], value[y*w+C*W+x+1])
        end
      end
    end

    local shiftOut, shiftPipelines = fpgamodules.addShifterSimple( systolicModule, J.map(sconsts, function(n) return S.constant(n,types.array2d(A,W,h)) end), DARKROOM_VERBOSE )
    
    if shiftOut.type:const() then
      -- this happens if we have an array of size 1, for example (becomes a passthrough). Strip the const-ness so that the module returns a consistant type with different parameters.
      shiftOut = S.cast(shiftOut, shiftOut.type:stripConst())
    end
    
    local inp = S.parameter("process_input", types.null() )

    systolicModule:addFunction( S.lambda("process", inp, shiftOut, "process_output", shiftPipelines, nil, S.CE("process_CE") ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("process_nilinp", types.null() ), nil, "process_reset", {}, S.parameter("reset", types.bool() ) ) )

    return systolicModule
  end

  return rigel.newFunction( res )
end)

modules.freadSeq = memoize(function( filename, ty )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  rigel.expectBasic(ty)
  local filenameVerilog=filename
  local res = {kind="freadSeq", filename=filename, filenameVerilog=filenameVerilog, type=ty, inputType=types.null(), outputType=ty, stateful=true, delay=0}
  res.sdfInput={{1,1}}
  res.sdfOutput={{1,1}}
  if terralib~=nil then res.terraModule = MT.freadSeq(filename,ty) end
  res.name = "freadSeq_"..verilogSanitize(filename)..verilogSanitize(tostring(ty))

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local sfile = systolicModule:add( S.module.file( filenameVerilog, ty, true ):instantiate("freadfile") )
    local inp = S.parameter("process_input", types.null() )
    local nilinp = S.parameter("process_nilinp", types.null() )
    local CE = S.CE("CE")

    systolicModule:addFunction( S.lambda("process", inp, sfile:read(), "process_output", nil, nil, CE ) )
    systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", {sfile:reset()}, S.parameter("reset", types.bool() ), CE ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

modules.fwriteSeq = memoize(function( filename, ty, filenameVerilog )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  rigel.expectBasic(ty)
  --local filenameVerilog=filename

  if filenameVerilog==nil then filenameVerilog=filename end
  
  local res = {kind="fwriteSeq", filename=filename, filenameVerilog=filenameVerilog, type=ty, inputType=ty, outputType=ty, stateful=true, delay=0, sdfInput={{1,1}}, sdfOutput={{1,1}} }
  if terralib~=nil then res.terraModule = MT.fwriteSeq(filename,ty) end
  res.name = "fwriteSeq_"..verilogSanitize(filename).."_"..verilogSanitize(tostring(ty))

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local sfile = systolicModule:add( S.module.file( filenameVerilog, ty, true ):instantiate("fwritefile") )

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( ty, "fwrite O %h", true):instantiate("printInst") ) end
    
    local inp = S.parameter("process_input", ty )
    local nilinp = S.parameter("process_nilinp", types.null() )
    local CE = S.CE("CE")
    
    local pipelines = {}
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(inp) ) end

    systolicModule:addFunction( S.lambda("process", inp, sfile:write(inp), "process_output", pipelines, nil,CE ) )

    local resetpipe={}
    table.insert(resetpipe,sfile:reset()) -- verilator: NOT SUPPORTED
    systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", resetpipe, S.parameter("reset", types.bool() ), CE ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

function modules.seqMap( f, W, H, T )
  err( darkroom.isFunction(f), "fn must be a function")
  err( type(W)=="number", "W must be a number")
  err( type(H)=="number", "H must be a number")
  err( type(T)=="number", "T must be a number")
  darkroom.expectBasic(f.inputType)
  darkroom.expectBasic(f.outputType)
  local res = {kind="seqMap", W=W,H=H,T=T,inputType=types.null(),outputType=types.null()}
  if terralib~=nil then res.terraModule = MT.seqMap(f, W, H, T) end
  res.name = "SeqMap_"..f.name.."_"..W.."_"..H

  function res.makeSystolic()
    local systolicModule = S.module.new(res.name,{},{f.systolicModule:instantiate("inst")},{verilog = [[module sim();
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

    return systolicModule
  end

  return darkroom.newFunction(res)
end

local function readAll(file)
    local f = io.open(file, "rb")
    local content = f:read("*all")
    f:close()
    return content
end

function modules.seqMapHandshake( f, inputType, tapInputType, tapValue, inputCount, outputCount, axi, readyRate, simCycles, X )
  err( darkroom.isFunction(f), "fn must be a function")
  err( types.isType(inputType), "inputType must be a type")
  err( tapInputType==nil or types.isType(tapInputType), "tapInputType must be a type")
  if tapInputType~=nil then tapInputType:checkLuaValue(tapValue) end
  err( type(inputCount)=="number", "inputCount must be a number")
  err( inputCount==math.floor(inputCount), "inputCount must be integer, but is "..tostring(inputCount) )
  err( type(outputCount)=="number", "outputCount must be a number")
  err( outputCount==math.floor(outputCount), "outputCount must be integer, but is "..tostring(outputCount) )
  err( type(axi)=="boolean", "axi should be a bool")
  err( X==nil, "seqMapHandshake: too many arguments" )

  err( f.inputType==types.null() or darkroom.isHandshake(f.inputType), "seqMapHandshake: input must be handshook or null")
  darkroom.expectHandshake(f.outputType)

  if f.inputType~=types.null() and rigel.SDF then
    local expectedOutputCount = (inputCount*f.sdfOutput[1][1]*f.sdfInput[1][2])/(f.sdfOutput[1][2]*f.sdfInput[1][1])
    err(expectedOutputCount==outputCount, "Error, seqMapHandshake, SDF output tokens ("..tostring(expectedOutputCount)..") does not match stated output tokens ("..tostring(outputCount)..")")
  end

  local res = {kind="seqMapHandshake", tapInputType=tapInputType, tapValue=tapValue, inputCount=inputCount, outputCount=outputCount, inputType=types.null(),outputType=types.null()}
  res.sdfInput = f.sdfInput
  res.sdfOutput = f.sdfOutput

  if readyRate==nil then readyRate=1 end

  res.name = "SeqMapHandshake_"..f.name.."_"..inputCount.."_"..outputCount.."_rr"..readyRate

  if terralib~=nil then res.terraModule = MT.seqMapHandshake( f, inputType, tapInputType, tapValue, inputCount, outputCount, axi, readyRate, simCycles) end

  function res.makeSystolic()
    local verilogStr

    if axi then
      local baseTypeI = inputType
      local baseTypeO = darkroom.extractData(f.outputType)
      err(baseTypeI:verilogBits()==64, "axi input must be 64 bits but is "..baseTypeI:verilogBits())
      err(baseTypeO:verilogBits()==64, "axi output must be 64 bits")

      local axiv = readAll("../platform/axi/axi.v")
      axiv = string.gsub(axiv,"___PIPELINE_MODULE_NAME",f.systolicModule.name)
      axiv = string.gsub(axiv,"___PIPELINE_INPUT_COUNT",inputCount)
      axiv = string.gsub(axiv,"___PIPELINE_OUTPUT_COUNT",outputCount)
  
      -- input/output tokens are one axi bus transaction => they are 8 bytes
      local inputBytes = J.upToNearest(128,inputCount*8)
      local outputBytes = J.upToNearest(128,outputCount*8)
      axiv = string.gsub(axiv,"___PIPELINE_INPUT_BYTES",inputBytes)
      -- extra 128 is for the extra AXI burst that contains metadata
      axiv = string.gsub(axiv,"___PIPELINE_OUTPUT_BYTES",outputBytes)

      local maxUtilization = 1

      axiv = string.gsub(axiv,"___PIPELINE_WAIT_CYCLES",math.ceil(inputCount*maxUtilization)+1024) -- just give it 1024 cycles of slack

      if tapInputType~=nil then
        local tv = J.map( J.range(tapInputType:verilogBits()),function(i) return J.sel(math.random()>0.5,"1","0") end )
        local tapreg = "reg ["..(tapInputType:verilogBits()-1)..":0] taps = "..tostring(tapInputType:verilogBits()).."'b"..table.concat(tv,"")..";\n"

        axiv = string.gsub(axiv,"___PIPELINE_TAPS", tapreg.."\nalways @(posedge FCLK0) begin if(CONFIG_READY) taps <= "..S.valueToVerilog(tapValue,tapInputType).."; end\n")
        axiv = string.gsub(axiv,"___PIPELINE_INPUT","{taps,pipelineInput}")
      else
        axiv = string.gsub(axiv,"___PIPELINE_TAPS","")
        axiv = string.gsub(axiv,"___PIPELINE_INPUT","pipelineInput")
      end

      verilogStr = readAll("../platform/axi/ict106_axilite_conv.v")..readAll("../platform/axi/conf.v")..readAll("../platform/axi/dramreader.v")..readAll("../platform/axi/dramwriter.v")..axiv
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

]]..f.systolicModule.name..[[ #(.INPUT_COUNT(]]..inputCount..[[),.OUTPUT_COUNT(]]..outputCount..[[)) inst (.CLK(CLK),.process_input(]]..J.sel(tapInputType~=nil,"{valid,taps}","valid")..[[),.reset(RST),.ready(ready),.ready_downstream(]]..readybit..[[),.process_output(process_output));
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
    ]]..J.sel(DARKROOM_VERBOSE,[[$display("------------------------------------------------- RST %d totalClocks %d validOutputs %d/]]..outputCount..[[ ready %d readyDownstream %d validInCnt %d/]]..inputCount..[[",RST,totalClocks,validCnt,ready,]]..readybit..[[,validInCnt);]],"")..[[
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

    local systolicModule = Ssugar.moduleConstructor(res.name):verilog(verilogStr)
    systolicModule:add(f.systolicModule:instantiate("inst"))

    return systolicModule
  end

  return darkroom.newFunction(res)
end

-- this is a Handshake triggered counter.
-- it accepts an input value V of type TY.
-- Then produces N tokens (from V to V+N-1)
modules.triggeredCounter = memoize(function(TY, N)
  err( types.isType(TY),"triggeredCounter: TY must be type")
  err( rigel.expectBasic(TY), "triggeredCounter: TY should be basic")
  err( TY:isNumber(), "triggeredCounter: type must be numeric rigel type, but is "..tostring(TY))
  
  err(type(N)=="number", "triggeredCounter: N must be number")

  local res = {kind="triggeredCounter"}
  res.inputType = TY
  res.outputType = rigel.RV(TY)
  res.sdfInput = {{1,N}}
  res.sdfOutput = {{1,1}}
  res.stateful=true
  res.delay=0
  res.name = "TriggeredCounter_"..verilogSanitize(tostring(TY)).."_"..tostring(N)

  if terralib~=nil then res.terraModule = MT.triggeredCounter(res,TY,N) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local sinp = S.parameter( "inp", TY )
    
    local sPhase = systolicModule:add( Ssugar.regByConstructor( TY, fpgamodules.sumwrap(TY,N-1) ):CE(true):instantiate("phase") )
    local reg = systolicModule:add( S.module.reg( TY,true ):instantiate("buffer") )
    
    local reading = S.eq(sPhase:get(),S.constant(0,TY)):disablePipelining()
    local out = S.select( reading, sinp, reg:get()+sPhase:get() ) 
    
    local pipelines = {}
    table.insert(pipelines, reg:set( sinp, reading ) )
    table.insert( pipelines, sPhase:setBy( S.constant(1,TY) ) )
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines, nil, CE) )
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:set(S.constant(0,TY))},S.parameter("reset",types.bool()),CE) )

    return systolicModule
  end

  return modules.liftHandshake(modules.waitOnInput( rigel.newFunction(res) ))
  
end)

return modules
