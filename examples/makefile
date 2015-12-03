SRCFILES = $(wildcard *.t)
SRCS = $(filter-out harness.t examplescommon.t lk_core.t lk_tr_core.t stereo_core.t stereo_tr_core.t pyramid_core.t harris_core.t,$(SRCFILES))

RAWS = $(wildcard *.raw)
DUPS = $(patsubst %.raw,out/%.raw.dup,$(RAWS))

# some images have intentially invalid pixels in them, so we can't compare with golds
#GOLDS = $(filter-out conv_wide_handshake.t ,$(SRCS))
GOLDS = $(SRCS)

TERRASRCS = $(filter-out underflow.t, $(SRCS))

TERRA = $(patsubst %.t,out/%.raw,$(TERRASRCS))
TERRA += $(patsubst %.t,out/%_half.raw,$(TERRASRCS))
TERRA += $(patsubst %.t,out/%.bmp,$(TERRASRCS))
TERRA += $(patsubst %.t,out/%_half.bmp,$(TERRASRCS))
TERRA += $(patsubst %.t,out/%.correct.txt,$(TERRASRCS))
TERRA += $(patsubst %.t,out/%_half.correct.txt,$(TERRASRCS))

# too slow
SIMSRCS = $(SRCS)
SIMSRCS := $(filter-out stereo_wide_handshake_medi.t stereo_wide_handshake_nostall_medi.t stereo_tr_medi_4.t stereo_tr_medi_8.t stereo_tr_medi_16.t ,$(SIMSRCS))
SIMSRCS := $(filter-out stereo_wide_handshake_full.t stereo_wide_handshake_nostall_full.t stereo_tr_full_4.t stereo_tr_full_8.t stereo_tr_full_16.t ,$(SIMSRCS))
SIMSRCS := $(filter-out lk_wide_handshake_4_4_float.t lk_wide_handshake_6_4_axi.t lk_wide_handshake_6_4_float.t lk_wide_handshake_6_1_axi.t lk_wide_handshake_4_4_axi.t lk_wide_handshake_4_1_axi.t lk_tr_handshake_4_4_axi.t lk_tr_handshake_6_6.t lk_tr_handshake_6_6_axi.t lk_tr_handshake_6_1.t lk_tr_handshake_6_1_axi.t lk_tr_handshake_6_2.t lk_tr_handshake_6_2_axi.t lk_tr_handshake_6_3.t lk_tr_handshake_6_3_axi.t ,$(SIMSRCS))
SIMSRCS := $(filter-out lk_wide_handshake_12_1_float.t lk_wide_handshake_12_1_axi.t lk_wide_handshake_12_1_axi_nostall.t lk_tr_handshake_12_1_axi.t lk_tr_handshake_12_2_axi.t lk_tr_handshake_12_3_axi.t lk_tr_handshake_12_4_axi.t lk_tr_handshake_12_6_axi.t lk_tr_handshake_12_12_axi.t,$(SIMSRCS))
SIMSRCS := $(filter-out campipe_512.t campipe_ov7660.t,$(SIMSRCS))
SIMSRCS := $(filter-out pyramid_large_1.t pyramid_large_2.t pyramid_large_3.t pyramid_large_4.t pyramid_large_tr_1.t pyramid_large_tr_2.t pyramid_large_tr_3.t pyramid_large_tr_4.t pyramid_large_nofifo_tr_1.t pyramid_large_nofifo_tr_2.t pyramid_large_nofifo_tr_3.t pyramid_large_nofifo_tr_4.t,$(SIMSRCS))
SIMSRCS := $(filter-out pyramid_large_taps_1.t pyramid_large_taps_2.t pyramid_large_taps_3.t pyramid_large_taps_4.t pyramid_large_nofifo_taps_1.t pyramid_large_nofifo_taps_2.t pyramid_large_nofifo_taps_3.t pyramid_large_nofifo_taps_4.t,$(SIMSRCS))
SIMSRCS := $(filter-out convpadcrop_wide_handshake_4_1_1080p.t convpadcrop_wide_handshake_4_2_1080p.t convpadcrop_wide_handshake_4_4_1080p.t convpadcrop_wide_handshake_4_8_1080p.t convpadcrop_wide_handshake_8_1_1080p.t convpadcrop_wide_handshake_8_2_1080p.t convpadcrop_wide_handshake_8_4_1080p.t convpadcrop_wide_handshake_8_8_1080p.t,$(SIMSRCS))
#nyi
SIMSRCS := $(filter-out harris.t filterseq.t,$(SIMSRCS))

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

AXISRCS = $(filter-out linebufferpartial_handshake_1.t linebufferpartial_handshake_2.t linebufferpartial_handshake_4.t convpadcrop_handshake.t reduceseq_handshake.t  stereo_wide_handshake_medi.t lk_wide_handshake_4_4_float.t lk_wide_handshake_6_4_float.t lk_wide_handshake_4_4.t lk_tr_handshake_4_4.t lk_tr_handshake_6_6.t lk_tr_handshake_6_1.t lk_tr_handshake_6_2.t lk_tr_handshake_6_3.t lk_wide_handshake_12_1_float.t,$(SRCS))

AXI100SRCS = $(filter-out linebufferpartial_handshake_1.t linebufferpartial_handshake_2.t linebufferpartial_handshake_4.t convpadcrop_handshake.t reduceseq_handshake.t lk_wide_handshake_4_4_float.t  lk_wide_handshake_6_4_float.t lk_wide_handshake_4_4.t lk_tr_handshake_4_4.t lk_tr_handshake_6_6.t lk_tr_handshake_6_1.t lk_tr_handshake_6_2.t lk_tr_handshake_6_3.t lk_wide_handshake_12_1_float.t,$(SRCS))

AXIBITS = $(patsubst %.t,out/%.axi.v,$(AXISRCS))
AXIBITS += $(patsubst %.t,out/%.axi.bit,$(AXISRCS))

AXIBITS100 = $(patsubst %.t,out/%.axi100.bit,$(AXI100SRCS))
AXIBITS100 += $(patsubst %.t,out/%.axi100.bit.bin,$(AXI100SRCS))

AXI = $(patsubst %.t,out/%.axi.raw,$(AXISRCS))
AXI += $(patsubst %.t,out/%.axi.bmp,$(AXISRCS))
AXI += $(patsubst %.t,out/%.axi.correct.txt,$(AXISRCS))
AXI += $(AXIBITS)

AXI100 = $(patsubst %.t,out/%.axi100.correct.txt,$(AXI100SRCS))
AXI100 += $(patsubst %.t,out/%.axi100.raw,$(AXI100SRCS))
AXI100 += $(patsubst %.t,out/%.axi100.bmp,$(AXI100SRCS))
AXI100 += $(AXIBITS100)

STATS = $(patsubst %.t,out/%.stats.txt,$(AXISRCS))

STATS100 = $(patsubst %.t,out/%.stats100.txt,$(AXI100SRCS))

RES = $(TERRA)
RES += $(SIM)
RES += $(AXI)

CD = cd out;
all: $(RES)

dups: $(DUPS)

terra: $(TERRA)

sim: $(SIM)

stats: $(STATS)

stats100: $(STATS100)

axi: $(AXI)

axi100: $(AXI100)

axibits: $(AXIBITS)

axibits100: $(AXIBITS100)

clean:
	rm -Rf out/*

out/%.raw out/%_half.raw out/%.sim.v out/%_half.sim.v out/%.axi.v: %.t 
	terra $<
	# keep copy for future reference
	mkdir -p out/build_$*
	- cp out/$*.axi.v out/build_$*
	- cp out/$*.sim.v out/build_$*
	- cp out/$*.cycles.txt out/build_$*

#	$(CD) xst -ifn ../../extras/helloaxi/system.xst

out/%.axi.bit: out/%.axi.v
	mkdir -p out/build_$*
	# run xst, then 'help -arch zynq -command run' to get list of options
	cd out/build_$*; echo "run -ifn ../$*.axi.v -ifmt Verilog -p xc7z020-clg484-1 -top stage -use_dsp48 No -ofn system" | xst > OUT_xst.txt
	cd out/build_$*; ngdbuild -nt timestamp -uc ../../../extras/helloaxi/ps7_constraints.ucf -uc ../../../extras/helloaxi/system.ucf -p xc7z020-clg484-1 system.ngc system.ngd > OUT_ngd.txt
	cd out/build_$*; map -detail -p xc7z020-clg484-1 -w -logic_opt off -ol high -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o system_map.ncd system.ngd system.pcf > OUT_map.txt
	cd out/build_$*; par -w -ol high -mt off system_map.ncd system.ncd system.pcf > OUT_par.txt
	cd out/build_$*; trce -v 3 -s 1 -n 3 -fastpaths -xml system.twx system.ncd -o system.twr system.pcf -ucf ../../extras/helloaxi/ps7_constraints.ucf -ucf ../../extras/helloaxi/system.ucf > OUT_trce.txt
	cd out/build_$*; bitgen -w -g Binary:no -g CRC:Enable -g ProgPin:PullUp -g InitPin:Pullup -g TckPin:PullUp -g TdiPin:PullUp \
	  -g TdoPin:PullUp -g TmsPin:PullUp -g Disable_JTAG:No -g UnusedPin:PullDown -g UserID:0xFFFFFFFF -g OverTempPowerDown:Disable \
	  -g USR_ACCESS:None -g JTAG_XADC:Enable -g DCIUpdateMode:AsRequired -g StartUpClk:CClk -g DONE_cycle:4 -g GTS_cycle:5 -g GWE_cycle:6 \
	  -g Match_cycle:Auto -g Security:None -g ICAP_select:Auto -g DonePipe:Yes -g DriveDone:No system.ncd > OUT_bitgen.txt
	cp out/build_$*/system.bit $@

out/%.axi100.bit: out/%.axi.v
	mkdir -p out/build100_$*
	# run xst, then 'help -arch zynq -command run' to get list of options
	cd out/build100_$*; echo "run -ifn ../$*.axi.v -ifmt Verilog -p xc7z100-2ffg900 -top stage -use_dsp48 No -ofn system" | xst > OUT_xst.txt
	cd out/build100_$*; ngdbuild -nt timestamp -uc ../../../extras/helloaxi/ps7_constraints_100.ucf -uc ../../../extras/helloaxi/system_100.ucf -p xc7z100-2ffg900  system.ngc system.ngd > OUT_ngd.txt
	cd out/build100_$*; map -detail -p xc7z100-2ffg900 -w -logic_opt off -ol high -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o system_map.ncd system.ngd system.pcf > OUT_map.txt
	cd out/build100_$*; par -w -ol high -mt off system_map.ncd system.ncd system.pcf > OUT_par.txt
	cd out/build100_$*; trce -v 3 -s 1 -n 3 -fastpaths -xml system.twx system.ncd -o system.twr system.pcf -ucf ../../extras/helloaxi/ps7_constraint_100s.ucf -ucf ../../extras/helloaxi/system_100.ucf > OUT_trce.txt
	cd out/build100_$*; bitgen -w -g Binary:no -g CRC:Enable -g ProgPin:PullUp -g InitPin:Pullup -g TckPin:PullUp -g TdiPin:PullUp \
	  -g TdoPin:PullUp -g TmsPin:PullUp -g Disable_JTAG:No -g UnusedPin:PullDown -g UserID:0xFFFFFFFF -g OverTempPowerDown:Disable \
	  -g USR_ACCESS:None -g JTAG_XADC:Enable -g DCIUpdateMode:AsRequired -g StartUpClk:CClk -g DONE_cycle:4 -g GTS_cycle:5 -g GWE_cycle:6 \
	  -g Match_cycle:Auto -g Security:None -g ICAP_select:Auto -g DonePipe:Yes -g DriveDone:No system.ncd > OUT_bitgen.txt
	cp out/build100_$*/system.bit $@

out/%.axi100.bit.bin: out/%.axi100.bit
	cd out/build100_$*; bootgen -w -image ../../../extras/helloaxi/boot.bif -split bin -o i system.bin
	cp out/build100_$*/system.bit.bin $@

ZYNQ_WRITE_PATH=/var/volatile
ZYNQ_ADDR=192.168.2.2

out/%.axi.raw: out/%.axi.bit
	$(eval $@_IMG := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua inputImage))
	$(eval $@_SCALEN := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua scaleN))
	$(eval $@_SCALED := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua scaleD))
	$(eval $@_BPP_IN := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua inputBytesPerPixel))
	$(eval $@_BPP_OUT := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua outputBytesPerPixel))
###### SET THE CLOCK	
	- grep Maximum out/build_$*/OUT_trce.txt  | grep -P -o "[0-9.]+" | tail -1 | tr -d '\n' | awk '{print $$1" * 1000000"}' | bc -l | xargs printf "%d" > out/$*.hz.txt
# (* second time around we can't write to fclk_export, so surpress error)
	- sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "echo '$(shell cat out/$*.hz.txt)' > /sys/class/fclk/fclk0/set_rate"
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "cat /sys/class/fclk/fclk0/set_rate"
###### CLOCK STUFF END
	sshpass -p 'root' scp ../extras/helloaxi/processimage out/$*.axi.bit $($@_IMG) root@$(ZYNQ_ADDR):$(ZYNQ_WRITE_PATH)
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "cat $(ZYNQ_WRITE_PATH)/$*.axi.bit > /dev/xdevcfg"
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "$(ZYNQ_WRITE_PATH)/processimage 805339136 $(ZYNQ_WRITE_PATH)/$($@_IMG) $(ZYNQ_WRITE_PATH)/out.raw $($@_SCALEN) $($@_SCALED) $($@_BPP_IN) $($@_BPP_OUT)"
	sshpass -p 'root' scp root@$(ZYNQ_ADDR):$(ZYNQ_WRITE_PATH)/out.raw out/$*.axi.raw
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "rm $(ZYNQ_WRITE_PATH)/processimage $(ZYNQ_WRITE_PATH)/$($@_IMG) $(ZYNQ_WRITE_PATH)/out.raw $(ZYNQ_WRITE_PATH)/$*.axi.bit"
	terra ../extras/extractCycles.t out/$*.axi.raw > out/$*.axi.cycles.txt
	# keep copy for future reference
	cp out/$*.axi.cycles.txt out/build_$*


ZYNQ_100_WRITE_PATH=/tmp
ZYNQ_100_ADDR=192.168.1.10

out/%.axi100.raw: out/%.axi100.bit.bin
	$(eval $@_IMG := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua inputImage))
	$(eval $@_SCALEN := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua scaleN))
	$(eval $@_SCALED := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua scaleD))
	$(eval $@_BPP_IN := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua inputBytesPerPixel))
	$(eval $@_BPP_OUT := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua outputBytesPerPixel))
	printf "cd /tmp\n put ../extras/helloaxi/processimage\n put out/$*.axi100.bit.bin\n put $($@_IMG)" | sshpass -p 'root' sftp root@$(ZYNQ_100_ADDR)
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "rm -f /dev/xdevcfg"
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "mknod /dev/xdevcfg c 259 0"
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "cat $(ZYNQ_100_WRITE_PATH)/$*.axi100.bit.bin > /dev/xdevcfg"
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "$(ZYNQ_100_WRITE_PATH)/processimage 805339136 $(ZYNQ_100_WRITE_PATH)/$($@_IMG) $(ZYNQ_100_WRITE_PATH)/out.raw $($@_SCALEN) $($@_SCALED) $($@_BPP_IN) $($@_BPP_OUT)"
	printf "cd /tmp\n get out.raw $@" | sshpass -p 'root' sftp root@$(ZYNQ_100_ADDR)
	sshpass -p 'root' ssh root@$(ZYNQ_100_ADDR) "rm $(ZYNQ_100_WRITE_PATH)/processimage $(ZYNQ_100_WRITE_PATH)/$($@_IMG) $(ZYNQ_100_WRITE_PATH)/out.raw $(ZYNQ_100_WRITE_PATH)/$*.axi100.bit.bin"
	terra ../extras/extractCycles.t out/$*.axi100.raw > out/$*.axi100.cycles.txt
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
	terra ../extras/extractCycles.t out/$*.sim.raw > out/$*.sim.cycles.txt
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.sim.cycles.txt out/build_$*

out/%.sim.bmp: out/%.sim.raw
	terra ../extras/raw2bmp.t out/$*.sim.raw out/$*.sim.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.sim.bmp out/build_$*

out/%.sim.1.bmp: out/%.sim.raw
	terra ../extras/raw2bmp.t out/$*.sim.1.raw out/$*.sim.1.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.sim.1.bmp out/build_$*

out/%.axi.bmp: out/%.axi.raw
	terra ../extras/raw2bmp.t out/$*.axi.raw out/$*.axi.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.axi.bmp out/build_$*

out/%.axi100.bmp: out/%.axi100.raw
	terra ../extras/raw2bmp.t out/$*.axi100.raw out/$*.axi100.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build100_$*
	cp out/$*.axi100.bmp out/build100_$*

out/%.bmp: out/%.raw
	terra ../extras/raw2bmp.t out/$*.raw out/$*.bmp out/$*.metadata.lua 0
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.bmp out/build_$*

out/%.axi.correct.txt : out/%.axi.bmp
	diff out/$*.axi.bmp gold/$*.bmp > out/$*.axi.diff
	test ! -s out/$*.axi.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build_$*
	test ! -s out/$*.axi.diff && touch out/build_$*/$*.axi.correct.txt

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
	../extras/stats.sh out/build_$* out/$* $* axi $@

out/%.stats100.txt : out/%.axi100.bmp
	../extras/stats.sh out/build100_$* out/$* $* axi100 $@
