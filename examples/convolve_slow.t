R = require "rigelSimple"

P = 1/4
inSize = { 1920, 1080 }
padSize = { 1920+16, 1080+3 }

function makePartialConvolve()
  local convolveInput = R.input( R.array2d(R.uint8,4*P,4) )

  local filterCoeff = R.connect{ input=nil, toModule =
    R.modules.constSeq{ type=R.array2d(R.uint8,4,4), P=P, value = 
      { 4, 14, 14,  4,
        14, 32, 32, 14,
        14, 32, 32, 14,
        4, 14, 14,  4} } }
                                   
  local merged = R.connect{ input = R.tuple{ convolveInput, filterCoeff }, 
    toModule = R.modules.SoAtoAoS{ type={R.uint8,R.uint8}, size={4*P,4} } }
  
  local partials = R.connect{ input = merged, toModule =
    R.modules.map{ fn = R.modules.mult{ inType = R.uint8, outType = R.uint32}, 
                   size={4*P,4} } }
  
  local sum = R.connect{ input = partials, toModule =
    R.modules.reduce{ fn = R.modules.sum{ inType = R.uint32, outType = R.uint32 }, 
                      size={4*P,4} } }
  
  return R.pipeline{ input = convolveInput, output = sum }
end

----------------
input = R.input( R.RV( R.array( R.uint8, 1) ) )

padded = R.connect{ input=input, toModule = 
  R.RV(R.modules.padSeq{ type = R.uint8, P=1, size=inSize, pad={8,8,2,1}, value=0 }) }

stenciled = R.connect{ input=padded, toModule =
  R.RV(R.modules.linebuffer{ type=R.uint8, P=1, size=padSize, stencil={-3,0,-3,0} }) }

partialStencil = R.connect{ input=stenciled, toModule=
  R.RV(R.modules.changeRate{ type=R.uint8, H=4, inputW=4, outputW=4*P}) }

partialConvolved = R.connect{ input = partialStencil, toModule = 
  R.RV(makePartialConvolve()) }

sum = R.connect{ input=partialConvolved, toModule =
  R.RV(R.modules.reduceSeq{ fn = 
    R.modules.sumAsync{ inType = R.uint32, outType = R.uint32 }, P=P}) }

convolved = R.connect{ input = sum, toModule = 
  R.RV(R.modules.shiftAndCast{ inType = R.uint32, outType = R.uint8, shift = 8 }) }

output = R.connect{ input = convolved, toModule = 
  R.RV(R.modules.cropSeq{ type = R.uint8, P=1, size=padSize, crop={9,7,3,0} }) }


convolveFunction = R.pipeline{ input = input, output = output }
----------------

R.harness{ fn = convolveFunction,
           inputFile = "1080p.raw", inputSize = inSize,
           outputFile = "convolve_slow", outputSize = inSize }