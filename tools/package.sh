#!/bin/bash
# Zips the mod for the mod portal (and for testers): dist/planet-workshop_<version>.zip (folder inside named the same).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(python3 -c "import json;print(json.load(open('$ROOT/planet-workshop/info.json'))['version'])")
NAME="planet-workshop_$VERSION"
mkdir -p "$ROOT/dist"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp -r "$ROOT/planet-workshop" "$TMP/$NAME"
python3 -c "import shutil,sys; shutil.make_archive(sys.argv[1], 'zip', sys.argv[2], sys.argv[3])" "$ROOT/dist/$NAME" "$TMP" "$NAME"
echo "$ROOT/dist/$NAME.zip"
