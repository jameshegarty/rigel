all: t1.bit



%.compile:
	mkdir -p out/build_$*
	cp xilinxip/*.ngc out/build_$*/.
	cd out/build_$*; xst -ifn ../../system.xst | tee OUT_xst.log

%.bit:
	mkdir -p out/build_$*
	cp xilinxip/*.ngc out/build_$*/.
	cd out/build_$*; xst -ifn ../../system.xst | tee OUT_xst.log
	cd out/build_$*; ngdbuild -nt timestamp -uc ../../ps7_constraints.ucf -uc ../../system.ucf -p xc7z020-clg484-1 system.ngc system.ngd | tee OUT_ngd.log
	cd out/build_$*; map -detail -p xc7z020-clg484-1 -w -logic_opt off -ol high -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o system_map.ncd system.ngd system.pcf > OUT_map.txt
	cd out/build_$*; par -w -ol high -mt off system_map.ncd system.ncd system.pcf > OUT_par.txt
	cd out/build_$*; trce -v 3 -s 1 -n 3 -fastpaths -xml system.twx system.ncd -o system.twr system.pcf -ucf ../../extras/camera1/ps7_constraints.ucf -ucf ../../system.ucf > OUT_trce.txt
	cd out/build_$*; bitgen -w -g Binary:no -g CRC:Enable -g ProgPin:PullUp -g InitPin:Pullup -g TckPin:PullUp -g TdiPin:PullUp \
	  -g TdoPin:PullUp -g TmsPin:PullUp -g Disable_JTAG:No -g UnusedPin:PullDown -g UserID:0xFFFFFFFF -g OverTempPowerDown:Disable \
	  -g USR_ACCESS:None -g JTAG_XADC:Enable -g DCIUpdateMode:AsRequired -g StartUpClk:CClk -g DONE_cycle:4 -g GTS_cycle:5 -g GWE_cycle:6 \
	  -g Match_cycle:Auto -g Security:None -g ICAP_select:Auto -g DonePipe:Yes -g DriveDone:No system.ncd > OUT_bitgen.txt
	mv out/build_$*/system.bit $@




c: processimage

%:  %.c
	arm-linux-gnueabi-gcc -std=c99  $< -o $@

clean: 
	rm -rf out/*
