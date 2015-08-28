local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"

W = 128
H = 64
T = 8

inp = S.parameter("inp",types.uint(8))
plus100 = d.lift( "plus100", types.uint(8), types.uint(8) , 10, terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, inp, inp + S.constant(100,types.uint(8)) )
------------
ITYPE = types.array2d( types.uint(8), T )
------------
local fifos = { d.instantiateRegistered("f1",d.fifo(ITYPE,128))}

A = d.input( d.StatefulHandshake(ITYPE) )

local muxout = d.applyMethod("L1", fifos[1],"load")


local out = darkroom.apply("toHandshakeArray", d.toHandshakeArray(ITYPE,{{1,2},{1,2}}), d.array2d("sa",{A,muxout},2,1,false))

local SER = darkroom.serialize( ITYPE, {{1,2},{1,2}}, d.interleveSchedule( 2, 2 ) ) 
local out = darkroom.apply("ser", SER, out )

multiplexed = d.apply( "plus100", d.makeHandshake(d.map(plus100,8),{{1,2},{1,2}}), out )
local out = darkroom.apply("demux", darkroom.demux(ITYPE,{{1,2},{1,2}}), multiplexed )


hsfn = d.lambda( "tmux_wide", A, d.statements{ d.selectStream("i1",out,1), d.applyMethod("s1",fifos[1],"store",d.selectStream("i0",out,0)) }, fifos )


harness.axi( "tmux_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)