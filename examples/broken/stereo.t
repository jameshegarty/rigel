import "darkroom"
require "mapmachine"
require "image"

searchRadius = 60
windowRadius = 4

SADSize = (windowRadius*2+1)*(windowRadius*2+1)
W = 720
H = 405

W=64
H=32

--------------------------------
-- AD (int8,int8)->int32
A = d.input( darkroom.type.uint(8) )
B = d.input( darkroom.type.uint(8) )

AD = d.leaf( terra( out : &int32, A : &uint8, B : &uint8 ) @out = cstdlib.abs([int32](@A)-[int32](@B)) end, darkroom.type.int(32), A, B )

--------------------------------
-- SAD (uint8[SADSize], uint8[SADSize]) -> int32
A = d.input( darkroom.type.array( darkroom.type.uint(8),{SADSize}) )
B = d.input( darkroom.type.array( darkroom.type.uint(8),{SADSize}) )

ADMap = d.map( "admap", AD, A, B )
SAD = d.reduce( "sum", ADMap ) -- (int32[SADSize] -> uint32)
SAD = d.fn( "SAD", SAD, A, B )

--------------------------------
-- stereoKernel ( (uint8[SADSize])[searchRadius], (uint8[SADSize])[searchRadius] ) -> uint8 )
frame1stencils = d.input( darkroom.type.array( darkroom.type.uint(8), {SADSize, searchRadius}) )
frame2stencils = d.input( darkroom.type.array( darkroom.type.uint(8), {SADSize, searchRadius}) )

SADarray = d.map( "sadmap", SAD, frame1stencils, frame2stencils ) -- uint8[searchRadius)

indices = d.range( searchRadius, darkroom.type.uint(8) )
match = d.reduce( "argmin", SADarray, indices ) -- uint8

stereoKernel = d.fn( "stereoKernel", match, frame1stencils, frame2stencils )

-------------------------------
dupInput = d.input( darkroom.type.array( darkroom.type.uint(8), {SADSize} ) )
dupStencil = d.dup( dupInput, searchRadius )
dupStencil = d.fn( "dupStencil", dupStencil, dupInput )
-------------------------------
-- stereo (uint8[W*H], uint8[W*H]) -> uint8[W*H]

frame1 = d.input( darkroom.type.array( darkroom.type.uint(8), {W*H}) )
frame2 = d.input( darkroom.type.array( darkroom.type.uint(8), {W*H}) )

frame1st = d.extractStencils( "frame1st", frame1, W, -windowRadius*2, -windowRadius*2 ) -- (uint8[SADSize])[W*H]
frame1st = d.map( "dupmap", dupStencil, frame1st )
-- extractStencilArray is a function of extractStencils, slice
frame2st = d.extractStencilArray( "sadextract", frame2, W, -windowRadius*2, -windowRadius*2, searchRadius ) -- ((uint8[windowRadius*2+1][windowRadius*2+1])[searchRadius])[W*H]

print("SR",frame1st.type, frame2st.type)
stereoResult = d.map( "stereomap", stereoKernel, frame1st, frame2st )
stereo = d.fn( "stereo", stereoResult, frame1, frame2 )

---------------------
-- apply
stereo = d.compile( stereo )

terra doit()
  var left : Image
  left:load("left0224.bmp")
  var right : Image
  right:load("right0224.bmp")

  var imOut : Image
  imOut:load("left0224.bmp")

  stereo( [&uint8[W*H]](imOut.data), [&uint8[W*H]](left.data), [&uint8[W*H]](right.data) )
  imOut:save("stereo.bmp")
end

doit()