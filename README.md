Installation
=====

Types : types.t
=====

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

State = opaque
Stateful(A) = {A,State} -- 1 state context
Stateful(A,N) = {A,State[N]} -- N state contexts
StatefulHandshake(A) = {A,State,bool}
StatefulHandshakeRegistered(A) = {A,State,bool}

Tmux(A, int T) = {A,validbit}

Sparse(A, int W, int H) = {A,validbit}[w,h]

Having a function from Stateful->StatefulHandshake is potentially valid, but then this module would have to have its own (infinite) buffer inside it (b/c on the input it might get data every cycle, but its output is stalled, so the data has to go somewhere). Instead, we currently only have StatefulHandshake->StatefulHandshake. In this case, no buffering is needed, and we get correct behavior. The stalls propagate all the way to the front of the pipe. We can insert explicit fifos to hide stalls. In particular, we can make a fifo of type Stateful->StatefulHandshake to represent this buffer, if this is the behavior we want. Fifos can also be of type StatefulHandshake->StatefulHandshake if they are just there to hide stalls.

operators
=========

lambda
------

When defining a function that has as input a tuple of StatefulHandshake, you have to declare the SDF rate of each StatefulHandshake explicitly. In the case of a single StatefulHandshake, you can just set the rate to 1, and calculate the resulting rate based on propegation. But for tuples, we can't solve for the rates without doing global constraint solving. Example, something that has input rates {1,1} may result in a valid output rate, but won't mean the same thing as declaring the input rate to be {1,1/2}, when we go to compose it with other functions.

Modules : src/modules.t
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
    modules.lift( newModuleName:String, inputType:Type, outputType:Type, delay:Number, terraFunction:terraFunction, systolicInput:SystolicAST, systolicOutput:SystolicAST)
    fields: {..., kind="lift_"..newModuleName}

*lift* takes a function from the lower-level languages (Terra and Systolic) and lifts them into a Rigel module. *delay* must correspond to the pipeline delay from *systolicInput* to *systolicOutput*.

### lambda ###

### linebuffer ###

### SSR ###

### SSRPartial ###

Array Manipulation
------------------

### stencil ###

### unpackStencil ###

### SoAtoAoS* ###
    type: {Array2d(a,W,H),Array2d(b,W,H),...} -> Array2d({a,b,c},W,H)
    examplescommon.SoAtoAos( width:uint, height:uint, typelist:Type[], [asArray:bool] )

*SoAtoAos* converts a tuple of arrays of the same size into an array of tuples (i.e. struct of arrays to arrays of structs transform).

### posSeq ###

### border ###

### borderSeq ###

### cropSeq ###

### padSeq ###

Multi-Rate Modules
------------------

### changeRate ###

### filterSeq ###

### downsampleXSeq ###

### downsampleYSeq ###

### upsampleXSeq ###

### upsampleYSeq ###


Higher-Order Modules
--------------------

### map ###

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

### liftHandshake ###
    given f:V(A)->RV(B), has type Handshake(A)->Handshake(B)
    modules.liftHandshake( f:Module )
    fields: {..., kind="liftHandshake", fn=f}


### makeHandshake ###
    given f:A->B, has type Handshake(A)->Handshake(B)
    modules,makeHandshake( f:Module )
    fields: {..., kind="makeHandshake"}

### RPassthrough ###

### waitOnInput ###

Streams
-------

### packTuple ###
    type: {Handshake(a), Handshake(b),...} -> Handshake({a,b,...})
    modules.packTuple( typelist:Type[] )
    fields: {..., kind="packTuple"}

*packTuple* takes multiple Handshake streams and synchronizes them into a single stream (i.e. to implement fan-in).

### serialize ###
    modules.interleveSchedule
    modules.pyramidSchedule

### toHandshakeArray ###

### demux ###

### flattenStreams ###

### broadcastStream ###

### fifo ###

Misc
----

### reduceThroughput ###

### lut ###

### constSeq ###

### overflow ###

### underflow ###

### cycleCounter ###

### freadSeq ###

### fwriteSeq ###

IR
==

apply
-----

applyRegStore, applyRegLoad
-----------------------

input (value)
-----

tuple
-----
A[n],B[n],C[n] -> {A,B,C}[n]

tuple must have valid bits on some (but not necessarily all) of its inputs. Then the type is eg:
Tmux(A[N]),B[n],C[n] -> Tmux({A,B,C}[n])

index
-----

SDF
===
The user provides us with some throughput T. In the case of the top level function (that processes the whole image), this is likely to be 1/w*h (i.e. 1 pixel per clock).

input :: input (1) ->
up {x,y} I :: I -> (1) up (x*y) ->
down {x,y} I :: I -> (x*y) down (1) ->
reduce f I given I:A[x,y] :: I -> (1) split (w*h) -> (w*h) reduce (1) ->
map f I given I:A[w,h] :: I -> (1) split (w*h) -> (1) f (1) -> (w*h) collect (1) ->
leaf I :: I -> (1) leaf (1) ->
stencil I :: I -> (1) stencil (1) ->

pointwise:
input (1) -> (1) map (w*h) -> (1) leaf (1) -> (w*h) collect (1) ->
rates: input=1, map=1, leaf=w*h, collect = 1
If T = 1/w*h, we get input=1/w*h, map = 1/w*h, leaf=1, collect = 1/w*h, as expected

convolution (SxS):
input (1) -> (1) stencil (1) -> (1) split (w*h) -> (1) split,"conv" (S*S) -> (1) leaf (1) -> (S*S) collect,"cconv" (1) -> (1) split,"reduce" (S*S) -> (S*S) reduce (1) -> (w*h) collect (1) ->
if T = 1/w*h we get:
input = 1/w*h
stencil = 1/w*h
split = 1/w*h
split,"conv" = 1
leaf = S*S
collect,"conv" = 1
split,"reduce" = 1
reduce = 1
collect = 1/w*h

conv :: input A[S,S] (S*S) -> (S*S) leaf A[S,S] (S*S) -> (S*S) array A[S,S][1] (S*S) -> (S*S) reduce A[1] (1) -> (1) index A (1)
input = 1
leaf = 1
array = 1/S*S
reduce = 1/S*S

input A[w,h] (w*h) -> (w*h) array A[w,h][1] (w*h) -> (w*h) stencil A[S,S][w,h][1] (w*h*S*S) -> (w*h*S*S) index A[S,S][w,h] (w*h*S*S) -> (S*S) conv A[w,h] (1) ->
input = 1
array = 1/w*h
stencil = 1/w*h
index = 1/w*h
conv = 1



if S=3, T = 1/w*h*7 we get:
input = 1/w*h*7 : 1/w*h
stencil = 1/w*h*7 : 1/w*h
split = 1/w*h*7 : 1/w*h
split,"conv" = 1/7 : 1/3
leaf = S*S/7 = 9/7 = 2
collect,"conv" = 1/7 = 1/3
split,"reduce" = 1/7 = 1
reduce = 1/7 = 1/3
collect = 1/w*h*7 = 1/w*h

for split, we look at the input type (array) and rate and round up to nearest factor. For collect, we look at the rate and output type (array) and round up. Otherwise, we look at the input type and rate and round up.

It doesn't matter what the rates end up being. We will synthesize the hardware. eg:
split,"conv" = 1/7 : 1/3
leaf = S*S/7 = 9/7 = 2
This means we have a fifo between the map (pushes 9/3 = 3 items into the fifo each clock), and the leaf (processess 2 items per clock). Fifo has 3 inputs, 2 outputs.

X (a) -> (b) Y
=> Y = (a/b) * X

lowering
========

Given a rate R, we lower a function f : A[w,h] -> B[w,h] to a function l : {A[R],State} -> {B[R],State}, such that:
f a === (scanlc l) {split a R, InitialState}

for each lifted function, it has one or more uses U={T,I,O} with throughput T, input I, and outputs O

1) choose a parition P of U such that the sum of the throughput in each partition is roughly integer
2) 