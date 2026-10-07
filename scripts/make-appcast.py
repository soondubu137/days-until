#!/usr/bin/env python3
"""Writes the Sparkle feed for a Days Until release: appcast.xml, with the one newest version.

The feed is uploaded as an asset of each GitHub release, and the app reads it from
releases/latest/download/appcast.xml, so it always names the latest release. Its enclosure is the
release's notarized zip, signed with Sparkle's sign_update. The key it signs with is the EdDSA
private key in the login keychain, whose public half is SUPublicEDKey in DaysUntil/Info.plist.

The release notes are Markdown, the release's own bullets without the install steps. Sparkle shows
them in its update window.

Usage: scripts/make-appcast.py DaysUntil-0.3.0.zip --version 0.3.0 --build 8 --notes notes.md > appcast.xml
    --url             where the zip is downloaded from (default: the release's asset on GitHub)
    --sign-update     Sparkle's sign_update (default: the one Xcode fetched with the package)
    --ed-key-file     sign with a key file instead of the keychain
"""

import argparse
import email.utils
import glob
import os
import re
import subprocess
import sys
from xml.sax.saxutils import escape, quoteattr

REPOSITORY = "https://github.com/soondubu137/days-until"
MINIMUM_SYSTEM_VERSION = "13.0"


def find_sign_update():
    pattern = os.path.expanduser("~/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update")
    found = sorted(glob.glob(pattern), key=os.path.getmtime)
    if not found:
        sys.exit("Couldn't find Sparkle's sign_update; build the app once, or pass --sign-update.")
    return found[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("zip")
    parser.add_argument("--version", required=True, help="CFBundleShortVersionString, e.g. 0.3.0")
    parser.add_argument("--build", required=True, help="CFBundleVersion, e.g. 8")
    parser.add_argument("--notes", required=True, help="a Markdown file")
    parser.add_argument("--url")
    parser.add_argument("--sign-update")
    parser.add_argument("--ed-key-file")
    args = parser.parse_args()

    command = [args.sign_update or find_sign_update()]
    if args.ed_key_file:
        command += ["--ed-key-file", args.ed_key_file]
    signed = subprocess.run(command + [args.zip], check=True, capture_output=True, text=True).stdout
    signature = re.search(r'sparkle:edSignature="([^"]+)"', signed).group(1)
    length = re.search(r'length="(\d+)"', signed).group(1)

    url = args.url or f"{REPOSITORY}/releases/download/v{args.version}/{os.path.basename(args.zip)}"
    notes = open(args.notes, encoding="utf-8").read().strip()
    if "]]>" in notes:
        sys.exit("The notes can't contain ]]>.")

    print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Days Until</title>
    <link>{escape(REPOSITORY)}</link>
    <item>
      <title>{escape(args.version)}</title>
      <pubDate>{email.utils.formatdate(localtime=False, usegmt=True)}</pubDate>
      <sparkle:version>{escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MINIMUM_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{escape(REPOSITORY)}/releases</sparkle:fullReleaseNotesLink>
      <description sparkle:format="markdown"><![CDATA[{notes}]]></description>
      <enclosure url={quoteattr(url)} length="{length}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
    </item>
  </channel>
</rss>""")


if __name__ == "__main__":
    main()
