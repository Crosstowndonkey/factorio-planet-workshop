-- Editing a hand-made start area: the player goes into Factorio's own map editor on their preview, changes the
-- area inside the circle, and Save keeps the changes (script/startarea.lua).
--
-- How: the preview is made fresh without the changes, and a "before" picture is taken (after the safety net,
-- as on the real planet); then the changes made so far are put back and the editor opens. On Save, a picture
-- of the area is compared with the "before" picture, and the differences become the start area's changes.
-- The planet's own ores aren't in the editor's lists (they're hidden stand-ins until the planet is loaded), so
-- the bar has an ore brush for them (a selection tool: drag to place, shift-drag to clear ores).

local state = require("__planet-workshop__.script.designer.state")
local preview = require("__planet-workshop__.script.designer.preview")
local gui = require("__planet-workshop__.script.designer.gui")
local startarea = require("__planet-workshop__.script.startarea")

local M = {}

local BAR = "pw_start_bar"
M.BRUSH = "pw-ore-brush"

local function L(key, ...) return {"planet-workshop-designer." .. key, ...} end

local function edit_base()
  storage.designer.edit_base = storage.designer.edit_base or {}
  return storage.designer.edit_base
end

local function bar(player, design)
  local ps = state.player(player.index)
  if player.gui.top[BAR] then player.gui.top[BAR].destroy() end
  local frame = player.gui.top.add{type = "frame", name = BAR, direction = "vertical"}
  local top = frame.add{type = "flow", direction = "horizontal"}
  top.style.vertical_align = "center"
  top.add{type = "label", caption = L("start-editing", design.name), style = "caption_label"}
  top.add{type = "button", caption = L("start-save"), style = "confirm_button_without_tooltip", tags = {pw = "start-save"}}
  top.add{type = "button", caption = L("start-cancel"), style = "red_button", tags = {pw = "start-cancel"}}
  local hint = frame.add{type = "label", caption = L("start-editing-hint")}
  hint.style.single_line = false
  hint.style.maximal_width = 520
  hint.style.font_color = {0.8, 0.8, 0.8}
  if #(design.ores or {}) > 0 then
    local f = frame.add{type = "flow", direction = "horizontal"}
    f.style.vertical_align = "center"
    f.add{type = "label", caption = L("start-own-ores")}
    local items, keys = {}, {}
    for i, ore in ipairs(design.ores) do
      items[i] = ore.name or ore.key
      keys[i] = ore.key
    end
    local current = 1
    for i, k in ipairs(keys) do if k == ps.brush then current = i end end
    ps.brush = keys[current]
    f.add{type = "drop-down", items = items, selected_index = current, tags = {pw = "brush-ore", values = keys}}
    f.add{type = "label", caption = L("start-amount")}
    local amount = f.add{type = "textfield", text = tostring(ps.brush_amount or 1000), numeric = true,
      tags = {pw = "brush-amount"}}
    amount.style.width = 70
    f.add{type = "button", caption = L("start-brush"), tooltip = L("start-brush-tooltip"), tags = {pw = "brush"}}
  end
end

--- "Edit start area": a fresh preview without the changes; the editor opens two ticks later (see M.begin).
function M.request(player)
  local design, ps = state.current(player)
  if not design.start or ps.editing or ps.testing then return end
  storage.designer.due[player.index] = nil
  ps.base_only = true
  preview.refresh(player) -- (clear() happens at the end of this tick)
  ps.editing = {pending = true}
  storage.designer.edit_start = storage.designer.edit_start or {}
  storage.designer.edit_start[player.index] = game.tick + 2
end

function M.begin(player)
  local design, ps = state.current(player)
  storage.designer.edit_start[player.index] = nil
  local surface = game.surfaces[preview.surface_name(player.index)]
  if not (surface and design.start) then
    ps.editing, ps.base_only = nil, nil
    return
  end
  -- the world as generated (with the safety net), then the "before" picture, then the changes so far
  local d = storage.designer
  if d.generate then d.generate[player.index] = nil end
  if d.settling then d.settling[player.index] = nil end
  surface.request_to_generate_chunks({0, 0}, preview.RADIUS)
  surface.force_generate_chunk_requests()
  preview.settle(player.index)
  ps.base_only = nil
  local radius = design.start.radius
  edit_base()[player.index] = startarea.snapshot(surface, radius)
  startarea.apply(surface, design.start, preview.resolver(design))
  if d.chart then d.chart[player.index] = game.tick + 120 end -- (the camera, later, shows the changes)

  gui.destroy(player)
  player.teleport({0, 0}, surface)
  local ok = pcall(player.set_controller, {type = defines.controllers.editor})
  if not ok or player.controller_type ~= defines.controllers.editor then
    player.teleport({0, 0}, game.surfaces.nauvis)
    ps.editing = nil
    edit_base()[player.index] = nil
    player.print(L("start-needs-admin"))
    preview.refresh(player)
    gui.build(player)
    return
  end
  game.tick_paused = false -- (the editor pauses the game; keep it running, for other players and the designer)
  player.zoom = math.max(0.2, math.min(1, 900 / (2 * radius * 32))) -- the whole circle in view
  ps.editing = {tick = game.tick}
  bar(player, design)
end

--- The planet's own ores' entity names -> "@ore:<key>".
local function ore_refs(design)
  local resolve = preview.resolver(design)
  local refs = {}
  for _, ore in ipairs(design.ores or {}) do
    local name = resolve("@ore:" .. ore.key)
    if name then refs[name] = "@ore:" .. ore.key end
  end
  return function(name) return refs[name] or name end
end

--- Leaves the editor; `save`: keep the changes.
function M.finish(player, save)
  local design, ps = state.current(player)
  if not (ps.editing and not ps.editing.pending) then return end
  local surface = game.surfaces[preview.surface_name(player.index)]
  local before = edit_base()[player.index]
  if save and surface and before and design.start then
    local after = startarea.snapshot(surface, design.start.radius)
    local changes, others = startarea.diff(before, after, design.start.radius, ore_refs(design))
    for k, v in pairs(changes) do design.start[k] = v end
    local tiles, added, removed = startarea.count(design.start)
    player.print(L("start-saved", tiles, added, removed))
    if others > 0 then player.print(L("start-not-kept", others)) end
  end
  edit_base()[player.index] = nil
  if player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name == M.BRUSH then
    player.cursor_stack.clear()
  end
  player.set_controller{type = defines.controllers.god}
  player.teleport({0, 0}, game.surfaces.nauvis)
  game.tick_paused = false -- (the editor's time controls may have paused the game)
  if player.gui.top[BAR] then player.gui.top[BAR].destroy() end
  ps.editing = nil
  preview.refresh(player)
  gui.build(player)
end

function M.on_tick()
  for index, tick in pairs(storage.designer.edit_start or {}) do
    if game.tick >= tick then
      local player = game.get_player(index)
      if player and player.valid then M.begin(player) else storage.designer.edit_start[index] = nil end
    end
  end
end

--- The ore brush: gives the player the selection tool.
function M.give_brush(player)
  if player.cursor_stack and player.clear_cursor() then player.cursor_stack.set_stack{name = M.BRUSH, count = 1} end
end

--- Dragging the ore brush: fills the area with the chosen own ore (a fluid ore: one well in the middle);
--- shift-dragging clears all ores in the area.
function M.on_selected_area(event, alt)
  if event.item ~= M.BRUSH then return end
  local player = game.get_player(event.player_index)
  local design, ps = state.current(player)
  if not (ps.editing and design.start) then return end
  local surface = event.surface
  local radius = design.start.radius
  local area = event.area
  local x1, y1 = math.floor(area.left_top.x), math.floor(area.left_top.y)
  local x2, y2 = math.ceil(area.right_bottom.x) - 1, math.ceil(area.right_bottom.y) - 1
  if alt then
    for _, e in pairs(surface.find_entities_filtered{area = area, type = "resource"}) do
      if startarea.inside(e.position.x, e.position.y, radius) then e.destroy() end
    end
    return
  end
  local ore
  for _, o in ipairs(design.ores or {}) do if o.key == ps.brush then ore = o end end
  if not ore then return end
  local name = preview.resolver(design)("@ore:" .. ore.key)
  if not (name and prototypes.entity[name]) then return end
  local amount = math.max(1, math.floor(ps.brush_amount or 1000))
  if ore.kind == "fluid" then
    local pos = {x = math.floor((x1 + x2) / 2) + 0.5, y = math.floor((y1 + y2) / 2) + 0.5}
    if startarea.inside(pos.x, pos.y, radius) and surface.can_place_entity{name = name, position = pos} then
      surface.create_entity{name = name, position = pos, amount = amount * 100, create_build_effect_smoke = false}
    end
    return
  end
  for x = x1, x2 do
    for y = y1, y2 do
      local pos = {x = x + 0.5, y = y + 0.5}
      if startarea.inside(pos.x, pos.y, radius) and not surface.get_tile(x, y).prototype.fluid then
        for _, e in pairs(surface.find_entities_filtered{position = pos, radius = 0.4, type = "resource"}) do e.destroy() end
        surface.create_entity{name = name, position = pos, amount = amount, create_build_effect_smoke = false}
      end
    end
  end
end

M.BAR = BAR

return M
