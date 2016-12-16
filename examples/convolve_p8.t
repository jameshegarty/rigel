R = require "rigelSimple"

P = 8
inSize = { 1920, 1080 }
padSize = { 1920+16, 1080+3 }

function makeConvolve()
  local convolveInput = R.input( R.array2d(R.uint8,4,4) )

  local filterCoeff = R.constant{ type=R.array2d(R.uint8,4,4), value = 
    { 4, 14, 14,  4,
      14, 32, 32, 14,
      14, 32, 32, 14,
      4, 14, 14,  4} }
  
  local merged = R.connect{ input = R.concat{ convolveInput, filterCoeff }, 
    toModule = R.modules.SoAtoAoS{ type={R.uint8,R.uint8}, size={4,4} } }
  
  local partials = R.connect{ input = merged, toModule =
    R.modules.map{ fn = R.modules.mult{ inType = R.uint8, outType = R.uint32}, 
                   size={4,4} } }
  
  local sum = R.connect{ input = partials, toModule =
    R.modules.reduce{ fn = R.modules.sum{ inType = R.uint32, outType = R.uint32 }, 
                      size={4,4} } }

  -- divide by 256 (right shift by 8)
  local output = R.connect{ input = sum, toModule = 
    R.modules.shiftAndCast{ inType = R.uint32, outType = R.uint8, shift = 8 } }

  return R.defineModule{ input = convolveInput, output = output }
end

----------------
input = R.input( R.HS( R.array( R.uint8, P) ) )

-- apply boundary condition by padding stream
padded = R.connect{ input=input, toModule = 
  R.HS(R.modules.padSeq{ type = R.uint8, P=P, size=inSize, pad={8,8,2,1}, value=0})}

-- use linebuffer to convert input stream into stencils
stenciled = R.connect{ input=padded, toModule =
  R.HS(R.modules.linebuffer{ type=R.uint8, P=P, size=padSize, stencil={-3,0,-3,0}})}

-- perform convolution vectorized over P
convolved = R.connect{ input = stenciled, toModule = 
  R.HS( R.modules.map{ fn = makeConvolve(), size = P } ) }

-- crop stream to remove boundary padding
output = R.connect{ input = convolved, toModule = 
  R.HS(R.modules.cropSeq{ type = R.uint8, P=P, size=padSize, crop={9,7,3,0} }) }

convolveFunction = R.defineModule{ input = input, output = output }
----------------

R.harness{ fn = convolveFunction,
           inputFile = "1080p.raw", inputSize = inSize,
           outputFile = "convolve_p8", outputSize = inSize }