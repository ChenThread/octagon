--[[
pngview: Simple high-resolution PNG viewer 
Copyright (c) 2016, 2017, 2018 asie

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

local args = {...}
local ocpng = require("png")
local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local keyboard = require("keyboard")
local text = require("text")
local os = require("os")
local pal = {}

-- 4x4 dithermask
--local oDither = {
--	0, 8, 2, 10,
--	12, 4, 14, 6,
--	3, 11, 1, 9,
--	15, 7, 13, 5
--}
-- 2x2 dithermask
local oDither = {
	0, 2,
	3, 1
}
local oDSize = #oDither
local oDWidth = math.floor(math.sqrt(#oDither))

local q = {}
for i=0,255 do
  local dat = (i & 0x01) << 7
  dat = dat | (i & 0x02) >> 1 << 6
  dat = dat | (i & 0x04) >> 2 << 5
  dat = dat | (i & 0x08) >> 3 << 2
  dat = dat | (i & 0x10) >> 4 << 4
  dat = dat | (i & 0x20) >> 5 << 1
  dat = dat | (i & 0x40) >> 6 << 3
  dat = dat | (i & 0x80) >> 7
  q[i + 1] = unicode.char(0x2800 | dat)
end

local function round(v)
  return math.floor(v + 0.5)
end

function resetPalette(data)
 for i=0,255 do
  if (i < 16) then
--    if data == nil or data[3] == nil or data[3][i] == nil then
      pal[i] = (i * 15) << 16 | (i * 15) << 8 | (i * 15)
--    else
--      pal[i] = data[3][i]
--      gpu.setPaletteColor(i, data[3][i])
--    end
  else
    local j = i - 16
    local b = math.floor((j % 5) * 255 / 4.0)
    local g = math.floor((math.floor(j / 5.0) % 8) * 255 / 7.0)
    local r = math.floor((math.floor(j / 40.0) % 6) * 255 / 5.0)
    pal[i] = r << 16 | g << 8 | b
  end
 end
end

resetPalette(nil)

local function pngSafeGet(png, x, y, paletted)
  if x >= png.w then x = png.w - 1 elseif x < 0 then x = 0 end
  if y >= png.h then y = png.h - 1 elseif y < 0 then y = 0 end
  return png:get(x, y, paletted)
end

local function maxAbs(r, g, b)
  local d1 = r - g
  local d2 = g - b
  if d1 < 0 then d1 = -d1 end
  if d2 < 0 then d2 = -d2 end
  if d1 >= d2 then return d1 else return d2 end
end

local function getOCPalEntry(png, data, rgb)
  -- TODO: more cleverness
  local r = (rgb >> 16) & 0xFF
  local g = (rgb >> 8) & 0xFF
  local b = (rgb) & 0xFF
  if maxAbs(r, g, b) <= 6 then
    local i = round(g * 16.0 / 255.0)
    if i <= 0 then return 16 elseif i >= 16 then return 255 else return i - 1 end
  else
    return 16 + (round(r * 5.0 / 255.0) * 40) + (round(g * 7.0 / 255.0) * 5) + round(b * 4.0 / 255.0)
  end
end

local function colorDistSq(rgb1, rgb2)
  if rgb1 == rgb2 then return 0 end

  local r1 = (rgb1 >> 16) & 0xFF
  local g1 = (rgb1 >> 8) & 0xFF
  local b1 = (rgb1) & 0xFF
  local r2 = (rgb2 >> 16) & 0xFF
  local g2 = (rgb2 >> 8) & 0xFF
  local b2 = (rgb2) & 0xFF
  local rs = (r1 - r2) * (r1 - r2)
  local gs = (g1 - g2) * (g1 - g2)
  local bs = (b1 - b2) * (b1 - b2)
  local rAvg = math.floor((r1 + r2) / 2)

  return (((512 + rAvg) * rs) >> 8) + (4 * gs) + (((767 - rAvg) * bs) >> 8)
end

-- inspired by the teachings of Bisqwit
-- http://bisqwit.iki.fi/story/howto/dither/jy/
local function ditherDistance(rgb, rgb1, rgb2)
  if rgb1 == rgb2 then return 0.5 end

  local r = (rgb >> 16) & 0xFF
  local g = (rgb >> 8) & 0xFF
  local b = (rgb) & 0xFF
  local r1 = (rgb1 >> 16) & 0xFF
  local g1 = (rgb1 >> 8) & 0xFF
  local b1 = (rgb1) & 0xFF
  local r2 = (rgb2 >> 16) & 0xFF
  local g2 = (rgb2 >> 8) & 0xFF
  local b2 = (rgb2) & 0xFF

  return (r * r1 - r * r2 - r1 * r2 + r2 * r2 +
    g * g1 - g * g2 - g1 * g2 + g2 * g2 +
    b * b1 - b * b2 - b1 * b2 + b2 * b2) /
    ((r1 - r2) * (r1 - r2) +
      (g1 - g2) * (g1 - g2) +
      (b1 - b2) * (b1 - b2));
end

function loadImage(filename)
  local png = ocpng.loadPNG(filename)

  local charH = math.ceil(png.h / 4.0)
  local charW = math.ceil(png.w / 2.0)
  local data = {}

  data[1] = {}
  data[2] = {charW, charH}
  data[3] = {}

  -- todo: populate with customColors [3][0]...

  local j = 1
  for y=0,charH-1 do
    for x=0,charW-1 do
      local pixelsRGB = {
        pngSafeGet(png, x*2+1, y*4+3),
        pngSafeGet(png, x*2, y*4+3),
        pngSafeGet(png, x*2+1, y*4+2),
        pngSafeGet(png, x*2, y*4+2),
        pngSafeGet(png, x*2+1, y*4+1),
        pngSafeGet(png, x*2, y*4+1),
        pngSafeGet(png, x*2+1, y*4),
        pngSafeGet(png, x*2, y*4)
      }
      local pixels = {}
      for i=1,#pixelsRGB do pixels[i] = getOCPalEntry(png, data, pixelsRGB[i]) end
      -- identify most common colors
      local pixelCount = {}
      local pixelColors = 0
      for i=1,#pixels do
        if pixelCount[pixels[i]] == nil then pixelColors = pixelColors + 1 end
        pixelCount[pixels[i]] = (pixelCount[pixels[i]] or 0) + 1
      end
      if pixelColors == 1 then
        data[1][j] = (0 << 16) | (0 << 8) | pixels[1]
      else
        local bg = -1
        local bgc = -1
        local fg = -1
        local fgc = -1
        for k,v in pairs(pixelCount) do
          if v > bgc then
            bg = k
            bgc = v
          end
        end
        for k,v in pairs(pixelCount) do
          local contrast = colorDistSq(pal[bg], pal[k]) * v
          if k ~= bg and contrast > fgc then
            fg = k
            fgc = contrast
          end
        end
        local chr = 0
        for i=1,#pixels do
          local px = x * 2 + ((i - 1) & 1)
          local py = y * 4 + ((i - 1) >> 1)
          local dDist = ditherDistance(pixelsRGB[i], pal[bg], pal[fg])
          local dDi = oDSize - round(dDist * oDSize)
          local dThr = oDither[1 + ((py % oDWidth) * oDWidth) + (px % oDWidth)]
          if dThr < dDi then
            chr = chr | (1 << (i - 1))
          end
        end
        data[1][j] = bg | (fg << 8) | (chr << 16)
      end
      j = j + 1
    end
  end

  return data
end

function gpuBG()
  local a, al = gpu.getBackground()
  if al then
    return gpu.getPaletteColor(a)
  else
    return a
  end
end
function gpuFG()
  local a, al = gpu.getForeground()
  if al then
    return gpu.getPaletteColor(a)
  else
    return a
  end
end

function drawImage(data, offx, offy)
  if offx == nil then offx = 0 end
  if offy == nil then offy = 0 end

  local WIDTH = data[2][1]
  local HEIGHT = data[2][2]

  gpu.setResolution(WIDTH, HEIGHT)
  resetPalette(data)

  local bg = 0
  local fg = 0
  local cw = 1
  local noBG = false
  local noFG = false
  local ind = 1

  local gBG = gpuBG()
  local gFG = gpuFG()

  for y=0,HEIGHT-1 do
    local str = ""
    for x=0,WIDTH-1 do
      ind = (y * WIDTH) + x + 1
      bg = pal[data[1][ind] & 0xFF]
      fg = pal[(data[1][ind] >> 8) & 0xFF]
      cw = ((data[1][ind] >> 16) & 0xFF) + 1
      noBG = (cw == 256)
      noFG = (cw == 1)
      if (noFG or (gBG == fg)) and (noBG or (gFG == bg)) then
        str = str .. q[257 - cw]
--        str = str .. "I"
      elseif (noBG or (gBG == bg)) and (noFG or (gFG == fg)) then
        str = str .. q[cw]
      else
        if #str > 0 then
          gpu.set(x + 1 + offx - unicode.wlen(str), y + 1 + offy, str)
        end
        if (gBG == fg and gFG ~= bg) or (gFG == bg and gBG ~= fg) then
          cw = 257 - cw
          local t = bg
          bg = fg
          fg = t
        end
        if gBG ~= bg then
          gpu.setBackground(bg)
          gBG = bg
        end
        if gFG ~= fg then
          gpu.setForeground(fg)
          gFG = fg
        end
        str = q[cw]
--        if (not noBG) and (not noFG) then str = "C" elseif (not noBG) then str = "B" elseif (not noFG) then str = "F" else str = "c" end
      end
    end
    if #str > 0 then
      gpu.set(WIDTH + 1 - unicode.wlen(str) + offx, y + 1 + offy, str)
    end
  end
end

local image = loadImage(args[1])
drawImage(image)

while true do
    local name,addr,char,key,player = event.pull("key_down")
    if key == 0x10 then
        break
    end
end

gpu.setBackground(0, false)
gpu.setForeground(16777215, false)
gpu.setResolution(80, 25)
gpu.fill(1, 1, 80, 25, " ")
