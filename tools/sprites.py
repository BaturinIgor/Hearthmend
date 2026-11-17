#!/usr/bin/env python3
"""Вырезает спрайты предметов, генераторов и завала из пака Cute Fantasy RPG.

    python3 tools/sprites.py <папка Cute_Fantasy> <куда положить png> [--sheet out.png]

Каждый спрайт обрезается по непрозрачным пикселям и сохраняется как <ключ>.png (ключи из chains.json).
--sheet дополнительно рисует лист для проверки глазами. Пак нельзя выкладывать, поэтому результат
шифруется tools/pack_sprites.sh в Art/sprites.enc.
"""
import json, os, sys
from PIL import Image, ImageDraw

FOOD = "Icons/Outline/Food_Icons_Outline.png"
RES = "Icons/Outline/Resources_Icons_Outline.png"
OTHER = "Icons/Outline/Other_Icons_Outline.png"
TOOLS = "Icons/Outline/Tool_Icons_Outline.png"
DECOR = "Outdoor decoration/Outdoor_Decor.png"
ORES = "Outdoor decoration/Ores.png"
CROPS = "Crops/Crops.png"
BARRELS = "Outdoor decoration/barrels.png"

# ключ -> (файл, колонка, ряд, ширина в клетках, высота в клетках); клетка 16x16
SPRITES = {
    # огород
    "garden_seed": (CROPS, 1, 5, 1, 1),
    "garden_sprout": (CROPS, 4, 5, 1, 1),
    "garden_carrot": (FOOD, 2, 4, 1, 1),
    "garden_cabbage": (FOOD, 2, 5, 1, 1),
    "garden_pumpkin": (FOOD, 0, 6, 1, 1),
    "garden_barrel": (BARRELS, 0, 2, 1, 2),
    "garden_hay": ("Outdoor decoration/Hay_Bales.png", 1, 0, 2, 1),
    "gen_garden": (CROPS, 0, 1, 1, 1),
    # лес
    "forest_twig": (RES, 2, 4, 1, 1),
    "forest_log": (RES, 0, 4, 1, 1),
    "forest_bark": (RES, 4, 4, 1, 1),
    "forest_stool": ("Outdoor decoration/Camp_Decor.png", 0, 0, 1, 1),
    "forest_mossy": (DECOR, 0, 11, 2, 1),
    "forest_bench": ("Outdoor decoration/Benches.png", 2, 0, 2, 2),
    "forest_barrel": (BARRELS, 3, 0, 1, 2),
    "gen_forest": (DECOR, 0, 9, 1, 1),
    # каменоломня
    "quarry_pebble": (RES, 0, 0, 1, 1),
    "quarry_stone": (ORES, 3, 0, 1, 1),
    "quarry_ore": (ORES, 1, 1, 1, 1),
    "quarry_copper": (RES, 2, 1, 1, 1),
    "quarry_gold": (RES, 2, 2, 1, 1),
    "quarry_pickaxe": (TOOLS, 2, 0, 1, 1),
    "quarry_lantern": ("Outdoor decoration/Lantern.png", 0, 0, 1, 1),
    "gen_quarry": (ORES, 0, 0, 1, 1),
    # пасека
    "apiary_flower": (OTHER, 0, 0, 1, 1),
    "apiary_lily": (OTHER, 2, 0, 1, 1),
    "apiary_violet": (OTHER, 3, 0, 1, 1),
    "apiary_pot": (BARRELS, 3, 2, 1, 2),
    "apiary_honey": (FOOD, 7, 8, 1, 1),
    "apiary_mead": (FOOD, 7, 7, 1, 1),
    "gen_apiary": ("Animals/Bee/Bee_Hive.png", 0, 0, 1, 1),
    # ферма
    "farm_egg": (FOOD, 6, 1, 1, 1),
    "farm_fried": (FOOD, 7, 1, 1, 1),
    "farm_milk": (FOOD, 7, 0, 1, 1),
    "farm_cheese": (FOOD, 6, 0, 1, 1),
    "farm_bread": ("Outdoor decoration/Picnic_Basket.png", 1, 0, 1, 1),
    "farm_picnic": ("Outdoor decoration/Picnic_Basket.png", 0, 0, 1, 1),
    "gen_farm": ("Animals/Chicken/Chicken_01.png", 0, 0, 2, 2),
    # сад
    "orchard_cherry": (FOOD, 6, 6, 1, 1),
    "orchard_pear": (FOOD, 6, 5, 1, 1),
    "orchard_apple": (FOOD, 6, 3, 1, 1),
    "orchard_peach": (FOOD, 6, 4, 1, 1),
    "orchard_grapes": (FOOD, 0, 5, 1, 1),
    "orchard_melon": (FOOD, 6, 7, 1, 1),
    "gen_orchard": ("Crops/Apple_Tree.png", 0, 0, 2, 4),
    # рыбалка
    "fishing_minnow": (FOOD, 1, 2, 1, 1),
    "fishing_perch": (FOOD, 0, 2, 1, 1),
    "fishing_bream": (FOOD, 2, 2, 1, 1),
    "fishing_pike": (FOOD, 3, 2, 1, 1),
    "fishing_carp": (FOOD, 4, 2, 1, 1),
    "fishing_salmon": (FOOD, 5, 2, 1, 1),
    "fishing_catfish": (FOOD, 7, 2, 1, 1),
    "fishing_goldfish": (FOOD, 6, 2, 1, 1),
    "gen_fishing": (TOOLS, 7, 0, 1, 1),
    # кристаллы
    "crystal_dust": (ORES, 5, 4, 1, 1),
    "crystal_shard": (ORES, 6, 4, 1, 1),
    "crystal_cluster": (ORES, 3, 4, 1, 1),
    "crystal_geode": (ORES, 2, 4, 1, 1),
    "crystal_druse": (ORES, 1, 4, 1, 1),
    "crystal_spire": (ORES, 4, 4, 1, 1),
    "crystal_ingot": (ORES, 7, 4, 1, 1),
    "crystal_orb": (RES, 5, 4, 1, 1),
    "gen_crystal": (ORES, 0, 4, 1, 1),
    # завал
    "debris": (DECOR, 3, 6, 1, 1),
}

# верхние ступени цепочек (1.1): большие предметы из декора. ("px", файл, x0, y0, x1, y1) - рамка в пикселях
TREES = "Trees/"
SPRITES.update({
    "garden_planter": ("px", "Buildings/House_Decor/Planters.png", 88, 12, 121, 31),
    "garden_scarecrow": ("px", "Outdoor decoration/Scarecrows.png", 2, 0, 30, 31),
    "garden_well": ("px", "Outdoor decoration/Well.png", 2, 8, 29, 47),
    "forest_sapling": ("px", TREES + "Small_Oak_Tree.png", 42, 32, 54, 52),
    "forest_spruce": ("px", TREES + "Medium_Spruce_Tree.png", 40, 0, 57, 37),
    "forest_bigoak": ("px", TREES + "Big_Oak_Tree.png", 75, 9, 116, 72),
    "quarry_anvil": ("Buildings/House_Decor/Anvil_Anim.png", 0, 0, 1, 1),
    "quarry_cart": ("px", "Outdoor decoration/Minecrats.png", 16, 45, 32, 61),
    "quarry_cart_copper": ("px", "Outdoor decoration/Minecrats.png", 16, 77, 32, 93),
    "quarry_cart_gold": ("px", "Outdoor decoration/Minecrats.png", 16, 109, 32, 125),
    "apiary_potted": ("Outdoor decoration/Flowers.png", 5, 0, 1, 1),
    "apiary_comb": ("Outdoor decoration/Nests.png", 2, 0, 1, 1),
    "apiary_lupin": ("px", DECOR, 86, 345, 106, 367),
    "apiary_fountain": ("px", "Outdoor decoration/Fountain.png", 0, 42, 32, 78),
    "farm_nest": ("Outdoor decoration/Nests.png", 0, 3, 1, 1),
    "farm_trough": ("px", "Outdoor decoration/Water_Troughs.png", 17, 1, 47, 15),
    "farm_cellar": ("px", BARRELS, 16, 34, 64, 64),
    "orchard_berries": ("Crops/Berries.png", 0, 0, 1, 1),
    "orchard_sapling": ("px", TREES + "Small_Fruit_Tree.png", 41, 30, 54, 52),
    "orchard_tree": ("px", TREES + "Big_Fruit_Tree.png", 34, 7, 61, 53),
    "orchard_arbor": ("px", "Crops/Grapes_Bower.png", 108, 93, 180, 149),
    "fishing_pond": ("px", "Outdoor decoration/Fountain.png", 0, 2, 32, 30),
    "fishing_boat": ("px", "Outdoor decoration/Boat.png", 2, 14, 42, 45),
    "crystal_cart_blue": ("px", "Outdoor decoration/Minecrats.png", 16, 173, 32, 189),
    "crystal_cart_pink": ("px", "Outdoor decoration/Minecrats.png", 16, 269, 32, 285),
})
# у иконок пака светлая обводка, у декора нет: добавляем, чтобы верхние ступени смотрелись так же
OUTLINED = {k for k, v in SPRITES.items() if v[0] == "px" or k in ("quarry_anvil", "apiary_comb", "farm_nest", "apiary_potted", "orchard_berries")}
CREAM = (249, 230, 207, 255)


def outline(im):
    out = Image.new("RGBA", (im.width + 2, im.height + 2), (0, 0, 0, 0))
    out.paste(im, (1, 1))
    src = out.copy().load()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            if src[x, y][3] > 0:
                continue
            if any(0 <= x + dx < out.width and 0 <= y + dy < out.height and src[x + dx, y + dy][3] > 100
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = CREAM
    return out


# заросли и ящики на поле: не из каталога, вырезаются всегда
CHEST = "Buildings/House_Decor/Chest_Anim.png"
METAL = "Buildings/House_Decor/Metal_Chest_Anim.png"
GOLD = "Buildings/House_Decor/Golden_Chest_Anim.png"
JEWEL = "Buildings/House_Decor/Golden_Jeweled_Chest_Anim.png"
EXTRA = {
    "thicket_0": (DECOR, 5, 9, 1, 1), "thicket_1": (DECOR, 6, 9, 1, 1), "thicket_2": (DECOR, 7, 9, 1, 1),
}
for lvl, sheet in enumerate([CHEST, METAL, GOLD]):
    EXTRA[f"chest_{lvl}"] = (sheet, 0, 0, 1, 1)
    EXTRA[f"chest_{lvl}_open"] = (sheet, 4, 0, 1, 1)
# находки события «Глубины»: руда, самоцветы, окаменелости по 5 уровней
for i, spec in enumerate([(RES, 0, 1, 1, 1), (RES, 1, 1, 1, 1), (RES, 2, 1, 1, 1), (RES, 2, 2, 1, 1),
                          ("px", "Outdoor decoration/Minecrats.png", 16, 109, 32, 125)]):
    EXTRA[f"depth_ore_{i}"] = spec
for i, spec in enumerate([(RES, 3, 3, 1, 1), (RES, 4, 3, 1, 1), (RES, 5, 3, 1, 1), (RES, 5, 4, 1, 1),
                          ("px", "Outdoor decoration/Minecrats.png", 16, 269, 32, 285)]):
    EXTRA[f"depth_gem_{i}"] = spec
for i, spec in enumerate([(RES, 1, 4, 1, 1), (RES, 3, 4, 1, 1), (RES, 3, 5, 1, 1), (RES, 2, 5, 1, 1), (RES, 4, 1, 1, 1)]):
    EXTRA[f"depth_fossil_{i}"] = spec
EXTRA["depth_rock"] = (RES, 0, 5, 1, 1)
# предметы события «Остров»: цветы, голубые и янтарные кристаллы по 6 ступеней
FLOWERS = "Outdoor decoration/Flowers.png"
ISLAND = {
    "island_flower": [(FLOWERS, 2, 0, 1, 1), (FLOWERS, 2, 8, 1, 1), (FLOWERS, 2, 2, 1, 1),
                      (FLOWERS, 2, 4, 1, 1), (FLOWERS, 2, 6, 1, 1), (FLOWERS, 7, 6, 1, 1)],
    "island_gem": [(ORES, 5, 4, 1, 1), (ORES, 6, 4, 1, 1), (ORES, 3, 4, 1, 1),
                   (ORES, 2, 4, 1, 1), (ORES, 1, 4, 1, 1), (ORES, 4, 4, 1, 1)],
    "island_amber": [(ORES, 5, 2, 1, 1), (ORES, 6, 2, 1, 1), (ORES, 3, 2, 1, 1),
                     (ORES, 2, 2, 1, 1), (ORES, 1, 2, 1, 1), (ORES, 4, 2, 1, 1)],
}
# растения события «Теплица»: росток, три стадии роста и урожай
for chain, k in (("gh_tomato", 1), ("gh_sunflower", 14), ("gh_strawberry", 17)):
    for t, col in enumerate(range(2, 7)):
        ISLAND[chain] = ISLAND.get(chain, []) + [(CROPS, col, 2 * k, 1, 2)]
ISLAND_OUTLINE = set()
for chain, specs in ISLAND.items():
    for i, spec in enumerate(specs):
        EXTRA[f"{chain}_{i}"] = spec
        if spec[0] in (FLOWERS, CROPS) and not (spec[0] == CROPS and spec[1] == 6) or (spec[0] == ORES and spec[1] < 5):
            ISLAND_OUTLINE.add(f"{chain}_{i}")
for kind, row in {"coins": 0, "gems": 1, "energy": 3, "items": 4}.items():
    EXTRA[f"chest_3_{kind}"] = (JEWEL, 0, row, 1, 1)
    EXTRA[f"chest_3_{kind}_open"] = (JEWEL, 4, row, 1, 1)

# портреты жителей: первый кадр (стоит лицом к игроку) из NPCs (Premade), кадр 64x64
NPCS = {
    "npc_mila": "Farmer_Buba", "npc_tim": "Farmer_Bob", "npc_jack": "Lumberjack_Jack",
    "npc_mike": "Miner_Mike", "npc_katy": "Bartender_Katy", "npc_chloe": "Chef_Chloe",
    "npc_fin": "Fisherman_Fin", "npc_bruno": "Bartender_Bruno",
}


def crop_opaque(im):
    box = im.getbbox()
    return im.crop(box) if box else im


def cut(pack, spec):
    if spec[0] == "px":
        _, path, x0, y0, x1, y1 = spec
        sheet = Image.open(os.path.join(pack, path)).convert("RGBA")
        return crop_opaque(sheet.crop((x0, y0, x1, y1)))
    path, c, r, w, h = spec
    sheet = Image.open(os.path.join(pack, path)).convert("RGBA")
    return crop_opaque(sheet.crop((c * 16, r * 16, (c + w) * 16, (r + h) * 16)))


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    pack, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))
    catalog = json.load(open(os.path.join(here, "..", "Sources", "HearthCore", "Resources", "chains.json")))
    need = ["debris"] + [k for ch in catalog["chains"] for k in ch["items"] + [ch["generator"]]]
    missing = [k for k in need if k not in SPRITES]
    if missing:
        sys.exit("нет спрайтов для: " + ", ".join(missing))
    images = {}
    for key in need:
        im = cut(pack, SPRITES[key])
        if key in OUTLINED:
            im = outline(im)
        if im.getbbox() is None:
            sys.exit(f"{key}: пустая клетка")
        im.save(os.path.join(out, key + ".png"))
        images[key] = im
    for key, spec in EXTRA.items():
        im = cut(pack, spec)
        if spec[0] == "px" or key in ISLAND_OUTLINE:
            im = outline(im)
        if im.getbbox() is None:
            sys.exit(f"{key}: пустая клетка")
        im.save(os.path.join(out, key + ".png"))
    for key, name in NPCS.items():
        sheet = Image.open(os.path.join(pack, "NPCs (Premade)", name + ".png")).convert("RGBA")
        frame = crop_opaque(sheet.crop((0, 0, 64, 64)))
        # квадрат по большей стороне, фигурка по центру снизу: одинаково встает в иконки
        side = max(frame.size)
        sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sq.paste(frame, ((side - frame.width) // 2, side - frame.height))
        sq.save(os.path.join(out, key + ".png"))
    print(f"{len(images)} спрайтов и {len(NPCS)} жителей в {out}")

    if "--sheet" in sys.argv:
        dest = sys.argv[sys.argv.index("--sheet") + 1]
        s, cell = 4, 40
        rows = catalog["chains"]
        width = max(len(ch["items"]) for ch in rows) + 1
        sheet = Image.new("RGBA", (width * cell * s // 2 + 20, (len(rows) + 1) * cell * s // 2 + 20), (205, 220, 170, 255))
        d = ImageDraw.Draw(sheet)
        step = cell * s // 2
        for y, ch in enumerate(rows + [{"items": [], "generator": "debris", "id": "debris"}]):
            for x, key in enumerate([ch["generator"]] + ch["items"]):
                im = images[key]
                k = max(1, min(64 // im.width, 64 // im.height))
                big = im.resize((im.width * k, im.height * k), Image.NEAREST)
                sheet.alpha_composite(big, (10 + x * step + (step - big.width) // 2, 10 + y * step + (step - big.height) // 2))
                if x == 0:
                    d.rectangle([10 + 2, 10 + y * step + 2, 10 + step - 2, 10 + (y + 1) * step - 2], outline=(150, 90, 40, 255), width=2)
        sheet.convert("RGB").save(dest)


if __name__ == "__main__":
    main()
