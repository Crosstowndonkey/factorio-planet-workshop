-- Test harness for Planet Workshop (not part of the mod). Run with --test-save and --test-arg <suite>
-- (tools/run_tests.sh does it). Suites:
--   bridge  the test codes (eight planets, a broken code, a too-new code) loaded into a new game: prototypes,
--           Brimstone's world, research, and real assemblers for "made only here"
--   terrain every test planet's generated world: shapes, ground shares, liquids, cliffs, plants, rocks, enemies,
--           picture and sky, and starting resources on several seeds
--   designer the Planet Designer: its window and controls, the preview, codes, import, and that the preview
--           uses exactly the map settings the finished planet gets
--   added   the same codes added to a save that was made without them
--   codec   codes made in game with helpers.encode_string read back by the mod's own decoder
--   startarea a hand-made start area made in the map editor (water, ores, own ore brush, taken away, Cancel)
--   sameworld the preview and a planet surface on the same seed are identical (start areas rely on it)
--   testplay the designer's checks (warnings for unplayable planets) and test play: landing as a character with
--           the planet's physics, coming back, dying
local codes = require("__planet-workshop__.lib.codes")
local json = require("__planet-workshop__.lib.json")
local base64 = require("__planet-workshop__.lib.base64")
local inflate = require("__planet-workshop__.lib.inflate")

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then passed = passed + 1 else failed = failed + 1 end
  print("STA " .. (ok and "PASS " or "FAIL ") .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
end
local function info(text) print("STA INFO " .. text) end

local B, F = "pw-brim0001", "pw-frost002"

local function report() return prototypes.mod_data["planet-workshop-report"].data end

local function find_problem(key, planet, thing)
  for _, p in ipairs(report().problems) do
    if p[1] == "planet-workshop-problem." .. key and (planet == nil or p[2] == planet) and (thing == nil or p[3] == thing) then
      return true
    end
  end
  return false
end

local function has_effect(tech, kind, value)
  for _, e in ipairs(prototypes.technology[tech].effects) do
    if e.type == kind and (e.recipe == value or e.space_location == value) then return true end
  end
  return false
end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function generate(surface, radius)
  surface.request_to_generate_chunks({0, 0}, radius)
  surface.force_generate_chunk_requests()
end

-- bridge ----------------------------------------------------------------------------------------------------

local function test_prototypes()
  local r = report()
  check("all eight test planets loaded from the codes", #r.planets == 8, #r.planets)
  for _, p in ipairs(r.problems) do info("problem: " .. serpent.line(p)) end
  check("the broken code is reported, not a crash", find_problem("unreadable"))
  check("the too-new code is reported", find_problem("newer-format"))
  local brim_problems = 0
  for _, p in ipairs(r.problems) do
    if p[2] == "Brimstone" then brim_problems = brim_problems + 1 end
  end
  check("Brimstone loads with no problems", brim_problems == 0, brim_problems)

  local planet = prototypes.space_location[B]
  check("Brimstone is a planet", planet and planet.type == "planet")
  check("Brimstone is on the star map", game.planets[B] ~= nil)
  check("Brimstone's name comes from the code", planet and planet.localised_name[2] == "Brimstone",
    planet and serpent.line(planet.localised_name))
  local route = prototypes.space_connection[B .. "-route"]
  check("a space route from Nauvis", route and route.from.name == "nauvis" and route.to.name == B)
  check("route length from the code", route and route.length == 12000, route and route.length)

  local ore = B .. "-ore-sulfite"
  check("the custom ore exists", prototypes.entity[ore] and prototypes.entity[ore].type == "resource")
  check("the custom ore item exists", prototypes.item[ore] ~= nil)
  check("the ore mines into its own item", prototypes.entity[ore] and
    prototypes.entity[ore].mineable_properties.products[1].name == ore)
  -- each resource takes a slot of the terrain kit; the planet's map settings hold its amounts
  local controls = planet and planet.map_gen_settings.autoplace_controls or {}
  check("the ore has a kit resource slot (size 1.5 from the code)", controls["pw-k-res-s1"] and
    math.abs(controls["pw-k-res-s1"].size - 1.5) < 0.01, serpent.line(controls["pw-k-res-s1"]))
  check("vanilla iron has the next slot (iron is denser: size 1.25)", controls["pw-k-res-s2"] and
    math.abs(controls["pw-k-res-s2"].size - 1.25) < 0.01, serpent.line(controls["pw-k-res-s2"]))
  check("crude oil has a fluid slot", controls["pw-k-res-g1"] ~= nil)

  local pack = B .. "-pack"
  check("the science pack exists", prototypes.item[pack] ~= nil)
  local recipe = prototypes.recipe[pack]
  local ing = {}
  for _, i in ipairs(recipe and recipe.ingredients or {}) do ing[i.name] = i.amount end
  check("pack recipe = 5 sulfite + 2 iron plates", ing[ore] == 5 and ing["iron-plate"] == 2, serpent.line(ing))
  local cond = recipe and recipe.surface_conditions
  check("pack can only be made on Brimstone", cond and cond[1].property == B .. "-here" and cond[1].min == 1,
    serpent.line(cond))
  for _, lab in ipairs{"lab", "biolab"} do
    local takes = false
    for _, input in ipairs(prototypes.entity[lab].lab_inputs) do
      if input == pack then takes = true end
    end
    check("the " .. lab .. " takes the pack", takes)
  end

  local disc = B .. "-discovery"
  check("discovery technology exists", prototypes.technology[disc] ~= nil)
  check("discovery unlocks the planet", has_effect(disc, "unlock-space-location", B))
  check("discovery unlocks the pack recipe", has_effect(disc, "unlock-recipe", pack))
  check("discovery unlocks the smelting recipe (no tech unlocks it)", has_effect(disc, "unlock-recipe", B .. "-recipe-smelt"))
  check("discovery does not unlock the acid recipe (a tech does)", not has_effect(disc, "unlock-recipe", B .. "-recipe-acid"))
  check("discovery needs space platform thrusters", prototypes.technology[disc].prerequisites["space-platform-thruster"] ~= nil)
  check("planet tech unlocks the acid recipe", has_effect(B .. "-tech-acid", "unlock-recipe", B .. "-recipe-acid"))
  local prod = prototypes.technology[B .. "-tech-prod"]
  check("infinite tech is infinite", prod and prod.max_level == 4294967295, prod and prod.max_level)
  check("infinite tech needs the acid tech", prod and prod.prerequisites[B .. "-tech-acid"] ~= nil)
  local cost = {}
  for _, i in ipairs(prod and prod.research_unit_ingredients or {}) do cost[i.name] = i.amount end
  check("infinite tech costs the pack + space science", cost[pack] == 1 and cost["space-science-pack"] == 1, serpent.line(cost))
  check("acid recipe is only for Brimstone", prototypes.recipe[B .. "-recipe-acid"].surface_conditions ~= nil)
  check("smelting recipe works anywhere", prototypes.recipe[B .. "-recipe-smelt"].surface_conditions == nil)

  -- Glacier: its own fluid resource, a pack made from it that spoils, a recipe using the fluid
  local G = "pw-glac0003"
  check("glacier: its own fluid exists", prototypes.fluid[G .. "-fluid-cryo"] ~= nil)
  local well = prototypes.entity[G .. "-ore-cryo"]
  check("glacier: its well gives that fluid", well and well.mineable_properties.products[1].type == "fluid" and
    well.mineable_properties.products[1].name == G .. "-fluid-cryo", well and serpent.line(well.mineable_properties.products))
  local gpack = prototypes.recipe[G .. "-pack"]
  local fluid_in = false
  for _, i in ipairs(gpack and gpack.ingredients or {}) do
    if i.type == "fluid" and i.name == G .. "-fluid-cryo" then fluid_in = true end
  end
  check("glacier: the pack recipe uses the fluid", fluid_in)
  check("glacier: the pack spoils (30 minutes)", prototypes.item[G .. "-pack"].get_spoil_ticks() == 30 * 3600,
    prototypes.item[G .. "-pack"].get_spoil_ticks())
  check("glacier: brine freezing recipe", prototypes.recipe[G .. "-recipe-freeze"] ~= nil)

  -- Frostbite: full of mistakes, each left out
  check("Frostbite still loads", prototypes.space_location[F] ~= nil)
  check("missing tile reported", find_problem("missing", "Frostbite", "snow-made-up"))
  check("missing resource reported", find_problem("missing", "Frostbite", "unobtainium-ore"))
  check("missing own ore reported", find_problem("missing", "Frostbite", "@ore:nope"))
  check("missing ingredient reported", find_problem("missing", "Frostbite", "unobtainium"))
  check("missing technology reported", find_problem("missing", "Frostbite", "no-such-tech"))
  check("missing pack look reported", find_problem("missing", "Frostbite", "no-such-pack"))
  check("missing route start reported", find_problem("missing", "Frostbite", "no-such-planet"))
  check("non-pack research cost reported", find_problem("not-a-pack", "Frostbite", "iron-plate"))
  check("recipe that makes nothing reported", find_problem("no-results", "Frostbite"))
  check("broken entries reported", find_problem("bad-entry"))
  check("the recipe that makes nothing is left out", prototypes.recipe[F .. "-recipe-nothing"] == nil)
  local froute = prototypes.space_connection[F .. "-route"]
  check("route falls back to Nauvis", froute and froute.from.name == "nauvis")
  check("too-long route is capped", froute and froute.length == 200000, froute and froute.length)
  local fpack = prototypes.recipe[F .. "-pack"]
  check("Frostbite pack keeps its good ingredient", fpack and #fpack.ingredients == 1 and fpack.ingredients[1].name == "copper-plate")
  local fdisc = prototypes.technology[F .. "-discovery"]
  check("bad discovery prerequisite falls back to thrusters", fdisc and fdisc.prerequisites["space-platform-thruster"] ~= nil)
  check("Frostbite discovery costs only real packs", fdisc and #fdisc.research_unit_ingredients == 1)
  local t1 = prototypes.technology[F .. "-tech-t1"]
  check("Frostbite tech made without bad parts", t1 and #t1.effects == 0 and t1.prerequisites[F .. "-discovery"] ~= nil)
end

local function test_world()
  local f = game.forces.player
  local s = game.planets[B].create_surface()
  generate(s, 5)
  local area = {{-160, -160}, {160, 160}}
  local total = s.count_tiles_filtered{area = area}
  local allowed = {"red-desert-0", "sand-1", "water", "deepwater"}
  local good = s.count_tiles_filtered{area = area, name = allowed}
  check("Brimstone's ground is only the chosen tiles", total > 0 and good == total, good .. "/" .. total)
  info("water tiles near the start: " .. s.count_tiles_filtered{area = area, name = {"water", "deepwater"}})
  local ore = B .. "-ore-sulfite"
  -- Ore placement near the landing spot varies with the seed (step 1 will guarantee starting ores), so this
  -- checks a wider area and logs the distances.
  generate(s, 12)
  local sulfite = s.count_entities_filtered{name = ore}
  check("sulfite ore generated", sulfite > 0, sulfite)
  local function nearest(name)
    local best = math.huge
    for _, e in pairs(s.find_entities_filtered{name = name, area = {{-400, -400}, {400, 400}}}) do
      best = math.min(best, math.sqrt(e.position.x ^ 2 + e.position.y ^ 2))
    end
    return best == math.huge and "none" or math.floor(best)
  end
  info("nearest sulfite " .. nearest(ore) .. " tiles from the landing spot, nearest iron " .. nearest("iron-ore") ..
    " (seed " .. s.map_gen_settings.seed .. ")")
  check("iron ore generated", s.count_entities_filtered{name = "iron-ore"} > 0)
  check("no copper (not chosen)", s.count_entities_filtered{name = "copper-ore"} == 0)
  check("no enemies", s.count_entities_filtered{force = "enemy"} == 0)
  check("gravity from the code", s.get_property("gravity") == 12, s.get_property("gravity"))
  check("pressure from the code", s.get_property("pressure") == 1500)
  check("the 'made here' property is set", s.get_property(B .. "-here") == 1)
  check("day length from the code (4 minutes)", s.ticks_per_day == 4 * 3600, s.ticks_per_day)

  local n = game.surfaces.nauvis
  generate(n, 3)
  check("Nauvis has no sulfite ore", n.count_entities_filtered{name = ore} == 0)
  check("Nauvis isn't 'here'", n.get_property(B .. "-here") == 0)

  f.technologies[B .. "-discovery"].researched = true
  check("researching the discovery unlocks the planet", f.is_space_location_unlocked(B))
  check("...and the pack recipe", f.recipes[B .. "-pack"].enabled)

  -- A powered assembler with the ingredients on each surface; after 15 seconds only Brimstone's has made packs.
  local function machine(surface)
    local pos = surface.find_non_colliding_position("assembling-machine-2", {0, 0}, 80, 4)
    local a = surface.create_entity{name = "assembling-machine-2", position = pos, force = f, recipe = B .. "-pack"}
    local eei = surface.create_entity{name = "electric-energy-interface", position = {pos.x + 3, pos.y}, force = f}
    eei.power_production = 1e9 / 60
    eei.electric_buffer_size = 1e10
    surface.create_entity{name = "substation", position = {pos.x, pos.y + 3}, force = f}
    a.insert{name = ore, count = 50}
    a.insert{name = "iron-plate", count = 20}
    return a
  end
  local here, nauvis = machine(s), machine(n)
  return 900, function()
    check("the pack is made on Brimstone", here.products_finished > 0, here.products_finished)
    check("the pack is not made on Nauvis", nauvis.products_finished == 0,
      nauvis.products_finished .. " made, status " .. tostring(nauvis.status))
  end
end

-- terrain ---------------------------------------------------------------------------------------------------

local catalog = require("__planet-workshop__.lib.catalog")

local function count(s, filter) return s.count_entities_filtered(filter) end

local function nearest(s, name, radius)
  local best = math.huge
  for _, e in pairs(s.find_entities_filtered{name = name, area = {{-radius, -radius}, {radius, radius}}}) do
    best = math.min(best, math.sqrt(e.position.x ^ 2 + e.position.y ^ 2))
  end
  return best
end

local function share_of(s, area, tile, others)
  local a = s.count_tiles_filtered{area = area, name = tile}
  local all = s.count_tiles_filtered{area = area, name = others}
  return all > 0 and a / all or 0
end

local function planet_surface(id, radius)
  local s = game.planets["pw-" .. id].create_surface()
  generate(s, radius)
  return s
end

local function test_terrain()
  local area = {{-320, -320}, {320, 320}}
  local r = report()
  local looks = {}
  for _, planet in ipairs(r.planets) do looks[planet.id] = planet end
  local function look(id, picture, sky)
    check(id .. ": picture " .. picture, looks[id].picture == picture, looks[id].picture)
    check(id .. ": sky " .. sky, looks[id].sky == sky, looks[id].sky)
  end
  look("brim0001", "nauvis", "nauvis")
  look("glac0003", "aquilo", "aquilo")
  look("cind0004", "vulcanus", "vulcanus")
  look("verd0005", "nauvis", "nauvis")
  look("bloo0006", "gleba", "gleba")
  look("dust0007", "fulgora", "fulgora")
  check("frostbite: chosen picture kept", looks["frost002"].picture == "aquilo")
  -- colour matching on its own (used when no planet owns most of the ground)
  local refs = {nauvis = {0.345, 0.29, 0.198}, vulcanus = {0.354, 0.234, 0.179}, gleba = {0.326, 0.258, 0.199},
    fulgora = {0.398, 0.264, 0.224}, aquilo = {0.454, 0.508, 0.58}}
  check("colour match: snow white is aquilo", catalog.closest_picture({0.75, 0.76, 0.77}, refs) == "aquilo")

  -- Brimstone: lakes, red desert 3 : sand 1, dry trees, rocks, Nauvis cliffs
  local s = planet_surface("brim0001", 10)
  local land = {"red-desert-0", "sand-1"}
  local red = share_of(s, area, "red-desert-0", land)
  check("brimstone: red desert is about 3/4 of the land", red > 0.6 and red < 0.9, string.format("%.2f", red))
  check("brimstone: dry trees grow", count(s, {name = catalog.PLANTS["dry-trees"]}) > 0, count(s, {name = catalog.PLANTS["dry-trees"]}))
  check("brimstone: no forest trees", count(s, {name = catalog.PLANTS.forest}) == 0)
  check("brimstone: rocks", count(s, {name = catalog.ROCKS.rocks}) > 0, count(s, {name = catalog.ROCKS.rocks}))
  check("brimstone: cliffs", count(s, {type = "cliff"}) > 0, count(s, {type = "cliff"}))
  generate(s, 18) -- oil has no starting patch; regular patches start about 450 tiles out
  if count(s, {name = "crude-oil"}) == 0 then generate(s, 28) end -- (on some map seeds the first is further)
  check("brimstone: crude oil further out", count(s, {name = "crude-oil"}) > 0)
  check("brimstone: oil wells don't bring snow", s.count_tiles_filtered{name = {"snow-flat", "snow-lumpy",
    "snow-patchy", "ice-rough"}} == 0)
  check("brimstone: no pollution type (no enemies)", prototypes.space_location["pw-brim0001"].pollutant_type == nil)

  -- Glacier: archipelago in ammonia, snow 2 : ice 1, icebergs, freezing
  s = planet_surface("glac0003", 10)
  local liquid = s.count_tiles_filtered{area = area, name = {"ammoniacal-ocean", "ammoniacal-ocean-2"}}
  local total = s.count_tiles_filtered{area = area}
  info(string.format("glacier: %.0f%% ammonia ocean", 100 * liquid / total))
  check("glacier: ammonia sea between the islands", liquid / total > 0.1 and liquid / total < 0.9)
  local odd = {}
  for _, tile in pairs(s.find_tiles_filtered{area = area, limit = 100,
    -- (Space Age's lithium brine and fluorine vents make lumpy/patchy snow and rough ice around themselves)
    name = {"snow-flat", "ice-smooth", "ammoniacal-ocean", "ammoniacal-ocean-2", "snow-lumpy", "snow-patchy",
      "ice-rough"}, invert = true}) do
    odd[tile.name] = (odd[tile.name] or 0) + 1
  end
  check("glacier: only snow, ice and ammonia", next(odd) == nil, serpent.line(odd))
  local snow = share_of(s, area, "snow-flat", {"snow-flat", "ice-smooth"})
  check("glacier: snow is about 2/3 of the land", snow > 0.5 and snow < 0.82, string.format("%.2f", snow))
  check("glacier: icebergs", count(s, {name = catalog.ROCKS.icebergs}) > 0, count(s, {name = catalog.ROCKS.icebergs}))
  check("glacier: buildings need heating", prototypes.space_location["pw-glac0003"].entities_require_heating == true)
  check("glacier: no cliffs (none chosen)", count(s, {type = "cliff"}) == 0)

  -- Cinder: continents in lava, Vulcanus cliffs, lichen, volcanic rocks, demolishers
  s = planet_surface("cind0004", 12)
  local lava = s.count_tiles_filtered{area = area, name = {"lava", "lava-hot"}}
  info(string.format("cinder: %.0f%% lava", 100 * lava / s.count_tiles_filtered{area = area}))
  check("cinder: lava", lava > 0)
  check("cinder: vulcanus cliffs", count(s, {name = "cliff-vulcanus"}) > 0, count(s, {name = "cliff-vulcanus"}))
  check("cinder: lichen trees", count(s, {name = catalog.PLANTS.lichen}) > 0)
  check("cinder: volcanic rocks", count(s, {name = catalog.ROCKS["volcanic-rocks"]}) > 0)
  check("cinder: tungsten", count(s, {name = "tungsten-ore"}) > 0)
  local territories = #s.get_territories()
  check("cinder: demolisher territories", territories > 0, territories)
  info("cinder: demolishers alive in the generated area: " .. count(s, {type = "segmented-unit"}))

  -- Verdant: island, forests, biters
  s = planet_surface("verd0005", 12)
  check("verdant: forests", count(s, {name = catalog.PLANTS.forest}) > 100, count(s, {name = catalog.PLANTS.forest}))
  local spawners = count(s, {type = "unit-spawner"})
  check("verdant: biter nests", spawners > 0, spawners)
  check("verdant: no nests near the landing spot", nearest(s, "biter-spawner", 400) > 100, nearest(s, "biter-spawner", 400))
  check("verdant: pollution draws attacks", prototypes.space_location["pw-verd0005"].pollutant_type.name == "pollution")
  check("verdant: fish in the water", count(s, {name = "fish"}) > 0)
  check("verdant: decorations", #s.find_decoratives_filtered{area = {{-100, -100}, {100, 100}}} > 0)
  check("verdant: no cliffs (none chosen)", count(s, {type = "cliff"}) == 0)

  -- Bloom: slime lakes, gleba plants, stromatolites, pentapods
  s = planet_surface("bloo0006", 18) -- nests start 300-400 tiles out
  check("bloom: slime", s.count_tiles_filtered{area = area, name = {"wetland-light-green-slime", "gleba-deep-lake"}} > 0)
  check("bloom: gleba plants", count(s, {name = catalog.PLANTS["gleba-plants"]}) > 0)
  check("bloom: stromatolites", count(s, {name = catalog.ROCKS.stromatolites}) > 0)
  local pods = count(s, {name = {"gleba-spawner", "gleba-spawner-small"}})
  check("bloom: pentapod nests (in the swamps)", pods > 0, pods)
  check("bloom: spores draw attacks", prototypes.space_location["pw-bloo0006"].pollutant_type.name == "spores")

  -- Dustbowl: no liquid at all, ruins, scrap
  s = planet_surface("dust0007", 8)
  total = s.count_tiles_filtered{area = {{-256, -256}, {256, 256}}}
  check("dustbowl: no liquid, only its two ground tiles", s.count_tiles_filtered{area = {{-256, -256}, {256, 256}},
    name = {"fulgoran-sand", "fulgoran-dunes"}} == total)
  check("dustbowl: ruins", count(s, {name = catalog.ROCKS.ruins}) > 0, count(s, {name = catalog.ROCKS.ruins}))
  check("dustbowl: scrap", count(s, {name = "scrap"}) > 0)

  -- Pond: our continents shape on a water planet always has a starting pond near the landing spot
  local farthest = 0
  for seed = 1, 4 do
    local mgs = game.planets["pw-pond0008"].create_surface().map_gen_settings
    mgs.seed = seed * 104729
    local test = game.create_surface("pond-seed-" .. seed, mgs)
    generate(test, 3)
    local water = test.find_tiles_filtered{area = {{-96, -96}, {96, 96}}, name = {"water", "deepwater"}}
    local best = math.huge
    for _, tile in pairs(water) do
      best = math.min(best, math.sqrt(tile.position.x ^ 2 + tile.position.y ^ 2))
    end
    farthest = math.max(farthest, best)
    game.delete_surface(test)
  end
  check("pond: water within 80 tiles of the landing spot on 4 seeds", farthest <= 80,
    farthest == math.huge and "none" or math.floor(farthest))

  -- The safety net on a very unlucky seed: no starting geysers or iron anywhere near the landing spot
  local mgs = game.planets["pw-cind0004"].surface.map_gen_settings
  mgs.seed = 31337
  local unlucky = game.create_surface("unlucky", mgs)
  generate(unlucky, 8)
  for _, e in pairs(unlucky.find_entities_filtered{name = {"sulfuric-acid-geyser", "coal"}, area = {{-260, -260}, {260, 260}}}) do
    e.destroy()
  end
  local placed = remote.call("planet-workshop", "ensure_start", unlucky.index, "pw-cind0004")
  check("safety net: places the missing geyser and coal", #placed == 2, serpent.line(placed))
  local wells = unlucky.find_entities_filtered{name = "sulfuric-acid-geyser", area = {{-200, -200}, {200, 200}}}
  check("safety net: a cluster of geysers near the landing spot", #wells >= 3, #wells)
  local wet = 0
  for _, e in pairs(unlucky.find_entities_filtered{name = {"sulfuric-acid-geyser", "coal"}, area = {{-200, -200}, {200, 200}}}) do
    if unlucky.get_tile(e.position.x, e.position.y).prototype.fluid then wet = wet + 1 end
  end
  check("safety net: nothing placed in lava", wet == 0, wet)
  check("safety net: a coal patch near the landing spot", nearest(unlucky, "coal", 200) <= 200)
  check("safety net: does nothing when all is there", #remote.call("planet-workshop", "ensure_start", unlucky.index,
    "pw-cind0004") == 0)
  game.delete_surface(unlucky)

  -- Starting resources on several seeds (with the safety net): all within 200 tiles of the landing spot (fluids:
  -- sparse wells and vents)
  for _, case in ipairs{
    {"brim0001", {"pw-brim0001-ore-sulfite", "iron-ore", "stone"}},
    {"verd0005", {"iron-ore", "copper-ore", "coal", "stone"}},
    {"cind0004", {"tungsten-ore", "calcite", "coal"}, {"sulfuric-acid-geyser"}},
    {"glac0003", {"iron-ore", "copper-ore"}, {"fluorine-vent", "pw-glac0003-ore-cryo"}},
  } do
    local worst, worst_name, worst_fluid, worst_fluid_name = 0, "", 0, ""
    for seed = 1, 4 do
      local mgs = game.planets["pw-" .. case[1]].surface.map_gen_settings
      mgs.seed = seed * 7919
      local test = game.create_surface(case[1] .. "-seed-" .. seed, mgs)
      generate(test, case[3] and 10 or 7)
      -- the safety net, as on a first visit (these test surfaces aren't the planet's own, so call it directly)
      local placed = remote.call("planet-workshop", "ensure_start", test.index, "pw-" .. case[1])
      if #placed > 0 then info(case[1] .. " seed " .. seed .. ": the safety net placed " .. table.concat(placed, ", ")) end
      for _, name in ipairs(case[2]) do
        local d = nearest(test, name, 224)
        if d > worst then worst, worst_name = d, name end
      end
      for _, name in ipairs(case[3] or {}) do
        local d = nearest(test, name, 320)
        if d > worst_fluid then worst_fluid, worst_fluid_name = d, name end
      end
      game.delete_surface(test)
    end
    local function show(d, name) return name .. " " .. (d == math.huge and "none" or math.floor(d)) end
    check(case[1] .. ": starting ores within 200 tiles on 4 seeds", worst <= 200, "farthest: " .. show(worst, worst_name))
    if case[3] then
      check(case[1] .. ": starting wells/vents within 200 tiles on 4 seeds", worst_fluid <= 200,
        "farthest: " .. show(worst_fluid, worst_fluid_name))
    end
  end
end

-- designer ----------------------------------------------------------------------------------------------------

local function R(name, ...) return remote.call("planet-workshop", name, ...) end
local spec = require("__planet-workshop__.lib.spec")

local function index_of_value(list, value)
  for i, v in ipairs(list) do if v == value then return i end end
  return 1
end

--- Finds a GUI element by its tags (depth first).
local function find(el, test)
  if el.tags and test(el.tags, el) then return el end
  for _, child in ipairs(el.children) do
    local found = find(child, test)
    if found then return found end
  end
  return nil
end

local function root(player) return player.gui.screen.pw_designer end

local function test_designer()
  local player = game.players[1]
  check("there is a player to design with", player ~= nil)
  R("start_designer")
  check("the designer window opens", root(player) ~= nil)
  check("the player flies freely (no body)", player.controller_type == defines.controllers.god)
  local designs = R("designer_designs")
  check("a blank planet to start from", #designs == 1 and designs[1].terrain.ground[1].tile == "sand-1")
  check("a fresh planet id", type(designs[1].id) == "string" and #designs[1].id == 8, designs[1].id)
  local surface = game.surfaces["pw-preview-" .. player.index]
  check("a preview surface", surface ~= nil)
  check("the preview camera is in the window", root(player) and root(player).body.right.camera ~= nil)

  -- every tab builds
  for tab = 1, 15 do
    local ok, err = pcall(R, "designer_tab", player.index, tab)
    check("tab " .. tab .. " builds", ok, err)
  end

  -- use the real controls: shape dropdown, liquid, a ground tile, a slider
  R("designer_tab", player.index, 2)
  local shape = find(root(player), function(t) return t.pw == "pick" and t.path == "terrain.shape" end)
  shape.selected_index = 5 -- continents
  R("designer_event", "on_gui_selection_state_changed", {element = shape, player_index = player.index})
  local liquid = find(root(player), function(t) return t.pw == "pick" and t.path == "terrain.liquid" end)
  liquid.selected_index = 2 -- lava
  R("designer_event", "on_gui_selection_state_changed", {element = liquid, player_index = player.index})
  local tile = find(root(player), function(t) return t.pw == "elem" and t.path == "terrain.ground.1.tile" end)
  tile.elem_value = "volcanic-ash-dark"
  R("designer_event", "on_gui_elem_changed", {element = tile, player_index = player.index})
  local add = find(root(player), function(t) return t.pw == "add-ground" end)
  R("designer_event", "on_gui_click", {element = add, player_index = player.index})
  local share = find(root(player), function(t) return t.pw == "number" and t.path == "terrain.ground.1.share" end)
  share.slider_value = 3
  R("designer_event", "on_gui_value_changed", {element = share, player_index = player.index})
  local d = R("designer_designs")[1]
  check("the controls change the planet", d.terrain.shape == "continents" and d.terrain.liquid == "lava" and
    d.terrain.ground[1].tile == "volcanic-ash-dark" and d.terrain.ground[1].share == 3 and #d.terrain.ground == 2,
    serpent.line(d.terrain))
  check("the slider's label follows it", share.parent.pw_value.caption[2] == "3")

  -- a resource, through the resources tab
  R("designer_tab", player.index, 4)
  local pick = find(root(player), function(t) return t.pw == "add-resource" end)
  pick.elem_value = "iron-ore"
  R("designer_event", "on_gui_elem_changed", {element = pick, player_index = player.index})
  check("a resource added", #R("designer_designs")[1].resources == 1)

  local second = R("designer_designs")[1].terrain.ground[2].tile
  return 600, function()
    local s = game.surfaces["pw-preview-" .. player.index]
    local area = {{-160, -160}, {160, 160}}
    local total = s.count_tiles_filtered{area = area}
    local chosen = s.count_tiles_filtered{area = area, name = {"volcanic-ash-dark", second, "lava", "lava-hot"}}
    check("the preview shows the new ground and lava", total > 0 and chosen == total, chosen .. "/" .. total)
    check("the preview has lava", s.count_tiles_filtered{area = area, name = {"lava", "lava-hot"}} > 0)
    check("the preview has iron near the start", s.count_entities_filtered{name = "iron-ore", area = area} > 0)
    local ash = s.count_tiles_filtered{area = area, name = "volcanic-ash-dark"}
    local other = s.count_tiles_filtered{area = area, name = second}
    info(string.format("preview: ash %.0f%% of the land (share 3 of 4 -> about 75%%)", 100 * ash / math.max(1, ash + other)))

    -- the code holds the planet exactly
    local code = R("designer_code", player.index)
    local pack = codes.decode_body(code:sub(5))
    local design = R("designer_designs")[1]
    check("Get code makes a code that reads back as the same planet", pack and same(pack.planets[1], design),
      pack and serpent.line(pack.planets[1].terrain))
    local count = R("designer_import", player.index, "junk with no code")
    check("importing junk adds nothing", count == 0 and #R("designer_designs") == 1)

    -- the preview uses exactly the map settings the loader gives the finished planet
    local n = R("designer_import", player.index, settings.startup["planet-workshop-planets"].value)
    check("importing the test codes adds their planets", n == 8 and #R("designer_designs") == 9, n)
    for i, design in ipairs(R("designer_designs")) do
      if design.id == "glac0003" then
        local dd = find(root(player), function(t) return t.pw == "select-design" end)
        dd.selected_index = i
        R("designer_event", "on_gui_selection_state_changed", {element = dd, player_index = player.index})
      end
    end
    local planet_mgs = prototypes.space_location["pw-glac0003"].map_gen_settings
    local preview_mgs = game.surfaces["pw-preview-" .. player.index].map_gen_settings
    -- (the planet's own ores show as stand-ins in the preview: count them as the same thing)
    local function own(k) return (k:gsub("pw%-glac0003%-ore%-[%w%-]+", "OWN"):gsub("pw%-k%-ore%-[%w%-]+%-%d+", "OWN")) end
    local function keys(t) local r = {} for k in pairs(t or {}) do r[#r + 1] = own(k) end table.sort(r) return table.concat(r, ",") end
    check("preview and planet: same property rules", keys(planet_mgs.property_expression_names) ==
      keys(preview_mgs.property_expression_names))
    local same_values = true
    local preview_props = {}
    for k, v in pairs(preview_mgs.property_expression_names) do preview_props[own(k)] = v end
    for k, v in pairs(planet_mgs.property_expression_names) do
      if preview_props[own(k)] ~= v then same_values = false end
    end
    check("preview and planet: same rule for each property", same_values)
    check("preview and planet: same tiles", keys(planet_mgs.autoplace_settings.tile.settings) ==
      keys(preview_mgs.autoplace_settings.tile.settings))
    check("preview and planet: same entities", keys(planet_mgs.autoplace_settings.entity.settings) ==
      keys(preview_mgs.autoplace_settings.entity.settings))
    local same_controls = true
    for k, v in pairs(planet_mgs.autoplace_controls) do
      local w = preview_mgs.autoplace_controls[k]
      if not w or math.abs(w.size - v.size) > 0.001 or math.abs(w.frequency - v.frequency) > 0.001 then
        same_controls = false
      end
    end
    check("preview and planet: same control values", same_controls)

    -- new, copy, delete (delete needs two clicks)
    R("designer_do", player.index, "new")
    check("New adds a blank planet", #R("designer_designs") == 10)
    R("designer_do", player.index, "copy")
    local all = R("designer_designs")
    check("Copy adds a copy with its own id", #all == 11 and all[11].id ~= all[10].id and all[11].name:find("copy"))
    R("designer_do", player.index, "delete")
    check("one click doesn't delete", #R("designer_designs") == 11)
    R("designer_do", player.index, "delete")
    check("the second click deletes", #R("designer_designs") == 10)
    R("designer_do", player.index, "walk")
    check("Fly around takes the player to the preview", player.surface.name == "pw-preview-" .. player.index)
    R("designer_do", player.index, "walk")
    check("...and back", player.surface.name == "nauvis")
    local ok = pcall(R, "designer_do", player.index, "get-code")
    check("the code window opens", ok and player.gui.screen.pw_designer_code ~= nil)

    -- Production, through the real controls: a planet with its own ore and fluid, pack, recipe and research
    R("designer_do", player.index, "new")
    R("designer_set", player.index, "name", "Roundtrip")
    for _, section in ipairs{"ores", "science", "recipes", "research"} do
      local built, err = pcall(R, "designer_tab", player.index, section)
      check("production section " .. section .. " builds (empty)", built, err)
    end
    R("designer_tab", player.index, "ores")
    R("designer_do", player.index, "add-ore", {kind = "solid"})
    R("designer_do", player.index, "add-ore", {kind = "fluid"})
    local name_field = find(root(player), function(t) return t.pw == "text" and t.path == "ores.1.name" end)
    name_field.text = "Glowstone"
    R("designer_event", "on_gui_text_changed", {element = name_field, player_index = player.index})
    local fluid_look = find(root(player), function(t) return t.pw == "pick" and t.path == "ores.2.base" end)
    fluid_look.selected_index = index_of_value(fluid_look.tags.values, "sulfuric-acid-geyser")
    R("designer_event", "on_gui_selection_state_changed", {element = fluid_look, player_index = player.index})
    local design = R("designer_designs")[#R("designer_designs")]
    check("own ore and fluid added, and to the resources", #design.ores == 2 and #design.resources == 2 and
      design.resources[1].resource == "@ore:ore1" and design.ores[1].name == "Glowstone" and
      design.ores[2].base == "sulfuric-acid-geyser", serpent.line(design.ores))

    R("designer_tab", player.index, "science")
    local on = find(root(player), function(t) return t.pw == "science-on" end)
    on.state = true
    R("designer_event", "on_gui_checked_state_changed", {element = on, player_index = player.index})
    local source = find(root(player), function(t) return t.pw == "ref-source" and t.path == "science.ingredients.1.name" end)
    source.selected_index = 2 -- the planet's own ore
    R("designer_event", "on_gui_selection_state_changed", {element = source, player_index = player.index})
    local spoil = find(root(player), function(t) return t.pw == "number" and t.path == "science.spoil_minutes" end)
    spoil.slider_value = 30
    R("designer_event", "on_gui_value_changed", {element = spoil, player_index = player.index})

    R("designer_tab", player.index, "recipes")
    R("designer_do", player.index, "add-recipe")
    source = find(root(player), function(t) return t.pw == "ref-source" and t.path == "recipes.1.ingredients.1.name" end)
    source.selected_index = 3 -- the planet's own fluid
    R("designer_event", "on_gui_selection_state_changed", {element = source, player_index = player.index})
    local category = find(root(player), function(t) return t.pw == "pick" and t.path == "recipes.1.category" end)
    category.selected_index = index_of_value(category.tags.values, "chemistry")
    R("designer_event", "on_gui_selection_state_changed", {element = category, player_index = player.index})
    local count = find(root(player), function(t) return t.pw == "num" and t.path == "recipes.1.results.1.amount" end)
    count.text = "3"
    R("designer_event", "on_gui_text_changed", {element = count, player_index = player.index})

    R("designer_tab", player.index, "research")
    R("designer_do", player.index, "add-technology")
    local add_reward = find(root(player), function(t) return t.pw == "add" and t.path == "technologies.1.effects" end)
    R("designer_event", "on_gui_click", {element = add_reward, player_index = player.index})
    source = find(root(player), function(t) return t.pw == "ref-source" and t.path == "technologies.1.effects.1.recipe" end)
    source.selected_index = 3 -- the planet's own recipe (after the pack recipe)
    R("designer_event", "on_gui_selection_state_changed", {element = source, player_index = player.index})
    local add_reward2 = find(root(player), function(t) return t.pw == "add" and t.path == "technologies.1.effects" end)
    R("designer_event", "on_gui_click", {element = add_reward2, player_index = player.index})
    local kind = find(root(player), function(t) return t.pw == "effect-type" and t.path == "technologies.1.effects.2" end)
    kind.selected_index = 3 -- mining productivity
    R("designer_event", "on_gui_selection_state_changed", {element = kind, player_index = player.index})
    local bonus = find(root(player), function(t) return t.pw == "num" and t.path == "technologies.1.effects.2.modifier" end)
    bonus.text = "15"
    R("designer_event", "on_gui_text_changed", {element = bonus, player_index = player.index})

    design = R("designer_designs")[#R("designer_designs")]
    local problems = {}
    local p = spec.normalize(design, problems)
    check("the designed planet has no problems", p and #problems == 0, serpent.line(problems))
    check("pack made from the own ore, spoils in 30 min", p.science and p.science.ingredients[1].name == "@ore:ore1" and
      p.science.spoil_minutes == 30, p.science and serpent.line(p.science.ingredients))
    check("recipe made from the own fluid, in a chemical plant, makes 3", p.recipes[1].ingredients[1].name == "@ore:fluid1" and
      p.recipes[1].category == "chemistry" and p.recipes[1].results[1].amount == 3, serpent.line(p.recipes[1]))
    local e = p.technologies[1] and p.technologies[1].effects or {}
    check("research unlocks the recipe and gives +15% mining productivity", e[1] and e[1].type == "unlock-recipe" and
      e[1].recipe == "@recipe:recipe1" and e[2] and e[2].type == "mining-drill-productivity-bonus" and
      math.abs(e[2].modifier - 0.15) < 0.001, serpent.line(e))
    R("designer_preview_now", player.index)
    local mgs = game.surfaces["pw-preview-" .. player.index].map_gen_settings
    check("the preview shows the own ore as an iron-ore stand-in",
      mgs.autoplace_settings.entity.settings["pw-k-ore-iron-ore-1"] ~= nil)
    for _, section in ipairs{"ores", "science", "recipes", "research"} do
      local built, err = pcall(R, "designer_tab", player.index, section)
      check("production section " .. section .. " builds (filled in)", built, err)
    end
    -- the code for the roundtrip suite (Get code also saves it to script-output/planet-workshop)
    R("designer_do", player.index, "get-code")
  end
end

-- testplay: checks and test play ----------------------------------------------------------------------------------

local function has_check(list, key, level)
  for _, c in ipairs(list) do
    if c.message[1] == "planet-workshop-check." .. key and (level == nil or c.level == level) then return true end
  end
  return false
end

local function check_keys(list)
  local keys = {}
  for _, c in ipairs(list) do keys[#keys + 1] = c.level .. ":" .. tostring(c.message[1]):gsub("^planet%-workshop%-", "") end
  return table.concat(keys, " ")
end

local function test_testplay()
  local player = game.players[1]
  local P = player.index
  R("start_designer")
  local list = R("designer_checks", P)
  check("a blank planet: warned that it has no resources", has_check(list, "no-resources", "warning"), check_keys(list))
  check("a blank planet: no problems", #list > 0 and list[1].level ~= "problem", check_keys(list))
  check("a blank planet: every building can be built (space-only ones don't count)", not has_check(list, "cant-build"),
    check_keys(list))

  -- an unplayable planet
  R("designer_set", P, "enemies.kind", "pentapods")
  R("designer_set", P, "physics.pressure", 0)
  R("designer_set", P, "terrain.liquid", "lava")
  R("designer_do", P, "add-ore", {kind = "solid"})
  R("designer_set", P, "resources", {})
  R("designer_set", P, "recipes", {
    {key = "r1", name = "Nothing", ingredients = {{name = "iron-plate", amount = 1}}, results = {}, category = "crafting", time = 1},
    {key = "r2", name = "Hot soup", ingredients = {{name = "water", amount = 10}}, results = {{name = "iron-plate", amount = 1}},
      category = "smelting", time = 1},
    {key = "r3", name = "Ghost", ingredients = {{name = "@ore:gone", amount = 1}}, results = {{name = "iron-plate", amount = 1}},
      category = "crafting", time = 1},
  })
  R("designer_set", P, "technologies", {
    {key = "a", name = "Chicken", prerequisites = {"@tech:b"}, count = 10, time = 10, ingredients = {{name = "automation-science-pack", amount = 1}}, effects = {}},
    {key = "b", name = "Egg", prerequisites = {"@tech:a"}, count = 10, time = 10, ingredients = {{name = "automation-science-pack", amount = 1}}, effects = {}},
  })
  R("designer_set", P, "science", {name = "Odd pack", ingredients = {{name = "@ore:ore1", amount = 1}}, count = 1, time = 5,
    category = "crafting"})
  list = R("designer_checks", P)
  info("checks: " .. check_keys(list))
  check("no air: no rocket silo", has_check(list, "no-rocket-silo", "warning"))
  check("no air: other buildings that can't be built", has_check(list, "cant-build", "note"))
  check("pentapods without slime", has_check(list, "pentapods-need-slime", "warning"))
  check("lava: no water", has_check(list, "no-water", "note"))
  check("an own ore that never generates", has_check(list, "ore-not-generated", "warning"))
  check("no resources at all", has_check(list, "no-resources", "warning"))
  check("a recipe that makes nothing", has_check(list, "makes-nothing", "warning"))
  check("a fluid in a furnace recipe", has_check(list, "fluid-needs-machine", "warning"))
  check("a reference to an ore that doesn't exist", has_check(list, "missing-ref", "warning"))
  check("research that needs itself", has_check(list, "research-loop", "warning"))
  check("research with no rewards", has_check(list, "no-rewards", "note"))
  check("a pack no research uses", has_check(list, "pack-unused", "note"))
  check("problems and warnings come before notes", list[#list].level == "note")
  check("checks point to the section to fix them in", list[1].section ~= nil)
  for _, section in ipairs{"checks", "testplay"} do
    local ok, err = pcall(R, "designer_tab", P, section)
    check("the " .. section .. " section builds", ok, err)
  end
  local ok = pcall(R, "designer_do", P, "get-code")
  check("the code window opens with warnings", ok and player.gui.screen.pw_designer_code ~= nil)
  R("designer_do", P, "close", {window = "pw_designer_code"})

  -- fixed
  R("designer_set", P, "physics.pressure", 1000)
  R("designer_set", P, "terrain.liquid", "slime")
  R("designer_set", P, "resources", {{resource = "@ore:ore1", frequency = 1, size = 1, richness = 1}})
  R("designer_set", P, "recipes", {})
  R("designer_set", P, "technologies", {
    {key = "a", name = "Chicken", prerequisites = {"@discovery"}, count = 10, time = 10, ingredients = {{name = "@pack", amount = 1}},
      effects = {{type = "laboratory-speed", modifier = 0.1}}},
  })
  list = R("designer_checks", P)
  check("fixed planet: no problems or warnings", #list == 0 or list[1].level == "note", check_keys(list))

  -- made to be a starting planet: what a new game needs
  R("designer_do", P, "new")
  R("designer_set", P, "starting_planet", true)
  R("designer_set", P, "resources", {{resource = "iron-ore", frequency = 1, size = 1, richness = 1},
    {resource = "copper-ore", frequency = 1, size = 1, richness = 1, starting = false}})
  R("designer_set", P, "physics.pressure", 5)
  R("designer_set", P, "physics.freezing", true)
  list = R("designer_checks", P)
  info("starting planet checks: " .. check_keys(list))
  check("starting planet: needs stone, coal and oil", has_check(list, "start-needs") and has_check(list, "start-needs-oil"))
  check("starting planet: copper should be near the start", has_check(list, "start-not-near"))
  check("starting planet: burner buildings need air", has_check(list, "start-burner"))
  check("starting planet: freezing", has_check(list, "start-freezing"))
  R("designer_set", P, "resources", {{resource = "iron-ore"}, {resource = "copper-ore"}, {resource = "stone"},
    {resource = "coal"}, {resource = "crude-oil"}})
  R("designer_set", P, "physics.pressure", 1000)
  R("designer_set", P, "physics.freezing", false)
  list = R("designer_checks", P)
  check("a good starting planet: no warnings", #list == 0 or list[1].level == "note", check_keys(list))
  R("designer_tab", P, "general")
  check("the starting planet switch is in General", find(root(player), function(t) return t.path == "starting_planet" end) ~= nil)
  local code = codes.decode_body(R("designer_code", P):sub(5))
  check("the code says it's made to be a starting planet", code and code.planets[1].starting_planet == true)

  -- a loaded planet's own ores are the real ones in the preview
  R("designer_import", P, settings.startup["planet-workshop-planets"].value)
  for i, d in ipairs(R("designer_designs")) do
    if d.id == "brim0001" then
      local dd = find(root(player), function(t) return t.pw == "select-design" end)
      dd.selected_index = i
      R("designer_event", "on_gui_selection_state_changed", {element = dd, player_index = P})
    end
  end
  local mgs = game.surfaces["pw-preview-" .. P].map_gen_settings
  check("a loaded planet's preview has its real ore", mgs.autoplace_settings.entity.settings["pw-brim0001-ore-sulfite"] ~= nil)

  -- a planet to test play: iron, biters, its own physics
  R("designer_do", P, "new")
  R("designer_set", P, "name", "Testbed")
  R("designer_set", P, "resources", {{resource = "iron-ore", frequency = 1, size = 1, richness = 1}})
  R("designer_set", P, "enemies.kind", "biters")
  R("designer_set", P, "physics.gravity", 5)
  R("designer_set", P, "physics.pressure", 800)
  R("designer_set", P, "physics.solar_power", 200)
  R("designer_set", P, "physics.day_length", 10)
  R("designer_do", P, "test-start")
  check("starting right after a change waits for a fresh preview", player.controller_type == defines.controllers.god)

  return 10, function()
    local surface = game.surfaces["pw-preview-" .. P]
    check("test play: the player has a body", player.controller_type == defines.controllers.character and player.character ~= nil)
    check("test play: on the preview planet", player.surface == surface)
    check("test play: the designer window is put away", root(player) == nil)
    check("test play: the way back is on screen", player.gui.top.pw_test_bar ~= nil)
    check("test play: the landing kit", player.character and
      player.character.get_main_inventory().get_item_count("electric-mining-drill") == 20)
    check("test play: its own force, everything researched", player.force.name == "pw-test-" .. P and
      player.force.technologies["automation"].researched)
    check("test play: the planet's gravity", math.abs(surface.get_property("gravity") - 5) < 0.001, surface.get_property("gravity"))
    check("test play: the planet's pressure", math.abs(surface.get_property("pressure") - 800) < 0.001)
    check("test play: solar power", math.abs(surface.solar_power_multiplier - 2) < 0.001, surface.solar_power_multiplier)
    check("test play: day and night", not surface.always_day and surface.ticks_per_day == 36000, surface.ticks_per_day)
    check("test play: enemies are awake", not surface.peaceful_mode)
    check("test play: iron near the landing spot", nearest(surface, "iron-ore", 224) <= 200)
    local built = surface.create_entity{name = "stone-furnace", position = {20, 20}, force = player.force}
    check("test play: buildings can be built", built ~= nil)

    R("designer_do", P, "test-stop")
    check("back: no body", player.controller_type == defines.controllers.god and player.character == nil)
    check("back: in the designer room", player.surface.name == "nauvis" and player.force.name == "player")
    check("back: the window is back", root(player) ~= nil and player.gui.top.pw_test_bar == nil)
    check("back: free crafting is off", not player.cheat_mode)

    -- options: nothing researched, free crafting, no kit; then dying ends it
    R("designer_tab", P, "testplay")
    for key, value in pairs{kit = "none", research = "none"} do
      local dd = find(root(player), function(t) return t.pw == "test-pick" and t.key == key end)
      dd.selected_index = index_of_value(dd.tags.values, value)
      R("designer_event", "on_gui_selection_state_changed", {element = dd, player_index = P})
    end
    for key, value in pairs{free_crafting = true, enemies = false} do
      local box = find(root(player), function(t) return t.pw == "test-check" and t.key == key end)
      box.state = value
      R("designer_event", "on_gui_checked_state_changed", {element = box, player_index = P})
    end
    local start = find(root(player), function(t) return t.pw == "test-start" end)
    R("designer_event", "on_gui_click", {element = start, player_index = P})
    return 10, function()
      check("test play again (options)", player.controller_type == defines.controllers.character and player.cheat_mode and
        not player.force.technologies["automation"].researched and
        player.character.get_main_inventory().get_item_count("electric-mining-drill") == 0)
      check("enemies asleep when asked", surface.peaceful_mode)
      R("designer_do", P, "test-stop")
      R("designer_tab", P, "testplay")
      local kit = find(root(player), function(t) return t.pw == "test-pick" and t.key == "kit" end)
      kit.selected_index = index_of_value(kit.tags.values, "newgame")
      R("designer_event", "on_gui_selection_state_changed", {element = kit, player_index = P})
      R("designer_do", P, "test-start")
      return 10, function()
        check("the New game kit", player.character and player.character.get_item_count("burner-mining-drill") == 1 and
          player.character.get_item_count("pistol") == 1 and player.character.get_item_count("electric-mining-drill") == 0)
        player.character.die()
        return 120, function()
        check("dying ends test play", player.controller_type == defines.controllers.god and player.character == nil and
          player.surface.name == "nauvis" and R("designer_player", P).testing == nil, player.controller_type)
        check("dying: the window is back", root(player) ~= nil)
        local placed = R("designer_settle", P)
        check("the preview runs the starting safety net", type(placed) == "table")
        return 1200, function()
          check("no body turns up later", player.character == nil and player.controller_type == defines.controllers.god,
            player.controller_type)
        end
      end
    end
    end
  end
end

-- startarea: a hand-made start area, made with the map editor ----------------------------------------------------

local function test_startarea()
  local player = game.players[1]
  local P = player.index
  player.admin = true
  R("start_designer")
  R("designer_set", P, "name", "Startland")
  R("designer_set", P, "resources", {{resource = "iron-ore", frequency = 1, size = 1, richness = 1}})
  R("designer_set", P, "terrain.plants.styles", {"forest"})
  R("designer_do", P, "add-ore", {kind = "solid"})
  R("designer_tab", P, "start")
  local on = find(root(player), function(t) return t.pw == "start-on" end)
  on.state = true
  R("designer_event", "on_gui_checked_state_changed", {element = on, player_index = P})
  local size = find(root(player), function(t) return t.pw == "pick" and t.path == "start.radius" end)
  size.selected_index = 1 -- 32 tiles
  R("designer_event", "on_gui_selection_state_changed", {element = size, player_index = P})
  local d = R("designer_designs")[1]
  check("a start area is switched on, on the preview's world", d.start and d.start.radius == 32 and
    d.start.seed == R("designer_player", P).seed, d.start and serpent.line(d.start))
  local seed_button = find(root(player), function(t) return t.pw == "reseed" end)
  check("New seed still works with no changes", seed_button and seed_button.enabled)
  local edit = find(root(player), function(t) return t.pw == "start-edit" end)
  R("designer_event", "on_gui_click", {element = edit, player_index = P})

  return 10, function()
    local s = game.surfaces["pw-preview-" .. P]
    check("the map editor opens on the preview", player.controller_type == defines.controllers.editor and player.surface == s,
      player.controller_type)
    check("the editor bar is on screen", player.gui.top.pw_start_bar ~= nil)
    -- changes, as the editor would make them
    local water = {}
    for x = 10, 14 do for y = 10, 14 do water[#water + 1] = {name = "water", position = {x, y}} end end
    s.set_tiles(water)
    s.set_tiles({{name = "sand-1", position = {10, 10}}, {name = "water", position = {10, 10}}})
    for x = -10, -8 do for y = -10, -8 do
      for _, e in pairs(s.find_entities_filtered{position = {x + 0.5, y + 0.5}, radius = 0.6}) do e.destroy() end
      s.create_entity{name = "copper-ore", position = {x + 0.5, y + 0.5}, amount = 777}
    end end
    s.create_entity{name = "wooden-chest", position = {-3.5, 5.5}, force = "player"}
    local gone
    for _, e in pairs(s.find_entities_filtered{area = {{-28, -28}, {28, 28}}, type = {"tree", "resource", "simple-entity"}}) do
      if e.position.x > 0 and e.position.y < 0 then gone = {name = e.name, x = e.position.x, y = e.position.y}; e.destroy(); break end
    end
    info("taken away: " .. serpent.line(gone))
    -- the ore brush for the planet's own ore
    R("designer_do", P, "brush")
    check("the ore brush is in the cursor", player.cursor_stack.valid_for_read and player.cursor_stack.name == "pw-ore-brush")
    R("designer_event", "on_player_selected_area", {item = "pw-ore-brush", player_index = P, surface = s,
      area = {left_top = {x = -20, y = 5}, right_bottom = {x = -16, y = 9}}})
    local stand_in = s.find_entities_filtered{position = {-18.5, 6.5}, radius = 0.5, type = "resource"}[1]
    check("the brush places the planet's own ore", stand_in ~= nil and stand_in.name:find("pw%-k%-ore") ~= nil,
      stand_in and stand_in.name)
    R("designer_do", P, "start-save")
    check("Save: back to the designer", player.controller_type == defines.controllers.god and root(player) ~= nil and
      player.gui.top.pw_start_bar == nil)
    d = R("designer_designs")[1]
    local st = d.start
    local tiles = 0
    for _, run in ipairs(st.tiles) do tiles = tiles + run[3] end
    check("the water is kept (25 tiles)", tiles == 25 and st.palette[1] == "water", tiles .. " " .. serpent.line(st.palette))
    local copper, own, chest = 0, 0, 0
    for _, a in ipairs(st.add) do
      if a.name == "copper-ore" and a.amount == 777 then copper = copper + 1 end
      if a.name == "@ore:ore1" then own = own + 1 end
      if a.name == "wooden-chest" then chest = chest + 1 end
    end
    check("the copper is kept with its amount", copper == 9, copper)
    check("the own ore is kept as the planet's ore", own == 16, own)
    check("buildings aren't kept", chest == 0)
    local removed = false
    for _, r in ipairs(st.remove) do
      if gone and r.name == gone.name and math.abs(r.x - gone.x) < 0.01 and math.abs(r.y - gone.y) < 0.01 then removed = true end
    end
    check("what was taken away is kept", gone == nil or removed)
    seed_button = find(root(player), function(t) return t.pw == "reseed" end)
    check("New seed is locked once there are changes", seed_button and not seed_button.enabled)
    return 5, function()
      R("designer_settle", P)
      s = game.surfaces["pw-preview-" .. P]
      check("the preview shows the changes: water", s.get_tile(12, 12).name == "water")
      check("the preview shows the changes: copper", s.count_entities_filtered{name = "copper-ore", area = {{-10, -10}, {-7, -7}}} == 9)
      check("the preview shows the changes: own ore", s.count_entities_filtered{area = {{-20, 5}, {-16, 9}}, type = "resource"} == 16)
      check("the preview shows the changes: taken away", gone == nil or
        s.count_entities_filtered{name = gone.name, position = {gone.x, gone.y}, radius = 0.01} == 0)
      check("the preview shows the changes: no chest", s.count_entities_filtered{name = "wooden-chest"} == 0)
      local code = R("designer_code", P)
      local pack = codes.decode_body(code:sub(5))
      local problems = {}
      local p = pack and spec.normalize(pack.planets[1], problems)
      check("the code holds the start area", p and p.start and p.start.seed == d.start.seed and #p.start.add == #st.add and
        #problems == 0, serpent.line(problems))
      -- edit again: the changes so far are there; Cancel keeps them as they were
      R("designer_do", P, "start-edit")
      return 10, function()
        s = game.surfaces["pw-preview-" .. P]
        check("editing again shows the changes so far", player.controller_type == defines.controllers.editor and
          s.get_tile(12, 12).name == "water")
        s.set_tiles({{name = "sand-1", position = {12, 12}}})
        R("designer_do", P, "start-cancel")
        local again = R("designer_designs")[1].start
        local t2 = 0
        for _, run in ipairs(again.tiles) do t2 = t2 + run[3] end
        check("Cancel throws away the new change", t2 == 25 and player.controller_type == defines.controllers.god)
        R("designer_do", P, "get-code") -- (for the roundtrip suite)
        -- smaller: changes outside go
        R("designer_set", P, "start.radius", 32)
        R("designer_tab", P, "start")
        check("the start section builds with changes", root(player) ~= nil)
      end
    end
  end
end

-- startplanet: a new game started on Verdant ---------------------------------------------------------------------

local function test_startplanet()
  local V = "pw-verd0005"
  local player = game.players[1]
  info("level: " .. serpent.line(script.level))
  check("the starting planet is known", report().start_planet and report().start_planet.planet == V,
    serpent.line(report().start_planet))
  check("the player starts on Verdant", player.surface.name == V, player.surface.name)
  check("with a body", player.character ~= nil and player.character.surface.name == V)
  local s = game.surfaces[V]
  local spawn = player.force.get_spawn_position(s)
  check("the force's spawn point is on Verdant", s ~= nil and math.abs(player.position.x - spawn.x) < 40 and
    math.abs(player.position.y - spawn.y) < 40, serpent.line(spawn))
  check("Verdant's discovery is researched", player.force.technologies[V .. "-discovery"].researched)
  local crash_here = s.count_entities_filtered{name = "crash-site-spaceship"}
  local crash_nauvis = game.surfaces.nauvis.count_entities_filtered{name = "crash-site-spaceship"}
  info("crash site: Verdant " .. crash_here .. ", Nauvis " .. crash_nauvis)
  check("no crash site left on Nauvis", crash_nauvis == 0)
  check("the starting items", player.get_item_count("burner-mining-drill") >= 1 or
    (player.character and player.character.get_item_count("burner-mining-drill") >= 1), player.get_item_count("pistol"))
  check("iron near the start", nearest(s, "iron-ore", 224) <= 200)
  if player.controller_type == defines.controllers.cutscene then player.exit_cutscene() end
  return 60, function()
    check("the start area is charted", player.force.is_chunk_charted(s, {0, 0}) and player.force.is_chunk_charted(s, {5, 5}))
    check("Nauvis is still there, to fly to later", game.planets.nauvis.surface ~= nil)
    if player.character then player.character.die() end
    return 1200, function()
      check("after dying, the player respawns on Verdant", player.surface.name == V and player.character ~= nil,
        player.surface.name .. " " .. tostring(player.controller_type))
    end
  end
end

-- roundtrip: the planet designed in the designer suite, loaded from its code ------------------------------------

local function test_roundtrip()
  local planet
  for _, entry in ipairs(report().planets) do
    if entry.name == "Roundtrip" then planet = entry end
  end
  check("the designed planet loads from its code", planet ~= nil)
  if not planet then return end
  local P = planet.planet
  check("its own ore", prototypes.item[P .. "-ore-ore1"] ~= nil and prototypes.item[P .. "-ore-ore1"].localised_name[2] == "Glowstone")
  check("its own fluid", prototypes.fluid[P .. "-fluid-fluid1"] ~= nil)
  check("no problems loading it", #report().problems == 0, serpent.line(report().problems))
  local pack = prototypes.recipe[P .. "-pack"]
  check("its pack is made from its ore", pack and pack.ingredients[1].name == P .. "-ore-ore1")
  check("its pack spoils", prototypes.item[P .. "-pack"].get_spoil_ticks() == 30 * 3600)
  local recipe = prototypes.recipe[P .. "-recipe-recipe1"]
  local cats = recipe and recipe.categories or {}
  local chemistry = cats.chemistry ~= nil
  for _, c in pairs(cats) do if c == "chemistry" then chemistry = true end end
  check("its recipe uses its fluid in a chemical plant", recipe and recipe.ingredients[1].name == P .. "-fluid-fluid1" and
    chemistry, serpent.line(cats))
  local tech = prototypes.technology[P .. "-tech-tech1"]
  local unlocks, mining = false, false
  for _, e in ipairs(tech and tech.effects or {}) do
    if e.type == "unlock-recipe" and e.recipe == P .. "-recipe-recipe1" then unlocks = true end
    if e.type == "mining-drill-productivity-bonus" and math.abs(e.modifier - 0.15) < 0.001 then mining = true end
  end
  check("its research unlocks the recipe and gives mining productivity", unlocks and mining)
  local s = game.planets[P].create_surface()
  generate(s, 7)
  check("its ore generates near the landing spot", nearest(s, P .. "-ore-ore1", 224) <= 200)

  -- the hand-made start area made in the startarea suite
  local start
  for _, entry in ipairs(report().planets) do
    if entry.name == "Startland" then start = entry end
  end
  check("the planet with a hand-made start loads", start ~= nil and start.start ~= nil)
  if not (start and start.start) then return end
  local ss = game.planets[start.planet].create_surface()
  check("it generates from the start area's seed", ss.map_gen_settings.seed == start.start.seed, ss.map_gen_settings.seed)
  check("its water is there", ss.get_tile(12, 12).name == "water" and ss.get_tile(10, 14).name == "water")
  check("its copper is there", ss.count_entities_filtered{name = "copper-ore", area = {{-10, -10}, {-7, -7}}} == 9)
  local own = ss.count_entities_filtered{name = start.planet .. "-ore-ore1", area = {{-20, 5}, {-16, 9}}}
  check("its own ore is there (the real one)", own == 16, own)
  local missing = 0
  for _, a in ipairs(start.start.add) do
    local name = a.name:sub(1, 5) == "@ore:" and (start.planet .. "-ore-" .. a.name:sub(6)) or a.name
    if ss.count_entities_filtered{name = name, position = {a.x, a.y}, radius = 0.01} == 0 then missing = missing + 1 end
  end
  check("everything placed is there", missing == 0, missing .. "/" .. #start.start.add)
  local left = 0
  for _, r in ipairs(start.start.remove) do
    if ss.count_entities_filtered{name = r.name, position = {r.x, r.y}, radius = 0.01} > 0 then left = left + 1 end
  end
  check("everything taken away is gone", left == 0, left .. "/" .. #start.start.remove)
end

-- added -----------------------------------------------------------------------------------------------------

local function test_added()
  check("Brimstone appears in a save made without it", game.planets[B] ~= nil)
  check("its discovery technology is in the tech tree", game.forces.player.technologies[B .. "-discovery"] ~= nil)
  local s = game.planets[B].create_surface()
  generate(s, 12)
  check("its surface generates with its ore", s.count_entities_filtered{name = B .. "-ore-sulfite"} > 0)
  check("the existing Nauvis is untouched (no sulfite ore)", game.surfaces.nauvis.count_entities_filtered{name = B .. "-ore-sulfite"} == 0)
end

-- codec -----------------------------------------------------------------------------------------------------

local function test_codec()
  local planet = {id = "abcd1234", name = "Ünïcode ☃ \"quoted\" \\ test", list = {1, 2.5, -3e5, true, false},
    nested = {deeper = {deepest = "x"}}, empty_text = ""}
  local text = helpers.table_to_json({planets = {planet}})
  local code = helpers.encode_string(text)
  local back, err = codes.decode_body(code)
  check("a code made with helpers.encode_string decodes", back ~= nil, err)
  check("...and comes back exactly the same", back and same(back.planets[1], planet), back and serpent.line(back.planets[1]))
  local found = codes.read_all("junk text " .. codes.PREFIX .. code .. "   " .. codes.PREFIX .. code .. "\nmore junk")
  check("read_all finds several codes among other text", #found == 2, #found)

  -- A big code, like a planet with a hand-built start area
  local tiles = {}
  for i = 1, 60000 do tiles[i] = {i % 300, math.floor(i / 300), "red-desert-" .. (i % 4)} end
  local rng = game.create_random_generator(42)
  local entities = {}
  for i = 1, 3000 do entities[i] = {name = "stone-wall", x = rng(-200, 200), y = rng(-200, 200)} end
  local big_text = helpers.table_to_json({planets = {{id = "big00001", tiles = tiles, entities = entities}}})
  local big = helpers.encode_string(big_text)
  info("big planet: " .. #big_text .. " characters of data -> a code of " .. (#big + #codes.PREFIX) .. " characters")
  local profiler = helpers.create_profiler()
  local bback, berr = codes.decode_body(big)
  profiler.stop()
  localised_print({"", "STA INFO decoding the big code took ", profiler})
  check("the big code decodes", bback and #bback.planets[1].tiles == 60000 and #bback.planets[1].entities == 3000, berr)
  local t1 = helpers.create_profiler()
  local raw = base64.decode(big)
  t1.stop()
  local t2 = helpers.create_profiler()
  local inflated = inflate.zlib(raw)
  t2.stop()
  local t3 = helpers.create_profiler()
  json.decode(inflated)
  t3.stop()
  localised_print({"", "STA INFO   base64 ", t1, " / inflate ", t2, " / json ", t3})
  check("the big code matches the game's own decoder", helpers.decode_string(big) == big_text)

  -- Damaged codes must fail politely, never crash or hang
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local polite, decoded, total = 0, 0, 0
  for i = 1, 400 do
    local pos = rng(1, #code)
    local c = rng(1, 64)
    local damaged = code:sub(1, pos - 1) .. alphabet:sub(c, c) .. code:sub(pos + 1)
    local ok, res, msg = pcall(codes.decode_body, damaged)
    total = total + 1
    if ok and res then decoded = decoded + 1 elseif ok and type(msg) == "string" then polite = polite + 1 end
  end
  for cut = 1, #code - 1, 7 do
    local ok, res, msg = pcall(codes.decode_body, code:sub(1, cut))
    total = total + 1
    if ok and res then decoded = decoded + 1 elseif ok and type(msg) == "string" then polite = polite + 1 end
  end
  info(decoded .. " of " .. total .. " damaged codes still decoded (a changed character can be harmless)")
  check("every damaged or cut code fails politely", polite + decoded == total, (polite + decoded) .. "/" .. total)
  for _, junk in ipairs{"", "A", "AAAA", string.rep("/", 1000), "!!!!", helpers.encode_string("not json at all")} do
    local ok, res, msg = pcall(codes.decode_body, junk)
    check("junk is refused politely: " .. junk:sub(1, 12), ok and res == nil and type(msg) == "string", msg)
  end

  -- The JSON reader
  local ok1, v1 = pcall(json.decode, '{"a":[1,2,{"b":null}],"c":"\\u00e9\\n\\ud83d\\ude00","d":-1.5e2}')
  check("JSON reader handles escapes and numbers", ok1 and v1.c == "é\n😀" and v1.d == -150 and v1.a[3].b == nil,
    ok1 and serpent.line(v1) or v1)
  local ok2 = pcall(json.decode, string.rep("[", 200) .. string.rep("]", 200))
  check("JSON reader refuses very deep nesting", not ok2)
  local ok3 = pcall(json.decode, '{"a":1}x')
  check("JSON reader refuses extra text", not ok3)
end

-- Runner ----------------------------------------------------------------------------------------------------

local SUITES = {
  bridge = function() test_prototypes(); return test_world() end,
  added = test_added,
  terrain = test_terrain,
  designer = test_designer,
  roundtrip = test_roundtrip,
  codec = test_codec,
  testplay = test_testplay,
  startarea = test_startarea,
  startplanet = test_startplanet,
  -- a planet given the preview's seed generates exactly the preview (what hand-made start areas rely on)
  sameworld = function()
    local player = game.players[1]
    local P = player.index
    R("start_designer")
    R("designer_import", P, settings.startup["planet-workshop-planets"].value)
    for i, d in ipairs(R("designer_designs")) do
      if d.id == "brim0001" then
        local dd = find(root(player), function(t) return t.pw == "select-design" end)
        dd.selected_index = i
        R("designer_event", "on_gui_selection_state_changed", {element = dd, player_index = P})
      end
    end
    return 5, function()
      R("designer_settle", P)
      local a = game.surfaces["pw-preview-" .. P]
      local S = a.map_gen_settings.seed
      local mgs = prototypes.space_location["pw-brim0001"].map_gen_settings
      mgs.seed = S
      local b = game.create_surface("cmp", mgs)
      generate(b, 7)
      local area = {{-200, -200}, {200, 200}}
      local diff, total = 0, 0
      for x = -200, 199, 3 do for y = -200, 199, 3 do
        total = total + 1
        if a.get_tile(x, y).name ~= b.get_tile(x, y).name then diff = diff + 1 end
      end end
      check("same seed: tiles identical (a sample every 3 tiles)", diff == 0, diff .. "/" .. total)
      local function ents(s)
        local t = {}
        for _, e in pairs(s.find_entities_filtered{area = area}) do
          if e.type ~= "character" then t[e.name .. string.format("@%.2f,%.2f", e.position.x, e.position.y)] = true end
        end
        return t
      end
      local ea, eb = ents(a), ents(b)
      local na, nb, miss = 0, 0, 0
      local sample = {}
      for k in pairs(ea) do na = na + 1; if not eb[k] then miss = miss + 1; if #sample < 5 then sample[#sample+1] = k end end end
      for k in pairs(eb) do nb = nb + 1 end
      check("same seed: entities identical", miss == 0 and na == nb, na .. " vs " .. nb .. " missing " .. miss .. " " .. table.concat(sample, " "))
      local da, db = #a.find_decoratives_filtered{area = area}, #b.find_decoratives_filtered{area = area}
      check("decorations identical (count)", da == db, da .. " vs " .. db)
    end
  end,
}

-- A suite runs on tick 1; it may return a number of ticks and a function to finish its checks after that.
local later, later_tick

local function finish()
  print(("STA %s: %d passed, %d failed"):format(script.test_arg, passed, failed))
  script.finish_test(failed == 0)
end

script.on_event(defines.events.on_tick, function(e)
  if e.tick == 0 then return end
  if later then
    if e.tick >= later_tick then
      local fn = later
      later = nil
      local ok, wait, more = pcall(fn)
      if not ok then check("suite ran to the end", false, wait) end
      if ok and type(wait) == "number" and more then -- another step
        later, later_tick = more, e.tick + wait
        return
      end
      finish()
    end
    return
  end
  if storage.started then return end
  storage.started = true
  local suite = SUITES[script.test_arg]
  if not suite then
    print("STA FAIL unknown suite '" .. tostring(script.test_arg) .. "'")
    script.finish_test(false)
    return
  end
  local ok, wait, fn = pcall(suite)
  if not ok then
    check("suite ran to the end", false, wait)
  elseif type(wait) == "number" and fn then
    later, later_tick = fn, e.tick + wait
    return
  end
  finish()
end)
