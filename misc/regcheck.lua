local a = dofile(arg[1])
local b = dofile(arg[2])

for k,v in pairs(a) do if a[k]~=b[k] then os.exit(1) end end
for k,v in pairs(b) do if a[k]~=b[k] then os.exit(1) end end
