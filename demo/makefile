SRCFILES = $(wildcard *.t)
SRCS = $(filter-out harness.t examplescommon.t lk_core.t lk_tr_core.t stereo_core.t stereo_tr_core.t pyramid_core.t harris_core.t sift_core.t sift_core_hw.t campipe_core.t,$(SRCFILES))

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

terra: $(TERRA)

CAMERA_ADDR=192.168.42.50
CAMERA_WRITE_PATH=/tmp
CAMERA_PASS=1234

cam.camera.run: out/campipe.camera1x.bit
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk1' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo '100000000' > /sys/class/fclk/fclk0/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat /sys/class/fclk/fclk0/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo '96000000' > /sys/class/fclk/fclk1/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat /sys/class/fclk/fclk1/set_rate"
###### CLOCK STUFF END
	sshpass -p $(CAMERA_PASS) scp ../platform/camera1x/csrc/processimage out/campipe.camera1x.bit root@$(CAMERA_ADDR):$(CAMERA_WRITE_PATH)/.
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat $(CAMERA_WRITE_PATH)/campipe.camera1x.bit > /dev/xdevcfg"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "$(CAMERA_WRITE_PATH)/processimage 0" 
	-sshpass -p $(CAMERA_PASS) scp root@$(CAMERA_ADDR):$(CAMERA_WRITE_PATH)/*.raw .
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "rm $(CAMERA_WRITE_PATH)/processimage $(CAMERA_WRITE_PATH)/campipe.camera1x.bit"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_unexport"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk1' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_unexport"

edge.camera.run: out/edge_taps.camera2.0.bit
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk1' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_export"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo '100000000' > /sys/class/fclk/fclk0/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat /sys/class/fclk/fclk0/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo '96000000' > /sys/class/fclk/fclk1/set_rate"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat /sys/class/fclk/fclk1/set_rate"
###### CLOCK STUFF END
	sshpass -p $(CAMERA_PASS) scp ../platform/camera2.0/csrc/processimage out/edge_taps.camera2.0.bit root@$(CAMERA_ADDR):$(CAMERA_WRITE_PATH)/.
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "cat $(CAMERA_WRITE_PATH)/edge_taps.camera2.0.bit > /dev/xdevcfg"
	sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "$(CAMERA_WRITE_PATH)/processimage 0" 
	-sshpass -p $(CAMERA_PASS) scp root@$(CAMERA_ADDR):$(CAMERA_WRITE_PATH)/*.raw .
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "rm $(CAMERA_WRITE_PATH)/processimage $(CAMERA_WRITE_PATH)/edge_taps.camera2.0.bit"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk0' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_unexport"
	-sshpass -p $(CAMERA_PASS) ssh root@$(CAMERA_ADDR) "echo 'fclk1' > /sys/devices/amba.0/f8007000.ps7-dev-cfg/fclk_unexport"

%.open: %.raw
	terra ../misc/raw2bmp.t $*.raw $*.bmp out/campipe_ov7660.metadata.lua 0
	open $*.bmp

cam.v:

cam.bmp:
	terra campipe_ov7660.t
	terra ../misc/raw2bmp.t out/campipe_ov7660.raw out/campipe_ov7660.bmp out/campipe_ov7660.metadata.lua 0
	# keep copy for future reference
	open out/campipe_ov7660.bmp
