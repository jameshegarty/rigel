Systolic is a language for describing synchronous data-processing pipelines: pipelines that read data from a stateful element (register, bram), perform some computation on it in a fixed number of cycles, and write the result to another stateful element. Systolic abstracts away performance characteristics of the pipeline (number of cycles it takes), resulting in semantics that allow pipelines of different timings to interact.

AST
===

a+b
a-b

AST:disablePipelining()
disable pipelining on this ast

AST:verilog()
convert this ast into verilog code. Used internally.

AST:pipeline()
Takes AST with no timing (all happens in one cycle), and inserts explicit registers to decrease clock cycle. Returns a table of delays for each function.

AST:toTerra()
converts this AST into a terra struct

systolic.parameter( name, type )
The formal parameter of a function

systolic.index( expr, idx, idy )
expr is a tuple or an array2d. idx,idy should be a number. if expr is a tuple, idy should be nil

systolic.cast( expr, type )
casts expr to type

systolic.constant( value, type )
makes a constant

systolic.tuple( {expr} )
Turns a list of asts into a tuple.

systolic.array2d( {expr}, w, h )
MACRO: a composition of systolic.tuple and a cast to array type. Types must match!

systolic.select( cond, a, b )

systolic.le( lhs, rhs ) : lhs <= rhs
systolic.lt( lhs, rhs ) : lhs < rhs
systolic.eq( lhs, rhs ) : lhs == rhs
systolic.ge( lhs, rhs ) : lhs >= rhs
systolic.gt( lhs, rhs ) : lhs > rhs
systolic.__or( lhs, rhs ) : lhs or rhs
systolic.__and( lhs, rhs ) : lhs and rhs
systolic.neg( expr ) : -expr

Functions
=========


Fn = systolic.lambda( name, input, valid )

If valid is 'true' (lua boolean), then this function will always run (valid bit will be wired to true). Similar to a verilog always@ block.
valid can also be a boolean parameter, if you want to explicitly refer to it.
if valid is nil, then the compiler will create a valid bit and wire it up using the default behavior.

Fn:addPipeline(ast)

Fn:addIf( condast, ast )
Syntax sugar for adding pipeline ast and wiring conast to its valid bits

Fn:addAssert( cond, str, ... )

Fn:returnValue(ast)

Fn:isPure()
Returns true if this function doesn't modify state (ie only has a :return)

Modules
=======

Module Options:

inst = M:instantiate( name, options )
returns an Instance

Instantiation Options:
These instantiation options will inheret the defaults of the module if not provided.

arbitrate = {nil, "valid", "values" }
nil => Can only call each function on this instance once
'valid' => can call functions multiple times, but only one valid bit can be true
'value' => can call functions multiple times, and multiple valid bits must be true, but values must match
'allow' => Just allow multiple calls?

coherent: This determines the semantics of calling different functions on this modules. 
If coherent==false, there is no guarantee about the timing of calling different functions. Ex: if you have a :valid() and a :get() function, you'd better make sure that your valid and get are called in the came clock. In practice, this means that :valid must not be pipelined, and :get must be the first thing in the pipe. The module documentation should tell you any inter-function semantics.
If coherent==true, we guarantee that all calls to a module happen in the same cycle, if the calls to these calls happen in the same cycle. So, if we call :set in one function A, and :get in another function B, if A and B are called in the same cycle, then :get and :set will be called in the same cycle, regardless of where they appear in the pipeline. The information from :set will propagate to the :get (like as if there is a direct wire). Examples: registers, DRAM

:toVerilog()
memoized. returns the verilog for defining this module. 

:toTerra()
returns terra Struct for simulator for this module.

:complete()
Checks whether functions refer to valid instances. Pipelines. Takes the module and lowers its definition to an AST. Used internally to implement :verilog(). 
Function delays are unavailable until :complete() is called. Once :complete() is called, the module can't be modified.

Module Constructors
===================

M = systolic.module( name, options ) : user defined module
------------------------------------------------------

inst = M:add( inst : Instance )
add Instance inst to the module and return it.

fn = M:addFunction( fn )

systolic.bram()
---------------

has functions:
oldvalue = :writeAndReturnOriginal( addr, value )

systolic.reg(T)
--------------

has functions:
:read() -- pure
:write( value )
:writeBy( module, value )
          module:process :: {A,B} -> A, not pipelined. A is type of register, B is type of value

systolic.ram128()
--------------

has functions:
:read( addr )
:write( addr, value )

systolic.wire(T)
---------------
This is like a register, but has no cycle delay.

:read() -- pure
:write( value )

systolic.fwrite(filename)
:write( value ) -- writes value to file

Instances
=========

:verilog()
memoized. returns the verilog for instantiating this module. 

:fn(), where fn is any function defined on the module
returns the AST for a call to function 'fn' on the module instance

Conventions
===========

A 'pure' module should have one function :process(input) on it.

A ready-valid module should have 4 functions.
ready-valid interfaces are not necessarily registered. Example: ready is wired from downstream, valid is wired from upstream, data is processed combinationally.
:valid() -- output is valid this clock cycle
:pop() -- get the output

:push(input) -- . Should only be called if ready() is true! Returns nil - a sink.
:ready() -- Is module ready to process an input?

So then, if we have a pipeline P of modules A->B->C, data flowing from left to right, the definition of P should look like:

process = systolic.function(...)
process:addIf(systolic.and(A:valid(), B:ready()), B:push(A:pop()) )

output of :ready() should be driven by valid bit of :pop() and any internal stalls. 

always:addStatement( systolic.if(B:ready(), B:push(A:pop(), A:valid())


-----------
popvalid = symb(bool)
module RV{
  reg store : T;
  reg writeAddr : uint8
  reg readAddr : uint8

  function pop({}, valid=popvalid) : stall
    storeValid:set(false)
    return doslowstuff(store:read())
  return

  function valid() : nopipeline
    return storeValid
  end

  function push(inp)
    storeValid:write(true)
    store:write(inp)
  end

  function ready() : nopipeline
    return storeValid==false or popvalid
  end
}