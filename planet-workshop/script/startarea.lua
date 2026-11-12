-- Hand-made start areas (runtime): what a player changed around the landing spot, saved as changes to the
-- generated world, and put back on a surface.
--
-- A planet with a hand-made start area always generates from the same seed (the one it was made on), so the
-- world around the changes is exactly the world they were made on and they fit it with no seams. The changes
-- (planet format, see lib/spec.lua `start`):
--   palette = {tile names}; tiles = {{x, y, length, palette index}} - runs of changed tiles along a row
--   add = {{name, x, y, amount?, dir?, orientation?, variation?, color?, enemy?}} - things placed
--   remove = {{name, x, y}} - generated things taken away
-- Names may be "@ore:<key>" (the planet's own ore); `resolve(name)` turns a name into a real entity name.
--
-- Order on a surface: generate, starting-resources safety net, then these changes (the designer takes its "before"
-- picture at the same point, so the changes fit exactly).

local M = {}

--- The kinds of things a start area keeps (buildings and other things are not kept).
M.TYPES = {"resource", "tree", "simple-entity", "plant", "fish", "cliff", "unit-spawner", "turret", "lightning-attractor"}
local KEPT = {}
for _, t in ipairs(M.TYPES) do KEPT[t] = true end
M.KEPT = KEPT

M.RADII = require("__planet-workshop__.lib.spec").START_RADII

local function key(name, x, y) return string.format("%s@%.3f,%.3f", name, x, y) end

local function inside(x, y, radius) return x * x + y * y <= radius * radius end

--- The area a radius covers (tile positions -radius .. radius-1).
local function bounds(radius) return {{-radius, -radius}, {radius, radius}} end

--- Makes sure the start area is generated.
function M.generate(surface, radius)
  surface.request_to_generate_chunks({0, 0}, math.ceil(radius / 32) + 1)
  surface.force_generate_chunk_requests()
end

--- A picture of the start area as it is now: {tiles = {[y] = {[x] = name}}, things = {[key] = info}}.
function M.snapshot(surface, radius)
  local tiles = {}
  for y = -radius, radius - 1 do
    local row = {}
    tiles[y] = row
    for x = -radius, radius - 1 do
      if inside(x + 0.5, y + 0.5, radius) then row[x] = surface.get_tile(x, y).name end
    end
  end
  local things, others = {}, 0
  for _, e in pairs(surface.find_entities_filtered{area = bounds(radius)}) do
    local p = e.position
    if inside(p.x, p.y, radius) then
      if KEPT[e.type] then
        local info = {name = e.name, x = p.x, y = p.y}
        if e.type == "resource" then info.amount = e.amount end
        if e.type == "cliff" then info.orientation = e.cliff_orientation end
        if e.type == "turret" or e.type == "unit-spawner" then info.enemy = e.force.name == "enemy" or nil end
        if e.supports_direction then info.dir = e.direction end
        if e.type == "tree" then info.color = e.tree_color_index end
        if e.type ~= "tree" and e.type ~= "cliff" then info.variation = e.graphics_variation end
        things[key(e.name, p.x, p.y)] = info
      elseif e.type ~= "character" and e.type ~= "character-corpse" then
        others = others + 1
      end
    end
  end
  return {tiles = tiles, things = things, others = others}
end

--- The changes from `before` to `after` (two snapshots of the same radius), in the planet format.
--- `to_ref(entity name)` may turn names into "@ore:<key>". Returns the changes and how many things weren't kept.
function M.diff(before, after, radius, to_ref)
  to_ref = to_ref or function(name) return name end
  local palette, index, runs = {}, {}, {}
  for y = -radius, radius - 1 do
    local b, a = before.tiles[y] or {}, after.tiles[y] or {}
    local run
    for x = -radius, radius do
      local name = a[x]
      if name ~= nil and name ~= b[x] then
        if not index[name] then
          palette[#palette + 1] = name
          index[name] = #palette
        end
        if run and run[1] + run[3] == x and run[4] == index[name] then
          run[3] = run[3] + 1
        else
          run = {x, y, 1, index[name]}
          runs[#runs + 1] = run
        end
      else
        run = nil
      end
    end
  end
  local add, remove = {}, {}
  local function same(p, q)
    return p.amount == q.amount and p.dir == q.dir and p.orientation == q.orientation
  end
  for k, info in pairs(after.things) do
    local was = before.things[k]
    if not was or not same(was, info) then
      local entry = {name = to_ref(info.name), x = info.x, y = info.y, amount = info.amount, dir = info.dir,
        orientation = info.orientation, variation = info.variation, color = info.color, enemy = info.enemy}
      add[#add + 1] = entry
      if was then remove[#remove + 1] = {name = to_ref(was.name), x = was.x, y = was.y} end
    end
  end
  for k, info in pairs(before.things) do
    if not after.things[k] then remove[#remove + 1] = {name = to_ref(info.name), x = info.x, y = info.y} end
  end
  -- (a stable order, so the same changes always make the same code)
  local function by_place(p, q)
    if p.y ~= q.y then return p.y < q.y end
    if p.x ~= q.x then return p.x < q.x end
    return p.name < q.name
  end
  table.sort(add, by_place)
  table.sort(remove, by_place)
  return {palette = palette, tiles = runs, add = add, remove = remove}, after.others
end

--- How much a start area changes: tiles, things added, things removed.
function M.count(start)
  local tiles = 0
  for _, run in ipairs(start and start.tiles or {}) do tiles = tiles + run[3] end
  return tiles, #(start and start.add or {}), #(start and start.remove or {})
end

--- Puts a start area's changes on a surface (already generated, and with the safety net run).
function M.apply(surface, start, resolve)
  resolve = resolve or function(name) return name end
  M.generate(surface, start.radius)
  for _, r in ipairs(start.remove or {}) do
    local name = resolve(r.name)
    if name and prototypes.entity[name] then
      for _, e in pairs(surface.find_entities_filtered{name = name, position = {r.x, r.y}, radius = 0.01}) do e.destroy() end
    end
  end
  local tiles = {}
  for _, run in ipairs(start.tiles or {}) do
    local name = start.palette[run[4]]
    if name and prototypes.tile[name] then
      for i = 0, run[3] - 1 do tiles[#tiles + 1] = {name = name, position = {run[1] + i, run[2]}} end
    end
  end
  if #tiles > 0 then surface.set_tiles(tiles, true, true, true) end
  local placed = 0
  for _, a in ipairs(start.add or {}) do
    local name = resolve(a.name)
    local proto = name and prototypes.entity[name]
    if proto and KEPT[proto.type] then
      local spec = {name = name, position = {a.x, a.y}, force = a.enemy and "enemy" or "neutral", amount = a.amount,
        direction = a.dir, cliff_orientation = a.orientation, create_build_effect_smoke = false}
      if proto.type == "resource" then
        spec.amount = math.max(1, a.amount or 1000)
        spec.enable_tree_removal, spec.enable_cliff_removal = false, false -- (what was taken away is in `remove`)
      end
      local e = surface.create_entity(spec)
      if e then
        placed = placed + 1
        if a.variation and e.graphics_variation then e.graphics_variation = a.variation end
        if a.color and proto.type == "tree" then e.tree_color_index = a.color end
      end
    end
  end
  return placed
end

--- Drops changes outside the start area's radius (after it was made smaller).
function M.trim(start)
  local r = start.radius
  local runs = {}
  for _, run in ipairs(start.tiles or {}) do
    local x1, y, len, p = run[1], run[2], run[3], run[4]
    local first, last
    for x = x1, x1 + len - 1 do
      if inside(x + 0.5, y + 0.5, r) then
        first = first or x
        last = x
      end
    end
    if first then runs[#runs + 1] = {first, y, last - first + 1, p} end
  end
  start.tiles = runs
  for _, list in ipairs{"add", "remove"} do
    local kept = {}
    for _, t in ipairs(start[list] or {}) do
      if inside(t.x, t.y, r) then kept[#kept + 1] = t end
    end
    start[list] = kept
  end
end

M.key, M.inside = key, inside

return M
