#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -O Shared/Calculator.swift Shared/Currency.swift Shared/Words.swift Shared/Reminders.swift Shared/Selection.swift Tests/main.swift -o build/gus-tests 2>&1 | grep -v warning || true
build/gus-tests
