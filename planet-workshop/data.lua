-- The designer's ore brush: a selection tool for placing the planet's own ores in a hand-made start area
-- (script/designer/startedit.lua). Only ever in the cursor.
data:extend{
  {
    type = "selection-tool",
    name = "pw-ore-brush",
    icon = "__base__/graphics/icons/iron-ore.png",
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    hidden = true,
    subgroup = "other",
    order = "z[pw-ore-brush]",
    stack_size = 1,
    select = {border_color = {1, 0.75, 0.2}, mode = {"any-tile"}, cursor_box_type = "entity"},
    alt_select = {border_color = {1, 0.3, 0.3}, mode = {"any-tile"}, cursor_box_type = "not-allowed"},
  },
}
