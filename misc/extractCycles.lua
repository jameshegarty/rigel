-- read the entire file
local f = io.open(arg[1], 'rb')
local data = f:read('*a')
f:close()

-- last 4 bytes of file are cycles
local bytes = string.sub(data, -4)

-- convert to hex string
local s = ''
for b in string.gfind(bytes, ".") do
	s = string.format("%02X", string.byte(b)) .. s
end

-- hex to decimal
print(tonumber(s, 16))