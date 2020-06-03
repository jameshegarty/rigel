local SOC = require "generators.soc"
local SOCMT = require "generators.socTerra"
local cstdlib = terralib.includec("stdlib.h", {"-Wno-nullability-completeness"})
local cstdio = terralib.includec("stdio.h", {"-Wno-nullability-completeness"})
local clocale = terralib.includec("locale.h", {"-Wno-nullability-completeness"})
local J = require "common"
local Uniform = require "uniform"
local Zynq = require "generators.zynq"
local types = require "types"
local AXI = require "generators.axi"

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)
local ready = macro(function(i) return `i._2 end)

function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

V = terralib.includec(script_path().."../platform/verilatorSOC/harness.h", {"-Wno-nullability-completeness"})

local Ctmp = terralib.includecstring([[
                                        #include <stdio.h>
                                          #include <stdlib.h>
                                          #include <sys/time.h>
                                          #include <assert.h>
                                          #include <stdint.h>
                                          #include <inttypes.h>
                                          double CurrentTimeInSecondsHT() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return tv.tv_sec + tv.tv_usec / 1000000.0;
                                 }
                                   ]], {"-Wno-nullability-completeness"})

local Locale = terralib.includecstring([[
#include <locale.h>
void enableCommas(){setlocale(LC_NUMERIC, "");}
]], {"-Wno-nullability-completeness"})

local currentTimeInSeconds = Ctmp.CurrentTimeInSecondsHT

return function(top, options)
  
  local simCycles
  if options~=nil and options.cycles~=nil then
    simCycles = options.cycles
  else
    simCycles = (top.sdfInput[1][2]):toNumber()/(top.sdfInput[1][1]):toNumber()
  end
  
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

  -- auto-discover the noc from the requires list. No correctness checking!
  local NOC
  local noc
  assert( J.keycount(top.requires)==1 )
  for inst,_ in pairs(top.requires) do
    noc=inst
    NOC=inst:terraReference()
  end

  local regs
  assert( J.keycount(top.provides)==1 )
  for inst,_ in pairs(top.provides) do
    regs = inst:terraReference()
    print("REGS",regs)
  end
  
  local S0LIST = {
    0,
    `IP_CLK,
    `IP_ARESET_N,
    `&NOC.SAXI0_ARADDR,
    `[&uint8](&NOC.SAXI0_ARVALID),
    `[&uint8](&NOC.SAXI0_ARREADY),
    `&NOC.SAXI0_AWADDR,
    `[&uint8](&NOC.SAXI0_AWVALID),
    `[&uint8](&NOC.SAXI0_AWREADY),
    `&NOC.SAXI0_RDATA,
    `[&uint8](&NOC.SAXI0_RVALID),
    `[&uint8](&NOC.readSink_ready),
    `&NOC.SAXI0_BRESP,
    `[&uint8](&NOC.SAXI0_BVALID),
    `[&uint8](&NOC.writeSink_ready),
    `&NOC.SAXI0_RRESP,
    `[&uint8](&NOC.SAXI0_WVALID),
    `[&uint8](&NOC.SAXI0_WREADY)
  }

  local MREAD_SLAVEOUT={}
  local MREAD_SLAVEIN={}
  local MWRITE_SLAVEOUT={}
  local MWRITE_SLAVEIN={}

  local MAX_READ_PORT = noc.module.readPorts-1
  local MAX_WRITE_PORT = noc.module.writePorts-1

  for i=0,noc.module.readPorts-1 do
    local I = J.sel(i==0,"",tostring(i))
      MREAD_SLAVEOUT[i] = {
        `[&uint8](&NOC.["read"..I.."_ready"]),
        `&NOC.["MAXI"..i.."_RDATA"],
        `[&uint8](&NOC.["MAXI"..i.."_RVALID"]),
        `&NOC.["MAXI"..i.."_RRESP"],
        `[&uint8](&NOC.["MAXI"..i.."_RLAST"]),
        `&NOC.["MAXI"..i.."_RID"]
      }

      MREAD_SLAVEIN[i] = {
        `&NOC.["MAXI"..i.."_ARADDR"],
        `[&uint8](&NOC.["MAXI"..i.."_ARVALID"]),
        `[&uint8](&NOC.["MAXI"..i.."_RREADY"]),
        `&NOC.["MAXI"..i.."_ARLEN"],
        `&NOC.["MAXI"..i.."_ARSIZE"],
        `&NOC.["MAXI"..i.."_ARBURST"],
        `&NOC.["MAXI"..i.."_ARID"]
      }
  end
  
  for i=0,noc.module.writePorts-1 do
    local I = J.sel(i==0,"",tostring(i))
    
    MWRITE_SLAVEOUT[i] = {
      `[&uint8](&NOC.["write"..I.."_ready"]._0),
      `[&uint8](&NOC.["write"..I.."_ready"]._1),
      `&NOC.["MAXI"..i.."_BRESP"],
      `[&uint8](&NOC.["MAXI"..i.."_BVALID"]),
      `&NOC.["MAXI"..i.."_BID"]
    }

    MWRITE_SLAVEIN[i] = {
      `&NOC.["MAXI"..i.."_AWADDR"],
      `[&uint8](&NOC.["MAXI"..i.."_AWVALID"]),
      `&NOC.["MAXI"..i.."_WDATA"],
      `[&uint8](&NOC.["MAXI"..i.."_WVALID"]),
      `[&uint8](&NOC.["MAXI"..i.."_BREADY"]),
      `&NOC.["MAXI"..i.."_WSTRB"],
      `[&uint8](&NOC.["MAXI"..i.."_WLAST"]),
      `&NOC.["MAXI"..i.."_AWLEN"],
      `&NOC.["MAXI"..i.."_AWSIZE"],
      `&NOC.["MAXI"..i.."_AWBURST"],
      `&NOC.["MAXI"..i.."_AWID"]}
  end

  local clearOutputs = {}
  for k,v in pairs(top.globalMetadata) do
    if k:sub(#k-13)=="_read_filename" then
      local prefix = k:sub(1,#k-14)

      if top.globalMetadata[prefix.."_read_filename"]~=nil then
        table.insert( readS, quote V.loadFile([top.globalMetadata[prefix.."_read_filename"]], memory, [Uniform(top.globalMetadata[prefix.."_read_address"]-MEMBASE):toTerra()]) end )
      end
    end
  end

  for k,v in pairs(top.globalMetadata) do
    if k:sub(#k-14)=="_write_filename" then
      local prefix = k:sub(1,#k-15)

      if top.globalMetadata[prefix.."_write_filename"]~=nil then
        local bytes = Uniform((top.globalMetadata[prefix.."_write_W"]*top.globalMetadata[prefix.."_write_H"]*top.globalMetadata[prefix.."_write_bitsPerPixel"])/8)
        table.insert( writeS, quote
                    var addr = [Uniform(top.globalMetadata[prefix.."_write_address"]-MEMBASE):toTerra()]
                    if addr+[bytes:toTerra()]>MEMSIZE then
                      cstdio.printf("ERROR: requested to read file outside of memory segment? addr:%d bytes:%d\n",addr,[bytes:toTerra()])
                      cstdlib.exit(1)
                    end
                    V.saveFile([top.globalMetadata[prefix.."_write_filename"]..".terra.raw"], memory, addr, [bytes:toTerra()] ) end )

        table.insert( clearOutputs, quote for ii=0,[bytes:toTerra()],4 do @[&uint32](memory+[Uniform(top.globalMetadata[prefix.."_write_address"]-MEMBASE):toTerra()]+ii)=0xbaadf00d; end end )
      end
    end
  end

  -- this is a total hack, just to save us having to rewrite some code...
--print("SLAVES",types.lower(AXI.ReadAddress32),types.lower(AXI.ReadData(32)))
  local terra stepSlaves()
    regs:read_calculateReady(NOC.readSink_ready)
    NOC:readSource_calculateReady(regs.read_ready)

    var AR : types.lower(AXI.ReadAddress32):toTerraType()
    var RDATA : types.lower(AXI.ReadData(32)):toTerraType()
    NOC:readSource(&AR)
    regs:read(&AR,&RDATA)
    NOC:readSink(&RDATA)

    regs:write_calculateReady(NOC.writeSink_ready)
    NOC:writeSource_calculateReady(regs.write_ready)

    var AW : types.lower(AXI.WriteIssue(32)):toTerraType()
    var WriteResp : types.lower(AXI.WriteResponse(32)):toTerraType()
    NOC:writeSource(&AW)
    regs:write(&AW,&WriteResp)
    NOC:writeSink(&WriteResp)
  end

  local terra setReg([IP_CLK], [IP_ARESET_N],m:&Module, addr:uint, writeData:uint)

    stepSlaves()
    m:calculateReady()
    m:process(nil)

    Locale.enableCommas()

    var srVerbose = true
    ----------------------------------------------- send start cmd
    if verbose or srVerbose then cstdio.printf("harnessTerra: WRITE REG addr:%x data:%d/0x%x\n",addr,writeData,writeData) end
  
    if NOC.SAXI0_AWREADY==false then
      cstdio.printf("IP_SAXI0_AWREADY should be true\n");
      cstdlib.exit(1)
    end
      
    NOC.SAXI0_AWADDR = addr;
    NOC.SAXI0_AWVALID = true;
    NOC.SAXI0_WDATA = writeData;
    NOC.SAXI0_WVALID = true;
    
    --------------------------------------------------- step
    stepSlaves()
    m:calculateReady()
    m:process(nil)
      
    var found = V.checkSlaveWriteResponse(S0LIST);
      
    NOC.SAXI0_AWVALID = false;
      
    --------------------------------------------------- step
    stepSlaves()
    m:calculateReady()
    m:process(nil)
      
    while(found==false and V.checkSlaveWriteResponse(S0LIST)==false) do
      cstdio.printf("Waiting for S0 response\n");
      stepSlaves()
      m:calculateReady()
      m:process(nil)
    end
  end

  local setTaps = {}

  local m = symbol(&Module)

  -- load default values into the registers
  for k,v in pairs(top.globalMetadata) do
    if string.sub(k,0,8)=="Register" then
      local addr = string.sub(k,10)

      local bytes = #v/2
      local addr = tonumber("0x"..addr)

      local numints = math.ceil(bytes/4)-1
      for b=0,numints do
        local dat = string.sub(v,b*8+1,(b+1)*8)
        local data = tonumber("0x"..dat)
        table.insert(setTaps,quote setReg([IP_CLK],[IP_ARESET_N],[m],[addr+(numints+1)*4-4-b*4],data) end)
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

    var NOCINST : noc.module.terraModule
    [NOC] = &NOCINST
    NOC:reset()
    
    var [m] = [&Module](cstdlib.malloc(sizeof(Module))); 
    m:init()
    m:reset();

    var [memory] = [&uint8](cstdlib.malloc(MEMSIZE))

    V.init()

    var ROUNDS = 2
    for round=0,ROUNDS do
      if verbose then cstdio.printf("ROUND %d\n",round) end


      [ (function() if MAX_READ_PORT>=0 then return quote V.deactivateMasterRead([MREAD_SLAVEOUT[0]]) end else return quote end end end)() ];
      V.deactivateMasterWrite([MWRITE_SLAVEOUT[0]])
      
      [ (function() if MAX_READ_PORT>=1 then return quote V.deactivateMasterRead([MREAD_SLAVEOUT[1]]) end else return quote end end end)() ];
      [ (function() if MAX_WRITE_PORT>=1 then return quote V.deactivateMasterWrite([MWRITE_SLAVEOUT[1]]) end else return quote end end end)() ];

      var cycle = 0

      [setTaps]
      if round==0 then [clearOutputs] end
      [readS]

      -- set start bit
      setReg( IP_CLK, IP_ARESET_N, m, 0xA0000000, 1 )
      
      [ (function() if MAX_READ_PORT>=0 then return quote V.activateMasterRead([MREAD_SLAVEOUT[0]]) end else return quote end end end)() ];
      V.activateMasterWrite([MWRITE_SLAVEOUT[0]])

      [ (function() if MAX_READ_PORT>=1 then return quote V.activateMasterRead([MREAD_SLAVEOUT[1]]) end else return quote end end end)() ];
      [ (function() if MAX_WRITE_PORT>=1 then return quote V.activateMasteWrite([MWRITE_SLAVEOUT[1]]) end else return quote end end end)() ];

      var totalCycles = simCycles+extraCycles
      cstdio.printf( "SimCycles %d extraCycles %d\n", simCycles, extraCycles )
      
      var lastPct : int = -1

      var startSec = currentTimeInSeconds()

      var cooldownCycles = 1000
      if(totalCycles/10<cooldownCycles) then cooldownCycles=totalCycles/10; end
      var cooldownTime = false

      var cyclesToDoneSignal = -1

      var doneBitSet : bool = false
      while (doneBitSet==false or cooldownCycles>0 or cycle<totalCycles) do
        if verbose then cstdio.printf("--------------------------- START CYCLE %d (round %d) -----------------------\n",cycle,round) end

        [ (function() if MAX_READ_PORT>=0 then return quote V.masterReadDataDriveOutputs(verbose,memory,0,[MREAD_SLAVEOUT[0]]) end else return quote end end end)() ];
        [ (function() if MAX_READ_PORT>=1 then return quote V.masterReadDataDriveOutputs(verbose,memory,1,[MREAD_SLAVEOUT[1]]) end else return quote end end end)() ];

        V.masterWriteDataDriveOutputs(verbose,memory,&slaveState0,0,[MWRITE_SLAVEOUT[0]]);
        [ (function() if MAX_WRITE_PORT>=1 then return quote V.masterWriteDataDriveOutputs(verbose,memory,&slaveState1,1,[MWRITE_SLAVEOUT[1]]) end else return quote end end end)() ];

        [ (function() if MAX_READ_PORT>=0 then return quote V.masterReadReqDriveOutputs(verbose,MEMBASE,MEMSIZE,0,[MREAD_SLAVEOUT[0]]) end else return quote end end end)() ];
        V.masterWriteReqDriveOutputs(verbose,MEMBASE,MEMSIZE,0,[MWRITE_SLAVEOUT[0]]);

        [ (function() if MAX_READ_PORT>=1 then return quote V.masterReadReqDriveOutputs(verbose,MEMBASE,MEMSIZE,1,[MREAD_SLAVEOUT[1]]) end else return quote end end end)() ];

        [ (function() if MAX_WRITE_PORT>=1 then return quote V.masterWriteReqDriveOutputs(verbose,MEMBASE,MEMSIZE,1,[MWRITE_SLAVEOUT[1]]) end else return quote end end end)() ];

        stepSlaves()
        m:calculateReady()
        m:process(nil)

        [ (function() if MAX_READ_PORT>=0 then return quote V.masterReadDataLatchFlops(verbose,memory,0,[MREAD_SLAVEIN[0]]) end else return quote end end end)() ];

        [ (function() if MAX_READ_PORT>=1 then return quote V.masterReadDataLatchFlops(verbose,memory,1,[MREAD_SLAVEIN[1]]) end else return quote end end end)() ];

        if verbose then
          [ (function() if MAX_READ_PORT>=0 then return quote V.printMasterRead(0,[MREAD_SLAVEIN[0]],[MREAD_SLAVEOUT[0]]) end else return quote end end end)() ];
        end
        if verbose then V.printMasterWrite(0,[MWRITE_SLAVEIN[0]],[MWRITE_SLAVEOUT[0]]); end


        if V.masterWriteDataLatchFlops(verbose,memory,&slaveState0,0,round==1,[MWRITE_SLAVEIN[0]])~=0 then
          cstdlib.exit(1)
        end
        

        [ (function() if MAX_WRITE_PORT>=1 then return quote if V.masterWriteDataLatchFlops(verbose,memory,&slaveState1,1,round==1,[MWRITE_SLAVEIN[1]])~=0 then cstdlib.exit(1) end end else return quote end end end)() ];

        [ (function() if MAX_READ_PORT>=0 then return quote V.masterReadReqLatchFlops(verbose,MEMBASE,MEMSIZE,0,[MREAD_SLAVEIN[0]]) end else return quote end end end)() ];

        V.masterWriteReqLatchFlops(verbose,MEMBASE,MEMSIZE,0,[MWRITE_SLAVEIN[0]]);

        [ (function() if MAX_READ_PORT>=1 then return quote V.masterReadReqLatchFlops(verbose,MEMBASE,MEMSIZE,1,[MREAD_SLAVEIN[1]]) end else return quote end end end)() ];

        [ (function() if MAX_WRITE_PORT>=1 then return quote V.masterWriteReqLatchFlops(verbose,MEMBASE,MEMSIZE,1,[MWRITE_SLAVEIN[1]]) end else return quote end end end)() ];

        if((cycle*100)/totalCycles>lastPct) then
          var t = currentTimeInSeconds() - startSec

          var pct = (cycle*100)/totalCycles
          cstdio.printf("Sim %d: %d %% complete! (%'d/%'d cycles) (%f sec elapsed, %f to go) (%'d bytes read, %'d bytes written)\n",round,pct,cycle,totalCycles,t,t*([float](100-pct))/([float](pct)),V.bytesRead(),V.bytesWritten())
          lastPct = (cycle*100)/totalCycles
        end

        if cycle % 100 == 0 then
          V.slaveReadReq(0xA0000000+4,S0LIST)
        end

        var db : uint32
        if V.checkSlaveReadResponse(S0LIST,&db) then
          if db==1 then
            doneBitSet=true

            var errored = V.checkPorts(true);
            if errored then
              cstdio.printf("Pipeline not actually done when done bit was set?\n")
            end
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

      writeS

      if round==ROUNDS-1 then
        m:free()
        cstdlib.free(m)
      end


      var errored = V.checkPorts(false);

      if doneBitSet==false then
        cstdio.printf("Error: Done bit not set at end of time!\n")
        errored = true
      end
    
      if(errored) then
        cstdlib.exit(1);
      end

      -- write cycles to file
      var f = cstdio.fopen([top.globalMetadata[noc.write.name.."_write_filename"]..".terra.cycles.txt"], "w");
      if f==nil then
        cstdio.printf("Error opening file '%s'!\n",[top.globalMetadata[noc.write.name.."_write_filename"]..".terra.cycles.txt"]);
        cstdlib.exit(1);
      end
      cstdio.fprintf(f,"%d",cyclesToDoneSignal)
      cstdio.fclose(f)

    end
  end

  dosim()
end
