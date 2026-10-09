#!/usr/bin/env python3
"""Checks a published Days Until release's assets and update feed.

The app reads releases/latest/download/appcast.xml, so a release without a good feed leaves
everyone on the version they have. Given the release's assets downloaded into one folder, this
checks that the disk image, the zip and appcast.xml are there; that the zip holds Days Until.app;
that the feed names this version and the project's build number; that its enclosure is this
release's zip with the zip's length; and that the zip's EdDSA signature verifies against
SUPublicEDKey in DaysUntil/Info.plist. Needs OpenSSL 3 for Ed25519.

Usage: scripts/check-release.py <assets folder> --tag v0.4.2
    --project     a checkout of the release's tag (default: this one)
"""

import argparse
import base64
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ElementTree
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPOSITORY = "https://github.com/soondubu137/days-until"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
# The DER header of an Ed25519 public key, before its 32 raw bytes.
ED25519_PUBLIC_KEY_PREFIX = bytes.fromhex("302a300506032b6570032100")


def signature_verifies(zip_path, signature, public_key):
    with tempfile.TemporaryDirectory() as folder:
        key_path = os.path.join(folder, "key.der")
        signature_path = os.path.join(folder, "signature")
        with open(key_path, "wb") as file:
            file.write(ED25519_PUBLIC_KEY_PREFIX + base64.b64decode(public_key))
        with open(signature_path, "wb") as file:
            file.write(base64.b64decode(signature))
        result = subprocess.run(
            ["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", key_path, "-keyform", "DER", "-rawin",
             "-in", zip_path, "-sigfile", signature_path],
            capture_output=True, text=True)
        return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("assets", help="a folder with the release's assets")
    parser.add_argument("--tag", required=True, help="the release tag, e.g. v0.4.2")
    parser.add_argument("--project", default=ROOT)
    args = parser.parse_args()

    version = args.tag.removeprefix("v")
    zip_name = f"DaysUntil-{version}.zip"
    zip_path = os.path.join(args.assets, zip_name)
    feed_path = os.path.join(args.assets, "appcast.xml")
    missing = [name for name in [f"DaysUntil-{version}.dmg", zip_name, "appcast.xml"]
               if not os.path.isfile(os.path.join(args.assets, name))]
    if missing:
        sys.exit(f"The release is missing {', '.join(missing)}")

    project = open(os.path.join(args.project, "DaysUntil.xcodeproj/project.pbxproj"), encoding="utf-8").read()
    build = re.search(r"CURRENT_PROJECT_VERSION = ([^;]+);", project).group(1)
    with open(os.path.join(args.project, "DaysUntil/Info.plist"), "rb") as file:
        public_key = plistlib.load(file)["SUPublicEDKey"]

    problems = []
    with zipfile.ZipFile(zip_path) as archive:
        tops = {name.split("/")[0] for name in archive.namelist()} - {"__MACOSX"}
    if tops != {"Days Until.app"}:
        problems.append(f"{zip_name} holds {sorted(tops)}, not Days Until.app")

    items = ElementTree.parse(feed_path).getroot().findall("channel/item")
    if len(items) != 1:
        sys.exit(f"appcast.xml has {len(items)} items, not one")
    item = items[0]
    for field, expected in [("shortVersionString", version), ("version", build)]:
        found = item.findtext(SPARKLE + field)
        if found != expected:
            problems.append(f"appcast.xml's sparkle:{field} is {found}, not {expected}")
    enclosure = item.find("enclosure")
    if enclosure is None:
        sys.exit("appcast.xml has no enclosure")
    url = f"{REPOSITORY}/releases/download/{args.tag}/{zip_name}"
    if enclosure.get("url") != url:
        problems.append(f"appcast.xml points at {enclosure.get('url')}, not {url}")
    if enclosure.get("length") != str(os.path.getsize(zip_path)):
        problems.append(f"appcast.xml gives the zip's length as {enclosure.get('length')}, not {os.path.getsize(zip_path)}")
    signature = enclosure.get(SPARKLE + "edSignature")
    if not signature or not signature_verifies(zip_path, signature, public_key):
        problems.append(f"appcast.xml's EdDSA signature doesn't verify {zip_name} against SUPublicEDKey")

    if problems:
        sys.exit(f"Release {args.tag}:\n" + "\n".join(f"- {p}" for p in problems))
    print(f"Release {args.tag}: dmg, zip and appcast.xml for {version} ({build}), signature verified")


if __name__ == "__main__":
    main()
