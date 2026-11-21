#!/bin/bash
# Builds Gus and copies it to build/Gus.app.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/generate.sh
xcodebuild -project Gus.xcodeproj -scheme Gus -configuration "${1:-Release}" -derivedDataPath build/dd \
    -allowProvisioningUpdates build | grep -E "error|BUILD" || true
rm -rf build/Gus.app && cp -R "build/dd/Build/Products/${1:-Release}/Gus.app" build/Gus.app
echo build/Gus.app
