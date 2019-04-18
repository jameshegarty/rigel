local R = require "rigel"
local types = require "types"
local J = require "common"
local C = require "examplescommon"
local SDF = require "sdf"
local S = require "systolic"
local RM = require "modules"

function parseBB(lex,input,compilerState,X)
  assert(type(input)=="table")
--  assert(type(cond)=="function" or cond==nil)
  assert(X==nil)

  --if cond~=nil then input = {kind="phi",inputs={{input,cond}}, line=lex:cur().linenumber,desc="entry"} end
  
  local function checkFalse(cond)
    return function(env)
      local condv = cond(env)
      J.err(R.isIR(condv), "condition of if statement must be Rigel value, but is: "..tostring(condv))
      J.err(condv.type==types.bool(), "condition of if statement must have bool type, but type is: "..tostring(condv.type))
      return C.eq(types.bool())(condv,R.c(false))
    end
  end
  
  while true do
    if lex:matches("if") then
      lex:expect("if")
      local ifcond = J.memoize(lex:luaexpr())
      lex:expect("then")
      local truePhi = {kind="phi",inputs={{value=input,cond=ifcond,condId=compilerState.nextCondId}},desc="ifTruePhi", line=lex:cur().linenumber}
      local falseCondId = compilerState.nextCondId+1
      compilerState.nextCondId = compilerState.nextCondId + 2
      local TrueBB = parseBB(lex,truePhi,compilerState)
      lex:expect("else")

      local falsePhi = {kind="phi",inputs={{value=input,cond=checkFalse(ifcond),condId=falseCondId}},desc="ifFalsePhi", line=lex:cur().linenumber}
      
      local FalseBB = parseBB(lex,falsePhi,compilerState)
      lex:expect("end")
      local phi = {kind="phi",inputs={{value=TrueBB},{value=FalseBB}}, line=lex:cur().linenumber,desc="ifjoin"} -- saves us from dealing with multiple outputs
      input = phi
    elseif lex:matches("while") then
      lex:expect("while")
      local whilecond = J.memoize(lex:luaexpr())
      lex:expect("do")
      local whileCondId = compilerState.nextCondId
      -- have a node which is the entry point of the loop, which we can then attach the back edge to
      local whileEntryPoint = {kind="phi",inputs={{value=input,cond=whilecond,condId=whileCondId}}, line=lex:cur().linenumber, desc="whileentry"}

      local falseCondId = compilerState.nextCondId+1
      compilerState.nextCondId = compilerState.nextCondId + 2
      
      local bb = parseBB(lex,whileEntryPoint,compilerState)
      lex:expect("end")
      table.insert(whileEntryPoint.inputs,{value=bb,cond=whilecond,condId=whileCondId}) -- the back edge
      input = { kind="phi", inputs={{value=whileEntryPoint,cond=checkFalse(whilecond),condId=falseCondId}}, desc="whileoutput", line=lex:cur().linenumber }
    elseif lex:matches("yield") then
      lex:expect("yield")
      local line = lex:cur().linenumber
      local yieldExpr = lex:luaexpr()
      local st = compilerState.stateId
      compilerState.stateId = compilerState.stateId+1
      input = {kind="yield",inputs={{value=input}},state=st,expr=yieldExpr, traces={}, line=line }
    elseif lex:matches("[") then
      lex:expect("[")
      local expr = lex:luaexpr()
      lex:expect("]")
      input = { kind="expr", expr=expr, inputs={{value=input}}, line=lex:cur().linenumber }
    elseif lex:lookaheadmatches(":") then
      local instname = lex:expect(lex.name).value

      lex:expect(":")
      local expr = lex:luaexpr()
      table.insert(compilerState.instances,{instname,expr})
    else
     -- print("BREAK")
      break
    end
  end

  return input
end

-- walk the graph and collect a list of all nodes seen
local function collectNodes(node, nodeList)
  nodeList[node] = 1
  for k,v in ipairs(node.inputs) do
    if nodeList[v.value]==nil then
      collectNodes(v.value,nodeList)
    end
  end
end

local specializeNode
specializeNode = J.memoize(function( node, env, compilerState, condMap, X )
  assert(X==nil)

  for k,v in ipairs(node.inputs) do
    if v.cond~=nil then
      node.inputs[k].cond = v.cond(env)
      condMap[node.inputs[k].condId] = node.inputs[k].cond
    end
  end
  
  if node.kind=="phi" then
    -- do nothing
  elseif node.kind=="start" then
    compilerState.stateMap[node.state]=node
  elseif node.kind=="yield"  then
    compilerState.stateMap[node.state]=node
    node.expr = node.expr(env)
    J.err(R.isIR(node.expr), "yield return must be Rigel value, but is: "..tostring(node.expr))
    J.err(node.expr.type==compilerState.outputType, "yield return type must match function output type ("..tostring(compilerState.outputType).."), but type is: "..tostring(node.expr.type))
  elseif node.kind=="expr" then
    node.expr = node.expr(env)
    J.err(R.isIR(node.expr), "basic block return must be Rigel value, but is: "..tostring(node.expr))
  else
    print("NYI - specialize "..node.kind)
    assert(false)
  end

  return node
end)

-- traces={ {bbs={[rigelExpr]=1}, conds={[rigelCondExpr]=1}, path={nodes}, endState=X} }
-- collecting traces is a backward pass... yield states pass to the input nodes,
--   and along the way we append any BBs or conditions they hit.
-- note that this is exponential, intentionally - we want to find all dynamic paths
function extractTraces( node, traces )

  local function checkTraces(a)
    for endState,v in pairs(a) do
      J.err(type(v.bbs)=="table", "bbs should be table, but is: "..tostring(type(v.bbs)) )
      assert(type(v.condIdMap)=="table")
      assert(type(v.path)=="table")
    end
  end

  local function copyTrace(trace)
    local newTrace = {bbs={},condIdMap={},path={},endState=trace.endState}
    for bb,_ in pairs(trace.bbs) do newTrace.bbs[bb]=1 end
    for condId,_ in pairs(trace.condIdMap) do newTrace.condIdMap[condId]=1 end
    for _,n in ipairs(trace.path) do table.insert(newTrace.path,n) end
    return newTrace
  end

  
  local function copyTraces(traces)
    local newTraces = {}
    for endState,v in pairs(traces) do newTraces[endState] = copyTrace(v) end
    return newTraces
  end

  local function printPath(p)
    for k,v in ipairs(p) do print(v.kind,"DESC",v.desc,v.expr,"LINE",v.line) end
  end

  if node.kind=="yield" or node.kind=="start" then
    -- yield nodes are terminating - they ignore the input traces when passing up
    -- accumulate all the nodes that end up hitting this start state
    node.traces = J.joinTables( node.traces, traces )
  elseif node.kind=="phi" or node.kind=="expr" then
    for k,v in ipairs(node.inputs) do

      local upTraces = copyTraces(traces)
      for _,trace in ipairs(upTraces) do
        -- careful! we're playing fast and loose with table format here
        if node.expr~=nil then assert(R.isIR(node.expr)); trace.bbs[node.expr]=1 end 
        if v.condId~=nil then assert(type(v.condId)=="number"); trace.condIdMap[v.condId]=1 end
        table.insert( trace.path, node )
      end

      extractTraces( v.value, upTraces )
    end
  else
    print("NYI - extract trace ",node.kind)
    assert(false)
  end
end

function compile(code,compilerState)
  for k,node in pairs(compilerState.stateMap) do
    -- for each input to the terminating state node, propagate its traces up to inputs
    assert(node.kind=="yield" or node.kind=="start")
    local nodeSeen = {}
    for k,v in ipairs(node.inputs) do
      local condIdMap={}
      if v.cond~=nil then condIdMap[v.condId]=1 end
      local traces = {{bbs={},condIdMap=condIdMap,path={},endState=node.state}}
      extractTraces( v.value, traces )
    end
  end
  
  print("Traces:")
  for k,node in pairs(compilerState.stateMap) do
    print("  State ",k)
    for tk,tv in pairs(node.traces) do
      print("    Target:",tk)
      for cond,_ in pairs(tv.condIdMap) do
        print("      Cond:",cond)
      end

      for bb,_ in pairs(tv.bbs) do
        print("      BBs:",bb)
      end
    end
    print("    Output: ",node.expr)
  end
end

function parseDecl(decl)
  if decl:sub(1,7)=="assign " then
    decl = decl:sub(8)
    return J.explode(" = ",decl)
  else
    J.err(decl:sub(1,9)=="  assign ","Decl not as expected? '"..decl.."'")
    decl = decl:sub(10)
    decl = J.explode(" = ",decl)
    return decl
  end
end

function mergeDecls(decls,indent)
  local str = ""
  local seen = {}
  for _,decl in ipairs(decls) do
    if seen[decl[1]]==nil then
      J.err(type(decl[1])=="string" and type(decl[2])=="string","mergeDecls, decls should be strings? "..tostring(decl[1])..", "..tostring(decl[2]))
      str = str..indent..decl[1].." = "..decl[2].."\n"
      seen[decl[1]] = decl[2]
    else  
      if seen[decl[1]]~=decl[2] then
        J.err(false,"Signal '"..decl[1].."' is set twice! first:'"..seen[decl[1]].."' second:'"..decl[2].."'")
      end
    end
  end
  return str
end

function cleanupDecls(decls,indent)
  local fd = {}
  for _,v in pairs(decls) do
    if v~="" and v:sub(1,11)~="// function" then table.insert(fd,parseDecl(v) ) end
  end

  return mergeDecls(fd,indent)
end

-- condMap is a mad of all conds from condId->rigelExpr
-- add required instance to systolic module 's', and collect decls
-- 's' should already have user-declared instances added
-- returns condWireDecls, condOutputMap : condId->verilogString
function codegenConds(s,condMap)
  local condWireDecls = {}
  local condOutputMap = {}

  local condvec = R.concat(condMap)
  
  local cs = condvec:codegenSystolic(s)
  J.err(cs[1]:internalDelay()==0,"Condition should be async")
  s:lookupFunction("process"):addPipeline(cs[1])
  
  local decls={}
  local fin = cs[1]:toVerilogInner(s,decls)

  return cleanupDecls(decls,"  "), fin[1], cs[1].type:verilogBits()
end

-- This constructs a fresh module with the instances on it,
-- wires up all BB statements and yield output, and codegens to verilog
-- * if a module wasn't driven along this dynamic path, this should given an error
-- returns wireDecls, yieldOutVerilog
function codegenBBs( compilerState, startState, traceId, bbs, yieldOut )
  local pipes={}
  table.insert(pipes,yieldOut)
  for bb,_ in pairs(bbs) do table.insert(pipes,bb) end

  local rmod = RM.lambda("BBGEN_"..tostring(startState).."_"..tostring(traceId), compilerState.rigelInput, R.statements(pipes), J.invertAndStripKeys(compilerState.instanceMap) )
  --rmod.instanceMap = compilerState.instanceMap
  
--  print(rmod)
  local wireDecls, instanceDecls = rmod:toVerilogNoHeader()
  return cleanupDecls(wireDecls,"    "), rmod.systolicModule.instanceMap, rmod.requires
end


function andConds(condIdMap)
  if J.keycount(condIdMap)==0 then
    return "1'b1"
  else
    local str = ""
    local first = true
    for condid,_ in pairs(condIdMap) do
      if first==false then str = str.." & " end
      first=false
      str = str.."COND_VEC["..(condid-1).."]"
    end
    return str
  end
end

return{
  name = "state";
  entrypoints = {"state"};
  keywords = {"if","else","end","yield","while", "do"};
  statement = function(self,lex)
    lex:expect("state")
    local fname = lex:expect(lex.name).value
    lex:expect("(")

    local Iname = lex:expect(lex.name).value
    lex:expect(":")
    local ItypeFn = lex:luaexpr()
    

    lex:expect(",")

    local Oname = lex:expect(lex.name).value
    lex:expect(":")
    local OtypeFn = lex:luaexpr()
    
    lex:expect(")")
    local startNode = {kind="start",inputs={},state=1,traces={}}
    -- condMap: map from condId to Rigel Expr
    local compilerState={stateId=2,instances={},instanceMap={}, nextCondId=1}
    local code = parseBB(lex,startNode,compilerState)
    lex:expect("end")
    return function(env_fn)
      local env = env_fn()
      local Itype = ItypeFn(env)
--      print("INPUTTYPE:",Itype)
      J.err(types.isType(Itype),"input type must be rigel type, but is: "..tostring(Itype))
      compilerState.inputType=Itype
      
      local Otype = OtypeFn(env)
--      print("OUTPUTTYPE:",Otype)
      J.err(types.isType(Otype),"output type must be rigel type, but is: "..tostring(Otype))
      compilerState.outputType=Otype
      compilerState.rigelInput = R.input(Itype)
      env[Iname] = compilerState.rigelInput

      compilerState.stateMap={} -- map from state id to yield node

      local res = R.newFunction{inputType=Itype,outputType=Otype,sdfInput=SDF{1,1},sdfOutput=SDF{1,1},name=fname,delay=0,stateful=true}
      compilerState.module = res

      for k,inst in pairs(compilerState.instances) do
        local rmod = inst[2](env)
        J.err(R.isModule(rmod),"instance module is not a Rigel module? Is :"..tostring(rmod))
        local rinst =  rmod:instantiate(inst[1])
        compilerState.instances[k][2] = rinst
        J.err(env[inst[1]]==nil,"instance name '' was already set in environment?")
        env[inst[1]] = rinst
        compilerState.instanceMap[rinst]=1
      end

      res.instanceMap = compilerState.instanceMap
      
      local nodeList = {}
      collectNodes( code, nodeList )

      local condMap = {}
      for node,_ in pairs(nodeList) do specializeNode( node, env, compilerState, condMap ) end

      --[=[
      for node,_ in pairs(nodeList) do
        print("NODE",node.kind,node.desc,node,"LINE",node.line)
        for _,inp in ipairs(node.inputs) do
          print("    input ",inp.value.kind,inp.value.desc,inp.value,"line",inp.value.line,"cond",inp[2])
        end
      end
      ]=]
      
      compile( code, compilerState )

      local extraInstances = {}

        local bbdecls={}
        for startState,node in pairs(compilerState.stateMap) do
          bbdecls[startState]={}
          for traceId,trace in ipairs(node.traces) do
            local instanceMap, requires
            bbdecls[startState][traceId], instanceMap, requires = codegenBBs( compilerState, startState, traceId, trace.bbs, compilerState.stateMap[trace.endState].expr )
            --for k,v in pairs(instDecl) do instanceDecls[v]=1 end
            for inst,_ in pairs(instanceMap) do
--              print("EXTRA INST",inst)
              extraInstances[inst.name] = inst
            end
            
            for ic,_ in pairs(requires) do res.requires[ic] = 1 end
          end
        end

      function res.makeSystolic()
--        S.DISABLE_WIRING_ERRORS = true



        local seenInstances = {}
        for inst,_ in pairs(res.instanceMap) do
          seenInstances[inst.name] = 1
        end

        local s = C.automaticSystolicStub(res)

        for name,sinst in pairs(extraInstances) do
          if seenInstances[name]==nil then
            s.__instanceMap[sinst] = 1

            for _,fn in pairs(sinst.module.functions) do
              if fn.inputParameter.type==types.null() then
                s.__functions.process:addPipeline(sinst[fn.name](sinst,nil,S.constant(false,types.bool())))
              else
                s.__functions.process:addPipeline(sinst[fn.name](sinst,S.constant(fn.inputParameter.type:fakeValue(),fn.inputParameter.type)))
              end
            end
          end
        end

--        C.tiedownInstances(s)

        local verilog = {}
        table.insert(verilog,res:vHeader())
        table.insert(verilog,[[  reg [31:0] STATE;
  wire [31:0] NEXT_STATE;

  always @ (posedge CLK) begin
    if (reset==1'b1) begin
      STATE <= 32'd1;
    end else ]]..J.sel(types.isHandshakeAny(Itype) or types.isHandshakeAny(Otype),"","if (CE && process_valid)")..[[ begin
      STATE <= NEXT_STATE;
    end

    //$display("STATEDISP reset %d CE %d STATE: %d, NEXT_STATE:%d process_valid %d process_input %d process_output %d",reset,CE,STATE,NEXT_STATE,process_valid,process_input,process_output);
  end

]])

        local condWireDecls, condOutput, condVecBits = codegenConds(s,condMap)
        for inst,_ in pairs(s.__instanceMap) do
          if inst.module.instanceToVerilogStart~=nil and (s.__externalInstances[inst]==nil) then
            local sst = inst.module:instanceToVerilogStart( inst )
            if sst~=nil then table.insert(verilog,sst) end
--            if sst~=nil then instanceDecls[sst]=1 end
          end
        end


--        for k,v in pairs(instanceDecls) do table.insert(verilog,k) end
        
        local first = true
        table.insert(verilog,"wire ["..tostring(condVecBits-1)..":0] COND_VEC;\n")
        table.insert(verilog,[[  always_comb begin
]]..condWireDecls.."  COND_VEC = "..condOutput..";\n")

        for startState,node in pairs(compilerState.stateMap) do
          if first==false then table.insert(verilog," else ") end
          first=false
          
          table.insert(verilog,"if (STATE==32'd"..startState..[[) begin
]])

          for traceId,trace in ipairs(node.traces) do
            table.insert(verilog,[[  if (]]..andConds(trace.condIdMap)..[[) begin
]])

--            local bbdecl, instanceDecls = codegenBBs( compilerState, startState, traceId, trace.bbs, compilerState.stateMap[trace.endState].expr )
            table.insert(verilog,bbdecls[startState][traceId])
--            table.insert(verilog,[[    process_output = ]]..yieldOut..";\n")
            table.insert(verilog,[[    NEXT_STATE = 32'd]]..tostring(trace.endState)..";\n")
            table.insert(verilog,[[  end
]])
          end
          table.insert(verilog,"end")
        end
      
        table.insert(verilog,"  end")
        
table.insert(verilog,[[

endmodule

]])

        s:verilog(table.concat(verilog,""))

        s = s:complete()

        S.DISABLE_WIRING_ERRORS = nil
        return s
      end
      return res
    end, {fname}
  end;
}
