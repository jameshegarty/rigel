local R = require "rigel"
local C = require "examplescommon"
local SOC = require "soc"
local J = require "common"
local SDF = require "sdfrate"

return function(fn,t)
  if R.isFunction(fn)==false then
    fn = C.linearPipeline(fn,"Top")
  else
    J.err(fn.name=="Top","Top module must be called 'Top', but is "..fn.name)
  end

  print("SDF: ", SDF.tostring(fn.sdfInput), SDF.tostring(fn.sdfOutput))

  assert(#fn.sdfInput==1)
  assert(#fn.sdfOutput==1)

  J.err( SDF.fracEq(fn.sdfInput[1],fn.sdfOutput[1]), "HarnessSOC error: total pipeline input and output SDF are not equal? This prob means there's an internal size mismatch.")
  
  local backend
  if t~=nil then backend = t.backend end
  if backend==nil then backend = arg[1] end
  if backend==nil then backend = "verilog" end

  local filename = string.gsub(arg[0],".lua","") --arg[0]
  print("FILENAME",filename)
  
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
    for i=0,SOC.ports do
      if fn.globalMetadata["MAXI"..i.."_read_filename"]~=nil then
        local rlist = {}
        table.insert(rlist,"filename='"..fn.globalMetadata["MAXI"..i.."_read_filename"].."'")
        if fn.globalMetadata["MAXI"..i.."_read_W"]~=nil then table.insert(rlist,"W="..fn.globalMetadata["MAXI"..i.."_read_W"]) end
        if fn.globalMetadata["MAXI"..i.."_read_H"]~=nil then table.insert(rlist,"H="..fn.globalMetadata["MAXI"..i.."_read_H"]) end
        if fn.globalMetadata["MAXI"..i.."_read_bitsPerPixel"]~=nil then table.insert(rlist,"bitsPerPixel="..fn.globalMetadata["MAXI"..i.."_read_bitsPerPixel"]) end
        if fn.globalMetadata["MAXI"..i.."_read_V"]~=nil then table.insert(rlist,"V="..fn.globalMetadata["MAXI"..i.."_read_V"]) end
        table.insert(rlist,"address=0x"..string.format("%x",fn.globalMetadata["MAXI"..i.."_read_address"]))
        table.insert(inputList, "{"..table.concat(rlist,",").."}")
      end
    end

    local outputList = {}
    for i=0,SOC.ports do
      if fn.globalMetadata["MAXI"..i.."_write_filename"]~=nil then
        table.insert(outputList,"{filename='"..fn.globalMetadata["MAXI"..i.."_write_filename"].."',W="..fn.globalMetadata["MAXI"..i.."_write_W"]..",H="..fn.globalMetadata["MAXI"..i.."_write_H"]..",bitsPerPixel="..fn.globalMetadata["MAXI"..i.."_write_bitsPerPixel"]..",V="..fn.globalMetadata["MAXI"..i.."_write_V"]..",address=0x"..string.format("%x",fn.globalMetadata["MAXI"..i.."_write_address"]).."}")
      end
    end

    local registerList = {}
    for k,v in pairs(fn.globalMetadata) do
      if string.sub(k,0,8)=="Register" then
        local addr = string.sub(k,10)
        table.insert(registerList,"['"..addr.."']='"..v.."'")
      end
    end
    registerList=",registers={"..table.concat(registerList,",").."}"

    local cyc = (fn.sdfInput[1][2]/fn.sdfInput[1][1])
    if t~=nil and t.cycles~=nil then cyc=t.cycles end
    
    f:write( "return {inputs={"..table.concat(inputList,",").."},outputs={"..table.concat(outputList,",").."},topModule='"..fn.name.."',memoryStart=0x30008000,memoryEnd=0x"..string.format("%x",SOC.currentAddr)..",cycles="..cyc..registerList.."}" )
    f:close()
  elseif backend=="terra" then
    local doTerraSim = require("harnessTerraSOC")
    doTerraSim(fn)
  else
    print("backend",backend)
    assert(false)
  end
end
