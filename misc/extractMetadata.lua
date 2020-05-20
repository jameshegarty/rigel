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

    local W = v.W
    if type(W)=="string" then
      local regAddress = metadata.registers[W]
      if regAddress==nil then print("Could not find register"); assert(false) end
      W = tonumber("0x"..metadata.registerValues[regAddress])
    end
    
    str = str.." "..W.." "..v.H.." "..v.bitsPerPixel.." "
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
elseif arg[2]=="__XDC" then
  local ns = 1000/tostring(metadata.MHz)
  print([[create_clock -add -name FCLK -period ]]..ns..[[ [get_nets FCLK0];
set_property PACKAGE_PIN AG14     [get_ports {LED[0]}] ;# Bank  44 VCCO - VCC3V3   - IO_L10P_AD2P_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[0]}] ;# Bank  44 VCCO - VCC3V3   - IO_L10P_AD2P_44
set_property PACKAGE_PIN AF13     [get_ports {LED[1]}] ;# Bank  44 VCCO - VCC3V3   - IO_L9N_AD3N_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[1]}] ;# Bank  44 VCCO - VCC3V3   - IO_L9N_AD3N_44
set_property PACKAGE_PIN AE13     [get_ports {LED[2]}] ;# Bank  44 VCCO - VCC3V3   - IO_L9P_AD3P_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[2]}] ;# Bank  44 VCCO - VCC3V3   - IO_L9P_AD3P_44
set_property PACKAGE_PIN AJ14     [get_ports {LED[3]}] ;# Bank  44 VCCO - VCC3V3   - IO_L8N_HDGC_AD4N_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[3]}] ;# Bank  44 VCCO - VCC3V3   - IO_L8N_HDGC_AD4N_44
set_property PACKAGE_PIN AJ15     [get_ports {LED[4]}] ;# Bank  44 VCCO - VCC3V3   - IO_L8P_HDGC_AD4P_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[4]}] ;# Bank  44 VCCO - VCC3V3   - IO_L8P_HDGC_AD4P_44
set_property PACKAGE_PIN AH13     [get_ports {LED[5]}] ;# Bank  44 VCCO - VCC3V3   - IO_L7N_HDGC_AD5N_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[5]}] ;# Bank  44 VCCO - VCC3V3   - IO_L7N_HDGC_AD5N_44
set_property PACKAGE_PIN AH14     [get_ports {LED[6]}] ;# Bank  44 VCCO - VCC3V3   - IO_L7P_HDGC_AD5P_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[6]}] ;# Bank  44 VCCO - VCC3V3   - IO_L7P_HDGC_AD5P_44
set_property PACKAGE_PIN AL12     [get_ports {LED[7]}] ;# Bank  44 VCCO - VCC3V3   - IO_L6N_HDGC_AD6N_44
set_property IOSTANDARD  LVCMOS33 [get_ports {LED[7]}] ;# Bank  44 VCCO - VCC3V3   - IO_L6N_HDGC_AD6N_44]])
elseif arg[2]=="INPUT_FILES" then
  local i=1
  local str = ""
  while metadata["inputFile"..i] do
    str = str .. "-testplusarg inputFilename"..i.."=../"..metadata["inputFile"..i].." "
    i = i + 1
  end
  print(str)
elseif arg[2]=="cycles" then
  if type(metadata.cycles)=="number" then
    print(metadata.cycles)
  elseif type(metadata.cycles)=="string" then
    -- register lookup
    local addr = metadata.registers[metadata.cycles]
    if addr==nil then print("Could not find register for cycles"); assert(false) end
    print(tonumber("0x"..metadata.registerValues[addr]))
  else
    assert(false)
  end
else
  if type(metadata[arg[2]])=="table" then
    print(table.concat(metadata[arg[2]]," "))
  else
    print(metadata[arg[2]])
  end
end
