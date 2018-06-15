local SOC = require "soc"
local SOCMT = require "socTerra"
local cstdlib = terralib.includec("stdlib.h")
local cstdio = terralib.includec("stdio.h")
local J = require "common"

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)
local ready = macro(function(i) return `i._2 end)

--V = terralib.includec("/home/jhegarty/rigel/platform/verilatorSOC/harness.h")
V = terralib.includec("..//platform/verilatorSOC/harness.h")

local Ctmp = terralib.includecstring [[
                                        #include <stdio.h>
                                          #include <stdlib.h>
                                          #include <sys/time.h>
                                          #include <assert.h>
                                          #include <pthread.h>
                                          #include <stdint.h>
                                          #include <inttypes.h>
                                          double CurrentTimeInSecondsHT() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return tv.tv_sec + tv.tv_usec / 1000000.0;
                                 }
                                   ]]

local currentTimeInSeconds = Ctmp.CurrentTimeInSecondsHT

return function(top, memStart, memEnd)
  local simCycles = top.sdfInput[1][2]/top.sdfInput[1][1]
  local extraCycles = 10240000
  
  local Module = top:toTerra()

  local memory = symbol(&uint8)
  local IP_CLK = symbol(uint8)
  local IP_ARESET_N = symbol(uint8)
  
  local readS = {}
  local writeS = {}

  local MEMBASE = 0x30008000
  local MEMSIZE = SOC.currentAddr-MEMBASE

  local verbose = false
  
  local S0LIST = {
    0,
    `&IP_CLK,
    `&IP_ARESET_N,
    `&data([top:getGlobal("IP_SAXI0_ARADDR"):terraValue()]),
    `[&uint8](&valid([top:getGlobal("IP_SAXI0_ARADDR"):terraValue()])),
    `[&uint8](&[top:getGlobal("IP_SAXI0_ARADDR"):terraReady()]),
    `&data([top:getGlobal("IP_SAXI0_AWADDR"):terraValue()]),
    `[&uint8](&valid([top:getGlobal("IP_SAXI0_AWADDR"):terraValue()])),
    `[&uint8](&[top:getGlobal("IP_SAXI0_AWADDR"):terraReady()]),
    `&data([top:getGlobal("IP_SAXI0_RDATA"):terraValue()]),
    `[&uint8](&valid([top:getGlobal("IP_SAXI0_RDATA"):terraValue()])),
    `[&uint8](&[top:getGlobal("IP_SAXI0_RDATA"):terraReady()]),
    `&data([top:getGlobal("IP_SAXI0_BRESP"):terraValue()]),
    `[&uint8](&valid([top:getGlobal("IP_SAXI0_BRESP"):terraValue()])),
    `[&uint8](&[top:getGlobal("IP_SAXI0_BRESP"):terraReady()])}

  local MREADLIST={}
  local MWRITELIST={}

  local MAX_READ_PORT = -1
  local MAX_WRITE_PORT = -1
  
  for i=0,SOC.ports do
    if top:getGlobal("IP_MAXI"..i.."_ARADDR")~=nil then
      MAX_READ_PORT = i
      MREADLIST[i] = {
        i,
        `&data([top:getGlobal("IP_MAXI"..i.."_ARADDR"):terraValue()]),
        `[&uint8](&valid([top:getGlobal("IP_MAXI"..i.."_ARADDR"):terraValue()])),
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_ARADDR"):terraReady()]),
        `&data([top:getGlobal("IP_MAXI"..i.."_RDATA"):terraValue()]),
        `[&uint8](&valid([top:getGlobal("IP_MAXI"..i.."_RDATA"):terraValue()])),
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_RDATA"):terraReady()]),
        `&[top:getGlobal("IP_MAXI"..i.."_RRESP"):terraValue()],
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_RLAST"):terraValue()]),
        `&[top:getGlobal("IP_MAXI"..i.."_ARLEN"):terraValue()],
        `&[top:getGlobal("IP_MAXI"..i.."_ARSIZE"):terraValue()],
        `&[top:getGlobal("IP_MAXI"..i.."_ARBURST"):terraValue()]}
    end

    if top:getGlobal("IP_MAXI"..i.."_AWADDR")~=nil then
      MAX_WRITE_PORT = i
      MWRITELIST[i] = {
        i,
        `&data([top:getGlobal("IP_MAXI"..i.."_AWADDR"):terraValue()]),
        `[&uint8](&valid([top:getGlobal("IP_MAXI"..i.."_AWADDR"):terraValue()])),
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_AWADDR"):terraReady()]),
        `&data([top:getGlobal("IP_MAXI"..i.."_WDATA"):terraValue()]),
        `[&uint8](&valid([top:getGlobal("IP_MAXI"..i.."_WDATA"):terraValue()])),
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_WDATA"):terraReady()]),
        `&data([top:getGlobal("IP_MAXI"..i.."_BRESP"):terraValue()]),
        `[&uint8](&valid([top:getGlobal("IP_MAXI"..i.."_BRESP"):terraValue()])),
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_BRESP"):terraReady()]),
        `&[top:getGlobal("IP_MAXI"..i.."_WSTRB"):terraValue()],
        `&[top:getGlobal("IP_MAXI"..i.."_WLAST"):terraValue()],
        `&[top:getGlobal("IP_MAXI"..i.."_AWLEN"):terraValue()],
        `&[top:getGlobal("IP_MAXI"..i.."_AWSIZE"):terraValue()],
        `&[top:getGlobal("IP_MAXI"..i.."_AWBURST"):terraValue()]}
    end
  end

  local clearOutputs = {}
  for i=0,SOC.ports do
    if top.globalMetadata["MAXI"..i.."_read_filename"]~=nil then
      table.insert( readS, quote V.loadFile([top.globalMetadata["MAXI"..i.."_read_filename"]], memory, [top.globalMetadata["MAXI"..i.."_read_address"]-MEMBASE]) end )
    end

    if top.globalMetadata["MAXI"..i.."_write_filename"]~=nil then
      local bytes = (top.globalMetadata["MAXI"..i.."_write_W"]*top.globalMetadata["MAXI"..i.."_write_H"]*top.globalMetadata["MAXI"..i.."_write_bitsPerPixel"])/8
      table.insert( writeS, quote V.saveFile([top.globalMetadata["MAXI"..i.."_write_filename"]..".terra.raw"], memory, [top.globalMetadata["MAXI"..i.."_write_address"]-MEMBASE],bytes) end )

      table.insert( clearOutputs, quote for ii=0,[bytes],4 do @[&uint32](memory+[top.globalMetadata["MAXI"..i.."_write_address"]-MEMBASE]+ii)=0x0df0adba; end end )
    end
  end
  
  local terra dosim()
    var [IP_CLK]
    var [IP_ARESET_N]
    
    var m = [&Module](cstdlib.malloc(sizeof(Module))); 
    m:init()
    m:reset();

    var [memory] = [&uint8](cstdlib.malloc(MEMSIZE))

    readS

    V.init()

    var ROUNDS = 2
    for round=0,ROUNDS do
      if verbose then cstdio.printf("ROUND %d\n",round) end

      clearOutputs

      V.deactivateMasterRead([MREADLIST[0]])
      V.deactivateMasterWrite([MWRITELIST[0]])
      
      [ (function() if MAX_READ_PORT>=1 then return quote V.deactivateMasterRead([MREADLIST[1]]) end else return quote end end end)() ];
      [ (function() if MAX_WRITE_PORT>=1 then return quote V.deactivateMasterWrite([MWRITELIST[1]]) end else return quote end end end)() ];

--[=[
      for i=0,100 do
        if verbose then cstdio.printf("START CYCLE: RESET\n") end
        if i<50 then
          m:reset()
        end
        m:calculateReady()
        m:process(nil,nil)
      end
]=]
      var cycle = 0

      ----------------------------------------------- send start cmd
      if verbose then cstdio.printf("START CYCLE: SEND START CMD\n") end
        
      if [top:getGlobal("IP_SAXI0_AWADDR"):terraReady()]==false then
        cstdio.printf("IP_SAXI0_AWREADY should be true\n");
        cstdlib.exit(1)
      end
      
      data([top:getGlobal("IP_SAXI0_AWADDR"):terraValue()]) = 0xA0000000;
      valid([top:getGlobal("IP_SAXI0_AWADDR"):terraValue()]) = true;
      
      --------------------------------------------------- step
      m:calculateReady()
      m:process(nil,nil)
      
      if verbose then V.printSlave(S0LIST); end
      var found = V.checkSlaveResponse(S0LIST);
      
      if [top:getGlobal("IP_SAXI0_WDATA"):terraReady()]==false then
        cstdio.printf("IP_SAXI0_WREADY should be true\n");
        cstdlib.exit(1)
      end
      
      data([top:getGlobal("IP_SAXI0_WDATA"):terraValue()]) = 1;
      valid([top:getGlobal("IP_SAXI0_WDATA"):terraValue()]) = true;
      
      --------------------------------------------------- step
      m:calculateReady()
      m:process(nil,nil)
      
      found = found or V.checkSlaveResponse(S0LIST);
      
      valid([top:getGlobal("IP_SAXI0_AWADDR"):terraValue()]) = false;
      
      --------------------------------------------------- step
      m:calculateReady()
      m:process(nil,nil)
      
      while(found==false and V.checkSlaveResponse(S0LIST)==false) do
        cstdio.printf("Waiting for S0 response\n");
        m:calculateReady()
        m:process(nil,nil)
      end
      
      V.activateMasterRead([MREADLIST[0]])
      V.activateMasterWrite([MWRITELIST[0]])
      
      [ (function() if MAX_READ_PORT>=1 then return quote V.activateMasterRead([MREADLIST[1]]) end else return quote end end end)() ];
      [ (function() if MAX_WRITE_PORT>=1 then return quote V.activateMasteWrite([MWRITELIST[1]]) end else return quote end end end)() ];

      var totalCycles = simCycles+extraCycles

      var lastPct : int = -1

      var startSec = currentTimeInSeconds()

      var cooldownCycles = 10000
      var cooldownTime = false

      var cyclesToDoneSignal = -1
      while (cycle<totalCycles) and (cooldownCycles>0) do
        if verbose then cstdio.printf("--------------------------- START CYCLE %d (round %d) -----------------------\n",cycle,round) end
        
        m:calculateReady()
        
        -- feed data in
        V.masterReadData(verbose,memory,[MREADLIST[0]]);
        [ (function() if MAX_READ_PORT>=1 then return quote V.masterReadData(verbose,memory,[MREADLIST[1]]) end else return quote end end end)() ];

        m:process(nil,nil)

        if verbose then V.printMasterRead([MREADLIST[0]]); end
        if verbose then V.printMasterWrite([MWRITELIST[0]]); end

        V.masterWriteData(verbose,memory,[MWRITELIST[0]]);
        [ (function() if MAX_WRITE_PORT>=1 then return quote V.masterWriteData(verbose,memory,[MWRITELIST[1]]) end else return quote end end end)() ];

        -- get data out
        V.masterReadReq(verbose,MEMBASE,MEMSIZE,[MREADLIST[0]]);
        V.masterWriteReq(verbose,MEMBASE,MEMSIZE,[MWRITELIST[0]]);

        [ (function() if MAX_READ_PORT>=1 then return quote V.masterReadReq(verbose,MEMBASE,MEMSIZE,[MREADLIST[1]]) end else return quote end end end)() ];
        [ (function() if MAX_WRITE_PORT>=1 then return quote V.masterWriteReq(verbose,MEMBASE,MEMSIZE,[MWRITELIST[1]]) end else return quote end end end)() ];

        if((cycle*100)/totalCycles>lastPct) then
          var t = currentTimeInSeconds() - startSec

          var pct = (cycle*100)/totalCycles
          cstdio.printf("Sim %d %% complete! (%d/%d cycles) (%f sec elapsed, %f to go) (%d bytes read, %d bytes written)\n",pct,cycle,totalCycles,t,t*([float](100-pct))/([float](pct)),V.bytesRead(),V.bytesWritten())
          lastPct = (cycle*100)/totalCycles
        end

        if [SOCMT.doneHack] and cooldownTime==false then
          cstdio.printf("Start Cooldown\n")
          cyclesToDoneSignal = cycle
          cooldownTime = true
        end

        if cooldownTime then
          cooldownCycles = cooldownCycles - 1
        end
        
        cycle = cycle + 1
      end

      cstdio.printf("Executed cycles: %d, Cycles to Done:%d\n", cycle, cyclesToDoneSignal)

      if round==ROUNDS-1 then
        m:free()
        cstdlib.free(m)
      end

      writeS

      var errored = V.checkPorts();

      if [SOCMT.doneHack]==false then
        cstdio.printf("Error: Done bit not set at end of time!\n")
        errored = true
      end
    
      if(errored) then
        cstdlib.exit(1);
      end

    end
  end

  dosim()
end
