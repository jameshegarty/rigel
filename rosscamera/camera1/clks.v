module ClkCtrl(
    input CLKIN_100700kHz,
    output CLK_25175kHz,
    output CLK_50MHz,
    input rst_n,
    output clks_valid
);

/*
    cameraClkGen clkgen(
        .CLKIN_100MHz(CLKIN_100MHz),      // IN
        .CLK_25174kHz(CLK_25174kHz),     // OUT
        .CLK_80MHz(CLK_80MHz),     // OUT
        .RESET(!rst_n),// IN
        .LOCKED(clks_valid)
    );      // OUT
*/
    
    reg [1:0] cnt;
    always @(posedge CLKIN_100700kHz or negedge rst_n) begin
        if (!rst_n) cnt[1:0] <= 2'h0;
        else cnt[1:0] <= cnt[1:0] + 1'b1;
    end

    assign CLK_25175kHz = cnt[1];
    assign CLK_50MHz = cnt[0];
    assign clks_valid = 1'b1;

endmodule : ClkCtrl
