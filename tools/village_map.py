#!/usr/bin/env python3
"""Карта деревни из тайлов пака и спрайты построек.

    python3 tools/village_map.py <папка Cute_Fantasy> <куда положить png> [--preview out.png]

Фон карты собирается из травы, дорожек и реки (автотайлы пака) в map_bg.png.
Каждая постройка вырезается в bld_<имя>.png. Координаты построек в village.json: x, y - середина
нижнего края постройки в клетках по 16 пикселей. --preview рисует карту со всеми постройками.
"""
import json, os, random, sys
from PIL import Image

CELL = 16
MAP_W, MAP_H = 32, 94
# северный берег (сад и холм) над рекой; старые районы ниже на NORTH клеток
NORTH = 44

B = "Buildings/Buildings/"
U = B + "Unique_Buildings/"
OD = "Outdoor decoration/"

# ключ -> (файл, x, y, ширина, высота) в пикселях; None - весь файл
BUILDINGS = {
    "bld_square": (OD + "Fountain.png", 0, 40, 32, 40),
    "bld_well": (OD + "Well.png", None),
    "bld_lamps": (OD + "Lanter_Posts.png", 0, 0, 32, 48),
    "bld_home": (B + "Houses/Wood/House_1_Wood_Base_Blue.png", None),
    "bld_benches": (OD + "Benches.png", 32, 0, 32, 32),
    "bld_flowers": (OD + "Flowers.png", 0, 0, 48, 16),
    "bld_beekeeper": (U + "Shed/Shed_Base_Red.png", None),
    "bld_stalls": (U + "Stalls/Market_Stalls.png", 0, 0, 96, 48),
    "bld_inn": (U + "Inn/Inn_Red.png", None),
    "bld_fence": (OD + "Fences.png", 16, 0, 48, 16),
    "bld_coop": (U + "Coop/Coop_Base_Red.png", 0, 0, 80, 128),
    "bld_hay": (OD + "Hay_Bales.png", None),
    "bld_silo": (U + "Silo/Silo.png", None),
    "bld_barn": (U + "Barn/Barn_Base_Red.png", None),
    "bld_windmill": (U + "Windmill/Windmill.png", 0, 0, 64, 112),
    # крылья мельницы крутятся отдельно, в игре их центр ставится на WINDMILL_HUB
    "bld_windmill_blades": (U + "Windmill/Windmill.png", 64, 8, 64, 64),
    "bld_bridge": ("Tiles/Bridge/Bridge_Stone_Vertical.png", None),
    "bld_fisher": (U + "Fisherman_House/Fisherman_House_Base_Blue.png", None),
    "bld_boat": (OD + "Boat.png", None),
    "bld_smithy": (U + "Blacksmith_House/Blacksmith_House_Red.png", None),
    "bld_greenhouse": (U + "Greenhouse/GreenHouse_Wood.png", 0, 0, 96, 128),
    "bld_festival": (U + "Church/Church_Red.png", 336, 0, 112, 144),
    # сад
    "bld_signpost": (OD + "Signs.png", 0, 16, 16, 32),
    # роща из трех деревьев собирается в grove()
    "bld_grove": ("Crops/Apple_Tree.png", None),
    "bld_bower": ("Crops/Grapes_Bower.png", 96, 80, 96, 80),
    "bld_orchard_house": (B + "Houses/Stone/House_2_Stone_Green_Red.png", None),
    "bld_press": (U + "Shed/Shed_Green_Blue.png", None),
    "bld_market2": (U + "Stalls/Market_Stalls.png", 96, 0, 96, 48),
    # холм
    "bld_hill_cottage": (B + "Houses/Limestone/House_1_Limestone_Base_Red.png", None),
    "bld_bakery": (B + "Houses/Limestone/House_4_Limestone_Base_Red.png", None),
    "bld_glasshouse": (U + "Greenhouse/GreenHouse_Green.png", 0, 0, 96, 128),
    "bld_library": (B + "Houses/Limestone/House_3_Limestone_Base_Blue.png", None),
    "bld_manor": (B + "Houses/Stone/House_5_Stone_Red_Blue.png", None),
    "bld_bell": (U + "Church/Church_Blue.png", 336, 0, 112, 144),
}

# украшения из событий: ставятся на карту куда угодно
DECOR = {
    "decor_scarecrow": (OD + "Scarecrows.png", 0, 0, 32, 32),
    "decor_trough": (OD + "Water_Troughs.png", 16, 0, 32, 16),
    "decor_torch": (OD + "Big_Torch_Anim.png", 0, 0, 16, 48),
    "decor_garland": (OD + "Outdoor_Decor.png", 64, 240, 32, 32),
    "decor_bush": (OD + "Outdoor_Decor.png", 48, 144, 16, 16),
    "decor_flowers_purple": (OD + "Outdoor_Decor.png", 80, 336, 32, 32),
    "decor_flowers_red": (OD + "Outdoor_Decor.png", 80, 368, 32, 32),
    "decor_logs": (OD + "Outdoor_Decor.png", 0, 256, 32, 48),
    "decor_mushroom": (OD + "Outdoor_Decor.png", 112, 32, 16, 16),
    "decor_nest": ("Outdoor decoration/Nests.png", 32, 0, 16, 16),
    "decor_bench": (OD + "Benches.png", 0, 0, 32, 32),
    # из покупок: пропуск события, набор выходных, набор строителя
    "decor_lamp_hanging": (OD + "Lanter_Posts.png", 0, 288, 32, 48),
    "decor_pond": (OD + "Fountain.png", 0, 0, 32, 40),
    "decor_lamp_double": (OD + "Lanter_Posts.png", 0, 96, 16, 48),
}
BUILDINGS.update(DECOR)


# центр крыльев относительно левого верхнего угла башни, в пикселях
WINDMILL_HUB = (22, 40)


def crop_opaque(im):
    box = im.getbbox()
    return im.crop(box) if box else im


def load(pack, path):
    return Image.open(os.path.join(pack, path)).convert("RGBA")


def grove(pack):
    trees = [crop_opaque(load(pack, f"Crops/{n}_Tree.png")) for n in ("Pear", "Apple", "Peach")]
    w = trees[0].width + trees[1].width + trees[2].width - 8
    h = max(t.height for t in trees) + 6
    im = Image.new("RGBA", (w, h))
    # средняя чуть ниже, чтобы роща не выглядела строем
    im.alpha_composite(trees[0], (0, h - 6 - trees[0].height))
    im.alpha_composite(trees[2], (w - trees[2].width, h - 6 - trees[2].height))
    im.alpha_composite(trees[1], (trees[0].width - 4, h - trees[1].height))
    return im


def building(pack, key):
    if key == "bld_grove":
        return grove(pack)
    spec = BUILDINGS[key]
    im = load(pack, spec[0])
    if spec[1] is not None:
        _, x, y, w, h = spec
        im = im.crop((x, y, x + w, y + h))
    # у крыльев ось ровно в центре картинки, поэтому их не обрезаем
    return im if key == "bld_windmill_blades" else crop_opaque(im)


def tile(sheet, c, r):
    return sheet.crop((c * CELL, r * CELL, (c + 1) * CELL, (r + 1) * CELL))


def autotile(base, mask, sheet, col0, row0, fill):
    """Рисует область mask (множество клеток) по автотайлу 3x3 с внутренними углами ниже.
    fill - тайл середины области."""
    def inside(x, y):
        if x < 0 or x >= MAP_W:
            return (min(max(x, 0), MAP_W - 1), y) in mask
        if y < 0 or y >= MAP_H:
            return (x, min(max(y, 0), MAP_H - 1)) in mask
        return (x, y) in mask

    for (x, y) in mask:
        up, down, left, right = inside(x, y - 1), inside(x, y + 1), inside(x - 1, y), inside(x + 1, y)
        c = 0 if not left else (2 if not right else 1)
        r = 0 if not up else (2 if not down else 1)
        base.alpha_composite(fill, (x * CELL, y * CELL))
        base.alpha_composite(tile(sheet, col0 + c, row0 + r), (x * CELL, y * CELL))
        if c == 1 and r == 1:
            # внутренние углы: трава по диагонали
            for dx, dy, ic, ir in ((-1, -1, 1, 1), (1, -1, 0, 1), (-1, 1, 1, 0), (1, 1, 0, 0)):
                if not inside(x + dx, y + dy):
                    base.alpha_composite(tile(sheet, col0 + ic, row0 + 3 + ir), (x * CELL, y * CELL))


def compose_background(pack):
    rnd = random.Random(7)
    grass = load(pack, "Tiles/Grass/Grass_1_Middle.png")
    tufts = [tile(load(pack, "Tiles/Grass/Grass_Tiles_1.png"), c, 9) for c in (5, 6, 7)]
    bg = Image.new("RGBA", (MAP_W * CELL, MAP_H * CELL))
    for y in range(MAP_H):
        for x in range(MAP_W):
            bg.alpha_composite(grass, (x * CELL, y * CELL))
            if rnd.random() < 0.08:
                bg.alpha_composite(rnd.choice(tufts), (x * CELL, y * CELL))

    # река поперек карты, сад и холм на северном берегу
    water_sheet = load(pack, "Tiles/Water/Water_Tile_1.png")
    water_fill = load(pack, "Tiles/Water/Water_Middle.png")
    water = {(x, y) for x in range(MAP_W) for y in range(NORTH, NORTH + 5)}
    autotile(bg, water, water_sheet, 0, 0, water_fill)

    # дорожки: главная сверху вниз через мост и поперечные в каждом районе
    grass_sheet = load(pack, "Tiles/Grass/Grass_Tiles_1.png")
    dirt_fill = tile(grass_sheet, 1, 6)
    path = set()
    for y in list(range(10, NORTH)) + list(range(NORTH + 6, NORTH + 41)):
        path |= {(15, y), (16, y)}
    for y0 in (13, 28, NORTH + 20, NORTH + 39):
        path |= {(x, y) for x in range(2, 30) for y in (y0, y0 + 1)}
    # площадь вокруг фонтана
    path |= {(x, y) for x in range(8, 15) for y in range(NORTH + 22, NORTH + 28)}
    autotile(bg, path, grass_sheet, 0, 5, dirt_fill)
    return bg


def place(canvas, im, x, y):
    canvas.alpha_composite(im, (int(x * CELL - im.width / 2), int(y * CELL - im.height)))


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    pack, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))
    village = json.load(open(os.path.join(here, "..", "Sources", "HearthCore", "Resources", "village.json")))
    tasks = [t for d in village["districts"] for t in d["tasks"]]
    missing = [t["building"] for t in tasks if t["building"] not in BUILDINGS]
    if missing:
        sys.exit("нет спрайтов для: " + ", ".join(missing))
    images = {k: building(pack, k) for k in BUILDINGS}
    for k, im in images.items():
        im.save(os.path.join(out, k + ".png"))
    bg = compose_background(pack)
    bg.save(os.path.join(out, "map_bg.png"))
    print(f"{len(images)} построек и фон {bg.width}x{bg.height} в {out}")

    if "--preview" in sys.argv:
        dest = sys.argv[sys.argv.index("--preview") + 1]
        canvas = bg.copy()
        for t in sorted(tasks, key=lambda t: t["y"]):
            im = images[t["building"]]
            place(canvas, im, t["x"], t["y"])
            if t["building"] == "bld_windmill":
                blades = images["bld_windmill_blades"]
                left, top = int(t["x"] * CELL - im.width / 2), int(t["y"] * CELL - im.height)
                canvas.alpha_composite(blades, (left + WINDMILL_HUB[0] - blades.width // 2,
                                                top + WINDMILL_HUB[1] - blades.height // 2))
        canvas.resize((canvas.width * 2, canvas.height * 2), Image.NEAREST).convert("RGB").save(dest)


if __name__ == "__main__":
    main()
