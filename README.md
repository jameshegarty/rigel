Types
=====

State = opaque
Stateful(A) = {A,State}

Tmux(A, int T) = {A,validbit}

Sparse(A, int W, int H) = {A,validbit}[w,h]

functions
=========

split
-----
split :: {A[n*m],n} -> (A[m])[n]
splits an array of size n*m into n arrays of size m

higher-order functions
======================

map
---
map :: (A -> B) -> (A[w,h] -> B[w,h])
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

threadState
-----
threadState :: (A->B) => ( Stateful(A) -> Stateful(B) )

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

implementation:
downSeq = stateCompose {sparseFifo, downModule }

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

constSeq
--------
constSeq :: {A[w,h],T} -> ( Stateful(nil) -> Stateful(A[w*T,h]) )
s.t. a === scanSeq { constSeq {A,T}, broadcast nil 1/T, Initial }

sparseFifo
------------
sparseFifo :: int n -> (Sparse(A) -> A[n])

Take a sparse array and densify it.

tmux
----
tmux :: {f, inoutMap, Gs} -> ( Stateful({A,A,...}) -> Stateful({Tmux(B,T_1,Tmux(B,T_2)...}) ) given f : A->B, not stateful

f is the function to time multiplex.
inoutMap is a list of numbers or x. {x,0,1,2} means input 0 is an input of the resulting function, input 1 is fed by output 0, etc.
Gs is a list of (stateful) functions that are applied to the inputs before being processed. G={g1,g2,g3} Then, f.g1, f.g2 is computed by the tmux.

IR
==

apply
-----

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