-- The designer's live preview: a surface per player, generated from the planet's map settings by the same code
-- the loader uses (lib/mapgen.lua), so it shows what the finished planet will look like (on a sample seed).

local spec = require("__planet-workshop__.lib.spec")
local mapgen = require("__planet-workshop__.lib.mapgen")
local lookup = require("__planet-workshop__.script.lookup")
local state = require("__planet-workshop__.script.designer.state")
local starting = require("__planet-workshop__.script.starting")

local M = {}

M.RADIUS = starting.GENERATE -- chunks generated around the landing spot (as much as the safety net looks at)

function M.surface_name(player_index)
  return "pw-preview-" .. player_index
end

--- The planet as the loader would see it, its map settings, and any problems.
function M.evaluate(design, seed)
  local problems = {}
  local p = spec.normalize(design, problems)
  if not p then return nil, nil, problems end
  local made = mapgen.build(p, lookup.for_planet(p), function(key, ...)
    problems[#problems + 1] = {"planet-workshop-problem." .. key, p.name, ...}
  end)
  local mgs = made.mgs
  mgs.seed = seed
  mgs.starting_points = {{x = 0, y = 0}}
  return p, made, problems
end

--- Regenerates a player's preview now (not while they're test playing on it). Returns the surface.
function M.refresh(player)
  local design, ps = state.current(player)
  if ps.testing then return nil end
  local p, made, problems = M.evaluate(design, ps.seed)
  ps.problems = problems
  if not made then return nil end
  ps.picture, ps.sky = made.picture, made.sky
  ps.starting, ps.pollutant, ps.placed = made.starting, made.pollutant, nil
  local name = M.surface_name(player.index)
  local surface = game.surfaces[name]
  if surface then
    surface.map_gen_settings = made.mgs
    surface.clear(true)
  else
    surface = game.create_surface(name, made.mgs)
  end
  surface.always_day = true
  surface.peaceful_mode = true -- a sample to look at: its nests shouldn't wake up and expand
  -- clear() only happens at the end of the tick and would drop a request made now, so ask next tick
  storage.designer.generate = storage.designer.generate or {}
  storage.designer.generate[player.index] = game.tick + 1
  return surface
end

local function all_generated(surface)
  for x = -M.RADIUS, M.RADIUS - 1 do
    for y = -M.RADIUS, M.RADIUS - 1 do
      if not surface.is_chunk_generated({x, y}) then return false end
    end
  end
  return true
end

--- Runs the starting-resources safety net on a finished preview, as the real planet's surface will (so the
--- preview shows what players find). Returns true if it ran.
function M.settle(player_index)
  local surface = game.surfaces[M.surface_name(player_index)]
  local ps = state.player(player_index)
  if not surface or ps.placed then return false end
  ps.placed = starting.ensure_list(surface, ps.starting)
  return true
end

--- Asks for the preview's chunks for the players whose surface was just made or cleared, charts them, and
--- settles finished previews. Returns the players whose preview just finished (their checks may have changed).
function M.generate_due()
  local finished = {}
  for index, tick in pairs(storage.designer.generate or {}) do
    if game.tick >= tick then
      storage.designer.generate[index] = nil
      local surface = game.surfaces[M.surface_name(index)]
      if surface then
        surface.request_to_generate_chunks({0, 0}, M.RADIUS)
        storage.designer.chart = storage.designer.chart or {}
        storage.designer.chart[index] = game.tick + 600
        storage.designer.settling = storage.designer.settling or {}
        storage.designer.settling[index] = true
      end
    end
  end
  -- The window's camera only draws charted ground, so chart the preview while its chunks are being made.
  if game.tick % 30 == 0 then
    for index, until_tick in pairs(storage.designer.chart or {}) do
      local surface = game.surfaces[M.surface_name(index)]
      local player = game.get_player(index)
      if surface and player then
        local r = M.RADIUS * 32
        player.force.chart(surface, {{-r, -r}, {r, r}})
        if (storage.designer.settling or {})[index] and all_generated(surface) then
          storage.designer.settling[index] = nil
          if M.settle(index) then finished[#finished + 1] = index end
          storage.designer.chart[index] = math.max(game.tick + 60, until_tick) -- chart the added patches too
          until_tick = storage.designer.chart[index]
        end
      end
      if game.tick >= until_tick then storage.designer.chart[index] = nil end
    end
  end
  return finished
end

--- Asks for a new preview soon (changes come in bursts while a slider is dragged).
function M.schedule(player_index, delay)
  storage.designer.due[player_index] = game.tick + (delay or 30)
end

--- Returns the players whose preview is due now.
function M.take_due()
  local ready = {}
  for index, tick in pairs(storage.designer.due) do
    if game.tick >= tick then ready[#ready + 1] = index end
  end
  for _, index in ipairs(ready) do storage.designer.due[index] = nil end
  return ready
end

return M
