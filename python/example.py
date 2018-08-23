import magma as m
m.set_mantle_target("ice40")
import mantle as mantle

import lupa
from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)

lua.execute("package.path='./?.lua;/home/jhegarty/rigel/?.lua;/home/jhegarty/rigel/src/?.lua;/home/jhegarty/rigel/modules/?.lua;/home/jhegarty/rigel/misc/?.lua;/home/jhegarty/rigel/misc/compare/?.lua;/home/jhegarty/rigel/examples/?.lua'")

##############################################
# generate a rigel module like in regular lua...
R = lua.require("rigel")
G = lua.require("generators")
RM = lua.require("modules")
types = lua.require("types")
C = lua.require("examplescommon")

inp = R.input( types.uint(8) )
a = R.apply("a", C.plus100(types.uint(8)), inp)
b = R.apply("b", C.plus100(types.uint(8)), a)
p200 = RM["lambda"]( "p200", inp, b )

#######################################
def rigelTypeToMagmaType(ty):
    assert(types.isType(ty))
    if ty.isUint(ty):
        return m.UInt(ty.verilogBits(ty))
    else:
        assert(false)
    
def rigelToMagma(mod):
    IOL = ["CLK",m.ClockIn,"CE",m.In(m.Bit)]
    itype = R.lower(mod.inputType)
    otype = R.lower(mod.outputType)

    IOL.append("process_input")
    IOL.append(m.In(rigelTypeToMagmaType(itype)))
    IOL.append("process_output")
    IOL.append(m.Out(rigelTypeToMagmaType(otype)))
    
    class NewMod(m.Circuit):
        name = mod.name
        IO = IOL
        
    NewMod.verilogFile = mod.toVerilog(mod)

    return NewMod

#############################################
# convert rigel module to magma & wire it to some magma stuff

RigelMod = rigelToMagma(p200)
print(RigelMod)

class Add210(m.Circuit):
    IO = ["I",m.In(m.UInt(8)),"O",m.Out(m.UInt(8))]+m.ClockInterface()
    @classmethod
    def definition(io):
        rm = RigelMod()
        m.wire(io.I,rm.process_input)
        out = rm.process_output+m.uint(10,8)
        m.wire(io.O,out)
        m.wire(rm.CE,m.bit(True))

m.compile("example",Add210)
