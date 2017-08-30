import os
os.environ['MANTLE_TARGET'] = 'ice40'

from magma import *
from mantle import Mux, Mux2, Register

TXMOD = DefineFromVerilogFile("txmod.v")[0]
RXMOD = DefineFromVerilogFile("rxmod.v")[0]

class Process(Circuit):
    name = "Process"
    IO = ["I",In(Bits(8)), "O",Out(Bits(8))]

    @classmethod
    def definition(io):
        wire(io.O,bits(uint(io.I)+uint(10,8)))

class Main(Circuit):
    name = "main"
    IO = ["CLK",In(Bit), "RX", In(Bit), "TX",Out(Bit),
          "LED0",Out(Bit),
          "LED1",Out(Bit),
          "LED2",Out(Bit),
          "LED3",Out(Bit),
          "LED4",Out(Bit),
          "PMOD_1",Out(Bit),
          "PMOD_2",Out(Bit)]

    @classmethod
    def definition(io):
        rxmod = RXMOD()
        txmod = TXMOD()
        
        databuf = Register(8, has_ce=True)
        wire(databuf.CLK,io.CLK)
        wire(databuf.CE,txmod.ready | rxmod.valid)
        wire(databuf.I, rxmod.data)

        databufValid = Register(1, has_ce=True)
        wire(databufValid.CLK,io.CLK)
        wire(databufValid.CE,txmod.ready | rxmod.valid)
        wire(databufValid.I,bits(rxmod.valid))

        wire(rxmod.RX,io.RX)
        wire(rxmod.CLK,io.CLK)

        wire(txmod.TX,io.TX)
        wire(txmod.CLK,io.CLK)
        #wire(txmod.data,databuf.O)
        wire(bits(txmod.valid),databufValid.O)

        process = Process()
        wire(databuf.O,process.I)
        wire(process.O,txmod.data)

from magma.backend.verilog import compile as compile_verilog
print(compile_verilog(Main))

compile("magtest",Main,include_coreir=True)
