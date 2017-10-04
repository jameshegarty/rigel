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
