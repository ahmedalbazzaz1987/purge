#!/bin/bash
#
#  update.sh — updates Purge from source.
#
#  The in-app updater downloads a prebuilt release. This script is the other
#  route: pull the latest commit from GitHub and rebuild locally.
#
#      ./update.sh            pull and rebuild into ./build
#      ./update.sh --install  pull, rebuild, and replace /Applications/Purge.app
#

set -euo pipefail
cd "$(dirname "$0")"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
info() { printf '  \033[36m•\033[0m %s\n' "$1"; }

bold "Updating Purge from source"

if [ ! -d .git ]; then
  echo
  echo "  This folder is not a git checkout, so there is nothing to pull."
  echo "  Either download the latest zip from your Releases page, or set the"
  echo "  repository up once:"
  echo
  echo "      git init"
  echo "      git remote add origin https://github.com/<owner>/<repo>.git"
  echo "      git fetch origin && git reset --hard origin/main"
  echo
  exit 1
fi

BEFORE=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

if [ -n "$(git status --porcelain)" ]; then
  info "You have local changes — stashing them"
  git stash push -u -m "purge-update-$(date +%s)" >/dev/null
  STASHED=1
fi

git pull --ff-only
AFTER=$(git rev-parse --short HEAD)

if [ "$BEFORE" = "$AFTER" ]; then
  ok "Already on the newest commit ($AFTER)"
else
  ok "Updated $BEFORE → $AFTER"
  git log --oneline "$BEFORE..$AFTER" | sed 's/^/      /'
fi

if [ "${STASHED:-0}" = "1" ]; then
  info "Restoring your local changes: git stash pop"
  git stash pop || true
fi

echo
./build.sh "$@"
