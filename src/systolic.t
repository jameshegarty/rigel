local systolic={}

systolicModuleFunctions = {}
systolicModuleMT={__index=systolicModuleFunctions}

systolicInstanceFunctions = {}

function sanitize(s)
  s = s:gsub("%[","_")
  s = s:gsub("%]","_")
  s = s:gsub("%,","_")
  s = s:gsub("%.","_")
  return s
end

local function typecheck(ast)
  assert(darkroom.ast.isAST(ast))

  if ast.kind=="ram128" then
    local t = ast:shallowcopy()
    t.type=darkroom.type.bool()
    return systolicAST.new(t):copyMetadataFrom(ast)
  elseif ast.kind=="reg" or ast.kind=="readinput" then
    local t = ast:shallowcopy()
    t.type = t.inst.type
    return systolicAST.new(t):copyMetadataFrom(ast)
  else
    return darkroom.typedAST.typecheckAST(ast, filter(ast,function(n) return systolicAST.isSystolicAST(n) end), systolicAST.new )
  end
end

local function convert(ast)
  if getmetatable(ast)==systolicASTMT then
    return ast
  elseif type(ast)=="boolean" then
    -- we might want to do this, but if we accidentally
    -- use a binary op (==) or w/e on a systolic table,
    -- we will get a bool, but this is definitely not what we want
    assert(false)
  elseif type(ast)=="number" then
    local t = darkroom.ast.new({kind="value", value=ast}):setLinenumber(0):setOffset(0):setFilename("")
    return typecheck(t)
  else
    print(type(ast))
    assert(false)
  end
end

function checkReserved(k)
  if k=="input" or k=="output" or k=="reg" then
    print("Error, variable name ",k," is a reserved keyword in verilog")
    assert(false)
  end
end

local definitionCache = {}
function systolic.addDefinition(X)
  if definitionCache[X:getDefinitionKey()]==nil then
    definitionCache[X:getDefinitionKey()] = X:getDefinition()
  end
end

function systolic.getDefinitions()
  local t = ""
  for k,v in pairs(definitionCache) do
    t = t..table.concat(v)
  end

  return t
end

local binopToVerilog={["+"]="+",["*"]="*",["<<"]="<<<",[">>"]=">>>",["pow"]="**",["=="]="==",["and"]="&",["-"]="-",["<"]="<",[">"]=">",["<="]="<=",[">="]=">="}

local binopToVerilogBoolean={["=="]="==",["and"]="&&",["~="]="!=",["or"]="||"}

function declareReg(ty, name, initial, comment)
  assert(type(name)=="string")

  if comment==nil then comment="" end

  if initial==nil or initial=="" then 
    initial=""
  else
    initial = " = "..valueToVerilog(initial,ty)
  end

  if ty:isBool() then
    return "reg "..name..initial..";"..comment.."\n"
  else
    return "reg ["..(ty:sizeof()*8-1)..":0] "..name..initial..";"..comment.."\n"
 end
end

function declareWire(ty, name, str, comment)
  assert(darkroom.type.isType(ty))
  assert(type(str)=="string" or str==nil)

  if comment==nil then comment="" end

  if str == nil or str=="" then
    str = ""
  else
    str = " = "..str
  end

  if ty:isBool() then
    return "wire "..name..str..";"..comment.."\n"
  else
    return "wire ["..(ty:sizeof()*8-1)..":0] "..name..str..";"..comment.."\n"
  end
end

function declarePort(ty,name,isInput)
  assert(type(name)=="string")

  local t = "input "
  if isInput==false then t = "output " end

  if ty:isBool()==false then
    t = t .."["..(ty:sizeof()*8-1)..":0] "
  end
  t = t..name
  
  return t
end

function channelIndex( ty, c )
  assert(darkroom.type.isType(ty))
  assert(type(c)=="number")

  if ty:channels()==1 then
    return ""
  elseif ty:baseType():isBool() then
    assert(false)
  else
    return "["..(c*ty:baseType():sizeof()*8-1)..":"..((c-1)*ty:baseType():sizeof()*8).."]"
  end
end

function numToVarname(x)
  if x>0 then return x end
  if x==0 then return "0" end
  return "m"..math.abs(x)
end

function pointerToVarname(x)
  assert(type(x)=="table")
  return tostring(x):sub(10)
end

local __usedModuleNames = {}
function systolic.module( name, options )
  assert(type(name)=="string")
  if options==nil then options={} end
  assert(type(options)=="table")

  if __usedModuleNames[name]~=nil then
    print("Module name ",name, "already used")
    assert(false)
  end

  __usedModuleNames[name]=1
  local t = {name=name,instances={},functions={}, instanceMap={}, usedInstanceNames = {}, options=options}
  return setmetatable(t,systolicModuleMT)
end

function systolicModuleFunctions:add( inst )
  assert(systolicInstance.isSystolicInstance(inst))
  assert( inst.kind=="module" or inst.kind=="reg" or inst.kind=="ram128" or inst.kind=="bram")

  checkReserved(inst.name)
  if self.usedInstanceNames[inst.name]~=nil then
    print("Error, name "..inst.name.." already in use")
    assert(false)
  end

  self.instanceMap[inst] = 1
  self.usedInstanceNames[inst.name] = 1

  table.insert(self.instances,inst)
  return inst
end

function valueToVerilogLL(value,signed,bits)
  assert(type(value)=="number")

  if signed then
    if value==0 then
      return bits.."'d0"
    elseif value<0 then
      return "-"..bits.."'d"..math.abs(value)
    else
      return bits.."'d"..value
    end
  else
    assert(value>=0)
    return bits.."'d"..math.abs(value)
  end
end

function valueToVerilog(value,ty)

  if ty:isInt() then
    assert(type(value)=="number")
    if value==0 then
      return (ty:sizeof()*8).."'d0"
    elseif value<0 then
      return "-"..(ty:sizeof()*8).."'d"..math.abs(value)
    else
      return (ty:sizeof()*8).."'d"..value
    end
  elseif ty:isUint() then
    assert(type(value)=="number")
    assert(value>=0)
    return (ty:sizeof()*8).."'d"..value
  elseif ty:isBool() then
    if value then
      return "1'd1"
    else
      return "1'd0"
    end
  else
    assert(false)
  end
end

function systolicModuleFunctions:instantiate(name)
  assert(type(name)=="string")
  return systolicInstance.new({kind="module",module=self,name=name,callsites={}})
end

local function checkArgList( fn, args, calltable )
  assert(systolicFunction.isSystolicFunction(fn))

  calltable.type = darkroom.type.null()
  if fn.output~=nil then calltable.type=fn.output.type end

  if fn.inputs==nil or keycount(fn.inputs)==0 then
    assert(args==nil or keycount(args)==0)
    return true
  end

  assert(type(args)=="table")
  assert(systolicAST.isSystolicAST(args)==false)
  assert(type(calltable)=="table")
  local correct = keycount(args)==keycount(fn.inputs)

  map(fn.inputs, function(v,k) 
        assert(systolicInstance.isSystolicInstance(v))
        correct = correct and args[v.name]~=nil and (args[v.name].type==v.type)
        calltable["input"..k] = args[v.name]
                 end)
  
  if correct==false then
    print("Error, pure function call incorrect argument type, function", fn.name,"module",fn.module.name)
    print("Expected:")
    map(fn.inputs,function(v,k) print(v.name..":"..tostring(v.type)) end)
    print("Actual:")
    map(args,function(v,k) print(k..":"..tostring(v.type)) end)
    assert(false)
  end
end

systolicFunctionFunctions = {}
systolicFunctionMT={__index=systolicFunctionFunctions
--                    __call = function(self,args) -- args is a table of key,value pairs for the named arguments
--                      assert(self.pure)
--                      local t = {kind="call",func=self,pure=true,type=self.outputtype,valid="placeholder"}
--                      checkArgList( self, args, t)
--                      return systolicAST.new(t):setLinenumber(0):setOffset(0):setFilename("")
--                    end
}

systolicFunction = {}
function systolicFunction.isSystolicFunction(t)
  return getmetatable(t)==systolicFunctionMT
end

function systolic.makeFunction(name, inputs, output, valid)
  assert(type(inputs)=="table")
  assert(#inputs==keycount(inputs))
  for k,v in ipairs(inputs) do assert(type(k)=="number");assert(systolicInstance.isSystolicInstance(v));assert(v.kind=="input") end
  assert(systolicInstance.isSystolicInstance(output) or output==nil)

  if valid==nil then
    valid = systolic.input("valid",darkroom.type.bool())
  end

  local t = {name=name, inputs=inputs, output=output, assignments={}, asserts={}, usedInstanceNames = {}, instanceMap = {}, valid=valid:read()}

  t.instanceMap[valid] = 1
  t.usedInstanceNames[valid.name] = 1

  if output~=nil then
    t.instanceMap[output] = 1
    t.usedInstanceNames[output.name] = 1
  end

  map(inputs, function(n) assert(t.instanceMap[n]==nil);
        assert(t.usedInstanceNames[n.name]==nil);
        t.instanceMap[n] = 1;
        t.usedInstanceNames[n.name] = 1
              end)

  return setmetatable(t,systolicFunctionMT)
end

function systolicModuleFunctions:addFunction( name, inputs, output, options )
  assert(type(name)=="string")

  local valid = systolic.input(name.."_valid", darkroom.type.bool())
  local fn = systolic.makeFunction( name, inputs, output, valid )

  assert(systolicFunction.isSystolicFunction(fn))
  if self.usedInstanceNames[fn.name]~=nil then
    print("Error, function name "..fn.name.." already in use")
    assert(false)
  end

  self.functions[fn.name]=fn
  fn.module = self

  if options~=nil and options.pipeline~=nil and options.pipeline==false then 
    fn.pipeline = false 
  else
    fn.pipeline = true
  end

  if type(options)=="table" then fn.verilogDelay = options.verilogDelay end

  return fn
end

function systolicFunctionFunctions:addAssign( dst, expr )
  assert(systolicInstance.isSystolicInstance(dst) or (dst.kind=="output" or dst.kind=="reg"))
  expr = convert(expr)
  table.insert(self.assignments,{dst=dst,expr=expr})
end

function systolicFunctionFunctions:addAssignBy( op, dst, expr, expr2, expr3 )
  assert(type(op)=="string")
  assert(dst.kind=="reg")
  expr = convert(expr)
  if expr2~=nil then expr2=convert(expr2) end
  if expr3~=nil then expr3=convert(expr3) end
  table.insert(self.assignments,{dst=dst,expr=expr, expr2=expr2, expr3=expr3, by=op})
end

function systolicFunctionFunctions:writeRam128( ram128, addr, expr )
  assert(systolicInstance.isSystolicInstance(ram128))
  assert(ram128.kind=="ram128")
  addr = convert(addr)
  expr = convert(expr)

  table.insert( self.assignments, { dst=ram128, expr=expr, addr=addr } )
end

function systolicFunctionFunctions:bramWriteAndReturnOriginal( bram, addr, expr, ty )
  assert( systolicInstance.isSystolicInstance(bram) )
  assert( darkroom.type.isType(ty) )
  assert(bram.kind=="bram")
  addr = convert(addr)
  expr = convert(expr)

  if bram.typeA~=nil then
    print("Error, double assign to bram")
    assert(false)
  end

  bram.typeA = ty

  table.insert( self.assignments, { dst=bram, expr=expr, addr=addr, op="writeAndReturnOriginal" } )

  return systolicAST.new({kind="bram", inst=bram, writeAddr = addr, writeExpr = expr, portMode="writeAndReturnOriginal", type = ty}):copyMetadataFrom(expr)
end

local function codegen(ast, callsiteId)
  assert(systolicAST.isSystolicAST(ast))
  assert(type(callsiteId)=="number" or callsiteId==nil)

  local callsite = ""
  if type(callsiteId)=="number" then callsite = "C"..callsiteId.."_" end

  local delay = {}
  local finalOut = ast:visitEach(
    function(n, args)
      local inputs = {}
      local inputResDeclarations = {}
      local inputResClockedLogic = {}
      local thisDelay = 0

      map( args, function(v,k) inputResDeclarations[k]=v[2]; inputResClockedLogic[k]=v[3]; end)

      -- 'used' are declarations from inputs that we actually end up using
      -- 'res' are declarations from this node
      local usedResDeclarations = {}
      local usedResDeclarationsSeen = {}
      local usedResClockedLogic = {}
      local usedResClockedLogicSeen = {}
      local resDeclarations = {}
      local resClockedLogic = {}

      local usedInputs = {}
      local function addInput(key)
        usedInputs[key] = 1
        for k,v in pairs(inputResDeclarations[key]) do
          if usedResDeclarationsSeen[v]==nil then
            table.insert(usedResDeclarations,v)
          end
          usedResDeclarationsSeen[v] = 1
        end

        for k,v in pairs(inputResClockedLogic[key]) do
          if usedResClockedLogicSeen[v]==nil then
            table.insert(usedResClockedLogic,v)
          end
          usedResClockedLogicSeen[v] = 1
        end
      end

      local function getInputs()
        local maxd = foldl( math.max, 0, stripkeys(map( usedInputs, function(v,k) return delay[n[k]] end )) )
        
        if delay[n]~=nil and maxd~=delay[n] then print("delay shouldn't change if we call getInputs multiple times! declare _all_ your inputs upfront before calling this"); assert(false) end
        delay[n] = maxd

        for k,_ in pairs(usedInputs) do
          -- need to do a deep copy of the table of outputs (b/c this is shared between nodes)
          for c,v in ipairs(args[k][1]) do 
            if c==1 then inputs[k]={} end
            inputs[k][c]=v 
          end

          local input = n[k]
          local delayby = maxd-delay[input]

          if type(n[k].constLow_1)=="number" and n[k].constLow_1==n[k].constHigh_1 then
            -- this is something with a constant value, so we don't need to retime it
            delayby = 0
          end

          for d=1,delayby do
            for c=1,input.type:channels() do
              -- type is determined by producer, b/c consumer op can change type
              local const = type(n[k].constLow_1)=="number" and n[k].constLow_1==n[k].constHigh_1
              if input.type~=darkroom.type.null() and const==false then
                local decl = declareReg( input.type:baseType(), inputs[k][c].."_retime"..d, "")
                local cl = inputs[k][c].."_retime"..d.." <= "..sel(d>1,inputs[k][c].."_retime"..(d-1),inputs[k][c]).."; // retiming\n"
                table.insert(usedResDeclarations, decl)
                table.insert(usedResClockedLogic, cl)
              end
            end
          end
          if delayby>0 then
            for c=1,input.type:channels() do
              local const = type(n[k].constLow_1)=="number" and n[k].constLow_1==n[k].constHigh_1
              if const==false then
                 inputs[k][c] = inputs[k][c].."_retime"..delayby
              end
            end
          end
        end
      end

      local finalOut = {}

      local function addstat( pipeline, dst, expr )
        assert(type(pipeline)=="boolean")
        assert(type(dst)=="string")
        assert(type(expr)=="string")
        
        if pipeline then
          table.insert(resClockedLogic, dst.." <= "..expr)
        else
          table.insert(resDeclarations, "assign "..dst.." = "..expr)
        end
      end

      for c=1,n.type:channels() do
        local res

        if n.kind=="binop" then
          addInput("lhs")
          addInput("rhs")
          getInputs()

          if n.pipeline then
            thisDelay = 1
            table.insert(resDeclarations, declareReg( n.type:baseType(), callsite..n:cname(c),"", " // binop "..n.op.." result" ))
          else
            thisDelay = 0
            table.insert(resDeclarations, declareWire( n.type:baseType(), callsite..n:cname(c),"", " // binop "..n.op.." result" ))
          end

          if n.op=="<" or n.op==">" or n.op=="<=" or n.op==">=" then
            if n.type:baseType():isBool() and n.lhs.type:baseType():isInt() and n.rhs.type:baseType():isInt() then
              addstat( n.pipeline, callsite..n:name().."_c"..c, "($signed("..inputs.lhs[c]..")"..n.op.."$signed("..inputs.rhs[c].."));\n")
            elseif n.type:baseType():isBool() and n.lhs.type:baseType():isUint() and n.rhs.type:baseType():isUint() then
              addstat( n.pipeline, callsite..n:name().."_c"..c, "(("..inputs.lhs[c]..")"..n.op.."("..inputs.rhs[c].."));\n")
            else
              print( n.type:baseType():isBool() , n.lhs.type:baseType():isInt() , n.rhs.type:baseType():isInt(),n.type:baseType():isBool() , n.lhs.type:baseType():isUint() , n.rhs.type:baseType():isUint())
              assert(false)
            end
          elseif n.type:isBool() then
            local op = binopToVerilogBoolean[n.op]
            if type(op)~="string" then print("OP_BOOLEAN",n.op); assert(false) end
            addstat(n.pipeline, callsite..n:name().."_c"..c, inputs.lhs[c]..op..inputs.rhs[c]..";\n")
          else
            local op = binopToVerilog[n.op]
            if type(op)~="string" then print("OP",n.op); assert(false) end
            local lhs = inputs.lhs[c]
            if n.lhs.type:baseType():isInt() then lhs = "$signed("..lhs..")" end
            local rhs = inputs.rhs[c]
            if n.rhs.type:baseType():isInt() then rhs = "$signed("..rhs..")" end
            addstat( n.pipeline, callsite..n:name().."_c"..c, lhs..op..rhs..";\n")
          end

          res = callsite..n:name().."_c"..c
        elseif n.kind=="unary" then
          addInput("expr")
          getInputs()
          thisDelay = 1

          if n.op=="abs" then
            if n.type:baseType():isInt() then
              table.insert(resDeclarations, declareReg( n.type:baseType(), callsite..n:cname(c) ))
              table.insert(resClockedLogic, callsite..n:cname(c).." <= ("..inputs.expr[c].."["..(n.type:baseType():sizeof()*8-1).."])?(-"..inputs.expr[c].."):("..inputs.expr[c].."); //abs\n")
              res = callsite..n:cname(c)
            else
              return inputs.expr[c] -- must be unsigned
            end
          elseif n.op=="-" then
            assert(n.type:baseType():isInt())
            table.insert(resDeclarations, declareReg(n.type:baseType(), callsite..n:cname(c)))
            table.insert(resClockedLogic, callsite..n:cname(c).." <= -"..inputs.expr[c].."; // unary sub\n")
            res = callsite..n:cname(c)
          else
            print(n.op)
            assert(false)
          end
        elseif n.kind=="select" or n.kind=="vectorSelect" then
          addInput("cond"); addInput("a"); addInput("b");
          getInputs()

          if n.pipeline then
            thisDelay = 1
            table.insert( resDeclarations, declareReg( n.type:baseType(), callsite..n:cname(c), "", " // "..n.kind.." result" ))
          else
            thisDelay = 0
            table.insert( resDeclarations, declareWire( n.type:baseType(), callsite..n:cname(c), "", " // "..n.kind.." result" ))
          end

          local condC = 1
          if n.kind=="vectorSelect" then condC=c end

          --table.insert(resClockedLogic, callsite..n:cname(c).." <= ("..inputs.cond[condC]..")?("..inputs.a[c].."):("..inputs.b[c].."); // "..n.kind.."\n")
          addstat( n.pipeline, callsite..n:cname(c), "("..inputs.cond[condC]..")?("..inputs.a[c].."):("..inputs.b[c].."); // "..n.kind.."\n") 
          res = callsite..n:cname(c)
        elseif n.kind=="cast" then
          addInput("expr")
          getInputs()
          local expr
          local cmt = " // cast "..tostring(n.expr.type).." to "..tostring(n.type)

          local function dobasecast( expr, fromType, toType )
            assert(type(expr)=="string")

            if fromType:isUint() and (toType:isInt() or toType:isUint()) and fromType.precision <= toType.precision then
              -- casting smaller uint to larger or equal int or uint. Don't need to sign extend
              return expr
            elseif toType:isInt() and fromType:isInt() and toType.precision > fromType.precision then
              -- casting smaller int to larger int. must sign extend
              return "{ {"..(8*(toType:sizeof() - fromType:sizeof())).."{"..expr.."["..(fromType:sizeof()*8-1).."]}},"..expr.."["..(fromType:sizeof()*8-1)..":0]}"
            elseif (fromType:isUint() or fromType:isInt()) and (toType:isInt() or toType:isUint()) and fromType.precision>toType.precision then
              -- truncation. I don't know how this works
              return expr
            elseif fromType:isInt() and toType:isUint() and fromType.precision == toType.precision then
              -- int to uint with same precision. I don't know how this works
              return expr
            else
              print("FAIL TO CAST",fromType,"to",toType)
              assert(false)
            end
          end

          if n.type:isArray() and n.expr.type:isArray()==false then
            expr = inputs["expr"][1] -- broadcast
            cmt = " // broadcast "..tostring(n.expr.type).." to "..tostring(n.type)
          elseif n.expr.type:isArray() and n.type:isArray()==false and n.expr.type:arrayOver():isBool() and (n.type:isUint() or n.type:isInt()) then
            -- casting an array of bools (bitfield) to an int or uint
            expr = "}"
            for c=1,n.expr.type:channels() do
              if c>1 then expr = ","..expr end
              expr = inputs.expr[c]..expr
            end
            expr = "{"..expr
          elseif n.type:isArray() and n.expr.type:isArray() and n.type:baseType()==n.expr.type:baseType() then
            assert(n.type:channels() == n.expr.type:channels())
            expr = inputs.expr[c]
            cmt = " // cast, array size change from "..tostring(n.expr.type).." to "..tostring(n.type)
          elseif n.type:isArray() and n.expr.type:isArray()  then
            assert(n.type:arrayLength() == n.expr.type:arrayLength())
            -- same shape arrays, different base types
            expr = dobasecast( inputs.expr[c], n.expr.type:baseType(), n.type:baseType() )
          else
            expr = dobasecast( inputs.expr[c], n.expr.type, n.type )
          end

          
          table.insert(resDeclarations, declareWire( n.type:baseType(), callsite..n:cname(c), "",cmt))
          table.insert(resDeclarations, "assign "..callsite..n:cname(c).." = "..expr..";"..cmt.."\n")
          res = callsite..n:cname(c)
        elseif n.kind=="value" then
          getInputs()
          local v
          if type(n.value)=="table" then 
            v = valueToVerilog(n.value[c], n.type:baseType()) 
          else
            v = valueToVerilog(n.value, n.type:baseType())
          end
--          table.insert(resDeclarations,declareWire( n.type:baseType(), callsite..n:cname(c), v, " //value" ))
--          res = callsite..n:cname(c)
          res = "("..v..")"
        elseif n.kind=="array" then
          map( range(n.type:channels()), function(c) addInput("expr"..c) end )
          getInputs()
          res = inputs["expr"..c][1]
        elseif n.kind=="index" then
          addInput("expr")
          getInputs()

          if n.expr.type:isArray() then
            local flatIdx = 0

            local dim = 1
            local scalefactor = 1
            while n["index"..dim] do
              assert(n["index"..dim].constLow_1 == n["index"..dim].constHigh_1)
              flatIdx = flatIdx + (n["index"..dim].constLow_1)*scalefactor
              scalefactor = scalefactor*(n.expr.type:arrayLength())[dim]
              dim = dim + 1
            end
            
            res = inputs["expr"][flatIdx+1]
          elseif n.expr.type:isUint() or n.expr.type:isInt() then
            table.insert( resDeclarations, declareWire( n.type:baseType(), n:cname(c), "", " // index result" ))
            table.insert( resDeclarations, "assign "..n:cname(c).." = "..inputs["expr"][c].."["..n.index1.constLow_1.."]; // index\n")
            res = n:cname(c)
          else
            print(n.expr.type)
            assert(false)
          end
          
--[=[          else
            for k,v in pairs(n) do print(k,v) end
            local range = n.index:eval(1,kernel)
            -- synth a reduction tree to select the element we want
            local rname, rmod = fpga.modules.reduce(compilerState, "valid", range:bbArea(), n.type)
            result = concat(rmod, result)
            table.insert(resDeclarations, declareWire(n.type, n:cname(c),"", "// index result"))
            local str = rname.." indexreduce_"..n:cname(c).."(.CLK(CLK),.out("..n:cname(c)..")"
            for i=range:min(1), range:max(1) do
              local idx = i-range:min(1)
              str = str..",.partial_"..idx.."("..inputs["expr"][i+1]..")"
              str = str..",.partial_valid_"..idx.."("..n.index:codegenHW(kernel).." == "..valueToVerilogLL(i,true,32)..")"
            end
            table.insert(resDeclarations,str..");\n")
            res = n:cname(c)
          end]=]
        elseif n.kind=="readinput" then
          getInputs()
          if n.type:channels()==1 then
            res = callsite..n.inst.name
          else
            table.insert(resDeclarations, declareWire(n.type:baseType(), n:cname(c),"", "// input"))
            table.insert(resDeclarations, "assign "..n:cname(c).." = "..callsite..n.inst.name..channelIndex( n.inst.type, c).."; // input \n")
            res = n:cname(c)
          end
        elseif n.kind=="reg" then
          for i=1,n.writeCount do
            addInput("expr1_"..i)
            if n["expr2_"..i]~=nil then addInput("expr2_"..i) end
            if n["expr3_"..i]~=nil then addInput("expr3_"..i) end
            addInput("valid"..i)
          end
          getInputs()

          local dbg=true

          for i=1,n.writeCount do
            if dbg and n.writeCount>1 then
              table.insert(resDeclarations, declareWire( darkroom.type.uint(16), n:cname(c).."_validCheck"..i,""," // valid arbitration"))
              if i==1 then table.insert( resDeclarations, "assign "..n:cname(c).."_validCheck"..i.." = "..inputs["valid"..i][1]..";\n") end
              if i>1 then table.insert( resDeclarations, "assign "..n:cname(c).."_validCheck"..i.." = "..n:cname(c).."_validCheck"..(i-1).." + "..inputs["valid"..i][1].."; // valid arbitration\n") end
              if i==n.writeCount then table.insert( resDeclarations, "always @ (posedge CLK) begin if ("..n:cname(c)..[[_validCheck]]..i..[[>1) begin $display("Multiple write to same signal ]]..n.inst.name..[["); $stop(); end end]].."\n") end
            end

            if n["by"..i]=="always" then
              table.insert(resClockedLogic, "if ("..inputs["valid"..i][1]..") begin "..n.inst.name..channelIndex( n.inst.type, c).." <= "..inputs["expr1_"..i][c].."; end  // function register assignment\n")
            elseif n["by"..i]=="sum" then
              table.insert(resClockedLogic, "if ("..inputs["valid"..i][1]..") begin "..n.inst.name..channelIndex( n.inst.type, c).." <= "..n.inst.name.."+"..inputs["expr1_"..i][c].."; end  // function register assignment by sum\n")
            elseif n["by"..i]=="sumwrap" then
              local wrapto = valueToVerilog(0,n.type)
              if n["expr3_"..i]~=nil then wrapto = inputs["expr3_"..i][1] end
              
              table.insert(resClockedLogic, "if ("..inputs["valid"..i][1]..") begin "..n.inst.name.." <= ("..n.inst.name.."=="..inputs["expr2_"..i][1]..")?("..wrapto.."):("..n.inst.name.."+"..inputs["expr1_"..i][1].."); end  // function register assignment by sumwrap\n")
            else
              print("BY",n["by"..i])
              assert(false)
            end
            
            if n.type:channels()>1 then
              table.insert(resDeclarations, declareWire(n.type:baseType(), n:cname(c),"", "// register output channelselect"))
              table.insert(resDeclarations, "assign "..n:cname(c).." = "..n.inst.name..channelIndex( n.inst.type, c).."; // register output channelselect\n")
              res = n:cname(c)
            else
              res = n.inst.name
            end
          end
        elseif n.kind=="ram128" then
          assert(n.writeCount==1)
          addInput("readAddr")
          addInput("writeAddr1")
          addInput("valid1")
          addInput("writeExpr1")
          getInputs()

          table.insert(resDeclarations,"assign "..n.inst.name.."_readAddr = "..inputs.readAddr[1]..";\n")
          table.insert(resDeclarations,"assign "..n.inst.name.."_writeAddr = "..inputs.writeAddr1[1]..";\n")
          table.insert(resDeclarations,"assign "..n.inst.name.."_WE = "..inputs.valid1[1]..";\n")
          table.insert(resDeclarations,"assign "..n.inst.name.."_D = "..inputs.writeExpr1[1]..";\n")
          res = n.inst.name.."_readOut"
        elseif n.kind=="call" then
          
          if n.func.verilogDelay~=nil then
            thisDelay = n.func.verilogDelay
          else
            thisDelay = n.inst:getDelay(n.func)
          end

          if n.pipeline==false and thisDelay>0 then
            print("Error, calling pipelined function ",n.func.name," in a section of code w/ pipeling disabled, module",n.inst.name)
            assert(false)
          end

          systolic.addDefinition( n.inst )
          if n.func:isPure()==false then addInput("valid") end
          map( n.func.inputs, function(v,k) addInput("input"..k) end)
          getInputs()
          
          local call_callsite = ""
          if #n.inst.callsites[n.func.name]>1 then
            call_callsite = "C"..n.callsiteid.."_"
          end
          
          if n.func:isPure()==false then
            table.insert(resDeclarations, "assign "..n.inst.name.."_"..call_callsite..n.func.name.."_valid = "..inputs.valid[1].."; // call valid\n")
          end
          
          map(n.func.inputs, function(v,k) 
                for cc=1,n["input"..k].type:channels() do
                  table.insert(resDeclarations, "assign "..n.inst.name.."_"..call_callsite..v.name..channelIndex(n["input"..k].type, cc).." = "..inputs["input"..k][cc].."; // call input\n") 
                end
                             end)
          
          if n.func.output~=nil and n.type:channels()==1 then
            res = n.inst.name.."_"..n.func.output.name
          elseif n.func.output~=nil and n.type:channels()>1 then
            table.insert(resDeclarations, declareWire(n.type:baseType(), n:cname(c),"", "// call output channelselect"))
            table.insert(resDeclarations, "assign "..n:cname(c).." = "..n.inst.name.."_"..n.func.output.name..channelIndex(n.type,c).."; // call output channelselect\n")
            res = n:cname(c)
          else
            res = "__NILVALUE_ERROR"
          end

        elseif n.kind=="fndefn" then
          n:map( "dst", function(n,k) addInput("expr"..k) end)
          n:map( "assert", 
                 function(_,k) 
                   addInput("assert"..k) 
                   n:map( "assert"..k.."_expr", function(nn,kk) addInput("assert"..k.."_expr"..kk) end)
                 end)
          if n.fn:isPure()==false then addInput("valid") end
          getInputs()


          table.insert(resDeclarations,"  // function: "..n.fn.name.." callsites "..n.callsites.." delay "..delay[n]..", pure="..tostring(n.fn:isPure()).."\n")

          if n.callsites>1 and (n.fn:isAccessor()==false or n.fn:isPure()==false) then
            table.insert(resDeclarations," // merge: "..n.fn.name.."\n")
            assert(n.fn:isAccessor())

            -- valid bit merge
            if n.fn:isPure()==false then
              table.insert(resDeclarations, declareWire(darkroom.type.bool(),n.fn.name.."_valid",""," // valid bit merge"))
              table.insert(resDeclarations, "assign "..n.fn.name.."_valid = C1_"..n.fn.name.."_valid; // valid bit merge (chosen arbitrarily)\n")
              for id=2,n.callsites do
                table.insert(resDeclarations,"always @ (posedge CLK) begin if ("..n.fn.name.."_valid!=C"..id..[[_]]..n.fn.name..[[_valid) begin $display("ERROR, ]]..n.fn.name..[[ valid doesnt match, function ]]..n.fn.name..[[, module ]]..n.fn.module.name..[["); $stop(); end end]].."\n")
                
              end
            end
          end

          local assn = 1
          while n["dst"..assn] do
            if n["dst"..assn].kind=="output" then
              for c=1,n["expr"..assn].type:channels() do
                table.insert(resDeclarations, "assign "..callsite..n["dst"..assn].name..channelIndex(n["dst"..assn].type,c).." = "..inputs["expr"..assn][c]..";  // function output assignment\n")
              end
            end
            assn = assn + 1
          end

          local asst = 1
          while n["assert"..asst] do
            assert(n.fn:isPure()==false)
            local asstStr = "always @ (posedge CLK) begin if ("..inputs.valid[1].." && "..inputs["assert"..asst][1]..[[==1'd0) begin $display("ASSERT FAILED, function ]]..n.fn.name..[[, module ]]..n.fn.module.name..[[,]]..n["assertError"..asst]..[[ inst %s",]]
            n:map( "assert"..asst.."_expr", function(_,k) asstStr = asstStr..inputs["assert"..asst.."_expr"..k][1].."," end)
            asstStr = asstStr..[[INSTANCE_NAME); $stop(); end end]].."\n"

            table.insert(resDeclarations, asstStr)
            asst = asst + 1
          end

          res = "_ERR_NULL_FNDEFN"
        elseif n.kind=="module" then
          local i = 1
          while n["fn"..i] do
            addInput("fn"..i)
            i = i + 1
          end
          getInputs()
          res = "__ERR_NULL_MODULE"
        elseif n.kind=="bram" then
          if n.portMode=="writeAndReturnOriginal" then
            addInput("writeAddr")
            addInput("valid")
            addInput("writeExpr")
            getInputs()

            thisDelay = 1
            table.insert(resDeclarations,"assign "..n.inst.name.."_addr = "..inputs.writeAddr[1]..";\n")
            table.insert(resDeclarations,"assign "..n.inst.name.."_WE = "..inputs.valid[1]..";\n")
            table.insert(resDeclarations,"assign "..n.inst.name.."_DI = "..inputs.writeExpr[1]..";\n")
           res = n.inst.name.."_DO"
          else
            assert(false)
          end
        else
          print(n.kind)
          assert(false)
        end

        if n.pipeline==false and thisDelay>0 then
          print("Error, something that shouldn't be pipelined is! kind ",n.kind)
          assert(false)
        end

        assert(type(res)=="string")
        assert(res:match("[%w%[%]]")) -- should only be alphanumeric
        finalOut[c] = res
      end

      assert(keycount(finalOut)>0)
      delay[n] = delay[n] + thisDelay
      return {finalOut, concat(usedResDeclarations, resDeclarations), concat(usedResClockedLogic, resClockedLogic)}
    end)

  local resDeclarations = finalOut[2]
  local resClockedLogic = finalOut[3]
  finalOut = finalOut[1]

  return resDeclarations, resClockedLogic, finalOut, delay
end

function systolicInstanceFunctions:getDelay(fn)
  local _, fndelays = self:codegen()
  local d = fndelays[fn]
  assert(type(d)=="number")
  return d
end


-- some functions don't modify state. These do not need a valid bit
function systolicFunctionFunctions:isPure()
  return foldl( andop, true, map( self.assignments, function(n) return n.dst.kind=="output" end ) )
end

function systolicFunctionFunctions:isAccessor()
  return #self.inputs==0
end

function systolicFunctionFunctions:addAssert( cond,  s, ...)
  assert(systolicAST.isSystolicAST(cond))
  assert(type(s)=="string")

  local asst = {cond=cond,error=s,expr={}}

  for k,v in ipairs({...}) do
    table.insert(asst.expr, v)
  end

  table.insert(self.asserts, asst )
end


function systolicFunctionFunctions:getDefinitionKey()
  assert(self.pure)
  return self
end

local __instCodegenCache = {}
function systolicInstanceFunctions:codegen()
  assert(self.kind=="module")

  if __instCodegenCache[self]==nil then
    local code, finalOut, fndelays = self:lower():toVerilog({})
    __instCodegenCache[self] = {code, fndelays}
  end
  
  return __instCodegenCache[self][1], __instCodegenCache[self][2]
end

function systolicInstanceFunctions:lower()
  local mod = {kind="module", type=darkroom.type.null()}
  local modfncnt = 1

  local metadata
  for _,fn in pairs(self.module.functions) do
    if type(self.callsites[fn.name])=="table" then -- only codegen stuff we actually used
      
      local node = {kind="fndefn", callsites=#self.callsites[fn.name],fn=fn,type=darkroom.type.null(),valid=fn.valid}
      
      local cnt = 1
      local drivenOutput = false
      for _,assn in pairs( fn.assignments ) do
        metadata = assn.expr
        if fn.output~=nil and assn.dst==fn.output then 
          drivenOutput = true 
          node["dst"..cnt] = assn.dst
          if fn.pipeline then
            node["expr"..cnt] = assn.expr
          else
            node["expr"..cnt] = assn.expr:disablePipelining()
          end

          cnt = cnt+1
        elseif assn.dst.kind=="reg" then
        elseif assn.dst.kind=="ram128" then
        elseif assn.dst.kind=="bram" then
        else
          print(assn.dst.kind)
          assert(false)
        end

        assn.expr:checkVariables( {fn, self.module} )
      end
      
      local acnt = 1
      for _,asst in pairs( fn.asserts ) do
        node["assert"..acnt] = asst.cond:disablePipelining()
        node["assertError"..acnt] = asst.error

        for k,v in ipairs(asst.expr) do
          node["assert"..acnt.."_expr"..k] = v
        end

        acnt = acnt + 1
      end

      if drivenOutput==false and fn.output~=nil  then
        print( "undriven output, function", fn.name )
        if self.module~=nil then print( "module", self.module.name ) end
        assert(false)
      end

      node = systolicAST.new(node):copyMetadataFrom( metadata )
      mod["fn"..modfncnt] = node
      modfncnt = modfncnt+1
    end
  end

  mod = systolicAST.new(mod):copyMetadataFrom(metadata)

  -- drive the inputs to the registers, rams, etc
  -- we have to do two passes here b/c in the first part we drop in expressions that may include
  -- register reads, which we also need to tie to the correct input.

  local rwnodes = {} -- inst -> ast node

  for _,fn in pairs(self.module.functions) do
    if type(self.callsites[fn.name])=="table" then -- only codegen stuff we actually used
      for _,assn in pairs( fn.assignments ) do
        if fn.output~=nil and assn.dst==fn.output then 
        elseif assn.dst.kind=="reg" or assn.dst.kind=="ram128" then
          assn.expr:S(assn.dst.kind):process(
            function(n)
              if n.inst==assn.dst then
                print("Error, "..assn.dst.kind.." can't be assigned to themselves. Use increment")
                print("module",self.module.name,"function",fn.name,assn.dst.kind,assn.dst.name)
                assert(false)
              end
            end)
            
          fn.valid:S(assn.dst.kind):process(
            function(n)
              if n.inst==assn.dst then
                print("Error, "..assn.dst.kind.." can't be their own valid bit")
                print("module",self.module.name,"function",fn.name,assn.dst.kind,assn.dst.name)
                assert(false)
              end
            end)

          local n = rwnodes[assn.dst] or {kind=assn.dst.kind, inst=assn.dst, writeCount = 0}
          local alreadyAssigned = false

          local i = 1
          while n["assn"..i] do
            alreadyAssigned = (alreadyAssigned or n["assn"..i]==assn)
            i=i+1
          end

          n.writeCount = n.writeCount + 1
          local i = n.writeCount
          assert(systolicAST.isSystolicAST(assn.expr))

          if assn.dst.kind=="ram128" then
            n["writeExpr"..i] = assn.expr
            n["writeAddr"..i] = assn.addr
          elseif assn.dst.kind=="reg" then
            n["expr1_"..i] = assn.expr
            n["expr2_"..i] = assn.expr2
            n["expr3_"..i] = assn.expr3
          else
            assert(false)
          end

          n["valid"..i] = fn.valid
          n["assn"..i] = assn
          n["by"..i] = assn.by or "always"

          if n.writeCount>1 and self.module.options.assignArbitrate==false then
            print("Double Write to ",assn.dst.kind,n.inst.name)
            assert(false)
          end
 assert(type(n.writeCount)=="number")
          rwnodes[n.inst] = n
        elseif assn.dst.kind=="bram" then
          assert( rwnodes[assn.dst] == nil )
          local n = {kind="bram"}
          n.valid = fn.valid
          n.inst = assn.dst

          rwnodes[n.inst] = n
        else
          assert(false)
        end
          
      end
    end
  end

  local found = {} -- inst -> 1

  local function replaceRams(m)
    return m:S("reg ram128 bram"):process(
      function(n)
        found[n.inst] = 1
        local nn = rwnodes[n.inst]

        if nn==nil then
         print("ERR, ", n.kind, n.inst.name, "module", self.module.name, "is not assigned to?")
         assert(false)       
        end

        local r = n:shallowcopy()
        for k,v in pairs(nn) do
          -- just clobber any existing data. whatev
          r[k] = v
        end

        r.done = true
        return systolicAST.new(r):copyMetadataFrom(n)
     end)
  end

  -- iterate until convergence
  local done = false
  while done==false do
    done = true
    rwnodes =  map( rwnodes, function(v) return map( v, function(n) if systolicAST.isSystolicAST(n) then return replaceRams(n) else return n end end) end)

     map( rwnodes, function(v) map( v, function(n) if systolicAST.isSystolicAST(n) then 
n:S("reg ram128 bram"):process(function(nn) 
if nn.done==nil then done=false end
 end)
 end end) end)
  end

  mod = replaceRams(mod)

  for inst,v in pairs(rwnodes) do
    if found[inst]==nil then
      print("Error, ",inst.kind, inst.assn1.dst.name,"function",fn.name,"is never read from. bug?")
    end
  end

  return mod
end

local function binop(lhs, rhs, op)
  lhs = convert(lhs)
  rhs = convert(rhs)
  return typecheck(darkroom.ast.new({kind="binop",op=op,lhs=lhs,rhs=rhs}):copyMetadataFrom(lhs))
end

local function unary(expr, op)
  expr = convert(expr)
  return typecheck(darkroom.ast.new({kind="unary",op=op,expr=expr}):copyMetadataFrom(expr))
end

systolic._callsites = {}
systolicInstance = {}
function systolicInstance.new(tab)
  return setmetatable(tab,systolicInstanceMT)
end

function systolicInstance.isSystolicInstance(tab)
  return getmetatable(tab)==systolicInstanceMT
end

function systolicInstanceFunctions:toVerilog()
  if self.kind=="reg" then
    return declareReg(self.type, self.name, self.initial)
  elseif self.kind=="ram128" then
    return [[ wire ]]..self.name..[[_WE;
wire ]]..self.name..[[_D;
wire ]]..self.name..[[_writeOut;
wire ]]..self.name..[[_readOut;
wire [6:0] ]]..self.name..[[_writeAddr;
wire [6:0] ]]..self.name..[[_readAddr;
RAM128X1D ]]..self.name..[[  (
  .WCLK(CLK),
  .D(]]..self.name..[[_D),
  .WE(]]..self.name..[[_WE),
  .SPO(]]..self.name..[[_writeOut),
  .DPO(]]..self.name..[[_readOut),
  .A(]]..self.name..[[_writeAddr),
  .DPRA(]]..self.name..[[_readAddr));
]]
  elseif self.kind=="bram" then
    local conf={name=self.name}
    conf.A={chunk=self.typeA:sizeof(),
           DI = self.name.."_DI",
           DO = self.name.."_DO",
           ADDR = self.name.."_addr",
           CLK = "CLK",
           WE = self.name.."_WE",
           readFirst = true}
    conf.B={chunk=self.typeA:sizeof(),
           DI = self.name.."_DI_B",
           DO = self.name.."_DO_B",
           ADDR = self.name.."_addr_B",
           CLK = "CLK",
           WE = "1'd0",
           readFirst = true}
    local addrbits = 10 - math.log(self.typeA:sizeof())/math.log(2)
    return [[wire ]]..self.name..[[_WE;
wire []]..(self.typeA:sizeof()*8-1)..":0]"..self.name..[[_DI;
wire []]..(self.typeA:sizeof()*8-1)..":0]"..self.name..[[_DI_B;
wire []]..(self.typeA:sizeof()*8-1)..":0]"..self.name..[[_DO;
wire []]..(self.typeA:sizeof()*8-1)..":0]"..self.name..[[_DO_B;
wire []]..addrbits..[[:0] ]]..self.name..[[_addr;
wire []]..addrbits..[[:0] ]]..self.name..[[_addr_B;
]]..table.concat(fixedBram(conf))
  elseif self.kind=="module" then
    local wires = {}
    local arglist = {}
    
    for fnname,fn in pairs(self.module.functions) do
      if self.callsites[fnname]~=nil then
        local callsitecnt = #self.callsites[fnname]
        if fn:isPure() and fn:isAccessor() then callsitecnt=1 end

        for id=1,callsitecnt do
          local callsite = "C"..id.."_"
          if callsitecnt==1 then callsite="" end
          if fn:isPure()==false then 
            table.insert(wires,declareWire( darkroom.type.bool(), self.name.."_"..callsite..fnname.."_valid" ))
            table.insert(arglist,", ."..callsite..fnname.."_valid("..self.name.."_"..callsite..fnname.."_valid)") 
          end

          map(fn.inputs, function(v) table.insert(wires,declareWire( v.type, self.name.."_"..callsite..v.name )); table.insert(arglist,", ."..v.name..callsite.."("..self.name.."_"..callsite..v.name..")") end)
        end

        if fn.output~=nil then
          table.insert(wires, declareWire( fn.output.type, self.name.."_"..fn.output.name))
          table.insert(arglist,", ."..fn.output.name.."("..self.name.."_"..fn.output.name..")")
        end
        
      end
    end

    return table.concat(wires)..self:getDefinitionKey()..[[ #(.INSTANCE_NAME("]]..self.name..[[")) ]]..self.name.."(.CLK(CLK)"..table.concat(arglist)..");\n\n"
  else
    assert(false)
  end
end

function systolicInstanceFunctions:getDefinitionKey()
  assert(self.kind=="module")
  local key = self.module.name
  -- for external verilog modules, there is only one verion of them
  if self.module.options.verilog~=nil then return key end
  for k,v in pairs(sort(stripkeys(invertTable(self.module.functions)))) do
    if self.callsites[v]~=nil then
      local callsitecnt = #self.callsites[v]
      -- no inputs or valid bit: we can just ignore callsites
      if self.module.functions[v]:isAccessor() and self.module.functions[v]:isPure() then callsitecnt=1 end
      key = key.."_"..v..callsitecnt
    else
      key = key.."_"..v.."0"
    end
  end
  return key
end

function systolicInstanceFunctions:getDefinition()
  assert(self.kind=="module")
  local t = {}

  if type(self.module.options.verilog)=="table" then
    return self.module.options.verilog
  end

  table.insert(t,"module "..self:getDefinitionKey().."(input CLK")
  
  for fnname,fn in pairs(self.module.functions) do
    if self.callsites[fnname]~=nil then
      local callsitecnt = #self.callsites[fnname]

      for id=1,callsitecnt do
        
        local callsite = "C"..id.."_"
        if #self.callsites[fnname]==1 then callsite="" end
        
        if fn:isPure()==false then table.insert(t,", input "..callsite..fnname.."_valid") end
        
        for _,input in pairs(fn.inputs) do
          table.insert(t,", input ["..(input.type:sizeof()*8-1)..":0] "..callsite..input.name)
        end
        
      end

      if fn.output~=nil then
        table.insert(t,", "..declarePort(fn.output.type,fn.output.name,false))
      end

    end
  end
  table.insert(t,");\n")
  table.insert(t,[[parameter INSTANCE_NAME="INST";]].."\n")
  table.insert(t," // state\n")
  
  for k,v in pairs(self.module.instances) do
    table.insert(t, v:toVerilog() )
  end

  t = concat( t, self:codegen() )

  table.insert(t,"endmodule\n\n")

  return t
end

function systolicInstanceFunctions:read(addr)
  if self.kind=="reg" then
    assert(addr==nil)
    if self.node==nil then
      self.node = typecheck(darkroom.ast.new({kind="reg",inst=self}):setLinenumber(0):setOffset(0):setFilename(""))
    end
    return self.node
  elseif self.kind=="input" then
    assert(addr==nil)
    return typecheck(darkroom.ast.new({kind="readinput",inst=self}):setLinenumber(0):setOffset(0):setFilename(""))
  elseif self.kind=="ram128" then
    addr = convert(addr)
    return typecheck(darkroom.ast.new({kind="ram128",readAddr=addr,inst=self}):setLinenumber(0):setOffset(0):setFilename(""))
  else
    assert(false)
  end
end

systolicInstanceMT={
__index = function(tab,key)
  local v = rawget(tab, key)
  if v ~= nil then return v end
  v = systolicInstanceFunctions[key]

  if v==nil and rawget(tab,"kind")=="module" then
    -- try to find key in function tab
    local fn = rawget(tab,"module").functions[key]
    if fn~=nil then
      return function(self, args, valid)
        assert(type(args)=="table" or args==nil)
        
        tab.callsites[fn.name] = tab.callsites[fn.name] or {}
        table.insert(tab.callsites[fn.name],1)
        if valid==nil then valid="placeholder" end

        local t = { kind="call", inst=self, valid=valid, func=fn, callsiteid = #tab.callsites[fn.name] }
        
        checkArgList( fn, args, t )
        
        return systolicAST.new(t):setLinenumber(0):setOffset(0):setFilename("")
             end
    end
    
  end
  return v
end}

systolicASTFunctions = {}
setmetatable(systolicASTFunctions,{__index=IRFunctions})
systolicASTMT={__index = systolicASTFunctions,
__add=function(l,r) return binop(l,r,"+") end, 
__sub=function(l,r) return binop(l,r,"-") end,
  __newindex = function(table, key, value)
                    darkroom.error("Attempt to modify systolic AST node")
                  end}

function systolicASTFunctions:init()
  setmetatable(self,nil)
  systolicAST.new(self)
end

-- ops
function systolic.index( expr, idx )
  assert(systolicAST.isSystolicAST(expr))
  assert(type(idx)=="table")
  local t = {kind="index", expr=expr}
  map(idx, function(n,i) t["index"..i] = convert(n);  end)
  return typecheck(darkroom.ast.new(t):copyMetadataFrom(expr))
end

-- This is a macro!
-- first, flattens a n-d array into a 1 d array w/ same elements,
-- then indexes into it.
function systolic.flatindex( expr, idx )
  assert(systolicAST.isSystolicAST(expr))
  assert(type(idx)=="number")
  assert( expr.type:isArray() )
  local ty = darkroom.type.array( expr.type:baseType(), expr.type:channels() )
  return systolic.index( systolic.cast( expr, ty ), {idx} )
end

function systolic.cast( expr, ty )
  expr = convert(expr)
  ty = darkroom.type.fromTerraType(ty,0,0,"")

  --assert(systolicAST.isSystolicAST(expr))
  --assert(darkroom.type.isType(ty))
  return typecheck(darkroom.ast.new({kind="cast",expr=expr,type=ty}):copyMetadataFrom(expr))
end

function systolic.value(v)
  assert(type(v)=="number" or type(v)=="boolean")
  local t = darkroom.ast.new({kind="value", value=v}):setLinenumber(0):setOffset(0):setFilename("")
  return typecheck(t)
end

function systolic.array( expr )
  assert(type(expr)=="table")
  assert(#expr>0)
  local t = {kind="array"}
  for k,v in ipairs(expr) do
    assert(systolicAST.isSystolicAST(v))
    t["expr"..k] = v
  end
  return typecheck(darkroom.ast.new(t):copyMetadataFrom(expr[1]))
end

function systolic.select( cond, a, b )
  cond, a, b = convert(cond), convert(a), convert(b)
  return typecheck(darkroom.ast.new({kind="select",cond=cond,a=a,b=b}):copyMetadataFrom(cond))
end

function systolic.le(lhs, rhs) return binop(lhs,rhs,"<=") end
function systolic.eq(lhs, rhs) return binop(lhs,rhs,"==") end
function systolic.lt(lhs, rhs) return binop(lhs,rhs,"<") end
function systolic.ge(lhs, rhs) return binop(lhs,rhs,">=") end
function systolic.gt(lhs, rhs) return binop(lhs,rhs,">") end
function systolic.__or(lhs, rhs) return binop(lhs,rhs,"or") end
function systolic.__and(lhs, rhs) return binop(lhs,rhs,"and") end
function systolic.neg(expr) return unary(expr,"-") end

function systolicASTFunctions:cname(c)
  return self:name().."_c"..c
end


function checkForInst(inst, scopes)
  assert(systolicInstance.isSystolicInstance(inst))

  local fnd = false
  for k,scope in ipairs(scopes) do
    fnd = fnd or scope.instanceMap[inst]~=nil
  end
  
  if fnd==false then
    print("missing instance "..inst.name.." (kind "..inst.kind..")")
    map(scopes, function(n) print("scope",n.name) end)
    assert(false)
  end
end

-- check that all of the variables refered to are actually in scope
-- scopes goes from innermost (index 1) to outermost (index n)
function systolicASTFunctions:checkVariables(scopes)
  assert(type(scopes)=="table")

  local function astcheck(n)
    if n.kind=="readinput" or n.kind=="reg" or n.kind=="ram128" or n.kind=="call" then
      checkForInst(n.inst, scopes)
    end

    if n.kind=="fndefn" then
      local i=1
      while n["dst"..i] do
        checkForInst(n["dst"..i], scopes)
        i = i + 1
      end
    end

    if n.kind=="call" and n.func:isPure()==false then
      assert(systolicAST.isSystolicAST(n.valid))
    end
  end

  self:visitEach(astcheck)
end

function systolicASTFunctions:disablePipelining()
  return self:S("*"):process(
    function(n)
      if n.kind=="reg" then
        -- these things we can't disable pipelining on
      else
        local nn = n:shallowcopy()
        nn.pipeline=false
        return systolicAST.new(nn):copyMetadataFrom(n)
      end
    end)
end

function systolicASTFunctions:toVerilog( options, scopes )
  assert(type(scopes)=="table" or scopes==nil)

  local function addValidBit(ast,valid)
    assert(systolicAST.isSystolicAST(ast))
    assert(systolicAST.isSystolicAST(valid))

    return ast:S("call"):process(
      function(n)
        if n.pure~=true and systolicAST.isSystolicAST(n.valid)==false then
          local nn = n:shallowcopy()
          nn.valid = valid
          assert(systolicAST.isSystolicAST(valid))
          return systolicAST.new(nn):copyMetadataFrom(n)
        end
      end)
  end

  local ast = self
  if options.valid~=nil then
    local optv = options.valid
    if type(optv)=="boolean" then optv=systolic.value(optv) end
    -- obviously, if there are any function calls in the condition, we want them to always run
    local valid = addValidBit(optv, systolic.value(true) )
    valid = valid:disablePipelining()
    ast = addValidBit(ast,valid)
  end

  if scopes~=nil then ast:checkVariables( scopes ) end
  ast = darkroom.optimize.optimize( ast, {})

  local decl, clocked, finalOut, delays = codegen(ast)

  local t = decl
  if #clocked>0 then
    table.insert(t,"always @ (posedge CLK) begin\n")
    t = concat(t,clocked)
    table.insert(t,"end\n")
  end

  local fndelays = {}
  ast:S("fndefn"):process(
    function(n)
      fndelays[n.fn] = delays[n]
      if n.fn.pipeline==false then assert(delays[n]==0) end
    end)

  return t, finalOut, fndelays, delays[ast]
end

systolicAST = {}
function systolicAST.isSystolicAST(ast)
  return getmetatable(ast)==systolicASTMT
end

function systolicAST.new(tab)
  assert(type(tab)=="table")
  if tab.scaleN1==nil then tab.scaleN1=0 end
  if tab.scaleD1==nil then tab.scaleD1=0 end
  if tab.scaleN2==nil then tab.scaleN2=0 end
  if tab.scaleD2==nil then tab.scaleD2=0 end
  assert(darkroom.type.isType(tab.type))
  if tab.pipeline==nil then tab.pipeline=true end
  darkroom.IR.new(tab)
  return setmetatable(tab,systolicASTMT)
end

function systolic.reg( name, ty, initial )
  assert(type(name)=="string")
  checkReserved(name)
  ty = darkroom.type.fromTerraType(ty, 0, 0, "")
  return systolicInstance.new({kind="reg",name=name,initial=initial,type=ty})
end

function systolic.ram128( name )
  assert(type(name)=="string")
  checkReserved(name)
  return systolicInstance.new({kind="ram128",name=name,type=darkroom.type.null()})
end

function systolic.bram( name )
  assert(type(name)=="string")
  checkReserved(name)
  return systolicInstance.new({kind="bram",name=name,type=darkroom.type.null()})
end

function systolic.output(name, ty)
  assert(type(name)=="string")
  checkReserved(name)
  ty = darkroom.type.fromTerraType(ty, 0, 0, "")
  return systolicInstance.new({kind="output",name=name,type=ty})
end

function systolic.input(name, ty)
  assert(type(name)=="string")
  checkReserved(name)
  ty = darkroom.type.fromTerraType(ty, 0, 0, "")
  return systolicInstance.new({kind="input",name=name,type=ty})
end

return systolic