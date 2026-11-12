#!/bin/bash
# Multiplayer check (needs a desktop: the client is a real game window): a headless server runs the Planet
# Designer, a client joins, and tests/pw-mp drives the designer on every peer (examples, sections, previews, test
# play, share window and picture, then a deterministic monkey). Passes if both logs reach MPDONE with no desync.
# Runs in a throwaway folder; never touches ~/.factorio.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORIO="${FACTORIO:-/mnt/GamingSSD/SteamLibrary/steamapps/common/Factorio/bin/x64/factorio}"
W="$(mktemp -d)"; echo "(work folder: $W)"
mkdir -p "$W/mods/pw-codes" "$W/server" "$W/client"
cp -r "$ROOT/planet-workshop" "$W/mods/planet-workshop"
cp -r "$ROOT/tests/pw-mp" "$W/mods/pw-mp"
cp "$ROOT/tests/pw-codes/info.json" "$ROOT/tests/pw-codes/settings-final-fixes.lua" "$W/mods/pw-codes/"
cp "$ROOT/planet-workshop/script/examples.lua" "$W/mods/pw-codes/codes.lua"
cat > "$W/mods/mod-list.json" <<'J'
{"mods":[{"name":"base","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},{"name":"elevated-rails","enabled":true},{"name":"planet-workshop","enabled":true},{"name":"pw-codes","enabled":true},{"name":"pw-mp","enabled":true}]}
J
printf '[path]\nread-data=__PATH__system-read-data__\nwrite-data=%s\n' "$W/server" > "$W/server.ini"
printf '[path]\nread-data=__PATH__system-read-data__\nwrite-data=%s\n' "$W/client" > "$W/client.ini"
printf '{"name":"pw-mp","description":"","tags":[],"max_players":0,"visibility":{"public":false,"lan":false},"require_user_verification":false,"auto_pause":false,"autosave_interval":0,"game_password":""}' > "$W/server.json"
timeout -s INT 200 "$FACTORIO" -c "$W/server.ini" --mod-directory "$W/mods" --start-server-load-scenario planet-workshop/planet-designer \
  --server-settings "$W/server.json" --port 34311 < /dev/null > "$W/server.log" 2>&1 &
until grep -q "Hosting game" "$W/server.log" 2>/dev/null; do sleep 1; done
SteamAppId=427520 SteamGameId=427520 timeout -s INT 150 "$FACTORIO" -c "$W/client.ini" --mod-directory "$W/mods" \
  --mp-connect 127.0.0.1:34311 --disable-audio < /dev/null > "$W/client.log" 2>&1 || true
wait || true
grep -h "MP\|desync\|Desync\|Error while" "$W/server.log" "$W/client.log" | grep -v "Got EOF" || true
if grep -q MPDONE "$W/server.log" && grep -q MPDONE "$W/client.log" && ! grep -qi desync "$W/server.log" "$W/client.log"; then
  echo "=== MULTIPLAYER PASSED"
else
  echo "=== MULTIPLAYER FAILED"; exit 1
fi
