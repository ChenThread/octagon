--[[
inflate: like a balloon
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

local sysnative = not not package.loadlib
local datacard = nil
if not sysnative then
	local component = require("component")
	if component.isAvailable("data") then
		datacard = component.data
	end
end

local inflate = {}

function inflate.inflate(data)
	if datacard ~= nil then
		return datacard.inflate(data)
	end

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
		if not sysnative then os.sleep(0) end
	end

	--print(#ret)
	return retcomb
end

return inflate
