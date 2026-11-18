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
    """Клетка поля 16x16: лунка со скругленными углами. Светлый край сверху, тень снизу,
    между клетками видна деревянная подложка поля."""
    import random
    rnd = random.Random(seed)
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    edge = tuple(max(0, c - 34) for c in dark[:3]) + (255,)
    d.rounded_rectangle((0, 0, 15, 15), radius=3, fill=edge)
    d.rounded_rectangle((1, 1, 14, 14), radius=2, fill=base)
    px = im.load()
    for x in range(3, 13):
        px[x, 1] = light
    for y in range(3, 12):
        px[1, y] = light
    for x in range(2, 14):
        px[x, 13] = dark
        px[x, 14] = dark
    for _ in range(4):
        x, y = rnd.randrange(4, 12), rnd.randrange(4, 11)
        px[x, y] = light if rnd.random() < 0.5 else dark
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
    """Кнопка закрытия: деревянный кружок с симметричным крестиком."""
    im = canvas()
    d = ImageDraw.Draw(im)
    d.ellipse((1, 1, 14, 14), fill=WOOD_L)
    d.ellipse((2, 2, 13, 13), fill=WOOD_M)
    # две диагонали по 2 пикселя, зеркальные: крестик ровный при любом масштабе
    cross = {(i, i) for i in range(5, 11)} | {(i + 1, i) for i in range(5, 10)}
    cross |= {(15 - x, y) for x, y in cross}
    for p in cross:
        d.point(p, fill=CREAM)
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


# --- иконки вместо эмодзи (16x16, форма в пределах 2..13, контур добавляет outlined)

def _px(d, pts, color):
    for p in pts:
        d.point(p, fill=color)


def crown():
    im = canvas(); d = ImageDraw.Draw(im)
    gold, light, dark = (250, 200, 50, 255), (255, 236, 140, 255), (200, 140, 30, 255)
    d.polygon([(3, 5), (5, 8), (7.5, 4), (10, 8), (12, 5), (12, 11), (3, 11)], fill=gold)
    d.rectangle((3, 10, 12, 11), fill=dark)
    _px(d, [(3, 4), (7, 3), (8, 3), (12, 4)], light)
    _px(d, [(5, 9), (10, 9)], (232, 72, 96, 255))
    _px(d, [(7, 9), (8, 9)], (60, 190, 240, 255))
    return outlined(im)


def house():
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(2, 7), (7.5, 2), (13, 7)], fill=(200, 80, 60, 255))
    d.line((3, 7, 12, 7), fill=(150, 50, 40, 255))
    d.rectangle((3, 8, 12, 13), fill=(236, 210, 160, 255))
    d.rectangle((6, 10, 8, 13), fill=(140, 90, 50, 255))
    d.rectangle((10, 9, 11, 10), fill=(120, 200, 240, 255))
    return outlined(im)


def ribbon():
    im = canvas(); d = ImageDraw.Draw(im)
    pink, dark, light = (236, 110, 150, 255), (190, 60, 100, 255), (255, 186, 206, 255)
    # петли бантика с пустой серединкой
    d.polygon([(7, 6), (2, 3), (2, 9)], fill=pink)
    d.polygon([(8, 6), (13, 3), (13, 9)], fill=pink)
    _px(d, [(3, 5), (3, 6), (4, 6), (12, 5), (12, 6), (11, 6)], dark)
    _px(d, [(3, 4), (12, 4)], light)
    # хвостики
    d.line((6, 8, 4, 13), fill=dark, width=2)
    d.line((9, 8, 11, 13), fill=dark, width=2)
    d.rectangle((6, 5, 9, 8), fill=light)
    d.rectangle((7, 6, 8, 7), fill=pink)
    return outlined(im)


def ticket():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rectangle((2, 4, 13, 11), fill=(160, 120, 220, 255))
    d.rectangle((3, 5, 12, 10), fill=(200, 170, 240, 255))
    d.line((9, 5, 9, 10), fill=(140, 100, 200, 255))
    _px(d, [(2, 7), (2, 8), (13, 7), (13, 8)], CLEAR)
    d.rectangle((4, 7, 7, 8), fill=(255, 240, 255, 255))
    return outlined(im)


def frame_pic():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rectangle((2, 3, 13, 12), fill=WOOD_L)
    d.rectangle((4, 5, 11, 10), fill=(140, 210, 250, 255))
    d.rectangle((4, 9, 11, 10), fill=(110, 180, 80, 255))
    d.polygon([(4, 9), (7, 6), (10, 9)], fill=(90, 160, 70, 255))
    d.point((10, 6), fill=(255, 230, 120, 255))
    return outlined(im)


def basket():
    im = canvas(); d = ImageDraw.Draw(im)
    d.arc((4, 2, 11, 10), 180, 360, fill=WOOD_M, width=1)
    d.polygon([(2, 7), (13, 7), (12, 13), (3, 13)], fill=WOOD_L)
    for x in (4, 7, 10):
        d.line((x, 8, x, 12), fill=WOOD_M)
    d.line((2, 7, 13, 7), fill=WOOD_H)
    return outlined(im)


def gift():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rectangle((2, 6, 13, 13), fill=(232, 80, 96, 255))
    d.rectangle((2, 6, 13, 7), fill=(250, 120, 130, 255))
    d.rectangle((7, 6, 8, 13), fill=(250, 210, 80, 255))
    d.polygon([(7, 6), (4, 3), (3, 5)], fill=(250, 210, 80, 255))
    d.polygon([(8, 6), (11, 3), (12, 5)], fill=(250, 210, 80, 255))
    return outlined(im)


def jar():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rectangle((5, 2, 10, 3), fill=WOOD_M)
    d.rounded_rectangle((3, 4, 12, 13), radius=3, fill=(190, 230, 240, 255))
    d.rounded_rectangle((4, 7, 11, 12), radius=2, fill=(250, 220, 90, 255))
    _px(d, [(6, 9), (9, 8), (7, 11)], (255, 255, 210, 255))
    d.line((4, 5, 4, 8), fill=(255, 255, 255, 255))
    return outlined(im)


def rosette():
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(5, 9), (3, 14), (6, 12), (7, 14)], fill=(60, 120, 220, 255))
    d.polygon([(10, 9), (12, 14), (9, 12), (8, 14)], fill=(60, 120, 220, 255))
    d.ellipse((2, 1, 13, 11), fill=(250, 190, 60, 255))
    d.ellipse((4, 3, 11, 9), fill=(255, 226, 120, 255))
    d.point((6, 4), fill=(255, 250, 220, 255))
    return outlined(im)


def question():
    im = canvas(); d = ImageDraw.Draw(im)
    c = (255, 246, 220, 255)
    d.ellipse((2, 2, 13, 13), fill=(160, 120, 220, 255))
    for p in [(6, 4), (7, 4), (8, 4), (9, 4), (5, 5), (10, 5), (10, 6), (9, 7), (8, 7), (7, 8), (7, 9), (7, 11)]:
        d.point(p, fill=c)
    _px(d, [(8, 8), (8, 9), (8, 11), (6, 4)], c)
    return outlined(im)


def lock():
    im = canvas(); d = ImageDraw.Draw(im)
    d.arc((4, 2, 11, 10), 180, 360, fill=(150, 150, 160, 255), width=2)
    d.rectangle((4, 6, 5, 7), fill=(150, 150, 160, 255))
    d.rectangle((10, 6, 11, 7), fill=(150, 150, 160, 255))
    d.rectangle((3, 7, 12, 13), fill=(240, 190, 60, 255))
    d.line((3, 7, 12, 7), fill=(255, 226, 120, 255))
    d.rectangle((7, 9, 8, 11), fill=(140, 90, 30, 255))
    return outlined(im)


def undo():
    im = canvas(); d = ImageDraw.Draw(im)
    c = (255, 246, 220, 255)
    d.arc((4, 4, 13, 13), 270, 90, fill=c, width=2)
    d.line((8, 4, 9, 4), fill=c, width=2)
    d.line((8, 12, 4, 12), fill=c, width=2)
    d.polygon([(2, 4), (6, 1), (6, 7)], fill=c)
    return im


def pouch():
    im = canvas(); d = ImageDraw.Draw(im)
    d.ellipse((3, 5, 12, 13), fill=(150, 100, 200, 255))
    d.polygon([(5, 6), (10, 6), (11, 3), (4, 3)], fill=(170, 120, 220, 255))
    d.line((5, 6, 10, 6), fill=(250, 210, 80, 255))
    d.point((7, 9), fill=(140, 232, 255, 255)); d.point((8, 9), fill=(60, 190, 240, 255))
    return outlined(im)


def chest():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rectangle((2, 7, 13, 13), fill=WOOD_L)
    d.rounded_rectangle((2, 3, 13, 7), radius=2, fill=WOOD_M)
    d.line((2, 7, 13, 7), fill=(250, 200, 60, 255))
    d.rectangle((2, 3, 3, 13), fill=(250, 200, 60, 255))
    d.rectangle((12, 3, 13, 13), fill=(250, 200, 60, 255))
    d.rectangle((7, 6, 8, 9), fill=(250, 230, 120, 255))
    return outlined(im)


def bag():
    im = canvas(); d = ImageDraw.Draw(im)
    d.ellipse((2, 5, 13, 14), fill=(220, 180, 100, 255))
    d.polygon([(5, 6), (10, 6), (12, 2), (3, 2)], fill=(200, 160, 84, 255))
    d.line((5, 6, 10, 6), fill=(140, 90, 40, 255))
    d.polygon([(6, 8), (9, 8), (10, 10), (7.5, 12), (5, 10)], fill=(60, 190, 240, 255))
    return outlined(im)


def vault():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rectangle((2, 5, 13, 13), fill=(170, 170, 180, 255))
    for x in (2, 6, 10):
        d.rectangle((x, 2, x + 2, 5), fill=(170, 170, 180, 255))
    d.rectangle((6, 9, 9, 13), fill=(110, 70, 40, 255))
    d.line((2, 5, 13, 5), fill=(210, 210, 220, 255))
    d.point((7, 7), fill=(60, 190, 240, 255)); d.point((8, 7), fill=(60, 190, 240, 255))
    return outlined(im)


def hammer():
    im = canvas(); d = ImageDraw.Draw(im)
    d.line((4, 13, 10, 7), fill=WOOD_L, width=2)
    d.polygon([(7, 3), (11, 2), (14, 5), (12, 7), (9, 6)], fill=(170, 170, 180, 255))
    d.line((8, 3, 11, 2), fill=(220, 220, 230, 255))
    return outlined(im)


def piggy():
    im = canvas(); d = ImageDraw.Draw(im)
    pink, dark = (250, 160, 180, 255), (220, 110, 140, 255)
    d.ellipse((2, 4, 13, 12), fill=pink)
    d.rectangle((4, 11, 5, 13), fill=dark); d.rectangle((10, 11, 11, 13), fill=dark)
    d.polygon([(4, 5), (5, 2), (7, 4)], fill=dark)
    d.rectangle((12, 7, 13, 9), fill=dark)
    d.point((10, 6), fill=INK)
    d.line((6, 4, 9, 4), fill=(140, 90, 30, 255))
    return outlined(im)


def check():
    im = canvas(); d = ImageDraw.Draw(im)
    g = (96, 170, 72, 255)
    d.line((3, 8, 6, 11), fill=g, width=2)
    d.line((6, 11, 12, 4), fill=g, width=2)
    return outlined(im)


def party():
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(2, 13), (6, 4), (11, 9)], fill=(250, 200, 60, 255))
    d.line((4, 9, 8, 11), fill=(232, 80, 96, 255))
    d.line((5, 6, 9, 8), fill=(60, 160, 230, 255))
    _px(d, [(10, 2), (13, 4), (12, 7), (9, 4)], (232, 80, 96, 255))
    _px(d, [(11, 3), (13, 9), (8, 2)], (110, 200, 90, 255))
    return outlined(im)


def confetti():
    im = canvas(); d = ImageDraw.Draw(im)
    cols = [(232, 80, 96, 255), (250, 200, 60, 255), (60, 160, 230, 255), (110, 200, 90, 255), (190, 120, 230, 255)]
    pts = [(3, 3), (7, 2), (11, 4), (4, 7), (9, 7), (13, 8), (2, 11), (6, 11), (11, 12), (8, 13)]
    for i, (x, y) in enumerate(pts):
        d.rectangle((x, y, x + 1, y), fill=cols[i % len(cols)])
    return outlined(im)


def season(kind):
    im = canvas(); d = ImageDraw.Draw(im)
    if kind == "spring":
        for (x, y) in ((7, 3), (3, 7), (11, 7), (5, 11), (10, 11)):
            d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=(250, 170, 200, 255))
        d.ellipse((6, 6, 9, 9), fill=(250, 210, 80, 255))
    elif kind == "summer":
        d.ellipse((4, 4, 11, 11), fill=(250, 200, 50, 255))
        for a, b in (((7, 1), (8, 2)), ((7, 13), (8, 14)), ((1, 7), (2, 8)), ((13, 7), (14, 8)),
                     ((3, 3), (3, 3)), ((12, 3), (12, 3)), ((3, 12), (3, 12)), ((12, 12), (12, 12))):
            d.rectangle((*a, *b), fill=(250, 200, 50, 255))
        d.point((6, 6), fill=(255, 240, 170, 255))
    elif kind == "autumn":
        d.polygon([(7.5, 1), (10, 5), (13, 5), (11, 9), (12, 12), (7.5, 10), (3, 12), (4, 9), (2, 5), (5, 5)], fill=(230, 120, 40, 255))
        d.line((7, 6, 7, 14), fill=(150, 70, 30, 255))
    else:
        c = (150, 210, 250, 255)
        d.line((7, 1, 7, 14), fill=c); d.line((8, 1, 8, 14), fill=c)
        d.line((1, 7, 14, 7), fill=c); d.line((1, 8, 14, 8), fill=c)
        d.line((3, 3, 12, 12), fill=c); d.line((12, 3, 3, 12), fill=c)
    return outlined(im)


def book():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rectangle((3, 2, 12, 13), fill=(70, 130, 200, 255))
    d.rectangle((3, 2, 4, 13), fill=(40, 90, 160, 255))
    d.rectangle((11, 3, 12, 12), fill=PAPER)
    d.rectangle((6, 5, 10, 8), fill=(250, 200, 60, 255))
    d.point((8, 6), fill=(255, 240, 170, 255))
    d.line((6, 10, 10, 10), fill=(150, 190, 240, 255))
    return outlined(im)


def plant():
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(4, 9), (11, 9), (10, 13), (5, 13)], fill=(200, 110, 70, 255))
    d.line((4, 9, 11, 9), fill=(230, 150, 100, 255))
    d.ellipse((3, 3, 8, 8), fill=(100, 180, 80, 255))
    d.ellipse((7, 2, 12, 7), fill=(120, 200, 90, 255))
    d.line((7, 6, 7, 9), fill=(70, 130, 60, 255))
    return outlined(im)


def trophy():
    im = canvas(); d = ImageDraw.Draw(im)
    gold, light, dark = (250, 196, 60, 255), (255, 232, 140, 255), (200, 130, 30, 255)
    # ручки
    d.rectangle((2, 3, 3, 6), fill=gold); d.point((3, 7), fill=gold)
    d.rectangle((12, 3, 13, 6), fill=gold); d.point((12, 7), fill=gold)
    # чаша
    d.rectangle((4, 2, 11, 6), fill=gold)
    d.rectangle((5, 7, 10, 8), fill=gold)
    d.line((4, 2, 11, 2), fill=light)
    d.line((6, 3, 6, 6), fill=(255, 250, 220, 255))
    d.line((10, 3, 10, 7), fill=dark)
    # ножка и подставка
    d.rectangle((7, 9, 8, 10), fill=dark)
    d.rectangle((5, 11, 10, 13), fill=WOOD_M)
    d.line((5, 11, 10, 11), fill=WOOD_L)
    return outlined(im)


def wagon():
    im = canvas(); d = ImageDraw.Draw(im)
    d.pieslice((2, 1, 13, 12), 180, 360, fill=(246, 236, 210, 255))
    d.line((5, 2, 5, 6), fill=(232, 110, 120, 255))
    d.line((10, 2, 10, 6), fill=(232, 110, 120, 255))
    d.rectangle((1, 6, 14, 10), fill=WOOD_M)
    d.line((1, 6, 14, 6), fill=WOOD_L)
    d.ellipse((2, 9, 6, 13), fill=(90, 60, 40, 255)); d.point((4, 11), fill=(250, 210, 80, 255))
    d.ellipse((9, 9, 13, 13), fill=(90, 60, 40, 255)); d.point((11, 11), fill=(250, 210, 80, 255))
    return outlined(im)


def pickaxe():
    im = canvas(); d = ImageDraw.Draw(im)
    d.line((4, 13, 10, 5), fill=WOOD_L, width=2)
    d.line((5, 13, 11, 5), fill=WOOD_D)
    d.arc((2, 1, 15, 12), 200, 340, fill=(170, 170, 184, 255), width=2)
    d.point((4, 4), fill=(225, 225, 235, 255)); d.point((13, 4), fill=(225, 225, 235, 255))
    return outlined(im)


def lantern():
    im = canvas(); d = ImageDraw.Draw(im)
    d.arc((5, 1, 10, 5), 180, 360, fill=(90, 80, 80, 255))
    d.rectangle((4, 4, 11, 5), fill=(90, 80, 80, 255))
    d.rectangle((5, 6, 10, 12), fill=(255, 214, 96, 255))
    d.rectangle((7, 8, 8, 10), fill=(255, 250, 210, 255))
    d.line((5, 6, 5, 12), fill=(90, 80, 80, 255)); d.line((10, 6, 10, 12), fill=(90, 80, 80, 255))
    d.rectangle((4, 13, 11, 13), fill=(90, 80, 80, 255))
    return outlined(im)


def minecart():
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(1, 5), (14, 5), (12, 11), (3, 11)], fill=(150, 150, 164, 255))
    d.line((1, 5, 14, 5), fill=(205, 205, 215, 255))
    d.line((3, 8, 12, 8), fill=(120, 120, 134, 255))
    for x, c in ((4, (250, 200, 70, 255)), (7, (230, 120, 200, 255)), (10, (250, 200, 70, 255))):
        d.ellipse((x - 1, 2, x + 2, 5), fill=c)
    d.ellipse((3, 10, 6, 13), fill=(70, 60, 60, 255)); d.ellipse((9, 10, 12, 13), fill=(70, 60, 60, 255))
    return outlined(im)


def mine_tile(base, light, dark, seed, specks):
    """Клетка шахты 16x16: порода с крапинками и объемом, чем тверже, тем темнее и пестрее."""
    import random
    rnd = random.Random(seed)
    im = Image.new("RGBA", (16, 16), base)
    px = im.load()
    for _ in range(specks):
        x, y = rnd.randrange(2, 14), rnd.randrange(2, 14)
        px[x, y] = light if rnd.random() < 0.4 else dark
        if rnd.random() < 0.5 and x < 13:
            px[x + 1, y] = dark
    for i in range(16):
        px[i, 0] = light; px[0, i] = light
        px[i, 15] = dark; px[15, i] = dark
    return im


def mine_open():
    import random
    rnd = random.Random(5)
    im = Image.new("RGBA", (16, 16), (74, 52, 44, 255))
    px = im.load()
    for _ in range(6):
        px[rnd.randrange(16), rnd.randrange(16)] = (64, 44, 38, 255)
    for i in range(16):
        px[i, 0] = (52, 36, 30, 255)
    return im


def shell():
    im = canvas(); d = ImageDraw.Draw(im)
    d.pieslice((2, 3, 13, 14), 180, 360, fill=(250, 196, 180, 255))
    d.rectangle((2, 8, 13, 10), fill=(250, 196, 180, 255))
    d.polygon([(6, 10), (9, 10), (10, 13), (5, 13)], fill=(236, 160, 150, 255))
    for x in (4, 6, 8, 10):
        d.line((7.5, 10, x, 4), fill=(222, 140, 130, 255))
    d.point((5, 5), fill=(255, 236, 226, 255))
    return outlined(im)


def wave():
    import math
    im = canvas(); px = im.load()
    for row, color in ((4, (150, 210, 245, 255)), (8, (80, 160, 230, 255)), (12, (50, 120, 200, 255))):
        for x in range(2, 14):
            y = row + round(math.sin(x / 1.6) * 1.2)
            px[x, y] = color
            px[x, y + 1] = color
    return outlined(im)


def fog_tile():
    import random
    rnd = random.Random(9)
    im = Image.new("RGBA", (16, 16), (214, 222, 230, 255))
    px = im.load()
    for _ in range(14):
        x, y = rnd.randrange(16), rnd.randrange(16)
        px[x, y] = (236, 240, 246, 255) if rnd.random() < 0.6 else (196, 204, 216, 255)
    for i in range(16):
        px[i, 15] = (190, 198, 212, 255)
    return im


def water_tile():
    im = Image.new("RGBA", (16, 16), (92, 168, 214, 255))
    px = im.load()
    for x in range(2, 7):
        px[x, 4] = (150, 206, 236, 255)
    for x in range(9, 14):
        px[x, 11] = (150, 206, 236, 255)
    return im


def seeds():
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(3, 5), (12, 5), (13, 14), (2, 14)], fill=(214, 170, 110, 255))
    d.rectangle((4, 2, 11, 5), fill=(196, 150, 92, 255))
    d.line((4, 5, 11, 5), fill=(150, 104, 60, 255))
    d.ellipse((5, 8, 10, 12), fill=(110, 180, 80, 255))
    d.point((7, 7), fill=(110, 180, 80, 255)); d.point((8, 6), fill=(110, 180, 80, 255))
    return outlined(im)


def can():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rectangle((3, 6, 10, 13), fill=(110, 170, 220, 255))
    d.line((3, 6, 10, 6), fill=(170, 210, 240, 255))
    d.arc((4, 2, 10, 9), 180, 360, fill=(80, 130, 180, 255))
    d.line((10, 9, 14, 5), fill=(110, 170, 220, 255), width=2)
    d.point((14, 4), fill=(170, 210, 240, 255))
    return outlined(im)


def glass():
    """Стекло для витража: три цветных осколка в свинцовой рамке."""
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(2, 3), (8, 2), (7, 8), (2, 9)], fill=(224, 72, 96, 255))
    d.polygon([(8, 2), (13, 3), (13, 9), (7, 8)], fill=(80, 140, 232, 255))
    d.polygon([(2, 9), (7, 8), (13, 9), (12, 14), (3, 14)], fill=(250, 186, 64, 255))
    lead = (60, 54, 70, 255)
    d.line((8, 2, 7, 8), fill=lead); d.line((2, 9, 7, 8), fill=lead); d.line((7, 8, 13, 9), fill=lead)
    d.point((4, 4), fill=(255, 200, 210, 255)); d.point((10, 4), fill=(200, 226, 255, 255))
    d.point((5, 11), fill=(255, 236, 170, 255)); d.point((6, 10), fill=(255, 236, 170, 255))
    return outlined(im)


def trade():
    """Обмен: две встречные стрелки, зеленая вправо и оранжевая влево."""
    im = canvas(); d = ImageDraw.Draw(im)
    g, gl = (96, 176, 72, 255), (168, 222, 120, 255)
    o, ol = (240, 150, 50, 255), (252, 206, 120, 255)
    d.rectangle((2, 4, 10, 6), fill=g); d.line((2, 4, 10, 4), fill=gl)
    d.polygon([(10, 1), (14, 5), (10, 9)], fill=g); d.point((11, 3), fill=gl)
    d.rectangle((5, 10, 13, 12), fill=o); d.line((5, 10, 13, 10), fill=ol)
    d.polygon([(5, 7), (1, 11), (5, 15)], fill=o); d.point((4, 9), fill=ol)
    return outlined(im)


def soil_tile():
    import random
    rnd = random.Random(4)
    im = Image.new("RGBA", (16, 16), (126, 86, 58, 255))
    px = im.load()
    for y in (4, 9, 14):
        for x in range(16):
            px[x, y] = (104, 70, 46, 255)
    for _ in range(10):
        px[rnd.randrange(16), rnd.randrange(16)] = (146, 104, 72, 255)
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
        "ui_crown": crown(), "ui_house": house(), "ui_ribbon": ribbon(), "ui_ticket": ticket(),
        "ui_frame": frame_pic(), "ui_basket": basket(), "ui_gift": gift(), "ui_jar": jar(),
        "ui_rosette": rosette(), "ui_question": question(), "ui_lock": lock(), "ui_undo": undo(),
        "ui_pouch": pouch(), "ui_chest": chest(), "ui_bag": bag(), "ui_vault": vault(),
        "ui_hammer": hammer(), "ui_piggy": piggy(), "ui_check": check(), "ui_party": party(),
        "ui_confetti": confetti(), "ui_plant": plant(), "ui_book": book(),
        "ui_trophy": trophy(), "ui_wagon": wagon(),
        "ui_pickaxe": pickaxe(), "ui_lantern": lantern(), "ui_minecart": minecart(),
        "ui_mine_1": mine_tile((176, 124, 82, 255), (202, 152, 106, 255), (140, 96, 62, 255), 1, 8),
        "ui_mine_2": mine_tile((150, 146, 140, 255), (186, 182, 176, 255), (112, 108, 104, 255), 2, 12),
        "ui_mine_3": mine_tile((104, 96, 112, 255), (150, 140, 160, 255), (70, 64, 80, 255), 3, 16),
        "ui_mine_open": mine_open(),
        "ui_seeds": seeds(), "ui_can": can(), "ui_soil": soil_tile(), "ui_glass": glass(), "ui_trade": trade(),
        "ui_shell": shell(), "ui_wave": wave(), "ui_fog": fog_tile(), "ui_water": water_tile(),
        "ui_spring": season("spring"), "ui_summer": season("summer"),
        "ui_autumn": season("autumn"), "ui_winter": season("winter"),
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
