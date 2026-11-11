-- The one startup setting: the planet codes to load. Several codes can be pasted one after another.
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
}
