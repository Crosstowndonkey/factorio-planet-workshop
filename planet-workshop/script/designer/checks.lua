-- The designer's checks: what's wrong with a planet, or could make it hard or impossible to play. Each check is
-- {level = "problem" | "warning" | "note", message = LocalisedString, section = the designer section to fix it in}.
--   problem  something in the planet can't be used as it is (the loader would skip it): from lib/spec.lua and
--            lib/mapgen.lua, the same messages players see when they load the code
--   warning  it loads, but players could get stuck (no rocket silo, an ore that never generates...)
--   note     worth knowing, often on purpose (no water, a pack that no research uses...)
-- Runtime only (it looks at what exists in this game: items, recipes, buildings and their surface conditions).

local preview = require("__planet-workshop__.script.designer.preview")

local M = {}

local function L(key, ...) return {"planet-workshop-check." .. key, ...} end

M.LEVELS = {"problem", "warning", "note"}

--- True if `conditions` (a prototype's surface_conditions) are met with these properties.
function M.conditions_met(conditions, props)
  for _, c in ipairs(conditions or {}) do
    local value = props[c.property]
    if value == nil then
      local proto = prototypes.surface_property[c.property]
      value = proto and proto.default_value or 0
    end
    if (c.min and value < c.min) or (c.max and value > c.max) then return false end
  end
  return true
end

-- What exists in the game (worked out once) -----------------------------------------------------------------

local cache

--- Buildings with surface conditions, and recipe categories that some machine can make with fluids.
local function game_info()
  if cache then return cache end
  cache = {buildings = {}, fluid_categories = {}}
  -- (only buildings that can be built on some planet: space-platform-only ones, like thrusters, don't count)
  local planets = {}
  for name, planet in pairs(prototypes.space_location) do
    if planet.type == "planet" and name:sub(1, 3) ~= "pw-" and planet.surface_properties then
      planets[#planets + 1] = planet.surface_properties
    end
  end
  local seen = {}
  for _, item in pairs(prototypes.item) do
    local e = item.place_result
    if e and not seen[e.name] and not item.hidden and e.surface_conditions and #e.surface_conditions > 0 then
      seen[e.name] = true
      for _, props in ipairs(planets) do
        if M.conditions_met(e.surface_conditions, props) then
          cache.buildings[#cache.buildings + 1] = e
          break
        end
      end
    end
  end
  table.sort(cache.buildings, function(a, b) return a.name < b.name end)
  for _, e in pairs(prototypes.get_entity_filtered{{filter = "crafting-machine"}}) do
    if #e.fluidbox_prototypes > 0 then
      for category in pairs(e.crafting_categories or {}) do cache.fluid_categories[category] = true end
    end
  end
  return cache
end

--- The planet's surface properties, as the loader gives them (prototypes/build.lua).
function M.surface_properties(p)
  return {
    gravity = p.physics.gravity,
    pressure = p.physics.pressure,
    ["magnetic-field"] = p.physics.magnetic_field,
    ["solar-power"] = p.physics.solar_power,
    ["day-night-cycle"] = p.physics.day_length * 3600,
    ["pw-" .. p.id .. "-here"] = 1,
  }
end

-- Reading the planet's references ----------------------------------------------------------------------------

local function own_ore(p, ref)
  return type(ref) == "string" and ref:sub(1, 5) == "@ore:" and p.ore_keys[ref:sub(6)] or nil
end

--- A name for a reference, for messages.
local function describe(p, ref)
  if ref == "@pack" then return p.science and p.science.name or {"planet-workshop-check.the-pack"} end
  if ref == "@discovery" then return {"planet-workshop-check.the-discovery"} end
  local kind, key = (ref or ""):match("^@(%a+):(.+)$")
  if kind == "ore" then return p.ore_keys[key] and p.ore_keys[key].name or key end
  if kind == "recipe" then return p.recipe_keys[key] and (p.recipe_keys[key].name or key) or key end
  if kind == "tech" then return p.tech_keys[key] and p.tech_keys[key].name or key end
  for _, group in ipairs{prototypes.item, prototypes.fluid, prototypes.recipe, prototypes.technology} do
    if group[ref] then return group[ref].localised_name end
  end
  return ref or "?"
end

--- Is a reference of this kind ("thing", "pack", "recipe", "tech") to something that exists?
local function exists(p, ref, kind)
  if ref == "@pack" then return p.science ~= nil end
  if ref == "@discovery" then return kind == "tech" end
  local own, key = (ref or ""):match("^@(%a+):(.+)$")
  if own == "ore" then return kind == "thing" and p.ore_keys[key] ~= nil end
  if own == "recipe" then return kind == "recipe" and p.recipe_keys[key] ~= nil end
  if own == "tech" then return kind == "tech" and p.tech_keys[key] ~= nil end
  if kind == "thing" then return prototypes.item[ref] ~= nil or prototypes.fluid[ref] ~= nil end
  if kind == "pack" then return prototypes.item[ref] ~= nil end
  if kind == "recipe" then return prototypes.recipe[ref] ~= nil end
  if kind == "tech" then return prototypes.technology[ref] ~= nil end
  return false
end

local function is_fluid(p, ref)
  local ore = own_ore(p, ref)
  if ore then return ore.kind == "fluid" end
  return type(ref) == "string" and ref:sub(1, 1) ~= "@" and prototypes.fluid[ref] ~= nil and prototypes.item[ref] == nil
end

-- The checks -----------------------------------------------------------------------------------------------------

--- All checks for a design; `ps` is the player's designer state (for what the preview found).
function M.run(design, ps)
  local out = {}
  local function add(level, section, message) out[#out + 1] = {level = level, section = section, message = message} end

  local p, made, problems = preview.evaluate(design, preview.seed(design, ps))
  for _, problem in ipairs(problems) do add("problem", nil, problem) end
  if not p then return out end

  -- Leaving again: rockets need a silo, and getting things down needs a landing pad.
  local props = M.surface_properties(p)
  local silo = prototypes.entity["rocket-silo"]
  if silo and not M.conditions_met(silo.surface_conditions, props) then
    add("warning", "physics", L("no-rocket-silo"))
  end
  local pad = prototypes.entity["cargo-landing-pad"]
  if pad and not M.conditions_met(pad.surface_conditions, props) then
    add("warning", "physics", L("no-landing-pad"))
  end
  local cant = {}
  for _, e in ipairs(game_info().buildings) do
    if e.name ~= "rocket-silo" and e.name ~= "cargo-landing-pad" and not M.conditions_met(e.surface_conditions, props) then
      cant[#cant + 1] = e.localised_name
    end
  end
  if #cant > 0 then
    local list = {""}
    for i = 1, math.min(#cant, 5) do
      if i > 1 then list[#list + 1] = ", " end
      list[#list + 1] = cant[i]
    end
    if #cant > 5 then list[#list + 1] = {"planet-workshop-check.and-more", #cant - 5} end
    add("note", "physics", L("cant-build", list))
  end

  -- Resources
  if #p.resources == 0 then
    add("warning", "resources", L("no-resources"))
  elseif made and #made.starting == 0 then
    add("note", "resources", L("no-starting"))
  end
  local generated = {}
  for _, res in ipairs(p.resources) do generated[res.resource] = true end
  for _, ore in ipairs(p.ores) do
    if not generated["@ore:" .. ore.key] then add("warning", "resources", L("ore-not-generated", ore.name)) end
  end
  for _, entity in ipairs(ps.placed or {}) do
    local proto = prototypes.entity[entity]
    add("note", "resources", L("start-patch-added", proto and proto.localised_name or entity))
  end

  -- A starting planet: what a new game needs to get going and get to space (from Nauvis's usual start)
  if p.starting_planet then
    local have = {}
    for _, res in ipairs(p.resources) do have[res.resource] = res end
    local trees = false
    for _, style in ipairs(p.terrain.plants.styles) do
      if style == "forest" or style == "dry-trees" then trees = true end
    end
    for _, need in ipairs{"iron-ore", "copper-ore", "stone", "coal", "crude-oil"} do
      local proto = prototypes.entity[need]
      local name = proto and proto.localised_name or need
      if not have[need] then
        if need == "coal" and trees then
          add("note", "resources", L("start-wood-only"))
        else
          add("warning", "resources", L(need == "crude-oil" and "start-needs-oil" or "start-needs", name))
        end
      elseif have[need].starting == "no" and need ~= "crude-oil" then
        add("warning", "resources", L("start-not-near", name))
      end
    end
    if p.physics.pressure < 10 then add("warning", "physics", L("start-burner")) end
    if p.physics.freezing then add("warning", "physics", L("start-freezing")) end
    if p.physics.lightning then add("warning", "physics", L("start-lightning")) end
  end

  -- Liquid and enemies
  local water = false
  local liquid = ({water = "water", lava = "lava", oil = "oil-ocean-shallow", ammonia = "ammoniacal-ocean",
    slime = "wetland-light-green-slime"})[p.terrain.liquid]
  local tile = liquid and prototypes.tile[liquid]
  if tile and tile.fluid and tile.fluid.name == "water" then water = true end
  if not water then
    if p.starting_planet then add("warning", "terrain", L("start-needs-water")) else add("note", "terrain", L("no-water")) end
  end
  if p.enemies.kind == "pentapods" and p.terrain.liquid ~= "slime" then
    add("warning", "enemies", L("pentapods-need-slime"))
  end

  -- References to things that don't exist (any more)
  local function ref_ok(ref, kind, where, section)
    if not exists(p, ref, kind) then add("warning", section, L("missing-ref", where, describe(p, ref))) end
  end
  local function fluid_ok(name, list_of_lists, category, section)
    local fluid = false
    for _, list in ipairs(list_of_lists) do
      for _, entry in ipairs(list) do if is_fluid(p, entry.name) then fluid = true end end
    end
    if fluid and not game_info().fluid_categories[category] then
      add("warning", section, L("fluid-needs-machine", name))
    end
  end
  if p.science then
    local s = p.science
    for _, entry in ipairs(s.ingredients) do ref_ok(entry.name, "thing", s.name, "science") end
    if #s.ingredients == 0 then add("note", "science", L("free-recipe", s.name)) end
    fluid_ok(s.name, {s.ingredients}, s.category, "science")
  end
  for _, r in ipairs(p.recipes) do
    local name = r.name or r.key
    for _, entry in ipairs(r.ingredients) do ref_ok(entry.name, "thing", name, "recipes") end
    for _, entry in ipairs(r.results) do ref_ok(entry.name, "thing", name, "recipes") end
    if #r.results == 0 then add("warning", "recipes", L("makes-nothing", name)) end
    if #r.ingredients == 0 then add("note", "recipes", L("free-recipe", name)) end
    fluid_ok(name, {r.ingredients, r.results}, r.category, "recipes")
  end
  local pack_used = false
  local function cost_ok(t, name)
    for _, entry in ipairs(t.ingredients) do
      if entry.name == "@pack" then pack_used = true end
      ref_ok(entry.name, "pack", name, "research")
    end
  end
  cost_ok(p.discovery, {"planet-workshop-check.the-discovery"})
  for _, ref in ipairs(p.discovery.prerequisites) do
    ref_ok(ref, "tech", {"planet-workshop-check.the-discovery"}, "research")
  end
  for _, t in ipairs(p.technologies) do
    cost_ok(t, t.name)
    for _, ref in ipairs(t.prerequisites) do ref_ok(ref, "tech", t.name, "research") end
    for _, e in ipairs(t.effects) do
      if e.recipe then ref_ok(e.recipe, "recipe", t.name, "research") end
    end
    if #t.effects == 0 then add("note", "research", L("no-rewards", t.name)) end
  end
  if p.science and not pack_used then add("note", "research", L("pack-unused", p.science.name)) end

  -- Hand-made start area: things in it that don't exist in this game
  if p.start then
    local missing = {}
    for _, name in ipairs(p.start.palette) do
      if not prototypes.tile[name] then missing[name] = true end
    end
    for _, t in ipairs(p.start.add) do
      local own = t.name:match("^@ore:(.+)$")
      if (own and not p.ore_keys[own]) or (not own and not prototypes.entity[t.name]) then missing[t.name] = true end
    end
    local names = {}
    for name in pairs(missing) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do add("warning", "start", L("start-missing", describe(p, name))) end
  end

  -- Research that can never start: technologies that need each other
  local needs = {["@discovery"] = p.discovery.prerequisites}
  for _, t in ipairs(p.technologies) do needs["@tech:" .. t.key] = t.prerequisites end
  local function reaches(from, target, seen)
    for _, ref in ipairs(needs[from] or {}) do
      if ref == target then return true end
      if needs[ref] and not seen[ref] then
        seen[ref] = true
        if reaches(ref, target, seen) then return true end
      end
    end
    return false
  end
  local looped = {}
  for node in pairs(needs) do
    if reaches(node, node, {}) then looped[node] = true end
  end
  local loop_names = {""}
  local nodes = {}
  for node in pairs(looped) do nodes[#nodes + 1] = node end
  table.sort(nodes)
  for i, node in ipairs(nodes) do
    if i > 1 then loop_names[#loop_names + 1] = ", " end
    loop_names[#loop_names + 1] = describe(p, node)
  end
  if #nodes > 0 then add("warning", "research", L("research-loop", loop_names)) end

  -- problems first, then warnings, then notes (each kept in the order found)
  local sorted = {}
  for _, level in ipairs(M.LEVELS) do
    for _, c in ipairs(out) do if c.level == level then sorted[#sorted + 1] = c end end
  end
  return sorted
end

--- How many checks of each level: {problem = n, warning = n, note = n}.
function M.count(list)
  local n = {problem = 0, warning = 0, note = 0}
  for _, c in ipairs(list) do n[c.level] = n[c.level] + 1 end
  return n
end

return M
