local systolic = require("systolic")
local Ssugar = require("systolicsugar")
local types = require("types")
local SS = Ssugar
local J = require "common"
local memoize = J.memoize
local err = J.err
local Uniform = require "uniform"

local S=systolic
--statemachine = require("statemachine")
local modules = {}

-- calculate A+B s.t. A+B <= limit
modules.sumwrap = memoize(function( ty, limit_orig, X)
  err( types.isType(ty), "sumwrap: type must be rigel type, but is: "..tostring(ty) )
  err( ty:isNumber(), "sumwrap: type must be numeric rigel type, but is "..tostring(ty))
  
  local limit = Uniform(limit_orig)
  assert(X==nil)

  local name = J.sanitize("sumwrap_"..tostring(ty).."_to"..tostring(limit_orig))

  local mod = Ssugar.moduleConstructor(name)
  local swinp = S.parameter("process_input", types.tuple{ty,ty})
  local ot = S.select(S.eq(S.index(swinp,0),limit:toSystolic(ty,mod)),
                      S.constant(0,ty),
                      S.index(swinp,0)+S.index(swinp,1)):disablePipelining()
  mod:addFunction(S.lambda("process",swinp,ot,"process_output",nil,nil))
  return mod
end)

-- {uint16,bool}->uint16. Increment by inc if the bool is true s.t. output <= limit
modules.incIf = memoize(function( inc, ty, X )
  if inc==nil then inc=1 end
  if ty==nil then ty=types.uint(16) end
  assert(X==nil)

  local swinp = S.parameter("process_input", types.tuple{ty,types.bool()})
  
  local ot = S.select( S.index(swinp,1), S.index(swinp,0)+S.constant(inc,ty), S.index(swinp,0) ):disablePipelining()
  return S.module.new( J.sanitize("incif_"..inc..tostring(ty)), {process=S.lambda("process",swinp,ot,"process_output",nil,nil)},{})
end)

-- this will never wrap around (this just stops at top value)
modules.incIfNowrap=memoize(function(inc,ty)
  if inc==nil then inc=1 end
  if ty==nil then ty=types.uint(16) end
  
  local max
  if ty:isUint() then
    max = math.pow(2,ty.precision)-1
  else
    assert(false)
  end
  local swinp = S.parameter("process_input", types.tuple{ty,types.bool()})
  
  local ot = S.select( S.__and(S.index(swinp,1),S.lt(S.index(swinp,0),S.constant(max,ty))), S.index(swinp,0)+S.constant(inc,ty), S.index(swinp,0) ):disablePipelining()
  return S.module.new( "incifnowrap_"..inc..tostring(ty), {process=S.lambda("process",swinp,ot,"process_output",nil,nil,S.CE("CE"))},{})
end)

-- we generally want to use incIf if we are going to increment a variable based on some (calculated) condition.
-- The reason for this is if we module the valid bit based on the condition, the valid bit may go into a undefined state.
-- (ie at init time the condition will be unstable garbage or X's). This allows us to not mess with the valid bit,
-- but still conditionally increment.
modules.incIfWrap = memoize(function( ty, limit_orig, inc, X )
  err(types.isType(ty), "incIfWrap: type must be rigel type")
  local limit = Uniform(limit_orig)
  err( X==nil, "incIfWrap: too many arguments" )

  local mod = Ssugar.moduleConstructor(J.sanitize("incif_wrap_"..tostring(ty).."_"..tostring(limit_orig).."_inc"..tostring(inc)))
  local incv = inc or 1
  local swinp = S.parameter("process_input", types.tuple{ty, types.bool()})
  
  local nextValue = S.select( S.eq(S.index(swinp,0), limit:toSystolic(ty,mod) ), S.constant(0,ty), S.index(swinp,0)+S.constant(incv,ty) )
  local ot = S.select( S.index(swinp,1), nextValue, S.index(swinp,0) ):disablePipelining()
  --return S.module.new( J.sanitize("incif_wrap"..tostring(ty).."_"..tostring(limit_orig).."_inc"..tostring(inc)), {process=S.lambda("process",swinp,ot,"process_output",nil,nil)},{})

  mod:addFunction(S.lambda("process",swinp,ot,"process_output",nil,nil))
  return mod
end)


------------
local swinp = S.parameter("process_input", types.tuple{types.uint(16),types.uint(16)})
modules.sum = S.module.new( "summodule", {process=S.lambda("process",swinp,(S.index(swinp,0)+S.index(swinp,1)):disablePipelining(),"process_output")},{})
------------
modules.max = memoize(function(ty,hasCE)
  local swinp = S.parameter("process_input", types.tuple{ty,ty})
  local CE = S.CE("CE")
  if hasCE==false then CE=nil end
  return S.module.new( "maxmodule", {process=S.lambda("process",swinp,S.select(S.gt(S.index(swinp,0),S.index(swinp,1)),S.index(swinp,0),S.index(swinp,1)):disablePipelining(),"process_output",nil,nil)},{})
end)
------------
local swinp = S.parameter("process_input", types.tuple{types.bool(),types.bool()})
modules.__and = S.module.new( "andmodule", {process=S.lambda("process",swinp,S.__and(S.index(swinp,0),S.index(swinp,1)),"process_output")},{})
------------
local swinp = S.parameter("process_input", types.tuple{types.bool(),types.bool()})
modules.__andSingleCycle = S.module.new( "andmoduleSingleCycle", {process=S.lambda("process",swinp,S.__and(S.index(swinp,0),S.index(swinp,1)):disablePipelining(),"process_output")},{})
------------
-- modsub calculates A-B where A,B are mod 'wrap'. We say that A>=B always. So if A<B (as stored), we calculate it as if they have just wrapped around circularly.
-- This is obviously ambiguous - we can't tell how many times A vs B have wrapped around. Assume they have only wrapped around once.
function modules.modSub( A, B, wrap )
  assert( systolic.isAST(A))
  assert( systolic.isAST(B))
  assert(A.type==B.type)
  assert(type(wrap)=="number")
  
  return S.select(S.lt(A,B), S.constant(wrap, A.type)-B+A, A-B )
end

------------

--local terra bitselect(a : uint, bit : uint)
--  return a and bit
--end

local function bitselect(a,biti)
   return bit.band(a,biti)
end

-- make an array of ram128s to service a certain bandwidth
modules.ram128 = function(ty, init)
  assert(types.isType(ty))
  local ram128 = Ssugar.moduleConstructor( J.sanitize("ram128_"..tostring(ty)) )
  local bits = ty:verilogBits()
  
  assert(type(init)=="table")
  local slicedInit = {}
  for b=1,bits do
    slicedInit[b] = {}
    for i=1,#init do
      slicedInit[b][i] = (bitselect(init[i],math.pow(2,b-1))~=0)
    end
  end

  local rams = J.map( J.range( bits ), function(v) return ram128:add(systolic.module.ram128(false,true,slicedInit[v]):instantiate("ram"..v)) end )

  local read = ram128:addFunction( Ssugar.lambdaConstructor("read",types.uint(8),"read_input") )
--  pushBackReset:setCE(pushCE)

  local bitfield = J.map( J.range(bits), function(b) return rams[b]:read( S.cast( read:getInput(), types.uint(7)) ) end)
  read:setOutput( systolic.cast( S.tuple(bitfield), ty), "read_output" )

  return ram128
end

-- build a bits-width ram out of slices.
-- Saves compile times with large # of bits... always makes constant size modules, even with 10000s of bits
-- module interface looks the same as systolic.module.ram128()
modules.sliceRamGen = J.memoize(function(bits)
  assert(bits>0)

  local ram = Ssugar.moduleConstructor( J.sanitize("sliceRamGen_"..tostring(bits)) )

  local readFn = ram:addFunction( Ssugar.lambdaConstructor("read",types.uint(7),"readAddr") )
  readFn:setCE(S.CE("RE"))

  local remainingBits = bits

  local output = {}

  local writeFn = ram:addFunction( Ssugar.lambdaConstructor("write",types.tuple{types.uint(7),types.bits(bits)},"writeAddrAndData") )
  writeFn:setCE(S.CE("WE"))

  local addr = S.index(writeFn:getInput(),0)
  
  local i = 0
  while remainingBits>0 do
    local thisBits = J.nearestPowerOf2(remainingBits)
    if thisBits>1 then thisBits = thisBits/2 end

    local m
    if thisBits==1 then
      m = systolic.module.ram128()
    else
      m = modules.sliceRamGen(thisBits)
    end
    
    local inst = ram:add(m:instantiate("subinst_"..i))

    table.insert(output, inst:read(readFn:getInput()) )

    local seenBits = bits - remainingBits
    local thisWriteData = S.bitSlice(S.index(writeFn:getInput(),1),seenBits,seenBits+thisBits-1)
    writeFn:addPipeline( inst:write(S.tuple{addr,thisWriteData}) )

    remainingBits = remainingBits - thisBits
    i = i + 1
  end
  readFn:setOutput( S.cast(S.tuple(output),types.bits(bits)),"readOut")

  return ram
end)

modules.fifo = memoize(function( ty, items, verbose, nostall, X )
  err(types.isType(ty),"fifo type must be type")
  err(type(items)=="number","fifo items must be number")
  err(type(verbose)=="boolean","fifo verbose must be bool")
  err( items>1,"fifo: items must be >1, but is: ",items)
  assert( X==nil )
  
  local fifo = Ssugar.moduleConstructor( J.sanitize("fifo_"..tostring(ty).."_"..items.."_nostall"..tostring(nostall)) )
  -- writeAddr, readAddr hold the address we will read/write from NEXT time we do a read/write
  local addrBits = (math.ceil(math.log(items)/math.log(2)))+1 -- the +1 is so that we can disambiguate wraparoudn
  local writeAddr = fifo:add( modules.regBy( types.uint(addrBits), modules.incIfWrap(types.uint(addrBits),items-1), true,nil,0 ):instantiate("writeAddr"))
  local readAddr = fifo:add( modules.regBy( types.uint(addrBits), modules.incIfWrap(types.uint(addrBits),items-1), true,nil,0 ):instantiate("readAddr"))
  local bits = ty:verilogBits()
  local bytes = bits/8
  bytes = math.ceil(bytes) -- bits may not be byte aligned
  
  local ram, rams
  if items <= 128 and J.isPowerOf2(bits) then
    ram = fifo:add( modules.sliceRamGen(bits):instantiate("ram") )
  elseif items <= 128 then
    rams = J.map( J.range( bits ), function(v) return fifo:add(systolic.module.ram128():instantiate("fifo"..v)) end )
  else
    ram = fifo:add(modules.bramSDP( true, J.nearestPowerOf2(items)*bytes, bytes, bytes, nil, true ):instantiate("ram"))
  end

  -- size
  local sizeFn = fifo:addFunction( Ssugar.lambdaConstructor("size") )
  local fsize = modules.modSub(writeAddr:get(),readAddr:get(), items ):disablePipelining()
  sizeFn:setOutput( fsize, "size" )

  -- ready (not full)
  -- HACK: this is definitely an abuse of registers w/no valid bit. No valid bit=>isPure()==true. So then this function is pure.
  -- Calculating the ready bit can take a bit of time, and we don't want the fifo to limit the speed of our design
  -- So, we pipeline the ready bit calculation. This means that the ready bit will be READY_PIPELINE cycles out of date of what it should be.
  -- ie when it is getting full, it will be true for READY_PIPELINE more cycles than it should be.
  -- To account for this, pretend the FIFO size is READY_PIPELINE entries smaller. Then, when we run over the end, it won't cause errors.
  local readyReg = fifo:add( S.module.reg(types.bool(),false,nil,false):instantiate("readyReg") )
  local READY_PIPELINE = 1
  local readyFn = fifo:addFunction( Ssugar.lambdaConstructor("ready") )
  local ready = S.lt( fsize, S.constant(items-2-READY_PIPELINE,types.uint(addrBits)) ):disablePipelining()
  readyFn:addPipeline( readyReg:set(ready) )
  readyFn:setOutput( readyReg:get(), "ready" )

  -- has data
  local hasDataFn = fifo:addFunction( Ssugar.lambdaConstructor("hasData") )
  local hasData = S.__not( S.eq( writeAddr:get(), readAddr:get()) ):disablePipelining()
  hasDataFn:setOutput( hasData, "hasData" )

  -- pushBack
  local pushCE = S.CE("CE_push")
  local pushBack = fifo:addFunction( Ssugar.lambdaConstructor("pushBack",ty,"pushBack_input" ) )
  pushBack:setCE(pushCE)
  local pushBackAssert = fifo:add( systolic.module.assert( "attempting to push to a full fifo", true, nostall~=true ):instantiate("pushBackAssert") )
  local hasSpace = S.lt( fsize, S.constant(items-2,types.uint(addrBits)) ):disablePipelining() -- note that this is different than ready
  pushBack:addPipeline( pushBackAssert:process( hasSpace )  )
  pushBack:addPipeline( writeAddr:setBy(systolic.constant(true, types.bool()) ) )

  if items<=128 and J.isPowerOf2(bits) then
    pushBack:addPipeline( ram:write( S.tuple{ S.cast(writeAddr:get(),types.uint(7)), S.cast(pushBack:getInput(),types.bits(bits))} )  )
  elseif items<=128 then
    for b=1,bits do
      pushBack:addPipeline( rams[b]:write( S.tuple{ S.cast(writeAddr:get(),types.uint(7)), S.bitSlice(pushBack:getInput(),b-1,b-1)} )  )
    end
  else
    local tinp = S.cast(pushBack:getInput(),types.bits(bits))
    tinp = S.cast(tinp,types.bits(bytes*8))
    pushBack:addPipeline( ram:writeAndReturnOriginal( S.tuple{ S.cast(writeAddr:get(),types.uint(addrBits-1)), tinp} )  )
  end

  -- pushBackReset
  local pushBackReset = fifo:addFunction( Ssugar.lambdaConstructor("pushBackReset" ) )
  pushBackReset:addPipeline( writeAddr:reset() )

  -- popFront
  local popCE = S.CE("CE_pop")
  local popFront = fifo:addFunction( Ssugar.lambdaConstructor("popFront") )
  popFront:setCE(popCE)
  local popFrontAssert = fifo:add( systolic.module.assert( "attempting to pop from an empty fifo", true ):instantiate("popFrontAssert") )
  popFront:addPipeline( popFrontAssert:process( hasData ) )
  local popFrontPrint
  if verbose then 
    popFrontPrint= fifo:add( systolic.module.print( types.tuple{types.uint(addrBits),types.uint(addrBits),types.uint(addrBits),types.bool()},"FIFO readaddr %d writeaddr %d size %d ready %d", true):instantiate("popFrontPrintInst") ) 
    popFront:addPipeline( popFrontPrint:process( S.tuple{readAddr:get(), writeAddr:get(), fsize, readyReg:get()} ) )
  end
  popFront:addPipeline( readAddr:setBy( S.constant(true, types.bool() ) ) )

  local popOutput
  if items<=128 and J.isPowerOf2(bits) then
    local bitfield = ram:read(S.cast( readAddr:get(), types.uint(7)))
    popOutput = systolic.cast( bitfield, ty)
    popFront:setOutput( popOutput, "popFront" )
  elseif items<=128 then
    local bitfield = J.map( J.range(bits), function(b) return rams[b]:read( S.cast( readAddr:get(), types.uint(7)) ) end)
    popOutput = systolic.cast( systolic.tuple(bitfield), ty)
    popFront:setOutput( popOutput, "popFront" )
  else
    popOutput = S.cast(ram:read(S.cast(readAddr:get(),types.uint(addrBits-1))),types.uint(bytes*8))
    popOutput = S.cast(popOutput,types.uint(bits))
    popOutput = S.cast(popOutput,types.bits(bits))
    popOutput = S.cast(popOutput,ty)
    popFront:setOutput( popOutput, "popFront" )
  end

  -- peekFront
  local peekFront = fifo:addFunction( Ssugar.lambdaConstructor("peekFront") )
  peekFront:setOutput( popOutput, "peekFront" )
  peekFront:setCE(popCE)
  
  -- popFrontReset
  local popFrontReset = fifo:addFunction( Ssugar.lambdaConstructor("popFrontReset" ) )
  popFrontReset:addPipeline( readAddr:reset() )

  return fifo
end)

modules.fifo128 = memoize(function(ty,verbose) return modules.fifo(ty,128,verbose) end)

modules.fifonoop = memoize(function( ty, addrBits, moduleName )
  assert(types.isType(ty))

  if moduleName==nil then
    moduleName = J.sanitize("fifonoop_"..tostring(ty).."_addrbits"..tostring(addrBits))
  end
  
  local fifo = Ssugar.moduleConstructor( moduleName ):onlyWire(true)

  local internalData = systolic.parameter("store_input",types.tuple{ty,types.bool()})
  local internalReady = systolic.parameter("load_ready_downstream",types.bool())

  -- pushBack
  local pushBack = fifo:addFunction( systolic.lambda("store",internalData,nil,"store_input",{} ) )
  local pushBack_ready = fifo:addFunction( systolic.lambda("store_ready",S.parameter("SRNIL",types.null()),internalReady,"store_ready",{} ) )

  -- popFront
  local popFront = fifo:addFunction( S.lambda("load",S.parameter("pfnil",types.null()),internalData,"load_output") )
  local popFront_ready = fifo:addFunction( S.lambda("load_ready",internalReady,nil,"load_ready") )

  -- size
  local size = fifo:addFunction( Ssugar.lambdaConstructor("size" ) )
  size:setOutput(S.constant(0,types.uint(addrBits)),"size")
  
  -- reset
  --local reset = fifo:addFunction( Ssugar.lambdaConstructor("reset" ) )

  return fifo
end)

-- tab should be a key of systolic values. Key is a systolic value that chooses between them.
-- key is 0 indexed
function modules.wideMux( tab, key )
  assert(#tab>0)
  local packed = J.map(tab, function(t,i) return S.tuple{t,S.eq(key,S.constant(i-1,types.uint(16)))} end )
  local r = J.foldt( packed, function(a,b) return S.select(S.index(a,1),a,b) end )
  return S.index(r,0)
end

modules.shiftRegisterOld = memoize(function( ty, size, resetValue, CE, X )
  err( types.isType(ty),"shiftRegister: type must be type, but is: "..tostring(ty))
  err( type(size)=="number","shiftRegister: size must be number")
  assert(X==nil)
  if resetValue~=nil then ty:checkLuaValue(resetValue) end
  err( type(CE)=="boolean", "CE option must be bool")

  local M = Ssugar.moduleConstructor( "ShiftRegister_"..size.."_CE"..tostring(CE).."_TY"..ty:verilogBits() )
  local pipelines = {}
  local resetPipelines = {}
  local out
  local inp = systolic.parameter("sr_input", ty)
  local regs = {}

  local ppvalid = systolic.parameter("process_valid",types.bool())
  local rstvalid = systolic.parameter("reset",types.bool())

  for i=1,size do
    local I = M:add( systolic.module.reg( ty, CE, nil, nil, resetValue ):instantiate("SR"..i) )
    table.insert( regs, I )
    if i==1 then
      table.insert(pipelines, I:set(inp) )
    else
      table.insert(pipelines, I:set(regs[i-1]:get()) )
    end
    table.insert( resetPipelines, I:reset() )
    if i==size then out=I:get() end
  end
  if size==0 then out=inp end

  local CEvar = J.sel(CE,S.CE("CE"),nil)
  local pushPop = M:addFunction( systolic.lambda("process", inp, out, "process_out", pipelines, ppvalid, CEvar ) )
  local reset = M:addFunction( systolic.lambda("reset", systolic.parameter("R",types.null()), nil, "reset_out", resetPipelines, rstvalid ) )

  return M
end)

modules.shiftRegister = function( ty, size, resetValue, CE, X )
  if (resetValue==nil or resetValue==0 or resetValue==false) and CE and size>0 then
    local RM = require "generators.modules"
    local mod = RM.shiftRegister( ty, size, resetValue~=nil )
    return mod.systolicModule
  else
    return modules.shiftRegisterOld( ty, size, resetValue, CE )
  end
end

-- This returns a module that keeps track of phase. It returns a phase value and a valid bit.
-- valid bit is only true after a full phase has completed.
--
-- If period=2 it returns:
-- t0: value=0, valid=false
-- t1: value=1, valid=false
-- t2: value=0, valid=true
-- t3: value=1, valid=false
function modules.addPhaser( module, period, fnValidBit )
  assert( math.floor(period)==period )
  assert(S.isAST(fnValidBit))

  local phase = module:add( S.module.regByConstructor( types.uint(16), modules.sumwrap( types.uint(16), period-1) ):includeCE():instantiate("phase") )
  local notFirstCycle = module:add( S.module.reg( types.bool() ):instantiate("notFirstCycle",{arbitrate="valid"}) )

  local valueout = phase:get()
  local validbit = S.__and(S.eq(phase:get(), S.constant(0,types.uint(16))), notFirstCycle:get())
  local resetPipelines = {phase:set( S.constant(0, types.uint(16) ) ), notFirstCycle:set( S.constant( false, types.bool() ), fnValidBit )}
  local pipelines = {phase:setBy( S.constant(1,types.uint(16)) ), notFirstCycle:set( S.constant(true, types.bool() ), fnValidBit ) }

  return valueout, validbit, pipelines, resetPipelines
end

-- If exprs[i] === exprs[i+j](j*P), then we can just read exprs[i] out of reg[i+j] (and not have to calcuate exprs[i]).
-- Where P=#exprs
-- (reg[i]:get() == exprs[i](P), because we do a read every P cycles)
local function optimizeShifter( exprs, regs, stride, period, X )
  assert(type(period)=="number")
  assert(X==nil)

  local CSErepo = {}
  local internalized = J.map(exprs, function(e) local node, totalDelay = e:internalizeDelays(); return {node=node:CSE(CSErepo), delay=totalDelay} end)

  local newexprs = {}

  -- search for matches
--  local P = #exprs
  for i=1,#exprs do
    local nearestj, nearestV
    for j=1,#exprs-i do
      if internalized[i].node==internalized[i+j].node then
        local dist =  internalized[i].delay - (internalized[i+j].delay+j*period)
        if dist>=0 and (nearestj==nil or dist<nearestV) then
          nearestj, nearestV = j, dist
        end
      end
    end

    -- the j that we find may not match exactly (we may need to add a few extra delays).
    -- This may not theoretically provide any benefit, but it may help if Verilog's CSE fails (which is likely).
    -- It shouldn't make it any worse...
    if nearestj~=nil then
      local i_0idx = i-1 -- do this 0 indexed b/c 1 indexed is confusing
      -- we actually read at the (period-1), b/c in the cycle we read the values haven't been shifted all the way back to their original position yet
      -- remember, we bypass the SR on cycle 0
      -- (-endOffset) is where value exprs[1] will end up in the array after we do all the shift cycles
      local endOffset = stride*(period-1)
      -- note that lua's mod behaves 'correctly' for negative numbers
      newexprs[i] = (regs[(i_0idx-endOffset+nearestj)%#exprs+1]:get())(nearestV)
    else
      newexprs[i] = exprs[i]
    end
  end

  return newexprs
end

-- This is a nice interface for generating a shift register.
-- This takes a table of expressions 'exprs', and returns a code quote
-- that returns their values over #exprs clock cycles. Also returns
-- a value that tells you whether it's storing the values in that cycle.
--
-- More precisely, for period==3:
-- t0 returns exprs[1]@t0,true
-- t1 returns exprs[1+stride]@t0,false
-- t2 returns exprs[1+stride*2]@t0,false
-- t3 returns exprs[1]@t3,true
-- t4 returns exprs[1+stride]@t3,false
-- t5 returns exprs[1+stride*2]@t3,false
-- etc
--
-- This does a few clever optimizations:
-- * if all exprs are const, it does no reads.
-- * If one of the exprs happens to have a value that is 
--   already in the shift register, it will just read that value instead
--   of calculating it. This happens if exprs[a] == exprs[b](#exprs), using the delay syntax
function modules.addShifter( module, exprs, stride, period, verbose, X )
  assert( Ssugar.isModuleConstructor(module) )
  assert(type(exprs)=="table")
  assert(#exprs>0)
  assert(#exprs==J.keycount(exprs))
  J.map( exprs, function(e) assert(S.isAST(e)) end )
  assert(type(verbose)=="boolean")
  assert(X==nil)
  assert(math.floor(stride)==stride)
  assert(math.floor(period)==period)

  if #exprs==1 and period==1 then
    -- period==1 => reading is always true
    -- strid doesn't matter (only 1 element)
    -- only 1 element in array: just return it
    return exprs, {}, {}, S.constant( true, types.bool() )
  end

  local resetPipelines, pipelines, out, reading, ty

  J.map(exprs, function(e) assert(ty==nil or e.type==ty); ty=e.type; end )

  local allconst = J.foldl( J.andop, true, J.map(exprs, function(e) return e:const()~=nil end ) )

  if allconst and period*stride==#exprs then
    -- period*stride==#exprs => we will get back to initial condition after 'period' cycles
    local regs = J.map(exprs, function(e,i) return module:add( Ssugar.regConstructor(ty):CE(true):setInit(e:const()):instantiate("SR_"..i) ) end )

    pipelines = J.map( regs, function(r,i) return r:set( regs[((i-1+stride)%#exprs)+1]:get() )  end )
    out = J.map( regs, function(r) return r:get() end )
  else
    local phase = module:add( Ssugar.regByConstructor( types.uint(16), modules.sumwrap(types.uint(16),period-1) ):CE(true):setReset(0):instantiate("phase") )

    resetPipelines = {phase:reset()}
    reading = S.eq(phase:get(),S.constant(0,types.uint(16))):disablePipelining():setName("reading")

    local regs = J.map(exprs, function(e,i) return module:add( Ssugar.regConstructor(ty):CE(true):instantiate("SR_"..i) ) end )

    exprs = optimizeShifter( exprs, regs, stride, period )

    -- notice that in the first cycle we write exprs[1] to regs[1].
    -- Since we bypass exprs[1] to the output on the first cycle, this means we actually always read out of reg[2]
    -- it's possible we may not even use regs[1]. This is just if we end up CSEing (optimizeShifter)
    --
    -- disable pipeling on the select to make sure all the reads/write happen in same cycle (or else we will create timing cycle)
    pipelines = {}
    for i,r in ipairs(regs) do
      local lhs = exprs[i]
      local rhs = regs[((i-1+stride)%#exprs)+1]:get()
      local v =r:set( S.select(reading, lhs, rhs):disablePipeliningSingle() )
      table.insert( pipelines, v )
    end
    
    table.insert( pipelines, phase:setBy( S.constant(1, types.uint(16) ) ) )

    --out = S.select( reading, exprs[1], regs[2]:get() )
    out = J.map( exprs, function(expr,i) return S.select( reading, expr, regs[((i-1+stride)%#exprs)+1]:get() ) end )

    if verbose then
      --local printInst = module:add( S.module.print( types.tuple{types.uint(16),types.bool(),out.type}, "Shifter phase %d reading %d out %h", true):instantiate("printInst") )
      --table.insert( pipelines, printInst:process( S.tuple{phase:get(), reading, out}) )
    end
  end

  return out, pipelines, resetPipelines, reading
end

-- this just rotates through the exprs array, one element per clock
function modules.addShifterSimple( module, exprs, verbose, X )
  assert(type(verbose)=="boolean")
  assert(X==nil)
  local out, pipelines, resetPipelines, reading =  modules.addShifter( module, exprs, 1, #exprs, verbose )
  return out[1], pipelines, resetPipelines, reading
end


function fixedBram(conf)

  assert( type(conf.A.bits)=="number" )
  assert( conf.A.bits==1 or conf.A.bits==2 or conf.A.bits==4 or conf.A.bits==8 or conf.A.bits==16 or conf.A.bits==32)
  assert( type(conf.B.bits)=="number" )
  assert( conf.B.bits==1 or conf.B.bits==2 or conf.B.bits==4 or conf.B.bits==8 or conf.B.bits==16 or conf.B.bits==32)

  local A = "A"
  local B = "B"
  if conf.A.bits>conf.B.bits then A,B=B,A end
  local res = {}

  local configParams = {}
  if conf[A].readFirst then table.insert(configParams, [[.WRITE_MODE_A("READ_FIRST")]]) end
  if conf[B].readFirst then table.insert(configParams, [[.WRITE_MODE_B("READ_FIRST")]]) end

  local initS = ""
  if conf.init~=nil then
      -- init should be an array of bytes
      assert( type(conf.init)=="table")
      assert( #conf.init == 2048 )
      for block=0,63 do
        local S = {}
        for i=0,31 do 
          local value = conf.init[block*32+i+1]
          assert( value < 256 )
          table.insert(S,1,string.format("%02x",value)) 
        end
--        initS = initS..".INIT_"..string.format("%02X",block).."(256'h"..table.concat(S,"").."),\n"
        table.insert(configParams, ".INIT_"..string.format("%02X",block).."(256'h"..table.concat(S,"")..")")
      end
--      table.insert(configParams, initS)
  end

  local Abit = conf[A].bits
  if Abit>=8 then Abit = Abit + (Abit/8) end
  local Bbit = conf[B].bits
  if Bbit>=8 then Bbit = Bbit + (Bbit/8) end
  
  table.insert(res,"RAMB16_S"..tostring(Abit).."_S"..tostring(Bbit).." #("..table.concat(configParams,",")..") "..conf.name.." (\n")
    if conf[A].bits>=8 then
      table.insert(res,".DIPA("..(conf[A].bits/8).."'b0),\n")
    end

    if conf[B].bits>=8 then
      table.insert(res,".DIPB("..(conf[B].bits/8).."'b0),\n")
    end

    if conf[A].DI~=nil then table.insert(res,".DIA("..conf[A].DI.."),\n") end
    if conf[B].DI~=nil then table.insert(res,".DIB("..conf[B].DI.."),\n") end
    if conf[A].DO~=nil then table.insert(res,".DOA("..conf[A].DO.."),\n") end
    if conf[B].DO~=nil then table.insert(res,".DOB("..conf[B].DO.."),\n") end
    table.insert(res,".ADDRA("..conf[A].ADDR.."),\n")
    table.insert(res,".ADDRB("..conf[B].ADDR.."),\n")
    table.insert(res,".WEA("..conf[A].WE.."),\n")
    table.insert(res,".WEB("..conf[B].WE.."),\n")
    table.insert(res,".ENA("..conf[A].EN.."),\n")
    table.insert(res,".ENB("..conf[B].EN.."),\n")
    table.insert(res,".CLKA("..conf[A].CLK.."),\n")
    table.insert(res,".CLKB("..conf[B].CLK.."),\n")
    table.insert(res,".SSRA(1'b0),\n")
    table.insert(res,".SSRB(1'b0)\n")
    table.insert(res,");\n\n")
  return res
end


-- makes a module that implements a large ram out of N smaller rams
local function makeRamArray(
    writeAndReturnOriginal,
    sizeInBytes, -- total size to allocate
    inputBytes,
    outputBytes,
    init,
    CE,

    -- next, we specify the number of rams we have chosen to service the requirements above
    -- there is a tradeoff: depending on the size & BW requirements, we may need to under-utilize either the BW
    -- or the storage.
    -- ramCount/ramBits indicates which choice we have chosen.
    -- ramCount is the # of rams (integer)
    -- ramIn/OutputBits is the BW in bits for the _fully utilized_ rams
    -- if input/output Bytes won't fully utilize the rams, the last ram in the array is dangling!
    --    (IE we don't use all its bits)
    -- NOTE: WE ASSUME USER CHOSE VALID PARAMS HERE! IE: which can successfully service BW/Size requirements above

    ramCount, -- # of rams to make. Can be non-integer (indicates we will underutilize one of the rams)
    ramInputBits, -- input BW of each ram
    ramOutputBits, -- output BW of each ram
    X)

  assert( type(ramCount)=="number" )
  assert( ramCount==math.floor(ramCount) )
  assert( ramCount>0 )
  assert( type(ramInputBits)=="number" )
  assert( J.isPowerOf2(ramInputBits) )
  assert( ramOutputBits==nil or type(ramOutputBits)=="number" )
  assert( ramOutputBits==nil or J.isPowerOf2(ramOutputBits) )
  assert( ramOutputBits==nil or (ramOutputBits>=1 and ramOutputBits<=32) )
  
  assert( ramInputBits>=1 and ramInputBits<=32 ) -- we don't have rams with >32bit bandwidth

  -- THIS IS NOT TRUE: ramInputBits is the BW for the fully utilized rams, not the dangling rams at the end!!
  --assert( ramInputBits*ramCountInt == inputBytes*8 )

  -- # of address bits for each actual ram. We may not fully utilize ram, so round up!
  local ramInputAddrBits = math.ceil(math.log((2048*8)/(ramInputBits))/math.log(2))

  local ramOutputAddrBits
  if outputBytes~=nil then
    ramOutputAddrBits = math.ceil(math.log( (2048*8)/(ramOutputBits))/math.log(2))
  end

  local inputAddrBits = math.log(sizeInBytes/inputBytes)/math.log(2)
  local outputAddrBits
  if outputBytes~=nil then outputAddrBits = math.log(sizeInBytes/outputBytes)/math.log(2) end

  if init~=nil then
    err( ramCount <= 1, "NYI - inits with striped ram array" )

    err( #init==sizeInBytes, "init field has size "..(#init).." but should have size "..sizeInBytes )

    assert( outputBytes==nil or inputBytes==outputBytes )
    
    if inputBytes~=ramInputBits*8 then
      -- we need to pad the bytes
      local newInit = {}
      local realBytes = inputBytes
      local ramInputBytes = ramInputBits/8
      assert(ramInputBytes==math.floor(ramInputBytes))
      local padBytes = ramInputBytes-inputBytes

      for item=0,(sizeInBytes/inputBytes)-1 do
        for b=0,realBytes-1 do table.insert(newInit, init[item*inputBytes+b+1] ) end
        for b=0,padBytes-1 do table.insert(newInit, 0 ) end
      end
      init = newInit
    end

    -- pad out to fill ram entries we're not using
    while #init < 2048 do
      table.insert(init,0)
    end
  end

  if writeAndReturnOriginal then
    local name = J.sanitize("bramSDP_WARO"..tostring(writeAndReturnOriginal).."_size"..sizeInBytes.."_bw"..inputBytes.."_obw"..tostring(outputBytes).."_CE"..tostring(CE).."_init"..tostring(init))
    local mod = Ssugar.moduleConstructor( name )
    
    ------------------ WRITE PORT
    local sinp = systolic.parameter("writeAddrAndData",types.tuple{types.uint(inputAddrBits),types.bits(inputBytes*8)})
    local inpAddr = systolic.index(sinp,0)
    local inpData = systolic.index(sinp,1)

    local inpAddrPadded = inpAddr
    if ramInputAddrBits>inputAddrBits then
      -- ram supplies more addressible items than we require, so pad it out
      inpAddrPadded = systolic.cast( inpAddrPadded, types.uint( ramInputAddrBits ) )
    end

    local out = {}
    local rams = {}
    local writeRamLoc = 0
    for ram=0,ramCount-1 do
      rams[ram] =  mod:add( systolic.module.bram2KSDP( writeAndReturnOriginal, ramInputBits, ramOutputBits, CE, init ):instantiate("bram_"..ram) )

      local writeRamLocNext = math.min(writeRamLoc+ramInputBits, inputBytes*8)
      local inp = systolic.bitSlice( inpData, writeRamLoc, writeRamLocNext-1 )
      inp = systolic.cast( inp, types.bits(ramInputBits) ) -- potentially pad to width

      local ot = rams[ram]:writeAndReturnOriginal( systolic.tuple{inpAddrPadded,inp} )
      ot = systolic.bitSlice( ot, 0, writeRamLocNext-writeRamLoc-1 )
      table.insert( out, ot )

      writeRamLoc = writeRamLocNext
    end
    
    local res = systolic.cast(systolic.tuple(out),types.bits(inputBytes*8))
    
    mod:addFunction( systolic.lambda("writeAndReturnOriginal", sinp, res, "WARO_OUT", nil, nil, J.sel(CE,S.CE("WE"),nil)) )

    ----------- READ PORT
    if outputBytes~=nil then
      local sinpRead = systolic.parameter("readAddr",types.uint(outputAddrBits))

      local outAddrPadded = sinpRead
      if ramOutputAddrBits>outputAddrBits then
        outAddrPadded = systolic.cast( outAddrPadded, types.uint(ramOutputAddrBits) )
      end

      local outRead = {}
      local readLoc = 0
      for ram=0,ramCount-1 do
        local ot = rams[ram]:read(outAddrPadded)
        local readLocNext = math.min( readLoc + ramOutputBits, outputBytes*8 )
        ot = systolic.bitSlice( ot, 0, readLocNext-readLoc-1 )
        readLoc = readLocNext
        table.insert( outRead, ot ) 
      end

      local readRes = systolic.cast(systolic.tuple(outRead),types.bits(outputBytes*8))

      mod:addFunction( systolic.lambda("read", sinpRead, readRes, "readOut", nil, nil, J.sel(CE,S.CE("RE"),nil) ) ) 
    end

    return mod
  else
    assert(false)
  end
end

-- the rams are fundamentally limited by the # of addressable items (# of items with addresses)
-- We an always make more storage space or BW by making rams in parallel, but for now we don't increase # of addressible items
-- given constraints on BRAMs,
-- this function returns: # of addressible itmes, bit BW of BRAMS with this # of items
local function addressableItems( sizeInBytes, bwBytes )
  local addrs = sizeInBytes/bwBytes
  err( J.isPowerOf2(addrs),"bramSDP error, number of addresses must be power of 2! We don't support padding out the addressing")

  local addressable = math.max(sizeInBytes/bwBytes,math.pow(2,9)) -- bram with least # of addressable items has 512 addressable items
  err(addressable<=math.pow(2,14),"Error, bramSDP arguments have more addressable items than are supported by 1 bram (totalSize:"..tostring(sizeInBytes)..", bytes/cycle:"..tostring(bwBytes)..", addressableItems:"..tostring(addressable)..")")
  assert( J.isPowerOf2(addressable) )

  return addressable
end

local function ramBWBits( addressable )
  -- what ram has a small enough port size to support the # of addressable items we need?
  -- ram with largest port size is 32 bit port size (with 2^9 addressable items).
  -- smallest port size ram has port size 1 bit (2^14 addressable)

  local maxPossibleBWBits = 32/(addressable/math.pow(2,9)) -- can be non-integer!!
  assert( maxPossibleBWBits<=32 and maxPossibleBWBits>=1 and J.isPowerOf2(maxPossibleBWBits) )

  return maxPossibleBWBits
end

----------------
-- supports any size/bandwidth by instantiating multiple BRAMs
-- if outputBits==nil, we don't make a read function (only a write function)
--
-- The bram supports reading/writing at different bandwidths. So we specify total size to allocate (sizeInBytes),
-- and the read/write BW.
--
-- notice that we don't allow non-byte input/output BW, non-power of two sizes here. The reason is that we expose the # of address bits correctly,
-- so these need to be actual realistic values (address count must be power of 2 to make sense). Potentially, we could make a wrapper for this that
-- allows for non-power-of-2 addressing, and has more flexibility in these values.
modules.bramSDP = memoize(function( writeAndReturnOriginal, sizeInBytes, inputBytes, outputBytes, init, CE, X)
  assert(X==nil)
  err( type(sizeInBytes)=="number", "sizeInBytes must be a number")
  err( type(inputBytes)=="number", "inputBytes must be a number")
  err( outputBytes==nil or type(outputBytes)=="number", "outputBytes must be a number")
  err( outputBytes==nil or (math.floor(outputBytes)==outputBytes), "outputBytes not integral "..tostring(outputBytes))
  err( type(CE)=="boolean", "CE must be boolean")
  err( math.floor(inputBytes)==inputBytes, "bramSDP: inputBytes not integral "..tostring(inputBytes))
  err ( outputBytes==nil or inputBytes==outputBytes, "NYI: different read and write BW!")
  
  local addressable  = addressableItems( sizeInBytes, inputBytes )
  local bwBits = ramBWBits( addressable )

  local ramCount = math.ceil((inputBytes*8)/bwBits)
  
  return makeRamArray( writeAndReturnOriginal, sizeInBytes, inputBytes, outputBytes, init, CE, ramCount, bwBits, J.sel(outputBytes==nil,nil,bwBits) )
end)

function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  local l =  str:match("(.*/)")
  return l:sub(0,#l-4)
end

function readAll(file)
  local fn = script_path().."misc/"..file

  local f = io.open(fn, "rb")
  err(f~=nil, "could not open file '"..file.."'")
  local content = f:read("*all")
  f:close()
  return content
end


local function loadVerilogFile(inpType,outType,filestr)
  assert(types.isType(inpType))
  assert(types.isType(outType))

  local vstring = readAll(filestr..".v")
  local delaystring = readAll(filestr..".delay")

  local fns = {}
  local inp = S.parameter("inp",inpType)

  local outv = 0
  if outType==types.bool() then outv=false end

  local delay = tonumber(delaystring)
  local CE
  if delay>0 then CE=S.CE("ce") end
  fns.process = S.lambda("process",inp,S.cast(S.constant(outv,outType),outType),"out",nil,nil,CE)
  --print("MODULE ",filestr,"DELAY",tonumber(delaystring))
  local m = systolic.module.new(filestr,fns,{},true,nil,vstring,{process=delay})
  return m
end

modules.binop = memoize(function(op,lhsType,rhsType,outType)
  assert(type(op)=="string")
  assert(types.isType(lhsType))
  assert(types.isType(rhsType))
  assert(types.isType(outType))
  
  local str = op.."_"..string.lower(tostring(lhsType)).."_"..string.lower(tostring(rhsType)).."_"..string.lower(tostring(outType))
  return loadVerilogFile( types.tuple{lhsType,rhsType}, outType, str)
end)

modules.multiply = function(lhsType,rhsType,outType) return modules.binop("mul",lhsType,rhsType,outType) end

modules.intToFloat = loadVerilogFile(types.int(32),types.Float32,"int32_to_float")
modules.floatToInt = loadVerilogFile(types.Float32,types.int(32),"float32_to_int")
modules.floatSqrt = loadVerilogFile(types.Float32,types.Float32,"sqrt_float_float")
modules.floatInvert = loadVerilogFile(types.Float32,types.Float32,"invert_float_float")

function modules.verilatorDiv(ty)
  local fns = {}
  local inp = S.parameter("inp",types.tuple{ty,ty})

  fns.process = S.lambda("process",inp,S.cast(S.constant(0,ty),ty),"out",nil,nil,S.CE("ce"))

  local vstring=[[
module div(CLK,ce,inp,out);
  parameter INSTANCE_NAME="INST";

  input CLK;
  input ce;
  input []]..(ty:verilogBits()*2-1)..[[:0] inp;
  output []]..(ty:verilogBits()-1)..[[:0] out;

  reg []]..(ty:verilogBits()*2-1)..[[:0] inpreg;

  wire []]..(ty:verilogBits()-1)..[[:0] a;
  wire []]..(ty:verilogBits()-1)..[[:0] b;
  assign a = inpreg[]]..(ty:verilogBits()-1)..[[:0];
  assign b = inpreg[]]..(ty:verilogBits()*2-1)..":"..(ty:verilogBits())..[[];

  reg []]..(ty:verilogBits()-1)..[[:0] tmp;
  assign out = tmp;

  always @(posedge CLK) begin
    if(ce) begin
      inpreg <= inp;
//      $c(tmp,"=",a,"/(",b,"==0?1:",b,");");
      tmp <= $c(a,"/(",b,"==0?1:",b,")");
    end
  end
endmodule
]]
  
  local m = systolic.module.new("div",fns,{},true,nil,nil,vstring,{process=2})
  return m
end

-- see: http://www4.wittenberg.edu/academics/mathcomp/shelburne/comp255/notes/BinaryDivision.pdf
-- if divisor==0, this returns all 1's (??)
function modules.div(ty)
  err(types.isType(ty),"div:argument should be type")
  err(ty:isUint(),"div: argument should be uint")

  local tyDouble = types.uint(ty.precision*2)
  
  local divMod = SS.moduleConstructor("div")

  local process = divMod:addFunction(SS.lambdaConstructor( "process", types.tuple{ty,ty}, "inp" ))
  process:setCE( S.CE("ce") )
  local inp = process:getInput()
  local Qinp = S.index(inp,0)
  Qinp.name="Qinp"
  local divisor = S.index(inp,1)
  divisor.name="divisor"
  
  local QR = S.cast(Qinp,tyDouble)
  QR.name="QRinp"

  for i=1,ty.precision do
    QR = S.lshift(QR,S.constant(1,types.uint(4)))
    QR.name="QR"..tostring(i)

    -- if r >= divisor
    local Q = S.cast(S.bitSlice(QR,0,ty.precision-1),ty)
    local R = S.cast(S.bitSlice(QR,ty.precision,ty.precision*2-1),ty)
    local newQ = S.__or(Q,S.constant(1,ty))
    newQ.name="newQ"..tostring(i)
    local newR = R-divisor
    newR.name="newR"..tostring(i)
    --    local newQR = S.cast( S.tuple{newR,newQ}, tyDouble)

    local newQR = S.cast( S.tuple{S.cast(newQ,types.bits(ty.precision)),S.cast(newR,types.bits(ty.precision))}, types.bits(ty.precision*2))
    newQR = S.cast(newQR, tyDouble)
    newQR.name="newQR"..tostring(i)
    
    QR = S.select( S.ge(R,divisor), newQR, QR)
    QR.name="QRout"..tostring(i)
  end

  local out = S.bitSlice(QR,0,ty.precision-1)
  process:setOutput(out,"out")

  divMod:complete()

  return divMod
end

modules.regBy = memoize(function( ty, setby_orig, CE, init, resetValue, hasSet, X)
  err( types.isType(ty), "systolic.module.regBy, type must be type" )

  local setby, setbyName
  if Ssugar.isModuleConstructor(setby_orig) then
    setby = setby_orig:complete()
    setbyName = "MODULECONSTRUCT_"..setby.name
  else
    setby = setby_orig
    setbyName = setby.name
  end
  
  assert( systolic.isModule(setby) )
  assert( setby:getDelay( "process" ) == 0 )
  assert( setby.functions.process:isPure() )
  assert( CE==nil or type(CE)=="boolean" )
  if init~=nil then ty:checkLuaValue(init) end
  if resetValue~=nil then ty:checkLuaValue(resetValue) end
  if hasSet==nil then hasSet=false end
  err( type(hasSet)=="boolean", "systolic.module.regBy: hasSet must be boolean but is "..tostring(hasSet))
  assert(X==nil)

  local R = systolic.module.reg( ty, CE, init, nil, resetValue ):instantiate("R")
  local inner = setby:instantiate("regby_inner")
  local fns = {}
  fns.get = systolic.lambda("get", systolic.parameter("getinp",types.null()), R:get(), "GET_OUTPUT" )

  -- check setby type
  --err(#setby.functions==1, "regBy setby module should only have process function")
  assert(setby.functions.process:isPure())
  local setbytype = setby:lookupFunction("process"):getInput().type
  assert(setbytype:isTuple())
  local setbyTypeA = setbytype.list[1]
  local setbyTypeB = setbytype.list[2]
  err( setbyTypeA==ty, "regby type does not match type on setby function" )

  local CEVar
  if CE then CEVar = systolic.CE("CE") end

  -- if we include the set function, and both set and setBy are called in the same cycle, set gets prescedence
  local sinp, setvalid
  if hasSet then
    sinp = systolic.parameter("set_inp",ty)
    setvalid = systolic.parameter("set_valid",types.bool())
    fns.set = systolic.lambda("set", sinp, nil, "SET_OUTPUT",{}, setvalid, CEVar )
  end

  local sbinp = systolic.parameter("setby_inp",setbyTypeB)
  local setbyvalidparam = systolic.parameter("setby_valid",types.bool())
  local setbyvalid = setbyvalidparam
  local setbyout = inner:process(systolic.tuple{R:get(),sbinp},systolic.null())

  if hasSet then
    setbyvalid = systolic.__or(setbyvalid,setvalid)
    setbyout = systolic.select(setvalid,sinp,setbyout)
  end

  fns.setBy = systolic.lambda("setby", sbinp, setbyout, "SETBY_OUTPUT",{R:set(setbyout,setbyvalid,CEVar)}, setbyvalidparam, CEVar )

  if resetValue~=nil then
    local resetvalid = systolic.parameter("reset_valid",types.bool())
    fns.reset = systolic.lambda("reset", systolic.parameter("reset_input",types.null()), R:reset(nil,resetvalid), "RESET_OUTPUT",{}, resetvalid )
  end

  local name = J.sanitize("RegBy_"..tostring(ty).."_"..setbyName.."_CE"..tostring(CE).."_init"..tostring(init).."_reset"..tostring(resetValue).."_hasSet"..tostring(hasSet))
    
  local M = systolic.module.new( name, fns, {R,inner}, true, nil,nil,{get=0,reset=0,setBy=0,set=0} )
  assert(systolic.isModule(M))

  return M
end)

return modules
