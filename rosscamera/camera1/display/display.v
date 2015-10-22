module display(
  
    input fclk,
    input rst_n,
    input vgaclk,

    input [31:0] vga_cmd,
    input vga_cmd_valid,
    output vga_cmd_ready,

    output reg VGA_VS_n,
    output reg VGA_HS_n,
    output reg [7:0] VGA_red,
    output reg [7:0] VGA_green,
    output reg [7:0] VGA_blue,

    output [7:0] debug,

    output sdata_burst_ready,
    input sdata_valid,
    output sdata_ready,
    input [63:0] sdata


);
    
    assign sdata_ready = 1'b1;
    
    wire fifo_read_en;
    wire [7:0] fifo_dout;
    wire fifo_full;
    wire fifo_empty;
    
    // Magic number 850 is just a number less than 1024-128
    // This is required so that there is enough room in the fifo for the axi burst
    wire [12:0] fifo_rd_data_count;
    wire [9:0] fifo_wr_data_count;
    assign sdata_burst_ready = (fifo_wr_data_count[9:0] < (10'd850));
    
    
    reg fifo_full_err;
    `REG_ERR(fclk, fifo_full_err, fifo_full)
    
    wire [63:0] fifo_data_swapped;
    assign fifo_data_swapped = {
        sdata[7:0],sdata[15:8],sdata[23:16],sdata[31:24],
        sdata[39:32],sdata[47:40],sdata[55:48],sdata[63:56]
    };

    vgafifo_64w_8r_1024d vgafifo (
          .rst(!rst_n), // input rst
          .wr_clk(fclk), // input wr_clk
          .rd_clk(vgaclk), // input rd_clk
          .din(fifo_data_swapped[63:0]), // input [63 : 0] din
          .wr_en(sdata_valid), // input wr_en
          .rd_en(fifo_read_en), // input rd_en
          .dout(fifo_dout), // output [7 : 0] dout
          .full(fifo_full), // output full
          .empty(fifo_empty), // output empty
          .rd_data_count(fifo_rd_data_count[12:0]), // output [12 : 0] rd_data_count
          .wr_data_count(fifo_wr_data_count[9:0]) // output [9 : 0] wr_data_count
    );
    

    wire [31:0] vga_cmd_out;
    wire vga_cmd_empty;
    wire vga_cmd_fifo;
    assign vga_cmd_ready = !vga_cmd_full;
    
    cfifo32x16 cfifo (
        .rst(!rst_n), // input rst
        .wr_clk(fclk), // input wr_clk
        .rd_clk(vgaclk), // input rd_clk
        .din(vga_cmd), // input [31 : 0] din
        .wr_en(vga_cmd_valid), // input wr_en
        .rd_en(!vga_cmd_empty), // input rd_en
        .dout(vga_cmd_out), // output [31 : 0] dout
        .full(vga_cmd_full), // output full
        .empty(vga_cmd_empty) // output empty
    );
    
    //in vgaclk domain
    wire vga_start;
    wire vga_stop;
    assign vga_start = !vga_cmd_empty && (vga_cmd_out == `CMD_START); //pulse    
    assign vga_stop = !vga_cmd_empty && (vga_cmd_out == `CMD_STOP); //pulse    
    
    reg saw_vga_start;
    `REG(vgaclk, saw_vga_start, 1'b0, vga_start ? 1'b1 : vga_running ? 1'b0 : saw_vga_start)
    reg vga_stopping;
    `REG(vgaclk, vga_stopping, 1'b0, vga_stop ? 1'b1 : vga_stopping)

    wire [9:0] vga_row;
    wire [9:0] vga_col;
    wire vga_pixel_valid;
    wire vstart;
    wire hstart;
    assign vstart = vga_pixel_valid && (vga_row == 10'h0);
    assign hstart = vga_pixel_valid && (vga_col == 10'h0);
    
    reg vga_running;
    wire vga_running_nxt;
    assign vga_running_nxt = ((fifo_rd_data_count[12:0] > 13'd1024) && saw_vga_start && vstart && hstart) ? 1'b1 : vga_running;
    `REG(vgaclk, vga_running, 1'b0, vga_running_nxt)

    assign debug[7:0] = {4'b0,fifo_read_en, saw_vga_start, vga_running, vga_stopping};

    wire HS_n;
    wire VS_n;
    wire [7:0] VGA_red_nxt;
    wire [7:0] VGA_green_nxt;
    wire [7:0] VGA_blue_nxt;
    
    VGATiming vga_timing(
        .clk_25M(vgaclk),
        .rst_n(rst_n),
        .HS_n(HS_n),
        .VS_n(VS_n),
        .pixel_valid(vga_pixel_valid),
        .vga_row(vga_row),
        .vga_col(vga_col)
    );

    //flop all the vga signals
    `REG(vgaclk, VGA_VS_n, 1'b0, VS_n)
    `REG(vgaclk, VGA_HS_n, 1'b0, HS_n)
    `REG(vgaclk, VGA_red[7:0], 8'hFF, VGA_red_nxt[7:0])
    `REG(vgaclk, VGA_green[7:0], 8'hFF, VGA_green_nxt[7:0])
    `REG(vgaclk, VGA_blue[7:0], 8'hFF, VGA_blue_nxt[7:0])
    
    wire [7:0] pattern_red;
    wire [7:0] pattern_green;
    wire [7:0] pattern_blue;

    // Need to read a cycle early in order to flop the data
    assign fifo_read_en = !vga_stopping && vga_running_nxt && vga_pixel_valid;
    assign VGA_red_nxt = fifo_read_en ? fifo_dout[7:0] : pattern_red[7:0];
    assign VGA_green_nxt = fifo_read_en ? fifo_dout[7:0] : pattern_green[7:0];
    assign VGA_blue_nxt = fifo_read_en ? fifo_dout[7:0] : pattern_blue[7:0];

    assign pattern_red = (vga_col <=210) ? 8'hFF : 8'h0;
    assign pattern_green = ((vga_col >210) && (vga_col <= 420)) ? 8'hFF : 8'h0;
    assign pattern_blue = (vga_col >420) ? 8'hFF : 8'h0;


endmodule : display
