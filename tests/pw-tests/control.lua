-- Test harness for Planet Workshop (not part of the mod). Run with --test-save and --test-arg <suite>
-- (tools/run_tests.sh does it). Suites:
--   bridge  the test codes (Brimstone, Frostbite, a broken code, a too-new code) loaded into a new game
--   added   the same codes added to a save that was made without them
--   codec   codes made in game with helpers.encode_string read back by the mod's own decoder
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

local function generate(surface, radius)
  surface.request_to_generate_chunks({0, 0}, radius)
  surface.force_generate_chunk_requests()
end

-- bridge ----------------------------------------------------------------------------------------------------

local function test_prototypes()
  local r = report()
  check("two planets loaded from the codes", #r.planets == 2, #r.planets)
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
  check("the ore has a map-gen control", prototypes.autoplace_control[ore] ~= nil)

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
  local allowed = {"red-desert-0", "red-desert-1", "red-desert-2", "red-desert-3", "water", "deepwater"}
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
  check("no trees (not chosen)", s.count_entities_filtered{type = "tree"} == 0)
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

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

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
  codec = test_codec,
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
      local ok, err = pcall(fn)
      if not ok then check("suite ran to the end", false, err) end
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
