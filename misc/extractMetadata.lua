local metadata = dofile(arg[1])

if arg[2]=="__INPUTS" then
  -- special case for SOC
  local str = ""
  for _,v in ipairs(metadata.inputs) do
    str = str..v.filename.." "..v.address.." "
  end
  print(str)
elseif arg[2]=="__OUTPUTS" then
  -- special case for SOC
  local str = ""
  for _,v in ipairs(metadata.outputs) do
    str = str..v.filename.." "..v.address.." "..v.W.." "..v.H.." "..v.bitsPerPixel.." "
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
