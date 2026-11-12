-- The starting-resources safety net (runtime).
--
-- A planet's map settings already give every starting resource a patch near the landing spot (the planet's
-- patch set in the terrain kit, see lib/kit.lua), but noise can't promise it: on some seeds a patch lands under a
-- lava sea or under another ore. So the first time a Planet Workshop planet's surface is created, the area
-- around the landing spot is generated and any starting resource missing within SEARCH tiles gets a small
-- patch on dry ground nearby. It runs once per surface.

local startarea = require("__planet-workshop__.script.startarea")

local M = {}

M.SEARCH = 200 -- tiles from the landing spot
M.GENERATE = 7 -- chunks around the landing spot generated before checking
local GENERATE = M.GENERATE

local function planet_info(name)
  local data = prototypes.mod_data["planet-workshop-report"]
  for _, planet in ipairs(data and data.data.planets or {}) do
    if planet.planet == name then return planet end
  end
  return nil
end

local function is_dry(surface, position)
  local tile = surface.get_tile(position.x, position.y)
  return tile.valid and not tile.prototype.fluid
end

--- Places a small patch of `res` around a free spot about 60-140 tiles from the landing spot.
local function place_patch(surface, res, rng)
  local proto = prototypes.entity[res.entity]
  if not proto then return false end
  for _ = 1, 24 do
    local angle = rng() * 2 * math.pi
    local dist = 60 + rng() * 80
    local cx, cy = math.floor(math.cos(angle) * dist) + 0.5, math.floor(math.sin(angle) * dist) + 0.5
    local placed = 0
    if res.fluid then
      local amount = math.floor((proto.normal_resource_amount or 100000) * 3 * res.richness)
      for i = 0, 4 do
        local pos = {x = cx + (i % 3) * 5 - 5, y = cy + math.floor(i / 3) * 6 - 3}
        if is_dry(surface, pos) and surface.can_place_entity{name = res.entity, position = pos} then
          surface.create_entity{name = res.entity, position = pos, amount = amount}
          placed = placed + 1
        end
      end
      if placed >= 3 then return true end
    else
      local radius = 7
      local amount = math.floor(800 * res.richness)
      local spots = {}
      for dx = -radius, radius do
        for dy = -radius, radius do
          if dx * dx + dy * dy <= radius * radius then
            local pos = {x = cx + dx, y = cy + dy}
            if is_dry(surface, pos) and surface.can_place_entity{name = res.entity, position = pos} then
              spots[#spots + 1] = pos
            end
          end
        end
      end
      if #spots >= 80 then
        for _, pos in ipairs(spots) do
          local edge = 1 - math.sqrt((pos.x - cx) ^ 2 + (pos.y - cy) ^ 2) / (radius + 1)
          surface.create_entity{name = res.entity, position = pos, amount = math.max(10, math.floor(amount * (0.4 + edge)))}
        end
        return true
      end
    end
  end
  return false
end

--- Makes sure every resource in `list` ({{entity, fluid, richness}}, from lib/mapgen.lua) is near the landing spot
--- on `surface`. Returns the list of resources it had to place.
function M.ensure_list(surface, list)
  if not list or #list == 0 then return {} end
  surface.request_to_generate_chunks({0, 0}, GENERATE)
  surface.force_generate_chunk_requests()
  local rng = game.create_random_generator(surface.map_gen_settings.seed % 4294967295)
  local placed = {}
  local area = {{-M.SEARCH, -M.SEARCH}, {M.SEARCH, M.SEARCH}}
  for _, res in ipairs(list) do
    local near = false
    for _, e in pairs(surface.find_entities_filtered{name = res.entity, area = area}) do
      if e.position.x ^ 2 + e.position.y ^ 2 <= M.SEARCH ^ 2 then
        near = true
        break
      end
    end
    if not near and place_patch(surface, res, rng) then placed[#placed + 1] = res.entity end
  end
  return placed
end

--- The same for a loaded planet (its starting resources come from the loader's report).
function M.ensure(surface, planet_name)
  local info = planet_info(planet_name)
  return M.ensure_list(surface, info and info.starting)
end

--- A planet's own ore names: "@ore:<key>" -> its resource.
function M.resolver(planet_id)
  return function(name)
    if name:sub(1, 5) == "@ore:" then return "pw-" .. planet_id .. "-ore-" .. name:sub(6) end
    return name
  end
end

function M.on_surface_created(event)
  local surface = game.surfaces[event.surface_index]
  local planet = surface and surface.planet
  if planet and planet.name:sub(1, 3) == "pw-" then
    storage.started = storage.started or {}
    if not storage.started[surface.index] then
      storage.started[surface.index] = true
      local info = planet_info(planet.name)
      -- a hand-made start area: the planet is always the world it was made on, with its changes on top
      if info and info.start then
        local mgs = surface.map_gen_settings
        mgs.seed = info.start.seed
        surface.map_gen_settings = mgs
      end
      M.ensure(surface, planet.name)
      if info and info.start then startarea.apply(surface, info.start, M.resolver(info.id)) end
    end
  end
end

return M
