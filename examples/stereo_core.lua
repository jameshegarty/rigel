local R = require "rigel"
local RM = require "generators.modules"
local types = require "types"
local S = require "systolic"
local C = require "generators.examplescommon"

local stereoCoreTerra
if terralib~=nil then stereoCoreTerra=require("stereo_core_terra") end

-- This function is used to select and format the output we want to display to the user
-- (either the index, or SAD value)
local function displayOutput(TRESH)
  assert(type(TRESH)=="number")
  local ITYPE = types.tuple{types.uint(8),types.uint(16)}
  local OTYPE = types.array2d(types.uint(8),1)

  return RM.lift("displayOutput",ITYPE, OTYPE, 0,
    function(inp)
      local out = S.cast(S.tuple{S.index(inp,0)},OTYPE)
      if TRESH~=0 then
        local reduceType = types.uint(16)
        out = S.cast(S.tuple{S.select(S.gt(S.index(inp,1),S.constant(TRESH,reduceType)),S.constant(0,types.uint(8)),S.index(inp,0))},OTYPE)
      end
      return out
    end,
    function() return stereoCoreTerra.displayOutput(ITYPE,TRESH) end)
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
  local inp = R.input( types.rv(types.Par(ITYPE)) )

  local idx = {}
  for i=1,SearchWindow do
    -- index gives us the distance to the right hand side of the window
    idx[i] = SearchWindow+OffsetX-(i-1)
  end
  local indices = R.constant( "convKernel", idx, types.array2d( types.uint(8), SearchWindow ) ) -- uint8[SearchWindow]

  local sadout = R.apply("sadvalues", RM.map( C.SAD( A, types.uint(16), SADWidth ), SearchWindow), inp ) -- uint16[SearchWindow]
  local packed = R.apply("SOS", C.SoAtoAoS( SearchWindow, 1, {types.uint(8), types.uint(16)} ), R.concat("stup",{indices, sadout}) )
  local AM = C.argmin(types.uint(8),types.uint(16))
  local out = R.apply("argmin", RM.reduce(AM,SearchWindow,1),packed)

  return RM.lambda("argmin", inp, out )
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
  local TYPE = types.array2d(ATYPE,4) -- read in 64 bits from axi bus (ie 4 L/R byte pairs)
  local STENCIL_TYPE = types.array2d(A,SADWidth,SADWidth)
  local hsfninp = R.input( R.Handshake(TYPE) )
  local LRTYPE = types.array2d(A,2)
  local inp = R.apply("reducerate", RM.changeRate(LRTYPE,1,4,1), hsfninp ) -- A[2][1] -- read 4 bytes from axi bus, but reduce this to 1 L/R pair per cycle

  local internalW, internalH = W+OffsetX+SearchWindow+SADWidth, H+SADWidth-1
  local inp = R.apply("pad", RM.liftHandshake(RM.padSeq(LRTYPE, W, H, 1, OffsetX+SearchWindow+SADWidth, 0, 3, 4, {0,0})), inp)
  local inp = R.apply("oi0", RM.makeHandshake(C.index(types.array2d(LRTYPE,1),0)), inp) -- A[2] -- just dig into the 1 element array
  local inp_broadcast = R.apply("inp_broadcast", RM.broadcastStream(types.Par(LRTYPE),2), inp) -- fan out

  -------------
  local left = R.apply("left", RM.makeHandshake(C.index(types.array2d(A,2),0)), R.selectStream("i0",inp_broadcast,0) )
  
  -- theoretically, the left and right branch may have the same delay, so may not need a fifo.
  -- but, fifo one of the branches to be safe.
  --table.insert( fifos, R.instantiateRegistered("f1",RM.fifo(A,128)) )
  --table.insert( statements, R.applyMethod("s1",fifos[1],"store",left) )
  --left = R.applyMethod("l1",fifos[1],"load")
  left = C.fifo(A,128)(left)

  local left = R.apply("AO",RM.makeHandshake(C.arrayop(types.uint(8),1)),left)
  local left = R.apply( "LB", RM.makeHandshake(C.stencilLinebuffer( types.uint(8), internalW, internalH, 1, -(SearchWindow+SADWidth+OffsetX)+2, 0, -SADWidth+1, 0 )), left)
  local left = R.apply( "lslice", RM.makeHandshake(C.slice( types.array2d(types.uint(8),SearchWindow+SADWidth+OffsetX-1,SADWidth), 0, SearchWindow+SADWidth-2, 0, SADWidth-1)), left)
  left = R.apply( "llb", RM.makeHandshake( C.unpackStencil( A, SADWidth, SADWidth, SearchWindow)  ), left) -- A[SADWidth,SADWidth][SearchWindow] -- build stencil of stencils

  --------
  local right = R.apply("right", RM.makeHandshake( C.index(types.array2d(A,2),1)), R.selectStream("i1",inp_broadcast,1) )

  --table.insert( fifos, R.instantiateRegistered("f2",RM.fifo(A,128)) )
  --table.insert( statements, R.applyMethod( "s2", fifos[2], "store", right ) )
  --right = R.applyMethod("r1",fifos[#fifos],"load")
  right = C.fifo(A,128)(right)

  local right = R.apply("AOr", RM.makeHandshake( C.arrayop(types.uint(8),1)),right) -- uint8[1]
  local right = R.apply( "rightLB", RM.makeHandshake( C.stencilLinebuffer( A, internalW, internalH, 1, -SADWidth+1, 0, -SADWidth+1, 0 )), right)
  right = R.apply("rb", RM.makeHandshake(  C.broadcast( STENCIL_TYPE, SearchWindow )  ), right ) -- A[SADWidth,SADWidth][SearchWindow]
  -------

  local merged = R.apply("merge", C.SoAtoAoSHandshake( SearchWindow, 1, {STENCIL_TYPE,STENCIL_TYPE} ), R.concat("mtup",{left,right})) -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]}[SearchWindow]
  local packStencils = C.SoAtoAoS( SADWidth, SADWidth, {A,A}, true )  -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]} to A[2][SADWidth,SADWidth]
  local merged = R.apply("mer", RM.makeHandshake(RM.map(packStencils, SearchWindow)  ), merged ) -- A[2][SADWidth, SADWidth][SearchWindow]
  
  local res = R.apply("AM",RM.makeHandshake(argmin(SearchWindow,SADWidth,OffsetX)),merged) -- {uint8,uint16}

  local res = R.apply("display",RM.makeHandshake(displayOutput(TRESH)), res)

  -- FIFO to improve timing
  if false then
  else
    local sz = 128
    if NOSTALL then sz = 2048 end
    --table.insert( fifos, R.instantiateRegistered("f_timing",RM.fifo(types.array2d(types.uint(8),1),sz,NOSTALL)) )
    --table.insert( statements, R.applyMethod( "s_timing", fifos[#fifos], "store", res ) )
    --res = R.applyMethod("r_timing",fifos[#fifos],"load")
    res = C.fifo(types.array2d(types.uint(8),1),sz,NOSTALL)(res)
  end

  res = R.apply("CRP", RM.liftHandshake(RM.liftDecimate(RM.cropSeq(types.uint(8), internalW, internalH, 1, OffsetX+SearchWindow+SADWidth,0,SADWidth-1,0))), res)
  local res = R.apply("incrate", RM.changeRate(types.uint(8),1,1,8), res )

  table.insert(statements,1,res)

  local hsfn = RM.lambda( "hsfn", hsfninp, R.statements(statements), fifos )

  return hsfn
end

return makeStereo
