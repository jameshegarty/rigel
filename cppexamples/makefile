SRCS = soc_simple.cpp
SRCS += soc_convgenTaps_4_4.cpp

LUA = $(patsubst %.cpp,out/%.lua,$(SRCS))
LUA += $(patsubst %.cpp,out/%,$(SRCS))


all: $(LUA)

lua: $(LUA)

clean:
	rm -Rf out/*

out/%: %.cpp
	g++ -o $@ -I../cppsrc -std=c++17 $^

out/%.lua: out/%
	./out/$*
