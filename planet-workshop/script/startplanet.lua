-- Starting on one of your own planets instead of Nauvis (the "Starting planet" startup setting).
--
-- Only for new freeplay games: when the mod is set up at tick 0 of a freeplay game, the planet's surface is made
-- (its start area generated, with the safety net and any hand-made start area, see script/starting.lua), its
-- discovery research is done, and the player force's spawn point is put there. Each new player is moved there as
-- they're created. Freeplay handles a new player before mods do (it would make its crash site and intro cutscene
-- on Nauvis), so its crash site is switched off and the crash site is made on the planet instead (no cutscene;
-- freeplay shows the intro message, ours). Players who die on it respawn there. Nauvis stays, to fly to later.

local starting = require("__planet-workshop__.script.starting")
local crash_site = require("crash-site")

local M = {}

local function report()
  local proto = prototypes.mod_data["planet-workshop-report"]
  return proto and proto.data or {}
end

--- Where new games start: {planet, name, surface, position}, or nil (Nauvis).
function M.target()
  return storage.start_planet and storage.start_planet.surface and storage.start_planet or nil
end

--- Sets up a new game on the starting planet (from on_init).
function M.on_init()
  local wanted = report().start_planet
  if not wanted then return end
  storage.start_planet = {planet = wanted.planet, name = wanted.name}
  local why
  if script.active_mods["any-planet-start"] then
    why = "any-planet-start"
  elseif game.tick > 0 then
    why = "not-new" -- (the mod was added to a game that had already started)
  elseif not (script.level and script.level.level_name == "freeplay" and script.level.campaign_name == nil) then
    why = "not-freeplay"
  elseif not game.planets[wanted.planet] then
    why = "missing"
  end
  if why == "not-freeplay" and script.level and script.level.mod_name == "planet-workshop" then
    storage.start_planet = nil -- (the Planet Designer: nothing to say)
    return
  end
  if why then
    storage.start_planet.skipped = why
    log("Planet Workshop: not starting on " .. wanted.name .. " (" .. why .. ")")
    return
  end

  local surface = game.planets[wanted.planet].surface or game.planets[wanted.planet].create_surface()
  starting.on_surface_created({surface_index = surface.index}) -- (runs once per surface; in case the event came early)
  surface.request_to_generate_chunks({0, 0}, starting.GENERATE)
  surface.force_generate_chunk_requests()
  local position = surface.find_non_colliding_position("character", {0, 0}, 64, 0.5) or {x = 0, y = 0}
  local force = game.forces.player
  force.set_spawn_position(position, surface)
  local discovery = force.technologies[wanted.discovery]
  if discovery then discovery.researched = true end
  force.chart(surface, {{position.x - 200, position.y - 200}, {position.x + 200, position.y + 200}})
  local freeplay = remote.interfaces.freeplay
  if freeplay and freeplay.set_custom_intro_message then
    remote.call("freeplay", "set_custom_intro_message", {"planet-workshop.start-intro", wanted.name})
  end
  if freeplay and freeplay.set_disable_crashsite then
    remote.call("freeplay", "set_disable_crashsite", true)
    storage.start_planet.crash = true -- (made on the planet when the first player arrives)
  end
  storage.start_planet.surface = surface.index
  storage.start_planet.position = position
  storage.start_planet.moved = {}
  log("Planet Workshop: new game starts on " .. wanted.name)
end

local function move(player)
  local target = M.target()
  if not target then return end
  local surface = game.surfaces[target.surface]
  if not surface then return end
  local position = surface.find_non_colliding_position("character", target.position, 32, 0.5) or target.position
  player.teleport(position, surface)
end

function M.on_player_created(event)
  local target = M.target()
  local player = game.get_player(event.player_index)
  local skipped = storage.start_planet and storage.start_planet.skipped
  if skipped then
    player.print({"planet-workshop.start-skipped-" .. skipped, storage.start_planet.name})
    return
  end
  if not target or target.moved[player.index] then return end
  target.moved[player.index] = true
  move(player)
  local surface = game.surfaces[target.surface]
  local p = target.position
  player.force.chart(surface, {{p.x - 200, p.y - 200}, {p.x + 200, p.y + 200}}) -- (as freeplay does on Nauvis)
  if target.crash then
    target.crash = nil
    surface.daytime = 0.7
    -- (the ship's and debris' items stay with the player: freeplay only takes them when it makes the crash site)
    crash_site.create_crash_site(surface, {target.position.x - 5, target.position.y - 6}, {}, {},
      crash_site.default_ship_parts())
  end
end

--- Players who died on the starting planet respawn there (not on Nauvis).
function M.on_player_died(event)
  local target = M.target()
  local player = game.get_player(event.player_index)
  if target and player and player.surface.index == target.surface then
    storage.start_planet.died_here = storage.start_planet.died_here or {}
    storage.start_planet.died_here[player.index] = true
  end
end

function M.on_player_respawned(event)
  local target = M.target()
  local died = target and storage.start_planet.died_here
  if died and died[event.player_index] then
    died[event.player_index] = nil
    local player = game.get_player(event.player_index)
    if player and player.surface.index ~= target.surface then move(player) end
  end
end

return M
