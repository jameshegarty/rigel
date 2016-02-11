systolic = require("systolic")
S=systolic
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

function modules.reduceSystolic( op, cnt, datatype, argminVars)
  local rname, rmod = modules.reduceVerilog( op, cnt, datatype, argminVars )
  local r = systolic.module(rname, {verilog=rmod} )

  local inputs = {}
  local output = systolic.output("out",datatype)
  for i=0, cnt-1 do
    table.insert( inputs, systolic.input( "partial_"..i, datatype ) )
  end

  local delay = math.ceil(math.log(cnt)/math.log(2))
  local redFn = r:addFunction("reduce", inputs, output, {verilogDelay=delay} )
  return r
end

--modules.reduce = modules.reduceSystolic
modules.reduce = memoize( modules.reduceSystolic )

function modules.linebuffer( maxDelayX, maxDelayY, datatype, stripWidth )
  assert(type(maxDelayX)=="number")
  assert(type(maxDelayY)=="number")
  assert(maxDelayX>=0)
  assert(maxDelayY>=0)
  assert(darkroom.type.isType(datatype))

  local OR = {}
  local BRAM = {}
  local writeAddr = systolic.reg("writeAddr", uint16, 0)
  local readAddr = systolic.reg("readAddr", uint16, 0)

  local modname = "Linebuffer_"..numToVarname(maxDelayX).."delayX_"..numToVarname(maxDelayY).."delayY_"..datatype:sizeof().."bpp_"..stripWidth.."w"
  local lb = systolic.module(modname)

  lb:add(writeAddr)
  lb:add(readAddr)

  for y=-maxDelayY,0 do
    OR[y] = {}
    for x=-maxDelayX,0 do
      OR[y][x] = systolic.reg("lb_x"..numToVarname(x).."_y"..numToVarname(y), datatype)
      lb:add(OR[y][x])
    end
    if y>-maxDelayY then
      BRAM[y] = systolic.bram( "line"..numToVarname(y) )
      lb:add(BRAM[y])
    end
  end

  do -- store
    local I = systolic.input( "indata", datatype )
    local storeFn = lb:addFunction("store",{I},nil)
    storeFn:addAssignBy( "sumwrap", writeAddr, systolic.cast(1,uint16), systolic.cast( stripWidth-1, uint16 ) )

    local evicted
    local y = 0
    while y>=-maxDelayY do
      for x=-maxDelayX,0 do
        if x==0 and y==0 then
          storeFn:addAssign(OR[y][x],I:read())
          if maxDelayY>0 then evicted = storeFn:bramWriteAndReturnOriginal( BRAM[y], writeAddr:read(), I:read(), datatype) end
        elseif x==0 and y>-maxDelayY then
          storeFn:addAssign( OR[y][x], evicted )
          evicted = storeFn:bramWriteAndReturnOriginal( BRAM[y], writeAddr:read(), evicted, datatype)
        elseif x==0 then
          storeFn:addAssign( OR[y][x], evicted )
        else
          storeFn:addAssign( OR[y][x], OR[y][x+1]:read() )
        end
      end
      y = y - 1
    end
  end

  local hasData = systolic.eq( writeAddr:read(), systolic.select( systolic.eq(readAddr:read(),systolic.cast(stripWidth-1, uint16)), systolic.cast(0,uint16), readAddr:read()+systolic.cast(1,uint16) ) )

  do -- load
    local strideX = systolic.input("strideX",uint8)
    local Output = systolic.output("out", darkroom.type.array(datatype,{maxDelayX+1,maxDelayY+1}))
    local loadFn = lb:addFunction("load",{},Output)
    loadFn:addAssignBy( "sumwrap", readAddr, systolic.cast(1,uint16), systolic.cast( stripWidth-1, uint16 ) )
    loadFn:addAssert( hasData, "read from linebuffer when it doesnt have data WA %d RA %d ", writeAddr:read(), readAddr:read() )
    --loadFn:addAssert(systolic.eq(writeAddr:read(),readAddr:read()+systolic.cast(1,uint16)), "read from linebuffer too late!")

    local Oflat = {}
    for y=0,maxDelayY do
      for x=0,maxDelayX do
        table.insert(Oflat, OR[-y][-x]:read())
      end
    end
    loadFn:addAssign(Output,systolic.array(Oflat))
  end


  -- ready
  local readyres = systolic.output("isReady", darkroom.type.bool() )
  local readyFn = lb:addFunction("ready",{},readyres,{pipeline=false})
  readyFn:addAssign( readyres, hasData )

  return lb
end
modules.linebuffer = memoize( modules.linebuffer )

local terra bitselect(a : uint, bit : uint)
  return a and bit
end

-- make an array of ram128s to service a certain bandwidth
modules.ram128 = function(ty, init)
  assert(types.isType(ty))
  local ram128 = systolic.moduleConstructor("ram128_"..sanitize(tostring(ty)) )
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

  local read = ram128:addFunction( systolic.lambdaConstructor("read",types.uint(8),"read_input") )
--  pushBackReset:setCE(pushCE)

  local bitfield = map( range(bits), function(b) return rams[b]:read( S.cast( read:getInput(), types.uint(7)) ) end)
  read:setOutput( systolic.cast( S.tuple(bitfield), ty), "read_output" )

  return ram128
end

modules.fifo = memoize(function(ty,items,verbose)
  assert(types.isType(ty))
  assert(type(items)=="number")
  assert(type(verbose)=="boolean")

  local fifo = systolic.moduleConstructor("fifo_"..sanitize(tostring(ty).."_"..items) )
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
    ram = fifo:add(systolic.module.bramSDP(true,items*bytes,bytes,bytes,nil,true):instantiate("ram"))
  end

  -- size
  local sizeFn = fifo:addFunction( S.lambdaConstructor("size") )
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
  local readyFn = fifo:addFunction( S.lambdaConstructor("ready") )
  local ready = S.lt( fsize, S.constant(items-2-READY_PIPELINE,types.uint(addrBits)) ):disablePipelining()
  readyFn:addPipeline( readyReg:set(ready) )
  readyFn:setOutput( readyReg:get(), "ready" )

  -- has data
  local hasDataFn = fifo:addFunction( S.lambdaConstructor("hasData") )
  local hasData = S.__not( S.eq( writeAddr:get(), readAddr:get()) ):disablePipelining()
--  local hasData = S.gt(fsize,S.constant(16,types.uint(addrBits))):disablePipelining()
--  local hasData = S.gt( modules.modSub(writeAddr:get(),readAddr:get(), 128 ), S.constant(1,types.uint(8)) ):disablePipelining()
  hasDataFn:setOutput( hasData, "hasData" )


  -- pushBack
  local pushCE = S.CE("CE_push")
  local pushBack = fifo:addFunction( systolic.lambdaConstructor("pushBack",ty,"pushBack_input" ) )
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
  local pushBackReset = fifo:addFunction( systolic.lambdaConstructor("pushBackReset" ) )
  pushBackReset:setCE(pushCE)
  pushBackReset:addPipeline( writeAddr:set(systolic.constant(0,types.uint(addrBits))))

  -- popFront
  local popCE = S.CE("CE_pop")
  local popFront = fifo:addFunction( S.lambdaConstructor("popFront") )
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
  local popFrontReset = fifo:addFunction( systolic.lambdaConstructor("popFrontReset" ) )
  popFrontReset:setCE(popCE)
  popFrontReset:addPipeline( readAddr:set(systolic.constant(0,types.uint(addrBits))))

  return fifo
                          end)


modules.fifo128 = memoize(function(ty,verbose) return modules.fifo(ty,128,verbose) end)

modules.fifonoop = memoize(function(ty)
  assert(types.isType(ty))

  local fifo = systolic.moduleConstructor("fifonoop_"..sanitize(tostring(ty))):onlyWire(true)

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
  local pushBackReset = fifo:addFunction( systolic.lambdaConstructor("store_reset" ) )

  -- popFrontReset
  local popFrontReset = fifo:addFunction( systolic.lambdaConstructor("load_reset" ) )

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
  err( resetValue==nil or type(resetValue) == ty:toLuaType(), "resetValue has incorrect type")
  err( type(CE)=="boolean", "CE option must be bool")

  local M = systolic.moduleConstructor( "ShiftRegister_"..size.."_CE"..tostring(CE).."_TY"..ty:verilogBits() )
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
    local regs = map(exprs, function(e,i) return module:add( S.module.regConstructor(ty):CE(true):setInit(e:const()):instantiate("SR_"..i) ) end )

    pipelines = map( regs, function(r,i) return r:set( regs[((i-1+stride)%#exprs)+1]:get() )  end )
    out = map( regs, function(r) return r:get() end )
  else
    local phase = module:add( S.module.regByConstructor( types.uint(16), modules.sumwrap(types.uint(16),period-1) ):CE(true):instantiate("phase") )

    resetPipelines = {phase:set( S.constant(0,types.uint(16)) )}
    reading = S.eq(phase:get(),S.constant(0,types.uint(16))):disablePipelining():setName("reading")

    local regs = map(exprs, function(e,i) return module:add( S.module.regConstructor(ty):CE(true):instantiate("SR_"..i) ) end )

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

function modules.xygen( minX, maxX, minY, maxY )
  assert(type(minX)=="number")
  assert(type(maxX)=="number")
  assert(type(minY)=="number")
  assert(type(maxY)=="number")

  local xygen = systolic.module( "xygen", {assignArbitrate=true} )
  local xreg = xygen:add(systolic.reg("xreg", int16, minX))
  local yreg = xygen:add(systolic.reg("yreg", int16, minY))

  -- reset
  local reset = xygen:addFunction( "reset", {}, nil )
  reset:addAssign( xreg, systolic.cast( minX, int16) )
  reset:addAssign( yreg, systolic.cast( minY, int16) )

  -- x fn
  local xout = systolic.output("xout", int16 )
  local x = xygen:addFunction("x",{},xout)
  x:addAssign(xout, xreg:read())
  x:addAssignBy( "sumwrap", xreg, systolic.cast(1,int16), systolic.cast( maxX-1 ,int16), systolic.cast( minX, int16) )
  x:addAssignBy( "sum", yreg, systolic.select(systolic.eq( xreg:read(), systolic.cast( maxX-1, int16 ) ), systolic.cast(1,int16), systolic.cast(0,int16)) )

  -- y fn
  local yout = systolic.output("yout", int16 )
  local y = xygen:addFunction("y",{},yout)
  y:addAssign(yout, yreg:read())

  return xygen
end
modules.xygen = memoize(modules.xygen)

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

function modules.buffer(moduleName, sizeBytes, inputBytes, outputBytes)
  assert(type(inputBytes)=="number")
  assert(type(outputBytes)=="number")

  local bramCnt = math.ceil(sizeBytes / 2048)
  local extraBits = math.ceil(math.log(bramCnt)/math.log(2))

  local chunkBits = {}
  local outputChunkSize = nearestPowerOf2(outputBytes)
  chunkBits.outaddr = math.log(outputChunkSize)/math.log(2)
  local inputChunkSize = nearestPowerOf2(inputBytes)
  chunkBits.inaddr = math.log(inputChunkSize)/math.log(2)

  -- if inputBytes==1
  local chunkSize, contiguous, strideAddr, nonstrideAddr, strideClk

  if inputBytes==1 then
    chunkSize = nearestPowerOf2(outputBytes)
    contiguous = outputBytes
    strideAddr = "inaddr"
    nonstrideAddr = "outaddr"
    strideClk = "CLK_INPUT"
  elseif outputBytes==1 then
    chunkSize = nearestPowerOf2(inputBytes)
    contiguous = inputBytes
    strideAddr = "outaddr"
    nonstrideAddr = "inaddr"
    strideClk = "CLK_OUTPUT"
  elseif inputBytes==outputBytes then
    chunkSize = nearestPowerOf2(inputBytes)
    contiguous = chunkSize
  else
    assert(false)
  end

  assert(chunkSize<=4)

  local res = {"module "..moduleName.."(\ninput CLK_INPUT, \ninput CLK_OUTPUT,\ninput ["..(10+extraBits-chunkBits.inaddr)..":0] inaddr,\ninput WE,\ninput ["..(inputBytes*8-1)..":0] indata,\ninput ["..(10+extraBits-chunkBits.outaddr)..":0] outaddr,\noutput ["..(outputBytes*8-1)..":0] outdata\n);\n\n"}

  if contiguous~=chunkSize and (outputBytes~=inputBytes) then
    table.insert(res,"reg ["..(10+extraBits-chunkBits[strideAddr])..":0] lastaddr = 0;\n")
    table.insert(res,"reg [4:0] cycleCNT = 0;\n")
    table.insert(res,"reg ["..(10+extraBits-chunkBits[strideAddr])..":0] "..strideAddr.."Internal = 0;\n")
    table.insert(res,"wire ["..(10+extraBits-chunkBits[nonstrideAddr])..":0] "..nonstrideAddr.."Internal = "..nonstrideAddr..";\n")
  else
    table.insert(res,"wire ["..(10+extraBits-chunkBits.inaddr)..":0] inaddrInternal = inaddr;\n")
    table.insert(res,"wire ["..(10+extraBits-chunkBits.outaddr)..":0] outaddrInternal = outaddr;\n")
  end

  local assn = "outdata0"
  for i=0,bramCnt-1 do
    table.insert(res,"wire ["..(outputChunkSize*8-1)..":0] outdata"..i..";\n")

    local bramconf = {name="ram"..i,A={DI="indata",WE="WE", ADDR="inaddrInternal", CLK="CLK_INPUT", chunk=inputChunkSize},
                     B={DO="outdata"..i, WE="1'b0", ADDR="outaddrInternal", CLK="CLK_OUTPUT", chunk=outputChunkSize}}
    if bramCnt > 1 then
      bramconf.A.WE = "(WE && (inaddrInternal["..(10+extraBits-chunkBits.inaddr)..":"..(11-chunkBits.inaddr).."]=="..extraBits.."'d"..i.."))"
    end
    res = concat(res, fixedBram(bramconf))

    if i>0 then assn = "(outaddr["..(10+extraBits-chunkBits.outaddr)..":"..(11-chunkBits.outaddr).."]=="..extraBits.."'d"..i..")? outdata"..i.." : ("..assn..")" end
  end

  table.insert(res, "wire ["..(outputChunkSize*8-1)..":0] outdata_tmp;\n")
  table.insert(res, "assign outdata_tmp = "..assn..";\n")
  table.insert(res, "assign outdata = outdata_tmp["..(outputBytes*8-1)..":0];\n")

  if contiguous~=chunkSize and (outputBytes~=inputBytes) then
    table.insert(res,[=[always @(posedge ]=]..strideClk..[=[) begin
  if(]=]..strideAddr..[=[ != lastaddr) begin
    if(]=]..strideAddr..[=[==0) begin
      cycleCNT <= 0;
      ]=]..strideAddr..[=[Internal <= 0;
    end else if(cycleCNT == ]=]..(contiguous-1)..[=[) begin
      cycleCNT <= 0;
      ]=]..strideAddr..[=[Internal <= ]=]..strideAddr..[=[Internal+1+]=]..(chunkSize-contiguous)..[=[;
    end else begin
      cycleCNT <= cycleCNT+1;
      ]=]..strideAddr..[=[Internal <= ]=]..strideAddr..[=[Internal+1;
    end

  end
  lastaddr <= ]=]..strideAddr..[=[;
end
]=])

  end

  table.insert(res,"endmodule\n\n")
  return res
end

function modules.sim(inputBytes, outputBytes, stripWidth, imageHeight, outputShift, metadata)
  assert(type(inputBytes)=="number")
  assert(type(outputBytes)=="number")
  assert(type(stripWidth)=="number")

  local res = {[=[`define EOF 32'hFFFF_FFFF
module sim;
  integer c, r,fileout;
  reg     CLK;
  reg []=]..(inputBytes*8-1)..[=[:0] pipelineInput;
  wire []=]..(outputBytes*8-1)..[=[:0] pipelineOutput;
  reg [12:0] posX = 0;
  reg [12:0] posY = 0;
  reg [7:0] cycle = 0;
  reg validIn = 0;
  reg RST = 0;
  wire validOut;
  integer realX = ]=]..(stripWidth+metadata.padMaxX-1)..[=[;
  integer realY = ]=]..(metadata.padMinY-1)..[=[;
  integer addrT;
  integer outputPixelsSeen = 0;
]=]}

  local i=1
  while metadata["inputFile"..i] do
    table.insert(res, "reg [10000:0] inputFilename"..i..";\n")
    table.insert(res,"integer file"..i..";\n")
    i = i + 1
  end

  table.insert( res, [=[  reg [10000:0] outputFilename; 
  reg [7:0] i = 0;

  Pipeline pipeline(.CLK(CLK),.input1(pipelineInput),.out(pipelineOutput),.validIn(validIn),.validOut(validOut),.reset(RST));

  initial begin
   $display("HELLO");]=])

   local i=1
   while metadata["inputFile"..i] do
     table.insert( res, [=[$value$plusargs("inputFilename]=]..i..[=[=%s",inputFilename]=]..i..[=[);
     ]=])
     table.insert( res, [=[file]=]..i..[=[ = $fopen(inputFilename]=]..i..[=[,"r");
     ]=])
     i = i + 1
   end
   table.insert( res, [=[
   $value$plusargs("outputFilename=%s",outputFilename);

   fileout = $fopen(outputFilename,"w");

   // prime the pipe
   // we run this for a large number of cycles to simulate what will happen in the actual hardware
   addrT = 1000+]=]..outputShift..[=[;
   while(addrT>0) begin
     posX = realX;
     posY = realY;
     cycle = ]=]..(metadata.cycles-1)..[=[;
     validIn = 0;
     RST = 1;
     CLK = 0;
     #10
     CLK = 1;
     #10
     addrT = addrT-1;
   end

   realY = ]=]..(metadata.padMinY)..[=[;
   while (realY < ]=]..(imageHeight+metadata.padMaxY)..[=[) begin
     realX = ]=]..(metadata.padMinX)..[=[;
     while (realX < ]=]..(stripWidth+metadata.padMaxX)..[=[) begin

         if ( realX>=0 && realX<]=]..stripWidth..[=[ && realY>=0 && realY <]=]..imageHeight..[=[ ) begin
]=])

local i=1
local bpos = 0
while metadata["inputFile"..i] do
  for ch=0,metadata["inputBytes"..i]-1 do
    table.insert( res, "pipelineInput["..(bpos*8+7)..":"..(bpos*8).."] = $fgetc(file"..i..");\n")
    bpos = bpos + 1
  end
  i=i+1
end
         
table.insert( res, [=[       end else begin
         pipelineInput = 0;
         end

       cycle = 0;
       while (cycle < ]=]..metadata.cycles..[=[) begin
       posX = realX;
       posY = realY;
       validIn = 1;
       RST=0;
       CLK = 0;
       #10
       CLK = 1;
       #10
//     $display(modOutput);
       if(validOut) begin 
         i = 0;
         while( i<]=]..outputBytes..[=[) begin
           $fwrite(fileout, "%c", pipelineOutput[i*8+:8]); 
           i = i + 1;
         end
//         $display("outvalid %d",outputPixelsSeen);
         outputPixelsSeen = outputPixelsSeen + 1;
       end

         cycle = cycle + 1;
       end

       realX = realX + 1;
     end
     realY = realY + 1;
   end // while (c != `EOF)

   // drain pipe

   realX = ]=]..(metadata.padMinX)..[=[;
   while (outputPixelsSeen < ]=]..(metadata.stripWidth*metadata.stripHeight)..[=[) begin
     cycle = 0;
     while (cycle < ]=]..metadata.cycles..[=[) begin
       pipelineInput = 0;
       posX = realX;
       posY = realY;
       validIn = 0;
       CLK = 0;
       #10
       CLK = 1;
       #10

     if (validOut) begin 
       i=0;
       while( i<]=]..outputBytes..[=[) begin
         $fwrite(fileout, "%c", pipelineOutput[i*8+:8]);
         i = i + 1;
       end
       outputPixelsSeen = outputPixelsSeen+1;
     end

       cycle = cycle + 1;
     end

     if(realX==]=]..(stripWidth+metadata.padMaxX-1)..[=[) begin
      realX = ]=]..(metadata.padMinX)..[=[;
      realY = realY+1;
     end else begin
     realX = realX + 1;
     end


   end	   

   $display("DONE");
   $fclose(fileout);
  end // initial begin

endmodule // sim        ]=])

return res
end

function modules.tx(clockMhz, uartClock)
assert(type(clockMhz)=="number")
assert(type(uartClock)=="number")
  return {[=[module TXMOD(
input CLK,
output TX,
input [7:0] inbits,
input enable,
output ready // when true, we're ready to transmit a new bit
    );

  reg TXd = 1;
  assign TX = TXd;

  reg [28:0] d;
  wire [28:0] dInc = d[28] ? (]=]..uartClock..[=[) : (]=]..uartClock..[=[ - ]=]..clockMhz..[=[000000);
  wire [28:0] dNxt = d + dInc;
  always @(posedge CLK)
  begin
    d = dNxt;
  end
  wire SLOWCLK = ~d[28]; // this is the 115200 Hz clock


  reg [3:0] counter = 0;

  always @ (posedge SLOWCLK)
  begin
    if(enable && counter==0) begin
      TXd <= 0; // signal start
      counter <= 1;
    end else if(enable && counter==9) begin
      TXd <= 1; // signal end
      counter <= 0;
    end else if(enable) begin
		  TXd <= inbits[counter-1];
      counter <= counter + 1;
    end else begin
	   TXd <= 1;
     counter <= 0;
	 end
  end

  reg readyBitSent = 0;
  reg readyBit = 0;
  assign ready = readyBit;
  
  always @ (posedge CLK)
  begin
    if(enable && counter==0 && readyBitSent==0) begin      
      readyBit <= 1;
      readyBitSent <= 1;
    end else if(enable && counter==0 ) begin
      readyBit <= 0;
    end else begin
      readyBit <= 0;
		readyBitSent <= 0;
    end
  end

endmodule

]=]}
end

function modules.rx(clockMhz, uartClock)
assert(type(clockMhz)=="number")
assert(type(uartClock)=="number")
return {[=[module RXMOD(
input RX, 
input CLK,
output [7:0] outbits,
output outvalid
    );

reg [8:0] data;
assign outbits = data[8:1];

reg [3:0] readClock = 0; // which subclock?
reg [3:0] readBitClock = 0; // which bit?
reg reading = 0;

reg outvalidReg = 0;
assign outvalid = outvalidReg;


// we'd better see some 1s on the line before we start reading data
//reg [7:0] started = 0;

reg [28:0] d;
  wire [28:0] dInc = d[28] ? (]=]..(uartClock*16)..[=[) : (]=]..(uartClock*16)..[=[ - ]=]..clockMhz..[=[000000);
  wire [28:0] dNxt = d + dInc;
  always @(posedge CLK)
  begin
    d = dNxt;
  end
  wire SMPCLK = ~d[28]; // this is the 115200 Hz clock


always @ (posedge SMPCLK)
begin
  if(RX==0 && reading==0) begin
    reading <= 1;
    readClock <= 0;
    readBitClock <= 0;
  end else if(reading==1 && readClock==7 && readBitClock==9) begin
    // we're done
    reading <= 0;
    readClock <= readClock + 1;
  end else if(reading==1 && readClock==7) begin
    // read a byte
    data[readBitClock] <= RX;
    readClock <= readClock + 1;
	 readBitClock <= readBitClock + 1;
  end else begin
    readClock <= readClock + 1;
  end
end

reg wrote = 0;

always @(posedge CLK)
begin
  if(RX==0 && reading==0) begin
  	 wrote <= 0;
	 outvalidReg <= 0;
  end else if(reading==1 && readClock==7 && readBitClock==9 && wrote==0) begin
    outvalidReg <= 1;
	 wrote <= 1;
  end else begin
    outvalidReg <= 0;
  end
end

endmodule

]=]}
end

function modules.stageUART(options, inputBytes, outputBytes, stripWidth, stripHeight)

  local result = {}
  result = concat(result, fpga.modules.tx(options.clockMhz, options.uartClock))
  result = concat(result, fpga.modules.rx(options.clockMhz, options.uartClock))
  result = concat(result, fpga.modules.buffer("InputBuffer",stripWidth*stripHeight,1,inputBytes))
  result = concat(result, fpga.modules.buffer("OutputBuffer",stripWidth*stripHeight,outputBytes,1))

  local pxcnt = stripWidth*stripHeight
  local metadataBytes = 4
  local rxStartAddr = math.pow(2,13)-metadataBytes

  local shiftInMetadata = "metadata[31:24] <= rxbits;\n"
  for i=0,metadataBytes-2 do
    shiftInMetadata = shiftInMetadata .. "metadata["..(i*8+7)..":"..(i*8).."] <= metadata["..(i*8+15)..":"..(i*8+8).."];\n"
  end

table.insert(result, [=[module stage(
input CLK, 
input RX, 
output TX,
output [7:0] LED);

reg [12:0] addr = ]=]..rxStartAddr..[=[;
reg [12:0] sendAddr = -1;

reg []=]..(metadataBytes*8-1)..[=[:0] metadata = 0;
reg [12:0] posX = 0;
reg [12:0] posY = 0;

reg receiving = 1;
reg processing = 0;
reg sending = 0;

wire [7:0] rxbits;
wire []=]..(inputBytes*8-1)..[=[:0] pipelineInput;
reg [12:0] pipelineReadAddr = 0; 
InputBuffer inputBuffer(.CLK_INPUT(CLK), .CLK_OUTPUT(CLK), .inaddr(addr), .WE(receiving), .indata(rxbits), .outaddr(pipelineReadAddr), .outdata(pipelineInput));

wire []=]..(outputBytes*8-1)..[=[:0] pipelineOutput;
wire [7:0] outbuf;
reg [12:0] pipelineWriteAddr = -PIPE_DELAY; // pipe delay
OutputBuffer outputBuffer(.CLK_INPUT(CLK), .CLK_OUTPUT(CLK), .inaddr(pipelineWriteAddr), .WE(processing), .indata(pipelineOutput), .outaddr(sendAddr), .outdata(outbuf));

Pipeline pipeline(.CLK(CLK), .inX(posX+metadata[12:0]), .inY(posY+metadata[28:16]), .packedinput(pipelineInput), .out(pipelineOutput));

reg [7:0] rxCRC = 0;
reg [7:0] sendCRC = 0;
   
wire rxvalid;
wire txready;
RXMOD rxmod(.RX(RX),.CLK(CLK),.outbits(rxbits),.outvalid(rxvalid));
TXMOD txmod(.TX(TX),.CLK(CLK),.inbits( (sendAddr>]=]..(pxcnt*outputBytes-1)..[=[)?((sendAddr==]=]..(pxcnt*outputBytes)..[=[)?sendCRC:rxCRC):outbuf),.enable(sending),.ready(txready));

always @(posedge CLK) begin
  if(receiving) begin
  if(addr == ]=]..(pxcnt*inputBytes)..[=[) begin
      addr <= ]=]..rxStartAddr..[=[;
      receiving <= 0;
		  sending <= 0;
		  processing <= 1;
      pipelineReadAddr <= 1; // it will have addr 0 valid on the output on next clock, then 1 on the output on following clock
    end else if(rxvalid) begin
      if(addr>=]=]..rxStartAddr..[=[) begin
        ]=]..shiftInMetadata..[=[
      end
      addr <= addr + 1;
      rxCRC <= rxCRC + rxbits;
    end
  end
  
  if(processing) begin
    if(rxvalid) begin // restart if new data comes in
      sending <= 0;
      receiving <= 1;
      rxCRC <= 0;
      processing <= 0;
      sendAddr <= -1;
      pipelineWriteAddr <= -PIPE_DELAY;
      pipelineReadAddr <= 0;
      posX <= 0;
      posY <= 0;
    end else if(pipelineWriteAddr == ]=]..pxcnt..[=[) begin
      pipelineWriteAddr <= -PIPE_DELAY;
		  pipelineReadAddr <= 0;
      posX <= 0;
      posY <= 0;
      receiving <= 0;
		  sending <= 1;
		  processing <= 0;
    end else begin
	    pipelineReadAddr <= pipelineReadAddr + 1;
      pipelineWriteAddr <= pipelineWriteAddr + 1;
      if (posX == ]=]..(stripWidth-1)..[=[) begin
        posX <= 0;
        posY <= posY+1; // inc y
      end else begin
        posX <= posX + 1; // inc x
      end
	 end
  end
  
  if(sending) begin
    if(rxvalid) begin // restart if new data comes in
      sending <= 0;
      receiving <= 1;
      rxCRC <= 0;
      processing <= 0;
      sendAddr <= -1;
      end else if(sendAddr==]=]..(pxcnt*outputBytes+2)..[=[) begin
      // we're done
      sending <= 0;
      receiving <= 1;
      rxCRC <= 0;
      processing <= 0;
	    sendAddr <= -1;
      sendCRC <= 0;
    end else if(txready) begin
      sendAddr <= sendAddr + 1;
      if (sendAddr >= 0 && sendAddr < ]=]..(pxcnt*outputBytes)..[=[) begin sendCRC <= sendCRC + outbuf; end
    end
  end

end

assign LED = {addr[6:1],receiving,processing,sending};
endmodule

]=])

  return table.concat(result,"")
end

function modules.sccbctrl()
return [=[module SCCBCtrl (clk_i, rst_i, sccb_clk_i, data_pulse_i, addr_i, data_i, data_o, rw_i, start_i, ack_error_o, 
                  done_o, sioc_o, siod_io);

   input       clk_i;               // Main clock.
   input       rst_i;               // Reset.
   input       sccb_clk_i;          // SCCB clock. Typical - 100KHz as per SCCB spec.
   input       data_pulse_i;        // Negative mid sccb_clk_i cycle pulse.
   input       [7:0] addr_i;        // Device ID. Bit 0 is ignored since read/write operation is specified by rw_i.
   input       [15:0] data_i;       // Register address in [15:8] and data to write in [7:0] if rw_i = 1 (write).
                                    // Register address in [15:8] if rw_i = 0 (read).
   output reg  [7:0] data_o;        // Data received if rw_i = 0 (read).
   input       rw_i;                // 0 - read command. 1 - write command. 
   input       start_i;             // Start transaction.
   output      ack_error_o;         // Error occurred during the transaction.
   output reg  done_o;              // 0 - transaction is in progress. 1 - transaction has completed.
   output      sioc_o;              // SIOC line.
   inout       siod_io;             // SIOD line. External pull-up resistor required.
   

   reg         sccb_stm_clk = 1;
   reg         [6:0] stm = 0;
   reg         bit_out = 1;
   reg         ack_err1 = 1;
   reg         ack_err2 = 1;
   reg         ack_err3 = 1;
   
   assign   sioc_o = (start_i == 1 && 
                     (stm >= 5 && stm <= 12 || stm == 14 ||   
                     stm >= 16 && stm <= 23 || stm == 25 ||
                     stm >= 27 && stm <= 34 || stm == 36 ||
                     stm >= 44 && stm <= 51 || stm == 53 ||
                     stm >= 55 && stm <= 62 || stm == 64)) ? sccb_clk_i : sccb_stm_clk;
                     
   // Output acks and read data only.
   assign   siod_io = (stm == 13 || stm == 14 || stm == 24 || stm == 25 || stm == 35 || stm == 36 ||
                        stm == 52 || stm == 53 || stm >= 54 && stm <= 62) ? 1'bz : bit_out;
                       
   assign   ack_error_o = ack_err1 | ack_err2 | ack_err3;
   //assign   ack_error_o = ack_err1 || ack_err2;
   //assign   ack_error_o = ack_err1;

   always @(posedge clk_i or negedge rst_i) begin
      if(rst_i == 0) begin 
         stm <= 0;
         sccb_stm_clk <= 1;
         bit_out <= 1; 
         data_o <= 0;  
         done_o <= 0;
         ack_err1 <= 1; 
         ack_err2 <= 1; 
         ack_err3 <= 1;          
      end else if (data_pulse_i) begin
         if (start_i == 0 || done_o == 1) begin
            stm <= 0;
         end else if (rw_i == 0 && stm == 25) begin
            stm <= 37;
         end else if (rw_i == 1 && stm == 36) begin
            stm <= 65;
         end else if (stm < 68) begin
            stm <= stm + 1;
         end

         if (start_i == 1) begin
                (* parallel_case *) case(stm)
                  // Initialize
                  7'd0 : bit_out <= 1;
                  7'd1 : bit_out <= 1;

                  // Start write transaction.
                  7'd2 : bit_out <= 0;
                  7'd3 : sccb_stm_clk <= 0;
                  
                  // Write device`s ID address.
                  7'd4 : bit_out <= addr_i[7];
                  7'd5 : bit_out <= addr_i[6];
                  7'd6 : bit_out <= addr_i[5];
                  7'd7 : bit_out <= addr_i[4];
                  7'd8 : bit_out <= addr_i[3];
                  7'd9 : bit_out <= addr_i[2];
                  7'd10: bit_out <= addr_i[1];
                  7'd11: bit_out <= 0;
                  7'd12: bit_out <= 0;
                  7'd13: ack_err1 <= siod_io;
                  7'd14: bit_out <= 0;
                  
                  // Write register address.
                  7'd15: bit_out <= data_i[15];
                  7'd16: bit_out <= data_i[14];
                  7'd17: bit_out <= data_i[13];
                  7'd18: bit_out <= data_i[12];
                  7'd19: bit_out <= data_i[11];
                  7'd20: bit_out <= data_i[10];
                  7'd21: bit_out <= data_i[9];
                  7'd22: bit_out <= data_i[8];
                  7'd23: bit_out <= 0;
                  7'd24: ack_err2 <= siod_io;
                  7'd25: bit_out <= 0;
                  
                  // Write data. This concludes 3-phase write transaction.
                  7'd26: bit_out <= data_i[7];
                  7'd27: bit_out <= data_i[6];
                  7'd28: bit_out <= data_i[5];
                  7'd29: bit_out <= data_i[4];
                  7'd30: bit_out <= data_i[3];
                  7'd31: bit_out <= data_i[2];
                  7'd32: bit_out <= data_i[1];
                  7'd33: bit_out <= data_i[0];
                  7'd34: bit_out <= 0;
                  7'd35: ack_err3 <= siod_io;
                  7'd36: bit_out <= 0;

                  // Stop transaction.
                  7'd37: sccb_stm_clk <= 0; 
                  7'd38: sccb_stm_clk <= 1;   
                  7'd39: bit_out <= 1;

                  // Start read tranasction. At this point register address has been set in prev write transaction.  
                  7'd40: sccb_stm_clk <= 1;
                  7'd41: bit_out <= 0;
                  7'd42: sccb_stm_clk <= 0;
                  
                  // Write device`s ID address.
                  7'd43: bit_out <= addr_i[7];
                  7'd44: bit_out <= addr_i[6];
                  7'd45: bit_out <= addr_i[5];
                  7'd46: bit_out <= addr_i[4];
                  7'd47: bit_out <= addr_i[3];
                  7'd48: bit_out <= addr_i[2];
                  7'd49: bit_out <= addr_i[1];
                  7'd50: bit_out <= 1;
                  7'd51: bit_out <= 0;
                  7'd52: ack_err3 <= siod_io;
                  7'd53: bit_out <= 0;
                  
                  // Read register value. This concludes 2-phase read transaction.
                  7'd54: bit_out <= 0; 
                  7'd55: data_o[7] <= siod_io;
                  7'd56: data_o[6] <= siod_io; 
                  7'd57: data_o[5] <= siod_io; 
                  7'd58: data_o[4] <= siod_io;
                  7'd59: data_o[3] <= siod_io;
                  7'd60: data_o[2] <= siod_io; 
                  7'd61: data_o[1] <= siod_io;
                  7'd62: data_o[0] <= siod_io;
                  7'd63: bit_out <= 1;
                  7'd64: bit_out <= 0;

                  // Stop transaction.
                  7'd65: sccb_stm_clk <= 0;
                  7'd66: sccb_stm_clk <= 1;
                  7'd67: begin 
                     bit_out <= 1;
                     done_o <= 1;
                  end
                  default: sccb_stm_clk <= 1;
               endcase
            
         end else begin
            sccb_stm_clk <= 1;
            bit_out <= 1; 
            data_o <= data_o;
            done_o <= 0;
            ack_err1 <= 1; 
            ack_err2 <= 1; 
            ack_err3 <= 1;
         end
      end
   end
   
endmodule

]=]
end

function modules.vga()
return [=[module VGA(input CLK,
input RST,
output [9:0] X,
output [9:0] Y,
output VGA_CLK,
input [7:0] R,
input [7:0] G,
input [7:0] B,
                          output VGA_VSYNC, 
                          output VGA_HSYNC,
                          output [2:0] VGA_RED,
                          output [2:0] VGA_GREEN,
                          output [1:0] VGA_BLUE);

parameter DATA_WIDTH = 640;
parameter DATA_HEIGHT = 480;

parameter H_FRONT_PORCH = 16;
parameter H_BACK_PORCH = 48;
parameter H_PULSE = 96;
parameter H_TOTAL = 800;

parameter V_FRONT_PORCH = 10;
parameter V_BACK_PORCH = 33;
parameter V_PULSE = 2;
parameter V_TOTAL = 525; 

//wire rst = 0;//~JOY_UP;

wire CLK50; 
assign VGA_CLK = CLK50;
  DCM_SP #(
.CLKDV_DIVIDE(2.0), // Divide by: 1.5,2.0,2.5,3.0,3.5,4.0,4.5,5.0,5.5,6.0,6.5
//   7.0,7.5,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0 or 16.0
.CLKFX_DIVIDE(14),   // Can be any integer from 1 to 32
.CLKFX_MULTIPLY(11), // Can be any integer from 2 to 32
.CLKIN_DIVIDE_BY_2("FALSE"), // TRUE/FALSE to enable CLKIN divide by two feature
.CLKIN_PERIOD(31.25),  // Specify period of input clock
.CLKOUT_PHASE_SHIFT("NONE"), // Specify phase shift of NONE, FIXED or VARIABLE
.CLK_FEEDBACK("1X"),  // Specify clock feedback of NONE, 1X or 2X
.DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"), // SOURCE_SYNCHRONOUS, SYSTEM_SYNCHRONOUS or
//   an integer from 0 to 15
.DLL_FREQUENCY_MODE("LOW"),  // HIGH or LOW frequency mode for DLL
.DUTY_CYCLE_CORRECTION("TRUE"), // Duty cycle correction, TRUE or FALSE
.PHASE_SHIFT(0),     // Amount of fixed phase shift from -255 to 255
.STARTUP_WAIT("FALSE")   // Delay configuration DONE until DCM LOCK, TRUE/FALSE
) DCM_SP_inst (
//.CLK0(CLK0),     // 0 degree DCM CLK output
//.CLK180(CLK180), // 180 degree DCM CLK output
//.CLK270(CLK270), // 270 degree DCM CLK output
//.CLK2X(CLK2X),   // 2X DCM CLK output
//.CLK2X180(CLK2X180), // 2X, 180 degree DCM CLK out
//.CLK90(CLK90),   // 90 degree DCM CLK output
//.CLKDV(CLKDV),   // Divided DCM CLK out (CLKDV_DIVIDE)
.CLKFX(CLK50),   // DCM CLK synthesis out (M/D)
//.CLKFX180(CLKFX180), // 180 degree CLK synthesis out
//.LOCKED(LOCKED), // DCM LOCK status output
//.PSDONE(PSDONE), // Dynamic phase adjust done output
//.STATUS(STATUS), // 8-bit DCM status bits output
//.CLKFB(CLKFB),   // DCM clock feedback
.CLKIN(CLK),   // Clock input (from IBUFG, BUFG or DCM)
//.PSCLK(PSCLK),   // Dynamic phase adjust clock input
//.PSEN(PSEN),     // Dynamic phase adjust enable input
//.PSINCDEC(PSINCDEC), // Dynamic phase adjust increment/decrement
.RST(0)        // DCM asynchronous reset input
);


reg [9:0] posx;
reg [9:0] posy;

reg [4:0] JX;
reg [4:0] JY;
 
assign xreset = RST || (posx == (H_TOTAL-1));
assign yreset = RST || (posy ==  (V_TOTAL-1));

wire frontporch;
assign frontporch = (posx == DATA_WIDTH-20);

//wire [9:0] Y;
//wire [9:0] X;
assign Y = posy;
assign X = posx;
assign valid = X < DATA_WIDTH && Y < DATA_HEIGHT;

assign injoy = valid && (X < 16*JX + 16 && X >= 16*JX &&
                         Y < 16*JY + 16 && Y >= 16*JY); 

assign c = valid && (Y[4:4] ^ X[4:4]);
assign VGA_RED = {R[2:2] && valid, R[1:1] && valid, R[0:0] && valid};
//assign VGA_GREEN = {c ,c , c};
assign VGA_GREEN = {G[2:2] && valid, G[1:1] && valid, G[0:0] && valid};
//assign VGA_BLUE = {c,c};
assign VGA_BLUE = {B[1:1] && valid, B[0:0] && valid};

always @(posedge CLK50)
    if(xreset)
        posx <= 0;
    else
        posx <= posx + 1;
        
always @(posedge CLK50)
    if(frontporch)
        if(yreset)
            posy <= 0;
        else
            posy <= posy + 1;

reg hsync;
always @(posedge CLK50)
    if(posx == DATA_WIDTH+H_FRONT_PORCH)
        hsync <= 0;
    else if(RST || posx == DATA_WIDTH+H_FRONT_PORCH+H_PULSE)
        hsync <= 1;
		  
reg vsync;
always @(posedge CLK50)
    if(posy == DATA_HEIGHT+V_FRONT_PORCH && frontporch)
        vsync <= 0;
    else if(RST || (posy == DATA_HEIGHT+V_FRONT_PORCH+V_PULSE && frontporch))
        vsync <= 1;

assign VGA_VSYNC = vsync;
assign VGA_HSYNC = hsync;

endmodule

]=]

end

function modules.stageVGA()
  local res = {}

  table.insert(res, modules.sccbctrl())
  table.insert(res, modules.vga())
  table.insert(res, table.concat(modules.buffer("OutputBuffer",2048*4,3,3),""))

table.insert(res,[=[module stage(input RAW_CLK,
input [7:0] CAM_DOUT,
input CAM_VSYNC,
input CAM_HREF,
output CAM_SCL,
inout CAM_SDATA,
output CAM_PWDN,
input CAM_PCLK,
output CAM_XCLK,
output VGA_VSYNC, 
output VGA_HSYNC,
output [2:0] VGA_RED,
output [2:0] VGA_GREEN,
output [1:0] VGA_BLUE,
output LED1,
input REAL_JOYLEFT,
input REAL_JOYRIGHT
    ); 

wire CLK;
IBUFG clockbuffer ( .I(RAW_CLK), .O(CLK));

reg JOY = 1;
reg JOYDOWN = 1;
reg JOYUP = 1;
reg JOYLEFT = 1;
reg JOYRIGHT = 1;

reg jlset = 0;

reg [25:0] switchCnt = 0;
always @(posedge CLK) begin
	switchCnt <= switchCnt + 1;
	if(switchCnt[25:23]==3'b001 && jlset==0) begin
	   JOYRIGHT <= 0;
		JOYLEFT <= 1;
		JOYDOWN <= 1;
	end else if(switchCnt[25:23]==3'b011 && jlset==0) begin
		JOYLEFT <= 0;
		JOYRIGHT <= 1;
		JOYDOWN <= 1;
	end else if(switchCnt[25:23]==3'b101 && jlset==0) begin
		JOYDOWN <= 0;
		JOYLEFT <= 1;
		JOYRIGHT <= 1;
   end else if(switchCnt[25:23]==3'b111) begin
	  jlset <= 1;
	end else begin
	  JOYLEFT <= 1;
	  JOYRIGHT <= 1;
	  JOYDOWN <= 1;
	end
end

wire PCLK;
IBUFG clockbuffer2 ( .I(CAM_PCLK), .O(PCLK));

parameter   IN_FREQ = 32_000_000;   // clk_i frequency in Hz.
localparam  SCCB_FREQ = 100_000;    // SCCB frequency in Hz.
localparam  SCCB_PERIOD = IN_FREQ/SCCB_FREQ/2;
reg         [8:0] sccb_clk_cnt = 0;
reg         sccb_clk = 0;
wire        data_pulse = (sccb_clk_cnt == SCCB_PERIOD/2 && sccb_clk == 0); 
parameter   CAM_ID = 8'h42;         // OV7670 ID. Bit 0 is Don't Care since we specify r/w op in register lookup table.

// Generate clock for the SCCB.
   always @(posedge CLK) begin
      if (0) begin
         sccb_clk_cnt <= 0;
         sccb_clk <= 0;
      end else begin
         if (sccb_clk_cnt < SCCB_PERIOD) begin
            sccb_clk_cnt <= sccb_clk_cnt + 1;
         end else begin
            sccb_clk <= ~sccb_clk;
            sccb_clk_cnt <= 0;
         end
      end
   end

reg transDone = 0;

wire ack_error;
assign LED1 = transDone;

//reg [15:0] data = 16'h1540; //hsync
//reg [15:0] data = 16'h1204; //rgb mode
//reg [15:0] data = 16'h1280; 
//reg [15:0] data = 16'h0A80; // product ID
//reg [15:0] data = 16'h0B80; // com4
//40D0 - 565
//1280 - reset
//0010 - gain
// 1215 - QVGA raw 
// 0e81 - high frame rate mode?
//1709 - this sort of changed it to the left a little
//reg [15:0] data = (JOYLEFT==0)? 16'h1204 : 16'h1540; //rgb mode
//reg [15:0] data = (JOYDOWN==0)?16'h0E80:((JOYLEFT==0)? 16'h1210 : 16'h1542); //rgb mode
//reg [15:0] data = (JOYDOWN==0)?16'h1700:((JOYLEFT==0)? 16'h1205 : ((JOYRIGHT==0)? 16'h1542 : ((JOYUP==0) ? 16'h1841 : 16'h1280) )); //rgb mode
//reg [15:0] data = (JOYDOWN==0)?16'h1700:((JOYLEFT==0)? 16'h1205 : ((JOYRIGHT==0)? 16'h1542 : ((JOYUP==0) ? 16'h32A0 : 16'h1280) )); //rgb mode
//reg [15:0] data = (JOYDOWN==0)?16'h0E80:((JOYLEFT==0)? 16'h1215 : ((JOYRIGHT==0)? 16'h0e81 : ((JOYUP==0) ? 16'h32A0 : 16'h1280) )); //rgb mode

reg [15:0] data = (JOYDOWN==0)?16'h1542:((JOYLEFT==0)? 16'h1205 : ((JOYRIGHT==0)? 16'h0e81 : ((JOYUP==0) ? 16'h0e81 : 16'h1280) )); //rgb mode
    
wire [7:0] dataOut;
wire done;

SCCBCtrl sccb(.clk_i(CLK),
.rst_i(1'b1),
.sccb_clk_i(sccb_clk),
.data_pulse_i(data_pulse), 
.addr_i(CAM_ID),
.data_i(data), 
.data_o(dataOut), 
//.rw_i(JOYDOWN==0 || JOYLEFT==0), 
.rw_i(1'b1), 
.start_i( (JOY==0 || JOYLEFT==0 || JOYDOWN==0 || JOYUP==0 || JOYRIGHT==0) && transDone==0), 
.ack_error_o(ack_error), 
.done_o(done), 
.sioc_o(CAM_SCL), 
.siod_io(CAM_SDATA));
			
//assign CAM_SCL = 	sccb_clk;
//assign CAM_SDATA = 1'bz;
 
wire RCLK48;
   

DCM_CLKGEN #(
   .CLKFXDV_DIVIDE(2),
   .CLKFX_DIVIDE(125),
   .CLKFX_MD_MAX(0.0),
   .CLKFX_MULTIPLY(187),
   .CLKIN_PERIOD(31.25),
   .STARTUP_WAIT("FALSE")
)
DCM_CLKGEN_inst (
   .CLKFX(RCLK48),
//   .CLKFX180(CLKFX180),
//   .CLKFXDV(CLKFXDV),
//   .LOCKED(LOCKED), 
//   .PROGDONE(PROGDONE),
//   .STATUS(STATUS),
   .CLKIN(CLK),
.FREEZEDCM(1'b0),
.PROGCLK(1'b0),
.PROGDATA(1'b0),
.PROGEN(1'b0),
   .RST(1'b0)
);


 wire CLK24;
 ODDR2 #(
    .DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1" 
    .SRTYPE    ("SYNC") // Specifies "SYNC" or "ASYNC" set/reset
) ODDR2_inst (
    .Q     (CLK24),   // 1-bit DDR output data
    .C0    (RCLK48),   // 1-bit clock input
    .C1    (~RCLK48),  // 1-bit clock input
    .CE    (1'b1),       // 1-bit clock enable input
    .D0    (1'b1),       // 1-bit data input (associated with C0)
    .D1    (1'b0),       // 1-bit data input (associated with C1)
    .R     (1'b0),       // 1-bit reset input
    .S     (1'b0) );     // 1-bit set input

reg [7:0] pipelineInput;
wire [23:0] pipelineOutput;

reg [12:0] posX = 0;
reg [12:0] posY = 0;
reg [10:0] writeAddr = 0;
reg [10:0] readAddr = 0;
reg VGA_RST = 0;
reg vgaSyncOccured = 0; // we only need to reset VGA once
reg CAM_HREF_LAST;
reg CAM_VSYNC_R;
reg CAM_HREF_R;

reg [24:0] phase = 0;
always @(posedge PCLK) begin
  pipelineInput <= CAM_DOUT;
  if(CAM_VSYNC_R==0) begin
    posY <= 0;
    if(vgaSyncOccured==0) begin
      VGA_RST <= 1;
    end
  end else begin
    VGA_RST <= 0;
    vgaSyncOccured <= vgaSyncOccured || (VGA_RST==1);

    if(CAM_HREF_R==1 && CAM_HREF_LAST==0) begin
     posY <= posY + 1;
     posX <= 0;
    end else begin
     posX <= posX + 1;
    end
  end

  CAM_HREF_R <= CAM_HREF;
  CAM_HREF_LAST <= CAM_HREF_R;
  CAM_VSYNC_R <= CAM_VSYNC;
  writeAddr <= posX+phase[24:15];
  if(REAL_JOYLEFT==0) begin
    phase <= phase - 1;
  end

  if(REAL_JOYRIGHT==0) begin
    phase <= phase + 1;
  end
end

wire VGA_CLK;
wire [23:0] outdata;
wire [7:0] VGA_IN_R;
assign VGA_IN_R = outdata[7:0];
wire [7:0] VGA_IN_G;
assign VGA_IN_G = outdata[15:8];
wire [7:0] VGA_IN_B;
assign VGA_IN_B = outdata[23:16];
wire [9:0] VGA_X;
wire [9:0] VGA_Y;

//assign VGA_GREEN={posX==0,CAM_VSYNC_R,CAM_HREF_R}; // for debug
VGA vga(.CLK(CLK), .RST(VGA_RST), .VGA_CLK(VGA_CLK), .VGA_VSYNC(VGA_VSYNC), .VGA_HSYNC(VGA_HSYNC), .VGA_RED(VGA_RED), .VGA_GREEN(VGA_GREEN), .VGA_BLUE(VGA_BLUE), .R(VGA_IN_R), .G(VGA_IN_G), .B(VGA_IN_B),.X(VGA_X), .Y(VGA_Y));
//pipelineOutput
OutputBuffer outputBuffer(.CLK_INPUT(PCLK), .CLK_OUTPUT(VGA_CLK), .WE(1'b1), .inaddr(writeAddr), .indata(pipelineOutput), .outaddr(readAddr), .outdata(outdata));
Pipeline pipeline(.CLK(PCLK), .inX(posX), .inY(posY), .packedinput(pipelineInput), .out(pipelineOutput));

always @(posedge VGA_CLK) begin
  readAddr <= VGA_X;
//  VGA_IN_R <= VGA_X[5:5];
end

assign CAM_XCLK = CLK24;
assign CAM_PWDN = 1'b0;

always @(posedge CLK) begin
  transDone = (transDone | done) && JOY && JOYLEFT && JOYDOWN && JOYRIGHT && JOYUP;
end

endmodule
]=])

  return table.concat(res,"")
end

function modules.axi(inputBytes, outputBytes, stripWidth, outputShift, metadata)
  assert(type(metadata)=="table")

  local totalData = metadata.stripWidth*metadata.stripHeight
  -- zach's interface requires that we write in 128 byte chunks. Just expand out the totaldata to this amount.
  -- it will contain garbage but whatever
  local totalDataDown = totalData/(metadata.downsampleX*metadata.downsampleY)
  totalDataDown = totalDataDown + (8*16-(totalDataDown % (8*16)))
  totalData = totalDataDown * (metadata.downsampleX*metadata.downsampleY)
  assert(totalData % (8*16) == 0)

  return {[=[module PipelineInterface(input CLK,input validIn, output validOut, input []=]..(inputBytes*8-1)..[=[:0] pipelineInput, output []=]..(outputBytes*8-1)..[=[:0] pipelineOutput);
reg [12:0] posX = ]=]..valueToVerilogLL(metadata.padMinX,true,13)..[=[;
reg [12:0] posY = ]=]..valueToVerilogLL(metadata.padMinY,true,13)..[=[;

reg validInD;
reg []=]..(inputBytes*8-1)..[=[:0] pipelineInputD;
reg [15:0] cycleCnt = 0;
reg processStarted = 0;
wire pipelineValidOut;

Pipeline pipeline(.CLK(CLK),.inX(posX),.inY(posY),.packedinput(pipelineInputD),.out(pipelineOutput),.validInNextCycle(validIn),.validOut(pipelineValidOut));

assign validOut = pipelineValidOut && (cycleCnt >= PIPE_DELAY+]=]..(outputShift)..[=[) && (cycleCnt < PIPE_DELAY+]=]..(outputShift+totalData)..[=[);

always @ (posedge CLK) begin
  if (validIn && !validInD) begin
    // this runs the cycle before we start
    posX <= ]=]..valueToVerilogLL(metadata.padMinX,true,13)..[=[;
    posY <= ]=]..valueToVerilogLL(metadata.padMinY,true,13)..[=[;
  end else if(validInD) begin
    if (posX == ]=]..(stripWidth+metadata.padMaxX-1)..[=[) begin
      posX <= ]=]..valueToVerilogLL(metadata.padMinX,true,13)..[=[;
      posY <= posY + 1;
    end else begin
      posX <= posX + 1;
    end
  end else begin
    // prime the pipe
    posX <= ]=]..valueToVerilogLL(stripWidth+metadata.padMaxX-1,true,13)..[=[;
    posY <= ]=]..valueToVerilogLL(metadata.padMinY-1,true,13)..[=[;
  end

  if (validIn && !validInD) begin
    cycleCnt <= 0;
    processStarted <= 1;
  end else if (cycleCnt > PIPE_DELAY+]=]..(outputShift+totalData+10)..[=[) begin
    // prevent wraparound causing it to start sending again
    processStarted <= 0;
  end else if (processStarted) begin 
    cycleCnt <= cycleCnt+1;
  end

  validInD <= validIn;
  pipelineInputD <= pipelineInput;
end
endmodule]=]}

end

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