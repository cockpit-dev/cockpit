#!/usr/bin/env bash
set -euo pipefail

workspace_pubspec="${1:-pubspec.yaml}"
console_member='  - packages/cockpit_console'

if [[ ! -f "$workspace_pubspec" ]]; then
  echo "Workspace pubspec not found: $workspace_pubspec" >&2
  exit 1
fi

member_count="$(grep -Fxc "$console_member" "$workspace_pubspec" || true)"
if [[ "$member_count" != '1' ]]; then
  echo "Expected exactly one cockpit_console workspace member, found $member_count." >&2
  exit 1
fi

temporary_pubspec="${workspace_pubspec}.minimum-flutter"
awk -v member="$console_member" '$0 != member { print }' \
  "$workspace_pubspec" >"$temporary_pubspec"
mv "$temporary_pubspec" "$workspace_pubspec"
