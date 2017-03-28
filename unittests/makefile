SRCS = $(wildcard *.lua)

# we do 3 phases
# 1) compile to .v and writes terra .bmp (test dependent)
# 2) run all .v files in verilator, and checks that results match terra (when both files exists)
# 3) extra test dependant correctness checks

COMPILE_TARGETS = $(patsubst %.lua,out/%.compiles.txt,$(SRCS))

TARGETS = $(COMPILE_TARGETS)
TARGETS += out/verilogcorrect.txt
TARGETS += $(patsubst %.lua,out/%.correct.txt,$(SRCS))

all: $(TARGETS)

# build all .v files
out/verilogcorrect.txt: $(COMPILE_TARGETS)
	make -f makefile.compileverilog

out/moduleparams.compiles.txt: moduleparams.lua
	../rigelTerra moduleparams.lua

out/moduleparams.correct.txt: out/verilogcorrect.txt
	touch out/moduleparams.correct.txt

out/fwriteseq.compiles.txt: fwriteseq.lua
	../rigelTerra fwriteseq.lua terrasim
	../rigelLuajit fwriteseq.lua

out/fwriteseq.correct.txt: out/verilogcorrect.txt
	diff out/fwriteseqtest.raw out/fwriteseqtestVerilog.raw > out/fwriteseqtest.diff
	test ! -s out/$*.fwriteseqtest.diff && touch $@

out/fwriteseq16.compiles.txt: fwriteseq16.lua
	../rigelTerra fwriteseq16.lua terrasim
	../rigelLuajit fwriteseq16.lua

out/fwriteseq16.correct.txt: out/verilogcorrect.txt
	diff out/fwriteseq16test.raw out/fwriteseq16testVerilog.raw > out/fwriteseq16test.diff
	test ! -s out/$*.fwriteseq16test.diff && touch $@

clean:
	rm -Rf out/*
