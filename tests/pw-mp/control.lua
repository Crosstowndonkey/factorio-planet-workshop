-- Multiplayer test driver (not part of the mod; tools/mp_test.sh). It runs on every peer, so the actions happen everywhere:
-- joined player through a fixed script, then a deterministic monkey, and logs MPDONE.
local function R(...) return remote.call("planet-workshop", ...) end
local function find(el, test)
  if el.tags and test(el.tags, el) then return el end
  for _, c in ipairs(el.children) do local f = find(c, test) if f then return f end end
end
local function select(p, i)
  local dd = find(p.gui.screen.pw_designer, function(t) return t.pw == "select-design" end)
  if dd and dd.items[i] then dd.selected_index = i; R("designer_event", "on_gui_selection_state_changed", {element = dd, player_index = p.index}) end
end
local SKIP = {["start-edit"] = true, walk = true, minimize = true, restore = true, brush = true, ["test-start"] = true}
script.on_event(defines.events.on_tick, function(e)
  local p
  for _, pl in pairs(game.players) do if pl.connected then p = pl end end
  if not (p and p.gui.screen.pw_designer) and not storage.t0 then return end
  storage.t0 = storage.t0 or e.tick
  local t = e.tick - storage.t0
  if not (p and p.valid) then return end
  if t == 60 then R("designer_do", p.index, "examples"); log("MP examples")
  elseif t == 120 then select(p, 2); R("designer_tab", p.index, "terrain")
  elseif t == 300 then select(p, 3); R("designer_tab", p.index, "resources")
  elseif t == 480 then R("designer_do", p.index, "test-start")
  elseif t == 700 then R("designer_do", p.index, "test-stop"); log("MP testplay done")
  elseif t == 760 then R("designer_do", p.index, "share-picture"); R("designer_do", p.index, "get-code")
  elseif t == 800 then R("designer_do", p.index, "close", {window = "pw_designer_code"}); select(p, 4)
  elseif t > 900 and t < 2400 and t % 3 == 0 then
    storage.rng = storage.rng or game.create_random_generator(99)
    local rng = storage.rng
    local window = p.gui.screen.pw_designer
    if not window then return end
    local inputs = {}
    local function walk(el)
      if el.tags and el.tags.pw and not SKIP[el.tags.pw] and el.enabled ~= false then inputs[#inputs + 1] = el end
      for _, c in ipairs(el.children) do walk(c) end
    end
    walk(window)
    if #inputs == 0 then return end
    local el = inputs[rng(1, #inputs)]
    local ev = {element = el, player_index = p.index}
    if el.type == "button" or el.type == "sprite-button" then R("designer_event", "on_gui_click", ev)
    elseif el.type == "drop-down" and #el.items > 0 then el.selected_index = rng(1, #el.items); R("designer_event", "on_gui_selection_state_changed", ev)
    elseif el.type == "slider" then el.slider_value = el.get_slider_minimum() + rng() * (el.get_slider_maximum() - el.get_slider_minimum()); R("designer_event", "on_gui_value_changed", ev)
    elseif el.type == "checkbox" then el.state = not el.state; R("designer_event", "on_gui_checked_state_changed", ev)
    end
  elseif t == 2500 then log("MPDONE designs=" .. #R("designer_designs") .. " tick=" .. e.tick)
  end
end)
