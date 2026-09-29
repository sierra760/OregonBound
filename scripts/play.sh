#!/bin/bash
set -euo pipefail

TRAIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRAIL_BUILD="${TRAIL_ROOT}/build/DerivedData"

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --spec "${TRAIL_ROOT}/OregonBound/project.yml"
fi

xcodebuild -quiet -project "${TRAIL_ROOT}/OregonBound/OregonBound.xcodeproj" \
    -scheme OregonBound -configuration Debug -destination "platform=macOS" \
    -derivedDataPath "${TRAIL_BUILD}" build CODE_SIGNING_ALLOWED=NO

open "${TRAIL_BUILD}/Build/Products/Debug/Oregon Bound.app"
