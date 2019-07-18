local R = require "rigel"
local types = require "types"
local J = require "common"
local C = require "examplescommon"
local SDF = require "sdf"
local AXI = require "axi"
local RM = require "modules"
local G = require "generators"
local Bjump = {}

-- a direct mapped cache, with 'sets' number of blocks, each block of size ty:verilogBytes()*itemsPerBlock bytes
function Bjump.AXICachedRead( ty, itemsPerBlock, sets, readFn )
  J.err( types.isBasic(ty)," AXICachedRead: ty should be basic")
  J.err( type(itemsPerBlock)=="number", "itemsPerBlock should be number")
  J.err( type(sets)=="number", "sets should be number")

  assert(ty:verilogBits()==32)
  J.err( types.extractData(readFn.inputType):verilogBits()==32, "bjump cache: readFn should take in 32 bit address, but input type is: "..tostring(readFn.inputType) )
  J.err( types.extractData(readFn.outputType):verilogBits()==32, "bjump cache: readFn should return 32 bits, but output type is: "..tostring(readFn.outputType) )
  
  local INP = R.input(types.Handshake(types.uint(32)))
  print("INP",INP)
  local readFnInst = readFn:instantiate("read")
  local out = R.statements{RM.makeHandshake(C.bitcast(types.uint(32),ty))(INP),readFnInst(RM.makeHandshake(C.const(types.uint(32),0))())}
  local res = RM.lambda("Bjump_AXICachedRead",INP,out,{readFnInst})
  
  local bsg_defines = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_defines.v")
  local bsg_mem_1rw_sync_mask_write_bit_synth = C.VerilogFile("modules/bsg_ip_cores/bsg_mem/bsg_mem_1rw_sync_mask_write_bit_synth.v",{bsg_defines})
  local bsg_mem_1rw_sync_mask_write_bit = C.VerilogFile("modules/bsg_ip_cores/bsg_mem/bsg_mem_1rw_sync_mask_write_bit.v",{bsg_defines,bsg_mem_1rw_sync_mask_write_bit_synth})
  local bsg_mem_1rw_sync_synth = C.VerilogFile("modules/bsg_ip_cores/bsg_mem/bsg_mem_1rw_sync_synth.v",{bsg_defines})
  local bsg_mem_1rw_sync = C.VerilogFile("modules/bsg_ip_cores/bsg_mem/bsg_mem_1rw_sync.v",{bsg_defines,bsg_mem_1rw_sync_synth})
  local bsg_mem_1rw_sync_mask_write_byte_synth = C.VerilogFile("modules/bsg_ip_cores/bsg_mem/bsg_mem_1rw_sync_mask_write_byte_synth.v",{bsg_defines,bsg_mem_1rw_sync})
  local bsg_mem_1rw_sync_mask_write_byte = C.VerilogFile("modules/bsg_ip_cores/bsg_mem/bsg_mem_1rw_sync_mask_write_byte.v",{bsg_defines,bsg_mem_1rw_sync_mask_write_byte_synth})

  local bsg_mux_segmented = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_mux_segmented.v")
  local bsg_mux = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_mux.v",{bsg_defines})

  local bsg_cache_pkg = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache_pkg.v")
  local bsg_cache_pkt = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache_pkt.vh",{bsg_cache_pkg})
  local bsg_cache_miss = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache_miss.v")
  local bsg_cache_dma_pkt = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache_dma_pkt.vh")

  local bsg_circular_ptr = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_circular_ptr.v",{bsg_defines})
  local bsg_fifo_1rw_large = C.VerilogFile("modules/bsg_ip_cores/bsg_dataflow/bsg_fifo_1rw_large.v",{bsg_defines,bsg_circular_ptr})
  local bsg_fifo_tracker = C.VerilogFile("modules/bsg_ip_cores/bsg_dataflow/bsg_fifo_tracker.v",{})
  local bsg_parallel_in_serial_out = C.VerilogFile("modules/bsg_ip_cores/bsg_dataflow/bsg_parallel_in_serial_out.v",{})
  local bsg_serial_in_parallel_out = C.VerilogFile("modules/bsg_ip_cores/bsg_dataflow/bsg_serial_in_parallel_out.v",{})

  local bsg_thermometer_count = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_thermometer_count.v",{})
  local bsg_decode = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_decode.v",{bsg_defines})
  local bsg_decode_with_v = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_decode_with_v.v",{bsg_decode})
  local bsg_counter_clear_up = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_counter_clear_up.v",{bsg_defines})
  local bsg_round_robin_2_to_2 = C.VerilogFile("modules/bsg_ip_cores/bsg_dataflow/bsg_round_robin_2_to_2.v",{})

  local bsg_round_robin_arb = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_round_robin_arb.v",{bsg_defines})

  local bsg_mux_one_hot = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_mux_one_hot.v",{})
  local bsg_crossbar_o_by_i = C.VerilogFile("modules/bsg_ip_cores/bsg_misc/bsg_crossbar_o_by_i.v",{bsg_mux_one_hot})
  
  local bsg_round_robin_n_to_1 = C.VerilogFile("modules/bsg_ip_cores/bsg_dataflow/bsg_round_robin_n_to_1.v",{bsg_round_robin_arb,bsg_crossbar_o_by_i})
  local bsg_mem_1r1w_synth = C.VerilogFile("modules/bsg_ip_cores/bsg_mem/bsg_mem_1r1w_synth.v",{bsg_defines})
  local bsg_mem_1r1w = C.VerilogFile("modules/bsg_ip_cores/bsg_mem/bsg_mem_1r1w.v",{bsg_mem_1r1w_synth,bsg_defines })
  local bsg_two_fifo = C.VerilogFile("modules/bsg_ip_cores/bsg_dataflow/bsg_two_fifo.v",{bsg_mem_1r1w})

  local bsg_fifo_1r1w_small = C.VerilogFile("modules/bsg_ip_cores/bsg_dataflow/bsg_fifo_1r1w_small.v",{bsg_fifo_tracker})
  
  local bsg_fifo_1r1w_large = C.VerilogFile("modules/bsg_ip_cores/bsg_dataflow/bsg_fifo_1r1w_large.v",{bsg_fifo_1rw_large,bsg_serial_in_parallel_out,bsg_thermometer_count,bsg_round_robin_2_to_2,bsg_two_fifo,bsg_round_robin_n_to_1})
  local bsg_cache_dma = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache_dma.v",{bsg_cache_dma_pkt,bsg_fifo_1r1w_large})
  local bsg_cache_sbuf_queue = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache_sbuf_queue.v")
  local bsg_cache_sbuf = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache_sbuf.v",{bsg_cache_sbuf_queue})

  
  local bsg_cache_to_axi_rx = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache_to_axi_rx.v",{bsg_defines,bsg_fifo_1r1w_small,bsg_parallel_in_serial_out,bsg_decode_with_v,bsg_counter_clear_up})
  local bsg_cache_to_axi_tx = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache_to_axi_tx.v",{bsg_defines})

  local bsg_cache_to_axi = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache_to_axi.v",{bsg_cache_to_axi_rx,bsg_cache_to_axi_tx,bsg_cache_dma_pkt})

  local bsg_cache = C.VerilogFile("modules/bsg_ip_cores/bsg_cache/bsg_cache.v",{bsg_cache_pkt,bsg_cache_dma_pkt,bsg_mem_1rw_sync_mask_write_bit,bsg_mem_1rw_sync_mask_write_byte,bsg_cache_miss,bsg_cache_dma,bsg_cache_sbuf,bsg_mux_segmented,bsg_mux})


  local bsg_flow_convert = C.VerilogFile("modules/bsg_ip_cores/bsg_dataflow/bsg_flow_convert.v",{})
  
  res.instanceMap[bsg_cache:instantiate()] = 1
  res.instanceMap[bsg_cache_pkt:instantiate()] = 1
  res.instanceMap[bsg_flow_convert:instantiate()] = 1
  
  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)
    local vstr = {}
    print("RPATH",R.path)
    
    table.insert(vstr,CACHE)

    table.insert(vstr,res:vHeader())

    table.insert(vstr,readFnInst:toVerilog())

    table.insert(vstr,[[

  `declare_bsg_cache_pkt_s(32, ]]..ty:verilogBits()..[[);
  bsg_cache_pkt_s cache_pkt;

  assign cache_pkt.sigext = 1'b0; // sign extend accesses less than a full word?
  assign cache_pkt.opcode = 5'b00010; // load full word
  assign cache_pkt.addr = ]]..res:vInputData()..[[;

  wire [`bsg_cache_dma_pkt_width(32)-1:0] dma_pkt;
  wire dma_pkt_v;
  wire dma_pkt_yumi;

  //wire []]..(ty:verilogBits()-1)..[[:0] dma_data_i;
  //wire dma_data_v_i;
  //wire dma_data_ready_o;

  wire []]..(ty:verilogBits()-1)..[[:0] dma_data_o;
  wire dma_data_v_o;
  //wire dma_data_yumi_i;

  wire v_o;
  wire yumi_i;

  bsg_cache #(
    .addr_width_p(32),
    .data_width_p(]]..ty:verilogBits()..[[),
    .block_size_in_words_p(]]..itemsPerBlock..[[),
    .sets_p(]]..sets..[[))
  cache(
    .clk_i(CLK),
    .reset_i(reset),
    .cache_pkt_i(cache_pkt),
    .v_i(]]..res:vInputValid()..[[),
    .ready_o(]]..res:vInputReady()..[[),

    .data_o(]]..res:vOutputData()..[[),
    .v_o(v_o),
    .yumi_i(yumi_i),

    .dma_pkt_o(dma_pkt),
    .dma_pkt_v_o(dma_pkt_v),
    .dma_pkt_yumi_i(dma_pkt_yumi),
 
    .dma_data_i(]]..readFnInst:vOutputData()..[[),
    .dma_data_v_i(]]..readFnInst:vOutputValid()..[[),
    .dma_data_ready_o(]]..readFnInst:vOutputReady()..[[),

    .dma_data_o(dma_data_o),
    .dma_data_v_o(dma_data_v_o),
    .dma_data_yumi_i(1'b0),

    .v_we_o()
 );

  bsg_flow_convert #(.send_v_then_yumi_p(1),.recv_v_and_ready_p(1)) flow_convert2(
    .v_i(v_o),.fc_o(yumi_i),.v_o(]]..res:vOutputValid()..[[),.fc_i(]]..res:vOutputReady()..[[));

  bsg_flow_convert #(.send_v_then_yumi_p(1),.recv_v_and_ready_p(1)) flow_convert(
    .v_i(dma_pkt_v),.fc_o(dma_pkt_yumi),.v_o(]]..readFnInst:vInputValid()..[[),.fc_i(]]..readFnInst:vInputReady()..[[));

always @(posedge CLK) begin
//  $display("data v %d yumi %d ready_downstream %d",v_o,yumi_i,]]..res:vOutputReady()..[[);

//  $display("cache addr %d v_i %d ready %d",cache_pkt.addr,]]..res:vInputValid()..[[,]]..res:vInputReady()..[[);
//   $display("dma addr %d dmapkt %x dma_pkt_v %d dma_pkt_yumi %d dmavalid %d ready %d",]]..readFnInst:vInputData()..[[,dma_pkt,dma_pkt_v,dma_pkt_yumi,]]..readFnInst:vInputValid()..[[,]]..readFnInst:vInputReady()..[[);
//  $display("dmaresp data %x valid %d ready %d",]]..readFnInst:vOutputData()..[[,]]..readFnInst:vOutputValid()..[[,]]..readFnInst:vOutputReady()..[[);
//  $display("dma_data_v_o %d",dma_data_v_o);
end

  assign ]]..readFnInst:vInputData()..[[ = dma_pkt[31:0];
endmodule

]])


    --[=[   bsg_cache_to_axi #(
    .addr_width_p(32),
    .data_width_p(]]..ty:verilogBits()..[[),
    .block_size_in_words_p(]]..itemsPerBlock..[[),
    .num_cache_p(1),
    .axi_id_width_p(12),
    .axi_addr_width_p(32),
    .axi_data_width_p(64),
    .axi_burst_len_p(8))
  cache_to_axi(
    .clk_i(CLK),
    .reset_i(reset),

    .dma_pkt_i(dma_pkt),
    .dma_pkt_v_i(dma_pkt_v),
    .dma_pkt_yumi_o(dma_pkt_yumi),

    .dma_data_o(dma_data_i),
    .dma_data_v_o(dma_data_v_i),
    .dma_data_ready_i(dma_data_ready_o),
   
    .dma_data_i(dma_data_o),
    .dma_data_v_i(dma_data_v_o),
    .dma_data_yumi_o(dma_data_yumi_i),

    .axi_awid_o(),
    .axi_awaddr_o(),
    .axi_awlen_o(),
    .axi_awsize_o(),
.axi_awburst_o(),
.axi_awcache_o(),
.axi_awprot_o(),
.axi_awlock_o(),
.axi_awvalid_o(),
.axi_awready_i(1'b0),

.axi_wdata_o(),
.axi_wstrb_o(),
.axi_wlast_o(),
.axi_wvalid_o(),
.axi_wready_i(1'b0),

.axi_bid_i(),
.axi_bresp_i(2'b0),
.axi_bvalid_i(1'b0),
.axi_bready_o(),

.axi_arid_o(]]..readFnInst:vInput()..AXI.ReadAddressVSelect.arid..[[),
.axi_araddr_o(]]..readFnInst:vInput()..AXI.ReadAddressVSelect.araddr..[[),
.axi_arlen_o(]]..readFnInst:vInput()..AXI.ReadAddressVSelect.arlen..[[),
.axi_arsize_o(]]..readFnInst:vInput()..AXI.ReadAddressVSelect.arsize..[[),
.axi_arburst_o(]]..readFnInst:vInput()..AXI.ReadAddressVSelect.arburst..[[),
.axi_arcache_o(]]..readFnInst:vInput()..AXI.ReadAddressVSelect.arcache..[[),
.axi_arprot_o(]]..readFnInst:vInput()..AXI.ReadAddressVSelect.arprot..[[),
.axi_arlock_o(]]..readFnInst:vInput()..AXI.ReadAddressVSelect.arlock..[[),
.axi_arvalid_o(]]..readFnInst:vInput()..AXI.ReadAddressVSelect.arvalid..[[),
.axi_arready_i(]]..readFnInst:vInputReady()..[[),

.axi_rid_i(]]..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rid..[[),
.axi_rdata_i(]]..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rdata..[[),
.axi_rresp_i(]]..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rresp..[[),
.axi_rlast_i(]]..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rlast..[[),
.axi_rvalid_i(]]..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rvalid..[[),
.axi_rready_o(]]..readFnInst:vOutputReady()..[[)
 );
    ]=]
    
    s:verilog(table.concat(vstr,"\n"))
    return s
  end

  return res
end

return Bjump
