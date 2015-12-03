local d = require "darkroom"
local C = require "examplescommon"

-- This function is used to select and format the output we want to display to the user
-- (either the index, or SAD value)
local function displayOutput(TRESH)
  assert(type(TRESH)=="number")
  local ITYPE = types.tuple{types.uint(8),types.uint(16)}
  local OTYPE = types.array2d(types.uint(8),1)
  local inp = S.parameter( "inp", ITYPE )

  local out = S.cast(S.tuple{S.index(inp,0)},OTYPE)
  if TRESH~=0 then
    local reduceType = types.uint(16)
    out = S.cast(S.tuple{S.select(S.gt(S.index(inp,1),S.constant(TRESH,reduceType)),S.constant(0,types.uint(8)),S.index(inp,0))},OTYPE)
  end

  return d.lift("displayOutput",ITYPE, OTYPE, 0,
                terra(a:&ITYPE:toTerraType(), out:&uint8[1])
                  @out = array(a._0)
                  if TRESH~=0 and a._1>TRESH then @out = array([uint8](0)) end
                end, inp, 
                out
)
end

-- argmin expects type Stateful(A[2][SADWidth,SADWidth][SearchWindow])->StatefulV
-- which corresponds to [leftEye,rightEye]. rightEye should be the same window 'perCycleSearch' times. leftEye has the windows we're searching for the match in.
-- returns: Handshake{index,SADvalu@index} (valid every T cycles)
local function argmin( SearchWindow, SADWidth, OffsetX, X)
  assert(type(SearchWindow)=="number")
  assert(type(SADWidth)=="number")
  assert(type(OffsetX)=="number")
  assert(X==nil)

  local A = types.uint(8)
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

local function makeStereo(W,H,OffsetX,SearchWindow,SADWidth,NOSTALL,TRESH,X)
  assert(type(W)=="number")
  assert(type(SADWidth)=="number")
  assert(type(NOSTALL)=="boolean")
  assert(type(TRESH)=="number")
  assert(X==nil)

  local fifos = {}
  local statements = {}

  local A = types.uint(8)

  local ATYPE = types.array2d(A,2)
  local TYPE = types.array2d(ATYPE,4)
  local STENCIL_TYPE = types.array2d(A,SADWidth,SADWidth)
  local hsfninp = d.input( d.Handshake(TYPE) )
  local LRTYPE = types.array2d(A,2)
  local inp = d.apply("reducerate", d.liftHandshake(d.changeRate(LRTYPE,1,4,1)), hsfninp ) -- A[2][1]

  local internalW, internalH = W+OffsetX+SearchWindow, H+SADWidth-1
  local inp = d.apply("pad", d.liftHandshake(d.padSeq(LRTYPE, W, H, 1, OffsetX+SearchWindow, 0, 3, 4, {0,0})), inp)
  local inp = d.apply("oi0", d.makeHandshake(d.index(types.array2d(LRTYPE,1),0)), inp) -- A[2]
  local inp_broadcast = d.apply("inp_broadcast", d.broadcastStream(LRTYPE,2), inp)

  -------------
  local left = d.apply("left", d.makeHandshake(d.index(types.array2d(A,2),0)), d.selectStream("i0",inp_broadcast,0) )
  
  -- theoretically, the left and right branch may have the same delay, so may not need a fifo.
  -- but, fifo one of the branches to be safe.
  table.insert( fifos, d.instantiateRegistered("f1",d.fifo(A,128)) )
  table.insert( statements, d.applyMethod("s1",fifos[1],"store",left) )
  left = d.applyMethod("l1",fifos[1],"load")

  local left = d.apply("AO",d.makeHandshake(C.arrayop(types.uint(8),1)),left)
  local left = d.apply( "LB", d.makeHandshake(d.stencilLinebuffer( types.uint(8), internalW, internalH, 1, -(SearchWindow+SADWidth+OffsetX)+2, 0, -SADWidth+1, 0 )), left)
  local left = d.apply( "lslice", d.makeHandshake(d.slice( types.array2d(types.uint(8),SearchWindow+SADWidth+OffsetX-1,SADWidth), 0, SearchWindow+SADWidth-2, 0, SADWidth-1)), left)
  left = d.apply( "llb", d.makeHandshake( d.unpackStencil( A, SADWidth, SADWidth, SearchWindow)  ), left) -- A[SADWidth,SADWidth][SearchWindow]

  --------
  local right = d.apply("right", d.makeHandshake( d.index(types.array2d(A,2),1)), d.selectStream("i1",inp_broadcast,1) )

  table.insert( fifos, d.instantiateRegistered("f2",d.fifo(A,128)) )
  table.insert( statements, d.applyMethod( "s2", fifos[2], "store", right ) )
  right = d.applyMethod("r1",fifos[#fifos],"load")

  local right = d.apply("AOr", d.makeHandshake( C.arrayop(types.uint(8),1)),right) -- uint8[1]
  local right = d.apply( "rightLB", d.makeHandshake( d.stencilLinebuffer( A, internalW, internalH, 1, -SADWidth+1, 0, -SADWidth+1, 0 )), right)
  right = d.apply("rb", d.makeHandshake(  d.broadcast( STENCIL_TYPE, SearchWindow )  ), right ) -- A[SADWidth,SADWidth][SearchWindow]
  -------

  local merged = d.apply("merge", d.SoAtoAoSHandshake( SearchWindow, 1, {STENCIL_TYPE,STENCIL_TYPE} ), d.tuple("mtup",{left,right},false)) -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]}[SearchWindow]
  local packStencils = d.SoAtoAoS( SADWidth, SADWidth, {A,A}, true )  -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]} to A[2][SADWidth,SADWidth]
  local merged = d.apply("mer", d.makeHandshake(d.map(packStencils, SearchWindow)  ), merged ) -- A[2][SADWidth, SADWidth][SearchWindow]
  
  local res = d.apply("AM",d.makeHandshake(argmin(SearchWindow,SADWidth,OffsetX)),merged) -- {uint8,uint16}

  local res = d.apply("display",d.makeHandshake(displayOutput(TRESH)), res)

  -- FIFO to improve timing
  if false then
  else
    local sz = 128
    if NOSTALL then sz = 2048 end
    table.insert( fifos, d.instantiateRegistered("f_timing",d.fifo(types.array2d(types.uint(8),1),sz,NOSTALL)) )
    table.insert( statements, d.applyMethod( "s_timing", fifos[#fifos], "store", res ) )
    res = d.applyMethod("r_timing",fifos[#fifos],"load")
  end

  res = d.apply("CRP", d.liftHandshake(d.liftDecimate(d.cropSeq(types.uint(8), internalW, internalH, 1, OffsetX+SearchWindow,0,SADWidth-1,0))), res)
  local res = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,1,8)), res )

  --res = d.apply( "border", d.makeHandshake(darkroom.borderSeq( types.uint(8), W, H, 8, SADWidth+SearchWindow+OffsetX-2, 0, SADWidth-1, 0, 0 )), res ) -- cut off the junk (undefined region)

  table.insert(statements,1,res)

  local hsfn = d.lambda( "hsfn", hsfninp, d.statements(statements), fifos )

  return hsfn
end

return makeStereo