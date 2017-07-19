source /home/jhegarty/saed32/saed32.tcl
set_app_var target_library $TARGET_LIBRARY_FILES
set_app_var synthetic_library {dw_foundation.sldb}
set_app_var link_library [concat * $target_library $synthetic_library]

# information about capacitance, wire length (analog stuff)
set_tlu_plus_files -max_tluplus $TLUPLUS_MAX_FILE -min_tluplus $TLUPLUS_MIN_FILE -tech2itf_map $MAP_FILE

# milkyway: a database format (synopsys)
# information about process & design constraints
create_mw_lib  -technology $TECH_FILE  \
    -mw_reference_library $MW_REFERENCE_LIB_DIRS_MV \
    -bus_naming_style {[%d]}             \
    -open     ./chiptop.mw

import_designs -format ddc -top $TOP -cel $TOP $DDCFILE

# design constraints file. clocking contraints. 
source -echo ../../../platform/32nm/compile.sdc

# unified power format
#load_upf ../outputs/compile.upf

# # DERIVE CONNECTIONS
# derive power & ground connections. connect different gates to correct power, based on upf.
derive_pg_connection -create_nets
#derive_pg_connection -power_net VDDL -power_pin {VDD} -cells "GPRs" -verbose
derive_pg_connection -power_net VDD -power_pin {VDD}
derive_pg_connection -ground_net VSS -ground_pin {VSS}
#derive_pg_connection -power_net VDD -power_pin {VDDH}
#derive_pg_connection -power_net VDDL -power_pin {VDDL}

#create_floorplan \
#  -core_utilization 0.25\
#  -start_first_row\
#  -flip_first_row\
#  -left_io2core 50\
#  -bottom_io2core 50\
#  -right_io2core 50\
#  -top_io2core 50

#create_floorplan -width 400 -height 400
create_floorplan -control_type width_and_height -core_width 400 -core_height 400 -start_first_row -left_io2core 25 -bottom_io2core 25 -right_io2core 25 -top_io2core 25

# # GET CORE
# ##########
set bbox [get_att [get_core_area] bbox]
set x1 [lindex [lindex $bbox 0] 0]
set y1 [lindex [lindex $bbox 0] 1]
set x2 [lindex [lindex $bbox 1] 0]
set y2 [lindex [lindex $bbox 1] 1]

# # CREATE VOLTAGE AREAS
# ######################
set GPRS_x 55
set GPRS_y 55
set GPRS_w 350
set GPRS_h 450

set TOP_ring_w 5
set TOP_ring_s 12
set TOP_VSS_ring_s 22
set TOP_VDDL_ring_s 32

remove_voltage_area -all
create_voltage_area  -coordinate [list $GPRS_x $GPRS_y $GPRS_w $GPRS_h] -power_domain GPRS -guard_band_x 2 -guard_band_y 2 -target_utilization 0.4 -cycle_color

# ### RINGS
# high voltage
create_rectangular_rings  -nets  {VDD} \
-left_offset $TOP_ring_s -left_segment_layer M5 -left_segment_width $TOP_ring_w -extend_ll -extend_lh \
-right_offset $TOP_ring_s -right_segment_layer M5 -right_segment_width $TOP_ring_w -extend_rl -extend_rh \
-bottom_offset $TOP_ring_s -bottom_segment_layer M6 -bottom_segment_width $TOP_ring_w -extend_bl -extend_bh \
-top_offset $TOP_ring_s -top_segment_layer M6 -top_segment_width $TOP_ring_w -extend_tl -extend_th

# ground
create_rectangular_rings  -nets  {VSS}  \
-left_offset $TOP_VSS_ring_s -left_segment_layer M5 -left_segment_width $TOP_ring_w  -extend_ll -extend_lh \
 -right_offset $TOP_VSS_ring_s -right_segment_layer M5 -right_segment_width $TOP_ring_w  -extend_rl -extend_rh \
 -bottom_offset $TOP_VSS_ring_s -bottom_segment_layer M6 -bottom_segment_width $TOP_ring_w  -extend_bl -extend_bh \
 -top_offset $TOP_VSS_ring_s -top_segment_layer M6 -top_segment_width $TOP_ring_w -extend_tl -extend_th

########################
# some kind of cell placement options
set_fp_placement_strategy       -macros_on_edge on \
                                -sliver_size 5 \
                                -virtual_IPO on


set_keepout_margin  -type hard -all_macros -outer {20 20 20 20}

create_fp_placement -timing_driven -no_hierarchy_gravity

#set_dont_touch_placement [all_macro_cells]

#########################################PNS TOP################################################################
# more placement options
set_fp_rail_constraints -remove_all_layers

analyze_fp_rail  -nets {VDD VSS} -power_budget 1000 -voltage_supply 0.95 -use_pins_as_pads

set_fp_rail_constraints  -skip_ring -extend_strap core_ring

set_fp_rail_constraints -add_layer  -layer M5 -direction vertical -max_strap 14 -min_strap 2 -max_width 6.080 -min_width 3.040 -spacing 6.080
set_fp_rail_constraints -add_layer  -layer M6 -direction horizontal -max_strap 14 -min_strap 2 -max_width 6.080 -min_width 3.040 -spacing 6.080


set_fp_rail_constraints -set_global   -no_routing_over_hard_macros -no_routing_over_soft_macros -no_routing_over_plan_groups

set_fp_block_ring_constraints -add -horizontal_layer M6 -horizontal_width 3 -horizontal_offset 1 -vertical_layer M5 -vertical_width 3 -vertical_offset 1 -spacing 2 -block_type master  -block {SRAM1RW256x32} -net  {VDD VSS}

synthesize_fp_rail  -nets {VDD VSS} -voltage_supply 0.95 -synthesize_power_plan -power_budget 1000 -use_pins_as_pads -use_strap_ends_as_pads

commit_fp_rail

# fix (constrain) placement of a cell. but doesn't actually set position.
#set_object_fixed_edit [get_cell MemXHier/MemXa] 1
#set_object_fixed_edit [get_cell MemXHier/MemXb] 1
#set_object_fixed_edit [get_cell MemYHier/MemXa] 1
#set_object_fixed_edit [get_cell MemYHier/MemXb] 1

# needed for multiple voltage areas
# remove_plan_groups {GPRs}

##############################################################FILLERS ##############################################################
# cells are placed in a grid. each grid cell has power on top of cell, ground on bottom. Tell it which cells to use for empty areas to pass through power/ground

set filler_cell [list SHFILL128_RVT SHFILL64_RVT SHFILL3_RVT SHFILL2_RVT  SHFILL1_RVT]
set filler_cell_wom [list SHFILLWM128_RVT SHFILLWM16_RVT SHFILLWM2_RVT]
#insert_stdcell_filler -cell_without_metal $filler_cell  \
# -voltage_area GPRS -connect_to_power VDDL -connect_to_ground VSS
insert_stdcell_filler -cell_without_metal $filler_cell \
-voltage_area DEFAULT_VA -connect_to_power VDD -connect_to_ground VSS

######################################################3
# #PREROUTE
set preroute_layerSwitching 0

# we have no VDDL
#preroute_standard_cells -nets  {VDDL} -remove_floating_pieces -within_voltage_areas [get_voltage_areas {GPRS}]
preroute_standard_cells  -nets  {VDD} -remove_floating_pieces -extend_to_boundaries_and_generate_pins
preroute_standard_cells  -nets  {VSS} -remove_floating_pieces -extend_to_boundaries_and_generate_pins

remove_stdcell_filler -stdcell

# ###############################################################################
save_mw_cel -as chiptop_1_planned
# set # of routing layers
set_net_routing_layer_constraints   {ChipTop}   -min_layer M1  -max_layer M9
set_pnet_options -partial {M5 M6}
set_pnet_options -complete {M5 M6}
legalize_fp_placement

# do actual placement!!
place_opt

##############################
# start routing stuff
set_app_var physopt_hard_keepout_distance 10

# set up power and ground connections
#derive_pg_connection -power_net VDDL -power_pin {VDD} -cells "GPRs" -verbose
derive_pg_connection -power_net VDD -power_pin {VDD}
derive_pg_connection -ground_net VSS -ground_pin {VSS}
#derive_pg_connection -power_net VDD -power_pin {VDDH}
#derive_pg_connection -power_net VDDL -power_pin {VDDL}

# ??
#preroute_standard_cells -mode net -nets VDD -port_filter VDDH -h_layer M3 -v_layer M2 -connect horizontal  -voltage_area_filter_mode select -voltage_area_filter "GPRS"
preroute_standard_cells -mode net -nets VDDL -port_filter VDDL -h_layer M3 -v_layer M2
preroute_standard_cells -mode net -nets VDDL -port_filter VDDL -port_filter_mode select -h_layer M3 -v_layer M2

# don't change these things during routing (??)
set_dont_touch GPRs/LS_*
set_dont_touch LS_*
set_dont_use GPRs/LS_*
set_dont_use LS_*
set_object_fixed_edit [get_cells GPRs/LS_*] 1
set_object_fixed_edit [get_cells LS_*] 1


preroute_instances

# checkpointing
save_mw_cel -as chiptop_2_placed

# set which layers clock can use
set_clock_tree_options -layer_list {M2 M3 M4}

# do clock routing (more important & contrained)
clock_opt
derive_pg_connection

save_mw_cel -as chiptop_3_cts

set_ignored_layers -min_routing_layer M2  -max_routing_layer M4

# do all other routing than clock&power
route_opt

save_mw_cel -as chiptop_4_routed
derive_pg_connection

# needed for different voltage areas??
#insert_stdcell_filler -cell_with_metal $filler_cell -cell_without_metal $filler_cell_wom \
# -voltage_area GPRS -connect_to_power VDDL -connect_to_ground VSS

###########reports##########################
report_area
report_timing
report_power

save_mw_cel -as chiptop_4_finished


change_names -rules verilog -verbose
# write out verilog with power and ground wires (PG)
write_verilog -pg -wire_declaration ./chiptop.v

# write GDS file to send to foundary
set_write_stream_options -flatten_via -child_depth 20 -output_filling fill -output_pin text
write_stream -format gds ./chiptop.gds


close_mw_cel
close_mw_lib

exit
