import os
from PIL import Image, ImageDraw, ImageFont

sizes = {
    r"d:\project\D2PDF\d2pdf_app\android\app\src\main\res\mipmap-mdpi\ic_launcher.png": 48,
    r"d:\project\D2PDF\d2pdf_app\android\app\src\main\res\mipmap-hdpi\ic_launcher.png": 72,
    r"d:\project\D2PDF\d2pdf_app\android\app\src\main\res\mipmap-xhdpi\ic_launcher.png": 96,
    r"d:\project\D2PDF\d2pdf_app\android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png": 144,
    r"d:\project\D2PDF\d2pdf_app\android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png": 192,
}

base_size = 512
img = Image.new("RGBA", (base_size, base_size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Background rounded rectangle: deep dark blue / modern hi-pda style
bg_color = (25, 45, 80, 255) # deep blue
corner_radius = 110
draw.rounded_rectangle([0, 0, base_size, base_size], radius=corner_radius, fill=bg_color)

# Draw inner border/shadow for elegance
draw.rounded_rectangle([8, 8, base_size-8, base_size-8], radius=corner_radius-6, outline=(60, 95, 150, 255), width=6)

# Try font
font_hi = None
font_pad = None
for font_name in ["arialbd.ttf", "segoeuib.ttf", "simhei.ttf", "msyhbd.ttc", "arial.ttf"]:
    font_path = os.path.join(os.environ.get("WINDIR", "C:\\Windows"), "Fonts", font_name)
    if os.path.exists(font_path):
        try:
            font_hi = ImageFont.truetype(font_path, 190)
            font_pad = ImageFont.truetype(font_path, 175)
            break
        except Exception:
            continue

if not font_hi:
    font_hi = ImageFont.load_default()
    font_pad = ImageFont.load_default()

# Draw "Hi!" and "PDA"
text1 = "Hi!"
text2 = "PDA"

# Measure text
bbox1 = draw.textbbox((0, 0), text1, font=font_hi)
w1 = bbox1[2] - bbox1[0]
h1 = bbox1[3] - bbox1[1]

bbox2 = draw.textbbox((0, 0), text2, font=font_pad)
w2 = bbox2[2] - bbox2[0]
h2 = bbox2[1] - bbox2[1]

x1 = (base_size - w1) // 2
y1 = 65

x2 = (base_size - w2) // 2
y2 = 265

# Text 1: "Hi!" in bright amber / cyan
draw.text((x1 + 3, y1 + 3), text1, font=font_hi, fill=(10, 20, 40, 180)) # subtle shadow
draw.text((x1, y1), text1, font=font_hi, fill=(255, 180, 40, 255)) # amber/gold

# Text 2: "PAD" in clean crisp white
draw.text((x2 + 3, y2 + 3), text2, font=font_pad, fill=(10, 20, 40, 180))
draw.text((x2, y2), text2, font=font_pad, fill=(255, 255, 255, 255))

for out_path, size in sizes.items():
    resized = img.resize((size, size), Image.Resampling.LANCZOS)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    resized.save(out_path, "PNG")
    print(f"Generated {size}x{size} icon: {out_path}")

# Also save 512x512 preview
img.save(r"d:\project\D2PDF\app_icon_preview.png", "PNG")
print("Saved 512x512 icon preview: app_icon_preview.png")
