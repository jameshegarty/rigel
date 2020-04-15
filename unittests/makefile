SRCS = $(wildcard *.lua)
SRCS := $(filter-out moduleparams_core.lua,$(SRCS))

BUILDDIR := out

# we do 3 phases
# 1) compile to .v and writes terra .bmp (test dependent)
# 2) run all .v files in verilator, and checks that results match terra (when both files exists)
# 3) extra test dependant correctness checks

COMPILE_TARGETS = $(patsubst %.lua,$(BUILDDIR)/%.compiles.txt,$(SRCS))

TARGETS = $(COMPILE_TARGETS)
TARGETS += $(BUILDDIR)/verilogcorrect.txt
TARGETS += $(patsubst %.lua,$(BUILDDIR)/%.correct.txt,$(SRCS))

CORES ?= 2

LUA ?= ../rigelLuajit
LUAJIT ?= ../rigelLuajit

all: $(TARGETS)

# build all .v files
$(BUILDDIR)/verilogcorrect.txt: $(COMPILE_TARGETS)
	make -j $(CORES) -f makefile.compileverilog

#################
$(BUILDDIR)/moduleparams.compiles.txt: moduleparams.lua
	../rigelTerra moduleparams.lua

$(BUILDDIR)/moduleparams.correct.txt: $(BUILDDIR)/verilogcorrect.txt
	# no extra checks
	touch $(BUILDDIR)/moduleparams.correct.txt

#################
$(BUILDDIR)/moduleparams_downsample.compiles.txt: moduleparams_downsample.lua
	../rigelTerra moduleparams_downsample.lua

$(BUILDDIR)/moduleparams_downsample.correct.txt: $(BUILDDIR)/verilogcorrect.txt
	# no extra checks
	touch $(BUILDDIR)/moduleparams_downsample.correct.txt

#################
$(BUILDDIR)/fixedtest.compiles.txt: fixedtest.lua
	../rigelTerra fixedtest.lua

$(BUILDDIR)/fixedtest.correct.txt: $(BUILDDIR)/verilogcorrect.txt
	diff $(BUILDDIR)/dbg_terra_writePixelTest.raw $(BUILDDIR)/fixed_testwritepx.terra.raw > $(BUILDDIR)/fixed_testwritepx_tt.diff
	diff $(BUILDDIR)/dbg_verilator_writePixelTest.raw $(BUILDDIR)/fixed_testwritepx.terra.raw > $(BUILDDIR)/fixed_testwritepx_vv.diff

	diff gold/dbg_terra_gt.raw $(BUILDDIR)/dbg_terra_gt.raw > $(BUILDDIR)/dbg_fixedtest_gt.diff
	diff gold/dbg_terra_gt.raw $(BUILDDIR)/dbg_verilator_gt.raw > $(BUILDDIR)/dbg_fixedtest_gt.diff
	diff gold/dbg_gt.metadata.lua $(BUILDDIR)/dbg_gt.metadata.lua > $(BUILDDIR)/dbg_fixedtest_gt.metadata.diff

	diff gold/dbg_verilator_removelsbs.raw $(BUILDDIR)/dbg_terra_removelsbs.raw > $(BUILDDIR)/dbg_fixedtest_removelsbs.diff
	diff gold/dbg_verilator_removelsbs.raw $(BUILDDIR)/dbg_verilator_removelsbs.raw > $(BUILDDIR)/dbg_fixedtest_removelsbs.diff
	diff gold/dbg_removelsbs.metadata.lua $(BUILDDIR)/dbg_removelsbs.metadata.lua > $(BUILDDIR)/dbg_fixedtest_removelsbs.metadata.diff

	diff gold/dbg_verilator_removemsbs.raw $(BUILDDIR)/dbg_terra_removemsbs.raw > $(BUILDDIR)/dbg_fixedtest_removemsbs.diff
	diff gold/dbg_verilator_removemsbs.raw $(BUILDDIR)/dbg_verilator_removemsbs.raw > $(BUILDDIR)/dbg_fixedtest_removemsbs.diff
	diff gold/dbg_removemsbs.metadata.lua $(BUILDDIR)/dbg_removemsbs.metadata.lua > $(BUILDDIR)/dbg_fixedtest_removemsbs.metadata.diff

	touch $(BUILDDIR)/fixedtest.correct.txt

###################
$(BUILDDIR)/fwriteseq.compiles.txt: fwriteseq.lua
	../rigelTerra fwriteseq.lua terra
	$(LUA) fwriteseq.lua verilog

$(BUILDDIR)/fwriteseq.correct.txt: $(BUILDDIR)/verilogcorrect.txt
	diff $(BUILDDIR)/fwriteseqtest.raw $(BUILDDIR)/fwriteseqtestVerilog.raw > $(BUILDDIR)/fwriteseqtest.diff
	test ! -s $(BUILDDIR)/$*.fwriteseqtest.diff && touch $@
###################
$(BUILDDIR)/fwriteseq16.compiles.txt: fwriteseq16.lua
	../rigelTerra fwriteseq16.lua terra
	$(LUA) fwriteseq16.lua verilog

$(BUILDDIR)/fwriteseq16.correct.txt: $(BUILDDIR)/verilogcorrect.txt
	diff $(BUILDDIR)/fwriteseq16test.raw $(BUILDDIR)/fwriteseq16testVerilog.raw > $(BUILDDIR)/fwriteseq16test.diff
	test ! -s $(BUILDDIR)/$*.fwriteseq16test.diff && touch $@
###################
$(BUILDDIR)/fwriteseq12.compiles.txt: fwriteseq12.lua
	../rigelTerra fwriteseq12.lua terra
	$(LUA) fwriteseq12.lua verilog

$(BUILDDIR)/fwriteseq12.correct.txt: $(BUILDDIR)/verilogcorrect.txt
	diff $(BUILDDIR)/fwriteseq16test.raw $(BUILDDIR)/fwriteseq12.terra.writePixels.raw > $(BUILDDIR)/fwriteseq12test.diff
	diff $(BUILDDIR)/fwriteseq16test.raw $(BUILDDIR)/fwriteseq12.verilatorSOC.writePixels.raw > $(BUILDDIR)/fwriteseq12testVerilog.diff
	test ! -s $(BUILDDIR)/$*.fwriteseq12testVerilog.diff && touch $@
###################
$(BUILDDIR)/fwriteseq18.compiles.txt: fwriteseq18.lua
	../rigelTerra fwriteseq18.lua terra
	$(LUA) fwriteseq18.lua verilog
#	$(LUA) fwriteseq18.lua metadata

$(BUILDDIR)/fwriteseq18.correct.txt: $(BUILDDIR)/verilogcorrect.txt
	diff $(BUILDDIR)/fwriteseq18.terra.writePixels.raw $(BUILDDIR)/fwriteseq18.verilatorSOC.writePixels.raw > $(BUILDDIR)/fwriteseq18test.diff
	test ! -s $(BUILDDIR)/$*.fwriteseq18test.diff && touch $@
###################
$(BUILDDIR)/fwriteseq24.compiles.txt: fwriteseq24.lua
	../rigelTerra fwriteseq24.lua terra
	$(LUA) fwriteseq24.lua verilog

$(BUILDDIR)/fwriteseq24.correct.txt: $(BUILDDIR)/verilogcorrect.txt
	diff $(BUILDDIR)/fwriteseq24.terra.writePixels.raw $(BUILDDIR)/fwriteseq24.verilatorSOC.writePixels.raw > $(BUILDDIR)/fwriteseq24test.diff
	diff $(BUILDDIR)/fwriteseq24.terra.raw $(BUILDDIR)/fwriteseq24.terra.writePixels.raw > $(BUILDDIR)/fwriteseq24test2.diff
	diff $(BUILDDIR)/fwriteseq24.terra.raw $(BUILDDIR)/fwriteseq24.verilatorSOC.writePixels.raw > $(BUILDDIR)/fwriteseq24testVerilog.diff
	test ! -s $(BUILDDIR)/$*.fwriteseq24test.diff && touch $@
###################
$(BUILDDIR)/fwriteseq37.compiles.txt: fwriteseq37.lua
	../rigelTerra fwriteseq37.lua terra
	$(LUA) fwriteseq37.lua verilog

$(BUILDDIR)/fwriteseq37.correct.txt: $(BUILDDIR)/verilogcorrect.txt
	diff $(BUILDDIR)/fwriteseq37.terra.writePixels.raw $(BUILDDIR)/fwriteseq37.verilatorSOC.writePixels.raw > $(BUILDDIR)/fwriteseq37test.diff
	test ! -s $(BUILDDIR)/$*.fwriteseq37test.diff && touch $@
###################

clean:
	echo $(BUILDDIR)/* | xargs -n 100 rm -Rf
