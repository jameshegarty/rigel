LUA = ../rigelLuajit
LUAJIT = ../rigelLuajit
TERRA = ../rigelTerra

SRCS = soc_simple.cpp
SRCS += soc_convgenTaps_4_4.cpp

LUAOUT = $(patsubst %.cpp,out/%.lua,$(SRCS))
LUAOUT += $(patsubst %.cpp,out/%,$(SRCS))

VERILOG = $(patsubst %.cpp,out/%.v,$(SRCS))

VERILATORSOC = $(patsubst %.cpp,out/%.verilatorSOC.raw,$(SRCS))
VERILATORSOC += $(patsubst %.cpp,out/%.verilatorSOC.correct.txt,$(SRCS))

all: $(LUAOUT) $(VERILOG) $(VERILATORSOC)

lua: $(LUAOUT)

clean:
	rm -Rf out/*

out/%: %.cpp
	g++ -o $@ -I../cppsrc -std=c++17 $^

out/%.lua: out/%
	./out/$*

out/%.v: out/%.lua
	../rigelLuajit $^

include ../platform/platform.mk
