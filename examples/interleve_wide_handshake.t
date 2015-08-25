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
local BTYPE = types.tuple{ITYPE,types.uint(8)}
inp = S.parameter("inp",BTYPE)
ignoreBin = d.lift( "ignoreBin", BTYPE, ITYPE, 0, terra( a:&BTYPE:toTerraType(), out:&ITYPE:toTerraType()) @out = a._0 end, inp, S.index(inp,0) )
--ignoreBin = d.lift( "ignoreBin", BTYPE, ITYPE, 0, terra( a:&BTYPE:toTerraType(), out:&ITYPE:toTerraType()) @out = array(a._1,a._1,a._1,a._1,a._1,a._1,a._1,a._1) end, inp, S.index(inp,0) )
------------
local fifos = { d.instantiateRegistered("f1",d.fifo(ITYPE,128)), d.instantiateRegistered("f2",d.fifo(ITYPE,128)) }
--local fifos = { d.instantiateRegistered("f1",d.fifo(ITYPE,128))}

A = d.input( d.StatefulHandshake(ITYPE) )
local Abroadcast = d.apply("Abroadcast", d.broadcastStream(ITYPE,2), A)

--B = d.apply( "plus100", d.makeHandshake(d.makeStateful(d.map(plus100,8))), d.selectStream("A0",Abroadcast,0) )
local AinFifo1 = d.applyMethod("L1", fifos[1],"load")
B = d.apply( "plus100", d.makeHandshake(d.makeStateful(d.map(plus100,8))), AinFifo1 )



local AinFifo2 = d.applyMethod("L2", fifos[2],"load")

--local out = darkroom.apply("toHandshakeArray", d.toHandshakeArray(ITYPE,{{1,2},{1,2}}), d.array2d("sa",{d.selectStream("A1",Abroadcast,1),BinFifo},2,1,false))
local out = darkroom.apply("toHandshakeArray", d.toHandshakeArray(ITYPE,{{1,2},{1,2}}), d.array2d("sa",{AinFifo2,B},2,1,false))

local SER = darkroom.serialize( ITYPE, {{1,2},{1,2}}, d.interleveSchedule( 2, 2 ) ) 
local out = darkroom.apply("ser", SER, out )

--out = d.apply("ignoreBin", d.makeHandshake(d.makeStateful(ignoreBin)), out )
out = d.apply("flatten", d.flattenStreams(ITYPE,{{1,2},{1,2}}), out )

hsfn = d.lambda( "interleve_wide", A, d.statements{out, d.applyMethod("s1",fifos[1],"store",d.selectStream("A0",Abroadcast,0)), d.applyMethod("s2",fifos[2],"store",d.selectStream("A1",Abroadcast,1)) }, fifos )
--hsfn = d.lambda( "interleve_wide", A, d.statements{out, d.applyMethod("s1",fifos[1],"store",A) }, fifos )
--hsfn = d.lambda( "interleve_wide", A, d.statements{out, d.applyMethod("s1",fifos[1],"store",B) }, fifos )

------------
--ITYPE = d.StatefulHandshake(ITYPE)
--inp = d.input( ITYPE )
--out = d.apply( "hs", d.makeHandshake(d.makeStateful(fn)), inp)
--hsfn = d.lambda( "pointwise_wide_hs", inp, out )
--hsfn = d.makeHandshake(d.makeStateful(fn))

harness.axi( "interleve_wide_handshake", hsfn, ITYPE, nil, nil, W,H, ITYPE,W*2,H)