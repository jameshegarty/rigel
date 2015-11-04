
module pipeWrap(
    input clk,
    input rst_n,

    input start,

    input in_valid,
    output in_ready,
    input [63:0] in_data,

    output reg out_valid,
    input out_ready,
    output [63:0] out_data,

    output [31:0] debug_cnt_in,
    output [31:0] debug_cnt_out,
    
    output reg [31:0] debug_tot_in,
    output reg [31:0] debug_tot_out,
    
    output reg [3:0] num_frames
);

// 8 pixles -> 2 pixels

localparam IN_PIXELS_MAX = (640*480/8) - 1;
localparam OUT_PIXELS_MAX = (640*480/2) - 1;
localparam PIPE_CLEAR_TIME = 150;


    localparam INIT=2'h0, WAIT=2'h1, VALID=2'h2, CLEAR=2'h3;
    reg [1:0] CS_in, NS_in;
    reg [31:0] cnt_in;
    reg [31:0] cnt_in_next;
    
    wire pipe_in_valid;
    wire pipe_in_ready;
    wire [63:0] pipe_in_data;

    reg out_done;

    always @(*) begin
        case(CS_in)
            INIT : begin
                NS_in = start ? VALID : INIT;
                cnt_in_next = 0;
            end
            VALID : begin
                NS_in = (in_valid && pipe_in_ready && cnt_in==IN_PIXELS_MAX) ? WAIT : VALID ;
                cnt_in_next = (in_valid && pipe_in_ready) ? ((cnt_in==IN_PIXELS_MAX) ? 0 : cnt_in + 1'b1) : cnt_in;
            end
            WAIT : begin
                NS_in = out_done ? VALID : WAIT ;
                cnt_in_next = 0;
            end
            default : begin
                NS_in = INIT;
                cnt_in_next = 0;
            end
        endcase
    end
    `REG(clk, CS_in, INIT, NS_in)
    `REG(clk, cnt_in, 0, cnt_in_next)
    
    assign pipe_in_data = in_data;
    assign pipe_in_valid = (CS_in==VALID) && in_valid ;
    assign in_ready = (CS_in==VALID) && pipe_in_ready ;

    wire sync_reset;
    wire pipe_out_valid;
    reg pipe_out_ready;
    wire [63:0] pipe_out_data;
    wire [64:0] pipe_out;

    hsfnfin #(.INSTANCE_NAME("demosaic")) hsfna(.CLK(clk), .ready_downstream(pipe_out_ready), .ready(pipe_in_ready), .reset(sync_reset), .process_input({pipe_in_valid,pipe_in_data}), .process_output(pipe_out));

    //MakeHandshake_pointwise_wide #(.INSTANCE_NAME("hsfna")) hsfna(.CLK(clk), .ready_downstream(pipe_out_ready), .ready(pipe_in_ready), .reset(sync_reset), .process_input({pipe_in_valid,pipe_in_data}), .process_output(pipe_out));

    assign pipe_out_valid = pipe_out[64];
    assign pipe_out_data = pipe_out[63:0];
 
    reg [1:0] CS_out, NS_out;
    reg [31:0] cnt_out;
    reg [31:0] cnt_out_next;

    always @(*) begin
        case(CS_out)
            INIT : begin
                NS_out = start ? VALID : INIT;
                cnt_out_next = 0;
                out_done = 0;
                out_valid = 0;
                pipe_out_ready = 0;
            end
            VALID : begin
                NS_out = (pipe_out_valid && out_ready && cnt_out==OUT_PIXELS_MAX) ? CLEAR : VALID ;
                cnt_out_next = (pipe_out_valid && out_ready) ? ((cnt_out==OUT_PIXELS_MAX) ? 0 : cnt_out + 1'b1) : cnt_out;
                out_done = 0;
                out_valid = pipe_out_valid ;
                pipe_out_ready = out_ready;
            end
            CLEAR : begin
                NS_out = (cnt_out==PIPE_CLEAR_TIME) ? VALID : CLEAR ;
                cnt_out_next = (cnt_out==PIPE_CLEAR_TIME) ? 0 : cnt_out+1'b1 ;
                out_done = (cnt_out==PIPE_CLEAR_TIME) ? 1 : 0 ;
                out_valid = 0;
                pipe_out_ready = 1;
            end
            default : begin
                NS_out = INIT;
                cnt_out_next = 0;
                out_done = 0;
                out_valid = 0;
                pipe_out_ready = 0;
            end
        endcase
    end
    `REG(clk, CS_out, INIT, NS_out)
    `REG(clk, cnt_out, 0, cnt_out_next)

    assign sync_reset = (CS_out==CLEAR) || (CS_out==INIT) ;
    assign out_data = pipe_out_data;
   
    assign debug_cnt_out = cnt_out;
    assign debug_cnt_in = cnt_in;

    `REG(clk, debug_tot_in, 0, debug_tot_in + (pipe_in_valid && pipe_in_ready))
    `REG(clk, debug_tot_out, 0, debug_tot_out + (pipe_out_valid && pipe_out_ready))
    
    `REG(clk, num_frames, 0, num_frames + out_valid)

endmodule : pipeWrap

/*
 frameControl frameControl_inst(
    .clk(XXX_clk),
    .rst_n(XXX_rst_n),

    .start(XXX_start),

    .in_valid(XXX_in_valid),
    .in_ready(XXX_in_ready),
    .in_data(XXX_in_data[63:0]),

    .out_valid(XXX_out_valid),
    .out_ready(XXX_out_ready),
    .out_data(XXX_out_data[63:0]),
);
*/
