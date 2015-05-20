SRCS = $(wildcard *.t)
RES = $(patsubst %.t,out/%.bmp,$(SRCS))
RES += $(patsubst %.t,out/%.bmp.correct.txt,$(SRCS))

SIM = $(patsubst %.t,out/%.sim.bmp,$(SRCS))
SIM += $(patsubst %.t,out/%.sim.correct.txt,$(SRCS))
SIM += $(patsubst %.t,out/%.sim.v,$(SRCS))

all: $(RES)

clean:
	rm out/*

out/%.bmp out/%.sim.v: %.t
	terra $<

out/%.sim.raw: out/%.sim.v
	vlogcomp out/$*.sim.v; fuse -o $* -lib $* -top sim

out/%.bmp.correct.txt : out/%.bmp
	diff out/$*.bmp gold/$*.bmp > out/$*.diff
	test ! -s out/$*.diff && touch $@