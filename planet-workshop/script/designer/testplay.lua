-- Test play: the player lands on their preview as a character, with a starter kit, and plays the planet as it
-- will be: its physics (gravity, pressure, solar power, day and night) are set on the preview surface, enemies
-- wake up, and the starting-resources safety net has run. "Back to the designer" ends it and makes a fresh
-- preview (whatever was built is cleared away).
--
-- A preview is not the real planet: a running game can't make planet prototypes, so freezing (buildings that
-- need heat) and lightning only happen on the real planet, and a planet that isn't loaded yet has look-alike
-- ores and no pack, recipes or research of its own. Each tester gets their own force ("pw-test-<player>"), so
-- their research choice doesn't touch anyone else.

local state = require("__planet-workshop__.script.designer.state")
local preview = require("__planet-workshop__.script.designer.preview")
local checks = require("__planet-workshop__.script.designer.checks")
local gui = require("__planet-workshop__.script.designer.gui")

local M = {}

local BAR = "pw_test_bar"

M.DEFAULTS = {kit = "landing", research = "all", free_crafting = false, enemies = true}
M.KITS = {"landing", "none"}
M.RESEARCH = {"all", "none"}

--- The landing kit: what a first rocket down to a new planet might carry. (Things that don't exist are skipped.)
local LANDING_KIT = {
  {"electric-mining-drill", 20}, {"stone-furnace", 24}, {"assembling-machine-2", 10}, {"inserter", 50},
  {"long-handed-inserter", 10}, {"transport-belt", 300}, {"underground-belt", 20}, {"splitter", 10},
  {"small-electric-pole", 50}, {"medium-electric-pole", 50}, {"solar-panel", 30}, {"accumulator", 20},
  {"offshore-pump", 2}, {"boiler", 4}, {"steam-engine", 8}, {"pipe", 100}, {"pipe-to-ground", 20},
  {"wooden-chest", 20}, {"lab", 4}, {"radar", 2}, {"gun-turret", 10}, {"repair-pack", 50}, {"coal", 100},
  {"iron-plate", 200}, {"copper-plate", 200}, {"cargo-landing-pad", 1},
}
local FREEZING_KIT = {{"heating-tower", 4}, {"heat-pipe", 50}}

function M.options(ps)
  ps.test = ps.test or {}
  for k, v in pairs(M.DEFAULTS) do
    if ps.test[k] == nil then ps.test[k] = v end
  end
  return ps.test
end

--- True if this planet is loaded in this game (its code is in the mod setting), so its own things exist.
function M.loaded(design)
  return prototypes.space_location["pw-" .. design.id] ~= nil
end

local function give_kit(character, p)
  local main = character.get_inventory(defines.inventory.character_main)
  local list = {}
  for _, e in ipairs(LANDING_KIT) do list[#list + 1] = e end
  if p.physics.freezing then
    for _, e in ipairs(FREEZING_KIT) do list[#list + 1] = e end
  end
  for _, e in ipairs(list) do
    if prototypes.item[e[1]] then main.insert{name = e[1], count = e[2]} end
  end
  local guns = character.get_inventory(defines.inventory.character_guns)
  local ammo = character.get_inventory(defines.inventory.character_ammo)
  local armor = character.get_inventory(defines.inventory.character_armor)
  if guns and prototypes.item["submachine-gun"] then guns.insert{name = "submachine-gun", count = 1} end
  if ammo and prototypes.item["firearm-magazine"] then ammo.insert{name = "firearm-magazine", count = 200} end
  if armor and prototypes.item["heavy-armor"] then armor.insert{name = "heavy-armor", count = 1} end
end

local function show_view(player, on)
  local view = player.game_view_settings
  view.show_minimap = on
  view.show_research_info = on
  view.show_quickbar = on
  view.show_shortcut_bar = on
  player.game_view_settings = view
end

local function bar(player, design, p)
  if player.gui.top[BAR] then player.gui.top[BAR].destroy() end
  local frame = player.gui.top.add{type = "frame", name = BAR, direction = "vertical"}
  local top = frame.add{type = "flow", direction = "horizontal"}
  top.style.vertical_align = "center"
  top.add{type = "label", caption = {"planet-workshop-designer.testing", design.name}, style = "caption_label"}
  top.add{type = "button", caption = {"planet-workshop-designer.test-stop"}, style = "red_button",
    tags = {pw = "test-stop"}}
  local notes = {}
  if p.physics.freezing or p.physics.lightning then notes[#notes + 1] = {"planet-workshop-designer.test-note-real"} end
  if (#p.ores > 0 or p.science or #p.recipes > 0 or #p.technologies > 0) then
    notes[#notes + 1] = M.loaded(design) and {"planet-workshop-designer.test-note-loaded"} or
      {"planet-workshop-designer.test-note-not-loaded"}
  end
  for _, note in ipairs(notes) do
    local label = frame.add{type = "label", caption = note}
    label.style.single_line = false
    label.style.maximal_width = 420
    label.style.font_color = {0.8, 0.8, 0.8}
  end
end

local function test_force(player)
  local name = "pw-test-" .. player.index
  local force = game.forces[name] or game.create_force(name)
  force.reset()
  return force
end

--- Starts test play now, or (if the preview is out of date) makes a fresh preview and starts in two ticks.
function M.request(player)
  local d = storage.designer
  local ps = state.player(player.index)
  if ps.testing then return end
  if d.due[player.index] or (d.generate and d.generate[player.index]) or not game.surfaces[preview.surface_name(player.index)] then
    d.due[player.index] = nil
    preview.refresh(player) -- (its clear() happens at the end of this tick)
    d.test_start = d.test_start or {}
    d.test_start[player.index] = game.tick + 2
  else
    M.start(player)
  end
end

function M.start(player)
  local d = storage.designer
  local design, ps = state.current(player)
  if ps.testing then return end
  if d.test_start then d.test_start[player.index] = nil end
  local surface = game.surfaces[preview.surface_name(player.index)]
  if not surface then return end
  local opts = M.options(ps)
  local p, made = preview.evaluate(design, ps.seed)
  if not p then return end

  -- the whole start area, settled as the real planet's will be
  if d.generate then d.generate[player.index] = nil end
  if d.settling then d.settling[player.index] = nil end
  surface.request_to_generate_chunks({0, 0}, preview.RADIUS)
  surface.force_generate_chunk_requests()
  preview.settle(player.index)

  -- the planet's physics
  for name, value in pairs(checks.surface_properties(p)) do
    if prototypes.surface_property[name] then surface.set_property(name, value) end
  end
  surface.solar_power_multiplier = p.physics.solar_power / 100
  surface.always_day = false
  surface.ticks_per_day = math.max(60, math.floor(p.physics.day_length * 3600))
  surface.daytime = 0
  surface.peaceful_mode = not opts.enemies
  local pollutant = made and made.pollutant and prototypes.airborne_pollutant[made.pollutant]
  if pollutant then surface.override_pollution_type = {pollutant = pollutant} end

  -- a body on the planet
  if ps.walking then ps.walking = false end
  local force = test_force(player)
  if opts.research == "all" then force.research_all_technologies() end
  local position = surface.find_non_colliding_position("character", {0, 0}, 64, 0.5) or {0, 0}
  force.set_spawn_position(position, surface)
  player.teleport(position, surface)
  player.force = force
  local character = surface.create_entity{name = "character", position = position, force = force}
  player.set_controller{type = defines.controllers.character, character = character}
  player.cheat_mode = opts.free_crafting == true
  if opts.kit == "landing" then give_kit(character, p) end

  ps.testing = {tick = game.tick}
  gui.destroy(player)
  show_view(player, true)
  bar(player, design, p)
  log("Planet Workshop: test play of " .. p.name .. " by " .. player.name)
end

--- Ends test play: back to the designer, with a fresh preview. `why`: a message to print (or nil).
function M.stop(player, why)
  local ps = state.player(player.index)
  if not ps.testing then return end
  local body = player.character
  player.set_controller{type = defines.controllers.god}
  if body and body.valid then body.destroy() end
  player.cheat_mode = false
  player.force = game.forces.player
  player.teleport({0, 0}, game.surfaces.nauvis)
  ps.testing = nil
  if player.gui.top[BAR] then player.gui.top[BAR].destroy() end
  local surface = game.surfaces[preview.surface_name(player.index)]
  if surface then surface.override_pollution_type = nil end
  show_view(player, false)
  if why then player.print(why) end
  preview.refresh(player)
  gui.build(player)
end

--- Players whose delayed start is due (see M.request).
function M.on_tick()
  for index, tick in pairs(storage.designer.test_start or {}) do
    if game.tick >= tick then
      storage.designer.test_start[index] = nil
      local player = game.get_player(index)
      if player and player.valid then M.start(player) end
    end
  end
  for index, tick in pairs(storage.designer.test_died or {}) do
    if game.tick >= tick then
      storage.designer.test_died[index] = nil
      local player = game.get_player(index)
      if player and player.valid then
        if player.ticks_to_respawn then player.ticks_to_respawn = nil end -- (respawns now, on the preview)
        M.stop(player, {"planet-workshop-designer.test-died"})
      end
    end
  end
end

function M.on_player_died(event)
  local player = game.get_player(event.player_index)
  if player and state.player(player.index).testing then
    -- the game finishes the death after this event (the player then waits to respawn), so come back next tick
    storage.designer.test_died = storage.designer.test_died or {}
    storage.designer.test_died[player.index] = game.tick + 1
  end
end

--- A respawn in the designer (shouldn't happen after M.stop, but just in case): no body in the designer room.
function M.on_player_respawned(event)
  local player = game.get_player(event.player_index)
  if player and not state.player(player.index).testing then
    local body = player.character
    player.set_controller{type = defines.controllers.god}
    if body and body.valid then body.destroy() end
    player.teleport({0, 0}, game.surfaces.nauvis)
  end
end

M.BAR = BAR

return M
