#!/bin/bash
# Runs the test suites headless in a throwaway folder (never touches ~/.factorio).
# Usage: tools/run_tests.sh [suite ...]      suites: bridge terrain designer roundtrip testplay scenario codec added (roundtrip needs designer) (default: all)
# FACTORIO=/path/to/factorio overrides the game binary. KEEP=1 keeps the throwaway folder (its path is printed).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORIO="${FACTORIO:-/mnt/GamingSSD/SteamLibrary/steamapps/common/Factorio/bin/x64/factorio}"
SUITES=("$@")
[ ${#SUITES[@]} -eq 0 ] && SUITES=(bridge terrain designer roundtrip testplay scenario codec added)
WORK="$(mktemp -d)"
if [ -n "$KEEP" ]; then echo "(work folder: $WORK)"; else trap 'rm -rf "$WORK"' EXIT; fi
mkdir -p "$WORK/mods" "$WORK/write"
ln -s "$ROOT/planet-workshop" "$WORK/mods/planet-workshop"
ln -s "$ROOT/tests/pw-tests" "$WORK/mods/pw-tests"
# pw-codes is copied, not linked: the codes file is written into it
mkdir -p "$WORK/mods/pw-codes"
\cp -f "$ROOT/tests/pw-codes/"* "$WORK/mods/pw-codes/"
python3 "$ROOT/tools/make_code.py" --each "$ROOT"/tests/planets/brimstone.json "$ROOT"/tests/planets/frostbite.json \
  "$ROOT"/tests/planets/glacier.json "$ROOT"/tests/planets/cinder.json "$ROOT"/tests/planets/verdant.json \
  "$ROOT"/tests/planets/bloom.json "$ROOT"/tests/planets/dustbowl.json "$ROOT"/tests/planets/pond.json \
  --extra "PW1:bm90IGEgcmVhbCBjb2Rl" --extra "PW9:AAAA" --lua "$WORK/test-codes.lua"

mod_list() {  # mod_list <true|false: load the test codes>
  cat > "$WORK/mods/mod-list.json" <<JSON
{"mods":[{"name":"base","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},
{"name":"elevated-rails","enabled":true},{"name":"recycler","enabled":true},{"name":"planet-workshop","enabled":true},
{"name":"pw-tests","enabled":true},{"name":"pw-codes","enabled":$1}]}
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
    code=$(cat "$WORK"/write/script-output/planet-workshop/Roundtrip-*.txt 2>/dev/null | head -1)
    if [ -z "$code" ]; then echo "STA roundtrip: 0 passed, 1 failed (run the designer suite first)"; FAILED=1; continue; fi
    printf -- '-- the code the designer suite made\nreturn "%s"\n' "$code" > "$WORK/mods/pw-codes/codes.lua"
    mod_list true
    run --create "$WORK/roundtrip.zip" > "$WORK/roundtrip-create.log" 2>&1 || { tail -30 "$WORK/roundtrip-create.log"; exit 1; }
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
