-- The Planet Designer's production sections: the planet's own ores and fluids, its science pack, its recipes,
-- and its research (the discovery technology and its own technologies).

local spec = require("__planet-workshop__.lib.spec")
local W = require("__planet-workshop__.script.designer.widgets")

local M = {}
local L = W.L

local ORE_BASES, FLUID_BASES = {}, {}
for base in pairs(spec.ORE_BASES) do ORE_BASES[#ORE_BASES + 1] = base end
for base in pairs(spec.FLUID_BASES) do FLUID_BASES[#FLUID_BASES + 1] = base end
table.sort(ORE_BASES)
table.sort(FLUID_BASES)

M.EFFECTS = {"unlock-recipe", "change-recipe-productivity", "mining-drill-productivity-bonus", "laboratory-speed",
  "laboratory-productivity", "worker-robot-speed", "character-mining-speed"}

local function entity_captions(names)
  local captions = {}
  for i, name in ipairs(names) do
    captions[i] = prototypes.entity[name] and prototypes.entity[name].localised_name or name
  end
  return captions
end

-- Ores and fluids ---------------------------------------------------------------------------------------------

function M.ores(c, d)
  W.hint(c, L("ores-hint"))
  for i, ore in ipairs(d.ores or {}) do
    local box = W.box(c)
    local top = box.add{type = "flow", direction = "horizontal"}
    top.style.vertical_align = "center"
    W.text_field(top, "ores." .. i .. ".name", ore.name, 200)
    local fluid = ore.kind == "fluid"
    local bases = fluid and FLUID_BASES or ORE_BASES
    top.add{type = "label", caption = L("looks-like")}
    top.add{type = "drop-down", items = entity_captions(bases), selected_index = W.index_of(bases, ore.base),
      tags = {pw = "pick", path = "ores." .. i .. ".base", values = bases}}
    W.remove_button(top, "ores", i)
    W.hint(box, L(fluid and "own-fluid-kind" or "own-ore-kind", "@ore:" .. ore.key))
    W.tint_sliders(box, "ores." .. i .. ".tint", ore.tint)
    local f = W.row(box, L("mining-time"), L("mining-time-tooltip"))
    W.number_field(f, "ores." .. i .. ".mining_time", ore.mining_time or 1, true)
    if not fluid then
      f = W.row(box, L("stack-size"))
      W.number_field(f, "ores." .. i .. ".stack_size", ore.stack_size or 50)
    end
  end
  local f = c.add{type = "flow", direction = "horizontal"}
  f.add{type = "button", caption = L("add-ore"), tags = {pw = "add-ore", kind = "solid"}}
  f.add{type = "button", caption = L("add-fluid"), tags = {pw = "add-ore", kind = "fluid"}}
  W.hint(c, L("ores-preview-hint"))
end

-- Science pack ------------------------------------------------------------------------------------------------

function M.science(c, d)
  c.add{type = "checkbox", caption = L("science-on"), state = d.science ~= nil, tags = {pw = "science-on"}}
  local s = d.science
  if not s then
    W.hint(c, L("science-off-hint"))
    return
  end
  local f = W.row(c, L("name"))
  W.text_field(f, "science.name", s.name, 300)
  f = W.row(c, L("looks-like"))
  f.add{type = "choose-elem-button", elem_type = "item", item = prototypes.item[s.base] and s.base or nil,
    elem_filters = {{filter = "subgroup", subgroup = "science-pack"}}, tags = {pw = "elem", path = "science.base"}}
  W.heading(c, L("tint"))
  W.tint_sliders(c, "science.tint", s.tint)
  W.amount_list(c, L("ingredients"), "science.ingredients", s.ingredients, "thing", d, L("add-ingredient"))
  W.heading(c, L("making"))
  f = W.row(c, L("makes"))
  W.number_field(f, "science.count", s.count or 1)
  f = W.row(c, L("craft-time"))
  W.number_field(f, "science.time", s.time or 5, true)
  f.add{type = "label", caption = L("seconds")}
  f = W.row(c, L("made-in"))
  W.category_dropdown(f, "science.category", s.category or "crafting")
  W.checkbox(c, L("only-here"), "science.only_here", s.only_here ~= false, L("only-here-tooltip"))
  W.number_slider(c, L("spoils"), "science.spoil_minutes", s.spoil_minutes or 0, 0, 120, 5, "spoil",
    L("spoils-tooltip"))
  W.hint(c, L("science-hint"))
end

-- Recipes -------------------------------------------------------------------------------------------------------

function M.recipes(c, d)
  W.hint(c, L("recipes-hint"))
  for i, r in ipairs(d.recipes or {}) do
    local box = W.box(c)
    local p = "recipes." .. i
    local top = box.add{type = "flow", direction = "horizontal"}
    top.style.vertical_align = "center"
    W.text_field(top, p .. ".name", r.name, 260)
    top.add{type = "label", caption = L("craft-time")}
    W.number_field(top, p .. ".time", r.time or 1, true)
    top.add{type = "label", caption = L("seconds")}
    W.remove_button(top, "recipes", i)
    local f = W.row(box, L("made-in"))
    W.category_dropdown(f, p .. ".category", r.category or "crafting")
    W.amount_list(box, L("ingredients"), p .. ".ingredients", r.ingredients, "thing", d, L("add-ingredient"))
    W.amount_list(box, L("results"), p .. ".results", r.results, "thing", d, L("add-result"))
    W.checkbox(box, L("only-here"), p .. ".only_here", r.only_here, L("only-here-tooltip"))
    W.checkbox(box, L("known-from-start"), p .. ".enabled", r.enabled, L("known-from-start-tooltip"))
  end
  c.add{type = "button", caption = L("add-recipe"), tags = {pw = "add-recipe"}}
end

-- Research ------------------------------------------------------------------------------------------------------

local function cost(parent, path, t, design)
  local f = W.row(parent, L("research-count"))
  W.number_field(f, path .. ".count", t.count or 100)
  f.add{type = "label", caption = L("research-time")}
  W.number_field(f, path .. ".time", t.time or 30, true)
  f.add{type = "label", caption = L("seconds")}
  W.amount_list(parent, L("research-packs"), path .. ".ingredients", t.ingredients, "pack", design, L("add-pack"))
end

function M.research(c, d)
  local disc = d.discovery
  W.heading(c, L("discovery"))
  W.hint(c, L("discovery-hint"))
  local box = W.box(c)
  W.ref_list(box, L("prerequisites"), "discovery.prerequisites", disc.prerequisites, "gametech", d)
  cost(box, "discovery", disc, d)

  W.heading(c, L("technologies"))
  W.hint(c, L("technologies-hint"))
  for i, t in ipairs(d.technologies or {}) do
    local p = "technologies." .. i
    box = W.box(c)
    local top = box.add{type = "flow", direction = "horizontal"}
    top.style.vertical_align = "center"
    W.text_field(top, p .. ".name", t.name, 240)
    top.add{type = "label", caption = L("icon")}
    local signal
    if t.icon and prototypes.item[t.icon] then signal = {type = "item", name = t.icon}
    elseif t.icon and prototypes.fluid[t.icon] then signal = {type = "fluid", name = t.icon} end
    top.add{type = "choose-elem-button", elem_type = "signal", signal = signal, tags = {pw = "ref-elem", path = p .. ".icon",
      kind = "thing"}}.style.size = 32
    W.remove_button(top, "technologies", i)
    W.ref_list(box, L("prerequisites"), p .. ".prerequisites", t.prerequisites, "tech", d, t.key)
    cost(box, p, t, d)
    W.checkbox(box, L("infinite"), p .. ".infinite", t.infinite, L("infinite-tooltip"))
    W.heading(box, L("rewards"))
    for j, e in ipairs(t.effects or {}) do
      local ep = p .. ".effects." .. j
      local f = box.add{type = "flow", direction = "horizontal"}
      f.style.vertical_align = "center"
      local items = {}
      for k, kind in ipairs(M.EFFECTS) do items[k] = L("effect-" .. kind) end
      f.add{type = "drop-down", items = items, selected_index = W.index_of(M.EFFECTS, e.type),
        tags = {pw = "effect-type", path = ep}}.style.width = 220
      if e.type == "unlock-recipe" or e.type == "change-recipe-productivity" then
        W.ref_picker(f, ep .. ".recipe", e.recipe, "recipe", d)
      end
      if e.type ~= "unlock-recipe" then
        local field = e.type == "change-recipe-productivity" and "change" or "modifier"
        f.add{type = "label", caption = "+"}
        W.number_field(f, ep .. "." .. field, e[field] or 0.1, true, 60, 0.01)
        f.add{type = "label", caption = "%"}
      end
      W.remove_button(f, p .. ".effects", j)
    end
    box.add{type = "button", caption = L("add-reward"), tags = {pw = "add", path = p .. ".effects",
      template = {type = "unlock-recipe", recipe = "@pack"}}}
  end
  c.add{type = "button", caption = L("add-technology"), tags = {pw = "add-technology"}}
end

return M
