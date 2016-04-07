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
    modules.lift( newModuleName:String, inputType:Type, outputType:Type, delay:Number, terraFunction:terraFunction, systolicInput:SystolicAST, systolicOutput:SystolicAST, [systolicInstances:Table], [sdfOutput:SDFRate])

*lift* takes a function from the lower-level languages (Terra and Systolic) and lifts them into a Rigel module. *delay* must correspond to the pipeline delay from *systolicInput* to *systolicOutput*.
    
    fields: {..., kind="lift_"..newModuleName}

split
-----
split :: {A[n*m],n} -> (A[m])[n]
splits an array of size n*m into n arrays of size m

higher-order functions
======================

map
---
map :: (A -> B, int w, int h) -> (A[w,h] -> B[w,h])
map :: (Tmux(A) -> Tmux(B)) -> (Tmux(A[w,h]) -> Tmux(B[w,h]))

stencil
-------
stencil :: {int l, int r, int t, int b} -> (A[w,h] -> A[r-l+1,t-b+1][w,h])

reduce
------
reduce :: ({A,A}->A) -> (A[w,h] -> A)

reduce takes in a binary, associative operator f that reduces two values into one. 

(reduce f) a === (reduce f) ( (map (reduce f)) (split a n) ) given a : A[n*m]

down
----
down :: {int x, int y} -> ( A[w,h] -> A[w/x,h/y] )

(stencil {l,r,t,b}) down {x,y} === (down {x,y}) ((down {x,y}) stencil {l*x,r*x,t*y,b*y})
(down {x,y}) (map f) === map ( (down {x,y}) f )

up
----
up :: {int x, int y} -> ( A[w,h] -> A[w*x,h*y] )

lift
----
lift :: {terraFn, inputType, outputType} -> (inputType -> outputType)  

scanl
-----

filter
------
filter {f,cond} : {A[w,h], bool[w,h]} -> Sparse(A)

gather
------

broadcast
---------

packPyramid
-----------

unpackPyramid
-------------

concrete functions
==================

makeStateful
------------
makeStateful :: (A->B) => ( Stateful(A) -> Stateful(B) )

State passthrough.


The difference between handshakes of retimed (pure or stateful) modules and real handshake interfaces is that for retimed modules, the whole pipeline stalls at once if any units stall. For real retimed modules connected together, some of them call stall while others continue to work.

makeHandshake
-------------
makeHandshake :: (Stateful(A)->Stateful(B)) => ( StatefulHandshake(A) -> StatefulHandshake(B) )

Take a retimed module that has no valids and wrap it in a RV interface.


liftHandshake
-----------------
liftHandshake :: (f : StatefulV(A) -> StatefulRV(B)) => (StatefulHandshake(A)->StatefulHandshake(B))

This means wrap the retimed module in a RV interface. The input bool is input_valid_in_this_cycle. If this bool is false, then the input will be garbage and should be ignored. The two output bools are valid_this_cycle, and ready_next_cycle. Ready is initially set to false (in the cycle before f runs at all). Ready must have pipeline delay 0.

liftHandshakeAmplify
-----------------
liftHandshakeAmplify :: (f : StatefulV(A) -> StatefulRV(B)) => (StatefulHandshake(A)->StatefulHandshake(B))

Ready must have pipeline delay 0. Example: stencil linebuffer partial. This has to run even when there is no valid data (due to ready=false). So it takes an explicit bool for valid data in the input.

liftHandshakeDecimate
-----------------
liftHandshakeDecimate :: (f : Stateful(A) -> StatefulV(B)) => (StatefulHandshake(A)->StatefulHandshake(B))

This is like lift handshake, but ready=true always. This works well for modules that decimate data only. Example: sequential reduce.

liftStateful :: (f : Stateful(A) -> Stateful(B)) => (Stateful(A)->StatefulV(B))
valid=true always.

liftDecimate
------------
liftDecimate :: (f : Stateful(A) -> StatefulV(B)) => (StatefulV(A)->StatefulRV(B))
R=true always. f only runs if input is valid.


RPassthrough :: (f : StatefulV(A) -> StatefulRV(B)) => (StatefulRV(A) -> StatefulRV(B))
              R's are anded

RVPassthrough :: (f : Stateful(A) -> Stateful(B)) => (StatefulRV(A) -> StatefulRV(B))
=== RPassthrough(liftDecimate(liftStateful(f)))

stateCompose
------------
stateCompose :: { {A,State1}->{B,State1}, {B,State2}->{C,state2} } -> ( {A,{State1,State2}} -> {C,{State1,State2}} )

scanlSeq
--------
scanSeq :: { (Stateful(A)->Stateful(Tmux(B,T))), A[n], InitialState} -> B[n*T]
scanSeq {f, scanSeq {g, a, InitialG}, InitialF } === scanSeq { stateCompose {f,g}, a, {InitialF, InitialG} }

look at sequence, forM

inputC
------

downSeq
-------
downSeq :: {T,w,h,x,y} -> ( Stateful(A[T],DownState) -> Stateful( Tmux(A[T], 1/(x*y)),DownState) )
s.t. (down {x,y}) a === concat (scanlSeq {downSeq {R,w,h,x,y},a,InitialState}) given a : A[w,h]
s.t. down {x,y} === downSeq {w*h,w,h,x,y} given a : A[w,h] (purely wiring)

downModule :: {A,T,w,h,downX,downY} => ( Stateful(A[T]) -> Stateful(Sparse(A,T) )

implementation:
downSeq = liftPureHandshake(stateCompose {sparseFifo, downModule })

reduceSeq
---------
reduceSeq :: {f,T} -> ( Stateful(A,ReduceState) -> Stateful(Tmux(A,T),ReduceState) )
s.t. (reduce f) a === scanlSeq {reduceSeq {f,T}, (split a T), InitialState} given a : A[n*m]

T=1/n means that this produces 1 output for every n inputs, reduced using reduction function.

unpackStencil
-------------
unpackStencil :: {w,h,N} -> ( A[w+N-1,h] -> A[w,h][N] )

Neighboring stencils overlap. This takes N stencils that have been compressed into 1 array back into N arrays. Purely wiring.

linebuffer
----------
linebuffer :: {T,w,h,l,r,t,b} -> ( {A[T],State} -> {A[r-l+T,t-b+1],State} ) given T>=1
s.t. (stencil {l,r,t,b}) a === concat (unpackStencil (scanlSeq {linebuffer {T,w,h,l,r,t,b},split a T,Initial})) given a : A[w,h]

cat2dXSeq
--------
cat2dXSeq :: T : int => ( Stateful(A[w,h]) -> Stateful(Tmux(A[w/T,h],T) ) 
s.t. a = scanlSeq {cat2dXSeq T, splitX a 1/T, Initial}

linebufferPartial
----------
linebufferPartial :: {T : int, w : int,h,l,r,t,b} -> ( {A,State} -> Tmux(Stateful(A[(r-l+1)*T,(t-b+1)*T]),1/T) )

This is like a linebuffer, but instead of producing N stencils per pixels, it produces a substencil of size N per pixel.
(linebuffer {1,w,h,l,r,t,b}) a === scanSeq {(cat2dXSeq T).(linebufferPartial {T,w,h,l,r,t,b}), , Initial} given a : A[1]

SSR
---

SSRPartial
----------
SSRPartial :: {A, t, xmin, ymin} => ( 

constSeq
--------
constSeq :: {A[w,h],T} -> ( Stateful(nil) -> Stateful(A[w*T,h]) )
s.t. a === scanSeq { constSeq {A,T}, broadcast nil 1/T, Initial }

sparseFifo
------------
sparseFifo :: {A, int n, int w, int h} => (Stateful(Sparse(A,w,h)) -> StatefulHandshake(A[w,h]))

Take a sparse array and densify it.

linebufferTmux
--------------
linebufferTmux :: {T,N,[w],[h],[l],[r],[t],[b]} -> ( {StatefulHandshake(A[T]),StatefulHandshake(A[T]),...} -> {StatefulHandshake(A[r-l+T,t-b+1],N),} )

linebufferTmux takes N state contexts (with different stencil sizes etc) and multiplexes them onto one piece of hardware

tmux
----
tmux :: {f, N, internalRouting} => ( Stateful({A,A,...}) -> Stateful({Tmux(B,T_1,Tmux(B,T_2)...}) ) given f : A->B, not stateful

f is the function to time multiplex.
N is the number of inputs
internalRouting is a table of size N. if entry _i_ is 'x', this is an extern input. If _i_ is a table, this is driven by an output of the tmux - the table should have format {j,passthroughFn}. j is the output port to drive this with, passthroughFn is a stateful function that will be applied to this input.

tmux :: {f, inputlist} -> ( {StatefulHandshakeRegistered(A), StatefulHandshakeRegistered(A),...} -> {StatefulHandshakeRegistered(B), StatefulHandshakeRegistered(B), ... } ) given pure f : A->B 

inputlist is a table of SDF rates, one for each input/output of the tmux.

To solve SDF for the tmux, at least one of its inputs must have a determined SDF rate (eg be driven by a lambda parameter). Until this rate hits the tmux, the tmux's rate is set to undetermined. This will require multiple iterations to convergence.

It's possible to connect a tmux output to its inputs, creating an infinite loop. You can construct a graph like this in SDF, but it's malformed. We can detect this case in the SDF solver. If we have an iteration where the # of nodes with undetermined rates doesn't change relative to the last iteration, it's stalled, and we can error out.

freadSeq
--------
freadSeq :: {filename, type} => nil -> Stateful(type)
Read from the file at 'filename' in chunks of type:sizeof()

freadHandshake
--------
freadHandshake :: {filename, type, T} => nil -> Stateful(type)
Read from the file at 'filename' in chunks of type:sizeof(). If T<1 then this throttles the input rate to the pipe.

fwriteSeq
---------
fwriteSeq :: {filename, type} => type -> type
This is a passthrough, so that you can put it in the middle of a pipe

seqMap
------
seqMap :: {f,W,H,T} => A[W,H] -> B[W,H] given f:Stateful(A[T])->Stateful(B[T])

seqMapHandshake
---------------


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