SRCFILES = $(wildcard *.t)
SRCS = $(filter-out harness.t examplescommon.t lk_core.t lk_tr_core.t stereo_core.t stereo_tr_core.t pyramid_core.t harris_core.t sift_core.t sift_core_hw.t campipe_core.t descriptor_core.t,$(SRCFILES))
SRCS += $(wildcard *.lua)

VERPATH = /usr/local/Cellar/verilator/3.886/share/verilator/include/

LUA = luajit

RAWS = $(wildcard *.raw)
DUPS = $(patsubst %.raw,out/%.raw.dup,$(RAWS))

# some images have intentially invalid pixels in them, so we can't compare with golds
#GOLDS = $(filter-out conv_wide_handshake.t ,$(SRCS))
GOLDS = $(SRCS)

TERRASRCS = $(filter-out underflow.t, $(SRCS))

VERILOG = $(patsubst %.t,out/%.v,$(TERRASRCS))
VERILOG += $(patsubst %.lua,out/%.v,$(TERRASRCS))

TERRA = $(patsubst %.t,out/%.raw,$(TERRASRCS))
TERRA += $(patsubst %.t,out/%_half.raw,$(TERRASRCS))
TERRA += $(patsubst %.t,out/%.bmp,$(TERRASRCS))
TERRA += $(patsubst %.t,out/%_half.bmp,$(TERRASRCS))
TERRA += $(patsubst %.t,out/%.correct.txt,$(TERRASRCS))
TERRA += $(patsubst %.t,out/%_half.correct.txt,$(TERRASRCS))

VERILATORSRCS = $(filter-out underflow.t, $(SRCS))
VERILATOR = $(patsubst %.t,out/%.verilator,$(VERILATORSRCS))
VERILATOR = $(patsubst %.t,out/%.verilator.raw,$(VERILATORSRCS))
#VERILATOR += $(patsubst %.t,out/%_half.raw,$(VERILATORSRCS))
VERILATOR += $(patsubst %.t,out/%.verilator.bmp,$(VERILATORSRCS))
#VERILATOR += $(patsubst %.t,out/%_half.bmp,$(VERILATORSRCS))
VERILATOR += $(patsubst %.t,out/%.verilator.correct.txt,$(VERILATORSRCS))
#VERILATOR += $(patsubst %.t,out/%_half.correct.txt,$(VERILATORSRCS))

# too slow
SIMSRCS = $(SRCS)
SIMSRCS := $(filter-out stereo_wide_handshake_medi.t stereo_wide_handshake_nostall_medi.t stereo_tr_medi_4.t stereo_tr_medi_8.t stereo_tr_medi_16.t ,$(SIMSRCS))
SIMSRCS := $(filter-out stereo_wide_handshake_full.t stereo_wide_handshake_nostall_full.t stereo_tr_full_4.t stereo_tr_full_8.t stereo_tr_full_16.t stereo_tr_rgba_full_32.t,$(SIMSRCS))
SIMSRCS := $(filter-out stereo_ov7660.t ,$(SIMSRCS))
SIMSRCS := $(filter-out lk_wide_handshake_4_4_float.t lk_wide_handshake_6_4_axi.t lk_wide_handshake_6_4_float.t lk_wide_handshake_6_1_axi.t lk_wide_handshake_4_4_axi.t lk_wide_handshake_4_1_axi.t lk_tr_handshake_4_4_axi.t lk_tr_handshake_6_6.t lk_tr_handshake_6_6_axi.t lk_tr_handshake_6_1.t lk_tr_handshake_6_1_axi.t lk_tr_handshake_6_2.t lk_tr_handshake_6_2_axi.t lk_tr_handshake_6_3.t lk_tr_handshake_6_3_axi.t ,$(SIMSRCS))
SIMSRCS := $(filter-out lk_wide_handshake_12_1_float.t lk_wide_handshake_12_1_axi.t lk_wide_handshake_12_1_axi_nostall.t lk_tr_handshake_12_1_axi.t lk_tr_handshake_12_2_axi.t lk_tr_handshake_12_3_axi.t lk_tr_handshake_12_4_axi.t lk_tr_handshake_12_6_axi.t lk_tr_handshake_12_12_axi.t,$(SIMSRCS))
SIMSRCS := $(filter-out campipe_512.t campipe_ov7660.t,$(SIMSRCS))
SIMSRCS := $(filter-out pyramid_large_1.t pyramid_large_2.t pyramid_large_3.t pyramid_large_4.t pyramid_large_tr_1.t pyramid_large_tr_2.t pyramid_large_tr_3.t pyramid_large_tr_4.t pyramid_large_nofifo_tr_1.t pyramid_large_nofifo_tr_2.t pyramid_large_nofifo_tr_3.t pyramid_large_nofifo_tr_4.t,$(SIMSRCS))
SIMSRCS := $(filter-out pyramid_large_taps_1.t pyramid_large_taps_2.t pyramid_large_taps_3.t pyramid_large_taps_4.t pyramid_large_nofifo_taps_1.t pyramid_large_nofifo_taps_2.t pyramid_large_nofifo_taps_3.t pyramid_large_nofifo_taps_4.t,$(SIMSRCS))
SIMSRCS := $(filter-out convpadcrop_wide_handshake_4_1_1080p.t convpadcrop_wide_handshake_4_2_1080p.t convpadcrop_wide_handshake_4_4_1080p.t convpadcrop_wide_handshake_4_8_1080p.t convpadcrop_wide_handshake_8_1_1080p.t convpadcrop_wide_handshake_8_2_1080p.t convpadcrop_wide_handshake_8_4_1080p.t convpadcrop_wide_handshake_8_8_1080p.t,$(SIMSRCS))
SIMSRCS := $(filter-out convpadcrop_wide_handshake_8_1_1080p_nostall.t convpadcrop_wide_handshake_8_2_1080p_nostall.t convpadcrop_wide_handshake_8_4_1080p_nostall.t convpadcrop_wide_handshake_8_8_1080p_nostall.t,$(SIMSRCS))
SIMSRCS := $(filter-out conv_tr_handshake_4_1_1080p.t conv_tr_handshake_4_2_1080p.t conv_tr_handshake_4_4_1080p.t conv_tr_handshake_4_8_1080p.t conv_tr_handshake_8_1_1080p.t conv_tr_handshake_8_2_1080p.t conv_tr_handshake_8_4_1080p.t conv_tr_handshake_8_8_1080p.t,$(SIMSRCS))
#nyi
SIMSRCS := $(filter-out fixed_float_inv.t harris_corner.t filterseq.t harris_filterseq.t sift_float.t sift_desc.t sift_desc_hw.t sift_hw.t sift_hw_1080p.t,$(SIMSRCS))

SIM = $(patsubst %.t,out/%.sim.bmp,$(SIMSRCS))
SIM += $(patsubst %.t,out/%.sim.1.bmp,$(SIMSRCS))
SIM += $(patsubst %.t,out/%_half.sim.bmp,$(SIMSRCS))
SIM += $(patsubst %.t,out/%.sim.raw,$(SIMSRCS))
SIM += $(patsubst %.t,out/%_half.sim.raw,$(SIMSRCS))
SIM += $(patsubst %.t,out/%.sim.v,$(SIMSRCS))
SIM += $(patsubst %.t,out/%_half.sim.v,$(SIMSRCS))
SIM += $(patsubst %.t,out/%.sim.correct.txt,$(SIMSRCS))
SIM += $(patsubst %.t,out/%.sim.1.correct.txt,$(SIMSRCS))
SIM += $(patsubst %.t,out/%_half.sim.correct.txt,$(SIMSRCS))

AXI100SRCS = $(filter-out linebufferpartial_handshake_1.t linebufferpartial_handshake_2.t linebufferpartial_handshake_4.t convpadcrop_handshake.t reduceseq_handshake.t  stereo_wide_handshake_medi.t,$(SRCS))
AXI100SRCS := $(filter-out lk_tr_handshake_4_4.t lk_tr_handshake_6_6.t lk_tr_handshake_6_1.t lk_tr_handshake_6_2.t lk_tr_handshake_6_3.t lk_wide_handshake_12_1_float.t,$(AXI100SRCS))
AXI100SRCS := $(filter-out lk_wide_handshake_4_4_float.t lk_wide_handshake_6_4_float.t lk_wide_handshake_4_4.t lk_wide_handshake_4_1.t,$(AXI100SRCS))
AXI100SRCS := $(filter-out filterseq.t harris_filterseq.t sift_float.t sift_desc.t,$(AXI100SRCS))

# filter out stuff that's too big for the 7020
AXISRCS = $(AXI100SRCS)
AXISRCS := $(filter-out stereo_wide_handshake_nostall_full.t stereo_wide_handshake_nostall_medi.t stereo_wide_handshake_full.t,$(AXISRCS))
AXISRCS := $(filter-out lk_tr_handshake_12_1_axi.t lk_tr_handshake_12_2_axi.t lk_tr_handshake_12_3_axi.t lk_tr_handshake_12_4_axi.t lk_tr_handshake_12_6_axi.t lk_tr_handshake_6_1_axi.t lk_wide_handshake_4_4_axi.t lk_wide_handshake_6_4_axi.t,$(AXISRCS))
AXISRCS := $(filter-out lk_wide_handshake_12_1_axi_nostall.t lk_wide_handshake_12_1_axi.t,$(AXISRCS))
AXISRCS := $(filter-out pyramid_large_nofifo_taps_4.t pyramid_large_taps_3.t pyramid_taps_3.t pyramid_taps_4.t pyramid_large_taps_4.t,$(AXISRCS))

AXIBITS = $(patsubst %.t,out/%.axi.v,$(AXISRCS))
AXIBITS += $(patsubst %.t,out/%.axi.bit,$(AXISRCS))

AXIBITS100 = $(patsubst %.t,out/%.axi100.bit,$(AXI100SRCS))
AXIBITS100 += $(patsubst %.t,out/%.axi100.bit.bin,$(AXI100SRCS))

AXI = $(patsubst %.t,out/%.axi.raw,$(AXISRCS))
AXI += $(patsubst %.t,out/%.axi.bmp,$(AXISRCS))
AXI += $(patsubst %.t,out/%.axi.correct.txt,$(AXISRCS))
AXI += $(patsubst %.t,out/%.hz.txt,$(AXISRCS))
AXI += $(AXIBITS)

AXI100 = $(patsubst %.t,out/%.axi100.correct.txt,$(AXI100SRCS))
AXI100 += $(patsubst %.t,out/%.axi100.raw,$(AXI100SRCS))
AXI100 += $(patsubst %.t,out/%.axi100.bmp,$(AXI100SRCS))
AXI100 += $(AXIBITS100)

STATS = $(patsubst %.t,out/%.stats.txt,$(AXISRCS))

STATS100 = $(patsubst %.t,out/%.stats100.txt,$(AXI100SRCS))

CAMERASRCS = stereo_ov7660.t 2xov7660.t campipe_ov7660.t
CAMERABITS = $(patsubst %.t,out/%.axi.v,$(CAMERASRCS))
CAMERABITS += $(patsubst %.t,out/%.camera.bit,$(CAMERASRCS))


RES = $(TERRA)
RES += $(VERILATOR)
RES += $(SIM)
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

terra: $(TERRA)

verilator: $(VERILATOR)

sim: $(SIM)

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
	terra $<
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.v out/build_$*

out/%.v out/%.metadata.lua: %.lua
	$(LUA) $<
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.v out/build_$*

out/%.raw out/%_half.raw: %.t
	terra $< terrasim
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.cycles.txt out/build_$*

out/%.sim.v out/%_half.sim.v: %.t 
	terra $< isim
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.sim.v out/build_$*

out/%.axi.v: %.t 
	terra $< axi
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.axi.v out/build_$*
	mkdir -p out/build100_$*
	- cp out/$*.axi.v out/build100_$*

#/opt/Xilinx/14.5/ISE_DS/ISE/verilog/src/unisims
#	verilator -cc -Mdir out/$*_verilator  /opt/Xilinx/14.5/ISE_DS/ISE/verilog/src/unisims/RAMB16_S36_S36.v out/$*.verilator.v
out/%.verilator: out/%.v out/%.metadata.lua
	$(eval $@_TOP := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua topModule))
	verilator -cc -Mdir out/$*_verilator out/$*.v ../platform/verilator/RAMB16_S36_S36.v ../platform/verilator/RAMB16_S9_S9.v --top-module $($@_TOP)
	terra ../platform/verilator/makeHarness.lua out/$*.metadata.lua $* > out/$*.verilator.cpp
	g++ -I${VERPATH} out/$*_verilator/V$($@_TOP).cpp out/$*_verilator/V$($@_TOP)__Syms.cpp ${VERPATH}verilated.cpp out/$*.verilator.cpp -o $@

out/%.verilator.raw: out/%.verilator
	./out/$*.verilator

out/%.verilator.bmp: out/%.verilator.raw out/%.metadata.lua
	terra ../misc/raw2bmp.t out/$*.verilator.raw out/$*.verilator.bmp out/$*.metadata.lua 0
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.verilator.bmp out/build_$*

out/%.verilator.correct.txt : out/%.verilator.bmp
	diff out/$*.verilator.bmp gold/$*.bmp > out/$*.verilator.diff
	test ! -s out/$*.verilator.diff && touch $@
	# keep copy for future reference
#	mkdir -p out/build_$*
#	test ! -s out/$*.verilator.diff && touch $@

out/%.axi.bit: out/%.axi.v
	mkdir -p out/build_$*
	# run xst, then 'help -arch zynq -command run' to get list of options
	cd out/build_$*; echo "run -ifn ../$*.axi.v -ifmt Verilog -p xc7z020-clg484-1 -top stage -use_dsp48 No -ofn system" | xst > OUT_xst.txt
	cd out/build_$*; ngdbuild -nt timestamp -uc ../../../platform/axi/ps7_constraints.ucf -uc ../../../platform/axi/system.ucf -p xc7z020-clg484-1 system.ngc system.ngd > OUT_ngd.txt
	cd out/build_$*; map -detail -p xc7z020-clg484-1 -w -logic_opt off -ol high -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o system_map.ncd system.ngd system.pcf > OUT_map.txt
	cd out/build_$*; par -w -ol high -mt off system_map.ncd system.ncd system.pcf > OUT_par.txt
	cd out/build_$*; trce -v 3 -s 1 -n 3 -fastpaths -xml system.twx system.ncd -o system.twr system.pcf -ucf ../../platform/axi/ps7_constraints.ucf -ucf ../../platform/axi/system.ucf > OUT_trce.txt
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

out/%.axi.raw: out/%.axi.bit out/%.hz.txt
	$(eval $@_IMG := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua inputImage))
	$(eval $@_SCALEN := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua scaleN))
	$(eval $@_SCALED := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua scaleD))
	$(eval $@_BPP_IN := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua inputBytesPerPixel))
	$(eval $@_BPP_OUT := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua outputBytesPerPixel))
	$(eval $@_OUTW := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua outputWidth))
	$(eval $@_OUTH := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua outputHeight))
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
	terra ../misc/extractCycles.t out/$*.axi.raw > out/$*.axi.cycles.txt
	# keep copy for future reference
	cp out/$*.axi.cycles.txt out/build_$*


ZYNQ_100_WRITE_PATH=/tmp
ZYNQ_100_ADDR=192.168.1.10

out/%.axi100.raw: out/%.axi100.bit.bin
	$(eval $@_IMG := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua inputImage))
	$(eval $@_SCALEN := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua scaleN))
	$(eval $@_SCALED := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua scaleD))
	$(eval $@_BPP_IN := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua inputBytesPerPixel))
	$(eval $@_BPP_OUT := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua outputBytesPerPixel))
	$(eval $@_OUTW := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua outputWidth))
	$(eval $@_OUTH := $(shell terra ../misc/extractMetadata.t out/$*.metadata.lua outputHeight))
	printf "cd /tmp\n put ../platform/axi/processimage\n put out/$*.axi100.bit.bin\n put $($@_IMG)" | sshpass -p 'root' sftp root@$(ZYNQ_100_ADDR)
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "rm -f /dev/xdevcfg"
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "mknod /dev/xdevcfg c 259 0"
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "cat $(ZYNQ_100_WRITE_PATH)/$*.axi100.bit.bin > /dev/xdevcfg"
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "$(ZYNQ_100_WRITE_PATH)/processimage 805339136 $(ZYNQ_100_WRITE_PATH)/$($@_IMG) $(ZYNQ_100_WRITE_PATH)/out.raw $($@_SCALEN) $($@_SCALED) $($@_BPP_IN) $($@_BPP_OUT) $($@_OUTW) $($@_OUTH)"
	printf "cd /tmp\n get out.raw $@" | sshpass -p 'root' sftp root@$(ZYNQ_100_ADDR)
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "rm $(ZYNQ_100_WRITE_PATH)/processimage $(ZYNQ_100_WRITE_PATH)/$($@_IMG) $(ZYNQ_100_WRITE_PATH)/out.raw $(ZYNQ_100_WRITE_PATH)/$*.axi100.bit.bin"
	terra ../misc/extractCycles.t out/$*.axi100.raw > out/$*.axi100.cycles.txt
	# keep copy for future reference
	cp out/$*.axi100.cycles.txt out/build100_$*

# isim is crap, and if we run multiple processes at the same time in the same directory, they will clobber each other. So we need to run in different directories.
out/%.sim.raw: out/%.sim.v $(DUPS)
	mkdir -p out/sim_$*
	cd out/sim_$*; vlogcomp ../$*.sim.v
	cd out/sim_$*; fuse -o $* -lib $* -L unisim -L unimacro -top sim
	cd out/sim_$*; echo "run all" | ./$* > output.txt
	split -n 2 -d out/sim_$*/$*.sim.raw out/sim_$*/S
	mv out/sim_$*/S00 out/$*.sim.raw
	mv out/sim_$*/S01 out/$*.sim.1.raw
	terra ../misc/extractCycles.t out/$*.sim.raw > out/$*.sim.cycles.txt
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.sim.cycles.txt out/build_$*

out/%.sim.bmp: out/%.sim.raw out/%.metadata.lua
	terra ../misc/raw2bmp.t out/$*.sim.raw out/$*.sim.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.sim.bmp out/build_$*

out/%.sim.1.bmp: out/%.sim.raw out/%.metadata.lua
	terra ../misc/raw2bmp.t out/$*.sim.1.raw out/$*.sim.1.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.sim.1.bmp out/build_$*

out/%.axi.bmp: out/%.axi.raw
	terra ../misc/raw2bmp.t out/$*.axi.raw out/$*.axi.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.axi.bmp out/build_$*

out/%.axi100.bmp: out/%.axi100.raw
	terra ../misc/raw2bmp.t out/$*.axi100.raw out/$*.axi100.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build100_$*
	cp out/$*.axi100.bmp out/build100_$*

out/%.bmp: out/%.raw out/%.metadata.lua
	terra ../misc/raw2bmp.t out/$*.raw out/$*.bmp out/$*.metadata.lua 0
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.bmp out/build_$*

out/%_half.bmp: out/%_half.raw out/%.metadata.lua
	terra ../misc/raw2bmp.t out/$*_half.raw out/$*_half.bmp out/$*.metadata.lua 0
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*_half.bmp out/build_$*

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

out/%.sim.correct.txt : out/%.sim.bmp
	diff out/$*.sim.bmp gold/$*.bmp > out/$*.sim.diff
	test ! -s out/$*.sim.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build_$*
	test ! -s out/$*.sim.diff && touch out/build_$*/$*.sim.correct.txt

out/%.sim.1.correct.txt : out/%.sim.1.bmp
	diff out/$*.sim.1.bmp gold/$*.bmp > out/$*.sim.1.diff
	test ! -s out/$*.sim.1.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build_$*
	test ! -s out/$*.sim.1.diff && touch out/build_$*/$*.sim.1.correct.txt

out/%_half.correct.txt : out/%_half.bmp
	diff out/$*_half.bmp gold/$*.bmp > out/$*_half.diff
	test ! -s out/$*_half.diff && touch $@

out/%.correct.txt : out/%.bmp
	diff out/$*.bmp gold/$*.bmp > out/$*.diff
	test ! -s out/$*.diff && touch $@

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
	terra ../misc/sift/match.t $@.tmp 1920 1080 ../misc/sift/boxes_cheesed_233x346.sift 233 346 $@.match
	echo "return {outputWidth=1920,outputHeight=1080,outputBytesPerPixel=3}" > $@.tmp.lua
	terra ../misc/raw2bmp.t $@.match $@ $@.tmp.lua 0

#out/sift_hw.bmp: out/sift_hw.raw
#	terra ../misc/sift/match.t out/sift_hw.raw 256 256 ../misc/sift/boxes_cheesed_233x346.sift 233 346 out/sift_hw.raw.match
#	echo "return {outputWidth=256,outputHeight=256,outputBytesPerPixel=3}" > out/sift_hw.metadata.tmp.lua
#	terra ../misc/raw2bmp.t out/sift_hw.raw.match out/sift_hw.bmp out/sift_hw.metadata.tmp.lua 0

out/featuredescriptor.bmp: out/featuredescriptor.raw
out/featuredescriptor.axi.bmp: out/featuredescriptor.axi.raw
out/featuredescriptor_half.bmp: out/featuredescriptor_half.raw
out/sift_hw.bmp: out/sift_hw.raw
out/sift_hw.axi.bmp: out/sift_hw.axi.raw
out/sift_hw_half.bmp: out/sift_hw_half.raw

out/sift_hw.axi.bmp out/sift_hw.bmp out/sift_hw_half.bmp out/featuredescriptor.bmp out/featuredescriptor_half.bmp out/featuredescriptor.axi.bmp:
	terra ../misc/sift/match.t $< 256 256 ../misc/sift/boxes_cheesed_233x346.sift 233 346 out/__feature.match
	echo "return {outputWidth=256,outputHeight=256,outputBytesPerPixel=3}" > out/__feature.metadata.lua
	terra ../misc/raw2bmp.t out/__feature.match $@ out/__feature.metadata.lua 0
	rm out/__feature.match
	rm out/__feature.metadata.lua
