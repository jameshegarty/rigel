SRCS = $(wildcard *.lua)

# we do 3 phases
# 1) compile to .v and writes terra .bmp (test dependent)
# 2) run all .v files in verilator, and checks that results match terra (when both files exists)
# 3) extra test dependant correctness checks

COMPILE_TARGETS = $(patsubst %.lua,out/%.compiles.txt,$(SRCS))

TARGETS = $(COMPILE_TARGETS)
TARGETS += out/verilogcorrect.txt
TARGETS += $(patsubst %.lua,out/%.correct.txt,$(SRCS))

CORES ?= 2

all: $(TARGETS)

# build all .v files
out/verilogcorrect.txt: $(COMPILE_TARGETS)
	make -j $(CORES) -f makefile.compileverilog

#################
out/moduleparams.compiles.txt: moduleparams.lua
	../rigelTerra moduleparams.lua

out/moduleparams.correct.txt: out/verilogcorrect.txt
	# no extra checks
	touch out/moduleparams.correct.txt

#################
out/fixedtest.compiles.txt: fixedtest.lua
	../rigelTerra fixedtest.lua

out/fixedtest.correct.txt: out/verilogcorrect.txt
	diff out/dbg_terra_writePixelTest.raw out/fixed_testwritepx.terra.raw > out/fixed_testwritepx_tt.diff
	diff out/dbg_verilog_writePixelTest.raw out/fixed_testwritepx.terra.raw > out/fixed_testwritepx_vv.diff

	diff gold/dbg_terra_gt.raw out/dbg_terra_gt.raw > out/dbg_fixedtest_gt.diff
	diff gold/dbg_terra_gt.raw out/dbg_verilog_gt.raw > out/dbg_fixedtest_gt.diff
	diff gold/dbg_gt.metadata.lua out/dbg_gt.metadata.lua > out/dbg_fixedtest_gt.metadata.diff

	diff gold/dbg_verilog_removelsbs.raw out/dbg_terra_removelsbs.raw > out/dbg_fixedtest_removelsbs.diff
	diff gold/dbg_verilog_removelsbs.raw out/dbg_verilog_removelsbs.raw > out/dbg_fixedtest_removelsbs.diff
	diff gold/dbg_removelsbs.metadata.lua out/dbg_removelsbs.metadata.lua > out/dbg_fixedtest_removelsbs.metadata.diff

	diff gold/dbg_verilog_removemsbs.raw out/dbg_terra_removemsbs.raw > out/dbg_fixedtest_removemsbs.diff
	diff gold/dbg_verilog_removemsbs.raw out/dbg_verilog_removemsbs.raw > out/dbg_fixedtest_removemsbs.diff
	diff gold/dbg_removemsbs.metadata.lua out/dbg_removemsbs.metadata.lua > out/dbg_fixedtest_removemsbs.metadata.diff

	touch out/fixedtest.correct.txt

###################
out/fwriteseq.compiles.txt: fwriteseq.lua
	../rigelTerra fwriteseq.lua terra
	../rigelLuajit fwriteseq.lua verilog
	../rigelLuajit fwriteseq.lua metadata

out/fwriteseq.correct.txt: out/verilogcorrect.txt
	diff out/fwriteseqtest.raw out/fwriteseqtestVerilog.raw > out/fwriteseqtest.diff
	test ! -s out/$*.fwriteseqtest.diff && touch $@
###################
out/fwriteseq16.compiles.txt: fwriteseq16.lua
	../rigelTerra fwriteseq16.lua terra
	../rigelLuajit fwriteseq16.lua verilog
	../rigelLuajit fwriteseq16.lua metadata

out/fwriteseq16.correct.txt: out/verilogcorrect.txt
	diff out/fwriteseq16test.raw out/fwriteseq16testVerilog.raw > out/fwriteseq16test.diff
	test ! -s out/$*.fwriteseq16test.diff && touch $@
###################
out/fwriteseq12.compiles.txt: fwriteseq12.lua
	../rigelTerra fwriteseq12.lua terra
	../rigelLuajit fwriteseq12.lua verilog
	../rigelLuajit fwriteseq12.lua metadata

out/fwriteseq12.correct.txt: out/verilogcorrect.txt
	diff out/fwriteseq16test.raw out/dbg_terra_fwriteseq12.raw > out/fwriteseq12test.diff
	diff out/fwriteseq16test.raw out/dbg_verilog_fwriteseq12.raw > out/fwriteseq12testVerilog.diff
	test ! -s out/$*.fwriteseq12testVerilog.diff && touch $@
###################
out/fwriteseq18.compiles.txt: fwriteseq18.lua
	../rigelTerra fwriteseq18.lua terra
	../rigelLuajit fwriteseq18.lua verilog
	../rigelLuajit fwriteseq18.lua metadata

out/fwriteseq18.correct.txt: out/verilogcorrect.txt
	diff out/dbg_terra_fwriteseq18.raw out/dbg_verilog_fwriteseq18.raw > out/fwriteseq18test.diff
	test ! -s out/$*.fwriteseq18test.diff && touch $@
###################
out/fwriteseq24.compiles.txt: fwriteseq24.lua
	../rigelTerra fwriteseq24.lua terra
	../rigelLuajit fwriteseq24.lua verilog
	../rigelLuajit fwriteseq24.lua metadata

out/fwriteseq24.correct.txt: out/verilogcorrect.txt
	diff out/dbg_terra_fwriteseq24.raw out/dbg_verilog_fwriteseq24.raw > out/fwriteseq24test.diff
	diff out/fwriteseq24.terra.raw out/dbg_terra_fwriteseq24.raw > out/fwriteseq24test2.diff
	diff out/fwriteseq24.terra.raw out/dbg_verilog_fwriteseq24.raw > out/fwriteseq24testVerilog.diff
	test ! -s out/$*.fwriteseq24test.diff && touch $@
###################
out/fwriteseq37.compiles.txt: fwriteseq37.lua
	../rigelTerra fwriteseq37.lua terra
	../rigelLuajit fwriteseq37.lua verilog
	../rigelLuajit fwriteseq37.lua metadata

out/fwriteseq37.correct.txt: out/verilogcorrect.txt
	diff out/dbg_terra_fwriteseq37.raw out/dbg_verilog_fwriteseq37.raw > out/fwriteseq37test.diff
	test ! -s out/$*.fwriteseq37test.diff && touch $@
###################

clean:
	echo out/* | xargs -n 100 rm -Rf
