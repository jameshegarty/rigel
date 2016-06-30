Getting Started with Rigel
==========================

_James Hegarty <jhegarty@stanford.edu>_

Rigel is a language for describing image processing hardware embedded in Lua. Rigel can compile to Verilog hardware designs for Xilinx FPGAs, and also can compile to fast x86 test code using Terra.

Install & Run
-------------

Installing Rigel is not required. However your system needs to have Terra installed, and paths set correctly so that Terra can find all the Rigel sources. You can download the Terra binary files on https://github.com/zdevito/terra/releases (tested with release-2016-03-25) or build it. You can clone the repository and build Terra using the instructions in the [Terra Readme](https://github.com/zdevito/terra). Run the REPL and make sure it installed correctly.

Next, add the Rigel language definition to your lua path environment variable, and the Terra binary location to your PATH. This can be accomplished by adding the following to .profile or .bashrc:

    export RIGEL=[path to rigel git directory root]
    export TERRADIR=[path to terra root]
    export TERRA_PATH="$TERRA_PATH;./?.t;$RIGEL/?.t;$RIGEL/src/?.t;$RIGEL/extras/?.t;$TERRADIR/tests/lib/?.t;$RIGEL/examples/?.t"
    export PATH=${TERRADIR}/bin:${PATH}

Rigel and Terra are tested to work on Linux and Mac OS X. Other platforms are unlikely to work.

Now that you have added the correct paths, you should be able to run the example pipelines using Rigel's x86 simulator:

    cd [rigel root]/examples
    make terra

This runs 100s of test pipelines, so it may be slow. The output of each test is located at `examples/out/[testname].bmp`. If make completes without errors, this means that all tests were successful.

FPGA Setup
----------

`make terra` will write out verilog files for each test (located at `examples/out/[testname].axi.v`). You can compile and run these verilog files on your board using your own flow. However, we also provide a simplified Xilinx FPGA flow that we recommend (implemented in `examples/makefile`). Our flow supports both generating a Xilinx bitstream (.bit) and also loading and running the pipeline on the board automatically (over ethernet).

Rigel's FPGA flow was tested with [Xilinx ISE 14.5](http://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/design-tools/v2012_4---14_5.html). This is the only version of ISE that works with the Zynq 7100. Later versions of ISE should work fine as well, if you are building for the Zynq 7020. If ISE is installed, our makefile should be able to build bitstreams for the Zynq 7020 and 7100.

Rigel's FPGA flow optionally also supports loading the generated bitstream onto an FPGA board and running an image through the pipeline for testing. The board must be accessible via SSH over ethernet. We tested with [Xilinx Linux](http://www.wiki.xilinx.com/Zynq+Releases). This is the version of linux that comes by default on the Zedboards, etc. Our flow may be compatible with other Linux releases. We require that `/dev/xdevcfg` exists, which allows us to reprogram the FPGA fabric from within linux by cat'ing the bitstream to this device.

By default, the makefile is set up for two board configurations:

    Zynq 7020 (zedboard, Trenz Electric TE0720)
    address: 192.168.2.2
    username: root
    password: root
    fpga local write path: /var/volatile

    Zynq 7100 (Avnet)
    address: 192.168.1.10
    username: root
    password: root
    fpga local write path: /tmp

Addresses, etc can be modified in `examples/makefile`.

Our makefile supports the following options:

* **make terra:** Run compiler and x86 simulator on all tests. Sim outputs at `examples/out/[testname].bmp` and verilog outputs at `examples/out/[testname].axi.v`
* **make sim:** Run Verilog simulator on all tests. Outputs at `examples/out/[testname].sim.bmp`
* **make axibits:** Builds all 7020 bitstreams. Outputs at `examples/out/[testname].axi.bi`t
* **make axi:** Run all 7020 bitstream on board. Outputs at `examples/out/[testname].axi.bmp`
* **make axibits100:** Builds all 7100 bitstreams. Outputs at `examples/out/[testname].axi100.bit`
* **make axi100:** Run all 7100 bitstream on board. Outputs at `examples/out/[testname].axi100.bmp`
* **make:** build and run all simulations and bitstreams on both boards
* **make clean:** delete all built files from `examples/out/`

Overview
========

![Rigel System Overview](http://stanford.edu/~jhegarty/rigel_readme_system.png)

* [Base Types](#base-types-typest)
* [Rigel](#rigel-rigelt)
  * [Rigel Operators](#rigel-operators)
  * [Rigel Interface Types](#rigel-interface-types)
* [Rigel Modules](#modules-srcmodulest)
  * [Core Modules](#core-modules) lift, lambda, stencil, linebuffer
  * [Array Manipulation](#array-manipulation) SoAtoAoS, pad, crop, border
  * [Multi-Rate Modules](#multi-rate-modules) downsample, upsample, filter
  * [Higher-Order Modules](#higher-order-modules) map, reduce
  * [Interfaces](#interfaces) liftBasic, liftDecimate, liftHandshake
  * [Streams](#streams) broadcastStream, fifo
  * [Misc](#misc) lut, fread, fwrite
* [Systolic](#systolic-systolict)
* [Misc Other Files](#misc)

Base Types (types.t)
====================

Rigel's type system supports arbitrary precision ints, uints, floats, bitfields, bools, 2d arrays, and tuples. types.t provides the types that are used throughout darkroom.

Type can be marked as constant, indicating that their value will not change while the pipeline is executing. This allows the compiler to perform additional optimizations. Rigel's constants are roughly equivilant to 'uniforms' in shader programming, or 'taps' in image processing.

    types = require "types"

    -- base type constructors
    types.bool( constant:bool )
    types.uint( precision:uint, constant:bool )
    types.int( precision:uint, constant:bool )
    types.bits( precision:uint, constant:bool ) -- bitfield
    types.float( precision:uint, constant:bool )

    types.array2d( arrayover:Type, width:uint, height:uint )
    types.tuple( typelist:Type[] )
    
types.t also provides a number of helper functions for manipulating and introspecting on types.

    types.isType(x) -- is table a Type?

    type:const() -- is type constant?
    ty = type:makeConst() -- returns constant version of type
    ty = type:stripConst() -- returns non-constant version of type
    
    type:isArray()
    type:arrayOver() -- if type is array, return type that array is over. Otherwise error out.
    type:baseType()  -- if type is array, return type that array is over. Otherwise return type.
    sz = type:arrayLength() -- return array dimensions as lua type {width,height}
    type:channels() -- returns width*height

    type:isTuple()
    type:tupleList() -- return lua table of Types in tuple
    
    type:isBool()
    type:isInt()
    type:isUint()
    type:isBits()
    type:isFloat()
    type:isNumber() -- float, int, or uint

    ty = type:toTerraType( asPointer:bool, [vectorWidth:uint] ) -- lower Rigel type to Terra type
    type:valueToTerra( value:lua ) -- convert lua value into terra value, coerced into format of this type

    -- this checks that a lua value can be coerced into a Rigel type. 
    -- Lua numbers can convert to float, uint, or int (as long as they don't overflow).
    -- Lua tables can convert into tuples or arrays, as long as sizes and types match.
    type:checkLuaValue(value:lua)
    type:fakeValue() -- returns a arbitrary lua value that will successfully convert to 'type'

    type:sizeof() -- bytes when type is used in Terra
    type:verilogBits() -- bits when type is used in Verilog

Rigel (rigel.t)
===============

Users construct image processing pipelines in Rigel by creating a Directed Acyclic Graph (DAG) of Rigel operations, which manipulate Rigel values. Most Rigel opreations involve applying a *Rigel Module* to a Rigel value. Rigel contains a large suite of built-in modules for performaning typical image processing operations.

Each Rigel module has an *interface type*, which specifies low-level information about the underlying hardware interface of the module. This is typically used to indicate whether the module support a synchronous interface, handshake interface, or bus interface. Modules can only be applied if interface types match. The current implementation does not perform automatic type conversions on interface types.

`rigel.t` contains core functionality for manipulating Rigel DAGs, and the core classes for Rigel interface types and modules. `modules.t` (shown later) contains all the built-in Rigel modules that can be applied.

RigelIR Values
---------------

The following functions are used for defining leaf values.

### rigel.input( type:Type, [sdfRate:SDFRate] ) : RigelIR ###

`rigel.input` is used to declare an input to a pipeline of a given type `types`, and optionally with a SDF rate `sdfRate`.

### rigel.constant( name:String, value:LuaValue, type:Type ) : RigelIR ###

`rigel.constant` is used to create a constant value (set at compile time and never changed).

RigelIR Operators
---------------

### rigel.apply( name:String, module:RigelModule, input:RigelIR ) : RigelIR ###

Apply the Rigel Module `module` to `input`. `name` is used to identify this application when the graph is lowered to Verilog.

### rigel.applyMethod( name:String, instance: RigelInstance, functionName:String, input:RigelIR ) : RigelIR ###

Apply the function named `functionName` on module instance `instance` to `input`. `name` is used to identify this application when the graph is lowered to Verilog.

Typically, this only comes up with FIFOs. FIFO modules have both a `load` and `store` 'function', which must be applied separately.

### rigel.tuple( name:String, inputList:RigelIR[], [packStreams:Bool] ) : RigelIR ###

Composed a tuple of the ordered list of values in lua array `inputList`. `name` is used to identify this concatenation when lowering to Verilog. When dealing with concatenating Handshake streams, `packStreams` indicates whether we should treat the output as one Handshake stream, instead of multiple streams (default true - one stream). TODO: remove `packStreams` (legacy option).

### rigel.array2d( name:String, inputList:RigelIR[width*height], width:Uint, height:Uint, [packStreams:Bool] ) : RigelIR ###

Composed an array of the ordered list of values in lua array `inputList`. `inputList` must be a 1d array in row major order - 2D dimensions are specified by `width` and `height`. `name` is used to identify this concatenation when lowering to Verilog. When dealing with concatenating Handshake streams, `packStreams` indicates whether we should treat the output as one Handshake stream, instead of multiple streams (default true - one stream). TODO: remove `packStreams` (legacy option).

### rigel.selectStream( name:String, input:RigelIR, i:Uint ) : RigelIR ###

Given an array or tuple of Handshake values, this returns the stream at index `i` (0 indexed).

TODO: turn this into a module.

### rigel.statements( values:RigelIR[] ) : RigelIR ###

Rigel graphs can only have one input and output, however `statements` allows you to multiple pipelines into one, reducing this restriction. Typically, this is only necessary in graphs with FIFOs. Only the first value is passed as the actual output of the graph (lua index 1).

Rigel Interface Types
---------------------

Each module's interface type  specifies low-level information about the underlying hardware implementation interface of the module. This is typically used to indicate whether the module support a synchronous interface, handshake interface, or bus interface. Modules can only be applied if interface types match. The current implementation does not perform automatic type conversions on interface types.

It is useful to think of these as abstract types that enforce rules of composition, not as literal descriptions of the signals of the resulting hardware. The Rigel compiler runs a small amount of code to correctly wire each interface type to its neighbors when it lowers to RTL. TODO: in the future it may be possible to make the low-level RTL layer powerful enough to type all of these interfaces and compose them directly.

By convention in this document we will use the constants *A*, *B*, etc to refer to an arbitrary type. In this section they will refer to base types (see [types.t](#base-types-typest)).

### A->rigel.V(B) ###

Synchronous Module that performs decimation. This corresponds to a statically-timed hardware module with a valid bit on the output only.

### rigel.V(A)->rigel.RV(B) ###

Synchronous Module that performs both decimation and expansion. This corresponds to a statically-timed hardware module with a valid bit on both inputs/output, and a ready bit.

Note that while it is possible to construct a statically-timed pipeline out of multiple modules with ready bits, this is not valid! And this case is not checked by the compiler! A statically-timed pipeline can only have one module with a ready bit, because upstream stalls are not supported by static pipelines. To compose multiple modules with ready bits, the modules must first be lifed to Handshake types (below).

### rigel.Handshake(A)->rigel.Handshake(B) ###

Handshake (full Ready-Valid on both input/output) interface. Supports composition of modules that perform both decimation and expansion.

## Aggregates ##

Rigel also has the ability to make aggregates (arrays and tuples) of Handshakes. Since every Rigel module only has a single input and output, this allows us to implement modules that work on multiple streams. These types _can not_ be nested (no Handshakes of Handshakes). Handshake(A) only works over base types.

### Handshake(A)[N] ###
    Array of Handshakes.

### {Handshake(A),Handshake(B),...} ###
    Similar to the array of Handshakes above, but allows for different types.

## Multiplexed Busses ##

Rigel also has provisional support for the ability to pack multiple streams onto one shared bus. Compared to the aggregates above (which have N streams on N data lines), this has N streams on 1 data line. This allows for supporting time-multiplexed hardware (hardware that operates on different streams in different cycles), or serializing multiple streams into one stream.

### rigel.HandshakeArray(A,N) ###

Unlike an array of *Handshakes* (above), a *HandshakeArray* can only have 1 of the *N* streams active per cycle. HandshakeArray's ready bit identifies the stream that should be written on the data bus in the current cycle.

### rigel.HandshakeTmuxed(A,N) ###
    *HandshakeTmuxed* behaves like a regular *Handshake* but allows multiple different data streams to flow over one interface. HandshakeTmuxed's valid bit identifies the ID of the stream that is active. 

Regular *Handshake* modules can be lifted to work over *HandshakedTmuxed*, but this should only be done if the module isn't stateful - there is no way to automatically duplicate the module state so that it stays coherent for each stream!


RigelModule
-----------

### module:toTerra() ###

Lower the Rigel module to a simulator module in Terra.

Each module is lowered to a Terra class with the following format:

    local Struct Module {}

    -- reset the module. Must call this before start of a frame
    -- must be provided, but doesn't necessarily have to do anything
    terra Module:reset() end

    -- fire the module (perform 1 cycle of operation)
    terra Module:process( inputValue : &module.inputType, output : &module.outputType )

    -- calculate ready bit in backwards pass (see below)
    -- only appears if module has ready bit
    terra Module:calculateReady( readyDownstream : bool )

    -- write out useful simulator statistics about this module
    -- function is passed the name of the instance - to identify itself in output
    -- stats must be provided, but doesn't necessarily have to do anything
    terra Module:stats( moduleInstanceName : &int8 ) end

Rigel types are lowered to Terra like this:

Base types (the types in `types.t`) are lowered to Terra directly - the type systems are compatible (ints become ints, arrays become arrays etc).

    -- the bools are the valid bit
    Handshake(A): tuple(A,bool)
    V(A): tuple(A,bool)
    RV(A): tuple(A,bool)

Notice that ready bit inputs do not appear in the lowered types. Ready bits are handled separately. Ready bit data flows the opposite direction of input data. Input data flows from the front of the pipeline, but ready bit data flows from downstream. For this reason we special-case ready bits and calculate them in a separate backwards pass. Each simulation cycle, you must call `calculateReady` on all ready-valid modules in backwards order first, before calling `process` on all the modules. Each module must store the result of the ready bit calculation internally, so that it can remember the value of the ready bit when `process` fires.

### module:toSystolic() ###

Lowers the Rigel module to a Systolic module.

The Rigel module is lowered to a module with the following format:

    SystolicModule Module:

    -- this dataflow resets stateful modules.
    -- Note that this reset on a high value, which is unconventional
    Dataflow Module:reset( doReset : bool ) : nil

    -- Perform the module calculation
    Dataflow Module:process( inputValue : module.inputType ) : module.outputType

    -- Perform the ready bit calculation
    Dataflow Module:ready( readyDownstream : bool ) : bool

### module:toVerilog() ###

Convenience function - simply calls `toSystolic()` and then calls `toVerilog()` on the resulting systolic module.

Modules (src/modules.t)
=========

*modules.t* contains Rigel's core set of modules. This is intended to be the smallest and simplest set of core functionality that an architecture needs to support to implement Rigel's programming model. Some additional useful modules built out of these core modules are implemented in Rigel's standard library, *examplescommon.t*. A few of these modules from *examplescommon.t* are described here for completeness, and are marked with a (*).

All valid Rigel modules contain at least these fields:

    { kind:String, -- unique name for module
      inputType:Type,
      outputType:Type,
      sdfInput:SDFRate,
      sdfOutput:SDFRate,
      delay:Number, -- pipeline delay (synchronous modules only)
      stateful:Bool, -- Is module referentially transparent?
      terraModule:Terra,
      systolicModule:SystolicModule
    }

Each module may include additional fields to describe the particular configuation of that module. Those additions are documented below.

Core Modules
------------

### lambda ###
    type: input.type -> output.type
    modules.lambda( newModuleName : String, input : RigelIR, output : RigelIR, [instances : RigelInstance[]] )
    fields: {..., kind="lambda", name=newModuleName, input=input, output=output, instances=instances }

Define a new Rigel module based on a user-constructed pipeline. `input` must be a RigelIR node returned from `rigel.input`. `output` is a RigelIR of the intented output. `instances` is a list of any module instances returned from `rigel.instantiateRegistered` that you want to include (typically only used for FIFOs).

### lift ###
    modules.lift( newModuleName:String, inputType:Type, outputType:Type, delay:Number, terraFunction:terraFunction, systolicInput:SystolicValue, systolicOutput:SystolicValue)
    fields: {..., kind="lift_"..newModuleName}

*lift* takes a function from the lower-level languages (Terra and Systolic) and lifts them into a Rigel module. `delay` must correspond to the pipeline delay from *systolicInput* to *systolicOutput*.

### seqMap ###
    type: null->null
    modules.seqMap( module:RigelModule, width:uint, height:Uint, T:Uint )
    fields: {..., kind="seqMap", W=width, H=height, T=T }

`seqMap` executes a module multiple times sequentially over image data stored in memory. This is used to generate the top level module that actually executes the pipeline in the simulator or in hardware from DRAM. 

`seqMap` always reads/write data of the width expected by `module`. This module will then read `(W*H)/T` items of that size before halting. TODO: change this to match the `inputCount` interface of `seqMapHandshake`.

`seqMap` expects the module that it is mapping to have a basic input and output type - Handshake interfaces should use `seqMapHandshake` below.

### seqMapHandshake ###
    type: null->null
    modules.seqMapHandshake( module:RigelModule, [tapInputType:Type], [tapValue=tapValue], inputCount:Uint, outputCount:Uint, axi:Bool, [readyRate:Uint] )
    fields: {..., kind="seqMapHandshake", inputCount=inputCount, outputCount=outputCount }

`seqMapHandshake` executes a module multiple times sequentially over image data stored in memory. This is used to generate the top level module that actually executes the pipeline. 

`tapInputType` is an optional 'tap' value to send into the pipeline. Taps are runtime-configurable constants that can only be modified between frames. The Verilog we generate is designed to make sure the tap values are _not_ common subexpression eliminated by the compiler. `tapValue` gives an initial value for the tap input. Taps are passed into the pipeline in the high bits. If taps are included, the pipeline must include this as part of its type, and the tap input should be marked as a constant type.

if `axi` is true, generate hardware for reading from DRAM on the Zynq platform. If `axi` is false, generate a test harness for the Verilog simulator.

This module will read `inputCount` items of size `module.inputType` and write `outputCount` items of size `module.outputType`.

### stencil* ###
    type: A[width,height] -> A[xmax-xmin+1,ymax-ymin+1][width,height]
    examplescommon.stencil( A:Type, width:Uint, height:Uint, xmin:Int, xmax:Int, ymin:Int, ymax:Int )
    fields: {..., kind="stencil", type=A, w=width, h=height, xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax }

*stencil* takes an array of size *width*x*height* and turns it into an array of stencils. Similar to *linebuffer*, for pixels outside the array the value is undefined (this occurs on borders of the array). Borders with defined values can be implemented using a pad and crop, or with the *unpackStencil* module, which does not read outside the array.

### linebuffer ###
    type: A[T]->A[T,-ymin+1]
    modules.linebuffer( A:Type, width:Uint, height:Uint, T:Uint, ymin:Int <= 0 )
    fields: {..., kind="linebuffer", type=A, w=width, h=height, T=T, ymin=ymin }

*linebuffer* takes a stream of pixels of type *A* running at throughput *T* and converts it into a stream of columns of past lines, with size set by *ymin*. This stream of columns can then be converted into a stream of stencils using the *SSR* module.

As explained in Darkroom 2014, when processing the array in scanline order (low indices to high indices), the linebuffer can only provide pixels at indices *ymin<=0*, because these are the only values that have been seen. 

### SSR ###
    type: A[T,-ymin+1]->A[T-xmin,-ymin+1]
    modules.SSR( A:Type, T:Uint, xmin:Int <= 0, ymin:Int <= 0 )
    fields: {..., kind="SSR", type=A, T=T, xmin=xmin, ymin=ymin }

*SSR* implements a stencil shift register. The stencil shift register converts a stream of columns of lines into a stream of stencils. If *T*>1, this returns multiple stencils per firing coalesced into one large stencil, because the sub-stencil share values. This can be broken into multiple stencils using *unpackStencil*.

### stencilLinebuffer* ###
    type: A[T]->A[T-xmin,-ymin+1]
    examplescommon.stencilLinebuffer( A:Type, width:Uint, height:Uint, T:Uint, xmin:Int <= 0, xmax:Int = 0, ymin:Int <= 0, ymax: Int = 0)

*stencilLinebuffer* is a fusion of a *linebuffer* and a *SSR* for convenience.

Currently xmax/ymax must always be 0, which means that the stencil always reads values from the past that are available (as explained in Darkroom 2014). TODO: for extra programmer convenience, implement the scheduling algorithm from Darkroom 2014 to allow the user to write pipelines that read values with xmax/ymax>0.

### SSRPartial ###
    type: if fullOutput==false (the defualt) then A[1,-ymin+1]->A[(-xmin+1)*T,-ymin+1], else A[1,-ymin+1]->A[-xmin+1,-ymin+1]
    modules.SSRPartial( A:Type, T:Number <= 1, xmin:Int <= 0, ymin:Int <= 0, [stride:Uint], [fullOutput:Bool] )
    fields: {..., kind="SSRPartial", type=A, T=T, xmin=xmin, ymin=ymin, stride=stride, fullOutput=fullOutput }

*SSRPartial* is a special-case fusion of *SSR* and *changeRate*, which reduces the hardware cost by 50% by merging the shift registers for both modules into a single shift register with more complicated control logic.

### stencilLinebufferPartial* ###
    type: Handshake(A[T])->Handshake(A[1(-xmin+1)*T,-ymin+1])
    examplescommon.stencilLinebufferPartial( A:Type, width:Uint, height:Uint, T:Number <= 1, xmin:Int <= 0, xmax:Int = 0, ymin:Int <= 0, ymax: Int = 0 )

Convenience module that combines a linebuffer and SSRPartial.

### stencilLinebufferPartialOffsetOverlap* ###
    type: Handshake(A[T]) -> Handshake()
    examplescommon.stencilLinebufferPartialOffsetOverlap( A: Type, width:Uint, height:Uint, T:Number<=1, xmin:Int<=0, xmax: Int=0, ymin:Int<=0, ymax:Int=0, offset : Number, overlap : number )

Array Manipulation
------------------

### unpackStencil* ###
    type: A[stencilWidth+width-1, stencilHeight+height-1] -> A[stencilWidth, stencilHeight][width,height]
    examplescommon.unpackStencil( A:Type, stencilWidth:Uint, stencilHeight:Uint, width:Uint, [height:Uint] )

*unpackStencil* takes an array of type *A* and converts it into an array of stencils. Each stencil is composed of values with insides X=[-stencilWidth+1,0] and Y={-stencilHeight+1,0]. Unlike *stencil*, this module never reads outside of the array, so all stencils are made entirely of valid values.

TODO: make the arguments this takes more compatible with *stencil*.

### SoAtoAoS* ###
    type: {Array2d(a,W,H),Array2d(b,W,H),...} -> Array2d({a,b,c},W,H)
    examplescommon.SoAtoAos( width:uint, height:uint, typelist:Type[], [asArray:bool] )

*SoAtoAos* converts a tuple of arrays of the same size into an array of tuples (i.e. struct of arrays to arrays of structs transform).

### posSeq ###
    type: null -> {uint16,uint16}[T]
    modules.posSeq( width:Uint, height:Uint, T:Uint )
    fields = {..., kind="posSeq", W=width, H=height, T=T }

*posSeq* is a state machine that provides a {x,y} image coordinate tuple at throughput *T*. 

### border* ###
    type: A[width,height] -> A[width,height]
    examplescommon.border( A:Type, width:Uint, height:Uint, left:Uint, right:Uint, bottom:Uint, top:Uint, value:LuaValue )

Take in an array, and apply a border to the edges, keeping the array size the same. Used for implementing boundary conditions for stencil reads. Currently the only supported border condition is setting it to a constant value `value`. `left` pixels on the left of the image are replaced with the constant, along with `right` pixels on the right etc.

### borderSeq ###
    type: A[T]->A[T]
    examplescommon.borderSeq( A:Type, width:Uint, height:Uint, T:Uint, left:Uint, right:Uint, bottom:Uint, top:Uint, value:LuaValue )

Sequentialized version of `border` that operates on `T` pixels at a time, instead of the whole array at a time.

### cropSeq ###
    type: A[T]->V(A[T])
    modules.cropSeq( A:Type, width:Uint, height:Uint, T:Uint, left:Uint, right:Uint, bottom:Uint, top:Uint )
    fields: NYI

*cropSeq* takes an image of size *width* x *height* and removes *left* pixels from the left, *right* pixels from the right etc. This yields a smaller image of size (*width-left-right*x*height-top-bottom*). *cropSeq* is sequentialized to perform this operation on images of type *A* at throughput *T*.

### padSeq ###
    type: V(A[T])->RV(A[T])
    modules.padSeq( A:Type, width:Uint, height:Uint, T:Uint, left:Uint, right:Uint, bottom:Uint, top:Uint, value:A )
    fields: {..., kind="padSeq", type=A, T=T, width=width, height=height, L=left, R=right, B=bottom, Top=top, value=value }

*padSeq* takes an image of size *width* x *height* and adds *left* pixels to the left, *right* pixels to the right, etc., with value *value*. This yields a larger image of size (*width+left+right*x*height+top+bottom*). *padSeq* is sequentialized to perform this operation on images of type *A* at throughput *T*.

Multi-Rate Modules
------------------

### changeRate ###
    type: V(A[inputRate,H]) -> RV(A[outputRate,H])
    modules.changeRate( A:Type, H:Uint, inputRate:Uint, outputRate:Uint )
    fields: {..., kind="changeRate", type=A, H=H, inputRate=inputRate, outputRate=outputRate }

*changeRate* implements either the *vectorize* or *devectorize* operator. *vectorize* takes smaller vectors and concatenates them (inputRate<outputRate). *devectorize* takes larger vectors and writes them out over multiple firings (inputRate>outputRate).

Note that by default *changeRate* de/vectorizes 2D arrays column at a time. This can limit the amount of rate change if the array has many more rows than columns. However, the array can always be casted to a 1D array prior to *changeRate*, which will expose the maximum rate factors.

### filterSeq ###
    type: {A,Bool} -> V(A)
    modules.filterSeq( A:Type, width:Number, height:Number, rate:Number, fifoSize:Number )
    fields: { ..., kind="filterSeq", A=A }

*filterSeq* takes two inputs: a stream of data of type A, and a stream of bools which indicate whether the data should pass through (true) or be filtered out (false). *filterSeq's* SDF rate is set as *1/rate*. *filterSeq* may override the stream of bools on some cycles in order to keep the stream valid within the SDF model, assuming the *filterSeq* is followed by a fifo with *fifoSize* entries. In particular, *filterSeq* will override the filter if the fifo will under/overflow or if the total number of output tokens does not equal width*height/rate by the end.

### downsampleXSeq ###
    type: A[T]->V(A[T/scale]). If scale>T, this is A[T]->V(A[1]).
    modules.downsampleYSeq( A: Type, width:Uint, height:Uint, T:Uint, scale:Uint )
    fields: NYI

*downsampleXSeq* performs a downsample in X (i.e. keeps only *1/scale* columns, starting with column X=0). *downsampleXSeq* is sequentialized to work on scanline streams of vectors of type *A* with size *T*. *width* and *height* indicate the total size of the image to be downsampled.

### downsampleYSeq ###
    type: A[T]->V(A[T])
    modules.downsampleYSeq( A: Type, width:Uint, height:Uint, T:Uint, scale:Uint )
    fields: NYI

*downsampleYSeq* performs a downsample in Y (i.e. keeps only *1/scale* lines, starting with line Y=0). *downsampleYSeq* is sequentialized to work on scanline streams of vectors of type *A* with size *T*. *width* and *height* indicate the total size of the image to be downsampled.

### downsampleSeq* ###
    type: V(A[T])->RV(A[T])
    examplescommon.downsampleSeq( A: Type, width:Uint, height:Uint, T:Uint, scaleX:Uint, scaleY:Uint )

*downsampleSeq* is a convenience function to instantiate downsampleXSeq and/or downsampleYSeq modules to perform a combined scale in X and Y. *scaleX* and *scaleY* must be >= 1.

### upsampleXSeq ###
    type: Handshake(A[T])->Handshake(A[T])
    modules.upsampleXSeq( A:Type, T:Uint, scale:Uint )
    fields: { ..., kind="upsampleXSeq", A=A, T=T, scale=scale }

*upsampleXSeq* performs an upsample in X (i.e. duplicates each column *scale* times, starting with column X=0). *upsampleXSeq* is sequentialized to work on scanline streams of vectors of type *A* with size *T*. *width* and *height* indicate the total size of the image to be upsampled.

### upsampleYSeq ###
    type: V(A[T])->RV(A[T])
    modules.upsampleYSeq( A:Type, width:Uint, height:Uint, scale:Uint )
    fields: {..., kind="upsampleYSeq", A=A, T=T, width=width, height=height, scale=scale }

*upsampleYSeq* performs an upsample in Y (i.e. duplicates each line *scale* times, starting with line Y=0). *upsampleYSeq* is sequentialized to work on scanline streams of vectors of type *A* with size *T*. *width* and *height* indicate the total size of the image to be upsampled.

### upsampleSeq* ###
    type: Handshake(A[T]) -> Handshake(A[T])
    examplescommon.upsampleSeq( A:Type, width:Uint, height:Uint, T:Uint, scaleX:Uint, scaleY:Uint )

*upsampleSeq* is a convenience function to instantiate upsampleXSeq and/or upsampleYSeq modules to perform a combined upscale in X and Y.

Higher-Order Modules
--------------------

### map ###
    given f:A->B has type A[w,h]->B[w,h]
    modules.map( f:Modules, width:Number, height:Number )
    fields: {..., kind="map", fn=f, W=width, H=height }

*map* lifts a scalar function to work on arrays.

### reduce ###

### reduceSeq ###

Interfaces
----------

### liftBasic ###
    given f:A->B, has type A->V(B)
    modules.liftBasic( f:Module )
    fields: {..., kind="liftBasic", fn=f}

*liftBasic* takes a basic module, and lifts it to have a valid bit (i.e. supports decimation).

### liftDecimate ###
    given f:A->V(B), has type V(A)->RV(B)
    modules.liftDecimate( f:Module )
    fields: {..., kind="liftDecimate", fn=f}

*liftDecimate* lifts modules that support decimation only (i.e. A->V(B)) to the synchronous interface type that supports both data decimation and increase (V(A)->RV(B)).

### liftHandshake ###
    given f:V(A)->RV(B), has type Handshake(A)->Handshake(B)
    modules.liftHandshake( f:Module )
    fields: {..., kind="liftHandshake", fn=f}

*liftHandshake* converts the most general synchronous interface type *V(A)->RV(B)* to a handshake interface. Modules with handshake interfaces support upstream stalls, whereas synchronous interfaces do not.

### makeHandshake ###
    given f:A->B, has type Handshake(A)->Handshake(B)
    modules.makeHandshake( f:Module )
    fields: {..., kind="makeHandshake"}

Convenience module that directly converts a module with a basic interface to a Handshake interface.

### RPassthrough ###
    given f:V(A)->RV(B) has type RV(A)->RV(B)
    modules.RPassthrough( f:Module )
    fields: {..., kind="RPassthrough", fn=f}

*RPassthrough* allows for composition of *V(A)->RV(B)* interfaces. Note that synchronous pipelines do not support upstream stalls! This should only be used in pipelines where that can not occur.

### waitOnInput ###
    given f:A->RV(B) has type V(A)->RV(B)
    modules.waitOnInput( f:Module )

*waitOnInput* is typically for internal compiler use only. Modules with *A->RV(B)* type have ambiguous behavior, because they do not define how the module will behave with invalid input. This higher-order modules provides one possible semantic:

if f is ready, f with execute iff input valid is true (i.e. it waits on input). if f is not ready, inner will always run (input data is undefined).

This is useful for implementing modules that upsample data. If they are ready to read the input, the module will only ever see valid data. If they are not ready (i.e. are generating data themselves), input data is irrelevant.

Streams
-------

### packTuple ###
    type: {Handshake(a), Handshake(b),...} -> Handshake({a,b,...})
    modules.packTuple( typelist:Type[] )
    fields: {..., kind="packTuple"}

*packTuple* takes multiple Handshake streams and synchronizes them into a single stream (i.e. to implement fan-in).

### broadcastStream ###
    type: Handshake(A) -> Handshake(A)[N]
    modules.broadcastStream( A:Type, N:Uint )
    fields: {..., kind="broadcastStream", A=A, N=N }

`broadcastStream` takes a single Handshake stream, and splits it into multiple streams to implement fan-out. This is essentially the opposite of `packTuple`. The reason this module is necessary is that when there are multiple downstream streams, the upstream ready bit must be an AND of all the downstream ready bits. It must stall if ANY of the downstream streams are stalled. This module implements the AND.

Note: Currently the compiler does not check that you have correctly inserted this module! Handshake streams can be wired multiple times, which will compile, but won't behave correctly. TODO: Add a compiler pass to check for this (or rearchitect it so that fan-out is not allowed without an explicit module).

### fifo ###
    store type: Handshake(A) -> nil
    load type: nil -> Handshake(A)
    modules.fifo( A : Type, size : Uint>0, [nostall : bool], [W : Uint], [H : Uint], [T : Uint] )

The fifo module implements a first-in first-out queue. FIFOs are used to hide latency variation in modules, match pipeline delays, or support back edges (cycles). FIFOs are different than other modules because they have two separate 'ports' on it, a load and a store, which are decoupled. This allows us to support cycles in our language that only has DAGs.

Because FIFOs have multiple ports, they must be instantiated differently than other modules:

    fifoinst = rigel.instantiateRegistered( "myfifo", modules.fifo( ... ) )
    fifoloadval = rigel.applyMethod( "myload", fifoinst, "load" ) -- apply 'load' method on fifo

    -- fifoinst must also be passed to rigel.lambda in the instances list

`size` is the size of the FIFO (# of entries). Native FIFO hardware on the Zynq platform supports either 128, 512, 1024, or 2048 entries, so it is probably a good idea to choose one of those sizes. 128 entries will be implemented in slices, >128 is implemented with BRAMs. 

`nostall` disables the upstream stall signal as a performance optimization. If you FPGA clock period is limited by the length of the stall lines (which is pretty common), this will remove the stall lines, which can significantly improve the clock. This is only valid if you know that the FIFO is sufficiently sized to never need to stall.

`W`, `H`, `T` are used to calculate the number of input items the FIFO expects to see total. Then the Verilog simulator uses this to print out usage statistics at the end of the frame (specifically, max fifo size seen). This debug information is optional. TODO: could probably simplify this.

### serialize ###
    type: HandshakeArray(A,N)->HandshakeTmuxed(A,N)
    modules.serialize( A:Type, inputRates:SDFRate[N], schedule:Module )
    fields: {..., kind="serialize", A=A, inputRates=inputRates, schedule=schedule }

*serialize* is a higher-order module that takes multiple Handshake streams and serializes them into a single stream based on a user-specified ordering module.

Ordering modules have type *null -> uint8*. Each firining they return the ID of the stream to run. Ordering modules are stateful (or they wouldn't be useful).

**modules.interleveSchedule( N:Uint, period:Uint)**
    fields: {..., kind="interleveSchedule", N=N, period=period }

*interleveSchedule* imply interleves *N* stream with a fixed repeating pattern. This schedule returns *2^period* items of stream 0, then stream 1, etc. Like this:

    period=1: ABABABAB
    period=2: AABBAABB
    period=3: AAAABBBB

**modules.pyramidSchedule( depth:Uint, wtop:Uint, T:Uint )**
    fields: {..., kind="pyramidSchedule", depth=depth, wtop=wtop, T=T }

*pyramidSchedule* takes *depth* streams with pyramid rates (i.e. 1, 1/4, 1/16, 1/64) and serializes them into a "human readable" image pyramid. *wtop* is the width of the largest (finest) pyramid level. *T* is the number of pixels being processed in parallel (i.e. the module will expect *wtop/T* tokens per line for the first pyramid level).

This module is a compromise between human readability and FIFO size. Likely, there is a schedule that further reduces FIFO size but results in an image that is less understandable. Likewise, it would be nice to make this more human readable, but this would likely use too much FIFO size.

    with depth=3, wtop=4, T=1 the pattern is:
    AAAAAAAAAAAABBBBC
    i.e. 4 lines of A, 2 lines of B, 1 line of C

TODO: in the future, we would like to extend *serialize* to support ordering modules that make a dynamic decision on which stream to run. These modules would have type *{bool,bool,...}->uint8* (bools indicating valid data on each stream) or *{uint8,uint8,...}->uint8* (numbers indicating fifo sizes on each stream). This would allow for dynamically-scheduled time-multiplexed hardware modules.

### toHandshakeArray ###
    type: Handshake(A)[N] -> HandshakeArray(A,N)
    modules.toHandshakeArray( A:Type, inputRates:SDFRate[N] )
    fields: {..., kind="toHandshakeArray", A=A, inputRates=inputRates }

`toHandshakeArray` converts N streams onto a shared bus (N streams transported over 1 data line). Only one stream can be active each cycle, and this is chosen by the downstream ready id. `inputRates` is a list of SDF rates for each input stream. 

### demux ###
    type: HandshakeTmuxed(A,N)->Handshake(A)[N]
    modules.demux( A:Type, rates:SDFRate[N] )
    fields: {..., kind="demux", A=A, rates=rates }

A `HandshakeTmuxed` interface has multiple streams transported over one shared bus. `demux` takes the N streams and demultiplexes them into N individual busses. `rates` gives the expected SDF rates of the N busses. The rates must sum to one (the bus must be fully utilized but no more).

### flattenStreams ###
    type: HandshakeTmuxed(A,N) -> Handshake(A)
    modules.flattenStreams( A : Type, rates : SDFRate[N] )
    fields: {..., kind="flattenStreams", A=A, rates=rates }

A `HandshakeTmuxed` interface has multiple streams transported over one shared bus. `flattenStreams` flattens these N streams into one single stream, mixing values on the different streams together. Ordering of values is not guaranteed - they simply occur in the order that things happen on the Tmuxed bus. `rates` gives the expected SDF rate of the stream, which must sum to 1.

Misc
----

### reduceThroughput ###
    type: V(A) -> RV(A)
    modules.reduceThroughput( A:Type, factor:Number)
    {..., kind="reduceThroughput", factor=factor}

*reduceThroughput* is a debugging module. It artificially reduces the SDF throughput of the output stream by 1/factor.

### lut ###
    type: inputType -> outputType
    modules.lut( inputType : Type, outputType : Type, values : LuaValue[] )
    fields: {..., kind="lut", inputType=inputType, outputType=outputType, values = values }

`lut` creates a lookup table. `values` must be an array of size 2^(inputType:bits()), and each of its values must be convertible to `outputType`. When lowered to hardware, these lookup tables typically end up being instantiated at BRAMs, so trying to fit the input/output data type to match the size of the BRAMs is typically a good idea.

### constSeq ###
    type: nil -> A[W*T,H]
    modules.constSeq( value : LuaValue, A : Type, W : Uint, H : Uint, T : Number )
    T*W must be an integer <=W and >0.
    fields: {..., kind="constSeq", A=A, w=W, h=H, T=T, value=value}
    
`constSeq` is a combination of a constant and a shift register. `constSeq` returns sub-arrays of a 2d array constant (with value `value`). The sub-arrays returned are column subsets of width `W*T` and height `H` from low indicies to high. This matches the behavior of stencilLinebufferPartial - so it can be used to feed stencil computations with filter coefficients.

### overflow ###
    type: A -> V(A)
    modules.overflow( A : Type, count : Uint )
    fields: {..., kind="overflow", count = count }
    
`overflow` is used to set up the DRAM test harness. If the AXI bus recieves more data items than it was expecting, it crashes the board. `overflow` caps the number of data items at `count` to make sure this doesn't happen, even if the user's code has a bug.

### underflow ###
    type: Handshake(A) -> Handshake(A)
    modules.underflow( A : Type, count : Uint, cycles : Uint, upstream : Bool, [tooSoonCycles : Bool] )
    fields: {..., kind="underflow", A=A, count = count }
    
`underflow` is used to set up the DRAM test harness. If the AXI bus recieves fewer data items than it was expecting, it crashes the board. Underflow can occur for two reasons:

*Underflow on the output:* The pipeline didn't write enough values (not enough valid bits were true). For this case, set `upstream=false`, and it will monitor the writes. It will expect to see at least `count` items in `cycles` cycles. If this doesn't occur, it will write DEADBEEFs to the bus until `count` items have occured. `tooSoonCycles` will optionally also raise an assert in the Verilog simulator if the pipeline exits too soon (which is probably also an error of some sort).

*Underflow on the input:* The pipeline didn't read enough values (not enough ready bits were true). For this case, set `upstream=true`, and it will monitor the reads.

### cycleCounter ###
    type: Handshake(A) -> Handshake(A)
    modules.cycleCounter( A : Type, count : Uint )
    fields: {..., kind="cycleCounter", A=A, count=count }

Debug module. `cycleCounter` counts the number of cycles until `count` items have been written on the bus, and then writes out this number of cycles in one full AXI burst (128 bytes).  Cycle count is written out as 32 bit unsigned ints (repeated 32 times). This modules is used to measure the number of execution cycles used by the pipeline.

### freadSeq ###
    type: nil -> type
    modules.freadSeq( filename : String, type : Type )
    fields: {..., kind="freadSeq", filename=filename, type = type }

Debug module. Reads a file on disk in the Verilog and Terra simulator. Acts as a data source. This is a NOOP in hardware. The module will continue to read data until the file runs out of data.

### fwriteSeq ###
    type: type -> type
    modules.fwriteSeq( filename : String, type : Type )
    fields: {..., kind="fwriteSeq", filename=filename, type = type }

Debug module. Writes a file to disk in the Verilog and Terra simulator. Data is passed through this module unmodified, so this can be used to record data in the middle of the pipeline. This is a NOOP in hardware. The module will continue to write data whenever data is passed to it.

Systolic (systolic.t)
=====================

The `Systolic` library is used to construct pipelined datapaths and lower them to Verilog. In this system, users define `SystolicModule`'s, which correspond to modules in Verilog. SystolicModules can be instantiated (returning a `SystolicInstance`), and SystolicModules can contain instances of other modules. Instances indicate that a copy of the hardware necessary to implement that module should be created.

SystolicModules contain one or more `SystolicDataflow`'s, which represent operations to be performed by the module. Each SystolicDataflow can have one input and/or one output (which correspond to input/output ports on modules in Verilog). The output is typically driven by the input, but can also be driven by an internal module instance, such as a register. The user specifies the operations to be performed by the dataflow by creating a DAG of `SystolicIR` nodes. `SystolicIR` is a specification of the primitive operations that can be performed by the hardware.

The `SystolicIR` and SystolicDataflows are restricted so that they can always be pipelined to an arbitrary depth by the compiler. The pipelineing is performed automatically prior to lowering to Verilog. SystolicDataflows can each have an associated valid bit (to implement pipeline bubbles) and clock enable `CE` (to stall the pipeline). These two signals are wired automatically by the compiler.

SystolicIR Values
-----------

    systolic.parameter( name : String, type : Type )
Return a formal parameter of type `type` and name `name` (used when lowering to Verilog).

    systolic.constant( value : Lua, type : Type )
Return a value with value `value` and type `type`. `value` must be convertible to type.

    systolic.null()
Return a value of type null.

    SystolicIR:setName( name : String )
Set the intermediate variable name to `name` (when lowered to Verilog).

SystolicIR Operators
------------------

`systolic.cast( expr : SystolicAST, type : Type )` Cast `expr` to Type `type`.

`systolic.slice( expr : SystolicAST, idxLow : Uint, idxHigh : Uint, idyLow : Uint, idyHigh : Uint )`
if `expr` is of type Array2D, return a new array of smaller size. The new array will include X coordinates in range [idxLow,idxHigh] and Y in range [idyLow, idyHigh]. Coordinates are inclusive and must be in rate of `expr` array size.

`systolic.index( expr : SystolicAST, idx : Uint, idy : Uint )`
if `expr` is of type Array2D, select one element of the array (at coordinate `[idx,idy]`) and return its value (as a scalar).

`systolic.bitSlice( expr : SystolicAST, low : Uint, high : Uint )`
Perform a bitwise slice on `expr`. `expr` can be any type. This performs the same operation as writing `expr[high:low]` in Verilog. Returns bit type.

`systolic.tuple( list : SystolicAst[] )`
Takes a list `list` of SystolicAST values and returns them packed together as a tuple type.
Note: this is used in combination with `cast` to perform many type conversions. e.g. concatenating multiple values into an Array2D is accomplished by turning them into a tuple, and then casting to Array2D.

`systolic.select( cond : SystolicAST, a : SystolicAST, b : SystolicAST )`
Perform the ternary select operation like in C, `cond?a:b`.

### Binary operators: ###

* `+ (operator)` lhs+rhs
* `- (operator)` lhs-rhs
* `* (operator)` lhs*rhs
* `systolic.eq( lhs : SystolicAST, rhs : SystolicAST )` lhs == rhs
* `systolic.le( lhs : SystolicAST, rhs : SystolicAST )` lhs <= rhs
* `systolic.lt( lhs : SystolicAST, rhs : SystolicAST )` lhs < rhs
* `systolic.ge( lhs : SystolicAST, rhs : SystolicAST )` lhs >= rhs
* `systolic.gt( lhs : SystolicAST, rhs : SystolicAST )` lhs > rhs
* `systolic.__or( lhs : SystolicAST, rhs : SystolicAST )` lhs or rhs (boolean)
* `systolic.__and( lhs : SystolicAST, rhs : SystolicAST )` lhs and rhs (boolean)
* `systolic.xor( lhs : SystolicAST, rhs : SystolicAST )` lhs xor rhs (boolean)
* `systolic.rshift( lhs : SystolicAST, rhs : SystolicAST )` lhs >> rhs (arithmatic shift)
* `systolic.lshift( lhs : SystolicAST, rhs : SystolicAST )` lhs << rhs (arithmatic shift)

### Unary Operators: ###
* `SystolicIR( delay : Uint )` (Lua Call Operator). Apply Delay of `delay` cycles.
* `systolic.__not( input : SystolicAST )` boolean or bitwise not
* `systolic.neg( input : SystolicAST )` -input
* `systolic.abs( input : SystolicAST )` |input|
* `systolic.isX( input : SystolicAST )` is input Verilog value X?


SystolicDataflow
-----------

    systolic.lambda( name : String, inputParameter : SystolicIR, [output : SystolicAST], [outputName : String], [pipelines : SystolicAST[]], [valid : SystolicAST], [CE : SystolicAST] ) : SystolicDataflow

Define a Systolic Function (i.e. dataflow that drives a port).
* `name`: Name of the function (port). Used when calling the function.
* `inputParameter`: formal parameter for the function. Must be a SystolicIR returned by `systolic.parameter()` or `systolic.null()`
* `output`: output of the function (optional)
* `outputName`: name of the output port (when lowered to Verilog)
* `pipelines`: List of other pipelines that execute when this function executes. These pipelines do not return a value (typically the store values internally to registers, etc)
* `valid`: SystolicIR Parameter (of type bool) to drive the valid bit. Optional - if not given, a valid bit is automatically created. This is only necessary if you need explicit access to the valid bit for some reason.
* `CE`: SystolicAST Parameter (of type bool) to drive the clock enable. Optional - if not given, function has no clock enable.

SystolicInstance
------------

    SystolicInstance:anyFnName( input : SystolicAST ) : SystolicAST
Return a SystolicAST representing the value of applying any function (`anyFnName`) of an instantiated module on `input`.

SystolicModule
------------

`SystolicModule:toVerilog() : String`
Return the definition of this Systolic Module as a string of Verilog. Lowering to Verilog is relatively straightforward. The systolic module gets turned into a Verilog module. All dataflow inputs and outputs appear as input and output ports on the Verilog module. Port names are set by the dataflow input/output parameter names (which are explicitly passed by the user when the dataflow is constructed). All types get packed into bitfields with the same layout as the type in Terra.

`SystolicModule:instantiate( name : String, [coherent : bool], [arbitrate : bool] ) : SystolicInstance`

Generate a `SystolicInstance` instance of this module.

Systolic contains a number of built-in primitive modules:

### User Defined Module ###
    systolic.module.new( name : String, functions : SystolicFunction[], instances : SystolicInstance[], [onlyWire : bool], [coherentDefault : bool], [verilogParameters : ], [verilog : String], [verilogDelays : Uint[String]] ) : SystolicModule

Define a new Systolic module.
* `name`: Name of the new module (used when lowering to Verilog)
* `functions`: list of all functions to pack into this module.
* `instances`: list of all module instances to be contained in this module.
* `onlyWire`: If true, do not apply pipelining. Module is lowered directly to Verilog. This then serves simply as a higher-level interface to generating Verilog. (optional)
* `coherentDefault`: (optional)
* `verilogParameters`: (optional)
* `verilog`: provide a string of Verilog to stand in for this module (i.e. don't generate Verilog, just return this string). (optional)
* `verilogDelays`: If a Verilog string is provided, this allows you to pass pipelining delays for each port on the module. This is a map from function name to delay. (optional)

### Register ###
    systolic.module.reg( type : Type, hasCE : Bool, [initial : LuaValue], [hasValid : Bool] ) : SystolicModule

Create a register (D flip flop) of type `type`. `hasCE` and `hasValid` indicate whether the flip flop should be generated with a CE and Valid bit. `hasValid` is true by default. `initial` is an initial value for the register.

The returned register module `R` has two dataflows on it:
* `R:set( input : type ) : nil`
* `R:get() : type`

### RegBy ###
    systolic.module.regBy( type : Type, setBy : SystolicModule, [hasCE : Bool], [init : LuaValue] )

RegBy is a generalization of an accumulator. RegBy is a register that atomically performs an operation whenever is it In. The `setBy` argument is the module defining the operation to perform.  the case of an accumulator, setBy would perform an addition. More precisely, `setBy` must be a module with one `:process(input:{type,type})` dataflow on it. The first tuple index is the previous register value, and the second tuple index is the new user input. `process` must have a pipeline delay of 0.

As in the case of the register module, `hasCE` indicates whethere the module should have a CE, and `init` is an optional initial value.

The returned regby module `R` has three dataflows on it:
* `R:set( input : type ) : nil` Reset the value to `input`
* `R:setBy( input : type ) : nil` Set and Perform the setBy operation
* `R:get() : type`

### ram128 ###
    systolic.module.ram128( [hasWrite:Bool], [hasRead : Bool], [init:LuaValue] ) : SystolicModule

ram128 creates a Xilinx 128 bit ram, which occupies one slice. `hasWrite` and `hasRead` indicate whether a read/write dataflow should be generated.

The returned ram128 module `R` has two dataflows on it:
* `R:read( addr : Uint7) : Bits(1)` read bit at address `addr`
* `R:write( {addr : Uint7, Bits(1)} ) : Bits(1)` write bit at address `addr`

### bram2KSDP ###
    systolic.module.bram2KSDP( writeAndReturnOriginal : Bool, inputBits : Number, [outputBits: Number], CE : Bool, [init : LuaValue] ) : SystolicModule

bram2KSDP instantiates a Xilinx BRAM module. Xilinx BRAMs support a number of different configurations (sizes and bandwidths), but they all see to be built out of this module, so I believe this is the fundamental hardware primitive.

The returned bram2KSDP module `R` has two dataflows on it:
* `R:read( addr : Uint7) : Bits(1)` read bit at address `addr`
* `R:write( {addr : Uint7, Bits(1)} ) : Bits(1)` write bit at address `addr`

### FileModule (Verilog simulator only) ###
    systolic.module.file( filename : String, type :Type, CE : bool )

The file module allows you to read a file on disk in the Verilog simulator (only). `type` is the type of data to read each cycle.

The returned file module `F` has three dataflows on it:
* `F:read() : type` read one value
* `F:write( input : type ) : nil` write one value
* `F:reset() : nil` return to the start of the file

### PrintModule (Verilog simulator only) ###
    systolic.module.print( type : Type, string : String, [CE : Bool], [showIfInvalid : bool] )

The print module allows you to print a string to the console in the Verilog simulator. The module can also take an arbitrary type as input each cycle, which can be printed using the normal Verilog string formatting operators (i.e. `%d` etc). If `type` is a tuple, the tuple will be unpacked, so that you can print multiple values. If `showIfInvalid` is true, this module prints the string always (even when the dataflow is not running).

The returned file module `P` has three dataflows on it:
* `P:process( input : type )` print then string with `input`

### AssertModule (Verilog simulator only) ###
    systolic.module.assert( error : String, CE : bool, [exit : Bool] )

The assert module allows you to fire an assert in the Verilog simulator. String `error` is printed on assert failure. If `exit` is true, the simulation will finish (default true).

The returned assert module `A` has three dataflows on it:
* `A:process( flag : Bool )` check the assert condition on `flag`

Misc
===============

### src/sdfrate.t ###
Provides helper functions for dealing with SDFRates.

The `SDFRate` refered to in this document has no formal constructor. It simply refers to a lua table in the following format:

    {{n,d}} -- a single SDF stream with rate n/d. n and d must be unsigned integers.
    {{1,2}} -- e.g. SDF rate 1/2

    {{n1,d1},{n2,d2}} -- two SDF streams with rate n1/d1, n2/d2 (for modules with multiple stream inputs...)
    {{1,3},{2,3}} -- e.g. SDF rate 1/3,2/3

SDF Rates are stored in this rational format because technically doubles aren't sufficient to store all rationals, which caused problems for us in the past.

### src/systolicsugar.t ###
Convenience classes for incrementally constructing Systolic modules and dataflows.

### src/fpgamodules.t ###
A number of useful Systolic module constructors.

* arbitrary-width ram built of slices
* arbitrary-width ram built of BRAMs
* FIFO
* Shift register constructor

### src/fixed.t ###
Experimental. A fixed-point math library built on top of Systolic (which only supports plain ints). Internally keeps track of the correct fixed point location, which saves you from having to implement this with shifts and track the point yourself. Also has the ability to automatically lower the math to a Terra implementation, with the same (arbitrary) precision as the hardware.

### src/fixed_float.t ###
Experimental. A floating point implementation of `fixed.t`. Used to generate ground-truth implementations. Simply load `fixed_float.t` instead of `fixed.t` and your implementation should still work, but now has 'infinite' precision (from the floats).

### examples/examplescommon.t ###

A library of helper Rigel modules that are used for multiple examples.

### examples/harness.t ###

Code for generating the test harness for Terra (`harness.terraOnly`), Verilog simulator + Terra (`harness.sim`) and AXI+Terra+Sim (`harness.axi`).

TODO: These functions are a giant mess of arguments and spaghetti - refactor this to be cleaner.