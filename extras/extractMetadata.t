local metadata = dofile(arg[1])

if arg[2]=="INPUT_FILES" then
  local i=1
  local str = ""
  while metadata["inputFile"..i] do
    str = str .. "-testplusarg inputFilename"..i.."=../"..metadata["inputFile"..i].." "
    i = i + 1
  end
  print(str)
else
  print(metadata[arg[2]])
end