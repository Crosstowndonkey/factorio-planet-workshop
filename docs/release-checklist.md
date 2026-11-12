# Release checklist

Before publishing a release, after `tools/run_tests.sh` passes (and `tools/mp_test.sh` for bigger changes), play it
for about 15 minutes in your real game with only Planet Workshop and Space Age enabled.

1. **Designer.** New game > Scenarios > Planet Designer. Does "How it works" open? Make a small planet: pick ground
   tiles, a liquid, "Add the resources of: Nauvis", maybe an own ore. Does the preview follow your changes?
2. **Check and test play.** Open Checks: anything surprising? Press Test play, walk around, mine something, go back.
3. **Get code and save.** Get code, Ctrl+C. Esc > Save game. Quit to the main menu.
4. **Add it.** Settings > Mod settings > Startup > Planet codes: paste, Confirm. Does the game restart without errors?
5. **Play it.** New game (Freeplay). Open the research screen: is "Planet discovery <your planet>" there? Use the
   console (`/c game.player.force.research_all_technologies()`, achievements off - use a throwaway save) to check
   it unlocks, build a platform or use the map editor to visit, and check the planet looks like the preview.
6. **Starting planet.** Settings > Mod settings > Startup > Starting planet: type its name, new Freeplay game. Do
   you crash-land there?
7. **Back in the designer.** Load the designer save: are your designs there? Import the code again: same planet?
8. Clear the two settings again if you don't want the planet in your normal games.
