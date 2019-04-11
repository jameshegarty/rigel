local R = require "rigel"
local types = require "types"
local J = require "common"
local C = require "examplescommon"
local SDF = require "sdf"
local S = require "systolic"

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
      local truePhi = {kind="phi",inputs={{input,ifcond}},desc="ifTruePhi", line=lex:cur().linenumber}
      local TrueBB = parseBB(lex,truePhi,compilerState)
      lex:expect("else")
      --local falsePhi = {kind="phi",inputs={{input,checkFalse(cond)}} }
      local falsePhi = {kind="phi",inputs={{input,checkFalse(ifcond)}},desc="ifFalsePhi", line=lex:cur().linenumber}
      local FalseBB = parseBB(lex,falsePhi,compilerState)
      lex:expect("end")
      local phi = {kind="phi",inputs={{TrueBB},{FalseBB}}, line=lex:cur().linenumber,desc="ifjoin"} -- saves us from dealing with multiple outputs
      input = phi
    elseif lex:matches("while") then
      lex:expect("while")
      local whilecond = J.memoize(lex:luaexpr())
      lex:expect("do")
      -- have a node which is the entry point of the loop, which we can then attach the back edge to
      local whileEntryPoint = {kind="phi",inputs={{input,whilecond}}, line=lex:cur().linenumber, desc="whileentry"}
      local bb = parseBB(lex,whileEntryPoint,compilerState)
      lex:expect("end")
      table.insert(whileEntryPoint.inputs,{bb,whilecond}) -- the back edge
      input = { kind="phi", inputs={{whileEntryPoint,checkFalse(whilecond)}}, desc="whileoutput", line=lex:cur().linenumber }
    elseif lex:matches("yield") then
      lex:expect("yield")
      local line = lex:cur().linenumber
      local yieldExpr = lex:luaexpr()
      local st = compilerState.stateId
      compilerState.stateId = compilerState.stateId+1
      input = {kind="yield",inputs={{input}},state=st,expr=yieldExpr, traces={}, line=line }
    elseif lex:matches("[") then
      lex:expect("[")
      local expr = lex:luaexpr()
      lex:expect("]")
      input = { kind="expr", expr=expr, inputs={{input}}, line=lex:cur().linenumber }
    elseif lex:lookaheadmatches(":") then
      local instname = lex:expect(lex.name).value
      print("PARSE INST",instname)
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
    if nodeList[v[1]]==nil then
      collectNodes(v[1],nodeList)
    end
  end
end

-- returns outvar, decls list, readyOut (optional)
local function exprToCode(node,compilerState)
  local res = R.newFunction{inputType=compilerState.inputType,outputType=compilerState.outputType,sdfInput=SDF{1,1},sdfOutput=SDF{1,1},name=compilerState.module.name.."_YIELD"..tostring(node.state),delay=0,stateful=true,instanceMap=compilerState.instanceMap}
  local s = C.automaticSystolicStub(res)
  local cs = node.expr:codegenSystolic(s)

  local readyinp,readyout,readyPipelines
  if R.handshakeMode(node.expr) then
    print("HANDSHAKEMODE",node.expr)
    --assert(false)
    readyinp,readyout,readyPipelines = node.expr:codegenSystolicReady(s)
  end
    
  s = s:complete()
  local decls={}
  local fin = cs[1]:toVerilogInner(s,decls)

  local readyVOut
  if R.handshakeMode(node.expr) then
    if readyout~=nil then
      readyVOut = readyout:toVerilogInner(s,decls)
    end

    for _,p in ipairs(readyPipelines) do
      local tout = p:toVerilogInner(s,decls)
      print("READYOUT? ",tout[1],tout[2])
--      assert(tout==nil)
    end
  end
  
  return fin[1], decls, readyVOut
end

local specializeNode
specializeNode = J.memoize(function( node, env, compilerState, X )
  assert(X==nil)
    
  --print("Specialize",node.kind,node.state,node,env,compilerState)

  for k,v in ipairs(node.inputs) do
    if v[2]~=nil then node.inputs[k][2] = v[2](env) end
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

    
    node.verilogOut, node.verilogDecls = exprToCode(node,compilerState)
  elseif node.kind=="expr" then
    node.expr = node.expr(env)
    J.err(R.isIR(node.expr), "basic block return must be Rigel value, but is: "..tostring(node.expr))
  else
    print("NYI - specialize "..node.kind)
    assert(false)
  end

  return node
end)

-- traces={ endState={bbs={[rigelExpr]=1}, conds={[rigelCondExpr]=1}} }
-- collecting traces is a backward pass... yield states pass to the input nodes,
--   and along the way we append any BBs or conditions they hit.
-- note that this is exponential, intentionally - we want to find all dynamic paths
function extractTraces(node, traces, nodeSeen)

  --print("TRACE",node.kind,node.desc,node.line,node,"INPUTS:",#node.inputs)

  --[=[
-- doesn't work: there may be a common node that is hit along multiple dynamic paths
  if nodeSeen[node]~=nil then
    print("you have an infinite loop somewhere, with no yields to break it?")
    print("NODE: ",node.kind, "linenumber:",node.line,node.desc)
    assert(false)
  end
  nodeSeen[node] = 1
  ]=]
  
  local function mergeTraces(a,b)
    assert(a~=nil)
    assert(b~=nil)
    
    local tr = {}
    for k,v in pairs(a) do
      assert(type(v.bbs)=="table")
      assert(type(v.conds)=="table")
      tr[k] = {bbs=v.bbs,conds=v.conds}
    end

    for k,v in pairs(b) do
      if tr[k]==nil then tr[k]={bbs={},conds={}} end

      assert(type(v.bbs)=="table")
      assert(type(v.conds)=="table")

      tr[k].bbs = J.joinSet(tr[k].bbs,v.bbs,true)
      tr[k].conds = J.joinSet(tr[k].conds,v.conds,true)
    end

    for k,v in pairs(tr) do
      assert(type(v.bbs)=="table")
      assert(type(v.conds)=="table")
    end

    return tr
  end

  for k,v in pairs(traces) do
    assert(type(v.bbs)=="table")
    assert(type(v.conds)=="table")
  end
      
  if node.kind=="yield" or node.kind=="start" then
    node.traces = mergeTraces(node.traces,traces)
--    print("TRACEDONE")
    --yield nodes are terminating - they ignore the input traces when passing up
  elseif node.kind=="phi" or node.kind=="expr" then
    for k,v in ipairs(node.inputs) do

      local itrace = traces
      if v[2]~=nil then
        -- if this input has a condition, we need to add it to all the traces
        for tk,tv in pairs(traces) do
          local thisTrace = {}
          local bbs={}
          local conds={}
          conds[v[2]]=1
          thisTrace[tk] = {bbs=bbs,conds=conds}

          itrace = mergeTraces(itrace,thisTrace)
        end
      end

      extractTraces(v[1],itrace,nodeSeen)
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
      print("TRACE INPUT",k)
      local trace = {}
      local bbs={}
      local conds={}
      if v[2]~=nil then conds[v[2]]=1 end
      trace[node.state] = {bbs=bbs,conds=conds}

      extractTraces(v[1],trace,nodeSeen)
    end
  end
  
  print("Traces:")
  for k,node in pairs(compilerState.stateMap) do
    print("  State ",k)
    for tk,tv in pairs(node.traces) do
      print("    Target:",tk)
      for cond,_ in pairs(tv.conds) do
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
  J.err(decl:sub(1,9)=="  assign ","Decl not as expected? '"..decl.."'")
  decl = decl:sub(10)
  decl = J.explode(" = ",decl)
  return decl
end

function mergeDecls(decls)
  local str = ""
  local seen = {}
  for _,decl in ipairs(decls) do
    if seen[decl[1]]==nil then
      str = str..decl[1].." = "..decl[2].."\n"
      seen[decl[1]] = decl[2]
    else  
      if seen[decl[1]]~=decl[2] then
        J.err(false,"Signal '"..decl[1].."' is set twice! first:'"..seen[decl[1]].."' second:'"..decl[2].."'")
      end
    end
  end
  return str
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
    --J.err(types.isType(Otype),"output type must be rigel type")
    
    lex:expect(")")
    local startNode = {kind="start",inputs={},state=1,traces={}}
    local compilerState={stateId=2,instances={},instanceMap={}}
    local code = parseBB(lex,startNode,compilerState)
    lex:expect("end")
    return function(env_fn)
      local env = env_fn()
      local Itype = ItypeFn(env)
      print("INPUTTYPE:",Itype)
      J.err(types.isType(Itype),"input type must be rigel type, but is: "..tostring(Itype))
      compilerState.inputType=Itype
      
      local Otype = OtypeFn(env)
      print("OUTPUTTYPE:",Otype)
      J.err(types.isType(Otype),"output type must be rigel type, but is: "..tostring(Otype))
      compilerState.outputType=Otype
      env[Iname] = R.input(Itype)

      compilerState.stateMap={} -- map from state id to yield node

      local res = R.newFunction{inputType=Itype,outputType=Otype,sdfInput=SDF{1,1},sdfOutput=SDF{1,1},name=fname,delay=1,stateful=true}
      compilerState.module = res

      for k,inst in pairs(compilerState.instances) do
        local rmod = inst[2](env)
        --print("INST",inst[1],rinst)
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
      for node,_ in pairs(nodeList) do specializeNode( node, env, compilerState ) end

      for node,_ in pairs(nodeList) do
        print("NODE",node.kind,node.desc,node,"LINE",node.line)
        for _,inp in ipairs(node.inputs) do
          print("    input ",inp[1].kind,inp[1].desc,inp[1],"line",inp[1].line,"cond",inp[2])
        end
      end
      
      compile( code, compilerState )

      function res.makeSystolic()
        S.DISABLE_WIRING_ERRORS = true

        local s = C.automaticSystolicStub(res)
        s:lookupFunction("process"):setCE(S.CE("CE"))
          
        local verilog = {}
        table.insert(verilog,res:vHeader())
        table.insert(verilog,[[  reg [31:0] STATE;
  wire [31:0] NEXT_STATE;
  wire []]..(types.lower(Otype):verilogBits()-1)..[[:0] process_output_next;
  reg []]..(types.lower(Otype):verilogBits()-1)..[[:0] process_output_reg;

  always @ (posedge CLK) begin
    if (reset==1'b1) begin
      STATE <= 32'd1;
    end else if (CE) begin
      STATE <= NEXT_STATE;
      process_output_reg <= process_output_next;
    end

//    $display("STATE: %d, NEXT_STATE:%d",STATE,NEXT_STATE);
  end
  assign process_output = process_output_reg;
]])

        local declMap = {}
        local condV = {}
        local condDecl = {}
        
        for k,node in pairs(compilerState.stateMap) do
          condV[k] = {}
          condDecl[k] = {}

          for tk,tv in pairs(node.traces) do
            condV[k][tk] = ""

            local first = true
            for cond,_ in pairs(tv.conds) do
              local tempMod = C.automaticSystolicStub(res)
              tempMod.__name = J.sanitize(tempMod.__name.."_"..k.."_"..tk.."_"..tostring(cond))
              local cs = cond:codegenSystolic(tempMod)
              J.err(cs[1]:internalDelay()==0,"Condition should be async")
              tempMod:lookupFunction("process"):addPipeline(cs[1])
              tempMod = tempMod:complete()

              --[=[
              for _,inst in pairs(tempMod.instances) do
                local sinst = inst.module:instantiate("DEPINST_"..tostring(J.keycount(s.__instanceMap)))
                s:add( sinst )
                if sinst.module.functions.reset~=nil then
                  print("REST",s:lookupFunction("reset"))
                  s:lookupFunction("reset"):addPipeline(sinst:reset())
                end
                end]=]
              
              local decls={}
              local fin = cs[1]:toVerilogInner(tempMod,decls)

              for _,v in pairs(decls) do
                if v~="" then
                  table.insert(condDecl[k],parseDecl(v) )
                end
              end
              
              for _,inst in pairs(tempMod.instances) do
                if inst.module.instanceToVerilogStart~=nil and (tempMod.externalInstances[inst]==nil) then
                  local sst = inst.module:instanceToVerilogStart( inst )
                  if sst~=nil then declMap[sst]=1 end
                end
              end
              
              if first then
                condV[k][tk] = condV[k][tk]..fin[1]
                first = false
              else
                condV[k][tk] = condV[k][tk].." && "..fin[1]
              end
            end
          end
        end

        for d,_ in pairs(declMap) do
          table.insert(verilog,d)
        end

        local first = true
        table.insert(verilog,[[  always_comb begin
]])

        for k,node in pairs(compilerState.stateMap) do
          if first==false then table.insert(verilog," else ") end
          first=false
          
          table.insert(verilog,"if (STATE==32'd"..k..[[) begin
]])
          table.insert(verilog, mergeDecls(condDecl[k]) )

          for tk,tv in pairs(node.traces) do
            table.insert(verilog,[[  if (]]..condV[k][tk]..[[) begin
]])
            table.insert(verilog,[[    process_output_next = ]]..compilerState.stateMap[tk].verilogOut..";\n")
            table.insert(verilog,[[    NEXT_STATE = 32'd]]..tostring(tk)..";\n")
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
