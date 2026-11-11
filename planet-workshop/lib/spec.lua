-- The planet format (version 1): what a planet in a code may contain, with defaults and limits.
--
-- normalize(raw) turns an untrusted table (from someone's shared code) into a clean planet: every field the
-- right type, numbers clamped to their limits, text trimmed, missing parts filled with defaults. It never
-- errors; anything unusable becomes a problem message. Checking that tiles, items and technologies exist
-- is left to the loader (prototypes/build.lua), because only the data stage knows what exists.
--
-- References to the planet's own things start with "@":
--   "@pack"         its science pack          "@ore:<key>"    one of its ores (the ore item)
--   "@recipe:<key>" one of its recipes        "@tech:<key>"   one of its technologies
--   "@discovery"    its discovery technology
-- Anything else names a vanilla or modded prototype ("iron-plate", "space-platform-thruster").
--
-- Works in both stages (no game API needed).

local catalog = require("__planet-workshop__.lib.catalog")

local M = {}

M.PICTURES = {nauvis = true, vulcanus = true, gleba = true, fulgora = true, aquilo = true}
--- Asteroid mixes, named like Space Age's routes (asteroid-spawn-definitions.lua).
M.ASTEROIDS = {
  nauvis_vulcanus = true, nauvis_gleba = true, nauvis_fulgora = true, vulcanus_gleba = true,
  gleba_fulgora = true, gleba_aquilo = true, fulgora_aquilo = true, aquilo_solar_system_edge = true,
}
--- Vanilla ores a custom ore can take its look from.
M.ORE_BASES = {["iron-ore"] = true, ["copper-ore"] = true, ["stone"] = true, ["coal"] = true, ["uranium-ore"] = true}
--- Bonus effects a planet technology may give (besides unlocking its recipes).
M.MODIFIERS = {
  ["mining-drill-productivity-bonus"] = true, ["worker-robot-speed"] = true, ["laboratory-speed"] = true,
  ["laboratory-productivity"] = true, ["character-mining-speed"] = true, ["change-recipe-productivity"] = true,
}

M.LIMITS = {
  name = 40, description = 500, author = 40, list = 64, ingredients = 12,
}

-- Helpers ---------------------------------------------------------------------------------------------------

local function problem(problems, key, ...)
  problems[#problems + 1] = {"planet-workshop-problem." .. key, ...}
end

local function text(value, max, default)
  if type(value) ~= "string" then return default end
  value = value:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if value == "" then return default end
  if #value > max then value = value:sub(1, max) end
  return value
end

local function number(value, low, high, default)
  if type(value) ~= "number" or value ~= value then return default end
  if value < low then return low end
  if value > high then return high end
  return value
end

local function list(value)
  if type(value) ~= "table" then return {} end
  local out = {}
  for i = 1, math.min(#value, M.LIMITS.list) do out[i] = value[i] end
  return out
end

--- A colour {r, g, b} or {r = , g = , b = } with 0-1 or 0-255 values -> {r, g, b} in 0-1, or nil.
function M.color(value)
  if type(value) ~= "table" then return nil end
  local r, g, b = value.r or value[1], value.g or value[2], value.b or value[3]
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
  if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
  return {r = number(r, 0, 1, 1), g = number(g, 0, 1, 1), b = number(b, 0, 1, 1)}
end

--- A key for one of the planet's own things: lower-case letters, digits and dashes.
local function key(value)
  if type(value) ~= "string" or not value:match("^[a-z0-9%-]+$") or #value > 24 then return nil end
  return value
end

--- A prototype name or "@..." reference (checked for existence later, by the loader).
local function ref(value)
  if type(value) ~= "string" or #value == 0 or #value > 200 or value:match("[%c]") then return nil end
  return value
end

--- A list of {name, amount} (also accepts {name = , amount = }).
local function amounts(value, problems, what)
  local out = {}
  for _, entry in ipairs(list(value)) do
    local name, amount
    if type(entry) == "table" then
      name, amount = entry.name or entry[1], entry.amount or entry[2]
    end
    name = ref(name)
    if name and #out < M.LIMITS.ingredients then
      out[#out + 1] = {name = name, amount = math.floor(number(amount, 1, 65535, 1))}
    elseif type(entry) ~= "table" or not name then
      problem(problems, "bad-entry", what)
    end
  end
  return out
end

local function technology_cost(raw, problems, defaults)
  raw = type(raw) == "table" and raw or {}
  local ingredients = amounts(raw.ingredients, problems, "technology cost")
  if #ingredients == 0 then ingredients = defaults.ingredients end
  return {
    count = math.floor(number(raw.count, 1, 1000000, defaults.count)),
    time = number(raw.time, 1, 600, defaults.time),
    ingredients = ingredients,
    infinite = raw.infinite == true,
  }
end

-- The planet ------------------------------------------------------------------------------------------------

--- Returns a clean planet table (or nil when it can't be used at all) and adds problems to the list.
function M.normalize(raw, problems)
  if type(raw) ~= "table" then
    problem(problems, "not-a-planet")
    return nil
  end
  local id = type(raw.id) == "string" and raw.id:match("^[a-z0-9]+$") and #raw.id >= 4 and #raw.id <= 16 and raw.id
  if not id then
    problem(problems, "bad-id", text(raw.name, M.LIMITS.name, "?"))
    return nil
  end
  local p = {
    id = id,
    name = text(raw.name, M.LIMITS.name, "Unnamed planet"),
    description = text(raw.description, M.LIMITS.description, nil),
    author = text(raw.author, M.LIMITS.author, nil),
  }

  -- "auto" picture: the vanilla planet closest in colour to the ground (see catalog.closest_picture);
  -- "auto" sky (lighting, colour grading, ambient sound): the home planet of most of the ground.
  local look = type(raw.look) == "table" and raw.look or {}
  p.look = {
    picture = M.PICTURES[look.picture] and look.picture or "auto",
    tint = M.color(look.tint),
    sky = M.PICTURES[look.sky] and look.sky or "auto",
  }

  local space = type(raw.space) == "table" and raw.space or {}
  p.space = {
    from = ref(space.from) or "nauvis",
    length = math.floor(number(space.length, 1000, 200000, 15000)),
    distance = number(space.distance, 1, 60, 20),
    orientation = number(space.orientation, 0, 1, 0.5) % 1,
    magnitude = number(space.magnitude, 0.3, 3, 1),
    asteroids = M.ASTEROIDS[space.asteroids] and space.asteroids or "nauvis_vulcanus",
  }

  local physics = type(raw.physics) == "table" and raw.physics or {}
  p.physics = {
    gravity = number(physics.gravity, 0.1, 100, 10),
    pressure = number(physics.pressure, 0, 10000, 1000),
    magnetic_field = number(physics.magnetic_field, 0, 1000, 90),
    solar_power = number(physics.solar_power, 0, 1000, 100),
    day_length = number(physics.day_length, 0.5, 120, 7), -- minutes
    freezing = physics.freezing == true, -- buildings need heat, like on Aquilo
    lightning = physics.lightning == true, -- lightning storms, like on Fulgora
  }

  local terrain = type(raw.terrain) == "table" and raw.terrain or {}
  p.terrain = {
    shape = catalog.SHAPES[terrain.shape] and terrain.shape or "lakes",
    liquid = catalog.LIQUIDS[terrain.liquid] and terrain.liquid or "water",
    liquid_amount = number(terrain.liquid_amount, 1 / 6, 6, 1),
    patch_size = number(terrain.patch_size, 0.25, 4, 1),
    decorations = terrain.decorations ~= false,
    ground = {},
  }
  -- ground: a list of {tile = name, share = n} (a plain tile name counts as share 1). Codes from 0.0.1 had
  -- `tiles` instead; they still work.
  for _, entry in ipairs(list(terrain.ground or terrain.tiles)) do
    local tile, share = entry, 1
    if type(entry) == "table" then tile, share = entry.tile or entry[1], entry.share or entry[2] end
    if ref(tile) and #p.terrain.ground < 12 then
      p.terrain.ground[#p.terrain.ground + 1] = {tile = tile, share = number(share, 0.1, 100, 1)}
    else
      problem(problems, "bad-entry", "ground tile")
    end
  end
  local function style_amount(value, styles, multi, default_style)
    value = type(value) == "table" and value or {}
    local out = {amount = number(value.amount, 0, 6, 1)}
    if multi then
      out.styles = {}
      for _, name in ipairs(list(value.styles)) do
        if styles[name] then out.styles[#out.styles + 1] = name end
      end
    else
      out.style = styles[value.style] ~= nil and value.style or default_style
    end
    return out
  end
  p.terrain.cliffs = style_amount(terrain.cliffs, catalog.CLIFFS, false, "none")
  p.terrain.plants = style_amount(terrain.plants, catalog.PLANTS, true)
  p.terrain.rocks = style_amount(terrain.rocks, catalog.ROCKS, true)

  local enemies = type(raw.enemies) == "table" and raw.enemies or {}
  p.enemies = {
    kind = catalog.ENEMIES[enemies.kind] and enemies.kind or "none",
    amount = number(enemies.amount, 1 / 6, 6, 1),
  }

  -- Ores first: resources and recipes refer to them.
  p.ores, p.ore_keys = {}, {}
  for _, ore in ipairs(list(raw.ores)) do
    local k = type(ore) == "table" and key(ore.key)
    if not k or p.ore_keys[k] then
      problem(problems, "bad-entry", "ore")
    else
      local o = {
        key = k,
        name = text(ore.name, M.LIMITS.name, "Ore"),
        tint = M.color(ore.tint) or {r = 1, g = 1, b = 1},
        base = M.ORE_BASES[ore.base] and ore.base or "iron-ore",
        mining_time = number(ore.mining_time, 0.1, 20, 1),
        stack_size = math.floor(number(ore.stack_size, 1, 1000, 50)),
      }
      p.ores[#p.ores + 1] = o
      p.ore_keys[k] = o
    end
  end

  p.resources = {}
  for _, res in ipairs(list(raw.resources)) do
    local name = type(res) == "table" and ref(res.resource)
    if not name then
      problem(problems, "bad-entry", "resource")
    else
      p.resources[#p.resources + 1] = {
        resource = name,
        frequency = number(res.frequency, 0.1, 6, 1),
        size = number(res.size, 0.1, 6, 1),
        richness = number(res.richness, 0.1, 6, 1),
        -- "yes" / "no" / "default" (default: solids get a patch near the landing spot, fluids don't)
        starting = res.starting == true and "yes" or res.starting == false and "no" or "default",
      }
    end
  end

  if type(raw.science) == "table" then
    local s = raw.science
    p.science = {
      name = text(s.name, M.LIMITS.name, p.name .. " science pack"),
      tint = M.color(s.tint) or {r = 1, g = 1, b = 1},
      base = ref(s.base) or "automation-science-pack",
      ingredients = amounts(s.ingredients, problems, "science pack recipe"),
      count = math.floor(number(s.count, 1, 100, 1)),
      time = number(s.time, 0.1, 600, 5),
      category = ref(s.category) or "crafting",
      only_here = s.only_here ~= false,
    }
  end

  p.discovery = technology_cost(raw.discovery, problems, {
    count = 1000, time = 60,
    ingredients = {
      {name = "automation-science-pack", amount = 1}, {name = "logistic-science-pack", amount = 1},
      {name = "chemical-science-pack", amount = 1}, {name = "space-science-pack", amount = 1},
    },
  })
  local dprereq = type(raw.discovery) == "table" and list(raw.discovery.prerequisites) or {}
  p.discovery.prerequisites = {}
  for _, name in ipairs(dprereq) do
    if ref(name) then p.discovery.prerequisites[#p.discovery.prerequisites + 1] = name end
  end
  if #p.discovery.prerequisites == 0 then p.discovery.prerequisites = {"space-platform-thruster"} end

  p.recipes, p.recipe_keys = {}, {}
  for _, r in ipairs(list(raw.recipes)) do
    local k = type(r) == "table" and key(r.key)
    if not k or p.recipe_keys[k] then
      problem(problems, "bad-entry", "recipe")
    else
      local recipe = {
        key = k,
        name = text(r.name, M.LIMITS.name, nil),
        ingredients = amounts(r.ingredients, problems, "recipe"),
        results = amounts(r.results, problems, "recipe"),
        time = number(r.time, 0.1, 600, 1),
        category = ref(r.category) or "crafting",
        only_here = r.only_here == true,
        enabled = r.enabled == true, -- true: known from the start, no research needed
      }
      p.recipes[#p.recipes + 1] = recipe
      p.recipe_keys[k] = recipe
    end
  end

  p.technologies, p.tech_keys = {}, {}
  for _, t in ipairs(list(raw.technologies)) do
    local k = type(t) == "table" and key(t.key)
    if not k or p.tech_keys[k] then
      problem(problems, "bad-entry", "technology")
    else
      local tech = technology_cost(t, problems, {
        count = 500, time = 30, ingredients = {{name = "@pack", amount = 1}},
      })
      tech.key = k
      tech.name = text(t.name, M.LIMITS.name, "Research")
      tech.description = text(t.description, M.LIMITS.description, nil)
      tech.icon = ref(t.icon)
      tech.prerequisites = {}
      for _, name in ipairs(list(t.prerequisites)) do
        if ref(name) then tech.prerequisites[#tech.prerequisites + 1] = name end
      end
      if #tech.prerequisites == 0 then tech.prerequisites = {"@discovery"} end
      tech.effects = {}
      for _, e in ipairs(list(t.effects)) do
        if type(e) == "table" and e.type == "unlock-recipe" and ref(e.recipe) then
          tech.effects[#tech.effects + 1] = {type = "unlock-recipe", recipe = e.recipe}
        elseif type(e) == "table" and e.type == "change-recipe-productivity" and ref(e.recipe) then
          tech.effects[#tech.effects + 1] = {type = e.type, recipe = e.recipe, change = number(e.change, -1, 10, 0.1)}
        elseif type(e) == "table" and M.MODIFIERS[e.type] then
          tech.effects[#tech.effects + 1] = {type = e.type, modifier = number(e.modifier, -10, 10, 0.1)}
        else
          problem(problems, "bad-entry", "technology effect")
        end
      end
      p.technologies[#p.technologies + 1] = tech
      p.tech_keys[k] = tech
    end
  end

  return p
end

return M
