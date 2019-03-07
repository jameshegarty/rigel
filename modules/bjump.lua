local R = require "rigel"
local types = require "types"
local J = require "common"
local C = require "examplescommon"
local Bjump = {}

-- a direct mapped cache, with 'sets' number of blocks, each block of size ty:verilogBytes()*itemsPerBlock bytes
function Bjump.AXICachedRead( ty, itemsPerBlock, sets, readFn )
  J.err( types.isBasic(ty)," AXICachedRead: ty should be basic")
  J.err( type(itemsPerBlock)=="number", "itemsPerBlock should be number")
  J.err( type(sets)=="number", "sets should be number")
  local res = {inputType=types.Handshake(types.uint(32))}
  res.outputType = types.Handshake(ty)
  res.stateful = true
  res.sdfInput = SDF{1,1}
  res.sdfOutput = SDF{1,1}
  res.name = "Bjump_AXICachedRead"

  res = R.newFunction(res)

  function res.makeSystolic()
    local s = C.automaticSystolicStub(res)
    local vstr = {}
    table.insert(vstr,J.fileToString(R.path.."modules/bsg_ip_cores/bsg_cache/bsg_cache.v"))
    table.insert(vstr,J.fileToString(R.path.."modules/bsg_ip_cores/bsg_cache/bsg_cache_to_axi.v"))
    table.insert(vstr,res:vHeader()..[[

  `declare_bsg_cache_pkt_s(32, ]]..ty:verilogBits()..[[);
  bsg_cache_pkt_s cache_pkt;

  assign cache_pkt.sigext = 1'b0; // sign extend accesses less than a full word?
  assign cache_pkt.opcode = 5'b00010; // load full word
  assign cache_pkt.addr = ]]..res:vInputData()..[[;

  bsg_cache #(
    .addr_width_p(32),
    .data_width_p(]]..ty:verilogBits()..[[)),
    .block_size_in_words_p(]]..itemsPerBlock..[[),
    .sets_p(]]..sets..[[))
  cache(
    .clk_i(CLK),
    .reset_i(RST),
    .cache_pkt_i(cache_pkt),
    .v_i(]]..res:vInputValid()..[[),
    .ready_o]]..res:vInputReady()..[[),
 );

endmodule]])
    
    s.verilog = table.concat(vstr,"\n")
    return s
  end

  return res
end

return Bjump
