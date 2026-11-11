-- The designer's saved state (storage.designer): every planet being designed (in the planet code format, see
-- lib/spec.lua), and each player's view (which planet, preview zoom and seed, open tab).

local M = {}

M.ZOOMS = {0.03, 0.05, 0.08, 0.12, 0.2, 0.35}
--- Amount sliders (like the game's map settings): 17% ... 600%
M.AMOUNTS = {1 / 6, 1 / 4, 1 / 3, 1 / 2, 2 / 3, 1, 1.5, 2, 3, 4, 6}

function M.active()
  return storage.designer ~= nil and storage.designer.active == true
end

function M.start()
  storage.designer = storage.designer or {designs = {}, players = {}, due = {}, counter = 0}
  storage.designer.active = true
end

function M.player(index)
  local d = storage.designer
  local ps = d.players[index]
  if not ps then
    ps = {current = 1, zoom = 3, seed = 1000 + index * 7919, tab = 1}
    d.players[index] = ps
  end
  return ps
end

--- A new planet id: 8 letters/digits, different for every planet anyone makes (mixes the map seed, the tick,
--- the player and a counter, so two players' first planets don't share an id).
function M.new_id(player)
  local d = storage.designer
  d.counter = d.counter + 1
  local seed = (game.surfaces[1].map_gen_settings.seed + game.tick * 7919 + d.counter * 104729 + player.index * 31) % 4294967291
  for i = 1, #player.name do seed = (seed * 33 + player.name:byte(i)) % 4294967291 end
  local rng = game.create_random_generator(seed)
  local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  local id = {}
  for i = 1, 8 do
    local n = rng(1, #chars)
    id[i] = chars:sub(n, n)
  end
  return table.concat(id)
end

--- A blank planet: plain sand and water, nothing else; everything is chosen in the designer.
function M.blank(player)
  return {
    id = M.new_id(player),
    name = "New planet",
    author = player.name,
    description = "",
    look = {picture = "auto", sky = "auto"},
    space = {from = "nauvis", length = 15000, distance = 20, orientation = 0.5, magnitude = 1, asteroids = "nauvis_vulcanus"},
    physics = {gravity = 10, pressure = 1000, magnetic_field = 90, solar_power = 100, day_length = 7, freezing = false,
      lightning = false},
    terrain = {
      shape = "lakes", liquid = "water", liquid_amount = 1, patch_size = 1, decorations = true,
      ground = {{tile = "sand-1", share = 1}},
      cliffs = {style = "none", amount = 1},
      plants = {styles = {}, amount = 1},
      rocks = {styles = {}, amount = 1},
    },
    enemies = {kind = "none", amount = 1},
    resources = {},
    ores = {}, recipes = {}, technologies = {},
  }
end

--- The planet a player is working on (making a blank one if there are none).
function M.current(player)
  local d = storage.designer
  if #d.designs == 0 then d.designs[1] = M.blank(player) end
  local ps = M.player(player.index)
  if ps.current > #d.designs or ps.current < 1 then ps.current = 1 end
  return d.designs[ps.current], ps
end

--- Reads / writes a dotted path ("terrain.ground.2.share"; numbers index lists).
local function step(key)
  return tonumber(key) or key
end

function M.get(t, path)
  for key in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[step(key)]
  end
  return t
end

function M.set(t, path, value)
  local keys = {}
  for key in path:gmatch("[^%.]+") do keys[#keys + 1] = step(key) end
  for i = 1, #keys - 1 do
    if type(t[keys[i]]) ~= "table" then t[keys[i]] = {} end
    t = t[keys[i]]
  end
  t[keys[#keys]] = value
end

--- Paths whose change alters the generated world (others, like gravity or the route, don't need a new preview).
function M.affects_map(path)
  return path:find("^terrain") or path:find("^resources") or path:find("^enemies") or path:find("^look")
end

return M
