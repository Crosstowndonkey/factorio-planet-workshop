-- Builds the planets from the codes in the startup setting. It runs in data-updates so that items, tiles and
-- technologies from other mods already exist and can be used by planets.
local codes = require("__planet-workshop__.lib.codes")
local build = require("__planet-workshop__.prototypes.build")
local kitdefs = require("__planet-workshop__.prototypes.kit")

kitdefs.define() -- the terrain kit every planet and the designer preview use

local found, problems = codes.read_all(settings.startup["planet-workshop-planets"].value)
local report = build.build_all(found, problems)
for _, problem in ipairs(problems) do
  log("Planet Workshop problem: " .. serpent.line(problem))
end
log("Planet Workshop: loaded " .. #report.planets .. " planet(s)")

data:extend{
  {type = "mod-data", name = "planet-workshop-report", data = report},
  {type = "mod-data", name = "planet-workshop-kit", data = kitdefs.runtime_info()},
}
