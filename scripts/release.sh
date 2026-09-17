#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/release.sh <version>    e.g. ./scripts/release.sh 1.0.4"
  exit 1
fi

if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Version must look like 1.2.3"
  exit 1
fi

if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "Tag v$VERSION already exists."
  echo "Pick a higher version, or delete the old tag first:"
  echo "    git tag -d v$VERSION && git push origin :refs/tags/v$VERSION"
  exit 1
fi

OTHER_CHANGES="$(git status --porcelain | grep -v -e 'build.sh' -e 'Sources/Models.swift' || true)"
if [ -n "$OTHER_CHANGES" ]; then
  echo "Commit or stash your other changes first:"
  echo "$OTHER_CHANGES"
  exit 1
fi

sed -i '' "s/^VERSION=\".*\"/VERSION=\"$VERSION\"/" build.sh
sed -i '' "s/static let version = \".*\"/static let version = \"$VERSION\"/" Sources/Models.swift

echo "Version set to $VERSION:"
grep -n 'VERSION=' build.sh | head -1
grep -n 'static let version' Sources/Models.swift

if git diff --quiet -- build.sh Sources/Models.swift; then
  echo "Sources already say $VERSION — nothing to commit, tagging as is."
else
  git add build.sh Sources/Models.swift
  git commit -m "Release $VERSION"
fi

git tag "v$VERSION"
git push origin HEAD
git push origin "v$VERSION"

SLUG="$(git remote get-url origin | sed 's#.*github.com[:/]##;s/\.git$//')"
echo
echo "Pushed v$VERSION. Watch the build:"
echo "  https://github.com/$SLUG/actions"
echo "The release appears here once it finishes:"
echo "  https://github.com/$SLUG/releases"
