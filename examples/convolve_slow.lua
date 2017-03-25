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
                                   
  local merged = R.connect{ input = R.concat{ convolveInput, filterCoeff }, 
    toModule = R.modules.SoAtoAoS{ type={R.uint8,R.uint8}, size={4*P,4} } }
  
  local partials = R.connect{ input = merged, toModule =
    R.modules.map{ fn = R.modules.mult{ inType = R.uint8, outType = R.uint32}, 
                   size={4*P,4} } }
  
  local sum = R.connect{ input = partials, toModule =
    R.modules.reduce{ fn = R.modules.sum{ inType = R.uint32, outType = R.uint32 }, 
                      size={4*P,4} } }
  
  return R.defineModule{ input = convolveInput, output = sum }
end

----------------
input = R.input( R.HS( R.array( R.uint8, 1) ) )

padded = R.connect{ input=input, toModule = 
  R.HS(R.modules.padSeq{ type = R.uint8, V=1, size=inSize, pad={8,8,2,1}, value=0})}

stenciled = R.connect{ input=padded, toModule =
  R.HS(R.modules.linebuffer{ type=R.uint8, V=1, size=padSize, stencil={-3,0,-3,0}})}

-- split stencil into columns
partialStencil = R.connect{ input=stenciled, toModule=
  R.HS(R.modules.devectorize{ type=R.uint8, H=4, V=1/P}) }

-- perform partial convolution
partialConvolved = R.connect{ input = partialStencil, toModule = 
  R.HS(makePartialConvolve()) }

-- sum partial convolutions to calculate full convolution
summedPartials = R.connect{ input=partialConvolved, toModule =
  R.HS(R.modules.reduceSeq{ fn = 
    R.modules.sumAsync{ inType = R.uint32, outType = R.uint32 }, V=1/P}) }

convolved = R.connect{ input = summedPartials, toModule = 
  R.HS(R.modules.shiftAndCast{ inType = R.uint32, outType = R.uint8, shift = 8 }) }

output = R.connect{ input = convolved, toModule = 
  R.HS(R.modules.cropSeq{ type = R.uint8, V=1, size=padSize, crop={9,7,3,0} }) }


convolveFunction = R.defineModule{ input = input, output = output }
----------------

R.harness{ fn = convolveFunction,
           inFile = "1080p.raw", inSize = inSize,
           outFile = "convolve_slow", outSize = inSize }