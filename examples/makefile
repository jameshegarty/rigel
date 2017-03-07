SRCS = $(wildcard *.lua)
SRCS := $(filter-out harness.lua examplescommon.lua pyramid_core.lua harris_core.lua sift_core.lua sift_core_hw.lua campipe_core.lua descriptor_core.lua  stereo_core.lua stereo_tr_core.lua  lk_core.lua lk_tr_core.lua,$(SRCS))


VERILATOR_INCLUDE ?= $(shell pkg-config --variable=includedir verilator)
LUA = ../rigelLuajit
TERRA = ../rigelTerra

RAWS = $(wildcard *.raw)
DUPS = $(patsubst %.raw,out/%.raw.dup,$(RAWS))

VERILOG = $(patsubst %.lua,out/%.v,$(SRCS))

# too slow
SRCS_TERRA = $(filter-out stereo_tr_rgba_full_32.lua stereo_ov7660.lua underflow.lua lk_wide_handshake_12_1_float.lua lk_wide_handshake_12_1_axi.lua lk_wide_handshake_12_1_axi_nostall.lua lk_tr_handshake_12_1_axi.lua lk_tr_handshake_12_2_axi.lua lk_tr_handshake_12_3_axi.lua lk_tr_handshake_12_4_axi.lua lk_tr_handshake_12_6_axi.lua lk_tr_handshake_12_12_axi.lua, $(SRCS))

TERRAOUT = $(patsubst %.lua,out/%.terra.raw,$(SRCS_TERRA))
TERRAOUT += $(patsubst %.lua,out/%_half.terra.raw,$(SRCS_TERRA))
TERRAOUT += $(patsubst %.lua,out/%.terra.bmp,$(SRCS_TERRA))
TERRAOUT += $(patsubst %.lua,out/%_half.terra.bmp,$(SRCS_TERRA))
TERRAOUT += $(patsubst %.lua,out/%.terra.correct.txt,$(SRCS_TERRA))
TERRAOUT += $(patsubst %.lua,out/%_half.terra.correct.txt,$(SRCS_TERRA))

#SRCS_VERILATOR = $(filter-out underflow.lua, $(SRCS_TERRA))
VERILATOR = $(patsubst %.lua,out/%.verilator,$(SRCS))
VERILATOR = $(patsubst %.lua,out/%.verilator.raw,$(SRCS))
#VERILATOR += $(patsubst %.lua,out/%_half.raw,$(SRCS))
VERILATOR += $(patsubst %.lua,out/%.verilator.bmp,$(SRCS))
#VERILATOR += $(patsubst %.lua,out/%_half.bmp,$(SRCS))
VERILATOR += $(patsubst %.lua,out/%.verilator.correct.txt,$(SRCS))
#VERILATOR += $(patsubst %.lua,out/%_half.correct.txt,$(SRCS))

# too slow
SRCS_TERRA_SIM = $(SRCS_TERRA)
SRCS_TERRA_SIM := $(filter-out stereo_wide_handshake_medi.t stereo_wide_handshake_nostall_medi.t stereo_tr_medi_4.t stereo_tr_medi_8.t stereo_tr_medi_16.t ,$(SRCS_TERRA_SIM))
SRCS_TERRA_SIM := $(filter-out stereo_wide_handshake_full.t stereo_wide_handshake_nostall_full.t stereo_tr_full_4.t stereo_tr_full_8.t stereo_tr_full_16.t stereo_tr_rgba_full_32.t,$(SRCS_TERRA_SIM))
SRCS_TERRA_SIM := $(filter-out stereo_ov7660.t ,$(SRCS_TERRA_SIM))
SRCS_TERRA_SIM := $(filter-out lk_wide_handshake_4_4_float.t lk_wide_handshake_6_4_axi.t lk_wide_handshake_6_4_float.t lk_wide_handshake_6_1_axi.t lk_wide_handshake_4_4_axi.t lk_wide_handshake_4_1_axi.t lk_tr_handshake_4_4_axi.t lk_tr_handshake_6_6.t lk_tr_handshake_6_6_axi.t lk_tr_handshake_6_1.t lk_tr_handshake_6_1_axi.t lk_tr_handshake_6_2.t lk_tr_handshake_6_2_axi.t lk_tr_handshake_6_3.t lk_tr_handshake_6_3_axi.t ,$(SRCS_TERRA_SIM))
SRCS_TERRA_SIM := $(filter-out lk_wide_handshake_12_1_float.t lk_wide_handshake_12_1_axi.t lk_wide_handshake_12_1_axi_nostall.t lk_tr_handshake_12_1_axi.t lk_tr_handshake_12_2_axi.t lk_tr_handshake_12_3_axi.t lk_tr_handshake_12_4_axi.t lk_tr_handshake_12_6_axi.t lk_tr_handshake_12_12_axi.t,$(SRCS_TERRA_SIM))
SRCS_TERRA_SIM := $(filter-out campipe_512.t campipe_ov7660.t,$(SRCS_TERRA_SIM))
SRCS_TERRA_SIM := $(filter-out pyramid_large_1.t pyramid_large_2.t pyramid_large_3.t pyramid_large_4.t pyramid_large_tr_1.t pyramid_large_tr_2.t pyramid_large_tr_3.t pyramid_large_tr_4.t pyramid_large_nofifo_tr_1.t pyramid_large_nofifo_tr_2.t pyramid_large_nofifo_tr_3.t pyramid_large_nofifo_tr_4.t,$(SRCS_TERRA_SIM))
SRCS_TERRA_SIM := $(filter-out pyramid_large_taps_1.t pyramid_large_taps_2.t pyramid_large_taps_3.t pyramid_large_taps_4.t pyramid_large_nofifo_taps_1.t pyramid_large_nofifo_taps_2.t pyramid_large_nofifo_taps_3.t pyramid_large_nofifo_taps_4.t,$(SRCS_TERRA_SIM))
SRCS_TERRA_SIM := $(filter-out convpadcrop_wide_handshake_4_1_1080p.t convpadcrop_wide_handshake_4_2_1080p.t convpadcrop_wide_handshake_4_4_1080p.t convpadcrop_wide_handshake_4_8_1080p.t convpadcrop_wide_handshake_8_1_1080p.t convpadcrop_wide_handshake_8_2_1080p.t convpadcrop_wide_handshake_8_4_1080p.t convpadcrop_wide_handshake_8_8_1080p.t,$(SRCS_TERRA_SIM))
SRCS_TERRA_SIM := $(filter-out convpadcrop_wide_handshake_8_1_1080p_nostall.t convpadcrop_wide_handshake_8_2_1080p_nostall.t convpadcrop_wide_handshake_8_4_1080p_nostall.t convpadcrop_wide_handshake_8_8_1080p_nostall.t,$(SRCS_TERRA_SIM))
SRCS_TERRA_SIM := $(filter-out conv_tr_handshake_4_1_1080p.t conv_tr_handshake_4_2_1080p.t conv_tr_handshake_4_4_1080p.t conv_tr_handshake_4_8_1080p.t conv_tr_handshake_8_1_1080p.t conv_tr_handshake_8_2_1080p.t conv_tr_handshake_8_4_1080p.t conv_tr_handshake_8_8_1080p.t,$(SRCS_TERRA_SIM))
#nyi
SRCS_TERRA_SIM := $(filter-out fixed_float_inv.t harris_corner.t filterseq.t harris_filterseq.t sift_float.t sift_desc.t sift_desc_hw.t sift_hw.t sift_hw_1080p.t,$(SRCS_TERRA_SIM))

ISIM = $(patsubst %.t,out/%.sim.bmp,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.t,out/%.sim.1.bmp,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.t,out/%_half.sim.bmp,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.t,out/%.sim.raw,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.t,out/%_half.sim.raw,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.t,out/%.sim.v,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.t,out/%_half.sim.v,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.t,out/%.sim.correct.txt,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.t,out/%.sim.1.correct.txt,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.t,out/%_half.sim.correct.txt,$(SRCS_TERRA_ISIM))

SRCS_AXI100 = $(filter-out linebufferpartial_handshake_1.lua linebufferpartial_handshake_2.lua linebufferpartial_handshake_4.lua convpadcrop_handshake.lua reduceseq_handshake.lua  stereo_wide_handshake_medi.lua,$(SRCS))
SRCS_AXI100 := $(filter-out lk_tr_handshake_4_4.lua lk_tr_handshake_6_6.lua lk_tr_handshake_6_1.lua lk_tr_handshake_6_2.lua lk_tr_handshake_6_3.lua lk_wide_handshake_12_1_float.lua,$(SRCS_AXI100))
SRCS_AXI100 := $(filter-out lk_wide_handshake_4_4_float.lua lk_wide_handshake_6_4_float.lua lk_wide_handshake_4_4.lua lk_wide_handshake_4_1.lua,$(SRCS_AXI100))
SRCS_AXI100 := $(filter-out harris_filterseq.lua sift_float.lua sift_desc.lua,$(SRCS_AXI100))

# filter out stuff that's too big for the 7020
SRCS_AXI = $(SRCS_AXI100)
SRCS_AXI := $(filter-out stereo_wide_handshake_nostall_full.lua stereo_wide_handshake_nostall_medi.lua stereo_wide_handshake_full.lua,$(SRCS_AXI))
SRCS_AXI := $(filter-out lk_tr_handshake_12_1_axi.lua lk_tr_handshake_12_2_axi.lua lk_tr_handshake_12_3_axi.lua lk_tr_handshake_12_4_axi.lua lk_tr_handshake_12_6_axi.lua lk_tr_handshake_6_1_axi.lua lk_wide_handshake_4_4_axi.lua lk_wide_handshake_6_4_axi.lua,$(SRCS_AXI))
SRCS_AXI := $(filter-out lk_wide_handshake_12_1_axi_nostall.lua lk_wide_handshake_12_1_axi.lua,$(SRCS_AXI))
SRCS_AXI := $(filter-out pyramid_large_nofifo_taps_4.lua pyramid_large_taps_3.lua pyramid_taps_3.lua pyramid_taps_4.lua pyramid_large_taps_4.lua,$(SRCS_AXI))

AXIBITS = $(patsubst %.lua,out/%.axi.v,$(SRCS_AXI))
AXIBITS += $(patsubst %.lua,out/%.axi.bit,$(SRCS_AXI))

AXIBITS100 = $(patsubst %.lua,out/%.axi100.bit,$(SRCS_AXI100))
AXIBITS100 += $(patsubst %.lua,out/%.axi100.bit.bin,$(SRCS_AXI100))

AXI = $(patsubst %.lua,out/%.axi.raw,$(SRCS_AXI))
AXI += $(patsubst %.lua,out/%.axi.bmp,$(SRCS_AXI))
AXI += $(patsubst %.lua,out/%.axi.correct.txt,$(SRCS_AXI))
AXI += $(patsubst %.lua,out/%.hz.txt,$(SRCS_AXI))
AXI += $(AXIBITS)

AXI100 = $(patsubst %.lua,out/%.axi100.correct.txt,$(SRCS_AXI100))
AXI100 += $(patsubst %.lua,out/%.axi100.raw,$(SRCS_AXI100))
AXI100 += $(patsubst %.lua,out/%.axi100.bmp,$(SRCS_AXI100))
AXI100 += $(AXIBITS100)

STATS = $(patsubst %.lua,out/%.stats.txt,$(AXISRCS))

STATS100 = $(patsubst %.lua,out/%.stats100.txt,$(SRCS_AXI100))

CAMERASRCS = stereo_ov7660.t 2xov7660.t campipe_ov7660.t
CAMERABITS = $(patsubst %.t,out/%.axi.v,$(CAMERASRCS))
CAMERABITS += $(patsubst %.t,out/%.camera.bit,$(CAMERASRCS))


RES = $(TERRAOUT)
RES += $(VERILATOR)
RES += $(ISIM)
RES += $(AXI)
RES += $(AXIBITS)
RES += $(AXI100)
RES += $(AXIBITS100)

CD = cd out;
all: $(RES)

# keep make from deleting these intermediates
.SECONDARY:

dups: $(DUPS)

verilog: $(VERILOG)

terra: $(TERRAOUT)

verilator: $(VERILATOR)

isim: $(ISIM)

stats: $(STATS)

stats100: $(STATS100)

axi: $(AXI)

camerabits: $(CAMERABITS)

axi100: $(AXI100)

axibits: $(AXIBITS)

axibits100: $(AXIBITS100)

clean:
	rm -Rf out/*

out/%.v out/%.metadata.lua: %.t 
	$(TERRA) $<
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.v out/build_$*

out/%.v out/%.metadata.lua: %.lua
	$(LUA) $<
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.v out/build_$*

out/%.terra.raw out/%_half.terra.raw: %.t
	$(TERRA) $< terrasim
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.cycles.txt out/build_$*

out/%.terra.raw out/%_half.terra.raw: %.lua
	$(TERRA) $< terrasim
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.cycles.txt out/build_$*

out/%.isim.v out/%_half.isim.v: %.t 
	$(LUA) $< isim
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.sim.v out/build_$*

out/%.axi.v: %.lua
	$(LUA) $< axi
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.axi.v out/build_$*
	mkdir -p out/build100_$*
	- cp out/$*.axi.v out/build100_$*

#/opt/Xilinx/14.5/ISE_DS/ISE/verilog/src/unisims
#	verilator -cc -Mdir out/$*_verilator  /opt/Xilinx/14.5/ISE_DS/ISE/verilog/src/unisims/RAMB16_S36_S36.v out/$*.verilator.v
out/%.verilator: out/%.v out/%.metadata.lua
	$(eval $@_TOP := $(shell luajit ../misc/extractMetadata.lua out/$*.metadata.lua topModule))
	verilator -cc -Mdir out/$*_verilator out/$*.v ../platform/verilator/RAMB16_S36_S36.v ../platform/verilator/RAMB16_S18_S18.v ../platform/verilator/RAMB16_S9_S9.v ../platform/verilator/RAMB16_RIGEL.v --top-module $($@_TOP)
	$(LUA) ../platform/verilator/makeHarness.lua out/$*.metadata.lua $* > out/$*.verilator.cpp
	g++ $(shell pkg-config --cflags verilator) out/$*_verilator/V$($@_TOP).cpp out/$*_verilator/V$($@_TOP)__Syms.cpp ${VERILATOR_INCLUDE}/verilated.cpp out/$*.verilator.cpp -o $@

out/%.verilator.raw: out/%.verilator
	./out/$*.verilator

out/%.verilator.bmp: out/%.verilator.raw out/%.metadata.lua
	$(LUA) ../misc/raw2bmp.lua out/$*.verilator.raw out/$*.verilator.bmp out/$*.metadata.lua 0
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.verilator.bmp out/build_$*

out/%.verilator.correct.txt : out/%.verilator.bmp
	diff out/$*.verilator.bmp gold/$*.bmp > out/$*.verilator.diff
	test ! -s out/$*.verilator.diff && touch $@
	# keep copy for future reference
#	mkdir -p out/build_$*
#	test ! -s out/$*.verilator.diff && touch $@

out/build_%/system.ngc: out/%.axi.v
	mkdir -p out/build_$*
	# run xst, then 'help -arch zynq -command run' to get list of options
	cd out/build_$*; echo "run -ifn ../$*.axi.v -ifmt Verilog -p xc7z020-clg484-1 -top stage -use_dsp48 No -ofn system" | xst > OUT_xst.txt

out/build_%/system.ngd: out/build_%/system.ngc
	cd out/build_$*; ngdbuild -nt timestamp -uc ../../../platform/axi/ps7_constraints.ucf -uc ../../../platform/axi/system.ucf -p xc7z020-clg484-1 system.ngc system.ngd > OUT_ngd.txt

out/build_%/system_map.ncd: out/build_%/system.ngd
	cd out/build_$*; map -detail -p xc7z020-clg484-1 -w -logic_opt off -ol high -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o system_map.ncd system.ngd system.pcf > OUT_map.txt

out/build_%/system.ncd: out/build_%/system_map.ncd
	cd out/build_$*; par -w -ol high -mt off system_map.ncd system.ncd system.pcf > OUT_par.txt

out/build_%/system.twr: out/build_%/system.ncd
	cd out/build_$*; trce -v 3 -s 1 -n 3 -fastpaths -xml system.twx system.ncd -o system.twr system.pcf -ucf ../../platform/axi/ps7_constraints.ucf -ucf ../../platform/axi/system.ucf > OUT_trce.txt

out/%.axi.bit: out/build_%/system.twr
	cd out/build_$*; bitgen -w -g Binary:no -g CRC:Enable -g ProgPin:PullUp -g InitPin:Pullup -g TckPin:PullUp -g TdiPin:PullUp \
	  -g TdoPin:PullUp -g TmsPin:PullUp -g Disable_JTAG:No -g UnusedPin:PullDown -g UserID:0xFFFFFFFF -g OverTempPowerDown:Disable \
	  -g USR_ACCESS:None -g JTAG_XADC:Enable -g DCIUpdateMode:AsRequired -g StartUpClk:CClk -g DONE_cycle:4 -g GTS_cycle:5 -g GWE_cycle:6 \
	  -g Match_cycle:Auto -g Security:None -g ICAP_select:Auto -g DonePipe:Yes -g DriveDone:No system.ncd > OUT_bitgen.txt
	cp out/build_$*/system.bit $@


out/%.camera.bit: out/%.axi.v
	mkdir -p out/buildcamera_$*
	echo "verilog work \"../$*.axi.v\"" > out/buildcamera_$*/system.prj
	echo "verilog work \"../../../platform/camera/vsrc/*.v\"" >> out/buildcamera_$*/system.prj
	cp ../platform/camera/vsrc/*.ngc out/buildcamera_$*/.
	cd out/buildcamera_$*; xst -ifn ../../../platform/camera/system.xst  | tee OUT_xst.log
	cd out/buildcamera_$*; ngdbuild -nt timestamp -uc ../../../platform/camera/ps7_constraints.ucf -uc ../../../platform/camera/system.ucf -p xc7z020-clg484-1 system.ngc system.ngd | tee OUT_ngd.log
	cd out/buildcamera_$*; map -detail -p xc7z020-clg484-1 -w -logic_opt off -ol high -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o system_map.ncd system.ngd system.pcf > OUT_map.txt
	cd out/buildcamera_$*; par -w -ol high -mt off system_map.ncd system.ncd system.pcf > OUT_par.txt
	cd out/buildcamera_$*; trce -v 3 -s 1 -n 3 -fastpaths -xml system.twx system.ncd -o system.twr system.pcf -ucf ../../platform/axi/ps7_constraints.ucf -ucf ../../platform/axi/system.ucf > OUT_trce.txt
	cd out/buildcamera_$*; bitgen -w -g Binary:no -g CRC:Enable -g ProgPin:PullUp -g InitPin:Pullup -g TckPin:PullUp -g TdiPin:PullUp \
	  -g TdoPin:PullUp -g TmsPin:PullUp -g Disable_JTAG:No -g UnusedPin:PullDown -g UserID:0xFFFFFFFF -g OverTempPowerDown:Disable \
	  -g USR_ACCESS:None -g JTAG_XADC:Enable -g DCIUpdateMode:AsRequired -g StartUpClk:CClk -g DONE_cycle:4 -g GTS_cycle:5 -g GWE_cycle:6 \
	  -g Match_cycle:Auto -g Security:None -g ICAP_select:Auto -g DonePipe:Yes -g DriveDone:No system.ncd > OUT_bitgen.txt
	cp out/buildcamera_$*/system.bit $@

out/%.camera1x.bit: out/%.axi.v
	mkdir -p out/buildcamera_$*
	echo "verilog work \"../$*.axi.v\"" > out/buildcamera_$*/system.prj
	echo "verilog work \"../../../platform/camera1x/vsrc/*.v\"" >> out/buildcamera_$*/system.prj
	cp ../platform/camera1x/vsrc/*.ngc out/buildcamera_$*/.
	cd out/buildcamera_$*; xst -ifn ../../../platform/camera/system.xst  | tee OUT_xst.log
	cd out/buildcamera_$*; ngdbuild -nt timestamp -uc ../../../platform/camera/ps7_constraints.ucf -uc ../../../platform/camera1x/system.ucf -p xc7z020-clg484-1 system.ngc system.ngd | tee OUT_ngd.log
	cd out/buildcamera_$*; map -detail -p xc7z020-clg484-1 -w -logic_opt off -ol high -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o system_map.ncd system.ngd system.pcf > OUT_map.txt
	cd out/buildcamera_$*; par -w -ol high -mt off system_map.ncd system.ncd system.pcf > OUT_par.txt
	cd out/buildcamera_$*; trce -v 3 -s 1 -n 3 -fastpaths -xml system.twx system.ncd -o system.twr system.pcf -ucf ../../platform/axi/ps7_constraints.ucf -ucf ../../platform/axi/system.ucf > OUT_trce.txt
	cd out/buildcamera_$*; bitgen -w -g Binary:no -g CRC:Enable -g ProgPin:PullUp -g InitPin:Pullup -g TckPin:PullUp -g TdiPin:PullUp \
	  -g TdoPin:PullUp -g TmsPin:PullUp -g Disable_JTAG:No -g UnusedPin:PullDown -g UserID:0xFFFFFFFF -g OverTempPowerDown:Disable \
	  -g USR_ACCESS:None -g JTAG_XADC:Enable -g DCIUpdateMode:AsRequired -g StartUpClk:CClk -g DONE_cycle:4 -g GTS_cycle:5 -g GWE_cycle:6 \
	  -g Match_cycle:Auto -g Security:None -g ICAP_select:Auto -g DonePipe:Yes -g DriveDone:No system.ncd > OUT_bitgen.txt
	cp out/buildcamera_$*/system.bit $@

out/%.camera2.0.bit: out/%.axi.v
	mkdir -p out/buildcamera_$*
	echo "verilog work \"../$*.axi.v\"" > out/buildcamera_$*/system.prj
	echo "verilog work \"../../../platform/camera2.0/vsrc/*.v\"" >> out/buildcamera_$*/system.prj
	cp ../platform/camera2.0/vsrc/*.ngc out/buildcamera_$*/.
	cd out/buildcamera_$*; xst -ifn ../../../platform/camera/system.xst  | tee OUT_xst.log
	cd out/buildcamera_$*; ngdbuild -nt timestamp -uc ../../../platform/camera/ps7_constraints.ucf -uc ../../../platform/camera2.0/system.ucf -p xc7z020-clg484-1 system.ngc system.ngd | tee OUT_ngd.log
	cd out/buildcamera_$*; map -detail -p xc7z020-clg484-1 -w -logic_opt off -ol high -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o system_map.ncd system.ngd system.pcf > OUT_map.txt
	cd out/buildcamera_$*; par -w -ol high -mt off system_map.ncd system.ncd system.pcf > OUT_par.txt
	cd out/buildcamera_$*; trce -v 3 -s 1 -n 3 -fastpaths -xml system.twx system.ncd -o system.twr system.pcf -ucf ../../platform/axi/ps7_constraints.ucf -ucf ../../platform/axi/system.ucf > OUT_trce.txt
	cd out/buildcamera_$*; bitgen -w -g Binary:no -g CRC:Enable -g ProgPin:PullUp -g InitPin:Pullup -g TckPin:PullUp -g TdiPin:PullUp \
	  -g TdoPin:PullUp -g TmsPin:PullUp -g Disable_JTAG:No -g UnusedPin:PullDown -g UserID:0xFFFFFFFF -g OverTempPowerDown:Disable \
	  -g USR_ACCESS:None -g JTAG_XADC:Enable -g DCIUpdateMode:AsRequired -g StartUpClk:CClk -g DONE_cycle:4 -g GTS_cycle:5 -g GWE_cycle:6 \
	  -g Match_cycle:Auto -g Security:None -g ICAP_select:Auto -g DonePipe:Yes -g DriveDone:No system.ncd > OUT_bitgen.txt
	cp out/buildcamera_$*/system.bit $@


CAMERA_ADDR=192.168.42.50
CAMERA_WRITE_PATH=/tmp
CAMERA_PASS=1234

%.camera.run: out/%.camera.bit
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk1' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo '100000000' > /sys/class/fclk/fclk0/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat /sys/class/fclk/fclk0/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo '96000000' > /sys/class/fclk/fclk1/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat /sys/class/fclk/fclk1/set_rate"
###### CLOCK STUFF END
	sshpass -p $(CAMERA_PASS) scp ../platform/camera/csrc/processimage out/$*.camera.bit root@$(CAMERA_ADDR):$(CAMERA_WRITE_PATH)/.
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat $(CAMERA_WRITE_PATH)/$*.camera.bit > /dev/xdevcfg"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "$(CAMERA_WRITE_PATH)/processimage 0" 
	-sshpass -p $(CAMERA_PASS) scp root@$(CAMERA_ADDR):$(CAMERA_WRITE_PATH)/*.raw .
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "rm $(CAMERA_WRITE_PATH)/processimage $(CAMERA_WRITE_PATH)/$*.camera.bit"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_unexport"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk1' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_unexport"

%.camera1x.run: out/%.camera1x.bit
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk1' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo '100000000' > /sys/class/fclk/fclk0/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat /sys/class/fclk/fclk0/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo '96000000' > /sys/class/fclk/fclk1/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat /sys/class/fclk/fclk1/set_rate"
###### CLOCK STUFF END
	sshpass -p $(CAMERA_PASS) scp ../platform/camera1x/csrc/processimage out/$*.camera1x.bit root@$(CAMERA_ADDR):$(CAMERA_WRITE_PATH)/.
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat $(CAMERA_WRITE_PATH)/$*.camera1x.bit > /dev/xdevcfg"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "$(CAMERA_WRITE_PATH)/processimage 0" 
	-sshpass -p $(CAMERA_PASS) scp root@$(CAMERA_ADDR):$(CAMERA_WRITE_PATH)/*.raw .
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "rm $(CAMERA_WRITE_PATH)/processimage $(CAMERA_WRITE_PATH)/$*.camera1x.bit"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_unexport"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk1' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_unexport"

%.camera2.0.run: out/%.camera2.0.bit
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk1' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo '100000000' > /sys/class/fclk/fclk0/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat /sys/class/fclk/fclk0/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo '96000000' > /sys/class/fclk/fclk1/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat /sys/class/fclk/fclk1/set_rate"
###### CLOCK STUFF END
	sshpass -p $(CAMERA_PASS) scp ../platform/camera2.0/csrc/processimage out/$*.camera2.0.bit root@$(CAMERA_ADDR):$(CAMERA_WRITE_PATH)/.
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat $(CAMERA_WRITE_PATH)/$*.camera2.0.bit > /dev/xdevcfg"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "$(CAMERA_WRITE_PATH)/processimage 0" 
	-sshpass -p $(CAMERA_PASS) scp root@$(CAMERA_ADDR):$(CAMERA_WRITE_PATH)/*.raw .
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "rm $(CAMERA_WRITE_PATH)/processimage $(CAMERA_WRITE_PATH)/$*.camera2.0.bit"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_unexport"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk1' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_unexport"

out/%.axi100.bit: out/%.axi.v
	mkdir -p out/build100_$*
	# run xst, then 'help -arch zynq -command run' to get list of options
	cd out/build100_$*; echo "run -ifn ../$*.axi.v -ifmt Verilog -p xc7z100-2ffg900 -top stage -use_dsp48 No -ofn system" | xst > OUT_xst.txt
	cd out/build100_$*; ngdbuild -nt timestamp -uc ../../../platform/axi/ps7_constraints_100.ucf -uc ../../../platform/axi/system_100.ucf -p xc7z100-2ffg900  system.ngc system.ngd > OUT_ngd.txt
	cd out/build100_$*; map -detail -p xc7z100-2ffg900 -w -logic_opt off -ol high -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o system_map.ncd system.ngd system.pcf > OUT_map.txt
	cd out/build100_$*; par -w -ol high -mt off system_map.ncd system.ncd system.pcf > OUT_par.txt
	cd out/build100_$*; trce -v 3 -s 1 -n 3 -fastpaths -xml system.twx system.ncd -o system.twr system.pcf -ucf ../../platform/axi/ps7_constraint_100s.ucf -ucf ../../platform/axi/system_100.ucf > OUT_trce.txt
	cd out/build100_$*; bitgen -w -g Binary:no -g CRC:Enable -g ProgPin:PullUp -g InitPin:Pullup -g TckPin:PullUp -g TdiPin:PullUp \
	  -g TdoPin:PullUp -g TmsPin:PullUp -g Disable_JTAG:No -g UnusedPin:PullDown -g UserID:0xFFFFFFFF -g OverTempPowerDown:Disable \
	  -g USR_ACCESS:None -g JTAG_XADC:Enable -g DCIUpdateMode:AsRequired -g StartUpClk:CClk -g DONE_cycle:4 -g GTS_cycle:5 -g GWE_cycle:6 \
	  -g Match_cycle:Auto -g Security:None -g ICAP_select:Auto -g DonePipe:Yes -g DriveDone:No system.ncd > OUT_bitgen.txt
	cp out/build100_$*/system.bit $@

out/%.axi100.bit.bin: out/%.axi100.bit
	cd out/build100_$*; bootgen -w -image ../../../platform/axi/boot.bif -split bin -o i system.bin
	cp out/build100_$*/system.bit.bin $@

ZYNQ_WRITE_PATH=/var/volatile
ZYNQ_ADDR=192.168.2.2

out/%.hz.txt: out/%.axi.bit
	$(eval $@_HZl := $(shell grep Maximum out/build_$*/OUT_trce.txt  | grep -P -o "[0-9.]+" | tail -1 | tr -d '\n' | awk '{print $$1" * 1000000"}' | bc -l | xargs printf "%d"))
	echo $($@_HZl) > out/$*.hz.txt

out/%.axi.raw: out/%.axi.bit out/%.hz.txt out/%.metadata.lua
	$(eval $@_IMG := $(shell $(LUA) ../misc/extractMetadata.lua out/$*.metadata.lua inputImage))
	$(eval $@_SCALEN := $(shell $(LUA) ../misc/extractMetadata.lua out/$*.metadata.lua scaleN))
	$(eval $@_SCALED := $(shell $(LUA) ../misc/extractMetadata.lua out/$*.metadata.lua scaleD))
	$(eval $@_BPP_IN := $(shell $(LUA) ../misc/extractMetadata.lua out/$*.metadata.lua inputBytesPerPixel))
	$(eval $@_BPP_OUT := $(shell $(LUA) ../misc/extractMetadata.lua out/$*.metadata.lua outputBytesPerPixel))
	$(eval $@_OUTW := $(shell $(LUA) ../misc/extractMetadata.lua out/$*.metadata.lua outputWidth))
	$(eval $@_OUTH := $(shell $(LUA) ../misc/extractMetadata.lua out/$*.metadata.lua outputHeight))
###### SET THE CLOCK	
	$(eval $@_HZ := $(shell cat out/$*.hz.txt))
# (* second time around we can't write to fclk_export, so surpress error)
	- sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "echo '$($@_HZ)' > /sys/class/fclk/fclk0/set_rate"
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "cat /sys/class/fclk/fclk0/set_rate" > out/$*.realhz.txt
###### CLOCK STUFF END
	sshpass -p 'root' scp ../platform/axi/processimage out/$*.axi.bit $($@_IMG) root@$(ZYNQ_ADDR):$(ZYNQ_WRITE_PATH)
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "cat $(ZYNQ_WRITE_PATH)/$*.axi.bit > /dev/xdevcfg"
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "$(ZYNQ_WRITE_PATH)/processimage 805339136 $(ZYNQ_WRITE_PATH)/$($@_IMG) $(ZYNQ_WRITE_PATH)/out.raw $($@_SCALEN) $($@_SCALED) $($@_BPP_IN) $($@_BPP_OUT) $($@_OUTW) $($@_OUTH)"
	sshpass -p 'root' scp root@$(ZYNQ_ADDR):$(ZYNQ_WRITE_PATH)/out.raw out/$*.axi.raw
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "rm $(ZYNQ_WRITE_PATH)/processimage $(ZYNQ_WRITE_PATH)/$($@_IMG) $(ZYNQ_WRITE_PATH)/out.raw $(ZYNQ_WRITE_PATH)/$*.axi.bit"
	$(TERRA) ../misc/extractCycles.t out/$*.axi.raw > out/$*.axi.cycles.txt
	# keep copy for future reference
	cp out/$*.axi.cycles.txt out/build_$*


ZYNQ_100_WRITE_PATH=/tmp
ZYNQ_100_ADDR=192.168.1.10

out/%.axi100.raw: out/%.axi100.bit.bin out/%.metadata.lua
	$(eval $@_IMG := $(shell $(TERRA) ../misc/extractMetadata.t out/$*.metadata.lua inputImage))
	$(eval $@_SCALEN := $(shell $(TERRA) ../misc/extractMetadata.t out/$*.metadata.lua scaleN))
	$(eval $@_SCALED := $(shell $(TERRA) ../misc/extractMetadata.t out/$*.metadata.lua scaleD))
	$(eval $@_BPP_IN := $(shell $(TERRA) ../misc/extractMetadata.t out/$*.metadata.lua inputBytesPerPixel))
	$(eval $@_BPP_OUT := $(shell $(TERRA) ../misc/extractMetadata.t out/$*.metadata.lua outputBytesPerPixel))
	$(eval $@_OUTW := $(shell $(TERRA) ../misc/extractMetadata.t out/$*.metadata.lua outputWidth))
	$(eval $@_OUTH := $(shell $(TERRA) ../misc/extractMetadata.t out/$*.metadata.lua outputHeight))
	printf "cd /tmp\n put ../platform/axi/processimage\n put out/$*.axi100.bit.bin\n put $($@_IMG)" | sshpass -p 'root' sftp root@$(ZYNQ_100_ADDR)
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "rm -f /dev/xdevcfg"
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "mknod /dev/xdevcfg c 259 0"
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "cat $(ZYNQ_100_WRITE_PATH)/$*.axi100.bit.bin > /dev/xdevcfg"
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "$(ZYNQ_100_WRITE_PATH)/processimage 805339136 $(ZYNQ_100_WRITE_PATH)/$($@_IMG) $(ZYNQ_100_WRITE_PATH)/out.raw $($@_SCALEN) $($@_SCALED) $($@_BPP_IN) $($@_BPP_OUT) $($@_OUTW) $($@_OUTH)"
	printf "cd /tmp\n get out.raw $@" | sshpass -p 'root' sftp root@$(ZYNQ_100_ADDR)
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "rm $(ZYNQ_100_WRITE_PATH)/processimage $(ZYNQ_100_WRITE_PATH)/$($@_IMG) $(ZYNQ_100_WRITE_PATH)/out.raw $(ZYNQ_100_WRITE_PATH)/$*.axi100.bit.bin"
	$(TERRA) ../misc/extractCycles.t out/$*.axi100.raw > out/$*.axi100.cycles.txt
	# keep copy for future reference
	cp out/$*.axi100.cycles.txt out/build100_$*

# isim is crap, and if we run multiple processes at the same time in the same directory, they will clobber each other. So we need to run in different directories.
out/%.isim.raw: out/%.isim.v $(DUPS)
	mkdir -p out/sim_$*
	cd out/sim_$*; vlogcomp ../$*.sim.v
	cd out/sim_$*; fuse -o $* -lib $* -L unisim -L unimacro -top sim
	cd out/sim_$*; echo "run all" | ./$* > output.txt
	split -n 2 -d out/sim_$*/$*.sim.raw out/sim_$*/S
	mv out/sim_$*/S00 out/$*.sim.raw
	mv out/sim_$*/S01 out/$*.sim.1.raw
	$(TERRA) ../misc/extractCycles.t out/$*.sim.raw > out/$*.sim.cycles.txt
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.sim.cycles.txt out/build_$*

out/%.isim.bmp: out/%.isim.raw out/%.metadata.lua
	$(LUA) ../misc/raw2bmp.lua out/$*.sim.raw out/$*.sim.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.sim.bmp out/build_$*

out/%.isim.1.bmp: out/%.isim.raw out/%.metadata.lua
	$(LUA) ../misc/raw2bmp.lua out/$*.sim.1.raw out/$*.sim.1.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.sim.1.bmp out/build_$*

out/%.axi.bmp: out/%.axi.raw
	$(LUA) ../misc/raw2bmp.lua out/$*.axi.raw out/$*.axi.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.axi.bmp out/build_$*

out/%.axi100.bmp: out/%.axi100.raw
	$(LUA) ../misc/raw2bmp.lua out/$*.axi100.raw out/$*.axi100.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build100_$*
	cp out/$*.axi100.bmp out/build100_$*

out/%.terra.bmp: out/%.terra.raw out/%.metadata.lua
	$(LUA) ../misc/raw2bmp.lua out/$*.terra.raw out/$*.terra.bmp out/$*.metadata.lua 0
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.terra.bmp out/build_$*

out/%_half.terra.bmp: out/%_half.terra.raw out/%.metadata.lua
	$(LUA) ../misc/raw2bmp.lua out/$*_half.terra.raw out/$*_half.terra.bmp out/$*.metadata.lua 0
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*_half.terra.bmp out/build_$*

out/%.axi.correct.txt : out/%.axi.bmp
	diff out/$*.axi.bmp gold/$*.bmp > out/$*.axi.diff
	test ! -s out/$*.axi.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build_$*
	test ! -s out/$*.axi.diff && touch out/build_$*/$*.axi.correct.txt

# hack: this file is different in HW due to floating point differences, so override the check
out/sift_desc_hw.axi100.correct.txt : out/sift_desc_hw.axi100.bmp
	diff out/sift_desc_hw.axi100.bmp gold/sift_desc_hw.axi100.bmp > out/sift_desc_hw.axi100.diff
	test ! -s out/sift_desc_hw.axi100.diff && touch $@

out/%.axi100.correct.txt : out/%.axi100.bmp
	diff out/$*.axi100.bmp gold/$*.bmp > out/$*.axi100.diff
	test ! -s out/$*.axi100.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build100_$*
	test ! -s out/$*.axi100.diff && touch out/build100_$*/$*.axi100.correct.txt

out/%_half.sim.correct.txt : out/%_half.sim.bmp
	diff out/$*_half.sim.bmp gold/$*.bmp > out/$*_half.sim.diff
	test ! -s out/$*_half.sim.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build_$*
	test ! -s out/$*_half.sim.diff && touch out/build_$*/$*_half.sim.correct.txt

out/%.isim.correct.txt : out/%.isim.bmp
	diff out/$*.isim.bmp gold/$*.bmp > out/$*.isim.diff
	test ! -s out/$*.isim.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build_$*
	test ! -s out/$*.isim.diff && touch out/build_$*/$*.isim.correct.txt

out/%.isim.1.correct.txt : out/%.isim.1.bmp
	diff out/$*.isim.1.bmp gold/$*.bmp > out/$*.isim.1.diff
	test ! -s out/$*.isim.1.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build_$*
	test ! -s out/$*.isim.1.diff && touch out/build_$*/$*.isim.1.correct.txt

out/%_half.terra.correct.txt : out/%_half.terra.bmp
	diff out/$*_half.terra.bmp gold/$*.bmp > out/$*_half.terra.diff
	test ! -s out/$*_half.terra.diff && touch $@

out/%.terra.correct.txt : out/%.terra.bmp
	diff out/$*.terra.bmp gold/$*.bmp > out/$*.terra.diff
	test ! -s out/$*.terra.diff && touch $@

out/%.raw.dup : %.raw
	cat $*.raw > $@
	cat $*.raw >> $@

out/%.stats.txt : out/%.axi.bmp
	../misc/stats.sh out/build_$* out/$* $* axi $@

out/%.stats100.txt : out/%.axi100.bmp
	../misc/stats.sh out/build100_$* out/$* $* axi100 $@

# special case SIFT - write out matches as a postprocess
out/sift_hw_1080p.bmp: out/sift_hw_1080p.raw
out/sift_hw_1080p.axi.bmp: out/sift_hw_1080p.axi.raw
out/sift_hw_1080p_half.bmp: out/sift_hw_1080p_half.raw

out/sift_hw_1080p.axi.bmp out/sift_hw_1080p.bmp out/sift_hw_1080p_half.bmp:
	# cut off the axi burst padding
	head -c 8424000 $< > $@.tmp
	$(TERRA) ../misc/sift/match.t $@.tmp 1920 1080 ../misc/sift/boxes_cheesed_233x346.sift 233 346 $@.match
	echo "return {outputWidth=1920,outputHeight=1080,outputBytesPerPixel=3}" > $@.tmp.lua
	$(LUA) ../misc/raw2bmp.lua $@.match $@ $@.tmp.lua 0

#out/sift_hw.bmp: out/sift_hw.raw
#	$(TERRA) ../misc/sift/match.t out/sift_hw.raw 256 256 ../misc/sift/boxes_cheesed_233x346.sift 233 346 out/sift_hw.raw.match
#	echo "return {outputWidth=256,outputHeight=256,outputBytesPerPixel=3}" > out/sift_hw.metadata.tmp.lua
#	$(TERRA) ../misc/raw2bmp.t out/sift_hw.raw.match out/sift_hw.bmp out/sift_hw.metadata.tmp.lua 0

out/featuredescriptor.bmp: out/featuredescriptor.raw
out/featuredescriptor.axi.bmp: out/featuredescriptor.axi.raw
out/featuredescriptor_half.bmp: out/featuredescriptor_half.raw
out/sift_hw.bmp: out/sift_hw.raw
out/sift_hw.axi.bmp: out/sift_hw.axi.raw
out/sift_hw_half.bmp: out/sift_hw_half.raw

out/sift_hw.axi.bmp out/sift_hw.bmp out/sift_hw_half.bmp out/featuredescriptor.bmp out/featuredescriptor_half.bmp out/featuredescriptor.axi.bmp:
	$(TERRA) ../misc/sift/match.t $< 256 256 ../misc/sift/boxes_cheesed_233x346.sift 233 346 out/__feature.match
	echo "return {outputWidth=256,outputHeight=256,outputBytesPerPixel=3}" > out/__feature.metadata.lua
	$(LUA) ../misc/raw2bmp.lua out/__feature.match $@ out/__feature.metadata.lua 0
	rm out/__feature.match
	rm out/__feature.metadata.lua
