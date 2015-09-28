////////////////////////////////////////////////////////////////////////////////////////////////////
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
// 02111-1307, USA.
//
// ©2013 - Roman Ovseitsev <romovs@gmail.com>
////////////////////////////////////////////////////////////////////////////////////////////////////

//##################################################################################################
//
// OmniVision Camera setup module. Configured to initialize OV7670 model.
//
// Initializes camera module using register set defined in OV7670Init and once done raises 
// done_o signal.
//
// Other camera models require modification of register set and timing parameters.
// After a hardware reset delay for 1ms prior to raising rst_i.
// External pull-up register (4.7k should be enough) is required on SIOD line. FPGA`s internal 
// pull-ups may not be sufficient.
//
//##################################################################################################

`timescale 1ns / 1ps

module CamSetup (clk_i, rst_i, start_i, done_o, sioc_o, siod_io);

    `include "Math.v" 

    parameter   IN_FREQ = 24_000_000;   // clk_i frequency in Hz.
    parameter   CAM_ID = 8'h42;         // OV7670 ID. Bit 0 is Don't Care since we specify r/w op in register lookup table.
    
    input       clk_i;                  // Main clock.
    input       rst_i;                  // 0 - reset.
    input       start_i;
    output reg  done_o;                   // 0 - setup in progress. 1 - setup has completed.
    output      sioc_o;                 // Camera's SIOC.
    inout       siod_io;                // Camera's SIOD. Should have a pullup resistor.
 
 
    localparam  SCCB_FREQ = 100_000;    // SCCB frequency in Hz.
    localparam  T_SREG = 300;           // Register setup time in ms. 300ms for OV7670.
 
    localparam  integer SREG_CYCLES = (IN_FREQ/1000)*T_SREG;   
    localparam  SCCB_PERIOD = IN_FREQ/SCCB_FREQ/2;
                
    reg         [clog2(SCCB_PERIOD):0] sccb_clk_cnt = 0;
    reg         sccb_clk = 0;
    reg         [1:0] stm = 0;
    reg         [5:0] reg_data_index = 0; 
    wire        [7:0] reg_data_rcvd;
    wire        [16:0] reg_data_snd;
    reg         rw;
    reg         sccb_start;
    wire        transact_done;
    wire        ack_error;
    reg         [clog2(SREG_CYCLES):0] reg_setup_tmr = 0;
    wire        data_pulse = (sccb_clk_cnt == SCCB_PERIOD/2 && sccb_clk == 0); 
    reg         do_tsreg_delay = 0;
    
    OV7670Init caminit
    (
        .index_i(reg_data_index),
        .data_o(reg_data_snd)
    );
 
    SCCBCtrl sccbcntl 
    (   
        .clk_i(clk_i),
        .rst_i(rst_i),
        .sccb_clk_i(sccb_clk),
        .data_pulse_i(data_pulse),
        .addr_i(CAM_ID),
        .data_i(reg_data_snd[16:1]),
        .rw_i(rw),
        .start_i(sccb_start),
        .ack_error_o(ack_error),
        .done_o(transact_done),
        .data_o(reg_data_rcvd),
        .sioc_o(sioc_o),
        .siod_io(siod_io)
    );    
 
    // Generate clock for the SCCB.
    always @(posedge clk_i or negedge rst_i) begin
        if (rst_i == 0) begin
            sccb_clk_cnt <= 0;
            sccb_clk <= 0;
        end else begin
            if (sccb_clk_cnt < SCCB_PERIOD) begin
                sccb_clk_cnt <= sccb_clk_cnt + 1;
            end else begin
                sccb_clk <= ~sccb_clk;
                sccb_clk_cnt <= 0;
            end
        end
    end
 

    // TODO This state machine is garbage ad hoc. Should recode to an actual state machine.
    
    reg run_state; // 0 is not running, 1 is running
    
    always @(posedge clk_i or negedge rst_i) begin
        if (rst_i==0) begin
            run_state <= 0;
        end
        else begin
            run_state <= start_i ? 1'b1 : run_state ;
        end
    end
    
    // Read/Write the registers.
    always @(posedge clk_i or negedge rst_i) begin
    
        if (rst_i == 0) begin
            done_o <= 0;
            reg_data_index <= 0;
            stm <= 0;
            sccb_start <= 0;
            rw <= 0;   
            reg_setup_tmr <= 0;
            do_tsreg_delay <= 0;
        // once registers have been written we need to wait for T_SREG ms. 
        end
        else if (run_state) begin
            else if (do_tsreg_delay == 1) begin   
                if (reg_setup_tmr == SREG_CYCLES)
                    done_o <= 1;
                else 
                reg_setup_tmr <= reg_setup_tmr + 1;
            // delay for T_SREG ms if needed 
            end
            else if  (reg_data_snd == {16'hf0f0, 1'b1}) begin
                if (reg_setup_tmr  == SREG_CYCLES)
                    reg_data_index <= reg_data_index + 1;
                else
                    reg_setup_tmr <= reg_setup_tmr + 1;
            end 
            else if (data_pulse) begin
                if(reg_data_snd != {16'hffff, 1'b1}) begin
                    done_o <= 0;
                    (* parallel_case *) case(stm)
                    2'd0: begin
                        if (transact_done == 1) 
                           stm <= 2'd0;
                        else 
                           stm <= 2'd1;
          
                        sccb_start <= 1;
                        rw <= reg_data_snd[0];
                    end
                    2'd1: begin
                        if (transact_done == 1) begin
                            if (ack_error == 1) 
                                stm <= 2'd0;
                            else 
                                stm <= 2'd2;
                        
                            rw <= reg_data_snd[0];
                            sccb_start <= 0;
                        end
                    end
                    2'd2: begin
                        reg_data_index <= reg_data_index + 1;
                        stm <= 0;
                        sccb_start <= 0;
                        rw <= reg_data_snd[0];
                    end
                    endcase
                end 
                else begin
                    stm <= 3;
                    sccb_start <= 0;
                    rw <= 0;
                    do_tsreg_delay <= 1;
                    reg_setup_tmr <= 0;
                end
            end
        end
    end
endmodule
