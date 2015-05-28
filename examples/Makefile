SRCS = $(wildcard *.t)
RES = $(patsubst %.t,out/%.bmp,$(SRCS))
RES += $(patsubst %.t,out/%.bmp.correct.txt,$(SRCS))

SIM = $(patsubst %.t,out/%.sim.bmp,$(SRCS))
SIM += $(patsubst %.t,out/%.sim.raw,$(SRCS))
SIM += $(patsubst %.t,out/%.sim.correct.txt,$(SRCS))
SIM += $(patsubst %.t,out/%.sim.v,$(SRCS))

RES += $(SIM)

all: $(RES)

clean:
	rm -Rf out/*

out/%.raw out/%.sim.v: %.t ../src/systolic.t ../darkroom.t
	terra $<

out/%.sim.raw: out/%.sim.v
	cd out; vlogcomp $*.sim.v
	cd out; fuse -o $* -lib $* -top sim
	cd out; echo "run all" | ./$*

out/%.sim.bmp: out/%.sim.raw
	terra ../extras/raw2bmp.t out/$*.sim.raw out/$*.sim.bmp out/$*.metadata.lua

out/%.bmp: out/%.raw
	terra ../extras/raw2bmp.t out/$*.raw out/$*.bmp out/$*.metadata.lua

out/%.sim.correct.txt : out/%.sim.bmp
	diff out/$*.sim.bmp gold/$*.bmp > out/$*.sim.diff
	test ! -s out/$*.sim.diff && touch $@

out/%.bmp.correct.txt : out/%.bmp
	diff out/$*.bmp gold/$*.bmp > out/$*.diff
	test ! -s out/$*.diff && touch $@