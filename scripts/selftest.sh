#!/bin/bash
# Runs every feature inside the real app (so macOS permissions apply to Gus) and prints the report.
# Quit Gus first: two copies would fight over the shortcut. Asks the engine picked in Settings two short
# questions, creates and removes two test reminders, and puts the clipboard back.
set -euo pipefail
cd "$(dirname "$0")/.."
report="$(mktemp -t gus-selftest).txt"
pkill -x Gus 2>/dev/null || true
sleep 1
open -n build/Gus.app --args --selftest "$report"
for _ in $(seq 1 150); do [ -s "$report" ] && break; sleep 2; done
cat "$report"
tail -1 "$report" | grep -q " 0 failed"
