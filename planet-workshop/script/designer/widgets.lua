-- Building blocks for the Planet Designer window. Every input gets tags saying what it changes: `pw` (the kind of
-- input, which picks the handler in init.lua) and `path` (the field in the planet table, e.g. "recipes.2.time").

local state = require("__planet-workshop__.script.designer.state")
local spec = require("__planet-workshop__.lib.spec")

local M = {}

M.LEFT_WIDTH = 600

function M.L(key, ...) return {"planet-workshop-designer." .. key, ...} end
local L = M.L

function M.index_of(list, value)
  for i, v in ipairs(list) do if v == value then return i end end
  return 1
end

local function percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

local function amount_index(v)
  local best, best_d = 6, math.huge
  for i, a in ipairs(state.AMOUNTS) do
    local d = math.abs(math.log(a) - math.log(math.max(v, 0.001)))
    if d < best_d then best, best_d = i, d end
  end
  return best
end

function M.row(parent, caption, tooltip, width)
  local flow = parent.add{type = "flow", direction = "horizontal"}
  flow.style.vertical_align = "center"
  flow.style.horizontal_spacing = 8
  if caption then
    local label = flow.add{type = "label", caption = caption, tooltip = tooltip}
    label.style.width = width or 150
  end
  return flow
end

function M.heading(parent, caption)
  local label = parent.add{type = "label", caption = caption, style = "caption_label"}
  label.style.top_margin = 6
  return label
end

function M.hint(parent, caption)
  local label = parent.add{type = "label", caption = caption}
  label.style.font_color = {0.7, 0.7, 0.7}
  label.style.single_line = false
  label.style.maximal_width = M.LEFT_WIDTH - 30
  return label
end

--- A bordered box for one item of a list (an ore, a recipe...).
function M.box(parent)
  local box = parent.add{type = "frame", direction = "vertical", style = "bordered_frame"}
  box.style.horizontally_stretchable = true
  return box
end

function M.remove_button(parent, path, index, enabled)
  return parent.add{type = "sprite-button", sprite = "utility/close", style = "tool_button_red", tooltip = L("remove"),
    tags = {pw = "remove", path = path, index = index}, enabled = enabled ~= false}
end

--- A dropdown that sets `path` to one of `values` (captions: locale prefix-value, or the given captions).
function M.dropdown(parent, caption, path, values, prefix, current, tooltip, captions)
  local flow = M.row(parent, caption, tooltip)
  local items = {}
  for i, v in ipairs(values) do items[i] = captions and captions[i] or L(prefix .. "-" .. v) end
  flow.add{type = "drop-down", items = items, selected_index = M.index_of(values, current),
    tags = {pw = "pick", path = path, values = values}}
  return flow
end

--- A slider for an amount (17% ... 600%).
function M.amount_slider(parent, caption, path, value, tooltip)
  local flow = M.row(parent, caption, tooltip)
  local slider = flow.add{type = "slider", minimum_value = 1, maximum_value = #state.AMOUNTS, value_step = 1,
    value = amount_index(value), discrete_slider = true, tags = {pw = "amount", path = path}}
  slider.style.width = 200
  flow.add{type = "label", name = "pw_value", caption = percent(value)}
  return flow
end

--- A slider for a number, shown with a unit (locale unit-<unit>).
function M.number_slider(parent, caption, path, value, min, max, step, unit, tooltip)
  local flow = M.row(parent, caption, tooltip)
  local slider = flow.add{type = "slider", minimum_value = min, maximum_value = max, value_step = step,
    value = math.max(min, math.min(max, value)), tags = {pw = "number", path = path, unit = unit}}
  slider.style.width = 200
  flow.add{type = "label", name = "pw_value", caption = M.unit_caption(unit, value)}
  return flow
end

--- A slider's value with its unit ("7 min"); a spoil time of 0 is "never".
function M.unit_caption(unit, value)
  if unit == "spoil" and (value or 0) <= 0 then return {"planet-workshop-designer.unit-spoil-never"} end
  return {"planet-workshop-designer.unit-" .. unit, tostring(value)}
end

function M.checkbox(parent, caption, path, value, tooltip)
  return parent.add{type = "checkbox", caption = caption, state = value == true, tooltip = tooltip,
    tags = {pw = "check", path = path}}
end

--- A text box for a number. `scale`: stored = typed * scale (e.g. 0.01 for a percentage).
function M.number_field(parent, path, value, decimal, width, scale)
  local shown = value or 0
  if scale then shown = math.floor(shown / scale * 100 + 0.5) / 100 end
  local field = parent.add{type = "textfield", text = tostring(shown), numeric = true, allow_decimal = decimal == true,
    allow_negative = false, tags = {pw = "num", path = path, scale = scale}}
  field.style.width = width or 70
  return field
end

function M.text_field(parent, path, value, width)
  local field = parent.add{type = "textfield", text = value or "", tags = {pw = "text", path = path}}
  field.style.width = width or 220
  return field
end

--- Red / green / blue sliders for a colour at `path` ({r, g, b}, 0-1).
--- Rich text showing a colour as a block (updated live by the tint sliders).
function M.swatch_text(tint)
  return string.format("[color=%d,%d,%d]██████████[/color]", math.floor(tint.r * 255 + 0.5), math.floor(tint.g * 255 + 0.5),
    math.floor(tint.b * 255 + 0.5))
end

function M.tint_sliders(parent, path, color)
  local tint = spec.color(color) or {r = 1, g = 1, b = 1}
  local holder = parent.add{type = "flow", direction = "vertical"}
  local swatch_row = M.row(holder, L("colour"))
  swatch_row.add{type = "label", name = "pw_swatch", caption = M.swatch_text(tint)}
  parent = holder
  for _, ch in ipairs{"r", "g", "b"} do
    local flow = M.row(parent, L("tint-" .. ch))
    local slider = flow.add{type = "slider", minimum_value = 0, maximum_value = 255, value_step = 1,
      value = math.floor(tint[ch] * 255 + 0.5), tags = {pw = "tint", path = path, channel = ch}}
    slider.style.width = 200
    flow.add{type = "label", name = "pw_value", caption = tostring(math.floor(tint[ch] * 255 + 0.5))}
  end
end

-- Picking things: from the game, or the planet's own --------------------------------------------------------

--- The planet's own things a picker of `kind` can offer: {refs = {...}, captions = {...}}.
local function own_options(kind, design, self_key)
  local refs, captions = {}, {}
  local function add(ref, caption) refs[#refs + 1] = ref; captions[#captions + 1] = caption end
  if kind == "thing" then
    for _, ore in ipairs(design.ores or {}) do
      add("@ore:" .. ore.key, L(ore.kind == "fluid" and "own-fluid" or "own-ore", ore.name or ore.key))
    end
    if design.science then add("@pack", L("own-pack", design.science.name or "")) end
  elseif kind == "pack" then
    if design.science then add("@pack", L("own-pack", design.science.name or "")) end
  elseif kind == "tech" then
    add("@discovery", L("own-discovery"))
    for _, tech in ipairs(design.technologies or {}) do
      if tech.key ~= self_key then add("@tech:" .. tech.key, L("own-tech", tech.name or tech.key)) end
    end
  elseif kind == "recipe" then
    if design.science then add("@pack", L("own-pack-recipe", design.science.name or "")) end
    for _, recipe in ipairs(design.recipes or {}) do
      add("@recipe:" .. recipe.key, L("own-recipe", recipe.name or recipe.key))
    end
  end
  return refs, captions
end

M.GAME_DEFAULT = {thing = "iron-plate", pack = "automation-science-pack", tech = "space-platform-thruster",
  gametech = "space-platform-thruster", recipe = "iron-gear-wheel"}

--- A picker for a reference at `path`: a dropdown ("From the game" or one of the planet's own things) and, for
--- game things, the game's own icon picker.
function M.ref_picker(parent, path, value, kind, design, self_key)
  local refs, captions = own_options(kind, design, self_key)
  local flow = parent.add{type = "flow", direction = "horizontal"}
  flow.style.vertical_align = "center"
  local items = {L("from-game")}
  for i, c in ipairs(captions) do items[i + 1] = c end
  local selected = 1
  if type(value) == "string" and value:sub(1, 1) == "@" then selected = M.index_of(refs, value) + 1 end
  if #refs > 0 then
    local dd = flow.add{type = "drop-down", items = items, selected_index = selected,
      tags = {pw = "ref-source", path = path, refs = refs, kind = kind}}
    dd.style.width = 240
  end
  if selected == 1 then
    local button
    if kind == "thing" then
      local signal
      if value and prototypes.item[value] then signal = {type = "item", name = value}
      elseif value and prototypes.fluid[value] then signal = {type = "fluid", name = value} end
      button = flow.add{type = "choose-elem-button", elem_type = "signal", signal = signal,
        tags = {pw = "ref-elem", path = path, kind = kind}}
    elseif kind == "pack" then
      button = flow.add{type = "choose-elem-button", elem_type = "item", item = prototypes.item[value] and value or nil,
        elem_filters = {{filter = "subgroup", subgroup = "science-pack"}}, tags = {pw = "ref-elem", path = path, kind = kind}}
    elseif kind == "tech" or kind == "gametech" then
      button = flow.add{type = "choose-elem-button", elem_type = "technology",
        technology = prototypes.technology[value] and value or nil, tags = {pw = "ref-elem", path = path, kind = kind}}
    elseif kind == "recipe" then
      button = flow.add{type = "choose-elem-button", elem_type = "recipe", recipe = prototypes.recipe[value] and value or nil,
        tags = {pw = "ref-elem", path = path, kind = kind}}
    end
    if button then button.style.size = 32 end
    -- technology icons alone are hard to tell apart: their names too
    if (kind == "tech" or kind == "gametech") and prototypes.technology[value] then
      local label = flow.add{type = "label", caption = prototypes.technology[value].localised_name}
      label.style.maximal_width = 260
    end
  end
  return flow
end

--- A list of {name, amount} (ingredients, results, research costs) with add / remove.
function M.amount_list(parent, caption, path, list, kind, design, add_caption)
  M.heading(parent, caption)
  for i, entry in ipairs(list or {}) do
    local flow = parent.add{type = "flow", direction = "horizontal"}
    flow.style.vertical_align = "center"
    M.ref_picker(flow, path .. "." .. i .. ".name", entry.name, kind, design)
    flow.add{type = "label", caption = "×"}
    M.number_field(flow, path .. "." .. i .. ".amount", entry.amount or 1, false, 60)
    M.remove_button(flow, path, i)
  end
  parent.add{type = "button", caption = add_caption or L("add"), tags = {pw = "add", path = path,
    template = {name = M.GAME_DEFAULT[kind], amount = 1}}}
end

--- A list of references (prerequisites) with add / remove.
function M.ref_list(parent, caption, path, list, kind, design, self_key)
  M.heading(parent, caption)
  for i, ref in ipairs(list or {}) do
    local flow = parent.add{type = "flow", direction = "horizontal"}
    flow.style.vertical_align = "center"
    M.ref_picker(flow, path .. "." .. i, ref, kind, design, self_key)
    M.remove_button(flow, path, i)
  end
  parent.add{type = "button", caption = L("add"), tags = {pw = "add", path = path, template = M.GAME_DEFAULT[kind]}}
end

--- Recipe categories with the machines that make them (for the category dropdown's tooltip).
local categories
function M.categories()
  if not categories then
    local machines = {}
    for _, e in pairs(prototypes.get_entity_filtered{{filter = "crafting-machine"}}) do
      for cat in pairs(e.crafting_categories or {}) do
        machines[cat] = machines[cat] or {}
        if #machines[cat] < 3 then table.insert(machines[cat], e.localised_name) end
      end
    end
    categories = {names = {}, tooltips = {}}
    for name in pairs(prototypes.recipe_category) do
      if machines[name] and name ~= "parameters" then categories.names[#categories.names + 1] = name end
    end
    table.sort(categories.names)
    for i, name in ipairs(categories.names) do
      local tip = {""}
      for j, m in ipairs(machines[name]) do
        if j > 1 then tip[#tip + 1] = ", " end
        tip[#tip + 1] = m
      end
      categories.tooltips[i] = tip
    end
  end
  return categories
end

--- A dropdown of recipe categories ("which machine makes it").
function M.category_dropdown(parent, path, current)
  local c = M.categories()
  local items = {}
  for i, name in ipairs(c.names) do items[i] = {"", name:gsub("%-", " "), " (", c.tooltips[i], ")"} end
  local dd = parent.add{type = "drop-down", items = items, selected_index = M.index_of(c.names, current),
    tags = {pw = "pick", path = path, values = c.names}}
  dd.style.width = 300
  return dd
end

return M
