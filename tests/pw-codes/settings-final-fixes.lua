-- Test helper (not part of the mod): puts the test planet codes into the startup setting, as if a player had
-- pasted them. tools/run_tests.sh writes codes.lua next to this file in its throwaway folder.
data.raw["string-setting"]["planet-workshop-planets"].default_value = require("codes")
