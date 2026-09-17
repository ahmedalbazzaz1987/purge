#!/bin/bash
#
#  uninstall.sh — removes Purge and everything it ever wrote.
#
#  The app can do this itself (Settings → Uninstall Purge). This script exists
#  so you can verify the claim by hand, or clean up after deleting the app.
#

set -uo pipefail

APP_NAME="Purge"
BUNDLE_ID="com.novamira.purge"

TARGETS=(
  "/Applications/$APP_NAME.app"
  "$HOME/Applications/$APP_NAME.app"
  "$HOME/Library/Application Support/$APP_NAME"
  "$HOME/Library/Preferences/$BUNDLE_ID.plist"
  "$HOME/Library/Caches/$BUNDLE_ID"
  "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
  "$HOME/Library/HTTPStorages/$BUNDLE_ID"
  "$HOME/Library/WebKit/$BUNDLE_ID"
)

printf '\033[1mRemoving Purge\033[0m\n\n'

FOUND=0
for t in "${TARGETS[@]}"; do
  if [ -e "$t" ]; then
    FOUND=1
    SIZE=$(du -sh "$t" 2>/dev/null | cut -f1 | tr -d ' ')
    printf '  found  %s  (%s)\n' "$t" "$SIZE"
  fi
done

if [ "$FOUND" = "0" ]; then
  printf '  Nothing to remove — Purge left no trace.\n\n'
  exit 0
fi

printf '\n  Remove all of the above? [y/N] '
read -r answer
case "$answer" in
  [yY]*) ;;
  *) printf '  Cancelled.\n'; exit 0 ;;
esac

for t in "${TARGETS[@]}"; do
  [ -e "$t" ] || continue
  if rm -rf "$t" 2>/dev/null; then
    printf '  \033[32m✓\033[0m removed  %s\n' "$t"
  else
    printf '  \033[31m✗\033[0m could not remove  %s\n' "$t"
  fi
done

defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

printf '\n  Done. Purge is gone.\n'
printf '  Files you cleaned with it are unaffected.\n\n'
