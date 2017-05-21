--[[
ocunzip: unzip zip files in opencomputers
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

local crc = dofile("./crc32.lua")
local inflate = dofile("./inflate.lua")

local fname = ...

local outdir = "results/"
local HACKS = true

-- detect if we're running on OC or a native system
local sysnative = not not package.loadlib

-- readers
function readu8(fp)
	return fp:read(1):byte()
end
function readu16(fp)
	local v1 = readu8(fp)
	local v2 = readu8(fp)
	return v1 + (v2*256)
end
function readu32(fp)
	local v1 = readu16(fp)
	local v2 = readu16(fp)
	return v1 + (v2*65536)
end

assert(fname, "provide a filename as an argument")

infp = io.open(fname, "rb")
while true do
	-- ZIP file header (we unzip from file start here)
	local magic = infp:read(4)
	if magic ~= "PK\x03\x04" then
		-- check for central directory header
		if magic == "PK\x01\x02" then break end

		-- nope? ok, we've gone off the rails here
		error("invalid zip magic")
	end
	zver = readu16(infp)
	zflags = readu16(infp)
	zcm = readu16(infp)
	assert(zver <= 20, "we don't support features above zip 2.0")
	--print(zflags)
	assert(zflags & 0xF7F9 == 0, "zip relies on features we don't support (e.g. encraption)")
	--assert(zflags & 0xF7F1 == 0, "zip relies on features we don't support (e.g. encraption)")
	assert(zcm == 0 or zcm == 8, "we don't support stupid compression modes")
	readu32(infp) -- last modified time, date
	zcrc = readu32(infp)
	zcsize = readu32(infp)
	zusize = readu32(infp)
	zfnlen = readu16(infp)
	zeflen = readu16(infp)
	assert(zfnlen >= 1, "extracting empty file name")
	zfname = infp:read(zfnlen)
	assert(zfname:len() == zfnlen)
	zefield = infp:read(zeflen)
	assert(zefield:len() == zeflen)
	print("Extracting \""..zfname.."\" (csize="..zcsize..", usize="..zusize..")...")
	cmpdata = infp:read(zcsize)
	assert(cmpdata:len() == zcsize)

	if HACKS and zcrc == 1389383875 and zcsize == 87145 and zusize == 2189817 then
		-- this file takes forever to uncompress
		print("SKIPPED")
	else
		ucmpdata = ((zcm == 8 and inflate.inflate(string.char(0x78) .. string.char(1) .. cmpdata)) or cmpdata)
		assert(ucmpdata:len() == zusize)
		assert(crc.crc32(ucmpdata) == (zcrc & 0xFFFFFFFF), "CRC mismatch")

		if zfname:sub(-1) == "/" then
			os.execute("mkdir -p \""..outdir..zfname.."\"")
		else
			outfp = io.open(outdir..zfname, "wb")
			outfp:write(ucmpdata)
			outfp:close()
		end
	end
end
