local d = require "darkroom"
local C = require "examplescommon"
local harness = require "harness"

--local SADRadius = 4
local SADWidth = 8
--local SearchWindow = 64
local OffsetX = 20 -- we search the range [-OffsetX-SearchWindow, -OffsetX]
local A = types.uint(8)

-- This function is used to select and format the output we want to display to the user
-- (either the index, or SAD value)
function displayOutput()
  local ITYPE = types.tuple{types.uint(8),types.uint(16)}
  local OTYPE = types.array2d(types.uint(8),1)
  local inp = S.parameter( "inp", ITYPE )
  return d.lift("displayOutput",ITYPE, OTYPE, 0,
                terra(a:&ITYPE:toTerraType(), out:&uint8[1])
                  @out = array(a._0)
--                  @out = array([uint8](a._1))
                end, inp, 
                S.cast(S.tuple{S.index(inp,0)},OTYPE) 
                --S.cast(S.tuple{S.cast(S.index(inp,1),types.uint(8))},OTYPE) 
)
end

-- argmin expects type Stateful(A[2][SADWidth,SADWidth][SearchWindow])->StatefulV
-- which corresponds to [leftEye,rightEye]. rightEye should be the same window 'perCycleSearch' times. leftEye has the windows we're searching for the match in.
-- returns: Handshake{index,SADvalu@index} (valid every T cycles)
function argmin(SearchWindow)
  assert(type(SearchWindow)=="number")

  local ITYPE = types.array2d( types.array2d( types.array2d(A,2), SADWidth, SADWidth ), SearchWindow )
  local inp = d.input( ITYPE )

  local idx = {}
  for i=1,SearchWindow do
    -- index gives us the distance to the right hand side of the window
    idx[i] = SearchWindow+OffsetX-(i-1)
  end
  local indices = d.constant( "convKernel", idx, types.array2d( types.uint(8), SearchWindow ) ) -- uint8[SearchWindow]

  local sadout = d.apply("sadvalues", d.map( C.SAD( A, types.uint(16), SADWidth ), SearchWindow), inp ) -- uint16[SearchWindow]
  local packed = d.apply("SOS", d.SoAtoAoS( SearchWindow, 1, {types.uint(8), types.uint(16)} ), d.tuple("stup",{indices, sadout}) )
  local AM = C.argmin(types.uint(8),types.uint(16))
  local out = d.apply("argmin", d.reduce(AM,SearchWindow,1),packed)

  return d.lambda("argmin", inp, out )
end

function make(filename)
  -- input is in the format A[2]. [left,right]. We need to break this up into 2 separate streams,
  -- linebuffer them differently, then put them back together and run argmin on them.
  -- 'left' means that the objects we're searching for are to the left of things in channel 'right', IN IMAGE SPACE.
  -- we only search to the left.

  -- full size is 720x405
  local W = 360
  local H = 203
  local SearchWindow = 64

  if filename=="tiny" then
    -- fast version for automated testing
    W,H = 256,16
    SearchWindow = 4
  elseif filename=="medi" then
    W,H = 352,200
    SearchWindow = 64
  else
    print("UNKNOWN FILENAME "..filename)
    assert(false)
  end

  local fifos = {}
  local statements = {}

  local ATYPE = types.array2d(A,2)
  local TYPE = types.array2d(ATYPE,4)
  local STENCIL_TYPE = types.array2d(A,SADWidth,SADWidth)
  local hsfninp = d.input( d.Handshake(TYPE) )
  local inp = d.apply("reducerate", d.liftHandshake(d.changeRate(types.array2d(A,2),1,4,1)), hsfninp ) -- A[2][1]
  local inp = d.apply("oi0", d.makeHandshake(d.index(types.array2d(types.array2d(A,2),1),0)), inp) -- A[2]
  local inp_broadcast = d.apply("inp_broadcast", d.broadcastStream(types.array2d(A,2),2), inp)

  -------------
  local left = d.apply("left", d.makeHandshake(d.index(types.array2d(A,2),0)), d.selectStream("i0",inp_broadcast,0) )
  
  -- theoretically, the left and right branch may have the same delay, so may not need a fifo.
  -- but, fifo one of the branches to be safe.
  table.insert( fifos, d.instantiateRegistered("f1",d.fifo(A,128)) )
  table.insert( statements, d.applyMethod("s1",fifos[1],"store",left) )
  left = d.applyMethod("l1",fifos[1],"load")

  local left = d.apply("AO",d.makeHandshake(C.arrayop(types.uint(8),1)),left)
  local left = d.apply( "LB", d.makeHandshake(d.stencilLinebuffer( types.uint(8), W, H, 1, -(SearchWindow+SADWidth+OffsetX)+2, 0, -SADWidth+1, 0 )), left)
  local left = d.apply( "lslice", d.makeHandshake(d.slice( types.array2d(types.uint(8),SearchWindow+SADWidth+OffsetX-1,SADWidth), 0, SearchWindow+SADWidth-2, 0, SADWidth-1)), left)
  left = d.apply( "llb", d.makeHandshake( d.unpackStencil( A, SADWidth, SADWidth, SearchWindow)  ), left) -- A[SADWidth,SADWidth][SearchWindow]

  --------
  local right = d.apply("right", d.makeHandshake( d.index(types.array2d(A,2),1)), d.selectStream("i1",inp_broadcast,1) )

  table.insert( fifos, d.instantiateRegistered("f2",d.fifo(A,128)) )
  table.insert( statements, d.applyMethod( "s2", fifos[2], "store", right ) )
  right = d.applyMethod("r1",fifos[#fifos],"load")

  local right = d.apply("AOr", d.makeHandshake( C.arrayop(types.uint(8),1)),right) -- uint8[1]
  local right = d.apply( "rightLB", d.makeHandshake( d.stencilLinebuffer( A, W, H, 1, -SADWidth+1, 0, -SADWidth+1, 0 )), right)
  right = d.apply("rb", d.makeHandshake(  d.broadcast( STENCIL_TYPE, SearchWindow )  ), right ) -- A[SADWidth,SADWidth][SearchWindow]
  -------

  local merged = d.apply("merge", d.SoAtoAoSHandshake( SearchWindow, 1, {STENCIL_TYPE,STENCIL_TYPE} ), d.tuple("mtup",{left,right},false)) -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]}[SearchWindow]
  local packStencils = d.SoAtoAoS( SADWidth, SADWidth, {A,A}, true )  -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]} to A[2][SADWidth,SADWidth]
  local merged = d.apply("mer", d.makeHandshake(d.map(packStencils, SearchWindow)  ), merged ) -- A[2][SADWidth, SADWidth][SearchWindow]
  
  local res = d.apply("AM",d.makeHandshake(argmin(SearchWindow)),merged) -- {uint8,uint16}
  local res = d.apply("display",d.makeHandshake(displayOutput()), res)

  local res = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,1,8)), res )

  res = d.apply( "border", d.makeHandshake(darkroom.borderSeq( types.uint(8), W, H, 8, SADWidth+SearchWindow+OffsetX-2, 0, SADWidth-1, 0, 0 )), res ) -- cut off the junk (undefined region)

  table.insert(statements,1,res)

  local hsfn = d.lambda( "hsfn", hsfninp, d.statements(statements), fifos )

--  local OUT_TYPE = types.array2d(types.tuple{types.uint(8),types.uint(16)},4)
  local OUT_TYPE = types.array2d(types.uint(8),8)
  -- output rate is half input rate, b/c we remove one channel.
  local outfile = "stereo_wide_handshake_"..filename
  harness.axi( outfile, hsfn,"stereo_"..filename..".raw",nil, nil,  TYPE,  4, W, H, OUT_TYPE, 8, W, H )

  io.output("out/"..outfile..".design.txt"); io.write("Stereo "..SearchWindow.." "..SADWidth.."x"..SADWidth); io.close()
  io.output("out/"..outfile..".designT.txt"); io.write(1); io.close()
end

make(string.sub(arg[0],#arg[0]-5,#arg[0]-2))
