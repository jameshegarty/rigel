local lifts = {}
local P = require "params"
local T = require "types"
local RM = require "generators.modules"

-- fn L[5] lifts L[1]->L[2] to L[3]->L[4]

-- lift pointwise to Seq: S(A)->S(B) to S(A{w,h})->S(B{w,h})
lifts.mapSeq={
  P.InterfaceType("InterfaceIn",P.ScheduleType("SchedIn")), P.InterfaceType("InterfaceOut",P.ScheduleType("SchedOut")),
  P.InterfaceType("InterfaceIn",T.Seq(P.ScheduleType("SchedIn"),P.SizeValue("Size"))), P.InterfaceType("InterfaceOut",T.Seq(P.ScheduleType("SchedOut"),P.SizeValue("Size"))),
  function(args) return function(f) return RM.mapSeq(f,args.Size[1],args.Size[2]) end end}

lifts.mapVarSeq={
  P.InterfaceType("InterfaceIn",P.ScheduleType("SchedIn")),
  P.InterfaceType("InterfaceOut",P.ScheduleType("SchedOut")),
  
  P.InterfaceType("InterfaceIn",T.VarSeq(P.ScheduleType("SchedIn"),P.SizeValue("Size"))),
  P.InterfaceType("InterfaceOut",T.VarSeq(P.ScheduleType("SchedOut"),P.SizeValue("Size"))),
  
  function(args) return function(f) return RM.mapVarSeq(f,args.Size[1],args.Size[2]) end end}

-- lift pointwise to Seq: S(A)->S(B) to S(A{w,h})->S(B{w,h})
lifts.mapSeqInilOut={
  P.InterfaceType("InterfaceIn",P.ScheduleType("SchedIn",P.DataType("A"))), T.Interface(),
  P.InterfaceType("InterfaceIn",T.Seq(P.ScheduleType("SchedIn",P.DataType("A")),P.SizeValue("Size"))), T.Interface(),
  function(args) return function(f) return RM.mapSeq(f,args.Size[1],args.Size[2]) end end}

lifts.mapParSeq={
  T.rv(T.Par(P.DataType("A"))),T.rv(T.Par(P.DataType("B"))),
  T.rv(T.ParSeq(T.array2d(P.DataType("A"),P.SizeValue("V")),P.SizeValue("Size"))),
  T.rv(T.ParSeq(T.array2d(P.DataType("B"),P.SizeValue("V")),P.SizeValue("Size"))),
  function(args) return function(f) return RM.mapParSeq(f,args.V[1],args.V[2],args.Size[1],args.Size[2]) end end}

-- lift stateless modules to RV: S(A)->S(B) to RV(A)->RV(B)
lifts.makeHandshake={
  T.rv(P.ScheduleType("A")),T.rv(P.ScheduleType("B")),
  T.RV(P.ScheduleType("A")),T.RV(P.ScheduleType("B")),
  function(args) return function(f) return RM.makeHandshake(f) end end}

lifts.makeHandshakeTrigger={
  T.Interface(),T.rv(P.ScheduleType("B")),
  T.HandshakeTrigger,T.RV(P.ScheduleType("B")),
  function(args) return function(f) return RM.makeHandshake(f,nil,true) end end}

lifts.makeHandshakeTriggerOut={
  T.rv(P.ScheduleType("B")),T.Interface(),
  T.RV(P.ScheduleType("B")),T.HandshakeTrigger,
  function(args) return function(f) return RM.makeHandshake(f,nil,true) end end}

--[=[
lifts.liftBasicToDecimate={
  T.S(P.ScheduleType("A")),T.S(P.ScheduleType("B")),
  T.S(P.ScheduleType("A")),T.V(P.ScheduleType("B")),
  function(args) return function(f) return RM.liftBasic(f) end end}
]=]
lifts.liftBasicToUpsamp={
  T.rv(P.ScheduleType("A")),T.rv(P.ScheduleType("B")),
  T.rV(P.ScheduleType("A")),T.rRV(P.ScheduleType("B")),
  function(args) return function(f) return RM.liftDecimate(RM.liftBasic(f)) end end}

lifts.liftDecimateToHandshake={
  T.rv(P.ScheduleType("A")),T.rvV(P.ScheduleType("B")),
  T.RV(P.ScheduleType("A")),T.RV(P.ScheduleType("B")),
  function(args) return function(f) return RM.liftHandshake(RM.liftDecimate(f)) end end}

lifts.liftHandshake={
  T.rV(P.ScheduleType("A")),T.rRV(P.ScheduleType("B")),
  T.RV(P.ScheduleType("A")),T.RV(P.ScheduleType("B")),
  function(args) return function(f) return RM.liftHandshake(f) end end}

-- typical map, A->B to A[w,h]->B[w,h]
lifts.arrayMap={
  T.rv(T.Par(P.DataType("A"))),T.rv(T.Par(P.DataType("B"))),
  T.rv(T.Par(T.array2d(P.DataType("A"),P.SizeValue("Size")))),
  T.rv(T.Par(T.array2d(P.DataType("B"),P.SizeValue("Size")))),
  function(args) return function(f) return RM.map(f,args.Size[1],args.Size[2]) end end}
--[=[
lifts.mapStateless={
  T.S(T.Par(P.DataType("A"))),T.S(T.Par(P.DataType("B"))),
  T.S(T.Par(T.array2d(P.DataType("A"),P.SizeValue("Size")))),
  T.S(T.Par(T.array2d(P.DataType("B"),P.SizeValue("Size")))),
  function(args) return function(f) return RM.map(f,args.Size[1],args.Size[2]) end end}
]=]
return lifts
