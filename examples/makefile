SRCFILES = $(wildcard *.t)
SRCS = $(filter-out harness.t,$(SRCFILES))

# some images have intentially invalid pixels in them, so we can't compare with golds
#GOLDS = $(filter-out conv_wide_handshake.t ,$(SRCS))
GOLDS = $(SRCS)
RES = $(patsubst %.t,out/%.bmp,$(SRCS))
RES += $(patsubst %.t,out/%.bmp.correct.txt,$(GOLDS))

SIM = $(patsubst %.t,out/%.sim.bmp,$(SRCS))
SIM += $(patsubst %.t,out/%_half.sim.bmp,$(SRCS))
SIM += $(patsubst %.t,out/%.sim.raw,$(SRCS))
SIM += $(patsubst %.t,out/%_half.sim.raw,$(SRCS))
SIM += $(patsubst %.t,out/%.sim.v,$(SRCS))
SIM += $(patsubst %.t,out/%_half.sim.v,$(SRCS))
SIM += $(patsubst %.t,out/%.sim.correct.txt,$(GOLDS))
SIM += $(patsubst %.t,out/%_half.sim.correct.txt,$(GOLDS))

AXIBITS = $(patsubst %.t,out/%.axi.v,$(SRCS))
AXIBITS += $(patsubst %.t,out/%.axi.bit,$(SRCS))

AXI = $(patsubst %.t,out/%.axi.raw,$(SRCS))
AXI += $(patsubst %.t,out/%.axi.bmp,$(SRCS))
AXI += $(patsubst %.t,out/%.axi.correct.txt,$(GOLDS))
AXI += $(AXIBITS)

RES += $(SIM)
RES += $(AXI)

CD = cd out;
all: $(RES)

sim: $(SIM)

axi: $(AXI)

axibits: $(AXIBITS)

clean:
	rm -Rf out/*

out/%.raw out/%.sim.v out/%_half.sim.v out/%.axi.v: %.t 
	terra $<

#	$(CD) xst -ifn ../../extras/helloaxi/system.xst

out/%.axi.bit: out/%.axi.v
	mkdir -p out/build_$*
	cd out/build_$*; echo "run -ifn ../$*.axi.v -ifmt Verilog -p xc7z020-clg484-1 -top stage -ofn system" | xst > OUT_xst.txt
	cd out/build_$*; ngdbuild -nt timestamp -uc ../../../extras/helloaxi/ps7_constraints.ucf -uc ../../../extras/helloaxi/system.ucf -p xc7z020-clg484-1 system.ngc system.ngd > OUT_ngd.txt
	cd out/build_$*; map -p xc7z020-clg484-1 -w -logic_opt off -ol high -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o system_map.ncd system.ngd system.pcf > OUT_map.txt
	cd out/build_$*; par -w -ol high -mt off system_map.ncd system.ncd system.pcf > OUT_par.txt
	cd out/build_$*; trce -v 3 -s 1 -n 3 -fastpaths -xml system.twx system.ncd -o system.twr system.pcf -ucf ../../extras/helloaxi/ps7_constraints.ucf -ucf ../../extras/helloaxi/system.ucf > OUT_trce.txt
	cd out/build_$*; bitgen -w -g Binary:no -g CRC:Enable -g ProgPin:PullUp -g InitPin:Pullup -g TckPin:PullUp -g TdiPin:PullUp \
	  -g TdoPin:PullUp -g TmsPin:PullUp -g Disable_JTAG:No -g UnusedPin:PullDown -g UserID:0xFFFFFFFF -g OverTempPowerDown:Disable \
	  -g USR_ACCESS:None -g JTAG_XADC:Enable -g DCIUpdateMode:AsRequired -g StartUpClk:CClk -g DONE_cycle:4 -g GTS_cycle:5 -g GWE_cycle:6 \
	  -g Match_cycle:Auto -g Security:None -g ICAP_select:Auto -g DonePipe:Yes -g DriveDone:No system.ncd > OUT_bitgen.txt
	mv out/build_$*/system.bit $@

ZYNQ_WRITE_PATH=/var/volatile
ZYNQ_ADDR=192.168.2.2

out/%.axi.raw: out/%.axi.bit
	$(eval $@_IMG := $(shell terra ../extras/extractMetadata.t out/$*.metadata.lua inputImage))
	sshpass -p 'root' scp ../extras/helloaxi/processimage out/$*.axi.bit $($@_IMG) root@$(ZYNQ_ADDR):$(ZYNQ_WRITE_PATH)
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "cat $(ZYNQ_WRITE_PATH)/$*.axi.bit > /dev/xdevcfg"
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "$(ZYNQ_WRITE_PATH)/processimage 805339136 $(ZYNQ_WRITE_PATH)/$($@_IMG) $(ZYNQ_WRITE_PATH)/out.raw 1 1"
	sshpass -p 'root' scp root@$(ZYNQ_ADDR):$(ZYNQ_WRITE_PATH)/out.raw out/$*.axi.raw
	sshpass -p 'root' ssh root@$(ZYNQ_ADDR) "rm $(ZYNQ_WRITE_PATH)/processimage $(ZYNQ_WRITE_PATH)/$($@_IMG) $(ZYNQ_WRITE_PATH)/out.raw $(ZYNQ_WRITE_PATH)/$*.axi.bit"

# isim is crap, and if we run multiple processes at the same time in the same directory, they will clobber each other. So we need to run in different directories.
out/%.sim.raw: out/%.sim.v
	mkdir -p out/sim_$*
	cd out/sim_$*; vlogcomp ../$*.sim.v
	cd out/sim_$*; fuse -o $* -lib $* -L unisim -L unimacro -top sim
	cd out/sim_$*; echo "run all" | ./$*
	mv out/sim_$*/$*.sim.raw out

out/%.sim.bmp: out/%.sim.raw
	terra ../extras/raw2bmp.t out/$*.sim.raw out/$*.sim.bmp out/$*.metadata.lua

out/%.axi.bmp: out/%.axi.raw
	terra ../extras/raw2bmp.t out/$*.axi.raw out/$*.axi.bmp out/$*.metadata.lua

out/%.bmp: out/%.raw
	terra ../extras/raw2bmp.t out/$*.raw out/$*.bmp out/$*.metadata.lua

out/%.axi.correct.txt : out/%.axi.bmp
	diff out/$*.axi.bmp gold/$*.bmp > out/$*.axi.diff
	test ! -s out/$*.axi.diff && touch $@

out/%_half.sim.correct.txt : out/%_half.sim.bmp
	diff out/$*_half.sim.bmp gold/$*.bmp > out/$*_half.sim.diff
	test ! -s out/$*_half.sim.diff && touch $@

out/%.sim.correct.txt : out/%.sim.bmp
	diff out/$*.sim.bmp gold/$*.bmp > out/$*.sim.diff
	test ! -s out/$*.sim.diff && touch $@

out/%.correct.txt : out/%.bmp
	diff out/$*.bmp gold/$*.bmp > out/$*.diff
	test ! -s out/$*.diff && touch $@
