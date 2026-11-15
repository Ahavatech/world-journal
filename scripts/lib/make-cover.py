#!/usr/bin/env python3
"""Compose an issue cover: an AI-generated abstract background + the journal logo + the issue label, as a 1200x1600 JPEG for OJS (Issues > edit > Cover image).
   python3 -I scripts/lib/make-cover.py BACKGROUND.png OUT.jpg [--volume 1] [--issue 1]
The background carries no lettering (AI image tools garble it); every word on the cover is set here. No year is printed: the client has not given one."""
import argparse
from PIL import Image, ImageDraw, ImageFont
ap = argparse.ArgumentParser()
ap.add_argument("background"); ap.add_argument("out")
ap.add_argument("--volume", default="1"); ap.add_argument("--issue", default="1")
a = ap.parse_args()
W, H = 1200, 1600
bg = Image.open(a.background).convert("RGB")
# cover-crop to 3:4 then scale
r = W / H
w, h = bg.size
if w / h > r:
    nw = int(h * r); bg = bg.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
else:
    nh = int(w / r); bg = bg.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
bg = bg.resize((W, H), Image.LANCZOS)
d = ImageDraw.Draw(bg, "RGBA")
F = "/usr/share/fonts/truetype/liberation/"
font = lambda n, s: ImageFont.truetype(F + n, s)
# logo on a white rounded panel (the logo is made for a light background)
logo = Image.open("ojs/plugins/themes/worj/assets/img/logo-lockup.jpg").convert("RGB")
lw = 640; logo = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
px, py, pad = (W - lw) // 2, 110, 36
d.rounded_rectangle((px - pad, py - pad, px + lw + pad, py + logo.height + pad), radius=28, fill=(255, 255, 255, 245))
bg.paste(logo, (px, py))
def centered(text, y, f, fill, spacing=0):
    tw = sum(d.textlength(c, font=f) + spacing for c in text) - spacing
    x = (W - tw) / 2
    for c in text:
        d.text((x, y), c, font=f, fill=fill)
        x += d.textlength(c, font=f) + spacing
# label and name at the bottom
d.rectangle((0, 1190, W, H), fill=(6, 24, 46, 150))
centered(f"VOLUME {a.volume}  |  ISSUE {a.issue}", 1235, font("LiberationSans-Bold.ttf", 46), (245, 200, 100, 255), 6)
centered("World Open Research Journal", 1330, font("LiberationSerif-Bold.ttf", 76), (255, 255, 255, 255))
centered("Recognizing Excellence. Advancing Knowledge. Inspiring Innovation.", 1450, font("LiberationSerif-Italic.ttf", 36), (225, 235, 245, 255))
bg.save(a.out, "JPEG", quality=88, optimize=True)
print("wrote", a.out, bg.size)
