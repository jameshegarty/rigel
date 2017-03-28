all:
	../rigelTerra moduleparams.lua

	../rigelTerra fwriteseq.lua terrasim
	../rigelLuajit fwriteseq.lua

	../rigelTerra fwriteseq16.lua terrasim
	../rigelLuajit fwriteseq16.lua

	# build all .v files
	make -f makefile.compare

	#fwriteSeq test
	diff out/fwriteseqtest.raw out/fwriteseqtestVerilog.raw > out/fwriteseqtest.diff
	diff out/fwriteseq16test.raw out/fwriteseq16testVerilog.raw > out/fwriteseq16test.diff

clean:
	rm -Rf out/*
