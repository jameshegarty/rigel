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
  MT = require("generators.modulesTerra")
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

  assert( tab[1].type:isArray() )
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
-- inputType: if g is a generator, we won't know its input type. Allow user to explicitly pass it.
modules.compose = memoize(function( name, f, g, generatorStr, inputType, inputSDF )
  err( type(name)=="string", "first argument to compose must be name of function")
  err( rigel.isFunction(f), "compose: second argument should be rigel module")
  err( rigel.isPlainFunction(g) or inputType~=nil, "compose: third argument should be plain rigel function, but is: ",g)

  if inputType~=nil then
    err( types.isType(inputType), "compose: inputType should be type, but is: "..tostring(inputType) )
  else
    inputType = g.inputType
  end

  if inputSDF~=nil then
    err( SDF.isSDF(inputSDF),"compose: inputSDF should be SDF")
  else
    inputSDF = g.sdfInput
  end

  name = J.verilogSanitize(name)

  local inp = rigel.input( inputType, inputSDF )
  local gvalue = rigel.apply(J.verilogSanitize(name.."_g"),g,inp)

  return modules.lambda( name, inp, rigel.apply(J.verilogSanitize(name.."_f"),f,gvalue), nil, generatorStr )
end)


-- *this should really be in examplescommon.t
-- This converts SoA to AoS
-- ie {Arr2d(a,W,H),Arr2d(b,W,H),...} to Arr2d({a,b,c},W,H)
-- if asArray==true then converts {Arr2d(a,W,H),Arr2d(b,W,H),...} to Arr2d(a[N],W,H). This requires a,b,c be the same...
-- framedW, framedH, if not nil, will let us operate on ParSeqs
modules.SoAtoAoS = memoize(function( W, H, typelist, asArray, framedW, framedH )
  err( type(W)=="number", "SoAtoAoS: first argument should be number (width)")
  err( type(H)=="number", "SoAtoAoS: second argument should be number (height)")
  err( W*H>0, "SoAtoAoS: W*H must be >0, W: ",W," H:",H)
  err( type(typelist)=="table", "SoAtoAoS: typelist must be table")
  err( J.keycount(typelist)==#typelist, "SoAtoAoS: typelist must be lua array")
  err( asArray==nil or type(asArray)=="boolean", "SoAtoAoS: asArray must be bool or nil")
  if asArray==nil then asArray=false end

  for k,v in ipairs(typelist) do
    err(types.isType(v),"SoAtoAoS: typelist index "..tostring(k).." must be rigel type")
    err( v:isData(),"SoAtoAoS: input should be list of data type, but is: "..tostring(v))
  end

  local res
  if (W*H)%2==0 and asArray==false then
    -- codesize optimization (make codesize log(n) instead of linear)
 
    local C = require "generators.examplescommon"

    local itype = types.rv(types.Par(types.tuple( J.map(typelist, function(t) return types.array2d(t,W,H) end) )))
    local I = rigel.input( itype )

    local IA = {}
    local IB = {}
    for k,t in ipairs(typelist) do
      local i = rigel.apply("II"..tostring(k-1), C.index(itype:deInterface(),k-1), I)
      
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

    res = modules.lambda(verilogSanitize("SoAtoAoS_pow2_W"..tostring(W).."_H"..tostring(H).."_types"..tostring(typelist).."_asArray"..tostring(asArray).."_framedW"..tostring(framedW).."_framedH"..tostring(framedH)), I, out)

  else
    res = { kind="SoAtoAoS", W=W, H=H, asArray = asArray }
    
    res.inputType = types.tuple( J.map(typelist, function(t) return types.array2d(t,W,H) end) )
    if asArray then
      J.map( typelist, function(n) err(n==typelist[1], "if asArray==true, all elements in typelist must match, but tuple item 0 types is:",typelist[1]," but item ? type is:",n) end )
      res.outputType = types.array2d(types.array2d(typelist[1],#typelist),W,H)
    else
      res.outputType = types.array2d(types.tuple(typelist),W,H)
    end
    
    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
    res.delay = 0
    res.stateful=false
    res.name = verilogSanitize("SoAtoAoS_W"..tostring(W).."_H"..tostring(H).."_types"..tostring(typelist).."_asArray"..tostring(asArray).."_framedW"..tostring(framedW).."_framedH"..tostring(framedH))
    
    function res.makeSystolic()
      local systolicModule = Ssugar.moduleConstructor(res.name)
      local sinp = S.parameter("process_input", res.inputType:lower() )
      local arrList = {}
      for y=0,H-1 do
        for x=0,W-1 do
          local r = S.tuple(J.map(J.range(0,#typelist-1), function(i) return S.index(S.index(sinp,i),x,y) end))
          if asArray then r = S.cast(r, types.array2d(typelist[1],#typelist) ) end
          table.insert( arrList, r )
        end
      end
      systolicModule:addFunction( S.lambda("process", sinp, S.cast(S.tuple(arrList),rigel.lower(res.outputType)), "process_output") )
      return systolicModule
    end

    res = rigel.newFunction(res)
  end

  if framedW~=nil then
    -- hackity hack
    local inputType = types.rv(types.tuple( J.map(typelist, function(t) return types.ParSeq(types.array2d(t,W,H),framedW,framedH) end) ))
    local outputType

    if asArray then
      outputType = types.rv(types.ParSeq(types.array2d(types.Array2d(typelist[1],#typelist),W,H),framedW,framedH ))
    else
      outputType = types.rv(types.ParSeq(types.array2d(types.tuple(typelist),W,H),framedW,framedH ))
    end
    
    assert(res.inputType:lower()==inputType:lower())
    assert(res.outputType:lower()==outputType:lower())
    res.inputType = inputType
    res.outputType = outputType
  end

  if terralib~=nil then res.terraModule = MT.SoAtoAoS(res,W,H,typelist,asArray) end

  return res
end)

-- Zips Seq types (this is just a trivial conversion)
-- takes rv([A{W,H},B{W,H},C{W,H}]) to rv({A,B,C}{W,H})
-- typelist: list of {A,B,C} schedule types
modules.ZipSeq = memoize(function( var, W, H, ... )
  err( Uniform.isUniform(W) or type(W)=="number", "ZipSchedules: first argument should be number (width), but is:",W)
  err( Uniform.isUniform(H) or type(H)=="number", "ZipSchedules: second argument should be number (height), but is:",H)
  local typelist = {...}
  err( type(typelist)=="table", "ZipSchedules: typelist must be table")
  err( J.keycount(typelist)==#typelist, "ZipSchedules: typelist must be lua array")
  assert(type(var)=="boolean")

  local typeString = ""
  local itype = {}

  -- if all schedules are Seq(Par(data)), get rid of the Pars as a courtesy
  local terminal = true
  for k,v in ipairs(typelist) do
    err( types.isType(v),"ZipSchedules: typelist index "..tostring(k).." must be rigel type")
    err( v:isSchedule(),"ZipSchedules: input should be list of schedule types, but is: "..tostring(v))
    if (v:is("Par") and v.over:isData())==false then
      terminal = false
    end
    
    typeString = typeString.."_"..tostring(v)
    if var then
      table.insert(itype,types.VarSeq(v,W,H))
    else
      table.insert(itype,types.Seq(v,W,H))
    end
  end

  local inputType = types.rv(types.tuple(itype))

  local G = require "generators.core"

  local res = G.Function{"ZipSchedules_W"..tostring(W).."_H"..tostring(H).."_var"..tostring(var)..typeString,types.rv(types.Par(inputType:lower())),SDF{1,1},function(inp) return inp end}

  assert(res.inputType:lower()==inputType:lower())
  res.inputType = inputType

  local typeOut = types.Tuple(typelist)
  if terminal then
    local newlist = {}
    for k,v in ipairs(typelist) do
      table.insert(newlist,v.over)
    end
    typeOut = types.Par(types.Tuple(newlist))
  end
  
  -- hackity hack
  local outputType
  if var then
    outputType = types.rv(types.VarSeq(typeOut,W,H))
  else
    outputType = types.rv(types.Seq(typeOut,W,H))
  end

  assert(res.outputType:lower()==outputType:lower())
  res.outputType = outputType
  
  return res
end)

-- Converst {Handshake(a), Handshake(b)...} to Handshake{a,b}
-- typelist should be a table of pure types
-- WARNING: ready depends on ValidIn
-- arraySize: if not nil, accept an array instead of a tuple (typelist should just be a type then)
modules.packTuple = memoize(function( typelist, disableFIFOCheck, arraySize, X )
  err( type(typelist)=="table", "packTuple: type list must be table, but is: "..tostring(typelist) )
  err( disableFIFOCheck==nil or type(disableFIFOCheck)=="boolean", "packTuple: disableFIFOCheck must be nil or bool" )
  err( X==nil, "packTuple: too many arguments" )
  
  local res = {kind="packTuple", disableFIFOCheck = disableFIFOCheck}

  for k,t in ipairs(typelist) do
    err( types.isType(t),"packTuple: typelist should be list of types, but is:",t)
    err(t:isRV(),"packTuple: should be list of RV types, but is: "..tostring(t))
  end
  
  if arraySize==nil then
    res.inputType = types.tuple(typelist)
    local schedList = {}
    local schedListOver = {}
    local allPar = true -- backwards compatibility hack

    if typelist[1]==types.RV() then
      -- handshake trigger tuple
      res.outputType=types.RV()
    else
      for k,v in ipairs(typelist) do
        table.insert(schedList,v.over)
        table.insert(schedListOver,v.over.over)
        if v.over:is("Par")==false then allPar=false end
      end
      if allPar then
        res.outputType = types.RV(types.Par(types.tuple(schedListOver)))
      else
        res.outputType = types.RV(types.tuple(schedList))
      end
    end
  else
    print("NYI - packTuple over an array")
    assert(false)
  end
    
  res.stateful = false
  res.sdfOutput = SDF{1,1}
  res.sdfInput = SDF(J.map(typelist, function(n)  return {1,1} end))
  res.name = J.sanitize("packTuple_"..tostring(typelist))

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
      
    local inputValues = S.tuple(J.map(J.range(0,#typelist-1), function(i) return S.index(S.index(sinp,i),0) end))
    
    -- valid bit is the AND of all the inputs
    local validInList = J.map(J.range(0,#typelist-1),function(i) return S.index(S.index(sinp,i),1) end)

    local validOut = J.foldt(validInList,function(a,b) return S.__and(a,b) end,"X")
  
    local pipelines={}
    
    local downstreamReady = S.parameter("ready_downstream", types.bool())
    
    -- we only want this module to be ready if _all_ streams have data.
    -- WARNING: this makes ready depend on ValidIn
    local readyOutList = {}
    for i=1,#typelist do
      -- if this stream doesn't have data, let it run regardless.
      local valid_i
      if typelist[1]==types.RV() then -- HandshakeTrigger mode
        valid_i = S.index(sinp,i-1)
      else
        valid_i = S.index(S.index(sinp,i-1),1)
      end
      table.insert( readyOutList, S.__or(S.__and( downstreamReady, validOut), S.__not(valid_i) ) )
    end
  
    local readyOut = S.tuple(readyOutList)
    if arraySize~=nil then
      assert(false)
      readyOut = S.cast(readyOut, types.array2d(types.bool(),#typelist) )
    end
    
    --if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process(S.tuple(concat(concat(validInFullList,{validOut}),concat(readyOutList,{downstreamReady})))) ) end
    
    local out
    if typelist[1]==types.RV() then -- HandshakeTrigger mode
      out = validOut
    else
      out = S.tuple{inputValues, validOut}
    end
    systolicModule:addFunction( S.lambda("process", sinp, out, "process_output", pipelines) )
    
    systolicModule:addFunction( S.lambda("ready", downstreamReady, readyOut, "ready" ) )

    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- lift rv->rv to rv->rvV
modules.liftBasic = memoize(function(f)
  err(rigel.isFunction(f),"liftBasic argument should be darkroom function")

  local res = {kind="liftBasic", fn = f}

  err( f.inputType:isrv(), "liftBasic: f input type should be rv, but is: "..tostring(f.inputType))
  err( f.outputType:isrv(), "liftBasic: f output type should be rv, but is: "..tostring(f.outputType))
  
  res.inputType = f.inputType
  res.outputType = types.rvV(f.outputType.over)
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
  res.RVDelay = f.RVDelay
  res.delay = f.delay
  res.stateful = f.stateful
  res.name = J.sanitize("LiftBasic_"..f.name)

  if terralib~=nil then res.terraModule = MT.liftBasic(res,f) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local inner = systolicModule:add( f.systolicModule:instantiate("LiftBasic_inner") )
    local sinp = S.parameter("process_input", rigel.lower(res.inputType) )

    local CE
    if f.stateful or f.delay>0 then
      CE = S.CE("CE")
    end
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

    local VALID
    if onlyWire and srcFn.implicitValid==false then
      VALID = srcFn:getValid()
    end

    local fn = Ssugar.lambdaConstructor( fnname, srcFn:getInput().type, srcFn:getInput().name, J.sel(srcFn.implicitValid,nil,srcFn:getValid().name) )
    fn:setOutput( inner[fnname]( inner, srcFn:getInput(), VALID ), srcFn:getOutputName() )
    fn:setCE(srcFn:getCE())
    res:addFunction(fn)

    local readySrcFn = systolicModule:lookupFunction(fnname.."_ready")
    if readySrcFn~=nil then
      res:addFunction( S.lambda(fnname.."_ready", readySrcFn:getInput(), inner[fnname.."_ready"]( inner, readySrcFn:getInput() ), readySrcFn:getOutputName(), nil, readySrcFn:getValid(), readySrcFn:getCE() ) )
    end

    local resetSrcFn = systolicModule:lookupFunction(fnname.."_reset")
    if resetSrcFn~=nil then
      res:addFunction( S.lambda(fnname.."_reset", resetSrcFn:getInput(), inner[fnname.."_reset"]( inner, resetSrcFn:getInput() ), resetSrcFn:getOutputName(), nil, resetSrcFn:getValid() ) )
    end

    res:setDelay(fnname,systolicModule:getDelay(fnname))
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

    if srcFn:getInput().type==types.Interface() then
      sinp = S.parameter(fnname.."_input", types.null() )
    else
      sinp = S.parameter(fnname.."_input", types.lower(types.V(types.Par(srcFn:getInput().type))) )
    end
    
    local svalid = S.parameter(fnname.."_valid", types.bool())
    local runable = S.__and(inner[prefix.."ready"](inner), S.index(sinp,1) ):disablePipelining()

    local out = inner[fnname]( inner, S.index(sinp,0), runable )

    if out.type~=types.null() then
      out = S.tuple{ out, S.__and( runable,svalid ):disablePipelining() }
    end
    
    
    if systolicModule:lookupFunction(prefix.."reset")~=nil then
      local RST = S.parameter(prefix.."reset",types.bool())
      if systolicModule:lookupFunction(prefix.."reset"):isPure() then
        RST=S.constant(false,types.bool())
      end
      
      res:addFunction( S.lambda(prefix.."reset", S.parameter(prefix.."r",types.null()), inner[prefix.."reset"](inner), "ro", {}, RST) )
    end

    local pipelines = {}

    local CE = S.CE("CE")
    res:addFunction( S.lambda(fnname, sinp, out, fnname.."_output", pipelines, svalid, CE ) )
    res:addFunction( S.lambda(prefix.."ready", S.parameter(prefix.."readyinp",types.null()), inner[prefix.."ready"](inner), prefix.."ready", {} ) )
  end

  passthroughSystolic( res, systolicModule, inner, passthroughFns )
  return res
end

local function waitOnInputSystolic( systolicModule, fns, passthroughFns )
  local res = Ssugar.moduleConstructor(J.sanitize("WaitOnInput_"..systolicModule.name))
  local inner = res:add( systolicModule:instantiate("WaitOnInput_inner") )

  for _,fnname in pairs(fns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    err( systolicModule:getDelay(prefix.."ready")==0, "ready bit should not be pipelined")

    local printInst
    if DARKROOM_VERBOSE then printInst = res:add( S.module.print( types.tuple{types.bool(),types.bool(),types.bool(),types.bool()}, "WaitOnInput "..systolicModule.name.." ready %d validIn %d runable %d RST %d", true ):instantiate(prefix.."printInst") ) end

    local sinp = S.parameter(fnname.."_input", rigel.lower(rigel.V(types.Par(srcFn:getInput().type))) )

    local svalid = S.parameter(fnname.."_valid", types.bool())
    local runable = S.__or(S.__not(inner[prefix.."ready"](inner)), S.index(sinp,1) ):disablePipelining()

    local out = inner[fnname]( inner, S.index(sinp,0), runable )

    local RST = S.parameter(prefix.."reset",types.bool())
--    if systolicModule:lookupFunction(prefix.."reset"):isPure() then RST=S.constant(false,types.bool()) end

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
modules.reduceThroughput = memoize(function(A,factor,X)
  err( type(factor)=="number", "reduceThroughput: second argument must be number (reduce factor)" )
  err( factor>1, "reduceThroughput: reduce factor must be >1" )
  err( math.floor(factor)==factor, "reduceThroughput: reduce factor must be an integer" )
  assert(X==nil)
  err( types.isType(A) and A:isData(), "reduceThroughput: input type should be Data, but is: "..tostring(A) )
  
  local res = {kind="reduceThroughput",factor=factor}
  res.inputType = types.rv(types.Par(A))
  res.outputType = types.rRvV(types.Par(A))
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
modules.waitOnInput = memoize(function( f, X )
  err(rigel.isFunction(f),"waitOnInput argument should be darkroom function")
  err( X==nil, "waitOnInput: too many arguments" )
  local res = {kind="waitOnInput", fn = f}
  err( f.inputType:isrv(), "waitOnInput of fn '"..f.name.."': input type should be rv, but is: "..tostring(f.inputType))
  err( f.outputType:isrRvV(), "waitOnInput: output type should be rRvV, but is: "..tostring(f.outputType))
  res.inputType = types.rV(f.inputType.over)
  res.outputType = types.rRV(f.outputType.over)

  err(f.delay == math.floor(f.delay), "waitOnInput, delay is fractional?")
  err( type(f.sdfInput)=="table", "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput
  err( type(f.stateful)=="boolean", "Missing stateful annotation for fn "..f.kind)
  res.stateful = f.stateful
  res.delay = f.delay
  res.RVDelay = f.RVDelay
  res.name = J.verilogSanitize("WaitOnInput_"..f.name)
  res.inputBurstiness = f.inputBurstiness
  res.outputBurstiness = f.outputBurstiness
    
  if terralib~=nil then res.terraModule = MT.waitOnInput(res,f) end

  function res.makeSystolic()
    assert( S.isModule(f.systolicModule) )
    local sm = waitOnInputSystolic( f.systolicModule, {"process"},{} )
    return sm
  end

  return rigel.newFunction(res)
end)

local function liftDecimateSystolic( systolicModule, liftFns, passthroughFns, handshakeTrigger, includeCE, X )
  if Ssugar.isModuleConstructor(systolicModule) then systolicModule=systolicModule:toModule() end
  assert( S.isModule(systolicModule) )
  assert(type(handshakeTrigger)=="boolean")
  assert(type(includeCE)=="table")
  
  local res = Ssugar.moduleConstructor( J.sanitize("LiftDecimate_"..systolicModule.name) )
  local inner = res:add( systolicModule:instantiate("LiftDecimate") )

  for k,fnname in pairs(liftFns) do
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
      sinp = S.parameter(fnname.."_input", rigel.lower(types.V(types.Par(srcFn.inputParameter.type))) )
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
      print("liftDecimateDystolic of "..systolicModule.name.." NYI type "..tostring(pout.type))
      assert(false)
    end
    local validout = pout_valid

    if srcFn.inputParameter.type~=types.null() then
      validout = S.__and(pout_valid,validi)
    end

    local CE
    if includeCE[k] then
      CE = S.CE(prefix.."CE")
    end
--    local CE
--    if srcFn.CE~=nil then
--      CE = S.CE(prefix.."CE")
--    end
    
    if pout_data==nil then
      res:addFunction( S.lambda(fnname, sinp, validout, fnname.."_output",nil,nil,CE ) )
    else
      res:addFunction( S.lambda(fnname, sinp, S.tuple{pout_data, validout}, fnname.."_output",nil,nil,CE ) )
    end
    
    if systolicModule:lookupFunction(prefix.."reset")~=nil then
      -- stateless modules don't have a reset
      res:addFunction( S.lambda(prefix.."reset", S.parameter("r",types.null()), inner[prefix.."reset"](inner), "ro", {},S.parameter(prefix.."reset",types.bool())) )
    end

    if srcFn.inputParameter.type==types.null() and handshakeTrigger==false then
      -- if fn has null input, ready shouldn't return anything
      res:addFunction( S.lambda(prefix.."ready", S.parameter(prefix.."readyinp",types.null()), nil, prefix.."ready", {} ) )
    else
      res:addFunction( S.lambda(prefix.."ready", S.parameter(prefix.."readyinp",types.null()), S.constant(true,types.bool()), prefix.."ready", {} ) )
    end
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
  err( f.inputType:isrv() or f.inputType==types.Interface(), "liftDecimate: fn '"..f.name.."' input type should be rv, but is: "..tostring(f.inputType) )
  err( f.outputType:isrvV(), "liftDecimate: fn '"..f.name.."' output type should be rvV, but is: "..tostring(f.outputType) )

  res.name = J.sanitize("LiftDecimate_"..f.name)
  res.inputType = types.rV(f.inputType.over)
  res.outputType = types.rRV(f.outputType.over)

  res.inputBurstiness = f.inputBurstiness
  res.outputBurstiness = f.outputBurstiness
  
  err(type(f.stateful)=="boolean", "Missing stateful annotation for "..f.kind)
  res.stateful = f.stateful

  err( rigel.SDF==false or SDFRate.isSDFRate(f.sdfInput), "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput

  res.RVDelay = f.RVDelay
  res.delay = f.delay
  
  res.requires = {}
  for inst,fnmap in pairs(f.requires) do for fnname,_ in pairs(fnmap) do J.deepsetweak(res.requires,{inst,fnname},1) end end
  res.provides = {}
  for inst,fnmap in pairs(f.provides) do for fnname,_ in pairs(fnmap) do J.deepsetweak(res.provides,{inst,fnname},1) end end

  if terralib~=nil then res.terraModule = MT.liftDecimate(res,f) end

  function res.makeSystolic()
    err( S.isModule(f.systolicModule), "Missing/incorrect systolic for "..f.name )
    return liftDecimateSystolic( f.systolicModule, {"process"}, {}, handshakeTrigger, {f.stateful or f.delay>0} )
  end

  local res = rigel.newFunction(res)

  return res
end)

-- converts V->RV to RV->RV
modules.RPassthrough = memoize(function(f)
  local res = {kind="RPassthrough", fn = f}
  --rigel.expectV(f.inputType)
  err( f.inputType:isrV(),"RPassthrough: fn input should br rV, but is: "..tostring(f.inputType) )
  err( f.outputType:isrRV(),"RPassthrough: fn output type should be rRV, but is: "..tostring(f.outputType) )
  res.inputType = types.rRV(f.inputType:deInterface())
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
    local CE
    if f.delay>0 or f.stateful then
      CE = S.CE("CE")
    end
    
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

local function liftHandshakeSystolic( systolicModule, liftFns, passthroughFns, hasReadyInput, hasCE, hasReset, X )
  if Ssugar.isModuleConstructor(systolicModule) then systolicModule = systolicModule:toModule() end
  err( S.isModule(systolicModule), "liftHandshakeSystolic: systolicModule not a systolic module?" )
  assert(type(hasReadyInput)=="table")
  assert(type(hasCE)=="table")
  assert(type(hasReset)=="boolean")
  assert(X==nil)
  
  local res = Ssugar.moduleConstructor( J.sanitize("LiftHandshake_"..systolicModule.name) ):onlyWire(true):parameters({INPUT_COUNT=0, OUTPUT_COUNT=0})
  local inner = res:add(systolicModule:instantiate( J.sanitize("inner") ))

  if Ssugar.isModuleConstructor(systolicModule) then systolicModule:complete(); systolicModule=systolicModule.module end

  local resetPipelines = {}
  
  passthroughSystolic( res, systolicModule, inner, passthroughFns, true )

  if res:lookupFunction("reset")==nil and hasReset then
    -- we need a reset for the shift register or something?
    res:addFunction( Ssugar.lambdaConstructor( "reset", types.null(), "reset" ) )
  end
    
  for K,fnname in pairs(liftFns) do
    local srcFn = systolicModule:lookupFunction(fnname)

    local prefix = fnname.."_"
    if fnname=="process" then prefix="" end

    local printInst 
    --if DARKROOM_VERBOSE then printInst = res:add( S.module.print( types.tuple{types.bool(), srcFn:getInput().type.list[1],types.bool(),srcFn:getOutput().type.list[1],types.bool(),types.bool(),types.bool(),types.uint(16), types.uint(16)}, fnname.." RST %d I %h IV %d O %h OV %d readyDownstream %d ready %d outputCount %d expectedOutputCount %d"):instantiate(prefix.."printInst") ) end

    local outputCount
    --if STREAMING==false and DARKROOM_VERBOSE then outputCount = res:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIf() ):CE(true):instantiate(prefix.."outputCount") ) end

    local pinp = S.parameter(fnname.."_input", srcFn:getInput().type )

    local downstreamReady
    local CE

    if hasReadyInput[K] then
      downstreamReady = S.parameter(prefix.."ready_downstream", types.bool())
      CE = downstreamReady
    else
      downstreamReady = S.parameter(prefix.."ready_downstream", types.null())
      CE = S.constant(true,types.bool())
    end

    local pout = inner[fnname](inner,pinp,S.constant(true,types.bool()), J.sel(hasCE[K],CE,nil) )

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
      SR = res:add( fpgamodules.shiftRegister( types.bool(), systolicModule:getDelay(fnname), false, true ):instantiate( J.sanitize(prefix.."validBitDelay") ) )
    
      local srvalue = SR:process(S.constant(true,types.bool()), S.constant(true,types.bool()), CE )
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

    err( systolicModule.functions[prefix.."ready"]~=nil, "LiftHandshake, module is missing ready fn? module '"..systolicModule.name.."', fn "..tostring(prefix).."ready")

    if hasReadyInput[K] and systolicModule.functions[prefix.."ready"].output~=nil and systolicModule.functions[prefix.."ready"].output.type~=types.null() then
      readyOut = systolic.__and(inner[prefix.."ready"](inner),downstreamReady)
    else
      readyOut = inner[prefix.."ready"](inner)
    end

    local pipelines = {}
    --if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple{ rst, S.index(pinp,0), S.index(pinp,1), S.index(out,0), S.index(out,1), downstreamReady, readyOut, outputCount:get(), S.instanceParameter("OUTPUT_COUNT",types.uint(16)) } ) ) end
    --if STREAMING==false and DARKROOM_VERBOSE then table.insert(pipelines,  outputCount:setBy(outvalid, S.__not(rst), CE) ) end
    
    res:addFunction( S.lambda(fnname, pinp, out, fnname.."_output", pipelines ) ) 
    
    if pout.type~=types.null() and hasReset then
      --err(res:lookupFunction("reset")~=nil, "Reset is missing on module '",systolicModule.name,"'? ",systolicModule)
      table.insert(resetPipelines, SR:reset( nil, res:lookupFunction("reset"):getValid() ))
    end
    
    assert( systolicModule:getDelay(prefix.."ready")==0 ) -- ready bit calculation can't be pipelined! That wouldn't make any sense
    
    res:addFunction( S.lambda(prefix.."ready", downstreamReady, readyOut, prefix.."ready" ) )

    res:setDelay(fnname,systolicModule:getDelay(fnname))
  end

  if hasReset then
    assert(res:lookupFunction("reset")~=nil)

    for _,p in pairs(resetPipelines) do
      assert( Ssugar.isFunctionConstructor(res:lookupFunction("reset")) )
      res:lookupFunction("reset"):addPipeline(p)
    end
  end
  
  return res
end

-- takes V->RV to Handshake->Handshake
-- if input type is null, and handshakeTrigger==true, we produce input type HandshakeTrigger
-- if input type is null, and handshakeTrigger==false, we produce input type null
modules.liftHandshake = memoize(function( f, handshakeTrigger, X )
  err( X==nil, "liftHandshake: too many arguments" )
    
  local res = {kind="liftHandshake", fn=f}
  err( f.inputType:isrV(), "liftHandshake of fn '"..f.name.."': expected rV input interface type, but is "..tostring(f.inputType))
  err( f.outputType:isrRV() ,"liftHandshake: expected rRV output type, but is: "..tostring(f.outputType))

  res.inputType = types.RV(f.inputType.over)
  res.outputType = types.RV(f.outputType.over)

  res.inputBurstiness = f.inputBurstiness
  res.outputBurstiness = f.outputBurstiness
  
  res.name = J.sanitize("LiftHandshake_"..f.name)

  err( rigel.SDF==false or SDFRate.isSDFRate(f.sdfInput), "Missing SDF rate for fn "..f.kind)
  res.sdfInput, res.sdfOutput = f.sdfInput, f.sdfOutput

  err( type(f.delay)=="number","Module is missing delay? ",f)
  err(f.delay==math.floor(f.delay),"delay is fractional ?!, "..f.kind)

  if f.RVDelay~=nil then
    res.delay = f.RVDelay + f.delay
  else
    --res.delay = math.max(1, f.delay)
    res.delay = f.delay
  end
  
  err(type(f.stateful)=="boolean", "Missing stateful annotation, "..f.kind)
  res.stateful = f.stateful --f.stateful  valid bit shift register is stateful

  res.requires = {}
  for inst,fnmap in pairs(f.requires) do for fnname,_ in pairs(fnmap) do J.deepsetweak(res.requires,{inst,fnname},1) end end
  res.provides = {}
  for inst,fnmap in pairs(f.provides) do for fnname,_ in pairs(fnmap) do J.deepsetweak(res.provides,{inst,fnname},1) end end

  if terralib~=nil then res.terraModule = MT.liftHandshake(res,f,f.delay) end

  function res.makeSystolic()
    assert( S.isModule(f.systolicModule) )
    local passthrough = {}
    if f.stateful then passthrough={"reset"} end
    return liftHandshakeSystolic( f.systolicModule, {"process"},passthrough,{true},{f.stateful or f.delay>0},f.stateful )
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


-- map f:RV(scheduleType)->RV(scheduleType)
-- over an RV(scheduleType)[W,H] array
modules.mapOverInterfaces = memoize(function( f, W_orig, H_orig, X )
  err( rigel.isFunction(f), "first argument to mapOverInterfaces must be Rigel module, but is ",f )
  err( f.inputType:isRV(), "mapOverInterfaces: fn input must be RV, but is: ",f.inputType )
  err( f.outputType:isRV(), "mapOverInterfaces: fn output must be RV, but is: ",f.outputType )

  local W = Uniform(W_orig):toNumber()
  local H = Uniform(H_orig):toNumber()
    
  local G = require "generators.core"

  return G.Function{ "MapOverInterfaces_"..f.name.."_"..tostring(W_orig).."_"..tostring(H_orig), types.Array2d( f.inputType, W_orig, H_orig ),
    function(inp)
      local outt = {}
      for h=0,H-1 do
        for w=0,W-1 do
          table.insert(outt, f(rigel.selectStream( "str"..tostring(w).."_"..tostring(h), inp, w, h )) )
        end
      end
      return rigel.concatArray2d( "moiout", outt, W, H )
    end}
end)

-- f : ( A, B, ...) -> C (darkroom function)
-- map : ( f, A[n], B[n], ...) -> C[n]
-- allowStateful: allow us to make stateful modules (use this more like 'duplicate')
modules.map = memoize(function( f, W_orig, H_orig, allowStateful, X )
  err( rigel.isFunction(f), "first argument to map must be Rigel module, but is ",f )
  assert(allowStateful==nil or type(allowStateful)=="boolean")
  local W = Uniform(W_orig)  
  --err( Uniform(W)=="number", "width must be number")
  err( X==nil, "map: too many arguments" )
  
  if H_orig==nil then 
    return modules.map(f,W,1,allowStateful)
  end

  local H = Uniform(H_orig)
  --err( type(H)=="number", "map: H must be number" )

  err( f.inputType:isrv(), "map: error, mapping a module with a non-rv input type? name:",f.name," ",f.inputType," W:",W_orig," H:",H_orig)
  err( f.outputType==types.Interface() or f.outputType:isrv(), "map: error, mapping a module with a non-rv output type? name:",f.name," ",f.outputType)
  err( f.inputType:deInterface():isData(), "map: error, map can only map a fully parallel function, but is: name:",f.name," inputType:",f.inputType)
  err( f.outputType:deInterface():isData(), "map: error, map can only map a fully parallel function, but is: name:",f.name," outputType:",f.outputType)
       
  W,H = W:toNumber(), H:toNumber()
  
  err( W*H==1 or f.stateful==false or allowStateful==true,"map: mapping a stateful function ("..f.name.."), which will probably not work correctly. (may execute out of order) W="..tostring(W)..",H="..tostring(H)," allowStateful=",tostring(allowStateful) )
  
  local res
  
  if (W*H)%2==0 then
    -- special case: this is a power of 2, so we can easily split it, to save compile time 
    -- (produces log(n) sized code instead of linear)
    
    local C = require "generators.examplescommon"
    local I = rigel.input( types.rv(types.Par(types.array2d( f.inputType:deInterface(), W, H ))) )
    local ic = rigel.apply( "cc", C.cast( types.array2d( f.inputType:deInterface(), W, H ), types.array2d( f.inputType:deInterface(), W*H ) ), I)

    local ica = rigel.apply("ica", C.slice(types.array2d( f.inputType:deInterface(), W*H ),0,(W*H)/2-1,0,0), ic)
    local a = rigel.apply("a", modules.map(f,(W*H)/2,1,allowStateful), ica)

    local icb = rigel.apply("icb", C.slice(types.array2d( f.inputType:deInterface(), W*H ),(W*H)/2,(W*H)-1,0,0), ic)
    local b = rigel.apply("b", modules.map(f,(W*H)/2,1,allowStateful), icb)

    local out = rigel.concat("conc", {a,b})
    --local T = types.array2d( f.outputType, (W*H)/2 )
    out = rigel.apply( "cflat", C.flatten2( f.outputType:deInterface(), W*H ), out)
    out = rigel.apply( "cflatar", C.cast( types.array2d( f.outputType:deInterface(), W*H ), types.array2d( f.outputType:deInterface(), W,H ) ), out)

    res = modules.lambda("map_pow2_"..f.name.."_W"..tostring(W_orig).."_H"..tostring(H_orig).."_logn", I, out)
  else
    res = { kind="map", fn = f, W=W, H=H }

    res.inputType = types.array2d( f.inputType:deInterface(), W, H )
    res.outputType = types.Interface()
    if f.outputType~=types.Interface() then
      res.outputType = types.array2d( f.outputType:deInterface(), W, H )
    end
    err( type(f.stateful)=="boolean", "Missing stateful annotation ",f)

    res.stateful = f.stateful
    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
    res.delay = f.delay
    res.name = sanitize("map_"..f.name.."_W"..tostring(W_orig).."_H"..tostring(H_orig))

    res.requires = {}
    for inst,fnmap in pairs(f.requires) do for fnname,_ in pairs(fnmap) do J.deepsetweak(res.requires,{inst,fnname},1) end end
    res.provides = {}
    for inst,fnmap in pairs(f.provides) do for fnname,_ in pairs(fnmap) do J.deepsetweak(res.provides,{inst,fnname},1) end end
      
    function res.makeSystolic()
      local systolicModule = Ssugar.moduleConstructor(res.name)
      
      local inp = S.parameter("process_input", res.inputType:deInterface() )
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
      
      local CE
      if f.systolicModule.functions.process.CE~=nil then
        CE = S.CE("process_CE")
      end

      local finalOutput
      local pipelines

      finalOutput = S.cast( S.tuple( out ), res.outputType:deInterface() )

      systolicModule:addFunction( S.lambda("process", inp, finalOutput, "process_output", pipelines, nil, CE ) )
      if f.stateful then
        systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, S.parameter("reset",types.bool()) ) )
      end
      return systolicModule
    end
    
    res = rigel.newFunction(res)
  end

  if terralib~=nil then res.terraModule = MT.map(res,f,W,H) end

  return res
end)

-- lift a fn:DataType->DataType to a fn:DataType[V;S}->fn:DataType[V;S}
-- basically the same as regular map, but for parseq
-- scalar: is fn a scalar type?
modules.mapParSeq = memoize(function( fn, Vw_orig, Vh_orig, W_orig, H_orig, allowStateful, X )
  err( rigel.isPlainFunction(fn), "mapParSeq: first argument to map must be a plain Rigel function, but is ",fn )
  err( X==nil, "mapParSeq: too many arguments" )

  local Vw,Vh,W,H = Uniform(Vw_orig), Uniform(Vh_orig), Uniform(W_orig), Uniform(H_orig)

  local res

  local G = require "generators.core"
  local C = require "generators.examplescommon"
  
  if fn.inputType:isRV() or fn.outputType:isRV() then
    -- special case
    err( Vw:toNumber()==1 and Vh:toNumber()==1,"mapParSeq: if RV, vector width must be 1! but was Vw:",Vw_orig," Vh:",Vh_orig," fn:",fn.name)

    assert( fn.inputType:deInterface():isData() )
    local ty = fn.inputType:extractData()
    
    res = G.Function{"MapParSeq_fn"..fn.name.."_Vw"..tostring(Vw_orig).."_Vh"..tostring(Vh_orig).."_W"..tostring(W_orig).."_H"..tostring(H_orig),
                     types.RV(types.Array2d(ty,1,1)), SDF{1,1}, function(inp) return fn(G.Index{0}(inp)) end}

    assert( rigel.isPlainFunction(res) )
        
    -- hackity hack
    if fn.inputType~=types.Interface() then
      err( res.inputType:extractData():isArray(), "mapParSeq: internal error, function input type should be an array? but was: ",res.inputType)
      res.inputType = fn.inputType:replaceVar("over",types.ParSeq(res.inputType:extractData(),W_orig,H_orig))
    end
    
    if fn.outputType~=types.Interface() then
      -- fix: technically, we want this to return a parseq, I guess? But this also works...
      res.outputType = types.RV( types.Seq(fn.outputType.over,W_orig,H_orig) )
    end
  else
    err( fn.inputType:isrv(),"mapParSeq: input must be rv, but is: ",fn.inputType )
    err( fn.outputType==types.Interface() or fn.outputType:isrv(),"mapParSeq: output must be rv, but is: ",fn.outputType )


    local fnMapped
    fnMapped = modules.map( fn, Vw, Vh, allowStateful )
    
    res = G.Function{"MapParSeq_fn"..fn.name.."_Vw"..tostring(Vw_orig).."_Vh"..tostring(Vh_orig).."_W"..tostring(W_orig).."_H"..tostring(H_orig),
                     fnMapped.inputType,SDF{1,1},function(inp) return fnMapped(inp) end}

    assert( rigel.isPlainFunction(res) )

    -- hackity hack
    if fn.inputType~=types.Interface() then
      err( res.inputType:extractData():isArray(), "mapParSeq: internal error, function input type should be an array? but was: ",res.inputType)
      res.inputType = fn.inputType:replaceVar("over",types.ParSeq(res.inputType:extractData(),W_orig,H_orig))
    end
    
    if fn.outputType~=types.Interface() then
      err( res.outputType:extractData():isArray(), "mapParSeq: internal error, function output type should be an array? but was: ",res.outputType)
      res.outputType = fn.outputType:replaceVar("over",types.ParSeq(res.outputType:extractData(),W_orig,H_orig))
    end
  end
  
  return res
end)
 
-- take a fn:T1->T2 and map over a Seq, ie to f:T1{w,h}->T2{w,h}
-- this is basically a trivial conversion
modules.mapSeq = memoize(function( fn, W_orig, H_orig, X )
  err( rigel.isPlainFunction(fn), "mapSeq: first argument to map must be Rigel module, but is ",fn )
  err( fn.inputType.kind=="Interface", "mapSeq: fn input should be interface, but is: ",fn.inputType )
  err( fn.outputType.kind=="Interface", "mapSeq: fn '",fn.name,"' output should be interface, but is: ",fn.outputType )
  err( type(W_orig)=="number" or Uniform.isUniform(W_orig),"mapSeq: W must be number or uniform")
  err( type(H_orig)=="number" or Uniform.isUniform(H_orig),"mapSeq: H must be number or uniform")
       
  local G = require "generators.core"
    
  local res = G.Function{"MapSeq_fn"..fn.name.."_W"..tostring(W_orig).."_H"..tostring(H_orig),fn.inputType,fn.sdfInput,function(inp) return fn(inp) end}

  assert( rigel.isPlainFunction(res) )
  
  -- hackity hack
  if fn.inputType~=types.Interface() then
    local inputType = fn.inputType:replaceVar("over",types.Seq(fn.inputType:deInterface(),W_orig,H_orig))
    assert(res.inputType:lower()==inputType:lower())
    res.inputType = inputType
  end

  if fn.outputType~=types.Interface() then
    local outputType = fn.outputType:replaceVar("over",types.Seq(fn.outputType:deInterface(),W_orig,H_orig))
--    print("MAPSEQ",res.outputType,outputType)
--    print("MAPSEQ_low",res.outputType:lower(),outputType:lower())
    assert(res.outputType:lower()==outputType:lower())
    res.outputType = outputType
  end
  
  return res
end)

-- take a fn:T1->T2 and map over a Seq, ie to f:T1{w,h}->T2{w,h}
-- this is basically a trivial conversion
modules.mapVarSeq = memoize(function( fn, W_orig, H_orig, X )
  err( rigel.isFunction(fn), "mapVarSeq: first argument to map must be Rigel module, but is ",fn )

  local G = require "generators.core"
  
  local res = G.Function{"MapVarSeq_fn"..fn.name.."_W"..tostring(W_orig).."_H"..tostring(H_orig),fn.inputType,SDF{1,1},function(inp) return fn(inp) end}

  assert(res.over==nil)
  res.over = fn
  assert( rigel.isFunction(res) )
  
  -- hackity hack
  if fn.inputType~=types.Interface() then
    local NT = fn.inputType:replaceVar("over",types.Array2d(res.inputType.over,W_orig,H_orig,0,0,true))
    assert( NT:lower()==res.inputType:lower() )
    res.inputType = NT
  end
  
  if fn.outputType~=types.Interface() then
    local NT = fn.outputType:replaceVar("over",types.Array2d(res.outputType.over,W_orig,H_orig,0,0,true))
    assert( NT:lower()==res.outputType:lower() )
    res.outputType = NT
  end
  
  return res
end)

-- convert S interface to rv
modules.Storv = memoize(function( fn, X )
  assert(X==nil)
  err( rigel.isFunction(fn), "Storv: first argument to map must be Rigel module, but is ",fn )

  err( fn.inputType==types.Interface() or fn.inputType:isS(), "Storv: input type must be Inil or S")
  err( fn.outputType==types.Interface() or fn.outputType:isS(), "Storv: output type must be Inil or S")

  local res = { kind="Storv", delay=fn.delay, sdfInput=fn.sdfInput, sdfOutput=fn.sdfOutput, stateful=fn.stateful }
  res.name = sanitize("Storv_"..fn.name)

  res.requires = {}
  for inst,fnmap in pairs(fn.requires) do for fnname,_ in pairs(fnmap) do J.deepsetweak(res.requires,{inst,fnname},1) end end
  res.provides = {}
  for inst,fnmap in pairs(fn.provides) do for fnname,_ in pairs(fnmap) do J.deepsetweak(res.provides,{inst,fnname},1) end end

  res.instanceMap = {}
  res.instanceMap[fn:instantiate("fn")] = 1
    
  -- hackity hack
  if fn.inputType==types.Interface() then
    if fn.outputType:deInterface():isData() then
      res.inputType = types.rv(types.Par(types.Trigger))
    else
      print(fn.outputType)
      assert(false)
    end
  else
    assert(false)
    res.inputType = types.rv(fn.inputType.over)
  end

  if fn.outputType==types.Interface() then
    if fn.inputType.over:is("Par") then
      assert(false)
      res.outputType = types.rv(types.Par(types.Trigger))
    else
      assert(false)
    end
  else
    res.outputType = types.rv(fn.outputType.over)
  end

  res = rigel.newFunction(res)

  function res.makeSystolic()
    local C = require "generators.examplescommon"
    local s = C.automaticSystolicStub(res)
    s:verilog(res:vHeader()..res:vInstances()..[=[
assign process_output = fn_process_output;
endmodule

]=])
    return s
  end

  if terralib~=nil then res.terraModule = MT.Storv( res, fn ) end
  
  return res
end)

-- it's hard to know how any given module should be flatmapped, so just have user explicitly say what they want
-- take f:Par(T1[Vw1,Vh1])->Par(T2[Vw2,Vh2]) to T1[Vw1,Vh1;W1,H1}->T2[Vw2,Vh2;W2,H2}
-- if Vw==Vh==W==H==0, just leave that dimension alone (scalar output)
-- if Vw==Vh==0, have a Seq output, instead of ParSeq
modules.flatmap = memoize(function( fn, Vw1, Vh1, W1_orig, H1_orig, Vw2, Vh2, W2_orig, H2_orig, X )
  err( rigel.isFunction(fn), "flatmapParSeq: first argument must be Rigel function, but is ",fn )

  err( (Vw1==0 and Vh1==0) or fn.inputType:deInterface():isData(), "flatmapParSeq: fn input must Par, but input type is: "..tostring(fn.inputType) )
  err( (Vw1==0 and Vh1==0) or fn.inputType:extractData():isArray(), "flatmapParSeq: fn input must be array, but input type is: "..tostring(fn.inputType) )
  
  err( (Vw2==0 and Vh2==0) or fn.outputType:deInterface():isData(), "flatmapParSeq: fn output must be Par, but output type is: "..tostring(fn.outputType) )
  err( (Vw2==0 and Vh2==0) or fn.outputType:extractData():isArray(), "flatmapParSeq: fn output must be array, but output type is: "..tostring(fn.outputType) )
  
  local G = require "generators.core"

  local res = G.Function{"flatmapParSeq_fn"..fn.name.."_Vw1"..tostring(Vw1).."_Vh1"..tostring(Vh1).."_W1"..tostring(W1_orig).."_H1"..tostring(H1_orig),fn.inputType,SDF{1,1},function(inp) return fn(inp) end}
  assert( rigel.isFunction(res) )

  -- hackity hack
  if Vw1>0 or Vh1>0 then
    local newinp = fn.inputType:replaceVar("over",types.ParSeq( res.inputType:extractData(), W1_orig, H1_orig ))
    assert( res.inputType:lower()==newinp:lower() )
    res.inputType = newinp
  elseif W1_orig>0 or H1_orig>0 then
    local newinp = fn.inputType:replaceVar("over",types.Seq(types.Par( res.inputType:extractData()) ,W1_orig, H1_orig ))
    assert( res.inputType:lower()==newinp:lower() )
    res.inputType = newinp
  end
  
  if Vw2>0 or Vh2>0 then
    local newout = fn.outputType:replaceVar("over",types.ParSeq( res.outputType:extractData(), W2_orig, H2_orig ))
    assert( res.outputType:lower() == newout:lower() )
    res.outputType = newout
  elseif W2_orig>0 or H2_orig>0 then
    local newout = fn.outputType:replaceVar("over",types.Seq(types.Par( res.outputType:extractData() ), W2_orig, H2_orig ))
    assert( res.outputType:lower() == newout:lower() )
    res.outputType = newout
  end

  return res
end)

-- type {A,bool}->A
-- rate: {n,d} format frac. If coerce=true, 1/rate must be integer.
-- if rate={1,16}, filterSeq will return W*H/16 pixels
modules.filterSeq = memoize(function( A, W_orig, H, rate, fifoSize, coerce, framed, X )
  assert(types.isType(A))
  local W = Uniform(W_orig):toNumber()
  --err(type(W)=="number", "filterSeq: W must be number, but is: ",W)
  err(type(H)=="number", "filterSeq: H must be number, but is: ",H)
  err( SDFRate.isFrac(rate), "filterSeq: rate must be {n,d} format fraction" )
  err(type(fifoSize)=="number", "fifoSize must be number")
  if framed==nil then framed=false end
  err( type(framed)=="boolean", "filterSeq: framed must be bool" )
  err(X==nil,"filterSeq: too many args")
  
  if coerce==nil then coerce=true end


  local res = { kind="filterSeq", A=A }
  -- this has type basic->V (decimate)
  if framed then
    res.inputType = types.rv(types.Seq(types.Par(types.tuple{A,types.bool()}),W_orig,H))
    res.outputType = types.rvV(types.VarSeq(types.Par(A),W_orig,H))
  else
    res.inputType = types.rv(types.Par(types.tuple{A,types.bool()}))
    res.outputType = types.rvV(types.Par(A))
  end
  
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
    
    local sinp = S.parameter("process_input", res.inputType:lower() )
    local CE = S.CE("CE")
    local v = S.parameter("process_valid",types.bool())
    
    if coerce then
      
      local invrate = rate[2]/rate[1]
      err(math.floor(invrate)==invrate,"filterSeq: in coerce mode, 1/rate must be integer but is "..tostring(invrate))
      
      local outputCount = (W*H*rate[1])/rate[2]
      err(math.floor(outputCount)==outputCount,"filterSeq: in coerce mode, outputCount must be integer, but is "..tostring(outputCount))
      
      local vstring = [[
module FilterSeqImpl(input wire CLK, input wire process_valid, input wire reset, input wire ce, input wire []]..tostring(res.inputType:lower():verilogBits()-1)..[[:0] inp, output wire []]..tostring(rigel.lower(res.outputType):verilogBits()-1)..[[:0] out);
parameter INSTANCE_NAME="INST";

  reg [31:0] phase;
  reg [31:0] cyclesSinceOutput;
  reg [31:0] currentFifoSize;
  reg [31:0] remainingInputs;
  reg [31:0] remainingOutputs;

  wire []]..tostring(res.inputType:lower():verilogBits()-2)..[[:0] inpData;
  assign inpData = inp[]]..tostring(res.inputType:lower():verilogBits()-2)..[[:0];

  wire filterCond;
  assign filterCond = inp[]]..tostring(res.inputType:lower():verilogBits()-1)..[[];

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
      local inp = S.parameter("inp",res.inputType:lower())
    
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

-- takes in a vectorized sparse array: {A,bool}[N], and returns it as sparse A array
--   We simplify this module by only writing out at most 1 token per cycle.
--   So, our output rate really needs to be <1/N, or else we will not be able to keep up with throughput
-- restrictions: input array of valids must be sorted (valids come first)
-- 'rate' is % of tokens that will survive the filter. (ie 1/2 means half elements will be filtered)
modules.filterSeqPar = memoize(function( A, N, rate, framed, framedW, framedH, X )
  err( types.isType(A), "filterSeqPar: input type must be type" )
  err( type(N)=="number", "filterSeqPar: N must be number, but is: "..tostring(N) )
  err( N>0,"filterSeqPar: N must be > 0")
  err( SDF.isSDF(rate), "filterSeqPar: rate must be SDF rate" )
  assert(X==nil)

  if framed==nil then framed=false end
  assert(type(framed)=="boolean")
  
  local res = {kind="filterSeqPar"}

  if framed then
    res.inputType = types.rv(types.ParSeq(types.array2d( types.tuple{A,types.bool()}, N ),framedW,framedH) )
    res.outputType = types.rRvV(types.VarSeq(types.Par(A),framedW,framedH))
  else
    res.inputType = types.rv(types.Par(types.array2d( types.tuple{A,types.bool()}, N )) )
    res.outputType = types.rRvV( types.Par(A) )
  end
  
  res.sdfInput = SDF{1,1}

  -- we have N elements coming in, but we only write out 1 per cycle, so include that factor
  res.sdfOutput = SDF{rate[1][1]*N,rate[1][2]}
  res.stateful = true
  res.delay = 0
  res.name = J.sanitize("FilterSeqPar_"..tostring(A).."_N"..tostring(N).."_rate"..tostring(rate))

  local fakeV = {A:fakeValue(),false}
  local fakeVA = J.broadcast(fakeV,N)

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local buffer = systolicModule:add( S.module.reg( res.inputType:extractData(), true, fakeVA, true, fakeVA ):instantiate("buffer") )

    --local readyForMore = S.__or(readyForMore0, S.__and(readyForMore1,readyForMore2)):disablePipelining()
    local readyForMore = S.eq( S.index(S.index(buffer:get(),0),1), S.constant(false,types.bool()) )
    local sinp = S.parameter( "inp", res.inputType:lower() )

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
modules.downsampleYSeq = memoize(function( A, W_orig, H_orig, T, scale, X )
  err( types.isType(A), "downsampleYSeq: type must be rigel type")
  err( Uniform(W_orig):isNumber(), "downsampleYSeq: W must be number" )
  err( Uniform(H_orig):isNumber(), "downsampleYSeq: H must be number" )
  err( type(T)=="number", "downsampleYSeq: T must be number" )
  err( type(scale)=="number", "downsampleYSeq: scale must be number" )
  err( scale>=1, "downsampleYSeq: scale must be >=1" )
  err( T==0 or (Uniform(W_orig)%Uniform(T)):eq(0):assertAlwaysTrue(), "downsampleYSeq, W%T~=0")
  err( J.isPowerOf2(scale), "scale must be power of 2")
  err( X==nil, "downsampleYSeq: too many arguments" )

  local sbits = math.log(scale)/math.log(2)

  local inputType = A
  if T>0 then inputType = types.array2d(A,T) end
  local outputType = types.lower(types.rvV(types.Par(inputType)))
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},math.max(T,1))
  local innerInputType = types.tuple{xyType, inputType}

  local modname = J.sanitize("DownsampleYSeq_W"..tostring(W_orig).."_H"..tostring(H_orig).."_scale"..tostring(scale).."_"..tostring(A).."_T"..tostring(T))

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

  local res = modules.liftXYSeq( modname, "rigel.downsampleYSeq", f, W_orig, H_orig, math.max(1,T) )

  res.outputType = types.rvV(types.Par(inputType))

  local W,H = Uniform(W_orig):toNumber(), Uniform(H_orig):toNumber()
  
  local function downYSim()
    for y=0,H-1 do
      for x=0,W-1,math.max(T,1) do
        if y%scale==0 then
          coroutine.yield(true)
        else
          coroutine.yield(false)
        end
      end
    end
  end

  res.delay = J.sel(T>1,1,0)
  res.RVDelay, res.outputBurstiness = J.simulateFIFO( downYSim, res.sdfOutput, modname, false )
  
  return res
end)

-- takes A[W,H] to A[W/scale,H]
-- lines where xcoord%scale==0 are kept
-- basic -> V
-- 
-- This takes A[T] to A[T/scale], except in the case where scale>T. Then it goes from A[T] to A[1]. If you want to go from A[T] to A[T], use changeRate.
modules.downsampleXSeq = memoize(function( A, W_orig, H_orig, T, scale, X )
  err( types.isType(A), "downsampleXSeq: type must be rigel type" )
  err( A:isData(),"downsampleXSeq: input type must be data type")
  --err( type(W)=="number", "downsampleXSeq: W must be number" )
  --err( type(H)=="number", "downsampleXSeq: H must be number" )
  err( type(T)=="number", "downsampleXSeq: T must be number" )
  err( type(scale)=="number", "downsampleXSeq: scale must be number" )
  err( scale>=1, "downsampleXSeq: scale must be >=1 ")
  err( T==0 or (Uniform(W_orig)%Uniform(T)):eq(0):assertAlwaysTrue(), "downsampleXSeq, W%T~=0")
  err( J.isPowerOf2(scale), "NYI - scale must be power of 2")
  err( X==nil, "downsampleXSeq: too many arguments" )

  err( (Uniform(W_orig)%Uniform(scale)):eq(0):assertAlwaysTrue(),"downsampleXSeq: NYI - scale ("..tostring(scale)..") does not divide W ("..tostring(W_orig)..")")

  local W,H = Uniform(W_orig):toNumber(), Uniform(H_orig):toNumber()
  
  local sbits = math.log(scale)/math.log(2)

  local outputT
  if scale>T then outputT = J.sel(T==0,0,1)
  elseif T%scale==0 then outputT = T/scale
  else err(false,"T%scale~=0 and scale<T") end

  local inputType = A
  if T>0 then inputType = types.array2d(A,T) end
  local outputType = types.lower(types.rvV(A))
  if outputT>0 then outputType = types.lower(types.rvV(types.Par(types.array2d(A,outputT)))) end
  local xyType = types.array2d(types.tuple{types.uint(16),types.uint(16)},math.max(T,1))
  local innerInputType = types.tuple{xyType, inputType}

  local tfn, sdfOverride

  local modname = J.sanitize("DownsampleXSeq_W"..tostring(W_orig).."_H"..tostring(H_orig).."_"..tostring(A).."_T"..tostring(T).."_scale"..tostring(scale))

  local delay, RVDelay, outputBurstiness
  
  if scale>T then -- A[T] to A[1]
    -- tricky: each token contains multiple pixels, any of of which can be valid
    assert(scale%math.max(T,1)==0)
    sdfOverride = {{1,scale/math.max(T,1)}}
    if terralib~=nil then tfn = MT.downsampleXSeqFn( innerInputType, outputType, scale, T, outputT ) end

    local function downXSim()
      for y=0,H-1 do
        for x=0,W-1,math.max(T,1) do

          if x%scale==0 then
            coroutine.yield(true)
          else
            coroutine.yield(false)
          end
        end
      end
    end

    delay = J.sel(T>1,1,0)
    RVDelay, outputBurstiness = J.simulateFIFO( downXSim, SDF(sdfOverride), modname, false )
  else -- scale <= T... for every token, we output 1 token
    sdfOverride = {{1,1}}
    if terralib~=nil then tfn = MT.downsampleXSeqFnShort(innerInputType,outputType,scale,outputT) end
    delay = 1
    outputBurstiness = 0
  end

  local f = modules.lift( modname, innerInputType, outputType, 0, 
    function(sinp)
      local svalid, sdata
      if scale>T then -- A[T] to A[1]
        local sx = S.index(S.index(S.index(sinp,0),0),0)
        svalid = S.eq(S.cast(S.bitSlice(sx,0,sbits-1),types.uint(sbits)),S.constant(0,types.uint(sbits)))
        sdata = S.index(sinp,1)
        if T>0 then
          sdata = S.index(sdata,0)
          sdata = S.cast(S.tuple{sdata},types.array2d(sdata.type,1))
        end
      else
        svalid = S.constant(true,types.bool())
        local datavar = S.index(sinp,1)
        sdata = J.map(J.range(0,outputT-1), function(i) return S.index(datavar, i*scale) end)
        sdata = S.cast(S.tuple(sdata), types.array2d(A,outputT))
      end

      local res = S.tuple{sdata,svalid}
      return res
    end,
    function() return tfn end, nil,
    sdfOverride)
  
  local res = modules.liftXYSeq( modname, "rigel.downsampleXSeq", f, W_orig, H_orig, math.max(T,1) )
  
  -- hack
  local newType = types.rvV(A)
  if outputT>0 then
    newType = types.rvV(types.array2d(A,outputT))
  end
  
  assert(res.outputType:lower()==newType:lower())

  res.outputType = newType
  res.delay, res.outputBurstiness = delay, outputBurstiness
    
  return res
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
  assert(scale<100)
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
modules.upsampleXSeq = memoize(function( A, T, scale_orig, framed, X )
  err( types.isType(A), "upsampleXSeq: first argument must be rigel type, but is: ",A)
  err( rigel.isBasic(A),"upsampleXSeq: type must be basic type, but is: ",A)
  err( type(T)=="number", "upsampleXSeq: vector width must be number")
  if framed==nil then framed=false end
  err( type(framed)=="boolean", "upsampleXSeq: framed must be bool" )
  
  --err( type(scale)=="number","upsampleXSeq: scale must be number")
  local scale = Uniform(scale_orig)
  local COUNTER_BITS = 24
  local COUNTER_MAX = math.pow(2,COUNTER_BITS)-1
  err( scale:lt(COUNTER_MAX):assertAlwaysTrue(), "upsampleXSeq: NYI - scale>="..tostring(COUNTER_MAX)..". scale="..tostring(scale))
  err( scale:gt(0):assertAlwaysTrue(),"upsampleXSeq: scale must be >0! but is: "..tostring(scale))
  err(X==nil, "upsampleXSeq: too many arguments")
  
  if T==1 or T==0 then
    -- special case the EZ case of taking one value and writing it out N times
    local res = {kind="upsampleXSeq",sdfInput=SDF{1,scale}, sdfOutput=SDF{1,1}, stateful=true, A=A, T=T, scale=scale}

    if T==0 then
      res.inputType = types.rv(types.Par(A))
      res.outputType = types.rRvV(types.Par(A))
    else
      local ITYPE = types.array2d(A,T)
      res.inputType = types.rv(types.Par(ITYPE))
      res.outputType = types.rRvV(types.Par(types.array2d(A,T)))
    end
    
    res.delay=0
    res.name = verilogSanitize("UpsampleXSeq_"..tostring(A).."_T_"..tostring(T).."_scale_"..tostring(scale_orig))

    if terralib~=nil then res.terraModule = MT.upsampleXSeq(res, A, T, scale, res.inputType:extractData() ) end

    -----------------
    function res.makeSystolic()
      local systolicModule = Ssugar.moduleConstructor(res.name)
      local sinp = S.parameter( "inp", res.inputType:extractData() )

      local sPhase = systolicModule:add( Ssugar.regByConstructor( types.uint(COUNTER_BITS), fpgamodules.sumwrap(types.uint(COUNTER_BITS),scale-1) ):CE(true):setReset(0):instantiate("phase") )
      local reg
      if A~=types.Trigger then
        reg = systolicModule:add( S.module.reg( res.inputType:extractData(),true ):instantiate("buffer") )
      end
      
      local reading = S.eq(sPhase:get(),S.constant(0,types.uint(COUNTER_BITS))):disablePipelining()
      local out
      if A==types.Trigger then
        out = S.constant(res.outputType:extractData():fakeValue(),res.outputType:extractData())
      else
        out = S.select( reading, sinp, reg:get() ) 
      end
      
      local pipelines = {}
      if A~=types.Trigger then
        table.insert(pipelines, reg:set( sinp, reading ) )
      end
      table.insert( pipelines, sPhase:setBy( S.constant(1,types.uint(COUNTER_BITS)) ) )

      local CE = S.CE("CE")
      systolicModule:addFunction( S.lambda("process", sinp, S.tuple{out,S.constant(true,types.bool())}, "process_output", pipelines, nil, CE) )
      systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), reading, "ready", {} ) )
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:reset()},S.parameter("reset",types.bool())) )

      return systolicModule
    end

    local res = modules.liftHandshake(modules.waitOnInput( rigel.newFunction(res) ))
    if framed then
      res.outputType = types.RV(types.Seq(res.outputType:extractData(),scale_orig,1))
    end
    
    return res
  else -- T>1
    -- this takes T[V]->T[V] with rate (1/scale)->1
    err( scale:isConst(), "upsampleXSeq: NYI - runtime configurable scale" )
    local scaleV = scale:toNumber()

    if scaleV>T and scaleV%T==0 then
      -- codesize optimization
      local C = require "generators.examplescommon"
      return C.linearPipeline({modules.changeRate(A,1,T,0),
                               modules.upsampleXSeq(A,0,scaleV/T),
                               modules.makeHandshake(C.broadcast(A,T))},
        "upsampleXSeq_"..J.verilogSanitize(tostring(A)).."_T"..tostring(T).."_scale"..tostring(scaleV))
    else
      return modules.compose("upsampleXSeq_"..J.verilogSanitize(tostring(A)).."_T"..tostring(T).."_scale"..tostring(scaleV), modules.changeRate(A,1,T*scaleV,T), modules.makeHandshake(broadcastWide(A,T,scaleV)))
    end
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
  res.inputType = types.rv(types.Par(ITYPE))
  res.outputType = types.rRvV(types.Par(types.array2d(A,T)))
  res.delay = 1
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

  local upsampleYSim = function()
    for y=0,(H*scale)-1 do
      for x=0,W-1,math.max(T,1) do
        if y%scale==0 then
          coroutine.yield(true)
        else
          coroutine.yield(false)
        end
      end
    end
  end

  res.RVDelay, res.inputBurstiness = J.simulateFIFO( upsampleYSim, res.sdfInput, res.name, true, (W*H)/math.max(T,1) )
  res.outputBurstiness = 2 -- hack: make it wait to start writing stuff out until it's fifo is full enough
  
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

  local log2N = math.ceil(math.log(N)/math.log(2))
  
  local res = {kind="interleveSchedule", N=N, period=period, delay=0, inputType=types.rv(types.Par(types.Trigger)), outputType=types.rv(types.Par(types.uint(log2N))), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=true }
  res.name = "InterleveSchedule_"..N.."_"..period

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.uint(8), "interleve schedule phase %d", true):instantiate("printInst") ) end
    
    local inp = S.parameter("process_input", rigel.lower(res.inputType) )
    local phase = systolicModule:add( Ssugar.regByConstructor( types.uint(8), fpgamodules.incIfWrap( types.uint(8), 255, 1 ) ):setInit(0):setReset(0):CE(true):instantiate("interlevePhase") )
    
    
    local CE = S.CE("CE")
    local pipelines = {phase:setBy( S.constant(true,types.bool()))}
    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(phase:get())) end
    
    systolicModule:addFunction( S.lambda("process", inp, S.cast(S.bitSlice(phase:get(),period,period+log2N-1),types.uint(log2N)), "process_output", pipelines, nil, CE ) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:reset()}, S.parameter("reset",types.bool())) )

    return systolicModule
  end

  res = rigel.newFunction(res)
  
  if terralib~=nil then res.terraModule = MT.interleveSchedule( res, N, period ) end

  return res
end)

-- wtop is the width of the largest (top) pyramid level
modules.pyramidSchedule = memoize(function( depth, wtop, T )
  err(type(depth)=="number", "depth must be number")
  err(type(wtop)=="number", "wtop must be number")
  err(type(T)=="number", "T must be number")

  local log2N = math.ceil(math.log(depth)/math.log(2))

  local res = {kind="pyramidSchedule", wtop=wtop, depth=depth, T=T, delay=0, inputType=types.rv(types.Par(types.Trigger)), outputType=types.rv(types.Par(types.uint(log2N))), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=true }
  res.name = "PyramidSchedule_depth_"..tostring(depth).."_wtop_"..tostring(wtop).."_T_"..tostring(T)

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

  res = rigel.newFunction(res)

  if terralib~=nil then res.terraModule = MT.pyramidSchedule( res, depth, wtop, T ) end

  return res
end)

-- WARNING: validOut depends on readyDownstream
modules.toHandshakeArrayOneHot = memoize(function( A, inputRates )
  err( types.isType(A), "A must be type" )
  rigel.expectBasic(A)
  err( type(inputRates)=="table", "inputRates must be table")
  assert( SDFRate.isSDFRate(inputRates))

  local res = {kind="toHandshakeArrayOneHot", A=A, inputRates = inputRates}
  res.inputType = types.array2d(types.RV(types.Par(A)), #inputRates)
  res.outputType = rigel.HandshakeArrayOneHot( types.Par(A), #inputRates )
  res.sdfInput = SDF(inputRates)
  res.sdfOutput = SDF(inputRates)
  res.stateful = false
  res.name = sanitize("ToHandshakeArrayOneHot_"..tostring(A).."_"..#inputRates)

  res.delay = 0
  
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
modules.sequence = memoize(function( A, inputRates, Schedule, X )
  err( types.isType(A), "A must be type" )
  err( A:isData(), "sequence: type must be data type")
  err( type(inputRates)=="table", "inputRates must be table")
  assert( SDFRate.isSDFRate(inputRates) )
  err( rigel.isFunction(Schedule), "schedule must be darkroom function")

  local log2N = math.ceil(math.log(#inputRates)/math.log(2))
  err( rigel.lower(Schedule.outputType)==types.uint(log2N), "schedule function has incorrect output type, ",Schedule.outputType," should be : ",types.Uint(log2N))
  rigel.expectBasic(A)
  assert(X==nil)

  local res = {kind="sequence", A=A, inputRates=inputRates, schedule=Schedule}
  res.inputType = rigel.HandshakeArrayOneHot( types.Par(A), #inputRates )
  res.outputType = rigel.HandshakeTmuxed( types.Par(A), #inputRates )
  err( type(Schedule.stateful)=="boolean", "Schedule missing stateful annotation")
  res.stateful = Schedule.stateful
  res.name = sanitize("Sequence_"..tostring(A).."_"..#inputRates)

  res.delay = 0
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
    local nextFIFO = scheduler:process(S.trigger,stepSchedule, schedulerCE)
    
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
modules.arbitrate = memoize(function( A, inputRates, tmuxed, X )
  err( types.isType(A), "A must be type, but is: "..tostring(A) )
  err( A:isSchedule(),"arbitrate: type must be schedule type" )
  err( type(inputRates)=="table", "inputRates must be table")
  assert( SDFRate.isSDFRate(inputRates) )
  err( #inputRates>1, "arbitrate: must be passed more than 1 input rate! Or, there's nothing to arbitrate. Passed:",inputRates )
  
  if tmuxed==nil then tmuxed=false end
  assert(type(tmuxed)=="boolean")
  err(X==nil,"arbitrate: too many arguments")

  local res = {kind="arbitrate", A=A, inputRates=inputRates}
  res.name = sanitize("Arbitrate_"..tostring(A).."_"..#inputRates)
  res.stateful = false
  res.delay = 0
  
  res.inputType = types.array2d( types.RV(A), #inputRates )

  if tmuxed then
    res.outputType = rigel.HandshakeTmuxed( A, #inputRates )
  else
    res.outputType = types.RV( A )
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

  res.inputType = rigel.HandshakeTmuxed( types.Par(A), #rates )
  res.outputType = types.array2d( types.RV(types.Par(A)), #rates)
  res.stateful = false
  res.name = sanitize("Demux_"..tostring(A).."_"..#rates)

  local sdfSum = SDFRate.sum(rates)
  err(  SDFRate.fracEq(sdfSum,{1,1}), "rates must sum to 1")

  res.sdfInput = SDF(rates)
  res.sdfOutput = SDF(rates)

  res.delay = 0
  
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

  res.inputType = rigel.HandshakeTmuxed( types.Par(A), #rates )
  res.outputType = rigel.Handshake(A)
  res.stateful = false

  local sdfSum = SDFRate.sum(rates) --rates[1][1]/rates[1][2]
  --for i=2,#rates do sdfSum = sdfSum + (rates[i][1]/rates[i][2]) end
  err( Uniform(sdfSum[1]):eq(sdfSum[2]):assertAlwaysTrue(), "inputRates must sum to 1, but are: "..tostring(SDF(rates)).." sum:"..tostring(sdfSum[1]).."/"..tostring(sdfSum[2]))
  
  res.sdfInput = SDF(rates)
  res.sdfOutput = SDF{1,1}
  res.name = sanitize("FlattenStreams_"..tostring(A).."_"..#rates)

  res.delay = 0
  
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
modules.broadcastStream = memoize(function(A,W,H,X)
  err( A==nil or types.isType(A), "broadcastStream: type must be type, but is: "..tostring(A))
  err( A==nil or A:isSchedule() or A:isData(),"broadcastStream: type must be data or schedule type, but is: "..tostring(A))
  err( type(W)=="number", "broadcastStream: W must be number")
  if H==nil then H=1 end
  err( type(H)=="number", "broadcastStream: H must be number")
  assert(X==nil)

  local res = {kind="broadcastStream", A=A, W=W, H=H,  stateful=false, delay=0}

  res.inputType = types.RV(A)
  res.outputType = types.array2d(types.RV(A), W, H)

  res.sdfInput = SDF{1,1}
  res.sdfOutput = SDF(J.broadcast({1,1},W*H))
  res.name = sanitize("BroadcastStream_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H))

  if terralib~=nil then res.terraModule = MT.broadcastStream(res,W,H) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name):onlyWire(true)

    local printStr = "IV %d readyDownstream ["..table.concat( J.broadcast("%d",W*H),",").."] ready %d"
    local printInst
--    if DARKROOM_VERBOSE then 
--      printInst = systolicModule:add( S.module.print( types.tuple( J.broadcast(types.bool(),N+2)), printStr):instantiate("printInst") ) 
--    end

    local inp = S.parameter( "process_input", rigel.lower(res.inputType) )
    local inpData, inpValid

    if A==nil then -- HandshakeTrigger
      inpValid = inp
    else
      inpData = S.index(inp,0)
      inpValid = S.index(inp,1)
    end

    local readyDownstream = S.parameter( "ready_downstream", types.array2d(types.bool(),W,H) )
    local readyDownstreamList = J.map(J.range(W*H), function(i) return S.index(readyDownstream,i-1) end )
    
    local allReady = J.foldt( readyDownstreamList, function(a,b) return S.__and(a,b) end, "X" )
    local validOut = S.__and(inpValid,allReady)

    local out

    if inpData==nil then
      -- HandshakeTrigger
      out  = S.tuple( J.broadcast(validOut, W*H))
      out = S.cast(out, types.array2d(types.bool(),W,H) )
    else
      out  = S.tuple( J.broadcast(S.tuple{inpData, validOut}, W,H))
    end
    out = S.cast(out, rigel.lower(res.outputType) )
    
    local pipelines = {}
    
    --if DARKROOM_VERBOSE then table.insert( pipelines, printInst:process( S.tuple( J.concat( J.concat({inpValid}, readyDownstreamList),{allReady}) ) ) ) end
    
    systolicModule:addFunction( S.lambda("process", inp, out, "process_output", pipelines ) )


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
  err(type(T)=="number","posSeq: T must be number, but is: "..tostring(T))
  err( W:gt(0):assertAlwaysTrue(), "posSeq: W must be >0, but is: "..tostring(W));
  err(H>0, "posSeq: H must be >0");
  err(T>=0, "posSeq: T must be >=0");
  if framed==nil then framed=false end
  err( type(framed)=="boolean", "posSeq: framed should be boolean")
  if asArray==nil then asArray=false end
  err( type(asArray)=="boolean", "posSeq: asArray should be boolean")
  err(X==nil, "posSeq: too many arguments")

  local res = {kind="posSeq", T=T, W=W, H=H }
  res.inputType = types.rv(types.Par(types.Trigger))
  
  local sizeType = types.tuple({types.uint(bits),types.uint(bits)})
  if asArray then sizeType = types.array2d(types.uint(bits),2) end
  if T==0 then
    res.outputType = sizeType
    if framed then
      res.outputType = types.rv(types.Seq(types.Par(res.outputType),W_orig,H))
      res.inputType = types.rv(types.Seq(types.Par(types.Trigger),W_orig,H))
    end
  else
    res.outputType = types.array2d(sizeType,T)
    if framed then
      res.outputType = types.rv(types.ParSeq(res.outputType,W_orig,H))
      res.inputType = types.rv(types.ParSeq(types.Array2d(types.Trigger,T),W_orig,H))
    end
  end
  res.stateful = true
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
--  res.delay = J.sel(T>1,math.floor(S.delayScale),0)
  res.delay = J.sel(T>1,math.floor(S.delayTable["+"][bits]*S.delayScale),0)
  res.name = sanitize("PosSeq_W"..tostring(W_orig).."_H"..H.."_T"..T.."_bits"..tostring(bits).."_framed"..tostring(framed))

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
      if asArray then
        local newout = {}
        for _,v in ipairs(out) do
          table.insert(newout, S.cast(v,types.array2d(types.uint(bits),2)) )
        end
        finout = S.cast(S.tuple(newout),types.array2d(types.Array2d(types.uint(bits),2),T))
      else
        finout = S.cast(S.tuple(out),types.array2d(types.tuple{types.uint(bits),types.uint(bits)},T))
      end
      --assert(asArray==false) -- NYI
    end
    
    systolicModule:addFunction( S.lambda("process", S.parameter("pinp",res.inputType:lower()), finout, "process_output", pipelines, nil, CE ) )

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
  err( f.inputType:isrv() and f.inputType:deInterface():isData(), "liftXYSeq: f must have rv parallel input type, but is: "..tostring(f.inputType) )
  err( f.inputType:deInterface():isTuple(),"liftXYSeq: f must have tuple input type, but is: "..tostring(f.inputType) )

  local W = Uniform(W_orig)
  err( type(H)=="number", "liftXYSeq: H must be number")
  err( type(T)=="number", "liftXYSeq: T must be number")
  err( X==nil, "liftXYSeq: too many arguments")

  local G = require "generators.core"
  
  local inputType = f.inputType:deInterface().list[2]
  local inp = rigel.input( types.rv(types.Par(inputType)) )
  local p = rigel.apply("p", modules.posSeq(W,H,T,bits), G.ValueToTrigger(inp) )
  local out = rigel.apply("m", f, rigel.concat("ptup", {p,inp}) )
  local res = modules.lambda( "liftXYSeq_"..name.."_W"..tostring(W_orig), inp, out,nil,generatorStr )
  return res
end)

-- this takes a function f : {{uint16,uint16},inputType} -> outputType
-- and returns a function of type inputType[T]->outputType[T]
function modules.liftXYSeqPointwise( name, generatorStr, f, W, H, T, X )
  err( type(name)=="string", "liftXYSeqPointwise: name must be string" )
  err( type(generatorStr)=="string", "liftXYSeqPointwise: generatorStr must be string" )
  err( rigel.isFunction(f), "liftXYSeqPointwise: f must be function")
  err( f.inputType:isrv() and f.inputType:deInterface():isData(), "liftXYSeqPointwise: f input type must be parallel, but is: "..tostring(f.inputType))
  err( f.inputType:deInterface():isTuple(), "liftXYSeqPointwise: f input type must be tuple, but is: "..tostring(f.inputType))
  err( type(W)=="number", "liftXYSeqPointwise: W must be number" )
  err( type(H)=="number", "liftXYSeqPointwise: H must be number" )
  err( type(T)=="number", "liftXYSeqPointwise: T must be number" )
  err( X==nil, "liftXYSeqPointwise: too many arguments" )

  local fInputType = f.inputType:deInterface().list[2]
  local inputType = types.array2d(fInputType,T)
  local xyinner = types.tuple{types.uint(16),types.uint(16)}
  local xyType = types.array2d(xyinner,T)
  local innerInputType = types.tuple{xyType, inputType}

  local inp = rigel.input( types.rv(types.Par(innerInputType)) )
  local unpacked = rigel.apply("unp", modules.SoAtoAoS(T,1,{xyinner,fInputType}), inp) -- {{uint16,uint16},A}[T]
  local out = rigel.apply("f", modules.map(f,T), unpacked )
  local ff = modules.lambda("liftXYSeqPointwise_"..f.kind, inp, out )
  return modules.liftXYSeq(name, generatorStr, ff, W, H, T )
end

-- takes an image of size A[W,H] to size A[W-L-R,H-B-Top]
-- indexMode: cropSeq is basically the same as slice! if indexMode==true, we expect the crop to only return 1 item
--     and, instead of returning that as an array, we just return the item. This allows us to use cropSeq to implement index
--     on non-parallel types
modules.cropSeq = memoize(function( A, W_orig, H, V, L, R_orig, B, Top, framed, indexMode, X )
  local BITS = 32
  err( types.isType(A), "cropSeq: type must be rigel type, but is: ",A)
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
  err( (W-L-R):gt(0):assertAlwaysTrue(),"cropSeq, (W-L-R) must be >0! This means you have cropped the whole image! W=",W," L=",L," R=",R)
  err( (H-B-Top)>0,"cropSeq, (H-B-Top) must be >0! This means you have cropped the whole image!")
  err( X==nil, "cropSeq: too many arguments" )

  --err( W:lt(math.pow(2,BITS)-1):assertAlwaysTrue(), "cropSeq: width too large!")
  err( H<math.pow(2,BITS), "cropSeq: height too large!")

  if indexMode==nil then indexMode = false end
  err( type(indexMode)=="boolean","cropSeq: indexMode should be bool" )
  if indexMode then
    err( (Uniform(W_orig)-L-R_orig):eq(1),"cropSeq: in indexMode, output size should be 1, but is W:",W_orig," L:",L, " R:",R_orig )
    err( (H-B-Top)==1,"cropSeq: in indexMode, output size should be 1, but is H:",H," B:",B," Top:",Top )
  end
  
  local inputType
  if V==0 then
    inputType = A
  else
    inputType = types.array2d(A,V)
  end
  
  local outputType = types.tuple{inputType,types.bool()}
  local xyType = types.array2d(types.tuple{types.uint(BITS),types.uint(BITS)},math.max(V,1))
  local innerInputType = types.tuple{xyType, inputType}

  local modname = J.verilogSanitize("CropSeq_"..tostring(A).."_W"..tostring(W_orig).."_H"..tostring(H).."_V"..tostring(V).."_L"..tostring(L).."_R"..tostring(R_orig).."_B"..tostring(B).."_Top"..tostring(Top).."_idx"..tostring(indexMode))

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
    if V==0 then
      local it = types.rv(types.Seq(types.Par(res.inputType:deInterface()),W_orig,H))
      assert( it:lower()==res.inputType:lower() )
      res.inputType = it
      local ot = types.rvV(types.Seq(types.Par(res.outputType:deInterface().list[1]),W_orig-L-R_orig,H-B-Top))
      if indexMode then
        ot = types.rvV(res.outputType:deInterface().list[1])
      end
      assert( ot:lower()==res.outputType:lower() )

      res.outputType = ot
    else
      err( indexMode==false or V==1, "NYI - cropSeq, framed, indexMode with V>1 not implemented. V=",V)
      local it = types.rv(types.ParSeq(res.inputType:deInterface(),W_orig,H))
      assert( it:lower()==res.inputType:lower() )
      res.inputType = it
      local ot =  types.rvV(types.ParSeq(res.outputType:deInterface().list[1],W_orig-L-R_orig,H-B-Top))
      if indexMode then
        ot = types.rvV(res.outputType:deInterface().list[1]:arrayOver())
      end
      assert( ot:lower()==res.outputType:lower() )
      res.outputType = ot
    end
  else
    assert( indexMode==false)
    local ot = types.rvV(types.Par(res.outputType:deInterface().list[1]))
    assert( ot:lower()==res.outputType:lower() )
    res.outputType = ot
  end

  local ff = Uniform(W_orig):toNumber()*math.max(Top,B,1)

  local W_n = Uniform(W_orig):toNumber()
  local R_n = Uniform(R_orig):toNumber()
  
  local cropSim = function()
    for y=0,H-1 do
      for x=0,W_n-1,math.max(V,1) do
        if x>=L and x<(W_n-R_n) and y>=B and y<(H-Top) then
          coroutine.yield(true)
        else
          coroutine.yield(false)
        end
      end
    end
  end
  
  res.inputBurstiness = 0
  res.delay = J.sel(V>1,1,0)
  res.RVDelay, res.outputBurstiness = J.simulateFIFO( cropSim, res.sdfOutput, modname, false )
    
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
-- waitForFirstInput: don't start writing frames until we see at least one input!
modules.padSeq = memoize(function( A, W_orig, H, T, L, R_orig, B, Top, Value, framed, waitForFirstInput, X )
  err( types.isType(A), "A must be a type")
  
  err( A~=nil, "padSeq A==nil" )
  err( W_orig~=nil, "padSeq W==nil" )
  err( H~=nil, "padSeq H==nil" )
  err( T~=nil, "padSeq T==nil" )
  err( L~=nil, "padSeq L==nil" )
  err( R_orig~=nil, "padSeq R==nil" )
  err( B~=nil, "padSeq B==nil" )
  err( Top~=nil, "padSeq Top==nil" )
  err( Value~=nil, "padSeq Value==nil" )
  if framed==nil then framed=false end
  err( type(framed)=="boolean","padSeq: framed should be boolean" )
  if waitForFirstInput==nil then waitForFirstInput=false end
  err( type(waitForFirstInput)=="boolean")
  err( X==nil, "padSeq: too many arguments" )
  
  J.map({H=H,T=T,L=L,B=B,Top=Top},function(n,k)
        err(type(n)=="number","PadSeq expected number for argument "..k.." but is "..tostring(n)); 
        err(n==math.floor(n),"PadSeq non-integer argument "..k..":"..n); 
        err(n>=0,"n<0") end)

  local R = Uniform(R_orig)
  local W = Uniform(W_orig)
  
  A:checkLuaValue(Value)

  if T~=0 then
    err( (W%T):eq(0):assertAlwaysTrue(), "padSeq, W%T~=0, W="..tostring(W_orig).." T="..tostring(T))
    err( L==0 or (L>=T and L%T==0), "padSeq, L<T or L%T~=0 (L="..tostring(L)..",T="..tostring(T)..")")
    err( (R:eq(0):Or( R:ge(T):And( (R%T):eq(0)))):assertAlwaysTrue(), "padSeq, R<T or R%T~=0") -- R==0 or (R>=T and R%T==0)
    err( Uniform((W+L+R)%T):eq(0):assertAlwaysTrue(), "padSeq, (W+L+R)%T~=0") -- (W+L+R)%T==0
  end

  local res = {kind="padSeq", type=A, T=T, L=L, R=R, B=B, Top=Top, value=Value, width=W_orig, height=H}
  
  if T==0 then
    res.inputType = A
    res.outputType = A
  else
    res.inputType = types.array2d(A,T)
    res.outputType = types.array2d(A,T)
  end
  
  if framed then
    if T==0 then
      res.inputType = types.rv(types.Seq( types.Par(res.inputType), W_orig, H ))
      res.outputType = types.rRvV(types.Seq( types.Par(res.outputType), W_orig+L+R, H+B+Top ))
    else
      res.inputType = types.rv(types.ParSeq(res.inputType,W_orig,H))
      res.outputType = types.rRvV(types.ParSeq(res.outputType,W_orig+L+R,H+B+Top))
    end
  else
    res.inputType = types.rv(types.Par(res.inputType))
    res.outputType = types.rRvV(types.Par(res.outputType))
  end
  
  local Tf = math.max(T,1)
  
  res.stateful = true
  res.sdfInput, res.sdfOutput = SDF{ (W_orig*H)/Tf, ((Uniform(W)+Uniform(L)+R)*(H+B+Top))/Tf}, SDF{1,1}
  res.name = verilogSanitize("PadSeq_"..tostring(A).."_W"..tostring(W_orig).."_H"..H.."_L"..L.."_R"..tostring(R_orig).."_B"..B.."_Top"..Top.."_T"..T.."_Value"..tostring(Value))


  local R_n = R:toNumber()
  local W_n = W:toNumber()
  local padSim = function()
    local totalOut = 0
    for y=0,(H+B+Top)-1 do
      for x=0,(W_n+L+R_n)-1,math.max(T,1) do
        if x>=L and x<(W_n+L) and y>=B and y<(H+B) then
          totalOut = totalOut+1
          coroutine.yield(true)
        else
          coroutine.yield(false)
        end
      end
    end
  end

  res.delay = 0
  res.RVDelay, res.inputBurstiness = J.simulateFIFO( padSim, res.sdfInput, res.name, true, (W_n*H)/math.max(T,1) )
  --res.inputBurestiness = res.inputBurstiness + 1
  res.outputBurstiness = 1 -- hack: module starts up at time=0, regardless of when triggered. Do this to throttle it.
  
  if terralib~=nil then res.terraModule = MT.padSeq( res, A, W, H, T, L, R, B, Top, Value ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local posX = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.incIfWrap( types.uint(32), W+L+R-Tf, Tf ) ):CE(true):setInit(0):setReset(0):instantiate("posX_padSeq") ) 
    local posY = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), H+Top+B-1) ):CE(true):setInit(0):setReset(0):instantiate("posY_padSeq") ) 
    local printInst
    --if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(16),types.uint(16),types.bool()}, "x %d y %d ready %d", true ):instantiate("printInst") ) end
    
    local pinp = S.parameter("process_input", res.inputType:lower() )
    local pvalid = S.parameter("process_valid", types.bool() )
    
    local C1 = S.ge( posX:get(), S.constant(L,types.uint(32)))
    local C2 = S.lt( posX:get(), Uniform(L+W):toSystolic(types.U32) )
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
    
    local isInside = S.__and(xcheck,ycheck):disablePipelining()

    local pipelines={}

    local readybit
    local userinput
    if waitForFirstInput then
      local first = S.__and(S.eq( posX:get(), S.constant(0,types.uint(32)) ), S.eq( posY:get(), S.constant(0,types.uint(16)) ))
      local last = S.__and(S.eq( posX:get(), Uniform(L+W-math.max(T,1)):toSystolic(types.U32) ), S.eq( posY:get(), S.constant(B+H-1,types.uint(16)) ))
      readybit = S.__and(isInside,S.__not(last))
      readybit = S.__or(readybit,first)
      readybit = readybit:disablePipelining()

      local databuf = systolicModule:add( S.module.reg( res.inputType:lower(), true ):instantiate("databuf") )
      table.insert( pipelines, databuf:set(pinp,readybit) )
      userinput = databuf:get()
    else
      readybit = isInside
      userinput = pinp
    end
    
    local incY = S.eq( posX:get(), Uniform(W+L+R-Tf):toSystolic(types.uint(32))  ):disablePipelining()
    table.insert( pipelines, posY:setBy( incY ) )
    table.insert( pipelines, posX:setBy( S.constant(true,types.bool()) ) )

    local ValueBroadcast
    if T==0 then
      ValueBroadcast = S.constant(Value,A)
    else
      ValueBroadcast = S.cast( S.tuple( J.broadcast(S.constant(Value,A),T)) ,types.array2d(A,T))
    end
    
    local ConstTrue = S.constant(true,types.bool())

    local out = S.select( isInside, userinput, ValueBroadcast )
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", pinp, S.tuple{out,ConstTrue}, "process_output", pipelines, pvalid, CE) )
    
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {posX:reset(), posY:reset()},S.parameter("reset",types.bool())) )
    
    systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), readybit, "ready", {} ) )

    return systolicModule
  end

  return modules.waitOnInput(rigel.newFunction(res))
end)


--StatefulRV. Takes A[inputRate,H] in, and buffers to produce A[outputRate,H]
-- 'rate' has a strange meaning here: 'rate' means size of array.
--     so inputRate=2 means 2items/clock (2 wide array)
-- framedW/H: these are the size of the whole array. So, when framed, we expect input:
--    [inputRate,H;framedW,framedH} to [outputRate,H;framedW,framedH}
modules.changeRate = memoize(function(A, H, inputRate, outputRate, framed, framedW, framedH, X)
  err( types.isType(A), "changeRate: A should be a type")
  err( type(H)=="number", "changeRate: H should be number")
  err( H>0,"changeRate: H must be >0, but is: ",H)
  err( type(inputRate)=="number", "changeRate: inputRate should be number, but is: "..tostring(inputRate))
  err( inputRate>=0, "changeRate: inputRate must be >=0")
  err( inputRate==math.floor(inputRate), "changeRate: inputRate should be integer")
  err( type(outputRate)=="number", "changeRate: outputRate should be number, but is: "..tostring(outputRate))
  err( outputRate==math.floor(outputRate), "changeRate: outputRate should be integer, but is: "..tostring(outputRate))
  if framed==nil then framed=false end
  err( type(framed)=="boolean","changeRate: framed must be boolean")
  err( X==nil, "changeRate: too many arguments")

  local maxRate = math.max(math.max(inputRate,outputRate),1)
  local minRate = math.max(math.min(inputRate,outputRate),1)
  
  err( inputRate==0 or maxRate % inputRate == 0, "maxRate ("..tostring(maxRate)..") % inputRate ("..tostring(inputRate)..") ~= 0")
  err( outputRate==0 or maxRate % outputRate == 0, "maxRate ("..tostring(maxRate)..") % outputRate ("..tostring(outputRate)..") ~=0")
  rigel.expectBasic(A)

  local inputCount = maxRate/math.max(inputRate,1)
  local outputCount = maxRate/math.max(outputRate,1)

  local res = {kind="changeRate", type=A, H=H, inputRate=inputRate, outputRate=outputRate}

  if inputRate>outputRate then
    -- 8->4
    res.inputBurstiness = 0
    res.outputBurstiness = 0
    res.delay = 1
  else
    -- 4->8
    res.inputBurstiness = 0
    res.outputBurstiness = 0
    res.delay = 1
  end
  
  
  if framed then
    err(type(framedW)=="number", "changeRate: if framed, framedW should be number, but is: "..tostring(framedW))
    assert(type(framedH)=="number")
    assert(inputRate==0 or framedW%inputRate==0)
    assert(outputRate==0 or framedW%outputRate==0)
    
    if inputRate==0 then
      assert(framedH==1)
      assert(H==1)
      res.inputType = types.RV(types.Seq(types.Par(A),framedW,framedH))
    elseif inputRate<framedW then
      assert(H==framedH)
      res.inputType = types.RV(types.ParSeq(types.array2d(A,inputRate,H),framedW,framedH))
    elseif inputRate==framedW then
      assert(H==framedH)
      res.inputType = types.RV(types.Par(types.array2d(A,inputRate,H)))
    else
      assert(false)
    end

    if outputRate==0 then
      assert(framedH==1)
      assert(H==1)
      res.outputType = types.RV(types.Seq(A,framedW,framedH))
    elseif outputRate<framedW then
      assert(framedH==H)
      res.outputType = types.RV(types.ParSeq(types.array2d(A,outputRate,H),framedW,framedH))
    elseif outputRate==framedW then
      assert(framedH==H)
      res.outputType = types.RV(types.Par(types.array2d(A,framedW,framedH)))
    else
      assert(false)
    end
  else
    if inputRate==0 then
      assert(H==1)
      res.inputType = types.RV(types.Par(A))
    else
      res.inputType = types.RV(types.Par(types.array2d(A,inputRate,H)))
    end

    if outputRate==0 then
      assert(H==1)
      res.outputType = types.RV(types.Par(A))
    else
      res.outputType = types.RV(types.Par(types.array2d(A,outputRate,H)))
    end
  end
  
  res.stateful = true

  res.name = J.verilogSanitize("ChangeRate_"..tostring(A).."_from"..inputRate.."_to"..outputRate.."_H"..H.."_framed"..tostring(framed).."_framedW"..tostring(framedW).."_framedH"..tostring(framedH))

  if inputRate>outputRate then -- 8 to 4
    res.sdfInput, res.sdfOutput = SDF{math.max(outputRate,1),math.max(inputRate,1)},SDF{1,1}
  else -- 4 to 8
    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{math.max(inputRate,1),math.max(outputRate,1)}
  end

  function res.makeSystolic()
    local C = require "generators.examplescommon"
    
    local s = C.automaticSystolicStub(res)

    local verilog = {res:vHeader()}

    table.insert(verilog, "  reg ["..(maxRate*H*A:verilogBits()-1)..":0] R;\n")
    local PHASES = maxRate/minRate
    local phaseBits = math.ceil((math.log(PHASES)/math.log(2))+1)
    -- phase 0: indicates full (if Ser) or empty (if Deser)
    table.insert(verilog, "  reg ["..(phaseBits-1)..":0] phase;\n")
    
    if math.max(inputRate,1)>math.max(outputRate,1) then
      -- Ser: eg 8 to 4

      -- for dumb reasons, we buffer the data in row major order, but need to write it out as column major
      local COLTOROW = {}
      for chunk=0,(maxRate/minRate)-1 do
        for y=0,H-1 do
          local OR = math.max(outputRate,1)
          for x=0,OR-1 do
            table.insert(COLTOROW,res:vInput().."["..(A:verilogBits()*((x+chunk*OR)+y*H+1)-1)..":"..(A:verilogBits()*((x+chunk*OR)+y*H)).."]")
          end
        end
      end
      
      table.insert(verilog, "  reg hasData;\n")

      table.insert(verilog,[[
  assign ]]..res:vInputReady()..[[ = (hasData==1'b0) || (]]..res:vOutputReady()..[[ && phase==]]..phaseBits..[['d]]..(PHASES-1)..[[);
  assign ]]..res:vOutputValid()..[[ = (hasData==1'b1);
  assign ]]..res:vOutputData()..[[ = R[]]..(A:verilogBits()*H*math.max(outputRate,1)-1)..[[:0];

  always @(posedge CLK) begin
    if (reset) begin
      phase <= ]]..phaseBits..[['d0;
      hasData <= 1'b0;
    end else begin
      if (]]..res:vInputValid().."&&"..res:vInputReady()..[[) begin
        R <=  {]]..table.concat(J.reverse(COLTOROW),",")..[[};
        hasData <= 1'b1;
        phase <= ]]..phaseBits..[['d0;
      end else if (hasData && ]]..res:vOutputReady()..[[) begin
        // step the buffers
        R <= {]]..(A:verilogBits()*H*math.max(outputRate,1))..[['d0,R[]]..(A:verilogBits()*H*maxRate-1)..":"..(A:verilogBits()*H*math.max(outputRate,1))..[[]};
        phase <= phase+]]..phaseBits..[['d1;
        if (phase==]]..phaseBits..[['d]]..(PHASES-1)..[[) begin
          hasData <= 1'b0;
          phase <= ]]..phaseBits..[['d0;
        end
      end
    end
  end
]])
    else
      -- inputRate <= outputRate. Deser: eg 4 to 8

      -- for dumb reasons, we buffer the data in column major order, but need to write it out as row major
      local COLTOROW = {}
      for y=0,H-1 do
        for x=0,math.max(outputRate,1)-1 do
          table.insert(COLTOROW,"R["..(A:verilogBits()*(x*H+y+1)-1)..":"..(A:verilogBits()*(x*H+y)).."]")
        end
      end

      local ROWTOCOL = {}
      local IRT = math.max(inputRate,1)
      for x=0,IRT-1 do
        for y=0,H-1 do
          table.insert(ROWTOCOL,res:vInput().."["..(A:verilogBits()*(x+y*IRT+1)-1)..":"..(A:verilogBits()*(x+y*IRT)).."]")
        end
      end
      
      table.insert(verilog,[[
  assign ]]..res:vOutputValid()..[[ = (phase==]]..phaseBits..[['d]]..PHASES..[[);
  assign ]]..res:vInputReady()..[[ = (]]..res:vOutputValid()..[[==1'b0) || (]]..res:vOutputValid()..[[ && ]]..res:vOutputReady()..[[);
  assign ]]..res:vOutputData()..[[ = {]]..table.concat(J.reverse(COLTOROW),",")..[[};

  always @(posedge CLK) begin
    if (reset) begin
      phase <= ]]..phaseBits..[['d0;
    end else begin
      if (]]..res:vOutputValid()..[[ && ]]..res:vOutputReady()..[[) begin
        if (]]..res:vInputValid().."&&"..res:vInputReady()..[[) begin
          phase <= ]]..phaseBits..[['d1; // reading and writing in the same cycle
        end else begin
          phase <= ]]..phaseBits..[['d0;
        end
      end else if (]]..res:vInputValid().."&&"..res:vInputReady()..[[) begin
        phase <= phase+]]..phaseBits..[['d1;
      end

      if (]]..res:vInputValid().."&&"..res:vInputReady()..[[) begin]])
                   if math.max(inputRate,1)==math.max(outputRate,1) then
table.insert( verilog,[[        R <= ]]..res:vInputData()..";")
                   else
table.insert(verilog,[[        R <= {]]..table.concat(J.reverse(ROWTOCOL),",")..[[,R[]]..(A:verilogBits()*H*maxRate-1)..[[:]]..(A:verilogBits()*H*math.max(inputRate,1))..[[]};]])
                   end
table.insert(verilog,[[      end
    end
  end
]])
    end

    table.insert(verilog,[[
endmodule

]])
    
    s:verilog( table.concat(verilog,"") )

    return s
  end

  if terralib~=nil then res.terraModule = MT.changeRate(res, A, H, inputRate, outputRate,maxRate,outputCount,inputCount ) end

  return rigel.newFunction(res)
end)

--StatefulRV. Takes A[inputRate,H] in, and buffers to produce A[outputRate,H]
-- 'rate' has a strange meaning here: 'rate' means size of array.
--     so inputRate=2 means 2items/clock (2 wide array)
-- framedW/H: these are the size of the whole array. So, when framed, we expect input:
--    [inputRate,H;framedW,framedH} to [outputRate,H;framedW,framedH}
modules.changeRateNonFIFO = memoize(function(A, H, inputRate, outputRate, framed, framedW, framedH, X)
  err( types.isType(A), "changeRate: A should be a type")
  err( type(H)=="number", "changeRate: H should be number")
  err( H>0,"changeRate: H must be >0, but is: ",H)
  err( type(inputRate)=="number", "changeRate: inputRate should be number, but is: "..tostring(inputRate))
  err( inputRate>=0, "changeRate: inputRate must be >=0")
  err( inputRate==math.floor(inputRate), "changeRate: inputRate should be integer")
  err( type(outputRate)=="number", "changeRate: outputRate should be number, but is: "..tostring(outputRate))
  err( outputRate==math.floor(outputRate), "changeRate: outputRate should be integer, but is: "..tostring(outputRate))
  if framed==nil then framed=false end
  err( type(framed)=="boolean","changeRate: framed must be boolean")
  err( X==nil, "changeRate: too many arguments")

  local maxRate = math.max(inputRate,outputRate)

  err( inputRate==0 or maxRate % inputRate == 0, "maxRate ("..tostring(maxRate)..") % inputRate ("..tostring(inputRate)..") ~= 0")
  err( outputRate==0 or maxRate % outputRate == 0, "maxRate ("..tostring(maxRate)..") % outputRate ("..tostring(outputRate)..") ~=0")
  rigel.expectBasic(A)

  local inputCount = maxRate/math.max(inputRate,1)
  local outputCount = maxRate/math.max(outputRate,1)

  local res = {kind="changeRate", type=A, H=H, inputRate=inputRate, outputRate=outputRate}

  if inputRate>outputRate then
    -- 8->4
    res.inputBurstiness = 0
    res.outputBurstiness = 0
    res.delay = 0
  else
    -- 4->8
    res.inputBurstiness = 0
    res.outputBurstiness = 0
    res.delay = 0
    res.RVDelay = (math.max(outputRate,1)/math.max(inputRate,1))-1
  end
  
  
  if framed then
    err(type(framedW)=="number", "changeRate: if framed, framedW should be number, but is: "..tostring(framedW))
    assert(type(framedH)=="number")
    assert(inputRate==0 or framedW%inputRate==0)
    assert(outputRate==0 or framedW%outputRate==0)
    
    if inputRate==0 then
      assert(framedH==1)
      assert(H==1)
      res.inputType = types.rv(types.Seq(types.Par(A),framedW,framedH))
    elseif inputRate<framedW then
      assert(H==framedH)
      res.inputType = types.rv(types.ParSeq(types.array2d(A,inputRate,H),framedW,framedH))
    elseif inputRate==framedW then
      assert(H==framedH)
      res.inputType = types.rv(types.Par(types.array2d(A,inputRate,H)))
    else
      assert(false)
    end

    if outputRate==0 then
      assert(framedH==1)
      assert(H==1)
      res.outputType = types.rRvV(types.Seq(A,framedW,framedH))
    elseif outputRate<framedW then
      assert(framedH==H)
      res.outputType = types.rRvV(types.ParSeq(types.array2d(A,outputRate,H),framedW,framedH))
    elseif outputRate==framedW then
      assert(framedH==H)
      res.outputType = types.rRvV(types.Par(types.array2d(A,framedW,framedH)))
    else
      assert(false)
    end
  else
    if inputRate==0 then
      assert(H==1)
      res.inputType = types.rv(types.Par(A))
    else
      res.inputType = types.rv(types.Par(types.array2d(A,inputRate,H)))
    end

    if outputRate==0 then
      assert(H==1)
      res.outputType = types.rRvV(types.Par(A))
    else
      res.outputType = types.rRvV(types.Par(types.array2d(A,outputRate,H)))
    end
  end
  
  res.stateful = true

  res.name = J.verilogSanitize("ChangeRate_"..tostring(A).."_from"..inputRate.."_to"..outputRate.."_H"..H.."_framed"..tostring(framed).."_framedW"..tostring(framedW).."_framedH"..tostring(framedH))

  if inputRate>outputRate then -- 8 to 4
    res.sdfInput, res.sdfOutput = SDF{math.max(outputRate,1),math.max(inputRate,1)},SDF{1,1}
  else -- 4 to 8
    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{math.max(inputRate,1),math.max(outputRate,1)}
  end

  function res.makeSystolic()
    local systolicModule= Ssugar.moduleConstructor(res.name)

    local svalid = S.parameter("process_valid", types.bool() )
    local rvalid = S.parameter("reset", types.bool() )
    local pinp = S.parameter("process_input", rigel.lower(res.inputType,res.outputType) )
    
    if inputRate>outputRate then
      -- 8 to 4
      local shifterReads = {}
            
      for i=0,outputCount-1 do
        table.insert(shifterReads, S.slice( pinp, i*math.max(outputRate,1), (i+1)*math.max(outputRate,1)-1, 0, H-1 ) )
      end
      local out, pipelines, resetPipelines, ready = fpgamodules.addShifterSimple( systolicModule, shifterReads, DARKROOM_VERBOSE )

      if outputRate==0 then
        out = S.index(out,0)
      end
      
      local CE = S.CE("CE")
      systolicModule:addFunction( S.lambda("process", pinp, S.tuple{ out, S.constant(true,types.bool()) }, "process_output", pipelines, svalid, CE) )
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", resetPipelines, rvalid ) )
      systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), ready, "ready", {} ) )
      
    else -- inputRate <= outputRate. 4 to 8
      --assert(H==1) -- NYI

      
      local sPhase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.incIfWrap( types.uint(16), inputCount-1) ):CE(true):setReset(0):instantiate("phase_changerateup") )
      local printInst
      if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(16),types.array2d(A,outputRate)}, "phase %d buffer %h", true ):instantiate("printInst") ) end
      local ConstTrue = S.constant(true,types.bool())
      local CE = S.CE("CE")
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", { sPhase:reset() }, rvalid ) )
      
      -- in the first cycle (first time inputPhase==0), we don't have any data yet. Use the sWroteLast variable to keep track of this case
      local validout = S.eq(sPhase:get(),S.constant(inputCount-1,types.uint(16))):disablePipelining()
      
      local out
      if inputRate==0 then
        assert(H==1)
        local delayedVals = J.map(J.range(inputCount-1,0), function(i) return pinp(i) end)
        out = S.cast( S.tuple(delayedVals), types.array2d(A,outputRate,H) )
      else
        out = concat2dArrays(J.map(J.range(inputCount-1,0), function(i) return pinp(i) end))
      end
      
      local pipelines = {sPhase:setBy(ConstTrue)} 
      if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process(S.tuple{sPhase:get(),out})) end
      
      systolicModule:addFunction( S.lambda("process", pinp, S.tuple{out,validout}, "process_output", pipelines, svalid, CE) )
      systolicModule:addFunction( S.lambda("ready", S.parameter("readyinp",types.null()), ConstTrue, "ready" ) )
    end

    return systolicModule
  end

  if terralib~=nil then res.terraModule = MT.changeRateOld(res, A, H, inputRate, outputRate,maxRate,outputCount,inputCount ) end

  return modules.waitOnInput(rigel.newFunction(res))
end)

modules.linebuffer = memoize(function( A, w_orig, h, T, ymin, framed, X )
  assert(Uniform(w_orig):toNumber()>0);
  assert(h>0);
  assert(ymin<=0)
  err(X==nil,"linebuffer: too many args!")
  err( framed==nil or type(framed)=="boolean", "modules.linebuffer: framed must be bool or nil")
  err( type(T)=="number" and T>=0,"modules.linebuffer: T must be number >=0")
  if framed==nil then framed=false end
  
  -- if W%T~=0, then we would potentially have to do two reads on wraparound. So don't allow this case.
  if T>0 then
    err( (Uniform(w_orig)%Uniform(T)):eq(0):assertAlwaysTrue(), "Linebuffer error, W%T~=0 , W="..tostring(w_orig).." T="..tostring(T))
  end
  
  local res = {kind="linebuffer", type=A, T=T, w=w_orig, h=h, ymin=ymin }
  --rigel.expectBasic(A)

  err( types.isType(A) and A:isData(), "Linebuffer: input should be data type, but is: "..tostring(A))
  if T==0 then
    res.inputType = A
    res.outputType = types.array2d(A,1,-ymin+1)
  else
    res.inputType = types.array2d(A,T)
    res.outputType = types.array2d(A,T,-ymin+1)
  end
  
  if framed then
    --res.inputType = types.StaticFramed(res.inputType,true,{{w,h}})
    -- this is strange for a reason: inner loop is no longer a serialized flat array, so size must change
    --res.outputType = types.StaticFramed(res.outputType,false,{{w/T,h}})
    --T[1,ymin][T;w,h}
    if T==0 then
      res.inputType = types.rv(types.Seq(types.Par(A),w_orig,h))
      res.outputType = types.rv(types.Seq(types.Par(types.array2d(A,1,-ymin+1)),w_orig,h))
    else
      res.inputType = types.rv(types.ParSeq(res.inputType,w_orig,h))
      res.outputType = types.rv(types.ParSeq(types.array2d(types.array2d(A,1,-ymin+1),T),w_orig,h))
    end
  else
    res.inputType = types.rv(types.Par(res.inputType))
    res.outputType = types.rv(types.Par(types.array2d(A,math.max(T,1),-ymin+1)))
  end
  
  res.stateful = true
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
  res.delay = -ymin
  res.name = sanitize("linebuffer_w"..tostring(w_orig).."_h"..tostring(h).."_T"..tostring(T).."_ymin"..tostring(ymin).."_A"..tostring(A).."_framed"..tostring(framed))

  if terralib~=nil then res.terraModule = MT.linebuffer(res, A, Uniform(w_orig):toNumber(), h, T, ymin, framed ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local sinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local addr = systolicModule:add( fpgamodules.regBy( types.uint(16), fpgamodules.incIfWrap( types.uint(16), (Uniform(w_orig):toNumber()/math.max(T,1))-1), true, nil, 0 ):instantiate("addr") )
    
    local outarray = {}
    local evicted
    
    local bits = rigel.lower(res.inputType):verilogBits()
    local bytes = J.nearestPowerOf2(J.upToNearest(8,bits)/8)
    local sizeInBytes = J.nearestPowerOf2((Uniform(w_orig):toNumber()/math.max(T,1))*bytes)

    local bramMod = fpgamodules.bramSDP( true, sizeInBytes, bytes, nil, nil, true )
    local addrbits = math.log(sizeInBytes/bytes)/math.log(2)
    
    for y=0,-ymin do
      local lbinp = evicted
      if y==0 then lbinp = sinp end

      if T>0 then
        for x=1,T do outarray[x+(-ymin-y)*T] = S.index(lbinp,x-1) end
      else
        outarray[-ymin-y+1] = lbinp
      end
      
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

    local finalOut
    
    if framed and T>0 then
      local results = {}
      for v=1,T do
        local thisV = {}
        for y=ymin,0 do
          local yidx = y-ymin
          table.insert(thisV,outarray[yidx*T+v])
        end
        table.insert( results, S.cast( S.tuple( thisV ), types.array2d(A,1,-ymin+1) ) )
      end
      finalOut = S.cast( S.tuple( results ), rigel.lower(res.outputType) )
    else
      finalOut = S.cast( S.tuple( outarray ), rigel.lower(res.outputType) )
    end
    
    systolicModule:addFunction( S.lambdaTab
      { name="process", 
        input=sinp, 
        output=finalOut, 
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

  res = rigel.newFunction(res)

  if terralib~=nil then res.terraModule = MT.sparseLinebuffer( res, A, imageW, imageH, rowWidth, ymin, defaultValue) end

  return res
end)

-- xmin, ymin are inclusive
modules.SSR = memoize(function( A, T, xmin, ymin, framed, framedW_orig, framedH_orig, X )
  err( types.isType(A) and A:isData(),"SSR: type should be data type")
  J.map({T,xmin,ymin}, function(i) assert(type(i)=="number") end)
  err( ymin<=0, "modules.SSR: ymin>0")
  err( xmin<=0, "module.SSR: xmin>0")
  err( T>=0, "modules.SSR: T<0")
  if framed==nil then framed=false end
  err(type(framed)=="boolean","SSR: framed must be boolean")
  err( X==nil,"SSR: too many arguments")
  
  local res = {kind="SSR", type=A, T=T, xmin=xmin, ymin=ymin }

  if framed then
    err(type(framedW_orig)=="number" or Uniform.isUniform(framedW_orig),"SSR: framedW must be uniform or number")
    err(type(framedH_orig)=="number" or Uniform.isUniform(framedH_orig),"SSR: framedH must be uniform or number")
    if T==0 then
      res.inputType = types.Seq( types.Par(types.array2d(A,1,-ymin+1)),framedW_orig,framedH_orig)
      res.outputType = types.Seq(types.Par(types.array2d(A,-xmin+1,-ymin+1)),framedW_orig,framedH_orig)
    else
      res.inputType = types.ParSeq(types.array2d(types.array2d(A,1,-ymin+1),T),framedW_orig,framedH_orig)
      res.outputType = types.ParSeq(types.array2d(types.array2d(A,-xmin+1,-ymin+1),T),framedW_orig,framedH_orig)
    end
  else
    assert(T>0) -- NYI
    res.inputType = types.array2d(A,T,-ymin+1)
    res.outputType = types.array2d(A,T-xmin,-ymin+1)

    res.inputType, res.outputType = types.Par(res.inputType), types.Par(res.outputType)
  end

  res.inputType, res.outputType = types.rv(res.inputType), types.rv(res.outputType)
  
  res.stateful = (xmin<0)
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
  res.delay=0
  res.name = verilogSanitize("SSR_W"..(-xmin+1).."_H"..(-ymin+1).."_T"..tostring(T).."_A"..tostring(A).."_XMIN"..tostring(xmin).."_YMIN"..tostring(ymin).."_framed"..tostring(framed).."_framedW"..tostring(framedW_orig).."_framedH"..tostring(framedH_orig))

  if terralib~=nil then res.terraModule = MT.SSR(res, A, T, xmin, ymin, framed ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local sinp = S.parameter("inp", rigel.lower(res.inputType))
    local pipelines = {}
    local SR = {}
    local out = {}
    local Tf = math.max(T,1) -- fix for when T==0
    for y=0,-ymin do 
      SR[y]={}
      local x = -xmin+Tf-1
      while(x>=0) do
        if x<-xmin-Tf then
          SR[y][x] = systolicModule:add( S.module.reg(A,true):instantiate(J.sanitize("SR_x"..x.."_y"..y)) )
          table.insert( pipelines, SR[y][x]:set(SR[y][x+Tf]:get()) )
          out[y*(-xmin+Tf)+x+1] = SR[y][x]:get()
        elseif x<-xmin then
          SR[y][x] = systolicModule:add( S.module.reg(A,true):instantiate(J.sanitize("SR_x"..x.."_y"..y) ) )

          local val
          if framed and T>0 then
            val = S.index(S.index(sinp,x+(Tf+xmin)),0,y)
          else
            val = S.index(sinp,x+(Tf+xmin),y )
          end
          
          table.insert( pipelines, SR[y][x]:set(val) )
          out[y*(-xmin+Tf)+x+1] = SR[y][x]:get()
        else -- x>-xmin
          local val
          if framed and T>0 then
            val = S.index(sinp,x+xmin)
            val = S.index(val,0,y)
          else
            val = S.index(sinp,x+xmin,y )
          end

          out[y*(-xmin+Tf)+x+1] = val
        end

        x = x - 1
      end
    end

    local finalOut
    
    if framed and T>0 then
      local results = {}
      for v=1,T do
        local thisV = {}
        for y=ymin,0 do
          local yidx = y-ymin
          for x = xmin,0 do
            local xidx = x-xmin
            table.insert(thisV,out[yidx*(-xmin+T)+xidx+(v-1)+1])
          end
        end
        table.insert( results, S.cast( S.tuple( thisV ), types.array2d(A,-xmin+1,-ymin+1) ) )
      end
      finalOut = S.cast( S.tuple( results ), rigel.lower(res.outputType) )
    else
      finalOut = S.cast( S.tuple( out ), rigel.lower(res.outputType) )
    end

    local CE
    if res.stateful then
      CE = S.CE("process_CE")
      systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", nil, S.parameter("reset",types.bool()) ) )
    end
    
    systolicModule:addFunction( S.lambda("process", sinp, finalOut, "process_output", pipelines, nil, CE ) )
    
    return systolicModule
  end

  return rigel.newFunction(res)
end)

-- T: the number of cycles to take to emit the stencil. IE T=4 => serialize the stencil and send it out over 4 cycles.
modules.SSRPartial = memoize(function( A, T, xmin, ymin, stride, fullOutput, framed_orig, framedW_orig, framedH_orig, X )
  err(T>=1,"SSRPartial: T should be >=1")
  assert(X==nil)

  local framed = framed_orig
  if framed==nil then
    framed=false
  end
  
  if stride==nil then
    local Weach = (-xmin+1)/T
    err(Weach==math.floor(Weach),"SSRPartial: requested parallelism does not divide stencil size. xmin=",xmin," ymin=",ymin," T=",T)
    stride=Weach
  end

  if fullOutput==nil then fullOutput=false end 

  local res = {kind="SSRPartial", type=A, T=T, xmin=xmin, ymin=ymin, stride=stride, fullOutput=fullOutput, stateful=true }

  if framed then
    err(type(framedW_orig)=="number" or Uniform.isUniform(framedW_orig),"SSR: framedW must be uniform or number")
    err(type(framedH_orig)=="number" or Uniform.isUniform(framedH_orig),"SSR: framedH must be uniform or number")
--    if T==0 then
--      res.inputType = types.Seq( types.Par(types.array2d(A,1,-ymin+1)),framedW_orig,framedH_orig)
--      res.outputType = types.Seq(types.Par(types.array2d(A,-xmin+1,-ymin+1)),framedW_orig,framedH_orig)
--    else
    res.inputType = types.rv(types.ParSeq(types.array2d(types.array2d(A,1,-ymin+1),1),framedW_orig,framedH_orig))
    res.outputType = types.rRvV(types.Seq(types.ParSeq(types.array2d(A,(-xmin+1)/T,-ymin+1),-xmin+1,-ymin+1),framedW_orig,framedH_orig))
--    end

    assert(fullOutput==false)
  else
    res.inputType = types.rv(types.Par(types.array2d(A,1,-ymin+1)))

    if fullOutput then
      res.outputType = types.rRvV(types.Par(types.array2d(A,(-xmin+1),-ymin+1)))
    else
      res.outputType = types.rRvV(types.Par(types.array2d(A,(-xmin+1)/T,-ymin+1)))
    end
  end
  
  res.sdfInput, res.sdfOutput = SDF{1,T},SDF{1,1}
  res.delay=0
  res.name = sanitize("SSRPartial_"..tostring(A).."_T"..tostring(T).."_fullOutput"..tostring(fullOutput).."_framed"..tostring(framed_orig).."_framedW"..tostring(framedW_orig).."_framedH"..tostring(framedH_orig))

  if terralib~=nil then res.terraModule =  MT.SSRPartial(res,A, T, xmin, ymin, stride, fullOutput, framed ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    local sinp_orig = S.parameter("process_input", rigel.lower(res.inputType) )

    local sinp= sinp_orig
    if framed then
      sinp = S.index(sinp_orig,0)
    end
    
    local P = T
    
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
    systolicModule:addFunction( S.lambda("process", sinp_orig, S.tuple{ shifterOut, processValid }, "process_output", shifterPipelines, processValid, CE) )
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
modules.makeHandshake = memoize(function( f, tmuxRates, nilhandshake, name, X )
  assert( rigel.isFunction(f) )
  if nilhandshake==nil then
    -- set nilhandshake=true by default if we are dealing with explicit trigger types
    nilhandshake = f.inputType:extractData():verilogBits()==0 or f.outputType:extractData():verilogBits()==0
  end
  err( type(nilhandshake)=="boolean", "makeHandshake: nilhandshake must be nil or boolean")
  assert( X==nil )
  
  local res = { kind="makeHandshake", fn = f, tmuxRates = tmuxRates }

  if tmuxRates~=nil then
    err(f.inputType:isrv() and f.inputType:deInterface():isData(),"makeHandshake fn input should be rvPar, but is: "..tostring(f.inputType))
    err(f.outputType:isrv() and f.outputType:deInterface():isData(),"makeHandshake fn output should be rvPar, but is: "..tostring(f.outputType))

    res.inputType = rigel.HandshakeTmuxed( f.inputType.over, #tmuxRates )
    res.outputType = rigel.HandshakeTmuxed (f.outputType.over, #tmuxRates )
    assert( SDFRate.isSDFRate(tmuxRates) )
    res.sdfInput, res.sdfOutput = SDF(tmuxRates), SDF(tmuxRates)
  else
    err( f.inputType:isrv() or f.inputType==types.Interface(),"makeHandshake: fn '"..f.name.."' input type should be rv or null, but is "..tostring(f.inputType) )
    err( f.outputType:isrv() or f.outputType==types.Interface(),"makeHandshake: fn '"..f.name.."' output type should be rv or null, but is "..tostring(f.outputType))

    if f.inputType==types.Interface() and nilhandshake==true then
      res.inputType = rigel.HandshakeTrigger
    elseif f.inputType~=types.Interface() and f.inputType:is("StaticFramed") then
      res.inputType = types.HandshakeFramed( f.inputType.params.A, f.inputType.params.mixed, f.inputType.params.dims )
    elseif f.inputType~=types.Interface() then
      res.inputType = rigel.Handshake(f.inputType.over)
    else
      res.inputType = types.Interface()
    end

    if f.outputType==types.Interface() and nilhandshake==true then
      res.outputType = rigel.HandshakeTrigger
    elseif f.outputType~=types.Interface() and f.outputType:is("StaticFramed") then
      res.outputType = types.HandshakeFramed( f.outputType.params.A, f.outputType.params.mixed, f.outputType.params.dims )
    elseif f.outputType~=types.Interface() then
      res.outputType = rigel.Handshake(f.outputType.over)
    else
      res.outputType = types.Interface()
    end

    J.err( rigel.SDF==false or f.sdfInput~=nil, "makeHandshake: fn is missing sdfInput? "..f.name )
    J.err( rigel.SDF==false or f.sdfOutput~=nil, "makeHandshake: fn is missing sdfOutput? "..f.name )
    
    J.err( rigel.SDF==false or #f.sdfInput==1, "makeHandshake expects SDF input rate of 1")
    J.err( rigel.SDF==false or f.sdfInput[1][1]:eq(f.sdfInput[1][2]):assertAlwaysTrue(), "makeHandshake expects SDF input rate of 1, but is: "..tostring(f.sdfInput))
    J.err( rigel.SDF==false or #f.sdfOutput==1, "makeHandshake expects SDF output rate of 1")
    J.err( rigel.SDF==false or f.sdfOutput[1][1]:eq(f.sdfOutput[1][2]):assertAlwaysTrue(), "makeHandshake of fn '"..f.name.."' expects SDF output rate of 1, but is: "..tostring(f.sdfOutput))

    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
  end

  assert(res.inputType~=nil)
  
  err(type(f.delay)=="number","MakeHandshake fn is missing delay? ",f)

  if f.RVDelay~=nil then
    -- not sure why this should be needed, but whatever...
    res.delay = f.RVDelay+f.delay
  else
    res.delay = f.delay
  end
  
  res.stateful = (f.delay>0) or f.stateful -- for the shift register of valid bits

  if name~=nil then
    assert(type(name)=="string")
    res.name = name
  else
    res.name = J.sanitize("MakeHandshake_HST_"..tostring(nilhandshake).."_"..f.name)
  end
  
  res.requires = {}
  for inst,fnmap in pairs(f.requires) do for fnname,_ in pairs(fnmap) do J.deepsetweak(res.requires,{inst,fnname},1) end end
  res.provides = {}
  for inst,fnmap in pairs(f.provides) do for fnname,_ in pairs(fnmap) do J.deepsetweak(res.provides,{inst,fnname},1) end end

  if terralib~=nil then res.makeTerra = function() return MT.makeHandshake(res, f, tmuxRates, nilhandshake ) end end

  function res.makeSystolic()
    -- We _NEED_ to set an initial value for the shift register output (invalid), or else stuff downstream can get strange values before the pipe is primed

    local systolicModule = Ssugar.moduleConstructor(res.name):parameters({INPUT_COUNT=0,OUTPUT_COUNT=0}):onlyWire(true)
    
    local outputCount
    
    local SRdefault = false
    if tmuxRates~=nil then SRdefault = #tmuxRates end

    local srtype = rigel.extractValid(res.inputType)
    if res.inputType==types.Interface() then srtype = rigel.extractValid(res.outputType) end

    local SRMod = fpgamodules.shiftRegister( srtype, f.systolicModule:getDelay("process"), SRdefault, true )
    local SR = systolicModule:add( SRMod:instantiate( J.sanitize("makeHSvalidBitDelay") ) )
    local inner = systolicModule:add(f.systolicModule:instantiate("inner"))

    local pinp = S.parameter("process_input", rigel.lower(res.inputType) )
    local rst = S.parameter("reset",types.bool())
    
    local pipelines = {}

    local pready = S.parameter("ready_downstream", types.bool())
    local CE = pready

    -- some modules may not require a CE (pure functions)
    local processCE = CE
    if f.systolicModule.functions.process.CE==nil then processCE=nil end
      
    local outvalid
    local out
    local inputNullary = f.inputType==types.Interface()
    local outputNullary = f.outputType==types.Interface()

    if inputNullary and outputNullary and nilhandshake==true then
      assert(false) -- NYI
    elseif inputNullary and nilhandshake==true then
      outvalid = SR:process( pinp, S.constant(true,types.bool()), CE)
      out = S.tuple({inner:process(nil,pinp,processCE), outvalid})
    elseif inputNullary and nilhandshake==false then
      outvalid = SR:process(S.constant(true,types.bool()), S.constant(true,types.bool()), CE)
      --table.insert(pipelines,inner:process(nil,pinp,CE))
      out = S.tuple({inner:process(nil,S.constant(true,types.bool()),processCE), outvalid})
    elseif outputNullary and nilhandshake==true then
      outvalid = SR:process(S.index(pinp,1), S.constant(true,types.bool()), CE)
      out = outvalid
      table.insert(pipelines,inner:process(S.index(pinp,0),S.index(pinp,1), processCE))
    elseif outputNullary and nilhandshake==false then
      table.insert(pipelines,inner:process(S.index(pinp,0),S.index(pinp,1), processCE))
    else
      outvalid = SR:process(S.index(pinp,1), S.constant(true,types.bool()), CE)
      out = S.tuple({inner:process(S.index(pinp,0),S.index(pinp,1), processCE), outvalid})
    end
    
    --[=[if DARKROOM_VERBOSE then
      local typelist = {types.bool(),rigel.lower(f.outputType), rigel.extractValid(res.outputType), types.bool(), types.bool(), types.uint(16), types.uint(16)}
      local str = "RST %d O %h OV %d readyDownstream %d ready %d outputCount %d expectedOutput %d"
      local lst = {rst, S.index(out,0), S.index(out,1), pready, pready, outputCount:get(), S.instanceParameter("OUTPUT_COUNT",types.uint(16)) }
      
      if res.inputType~=types.Interface() then
        table.insert(lst, S.index(pinp,1))
        table.insert(typelist, rigel.extractValid(res.inputType))
        str = str.." IV %d"
      end
      
      local printInst = systolicModule:add( S.module.print( types.tuple(typelist), str):instantiate("printInst") )
      table.insert(pipelines, printInst:process( S.tuple(lst)  ) )
      end]=]
    
    if tmuxRates~=nil then
      --if DARKROOM_VERBOSE then table.insert(pipelines,  outputCount:setBy(S.lt(outvalid,S.constant(#tmuxRates,types.uint(8))), S.__not(rst), CE) ) end
    else
      --if DARKROOM_VERBOSE then table.insert(pipelines,  outputCount:setBy(outvalid, S.constant(true,types.bool()), CE) ) end
    end
    
    systolicModule:addFunction( S.lambda("process", pinp, out, "process_output", pipelines) ) 
    
    local resetOutput
    if f.stateful then
      resetOutput = inner:reset(nil,rst)
    end
    
    local resetPipelines = {}
    table.insert( resetPipelines, SR:reset(nil,rst) )
    --if DARKROOM_VERBOSE then table.insert( resetPipelines, outputCount:set(S.constant(0,types.uint(16)),rst,CE) ) end

    if res.stateful then
      systolicModule:addFunction( S.lambda("reset", S.parameter("rst",types.null()), resetOutput, "reset_out", resetPipelines,rst) )
    end
    
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
-- VRStore: make the store function be HandshakeVR
modules.fifo = memoize(function( A, size, nostall, W, H, T, csimOnly, VRLoad, SDFRate, VRStore, includeSizeFn, dbgname, X )
  err( types.isType(A), "fifo: type must be type")
  err( A:isData() or A:isSchedule(),"fifo: type must be data type or schedule type")
  err( type(size)=="number", "fifo: size must be number")
  err( size >0,"fifo: size must be >0")
  err( size <=32768/2,"fifo: size must be <32768 (max items in a BRAM). size:",size)
  err(nostall==nil or type(nostall)=="boolean", "fifo: nostall should be nil or boolean")
  err(W==nil or type(W)=="number", "W should be nil or number")
  err(H==nil or type(H)=="number", "H should be nil or number")
  err(T==nil or type(T)=="number", "T should be nil or number")
  assert(csimOnly==nil or type(csimOnly)=="boolean")
  if csimOnly==nil then csimOnly=false end
  if VRLoad==nil then VRLoad=false end
  err( type(VRLoad)=="boolean","fifo: VRLoad should be boolean")
  if VRStore==nil then VRStore=false end
  err( type(VRStore)=="boolean","fifo: VRStore should be boolean")
  assert( dbgname==nil or type(dbgname)=="string" )

  if SDFRate==nil then SDFRate=SDF{1,1} end
  err( SDF.isSDF(SDFRate),"modules.fifo: SDFRate must be nil or SDF rate")

  if includeSizeFn==nil then includeSizeFn=false end
  
  assert(X==nil)

  local storeFunction = {name="store", outputType=types.Interface(), sdfInput=SDFRate, sdfOutput=SDFRate, stateful=(csimOnly~=true), sdfExact=true, delay=0}

  if VRStore then
    storeFunction.inputType = types.HandshakeVR(A)
  else
    storeFunction.inputType = types.Handshake(A)
  end

  local loadFunction = {name="load", inputType=types.Interface(), sdfInput=SDFRate, sdfOutput=SDFRate, stateful=(csimOnly~=true), sdfExact=true, delay=1}
  
  if VRLoad then
    loadFunction.outputType = types.HandshakeVR(A)
  else
    loadFunction.outputType = types.Handshake(A)
  end
  
  if A==types.null() then
    storeFunction.inputType=rigel.HandshakeTrigger
    loadFunction.outputType=rigel.HandshakeTrigger
  end

  local storeRigelFn = rigel.newFunction(storeFunction)
  local loadRigelFn = rigel.newFunction(loadFunction)

  local addrBits = (math.ceil(math.log(size)/math.log(2)))+1
  local sizeRigelFn
  if includeSizeFn then
    sizeRigelFn = rigel.newFunction{name="size",inputType=types.null(),outputType=types.uint(addrBits),sdfInput=SDF{1,1},sdfOutput=SDF{1,1},delay=0,stateful=(csimOnly~=true)}
  end

  local dbgMonitor = ""
  if false then
  dbgMonitor  = [[  // debug monitor
  reg [31:0] totalCycles=32'd0;
  reg [31:0] stalledCycles=32'd0;
  reg [31:0] downstreamStalledCycles=32'd0;
  reg printed = 1'b1;

  always @(posedge CLK) begin
    if (reset) begin
      if (printed==1'b0 ) begin
        $display("|]]..J.verilogSanitizeInner(tostring(dbgname)).."|"..size.."|"..tostring(A)..[[|%0d|%0d|%0d", stalledCycles, downstreamStalledCycles, totalCycles );
      end
      totalCycles <= 32'd0;
      stalledCycles <= 32'd0;
      downstreamStalledCycles <= 32'd0;
      printed <= 1'b1;
    end else begin
      printed <= 1'b0;
      totalCycles <= totalCycles+32'd1;
      if(store_ready==1'b0) begin
        stalledCycles <= stalledCycles + 32'd1;
      end
      if( load_ready_downstream==1'b0) begin
        downstreamStalledCycles <= downstreamStalledCycles + 32'd1;
      end
    end
  end
]]
  end
  
  if size==1 and (csimOnly==false) then
    local name = J.sanitize("OneElementFIFO_"..tostring(A).."_dbgname"..tostring(dbgname))
    local vstr=[[module ]]..name..[[(input wire CLK, output wire []]..tostring(A:lower():verilogBits())..[[:0] load_output, input wire reset, output wire store_ready, input wire load_ready_downstream, input wire []]..tostring(A:lower():verilogBits())..[[:0] store_input);
  parameter INSTANCE_NAME="INST";
  reg hasItem;
  reg []]..tostring(A:lower():verilogBits()-1)..[[:0] dataBuffer;

  wire store_valid;
  assign store_valid = store_input[]]..tostring(A:lower():verilogBits())..[[];

  always @(posedge CLK) begin
    if (reset) begin
      hasItem <= 1'b0;
    end else begin
      if (store_valid && (load_ready_downstream || hasItem==1'b0) ) begin
        // input is valid and we can accept it
        hasItem <= 1'b1;
        dataBuffer <= store_input[]]..tostring(A:lower():verilogBits()-1)..[[:0];
      end else if (load_ready_downstream) begin
        // buffer is being emptied
        hasItem <= 1'b0;
      end
    end
  end

  assign load_output = {hasItem,dataBuffer};
  assign store_ready = (hasItem==1'b0)||load_ready_downstream;

]]..dbgMonitor..[[

endmodule

]]

    local mod =  modules.liftVerilogModule(name, vstr, {load=loadRigelFn,store=storeRigelFn}, true)
    if terralib~=nil then mod.terraModule = MT.fifo( mod, storeRigelFn.inputType, loadRigelFn.outputType, A, 2, nostall, W, H, T, csimOnly, dbgname ) end
return mod
  else
    local bytes = (size*A:verilogBits())/8
    
    local name = sanitize("fifo_SIZE"..size.."_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_BYTES"..tostring(bytes).."_nostall"..tostring(nostall).."_csimOnly"..tostring(csimOnly).."_VRLoad"..tostring(VRLoad).."_VRS"..tostring(VRStore).."_SZFN"..tostring(includeSizeFn).."_RATE"..tostring(SDFRate).."_dbgname"..tostring(dbgname))

    local res = rigel.newModule{ kind="fifo", name=name, functions={store=storeRigelFn, load=loadRigelFn, size=sizeRigelFn}, stateful=(csimOnly~=true) }

    if terralib~=nil then res.terraModule = MT.fifo( res, storeRigelFn.inputType, loadRigelFn.outputType ,A, size, nostall, W, H, T, csimOnly, dbgname ) end

    local fifo
    if csimOnly then
      res.makeSystolic = function()
        return fpgamodules.fifonoop( A, addrBits, name )
      end
    else
      res.makeSystolic = function()
        local C = require "generators.examplescommon"
        local s = C.automaticSystolicStub( res )
        
        local allocatedItems
        local allocatedBits
        local addrBits
        
        local ramMod 
        local ramInst
        local brammode
        if size<=128 then
          allocatedItems = 128
          allocatedBits = A:lower():verilogBits()
          addrBits = 7
          brammode=false
          ramMod = fpgamodules.sliceRamGen( allocatedBits ):complete()
          --if Ssugar.isModuleConstructor(ramMod) then ramMod = ramMod:complete() end
          ramInst = ramMod:instantiate("ram")
          s:add( ramInst )
          
          local rd = ramInst.read( ramInst, S.constant(0,types.uint(addrBits)), S.constant(true,types.bool()), S.constant(true,types.bool()) )
          s:lookupFunction("load"):addPipeline(rd)
          local wr = ramInst.write( ramInst, S.tuple{S.constant(0,types.uint(addrBits)),S.constant(0,types.bits(A:lower():verilogBits()))}, S.constant(true,types.bool()), S.constant(true,types.bool()) )
          s:lookupFunction("store"):addPipeline(wr)
        else
          brammode=true
          allocatedItems = J.nearestPowerOf2(size)
          addrBits = math.log(allocatedItems)/math.log(2)
          
          local allocatedBytes = math.ceil(A:lower():verilogBits()/8)
          allocatedBits = allocatedBytes * 8
          ramMod = fpgamodules.bramSDP( true, allocatedItems*allocatedBytes, allocatedBytes, allocatedBytes, nil, true ):complete()

          ramInst = ramMod:instantiate("ram")
          s:add( ramInst )
          
          local rd = ramInst.read( ramInst, S.constant(0,types.uint(addrBits)), S.constant(true,types.bool()), S.constant(true,types.bool()) )
          s:lookupFunction("load"):addPipeline(rd)
          local wr = ramInst.writeAndReturnOriginal( ramInst, S.tuple{S.constant(0,types.uint(addrBits)),S.constant(0,types.bits(allocatedBits))}, S.constant(true,types.bool()), S.constant(true,types.bool()) )
          s:lookupFunction("store"):addPipeline(wr)
        end
        
        err(S.isModule(ramMod),"ram was not a systolic module? size:",size, " bits ",allocatedBits,ramMod)
        
        local verilog = {res:vHeader()}
        table.insert( verilog, ramMod:instanceToVerilogStart(ramInst) )
        table.insert( verilog,[[
reg [31:0] readAddr;
reg [31:0] writeAddr;
wire [31:0] size;
assign size = writeAddr-readAddr;
assign store_ready = size < 32'd]]..size..[[;
wire hasData;
assign hasData = size>32'd0;

wire reading;

]] )
        if brammode then
          -- brams have a 1 cycle delay on read! we always queue up the next address asap, but if FIFO is empty, we do need to wait one cycle

          -- if bram is 'preloaded', this means that BRAM address is one ahead of actual readAddr, but ReadEnable hasn't been flipped yet
          -- this means output port of BRAM contains the next token we need (available immediately), and next cycle the next one is available
          --
          -- another way to say this: readAddr is the address we want to read _this_ cycle. But ram will be a cycle behind. So if addr X is readAddr
          -- this cycle, X must have been the ram_readAddr the last time RE was true.
          --
          -- to accomlish this, we have readAddrNext, which is basically running one ahead of readAddr, and is the next addr we need to queue up
          -- this is tricky to implement, b/c readAddrNext has to behave the same as readAddr (has to wrap the same, and FIFO size check has to happen the same way!)
          --
          -- but: if you pretend readAddrNext basically follows the same rules as readAddr, it's just one ahead, the logic isn't actually too complex
          table.insert(verilog,[[
reg [31:0] readAddrNext;
wire preloading; // this is basically like reading, but runs ahead
wire hasDataNext;
assign hasDataNext = (writeAddr-readAddrNext)>32'd0;
assign preloading = hasDataNext && (load_ready_downstream || preloaded==1'b0);
reg preloaded;
wire load_valid;
always @(posedge CLK) begin
  if ( reset ) begin
    preloaded <= 1'b0;
    readAddrNext <= 32'd0;
  end else begin
    if ( readAddr==32'd]]..(allocatedItems-1)..[[ && reading ) begin // time for pointers to wrap
      if( preloading ) begin
        readAddrNext <= readAddrNext - 32'd]]..(allocatedItems-1)..[[; 
        preloaded <= 1'b1;
      end else begin
        readAddrNext <= readAddrNext - 32'd]]..allocatedItems..[[; 
        preloaded <= 1'b0;
      end
    end else if( preloading ) begin
      readAddrNext <= readAddrNext + 32'd1;
      preloaded <= 1'b1;
    end else if (load_ready_downstream) begin
      // if load_ready_downstream is true, and somehow we aren't preloading, that means preload failed
      // ie: we need to introduce a cycle of delay
      preloaded <= 1'b0;
    end
  end
//$display("FIFO ]]..size..[[ size:%d preloaded:%d preloading:%d ram_RE:%d readAddr:%3d ram_readAddr:%3d writeAddr:%3d load_valid:%d readDS:%d data:%d\n",size,preloaded, preloading, ram_RE, readAddr, ram_readAddr, writeAddr, load_valid, load_ready_downstream, load_output[]]..(A:extractData():verilogBits()-1)..[[:0]  );
end

assign ram_RE = preloading; //load_ready_downstream || ( preloaded==1'b0 );
assign ram_readAddr = readAddrNext[]]..(addrBits-1)..[[:0];
assign load_valid = preloaded; // ram buffer slot contains readAddr
]])
        else
          table.insert(verilog,[[wire load_valid;
assign load_valid = size>32'd0;
assign ram_RE = load_ready_downstream;
assign ram_readAddr = readAddr[]]..(addrBits-1)..[[:0];

]])
        end

        table.insert(verilog,[[assign load_output = {load_valid,ram_readOut[]]..(A:lower():verilogBits())..[[-1:0]};
assign reading = load_valid && load_ready_downstream;


wire store_valid;
assign store_valid = store_input[]]..(A:lower():verilogBits())..[[];

wire writing;
assign writing = store_ready && store_valid;

assign ram_WE = 1'b1;
assign ram_]]..J.sel(brammode,"writeAndReturnOriginal","write")..[[_valid = writing;
assign ram_writeAddrAndData = {]]..J.sel(brammode and A:lower():verilogBits()<J.upToNearest(8,A:lower():verilogBits()),tostring(J.upToNearest(8,A:lower():verilogBits())-A:lower():verilogBits()).."'d0,","")..[[store_input[]]..(A:lower():verilogBits()-1)..[[:0],writeAddr[]]..(addrBits-1)..[[:0]};

always @(posedge CLK) begin
  if (reset) begin
    readAddr <= 32'd0;    
    writeAddr <= 32'd0;
  end else begin
    if ( readAddr==32'd]]..(allocatedItems-1)..[[ && reading ) begin // we need to wrap around
      readAddr <= 32'd0;
      if (writing) begin 
        writeAddr <= writeAddr - 32'd]]..(allocatedItems-1)..[[; 
      end else begin
        writeAddr <= writeAddr - 32'd]]..allocatedItems..[[; 
      end
    end else begin
      if (reading) begin readAddr <= readAddr + 32'd1; end
      if (writing) begin writeAddr <= writeAddr + 32'd1; end
    end
  end 

  //$display("size %d reading %d writing %d readAddr %d readDat %x writeAddr %d writeDat %x",size,reading,writing,readAddr, ram_readOut, writeAddr, ram_writeAddrAndData[71:8]);
end
]])

        
        if true then
          -- extra debug stuff

          table.insert(verilog,dbgMonitor)
          
table.insert(verilog,[[          
reg [31:0] numRead = 32'd0;
reg [31:0] numWritten = 32'd0;

always @(posedge CLK) begin
  if( reset) begin
    if( numRead!=numWritten ) begin
      $display("SEVERE WARNING: FIFO INPUTS/OUTPUTS DONT MATCH AT RESET. THIS MEANS SOME STATE WASNT FULLY CLEAR AT RESET TIME. CHECK PADSEQS. stored:%0d loaded:%0d ]]..J.verilogSanitizeInner(res.name)..[[",numWritten, numRead);
    end

    numRead <= 32'd0;
    numWritten <= 32'd0;
  end else begin
    if(store_valid && store_ready) begin
      numWritten <= numWritten + 32'd1;
    end
    if(load_valid && load_ready_downstream) begin
      numRead <= numRead + 32'd1;
    end

    if(numRead>numWritten) begin
      $display("ERROR: MORE OUTPUTS FROM FIFO THAN INPUTS!");
    end
  end
end

]])
        end
        
        table.insert(verilog,[[
endmodule

]])
        
        s:verilog(table.concat(verilog,""))
          
        return s
      end
    end
return res
  end

  assert(false)
end)

modules.triggerFIFO = memoize(function(ty)
  assert(ty==nil or ty:isSchedule())

  local portType
  if ty==nil then
    portType=types.HandshakeTrigger
  else
    assert(ty:extractData():verilogBits()==0)
    portType = types.RV(ty)
  end
  
  local SDFRate = SDF{1,1}
  local storeFunction = rigel.newFunction{name="store", inputType=portType,  outputType=types.null(), sdfInput=SDFRate, sdfOutput=SDFRate, stateful=true, sdfExact=true, delay=0}
  local loadFunction = rigel.newFunction{name="load", inputType=types.null(), outputType=portType, sdfInput=SDFRate, sdfOutput=SDFRate, stateful=true, sdfExact=true, delay=0}

  local name = J.verilogSanitize("TriggerFIFO_"..tostring(ty))
  local res = rigel.newModule{ name=name, functions={store=storeFunction, load=loadFunction}, stateful=true }
  res.kind="fifo"

  if terralib~=nil then res.terraModule = MT.triggerFIFO( res, ty ) end
  
  function res.makeSystolic()
    local C = require "generators.examplescommon"
    local s = C.automaticSystolicStub(res)

    local vstr = res:vHeader()..[=[
  reg [31:0] cnt;
  always @(posedge CLK) begin
    if (reset==1'b1) begin
      cnt <= 32'd0;
    end else if (store_ready==1'b1 && store_input==1'b1 && load_ready_downstream==1'b1) begin
      // do nothing! load&store in same cycle
    end else if (store_ready==1'b1 && store_input==1'b1) begin
      cnt <= cnt+32'd1;
    end else if ( load_ready_downstream==1'b1 && cnt>32'd0) begin
      cnt <= cnt-32'd1;
    end
  end
  assign store_ready = cnt<32'd4294967295;
  assign load_output = (cnt>32'd0) || (store_ready==1'b1 && store_input==1'b1);
endmodule
]=]
    s:verilog(vstr)
    return s
  end
  
  return res
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
  res.name = J.sanitize("LUT_"..tostring(inputType).."_"..(tostring(outputType)).."_"..(tostring(values)) )

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    -- bram can only read byte aligned?
    local inputBytes = math.ceil(inputType:verilogBits()/8)
    
    local lut = systolicModule:add( fpgamodules.bramSDP( true, inputCount*(outputType:verilogBits()/8), inputBytes, outputType:verilogBits()/8, values, true ):instantiate("LUT") )

    --systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {},S.parameter("reset",types.bool())) )
    
    local sinp = S.parameter("process_input", inputType )

    local pipelines = {}

    -- needs to be driven, but set valid==false
    table.insert(pipelines, lut:writeAndReturnOriginal( S.tuple{sinp,S.constant(0,types.bits(inputBytes*8))},S.constant(false,types.bool())) )

    systolicModule:addFunction( S.lambda("process",sinp, S.cast(lut:read(sinp),outputType), "process_output", pipelines, nil, S.CE("process_CE") ) )

    return systolicModule
  end

  res = rigel.newFunction(res)

  if terralib~=nil then res.terraModule = MT.lut( res, inputType, outputType, values, inputCount ) end

  return res
end)

modules.reduce = memoize(function( f, W, H, X )
  if rigel.isPlainFunction(f)==false then error("Argument to reduce must be a plain rigel function, but is: "..tostring(f)) end

  err( f.inputType:isrv(), "reduce: input function should be rv parallel")
  err( f.inputType:deInterface():isData(), "reduce: input function should be rv parallel")
  err( f.outputType:isrv(), "reduce: input function should be rv parallel")
  err( f.outputType:deInterface():isData(), "reduce: input function should be rv parallel")

  if f.inputType:deInterface():isTuple()==false or f.inputType:deInterface()~=types.tuple({f.outputType:deInterface(),f.outputType:deInterface()}) then
    error("Reduction function f must be of type {A,A}->A, but is type "..tostring(f.inputType).."->"..tostring(f.outputType))
  end


  err(type(W)=="number", "reduce W must be number")
  err(type(H)=="number", "reduce H must be number")
  local ty=f.outputType:deInterface()

  err( X==nil,"reduce: too many arguments")

  local res
  if (W*H)==2 then
    local G = require "generators.core"
    local C = require "generators.examplescommon"
    return C.compose("ReduceArrayToTupleWrapper_"..f.name.."_W"..tostring(W).."_H"..tostring(H),f,G.ArrayToTuple,nil,types.rv( types.Par( types.array2d( ty, W, H ) ) ),SDF{1,1})
  elseif (W*H)%2==0 then
    -- codesize reduction optimization
    local C = require "generators.examplescommon"

    local I = rigel.input( types.rv( types.Par( types.array2d( ty, W, H ) ) ) )
    local ic = rigel.apply( "cc", C.cast( types.array2d( ty, W, H ), types.array2d( ty, W*H ) ), I)

    local ica = rigel.apply("ica", C.slice(types.array2d( ty, W*H ),0,(W*H)/2-1,0,0), ic)
    local a = rigel.apply("a", modules.reduce(f,(W*H)/2,1), ica)

    local icb = rigel.apply("icb", C.slice(types.array2d( ty, W*H ),(W*H)/2,(W*H)-1,0,0), ic)
    local b = rigel.apply("b", modules.reduce(f,(W*H)/2,1), icb)

    local fin = rigel.concat("conc", {a,b})
    local out = rigel.apply("out", f, fin)
    res = modules.lambda("reduce_"..f.name.."_W"..tostring(W).."_H"..tostring(H), I, out)
  else
    res = {kind="reduce", fn = f, W=W, H=H}

    res.inputType = types.rv(types.Par(types.array2d( ty, W, H )))
    res.outputType = types.rv(types.Par(ty))
    res.stateful = f.stateful
    if f.stateful then print("WARNING: reducing with a stateful function - are you sure this is what you want to do?") end
    
    res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,1}
    res.delay = math.ceil(math.log(W*H)/math.log(2))*f.delay
    res.name = sanitize("reduce_"..f.name.."_W"..tostring(W).."_H"..tostring(H))
    
    function res.makeSystolic()
      local systolicModule = Ssugar.moduleConstructor(res.name)
      
      --local resetPipelines = {}
      local sinp = S.parameter("process_input", res.inputType:deInterface() )
      local t = J.map( J.range2d(0,W-1,0,H-1), function(i) return S.index(sinp,i[1],i[2]) end )
      
      local i=0
      local expr = J.foldt(t, function(a,b) 
                             local I = systolicModule:add(f.systolicModule:instantiate("inner"..i))
                             i = i + 1
                             return I:process(S.tuple{a,b}) end, nil )

      local CE

      if f.delay>0 or f.stateful then
        CE = S.CE("process_CE")
      end
      
      systolicModule:addFunction( S.lambda( "process", sinp, expr, "process_output", nil, nil, CE ) )
      
      return systolicModule
    end

    res = rigel.newFunction( res )
  end

  if terralib~=nil then res.terraModule = MT.reduce(res,f,W,H) end

  return res
end)


-- takes T{Wv,Vh}->T
modules.reduceSeq = memoize(function( f, Vw, Vh, framed, X )
  err(type(Vw)=="number","reduceSeq: Vw should be number")
  --err(T<=1, "reduceSeq: T>1, T="..tostring(T))
  err(Vw>=1,"reduceSeq: Vw should be >=1, but is: "..tostring(Vw))
  if Vh==nil then Vh=1 end
  err(type(Vh)=="number","reduceSeq: Vh should be number")
  err(Vh>=1,"reduceSeq: Vh should be >=1")
  
  if framed==nil then framed=false end
  err( type(framed)=="boolean","reduceSeq: framed must be boolean" )
  assert(X==nil)

  err( rigel.isPlainFunction(f), "reduceSeq: input should be plain rigel function" )
  
  assert( f.inputType:isrv())
  assert( f.inputType:deInterface():isData() )
  assert( f.outputType:isrv())
  assert( f.outputType:deInterface():isData() )
  
  if f.inputType:deSchedule():isTuple()==false or f.inputType:deSchedule()~=types.tuple({f.outputType:deSchedule(),f.outputType:deSchedule()}) then
    error("Reduction function f must be of type {A,A}->A, but is type "..tostring(f.inputType).."->"..tostring(f.outputType))
  end

  local res = {kind="reduceSeq", fn=f, Vw=Vw, Vh=Vh}

  res.inputType = types.rv(f.outputType:deSchedule())
  if framed then
    res.inputType = types.rv(types.Seq( types.Par(f.outputType:deSchedule()), Vw, Vh ))
  end

  res.outputType = types.rvV(types.Par(f.outputType:deSchedule()))
  res.sdfInput, res.sdfOutput = SDF{1,1},SDF{1,Vw*Vh}
  res.stateful = true
  err( f.delay==0, "reduceSeq, function must be asynchronous (0 cycle delay)")
  res.delay = 0
  res.name = J.sanitize("ReduceSeq_"..f.name.."_Vw"..tostring(Vw).."_Vh"..tostring(Vh))

  if terralib~=nil then res.terraModule = MT.reduceSeq(res,f,Vw,Vh) end

  function res.makeSystolic()
    local del = f.systolicModule:getDelay("process")
    err( del == 0, "ReduceSeq function must have delay==0 but instead has delay of "..del )

    local systolicModule = Ssugar.moduleConstructor(res.name)

    local printInst
    if DARKROOM_VERBOSE then printInst = systolicModule:add( S.module.print( types.tuple{types.uint(16),f.outputType,f.outputType}, "ReduceSeq "..f.systolicModule.name.." phase %d input %d output %d", true):instantiate("printInst") ) end

    local sinp = S.parameter("process_input", f.outputType:deSchedule() )
    local svalid = S.parameter("process_valid", types.bool() )

    local phase = systolicModule:add( Ssugar.regByConstructor( types.uint(16), fpgamodules.sumwrap(types.uint(16), (Vw*Vh)-1 ) ):CE(true):setReset(0):instantiate("phase") )
    
    local pipelines = {}
    table.insert(pipelines, phase:setBy( S.constant(1,types.uint(16)) ) )
    
    local out
    
    if Vw*Vh==1 then
      -- hack: Our reduce fn always adds two numbers. If we only have 1 number, it won't work! just return the input.
      out = sinp
    else
      local sResult = systolicModule:add( Ssugar.regByConstructor( f.outputType:deSchedule(), f.systolicModule ):CE(true):hasSet(true):instantiate("result") )
      table.insert( pipelines, sResult:set( sinp, S.eq(phase:get(), S.constant(0, types.uint(16) ) ):disablePipelining() ) )
      out = sResult:setBy( sinp, S.__not(S.eq(phase:get(), S.constant(0, types.uint(16) ) )):disablePipelining() )
    end
    
    if DARKROOM_VERBOSE then table.insert(pipelines, printInst:process( S.tuple{phase:get(),sinp,out} ) ) end
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", sinp, S.tuple{ out, S.eq(phase:get(), S.constant( (Vw*Vh)-1, types.uint(16))) }, "process_output", pipelines, svalid, CE) )
    
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {phase:reset()}, S.parameter("reset",types.bool())) )
    
    return systolicModule
  end

  return rigel.newFunction( res )
end)

-- takes rv(T[Vw,Vh;W,H})->rvV(T)
modules.reduceParSeq = memoize(function( f, Vw, Vh, W, H, X )
  assert(W%Vw==0)
  assert(H%Vh==0)
  local res = modules.compose("ReduceParSeq_f"..f.name.."_Vw"..tostring(Vw).."_Vh"..tostring(Vh).."_W"..tostring(W).."_H"..tostring(H),modules.reduceSeq(f,W/Vw,H/Vh,true),modules.flatmap(modules.reduce(f,Vw,Vh),Vw,Vh,W,H,0,0,W/Vw,H/Vh))

  return res
end)
  
-- surpresses output if we get more then _count_ inputs
modules.overflow = memoize(function( A, count )
  rigel.expectBasic(A)

  err( count<2^32-1, "overflow: outputCount must not overflow")
  
  -- SDF rates are not actually correct, b/c this module doesn't fit into the SDF model.
  -- But in theory you should only put this at the very end of your pipe, so whatever...
  local res = {kind="overflow", A=A, inputType=types.rv(types.Par(A)), outputType=types.rvV(types.Par(A)), stateful=true, count=count, sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, delay=0}
  if terralib~=nil then res.terraModule = MT.overflow(res,A,count) end
  res.name = J.sanitize("Overflow_"..count.."_"..tostring(A))

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
    fns.process.isPure = function() return false end
    
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
local function lambdaSDFNormalize( input, output, name, X )
  assert( X==nil, "lambdaSDFNormalize: too many arguments")
  assert( type(name)=="string")
  

  if input~=nil and input.sdfRate~=nil then
    err( SDFRate.isSDFRate(input.sdfRate),"SDF input rate is not a valid SDF rate")

    for k,v in pairs(input.sdfRate) do
      err(v=="x" or v[1]/v[2]<=1, "error, lambda declared with input BW > 1")
    end
  end

  local extreme = output:sdfExtremeRate(true,true)
  local sdfMaxRate, maxNode = extreme[1], extreme[2]
  
  if Uniform(sdfMaxRate[1]):eq(0):assertAlwaysTrue() then
    output:visitEach(function(n) print(n) end)
    J.err( false,"Error: max utilization of pipeline is 0! Something weird must have happened. Function:",name," due to node: ", maxNode)
  end

  local scaleFactor = SDFRate.fracInvert(sdfMaxRate)
  
  --if DARKROOM_VERBOSE then print("NORMALIZE, sdfMaxRate", SDFRate.fracToNumber(sdfMaxRate),"outputBW", SDFRate.fracToNumber(outputBW), "scaleFactor", SDFRate.fracToNumber(scaleFactor)) end

  local newInput
  local newOutput = output:process(
    function(n,orig)
      if n.kind=="input" then
        err( n.id==input.id, "lambdaSDFNormalize: unexpected input node. input node is not the declared module input." )
        local orig = n.rate

        n.rate = SDF(SDFRate.multiply(n.rate,scaleFactor[1],scaleFactor[2]))
        assert( SDFRate.isSDFRate(n.rate))

        if n.rate:allLE1()==false then
          -- this is kind of a hack? not all input rates will affect a module, so make sure we never
          -- end up with an input rate >1

          local tr = n.rate:largest()

          n.rate = SDF(SDFRate.multiply(n.rate,tr[1][2],tr[1][1]))
          assert( SDFRate.isSDFRate(n.rate))

          --output:visitEach(function(n) print(n) end)
          --J.err( n.rate:allLE1(), "Error? somehow lambda SDF normalize resulted in a function input with rate>1? rate:",n.rate," originalRate:",orig," maxRate:",sdfMaxRate[1],"/",sdfMaxRate[2])
        end

        if orig:le(n.rate)==false then
          print("Warning: Module rate ended up being less than what the user requested. Function ",name," requested:",orig," but solved rate was:", n.rate)
        end
        
        newInput = rigel.newIR(n)
        return newInput
      elseif n.kind=="apply" and #n.inputs==0 then
        -- for nullary modules, we sometimes provide an explicit SDF rate, to get around the fact that we don't solve for SDF rates bidirectionally
        n.rate = SDF(SDFRate.multiply(n.rate, scaleFactor[1], scaleFactor[2] ))
        return rigel.newIR(n)
      elseif n.kind=="applyMethod" then
        n.rate = SDF(SDFRate.multiply(n.rate, scaleFactor[1], scaleFactor[2] ))
        return rigel.newIR(n)
      else
        return rigel.newIR(n)
      end
    end)

  if (input~=nil)~=(newInput~=nil) then
    print("lambdaSDFNormalize warning: declared input was not actually used anywhere in function '"..name.."'?" )
  end
  
  return newInput, newOutput
end

-- check to make sure we have FIFOs in diamonds
-- we check for fifos whenever we have fan in. One one exception is:
--    if all branches into the fan in trace directly to an input (not through a fan out), we consider it ok.
--    ie: that is basically a fan-in module itself, which we will check for later.
local function checkFIFOs( output, moduleName, X )
  assert( X==nil )
  assert( type(moduleName)=="string" )
  
  -- does this node's inputs trace directly to an input node, NOT through a fan-out? (ie only through nodes with 1 in, 1 out)
  local traceToInput
  traceToInput = J.memoize(function(n)
      local res
      if n.kind=="concat" then
        res = true
        for _,i in ipairs(n.inputs) do
          if traceToInput(i)==false then res=false end
        end
      elseif #n.inputs==0 then
        res = true -- this is an input or nullary module
      elseif n.kind=="apply" and n.fn.fifoStraightThrough==true and n.fn.inputType:streamCount()==n.fn.outputType:streamCount() then
        res = traceToInput(n.inputs[1])
      elseif #n.inputs>1 or types.streamCount(n.type)>1 then
        res = false
      else
        assert(#n.inputs==1 and types.streamCount(n.type)==1 )
        res = traceToInput(n.inputs[1])
      end

      return res
  end)
  
  return output:visitEach(
    function(n, arg)
      local res = {}
      if n.kind=="input" then
        res = J.broadcast(false,types.streamCount(n.type))
      elseif n.kind=="apply" or (n.kind=="applyMethod" and rigel.isPlainFunction(n.inst.module)) then
        local fn = n.fn
        if n.kind=="applyMethod" and rigel.isPlainFunction(n.inst.module) then fn = n.inst.module end

        if #n.inputs==0 then
          assert(false)
        elseif fn.inputType:streamCount()<=1 and fn.outputType:streamCount()<=1 then
          if fn.outputType:streamCount()==0 then
            res = {}
          else
            res = {fn.fifoed or arg[1][1]}
          end
        elseif fn.inputType:streamCount()==1 and fn.outputType:streamCount()>1 then
          -- always consider these to be fan outs
          res = J.broadcast( false, n.type.size[1]*n.type.size[2] ) -- clear fifo flag on fan-out
        elseif fn.inputType:streamCount()>1 and fn.outputType:streamCount()==1 then
          -- always consider these to be fan ins
          assert(#arg==1)
          assert(#arg[1]==types.streamCount(fn.inputType) )

          local allStreamsTraceToInput = traceToInput(n.inputs[1])
          local allFIFOed = true
          
          for i=1,types.streamCount(fn.inputType) do
            J.err( fn.disableFIFOCheck==true or arg[1][i] or allStreamsTraceToInput, "CheckFIFOs: branch in a diamond is missing FIFO! (input stream idx ",i-1,". ",types.streamCount(fn.inputType)," input streams, to fn:",fn.name,") inside function: ",moduleName," ", n.loc)
            allFIFOed = allFIFOed and arg[1][i]
          end

          -- Is this right???? if we got this far, we did have a fifo along this brach...
          res = J.broadcast(allFIFOed,types.streamCount(n.type))
        elseif fn.inputType:streamCount()==fn.outputType:streamCount() and fn.fifoStraightThrough then
          -- sort of a hack: we marked this function to indicate that streams pass straight through, so we can just propagate signals
          res = arg[1]
        else
          J.err(false, "unknown fn fifo behavior? ",fn.name," type:",fn.inputType,"->",fn.outputType," inputCount:",#n.inputs," inputStreamCount:",fn.inputType:streamCount()," outputStreamCount:",fn.outputType:streamCount() )
        end
      elseif n.kind=="applyMethod" then
        assert(rigel.isModule(n.inst.module))
        
        if n.fnname=="load" and n.inst.module.kind=="fifo" then
          res = {true}
        else
          res = J.broadcast(false, types.streamCount(n.inst.module.functions[n.fnname].outputType) )
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
      elseif n.kind=="constant" then
        assert(false) -- should not appear in RV graphs
        --res = {}
      else
        print("NYI ",n.kind)
        assert(false)
      end

      J.err( type(res)=="table", "checkFIFOs bad res ",n )
      J.err( #res == types.streamCount(n.type), "checkFIFOs error (res:",#res,",streamcount:",types.streamCount(n.type),",type:",n.type,")- ",n )
      return res
    end)
end

-- this will go through the module/instances, and collect list of provided/required ports that are not tied down
local function collectProvidesRequires( moduleName, output, instanceMap )
  -- instance->fnlist
  local provides = {}
  local requires = {}

  local function addDependencies(mod)
    for inst,fnmap in pairs(mod.requires) do
      if requires[inst]==nil then requires[inst] = {} end
      for fnname,_ in pairs(fnmap) do
        local fn = inst.module.functions[fnname]
        J.err( requires[inst][fnname]==nil or fn.inputType==types.Interface(), "Multiple modules require the same function? "..inst.name..":"..fnname)
        requires[inst][fnname] = 1
      end
    end

    for inst,fnmap in pairs(mod.provides) do
      if provides[inst]==nil then provides[inst] = {} end
      for fnname,_ in pairs(fnmap) do
        J.err( requires[inst][fnname]==nil, "Multiple modules provide the same function? "..inst.name..":"..fnname)
        provides[inst][fnname] = 1
      end
    end
  end

  for inst,_ in pairs(instanceMap) do
    addDependencies(inst.module)
    
     if rigel.isModule(inst.module) then
      -- all fns in this module should be added to provides list
      for fnname,fn in pairs(inst.module.functions) do
        J.deepsetweak(provides,{inst,fnname},1)
      end
    end
  end

  -- collect other instances refered to by the fn code
  output:visitEach(
    function(n)
      if n.kind=="applyMethod" then
        -- *** just because we called one fn on an inst, doesn't mean we need to include the whole thing
        if requires[n.inst]==nil then requires[n.inst]={} end
        J.err( requires[n.inst][n.fnname]==nil, "Multiple modules require the same function? "..n.inst.name..":"..n.fnname)
        requires[n.inst][n.fnname] = 1
      elseif n.kind=="apply" then
        addDependencies(n.fn)
      end
    end)

  return provides, requires
end

local function checkInstTables( moduleName, output, instanceMap, provides, requires, userInstanceMap)
  -- purely checking
  for inst,_ in pairs(instanceMap) do
    for rinst,rfnmap in pairs(inst.module.requires) do
      for rfn,_ in pairs(rfnmap) do
        err( instanceMap[rinst]~=nil or (requires[rinst]~=nil and requires[rinst][rfn]~=nil), "Instance '"..inst.name.."' requires "..rinst.name..":"..rfn.."(), but this is not in requires list or internal instance list?" )
        --err( (externalInstances[ic.instance]~=nil and externalInstances[ic.instance][ic.functionName]~=nil) or instanceMap[ic.instance]~=nil,"Instance '"..inst.name.."' requires "..ic.instance.name..":"..ic.functionName..", but this is not in external or internal instances list?" )
        --local fn = ic.instance.module.functions[ic.functionName]
        --if types.isHandshakeAny(fn.inputType) or types.isHandshakeAny(fn.outputType) then
         -- err( (externalInstances[ic.instance]~=nil and externalInstances[ic.instance][ic.functionName.."_ready"]~=nil) or (instanceMap[ic.instance]~=nil),"Instance '"..inst.name.."' requires "..ic.instance.name..":"..ic.functionName.."_ready(), but this is not in external or internal instances list?" )
        --end
      end
    end
  end

  -- checking
  for inst,_ in pairs(userInstanceMap) do
    if requires[inst]~=nil then
      err( false, "The instance '"..inst.name.."' of module '"..inst.module.name.."' that the user explicitly included in module '"..moduleName.."' somehow ended up getting set as external? fnlist: "..table.concat(J.invertAndStripKeys(requires[inst]),",") )
    end
  end

  for einst,_ in pairs(requires) do
    err( instanceMap[einst]==nil, "External instance '"..einst.name.."' is somehow also in instance list?")
  end

  for inst,_ in pairs(instanceMap) do
    err( requires[inst]==nil, "Instance '"..inst.name.."' is somehow also in external instance list?")
  end

  local usedInstances = {}
  output:visitEach(
    function(n)
      if n.kind=="applyMethod" then
        usedInstances[n.inst] = 1
      elseif n.kind=="apply" then
      end
    end)

  -- it's OK for the instance to not be used if user explicitly placed it there...
  for inst,_ in pairs(instanceMap) do
    err( usedInstances[inst]~=nil or userInstanceMap[inst]~=nil, "Instance '"..inst.name.."' was not used? inside module '"..moduleName.."'")
  end

  for inst,_ in pairs(usedInstances) do
    err( instanceMap[inst]~=nil or requires[inst]~=nil, "Instance '"..inst.name.."' was used in function '"..moduleName.."', but is not in instance map or requires map?")
  end

end

local function collectInstances( moduleName, output, userInstanceMap )
  assert( type(userInstanceMap)=="table" )
  -- add instances to instance list that are fully resolved
  -- (ie, all their dependencies and provided functions are fully tied down)

  -- collect set of all provides/requires in the module (some may be tied down!)
  local provides, requires = collectProvidesRequires( moduleName, output, userInstanceMap )

  -- delete matched provides/requires connections, and add fully wired modules to instance map    
  local finalRequires = {}
  local finalProvides = {}
  
  -- clear matching connections
  -- NOTE: even if we delete everything out of FN list, we keep an empty FN list around!
  --       this is how we detect tied down instances
  for instance,fnmap in pairs(requires) do
    if finalRequires[instance]==nil then finalRequires[instance]={} end
    for fn,_ in pairs(fnmap) do  -- add anything not tied down
      if provides[instance]==nil or provides[instance][fn]==nil then finalRequires[instance][fn]=1 end
    end
  end

  for instance,fnmap in pairs(provides) do
    if finalProvides[instance]==nil then finalProvides[instance]={} end
    for fn,_ in pairs(fnmap) do
      if requires[instance]==nil or requires[instance][fn]==nil then finalProvides[instance][fn]=1 end
    end
  end

  -- anything in final requires/provides that has no fns in list is tied down
  local finalFinalRequires = {}
  local finalFinalProvides = {}
  local instanceMap = {}
  for inst,_ in pairs(userInstanceMap) do instanceMap[inst]=1 end
  
  for inst,fnmap in pairs(finalRequires) do
    -- anything explicitly added has all requirements satisfied...
    if (J.keycount(fnmap)==0 and J.keycount(finalProvides[inst])==0) or userInstanceMap[inst]~=nil then
      -- tied down. add to Instance Map
      instanceMap[inst] = 1
    else
      for fn,_ in pairs(fnmap) do
        J.deepsetweak(finalFinalRequires,{inst,fn},1)
      end
    end
  end

  for inst,fnmap in pairs(finalProvides) do
    if J.keycount(fnmap)==0 and J.keycount(finalRequires[inst])==0 then
      -- tied down. add to Instance Map
      instanceMap[inst] = 1
    else
      for fn,_ in pairs(fnmap) do
        J.deepsetweak(finalFinalProvides,{inst,fn},1)
      end
    end
  end

  checkInstTables( moduleName, output, instanceMap, finalFinalProvides, finalFinalRequires, userInstanceMap )
  
  return instanceMap, finalFinalProvides, finalFinalRequires
end

function modules.lambdaTab(tab)
  return modules.lambda(tab.name,tab.input,tab.output,tab.instanceList, tab.generatorStr, tab.generatorParams, tab.globalMetadata)
end

local function FIFOSizeToDelay( fifoSize )
  if fifoSize==0 then
    return 0
  elseif fifoSize<=128 then
    -- takes one cycle to store, 0 to load
    return 1
  else
    -- takes one cycle to store, 1 cycle to load
    return 2
  end
end

local function insertFIFOs( out, delayTable, moduleName, X )
  assert( type(moduleName)=="string")
  assert( X==nil )

  local C = require "generators.examplescommon"

  local verbose = false

  if verbose then
    print("* InsertFIFOs",moduleName)
  end
  
  local depth = {}
  local maxDepth=0
  out:visitEach(
    function( n, args )
      local d = 0

      if #n.inputs>0 then
        d = math.max(unpack(args))+1
      end

      depth[n] = d
      if d>maxDepth then maxDepth=d end
      return d
    end)

  local fifoBits = 0

  local fr = out:process(
    function( n, orig )
      n = rigel.newIR(n)
      local res = n

      local extraDelayForFIFOs = 0

      -- first, insert delays
      if #n.inputs>0 then
        err( type(delayTable[orig.inputs[1]])=="number", "missing delay for: ", orig.inputs[1], "IS:"..tostring(delayTable[orig.inputs[1]]) )
        assert( type(delayTable[orig])=="number" )

        local iDelayThis = delayTable[orig]

        if n.kind=="apply" or n.kind=="applyMethod" then
          local fn = n.fn
          if n.kind=="applyMethod" then
            if rigel.isPlainFunction(n.inst.module) then
              fn = n.inst.module
            else
              fn = n.inst.module.functions[n.fnname]
            end
          end
          assert( rigel.isPlainFunction(fn) )

          extraDelayForFIFOs = FIFOSizeToDelay( fn.inputBurstiness ) + FIFOSizeToDelay( fn.outputBurstiness )
          iDelayThis = iDelayThis - fn.delay - extraDelayForFIFOs
        end
        
        assert( iDelayThis >= delayTable[orig.inputs[1]])

        local ntmp = n:shallowcopy()

        local INPUTCNT = #n.inputs
        -- for statements, we don't care about other inputs than input 0: other inputs can have different delays (they are just passed through)
        if n.kind=="statements" then INPUTCNT = 1 end
        for i=1,INPUTCNT do
          if iDelayThis ~= delayTable[orig.inputs[i]] then
            local d = iDelayThis-delayTable[orig.inputs[i]]

            J.err( d>0, "delay at input of this node is less than its input? thisDelay:",iDelayThis," delay of input "..(i-1)..":", delayTable[orig.inputs[i]], "\n",n )
            if verbose then
              print("** DFIFO",moduleName,d,n.name,n.inputs[i].name)
              print("input streamcount:",n.inputs[i].type:streamCount())
            end

            if n.inputs[i].type:streamCount()==1 then
              ntmp.inputs[i] = C.fifo( n.inputs[i].type:deInterface(), d, nil, nil, nil, nil, "DELAY_"..moduleName.."_"..n.name )(n.inputs[i])
            elseif n.inputs[i].type:streamCount()>0 then
              local stout = {}

              J.err( n.inputs[i].type:streamCount()>0, "input has no streams?",n,"INPUT"..i,n.inputs[i] )
              
              for st=1,n.inputs[i].type:streamCount() do
                local ity
                if n.inputs[i].type:isArray() then
                  ity = n.inputs[i].type:arrayOver()
                elseif n.inputs[i].type:isTuple() then
                  ity = n.inputs[i].type.list[st]
                else
                  assert(false)
                end
                stout[st] = C.fifo( ity:deInterface(), d, nil, nil, nil, nil, "DELAY_"..moduleName.."_"..n.name )(n.inputs[i][st-1])
              end
              ntmp.inputs[i] = rigel.concat(stout)
              J.err( n.inputs[i].type == ntmp.inputs[i].type, "BADTYPE",n.inputs[i].type," ",ntmp.inputs[i].type, n.inputs[i].type:streamCount() )
            end

          end
        end
        local oldn = n
        n = rigel.newIR(ntmp)
        res = n
--        print(n)
--        print("DELAYDONE",oldn,n)
      end
      
      if n.kind=="apply" and n.type:isRV() and n.type.VRmode~=true and n.inputs[1].type:isRV() and n.inputs[1].type.VRmode~=true then
        assert( #orig.inputs==1 )

        res = n.inputs[1]


        --err( delayTable[orig.inputs[1]] == iDelayThis, "NYI - input to fn requires delay buffer! inputDelay:",delayTable[orig.inputs[1]]," delayAtInputOfThisFn::",iDelayThis," bits:",n.inputs[1].type:extractData():verilogBits()," del ",delayTable[orig]," fn ",orig.fn.delay,orig, orig.fn )
        local NAME = moduleName.."_"..depth[orig].."_"..maxDepth.."_"..n.name.."_"..n.fn.name

        --err( n.fn.inputBurstiness<=16384, "inputBurstiness for module ",n.fn.name," is way too large: ",n.fn.inputBurstiness )
        --err( n.fn.outputBurstiness<=16384, "outputBurstiness for module ",n.fn.name," is way too large: ",n.fn.outputBurstiness )

        local ibts = (n.fn.inputBurstiness*n.fn.inputType:extractData():verilogBits())
        local obts = (n.fn.outputBurstiness*n.fn.outputType:extractData():verilogBits())

        --err( ibts<20*1024*8, "Input burst FIFO is tooo big! ",ibts/8192,"KB" )
        --err( obts<20*1024*8, "Output burst FIFO is tooo big! ",obts/8192,"KB" )
        
        local IFIFO, OFIFO
        if rigel.MONITOR_FIFOS==false then
          if n.fn.inputBurstiness>0 then
            local items = n.fn.inputBurstiness + FIFOSizeToDelay( n.fn.inputBurstiness )
            if items>16384/4 then
              print("warning: FIFO allocation is too big! Truncating! INPUT SIDE")
              print(n.fn)
              for i=1,30 do print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!") end
              items = 16384/4
            end
            
            IFIFO = C.fifo( n.inputs[1].type:deInterface(), items, nil, nil, nil,nil,  NAME.."IFIFO" )
          end
          if n.fn.outputBurstiness>0 then
            local items = n.fn.outputBurstiness + FIFOSizeToDelay( n.fn.outputBurstiness )
            if items>16384/4 then
              print("warning: FIFO allocation is too big! Truncating! OUTPUT SIDE")
              print(n.fn)
              for i=1,30 do print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!") end
              items = 16384/4
            end

            OFIFO = C.fifo( n.type:deInterface(), items, nil, nil, nil, nil,  NAME.."_OFIFO" )
          end
        else
          IFIFO = C.fifoWithMonitor( n.inputs[1].type:deInterface(), n.fn.inputBurstiness + FIFOSizeToDelay( n.fn.inputBurstiness ), delayTable[orig] - n.fn.delay - extraDelayForFIFOs, n.fn.delay, n.inputs[1].rate, true, NAME, n.fn.name, moduleName )
          OFIFO = C.fifoWithMonitor( n.type:deInterface(), n.fn.outputBurstiness + FIFOSizeToDelay( n.fn.outputBurstiness ), delayTable[orig], n.fn.delay, n.rate, false, NAME, n.fn.name, moduleName )
        end

        if IFIFO~=nil then
          local bts = (n.fn.inputBurstiness*n.fn.inputType:extractData():verilogBits())
          if verbose then print("IFIFO",moduleName, n.fn.inputBurstiness, n.fn.inputType:extractData():verilogBits(), (bts/8192).."KB", "delay"..n.fn.delay,  n.fn.name) end
          fifoBits = fifoBits + bts
          res = rigel.apply( J.sanitize(n.name.."_IFIFO"), IFIFO, res )

--          local G = require "generators.core"
--          if bts>0 then
--            res = G.Print{"IF",rigel.Unoptimized}(res)
--          end
        end
        res = rigel.apply( n.name, n.fn, res )
        if OFIFO~=nil then
          local bts = (n.fn.outputBurstiness*n.fn.outputType:extractData():verilogBits())
          if verbose then print("OFIFO",moduleName,n.fn.outputBurstiness, n.fn.outputType:extractData():verilogBits(), (bts/8192).."KB", "delay"..n.fn.delay, n.fn.name) end
          fifoBits = fifoBits + bts
          res = rigel.apply( J.sanitize(n.name.."_OFIFO"), OFIFO, res )
        end
--      elseif n.kind=="apply" and n.inputs[1].type:streamCount()>1 then
        -- this is stuff like fan ins:
--        assert( n.fn.inputBurstiness==0)
--        assert( n.fn.outputBurstiness==0)
--        assert( n.inputs[1].type:streamCount()==#
                
      elseif n.kind=="apply" or n.kind=="applyMethod" then
        -- can't applys of modules
        -- this is things like VR mode, tuples of handshakes, etc
        -- hopefully we can just ignore this...
        
        local fn = n.fn
        if n.kind=="applyMethod" then
          if rigel.isPlainFunction(n.inst.module) then
            fn = n.inst.module
          else
            fn = n.inst.module.functions[n.fnname]
          end
        end
        assert( rigel.isPlainFunction(fn) )

        err( fn.inputBurstiness==0 )
        err( fn.outputBurstiness==0 )

        if #orig.inputs==1 then
--          err( delayTable[orig.inputs[1]]==delayTable[orig]-fn.delay, "NYI - auto fifo unsupported call type, and the delays don't match! inputDelay:",delayTable[orig.inputs[1]]," thisdelay:",delayTable[orig],"thisFnDelay:",fn.delay,"inputburst:",fn.inputBurstiness,"outburst:",fn.outputBurstiness,"this:",orig , orig.loc )
        else
          err( #orig.inputs==0, "apply with multiple inputs? ",#orig.inputs, orig )
        end
        
--[=[      elseif n.kind~="statements" then
        -- all other nodes (like concats)
        
        for k,inp in pairs(orig.inputs) do
          assert( type(delayTable[inp])=="number" )
          assert( type(delayTable[orig])=="number" )
          assert( delayTable[inp]<=delayTable[orig] )

          local delayDiff = delayTable[orig] - delayTable[inp]
          if delayDiff>0 then
            -- insert shift register
            assert( orig.kind~="apply" and orig.kind~="applyMethod" )
            
            err( inp.type:isRV(),"input to shift register is not RV? is: ",inp.type," this:", orig )

            local G = require "generators.core"
            if verbose then print("DFIFO_statements",moduleName,delayDiff,n) end
            --res.inputs[k] = modules.makeHandshake(modules.shiftRegister( inp.type:deInterface(), delayDiff ))(res.inputs[k])
            res.inputs[k] = C.fifo( inp.type:deInterface(), delayDiff, nil, nil, nil, nil, "DELAY" )(res.inputs[k])
          end
  end]=]
      end

      return res
    end)

  return fr
end

local function calculateDelaysZ3( output, moduleName )
  assert( type(moduleName)=="string" )
  
  local statements = {}
  local ofTerms = {}

  local verbose = false

  if verbose then
    print("* DelaysZ3 ",moduleName )
  end
  
  local seenNames = {}
  local resdelay = output:visitEach(
    function(n, inputs)
      local res

      local name = J.verilogSanitizeInner(n.name)
      seenNames[name] = n
      table.insert( statements, "(declare-const "..name.." Int)" )
      
      if n.kind=="input" or n.kind=="constant" then
        table.insert( statements, "(assert (= "..name.." 0))" )
        res = name
      elseif n.kind=="concat" or n.kind=="concatArray2d" then
        -- todo fix: it looks like all streams in a concat get the same delay? is that good enough behavior?
        for k,i in ipairs(inputs) do
          table.insert( statements, "(assert (>= "..name.." "..i.."))" )
          table.insert( ofTerms, "(* (- "..name.." "..i..") "..(n.inputs[k].type:extractData():verilogBits())..")" )
        end
        res = name
      elseif n.kind=="apply" or (n.kind=="applyMethod" and rigel.isPlainFunction(n.inst.module)) then

        local fn = n.fn
        if n.kind=="applyMethod" and rigel.isPlainFunction(n.inst.module) then
          fn = n.inst.module
        end

        -- if we have burstiness, we need to add a fifo, which will introduce extra delay!
        local extra = 0
        if fn.inputType:isRV() then extra = extra + FIFOSizeToDelay(fn.inputBurstiness) end
        if fn.outputType:isRV() then extra = extra + FIFOSizeToDelay(fn.outputBurstiness) end
        
        if fn.inputType==types.Interface() or (fn.inputType:isrv() and fn.inputType:extractData():verilogBits()==0) then
          --res = fn.delay+extra
          table.insert( statements, "(assert (= "..name.." "..(fn.delay+extra).."))" )
          res = name
        else
          err(fn.delay~=nil,"Error: fn "..fn.name.." is missing delay? "..tostring(fn.inputType).." "..tostring(fn.outputType))
          --res = inputs[1] + fn.delay + extra
          --assert(false)
          table.insert( statements, "(assert (>= "..name.." (+ "..inputs[1].." "..(fn.delay+extra)..")))" )
          local bts = n.inputs[1].type:extractData():verilogBits()
          if bts>0 then table.insert( ofTerms, "(* (- "..name.." "..inputs[1]..") "..bts..")" ) end
          res = name
        end
      elseif n.kind=="applyMethod" then
        if n.inst.module.functions[n.fnname].inputType==types.null() or n.inst.module.functions[n.fnname].inputType:isInil() then
          --res = n.inst.module.functions[n.fnname].delay
          --          assert(false)
          table.insert( statements, "(assert (= "..name.." "..n.inst.module.functions[n.fnname].delay.."))" )
          res = name
        else
          table.insert( statements, "(assert (>= "..name.." (+ "..inputs[1].." "..n.inst.module.functions[n.fnname].delay..")))" )
          local bts = n.inputs[1].type:extractData():verilogBits()
          if bts>0 then table.insert( ofTerms, "(* (- "..name.." "..inputs[1]..") "..bts..")" ) end
          res = name
          --res = inputs[1] + n.inst.module.functions[n.fnname].delay
          --assert(false)
        end
      elseif n.kind=="statements" then
        table.insert( statements, "(assert (= "..name.." "..inputs[1].."))" )
        res = name
      elseif n.kind=="selectStream" then
        -- for concat, we currently make all stream delays the same! So just look at index 1 always
        table.insert( statements, "(assert (= "..name.." "..inputs[1].."))" )
        res = name
      else
        print("delay NYI - ",n.kind,input.type,output.type)
        assert(false)
      end
      
      err( type(res)=="string", "delay thing returned something other than a string?",res )
      return res
    end)

  -- add extra constraints to make sure FanOuts are delayed from FanIns
  local __INPUT = {} -- token to indicate this traces directly to input
  local traceDelay = {} -- name->minDelayFromInput (this is the sum of the delays in the trace back to the input)
  local nodeToName = {}
  output:visitEach(
    function(n, arg)
      local name = J.verilogSanitizeInner(n.name)
      nodeToName[n] = name

      local res
      
      if n.kind=="input" or n.kind=="constant" then
        res = J.broadcast(__INPUT,types.streamCount(n.type))
        traceDelay[name] = J.broadcast(0,types.streamCount(n.type))
      elseif n.kind=="concat" or n.kind=="concatArray2d" then
        traceDelay[name] = {}
        res = {}
        for i=1,#n.inputs do
          assert( #arg[i] == n.inputs[i].type:streamCount() )
          
          if #arg[i]>=1 then
            J.err( #arg[i]==1, "concat: an input has multiple streams?\ninput:", i,"\n",n.inputs[i],"\nty:",n.inputs[i].type,"\nstcnt:",n.inputs[i].type:streamCount(),"\nargcnt:",#arg[i],"\n",n,"\n",arg[i][1],"\n",tostring(arg[i][2]) )
            res[i] = arg[i][1]
            traceDelay[name][i] = traceDelay[ nodeToName[n.inputs[i]] ][1]
          else
            print("Concat with strange number of streams?",n)
            assert(false)
          end
        end

      elseif n.kind=="apply" or n.kind=="applyMethod" then --(n.kind=="applyMethod" and rigel.isPlainFunction(n.inst.module)) then

        local fn = n.fn
        if n.kind=="applyMethod" and rigel.isPlainFunction(n.inst.module) then
          fn = n.inst.module
        elseif n.kind=="applyMethod" then
          fn = n.inst.module.functions[n.fnname]
        end

        local delay = 0

        --assert( #n.inputs==1 )
        if #n.inputs==1 then
          for i=1,fn.inputType:streamCount() do
            --assert( #traceDelay[ nodeToName[n.inputs[i]] ]==1 )
            delay = math.max( delay, traceDelay[ nodeToName[n.inputs[1]] ][i]+fn.delay )
          end
        elseif #n.inputs==0 then
          delay = fn.delay
        else
          assert(false)
        end
        
        traceDelay[name] = J.broadcast( delay, n.type:streamCount() )
        
        if fn.inputType:streamCount()<=1 and fn.outputType:streamCount()<=1 then
          if fn.outputType:streamCount()==0 then
            res = {}
          elseif fn.inputType:streamCount()==0 then
            res = J.broadcast(__INPUT,types.streamCount(n.type))
          else
            assert( fn.outputType:streamCount()==1 )
            res = {arg[1][1]}
          end
        elseif fn.inputType:streamCount()==1 and fn.outputType:streamCount()>1 then
          -- always consider these to be fan outs
          res = J.broadcast( name, n.type:streamCount() )
        elseif fn.inputType:streamCount()>1 and fn.outputType:streamCount()==1 then
          -- always consider these to be fan ins
          assert(#arg==1)
          assert(#arg[1]==types.streamCount(fn.inputType) )


          for i=1,types.streamCount(fn.inputType) do
            -- insert constraints to make sure delay of this node is at least 1 larger than prior fanin/out
            if arg[1][i]~=__INPUT then -- paths to input don't need a FIFO
              local minDelay = traceDelay[name][1] - traceDelay[ arg[1][i] ][1] + 2
              table.insert( statements, "(assert (>= "..name.." (+ "..arg[1][i].." "..minDelay.."))) ; DIAMOND" )
            end
          end

          -- now, if we fan in, make sure we have a FIFO after this node...
          res = J.broadcast(name,types.streamCount(n.type))
        elseif fn.inputType:streamCount()==fn.outputType:streamCount() and fn.fifoStraightThrough then
          -- sort of a hack: we marked this function to indicate that streams pass straight through, so we can just propagate signals
          res = arg[1]
        else
          J.err(false, "unknown fn fifo behavior? ",fn.name," type:",fn.inputType,"->",fn.outputType," inputCount:",#n.inputs," inputStreamCount:",fn.inputType:streamCount()," outputStreamCount:",fn.outputType:streamCount() )
        end
      elseif n.kind=="selectStream" then
        res = {arg[1][n.i+1]}
        traceDelay[name] = {traceDelay[ nodeToName[n.inputs[1]] ][n.i+1]}
      elseif n.kind=="statements" then
        res = arg[1]
        traceDelay[name] = traceDelay[ nodeToName[n.inputs[1]] ]
      else
        J.err( false, "NYI - Diamond insertion on ",n)
      end

      J.err( type(res)=="table", "diamond insertion bad res ",n )
      J.err( #res == types.streamCount(n.type), "diamond insertion error (res:",#res,",streamcount:",types.streamCount(n.type),",type:",n.type,")- ",n )

      for i=1,#res do
        assert( res[i]==__INPUT or type(res[i])=="string")
      end

      J.err( type(traceDelay[name])=="table", "diamond insertion bad traceDelay ",n, "is:"..tostring(traceDelay[name]) )
      J.err( #traceDelay[name] == types.streamCount(n.type), "diamond insertion error traceDelay (res:",#res,",streamcount:",types.streamCount(n.type),",type:",n.type,")- ",n," #traceDelay",#traceDelay[name] )

      for i=1,#res do
        assert( type(traceDelay[name][i])=="number" )
      end

      return res
    end)
  
  local z3str = {}
  table.insert(z3str,"(set-option :produce-models true)")
  table.insert(z3str,"(declare-const MINVAR Int)")
  for k,v in ipairs(statements) do
    table.insert(z3str, v )
  end
  if #ofTerms==0 then
    table.insert(z3str,"(assert (>= MINVAR 0))")
  else
    table.insert(z3str,"(assert (>= MINVAR (+ "..table.concat(ofTerms," ")..")))")
  end
  table.insert(z3str, "(minimize MINVAR )")
  table.insert(z3str, "(check-sat)")
  --table.insert(z3str, "(get-objectives)")
  table.insert(z3str, "(get-model)")
  
  z3str = table.concat(z3str,"\n")

  if verbose then
    print("** Z3STR_"..moduleName)
    print(z3str)
  end
  
  local z3call = [[echo "]]..z3str..[[" | z3 -in -smt2]]

  local f = assert (io.popen (z3call))
  
  local res = ""
  local curname
  local delayTable = {}

  local totalbits
  for line in f:lines() do
    if string.match(line,"error") then
      J.err(false,"Z3 Error:", line, " from command: ",z3str)
      
    elseif string.match(line,"%|%->") then
      -- some versions of z3 write out the objective function
    elseif string.match(line,"define%-fun") then
      local nam = string.match(line,"define%-fun (%g+)")
      curname = nam
    elseif string.match (line, "%d+") then
      local num = string.match (line, "%d+")
      num = tonumber(num)
      err(type(curname)=="string","name not set? is:",curname)
      if curname=="MINVAR" then
        totalbits = num
      else
        err( seenNames[curname]~=nil,"name not valid?",curname )
        delayTable[curname] = num
      end
    end
  end

  f:close()

  if verbose then
    print("** TOTALBITS",totalbits)
    print("** DELAYTABLE")
    for k,v in pairs(delayTable) do
      print("|"..k.."|"..v.."|")
    end
  end
  
  local delayTableASTs = {}
  for k,v in pairs(seenNames) do
    err( delayTable[k]~=nil," missing delay for: ",k)
    delayTableASTs[v] = delayTable[k]
  end
  
  err( type(delayTableASTs[output])=="number","delay for output missing? name: ",output.name," is: ",delayTableASTs[output] )
--  print("RES",res)
  
--  if string.match(res,"sat") then
--    local num = string.match (res, "%d+")
--    print("Z3MAX:",num)
--    J.err(num~=nil and type(tonumber(num))=="number","failed to find maximum value of expr? "..tostring(self))
--    return tonumber(num)
--  else
--    assert(false)
--  end

  return delayTableASTs[output], delayTableASTs
end


local function calculateDelaysGreedy( output )
  local delayTable = {}
  local resdelay = output:visitEach(
    function(n, inputs)
      local res
      if n.kind=="input" or n.kind=="constant" then
        res = 0
      elseif n.kind=="concat" or n.kind=="concatArray2d" then
        res = math.max(unpack(inputs))
      elseif n.kind=="apply" or (n.kind=="applyMethod" and rigel.isPlainFunction(n.inst.module)) then

        local fn = n.fn
        if n.kind=="applyMethod" and rigel.isPlainFunction(n.inst.module) then
          fn = n.inst.module
        end

        -- if we have burstiness, we need to add a fifo, which will introduce extra delay!
        local extra = 0
        if fn.inputType:isRV() then extra = extra + FIFOSizeToDelay(fn.inputBurstiness) end
        if fn.outputType:isRV() then extra = extra + FIFOSizeToDelay(fn.outputBurstiness) end
        
        if fn.inputType==types.Interface() or (fn.inputType:isrv() and fn.inputType:extractData():verilogBits()==0) then
          res = fn.delay+extra
        else
          err(fn.delay~=nil,"Error: fn ",fn.name," is missing delay? ",fn.inputType," ",fn.outputType)
          res = inputs[1] + fn.delay + extra
        end
      elseif n.kind=="applyMethod" then
        if n.inst.module.functions[n.fnname].inputType==types.null() or n.inst.module.functions[n.fnname].inputType:isInil() then
          res = n.inst.module.functions[n.fnname].delay
        else
          res = inputs[1] + n.inst.module.functions[n.fnname].delay
        end
      elseif n.kind=="statements" then
        res = inputs[1]
      elseif n.kind=="selectStream" then
        res = inputs[1]
      else
        print("delay NYI - ",n.kind,input.type,output.type)
        assert(false)
      end
      
      err( type(res)=="number",n.kind.." returned a non-numeric delay? returned:", res, n)
      delayTable[n] = res
      return res
    end)

  assert(type(resdelay)=="number")

  return resdelay, delayTable
end

-- function definition
-- output, inputs
-- autofifos: override global autofifo setting
function modules.lambda( name, input, output, instanceList, generatorStr, generatorParams, globalMetadata, autofifos, z3fifos, X )
  if DARKROOM_VERBOSE then print("lambda start '"..name.."'") end

  err( X==nil, "lambda: too many arguments" )
  err( type(name) == "string", "lambda: module name must be string" )
  err( input==nil or rigel.isIR( input ), "lambda: input must be a rigel input value or nil" )
  err( input==nil or input.kind=="input", "lambda: input must be a rigel input or nil" )
  err( rigel.isIR( output ), "modules.lambda: module '",name,"' output should be Rigel value, but is: ",output )
  if instanceList==nil then instanceList={} end
  err( type(instanceList)=="table", "lambda: instances must be nil or a table")
  J.map( instanceList, function(n) err( rigel.isInstance(n), "lambda: instances argument must be an array of instances" ) end )
  err( generatorStr==nil or type(generatorStr)=="string","lambda: generatorStr must be nil or string")
  err( generatorParams==nil or type(generatorParams)=="table","lambda: generatorParams must be nil or table")
  err( globalMetadata==nil or type(globalMetadata)=="table","lambda: globalMetadata must be nil or table")

  -- should we compile thie module as handshaked or not?
  -- For handshaked modules, the input/output type is _not_ necessarily handshaked
  -- for example, input/output type could be null, but the internal connections may be handshaked
  -- so, check if we handshake anywhere
  local HANDSHAKE_MODE = rigel.handshakeMode(output)

  local instanceMap = J.invertTable(instanceList)
  instanceList=nil -- now invalid

  -- collect instances (user doesn't have to explicitly give all instances)
  local instanceMap, provides, requires, requiresWithReadys = collectInstances( name, output, instanceMap )
  
  if rigel.SDF then
    input, output = lambdaSDFNormalize(input,output,name)
    local sdfMaxRate = output:sdfExtremeRate(true)

    if (Uniform(sdfMaxRate[1]):le(sdfMaxRate[2]):assertAlwaysTrue())==false then
      output:visitEach(function(n) print(tostring(n)) end)
      err( false,"LambdaSDFNormalize failed? somehow we ended up with a instance utilization of "..tostring(sdfMaxRate[1]).."/"..tostring(sdfMaxRate[2]).." somewhere in module '"..name.."'")
    end
  end
  
  --local resdelay, delayTable = calculateDelaysGreedy( output )

  local resdelay, delayTable

  if (rigel.Z3_FIFOS and HANDSHAKE_MODE and z3fifos==nil) or z3fifos==true then
    resdelay, delayTable = calculateDelaysZ3( output, name )
  else
    resdelay, delayTable = calculateDelaysGreedy( output, name )
  end

  local inputBurstiness = 0
  local outputBurstiness = 0
  
  if (rigel.AUTO_FIFOS~=false and autofifos==nil) or autofifos==true then

    if HANDSHAKE_MODE and input~=nil and input.type:isInil()==false then
      output = insertFIFOs( output, delayTable, name )
    elseif input~=nil and input.type:isInil()==false then
      output:visitEach(
        function(n)
          if n.kind=="apply" then
            if n==output and n.inputs[1].kind=="input" then
              -- HACK! For wrappers, just propagate the bursts up!
              inputBurstiness = n.fn.inputBurstiness
              outputBurstiness = n.fn.outputBurstiness
            else
              err( n.fn.inputBurstiness==0 and n.fn.outputBurstiness==0, "NYI: burstiness must be 0 for non-handshaked modules! \nmodule:",name,":",input.type,"->",output.type," \ncontains function:",n.fn.name,":",n.fn.inputType,"->",n.fn.outputType," \ninputBurstiness:", tostring(n.fn.inputBurstiness), " outputBurstiness:", tostring(n.fn.outputBurstiness)," loc:", n.loc )
            end
          end
      end)
    else
--      print("NYI - FIFO ALLOCATION FOR INIL MODULE")
    end
  end
  
  name = J.verilogSanitize(name)

  local res = {kind = "lambda", name=name, input = input, output = output, instanceMap=instanceMap, generator=generatorStr, params=generatorParams, requires = requires, provides=provides, globalMetadata={}, delay = resdelay }

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
        err( type(n.fn.stateful)=="boolean", "Missing stateful annotation, fn ",n.fn.name )
        res.stateful = res.stateful or n.fn.stateful
      elseif n.kind=="applyMethod" then
        if rigel.isModule(n.inst.module) then
          err( type(n.inst.module.functions[n.fnname].stateful)=="boolean", "Missing stateful annotation, fn "..n.fnname )
          res.stateful = res.stateful or n.inst.module.functions[n.fnname].stateful
        elseif rigel.isPlainFunction(n.inst.module) then
          err( type(n.inst.module.stateful)=="boolean", "Missing stateful annotation, fn "..n.fnname )
          res.stateful = res.stateful or n.inst.module.stateful
        else
          assert(false)
        end
      end
    end)

  for inst,_ in pairs(res.instanceMap) do
    res.stateful = res.stateful or inst.module.stateful
  end  

  -- collect metadata
  output:visitEach(
    function(n)
      if n.kind=="apply" or n.kind=="applyMethod" then
        local globalMetadata
        if n.kind=="apply" then globalMetadata=n.fn.globalMetadata else globalMetadata=n.inst.module.globalMetadata end
        
        for k,v in pairs(globalMetadata) do
          err( res.globalMetadata[k]==nil or res.globalMetadata[k]==v,"Error: wrote to global metadata '",k,"' twice! this value: '",v,"', orig value: '",res.globalMetadata[k],"' ",n.loc)
          res.globalMetadata[k] = v
        end
      end
    end)

  -- NOTE: notice that this will overwrite the previous metadata values
  if globalMetadata~=nil then
    for k,v in pairs(globalMetadata) do
      J.err(type(k)=="string","global metadata key must be string")

      if res.globalMetadata[k]~=nil and res.globalMetadata[k]~=v then
        --print("WARNING: overwriting metadata '"..k.."' with previous value '"..tostring(res.globalMetadata[k]).."' ("..type(res.globalMetadata[k])..") with overridden value '"..tostring(v).."' ("..type(v)..")")
      end
      
      res.globalMetadata[k]=v
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

    err(SDF.isSDF(res.sdfInput),"NOT SDF inp ",res.name," ",tostring(res.sdfInput))
    err(SDF.isSDF(res.sdfOutput),"NOT SDF out ",res.name," ",tostring(res.sdfOutput))

    if DARKROOM_VERBOSE then print("LAMBDA",name,"SDF INPUT",res.sdfInput[1][1],res.sdfInput[1][2],"SDF OUTPUT",res.sdfOutput[1][1],res.sdfOutput[1][2]) end

    -- each rate should be <=1
    for k,v in ipairs(res.sdfInput) do
      err( v[1]:le(v[2]):assertAlwaysTrue(), "lambda '",name,"' has strange SDF rate. input: ",tostring(res.sdfInput)," output:",tostring(res.sdfOutput))
    end
      
    -- each rate should be <=1
    for _,v in ipairs(res.sdfOutput) do
      err( v[1]:le(v[2]):assertAlwaysTrue(), "lambda '",name,"' has strange SDF rate. input: ",tostring(res.sdfInput)," output:",tostring(res.sdfOutput))
    end

  end

  if HANDSHAKE_MODE then
    res.fifoed = checkFIFOs( output, name )
  end
  
  local function makeSystolic( fn )
    local module = Ssugar.moduleConstructor( fn.name ):onlyWire( HANDSHAKE_MODE )

    local process = module:addFunction( Ssugar.lambdaConstructor( "process", rigel.lower(fn.inputType), "process_input") )
    local reset

    local rateMonitors = { usValid={}, dsValid={}, dsReady={}, delay={}, rate={}, functionName={} }
    
    if fn.stateful then
      reset = module:addFunction( Ssugar.lambdaConstructor( "reset", types.null(), "resetNILINPUT", "reset") )
    end
    
    for inst,_ in pairs(fn.instanceMap) do
      err( systolic.isModule(inst.module.systolicModule), "Missing systolic module for instance '",inst.name,"' of module '",inst.module.name,"'")
      -- even though this isn't external here, it may be refered to in other modules (ie some ports may be externalized), so we need to use the same instance
      local I = module:add( inst:toSystolicInstance() )
        
      if inst.module.stateful then
        J.err(module:lookupFunction("reset")~=nil,"module '",fn.name,"' instantiates a stateful module '",inst.module.name,"', but is not itself stateful? stateful=",res.stateful )
        module:lookupFunction("reset"):addPipeline( I["reset"](I,nil,module:lookupFunction("reset"):getValid()) )
      end
    end

    for inst,fnmap in pairs(fn.requires) do
      module:addExternal( inst:toSystolicInstance(), fnmap )

      -- hack: systolic expects ready to be explicitly given! 
      if rigel.isModule(inst.module) then
        for fnname,_ in pairs(fnmap) do
          local fn = inst.module.functions[fnname]

          if types.isHandshakeAny(fn.inputType) or types.isHandshakeAny(fn.outputType) then
            module:addExternalFn( inst:toSystolicInstance(), fnname.."_ready" )
          end
        end
      elseif rigel.isPlainFunction(ic.instance.module) then
        if types.isHandshakeAny(ic.instance.module.inputType) or types.isHandshakeAny(ic.instance.module.outputType) then
          module:addExternalFn( inst:toSystolicInstance(), fnname.."_ready" )
        end
      else
        assert(false)
      end
    end

    for inst,fnmap in pairs(fn.provides) do
      for fnname,_ in pairs(fnmap) do
        module:addProvidesFn( inst:toSystolicInstance(), fnname )

        -- hack...
        if rigel.isModule(inst.module) then
          local fn = inst.module.functions[fnname]
          if types.isHandshakeAny(fn.inputType) or types.isHandshakeAny(fn.outputType) then
            module:addProvidesFn( inst:toSystolicInstance(), fnname.."_ready" )
          end
        elseif rigel.isPlainFunction(inst.module) then
          if types.isHandshakeAny(inst.module.inputType) or types.isHandshakeAny(inst.module.outputType) then
            module:addProvidesFn( inst:toSystolicInstance(), fnname.."_ready" )
          end
        else
          assert(false)
        end
      end
    end

    local out = fn.output:codegenSystolic( module, rateMonitors )

    --if HANDSHAKE_MODE==false then
    if fn.inputType:isrv() and fn.outputType:isrv() then
      err( (out[1]:getDelay()>0) == (res.delay>0), "Module '"..res.name.."' is declared with delay=",res.delay," but systolic AST delay=",out[1]:getDelay()," which doesn't match")
    end
    
    if HANDSHAKE_MODE==false and (res.stateful or res.delay>0) then 
      local CE = S.CE("CE")
      process:setCE(CE)
    end

    assert(systolic.isAST(out[1]))

    err( out[1].type==rigel.lower(res.outputType), "modules.lambda: Internal error, systolic output type is ",out[1].type," but should be ",rigel.lower(res.outputType)," function ",name )

    -- for the non-handshake (purely systolic) modules, the ready bit doesn't flow from outputs to inputs,
    -- it flows from inputs to outputs. The reason is that upstream things can't stall downstream things anyway, so there's really no point of doing it the 'right' way.
    -- this is kind of messed up!
    if fn.inputType:isrRV() and fn.output.type:isrRV() then
      -- weird (old) RV->RV fn type?
      assert( S.isAST(out[2]) )
      local readyfn = module:addFunction( S.lambda("ready", readyInput, out[2], "ready", {} ) )
    elseif fn.inputType:isrV() and fn.outputType:isrRV() then
      local readyfn = module:addFunction( S.lambda("ready", S.parameter("RINIL",types.null()), out[2], "ready", {} ) )
    elseif HANDSHAKE_MODE then
      local readyinp, readyout, readyPipelines = fn.output:codegenSystolicReady( module, rateMonitors )
      local readyfn = module:addFunction( S.lambda("ready", readyinp, readyout, "ready", readyPipelines ) )
    end

    assert(Ssugar.isFunctionConstructor(process))
    process:setOutput( out[1], "process_output" )

    --err( module:lookupFunction("process"):isPure() ~= res.stateful, "Module '"..res.name.."' is declared stateful=",res.stateful," but systolic AST is pure=",module:lookupFunction("process"):isPure()," which doesn't match!",out[1] )

    return module
  end

  function res.makeSystolic()
    local systolicModule = makeSystolic(res)
    systolicModule:toVerilog()
    return systolicModule
  end

  if DARKROOM_VERBOSE then  print("lambda done '",name,"'") end

  return rigel.newFunction( res )
end

-- makeTerra: a lua function that returns the terra implementation
-- makeSystolic: a lua function that returns the systolic implementation. 
--      Input argument: systolic input value. Output: systolic output value, systolic instances table
-- outputType, delay are optional, but will cause systolic to be built if they are missing!
function modules.lift( name, inputType, outputType, delay, makeSystolic, makeTerra, generatorStr, sdfOutput, instanceMap, X )
  err( type(name)=="string", "modules.lift: name must be string" )
  err( types.isType( inputType ), "modules.lift: inputType must be rigel type" )
  err( inputType:isData(),"modules.lift: inputType should be Data Type, but is: ",inputType)
  err( outputType==nil or types.isType( outputType ), "modules.lift: outputType must be rigel type, but is "..tostring(outputType) )
  err( outputType==nil or outputType:isData(),"modules.lift: outputType should be Data Type, but is: "..tostring(outputType))
  err( delay==nil or type(delay)=="number",  "modules.lift: delay must be number" )
  err( sdfOutput==nil or SDFRate.isSDFRate(sdfOutput),"modules.lift: SDF output must be SDF")
  err( makeTerra==nil or type(makeTerra)=="function", "modules.lift: makeTerra argument must be lua function that returns a terra function" )
  err( type(makeSystolic)=="function", "modules.lift: makeSystolic argument must be lua function that returns a systolic value" )
  err( generatorStr==nil or type(generatorStr)=="string", "generatorStr must be nil or string")
  assert(X==nil)

  if instanceMap==nil then instanceMap={} end
  err( type(instanceMap)=="table", "lift:  instanceMap should be table")
  
  if sdfOutput==nil then sdfOutput = SDF{1,1} end

  name = J.verilogSanitize(name)
  
  local res = { kind="lift", name=name, inputType = inputType, delay=delay, sdfInput=SDF{1,1}, sdfOutput=SDF(sdfOutput), stateful=false, generator=generatorStr, instanceMap=instanceMap }

  if outputType==types.null() then
    res.outputType = types.Interface()
  else
    res.outputType = outputType
  end
  
  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(name)

    local systolicInput = S.parameter( "inp", inputType )

    local systolicOutput, systolicInstances
    systolicOutput, systolicInstances = makeSystolic(systolicInput)
    
    err( ( (outputType==types.null() or outputType==types.Trigger) and systolicOutput==nil) or systolicAST.isSystolicAST(systolicOutput), "modules.lift: makeSystolic returned something other than a systolic value (module "..name.."), returned: ",systolicOutput )

    if outputType~=nil and systolicOutput~=nil then -- user may not have passed us a type, and is instead using the systolic system to calculate it
      err( systolicOutput.type==rigel.lower(types.S(types.Par(outputType))), "lifted systolic output type does not match. Is ",systolicOutput.type," but should be ",outputType,", which lowers to ",rigel.lower(types.S(types.Par(outputType)))," (module ",name,")" )
    end
    
    if systolicInstances~=nil then
      for k,v in pairs(systolicInstances) do systolicModule:add(v) end
    end

    local CE
    if systolicOutput~=nil and (delay==nil or delay>0) then
      if (systolicOutput:isPure()==false or systolicOutput:getDelay()>0) then
        CE = S.CE("process_CE")
      end
    end
    
    systolicModule:addFunction( S.lambda("process", systolicInput, systolicOutput, "process_output",nil,nil,CE) )

    systolicModule:complete()
    return systolicModule
  end

  J.err(types.isType(res.outputType),"modules.lift: missing outputType")

  if res.delay==nil then
    local SM = res.makeSystolic()
    res.delay = SM:getDelay("process")
    function res.makeSystolic() return SM end
  end

  local res = rigel.newFunction( res )

  if terralib~=nil then 
    local systolicInput, systolicOutput

    if makeTerra==nil then
      systolicInput = res.systolicModule.functions.process.inputParameter
      systolicOutput = res.systolicModule.functions.process.output
    end

    local tmod = MT.lift( res, name, inputType, outputType, makeTerra, systolicInput, systolicOutput )
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

function modules.moduleLambda( name, functionList, instanceList, X )
  err( type(name)=="string", "moduleLambda: name must be string")
  assert(X==nil)
  
    -- collect globals of all fns
  local requires = {}
  local provides = {}
  local globalMetadata = {}
  local stateful = false
  for k,fn in pairs(functionList) do
    err( type(k)=="string", "newModule: function name should be string?")
    err( rigel.isPlainFunction(fn), "newModule: function should be plain Rigel function")

    for inst,fnlist in pairs(fn.requires) do for fn,_ in pairs(fnlist) do J.deepsetweak(requires,{inst,fn},1) end end
    for inst,fnlist in pairs(fn.provides) do for fn,_ in pairs(fnlist) do J.deepsetweak(provides,{inst,fn},1) end end

    for k,v in pairs(fn.globalMetadata) do assert(globalMetadata[k]==nil); globalMetadata[k]=v end
    stateful = stateful or fn.stateful
  end

  if instanceList==nil then instanceList={} end
  err( type(instanceList)=="table", "moduleLambda: instanceList should be table")
  local instanceMap = {}
  for _,inst in pairs(instanceList) do
    err( rigel.isInstance(inst), "moduleLambda: entries in instanceList should be instances" )
    for inst,fnlist in pairs(inst.module.requires) do for fn,_ in pairs(fnlist) do J.deepsetweak(requires,{inst,fn},1) end end
    for inst,fnlist in pairs(inst.module.provides) do for fn,_ in pairs(fnlist) do J.deepsetweak(provides,{inst,fn},1) end end

    instanceMap[inst] = 1
  end

  --makeSystolic=makeSystolic,makeTerra=makeTerra, 
  local tab = {name=name,functions=functionList, globalMetadata=globalMetadata, stateful=stateful, requires=requires, provides=provides, instanceMap=instanceMap, stateful=stateful }

  return rigel.newModule(tab)
end

function modules.liftVerilogTab(tab)
  return modules.liftVerilog( tab.name, tab.inputType, tab.outputType, tab.vstr, tab.globalMetadata, tab.sdfInput, tab.sdfOutput, tab.instanceMap, tab.delay, tab.inputBurstiness, tab.outputBurstiness, tab.stateful )
end

-- requires: this is a map of instance callsites (for external requirements)
-- instanceMap: this is a map of rigel instances of modules this depends on
modules.liftVerilog = memoize(function( name, inputType, outputType, vstr, globalMetadata, sdfInput, sdfOutput, instanceMap, delay, inputBurstiness, outputBurstiness, stateful, X )
  err( type(name)=="string", "liftVerilog: name must be string")
  err( types.isType(inputType), "liftVerilog: inputType must be type")
  err( types.isType(outputType), "liftVerilog: outputType must be type")
  err( type(vstr)=="string" or type(vstr)=="function", "liftVerilog: verilog string must be string or function that produces string")
  err( globalMetadata==nil or type(globalMetadata)=="table", "liftVerilog: global metadata must be table")
  if sdfInput==nil then sdfInput=SDF{1,1} end
  err( SDFRate.isSDFRate(sdfInput), "liftVerilog: sdfInput must be SDF rate, but is: "..tostring(sdfInput))
  if sdfOutput==nil then sdfOutput=SDF{1,1} end
  err( SDFRate.isSDFRate(sdfOutput), "liftVerilog: sdfOutput must be SDF rate, but is: "..tostring(sdfOutput))
  err( X==nil, "liftVerilog: too many arguments")
  if stateful==nil then stateful = true end

  local res = { kind="liftVerilog", inputType=inputType, outputType=outputType, verilogString=vstr, name=name, instanceMap=instanceMap, delay = delay, inputBurstiness=inputBurstiness, outputBurstiness=outputBurstiness }
  res.stateful = stateful
  res.sdfInput=SDF(sdfInput)
  res.sdfOutput=SDF(sdfOutput)

  res.requires = {}

  res.globalMetadata = {}
  if globalMetadata~=nil then
    for k,v in pairs(globalMetadata) do
      res.globalMetadata[k] = v
    end
  end
    
  if instanceMap~=nil then
    for inst,_ in pairs(instanceMap) do
      J.err(rigel.isInstance(inst),"liftVerilog: instance map should be map of instances, but is: ",inst)

      for inst,fnlist in pairs(inst.module.requires) do
        for fn,_ in pairs(fnlist) do
          J.deepsetweak(res.requires,{inst,fn},1)
        end
      end

      for kk,vv in pairs(inst.module.globalMetadata) do
        res.globalMetadata[kk] = vv
      end
      
    end
  end

  function res.makeSystolic()
    if type(vstr)=="function" then
      vstr = vstr(res)
    end

    local C = require "generators.examplescommon"
    local s = C.automaticSystolicStub(res)
    s:verilog(vstr)
    return s
  end
  
  return rigel.newFunction(res)
end)

modules.liftVerilogModule = memoize(function( name, vstr, functionList, stateful, X )
  err( type(name)=="string", "liftVerilogModule: name must be string")
  err( type(vstr)=="string", "liftVerilogModule: verilog string must be string")
  err( type(functionList)=="table", "liftVerilogModule: functionList must be table")
  err( X==nil, "liftVerilog: too many arguments")

  for _,fn in pairs(functionList) do
    err( rigel.isPlainFunction(fn),"liftVerilogModule: functions in function list should be rigel functions")
  end
  
  local res = rigel.newModule{ name=name, functions=functionList, stateful=stateful }

  function res.makeSystolic()
    local C = require "generators.examplescommon"
    local s = C.automaticSystolicStub(res)
    s:verilog(vstr)
    return s
  end
  
  return res
end)

modules.constSeqInner = memoize(function( value, A, w, h, T, X )
  err( type(value)=="table", "constSeq: value should be a lua array of values to shift through")
  err( J.keycount(value)==#value, "constSeq: value should be a lua array of values to shift through")
  err( #value==w*h, "constSeq: value array has wrong number of values")
  err( X==nil, "constSeq: too many arguments")
  err( T>=1, "constSeq: T must be >=1")
  err( type(w)=="number", "constSeq: W must be number" )
  err( type(h)=="number", "constSeq: H must be number" )
  err( types.isType(A), "constSeq: type must be type" )

  for k,v in ipairs(value) do
    err( A:checkLuaValue(v), "constSeq value array index "..tostring(k).." cannot convert to the correct systolic type" )
  end

  local res = { kind="constSeq", A = A, w=w, h=h, value=value, T=T}
  res.inputType = types.rv(types.Par(types.Trigger))
  local W = w/T
  err( W == math.floor(W), "constSeq T must divide array size")
  res.outputType = types.rv(types.Par(types.array2d(A,W,h)))
  res.stateful = (T>1)

  res.sdfInput, res.sdfOutput = SDF{1,1}, SDF{1,1}  -- well, technically this produces 1 output for every (nil) input

  -- TODO: FIX: replace this with an actual hash function... it seems likely this can lead to collisions
  local vh = J.to_string(value)
  if #vh>50 then vh = string.sub(vh,0,50) end
  
  -- some different types can have the same lua array representation (i.e. different array shapes), so we need to include both
  res.name = verilogSanitize("constSeq_"..tostring(A).."_"..tostring(vh).."_T"..tostring(T).."_w"..tostring(w).."_h"..tostring(h))
  res.delay = 0

  if terralib~=nil then res.terraModule = MT.constSeq(res, value, A, w, h, T,W ) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local sconsts = J.map(J.range(T), function() return {} end)
    
    for C=0, T-1 do
      for y=0, h-1 do
        for x=0, W-1 do
          table.insert(sconsts[C+1], value[y*w+C*W+x+1])
        end
      end
    end

    local shiftOut, shiftPipelines, resetPipelines = fpgamodules.addShifterSimple( systolicModule, J.map(sconsts, function(n) return S.constant(n,types.array2d(A,W,h)) end), DARKROOM_VERBOSE )
    
    local inp = S.parameter("process_input", types.Trigger )

    local CE
    if res.stateful then
      CE = S.CE("process_CE")
      systolicModule:addFunction( S.lambda("reset", S.parameter("process_nilinp", types.null() ), nil, "process_reset", resetPipelines, S.parameter("reset", types.bool() ) ) )
    end
    
    systolicModule:addFunction( S.lambda("process", inp, shiftOut, "process_output", shiftPipelines, nil, CE ) )

    return systolicModule
  end

  return rigel.newFunction( res )
end)

function modules.constSeq( value, A, w, h, T, X )
  err( type(value)=="table", "constSeq: value should be a lua array of values to shift through")
  local UV = J.uniq(value)
  local I = modules.constSeqInner(UV,A,w,h,T,X)
  return I
end

-- addressable: if true, this will accept an index, which will seek to the location every cycle
modules.freadSeq = memoize(function( filename, ty, addressable, X )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  err( ty:verilogBits()>0, "freadSeq: type has zero size?" )
  err( X==nil, "freadSeq: too many arguments" )
  rigel.expectBasic(ty)
  local filenameVerilog=filename
  local res = {kind="freadSeq", filename=filename, filenameVerilog=filenameVerilog, type=ty, stateful=true, delay=3}

  if addressable then
    res.inputType=types.rv(types.Par(types.uint(32)))
    res.outputType=types.rv(types.Par(ty))
  else
    res.inputType=types.rv(types.Par(types.Trigger))
    res.outputType=types.rv(types.Par(ty))
  end
  
  res.sdfInput=SDF{1,1}
  res.sdfOutput=SDF{1,1}

  if addressable==nil then addressable=false end
  err( type(addressable)=="boolean", "freadSeq: addressable must be bool")

  res.name = J.sanitize("freadSeq_"..verilogSanitize(filename)..verilogSanitize(tostring(ty)).."_addressable"..tostring(addressable))

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local sfile = systolicModule:add( S.module.file( filenameVerilog, ty, true, true, true, false, true ):instantiate("freadfile") )
    local inp
    if addressable then
      inp = S.parameter("process_input", types.uint(32) )
    else
      inp = S.parameter("process_input", types.null() )
    end
    
    local nilinp = S.parameter("process_nilinp", types.null() )
    local CE = S.CE("CE")

    systolicModule:addFunction( S.lambda("process", inp, sfile:read(inp), "process_output", nil, nil, CE ) )
    systolicModule:addFunction( S.lambda("reset", nilinp, nil, "process_reset", {sfile:reset()}, S.parameter("reset", types.bool() ) ) )

    return systolicModule
  end

  res = rigel.newFunction(res)

  if terralib~=nil then res.terraModule = MT.freadSeq( res, filename, ty, addressable ) end
  
  return res
end)

-- passthrough: write out the input? default=true
-- allowBadSizes: hack for legacy code - allow us to write sizes which will have different behavior between verilog & terra (BAD!)
-- tokensX, tokensY: optional - what is the size of the transaction? enables extra debugging (terra checks for regressions on second run)
-- 'filename' is used for Terra
-- We don't modify filenames in any way!
-- header: a string to append at the very start of the file
modules.fwriteSeq = memoize(function( filename, ty, filenameVerilog, passthrough, allowBadSizes, tokensX, tokensY, header, X )
  err( type(filename)=="string", "filename must be a string")
  err( types.isType(ty), "type must be a type")
  rigel.expectBasic(ty)
  if passthrough==nil then passthrough=true end
  err( type(passthrough)=="boolean","fwriteSeq: passthrough must be bool" )
  err(X==nil,"fwriteSeq: too many arguments")

  if filenameVerilog==nil then filenameVerilog=filename end
  
  local res = {kind="fwriteSeq", filename=filename, filenameVerilog=filenameVerilog, type=ty, inputType=ty, outputType=J.sel(passthrough,ty,types.null()), stateful=true, delay=2, sdfInput=SDF{1,1}, sdfOutput=SDF{1,1} }

  res.name = verilogSanitize("fwriteSeq_"..filename.."_"..tostring(ty))

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)

    local sfile = systolicModule:add( S.module.file( filenameVerilog, ty, true, passthrough, false, true, nil, header ):instantiate("fwritefile") )

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

  res = rigel.newFunction(res)

  if terralib~=nil then res.terraModule = MT.fwriteSeq( res, filename,ty,passthrough, allowBadSizes, tokensX, tokensY, header ) end

  return res
end)

local function readAll(file)
    local f = io.open(file, "rb")
    local content = f:read("*all")
    f:close()
    return content
end

-- this is a Handshake triggered counter.
-- it accepts an input value V of type TY.
-- Then produces N tokens (from V to V+(N-1)*stride)
modules.triggeredCounter = memoize(function(TY, N, stride, framed, X)
  err( types.isType(TY),"triggeredCounter: TY must be type")
  err( rigel.expectBasic(TY), "triggeredCounter: TY should be basic")
  err( TY:isNumber(), "triggeredCounter: type must be numeric rigel type, but is "..tostring(TY))
  if stride==nil then stride=1 end
  err( type(stride)=="number", "triggeredCounter: stride should be number")
  if framed==nil then framed=false end
  assert(type(framed)=="boolean")
  assert(X==nil)
  
  err(type(N)=="number", "triggeredCounter: N must be number")

  local res = {kind="triggeredCounter"}
  res.inputType = types.rv(types.Par(TY))
  if framed then
    res.outputType = types.rRvV(types.Seq(types.Par(TY),N,1))
  else
    res.outputType = types.rRvV(types.Par(TY))
  end
  res.sdfInput = SDF{1,N}
  res.sdfOutput = SDF{1,1}
  res.stateful=true
  res.delay = 3
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
modules.triggerCounter = memoize(function(N_orig)
    --err(type(N)=="number", "triggerCounter: N must be number")
  local N = Uniform(N_orig)

  local res = {kind="triggerCounter"}
  res.inputType = types.rv(types.Par(types.Trigger))
  res.outputType = types.rvV(types.Par(types.Trigger))
  res.sdfInput = SDF{1,1}
  res.sdfOutput = SDF{1,N}
  res.stateful=true
  res.delay=0
  res.name = J.sanitize("TriggerCounter_"..tostring(N_orig))
  res.includeMap = N:getInstances()
  
  if terralib~=nil then res.terraModule = MT.triggerCounter(res,N) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    
    local sPhase = systolicModule:add( Ssugar.regByConstructor( types.uint(32), fpgamodules.sumwrap(types.uint(32),N-1) ):CE(true):setReset(0):instantiate("phase") )
    
    --local done = S.eq(sPhase:get(),S.constant(N-1,types.uint(32))):disablePipelining()
    local done = S.eq( sPhase:get(),Uniform(N-1):toSystolic(types.uint(32),systolicModule) ):disablePipelining()

    local out = S.tuple{S.constant(types.Trigger:fakeValue(),types.Trigger),done}
    
    local pipelines = {}
    table.insert( pipelines, sPhase:setBy( S.constant(1,types.uint(32)) ) )
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", S.parameter( "inp", types.Trigger ), out, "process_output", pipelines, nil, CE) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:reset()},S.parameter("reset",types.bool()) ) )

    return systolicModule
  end

  return modules.liftHandshake(modules.liftDecimate( rigel.newFunction(res), true ))
end)

-- just counts from 0....N-1
local counterInner = memoize(function(ty,N,X)
  err( types.isType(ty), "counter: type must be rigel type")                          
  err( ty:isUint() or ty:isInt(), "counter: type must be uint or int")
  assert(X==nil)
  assert(Uniform.isUniform(N))
  J.err( N:ge(1):assertAlwaysTrue(), "modules.counter: N must be >= 1, but is: "..tostring(N) )
  
  local res = {kind="counter"}
  res.inputType = types.rv(types.Par(types.Trigger))
  res.outputType = types.rv(types.Par(ty))
  res.sdfInput = SDF{1,1}
  res.sdfOutput = SDF{1,1}
  res.stateful=true
  res.delay=0
  res.name = J.sanitize("Counter_"..tostring(ty).."_"..tostring(N))
  res.instanceMap=N:getInstances()
  res.requires = {}
  N:appendRequires(res.requires)
  res.provides = {}
  N:appendProvides(res.provides)
  
  if terralib~=nil then res.terraModule = MT.counter(res,ty,N) end

  function res.makeSystolic()
    local systolicModule = Ssugar.moduleConstructor(res.name)
    
    local sPhase = systolicModule:add( Ssugar.regByConstructor( ty, fpgamodules.sumwrap(ty,N-1) ):CE(true):setReset(0):instantiate("phase") )
    
    local pipelines = {}
    table.insert( pipelines, sPhase:setBy( S.constant(1,ty) ) )
    
    local CE = S.CE("CE")
    systolicModule:addFunction( S.lambda("process", S.parameter( "inp", types.Trigger ), sPhase:get(), "process_output", pipelines, nil, CE) )
    systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro", {sPhase:reset()},S.parameter("reset",types.bool()) ) )

    return systolicModule
  end

  local res = rigel.newFunction(res)
  return res
end)
modules.counter = function(ty,N_orig) return counterInner(ty,Uniform(N_orig)) end
  
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

-- extraPortIsWrite: should the extra port be a write port?
modules.reg = memoize(function(ty,initial,extraPortIsWrite,read1bits,X)
  if read1bits==nil then read1bits=32 end
  assert(type(read1bits)=="number")
  assert(types.isType(ty))
  assert(ty:isData())
  ty:checkLuaValue(initial)
  assert(X==nil)

  J.err( ty:verilogBits()<32 or ty:verilogBits()%read1bits==0,"reg: request type '"..tostring(ty).."' of bits '"..(ty:verilogBits()).."'  must be divisible by "..read1bits)
  
  local tab = {name=J.sanitize("Reg_"..tostring(ty).."_read1bits"..tostring(read1bits).."_extraPortIsWrite"..tostring(extraPortIsWrite).."_init"..tostring(initial)), stateful=true, functions={}}
  if extraPortIsWrite==true then
    tab.functions.write1 = rigel.newFunction{name="write1",inputType=types.rv(types.Par(ty)),outputType=types.Interface(),sdfInput=SDF{1,1},sdfOutput=SDF{1,1},stateful=true,delay=0}
  else
    tab.functions.read1 = rigel.newFunction{name="read1",inputType=types.Interface(),outputType=types.rv(types.Par(ty)),sdfInput=SDF{1,1},sdfOutput=SDF{1,1},stateful=false,delay=0}
  end
  
  tab.functions.read = rigel.newFunction{name="read",inputType=types.rv(types.Par(types.Uint(32))),outputType=types.rv(types.Par(types.Bits(read1bits))),sdfInput=SDF{1,1},sdfOutput=SDF{1,1},stateful=false,delay=0}
  tab.functions.write = rigel.newFunction{name="write",inputType=types.rv(types.Par(types.Tuple{types.Uint(32),types.Bits(read1bits)})),outputType=types.Interface(),sdfInput=SDF{1,1},sdfOutput=SDF{1,1},stateful=true,delay=0}
  
  local res = rigel.newModule(tab)
  --assert(res.size==nil)
  --res.size = ty:verilogBits()
  assert(res.type==nil)
  res.type = ty
  assert(res.init==nil)
  res.init=initial
  
  function res.makeSystolic()
    local C = require "generators.examplescommon"
    local s = C.automaticSystolicStub(res)

    local vstr = {res:vHeader()..[=[
  reg []=]..(read1bits-1)..[=[:0] r[]=]..(math.max(ty:verilogBits()/read1bits,1)-1)..[=[:0];
]=]}

    table.insert(vstr,[=[
assign read_output = r[read_input];
]=])
    
    if extraPortIsWrite~=true then
      if ty:verilogBits()<32 then
        table.insert(vstr,"assign read1_output = r[0]["..(ty:verilogBits()-1)..":0];\n")
      else
        for i=0,(ty:verilogBits()/read1bits)-1 do
          table.insert(vstr,"assign read1_output["..((i+1)*read1bits-1)..":"..(i*read1bits).."] = r["..i.."];\n")
        end
      end
    end
    
table.insert(vstr,[=[  always @(posedge CLK) begin
    if (write_CE && write_valid) begin
      r[write_input[31:0]] <= write_input[63:32];
    end]=])

  if extraPortIsWrite==true then
    table.insert(vstr," else if(write1_CE && write1_valid) begin\n")
    if ty:verilogBits()<32 then
      table.insert(vstr,[=[r[0] <= {]=]..(32-ty:verilogBits()).."'d0,write1_input};\n")
    else
      for i=0,(ty:verilogBits()/read1bits)-1 do
        table.insert(vstr,"r["..i.."] = write1_input["..((i+1)*read1bits-1)..":"..(i*read1bits).."];\n")
      end
    end
    table.insert(vstr,"end\n")
  end

table.insert(vstr,[=[  end
endmodule

]=])

    s:verilog(table.concat(vstr,""))
    
    return s
  end

  if terralib~=nil then res.terraModule = MT.reg(ty,initial,extraPortIsWrite,read1bits) end
  
  return res
end)

modules.shiftRegister = J.memoize(function(ty, N, clear )
  assert( types.isType(ty) )
  assert( ty:isSchedule() )
  assert( type(N)=="number" )
  err( N>0, "shift register with 0 delay?" )

  if clear==nil then clear=false end
  
  local modname = J.sanitize("ShiftRegisterDELAY"..tostring(N).."_"..tostring(ty))
  local res = rigel.newFunction{ inputType = types.rv(ty), outputType = types.rv(ty), name = modname, delay=N, stateful=true, sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, generator="ShiftRegister" }

  if terralib~=nil then res.terraModule = MT.shiftRegister( res, ty, N ) end
  
  function res.makeSystolic()
    local C = require "generators.examplescommon"
    local s = C.automaticSystolicStub(res)
    
    local verilog = {res:vHeader()}

    if ty:lower():verilogBits()==0 then
      -- do nothing! it's empty
      --    elseif N<10 then
    elseif N<10 then
      -- it's possible ty is a trigger...
      if ty:lower():verilogBits()>0 then
        for i=1,N do
          table.insert(verilog,"reg ["..(ty:lower():verilogBits()-1)..":0] DELAY_"..i..";\n")
        end
        table.insert(verilog,"assign "..res:vOutput().." = DELAY_"..N..";\n")
        
        table.insert(verilog,[[always @(posedge CLK) begin
]])

        if clear then
table.insert(verilog,[[  if( reset ) begin
]])
        for i=1,N do
          table.insert(verilog,"    DELAY_"..i.." <= "..(ty:lower():verilogBits()).."'d0;\n")
        end

             table.insert(verilog,[[
end else ]])          
        end
        
table.insert(verilog,[[  if( process_CE ) begin
    DELAY_1 <= ]]..res:vInput()..[[;
]])

        for i=2,N do
          table.insert(verilog,"    DELAY_"..i.." <= DELAY_"..(i-1)..";\n")
        end
        
        table.insert(verilog,[[  end
end
]])
      end
    else
      local nearestN = J.nearestPowerOf2(N)
      local addrBits = math.log(nearestN)/math.log(2)

--      for i=1,nearestN do
--        table.insert(verilog,ty:lower():verilogBits())
--        table.insert(verilog,"'d0")
--        if i<nearestN then table.insert(verilog,",") end
--      end

      table.insert(verilog, [[  reg []]..(addrBits-1)..[[:0] writeAddr = ]]..addrBits..[['d]]..(N%nearestN)..[[;
  reg []]..(addrBits-1)..[[:0] readAddr = ]]..addrBits..[['d0;
  reg []]..(ty:lower():verilogBits()-1)..[[:0] ram []]..(nearestN-1)..[[:0];

  assign ]]..res:vOutput()..[[ = ram[readAddr];

reg [31:0] i;
reg [31:0] j;

  always @(posedge CLK) begin
]])

      if clear then
      table.insert(verilog,[[
  if( reset ) begin
      for(i=0; i<]]..nearestN..[[-1; i=i+1) begin
        for(j=0; j<]]..(ty:lower():verilogBits())..[[; j=j+1) begin
           ram[i][j] = 1'b0;
        end
      end   
    end else]])
      end
      
table.insert(verilog,[[      if( process_CE ) begin
      ram[writeAddr] <= ]]..res:vInput()..[[;
      readAddr <= readAddr + ]]..addrBits..[['d1;
      writeAddr <= writeAddr + ]]..addrBits..[['d1;
    end
  end
]])
      
    end
    
    table.insert(verilog,[[
endmodule

]])

    s:verilog(table.concat(verilog))
    return s
  end
  
  return res
end)

return modules
