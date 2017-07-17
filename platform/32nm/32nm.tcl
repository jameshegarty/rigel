analyze -autoread -top $TOP -format verilog $FILE
elaborate $TOP
list_designs
link
create_clock -name CLK -period 1 [get_ports CLK]
source /home/jhegarty/saed32/saed32.tcl
set_app_var target_library $TARGET_LIBRARY_FILES
set_app_var synthetic_library {dw_foundation.sldb}
set_app_var link_library [concat * $target_library $synthetic_library]
# avoid re-analyzing the libs
set_app_var alib_library_analysis_path "/home/jhegarty/alib"
alib_analyze_libs
# end
compile_ultra
report_qor > $OUTFILE
write -format ddc -hierarchy -output $DDCFILE
write -f verilog -hierarchy -output $SYNFILE
exit
