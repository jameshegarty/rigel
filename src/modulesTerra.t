local simmodules = require("simmodules")
local rigel = require "rigel"
local types = require "types"
local S = require "systolic"
local systolic = S
local Ssugar = require "systolicsugar"
local cstring = terralib.includec("string.h")
local cmath = terralib.includec("math.h")
local cstdlib = terralib.includec("stdlib.h")
local cstdio = terralib.includec("stdio.h")
local fpgamodules = require("fpgamodules")
local SDFRate = require "sdfrate"
local J = require "common"
local err = J.err

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)
local ready = macro(function(i) return `i._2 end)


function rigelGlobalFunctions:terraValue()
  if self.terraValueVar==nil then
    local v
    --if self.direction=="output" then v=self.type:valueToTerra(self.initValue) end
    self.terraValueVar = global( self.type:toTerraType(), v, self.name )
  end
  return self.terraValueVar
end

function rigelGlobalFunctions:terraReady()
  if self.terraReadyVar==nil then
    self.terraReadyVar = global( bool, false, self.name )
  end
  return self.terraReadyVar
end

local MT = {}

function MT.new(Module)
  if Module.methods.init==nil then terra Module:init() end end
  if Module.methods.free==nil then terra Module:free() end end
  if Module.methods.reset==nil then terra Module:reset() end end
  if Module.methods.stats==nil then terra Module:stats(n:&int8) end end

  err( Module.methods.process~=nil or (Module.methods.load~=nil and Module.methods.store~=nil) or (Module.methods.start~=nil and Module.methods.done~=nil), "at least one process/load/store/start/done must be given!")
  assert(Module.methods.init~=nil)
  assert(Module.methods.stats~=nil)
  assert(Module.methods.free~=nil)
  assert(Module.methods.reset~=nil)

  return Module
end

function MT.SoAtoAoS(res,W,H,typelist,asArray)
  local struct PackTupleArrays { }

  terra PackTupleArrays:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    for c = 0, [W*H] do
      escape
      if asArray then
        emit quote (@out)[c] = array( [J.map(J.range(0,#typelist-1), function(i) return `(inp.["_"..i])[c] end ) ] ) end
      else
        -- terra doesn't like us copying large structs by value
        J.map(typelist, function(t,k) emit quote cstring.memcpy( &(@out)[c].["_"..(k-1)], &(inp.["_"..(k-1)])[c], [t:sizeof()]) end end )
      end
      end
    end
  end

  return MT.new(PackTupleArrays)
end

function MT.packTuple(res,typelist)
  local struct PackTuple { ready:bool[#typelist], readyDownstream:bool, outputCount:uint32}

  -- ignore the valid bit on const stuff: it is always considered valid
  local activePorts = {}
  for k,v in ipairs(typelist) do
    assert(types.isType(v))
    table.insert(activePorts, k)
  end
    
  -- the simulator doesn't have true bidirectional dataflow, so fake it with a FIFO
  J.map( activePorts, function(k) table.insert(PackTuple.entries,{field="FIFO"..k, type=simmodules.fifo( typelist[k]:toTerraType(), 8, "PackTuple"..k)}) end )
  
  terra PackTuple:stats(name:&int8) self.outputCount=0 end
  terra PackTuple:reset() [J.map(activePorts, function(i) return quote self.["FIFO"..i]:reset() end end)] end
  terra PackTuple:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    [J.map(activePorts, function(i) return quote 
             if valid(inp.["_"..(i-1)]) and self.ready[i-1] then 
               self.["FIFO"..i]:pushBack(&data(inp.["_"..(i-1)])) 
             end 
                      end end )]

    if self.readyDownstream then
        var hasData = [J.foldt(J.map(activePorts, function(i) return `self.["FIFO"..i]:hasData() end ), J.andopterra, true )]

        escape if DARKROOM_VERBOSE then J.map( typelist, function(t,k) 
--                      if t:const() then emit quote cstdio.printf("PackTuple FIFO %d valid:%d (const)\n",k-1,1) end 
               emit quote cstdio.printf("PackTuple FIFO %d valid:%d (size %d)\n", k-1, self.["FIFO"..k]:hasData(),self.["FIFO"..k]:size()) end end) end end

        if hasData then
          -- terra doesn't like us copying large structs by value
          escape J.map( typelist, function(t,k) 
--                        if t:const() then emit quote cstring.memcpy( &data(out).["_"..(k-1)], &data(inp.["_"..(k-1)]), [t:sizeof()] ) end 
        emit quote cstring.memcpy( &data(out).["_"..(k-1)], self.["FIFO"..k]:popFront(), [t:sizeof()] ) end
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
--          if typelist[i]:const() then
--            emit quote self.ready[i-1] = true end 
--          else
            emit quote self.ready[i-1] = (self.["FIFO"..i]:full()==false) end 
--          end
        end
      end
  end

  return MT.new(PackTuple)
end

function MT.liftBasic(res,f)
  local struct LiftBasic { inner : f.terraModule}
  terra LiftBasic:reset() self.inner:reset() end
  terra LiftBasic:init() self.inner:init() end
  terra LiftBasic:free() self.inner:free() end
  terra LiftBasic:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    self.inner:process(inp,&data(out))
    valid(out) = true
  end
  return MT.new(LiftBasic)
end


function MT.reduceThroughput(res,A,factor)
  local struct ReduceThroughput {ready:bool; phase:int}
  terra ReduceThroughput:reset() self.phase=0 end
  terra ReduceThroughput:process(inp:&A:toTerraType(),out:&rigel.lower(res.outputType):toTerraType()) 
    data(out) = @inp
    valid(out) = self.ready
    self.phase = self.phase+1
    if self.phase==factor then self.phase=0 end
  end
  terra ReduceThroughput:calculateReady() 
    self.ready = (self.phase==0) 
  end

  return MT.new(ReduceThroughput)
end

function MT.waitOnInput(res,f)
  local struct WaitOnInput { inner : f.terraModule, ready:bool }
  terra WaitOnInput:reset() self.inner:reset() end
  terra WaitOnInput:init() self.inner:init() end
  terra WaitOnInput:free() self.inner:free() end
  terra WaitOnInput:stats(name:&int8) self.inner:stats(name) end
  terra WaitOnInput:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return MT.new(WaitOnInput)
end

function MT.liftDecimate(res,f)
  local struct LiftDecimate { inner : f.terraModule; idleCycles:int, activeCycles:int, ready:bool}
  terra LiftDecimate:reset() self.inner:reset(); self.idleCycles = 0; self.activeCycles=0; end
  terra LiftDecimate:init() self.inner:init() end
  terra LiftDecimate:free() self.inner:free() end
  terra LiftDecimate:stats(name:&int8) cstdio.printf("LiftDecimate %s utilization %f\n",name,[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end

  if rigel.isVTrigger(res.inputType) and rigel.isRVTrigger(res.outputType) then
    print("INOUT",res.inputType,res.outputType)
    terra LiftDecimate:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      if @inp then
        self.inner:process(out)
        self.activeCycles = self.activeCycles + 1
      else
        @out = false
        self.idleCycles = self.idleCycles + 1
      end
    end
  else
    terra LiftDecimate:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      if valid(inp) then
        self.inner:process(&data(inp),[&rigel.lower(f.outputType):toTerraType()](out))
        self.activeCycles = self.activeCycles + 1
      else
        valid(out) = false
        self.idleCycles = self.idleCycles + 1
      end
    end
  end

  terra LiftDecimate:calculateReady() self.ready=true end

  return MT.new(LiftDecimate)
end


function MT.RPassthrough(res,f)
  local struct RPassthrough { inner : f.terraModule, readyDownstream:bool, ready:bool}
  terra RPassthrough:reset() self.inner:reset() end
  terra RPassthrough:init() self.inner:init() end
  terra RPassthrough:free() self.inner:free() end
  terra RPassthrough:stats( name : &int8 ) self.inner:stats(name) end
  terra RPassthrough:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    self.inner:process([&rigel.lower(f.inputType):toTerraType()](inp),out)
  end
  terra RPassthrough:calculateReady( readyDownstream:bool ) 
    self.readyDownstream = readyDownstream
    self.inner:calculateReady()
    self.ready = readyDownstream and self.inner.ready
  end

  return MT.new(RPassthrough)
end

function MT.liftHandshake(res,f,delay)
  local struct LiftHandshake{ delaysr: simmodules.fifo( rigel.lower(f.outputType):toTerraType(), delay, "liftHandshake"),
                              inner: f.terraModule, ready:bool, readyDownstream:bool}
  terra LiftHandshake:reset() self.delaysr:reset(); self.inner:reset() end
  terra LiftHandshake:init() self.inner:init() end
  terra LiftHandshake:free() self.inner:free() end
  terra LiftHandshake:stats(name:&int8) 
--    cstdio.printf("LiftHandshake %s, Max input fifo size: %d\n", name, self.fifo:maxSizeSeen())
    self.inner:stats(name) 
  end

  if rigel.isHandshakeTrigger(res.inputType) and rigel.isHandshakeTrigger(res.outputType) then
    terra LiftHandshake:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      if self.readyDownstream then
        if DARKROOM_VERBOSE then cstdio.printf("LIFTHANDSHAKE %s READY DOWNSTRAM = true. ready this = %d\n", f.kind,self.inner.ready) end

        if self.delaysr:size()==delay then
          var ot = self.delaysr:popFront()
          @out = @ot
        else
          @out = false
        end

        var tout : rigel.lower(f.outputType):toTerraType()

        self.inner:process(inp,&tout)
        self.delaysr:pushBack(&tout)
      end
    end
  else
    terra LiftHandshake:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      if self.readyDownstream then
        if DARKROOM_VERBOSE then cstdio.printf("LIFTHANDSHAKE %s READY DOWNSTRAM = true. ready this = %d\n", f.kind,self.inner.ready) end

        if self.delaysr:size()==delay then
          var ot = self.delaysr:popFront()
          valid(out) = valid(ot)
          data(out) = data(ot)
        else
          valid(out) = false
        end

        var tout : rigel.lower(f.outputType):toTerraType()

        self.inner:process(inp,&tout)
        self.delaysr:pushBack(&tout)
      end
    end
  end

  terra LiftHandshake:calculateReady(readyDownstream:bool) 
    self.readyDownstream = readyDownstream
    self.inner:calculateReady()
    self.ready = readyDownstream and self.inner.ready 
  end

  return LiftHandshake
end


function MT.map(res,f,W,H)
  local struct MapModule {fn:f.terraModule}
  terra MapModule:reset() self.fn:reset() end
  terra MapModule:init() self.fn:init() end
  terra MapModule:free() self.fn:free() end
  terra MapModule:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for i=0,W*H do self.fn:process( &((@inp)[i]), &((@out)[i])  ) end
  end
  return MT.new(MapModule)
end

function MT.filterSeq( res, A, W,H, rate, fifoSize, coerce )

  assert(type(coerce)=="boolean")

  if coerce then
    local invrate = rate[2]/rate[1]
    err(math.floor(invrate)==invrate,"filterSeq: in coerce mode, 1/rate must be integer but is "..tostring(invrate))
    
    local outputCount = (W*H*rate[1])/rate[2]
    err(math.floor(outputCount)==outputCount,"filterSeq: in coerce mode, outputCount must be integer, but is "..tostring(outputCount))
    
    local struct FilterSeq { phase:int; cyclesSinceOutput:int; currentFifoSize: int; remainingInputs : int; remainingOutputs : int }
    terra FilterSeq:reset() self.phase=0; self.cyclesSinceOutput=0; self.currentFifoSize=0; self.remainingInputs=W*H; self.remainingOutputs=outputCount; end
    terra FilterSeq:stats(name:&int8) end
    terra FilterSeq:init() end
    terra FilterSeq:free() end

    terra FilterSeq:process( inp : &res.inputType:toTerraType(), out:&rigel.lower(res.outputType):toTerraType() )

      var validIn = inp._1

      var underflow = (self.currentFifoSize==0 and self.cyclesSinceOutput==invrate)
      var fifoHasSpace = (self.currentFifoSize<fifoSize)
      var outaTime : bool = (self.remainingInputs < self.remainingOutputs*invrate)
      var validOut : bool = (((validIn or underflow) and fifoHasSpace) or outaTime)
      
      var currentFifoSize = terralib.select(validOut and self.phase<invrate-1, self.currentFifoSize+1, terralib.select(validOut==false and self.phase==invrate-1 and self.currentFifoSize>0,self.currentFifoSize-1,self.currentFifoSize))
      var cyclesSinceOutput = terralib.select(validOut,0,self.cyclesSinceOutput+1)
      var remainingOutputs = terralib.select( validOut, self.remainingOutputs-1, self.remainingOutputs )
      
      
      -- now set
      self.remainingOutputs = remainingOutputs
      self.cyclesSinceOutput = cyclesSinceOutput
      self.currentFifoSize = currentFifoSize
      valid(out) = validOut
      data(out) = inp._0
      self.remainingInputs = self.remainingInputs - 1
      self.phase = self.phase + 1
      if self.phase==invrate then self.phase = 0 end    
    end

    return FilterSeq

  else
    local struct FilterSeq {  }
    terra FilterSeq:reset()  end
    terra FilterSeq:init()  end
    terra FilterSeq:free()  end
    terra FilterSeq:stats(name:&int8) end

    terra FilterSeq:process( inp : &res.inputType:toTerraType(), out:&rigel.lower(res.outputType):toTerraType() )
      valid(out) = inp._1
      data(out) = inp._0
    end

    return FilterSeq

  end
  
end

function MT.upsampleXSeq(res,A, T, scale, ITYPE )
  local struct UpsampleXSeq { buffer : ITYPE:toTerraType(), phase:int, ready:bool }
  terra UpsampleXSeq:reset() self.phase=0; end
  terra UpsampleXSeq:stats(name:&int8)  end
  terra UpsampleXSeq:init()  end
  terra UpsampleXSeq:free()  end
  terra UpsampleXSeq:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return UpsampleXSeq
end

function MT.triggeredCounter(res,TY,N,stride,X)
  assert(type(stride)=="number")
  assert(X==nil)
  
  local struct TriggeredCounter { buffer : TY:toTerraType(), phase:int, ready:bool }
  terra TriggeredCounter:reset() self.phase=0; end
  terra TriggeredCounter:stats(name:&int8)  end
  terra TriggeredCounter:init() end
  terra TriggeredCounter:free() end
  terra TriggeredCounter:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    valid(out) = true
    if self.phase==0 then
      self.buffer = @(inp)
      data(out) = @(inp)
    else
      data(out) = self.buffer+(self.phase*[stride])
    end

    self.phase = self.phase + 1
    if self.phase==N then self.phase=0 end
  end
  terra TriggeredCounter:calculateReady()  self.ready = (self.phase==0) end

  return MT.new(TriggeredCounter)
end

function MT.triggerCounter(res,N,X)
  assert(X==nil)
  
  local struct TriggerCounter { phase:int, ready:bool }
  terra TriggerCounter:reset() self.phase=0; end
  terra TriggerCounter:process( out : &rigel.lower(res.outputType):toTerraType() )
    self.phase = self.phase + 1
    if self.phase==N then
      self.phase=0
      @out = true
    else
      @out = false
    end
  end

  return MT.new(TriggerCounter)
end

function MT.downsampleYSeqFn(innerInputType,outputType,scale)
   return terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
                             var y = (inp._0)[0]._1
                             data(out) = inp._1
                             valid(out) = (y%scale==0)
                           end
end

function MT.downsampleXSeqFn(innerInputType,outputType,scale)
return terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
                             var x = (inp._0)[0]._0
                             data(out) = inp._1
                             valid(out) = (x%scale==0)
                           end
end

function MT.downsampleXSeqFnShort(innerInputType,outputType,scale,outputT)
    return terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
      for i=0,outputT do (data(out))[i] = (inp._1)[i*scale] end
      valid(out) = true
    end
end

function MT.broadcastWide(ITYPE,OTYPE,T,scale)
return terra(inp : &ITYPE:toTerraType(), out:&OTYPE:toTerraType())
                         for t=0,T do
                           for s=0,scale do
                             (@out)[t*scale+s] = (@inp)[t]
                           end
                         end
                       end
end

function MT.upsampleYSeq( res,A, W, H, T, scale,ITYPE )
  local struct UpsampleYSeq { buffer : (ITYPE:toTerraType())[W/T], phase:int, xpos: int, ready:bool }
  terra UpsampleYSeq:reset() self.phase=0; self.xpos=0; end
  terra UpsampleYSeq:stats(name:&int8)  end
  terra UpsampleYSeq:init() end
  terra UpsampleYSeq:free() end
  terra UpsampleYSeq:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return UpsampleYSeq
end

function MT.interleveSchedule( N, period )
  local struct InterleveSchedule { phase: uint8 }
  terra InterleveSchedule:reset() self.phase=0 end
  terra InterleveSchedule:init()  end
  terra InterleveSchedule:free()  end
  terra InterleveSchedule:process( out : &uint8 )
    @out = (self.phase >> period) % N
    self.phase = self.phase+1
  end

  return InterleveSchedule
end

function MT.pyramidSchedule( depth, wtop, T )
  local struct PyramidSchedule { depth: uint8; w:uint }
  terra PyramidSchedule:reset() self.depth=0; self.w=0 end
  terra PyramidSchedule:init() end
  terra PyramidSchedule:free() end
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

  return PyramidSchedule
end

function MT.toHandshakeArrayOneHot( res,A, inputRates )
  local struct ToHandshakeArrayOneHot {ready:bool[#inputRates], readyDownstream:uint8}
  terra ToHandshakeArrayOneHot:reset()  end
  terra ToHandshakeArrayOneHot:init() end
  terra ToHandshakeArrayOneHot:free() end
  terra ToHandshakeArrayOneHot:stats( name: &int8 ) end
  terra ToHandshakeArrayOneHot:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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
  terra ToHandshakeArrayOneHot:calculateReady( readyDownstream : uint8 )
    self.readyDownstream = readyDownstream
    for i=0,[#inputRates] do 
      self.ready[i] = (i == readyDownstream ) 
      if DARKROOM_VERBOSE then cstdio.printf("HANDSHAKE ARRAY READY DS %d I %d %d\n", readyDownstream,i, self.ready[i] ) end
    end
  end

  return ToHandshakeArrayOneHot
end

function MT.serialize( res, A, inputRates, Schedule)
  local struct Serialize { schedule: Schedule.terraModule; nextId : uint8, ready:uint8, readyDownstream:bool}
  terra Serialize:reset() self.schedule:reset(); self.schedule:process(&self.nextId) end
  terra Serialize:init() self.schedule:init() end
  terra Serialize:free() self.schedule:free() end
  terra Serialize:stats( name: &int8 ) end
  terra Serialize:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return Serialize
end

function MT.demux( res,A, rates)
  -- HACK: we don't have true bidirectional data transfer in the simulator, so fake it with a FIFO
  local struct Demux { fifo: simmodules.fifo( rigel.lower(res.inputType):toTerraType(), 8, "makeHandshake"), ready:bool, readyDownstream:bool[#rates]}
  terra Demux:reset() self.fifo:reset() end
  terra Demux:init() end
  terra Demux:free() end
  terra Demux:stats( name: &int8 ) end
  terra Demux:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return Demux
end

function MT.flattenStreams( res, A, rates)
  local struct FlattenStreams { ready:bool, readyDownstream:bool}
  terra FlattenStreams:reset()  end
  terra FlattenStreams:init()  end
  terra FlattenStreams:free()  end
  terra FlattenStreams:stats( name: &int8 ) end
  terra FlattenStreams:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    valid(out) = (valid(inp)<[#rates])
    data(out) = data(inp)
  end
  terra FlattenStreams:calculateReady( readyDownstream : bool )
    self.readyDownstream = readyDownstream
    self.ready = readyDownstream
  end

  return FlattenStreams
end

function MT.broadcastStream(res,A,N)
  local struct BroadcastStream {ready:bool, readyDownstream:bool[N]}
  terra BroadcastStream:reset() end
  terra BroadcastStream:init() end
  terra BroadcastStream:free() end
  terra BroadcastStream:stats( name: &int8) end

  if rigel.isHandshakeTrigger(res.inputType) and rigel.isHandshakeTriggerArray(res.outputType) then
    terra BroadcastStream:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      for i=0,N do
        if self.ready then -- all of readyDownstream are true
          (@out)[i] = @inp
        else
          (@out)[i] = false
        end
      end
    end

  else
    terra BroadcastStream:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      for i=0,N do
        if self.ready then -- all of readyDownstream are true
          data((@out)[i]) = data(inp)
          valid((@out)[i]) = valid(inp)
        else
          valid((@out)[i]) = false
        end
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

  return BroadcastStream
end

function MT.posSeq(res,W,H,T)
  local struct PosSeq { x:uint16, y:uint16 }
  terra PosSeq:reset() self.x=0; self.y=0 end
  terra PosSeq:process( out : &rigel.lower(res.outputType):toTerraType() )
    for i=0,T do 
      (@out)[i] = {self.x,self.y}
      self.x = self.x + 1
      if self.x==W then self.x=0; self.y=self.y+1 end
      if self.y==H then self.y=0 end
    end
  end

  return MT.new(PosSeq)
end

function MT.pad( res, A, W, H, L, R, B, Top, Value )
  local struct Pad {}

  local outW = W+L+R
  
  terra Pad:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    for y=0,H+B+Top do
      for x=0,W+L+R do
        if x>=L and x<W+L and y>=B and y<H+B then
          (@out)[x+y*outW] = (@inp)[(x-L)+(y-B)*W]
        else
          (@out)[x+y*outW] = [Value]
        end
      end
    end
  end
  
  return MT.new(Pad)
end

function MT.downsample( res, A, W, H, scaleX, scaleY )
  local struct Downsample {}
  terra Downsample:reset() end
  terra Downsample:init() end
  terra Downsample:free() end
  terra Downsample:stats(name:&int8) end -- not particularly interesting
  
  local outW = W/scaleX
  
  terra Downsample:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    for y=0,H/scaleY do
      for x=0,W/scaleX do
        (@out)[x+y*outW] = (@inp)[(x*scaleX)+(y*scaleY)*W]
      end
    end
  end

  return Downsample
end

function MT.upsample( res, A, W, H, scaleX, scaleY )
  local struct Upsample {}
  terra Upsample:reset() end
  terra Upsample:init() end
  terra Upsample:free() end
  terra Upsample:stats(name:&int8) end -- not particularly interesting
  
  local outW = W*scaleX
  
  terra Upsample:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    for y=0,H*scaleY do
      for x=0,W*scaleX do
        (@out)[x+y*outW] = (@inp)[(x/scaleX)+(y/scaleY)*W]
      end
    end
  end
  
  return Upsample
end


function MT.padSeq( res, A, W, H, T, L, R, B, Top, Value )

  local struct PadSeq {posX:int; posY:int, ready:bool}
  terra PadSeq:reset() self.posX=0; self.posY=0; end
  terra PadSeq:init() end
  terra PadSeq:free() end
  terra PadSeq:stats(name:&int8) end -- not particularly interesting
  terra PadSeq:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    var interior : bool = (self.posX>=L and self.posX<(L+W) and self.posY>=B and self.posY<(B+H))

--    cstdio.printf("PADPOS %d %d, %d %d %d %d, %d %d\n",self.posX,self.posY,L,R,B,Top,W,H)
    valid(out) = true
    if interior then
      data(out) = @inp
    else
      data(out) = arrayof([A:toTerraType()],[J.broadcast(A:valueToTerra(Value),T)])
--      cstdio.printf("INBORDER\n")
    end
    
    self.posX = self.posX+T;
    if self.posX==(W+L+R) then
      self.posX=0;
      self.posY = self.posY+1;
    end

    if self.posY==(H+B+Top) then
      self.posY = 0
    end
--    cstdio.printf("PAD x %d y %d inner %d\n",self.posX,self.posY,inner)
  end
  terra PadSeq:calculateReady()  self.ready = (self.posX>=L and self.posX<(L+W) and self.posY>=B and self.posY<(B+H)) end

  return PadSeq
end

function MT.changeRate(res, A, H, inputRate, outputRate,maxRate,outputCount,inputCount )

  local struct ChangeRate { buffer : (A:toTerraType())[maxRate*H]; phase:int, ready:bool}

  terra ChangeRate:stats(name:&int8) end
  terra ChangeRate:init() end
  terra ChangeRate:free() end

  if inputRate>outputRate then
    terra ChangeRate:reset() self.phase = 0; end
    terra ChangeRate:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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
  else
    terra ChangeRate:reset() self.phase = 0; end
    terra ChangeRate:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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
  end

  return MT.new(ChangeRate)
end

function MT.linebuffer(res, A, w, h, T, ymin)
  local struct Linebuffer { SR: simmodules.shiftRegister( A:toTerraType(), w*(-ymin)+T, "linebuffer")}
  terra Linebuffer:reset() self.SR:reset() end
  terra Linebuffer:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return MT.new(Linebuffer)
end

function MT.sparseLinebuffer( A, imageW, imageH, rowWidth, ymin, defaultValue )
  assert(ymin<=0)

  local struct SparseLinebuffer { 
    currentX : uint16,
--    xlocs : uint[-ymin], 
--    staging : (A:toTerraType())[-ymin+1]
    -- index 0 is ymin+1 row, index 1 is ymin+2 row etc
    -- remember ymin is <0
    fifos : (simmodules.fifo( A:toTerraType(), rowWidth, "sparseLinebuffer FIFO" ))[-ymin]
    xlocfifos : (simmodules.fifo( uint16, rowWidth, "sparseLinebuffer FIFO" ))[-ymin]
  }


  -- the staging register should contain the next value to write out. so X value in staging register should be > currentX

  -- if X value in staging register equals currentX, write it out, and read next value from FIFO.
  -- if the next FIFO is full, drop the value instead of writing it.

  -- if input fifo to this line is empty: add a bogus X value (x>imageW) to staging register so that if there are multiple empty lines, 
  -- we don't write out that value twice.


  terra SparseLinebuffer:reset() 
    self.currentX = 0

    for i=0,-ymin do
      --self.xlocs[i] = imageW -- invalid value
      self.fifos[i]:reset()
      self.xlocfifos[i]:reset()
    end
  end

  local inputType = tuple( A:toTerraType(), bool )
  local outputType = (A:toTerraType())[-ymin+1]

  terra SparseLinebuffer:process( inp : &inputType, out : &outputType )

    -- do it in this order to simulate non blocking reads
    for outi=0,-ymin do

      if self.xlocfifos[outi]:hasData() and @(self.xlocfifos[outi]:peekFront(0))==self.currentX then
        -- we are ready to read
        var dat = @(self.fifos[outi]:popFront())
        var xloc = @(self.xlocfifos[outi]:popFront())
        (@out)[outi] = dat

        -- preload the next value into staging
        if outi>0 then
          self.fifos[outi-1]:pushBack( &dat )
          self.xlocfifos[outi-1]:pushBack( &xloc )
        end
      else
        (@out)[outi] = [A:valueToTerra(defaultValue)]
      end
    end

    if inp._1 and self.fifos[-ymin-1]:full()==false then
      -- this token is valid, write it out
      (@out)[-ymin] = inp._0

      self.xlocfifos[-ymin-1]:pushBack( &self.currentX )
      self.fifos[-ymin-1]:pushBack( &(inp._0) )
    else
      (@out)[-ymin] = [A:valueToTerra(defaultValue)]
    end

    self.currentX = self.currentX+1
    if self.currentX==imageW then self.currentX=0 end
  end

  return MT.new(SparseLinebuffer)
end

function MT.SSR(res, A, T, xmin, ymin )
  local struct SSR {SR:(A:toTerraType())[-xmin+T][-ymin+1]}
  terra SSR:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
    for y=0,-ymin+1 do for x=0,-xmin do self.SR[y][x] = self.SR[y][x+T] end end
    for y=0,-ymin+1 do for x=-xmin,-xmin+T do self.SR[y][x] = (@inp)[y*T+(x+xmin)] end end

    -- write to output
    for y=0,-ymin+1 do for x=0,-xmin+T do (@out)[y*(-xmin+T)+x] = self.SR[y][x] end end
  end

  return MT.new(SSR)
end

function MT.SSRPartial(res,A, T, xmin, ymin, stride, fullOutput)
  local struct SSRPartial {phase:int; SR:(A:toTerraType())[-xmin+1][-ymin+1]; activeCycles:int; idleCycles:int, ready:bool}
  terra SSRPartial:reset() self.phase=0; self.activeCycles=0;self.idleCycles=0; end
  terra SSRPartial:stats(name:&int8) cstdio.printf("SSRPartial %s T=%f utilization:%f\n",name,[float](T),[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end
  terra SSRPartial:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    var phaseAtStart = self.phase

    if self.ready then
      -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
      var SStride = 1
      for y=0,-ymin+1 do for x=0,-xmin do self.SR[y][x] = self.SR[y][x+SStride] end end
      for y=0,-ymin+1 do for x=-xmin,-xmin+SStride do self.SR[y][x] = (@inp)[y*SStride+(x+xmin)] end end
      self.phase = terralib.select([T==1],0,1)
    else
      if self.phase<[1/T]-1 then 
        self.phase = self.phase + 1 
      else
        self.phase = 0
      end
    end

    var W : int = [(-xmin+1)*T]
    var Wtotal = -xmin+1
    if fullOutput then W = Wtotal end
    for y=0,-ymin+1 do for x=0,W do data(out)[y*W+x] = self.SR[y][J.fixedModulus(x+phaseAtStart*stride,Wtotal)] end end
    valid(out)=true
  end
  terra SSRPartial:calculateReady()  self.ready = (self.phase==0) end

  return MT.new(SSRPartial)
end

function MT.makeHandshake(res, f, tmuxRates, nilhandshake )
  local delay = math.max( 1, f.delay )
  --assert(delay>0)
  -- we don't need an input fifo here b/c ready is always true
  local struct MakeHandshake{ delaysr: simmodules.fifo( rigel.lower(res.outputType):toTerraType(), delay, "makeHandshake"),
                              inner: f.terraModule,
                            ready:bool, readyDownstream:bool}
  terra MakeHandshake:reset() self.delaysr:reset(); self.inner:reset() end
  terra MakeHandshake:init() self.inner:init() end
  terra MakeHandshake:free() self.inner:free() end
  terra MakeHandshake:stats( name : &int8 ) self.inner:stats(name) end
  
  -- if inner function is const, consider input to always be valid
  local innerconst = false

  local validFalse = false
  if tmuxRates~=nil then validFalse = #tmuxRates end

  if f.inputType==types.null() and nilhandshake==false then
    terra MakeHandshake:process( out : &rigel.lower(res.outputType):toTerraType())
      if self.readyDownstream then
        if self.delaysr:size()==delay then
          var ot = self.delaysr:popFront()
          valid(out) = valid(ot)
          cstring.memcpy( &data(out), &data(ot), [rigel.lower(f.outputType):sizeof()])
        else
          valid(out)=validFalse
        end

        var tout : rigel.lower(res.outputType):toTerraType()
        valid(tout) = true
        self.inner:process(&data(tout))
        self.delaysr:pushBack(&tout)
      end
    end
  elseif f.inputType==types.null() and nilhandshake==true then
    terra MakeHandshake:process( inp : &bool,
                                 out : &rigel.lower(res.outputType):toTerraType())
      if self.readyDownstream then
        if self.delaysr:size()==delay then
          var ot = self.delaysr:popFront()
          valid(out) = valid(ot)
          cstring.memcpy( &data(out), &data(ot), [rigel.lower(f.outputType):sizeof()])
        else
          valid(out)=validFalse
        end

        var tout : rigel.lower(res.outputType):toTerraType()
        
        valid(tout) = @inp;

        if (@inp~=validFalse) or innerconst then self.inner:process(&data(tout)) end -- don't bother if invalid

        self.delaysr:pushBack(&tout)
      end
    end
  elseif f.outputType==types.null() and nilhandshake==false then
    terra MakeHandshake:process( inp : &rigel.lower(res.inputType):toTerraType())
      if DARKROOM_VERBOSE then cstdio.printf("MakeHandshake %s IV %d readyDownstream=true\n",f.kind,valid(inp)) end
      if (valid(inp)~=validFalse) then self.inner:process(&data(inp)) end -- don't bother if invalid
    end
  elseif f.outputType==types.null() and nilhandshake==true then
    terra MakeHandshake:process( inp : &rigel.lower(res.inputType):toTerraType(), 
                                 out : &bool)
      if self.readyDownstream then
        if self.delaysr:size()==delay then
          var ot = self.delaysr:popFront()
          @out = @ot
        else
          @out=validFalse
        end

        var tout : bool
        
        tout = valid(inp);

        if (valid(inp)~=validFalse) then self.inner:process(&data(inp)) end -- don't bother if invalid

        self.delaysr:pushBack(&tout)
      end
    end
  elseif f.inputType==types.null() and f.outputType==types.null() and nilhandshake==false then
    assert(false)
  else
    terra MakeHandshake:process( inp : &rigel.lower(res.inputType):toTerraType(), 
                               out : &rigel.lower(res.outputType):toTerraType())

      --if DARKROOM_VERBOSE then cstdio.printf("MakeHandshake %s IV %d readyDownstream=true\n",f.kind,valid(inp)) end
      if self.delaysr:size()==delay then
        -- we've waited enough cycles
        var ot = self.delaysr:peekFront(0)
        valid(out) = valid(ot)
        cstring.memcpy( &data(out), &data(ot), [rigel.lower(f.outputType):sizeof()])
        
        if self.readyDownstream then
          self.delaysr:popFront()
        end
      else
        valid(out)=validFalse
      end
      
      if self.readyDownstream then
        var tout : rigel.lower(res.outputType):toTerraType()
        
        valid(tout) = valid(inp);
        if (valid(inp)~=validFalse) or innerconst then self.inner:process(&data(inp),&data(tout)) end -- don't bother if invalid
        
        self.delaysr:pushBack(&tout)
      end
    end
  end

  if f.outputType==types.null() and nilhandshake==false then
    terra MakeHandshake:calculateReady( ) self.ready = true; self.readyDownstream = true; end
  else
    terra MakeHandshake:calculateReady( readyDownstream: bool ) self.ready = readyDownstream; self.readyDownstream = readyDownstream end
  end

  return MT.new(MakeHandshake)
end


function MT.fifo( res, A, size, nostall, W, H, T, csimOnly)
  local struct Fifo { fifo : simmodules.fifo(A:toTerraType(),size,"fifofifo"), ready:bool, readyDownstream:bool }
  terra Fifo:reset() self.fifo:reset() end
  terra Fifo:stats(name:&int8)  end
  terra Fifo:store( inp : &rigel.lower(res.inputType):toTerraType())
    if DARKROOM_VERBOSE then cstdio.printf("FIFO STORE ready:%d valid:%d\n",self.ready,valid(inp)) end
    -- if ready==false, ignore then input (if it's behaving correctly, the input module will be stalled)
    -- 'ready' argument was the ready value we agreed on at start of cycle. Note this this may change throughout the cycle! That's why we can't just call the :storeReady() method
    if valid(inp) and self.ready then 
      if DARKROOM_VERBOSE then cstdio.printf("FIFO STORE, valid input\n") end
      self.fifo:pushBack(&data(inp)) 
    end
  end
  terra Fifo:load( out : &rigel.lower(res.outputType):toTerraType())
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

  return MT.new(Fifo)
end


FR = terralib.includecstring([[
#include <stdio.h>
#include <stdlib.h>
void fr(FILE* file,unsigned char** mem, unsigned int* fsize){
fseek(file,0,SEEK_END);
*fsize = ftell(file);
fseek(file,0,SEEK_SET);
*mem = malloc(*fsize);
fread(*mem,1,*fsize,file);
}

]])

function MT.dram( res, A, delay, filename )
  local struct Dram { fifo : simmodules.fifo(int,delay,"dramfifo"), ready:bool, readyDownstream:bool, mem:&A:toTerraType(), fsize:uint }
  terra Dram:reset() self.fifo:reset() end

  terra Dram:init() 
    var file = cstdio.fopen(filename, "rb") 
    [J.darkroomAssert](file~=nil, ["file "..filename.." doesnt exist"])

    --var n : int = 0
    --while cstdio.fread(self.mem+n,1,[A:sizeof()],file)>0 do n=n+1 end
    FR.fr(file,[&&uint8](&self.mem),&self.fsize)
    
    cstdio.fclose(file)
  end

  terra Dram:free() cstdlib.free(self.mem) end

  local VV = false

  terra Dram:store( inp : &rigel.lower(res.inputType):toTerraType())
    if VV or DARKROOM_VERBOSE then cstdio.printf("DRAM ADDR REQUEST ready:%d valid:%d\n",self.ready,valid(inp)) end
    -- if ready==false, ignore then input (if it's behaving correctly, the input module will be stalled)
    -- 'ready' argument was the ready value we agreed on at start of cycle. Note this this may change throughout the cycle! That's why we can't just call the :storeReady() method
    if valid(inp) and self.ready then
      var a :int = data(inp)
      if VV or DARKROOM_VERBOSE then cstdio.printf("DRAM STORE, valid input %d\n",a) end

      if a>self.fsize then
        cstdio.printf("DRAM SEGFAULT %d\n",a)
      end
      
      self.fifo:pushBack(&a)
    elseif self.ready then
      if VV or DARKROOM_VERBOSE then cstdio.printf("DRAM STORE, invalid input, ready=%d\n",self.ready) end
      var a : int = -1
      self.fifo:pushBack(&a)
    end
  end

  terra Dram:load( out : &rigel.lower(res.outputType):toTerraType())
    if self.readyDownstream then
      if self.fifo:hasData() and @(self.fifo:peekFront(0))>=0 then
        var addr : int = @(self.fifo:popFront())
        if VV or DARKROOM_VERBOSE then cstdio.printf("DRAM LOAD, hasData. addr=%d size=%d\n", addr,self.fifo:size()) end
        valid(out) = true


        data(out) = self.mem[addr]
      else
        if VV or DARKROOM_VERBOSE then cstdio.printf("DRAM LOAD, no data. sizee=%d\n", self.fifo:size()) end
        valid(out) = false

        if self.fifo:hasData() then
          -- remove bubbles
          self.fifo:popFront()
        end
      end
    else
      if VV or DARKROOM_VERBOSE then cstdio.printf("DRAM LOAD, not ready. FIFO size: %d\n", self.fifo:size()) end
    end
  end

  terra Dram:calculateStoreReady() self.ready = (self.fifo:full()==false) end
  terra Dram:calculateLoadReady(readyDownstream:bool) self.readyDownstream = readyDownstream end

  return MT.new(Dram)
end

function MT.lut(inputType, outputType, values, inputCount)
  local struct LUTModule { lut : (outputType:toTerraType())[inputCount] }
  terra LUTModule:reset() self.lut = arrayof([outputType:toTerraType()], values) end
  terra LUTModule:process( inp:&inputType:toTerraType(), out:&outputType:toTerraType())
    @out = self.lut[@inp]
  end

  return MT.new(LUTModule)
end

function MT.reduce(res,f, W, H)
  local struct ReduceModule { inner: f.terraModule }
  terra ReduceModule:reset() self.inner:reset() end

  -- the execution order needs to match the hardware
  local inp = symbol( &res.inputType:toTerraType() )
  local mself = symbol( &ReduceModule )
  local t = J.map(J.range(0,W*H-1), function(i) return `(@inp)[i] end )

  local foldout = J.foldt(t, function(a,b) return quote 
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

  return MT.new(ReduceModule)
end

function MT.reduceSeq(res,f, T)
  local struct ReduceSeq { phase:int; result : f.outputType:toTerraType(); inner : f.terraModule}
  terra ReduceSeq:reset() self.phase=0; self.inner:reset() end
  terra ReduceSeq:process( inp : &f.outputType:toTerraType(), out : &rigel.lower(res.outputType):toTerraType())
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

  return MT.new(ReduceSeq)
end

function MT.overflow(res,A,count)
  local struct Overflow {cnt:int}
  terra Overflow:reset() self.cnt=0 end
  terra Overflow:process( inp : &A:toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    data(out) = @inp
    if self.cnt>=count then
      cstdio.printf("OUTPUT OVERFLOW %d\n",self.cnt)
    end
    valid(out) = (self.cnt<count)
    self.cnt = self.cnt+1
  end

  return MT.new(Overflow)
end


function MT.underflow(res,  A, count, cycles, upstream, tooSoonCycles ) 
  local struct Underflow {ready:bool; readyDownstream:bool;cycles:uint32; outputCount:uint32}
  terra Underflow:reset() self.cycles=0; self.outputCount=0 end
  terra Underflow:process( inp : &rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  terra Underflow:calculateReady(readyDownstream:bool) self.ready = readyDownstream; self.readyDownstream=readyDownstream end
  return MT.new(Underflow)
end

function MT.cycleCounter( res, A, count )
  local struct CycleCounter {ready:bool; readyDownstream:bool; cycles:uint32; outputCount:uint32}
  terra CycleCounter:reset() self.cycles=0; self.outputCount=0 end
  terra CycleCounter:process( inp : &rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  terra CycleCounter:calculateReady(readyDownstream:bool) self.ready = readyDownstream; self.readyDownstream=readyDownstream end

  return MT.new(CycleCounter)
end

function MT.lift( inputType, outputType, terraFunction, systolicInput, systolicOutput)
  err(types.isType(inputType),"modules terra lift: input type must be type")


  local struct LiftModule {}

  if terraFunction==nil and systolicInput~=nil and systolicOutput~=nil then
    if outputType==nil then
      outputType = systolicOutput.type
    end

    err(types.isType(outputType),"modules terra lift: output type must be type")
    
    local inpS = symbol(systolicInput.type:toTerraType())
    local symbs = {}
    symbs[systolicInput.name] = inpS
    local terraOut = systolicOutput:toTerra(symbs)

    if inputType==types.null() then
      terra LiftModule:process(out:&rigel.lower(outputType):toTerraType())
        @out = [terraOut]
      end
    else
      terra LiftModule:process(inp:&rigel.lower(inputType):toTerraType(),out:&rigel.lower(outputType):toTerraType())
        var [inpS] = @inp
        @out = [terraOut]
      end
    end
  elseif type(terraFunction)=="function" then
    -- terraFunction is actually a lua function that produces terra Module when called.
    -- keep the lazyness
    
    return function()
      local tfn = terraFunction()
      if outputType==types.null() then
        terra LiftModule:process(inp:&rigel.lower(inputType):toTerraType()) tfn(inp) end
      else
        terra LiftModule:process(inp:&rigel.lower(inputType):toTerraType(),out:&rigel.lower(outputType):toTerraType()) tfn(inp,out) end
      end
      return MT.new(LiftModule)
    end
  else
    err(types.isType(outputType),"modules terra lift: output type must be type")
    assert(inputType~=types.null())
    --assert(outputType~=types.null())
    if outputType==types.null() and terraFunction==nil then
      terra LiftModule:process(inp:&rigel.lower(inputType):toTerraType()) end
    elseif outputType==types.null() then
      terra LiftModule:process(inp:&rigel.lower(inputType):toTerraType()) terraFunction(inp) end
    else
      terra LiftModule:process(inp:&rigel.lower(inputType):toTerraType(),out:&rigel.lower(outputType):toTerraType()) terraFunction(inp,out) end
    end
  end

  return MT.new(LiftModule)
end

function MT.constSeq(res, value, A, w, h, T,W )
  local struct ConstSeqState {phase : int; data : (A:toTerraType())[h*W][1/T] }
  local mself = symbol(&ConstSeqState,"mself")
  local initstats = {}

  for C=0,(1/T)-1 do
    for y=0,h-1 do
      for x=0,W-1 do
        table.insert( initstats, quote mself.data[C][y*W+x] = [A:valueToTerra(value[x+y*w+C*W+1])] end )
      end
    end
  end
  terra ConstSeqState.methods.reset([mself]) mself.phase = 0; [initstats] end
  terra ConstSeqState:process( out : &rigel.lower(res.outputType):toTerraType() )
    @out = self.data[self.phase]
    self.phase = self.phase + 1
    if self.phase == [1/T] then self.phase = 0 end
  end

  return MT.new(ConstSeqState)
end

function MT.freadSeq(filename,ty)
  local struct FreadSeq { file : &cstdio.FILE }
  terra FreadSeq:init() 
    self.file = cstdio.fopen(filename, "rb") 
    [J.darkroomAssert](self.file~=nil, ["file "..filename.." doesnt exist"])
  end
  terra FreadSeq:free() cstdio.fclose(self.file) end
  terra FreadSeq:reset() end
  terra FreadSeq:process(out : &ty:toTerraType())
    var outBytes = cstdio.fread(out,1,[ty:sizeof()],self.file)
    [J.darkroomAssert](outBytes==[ty:sizeof()], "Error, freadSeq failed, probably end of file?")
  end

  return MT.new(FreadSeq)
end

function MT.fwriteSeq(filename,ty,passthrough)
  local struct FwriteSeq { file : &cstdio.FILE }
  terra FwriteSeq:init()
    self.file = cstdio.fopen(filename, "wb") 
    if self.file==nil then cstdio.perror(["Error opening "..filename.." for writing"]) end
    [J.darkroomAssert]( self.file~=nil, ["Error opening "..filename.." for writing"] )
  end
  terra FwriteSeq:free()
    cstdio.fclose(self.file)
  end
  terra FwriteSeq:reset() 
  end

  if passthrough then
    terra FwriteSeq:process(inp : &ty:toTerraType(), out : &ty:toTerraType())
      cstdio.fwrite(inp,[ty:sizeof()],1,self.file)
      cstring.memcpy(out,inp,[ty:sizeof()])
    end
  else
    terra FwriteSeq:process(inp : &ty:toTerraType())
      cstdio.fwrite(inp,[ty:sizeof()],1,self.file)
    end
  end

  return MT.new(FwriteSeq)
end

function MT.seqMap(f, W, H, T)
  local struct SeqMap { inner: f.terraModule}
  terra SeqMap:reset() self.inner:reset() end
  terra SeqMap:stats() self.inner:stats("TOP") end
  terra SeqMap:process( inp:&types.null():toTerraType(), out:&types.null():toTerraType())
    var o : darkroom.lower(f.outputType):toTerraType()
    for i=0,W*H do self.inner:process(nil,&o) end
  end

  return SeqMap
end

-- simCycles: run the simulation for at least this number of cycles
function MT.seqMapHandshake(f, inputType, tapInputType, tapValue, inputCount, outputCount, axi, readyRate, simCycles, X)
  assert(X==nil)

  if simCycles==nil then simCycles=0 end
  
  local struct SeqMap { inner: f.terraModule}
  terra SeqMap:reset() self.inner:reset() end
  terra SeqMap:init() self.inner:init() end
  terra SeqMap:free() self.inner:free() end
  terra SeqMap:stats() self.inner:stats("TOP") end

  local innerinp = symbol(darkroom.lower(f.inputType):toTerraType(), "innerinp")
  local assntaps = quote end
  if tapInputType~=nil then assntaps = quote data(innerinp) = {nil,[tapInputType:valueToTerra(tapValue)]} end end

  terra SeqMap:process( inp:&types.null():toTerraType(), out:&types.null():toTerraType())
    var [innerinp]
    [assntaps]

    var o : darkroom.lower(f.outputType):toTerraType()
    var inpAddr = 0
    var outAddr = 0
    var downstreamReady = 0
    var cycles : uint = 0

    while [J.sel(inputType==types.null(),false,`inpAddr<inputCount)] or outAddr<outputCount or (simCycles~=0 and cycles<simCycles) do
      [J.sel(inputType==types.null(),quote end, quote valid(innerinp)=(inpAddr<inputCount) end)]
      self.inner:calculateReady(downstreamReady==0)
      if DARKROOM_VERBOSE then cstdio.printf("---------------------------------- RUNPIPE inpAddr %d/%d outAddr %d/%d ready %d downstreamReady %d cycle %d\n", inpAddr, inputCount, outAddr, outputCount, [J.sel(inputType==types.null(),true,`self.inner.ready)], downstreamReady==0, cycles) end
      [J.sel(inputType==types.null(),quote self.inner:process(&o) end, quote self.inner:process(&innerinp,&o) end)]
      [J.sel(inputType==types.null(),quote end, quote if self.inner.ready then inpAddr = inpAddr + 1 end end)]
      if valid(o) and (downstreamReady==0) then outAddr = outAddr + 1 end
      downstreamReady = downstreamReady+1
      if downstreamReady==readyRate then downstreamReady=0 end
      cycles = cycles + 1
    end

    return cycles
  end

  return SeqMap
end

function MT.cropSeqFn(innerInputType,outputType,A, W, H, T, L, R, B, Top )
return terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
                             var x,y = (inp._0)[0]._0, (inp._0)[0]._1
                             data(out) = inp._1
                             valid(out) = (x>=L and y>=B and x<W-R and y<H-Top)
                             if DARKROOM_VERBOSE then cstdio.printf("CROP x %d y %d VO %d\n",x,y,valid(out)) end
                           end

end

function MT.crop( res, A, W, H, L, R, B, Top )
  local struct Crop {}
  terra Crop:reset() end
  terra Crop:init() end
  terra Crop:free() end
  terra Crop:stats(name:&int8) end -- not particularly interesting
  
  local outW = W-L-R
  
  terra Crop:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    for y=0,H-B-Top do
      for x=0,W-L-R do
        (@out)[x+y*outW] = (@inp)[(x+L)+(y+B)*W]
      end
    end
  end
  
  return Crop
end


function MT.lambdaCompile(fn)
  local inputSymbol
  if fn.input~=nil then inputSymbol = symbol( &rigel.lower(fn.input.type):toTerraType(), "lambdainput" ) end
  
  local outputSymbol = symbol( &rigel.lower(fn.output.type):toTerraType(), "lambdaoutput" )
  
  local stats = {}
  local resetStats = {}
  local initStats = {}
  local freeStats = {}
  local readyStats = {}
  local statStats = {}
  
  local Module = terralib.types.newstruct("lambda"..fn.name.."_module")
  Module.entries = terralib.newlist( {} )
  
  local readyInput
  if rigel.hasReady(fn.output.type) then
    local RIT = rigel.extractReady(fn.output.type):toTerraType()
    readyInput = symbol(RIT, "readyinput")
    table.insert( Module.entries, {field="readyDownstream", type=rigel.extractReady(fn.output.type):toTerraType()} )
  end

  if rigel.hasReady(fn.inputType) or rigel.isRV(fn.output.type) then
    table.insert( Module.entries, {field="ready", type=rigel.extractReady(fn.input.type):toTerraType()} )
  end
  
  local mself = symbol( &Module, "module self" )
  
  if fn.instances~=nil then for k,v in pairs(fn.instances) do 
    err(v.fn.terraModule~=nil, "Missing terra module for "..v.fn.kind)
    table.insert( Module.entries, {field=v.name, type=v.fn.terraModule} ) end 
  end

  fn.output:visitEach(
    function(n, inputs)
      if n==fn.output then
      elseif n.kind=="applyRegStore" then
      elseif n.kind~="input" then
        table.insert( Module.entries, {field="simstateoutput_"..n.name, type=rigel.lower(n.type):toTerraType()} )
      end

      if n.kind=="apply" then
        table.insert( Module.entries, {field=n.name, type=n.fn.terraModule} )
      end
    end)
  
  local readyOutput
    
    -- build ready calculation
  if rigel.isRV(fn.output.type) or fn.output:outputStreams()>0 or rigel.streamCount(fn.inputType)>0 or rigel.handshakeMode(fn.output) then
    
    fn.output:visitEachReverseBreakout(
      function(n, args)

        -- special case: multiple stream output with multiple consumers
        -- the only time this should happen is if everything is selectstreamed
        if n:outputStreams()>1 and n:parentCount(fn.output)>1 then

          -- all of then N consumers should be selectStream
          local list = {}
          for dsNode, _ in n:parents(fn.output) do
            if dsNode.kind=="selectStream" then
              err(list[dsNode.i+1]==nil,"Error, 2 selectStream reads of same signal! "..n.loc)
              list[dsNode.i+1] = `[args[dsNode]][dsNode.i]
            else
              err( false, "Error, a multi-stream node is being consumed by something other than a selectStream? (a "..dsNode.kind..") "..n.loc )
            end
          end

          err( n:outputStreams()==#list and #list==J.keycount(list),"a multi-stream node has an incorrect number of consumers. Has "..#list.." consumers but expected "..tostring(n:outputStreams())..". "..n.loc)

          if n.kind=="input" then
            readyOutput = `array(list)
return {readyOutput}
          else
            table.insert( readyStats, quote mself.[n.name]:calculateReady(array(list)) end )
return {`mself.[n.name].ready}
          end
        end

        local arg
  
        if J.keycount(args)==0 then
          -- special case: the input node
          arg = readyInput
        else
          if J.keycount(args)>1 then
            print("Error: a handshook node ("..tostring(n.name)..") has multiple consumers! This should only happen with broadcastStream! "..n.loc)
            for parentNode,parentValue in pairs(args) do
              print("Consumer "..tostring(parentNode).." "..parentNode.loc)
            end
            assert(false)
          end
          
          for k,v in pairs(args) do
            assert(terralib.isquote(v) or terralib.issymbol(v))
            arg=v
          end
        end

        assert(rigel.hasReady(fn.output.type)==false or terralib.isquote(arg) or terralib.issymbol(arg))
        
        local res
        if n.kind=="input" then
          assert(readyOutput==nil)
          readyOutput = arg
          assert(readyOutput~=nil)
        elseif n.kind=="apply" then
          if rigel.hasReady(n.fn.outputType)==false or rigel.isV(n.fn.inputType) then
            table.insert( readyStats, quote mself.[n.name]:calculateReady() end )
            res = {`mself.[n.name].ready}
          else
            table.insert( readyStats, quote mself.[n.name]:calculateReady(arg) end )
            res = {`mself.[n.name].ready}
          end
        elseif n.kind=="applyMethod" then
          if n.fnname=="load" then 
            -- load has nothing upstream, so whatever
            table.insert( readyStats, quote mself.[n.inst.name]:calculateLoadReady(arg) end ) 
          elseif n.fnname=="store" then
            -- ready value may change throughout the cycle (as loads happen etc). So we store the agreed upon value and use that
            table.insert( readyStats, quote mself.[n.inst.name]:calculateStoreReady() end ) 
            res = {`mself.[n.inst.name].ready}
          elseif n.fnname=="start" then
            table.insert( readyStats, quote mself.[n.inst.name]:calculateStartReady(arg) end ) 
            res = {`mself.[n.inst.name].startReady}
          elseif n.fnname=="done" then
            table.insert( readyStats, quote mself.[n.inst.name]:calculateDoneReady() end ) 
            res = {`mself.[n.inst.name].doneReady}
          else
            assert(false)
          end
        elseif n.kind=="concat" or n.kind=="concatArray2d" then
          res = {}
          for k,_ in ipairs(n.inputs) do
            res[k] = `[arg][ [k-1] ]
          end
        elseif n.kind=="statements" then
          res = {readyInput}
          for i=2,#n.inputs do 
            table.insert( res, `true )
          end
        elseif n.kind=="selectStream" then
          res = symbol(bool[n.inputs[1]:outputStreams()])
          table.insert( readyStats, quote var [res]; [res][n.i] = [arg] end )
          res = {res}
        else
          print(n.kind)
          assert(false)
        end

        return res
      end)
  end

  if rigel.isRV(fn.inputType) then
    assert(readyOutput~=nil)
    terra Module.methods.calculateReady( [mself], [readyInput] ) mself.readyDownstream = readyInput; [readyStats]; mself.ready = readyOutput end
  elseif rigel.isRV(fn.outputType) then
    assert(readyOutput~=nil)
    -- notice that we set readyInput to true here. This is kind of a hack to make the code above simpler. This should never actually be read from.
    terra Module.methods.calculateReady( [mself] ) var [readyInput] = true; [readyStats]; mself.ready = readyOutput end
  elseif rigel.isHandshake(fn.outputType) or fn.output:outputStreams()>0 then
    local TMP = quote end
    if fn.input~=nil then TMP = quote mself.ready = [readyOutput] end end
    terra Module.methods.calculateReady( [mself], [readyInput] ) mself.readyDownstream = readyInput; [readyStats]; TMP; end
  elseif rigel.streamCount(fn.inputType)>0 then
    -- has a handshake input, but not a handshake output
    assert(fn.outputType==types.null())
    terra Module.methods.calculateReady( [mself] ) [readyStats]; mself.ready = [readyOutput]; end
  elseif rigel.handshakeMode(fn.output) then
    assert(fn.outputType==types.null())
    assert(fn.inputType==types.null())
    terra Module.methods.calculateReady( [mself] ) [readyStats]; end
  end

  local out = fn.output:visitEach(
    function(n, inputs)
      local out

      if n==fn.output then
        out = outputSymbol
      elseif n.kind=="applyRegStore" then
      elseif n.kind~="input" then
--        table.insert( Module.entries, {field="simstateoutput_"..n.name, type=rigel.lower(n.type):toTerraType()} )
        out = `&mself.["simstateoutput_"..n.name]
      end

      if n.kind=="input" then
        if n.id~=fn.input.id then error("Input node is not the specified input to the lambda") end
        return inputSymbol
      elseif n.kind=="apply" then
--        table.insert( Module.entries, {field=n.name, type=n.fn.terraModule} )
        table.insert( resetStats, quote mself.[n.name]:reset() end )
        table.insert( initStats, quote mself.[n.name]:init() end )
        table.insert( freeStats, quote mself.[n.name]:free() end )
        table.insert( statStats, quote mself.[n.name]:stats([n.name]) end )

        if n.fn.inputType==types.null() then
          table.insert( stats, quote mself.[n.name]:process( out ) end )
        else
          if DARKROOM_VERBOSE then
            print("COMPILE "..n.fn.name)
            n.fn.terraModule.methods.process:compile()
            print("COMPILEDONE "..n.fn.name)
          end

          table.insert( stats, quote mself.[n.name]:process( [inputs[1]], out ) end )
        end

          if DARKROOM_VERBOSE then
            if n.type:isArray() and rigel.isHandshake(n.type:arrayOver()) then
            elseif #n.inputs>0 and rigel.isHandshake(n.inputs[1].type) then
              table.insert( Module.entries, {field=n.name.."CNT", type=int} )
              table.insert( resetStats, quote mself.[n.name.."CNT"]=0 end )

              table.insert( Module.entries, {field=n.name.."ICNT", type=int} )
              table.insert( resetStats, quote mself.[n.name.."ICNT"]=0 end )

              local readyDownstream = `mself.[n.name].readyDownstream
              local readyThis = `mself.[n.name].ready

              table.insert( stats, quote 
--                cstdio.printf("APPLY %s inpvalid %d outvalid %d cnt %d icnt %d ready %d readydownstream %d\n",n.name, valid([inputs[1]]), valid(out), mself.[n.name.."CNT"],mself.[n.name.."ICNT"] , readyThis, readyDownstream);

--                if valid(out) and readyDownstream then mself.[n.name.."CNT"]=mself.[n.name.."CNT"]+1 end
--                if valid([inputs[1]]) and readyDownstream and readyThis then mself.[n.name.."ICNT"]=mself.[n.name.."ICNT"]+1 end
              end )
            elseif  rigel.isHandshake(n.type) then
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
            table.insert( initStats, quote mself.[n.inst.name]:init() end )
            table.insert( freeStats, quote mself.[n.inst.name]:free() end )

            if DARKROOM_VERBOSE then table.insert( stats, quote cstdio.printf("STORE INPUT %s valid:%d ready:%d\n",n.name,valid([inputs[1]]), mself.[n.inst.name].ready) end ) end
            table.insert(stats, quote  mself.[n.inst.name]:store( [inputs[1]] ) end )
            return `nil
          elseif n.fnname=="start" then
            table.insert( statStats, quote mself.[n.inst.name]:stats([n.name]) end )
            table.insert( resetStats, quote mself.[n.inst.name]:reset() end )
            table.insert( initStats, quote mself.[n.inst.name]:init() end )
            table.insert( freeStats, quote mself.[n.inst.name]:free() end )

            table.insert( stats, quote mself.[n.inst.name]:start( out ) end)

            return out
          elseif n.fnname=="done" then
            table.insert(stats, quote  mself.[n.inst.name]:done( [inputs[1]] ) end )
            return `nil
          else
            assert(false)
          end
        elseif n.kind=="constant" then
          table.insert( stats, quote (@out) = [n.type:valueToTerra(n.value)] end )
          --if n.type:isArray() then
          --  J.map( n.value, function(m,i) table.insert( stats, quote (@out)[i-1] = m end ) end )
          --elseif n.type:isInt() or n.type:isUint() then
          --  table.insert( stats, quote (@out) = n.value end)
          --else
          --  assert(false)
          --end

          return out
        elseif n.kind=="concat" then
          J.map( inputs, function(m,i) local ty = rigel.lower(rigel.lower(n.type).list[i])
              table.insert(stats, quote cstring.memcpy(&(@out).["_"..(i-1)],[m],[ty:sizeof()]) end) end)
          return out
        elseif n.kind=="concatArray2d" then
          local ty = rigel.lower(n.type):arrayOver()
          J.map( inputs, function(m,i) table.insert(stats, quote cstring.memcpy(&((@out)[i-1]),[m],[ty:sizeof()]) end) end)
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
          if rigel.isHandshakeTuple(n.inputs[1].type) then
            return `&((@[inputs[1]]).["_"..tostring(n.i)])
          else
            return `&((@[inputs[1]])[n.i])
          end
        elseif n.kind=="readGlobal" then
          return `&[n.global:terraValue()]
        else
          print(n.kind)
          assert(false)
        end
    end)

  -- kind of a hack: we might have a pair of globals inside a module (in/out)
  -- which should drive each other. Instead of trying to merge the global, just copy the value
  -- will this work???
  local tiedownGlobals = {}
  local seenGlobals = {}
  for k,_ in pairs(fn.globals) do
    if seenGlobals[k.name]~=nil then
      if seenGlobals[k.name].direction=="input" and k.direction=="output" then
        table.insert(tiedownGlobals, quote [seenGlobals[k.name]:terraValue()] = [k:terraValue()] end)
      elseif seenGlobals[k.name].direction=="output" and k.direction=="input" then
        table.insert(tiedownGlobals, quote [k:terraValue()] = [seenGlobals[k.name]:terraValue()] end)
      else
        print("ERROR: two globals with same name?")
        assert(false)
      end
    end
    
    seenGlobals[k.name] = k
  end
  
  if fn.input==nil then
    terra Module.methods.process( [mself], [outputSymbol] ) [tiedownGlobals];[stats] end
  else
    terra Module.methods.process( [mself], [inputSymbol], [outputSymbol] ) [tiedownGlobals];[stats] end
  end

  terra Module.methods.reset( [mself] ) [resetStats] end
  terra Module.methods.init( [mself] ) [initStats] end
  terra Module.methods.free( [mself] ) [freeStats] end
  terra Module.methods.stats( [mself], name:&int8 ) [statStats] end

  --if DARKROOM_VERBOSE then Module.methods.process:printpretty(true,false) end
  --if Module.methods.calculateReady~=nil then Module.methods.calculateReady:printpretty(true,false) end

  return Module
end

return MT
