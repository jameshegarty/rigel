local SOC = require "soc"
local cstdlib = terralib.includec("stdlib.h")
local cstdio = terralib.includec("stdio.h")

local function resetMAXI(top,port)
  return quote
  [top:getGlobal("IP_MAXI"..port.."_ARADDR"):terraReady()] = false
  [top:getGlobal("IP_MAXI"..port.."_AWADDR"):terraReady()] = false
  [top:getGlobal("IP_MAXI"..port.."_WDATA"):terraReady()] = false
  end
end

local chack = terralib.includecstring([[
#include <stdio.h>

void loadFile( char* filename, unsigned char* memory, unsigned int addrOffset ){
printf("LOADFILE %s\n",filename);
    FILE* infile = fopen( filename, "rb" );
    if(infile==NULL){printf("could not open input '%s'\n", filename);}
    fseek(infile, 0L, SEEK_END);
    unsigned long insize = ftell(infile);
    fseek(infile, 0L, SEEK_SET);
    fread( memory+addrOffset, insize, 1, infile );
    fclose( infile );
}

/*
void saveFile( char* filename, unsigned char* memory, unsigned int addrOffset, unsigned int bytes ){
    FILE* outfile = fopen(outFilename.c_str(),"wb");
    if(outfile==NULL){printf("could not open output '%s'\n", outFilename.c_str());}
    fwrite( memory+addrOffset, bytes, 1, outfile);
    fclose(outfile);
std::queue<int> a;
a.size();
}
*/
]])

return function(top, memStart, memEnd)
  local simCycles = top.sdfInput[1][2]/top.sdfInput[1][1]
  local Module = top:toTerra()

  local memory = symbol(&uint8)
  
  local readS = {}
  local writeS = {}

  local MEMBASE = 0x30008000
  local MEMSIZE = SOC.currentAddr-MEMBASE
  
  for i=0,SOC.ports do
    if top.globalMetadata["MAXI"..i.."_read_filename"]~=nil then
      local ll = {top.globalMetadata["MAXI"..i.."_read_filename"], memory, top.globalMetadata["MAXI"..i.."_read_address"]-MEMBASE}
      table.insert(readS,quote chack.loadFile(ll) end )
    end

    if top.globalMetadata["MAXI"..i.."_write_filename"]~=nil then
--      fn.globalMetadata["MAXI"..i.."_write_W"]
--      fn.globalMetadata["MAXI"..i.."_write_H"]
--      fn.globalMetadata["MAXI"..i.."_write_bitsPerPixel"]
      --      fn.globalMetadata["MAXI"..i.."_write_address"]
--      table.insert(writeS, quote chack.saveFile() end)
    end
  end
  
  local terra dosim()
    var m = [&Module](cstdlib.malloc(sizeof(Module))); 
    m:init()
    m:reset();

    var [memory] = [&uint8](cstdlib.malloc(MEMSIZE))

    readS
    [resetMAXI(top,0)]
    
    var cycle = 0
    
    while(cycle<simCycles) do
      m:calculateReady()
      m:process(nil,nil)
      cycle = cycle + 1
    end
    
    m:free()
    cstdlib.free(m)

    writeS
  end

  dosim()
end
