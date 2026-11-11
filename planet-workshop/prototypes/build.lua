-- The loader: turns planets from codes into real prototypes (data stage only).
--
-- For each planet: the planet itself, its space route, its hidden "made here" surface property, its ores
-- (resource + item + map-gen control), its science pack (item + recipe), its recipes, its discovery
-- technology and its own technologies. Anything that refers to something missing (a tile or item from a mod
-- that isn't installed, a typo) is left out with a problem message instead of stopping the game from loading.
-- The problems and a summary of the loaded planets go to runtime in the "planet-workshop-report" mod-data.

local util = require("util")
local asteroid_util = require("__space-age__.prototypes.planet.asteroid-spawn-definitions")
local spec = require("__planet-workshop__.lib.spec")
local mapgen = require("__planet-workshop__.lib.mapgen")
local kitdefs = require("__planet-workshop__.prototypes.kit")

local M = {}

local MINUTE = 60 * 60 -- ticks

--- Every prototype type that is an item (an ingredient, result or pack can be any of these).
local ITEM_TYPES = {
  "item", "tool", "ammo", "capsule", "gun", "armor", "module", "repair-tool", "rail-planner",
  "item-with-entity-data", "item-with-label", "item-with-inventory", "item-with-tags", "selection-tool",
  "space-platform-starter-pack", "blueprint", "blueprint-book", "copy-paste-tool", "deconstruction-item",
  "upgrade-item", "spidertron-remote",
}

local PICTURE_TECH_ICON = {
  nauvis = {icon = "__base__/graphics/icons/starmap-planet-nauvis.png", icon_size = 512},
  vulcanus = {icon = "__space-age__/graphics/technology/vulcanus.png", icon_size = 256},
  gleba = {icon = "__space-age__/graphics/technology/gleba.png", icon_size = 256},
  fulgora = {icon = "__space-age__/graphics/technology/fulgora.png", icon_size = 256},
  aquilo = {icon = "__space-age__/graphics/technology/aquilo.png", icon_size = 256},
}

-- Small helpers ---------------------------------------------------------------------------------------------

local function find_item(name)
  for _, t in ipairs(ITEM_TYPES) do
    local proto = data.raw[t] and data.raw[t][name]
    if proto then return proto end
  end
  return nil
end

--- A whole-number hash of a text (for map seeds).
local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

--- The icons of a prototype as an icons list (handles both `icon` and `icons`).
local function icons_of(proto)
  if proto.icons then return util.table.deepcopy(proto.icons) end
  if proto.icon then return {{icon = proto.icon, icon_size = proto.icon_size or 64}} end
  return nil
end

--- The icons with a tint on every layer (layers that already have a tint keep theirs multiplied in).
local function tinted(icons, tint)
  if not icons or not tint then return icons end
  for _, layer in ipairs(icons) do
    local t = layer.tint
    if t then
      layer.tint = {r = (t.r or t[1] or 1) * tint.r, g = (t.g or t[2] or 1) * tint.g, b = (t.b or t[3] or 1) * tint.b,
        a = t.a or t[4] or 1}
    else
      layer.tint = {r = tint.r, g = tint.g, b = tint.b, a = 1}
    end
  end
  return icons
end

--- Puts a tint on every sprite in a graphics table (anything with a filename), in place.
local function tint_sprites(graphics, tint, seen)
  if type(graphics) ~= "table" then return end
  seen = seen or {}
  if seen[graphics] then return end
  seen[graphics] = true
  if graphics.filename or graphics.filenames then
    graphics.tint = {r = tint.r, g = tint.g, b = tint.b, a = 1}
  end
  for k, v in pairs(graphics) do
    if type(v) == "table" and k ~= "tint" then tint_sprites(v, tint, seen) end
  end
end

local function literal(text)
  return text and {"", text} or nil
end

-- One planet ------------------------------------------------------------------------------------------------

local Builder = {}
Builder.__index = Builder

function Builder:problem(key, ...)
  self.problems[#self.problems + 1] = {"planet-workshop-problem." .. key, self.p.name, ...}
end

function Builder:name(kind, key)
  local n = "pw-" .. self.p.id
  if kind then n = n .. "-" .. kind end
  if key then n = n .. "-" .. key end
  return n
end

--- An item or fluid reference -> {type = "item"|"fluid", name = prototype name}, or nil (with a problem).
function Builder:resolve_item(ref, where)
  if ref == "@pack" then
    if self.p.science then return {type = "item", name = self:name("pack")} end
  elseif ref:sub(1, 5) == "@ore:" then
    local ore = self.p.ore_keys[ref:sub(6)]
    if ore and ore.kind == "fluid" then return {type = "fluid", name = self:name("fluid", ref:sub(6))} end
    if ore then return {type = "item", name = self:name("ore", ref:sub(6))} end
  elseif ref:sub(1, 1) ~= "@" then
    if find_item(ref) then return {type = "item", name = ref} end
    if data.raw.fluid[ref] then return {type = "fluid", name = ref} end
  end
  self:problem("missing", ref, where)
  return nil
end

function Builder:resolve_recipe(ref, where)
  if ref == "@pack" then
    if self.p.science then return self:name("pack") end
  elseif ref:sub(1, 8) == "@recipe:" then
    if self.p.recipe_keys[ref:sub(9)] and self.built_recipes[ref:sub(9)] then return self:name("recipe", ref:sub(9)) end
  elseif ref:sub(1, 1) ~= "@" then
    if data.raw.recipe[ref] then return ref end
  end
  self:problem("missing", ref, where)
  return nil
end

function Builder:resolve_tech(ref, where)
  if ref == "@discovery" then return self:name("discovery") end
  if ref:sub(1, 6) == "@tech:" then
    if self.p.tech_keys[ref:sub(7)] then return self:name("tech", ref:sub(7)) end
  elseif ref:sub(1, 1) ~= "@" then
    if data.raw.technology[ref] then return ref end
  end
  self:problem("missing", ref, where)
  return nil
end

function Builder:ingredients(list, where, allow_fluids)
  local out = {}
  for _, entry in ipairs(list) do
    local r = self:resolve_item(entry.name, where)
    if r and (allow_fluids or r.type == "item") then
      out[#out + 1] = {type = r.type, name = r.name, amount = entry.amount}
    end
  end
  return out
end

--- Is an item a science pack some lab accepts (or this planet's own pack)?
local function lab_accepts(name)
  for _, lab in pairs(data.raw.lab or {}) do
    for _, input in ipairs(lab.inputs or {}) do
      if input == name then return true end
    end
  end
  return false
end

function Builder:tech_unit(cost, where)
  local ingredients = {}
  for _, entry in ipairs(cost.ingredients) do
    local r = self:resolve_item(entry.name, where)
    if r and r.type == "item" then
      if r.name == self:name("pack") or lab_accepts(r.name) then
        ingredients[#ingredients + 1] = {r.name, entry.amount}
      else
        self:problem("not-a-pack", r.name, where)
      end
    end
  end
  if #ingredients == 0 then
    ingredients = {{"automation-science-pack", 1}}
  end
  local unit = {ingredients = ingredients, time = cost.time}
  if cost.infinite then
    unit.count_formula = cost.count .. "*2^(L-1)"
  else
    unit.count = cost.count
  end
  return unit
end

function Builder:category(name)
  if data.raw["recipe-category"][name] then return name end
  self:problem("missing", name, "recipe category")
  return "crafting"
end

function Builder:surface_conditions(only_here)
  if not only_here then return nil end
  return {{property = self:name("here"), min = 1, max = 1}}
end

-- The parts -------------------------------------------------------------------------------------------------

function Builder:build_ores()
  for _, ore in ipairs(self.p.ores) do
    local name = self:name("ore", ore.key)
    local base_resource = data.raw.resource[ore.base]
    local res = util.table.deepcopy(base_resource)
    res.name = name
    res.localised_name = literal(ore.name)
    res.localised_description = nil
    res.factoriopedia_simulation = nil
    res.order = "z-pw-" .. self.p.id .. "-" .. ore.key
    res.icons = tinted(icons_of(base_resource), ore.tint)
    res.icon = nil
    res.map_color = {r = ore.tint.r, g = ore.tint.g, b = ore.tint.b}
    res.mining_visualisation_tint = {r = ore.tint.r, g = ore.tint.g, b = ore.tint.b, a = 1}
    res.minable = util.table.deepcopy(base_resource.minable)
    res.minable.mining_time = ore.mining_time
    res.minable.required_fluid = nil
    res.minable.fluid_amount = nil
    res.created_effect = nil -- (Space Age's wells make Aquilo snow around themselves; ours don't)
    tint_sprites(res.stages, ore.tint)
    tint_sprites(res.stages_effect, ore.tint)
    -- Placed only where a planet's map settings ask for it (lib/mapgen.lua), never by default.
    res.autoplace = {order = "b", probability_expression = 0, richness_expression = 0}

    if ore.kind == "fluid" then
      -- a well or vent that gives the planet's own fluid
      local fluid_name = self:name("fluid", ore.key)
      local fluid = util.table.deepcopy(data.raw.fluid[spec.FLUID_BASES[ore.base]])
      fluid.name = fluid_name
      fluid.localised_name = literal(ore.name)
      fluid.localised_description = nil
      fluid.icons = tinted(icons_of(fluid), ore.tint)
      fluid.icon = nil
      fluid.base_color = {r = ore.tint.r * 0.6, g = ore.tint.g * 0.6, b = ore.tint.b * 0.6}
      fluid.flow_color = {r = ore.tint.r, g = ore.tint.g, b = ore.tint.b}
      fluid.order = "z-pw-" .. self.p.id .. "-" .. ore.key
      fluid.factoriopedia_simulation = nil
      fluid.auto_barrel = false
      res.minable.result = nil
      res.minable.results = {{type = "fluid", name = fluid_name, amount_min = 10, amount_max = 10}}
      data:extend{res, fluid}
    else
      local base_item = data.raw.item[ore.base]
      res.minable.result = name
      res.minable.results = nil
      local item = util.table.deepcopy(base_item)
      item.name = name
      item.localised_name = literal(ore.name)
      item.localised_description = nil
      item.icons = tinted(icons_of(base_item), ore.tint)
      item.icon = nil
      item.order = "z-pw-" .. self.p.id .. "-" .. ore.key
      item.stack_size = ore.stack_size
      item.factoriopedia_simulation = nil
      if item.pictures then tint_sprites(item.pictures, ore.tint) end
      data:extend{res, item}
    end
  end
end

function Builder:build_science()
  local s = self.p.science
  if not s then return end
  local base = find_item(s.base)
  if not base then
    self:problem("missing", s.base, "science pack look")
    base = data.raw.item["automation-science-pack"] or find_item("automation-science-pack")
  end
  local name = self:name("pack")
  local item = util.table.deepcopy(base)
  item.name = name
  item.localised_name = literal(s.name)
  item.localised_description = {"item-description.science-pack"}
  item.icons = tinted(icons_of(base), s.tint)
  item.icon = nil
  item.subgroup = "science-pack"
  item.order = "z[pw-" .. self.p.id .. "]"
  item.factoriopedia_simulation = nil
  if item.pictures then tint_sprites(item.pictures, s.tint) end
  if s.spoil_minutes > 0 then -- spoils like Gleba's agricultural science pack
    item.spoil_ticks = math.floor(s.spoil_minutes * 3600)
    item.spoil_result = data.raw.item.spoilage and "spoilage" or nil
  end

  local results = {{type = "item", name = name, amount = s.count}}
  data:extend{
    item,
    {
      type = "recipe",
      name = name,
      localised_name = literal(s.name),
      categories = {self:category(s.category)},
      enabled = false,
      energy_required = s.time,
      ingredients = self:ingredients(s.ingredients, "science pack recipe", true),
      results = results,
      allow_productivity = true,
      surface_conditions = self:surface_conditions(s.only_here),
    },
  }
  self.unlocked_by_discovery[#self.unlocked_by_discovery + 1] = name
end

function Builder:build_recipes()
  for _, r in ipairs(self.p.recipes) do
    local results = self:ingredients(r.results, "recipe result", true)
    if #results == 0 then
      self:problem("no-results", r.name or r.key)
    else
      local name = self:name("recipe", r.key)
      data:extend{{
        type = "recipe",
        name = name,
        localised_name = literal(r.name),
        categories = {self:category(r.category)},
        enabled = r.enabled,
        energy_required = r.time,
        ingredients = self:ingredients(r.ingredients, "recipe", true),
        results = results,
        main_product = results[1].name,
        allow_productivity = true,
        surface_conditions = self:surface_conditions(r.only_here),
      }}
      self.built_recipes[r.key] = true
    end
  end
end

function Builder:build_technologies()
  local unlocked = {}
  for _, t in ipairs(self.p.technologies) do
    local effects = {}
    for _, e in ipairs(t.effects) do
      if e.type == "unlock-recipe" then
        local recipe = self:resolve_recipe(e.recipe, "technology reward")
        if recipe then
          effects[#effects + 1] = {type = "unlock-recipe", recipe = recipe}
          unlocked[recipe] = true
        end
      elseif e.type == "change-recipe-productivity" then
        local recipe = self:resolve_recipe(e.recipe, "technology reward")
        if recipe then effects[#effects + 1] = {type = e.type, recipe = recipe, change = e.change} end
      else
        effects[#effects + 1] = {type = e.type, modifier = e.modifier}
      end
    end
    local prerequisites = {}
    for _, ref in ipairs(t.prerequisites) do
      local tech = self:resolve_tech(ref, "technology prerequisite")
      if tech and tech ~= self:name("tech", t.key) then prerequisites[#prerequisites + 1] = tech end
    end
    if #prerequisites == 0 then prerequisites = {self:name("discovery")} end

    local icons
    if t.icon then
      local item = t.icon:sub(1, 1) == "@" and self:resolve_item(t.icon, "technology icon")
      local proto = item and find_item(item.name) or (t.icon:sub(1, 1) ~= "@" and
        (data.raw.technology[t.icon] or find_item(t.icon) or data.raw.fluid[t.icon]))
      icons = proto and icons_of(proto)
    end
    if not icons then
      icons = tinted({util.table.deepcopy(PICTURE_TECH_ICON[self.picture])}, self.p.look.tint)
    end

    data:extend{{
      type = "technology",
      name = self:name("tech", t.key),
      localised_name = literal(t.name),
      localised_description = literal(t.description),
      icons = icons,
      effects = effects,
      prerequisites = prerequisites,
      unit = self:tech_unit(t, "technology cost"),
      max_level = t.infinite and "infinite" or nil,
      upgrade = t.infinite or nil,
    }}
  end
  -- Recipes that no technology unlocks (and aren't known from the start) come with the discovery.
  for _, r in ipairs(self.p.recipes) do
    local name = self:name("recipe", r.key)
    if self.built_recipes[r.key] and not r.enabled and not unlocked[name] then
      self.unlocked_by_discovery[#self.unlocked_by_discovery + 1] = name
    end
  end
end

function Builder:build_discovery()
  local d = self.p.discovery
  local effects = {{type = "unlock-space-location", space_location = self:name(), use_icon_overlay_constant = true}}
  for _, recipe in ipairs(self.unlocked_by_discovery) do
    effects[#effects + 1] = {type = "unlock-recipe", recipe = recipe}
  end
  local prerequisites = {}
  for _, ref in ipairs(d.prerequisites) do
    local tech = ref:sub(1, 1) ~= "@" and self:resolve_tech(ref, "discovery prerequisite")
    if tech then prerequisites[#prerequisites + 1] = tech end
  end
  if #prerequisites == 0 and data.raw.technology["space-platform-thruster"] then
    prerequisites = {"space-platform-thruster"}
  end
  local pic = util.table.deepcopy(PICTURE_TECH_ICON[self.picture])
  local icons = tinted({pic}, self.p.look.tint)
  icons[#icons + 1] = {
    icon = "__core__/graphics/icons/technology/constants/constant-planet.png",
    icon_size = 128, scale = 0.5 * pic.icon_size / 256, shift = {50 * pic.icon_size / 256, 50 * pic.icon_size / 256},
    floating = true,
  }
  data:extend{{
    type = "technology",
    name = self:name("discovery"),
    localised_name = {"planet-workshop.discovery", self.p.name},
    localised_description = literal(self.p.description),
    icons = icons,
    essential = true,
    effects = effects,
    prerequisites = prerequisites,
    unit = self:tech_unit(d, "discovery cost"),
  }}
end

-- What exists in this game, for lib/mapgen.lua (the designer has a runtime version of this).
local tile_home, reference_colors
function Builder:lookup()
  if not tile_home then tile_home, reference_colors = kitdefs.planet_info() end
  return {
    tile = function(name)
      local t = data.raw.tile[name]
      return t and {autoplace = t.autoplace ~= nil, color = t.map_color, fluid = t.fluid ~= nil} or nil
    end,
    tile_home = function(name) return tile_home[name] end,
    reference_colors = reference_colors,
    resource = function(name)
      local r = data.raw.resource[name]
      return r and {fluid = (r.category or ""):find("fluid") ~= nil, autoplace = r.autoplace ~= nil} or nil
    end,
    entity = function(name) return kitdefs.entity_exists(name) ~= nil end,
    cliff = function(name) return data.raw.cliff ~= nil and data.raw.cliff[name] ~= nil end,
    decoratives = kitdefs.planet_decoratives,
    pollutant = function(name) return data.raw["airborne-pollutant"] ~= nil and data.raw["airborne-pollutant"][name] ~= nil end,
    style_entities = kitdefs.style_entities,
    ore_entity = function(key) return self:name("ore", key) end,
  }
end

function Builder:build_planet()
  local p = self.p
  local made = mapgen.build(p, self:lookup(), function(key, ...) self:problem(key, ...) end)
  self.picture, self.sky, self.starting = made.picture, made.sky, made.starting
  local mgs = made.mgs
  local base = data.raw.planet[self.picture]
  local enemy_fields = {pollutant_type = made.pollutant}
  local planet = util.table.deepcopy(base)
  local sky = data.raw.planet[self.sky] or base
  planet.surface_render_parameters = util.table.deepcopy(sky.surface_render_parameters)
  planet.persistent_ambient_sounds = util.table.deepcopy(sky.persistent_ambient_sounds)
  planet.name = self:name()
  planet.localised_name = literal(p.name)
  planet.localised_description = literal(p.description)
  planet.icons = tinted(icons_of(base), p.look.tint)
  planet.icon = nil
  planet.starmap_icons = tinted({{icon = base.starmap_icon, icon_size = base.starmap_icon_size or 512}}, p.look.tint)
  planet.starmap_icon = nil
  planet.distance = p.space.distance
  planet.orientation = p.space.orientation
  planet.magnitude = p.space.magnitude
  planet.label_orientation = nil
  planet.order = "z[pw-" .. p.id .. "]"
  planet.subgroup = "planets"
  planet.map_seed_offset = hash(p.id)
  planet.map_gen_settings = mgs
  planet.pollutant_type = enemy_fields.pollutant_type
  planet.entities_require_heating = p.physics.freezing or nil
  planet.lightning_properties = p.physics.lightning and data.raw.planet.fulgora and
    util.table.deepcopy(data.raw.planet.fulgora.lightning_properties) or nil
  planet.player_effects = nil
  planet.ticks_between_player_effects = nil
  planet.factoriopedia_simulation = nil
  planet.surface_properties = {
    gravity = p.physics.gravity,
    pressure = p.physics.pressure,
    ["magnetic-field"] = p.physics.magnetic_field,
    ["solar-power"] = p.physics.solar_power,
    ["day-night-cycle"] = p.physics.day_length * MINUTE,
    [self:name("here")] = 1,
  }
  planet.asteroid_spawn_influence = 1
  planet.asteroid_spawn_definitions = asteroid_util.spawn_definitions(asteroid_util[p.space.asteroids], 0.9)

  local from = p.space.from
  if not (data.raw.planet[from] or data.raw["space-location"][from]) then
    self:problem("missing", from, "space route")
    from = "nauvis"
  end
  -- The route's icon: Space Age's route arrow with the two planets (Space Age adds these in its data-updates,
  -- which has already run, so new routes need their own).
  local route_icons = {{icon = "__space-age__/graphics/icons/planet-route.png"}}
  local from_proto = data.raw.planet[from] or data.raw["space-location"][from]
  for i, proto in ipairs{from_proto, planet} do
    local layer = icons_of(proto)
    layer = layer and layer[1]
    if layer then
      local size = layer.icon_size or 64
      layer.scale = 0.333 * (64 / size)
      layer.shift = i == 1 and {-6, -6} or {6, 6}
      route_icons[#route_icons + 1] = layer
    end
  end
  data:extend{
    {
      type = "surface-property",
      name = self:name("here"),
      localised_name = {"planet-workshop.here-property", p.name},
      default_value = 0,
      order = "z[pw-" .. p.id .. "]",
    },
    planet,
    {
      type = "space-connection",
      name = self:name("route"),
      subgroup = "planet-connections",
      from = from,
      to = self:name(),
      order = "z[pw-" .. p.id .. "]",
      length = p.space.length,
      icons = route_icons,
      asteroid_spawn_definitions = asteroid_util.spawn_definitions(asteroid_util[p.space.asteroids]),
    },
  }
end

-- All planets -----------------------------------------------------------------------------------------------

--- Builds every planet in the list (the output of codes.read_all) and returns a report for runtime.
function M.build_all(found, problems)
  local report = {planets = {}, problems = problems}
  local seen = {}
  for _, entry in ipairs(found) do
    local p = spec.normalize(entry.planet, problems)
    if p and seen[p.id] then
      problems[#problems + 1] = {"planet-workshop-problem.duplicate", p.name}
    elseif p then
      seen[p.id] = true
      local b = setmetatable({p = p, problems = problems, unlocked_by_discovery = {}, built_recipes = {}}, Builder)
      b:build_ores()
      b:build_planet()
      b:build_science()
      b:build_recipes()
      b:build_technologies()
      b:build_discovery()
      report.planets[#report.planets + 1] = {
        id = p.id, name = p.name, author = p.author, planet = b:name(), discovery = b:name("discovery"),
        pack = p.science and b:name("pack") or nil, code = entry.code, picture = b.picture, sky = b.sky,
        starting = b.starting,
      }
    end
  end
  return report
end

return M
