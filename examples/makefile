# make sure we use bash shell - to make the hacky runtime timers work
SHELL = /bin/bash

BUILDDIR ?= out

SRCS_SOC = soc_simple.lua soc_simple_uniform.lua soc_2in.lua soc_convgen.lua soc_convgen_0.lua soc_convgenTaps.lua soc_flip.lua soc_15x15.lua soc_15x15x15.lua soc_flipWrite.lua soc_regin.lua soc_regout.lua soc_convtest.lua soc_read.lua soc_redu1024.lua soc_redu2048.lua soc_redu4096.lua soc_redu8192.lua soc_redu16384.lua soc_redu32768.lua soc_sort.lua soc_filterseq.lua soc_filterseq8.lua soc_unaligned.lua soc_underflow.lua soc_parread.lua soc_tokencounter.lua soc_arbiter.lua soc_readlen.lua soc_readarrays_1.lua soc_readarrays_8.lua
SRCS_SOC += soc_convgenTaps_4_2.lua  soc_convgenTaps_8_8.lua soc_convgenTaps_4_8.lua soc_convgenTaps_4_16.lua  soc_convgenTaps_4_16.lua soc_convgenTaps_8_4.lua soc_convgenTaps_8_2.lua soc_convgenTaps_8_1.lua soc_convgenTaps_4_4.lua  soc_convgenTaps_8_16.lua  soc_convgenTaps_8_32.lua soc_convgenTaps_8_64.lua

SRCS_SOC += soc_stereo_tiny_4_4.lua soc_stereo_tiny_4_1.lua soc_stereo_tiny_4_2.lua soc_stereo_tiny_4_8.lua soc_stereo_full_64_64.lua soc_stereo_full_64_32.lua soc_stereo_full_64_16.lua soc_stereo_full_64_8.lua soc_stereo_full_64_4.lua
SRCS_SOC += soc_lk_4_4.lua soc_lk_4_2.lua soc_lk_4_1.lua soc_lk_4_8.lua soc_lk_6_6.lua soc_lk_12_12.lua soc_lk_12_24.lua soc_lk_12_48.lua soc_lk_12_6.lua
SRCS_SOC += soc_sift_4_1.lua soc_sift_4_1_1080p.lua soc_sift_4_2.lua soc_sift_4_2_1080p.lua soc_sift_4_4.lua soc_sift_4_4_1080p.lua soc_sift_4_8.lua soc_sift_4_8_1080p.lua soc_sift_1_2.lua

SIG20 := soc_lk_12_12.lua soc_lk_12_6.lua soc_lk_12_4.lua soc_lk_12_3.lua soc_lk_12_2.lua soc_lk_12_1.lua soc_lk_12_24.lua soc_lk_12_48.lua soc_lk_6_6.lua soc_lk_4_4.lua soc_lk_4_2.lua soc_lk_4_1.lua soc_lk_4_8.lua
SIG20 += soc_convgenTaps_8_1.lua soc_convgenTaps_8_2.lua soc_convgenTaps_8_4.lua  soc_convgenTaps_8_8.lua soc_convgenTaps_8_16.lua soc_convgenTaps_8_32.lua soc_convgenTaps_8_64.lua
SIG20 += soc_stereo_tiny_4_4.lua soc_stereo_tiny_4_1.lua soc_stereo_tiny_4_2.lua soc_stereo_tiny_4_8.lua soc_stereo_full_64_64.lua soc_stereo_full_64_32.lua soc_stereo_full_64_16.lua soc_stereo_full_64_8.lua
SIG20 += soc_sift_4_1.lua soc_sift_4_1_1080p.lua soc_sift_4_2.lua soc_sift_4_2_1080p.lua soc_sift_4_4.lua soc_sift_4_4_1080p.lua soc_sift_4_8.lua soc_sift_4_8_1080p.lua soc_sift_1_2.lua

ZU9VIVADOSOCBITS_SIG20 := $(patsubst %.lua,$(BUILDDIR)/%.zu9vivadoSOC.bit,$(SIG20))
ZU9VIVADOSOCBITS_SIG20 += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.correct.txt,$(SIG20))
#ZU9VIVADOSOCBITS_SIG20 += $(patsubst %.lua,$(BUILDDIR)/%.zu9vivadoSOC.stats2020.txt,$(SIG20))

# too slow
SRCS_VERILATOR_SOC := $(filter-out soc_lk_12_12.lua soc_lk_12_24.lua soc_lk_12_48.lua soc_lk_12_6.lua, $(SRCS_SOC))
SRCS_VERILATOR_SOC := $(filter-out soc_stereo_full_64_64.lua soc_stereo_full_64_32.lua soc_stereo_full_64_16.lua soc_stereo_full_64_8.lua soc_stereo_full_64_4.lua, $(SRCS_VERILATOR_SOC))
SRCS_VERILATOR_SOC := $(filter-out soc_sift_4_1.lua soc_sift_4_1_1080p.lua soc_sift_4_2.lua soc_sift_4_2_1080p.lua soc_sift_4_4.lua soc_sift_4_4_1080p.lua soc_sift_4_8.lua soc_sift_4_8_1080p.lua, $(SRCS_VERILATOR_SOC))
SRCS_VERILATOR_SOC := $(filter-out soc_convgenTaps_8_64.lua, $(SRCS_VERILATOR_SOC))

# broken in circleci for some reason?
SRCS_VERILATOR_SOC := $(filter-out soc_stereo_tiny_4_1.lua soc_stereo_tiny_4_2.lua soc_stereo_tiny_4_8.lua, $(SRCS_VERILATOR_SOC))

VERILATOR_SOC = $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.bit,$(SRCS_VERILATOR_SOC))
VERILATOR_SOC += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.raw,$(SRCS_VERILATOR_SOC))
VERILATOR_SOC += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.bmp,$(SRCS_VERILATOR_SOC))
VERILATOR_SOC += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.correct.txt,$(SRCS_VERILATOR_SOC))
VERILATOR_SOC += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.regcorrect.txt,$(SRCS_VERILATOR_SOC))	
VERILATOR_SOC += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.cyclescorrect.txt,$(SRCS_VERILATOR_SOC))

# too slow
SRCS_YOSYS_SOC := $(filter-out soc_convgenTaps_8_8.lua soc_convgenTaps_8_4.lua soc_convgenTaps_8_2.lua soc_convgenTaps_8_1.lua soc_convgenTaps_8_8.lua  soc_convgenTaps_8_16.lua  soc_convgenTaps_8_32.lua soc_convgenTaps_8_64.lua, $(SRCS_SOC))
SRCS_YOSYS_SOC := $(filter-out soc_stereo_full_64_64.lua soc_stereo_full_64_32.lua soc_stereo_full_64_16.lua soc_stereo_full_64_8.lua soc_stereo_full_64_4.lua, $(SRCS_YOSYS_SOC))
SRCS_YOSYS_SOC := $(filter-out soc_lk_12_12.lua soc_lk_12_6.lua soc_lk_12_24.lua soc_lk_12_48.lua, $(SRCS_YOSYS_SOC))
SRCS_YOSYS_SOC := $(filter-out soc_sift_4_1.lua soc_sift_4_1_1080p.lua soc_sift_4_2.lua soc_sift_4_2_1080p.lua soc_sift_4_4.lua soc_sift_4_4_1080p.lua soc_sift_4_8.lua soc_sift_4_8_1080p.lua, $(SRCS_YOSYS_SOC))

YOSYS_SOC = $(patsubst %.lua,$(BUILDDIR)/%.yosysSOC.bit,$(SRCS_YOSYS_SOC))
YOSYS_SOC += $(patsubst %.lua,$(BUILDDIR)/%.yosysSOC.cellscorrect.txt,$(SRCS_YOSYS_SOC))
YOSYS_SOC += $(patsubst %.lua,$(BUILDDIR)/%.yosysSOC.RAMB16_S9_S9correct.txt,$(SRCS_YOSYS_SOC))
YOSYS_SOC += $(patsubst %.lua,$(BUILDDIR)/%.yosysSOC.RAMB16_S36_S36correct.txt,$(SRCS_YOSYS_SOC))
YOSYS_SOC += $(patsubst %.lua,$(BUILDDIR)/%.yosysSOC.RAM128X1Dcorrect.txt,$(SRCS_YOSYS_SOC))

SRCS_STATE = state_simple.t

STATE = $(patsubst %.t,$(BUILDDIR)/%.verilatorSOC.bit,$(SRCS_STATE))
STATE += $(patsubst %.t,$(BUILDDIR)/%.verilatorSOC.raw,$(SRCS_STATE))
STATE += $(patsubst %.t,$(BUILDDIR)/%.verilatorSOC.bmp,$(SRCS_STATE))
STATE += $(patsubst %.t,$(BUILDDIR)/%.verilatorSOC.correct.txt,$(SRCS_STATE))
STATE += $(patsubst %.t,$(BUILDDIR)/%.verilatorSOC.regcorrect.txt,$(SRCS_STATE))
STATE += $(patsubst %.t,$(BUILDDIR)/%.verilatorSOC.cyclescorrect.txt,$(SRCS_STATE))	

SRCS_BJUMP = soc_bjump_cache.lua  soc_bjump_cache_nocache.lua

BJUMP = $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.bit,$(SRCS_BJUMP))
BJUMP += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.raw,$(SRCS_BJUMP))
BJUMP += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.bmp,$(SRCS_BJUMP))
BJUMP += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.correct.txt,$(SRCS_BJUMP))
BJUMP += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.regcorrect.txt,$(SRCS_BJUMP))
BJUMP += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.cyclescorrect.txt,$(SRCS_BJUMP))	

SRCS_PULPINO = soc_pulpino_noc.lua

PULPINO = $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.bit,$(SRCS_PULPINO))
PULPINO += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.raw,$(SRCS_PULPINO))
PULPINO += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.bmp,$(SRCS_PULPINO))
PULPINO += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.correct.txt,$(SRCS_PULPINO))
PULPINO += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.regcorrect.txt,$(SRCS_PULPINO))
PULPINO += $(patsubst %.lua,$(BUILDDIR)/%.verilatorSOC.cyclescorrect.txt,$(SRCS_PULPINO))	

ZU9VIVADOSOCBITS = $(patsubst %.lua,$(BUILDDIR)/%.zu9vivadoSOC.bit,$(SRCS_SOC))

ZU9VIVADOSOC = $(ZU9VIVADOSOCBITS)
ZU9VIVADOSOC += $(patsubst %.lua,$(BUILDDIR)/%.zu9vivadoSOC.raw,$(SRCS_SOC))
ZU9VIVADOSOC += $(patsubst %.lua,$(BUILDDIR)/%.zu9vivadoSOC.bmp,$(SRCS_SOC))
ZU9VIVADOSOC += $(patsubst %.lua,$(BUILDDIR)/%.zu9vivadoSOC.correct.txt,$(SRCS_SOC))
ZU9VIVADOSOC += $(patsubst %.lua,$(BUILDDIR)/%.zu9vivadoSOC.regcorrect.txt,$(SRCS_SOC))

SRCS = $(wildcard *.lua)
SRCS := $(filter-out pyramid_core.lua harris_core.lua sift_core.lua sift_core_hw.lua campipe_core.lua descriptor_core.lua  stereo_core.lua stereo_tr_core.lua  lk_core.lua lk_tr_core.lua $(SRCS_BJUMP) $(SRCS_PULPINO) $(SRCS_SOC),$(SRCS))

# broken
SRCS := $(filter-out soc_lk_12_4.lua soc_lk_12_3.lua soc_lk_12_2.lua soc_lk_12_1.lua, $(SRCS) )
SRCS := $(filter-out soc_stereo_tiny_4_1.lua soc_stereo_tiny_4_8.lua soc_stereo_full_64_64.lua, $(SRCS) )

RIGEL_VERILATOR_INCLUDE ?= $(shell pkg-config --variable=includedir verilator)
RIGEL_VERILATOR_CFLAGS ?= $(shell pkg-config --cflags verilator)
LUA = ../rigelLuajit
LUAJIT = ../rigelLuajit
TERRA = ../rigelTerra

RAWS = $(wildcard *.raw)
DUPS = $(patsubst %.raw,$(BUILDDIR)/%.raw.dup,$(RAWS))

# NYI
SRCS_VERILOG := $(filter-out pad.lua crop.lua stencil.lua downsample_2.lua downsample_4.lua upsample_2.lua upsample_4.lua, $(SRCS))

# dead code (float verilog)
SRCS_VERILOG := $(filter-out sift_float.lua lk_wide_handshake_12_1_float.lua lk_wide_handshake_4_4_float.lua lk_wide_handshake_6_4_float.lua sift_desc.lua sift_desc_2_1.lua,  $(SRCS_VERILOG))

# remove long poles
SRCS_VERILOG := $(filter-out lk_tr_handshake_12_1_axi.lua, $(SRCS_VERILOG))

VERILOG = $(patsubst %.lua,$(BUILDDIR)/%.v,$(SRCS_VERILOG))
SRCS_WRAPPER = $(filter-out readmemory.lua readmemory_flip.lua 12bpp.lua 18bpp.lua nullary.lua,$(SRCS_VERILOG)) ## NYI
WRAPPER = $(patsubst %.lua,$(BUILDDIR)/%.v.mpsocwrapper.v,$(SRCS_WRAPPER))

# too slow
SRCS_TERRA := $(filter-out stereo_tr_rgba_full_32.lua stereo_ov7660.lua underflow.lua lk_wide_handshake_12_1_float.lua lk_wide_handshake_12_1_axi.lua lk_wide_handshake_12_1.lua lk_wide_handshake_12_1_axi_nostall.lua lk_tr_handshake_12_1_axi.lua lk_tr_handshake_12_2_axi.lua lk_tr_handshake_12_3_axi.lua lk_tr_handshake_12_4_axi.lua lk_tr_handshake_12_6_axi.lua lk_tr_handshake_12_12_axi.lua lk_tr_handshake_12_1.lua lk_tr_handshake_12_2.lua lk_tr_handshake_12_3.lua lk_tr_handshake_12_4.lua lk_tr_handshake_12_6.lua lk_tr_handshake_12_12.lua, $(SRCS))

SRCS_TERRA += $(SRCS_SOC)

# too slow
SRCS_TERRA := $(filter-out soc_stereo_full_64_64.lua soc_stereo_full_64_32.lua soc_stereo_full_64_16.lua soc_stereo_full_64_8.lua soc_stereo_full_64_4.lua, $(SRCS_TERRA))
SRCS_TERRA := $(filter-out soc_sift_4_1_1080p.lua soc_sift_4_2_1080p.lua soc_sift_4_4_1080p.lua soc_sift_4_8_1080p.lua, $(SRCS_TERRA))

TERRAOUT := $(patsubst %.lua,$(BUILDDIR)/%.terra.raw,$(SRCS_TERRA))
TERRAOUT += $(patsubst %.lua,$(BUILDDIR)/%.terra.bmp,$(SRCS_TERRA))
TERRAOUT += $(patsubst %.lua,$(BUILDDIR)/%.terra.correct.txt,$(SRCS_TERRA))
TERRAOUT += $(patsubst %.lua,$(BUILDDIR)/%.terra.cyclescorrect.txt,$(SRCS_TERRA))

# no support for xilinx prims needed for float
SRCS_VERILATOR := $(filter-out featuredescriptor.lua lk_wide_handshake_12_1_float.lua lk_wide_handshake_4_4_float.lua lk_wide_handshake_6_4_float.lua, $(SRCS))

SRCS_VERILATOR := $(filter-out sift_float.lua sift_desc.lua sift_desc_2_1.lua, $(SRCS_VERILATOR))

# too slow
SRCS_VERILATOR := $(filter-out sift_hw_4_1080p.lua sift_desc_hw.lua, $(SRCS_VERILATOR))

# uses Xilinx huge mult blocks - no support for prims
SRCS_VERILATOR := $(filter-out lk_tr_handshake_6_3_axi.lua lk_tr_handshake_6_6_axi.lua  lk_tr_handshake_6_2_axi.lua  lk_tr_handshake_6_1_axi.lua lk_tr_handshake_4_4_axi.lua lk_tr_handshake_4_1_axi.lua lk_tr_handshake_12_12_axi.lua  lk_tr_handshake_12_6_axi.lua lk_tr_handshake_12_4_axi.lua lk_tr_handshake_12_3_axi.lua lk_tr_handshake_12_2_axi.lua lk_tr_handshake_12_1_axi.lua lk_wide_handshake_12_1_axi.lua lk_wide_handshake_12_1_axi_nostall.lua  lk_wide_handshake_6_4_axi.lua lk_wide_handshake_6_1_axi.lua lk_wide_handshake_4_4_axi.lua lk_wide_handshake_4_1_axi.lua, $(SRCS_VERILATOR))

SRCS_VERILATOR := $(filter-out lk_tr_handshake_12_12.lua  lk_tr_handshake_12_6.lua lk_tr_handshake_12_4.lua lk_tr_handshake_12_3.lua lk_tr_handshake_12_2.lua lk_tr_handshake_12_1.lua lk_wide_handshake_12_1.lua, $(SRCS_VERILATOR))

# verilator target doesn't include underflow block
SRCS_VERILATOR := $(filter-out underflow.lua, $(SRCS_VERILATOR))

# TODO: broken due to verilator bug?
SRCS_VERILATOR := $(filter-out stereo_tr_rgba_full_32.lua tmux_wide_handshake.lua pyramid_large_taps_3.lua pyramid_taps_4.lua pyramid_taps_3.lua pyramid_tr_3.lua, $(SRCS_VERILATOR))

# too slow for travis
SRCS_VERILATOR := $(filter-out stereo_wide_handshake_full.lua stereo_wide_handshake_nostall_full.lua, $(SRCS_VERILATOR))

# fails in travis for some reason?
SRCS_VERILATOR := $(filter-out stereo_wide_handshake_medi.lua stereo_wide_handshake_nostall_medi.lua pyramid_large_nofifo_taps_4.lua, $(SRCS_VERILATOR))

# NYI
SRCS_VERILATOR := $(filter-out pad.lua crop.lua  stencil.lua downsample_2.lua downsample_4.lua upsample_2.lua upsample_4.lua, $(SRCS_VERILATOR))

SRCS_VERILATOR := $(filter-out readmemory.lua readmemory_flip.lua, $(SRCS_VERILATOR))

# remove long poles
SRCS_VERILATOR := $(filter-out stereo_ov7660.lua stereo_tr_full_4.lua stereo_tr_full_8.lua stereo_tr_full_16.lua, $(SRCS_VERILATOR))

# too slow
SRCS_TERRA_ISIM = $(SRCS_TERRA)
SRCS_TERRA_ISIM := $(filter-out stereo_wide_handshake_medi.t stereo_wide_handshake_nostall_medi.t stereo_tr_medi_4.t stereo_tr_medi_8.t stereo_tr_medi_16.t ,$(SRCS_TERRA_ISIM))
SRCS_TERRA_ISIM := $(filter-out stereo_wide_handshake_full.t stereo_wide_handshake_nostall_full.t stereo_tr_full_4.t stereo_tr_full_8.t stereo_tr_full_16.t stereo_tr_rgba_full_32.t,$(SRCS_TERRA_ISIM))
SRCS_TERRA_ISIM := $(filter-out stereo_ov7660.t ,$(SRCS_TERRA_ISIM))
SRCS_TERRA_ISIM := $(filter-out lk_wide_handshake_4_4_float.t lk_wide_handshake_6_4_axi.t lk_wide_handshake_6_4_float.t lk_wide_handshake_6_1_axi.t lk_wide_handshake_4_4_axi.t lk_wide_handshake_4_1_axi.t lk_tr_handshake_4_4_axi.t lk_tr_handshake_6_6.t lk_tr_handshake_6_6_axi.t lk_tr_handshake_6_1.t lk_tr_handshake_6_1_axi.t lk_tr_handshake_6_2.t lk_tr_handshake_6_2_axi.t lk_tr_handshake_6_3.t lk_tr_handshake_6_3_axi.t ,$(SRCS_TERRA_ISIM))
SRCS_TERRA_ISIM := $(filter-out lk_wide_handshake_12_1_float.t lk_wide_handshake_12_1_axi.t lk_wide_handshake_12_1_axi_nostall.t lk_tr_handshake_12_1_axi.t lk_tr_handshake_12_2_axi.t lk_tr_handshake_12_3_axi.t lk_tr_handshake_12_4_axi.t lk_tr_handshake_12_6_axi.t lk_tr_handshake_12_12_axi.t,$(SRCS_TERRA_ISIM))
SRCS_TERRA_ISIM := $(filter-out campipe_512.t campipe_ov7660.t,$(SRCS_TERRA_ISIM))
SRCS_TERRA_ISIM := $(filter-out pyramid_large_1.t pyramid_large_2.t pyramid_large_3.t pyramid_large_4.t pyramid_large_tr_1.t pyramid_large_tr_2.t pyramid_large_tr_3.t pyramid_large_tr_4.t pyramid_large_nofifo_tr_1.t pyramid_large_nofifo_tr_2.t pyramid_large_nofifo_tr_3.t pyramid_large_nofifo_tr_4.t,$(SRCS_TERRA_ISIM))
SRCS_TERRA_ISIM := $(filter-out pyramid_large_taps_1.t pyramid_large_taps_2.t pyramid_large_taps_3.t pyramid_large_taps_4.t pyramid_large_nofifo_taps_1.t pyramid_large_nofifo_taps_2.t pyramid_large_nofifo_taps_3.t pyramid_large_nofifo_taps_4.t,$(SRCS_TERRA_ISIM))
SRCS_TERRA_ISIM := $(filter-out convpadcrop_wide_handshake_4_1_1080p.t convpadcrop_wide_handshake_4_2_1080p.t convpadcrop_wide_handshake_4_4_1080p.t convpadcrop_wide_handshake_4_8_1080p.t convpadcrop_wide_handshake_8_1_1080p.t convpadcrop_wide_handshake_8_2_1080p.t convpadcrop_wide_handshake_8_4_1080p.t convpadcrop_wide_handshake_8_8_1080p.t,$(SRCS_TERRA_ISIM))
SRCS_TERRA_ISIM := $(filter-out convpadcrop_wide_handshake_8_1_1080p_nostall.t convpadcrop_wide_handshake_8_2_1080p_nostall.t convpadcrop_wide_handshake_8_4_1080p_nostall.t convpadcrop_wide_handshake_8_8_1080p_nostall.t,$(SRCS_TERRA_ISIM))
SRCS_TERRA_ISIM := $(filter-out conv_tr_handshake_4_1_1080p.t conv_tr_handshake_4_2_1080p.t conv_tr_handshake_4_4_1080p.t conv_tr_handshake_4_8_1080p.t conv_tr_handshake_8_1_1080p.t conv_tr_handshake_8_2_1080p.t conv_tr_handshake_8_4_1080p.t conv_tr_handshake_8_8_1080p.t,$(SRCS_TERRA_ISIM))
#nyi
SRCS_TERRA_ISIM := $(filter-out fixed_float_inv.t harris_corner.t filterseq.t harris_filterseq.t sift_float.t sift_desc.t sift_desc_hw.t sift_hw.t sift_hw_1080p.t,$(SRCS_TERRA_ISIM))

ISIM = $(patsubst %.lua,$(BUILDDIR)/%.isim.bmp,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.lua,$(BUILDDIR)/%.isim.1.bmp,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.lua,$(BUILDDIR)/%_half.isim.bmp,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.lua,$(BUILDDIR)/%.isim.raw,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.lua,$(BUILDDIR)/%_half.isim.raw,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.lua,$(BUILDDIR)/%.isim.v,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.lua,$(BUILDDIR)/%_half.isim.v,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.lua,$(BUILDDIR)/%.isim.correct.txt,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.lua,$(BUILDDIR)/%.isim.1.correct.txt,$(SRCS_TERRA_ISIM))
ISIM += $(patsubst %.lua,$(BUILDDIR)/%_half.isim.correct.txt,$(SRCS_TERRA_ISIM))

SRCS_AXI = $(filter-out linebufferpartial_handshake_1.lua linebufferpartial_handshake_2.lua linebufferpartial_handshake_4.lua convpadcrop_handshake.lua reduceseq_handshake.lua  stereo_wide_handshake_medi.lua,$(SRCS))
SRCS_AXI := $(filter-out lk_tr_handshake_4_4.lua lk_tr_handshake_6_6.lua lk_tr_handshake_6_1.lua lk_tr_handshake_6_2.lua lk_tr_handshake_6_3.lua lk_wide_handshake_12_1_float.lua,$(SRCS_AXI))
SRCS_AXI := $(filter-out lk_wide_handshake_4_4_float.lua lk_wide_handshake_6_4_float.lua lk_wide_handshake_4_4.lua lk_wide_handshake_4_1.lua,$(SRCS_AXI))
SRCS_AXI := $(filter-out harris_filterseq.lua sift_float.lua sift_desc.lua,$(SRCS_AXI))

# fails in the cron script b/c par takes too long
SRCS_AXI := $(filter-out convpadcrop_wide_handshake_8_8.lua lk_wide_handshake_4_4_axi.lua lk_tr_handshake_12_3_axi.lua,$(SRCS_AXI))

# TODO fix: fails in cron due to taking too many cycles to execute?
SRCS_AXI := $(filter-out upsample_wide_handshake_2.lua upsample_wide_handshake_4.lua tmux_wide_handshake.lua edge_taps.lua,$(SRCS_AXI))

# broken tests
SRCS_AXI := $(filter-out fixed_float_inv.lua sift_desc_hw.lua sift_hw.lua sift_hw_1080p.lua featuredescriptor.lua,$(SRCS_AXI))

# NYI - type size not a factor of axi bus size
SRCS_AXI := $(filter-out 4bpp.lua 12bpp.lua 18bpp.lua,$(SRCS_AXI))

# NYI
SRCS_AXI := $(filter-out readmemory.lua readmemory_flip.lua pad.lua crop.lua  stencil.lua downsample_2.lua downsample_4.lua upsample_2.lua upsample_4.lua nullary.lua,$(SRCS_AXI))

SRCS_AXI100 = $(SRCS_AXI)

# Broken due to 'too many cycles' bug
SRCS_AXI100 := $(filter-out 2xov7660.lua convolve_p8.lua convpadcrop_wide_handshake_4_2.lua convpadcrop_wide_handshake_4_4_1080p.lua convpadcrop_wide_handshake_8_2_1080p_nostall.lua edge.lua fifo_wide_handshake_2.lua lk_wide_handshake_4_1_axi.lua inv_wide_handshake.lua pyramid_large_1.lua pyramid_large_2.lua pyramid_large_4.lua lk_tr_handshake_12_1_axi.lua convpadcrop_wide_handshake_8_4_1080p.lua lk_tr_handshake_6_1_axi.lua pyramid_large_nofifo_taps_2.lua pyramid_large_taps_4.lua pyramid_large_tr_2.lua pyramid_large_tr_4.lua lk_tr_handshake_6_2_axi.lua,$(SRCS_AXI100))

# fails in PAR b/c takes too long or something?
SRCS_AXI100 := $(filter-out  stereo_tr_full_4.lua stereo_tr_medi_4.lua lk_tr_handshake_12_2_axi.lua, $(SRCS_AXI100))

# filter out stuff that's too big for the 7020
SRCS_AXI20 = $(SRCS_AXI)
SRCS_AXI20 := $(filter-out stereo_wide_handshake_nostall_full.lua stereo_wide_handshake_nostall_medi.lua stereo_wide_handshake_full.lua,$(SRCS_AXI20))
SRCS_AXI20 := $(filter-out lk_tr_handshake_12_1_axi.lua lk_tr_handshake_12_2_axi.lua lk_tr_handshake_12_3_axi.lua lk_tr_handshake_12_4_axi.lua lk_tr_handshake_12_6_axi.lua lk_tr_handshake_6_1_axi.lua lk_wide_handshake_4_4_axi.lua lk_wide_handshake_6_4_axi.lua,$(SRCS_AXI20))
SRCS_AXI20 := $(filter-out lk_wide_handshake_12_1_axi_nostall.lua lk_wide_handshake_12_1_axi.lua,$(SRCS_AXI20))
SRCS_AXI20 := $(filter-out pyramid_large_nofifo_taps_4.lua pyramid_large_taps_3.lua pyramid_taps_3.lua pyramid_taps_4.lua pyramid_large_taps_4.lua,$(SRCS_AXI20))

# fails due to size in cron script?
SRCS_AXI20 := $(filter-out convpadcrop_wide_handshake_8_8_1080p_nostall.lua pyramid_large_nofifo_taps_3.lua convpadcrop_wide_handshake_8_8_1080p.lua,$(SRCS_AXI20))

# TODO broken in cron script?
SRCS_AXI20 := $(filter-out edge.lua upsampley_wide_handshake.lua pointwise_wide_handshake_1080p.lua,$(SRCS_AXI20))

AXIVERILOG = $(patsubst %.lua,$(BUILDDIR)/%.axi.v,$(SRCS_AXI))

AXIBITS = $(patsubst %.lua,$(BUILDDIR)/%.axi.bit,$(SRCS_AXI20))

AXIBITS100 = $(patsubst %.lua,$(BUILDDIR)/%.zynq100.bit,$(SRCS_AXI100))
AXIBITS100 += $(patsubst %.lua,$(BUILDDIR)/%.zynq100.bit.bin,$(SRCS_AXI100))

AXI = $(patsubst %.lua,$(BUILDDIR)/%.axi.raw,$(SRCS_AXI20))
AXI += $(patsubst %.lua,$(BUILDDIR)/%.axi.bmp,$(SRCS_AXI20))
AXI += $(patsubst %.lua,$(BUILDDIR)/%.axi.correct.txt,$(SRCS_AXI20))
AXI += $(patsubst %.lua,$(BUILDDIR)/%.hz.txt,$(SRCS_AXI20))
AXI += $(AXIBITS)

AXI100 = $(patsubst %.lua,$(BUILDDIR)/%.zynq100.correct.txt,$(SRCS_AXI100))
AXI100 += $(patsubst %.lua,$(BUILDDIR)/%.zynq100.raw,$(SRCS_AXI100))
AXI100 += $(patsubst %.lua,$(BUILDDIR)/%.zynq100.bmp,$(SRCS_AXI100))
AXI100 += $(AXIBITS100)

SRCS_ZU9 = $(SRCS_AXI20)

#combination loop race condition DRC error
SRCS_AXI20 := $(filter-out lk_tr_handshake_6_2_axi.lua lk_tr_handshake_6_6_axi.lua lk_tr_handshake_12_12_axi.lua lk_tr_handshake_6_3_axi.lua lk_tr_handshake_4_4_axi.lua,$(SRCS_AXI20))

# broken?
SRCS_AXI20 := $(filter-out underflow.lua,$(SRCS_AXI20))

ZU9VIVADOBITS = $(patsubst %.lua,$(BUILDDIR)/%.zu9vivado.bit,$(SRCS_ZU9))
ZU9VIVADOBITS += $(patsubst %.lua,$(BUILDDIR)/%.zu9vivado.perfcorrect.txt,$(SRCS_ZU9))

ZU9VIVADO = $(patsubst %.lua,$(BUILDDIR)/%.zu9vivado.raw,$(SRCS_ZU9))
ZU9VIVADO += $(patsubst %.lua,$(BUILDDIR)/%.zu9vivado.bmp,$(SRCS_ZU9))
ZU9VIVADO += $(patsubst %.lua,$(BUILDDIR)/%.zu9vivado.correct.txt,$(SRCS_ZU9))
ZU9VIVADO += $(ZU9VIVADOBITS)

SRCS_CORA10 = $(SRCS_AXI20)

# ERROR [Synth 8-448] named port connection 'taps' does not exist for instance 'pipeline' of module 'harnessaxi'
SRCS_CORA10 := $(filter-out conv_wide_handshake_taps.lua convpadcrop_wide_handshake_4_1.lua convpadcrop_wide_handshake_4_1_1080p.lua convpadcrop_wide_handshake_4_2.lua convpadcrop_wide_handshake_4_2_1080p.lua convpadcrop_wide_handshake_4_4.lua convpadcrop_wide_handshake_4_4_1080p.lua convpadcrop_wide_handshake_4_8.lua convpadcrop_wide_handshake_4_8_1080p.lua convpadcrop_wide_handshake_8_1.lua convpadcrop_wide_handshake_8_1_1080p.lua convpadcrop_wide_handshake_8_1_1080p_nostall.lua convpadcrop_wide_handshake_8_2.lua convpadcrop_wide_handshake_8_2_1080p.lua convpadcrop_wide_handshake_8_2_1080p_nostall.lua convpadcrop_wide_handshake_8_4.lua convpadcrop_wide_handshake_8_4_1080p.lua convpadcrop_wide_handshake_8_4_1080p_nostall.lua pyramid_large_nofifo_taps_1.lua pyramid_large_nofifo_taps_2.lua pyramid_large_nofifo_tr_1.lua pyramid_large_nofifo_tr_2.lua pyramid_large_nofifo_tr_3.lua pyramid_large_nofifo_tr_4.lua pyramid_large_taps_1.lua pyramid_large_taps_2.lua pyramid_large_tr_1.lua pyramid_large_tr_2.lua pyramid_large_tr_3.lua pyramid_large_tr_4.lua pyramid_taps_1.lua pyramid_taps_2.lua pyramid_tr_1.lua pyramid_tr_2.lua pyramid_tr_3.lua pyramid_tr_4.lua,$(SRCS_CORA10))

# ERROR [Place 30-640] Place Check
SRCS_CORA10 := $(filter-out harris.lua harris_corner.lua lk_wide_handshake_6_1_axi.lua stereo_tr_full_4.lua stereo_tr_full_8.lua stereo_tr_medi_4.lua stereo_tr_medi_8.lua stereo_tr_rgba_full_32.lua,$(SRCS_CORA10))

# diff fails
SRCS_CORA10 := $(filter-out 2xov7660.lua campipe_128.lua campipe_512.lua campipe_ov7660.lua campipe_ov7660_1x.lua conv_tr_handshake_4_1.lua conv_tr_handshake_4_1_1080p.lua conv_tr_handshake_4_2.lua conv_tr_handshake_4_2_1080p.lua conv_tr_handshake_4_4.lua conv_tr_handshake_4_4_1080p.lua conv_tr_handshake_8_1.lua conv_tr_handshake_8_1_1080p.lua conv_tr_handshake_8_2.lua conv_tr_handshake_8_2_1080p.lua conv_tr_handshake_8_4.lua conv_tr_handshake_8_4_1080p.lua conv_tr_handshake_8_8.lua conv_tr_handshake_8_8_1080p.lua convolve_p8.lua convolve_slow.lua downsample_wide_handshake_2.lua downsample_wide_handshake_4.lua downsamplex_wide_handshake_1.lua downsamplex_wide_handshake_2.lua downsamplex_wide_handshake_4.lua downsamplex_wide_handshake_8.lua filterseq.lua fixed_inv_wide_handshake.lua interleve_wide_handshake.lua lk_wide_handshake_4_1_axi.lua lowthroughput_128.lua lowthroughput_16.lua lowthroughput_4.lua nilhandshake.lua pyramid_1.lua pyramid_2.lua pyramid_3.lua pyramid_4.lua pyramid_large_1.lua pyramid_large_2.lua pyramid_large_3.lua pyramid_large_4.lua rcp.lua rcpsigned.lua resample_wide_handshake.lua sparselb.lua sparselb_dense.lua sparselb_overflow.lua stereo_ov7660.lua stereo_tr_full_16.lua stereo_tr_medi_16.lua stereo_tr_tiny_1.lua stereo_tr_tiny_2.lua stereo_tr_tiny_4.lua stereo_wide_handshake_tiny.lua triggeredCounter.lua upsamplex_wide_handshake_1.lua upsamplex_wide_handshake_8.lua,$(SRCS_CORA10))

CORA10VIVADOBITS = $(patsubst %.lua,$(BUILDDIR)/%.cora10vivado.bit,$(SRCS_CORA10))

CORA10VIVADO = $(patsubst %.lua,$(BUILDDIR)/%.cora10vivado.raw,$(SRCS_CORA10))
CORA10VIVADO += $(patsubst %.lua,$(BUILDDIR)/%.cora10vivado.bmp,$(SRCS_CORA10))
CORA10VIVADO += $(patsubst %.lua,$(BUILDDIR)/%.cora10vivado.correct.txt,$(SRCS_CORA10))
CORA10VIVADO += $(CORA10VIVADOBITS)

STATS = $(patsubst %.lua,$(BUILDDIR)/%.stats.txt,$(AXISRCS))

STATS100 = $(patsubst %.lua,$(BUILDDIR)/%.stats100.txt,$(SRCS_AXI100))

CAMERASRCS = stereo_ov7660.t 2xov7660.t campipe_ov7660.t
CAMERABITS = $(patsubst %.t,$(BUILDDIR)/%.axi.v,$(CAMERASRCS))
CAMERABITS += $(patsubst %.t,$(BUILDDIR)/%.camera.bit,$(CAMERASRCS))

SRCS_ASIC = $(SRCS_VERILATOR)

ASIC = $(patsubst %.lua, $(BUILDDIR)/%.32nm.txt, $(SRCS_ASIC))

COVERAGE_SRCS = pointwise_wide_handshake.lua convpadcrop_wide_handshake_4_1.lua conv_tr_handshake_4_4.lua campipe_128.lua downsamplex_wide_handshake_2.lua filterseq.lua downsampley_wide_handshake.lua padcrop_wide_handshake.lua shifty_wide_handshake.lua reduceseq_handshake.lua tmux_wide_handshake.lua upsample_wide_handshake_2.lua 4bpp.lua 12bpp.lua fifo_wide_handshake_2.lua  fifo_wide_handshake_2_noloop.lua pad_wide_handshake.lua fifo_wide_handshake_bram.lua pyramid_tr_1.lua stereo_wide_handshake_tiny.lua
COVERAGE = $(patsubst %.lua,$(BUILDDIR)/%.coverage.txt,$(COVERAGE_SRCS))

# split out siggraph 2016 stuff to run tests faster
SIG16 := convpadcrop_wide_handshake_8_8_1080p.lua convpadcrop_wide_handshake_8_4_1080p.lua convpadcrop_wide_handshake_8_2_1080p.lua conv_tr_handshake_8_1_1080p.lua conv_tr_handshake_8_2_1080p.lua conv_tr_handshake_8_4_1080p.lua conv_tr_handshake_8_8_1080p.lua
SIG16 += stereo_wide_handshake_full.lua stereo_tr_full_4.lua stereo_tr_full_8.lua stereo_tr_full_16.lua stereo_wide_handshake_tiny.lua stereo_tr_tiny_1.lua stereo_tr_tiny_2.lua stereo_tr_tiny_4.lua
SIG16 += lk_wide_handshake_12_1.lua lk_tr_handshake_12_1.lua lk_tr_handshake_12_2.lua lk_tr_handshake_12_3.lua lk_tr_handshake_12_4.lua lk_tr_handshake_12_6.lua lk_tr_handshake_12_12.lua sift_hw_1080p.lua
SIG16 += sift_hw_4.lua sift_hw_1.lua sift_hw_4_1080p.lua sift_desc_hw.lua

# add some extra slow tests
SIG16_EXT := $(SIG16)
SIG16_EXT += convpadcrop_wide_handshake_8_8_1080p_nostall.lua pyramid_large_4.lua lk_tr_handshake_6_2.lua pyramid_4.lua pyramid_large_nofifo_taps_3.lua sift_desc_hw_2_1.lua stereo_tr_medi_4.lua lk_tr_handshake_6_1.lua pyramid_taps_2.lua pyramid_large_nofifo_taps_2.lua convpadcrop_wide_handshake_8_8_1080p_nostall.lua convpadcrop_wide_handshake_8_8.lua pyramid_4.lua pyramid_large_4.lua pyramid_large_taps_2.lua sift_desc_hw_2_1.lua lk_tr_handshake_6_2.lua pyramid_large_nofifo_taps_3.lua stereo_tr_medi_4.lua lk_tr_handshake_6_1.lua

# compute the intersection of the verilator list and sig16 list
SRCS_VERILATOR_SIG16_INV := $(filter-out $(SRCS_VERILATOR), $(SIG16_EXT))
SRCS_VERILATOR_SIG16 := $(filter-out $(SRCS_VERILATOR_SIG16_INV), $(SIG16_EXT))

VERILATOR_SIG16 := $(patsubst %.lua,$(BUILDDIR)/%.verilator,$(SRCS_VERILATOR_SIG16))
VERILATOR_SIG16 += $(patsubst %.lua,$(BUILDDIR)/%.verilator.raw,$(SRCS_VERILATOR_SIG16))
VERILATOR_SIG16 += $(patsubst %.lua,$(BUILDDIR)/%.verilator.bmp,$(SRCS_VERILATOR_SIG16))
VERILATOR_SIG16 += $(patsubst %.lua,$(BUILDDIR)/%.verilator.correct.txt,$(SRCS_VERILATOR_SIG16))
VERILATOR_SIG16 += $(patsubst %.lua,$(BUILDDIR)/%.verilator.cyclescorrect.txt,$(SRCS_VERILATOR_SIG16))

# remove SIG16 tests from verilator test
# spaghetti code!!
SRCS_VERILATOR := $(filter-out $(SIG16_EXT), $(SRCS_VERILATOR))

ZU9VIVADOBITS_SIG16 := $(patsubst %.lua,$(BUILDDIR)/%.zu9vivado.bit,$(SIG16))
ZU9VIVADOBITS_SIG16 += $(patsubst %.lua,$(BUILDDIR)/%.verilator.correct.txt,$(SIG16))
#ZU9VIVADOBITS_SIG16 += $(patsubst %.lua,$(BUILDDIR)/%.zu9vivado.stats2020.txt,$(SIG16))

VERILATOR := $(patsubst %.lua,$(BUILDDIR)/%.verilator,$(SRCS_VERILATOR))
VERILATOR += $(patsubst %.lua,$(BUILDDIR)/%.verilator.raw,$(SRCS_VERILATOR))
VERILATOR += $(patsubst %.lua,$(BUILDDIR)/%.verilator.bmp,$(SRCS_VERILATOR))
VERILATOR += $(patsubst %.lua,$(BUILDDIR)/%.verilator.correct.txt,$(SRCS_VERILATOR))
VERILATOR += $(patsubst %.lua,$(BUILDDIR)/%.verilator.cyclescorrect.txt,$(SRCS_VERILATOR))

RES = $(TERRAOUT)
RES += $(VERILATOR)
RES += $(ISIM)
RES += $(AXI)
RES += $(AXIBITS)
RES += $(AXI100)
RES += $(AXIBITS100)
RES += $(ASIC)

CD = cd out;
all: $(RES)

# keep make from deleting these intermediates
.SECONDARY:

dups: $(DUPS)

verilog: $(VERILOG)
	touch $(BUILDDIR)/verilog_done.txt
	date

wrapper: $(WRAPPER)
	touch $(BUILDDIR)/wrapper_done.txt
	date

terra: $(TERRAOUT)
	touch $(BUILDDIR)/terra_done.txt
	date

verilator: $(VERILATOR)
	touch $(BUILDDIR)/verilator_done.txt
	date

verilatorSIG16: $(VERILATOR_SIG16)
	touch $(BUILDDIR)/verilatorSIG16_done.txt
	date

verilatorSOC: $(VERILATOR_SOC)
	touch $(BUILDDIR)/verilatorSOC_done.txt
	date

yosysSOC: $(YOSYS_SOC)
	touch $(BUILDDIR)/yosysSOC_done.txt
	date

bjump: $(BJUMP)
	touch $(BUILDDIR)/bjump_done.txt
	date

state: $(STATE)
	touch $(BUILDDIR)/state_done.txt
	date

pulpino: $(PULPINO)
	touch $(BUILDDIR)/pulpino_done.txt
	date

isim: $(ISIM)

stats: $(STATS)

stats100: $(STATS100)

zynq20: $(AXI)

camerabits: $(CAMERABITS)

zynq100: $(AXI100)

zu9vivado: $(ZU9VIVADO)

zu9vivadobits: $(ZU9VIVADOBITS)

zu9vivadoSOCbits: $(ZU9VIVADOSOCBITS)

SIG20: $(ZU9VIVADOSOCBITS_SIG20)

SIG16: $(ZU9VIVADOBITS_SIG16)

zu9vivadoSOC: $(ZU9VIVADOSOC)

axiverilog: $(AXIVERILOG)
	touch $(BUILDDIR)/axiverilog_done.txt

zynq20bits: $(AXIBITS)

zynq100bits: $(AXIBITS100)

cora10vivado: $(CORA10VIVADO)

cora10vivadobits: $(CORA10VIVADOBITS)

asic: $(ASIC)

coverage: $(COVERAGE)
	touch $(BUILDDIR)/coverage_done.txt


clean:
	rm -Rf $(BUILDDIR)/*

# this crazyness is to be able to write the output (runtime from time) to a file AND to stdout, and exit correctly :o
$(BUILDDIR)/%.v: %.lua
	{ time -p $(LUA) $< verilator; } 2>&1 | tee $(BUILDDIR)/$*.luatimeraw.txt; exit "$${PIPESTATUS[0]}"
	printf '$*,' > $(BUILDDIR)/$*.luatime.txt
	cat $(BUILDDIR)/$*.luatimeraw.txt | grep user | grep -Eo "[0-9\.]+" >> $(BUILDDIR)/$*.luatime.txt
	rm $(BUILDDIR)/$*.luatimeraw.txt
	# keep copy for future reference
	mkdir -p $(BUILDDIR)/$*_build
	cp $(BUILDDIR)/$*.v $(BUILDDIR)/$*_build

$(BUILDDIR)/%.v: %.t
	$(TERRA) $< verilator
	# keep copy for future reference
	mkdir -p $(BUILDDIR)/$*_build
	- cp $(BUILDDIR)/$*.v $(BUILDDIR)/$*_build

$(BUILDDIR)/%.v.mpsocwrapper.v: $(BUILDDIR)/%.v 
	$(LUA) ../platform/axi/wrapper.lua $(BUILDDIR)/$*.v $(BUILDDIR)/$*.metadata.lua $@ ../platform/ mpsoc

$(BUILDDIR)/%.coverage.txt: %.lua
	$(LUA) -lluacov $< verilator
	luacov-coveralls -v
	touch $@

$(BUILDDIR)/%.terra.raw: %.lua
	{ time -p $(TERRA) $< terra; } 2>&1 | tee $(BUILDDIR)/$*.terra.terratimeraw.txt; exit "$${PIPESTATUS[0]}"
	printf '$*,' > $(BUILDDIR)/$*.terra.terratime.txt
	cat $(BUILDDIR)/$*.terra.terratimeraw.txt | grep user | grep -Eo "[0-9\.]+" >> $(BUILDDIR)/$*.terra.terratime.txt
	rm $(BUILDDIR)/$*.terra.terratimeraw.txt
	# keep copy for future reference
	mkdir -p $(BUILDDIR)/$*_build
	#- cp $(BUILDDIR)/$*.cycles.txt $(BUILDDIR)/build_$*

$(BUILDDIR)/%.isim.v $(BUILDDIR)/%_half.isim.v: %.lua
	$(LUA) $< isim
	# keep copy for future reference
	mkdir -p $(BUILDDIR)/$*_build
	- cp $(BUILDDIR)/$*.isim.v $(BUILDDIR)/$*_build

$(BUILDDIR)/%.axi.v: %.lua
	$(LUA) $< axi
	# keep copy for future reference
	mkdir -p $(BUILDDIR)/build_$*
	- cp $(BUILDDIR)/$*.axi.v $(BUILDDIR)/build_$*
	mkdir -p $(BUILDDIR)/build100_$*
	- cp $(BUILDDIR)/$*.axi.v $(BUILDDIR)/build100_$*

#/opt/Xilinx/14.5/ISE_DS/ISE/verilog/src/unisims
#	verilator -cc -Mdir $(BUILDDIR)/$*_verilator  /opt/Xilinx/14.5/ISE_DS/ISE/verilog/src/unisims/RAMB16_S36_S36.v $(BUILDDIR)/$*.verilator.v
$(BUILDDIR)/%.verilator: $(BUILDDIR)/%.v ../platform/verilator/harness.cpp
	../platform/verilator/compile $(BUILDDIR)/$*.v $(BUILDDIR)/$*.metadata.lua $(BUILDDIR)/$*_verilator $@

$(BUILDDIR)/%.hz.txt: $(BUILDDIR)/%.axi.bit
	$(eval $@_HZl := $(shell grep Maximum $(BUILDDIR)/build_$*/OUT_trce.txt  | grep -P -o "[0-9.]+" | tail -1 | tr -d '\n' | awk '{print $$1" * 1000000"}' | bc -l | xargs printf "%d"))
	echo $($@_HZl) > $(BUILDDIR)/$*.hz.txt

$(BUILDDIR)/%.raw.dup : %.raw
	cat $*.raw > $@
	cat $*.raw >> $@

$(BUILDDIR)/%.stats.txt : $(BUILDDIR)/%.axi.bmp
	../misc/stats.sh $(BUILDDIR)/build_$* $(BUILDDIR)/$* $* axi $@

$(BUILDDIR)/%.stats100.txt : $(BUILDDIR)/%.zynq100.bmp
	../misc/stats.sh $(BUILDDIR)/build100_$* $(BUILDDIR)/$* $* axi100 $@

$(BUILDDIR)/%.zu9vivado.stats2020.txt : $(BUILDDIR)/%.zu9vivado.brams.txt $(BUILDDIR)/%.zu9vivado.clbs.txt $(BUILDDIR)/%.zu9vivado.dsps.txt $(BUILDDIR)/%.verilator.correct.txt
	../misc/stats2020.sh $*

$(BUILDDIR)/%.zu9vivadoSOC.stats2020.txt : $(BUILDDIR)/%.zu9vivadoSOC.brams.txt $(BUILDDIR)/%.zu9vivadoSOC.clbs.txt $(BUILDDIR)/%.zu9vivadoSOC.dsps.txt $(BUILDDIR)/%.verilatorSOC.correct.txt
	../misc/stats2020.sh $* SOC

$(BUILDDIR)/%.32nm.txt : $(BUILDDIR)/%.v
	$(eval $@_TOP := $(shell luajit ../misc/extractMetadata.lua $(BUILDDIR)/$*.metadata.lua topModule))
	mkdir -p $(BUILDDIR)/$*_32nm
	cp $(BUILDDIR)/$*.v $(BUILDDIR)/$*_32nm
	cd $(BUILDDIR)/$*_32nm; dc_shell -x 'set TOP $($@_TOP); set FILE $*.v; set OUTFILE ../$*.32nm.txt; set DDCFILE $*.ddc; set SYNFILE $*.synthesis.v;' -f ../../../platform/32nm/32nm.tcl > OUT.txt

$(BUILDDIR)/%.32nmpnr.txt : $(BUILDDIR)/%.32nm.txt
	$(eval $@_TOP := $(shell luajit ../misc/extractMetadata.lua $(BUILDDIR)/$*.metadata.lua topModule))
	rm -Rf $(BUILDDIR)/$*_32nm/chiptop.mw
	cd $(BUILDDIR)/$*_32nm; icc_shell -x 'set TOP $($@_TOP); set FILE $*.v; set OUTFILE ../$*.32nmpnr.txt; set DDCFILE $*.ddc; set SYNFILE $*.synthesis.v;' -f ../../../platform/32nm/32nm_icc.tcl

$(BUILDDIR)/%.zu9vivado.clbs.txt: $(BUILDDIR)/%.zu9vivado.bit
	 cat $(BUILDDIR)/$*_zu9vivado/utilization.txt | grep "CLB\s*|" | grep -P -o "[0-9]+" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivadoSOC.clbs.txt: $(BUILDDIR)/%.zu9vivadoSOC.bit
	 cat $(BUILDDIR)/$*_zu9vivadoSOC/utilization.txt | grep "CLB\s*|" | grep -P -o "[0-9]+" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivado.dsps.txt: $(BUILDDIR)/%.zu9vivado.bit
	 cat $(BUILDDIR)/$*_zu9vivado/utilization.txt | grep "DSPs" | grep -P -o "[0-9]+" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivadoSOC.dsps.txt: $(BUILDDIR)/%.zu9vivadoSOC.bit
	 cat $(BUILDDIR)/$*_zu9vivadoSOC/utilization.txt | grep "DSPs" | grep -P -o "[0-9]+" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivado.luts.txt: $(BUILDDIR)/%.zu9vivado.bit
	 cat $(BUILDDIR)/$*_zu9vivado/utilization.txt | grep "CLB LUTs" | grep -P -o "[0-9]+" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivado.lutscorrect.txt: $(BUILDDIR)/%.zu9vivado.luts.txt
	$(LUA) ../misc/approxnumdiff.lua $^ gold/$*.zu9vivado.luts.txt $@ 0 smallerIsBetter

$(BUILDDIR)/%.zu9vivado.brams.txt: $(BUILDDIR)/%.zu9vivado.bit
	 cat $(BUILDDIR)/$*_zu9vivado/utilization.txt | grep "Block RAM Tile" | grep -P -o "\d*\.?\d*" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivadoSOC.brams.txt: $(BUILDDIR)/%.zu9vivadoSOC.bit
	 cat $(BUILDDIR)/$*_zu9vivadoSOC/utilization.txt | grep "Block RAM Tile" | grep -P -o "\d*\.?\d*" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivado.bramscorrect.txt: $(BUILDDIR)/%.zu9vivado.brams.txt
	$(LUA) ../misc/approxnumdiff.lua $^ gold/$*.zu9vivado.brams.txt $@ 0 smallerIsBetter

$(BUILDDIR)/%.zu9vivado.dsps.txt: $(BUILDDIR)/%.zu9vivado.bit
	 cat $(BUILDDIR)/$*_zu9vivado/utilization.txt | grep "DSPs" | grep -P -o "[0-9]+" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivado.dspscorrect.txt: $(BUILDDIR)/%.zu9vivado.dsps.txt
	$(LUA) ../misc/approxnumdiff.lua $^ gold/$*.zu9vivado.dsps.txt $@ 0 smallerIsBetter

$(BUILDDIR)/%.zu9vivado.mhz.txt: $(BUILDDIR)/%.zu9vivado.bit
	 cat $(BUILDDIR)/$*_zu9vivado/vivado.log | grep "arrival time" | head -2 | tail -1 | grep -P -o "[0-9]+\.[0-9]+" | xargs printf "scale=5; (1/%f)*1000\n" | bc | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivado.mhzcorrect.txt: $(BUILDDIR)/%.zu9vivado.mhz.txt
	$(LUA) ../misc/approxnumdiff.lua $^ gold/$*.zu9vivado.mhz.txt $@ 0 largerIsBetter

$(BUILDDIR)/%.zu9vivado.perfcorrect.txt: $(BUILDDIR)/%.zu9vivado.lutscorrect.txt $(BUILDDIR)/%.zu9vivado.bramscorrect.txt $(BUILDDIR)/%.zu9vivado.dspscorrect.txt $(BUILDDIR)/%.zu9vivado.mhzcorrect.txt
	touch $@

$(BUILDDIR)/%.yosysSOC.cells.txt: $(BUILDDIR)/%.yosysSOC.bit
	 cat $(BUILDDIR)/$*_yosysSOC/log.txt | grep "Number of cells:" | tail -n 1 | grep -Eo "[0-9]+" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.yosysSOC.cellscorrect.txt: $(BUILDDIR)/%.yosysSOC.cells.txt
	$(LUA) ../misc/approxnumdiff.lua $^ gold/$*.yosysSOC.cells.txt $@ 0.02 smallerIsBetter

$(BUILDDIR)/%.yosysSOC.RAMB16_S9_S9.txt: $(BUILDDIR)/%.yosysSOC.bit
	 cat $(BUILDDIR)/$*_yosysSOC/log.txt | grep "RAMB16_S9_S9" | tail -n 1 | grep -Eo "[0-9]+" | tail -1 | tr -d '\n' > $@

$(BUILDDIR)/%.yosysSOC.RAMB16_S9_S9correct.txt: $(BUILDDIR)/%.yosysSOC.RAMB16_S9_S9.txt
	$(LUA) ../misc/approxnumdiff.lua $^ gold/$*.yosysSOC.RAMB16_S9_S9.txt $@ 0.02 smallerIsBetter

$(BUILDDIR)/%.yosysSOC.RAMB16_S36_S36.txt: $(BUILDDIR)/%.yosysSOC.bit
	 cat $(BUILDDIR)/$*_yosysSOC/log.txt | grep "RAMB16_S36_S36" | tail -n 1 | grep -Eo "[0-9]+" | tail -1 | tr -d '\n' > $@

$(BUILDDIR)/%.yosysSOC.RAMB16_S36_S36correct.txt: $(BUILDDIR)/%.yosysSOC.RAMB16_S36_S36.txt
	$(LUA) ../misc/approxnumdiff.lua $^ gold/$*.yosysSOC.RAMB16_S36_S36.txt $@ 0.02 smallerIsBetter

$(BUILDDIR)/%.yosysSOC.RAM128X1D.txt: $(BUILDDIR)/%.yosysSOC.bit
	 cat $(BUILDDIR)/$*_yosysSOC/log.txt | grep "RAM128X1D" | tail -n 1 | grep -Eo "[0-9]+" | tail -1 | tr -d '\n' > $@

$(BUILDDIR)/%.yosysSOC.RAM128X1Dcorrect.txt: $(BUILDDIR)/%.yosysSOC.RAM128X1D.txt
	$(LUA) ../misc/approxnumdiff.lua $^ gold/$*.yosysSOC.RAM128X1D.txt $@ 0.02 smallerIsBetter

$(BUILDDIR)/%.yosysSOC.correct.txt: $(BUILDDIR)/%.yosysSOC.RAM128X1Dcorrect.txt $(BUILDDIR)/%.yosysSOC.RAMB16_S36_S36correct.txt $(BUILDDIR)/%.yosysSOC.RAMB16_S9_S9correct.txt $(BUILDDIR)/%.yosysSOC.cellscorrect.txt
	touch $@

include ../platform/platform.mk

# hack: terra doesn't write out reg info, so skip
$(BUILDDIR)/%.terra.regcorrect.txt: $(BUILDDIR)/%.terra.bmp
	touch $@

$(BUILDDIR)/%.verilator.regcorrect.txt: $(BUILDDIR)/%.verilator.bmp
	touch $@
