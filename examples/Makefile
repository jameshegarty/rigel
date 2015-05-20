SRCS = $(wildcard *.t)
RES = $(patsubst %.t,out/%.bmp,$(SRCS))
RES += $(patsubst %.t,out/%.bmp.correct.txt,$(SRCS))

all: $(RES)

clean:
	rm out/*

out/%.bmp : %.t
	terra $<

out/%.bmp.correct.txt : out/%.bmp
	diff out/$*.bmp gold/$*.bmp > out/$*.diff
	test ! -s out/$*.diff && touch $@