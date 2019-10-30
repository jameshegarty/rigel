#################################################
### ZCU102 Rev1.0 Master XDC file 09-15-2016 ####
#################################################
#Other net   PACKAGE_PIN W17      - SYSMON_DXN                Bank   0 - DXN
#Other net   PACKAGE_PIN T18      - FPGA_SYSMON_AVCC          Bank   0 - VCCADC
#Other net   PACKAGE_PIN T17      - SYSMON_AGND               Bank   0 - GNDADC
#Other net   PACKAGE_PIN W18      - SYSMON_DXP                Bank   0 - DXP
#Other net   PACKAGE_PIN V18      - SYSMON_VREFP              Bank   0 - VREFP
#Other net   PACKAGE_PIN U17      - SYSMON_AGND               Bank   0 - VREFN
#Other net   PACKAGE_PIN U18      - SYSMON_VP_R               Bank   0 - VP
#Other net   PACKAGE_PIN V17      - SYSMON_VN_R               Bank   0 - VN
#Other net   PACKAGE_PIN AD15     - 3N5822                    Bank   0 - PUDC_B_0
#Other net   PACKAGE_PIN AD14     - 3N5824                    Bank   0 - POR_OVERRIDE

#create_clock -add -name FCLK -period 5.00 -waveform {0 4} [get_nets FCLK0];
create_clock -add -name FCLK -period 5.0 [get_nets FCLK0];

set_property PACKAGE_PIN AG14     [get_ports {LED[0]}] ;# Bank  44 VCCO - VCC3V3   - IO_L10P_AD2P_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[0]}] ;# Bank  44 VCCO - VCC3V3   - IO_L10P_AD2P_44
set_property PACKAGE_PIN AF13     [get_ports {LED[1]}] ;# Bank  44 VCCO - VCC3V3   - IO_L9N_AD3N_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[1]}] ;# Bank  44 VCCO - VCC3V3   - IO_L9N_AD3N_44
set_property PACKAGE_PIN AE13     [get_ports {LED[2]}] ;# Bank  44 VCCO - VCC3V3   - IO_L9P_AD3P_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[2]}] ;# Bank  44 VCCO - VCC3V3   - IO_L9P_AD3P_44
set_property PACKAGE_PIN AJ14     [get_ports {LED[3]}] ;# Bank  44 VCCO - VCC3V3   - IO_L8N_HDGC_AD4N_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[3]}] ;# Bank  44 VCCO - VCC3V3   - IO_L8N_HDGC_AD4N_44
set_property PACKAGE_PIN AJ15     [get_ports {LED[4]}] ;# Bank  44 VCCO - VCC3V3   - IO_L8P_HDGC_AD4P_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[4]}] ;# Bank  44 VCCO - VCC3V3   - IO_L8P_HDGC_AD4P_44
set_property PACKAGE_PIN AH13     [get_ports {LED[5]}] ;# Bank  44 VCCO - VCC3V3   - IO_L7N_HDGC_AD5N_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[5]}] ;# Bank  44 VCCO - VCC3V3   - IO_L7N_HDGC_AD5N_44
set_property PACKAGE_PIN AH14     [get_ports {LED[6]}] ;# Bank  44 VCCO - VCC3V3   - IO_L7P_HDGC_AD5P_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[6]}] ;# Bank  44 VCCO - VCC3V3   - IO_L7P_HDGC_AD5P_44
set_property PACKAGE_PIN AL12     [get_ports {LED[7]}] ;# Bank  44 VCCO - VCC3V3   - IO_L6N_HDGC_AD6N_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[7]}] ;# Bank  44 VCCO - VCC3V3   - IO_L6N_HDGC_AD6N_44
#set_property PACKAGE_PIN AK13     [get_ports "GPIO_DIP_SW7"] ;# Bank  44 VCCO - VCC3V3   - IO_L6P_HDGC_AD6P_44
#set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_DIP_SW7"] ;# Bank  44 VCCO - VCC3V3   - IO_L6P_HDGC_AD6P_44
#set_property PACKAGE_PIN AL13     [get_ports "GPIO_DIP_SW6"] ;# Bank  44 VCCO - VCC3V3   - IO_L4P_AD8P_44
#set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_DIP_SW6"] ;# Bank  44 VCCO - VCC3V3   - IO_L4P_AD8P_44
#set_property PACKAGE_PIN AP12     [get_ports "GPIO_DIP_SW5"] ;# Bank  44 VCCO - VCC3V3   - IO_L3N_AD9N_44
#set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_DIP_SW5"] ;# Bank  44 VCCO - VCC3V3   - IO_L3N_AD9N_44
#set_property PACKAGE_PIN AN12     [get_ports "GPIO_DIP_SW4"] ;# Bank  44 VCCO - VCC3V3   - IO_L3P_AD9P_44
#set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_DIP_SW4"] ;# Bank  44 VCCO - VCC3V3   - IO_L3P_AD9P_44
#set_property PACKAGE_PIN AN13     [get_ports "GPIO_DIP_SW3"] ;# Bank  44 VCCO - VCC3V3   - IO_L2N_AD10N_44
#set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_DIP_SW3"] ;# Bank  44 VCCO - VCC3V3   - IO_L2N_AD10N_44
#set_property PACKAGE_PIN AM14     [get_ports "GPIO_DIP_SW2"] ;# Bank  44 VCCO - VCC3V3   - IO_L2P_AD10P_44
#set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_DIP_SW2"] ;# Bank  44 VCCO - VCC3V3   - IO_L2P_AD10P_44
#set_property PACKAGE_PIN AP14     [get_ports "GPIO_DIP_SW1"] ;# Bank  44 VCCO - VCC3V3   - IO_L1N_AD11N_44
#set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_DIP_SW1"] ;# Bank  44 VCCO - VCC3V3   - IO_L1N_AD11N_44
#set_property PACKAGE_PIN AN14     [get_ports "GPIO_DIP_SW0"] ;# Bank  44 VCCO - VCC3V3   - IO_L1P_AD11P_44
#set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_DIP_SW0"] ;# Bank  44 VCCO - VCC3V3   - IO_L1P_AD11P_44
