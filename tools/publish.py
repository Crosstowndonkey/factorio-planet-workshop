#!/usr/bin/env python3
"""Publishes Planet Workshop on the Factorio mod portal, or uploads a new release if it's already there.

Reads the API key from ~/.config/factorio/modportal-api-key (never pass it on the command line).
The key needs the usages "ModPortal: Publish Mods", "ModPortal: Upload Mods" and "ModPortal: Edit Mods"
(factorio.com/profile > API keys).

Usage: tools/publish.py [--first | --details | --gallery]
  (nothing)  upload a new release
  --first    brand-new mod: publish, then set details and the gallery
  --details  update the portal page from docs/portal-description.md; uploads no release
  --gallery  upload docs/gallery/* again and set them as the gallery (in file name order)
Uploading runs tools/package.sh first, so the zip is always fresh.
"""
import glob
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = "planet-workshop"
KEY_FILE = os.path.expanduser("~/.config/factorio/modportal-api-key")
API = "https://mods.factorio.com/api/v2/mods"
SOURCE = None  # the GitHub repo, once there is one
DESCRIPTION = os.path.join(ROOT, "docs", "portal-description.md")
GALLERY = os.path.join(ROOT, "docs", "gallery")
# sent with every details update, so they can't be cleared by being left out
DETAILS = [("tags", "environment"), ("tags", "enemies"), ("tags", "mining")]
if SOURCE:
    DETAILS.append(("homepage", SOURCE))


def key():
    with open(KEY_FILE) as f:
        return f.read().strip()


def curl(url, fields, auth=True):
    """POST multipart form fields with curl (values starting with @ are files). Returns parsed JSON."""
    args = ["curl", "-sS", "-X", "POST", url]
    if auth:
        # the key goes to curl through stdin, never onto the command line
        args += ["-H", "@-"]
    for name, value in fields:
        args += ["-F", f"{name}={value}"]
    header = f"Authorization: Bearer {key()}\n" if auth else ""
    out = subprocess.run(args, input=header, capture_output=True, text=True, check=True).stdout
    try:
        result = json.loads(out)
    except json.JSONDecodeError:
        sys.exit(f"Unexpected answer from {url}: {out[:500]}")
    if result.get("error"):
        sys.exit(f"{url}: {result['error']} - {result.get('message')}")
    return result


def gallery():
    ids = []
    for path in sorted(glob.glob(os.path.join(GALLERY, "*.jpg")) + glob.glob(os.path.join(GALLERY, "*.png"))):
        upload_url = curl(f"{API}/images/add", [("mod", MOD)])["upload_url"]
        image = curl(upload_url, [("image", "@" + path)], auth=False)
        print("Image:", os.path.basename(path), image.get("url"))
        ids.append(image["id"])
    curl(f"{API}/images/edit", [("mod", MOD), ("images", ",".join(ids))])
    print(f"Gallery set ({len(ids)} images).")


def main():
    if "--details" in sys.argv:
        details = curl(f"{API}/edit_details", [("mod", MOD), ("description", "<" + DESCRIPTION)] + DETAILS)
        print("Details updated:", details.get("url"))
        print(f"https://mods.factorio.com/mod/{MOD}")
        return
    if "--gallery" in sys.argv:
        gallery()
        return
    first = "--first" in sys.argv
    zip_path = subprocess.run([os.path.join(ROOT, "tools", "package.sh")], capture_output=True, text=True,
                              check=True).stdout.strip()
    print("Package:", zip_path)

    if first:
        upload_url = curl(f"{API}/init_publish", [("mod", MOD)])["upload_url"]
        fields = [("file", "@" + zip_path), ("description", "<" + DESCRIPTION), ("category", "content"),
                  ("license", "default_mit")]
        if SOURCE:
            fields.append(("source_url", SOURCE))
        result = curl(upload_url, fields, auth=False)
        print("Published:", result.get("url"))
        details = curl(f"{API}/edit_details", [("mod", MOD)] + DETAILS)
        print("Details:", details.get("url"))
        gallery()
    else:
        upload_url = curl(f"{API}/releases/init_upload", [("mod", MOD)])["upload_url"]
        result = curl(upload_url, [("file", "@" + zip_path)], auth=False)
        print("Release uploaded:", result)
    print(f"https://mods.factorio.com/mod/{MOD}")


if __name__ == "__main__":
    main()
