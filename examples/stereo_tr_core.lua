local R = require "rigel"
local RM = require "generators.modules"
local C = require "generators.examplescommon"
local f = require "fixed"
local types = require "types"
local S = require "systolic"
local J = require "common"

local stereoTRCoreTerra
if terralib~=nil then stereoTRCoreTerra=require("stereo_tr_core_terra") end

-- we only display the found match if energy < threshold, or threshold==0 (no thresholding)
-- if threshold<0, then we only display if energy>-threshold
function displayOutput( reduceType, threshold )
  assert(type(threshold)=="number")

  local ITYPE = types.tuple{types.uint(8),reduceType}
  local OTYPE = types.array2d(types.uint(8),1)

  return RM.lift("displayOutput",ITYPE, OTYPE, 0,
    function(inp)
      local out = S.cast(S.tuple{S.index(inp,0)},OTYPE)
      if threshold~=0 then
        local cond
        if threshold>0 then
          cond = S.gt(S.index(inp,1),S.constant(threshold,reduceType))
        else
          cond = S.lt(S.index(inp,1),S.constant(-threshold,reduceType))
        end
        out = S.cast(S.tuple{S.select(cond,S.constant(0,types.uint(8)),S.index(inp,0))},OTYPE)
      end
      return out
    end,
    function() return stereoTRCoreTerra.displayOutput(ITYPE,threshold) end)
end

function displayOutputColor( reduceType, threshold )
  assert(type(threshold)=="number")

  local ITYPE = types.tuple{types.uint(8),reduceType}
  local OTYPE = types.array2d(types.array2d(types.uint(8),4),1)

  return RM.lift("displayOutput",ITYPE, OTYPE, 2,
    function(inp)
      local out = S.cast(S.index(inp,0),types.array2d(types.uint(8),4))
      out = S.cast(out,OTYPE)
      
      local zeroS = S.constant(0,types.uint(8))
      
      local colorOutputR = S.lshift(S.index(inp,0)-S.constant(60,types.uint(8)),S.constant(4,types.uint(8)))
      local colorOutputG = S.constant(128,types.uint(8))
      local colorOutputB = S.lshift(S.constant(16,types.uint(8))-(S.index(inp,0)-S.constant(60,types.uint(8))),S.constant(4,types.uint(8)))
      local colorOutput = S.cast(S.tuple{colorOutputR,colorOutputG,colorOutputB,zeroS}, types.array2d(types.uint(8),4))
      local colorOutput = S.cast(S.tuple{colorOutput},OTYPE)
      
      local zero = S.cast(S.tuple{zeroS,zeroS,zeroS,zeroS},types.array2d(types.uint(8),4))
      local zero = S.cast(S.tuple{zero},OTYPE)
      
      if threshold~=0 then
        local cond
        if threshold>0 then
          cond = S.gt(S.index(inp,1),S.constant(threshold,reduceType))
        else
          cond = S.lt(S.index(inp,1),S.constant(-threshold,reduceType))
        end
        out = S.select(cond,zero,colorOutput)
      end
      return out
    end,
    function() return stereoTRCoreTerra.displayOutputColor(ITYPE,threshold) end)
end

-- perCycleSearch = (SearchWindow*T)
-- argmin expects type Stateful(A[2][SADWidth,SADWidth][perCycleSearch])->StatefulV
-- which corresponds to [leftEye,rightEye]. rightEye should be the same window 'perCycleSearch' times. leftEye has the windows we're searching for the match in.
-- returns: Handshake{index,SADvalu@index} (valid every T cycles)
function argmin(A, T, SearchWindow, SADWidth, OffsetX, reduceType, RGBA)
  assert(types.isType(A))
  assert(type(T)=="number")
  assert(T<=1)
  assert(type(SearchWindow)=="number")
  f.expectFixed(reduceType)
  assert(type(RGBA)=="boolean")

  local perCycleSearch = (SearchWindow*T)

  local ITYPE = types.array2d(types.array2d(types.array2d(A,2),SADWidth,SADWidth),perCycleSearch)
  local inp = R.input( types.rv(types.Par(ITYPE)) )

  local idx = {}
  for i=1,SearchWindow do
    -- index gives us the distance to the right hand side of the window
    idx[i] = SearchWindow+OffsetX-(i-1)
  end

  local indices = R.apply( "convKernel", RM.constSeq( idx, types.uint(8), SearchWindow, 1, 1/T ) ) -- uint8[perCycleSearch]

  -------
  local LOWER_SUM_INP = f.parameter("LOWER_SUM_INP", reduceType)
  local LOWER_SUM = LOWER_SUM_INP:lower():disablePipelining()
  -------

  local sadout
  if RGBA then
    sadout = R.apply("sadvalues", RM.map(C.SADFixed4( A, reduceType, SADWidth ),perCycleSearch), inp ) -- uint16[perCycleSearch]
  else
    sadout = R.apply("sadvalues", RM.map(C.SADFixed( A, reduceType, SADWidth ),perCycleSearch), inp ) -- uint16[perCycleSearch]
  end

  sadout = R.apply("LOWER_SUM", RM.map(LOWER_SUM:toRigelModule("LowerSum"),perCycleSearch), sadout)
  local packed = R.apply("SOS", C.SoAtoAoS( perCycleSearch, 1, {types.uint(8), LOWER_SUM.type} ), R.concat("stup",{indices, sadout}) )

  local AM = C.argmin(types.uint(8),LOWER_SUM.type)
  local AM_async = C.argmin(types.uint(8),LOWER_SUM.type,true)
  local out = R.apply("argmin", RM.reduce(AM,perCycleSearch,1),packed)
  out = R.apply("argminseq", RM.reduceSeq(AM_async,1/T), out)

  return RM.lambda("argmin", inp, out )
end

-- errorThreshold: if the SAD energy is above this, display 0.
-- if errorThreshold==0, do no thresholding
function makeStereo( T, W, H, A, SearchWindow, SADWidth, OffsetX, reducePrecision, errorThreshold, COLOR_OUTPUT, RGBA )
  assert(type(OffsetX)=="number")
  assert(type(SADWidth)=="number")
  assert(type(COLOR_OUTPUT)=="boolean")
  assert(type(RGBA)=="boolean")

  -- input is in the format A[2]. [left,right]. We need to break this up into 2 separate streams,
  -- linebuffer them differently, then put them back together and run argmin on them.
  -- 'left' means that the objects we're searching for are to the left of things in channel 'right', IN IMAGE SPACE.
  -- we only search to the left.

  local perCycleSearch = (SearchWindow*T)

  local fifos = {}
  local statements = {}

  local ATYPE = types.array2d(A,2)
  local TYPE = types.array2d(ATYPE,J.sel(RGBA,1,4))
  local STENCIL_TYPE = types.array2d(A,SADWidth,SADWidth)
  local hsfninp = R.input( R.Handshake(TYPE) )
  local LRTYPE = types.array2d(A,2)
  local inp
  if RGBA then
    inp = hsfninp
  else
    inp = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.array2d(A,2),1,4,1)), hsfninp )
  end

  local internalW, internalH = W+OffsetX+SearchWindow, H+SADWidth-1
  local inp = R.apply("pad", RM.liftHandshake(RM.padSeq(LRTYPE, W, H, 1, OffsetX+SearchWindow, 0, SADWidth/2-1, SADWidth/2, J.sel(RGBA,{{0,0,0,0},{0,0,0,0}},{0,0}) )), inp)
  local inp = R.apply("oi0", RM.makeHandshake(C.index(types.array2d(types.array2d(A,2),1),0)), inp) -- A[2]
  local inp_broadcast = R.apply("inp_broadcast", RM.broadcastStream(types.Par(types.array2d(A,2)),2), inp)

  -------------
  local left = R.apply("left", RM.makeHandshake(C.index(types.array2d(A,2),0)), R.selectStream("i0",inp_broadcast,0))
  
  -- theoretically, the left and right branch may have the same delay, so may not need a fifo.
  -- but, fifo one of the branches to be safe.
  --table.insert( fifos, R.instantiateRegistered("f1",RM.fifo(A,128)) )
  --table.insert( statements, R.applyMethod("s1",fifos[1],"store",left) )
  --left = R.applyMethod("l1",fifos[1],"load")
  left = C.fifo(A,128)(left)

  local left = R.apply("AO",RM.makeHandshake(C.arrayop(A,1)),left)
  local left = R.apply("LB", C.stencilLinebufferPartialOffsetOverlap( A, internalW, internalH, 1/T, -(SearchWindow+SADWidth+OffsetX)+2, 0, -SADWidth+1, 0, OffsetX, SADWidth-1), left )
  local left = R.apply( "llb", RM.makeHandshake(C.unpackStencil( A, SADWidth, SADWidth, perCycleSearch)), left) -- A[SADWidth,SADWidth][PCS]

  --------
  local right = R.apply("right", RM.makeHandshake(C.index(types.array2d(A,2),1)), R.selectStream("i1",inp_broadcast,1))
  
  -- theoretically, the left and right branch may have the same delay, so may not need a fifo.
  -- but, fifo one of the branches to be safe.
  --table.insert( fifos, R.instantiateRegistered("f2",RM.fifo(A,128)) )
  --table.insert( statements, R.applyMethod("s2",fifos[#fifos],"store",right) )
  --right = R.applyMethod("l12",fifos[#fifos],"load")
  right = C.fifo(A,128)(right)

  local right = R.apply("AOr", RM.makeHandshake(C.arrayop(A,1)),right) -- uint8[1]
  local right = R.apply( "rightLB", RM.makeHandshake( C.stencilLinebuffer( A, internalW, internalH, 1, -SADWidth+1, 0, -SADWidth+1, 0 ) ), right)

  right = R.apply("rAO",RM.makeHandshake(C.arrayop(STENCIL_TYPE,1)),right)
  right = R.apply( "rup", RM.upsampleXSeq(STENCIL_TYPE,1,1/T), right)

  right = R.apply("right2", RM.makeHandshake(C.index(types.array2d(STENCIL_TYPE,1),0)), right)
  right = R.apply("rb2", RM.makeHandshake(C.broadcast( STENCIL_TYPE, perCycleSearch ) ), right ) -- A[SADWidth,SADWidth][PCS]

  -------

  local merged = R.apply("merge", C.SoAtoAoSHandshake( perCycleSearch, 1, {STENCIL_TYPE,STENCIL_TYPE} ), R.concat("mtup",{left,right})) -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]}[PCS]
  local packStencils = C.SoAtoAoS( SADWidth, SADWidth, {A,A}, true )  -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]} to A[2][SADWidth,SADWidth]
  local merged = R.apply("mer", RM.makeHandshake( RM.map(packStencils, perCycleSearch) ), merged ) -- A[2][SADWidth, SADWidth][perCycleSearch]
  
  local res = R.apply("AM",RM.liftHandshake(RM.liftDecimate(argmin(A,T,SearchWindow,SADWidth,OffsetX,f.type(false,reducePrecision,0),RGBA))),merged)

  -- this FIFO is only for improving timing
  local argminType = types.tuple{types.uint(8),types.uint(reducePrecision)}
  --table.insert( fifos, R.instantiateRegistered("f3",RM.fifo(argminType,128)) )
  --table.insert( statements, R.applyMethod("s3",fifos[#fifos],"store",res) )
  --res = R.applyMethod("l13",fifos[#fifos],"load")
  res = C.fifo(argminType,128)(res)



  local OUTPUT_TYPE = types.uint(8)
  local OUTPUT_T = 8
  if COLOR_OUTPUT then 
    OUTPUT_TYPE = types.array2d(types.uint(8),4) 
    OUTPUT_T = 2
    res = R.apply("display",RM.makeHandshake( displayOutputColor(types.uint(reducePrecision),errorThreshold,COLOR_OUTPUT) ), res)
  else
    res = R.apply("display",RM.makeHandshake( displayOutput(types.uint(reducePrecision),errorThreshold,COLOR_OUTPUT) ), res)
  end

  res = R.apply("CRP", RM.liftHandshake(RM.liftDecimate(RM.cropSeq(OUTPUT_TYPE, internalW, internalH, 1, OffsetX+SearchWindow,0,SADWidth-1,0))), res)

  local res = R.apply("incrate", RM.liftHandshake(RM.changeRate(OUTPUT_TYPE,1,1,OUTPUT_T)), res )

  table.insert(statements,1,res)

  local hsfn = RM.lambda( "hsfn", hsfninp, R.statements(statements), fifos )
  return hsfn
end

return makeStereo
