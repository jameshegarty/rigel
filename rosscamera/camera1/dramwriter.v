module DRAMWriter(
    //AXI port
    input ACLK,
    input rst_n,
    output reg [31:0] M_AXI_AWADDR,
    input M_AXI_AWREADY,
    output M_AXI_AWVALID,
    
    output [63:0] M_AXI_WDATA,
    output [7:0] M_AXI_WSTRB,
    input M_AXI_WREADY,
    output M_AXI_WVALID,
    output M_AXI_WLAST,
    
    input [1:0] M_AXI_BRESP,
    input M_AXI_BVALID,
    output M_AXI_BREADY,
    
    output [3:0] M_AXI_AWLEN,
    output [1:0] M_AXI_AWSIZE,
    output [1:0] M_AXI_AWBURST,
    
    //Control config
    input start,
    input stop,
    input burst_valid,
    input [31:0] STREAMBUF_NBYTES,
    input [31:0] STREAMBUF_ADDR,
    output [31:0] STREAMBUF_CURADDR,
    
    //RAM port
    input [63:0] din,
    output din_ready,
    input din_valid
    
);

assign M_AXI_AWLEN = 4'b1111; // 16 transfers??
assign M_AXI_AWSIZE = 2'b11; // Represents 8 Bytes per "Transfer" (64 bit wide data bus)
assign M_AXI_AWBURST = 2'b01; // Represents Type "Incr"
assign M_AXI_WSTRB = 8'b11111111;

parameter IDLE = 0, RWAIT = 1;

reg stopping;
`REG(ACLK, stopping, 0, stop ? 1'b1 : stopping)

// TODO shut down nicely?
//ADDR logic
reg a_state;  
assign M_AXI_AWVALID = (a_state == RWAIT);
wire wrap = M_AXI_AWREADY && ((M_AXI_AWADDR + 128)==(STREAMBUF_ADDR+STREAMBUF_NBYTES));
// Create stall logic 
always @(posedge ACLK or negedge rst_n) begin
    if (rst_n == 0) begin
        a_state <= IDLE;
        M_AXI_AWADDR <= 0;
    end else case(a_state)
        IDLE: begin
            if (start) begin
                M_AXI_AWADDR <= STREAMBUF_ADDR;
                a_state <= RWAIT;
            end
        end
        RWAIT: begin
            if (stopping && wrap) begin
                a_state <= IDLE;
            end
            else if (M_AXI_AWREADY == 1) begin
                M_AXI_AWADDR <= wrap ? STREAMBUF_ADDR : (M_AXI_AWADDR+128);
            end
        end
    endcase
end
assign STREAMBUF_CURADDR = M_AXI_AWADDR;

//WRITE logic
reg [5:0] b_count;
reg w_state;
always @(posedge ACLK or negedge rst_n) begin
    if (rst_n == 0) begin
        w_state <= IDLE;
        b_count <= 0;
    end else case(w_state)
        IDLE: begin
            if(burst_valid) begin
                b_count <= 16;
                w_state <= RWAIT;
            end
        end
        RWAIT: begin
            if (M_AXI_WREADY && M_AXI_WVALID) begin
                //use M_AXI_WDATA
                if(b_count == 5'h1) begin
                    w_state <= IDLE;
                end
                b_count <= b_count - 1'b1;
            end
        end
    endcase
end

assign M_AXI_WLAST = (b_count == 5'h1);

assign M_AXI_WVALID = (w_state == RWAIT) && din_valid;

assign din_ready = (w_state == RWAIT) && M_AXI_WREADY;
   

assign M_AXI_BREADY = 1;

assign M_AXI_WDATA = din;

endmodule // DRAMWriter

