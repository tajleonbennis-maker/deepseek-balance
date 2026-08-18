#!/usr/bin/env python3
"""生成 DeepSeekBalance 应用图标：深蓝渐变圆角方块 + ¥ 符号，输出 .icns"""
import os, subprocess
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 1024

# ---- 绘制 1024x1024 主图 ----
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# 圆角矩形遮罩（约 22% 圆角，macOS 风格）
radius = int(SIZE * 0.22)
mask = Image.new("L", (SIZE, SIZE), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE, SIZE], radius=radius, fill=255)

# 深蓝到蓝的渐变
top = (13, 37, 71)      # #0D2547
bottom = (37, 118, 235) # #2576EB
grad = Image.new("RGBA", (1, SIZE))
for y in range(SIZE):
    t = y / SIZE
    c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    grad.putpixel((0, y), c + (255,))
grad = grad.resize((SIZE, SIZE))
img.paste(grad, (0, 0), mask)

# 底部一点高光弧（可选，增加立体感）
glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse(
    [int(SIZE*0.10), int(SIZE*0.68), int(SIZE*0.90), int(SIZE*1.18)],
    fill=(255, 255, 255, 26))
img = Image.alpha_composite(img, glow)

# ¥ 符号（白色，居中）
font_candidates = [
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial Unicode.ttf",
]
font = None
for fp in font_candidates:
    if os.path.exists(fp):
        try:
            font = ImageFont.truetype(fp, int(SIZE * 0.52))
            break
        except Exception:
            continue
if font is None:
    font = ImageFont.load_default()

draw = ImageDraw.Draw(img)
text = "¥"
bbox = draw.textbbox((0, 0), text, font=font, anchor=None)
tw = bbox[2] - bbox[0]
th = bbox[3] - bbox[1]
draw.text(((SIZE - tw) / 2 - bbox[0], (SIZE - th) / 2 - bbox[1]), text,
          font=font, fill=(255, 255, 255, 255))

png1024 = os.path.join(HERE, "icon_1024.png")
img.save(png1024)

# ---- 生成 iconset 并转 icns ----
iconset = os.path.join(HERE, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
specs = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for name, size in specs:
    out = os.path.join(iconset, name)
    img.resize((size, size), Image.LANCZOS).save(out)

icns = os.path.join(HERE, "AppIcon.icns")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
print("OK ->", icns)
