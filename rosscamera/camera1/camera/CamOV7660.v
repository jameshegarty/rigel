`include "../macros.vh"

module CamOV7660 (
    
    //general
    input fclk,
    input rst_n,
    
    // Camera IO
    input [9:2] CAM_DIN,
    input CAM_VSYNC,
    input CAM_HREF,
    output CAM_PWDN,
    input CAM_PCLK,
    output CAM_XCLK,
    output CAM_SIO_C,
    inout CAM_SIO_D,
    

    //Camera register setup
    input [16:0] rw_cmd,
    input rw_cmd_valid,
    output [17:0] rw_resp,// {err,rw,addr,data}
    output rw_resp_valid,

    //pclk
    input [31:0] cam_cmd,
    input cam_cmd_valid,
    output cam_cmd_ready,

    //camera output
    output [63:0] sdata,
    output sdata_valid,
    output sdata_burst_valid, // Only valid if the next N (16) are valid
    input sdata_ready,

    // debug signals
    output [31:0] debug0,
    output [31:0] debug1,
    output [31:0] debug2
);

    wire pclk;
  

    reg CAM_VSYNC_D;
    reg CAM_HREF_D;
    reg [7:0] CAM_DIN_D;

    IBUFG pclk_buffer( .I(CAM_PCLK), .O(pclk));
    //assign pclk = CAM_PCLK;
    always @(posedge pclk) begin
        CAM_VSYNC_D <= CAM_VSYNC;
        CAM_HREF_D <= CAM_HREF;
        CAM_DIN_D <= CAM_DIN;
    end
  
    assign CAM_PWDN = 1'b0; // 0: Normal mode

    wire XCLK_DIV;

    // TODO might need to change the frequency for XCLK
    assign XCLK_DIV = fclk;
    OBUF xclk_buffer(.I(XCLK_DIV), .O(CAM_XCLK));

    wire cfifo_full;
    wire cfifo_empty;
    
    wire [31:0] pcam_cmd;
    wire pcam_cmd_valid;
    wire pcam_cmd_ready;

    cfifo32x16 cfifo (
        .rst(!rst_n), // input rst
        .wr_clk(fclk), // input wr_clk
        .rd_clk(pclk), // input rd_clk
        .din(cam_cmd), // input [31 : 0] din
        .wr_en(cam_cmd_valid), // input wr_en
        .rd_en(pcam_cmd_ready), // input rd_en
        .dout(pcam_cmd), // output [31 : 0] dout
        .full(cfifo_full), // output full
        .empty(cfifo_empty) // output empty
    );

    assign cam_cmd_ready = !cfifo_full;
    
    assign pcam_cmd_valid = !cfifo_empty;
    assign pcam_cmd_ready = pcam_cmd_valid;



    // debug counters
    reg [31:0] debug_cnt[2:0];

    reg camsetup_err;
    `REG_ERR(fclk, camsetup_err, rw_cmd_valid && !rw_cmd_ready)
    assign rw_resp[17] = camsetup_err;
    // Camera set up
    CamSetup camsetup(
        .clk(fclk),
        .rst_n(rst_n),
        .rw_cmd(rw_cmd[16:0]),
        .rw_cmd_valid(rw_cmd_valid),
        .rw_cmd_ready(rw_cmd_ready),
        .rw_resp(rw_resp[16:0]),
        .rw_resp_valid(rw_resp_valid),
        .sioc_o(CAM_SIO_C),
        .siod_io(CAM_SIO_D)
    );

    wire [15:0] cr_pixel;
    wire vstart;
    wire hstart;

    wire start_stream;

    // TODO make module for this if I want it more commands
    assign start_stream = pcam_cmd_valid && (pcam_cmd == 5);

    CamReader camreader(
        .din(CAM_DIN_D),        // D0 - D7
        .vsync(CAM_VSYNC_D),          // VSYNC
        .href(CAM_HREF_D),           // HREF
        .pclk(pclk),           // PCLK 
        .rst_n(rst_n),            // 0 - Reset.
        .pixel_valid(cr_pixel_valid),     // Indicates that a pixel has been received.
        .pixel(cr_pixel),   // RGB565 pixel.
        .vstart(vstart),           // first pixel of frame
        .hstart(hstart),    // first pixel of line
        .raw(1'b1),     // TODO control this?
        .start(start_stream), 
        .stop(1'b0)    // TODO
    );
    
    // check if vstart and hstart are on valid pixels
    reg camreader_err;
    `REG_ERR(pclk, camreader_err, 
        running && (vstart || hstart) && !cr_pixel_valid 
    );

    wire [10:0] fifo_cnt;
    wire cr_pixel_ready;
    // Guarentees that once data is accepted it will stay valid for at least 16 
    StreamBuffer stream_buffer(
        .pclk(pclk),
        .fclk(fclk),
        .rst_n(rst_n),
        
        .start(start_stream),

        .din(cr_pixel),
        .din_valid(cr_pixel_valid),
        .din_ready(cr_pixel_ready), //this should never be not ready

        .dout(sdata),
        .dout_valid(sdata_valid),
        .dout_ready(sdata_ready),
        .burst_valid(sdata_burst_valid),
        .fifo_cnt(fifo_cnt)
    );
    reg running;
    `REG(pclk, running, 0, start_stream ? 1'b1 : running);
    always @(posedge pclk or negedge rst_n) begin
        if (rst_n==0) begin
            debug_cnt[0] <= 32'h0;
            debug_cnt[1] <= 32'h0;
            debug_cnt[2] <= 32'h0;
        end
        else begin
            debug_cnt[0] <= (running & vstart) ? (debug_cnt[0]+1'b1) : debug_cnt[0] ;
            debug_cnt[1] <= (running & hstart) ? (debug_cnt[1]+1'b1) : debug_cnt[1] ;
            debug_cnt[2] <= {camreader_err,20'h0,fifo_cnt};
        end
    end

    assign debug0 = debug_cnt[0];
    assign debug1 = debug_cnt[1];
    assign debug2 = debug_cnt[2];

endmodule
