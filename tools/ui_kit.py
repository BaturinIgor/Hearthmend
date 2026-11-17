#!/usr/bin/env python3
"""Пиксельный набор интерфейса Hearthmend: иконки валют, деревянные рамки, кнопки.

Рисуется с нуля (свой стиль, не из пака), но в манере пака Cute Fantasy: черный контур
и светлая кремовая обводка снаружи. Картинки маленькие (16 px), в игре увеличиваются
без сглаживания. Запуск: python3 tools/ui_kit.py Hearthmend/Resources/UI
"""
import os
import sys

from PIL import Image, ImageDraw

INK = (34, 22, 18, 255)
CREAM = (249, 230, 207, 255)
CLEAR = (0, 0, 0, 0)


def outlined(shape):
    """Добавляет черный контур и кремовую обводку вокруг непрозрачной формы."""
    w, h = shape.size
    out = Image.new("RGBA", (w, h), CLEAR)
    src = shape.load()
    px = out.load()

    def ring(mask, color):
        res = set()
        for y in range(h):
            for x in range(w):
                if (x, y) in mask:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if (x + dx, y + dy) in mask:
                        res.add((x, y))
                        break
        for p in res:
            px[p] = color
        return res

    body = {(x, y) for y in range(h) for x in range(w) if src[x, y][3] > 0}
    for (x, y) in body:
        px[x, y] = src[x, y]
    ink = ring(body, INK)
    ring(body | ink, CREAM)
    return out


def canvas(n=16):
    return Image.new("RGBA", (n, n), CLEAR)


def coin():
    im = canvas()
    d = ImageDraw.Draw(im)
    d.ellipse((3, 3, 12, 12), fill=(232, 168, 40, 255))
    d.ellipse((4, 4, 11, 11), fill=(250, 204, 72, 255))
    d.ellipse((5, 5, 10, 10), fill=(236, 176, 48, 255))
    d.line((7, 6, 7, 9), fill=(250, 214, 96, 255))
    d.line((8, 6, 8, 9), fill=(255, 236, 150, 255))
    d.point((5, 5), fill=(255, 246, 200, 255))
    d.point((4, 6), fill=(255, 246, 200, 255))
    return outlined(im)


def star():
    im = canvas()
    d = ImageDraw.Draw(im)
    pts = [(7.5, 2), (9.3, 6), (13.5, 6.3), (10.3, 9), (11.4, 13.3), (7.5, 11), (3.6, 13.3), (4.7, 9), (1.5, 6.3), (5.7, 6)]
    d.polygon(pts, fill=(250, 200, 50, 255))
    d.polygon([(7.5, 4), (8.6, 7), (11, 7.2), (9.2, 8.7), (9.8, 11.2), (7.5, 9.8)], fill=(255, 228, 120, 255))
    d.point((7, 4), fill=(255, 250, 220, 255))
    return outlined(im)


def bolt():
    im = canvas()
    d = ImageDraw.Draw(im)
    d.polygon([(9, 1), (3, 8), (7, 8), (5, 14), (12, 6), (8, 6), (10, 1)], fill=(120, 214, 255, 255))
    d.line((8, 2, 5, 7), fill=(220, 248, 255, 255))
    d.line((8, 8, 7, 11), fill=(70, 160, 230, 255))
    return outlined(im)


def gem():
    im = canvas()
    d = ImageDraw.Draw(im)
    d.polygon([(4, 4), (11, 4), (13, 7), (7.5, 13), (2, 7)], fill=(60, 190, 240, 255))
    d.polygon([(4, 4), (11, 4), (13, 7), (2, 7)], fill=(140, 232, 255, 255))
    d.polygon([(6, 4), (9, 4), (10, 7), (5, 7)], fill=(210, 250, 255, 255))
    d.polygon([(5, 7), (10, 7), (7.5, 13)], fill=(30, 150, 215, 255))
    d.point((5, 5), fill=(255, 255, 255, 255))
    return outlined(im)


def heart():
    im = canvas()
    d = ImageDraw.Draw(im)
    d.ellipse((2, 3, 8, 9), fill=(232, 72, 96, 255))
    d.ellipse((7, 3, 13, 9), fill=(232, 72, 96, 255))
    d.polygon([(2, 7), (13, 7), (7.5, 13)], fill=(232, 72, 96, 255))
    d.point((4, 5), fill=(255, 190, 200, 255))
    d.point((5, 4), fill=(255, 190, 200, 255))
    return outlined(im)


# --- рамки (9-slice): углы 6 px, середина тянется плиткой

WOOD_D = (92, 52, 28, 255)
WOOD_M = (146, 92, 50, 255)
WOOD_L = (188, 128, 72, 255)
WOOD_H = (220, 168, 104, 255)
PAPER = (250, 236, 204, 255)
PAPER_S = (234, 212, 168, 255)


def wood_panel():
    """Деревянная рамка с пергаментом внутри, 18x18, края 6 px."""
    n = 18
    im = Image.new("RGBA", (n, n), CLEAR)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, n - 1, n - 1), radius=3, fill=INK)
    d.rounded_rectangle((1, 1, n - 2, n - 2), radius=2, fill=WOOD_M)
    d.line((2, 1, n - 3, 1), fill=WOOD_H)
    d.line((1, 2, 1, n - 3), fill=WOOD_L)
    d.line((2, n - 2, n - 3, n - 2), fill=WOOD_D)
    d.line((n - 2, 2, n - 2, n - 3), fill=WOOD_D)
    # волокна дерева на рамке
    for x in (4, 9, 13):
        d.point((x, 2), fill=WOOD_L)
        d.point((x + 1, n - 3), fill=WOOD_D)
    d.rectangle((4, 4, n - 5, n - 5), fill=INK)
    d.rectangle((5, 5, n - 6, n - 6), fill=PAPER)
    d.line((5, 5, n - 6, 5), fill=PAPER_S)
    return im


def paper_panel():
    """Пергамент с тонкой коричневой рамкой, 12x12, края 4 px."""
    n = 12
    im = Image.new("RGBA", (n, n), CLEAR)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, n - 1, n - 1), radius=2, fill=WOOD_D)
    d.rounded_rectangle((1, 1, n - 2, n - 2), radius=1, fill=PAPER)
    d.line((2, n - 2, n - 3, n - 2), fill=PAPER_S)
    d.line((n - 2, 2, n - 2, n - 3), fill=PAPER_S)
    return im


def tinted_paper(edge, light, fill):
    """Пергамент с цветной двойной рамкой 12x12, края 4 px: выделенные карточки
    (готовый заказ, праздник, VIP)."""
    n = 12
    im = Image.new("RGBA", (n, n), CLEAR)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, n - 1, n - 1), radius=2, fill=WOOD_D)
    d.rounded_rectangle((1, 1, n - 2, n - 2), radius=1, fill=edge)
    d.line((2, 1, n - 3, 1), fill=light)
    d.rectangle((3, 3, n - 4, n - 4), fill=fill)
    d.line((3, n - 4, n - 4, n - 4), fill=PAPER_S)
    return im


def button(base, light, dark):
    """Кнопка 16x14: светлый верх, темный низ-тень, края 5 px."""
    w, h = 16, 14
    im = Image.new("RGBA", (w, h), CLEAR)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=3, fill=INK)
    d.rounded_rectangle((1, 1, w - 2, h - 2), radius=2, fill=dark)
    d.rounded_rectangle((1, 1, w - 2, h - 4), radius=2, fill=base)
    d.line((3, 2, w - 4, 2), fill=light)
    d.point((2, 3), fill=light)
    return im


def cell(base, light, dark, seed):
    """Клетка поля 16x16: трава с крапинками, светлый верх-лево и темный низ-право (объем)."""
    import random
    rnd = random.Random(seed)
    im = Image.new("RGBA", (16, 16), base)
    px = im.load()
    for _ in range(9):
        x, y = rnd.randrange(2, 14), rnd.randrange(2, 14)
        px[x, y] = light if rnd.random() < 0.5 else dark
        if rnd.random() < 0.5 and y > 2:
            px[x, y - 1] = light
    for i in range(16):
        px[i, 0] = light
        px[0, i] = light
        px[i, 15] = dark
        px[15, i] = dark
    return im


def crate():
    """Подставка генератора: деревянный ящик 16x16."""
    im = Image.new("RGBA", (16, 16), CLEAR)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 15, 15), fill=INK)
    d.rectangle((1, 1, 14, 14), fill=WOOD_L)
    for y in (4, 8, 12):
        d.line((1, y, 14, y), fill=WOOD_M)
    d.line((1, 1, 14, 1), fill=WOOD_H)
    d.rectangle((1, 1, 2, 14), fill=WOOD_M)
    d.rectangle((13, 1, 14, 14), fill=WOOD_D)
    d.line((1, 14, 14, 14), fill=WOOD_D)
    for p in ((2, 2), (13, 2), (2, 13), (13, 13)):
        d.point(p, fill=(230, 210, 170, 255))
    return im


def bar_track():
    """Желоб полоски прогресса 12x8, края 3 px."""
    w, h = 12, 8
    im = Image.new("RGBA", (w, h), CLEAR)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=2, fill=INK)
    d.rectangle((1, 1, w - 2, h - 2), fill=(120, 80, 48, 255))
    d.line((1, 1, w - 2, 1), fill=(84, 52, 30, 255))
    return im


def bar_fill(base, light, dark):
    """Заливка полоски 8x6, края 2 px: светлый блик сверху, тень снизу."""
    w, h = 8, 6
    im = Image.new("RGBA", (w, h), base)
    d = ImageDraw.Draw(im)
    d.line((0, 0, w - 1, 0), fill=light)
    d.line((0, h - 1, w - 1, h - 1), fill=dark)
    return im


def close_icon():
    """Кнопка закрытия: деревянный кружок с крестиком."""
    im = canvas()
    d = ImageDraw.Draw(im)
    d.ellipse((1, 1, 14, 14), fill=WOOD_L)
    d.ellipse((2, 2, 13, 13), fill=WOOD_M)
    d.arc((2, 2, 13, 13), 200, 340, fill=WOOD_H)
    for a, b in (((5, 5), (10, 10)), ((10, 5), (5, 10))):
        d.line((*a, *b), fill=CREAM, width=2)
    return outlined(im)


def paper_tile():
    """Фон окон: пергамент 16x16 с редкими волокнами, кладется плиткой."""
    import random
    rnd = random.Random(7)
    im = Image.new("RGBA", (16, 16), (245, 232, 204, 255))
    px = im.load()
    for _ in range(14):
        x, y = rnd.randrange(16), rnd.randrange(16)
        px[x, y] = (236, 220, 186, 255) if rnd.random() < 0.7 else (250, 242, 222, 255)
    return im


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "Hearthmend/Resources/UI"
    os.makedirs(out, exist_ok=True)
    items = {
        "ui_coin": coin(), "ui_star": star(), "ui_energy": bolt(), "ui_gem": gem(), "ui_heart": heart(),
        "ui_panel": wood_panel(), "ui_paper": paper_panel(),
        "ui_btn_green": button((104, 178, 76, 255), (168, 222, 120, 255), (52, 112, 52, 255)),
        "ui_btn_wood": button(WOOD_L, WOOD_H, WOOD_D),
        "ui_btn_pink": button((232, 110, 140, 255), (255, 180, 196, 255), (160, 60, 92, 255)),
        "ui_cell_a": cell((150, 196, 104, 255), (178, 216, 124, 255), (122, 168, 86, 255), 1),
        "ui_cell_b": cell((138, 184, 96, 255), (164, 204, 114, 255), (112, 156, 78, 255), 2),
        "ui_crate": crate(),
        "ui_paper_green": tinted_paper((96, 170, 72, 255), (160, 216, 116, 255), (240, 246, 214, 255)),
        "ui_paper_pink": tinted_paper((226, 112, 146, 255), (255, 182, 200, 255), (253, 234, 232, 255)),
        "ui_paper_gold": tinted_paper((222, 160, 40, 255), (252, 214, 110, 255), (254, 240, 200, 255)),
        "ui_paper_lilac": tinted_paper((150, 110, 200, 255), (200, 170, 236, 255), (242, 234, 248, 255)),
        "ui_bar_track": bar_track(),
        "ui_bar_fill": bar_fill((112, 190, 80, 255), (172, 228, 124, 255), (64, 130, 56, 255)),
        "ui_bar_pink": bar_fill((236, 120, 150, 255), (255, 186, 204, 255), (176, 70, 104, 255)),
        "ui_close": close_icon(),
        "ui_bg": paper_tile(),
    }
    for key, im in items.items():
        im.save(os.path.join(out, key + ".png"))
    if "--preview" in sys.argv:
        prev = Image.new("RGBA", (len(items) * 20 * 8, 20 * 8), (60, 110, 60, 255))
        for i, im in enumerate(items.values()):
            prev.alpha_composite(im.resize((im.width * 8, im.height * 8), Image.NEAREST), (i * 160 + 8, 8))
        prev.save(sys.argv[sys.argv.index("--preview") + 1])
    print(f"{len(items)} картинок в {out}")


if __name__ == "__main__":
    main()
