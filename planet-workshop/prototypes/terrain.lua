-- A planet's map generation (data stage): land shape, ground, liquid, resources, cliffs, plants, rocks,
-- decorations and enemies, plus the "auto" picture and sky.
--
-- Every planet gets its own named noise expressions (pw_<id>_...), and its map_gen_settings point the game's
-- properties at them (property_expression_names), so nothing here changes how Nauvis or any other planet
-- generates. Ground tiles are placed by our own expressions, not their home planet's, so tiles from different
-- planets mix in natural patches. Resources get the planet's own patch set (like Nauvis' starting ores), so
-- every starting resource gets a patch near the landing spot.

local resource_autoplace = require("resource-autoplace")
local catalog = require("__planet-workshop__.lib.catalog")

local M = {}

-- The vanilla planet each natural tile comes from, and each planet's reference colour (its ground and
-- liquids' map colours averaged, liquids counting a quarter): worked out once from the loaded prototypes.
local home_of_tile, reference_colors
local function scan_planets()
  if home_of_tile then return end
  home_of_tile, reference_colors = {}, {}
  for _, planet_name in ipairs(catalog.PLANETS) do
    local planet = data.raw.planet[planet_name]
    local settings = planet and planet.map_gen_settings and planet.map_gen_settings.autoplace_settings
    local land, wet = {}, {}
    for tile_name in pairs(settings and settings.tile and settings.tile.settings or {}) do
      home_of_tile[tile_name] = home_of_tile[tile_name] or planet_name
      local tile = data.raw.tile[tile_name]
      if tile and tile.map_color then
        table.insert(tile.fluid and wet or land, {color = tile.map_color, weight = 1})
      end
    end
    local land_avg, wet_avg = catalog.average_color(land), catalog.average_color(wet)
    if land_avg and wet_avg then
      reference_colors[planet_name] = catalog.average_color{{color = land_avg, weight = 3}, {color = wet_avg, weight = 1}}
    else
      reference_colors[planet_name] = land_avg or wet_avg
    end
  end
end
local function tile_home(name)
  scan_planets()
  return home_of_tile[name]
end

local function number_text(n)
  return string.format("%.6g", n)
end

local function entity_exists(name)
  for _, t in ipairs{"tree", "plant", "simple-entity", "unit-spawner", "turret", "fish", "lightning-attractor",
    "resource", "segmented-unit"} do
    if data.raw[t] and data.raw[t][name] then return data.raw[t][name] end
  end
  return nil
end

--- Adds a named noise expression and returns its name.
local function expression(name, text)
  data:extend{{type = "noise-expression", name = name, expression = text}}
  return name
end

--- Builds the map_gen_settings and fills in the planet's look and enemy fields. `b` is the Builder (build.lua).
function M.build(b, planet)
  local p, id = b.p, b.p.id
  local t = p.terrain
  local x = "pw_" .. id .. "_" -- noise names: underscores only (a dash reads as minus)
  local mgs = {
    property_expression_names = {},
    autoplace_controls = {water = {frequency = 1, size = t.liquid_amount, richness = 1}},
    -- treat_missing_as_default = false: only what is listed generates (some tiles, like Aquilo's rough ice,
    -- would otherwise turn up by default)
    autoplace_settings = {
      tile = {treat_missing_as_default = false, settings = {}},
      decorative = {treat_missing_as_default = false, settings = {}},
      entity = {treat_missing_as_default = false, settings = {}},
    },
  }
  local props = mgs.property_expression_names
  local tiles, decoratives, entities = mgs.autoplace_settings.tile.settings,
    mgs.autoplace_settings.decorative.settings, mgs.autoplace_settings.entity.settings

  -- Land shape ----------------------------------------------------------------------------------------------
  local shape = catalog.SHAPES[t.shape]
  if shape.vanilla then
    props.elevation = shape.vanilla
  else
    -- Our shapes: noise land, plus land around the landing spot (with a ragged edge, not a circle) and, on
    -- water planets, a starting pond (also ragged) so there is water for steam power.
    local land = "25 * (" .. number_text(shape.land) .. " + quick_multioctave_noise{x = x, y = y,\z
                   seed0 = map_seed, seed1 = 4711, octaves = 5,\z
                   input_scale = " .. number_text(shape.scale) .. " * segmentation_multiplier, output_scale = 1,\z
                   octave_input_scale_multiplier = 2, octave_output_scale_multiplier = 0.5}) - water_level"
    local start = "25 - distance / 5 + 12 * quick_multioctave_noise{x = x, y = y, seed0 = map_seed, seed1 = 4712,\z
                   octaves = 3, input_scale = 1/50, output_scale = 1,\z
                   octave_input_scale_multiplier = 2, octave_output_scale_multiplier = 0.5}"
    local text = "max(" .. start .. ", " .. land .. ")"
    if t.liquid == "water" then
      text = "min(" .. text .. ", -2.5 + (distance_from_nearest_point{x = x, y = y, points = starting_lake_positions,\z
                maximum_distance = 1024} + 10 * quick_multioctave_noise{x = x, y = y, seed0 = map_seed, seed1 = 4713,\z
                octaves = 3, input_scale = 1/12, output_scale = 1, octave_input_scale_multiplier = 2,\z
                octave_output_scale_multiplier = 0.5}) / 6)"
    end
    props.elevation = expression(x .. "elevation", text)
    props.cliff_elevation = "cliff_elevation_from_elevation"
    props.cliffiness = "cliffiness_basic"
  end

  -- Liquid --------------------------------------------------------------------------------------------------
  local liquid = catalog.LIQUIDS[t.liquid]
  local liquid_tiles = {}
  if liquid.shallow then
    for depth, threshold in pairs{shallow = 0, deep = liquid.deep_below or -2} do
      local name = liquid[depth]
      if data.raw.tile[name] then
        tiles[name] = {}
        liquid_tiles[name] = true
        props["tile:" .. name .. ":probability"] = expression(x .. "liquid_" .. depth,
          "if(elevation < " .. threshold .. ", " .. (depth == "deep" and 2000 or 1000) .. ", -1000)")
      else
        b:problem("missing", name, "liquid")
      end
    end
    if liquid.fish and data.raw.fish and data.raw.fish.fish then entities.fish = {} end
  end

  -- Ground --------------------------------------------------------------------------------------------------
  -- Each ground tile has its own patch noise; the highest wins, so each tile's share sets how often it wins.
  -- (Liquids use 1000 / 2000, so they always win where the land is low enough.)
  local ground = {}
  for _, g in ipairs(t.ground) do
    local tile = data.raw.tile[g.tile]
    if not tile then
      b:problem("missing", g.tile, "ground")
    elseif not tile.autoplace then
      b:problem("cant-generate", g.tile)
    elseif not liquid_tiles[g.tile] then
      ground[#ground + 1] = g
    end
  end
  if #ground == 0 then
    b:problem("no-ground")
    for _, name in ipairs{"sand-1", "red-desert-0", "dirt-4"} do
      if data.raw.tile[name] then ground[#ground + 1] = {tile = name, share = 1} end
    end
  end
  local share_total = 0
  for _, g in ipairs(ground) do share_total = share_total + g.share end
  local input_scale = 1 / (48 * t.patch_size)
  for i, g in ipairs(ground) do
    tiles[g.tile] = {}
    local bias = 0.6 * math.log(g.share / (share_total / #ground))
    props["tile:" .. g.tile .. ":probability"] = expression(x .. "ground_" .. i,
      "multioctave_noise{x = x, y = y, persistence = 0.6, seed0 = map_seed, seed1 = " .. (7000 + 13 * i) .. ",\z
                         octaves = 4, input_scale = " .. number_text(input_scale) .. ", output_scale = 1} + " ..
      number_text(10 + bias)) -- kept above zero: the highest wins only among positive values
  end

  -- Look: picture and sky -----------------------------------------------------------------------------------
  local colors, by_home = {}, {}
  for _, g in ipairs(ground) do
    colors[#colors + 1] = {color = data.raw.tile[g.tile].map_color or {0.5, 0.5, 0.5}, weight = g.share / share_total}
    local home = tile_home(g.tile) or "other" -- modded tiles: no home planet, colour decides
    by_home[home] = (by_home[home] or 0) + g.share
  end
  if liquid.shallow and data.raw.tile[liquid.shallow] then
    colors[#colors + 1] = {color = data.raw.tile[liquid.shallow].map_color or {0.2, 0.3, 0.4},
      weight = 0.35 * math.min(1, math.sqrt(t.liquid_amount))}
  end
  -- "auto" picture: the home planet of half or more of the ground, else the closest reference colour
  local picture = p.look.picture
  if picture == "auto" then
    for home, share in pairs(by_home) do
      if share >= share_total / 2 and data.raw.planet[home] then picture = home end
    end
  end
  if picture == "auto" then
    scan_planets()
    picture = catalog.closest_picture(catalog.average_color(colors), reference_colors)
  end
  b.picture = picture
  local sky = p.look.sky
  if sky == "auto" then
    sky = "nauvis"
    local best = 0
    for _, home in ipairs(catalog.PLANETS) do
      if (by_home[home] or 0) > best then sky, best = home, by_home[home] end
    end
  end
  b.sky = sky

  -- Cliffs --------------------------------------------------------------------------------------------------
  local cliff = catalog.CLIFFS[t.cliffs.style]
  if cliff and not (data.raw.cliff and data.raw.cliff[cliff]) then
    b:problem("missing", cliff, "cliffs")
    cliff = nil
  end
  mgs.cliff_settings = {
    name = cliff or "cliff", control = "", cliff_elevation_0 = 10, cliff_elevation_interval = 40, cliff_smoothing = 0,
    richness = cliff and t.cliffs.amount or 0,
  }

  -- Plants and rocks ----------------------------------------------------------------------------------------
  local function scatter(kind, styles, amount, make)
    if amount <= 0 then return end
    for s, style in ipairs(styles) do
      local list = {}
      for _, name in ipairs(catalog[kind][style]) do
        local proto = entity_exists(name)
        if proto and proto.autoplace then list[#list + 1] = name end
      end
      for _, name in ipairs(list) do
        entities[name] = {}
        props["entity:" .. name .. ":probability"] = make(style, s, #list)
      end
    end
  end
  scatter("PLANTS", t.plants.styles, t.plants.amount, function(style, s, count)
    -- forests: a shared patch noise per style; more amount = more and denser forest
    local name = x .. "plants_" .. s
    if not data.raw["noise-expression"][name] then
      expression(name, "clamp((multioctave_noise{x = x, y = y, persistence = 0.6, seed0 = map_seed,\z
                                 seed1 = " .. (900 + s) .. ", octaves = 3, input_scale = 1/90, output_scale = 1}\z
                                 + " .. number_text(0.25 * (math.log(t.plants.amount) / math.log(2)) - 0.15) .. ") * 2, 0, 1) * " ..
        number_text(0.6 * (catalog.PLANT_DENSITY[style] or 1) / count))
    end
    return name
  end)
  scatter("ROCKS", t.rocks.styles, t.rocks.amount, function(style, s, count)
    local name = x .. "rocks_" .. s
    if not data.raw["noise-expression"][name] then
      local rarity = (style == "ruins" or style == "icebergs") and 0.2 or 1
      expression(name, "if(distance < 24, 0, " .. number_text(0.003 * t.rocks.amount * rarity / count) .. ")")
    end
    return name
  end)

  -- Decorations: those of each ground tile's home planet ----------------------------------------------------
  if t.decorations then
    for home in pairs(by_home) do
      local planet_proto = data.raw.planet[home]
      local settings = planet_proto and planet_proto.map_gen_settings and planet_proto.map_gen_settings.autoplace_settings
      for name in pairs(settings and settings.decorative and settings.decorative.settings or {}) do
        if data.raw["optimized-decorative"] and data.raw["optimized-decorative"][name] then decoratives[name] = {} end
      end
    end
  end

  -- Enemies -------------------------------------------------------------------------------------------------
  local enemy = catalog.ENEMIES[p.enemies.kind]
  planet.pollutant_type = enemy.pollutant
  if enemy.pollutant and not (data.raw["airborne-pollutant"] and data.raw["airborne-pollutant"][enemy.pollutant]) then
    planet.pollutant_type = nil
  end
  for _, name in ipairs(enemy.entities or {}) do
    if entity_exists(name) then entities[name] = {} else b:problem("missing", name, "enemies") end
  end
  if enemy.control then
    mgs.autoplace_controls[enemy.control] = {frequency = p.enemies.amount, size = p.enemies.amount, richness = 1}
  end
  for _, control in ipairs(enemy.controls or {}) do
    mgs.autoplace_controls[control] = {frequency = p.enemies.amount, size = p.enemies.amount, richness = 1}
  end
  for property, name in pairs(enemy.properties or {}) do
    if data.raw["noise-expression"][name] then props[property] = name end
  end
  local n = 0
  for name, text in pairs(enemy.expressions or {}) do
    n = n + 1
    if entities[name] then props["entity:" .. name .. ":probability"] = expression(x .. "enemy_" .. n, text) end
  end
  if enemy.territory then
    local units = {}
    for _, name in ipairs(enemy.territory) do
      if data.raw["segmented-unit"] and data.raw["segmented-unit"][name] then units[#units + 1] = name end
    end
    if #units > 0 then
      local radius = math.floor(384 / math.sqrt(p.enemies.amount))
      mgs.territory_settings = {
        units = units,
        territory_index_expression = expression(x .. "territory",
          "if(distance < 350, -1, voronoi_cell_id{x = x + 1000 * " .. radius .. ", y = y + 1000 * " .. radius .. ",\z
             seed0 = map_seed, seed1 = 0, grid_size = " .. radius .. ", distance_type = 'manhattan', jitter = 1})"),
        territory_variation_expression = "demolisher_variation_expression",
        minimum_territory_size = 10,
      }
    else
      b:problem("missing", "demolishers", "enemies")
    end
  end

  -- Resources -----------------------------------------------------------------------------------------------
  M.resources(b, mgs, x)

  return mgs
end

--- Every resource on the planet goes into the planet's own patch set ("pw_<id>"), so each starting resource
--- gets its own patch near the landing spot and Nauvis' patches stay as they were.
function M.resources(b, mgs, x)
  local p = b.p
  local props, entities = mgs.property_expression_names, mgs.autoplace_settings.entity.settings
  local set = "pw_" .. p.id
  local seen = {}
  for i, res in ipairs(p.resources) do
    local entity, label
    if res.resource:sub(1, 5) == "@ore:" then
      if p.ore_keys[res.resource:sub(6)] then
        entity = b:name("ore", res.resource:sub(6))
        label = {"", p.ore_keys[res.resource:sub(6)].name}
      else
        b:problem("missing", res.resource, "resources")
      end
    elseif res.resource:sub(1, 1) ~= "@" and data.raw.resource[res.resource] then
      if data.raw.resource[res.resource].autoplace then
        entity = res.resource
        label = data.raw.resource[entity].localised_name or {"entity-name." .. entity}
      else
        b:problem("cant-generate", res.resource)
      end
    else
      b:problem("missing", res.resource, "resources")
    end
    if entity and not seen[entity] then
      seen[entity] = true
      local proto = data.raw.resource[entity]
      local fluid = proto.category and proto.category:find("fluid") ~= nil
      local defaults = catalog.RESOURCE_DEFAULTS[entity] or catalog.RESOURCE_DEFAULTS[fluid and "fluid" or "solid"]
      local params = {}
      for k, v in pairs(defaults) do params[k] = v end
      local control = "pw-" .. p.id .. "-res-" .. i
      params.name = control
      params.autoplace_set_name = set
      params.autoplace_control_name = control
      params.order = fluid and "c" or "b"
      if res.starting == "yes" or (res.starting == "default" and not fluid) then
        params.has_starting_area_placement = true
      else
        params.has_starting_area_placement = false
      end
      params.seed1 = 100 + i
      local spec = resource_autoplace.resource_autoplace_settings(params)
      props["entity:" .. entity .. ":probability"] = expression(x .. "res_" .. i .. "_probability", spec.probability_expression)
      props["entity:" .. entity .. ":richness"] = expression(x .. "res_" .. i .. "_richness", spec.richness_expression)
      entities[entity] = {}
      if params.has_starting_area_placement then
        b.starting[#b.starting + 1] = {entity = entity, fluid = fluid, richness = res.richness}
      end
      data:extend{{
        type = "autoplace-control", name = control, localised_name = label, category = "resource", richness = true,
        order = "z-pw-" .. p.id .. "-" .. string.format("%02d", i),
      }}
      mgs.autoplace_controls[control] = {frequency = res.frequency, size = res.size, richness = res.richness}
    end
  end
end

return M
