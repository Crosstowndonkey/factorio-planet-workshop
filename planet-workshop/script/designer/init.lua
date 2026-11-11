-- The Planet Designer (runtime): started by the Planet Designer scenario (remote "start_designer"). Handles the
-- window's events and actions; the window is script/designer/gui.lua, the preview script/designer/preview.lua and
-- the saved designs script/designer/state.lua.

local util = require("util")
local codes = require("__planet-workshop__.lib.codes")
local spec = require("__planet-workshop__.lib.spec")
local state = require("__planet-workshop__.script.designer.state")
local preview = require("__planet-workshop__.script.designer.preview")
local gui = require("__planet-workshop__.script.designer.gui")
local W = require("__planet-workshop__.script.designer.widgets")
local production = require("__planet-workshop__.script.designer.production")

local M = {}

--- Ground tiles offered when "Add ground tile" is pressed (the first one not used yet).
local NEW_GROUND = {"dirt-4", "grass-1", "red-desert-0", "sand-2", "volcanic-ash-dark", "snow-flat", "fulgoran-sand",
  "midland-turquoise-bark"}

function M.setup_player(player)
  if player.controller_type ~= defines.controllers.god then
    local body = player.character
    player.set_controller{type = defines.controllers.god}
    if body and body.valid then body.destroy() end
  end
  -- a quiet room: no minimap, research hint, quickbar or shortcut bar
  local view = player.game_view_settings
  view.show_minimap = false
  view.show_research_info = false
  view.show_quickbar = false
  view.show_shortcut_bar = false
  player.game_view_settings = view
  state.current(player)
  preview.refresh(player)
  gui.build(player)
end

function M.start()
  if state.active() then return end
  state.start()
  log("Planet Workshop: Planet Designer started")
  local room = game.surfaces.nauvis -- the designer's own room: an empty lab floor
  room.generate_with_lab_tiles = true
  room.always_day = true
  room.clear(true)
  for _, player in pairs(game.players) do M.setup_player(player) end
end

local function refresh_now(player)
  preview.refresh(player)
  gui.build(player)
end

--- Applies a change to the current planet. `rebuild`: redraw the window (for anything that changes its layout).
function M.set(player, path, value, rebuild)
  local design, ps = state.current(player)
  ps.confirm_delete = nil
  if path == "space.orientation" then value = (value / 360) % 1 end
  state.set(design, path, value)
  if state.affects_map(path) then preview.schedule(player.index, rebuild and 1 or 30) end
  if rebuild then gui.build(player) end
end

-- Actions (buttons) ------------------------------------------------------------------------------------------

local ACTIONS = {}

function ACTIONS.new(player, ps)
  table.insert(storage.designer.designs, state.blank(player))
  ps.current = #storage.designer.designs
  refresh_now(player)
end

function ACTIONS.copy(player, ps)
  local design = state.current(player)
  local copy = util.table.deepcopy(design)
  copy.id = state.new_id(player)
  copy.name = (design.name or "Planet") .. " (copy)"
  table.insert(storage.designer.designs, copy)
  ps.current = #storage.designer.designs
  refresh_now(player)
end

function ACTIONS.delete(player, ps)
  if ps.confirm_delete and game.tick - ps.confirm_delete <= 600 then
    table.remove(storage.designer.designs, ps.current)
    ps.confirm_delete = nil
    ps.current = math.max(1, ps.current - 1)
    refresh_now(player)
  else
    ps.confirm_delete = game.tick
    gui.build(player)
  end
end

ACTIONS["add-ground"] = function(player)
  local design = state.current(player)
  local used = {}
  for _, g in ipairs(design.terrain.ground) do used[g.tile] = true end
  for _, tile in ipairs(NEW_GROUND) do
    if not used[tile] and prototypes.tile[tile] then
      table.insert(design.terrain.ground, {tile = tile, share = 1})
      break
    end
  end
  preview.schedule(player.index, 1)
  gui.build(player)
end

function ACTIONS.remove(player, _, tags)
  local design = state.current(player)
  local list = state.get(design, tags.path)
  if tags.path == "ores" and list and list[tags.index] then -- an ore stops generating with it
    local ref = "@ore:" .. list[tags.index].key
    for i = #design.resources, 1, -1 do
      if design.resources[i].resource == ref then table.remove(design.resources, i) end
    end
  end
  if list and list[tags.index] then table.remove(list, tags.index) end
  preview.schedule(player.index, 1)
  gui.build(player)
end

function ACTIONS.zoom(player, ps, tags)
  ps.zoom = math.max(1, math.min(#state.ZOOMS, ps.zoom + tags.by))
  gui.build(player)
end

function ACTIONS.reseed(player, ps)
  ps.seed = (ps.seed * 48271 + 12345) % 2147483647
  refresh_now(player)
end

function ACTIONS.walk(player, ps)
  if ps.walking then
    player.teleport({0, 0}, game.surfaces.nauvis)
    ps.walking = false
  else
    local surface = game.surfaces[preview.surface_name(player.index)]
    if surface then
      player.teleport({0, 0}, surface)
      ps.walking = true
    end
  end
  gui.build(player)
end

function ACTIONS.section(player, ps, tags)
  ps.section = tags.key
  gui.build(player)
end

--- Adds a copy of tags.template to the list at tags.path.
function ACTIONS.add(player, _, tags)
  local design = state.current(player)
  local list = state.get(design, tags.path)
  if type(list) ~= "table" then
    list = {}
    state.set(design, tags.path, list)
  end
  table.insert(list, util.table.deepcopy(tags.template))
  if state.affects_map(tags.path) then preview.schedule(player.index, 1) end
  gui.build(player)
end

--- A key not used yet in a list ("ore1", "ore2"...).
local function new_key(list, prefix)
  local used = {}
  for _, entry in ipairs(list or {}) do used[entry.key] = true end
  local i = 1
  while used[prefix .. i] do i = i + 1 end
  return prefix .. i
end

ACTIONS["add-ore"] = function(player, _, tags)
  local design = state.current(player)
  design.ores = design.ores or {}
  local fluid = tags.kind == "fluid"
  local key = new_key(design.ores, fluid and "fluid" or "ore")
  table.insert(design.ores, {key = key, kind = tags.kind, name = fluid and "New fluid" or "New ore",
    base = fluid and "crude-oil" or "iron-ore", tint = {r = 0.75, g = 0.55, b = 1}, mining_time = 1, stack_size = 50})
  -- it generates on the planet straight away (it can be tuned or removed under Resources)
  table.insert(design.resources, {resource = "@ore:" .. key, frequency = 1, size = 1, richness = 1})
  preview.schedule(player.index, 1)
  gui.build(player)
end

ACTIONS["add-recipe"] = function(player)
  local design = state.current(player)
  design.recipes = design.recipes or {}
  table.insert(design.recipes, {key = new_key(design.recipes, "recipe"), name = "New recipe",
    ingredients = {{name = "iron-plate", amount = 1}}, results = {{name = "iron-gear-wheel", amount = 1}},
    category = "crafting", time = 1, only_here = false, enabled = false})
  gui.build(player)
end

ACTIONS["add-technology"] = function(player)
  local design = state.current(player)
  design.technologies = design.technologies or {}
  table.insert(design.technologies, {key = new_key(design.technologies, "tech"), name = "New research",
    prerequisites = {"@discovery"}, count = 500, time = 30,
    ingredients = {{name = design.science and "@pack" or "automation-science-pack", amount = 1}},
    infinite = false, effects = {}})
  gui.build(player)
end

ACTIONS["get-code"] = function(player) gui.show_code(player) end
ACTIONS["import-open"] = function(player) gui.show_import(player) end

--- Adds the planets in a code to the designs (a planet with the same id replaces the old one: it's an update).
--- Returns how many were added or updated, and the problems.
function M.import(player, text)
  local found, problems = codes.read_all(text)
  local designs, count = storage.designer.designs, 0
  for _, entry in ipairs(found) do
    if spec.normalize(entry.planet, problems) then
      local replaced = false
      for i, d in ipairs(designs) do
        if d.id == entry.planet.id then
          designs[i] = entry.planet
          replaced = true
          state.player(player.index).current = i
        end
      end
      if not replaced then
        table.insert(designs, entry.planet)
        state.player(player.index).current = #designs
      end
      count = count + 1
    end
  end
  return count, problems
end

ACTIONS["import-do"] = function(player)
  local window = player.gui.screen[gui.IMPORT]
  local text = window and window.code and window.code.text or ""
  local count, problems = M.import(player, text)
  if count > 0 then
    window.destroy()
    player.print({"planet-workshop-designer.imported", count})
    for _, problem in ipairs(problems) do player.print(problem) end
    refresh_now(player)
  else
    gui.show_import(player, problems[1] or {"planet-workshop-designer.import-nothing"})
  end
end

function ACTIONS.close(player, _, tags)
  if player.gui.screen[tags.window] then player.gui.screen[tags.window].destroy() end
end

function ACTIONS.minimize(player, ps)
  ps.minimized = true
  gui.build(player)
end

function ACTIONS.restore(player, ps)
  ps.minimized = false
  gui.build(player)
end

-- Events --------------------------------------------------------------------------------------------------------

local function ours(event)
  local el = event.element
  if not (state.active() and el and el.valid) then return nil end
  local tags = el.tags
  if not tags or not tags.pw then return nil end
  return el, tags, game.get_player(event.player_index)
end

function M.on_gui_click(event)
  local el, tags, player = ours(event)
  if not el then return end
  local action = ACTIONS[tags.pw]
  if action then
    local ps = state.player(player.index)
    if tags.pw ~= "delete" then ps.confirm_delete = nil end
    action(player, ps, tags)
  end
end

function M.on_gui_value_changed(event)
  local el, tags, player = ours(event)
  if not el then return end
  local value = el.slider_value
  local caption
  if tags.pw == "amount" then
    value = state.AMOUNTS[math.floor(value + 0.5)]
    caption = string.format("%d%%", math.floor(value * 100 + 0.5))
  elseif tags.pw == "number" then
    value = math.floor(value * 10 + 0.5) / 10
    caption = {"planet-workshop-designer.unit-" .. tags.unit, tostring(value)}
  elseif tags.pw == "tint" then
    local design = state.current(player)
    local tint = spec.color(state.get(design, tags.path)) or {r = 1, g = 1, b = 1}
    tint[tags.channel] = math.floor(value + 0.5) / 255
    state.set(design, tags.path, tint)
    if el.parent.pw_value then el.parent.pw_value.caption = tostring(math.floor(value + 0.5)) end
    local holder = el.parent.parent -- the swatch is in the first row of the sliders' block
    local first = holder and holder.children[1]
    if first and first.pw_swatch then first.pw_swatch.caption = W.swatch_text(tint) end
    return
  else
    return
  end
  if el.parent.pw_value then el.parent.pw_value.caption = caption end
  M.set(player, tags.path, value, false)
end

function M.on_gui_selection_state_changed(event)
  local el, tags, player = ours(event)
  if not el then return end
  local ps = state.player(player.index)
  if tags.pw == "pick" then
    M.set(player, tags.path, tags.values[el.selected_index], true)
  elseif tags.pw == "starting" then
    local choice = gui.STARTING[el.selected_index]
    local value = nil
    if choice == "yes" then value = true elseif choice == "no" then value = false end
    M.set(player, tags.path, value, true)
  elseif tags.pw == "ref-source" then
    local i = el.selected_index
    if i == 1 then
      M.set(player, tags.path, W.GAME_DEFAULT[tags.kind], true)
    else
      M.set(player, tags.path, tags.refs[i - 1], true)
    end
  elseif tags.pw == "effect-type" then
    local kind = production.EFFECTS[el.selected_index]
    local effect = {type = kind}
    if kind == "unlock-recipe" or kind == "change-recipe-productivity" then effect.recipe = "@pack" end
    if kind == "change-recipe-productivity" then effect.change = 0.1 elseif kind ~= "unlock-recipe" then effect.modifier = 0.1 end
    M.set(player, tags.path, effect, true)
  elseif tags.pw == "select-design" then
    ps.current = el.selected_index
    ps.confirm_delete = nil
    refresh_now(player)
  end
end

function M.on_gui_checked_state_changed(event)
  local el, tags, player = ours(event)
  if not el then return end
  local design = state.current(player)
  if tags.pw == "check" then
    if tags.path == "look.use_tint" then
      design.look.tint = el.state and {r = 1, g = 1, b = 1} or nil
      gui.build(player)
    else
      M.set(player, tags.path, el.state, true)
    end
  elseif tags.pw == "science-on" then
    if el.state then
      design.science = {name = (design.name or "Planet") .. " science pack", tint = {r = 0.75, g = 0.55, b = 1},
        base = "automation-science-pack", ingredients = {{name = "iron-plate", amount = 1}}, count = 1, time = 5,
        category = "crafting", only_here = true, spoil_minutes = 0}
    else
      design.science = nil
    end
    gui.build(player)
  elseif tags.pw == "style" then
    local list = state.get(design, tags.path) or {}
    local kept = {}
    for _, s in ipairs(list) do if s ~= tags.style then kept[#kept + 1] = s end end
    if el.state then kept[#kept + 1] = tags.style end
    M.set(player, tags.path, kept, true)
  end
end

function M.on_gui_elem_changed(event)
  local el, tags, player = ours(event)
  if not el then return end
  local value = el.elem_value
  if tags.pw == "elem" then
    if value then M.set(player, tags.path, value, true) else gui.build(player) end
  elseif tags.pw == "ref-elem" then
    if type(value) == "table" then -- a signal: only items and fluids count
      value = (value.type == nil or value.type == "item" or value.type == "fluid") and value.name or nil
    end
    if value then M.set(player, tags.path, value, true) else gui.build(player) end
  elseif tags.pw == "add-resource" and value then
    local design = state.current(player)
    for _, res in ipairs(design.resources) do
      if res.resource == value then return gui.build(player) end
    end
    table.insert(design.resources, {resource = value, frequency = 1, size = 1, richness = 1})
    preview.schedule(player.index, 1)
    gui.build(player)
  end
end

function M.on_gui_text_changed(event)
  local el, tags, player = ours(event)
  if not el then return end
  if tags.pw == "text" then
    M.set(player, tags.path, el.text, false)
  elseif tags.pw == "num" then
    local n = tonumber(el.text)
    if n then M.set(player, tags.path, n * (tags.scale or 1), false) end
  end
end

function M.on_tick()
  if not state.active() then return end
  preview.generate_due()
  for _, index in ipairs(preview.take_due()) do
    local player = game.get_player(index)
    if player and player.valid then
      preview.refresh(player)
      if player.gui.screen[gui.ROOT] and not gui.has_camera(player) then gui.build(player) else gui.update_status(player) end
    end
  end
end

function M.on_player_created(event)
  if state.active() then M.setup_player(game.get_player(event.player_index)) end
end

-- For tests: drive the designer the way the window does.
M.remote = {
  start_designer = M.start,
  designer_set = function(player_index, path, value)
    M.set(game.get_player(player_index), path, value, true)
  end,
  designer_do = function(player_index, action, tags)
    local player = game.get_player(player_index)
    ACTIONS[action](player, state.player(player_index), tags or {})
  end,
  designer_import = function(player_index, text)
    local count = M.import(game.get_player(player_index), text)
    refresh_now(game.get_player(player_index))
    return count
  end,
  designer_code = function(player_index)
    return codes.encode({state.current(game.get_player(player_index))})
  end,
  designer_designs = function() return storage.designer and storage.designer.designs end,
  designer_tab = function(player_index, section) -- a section name, or its number in the sidebar
    state.player(player_index).section = type(section) == "number" and gui.SECTIONS[section] or section
    gui.build(game.get_player(player_index))
  end,
  -- runs a GUI handler on a real element, as if the player had used it
  designer_event = function(handler, event) M[handler](event) end,
  designer_player = function(player_index) return storage.designer and storage.designer.players[player_index] end,
  designer_preview_now = function(player_index)
    local player = game.get_player(player_index)
    refresh_now(player)
    return preview.surface_name(player_index)
  end,
}

return M
