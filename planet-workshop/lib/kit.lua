-- The terrain kit: names shared by the loader and the designer (plain data, both stages).
--
-- Planets can't get their own noise rules at runtime, so every planet (and the designer's preview) uses the
-- same kit of named noise expressions (prototypes/kit.lua). What makes one planet different from another is the
-- values of the kit's hidden map-gen controls in its map settings, which a running game can change. So the
-- preview and the finished planet are made by exactly the same rules (lib/mapgen.lua).
--
-- Changing slot counts or expressions changes how existing planets generate new chunks, so after release these
-- should only ever be added to.

local M = {}

M.PREFIX = "pw-k-" -- controls (and preview stand-in ores)
M.X = "pw_k_" -- noise expressions (underscores: a dash would read as minus)

M.GROUND_SLOTS = 12

--- Resource slots: each kind has its own patch settings and its own place in the shared patch set.
M.RESOURCE_SLOTS = {
  {kind = "solid-start", key = "s", count = 8, fluid = false, starting = true},
  {kind = "solid", key = "r", count = 8, fluid = false, starting = false},
  {kind = "fluid-start", key = "f", count = 3, fluid = true, starting = true},
  {kind = "fluid", key = "g", count = 4, fluid = true, starting = false},
}

--- Demolisher territory sizes (tiles); the planet's amount picks the closest.
M.TERRITORY_RADII = {640, 480, 384, 300, 240, 190}

--- Stand-ins for the designer preview (a planet's own ores only exist after a restart): this many hidden copies
--- of each base look (spec.ORE_BASES and spec.FLUID_BASES).
M.PREVIEW_ORES = 4

function M.control(name) return M.PREFIX .. name end
function M.ground_control(i) return M.PREFIX .. "ground-" .. i end
function M.ground_expression(i) return M.X .. "ground_" .. i end
function M.resource_control(key, i) return M.PREFIX .. "res-" .. key .. i end
function M.resource_expression(key, i, what) return M.X .. "res_" .. key .. i .. "_" .. what end
function M.elevation_expression(shape, pond) return M.X .. "elevation_" .. shape .. (pond and "_pond" or "") end
function M.plants_expression(style) return M.X .. "plants_" .. style:gsub("%-", "_") end
function M.rocks_expression(style) return M.X .. "rocks_" .. style:gsub("%-", "_") end
function M.territory_expression(i) return M.X .. "territory_" .. i end
function M.preview_ore(base, i) return M.PREFIX .. "ore-" .. base .. "-" .. i end

--- Picks the territory size for an enemy amount (1 = normal).
function M.territory_index(amount)
  local radius = 384 / math.sqrt(amount)
  local best, best_d = 1, math.huge
  for i, r in ipairs(M.TERRITORY_RADII) do
    if math.abs(r - radius) < best_d then best, best_d = i, math.abs(r - radius) end
  end
  return best
end

return M
