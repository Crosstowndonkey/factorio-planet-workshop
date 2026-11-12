#!/bin/bash
# Runs the test suites headless in a throwaway folder (never touches ~/.factorio).
# Usage: tools/run_tests.sh [suite ...]      suites: bridge terrain designer startarea roundtrip sameworld testplay startplanet homestead share examples fuzz monkey monkeyload saveload existing scenario codec added (roundtrip needs designer and startarea) (default: all)
# FACTORIO=/path/to/factorio overrides the game binary. KEEP=1 keeps the throwaway folder (its path is printed).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORIO="${FACTORIO:-/mnt/GamingSSD/SteamLibrary/steamapps/common/Factorio/bin/x64/factorio}"
SUITES=("$@")
[ ${#SUITES[@]} -eq 0 ] && SUITES=(bridge terrain designer startarea roundtrip sameworld testplay startplanet homestead share examples fuzz monkey monkeyload saveload existing scenario codec added)
WORK="$(mktemp -d)"
if [ -n "$KEEP" ]; then echo "(work folder: $WORK)"; else trap 'rm -rf "$WORK"' EXIT; fi
mkdir -p "$WORK/mods" "$WORK/write"
ln -s "$ROOT/planet-workshop" "$WORK/mods/planet-workshop"
ln -s "$ROOT/tests/pw-tests" "$WORK/mods/pw-tests"
ln -s "$ROOT/tests/pw-setup" "$WORK/mods/pw-setup"
# pw-codes is copied, not linked: the codes file is written into it
mkdir -p "$WORK/mods/pw-codes"
\cp -f "$ROOT/tests/pw-codes/"* "$WORK/mods/pw-codes/"
python3 "$ROOT/tools/make_code.py" --each "$ROOT"/tests/planets/brimstone.json "$ROOT"/tests/planets/frostbite.json \
  "$ROOT"/tests/planets/glacier.json "$ROOT"/tests/planets/cinder.json "$ROOT"/tests/planets/verdant.json \
  "$ROOT"/tests/planets/bloom.json "$ROOT"/tests/planets/dustbowl.json "$ROOT"/tests/planets/pond.json \
  --extra "PW1:bm90IGEgcmVhbCBjb2Rl" --extra "PW9:AAAA" --lua "$WORK/test-codes.lua"

mod_list() {  # mod_list <true|false: load the test codes> [true: the pw-setup mod too]
  cat > "$WORK/mods/mod-list.json" <<JSON
{"mods":[{"name":"base","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},
{"name":"elevated-rails","enabled":true},{"name":"recycler","enabled":true},{"name":"planet-workshop","enabled":true},
{"name":"pw-tests","enabled":true},{"name":"pw-codes","enabled":$1},{"name":"pw-setup","enabled":${2:-false}}]}
JSON
}
printf '[path]\nread-data=__PATH__system-read-data__\nwrite-data=%s\n' "$WORK/write" > "$WORK/config.ini"
# Factorio stores setting values in mods/mod-settings.dat; removing it before each run makes the setting
# fall back to its default, which pw-codes sets (so a run without pw-codes really has no codes).
run() { \rm -f "$WORK/mods/mod-settings.dat"; "$FACTORIO" -c "$WORK/config.ini" --mod-directory "$WORK/mods" "$@"; }
report() {  # report <log>: the STA lines, and any error
  grep -E "^STA" "$1" || true
  if grep -qE "Error while|non-recoverable|Failed to load|errored|Error ModManager|Error Util" "$1"; then
    grep -E -A12 "Error while|non-recoverable|Failed to load|errored|Error ModManager|Error Util" "$1" | head -60
  fi
}

FAILED=0
for suite in "${SUITES[@]}"; do
  echo "=== $suite"
  \cp -f "$WORK/test-codes.lua" "$WORK/mods/pw-codes/codes.lua" # (roundtrip swaps in its own code)
  \rm -f "$WORK/mods/pw-codes/start.lua"
  if [ "$suite" = existing ]; then
    # a save with Brimstone in use (pw-setup builds on it), loaded again with its code removed, changed, and with a
    # starting planet set after the game began
    mod_list true true
    run --create "$WORK/existing.zip" > "$WORK/existing-create.log" 2>&1 || { tail -30 "$WORK/existing-create.log"; exit 1; }
    python3 - "$ROOT/tests/planets/brimstone.json" "$WORK/brim-changed.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); p = d["planets"][0] if "planets" in d else d
p["ores"] = []; p["science"] = None; p["recipes"] = []; p["technologies"] = []
p["resources"] = [r for r in p["resources"] if not r["resource"].startswith("@")]
json.dump(p, open(sys.argv[2], "w"))
PY
    for phase in removed changed start; do
      \cp -f "$WORK/existing.zip" "$WORK/existing-$phase.zip"
      \rm -f "$WORK/mods/pw-codes/start.lua"
      case $phase in
        removed) printf 'return ""\n' > "$WORK/mods/pw-codes/codes.lua" ;;
        changed) python3 "$ROOT/tools/make_code.py" "$WORK/brim-changed.json" --lua "$WORK/mods/pw-codes/codes.lua" > /dev/null ;;
        start) \cp -f "$WORK/test-codes.lua" "$WORK/mods/pw-codes/codes.lua"; printf 'return "Brimstone"\n' > "$WORK/mods/pw-codes/start.lua" ;;
      esac
      mod_list true false
      run --test-save "$WORK/existing-$phase.zip" --test-ticks 600 --test-arg "existing-$phase" > "$WORK/existing-$phase.log" 2>&1 || true
      report "$WORK/existing-$phase.log"
      grep -q "STA existing-$phase: .* 0 failed" "$WORK/existing-$phase.log" || FAILED=1
    done
    continue
  fi
  if [ "$suite" = scenario ]; then
    # the Planet Designer scenario starts on a headless server without errors
    mod_list false
    printf '{"name":"pw-test","description":"","tags":[],"max_players":0,"visibility":{"public":false,"lan":false},"require_user_verification":false,"auto_pause":false,"autosave_interval":0,"game_password":""}' > "$WORK/server.json"
    \rm -f "$WORK/mods/mod-settings.dat"
    timeout -s INT 20 "$FACTORIO" -c "$WORK/config.ini" --mod-directory "$WORK/mods" \
      --start-server-load-scenario planet-workshop/planet-designer --server-settings "$WORK/server.json" --port 34298 \
      < /dev/null > "$WORK/scenario.log" 2>&1 || true
    if grep -q "Planet Designer started" "$WORK/scenario.log" && ! grep -E "Error|error while" "$WORK/scenario.log" | grep -qv "Got EOF on stdin"; then
      echo "STA scenario: 1 passed, 0 failed"
    else
      grep -E -A8 "Error|error" "$WORK/scenario.log" | grep -v "Got EOF" | head -30
      echo "STA scenario: 0 passed, 1 failed"; FAILED=1
    fi
    continue
  fi
  if [ "$suite" = roundtrip ]; then
    # load the planet the designer suite made (its Get code saved the code) in a new game
    code=$(cat "$WORK"/write/script-output/planet-workshop/Roundtrip-*.txt "$WORK"/write/script-output/planet-workshop/Startland-*.txt 2>/dev/null | tr '\n' ' ')
    if [ -z "$code" ]; then echo "STA roundtrip: 0 passed, 1 failed (run the designer suite first)"; FAILED=1; continue; fi
    printf -- '-- the code the designer suite made\nreturn "%s"\n' "$code" > "$WORK/mods/pw-codes/codes.lua"
    mod_list true
    run --create "$WORK/roundtrip.zip" > "$WORK/roundtrip-create.log" 2>&1 || { tail -30 "$WORK/roundtrip-create.log"; exit 1; }
  elif [ "$suite" = saveload ]; then
    # a designer game saved mid test play (made in a real game: tests can't save), with the examples loaded
    \cp -f "$ROOT/planet-workshop/script/examples.lua" "$WORK/mods/pw-codes/codes.lua"
    mod_list true
    \cp -f "$ROOT/tests/fixtures/designer-0.9.0-test-play.zip" "$WORK/saveload.zip"
  elif [ "$suite" = fuzz ]; then
    # a new game with 60+ random planets, half of them broken (FUZZ_SEED picks another set)
    python3 "$ROOT/tools/fuzz_planets.py" --seed "${FUZZ_SEED:-1}" --count "${FUZZ_COUNT:-60}" --lua "$WORK/mods/pw-codes/codes.lua" > /dev/null
    mod_list true
    run --create "$WORK/fuzz.zip" > "$WORK/fuzz-create.log" 2>&1 || { tail -40 "$WORK/fuzz-create.log"; exit 1; }
  elif [ "$suite" = examples ]; then
    # a new game with only the example planets loaded
    \cp -f "$ROOT/planet-workshop/script/examples.lua" "$WORK/mods/pw-codes/codes.lua"
    mod_list true
    run --create "$WORK/examples.zip" > "$WORK/examples-create.log" 2>&1 || { tail -30 "$WORK/examples-create.log"; exit 1; }
  elif [ "$suite" = homestead ]; then
    # a new game started on a planet with the biggest hand-made start area (a lake on the landing spot)
    python3 "$ROOT/tools/make_code.py" "$ROOT/tests/planets-extra/homestead.json" --lua "$WORK/mods/pw-codes/codes.lua" > /dev/null
    printf 'return "Homestead"\n' > "$WORK/mods/pw-codes/start.lua"
    mod_list true
    run --create "$WORK/homestead.zip" > "$WORK/homestead-create.log" 2>&1 || { tail -30 "$WORK/homestead-create.log"; exit 1; }
  elif [ "$suite" = startplanet ]; then
    # a new game with Verdant as the starting planet (by name, in another case)
    printf 'return "verdant"\n' > "$WORK/mods/pw-codes/start.lua"
    mod_list true
    run --create "$WORK/startplanet.zip" > "$WORK/startplanet-create.log" 2>&1 || { tail -30 "$WORK/startplanet-create.log"; exit 1; }
  elif [ "$suite" = monkeyload ]; then
    # the planets the monkey suite made, loaded as real planets
    code=$(cat "$WORK"/write/script-output/planet-workshop/Monkey-all.txt 2>/dev/null | head -1)
    if [ -z "$code" ]; then echo "STA monkeyload: 0 passed, 1 failed (run the monkey suite first)"; FAILED=1; continue; fi
    printf -- 'return "%s"\n' "$code" > "$WORK/mods/pw-codes/codes.lua"
    mod_list true
    run --create "$WORK/monkeyload.zip" > "$WORK/monkeyload-create.log" 2>&1 || { tail -30 "$WORK/monkeyload-create.log"; FAILED=1; continue; }
  elif [ "$suite" = added ]; then
    mod_list false   # make the save without any planet codes...
    run --create "$WORK/added.zip" > "$WORK/added-create.log" 2>&1 || { cat "$WORK/added-create.log"; exit 1; }
    mod_list true    # ...then load it with the codes
  else
    mod_list true
    [ -f "$WORK/map.zip" ] || run --create "$WORK/map.zip" > "$WORK/create.log" 2>&1 || { tail -40 "$WORK/create.log"; exit 1; }
    \cp -f "$WORK/map.zip" "$WORK/$suite.zip"
  fi
  run --test-save "$WORK/$suite.zip" --test-ticks 3000 --test-arg "$suite" > "$WORK/$suite.log" 2>&1 || true
  report "$WORK/$suite.log"
  grep -q "STA $suite: .* 0 failed" "$WORK/$suite.log" || FAILED=1
done
grep -h "Planet Workshop" "$WORK/write/factorio-current.log" 2>/dev/null | head -5 || true
[ $FAILED = 0 ] && echo "=== ALL PASSED" || { echo "=== SOME FAILED"; exit 1; }
