#!/usr/bin/env python3
#
# Build the Tomato64 boot splash assets for the GL-BE14000 front panel.
#
#     ./gen-splash.py [source.png]
#
# The source is the 1024x1024 artwork of Tux holding a tomato. It is not kept
# in the tree; the outputs are, and this script documents how they were made.
#
# files/tux.png     320x240, the full-screen splash
# files/tomato.png  the progress marker that travels along the bottom
#
# lv.image_load() decodes a PNG to RGB565 and DISCARDS ALPHA, so nothing here
# can rely on transparency. The marker is therefore composited onto the exact
# colour of the band it travels over, and boot_tomato64.uc paints that band
# with the colour this script prints.

import os
import sys
from PIL import Image, ImageChops

W, H = 320, 240

# Bottom band the progress track runs along. Below Tux's feet.
BAND_H = 22

MARKER = 18

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'files')


def splash(src):
    bg = src.getpixel((2, 2))

    # The artwork has a wide empty margin; crop to the content so Tux fills
    # the height rather than floating small in the middle.
    flat = Image.new('RGB', src.size, bg)
    mask = ImageChops.difference(src, flat).convert('L').point(lambda v: 255 if v > 12 else 0)
    x0, y0, x1, y1 = mask.getbbox()
    pad = 12
    art = src.crop((max(0, x0 - pad), max(0, y0 - pad),
                    min(src.width, x1 + pad), min(src.height, y1 + pad)))
    art.thumbnail((W, H), Image.LANCZOS)

    canvas = Image.new('RGB', (W, H))
    ox, oy = (W - art.width) // 2, (H - art.height) // 2
    canvas.paste(art, (ox, oy))

    # The source background is a vignette, not a flat colour, so pad by
    # replicating the art's own edge columns: a constant fill leaves a seam.
    left = art.crop((0, 0, 1, art.height))
    right = art.crop((art.width - 1, 0, art.width, art.height))
    for x in range(ox):
        canvas.paste(left, (x, oy))
    for x in range(ox + art.width, W):
        canvas.paste(right, (x, oy))

    return canvas


def band_colour(canvas):
    # Mean of the strip the band covers, so the band edge is quiet.
    strip = canvas.crop((0, H - BAND_H, W, H))
    px = list(strip.getdata())
    return tuple(sum(c[i] for c in px) // len(px) for i in range(3))


def is_tomato(r, g, b):
    # Red and its pink highlight both have green close to blue. Tux's orange
    # beak, which reaches into this region, has green far above blue - that is
    # what separates it, not how red it is.
    red = r > 150 and r > g + 25 and r > b + 25 and abs(g - b) < 60
    stem = g > 120 and g > r + 20 and b < 120		# the green calyx
    return red or stem


def marker(src, band):
    # Region holding the tomato and its stem, clear of Tux's body and feet.
    region = src.crop((165, 265, 450, 560))
    px = region.load()
    out = Image.new('RGB', region.size, band)
    opx = out.load()

    for y in range(region.height):
        for x in range(region.width):
            if is_tomato(*px[x, y]):
                opx[x, y] = px[x, y]

    # Composite at full size, then scale: the resampling blends the edge
    # into the band colour rather than into black.
    side = max(out.size)
    square = Image.new('RGB', (side, side), band)
    square.paste(out, ((side - out.width) // 2, (side - out.height) // 2))

    return square.resize((MARKER, MARKER), Image.LANCZOS)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else '/home/lance/tux.png'
    src = Image.open(path).convert('RGB')

    canvas = splash(src)
    band = band_colour(canvas)

    canvas.save(os.path.join(OUT, 'tux.png'), optimize=True)
    marker(src, band).save(os.path.join(OUT, 'tomato.png'), optimize=True)

    print('band colour 0x%02x%02x%02x  (BAND in boot_tomato64.uc)' % band)


if __name__ == '__main__':
    main()
