uarttest.v:
  adds 10 to input over uart, pure verilog implementation

`make uarttest.run`:
  load uarttest.v on icestick

`python uarttest.py infile outfile`:
  load file `infile` into icestick using uart, write returned data to `outfile`      

--------------
magtest.py:
  The same thing as uarttest.v, but implemented in Magma. `txmod.v` and `rxmod.v` are verilog files needed for this example (modules were simply pulled out of uarttest.v)