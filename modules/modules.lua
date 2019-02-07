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
local SDF = require "sdf"
local Uniform = require "uniform"

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
  err( rigel.isFunction(f), "compose: second argument should be rigel module")
  err( rigel.isFunction(g), "compose: third argument should be rigel module")

  name = J.verilogSanitize(name)

  local inp = rigel.input( g.inputType, g.sdfInput )
  local gvalue = rigel.apply(name.."_g",g,inp)
  return modules.lambda( name, inp, rigel.apply(name.."_f",f,gvalue), nil, generatorStr )
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

  local res
  if (W*H)%2==0 and asArray==false then
    -- codesize optimization (make codesize log(n) instead of linear)
 
    local C = require "examplescommon"

    local itype = types.tuple( J.map(typelist, function(t) return types.array2d(t,W,H) end) )
    local I = rigel.input( itype )

    local IA = {}
    local IB = {}
    for k,t in ipairs(typelist) do
      local i = rigel.apply("II"..tostring(k-1), C.index(itype,k-1), I)
      
      local ic = rigel.apply( "cc"..tostring(k-1), C.cast( types.array2d( t, W, H ), types.array2d( t, W*H ) ), i)

      local ica = rigel.apply("ica"..tostring(k-1), C.slice(types.array2d( t, W*H ),0,(W*H)/2-1,0,0), ic)
      local icb = rigel.apply("icb"..tostring(k-1), C.slice(types.array2d( t, W*H ),(W*H)/2,(W*H)-1,0,0), ic)
      table.insert(IA,ica)
      table.insert(IB,icb)
    end

    IA = rigel.concat("IA",IA)
    IB = rigel.concat("IB",IB)

    local oa = rigel.apply("oa", modules.SoAtoAoS((W*H)/2,1,typelist,asArray), IA)
    local ob = rigel.apply("ob", modules.SoAtoAoS((W*H)/2,1,typelist,asArray), IB)

    local out = rigel.concat("conc", {oa,ob})
    --local T = types.array2d( types.tuple(typelist), (W*H)/2 )
    out = rigel.apply( "cflat", C.flatten2( types.tuple(typelist), W*H ), out)
    out = rigel.apply( "cflatar", C.cast( types.array2d( types.tuple(typelist), W*H ), types.array2d( types.tuple(typelist), W,H ) ), out)

    res = modules.lambda(verilogSanitize("SoAtoAoS_W"..tostring(W).."_H"..tostring(H).."_types"..tostring(typelist).."_asArray"..tostring(asArray)), I, out)
  else
    res = { kind="SoAtoAoS", W=W, H=H, asArray = asArray }
    
    res.inputType = types.tuple( J.map(typelist, function(t) return types.array2d(t,W,H) end) )
    if asArray then
      J.map( typelist, function(n) err(n==typelist[1], "if asArray==true, all elements in typelist must match") end )
      res.outputType = types.array2d(types.array2d(typelist[1],#typelist),W,H)
    else
      res.outputType = types.array2d(types.tuple(typelist),W,H)
    end
    
    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
    res.delay = 0
    res.stateful=false
    res.name = verilogSanitize("SoAtoAoS_W"..tostring(W).."_H"..tostring(H).."_types"..tostring(typelist).."_asArray"..tostring(asArray))
    
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

    res = rigel.newFunction(res)
  end
  
  if terralib~=nil then res.terraModule = MT.SoAtoAoS(res,W,H,typelist,asArray) end

  return res
end)

-- Converst {Handshake(a), Handshake(b)...} to Handshake{a,b}
-- typelist should be a table of pure types
-- WARNING: ready depends on ValidIn
modules.packTuple = memoize(function( typelist, disableFIFOCheck, X )
  err( type(typelist)=="table", "packTuple: type list must be table" )
  err( disableFIFOCheck==nil or type(disableFIFOCheck)=="boolean", "packTuple: disableFIFOCheck must be nil or bool" )
  err( X==nil, "packTuple: too many arguments" )
  
  local res = {kind="packTuple", disableFIFOCheck = disableFIFOCheck}
  
  J.map(typelist, function(t) rigel.expectBasic(t) end )
  res.inputType = rigel.HandshakeTuple(typelist)
  res.outputType = rigel.Handshake( types.tuple(typelist) )
  res.stateful = false
  res.sdfOutput = SDF{1,1}
  res.sdfInput = SDF(J.map(typelist, function(n)  return {1,1} end))
  res.name = "packTuple_"..verilogSanitize(tostring(typelist))

  res.delay = 0

  if terralib~=nil then res.terraModule = MT.packTuple(res,typelist) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local CE
    local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
    --systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro",nil,nil,CE) )
    
    systolicModule:onlyWire(true)
    
    local printStr = "IV ["..table.concat( J.broadcast("%d",#typelist),",").."] OV %d ready ["..table.concat(J.broadcast("%d",#typelist),",").."] readyDownstream %d"
    local printInst 
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple(J.broadcast(types.bool(),(#typelist)*2+2)), printStr):instantiate("printInst") ) end
    
    local activePorts={}
    for k,v in pairs(typelist) do  table.insert(activePorts,k) end
      
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
      -- if this stream doesn't have data, let it run regardless.
      local valid_i = S.index(S.index(sinp,i-1),1)
      table.insert( readyOutList, S.__or(S.__and( downstreamReady, validOut), S.__not(valid_i) ) )
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
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
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
    if f.stateful then systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {},S.parameter("reset",types.bool())) ) end
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
      res:addFunction( S.lambda(fnname.."_reset", resetSrcFn:getInput(), inner[fnname.."_reset"]( inner, resetSrcFn:getInput() ), resetSrcFn:getOutputName(), nil, resetSrcFn:getValid() ) )
    end

  end
end

-- This takes a basic->R to V->RV
-- Compare to waitOnInput below: runIffReady is used when we want to take control of the ready bit purely for performance reasons, but don't want to amplify or decimate data.
local function runIffReadySystolic( systolicModule, fns, passthroughFns )
  if Ssugar.isModuleConstructor(systolicModule) then systolicModule = systolicModule:toModule() end
  local res = Ssugar.moduleConstructor("RunIffReady_"..systolicModule.name)
  local inner = res:add( systolicModule:instantiate("RunIffReady") )

  for _,fnname in pairs(fns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    err( systolicModule:getDelay(prefix.."ready")==0, "ready bit should not be pipelined")

    local sinp

    if srcFn:getInput().type==types.null() then
      sinp = S.parameter(fnname.."_input", types.null() )
    else
      sinp = S.parameter(fnname.."_input", rigel.lower(rigel.V(srcFn:getInput().type)) )
    end
    
    local svalid = S.parameter(fnname.."_valid", types.bool())
    local runable = S.__and(inner[prefix.."ready"](inner), S.index(sinp,1) ):disablePipelining()

    local out = inner[fnname]( inner, S.index(sinp,0), runable )

    if out.type==types.null() then
      
    else
      out = S.tuple{ out, S.__and( runable,svalid ):disablePipelining() }
    end
    
    local RST = S.parameter(prefix.."reset",types.bool())
    if systolicModule:lookupFunction(prefix.."reset"):isPure() then RST=S.constant(false,types.bool()) end

    local pipelines = {}

    local CE = S.CE("CE")
    res:addFunction( S.lambda(fnname, sinp, out, fnname.."_output", pipelines, svalid, CE ) )
    res:addFunction( S.lambda(prefix.."reset", S.parameter(prefix.."r",types.null()), inner[prefix.."reset"](inner), "ro", {}, RST) )
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

    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple{inner[prefix.."ready"](inner),S.index(sinp,1), runable, RST} ) ) end

    local CE = S.CE("CE")
    res:addFunction( S.lambda(fnname, sinp, S.tuple{ S.index(out,0), S.__and(S.index(out,1),S.__and(runable,svalid):disablePipelining()):disablePipeliningSingle() }, fnname.."_output", pipelines, svalid, CE ) )
    res:addFunction( S.lambda(prefix.."reset", S.parameter(prefix.."r",types.null()), inner[prefix.."reset"](inner), "ro", {}, RST) )
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
  res.sdfInput = SDF{1,factor}
  res.sdfOutput = SDF{1,factor}
  res.stateful = true
  res.delay = 0
  res.name = "ReduceThroughput_"..tostring(factor)

  if terralib~=nil then res.terraModule = MT.reduceThroughput(res,A,factor) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local phase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), factor-1, 1 ) ):CE(true):setInit(0):setReset(0):instantiate("phase") ) 

    local reading = S.eq( phase:get(), S.constant(0,types.uint(16)) ):disablePipelining()
    
    local sinp = S.parameter( "inp", A )
    
    local pipelines = {}
    table.insert(pipelines, phase:setBy(S.constant(true,types.bool())))

    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{sinp,reading}, "process_output", pipelines, nil, CE) )
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:reset()},S.parameter("reset",types.bool())) )

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
  err( rigel.isRV(f.outputType) or f.outputType:is("RVFramed"), "waitOnInput: output type should be RV, but is: "..tostring(f.outputType))
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

local function liftDecimateSystolic( systolicModule, liftFns, passthroughFns, handshakeTrigger )
  if Ssugar.isModuleConstructor(systolicModule) then systolicModule=systolicModule:toModule() end
  assert( S.isModule(systolicModule) )
  assert(type(handshakeTrigger)=="boolean")
  
  local res = Ssugar.moduleConstructor("LiftDecimate_"..systolicModule.name)
  local inner = res:add( systolicModule:instantiate("LiftDecimate") )

  for _,fnname in pairs(liftFns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    local sinp
    local datai
    local validi
    if srcFn.inputParameter.type==types.null() and handshakeTrigger==false then
      sinp = S.parameter(fnname.."_input", types.null() )
    elseif srcFn.inputParameter.type==types.null() and handshakeTrigger then
      sinp = S.parameter(fnname.."_input", types.bool() )
      validi = sinp
    else
      sinp = S.parameter(fnname.."_input", rigel.lower(rigel.V(srcFn.inputParameter.type)) )
      datai = S.index(sinp,0)
      validi = S.index(sinp,1)
    end

    local pout = inner[fnname]( inner, datai, validi )
    --local 
    local pout_data, pout_valid

    if pout.type:isTuple() and #pout.type.list==2 then
      pout_data = S.index(pout,0)
      pout_valid = S.index(pout,1)
    elseif pout.type:isBool() then
      pout_valid = pout
    else
      assert(false)
    end
    local validout = pout_valid

    if srcFn.inputParameter.type~=types.null() then
      validout = S.__and(pout_valid,validi)
    end
    
    local CE = S.CE(prefix.."CE")

    if pout_data==nil then
      res:addFunction( S.lambda(fnname, sinp, validout, fnname.."_output",nil,nil,CE ) )
    else
      res:addFunction( S.lambda(fnname, sinp, S.tuple{pout_data, validout}, fnname.."_output",nil,nil,CE ) )
    end
    
    if systolicModule:lookupFunction(prefix.."reset")~=nil then
      -- stateless modules don't have a reset
      res:addFunction( S.lambda(prefix.."reset", S.parameter("r",types.null()), inner[prefix.."reset"](inner), "ro", {},S.parameter(prefix.."reset",types.bool())) )
    end
    res:addFunction( S.lambda(prefix.."ready", S.parameter(prefix.."readyinp",types.null()), S.constant(true,types.bool()), prefix.."ready", {} ) )
  end

  passthroughSystolic( res, systolicModule, inner, passthroughFns )

  return res
end

-- takes basic->V to V->RV
-- if handshakeTrigger==true, then nil->V(A) maps to VTrigger->RV(A)
modules.liftDecimate = memoize(function(f, handshakeTrigger, X)
  err( rigel.isFunction(f), "liftDecimate: input should be rigel module" )
  err( X==nil, "liftDecimate: too many arguments")
  if handshakeTrigger==nil then handshakeTrigger=true end
  
  local res = {kind="liftDecimate", fn = f}
  err( types.isBasic(f.inputType) or f.inputType:is("StaticFramed"), "liftDecimate: fn input type should be basic or StaticFramed" )

  if f.inputType==types.null() then
    res.inputType = rigel.VTrigger
  elseif f.inputType:is("StaticFramed") then
    res.inputType = types.VFramed( f.inputType.params.A, f.inputType.params.mixed, f.inputType.params.dims )
  else
    res.inputType = rigel.V(f.inputType)
  end
  
  res.name = "LiftDecimate_"..f.name

  if rigel.isV(f.outputType) then
    res.outputType = rigel.RV(rigel.extractData(f.outputType))
  elseif rigel.isVTrigger(f.outputType) then
    res.outputType = rigel.RVTrigger
  elseif f.outputType:is("VFramed") then
    res.outputType = types.RVFramed( f.outputType.params.A, f.outputType.params.mixed, f.outputType.params.dims )
  else
    err(false, "liftDecimate: expected V output type, but is "..tostring(f.outputType))
  end

  err(type(f.stateful)=="boolean", "Missing stateful annotation for "..f.kind)
  res.stateful = f.stateful

  err( rigel.SDF==false or SDFRate.isSDFRate(f.sdfInput), "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput

  res.delay = f.delay

  if terralib~=nil then res.terraModule = MT.liftDecimate(res,f) end

  function res.makeSystolic()
    err( S.isModule(f.systolicModule), "Missing/incorrect systolic for "..f.name )
    return liftDecimateSystolic( f.systolicModule, {"process"}, {}, handshakeTrigger )
  end

  return rigel.newFunction(res)
end)

-- converts V->RV to RV->RV
modules.RPassthrough = memoize(function(f)
  local res = {kind="RPassthrough", fn = f}
  rigel.expectV(f.inputType)
  err( rigel.isRV(f.outputType) or f.outputType:is("RVFramed"),"RPassthrough: fn output type should be RV, but is: "..tostring(f.outputType) )
  res.inputType = rigel.RV(rigel.extractData(f.inputType))
  res.outputType = f.outputType
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
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", {}, S.parameter("reset",types.bool())) )
    end
    local rinp = S.parameter("ready_input", types.bool() )
    systolicModule:addFunction( S.lambda("ready", rinp, S.__and(inner:ready(),rinp):disablePipelining(), "ready", {} ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

local function liftHandshakeSystolic( systolicModule, liftFns, passthroughFns, hasReadyInput, X )
  if Ssugar.isModuleConstructor(systolicModule) then systolicModule = systolicModule:toModule() end
  err( S.isModule(systolicModule), "liftHandshakeSystolic: systolicModule not a systolic module?" )
  assert(type(hasReadyInput)=="table")
  assert(X==nil)
  
  local res = Ssugar.moduleConstructor( "LiftHandshake_"..systolicModule.name ):onlyWire(true):parameters({INPUT_COUNT=0, OUTPUT_COUNT=0})
  local inner = res:add(systolicModule:instantiate("inner_"..systolicModule.name))

  if Ssugar.isModuleConstructor(systolicModule) then systolicModule:complete(); systolicModule=systolicModule.module end

  for K,fnname in pairs(liftFns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    local printInst 
    if DARKROOM_VERBOSE then printInst = res:add( S.module.print( types.tuple{types.bool(), srcFn:getInput().type.list[1],types.bool(),srcFn:getOutput().type.list[1],types.bool(),types.bool(),types.bool(),types.uint(16), types.uint(16)}, fnname.." RST %d I %h IV %d O %h OV %d readyDownstream %d ready %d outputCount %d expectedOutputCount %d"):instantiate(prefix.."printInst") ) end

    local outputCount
    if STREAMING==false and DARKROOM_VERBOSE then outputCount = res:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIf() ):CE(true):instantiate(prefix.."outputCount") ) end

    local pinp = S.parameter(fnname.."_input", srcFn:getInput().type )

    local rst = S.parameter(prefix.."reset",types.bool())

    local downstreamReady
    local CE
    
    if hasReadyInput[K] then
      downstreamReady = S.parameter(prefix.."ready_downstream", types.bool())
      CE = downstreamReady
    else
      downstreamReady = S.parameter(prefix.."ready_downstream", types.null())
      CE = S.constant(true,types.bool())
    end

    local pout = inner[fnname](inner,pinp,S.constant(true,types.bool()), CE )

    if pout.type:isTuple() and #pout.type.list==2 then
    elseif pout.type==types.null() then
    elseif pout.type:isBool() then
    else
      print("liftHandshakeSystolic: unexpected return type? "..tostring(pout.type).." FNNAME:"..fnname)
      assert(false)
    end
    
    -- not blocked downstream: either downstream is ready (downstreamReady), or we don't have any data anyway (pout[1]==false), so we can work on clearing the pipe
    -- Actually - I don't think this is legal. We can't have our stall signal depend on our own output. We would have to register it, etc
    --local notBlockedDownstream = S.__or(downstreamReady, S.eq(S.index(pout,1),S.constant(false,types.bool()) ))
  --local CE = notBlockedDownstream
    
    -- the point of the shift register: systolic doesn't have an output valid bit, so we have to explicitly calculate it.
    -- basically, for the first N cycles the pipeline is executed, it will have garbage in the pipe (valid was false at the time those cycles occured). So we need to gate the output by the delayed valid bits. This is a little big goofy here, since process_valid is always true, except for resets! It's not true for the first few cycles after resets! And if we ignore that the first few outputs will be garbage!

    local SR, out
    if pout.type~=types.null() then
      SR = res:add( fpgamodules.shiftRegister( types.bool(), systolicModule:getDelay(fnname), false, true ):instantiate(prefix.."validBitDelay_"..systolicModule.name) )
    
      local srvalue = SR:pushPop(S.constant(true,types.bool()), S.constant(true,types.bool()), CE )
      local outvalid

      if pout.type:isBool() then -- IE RVTrigger
        outvalid = S.__and( pout, srvalue )
      else
        outvalid = S.__and(S.index(pout,1), srvalue )
      end
      
      local outvalidRaw = outvalid
      --if STREAMING==false then outvalid = S.__and( outvalid, S.lt(outputCount:get(),S.instanceParameter("OUTPUT_COUNT",types.uint(16)))) end

      if pout.type:isBool() then -- RVTrigger
        out = outvalid
      else
        out = S.tuple{ S.index(pout,0), outvalid }
      end
    else
      out = pout
    end
    
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

    if pout.type~=types.null() then
      resetPipelines[1] = SR:reset( nil, rst )
    end
    
    if STREAMING==false and DARKROOM_VERBOSE then table.insert(resetPipelines, outputCount:set(S.constant(0,types.uint(16)),rst,CE) ) end
    
    if systolicModule.functions[prefix.."reset"]~=nil then -- stateless modules do not have reset
      res:addFunction( S.lambda(prefix.."reset", S.parameter(prefix.."r",types.null()), inner[prefix.."reset"]( inner, nil, rst ), prefix.."reset_out", resetPipelines, rst ) )
    end

    assert( systolicModule:getDelay(prefix.."ready")==0 ) -- ready bit calculation can't be pipelined! That wouldn't make any sense
    
    res:addFunction( S.lambda(prefix.."ready", downstreamReady, readyOut, prefix.."ready" ) )
  end
  
  assert(#passthroughFns==0)

  return res
end

-- takes V->RV to Handshake->Handshake
modules.liftHandshake = memoize(function( f, X )
  err( X==nil, "liftHandshake: too many arguments" )
  local res = {kind="liftHandshake", fn=f}
  err( rigel.isV(f.inputType) or rigel.isVTrigger(f.inputType) or f.inputType:is("VFramed"), "liftHandshake: expected V or VTrigger or VFramed input type")
  err( rigel.isRV(f.outputType) or rigel.isRVTrigger(f.outputType) or f.outputType:is("RVFramed"),"liftHandshake: expected RV or RVTrigger or RVFramed output type")

  if rigel.isVTrigger(f.inputType) then
    res.inputType = rigel.HandshakeTrigger
  elseif f.inputType:is("VFramed") then
    res.inputType = types.HandshakeFramed( f.inputType.params.A, f.inputType.params.mixed, f.inputType.params.dims )
  else
    res.inputType = rigel.Handshake(rigel.extractData(f.inputType))
  end

  if rigel.isRVTrigger(f.outputType) then
    res.outputType = rigel.HandshakeTrigger
  elseif f.outputType:is("RVFramed") then
    res.outputType = types.HandshakeFramed( f.outputType.params.A, f.outputType.params.mixed, f.outputType.params.dims )
  else
    res.outputType = rigel.Handshake(rigel.extractData(f.outputType))
  end
  
  res.name = "LiftHandshake_"..f.name

  err( rigel.SDF==false or SDFRate.isSDFRate(f.sdfInput), "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  err(type(f.stateful)=="boolean", "Missing stateful annotation, "..f.kind)
  res.stateful = f.stateful

  local delay = math.max(1, f.delay)
  err(f.delay==math.floor(f.delay),"delay is fractional ?!, "..f.kind)

  if terralib~=nil then res.terraModule = MT.liftHandshake(res,f,delay) end

  function res.makeSystolic()
    assert( S.isModule(f.systolicModule) )
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
  res.sdfInput, res.sdfOutput = SDF{1,1}, SDF{1,1}
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
modules.map = memoize(function( f, W, H, X )
  err( rigel.isFunction(f), "first argument to map must be Rigel module, but is "..tostring(f) )
  err( type(W)=="number", "width must be number")
  err( X==nil, "map: too many arguments" )
  
  if H==nil then 
    return modules.map(f,W,1)
  end

  err( type(H)=="number", "map: H must be number" )

  err( types.isBasic(f.inputType), "map: error, mapping a module with a non-basic input type? name:"..f.name.." "..tostring(f.inputType))
  err( types.isBasic(f.outputType), "map: error, mapping a module with a non-basic output type? name:"..f.name.." "..tostring(f.outputType))

  err( W*H==1 or f.stateful==false,"map: mapping a stateful function ("..f.name.."), which will probably not work correctly. (may execute out of order)" )
  
  local res
  
  if (W*H)%2==0 then
    -- special case: this is a power of 2, so we can easily split it, to save compile time 
    -- (produces log(n) sized code instead of linear)
    
    local C = require "examplescommon"
    local I = rigel.input( types.array2d( f.inputType, W, H ) )
    local ic = rigel.apply( "cc", C.cast( types.array2d( f.inputType, W, H ), types.array2d( f.inputType, W*H ) ), I)

    local ica = rigel.apply("ica", C.slice(types.array2d( f.inputType, W*H ),0,(W*H)/2-1,0,0), ic)
    local a = rigel.apply("a", modules.map(f,(W*H)/2), ica)

    local icb = rigel.apply("icb", C.slice(types.array2d( f.inputType, W*H ),(W*H)/2,(W*H)-1,0,0), ic)
    local b = rigel.apply("b", modules.map(f,(W*H)/2), icb)

    local out = rigel.concat("conc", {a,b})
    --local T = types.array2d( f.outputType, (W*H)/2 )
    out = rigel.apply( "cflat", C.flatten2( f.outputType, W*H ), out)
    out = rigel.apply( "cflatar", C.cast( types.array2d( f.outputType, W*H ), types.array2d( f.outputType, W,H ) ), out)

    res = modules.lambda("map_"..f.name.."_W"..tostring(W).."_H"..tostring(H).."_logn", I, out)
  else
    res = { kind="map", fn = f, W=W, H=H }

    res.inputType = types.array2d( f.inputType, W, H )
    res.outputType = types.array2d( f.outputType, W, H )
    err( type(f.stateful)=="boolean", "Missing stateful annotation "..tostring(f))

    res.stateful = f.stateful
    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
    res.delay = f.delay
    res.name = sanitize("map_"..f.name.."_W"..tostring(W).."_H"..tostring(H))
    
    res.globals={}
    for k,_ in pairs(f.globals) do
      err( k.direction=="input", "modules.map: mapped modules not allowed to write output globals")
      res.globals[k] = 1
    end
    
    function res.makeSystolic()
      local systolicModule = Ssugar.moduleConstructor(res.name)
      
      for k,_ in pairs(f.globals) do
        systolicModule:addSideChannel(k.systolicValue)
        assert(S.isSideChannel(k.systolicValue))
      end
      
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
        print("ISTATE",f.name,f.stateful)
        systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, S.parameter("reset",types.bool()) ) )
      end
      return systolicModule
    end
    
    res = rigel.newFunction(res)
  end

  if terralib~=nil then res.terraModule = MT.map(res,f,W,H) end

  return res
end)

-- vectorized: if true, treat fn as a vectorized module (ie has some array size V, where V will be part of the {w,h} loop)
--                      (this is the same as 'mixed')
--             if false, just treat fn as some opaque data type
--
-- outputW/outputH/outputMixed: if 'fn' changes SDF Rate or vector size, this allows us to override the outputW/H/Mixed
--    think of this like a combined map+flatten operation (not just a hack..)
modules.mapFramed = memoize(function( fn, w, h, mixed, outputW, outputH, outputMixed, X )
  err( rigel.isFunction(fn), "mapFramed: first argument to map must be Rigel module, but is "..tostring(fn) )
  err( type(w)=="number", "mapFramed: width must be number")
  err( type(h)=="number", "mapFramed: height must be number")
  err( type(mixed)=="boolean", "mapFramed: mixed must be bool")
  err( outputW==nil or type(outputW)=="number", "mapFramed: outputW must be number or nil" )
  err( outputH==nil or type(outputH)=="number", "mapFramed: outputH must be number or nil" )
  err( outputMixed==nil or type(outputMixed)=="boolean", "mapFramed: outputMixed must be boolean or nil" )
  err( X==nil, "mapFramed: too many arguments" )
       
  local res = {kind="mapFramed",fn=fn,w=w,h=h,mixed=mixed,stateful=fn.stateful,delay=fn.delay}
  
  res.name=J.sanitize("MapFramed_"..fn.name.."_W"..tostring(w).."_H"..tostring(h).."_mixed"..tostring(mixed).."_outputW"..tostring(outputW).."_outputH"..tostring(outputH).."_outputMixed"..tostring(outputMixed))

  if fn.sdfInput~=nil then
    assert(#fn.sdfInput==1)
    assert(#fn.sdfOutput==1)
    res.sdfInput=SDF{fn.sdfInput[1][1],fn.sdfInput[1][2]}
    res.sdfOutput=SDF{fn.sdfOutput[1][1],fn.sdfOutput[1][2]}
  else
    res.sdfInput=SDF{1,1}
    res.sdfOutput=SDF{1,1}
  end
  
  res.globals={}
  for k,_ in pairs(fn.globals) do res.globals[k]=1 end

  res.globalMetadata = {}
  for k,v in pairs(fn.globalMetadata) do res.globalMetadata[k]=v end

  print("MAPFRAMED","inputType",fn.inputType,w,h,mixed)
  print("MAPFRAMED","outputType",fn.outputType, outputW, outputH, outputMixed)
  
  res.inputType = fn.inputType:addDim(w,h,mixed)

  -- tokens: # of parallel data tokens we process (which is what SDF tells us)
  -- make sure this ends up being consistant... (ie possible based on given vector widths/SDF)
  local inTok = w*h
  if mixed and fn.inputType:is("HandshakeFramed") then
    inTok = inTok/fn.inputType:FV()
  elseif mixed then
    err( types.isBasic(fn.inputType) or fn.inputType:is("Handshake"), "mapFramed unsupported type: "..tostring(fn.inputType) )
    local BT = rigel.extractData(fn.inputType)
    inTok = inTok/BT:channels()
  end

  local outTok
  if outputW==nil then
    res.outputType = fn.outputType:addDim(w,h,mixed)
    outTok = w*h
    if mixed and fn.outputType:is("HandshakeFramed") then
      outTok = outTok/fn.outputType:FV()
    elseif mixed then
      err( types.isBasic(fn.outputType) or fn.outputType:is("Handshake"), "mapFramed unsupported type: "..tostring(fn.outputType) )
      local BT = rigel.extractData(fn.outputType)
      outTok = outTok/BT:channels()
    end
  else
    res.outputType = fn.outputType:addDim(outputW,outputH,outputMixed)
    outTok = outputW*outputH

    if outputMixed then outTok = outTok/fn.outputType:FV() end
  end

  print("MAPFRAMED_RESTYPE",res.inputType, res.outputType)
  
  if fn.inputType:is("Handshake") then
    -- sanity check: make sure # of tokens we say we're making is consistant with SDF
    -- need to scale # of output tokens by SDF
    -- outputSDF/inputSDF = (out[1]/out[2])/(in[1]/in[2]) = (out[1]*in[2])/(out[2]*in[1])
    local n,d = fn.sdfOutput[1][1]*fn.sdfInput[1][2], fn.sdfOutput[1][2], fn.sdfInput[1][1]
    local SDFTok = (inTok*n)/d
    
    if outTok~=SDFTok then
      print("mapFramed: warning, number of input and output tokens not equal based on specified params! inTok:"..tostring(inTok).." outTok:"..tostring(outTok).." SDFTok:"..tostring(SDFTok).." inputW:"..tostring(w).." inputH:"..tostring(h).." outputW:"..tostring(outputW).." outputH:"..tostring(outputH))
    end
  end
  
  function res.makeSystolic()
    local sm = Ssugar.moduleConstructor(res.name)

    for k,_ in pairs(fn.globals) do
      sm:addSideChannel(k.systolicValue)
      if k.systolicValueReady~=nil then sm:addSideChannel(k.systolicValueReady) end
    end

    --local r = S.parameter("ready_downstream",types.bool())
    --sm:addFunction( S.lambda("ready", r, r, "ready") )
    local inner = sm:add(fn.systolicModule:instantiate("inner"))


    local CE = S.CE("process_CE")
    local reset_valid = S.parameter("reset",types.bool())
    if fn.inputType:is("Handshake") and fn.outputType==types.null() then
      sm:addFunction( S.lambda("ready", S.parameter("ready_downstream",types.null()), inner:ready(), "ready" ) )
      sm:onlyWire(true)
      CE=nil
    elseif (fn.inputType:is("Handshake") or fn.inputType:is("HandshakeFramed")) and (fn.outputType:is("Handshake") or fn.outputType:is("HandshakeFramed")) then
      local rds = S.parameter("ready_downstream",types.bool())
      sm:addFunction( S.lambda("ready", rds, inner:ready(rds), "ready" ) )
      sm:onlyWire(true)
      CE=nil
    elseif fn.inputType:is("StaticFramed") and (fn.outputType:is("StaticFramed") or fn.outputType:is("V")) then
      --
    else
      err(types.isBasic(fn.inputType) and types.isBasic(fn.outputType), "MapFramed NYI - "..tostring(fn.inputType).." "..tostring(fn.outputType) )
    end

    local I = S.parameter("process_input", rigel.lower(fn.inputType) )
    sm:addFunction( S.lambda("process",I,inner:process(I),"process_output",nil,nil,CE) )

    if fn.stateful then
      if fn.inputType:is("Handshake") or fn.inputType:is("HandshakeFramed") then
        sm:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(nil,reset_valid), "ro", nil, reset_valid)  )
      else
        sm:addFunction( S.lambda("reset", S.parameter("r",types.null()), inner:reset(), "ro", nil, S.parameter("reset",types.bool())) )
      end
    end
    
    return sm
  end

  function res.makeTerra() return MT.mapFramed(res,fn,w,h,mixed) end
  
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
  res.sdfInput = SDF{1,1}
  res.sdfOutput = SDF{rate}
  res.name = sanitize("FilterSeq_"..tostring(A))

  if coerce then
    local outTokens = ((W*H)*rate[1])/rate[2]
    err(outTokens==math.ceil(outTokens),"FilterSeq error: number of resulting tokens is non integer ("..tonumber(outTokens)..")")
  end
  
  if terralib~=nil then res.terraModule = MT.filterSeq( res, A, W,H, rate, fifoSize, coerce ) end


  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    -- hack: get broken systolic library to actually wire valid
    local phase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), 42, 1 ) ):CE(true):setReset(0):setInit(0):instantiate("phase") ) 
    
    local sinp = S.parameter("process_input", res.inputType )
    local CE = S.CE("CE")
    local v = S.parameter("process_valid",types.bool())
    
    if coerce then
      
      local invrate = rate[2]/rate[1]
      err(math.floor(invrate)==invrate,"filterSeq: in coerce mode, 1/rate must be integer but is "..tostring(invrate))
      
      local outputCount = (W*H*rate[1])/rate[2]
      err(math.floor(outputCount)==outputCount,"filterSeq: in coerce mode, outputCount must be integer, but is "..tostring(outputCount))
      
      local vstring = [[
module FilterSeqImpl(input wire CLK, input wire process_valid, input wire reset, input wire ce, input wire []]..tostring(res.inputType:verilogBits()-1)..[[:0] inp, output wire []]..tostring(rigel.lower(res.outputType):verilogBits()-1)..[[:0] out);
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
      fns.reset = S.lambda( "reset", S.parameter("resetinp",types.null()), S.null(), "resetout",nil,S.parameter("reset",types.bool()))
    
      local FilterSeqImpl = systolic.module.new("FilterSeqImpl", fns, {}, true,nil, vstring,{process=0,reset=0})

      local inner = systolicModule:add(FilterSeqImpl:instantiate("filterSeqImplInner"))

      systolicModule:addFunction( S.lambda("process", sinp, inner:process(sinp,v), "process_output", {phase:setBy(S.constant(true,types.bool()))}, v, CE ) )
      local resetValid = S.parameter("reset",types.bool())
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:reset(),inner:reset(nil,resetValid)},resetValid) )

    else
      systolicModule:addFunction( S.lambda("process", sinp, sinp, "process_output", {phase:setBy(S.constant(true,types.bool()))}, v, CE ) )
      local resetValid = S.parameter("reset",types.bool())
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:reset()},resetValid) )
    end

    return systolicModule
  end
  
  return rigel.newFunction(res)
end)

-- restrictions: input array of valids must be sorted (valids come first)
-- 'rate' is % of tokens that will survive the filter. (ie 1/2 means half elements will be filtered)
modules.filterSeqPar = memoize(function( A, N, rate )
  err( types.isType(A), "filterSeqPar: input type must be type" )
  err( type(N)=="number", "filterSeqPar: N must be number" )
  err( N>0,"filterSeqPar: N must be > 0")
  err( SDF.isSDF(rate), "filterSeqPar: rate must be SDF rate" )

  local res = {kind="filterSeqPar"}
  res.inputType = types.array2d( types.tuple{A,types.bool()}, N )
  res.outputType = types.RV( A )
  res.sdfInput = SDF{1,1}

  -- we have N elements coming in, but we only write out 1 per cycle, so include that factor
  res.sdfOutput = SDF{rate[1][1]*N,rate[1][2]}
  res.stateful = true
  res.delay = 1
  res.name = J.sanitize("FilterSeqPar_"..tostring(A).."_N"..tostring(N).."_rate"..tostring(rate))

  local fakeV = {A:fakeValue(),false}
  local fakeVA = J.broadcast(fakeV,N)

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local buffer = systolicModule:add( S.module.reg( res.inputType, true, fakeVA, true, fakeVA ):instantiate("buffer") )

    local readyForMore0 = S.eq( S.index(S.index(buffer:get(),0),1), S.constant(false,types.bool()) )
    local readyForMore1 = S.eq( S.index(S.index(buffer:get(),0),1), S.constant(true,types.bool()) )
    local readyForMore2 = S.eq( S.index(S.index(buffer:get(),1),1), S.constant(false,types.bool()) )
    local readyForMore = S.__or(readyForMore0, S.__and(readyForMore1,readyForMore2)):disablePipelining()

    local sinp = S.parameter( "inp", res.inputType )

    -- shift phase
    local sptup = {}
    for i=1,N-1 do
      table.insert( sptup, S.index(buffer:get(),i) )
    end
    table.insert( sptup, S.constant(fakeV, types.tuple{A,types.bool()} ) )
    local shiftPhase = S.tuple(sptup)
    shiftPhase = S.cast(shiftPhase, types.array2d(types.tuple{A,types.bool()},N) )

    ----------
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.index( buffer:get(), 0 ), "process_output", {buffer:set(S.select(readyForMore,sinp,shiftPhase))}, nil, CE) )
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), readyForMore, "ready", {} ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {buffer:reset()},S.parameter("reset",types.bool())) )

    return systolicModule
  end

  res.makeTerra = function() return MT.filterSeqPar(res,A,N) end
  
  return modules.waitOnInput( rigel.newFunction(res) )
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
  local outputType = rigel.V(inputType)
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)
  local innerInputType = types.tuple{xyType, inputType}

  local modname = J.sanitize("DownsampleYSeq_W"..tostring(W).."_H"..tostring(H).."_scale"..tostring(scale).."_"..tostring(A).."_T"..tostring(T))

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

  err( W%scale==0,"downsampleXSeq: NYI - scale ("..tostring(scale)..") does not divide W ("..tostring(W)..")")
  
  local sbits = math.log(scale)/math.log(2)

  local outputT
  if scale>T then outputT = 1
  elseif T%scale==0 then outputT = T/scale
  else err(false,"T%scale~=0 and scale<T") end

  local inputType = types.array2d(A,T)
  local outputType = rigel.V(types.array2d(A,outputT))
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},T)
  local innerInputType = types.tuple{xyType, inputType}

  local tfn, sdfOverride

  if scale>T then -- A[T] to A[1]
    -- tricky: each token contains multiple pixels, any of of which can be valid
    assert(scale%T==0)
    sdfOverride = {{1,scale/T}}
    if terralib~=nil then tfn = MT.downsampleXSeqFn(innerInputType,outputType,scale) end
  else -- scale <= T... for every token, we output 1 token
    sdfOverride = {{1,1}}
    if terralib~=nil then tfn = MT.downsampleXSeqFnShort(innerInputType,outputType,scale,outputT) end
  end

  local modname = J.sanitize("DownsampleXSeq_W"..tostring(W).."_H"..tostring(H).."_"..tostring(A).."_T"..tostring(T).."_scale"..tostring(scale))

  local f = modules.lift( modname, innerInputType, outputType, 0, 
    function(sinp)
      local svalid, sdata
      local sy = S.index(S.index(S.index(sinp,0),0),0)
      if scale>T then -- A[T] to A[1]
        svalid = S.eq(S.cast(S.bitSlice(sy,0,sbits-1),types.uint(sbits)),S.constant(0,types.uint(sbits)))
        sdata = S.index(sinp,1)
--        print("SDATA",sdata.type)
        sdata = S.index(sdata,0)
--        print("SDATA",sdata.type)
        sdata = S.cast(S.tuple{sdata},types.array2d(sdata.type,1))
      else
        svalid = S.constant(true,types.bool())
        local datavar = S.index(sinp,1)
        sdata = J.map(J.range(0,outputT-1), function(i) return S.index(datavar, i*scale) end)
        sdata = S.cast(S.tuple(sdata), types.array2d(A,outputT))
      end
      local res = S.tuple{sdata,svalid}
--      print("DXSRES",res.type,scale,T,sinp.type,sdata.type)
      return res
    end,
    function() return tfn end, nil,
    sdfOverride)

--  print(f)
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
  res.sdfInput, res.sdfOutput = SDF{1,1}, SDF{1,1}
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
  res.sdfInput, res.sdfOutput = SDF{1,1}, SDF{1,1}
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

  return modules.lift( J.sanitize("broadcastWide_"..tostring(A).."_T"..tostring(T).."_scale"..tostring(scale)), ITYPE, OTYPE, 0,
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
  local COUNTER_BITS = 24
  local COUNTER_MAX = math.pow(2,COUNTER_BITS)-1
  err( scale<COUNTER_MAX, "upsampleXSeq: NYI - scale>="..tostring(COUNTER_MAX)..". scale="..tostring(scale))
  err(X==nil, "upsampleXSeq: too many arguments")
  
  if T==1 or T==0 then
    -- special case the EZ case of taking one value and writing it out N times
    local res = {kind="upsampleXSeq",sdfInput=SDF{1,scale}, sdfOutput=SDF{1,1}, stateful=true, A=A, T=T, scale=scale}

    if T==0 then
      res.inputType = A
      res.outputType = rigel.RV(A)
    else
      local ITYPE = types.array2d(A,T)
      res.inputType = ITYPE
      res.outputType = rigel.RV(types.array2d(A,T))
    end
    
    res.delay=0
    res.name = verilogSanitize("UpsampleXSeq_"..tostring(A).."_T_"..tostring(T).."_scale_"..tostring(scale))

    if terralib~=nil then res.terraModule = MT.upsampleXSeq(res,A, T, scale, res.inputType ) end

    -----------------
    function res.makeSystolic()
      local systolicModule = Ssugar.moduleConstructor(res.name)
      local sinp = S.parameter( "inp", res.inputType )

      local sPhase = systolicModule:add( Ssugar.regByConstructor( types.uint(COUNTER_BITS), fpgamodules.sumwrap(types.uint(COUNTER_BITS),scale-1) ):CE(true):setReset(0):instantiate("phase") )
      local reg = systolicModule:add( S.module.reg( res.inputType,true ):instantiate("buffer") )

      local reading = S.eq(sPhase:get(),S.constant(0,types.uint(COUNTER_BITS))):disablePipelining()
      local out = S.select( reading, sinp, reg:get() ) 

      local pipelines = {}
      table.insert(pipelines, reg:set( sinp, reading ) )
      table.insert( pipelines, sPhase:setBy( S.constant(1,types.uint(COUNTER_BITS)) ) )

      local CE = S.CE("CE")
      systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines, nil, CE) )
      systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:reset()},S.parameter("reset",types.bool())) )

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
  err( (W/T)*scale<65536, "upsampleXSeq: NYI - (W/T)*scale>=65536")
  err( W%T==0,"W%T~=0")
  err( J.isPowerOf2(scale), "scale must be power of 2")
  err( J.isPowerOf2(W), "W must be power of 2")

  local res = {kind="upsampleYSeq", sdfInput=SDF{1,scale}, sdfOutput=SDF{1,1}, A=A, T=T, width=W, height=H, scale=scale}
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
    local sPhase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.sumwrap(types.uint(16),(W/T)*scale-1) ):setReset(0):CE(true):instantiate("xpos") )

    local addrbits = math.log(W/T)/math.log(2)
    assert(addrbits==math.floor(addrbits))
    
    local xpos = S.cast(S.bitSlice( sPhase:get(), 0, addrbits-1), types.uint(addrbits))
    
    local phasebits = (math.log(scale)/math.log(2))
    local phase = S.cast(S.bitSlice( sPhase:get(), addrbits, addrbits+phasebits-1 ), types.uint(phasebits))
    
    local sBuffer = systolicModule:add( fpgamodules.bramSDP( true, (A:verilogBits()*W)/8, ITYPE:verilogBits()/8, ITYPE:verilogBits()/8,nil,true ):instantiate("buffer") )
    local reading = S.eq( phase, S.constant(0,types.uint(phasebits)) ):disablePipelining()
    
    local pipelines = {sBuffer:writeAndReturnOriginal(S.tuple{xpos,S.cast(sinp,types.bits(ITYPE:verilogBits()))}, reading), sPhase:setBy( S.constant(1, types.uint(16)) )}
    local out = S.select( reading, sinp, S.cast(sBuffer:read(xpos),ITYPE) ) 
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines, nil, CE) )
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:reset()},S.parameter("reset",types.bool())) )

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
  local res = {kind="interleveSchedule", N=N, period=period, delay=0, inputType=types.null(), outputType=types.uint(8), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=true }
  res.name = "InterleveSchedule_"..N.."_"..period

  if terralib~=nil then res.terraModule = MT.interleveSchedule( N, period ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.uint(8), "interleve schedule phase %d", true):instantiate("printInst") ) end
    
    local inp = S.parameter("process_input", rigel.lower(res.inputType) )
    local phase = systolicModule:add( Ssugar.regByConstructor( types.uint(8), fpgamodules.incIfWrap( types.uint(8), 255, 1 ) ):setInit(0):setReset(0):CE(true):instantiate("interlevePhase") )
    local log2N = math.log(N)/math.log(2)
    
    local CE = S.CE("CE")
    local pipelines = {phase:setBy( S.constant(true,types.bool()))}
    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(phase:get())) end
    
    systolicModule:addFunction( S.lambda("process", inp, S.cast(S.cast(S.bitSlice(phase:get(),period,period+log2N-1),types.uint(log2N)), types.uint(8)), "process_output", pipelines, nil, CE ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:reset()}, S.parameter("reset",types.bool())) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- wtop is the width of the largest (top) pyramid level
modules.pyramidSchedule = memoize(function( depth, wtop, T )
  err(type(depth)=="number", "depth must be number")
  err(type(wtop)=="number", "wtop must be number")
  err(type(T)=="number", "T must be number")
  local res = {kind="pyramidSchedule", wtop=wtop, depth=depth, T=T, delay=0, inputType=types.null(), outputType=types.uint(8), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=true }
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
    local addr = systolicModule:add( Ssugar.regByConstructor( types.uint(8), fpgamodules.incIfWrap( types.uint(8), patternTotal-1, 1 ) ):setInit(0):CE(true):setReset(0):instantiate("patternAddr") )
    local wcnt = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), tokensPerAddr-1, 1 ) ):setInit(0):CE(true):setReset(0):instantiate("wcnt") )
    local patternRam = systolicModule:add(fpgamodules.ram128(types.uint(log2N), pattern):instantiate("patternRam"))

    
    local CE = S.CE("CE")
    local pipelines = {addr:setBy( S.eq(wcnt:get(),S.constant(tokensPerAddr-1,types.uint(16))):disablePipelining() )}
    table.insert(pipelines, wcnt:setBy( S.constant(true,types.bool()) ) )
    
    local out = patternRam:read(addr:get())

    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(S.tuple{addr:get(),wcnt:get(),out})) end
    
    systolicModule:addFunction( S.lambda("process", inp, out, "process_output", pipelines, nil, CE ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {addr:reset(), wcnt:reset()}, S.parameter("reset",types.bool())) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- WARNING: validOut depends on readyDownstream
modules.toHandshakeArrayOneHot = memoize(function( A, inputRates )
  err( types.isType(A), "A must be type" )
  rigel.expectBasic(A)
  err( type(inputRates)=="table", "inputRates must be table")
  assert( SDFRate.isSDFRate(inputRates))

  local res = {kind="toHandshakeArrayOneHot", A=A, inputRates = inputRates}
  res.inputType = rigel.HandshakeArray(A, #inputRates)
  res.outputType = rigel.HandshakeArrayOneHot( A, #inputRates )
  res.sdfInput = SDF(inputRates)
  res.sdfOutput = SDF(inputRates)
  res.stateful = false
  res.name = sanitize("ToHandshakeArrayOneHot_"..tostring(A).."_"..#inputRates)

--  function res:sdfTransfer( I, loc ) 
--    err(#I[1]==#inputRates, "toHandshakeArrayOneHot: incorrect number of input streams. Is "..(#I[1]).." but expected "..(#inputRates) )
--    return I 
--  end
  
  if terralib~=nil then res.terraModule = MT.toHandshakeArrayOneHot( res,A, inputRates ) end

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

    --systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro",nil,S.parameter("reset",types.bool())) )
    
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
  res.inputType = rigel.HandshakeArrayOneHot( A, #inputRates )
  res.outputType = rigel.HandshakeTmuxed( A, #inputRates )
  err( type(Schedule.stateful)=="boolean", "Schedule missing stateful annotation")
  res.stateful = Schedule.stateful
  res.name = sanitize("Serialize_"..tostring(A).."_"..#inputRates)

  local sdfSum = SDFRate.sum(inputRates)

  err( Uniform(sdfSum[1]):eq(sdfSum[2]):assertAlwaysTrue(), "inputRates must sum to 1, but are: "..tostring(SDF(inputRates)).." sum:"..tostring(sdfSum[1]).."/"..tostring(sdfSum[2]))

  -- the output rates had better be the same as the inputs!
  res.sdfInput = SDF(inputRates)
  res.sdfOutput = SDF(inputRates)

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
    
    local stepSchedule = S.__and(inpValid, readyDownstream)
    
    assert( Schedule.systolicModule:getDelay("process")==0 )
    local schedulerCE = readyDownstream
    local nextFIFO = scheduler:process(nil,stepSchedule, schedulerCE)
    
    table.insert( resetPipelines, scheduler:reset(nil, resetValid ) )
    
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

-- tmuxed: should we return a tmuxed type? or just a raw Handshake stream (no ids). Default false
modules.arbitrate = memoize(function(A,inputRates,tmuxed,X)
  err( types.isType(A), "A must be type" )
  err( type(inputRates)=="table", "inputRates must be table")
  assert( SDFRate.isSDFRate(inputRates) )
  rigel.expectBasic(A)
  if tmuxed==nil then tmuxed=false end
  assert(type(tmuxed)=="boolean")
  err(X==nil,"arbitrate: too many arguments")

  local res = {kind="arbitrate", A=A, inputRates=inputRates}
  res.name = sanitize("Arbitrate_"..tostring(A).."_"..#inputRates)
  res.stateful = false

  res.inputType = types.HandshakeArray( A, #inputRates )

  if tmuxed then
    res.outputType = rigel.HandshakeTmuxed( A, #inputRates )
  else
    res.outputType = rigel.Handshake( A )
  end

  local sdfSum = SDFRate.sum(inputRates)

  -- normalize to 1
  local tmp = {}
  for k,v in ipairs(inputRates) do
    table.insert(tmp,SDFRate.fracMultiply(v,{sdfSum[2],sdfSum[1]}))
  end

  local sdfSumTmp = SDFRate.sum(tmp)

  err( Uniform(sdfSumTmp[1]):eq(sdfSumTmp[2]):assertAlwaysTrue(), "inputRates must sum to <= 1, but are: "..tostring(SDF(tmp)).." sum:"..tostring(sdfSumTmp[1]).."/"..tostring(sdfSumTmp[2]))
  
  res.sdfInput = SDF(tmp)
  res.sdfOutput = SDF{1,1}

  if terralib~=nil then res.terraModule = MT.Arbitrate( res, A, inputRates, tmuxed) end
  
  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name):onlyWire(true)

    local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
    
    local inpData = {}
    local inpValid = {}
    
    for i=1,#inputRates do
      table.insert( inpData, S.index(S.index(inp,i-1),0) )
      table.insert( inpValid, S.index(S.index(inp,i-1),1) )
    end

    local readyDownstream = S.parameter( "ready_downstream", types.bool() )

    -- which order do we prefer to read the interfaces in?
    -- ie if multiple are true, which do we prefer to read
    local order = J.range(#inputRates)

    local readyOut = {}
    local dataOut
    for idx,k in ipairs(order) do
      if idx==1 then
        readyOut[k] = inpValid[k]
        dataOut = inpData[k]
      else
        readyOut[k] = S.__and( inpValid[k], S.__not(readyOut[order[idx-1]]) )
        dataOut = S.select(readyOut[k],inpData[k],dataOut)
      end
    end

    local validOut = J.foldt( inpValid, function(a,b) return S.__or(a,b) end, "X" )

    -- if nothing is valid, set all readys to true (or else we will block progress)
    for k,v in ipairs(readyOut) do readyOut[k] = S.__and(S.__or(readyOut[k],S.__not(validOut)),readyDownstream) end

    local pipelines={}
    
    systolicModule:addFunction( S.lambda("process", inp, S.tuple{dataOut,validOut} , "process_output", pipelines) )

    systolicModule:addFunction( S.lambda("ready", readyDownstream, S.cast(S.tuple(readyOut),types.array2d(types.bool(),#inputRates)), "ready" ) )
    
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
  res.outputType = rigel.HandshakeArray(A, #rates)
  res.stateful = false
  res.name = sanitize("Demux_"..tostring(A).."_"..#rates)

  local sdfSum = SDFRate.sum(rates)
  err(  SDFRate.fracEq(sdfSum,{1,1}), "rates must sum to 1")

  res.sdfInput = SDF(rates)
  res.sdfOutput = SDF(rates)

  if terralib~=nil then res.terraModule = MT.demux(res,A,rates) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name):onlyWire(true)

    local printInst
    if DARKROOM_VERBOSE then 
      printInst = systolicModule:add( S.module.print( types.tuple( J.concat({types.uint(8)},J.broadcast(types.bool(),#rates+1))), "Demux IV %d readyDownstream ["..table.concat(J.broadcast("%d",#rates),",").."] ready %d"):instantiate("printInst") ) 
    end
    
    local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
    local inpData = S.index(inp,0)
    local inpValid = S.index(inp,1)  -- uint8
    local readyDownstream = S.parameter( "ready_downstream", types.array2d( types.bool(), #rates ) )
    
    local pipelines = {}
    
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

  local sdfSum = SDFRate.sum(rates) --rates[1][1]/rates[1][2]
  --for i=2,#rates do sdfSum = sdfSum + (rates[i][1]/rates[i][2]) end
  err( Uniform(sdfSum[1]):eq(sdfSum[2]):assertAlwaysTrue(), "inputRates must sum to 1, but are: "..tostring(SDF(rates)).." sum:"..tostring(sdfSum[1]).."/"..tostring(sdfSum[2]))
  
  res.sdfInput = SDF(rates)
  res.sdfOutput = SDF{1,1}
  res.name = sanitize("FlattenStreams_"..tostring(A).."_"..#rates)

  if terralib~=nil then res.terraModule = MT.flattenStreams(res,A,rates) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name):onlyWire(true)

    --local resetValid = S.parameter("reset_valid", types.bool() )
    
    local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
    local inpData = S.index(inp,0)
    local inpValid = S.index(inp,1)
    local readyDownstream = S.parameter( "ready_downstream", types.bool() )
    
    local pipelines = {}
    --local resetPipelines = {}
    
    systolicModule:addFunction( S.lambda("process", inp, S.tuple{inpData,S.__not(S.eq(inpValid,S.constant(#rates,types.uint(8))))} , "process_output", pipelines ) )
    --systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, resetValid ) )
    
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
modules.broadcastStream = memoize(function(A,N,framed,framedMixed,framedDims,X)
  err( types.isType(A), "broadcastStream: A must be type")
  rigel.expectBasic(A)
  err( type(N)=="number", "broadcastStream: N must be number")
  if framed==nil then framed=false end
  err( type(framed)=="boolean","broadcastStream: framed must be boolean")
  err( framed==false or type(framedMixed)=="boolean", "broadcastStream: frameMixed should be boolean")
  assert(X==nil)

  local res = {kind="broadcastStream", A=A, N=N,  stateful=false}

  if A==types.null() then
    res.inputType = rigel.HandshakeTrigger
    res.outputType = rigel.HandshakeTriggerArray(N)
  elseif framed then
    res.inputType = types.HandshakeFramed(A,framedMixed,framedDims)
    res.outputType = types.HandshakeArrayFramed( A, framedMixed, framedDims, N )
  else
    res.inputType = rigel.Handshake(A)
    res.outputType = rigel.HandshakeArray(A, N)
  end

  res.sdfInput = SDF{1,1}
  res.sdfOutput = SDF(J.broadcast({1,1},N))
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
    local inpData, inpValid

    if A==types.null() then -- HandshakeTrigger
      inpValid = inp
    else
      inpData = S.index(inp,0)
      inpValid = S.index(inp,1)
    end

    local readyDownstream = S.parameter( "ready_downstream", types.array2d(types.bool(),N) )
    local readyDownstreamList = J.map(J.range(N), function(i) return S.index(readyDownstream,i-1) end )
    
    local allReady = J.foldt( readyDownstreamList, function(a,b) return S.__and(a,b) end, "X" )
    local validOut = S.__and(inpValid,allReady)

    local out

    if inpData==nil then
      -- HandshakeTrigger
      out  = S.tuple( J.broadcast(validOut, N))
      out = S.cast(out, types.array2d(types.bool(),N) )
    else
      out  = S.tuple( J.broadcast(S.tuple{inpData, validOut}, N))
    end
    out = S.cast(out, rigel.lower(res.outputType) )
    
    local pipelines = {}
    
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple( J.concat( J.concat({inpValid}, readyDownstreamList),{allReady}) ) ) ) end
    
    systolicModule:addFunction( S.lambda("process", inp, out, "process_output", pipelines ) )

    --local resetValid = S.parameter("reset_valid", types.bool() )
    --systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", nil, resetValid ) )

    systolicModule:addFunction( S.lambda("ready", readyDownstream, allReady, "ready" ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- output type: {uint16,uint16}[T]
-- asArray: return output as u16[2][T] instead
modules.posSeq = memoize(function( W_orig, H, T, bits, framed, asArray, X )
  if bits==nil then bits=16 end
  err( type(bits)=="number", "posSeq: bits should be number, but is: "..tostring(bits))
  local W = Uniform(W_orig)
  err(type(H)=="number","posSeq: H must be number")
  err(type(T)=="number","posSeq: T must be number")
  err( W:gt(0):assertAlwaysTrue(), "posSeq: W must be >0, but is: "..tostring(W));
  err(H>0, "posSeq: H must be >0");
  err(T>=0, "posSeq: T must be >=0");
  if framed==nil then framed=false end
  err( type(framed)=="boolean", "posSeq: framed should be boolean")
  if asArray==nil then asArray=false end
  err( type(asArray)=="boolean", "posSeq: asArray should be boolean")
  err(X==nil, "posSeq: too many arguments")

  local res = {kind="posSeq", T=T, W=W, H=H }
  res.inputType = types.null()

  local sizeType = types.tuple({types.uint(bits),types.uint(bits)})
  if asArray then sizeType = types.array2d(types.uint(bits),2) end
  if T==0 then
    res.outputType = sizeType
    if framed then res.outputType = types.StaticFramed(res.outputType,false,{{W,H}}) end
  else
    res.outputType = types.array2d(sizeType,T)
    if framed then res.outputType = types.StaticFramed(res.outputType,true,{{W,H}}) end
  end
  res.stateful = true
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
  res.delay = 0
  res.name = sanitize("PosSeq_W"..tostring(W_orig).."_H"..H.."_T"..T.."_bits"..tostring(bits))

  if terralib~=nil then res.terraModule = MT.posSeq(res,W,H,T,asArray) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local posX = systolicModule:add( Ssugar.regByConstructor( types.uint(bits), fpgamodules.incIfWrap( types.uint(bits), W-math.max(T,1), math.max(T,1) ) ):setInit(0):setReset(0):CE(true):instantiate("posX_posSeq") )
    local posY = systolicModule:add( Ssugar.regByConstructor( types.uint(bits), fpgamodules.incIfWrap( types.uint(bits), H-1 ) ):setInit(0):setReset(0):CE(true):instantiate("posY_posSeq") )

    local printInst

    if DARKROOM_VERBOSE then 
      printInst = systolicModule:add( S.module.print( types.tuple{types.uint(bits),types.uint(bits)}, "x %d y %d", true):instantiate("printInst") ) 
    end
    
    local incY = S.eq( posX:get(), (W-math.max(T,1)):toSystolic(types.uint(bits))  ):disablePipelining()
    
    local out = {S.tuple{posX:get(),posY:get()}}
    for i=1,T-1 do
      table.insert(out, S.tuple{posX:get()+S.constant(i,types.uint(bits)),posY:get()})
    end
    
    local CE = S.CE("CE")
    local pipelines = {}
    table.insert( pipelines, posX:setBy( S.constant(true, types.bool() ) ) )
    table.insert( pipelines, posY:setBy( incY ) )
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple{posX:get(),posY:get()}) ) end

    local finout
    if T==0 then
      finout = out[1]
      if asArray then
        finout = S.cast(finout,types.array2d(types.uint(bits),2))
      end
    else
      finout = S.cast(S.tuple(out),types.array2d(types.tuple{types.uint(bits),types.uint(bits)},T))
      assert(asArray==false) -- NYI
    end
    
    systolicModule:addFunction( S.lambda("process", S.parameter("pinp",types.null()), finout, "process_output", pipelines, nil, CE ) )

    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {posX:reset(), posY:reset()}, S.parameter("reset",types.bool())) )

    systolicModule:complete()

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- this takes a pure function f : {{int32,int32}[T],inputType} -> outputType
-- and drives the first tuple with (x,y) coord
-- returns a function with type Stateful(inputType)->Stateful(outputType)
-- sdfOverride: we can use this to define stateful->StatefulV interfaces etc, so we may want to override the default SDF rate
modules.liftXYSeq = memoize(function( name, generatorStr, f, W_orig, H, T, bits, X )
  if bits==nil then bits=16 end
  err( type(bits)=="number", "liftXYSeq: bits must be number or nil")

  err( type(name)=="string", "liftXYSeq: name must be string" )
  err( type(generatorStr)=="string", "liftXYSeq: generatorStr must be string" )
  err( rigel.isFunction(f), "liftXYSeq: f must be function")
  --err( type(W)=="number", "liftXYSeq: W must be number")
  local W = Uniform(W_orig)
  err( type(H)=="number", "liftXYSeq: H must be number")
  err( type(T)=="number", "liftXYSeq: T must be number")
  err( X==nil, "liftXYSeq: too many arguments")

  local inputType = f.inputType.list[2]
  local inp = rigel.input( inputType )
  local p = rigel.apply("p", modules.posSeq(W,H,T,bits) )
  local out = rigel.apply("m", f, rigel.concat("ptup", {p,inp}) )
  return modules.lambda( "liftXYSeq_"..name.."_W"..tostring(W_orig), inp, out,nil,generatorStr )
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
modules.cropSeq = memoize(function( A, W_orig, H, V, L, R_orig, B, Top, framed, X )

  local BITS = 32

  err( types.isType(A), "cropSeq: type must be rigel type ")
  err( rigel.isBasic(A),"cropSeq: expects basic type, but is: "..tostring(A))
  local W = Uniform(W_orig)
  err( W:gt(0):assertAlwaysTrue(),"cropSeq: W must be >=0, but is: "..tostring(W) )
  --err( type(W)=="number", "cropSeq: W must be number"); err(W>=0, "cropSeq: W must be >=0")
  err( type(H)=="number", "cropSeq: H must be number"); err(H>=0, "cropSeq: H must be >=0")
  err( type(V)=="number", "cropSeq: V must be number"); err(V>=0, "cropSeq: V must be >=0")
  err( type(L)=="number", "cropSeq: L must be number"); err(L>=0, "cropSeq: L must be >=0")
  --err( type(R)=="number", "cropSeq: R must be number"); err(R>=0, "cropSeq: R must be >=0")
  local R = Uniform(R_orig)
  err( type(B)=="number", "cropSeq: B must be number"); err(B>=0, "cropSeq: B must be >=0")
  err( type(Top)=="number", "cropSeq: Top must be number"); err(Top>=0, "cropSeq: Top must be >=0")
  if framed==nil then framed=false end
  err( type(framed)=="boolean", "cropSeq: framed must be boolean")

  err( L>=0, "cropSeq, L must be >=0")
  err( R:ge(0):assertAlwaysTrue(), "cropSeq, R must be >= 0, but is: "..tostring(R))
  err( V==0 or (W%V):eq(0):assertAlwaysTrue(), "cropSeq, W%V must be 0. W="..tostring(W)..", V="..tostring(V))
  err( V==0 or L%V==0, "cropSeq, L%V must be 0. L="..tostring(L).." V="..tostring(V))
  err( V==0 or (R%V):eq(0):assertAlwaysTrue(), "cropSeq, R%V must be 0, R="..tostring(R)..", V="..tostring(V))
  err( V==0 or ((W-L-R)%V):eq(0):assertAlwaysTrue(), "cropSeq, (W-L-R)%V must be 0")
  err( X==nil, "cropSeq: too many arguments" )


  --err( W:lt(math.pow(2,BITS)-1):assertAlwaysTrue(), "cropSeq: width too large!")
  err( H<math.pow(2,BITS), "cropSeq: height too large!")
  
  local inputType
  if V==0 then
    inputType = A
  else
    inputType = types.array2d(A,V)
  end
  local outputType = rigel.V(inputType)
  local xyType = types.array2d(types.tuple{types.uint(BITS),types.uint(BITS)},math.max(V,1))
  local innerInputType = types.tuple{xyType, inputType}

  local modname = J.verilogSanitize("CropSeq_"..tostring(A).."_W"..tostring(W_orig).."_H"..tostring(H).."_V"..tostring(V).."_L"..tostring(L).."_R"..tostring(R_orig).."_B"..tostring(B).."_Top"..tostring(Top))

  local f = modules.lift( modname, innerInputType, outputType, 0, 
    function(sinp)
      local sdata = S.index(sinp,1)
      local sx, sy = S.index(S.index(S.index(sinp,0),0),0), S.index(S.index(S.index(sinp,0),0),1)
      local sL,sB = S.constant(L,types.uint(BITS)),S.constant(B,types.uint(BITS))
      local sWmR,sHmTop = (W-R):toSystolic(types.uint(BITS)),S.constant(H-Top,types.uint(BITS))
      
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
      return MT.cropSeqFn( innerInputType, outputType, A, W, H, V, L, R, B, Top ) 
    end, nil,
    {{((W-L-R)*(H-B-Top))/math.max(1,V),(W*H)/math.max(1,V)}})

  local res = modules.liftXYSeq( modname, "rigel.cropSeq", f, W, H, math.max(1,V), BITS )

  -- HACK
  if framed then
    print("CROPHACK", res.inputType, res.outputType,W,H)
    --local idim = res.inputType:dims()
    --idim[#idim]={W,H}
    res.inputType = res.inputType:addDim(W,H,V>0) --types.StaticFramed(res.inputType,idim)
    --local odim = rigel.extractData(res.outputType):dims()
    --odim[#odim]={W-L-R,H-B-Top}
    res.outputType = types.VFramed(res.outputType.params.A,V>0,{{W-L-R,H-B-Top}})
    print("CROPHACK", res.inputType, res.outputType)
  end
  
  return res
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
  res.sdfInput, res.sdfOutput = SDF{1,1}, SDF{1,1}
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
modules.padSeq = memoize(function( A, W, H, T, L, R_orig, B, Top, Value, X )
  err( types.isType(A), "A must be a type")
  
  err( A~=nil, "padSeq A==nil" )
  err( W~=nil, "padSeq W==nil" )
  err( H~=nil, "padSeq H==nil" )
  err( T~=nil, "padSeq T==nil" )
  err( L~=nil, "padSeq L==nil" )
  err( R_orig~=nil, "padSeq R==nil" )
  err( B~=nil, "padSeq B==nil" )
  err( Top~=nil, "padSeq Top==nil" )
  err( Value~=nil, "padSeq Value==nil" )
  err( X==nil, "padSeq: too many arguments" )
  
  J.map({W=W,H=H,T=T,L=L,B=B,Top=Top},function(n,k)
        err(type(n)=="number","PadSeq expected number for argument "..k.." but is "..tostring(n)); 
        err(n==math.floor(n),"PadSeq non-integer argument "..k..":"..n); 
        err(n>=0,"n<0") end)

  local R = Uniform(R_orig)
  
  A:checkLuaValue(Value)
  err(T>=1, "padSeq, T<1")

  err( W%T==0, "padSeq, W%T~=0, W="..tostring(W).." T="..tostring(T))
  err( L==0 or (L>=T and L%T==0), "padSeq, L<T or L%T~=0 (L="..tostring(L)..",T="..tostring(T)..")")
  err( (R:eq(0):Or( R:ge(T):And( (R%T):eq(0)))):assertAlwaysTrue(), "padSeq, R<T or R%T~=0") -- R==0 or (R>=T and R%T==0)
  err( Uniform((W+L+R)%T):eq(0):assertAlwaysTrue(), "padSeq, (W+L+R)%T~=0") -- (W+L+R)%T==0

  local res = {kind="padSeq", type=A, T=T, L=L, R=R, B=B, Top=Top, value=Value, width=W, height=H}
  res.inputType = types.array2d(A,T)
  res.outputType = rigel.RV(types.array2d(A,T))
  res.stateful = true
  res.sdfInput, res.sdfOutput = SDF{ (W*H)/T, ((Uniform(W)+Uniform(L)+R)*(H+B+Top))/T}, SDF{1,1}
  res.delay=0
  res.name = verilogSanitize("PadSeq_"..tostring(A).."_W"..W.."_H"..H.."_L"..L.."_R"..tostring(R_orig).."_B"..B.."_Top"..Top.."_T"..T.."_Value"..tostring(Value))

  if terralib~=nil then res.terraModule = MT.padSeq( res, A, W, H, T, L, R, B, Top, Value ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local posX = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap( types.uint(32), W+L+R-T, T ) ):CE(true):setInit(0):setReset(0):instantiate("posX_padSeq") ) 
    local posY = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), H+Top+B-1) ):CE(true):setInit(0):setReset(0):instantiate("posY_padSeq") ) 
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

    local incY = S.eq( posX:get(), Uniform(W+L+R-T):toSystolic(types.uint(32))  ):disablePipelining()
    pipelines[1] = posY:setBy( incY )
    pipelines[2] = posX:setBy( S.constant(true,types.bool()) )

    local ValueBroadcast = S.cast( S.tuple( J.broadcast(S.constant(Value,A),T)) ,types.array2d(A,T))
    local ConstTrue = S.constant(true,types.bool())

    local out = S.select( readybit, pinp, ValueBroadcast )
    
    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process( S.tuple{ posX:get(), posY:get(), readybit } ) ) end
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", pinp, S.tuple{out,ConstTrue}, "process_output", pipelines, pvalid, CE) )
    
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {posX:reset(), posY:reset()},S.parameter("reset",types.bool())) )
    
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), readybit, "ready", {} ) )

    return systolicModule
  end

  return modules.waitOnInput(rigel.newFunction(res))
                          end)


--StatefulRV. Takes A[inputRate,H] in, and buffers to produce A[outputRate,H]
modules.changeRate = memoize(function(A, H, inputRate, outputRate, framed, framedW, framedH, X)
  err( types.isType(A), "changeRate: A should be a type")
  err( type(H)=="number", "changeRate: H should be number")
  err( type(inputRate)=="number", "changeRate: inputRate should be number")
  err( inputRate>0, "changeRate: inputRate must be >0")
  err( inputRate==math.floor(inputRate), "changeRate: inputRate should be integer")
  err( type(outputRate)=="number", "changeRate: outputRate should be number, but is: "..tostring(outputRate))
  err( outputRate==math.floor(outputRate), "changeRate: outputRate should be integer, but is: "..tostring(outputRate))
  if framed==nil then framed=false end
  err( type(framed)=="boolean","changeRate: framed must be boolean")
  err( X==nil, "changeRate: too many arguments")

  local maxRate = math.max(inputRate,outputRate)

  err( maxRate % inputRate == 0, "maxRate ("..tostring(maxRate)..") % inputRate ("..tostring(inputRate)..") ~= 0")
  err( maxRate % outputRate == 0, "maxRate % outputRate ~=0")
  rigel.expectBasic(A)

  local inputCount = maxRate/inputRate
  local outputCount = maxRate/outputRate

  local res = {kind="changeRate", type=A, H=H, inputRate=inputRate, outputRate=outputRate}
  res.inputType = types.array2d(A,inputRate,H)
  res.outputType = rigel.RV(types.array2d(A,outputRate,H))

  if framed and inputRate<outputRate then
    assert(H==1) -- makes no sense
    assert(outputRate==framedW*framedH)
    res.inputType = res.inputType:addDim(framedW,framedH,true)
  elseif framed and inputRate>outputRate then
    assert(H==1) -- makes no sense
    assert(inputRate==framedW*framedH)
    print("SER",res.inputType,res.outputType,framedW,framedH)
    res.outputType = res.outputType:addDim(framedW,framedH,true)
  end
  
  res.stateful = true
  res.delay = 0
  res.name = J.verilogSanitize("ChangeRate_"..tostring(A).."_from"..inputRate.."_to"..outputRate.."_H"..H.."_framed"..tostring(framed))

  if inputRate>outputRate then -- 8 to 4
    res.sdfInput, res.sdfOutput = SDF{outputRate,inputRate},SDF{1,1}
  else -- 4 to 8
    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{inputRate,outputRate}
  end

  function res.makeSystolic()
    local systolicModule= Ssugar.moduleConstructor(res.name)

    local svalid = S.parameter("process_valid", types.bool() )
    local rvalid = S.parameter("reset", types.bool() )
    local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
    
    if inputRate>outputRate then
      
      -- 8 to 4
      local shifterReads = {}
      for i=0,outputCount-1 do
        table.insert(shifterReads, S.slice( pinp, i*outputRate, (i+1)*outputRate-1, 0, H-1 ) )
      end
      local out, pipelines, resetPipelines, ready = fpgamodules.addShifterSimple( systolicModule, shifterReads, DARKROOM_VERBOSE )
      
      local CE = S.CE("CE")
      systolicModule:addFunction( S.lambda("process", pinp, S.tuple{ out, S.constant(true,types.bool()) }, "process_output", pipelines, svalid, CE) )
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, rvalid ) )
      systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), ready, "ready", {} ) )
      
    else -- inputRate <= outputRate. 4 to 8
      assert(H==1) -- NYI
      
      local sPhase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), inputCount-1) ):CE(true):setReset(0):instantiate("phase_changerateup") )
      local printInst
      if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(16),types.array2d(A,outputRate)}, "phase %d buffer %h", true ):instantiate("printInst") ) end
      local ConstTrue = S.constant(true,types.bool())
      local CE = S.CE("CE")
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", { sPhase:reset() }, rvalid ) )
      
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

modules.linebuffer = memoize(function( A, w, h, T, ymin, framed, X )
  assert(w>0); assert(h>0);
  assert(ymin<=0)
  err(X==nil,"linebuffer: too many args!")
  err( framed==nil or type(framed)=="boolean", "modules.linebuffer: framed must be bool or nil")
  if framed==nil then framed=false end
  
  -- if W%T~=0, then we would potentially have to do two reads on wraparound. So don't allow this case.
  err( w%T==0, "Linebuffer error, W%T~=0 , W="..tostring(w).." T="..tostring(T))

  local res = {kind="linebuffer", type=A, T=T, w=w, h=h, ymin=ymin }
  rigel.expectBasic(A)
  res.inputType = types.array2d(A,T)
  res.outputType = types.array2d(A,T,-ymin+1)

  if framed then
    res.inputType = types.StaticFramed(res.inputType,true,{{w,h}})
    -- this is strange for a reason: inner loop is no longer a serialized flat array, so size must change
    res.outputType = types.StaticFramed(res.outputType,false,{{w/T,h}})
  end
  
  res.stateful = true
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
  res.delay = 0
  res.name = sanitize("linebuffer_w"..w.."_h"..h.."_T"..T.."_ymin"..ymin.."_A"..tostring(A).."_framed"..tostring(framed))

  if terralib~=nil then res.terraModule = MT.linebuffer(res, A, w, h, T, ymin) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local addr = systolicModule:add( fpgamodules.regBy( types.uint(16), fpgamodules.incIfWrap( types.uint(16), (w/T)-1), true, nil, 0 ):instantiate("addr") )
    
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

    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {addr:reset()},S.parameter("reset",types.bool())) )
    
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
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
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
    
    local currentX = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), imageW-1, 1 ) ):CE(true):setInit(0):setReset(0):instantiate("currentX") )
    table.insert( pipelines, currentX:setBy( S.constant(true,types.bool()) ) )
    table.insert( resetPipelines, currentX:reset() )
    
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
        valid=S.parameter("reset",types.bool())} )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- xmin, ymin are inclusive
modules.SSR = memoize(function( A, T, xmin, ymin )
  J.map({T,xmin,ymin}, function(i) assert(type(i)=="number") end)
  err( ymin<=0, "modules.SSR: ymin>0")
  err( xmin<=0, "module.SSR: xmin>0")
  err( T>0, "modules.SSR: T<=0")
  local res = {kind="SSR", type=A, T=T, xmin=xmin, ymin=ymin }
  res.inputType = types.array2d(A,T,-ymin+1)
  res.outputType = types.array2d(A,T-xmin,-ymin+1)
  res.stateful = true
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
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
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", nil, S.parameter("reset",types.bool()) ) )

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

  res.sdfInput, res.sdfOutput = SDF{1,1/T},SDF{1,1}
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
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", shifterResetPipelines,S.parameter("reset",types.bool())) )
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
modules.makeHandshake = memoize(function( f, tmuxRates, nilhandshake, X )
  assert( rigel.isFunction(f) )
  if nilhandshake==nil then nilhandshake=false end
  err( type(nilhandshake)=="boolean", "makeHandshake: nilhandshake must be nil or boolean")
  assert( X==nil )
  
  local res = { kind="makeHandshake", fn = f, tmuxRates = tmuxRates }

  if tmuxRates~=nil then
    rigel.expectBasic(f.inputType)
    rigel.expectBasic(f.outputType)
    res.inputType = rigel.HandshakeTmuxed( f.inputType, #tmuxRates )
    res.outputType = rigel.HandshakeTmuxed (f.outputType, #tmuxRates )
    assert( SDFRate.isSDFRate(tmuxRates) )
    res.sdfInput, res.sdfOutput = SDF(tmuxRates), SDF(tmuxRates)
  else
    err( types.isBasic(f.inputType) or f.inputType:is("StaticFramed"),"makeHandshake: fn input type should be basic or StaticFramed")
    err( types.isBasic(f.outputType) or f.outputType:is("StaticFramed"),"makeHandshake: fn output type should be basic or StaticFramed")

    if f.inputType==types.null() and nilhandshake==true then
      res.inputType = rigel.HandshakeTrigger
    elseif f.inputType~=types.null() and f.inputType:is("StaticFramed") then
      res.inputType = types.HandshakeFramed( f.inputType.params.A, f.inputType.params.mixed, f.inputType.params.dims )
    elseif f.inputType~=types.null() then
      res.inputType = rigel.Handshake(f.inputType)
    else
      res.inputType = types.null()
    end

    if f.outputType==types.null() and nilhandshake==true then
      res.outputType = rigel.HandshakeTrigger
    elseif f.outputType~=types.null() and f.outputType:is("StaticFramed") then
      res.outputType = types.HandshakeFramed( f.outputType.params.A, f.outputType.params.mixed, f.outputType.params.dims )
    elseif f.outputType~=types.null() then
      res.outputType = rigel.Handshake(f.outputType)
    else
      res.outputType = types.null()
    end

    J.err( rigel.SDF==false or f.sdfInput~=nil, "makeHandshake: fn is missing sdfInput? "..f.name )
    J.err( rigel.SDF==false or f.sdfOutput~=nil, "makeHandshake: fn is missing sdfOutput? "..f.name )
    
    J.err( rigel.SDF==false or #f.sdfInput==1, "makeHandshake expects SDF input rate of 1")
    J.err( rigel.SDF==false or f.sdfInput[1][1]:eq(f.sdfInput[1][2]):assertAlwaysTrue(), "makeHandshake expects SDF input rate of 1, but is: "..tostring(f.sdfInput))
    J.err( rigel.SDF==false or #f.sdfOutput==1, "makeHandshake expects SDF output rate of 1")
    J.err( rigel.SDF==false or f.sdfOutput[1][1]:eq(f.sdfOutput[1][2]):assertAlwaysTrue(), "makeHandshake expects SDF output rate of 1, but is: "..tostring(f.sdfOutput))

    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
  end

  res.stateful = true -- for the shift register of valid bits
  res.name = J.sanitize("MakeHandshake_HST_"..tostring(nilhandshake).."_"..f.name)

  res.globals={}
  for k,_ in pairs(f.globals) do res.globals[k]=1 end
  
  if terralib~=nil then res.makeTerra = function() return MT.makeHandshake(res, f, tmuxRates, nilhandshake ) end end

  function res.makeSystolic()
    -- We _NEED_ to set an initial value for the shift register output (invalid), or else stuff downstream can get strange values before the pipe is primed
    local systolicModule = Ssugar.moduleConstructor(res.name):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

--    local SC = {}
    for k,_ in pairs(f.globals) do
      systolicModule:addSideChannel(k.systolicValue)
--      SC[k.systolicValue]=k.systolicValue
    end
    
    local outputCount
    if DARKROOM_VERBOSE then outputCount = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIf() ):CE(true):instantiate("outputCount") ) end
    
    local SRdefault = false
    if tmuxRates~=nil then SRdefault = #tmuxRates end
    local SR = systolicModule:add( fpgamodules.shiftRegister( rigel.extractValid(res.inputType), f.systolicModule:getDelay("process"), SRdefault, true ):instantiate( J.sanitize("validBitDelay_"..f.systolicModule.name) ) )
    local inner = systolicModule:add(f.systolicModule:instantiate("inner"))
    local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local rst = S.parameter("reset",types.bool())
    
    local pipelines = {}

    local pready = S.parameter("ready_downstream", types.bool())
    local CE = pready
    
    local outvalid
    local out
    if f.inputType==types.null() and f.outputType==types.null() and nilhandshake==true then
      assert(false) -- NYI
    elseif f.inputType==types.null() and nilhandshake==true then
      outvalid = SR:pushPop( pinp, S.constant(true,types.bool()), CE)
      out = S.tuple({inner:process(nil,pinp,CE), outvalid})
    elseif f.inputType==types.null() and nilhandshake==false then
      outvalid = SR:pushPop(S.constant(true,types.bool()), S.constant(true,types.bool()), CE)
      --table.insert(pipelines,inner:process(nil,pinp,CE))
      out = S.tuple({inner:process(nil,S.constant(true,types.bool()),CE), outvalid})
    elseif f.outputType==types.null() and nilhandshake==true then
      outvalid = SR:pushPop(S.index(pinp,1), S.constant(true,types.bool()), CE)
      out = outvalid
      table.insert(pipelines,inner:process(S.index(pinp,0),S.index(pinp,1), CE))
    elseif f.outputType==types.null() and nilhandshake==false then
      table.insert(pipelines,inner:process(S.index(pinp,0),S.index(pinp,1), CE))
    else
      outvalid = SR:pushPop(S.index(pinp,1), S.constant(true,types.bool()), CE)
      out = S.tuple({inner:process(S.index(pinp,0),S.index(pinp,1), CE), outvalid})
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
      if DARKROOM_VERBOSE then table.insert(pipelines,  outputCount:setBy(outvalid, S.constant(true,types.bool()), CE) ) end
    end
    
    systolicModule:addFunction( S.lambda("process", pinp, out, "process_output", pipelines) ) 
    
    local resetOutput
    if f.stateful then resetOutput = inner:reset(nil,rst) end
    
    local resetPipelines = {}
    table.insert( resetPipelines, SR:reset(nil,rst) )
    if DARKROOM_VERBOSE then table.insert( resetPipelines, outputCount:set(S.constant(0,types.uint(16)),rst,CE) ) end
    
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), resetOutput, "reset_out", resetPipelines,rst) )
    
    if res.inputType==types.null() and nilhandshake==false then
      systolicModule:addFunction( S.lambda("ready", pready, nil, "ready" ) )
    elseif res.outputType==types.null() and nilhandshake==false then
      systolicModule:addFunction( S.lambda("ready", S.parameter("r",types.null()), S.constant(true,types.bool()), "ready" ) )
    else
      systolicModule:addFunction( S.lambda("ready", pready, pready, "ready" ) )
    end

    return systolicModule
  end

  local out = rigel.newFunction(res)
  return out
end)


-- promotes FIFO systolic module to handshake type.
-- In the future, we'd like to make our type system powerful enough to be able to do this...
local function promoteFifo(systolicModule)
  
end

-- nostall: unsafe -> ready always set to true
-- W,H,T: used for debugging (calculating last cycle)
-- csimOnly: hack for large fifos - don't actually allocate hardware
-- VRLoad: make the load function be HandshakeVR
modules.fifo = memoize(function( A, size, nostall, W, H, T, csimOnly, VRLoad, X )
  rigel.expectBasic(A)
  err( type(size)=="number", "fifo: size must be number")
  err( size >0,"fifo: size must be >0")
  err(nostall==nil or type(nostall)=="boolean", "fifo: nostall should be nil or boolean")
  err(W==nil or type(W)=="number", "W should be nil or number")
  err(H==nil or type(H)=="number", "H should be nil or number")
  err(T==nil or type(T)=="number", "T should be nil or number")
  assert(csimOnly==nil or type(csimOnly)=="boolean")
  if VRLoad==nil then VRLoad=false end
  err( type(VRLoad)=="boolean","fifo: VRLoad should be boolean")
  
  assert(X==nil)

  if size==1 and csimOnly==false then
    local name = J.sanitize("OneElementFIFO_"..tostring(A))
    local vstr=[[module ]]..name..[[(input wire CLK, output wire []]..tostring(A:verilogBits())..[[:0] load_output, input wire store_reset, output wire store_ready, input wire load_ready, input wire load_reset, input wire []]..tostring(A:verilogBits())..[[:0] store_input);
  parameter INSTANCE_NAME="INST";
  reg hasItem;
  reg []]..tostring(A:verilogBits()-1)..[[:0] dataBuffer;

  wire store_valid;
  assign store_valid = store_input[]]..tostring(A:verilogBits())..[[];

  always @(posedge CLK) begin
    if (store_reset || load_reset ) begin
      hasItem <= 1'b0;
    end else begin
      if (store_valid && (load_ready || hasItem==1'b0) ) begin
        // input is valid and we can accept it
        hasItem <= 1'b1;
        dataBuffer <= store_input[]]..tostring(A:verilogBits()-1)..[[:0];
      end else if (load_ready) begin
        // buffer is being emptied
        hasItem <= 1'b0;
      end
    end
  end

  assign load_output = {hasItem,dataBuffer};
  assign store_ready = (hasItem==1'b0)||load_ready;
endmodule

]]

    local outputType = types.Handshake(A)
    if VRLoad then
      outputType=types.HandshakeVR(A)
    end
    
    local mod =  modules.liftVerilog(name, types.Handshake(A), outputType, vstr, nil,nil,nil,nil,nil, true )
    mod.registered = true
    if terralib~=nil then mod.terraModule = MT.fifo(mod,A,2,nostall,W,H,T,csimOnly) end
return mod
  end
  
  local res = {kind="fifo", inputType=rigel.Handshake(A),  registered=true, sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=true}

  if VRLoad then
    res.outputType = rigel.HandshakeVR(A)
  else
    res.outputType = rigel.Handshake(A)
  end
  
  if A==types.null() then
    res.inputType=rigel.HandshakeTrigger
    res.outputType=rigel.HandshakeTrigger
  else
    assert(A:verilogBits()>0)
  end
  
  if terralib~=nil then res.terraModule = MT.fifo(res,A, size, nostall, W, H, T, csimOnly) end

  local bytes = (size*A:verilogBits())/8

  res.name = sanitize("fifo_SIZE"..size.."_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_BYTES"..tostring(bytes).."_nostall"..tostring(nostall).."_csimOnly"..tostring(csimOnly))

  local fifo
  if csimOnly then
    function res.makeSystolic()
      return fpgamodules.fifonoop(A)
    end
    
    --res.stateful = false
  else
    function res.makeSystolic()
      local systolicModule = Ssugar.moduleConstructor(res.name)

      local fifo = systolicModule:add( fpgamodules.fifo(A,size,DARKROOM_VERBOSE,nostall):instantiate("FIFO") )

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
      storeReset:addPipeline(fifo:pushBackReset())

      --------------
      -- basic -> V
      local load = systolicModule:addFunction( Ssugar.lambdaConstructor( "load", types.null(), "process_input" ) )
      local loadCE = S.CE("load_CE")
      load:setCE(loadCE)

      if A==types.null() then
        load:setOutput( fifo:hasData(), "load_output" )
      else
        local res = S.tuple{fifo:popFront( nil, fifo:hasData() ), fifo:hasData() }
        load:setOutput( res, "load_output" )
      end
      
      local loadReset = systolicModule:addFunction( Ssugar.lambdaConstructor( "load_reset" ) )
      loadReset:addPipeline(fifo:popFrontReset())

      --------------
      -- debug
      if W~=nil then
        local outputCount = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap(types.uint(32),((W*H)/T)-1,1) ):CE(true):setInit(0):setReset(0):instantiate("outputCount") )
        load:addPipeline(outputCount:setBy(fifo:hasData()))
        loadReset:addPipeline(outputCount:reset())
        
        local maxSize = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.max(types.uint(16),true) ):setReset(0):CE(true):setInit(0):instantiate("maxSize") ) 
        local printInst = systolicModule:add( S.module.print( types.uint(16), "max size %d/"..size, nil, false):instantiate("printInst") )
        load:addPipeline(maxSize:setBy(S.cast(fifo:size(),types.uint(16))))
        local lastCycle = S.eq(outputCount:get(), S.constant(((W*H)/T)-1, types.uint(32))):disablePipelining()
        load:addPipeline(printInst:process(maxSize:get(), lastCycle))
        loadReset:addPipeline(maxSize:reset())
      end
      --------------

      systolicModule = liftDecimateSystolic( systolicModule, {"load"}, {"store"}, false )
      systolicModule = runIffReadySystolic( systolicModule,{"store"},{"load"})
      systolicModule = liftHandshakeSystolic( systolicModule,{"load","store"},{},{true,false})
      
      return systolicModule
    end
  end

  return rigel.newFunction(res)
end)

modules.dram = memoize(function( A, delay, filename, X )
  rigel.expectBasic(A)
  assert(X==nil)

  local res = {kind="dram", inputType=rigel.Handshake(types.uint(32)), outputType=rigel.Handshake(A), registered=true, sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=true}

  if terralib~=nil then res.terraModule = MT.dram(res,A,delay,filename) end

  res.name = sanitize("DRAM_"..tostring(A))
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
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
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

  local res
  if (W*H)%2==0 then
    -- codesize reduction optimization
    local C = require "examplescommon"
    local I = rigel.input( types.array2d( f.outputType, W, H ) )
    local ic = rigel.apply( "cc", C.cast( types.array2d( f.outputType, W, H ), types.array2d( f.outputType, W*H ) ), I)

    local ica = rigel.apply("ica", C.slice(types.array2d( f.outputType, W*H ),0,(W*H)/2-1,0,0), ic)
    local a = rigel.apply("a", modules.reduce(f,(W*H)/2,1), ica)

    local icb = rigel.apply("icb", C.slice(types.array2d( f.outputType, W*H ),(W*H)/2,(W*H)-1,0,0), ic)
    local b = rigel.apply("b", modules.reduce(f,(W*H)/2,1), icb)

    local fin = rigel.concat("conc", {a,b})
    local out = rigel.apply("out", f, fin)
    res = modules.lambda("reduce_"..f.name.."_W"..tostring(W).."_H"..tostring(H), I, out)
  else
    res = {kind="reduce", fn = f, W=W, H=H}
    rigel.expectBasic(f.inputType)
    rigel.expectBasic(f.outputType)
    if f.inputType:isTuple()==false or f.inputType~=types.tuple({f.outputType,f.outputType}) then
      err("Reduction function f must be of type {A,A}->A, but is "..tostring(f.inputType).." -> "..tostring(f.outputType))
    end
    res.inputType = types.array2d( f.outputType, W, H )
    res.outputType = f.outputType
    res.stateful = f.stateful
    if f.stateful then print("WARNING: reducing with a stateful function - are you sure this is what you want to do?") end
    
    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
    res.delay = math.ceil(math.log(res.inputType:channels())/math.log(2))*f.delay
    res.name = sanitize("reduce_"..f.name.."_W"..tostring(W).."_H"..tostring(H))
    
    
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

    res = rigel.newFunction( res )
  end

  if terralib~=nil then res.terraModule = MT.reduce(res,f,W,H) end

  return res
end)


modules.reduceSeq = memoize(function( f, T, framed, X )
  err(type(T)=="number","reduceSeq: T should be number")
  err(T<=1, "reduceSeq: T>1, T="..tostring(T))
  if framed==nil then framed=false end
  err( type(framed)=="boolean","reduceSeq: framed must be boolean" )
  assert(X==nil)

  if f.inputType:isTuple()==false or f.inputType~=types.tuple({f.outputType,f.outputType}) then
    error("Reduction function f must be of type {A,A}->A, but is type "..tostring(f.inputType).."->"..tostring(f.outputType))
  end

  local res = {kind="reduceSeq", fn=f, T=T}
  rigel.expectBasic(f.outputType)
  res.inputType = f.outputType
  if framed then
    res.inputType = types.StaticFramed( res.inputType, false, {{1/T,1}} )
  end
  res.outputType = rigel.V(f.outputType)
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1/T}
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

    local phase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.sumwrap(types.uint(16), (1/T)-1 ) ):CE(true):setReset(0):instantiate("phase") )
    
    local pipelines = {}
    table.insert(pipelines, phase:setBy( S.constant(1,types.uint(16)) ) )
    
    local out
    
    if T==1 then
      -- hack: Our reduce fn always adds two numbers. If we only have 1 number, it won't work! just return the input.
      out = sinp
    else
      local sResult = systolicModule:add( Ssugar.regByConstructor( f.outputType, f.systolicModule ):CE(true):hasSet(true):instantiate("result") )
      table.insert( pipelines, sResult:set( sinp, S.eq(phase:get(), S.constant(0, types.uint(16) ) ):disablePipelining() ) )
      out = sResult:setBy( sinp, S.__not(S.eq(phase:get(), S.constant(0, types.uint(16) ) )):disablePipelining() )
    end
    
    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process( S.tuple{phase:get(),sinp,out} ) ) end
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ out, S.eq(phase:get(), S.constant( (1/T)-1, types.uint(16))) }, "process_output", pipelines, svalid, CE) )
    
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:reset()}, S.parameter("reset",types.bool())) )
    
    return systolicModule
  end

  return rigel.newFunction( res )
    end)

-- surpresses output if we get more then _count_ inputs
modules.overflow = memoize(function( A, count )
  rigel.expectBasic(A)

  err( count<2^32-1, "overflow: outputCount must not overflow")
  
  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="overflow", A=A, inputType=A, outputType=rigel.V(A), stateful=true, count=count, sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, delay=0}
  if terralib~=nil then res.terraModule = MT.overflow(res,A,count) end
  res.name = "Overflow_"..count.."_"..verilogSanitize(tostring(A))

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local cnt = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32))):CE(true):setReset(0):instantiate("cnt") )

    local sinp = S.parameter("process_input", A )
    local CE = S.CE("CE")

    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ sinp, S.lt(cnt:get(), S.constant( count, types.uint(32))) }, "process_output", {cnt:setBy(S.constant(true,types.bool()))}, nil, CE ) )

    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {cnt:reset()}, S.parameter("reset",types.bool())) )

    return systolicModule
  end

  return rigel.newFunction( res )
end)

-- provides fake output if we get less then _count_ inputs after _cyclecount_ cycles
-- if thing thing is done before tooSoonCycles, throw an assert
-- waitForValid: don't actually start counting cycles until we see one valid input
--               (if false, cycle count starts at beginning of time)
-- overflowValue: what value should we emit when we overflow?
-- ratio: usually, should just be 1->1 rate, but this allows us to do ratio->1 rate. (doesn't actually affect behavior)
modules.underflow = memoize(function( A, count, cycles, upstream, tooSoonCycles, waitForValid, overflowValue, ratio, X )
  rigel.expectBasic(A)
  err( type(count)=="number", "underflow: count must be number" )
  err( type(cycles)=="number", "underflow: cycles must be number" )
  err( cycles==math.floor(cycles),"cycles must be an integer")
  err( type(upstream)=="boolean", "underflow: upstream must be bool" )
  err( tooSoonCycles==nil or type(tooSoonCycles)=="number", "tooSoonCycles must be nil or number" )
  if overflowValue~=nil then A:checkLuaValue(overflowValue) end
  err( X==nil, "underflow: too many arguments" )
  
  assert(count<2^32-1)
  err(cycles<2^32-1,"cycles >32 bit:"..tostring(cycles))

  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="underflow", A=A, inputType=rigel.Handshake(A), outputType=rigel.Handshake(A), stateful=true, count=count, sdfOutput=SDF{1,1}, delay=0, upstream = upstream, tooSoonCycles = tooSoonCycles}

  res.sdfInput = SDF{1,1}
  if ratio~=nil then
    assert(SDF.isSDF(ratio))
    res.sdfInput = ratio
  end
  
  if terralib~=nil then res.terraModule = MT.underflow(res,  A, count, cycles, upstream, tooSoonCycles, waitForValid, overflowValue ) end
  res.name = sanitize("Underflow_A"..tostring(A).."_count"..count.."_cycles"..cycles.."_toosoon"..tostring(tooSoonCycles).."_US"..tostring(upstream))

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor( res.name ):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(32),types.uint(32),types.bool()}, "outputCount %d cycleCount %d outValid"):instantiate("printInst") ) end
    
    local outputCount = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap(types.uint(32),count-1,1) ):CE(true):setReset(0):instantiate("outputCount") )
    
    -- NOTE THAT WE Are counting cycles where downstream_ready == true
    local cycleCount = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap(types.uint(32),cycles-1,1) ):CE(true):setReset(0):instantiate("cycleCount") )

    -- are we in fixup mode?
    local fixupReg = systolicModule:add( Ssugar.regByConstructor( types.uint(1), fpgamodules.incIf(1,types.uint(1)) ):CE(true):setReset(0):instantiate("fixupReg") )

    local countingReg

    if waitForValid then
      -- countingReg: if 1, we should count cycles, if 0, we're waiting until we see a valid
      countingReg = systolicModule:add( Ssugar.regByConstructor( types.uint(1), fpgamodules.incIf(1,types.uint(1)) ):CE(true):setReset(0):instantiate("countingReg") )
    end
    
    local rst = S.parameter("reset",types.bool())
    
    local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local pready = S.parameter("ready_downstream", types.bool())
    local pvalid = S.index(pinp,1)
    local pdata = S.index(pinp,0)
    
    --local fixupMode = S.gt(cycleCount:get(),S.constant(cycles,types.uint(32)))
    local fixupMode = S.eq(fixupReg:get(),S.constant(1,types.uint(32)))
    
    local CE = pready
    local CE_cycleCount = CE  

    if upstream then  
      CE = S.__or(CE,fixupMode) 
      CE_cycleCount = S.constant(true,types.bool())
    end

    local pipelines = {}
    table.insert( pipelines, outputCount:setBy(S.__and(pready,S.__or(pvalid,fixupMode)), S.constant(true,types.bool()), CE) )
    local cycleCountCond = S.__not(fixupMode)
    if waitForValid then cycleCountCond = S.__and(cycleCountCond,S.eq(countingReg:get(),S.constant(1,types.uint(1)))) end
    table.insert( pipelines, cycleCount:setBy(cycleCountCond, S.constant(true,types.bool()), CE_cycleCount) )

    local cycleCountLast = S.eq(cycleCount:get(),S.constant(cycles-1,types.uint(32)))
    local outputCountLast = S.eq(outputCount:get(),S.constant(count-1,types.uint(32)))
    table.insert( pipelines, fixupReg:setBy(S.__or(cycleCountLast,outputCountLast), S.constant(true,types.bool()), CE_cycleCount) )

    if waitForValid then
      table.insert( pipelines, countingReg:setBy(S.__or(S.__and(pvalid,S.__not(cycleCountCond)),S.__and(outputCountLast,fixupMode)), S.constant(true,types.bool()), CE) )
    end
    
    local outData
    if A:verilogBits()==0 then
      outData = pdata
    else
      local DEADBEEF = 4022250974 -- deadbeef
      if upstream then DEADBEEF = 3737169374 end -- deadc0de
      local fixupValue = S.cast(S.constant(math.min(DEADBEEF,math.pow(2,A:verilogBits())-1),types.bits(A:verilogBits())),A)

      if overflowValue~=nil then fixupValue = S.constant(overflowValue,A) end
      
      outData = S.select(fixupMode,fixupValue,pdata)
    end
    
    local outValid = S.__or(S.__and(fixupMode,S.lt(outputCount:get(),S.constant(count,types.uint(32)))),S.__and(S.__not(fixupMode),pvalid))
    
    if tooSoonCycles~=nil then
      local asstInst = systolicModule:add( S.module.assert( "pipeline completed eariler than expected", true, false ):instantiate("asstInst") )
      local tooSoon = S.eq(cycleCount:get(),S.constant(tooSoonCycles,types.uint(32)))
      tooSoon = S.__and(tooSoon,S.ge(outputCount:get(),S.constant(count,types.uint(32))))
      table.insert( pipelines, asstInst:process(S.__not(tooSoon),S.constant(true,types.bool()),CE) )
      
      -- ** throw in valids to mess up result
      -- just raising an assert doesn't work b/c verilog is dumb
      outValid = S.__or(outValid,tooSoon)
    end
    
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple{outputCount:get(),cycleCount:get(),outValid}) ) end
    
    systolicModule:addFunction( S.lambda("process", pinp, S.tuple{outData,outValid}, "process_output", pipelines) ) 
    
    local resetPipelines = {}
    table.insert( resetPipelines, outputCount:reset(nil,rst) )
    table.insert( resetPipelines, cycleCount:reset(nil,rst) )
    table.insert( resetPipelines, fixupReg:reset(nil,rst) )
    if waitForValid then table.insert( resetPipelines, countingReg:reset(nil,rst) ) end
    
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


modules.underflowNew = memoize(function(ty,cycles,count)
  err( types.isType(ty), "underflowNew: type must be rigel type" )
  err( types.isBasic(ty),"underflowNew: input should be basic, but is: "..tostring(ty) )
  
  local res = {kind="underflowNew"}
  res.inputType = types.Handshake(ty)
  res.outputType = types.Handshake(ty)
  res.sdfInput = SDF{1,1}
  res.sdfOutput = SDF{1,1}
  res.stateful=true
  res.delay=0
  res.name = sanitize("UnderflowNew_"..tostring(ty).."_cycles"..tostring(cycles).."_CNT"..tostring(count))

  if terralib~=nil then res.terraModule = MT.underflowNew( res, ty, cycles, count ) end
  
  local DEADCYCLES = 1024;
  
  function res.makeSystolic()
    local vstring = [[
module ]]..res.name..[[(input wire CLK, input wire reset, input wire []]..(ty:verilogBits())..[[:0] process_input, output wire []]..(ty:verilogBits())..[[:0] process_output, input wire ready_downstream, output wire ready);
  parameter INSTANCE_NAME="INST";



  reg [31:0] remainingItems = 32'd0;
  reg [31:0] remainingCycles = 32'd0;
  reg [31:0] deadCycles = 32'd0;

  wire validIn;
  assign validIn = process_input[]]..(ty:verilogBits())..[[];
  
  wire outtaTime;
  assign outtaTime =  (remainingCycles <= remainingItems) && (remainingItems>32'd1);

  wire firstItem;
  assign firstItem = remainingItems==32'd0 && remainingCycles==32'd0 && deadCycles==32'd0 && validIn;

  // write out a final item in exactly cycles+DEADCYCLES cycles
  wire lastWriteOut;
  assign lastWriteOut = (deadCycles==32'd1) && (remainingCycles==32'd0);

  wire validOut;
  assign validOut = (remainingItems>32'd1 && validIn) || firstItem || outtaTime || lastWriteOut;
  wire []]..(ty:verilogBits()-1)..[[:0] outData;
  assign outData = validIn?process_input[]]..(ty:verilogBits()-1)..[[:0]:(]]..(ty:verilogBits())..[['d0);

  wire lastItem;
  assign lastItem = remainingItems==32'd2 && validOut;

  assign process_output = { validOut, outData};

  assign ready = ready_downstream || outtaTime;

  always @(posedge CLK) begin
    if (reset) begin
      remainingItems <= 32'd0;
      remainingCycles <= 32'd0;
      deadCycles <= 32'd0;
    end else if (ready_downstream) begin
      if(firstItem) begin
        remainingItems <= 32'd]]..(count-1)..[[;
        remainingCycles <= 32'd]]..(cycles-1)..[[;
      end else if(lastItem) begin
        remainingItems <= 32'd1;
        deadCycles <= 32'd]]..DEADCYCLES..[[;
        if (remainingCycles>32'd0) begin remainingCycles <= remainingCycles-32'd1; end
      end else begin
        if (deadCycles>32'd0 && remainingCycles==32'd0) begin deadCycles <= deadCycles-32'd1; end
        if (remainingCycles>32'd0) begin remainingCycles <= remainingCycles-32'd1; end
        if (validOut) begin remainingItems <= remainingItems - 32'd1; end
      end
    end else begin
      // count down cycles even if not ready
      if (remainingCycles>32'd0) begin remainingCycles <= remainingCycles-32'd1; end
    end

//    if( lastItem || lastWriteOut || firstItem || outtaTime ) begin
//      $display("firstItem:%d lastItem:%d lastWriteOut:%d deadCycles:%d validOut:%d outtaTime:%d remainingItems:%d remainingCycles:%d readyDS:%d validIn:%d CNT:%d", firstItem, lastItem, lastWriteOut, deadCycles,validOut,outtaTime,remainingItems, remainingCycles, ready_downstream, validIn, CNT);
//    end
  end

endmodule
]]

    local fns = {}
    fns.reset = S.lambda( "reset", S.parameter("resetinp",types.null()), S.null(), "resetout",nil,S.parameter("reset",types.bool()))

    local inp = S.parameter("process_input",types.lower(res.inputType))
    fns.process = S.lambda("process",inp,S.tuple{ S.constant(ty:fakeValue(),ty), S.constant(true,types.bool()) }, "process_output")
    
    local downstreamReady = S.parameter("ready_downstream", types.bool())
    fns.ready = S.lambda("ready", downstreamReady, downstreamReady, "ready" )
    
    local ToVarlenSys = systolic.module.new(res.name, fns, {}, true,nil, vstring,{process=0,reset=0})
    
    return ToVarlenSys
  end
  
  return rigel.newFunction(res)

end)

-- record the # of cycles needed to complete the computation, and write it into the last axi burst
-- Note that this module _does_not_ wait until it sees the first token to start counting. It
--    starts counting immediately after reset. This is so that it includes startup latency in cycle count.
modules.cycleCounter = memoize(function( A, count, X )
  rigel.expectBasic(A)
  J.err( type(count)=="number","cycleCounter: count must be number" )
  J.err( X==nil, "cycleCounter: too many arguments")
  
  assert(count<2^32-1)

    -- # of cycles we need to write out metadata
  local padCount = (128*8) / A:verilogBits()

  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="cycleCounter", A=A, inputType=rigel.Handshake(A), outputType=rigel.Handshake(A), stateful=true, count=count, sdfInput=SDF{count,count+padCount}, sdfOutput=SDF{1,1}, delay=0}
  res.name = sanitize("CycleCounter_A"..tostring(A).."_count"..count)

  if terralib~=nil then res.terraModule = MT.cycleCounter(res,A,count) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor( res.name ):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(32),types.uint(32),types.bool(),types.bool()}, "cycleCounter outputCount %d cycleCount %d outValid %d metadataMode %d"):instantiate("printInst") ) end
    
    local outputCount = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap(types.uint(32),count+padCount-1,1) ):CE(true):setReset(0):instantiate("outputCount") )
    local cycleCount = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIf(1,types.uint(32),false) ):CE(false):setReset(0):instantiate("cycleCount") )
    
    local rst = S.parameter("reset",types.bool())
    
    local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local pready = S.parameter("ready_downstream", types.bool())
    local pvalid = S.index(pinp,1)
    local pdata = S.index(pinp,0)
    
    local done = S.ge(outputCount:get(),S.constant(count,types.uint(32)))

    local metadataMode = done

    local CE = pready
    
    local pipelines = {}
    table.insert( pipelines, outputCount:setBy(S.__and(pready,S.__or(pvalid,metadataMode)), S.constant(true,types.bool()), CE) )
    table.insert( pipelines, cycleCount:setBy(S.__not(done), S.constant(true,types.bool())) )
    
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
    
    if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple{outputCount:get(),cycleCount:get(),outValid,metadataMode}) ) end
    
    systolicModule:addFunction( S.lambda("process", pinp, S.tuple{outData,outValid}, "process_output", pipelines) ) 
    
    local resetPipelines = {}
    table.insert( resetPipelines, outputCount:reset(nil,rst) )
    table.insert( resetPipelines, cycleCount:reset(nil,rst) )
    
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
local function lambdaSDFNormalize( input, output, instances )
  local sdfMaxRate = output:sdfExtremeRate(true)

  -- if we don't early exit, we'll rescale up so that something is at 100%
  --if SDFRate.fracToNumber(sdfMaxRate) < 1 then
  --  print("Warning: SDF Rate < 1, inefficient hardware may be generated")
  --  return input, output, instances
  --end

  if input~=nil and input.sdfRate~=nil then
    err( SDFRate.isSDFRate(input.sdfRate),"SDF input rate is not a valid SDF rate")

    for k,v in pairs(input.sdfRate) do
      err(v=="x" or v[1]/v[2]<=1, "error, lambda declared with input BW > 1")
    end
  end

  local scaleFactor = SDFRate.fracInvert(sdfMaxRate)
  
  if DARKROOM_VERBOSE then print("NORMALIZE, sdfMaxRate", SDFRate.fracToNumber(sdfMaxRate),"outputBW", SDFRate.fracToNumber(outputBW), "scaleFactor", SDFRate.fracToNumber(scaleFactor)) end

  local newInstances = {}
  local instanceMap = {}
  for _,v in ipairs(instances) do
    local newRate = SDF(SDFRate.multiply( v.rate, scaleFactor[1], scaleFactor[2] ) )
    local inst = rigel.instantiateRegistered( v.name, v.fn, newRate )
    instanceMap[v] = inst
    table.insert( newInstances, inst)
  end

  local newInput
  local newOutput = output:process(
    function(n,orig)
      if n.kind=="input" then
        err( n.id==input.id, "lambdaSDFNormalize: unexpected input node. input node is not the declared module input." )
        n.rate = SDF(SDFRate.multiply(n.rate,scaleFactor[1],scaleFactor[2]))
        assert( SDFRate.isSDFRate(n.rate))
        newInput = rigel.newIR(n)
        return newInput
      elseif n.kind=="apply" and #n.inputs==0 then
        -- for nullary modules, we sometimes provide an explicit SDF rate, to get around the fact that we don't solve for SDF rates bidirectionally
        n.rate = SDF(SDFRate.multiply(n.rate, scaleFactor[1], scaleFactor[2] ))
        return rigel.newIR(n)
      elseif n.kind=="applyMethod" then
        n.inst = instanceMap[n.inst]
        return rigel.newIR(n)
      else
        return rigel.newIR(n)
      end
    end)

  return newInput, newOutput, newInstances
end

-- check to make sure we have FIFOs in diamonds
local function checkFIFOs(output)
  output:visitEach(
    function(n, arg)
      local res = {}
      if n.kind=="input" then
        -- HACK: if we have multiple stream inputs, just give the user the benefit of the doubt? (& count them as fifoed)
        res = J.broadcast(true,types.streamCount(n.type))
      elseif n.kind=="apply" and n.fn.kind=="broadcastStream" then
        res = J.broadcast( false, n.type.params.W*n.type.params.H )
      elseif n.kind=="apply" and (n.fn.kind=="packTuple" or n.fn.kind=="toHandshakeArrayOneHot") then
        assert(#arg==1)
        assert(#arg[1]==types.streamCount(n.fn.inputType) )
        for i=1,types.streamCount(n.fn.inputType) do
          J.err( n.fn.disableFIFOCheck==true or arg[1][i], "CheckFIFOs: branch in a diamond is missing FIFO! (input stream idx "..(i-1)..". "..tostring(types.streamCount(n.fn.inputType)).." input streams) "..n.loc)
        end

        -- Is this right???? if we got this far, we did have a fifo along this brach...
        res = J.broadcast(true,types.streamCount(n.type))
      elseif n.kind=="apply" and rigel.isGenerator(n.fn.generator) and n.fn.generator.name=="FIFO" then
        res = {true}
      elseif n.kind=="apply" and n.fn.generator=="C.fifo" then
        res = {true}
      elseif n.kind=="applyMethod" then
        if n.fnname=="store" or n.fnname=="done" then
          res = {}
        elseif n.fnname=="load" and n.inst.fn.kind=="fifo" then
          res = {true}
        else
          res = {false} -- HACK: this isn't really correct...
        end
      elseif n.kind=="apply" then
        assert(#arg==#n.inputs)

        if #n.inputs==0 then
          -- HACK: for nullary modules, just give the user the benefit of the doubt? (& count them as fifoed)
          res = J.broadcast(true,types.streamCount(n.type))
        else
          if types.streamCount(n.fn.inputType) ~= types.streamCount(n.fn.outputType) then
            -- hack: tooooo hard to figure this out, so be conservative
            res = J.broadcast( false, types.streamCount(n.fn.outputType) )
          else
            res = arg[1]
          end
        end
      elseif n.kind=="selectStream" then
        assert(#arg==1)
        res = {arg[1][n.i+1]}
      elseif n.kind=="concat" or n.kind=="concatArray2d" then
        for i=1,#n.inputs do
          if #arg[i]>=1 then
            assert(#arg[i]==1)
            res[i] = arg[i][1]
          end
        end
      elseif n.kind=="statements" then
        res = arg[1]
      elseif n.kind=="readGlobal" then
        -- is this right???
        res = J.broadcast(true,types.streamCount(n.type))
      elseif n.kind=="constant" or n.kind=="writeGlobal" then
        res = {}
      else
        print("NYI ",n.kind)
        assert(false)
      end

      J.err( type(res)=="table", "checkFIFOs bad res "..tostring(n) )
      J.err( #res == types.streamCount(n.type), "checkFIFOs error (res:"..#res..",streamcount:"..types.streamCount(n.type)..",type:"..tostring(n.type)..")- "..tostring(n) )
      return res
    end)
end

-- function definition
-- output, inputs
function modules.lambda( name, input, output, instances, generatorStr, generatorParams, globalMetadata, X )
  if DARKROOM_VERBOSE then print("lambda start '"..name.."'") end

  err( X==nil, "lambda: too many arguments" )
  err( type(name) == "string", "lambda: module name must be string" )
  err( input==nil or rigel.isIR( input ), "lambda: input must be a rigel input value or nil" )
  err( input==nil or input.kind=="input", "lambda: input must be a rigel input or nil" )
  err( rigel.isIR( output ), "modules.lambda: module '"..tostring(name).."' output should be Rigel value, but is: "..tostring(output) )
  if instances==nil then instances={} end
  err( type(instances)=="table", "lambda: instances must be nil or a table")
  J.map( instances, function(n) err( rigel.isInstance(n), "lambda: instances argument must be an array of instances" ) end )
  err( generatorStr==nil or type(generatorStr)=="string","lambda: generatorStr must be nil or string")
  err( generatorParams==nil or type(generatorParams)=="table","lambda: generatorParams must be nil or table")
  err( globalMetadata==nil or type(globalMetadata)=="table","lambda: globalMetadata must be nil or table")

  -- collect instances (user doesn't have to explicitly give all instances)
  local instanceMap = J.invertTable( instances )

  output:visitEach(
    function(n)
      if n.kind=="applyMethod" then
        if instanceMap[n.inst]==nil then
          table.insert( instances, n.inst )
          instanceMap[n.inst] = "found"
        else
          instanceMap[n.inst] = "found"
        end
      end
    end)

  for k,v in pairs(instanceMap) do
    err( v=="found", "lambda: instance '"..k.name.."' was never used?" )
  end
  
  if rigel.SDF then
    input, output, instances = lambdaSDFNormalize(input,output,instances)
    local sdfMaxRate = output:sdfExtremeRate(true)
    err( Uniform(sdfMaxRate[1]):le(sdfMaxRate[2]):assertAlwaysTrue(),"LambdaSDFNormalize failed? somehow we ended up with a instance utilization of "..tostring(sdfMaxRate[1]).."/"..tostring(sdfMaxRate[2]).." somewhere in module '"..name.."'") 
  end

  name = J.verilogSanitize(name)

  local res = {kind = "lambda", name=name, input = input, output = output, instances=instances, generator=generatorStr, params=generatorParams }

  if input==nil then
    res.inputType = types.null()
  else
    res.inputType = input.type
  end

  res.outputType = output.type

  local usedNames = {}
  output:visitEach(
    function(n)
      if n.name~=nil then
        assert(type(n.name)=="string")
        if usedNames[n.name]~=nil then
          print("FIRST: "..usedNames[n.name])
          print("SECOND: "..n.loc)
          print("NAME USED TWICE:",n.name)
          assert(false)
        end
        usedNames[n.name] = n.loc
      end
    end)

  res.stateful=false
  output:visitEach(
    function(n)
      if n.kind=="apply" then
        err( type(n.fn.stateful)=="boolean", "Missing stateful annotation, fn "..n.fn.name )
        res.stateful = res.stateful or n.fn.stateful
      elseif n.kind=="applyMethod" then
        err( type(n.inst.fn.stateful)=="boolean", "Missing stateful annotation, fn "..n.inst.fn.name )
        res.stateful = res.stateful or n.inst.fn.stateful
      end
    end)

  if input~=nil and input.type~=types.null() and rigel.isStreaming(input.type)==false and rigel.isStreaming(output.type)==false then
    res.delay = output:visitEach(
      function(n, inputs)
        if n.kind=="input" or n.kind=="constant" or n.kind=="readGlobal" or n.kind=="writeGlobal" then
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
  
  -- collect the globals
  res.globals = {}
  res.globalsInternal = {} -- global_name->global (either the input or output, it's arbitrary)
  res.globalMetadata = {}
  local globalPairs = {} -- detect if we have an internal input/output pair
  local globalDbgLoc = {}
  
  output:visitEach(
    function(n)
      if n.kind=="apply" then
        for g,_ in pairs(n.fn.globals) do

          if globalPairs[g.name]~=nil and globalPairs[g.name].direction~=g.direction then
            -- this is an internal pair, remove from list
	    res.globalsInternal[g.name] = g
            res.globals[globalPairs[g.name]] = nil
            res.globals[g]=nil
            globalDbgLoc[g] = nil
          else
            if g.direction=="output" then
              err( res.globals[g]==nil,"Error: wrote to output global '"..g.name.."' twice (apply)! "..n.loc.." ORIG: "..tostring(globalDbgLoc[g]))
            end
            res.globals[g] = 1
            globalPairs[g.name]=g
            globalDbgLoc[g] = n.loc
          end
        end

        for k,v in pairs(n.fn.globalMetadata) do
          err(res.globalMetadata[k]==nil,"Error: wrote to global metadata '"..k.."' twice! this value: '"..tostring(v).."', orig value: '"..tostring(res.globalMetadata[k]).."' "..n.loc)
          res.globalMetadata[k] = v
        end
      elseif n.kind=="readGlobal" or n.kind=="writeGlobal" then
        if globalPairs[n.global.name]~=nil and (n.kind=="readGlobal" and globalPairs[n.global.name].direction=="output") then
          -- this is an internal pair, remove from list
          res.globalsInternal[n.global.name] = n.global
          res.globals[globalPairs[n.global.name]] = nil
          res.globals[n.global] = nil
          globalDbgLoc[n.global] = nil
        else
          res.globals[n.global]=1
          globalDbgLoc[n.global] = n.loc
          globalPairs[n.global.name]=n.global
        end
      end
    end)

  -- NOTE: notice that this will overwrite the previous metadata values
  if globalMetadata~=nil then
    for k,v in pairs(globalMetadata) do
      J.err(type(k)=="string","global metadata key must be string")

      if res.globalMetadata[k]~=nil and res.globalMetadata[k]~=v then
        print("WARNING: overwriting metadata '"..k.."' with previous value '"..tostring(res.globalMetadata[k]).."' ("..type(res.globalMetadata[k])..") with overridden value '"..tostring(v).."' ("..type(v)..")")
      end
      
      res.globalMetadata[k]=v
    end
  end
  

  for k,v in pairs(res.instances) do
    for g,_ in pairs(v.fn.globals) do
      if globalPairs[g.name]~=nil and globalPairs[g.name].direction~=g.direction then
        res.globals[globalPairs[g.name]] = nil
        res.globals[g]=nil
        res.globalsInternal[g.name] = g
        globalDbgLoc[g]=nil
      else
        if g.direction=="output" then
          err( res.globals[g]==nil,"Error: wrote to output global '"..g.name.."' twice (apply)! ORIG: "..tostring(globalDbgLoc[g]) )
        end
        res.globals[g] = 1
        globalPairs[g.name]=g
        globalDbgLoc[g]="INSTANCE:"..v.name
      end
    end

    for k,v in pairs(v.fn.globalMetadata) do
      err(res.globalMetadata[k]==nil,"Error: wrote to global metadata twice!")
      res.globalMetadata[k] = v
    end
  end
  
  if terralib~=nil then res.makeTerra = function() return MT.lambdaCompile(res) end end

  if rigel.SDF then
    if input==nil then
      res.sdfInput = SDF({1,1})
    else
      assert( SDFRate.isSDFRate(input.rate) )

      if input.type==types.null() then
        -- HACK(?): if we have a nullary input, look for the actual input to the pipeline,
        -- which is the module this input drives. Use that module's rate as the input rate
        -- this pretty much only applies to the top module
        output:visitEach(
          function(n)
            if #n.inputs==1 and n.inputs[1]==input then
              res.sdfInput = n.rate
            end
          end)

        assert(res.sdfInput~=nil)
      else
        res.sdfInput = SDF(input.rate)
      end
    end

    res.sdfOutput = output.rate

    err(SDF.isSDF(res.sdfInput),"NOT SDF inp "..res.name.." "..tostring(res.sdfInput))
    err(SDF.isSDF(res.sdfOutput),"NOT SDF out "..res.name.." "..tostring(res.sdfOutput))

    if DARKROOM_VERBOSE then print("LAMBDA",name,"SDF INPUT",res.sdfInput[1][1],res.sdfInput[1][2],"SDF OUTPUT",res.sdfOutput[1][1],res.sdfOutput[1][2]) end

    -- each rate should be <=1
    for k,v in ipairs(res.sdfInput) do
      err( v[1]:le(v[2]):assertAlwaysTrue(), "lambda '"..name.."' has strange SDF rate. input: "..tostring(res.sdfInput).." output:"..tostring(res.sdfOutput))
    end
      
    -- each rate should be <=1
    for _,v in ipairs(res.sdfOutput) do
      err( v[1]:le(v[2]):assertAlwaysTrue(), "lambda '"..name.."' has strange SDF rate. input: "..tostring(res.sdfInput).." output:"..tostring(res.sdfOutput))
    end

  end

  checkFIFOs(output)
  
  -- should we compile thie module as handshaked or not?
  -- For handshaked modules, the input/output type is _not_ necessarily handshaked
  -- for example, input/output type could be null, but the internal connections may be handshaked
  -- so, check if we handshake anywhere
  local HANDSHAKE_MODE = rigel.handshakeMode(output)
  
  local function makeSystolic( fn )
    local module = Ssugar.moduleConstructor( fn.name ):onlyWire( HANDSHAKE_MODE )

    for g,_ in pairs(fn.globals) do
      module:addSideChannel(g.systolicValue)
      if g.systolicValueReady~=nil then module:addSideChannel(g.systolicValueReady) end
    end
    
    local process = module:addFunction( Ssugar.lambdaConstructor( "process", rigel.lower(fn.inputType), "process_input") )
    local reset

    if fn.stateful then
      reset = module:addFunction( Ssugar.lambdaConstructor( "reset", types.null(), "resetNILINPUT", "reset") )
    end
    
    if HANDSHAKE_MODE==false then 
      local CE = S.CE("CE")
      process:setCE(CE)
    end

    if fn.instances~=nil then
      for k,v in pairs(fn.instances) do
        err( systolic.isModule(v.fn.systolicModule), "Missing systolic module for "..v.fn.kind)
        module:add( v.fn.systolicModule:instantiate(v.name) )
      end
    end

    local out = fn.output:codegenSystolic( module )

    assert(systolic.isAST(out[1]))

    err( out[1].type==rigel.lower(res.outputType), "Internal error, systolic type is "..tostring(out[1].type).." but should be "..tostring(rigel.lower(res.outputType)).." function "..name )

    assert(Ssugar.isFunctionConstructor(process))
    process:setOutput( out[1], "process_output" )

    -- for the non-handshake (purely systolic) modules, the ready bit doesn't flow from outputs to inputs,
    -- it flows from inputs to outputs. The reason is that upstream things can't stall downstream things anyway, so there's really no point of doing it the 'right' way.
    -- this is kind of messed up!
    if rigel.isRV( fn.inputType ) or fn.inputType:is("RVFramed") then
      assert( S.isAST(out[2]) )
      local readyfn = module:addFunction( S.lambda("ready", readyInput, out[2], "ready", {} ) )
    elseif rigel.isRV( fn.outputType ) or fn.outputType:is("RVFramed") then
      local readyfn = module:addFunction( S.lambda("ready", S.parameter("RINIL",types.null()), out[2], "ready", {} ) )
    elseif HANDSHAKE_MODE then
       
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

          -- why do we need to support multiple readers of a HS stream? (ie ANDing the ready bits?)
          -- A stream may be read by multi selectStreams, which is OK.
          -- However: why can't we just special-case expect all multiple readers to be selectStreams? It seems like this should work.
          -- Note 1: Take a look at modulesTerra.lambda... it basically implements this that way
          -- Note 2: one issue is that it's very important that this function returns a systolic value of the correct type for
          --         every intermediate! We can return/examine any intermediate, and it must have the right type!
          --         don't try to special case by having this function return intermediates as lua arrays of bools or something.
         
          for k,i in pairs(args) do
            local parentKey = i[2]
            local value = i[1]
            local thisi = value[parentKey]

            if rigel.isHandshake(n.type) or rigel.isHandshakeTrigger(n.type) or n.type:is("HandshakeFramed") then
              assert(systolicAST.isSystolicAST(thisi))
              assert(thisi.type:isBool())
              
              if input==nil then
                input = thisi
              else
                input = S.__and(input,thisi)
              end
            elseif n:outputStreams()>1 or rigel.isHandshakeArray(n.type) then
              assert(systolicAST.isSystolicAST(thisi))
              
              if rigel.isHandshakeTmuxed(n.type) or rigel.isHandshakeArrayOneHot(n.type) then
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
            assert(n:parentCount(fn.output)==0)
            
            if n:outputStreams()==1 then
              readyinp = S.parameter( "ready_downstream", types.bool() )
              input = readyinp
            elseif n:outputStreams()>1 then
              readyinp = S.parameter( "ready_downstream", types.array2d(types.bool(),n:outputStreams()) )
              input = readyinp
            else
              -- this is ok: ready bit may be totally internal to the module
              readyinp = S.parameter( "ready_downstream", types.null() )
              input = readyinp
            end
          else
            -- if any downstream nodes are selectStream, they'd better all be selectStream, and the count had better match
            local anySS = false
            local allSS = true
            for dsNode,_ in n:parents(fn.output) do
              if dsNode.kind=="selectStream" then
                anySS = true
              else
                allSS = false
              end
            end

            err( anySS==allSS,"If any consumers are selectStream, all consumers must be selectStream "..n.loc )
            err( allSS==false or J.keycount(args)==n:outputStreams(), "Unconnected output? Module expects "..tostring(n:outputStreams()).." stream readers, but only "..tostring(J.keycount(args)).." were found. "..n.loc )

            if n:outputStreams()>=1 and n:parentCount(fn.output)>1 then
              err(allSS,"Error, a Handshaked, multi-reader node is being consumed by something other than a selectStream? Handshaked nodes with multiple consumers should use broadcastStream. "..n.loc)
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
            if n.fnname=="load" or n.fnname=="start" then
              -- "hack": systolic requires all function to be driven. We don't actually care about load fn ready bit, but drive it anyway
              local inst = module:lookupInstance(n.inst.name)
              res = {inst[n.fnname.."_ready"](inst, input)}
              table.insert(readyPipelines,res[1])
            elseif n.fnname=="store" or n.fnname=="done" then
              local inst = module:lookupInstance(n.inst.name)
              res = {inst[n.fnname.."_ready"](inst, input)}
            else
              err(false, "ready bit wiring for applyMethod, unknown function '"..n.fnname.."'")
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
          elseif n.kind=="writeGlobal" then
            assert( rigel.isHandshakeAny(n.global.type) )
            assert( n.global.direction=="output" )
            res = {S.readSideChannel(n.global.systolicValueReady)}
          elseif n.kind=="readGlobal" then
            assert( rigel.isHandshakeAny(n.global.type) )
            assert( n.global.direction=="input" )
            table.insert(readyPipelines, S.writeSideChannel(n.global.systolicValueReady,input) )
          else
            print("missing ready wiring of op - "..n.kind)
            assert(false)
          end

          -- now, validate that the output is what we expect
          err( #n.inputs==0 or type(res)=="table","res should be table "..n.kind.." inputs "..tostring(#n.inputs))
              
          for k,i in ipairs(n.inputs) do
            if rigel.isHandshake(i.type) or i.type:is("HandshakeFramed") then
              err(systolicAST.isSystolicAST(res[k]), "incorrect output format "..n.kind.." input "..tostring(k)..", not systolic value" )
              err(systolicAST.isSystolicAST(res[k]) and res[k].type:isBool(), "incorrect output format "..n.kind.." input "..tostring(k).." (type "..tostring(i.type)..", name "..i.name..") is "..tostring(res[k].type).." but expected bool, "..n.loc )
            elseif rigel.isHandshakeTrigger(i.type) then
              assert(#res==1)
              assert(res[1].type:isBool())
            elseif i:outputStreams()>1 or rigel.isHandshakeArray(i.type) then

              err(systolicAST.isSystolicAST(res[k]), "incorrect output format "..n.kind.." input "..tostring(k)..", not systolic value" )
              if(rigel.isHandshakeTmuxed(i.type)) then
                err( res[k].type:isBool(),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
              elseif rigel.isHandshakeArrayOneHot(i.type) then
                err( res[k].type==types.uint(8),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
              else
                err(res[k].type:isArray() and res[k].type:arrayOver():isBool(),  "incorrect output format "..n.kind.." input "..tostring(k).." is "..tostring(res[k].type).." but expected stream count "..tostring(i:outputStreams()).."  - "..n.loc)
              end
            elseif i:outputStreams()==0 then
              err(res[k]==nil or res[k].type==types.null(), "incorrect ready bit output format kind:'"..n.kind.."' - "..n.loc)
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
function modules.lift( name, inputType, outputType, delay, makeSystolic, makeTerra, generatorStr, sdfOutput, globals, X )
  err( type(name)=="string", "modules.lift: name must be string" )
  err( types.isType( inputType ), "modules.lift: inputType must be rigel type" )
  err( outputType==nil or types.isType( outputType ), "modules.lift: outputType must be rigel type, but is "..tostring(outputType) )
  err( delay==nil or type(delay)=="number",  "modules.lift: delay must be number" )
  err( sdfOutput==nil or SDFRate.isSDFRate(sdfOutput),"modules.lift: SDF output must be SDF")
  err( makeTerra==nil or type(makeTerra)=="function", "modules.lift: makeTerra argument must be lua function that returns a terra function" )
  err( type(makeSystolic)=="function", "modules.lift: makeSystolic argument must be lua function that returns a systolic value" )
  err( generatorStr==nil or type(generatorStr)=="string", "generatorStr must be nil or string")
  err( globals==nil or type(globals)=="table","modules.lift: globals must be table")
  assert(X==nil)

  if sdfOutput==nil then sdfOutput = SDF{1,1} end

  name = J.verilogSanitize(name)

  local res = { kind="lift", name=name, inputType = inputType, outputType = outputType, delay=delay, sdfInput=SDF{1,1}, sdfOutput=SDF(sdfOutput), stateful=false, generator=generatorStr,globals={} }

  if globals~=nil then
    for g,_ in pairs(globals) do
      assert(rigel.isGlobal(g))
      res.globals[g]=1
    end
  end
  
  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(name)

    for g,_ in pairs(res.globals) do
      systolicModule:addSideChannel(g.systolicValue)
    end
    
    local systolicInput = S.parameter( "inp", inputType )

    local systolicOutput, systolicInstances
    systolicOutput, systolicInstances = makeSystolic(systolicInput)
    
    err( (outputType==types.null() and systolicOutput==nil) or systolicAST.isSystolicAST(systolicOutput), "modules.lift: makeSystolic returned something other than a systolic value (module "..name..")" )

    if outputType~=nil and systolicOutput~=nil then -- user may not have passed us a type, and is instead using the systolic system to calculate it
      err( systolicOutput.type==rigel.lower(outputType), "lifted systolic output type does not match. Is "..tostring(systolicOutput.type).." but should be "..tostring(outputType)..", which lowers to "..tostring(rigel.lower(outputType)).." (module "..name..")" )
    end
    
    if systolicInstances~=nil then
      for k,v in pairs(systolicInstances) do systolicModule:add(v) end
    end

    systolicModule:addFunction( S.lambda("process", systolicInput, systolicOutput, "process_output",nil,nil,S.CE("process_CE")) )

    systolicModule:complete()
    return systolicModule
  end

  --[=[
  if res.outputType==nil then
    --err( S.isModule(res.systolicModule), "modules.lift: outputType is missing, and so is the systolic module?")
    res.systolicModule = res.makeSystolic()
    res.outputType = res.systolicModule:lookupFunction("process").output.type
    err( types.isType(res.outputType), "modules.lift: systolic module did not return a valid type")
  end
  ]=]
  J.err(types.isType(res.outputType),"modules.lift: missing outputType")

  local res = rigel.newFunction( res )

  if res.delay==nil then
    res.delay = res.systolicModule:getDelay("process")
  end

  if terralib~=nil then 
    local systolicInput, systolicOutput

    if makeTerra==nil then
      systolicInput = res.systolicModule.functions.process.inputParameter
      systolicOutput = res.systolicModule.functions.process.output
    end

    local tmod = MT.lift(inputType,outputType,makeTerra,systolicInput,systolicOutput)
    if type(tmod)=="function" then
      res.makeTerra = tmod
    elseif terralib.types.istype(tmod) then
      res.terraModule = tmod
    else
      assert(false)
    end
  end

  return res
end

modules.liftVerilog = memoize(function( name, inputType, outputType, vstr, globals, globalMetadata, sdfInput, sdfOutput, dependencies, registered, X )
  err( type(name)=="string", "liftVerilog: name must be string")
  err( types.isType(inputType), "liftVerilog: inputType must be type")
  err( types.isType(outputType), "liftVerilog: outputType must be type")
  err( type(vstr)=="string", "liftVerilog: verilog string must be string")
  err( globals==nil or type(globals)=="table", "liftVerilog: globals must be table")
  err( globalMetadata==nil or type(globalMetadata)=="table", "liftVerilog: global metadata must be table")
  if sdfInput==nil then sdfInput=SDF{1,1} end
  err( SDFRate.isSDFRate(sdfInput), "liftVerilog: sdfInput must be SDF rate, but is: "..tostring(sdfInput))
  if sdfOutput==nil then sdfOutput=SDF{1,1} end
  err( SDFRate.isSDFRate(sdfOutput), "liftVerilog: sdfOutput must be SDF rate, but is: "..tostring(sdfOutput))
  if registered==nil then registered=false end
  err( type(registered)=="boolean", "liftVerilog: registered must be nil or bool")
  err( X==nil, "liftVerilog: too many arguments")
  
  local res = { kind="liftVerilog", inputType=inputType, outputType=outputType, verilogString=vstr, name=name }
  res.stateful = true
  res.sdfInput=SDF(sdfInput)
  res.sdfOutput=SDF(sdfOutput)

  res.globals = {}
  if globals~=nil then
    for g,_ in pairs(globals) do
      assert(rigel.isGlobal(g))
      res.globals[g]=1
    end
  end

  res.globalMetadata = {}
  if globalMetadata~=nil then
    for k,v in pairs(globalMetadata) do
      res.globalMetadata[k] = v
    end
  end
    
  if dependencies~=nil then
    for k,v in ipairs(dependencies) do
      assert(rigel.isFunction(v))

      for g,_ in pairs(v.globals) do
        assert(rigel.isGlobal(g))
        res.globals[g]=1
      end

      for kk,vv in pairs(v.globalMetadata) do
        res.globalMetadata[kk] = vv
      end
      
    end
  end

  function res.makeSystolic()
    local fns = {}

    if registered then
      local inp = S.parameter("store_input",rigel.lower(inputType))
      fns.store = S.lambda("store",inp,nil,"store_output")

      local outv = rigel.lower(outputType):fakeValue()
      fns.load = S.lambda("load",S.parameter("LO",types.null()),S.constant(outv,rigel.lower(outputType)),"load_output")

      if rigel.hasReady(inputType) then
        fns.store_ready = S.lambda( "store_ready", S.parameter("nn",types.null()), S.constant(rigel.extractReady(res.inputType):fakeValue(),rigel.extractReady(res.inputType)), "store_ready")
      end

      if rigel.hasReady(outputType) then
        local rinp =  S.parameter("load_ready",rigel.extractReady(res.outputType))
        fns.load_ready = S.lambda( "load_ready", rinp, nil, "load_ready")
      end

      fns.store_reset = S.lambda("store_reset",S.parameter("rnils",types.null()),nil,"store_reset",{},S.parameter("store_reset",types.bool()))
      fns.load_reset = S.lambda("load_reset",S.parameter("rnill",types.null()),nil,"load_reset",{},S.parameter("load_reset",types.bool()))

    else
      local inp = S.parameter("process_input",rigel.lower(inputType))
      local outv = rigel.lower(outputType):fakeValue()
      fns.process = S.lambda("process",inp,S.constant(outv,rigel.lower(outputType)),"process_output")

      if rigel.hasReady(inputType) and rigel.hasReady(outputType) then
        local rinp =  S.parameter("ready_downstream",rigel.extractReady(res.outputType))
        fns.ready = S.lambda( "ready", rinp, S.constant(rigel.extractReady(res.inputType):fakeValue(),rigel.extractReady(res.inputType)), "ready")
      else
        print("liftVerilog: unsupported input/output type? inputType: "..tostring(inputType)..", outputType:"..tostring(outputType))
        assert(false)
      end

      fns.reset = S.lambda("reset",S.parameter("rnil",types.null()),nil,"process_reset",{},S.parameter("reset",types.bool()))
    end
    
    local SC = {}
    if globals~=nil then
      for g,_ in pairs(res.globals) do
        SC[g.systolicValue] = 1
        if g.systolicValueReady~=nil then SC[g.systolicValueReady] = 1 end
      end
    end

    local instances = {}
    if dependencies~=nil then
      for k,v in ipairs(dependencies) do
        table.insert(instances,v.systolicModule:instantiate("INST"..tostring(k)))
      end
    end
    
    return S.module.new(name,fns,instances,true,nil,vstr,{process=0,ready=0},SC)
  end
  
  return rigel.newFunction(res)
end)

modules.constSeqInner = memoize(function( value, A, w, h, T, X )
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
  res.stateful = true

  res.sdfInput, res.sdfOutput = SDF{1,1}, SDF{1,1}  -- well, technically this produces 1 output for every (nil) input

  -- TODO: FIX: replace this with an actual hash function... it seems likely this can lead to collisions
  local vh = J.to_string(value)
  if #vh>100 then vh = string.sub(vh,0,100) end
  
  -- some different types can have the same lua array representation (i.e. different array shapes), so we need to include both
  res.name = verilogSanitize("constSeq_"..tostring(A).."_"..tostring(vh).."_T"..tostring(1/T).."_w"..tostring(w).."_h"..tostring(h))
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

    local shiftOut, shiftPipelines, resetPipelines = fpgamodules.addShifterSimple( systolicModule, J.map(sconsts, function(n) return S.constant(n,types.array2d(A,W,h)) end), DARKROOM_VERBOSE )
    
    local inp = S.parameter("process_input", types.null() )

    systolicModule:addFunction( S.lambda("process", inp, shiftOut, "process_output", shiftPipelines, nil, S.CE("process_CE") ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("process_nilinp", types.null() ), nil, "process_reset", resetPipelines, S.parameter("reset", types.bool() ) ) )

    return systolicModule
  end

  return rigel.newFunction( res )
end)

function modules.constSeq(value,A,w,h,T,X)
  err( type(value)=="table", "constSeq: value should be a lua array of values to shift through")
  local UV = J.uniq(value)
  local I = modules.constSeqInner(UV,A,w,h,T,X)
  return I
end

modules.freadSeq = memoize(function( filename, ty )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  rigel.expectBasic(ty)
  local filenameVerilog=filename
  local res = {kind="freadSeq", filename=filename, filenameVerilog=filenameVerilog, type=ty, inputType=types.null(), outputType=ty, stateful=true, delay=0}
  res.sdfInput=SDF{1,1}
  res.sdfOutput=SDF{1,1}
  if terralib~=nil then res.terraModule = MT.freadSeq(filename,ty) end
  res.name = "freadSeq_"..verilogSanitize(filename)..verilogSanitize(tostring(ty))

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local sfile = systolicModule:add( S.module.file( filenameVerilog, ty, true ):instantiate("freadfile") )
    local inp = S.parameter("process_input", types.null() )
    local nilinp = S.parameter("process_nilinp", types.null() )
    local CE = S.CE("CE")

    systolicModule:addFunction( S.lambda("process", inp, sfile:read(), "process_output", nil, nil, CE ) )
    systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", {sfile:reset()}, S.parameter("reset", types.bool() ) ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- passthrough: write out the input?
-- allowBadSizes: hack for legacy code - allow us to write sizes which will have different behavior between verilog & terra (BAD!)
modules.fwriteSeq = memoize(function( filename, ty, filenameVerilog, passthrough, allowBadSizes, X )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  rigel.expectBasic(ty)
  if passthrough==nil then passthrough=true end
  err( type(passthrough)=="boolean","fwriteSeq: passthrough must be bool" )
  err(X==nil,"fwriteSeq: too many arguments")

  if filenameVerilog==nil then filenameVerilog=filename end
  
  local res = {kind="fwriteSeq", filename=filename, filenameVerilog=filenameVerilog, type=ty, inputType=ty, outputType=J.sel(passthrough,ty,types.null()), stateful=true, delay=0, sdfInput=SDF{1,1}, sdfOutput=SDF{1,1} }
  if terralib~=nil then res.terraModule = MT.fwriteSeq(filename,ty,passthrough, allowBadSizes) end
  res.name = verilogSanitize("fwriteSeq_"..filename.."_"..tostring(ty))

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local sfile = systolicModule:add( S.module.file( filenameVerilog, ty, true, passthrough, false ):instantiate("fwritefile") )

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
    systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", resetpipe, S.parameter("reset", types.bool() ) ) )

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
  err( rigel.isFunction(f), "fn must be a function")
  err( types.isType(inputType), "inputType must be a type")
  err( tapInputType==nil or types.isType(tapInputType), "tapInputType must be a type")
  if tapInputType~=nil then tapInputType:checkLuaValue(tapValue) end
  err( type(inputCount)=="number", "inputCount must be a number")
  err( inputCount==math.floor(inputCount), "inputCount must be integer, but is "..tostring(inputCount) )
  err( type(outputCount)=="number", "outputCount must be a number")
  err( outputCount==math.floor(outputCount), "outputCount must be integer, but is "..tostring(outputCount) )
  err( type(axi)=="boolean", "axi should be a bool")
  err( X==nil, "seqMapHandshake: too many arguments" )

  err( f.inputType==types.null() or rigel.isHandshake(f.inputType), "seqMapHandshake: input must be handshook or null")
  rigel.expectHandshake(f.outputType)

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
      local baseTypeO = rigel.extractData(f.outputType)
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
]]..S.declareWire( rigel.lower(f.outputType), "process_output" )..[[

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
    if(]]..readybit..[[ && process_output[]]..(rigel.lower(f.outputType):verilogBits()-1)..[[] && RST==1'b0) begin validCnt = validCnt + 1; end
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

  return rigel.newFunction(res)
end

-- this is a Handshake triggered counter.
-- it accepts an input value V of type TY.
-- Then produces N tokens (from V to V+(N-1)*stride)
modules.triggeredCounter = memoize(function(TY, N, stride)
  err( types.isType(TY),"triggeredCounter: TY must be type")
  err( rigel.expectBasic(TY), "triggeredCounter: TY should be basic")
  err( TY:isNumber(), "triggeredCounter: type must be numeric rigel type, but is "..tostring(TY))
  if stride==nil then stride=1 end
  err( type(stride)=="number", "triggeredCounter: stride should be number")
  
  err(type(N)=="number", "triggeredCounter: N must be number")

  local res = {kind="triggeredCounter"}
  res.inputType = TY
  res.outputType = rigel.RV(TY)
  res.sdfInput = SDF{1,N}
  res.sdfOutput = SDF{1,1}
  res.stateful=true
  res.delay=0
  res.name = "TriggeredCounter_"..verilogSanitize(tostring(TY)).."_"..tostring(N)

  if terralib~=nil then res.terraModule = MT.triggeredCounter(res,TY,N,stride) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local sinp = S.parameter( "inp", TY )
    
    local sPhase = systolicModule:add( Ssugar.regByConstructor( TY, fpgamodules.sumwrap(TY,N-1) ):CE(true):setReset(0):instantiate("phase") )
    local reg = systolicModule:add( S.module.reg( TY,true ):instantiate("buffer") )
    
    local reading = S.eq(sPhase:get(),S.constant(0,TY)):disablePipelining()
    local out = S.select( reading, sinp, reg:get()+(sPhase:get()*S.constant(stride,TY)) ) 
    
    local pipelines = {}
    table.insert(pipelines, reg:set( sinp, reading ) )
    table.insert( pipelines, sPhase:setBy( S.constant(1,TY) ) )
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines, nil, CE) )
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:reset()},S.parameter("reset",types.bool()) ) )

    return systolicModule
  end

  return modules.liftHandshake(modules.waitOnInput( rigel.newFunction(res) ))
  
end)

-- this output one trigger token after N inputs
modules.triggerCounter = memoize(function(N)
  err(type(N)=="number", "triggerCounter: N must be number")

  local res = {kind="triggerCounter"}
  res.inputType = types.null()
  res.outputType = rigel.VTrigger
  res.sdfInput = SDF{1,1}
  res.sdfOutput = SDF{1,N}
  res.stateful=true
  res.delay=0
  res.name = "TriggerCounter_"..tostring(N)

  if terralib~=nil then res.terraModule = MT.triggerCounter(res,N) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    
    local sPhase = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.sumwrap(types.uint(32),N-1) ):CE(true):setReset(0):instantiate("phase") )
    
    local done = S.eq(sPhase:get(),S.constant(N-1,types.uint(32))):disablePipelining()
    
    local pipelines = {}
    table.insert( pipelines, sPhase:setBy( S.constant(1,types.uint(32)) ) )
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", S.parameter( "inp", types.null() ), done, "process_output", pipelines, nil, CE) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:reset()},S.parameter("reset",types.bool()) ) )

    return systolicModule
  end

  return modules.liftHandshake(modules.liftDecimate( rigel.newFunction(res) ))
  
end)

-- just counts from 0....N-1
modules.counter = memoize(function(ty,N_orig)
  err( types.isType(ty), "counter: type must be rigel type")                          
  err( ty:isUint() or ty:isInt(), "counter: type must be uint or int")
  --err(type(N)=="number", "counter: N must be number")
  local N = Uniform(N_orig)

  J.err( N:ge(1):assertAlwaysTrue(), "modules.counter: N must be >= 1, but is: "..tostring(N) )
  
  local res = {kind="counter"}
  res.inputType = types.null()
  res.outputType = ty
  res.sdfInput = SDF{1,1}
  res.sdfOutput = SDF{1,1}
  res.stateful=true
  res.delay=0
  res.name = J.sanitize("Counter_"..tostring(ty).."_"..tostring(N_orig))
  res.globals={}
  N:appendGlobals(res.globals)
  
  if terralib~=nil then res.terraModule = MT.counter(res,ty,N) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    
    local sPhase = systolicModule:add( Ssugar.regByConstructor( ty, fpgamodules.sumwrap(ty,N-1) ):CE(true):setReset(0):instantiate("phase") )
    
    local pipelines = {}
    table.insert( pipelines, sPhase:setBy( S.constant(1,ty) ) )
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", S.parameter( "inp", types.null() ), sPhase:get(), "process_output", pipelines, nil, CE) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:reset()},S.parameter("reset",types.bool()) ) )

    return systolicModule
  end

  return rigel.newFunction(res)
  
end)

modules.toVarlen = memoize(
  function(ty,cnt)
    err( types.isType(ty), "toVarlen: type must be rigel type" )
    err( types.isBasic(ty),"toVarlen: input should be basic" )
    err(type(cnt)=="number", "toVarlen: cnt must be number")
    
    local res = {kind="toVarlen"}
    res.inputType = types.Handshake(ty)
    res.outputType = types.HandshakeVarlen(ty)
    res.sdfInput = SDF{1,1}
    res.sdfOutput = SDF{1,1}
    res.stateful=true
    res.delay=0
    res.name = sanitize("ToVarlen_"..tostring(ty).."_"..tostring(cnt))

    function res.makeSystolic()
      local vstring = [[
module ]]..res.name..[[(input wire CLK, input wire reset, input wire []]..(ty:verilogBits())..[[:0] process_input, output wire []]..(ty:verilogBits()+1)..[[:0] process_output, input wire ready_downstream, output wire ready);
  parameter INSTANCE_NAME="INST";

  // value 0 means we're not in a frame (waiting for data)
  reg [31:0] count = 32'd0;
  reg []]..(ty:verilogBits())..[[:0] pbuf; // top bit is valid bit

  assign ready = ready_downstream;
  assign process_output[]]..(ty:verilogBits())..[[:0] = pbuf;
  assign process_output[]]..(ty:verilogBits()+1)..[[] = (count>32'd0) || pbuf[]]..(ty:verilogBits())..[[];

  always @(posedge CLK) begin
    if(reset) begin
      count <= 32'd0;
      pbuf <= ]]..(ty:verilogBits()+1)..[['d0;
    end else begin
      if (ready_downstream) begin
        pbuf <= process_input;

        if (process_input[]]..(ty:verilogBits())..[[]) begin
          if (count==32'd]]..(cnt-1)..[[) begin
            count <= 32'd0;
          end else begin
            count <= count+32'd1;
          end
        end
      end
    end
  end
endmodule

]]

      local fns = {}
      fns.reset = S.lambda( "reset", S.parameter("resetinp",types.null()), S.null(), "resetout",nil,S.parameter("reset",types.bool()))

      local inp = S.parameter("process_input",types.lower(res.inputType))
      fns.process = S.lambda("process",inp,S.tuple{S.constant(ty:fakeValue(),ty),S.constant(true,types.bool()),S.constant(true,types.bool())}, "process_output")

      local downstreamReady = S.parameter("ready_downstream", types.bool())
      fns.ready = S.lambda("ready", downstreamReady, downstreamReady, "ready" )
      
      local ToVarlenSys = systolic.module.new(res.name, fns, {}, true,nil, vstring,{process=0,reset=0})

      return ToVarlenSys
    end

    return rigel.newFunction(res)
  end)

return modules
