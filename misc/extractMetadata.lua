local metadata = dofile(arg[1])

function basename(fn)
  local a,b,c = string.match(fn, "(.-)([^\\/]-%.?([^%.\\/]*))$")
  return b
end

if arg[2]=="memoryStart" or arg[2]=="memoryEnd" then
  if metadata[arg[2]]~=nil then
    print("--"..arg[2].." "..string.format("%x",metadata[arg[2]]))
  end
elseif arg[2]=="__INPUT_HOST_FILES" or arg[2]=="__INPUT_DEVICE_FILES" then
  local str = ""
  for _,v in ipairs(metadata.inputs) do
    if arg[2]=="__INPUT_HOST_FILES" then
      str = str..v.filename.." "
    else
      str = str..basename(v.filename).." "
    end
  end
  print(str)
elseif arg[2]=="__INPUTS" or arg[2]=="__INPUTS_ZYNQ" then
  -- special case for SOC
  local str = ""
  for _,v in ipairs(metadata.inputs) do
    local fn = v.filename
    if arg[2]=="__INPUTS_ZYNQ" then fn=basename(fn) end

    if type(v.address)=="number" then
      str = str..fn.." 0x"..string.format("%x",v.address).." "
    else
      local regAddress = metadata.registers[v.address]
      if regAddress==nil then print("Could not find register"); assert(false) end
      --str = str..fn.." reg:0x"..string.format("%x",regAddress).." "
      -- HACK: b/c this is set by the harness, just load the default address
      str = str..fn.." 0x"..metadata.registerValues[regAddress].." "
    end
  end
  print(str)
elseif arg[2]=="__OUTPUTS" or arg[2]=="__OUTPUTS_ZYNQ" then
  -- special case for SOC
  local str = ""
  for _,v in ipairs(metadata.outputs) do
    local fn = v.filename
    if arg[2]=="__OUTPUTS_ZYNQ" then fn=basename(fn) end
    str = str..fn.." "

    if type(v.address)=="number" then
      str = str.."0x"..string.format("%x",v.address)
    else
      local regAddress = metadata.registers[v.address]
      if regAddress==nil then print("Could not find register"); assert(false) end
      str = str.." reg:0x"..string.format("%x",regAddress).." "
    end
    
    str = str.." "..v.W.." "..v.H.." "..v.bitsPerPixel.." "
  end
  print(str)
elseif arg[2]=="__REGISTERS" then
  -- special case for SOC
  assert(type(metadata.registerValues)=="table")
  local str = ""
  for k,v in pairs(metadata.registerValues) do
    str = str..k.." "..v.." "
  end
  print(str)
elseif arg[2]=="__REGISTERSOUT" then
  -- special case for SOC
  assert(type(metadata.registers)=="table")
  local str = ""
  for k,v in pairs(metadata.registers) do
    str = str..k.." "..v.." "
  end
  print(str)
elseif arg[2]=="INPUT_FILES" then
  local i=1
  local str = ""
  while metadata["inputFile"..i] do
    str = str .. "-testplusarg inputFilename"..i.."=../"..metadata["inputFile"..i].." "
    i = i + 1
  end
  print(str)
else
  if type(metadata[arg[2]])=="table" then
    print(table.concat(metadata[arg[2]]," "))
  else
    print(metadata[arg[2]])
  end
end
