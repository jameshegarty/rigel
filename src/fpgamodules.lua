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
  
  --assert(type(limit)=="number")
  local limit = Uniform(limit_orig)
  assert(X==nil)

  local name = J.sanitize("sumwrap_"..tostring(ty).."_to"..tostring(limit_orig))
  
  local swinp = S.parameter("process_input", types.tuple{ty,ty})
  local ot = S.select(S.eq(S.index(swinp,0),limit:toSystolic(ty)),
                      S.constant(0,ty),
                      S.index(swinp,0)+S.index(swinp,1)):disablePipelining()
  return S.module.new( name, {process=S.lambda("process",swinp,ot,"process_output",nil,nil,S.CE("CE"))},{})
end)

-- {uint16,bool}->uint16. Increment by inc if the bool is true s.t. output <= limit
modules.incIf=memoize(function(inc,ty,hasCE)
  if inc==nil then inc=1 end
  if ty==nil then ty=types.uint(16) end
  if hasCE==nil then hasCE=true end
  assert(type(hasCE)=="boolean")

  local swinp = S.parameter("process_input", types.tuple{ty,types.bool()})
  
  local ot = S.select( S.index(swinp,1), S.index(swinp,0)+S.constant(inc,ty), S.index(swinp,0) ):disablePipelining()
  local CE = S.CE("CE")
  if hasCE==false then CE=nil end
  return S.module.new( J.sanitize("incif_"..inc..tostring(ty).."_CE"..tostring(CE)), {process=S.lambda("process",swinp,ot,"process_output",nil,nil,CE)},{})
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
modules.incIfWrap=memoize(function( ty, limit_orig, inc, X )
  err(types.isType(ty), "incIfWrap: type must be rigel type")
  local limit = Uniform(limit_orig)
  err( X==nil, "incIfWrap: too many arguments" )
  
  local incv = inc or 1
  local swinp = S.parameter("process_input", types.tuple{ty, types.bool()})
  
  local nextValue = S.select( S.eq(S.index(swinp,0), limit:toSystolic(ty) ), S.constant(0,ty), S.index(swinp,0)+S.constant(incv,ty) )
  local ot = S.select( S.index(swinp,1), nextValue, S.index(swinp,0) ):disablePipelining()
  return S.module.new( J.sanitize("incif_wrap"..tostring(ty).."_"..tostring(limit_orig).."_inc"..tostring(inc)), {process=S.lambda("process",swinp,ot,"process_output",nil,nil,S.CE("CE"))},{})
end)


------------
local swinp = S.parameter("process_input", types.tuple{types.uint(16),types.uint(16)})
modules.sum = S.module.new( "summodule", {process=S.lambda("process",swinp,(S.index(swinp,0)+S.index(swinp,1)):disablePipelining(),"process_output")},{})
------------
modules.max = memoize(function(ty,hasCE)
  local swinp = S.parameter("process_input", types.tuple{ty,ty})
  local CE = S.CE("CE")
  if hasCE==false then CE=nil end
  return S.module.new( "maxmodule", {process=S.lambda("process",swinp,S.select(S.gt(S.index(swinp,0),S.index(swinp,1)),S.index(swinp,0),S.index(swinp,1)):disablePipelining(),"process_output",nil,nil,CE)},{})
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
local sliceRamCache = {}
local function sliceRamGen(bits)

    if bits==1 then
return systolic.module.ram128()
  end

  if sliceRamCache[bits]~=nil then
return sliceRamCache[bits]
  end

  err( bits%2==0, "NYI - sliceRamGen with non-power of 2 number of bits "..tostring(bits))
  
  local m = sliceRamGen(bits/2)

  local ram = Ssugar.moduleConstructor( J.sanitize("sliceRamGen_"..tostring(bits)) )
  local ai, bi = ram:add(m:instantiate("a")), ram:add(m:instantiate("b"))

  local readFn = ram:addFunction( Ssugar.lambdaConstructor("read",types.uint(7),"readAddr") )
  readFn:setCE(S.CE("RE"))
  readFn:setOutput( S.cast(S.tuple{ai:read(readFn:getInput()),bi:read(readFn:getInput())},types.bits(bits)),"readOut")

  local writeFn = ram:addFunction( Ssugar.lambdaConstructor("write",types.tuple{types.uint(7),types.bits(bits)},"readAddrDat") )
  writeFn:setCE(S.CE("WE"))
  local lowbits = S.bitSlice(S.index(writeFn:getInput(),1),0,bits/2-1)
  local highbits = S.bitSlice(S.index(writeFn:getInput(),1),bits/2,bits-1)
  local addr = S.index(writeFn:getInput(),0)
  writeFn:addPipeline( ai:write(S.tuple{addr,lowbits}) )
  writeFn:addPipeline( bi:write(S.tuple{addr,highbits}) )

  sliceRamCache[bits] = ram
  return ram
end

modules.fifo = memoize(function(ty,items,verbose,nostall)
  err(types.isType(ty),"fifo type must be type")
  err(type(items)=="number","fifo items must be number")
  err(type(verbose)=="boolean","fifo verbose must be bool")
  err( items>1,"fifo: items must be >1")
  
  local fifo = Ssugar.moduleConstructor( J.sanitize("fifo_"..tostring(ty).."_"..items.."_nostall"..tostring(nostall)) )
  -- writeAddr, readAddr hold the address we will read/write from NEXT time we do a read/write
  local addrBits = (math.ceil(math.log(items)/math.log(2)))+1 -- the +1 is so that we can disambiguate wraparoudn
  local writeAddr = fifo:add( systolic.module.regBy( types.uint(addrBits), modules.incIfWrap(types.uint(addrBits),items-1), true,nil,0 ):instantiate("writeAddr"))
  local readAddr = fifo:add( systolic.module.regBy( types.uint(addrBits), modules.incIfWrap(types.uint(addrBits),items-1), true,nil,0 ):instantiate("readAddr"))
  local bits = ty:verilogBits()
  local bytes = bits/8
  bytes = math.ceil(bytes) -- bits may not be byte aligned
  
  local ram, rams
  if items <= 128 and J.isPowerOf2(bits) then
    ram = fifo:add( sliceRamGen(bits):instantiate("ram") )
  elseif items <= 128 then
    rams = J.map( J.range( bits ), function(v) return fifo:add(systolic.module.ram128():instantiate("fifo"..v)) end )
  else
    ram = fifo:add(modules.bramSDP(true,items*bytes,bytes,bytes,nil,true):instantiate("ram"))
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

modules.fifonoop = memoize(function(ty)
  assert(types.isType(ty))

  local fifo = Ssugar.moduleConstructor(J.sanitize("fifonoop_"..tostring(ty))):onlyWire(true)

  local internalData = systolic.parameter("store_input",types.tuple{ty,types.bool()})
  local internalReady = systolic.parameter("load_ready_downstream",types.bool())

  -- pushBack
  local pushBack = fifo:addFunction( systolic.lambda("store",internalData,nil,"store_input",{} ) )
  local pushBack_ready = fifo:addFunction( systolic.lambda("store_ready",S.parameter("SRNIL",types.null()),internalReady,"store_ready",{} ) )

  -- popFront
  local popFront = fifo:addFunction( S.lambda("load",S.parameter("pfnil",types.null()),internalData,"load_output") )
  local popFront_ready = fifo:addFunction( S.lambda("load_ready",internalReady,nil,"load_ready") )

  -- size
--  local sizeFn = fifo:addFunction( S.lambda("size",S.parameter("sznil",types.null()),S.constant(0,types.uint(16)),"size",{}) )

  -- ready
--  local readyFn = fifo:addFunction( S.lambda("ready",S.parameter("rnil",types.null()),internalReady,"readyv") )

  -- has data
--  local hasDataFn = fifo:addFunction( S.lambda("hasData",S.parameter("hdnil",types.null()),internalValid,"hasData") )

  -- pushBackReset
  local pushBackReset = fifo:addFunction( Ssugar.lambdaConstructor("store_reset" ) )

  -- popFrontReset
  local popFrontReset = fifo:addFunction( Ssugar.lambdaConstructor("load_reset" ) )

  return fifo
                           end)
--modules.fifo = memoize(modules.fifonoop)

-- tab should be a key of systolic values. Key is a systolic value that chooses between them.
-- key is 0 indexed
function modules.wideMux( tab, key )
  assert(#tab>0)
  local packed = J.map(tab, function(t,i) return S.tuple{t,S.eq(key,S.constant(i-1,types.uint(16)))} end )
  local r = J.foldt( packed, function(a,b) return S.select(S.index(a,1),a,b) end )
  return S.index(r,0)
end

modules.shiftRegister = memoize(function( ty, size, resetValue, CE, X )
  assert(X==nil)
  if resetValue~=nil then ty:checkLuaValue(resetValue) end
  err( type(CE)=="boolean", "CE option must be bool")

  local M = Ssugar.moduleConstructor( "ShiftRegister_"..size.."_CE"..tostring(CE).."_TY"..ty:verilogBits() )
  local pipelines = {}
  local resetPipelines = {}
  local out
  local inp = systolic.parameter("sr_input", ty)
  local regs = {}

  local ppvalid = systolic.parameter("pushPop_valid",types.bool())
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
  local pushPop = M:addFunction( systolic.lambda("pushPop", inp, out, "pushPop_out", pipelines, ppvalid, CEvar ) )
  local reset = M:addFunction( systolic.lambda("reset", systolic.parameter("R",types.null()), nil, "reset_out", resetPipelines, rstvalid ) )

  return M
                                end)

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
    pipelines = J.map( regs, function(r,i) return r:set( S.select(reading, exprs[i], regs[((i-1+stride)%#exprs)+1]:get()):disablePipeliningSingle() ) end )
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
    sizeInBytes,
    inputBytes,
    outputBytes,
    init,
    CE,

    ramCount, -- # of rams to make. Can be <1 (means make 1, but underutilize it)
    ramInputBits, -- input BW of each ram
    ramOutputBits, -- output BW of each ram
    X)


  assert( ramInputBits>=1 and ramInputBits<=32 ) -- don't have rams outside this range
  assert( ramInputBits*math.max(ramCount,1) == inputBytes*8 )

  local ramInputAddrBits = math.log((2048*8)/ramInputBits)/math.log(2)

  local ramOutputAddrBits
  if outputBytes~=nil then
    assert( ramOutputBits>=1 and ramOutputBits<=32 )
    assert( ramOutputBits*math.max(ramCount,1)==outputBytes*8 )
    ramOutputAddrBits = math.log( (2048*8)/ramOutputBits)/math.log(2)
  end

  local inputAddrBits = math.log(sizeInBytes/inputBytes)/math.log(2)
  local outputAddrBits
  if outputBytes~=nil then outputAddrBits = math.log(sizeInBytes/outputBytes)/math.log(2) end

  if init~=nil then
    err( ramCount <= 1, "NYI - inits with striped ram array" )
    err( ramInputBits==inputBytes*8, "NYI - inits with striped ram array"  )
    if outputBytes~=nil then err( ramOutputBits==outputBytes*8, "NYI - inits with striped ram array"  ) end
    err( #init==sizeInBytes, "init field has size "..(#init).." but should have size "..sizeInBytes )
    while #init < 2048 do
      table.insert(init,0)
    end
  end

  if writeAndReturnOriginal then
    local name = J.sanitize("bramSDP_WARO"..tostring(writeAndReturnOriginal).."_size"..sizeInBytes.."_bw"..inputBytes.."_obw"..tostring(outputBytes).."_CE"..tostring(CE).."_init"..tostring(init))
    local mod = Ssugar.moduleConstructor( name )
    
    ------------------ WRITE PORT
    local sinp = systolic.parameter("inp",types.tuple{types.uint(inputAddrBits),types.bits(inputBytes*8)})
    local inpAddr = systolic.index(sinp,0)
    local inpData = systolic.index(sinp,1)

    local inpAddrPadded = inpAddr
    if ramInputAddrBits>inputAddrBits then
      -- ram supplies more addressible items than we require, so pad it out
      inpAddrPadded = systolic.cast( inpAddrPadded, types.uint( ramInputAddrBits ) )
    end

    local out = {}
    local rams = {}
    for ram=0,math.max(1,ramCount)-1 do
      rams[ram] =  mod:add( systolic.module.bram2KSDP( writeAndReturnOriginal, ramInputBits, ramOutputBits, CE, init ):instantiate("bram_"..ram) )
      local inp

      if ramInputBits==inputBytes*8 then
        inp = inpData
      elseif ramInputBits>inputBytes*8 then
        -- pad it out
        inp = systolic.cast( inpData, types.bits(ramInputBits) )
      else
        inp = systolic.bitSlice( inpData, ram*ramInputBits, (ram+1)*ramInputBits-1 )
      end

      
      table.insert( out, rams[ram]:writeAndReturnOriginal( systolic.tuple{inpAddrPadded,inp} ) )
    end

    local res
    if ramInputBits>inputBytes*8 then
      assert(ramCount<1)
      res = systolic.bitSlice( out[1], 0, inputBytes*8-1 )
    else
      res = systolic.cast(systolic.tuple(out),types.bits(inputBytes*8))
    end
    
    mod:addFunction( systolic.lambda("writeAndReturnOriginal", sinp, res, "WARO_OUT", nil, nil, J.sel(CE,S.CE("writeAndReturnOriginal_CE"),nil)) )

    ----------- READ PORT
    if outputBytes~=nil then
      local sinpRead = systolic.parameter("inpRead",types.uint(outputAddrBits))

      local outAddrPadded = sinpRead
      if ramOutputAddrBits>outputAddrBits then
        outAddrPadded = systolic.cast( outAddrPadded, types.uint(ramOutputAddrBits) )
      end

      local outRead = {}
      for ram=0,math.max(1,ramCount)-1 do
        table.insert( outRead, rams[ram]:read(outAddrPadded) ) 
      end

      local readRes
      if ramOutputBits>outputBytes*8 then
        assert(ramCount<1)
        readRes = systolic.bitSlice( outRead[1], 0, outputBytes*8-1 )
      else
        readRes = systolic.cast(systolic.tuple(outRead),types.bits(outputBytes*8))
      end

      mod:addFunction( systolic.lambda("read", sinpRead, readRes, "READ_OUT", nil, nil, J.sel(CE,S.CE("read_CE"),nil) ) ) 
    end

    return mod
  else
    assert(false)
  end
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

  -- non power of 2 sizes are actually ok: the number of addressable items just needs to be power of 2
  --err( isPowerOf2(sizeInBytes), "Size in Bytes must be power of 2, but is "..sizeInBytes)
  err( type(CE)=="boolean", "CE must be boolean")

  err( math.floor(inputBytes)==inputBytes, "bramSDP: inputBytes not integral "..tostring(inputBytes))
  
  --err( isPowerOf2(inputBytes), "inputBytes is not power of 2")
  local writeAddrs = sizeInBytes/inputBytes
  err( J.isPowerOf2(writeAddrs), "writeAddress count isn't a power of 2 (size="..sizeInBytes..",inputBytes="..inputBytes..",writeAddrs="..writeAddrs..")")

  if outputBytes~=nil then
    err( math.floor(outputBytes)==outputBytes, "outputBytes not integral "..tostring(outputBytes))
    local readAddrs = sizeInBytes/outputBytes
    err( J.isPowerOf2(readAddrs), "readAddress count isn't a power of 2")
  end
  
  -- the idea here is that we want to pack the data into the smallest # of brams possible.
  -- we are limited by (a) the number of addressable items, and (b) the bw of each bram.
  -- if we have more than 2048 addressable items, we can't pack into brams (would need additional multiplexers)
  local minbw = inputBytes
  if outputBytes~=nil then minbw = math.min(inputBytes, outputBytes) end
  local maxbw = inputBytes
  if outputBytes~=nil then maxbw = math.max(inputBytes, outputBytes) end

  local addressable = math.max(sizeInBytes/minbw,math.pow(2,9)) -- bram with least # of addressable items has 512 addressable items
  err(addressable<=math.pow(2,14),"Error, bramSDP arguments have more addressable items than are supported by 1 bram (totalSize:"..tostring(sizeInBytes)..", inputBytes/cycle:"..tostring(inputBytes)..", outputBytes/cycle:"..tostring(outputBytes)..", addressableItems:"..tostring(addressable)..")")

  -- find the # brams if we're bw limited, or address limited

  -- what ram has a small enough port size to support the # of addressable items we need?
  -- ram with largest port size is 32 bit port size (with 2^9 addressable items).
  -- smallest port size ram has port size 1 bit (2^14 addressable)
  local maxPossibleBWBits = 32/(addressable/math.pow(2,9))
  assert(maxPossibleBWBits<=32 and maxPossibleBWBits>=1)
  local maxPossibleBWBytes = maxPossibleBWBits/8 -- can be non-integer!!
  local ramCount = maxbw/maxPossibleBWBytes
  
  --print(ramCount,"BRAMS needed","maxPossibleBWBits",maxPossibleBWBits,"addressable",addressable,"sizeInBytes",sizeInBytes,"inputBytes",inputBytes,"outputBytes",outputBytes)

  -- it's ok to require <1 bram (like half a bram)
  err( ramCount==math.floor(ramCount) or ramCount < 1, "non-integer number of BRAMS needed?")

  -- number of input bits of the actual bram we chose
  -- if ram BW is more than we need, prefer to have the input/output port match real port size (# allocate too many addressible items).
  -- ... this make it easier to deal with init values
  local ramInputBits = math.min((inputBytes*8)/ramCount,inputBytes*8)

  local ramOutputBits, ramOutputAddrBits
  if outputBytes~=nil then
    ramOutputBits = math.min((outputBytes*8)/ramCount,outputBytes*8)
  end

  return makeRamArray( writeAndReturnOriginal, sizeInBytes, inputBytes, outputBytes, init, CE, ramCount, ramInputBits, ramOutputBits )
end)

function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  local l =  str:match("(.*/)")
  return l:sub(0,#l-4)
end

function readAll(file)
  local fn = script_path().."misc/"..file
  --print("LOAD FILE "..fn)
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
  fns.process = S.lambda("process",inp,S.cast(S.constant(outv,outType),outType),"out",nil,nil,S.CE("ce"))
  --print("MODULE ",filestr,"DELAY",tonumber(delaystring))
  local m = systolic.module.new(filestr,fns,{},true,nil,vstring,{process=tonumber(delaystring)})
  return m
end

modules.binop = memoize(function(op,lhsType,rhsType,outType)
  assert(type(op)=="string")
  assert(types.isType(lhsType))
  assert(types.isType(rhsType))
  assert(types.isType(outType))
  
  local str = op.."_"..tostring(lhsType).."_"..tostring(rhsType).."_"..tostring(outType)
  return loadVerilogFile( types.tuple{lhsType,rhsType}, outType, str)
end)

modules.multiply = function(lhsType,rhsType,outType) return modules.binop("mul",lhsType,rhsType,outType) end

modules.intToFloat = loadVerilogFile(types.int(32),types.float(32),"int32_to_float")
modules.floatToInt = loadVerilogFile(types.float(32),types.int(32),"float32_to_int")
modules.floatSqrt = loadVerilogFile(types.float(32),types.float(32),"sqrt_float_float")
modules.floatInvert = loadVerilogFile(types.float(32),types.float(32),"invert_float_float")

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

return modules
