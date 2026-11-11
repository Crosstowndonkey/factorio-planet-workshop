-- Runtime: tells players about planet codes that couldn't be fully loaded, adds the /planet-workshop command
-- that lists the loaded planets, and runs the starting-resources safety net (script/starting.lua).

local starting = require("script.starting")

script.on_event(defines.events.on_surface_created, starting.on_surface_created)

-- For tests and other mods: remote.call("planet-workshop", "ensure_start", surface_index, planet_name)
remote.add_interface("planet-workshop", {
  ensure_start = function(surface_index, planet_name)
    return starting.ensure(game.surfaces[surface_index], planet_name)
  end,
})

local function report()
  local proto = prototypes.mod_data["planet-workshop-report"]
  return proto and proto.data or {planets = {}, problems = {}}
end

local function tell_problems(target)
  local r = report()
  if #r.problems == 0 then return end
  target.print({"planet-workshop.problems-header", #r.problems})
  for i = 1, math.min(#r.problems, 10) do
    target.print(r.problems[i])
  end
  if #r.problems > 10 then target.print({"planet-workshop.more-problems", #r.problems - 10}) end
end

script.on_event(defines.events.on_player_created, function(e)
  tell_problems(game.get_player(e.player_index))
end)

script.on_configuration_changed(function()
  tell_problems(game)
end)

commands.add_command("planet-workshop", {"planet-workshop.command-help"}, function(cmd)
  local target = cmd.player_index and game.get_player(cmd.player_index) or game
  local r = report()
  target.print({"planet-workshop.loaded", #r.planets})
  for _, p in ipairs(r.planets) do
    target.print({"planet-workshop.loaded-planet", p.name, p.author or "?", p.code})
  end
  tell_problems(target)
end)
