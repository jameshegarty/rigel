all:
	../rigelTerra moduleparams.lua

	../rigelTerra fwriteseq.lua terrasim
	../rigelLuajit fwriteseq.lua

	# build all .v files
	make -f makefile.compare

	#fwriteSeq test
	diff out/fwriteseqtest.raw out/fwriteseqtestVerilog.raw > out/fwriteseqtest.diff

clean:
	rm -Rf out/*
