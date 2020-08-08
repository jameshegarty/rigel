LUA = ../rigelLuajit
LUAJIT = ../rigelLuajit
TERRA = ../rigelTerra

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
	g++ -o $@ -I../cppsrc -std=c++17 $^

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

include ../platform/platform.mk
