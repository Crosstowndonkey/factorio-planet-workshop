-- Every lab that takes the first vanilla science pack also takes the planets' own packs (this runs last, so
-- labs added by other mods are included).
local report = data.raw["mod-data"]["planet-workshop-report"].data

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

for _, planet in ipairs(report.planets) do
  if planet.pack then
    for _, lab in pairs(data.raw.lab or {}) do
      lab.inputs = lab.inputs or {}
      if contains(lab.inputs, "automation-science-pack") and not contains(lab.inputs, planet.pack) then
        table.insert(lab.inputs, planet.pack)
      end
    end
  end
end
