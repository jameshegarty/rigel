local systolic = require "systolic"
local M = require "magmair"
local Mtypes = require "magmairtypes"
local Mstd = require "magmastd"
local Mhelper = require "magmahelper"
local types = require "types"

function toMagmaType(ty)
  assert(types.isType(ty))

  if ty:isBool() then
    return Mtypes.bool{const=ty:const()}
  elseif ty:isInt() then
    return Mtypes.int(ty.precision,{const=ty:const()})
  elseif ty:isUint() then
    return Mtypes.uint(ty.precision,{const=ty:const()})
  elseif ty:isTuple() then
    return Mtypes.record(map(ty.list, function(n,k) return {k-1,toMagmaType(n)} end))
  else
    print(ty)
    assert(false)
  end
end

local binopToVerilog={["+"]=Mhelper.add,["*"]="*",["<<"]="<<<",[">>"]=">>>",["pow"]="**",["=="]="==",["and"]="&",["-"]="-",["<"]="<",[">"]=">",["<="]="<=",[">="]=">="}

function systolicASTFunctions:toMagmaIR( systolicModule, magmaModule )
  assert( systolic.isModule(systolicModule))
  assert( M.isDefinition(magmaModule))

  local finalOut = self:visitEach(
    function(n, args)
      local finalResult

      if n.kind=="call" then
        local fn = n.func

        local i = 0

        local callmodule = n.inst.module
        if fn:isPure()==false or callmodule.onlyWire then
          if callmodule.onlyWire and fn.implicitValid then
            -- when in onlyWire mode, it's ok to have an undriven valid bit
          else
            err( M.isWire(args[2]), "undriven valid bit, function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."'")
            module:wire(args[2],module:select(module:select(module:lookupInstance(n.inst.name),fn.name),i),n.name.."_valid")
            i=i+1
          end      
        end

        if fn.CE~=nil then
          err( M.isWire(args[3]), "undriven CE '"..fn.CE.name.."', function '"..fn.name.."' on instance '"..n.inst.name.."' in module '"..module.name.."'")
          module:wire(args[3],module:select(module:select(module:lookupInstance(n.inst.name),fn.name),i),n.name.."_CE")
          i=i+1
        end

        if fn.inputParameter.type~=types.null() and fn.inputParameter.type:verilogBits()>0  then
          err( instance.verilogCompilerState[module][fnname]~=nil, "No calls to fn '"..fnname.."' on instance '"..instance.name.."'? input type "..tostring(fn.inputParameter.type))
          err( M.isWire(args[1]), "undriven input, function '"..fnname.."' on instance '"..instance.name.."' in module '"..module.name.."'")
          module:wire(args[1],module:select(module:select(module:lookupInstance(n.inst.name),fn.name),i),n.name.."_data")
          i=i+1
        end
        
        finalResult = magmaModule:select(module:select(module:lookupInstance(n.inst.name),fn.name),i)
      elseif n.kind=="callArbitrate" then
        -- inputs are stored as {data,validbit} pairs, ie {call1data,call1valid,call2data,call2valid}
        local argpairs = split(args,2)

        local inst = module:addInstance( Mhelper.callArbitrate(n.name,{type=n.type,N=#argpairs}) )

        for k,v in pairs(args) do
          module:addWire(v,module:select(module:select(inst,0),k-1))
        end

        finalResult = module:select(inst,1)
      elseif n.kind=="constant" then
        finalResult = magmaModule:addInstance( Mhelper.constant{type=toMagmaType(n.type),value=n.value}, n.name )
      elseif n.kind=="fndefn" then
        finalResult = "_ERR_NULL_FNDEFN"
      elseif n.kind=="module" then
        finalResult = "__ERR_NULL_MODULE"
      elseif n.kind=="bitSlice" then
        local inst = module:addInstance( Mhelper.bitslice(n.name,{start=n.low, len=n.high-n.low+1, type=n.type}) )
        finalResult = module:addWireFunction(inst,args[1])
      elseif n.kind=="slice" then
        if n.inputs[1].type:isArray() then
          finalResult = Mstd.arraySlice(n.name,{type=n.inputs[1].type,start=n.idxLow,len=n.idxHigh-n.idxLow+1})
        elseif n.inputs[1].type:isTuple() then
          finalResult = magmaModule:addInstance(Mhelper.tupleSlice{type=toMagmaType(n.inputs[1].type),start=n.idxLow,len=n.idxHigh-n.idxLow+1}, n.name)
          finalResult.input:wire(args[1])
          finalResult = finalResult.output
        else
          print(n.expr.type)
          assert(false)
        end
      elseif n.kind=="tuple" then
        finalResult = Mstd.record(n.name,{type=n.type})
      elseif n.kind=="cast" then
        finalResult = magmaModule:addInstance(Mhelper.cast{inputType=toMagmaType(n.inputs[1].type),outputType=toMagmaType(n.type)},n.name)
        finalResult.input:wire(args[1])
        finalResult = finalResult.output
      elseif n.kind=="parameter" then
        finalResult = magmaModule.parameter[n.name]
      elseif n.kind=="instanceParameter" then
        table.insert(declarations, declareWire(n.type, n.name, n.variable))
        finalResult = n.name
        wire=true
      elseif n.kind=="null" then
        finalResult = "__SYSTOLIC_NULL"
      elseif n.kind=="select" then
        finalResult = magmaModule:addInstance( Mhelper.select{type=toMagmaType(n.type)}, n.name )
        finalResult.input[0]:wire(args[1])
        finalResult.input[1]:wire(args[2])
        finalResult.input[2]:wire(args[3])
        finalResult = finalResult.output
      elseif n.kind=="binop" then
        print("DOOP",n.op)
        local op = binopToVerilog[n.op]
        local inst = magmaModule:addInstance( op{lType=toMagmaType(n.inputs[1].type), rType=toMagmaType(n.inputs[2].type), outputType=toMagmaType(n.type)}, n.name )
        inst.input[0]:wire(args[1])
        inst.input[1]:wire(args[2])
        finalResult = inst.output
      elseif n.kind=="unary" then
        if n.op=="abs" then
          if n.type:isInt() then
            res = systolic.wireIfNecessary( argwire[1], declarations, n.inputs[1].type, n.inputs[1].name, args[1], "// wire for abs")
            res = "(("..res.."["..(n.type:verilogBits()-1).."])?(-"..res.."):("..res.."))"
          else
            --              return inputs.expr[c] -- must be unsigned
            assert(false)
          end
        elseif n.op=="-" then
          res = "(-"..args[1]..")"
        elseif n.op=="not" then
          res = "(~"..args[1]..")"
        elseif n.op=="isX" then
          res = "("..args[1].."===1'bx)"
        else
          print(n.op)
          assert(false)
        end
      elseif n.kind=="vectorSelect" then
        assert(false)
      else
        print(n.kind)
        assert(false)
      end

      if n.kind~="fndefn" and n.kind~="module" and n.kind~="null" then
        err( M.isValue(finalResult), "incorrect output type! kind="..n.kind )
      end

      return finalResult
    end)

  return finalOut
end

function userModuleFunctions:toMagmaIR()

  if self.magmaIR~=nil then return self.magmaIR end

  local CEseen = {}

  local portlist = {{"CLK",Mtypes.bool():input()}}

  for fnname,fn in pairs(self.functions) do

      -- our purity analysis isn't smart enough to know whether a valid bit is needed when onlyWire==true.
      -- EG, if we use the valid bit to control clock enables or something. So just do what the user said (include the valid unless it was implicit)
      if (fn:isPure()==false or self.onlyWire) and not (self.onlyWire and fn.implicitValid) then 
        table.insert(portlist,{fn.valid.name,Mtypes.bool():input()})
      end

      if fn.CE~=nil then 
        CEseen[fn.CE.name]=1; 
        table.insert(portlist,{fn.CE.name,Mtypes.bool():input()}) 
      end

      if fn.inputParameter.type~=types.null() and fn.inputParameter.type:verilogBits()>0 then 
        table.insert(portlist,{ fn.inputParameter.name, toMagmaType(fn.inputParameter.type):input()})
      end

      if fn.output~=nil and fn.output.type~=types.null() and fn.output.type:verilogBits()>0 then table.insert(portlist,{ fn.outputName, toMagmaType(fn.output.type):output() })  end

  end

  local module = M.defineModule( self.name, Mtypes.record(portlist) )

  self.ast:toMagmaIR( self, module )

  self.magmaIR = module
  return module
end

function userModuleFunctions:getDependenciesMagmaIR()
  return table.concat(map(self:getDependenciesLL(), function(n) return table_print(n[1]:toMagmaIR():pickle()) end),"")
end

function assertModuleFunctions:toMagmaIR()
  return Mstd.assert{ error=self.str, exit=self.exit, hasCE = self.CE}
end

function regModuleFunctions:toMagmaIR()
  return Mstd.reg{ type = toMagmaType(self.type), hasCE = self.hasCE, hasValid = self.hasValue }
end