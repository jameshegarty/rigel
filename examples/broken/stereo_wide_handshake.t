local d = require "darkroom"
local C = require "examplescommon"
local harness = require "harness"

-- full size is 720x405
local W = 360
local H = 203
--local SADRadius = 4
local SADWidth = 8
local SearchWindow = 64
local OffsetX = 20 -- we search the range [-OffsetX-SearchWindow, -OffsetX]
local A = types.uint(8)

-- argmin expects type Stateful(A[2][SADWidth,SADWidth][SearchWindow])->StatefulV
-- which corresponds to [leftEye,rightEye]. rightEye should be the same window 'perCycleSearch' times. leftEye has the windows we're searching for the match in.
-- returns: Handshake{index,SADvalu@index} (valid every T cycles)
function argmin()
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

function make()
  -- input is in the format A[2]. [left,right]. We need to break this up into 2 separate streams,
  -- linebuffer them differently, then put them back together and run argmin on them.
  -- 'left' means that the objects we're searching for are to the left of things in channel 'right', IN IMAGE SPACE.
  -- we only search to the left.

  local fifos = {}
  local statements = {}

  local ATYPE = types.array2d(A,2)
  local TYPE = types.array2d(ATYPE,4)
  local STENCIL_TYPE = types.array2d(A,SADWidth,SADWidth)
  local hsfninp = d.input( d.StatefulHandshake(TYPE) )
  local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.array2d(A,2),1,4,1)), hsfninp ) -- A[2][1]
  local out = d.apply("oi0", d.makeHandshake(d.makeStateful(d.index(types.array2d(types.array2d(A,2),1),0))), out) -- A[2]

  -------------
  local left = d.apply("left", d.makeHandshake(d.makeStateful(d.index(types.array2d(A,2),0))), out)
  
  -- theoretically, the left and right branch may have the same delay, so may not need a fifo.
  -- but, fifo one of the branches to be safe.
  table.insert( fifos, d.instantiateRegistered("f1",d.fifo(A,128)) )
  table.insert( statements, d.applyMethod("s1",fifos[1],"store",left) )
  left = d.applyMethod("l1",fifos[1],"load")

  local left = d.apply("AO",d.makeHandshake(d.makeStateful(C.arrayop(types.uint(8),1))),left)
  local left = d.apply( "LB", d.makeHandshake(d.stencilLinebuffer( types.uint(8), W, H, 1, -(SearchWindow+SADWidth+OffsetX)+2, 0, -SADWidth+1, 0 )), left)
  local left = d.apply( "lslice", d.makeHandshake(d.makeStateful(d.slice( types.array2d(types.uint(8),SearchWindow+SADWidth+OffsetX-1,SADWidth), 0, SearchWindow+SADWidth-2, 0, SADWidth-1))), left)
  left = d.apply( "llb", d.makeHandshake( d.makeStateful( d.unpackStencil( A, SADWidth, SADWidth, SearchWindow) ) ), left) -- A[SADWidth,SADWidth][SearchWindow]

  --------
  local right = d.apply("right", d.makeHandshake( d.makeStateful(d.index(types.array2d(A,2),1))), out)

--  table.insert( fifos, d.instantiateRegistered("f2",d.fifo(A,128)) )
--  table.insert( statements, d.applyMethod( "s2", fifos[2], "store", right ) )
--  right = d.applyMethod("r1",fifos[#fifos],"load")

  local right = d.apply("AOr", d.makeHandshake( d.makeStateful(C.arrayop(types.uint(8),1))),right) -- uint8[1]
  local right = d.apply( "rightLB", d.makeHandshake( d.stencilLinebuffer( A, W, H, 1, -SADWidth+1, 0, -SADWidth+1, 0 )), right)
  right = d.apply("rb", d.makeHandshake( d.makeStateful( d.broadcast( STENCIL_TYPE, SearchWindow ) ) ), right ) -- A[SADWidth,SADWidth][SearchWindow]
  -------

  local merged = d.apply("merge", d.SoAtoAoSStateful( SearchWindow, 1, {STENCIL_TYPE,STENCIL_TYPE}, true ), d.tuple("mtup",{left,right},false)) -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]}[SearchWindow]
  local packStencils = d.SoAtoAoS( SADWidth, SADWidth, {A,A}, true )  -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]} to A[2][SADWidth,SADWidth]
  local merged = d.apply("mer", d.makeHandshake(d.makeStateful(d.map(packStencils, SearchWindow) ) ), merged ) -- A[2][SADWidth, SADWidth][SearchWindow]
  
  local res = d.apply("AM",d.makeHandshake(d.makeStateful(argmin())),merged) -- {uint8,uint16}
  local res = d.apply("ami",d.makeHandshake(d.makeStateful(d.index(types.tuple{types.uint(8),types.uint(16)},0))),res) -- uint8
  local res = d.apply("amiAOr", d.makeHandshake( d.makeStateful(C.arrayop(types.uint(8),1))),res) -- uint8[1]
  local res = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,1,8)), res )

  table.insert(statements,1,res)


  local hsfn = d.lambda( "hsfn", hsfninp, d.statements(statements), fifos )

--  local OUT_TYPE = types.array2d(types.tuple{types.uint(8),types.uint(16)},4)
  local OUT_TYPE = types.array2d(types.uint(8),8)
  -- output rate is half input rate, b/c we remove one channel.
  harness.axi( "stereo_wide_handshake", hsfn,"stereo_half.raw",nil, nil,  TYPE,  4, W, H, OUT_TYPE, 8, W, H )
end

make()
