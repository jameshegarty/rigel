module incif_1uint32(input CLK, input CE, input [32:0] process_input, output [31:0] process_output);
parameter INSTANCE_NAME="INST";
  wire [31:0] unnamedcast695USEDMULTIPLEcast;assign unnamedcast695USEDMULTIPLEcast = (process_input[31:0]); 
  assign process_output = (((process_input[32]))?({(unnamedcast695USEDMULTIPLEcast+(32'd1))}):(unnamedcast695USEDMULTIPLEcast));
  // function: process pure=true delay=0
endmodule

module RegBy_incif_1uint32_CEtrue_initnil(input CLK, input set_valid, input CE, input [31:0] set_inp, input setby_valid, input setby_inp, output [31:0] SETBY_OUTPUT, output [31:0] GET_OUTPUT);
parameter INSTANCE_NAME="INST";
  reg [31:0] R;
  wire [31:0] regby_inner_process_output;
  always @(posedge CLK) begin if(set_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'R' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if(setby_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'R' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if((({4'b0,set_valid})+({4'b0,setby_valid})) > 5'd1) begin $display("error, function 'set' on instance 'R' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end
  wire [32:0] unnamedcallArbitrate727USEDMULTIPLEcallArbitrate;assign unnamedcallArbitrate727USEDMULTIPLEcallArbitrate = {(set_valid||setby_valid),((set_valid)?(set_inp):(regby_inner_process_output))}; 
    always @ (posedge CLK) begin if ((unnamedcallArbitrate727USEDMULTIPLEcallArbitrate[32]) && CE) begin R <= (unnamedcallArbitrate727USEDMULTIPLEcallArbitrate[31:0]); end end
  assign SETBY_OUTPUT = regby_inner_process_output;
  assign GET_OUTPUT = R;
  // function: set pure=false ONLY WIRE
  // function: setby pure=false ONLY WIRE
  // function: get pure=true ONLY WIRE
  incif_1uint32 #(.INSTANCE_NAME("regby_inner")) regby_inner(.CLK(CLK), .CE(CE), .process_input({setby_inp,R}), .process_output(regby_inner_process_output));
endmodule

module Underflow_Auint8_2_1__4_1__count76800_cycles154624_toosoonnil_UStrue(input CLK, input ready_downstream, output ready, input reset, input [64:0] process_input, output [64:0] process_output);
parameter INSTANCE_NAME="INST";
parameter OUTPUT_COUNT=0;
parameter INPUT_COUNT=0;
  wire [31:0] cycleCount_GET_OUTPUT;
  wire unnamedbinop1577USEDMULTIPLEbinop;assign unnamedbinop1577USEDMULTIPLEbinop = {((cycleCount_GET_OUTPUT)>((32'd154624)))}; 
  assign ready = {(ready_downstream||unnamedbinop1577USEDMULTIPLEbinop)};
  wire unnamedbinop1579USEDMULTIPLEbinop;assign unnamedbinop1579USEDMULTIPLEbinop = {({(ready_downstream||reset)}||unnamedbinop1577USEDMULTIPLEbinop)}; 
  wire [31:0] outputCount_GET_OUTPUT;
  wire unnamedcast1571USEDMULTIPLEcast;assign unnamedcast1571USEDMULTIPLEcast = (process_input[64]); 
  wire unnamedunary1599USEDMULTIPLEunary;assign unnamedunary1599USEDMULTIPLEunary = {(~reset)}; 
  wire [31:0] outputCount_SETBY_OUTPUT;
  wire [31:0] cycleCount_SETBY_OUTPUT;
  assign process_output = {{({({(unnamedbinop1577USEDMULTIPLEbinop&&{((outputCount_GET_OUTPUT)<((32'd76800)))})}||{({(~unnamedbinop1577USEDMULTIPLEbinop)}&&unnamedcast1571USEDMULTIPLEcast)})}&&unnamedunary1599USEDMULTIPLEunary)},((unnamedbinop1577USEDMULTIPLEbinop)?((64'd3735928559)):((process_input[63:0])))};
  // function: ready pure=true ONLY WIRE
  // function: reset pure=false ONLY WIRE
  // function: process pure=false ONLY WIRE
  RegBy_incif_1uint32_CEtrue_initnil #(.INSTANCE_NAME("outputCount")) outputCount(.CLK(CLK), .set_valid(reset), .CE(unnamedbinop1579USEDMULTIPLEbinop), .set_inp((32'd0)), .setby_valid(unnamedunary1599USEDMULTIPLEunary), .setby_inp({(ready_downstream&&{(unnamedcast1571USEDMULTIPLEcast||unnamedbinop1577USEDMULTIPLEbinop)})}), .SETBY_OUTPUT(outputCount_SETBY_OUTPUT), .GET_OUTPUT(outputCount_GET_OUTPUT));
  RegBy_incif_1uint32_CEtrue_initnil #(.INSTANCE_NAME("cycleCount")) cycleCount(.CLK(CLK), .set_valid(reset), .CE((1'd1)), .set_inp((32'd0)), .setby_valid(unnamedunary1599USEDMULTIPLEunary), .setby_inp((1'd1)), .SETBY_OUTPUT(cycleCount_SETBY_OUTPUT), .GET_OUTPUT(cycleCount_GET_OUTPUT));
endmodule

module sumwrap_uint16_to1(input CLK, input CE, input [31:0] process_input, output [15:0] process_output);
parameter INSTANCE_NAME="INST";
  wire [15:0] unnamedcast96USEDMULTIPLEcast;assign unnamedcast96USEDMULTIPLEcast = (process_input[15:0]); 
  assign process_output = (({(unnamedcast96USEDMULTIPLEcast==(16'd1))})?((16'd0)):({(unnamedcast96USEDMULTIPLEcast+(process_input[31:16]))}));
  // function: process pure=true delay=0
endmodule

module RegBy_sumwrap_uint16_to1_CEtrue_initnil(input CLK, input set_valid, input CE, input [15:0] set_inp, input setby_valid, input [15:0] setby_inp, output [15:0] SETBY_OUTPUT, output [15:0] GET_OUTPUT);
parameter INSTANCE_NAME="INST";
  reg [15:0] R;
  wire [15:0] regby_inner_process_output;
  always @(posedge CLK) begin if(set_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'R' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if(setby_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'R' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if((({4'b0,set_valid})+({4'b0,setby_valid})) > 5'd1) begin $display("error, function 'set' on instance 'R' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end
  wire [16:0] unnamedcallArbitrate136USEDMULTIPLEcallArbitrate;assign unnamedcallArbitrate136USEDMULTIPLEcallArbitrate = {(set_valid||setby_valid),((set_valid)?(set_inp):(regby_inner_process_output))}; 
    always @ (posedge CLK) begin if ((unnamedcallArbitrate136USEDMULTIPLEcallArbitrate[16]) && CE) begin R <= (unnamedcallArbitrate136USEDMULTIPLEcallArbitrate[15:0]); end end
  assign SETBY_OUTPUT = regby_inner_process_output;
  assign GET_OUTPUT = R;
  // function: set pure=false ONLY WIRE
  // function: setby pure=false ONLY WIRE
  // function: get pure=true ONLY WIRE
  sumwrap_uint16_to1 #(.INSTANCE_NAME("regby_inner")) regby_inner(.CLK(CLK), .CE(CE), .process_input({setby_inp,R}), .process_output(regby_inner_process_output));
endmodule

module ChangeRate_uint8_2_1__from4_to2_H1(input CLK, output ready, input reset, input CE, input process_valid, input [63:0] process_input, output [32:0] process_output);
parameter INSTANCE_NAME="INST";
always @(posedge CLK) begin if(reset===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'reset'", INSTANCE_NAME);  end end
always @(posedge CLK) begin if(process_valid===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'process'", INSTANCE_NAME);  end end
  wire [15:0] phase_GET_OUTPUT;
  wire unnamedbinop147_readingUSEDMULTIPLEbinop;assign unnamedbinop147_readingUSEDMULTIPLEbinop = {(phase_GET_OUTPUT==(16'd0))}; 
  assign ready = unnamedbinop147_readingUSEDMULTIPLEbinop;
  reg [31:0] SR_2;
  wire [31:0] unnamedselect157USEDMULTIPLEselect;assign unnamedselect157USEDMULTIPLEselect = ((unnamedbinop147_readingUSEDMULTIPLEbinop)?(({process_input[31:0]})):(SR_2)); 
  reg [31:0] unnamedselect157_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin unnamedselect157_delay1_validunnamednull0_CECE <= unnamedselect157USEDMULTIPLEselect; end end
  reg [31:0] SR_1;  always @ (posedge CLK) begin if (process_valid && CE) begin SR_1 <= unnamedselect157USEDMULTIPLEselect; end end
    always @ (posedge CLK) begin if (process_valid && CE) begin SR_2 <= ((unnamedbinop147_readingUSEDMULTIPLEbinop)?(({process_input[63:32]})):(SR_1)); end end
  wire [15:0] phase_SETBY_OUTPUT;
  assign process_output = {(1'd1),unnamedselect157_delay1_validunnamednull0_CECE};
  // function: ready pure=true delay=0
  // function: reset pure=false delay=0
  // function: process pure=false delay=1
  RegBy_sumwrap_uint16_to1_CEtrue_initnil #(.INSTANCE_NAME("phase")) phase(.CLK(CLK), .set_valid(reset), .CE(CE), .set_inp((16'd0)), .setby_valid(process_valid), .setby_inp((16'd1)), .SETBY_OUTPUT(phase_SETBY_OUTPUT), .GET_OUTPUT(phase_GET_OUTPUT));
endmodule

module WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1(input CLK, output ready, input reset, input CE, input process_valid, input [64:0] process_input, output [32:0] process_output);
parameter INSTANCE_NAME="INST";
always @(posedge CLK) begin if(reset===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'reset'", INSTANCE_NAME);  end end
always @(posedge CLK) begin if(process_valid===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'process'", INSTANCE_NAME);  end end
  wire WaitOnInput_inner_ready;
  assign ready = WaitOnInput_inner_ready;
  wire unnamedbinop235USEDMULTIPLEbinop;assign unnamedbinop235USEDMULTIPLEbinop = {({({(~WaitOnInput_inner_ready)}||(process_input[64]))}&&process_valid)}; 
  wire [32:0] WaitOnInput_inner_process_output;
  reg unnamedbinop235_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin unnamedbinop235_delay1_validunnamednull0_CECE <= unnamedbinop235USEDMULTIPLEbinop; end end
  assign process_output = {{((WaitOnInput_inner_process_output[32])&&unnamedbinop235_delay1_validunnamednull0_CECE)},(WaitOnInput_inner_process_output[31:0])};
  // function: ready pure=true delay=0
  // function: reset pure=false delay=0
  // function: process pure=false delay=1
  ChangeRate_uint8_2_1__from4_to2_H1 #(.INSTANCE_NAME("WaitOnInput_inner")) WaitOnInput_inner(.CLK(CLK), .ready(WaitOnInput_inner_ready), .reset(reset), .CE(CE), .process_valid(unnamedbinop235USEDMULTIPLEbinop), .process_input((process_input[63:0])), .process_output(WaitOnInput_inner_process_output));
endmodule

module ShiftRegister_1_CEtrue_TY1(input CLK, input pushPop_valid, input CE, input sr_input, output pushPop_out, input reset);
parameter INSTANCE_NAME="INST";
always @(posedge CLK) begin if(pushPop_valid===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'pushPop'", INSTANCE_NAME);  end end
always @(posedge CLK) begin if(reset===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'reset'", INSTANCE_NAME);  end end
  reg SR1;
  always @(posedge CLK) begin if(pushPop_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR1' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if(reset===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR1' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if((({4'b0,pushPop_valid})+({4'b0,reset})) > 5'd1) begin $display("error, function 'set' on instance 'SR1' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end
  wire [1:0] unnamedcallArbitrate289USEDMULTIPLEcallArbitrate;assign unnamedcallArbitrate289USEDMULTIPLEcallArbitrate = {(pushPop_valid||reset),((pushPop_valid)?(sr_input):((1'd0)))}; 
    always @ (posedge CLK) begin if ((unnamedcallArbitrate289USEDMULTIPLEcallArbitrate[1]) && CE) begin SR1 <= (unnamedcallArbitrate289USEDMULTIPLEcallArbitrate[0]); end end
  assign pushPop_out = SR1;
  // function: pushPop pure=false delay=0
  // function: reset pure=false delay=0
endmodule

module LiftHandshake_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1(input CLK, input ready_downstream, output ready, input reset, input [64:0] process_input, output [32:0] process_output);
parameter INSTANCE_NAME="INST";
parameter OUTPUT_COUNT=0;
parameter INPUT_COUNT=0;
  wire inner_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1_ready;
  assign ready = {(inner_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1_ready&&ready_downstream)};
  wire unnamedbinop270USEDMULTIPLEbinop;assign unnamedbinop270USEDMULTIPLEbinop = {(reset||ready_downstream)}; 
  wire unnamedunary271USEDMULTIPLEunary;assign unnamedunary271USEDMULTIPLEunary = {(~reset)}; 
  wire [32:0] inner_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1_process_output;
  wire validBitDelay_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1_pushPop_out;
  wire [32:0] unnamedtuple303USEDMULTIPLEtuple;assign unnamedtuple303USEDMULTIPLEtuple = {{((inner_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1_process_output[32])&&validBitDelay_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1_pushPop_out)},(inner_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1_process_output[31:0])}; 
  always @(posedge CLK) begin if({(~{((unnamedtuple303USEDMULTIPLEtuple[32])===1'bx)})} == 1'b0 && (1'd1)==1'b1) begin $display("%s: LiftHandshake: output valid bit should not be X!",INSTANCE_NAME); end end
  always @(posedge CLK) begin if({(~{((process_input[64])===1'bx)})} == 1'b0 && (1'd1)==1'b1) begin $display("%s: LiftHandshake: input valid bit should not be X!",INSTANCE_NAME); end end
  assign process_output = unnamedtuple303USEDMULTIPLEtuple;
  // function: ready pure=true ONLY WIRE
  // function: reset pure=false ONLY WIRE
  // function: process pure=false ONLY WIRE
  WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1 #(.INSTANCE_NAME("inner_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1")) inner_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1(.CLK(CLK), .ready(inner_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1_ready), .reset(reset), .CE(unnamedbinop270USEDMULTIPLEbinop), .process_valid(unnamedunary271USEDMULTIPLEunary), .process_input(process_input), .process_output(inner_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1_process_output));
  ShiftRegister_1_CEtrue_TY1 #(.INSTANCE_NAME("validBitDelay_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1")) validBitDelay_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1(.CLK(CLK), .pushPop_valid(unnamedunary271USEDMULTIPLEunary), .CE(unnamedbinop270USEDMULTIPLEbinop), .sr_input((1'd1)), .pushPop_out(validBitDelay_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1_pushPop_out), .reset(reset));
endmodule

module ShiftRegister_3_CEtrue_TY1(input CLK, input pushPop_valid, input CE, input sr_input, output pushPop_out, input reset);
parameter INSTANCE_NAME="INST";
always @(posedge CLK) begin if(pushPop_valid===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'pushPop'", INSTANCE_NAME);  end end
always @(posedge CLK) begin if(reset===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'reset'", INSTANCE_NAME);  end end
  reg SR3;
  always @(posedge CLK) begin if(pushPop_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR1' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if(reset===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR1' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if((({4'b0,pushPop_valid})+({4'b0,reset})) > 5'd1) begin $display("error, function 'set' on instance 'SR1' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end
  wire [1:0] unnamedcallArbitrate637USEDMULTIPLEcallArbitrate;assign unnamedcallArbitrate637USEDMULTIPLEcallArbitrate = {(pushPop_valid||reset),((pushPop_valid)?(sr_input):((1'd0)))}; 
  reg SR1;  always @ (posedge CLK) begin if ((unnamedcallArbitrate637USEDMULTIPLEcallArbitrate[1]) && CE) begin SR1 <= (unnamedcallArbitrate637USEDMULTIPLEcallArbitrate[0]); end end
  always @(posedge CLK) begin if(pushPop_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR2' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if(reset===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR2' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if((({4'b0,pushPop_valid})+({4'b0,reset})) > 5'd1) begin $display("error, function 'set' on instance 'SR2' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end
  wire [1:0] unnamedcallArbitrate643USEDMULTIPLEcallArbitrate;assign unnamedcallArbitrate643USEDMULTIPLEcallArbitrate = {(pushPop_valid||reset),((pushPop_valid)?(SR1):((1'd0)))}; 
  reg SR2;  always @ (posedge CLK) begin if ((unnamedcallArbitrate643USEDMULTIPLEcallArbitrate[1]) && CE) begin SR2 <= (unnamedcallArbitrate643USEDMULTIPLEcallArbitrate[0]); end end
  always @(posedge CLK) begin if(pushPop_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR3' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if(reset===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR3' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if((({4'b0,pushPop_valid})+({4'b0,reset})) > 5'd1) begin $display("error, function 'set' on instance 'SR3' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end
  wire [1:0] unnamedcallArbitrate649USEDMULTIPLEcallArbitrate;assign unnamedcallArbitrate649USEDMULTIPLEcallArbitrate = {(pushPop_valid||reset),((pushPop_valid)?(SR2):((1'd0)))}; 
    always @ (posedge CLK) begin if ((unnamedcallArbitrate649USEDMULTIPLEcallArbitrate[1]) && CE) begin SR3 <= (unnamedcallArbitrate649USEDMULTIPLEcallArbitrate[0]); end end
  assign pushPop_out = SR3;
  // function: pushPop pure=false delay=0
  // function: reset pure=false delay=0
endmodule

module incif_wrap638_inc2(input CLK, input CE, input [16:0] process_input, output [15:0] process_output);
parameter INSTANCE_NAME="INST";
  wire [15:0] unnamedcast403USEDMULTIPLEcast;assign unnamedcast403USEDMULTIPLEcast = (process_input[15:0]); 
  assign process_output = (((process_input[16]))?((({(unnamedcast403USEDMULTIPLEcast==(16'd638))})?((16'd0)):({(unnamedcast403USEDMULTIPLEcast+(16'd2))}))):(unnamedcast403USEDMULTIPLEcast));
  // function: process pure=true delay=0
endmodule

module RegBy_incif_wrap638_inc2_CEtrue_init0(input CLK, input set_valid, input CE, input [15:0] set_inp, input setby_valid, input setby_inp, output [15:0] SETBY_OUTPUT, output [15:0] GET_OUTPUT);
parameter INSTANCE_NAME="INST";
  reg [15:0] R = 16'd0;
  wire [15:0] regby_inner_process_output;
  always @(posedge CLK) begin if(set_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'R' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if(setby_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'R' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if((({4'b0,set_valid})+({4'b0,setby_valid})) > 5'd1) begin $display("error, function 'set' on instance 'R' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end
  wire [16:0] unnamedcallArbitrate454USEDMULTIPLEcallArbitrate;assign unnamedcallArbitrate454USEDMULTIPLEcallArbitrate = {(set_valid||setby_valid),((set_valid)?(set_inp):(regby_inner_process_output))}; 
    always @ (posedge CLK) begin if ((unnamedcallArbitrate454USEDMULTIPLEcallArbitrate[16]) && CE) begin R <= (unnamedcallArbitrate454USEDMULTIPLEcallArbitrate[15:0]); end end
  assign SETBY_OUTPUT = regby_inner_process_output;
  assign GET_OUTPUT = R;
  // function: set pure=false ONLY WIRE
  // function: setby pure=false ONLY WIRE
  // function: get pure=true ONLY WIRE
  incif_wrap638_inc2 #(.INSTANCE_NAME("regby_inner")) regby_inner(.CLK(CLK), .CE(CE), .process_input({setby_inp,R}), .process_output(regby_inner_process_output));
endmodule

module incif_wrap479_incnil(input CLK, input CE, input [16:0] process_input, output [15:0] process_output);
parameter INSTANCE_NAME="INST";
  wire [15:0] unnamedcast461USEDMULTIPLEcast;assign unnamedcast461USEDMULTIPLEcast = (process_input[15:0]); 
  assign process_output = (((process_input[16]))?((({(unnamedcast461USEDMULTIPLEcast==(16'd479))})?((16'd0)):({(unnamedcast461USEDMULTIPLEcast+(16'd1))}))):(unnamedcast461USEDMULTIPLEcast));
  // function: process pure=true delay=0
endmodule

module RegBy_incif_wrap479_incnil_CEtrue_init0(input CLK, input set_valid, input CE, input [15:0] set_inp, input setby_valid, input setby_inp, output [15:0] SETBY_OUTPUT, output [15:0] GET_OUTPUT);
parameter INSTANCE_NAME="INST";
  reg [15:0] R = 16'd0;
  wire [15:0] regby_inner_process_output;
  always @(posedge CLK) begin if(set_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'R' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if(setby_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'R' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if((({4'b0,set_valid})+({4'b0,setby_valid})) > 5'd1) begin $display("error, function 'set' on instance 'R' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end
  wire [16:0] unnamedcallArbitrate512USEDMULTIPLEcallArbitrate;assign unnamedcallArbitrate512USEDMULTIPLEcallArbitrate = {(set_valid||setby_valid),((set_valid)?(set_inp):(regby_inner_process_output))}; 
    always @ (posedge CLK) begin if ((unnamedcallArbitrate512USEDMULTIPLEcallArbitrate[16]) && CE) begin R <= (unnamedcallArbitrate512USEDMULTIPLEcallArbitrate[15:0]); end end
  assign SETBY_OUTPUT = regby_inner_process_output;
  assign GET_OUTPUT = R;
  // function: set pure=false ONLY WIRE
  // function: setby pure=false ONLY WIRE
  // function: get pure=true ONLY WIRE
  incif_wrap479_incnil #(.INSTANCE_NAME("regby_inner")) regby_inner(.CLK(CLK), .CE(CE), .process_input({setby_inp,R}), .process_output(regby_inner_process_output));
endmodule

module PosSeq_W640_H480_T2(input CLK, input process_valid, input CE, output [63:0] process_output, input reset);
parameter INSTANCE_NAME="INST";
always @(posedge CLK) begin if(process_valid===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'process'", INSTANCE_NAME);  end end
always @(posedge CLK) begin if(reset===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'reset'", INSTANCE_NAME);  end end
  wire [15:0] posX_posSeq_GET_OUTPUT;
  wire [15:0] posY_posSeq_GET_OUTPUT;
  reg [31:0] unnamedtuple524_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin unnamedtuple524_delay1_validunnamednull0_CECE <= {posY_posSeq_GET_OUTPUT,posX_posSeq_GET_OUTPUT}; end end
  reg [15:0] unnamedbinop528_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin unnamedbinop528_delay1_validunnamednull0_CECE <= {(posX_posSeq_GET_OUTPUT+(16'd1))}; end end
  reg [15:0] unnamedcall523_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin unnamedcall523_delay1_validunnamednull0_CECE <= posY_posSeq_GET_OUTPUT; end end
  wire [15:0] posX_posSeq_SETBY_OUTPUT;
  wire [15:0] posY_posSeq_SETBY_OUTPUT;
  assign process_output = {{unnamedcall523_delay1_validunnamednull0_CECE,unnamedbinop528_delay1_validunnamednull0_CECE},unnamedtuple524_delay1_validunnamednull0_CECE};
  // function: process pure=false delay=1
  // function: reset pure=false delay=0
  RegBy_incif_wrap638_inc2_CEtrue_init0 #(.INSTANCE_NAME("posX_posSeq")) posX_posSeq(.CLK(CLK), .set_valid(reset), .CE(CE), .set_inp((16'd0)), .setby_valid(process_valid), .setby_inp((1'd1)), .SETBY_OUTPUT(posX_posSeq_SETBY_OUTPUT), .GET_OUTPUT(posX_posSeq_GET_OUTPUT));
  RegBy_incif_wrap479_incnil_CEtrue_init0 #(.INSTANCE_NAME("posY_posSeq")) posY_posSeq(.CLK(CLK), .set_valid(reset), .CE(CE), .set_inp((16'd0)), .setby_valid(process_valid), .setby_inp({(posX_posSeq_GET_OUTPUT==(16'd638))}), .SETBY_OUTPUT(posY_posSeq_SETBY_OUTPUT), .GET_OUTPUT(posY_posSeq_GET_OUTPUT));
endmodule

module packTupleArrays_table__0x4199b7d0(input CLK, input process_CE, input [95:0] process_input, output [95:0] process_output);
parameter INSTANCE_NAME="INST";
  wire [63:0] unnamedcast321USEDMULTIPLEcast;assign unnamedcast321USEDMULTIPLEcast = (process_input[63:0]); 
  wire [31:0] unnamedcast325USEDMULTIPLEcast;assign unnamedcast325USEDMULTIPLEcast = (process_input[95:64]); 
  assign process_output = {{({unnamedcast325USEDMULTIPLEcast[31:16]}),({unnamedcast321USEDMULTIPLEcast[63:32]})},{({unnamedcast325USEDMULTIPLEcast[15:0]}),({unnamedcast321USEDMULTIPLEcast[31:0]})}};
  // function: process pure=true delay=0
endmodule

module split(input CLK, input process_CE, input [47:0] inp, output [31:0] process_output);
parameter INSTANCE_NAME="INST";
  wire [31:0] unnamedcast45;assign unnamedcast45 = (inp[31:0]);  // wire for array index
  reg unnamedbinop50_delay1_validunnamednull0_CEprocess_CE;  always @ (posedge CLK) begin if (process_CE) begin unnamedbinop50_delay1_validunnamednull0_CEprocess_CE <= {(((unnamedcast45[15:0]))<((16'd320)))}; end end
  wire [15:0] unnamedcast52USEDMULTIPLEcast;assign unnamedcast52USEDMULTIPLEcast = (inp[47:32]); 
  reg [7:0] unnamedcast54_delay1_validunnamednull0_CEprocess_CE;  always @ (posedge CLK) begin if (process_CE) begin unnamedcast54_delay1_validunnamednull0_CEprocess_CE <= ({unnamedcast52USEDMULTIPLEcast[7:0]}); end end
  reg [7:0] unnamedcast58_delay1_validunnamednull0_CEprocess_CE;  always @ (posedge CLK) begin if (process_CE) begin unnamedcast58_delay1_validunnamednull0_CEprocess_CE <= ({unnamedcast52USEDMULTIPLEcast[15:8]}); end end
  reg [7:0] unnamedselect59_delay1_validunnamednull0_CEprocess_CE;  always @ (posedge CLK) begin if (process_CE) begin unnamedselect59_delay1_validunnamednull0_CEprocess_CE <= ((unnamedbinop50_delay1_validunnamednull0_CEprocess_CE)?(unnamedcast54_delay1_validunnamednull0_CEprocess_CE):(unnamedcast58_delay1_validunnamednull0_CEprocess_CE)); end end
  assign process_output = {(8'd0),unnamedselect59_delay1_validunnamednull0_CEprocess_CE,unnamedselect59_delay1_validunnamednull0_CEprocess_CE,unnamedselect59_delay1_validunnamednull0_CEprocess_CE};
  // function: process pure=true delay=2
endmodule

module map_split_W2_H1(input CLK, input process_CE, input [95:0] process_input, output [63:0] process_output);
parameter INSTANCE_NAME="INST";
  wire [31:0] inner0_0_process_output;
  wire [31:0] inner1_0_process_output;
  assign process_output = {inner1_0_process_output,inner0_0_process_output};
  // function: process pure=true delay=2
  split #(.INSTANCE_NAME("inner0_0")) inner0_0(.CLK(CLK), .process_CE(process_CE), .inp(({process_input[47:0]})), .process_output(inner0_0_process_output));
  split #(.INSTANCE_NAME("inner1_0")) inner1_0(.CLK(CLK), .process_CE(process_CE), .inp(({process_input[95:48]})), .process_output(inner1_0_process_output));
endmodule

module liftXYSeqPointwise_lift_split(input CLK, input CE, input [95:0] process_input, output [63:0] process_output);
parameter INSTANCE_NAME="INST";
  wire [95:0] unp_process_output;
  wire [63:0] f_process_output;
  assign process_output = f_process_output;
  // function: process pure=true delay=2
  // function: reset pure=true delay=0
  packTupleArrays_table__0x4199b7d0 #(.INSTANCE_NAME("unp")) unp(.CLK(CLK), .process_CE(CE), .process_input(process_input), .process_output(unp_process_output));
  map_split_W2_H1 #(.INSTANCE_NAME("f")) f(.CLK(CLK), .process_CE(CE), .process_input(unp_process_output), .process_output(f_process_output));
endmodule

module liftXYSeq_lambda(input CLK, input process_valid, input CE, input [31:0] process_input, output [63:0] process_output, input reset);
parameter INSTANCE_NAME="INST";
always @(posedge CLK) begin if(process_valid===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'process'", INSTANCE_NAME);  end end
always @(posedge CLK) begin if(reset===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'reset'", INSTANCE_NAME);  end end
  wire [63:0] p_process_output;
  reg [31:0] process_input_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin process_input_delay1_validunnamednull0_CECE <= process_input; end end
  wire [63:0] m_process_output;
  assign process_output = m_process_output;
  // function: process pure=false delay=3
  // function: reset pure=false delay=0
  PosSeq_W640_H480_T2 #(.INSTANCE_NAME("p")) p(.CLK(CLK), .process_valid(process_valid), .CE(CE), .process_output(p_process_output), .reset(reset));
  liftXYSeqPointwise_lift_split #(.INSTANCE_NAME("m")) m(.CLK(CLK), .CE(CE), .process_input({process_input_delay1_validunnamednull0_CECE,p_process_output}), .process_output(m_process_output));
endmodule

module MakeHandshake_liftXYSeq_lambda(input CLK, input ready_downstream, output ready, input reset, input [32:0] process_input, output [64:0] process_output);
parameter INSTANCE_NAME="INST";
parameter OUTPUT_COUNT=0;
parameter INPUT_COUNT=0;
  assign ready = ready_downstream;
  wire unnamedbinop661USEDMULTIPLEbinop;assign unnamedbinop661USEDMULTIPLEbinop = {(ready_downstream||reset)}; 
  wire unnamedcast669USEDMULTIPLEcast;assign unnamedcast669USEDMULTIPLEcast = (process_input[32]); 
  wire [63:0] inner_process_output;
  wire validBitDelay_liftXYSeq_lambda_pushPop_out;
  always @(posedge CLK) begin if({(~{(unnamedcast669USEDMULTIPLEcast===1'bx)})} == 1'b0 && (1'd1)==1'b1) begin $display("%s: MakeHandshake: input valid bit should not be X!",INSTANCE_NAME); end end
  assign process_output = {validBitDelay_liftXYSeq_lambda_pushPop_out,inner_process_output};
  // function: ready pure=true ONLY WIRE
  // function: reset pure=false ONLY WIRE
  // function: process pure=false ONLY WIRE
  ShiftRegister_3_CEtrue_TY1 #(.INSTANCE_NAME("validBitDelay_liftXYSeq_lambda")) validBitDelay_liftXYSeq_lambda(.CLK(CLK), .pushPop_valid({(~reset)}), .CE(unnamedbinop661USEDMULTIPLEbinop), .sr_input(unnamedcast669USEDMULTIPLEcast), .pushPop_out(validBitDelay_liftXYSeq_lambda_pushPop_out), .reset(reset));
  liftXYSeq_lambda #(.INSTANCE_NAME("inner")) inner(.CLK(CLK), .process_valid(unnamedcast669USEDMULTIPLEcast), .CE(unnamedbinop661USEDMULTIPLEbinop), .process_input((process_input[31:0])), .process_output(inner_process_output), .reset(reset));
endmodule

module hsfn(input CLK, input ready_downstream, output ready, input reset, input [64:0] process_input, output [64:0] process_output);
parameter INSTANCE_NAME="INST";
parameter OUTPUT_COUNT=0;
parameter INPUT_COUNT=0;
  wire hsfn_f_ready;
  wire hsfn_g_ready;
  assign ready = hsfn_g_ready;
  wire [32:0] hsfn_g_process_output;
  wire [64:0] hsfn_f_process_output;
  assign process_output = hsfn_f_process_output;
  // function: ready pure=true ONLY WIRE
  // function: reset pure=false ONLY WIRE
  // function: process pure=false ONLY WIRE
  LiftHandshake_WaitOnInput_ChangeRate_uint8_2_1__from4_to2_H1 #(.INSTANCE_NAME("hsfn_g")) hsfn_g(.CLK(CLK), .ready_downstream(hsfn_f_ready), .ready(hsfn_g_ready), .reset(reset), .process_input(process_input), .process_output(hsfn_g_process_output));
  MakeHandshake_liftXYSeq_lambda #(.INSTANCE_NAME("hsfn_f")) hsfn_f(.CLK(CLK), .ready_downstream(ready_downstream), .ready(hsfn_f_ready), .reset(reset), .process_input(hsfn_g_process_output), .process_output(hsfn_f_process_output));
endmodule

module Overflow_153600(input CLK, input process_valid, input CE, input [63:0] process_input, output [64:0] process_output, input reset);
parameter INSTANCE_NAME="INST";
always @(posedge CLK) begin if(process_valid===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'process'", INSTANCE_NAME);  end end
always @(posedge CLK) begin if(reset===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'reset'", INSTANCE_NAME);  end end
  reg [63:0] process_input_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin process_input_delay1_validunnamednull0_CECE <= process_input; end end
  wire [31:0] cnt_GET_OUTPUT;
  reg unnamedbinop871_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin unnamedbinop871_delay1_validunnamednull0_CECE <= {((cnt_GET_OUTPUT)<((32'd153600)))}; end end
  wire [31:0] cnt_SETBY_OUTPUT;
  assign process_output = {unnamedbinop871_delay1_validunnamednull0_CECE,process_input_delay1_validunnamednull0_CECE};
  // function: process pure=false delay=1
  // function: reset pure=false delay=0
  RegBy_incif_1uint32_CEtrue_initnil #(.INSTANCE_NAME("cnt")) cnt(.CLK(CLK), .set_valid(reset), .CE(CE), .set_inp((32'd0)), .setby_valid(process_valid), .setby_inp((1'd1)), .SETBY_OUTPUT(cnt_SETBY_OUTPUT), .GET_OUTPUT(cnt_GET_OUTPUT));
endmodule

module LiftDecimate_Overflow_153600(input CLK, output ready, input reset, input CE, input process_valid, input [64:0] process_input, output [64:0] process_output);
parameter INSTANCE_NAME="INST";
always @(posedge CLK) begin if(reset===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'reset'", INSTANCE_NAME);  end end
always @(posedge CLK) begin if(process_valid===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'process'", INSTANCE_NAME);  end end
  assign ready = (1'd1);
  wire unnamedcast899USEDMULTIPLEcast;assign unnamedcast899USEDMULTIPLEcast = (process_input[64]); 
  wire [64:0] LiftDecimate_inner_Overflow_153600_process_output;
  reg [63:0] unnamedcast902_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin unnamedcast902_delay1_validunnamednull0_CECE <= (LiftDecimate_inner_Overflow_153600_process_output[63:0]); end end
  reg unnamedcast899_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin unnamedcast899_delay1_validunnamednull0_CECE <= unnamedcast899USEDMULTIPLEcast; end end
  reg unnamedbinop907_delay1_validunnamednull0_CECE;  always @ (posedge CLK) begin if (CE) begin unnamedbinop907_delay1_validunnamednull0_CECE <= {((LiftDecimate_inner_Overflow_153600_process_output[64])&&unnamedcast899_delay1_validunnamednull0_CECE)}; end end
  assign process_output = {unnamedbinop907_delay1_validunnamednull0_CECE,unnamedcast902_delay1_validunnamednull0_CECE};
  // function: ready pure=true delay=0
  // function: reset pure=false delay=0
  // function: process pure=false delay=2
  Overflow_153600 #(.INSTANCE_NAME("LiftDecimate_inner_Overflow_153600")) LiftDecimate_inner_Overflow_153600(.CLK(CLK), .process_valid({(unnamedcast899USEDMULTIPLEcast&&process_valid)}), .CE(CE), .process_input((process_input[63:0])), .process_output(LiftDecimate_inner_Overflow_153600_process_output), .reset(reset));
endmodule

module ShiftRegister_2_CEtrue_TY1(input CLK, input pushPop_valid, input CE, input sr_input, output pushPop_out, input reset);
parameter INSTANCE_NAME="INST";
always @(posedge CLK) begin if(pushPop_valid===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'pushPop'", INSTANCE_NAME);  end end
always @(posedge CLK) begin if(reset===1'bx) begin $display("Valid bit can't be x! Module '%s' function 'reset'", INSTANCE_NAME);  end end
  reg SR2;
  always @(posedge CLK) begin if(pushPop_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR1' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if(reset===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR1' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if((({4'b0,pushPop_valid})+({4'b0,reset})) > 5'd1) begin $display("error, function 'set' on instance 'SR1' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end
  wire [1:0] unnamedcallArbitrate974USEDMULTIPLEcallArbitrate;assign unnamedcallArbitrate974USEDMULTIPLEcallArbitrate = {(pushPop_valid||reset),((pushPop_valid)?(sr_input):((1'd0)))}; 
  reg SR1;  always @ (posedge CLK) begin if ((unnamedcallArbitrate974USEDMULTIPLEcallArbitrate[1]) && CE) begin SR1 <= (unnamedcallArbitrate974USEDMULTIPLEcallArbitrate[0]); end end
  always @(posedge CLK) begin if(pushPop_valid===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR2' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if(reset===1'bx) begin $display("valid bit can't be x! Module '%s' instance 'SR2' function 'set'", INSTANCE_NAME); end end
  always @(posedge CLK) begin if((({4'b0,pushPop_valid})+({4'b0,reset})) > 5'd1) begin $display("error, function 'set' on instance 'SR2' in module '%s' has multiple valid bits active in same cycle!",INSTANCE_NAME);$finish(); end end
  wire [1:0] unnamedcallArbitrate980USEDMULTIPLEcallArbitrate;assign unnamedcallArbitrate980USEDMULTIPLEcallArbitrate = {(pushPop_valid||reset),((pushPop_valid)?(SR1):((1'd0)))}; 
    always @ (posedge CLK) begin if ((unnamedcallArbitrate980USEDMULTIPLEcallArbitrate[1]) && CE) begin SR2 <= (unnamedcallArbitrate980USEDMULTIPLEcallArbitrate[0]); end end
  assign pushPop_out = SR2;
  // function: pushPop pure=false delay=0
  // function: reset pure=false delay=0
endmodule

module LiftHandshake_LiftDecimate_Overflow_153600(input CLK, input ready_downstream, output ready, input reset, input [64:0] process_input, output [64:0] process_output);
parameter INSTANCE_NAME="INST";
parameter OUTPUT_COUNT=0;
parameter INPUT_COUNT=0;
  wire inner_LiftDecimate_Overflow_153600_ready;
  assign ready = {(inner_LiftDecimate_Overflow_153600_ready&&ready_downstream)};
  wire unnamedbinop944USEDMULTIPLEbinop;assign unnamedbinop944USEDMULTIPLEbinop = {(reset||ready_downstream)}; 
  wire unnamedunary945USEDMULTIPLEunary;assign unnamedunary945USEDMULTIPLEunary = {(~reset)}; 
  wire [64:0] inner_LiftDecimate_Overflow_153600_process_output;
  wire validBitDelay_LiftDecimate_Overflow_153600_pushPop_out;
  wire [64:0] unnamedtuple994USEDMULTIPLEtuple;assign unnamedtuple994USEDMULTIPLEtuple = {{((inner_LiftDecimate_Overflow_153600_process_output[64])&&validBitDelay_LiftDecimate_Overflow_153600_pushPop_out)},(inner_LiftDecimate_Overflow_153600_process_output[63:0])}; 
  always @(posedge CLK) begin if({(~{((unnamedtuple994USEDMULTIPLEtuple[64])===1'bx)})} == 1'b0 && (1'd1)==1'b1) begin $display("%s: LiftHandshake: output valid bit should not be X!",INSTANCE_NAME); end end
  always @(posedge CLK) begin if({(~{((process_input[64])===1'bx)})} == 1'b0 && (1'd1)==1'b1) begin $display("%s: LiftHandshake: input valid bit should not be X!",INSTANCE_NAME); end end
  assign process_output = unnamedtuple994USEDMULTIPLEtuple;
  // function: ready pure=true ONLY WIRE
  // function: reset pure=false ONLY WIRE
  // function: process pure=false ONLY WIRE
  LiftDecimate_Overflow_153600 #(.INSTANCE_NAME("inner_LiftDecimate_Overflow_153600")) inner_LiftDecimate_Overflow_153600(.CLK(CLK), .ready(inner_LiftDecimate_Overflow_153600_ready), .reset(reset), .CE(unnamedbinop944USEDMULTIPLEbinop), .process_valid(unnamedunary945USEDMULTIPLEunary), .process_input(process_input), .process_output(inner_LiftDecimate_Overflow_153600_process_output));
  ShiftRegister_2_CEtrue_TY1 #(.INSTANCE_NAME("validBitDelay_LiftDecimate_Overflow_153600")) validBitDelay_LiftDecimate_Overflow_153600(.CLK(CLK), .pushPop_valid(unnamedunary945USEDMULTIPLEunary), .CE(unnamedbinop944USEDMULTIPLEbinop), .sr_input((1'd1)), .pushPop_out(validBitDelay_LiftDecimate_Overflow_153600_pushPop_out), .reset(reset));
endmodule

module Underflow_Auint8_4_1__2_1__count153600_cycles154624_toosoonnil_USfalse(input CLK, input ready_downstream, output ready, input reset, input [64:0] process_input, output [64:0] process_output);
parameter INSTANCE_NAME="INST";
parameter OUTPUT_COUNT=0;
parameter INPUT_COUNT=0;
  assign ready = ready_downstream;
  wire unnamedbinop1615USEDMULTIPLEbinop;assign unnamedbinop1615USEDMULTIPLEbinop = {(ready_downstream||reset)}; 
  wire [31:0] cycleCount_GET_OUTPUT;
  wire unnamedbinop1614USEDMULTIPLEbinop;assign unnamedbinop1614USEDMULTIPLEbinop = {((cycleCount_GET_OUTPUT)>((32'd154624)))}; 
  wire [31:0] outputCount_GET_OUTPUT;
  wire unnamedcast1608USEDMULTIPLEcast;assign unnamedcast1608USEDMULTIPLEcast = (process_input[64]); 
  wire unnamedunary1634USEDMULTIPLEunary;assign unnamedunary1634USEDMULTIPLEunary = {(~reset)}; 
  wire [31:0] outputCount_SETBY_OUTPUT;
  wire [31:0] cycleCount_SETBY_OUTPUT;
  assign process_output = {{({({(unnamedbinop1614USEDMULTIPLEbinop&&{((outputCount_GET_OUTPUT)<((32'd153600)))})}||{({(~unnamedbinop1614USEDMULTIPLEbinop)}&&unnamedcast1608USEDMULTIPLEcast)})}&&unnamedunary1634USEDMULTIPLEunary)},((unnamedbinop1614USEDMULTIPLEbinop)?((64'd3735928559)):((process_input[63:0])))};
  // function: ready pure=true ONLY WIRE
  // function: reset pure=false ONLY WIRE
  // function: process pure=false ONLY WIRE
  RegBy_incif_1uint32_CEtrue_initnil #(.INSTANCE_NAME("outputCount")) outputCount(.CLK(CLK), .set_valid(reset), .CE(unnamedbinop1615USEDMULTIPLEbinop), .set_inp((32'd0)), .setby_valid(unnamedunary1634USEDMULTIPLEunary), .setby_inp({(ready_downstream&&{(unnamedcast1608USEDMULTIPLEcast||unnamedbinop1614USEDMULTIPLEbinop)})}), .SETBY_OUTPUT(outputCount_SETBY_OUTPUT), .GET_OUTPUT(outputCount_GET_OUTPUT));
  RegBy_incif_1uint32_CEtrue_initnil #(.INSTANCE_NAME("cycleCount")) cycleCount(.CLK(CLK), .set_valid(reset), .CE(unnamedbinop1615USEDMULTIPLEbinop), .set_inp((32'd0)), .setby_valid(unnamedunary1634USEDMULTIPLEunary), .setby_inp((1'd1)), .SETBY_OUTPUT(cycleCount_SETBY_OUTPUT), .GET_OUTPUT(cycleCount_GET_OUTPUT));
endmodule

module harnessaxi(input CLK, input ready_downstream, output ready, input reset, input [64:0] process_input, output [64:0] process_output);
parameter INSTANCE_NAME="INST";
parameter OUTPUT_COUNT=0;
parameter INPUT_COUNT=0;
  wire underflow_ready;
  wire overflow_ready;
  wire hsfna_ready;
  wire underflow_US_ready;
  assign ready = underflow_US_ready;
  wire [64:0] underflow_US_process_output;
  wire [64:0] hsfna_process_output;
  wire [64:0] overflow_process_output;
  wire [64:0] underflow_process_output;
  assign process_output = underflow_process_output;
  // function: ready pure=true ONLY WIRE
  // function: reset pure=false ONLY WIRE
  // function: process pure=false ONLY WIRE
  Underflow_Auint8_2_1__4_1__count76800_cycles154624_toosoonnil_UStrue #(.INSTANCE_NAME("underflow_US")) underflow_US(.CLK(CLK), .ready_downstream(hsfna_ready), .ready(underflow_US_ready), .reset(reset), .process_input(process_input), .process_output(underflow_US_process_output));
  hsfn #(.INSTANCE_NAME("hsfna")) hsfna(.CLK(CLK), .ready_downstream(overflow_ready), .ready(hsfna_ready), .reset(reset), .process_input(underflow_US_process_output), .process_output(hsfna_process_output));
  LiftHandshake_LiftDecimate_Overflow_153600 #(.INSTANCE_NAME("overflow")) overflow(.CLK(CLK), .ready_downstream(underflow_ready), .ready(overflow_ready), .reset(reset), .process_input(hsfna_process_output), .process_output(overflow_process_output));
  Underflow_Auint8_4_1__2_1__count153600_cycles154624_toosoonnil_USfalse #(.INSTANCE_NAME("underflow")) underflow(.CLK(CLK), .ready_downstream(ready_downstream), .ready(underflow_ready), .reset(reset), .process_input(overflow_process_output), .process_output(underflow_process_output));
endmodule

`timescale 1ps/1ps

module ict106_axilite_conv1 #
  (
   parameter integer C_AXI_ID_WIDTH              = 12,
   parameter integer C_AXI_ADDR_WIDTH            = 32,
   parameter integer C_AXI_DATA_WIDTH            = 32 // CONSTANT
   )
  (
   // System Signals
   input  wire                          ACLK,
   input  wire                          ARESETN,
   input  wire [C_AXI_ID_WIDTH-1:0]     S_AXI_AWID,
   input  wire [C_AXI_ADDR_WIDTH-1:0]   S_AXI_AWADDR,
   input  wire                          S_AXI_AWVALID,
   output wire                          S_AXI_AWREADY,
   input  wire [C_AXI_DATA_WIDTH-1:0]   S_AXI_WDATA,
   input  wire [C_AXI_DATA_WIDTH/8-1:0] S_AXI_WSTRB,
   input  wire                          S_AXI_WVALID,
   output wire                          S_AXI_WREADY,
   output wire [C_AXI_ID_WIDTH-1:0]     S_AXI_BID,
   output wire [2-1:0]                  S_AXI_BRESP,
   output wire                          S_AXI_BVALID,
   input  wire                          S_AXI_BREADY,
   input  wire [C_AXI_ID_WIDTH-1:0]     S_AXI_ARID,
   input  wire [C_AXI_ADDR_WIDTH-1:0]   S_AXI_ARADDR,
   input  wire                          S_AXI_ARVALID,
   output wire                          S_AXI_ARREADY,
   output wire [C_AXI_ID_WIDTH-1:0]     S_AXI_RID,
   output wire [C_AXI_DATA_WIDTH-1:0]   S_AXI_RDATA,
   output wire [2-1:0]                  S_AXI_RRESP,
   output wire                          S_AXI_RLAST,    // Constant =1
   output wire                          S_AXI_RVALID,
   input  wire                          S_AXI_RREADY,
   output wire [C_AXI_ADDR_WIDTH-1:0]   M_AXI_AWADDR,
   output wire                          M_AXI_AWVALID,
   input  wire                          M_AXI_AWREADY,
   output wire [C_AXI_DATA_WIDTH-1:0]   M_AXI_WDATA,
   output wire [C_AXI_DATA_WIDTH/8-1:0] M_AXI_WSTRB,
   output wire                          M_AXI_WVALID,
   input  wire                          M_AXI_WREADY,
   input  wire [2-1:0]                  M_AXI_BRESP,
   input  wire                          M_AXI_BVALID,
   output wire                          M_AXI_BREADY,
   output wire [C_AXI_ADDR_WIDTH-1:0]   M_AXI_ARADDR,
   output wire                          M_AXI_ARVALID,
   input  wire                          M_AXI_ARREADY,
   input  wire [C_AXI_DATA_WIDTH-1:0]   M_AXI_RDATA,
   input  wire [2-1:0]                  M_AXI_RRESP,
   input  wire                          M_AXI_RVALID,
   output wire                          M_AXI_RREADY
  );
  
  wire [31:0] m_axaddr;

  // Arbiter
  reg read_active;
  reg write_active;
  reg busy;

  wire read_req;
  wire write_req;
  wire read_complete;
  wire write_complete;
  
  reg [1:0] areset_d; // Reset delay register
  always @(posedge ACLK) begin
    areset_d <= {areset_d[0], ~ARESETN};
  end
  
  assign read_req  = S_AXI_ARVALID & ~write_active & ~busy & ~|areset_d;
  assign write_req = (S_AXI_AWVALID & ~read_active & ~busy & ~S_AXI_ARVALID & ~|areset_d) | (write_active & ~busy);

  assign read_complete  = M_AXI_RVALID & S_AXI_RREADY;
  assign write_complete = M_AXI_BVALID & S_AXI_BREADY;

  always @(posedge ACLK) begin : arbiter_read_ff
    if (~ARESETN)
      read_active <= 1'b0;
    else if (read_complete)
      read_active <= 1'b0;
    else if (read_req)
      read_active <= 1'b1;
  end

  always @(posedge ACLK) begin : arbiter_write_ff
    if (~ARESETN)
      write_active <= 1'b0;
    else if (write_complete)
      write_active <= 1'b0;
    else if (write_req)
      write_active <= 1'b1;
  end

  always @(posedge ACLK) begin : arbiter_busy_ff
    if (~ARESETN)
      busy <= 1'b0;
    else if (read_complete | write_complete)
      busy <= 1'b0;
    else if ((S_AXI_AWVALID & M_AXI_AWREADY & ~read_req) | (S_AXI_ARVALID & M_AXI_ARREADY & ~write_req))
      busy <= 1'b1;
  end

  assign M_AXI_ARVALID = read_req;
  assign S_AXI_ARREADY = M_AXI_ARREADY & read_req;

  assign M_AXI_AWVALID = write_req;
  assign S_AXI_AWREADY = M_AXI_AWREADY & write_req;

  assign M_AXI_RREADY  = S_AXI_RREADY & read_active;
  assign S_AXI_RVALID  = M_AXI_RVALID & read_active;

  assign M_AXI_BREADY  = S_AXI_BREADY & write_active;
  assign S_AXI_BVALID  = M_AXI_BVALID & write_active;

  // Address multiplexer
  assign m_axaddr = (read_req) ? S_AXI_ARADDR : S_AXI_AWADDR;

  // Id multiplexer and flip-flop
  reg [C_AXI_ID_WIDTH-1:0] s_axid;

  always @(posedge ACLK) begin : axid
    if      (~ARESETN)    s_axid <= {C_AXI_ID_WIDTH{1'b0}};
    else if (read_req)  s_axid <= S_AXI_ARID;
    else if (write_req) s_axid <= S_AXI_AWID;
  end

  assign S_AXI_BID = s_axid;
  assign S_AXI_RID = s_axid;

  assign M_AXI_AWADDR = m_axaddr;
  assign M_AXI_ARADDR = m_axaddr;


  // Feed-through signals
  assign S_AXI_WREADY   = M_AXI_WREADY & ~|areset_d;
  assign S_AXI_BRESP    = M_AXI_BRESP;
  assign S_AXI_RDATA    = M_AXI_RDATA;
  assign S_AXI_RRESP    = M_AXI_RRESP;
  assign S_AXI_RLAST    = 1'b1;

  assign M_AXI_WVALID   = S_AXI_WVALID & ~|areset_d;
  assign M_AXI_WDATA    = S_AXI_WDATA;
  assign M_AXI_WSTRB    = S_AXI_WSTRB;

endmodule

module Conf(
    input ACLK,
    input ARESETN,
    //AXI Inputs
    input [31:0] S_AXI_ARADDR,
    input [11:0] S_AXI_ARID,
    output S_AXI_ARREADY,
    input S_AXI_ARVALID,
    input [31:0] S_AXI_AWADDR,
    input [11:0] S_AXI_AWID,
    output S_AXI_AWREADY,
    input S_AXI_AWVALID,
    output [11:0] S_AXI_BID,
    input S_AXI_BREADY,
    output [1:0] S_AXI_BRESP,
    output S_AXI_BVALID,
    output [31:0] S_AXI_RDATA,
    output [11:0] S_AXI_RID,
    output S_AXI_RLAST,
    input S_AXI_RREADY,
    output [1:0] S_AXI_RRESP,
    output S_AXI_RVALID,
    input [31:0] S_AXI_WDATA,
    output S_AXI_WREADY,
    input [3:0] S_AXI_WSTRB,
    input S_AXI_WVALID,
    
    output CONFIG_VALID,
    input CONFIG_READY,
    output [31:0] CONFIG_CMD,
    output [31:0] CONFIG_SRC,
    output [31:0] CONFIG_DEST,
    output [31:0] CONFIG_LEN,
    output CONFIG_IRQ
    );

    //Convert Input signals to AXI lite, to avoid ID matching
    wire [31:0] LITE_ARADDR;
    wire LITE_ARREADY;
    wire LITE_ARVALID;
    wire [31:0] LITE_AWADDR;
    wire LITE_AWREADY;
    wire LITE_AWVALID;
    wire LITE_BREADY;
    reg [1:0] LITE_BRESP;
    wire LITE_BVALID;
    reg [31:0] LITE_RDATA;
    wire LITE_RREADY;
    reg [1:0] LITE_RRESP;
    wire LITE_RVALID;
    wire [31:0] LITE_WDATA;
    wire LITE_WREADY;
    wire [3:0] LITE_WSTRB;
    wire LITE_WVALID;
    
    ict106_axilite_conv axilite(
    .ACLK(ACLK),
    .ARESETN(ARESETN),
    .S_AXI_ARADDR(S_AXI_ARADDR), 
    .S_AXI_ARID(S_AXI_ARID),  
    .S_AXI_ARREADY(S_AXI_ARREADY), 
    .S_AXI_ARVALID(S_AXI_ARVALID), 
    .S_AXI_AWADDR(S_AXI_AWADDR), 
    .S_AXI_AWID(S_AXI_AWID), 
    .S_AXI_AWREADY(S_AXI_AWREADY), 
    .S_AXI_AWVALID(S_AXI_AWVALID), 
    .S_AXI_BID(S_AXI_BID), 
    .S_AXI_BREADY(S_AXI_BREADY), 
    .S_AXI_BRESP(S_AXI_BRESP), 
    .S_AXI_BVALID(S_AXI_BVALID), 
    .S_AXI_RDATA(S_AXI_RDATA), 
    .S_AXI_RID(S_AXI_RID), 
    .S_AXI_RLAST(S_AXI_RLAST), 
    .S_AXI_RREADY(S_AXI_RREADY), 
    .S_AXI_RRESP(S_AXI_RRESP), 
    .S_AXI_RVALID(S_AXI_RVALID), 
    .S_AXI_WDATA(S_AXI_WDATA), 
    .S_AXI_WREADY(S_AXI_WREADY), 
    .S_AXI_WSTRB(S_AXI_WSTRB), 
    .S_AXI_WVALID(S_AXI_WVALID),
       
    .M_AXI_ARADDR(LITE_ARADDR),
    .M_AXI_ARREADY(LITE_ARREADY),
    .M_AXI_ARVALID(LITE_ARVALID),
    .M_AXI_AWADDR(LITE_AWADDR),
    .M_AXI_AWREADY(LITE_AWREADY),
    .M_AXI_AWVALID(LITE_AWVALID),
    .M_AXI_BREADY(LITE_BREADY),
    .M_AXI_BRESP(LITE_BRESP),
    .M_AXI_BVALID(LITE_BVALID),
    .M_AXI_RDATA(LITE_RDATA),
    .M_AXI_RREADY(LITE_RREADY),
    .M_AXI_RRESP(LITE_RRESP),
    .M_AXI_RVALID(LITE_RVALID),
    .M_AXI_WDATA(LITE_WDATA),
    .M_AXI_WREADY(LITE_WREADY),
    .M_AXI_WSTRB(LITE_WSTRB),
    .M_AXI_WVALID(LITE_WVALID)
  );

parameter NREG = 4;
parameter W = 32;

reg [W-1:0] data[NREG-1:0];

parameter IDLE = 0, RWAIT = 1;
parameter OK = 2'b00, SLVERR = 2'b10;

reg [31:0] counter;

//READS
reg r_state;
wire [1:0] r_select;
assign r_select  = LITE_ARADDR[3:2];
assign ar_good = {LITE_ARADDR[31:4], 2'b00, LITE_ARADDR[1:0]} == 32'h70000000;
assign LITE_ARREADY = (r_state == IDLE);
assign LITE_RVALID = (r_state == RWAIT);
always @(posedge ACLK) begin
    if(ARESETN == 0) begin
        r_state <= IDLE;
    end else case(r_state)
        IDLE: begin
            if(LITE_ARVALID) begin
                LITE_RRESP <= ar_good ? OK : SLVERR;
                LITE_RDATA <= (r_select == 2'b0) ? counter : data[r_select];
                r_state <= RWAIT;
            end
        end
        RWAIT: begin
            if(LITE_RREADY)
                r_state <= IDLE;
        end
    endcase
end 

//WRITES
reg w_state;
reg [1:0] w_select_r;
reg w_wrotedata;
reg w_wroteresp;

wire [1:0] w_select;
assign w_select  = LITE_AWADDR[3:2];
assign aw_good = {LITE_AWADDR[31:4], 2'b00, LITE_AWADDR[1:0]} == 32'h70000000;

assign LITE_AWREADY = (w_state == IDLE);
assign LITE_WREADY = (w_state == RWAIT) && !w_wrotedata;
assign LITE_BVALID = (w_state == RWAIT) && !w_wroteresp;

always @(posedge ACLK) begin
    if(ARESETN == 0) begin
        w_state <= IDLE;
        w_wrotedata <= 0;
        w_wroteresp <= 0;
    end else case(w_state)
        IDLE: begin
            if(LITE_AWVALID) begin
                LITE_BRESP <= aw_good ? OK : SLVERR;
                w_select_r <= w_select;
                w_state <= RWAIT; 
                w_wrotedata <= 0;
                w_wroteresp <= 0;
            end
        end
        RWAIT: begin
            if (LITE_WREADY)
                data[w_select_r] <= LITE_WDATA;
            if((w_wrotedata || LITE_WVALID) && (w_wroteresp || LITE_BREADY)) begin
                w_wrotedata <= 0;
                w_wroteresp <= 0;
                w_state <= IDLE;
            end else if (LITE_WVALID)
                w_wrotedata <= 1;
            else if (LITE_BREADY)
                w_wroteresp <= 1;
        end
    endcase
end

reg v_state;
assign CONFIG_VALID = (v_state == RWAIT);
always @(posedge ACLK) begin
    if (ARESETN == 0)
        v_state <= IDLE;
    else case(v_state)
        IDLE:
            if (LITE_WVALID && LITE_WREADY && w_select_r == 2'b00)
                v_state <= RWAIT;
        RWAIT:
            if (CONFIG_READY)
                v_state <= IDLE;
    endcase
end

assign CONFIG_CMD = data[0];
assign CONFIG_SRC = data[1];
assign CONFIG_DEST = data[2];
assign CONFIG_LEN = data[3];


//how many cycles does the operation take?
always @(posedge ACLK) begin
    if (ARESETN == 0)
        counter <= 0;
    else if (CONFIG_READY && CONFIG_VALID)
        counter <= 0;
    else if (!CONFIG_READY)
        counter <= counter + 1;
end

reg busy;
reg busy_last;
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        busy <= 0;
        busy_last <= 0;
    end else begin
        if (CONFIG_READY) begin
            busy <= CONFIG_VALID ? 1 : 0;
        end
        busy_last <= busy;
    end
end

assign CONFIG_IRQ = !busy;

endmodule // Conf

module DRAMReader(
    //AXI port
    input ACLK,
    input ARESETN,
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
    input CONFIG_VALID,
    output CONFIG_READY,
    input [31:0] CONFIG_START_ADDR,
    input [31:0] CONFIG_NBYTES,
    
    //RAM port
    input DATA_READY_DOWNSTREAM,
    output DATA_VALID,
    output [63:0] DATA
);

assign M_AXI_ARLEN = 4'b1111;
assign M_AXI_ARSIZE = 2'b11;
assign M_AXI_ARBURST = 2'b01;
parameter IDLE = 0, RWAIT = 1;
    
//ADDR logic
reg [31:0] a_count;
reg a_state;  
assign M_AXI_ARVALID = (a_state == RWAIT);
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        a_state <= IDLE;
        M_AXI_ARADDR <= 0;
        a_count <= 0;
    end else case(a_state)
        IDLE: begin
            if(CONFIG_VALID) begin
                M_AXI_ARADDR <= CONFIG_START_ADDR;
                a_count <= CONFIG_NBYTES[31:7];
                a_state <= RWAIT;
            end
        end
        RWAIT: begin
            if (M_AXI_ARREADY == 1) begin
                if(a_count - 1 == 0)
                    a_state <= IDLE;
                a_count <= a_count - 1;
                M_AXI_ARADDR <= M_AXI_ARADDR + 128; // Bursts are 128 bytes long
            end
        end
    endcase
end
    
//READ logic
reg [31:0] b_count;
reg r_state;
assign M_AXI_RREADY = (r_state == RWAIT) && DATA_READY_DOWNSTREAM;
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        r_state <= IDLE;
        b_count <= 0;
    end else case(r_state)
        IDLE: begin
            if(CONFIG_VALID) begin
                b_count <= {CONFIG_NBYTES[31:7],7'b0}; // round to nearest 128 bytes
                r_state <= RWAIT;
            end
        end
        RWAIT: begin
            if (M_AXI_RVALID && DATA_READY_DOWNSTREAM) begin
                //use M_AXI_RDATA
                if(b_count - 8 == 0)
                    r_state <= IDLE;
                b_count <= b_count - 8; // each valid cycle the bus provides 8 bytes
            end
        end
    endcase
end

assign DATA = M_AXI_RDATA;
assign DATA_VALID = M_AXI_RVALID && (r_state == RWAIT);
assign CONFIG_READY = (r_state == IDLE) && (a_state == IDLE);

endmodule // DRAMReader

module DRAMWriter(
    //AXI port
    input ACLK,
    input ARESETN,
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
    input CONFIG_VALID,
    output CONFIG_READY,
    input [31:0] CONFIG_START_ADDR,
    input [31:0] CONFIG_NBYTES,
    
    //RAM port
    input [63:0] DATA,
    output DATA_READY,
    input DATA_VALID

);

assign M_AXI_AWLEN = 4'b1111;
assign M_AXI_AWSIZE = 2'b11;
assign M_AXI_AWBURST = 2'b01;
assign M_AXI_WSTRB = 8'b11111111;

parameter IDLE = 0, RWAIT = 1;
    
//ADDR logic
reg [31:0] a_count;
reg a_state;  
assign M_AXI_AWVALID = (a_state == RWAIT);
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        a_state <= IDLE;
        M_AXI_AWADDR <= 0;
        a_count <= 0;
    end else case(a_state)
        IDLE: begin
            if(CONFIG_VALID) begin
                M_AXI_AWADDR <= CONFIG_START_ADDR;
                a_count <= CONFIG_NBYTES[31:7];
                a_state <= RWAIT;
            end
        end
        RWAIT: begin
            if (M_AXI_AWREADY == 1) begin
                if(a_count - 1 == 0)
                    a_state <= IDLE;
                a_count <= a_count - 1;
                M_AXI_AWADDR <= M_AXI_AWADDR + 128; 
            end
        end
    endcase
end

//WRITE logic
reg [31:0] b_count;
reg w_state;
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        w_state <= IDLE;
        b_count <= 0;
    end else case(w_state)
        IDLE: begin
            if(CONFIG_VALID) begin
                b_count <= {CONFIG_NBYTES[31:7],7'b0};
                w_state <= RWAIT;
                last_count <= 4'b1111;
            end
        end
        RWAIT: begin
            if (M_AXI_WREADY && M_AXI_WVALID) begin
                //use M_AXI_WDATA
                if(b_count - 8 == 0) begin
                    w_state <= IDLE;
                end
                last_count <= last_count - 4'b1;
                b_count <= b_count - 8;
            end
        end
    endcase
end

reg [3:0] last_count;
assign M_AXI_WLAST = last_count == 4'b0000;

assign M_AXI_WVALID = (w_state == RWAIT) && DATA_VALID;

assign DATA_READY = (w_state == RWAIT) && M_AXI_WREADY;
   
assign CONFIG_READY = (w_state == IDLE) && (a_state == IDLE);

assign M_AXI_BREADY = 1;

assign M_AXI_WDATA = DATA;

endmodule // DRAMWriter

//-----------------------------------------------------------------------------
// system.v
//-----------------------------------------------------------------------------

// The axi bus expects the number of valid data items to exactly match the # of addresses we send.
// This module checks for underflow (too few valid data items). If there are too few, it inserts DEADBEEFs to make it correct.
// lengthOutput is in bytes
module UnderflowShim(input CLK, input RST, input [31:0] lengthOutput, input [63:0] inp, input inp_valid, output [63:0] out, output out_valid);
   parameter WAIT_CYCLES = 2048;
   
   reg [31:0] outCnt;
   reg [31:0] outLen;

   reg        fixupMode;
   reg [31:0]  outClks = 0;
   
   
   always@(posedge CLK) begin
     if (RST) begin 
        outCnt <= 32'd0;
        outLen <= lengthOutput;
        fixupMode <= 1'b0;
        outClks <= 32'd0;
     end else begin
        outClks <= outClks + 32'd1;
        
        if(inp_valid || fixupMode) begin outCnt <= outCnt+32'd8; end // AXI does 8 bytes per clock
        if(outClks > WAIT_CYCLES) begin fixupMode <= 1'b1; end
     end
   end

   assign out = (fixupMode)?(64'hDEAD):(inp);
   assign out_valid = (RST)?(1'b0):((fixupMode)?(outCnt<outLen):(inp_valid));
endmodule

module stage
  (
    inout [53:0] MIO,
    inout PS_SRSTB,
    inout PS_CLK,
    inout PS_PORB,
    inout DDR_Clk,
    inout DDR_Clk_n,
    inout DDR_CKE,
    inout DDR_CS_n,
    inout DDR_RAS_n,
    inout DDR_CAS_n,
    output DDR_WEB,
    inout [2:0] DDR_BankAddr,
    inout [14:0] DDR_Addr,
    inout DDR_ODT,
    inout DDR_DRSTB,
    inout [31:0] DDR_DQ,
    inout [3:0] DDR_DM,
    inout [3:0] DDR_DQS,
    inout [3:0] DDR_DQS_n,
    inout DDR_VRN,
    inout DDR_VRP,
    output [7:0] LED
  );

  wire [3:0] fclk;
  wire [3:0] fclkresetn;
  wire FCLK0;
  BUFG bufg(.I(fclk[0]),.O(FCLK0));
  assign ARESETN = fclkresetn[0];
  
  
    wire [31:0] PS7_ARADDR;
    wire [11:0] PS7_ARID;
    wire [2:0] PS7_ARPROT;
    wire PS7_ARREADY;
    wire PS7_ARVALID;
    wire [31:0] PS7_AWADDR;
    wire [11:0] PS7_AWID;
    wire [2:0] PS7_AWPROT;
    wire PS7_AWREADY;
    wire PS7_AWVALID;
    wire [11:0] PS7_BID;
    wire PS7_BREADY;
    wire [1:0] PS7_BRESP;
    wire PS7_BVALID;
    wire [31:0] PS7_RDATA;
    wire [11:0] PS7_RID;
    wire PS7_RLAST;
    wire PS7_RREADY;
    wire [1:0] PS7_RRESP;
    wire PS7_RVALID;
    wire [31:0] PS7_WDATA;
    wire PS7_WREADY;
    wire [3:0] PS7_WSTRB;
    wire PS7_WVALID;

    wire [31:0] M_AXI_ARADDR;
    wire M_AXI_ARREADY;
    wire  M_AXI_ARVALID;
    wire [31:0] M_AXI_AWADDR;
    wire M_AXI_AWREADY;
    wire  M_AXI_AWVALID;
    wire  M_AXI_BREADY;
    wire [1:0] M_AXI_BRESP;
    wire M_AXI_BVALID;
    wire [63:0] M_AXI_RDATA;
    wire M_AXI_RREADY;
    wire [1:0] M_AXI_RRESP;
    wire M_AXI_RVALID;
    wire [63:0] M_AXI_WDATA;
    wire M_AXI_WREADY;
    wire [7:0] M_AXI_WSTRB;
    wire M_AXI_WVALID;
    wire M_AXI_RLAST;
    wire M_AXI_WLAST;
    
    wire [3:0] M_AXI_ARLEN;
    wire [1:0] M_AXI_ARSIZE;
    wire [1:0] M_AXI_ARBURST;
    
    wire [3:0] M_AXI_AWLEN;
    wire [1:0] M_AXI_AWSIZE;
    wire [1:0] M_AXI_AWBURST;
    
    wire CONFIG_VALID;
    wire [31:0] CONFIG_CMD;
    wire [31:0] CONFIG_SRC;
    wire [31:0] CONFIG_DEST;
    wire [31:0] CONFIG_LEN;
    wire CONFIG_IRQ;
  
    wire READER_READY;
    wire WRITER_READY;
    
    assign CONFIG_READY = READER_READY && WRITER_READY;
    
    Conf conf(
    .ACLK(FCLK0),
    .ARESETN(ARESETN),
    .S_AXI_ARADDR(PS7_ARADDR), 
    .S_AXI_ARID(PS7_ARID),  
    .S_AXI_ARREADY(PS7_ARREADY), 
    .S_AXI_ARVALID(PS7_ARVALID), 
    .S_AXI_AWADDR(PS7_AWADDR), 
    .S_AXI_AWID(PS7_AWID), 
    .S_AXI_AWREADY(PS7_AWREADY), 
    .S_AXI_AWVALID(PS7_AWVALID), 
    .S_AXI_BID(PS7_BID), 
    .S_AXI_BREADY(PS7_BREADY), 
    .S_AXI_BRESP(PS7_BRESP), 
    .S_AXI_BVALID(PS7_BVALID), 
    .S_AXI_RDATA(PS7_RDATA), 
    .S_AXI_RID(PS7_RID), 
    .S_AXI_RLAST(PS7_RLAST), 
    .S_AXI_RREADY(PS7_RREADY), 
    .S_AXI_RRESP(PS7_RRESP), 
    .S_AXI_RVALID(PS7_RVALID), 
    .S_AXI_WDATA(PS7_WDATA), 
    .S_AXI_WREADY(PS7_WREADY), 
    .S_AXI_WSTRB(PS7_WSTRB), 
    .S_AXI_WVALID(PS7_WVALID),
    .CONFIG_VALID(CONFIG_VALID),
    .CONFIG_READY(CONFIG_READY),
    .CONFIG_CMD(CONFIG_CMD),
    .CONFIG_SRC(CONFIG_SRC),
    .CONFIG_DEST(CONFIG_DEST),
    .CONFIG_LEN(CONFIG_LEN),
    .CONFIG_IRQ(CONFIG_IRQ));

   // lengthInput/lengthOutput are in bytes
   wire [31:0] lengthInput;
   assign lengthInput = {4'b0000,CONFIG_LEN[27:0]};
   wire [31:0] lengthOutput;
   assign lengthOutput = (CONFIG_LEN[27:0] << 8'd8) >> CONFIG_LEN[31:28];

   reg [31:0]  clkcnt = 0;
//   assign LED = clkcnt[20:13];
   assign  LED = clkcnt[28:21];
   
  always @(posedge FCLK0) begin
//    if(ARESETN == 0)
//        LED <= 0;
//    else if(CONFIG_VALID)
//        LED <= {CONFIG_CMD[1:0],CONFIG_SRC[2:0],CONFIG_DEST[2:0]};
     clkcnt <= clkcnt+1;

  end

  wire [63:0] pipelineInput;
  wire       pipelineInputValid;
   
  wire [64:0] pipelineOutputPacked;
  wire [63:0] pipelineOutput;
  assign pipelineOutput = pipelineOutputPacked[63:0];   
  wire pipelineOutputValid;
  assign pipelineOutputValid = pipelineOutputPacked[64];
   
  wire       pipelineReady;
  wire      downstreamReady;

  
    
  harnessaxi  #(.INPUT_COUNT(76800),.OUTPUT_COUNT(153600)) pipeline(.CLK(FCLK0),.reset(CONFIG_READY),.ready(pipelineReady),.ready_downstream(downstreamReady),.process_input({pipelineInputValid,pipelineInput}),.process_output(pipelineOutputPacked));

//   UnderflowShim #(.WAIT_CYCLES(77824)) OS(.CLK(FCLK0),.RST(CONFIG_READY),.lengthOutput(lengthOutput),.inp(pipelineOutputPacked[63:0]),.inp_valid(pipelineOutputPacked[64]),.out(pipelineOutput),.out_valid(pipelineOutputValid));
   
  DRAMReader reader(
    .ACLK(FCLK0),
    .ARESETN(ARESETN),
    .M_AXI_ARADDR(M_AXI_ARADDR),
    .M_AXI_ARREADY(M_AXI_ARREADY),
    .M_AXI_ARVALID(M_AXI_ARVALID),
    .M_AXI_RDATA(M_AXI_RDATA),
    .M_AXI_RREADY(M_AXI_RREADY),
    .M_AXI_RRESP(M_AXI_RRESP),
    .M_AXI_RVALID(M_AXI_RVALID),
    .M_AXI_RLAST(M_AXI_RLAST),
    .M_AXI_ARLEN(M_AXI_ARLEN),
    .M_AXI_ARSIZE(M_AXI_ARSIZE),
    .M_AXI_ARBURST(M_AXI_ARBURST),
    
    .CONFIG_VALID(CONFIG_VALID),
    .CONFIG_READY(READER_READY),
    .CONFIG_START_ADDR(CONFIG_SRC),
    .CONFIG_NBYTES(614400),

    .DATA_READY_DOWNSTREAM(pipelineReady),
    .DATA_VALID(pipelineInputValid),
    .DATA(pipelineInput)
  );
  
  DRAMWriter writer(
    .ACLK(FCLK0),
    .ARESETN(ARESETN),
    .M_AXI_AWADDR(M_AXI_AWADDR),
    .M_AXI_AWREADY(M_AXI_AWREADY),
    .M_AXI_AWVALID(M_AXI_AWVALID),
    .M_AXI_WDATA(M_AXI_WDATA),
    .M_AXI_WREADY(M_AXI_WREADY),
    .M_AXI_WVALID(M_AXI_WVALID),
    .M_AXI_WLAST(M_AXI_WLAST),
    .M_AXI_WSTRB(M_AXI_WSTRB),
    
    .M_AXI_BRESP(M_AXI_BRESP),
    .M_AXI_BREADY(M_AXI_BREADY),
    .M_AXI_BVALID(M_AXI_BVALID),
    
    .M_AXI_AWLEN(M_AXI_AWLEN),
    .M_AXI_AWSIZE(M_AXI_AWSIZE),
    .M_AXI_AWBURST(M_AXI_AWBURST),
    
    .CONFIG_VALID(CONFIG_VALID),
    .CONFIG_READY(WRITER_READY),
    .CONFIG_START_ADDR(CONFIG_DEST),
    .CONFIG_NBYTES(1228800),

    .DATA_READY(downstreamReady),
    .DATA_VALID(pipelineOutputValid),
    .DATA(pipelineOutput)
  );

  PS7 ps7_0(
    .DMA0DATYPE(), 	// out std_logic_vector(1 downto 0);
    .DMA0DAVALID(), 	// out std_ulogic;
    .DMA0DRREADY(), 	// out std_ulogic;
    .DMA0RSTN(), 	// out std_ulogic;
    .DMA1DATYPE(), 	// out std_logic_vector(1 downto 0);
    .DMA1DAVALID(), 	// out std_ulogic;
    .DMA1DRREADY(), 	// out std_ulogic;
    .DMA1RSTN(), 	// out std_ulogic;
    .DMA2DATYPE(), 	// out std_logic_vector(1 downto 0);
    .DMA2DAVALID(), 	// out std_ulogic;
    .DMA2DRREADY(), 	// out std_ulogic;
    .DMA2RSTN(), 	// out std_ulogic;
    .DMA3DATYPE(), 	// out std_logic_vector(1 downto 0);
    .DMA3DAVALID(), 	// out std_ulogic;
    .DMA3DRREADY(), 	// out std_ulogic;
    .DMA3RSTN(), 	// out std_ulogic;
    .EMIOCAN0PHYTX(), 	// out std_ulogic;
    .EMIOCAN1PHYTX(), 	// out std_ulogic;
    .EMIOENET0GMIITXD(), 	// out std_logic_vector(7 downto 0);
    .EMIOENET0GMIITXEN(), 	// out std_ulogic;
    .EMIOENET0GMIITXER(), 	// out std_ulogic;
    .EMIOENET0MDIOMDC(), 	// out std_ulogic;
    .EMIOENET0MDIOO(), 	// out std_ulogic;
    .EMIOENET0MDIOTN(), 	// out std_ulogic;
    .EMIOENET0PTPDELAYREQRX(), 	// out std_ulogic;
    .EMIOENET0PTPDELAYREQTX(), 	// out std_ulogic;
    .EMIOENET0PTPPDELAYREQRX(), 	// out std_ulogic;
    .EMIOENET0PTPPDELAYREQTX(), 	// out std_ulogic;
    .EMIOENET0PTPPDELAYRESPRX(), 	// out std_ulogic;
    .EMIOENET0PTPPDELAYRESPTX(), 	// out std_ulogic;
    .EMIOENET0PTPSYNCFRAMERX(), 	// out std_ulogic;
    .EMIOENET0PTPSYNCFRAMETX(), 	// out std_ulogic;
    .EMIOENET0SOFRX(), 	// out std_ulogic;
    .EMIOENET0SOFTX(), 	// out std_ulogic;
    .EMIOENET1GMIITXD(), 	// out std_logic_vector(7 downto 0);
    .EMIOENET1GMIITXEN(), 	// out std_ulogic;
    .EMIOENET1GMIITXER(), 	// out std_ulogic;
    .EMIOENET1MDIOMDC(), 	// out std_ulogic;
    .EMIOENET1MDIOO(), 	// out std_ulogic;
    .EMIOENET1MDIOTN(), 	// out std_ulogic;
    .EMIOENET1PTPDELAYREQRX(), 	// out std_ulogic;
    .EMIOENET1PTPDELAYREQTX(), 	// out std_ulogic;
    .EMIOENET1PTPPDELAYREQRX(), 	// out std_ulogic;
    .EMIOENET1PTPPDELAYREQTX(), 	// out std_ulogic;
    .EMIOENET1PTPPDELAYRESPRX(), 	// out std_ulogic;
    .EMIOENET1PTPPDELAYRESPTX(), 	// out std_ulogic;
    .EMIOENET1PTPSYNCFRAMERX(), 	// out std_ulogic;
    .EMIOENET1PTPSYNCFRAMETX(), 	// out std_ulogic;
    .EMIOENET1SOFRX(), 	// out std_ulogic;
    .EMIOENET1SOFTX(), 	// out std_ulogic;
    .EMIOGPIOO(), 	 // out std_logic_vector(63 downto 0);
    .EMIOGPIOTN(),  // out std_logic_vector(63 downto 0);
    .EMIOI2C0SCLO(), 	 // out std_ulogic;
    .EMIOI2C0SCLTN(),  // out std_ulogic;
    .EMIOI2C0SDAO(), 	 // out std_ulogic;
    .EMIOI2C0SDATN(),  // out std_ulogic;
    .EMIOI2C1SCLO(), 	 // out std_ulogic;
    .EMIOI2C1SCLTN(),  // out std_ulogic;
    .EMIOI2C1SDAO(), 	 // out std_ulogic;
    .EMIOI2C1SDATN(),  // out std_ulogic;
    .EMIOPJTAGTDO(), 	// out std_ulogic;
    .EMIOPJTAGTDTN(), 	// out std_ulogic;
    .EMIOSDIO0BUSPOW(), 	// out std_ulogic;
    .EMIOSDIO0BUSVOLT(), 	// out std_logic_vector(2 downto 0);
    .EMIOSDIO0CLK(), 	// out std_ulogic;
    .EMIOSDIO0CMDO(), 	// out std_ulogic;
    .EMIOSDIO0CMDTN(), 	// out std_ulogic;
    .EMIOSDIO0DATAO(), 	// out std_logic_vector(3 downto 0);
    .EMIOSDIO0DATATN(), 	// out std_logic_vector(3 downto 0);
    .EMIOSDIO0LED(), 	// out std_ulogic;
    .EMIOSDIO1BUSPOW(), 	// out std_ulogic;
    .EMIOSDIO1BUSVOLT(), 	// out std_logic_vector(2 downto 0);
    .EMIOSDIO1CLK(), 	// out std_ulogic;
    .EMIOSDIO1CMDO(), 	// out std_ulogic;
    .EMIOSDIO1CMDTN(), 	// out std_ulogic;
    .EMIOSDIO1DATAO(), 	// out std_logic_vector(3 downto 0);
    .EMIOSDIO1DATATN(), 	// out std_logic_vector(3 downto 0);
    .EMIOSDIO1LED(), 	// out std_ulogic;
    .EMIOSPI0MO(), 	// out std_ulogic;
    .EMIOSPI0MOTN(), 	// out std_ulogic;
    .EMIOSPI0SCLKO(), 	// out std_ulogic;
    .EMIOSPI0SCLKTN(), 	// out std_ulogic;
    .EMIOSPI0SO(), 	// out std_ulogic;
    .EMIOSPI0SSNTN(), 	// out std_ulogic;
    .EMIOSPI0SSON(), 	// out std_logic_vector(2 downto 0);
    .EMIOSPI0STN(), 	// out std_ulogic;
    .EMIOSPI1MO(), 	// out std_ulogic;
    .EMIOSPI1MOTN(), 	// out std_ulogic;
    .EMIOSPI1SCLKO(), 	// out std_ulogic;
    .EMIOSPI1SCLKTN(), 	// out std_ulogic;
    .EMIOSPI1SO(), 	// out std_ulogic;
    .EMIOSPI1SSNTN(), 	// out std_ulogic;
    .EMIOSPI1SSON(), 	// out std_logic_vector(2 downto 0);
    .EMIOSPI1STN(), 	// out std_ulogic;
    .EMIOTRACECTL(), 	// out std_ulogic;
    .EMIOTRACEDATA(), 	// out std_logic_vector(31 downto 0);
    .EMIOTTC0WAVEO(), 	// out std_logic_vector(2 downto 0);
    .EMIOTTC1WAVEO(), 	// out std_logic_vector(2 downto 0);
    .EMIOUART0DTRN(), 	// out std_ulogic;
    .EMIOUART0RTSN(), 	// out std_ulogic;
    .EMIOUART0TX(), 	// out std_ulogic;
    .EMIOUART1DTRN(), 	// out std_ulogic;
    .EMIOUART1RTSN(), 	// out std_ulogic;
    .EMIOUART1TX(), 	// out std_ulogic;
    .EMIOUSB0PORTINDCTL(), 	// out std_logic_vector(1 downto 0);
    .EMIOUSB0VBUSPWRSELECT(), 	// out std_ulogic;
    .EMIOUSB1PORTINDCTL(), 	// out std_logic_vector(1 downto 0);
    .EMIOUSB1VBUSPWRSELECT(), 	// out std_ulogic;
    .EMIOWDTRSTO(), 	// out std_ulogic;
    .EVENTEVENTO(), 	// out std_ulogic;
    .EVENTSTANDBYWFE(), 	// out std_logic_vector(1 downto 0);
    .EVENTSTANDBYWFI(), 	// out std_logic_vector(1 downto 0);
    .FCLKCLK(fclk), 	 // out std_logic_vector(3 downto 0);
    .FCLKRESETN(fclkresetn), 	// out std_logic_vector(3 downto 0);
    .FTMTF2PTRIGACK(), 	// out std_logic_vector(3 downto 0);
    .FTMTP2FDEBUG(), 	// out std_logic_vector(31 downto 0);
    .FTMTP2FTRIG(), 	// out std_logic_vector(3 downto 0);
    .IRQP2F(), 	// out std_logic_vector(28 downto 0);
    
    .MAXIGP0ACLK(FCLK0), 	// in std_ulogic;
    .MAXIGP0ARADDR(PS7_ARADDR),  // out std_logic_vector(31 downto 0);
    .MAXIGP0ARBURST(),  // out std_logic_vector(1 downto 0);
    .MAXIGP0ARCACHE(),  // out std_logic_vector(3 downto 0);
    .MAXIGP0ARESETN(),  // out std_ulogic;
    .MAXIGP0ARID(PS7_ARID), 	 // out std_logic_vector(11 downto 0);
    .MAXIGP0ARLEN(),  // out std_logic_vector(3 downto 0);
    .MAXIGP0ARLOCK(),  // out std_logic_vector(1 downto 0);
    .MAXIGP0ARPROT(),  // out std_logic_vector(2 downto 0);
    .MAXIGP0ARQOS(),  // out std_logic_vector(3 downto 0);
    .MAXIGP0ARREADY(PS7_ARREADY), // in std_ulogic;
    .MAXIGP0ARSIZE(),  // out std_logic_vector(1 downto 0);
    .MAXIGP0ARVALID(PS7_ARVALID),  // out std_ulogic;
    .MAXIGP0AWADDR(PS7_AWADDR),  // out std_logic_vector(31 downto 0);
    .MAXIGP0AWBURST(),  // out std_logic_vector(1 downto 0);
    .MAXIGP0AWCACHE(),  // out std_logic_vector(3 downto 0);
    .MAXIGP0AWID(PS7_AWID), 	 // out std_logic_vector(11 downto 0);
    .MAXIGP0AWLEN(),  // out std_logic_vector(3 downto 0);
    .MAXIGP0AWLOCK(),  // out std_logic_vector(1 downto 0);
    .MAXIGP0AWPROT(),  // out std_logic_vector(2 downto 0);
    .MAXIGP0AWQOS(),  // out std_logic_vector(3 downto 0);
    .MAXIGP0AWREADY(PS7_AWREADY), // in std_ulogic;
    .MAXIGP0AWSIZE(),  // out std_logic_vector(1 downto 0);
    .MAXIGP0AWVALID(PS7_AWVALID),  // out std_ulogic;
    .MAXIGP0BID(PS7_BID), 	// in std_logic_vector(11 downto 0);
    .MAXIGP0BREADY(PS7_BREADY),  // out std_ulogic;
    .MAXIGP0BRESP(PS7_BRESP), // in std_logic_vector(1 downto 0);
    .MAXIGP0BVALID(PS7_BVALID), // in std_ulogic;
    .MAXIGP0RDATA(PS7_RDATA), // in std_logic_vector(31 downto 0);
    .MAXIGP0RID(PS7_RID), 	// in std_logic_vector(11 downto 0);
    .MAXIGP0RLAST(PS7_RLAST), // in std_ulogic;
    .MAXIGP0RREADY(PS7_RREADY),  // out std_ulogic;
    .MAXIGP0RRESP(PS7_RRESP), // in std_logic_vector(1 downto 0);    
    .MAXIGP0RVALID(PS7_RVALID), // in std_ulogic;
    .MAXIGP0WDATA(PS7_WDATA),  // out std_logic_vector(31 downto 0);
    .MAXIGP0WID(), 	 // out std_logic_vector(11 downto 0);
    .MAXIGP0WLAST(),  // out std_ulogic;
    .MAXIGP0WREADY(PS7_WREADY), // in std_ulogic;
    .MAXIGP0WSTRB(PS7_WSTRB),  // out std_logic_vector(3 downto 0);
    .MAXIGP0WVALID(PS7_WVALID),  // out std_ulogic;
    
    .MAXIGP1ARADDR(),  // out std_logic_vector(31 downto 0);
    .MAXIGP1ARBURST(),  // out std_logic_vector(1 downto 0);
    .MAXIGP1ARCACHE(),  // out std_logic_vector(3 downto 0);
    .MAXIGP1ARESETN(),  // out std_ulogic;
    .MAXIGP1ARID(), 	 // out std_logic_vector(11 downto 0);
    .MAXIGP1ARLEN(),  // out std_logic_vector(3 downto 0);
    .MAXIGP1ARLOCK(),  // out std_logic_vector(1 downto 0);
    .MAXIGP1ARPROT(),  // out std_logic_vector(2 downto 0);
    .MAXIGP1ARQOS(),  // out std_logic_vector(3 downto 0);
    .MAXIGP1ARSIZE(),  // out std_logic_vector(1 downto 0);
    .MAXIGP1ARVALID(),  // out std_ulogic;
    .MAXIGP1AWADDR(),  // out std_logic_vector(31 downto 0);
    .MAXIGP1AWBURST(),  // out std_logic_vector(1 downto 0);
    .MAXIGP1AWCACHE(),  // out std_logic_vector(3 downto 0);
    .MAXIGP1AWID(), 	 // out std_logic_vector(11 downto 0);
    .MAXIGP1AWLEN(),  // out std_logic_vector(3 downto 0);
    .MAXIGP1AWLOCK(),  // out std_logic_vector(1 downto 0);
    .MAXIGP1AWPROT(),  // out std_logic_vector(2 downto 0);
    .MAXIGP1AWQOS(),  // out std_logic_vector(3 downto 0);
    .MAXIGP1AWSIZE(),  // out std_logic_vector(1 downto 0);
    .MAXIGP1AWVALID(),  // out std_ulogic;
    .MAXIGP1BREADY(),  // out std_ulogic;
    .MAXIGP1RREADY(),  // out std_ulogic;
    .MAXIGP1WDATA(),  // out std_logic_vector(31 downto 0);
    .MAXIGP1WID(), 	 // out std_logic_vector(11 downto 0);
    .MAXIGP1WLAST(),  // out std_ulogic;
    .MAXIGP1WSTRB(),  // out std_logic_vector(3 downto 0);
    .MAXIGP1WVALID(),  // out std_ulogic;
    .SAXIGP0ARESETN(), 	// out std_ulogic;
    .SAXIGP0ARREADY(), 	// out std_ulogic;
    .SAXIGP0AWREADY(), 	// out std_ulogic;
    .SAXIGP0BID(), 	// out std_logic_vector(5 downto 0);
    .SAXIGP0BRESP(), 	// out std_logic_vector(1 downto 0);
    .SAXIGP0BVALID(), 	// out std_ulogic;
    .SAXIGP0RDATA(), 	// out std_logic_vector(31 downto 0);
    .SAXIGP0RID(), 	// out std_logic_vector(5 downto 0);
    .SAXIGP0RLAST(), 	// out std_ulogic;
    .SAXIGP0RRESP(), 	// out std_logic_vector(1 downto 0);
    .SAXIGP0RVALID(), 	// out std_ulogic;
    .SAXIGP0WREADY(), 	// out std_ulogic;
    .SAXIGP1ARESETN(), 	// out std_ulogic;
    .SAXIGP1ARREADY(), 	// out std_ulogic;
    .SAXIGP1AWREADY(), 	// out std_ulogic;
    .SAXIGP1BID(), 	// out std_logic_vector(5 downto 0);
    .SAXIGP1BRESP(), 	// out std_logic_vector(1 downto 0);
    .SAXIGP1BVALID(), 	// out std_ulogic;
    .SAXIGP1RDATA(), 	// out std_logic_vector(31 downto 0);
    .SAXIGP1RID(), 	// out std_logic_vector(5 downto 0);
    .SAXIGP1RLAST(), 	// out std_ulogic;
    .SAXIGP1RRESP(), 	// out std_logic_vector(1 downto 0);
    .SAXIGP1RVALID(), 	// out std_ulogic;
    .SAXIGP1WREADY(), 	// out std_ulogic;
    
    
    
    .SAXIHP0ACLK(1'b0), 		// in std_ulogic;
    .SAXIHP0ARADDR(32'b0),	// in std_logic_vector(31 downto 0);
    .SAXIHP0ARBURST(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIHP0ARCACHE(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIHP0ARESETN(), 	// out std_ulogic;
    .SAXIHP0ARID(6'b0),	// in std_logic_vector(2 downto 0);
    .SAXIHP0ARLEN(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIHP0ARLOCK(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIHP0ARPROT(3'b0),	// in std_logic_vector(2 downto 0);
    .SAXIHP0ARQOS(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIHP0ARREADY(), 	// out std_ulogic;
    .SAXIHP0ARSIZE(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIHP0ARVALID(1'b0), 		// in std_ulogic;
    .SAXIHP0AWADDR(32'b0),	// in std_logic_vector(31 downto 0);
    .SAXIHP0AWBURST(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIHP0AWCACHE(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIHP0AWID(6'b0),	// in std_logic_vector(2 downto 0);
    .SAXIHP0AWLEN(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIHP0AWLOCK(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIHP0AWPROT(3'b0),	// in std_logic_vector(2 downto 0);
    .SAXIHP0AWQOS(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIHP0AWREADY(), 	// out std_ulogic;
    .SAXIHP0AWSIZE(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIHP0AWVALID(1'b0), 		// in std_ulogic;
    .SAXIHP0BID(), 	// out std_logic_vector(2 downto 0);
    .SAXIHP0BREADY(1'b0), 		// in std_ulogic;
    .SAXIHP0BRESP(), 	// out std_logic_vector(1 downto 0);
    .SAXIHP0BVALID(), 	// out std_ulogic;
    .SAXIHP0RDATA(), 	// out std_logic_vector(63 downto 0);
    .SAXIHP0RID(), 	// out std_logic_vector(2 downto 0);
    .SAXIHP0RLAST(), 	// out std_ulogic;
    .SAXIHP0RREADY(1'b0), 		// in std_ulogic;
    .SAXIHP0RRESP(), 	// out std_logic_vector(1 downto 0);
    .SAXIHP0RVALID(), 	// out std_ulogic;
    .SAXIHP0WDATA(64'b0),	// in std_logic_vector(63 downto 0);
    .SAXIHP0WID(6'b0),	// in std_logic_vector(2 downto 0);
    .SAXIHP0WLAST(1'b0), 		// in std_ulogic;
    .SAXIHP0WREADY(), 	// out std_ulogic;
    .SAXIHP0WSTRB(8'b0),	// in std_logic_vector(7 downto 0);
    .SAXIHP0WVALID(1'b0), 		// in std_ulogic;
    
    .SAXIACPARUSER(5'b0),	// in std_logic_vector(4 downto 0);
    .SAXIACPAWUSER(5'b0),	// in std_logic_vector(4 downto 0);
    
    .SAXIACPACLK(FCLK0), 	// in std_ulogic;
    .SAXIACPARADDR(M_AXI_ARADDR),
    .SAXIACPARBURST(M_AXI_ARBURST), // in std_logic_vector(1 downto 0);
    .SAXIACPARCACHE(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIACPARESETN(),  // out std_ulogic;
    .SAXIACPARID(3'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIACPARLEN(M_AXI_ARLEN), // in std_logic_vector(3 downto 0);
    .SAXIACPARLOCK(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIACPARPROT(3'b0), // in std_logic_vector(2 downto 0);
    .SAXIACPARQOS(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIACPARREADY(M_AXI_ARREADY),
    .SAXIACPARSIZE(M_AXI_ARSIZE), // in std_logic_vector(1 downto 0);
    .SAXIACPARVALID(M_AXI_ARVALID),
    .SAXIACPAWADDR(M_AXI_AWADDR),
    .SAXIACPAWBURST(M_AXI_AWBURST), // in std_logic_vector(1 downto 0);
    .SAXIACPAWCACHE(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIACPAWID(3'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIACPAWLEN(M_AXI_AWLEN), // in std_logic_vector(3 downto 0);
    .SAXIACPAWLOCK(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIACPAWPROT(3'b0), // in std_logic_vector(2 downto 0);
    .SAXIACPAWQOS(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIACPAWREADY(M_AXI_AWREADY),
    .SAXIACPAWSIZE(M_AXI_AWSIZE), // in std_logic_vector(1 downto 0);
    .SAXIACPAWVALID(M_AXI_AWVALID),
    .SAXIACPBID(), 	 // out std_logic_vector(5 downto 0);
    .SAXIACPBREADY(M_AXI_BREADY),
    .SAXIACPBRESP(M_AXI_BRESP),
    .SAXIACPBVALID(M_AXI_BVALID),
    .SAXIACPRDATA(M_AXI_RDATA),
    .SAXIACPRID(), 	 // out std_logic_vector(5 downto 0);
    .SAXIACPRLAST(M_AXI_RLAST),  // out std_ulogic;
    .SAXIACPRREADY(M_AXI_RREADY),
    .SAXIACPRRESP(M_AXI_RRESP),
    .SAXIACPRVALID(M_AXI_RVALID),
    .SAXIACPWDATA(M_AXI_WDATA),
    .SAXIACPWID(3'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIACPWLAST(M_AXI_WLAST), // in std_ulogic;
    .SAXIACPWREADY(M_AXI_WREADY),
    .SAXIACPWSTRB(M_AXI_WSTRB),
    .SAXIACPWVALID(M_AXI_WVALID),
    
    .SAXIHP0RDISSUECAP1EN(1'b0), 		// in std_ulogic;
    .SAXIHP0WRISSUECAP1EN(1'b0), 		// in std_ulogic;
    .SAXIHP0RACOUNT(),  // out std_logic_vector(2 downto 0);
    .SAXIHP0RCOUNT(),  // out std_logic_vector(7 downto 0);
    .SAXIHP0WACOUNT(),  // out std_logic_vector(5 downto 0);
    .SAXIHP0WCOUNT(),  // out std_logic_vector(7 downto 0);
    
    .SAXIHP1ARESETN(),  // out std_ulogic;
    .SAXIHP1ARREADY(),  // out std_ulogic;
    .SAXIHP1AWREADY(),  // out std_ulogic;
    .SAXIHP1BID(), 	 // out std_logic_vector(5 downto 0);
    .SAXIHP1BRESP(),  // out std_logic_vector(1 downto 0);
    .SAXIHP1BVALID(),  // out std_ulogic;
    .SAXIHP1RACOUNT(),  // out std_logic_vector(2 downto 0);
    .SAXIHP1RCOUNT(),  // out std_logic_vector(7 downto 0);
    .SAXIHP1RDATA(),  // out std_logic_vector(63 downto 0);
    .SAXIHP1RID(), 	 // out std_logic_vector(5 downto 0);
    .SAXIHP1RLAST(),  // out std_ulogic;
    .SAXIHP1RRESP(),  // out std_logic_vector(1 downto 0);
    .SAXIHP1RVALID(),  // out std_ulogic;
    .SAXIHP1WACOUNT(),  // out std_logic_vector(5 downto 0);
    .SAXIHP1WCOUNT(),  // out std_logic_vector(7 downto 0);
    .SAXIHP1WREADY(),  // out std_ulogic;
    .SAXIHP2ARESETN(),  // out std_ulogic;
    .SAXIHP2ARREADY(),  // out std_ulogic;
    .SAXIHP2AWREADY(),  // out std_ulogic;
    .SAXIHP2BID(), 	 // out std_logic_vector(5 downto 0);
    .SAXIHP2BRESP(),  // out std_logic_vector(1 downto 0);
    .SAXIHP2BVALID(),  // out std_ulogic;
    .SAXIHP2RACOUNT(),  // out std_logic_vector(2 downto 0);
    .SAXIHP2RCOUNT(),  // out std_logic_vector(7 downto 0);
    .SAXIHP2RDATA(),  // out std_logic_vector(63 downto 0);
    .SAXIHP2RID(), 	 // out std_logic_vector(5 downto 0);
    .SAXIHP2RLAST(),  // out std_ulogic;
    .SAXIHP2RRESP(),  // out std_logic_vector(1 downto 0);
    .SAXIHP2RVALID(),  // out std_ulogic;
    .SAXIHP2WACOUNT(),  // out std_logic_vector(5 downto 0);
    .SAXIHP2WCOUNT(),  // out std_logic_vector(7 downto 0);
    .SAXIHP2WREADY(),  // out std_ulogic;
    .SAXIHP3ARESETN(),  // out std_ulogic;
    .SAXIHP3ARREADY(),  // out std_ulogic;
    .SAXIHP3AWREADY(),  // out std_ulogic;
    .SAXIHP3BID(), 	 // out std_logic_vector(5 downto 0);
    .SAXIHP3BRESP(),  // out std_logic_vector(1 downto 0);
    .SAXIHP3BVALID(),  // out std_ulogic;
    .SAXIHP3RACOUNT(),  // out std_logic_vector(2 downto 0);
    .SAXIHP3RCOUNT(),  // out std_logic_vector(7 downto 0);
    .SAXIHP3RDATA(),  // out std_logic_vector(63 downto 0);
    .SAXIHP3RID(), 	 // out std_logic_vector(5 downto 0);
    .SAXIHP3RLAST(),  // out std_ulogic;
    .SAXIHP3RRESP(),  // out std_logic_vector(1 downto 0);
    .SAXIHP3RVALID(),  // out std_ulogic;
    .SAXIHP3WACOUNT(),  // out std_logic_vector(5 downto 0);
    .SAXIHP3WCOUNT(),  // out std_logic_vector(7 downto 0);
    .SAXIHP3WREADY(),  // out std_ulogic;
    .DDRA(DDR_Addr), 	// inout std_logic_vector(14 downto 0);
    .DDRBA(DDR_BankAddr), // inout std_logic_vector(2 downto 0);
    .DDRCASB(DDR_CAS_n), 	// inout std_ulogic;
    .DDRCKE(DDR_CKE), 	// inout std_ulogic;
    .DDRCKN(DDR_Clk_n), 	// inout std_ulogic;
    .DDRCKP(DDR_Clk), 	// inout std_ulogic;
    .DDRCSB(DDR_CS_n), 	// inout std_ulogic;
    .DDRDM(DDR_DM), 	// inout std_logic_vector(3 downto 0);
    .DDRDQ(DDR_DQ), 	// inout std_logic_vector(31 downto 0);
    .DDRDQSN(DDR_DQS_n), 	// inout std_logic_vector(3 downto 0);
    .DDRDQSP(DDR_DQS), 	// inout std_logic_vector(3 downto 0);
    .DDRDRSTB(DDR_DRSTB), 	// inout std_ulogic;
    .DDRODT(DDR_ODT), 	// inout std_ulogic;
    .DDRRASB(DDR_RAS_n), 	// inout std_ulogic;
    .DDRVRN(DDR_VRN), 	// inout std_ulogic;
    .DDRVRP(DDR_VRP), 	// inout std_ulogic;
    .DDRWEB(DDR_WEB), 	// inout std_ulogic;
    .MIO(MIO), 	// inout std_logic_vector(53 downto 0);
    .PSCLK(PS_CLK), 	// inout std_ulogic;
    .PSPORB(PS_PORB), 	// inout std_ulogic;
    .PSSRSTB(PS_SRSTB), 	// inout std_ulogic;
    .DDRARB(4'b0),	// in std_logic_vector(3 downto 0);
    .DMA0ACLK(1'b0), 		// in std_ulogic;
    .DMA0DAREADY(1'b0), 		// in std_ulogic;
    .DMA0DRLAST(1'b0), 		// in std_ulogic;
    .DMA0DRTYPE(2'b0),	// in std_logic_vector(1 downto 0);
    .DMA0DRVALID(1'b0), 		// in std_ulogic;
    .DMA1ACLK(1'b0), 		// in std_ulogic;
    .DMA1DAREADY(1'b0), 		// in std_ulogic;
    .DMA1DRLAST(1'b0), 		// in std_ulogic;
    .DMA1DRTYPE(2'b0),	// in std_logic_vector(1 downto 0);
    .DMA1DRVALID(1'b0), 		// in std_ulogic;
    .DMA2ACLK(1'b0), 		// in std_ulogic;
    .DMA2DAREADY(1'b0), 		// in std_ulogic;
    .DMA2DRLAST(1'b0), 		// in std_ulogic;
    .DMA2DRTYPE(2'b0),	// in std_logic_vector(1 downto 0);
    .DMA2DRVALID(1'b0), 		// in std_ulogic;
    .DMA3ACLK(1'b0), 		// in std_ulogic;
    .DMA3DAREADY(1'b0), 		// in std_ulogic;
    .DMA3DRLAST(1'b0), 		// in std_ulogic;
    .DMA3DRTYPE(2'b0),	// in std_logic_vector(1 downto 0);
    .DMA3DRVALID(1'b0), 		// in std_ulogic;
    .EMIOCAN0PHYRX(1'b0), 		// in std_ulogic;
    .EMIOCAN1PHYRX(1'b0), 		// in std_ulogic;
    .EMIOENET0EXTINTIN(1'b0), 		// in std_ulogic;
    .EMIOENET0GMIICOL(1'b0), 		// in std_ulogic;
    .EMIOENET0GMIICRS(1'b0), 		// in std_ulogic;
    .EMIOENET0GMIIRXCLK(1'b0), 		// in std_ulogic;
    .EMIOENET0GMIIRXD(8'b0),	// in std_logic_vector(7 downto 0);
    .EMIOENET0GMIIRXDV(1'b0), 		// in std_ulogic;
    .EMIOENET0GMIIRXER(1'b0), 		// in std_ulogic;
    .EMIOENET0GMIITXCLK(1'b0), 		// in std_ulogic;
    .EMIOENET0MDIOI(1'b0), 		// in std_ulogic;
    .EMIOENET1EXTINTIN(1'b0), 		// in std_ulogic;
    .EMIOENET1GMIICOL(1'b0), 		// in std_ulogic;
    .EMIOENET1GMIICRS(1'b0), 		// in std_ulogic;
    .EMIOENET1GMIIRXCLK(1'b0), 		// in std_ulogic;
    .EMIOENET1GMIIRXD(8'b0),	// in std_logic_vector(7 downto 0);
    .EMIOENET1GMIIRXDV(1'b0), 		// in std_ulogic;
    .EMIOENET1GMIIRXER(1'b0), 		// in std_ulogic;
    .EMIOENET1GMIITXCLK(1'b0), 		// in std_ulogic;
    .EMIOENET1MDIOI(1'b0), 		// in std_ulogic;
    .EMIOGPIOI(64'b0), 	// in std_logic_vector(63 downto 0);
    .EMIOI2C0SCLI(1'b0), 	// in std_ulogic;
    .EMIOI2C0SDAI(1'b0), 	// in std_ulogic;
    .EMIOI2C1SCLI(1'b0), 	// in std_ulogic;
    .EMIOI2C1SDAI(1'b0), 	// in std_ulogic;
    .EMIOPJTAGTCK(1'b0), 		// in std_ulogic;
    .EMIOPJTAGTDI(1'b0), 		// in std_ulogic;
    .EMIOPJTAGTMS(1'b0), 		// in std_ulogic;
    .EMIOSDIO0CDN(1'b0), 		// in std_ulogic;
    .EMIOSDIO0CLKFB(1'b0), 		// in std_ulogic;
    .EMIOSDIO0CMDI(1'b0), 		// in std_ulogic;
    .EMIOSDIO0DATAI(4'b0),	// in std_logic_vector(3 downto 0);
    .EMIOSDIO0WP(1'b0), 		// in std_ulogic;
    .EMIOSDIO1CDN(1'b0), 		// in std_ulogic;
    .EMIOSDIO1CLKFB(1'b0), 		// in std_ulogic;
    .EMIOSDIO1CMDI(1'b0), 		// in std_ulogic;
    .EMIOSDIO1DATAI(4'b0),	// in std_logic_vector(3 downto 0);
    .EMIOSDIO1WP(1'b0), 		// in std_ulogic;
    .EMIOSPI0MI(1'b0), 		// in std_ulogic;
    .EMIOSPI0SCLKI(1'b0), 		// in std_ulogic;
    .EMIOSPI0SI(1'b0), 		// in std_ulogic;
    .EMIOSPI0SSIN(1'b0), 		// in std_ulogic;
    .EMIOSPI1MI(1'b0), 		// in std_ulogic;
    .EMIOSPI1SCLKI(1'b0), 		// in std_ulogic;
    .EMIOSPI1SI(1'b0), 		// in std_ulogic;
    .EMIOSPI1SSIN(1'b0), 		// in std_ulogic;
    .EMIOSRAMINTIN(1'b0), 		// in std_ulogic;
    .EMIOTRACECLK(1'b0), 		// in std_ulogic;
    .EMIOTTC0CLKI(3'b0),	// in std_logic_vector(2 downto 0);
    .EMIOTTC1CLKI(3'b0),	// in std_logic_vector(2 downto 0);
    .EMIOUART0CTSN(1'b0), 		// in std_ulogic;
    .EMIOUART0DCDN(1'b0), 		// in std_ulogic;
    .EMIOUART0DSRN(1'b0), 		// in std_ulogic;
    .EMIOUART0RIN(1'b0), 		// in std_ulogic;
    .EMIOUART0RX(1'b0), 		// in std_ulogic;
    .EMIOUART1CTSN(1'b0), 		// in std_ulogic;
    .EMIOUART1DCDN(1'b0), 		// in std_ulogic;
    .EMIOUART1DSRN(1'b0), 		// in std_ulogic;
    .EMIOUART1RIN(1'b0), 		// in std_ulogic;
    .EMIOUART1RX(1'b0), 		// in std_ulogic;
    .EMIOUSB0VBUSPWRFAULT(1'b0), 		// in std_ulogic;
    .EMIOUSB1VBUSPWRFAULT(1'b0), 		// in std_ulogic;
    .EMIOWDTCLKI(1'b0), 		// in std_ulogic;
    .EVENTEVENTI(1'b0), 		// in std_ulogic;
    .FCLKCLKTRIGN(4'b0),	// in std_logic_vector(3 downto 0);
    .FPGAIDLEN(1'b0), 		// in std_ulogic;
    .FTMDTRACEINATID(4'b0),	// in std_logic_vector(3 downto 0);
    .FTMDTRACEINCLOCK(1'b0), 		// in std_ulogic;
    .FTMDTRACEINDATA(32'b0),	// in std_logic_vector(31 downto 0);
    .FTMDTRACEINVALID(1'b0), 		// in std_ulogic;
    .FTMTF2PDEBUG(32'b0),	// in std_logic_vector(31 downto 0);
    .FTMTF2PTRIG(4'b0),	// in std_logic_vector(3 downto 0);
    .FTMTP2FTRIGACK(4'b0),	// in std_logic_vector(3 downto 0);
    .IRQF2P({19'b0,CONFIG_IRQ}),	// in std_logic_vector(19 downto 0);
    .MAXIGP1ACLK(1'b0), 	// in std_ulogic;
    .MAXIGP1ARREADY(1'b0), // in std_ulogic;
    .MAXIGP1AWREADY(1'b0), // in std_ulogic;
    .MAXIGP1BID(12'b0), 	// in std_logic_vector(11 downto 0);
    .MAXIGP1BRESP(2'b0), // in std_logic_vector(1 downto 0);
    .MAXIGP1BVALID(1'b0), // in std_ulogic;
    .MAXIGP1RDATA(32'b0), // in std_logic_vector(31 downto 0);
    .MAXIGP1RID(12'b0), 	// in std_logic_vector(11 downto 0);
    .MAXIGP1RLAST(1'b0), // in std_ulogic;
    .MAXIGP1RRESP(2'b0), // in std_logic_vector(1 downto 0);
    .MAXIGP1RVALID(1'b0), // in std_ulogic;
    .MAXIGP1WREADY(1'b0), // in std_ulogic;
    .SAXIGP0ACLK(1'b0), 		// in std_ulogic;
    .SAXIGP0ARADDR(32'b0),	// in std_logic_vector(31 downto 0);
    .SAXIGP0ARBURST(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP0ARCACHE(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP0ARID(6'b0),	// in std_logic_vector(5 downto 0);
    .SAXIGP0ARLEN(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP0ARLOCK(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP0ARPROT(3'b0),	// in std_logic_vector(2 downto 0);
    .SAXIGP0ARQOS(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP0ARSIZE(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP0ARVALID(1'b0), 		// in std_ulogic;
    .SAXIGP0AWADDR(32'b0),	// in std_logic_vector(31 downto 0);
    .SAXIGP0AWBURST(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP0AWCACHE(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP0AWID(6'b0),	// in std_logic_vector(5 downto 0);
    .SAXIGP0AWLEN(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP0AWLOCK(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP0AWPROT(3'b0),	// in std_logic_vector(2 downto 0);
    .SAXIGP0AWQOS(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP0AWSIZE(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP0AWVALID(1'b0), 		// in std_ulogic;
    .SAXIGP0BREADY(1'b0), 		// in std_ulogic;
    .SAXIGP0RREADY(1'b0), 		// in std_ulogic;
    .SAXIGP0WDATA(32'b0),	// in std_logic_vector(31 downto 0);
    .SAXIGP0WID(6'b0),	// in std_logic_vector(5 downto 0);
    .SAXIGP0WLAST(1'b0), 		// in std_ulogic;
    .SAXIGP0WSTRB(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP0WVALID(1'b0), 		// in std_ulogic;
    .SAXIGP1ACLK(1'b0), 		// in std_ulogic;
    .SAXIGP1ARADDR(32'b0),	// in std_logic_vector(31 downto 0);
    .SAXIGP1ARBURST(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP1ARCACHE(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP1ARID(6'b0),	// in std_logic_vector(5 downto 0);
    .SAXIGP1ARLEN(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP1ARLOCK(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP1ARPROT(3'b0),	// in std_logic_vector(2 downto 0);
    .SAXIGP1ARQOS(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP1ARSIZE(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP1ARVALID(1'b0), 		// in std_ulogic;
    .SAXIGP1AWADDR(32'b0),	// in std_logic_vector(31 downto 0);
    .SAXIGP1AWBURST(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP1AWCACHE(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP1AWID(6'b0),	// in std_logic_vector(5 downto 0);
    .SAXIGP1AWLEN(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP1AWLOCK(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP1AWPROT(3'b0),	// in std_logic_vector(2 downto 0);
    .SAXIGP1AWQOS(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP1AWSIZE(2'b0),	// in std_logic_vector(1 downto 0);
    .SAXIGP1AWVALID(1'b0), 		// in std_ulogic;
    .SAXIGP1BREADY(1'b0), 		// in std_ulogic;
    .SAXIGP1RREADY(1'b0), 		// in std_ulogic;
    .SAXIGP1WDATA(32'b0),	// in std_logic_vector(31 downto 0);
    .SAXIGP1WID(6'b0),	// in std_logic_vector(5 downto 0);
    .SAXIGP1WLAST(1'b0), 		// in std_ulogic;
    .SAXIGP1WSTRB(4'b0),	// in std_logic_vector(3 downto 0);
    .SAXIGP1WVALID(1'b0), 		// in std_ulogic;
    .SAXIHP1ACLK(1'b0), 	// in std_ulogic;
    .SAXIHP1ARADDR(32'b0), // in std_logic_vector(31 downto 0);
    .SAXIHP1ARBURST(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP1ARCACHE(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP1ARID(6'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIHP1ARLEN(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP1ARLOCK(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP1ARPROT(3'b0), // in std_logic_vector(2 downto 0);
    .SAXIHP1ARQOS(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP1ARSIZE(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP1ARVALID(1'b0), // in std_ulogic;
    .SAXIHP1AWADDR(32'b0), // in std_logic_vector(31 downto 0);
    .SAXIHP1AWBURST(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP1AWCACHE(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP1AWID(6'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIHP1AWLEN(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP1AWLOCK(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP1AWPROT(3'b0), // in std_logic_vector(2 downto 0);
    .SAXIHP1AWQOS(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP1AWSIZE(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP1AWVALID(1'b0), // in std_ulogic;
    .SAXIHP1BREADY(1'b0), // in std_ulogic;
    .SAXIHP1RDISSUECAP1EN(1'b0), 		// in std_ulogic;
    .SAXIHP1RREADY(1'b0), // in std_ulogic;
    .SAXIHP1WDATA(64'b0), // in std_logic_vector(63 downto 0);
    .SAXIHP1WID(6'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIHP1WLAST(1'b0), // in std_ulogic;
    .SAXIHP1WRISSUECAP1EN(1'b0), 		// in std_ulogic;
    .SAXIHP1WSTRB(8'b0), // in std_logic_vector(7 downto 0);
    .SAXIHP1WVALID(1'b0), // in std_ulogic;
    .SAXIHP2ACLK(1'b0), 	// in std_ulogic;
    .SAXIHP2ARADDR(32'b0), // in std_logic_vector(31 downto 0);
    .SAXIHP2ARBURST(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP2ARCACHE(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP2ARID(6'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIHP2ARLEN(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP2ARLOCK(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP2ARPROT(3'b0), // in std_logic_vector(2 downto 0);
    .SAXIHP2ARQOS(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP2ARSIZE(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP2ARVALID(1'b0), // in std_ulogic;
    .SAXIHP2AWADDR(32'b0), // in std_logic_vector(31 downto 0);
    .SAXIHP2AWBURST(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP2AWCACHE(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP2AWID(6'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIHP2AWLEN(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP2AWLOCK(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP2AWPROT(3'b0), // in std_logic_vector(2 downto 0);
    .SAXIHP2AWQOS(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP2AWSIZE(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP2AWVALID(1'b0), // in std_ulogic;
    .SAXIHP2BREADY(1'b0), // in std_ulogic;
    .SAXIHP2RDISSUECAP1EN(1'b0), 		// in std_ulogic;
    .SAXIHP2RREADY(1'b0), // in std_ulogic;
    .SAXIHP2WDATA(64'b0), // in std_logic_vector(63 downto 0);
    .SAXIHP2WID(6'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIHP2WLAST(1'b0), // in std_ulogic;
    .SAXIHP2WRISSUECAP1EN(1'b0), 		// in std_ulogic;
    .SAXIHP2WSTRB(8'b0), // in std_logic_vector(7 downto 0);
    .SAXIHP2WVALID(1'b0), // in std_ulogic;
    .SAXIHP3ACLK(1'b0), 	// in std_ulogic;
    .SAXIHP3ARADDR(32'b0), // in std_logic_vector(31 downto 0);
    .SAXIHP3ARBURST(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP3ARCACHE(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP3ARID(6'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIHP3ARLEN(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP3ARLOCK(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP3ARPROT(3'b0), // in std_logic_vector(2 downto 0);
    .SAXIHP3ARQOS(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP3ARSIZE(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP3ARVALID(1'b0), // in std_ulogic;
    .SAXIHP3AWADDR(32'b0), // in std_logic_vector(31 downto 0);
    .SAXIHP3AWBURST(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP3AWCACHE(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP3AWID(6'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIHP3AWLEN(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP3AWLOCK(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP3AWPROT(3'b0), // in std_logic_vector(2 downto 0);
    .SAXIHP3AWQOS(4'b0), // in std_logic_vector(3 downto 0);
    .SAXIHP3AWSIZE(2'b0), // in std_logic_vector(1 downto 0);
    .SAXIHP3AWVALID(1'b0), // in std_ulogic;
    .SAXIHP3BREADY(1'b0), // in std_ulogic;
    .SAXIHP3RDISSUECAP1EN(1'b0), 		// in std_ulogic;
    .SAXIHP3RREADY(1'b0), // in std_ulogic;
    .SAXIHP3WDATA(64'b0), // in std_logic_vector(63 downto 0);
    .SAXIHP3WID(6'b0), 	// in std_logic_vector(5 downto 0);
    .SAXIHP3WLAST(1'b0), // in std_ulogic;
    .SAXIHP3WRISSUECAP1EN(1'b0), 		// in std_ulogic;
    .SAXIHP3WSTRB(8'b0), // in std_logic_vector(7 downto 0);
    .SAXIHP3WVALID(1'b0)	// in std_ulogic;
  );
endmodule
