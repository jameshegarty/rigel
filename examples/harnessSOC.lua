local R = require "rigel"
local C = require "examplescommon"
local SOC = require "soc"
local J = require "common"

return function(fn,t)
  if R.isFunction(fn)==false then
    fn = C.linearPipeline(fn,"Top")
  else
    J.err(fn.name=="Top","Top module must be called 'Top', but is "..fn.name)
  end

  local backend
  if t~=nil then backend = t.backend end
  if backend==nil then backend = arg[1] end
  if backend==nil then backend = "verilog" end

  local filename = string.gsub(arg[0],".lua","") --arg[0]
  print("FILENAME",filename)
  
  if backend=="verilog" or backend=="verilator" then
    io.output("out/"..filename..".v")
    io.write(fn:toVerilog())
    io.output():close()
  elseif backend=="metadata" then
    local f = io.open("out/"..filename..".metadata.lua","w")

    local inputList = {}
    for i=0,SOC.ports do
      if fn.globalMetadata["MAXI"..i.."_read_filename"]~=nil then
        table.insert(inputList,"{filename='"..fn.globalMetadata["MAXI"..i.."_read_filename"].."',W="..fn.globalMetadata["MAXI"..i.."_read_W"]..",H="..fn.globalMetadata["MAXI"..i.."_read_H"]..",bitsPerPixel="..fn.globalMetadata["MAXI"..i.."_read_bitsPerPixel"]..",V="..fn.globalMetadata["MAXI"..i.."_read_V"]..",address=0x"..string.format("%x",fn.globalMetadata["MAXI"..i.."_read_address"]).."}")
      end
    end

    local outputList = {}
    for i=0,SOC.ports do
      if fn.globalMetadata["MAXI"..i.."_write_filename"]~=nil then
        table.insert(outputList,"{filename='"..fn.globalMetadata["MAXI"..i.."_write_filename"].."',W="..fn.globalMetadata["MAXI"..i.."_write_W"]..",H="..fn.globalMetadata["MAXI"..i.."_write_H"]..",bitsPerPixel="..fn.globalMetadata["MAXI"..i.."_write_bitsPerPixel"]..",V="..fn.globalMetadata["MAXI"..i.."_write_V"]..",address=0x"..string.format("%x",fn.globalMetadata["MAXI"..i.."_write_address"]).."}")
      end
    end
    
    f:write( "return {inputs={"..table.concat(inputList,",").."},outputs={"..table.concat(outputList,",").."},topModule='"..fn.name.."',memoryStart=0x30008000,memoryEnd=0x"..string.format("%x",SOC.currentAddr).."}" )
    f:close()
  else
    print("backend",backend)
    assert(false)
  end
end
