"""Synthetic, non-personal media for real editor screenshots (requires Pillow)."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/Cloakmark-Duo-Fixture.png")
version = sys.argv[2] if len(sys.argv) > 2 else "adaptive"
image = Image.new("RGB", (1200, 800), "#eff3f7")
draw = ImageDraw.Draw(image)
font_path = "/System/Library/Fonts/Supplemental/Arial.ttf"
def font(size):
    return ImageFont.truetype(font_path, size)
draw.rounded_rectangle((65, 50, 1135, 750), radius=28, fill="white", outline="#d5dce5", width=3)
draw.rounded_rectangle((95, 85, 1105, 195), radius=18, fill="#173550")
draw.text((125, 108), "RESERVATION  /  SAMPLE", fill="white", font=font(48))
draw.text((125, 235), "Local redaction review", fill="#173550", font=font(42))
draw.text((125, 310), "Name: Alex Sample", fill="#17212b", font=font(50))
draw.text((125, 408), "Reference: CM-2048-TEST", fill="#17212b", font=font(38))
draw.line((125, 485, 1075, 485), fill="#d5dce5", width=3)
draw.text((125, 525), "Route: North Shore  >  City Center", fill="#38536b", font=font(32))
draw.text((125, 590), "All processing stays on this device.", fill="#38536b", font=font(30))
draw.text((125, 675), "SYNTHETIC TEST DOCUMENT  |  " + version, fill="#668097", font=font(23))
image.save(out)
print(out)
