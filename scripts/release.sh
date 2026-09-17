#!/bin/bash
#
#  scripts/release.sh — cut a new version.
#
#      ./scripts/release.sh 1.0.1
#
#  Bumps the version in the two places that hold it, commits, tags and pushes.
#  GitHub Actions then builds the app and attaches the zip to the release,
#  which is what the in-app updater looks for.
#

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/release.sh <version>    e.g. ./scripts/release.sh 1.0.1"
  exit 1
fi

if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Version must look like 1.2.3"
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Commit or stash your changes first."
  exit 1
fi

# The two places the version lives.
sed -i '' "s/^VERSION=\".*\"/VERSION=\"$VERSION\"/" build.sh
sed -i '' "s/static let version = \".*\"/static let version = \"$VERSION\"/" Sources/Models.swift

echo "Version set to $VERSION:"
grep -n 'VERSION=' build.sh | head -1
grep -n 'static let version' Sources/Models.swift

git add build.sh Sources/Models.swift
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin HEAD
git push origin "v$VERSION"

echo
echo "Pushed v$VERSION. Watch the build:"
echo "  https://github.com/$(git remote get-url origin | sed 's#.*github.com[:/]##;s/\.git$//')/actions"
