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
local Uniform = require "uniform"

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)
local ready = macro(function(i) return `i._2 end)

local MT = {}


-- just putting this here to keep terra code out of rigel.lua
function MT.terraReference(inst)
  return global( &inst.module.terraModule, nil, inst.name )
end

function MT.new( Module, rigelFnMod )
  J.err( rigelFnMod~=nil, "MT.new: rigel Fn/Module not passed for ",Module )

  if Module.methods.init==nil then terra Module:init() end end
  if Module.methods.free==nil then terra Module:free() end end
  if Module.methods.reset==nil then terra Module:reset() end end
  if Module.methods.stats==nil then terra Module:stats(n:&int8) end end

  --err( Module.methods.process~=nil or (Module.methods.load~=nil and Module.methods.store~=nil) or (Module.methods.start~=nil and Module.methods.done~=nil), "at least one process/load/store/start/done must be given!")
  assert(Module.methods.init~=nil)
  assert(Module.methods.stats~=nil)
  assert(Module.methods.free~=nil)
  assert(Module.methods.reset~=nil)

  local fnlist = {}
  fnlist.process = rigelFnMod
  if rigel.isModule(rigelFnMod) then
    fnlist = rigelFnMod.functions
  end

  for fnname,rigelFn in pairs(fnlist) do
    J.err(Module.methods[fnname]~=nil, "Terra module method missing")

    if rigelFn.inputType==types.Interface() or rigelFn.outputType==types.Interface() then
      local tt = rigelFn.inputType
      if rigelFn.inputType==types.Interface() then tt = rigelFn.outputType end

      J.err(Module.methods[fnname].type.parameters[2]==&tt:lower():toTerraType(),"ModuleTerra.new error: function '",fnname,"' on module '",rigelFnMod.name,"', terra function input 2 type was:",Module.methods[fnname].type.parameters[2]," but should be:",tt:lower():toTerraType())
      J.err(Module.methods[fnname].type.parameters[3]==nil,"ModuleTerra.new error: function '",fnname,"' on module '",rigelFnMod.name,"', terra function input 3 type was:",Module.methods[fnname].type.parameters[3]," but should have been nil")
    else
      J.err(Module.methods[fnname].type.parameters[2]==&rigelFn.inputType:lower():toTerraType(),"ModuleTerra.new error: function '",fnname,"' on module '",rigelFnMod.name,"', terra function input 2 (fn input) type was:",Module.methods[fnname].type.parameters[2]," but should be:",rigelFn.inputType:lower():toTerraType()," because rigel fn input type was:",rigelFn.inputType)

      J.err(Module.methods[fnname].type.parameters[3]~=nil,"ModuleTerra.new error: function '",fnname,"' on module '",rigelFnMod.name,"', terra function parameter 3 missing!")
      
      J.err(Module.methods[fnname].type.parameters[3]==&rigelFn.outputType:lower():toTerraType(),"ModuleTerra.new error: function '",fnname,"' on module '",rigelFnMod.name,"', terra function input 3 (fn output) type was:",Module.methods[fnname].type.parameters[3]," but should be:",rigelFn.outputType:lower():toTerraType())
    end
  end

  return Module
end

function MT.SoAtoAoS( res, W, H, typelist, asArray )
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

  return MT.new( PackTupleArrays, res )
end

function MT.packTuple( res, typelist )
  local struct PackTuple { ready:res.inputType:extractReady():toTerraType(), readyDownstream:bool, outputCount:uint32}

  -- ignore the valid bit on const stuff: it is always considered valid
  local activePorts = {}
  for k,v in ipairs(typelist) do
    err(types.isType(v) and v:is("Interface"),"packTuple, types should be interface type, but is: "..tostring(v))
    table.insert(activePorts, k)
  end
    
  -- the simulator doesn't have true bidirectional dataflow, so fake it with a FIFO
  J.map( activePorts, function(k) table.insert(PackTuple.entries,{field="FIFO"..k, type=simmodules.fifo( typelist[k]:extractData():toTerraType(), 8, "PackTuple"..k)}) end )
  
  terra PackTuple:stats(name:&int8) self.outputCount=0 end
  terra PackTuple:reset() [J.map(activePorts, function(i) return quote self.["FIFO"..i]:reset() end end)] end
  terra PackTuple:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    [J.map(activePorts, function(i) return quote 
             if valid(inp.["_"..(i-1)]) and self.ready.["_"..(i-1)] then 
               self.["FIFO"..i]:pushBack(&data(inp.["_"..(i-1)])) 
             end 
                      end end )]

    if self.readyDownstream then
        var hasData = [J.foldt(J.map(activePorts, function(i) return `self.["FIFO"..i]:hasData() end ), J.andopterra, true )]

        escape if DARKROOM_VERBOSE then J.map( typelist, function(t,k) 
               emit quote cstdio.printf("PackTuple FIFO %d valid:%d (size %d)\n", k-1, self.["FIFO"..k]:hasData(),self.["FIFO"..k]:size()) end end) end end

        if hasData then
          -- terra doesn't like us copying large structs by value
          escape J.map( typelist, function(t,k) 
                          emit quote cstring.memcpy( &data(out).["_"..(k-1)], self.["FIFO"..k]:popFront(), [t:extractData():sizeof()] ) end
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
          emit quote self.ready.["_"..(i-1)] = (self.["FIFO"..i]:full()==false) end 
        end
      end
  end

  return MT.new( PackTuple, res )
end

function MT.liftBasic( res, f, X )
  assert(X==nil)
  local struct LiftBasic { inner : f.terraModule}
  terra LiftBasic:reset() self.inner:reset() end
  terra LiftBasic:init() self.inner:init() end
  terra LiftBasic:free() self.inner:free() end
  terra LiftBasic:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    self.inner:process(inp,&data(out))
    valid(out) = true
  end
  return MT.new( LiftBasic, res )
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

  return MT.new(ReduceThroughput,res)
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

      if DARKROOM_VERBOSE then cstdio.printf("WaitOnInput %s\n", f.name) end
      
      self.inner:process(&data(inp),out)
    else
      valid(out) = false
    end
  end
  terra WaitOnInput:calculateReady() self.inner:calculateReady(); self.ready = self.inner.ready end

  return MT.new(WaitOnInput,res)
end

function MT.liftDecimate(res,f)
  local struct LiftDecimate { inner : f.terraModule; idleCycles:int, activeCycles:int, ready:bool}
  terra LiftDecimate:reset() self.inner:reset(); self.idleCycles = 0; self.activeCycles=0; end
  terra LiftDecimate:init() self.inner:init() end
  terra LiftDecimate:free() self.inner:free() end
  terra LiftDecimate:stats(name:&int8) cstdio.printf("LiftDecimate %s utilization %f\n",name,[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end

  if res.inputType:isrVTrigger() and res.outputType:isrRVTrigger() then
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

  return MT.new(LiftDecimate,res)
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

  return MT.new(RPassthrough,res)
end

function MT.liftHandshake(res,f,delay)
  local struct LiftHandshake{ delaysr: simmodules.fifo( rigel.lower(f.outputType):toTerraType(), delay, "liftHandshake("..f.name..")"),
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
        if DARKROOM_VERBOSE then cstdio.printf("LIFTHANDSHAKE %s READY DOWNSTRAM = true. ready this = %d\n", f.name, self.inner.ready) end

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

        if self.delaysr:size()==delay then
          var ot = self.delaysr:popFront()
          valid(out) = valid(ot)
          data(out) = data(ot)
        else
          valid(out) = false
        end

        if DARKROOM_VERBOSE then cstdio.printf("LIFTHANDSHAKE %s READY DOWNSTRAM = true. ready this = %d, validInput=%d, validOut=%d\n", f.name, self.inner.ready,valid(inp),valid(out) ) end

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

  return MT.new( LiftHandshake, res )
end


function MT.map( res, f, W, H )
  local struct MapModule {fn:f.terraModule}
  terra MapModule:reset() self.fn:reset() end
  terra MapModule:init() self.fn:init() end
  terra MapModule:free() self.fn:free() end
  terra MapModule:process( inp : &types.lower(res.inputType):toTerraType(), out : &types.lower(res.outputType):toTerraType() )
    for i=0,W*H do self.fn:process( &((@inp)[i]), &((@out)[i])  ) end
  end
  return MT.new(MapModule,res)
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

    terra FilterSeq:process( inp : &res.inputType:lower():toTerraType(), out:&rigel.lower(res.outputType):toTerraType() )

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

    return MT.new( FilterSeq, res )

  else
    local struct FilterSeq {  }
    terra FilterSeq:reset()  end
    terra FilterSeq:init()  end
    terra FilterSeq:free()  end
    terra FilterSeq:stats(name:&int8) end

    terra FilterSeq:process( inp : &res.inputType:lower():toTerraType(), out:&rigel.lower(res.outputType):toTerraType() )
      valid(out) = inp._1
      data(out) = inp._0
    end

    return MT.new( FilterSeq, res )

  end
  
end

function MT.upsampleXSeq( res, A, T, scale_orig, ITYPE )
  assert(types.isType(ITYPE) and ITYPE:isData())
  local scale = Uniform(scale_orig)
  local struct UpsampleXSeq { buffer : ITYPE:toTerraType(), phase:uint, ready:bool }
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
    if self.phase==[scale:toTerra()] then self.phase=0 end
  end
  terra UpsampleXSeq:calculateReady()  self.ready = (self.phase==0) end

  return MT.new( UpsampleXSeq, res )
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

  return MT.new( TriggeredCounter, res )
end

function MT.triggerCounter( res, N_orig, X )
  assert(X==nil)
  local N = Uniform(N_orig)
  
  local struct TriggerCounter { phase:int, ready:bool }
  terra TriggerCounter:reset() self.phase=0; end
  terra TriggerCounter:process( inp : &rigel.lower(res.inputType):toTerraType(),
                                out : &rigel.lower(res.outputType):toTerraType() )
    self.phase = self.phase + 1
    if self.phase==[N:toTerra()] then
      self.phase=0
      valid(out) = true
    else
      valid(out) = false
    end
  end

  return MT.new( TriggerCounter, res )
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

  return MT.new( UpsampleYSeq, res )
end

function MT.interleveSchedule( res, N, period, X )
  assert(type(N)=="number")
  assert(type(period)=="number")
  assert(X==nil)
  
  local struct InterleveSchedule { phase: uint8 }
  terra InterleveSchedule:reset() self.phase=0 end
  terra InterleveSchedule:process( inp:&res.inputType:lower():toTerraType(), out : &uint8 )
    @out = (self.phase >> period) % N
    self.phase = self.phase+1
  end

  return MT.new( InterleveSchedule, res )
end

function MT.pyramidSchedule( res, depth, wtop, T, X )
  assert(type(depth)=="number")
  assert(type(T)=="number")
  assert(X==nil)
  
  local struct PyramidSchedule { depth: uint8; w:uint }
  terra PyramidSchedule:reset() self.depth=0; self.w=0 end
  terra PyramidSchedule:init() end
  terra PyramidSchedule:free() end
  terra PyramidSchedule:process( inp:&res.inputType:lower():toTerraType(), out : &uint8 )
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

  return MT.new( PyramidSchedule, res )
end

function MT.toHandshakeArrayOneHot( res, A, inputRates )
  local struct ToHandshakeArrayOneHot {ready:bool[#inputRates], readyDownstream:uint8}
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

  return MT.new( ToHandshakeArrayOneHot, res )
end

function MT.serialize( res, A, inputRates, Schedule)
  local struct Serialize { schedule: Schedule.terraModule; nextId : uint8, ready:uint8, readyDownstream:bool}
  terra Serialize:reset() self.schedule:reset(); self.schedule:process(nil,&self.nextId) end
  terra Serialize:init() self.schedule:init() end
  terra Serialize:free() self.schedule:free() end
  terra Serialize:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    if self.readyDownstream then
      if valid(inp) then
        valid(out) = self.nextId
        data(out) = data(inp)
        -- step the schedule
        if DARKROOM_VERBOSE then cstdio.printf("STEPSCHEDULE\n") end
        self.schedule:process( nil, &self.nextId)
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

  return MT.new( Serialize, res )
end

function MT.Arbitrate( res, A, inputRates, tmuxed )
  assert( types.isType(A) and A:isSchedule() )
  local N = #inputRates
  local struct Arbitrate { buffer:A:extractData():toTerraType()[N], hasItem:bool[N], ready:bool[N], readyDownstream:bool}
  
  terra Arbitrate:reset()
    for i=0,N do
      self.hasItem[i]=false
    end
  end

  terra Arbitrate:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )

    valid(out) = false
    for i=0,N do
      if self.hasItem[i] then
        valid(out) = true
        data(out) = self.buffer[i]
        if self.readyDownstream then
          self.hasItem[i]=false
        end

        break
      end
    end

    for i=0,N do
      if valid((@inp)[i]) then
        if self.hasItem[i] then
          cstdio.printf("INTERNAL ERROR: arbitrate buffer is full for some reason?\n")
          cstdlib.exit(1)
        end
        self.hasItem[i] = true
        self.buffer[i]=data((@inp)[i])
      end
    end
  end

  terra Arbitrate:calculateReady( readyDownstream : bool) 
    self.readyDownstream = readyDownstream
    for i=0,N do
      self.ready[i] = (self.hasItem[i]==false) or readyDownstream
    end
  end

  return MT.new( Arbitrate, res )
end

function MT.demux( res, A, rates )
  -- HACK: we don't have true bidirectional data transfer in the simulator, so fake it with a FIFO
  local struct Demux { fifo: simmodules.fifo( rigel.lower(res.inputType):toTerraType(), 8, "makeHandshake"), ready:bool, readyDownstream:bool[#rates]}
  terra Demux:reset() self.fifo:reset() end
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

  return MT.new( Demux, res )
end

function MT.flattenStreams( res, A, rates )
  local struct FlattenStreams { ready:bool, readyDownstream:bool}

  terra FlattenStreams:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    valid(out) = (valid(inp)<[#rates])
    data(out) = data(inp)
  end
  terra FlattenStreams:calculateReady( readyDownstream : bool )
    self.readyDownstream = readyDownstream
    self.ready = readyDownstream
  end

  return MT.new( FlattenStreams, res )
end

function MT.broadcastStream( res, W, H, X)
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(X==nil)
  assert(H==1)
  local struct BroadcastStream {ready:bool, readyDownstream:bool[W]}

  if rigel.isHandshakeTrigger(res.inputType) and rigel.isHandshakeTriggerArray(res.outputType) then
    terra BroadcastStream:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      for i=0,W do
        if self.ready then -- all of readyDownstream are true
          (@out)[i] = @inp
        else
          (@out)[i] = false
        end
      end
    end

  else
    --print("BROADCASTSTRAEM",res.inputType,rigel.lower(res.inputType),rigel.lower(res.outputType))
    
    terra BroadcastStream:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      for i=0,W do
        if self.ready then -- all of readyDownstream are true
          data((@out)[i]) = data(inp)
          valid((@out)[i]) = valid(inp)
        else
          valid((@out)[i]) = false
        end
      end
    end
  end

  terra BroadcastStream:calculateReady( readyDownstream : bool[W] )
    self.ready = true
    for i=0,W do
      self.readyDownstream[i] = readyDownstream[i]
      self.ready = self.ready and readyDownstream[i]
    end
  end

  return MT.new( BroadcastStream, res )
end

function MT.posSeq( res, W_orig, H, T, asArray )
  local W = Uniform(W_orig)
  local struct PosSeq { x:uint, y:uint }
  terra PosSeq:reset() self.x=0; self.y=0 end

  if T==0 then
    local slf = symbol(&PosSeq)
    local out = symbol(&rigel.lower(res.outputType):toTerraType())
    local assign
    if asArray then
      assign = quote (@out)[0] = slf.x; (@out)[1] = slf.y; end
    else
      assign = quote (@out) = {slf.x,slf.y} end
    end
    terra PosSeq.methods.process( [slf], inp : &rigel.lower(res.inputType):toTerraType(), [out]  )
      [assign]
      slf.x = slf.x + 1
      if slf.x==[W:toTerra()] then slf.x=0; slf.y=slf.y+1 end
      if slf.y==H then slf.y=0 end
    end
  else
    terra PosSeq:process( inp : &rigel.lower(res.inputType):toTerraType(),
                          out : &rigel.lower(res.outputType):toTerraType() )
      for i=0,T do
        [(function() if asArray then
             return quote (@out)[i][0]=self.x; (@out)[i][1]=self.y; end
           else
             return quote (@out)[i] = {self.x,self.y} end
           end
           end)()]

        self.x = self.x + 1
        if self.x==[W:toTerra()] then self.x=0; self.y=self.y+1 end
        if self.y==H then self.y=0 end
      end
    end
  end

  return MT.new( PosSeq, res )
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
  
  return MT.new( Pad, res )
end

function MT.downsample( res, A, W, H, scaleX, scaleY )
  local struct Downsample {}
  local outW = W/scaleX
  
  terra Downsample:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    for y=0,H/scaleY do
      for x=0,W/scaleX do
        (@out)[x+y*outW] = (@inp)[(x*scaleX)+(y*scaleY)*W]
      end
    end
  end

  return MT.new( Downsample, res )
end

function MT.upsample( res, A, W, H, scaleX, scaleY )
  local struct Upsample {}

local outW = W*scaleX
  
  terra Upsample:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    for y=0,H*scaleY do
      for x=0,W*scaleX do
        (@out)[x+y*outW] = (@inp)[(x/scaleX)+(y/scaleY)*W]
      end
    end
  end
  
  return MT.new( Upsample, res )
end


function MT.padSeq( res, A, W, H, T, L, R, B, Top, Value )
  assert(T>=0)
  
  local struct PadSeq {posX:int; posY:int, ready:bool}
  terra PadSeq:reset() self.posX=0; self.posY=0; end

  local Tf = math.max(T,1)
  
  terra PadSeq:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    var interior : bool = (self.posX>=L and self.posX<(L+W) and self.posY>=B and self.posY<(B+H))

--    cstdio.printf("PADPOS %d %d, %d %d %d %d, %d %d\n",self.posX,self.posY,L,R,B,Top,W,H)
    valid(out) = true
    if interior then
      data(out) = @inp
    else
      [(function() if T==0 then
        return quote data(out) = [A:valueToTerra(Value)] end
      else
        return quote data(out) = arrayof([A:toTerraType()],[J.broadcast(A:valueToTerra(Value),T)]) end
      end end)()]
    end
    
    self.posX = self.posX+Tf;
    if self.posX==[Uniform(W+L+R):toTerra()] then
      self.posX=0;
      self.posY = self.posY+1;
    end

    if self.posY==(H+B+Top) then
      self.posY = 0
    end
--    cstdio.printf("PAD x %d y %d inner %d\n",self.posX,self.posY,inner)
  end
  terra PadSeq:calculateReady()  self.ready = (self.posX>=L and self.posX<(L+W) and self.posY>=B and self.posY<(B+H)) end

  return MT.new( PadSeq, res )
end

function MT.changeRate(res, A, H, inputRate, outputRate, maxRate, outputCount, inputCount )
  assert(outputRate>=0)
  assert(inputRate>=0)
  assert(H>0)
  
  local struct ChangeRate { buffer : (A:toTerraType())[maxRate*H]; phase:int, ready:bool}

  if inputRate>outputRate then
    terra ChangeRate:reset() self.phase = 0; end

    local SELF = symbol(&ChangeRate)
    local out = symbol(&rigel.lower(res.outputType):toTerraType())

    local DOSET
    if outputRate==0 then
      assert(A:verilogBits()==0)
      DOSET = quote end
    else
      DOSET = quote for y=0,H do
        for i=0,outputRate do (data(out))[i+y*outputRate] = SELF.buffer[i+SELF.phase*outputRate+y*inputRate] end
      end end
    end
    terra ChangeRate.methods.process( [SELF], inp : &rigel.lower(res.inputType):toTerraType(), [out]  )
      if DARKROOM_VERBOSE then cstdio.printf("CHANGE_DOWN phase %d\n", SELF.phase) end
      if SELF.phase==0 then
        for y=0,H do
          for i=0,inputRate do SELF.buffer[i+y*inputRate] = (@inp)[i+y*inputRate] end
        end
      end

      DOSET
      valid(out) = true

      SELF.phase = SELF.phase + 1
      if  SELF.phase>=outputCount then SELF.phase=0 end

      if DARKROOM_VERBOSE then cstdio.printf("CHANGE_DOWN OUT validOut %d\n",valid(out)) end
    end
    terra ChangeRate:calculateReady()  self.ready = (self.phase==0) end
  else
    terra ChangeRate:reset() self.phase = 0; end
    terra ChangeRate:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      [(function() if inputRate==0 then
         return quote self.buffer[self.phase] = @inp end
       else
         return quote for i=0,inputRate do self.buffer[i+self.phase*inputRate] = (@(inp))[i] end end
       end end)()]

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

  return MT.new( ChangeRate, res )
end

function MT.linebuffer( res, A, w, h, T, ymin, framed, X )
  assert( types.isType(A) and A:isData() )
  assert( ymin<=0 )

  J.err(w*(-ymin+1)+T>0, "requested a 0 length line buffer? ymin=",ymin," w=",w," T=",T)
  assert(X==nil)
  
  local struct Linebuffer { SR: simmodules.shiftRegister( A:toTerraType(), w*(-ymin+1)+T, "linebuffer")}
  terra Linebuffer:reset() self.SR:reset() end

  if framed then
    if T==0 then
      terra Linebuffer:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
        self.SR:pushBack( inp )

        for y=[ymin],1 do
            var peekIdx = y*[w]
            var yidx = y-ymin

            (@out)[yidx] = @(self.SR:peekBack(peekIdx))
        end
      end
    else
      terra Linebuffer:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
        -- pretend that this happens in one cycle (delays are added later)
        for i=0,[T] do
          self.SR:pushBack( &(@inp)[i] )
        end

        for y=[ymin],1 do
          for x=[-T+1],1 do
            var peekIdx = x+y*[w]

            var yidx = y-ymin
            var vidx = x+T-1

            (@out)[vidx][yidx] = @(self.SR:peekBack(peekIdx))
          end
        end
      end
    end
  else
    assert( T>0 )
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
  end

  return MT.new( Linebuffer, res )
end

function MT.sparseLinebuffer( res, A, imageW, imageH, rowWidth, ymin, defaultValue, X )
  assert(rigel.isPlainFunction(res))
  assert(X==nil)
  assert(ymin<=0)

  local struct SparseLinebuffer { 
    currentX : uint16,
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

  return MT.new( SparseLinebuffer, res )
end

function MT.SSR(res, A, T, xmin, ymin, framed, X )
  assert(X==nil)
  assert(xmin<=0)
  assert(ymin<=0)

  assert(types.isType(A))
  assert(A:isData())

  local Tf = math.max(T,1)
  local SSR = struct{SR:(A:toTerraType())[-xmin+Tf][-ymin+1]}

  if framed then
    terra SSR:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
      for y=0,-ymin+1 do
        for x=0,-xmin do
          self.SR[y][x] = self.SR[y][x+Tf]
        end
      end

      for y=0,-ymin+1 do
        for x=-xmin,-xmin+Tf do
          self.SR[y][x] = [(function() if T==0 then return `(@inp)[y] else return `(@inp)[x+xmin][y] end end)()]
        end
      end

      -- write to output
      for v=0,Tf do
        for y=0,-ymin+1 do
          for x=0,-xmin+1 do
            var idx = y*(-xmin+1)+x
            --var dest = [(function() if T==0 then return `(@out)[v][idx] else return `(@out)[v][idx] end end)()]
            --@dest = self.SR[y][x+v]
            [(function() if T==0 then
               return quote (@out)[idx] = self.SR[y][x+v] end
              else
                return quote (@out)[v][idx] = self.SR[y][x+v] end
              end end)()]
          end
        end
      end
    end
  else
    terra SSR:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
      -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
      for y=0,-ymin+1 do for x=0,-xmin do self.SR[y][x] = self.SR[y][x+Tf] end end
      for y=0,-ymin+1 do for x=-xmin,-xmin+Tf do self.SR[y][x] = (@inp)[y*Tf+(x+xmin)] end end

      -- write to output
      for y=0,-ymin+1 do for x=0,-xmin+Tf do (@out)[y*(-xmin+Tf)+x] = self.SR[y][x] end end
    end
  end

  return MT.new( SSR, res )
end

function MT.SSRPartial(res, A, T, xmin, ymin, stride, fullOutput, framed, X)
  err(T>=1,"SSRPartial: T should be >=1")
  assert(X==nil)
  
  local struct SSRPartial {phase:int; SR:(A:toTerraType())[-xmin+1][-ymin+1]; activeCycles:int; idleCycles:int, ready:bool}
  terra SSRPartial:reset() self.phase=0; self.activeCycles=0;self.idleCycles=0; end
  terra SSRPartial:stats(name:&int8) cstdio.printf("SSRPartial %s T=%f utilization:%f\n",name,[float](T),[float](self.activeCycles*100)/[float](self.activeCycles+self.idleCycles)) end
  terra SSRPartial:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    var phaseAtStart = self.phase

    if self.ready then
      -- Shift in the new inputs. have this happen in 1 cycle (inputs are immediately visible on outputs in same cycle)
      var SStride = 1
      for y=0,-ymin+1 do for x=0,-xmin do self.SR[y][x] = self.SR[y][x+SStride] end end

      [(function() if framed then
        return quote for y=0,-ymin+1 do for x=-xmin,-xmin+SStride do self.SR[y][x] = (@inp)[0][y*SStride+(x+xmin)] end end end
      else
        return quote for y=0,-ymin+1 do for x=-xmin,-xmin+SStride do self.SR[y][x] = (@inp)[y*SStride+(x+xmin)] end end end
      end
      end)()]
      
      self.phase = terralib.select([T==1],0,1)
    else
      if self.phase<[T]-1 then 
        self.phase = self.phase + 1 
      else
        self.phase = 0
      end
    end

    var W : int = [(-xmin+1)/T]
    var Wtotal = -xmin+1
    if fullOutput then W = Wtotal end
    for y=0,-ymin+1 do for x=0,W do data(out)[y*W+x] = self.SR[y][J.fixedModulus(x+phaseAtStart*stride,Wtotal)] end end
    valid(out)=true
  end
  terra SSRPartial:calculateReady()  self.ready = (self.phase==0) end

  return MT.new( SSRPartial, res )
end

function MT.makeHandshake( res, f, tmuxRates, nilhandshake )
  local delay = math.max( 1, f.delay )
  --assert(delay>0)
  -- we don't need an input fifo here b/c ready is always true

  local struct MakeHandshake{ delaysr: simmodules.fifo( rigel.lower(res.outputType):toTerraType(), delay, "makeHandshake("..f.name..")"),
                              inner: f.terraModule,
                            ready:bool, readyDownstream:bool}
  terra MakeHandshake:reset() self.delaysr:reset(); self.inner:reset() end
  terra MakeHandshake:init() self.inner:init() end
  terra MakeHandshake:free() self.inner:free() end
  terra MakeHandshake:stats( name : &int8 ) self.inner:stats(name) end
  
  local validFalse = false
  if tmuxRates~=nil then validFalse = #tmuxRates end

  if f.inputType==types.Interface() and nilhandshake==false then
    terra MakeHandshake:process( out : &rigel.lower(res.outputType):toTerraType())
      if self.readyDownstream then
        if self.delaysr:size()==delay then
          var ot = self.delaysr:popFront()
          valid(out) = valid(ot)
          cstring.memcpy( &data(out), &data(ot), [f.outputType:extractData():sizeof()])
        else
          valid(out)=validFalse
        end

        var tout : rigel.lower(res.outputType):toTerraType()
        valid(tout) = true
        self.inner:process(&data(tout))

        self.delaysr:pushBack(&tout)
      end
    end
  elseif f.inputType==types.Interface() and nilhandshake==true then
    terra MakeHandshake:process( inp : &rigel.lower(res.inputType):toTerraType(),
                                 out : &rigel.lower(res.outputType):toTerraType())
      if self.readyDownstream then
        if self.delaysr:size()==delay then
          var ot = self.delaysr:popFront()
          valid(out) = valid(ot)
          cstring.memcpy( &data(out), &data(ot), [f.outputType:extractData():sizeof()])
        else
          valid(out)=validFalse
        end

        var tout : rigel.lower(res.outputType):toTerraType()
        
        valid(tout) = valid(inp);

        if (valid(inp)~=validFalse) then self.inner:process(&data(tout)) end -- don't bother if invalid

        self.delaysr:pushBack(&tout)
      end
    end
  elseif f.outputType==types.Interface() and nilhandshake==false then
    terra MakeHandshake:process( inp : &rigel.lower(res.inputType):toTerraType())
      if DARKROOM_VERBOSE then cstdio.printf("MakeHandshake %s IV %d readyDownstream=true\n",f.kind,valid(inp)) end
      if (valid(inp)~=validFalse) then self.inner:process(&data(inp)) end -- don't bother if invalid
    end
  elseif f.outputType==types.Interface() and nilhandshake==true then
    terra MakeHandshake:process( inp : &rigel.lower(res.inputType):toTerraType(), 
                                 out : &rigel.lower(res.outputType):toTerraType())
      if self.readyDownstream then
        if self.delaysr:size()==delay then
          var ot = self.delaysr:popFront()
          @out = @ot
        else
          valid(out) = validFalse
        end

        var tout : rigel.lower(res.outputType):toTerraType()
        
        valid(tout) = valid(inp);
        if (valid(inp)~=validFalse) then self.inner:process(&data(inp)) end -- don't bother if invalid

        self.delaysr:pushBack(&tout)
      end
    end
  elseif f.inputType==types.Interface() and f.outputType==types.Interface() and nilhandshake==false then
    assert(false)
  else
    terra MakeHandshake:process( inp : &rigel.lower(res.inputType):toTerraType(), 
                               out : &rigel.lower(res.outputType):toTerraType())

      --
      if self.delaysr:size()==delay then
        -- we've waited enough cycles
        var ot = self.delaysr:peekFront(0)

        --cstring.memcpy( &out, &ot, [res.outputType:lower():sizeof()])
        cstring.memcpy( &data(out), &data(ot), [f.outputType:lower():sizeof()])
        valid(out) = valid(ot)
        
        if self.readyDownstream then
          self.delaysr:popFront()
        end
      else
        valid(out)=validFalse
      end
      
      if self.readyDownstream then
        if  DARKROOM_VERBOSE then cstdio.printf("MakeHandshake %s readyDownstream=true ready=%d validIn=%d validOut=%d\n",res.name,self.ready,valid(inp),valid(out)) end
        
        var tout : rigel.lower(res.outputType):toTerraType()
        
        valid(tout) = valid(inp);
        if (valid(inp)~=validFalse) then
           self.inner:process(&data(inp),&data(tout))

           if  DARKROOM_VERBOSE then cstdio.printf("MakeHandshake %s Run It\n",res.name) end
        end -- don't bother if invalid
        self.delaysr:pushBack(&tout)
      end
    end
  end

  if f.outputType==types.Interface() and nilhandshake==false then
    terra MakeHandshake:calculateReady( ) self.ready = true; self.readyDownstream = true; end
  else
    terra MakeHandshake:calculateReady( readyDownstream: bool )
      self.ready = readyDownstream; self.readyDownstream = readyDownstream
      --if DARKROOM_VERBOSE then cstdio.printf("MakeHandshake:calculateReady %s readyDownstream=%d ready=%d\n",res.name,readyDownstream,self.ready) end
    end
  end

  return MT.new( MakeHandshake, res )
end


function MT.fifo( res, inputType, outputType, A, size, nostall, W, H, T, csimOnly, X )
  assert( rigel.isModule(res) )
  assert(X==nil)
  local struct Fifo { fifo : simmodules.fifo(A:lower():toTerraType(),size,"fifofifo"), store_ready:bool, readyDownstream:bool }
  terra Fifo:reset() self.fifo:reset() end
  terra Fifo:store( inp : &rigel.lower(inputType):toTerraType())
    if DARKROOM_VERBOSE then cstdio.printf("FIFO STORE ready:%d valid:%d\n",self.store_ready,valid(inp)) end
    -- if ready==false, ignore then input (if it's behaving correctly, the input module will be stalled)
    -- 'ready' argument was the ready value we agreed on at start of cycle. Note this this may change throughout the cycle! That's why we can't just call the :storeReady() method
    if valid(inp) and self.store_ready then 
      if DARKROOM_VERBOSE then cstdio.printf("FIFO STORE, valid input\n") end
      self.fifo:pushBack(&data(inp)) 
    end
  end
  terra Fifo:load( out : &rigel.lower(outputType):toTerraType())
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
  terra Fifo:store_calculateReady() self.store_ready = (self.fifo:full()==false) end
  terra Fifo:load_calculateReady(readyDownstream:bool) self.readyDownstream = readyDownstream end

  return MT.new( Fifo, res )
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

function MT.lut( res, inputType, outputType, values, inputCount, X )
  assert( rigel.isPlainFunction(res) )
  local struct LUTModule { lut : (outputType:toTerraType())[inputCount] }
  terra LUTModule:reset() self.lut = arrayof([outputType:toTerraType()], values) end
  terra LUTModule:process( inp:&inputType:toTerraType(), out:&outputType:toTerraType())
    @out = self.lut[@inp]
  end

  return MT.new( LUTModule, res )
end

function MT.reduce(res,f, W, H)
  local struct ReduceModule { inner: f.terraModule }
  terra ReduceModule:reset() self.inner:reset() end

  -- the execution order needs to match the hardware
  local inp = symbol( &res.inputType:lower():toTerraType() )
  local mself = symbol( &ReduceModule )
  local t = J.map(J.range(0,W*H-1), function(i) return `(@inp)[i] end )

  local foldout = J.foldt(t, function(a,b) return quote 
                            var tinp : f.inputType:lower():toTerraType() = {a,b}
                            var tout : f.outputType:lower():toTerraType()
    mself.inner:process(&tinp,&tout)
    in tout end end )

  ReduceModule.methods.process = terra( [mself], [inp], out : &res.outputType:lower():toTerraType() )
--      var res : res.outputType:toTerraType() = (@inp)[0]
--      for i=1,W*H do
--        var tinp : f.inputType:toTerraType() = {res, (@inp)[i]}
--        self.inner:process( &tinp, &res  )
--      end
--      @out = res
    @out = foldout
  end

  return MT.new( ReduceModule, res )
end

function MT.reduceSeq( res, f, Vw, Vh, X )
  assert(X==nil)
  assert(Vw>=1)
  assert(Vh>=1)
  
  local struct ReduceSeq { phase:int; result : f.outputType:lower():toTerraType(); inner : f.terraModule}
  terra ReduceSeq:reset() self.phase=0; self.inner:reset() end
  terra ReduceSeq:process( inp : &f.outputType:lower():toTerraType(), out : &rigel.lower(res.outputType):toTerraType())
    if self.phase==0 and Vw*Vh==1 then -- T==1 mean this is a noop, passthrough
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
      
      if self.phase==[Vw*Vh]-1 then
        self.phase = 0
        valid(out) = true
        data(out) = self.result
      else
        self.phase = self.phase + 1
        valid(out) = false
      end
    end
  end

  return MT.new( ReduceSeq, res )
end

function MT.overflow( res, A, count )
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

  return MT.new( Overflow, res )
end


function MT.underflow( res,  A, count, cycles, upstream, tooSoonCycles, waitForValid, overflowValue ) 
  local struct Underflow {ready:bool; readyDownstream:bool; cycles:uint32; outputCount:uint32; counting:bool}
  terra Underflow:reset()
    self.cycles=0;
    self.outputCount=0
    self.counting = false
  end

  if overflowValue==nil then overflowValue = 4022250974 end -- DEADBEEF

  terra Underflow:process( inp : &rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())

    @out = @inp

    if self.readyDownstream then
      if self.cycles>=cycles then
        if valid(inp) then
          cstdio.printf("ERROR? valid input during fixup time!\n")
          cstdlib.exit(1)
        end
      
        -- fixup mode
        valid(out) = true
        data(out) = overflowValue
        self.outputCount = self.outputCount+1

        --cstdio.printf("FIXUPTIME %d\n",self.outputCount)
      elseif valid(inp) then
        self.outputCount = self.outputCount+1
      end
    
      if [waitForValid==true] then
        if valid(inp) or self.counting then
          self.cycles = self.cycles+1
          self.counting = true
        end
      else
        self.cycles = self.cycles+1
      end
    end

    if self.outputCount>=count then
      self.outputCount = 0
      self.cycles = 0
      self.counting = false
    end
  end

  terra Underflow:calculateReady(readyDownstream:bool) self.ready = readyDownstream; self.readyDownstream=readyDownstream end

  return MT.new( Underflow, res )
end


function MT.underflowNew( res, ty, cycles, count)
  local struct UnderflowNew{ready:bool; readyDownstream:bool; remainingItems:uint32; remainingCycles:uint32; deadCycles:uint32 }

  local DEADCYCLES = 1024
  
  terra UnderflowNew:process( inp : &rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType() )
    var outtaTime = (self.remainingCycles<=self.remainingItems) and (self.remainingItems>1)
    var firstItem = self.remainingItems==0 and self.remainingCycles==0 and self.deadCycles==0 and valid(inp)
    var lastWriteOut = self.deadCycles==1 and self.remainingCycles==0

    valid(out) = (self.remainingItems>1 and valid(inp)) or firstItem or outtaTime or lastWriteOut
    var lastItem = self.remainingItems==2 and valid(out)
    
    if valid(inp) then
      data(out) = data(inp)
    else
      data(out) = [ty:valueToTerra(ty:fakeValue())]
    end

    if self.readyDownstream then
      if firstItem then
        self.remainingItems = count-1
        self.remainingCycles = cycles-1
      elseif lastItem then
        self.remainingItems = 1
        self.deadCycles = DEADCYCLES
        if self.remainingCycles>0 then self.remainingCycles = self.remainingCycles-1 end
      else
        if self.deadCycles>0 and self.remainingCycles==0 then self.deadCycles = self.deadCycles-1 end
        if self.remainingCycles>0 then self.remainingCycles = self.remainingCycles-1 end
        if valid(out) then self.remainingItems = self.remainingItems-1 end
      end
    else
      if self.remainingCycles>0 then self.remainingCycles = self.remainingCycles-1 end
    end
  end

  terra UnderflowNew:reset()
    self.remainingItems = 0
    self.remainingCycles = 0
    self.deadCycles = 0
  end

  terra UnderflowNew:calculateReady(readyDownstream:bool) self.ready = readyDownstream; self.readyDownstream=readyDownstream end

  return MT.new( UnderflowNew, res )
end

function MT.cycleCounter( res, A, count )
  local struct CycleCounter {ready:bool; readyDownstream:bool; cycles:uint32; outputCount:uint32}
  terra CycleCounter:reset() self.cycles=0; self.outputCount=0 end
  terra CycleCounter:process( inp : &rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  terra CycleCounter:calculateReady(readyDownstream:bool) self.ready = readyDownstream; self.readyDownstream=readyDownstream end

  return MT.new( CycleCounter, res )
end

function MT.lift( res, name, inputType, outputType, terraFunction, systolicInput, systolicOutput, X)
  assert(type(name)=="string")
  assert(rigel.isFunction(res))
  err(types.isType(inputType),"modules terra lift: input type must be type")
  assert(X==nil)

  local struct LiftModule {}

  if terraFunction==nil and (systolicInput~=nil or systolicOutput~=nil) then
    -- derive terra fn from systolic fn
    
    if outputType==nil then
      outputType = systolicOutput.type
    end

    err(types.isType(outputType),"modules terra lift: output type must be type")
    
    local inpS = symbol(systolicInput.type:toTerraType())
    local symbs = {}
    symbs[systolicInput.name] = inpS
    local terraOut
    if systolicOutput~=nil then
      terraOut = systolicOutput:toTerra(symbs)
    else
      err( outputType==types.null(),"MT.lift: systolicOutput is missing, but output type is: "..tostring(outputType).." on fn "..name )
    end

    if inputType==types.Interface() or inputType==types.null() then
      terra LiftModule:process(out:&rigel.lower(outputType):toTerraType())
        @out = [terraOut]
      end
    elseif outputType==types.null() then
      terra LiftModule:process(inp:&rigel.lower(inputType):toTerraType())
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
      return MT.new( LiftModule, res )
    end
  elseif terralib.isfunction(terraFunction) then
    err(types.isType(outputType),"modules terra lift: output type must be type")
    assert(inputType~=types.null())

    if outputType==types.null() and terraFunction==nil then
      terra LiftModule:process(inp:&rigel.lower(inputType):toTerraType()) end
    elseif outputType==types.null() then
      terra LiftModule:process(inp:&rigel.lower(inputType):toTerraType()) terraFunction(inp) end
    else
      terra LiftModule:process(inp:&rigel.lower(inputType):toTerraType(),out:&rigel.lower(outputType):toTerraType()) terraFunction(inp,out) end
    end
  else
    print("lift is missing an implementation?",name,terraFunction,systolicInput,systolicOutput)
    assert(false)
  end

  return MT.new( LiftModule, res )
end

function MT.constSeq( res, value, A, w, h, T, W, X )
  assert( types.isType(A) and A:isData() )
  assert( T>=1 )
assert( X==nil )
  
  local struct ConstSeqState {phase : int; data : (A:toTerraType())[h*W][T] }
  local mself = symbol(&ConstSeqState,"mself")
  local initstats = {}

  for C=0,T-1 do
    for y=0,h-1 do
      for x=0,W-1 do
        table.insert( initstats, quote mself.data[C][y*W+x] = [A:valueToTerra(value[x+y*w+C*W+1])] end )
      end
    end
  end
  terra ConstSeqState.methods.reset([mself]) mself.phase = 0; [initstats] end
  terra ConstSeqState:process( inp : &rigel.lower(res.inputType):toTerraType(),
                               out : &rigel.lower(res.outputType):toTerraType() )
    @out = self.data[self.phase]
    self.phase = self.phase + 1
    if self.phase == T then self.phase = 0 end
  end

  return MT.new( ConstSeqState, res )
end

function MT.freadSeq( res, filename, ty, addressable, X )
  assert( rigel.isFunction(res) )
  assert( X==nil )
  assert( ty:isData() )

  local struct FreadSeq { file : &cstdio.FILE }
  terra FreadSeq:init() 
    self.file = cstdio.fopen(filename, "rb") 
    [J.darkroomAssert](self.file~=nil, ["file "..filename.." doesnt exist"])
  end
  terra FreadSeq:free() cstdio.fclose(self.file) end
  terra FreadSeq:reset() end

  if addressable then
    terra FreadSeq:process(inp :&uint, out : &ty:toTerraType())
      cstdio.fseek( self.file, (@inp)*[ty:sizeof()], cstdio.SEEK_SET )
      var outBytes = cstdio.fread(out,1,[ty:sizeof()],self.file)
      [J.darkroomAssert](outBytes==[ty:sizeof()], ["Error, addressable freadSeq of '"..filename.."' failed, probably end of file?"])
    end
  else
    terra FreadSeq:process( inp:&res.inputType:lower():toTerraType(), out : &ty:toTerraType() )
      var outBytes = cstdio.fread(out,1,[ty:sizeof()],self.file)
      [J.darkroomAssert](outBytes==[ty:sizeof()], ["Error, freadSeq of '"..filename.."' failed, probably end of file?"])
    end
  end

  return MT.new( FreadSeq, res )
end

-- allowBadSizes: hack for legacy code - allow us to write sizes which will have different behavior between verilog & terra (BAD!)
-- tokensX, tokensY: optional - what is the size of the transaction? enables extra debugging (terra checks for regressions on second run)
function MT.fwriteSeq( res, filename, ty, passthrough, allowBadSizes, tokensX, tokensY, X )
  assert( rigel.isPlainFunction(res) )
  local terraSize = terralib.sizeof(ty:toTerraType())*8
  assert(X==nil)
  J.err( allowBadSizes==true or ty:verilogBits() == terraSize,"fwriteSeq: verilog size ("..ty:verilogBits()..") and terra size ("..terraSize..") don't match! This means terra and verilog representations don't match. Type: "..tostring(ty))

  if tokensX==nil then tokensX=0 end
  if tokensY==nil then tokensY=0 end

  local struct FwriteSeq { file : &cstdio.FILE, buf:&ty:toTerraType(), tokensSeen:int }
  terra FwriteSeq:init()
    self.file = cstdio.fopen(filename, "wb")
    if self.file==nil then cstdio.perror(["Error opening "..filename.." for writing"]) end
    [J.darkroomAssert]( self.file~=nil, ["Error opening "..filename.." for writing"] )
    if tokensX*tokensY>0 then
      self.buf = [&ty:toTerraType()](cstdlib.malloc(tokensX*tokensY*[ty:sizeof()]))
    end
    self.tokensSeen=0
  end

  terra FwriteSeq:free()
    cstdio.fclose(self.file)
    if tokensX*tokensY>0 then cstdlib.free(self.buf) end
  end

  terra FwriteSeq:reset()
    self.tokensSeen=0
  end

  if passthrough then
    terra FwriteSeq:process(inp : &ty:toTerraType(), out : &ty:toTerraType())
      if self.tokensSeen>=tokensX*tokensY and self.tokensSeen<tokensX*tokensY*2 then
        if cstring.memcmp(&self.buf[self.tokensSeen-tokensX*tokensY],inp,[ty:sizeof()])~=0 then
          cstdio.printf("REGRESSION file '%s' token:%d of transaction:%d old value:\n",filename,self.tokensSeen,tokensX*tokensY)
          [ty:terraPrint(`&self.buf[self.tokensSeen-tokensX*tokensY])]
          cstdio.printf("\nNew Value:\n")
          [ty:terraPrint(`inp)]
          cstdio.printf("\n")
          cstdlib.exit(1)
        end
      elseif self.tokensSeen<tokensX*tokensY then
        self.buf[self.tokensSeen] = @inp
      end
      self.tokensSeen = self.tokensSeen+1

      cstdio.fwrite(inp,[ty:sizeof()],1,self.file)
      cstring.memcpy(out,inp,[ty:sizeof()])
    end
  else
    terra FwriteSeq:process(inp : &ty:toTerraType())
      cstdio.fwrite(inp,[ty:sizeof()],1,self.file)
    end
  end

  return MT.new( FwriteSeq, res )
end

function MT.cropSeqFn(innerInputType,outputType,A, W_orig, H, T, L, R, B, Top )
  local W = Uniform(W_orig)
  return terra( inp : &innerInputType:toTerraType(), out:&outputType:toTerraType() )
    var x,y = (inp._0)[0]._0, (inp._0)[0]._1
    data(out) = inp._1
    valid(out) = (x>=L and y>=B and x<[(W-R):toTerra()] and y<H-Top)

    if DARKROOM_VERBOSE then cstdio.printf("CROP W %d H %d x %d y %d T %d VO %d\n",[W:toTerra()],H,x,y,T,valid(out)) end
  end
end

function MT.crop( res, A, W, H, L, R, B, Top )
  local struct Crop {}
  
  local outW = W-L-R
  
  terra Crop:process( inp : &rigel.lower(res.inputType):toTerraType(), out : &rigel.lower(res.outputType):toTerraType() )
    for y=0,H-B-Top do
      for x=0,W-L-R do
        (@out)[x+y*outW] = (@inp)[(x+L)+(y+B)*W]
      end
    end
  end
  
  return MT.new( Crop, res )
end

function MT.counter( res, ty, N )
  local struct Counter {buf:ty:toTerraType()}

  terra Counter:process( inp:&res.inputType:lower():toTerraType(), out:&ty:toTerraType() )
    @out = self.buf
    if self.buf==[(N-1):toTerra()] then
      self.buf = 0
    else
      self.buf = self.buf+1
    end
  end

  terra Counter:reset() self.buf=0 end

  return MT.new( Counter, res )
end

function MT.filterSeqPar(res,A,N)
  local struct FilterSeqPar { buffer:res.inputType:lower():toTerraType(), ready:bool }

  terra FilterSeqPar:process( inp : &res.inputType:lower():toTerraType(), out:&rigel.lower(res.outputType):toTerraType() )
    data(out) = self.buffer[0]._0
    valid(out) = self.buffer[0]._1

    if self.ready then
      self.buffer = @inp
    else
      for i=0,N-1 do self.buffer[i] = self.buffer[i+1] end
      self.buffer[N-1]._1 = false
    end
  end

  terra FilterSeqPar:reset()
    for i=0,N do self.buffer[i]._1 = false end
  end

  terra FilterSeqPar:calculateReady() 
    -- this logic allows us to overlap the read and the write - however, it drops the last item sometimes! not good.
    -- just wait until we fully flush
    --    var r0 = (self.buffer[0]._1==false)
    --    var r1 = (self.buffer[0]._1==true)
    --    var r2 = (self.buffer[1]._1==false)
    --    self.ready = r0 or (r1 and r2)
    self.ready = (self.buffer[0]._1==false)
  end

  return MT.new( FilterSeqPar, res )
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
  
  local readyInput = `true
  if rigel.hasReady(fn.output.type) then
    local RIT = rigel.extractReady(fn.output.type):toTerraType()
    readyInput = symbol(RIT, "readyinput")
    table.insert( Module.entries, {field="readyDownstream", type=rigel.extractReady(fn.output.type):toTerraType()} )
  end

  if rigel.hasReady(fn.inputType) or fn.output.type:isrRV() then
    table.insert( Module.entries, {field="ready", type=rigel.extractReady(fn.input.type):toTerraType()} )
  end
  
  local mself = symbol( &Module, "module self" )
  
  for inst,_ in pairs(fn.instanceMap) do 
    err(inst.module.terraModule~=nil, "Missing terra module for "..inst.module.name)
    table.insert( Module.entries, {field=inst.name, type=inst.module.terraModule} )
  end 

  -- terra requires that we predeclare all instances
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


  for inst,_ in pairs(fn.instanceMap) do 
    table.insert( initStats, quote [inst:terraReference()] = &mself.[inst.name] end )
    table.insert( initStats, quote mself.[inst.name]:init() end )
    table.insert( resetStats, quote mself.[inst.name]:reset() end )
    table.insert( freeStats, quote mself.[inst.name]:free() end )
    table.insert( statStats, quote mself.[inst.name]:stats([inst.name]) end )
  end

  local readyOutput
    
  -- build ready calculation
  if rigel.handshakeMode(fn.output) then
    
    fn.output:visitEachReverseBreakout(
      function(n, args)

        -- special case: multiple stream output with multiple consumers
        -- the only time this should happen is if everything is selectstreamed
        if n:outputStreams()>1 and n:parentCount(fn.output)>1 then

          -- all of then N consumers should be selectStream
          local list = {}
          for dsNode, _ in n:parents(fn.output) do
            if dsNode.kind=="selectStream" then
              err(list[dsNode.i+1]==nil,"Error, 2 selectStream reads of same signal! ",n.loc)

              if n.type:isTuple() then
                list[dsNode.i+1] = `[args[dsNode]].["_"..dsNode.i]
              elseif n.type:isArray() then
                list[dsNode.i+1] = `[args[dsNode]][dsNode.i]
              else
                print("NYI ready fan in of type "..tostring(n.type))
                assert(false)
              end
            else
              err( false, "Error, a multi-stream node is being consumed by something other than a selectStream? (a ",dsNode.kind,") ",n.loc )
            end
          end

          err( n:outputStreams()==#list and #list==J.keycount(list),"a multi-stream node has an incorrect number of consumers. Has ",#list," consumers but expected ",n:outputStreams(),". ",n.loc)

          if n.kind=="input" then
            if n.type:isTuple() then
              readyOutput = `{list}
            elseif n.type:isArray() then
              readyOutput = `array(list)
            else
              assert(false)
            end
return {readyOutput}
          else
            if n.type:isTuple() then
              assert(false)
            elseif n.type:isArray() then
              table.insert( readyStats, quote mself.[n.name]:calculateReady(array(list)) end )
            else
              assert(false)
            end

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
          if rigel.hasReady(n.fn.outputType)==false or n.fn.inputType:isrV() then
            table.insert( readyStats, quote mself.[n.name]:calculateReady() end )
            res = {`mself.[n.name].ready}
          else
            table.insert( readyStats, quote mself.[n.name]:calculateReady(arg) end )

            if n.fn.inputType~=types.Interface() then
              res = {`mself.[n.name].ready}
            else
              res = {`0} -- has to return something, but should not be read
            end
          end
        elseif n.kind=="applyMethod" then
          local applyfn = n.inst.module.functions[n.fnname]

          local inst
          if fn.requires[n.inst]~=nil then
            inst = n.inst:terraReference()
          else
            inst = `mself.[n.inst.name]
          end
          
          if types.isHandshakeAny(applyfn.inputType) and applyfn.outputType==types.Interface() then
            table.insert( readyStats, quote inst:[n.fnname.."_calculateReady"]() end ) 
            res = {`inst.[n.fnname.."_ready"]}
          elseif types.isHandshakeAny(applyfn.outputType) then
            table.insert( readyStats, quote inst:[n.fnname.."_calculateReady"](arg) end ) 
            if types.isHandshakeAny(applyfn.inputType) then
              res = {`inst.[n.fnname.."_ready"]}
            else
              res = {`0} -- has to return something, but should not be read
            end
          else
            assert(false)
          end
        elseif n.kind=="concat" then
          res = {}
          for k,_ in ipairs(n.inputs) do
            res[k] = `[arg].["_"..(k-1)]
          end
        elseif n.kind=="concatArray2d" then
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
          if n.inputs[1].type:isTuple() then
--                      assert(false)
            res = symbol(n.inputs[1].type:extractReady():toTerraType())

            table.insert( readyStats, quote var [res]; end)
            for i=0,n.inputs[1]:outputStreams()-1 do
              table.insert( readyStats, quote [res].["_"..i] = [arg]; end)
            end
            
            res = {res}
          elseif n.inputs[1].type:isArray() then
            res = symbol(bool[n.inputs[1]:outputStreams()])
            table.insert( readyStats, quote var [res]; [res][n.i] = [arg] end )
            res = {res}
          else
            print("NYI - terra selectstream on "..tostring(n.inputs[1].type))
            assert(false)
          end
        elseif n.kind=="writeGlobal" then
          -- write an output
          assert(n.global.direction=="output")
          res = {`[n.global:terraReady()]}
        elseif n.kind=="readGlobal" then
          -- read an input
          assert(n.global.direction=="input")
          table.insert( readyStats, quote [n.global:terraReady()]=[arg] end )
        else
          print(n.kind)
          assert(false)
        end

        if type(res)=="table" then
          local ty = res[1].type
          if terralib.isquote(res[1]) then
            ty = res[1]:gettype()
          end

          if n.inputs[1]~=nil and n.inputs[1].type~=types.Interface() then
            err(ty == types.extractReady(n.inputs[1].type):toTerraType(),"Expected terra ready type '",types.extractReady(n.inputs[1].type):toTerraType(),"' because input type was '",n.inputs[1].type,"' but was '",ty,"' ",res[1]," ",n)
          end
        end

        return res
      end)
  end

  -- dumb: remember, in RV mode readys flow forward(!)
  local RVReadyStats = {}
  local RVReadyOutput
  local RVReadyInput = symbol(bool,"RVReadyInput")
  
  local out = fn.output:visitEach(
    function(n, inputs)

      local inputsReady = {}
      for k,v in ipairs(inputs) do
        table.insert(inputsReady,v[2])
        inputs[k] = inputs[k][1]
      end
      
      local out

      if n==fn.output then
        out = outputSymbol
      elseif n.kind=="applyRegStore" then
      elseif n.kind~="input" then
        out = `&mself.["simstateoutput_"..n.name]
      end

      local res
      if n.kind=="input" then
        if n.id~=fn.input.id then error("Input node is not the specified input to the lambda") end
        if out~=nil then table.insert(stats,quote @out = @inputSymbol end) end
        res = {inputSymbol, RVReadyInput}
      elseif n.kind=="apply" then
        table.insert( resetStats, quote mself.[n.name]:reset() end )
        table.insert( initStats, quote mself.[n.name]:init() end )
        table.insert( freeStats, quote mself.[n.name]:free() end )
        table.insert( statStats, quote mself.[n.name]:stats([n.name]) end )

        if n.fn.inputType==types.Interface() then
          table.insert( stats, quote mself.[n.name]:process( out ) end )
        elseif n.fn.outputType==types.Interface() then
          table.insert( stats, quote mself.[n.name]:process( [inputs[1]] ) end )
        else
          table.insert( stats, quote mself.[n.name]:process( [inputs[1]], out ) end )
        end

        local rvready
        if #n.inputs==1 and n.inputs[1].type:isrV() then
          table.insert( RVReadyStats, quote mself.[n.name]:calculateReady() end )
          rvready = `mself.[n.name].ready
        elseif #n.inputs==1 and n.inputs[1].type:isrRV() then
          table.insert( RVReadyStats, quote mself.[n.name]:calculateReady([inputsReady[1]]) end )
          rvready = `mself.[n.name].ready
        end
        
        res = {out,rvready}
      elseif n.kind=="applyMethod" then

        local inst
        if fn.requires[n.inst]~=nil then
          inst = n.inst:terraReference()
        else
          inst = `mself.[n.inst.name]
        end

        local instfn = n.inst.module.functions[n.fnname]
        if instfn.inputType==types.Interface() then
          table.insert( stats, quote inst:[n.fnname]( out ) end)

--          if DARKROOM_VERBOSE then table.insert( stats, quote cstdio.printf("LOAD OUTPUT %s valid:%d readyDownstream:%d\n",n.name, valid(out), mself.[n.inst.name].readyDownstream ) end ) end

          res = {out}
        elseif instfn.outputType==types.Interface() then
          --if DARKROOM_VERBOSE then table.insert( stats, quote cstdio.printf("STORE INPUT %s valid:%d ready:%d\n",n.name,valid([inputs[1]]), mself.[n.inst.name].ready) end ) end

          table.insert(stats, quote  inst:[n.fnname]( [inputs[1]] ) end )
          res = {`nil}
        else
          table.insert( stats, quote inst:[n.fnname]( [inputs[1]], out ) end)
          res = {out}
--          print("NYI - terra method call on fn with type "..tostring(instfn.inputType).." -> "..tostring(instfn.outputType).." inside module "..fn.name )
--          assert(false)
        end
      elseif n.kind=="constant" then
        table.insert( stats, quote (@out) = [n.type.over.over:valueToTerra(n.value)] end )
        res = {out}
      elseif n.kind=="concat" then
        J.map( inputs, function(m,i) local ty = rigel.lower(rigel.lower(n.type).list[i])
            table.insert(stats, quote cstring.memcpy(&(@out).["_"..(i-1)],[m],[ty:sizeof()]) end) end)
        res = {out}
      elseif n.kind=="concatArray2d" then
        local ty = rigel.lower(n.type):arrayOver()
        J.map( inputs, function(m,i) table.insert(stats, quote cstring.memcpy(&((@out)[i-1]),[m],[ty:sizeof()]) end) end)
        res = {out}
      elseif n.kind=="statements" then
        if n.inputs[1].type~=types.Interface() then table.insert( stats, quote @out = @[inputs[1]] end) end
        res = {inputs[1]}
      elseif n.kind=="selectStream" then
        if rigel.isHandshakeTuple(n.inputs[1].type) then
          res = {`&((@[inputs[1]]).["_"..tostring(n.i)])}
        else
         res = {`&((@[inputs[1]])[n.i])}
        end
      elseif n.kind=="readGlobal" then
        -- read an input
        assert(n.global.direction=="input")
        res = {`&[n.global:terraValue()]}
      elseif n.kind=="writeGlobal" then
        -- write an output
        assert(n.global.direction=="output")
        table.insert( stats, quote [n.global:terraValue()] = @[inputs[1]] end)
        res = {`nil}
      else
        print(n.kind)
        assert(false)
      end

      if res[1]~=nil and terralib.isquote(res[1]) then
        err( n.type==types.Interface() or (res[1]:gettype() == &n.type:lower():toTerraType()), "Error, node terra type was '"..tostring(res[1]:gettype()).."', but should be '"..tostring(n.type:lower():toTerraType()).."' because type was '"..tostring(n.type).."'" )
      end           

      return res
    end)

  RVReadyOutput = out[2]
  out = out[1]

  if fn.input==nil or fn.inputType==types.Interface() then
    terra Module.methods.process( [mself], [outputSymbol] ) [stats] end
  elseif fn.outputType==types.Interface() then
    terra Module.methods.process( [mself], [inputSymbol] ) [stats] end
  else
    terra Module.methods.process( [mself], [inputSymbol], [outputSymbol] ) [stats] end
  end

  if DARKROOM_VERBOSE then Module.methods.process:printpretty() end

  if fn.inputType:isrRV() then
    terra Module.methods.calculateReady( [mself], [RVReadyInput] ) mself.readyDownstream = RVReadyInput; [RVReadyStats]; mself.ready = RVReadyOutput end
  elseif fn.outputType:isrRV() then
    -- notice that we set readyInput to true here. This is kind of a hack to make the code above simpler. This should never actually be read from.
    terra Module.methods.calculateReady( [mself] ) var [RVReadyInput] = true; [RVReadyStats]; mself.ready = RVReadyOutput end
  elseif rigel.isHandshake(fn.outputType) or fn.output:outputStreams()>0 then
    local TMP = quote end
    if fn.input~=nil and fn.input.type~=types.Interface() then TMP = quote mself.ready = [readyOutput] end end
    terra Module.methods.calculateReady( [mself], [readyInput] ) mself.readyDownstream = readyInput; [readyStats]; TMP; end
  elseif rigel.streamCount(fn.inputType)>0 then
    -- has a handshake input, but not a handshake output
    assert(fn.outputType==types.Interface())
    terra Module.methods.calculateReady( [mself] ) [readyStats]; mself.ready = [readyOutput]; end
  elseif rigel.handshakeMode(fn.output) then
    assert(fn.outputType==types.Interface())
    assert(fn.inputType==types.Interface())
    terra Module.methods.calculateReady( [mself] ) [readyStats]; end
  end

  if DARKROOM_VERBOSE and Module.methods.calculateReady~=nil then
    Module.methods.calculateReady:printpretty()
  end

  terra Module.methods.reset( [mself] ) [resetStats] end
  terra Module.methods.init( [mself] ) [initStats] end
  terra Module.methods.free( [mself] ) [freeStats] end
  terra Module.methods.stats( [mself], name:&int8 ) [statStats] end

  return Module
end

function MT.reg( ty, initial, extraPortIsWrite, read1bits, X )
  local chunks = math.max(ty:verilogBits()/read1bits,1)
  assert(math.floor(chunks)==chunks)

  assert(read1bits%8==0)
  local read1bytes = read1bits/8
  
  local chunkType = types.bits(read1bits):toTerraType()

  local struct Reg {r:chunkType[chunks],pout:int}
  terra Reg:read(addr:&uint32,out:&chunkType)
    var chunkAddr = @addr/read1bytes
    @out = self.r[chunkAddr]
  end

  terra Reg:reset()
    self.pout=10
  end

  -- address is in bytes
  terra Reg:write(inp:&tuple(uint32,chunkType))
    var chunkAddr = inp._0/read1bytes
--    cstdio.printf("Write Reg byte_addr %u chunk_addr %u value %u\n",inp._0,chunkAddr,inp._1)
    if chunkAddr>=chunks then
      cstdio.printf("Write to reg out of range! byte_addr %u value %u\n",inp._0,inp._1)
    else              
      self.r[chunkAddr]=inp._1
    end
  end

  if extraPortIsWrite==true then
    terra Reg:write1(inp:&ty:toTerraType())
      cstring.memcpy( &self.r, inp, [ty:sizeof()])    
    end
  else
    terra Reg:read1(out:&ty:toTerraType())
      cstring.memcpy( out, &self.r, [ty:sizeof()])
      if self.pout>0 then
        self.pout = self.pout-1
      end
    end
  end

  return Reg
end

function MT.Storv( res, f )
  local struct Storv { fn:f.terraModule }
  terra Storv:reset() self.fn:reset() end
  terra Storv:init() self.fn:init() end
  terra Storv:free() self.fn:free() end

  J.err( f.inputType==types.Interface(), "NYI - Storv only supports nil input", f)

  terra Storv:process( inp : &types.lower(res.inputType):toTerraType(),
                       out : &types.lower(res.outputType):toTerraType() )
    self.fn:process( out )
  end

  return MT.new( Storv, res )
end

function MT.triggerFIFO( res, ty )
  local struct TriggerFIFO { cnt:uint, store_ready:bool, readyDownstream:bool }
  terra TriggerFIFO:reset() self.cnt=0 end

  terra TriggerFIFO:store( inp : &rigel.lower(res.functions.store.inputType):toTerraType())
    if valid(inp) and self.store_ready then
      self.cnt = self.cnt+1
    end
  end

  terra TriggerFIFO:load( out : &rigel.lower(res.functions.load.outputType):toTerraType())
    if self.readyDownstream then
      if self.cnt>0 then
        valid(out) = true
        self.cnt = self.cnt-1
      else
        valid(out) = false
      end    
    end
  end

  terra TriggerFIFO:store_calculateReady() self.store_ready = (self.cnt < [math.pow(2,32)-1]) end
  terra TriggerFIFO:load_calculateReady(readyDownstream:bool) self.readyDownstream = readyDownstream end

  return MT.new( TriggerFIFO, res )

end
        
return MT
