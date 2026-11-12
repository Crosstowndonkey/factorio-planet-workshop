-- Sharing planets: the Share window (Get code), planet packs (one code with several planets), remixes, the
-- other mods a planet was made with, and the share picture.
--
-- Remixes: a planet imported from someone else's code keeps a copy of how it came (`_original`). If it's
-- changed and shared, it becomes the sharer's remix: its own id (so it doesn't replace the original in games
-- that have both), the sharer as the author, and a credit to the original ("Based on X by Y").
-- Fields starting with "_" are the designer's own and never go into codes.

local util = require("util")
local codes = require("__planet-workshop__.lib.codes")
local state = require("__planet-workshop__.script.designer.state")
local preview = require("__planet-workshop__.script.designer.preview")
local W = require("__planet-workshop__.script.designer.widgets")

local M = {}
local L = W.L

M.WINDOW = "pw_designer_code"
local IGNORED_MODS = {core = true, base = true, ["planet-workshop"] = true}

-- What a planet uses, and the mods that made it -----------------------------------------------------------------

local function created_by(kind, name)
  if type(name) ~= "string" or name:sub(1, 1) == "@" then return nil end
  local proto_type
  if kind == "item" then
    local item = prototypes.item[name]
    if item then proto_type = item.type elseif prototypes.fluid[name] then proto_type = "fluid" end
  elseif kind == "entity" then
    proto_type = prototypes.entity[name] and prototypes.entity[name].type
  elseif kind == "space" then
    proto_type = prototypes.space_location[name] and prototypes.space_location[name].type
  else
    proto_type = kind
  end
  if not proto_type then return nil end
  local ok, history = pcall(prototypes.get_history, proto_type, name)
  return ok and history and history.created or nil
end

--- The other mods a planet uses things from: {name = version}.
function M.required_mods(design)
  local found = {}
  local function use(kind, name)
    local mod = created_by(kind, name)
    if mod and not IGNORED_MODS[mod] and script.active_mods[mod] then found[mod] = script.active_mods[mod] end
  end
  local function amounts(list) for _, e in ipairs(list or {}) do use("item", e.name) end end
  local t = design.terrain or {}
  for _, g in ipairs(t.ground or {}) do use("tile", g.tile) end
  for _, r in ipairs(design.resources or {}) do use("entity", r.resource) end
  use("space", design.space and design.space.from)
  local s = design.science
  if s then
    amounts(s.ingredients)
    use("item", s.base)
    use("recipe-category", s.category)
  end
  for _, r in ipairs(design.recipes or {}) do
    amounts(r.ingredients)
    amounts(r.results)
    use("recipe-category", r.category)
  end
  local disc = design.discovery or {}
  amounts(disc.ingredients)
  for _, ref in ipairs(disc.prerequisites or {}) do use("technology", ref) end
  for _, tech in ipairs(design.technologies or {}) do
    amounts(tech.ingredients)
    use("item", tech.icon)
    for _, ref in ipairs(tech.prerequisites or {}) do use("technology", ref) end
    for _, e in ipairs(tech.effects or {}) do use("recipe", e.recipe) end
  end
  local st = design.start
  if st then
    for _, name in ipairs(st.palette or {}) do use("tile", name) end
    for _, a in ipairs(st.add or {}) do use("entity", a.name) end
  end
  return found
end

--- The mods a planet lists that aren't in this game.
function M.missing_mods(design)
  local missing = {}
  for name in pairs(design.mods or {}) do
    if not script.active_mods[name] then missing[#missing + 1] = name end
  end
  table.sort(missing)
  return missing
end

-- Remixes ------------------------------------------------------------------------------------------------------

local function stripped(design)
  local copy = util.table.deepcopy(design)
  for k in pairs(design) do
    if type(k) == "string" and k:sub(1, 1) == "_" then copy[k] = nil end
  end
  copy.mods = nil
  return copy
end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

--- Remembers how an imported planet came, so changing it later makes a remix.
function M.mark_imported(design)
  design._original = stripped(design)
end

--- True if this is someone else's imported planet.
function M.foreign(design, player)
  return design._original ~= nil and (design.author or "") ~= player.name
end

--- True if someone else's planet has been changed since it was imported.
function M.changed(design)
  return design._original ~= nil and not same(stripped(design), design._original)
end

--- Makes a planet the player's remix: its own id, the player as author, a credit to the one it's based on.
function M.make_remix(design, player)
  design.credits = design.credits or {}
  if #design.credits < 10 then
    design.credits[#design.credits + 1] = {name = design.name or "?", author = design.author or "?"}
  end
  design.id = state.new_id(player)
  design.author = player.name
  design._original = nil
end

--- A planet as it goes into a code: the designer's own fields out, the other mods it uses in.
function M.for_code(design)
  local copy = stripped(design)
  copy.mods = M.required_mods(copy)
  if next(copy.mods) == nil then copy.mods = nil end
  if copy.credits and #copy.credits == 0 then copy.credits = nil end
  return copy
end

-- The Share window --------------------------------------------------------------------------------------------

local function safe_file_name(text)
  local name = (text or "planet"):gsub("[^%w%-_ ]", ""):gsub("%s+", "-")
  if name == "" then name = "planet" end
  return name:sub(1, 40)
end

--- The planets that go in the player's code: the current one and any ticked in the Share window.
function M.chosen(player)
  local design, ps = state.current(player)
  local list = {}
  for _, d in ipairs(storage.designer.designs) do
    if d == design or (ps.share and ps.share[d.id]) then list[#list + 1] = d end
  end
  return list
end

--- Makes the code for the chosen planets (changed imports become remixes first). Returns code, file, remixed.
function M.make_code(player)
  local remixed = {}
  local chosen = M.chosen(player)
  for _, d in ipairs(chosen) do
    if M.foreign(d, player) and M.changed(d) then
      local was = {name = d.name, author = d.author}
      M.make_remix(d, player)
      remixed[#remixed + 1] = was
    end
  end
  local planets = {}
  for i, d in ipairs(chosen) do planets[i] = M.for_code(d) end
  local code = codes.encode(planets)
  local first = chosen[1]
  local file
  if #chosen == 1 then
    file = "planet-workshop/" .. safe_file_name(first.name) .. "-" .. first.id .. ".txt"
  else
    file = "planet-workshop/" .. safe_file_name(first.name) .. "-and-" .. (#chosen - 1) .. "-more.txt"
  end
  helpers.write_file(file, code .. "\n", false, player.index)
  return code, file, remixed
end

function M.show(player, popup, checks_text)
  local design, ps = state.current(player)
  ps.share = ps.share or {}
  local code, file, remixed = M.make_code(player)
  local chosen = M.chosen(player)
  local frame = popup(player, M.WINDOW, #chosen > 1 and L("pack-title", #chosen) or L("code-title", design.name))
  for _, r in ipairs(remixed) do
    local label = frame.add{type = "label", caption = L("now-remix", r.name, r.author)}
    label.style.single_line = false
    label.style.maximal_width = 600
    label.style.font_color = {1, 0.85, 0.5}
  end
  -- which planets go in it
  if #storage.designer.designs > 1 then
    frame.add{type = "label", caption = L("pack-hint"), style = "caption_label"}
    local table_el = frame.add{type = "table", column_count = 3}
    table_el.style.horizontal_spacing = 16
    for _, d in ipairs(storage.designer.designs) do
      local mine = d == design
      local box = table_el.add{type = "checkbox", caption = d.name ~= "" and d.name or "?", state = mine or ps.share[d.id] == true,
        enabled = not mine, tags = {pw = "share-pick", id = d.id}}
      box.style.minimal_width = 180
    end
  end
  local hint_label = frame.add{type = "label", caption = L(#chosen > 1 and "pack-code-hint" or "code-hint", file)}
  hint_label.style.single_line = false
  hint_label.style.maximal_width = 600
  if checks_text then
    local warn = frame.add{type = "label", caption = {"", "[img=utility/warning_icon] ", checks_text}}
    warn.style.single_line = false
    warn.style.maximal_width = 600
  end
  local used = {}
  for _, d in ipairs(chosen) do
    for name in pairs(M.required_mods(d)) do used[name] = true end
  end
  local names = {}
  for name in pairs(used) do names[#names + 1] = name end
  table.sort(names)
  if #names > 0 then
    local label = frame.add{type = "label", caption = L("needs-mods", table.concat(names, ", "))}
    label.style.single_line = false
    label.style.maximal_width = 600
  end
  local box = frame.add{type = "text-box", name = "code", text = code}
  box.word_wrap = true
  box.style.width = 600
  box.style.height = 160
  box.select_all()
  box.focus()
  local buttons = frame.add{type = "flow", direction = "horizontal"}
  buttons.add{type = "button", caption = L("share-picture"), tooltip = L("share-picture-tooltip"), tags = {pw = "share-picture"}}
  return code, #remixed
end

-- The share picture --------------------------------------------------------------------------------------------

local ZOOM = 0.35
local VIEW_W, VIEW_H = 1920, 1080

--- Tile positions on the picture: the picture is centred on `center`; returns the world position of pixel (px, py).
local function at(center, px, py)
  local scale = 32 * ZOOM
  return {x = center.x + (px - VIEW_W / 2) / scale, y = center.y + (py - VIEW_H / 2) / scale}
end

local function word_lines(text, width)
  local lines, line = {}, ""
  for word in (text or ""):gmatch("%S+") do
    if #line + #word + 1 > width and line ~= "" then
      lines[#lines + 1] = line
      line = word
    else
      line = line == "" and word or (line .. " " .. word)
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

--- Takes a picture of the planet's preview with a card about it, saved to script-output. Returns the file name,
--- or nil and a reason.
function M.picture(player)
  local design, ps = state.current(player)
  local surface = game.surfaces[preview.surface_name(player.index)]
  if not surface or storage.designer.due[player.index] or (storage.designer.generate or {})[player.index] then
    return nil, L("picture-wait")
  end
  local p = preview.evaluate(design, preview.seed(design, ps))
  if not p then return nil, L("picture-wait") end
  surface.request_to_generate_chunks({0, 0}, 4)
  surface.force_generate_chunk_requests()

  local center = {x = -24, y = 0}
  local objects = {}
  local function keep(obj) objects[#objects + 1] = obj end
  local common = {surface = surface, players = {player.index}, time_to_live = 3}
  local function rect(px1, py1, px2, py2, color)
    keep(rendering.draw_rectangle(util.merge{common, {left_top = at(center, px1, py1), right_bottom = at(center, px2, py2),
      color = color, filled = true}}))
  end
  local y = 70
  local texts = {}
  local function text(caption, px, size, color, font)
    texts[#texts + 1] = {text = caption, target = at(center, px, y), scale = size, color = color or {1, 1, 1},
      font = font or "default-game", use_rich_text = true}
  end
  y = 80
  text(p.name, 250, 6, {1, 0.85, 0.5}, "default-large-bold")
  y = 150
  if p.author then text({"planet-workshop-designer.picture-by", p.author}, 250, 3.2, {0.85, 0.85, 0.85}) end
  y = 195
  for _, c in ipairs(p.credits or {}) do
    text({"planet-workshop-designer.picture-based-on", c.name, c.author}, 250, 2.6, {0.7, 0.7, 0.7})
    y = y + 34
  end
  y = math.max(y, 250) + 20
  for _, line in ipairs(word_lines(p.description, 46)) do
    if y > 520 then break end
    text(line, 80, 3, {0.9, 0.9, 0.9})
    y = y + 38
  end
  y = y + 20
  -- facts
  local function fact(label, value)
    if y > VIEW_H - 140 then return end
    text({"", "[color=0.65,0.65,0.65]", label, ":[/color] ", value}, 80, 3, {1, 1, 1})
    y = y + 44
  end
  local ground = {""}
  for _, g in ipairs(p.terrain.ground) do
    if prototypes.tile[g.tile] then ground[#ground + 1] = "[img=tile/" .. g.tile .. "]" end
  end
  fact({"planet-workshop-designer.ground"}, ground)
  local res = {""}
  local resolve = preview.resolver(design)
  for _, r in ipairs(p.resources) do
    local name = r.resource:sub(1, 1) == "@" and resolve(r.resource) or r.resource
    if name and prototypes.entity[name] then res[#res + 1] = "[img=entity/" .. name .. "]" end
    if #res > 12 then break end
  end
  if #res > 1 then fact({"planet-workshop-designer.tab-resources"}, res) end
  fact({"planet-workshop-designer.enemy-kind"}, {"planet-workshop-designer.enemies-" .. p.enemies.kind})
  fact({"planet-workshop-designer.gravity"}, {"planet-workshop-designer.unit-gravity", tostring(p.physics.gravity)})
  fact({"planet-workshop-designer.day-length"}, {"planet-workshop-designer.unit-minutes", tostring(p.physics.day_length)})
  local own = {}
  if p.science then own[#own + 1] = p.science.name end
  if #p.ores > 0 then own[#own + 1] = {"planet-workshop-designer.picture-ores", #p.ores} end
  if #p.recipes > 0 then own[#own + 1] = {"planet-workshop-designer.picture-recipes", #p.recipes} end
  if #p.technologies > 0 then own[#own + 1] = {"planet-workshop-designer.picture-research", #p.technologies} end
  if #own > 0 then
    local list = {""}
    for i, o in ipairs(own) do
      if i > 1 then list[#list + 1] = ", " end
      list[#list + 1] = o
    end
    fact({"planet-workshop-designer.picture-own"}, list)
  end
  if p.starting_planet then fact({"planet-workshop-designer.starting-planet"}, {"planet-workshop-designer.picture-yes"}) end
  y = y + 30
  text({"planet-workshop-designer.picture-footer"}, 80, 2.6, {0.65, 0.65, 0.65})

  -- the card (as tall as what's on it), the planet's look, then the text
  rect(40, 40, 700, y + 70, {0, 0, 0, 0.78})
  -- (as a picture in text: sprites are drawn under the card, text over it)
  keep(rendering.draw_text(util.merge{common, {text = "[img=space-location/" .. (ps.picture or "nauvis") .. "]",
    target = at(center, 140, 150), scale = 15, color = {1, 1, 1}, alignment = "center", vertical_alignment = "middle",
    use_rich_text = true}}))
  for _, t in ipairs(texts) do keep(rendering.draw_text(util.merge{common, t})) end

  local file = "planet-workshop/" .. safe_file_name(design.name) .. "-" .. design.id .. ".png"
  game.take_screenshot{player = player, by_player = player, surface = surface, position = center, resolution = {VIEW_W, VIEW_H},
    zoom = ZOOM, path = file, show_gui = false, daytime = 0, hide_clouds = true, force_render = true}
  return file
end

return M
