--[[
ocpng: show a png in opencomputers
Copyright (c) 2015-16 GreaseMonkey

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

local fname = ...

-- detect if we're running on OC or a native system
local sysnative = not not package.loadlib

-- CRC32 implementation
-- standard table lookup version
do
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

	function crc32(str, v)
		v = v or 0
		v = v ~ 0xFFFFFFFF

		local i
		for i=1,#str do
			--print(str:byte(i))
			v = (v >> 8) ~ crctab[((v&0xFF) ~ str:byte(i))+1]
		end

		v = v ~ 0xFFFFFFFF
		return v
	end
end

function inflate(data)
	-- we aren't using data cards here
	-- anyhow, skip the first 2 bytes because i cannot be fucked with the header
	local pos = 2*8
	local ret = ""
	local retcomb = ""

	local function get(sz)
		if (pos>>3) >= #data then error("unexpected EOF in deflate stream") end
		local v = data:byte((pos>>3)+1) >> (pos&7)
		local boffs = 0
		if sz < 8-(pos&7) then
			pos = pos + sz
		else
			local boffs = (8-(pos&7))
			local brem = sz - boffs
			pos = pos + boffs

			while brem > 8 do
				if (pos>>3) >= #data then error("unexpected EOF in deflate stream") end
				v = v | (data:byte((pos>>3)+1)<<boffs)
				boffs = boffs + 8
				brem = brem - 8
				pos = pos + 8
			end

			if (pos>>3) >= #data then error("unexpected EOF in deflate stream") end
			v = v | (data:byte((pos>>3)+1)<<boffs)
			pos = pos + brem
		end

		return v & ((1<<sz)-1)
	end

	local function buildhuff(tab, tablen)
		local i
		local lsort = {}

		-- categorise by length
		for i=1,15 do lsort[i] = {} end
		for i=1,tablen do
			if tab[i] ~= 0 then
				table.insert(lsort[tab[i]], i-1)
			end
		end

		-- sort each by index
		for i=1,15 do table.sort(lsort[i]) end

		-- build bit selection table
		local llim = {}
		local v = 0
		for i=1,15 do
			v = (v << 1) + #lsort[i]
			--print(i, v)
			llim[i] = v
			assert(v <= (1<<i))
		end
		assert(v == (1<<15))

		return function()
			local v = 0
			local i
			for i=1,15 do
				v = (v<<1) + get(1)
				if v < llim[i] then
					return (lsort[i][1+(v-llim[i]+#lsort[i])] or
						error("lookup overflow"))
				end
			end

			error("we seem to have an issue with this huffman tree")
		end
	end

	local bfinal = false
	local btype

	local decoders = {}
	decoders[0+1] = function()
		pos = (pos+7)&~7
		local len, nlen = string.unpack("<2I <2I", data:sub(pos, pos+4-1))
		if len ~ nlen ~= 0xFFFF then error("stored block complement check failed") end
		error("TODO: stored deflate block")
	end
	decoders[1+1] = function()
		error("TODO: fixed huffman deflate block")
	end
	decoders[2+1] = function()
		local i, j

		local hlit = get(5)+257
		local hdist = get(5)+1
		local hclen = get(4)+4
		--print(hlit, hdist, hclen)

		local HCMAP = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15}
		local hctab = {}

		-- code lengths
		for i=0,18 do hctab[i+1] = 0 end
		for i=1,hclen do
			hctab[HCMAP[i]+1] = get(3)
			--print(HCMAP[i], hctab[HCMAP[i]+1])
		end
		local hctree = buildhuff(hctab, 19)

		-- literals
		local hltab = {}
		i = 1
		while i <= hlit do
			local v = hctree()
			if v <= 15 then
				hltab[i] = v
				i = i + 1
			elseif v == 16 then
				assert(i >= 2)
				for j=1,get(2)+3 do
					hltab[i] = hltab[i-1]
					i = i + 1
				end
			elseif v == 17 then
				for j=1,get(3)+3 do
					hltab[i] = 0
					i = i + 1
				end
			elseif v == 18 then
				for j=1,get(7)+11 do
					hltab[i] = 0
					i = i + 1
				end
			else
				error("hctree decoding issue")
			end
		end
		assert(i == hlit+1)

		local hdtab = {}
		i = 1
		while i <= hdist do
			local v = hctree()
			if v <= 15 then
				hdtab[i] = v
				i = i + 1
			elseif v == 16 then
				assert(i >= 2)
				for j=1,get(2)+3 do
					hdtab[i] = hdtab[i-1]
					i = i + 1
				end
			elseif v == 17 then
				for j=1,get(3)+3 do
					hdtab[i] = 0
					i = i + 1
				end
			elseif v == 18 then
				for j=1,get(7)+11 do
					hdtab[i] = 0
					i = i + 1
				end
			else
				error("hctree decoding issue")
			end
		end
		assert(i == hdist+1)

		local hltree = buildhuff(hltab, hlit)
		local hdtree = buildhuff(hdtab, hdist)

		return hltree, hdtree
		--error("TODO: dynamic huffman deflate block")
	end

	local function lzss(len, dist)
		if dist <= 3 then
			dist = dist + 1
		elseif dist <= 29 then
			-- i refuse to type this whole thing out
			local subdist = ((dist-4)>>1)
			--print(dist)
			local nd = get(subdist+1)
			dist = 1 + (1<<(subdist+2)) + ((dist&1)<<(subdist+1)) + nd
			--print(dist, nd)
		else
			print(dist)
			error("invalid deflate distance table code")
		end

		-- TODO: optimise
		assert(dist >= 1)
		local i
		local idx = #ret-dist+1
		if idx < 1 then
			-- pull back from combined return
			ret = retcomb:sub(#retcomb+idx) .. ret
			retcomb = retcomb:sub(1,#retcomb+idx-1)
			idx = 1
		end
		assert(idx >= 1)
		assert(idx <= #ret)
		for i=1,len do
			ret = ret .. ret:sub(idx, idx)
			idx = idx + 1
		end
	end

	while not bfinal do
		ret = ""
		bfinal = (get(1) ~= 0)
		btype = get(2)
		if btype == 3 then error("invalid block mode") end
		if sysnative then print("block", btype, bfinal) end

		local tfetch, tgetdist = decoders[btype+1]()

		while true do
			local v = tfetch()
			if v <= 255 then
				ret = ret .. string.char(v)
			elseif v == 256 then
				break
			elseif v >= 257 and v <= 264 then
				lzss(v-257 + 3, tgetdist())
			elseif v >= 265 and v <= 268 then
				lzss((v-265)*2 + 11 + get(1), tgetdist())
			elseif v >= 269 and v <= 272 then
				lzss((v-269)*4 + 19 + get(2), tgetdist())
			elseif v >= 273 and v <= 276 then
				lzss((v-273)*8 + 35 + get(3), tgetdist())
			elseif v >= 277 and v <= 280 then
				lzss((v-277)*16 + 67 + get(4), tgetdist())
			elseif v >= 281 and v <= 284 then
				lzss((v-281)*32 + 131 + get(5), tgetdist())
			elseif v >= 285 then
				lzss(258, tgetdist())
			else
				print(v)
				error("invalid deflate literal table code")
			end
		end

		--error("TODO!")
		retcomb = retcomb .. ret
		if not sysnative then os.sleep(0.05) end
	end

	--print(#ret)
	return retcomb
end

assert(fname, "provide a filename as an argument")

-- PNG magic header
fp = io.open(fname, "rb")
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

local idat_accum = ""
while true do
	local clen_s = fp:read(4)
	local clen = string.unpack(">I4", clen_s)
	local ctyp = fp:read(4)
	local cdat = fp:read(clen)
	local ccrc = string.unpack(">I4", fp:read(4))

	--print(ctyp, string.format("%08X", ccrc), clen)
	local acrc = crc32(ctyp..cdat)
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
				+ (cdat:byte(3*i+1)<<16)
				+ (cdat:byte(3*i+2)<<8)
				+ (cdat:byte(3*i+3)))
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

-- check if we have a datacard
if not sysnative then
	pcall(function()
		local component = require("component")
		if component.data then
			--print("FOUND DATA CARD")
			inflate = component.data.inflate
		end
	end)
end

-- actually decompress image
if sysnative then print("Inflating...") end
local png_data = inflate(idat_accum)

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
local converter

if png_cm == 3 and png_bpc == 8 then
	converter = function(x, y)
		local v = unpacked:byte(y*png_bwidth+x+1)
		return PALETTE[v+1] or error("out of range palette index")
	end
elseif png_cm == 3 and png_bpc == 4 then
	converter = function(x, y)
		local v = unpacked:byte(y*png_bwidth+(x>>1)+1)
		v = (v>>(4*(1~(x&1)))) & 0x0F
		return PALETTE[v+1] or error("out of range palette index")
	end
elseif png_cm == 3 and png_bpc == 2 then
	converter = function(x, y)
		local v = unpacked:byte(y*png_bwidth+(x>>2)+1)
		v = (v>>(2*(3~(x&3)))) & 0x03
		return PALETTE[v+1] or error("out of range palette index")
	end
elseif png_cm == 3 and png_bpc == 1 then
	converter = function(x, y)
		local v = unpacked:byte(y*png_bwidth+(x>>3)+1)
		v = (v>>(1*(7~(x&7)))) & 0x01
		return PALETTE[v+1] or error("out of range palette index")
	end
elseif png_cm == 2 and png_bpc == 8 then
	converter = function(x, y)
		local r = unpacked:byte(y*png_bwidth+x*3+1)
		local g = unpacked:byte(y*png_bwidth+x*3+2)
		local b = unpacked:byte(y*png_bwidth+x*3+3)
		return (r<<16)|(g<<8)|b
	end
elseif png_cm == 6 and png_bpc == 8 then
	converter = function(x, y)
		local r = unpacked:byte(y*png_bwidth+x*4+1)
		local g = unpacked:byte(y*png_bwidth+x*4+2)
		local b = unpacked:byte(y*png_bwidth+x*4+3)
		return (r<<16)|(g<<8)|b
	end
else
	error(string.format("TODO: support this colour mode setup: cm=%d bpc=%d", png_cm, png_bpc))
end
local x, y
local ctr = 0
for y=0,png_h-1 do
for x=0,png_w-1 do
	if ctr < 127 then
		gpu.setBackground(converter(x, y))
		gpu.set(x, y, " ")
	else--if ctr < 254 then
		gpu.setForeground(converter(x, y))
		gpu.set(x, y, "█")
	end
	ctr = ctr + 1
	ctr = ctr % 254
end
end

gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)

