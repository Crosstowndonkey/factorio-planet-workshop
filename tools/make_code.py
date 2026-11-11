#!/usr/bin/env python3
"""Makes planet codes from planet JSON files (for tests, and for hand-made planets before the designer exists).

A code is "PW1:" + base64(zlib(JSON of {"planets": [...]})), the same thing helpers.encode_string makes in game.

  tools/make_code.py planet.json [more.json ...]          one pack code holding all the planets
  tools/make_code.py --each a.json b.json                 one code per planet, separated by spaces
  tools/make_code.py --lua out.lua [--extra TEXT] ...     a Lua file returning the codes (the test mod reads it)
  tools/make_code.py --decode CODE                        prints the JSON inside a code
"""
import argparse
import base64
import json
import sys
import zlib

PREFIX = "PW1:"


def encode(pack: dict) -> str:
    raw = json.dumps(pack, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return PREFIX + base64.b64encode(zlib.compress(raw, 9)).decode("ascii")


def decode(code: str) -> dict:
    head, _, body = code.strip().partition(":")
    if head != "PW1":
        raise SystemExit(f"not a PW1 code: {head!r}")
    return json.loads(zlib.decompress(base64.b64decode(body)))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*")
    ap.add_argument("--each", action="store_true", help="one code per planet file")
    ap.add_argument("--lua", help="write a Lua file that returns the codes")
    ap.add_argument("--extra", action="append", default=[], help="extra text to add to the codes (tests)")
    ap.add_argument("--decode", help="print the JSON inside a code")
    args = ap.parse_args()

    if args.decode:
        print(json.dumps(decode(args.decode), indent=2, ensure_ascii=False))
        return

    planets = []
    for path in args.files:
        with open(path, encoding="utf-8") as f:
            planets.append(json.load(f))
    if args.each:
        codes = [encode({"planets": [p]}) for p in planets]
    else:
        codes = [encode({"planets": planets})] if planets else []
    text = " ".join(codes + args.extra)

    if args.lua:
        with open(args.lua, "w", encoding="utf-8") as f:
            f.write("-- Made by tools/make_code.py: the planet codes the tests load.\n")
            f.write("return " + json.dumps(text) + "\n")
        print(f"wrote {args.lua} ({len(text)} characters)", file=sys.stderr)
    else:
        print(text)


if __name__ == "__main__":
    main()
