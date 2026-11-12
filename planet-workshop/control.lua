-- Runtime: tells players about planet codes that couldn't be fully loaded, adds the /planet-workshop command that
-- lists the loaded planets, runs the starting-resources safety net (script/starting.lua) and the Planet Designer
-- (script/designer, started by the Planet Designer scenario) and moves new games to the starting planet, if one is
-- set (script/startplanet.lua).

local starting = require("script.starting")
local designer = require("script.designer.init")
local startplanet = require("script.startplanet")

script.on_init(startplanet.on_init)

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

script.on_event(defines.events.on_player_created, function(event)
  tell_problems(game.get_player(event.player_index))
  startplanet.on_player_created(event)
  designer.on_player_created(event)
end)

script.on_configuration_changed(function()
  tell_problems(game)
end)

script.on_event(defines.events.on_surface_created, starting.on_surface_created)
script.on_event(defines.events.on_tick, designer.on_tick)
script.on_event(defines.events.on_player_died, function(event)
  startplanet.on_player_died(event)
  designer.on_player_died(event)
end)
script.on_event(defines.events.on_player_respawned, function(event)
  startplanet.on_player_respawned(event)
  designer.on_player_respawned(event)
end)
script.on_event(defines.events.on_player_selected_area, designer.on_player_selected_area)
script.on_event(defines.events.on_player_alt_selected_area, designer.on_player_alt_selected_area)
script.on_event(defines.events.on_gui_click, designer.on_gui_click)
script.on_event(defines.events.on_gui_value_changed, designer.on_gui_value_changed)
script.on_event(defines.events.on_gui_selection_state_changed, designer.on_gui_selection_state_changed)
script.on_event(defines.events.on_gui_checked_state_changed, designer.on_gui_checked_state_changed)
script.on_event(defines.events.on_gui_elem_changed, designer.on_gui_elem_changed)
script.on_event(defines.events.on_gui_text_changed, designer.on_gui_text_changed)

-- remote.call("planet-workshop", ...): "ensure_start" (the safety net, for tests and other mods),
-- "start_designer" (the scenario) and the designer_* calls the tests use.
local interface = {
  ensure_start = function(surface_index, planet_name)
    return starting.ensure(game.surfaces[surface_index], planet_name)
  end,
}
for name, fn in pairs(designer.remote) do interface[name] = fn end
remote.add_interface("planet-workshop", interface)

commands.add_command("planet-workshop", {"planet-workshop.command-help"}, function(cmd)
  local target = cmd.player_index and game.get_player(cmd.player_index) or game
  local r = report()
  target.print({"planet-workshop.loaded", #r.planets})
  for _, p in ipairs(r.planets) do
    target.print({"planet-workshop.loaded-planet", p.name, p.author or "?", p.code})
    for _, c in ipairs(p.credits or {}) do target.print({"", "    ", {"planet-workshop.based-on", c.name, c.author}}) end
  end
  tell_problems(target)
end)
