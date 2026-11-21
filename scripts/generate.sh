#!/bin/bash
# Makes Gus.xcodeproj from project.yml (it isn't kept in the repository).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate -q
