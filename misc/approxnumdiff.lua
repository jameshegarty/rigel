-- compares two files that contain numbers: approxnumdiff.lua LEFT_FILE RIGHT_FILE out
-- only write 'out' if LEFT_FILE<RIGHT_FILE*1.1

local f0 = assert(io.open(arg[1], "r"))
local LEFT = tonumber(f0:read("*all"))
f0:close()

local f1 = assert(io.open(arg[2], "r"))
local RIGHT = tonumber(f1:read("*all"))
f1:close()

--print(LEFT,RIGHT)

if LEFT>RIGHT*1.1 then
  print("ERROR: stat regressed out of bounds, ",LEFT,RIGHT,tostring((LEFT/RIGHT)*100).."%")
  os.exit()
elseif LEFT>RIGHT then
  print("stat regressed in bounds, ",LEFT,RIGHT,tostring((LEFT/RIGHT)*100).."%")
elseif LEFT==RIGHT then
else
  print("stat improved!, ",LEFT,RIGHT,tostring((LEFT/RIGHT)*100).."%")
end

local f = assert(io.open(arg[3], "w"))
f:write("ok")
f:close()
