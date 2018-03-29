local R = require "rigel"
local C = require "examplescommon"

return function(fn,t)
  if R.isFunction(fn)==false then
    fn = C.linearPipeline(fn,"Top")
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
    f:write( "return {inputFiles={'"..fn.globalMetadata.MAXI0_read_filename.."'},outputFiles={'"..fn.globalMetadata.MAXI0_write_filename.."'},topModule='"..fn.name.."'}" )
    f:close()
  else
    print("backend",backend)
    assert(false)
  end
end
