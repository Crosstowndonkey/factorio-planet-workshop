-- Defines the terrain kit (data stage): hidden map-gen controls and the named noise expressions every Planet
-- Workshop planet and the designer preview use (see lib/kit.lua for why). Also passes what the runtime needs to
-- know (tile home planets, planet reference colours) in the "planet-workshop-kit" mod-data.

local resource_autoplace = require("resource-autoplace")
local util = require("util")
local catalog = require("__planet-workshop__.lib.catalog")
local kit = require("__planet-workshop__.lib.kit")

local M = {}

local function number_text(n)
  return string.format("%.6g", n)
end

local function control(name, category)
  return {type = "autoplace-control", name = name, category = category or "terrain", richness = true, hidden = true,
    order = "z-pw"}
end

local function expression(name, text)
  return {type = "noise-expression", name = name, expression = text}
end

--- Finer, fainter octaves: features are about 1 / input_scale tiles across (plain multioctave_noise does the
--- opposite: each octave is bigger, which made giant seas and lopsided ground mixes).
local function noise(seed, scale)
  return "quick_multioctave_noise{x = x, y = y, seed0 = map_seed, seed1 = " .. seed .. ", octaves = 4,\z
          input_scale = " .. scale .. ", output_scale = 1, octave_input_scale_multiplier = 2,\z
          octave_output_scale_multiplier = 0.5}"
end

local function entity_exists(name)
  for _, t in ipairs{"tree", "plant", "simple-entity", "unit-spawner", "turret", "fish", "lightning-attractor",
    "resource", "segmented-unit"} do
    if data.raw[t] and data.raw[t][name] then return data.raw[t][name] end
  end
  return nil
end
M.entity_exists = entity_exists

--- How many of a plant/rock style's entities exist and can be autoplaced in this game.
function M.style_entities(kind, style)
  local list = {}
  for _, name in ipairs(catalog[kind][style]) do
    local proto = entity_exists(name)
    if proto and proto.autoplace then list[#list + 1] = name end
  end
  return list
end

function M.define()
  local protos = {}
  local function add(p) protos[#protos + 1] = p end

  -- Ground: one patch noise per slot; a slot's control size is its tile's share / the average share.
  add(control(kit.control("patch")))
  for i = 1, kit.GROUND_SLOTS do
    add(control(kit.ground_control(i)))
    add(expression(kit.ground_expression(i),
      noise(7000 + 13 * i, "1 / (64 * var('control:" .. kit.control("patch") .. ":size'))") ..
      " + 10 + 0.485 * log2(var('control:" .. kit.ground_control(i) .. ":size'))"))
    -- (0.485 * log2 = 0.7 * ln; measured: shares 1:1 -> 50%, 3:1 -> 74%, 2:1 -> 64%)
  end

  -- Land shapes (the vanilla ones are used directly). `land` shifts the noise: archipelagos are about 60% sea,
  -- continents 30% (measured). Land around the landing spot has a ragged edge; water planets get a pond.
  for name, shape in pairs(catalog.SHAPES) do
    if not shape.vanilla then
      local land = "25 * (" .. number_text(shape.land) .. " + " ..
        noise(4711, number_text(shape.scale) .. " * segmentation_multiplier"):gsub("octaves = 4", "octaves = 5") ..
        ") - water_level"
      local start = "25 - distance / 5 + 12 * " .. noise(4712, "1/50"):gsub("octaves = 4", "octaves = 3")
      local text = "max(" .. start .. ", " .. land .. ")"
      add(expression(kit.elevation_expression(name, false), text))
      add(expression(kit.elevation_expression(name, true), "min(" .. text .. ", -2.5 + (distance_from_nearest_point{\z
        x = x, y = y, points = starting_lake_positions, maximum_distance = 1024} + 10 * " ..
        noise(4713, "1/12"):gsub("octaves = 4", "octaves = 3") .. ") / 6)"))
    end
  end

  -- Liquids: shallow below elevation 0, deep below -2 (or -8 for wide wetlands)
  add(expression(kit.X .. "liquid_shallow", "if(elevation < 0, 1000, -1000)"))
  add(expression(kit.X .. "liquid_deep_2", "if(elevation < -2, 2000, -1000)"))
  add(expression(kit.X .. "liquid_deep_8", "if(elevation < -8, 2000, -1000)"))

  -- Plants: forests on a shared patch noise per style; rocks scattered. Amount from the controls.
  add(control(kit.control("plants")))
  add(control(kit.control("rocks")))
  local s = 0
  for style in pairs(catalog.PLANTS) do
    s = s + 1
    local count = #M.style_entities("PLANTS", style)
    if count > 0 then
      add(expression(kit.plants_expression(style),
        "clamp((" .. noise(900 + s, "1/90"):gsub("octaves = 4", "octaves = 3") .. " + 0.25 * log2(var('control:" ..
        kit.control("plants") .. ":size')) - 0.15) * 2, 0, 1) * " ..
        number_text(0.6 * (catalog.PLANT_DENSITY[style] or 1) / count)))
    end
  end
  for style in pairs(catalog.ROCKS) do
    local count = #M.style_entities("ROCKS", style)
    if count > 0 then
      local rarity = (style == "ruins" or style == "icebergs") and 0.2 or 1
      add(expression(kit.rocks_expression(style), "if(distance < 24, 0, " .. number_text(0.003 * rarity / count) ..
        " * var('control:" .. kit.control("rocks") .. ":size'))"))
    end
  end

  -- Enemies: pentapod nests use the plain nest noise (Gleba's own needs Gleba's terrain masks)
  add(expression(kit.X .. "gleba_spawner", "enemy_autoplace_base(0, 8) * (distance > 400)"))
  add(expression(kit.X .. "gleba_spawner_small", "enemy_autoplace_base(0, 9) * (distance > 300)"))
  for i, radius in ipairs(kit.TERRITORY_RADII) do
    add(expression(kit.territory_expression(i),
      "if(distance < 350, -1, voronoi_cell_id{x = x + 1000 * " .. radius .. ", y = y + 1000 * " .. radius .. ",\z
         seed0 = map_seed, seed1 = 0, grid_size = " .. radius .. ", distance_type = 'manhattan', jitter = 1})"))
  end
  data:extend(protos)

  -- Resources: slots in one shared patch set ("pw_k"), so each starting slot gets a patch near the landing spot.
  -- A planet's resource maps to a slot of the right kind; its control holds the planet's frequency/size/richness.
  local seed = 300
  for _, slots in ipairs(kit.RESOURCE_SLOTS) do
    for i = 1, slots.count do
      seed = seed + 1
      local name = kit.resource_control(slots.key, i)
      local params = util.table.deepcopy(catalog.RESOURCE_DEFAULTS[slots.fluid and "fluid" or "solid"])
      params.name = name
      params.autoplace_set_name = "pw_k"
      params.autoplace_control_name = name
      params.order = slots.fluid and "c" or "b"
      params.has_starting_area_placement = slots.starting
      params.seed1 = seed
      data:extend{control(name, "resource")}
      local spec = resource_autoplace.resource_autoplace_settings(params)
      data:extend{
        expression(kit.resource_expression(slots.key, i, "probability"), spec.probability_expression),
        expression(kit.resource_expression(slots.key, i, "richness"), spec.richness_expression),
      }
    end
  end

  -- Stand-in ores for the designer preview: an untinted iron ore that never generates on its own.
  for i = 1, kit.PREVIEW_ORES do
    local ore = util.table.deepcopy(data.raw.resource["iron-ore"])
    ore.name = kit.preview_ore(i)
    ore.localised_name = {"planet-workshop.preview-ore", tostring(i)}
    ore.autoplace = {order = "b", probability_expression = 0, richness_expression = 0}
    ore.factoriopedia_simulation = nil
    ore.hidden = true
    ore.hidden_in_factoriopedia = true
    data:extend{ore}
  end
end

--- Tile home planets and each vanilla planet's reference colour (its ground and liquids' map colours averaged,
--- liquids counting a quarter), for the "auto" picture and sky. Also stored for runtime (designer).
function M.planet_info()
  local home, refs = {}, {}
  for _, planet_name in ipairs(catalog.PLANETS) do
    local planet = data.raw.planet[planet_name]
    local settings = planet and planet.map_gen_settings and planet.map_gen_settings.autoplace_settings
    local land, wet = {}, {}
    for tile_name in pairs(settings and settings.tile and settings.tile.settings or {}) do
      home[tile_name] = home[tile_name] or planet_name
      local tile = data.raw.tile[tile_name]
      if tile and tile.map_color then
        table.insert(tile.fluid and wet or land, {color = tile.map_color, weight = 1})
      end
    end
    local land_avg, wet_avg = catalog.average_color(land), catalog.average_color(wet)
    if land_avg and wet_avg then
      refs[planet_name] = catalog.average_color{{color = land_avg, weight = 3}, {color = wet_avg, weight = 1}}
    else
      refs[planet_name] = land_avg or wet_avg
    end
  end
  return home, refs
end

--- What the designer needs at runtime to build the same map settings (stored in the "planet-workshop-kit"
--- mod-data): tile homes, reference colours, the existing entities of each plant/rock style, and each vanilla
--- planet's decoratives.
function M.runtime_info()
  local home, refs = M.planet_info()
  local styles = {PLANTS = {}, ROCKS = {}}
  for kind in pairs(styles) do
    for style in pairs(catalog[kind]) do styles[kind][style] = M.style_entities(kind, style) end
  end
  local decoratives = {}
  for _, planet_name in ipairs(catalog.PLANETS) do
    decoratives[planet_name] = M.planet_decoratives(planet_name)
  end
  return {tile_home = home, reference_colors = refs, styles = styles, decoratives = decoratives}
end

function M.planet_decoratives(planet_name)
  local list = {}
  local planet = data.raw.planet[planet_name]
  local settings = planet and planet.map_gen_settings and planet.map_gen_settings.autoplace_settings
  for name in pairs(settings and settings.decorative and settings.decorative.settings or {}) do
    if data.raw["optimized-decorative"] and data.raw["optimized-decorative"][name] then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

return M
