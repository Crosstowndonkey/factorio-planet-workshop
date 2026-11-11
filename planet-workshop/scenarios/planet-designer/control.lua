-- The Planet Designer scenario: everything is in the Planet Workshop mod (script/designer); this only switches
-- it on for this game.
script.on_init(function()
  remote.call("planet-workshop", "start_designer")
end)
