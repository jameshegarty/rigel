local simmodules = require("simmodules")
local rigel = require "rigel"
local types = require "types"
local S = require "systolic"
local systolic = S
local Ssugar = require "systolicsugar"
local cstring = terralib.includec("string.h")
local cmath = terralib.includec("math.h")
local cstdlib = terralib.includec("stdlib.h")
local fpgamodules = require("fpgamodules")
local SDFRate = require "sdfrate"

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


-- *this should really be in examplescommon.t
-- f(g())
function modules.compose(name,f,g)
  err(type(name)=="string", "first argument to compose must be name of function")
  assert(darkroom.isFunction(f))
  assert(darkroom.isFunction(g))
  local inp = rigel.input( g.inputType, g.sdfInput )
  local gvalue = rigel.apply(name.."_g",g,inp)
  return modules.lambda(name,inp,rigel.apply(name.."_f",f,gvalue))
end


-- *this should really be in examplescommon.t
-- This converts SoA to AoS
-- ie {Arr2d(a,W,H),Arr2d(b,W,H),...} to Arr2d({a,b,c},W,H)
-- if asArray==true then converts {Arr2d(a,W,H),Arr2d(b,W,H),...} to Arr2d(a[N],W,H). This requires a,b,c be the same...
function modules.SoAtoAoS( W, H, typelist, asArray )
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

  if terralib~=nil then res.terraModule = MT.SoAtoAoS(res,W,H,typelist,asArray) end

  res.systolicModule = Ssugar.moduleConstructor("packTupleArrays_"..(tostring(typelist):gsub('%W','_')))
  local sinp = S.parameter("process_input", res.inputType )
  local arrList = {}
  for y=0,H-1 do
    for x=0,W-1 do
      table.insert( arrList, S.tuple(map(range(0,#typelist-1), function(i) return S.index(S.index(sinp,i),x,y) end)) )
    end
  end
  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast(S.tuple(arrList),rigel.lower(res.outputType)), "process_output",nil,nil,S.CE("process_CE")) )
  --res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro") )

  return rigel.newFunction(res)
end

-- Converst {Handshake(a), Handshake(b)...} to Handshake{a,b}
-- typelist should be a table of pure types
-- WARNING: ready depends on ValidIn
function modules.packTuple( typelist, X )
  assert(type(typelist)=="table")
  assert(X==nil)
  
  local res = {kind="packTuple"}
  
  map(typelist, function(t) rigel.expectBasic(t) end )
  res.inputType = types.tuple( map(typelist, function(t) return rigel.Handshake(t) end) )
  res.outputType = rigel.Handshake( types.tuple(typelist) )
  res.stateful = false
  res.sdfOutput = {{1,1}}
  res.sdfInput = map(typelist, function(n) if n:const() then return "x" else return {1,1} end end)
    
  res.delay = 0

  if terralib~=nil then res.terraModule = MT.packTuple(res,typelist) end

  res.systolicModule = Ssugar.moduleConstructor("packTuple_"..tostring(typelist))
  local CE
  local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
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
  
  return rigel.newFunction(res)
end


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
  if terralib~=nil then res.terraModule = MT.liftBasic(res,f) end
  res.systolicModule = Ssugar.moduleConstructor("LiftBasic_"..f.systolicModule.name)
  local inner = res.systolicModule:add( f.systolicModule:instantiate("LiftBasic_inner") )
  local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ inner:process(sinp), S.constant(true, types.bool())}, "process_output", nil, nil, CE ) )
  if f.stateful then res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {},S.parameter("reset",types.bool()),CE) ) end
  res.systolicModule:complete()
  return rigel.newFunction(res)
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
function modules.reduceThroughput(A,factor)
  assert(type(factor)=="number")
  assert(factor>1)
  assert(math.floor(factor)==factor)
  local res = {kind="reduceThroughput",factor=factor}
  res.inputType = A
  res.outputType = rigel.RV(A)
  res.sdfInput = {{1,factor}}
  res.sdfOutput = {{1,factor}}
  res.stateful = true
  res.delay = 0
  if terralib~=nil then res.terraModule = MT.reduceThroughput(res,A,factor) end
  res.systolicModule = Ssugar.moduleConstructor("ReduceThroughput_"..factor)

  local phase = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), factor-1, 1 ) ):CE(true):setInit(0):instantiate("phase") ) 

  local reading = S.eq( phase:get(), S.constant(0,types.uint(16)) ):disablePipelining()

  local sinp = S.parameter( "inp", A )

  local pipelines = {}
  table.insert(pipelines, phase:setBy(S.constant(true,types.bool())))

  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{sinp,reading}, "process_output", pipelines, nil, CE) )
  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()),CE) )

  return modules.waitOnInput( rigel.newFunction(res) )
end

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
  if terralib~=nil then res.terraModule = MT.waitOnInput(res,f) end
  res.systolicModule = waitOnInputSystolic( f.systolicModule, {"process"},{})

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
  assert(rigel.isFunction(f))
  local res = {kind="liftDecimate", fn = f}
  rigel.expectBasic(f.inputType)
  res.inputType = rigel.V(f.inputType)

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

  err( SDFRate.isSDFRate(f.sdfInput), "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput

  res.delay = f.delay

  if terralib~=nil then res.terraModule = MT.liftDecimate(res,f) end

  err( f.systolicModule~=nil, "Missing systolic for "..f.kind )
  res.systolicModule = liftDecimateSystolic( f.systolicModule, {"process"},{})

  return rigel.newFunction(res)
                                end)

-- converts V->RV to RV->RV
modules.RPassthrough = memoize(function(f)
  local res = {kind="RPassthrough", fn = f}
  rigel.expectV(f.inputType)
  rigel.expectRV(f.outputType)
  res.inputType = rigel.RV(rigel.extractData(f.inputType))
  res.outputType = rigel.RV(rigel.extractData(f.outputType))
  err( type(f.sdfInput)=="table", "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  err( type(f.stateful)=="boolean", "Missing stateful annotation for "..f.kind)
  res.stateful = f.stateful
  res.delay = f.delay
  if terralib~=nil then res.terraModule = MT.RPassthrough(res,f) end

  err( f.systolicModule~=nil, "RPassthrough null module "..f.kind)
  res.systolicModule = Ssugar.moduleConstructor("RPassthrough_"..f.systolicModule.name)
  local inner = res.systolicModule:add( f.systolicModule:instantiate("RPassthrough_inner") )
  local sinp = S.parameter("process_input", rigel.lower(res.inputType) )

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

  return rigel.newFunction(res)
                                end)

local function liftHandshakeSystolic( systolicModule, liftFns, passthroughFns )
  local res = Ssugar.moduleConstructor( "LiftHandshake_"..systolicModule.name ):onlyWire(true):parameters({INPUT_COUNT=0, OUTPUT_COUNT=0})
  local inner = res:add(systolicModule:instantiate("inner_"..systolicModule.name))

  systolicModule:complete()

  for _,fnname in pairs(liftFns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    local printInst 
    if DARKROOM_VERBOSE then printInst = res:add( S.module.print( types.tuple{types.bool(), srcFn:getInput().type.list[1],types.bool(),srcFn:getOutput().type.list[1],types.bool(),types.bool(),types.bool(),types.uint(16), types.uint(16)}, fnname.." RST %d I %h IV %d O %h OV %d readyDownstream %d ready %d outputCount %d expectedOutputCount %d"):instantiate(prefix.."printInst") ) end

    local outputCount
    if STREAMING==false and DARKROOM_VERBOSE then outputCount = res:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIf() ):CE(true):instantiate(prefix.."outputCount"):setCoherent(false) ) end


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
modules.liftHandshake = memoize(function(f)
  local res = {kind="liftHandshake", fn=f}
  rigel.expectV(f.inputType)
  rigel.expectRV(f.outputType)
  res.inputType = rigel.Handshake(rigel.extractData(f.inputType))
  res.outputType = rigel.Handshake(rigel.extractData(f.outputType))

  err( SDFRate.isSDFRate(f.sdfInput), "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  err(type(f.stateful)=="boolean", "Missing stateful annotation, "..f.kind)
  res.stateful = f.stateful

  local delay = math.max(1, f.delay)
  err(f.delay==math.floor(f.delay),"delay is fractional ?!, "..f.kind)

  if terralib~=nil then res.terraModule = MT.liftHandshake(res,f,delay) end
  res.systolicModule = liftHandshakeSystolic( f.systolicModule, {"process"},{} )

  return rigel.newFunction(res)
                                 end)

-- f : ( A, B, ...) -> C (darkroom function)
-- map : ( f, A[n], B[n], ...) -> C[n]
modules.map = memoize(function( f, W, H )
  assert( rigel.isFunction(f) )
  err(type(W)=="number", "width must be number")
  assert(type(H)=="number" or H==nil)
  if H==nil then H=1 end

  local res = { kind="map", fn = f, W=W, H=H }

  res.inputType = types.array2d( f.inputType, W, H )
  res.outputType = types.array2d( f.outputType, W, H )
  err(type(f.stateful)=="boolean", "Missing stateful annotation "..f.kind)
  res.stateful = f.stateful
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = f.delay
  if terralib~=nil then res.terraModule = MT.map(res,f,W,H) end
  res.systolicModule = Ssugar.moduleConstructor("map_"..f.systolicModule.name.."_W"..tostring(W).."_H"..tostring(H))
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

  return rigel.newFunction(res)
end)

-- type {A,bool}->A
-- rate: this will have a valid output every 1/rate cycles
function modules.filterSeq( A, W,H, rate, fifoSize )
  assert(types.isType(A))
  err(type(W)=="number", "W must be number")
  err(type(H)=="number", "H must be number")
  err(type(rate)=="number", "rate must be number")
  err(rate>1, "rate must be >1")
  err(type(fifoSize)=="number", "fifoSize must be number")
  err(isPowerOf2(rate), "rate should be power of 2")

  local logRate = math.log(rate)/math.log(2)

  local res = { kind="filterSeq", A=A }
  -- this has type basic->V (decimate)
  res.inputType = types.tuple{A,types.bool()}
  res.outputType = rigel.V(A)
  res.delay = 0
  res.stateful = true
  res.sdfInput = {{1,1}}
  res.sdfOutput = {{1,rate}}

  if terralib~=nil then res.terraModule = MT.filterSeq( res, A, W,H, rate, fifoSize ) end

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
  assign underflow = (currentFifoSize==0 && cyclesSinceOutput==]]..tostring(rate)..[[);

  wire fifoHasSpace;
  assign fifoHasSpace = currentFifoSize<]]..tostring(fifoSize)..[[;

  wire outaTime;
  assign outaTime = remainingInputs < (remainingOutputs*]]..tostring(rate)..[[);

  wire validOut;
  assign validOut = (((filterCond || underflow) && fifoHasSpace) || outaTime);

  assign out = {validOut,inpData};

  always @ (posedge CLK) begin
    if (reset) begin
      phase <= 0;
      cyclesSinceOutput <= 0;
      currentFifoSize <= 0;
      remainingInputs <= ]]..tostring(W*H)..[[;
      remainingOutputs <= ]]..tostring(W*H/rate)..[[;
    end else if (ce && process_valid) begin
      currentFifoSize <= (validOut && (phase<]]..tostring(rate-1)..[[))?(currentFifoSize+1):(   (validOut==1'b0 && phase==]]..tostring(rate-1)..[[ && currentFifoSize>0)? (currentFifoSize-1) : (currentFifoSize) );
      cyclesSinceOutput <= (validOut)?0:cyclesSinceOutput+1;
      remainingOutputs <= validOut?( (remainingOutputs==0)?]]..tostring(W*H/rate)..[[:(remainingOutputs-1) ):remainingOutputs;
      remainingInputs <= (remainingInputs==0)?]]..tostring(W*H)..[[:(remainingInputs-1);
      phase <= (phase==]]..tostring(rate)..[[)?0:(phase+1);
    end
  end

  always @(posedge CLK) begin
    $display("FILTER reset:%d process_valid:%d filterCond:%d validOut:%d phase:%d cyclesSinceOutput:%d currentFifoSize:%d remainingInputs:%d remainingOutputs:%d underflow:%d fifoHasSpace:%d outaTime:%d", reset, process_valid, filterCond, validOut, phase, cyclesSinceOutput, currentFifoSize, remainingInputs, remainingOutputs, underflow, fifoHasSpace, outaTime);
  end
endmodule
]]

  local fns = {}
  local inp = S.parameter("inp",res.inputType)

  local datat = rigel.extractData(res.outputType)
  local datav = datat:fakeValue()

  fns.process = S.lambda("process",inp,S.cast(S.tuple{S.constant(datav,datat),S.constant(true,types.bool())}, rigel.lower(res.outputType)), "out",nil,S.parameter("process_valid",types.bool()),S.CE("ce"))
  fns.reset = S.lambda( "reset", S.parameter("resetinp",types.null()), S.null(), "resetout",nil,S.parameter("reset",types.bool()),S.CE("ce"))

  local FilterSeqImpl = systolic.module.new("FilterSeqImpl", fns, {}, true,nil,nil, vstring,{process=0,reset=0})


  res.systolicModule = Ssugar.moduleConstructor("FilterSeqImplWrap")

  -- hack: get broken systolic library to actually wire valid
  local phase = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), 42, 1 ) ):CE(true):setInit(0):instantiate("phase") ) 

  local inner = res.systolicModule:add(FilterSeqImpl:instantiate("filterSeqImplInner"))

  local sinp = S.parameter("process_input", res.inputType )
  local CE = S.CE("CE")
  local v = S.parameter("process_valid",types.bool())
  res.systolicModule:addFunction( S.lambda("process", sinp, inner:process(sinp,v), "process_output", {phase:setBy(S.constant(true,types.bool()))}, v, CE ) )
  local resetValid = S.parameter("reset",types.bool())
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(16))),inner:reset(nil,resetValid)},resetValid,CE) )
  
  return rigel.newFunction(res)
end

-- takes A[W,H] to A[W,H/scale]
-- lines where ycoord%scale==0 are kept
-- basic -> V
modules.downsampleYSeq = memoize(function( A, W, H, T, scale )
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

  local tfn
  if terralib~=nil then tfn=MT.downsampleYSeqFn(innerInputType,outputType,scale) end

  local f = modules.lift( "DownsampleYSeq_W"..tostring(W).."_H"..tostring(H).."_scale"..tostring(scale), innerInputType, outputType, 0, 
                           tfn, sinp, S.tuple{sdata,svalid}, nil, {{1,scale}})

  return modules.liftXYSeq( f, W, H, T )
                                  end)

-- takes A[W,H] to A[W/scale,H]
-- lines where xcoord%scale==0 are kept
-- basic -> V
-- 
-- This takes A[T] to A[T/scale], except in the case where scale>T. Then it goes from A[T] to A[1]. If you want to go from A[T] to A[T], use changeRate.
modules.downsampleXSeq = memoize(function( A, W, H, T, scale )
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
    if terralib~=nil then tfn = MT.downsampleXSeqFn(innerInputType,outputType,scale) end
  else
    sdfOverride = {{1,1}}
    svalid = S.constant(true,types.bool())
    local datavar = S.index(sinp,1)
    sdata = map(range(0,outputT-1), function(i) return S.index(datavar, i*scale) end)
    sdata = S.cast(S.tuple(sdata), types.array2d(A,outputT))

    if terralib~=nil then tfn = MT.downsampleXSeqFnShort(innerInputType,outputType,scale,outputT) end
  end

  local f = modules.lift( "DownsampleXSeq_W"..tostring(W).."_H"..tostring(H), innerInputType, outputType, 0, tfn, sinp, S.tuple{sdata,svalid},nil,sdfOverride)

  return modules.liftXYSeq( f, W, H, T )

                                  end)

-- This is actually a pure function
-- takes A[T] to A[T*scale]
-- like this: [A[0],A[0],A[1],A[1],A[2],A[2],...]
local function broadcastWide( A, T, scale )
  local ITYPE, OTYPE = types.array2d(A,T), types.array2d(A,T*scale)
  local sinp = S.parameter("inp",types.array2d(A,T))
  local out = {}
  for t=0,T-1 do
    for s=0,scale-1 do
      table.insert(out, S.index(sinp,t) )
    end
  end
  out = S.cast(S.tuple(out), OTYPE)

  local tfn
  if terralib~=nil then tfn=MT.broadcastWide(ITYPE,OTYPE,T,scale) end
  return modules.lift("broadcastWide", ITYPE, OTYPE, 0,
                       tfn, sinp, out)
end

-- this has type V->RV
function modules.upsampleXSeq( A, T, scale, X )
  assert(X==nil)

  if T==1 then
    -- special case the EZ case of taking one value and writing it out N times
    local res = {kind="upsampleXSeq",sdfInput={{1,scale}}, sdfOutput={{1,1}}, stateful=true, A=A, T=T, scale=scale}

    local ITYPE = types.array2d(A,T)
    res.inputType = ITYPE
    res.outputType = rigel.RV(types.array2d(A,T))
    res.delay=0


    if terralib~=nil then res.terraModule = MT.upsampleXSeq(res,A, T, scale, ITYPE ) end

    -----------------
    res.systolicModule = Ssugar.moduleConstructor("UpsampleXSeq")
    local sinp = S.parameter( "inp", ITYPE )

    local sPhase = res.systolicModule:add( Ssugar.regByConstructor( types.uint(8), fpgamodules.sumwrap(types.uint(8),scale-1) ):CE(true):instantiate("phase") )
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

    return modules.liftHandshake(modules.waitOnInput( rigel.newFunction(res) ))
  else
    return modules.compose("upsampleXSeq_"..T, modules.liftHandshake(modules.changeRate(A,1,T*scale,T)), modules.makeHandshake(broadcastWide(A,T,scale)))
  end
end

-- V -> RV
function modules.upsampleYSeq( A, W, H, T, scale )
  err( W%T==0,"W%T~=0")
  err( isPowerOf2(scale), "scale must be power of 2")
  err( isPowerOf2(W), "W must be power of 2")

  local res = {kind="upsampleYSeq", sdfInput={{1,scale}}, sdfOutput={{1,1}}, A=A, T=T, width=W, height=H, scale=scale}
  local ITYPE = types.array2d(A,T)
  res.inputType = ITYPE
  res.outputType = rigel.RV(types.array2d(A,T))
  res.delay=0
  res.stateful = true

  if terralib~=nil then res.terraModule = MT.upsampleYSeq( res,A, W, H, T, scale, ITYPE ) end

  -----------------
  res.systolicModule = Ssugar.moduleConstructor("UpsampleYSeq")
  local sinp = S.parameter( "inp", ITYPE )

  -- we currently don't have a way to make a posx counter and phase counter coherent relative to each other. So just use 1 counter for both. This restricts us to only do power of two however!
  local sPhase = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.sumwrap(types.uint(16),(W/T)*scale-1) ):CE(true):instantiate("xpos") )

  local addrbits = math.log(W/T)/math.log(2)
  assert(addrbits==math.floor(addrbits))
  
  local xpos = S.cast(S.bitSlice( sPhase:get(), 0, addrbits-1), types.uint(addrbits))

  local phasebits = (math.log(scale)/math.log(2))
  local phase = S.cast(S.bitSlice( sPhase:get(), addrbits, addrbits+phasebits-1 ), types.uint(phasebits))

  local sBuffer = res.systolicModule:add( fpgamodules.bramSDP( true, (A:verilogBits()*W)/8, ITYPE:verilogBits()/8, ITYPE:verilogBits()/8,nil,true ):instantiate("buffer"):setCoherent(true) )
  local reading = S.eq( phase, S.constant(0,types.uint(phasebits)) ):disablePipelining()

  local pipelines = {sBuffer:writeAndReturnOriginal(S.tuple{xpos,S.cast(sinp,types.bits(ITYPE:verilogBits()))}, reading), sPhase:setBy( S.constant(1, types.uint(16)) )}
  local out = S.select( reading, sinp, S.cast(sBuffer:read(xpos),ITYPE) ) 
  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines, nil, CE) )
  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()),CE) )

  return modules.waitOnInput( rigel.newFunction(res) )
end

-- Stateful{uint8,uint8,uint8...} -> Stateful(uint8)
-- Ignores the counts. Just interleaves between streams.
-- N: number of streams.
-- period==0: ABABABAB, period==1: AABBAABBAABB, period==2: AAAABBBB
function modules.interleveSchedule( N, period )
  err(type(N)=="number", "N must be number")
  err( isPowerOf2(N), "N must be power of 2")
  err(type(period)=="number", "period must be number")
  local res = {kind="interleveSchedule", N=N, period=period, delay=0, inputType=types.null(), outputType=types.uint(8), sdfInput={{1,1}}, sdfOutput={{1,1}}, stateful=true }

  if terralib~=nil then res.terraModule = MT.interleveSchedule( N, period ) end

  res.systolicModule = Ssugar.moduleConstructor("InterleveSchedule_"..N.."_"..period)
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.uint(8), "interleve schedule phase %d", true):instantiate("printInst") ) end

  local inp = S.parameter("process_input", rigel.lower(res.inputType) )
  local phase = res.systolicModule:add( Ssugar.regByConstructor( types.uint(8), fpgamodules.incIfWrap( types.uint(8), 255, 1 ) ):setInit(0):CE(true):instantiate("interlevePhase") )
  local log2N = math.log(N)/math.log(2)

  local CE = S.CE("CE")
  local pipelines = {phase:setBy( S.constant(true,types.bool()))}
  if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(phase:get())) end

  res.systolicModule:addFunction( S.lambda("process", inp, S.cast(S.cast(S.bitSlice(phase:get(),period,period+log2N-1),types.uint(log2N)), types.uint(8)), "process_output", pipelines, nil, CE ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(8)))}, S.parameter("reset",types.bool()),CE) )

  return rigel.newFunction(res)
end

-- wtop is the width of the largest (top) pyramid level
function modules.pyramidSchedule( depth, wtop, T )
  err(type(depth)=="number", "depth must be number")
  err(type(wtop)=="number", "wtop must be number")
  err(type(T)=="number", "T must be number")
  local res = {kind="pyramidSchedule", wtop=wtop, depth=depth, T=T, delay=0, inputType=types.null(), outputType=types.uint(8), sdfInput={{1,1}}, sdfOutput={{1,1}}, stateful=true }
  
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

  res.systolicModule = Ssugar.moduleConstructor("PyramidSchedule_"..depth.."_"..wtop)
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(8), types.uint(16),types.uint(log2N)}, "pyramid schedule addr %d wcnt %d out %d", true):instantiate("printInst") ) end

  local tokensPerAddr = (wtop*minTargetW)/T

  local inp = S.parameter("process_input", rigel.lower(res.inputType) )
  local addr = res.systolicModule:add( Ssugar.regByConstructor( types.uint(8), fpgamodules.incIfWrap( types.uint(8), patternTotal-1, 1 ) ):setInit(0):CE(true):instantiate("patternAddr") )
  local wcnt = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), tokensPerAddr-1, 1 ) ):setInit(0):CE(true):instantiate("wcnt") )
  local patternRam = res.systolicModule:add(fpgamodules.ram128(types.uint(log2N), pattern):instantiate("patternRam"))


  local CE = S.CE("CE")
  local pipelines = {addr:setBy( S.eq(wcnt:get(),S.constant(tokensPerAddr-1,types.uint(16))):disablePipelining() )}
  table.insert(pipelines, wcnt:setBy( S.constant(true,types.bool()) ) )

  local out = patternRam:read(addr:get())

  if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(S.tuple{addr:get(),wcnt:get(),out})) end

  res.systolicModule:addFunction( S.lambda("process", inp, out, "process_output", pipelines, nil, CE ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {addr:set(S.constant(0,types.uint(8))), wcnt:set(S.constant(0,types.uint(16)))}, S.parameter("reset",types.bool()),CE) )

  return rigel.newFunction(res)
end

-- WARNING: validOut depends on readyDownstream
function modules.toHandshakeArray( A, inputRates )
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
  function res:sdfTransfer( I, loc ) 
    err(#I[1]==#inputRates, "toHandshakeArray: incorrect number of input streams. Is "..(#I[1]).." but expected "..(#inputRates) )
    return I 
  end
  
  if terralib~=nil then res.terraModule = MT.toHandshakeArray( res,A, inputRates ) end

  res.systolicModule = Ssugar.moduleConstructor("ToHandshakeArray_"..#inputRates):onlyWire(true)
  local printStr = "IV ["..table.concat(broadcast("%d",#inputRates),",").."] OV %d readyDownstream %d/"..(#inputRates-1)
  local printInst
    if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple(concat(broadcast(types.bool(),#inputRates+1),{types.uint(8)})), printStr):instantiate("printInst") ) end

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

  local validOut = foldt( validList, function(a,b) return S.__or(a,b) end, "X" )

  local pipelines = {}
  local tab = concat(concat(inpValid,{validOut}), {readyDownstream})
  assert(#tab==(#inputRates+2))
  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple(tab) ) ) end

  local dataOut = fpgamodules.wideMux( inpData, readyDownstream )
  res.systolicModule:addFunction( S.lambda("process", inp, S.tuple{dataOut,validOut} , "process_output", pipelines) )

  local readyOut = map(range(#inputRates), function(i) return S.eq(S.constant(i-1,types.uint(8)), readyDownstream) end )
  res.systolicModule:addFunction( S.lambda("ready", readyDownstream, S.cast(S.tuple(readyOut),types.array2d(types.bool(),#inputRates)), "ready" ) )

  return rigel.newFunction( res )
end

-- inputRates is a list of SDF rates
-- {StatefulHandshakRegistered(A),StatefulHandshakRegistered(A),...} -> StatefulHandshakRegistered({A,stream:uint8}),
-- where stream is the ID of the input that corresponds to the output
function modules.serialize( A, inputRates, Schedule, X )
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

  res.systolicModule = Ssugar.moduleConstructor("Serialize_"..#inputRates):onlyWire(true)
  local scheduler = res.systolicModule:add( Schedule.systolicModule:instantiate("Scheduler") )
  local printInst
  if DARKROOM_VERBOSE then printInst= res.systolicModule:add( S.module.print( types.tuple{types.uint(8),types.bool(),types.uint(8),types.bool()}, "Serialize OV %d/"..(#inputRates-1).." readyDownstream %d ready %d/"..(#inputRates-1).." stepSchedule %d"):instantiate("printInst") ) end
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

  res.systolicModule:addFunction( S.lambda("process", inp, S.tuple{ inpData, validOut } , "process_output", pipelines ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, resetValid ) )

  res.systolicModule:addFunction( S.lambda("ready", readyDownstream, readyOut, "ready" ) )

  return rigel.newFunction(res)
end

-- WARNING: ready depends on ValidIn
function modules.demux( A, rates, X )
  err( types.isType(A), "A must be type" )
  err( type(rates)=="table", "rates must be table")
  assert( SDFRate.isSDFRate(rates) )
  rigel.expectBasic(A)
  assert(X==nil)

  local res = {kind="demux", A=A, rates=rates}

  res.inputType = rigel.HandshakeTmuxed( A, #rates )
  res.outputType = types.array2d(rigel.Handshake(A), #rates)
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

  if terralib~=nil then res.terraModule = MT.demux(res,A,rates) end

  res.systolicModule = Ssugar.moduleConstructor("Demux_"..#rates):onlyWire(true)

  local printInst
  if DARKROOM_VERBOSE then printInst= res.systolicModule:add( S.module.print( types.tuple(concat({types.uint(8)},broadcast(types.bool(),#rates+1))), "Demux IV %d readyDownstream ["..table.concat(broadcast("%d",#rates),",").."] ready %d"):instantiate("printInst") ) end
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

  local readyOut = foldt( readyOut, function(a,b) return S.__or(a,b) end, "X" )
  readyOut = S.__or(readyOut, S.eq(inpValid, S.constant(#rates, types.uint(8)) ) )

  local printList = {}
  table.insert(printList,inpValid)
  for i=1,#rates do table.insert( printList, S.index(readyDownstream,i-1) ) end
  table.insert(printList,readyOut)
  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple(printList) ) ) end

  res.systolicModule:addFunction( S.lambda("process", inp, S.cast(S.tuple(out),rigel.lower(res.outputType)) , "process_output", pipelines ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, resetValid ) )

  res.systolicModule:addFunction( S.lambda("ready", readyDownstream, readyOut, "ready" ) )

  return rigel.newFunction(res)
end

function modules.flattenStreams( A, rates, X )
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

  for i=1,#rates do
    print("flattenStreams",i,rates[i][1],rates[i][2])
  end

  res.sdfInput = rates
  res.sdfOutput = {{1,1}}

  if terralib~=nil then res.terraModule = MT.flattenStreams(res,A,rates) end

  res.systolicModule = Ssugar.moduleConstructor("FlattenStreams_"..#rates):onlyWire(true)

  local resetValid = S.parameter("reset_valid", types.bool() )

  local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
  local inpData = S.index(inp,0)
  local inpValid = S.index(inp,1)
  local readyDownstream = S.parameter( "ready_downstream", types.bool() )

  local pipelines = {}
  local resetPipelines = {}

  res.systolicModule:addFunction( S.lambda("process", inp, S.tuple{inpData,S.__not(S.eq(inpValid,S.constant(#rates,types.uint(8))))} , "process_output", pipelines ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, resetValid ) )

  res.systolicModule:addFunction( S.lambda("ready", readyDownstream, readyDownstream, "ready" ) )

  return rigel.newFunction(res)
end

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
  res.sdfOutput = broadcast({1,1},N)

  if terralib~=nil then res.terraModule = MT.broadcastStream(res,A,N) end

  res.systolicModule = Ssugar.moduleConstructor("BroadcastStream_"..tostring(A):gsub('%W','_').."_"..N):onlyWire(true)

  local printStr = "IV %d readyDownstream ["..table.concat(broadcast("%d",N),",").."] ready %d"
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple(broadcast(types.bool(),N+2)), printStr):instantiate("printInst") ) end

  local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
  local inpData = S.index(inp,0)
  local inpValid = S.index(inp,1)
  local readyDownstream = S.parameter( "ready_downstream", types.array2d(types.bool(),N) )
  local readyDownstreamList = map(range(N), function(i) return S.index(readyDownstream,i-1) end )

  local allReady = foldt( readyDownstreamList, function(a,b) return S.__and(a,b) end, "X" )
  local validOut = S.__and(inpValid,allReady)
  local out = S.tuple(broadcast(S.tuple{inpData, validOut}, N))
  out = S.cast(out, rigel.lower(res.outputType) )

  local pipelines = {}

  if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple( concat(concat({inpValid}, readyDownstreamList),{allReady}) ) ) ) end

  res.systolicModule:addFunction( S.lambda("process", inp, out, "process_output", pipelines ) )

  local resetValid = S.parameter("reset_valid", types.bool() )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", nil, resetValid ) )

  res.systolicModule:addFunction( S.lambda("ready", readyDownstream, allReady, "ready" ) )

  return rigel.newFunction(res)
                                   end)

-- output type: {uint16,uint16}[T]
modules.posSeq = memoize(function( W, H, T )
  assert(W>0); assert(H>0); assert(T>=1);
  local res = {kind="posSeq", T=T, W=W, H=H }
  res.inputType = types.null()
  res.outputType = types.array2d(types.tuple({types.uint(16),types.uint(16)}),T)
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 0

  if terralib~=nil then res.terraModule = MT.posSeq(res,W,H,T) end

  res.systolicModule = Ssugar.moduleConstructor("PosSeq_W"..W.."_H"..H.."_T"..T)
  local posX = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), W-T, T ) ):setInit(0):CE(true):instantiate("posX_posSeq") )
  local posY = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), H-1 ) ):setInit(0):CE(true):instantiate("posY_posSeq") )
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

  return rigel.newFunction(res)
                          end)

-- this takes a pure function f : {{int32,int32}[T],inputType} -> outputType
-- and drives the first tuple with (x,y) coord
-- returns a function with type Stateful(inputType)->Stateful(outputType)
-- sdfOverride: we can use this to define stateful->StatefulV interfaces etc, so we may want to override the default SDF rate
modules.liftXYSeq = memoize(function( f, W, H, T, X )
  assert(rigel.isFunction(f))
  map({W,H,T},function(n) assert(type(n)=="number") end)
  assert(X==nil)

  local inputType = f.inputType.list[2]

  local inp = rigel.input( inputType )

  local p = rigel.apply("p", modules.posSeq(W,H,T) )
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)

  local out = rigel.apply("m", f, rigel.tuple("ptup", {p,inp}) )
  return modules.lambda( "liftXYSeq_"..f.kind, inp, out )
end)

-- this takes a function f : {{uint16,uint16},inputType} -> outputType
-- and returns a function of type inputType[T]->outputType[T]
function modules.liftXYSeqPointwise( f, W, H, T )
  assert(f.inputType:isTuple())
  local fInputType = f.inputType.list[2]
  local inputType = types.array2d(fInputType,T)
  local xyinner = types.tuple{types.uint(16),types.uint(16)}
  local xyType = types.array2d(xyinner,T)
  local innerInputType = types.tuple{xyType, inputType}

  local inp = rigel.input( innerInputType )
  local unpacked = rigel.apply("unp", modules.SoAtoAoS(T,1,{xyinner,fInputType}), inp) -- {{uint16,uint16},A}[T]
  local out = rigel.apply("f", modules.map(f,T), unpacked )
  local ff = modules.lambda("liftXYSeqPointwise_"..f.kind, inp, out )
  return modules.liftXYSeq(ff,W,H,T)
end

-- takes an image of size A[W,H] to size A[W-L-R,H-B-Top]
modules.cropSeq = memoize(function( A, W, H, T, L, R, B, Top )
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

  local tfn
  if terralib~=nil then tfn = MT.cropSeqFn(innerInputType,outputType,A, W, H, T, L, R, B, Top )  end

  local f = modules.lift( "CropSeq_"..tostring(A):gsub('%W','_').."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T), innerInputType, outputType, 0, 
                           tfn, sinp, S.tuple{sdata,svalid}, nil, {{((W-L-R)*(H-B-Top))/T,(W*H)/T}})

  return modules.liftXYSeq( f, W, H, T  )
                           end)

-- takes an image of size A[W,H] to size A[W+L+R,H+B+Top]. Fills the new pixels with value 'Value'
-- sequentialized to throughput T
modules.padSeq = memoize(function( A, W, H, T, L, R, B, Top, Value )
  err( types.isType(A), "A must be a type")
  map({W=W,H=H,T=T,L=L,R=R,B=B,Top=Top},function(n,k) assert(type(n)=="number"); err(n==math.floor(n),"PadSeq non-integer argument "..k..":"..n); err(n>=0,"n<0") end)
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

  if terralib~=nil then res.terraModule = MT.padSeq( res, A, W, H, T, L, R, B, Top, Value ) end

  res.systolicModule = Ssugar.moduleConstructor("PadSeq_"..tostring(A):gsub('%W','_').."_W"..W.."_H"..H.."_L"..L.."_R"..R.."_B"..B.."_Top"..Top.."_T"..T..T)


  local posX = res.systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap( types.uint(32), W+L+R-T, T ) ):CE(true):setInit(0):instantiate("posX_padSeq") ) 
  local posY = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), H+Top+B-1) ):CE(true):setInit(0):instantiate("posY_padSeq") ) 
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(16),types.uint(16),types.bool()}, "x %d y %d ready %d", true ):instantiate("printInst") ) end

  local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
  local pvalid = S.parameter("process_valid", types.bool() )

  local C1 = S.ge( posX:get(), S.constant(L,types.uint(32)))
  local C2 = S.lt( posX:get(), S.constant(L+W,types.uint(32)))
  local C3 = S.ge( posY:get(), S.constant(B,types.uint(16)))
  local C4 = S.lt( posY:get(), S.constant(B+H,types.uint(16)))
  local xcheck = S.__and(C1,C2)
  local ycheck = S.__and(C3,C4)
  local isInside = S.__and(xcheck,ycheck)
  local readybit = isInside:disablePipelining()

  local pipelines={}
  --local stepPipe = S.__or( pinp_valid, S.__not(readybit) )
  local incY = S.eq( posX:get(), S.constant(W+L+R-T,types.uint(32))  ):disablePipelining()
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

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {posX:set(S.constant(0,types.uint(32))), posY:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()), CE) )

  res.systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), readybit, "ready", {} ) )

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
  assert(X==nil)

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

  if inputRate>outputRate then -- 8 to 4
    res.sdfInput, res.sdfOutput = {{outputRate,inputRate}},{{1,1}}
  else -- 4 to 8
    res.sdfInput, res.sdfOutput = {{1,1}},{{inputRate,outputRate}}
  end

  res.systolicModule = Ssugar.moduleConstructor("ChangeRate_"..tostring(A).."_from"..inputRate.."_to"..outputRate.."_H"..H)
  local svalid = S.parameter("process_valid", types.bool() )
  local rvalid = S.parameter("reset", types.bool() )
  local pinp = S.parameter("process_input", rigel.lower(res.inputType) )

  local regs = map( range(maxRate), function(i) return res.systolicModule:add(S.module.reg(A,true):instantiate("Buffer_"..i)) end )

  if inputRate>outputRate then

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

    local sPhase = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), inputCount-1) ):CE(true):instantiate("phase_changerateup") )
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

  if terralib~=nil then res.terraModule = MT.changeRate(res, A, H, inputRate, outputRate,maxRate,outputCount,inputCount ) end

  return modules.waitOnInput(rigel.newFunction(res))
end)

modules.linebuffer = memoize(function( A, w, h, T, ymin, X )
  assert(w>0); assert(h>0);
  assert(ymin<=0)
  assert(X==nil)
  
  -- if W%T~=0, then we would potentially have to do two reads on wraparound. So don't allow this case.
  err( w%T==0, "Linebuffer error, W%T~=0 , W="..tostring(w).." T="..tostring(T))

  local res = {kind="linebuffer", type=A, T=T, w=w, h=h, ymin=ymin }
  rigel.expectBasic(A)
  res.inputType = types.array2d(A,T)
  res.outputType = types.array2d(A,T,-ymin+1)
  res.stateful = true
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 0

  if terralib~=nil then res.terraModule = MT.linebuffer(res, A, w, h, T, ymin) end

  res.systolicModule = Ssugar.moduleConstructor("linebuffer_w"..w.."_h"..h.."_T"..T.."_ymin"..ymin.."_A"..tostring(A))
  local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
  local addr = res.systolicModule:add( S.module.regBy( types.uint(16), fpgamodules.incIfWrap( types.uint(16), (w/T)-1), true, nil ):instantiate("addr") )

  local outarray = {}
  local evicted

  local bits = rigel.lower(res.inputType):verilogBits()
  local bytes = nearestPowerOf2(upToNearest(8,bits)/8)
  local sizeInBytes = nearestPowerOf2((w/T)*bytes)
  --local init = map(range(0,sizeInBytes-1), function(i) return i%256 end)  
  local bramMod = fpgamodules.bramSDP( true, sizeInBytes, bytes, nil, nil, true )
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
      evicted = S.cast( evicted, rigel.lower(res.inputType) )
    end
  end

  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple( outarray ), rigel.lower(res.outputType) ), "process_output", {addr:setBy(S.constant(true, types.bool()))}, nil, CE ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {addr:set(S.constant(0,types.uint(16)))},S.parameter("reset",types.bool()),CE) )

  return rigel.newFunction(res)
end)

-- xmin, ymin are inclusive
modules.SSR = memoize(function( A, T, xmin, ymin )
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

  if terralib~=nil then res.terraModule = MT.SSR(res, A, T, xmin, ymin ) end

  res.systolicModule = Ssugar.moduleConstructor("SSR_W"..(-xmin+1).."_H"..(-ymin+1).."_T"..T.."_A"..tostring(A))
  local sinp = S.parameter("inp", rigel.lower(res.inputType))
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

  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple( out ), rigel.lower(res.outputType)), "process_output", pipelines, nil, S.CE("process_CE") ) )
  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro" ) )

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

  if terralib~=nil then res.terraModule =  MT.SSRPartial(res,A, T, xmin, ymin, stride, fullOutput) end

  res.systolicModule = Ssugar.moduleConstructor("SSRPartial_"..tostring(A):gsub('%W','_').."_T"..tostring(T))
  local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
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

  return rigel.newFunction(res)
end)

-- we could construct this out of liftHandshake, but this is a special case for when we don't need a fifo b/c this is always ready
modules.makeHandshake = memoize(function( f, tmuxRates )
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
    res.inputType = rigel.Handshake(f.inputType)
    res.outputType = rigel.Handshake(f.outputType)
    res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  end

  res.stateful = f.stateful

  if terralib~=nil then res.terraModule = MT.makeHandshake(res, f, tmuxRates ) end

  -- We _NEED_ to set an initial value for the shift register output (invalid), or else stuff downstream can get strange values before the pipe is primed
  res.systolicModule = Ssugar.moduleConstructor( "MakeHandshake_"..f.systolicModule.name):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

  local outputCount
  if DARKROOM_VERBOSE then outputCount = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIf() ):CE(true):instantiate("outputCount"):setCoherent(false) ) end

  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.bool(),rigel.extractValid(res.inputType),rigel.lower(f.outputType), rigel.extractValid(res.outputType), types.bool(), types.bool(), types.uint(16), types.uint(16)}, "RST %d IV %d O %h OV %d readyDownstream %d ready %d outputCount %d expectedOutput %d"):instantiate("printInst") ) end

  local SRdefault = false
  if tmuxRates~=nil then SRdefault = #tmuxRates end
  local SR = res.systolicModule:add( fpgamodules.shiftRegister( rigel.extractValid(res.inputType), f.systolicModule:getDelay("process"), SRdefault, true ):instantiate("validBitDelay_"..f.systolicModule.name):setCoherent(false) )
  local inner = res.systolicModule:add(f.systolicModule:instantiate("inner"))
  local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
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

  local fifo
  if csimOnly then
    res.systolicModule = fpgamodules.fifonoop(A)
  else
    res.systolicModule = Ssugar.moduleConstructor("fifo_SIZE"..size.."_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_BYTES"..tostring(bytes))

    local fifo = res.systolicModule:add( fpgamodules.fifo(A,size,DARKROOM_VERBOSE):instantiate("FIFO") )

    --------------
    -- basic -> R
    local store = res.systolicModule:addFunction( Ssugar.lambdaConstructor( "store", A, "store_input" ) )
    local storeCE = S.CE("store_CE")
    store:setCE(storeCE)
    store:addPipeline( fifo:pushBack( store:getInput() ) )
    --store:setOutput(S.tuple{S.null(),S.constant(true,types.bool(true))}, "store_output")
    local storeReady = res.systolicModule:addFunction( Ssugar.lambdaConstructor( "store_ready" ) )
    if nostall then
      storeReady:setOutput( S.constant(true,types.bool()), "store_ready" )
    else
      storeReady:setOutput( fifo:ready(), "store_ready" )
    end
    local storeReset = res.systolicModule:addFunction( Ssugar.lambdaConstructor( "store_reset" ) )
    storeReset:setCE(storeCE)
    storeReset:addPipeline(fifo:pushBackReset())
    --------------
    -- basic -> V
    local load = res.systolicModule:addFunction( Ssugar.lambdaConstructor( "load", types.null(), "process_input" ) )
    local loadCE = S.CE("load_CE")
    load:setCE(loadCE)
    load:setOutput( S.tuple{fifo:popFront( nil, fifo:hasData() ), fifo:hasData() }, "load_output" )
    local loadReset = res.systolicModule:addFunction( Ssugar.lambdaConstructor( "load_reset" ) )
    loadReset:setCE(loadCE)
    loadReset:addPipeline(fifo:popFrontReset())
    --------------
    -- debug
    if W~=nil then
    local outputCount = res.systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap(types.uint(32),((W*H)/T)-1,1) ):CE(true):setInit(0):instantiate("outputCount") )
    load:addPipeline(outputCount:setBy(fifo:hasData()))
    loadReset:addPipeline(outputCount:set(S.constant(0,types.uint(32))))

    local maxSize = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.max(types.uint(16),true) ):CE(true):setInit(0):instantiate("maxSize") ) 
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
  end

  return rigel.newFunction(res)
                        end)

function modules.lut( inputType, outputType, values )
  err( types.isType(inputType), "inputType must be type")
  rigel.expectBasic( inputType )
  err( types.isType(outputType), "outputType must be type")
  rigel.expectBasic( outputType )

  local inputCount = math.pow(2, inputType:verilogBits())
  err( inputCount==#values, "values array has insufficient entries, has "..tonumber(#values).." but should have "..tonumber(inputCount))

  local res = {kind="lut", inputType=inputType, outputType=outputType, values=values, stateful=false }
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 1

  if terralib~=nil then res.terraModule = MT.lut(inputType, outputType, values, inputCount) end

  res.systolicModule = Ssugar.moduleConstructor("LUT")
  local lut = res.systolicModule:add( fpgamodules.bramSDP(true, inputCount*(outputType:verilogBits()/8), inputType:verilogBits()/8, outputType:verilogBits()/8, values, true ):instantiate("LUT") )

  local sinp = S.parameter("process_input", res.inputType )

  local pipelines = {}
  table.insert(pipelines, lut:writeAndReturnOriginal( S.tuple{sinp,S.constant(0,types.bits(inputType:verilogBits()))},S.constant(false,types.bool())) ) -- needs to be driven, but set valid==false
  res.systolicModule:addFunction( S.lambda("process",sinp, S.cast(lut:read(sinp),outputType), "process_output", pipelines, nil, S.CE("process_CE") ) )

  return rigel.newFunction(res)
end

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

  if terralib~=nil then res.terraModule = MT.reduce(res,f,W,H) end

  res.systolicModule = Ssugar.moduleConstructor("reduce_"..f.systolicModule.name.."_W"..tostring(W).."_H"..tostring(H))
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

  if terralib~=nil then res.terraModule = MT.reduceSeq(res,f,T) end

  local del = f.systolicModule:getDelay("process")
  err( del == 0, "ReduceSeq function must have delay==0 but instead has delay of "..del )

  res.systolicModule = Ssugar.moduleConstructor("ReduceSeq_"..f.systolicModule.name.."_T"..tostring(1/T))
  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(16),f.outputType,f.outputType}, "ReduceSeq "..f.systolicModule.name.." phase %d input %d output %d", true):instantiate("printInst") ) end
  local sinp = S.parameter("process_input", f.outputType )
  local svalid = S.parameter("process_valid", types.bool() )
  --local phaseValue, phaseValid, phasePipelines, phaseResetPipelines = fpgamodules.addPhaser( res.systolicModule, 1/T, svalid )
  local phase = res.systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.sumwrap(types.uint(16), (1/T)-1 ) ):CE(true):instantiate("phase") )
  
  local pipelines = {}
  table.insert(pipelines, phase:setBy( S.constant(1,types.uint(16)) ) )

  local out
  
  if T==1 then
    -- hack: Our reduce fn always adds two numbers. If we only have 1 number, it won't work! just return the input.
    out = sinp
  else
    local sResult = res.systolicModule:add( Ssugar.regByConstructor( f.outputType, f.systolicModule ):CE(true):instantiate("result") )
    table.insert( pipelines, sResult:set( sinp, S.eq(phase:get(), S.constant(0, types.uint(16) ) ):disablePipelining() ) )
    out = sResult:setBy( sinp, S.__not(S.eq(phase:get(), S.constant(0, types.uint(16) ) )):disablePipelining() )
  end

  if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process( S.tuple{phase:get(),sinp,out} ) ) end

  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ out, S.eq(phase:get(), S.constant( (1/T)-1, types.uint(16))) }, "process_output", pipelines, svalid, CE) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:set(S.constant(0,types.uint(16)))}, S.parameter("reset",types.bool()),CE) )

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

  res.systolicModule = Ssugar.moduleConstructor("Overflow_"..count)
  local cnt = res.systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32))):CE(true):instantiate("cnt") )

  local sinp = S.parameter("process_input", A )
  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ sinp, S.lt(cnt:get(), S.constant( count, types.uint(32))) }, "process_output", {cnt:setBy(S.constant(true,types.bool()))}, nil, CE ) )

  res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {cnt:set(S.constant(0,types.uint(32)))}, S.parameter("reset",types.bool()), CE) )

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

  res.systolicModule = Ssugar.moduleConstructor( "Underflow_A"..tostring(A).."_count"..count.."_cycles"..cycles.."_toosoon"..tostring(tooSoonCycles).."_US"..tostring(upstream)):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(32),types.uint(32),types.bool()}, "outputCount %d cycleCount %d outValid"):instantiate("printInst") ) end

  local outputCount = res.systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32)) ):CE(true):instantiate("outputCount"):setCoherent(false) )

  -- NOTE THAT WE Are counting cycles where downstream_ready == true
  local cycleCount = res.systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32)) ):CE(true):instantiate("cycleCount"):setCoherent(false) )

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

  if terralib~=nil then res.terraModule = MT.cycleCounter(res,A,count) end

  res.systolicModule = Ssugar.moduleConstructor( "CycleCounter_A"..tostring(A).."_count"..count ):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

  local printInst
  if DARKROOM_VERBOSE then printInst = res.systolicModule:add( S.module.print( types.tuple{types.uint(32),types.uint(32),types.bool(),types.bool()}, "cycleCounter outputCount %d cycleCount %d outValid %d metadataMode %d"):instantiate("printInst") ) end

  local outputCount = res.systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap(types.uint(32),count+padCount-1,1) ):CE(true):instantiate("outputCount"):setCoherent(false) )
  local cycleCount = res.systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32),false) ):CE(false):instantiate("cycleCount"):setCoherent(false) )

  local rst = S.parameter("reset",types.bool())

  local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
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

  return rigel.newFunction( res )
    end)

-- this takes in a darkroom IR graph and normalizes the input SDF rate so that
-- it obeys our constraints: (1) neither input or output should have bandwidth (token count) > 1
-- and (2) no node should have SDF rate > 1
local function lambdaSDFNormalize(input,output)
  local sdfMaxRate = output:sdfExtremeRate(true)
  err( SDFRate.fracToNumber(sdfMaxRate)>=1, "sdf max rate is <1?")

  if input.sdfRate~=nil then
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
        assert(n.id==input.id)
        n.sdfRate = SDFRate.multiply(n.sdfRate,scaleFactor[1],scaleFactor[2])
        assert( SDFRate.isSDFRate(n.sdfRate))
        newInput = rigel.newIR(n)
        return newInput
      end
      end)

  return newInput, newOutput
end


-- function definition
-- output, inputs
function modules.lambda( name, input, output, instances, pipelines, X )
  if DARKROOM_VERBOSE then print("lambda start '"..name.."'") end

  assert(X==nil)
  assert( type(name) == "string" )
  assert( rigel.isIR( input ) )
  assert( input.kind=="input" )
  assert( rigel.isIR( output ) )
  assert( instances==nil or type(instances)=="table")
  if instances~=nil then map( instances, function(n) assert(rigel.isInstance(n)) end ) end
  assert( pipelines==nil or type(pipelines)=="table")
  if pipelines~=nil then map( pipelines, function(n) assert(rigel.isIR(n)) end ) end


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

  if rigel.isHandshake( input.type ) == false and rigel.isHandshake(output.type)==false then
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

  res.terraModule = MT.lambdaCompile(res)

  assert( SDFRate.isSDFRate(input.sdfRate) )
  res.sdfInput = input.sdfRate
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
    print("INP",#res.sdfInput,res.sdfInput[1][1],res.sdfInput[1][2])
    print("out",#res.sdfOutput,res.sdfOutput[1][1],res.sdfOutput[1][2])
    err(false, "lambda '"..name.."' has strange SDF rate")
  end

  local function makeSystolic( fn )
    local module = Ssugar.moduleConstructor( fn.name ):onlyWire(rigel.isHandshake(fn.inputType) or rigel.isHandshake(fn.outputType))

    if rigel.isHandshake(fn.outputType) then
      module:parameters{INPUT_COUNT=0, OUTPUT_COUNT=0}
    end

    local process = module:addFunction( Ssugar.lambdaConstructor( "process", rigel.lower(fn.inputType), "process_input") )
    local reset = module:addFunction( Ssugar.lambdaConstructor( "reset", types.null(), "resetNILINPUT", "reset") )

    if rigel.isHandshake(fn.inputType)==false and rigel.isHandshake(fn.outputType)==false then 
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
    elseif rigel.isHandshake( fn.inputType ) or rigel.isHandshake( fn.outputType )  then
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
            if n.fn.outputType:isArray() and rigel.isHandshake(n.fn.outputType:arrayOver()) then
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
  return rigel.newFunction( res )
end

function modules.lift( name, inputType, outputType, delay, terraFunction, systolicInput, systolicOutput, systolicInstances, sdfOutput, X )
  err( type(name)=="string", "lift name must be string" )
  assert( types.isType(inputType ) )
  assert( types.isType(outputType ) )
  assert( type(delay)=="number" )
  err( systolic.isAST(systolicOutput), "missing systolic output")
  err(sdfOutput==nil or SDFRate.isSDFRate(sdfOutput),"SDF output must be SDF")
  assert(X==nil)

  if sdfOutput==nil then sdfOutput = {{1,1}} end


  err( systolicOutput.type:constSubtypeOf(outputType), "lifted systolic output type does not match. Is "..tostring(systolicOutput.type).." but should be "..tostring(outputType) )

  local systolicModule = Ssugar.moduleConstructor(name)

  if systolicInstances~=nil then
    for k,v in pairs(systolicInstances) do systolicModule:add(v) end
  end

  systolicModule:addFunction( S.lambda("process", systolicInput, systolicOutput, "process_output",nil,nil,S.CE("process_CE")) )
  local nip = S.parameter("nip",types.null())
  --systolicModule:addFunction( S.lambda("reset", nip, nil,"reset_output") )
  systolicModule:complete()
  local res = { kind="lift_"..name, inputType = inputType, outputType = outputType, delay=delay, systolicModule=systolicModule, sdfInput={{1,1}}, sdfOutput=sdfOutput, stateful=false }

  if terralib~=nil then res.terraModule=MT.lift(inputType,outputType,terraFunction) end

  return rigel.newFunction( res )
end

modules.constSeq = memoize(function( value, A, w, h, T, X )
  assert(type(value)=="table")
  assert(type(value[1])=="number")
  err(#value==w*h, "table has wrong number of values")
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

  if terralib~=nil then res.terraModule = MT.constSeq(res, value, A, w, h, T,W ) end

  res.systolicModule = Ssugar.moduleConstructor("constSeq_"..tostring(value):gsub('%W','_').."_T"..tostring(1/T))
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
  res.systolicModule = Ssugar.moduleConstructor("freadSeq_"..filename:gsub('%W','_'))
  local sfile = res.systolicModule:add( S.module.file( filenameVerilog, ty, true ):instantiate("freadfile") )
  local inp = S.parameter("process_input", types.null() )
  local nilinp = S.parameter("process_nilinp", types.null() )
  local CE = S.CE("CE")
  res.systolicModule:addFunction( S.lambda("process", inp, sfile:read(), "process_output", nil, nil, CE ) )
  res.systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", {sfile:reset()}, S.parameter("reset", types.bool() ), CE ) )

  return rigel.newFunction(res)
                            end)

function modules.fwriteSeq( filename, ty )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  rigel.expectBasic(ty)
  local filenameVerilog=filename
    local res = {kind="fwriteSeq", filename=filename, filenameVerilog=filenameVerilog, type=ty, inputType=ty, outputType=ty, stateful=true, delay=0, sdfInput={{1,1}}, sdfOutput={{1,1}} }
  if terralib~=nil then res.terraModule = MT.fwriteSeq(filename,ty) end
  res.systolicModule = Ssugar.moduleConstructor("fwriteSeq_"..filename:gsub('%W','_'))
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

  return rigel.newFunction(res)
end

function modules.seqMap( f, W, H, T )
  err( darkroom.isFunction(f), "fn must be a function")
  err( type(W)=="number", "W must be a number")
  err( type(H)=="number", "H must be a number")
  err( type(T)=="number", "T must be a number")
  darkroom.expectBasic(f.inputType)
  darkroom.expectBasic(f.outputType)
  local res = {kind="seqMap", W=W,H=H,T=T,inputType=types.null(),outputType=types.null()}
  if terralib~=nil then res.terraModule = MT.seqMap(f, W, H, T) end

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

function modules.seqMapHandshake( f, inputType, tapInputType, tapValue, inputCount, outputCount, axi, readyRate, X )
  err( darkroom.isFunction(f), "fn must be a function")
  err( types.isType(inputType), "inputType must be a type")
  err( tapInputType==nil or types.isType(tapInputType), "tapInputType must be a type")
  if tapInputType~=nil then tapInputType:checkLuaValue(tapValue) end
  err( type(inputCount)=="number", "inputCount must be a number")
  err( type(outputCount)=="number", "outputCount must be a number")
  err( type(axi)=="boolean", "axi should be a bool")
  assert(X==nil)

  darkroom.expectHandshake(f.inputType)
  darkroom.expectHandshake(f.outputType)

  local expectedOutputCount = (inputCount*f.sdfOutput[1][1]*f.sdfInput[1][2])/(f.sdfOutput[1][2]*f.sdfInput[1][1])
  err(expectedOutputCount==outputCount, "Error, seqMapHandshake, SDF output tokens ("..tostring(expectedOutputCount)..") does not match stated output tokens ("..tostring(outputCount)..")")

  local res = {kind="seqMapHandshake", tapInputType=tapInputType, tapValue=tapValue, inputCount=inputCount, outputCount=outputCount, inputType=types.null(),outputType=types.null()}
  res.sdfInput = f.sdfInput
  res.sdfOutput = f.sdfOutput

  if readyRate==nil then readyRate=1 end

  if terralib~=nil then res.terraModule = MT.seqMapHandshake( f, inputType, tapInputType, tapValue, inputCount, outputCount, axi, readyRate) end

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

  res.systolicModule = Ssugar.moduleConstructor("SeqMapHandshake_"..f.systolicModule.name.."_"..inputCount.."_"..outputCount.."_rr"..readyRate):verilog(verilogStr)
  res.systolicModule:add(f.systolicModule:instantiate("inst"))

  return darkroom.newFunction(res)
end

return modules