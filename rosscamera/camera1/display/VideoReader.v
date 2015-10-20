module VideoReader(
    //AXI port
    input ACLK,
    input rst_n,
    output reg [31:0] M_AXI_ARADDR,
    input M_AXI_ARREADY,
    output  M_AXI_ARVALID,
    input [63:0] M_AXI_RDATA,
    output M_AXI_RREADY,
    input [1:0] M_AXI_RRESP,
    input M_AXI_RVALID,
    input M_AXI_RLAST,
    output [3:0] M_AXI_ARLEN,
    output [1:0] M_AXI_ARSIZE,
    output [1:0] M_AXI_ARBURST,
    
    //Control config
    input start,
    input stop,
    input burst_ready,
    input [31:0] VGABUF_NBYTES,
    input [31:0] VGABUF_ADDR,
    output [31:0] VGABUF_CURADDR,
    
    //RAM port
    input dout_ready,
    output dout_valid,
    output [63:0] dout
);

    assign M_AXI_ARLEN = 4'b1111;
    assign M_AXI_ARSIZE = 2'b11;
    assign M_AXI_ARBURST = 2'b01;
    parameter IDLE = 0, RWAIT = 1, INIT=2;
        

    wire wrap;
    assign wrap = (M_AXI_ARADDR + 128)==(VGABUF_ADDR+VGABUF_NBYTES);
    assign VGABUF_CURADDR = M_AXI_ARADDR;
    reg stopping;
    `REG(ACLK, stopping, 0, stop ? 1'b1 : (a_state==INIT) ? 1'b0 : stopping)


    //ADDR logic
    reg [1:0] a_state;  
    assign M_AXI_ARVALID = (a_state == IDLE && burst_ready && M_AXI_ARREADY);
    always @(posedge ACLK or negedge rst_n) begin
        if (rst_n == 0) begin
            a_state <= INIT;
            M_AXI_ARADDR <= 0;
        end else case(a_state)
            INIT: begin
                 if(start) begin
                    M_AXI_ARADDR <= VGABUF_ADDR;
                    a_state <= IDLE;
                end
            end
            IDLE: begin
                if (burst_ready && M_AXI_ARREADY) begin
                    a_state <= RWAIT;
                end
            end
            RWAIT: begin
                if (r_state == IDLE) begin
                    M_AXI_ARADDR <= wrap ? VGABUF_ADDR : M_AXI_ARADDR + 128; // Bursts are 128 bytes long
                    a_state <= (stopping && wrap) ? INIT : IDLE ;
                end
            end
        endcase
    end
    // TODO changed the bcount
    //READ logic
    reg [3:0] b_count;
    reg r_state;
    assign M_AXI_RREADY = (r_state == RWAIT) && dout_ready;
    always @(posedge ACLK or negedge rst_n) begin
        if (rst_n == 0) begin
            r_state <= IDLE;
            b_count <= 0;
        end else case(r_state)
            IDLE: begin
                if (a_state==IDLE && burst_ready && M_AXI_ARREADY) begin
                    b_count <= 4'd15;
                    r_state <= RWAIT;
                end
            end
            RWAIT: begin
                if (M_AXI_RVALID && dout_ready) begin
                    if(b_count == 4'h0) begin
                        r_state <= IDLE;
                    end
                    b_count <= b_count - 1'b1; // each valid cycle the bus provides 8 bytes
                end
            end
        endcase
    end

    assign dout = M_AXI_RDATA;
    assign dout_valid = M_AXI_RVALID && (r_state == RWAIT);

endmodule // DRAMReader

