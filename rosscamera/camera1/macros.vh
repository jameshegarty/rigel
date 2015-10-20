`ifndef MACROS_VH
`define MACROS_VH


`define CMD_START 32'h5
`define CMD_STOP 32'h9

`define REG(clk, r, init, in) \
    always @(posedge clk or negedge rst_n) begin \
        if (!rst_n) r <= (init); \
        else r <= (in); \
    end

`define REG_ERR(clk, r, cond) \
    always @(posedge clk or negedge rst_n) begin \
        if (!rst_n) r <= 1'b0; \
        else r <= (cond) ? 1'b1 : r; \
    end



`endif
