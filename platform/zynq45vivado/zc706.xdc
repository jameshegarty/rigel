create_clock -add -name FCLK -period 5.00 -waveform {0 4} [get_nets FCLK0];

##LEDs
set_property PACKAGE_PIN W21 [get_ports  { LED[0] }]
set_property IOSTANDARD LVCMOS25 [get_ports  { LED[0] }]
set_property PACKAGE_PIN Y21 [get_ports  { LED[1] }]
set_property IOSTANDARD LVCMOS25 [get_ports  { LED[1] }]
set_property PACKAGE_PIN G2 [get_ports  { LED[2] }]
set_property IOSTANDARD LVCMOS15 [get_ports  { LED[2] }]
set_property PACKAGE_PIN A17 [get_ports  { LED[3] }]
set_property IOSTANDARD LVCMOS15 [get_ports  { LED[3] }]

# HACK: doesn't have 8 LEDs, instead, emulate that by putting some of the LEDs on PMOD

set_property PACKAGE_PIN Y20 [get_ports { LED[4] }]
set_property IOSTANDARD LVCMOS25 [get_ports { LED[4] }]
set_property PACKAGE_PIN AA20 [get_ports { LED[5] }]
set_property IOSTANDARD LVCMOS25 [get_ports { LED[5] }]
set_property PACKAGE_PIN AC18 [get_ports { LED[6] }]
set_property IOSTANDARD LVCMOS25 [get_ports { LED[6] }]
set_property PACKAGE_PIN AC19 [get_ports { LED[7] }]
set_property IOSTANDARD LVCMOS25 [get_ports { LED[7] }]
