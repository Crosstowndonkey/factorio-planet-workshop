-- The choices a planet's terrain is built from: liquids, cliff, plant, rock, enemy and sky styles, and how
-- planet pictures are matched to colours. Plain data, shared by the loader (data stage) and the designer.
-- Entities named here that don't exist in a game (another mod removed them) are simply skipped.

local M = {}

M.PLANETS = {"nauvis", "vulcanus", "gleba", "fulgora", "aquilo"}

--- Land shapes. `vanilla` shapes use the game's own elevation (with its starting lake); the others are ours
--- (prototypes/kit.lua). All of them keep land around the landing spot.
M.SHAPES = {
  lakes = {vanilla = "elevation_nauvis"},
  ["big-lakes"] = {vanilla = "elevation_lakes"},
  island = {vanilla = "elevation_island"},
  -- `land` shifts the noise (measured over 24,000 tiles: centred on 0, about 0.85 per standard deviation), so
  -- by default archipelagos are about 60% sea and continents 30% (measured); the liquid amount slider moves both.
  archipelago = {scale = 1 / 180, land = -0.2},
  continents = {scale = 1 / 700, land = 0.45},
}

--- Liquids: the tile for shallow and deep areas (deep where the elevation is below deep_below, default -2).
M.LIQUIDS = {
  water = {shallow = "water", deep = "deepwater", fish = true},
  lava = {shallow = "lava", deep = "lava-hot"},
  oil = {shallow = "oil-ocean-shallow", deep = "oil-ocean-deep"},
  ammonia = {shallow = "ammoniacal-ocean", deep = "ammoniacal-ocean-2"},
  -- wide shallow wetlands, like Gleba's: pentapod nests can only stand in shallow swamp, not on ground tiles
  slime = {shallow = "wetland-light-green-slime", deep = "gleba-deep-lake", deep_below = -8},
  none = {},
}

M.CLIFFS = {
  nauvis = "cliff", vulcanus = "cliff-vulcanus", gleba = "cliff-gleba", fulgora = "cliff-fulgora", none = false,
}

M.PLANTS = {
  forest = {"tree-01", "tree-02", "tree-02-red", "tree-03", "tree-04", "tree-05", "tree-06", "tree-06-brown",
    "tree-07", "tree-08", "tree-08-brown", "tree-08-red", "tree-09", "tree-09-brown", "tree-09-red"},
  ["dry-trees"] = {"dead-dry-hairy-tree", "dead-grey-trunk", "dead-tree-desert", "dry-hairy-tree", "dry-tree"},
  lichen = {"ashland-lichen-tree", "ashland-lichen-tree-flaming"},
  ["gleba-plants"] = {"boompuff", "cuttlepop", "funneltrunk", "hairyclubnub", "lickmaw", "slipstack", "stingfrond",
    "sunnycomb", "teflilly", "water-cane"},
}

--- How dense each plant style grows at amount 1 (a forest is thick; dead trees and lichen are scattered, as in
--- vanilla).
M.PLANT_DENSITY = {forest = 1, ["dry-trees"] = 0.04, lichen = 0.15, ["gleba-plants"] = 0.5}

M.ROCKS = {
  rocks = {"big-rock", "huge-rock", "big-sand-rock"},
  ["volcanic-rocks"] = {"big-volcanic-rock", "huge-volcanic-rock"}, -- only grow on volcanic ground
  ["fulgora-rocks"] = {"big-fulgora-rock", "fulgurite"},
  ruins = {"fulgoran-ruin-small", "fulgoran-ruin-medium", "fulgoran-ruin-big", "fulgoran-ruin-huge",
    "fulgoran-ruin-colossal"},
  icebergs = {"lithium-iceberg-big", "lithium-iceberg-huge"},
  stromatolites = {"iron-stromatolite", "copper-stromatolite"},
}

--- Enemies: what spawns, the map-gen control behind it, and what kind of pollution draws attacks.
M.ENEMIES = {
  none = {},
  biters = {
    entities = {"biter-spawner", "spitter-spawner", "small-worm-turret", "medium-worm-turret", "big-worm-turret",
      "behemoth-worm-turret"},
    control = "enemy-base", pollutant = "pollution",
  },
  pentapods = {
    entities = {"gleba-spawner", "gleba-spawner-small"},
    -- the nests' own control, plus the biters' one, which the shared nest noise (enemy_base_probability) reads
    control = "gleba_enemy_base", controls = {"enemy-base"}, pollutant = "spores",
    -- Gleba's own nest rules need Gleba's terrain masks, so other planets use the same nest noise as biters
    -- (Gleba's 0.02 cap left only 0-5 nests where biters got 180-370; measured)
    expressions = {
      ["gleba-spawner"] = "enemy_autoplace_base(0, 8) * (distance > 400)",
      ["gleba-spawner-small"] = "enemy_autoplace_base(0, 9) * (distance > 300)",
    },
  },
  demolishers = {territory = {"small-demolisher", "medium-demolisher", "big-demolisher"}},
}

-- Colours are compared by hue (chromaticity) plus half-weighted brightness.
local function colour_key(c)
  local sum = c[1] + c[2] + c[3]
  if sum <= 0 then return {1 / 3, 1 / 3, 1 / 3, 0} end
  return {c[1] / sum, c[2] / sum, c[3] / sum, sum / 6}
end

--- Averages a list of {color = {r, g, b} (0-1 or 0-255), weight = n} into {r, g, b} (0-1), or nil if empty.
function M.average_color(colors)
  local r, g, b, total = 0, 0, 0, 0
  for _, entry in ipairs(colors) do
    local c = entry.color
    local cr, cg, cb = c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0
    if cr > 1 or cg > 1 or cb > 1 then cr, cg, cb = cr / 255, cg / 255, cb / 255 end
    local w = entry.weight or 1
    r, g, b, total = r + cr * w, g + cg * w, b + cb * w, total + w
  end
  if total <= 0 then return nil end
  return {r / total, g / total, b / total}
end

--- The planet picture whose reference colour (refs[planet] = {r, g, b}, 0-1) is closest to a colour.
function M.closest_picture(color, refs)
  if not color then return "nauvis" end
  local target = colour_key(color)
  local best, best_d = "nauvis", math.huge
  for _, name in ipairs(M.PLANETS) do
    if refs[name] then
      local c = colour_key(refs[name])
      local d = 0
      for i = 1, 4 do d = d + (c[i] - target[i]) ^ 2 end
      if d < best_d then best, best_d = name, d end
    end
  end
  return best
end

--- Usual patch settings for resources (others get the "solid" or "fluid" defaults).
M.RESOURCE_DEFAULTS = {
  solid = {base_density = 8, regular_rq_factor_multiplier = 1.1, starting_rq_factor_multiplier = 1.5,
    candidate_spot_count = 22},
  fluid = {base_density = 8.2, base_spots_per_km2 = 1.8, random_probability = 1 / 48, random_spot_size_minimum = 1,
    random_spot_size_maximum = 1, additional_richness = 220000, regular_rq_factor_multiplier = 1},
  ["iron-ore"] = {base_density = 10, regular_rq_factor_multiplier = 1.1, starting_rq_factor_multiplier = 1.5,
    candidate_spot_count = 22},
  ["copper-ore"] = {base_density = 8, regular_rq_factor_multiplier = 1.1, starting_rq_factor_multiplier = 1.2,
    candidate_spot_count = 22},
  coal = {base_density = 8, regular_rq_factor_multiplier = 1.0, starting_rq_factor_multiplier = 1.1},
  stone = {base_density = 4, regular_rq_factor_multiplier = 1.0, starting_rq_factor_multiplier = 1.1},
  ["uranium-ore"] = {base_density = 0.9, base_spots_per_km2 = 1.25, random_spot_size_minimum = 2,
    random_spot_size_maximum = 4, regular_rq_factor_multiplier = 1},
}

return M
