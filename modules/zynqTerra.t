local MT = require "modulesTerra"
local AXI = require "axi"
local AXIT = require "axiTerra"
local types = require "types"

local function makeTerra()
  local struct ZynqNOCTerra{ SAXI0_ARADDR:uint32,
                             SAXI0_ARVALID:bool,
                             SAXI0_ARREADY:bool,
                             SAXI0_ARLEN:uint8,
                             SAXI0_ARSIZE:uint8,
                             SAXI0_ARBURST:uint8,
                             SAXI0_ARID:uint8,
                             SAXI0_ARPROT:uint8,
                             SAXI0_AWADDR:uint32,
                             SAXI0_AWVALID:bool,
                             SAXI0_AWREADY:bool,
                             SAXI0_AWLEN:uint8,
                             SAXI0_AWBURST:uint8,
                             SAXI0_AWSIZE:uint8,
                             SAXI0_AWID:uint8,
                             SAXI0_RDATA:uint32,
                             SAXI0_WDATA:uint32,
                             SAXI0_WSTRB:uint8,
                             SAXI0_WLAST:bool,
                             SAXI0_WID:uint8,
                             SAXI0_RVALID:bool,
                             --SAXI0_RREADY:bool,
                             SAXI0_BRESP:uint8,
                             SAXI0_BVALID:bool,
                             --SAXI0_BREADY:bool,
                             SAXI0_RRESP:uint8,
                             SAXI0_RLAST:bool,
                             SAXI0_RID:uint8,
                             SAXI0_WVALID:bool,
                             SAXI0_WREADY:bool,
                             SAXI0_BID:uint8,

                             --MAXI0_ARREADY:bool,
                             MAXI0_RDATA:uint64,
                             MAXI0_RVALID:bool,
                             MAXI0_RID:uint8,
                             MAXI0_RRESP:uint8,
                             MAXI0_RLAST:bool,
                             MAXI0_ARADDR:uint32,
                             MAXI0_ARVALID:bool,
                             MAXI0_RREADY:bool,
                             MAXI0_ARLEN:uint8,
                             MAXI0_ARSIZE:uint8,
                             MAXI0_ARID:uint8,
                             MAXI0_ARPROT:uint8,
                             MAXI0_ARBURST:uint8,

                             --MAXI0_AWREADY:bool,
                             MAXI0_AWADDR:uint32,
                             MAXI0_AWLEN:uint8,
                             MAXI0_AWSIZE:uint8,
                             MAXI0_AWBURST:uint8,
                             MAXI0_AWVALID:bool,
                             MAXI0_AWID:uint8,
                             MAXI0_WDATA:uint64,
                             MAXI0_WSTRB:uint8,
                             MAXI0_WLAST:bool,
                             MAXI0_WID:uint8,
                             MAXI0_WVALID:bool,
                             --MAXI0_WREADY:bool,
                             MAXI0_BRESP:uint8,
                             MAXI0_BVALID:bool,
                             MAXI0_BREADY:bool,
                             MAXI0_BID:uint8,
                             
                             readSink_ready:bool, -- SAXI0_RREADY (driven by TB)
                             writeSink_ready:bool, -- SAXI0_BREADY (driven by TB)
                             read_ready:bool,   -- MAXI0_ARREADY (driven by TB)
                             write_ready:bool[2] -- 0:MAXI0_AWREADY, 1:MAXI0_WREADY (driven by TB)
                           }

  terra ZynqNOCTerra:read( inp : &types.lower(AXI.ReadAddress64):toTerraType(), out : &types.lower(AXI.ReadData64):toTerraType() )
    @AXIT.RVALID64(out) = self.MAXI0_RVALID;
    @AXIT.RDATA64(out) = self.MAXI0_RDATA;
    @AXIT.RLAST64(out) = self.MAXI0_RLAST;
    @AXIT.RRESP64(out) = self.MAXI0_RRESP;
    @AXIT.RID64(out) = self.MAXI0_RID;

    self.MAXI0_ARVALID = @AXIT.ARVALID64(inp);
    self.MAXI0_ARADDR = @AXIT.ARADDR64(inp);
    self.MAXI0_ARSIZE = @AXIT.ARSIZE64(inp);
    self.MAXI0_ARLEN = @AXIT.ARLEN64(inp);
    self.MAXI0_ARBURST = @AXIT.ARBURST64(inp);
    self.MAXI0_ARID = @AXIT.ARID64(inp);
    self.MAXI0_ARPROT = @AXIT.ARPROT64(inp);
  end

  terra ZynqNOCTerra:write( inp : &types.lower(AXI.WriteIssue64):toTerraType(), out : &types.lower(AXI.WriteResponse64):toTerraType() )
    self.MAXI0_AWVALID = @AXIT.AWVALID64(inp) 
    self.MAXI0_AWADDR = @AXIT.AWADDR64(inp) 
    self.MAXI0_AWLEN = @AXIT.AWLEN64(inp) 
    self.MAXI0_AWBURST = @AXIT.AWBURST64(inp) 
    self.MAXI0_AWSIZE = @AXIT.AWSIZE64(inp) 
    self.MAXI0_AWID = @AXIT.AWID64(inp) 
    
    self.MAXI0_WVALID = @AXIT.WVALID64(inp) 
    self.MAXI0_WDATA = @AXIT.WDATA64(inp) 
    self.MAXI0_WSTRB = @AXIT.WSTRB64(inp) 
    self.MAXI0_WLAST = @AXIT.WLAST64(inp) 
    self.MAXI0_WID = @AXIT.WID64(inp) 

    @AXIT.BVALID64(out) = self.MAXI0_BVALID
    @AXIT.BRESP64(out) = self.MAXI0_BRESP
    @AXIT.BID64(out) = self.MAXI0_BID
  end

  terra ZynqNOCTerra:read_calculateReady(inp:bool)
    self.MAXI0_RREADY = inp
  end

  terra ZynqNOCTerra:write_calculateReady(inp:bool)
    self.MAXI0_BREADY = inp
  end

  terra ZynqNOCTerra:readSource_calculateReady(inp:bool)
    self.SAXI0_ARREADY = inp
  end

  terra ZynqNOCTerra:readSource(out:&types.lower(AXI.ReadAddress):toTerraType())
    @AXIT.ARVALID32(out) = self.SAXI0_ARVALID;
    @AXIT.ARADDR32(out) = self.SAXI0_ARADDR;
    @AXIT.ARLEN32(out) = self.SAXI0_ARLEN;
    @AXIT.ARSIZE32(out) = self.SAXI0_ARSIZE;
    @AXIT.ARBURST32(out) = self.SAXI0_ARBURST;
    @AXIT.ARID32(out) = self.SAXI0_ARID;
    @AXIT.ARPROT32(out) = self.SAXI0_ARPROT;
  end

  terra ZynqNOCTerra:readSink(inp:&types.lower(AXI.ReadData(32)):toTerraType())
    self.SAXI0_RVALID = @AXIT.RVALID32(inp)
    self.SAXI0_RDATA = @AXIT.RDATA32(inp)
    self.SAXI0_RLAST = @AXIT.RLAST32(inp)
    self.SAXI0_RRESP = @AXIT.RRESP32(inp)
    self.SAXI0_RID = @AXIT.RID32(inp)
  end

  terra ZynqNOCTerra:writeSource(out:&types.lower(AXI.WriteIssue(32)):toTerraType())
    @AXIT.AWVALID32(out) = self.SAXI0_AWVALID;
    @AXIT.AWADDR32(out) = self.SAXI0_AWADDR;
    @AXIT.AWLEN32(out) = self.SAXI0_AWLEN;
    @AXIT.AWBURST32(out) = self.SAXI0_AWBURST;
    @AXIT.AWSIZE32(out) = self.SAXI0_AWSIZE;
    @AXIT.AWID32(out) = self.SAXI0_AWID;

    @AXIT.WVALID32(out) = self.SAXI0_WVALID;
    @AXIT.WDATA32(out) = self.SAXI0_WDATA;
    @AXIT.WSTRB32(out) = self.SAXI0_WSTRB;
    @AXIT.WLAST32(out) = self.SAXI0_WLAST;
    @AXIT.WID32(out) = self.SAXI0_WID;
  end

  terra ZynqNOCTerra:writeSource_calculateReady(inp:bool[2])
    self.SAXI0_AWREADY = inp[0]
    self.SAXI0_WREADY = inp[1]
  end

  terra ZynqNOCTerra:writeSink(inp:&types.lower(AXI.WriteResponse(32)):toTerraType())
    self.SAXI0_BVALID = @AXIT.BVALID32(inp)
    self.SAXI0_BRESP = @AXIT.BRESP32(inp)
    self.SAXI0_BID = @AXIT.BID32(inp)
  end

  return MT.new(ZynqNOCTerra)
end

return makeTerra
