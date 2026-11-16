#!/usr/bin/env python3
"""Иконка приложения 1024x1024.

    python3 tools/make_icon.py <out.png> [папка Cute_Fantasy]

С паком: домик из пака на лугу под вечерним небом со светлячками (кладется в зашифрованный архив,
CI подставляет ее в AppIcon). Без пака: своя простая пиксельная иконка, она лежит в репозитории.
"""
import os, random, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024


def background():
    im = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(im)
    top, mid = (255, 196, 140), (255, 232, 190)
    for y in range(S):
        t = y / S
        c = tuple(int(top[i] + (mid[i] - top[i]) * min(1, t * 1.4)) for i in range(3))
        d.line([(0, y), (S, y)], fill=c)
    # луг
    d.ellipse([-300, 690, S + 300, 1500], fill=(120, 182, 86))
    d.ellipse([-200, 760, S + 200, 1600], fill=(98, 160, 70))
    return im.convert("RGBA")


def fireflies(im, n=14, seed=5):
    rnd = random.Random(seed)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    for _ in range(n):
        x, y = rnd.randint(80, S - 80), rnd.randint(80, 640)
        r = rnd.randint(10, 18)
        d.ellipse([x - r * 2, y - r * 2, x + r * 2, y + r * 2], fill=(255, 230, 120, 70))
        d.ellipse([x - r // 2, y - r // 2, x + r // 2, y + r // 2], fill=(255, 250, 200, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(3))
    im.alpha_composite(glow)


def own_house(im):
    """Простой пиксельный домик без пака (16x16, масштаб x40)."""
    px = [
        "......RR........",
        ".....RRRR.......",
        "....RRRRRR..CC..",
        "...RRRRRRRR.CC..",
        "..RRRRRRRRRRCC..",
        ".RRRRRRRRRRRRR..",
        "RRRRRRRRRRRRRRR.",
        ".WWWWWWWWWWWWW..",
        ".WWWBBWWWWBBWW..",
        ".WWWBBWWWWBBWW..",
        ".WWWWWWDDWWWWW..",
        ".WWWWWWDDWWWWW..",
        ".WWWWWWDDWWWWW..",
        "GGGGGGGGGGGGGGGG",
    ]
    colors = {"R": (196, 72, 60), "C": (120, 90, 70), "W": (186, 134, 86), "B": (110, 190, 230),
              "D": (110, 70, 40), "G": (90, 150, 64)}
    k = 40
    ox, oy = (S - 16 * k) // 2 + 20, 300
    d = ImageDraw.Draw(im)
    for y, row in enumerate(px):
        for x, ch in enumerate(row):
            if ch in colors:
                d.rectangle([ox + x * k, oy + y * k, ox + (x + 1) * k - 1, oy + (y + 1) * k - 1], fill=colors[ch])


def pack_house(im, pack):
    house = Image.open(os.path.join(pack, "Buildings/Buildings/Houses/Wood/House_1_Wood_Base_Blue.png")).convert("RGBA")
    house = house.crop(house.getbbox())
    k = min(640 // house.width, 640 // house.height)
    big = house.resize((house.width * k, house.height * k), Image.NEAREST)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([S // 2 - big.width // 2, 820, S // 2 + big.width // 2, 900], fill=(40, 80, 30, 110))
    im.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(12)))
    im.alpha_composite(big, ((S - big.width) // 2, 860 - big.height))
    flowers = Image.open(os.path.join(pack, "Outdoor decoration/Outdoor_Decor.png")).convert("RGBA").crop((80, 336, 112, 368))
    fl = flowers.resize((flowers.width * 6, flowers.height * 6), Image.NEAREST)
    im.alpha_composite(fl, (90, 800))
    im.alpha_composite(fl.transpose(Image.FLIP_LEFT_RIGHT), (S - 90 - fl.width, 810))


def main():
    out = sys.argv[1]
    im = background()
    if len(sys.argv) > 2:
        pack_house(im, sys.argv[2])
    else:
        own_house(im)
    fireflies(im)
    im.convert("RGB").save(out)


if __name__ == "__main__":
    main()
