-- Builds the planets from the codes in the startup setting. It runs in data-updates so that items, tiles and
-- technologies from other mods already exist and can be used by planets.
local codes = require("__planet-workshop__.lib.codes")
local build = require("__planet-workshop__.prototypes.build")
local kitdefs = require("__planet-workshop__.prototypes.kit")

kitdefs.define() -- the terrain kit every planet and the designer preview use

local found, problems = codes.read_all(settings.startup["planet-workshop-planets"].value)
local report = build.build_all(found, problems)
-- The starting planet (by name or id, any case), if one is set
local wanted = settings.startup["planet-workshop-start-planet"].value
if wanted ~= "" then
  local key = wanted:lower()
  for _, planet in ipairs(report.planets) do
    if planet.name:lower() == key or planet.id == key then
      report.start_planet = {planet = planet.planet, name = planet.name, discovery = planet.discovery}
    end
  end
  if not report.start_planet then problems[#problems + 1] = {"planet-workshop-problem.start-planet-missing", wanted} end
end
for _, problem in ipairs(problems) do
  log("Planet Workshop problem: " .. serpent.line(problem))
end
log("Planet Workshop: loaded " .. #report.planets .. " planet(s)")

data:extend{
  {type = "mod-data", name = "planet-workshop-report", data = report},
  {type = "mod-data", name = "planet-workshop-kit", data = kitdefs.runtime_info()},
}
