LUA = ../rigelLuajit
LUAJIT = ../rigelLuajit
TERRA = ../rigelTerra

BUILDDIR ?= out

SRCSCPP = soc_simple.cpp
SRCSCPP += soc_convgenTaps.cpp

SRCSLUA = out/soc_simple.lua

SRCSLUA += out/soc_convgenTaps_8_1.lua out/soc_convgenTaps_8_2.lua out/soc_convgenTaps_8_4.lua out/soc_convgenTaps_8_8.lua
SRCSLUA += out/soc_convgenTaps_8_1_autofifo.lua out/soc_convgenTaps_8_2_autofifo.lua out/soc_convgenTaps_8_4_autofifo.lua out/soc_convgenTaps_8_8_autofifo.lua

SRCSLUA += out/soc_stereo_full_64_4.lua out/soc_stereo_full_64_8.lua out/soc_stereo_full_64_16.lua out/soc_stereo_full_64_32.lua out/soc_stereo_full_64_64.lua
SRCSLUA += out/soc_stereo_full_64_4_autofifo.lua out/soc_stereo_full_64_8_autofifo.lua out/soc_stereo_full_64_16_autofifo.lua out/soc_stereo_full_64_32_autofifo.lua out/soc_stereo_full_64_64_autofifo.lua

SRCSLUA += out/soc_lk_12_1.lua out/soc_lk_12_2.lua out/soc_lk_12_3.lua out/soc_lk_12_4.lua out/soc_lk_12_6.lua out/soc_lk_12_12.lua out/soc_lk_12_24.lua out/soc_lk_12_48.lua

SRCSLUA += out/soc_sift_4_64_1080p.lua out/soc_sift_4_128_1080p.lua out/soc_sift_4_256_1080p.lua
SRCSLUA += out/soc_sift_4_64_1080p_autofifo.lua out/soc_sift_4_128_1080p_autofifo.lua out/soc_sift_4_256_1080p_autofifo.lua

CPP += $(patsubst %.cpp,out/%,$(SRCSCPP))

VERILOG = $(patsubst out/%.lua,out/%.v,$(SRCSLUA))

VERILATORSOC = $(patsubst out/%.lua,out/%.verilatorSOC.raw,$(SRCSLUA))
VERILATORSOC += $(patsubst out/%.lua,out/%.verilatorSOC.correct.txt,$(SRCSLUA))

all: $(CPP) $(SRCSLUA) $(VERILOG) $(VERILATORSOC)

clean:
	rm -Rf out/*

out/%: %.cpp
	g++ -o $@ -I../cppsrc -std=c++11 $^

out/%.lua: out/%
	./out/$*

out/soc_convgenTaps_8_1.lua out/soc_convgenTaps_8_2.lua out/soc_convgenTaps_8_4.lua out/soc_convgenTaps_8_8.lua: out/soc_convgenTaps
	./out/soc_convgenTaps

out/soc_stereo_full_64_4.lua out/soc_stereo_full_64_8.lua out/soc_stereo_full_64_16.lua out/soc_stereo_full_64_32.lua out/soc_stereo_full_64_64.lua: out/soc_stereo
	./out/soc_stereo

out/soc_lk_12_1.lua out/soc_lk_12_2.lua out/soc_lk_12_3.lua out/soc_lk_12_4.lua out/soc_lk_12_6.lua out/soc_lk_12_12.lua out/soc_lk_12_24.lua out/soc_lk_12_48.lua: out/soc_lk
	./out/soc_lk

out/soc_sift_4_64_1080p.lua out/soc_sift_4_128_1080p.lua out/soc_sift_4_256_1080p.lua: out/soc_sift
	./out/soc_sift

out/%.v: out/%.lua
	../rigelLuajit $^

out/%.terra.raw: out/%.lua
	{ time -p $(TERRA) $< terra; } 2>&1 | tee $(BUILDDIR)/$*.terra.terratimeraw.txt; exit "$${PIPESTATUS[0]}"
	printf '$*,' > $(BUILDDIR)/$*.terra.terratime.txt
	cat $(BUILDDIR)/$*.terra.terratimeraw.txt | grep user | grep -Eo "[0-9\.]+" >> $(BUILDDIR)/$*.terra.terratime.txt
	rm $(BUILDDIR)/$*.terra.terratimeraw.txt
	# keep copy for future reference
	mkdir -p $(BUILDDIR)/$*_build

$(BUILDDIR)/%.zu9vivadoSOC.clbs.txt: $(BUILDDIR)/%.zu9vivadoSOC.bit
	 cat $(BUILDDIR)/$*_zu9vivadoSOC/utilization.txt | grep "CLB\s*|" | grep -P -o "[0-9]+" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivadoSOC.dsps.txt: $(BUILDDIR)/%.zu9vivadoSOC.bit
	 cat $(BUILDDIR)/$*_zu9vivadoSOC/utilization.txt | grep "DSPs" | grep -P -o "[0-9]+" | head -1 | tr -d '\n' > $@

$(BUILDDIR)/%.zu9vivadoSOC.brams.txt: $(BUILDDIR)/%.zu9vivadoSOC.bit
	 cat $(BUILDDIR)/$*_zu9vivadoSOC/utilization.txt | grep "Block RAM Tile" | grep -P -o "\d*\.?\d*" | head -1 | tr -d '\n' > $@


$(BUILDDIR)/%.zu9vivadoSOC.stats2020.txt : $(BUILDDIR)/%.zu9vivadoSOC.brams.txt $(BUILDDIR)/%.zu9vivadoSOC.clbs.txt $(BUILDDIR)/%.zu9vivadoSOC.dsps.txt $(BUILDDIR)/%.verilatorSOC.correct.txt
	../misc/stats2020.sh $* SOC

include ../platform/platform.mk
