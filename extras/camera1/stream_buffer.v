module StreamBuffer(
    input clk,
    input rst_n,

    input start,

    input [15:0]    din,
    input           din_valid,
    output          din_ready,

    output [63:0]   dout,
    output          dout_valid,
    input           dout_ready
);

    wire data_packed_ready;
    // Logic to convert 16 bit input to 64 bit input
    reg [1:0] cnt;
    reg din_valid_p;
    reg [15:0] data_packed[4]

    reg running;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) running <= 1'b0;
        else running <= start ? 1'b1 : running;
    end

    always @(posedge clk or negedge rst_n) begin
        if (rst_n==0) din_valid_p <= (din_valid && running);
    end

    always @(posedge clk or negedge rst_n) begin
        if (rst_n==0) begin
            cnt <= 0;
        end
        else if (din_valid && running) begin
            data_packed[cnt] <= din;
            cnt <= cnt + 1'b1; // Should wrap
        end
    end
    
    assign data_packed_ready = din_valid_p && (cnt==2'h3);

    parameter FIFO_DEPTH=1024;
    //      bitwidth x depth
    vfifo64x1024 fifo64(
        .clk(clk),
        .rst(rst_n),
        .din({data_packed[3],data_packed[2],data_packed[1],data_packed[0]}),
        .wr_en(data_packed_ready),
        .rd_en(dout_ready), // TODO make sure the timing of this is fine
        .dout(dout),
        .full(vfifo_full),
        .empty(vfifo_empty)
    );

    assign dout_valid = !vfifo_empty;

endmodule // Conf
