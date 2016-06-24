local systolic = require("systolic")
local Ssugar = require("systolicsugar")
local types = require("types")

local S=systolic
--statemachine = require("statemachine")
local modules = {}

-- calculate A+B s.t. A+B <= limit
modules.sumwrap = memoize(function( ty, limit, X)
                            assert(types.isType(ty))
  assert(type(limit)=="number")
  assert(X==nil)

  local swinp = S.parameter("process_input", types.tuple{ty,ty})
  local ot = S.select(S.eq(S.index(swinp,0),S.constant(limit,ty)),
                      S.constant(0,ty),
                      S.index(swinp,0)+S.index(swinp,1)):disablePipelining()
  return S.module.new( "sumwrap_"..tostring(ty).."_to"..limit, {process=S.lambda("process",swinp,ot,"process_output",nil,nil,S.CE("CE"))},{},nil,true)
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
      return S.module.new( "incif_"..inc..tostring(ty).."_CE"..tostring(CE), {process=S.lambda("process",swinp,ot,"process_output",nil,nil,CE)},{},nil,true)
              end)

-- this will never wrap around
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
      return S.module.new( "incifnowrap_"..inc..tostring(ty), {process=S.lambda("process",swinp,ot,"process_output",nil,nil,S.CE("CE"))},{},nil,true)
              end)

-- we generally want to use incIf if we are going to increment a variable based on some (calculated) condition.
-- The reason for this is if we module the valid bit based on the condition, the valid bit may go into a undefined state.
-- (ie at init time the condition will be unstable garbage or X's). This allows us to not mess with the valid bit,
-- but still conditionally increment.
modules.incIfWrap=memoize(function(ty,limit,inc)
                            assert(types.isType(ty))
                        assert(type(limit)=="number")
                        err(limit<math.pow(2,ty:verilogBits()), "limit out of bounds!")
                        local incv = inc or 1
      local swinp = S.parameter("process_input", types.tuple{ty, types.bool()})

      local nextValue = S.select( S.eq(S.index(swinp,0), S.constant(limit,ty)), S.constant(0,ty), S.index(swinp,0)+S.constant(incv,ty) )
      local ot = S.select( S.index(swinp,1), nextValue, S.index(swinp,0) ):disablePipelining()
      return S.module.new( "incif_wrap"..tostring(ty).."_"..limit.."_inc"..tostring(inc), {process=S.lambda("process",swinp,ot,"process_output",nil,nil,S.CE("CE"))},{},nil,true)
              end)


------------
local swinp = S.parameter("process_input", types.tuple{types.uint(16),types.uint(16)})
modules.sum = S.module.new( "summodule", {process=S.lambda("process",swinp,(S.index(swinp,0)+S.index(swinp,1)):disablePipelining(),"process_output")},{},nil,true)
------------
modules.max = memoize(function(ty,hasCE)
                        local swinp = S.parameter("process_input", types.tuple{ty,ty})
                        local CE = S.CE("CE")
                        if hasCE==false then CE=nil end
                        return S.module.new( "maxmodule", {process=S.lambda("process",swinp,S.select(S.gt(S.index(swinp,0),S.index(swinp,1)),S.index(swinp,0),S.index(swinp,1)):disablePipelining(),"process_output",nil,nil,CE)},{},nil,true)
                      end)
------------
local swinp = S.parameter("process_input", types.tuple{types.bool(),types.bool()})
modules.__and = S.module.new( "andmodule", {process=S.lambda("process",swinp,S.__and(S.index(swinp,0),S.index(swinp,1)),"process_output")},{},nil,true)
------------
local swinp = S.parameter("process_input", types.tuple{types.bool(),types.bool()})
modules.__andSingleCycle = S.module.new( "andmoduleSingleCycle", {process=S.lambda("process",swinp,S.__and(S.index(swinp,0),S.index(swinp,1)):disablePipelining(),"process_output")},{},nil,true)
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

local terra bitselect(a : uint, bit : uint)
  return a and bit
end

-- make an array of ram128s to service a certain bandwidth
modules.ram128 = function(ty, init)
  assert(types.isType(ty))
  local ram128 = Ssugar.moduleConstructor("ram128_"..sanitize(tostring(ty)) )
  local bits = ty:verilogBits()
  
  assert(type(init)=="table")
  local slicedInit = {}
  for b=1,bits do
    slicedInit[b] = {}
    for i=1,#init do
      slicedInit[b][i] = (bitselect(init[i],math.pow(2,b-1))~=0)
    end
  end

  local rams = map( range( bits ), function(v) return ram128:add(systolic.module.ram128(false,true,slicedInit[v]):instantiate("ram"..v)) end )

  local read = ram128:addFunction( Ssugar.lambdaConstructor("read",types.uint(8),"read_input") )
--  pushBackReset:setCE(pushCE)

  local bitfield = map( range(bits), function(b) return rams[b]:read( S.cast( read:getInput(), types.uint(7)) ) end)
  read:setOutput( systolic.cast( S.tuple(bitfield), ty), "read_output" )

  return ram128
end

modules.fifo = memoize(function(ty,items,verbose)
  assert(types.isType(ty))
  assert(type(items)=="number")
  assert(type(verbose)=="boolean")

  local fifo = Ssugar.moduleConstructor("fifo_"..sanitize(tostring(ty).."_"..items) )
  -- writeAddr, readAddr hold the address we will read/write from NEXT time we do a read/write
  local addrBits = (math.log(items)/math.log(2))+1 -- the +1 is so that we can disambiguate wraparoudn
  local writeAddr = fifo:add( systolic.module.regBy( types.uint(addrBits), modules.incIfWrap(types.uint(addrBits),items-1), true ):instantiate("writeAddr"))
  local readAddr = fifo:add( systolic.module.regBy( types.uint(addrBits), modules.incIfWrap(types.uint(addrBits),items-1), true ):instantiate("readAddr"))
  local bits = ty:verilogBits()
  local bytes = bits/8

  local rams, ram
  if items <= 128 then
    assert(items==128)
    rams = map( range( bits ), function(v) return fifo:add(systolic.module.ram128():instantiate("fifo"..v)) end )
  else
    print("FIFO BRAMS",ty,"bytes",bytes,"items",items)
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
--  local hasData = S.gt(fsize,S.constant(16,types.uint(addrBits))):disablePipelining()
--  local hasData = S.gt( modules.modSub(writeAddr:get(),readAddr:get(), 128 ), S.constant(1,types.uint(8)) ):disablePipelining()
  hasDataFn:setOutput( hasData, "hasData" )


  -- pushBack
  local pushCE = S.CE("CE_push")
  local pushBack = fifo:addFunction( Ssugar.lambdaConstructor("pushBack",ty,"pushBack_input" ) )
  pushBack:setCE(pushCE)
  local pushBackAssert = fifo:add( systolic.module.assert( "attempting to push to a full fifo", true ):instantiate("pushBackAssert") )
  local hasSpace = S.lt( fsize, S.constant(items-2,types.uint(addrBits)) ):disablePipelining() -- note that this is different than ready
  pushBack:addPipeline( pushBackAssert:process( hasSpace )  )
  pushBack:addPipeline( writeAddr:setBy(systolic.constant(true, types.bool()) ) )

  if items<=128 then
    for b=1,bits do
      pushBack:addPipeline( rams[b]:write( S.tuple{ S.cast(writeAddr:get(),types.uint(7)), S.bitSlice(pushBack:getInput(),b-1,b-1)} )  )
    end
  else
    pushBack:addPipeline( ram:writeAndReturnOriginal( S.tuple{ S.cast(writeAddr:get(),types.uint(addrBits-1)), S.cast(pushBack:getInput(),types.bits(bits))} )  )
  end

  -- pushBackReset
  local pushBackReset = fifo:addFunction( Ssugar.lambdaConstructor("pushBackReset" ) )
  pushBackReset:setCE(pushCE)
  pushBackReset:addPipeline( writeAddr:set(systolic.constant(0,types.uint(addrBits))))

  -- popFront
  local popCE = S.CE("CE_pop")
  local popFront = fifo:addFunction( Ssugar.lambdaConstructor("popFront") )
  popFront:setCE(popCE)
  local popFrontAssert = fifo:add( systolic.module.assert( "attempting to pop from an empty fifo", true ):instantiate("popFrontAssert") )
  popFront:addPipeline( popFrontAssert:process( hasData ) )
  local popFrontPrint
  if verbose then 
    popFrontPrint= fifo:add( systolic.module.print( types.tuple{types.uint(addrBits),types.uint(addrBits),types.uint(addrBits)},"FIFO readaddr %d writeaddr %d size %d", true):instantiate("popFrontPrintInst") ) 
    popFront:addPipeline( popFrontPrint:process( S.tuple{readAddr:get(), writeAddr:get(), fsize} ) )
  end
  popFront:addPipeline( readAddr:setBy( S.constant(true, types.bool() ) ) )

  if items<=128 then
    local bitfield = map( range(bits), function(b) return rams[b]:read( S.cast( readAddr:get(), types.uint(7)) ) end)
    popFront:setOutput( systolic.cast( S.tuple(bitfield), ty), "popFront" )
  else
    popFront:setOutput( S.cast(ram:read(S.cast(readAddr:get(),types.uint(addrBits-1))),ty), "popFront" )
  end

  -- popFrontReset
  local popFrontReset = fifo:addFunction( Ssugar.lambdaConstructor("popFrontReset" ) )
  popFrontReset:setCE(popCE)
  popFrontReset:addPipeline( readAddr:set(systolic.constant(0,types.uint(addrBits))))

  return fifo
                          end)


modules.fifo128 = memoize(function(ty,verbose) return modules.fifo(ty,128,verbose) end)

modules.fifonoop = memoize(function(ty)
  assert(types.isType(ty))

  local fifo = Ssugar.moduleConstructor("fifonoop_"..sanitize(tostring(ty))):onlyWire(true)

  local internalData = systolic.parameter("store_input",types.tuple{ty,types.bool()})
  local internalReady = systolic.parameter("load_ready_downstream",types.bool())

  -- pushBack
  local pushBack = fifo:addFunction( systolic.lambda("store",internalData,nil,"store_input",{} ) )
  local pushBack_ready = fifo:addFunction( systolic.lambda("store_ready",S.parameter("SRNIL",types.bool()),internalReady,"store_ready",{} ) )

  -- popFront
  local popFront = fifo:addFunction( S.lambda("load",S.parameter("pfnil",types.tuple{types.null(),types.bool()}),internalData,"load_output") )
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
  local packed = map(tab, function(t,i) return S.tuple{t,S.eq(key,S.constant(i-1,types.uint(16)))} end )
  local r = foldt( packed, function(a,b) return S.select(S.index(a,1),a,b) end )
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
    local I = M:add( systolic.module.reg( ty, CE ):instantiate("SR"..i):setArbitrate("valid") )
    table.insert( regs, I )
    if i==1 then
      table.insert(pipelines, I:set(inp) )
    else
      table.insert(pipelines, I:set(regs[i-1]:get()) )
    end
    table.insert( resetPipelines, I:set( systolic.constant( resetValue, ty ) ) )
    if i==size then out=I:get() end
  end
  if size==0 then out=inp end

  local CEvar = sel(CE,S.CE("CE"),nil)
  local pushPop = M:addFunction( systolic.lambda("pushPop", inp, out, "pushPop_out", pipelines, ppvalid, CEvar ) )
  local reset = M:addFunction( systolic.lambda("reset", systolic.parameter("R",types.null()), nil, "reset_out", resetPipelines, rstvalid, CEvar) )

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
  local internalized = map(exprs, function(e) local node, totalDelay = e:internalizeDelays(); return {node=node:CSE(CSErepo), delay=totalDelay} end)

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
  assert( S.isModule(module) )
  assert(type(exprs)=="table")
  assert(#exprs>0)
  assert(#exprs==keycount(exprs))
  map( exprs, function(e) assert(S.isAST(e)) end )
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

  map(exprs, function(e) assert(ty==nil or e.type==ty); ty=e.type; end )

  local allconst = foldl( andop, true, map(exprs, function(e) return e:const()~=nil end ) )

  if allconst and period*stride==#exprs then
    -- period*stride==#exprs => we will get back to initial condition after 'period' cycles
    local regs = map(exprs, function(e,i) return module:add( Ssugar.regConstructor(ty):CE(true):setInit(e:const()):instantiate("SR_"..i) ) end )

    pipelines = map( regs, function(r,i) return r:set( regs[((i-1+stride)%#exprs)+1]:get() )  end )
    out = map( regs, function(r) return r:get() end )
  else
    local phase = module:add( Ssugar.regByConstructor( types.uint(16), modules.sumwrap(types.uint(16),period-1) ):CE(true):instantiate("phase") )

    resetPipelines = {phase:set( S.constant(0,types.uint(16)) )}
    reading = S.eq(phase:get(),S.constant(0,types.uint(16))):disablePipelining():setName("reading")

    local regs = map(exprs, function(e,i) return module:add( Ssugar.regConstructor(ty):CE(true):instantiate("SR_"..i) ) end )

    exprs = optimizeShifter( exprs, regs, stride, period )

    -- notice that in the first cycle we write exprs[1] to regs[1].
    -- Since we bypass exprs[1] to the output on the first cycle, this means we actually always read out of reg[2]
    -- it's possible we may not even use regs[1]. This is just if we end up CSEing (optimizeShifter)
    --
    -- disable pipeling on the select to make sure all the reads/write happen in same cycle (or else we will create timing cycle)
    pipelines = map( regs, function(r,i) return r:set( S.select(reading, exprs[i], regs[((i-1+stride)%#exprs)+1]:get()):disablePipeliningSingle() ) end )
    table.insert( pipelines, phase:setBy( S.constant(1, types.uint(16) ) ) )

    --out = S.select( reading, exprs[1], regs[2]:get() )
    out = map( exprs, function(expr,i) return S.select( reading, expr, regs[((i-1+stride)%#exprs)+1]:get() ) end )

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
  local A = "A"
  local B = "B"
  if conf.A.chunk>conf.B.chunk then A,B=B,A end
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

  table.insert(res,"RAMB16_S"..(conf[A].chunk*9).."_S"..(conf[B].chunk*9).." #("..table.concat(configParams,",")..") "..conf.name.." (\n")
    table.insert(res,".DIPA("..(conf[A].chunk).."'b0),\n")
    table.insert(res,".DIPB("..(conf[B].chunk).."'b0),\n")
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

  err( math.floor(inputBytes)==inputBytes, "inputBytes not integral "..tostring(inputBytes))
  
  --err( isPowerOf2(inputBytes), "inputBytes is not power of 2")
  local writeAddrs = sizeInBytes/inputBytes
  err( isPowerOf2(writeAddrs), "writeAddress count isn't a power of 2 (size="..sizeInBytes..",inputBytes="..inputBytes..",writeAddrs="..writeAddrs..")")

  if outputBytes~=nil then
    err( math.floor(outputBytes)==outputBytes, "outputBytes not integral "..tostring(outputBytes))
    local readAddrs = sizeInBytes/outputBytes
    err( isPowerOf2(readAddrs), "readAddress count isn't a power of 2")
  end
  
  -- the idea here is that we want to pack the data into the smallest # of brams possible.
  -- we are limited by (a) the number of addressable items, and (b) the bw of each bram.
  -- if we have more than 2048 addressable items, we can't pack into brams (would need additional multiplexers)
  local minbw = inputBytes
  if outputBytes~=nil then minbw = math.min(inputBytes, outputBytes) end
  local maxbw = inputBytes
  if outputBytes~=nil then maxbw = math.max(inputBytes, outputBytes) end
  local addressable = sizeInBytes/minbw

  err(addressable<=2048,"Error, bramSDP arguments have more addressable items than are supported by 1 bram (size:"..tostring(sizeInBytes)..", inputBytes:"..tostring(inputBytes)..")")

  -- find the # brams if we're bw limited, or size limited
  local bwlimit = maxbw/4
  local sizelimit = (addressable*maxbw)/2048

  local count = math.max(bwlimit, sizelimit, 1)

  err( count==math.floor(count), "non integer number of BRAMS needed?")
  assert(count <= inputBytes) -- must read at least 1 byte per ram

--  local eachInputBytes = sel(count==bwlimit,math.min(inputBytes,4),inputBytes/(sizeInBytes/(2048)))
  local eachInputBytes = math.max(inputBytes/count,1)
  local inputAddrBits = math.log(sizeInBytes/inputBytes)/math.log(2)

  print("eachInputBytes",eachInputBytes, "inputaddrbits",inputAddrBits,"count",count,"sizeinbytes",sizeInBytes,"inputBytes",inputBytes,"addressable",addressable)
  assert(eachInputBytes>=1 and eachInputBytes<=4)
  assert(eachInputBytes<=inputBytes)
  assert(eachInputBytes*count==inputBytes)

  local eachOutputBytes, outputAddrBits
  if outputBytes~=nil then
    assert(count <= outputBytes) -- must read at least 1 byte per ram
    eachOutputBytes = math.max(outputBytes/count,1)
--    eachOutputBytes = sel(count==bwlimit, math.min(outputBytes,4), outputBytes/(sizeInBytes/(2048)))
--    eachOutputBytes = math.max(eachOutputBytes,1)
    print("eachOutputBytes",eachOutputBytes)
    assert(eachOutputBytes>=1 and eachOutputBytes<=4)
    assert(eachOutputBytes<=outputBytes)
    assert(eachOutputBytes*count==outputBytes)
    outputAddrBits = math.log(sizeInBytes/outputBytes)/math.log(2)
  end

  if sizeInBytes < count*2048 then
    print("Warning: bram is underutilized ("..sizeInBytes.."bytes requested, "..(count*2048).."bytes allocated, "..(count).." BRAMs, "..inputBytes.." bytes input BW, "..tostring(outputBytes).." bytes output BW). "..debug.traceback())
  end

  if init~=nil then
    err( #init==sizeInBytes, "init field has size "..(#init).." but should have size "..sizeInBytes )
    while #init < 2048 do
      table.insert(init,0)
    end
  end

  if writeAndReturnOriginal then
    local mod = Ssugar.moduleConstructor( "bramSDP_WARO"..tostring(writeAndReturnOriginal).."_size"..sizeInBytes.."_bw"..inputBytes.."_obw"..tostring(outputBytes).."_CE"..tostring(CE).."_init"..tostring(init) )
    local sinp = systolic.parameter("inp",types.tuple{types.uint(inputAddrBits),types.bits(inputBytes*8)})
    local sinpRead
    if outputBytes~=nil then sinpRead = systolic.parameter("inpRead",types.uint(outputAddrBits)) end
    local inpAddr = systolic.index(sinp,0)
    local inpData = systolic.index(sinp,1)

    local out, outRead = {}, {}
    for ram=0,count-1 do
      local eachOutputBits
      if outputBytes~=nil then eachOutputBits = eachOutputBytes*8 end

      local m =  mod:add( systolic.module.bram2KSDP( writeAndReturnOriginal, eachInputBytes*8, eachOutputBits, CE, init ):instantiate("bram_"..ram) )
      local inp = systolic.bitSlice( inpData, ram*eachInputBytes*8, (ram+1)*eachInputBytes*8-1 )

      local internalInputAddrBits = math.log(2048/eachInputBytes)/math.log(2)
      table.insert( out, m:writeAndReturnOriginal( systolic.tuple{ systolic.cast(inpAddr,types.uint(internalInputAddrBits)),inp} ) )

      if outputBytes~=nil then 
        local internalOutputAddrBits = math.log(2048/eachOutputBytes)/math.log(2)
        table.insert( outRead, m:read( systolic.cast(sinpRead,types.uint(internalOutputAddrBits)) ) ) 
      end
    end

    local res = systolic.cast(systolic.tuple(out),types.bits(inputBytes*8))
    mod:addFunction( systolic.lambda("writeAndReturnOriginal", sinp, res, "WARO_OUT", nil, nil, sel(CE,S.CE("writeAndReturnOriginal_CE"),nil)) )

    if outputBytes~=nil then 
      mod:addFunction( systolic.lambda("read", sinpRead, systolic.cast(systolic.tuple(outRead),types.bits(outputBytes*8)), "READ_OUT", nil, nil, sel(CE,S.CE("read_CE"),nil) ) ) 
    end

    return mod
  else
    assert(false)
  end
                                  end)

function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  local l =  str:match("(.*/)")
  return l:sub(0,#l-4)
end

function readAll(file)
  local fn = script_path().."extras/"..file
  print("LOAD FILE "..fn)
  local f = io.open(fn, "rb")
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
  print("MODULE ",filestr,"DELAY",tonumber(delaystring))
  local m = systolic.module.new(filestr,fns,{},true,nil,nil,vstring,{process=tonumber(delaystring)})
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

return modules