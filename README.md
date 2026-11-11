# Planet Workshop

A Factorio 2.1 + Space Age mod: design your own planets in an in-game Planet Designer, then add them to any Space
Age save and share them with other players as **planet codes** (like blueprint strings).

**Status: step 0 (proof of concept) is done.** A planet code pasted into the mod's startup setting becomes a real
planet: you can research it, fly to it, and mine its own ore, and it comes with its own science pack, recipes and
technologies. The designer GUI comes later (see the plan below).

## How planet codes work

Factorio's planets are prototypes, made once while the game starts up. A running game can't create them, and the
loading game can't read files or saves. So the bridge is a startup setting:

1. The designer (later) makes a code: `PW1:` + base64 of zlib-compressed JSON (`helpers.encode_string`).
2. The player pastes it into **Settings > Mod settings > Startup > Planet codes**. Several codes can be pasted one
   after another, separated by spaces.
3. After the restart, `data-updates.lua` decodes the codes in plain Lua (`lib/base64.lua`, `lib/inflate.lua`,
   `lib/json.lua`: the data stage has no `helpers`) and builds the prototypes (`prototypes/build.lua`).

Codes are only ever read as data, never run. Anything in a code that refers to something missing (a tile or item
from a mod that isn't installed, a typo) is left out with a message to the player, not a crash.

## The code format (version 1)

The JSON inside a code is a pack: `{"planets": [planet, ...]}`. A planet (see `lib/spec.lua` for every limit and
default, and `tests/planets/brimstone.json` for a full example):

| Field | What it is |
|---|---|
| `id` | 4-16 lower-case letters/digits, unique per planet; every prototype is named `pw-<id>-...` |
| `name`, `description`, `author` | shown in game |
| `look` | `picture` (nauvis / vulcanus / gleba / fulgora / aquilo) and `tint` |
| `space` | `from` (the planet the route starts at), `length` (km), star-map `distance` / `orientation` / `magnitude`, `asteroids` (a Space Age route's mix) |
| `physics` | `gravity`, `pressure`, `magnetic_field`, `solar_power`, `day_length` (minutes) |
| `terrain` | `tiles`: the ground tiles that may generate |
| `ores` | the planet's own ores: `key`, `name`, `tint`, `base` (vanilla ore to look like), `mining_time`, `stack_size` |
| `resources` | what generates: `resource` (a resource or `@ore:<key>`), `frequency`, `size`, `richness` |
| `science` | its science pack: `name`, `tint`, `base` (pack to look like), `ingredients`, `count`, `time`, `category`, `only_here` |
| `discovery` | the discovery technology's `prerequisites`, `count`, `time`, `ingredients` |
| `recipes` | `key`, `name`, `ingredients`, `results`, `category`, `time`, `only_here`, `enabled` |
| `technologies` | `key`, `name`, `icon`, `prerequisites`, `count`, `time`, `ingredients`, `infinite`, `effects` (`unlock-recipe`, `change-recipe-productivity`, bonus modifiers) |

References to the planet's own things start with `@`: `@pack`, `@ore:<key>`, `@recipe:<key>`, `@tech:<key>`,
`@discovery`. Anything else names a vanilla or modded prototype. "Only here" recipes use a hidden surface property
`pw-<id>-here` that only that planet has.

## Developing

- `tools/run_tests.sh [bridge codec added]` runs the headless test suites in a throwaway folder (never
  `~/.factorio`). `KEEP=1` keeps the folder for reading logs.
  - **bridge**: two test planets (Brimstone, and Frostbite, which is full of mistakes) plus a broken code and a
    too-new code, loaded into a new game: prototypes, generated terrain and ore, research, and real assemblers
    showing the pack is only made on its planet.
  - **codec**: codes made in game with `helpers.encode_string` read back by the mod's decoder; a 1.5 MB planet;
    428 damaged or cut codes that must fail politely; JSON edge cases.
  - **added**: the codes added to a save that was made without them.
- `tools/make_code.py planet.json` makes a code from a planet JSON file (`--decode CODE` shows what's inside one).

## Licence

MIT (see LICENSE). No images are shipped: everything is vanilla art, tinted.
