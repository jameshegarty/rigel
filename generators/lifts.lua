local lifts = {}
local P = require "params"
local T = require "types"

-- fn L[5] lifts L[1]->L[2] to L[3]->L[4]

-- lift pointwise to ParSeq: S(A)->S(B) to S(A{w,h;W,H])->S(B{w,h;W,H])
table.insert(lifts,{T.S(T.Par(P.DataType("A"))),T.S(T.Par(P.DataType("B"))),
                    T.S(T.ParSeq(T.array2d(P.DataType("A"),P.UintValue("w"),P.UintValue("h")),P.UintValue("W"),P.UintValue("H"))),
                    T.S(T.ParSeq(T.array2d(P.DataType("B"),P.UintValue("w"),P.UintValue("h")),P.UintValue("W"),P.UintValue("H"))),
                    function(args) return function(f) return RM.mapFramed(f) end end})

-- lift stateless modules to RV: S(A)->S(B) to RV(A)->RV(B)
table.insert(lifts,{T.S(P.ScheduleType("A")),T.S(P.ScheduleType("B")),
                    T.InterfaceRV(P.ScheduleType("A")),T.InterfaceRV(P.ScheduleType("B")),
                    function(args) return function(f) return RM.makeHandshake(f) end end})

-- typical map, A->B to A[w,h]->B[w,h]
table.insert(lifts,{T.InterfaceV(T.Par(P.DataType("A"))),T.R(T.Par(P.DataType("B"))),
                    T.InterfaceV(T.Par(T.array2d(P.DataType("A"),P.UintValue("W"),P.UintValue("H")))),
                    T.R(T.Par(T.array2d(P.DataType("B"),P.UintValue("W"),P.UintValue("H")))),
                    function(args) return function(f) return RM.map(f,args.W,args.H) end end})


return lifts
