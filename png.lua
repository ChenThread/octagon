--[[
ocpng: show a png in opencomputers
Copyright (c) 2015-17 asie, GreaseMonkey

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

--[[
this requires Lua 5.3 at the moment
but it does NOT require a data card
]]

local crc = dofile("./crc32.lua")
local inflate = dofile("./inflate.lua")

local ocpng = {}

function ocpng.loadPNG(fname)
assert(fname, "provide a filename as an argument")
-- PNG magic header
fp = io.open(fname, "rb")
if fp == nil then
  error("file not found: " .. fname)
end
if fp:read(8) ~= "\x89PNG\x0D\x0A\x1A\x0A" then
	error("invalid PNG magic")
end

-- chunks
local png_w, png_h
local png_bpc, png_cm
local png_compr, png_filt, png_inter
local png_ccount
local png_fstride
local png_bwidth
local png_trns = {}

local idat_accum = ""
while true do
	local clen_s = fp:read(4)
	local clen = string.unpack(">I4", clen_s)
	local ctyp = fp:read(4)
	local cdat = fp:read(clen)
	local ccrc = string.unpack(">I4", fp:read(4))

	--print(ctyp, string.format("%08X", ccrc), clen)
	local acrc = crc.crc32(ctyp..cdat)
	if acrc ~= ccrc then
		print(string.format("%08X %08X", acrc, ccrc))
		error("CRC mismatch")
	end

	if ctyp == "IHDR" then
		png_w, png_h, png_bpc, png_cm, png_compr, png_filt, png_inter = string.unpack(">I4 >I4 B B B B B", cdat)
		if png_compr ~= 0 then error("unsupported compression mode") end
		if png_filt ~= 0 then error("unsupported filter mode") end
		if png_inter ~= 0 then error("we don't support interlacing (yet)") end

		-- decipher colour mode
		if (png_cm & ~7) ~= 0 or png_cm == 1 or (png_cm&~2) == 5 then
			error("unsupported colour mode")
		end
		if (png_cm&3) == 2 then png_ccount = 3 else png_ccount = 1 end
		if (png_cm&4) == 4 then png_ccount = png_ccount + 1 end

		if png_ccount ~= 1 and png_bpc < 8 then
			error("bpc must be >= 8 for colour modes with more than one component")
		end

		if png_cm == 3 and png_cm > 8 then
			error("bpc must be <= 8 for indexed colour modes")
		end

		png_fstride = 1
		if png_bpc == 1 then
			png_bwidth = (png_w+7)>>3
		elseif png_bpc == 2 then
			png_bwidth = (png_w+3)>>2
		elseif png_bpc == 4 then
			png_bwidth = (png_w+1)>>1
		else
			if png_bpc == 8 then
				png_fstride = 1*png_ccount
			elseif png_bpc == 16 then
				png_fstride = 2*png_ccount
			end

			png_bwidth = png_fstride*png_w
		end

	elseif ctyp == "PLTE" then
		print(png_cm, png_bpc, png_bwidth, #cdat)
		PALETTE = {}
		local i
		for i=0,#cdat//3-1 do
			PALETTE[i+1] = (0
				+ (cdat:byte(3*i+1,3*i+1)<<16)
				+ (cdat:byte(3*i+2,3*i+2)<<8)
				+ (cdat:byte(3*i+3,3*i+3)))
		end

	elseif ctyp == "tRNS" then
		if png_cm == 3 then
			-- indexed + transparency
			for i=0,#cdat do
				local c = cdat:byte(i+1,i+1)
				table.insert(png_trns, c)
			end
		elseif png_cm == 2 and png_bpc == 8 then
			-- rgb + transparency
			for i=0,#cdat//3-1 do
				png_trns[(cdat:byte(3*i+1,3*i+1)<<16)
					+ (cdat:byte(3*i+2,3*i+2)<<8)
					+ (cdat:byte(3*i+3,3*i+3))] = true
			end
		else
			error(string.format("TODO: support this tRNS colour mode setup: cm=%d bpc=%d", png_cm, png_bpc))
		end

	elseif ctyp == "IDAT" then
		idat_accum = idat_accum .. cdat

	elseif ctyp == "IEND" then
		break
	else
		if (ctyp:byte(1) & 0x20) == 0 then
			error("unhandled compulsory chunk")
		end
	end
end

fp:close()

-- actually decompress image
if sysnative then print("Inflating...") end
local png_data = inflate.inflate(idat_accum)

local function paeth(a, b, c)
	local p = a+b-c
	local pa = math.tointeger(math.abs(p-a))
	local pb = math.tointeger(math.abs(p-b))
	local pc = math.tointeger(math.abs(p-c))

	if pa <= pb and pa <= pc then return a
	elseif pb <= pc then return b
	else return c
	end
end

-- defilter
if sysnative then print("Defiltering...") end
local x,y
local unpackedcomb = ""
local unpacked = ""
--for x=1,png_bwidth do pline = pline .. string.char(0) end
for y=0,png_h-1 do
	if false and #unpacked > png_bwidth*6 then
		unpackedcomb = unpackedcomb .. unpacked:sub(1, #unpacked - (png_bwidth*3) - 1)
		unpacked = unpacked:sub(#unpacked - (png_bwidth*3))
	end
	local line = png_data:sub(1+y*(png_bwidth+1), (y+1)*(png_bwidth+1))
	local ftyp = line:byte(1)

	--print(ftyp)
	if ftyp == 0 then
		-- stored
		unpacked = unpacked .. line:sub(2)

	elseif ftyp == 1 then
		-- dx
		unpacked = unpacked .. line:sub(2, 2+png_fstride-1)
		for x=2+png_fstride,#line do
			unpacked = unpacked .. string.char(0xFF&(
				line:byte(x) + 
				unpacked:byte(#unpacked-png_fstride+1)))
		end

	elseif ftyp == 2 then
		-- dy
		for x=2,#line do
			unpacked = unpacked .. string.char(0xFF&(
				line:byte(x) + 
				unpacked:byte(#unpacked-png_bwidth+1)))
		end

	elseif ftyp == 3 then
		-- average xy
		for x=2,2+png_fstride-1 do
			unpacked = unpacked .. string.char(0xFF&(
				line:byte(x) + 
				(unpacked:byte(#unpacked-png_bwidth+1)>>1)))
		end
		for x=2+png_fstride,#line do
			unpacked = unpacked .. string.char(0xFF&(
				line:byte(x) + 
				((unpacked:byte(#unpacked-png_bwidth+1)
					+ unpacked:byte(#unpacked-png_fstride+1)
					)>>1)))
		end

	elseif ftyp == 4 then
		-- paeth

		for x=2,2+png_fstride-1 do
			unpacked = unpacked .. string.char(0xFF&(
				line:byte(x) + 
				paeth(0, unpacked:byte(#unpacked-png_bwidth+1), 0)))
		end
		for x=2+png_fstride,#line do
			unpacked = unpacked .. string.char(0xFF&(
				line:byte(x) + 
				paeth(
					unpacked:byte(#unpacked-png_fstride+1),
					unpacked:byte(#unpacked-png_bwidth+1),
					unpacked:byte(#unpacked-png_bwidth+1-png_fstride)
				)))
		end

	else
		print(ftyp)
		error("unhandled filter selection")
	end
end

-- bail out if not OC
if sysnative then return end

-- convert to screen
local gpu = require("component").gpu
local term = require("term")
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
term.clear()
local getter
local getalpha = function(self, x, y)
	local v = png_trns[getter(self, x, y)]
	if png_trns[v] then return 0 else return 255 end
end

if png_cm == 3 then
	getalpha = function(self, x, y)
		local pidx = getter(self, x, y, true)
		return png_trns[pidx] or 255
	end
end

if png_cm == 3 and png_bpc == 8 then
	getter = function(self, x, y, paletted)
		local v = unpacked:byte(y*self.png_bwidth+x+1)
		if paletted then
			return v+1
		else
			return PALETTE[v+1] or error("out of range palette index")
		end
	end
elseif png_cm == 3 and png_bpc == 4 then
	getter = function(self, x, y, paletted)
		local v = unpacked:byte(y*self.png_bwidth+(x>>1)+1)
		v = (v>>(4*(1~(x&1)))) & 0x0F
		if paletted then
			return v+1
		else
			return PALETTE[v+1] or error("out of range palette index")
		end
	end
elseif png_cm == 3 and png_bpc == 2 then
	getter = function(self, x, y, paletted)
		local v = unpacked:byte(y*self.png_bwidth+(x>>2)+1)
		v = (v>>(2*(3~(x&3)))) & 0x03
		if paletted then
			return v+1
		else
			return PALETTE[v+1] or error("out of range palette index")
		end
	end
elseif png_cm == 3 and png_bpc == 1 then
	getter = function(self, x, y, paletted)
		local v = unpacked:byte(y*self.png_bwidth+(x>>3)+1)
		v = (v>>(1*(7~(x&7)))) & 0x01
		if paletted then
			return v+1
		else
			return PALETTE[v+1] or error("out of range palette index")
		end
	end
elseif png_cm == 2 and png_bpc == 8 then
	getter = function(self, x, y, paletted)
		if paletted then error("not a paletted image") end
		local r = unpacked:byte(y*self.png_bwidth+x*3+1)
		local g = unpacked:byte(y*self.png_bwidth+x*3+2)
		local b = unpacked:byte(y*self.png_bwidth+x*3+3)
		return (r<<16)|(g<<8)|b
	end
elseif png_cm == 6 and png_bpc == 8 then
	getter = function(self, x, y, paletted)
		if paletted then error("not a paletted image") end
		local r = unpacked:byte(y*self.png_bwidth+x*4+1)
		local g = unpacked:byte(y*self.png_bwidth+x*4+2)
		local b = unpacked:byte(y*self.png_bwidth+x*4+3)
		return (r<<16)|(g<<8)|b
	end
	getalpha = function(self, x, y)
		return unpacked:byte(y*self.png_bwidth+x*4+4)
	end
else
	error(string.format("TODO: support this colour mode setup: cm=%d bpc=%d", png_cm, png_bpc))
end
return {
	w = png_w, h = png_h,
	get = getter, getAlpha = getalpha,
	isPaletted = function(self) return self.png_cm == 3 end,
	getPaletteCount = function(self)
		if self.png_cm == 3 then
			return 1 << self.png_bpc
		else
			return 0
		end
	end,
	getPaletteEntry = function(self, i)
		return PALETTE[i] or error("out of range palette index")
	end,

	png_cm = png_cm,
	png_bpc = png_bpc,
	png_bwidth = png_bwidth
}
end

return ocpng
