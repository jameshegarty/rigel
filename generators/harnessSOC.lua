local R = require "rigel"
local C = require "generators.examplescommon"
local SOC = require "generators.soc"
local J = require "common"
local SDF = require "sdfrate"
local types = require "types"
local Uniform = require "uniform"

return function(fn,t,instances)
  if R.isFunction(fn)==false then
    fn = C.linearPipeline(fn,"Top", nil, instances )
  elseif R.isFunctionGenerator(fn) then
    fn = fn{type=types.Interface()}
    J.err( R.isPlainFunction(fn), "harnessSOC: input generator could not be resolved into a module.")
  elseif R.isFunction(fn) then
    J.err(fn.name=="Top","Top module must be called 'Top', but is "..fn.name)
  else
    print("Unknown input type to harnessSOC? Not a Rigel module")
    assert(false)
  end

  assert(#fn.sdfInput==1)
  assert(#fn.sdfOutput==1)

  J.err( SDF.fracEq(fn.sdfInput[1],fn.sdfOutput[1]), "HarnessSOC error: total pipeline input and output SDF are not equal? This prob means there's an internal size mismatch. Input:"..tostring(fn.sdfInput[1][1]).."/"..tostring(fn.sdfInput[1][2]).." output:"..tostring(fn.sdfOutput[1][1]).."/"..tostring(fn.sdfOutput[1][2]))
  
  local backend
  if t~=nil then backend = t.backend end
  if backend==nil then backend = arg[1] end
  if backend==nil then backend = "verilog" end

  local filename = string.gsub(arg[0],"%.lua","") --arg[0]
  filename = string.gsub(filename,"%.t","")
  
  if backend=="verilog" or backend=="verilator" then
    local outfile = "out/"..filename..".v"
    if t~=nil and t.filename~=nil then outfile=t.filename..".v" end
    io.output(outfile)
    io.write(fn:toVerilog())
    io.output():close()
  elseif backend=="metadata" then
    local outfile = "out/"..filename..".metadata.lua"
    if t~=nil and t.filename~=nil then outfile=t.filename..".metadata.lua" end
    local f = io.open(outfile,"w")

    local inputList = {}

    for k,v in pairs(fn.globalMetadata) do
      if k:sub(#k-13)=="_read_filename" then
        local prefix = k:sub(1,#k-14)
        local rlist = {}
        table.insert(rlist,"filename='"..fn.globalMetadata[prefix.."_read_filename"].."'")
        if fn.globalMetadata[prefix.."_read_W"]~=nil then table.insert(rlist,"W="..Uniform(fn.globalMetadata[prefix.."_read_W"]):toEscapedString()) end
        if fn.globalMetadata[prefix.."_read_H"]~=nil then table.insert(rlist,"H="..Uniform(fn.globalMetadata[prefix.."_read_H"]):toEscapedString()) end
        if fn.globalMetadata[prefix.."_read_bitsPerPixel"]~=nil then table.insert(rlist,"bitsPerPixel="..fn.globalMetadata[prefix.."_read_bitsPerPixel"]) end
        if fn.globalMetadata[prefix.."_read_V"]~=nil then table.insert(rlist,"V="..fn.globalMetadata[prefix.."_read_V"]) end
        J.err(fn.globalMetadata[prefix.."_read_address"]~=nil,"Error: AXI port "..tostring(prefix).." was given a filename, but no address?")
        
        table.insert(rlist,"address="..Uniform(fn.globalMetadata[prefix.."_read_address"]):toEscapedString() )
        table.insert(inputList, "{"..table.concat(rlist,",").."}")
      end
    end

    local outputList = {}
    for k,v in pairs(fn.globalMetadata) do
      if k:sub(#k-14)=="_write_filename" then
        local prefix = k:sub(1,#k-15)
        local wlist = {}
        table.insert(wlist,"filename='"..fn.globalMetadata[prefix.."_write_filename"].."'")
        if fn.globalMetadata[prefix.."_write_W"]~=nil then table.insert(wlist,"W="..Uniform(fn.globalMetadata[prefix.."_write_W"]):simplify():toEscapedString()) end
        if fn.globalMetadata[prefix.."_write_H"]~=nil then table.insert(wlist,"H="..fn.globalMetadata[prefix.."_write_H"]) end
        if fn.globalMetadata[prefix.."_write_bitsPerPixel"]~=nil then table.insert(wlist,"bitsPerPixel="..fn.globalMetadata[prefix.."_write_bitsPerPixel"]) end
        if fn.globalMetadata[prefix.."_write_V"]~=nil then table.insert(wlist,"V="..fn.globalMetadata[prefix.."_write_V"]) end

        J.err(fn.globalMetadata[prefix.."_write_address"]~=nil,"Error: AXI write port "..prefix.." was given a filename, but no address?")
        table.insert( wlist, "address="..Uniform(fn.globalMetadata[prefix.."_write_address"]):toEscapedString() )

        table.insert(outputList, "{"..table.concat(wlist,",").."}")
      end
    end

    local registerList = {}
    for k,v in pairs(fn.globalMetadata) do
      if string.sub(k,0,8)=="Register" then
        local addr = string.sub(k,10)
        table.insert(registerList,"['0x"..addr.."']='"..v.."'")
      end
    end
    registerList=",registerValues={"..table.concat(registerList,",").."}"

    local registerNames = {}
    for k,v in pairs(fn.globalMetadata) do
      if string.sub(k,0,14)=="AddrOfRegister" then
        local name = string.sub(k,16)
        table.insert(registerNames,name.."='0x"..string.format("%x",v).."'")
      end
    end
    registerNames=",registers={"..table.concat(registerNames,",").."}"
    
    local cyc = (fn.sdfInput[1][2]/fn.sdfInput[1][1])
    if t~=nil and t.cycles~=nil then cyc=t.cycles end

    J.err( type(SOC.currentAddr)=="number","SOC.currentAddr should be a number?")
    J.err(SOC.currentAddr ~= 0x30008000,"SOC.currentAddr should imply a segment size > 0?")
    
    f:write( "return {inputs={"..table.concat(inputList,",").."},outputs={"..table.concat(outputList,",").."},topModule='"..fn.name.."',memoryStart=0x30008000,memoryEnd=0x"..string.format("%x",SOC.currentAddr)..",cycles="..Uniform(cyc):toEscapedString()..registerList..registerNames.."}" )
    f:close()
  elseif backend=="terra" then
    local doTerraSim = require("generators.harnessTerraSOC")
    doTerraSim(fn,t)
  else
    print("backend",backend)
    assert(false)
  end
end
