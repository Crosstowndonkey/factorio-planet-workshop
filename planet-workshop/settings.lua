-- Startup settings: the planet codes to load (several codes can be pasted one after another), and which of those
-- planets new games start on (empty: Nauvis).
data:extend{
  {
    type = "string-setting",
    name = "planet-workshop-planets",
    setting_type = "startup",
    default_value = "",
    allow_blank = true,
    auto_trim = true,
    order = "a",
  },
  {
    type = "string-setting",
    name = "planet-workshop-start-planet",
    setting_type = "startup",
    default_value = "",
    allow_blank = true,
    auto_trim = true,
    order = "b",
  },
}
