-- Test helper (not part of the mod): when a test map is made (--create), builds things on Brimstone, so a later
-- run can load the save with its code removed or changed (tools/run_tests.sh, suite "existing").
script.on_init(function()
  local planet = game.planets["pw-brim0001"]
  if not planet then return end
  local s = planet.create_surface()
  s.request_to_generate_chunks({0, 0}, 3)
  s.force_generate_chunk_requests()
  local force = game.forces.player
  force.technologies["pw-brim0001-discovery"].researched = true
  local chest = s.create_entity{name = "steel-chest", position = {3.5, 3.5}, force = force}
  chest.insert{name = "pw-brim0001-ore-sulfite", count = 100}
  chest.insert{name = "pw-brim0001-pack", count = 10}
  local lab = s.create_entity{name = "lab", position = {10.5, 10.5}, force = force}
  lab.insert{name = "pw-brim0001-pack", count = 5}
  s.create_entity{name = "assembling-machine-2", position = {-10.5, 10.5}, force = force, recipe = "pw-brim0001-pack"}
  storage.setup_done = true
end)
