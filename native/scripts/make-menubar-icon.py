# Generates the monochrome template glyph used in the menu bar from Resources/P1.png:
#   python3 scripts/make-menubar-icon.py Resources/P1.png /tmp/out
#   tiffutil -cathidpicheck /tmp/out/MenuBarIcon.png /tmp/out/MenuBarIcon@2x.png -out Resources/MenuBarIcon.tiff
import os, sys
from PIL import Image, ImageChops, ImageFilter
src, outdir = sys.argv[1], sys.argv[2]
r = Image.open(src).convert("RGB").split()[0]
mask = ImageChops.subtract(r, Image.new("L", r.size, 40)).point(lambda v: 255 if v > 40 else 0)
mask = mask.filter(ImageFilter.MedianFilter(7)).filter(ImageFilter.GaussianBlur(3)).point(lambda v: 255 if v > 127 else 0)
mask = mask.crop(mask.getbbox())
side = max(mask.size)
square = Image.new("L", (side, side), 0)
square.paste(mask, ((side - mask.width) // 2, (side - mask.height) // 2))
for name, px in (("MenuBarIcon.png", 16), ("MenuBarIcon@2x.png", 32)):
    alpha = square.resize((px, px), Image.LANCZOS)
    img = Image.new("RGBA", (px, px), (0, 0, 0, 255))
    img.putalpha(alpha)
    img.save(os.path.join(outdir, name), dpi=(72 * px // 16, 72 * px // 16))
