# isim is crap, and if we run multiple processes at the same time in the same directory, they will clobber each other. So we need to run in different directories.
out/%.isim.raw: out/%.isim.v $(DUPS)
	mkdir -p out/sim_$*
	cd out/sim_$*; vlogcomp ../$*.isim.v
	cd out/sim_$*; fuse -o $* -lib $* -L unisim -L unimacro -top sim
	cd out/sim_$*; echo "run all" | ./$* > output.txt
	split -n 2 -d out/sim_$*/$*.isim.raw out/sim_$*/S
	mv out/sim_$*/S00 out/$*.isim.raw
	mv out/sim_$*/S01 out/$*.isim.1.raw
	$(TERRA) ../misc/extractCycles.t out/$*.isim.raw > out/$*.isim.cycles.txt
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.isim.cycles.txt out/build_$*

out/%.isim.bmp: out/%.isim.raw out/%.metadata.lua
	$(LUA) ../misc/raw2bmp.lua out/$*.isim.raw out/$*.isim.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.isim.bmp out/build_$*

out/%.isim.1.bmp: out/%.isim.raw out/%.metadata.lua
	$(LUA) ../misc/raw2bmp.lua out/$*.isim.1.raw out/$*.isim.1.bmp out/$*.metadata.lua 1
	# keep copy for future reference
	mkdir -p out/build_$*
	cp out/$*.isim.1.bmp out/build_$*

out/%_half.isim.correct.txt : out/%_half.isim.bmp
	diff out/$*_half.isim.bmp gold/$*.bmp > out/$*_half.isim.diff
	test ! -s out/$*_half.isim.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build_$*
	test ! -s out/$*_half.isim.diff && touch out/build_$*/$*_half.isim.correct.txt

out/%.isim.correct.txt : out/%.isim.bmp
	diff out/$*.isim.bmp gold/$*.bmp > out/$*.isim.diff
	test ! -s out/$*.isim.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build_$*
	test ! -s out/$*.isim.diff && touch out/build_$*/$*.isim.correct.txt

out/%.isim.1.correct.txt : out/%.isim.1.bmp
	diff out/$*.isim.1.bmp gold/$*.bmp > out/$*.isim.1.diff
	test ! -s out/$*.isim.1.diff && touch $@
	# keep copy for future reference
	mkdir -p out/build_$*
	test ! -s out/$*.isim.1.diff && touch out/build_$*/$*.isim.1.correct.txt
