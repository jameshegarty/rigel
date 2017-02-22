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


local data = rigel.data
local valid = rigel.valid
local ready = rigel.ready


local MT = {}

function MT.SoAtoAoS(res,W,H,typelist,asArray)
  local struct PackTupleArrays { }
  terra PackTupleArrays:reset() end

  terra PackTupleArrays:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return PackTupleArrays
end

function MT.packTuple(res,typelist)
  local struct PackTuple { ready:bool[#typelist], readyDownstream:bool, outputCount:uint32}
    
  terra PackTuple:stats(name:&int8) self.outputCount=0 end
  
  -- ignore the valid bit on const stuff: it is always considered valid
  local activePorts = {}
  for k,v in ipairs(typelist) do if v:const()==false then table.insert(activePorts, k) end end
    
  -- the simulator doesn't have true bidirectional dataflow, so fake it with a FIFO
  map( activePorts, function(k) table.insert(PackTuple.entries,{field="FIFO"..k, type=simmodules.fifo( typelist[k]:toTerraType(), 8, "PackTuple"..k)}) end )
  terra PackTuple:reset() [map(activePorts, function(i) return quote self.["FIFO"..i]:reset() end end)] end
  terra PackTuple:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return PackTuple
end

function MT.liftBasic(res,f)
  local struct LiftBasic { inner : f.terraModule}
  terra LiftBasic:reset() self.inner:reset() end
  terra LiftBasic:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    self.inner:process(inp,&data(out))
    valid(out) = true
  end
  return LiftBasic
end


function MT.reduceThroughput(res,A,factor)
  local struct ReduceThroughput {ready:bool; phase:int}
  terra ReduceThroughput:reset() self.phase=0 end
  terra ReduceThroughput:stats(inp:&int8)  end
  terra ReduceThroughput:process(inp:&A:toTerraType(),out:&rigel.lower(res.outputType):toTerraType()) 
    data(out) = @inp
    valid(out) = self.ready
    self.phase = self.phase+1
    if self.phase==factor then self.phase=0 end
  end
  terra ReduceThroughput:calculateReady() 
    self.ready = (self.phase==0) 
  end

  return ReduceThroughput
end

function MT.waitOnInput(res,f)
  local struct WaitOnInput { inner : f.terraModule, ready:bool }
  terra WaitOnInput:reset() self.inner:reset() end
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

  return WaitOnInput
end

function MT.liftDecimate(res,f)
  local struct LiftDecimate { inner : f.terraModule; idleCycles:int, activeCycles:int, ready:bool}
  terra LiftDecimate:reset() self.inner:reset(); self.idleCycles = 0; self.activeCycles=0; end
  terra LiftDecimate:stats(name:&int8) cstdio.printf("LiftDecimate %s utilization %f\n",name,[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end
  terra LiftDecimate:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    if valid(inp) then
      self.inner:process(&data(inp),[&rigel.lower(f.outputType):toTerraType()](out))
      self.activeCycles = self.activeCycles + 1
    else
      valid(out) = false
      self.idleCycles = self.idleCycles + 1
    end
  end
  terra LiftDecimate:calculateReady() self.ready=true end

  return LiftDecimate
end


function MT.RPassthrough(res,f)
  local struct RPassthrough { inner : f.terraModule, readyDownstream:bool, ready:bool}
  terra RPassthrough:reset() self.inner:reset() end
  terra RPassthrough:stats( name : &int8 ) self.inner:stats(name) end
  terra RPassthrough:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    self.inner:process([&rigel.lower(f.inputType):toTerraType()](inp),out)
  end
  terra RPassthrough:calculateReady( readyDownstream:bool ) 
    self.readyDownstream = readyDownstream
    self.inner:calculateReady()
    self.ready = readyDownstream and self.inner.ready
  end

  return RPassthrough
end

function MT.liftHandshake(res,f,delay)
  local struct LiftHandshake{ delaysr: simmodules.fifo( rigel.lower(f.outputType):toTerraType(), delay, "liftHandshake"),
                              inner: f.terraModule, ready:bool, readyDownstream:bool}
  terra LiftHandshake:reset() self.delaysr:reset(); self.inner:reset() end
  terra LiftHandshake:stats(name:&int8) 
--    cstdio.printf("LiftHandshake %s, Max input fifo size: %d\n", name, self.fifo:maxSizeSeen())
    self.inner:stats(name) 
  end

  terra LiftHandshake:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

      var tout : rigel.lower(f.outputType):toTerraType()

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

  return LiftHandshake
end


function MT.map(res,f,W,H)
  local struct MapModule {fn:f.terraModule}
  terra MapModule:reset() self.fn:reset() end
  terra MapModule:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for i=0,W*H do self.fn:process( &((@inp)[i]), &((@out)[i])  ) end
  end
  return MapModule
end

function MT.filterSeq( res, A, W,H, rate, fifoSize )
  local struct FilterSeq { phase:int; cyclesSinceOutput:int; currentFifoSize: int; remainingInputs : int; remainingOutputs : int }
  terra FilterSeq:reset() self.phase=0; self.cyclesSinceOutput=0; self.currentFifoSize=0; self.remainingInputs=W*H; self.remainingOutputs=W*H/rate; end
  terra FilterSeq:stats(name:&int8) end
--[=[
  terra FilterSeq:process( inp : &res.inputType:toTerraType(), out:&rigel.lower(res.outputType):toTerraType() )
    data(out) = inp._0
    valid(out) = inp._1

    -- if it has been RATE cycles since we had an output, force us to have an output
    var underflow = (self.currentFifoSize==0 and self.cyclesSinceOutput==rate)
    valid(out) = valid(out) or underflow

    -- if fifo is full, surpress output
    var fifoHasSpace = (self.currentFifoSize<fifoSize)
    valid(out) = valid(out) and fifoHasSpace

    -- we're running out of possible outputs
--    var remainingInputOptions = (self.remainingInputs >> logRate) + (fifoSize-self.currentFifoSize)
    --var remainingInputOptions = (self.remainingInputs) + (fifoSize-self.currentFifoSize)
    var outaTime : bool = (self.remainingInputs < self.remainingOutputs*rate)
    valid(out) = valid(out) or outaTime

    if DARKROOM_VERBOSE then cstdio.printf("FilterSeq inputvalid %d outputvalid %d underflow %d fifoHasSpace %d outaTime %d currentFifoSize %d phase %d remainingOutputs %d\n", inp._1, valid(out), underflow, fifoHasSpace, terralib.select(outaTime,1,0), self.currentFifoSize, self.phase, self.remainingOutputs) end
    --cstdio.printf("remainingInputs %d remainingInputs>>logRate %d remainingOutputs %d\n", self.remainingInputs, self.remainingInputs >> logRate, self.remainingOutputs)
--    cstdio.printf("rate %d\n",rate)

    if valid(out) then
      if self.phase<rate-1 then
        -- if self.phase==rate, we consume in the same cycle (net change=0)
        self.currentFifoSize = self.currentFifoSize + 1
      end

      self.remainingOutputs = self.remainingOutputs - 1
      self.cyclesSinceOutput = 0
    else
      if self.phase==rate-1 and self.currentFifoSize>0 then self.currentFifoSize = self.currentFifoSize-1 end
      self.cyclesSinceOutput = self.cyclesSinceOutput + 1
    end

    self.remainingInputs = self.remainingInputs - 1
    self.phase = self.phase + 1
    if self.phase==rate then self.phase = 0 end
  end
  ]=]

  terra FilterSeq:process( inp : &res.inputType:toTerraType(), out:&rigel.lower(res.outputType):toTerraType() )

    var validIn = inp._1

    var underflow = (self.currentFifoSize==0 and self.cyclesSinceOutput==rate)
    var fifoHasSpace = (self.currentFifoSize<fifoSize)
    var outaTime : bool = (self.remainingInputs < self.remainingOutputs*rate)
    var validOut : bool = (((validIn or underflow) and fifoHasSpace) or outaTime)

    var currentFifoSize = terralib.select(validOut and self.phase<rate-1, self.currentFifoSize+1, terralib.select(validOut==false and self.phase==rate-1 and self.currentFifoSize>0,self.currentFifoSize-1,self.currentFifoSize))
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
    if self.phase==rate then self.phase = 0 end    
  end
  
  return FilterSeq
end

function MT.upsampleXSeq(res,A, T, scale, ITYPE )
  local struct UpsampleXSeq { buffer : ITYPE:toTerraType(), phase:int, ready:bool }
  terra UpsampleXSeq:reset() self.phase=0; end
  terra UpsampleXSeq:stats(name:&int8)  end
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
  terra InterleveSchedule:process( out : &uint8 )
    @out = (self.phase >> period) % N
    self.phase = self.phase+1
  end

  return InterleveSchedule
end

function MT.pyramidSchedule( depth, wtop, T )
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

  return PyramidSchedule
end

function MT.toHandshakeArray( res,A, inputRates )
  local struct ToHandshakeArray {ready:bool[#inputRates], readyDownstream:uint8}
  terra ToHandshakeArray:reset()  end
  terra ToHandshakeArray:stats( name: &int8 ) end
  terra ToHandshakeArray:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return ToHandshakeArray
end

function MT.serialize( res, A, inputRates, Schedule)
  local struct Serialize { schedule: Schedule.terraModule; nextId : uint8, ready:uint8, readyDownstream:bool}
  terra Serialize:reset() self.schedule:reset(); self.schedule:process(&self.nextId) end
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
  terra BroadcastStream:stats( name: &int8) end
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
    end
  end

  return PosSeq
end


function MT.padSeq( res, A, W, H, T, L, R, B, Top, Value )
  local struct PadSeq {posX:int; posY:int, ready:bool}
  terra PadSeq:reset() self.posX=0; self.posY=0; end
  terra PadSeq:stats(name:&int8) end -- not particularly interesting
  terra PadSeq:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return PadSeq
end

function MT.changeRate(res, A, H, inputRate, outputRate,maxRate,outputCount,inputCount )

  local struct ChangeRate { buffer : (A:toTerraType())[maxRate*H]; phase:int, ready:bool}

  terra ChangeRate:stats(name:&int8) end

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

  return ChangeRate
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

  return Linebuffer
end

function MT.SSR(res, A, T, xmin, ymin )
  local struct SSR {SR:(A:toTerraType())[-xmin+T][-ymin+1]}
  terra SSR:reset() end
  terra SSR:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
    for y=0,-ymin+1 do for x=0,-xmin do self.SR[y][x] = self.SR[y][x+T] end end
    for y=0,-ymin+1 do for x=-xmin,-xmin+T do self.SR[y][x] = (@inp)[y*T+(x+xmin)] end end

    -- write to output
    for y=0,-ymin+1 do for x=0,-xmin+T do (@out)[y*(-xmin+T)+x] = self.SR[y][x] end end
  end

  return SSR
end

function MT.SSRPartial(res,A, T, xmin, ymin, stride, fullOutput)
  local struct SSRPartial {phase:int; SR:(A:toTerraType())[-xmin+1][-ymin+1]; activeCycles:int; idleCycles:int, ready:bool}
  terra SSRPartial:reset() self.phase=0; self.activeCycles=0;self.idleCycles=0; end
  terra SSRPartial:stats(name:&int8) cstdio.printf("SSRPartial %s T=%f utilization:%f\n",name,[float](T),[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end
  terra SSRPartial:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
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

  return SSRPartial
end

function MT.makeHandshake(res, f, tmuxRates )
  local delay = math.max( 1, f.delay )
  --assert(delay>0)
  -- we don't need an input fifo here b/c ready is always true
  local struct MakeHandshake{ delaysr: simmodules.fifo( rigel.lower(res.outputType):toTerraType(), delay, "makeHandshake"),
                              inner: f.terraModule,
                            ready:bool, readyDownstream:bool}
  terra MakeHandshake:reset() self.delaysr:reset(); self.inner:reset() end
  terra MakeHandshake:stats( name : &int8 )  end
  
  -- if inner function is const, consider input to always be valid
  local innerconst = false
  if tmuxRates==nil then innerconst = f.outputType:const() end

  local validFalse = false
  if tmuxRates~=nil then validFalse = #tmuxRates end

  terra MakeHandshake:process( inp : &rigel.lower(res.inputType):toTerraType(), 
                               out : &rigel.lower(res.outputType):toTerraType())

    if self.readyDownstream then
      if DARKROOM_VERBOSE then cstdio.printf("MakeHandshake %s IV %d readyDownstream=true\n",f.kind,valid(inp)) end
      if self.delaysr:size()==delay then
        var ot = self.delaysr:popFront()
        valid(out) = valid(ot)
--        data(out) = data(ot)
        cstring.memcpy( &data(out), &data(ot), [rigel.lower(f.outputType):sizeof()])
      else
        valid(out)=validFalse
      end

      var tout : rigel.lower(res.outputType):toTerraType()
      valid(tout) = valid(inp)
      if (valid(inp)~=validFalse) or innerconst then self.inner:process(&data(inp),&data(tout)) end -- don't bother if invalid
      self.delaysr:pushBack(&tout)
    end

  end
  terra MakeHandshake:calculateReady( readyDownstream: bool ) self.ready = readyDownstream; self.readyDownstream = readyDownstream end

  return MakeHandshake
end

return MT