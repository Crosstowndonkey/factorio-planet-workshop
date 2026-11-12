-- The Planet Designer window: a planet list and toolbar, a sidebar of sections, the section, the live preview, and
-- problems at the bottom. Every input carries tags saying what it changes (tags.path in the planet table), so
-- one handler per event type covers them all. Changing a list (adding a ground tile, switching planets...)
-- rebuilds the window; dragging a slider only updates its label, so dragging stays smooth.

local catalog = require("__planet-workshop__.lib.catalog")
local spec = require("__planet-workshop__.lib.spec")
local state = require("__planet-workshop__.script.designer.state")
local preview = require("__planet-workshop__.script.designer.preview")

local checks = require("__planet-workshop__.script.designer.checks")
local share = require("__planet-workshop__.script.designer.share")
local startarea = require("__planet-workshop__.script.startarea")

local W = require("__planet-workshop__.script.designer.widgets")
local production = require("__planet-workshop__.script.designer.production")

local M = {}

local ROOT, CODE, IMPORT, MINI = "pw_designer", "pw_designer_code", "pw_designer_import", "pw_designer_mini"
local LEFT_WIDTH, VIEW, SIDEBAR = W.LEFT_WIDTH, 540, 150

local SHAPES = {"lakes", "big-lakes", "island", "archipelago", "continents"}
local LIQUIDS = {"water", "lava", "oil", "ammonia", "slime", "none"}
local CLIFFS = {"none", "nauvis", "vulcanus", "gleba", "fulgora"}
local PLANTS = {"forest", "dry-trees", "lichen", "gleba-plants"}
local ROCKS = {"rocks", "volcanic-rocks", "fulgora-rocks", "ruins", "icebergs", "stromatolites"}
local ENEMIES = {"none", "biters", "pentapods", "demolishers"}
local PICTURES = {"auto", "nauvis", "vulcanus", "gleba", "fulgora", "aquilo"}
local STARTING = {"default", "yes", "no"}
local ASTEROIDS = {}
for name in pairs(spec.ASTEROIDS) do ASTEROIDS[#ASTEROIDS + 1] = name end
table.sort(ASTEROIDS)

--- The sidebar: sections in groups. (Their order is also the numbering the tests use.)
local GROUPS = {
  {name = "world", sections = {"general", "terrain", "nature", "resources", "enemies", "start"}},
  {name = "planet", sections = {"physics", "space", "look"}},
  {name = "production", sections = {"ores", "science", "recipes", "research"}},
  {name = "test", sections = {"checks", "testplay"}},
}
M.SECTIONS = {}
for _, g in ipairs(GROUPS) do
  for _, key in ipairs(g.sections) do M.SECTIONS[#M.SECTIONS + 1] = key end
end

local L, index_of, row, heading, hint = W.L, W.index_of, W.row, W.heading, W.hint
local dropdown, amount_slider, number_slider, checkbox = W.dropdown, W.amount_slider, W.number_slider, W.checkbox

-- The world and planet sections ----------------------------------------------------------------------------------------------------

local function tab_general(c, d, ps, player)
  -- someone else's planet, and who it's based on
  if share.foreign(d, player) then
    local banner = hint(c, L("imported-banner", d.author or "?"))
    banner.style.font_color = {1, 0.85, 0.5}
  end
  for _, credit in ipairs(d.credits or {}) do
    hint(c, L("based-on", credit.name or "?", credit.author or "?"))
  end
  local f = row(c, L("name"))
  local name = f.add{type = "textfield", text = d.name or "", tags = {pw = "text", path = "name"}}
  name.style.width = 300
  f = row(c, L("author"))
  local author = f.add{type = "textfield", text = d.author or "", tags = {pw = "text", path = "author"}}
  author.style.width = 300
  heading(c, L("description"))
  local box = c.add{type = "text-box", text = d.description or "", tags = {pw = "text", path = "description"}}
  box.word_wrap = true
  box.style.width = LEFT_WIDTH - 30
  box.style.height = 120
  hint(c, L("general-hint"))
  heading(c, L("starting-planet"))
  checkbox(c, L("starting-planet-check"), "starting_planet", d.starting_planet == true, L("starting-planet-tooltip"))
  hint(c, L("starting-planet-hint", d.name or ""))
end

local function tab_terrain(c, d)
  local t = d.terrain
  heading(c, L("land"))
  dropdown(c, L("shape"), "terrain.shape", SHAPES, "shape", t.shape, L("shape-tooltip"))
  dropdown(c, L("liquid"), "terrain.liquid", LIQUIDS, "liquid", t.liquid)
  if t.liquid ~= "none" then amount_slider(c, L("liquid-amount"), "terrain.liquid_amount", t.liquid_amount) end

  heading(c, L("ground"))
  hint(c, L("ground-hint"))
  for i, g in ipairs(t.ground) do
    local f = c.add{type = "flow", direction = "horizontal"}
    f.style.vertical_align = "center"
    f.add{type = "choose-elem-button", elem_type = "tile", tile = g.tile, elem_filters = {{filter = "autoplace"}},
      tags = {pw = "elem", path = "terrain.ground." .. i .. ".tile"}}
    local label = f.add{type = "label", caption = prototypes.tile[g.tile] and prototypes.tile[g.tile].localised_name or g.tile}
    label.style.width = 170
    f.add{type = "label", caption = L("share")}
    local slider = f.add{type = "slider", minimum_value = 1, maximum_value = 10, value_step = 1, discrete_slider = true,
      value = math.max(1, math.min(10, g.share or 1)), tags = {pw = "number", path = "terrain.ground." .. i .. ".share", unit = "share"}}
    slider.style.width = 120
    f.add{type = "label", name = "pw_value", caption = {"planet-workshop-designer.unit-share", tostring(g.share or 1)}}
    f.add{type = "sprite-button", sprite = "utility/close", style = "tool_button_red", tooltip = L("remove"),
      tags = {pw = "remove", path = "terrain.ground", index = i}, enabled = #t.ground > 1}
  end
  if #t.ground < 12 then
    c.add{type = "button", caption = L("add-ground"), tags = {pw = "add-ground"}}
  end
  amount_slider(c, L("patch-size"), "terrain.patch_size", t.patch_size, L("patch-size-tooltip"))

  heading(c, L("cliffs"))
  dropdown(c, L("cliff-style"), "terrain.cliffs.style", CLIFFS, "cliffs", t.cliffs.style)
  if t.cliffs.style ~= "none" then amount_slider(c, L("amount"), "terrain.cliffs.amount", t.cliffs.amount) end
end

local function styles_block(c, caption, path, all, chosen, amount, prefix)
  heading(c, caption)
  local set = {}
  for _, s in ipairs(chosen) do set[s] = true end
  local table_el = c.add{type = "table", column_count = 3}
  table_el.style.horizontal_spacing = 16
  table_el.style.vertical_spacing = 6
  for _, s in ipairs(all) do
    local box = table_el.add{type = "checkbox", caption = L(prefix .. "-" .. s), state = set[s] == true,
      tags = {pw = "style", path = path .. ".styles", style = s}}
    box.style.minimal_width = 190
  end
  if #chosen > 0 then amount_slider(c, L("amount"), path .. ".amount", amount) end
end

local function tab_nature(c, d)
  local t = d.terrain
  styles_block(c, L("plants"), "terrain.plants", PLANTS, t.plants.styles, t.plants.amount, "plants")
  styles_block(c, L("rocks"), "terrain.rocks", ROCKS, t.rocks.styles, t.rocks.amount, "rocks")
  hint(c, L("rocks-hint"))
  heading(c, L("decorations"))
  checkbox(c, L("decorations-check"), "terrain.decorations", t.decorations ~= false, L("decorations-tooltip"))
end

local function tab_resources(c, d)
  hint(c, L("resources-hint"))
  for i, res in ipairs(d.resources) do
    local box = c.add{type = "frame", direction = "vertical", style = "bordered_frame"}
    box.style.horizontally_stretchable = true
    local top = box.add{type = "flow", direction = "horizontal"}
    top.style.vertical_align = "center"
    local own = res.resource:sub(1, 1) == "@"
    if own then
      local ore
      for _, o in ipairs(d.ores or {}) do if "@ore:" .. o.key == res.resource then ore = o end end
      top.add{type = "label", caption = ore and L("own-ore-resource", ore.name or ore.key) or res.resource}.style.width = 200
    else
      top.add{type = "choose-elem-button", elem_type = "entity", entity = res.resource,
        elem_filters = {{filter = "type", type = "resource"}}, tags = {pw = "elem", path = "resources." .. i .. ".resource"}}
      local proto = prototypes.entity[res.resource]
      top.add{type = "label", caption = proto and proto.localised_name or res.resource}.style.width = 160
    end
    top.add{type = "label", caption = L("starting")}
    local start = res.starting == true and "yes" or res.starting == false and "no" or "default"
    top.add{type = "drop-down", items = {L("starting-default"), L("starting-yes"), L("starting-no")},
      selected_index = index_of(STARTING, start), tags = {pw = "starting", path = "resources." .. i .. ".starting"}}
    top.add{type = "sprite-button", sprite = "utility/close", style = "tool_button_red", tooltip = L("remove"),
      tags = {pw = "remove", path = "resources", index = i}}
    amount_slider(box, L("frequency"), "resources." .. i .. ".frequency", res.frequency or 1)
    amount_slider(box, L("size"), "resources." .. i .. ".size", res.size or 1)
    amount_slider(box, L("richness"), "resources." .. i .. ".richness", res.richness or 1)
  end
  local f = c.add{type = "flow", direction = "horizontal"}
  f.style.vertical_align = "center"
  f.add{type = "label", caption = L("add-resource")}
  f.add{type = "choose-elem-button", elem_type = "entity", elem_filters = {{filter = "type", type = "resource"}},
    tags = {pw = "add-resource"}}
end

local function tab_enemies(c, d)
  dropdown(c, L("enemy-kind"), "enemies.kind", ENEMIES, "enemies", d.enemies.kind)
  if d.enemies.kind ~= "none" then amount_slider(c, L("amount"), "enemies.amount", d.enemies.amount) end
  hint(c, L("enemies-hint-" .. d.enemies.kind))
end

local function tab_start(c, d, ps)
  c.add{type = "checkbox", caption = L("start-on"), state = d.start ~= nil, tags = {pw = "start-on"}}
  hint(c, L("start-hint"))
  local st = d.start
  if not st then return end
  local captions = {}
  for i, r in ipairs(startarea.RADII) do captions[i] = L("start-radius-n", r) end
  dropdown(c, L("start-radius"), "start.radius", startarea.RADII, nil, st.radius, L("start-radius-tooltip"), captions)
  local tiles, added, removed = startarea.count(st)
  local f = row(c, L("start-changes"))
  f.add{type = "label", caption = L("start-counts", tiles, added, removed)}
  f = c.add{type = "flow", direction = "horizontal"}
  f.style.top_margin = 6
  f.add{type = "button", caption = L("start-edit"), tooltip = L("start-edit-tooltip"), style = "confirm_button_without_tooltip",
    tags = {pw = "start-edit"}}
  f.add{type = "button", caption = ps.confirm_clear and L("start-clear-confirm") or L("start-clear"), tags = {pw = "start-clear"},
    style = ps.confirm_clear and "red_button" or "button", enabled = tiles + added + removed > 0}
  heading(c, L("start-how"))
  hint(c, L("start-how-1"))
  hint(c, L("start-how-2"))
  hint(c, L("start-how-3"))
end

local function tab_physics(c, d)
  local ph = d.physics
  number_slider(c, L("gravity"), "physics.gravity", ph.gravity, 1, 100, 1, "gravity", L("gravity-tooltip"))
  number_slider(c, L("pressure"), "physics.pressure", ph.pressure, 0, 6000, 50, "pressure", L("pressure-tooltip"))
  number_slider(c, L("magnetic-field"), "physics.magnetic_field", ph.magnetic_field, 0, 200, 1, "magnetic",
    L("magnetic-tooltip"))
  number_slider(c, L("solar-power"), "physics.solar_power", ph.solar_power, 0, 600, 5, "percent", L("solar-tooltip"))
  number_slider(c, L("day-length"), "physics.day_length", ph.day_length, 1, 60, 0.5, "minutes", L("day-tooltip"))
  checkbox(c, L("freezing"), "physics.freezing", ph.freezing, L("freezing-tooltip"))
  checkbox(c, L("lightning"), "physics.lightning", ph.lightning, L("lightning-tooltip"))
  hint(c, L("physics-hint"))
end

local function tab_space(c, d)
  local sp = d.space
  local planets = {}
  for name in pairs(game.planets) do
    if name:sub(1, 3) ~= "pw-" then planets[#planets + 1] = name end
  end
  table.sort(planets)
  local f = row(c, L("route-from"))
  local items = {}
  for i, name in ipairs(planets) do items[i] = {"space-location-name." .. name} end
  f.add{type = "drop-down", items = items, selected_index = index_of(planets, sp.from),
    tags = {pw = "pick", path = "space.from", values = planets}}
  number_slider(c, L("route-length"), "space.length", sp.length, 1000, 100000, 1000, "km", L("route-length-tooltip"))
  dropdown(c, L("asteroids"), "space.asteroids", ASTEROIDS, "asteroids", sp.asteroids)
  heading(c, L("star-map"))
  number_slider(c, L("map-distance"), "space.distance", sp.distance, 1, 60, 1, "plain", L("map-distance-tooltip"))
  number_slider(c, L("map-angle"), "space.orientation", math.floor((sp.orientation or 0) * 360 + 0.5), 0, 359, 1,
    "degrees")
  number_slider(c, L("map-size"), "space.magnitude", sp.magnitude, 0.5, 2, 0.1, "times")
  hint(c, L("space-hint"))
end

local function tab_look(c, d, ps)
  local look = d.look
  local f = dropdown(c, L("picture"), "look.picture", PICTURES, "picture", look.picture, L("picture-tooltip"))
  local shown = look.picture ~= "auto" and look.picture or ps.picture or "nauvis"
  f.add{type = "sprite", sprite = "space-location/" .. shown}.style.size = 48
  if look.picture == "auto" then f.add{type = "label", caption = L("auto-is", {"space-location-name." .. shown})} end
  f = dropdown(c, L("sky"), "look.sky", PICTURES, "picture", look.sky, L("sky-tooltip"))
  if look.sky == "auto" then
    f.add{type = "label", caption = L("auto-is", {"space-location-name." .. (ps.sky or "nauvis")})}
  end
  heading(c, L("tint"))
  checkbox(c, L("use-tint"), "look.use_tint", look.tint ~= nil)
  if look.tint then W.tint_sliders(c, "look.tint", look.tint) end
  hint(c, L("look-hint"))
end

-- Checks and test play -------------------------------------------------------------------------------------------

local LEVEL_ICON = {problem = "utility/danger_icon", warning = "utility/warning_icon", note = "utility/tip_icon"}

local function check_line(parent, c, with_button)
  local f = parent.add{type = "flow", direction = "horizontal"}
  f.style.vertical_align = "center"
  local label = f.add{type = "label", caption = {"", "[img=" .. LEVEL_ICON[c.level] .. "] ", c.message}}
  label.style.single_line = false
  label.style.maximal_width = with_button and LEFT_WIDTH - 130 or LEFT_WIDTH + VIEW - 140
  if with_button and c.section then
    local gap = f.add{type = "empty-widget"}
    gap.style.horizontally_stretchable = true
    f.add{type = "button", caption = L("go-there"), tags = {pw = "section", key = c.section}}.style.minimal_width = 90
  end
end

local function tab_checks(c, d, ps)
  hint(c, L("checks-hint"))
  local list = checks.run(d, ps)
  if #list == 0 then
    c.add{type = "label", caption = {"", "[img=utility/check_mark_green] ", L("checks-none")}}
  end
  for _, level in ipairs(checks.LEVELS) do
    local first = true
    for _, check in ipairs(list) do
      if check.level == level then
        if first then heading(c, L("checks-" .. level)) end
        first = false
        check_line(c, check, true)
      end
    end
  end
  if not ps.placed then hint(c, L("checks-preview-pending")) end
end

local TEST_KITS, TEST_RESEARCH = {"landing", "newgame", "none"}, {"all", "none"}

local function tab_testplay(c, d, ps)
  hint(c, L("testplay-hint"))
  local opts = ps.test or {}
  local function pick(caption, key, values, current, tooltip)
    local f = row(c, caption, tooltip)
    local items = {}
    for i, v in ipairs(values) do items[i] = L("test-" .. key .. "-" .. v) end
    f.add{type = "drop-down", items = items, selected_index = index_of(values, current),
      tags = {pw = "test-pick", key = key, values = values}}
  end
  pick(L("test-kit"), "kit", TEST_KITS, opts.kit or "landing", L("test-kit-tooltip"))
  pick(L("test-research"), "research", TEST_RESEARCH, opts.research or "all")
  c.add{type = "checkbox", caption = L("test-free-crafting"), state = opts.free_crafting == true,
    tooltip = L("test-free-crafting-tooltip"), tags = {pw = "test-check", key = "free_crafting"}}
  if d.enemies.kind ~= "none" then
    c.add{type = "checkbox", caption = L("test-enemies"), state = opts.enemies ~= false,
      tags = {pw = "test-check", key = "enemies"}}
  end
  local start = c.add{type = "button", caption = L("test-start"), style = "confirm_button_without_tooltip",
    tags = {pw = "test-start"}}
  start.style.top_margin = 8
  heading(c, L("test-what"))
  hint(c, L("test-what-real"))
  if d.physics.freezing or d.physics.lightning then hint(c, L("test-note-real")) end
  local own = #(d.ores or {}) > 0 or d.science ~= nil or #(d.recipes or {}) > 0 or #(d.technologies or {}) > 0
  if own then
    hint(c, prototypes.space_location["pw-" .. d.id] and L("test-note-loaded") or L("test-note-not-loaded"))
  end
end

local BUILDERS = {general = tab_general, terrain = tab_terrain, nature = tab_nature, resources = tab_resources,
  enemies = tab_enemies, start = tab_start, physics = tab_physics, space = tab_space, look = tab_look,
  ores = production.ores, science = production.science, recipes = production.recipes, research = production.research,
  checks = tab_checks, testplay = tab_testplay}

-- The window ----------------------------------------------------------------------------------------------------

function M.destroy(player)
  for _, name in ipairs{ROOT, CODE, IMPORT} do
    if player.gui.screen[name] then player.gui.screen[name].destroy() end
  end
end

function M.build(player)
  local design, ps = state.current(player)
  local location = player.gui.screen[ROOT] and player.gui.screen[ROOT].location
  if location and location.x == 0 and location.y == 0 then location = nil end -- never placed: centre it
  if player.gui.screen[ROOT] then player.gui.screen[ROOT].destroy() end
  if player.gui.top[MINI] then player.gui.top[MINI].destroy() end
  if ps.minimized then
    player.gui.top.add{type = "button", name = MINI, caption = L("title"), tags = {pw = "restore"}}
    return
  end

  local frame = player.gui.screen.add{type = "frame", name = ROOT, direction = "vertical"}
  if location then frame.location = location end

  -- title bar
  local bar = frame.add{type = "flow", direction = "horizontal"}
  bar.drag_target = frame
  bar.add{type = "label", caption = L("title"), style = "frame_title", ignored_by_interaction = true}
  local drag = bar.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  bar.add{type = "sprite-button", sprite = "utility/collapse", style = "frame_action_button", tooltip = L("minimize"),
    tags = {pw = "minimize"}}

  -- planet list and toolbar
  local tools = frame.add{type = "flow", direction = "horizontal"}
  tools.style.vertical_align = "center"
  tools.add{type = "label", caption = L("planet"), style = "caption_label"}
  local names = {}
  for i, d in ipairs(storage.designer.designs) do names[i] = d.name ~= "" and d.name or "?" end
  tools.add{type = "drop-down", items = names, selected_index = ps.current, tags = {pw = "select-design"}}.style.width = 220
  tools.add{type = "button", caption = L("new"), tooltip = L("new-tooltip"), tags = {pw = "new"}}
  tools.add{type = "button", caption = L("copy"), tooltip = L("copy-tooltip"), tags = {pw = "copy"}}
  tools.add{type = "button", caption = ps.confirm_delete and L("delete-confirm") or L("delete"), tags = {pw = "delete"},
    style = ps.confirm_delete and "red_button" or "button"}
  local gap = tools.add{type = "empty-widget"}
  gap.style.horizontally_stretchable = true
  tools.add{type = "button", caption = L("import"), tooltip = L("import-tooltip"), tags = {pw = "import-open"}}
  tools.add{type = "button", caption = L("get-code"), tooltip = L("get-code-tooltip"), tags = {pw = "get-code"},
    style = "confirm_button_without_tooltip"}

  -- body: sidebar | section | preview
  local body = frame.add{type = "flow", name = "body", direction = "horizontal"}
  local side = body.add{type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding"}
  side.style.width = SIDEBAR
  local section = ps.section or "general"
  for _, g in ipairs(GROUPS) do
    heading(side, L("group-" .. g.name))
    for _, key in ipairs(g.sections) do
      local button = side.add{type = "button", caption = L("tab-" .. key), tags = {pw = "section", key = key}}
      button.style.horizontally_stretchable = true
      button.style.height = 28
      button.toggled = key == section
    end
  end
  local scroll = body.add{type = "scroll-pane", direction = "vertical", style = "naked_scroll_pane"}
  scroll.style.height = VIEW + 40
  scroll.style.width = LEFT_WIDTH
  scroll.style.padding = 8
  local content = scroll.add{type = "flow", direction = "vertical"}
  content.style.vertical_spacing = 6
  BUILDERS[section](content, design, ps, player)

  local right = body.add{type = "frame", name = "right", direction = "vertical", style = "inside_deep_frame"}
  local surface = game.surfaces[preview.surface_name(player.index)]
  if surface then
    local camera = right.add{type = "camera", name = "camera", position = {0, 0}, surface_index = surface.index,
      zoom = state.ZOOMS[ps.zoom]}
    camera.style.width = VIEW
    camera.style.height = VIEW
  else
    local wait = right.add{type = "label", caption = L("preview-wait")}
    wait.style.width = VIEW
    wait.style.height = VIEW
  end
  local controls = right.add{type = "flow", direction = "horizontal"}
  controls.style.vertical_align = "center"
  controls.style.left_padding = 8
  controls.add{type = "button", caption = "−", style = "tool_button", tooltip = L("zoom-out"),
    tags = {pw = "zoom", by = -1}, enabled = ps.zoom > 1}
  controls.add{type = "button", caption = "+", style = "tool_button", tooltip = L("zoom-in"),
    tags = {pw = "zoom", by = 1}, enabled = ps.zoom < #state.ZOOMS}
  local locked = design.start and (function() local a, b, c = startarea.count(design.start) return a + b + c > 0 end)()
  controls.add{type = "button", caption = L("new-seed"), tooltip = locked and L("new-seed-locked") or L("new-seed-tooltip"),
    tags = {pw = "reseed"}, enabled = not locked}
  controls.add{type = "button", caption = ps.walking and L("back") or L("walk"), tooltip = L("walk-tooltip"),
    tags = {pw = "walk"}}
  controls.add{type = "button", caption = L("test-play"), tooltip = L("test-play-tooltip"), tags = {pw = "test-start"},
    style = "confirm_button_without_tooltip"}

  -- problems
  frame.add{type = "flow", name = "status", direction = "vertical"}
  M.update_status(player)
  if not location then frame.force_auto_center() end -- (after the content, so it centres the full size)
end

--- True if the window shows a preview camera (it doesn't before the first preview exists).
function M.has_camera(player)
  local frame = player.gui.screen[ROOT]
  return frame ~= nil and frame.body ~= nil and frame.body.right ~= nil and frame.body.right.camera ~= nil
end

--- "2 warnings, 1 note" (only the levels there are).
function M.count_text(n)
  local text = {""}
  for _, level in ipairs(checks.LEVELS) do
    if n[level] > 0 then
      if #text > 1 then text[#text + 1] = ", " end
      text[#text + 1] = L("count-" .. level, n[level])
    end
  end
  return text
end

--- Refreshes the checks line at the bottom (after a change or a new preview) without rebuilding the window, so
--- a slider being dragged isn't interrupted.
function M.update_status(player)
  local frame = player.gui.screen[ROOT]
  if not (frame and frame.status) then return end
  local design, ps = state.current(player)
  local status = frame.status
  status.clear()
  local list = checks.run(design, ps)
  local n = checks.count(list)
  local f = status.add{type = "flow", direction = "horizontal"}
  f.style.vertical_align = "center"
  if #list == 0 then
    f.add{type = "label", caption = {"", "[img=utility/check_mark_green] ", L("no-problems")}}.style.font_color = {0.6, 0.8, 0.6}
    return
  end
  f.add{type = "label", caption = M.count_text(n), style = "caption_label"}
  f.add{type = "button", caption = L("checks-open"), tags = {pw = "section", key = "checks"}}
  -- the most important two
  for i = 1, math.min(#list, 2) do
    if list[i].level ~= "note" then check_line(status, list[i], false) end
  end
end

-- Code and import windows ----------------------------------------------------------------------------------------

local function popup(player, name, caption)
  if player.gui.screen[name] then player.gui.screen[name].destroy() end
  local frame = player.gui.screen.add{type = "frame", name = name, direction = "vertical"}
  frame.auto_center = true
  local bar = frame.add{type = "flow", direction = "horizontal"}
  bar.drag_target = frame
  bar.add{type = "label", caption = caption, style = "frame_title", ignored_by_interaction = true}
  local drag = bar.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  bar.add{type = "sprite-button", sprite = "utility/close", style = "frame_action_button", tags = {pw = "close", window = name}}
  return frame
end

--- The Share window (Get code): the code for this planet, or a pack with others, and the share picture.
function M.show_code(player)
  local design = state.current(player)
  local n = checks.count(checks.run(design, state.player(player.index)))
  local warnings
  if n.problem + n.warning > 0 then
    warnings = L("code-has-warnings", M.count_text({problem = n.problem, warning = n.warning, note = 0}))
  end
  local code, remixed = share.show(player, popup, warnings)
  if remixed > 0 then -- (its id and author changed: show that in the main window, keeping the Share window on top)
    M.build(player)
    if player.gui.screen[CODE] then player.gui.screen[CODE].bring_to_front() end
  end
  return code
end

function M.show_import(player, message)
  local frame = popup(player, IMPORT, L("import-title"))
  frame.add{type = "label", caption = L("import-hint")}
  local box = frame.add{type = "text-box", name = "code"}
  box.word_wrap = true
  box.style.width = 600
  box.style.height = 160
  box.focus()
  if message then frame.add{type = "label", caption = message}.style.single_line = false end
  frame.add{type = "button", caption = L("import-do"), style = "confirm_button_without_tooltip", tags = {pw = "import-do"}}
end

M.ROOT, M.CODE, M.IMPORT = ROOT, CODE, IMPORT
M.SHAPES, M.LIQUIDS, M.STARTING = SHAPES, LIQUIDS, STARTING

return M
