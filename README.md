octagon: the *jack* of all OpenComputers trades

MIT-licensed, see the files themselves for confirmation

**crc32.lua**: CRC32 implementation. Optionally uses the Data card for acceleration.

* crc32.crc32(data, start_value) - calculate CRC32. Optionally change the start value used.

**inflate.lua**: inflate decompression implementation. Optionally uses the Data Card for acceleration.

* inflate.inflate(data): like a balloon.

**png.lua**: PNG reader. Depends on crc32.lua and inflate.lua.

* png.loadPNG(filename): loads specified PNG file. The result is a table with the following functions exposed:
    * w, h - actually fields, the width and height of the image
    * get(x, y, paletted) - gets a specific pixel color, RGB888. If paletted is true and the image is paletted, returns a palette index instead.
    * getAlpha(x, y) - gets the alpha value for a specific location (0-255).
    * isPaletted() - returns true if the image is paletted.
    * getPaletteCount() - returns the amount of colors if the image is paletted, 0 otherwise.
    * getPaletteEntry(i) - returns the specified palette entry.

Keep in mind palette colors are 1-indexed here, so a 16-color image has palette colors 1, 2, ..., 16.

It's a bit incomplete, so please get in touch if your PNGs depend on the following:

* grayscale images (not otherwise indexed or RGB)
* 16bpc images (that is, 48/64bpp)

Additionally, please get in touch if you need the following features:

* sPLT and hIST chunks (for viewer palette adjustment, I assume, does anyone use/provide these though?)

Currently out of scope:

* any gamma/colorspace adjustments at all

**oczip.lua**: ZIP decompression. Depends on crc32.lua and inflate.lua.

Currently, it only works as a program and not as a library. "oczip [filename]" with a hardcoded output path "results/".

TODO: Refactor into a library.
