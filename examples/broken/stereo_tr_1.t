local d = require "darkroom"
local C = require "examplescommon"

local W = 720
local H = 405
--local SADRadius = 4
local SADWidth = 8
local SearchWindow = 64
local A = types.uint(8)

-- perCycleSearch = (SearchWindow*T)
-- argmin expects type Stateful(A[2][SADWidth,SADWidth][perCycleSearch])->StatefulV
-- which corresponds to [leftEye,rightEye]. rightEye should be the same window 'perCycleSearch' times. leftEye has the windows we're searching for the match in.
-- returns: Handshake{index,SADvalu@index} (valid every T cycles)
function argmin(T)
  local perCycleSearch = (SearchWindow*T)

  local ITYPE = types.array2d(types.array2d(types.array2d(A,2),SADWidth,SADWidth),perCycleSearch)
  local inp = d.input( d.Stateful(ITYPE) )

  local indices = d.apply( "convKernel", d.constSeq( range(SearchWindow), types.uint(8), SearchWindow, 1, T ), d.extractState("inext", inp) ) -- uint8[perCycleSearch]

  local sadout = d.apply("sadvalues", d.makeStateful(d.map(C.SAD( A, types.uint(16), SADWidth ),perCycleSearch)), inp ) -- uint16[perCycleSearch]
  local packed = d.apply("SOS", d.SoAtoAoSStateful( perCycleSearch, 1, {types.uint(8), types.uint(16)} ), d.tuple("stup",{indices, sadout}) )
  local AM = C.argmin(types.uint(8),types.uint(16))
  local AM_async = C.argmin(types.uint(8),types.uint(16),true)
  local out = d.apply("argmin", d.makeStateful(d.reduce(AM,perCycleSearch,1)),packed)
  out = d.apply("argminseq", d.reduceSeq(AM_async,T), out)

  return d.lambda("argmin", inp, out )
end

function make(T)
  -- input is in the format A[2]. [left,right]. We need to break this up into 2 separate streams,
  -- linebuffer them differently, then put them back together and run argmin on them.
  -- 'left' means that the objects we're searching for are to the left of things in channel 'right', IN IMAGE SPACE.
  -- we only search to the left.

  local perCycleSearch = (SearchWindow*T)

  local fifos = {}
  local statements = {}

  local ATYPE = types.array2d(A,2)
  local TYPE = types.array2d(ATYPE,4)
  local STENCIL_TYPE = types.array2d(A,SADWidth,SADWidth)
  local hsfninp = d.input( d.StatefulHandshake(TYPE) )
  local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.array2d(A,2),1,4,1)), hsfninp )
  
  -------------
  local left = d.apply("left", d.makeHandshake(d.makeStateful(d.index(types.array2d(A,2),0))), out)
  
  -- theoretically, the left and right branch may have the same delay, so may not need a fifo.
  -- but, fifo one of the branches to be safe.
  table.insert( fifos, d.instantiateRegistered("f1",d.fifo(A,128)) )
  table.insert( statements, d.applyMethod("s1",fifos[1],"store",left) )
  left = d.applyMethod("l1",fifos[1],"load")

  local left = d.apply("AO",d.makeHandshake(d.makeStateful(C.arrayop(types.uint(8),1))),left)
  local left = d.apply( "LB", d.stencilLinebufferPartial( types.uint(8), W, H, T, -(SearchWindow+SADWidth)+1, 0, -SADWidth+1, 0 ), left)
  left = d.apply( "llb", d.unpackStencil( A, SADWidth, SADWidth, perCycleSearch), left) -- A[SADWidth,SADWidth][PCS]

  --------
  local right = d.apply("right", d.makeHandshake(d.makeStateful(d.index(types.array2d(A,2),1))), out)
  local right = d.apply( "rightLB", d.stencilLinebuffer( A, W, H, 1, -SADWidth+1, 0, -SADWidth+1, 0 ), right)
  right = d.apply("rb", d.broadcast(A,perCycleSearch), right ) -- A[SADWidth,SADWidth][PCS]
  -------

  local merged = d.apply("merge", d.SoAtoAoSStateful( perCycleSearch, 1, {STENCIL_TYPE,STENCIL_TYPE}, true ), d.tuple("mtup",{left,right})) -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]}[PCS]
  local packStencils = d.SoAtoAoS( SADWidth, SADWidth, {A,A}, true )  -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]} to A[2][SADWidth,SADWidth]
  local merged = d.apply("mer", d.map(packStencils, perCycleSearch), merged ) -- A[2][SADWidth, SADWidth][perCycleSearch]
  
  local res = d.apply("AM",argmin(T),merged)
  table.insert(statements,1,res)

  return d.lambda( "hsfn", hsfninp, d.statements(statements), fifos )
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
make(tonumber(1/t))
