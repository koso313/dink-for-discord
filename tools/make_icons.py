"""Draws the Dink For Discord icon (a bell with 'ding' lines) at every size we need.

Outputs:
  DinkForDiscord/Media/Icon.tga   64x64, for the addon (TOC icon, window portrait, minimap)
  Helper/DinkHelper/icon.ico      multi-size, for the helper app and its tray icon
  curseforge/logo.png             400x400, for the CurseForge project page
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLURPLE = (88, 101, 242, 255)
DARK = (60, 69, 180, 255)
WHITE = (255, 255, 255, 255)
GOLD = (255, 209, 0, 255)


def draw(size, rounded=True):
    s = 8  # supersample
    W = size * s
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle([0, 0, W - 1, W - 1], radius=W * 0.22, fill=BLURPLE)
    else:
        d.rectangle([0, 0, W - 1, W - 1], fill=BLURPLE)
    if rounded:  # clip shading back to the rounded square
        mask = Image.new("L", (W, W), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, W - 1], radius=W * 0.22, fill=255)
        img.putalpha(mask)
        d = ImageDraw.Draw(img)

    cx = W * 0.5
    # Bell body.
    d.pieslice([cx - W * 0.22, W * 0.20, cx + W * 0.22, W * 0.62], 180, 360, fill=WHITE)
    d.polygon([(cx - W * 0.22, W * 0.41), (cx + W * 0.22, W * 0.41),
               (cx + W * 0.29, W * 0.66), (cx - W * 0.29, W * 0.66)], fill=WHITE)
    d.rounded_rectangle([cx - W * 0.33, W * 0.63, cx + W * 0.33, W * 0.71], radius=W * 0.04, fill=WHITE)
    # Top knob and clapper.
    d.ellipse([cx - W * 0.05, W * 0.13, cx + W * 0.05, W * 0.23], fill=WHITE)
    d.ellipse([cx - W * 0.075, W * 0.70, cx + W * 0.075, W * 0.85], fill=WHITE)
    # Ding lines.
    lw = max(int(W * 0.045), 1)
    for side in (-1, 1):
        x0 = cx + side * W * 0.34
        d.line([(x0, W * 0.30), (x0 + side * W * 0.09, W * 0.22)], fill=GOLD, width=lw)
        d.line([(x0 + side * W * 0.02, W * 0.42), (x0 + side * W * 0.13, W * 0.40)], fill=GOLD, width=lw)
    return img.resize((size, size), Image.LANCZOS)


def main():
    media = os.path.join(ROOT, "DinkForDiscord", "Media")
    os.makedirs(media, exist_ok=True)
    # WoW wants square power-of-two textures; square corners look best inside the round portrait.
    draw(64, rounded=False).save(os.path.join(media, "Icon.tga"))

    helper = os.path.join(ROOT, "Helper", "DinkHelper")
    os.makedirs(helper, exist_ok=True)
    big = draw(256)
    big.save(os.path.join(helper, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    cf = os.path.join(ROOT, "curseforge")
    os.makedirs(cf, exist_ok=True)
    draw(400).save(os.path.join(cf, "logo.png"))
    print("icons written")


if __name__ == "__main__":
    main()
