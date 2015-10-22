module StreamBuffer(
    input rst_n,
    input pclk,
    input fclk,

    input start,

    input           din_valid,
    output          din_ready,
    input [7:0]    din,

    output [63:0]   dout,
    output          dout_valid,
    input           dout_ready,
    output          burst_valid,

    output [10:0]   fifo_cnt
);

    reg data_packed_ready;
    wire [10:0] vfifo_count;
    // Logic to convert 16 bit input to 64 bit input
    reg [2:0] cnt;
    reg din_valid_p;
    reg [7:0] data_packed[7:0];

    reg running;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) running <= 1'b0;
        else running <= start ? 1'b1 : running;
    end


    always @(posedge pclk) begin
        din_valid_p <= (din_valid && running);
    end

    always @(posedge pclk or negedge rst_n) begin
        if (rst_n==0) begin
            cnt <= 3'h0;
            data_packed_ready <= 1'b0;
        end
        else begin
            data_packed_ready <= 1'b0;
            if (din_valid && running) begin
                data_packed[cnt] <= din[7:0];
                cnt <= cnt + 1'b1; // Should wrap
                data_packed_ready <= (cnt==3'd7) ? 1'b1 : 1'b0;
            end
        end
    end
    
    wire [63:0] data64;
    assign data64[63:0] = {data_packed[7],data_packed[6],data_packed[5],data_packed[4],data_packed[3],data_packed[2],data_packed[1],data_packed[0]};

    vfifo64x1024 your_instance_name (
        .rst(!rst_n), // input rst
        .wr_clk(pclk), // input wr_clk
        .rd_clk(fclk), // input rd_clk
        .din(data64[63:0]), // input [63 : 0] din
        .wr_en(data_packed_ready), // input wr_en
        .rd_en(dout_ready), // input rd_en
        .dout(dout), // output [63 : 0] dout
        .full(vfifo_full), // output full
        .empty(vfifo_empty), // output empty
        .rd_data_count(vfifo_count) // output [10 : 0] rd_data_count
    );
    assign din_ready = !vfifo_full;
    // I need to guarentee that 16 data entries are read out always
    assign burst_valid = (vfifo_count > 11'd25);
    assign dout_valid = !vfifo_empty;
    assign fifo_cnt = vfifo_count;

endmodule // Conf
