--[[
crc32: calculate crc32 in Lua
Copyright (c) 2015-17 GreaseMonkey

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local sysnative = not not package.loadlib
local datacard = nil
if not sysnative then
	local component = require("component")
	if component.isAvailable("data") then
		datacard = component.data
	end
end

-- CRC32 implementation
-- standard table lookup version
local crctab = {}

local i
for i=0,256-1 do
	local j
	local v = i
	--[[
	v = ((v<<4)|(v>>4)) & 0xFF
	v = ((v<<2)&0xCC)|((v>>2)&0x33)
	v = ((v<<1)&0xAA)|((v>>1)&0x55)
	]]

	for j=1,8 do
		if (v&1) == 0 then
			v = v>>1
		else
			v = (v>>1) ~ 0xEDB88320
		end
	end
	crctab[i+1] = v
end

local crc = {}
function crc.crc32(str, v)
	v = v or 0
	if v == 0 and datacard ~= nil then
		local a = datacard.crc32(str)
		v = string.byte(a, 1) | (string.byte(a, 2) << 8) | (string.byte(a, 3) << 16)
		v = v | (string.byte(a, 4) << 24)
		return v
	end
	v = v ~ 0xFFFFFFFF

	local i
	for i=1,#str do
		--print(str:byte(i))
		v = (v >> 8) ~ crctab[((v&0xFF) ~ str:byte(i))+1]
	end

	v = v ~ 0xFFFFFFFF
	return v
end

return crc
