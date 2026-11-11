# Regenerates Resources/AppIcon.png (macOS-style tile) from Resources/P1.png:
#   python3 scripts/make-icon.py Resources/P1.png Resources/AppIcon.png
# then rebuild Resources/AppIcon.icns with sips + iconutil.
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops
src, out = sys.argv[1], sys.argv[2]
S = 4  # supersample
N = 1024 * S
im = Image.open(src).convert("RGB")
# glyph mask: purple has high blue+red vs navy background
r, g, b = im.split()
mask = ImageChops.subtract(r, Image.new("L", im.size, 40)).point(lambda v: 255 if v > 40 else 0)
mask = mask.filter(ImageFilter.MedianFilter(7)).filter(ImageFilter.GaussianBlur(3)).point(lambda v: 255 if v > 127 else 0)
bbox = mask.getbbox()
glyph_mask = mask.crop(bbox)
purple = (108, 99, 220)
# tile geometry (Apple macOS template: 824pt body in 1024 canvas)
tile = 824 * S; off = 100 * S; radius = int(tile * 0.2237)
# gradient fill for tile
top, bot = (20, 26, 74), (5, 10, 38)
grad = Image.new("RGB", (1, tile))
for y in range(tile):
    t = y / (tile - 1)
    grad.putpixel((0, y), tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
grad = grad.resize((tile, tile))
tile_mask = Image.new("L", (tile, tile), 0)
ImageDraw.Draw(tile_mask).rounded_rectangle([0, 0, tile - 1, tile - 1], radius=radius, fill=255)
canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
# drop shadow
sh = Image.new("L", (N, N), 0)
sh.paste(tile_mask, (off, off + 12 * S))
sh = sh.filter(ImageFilter.GaussianBlur(14 * S)).point(lambda v: int(v * 0.35))
canvas.paste(Image.new("RGBA", (N, N), (0, 0, 0, 255)), (0, 0), sh)
tile_img = grad.convert("RGBA"); tile_img.putalpha(tile_mask)
canvas.alpha_composite(tile_img, (off, off))
# subtle inner top highlight stroke
hl = Image.new("L", (tile, tile), 0)
ImageDraw.Draw(hl).rounded_rectangle([0, 0, tile - 1, tile - 1], radius=radius, outline=255, width=3 * S)
fade = Image.linear_gradient("L").resize((tile, tile)).point(lambda v: int((255 - v) * 0.18))
hl = ImageChops.multiply(hl, fade)
canvas.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (tile, tile), (255, 255, 255)).split(), hl)), (off, off))
# glyph: fit in ~62% of the tile, optically centred
gw, gh = glyph_mask.size
target = int(tile * 0.62)
scale = target / max(gw, gh)
gm = glyph_mask.resize((int(gw * scale), int(gh * scale)), Image.LANCZOS)
gx = off + (tile - gm.width) // 2
gy = off + (tile - gm.height) // 2
glyph = Image.new("RGBA", gm.size, purple + (255,)); glyph.putalpha(gm)
canvas.alpha_composite(glyph, (gx, gy))
canvas.resize((1024, 1024), Image.LANCZOS).save(out)
print("bbox", bbox)
