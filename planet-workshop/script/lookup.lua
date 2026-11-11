-- What exists in this game, for lib/mapgen.lua at runtime (the designer preview). The loader has the same thing
-- built from data.raw (Builder:lookup in prototypes/build.lua); the kit info comes from the
-- "planet-workshop-kit" mod-data that the loader stores.

local kit = require("__planet-workshop__.lib.kit")

local M = {}

local function kit_info()
  local proto = prototypes.mod_data["planet-workshop-kit"]
  return proto and proto.data or {tile_home = {}, reference_colors = {}, styles = {PLANTS = {}, ROCKS = {}}, decoratives = {}}
end

--- A lookup for one planet (its own ores show as the kit's stand-in ores).
function M.for_planet(p)
  local info = kit_info()
  local ore_index = {}
  for i, ore in ipairs(p.ores or {}) do ore_index[ore.key] = i end
  return {
    tile = function(name)
      local t = prototypes.tile[name]
      return t and {autoplace = t.autoplace_specification ~= nil, color = t.map_color, fluid = t.fluid ~= nil} or nil
    end,
    tile_home = function(name) return info.tile_home[name] end,
    reference_colors = info.reference_colors,
    resource = function(name)
      local e = prototypes.entity[name]
      if not e or e.type ~= "resource" then return nil end
      return {fluid = (e.resource_category or ""):find("fluid") ~= nil, autoplace = e.autoplace_specification ~= nil}
    end,
    entity = function(name) return prototypes.entity[name] ~= nil end,
    cliff = function(name) return prototypes.entity[name] ~= nil and prototypes.entity[name].type == "cliff" end,
    decoratives = function(planet) return info.decoratives[planet] or {} end,
    pollutant = function(name) return prototypes.airborne_pollutant[name] ~= nil end,
    style_entities = function(kind, style) return info.styles[kind] and info.styles[kind][style] or {} end,
    ore_entity = function(key)
      local i = ore_index[key]
      return i and i <= kit.PREVIEW_ORES and kit.preview_ore(i) or nil
    end,
  }
end

return M
