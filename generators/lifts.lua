local lifts = {}
local P = require "params"
local T = require "types"
local RM = require "generators.modules"

-- fn L[5] lifts L[1]->L[2] to L[3]->L[4]

-- lift pointwise to ParSeq: S(A)->S(B) to S(A{w,h;W,H])->S(B{w,h;W,H])
lifts.mapSeq={
  T.S(T.Par(P.DataType("A"))),T.S(T.Par(P.DataType("B"))),
  T.S(T.Seq(P.DataType("A"),P.SizeValue("Size"))),T.S(T.Seq(P.DataType("B"),P.SizeValue("Size"))),
  function(args) return function(f) return RM.mapSeq(f,args.Size[1],args.Size[2]) end end}

lifts.mapParSeq={
  T.S(T.Par(P.DataType("A"))),T.S(T.Par(P.DataType("B"))),
  T.S(T.ParSeq(T.array2d(P.DataType("A"),P.SizeValue("V")),P.SizeValue("Size"))),
  T.S(T.ParSeq(T.array2d(P.DataType("B"),P.SizeValue("V")),P.SizeValue("Size"))),
  function(args) return function(f) return RM.mapParSeq(f,args.V[1],args.V[2],args.Size[1],args.Size[2]) end end}

-- lift stateless modules to RV: S(A)->S(B) to RV(A)->RV(B)
lifts.makeHandshake={
  T.S(P.ScheduleType("A")),T.S(P.ScheduleType("B")),
  T.RV(P.ScheduleType("A")),T.RV(P.ScheduleType("B")),
  function(args) return function(f) return RM.makeHandshake(f) end end}

lifts.liftDecimate={
  T.S(P.ScheduleType("A")),T.V(P.ScheduleType("B")),
  T.RV(P.ScheduleType("A")),T.RV(P.ScheduleType("B")),
  function(args) return function(f) return RM.liftHandshake(RM.liftDecimate(f)) end end}

lifts.liftHandshake={
  T.rV(P.ScheduleType("A")),T.RV(P.ScheduleType("B")),
  T.RV(P.ScheduleType("A")),T.RV(P.ScheduleType("B")),
  function(args) return function(f) return RM.liftHandshake(f) end end}

-- typical map, A->B to A[w,h]->B[w,h]
lifts.map={
  T.V(T.Par(P.DataType("A"))),T.R(T.Par(P.DataType("B"))),
  T.V(T.Par(T.array2d(P.DataType("A"),P.SizeValue("Size")))),
  T.R(T.Par(T.array2d(P.DataType("B"),P.SizeValue("Size")))),
  function(args) return function(f) return RM.map(f,args.Size[1],args.Size[2]) end end}

lifts.mapStateless={
  T.S(T.Par(P.DataType("A"))),T.S(T.Par(P.DataType("B"))),
  T.S(T.Par(T.array2d(P.DataType("A"),P.SizeValue("Size")))),
  T.S(T.Par(T.array2d(P.DataType("B"),P.SizeValue("Size")))),
  function(args) return function(f) return RM.map(f,args.Size[1],args.Size[2]) end end}

return lifts
