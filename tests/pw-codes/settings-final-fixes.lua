-- Test helper (not part of the mod): puts the test planet codes into the startup setting, as if a player had
-- pasted them. tools/run_tests.sh writes codes.lua next to this file in its throwaway folder (and start.lua, the
-- starting planet, for the startplanet suite).
data.raw["string-setting"]["planet-workshop-planets"].default_value = require("codes")
local ok, start = pcall(require, "start")
if ok and type(start) == "string" then
  data.raw["string-setting"]["planet-workshop-start-planet"].default_value = start
end
