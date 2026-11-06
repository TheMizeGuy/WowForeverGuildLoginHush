"""Project logo for Guild Login Hush: a bell with a strike through it on a dark disc, 400x400,
drawn at 4x and downsampled for smooth edges."""
import sys
from PIL import Image, ImageDraw

S = 4
W = 400 * S
img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# disc
d.ellipse((8 * S, 8 * S, W - 8 * S, W - 8 * S), fill=(31, 38, 48, 255), outline=(70, 82, 98, 255), width=6 * S)

# bell: dome + flared body + rim + clapper, in warm gold
gold = (232, 183, 74, 255)
dark_gold = (176, 128, 40, 255)
cx = W // 2
top = 92 * S
# handle knob
d.ellipse((cx - 14 * S, top - 6 * S, cx + 14 * S, top + 22 * S), fill=gold)
# dome
d.pieslice((cx - 92 * S, top + 10 * S, cx + 92 * S, top + 194 * S), 180, 360, fill=gold)
# body: trapezoid down to the rim
body = [(cx - 92 * S, top + 102 * S), (cx + 92 * S, top + 102 * S), (cx + 118 * S, top + 212 * S), (cx - 118 * S, top + 212 * S)]
d.polygon(body, fill=gold)
# rim
d.rounded_rectangle((cx - 126 * S, top + 204 * S, cx + 126 * S, top + 226 * S), radius=10 * S, fill=dark_gold)
# clapper
d.ellipse((cx - 22 * S, top + 222 * S, cx + 22 * S, top + 266 * S), fill=dark_gold)

# strike: a white-edged red bar from upper left to lower right
import math
x0, y0, x1, y1 = 96 * S, 86 * S, W - 96 * S, W - 86 * S
d.line((x0, y0, x1, y1), fill=(31, 38, 48, 255), width=46 * S)
d.line((x0, y0, x1, y1), fill=(214, 64, 64, 255), width=28 * S)
for (x, y) in ((x0, y0), (x1, y1)):
    d.ellipse((x - 14 * S, y - 14 * S, x + 14 * S, y + 14 * S), fill=(214, 64, 64, 255))

out = img.resize((400, 400), Image.LANCZOS)
out.save(sys.argv[1])
print(out.size, out.mode)
