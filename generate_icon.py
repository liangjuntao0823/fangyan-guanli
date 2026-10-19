"""在 GitHub Actions 的 macOS runner 上生成 AppIcon.png（需 pillow）。

与本地工程 Assets.xcassets 中的图标使用同一绘制逻辑。
"""
from PIL import Image, ImageDraw

size = 1024
img = Image.new('RGB', (size, size), (30, 48, 72))
d = ImageDraw.Draw(img)

# 垂直渐变背景：深墨蓝
top = (60, 88, 126)
bottom = (20, 38, 60)
for y in range(size):
    t = y / size
    r = int(top[0] + (bottom[0] - top[0]) * t)
    g = int(top[1] + (bottom[1] - top[1]) * t)
    b = int(top[2] + (bottom[2] - top[2]) * t)
    d.line([(0, y), (size, y)], fill=(r, g, b))

# 主楼（白色圆角矩形）
d.rounded_rectangle([370, 250, 760, 760], radius=26, fill=(245, 248, 252))
wx0, wy0, ww, wh = 402, 300, 52, 60
for row in range(6):
    for col in range(3):
        x = wx0 + col * (ww + 22)
        y = wy0 + row * (wh + 18)
        d.rounded_rectangle([x, y, x + ww, y + wh], radius=10, fill=(38, 62, 92))

# 矮楼（左侧）
d.rounded_rectangle([240, 430, 470, 780], radius=20, fill=(232, 237, 244))
for row in range(4):
    for col in range(2):
        x = 262 + col * (58 + 20)
        y = 462 + row * (54 + 20)
        d.rounded_rectangle([x, y, x + 58, y + 54], radius=9, fill=(70, 96, 128))

# 金色钥匙（斜置右下）
key = Image.new('RGBA', (size, size), (0, 0, 0, 0))
kd = ImageDraw.Draw(key)
gold = (226, 166, 75)
kd.ellipse([640, 640, 800, 800], outline=gold, width=40)
kd.rounded_rectangle([760, 690, 890, 742], radius=26, fill=gold)
kd.rounded_rectangle([820, 742, 862, 792], radius=12, fill=gold)
kd.rounded_rectangle([854, 742, 896, 780], radius=12, fill=gold)
key = key.rotate(-18, resample=Image.BICUBIC)

img = Image.alpha_composite(img.convert('RGBA'), key).convert('RGB')
out = 'HouseKeeper/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
img.save(out)
print('AppIcon generated:', out)
