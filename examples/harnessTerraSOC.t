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
  local extraCycles = math.max(math.floor(simCycles/10),1024)
  
  local Module = top:toTerra()

  local memory = symbol(&uint8)
  local IP_CLK = symbol(&uint8)
  local IP_ARESET_N = symbol(&uint8)
  
  local readS = {}
  local writeS = {}

  local MEMBASE = 0x30008000
  local MEMSIZE = SOC.currentAddr-MEMBASE

  local verbose = false
  
  local S0LIST = {
    0,
    `IP_CLK,
    `IP_ARESET_N,
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
    `[&uint8](&[top:getGlobal("IP_SAXI0_BRESP"):terraReady()]),
    `&[top:getGlobal("IP_SAXI0_RRESP"):terraValue()],
    `[&uint8](&valid([top:getGlobal("IP_SAXI0_WDATA"):terraValue()])),
    `[&uint8](&[top:getGlobal("IP_SAXI0_WDATA"):terraReady()]),}

  local MREAD_SLAVEOUT={}
  local MREAD_SLAVEIN={}
  local MWRITE_SLAVEOUT={}
  local MWRITE_SLAVEIN={}

  local MAX_READ_PORT = -1
  local MAX_WRITE_PORT = -1
  
  for i=0,SOC.ports do
    if top:getGlobal("IP_MAXI"..i.."_ARADDR")~=nil then
      MAX_READ_PORT = i
      MREAD_SLAVEOUT[i] = {
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_ARADDR"):terraReady()]),
        `&data([top:getGlobal("IP_MAXI"..i.."_RDATA"):terraValue()]),
        `[&uint8](&valid([top:getGlobal("IP_MAXI"..i.."_RDATA"):terraValue()])),
        `&[top:getGlobal("IP_MAXI"..i.."_RRESP"):terraValue()],
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_RLAST"):terraValue()])}

      MREAD_SLAVEIN[i] = {
        `&data([top:getGlobal("IP_MAXI"..i.."_ARADDR"):terraValue()]),
        `[&uint8](&valid([top:getGlobal("IP_MAXI"..i.."_ARADDR"):terraValue()])),
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_RDATA"):terraReady()]),
        `&[top:getGlobal("IP_MAXI"..i.."_ARLEN"):terraValue()],
        `&[top:getGlobal("IP_MAXI"..i.."_ARSIZE"):terraValue()],
        `&[top:getGlobal("IP_MAXI"..i.."_ARBURST"):terraValue()]}
    end

    if top:getGlobal("IP_MAXI"..i.."_AWADDR")~=nil then
      MAX_WRITE_PORT = i
      MWRITE_SLAVEOUT[i] = {
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_AWADDR"):terraReady()]),
        `[&uint8](&[top:getGlobal("IP_MAXI"..i.."_WDATA"):terraReady()]),
        `&data([top:getGlobal("IP_MAXI"..i.."_BRESP"):terraValue()]),
        `[&uint8](&valid([top:getGlobal("IP_MAXI"..i.."_BRESP"):terraValue()]))}

      MWRITE_SLAVEIN[i] = {
        `&data([top:getGlobal("IP_MAXI"..i.."_AWADDR"):terraValue()]),
        `[&uint8](&valid([top:getGlobal("IP_MAXI"..i.."_AWADDR"):terraValue()])),
        `&data([top:getGlobal("IP_MAXI"..i.."_WDATA"):terraValue()]),
        `[&uint8](&valid([top:getGlobal("IP_MAXI"..i.."_WDATA"):terraValue()])),
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

  local terra setReg([IP_CLK], [IP_ARESET_N],m:&Module, addr:uint, writeData:uint)
    var srVerbose = true
    ----------------------------------------------- send start cmd
    if verbose or srVerbose then cstdio.printf("WRITE REG addr:%x data:%d\n",addr,writeData) end
  
    if [top:getGlobal("IP_SAXI0_AWADDR"):terraReady()]==false then
      cstdio.printf("IP_SAXI0_AWREADY should be true\n");
      cstdlib.exit(1)
    end
      
    data([top:getGlobal("IP_SAXI0_AWADDR"):terraValue()]) = addr;
    valid([top:getGlobal("IP_SAXI0_AWADDR"):terraValue()]) = true;
    data([top:getGlobal("IP_SAXI0_WDATA"):terraValue()]) = writeData;
    valid([top:getGlobal("IP_SAXI0_WDATA"):terraValue()]) = true;
    
    --------------------------------------------------- step
    --[=[
    m:calculateReady()
    m:process(nil,nil)
      
    if verbose then V.printSlave(S0LIST); end
    var found = V.checkSlaveWriteResponse(S0LIST);
     
    if [top:getGlobal("IP_SAXI0_WDATA"):terraReady()]==false then
      cstdio.printf("IP_SAXI0_WREADY should be true\n");
      cstdlib.exit(1)
    end
      
    data([top:getGlobal("IP_SAXI0_WDATA"):terraValue()]) = writeData;
    valid([top:getGlobal("IP_SAXI0_WDATA"):terraValue()]) = true;
    ]=]

    --------------------------------------------------- step
    m:calculateReady()
    m:process(nil,nil)
      
    var found = V.checkSlaveWriteResponse(S0LIST);
      
    valid([top:getGlobal("IP_SAXI0_AWADDR"):terraValue()]) = false;
      
    --------------------------------------------------- step
    m:calculateReady()
    m:process(nil,nil)
      
    while(found==false and V.checkSlaveWriteResponse(S0LIST)==false) do
      cstdio.printf("Waiting for S0 response\n");
      m:calculateReady()
      m:process(nil,nil)
    end
  end

  local setTaps = {}

  local m = symbol(&Module)
  
  for k,v in pairs(top.globalMetadata) do
    if string.sub(k,0,8)=="Register" then
      local addr = string.sub(k,10)
      --table.insert(registerList,"['"..addr.."']='"..v.."'")
      print("REG",addr,v)
      local bytes = #v/2
      local addr = tonumber("0x"..addr)
      print("BYTES",bytes,"addr",addr)

      for b=0,bytes/4-1 do
        local dat = string.sub(v,b*8+1,(b+1)*8)
        local data = tonumber("0x"..dat)
        print("DAT",dat,data)
        table.insert(setTaps,quote setReg([IP_CLK],[IP_ARESET_N],[m],[addr+b*4],data) end)
      end
    end
  end

  local terra dosim()
    var ip_clk : uint8
    var [IP_CLK] = &ip_clk
    var ip_areset_n : uint8
    var [IP_ARESET_N] = &ip_areset_n

    var slaveState0 : V.SlaveState
    var slaveState1 : V.SlaveState
    V.initSlaveState(&slaveState0)
    V.initSlaveState(&slaveState1)
    
    var [m] = [&Module](cstdlib.malloc(sizeof(Module))); 
    m:init()
    m:reset();

    var [memory] = [&uint8](cstdlib.malloc(MEMSIZE))

    readS

    V.init()

    var ROUNDS = 2
    for round=0,ROUNDS do
      if verbose then cstdio.printf("ROUND %d\n",round) end

      clearOutputs

      V.deactivateMasterRead([MREAD_SLAVEOUT[0]])
      V.deactivateMasterWrite([MWRITE_SLAVEOUT[0]])
      
      [ (function() if MAX_READ_PORT>=1 then return quote V.deactivateMasterRead([MREAD_SLAVEOUT[1]]) end else return quote end end end)() ];
      [ (function() if MAX_WRITE_PORT>=1 then return quote V.deactivateMasterWrite([MWRITE_SLAVEOUT[1]]) end else return quote end end end)() ];

      var cycle = 0

      if round==0 then
        [setTaps]
      end

      setReg( IP_CLK, IP_ARESET_N, m, 0xA0000000, 1 )
      
      V.activateMasterRead([MREAD_SLAVEOUT[0]])
      V.activateMasterWrite([MWRITE_SLAVEOUT[0]])
      
      [ (function() if MAX_READ_PORT>=1 then return quote V.activateMasterRead([MREAD_SLAVEOUT[1]]) end else return quote end end end)() ];
      [ (function() if MAX_WRITE_PORT>=1 then return quote V.activateMasteWrite([MWRITE_SLAVEOUT[1]]) end else return quote end end end)() ];

      var totalCycles = simCycles+extraCycles
      cstdio.printf( "SimCycles %d extraCycles %d\n", simCycles, extraCycles )
      
      var lastPct : int = -1

      var startSec = currentTimeInSeconds()

      var cooldownCycles = 10000
      var cooldownTime = false

      var cyclesToDoneSignal = -1

      var doneBitSet : bool = false
      while (cycle<totalCycles) and (cooldownCycles>0) do
        if verbose then cstdio.printf("--------------------------- START CYCLE %d (round %d) -----------------------\n",cycle,round) end

        V.masterReadDataDriveOutputs(verbose,memory,0,[MREAD_SLAVEOUT[0]]);
        [ (function() if MAX_READ_PORT>=1 then return quote V.masterReadDataDriveOutputs(verbose,memory,1,[MREAD_SLAVEOUT[1]]) end else return quote end end end)() ];

        V.masterWriteDataDriveOutputs(verbose,memory,&slaveState0,0,[MWRITE_SLAVEOUT[0]]);
        [ (function() if MAX_WRITE_PORT>=1 then return quote V.masterWriteDataDriveOutputs(verbose,memory,&slaveState1,1,[MWRITE_SLAVEOUT[1]]) end else return quote end end end)() ];

        V.masterReadReqDriveOutputs(verbose,MEMBASE,MEMSIZE,0,[MREAD_SLAVEOUT[0]]);
        V.masterWriteReqDriveOutputs(verbose,MEMBASE,MEMSIZE,0,[MWRITE_SLAVEOUT[0]]);

        [ (function() if MAX_READ_PORT>=1 then return quote V.masterReadReqDriveOutputs(verbose,MEMBASE,MEMSIZE,1,[MREAD_SLAVEOUT[1]]) end else return quote end end end)() ];

        [ (function() if MAX_WRITE_PORT>=1 then return quote V.masterWriteReqDriveOutputs(verbose,MEMBASE,MEMSIZE,1,[MWRITE_SLAVEOUT[1]]) end else return quote end end end)() ];

        m:calculateReady()

        m:process(nil,nil)

        V.masterReadDataLatchFlops(verbose,memory,0,[MREAD_SLAVEIN[0]]);

        [ (function() if MAX_READ_PORT>=1 then return quote V.masterReadDataLatchFlops(verbose,memory,1,[MREAD_SLAVEIN[1]]) end else return quote end end end)() ];

        if verbose then V.printMasterRead(0,[MREAD_SLAVEIN[0]],[MREAD_SLAVEOUT[0]]); end
        if verbose then V.printMasterWrite(0,[MWRITE_SLAVEIN[0]],[MWRITE_SLAVEOUT[0]]); end


        V.masterWriteDataLatchFlops(verbose,memory,&slaveState0,0,[MWRITE_SLAVEIN[0]]);

        [ (function() if MAX_WRITE_PORT>=1 then return quote V.masterWriteDataLatchFlops(verbose,memory,&slaveState1,1,[MWRITE_SLAVEIN[1]]) end else return quote end end end)() ];

        V.masterReadReqLatchFlops(verbose,MEMBASE,MEMSIZE,0,[MREAD_SLAVEIN[0]]);

        V.masterWriteReqLatchFlops(verbose,MEMBASE,MEMSIZE,0,[MWRITE_SLAVEIN[0]]);

        [ (function() if MAX_READ_PORT>=1 then return quote V.masterReadReqLatchFlops(verbose,MEMBASE,MEMSIZE,1,[MREAD_SLAVEIN[1]]) end else return quote end end end)() ];

        [ (function() if MAX_WRITE_PORT>=1 then return quote V.masterWriteReqLatchFlops(verbose,MEMBASE,MEMSIZE,1,[MWRITE_SLAVEIN[1]]) end else return quote end end end)() ];

        if((cycle*100)/totalCycles>lastPct) then
          var t = currentTimeInSeconds() - startSec

          var pct = (cycle*100)/totalCycles
          cstdio.printf("Sim %d %% complete! (%d/%d cycles) (%f sec elapsed, %f to go) (%d bytes read, %d bytes written)\n",pct,cycle,totalCycles,t,t*([float](100-pct))/([float](pct)),V.bytesRead(),V.bytesWritten())
          lastPct = (cycle*100)/totalCycles
        end

        if cycle % 100 == 0 then
          V.slaveReadReq(0xA0000000+4,S0LIST)
        end

        var db : uint32
        if V.checkSlaveReadResponse(S0LIST,&db) then
          if db==1 then
            doneBitSet=true
          else
            doneBitSet=false
          end
        end

        if doneBitSet and cooldownTime==false then
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

      if doneBitSet==false then
        cstdio.printf("Error: Done bit not set at end of time!\n")
        errored = true
      end
    
      if(errored) then
        cstdlib.exit(1);
      end

      -- write cycles to file
      var f = cstdio.fopen([top.globalMetadata["MAXI0_write_filename"]..".terra.cycles.txt"], "w");
      if f==nil then
        cstdio.printf("Error opening file '%s'!\n",[top.globalMetadata["MAXI0_write_filename"]..".terra.cycles.txt"]);
        cstdlib.exit(1);
      end
      cstdio.fprintf(f,"%d",cyclesToDoneSignal)
      cstdio.fclose(f)

    end
  end

  dosim()
end
