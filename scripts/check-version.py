#!/usr/bin/env python3
"""Checks that every place showing Days Until's version agrees.

A version bump touches MARKETING_VERSION and CURRENT_PROJECT_VERSION in every build configuration
of the project, the version badge in each README, and "Version x (n)" in docs/DESIGN.md, where the
About panel is described. With --tag, the tag must name the same version.

Usage: scripts/check-version.py [--tag v0.4.2]
"""

import argparse
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path):
    return open(os.path.join(ROOT, path), encoding="utf-8").read()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tag", help="the release tag, e.g. v0.4.2")
    args = parser.parse_args()

    project = read("DaysUntil.xcodeproj/project.pbxproj")
    versions = sorted(set(re.findall(r"MARKETING_VERSION = ([^;]+);", project)))
    builds = sorted(set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", project)))
    if len(versions) != 1 or len(builds) != 1:
        sys.exit(f"The build configurations disagree: MARKETING_VERSION {versions}, CURRENT_PROJECT_VERSION {builds}")
    version, build = versions[0], builds[0]

    problems = []
    for path in sorted(glob.glob(os.path.join(ROOT, "README*.md"))):
        badges = re.findall(r'img\.shields\.io/badge/version-([^-"]+)-blue" alt="Version ([^"]+)"', read(path))
        if badges != [(version, version)]:
            problems.append(f"{os.path.basename(path)}: the version badge says {badges or 'nothing'}")
    about = re.findall(r'"Version ([^ ]+) \((\d+)\)"', read("docs/DESIGN.md"))
    if about != [(version, build)]:
        problems.append(f"docs/DESIGN.md: the About panel says {about or 'nothing'}")
    if args.tag and args.tag != f"v{version}":
        problems.append(f"The tag {args.tag} doesn't match the version {version}")

    if problems:
        sys.exit(f"The project is at version {version} ({build}), but:\n" + "\n".join(f"- {p}" for p in problems))
    print(f"Version {version} ({build}) everywhere")


if __name__ == "__main__":
    main()
