analyze -autoread -top $TOP -format verilog $FILE
elaborate $TOP
list_designs
link
create_clock -name CLK -period 20 [get_ports CLK]
source /home/jhegarty/saed32/saed32.tcl
set_app_var target_library $TARGET_LIBRARY_FILES
set_app_var synthetic_library {dw_foundation.sldb}
set_app_var link_library [concat * $target_library $synthetic_library]
compile_ultra
report_qor > $OUTFILE
#write -f verilog -hierarchy -output $FILE.synthesis.v
exit
