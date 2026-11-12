#!/usr/bin/env python3
"""Makes random planets for the fuzz test suite: some valid but unusual, some broken in every way a hand-edited or
damaged code could be (wrong types, things that don't exist, loops, junk start areas, absurd numbers).

  tools/fuzz_planets.py --seed 1 --count 60 --lua out.lua      a Lua file returning the codes (one code per planet)
"""
import argparse
import base64
import json
import random
import zlib

TILES = ["grass-1", "grass-2", "grass-3", "grass-4", "dry-dirt", "dirt-1", "dirt-4", "dirt-7", "sand-1", "sand-3",
         "red-desert-0", "red-desert-3", "volcanic-ash-dark", "volcanic-cracks-warm", "snow-flat", "ice-rough",
         "fulgoran-sand", "midland-turquoise-bark", "lowland-olive-blubber", "highland-dark-rock",
         "water", "deepwater", "lava", "concrete", "landfill"]
RESOURCES = ["iron-ore", "copper-ore", "coal", "stone", "uranium-ore", "crude-oil", "calcite", "tungsten-ore",
             "sulfuric-acid-geyser", "scrap", "lithium-brine", "fluorine-vent"]
ITEMS = ["iron-plate", "copper-plate", "steel-plate", "electronic-circuit", "plastic-bar", "ice", "stone-brick",
         "water", "petroleum-gas", "light-oil", "sulfuric-acid", "wood", "coal"]
PACKS = ["automation-science-pack", "logistic-science-pack", "chemical-science-pack", "space-science-pack",
         "metallurgic-science-pack", "agricultural-science-pack"]
TECHS = ["automation", "logistics", "oil-processing", "space-platform-thruster", "rocket-silo", "steel-processing"]
CATEGORIES = ["crafting", "smelting", "chemistry", "oil-processing", "cryogenics", "metallurgy", "organic",
              "electromagnetics", "crafting-with-fluid", "advanced-crafting"]
SHAPES = ["lakes", "big-lakes", "island", "archipelago", "continents"]
LIQUIDS = ["water", "lava", "oil", "ammonia", "slime", "none"]
CLIFFS = ["none", "nauvis", "vulcanus", "gleba", "fulgora"]
PLANTS = ["forest", "dry-trees", "lichen", "gleba-plants"]
ROCKS = ["rocks", "volcanic-rocks", "fulgora-rocks", "ruins", "icebergs", "stromatolites"]
ENEMIES = ["none", "biters", "pentapods", "demolishers"]
PICTURES = ["auto", "nauvis", "vulcanus", "gleba", "fulgora", "aquilo"]
ASTEROIDS = ["nauvis_vulcanus", "nauvis_gleba", "gleba_aquilo", "aquilo_solar_system_edge"]
EFFECTS = ["mining-drill-productivity-bonus", "laboratory-speed", "laboratory-productivity", "worker-robot-speed",
           "character-mining-speed"]
JUNK = [None, True, False, -1, 0, 1e30, -1e30, "", " ", "x" * 300, "\n\t", [], {}, [1, 2], {"a": 1}, "nonsense",
        "@ore:", "@ore:nope", "@recipe:nope", "@tech:nope", "@pack", "@discovery", "ünïcödé ⚙"]


def code(planets):
    raw = json.dumps({"planets": planets}, separators=(",", ":")).encode()
    return "PW1:" + base64.b64encode(zlib.compress(raw, 9)).decode()


def maybe(r, value, chance=0.15):
    """The value, or (sometimes) junk instead."""
    return r.choice(JUNK) if r.random() < chance else value


def amount_list(r, things, n):
    return [maybe(r, [r.choice(things), r.randint(1, 50)], 0.1) for _ in range(r.randint(0, n))]


def planet(r, i, broken):
    junk = 0.25 if broken else 0.0
    m = lambda v: maybe(r, v, junk)
    ore_keys = [f"ore{k}" for k in range(r.randint(0, 4))]
    ores = [{"key": k, "kind": r.choice(["solid", "fluid"]), "name": f"Ore {k}",
             "base": r.choice(["iron-ore", "copper-ore", "stone", "coal", "uranium-ore", "crude-oil",
                               "sulfuric-acid-geyser", "lithium-brine", "fluorine-vent", "nope"]),
             "tint": m([r.random(), r.random(), r.random()]), "mining_time": m(r.uniform(0.1, 5)),
             "stack_size": m(r.randint(1, 500))} for k in ore_keys]
    own = [f"@ore:{k}" for k in ore_keys]
    things = ITEMS + own + ["@pack"]
    recipe_keys = [f"r{k}" for k in range(r.randint(0, 4))]
    tech_keys = [f"t{k}" for k in range(r.randint(0, 4))]
    radius = r.choice([32, 48, 64, 96, 10, 500])
    start = None
    if r.random() < 0.4:
        start = {"seed": m(r.randint(0, 2 ** 32 - 1)), "radius": m(radius),
                 "palette": [m(r.choice(TILES)) for _ in range(r.randint(0, 5))],
                 "tiles": [m([r.randint(-radius - 5, radius + 5), r.randint(-radius - 5, radius + 5), r.randint(-3, 40),
                              r.randint(0, 6)]) for _ in range(r.randint(0, 40))],
                 "add": [m({"name": r.choice(RESOURCES + own + ["tree-01", "big-rock", "biter-spawner",
                                                                "small-worm-turret", "cliff", "wooden-chest", "nope"]),
                            "x": r.uniform(-radius, radius), "y": r.uniform(-radius, radius),
                            "amount": m(r.randint(1, 10 ** 6)), "dir": m(r.randint(0, 20)),
                            "orientation": m(r.choice(["west-to-east", "north-to-south", "bogus"])),
                            "variation": m(r.randint(0, 300)), "color": m(r.randint(0, 300)), "enemy": m(r.random() < 0.3)})
                         for _ in range(r.randint(0, 30))],
                 "remove": [m({"name": r.choice(RESOURCES + ["tree-01", "nope"]), "x": r.uniform(-radius, radius),
                               "y": r.uniform(-radius, radius)}) for _ in range(r.randint(0, 10))]}
    p = {
        "id": m(f"fz{i:04d}x"),
        "name": m(f"Fuzz {i}"),
        "author": m("Fuzzer"),
        "description": m("A random planet."),
        "starting_planet": m(r.random() < 0.3),
        "credits": m([m({"name": "Old", "author": "Someone"}) for _ in range(r.randint(0, 12))]),
        "mods": m({r.choice(["space-age", "quality", "no-such-mod", "bad name!"]): m("1.0.0")}),
        "look": {"picture": m(r.choice(PICTURES)), "sky": m(r.choice(PICTURES)), "tint": m([r.random(), 0.5, 1])},
        "space": {"from": m(r.choice(["nauvis", "vulcanus", "gleba", "fulgora", "aquilo", "nope"])),
                  "length": m(r.randint(100, 300000)), "distance": m(r.uniform(0, 80)),
                  "orientation": m(r.uniform(-2, 2)), "magnitude": m(r.uniform(0, 5)), "asteroids": m(r.choice(ASTEROIDS))},
        "physics": {"gravity": m(r.uniform(0, 120)), "pressure": m(r.uniform(0, 12000)),
                    "magnetic_field": m(r.uniform(0, 1200)), "solar_power": m(r.uniform(0, 1200)),
                    "day_length": m(r.uniform(0, 200)), "freezing": m(r.random() < 0.3), "lightning": m(r.random() < 0.3)},
        "terrain": {"shape": m(r.choice(SHAPES)), "liquid": m(r.choice(LIQUIDS)), "liquid_amount": m(r.uniform(0, 8)),
                    "patch_size": m(r.uniform(0, 6)), "decorations": m(r.random() < 0.7),
                    "ground": [m({"tile": m(r.choice(TILES)), "share": m(r.uniform(0, 120))})
                               for _ in range(r.randint(0, 14))],
                    "cliffs": {"style": m(r.choice(CLIFFS)), "amount": m(r.uniform(0, 8))},
                    "plants": {"styles": m(r.sample(PLANTS, r.randint(0, 4))), "amount": m(r.uniform(0, 8))},
                    "rocks": {"styles": m(r.sample(ROCKS, r.randint(0, 6))), "amount": m(r.uniform(0, 8))}},
        "enemies": {"kind": m(r.choice(ENEMIES)), "amount": m(r.uniform(0, 8))},
        "ores": m(ores),
        "resources": [m({"resource": m(r.choice(RESOURCES + own + ["nope"])), "frequency": m(r.uniform(0, 8)),
                         "size": m(r.uniform(0, 8)), "richness": m(r.uniform(0, 8)),
                         "starting": m(r.choice([True, False, None]))}) for _ in range(r.randint(0, 26))],
        "science": m({"name": "Fuzz pack", "base": m(r.choice(PACKS + ["nope"])), "tint": [1, 0.2, 0.2],
                      "ingredients": amount_list(r, things, 14), "count": m(r.randint(0, 200)),
                      "time": m(r.uniform(0, 700)), "category": m(r.choice(CATEGORIES + ["nope"])),
                      "only_here": m(r.random() < 0.5), "spoil_minutes": m(r.uniform(0, 700))}) if r.random() < 0.7 else None,
        "discovery": m({"prerequisites": [m(r.choice(TECHS + ["@tech:" + k for k in tech_keys] + ["nope"]))
                                          for _ in range(r.randint(0, 3))],
                        "count": m(r.randint(0, 10 ** 7)), "time": m(r.uniform(0, 700)),
                        "ingredients": amount_list(r, PACKS + ["@pack", "iron-plate"], 5)}),
        "recipes": [m({"key": m(k), "name": m(f"Recipe {k}"), "ingredients": amount_list(r, things, 14),
                       "results": amount_list(r, things, 6), "time": m(r.uniform(0, 700)),
                       "category": m(r.choice(CATEGORIES + ["nope"])), "only_here": m(r.random() < 0.5),
                       "enabled": m(r.random() < 0.3)}) for k in recipe_keys],
        "technologies": [m({"key": m(k), "name": m(f"Tech {k}"),
                            "prerequisites": [m(r.choice(TECHS + ["@discovery"] + ["@tech:" + t for t in tech_keys] + ["nope"]))
                                              for _ in range(r.randint(0, 3))],
                            "count": m(r.randint(0, 10 ** 7)), "time": m(r.uniform(0, 700)), "infinite": m(r.random() < 0.3),
                            "icon": m(r.choice(ITEMS + ["nope"])),
                            "ingredients": amount_list(r, PACKS + ["@pack"], 5),
                            "effects": [m(r.choice([{"type": "unlock-recipe", "recipe": r.choice(["@recipe:" + k for k in recipe_keys] + ["@pack", "iron-gear-wheel", "nope"])},
                                                    {"type": "change-recipe-productivity", "recipe": "@pack", "change": r.uniform(-2, 20)},
                                                    {"type": r.choice(EFFECTS), "modifier": r.uniform(-20, 20)},
                                                    {"type": "nope"}])) for _ in range(r.randint(0, 4))]})
                         for k in tech_keys],
    }
    if start:
        p["start"] = m(start)
    if broken and r.random() < 0.1:
        return r.choice(JUNK)  # not even a table
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--count", type=int, default=60)
    ap.add_argument("--lua", required=True)
    a = ap.parse_args()
    r = random.Random(a.seed)
    codes = [code([planet(r, i, broken=i % 2 == 1)]) for i in range(a.count)]
    # and a few whole-code oddities: an empty pack, a pack of 3, a code that isn't JSON
    codes.append(code([]))
    codes.append(code([planet(r, 900 + k, False) for k in range(3)]))
    codes.append("PW1:" + base64.b64encode(zlib.compress(b"[1,2,3]")).decode())
    with open(a.lua, "w") as f:
        f.write("-- Made by tools/fuzz_planets.py (random planets for the fuzz suite).\n")
        f.write("return " + json.dumps(" ".join(codes)) + "\n")
    print(f"wrote {a.lua}: {len(codes)} codes")


if __name__ == "__main__":
    main()
