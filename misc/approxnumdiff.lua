-- compares two files that contain numbers: approxnumdiff.lua NEW_FILE TARGET_FILE out SLACK largerIsBetter/smallerIsBetter
-- only write 'out' if LEFT_FILE<RIGHT_FILE*(1+SLACK)

local f0 = assert(io.open(arg[1], "r"))
local f0str = f0:read("*all")
local NEW
if f0str=="" then
  NEW = 0
else
  NEW = tonumber(f0str)
end
f0:close()

local f1 = assert(io.open(arg[2], "r"))
local f1str = f1:read("*all")
local TARGET
if f1str=="" then
  TARGET = 0
else
  TARGET = tonumber(f1str)
end
f1:close()

local SLACK = tonumber(arg[4])

--print(LEFT,RIGHT)

if (arg[5]=="smallerIsBetter" and NEW>TARGET*(1+SLACK)) or (arg[5]=="largerIsBetter" and NEW<TARGET*(1-SLACK)) then
  print("ERROR: stat regressed out of bounds, ","target:",TARGET,"new:",NEW,tostring((NEW/TARGET)*100).."%",arg[1])
  os.exit(1)
elseif (arg[5]=="smallerIsBetter" and NEW>TARGET) or (arg[5]=="largerIsBetter" and NEW<TARGET) then
  print("stat regressed in bounds, ","target:",TARGET,"new:",NEW,tostring((NEW/TARGET)*100).."%",arg[1])
elseif NEW==TARGET then
elseif (arg[5]=="smallerIsBetter" and NEW<TARGET*0.6) or (arg[5]=="largerIsBetter" and NEW>TARGET*1.5) then
  print("State improved wayyy too much, maybe a bug? Target:",TARGET," New:",NEW,arg[1] )
  os.exit(1)
else
  print("stat improved! ","target:",TARGET,"new:",NEW,tostring((NEW/TARGET)*100).."%",arg[1])
end

local f = assert(io.open(arg[3], "w"))
f:write("ok")
f:close()
