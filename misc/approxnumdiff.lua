-- compares two files that contain numbers: approxnumdiff.lua NEW_FILE TARGET_FILE out SLACK largerIsBetter/smallerIsBetter
-- only write 'out' if LEFT_FILE<RIGHT_FILE*(1+SLACK)

local f0 = assert(io.open(arg[1], "r"))
local NEW = tonumber(f0:read("*all"))
f0:close()

local f1 = assert(io.open(arg[2], "r"))
local TARGET = tonumber(f1:read("*all"))
f1:close()

local SLACK = tonumber(arg[4])

--print(LEFT,RIGHT)

if (arg[5]=="smallerIsBetter" and NEW>TARGET*(1+SLACK)) or (arg[5]=="largerIsBetter" and NEW<TARGET*(1-SLACK)) then
  print("ERROR: stat regressed out of bounds, ","target:",TARGET,"new:",NEW,tostring((NEW/TARGET)*100).."%")
  os.exit(1)
elseif (arg[5]=="smallerIsBetter" and NEW>TARGET) or (arg[5]=="largerIsBetter" and NEW<TARGET) then
  print("stat regressed in bounds, ","target:",TARGET,"new:",NEW,tostring((NEW/TARGET)*100).."%")
elseif NEW==TARGET then
else
  print("stat improved! ","target:",TARGET,"new:",NEW,tostring((NEW/TARGET)*100).."%")
end

local f = assert(io.open(arg[3], "w"))
f:write("ok")
f:close()
