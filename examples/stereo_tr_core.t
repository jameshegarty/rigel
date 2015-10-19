local d = require "darkroom"
local C = require "examplescommon"
local f = require "fixed"

function stencilLinebufferPartialOffsetOverlap( A, w, h, T, xmin, xmax, ymin, ymax, offset, overlap )
  map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T<=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  local ST_W = -xmin+1
  local ssr_region = ST_W - offset - overlap
  local stride = ssr_region*T
  assert(stride==math.floor(stride))

  local LB = darkroom.makeHandshake(darkroom.linebuffer( A, w, h, 1, ymin ))
  local SSR = darkroom.liftHandshake(darkroom.waitOnInput(darkroom.SSRPartial( A, T, xmin, ymin, stride, true )))

  local inp = d.input( LB.inputType )
  local out = d.apply("LB", LB, inp)
  out = d.apply("SSR", SSR, out)
  out = d.apply("slice", d.makeHandshake(d.slice(types.array2d(types.uint(8),ST_W,-ymin+1), 0, stride+overlap-1, 0,-ymin)), out)

  return d.lambda("stencilLinebufferPartialOverlap",inp,out)
  -- SSRPartial need to be able to stall the linebuffer, so we must do this with handshake interfaces. Systolic pipelines can't stall each other
  --return darkroom.compose("stencilLinebufferPartialOffsetOverlap", darkroom.liftHandshake(darkroom.waitOnInput(darkroom.SSRPartial( A, T, xmin, ymin ))),  )
end

-- we only display the found match if energy < threshold, or threshold==0 (no thresholding)
function displayOutput( reduceType, threshold )
  assert(type(threshold)=="number")

  local ITYPE = types.tuple{types.uint(8),reduceType}
  local OTYPE = types.array2d(types.uint(8),1)
  local inp = S.parameter( "inp", ITYPE )
  return d.lift("displayOutput",ITYPE, OTYPE, 0,
                terra(a:&ITYPE:toTerraType(), out:&uint8[1])
                  if a._1<threshold or threshold==0 then
                    @out = array(a._0)
                  else
                    @out = array([uint8](0))
                  end

--                  @out = array([uint8](a._1))
                end, inp, 
                S.cast(S.tuple{S.index(inp,0)},OTYPE) 
                --S.cast(S.tuple{S.cast(S.index(inp,1),types.uint(8))},OTYPE) 
)
end

-- perCycleSearch = (SearchWindow*T)
-- argmin expects type Stateful(A[2][SADWidth,SADWidth][perCycleSearch])->StatefulV
-- which corresponds to [leftEye,rightEye]. rightEye should be the same window 'perCycleSearch' times. leftEye has the windows we're searching for the match in.
-- returns: Handshake{index,SADvalu@index} (valid every T cycles)
function argmin(A, T, SearchWindow, SADWidth, OffsetX, reduceType)
  assert(types.isType(A))
  assert(type(T)=="number")
  assert(T<=1)
  assert(type(SearchWindow)=="number")
  f.expectFixed(reduceType)

  local perCycleSearch = (SearchWindow*T)

  local ITYPE = types.array2d(types.array2d(types.array2d(A,2),SADWidth,SADWidth),perCycleSearch)
  local inp = d.input( ITYPE )

  local idx = {}
  for i=1,SearchWindow do
    -- index gives us the distance to the right hand side of the window
    idx[i] = SearchWindow+OffsetX-(i-1)
  end

  local indices = d.apply( "convKernel", d.constSeq( idx, types.uint(8), SearchWindow, 1, T ) ) -- uint8[perCycleSearch]

  -------
  local LOWER_SUM_INP = f.parameter("LOWER_SUM_INP", reduceType)
  local LOWER_SUM = LOWER_SUM_INP:lower()
  -------

  local sadout = d.apply("sadvalues", d.map(C.SADFixed( A, reduceType, SADWidth ),perCycleSearch), inp ) -- uint16[perCycleSearch]
  sadout = d.apply("LOWER_SUM", d.map(LOWER_SUM:toDarkroom("LowerSum"),perCycleSearch), sadout)
  local packed = d.apply("SOS", d.SoAtoAoS( perCycleSearch, 1, {types.uint(8), LOWER_SUM.type} ), d.tuple("stup",{indices, sadout}) )



  local AM = C.argmin(types.uint(8),LOWER_SUM.type)
  local AM_async = C.argmin(types.uint(8),LOWER_SUM.type,true)
  local out = d.apply("argmin", d.reduce(AM,perCycleSearch,1),packed)
  out = d.apply("argminseq", d.reduceSeq(AM_async,T), out)

  return d.lambda("argmin", inp, out )
end

-- errorThreshold: if the SAD energy is above this, display 0.
-- if errorThreshold==0, do no thresholding
function makeStereo( filename, T, W, H, A, SearchWindow, SADWidth, OffsetX, reducePrecision, errorThreshold )
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
  local hsfninp = d.input( d.Handshake(TYPE) )
  local inp = d.apply("reducerate", d.liftHandshake(d.changeRate(types.array2d(A,2),1,4,1)), hsfninp )
  local inp = d.apply("oi0", d.makeHandshake(d.index(types.array2d(types.array2d(A,2),1),0)), inp) -- A[2]
  local inp_broadcast = d.apply("inp_broadcast", d.broadcastStream(types.array2d(A,2),2), inp)

  -------------
  local left = d.apply("left", d.makeHandshake(d.index(types.array2d(A,2),0)), d.selectStream("i0",inp_broadcast,0))
  
  -- theoretically, the left and right branch may have the same delay, so may not need a fifo.
  -- but, fifo one of the branches to be safe.
  table.insert( fifos, d.instantiateRegistered("f1",d.fifo(A,128)) )
  table.insert( statements, d.applyMethod("s1",fifos[1],"store",left) )
  left = d.applyMethod("l1",fifos[1],"load")

  local left = d.apply("AO",d.makeHandshake(C.arrayop(types.uint(8),1)),left)
  local left = d.apply("LB", stencilLinebufferPartialOffsetOverlap( types.uint(8), W, H, T, -(SearchWindow+SADWidth+OffsetX)+2, 0, -SADWidth+1, 0, OffsetX, SADWidth-1), left )
  local left = d.apply( "llb", d.makeHandshake(d.unpackStencil( A, SADWidth, SADWidth, perCycleSearch)), left) -- A[SADWidth,SADWidth][PCS]

  --------
  local right = d.apply("right", d.makeHandshake(d.index(types.array2d(A,2),1)), d.selectStream("i1",inp_broadcast,1))
  
  -- theoretically, the left and right branch may have the same delay, so may not need a fifo.
  -- but, fifo one of the branches to be safe.
  table.insert( fifos, d.instantiateRegistered("f2",d.fifo(A,128)) )
  table.insert( statements, d.applyMethod("s2",fifos[#fifos],"store",right) )
  right = d.applyMethod("l12",fifos[#fifos],"load")

  local right = d.apply("AOr", d.makeHandshake(C.arrayop(types.uint(8),1)),right) -- uint8[1]
  local right = d.apply( "rightLB", d.makeHandshake( d.stencilLinebuffer( A, W, H, 1, -SADWidth+1, 0, -SADWidth+1, 0 ) ), right)

  right = d.apply("rAO",d.makeHandshake(C.arrayop(STENCIL_TYPE,1)),right)
  right = d.apply( "rup", d.upsampleXSeq(STENCIL_TYPE,1,1/T), right)

  right = d.apply("right2", d.makeHandshake(d.index(types.array2d(STENCIL_TYPE,1),0)), right)
  right = d.apply("rb2", d.makeHandshake(d.broadcast( STENCIL_TYPE, perCycleSearch ) ), right ) -- A[SADWidth,SADWidth][PCS]

  -------

  local merged = d.apply("merge", d.SoAtoAoSHandshake( perCycleSearch, 1, {STENCIL_TYPE,STENCIL_TYPE} ), d.tuple("mtup",{left,right},false)) -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]}[PCS]
  local packStencils = d.SoAtoAoS( SADWidth, SADWidth, {A,A}, true )  -- {A[SADWidth,SADWidth],A[SADWidth,SADWidth]} to A[2][SADWidth,SADWidth]
  local merged = d.apply("mer", d.makeHandshake( d.map(packStencils, perCycleSearch) ), merged ) -- A[2][SADWidth, SADWidth][perCycleSearch]
  
  local res = d.apply("AM",d.liftHandshake(d.liftDecimate(argmin(A,T,SearchWindow,SADWidth,OffsetX,f.type(false,reducePrecision,0)))),merged)

  -- this FIFO is only for improving timing
  local argminType = types.tuple{types.uint(8),types.uint(reducePrecision)}
  table.insert( fifos, d.instantiateRegistered("f3",d.fifo(argminType,128)) )
  table.insert( statements, d.applyMethod("s3",fifos[#fifos],"store",res) )
  res = d.applyMethod("l13",fifos[#fifos],"load")

  local res = d.apply("display",d.makeHandshake( displayOutput(types.uint(reducePrecision),errorThreshold) ), res)

  local res = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,1,8)), res )

  res = d.apply( "border", d.makeHandshake(darkroom.borderSeq( types.uint(8), W, H, 8, SADWidth+SearchWindow+OffsetX-2, 0, SADWidth-1, 0, 0 )), res ) -- cut off the junk (undefined region)

  table.insert(statements,1,res)

  local hsfn = d.lambda( "hsfn", hsfninp, d.statements(statements), fifos )
  return hsfn
end

return makeStereo