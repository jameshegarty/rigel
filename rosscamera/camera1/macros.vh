`ifndef MACROS_VH
`define MACROS_VH

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
