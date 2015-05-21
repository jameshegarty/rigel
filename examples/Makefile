SRCS = $(wildcard *.t)
RES = $(patsubst %.t,out/%.bmp,$(SRCS))
RES += $(patsubst %.t,out/%.bmp.correct.txt,$(SRCS))

SIM = $(patsubst %.t,out/%.sim.bmp,$(SRCS))
SIM += $(patsubst %.t,out/%.sim.correct.txt,$(SRCS))
SIM += $(patsubst %.t,out/%.sim.v,$(SRCS))

RES += $(SIM)

all: $(RES)

clean:
	rm -Rf out/*

out/%.bmp out/%.sim.v: %.t
	terra $<

out/%.sim.raw: out/%.sim.v
	cd out; vlogcomp $*.sim.v
	cd out; fuse -o $* -lib $* -top sim
	cd out; echo "run all" | ./$*

out/%.bmp.correct.txt : out/%.bmp
	diff out/$*.bmp gold/$*.bmp > out/$*.diff
	test ! -s out/$*.diff && touch $@