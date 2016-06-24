Getting Started with Rigel
==========================

_James Hegarty <jhegarty@stanford.edu>_

Rigel is a language for describing image processing hardware embedded in Lua. Rigel can compile to Verilog hardware designs for Xilinx FPGAs, and also can compile to fast x86 test code using Terra.

Install & Run
-------------

Installing Rigel is not required. However your system needs to have Terra installed, and paths set correctly so that Terra can find all the Rigel sources. You can download the Terra binary files on https://github.com/zdevito/terra/releases (tested with release-2016-03-25) or build it. You can clone the repository and build Terra using the instructions in the [Terra Readme](https://github.com/zdevito/terra). Run the REPL and make sure it installed correctly.

Next, add the Rigel language definition to your lua path environment variable, and the Terra binary location to your PATH. This can be accomplished by add this to .profile or .bashrc:

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

* **make terra:** Run compiler and x86 simulator. Sim outputs at `examples/out/[testname].bmp` and verilog outputs at `examples/out/[testname].axi.v`
* **make sim:** Run Verilog simulator. Outputs at `examples/out/[testname].sim.bmp`
* **make axibits:** Build 7020 bitstreams. Outputs at `examples/out/[testname].axi.bi`t
* **make axi:** Run 7020 bitstream on board. Outputs at `examples/out/[testname].axi.bmp`
* **make axibits100:** Build 7100 bitstreams. Outputs at `examples/out/[testname].axi100.bit`
* **make axi100:** Run 7100 bitstream on board. Outputs at `examples/out/[testname].axi100.bmp`
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
* [Misc](#misc)

Base Types (types.t)
====================

Rigel's type system supports arbitrary precision ints, uints, floats, bitfields, bools, 2d arrays, and tuples. types.t provides the type class that is used throughout darkroom.

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

Rigel operators
---------------

### rigel.input( type:Type, [sdfRate:SDFRate] ) ###

### rigel.apply( name:String, module:RigelModule, input:RigelValue ) ###

### rigel.applyMethod( name:String, instance: RigelInstance, functionName:String, input:RigelValue ) ###

### rigel.constant( name:String, value:LuaValue, type:Type ) ###

### rigel.tuple( name:String, inputList:RigelValue[], [packStreams:Bool] ) ###

### rigel.array2d( name:String, inputList:RigelValue[width*height], width:Uint, height:Uint, [packStreams:Bool] ) ###

### rigel.selectStream( name:String, input:RigelValue, i:Uint ) ###

### rigel.statements( values:RigelValue[] ) ###

Rigel Interface Types
---------------------

It is useful to think of these as abstract types that enforce rules of composition, not as literal descriptions of the signals of the resulting hardware. The Rigel compiler runs a small amount of code to correctly wire each interface type to its neighbors when it lowers to RTL. TODO: in the future it may be possible to make the low-level RTL layer powerful enough to type all of these interfaces and compose them directly.

By convention in this document we will use the constants *A*, *B*, etc to refer to an arbitrary type. In this section they will refer to base types (see types.t below).

### A->rigel.V(B) ###

### rigel.V(A)->rigel.RV(B) ###

### rigel.Handshake(A)->rigel.Handshake(B) ###

Rigel also has the ability to make aggregates (arrays and tuples) of Handshakes. Since every Rigel module only has a single input and output, this allows us to implement modules that work on multiple streams. These types _can not_ be nested (no Handshakes of Handshakes). Handshake(A) only works over base types.

### Handshake(A)[N] ###
    Array of Handshakes.

### {Handshake(A),Handshake(B),...} ###
    Similar to the array of Handshakes above, but allows for different types.

Rigel also has provisional support for the ability to pack multiple streams onto one shared bus. This allows for supporting time-multiplexed hardware (hardware that operates on different streams in different cycles), or serializing multiple streams into one stream.

### rigel.HandshakeArray(A,N) ###
    Unlike an array of *Handshakes* (above), a *HandshakeArray* can only have 1 of the *N* streams active per cycle. HandshakeArray's ready bit identifies the stream that should be written on the data bus in the current cycle.

### rigel.HandshakeTmuxed(A,N) ###
    *HandshakeTmuxed* behaves like a regular *Handshake* but allows multiple different data streams to flow over one interface. HandshakeTmuxed's valid bit identifies the ID of the stream that is active. 

    Regular *Handshake* modules can be lifted to work over *HandshakedTmuxed*, but this should only be done if the module isn't stateful - there is no way to automatically duplicate the module state so that it stays coherent for each stream!


RigelModule
-----------

### module:compile() ###

### module:toVerilog() ###


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

### lift ###
    modules.lift( newModuleName:String, inputType:Type, outputType:Type, delay:Number, terraFunction:terraFunction, systolicInput:SystolicValue, systolicOutput:SystolicValue)
    fields: {..., kind="lift_"..newModuleName}

*lift* takes a function from the lower-level languages (Terra and Systolic) and lifts them into a Rigel module. *delay* must correspond to the pipeline delay from *systolicInput* to *systolicOutput*.

### lambda ###

### seqMap ###
    type: null->null
    modules.seqMap( module:RigelModule, width:uint, height:Uint, T:Uint )
    fields: {..., kind="seqMap", W=width, H=height, T=T }

### seqMapHandshake ###
    type: null->null
    modules.seqMapHandshake( module:RigelModule, tapInputType:Type, tapValue=tapValue, inputCount:Uint, outputCount:Uint, axi:Bool, [readyRate:Uint] )
    fields: {..., kind="seqMapHandshake", inputCount=inputCount, outputCount=outputCount }

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

### stencilLinebufferPartialOffsetOverlap* ###

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

### border ###

### borderSeq ###

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

    
### demux ###
    type: HandshakeTmuxed(A,N)->Handshake(A)[N]
    modules.demux( A:Type, rates:SDFRate[N] )
    fields: {..., kind="demux", A=A, rates=rates }

### flattenStreams ###

### broadcastStream ###
    type: Handshake(A) -> Handshake(A)[N]
    modules.broadcastStream( A:Type, N:Uint )
    fields: {..., kind="broadcastStream", A=A, N=N }

### fifo ###

Misc
----

### reduceThroughput ###
    type: V(A) -> RV(A)
    modules.reduceThroughput( A:Type, factor:Number)
    {..., kind="reduceThroughput", factor=factor}

*reduceThroughput* is a debugging module. It artificially reduces the SDF throughput of the output stream by 1/factor.

### lut ###

### constSeq ###

### overflow ###

### underflow ###

### cycleCounter ###

### freadSeq ###

### fwriteSeq ###

Systolic (systolic.t)
=====================

The `Systolic` library is used to construct pipelined datapaths and lower them to Verilog. In this system, users define `SystolicModule`'s, which correspond to modules in Verilog. SystolicModules can be instantiated (returning a `SystolicInstance`), and SystolicModules can contain instances of other modules. Instances indicate that a copy of the hardware necessary to implement that module should be created.

SystolicModules contain one or more `SystolicDataflow`'s, which represent operations to be performed by the module. Each SystolicDataflow can have one input and/or one output (which correspond to input/output ports on modules in Verilog). The output is typically driven by the input, but can also be driven by an internal module instance, such as a register. The user specifies the operations to be performed by the dataflow by creating a DAG of `SystolicIR` nodes. `SystolicIR` is a specification of the primitive operations that can be performed by the hardware.

The `SystolicIR` and SystolicDataflows are restricted so that they can always be pipelined to an arbitrary depth by the compiler. The pipelineing is performed automatically prior to lowering to Verilog. SystolicDataflows can each have an associated valid bit (to implement pipeline bubbles) and clock enable `CE` (to stall the pipeline). These two signals are wired automatically by the compiler.

SystolicIR
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
Return the definition of this Systolic Module as Verilog.

`SystolicModule:instantiate( name : String, [coherent : bool], [arbitrate : bool] ) : SystolicInstance`

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