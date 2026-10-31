"""Draws the temporary pixel-art placeholders used until the CC0 pack sprites are imported.

    python tools/art/make_placeholders.py

Writes:
  assets/placeholder/tiles.png        16x16 tiles in one row: grass, path, water, stone wall
  assets/placeholder/player_walk.png  64x64 character sheet: columns = down, up, left, right;
                                      rows = 4 walk frames (same layout the CharacterSprite loader expects)
"""
import random
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "placeholder"
OUT.mkdir(parents=True, exist_ok=True)
rng = random.Random(7)


def hexc(h, a=255):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def tiles():
    img = Image.new("RGBA", (64, 16))
    grass, grass_d, grass_l = hexc("6aa84f"), hexc("4f8a3a"), hexc("8cc66a")
    path, path_d, path_l = hexc("c9a46c"), hexc("a8834f"), hexc("dcbd8a")
    water, water_d, water_l = hexc("3f8fc4"), hexc("2f6f9c"), hexc("8fd0ea")
    wall, wall_d, wall_l = hexc("8d8a80"), hexc("5c5f6b"), hexc("b4b0a4")
    for x in range(16):
        for y in range(16):
            img.putpixel((x, y), grass)
            img.putpixel((16 + x, y), path)
            img.putpixel((32 + x, y), water)
            img.putpixel((48 + x, y), wall)
    for _ in range(14):  # grass tufts
        x, y = rng.randrange(16), rng.randrange(15)
        img.putpixel((x, y), grass_d)
        img.putpixel((x, y + 1), grass_d if rng.random() < 0.5 else grass_l)
    for _ in range(10):  # pebbles
        x, y = rng.randrange(16), rng.randrange(16)
        img.putpixel((16 + x, y), path_d if rng.random() < 0.6 else path_l)
    for y in (4, 11):  # ripples
        for x in range(2, 14):
            if (x + y) % 5 < 3:
                img.putpixel((32 + x, y), water_l if x % 7 else water_d)
    for y in range(16):  # bricks
        for x in range(16):
            if y % 5 == 4 or (x + (4 if (y // 5) % 2 else 0)) % 8 == 0:
                img.putpixel((48 + x, y), wall_d)
            elif y % 5 == 0:
                img.putpixel((48 + x, y), wall_l)
    img.save(OUT / "tiles.png")


def character():
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    skin, hair, shirt, shirt_d = hexc("f2c9a0"), hexc("6b3e26"), hexc("4a86b8"), hexc("2f5d86")
    pants, boot, eye, outline = hexc("4e3424"), hexc("2b1d14"), hexc("1d1d24"), hexc("1d1d24")
    for col, facing in enumerate(("down", "up", "left", "right")):
        for row in range(4):
            ox, oy = col * 16, row * 16
            step = (0, 1, 0, -1)[row]
            def px(x, y, c):
                if 0 <= x < 16 and 0 <= y < 16:
                    img.putpixel((ox + x, oy + y), c)
            bob = 1 if row in (1, 3) else 0
            # legs
            for i, lx in enumerate((6, 9)):
                off = step if i == 0 else -step
                for y in range(12, 15):
                    px(lx, y + (off if y == 14 else 0) - 0, pants)
                    px(lx + 1 if facing in ("down", "up") else lx, y, pants)
                px(lx, 15 + min(0, off), boot)
                px(lx + 1, 15 + min(0, off), boot)
            # body
            for y in range(8 - bob, 12):
                for x in range(5, 11):
                    px(x, y, shirt if x not in (5, 10) else shirt_d)
            # arms swing
            for i, ax in enumerate((4, 11)):
                if facing in ("left", "right") and ((ax == 4) != (facing == "left")):
                    continue
                arm = step if i == 0 else -step
                for y in range(8 - bob, 11):
                    px(ax, y + arm, shirt_d)
                px(ax, 11 + arm - bob, skin)
            # head
            for y in range(2 - bob, 8 - bob):
                for x in range(4, 12):
                    px(x, y, skin)
            for x in range(4, 12):  # hair top
                px(x, 1 - bob, hair)
                px(x, 2 - bob, hair)
            if facing == "up":
                for y in range(2 - bob, 7 - bob):
                    for x in range(4, 12):
                        px(x, y, hair)
            else:
                if facing == "down":
                    px(6, 5 - bob, eye)
                    px(9, 5 - bob, eye)
                    px(4, 3 - bob, hair)
                    px(11, 3 - bob, hair)
                elif facing == "left":
                    px(5, 5 - bob, eye)
                    for y in range(2 - bob, 6 - bob):
                        px(11, y, hair)
                        px(10, y, hair)
                else:
                    px(10, 5 - bob, eye)
                    for y in range(2 - bob, 6 - bob):
                        px(4, y, hair)
                        px(5, y, hair)
    img.save(OUT / "player_walk.png")


tiles()
character()
print("placeholders written to", OUT)
