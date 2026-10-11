#!/bin/bash
# Runs the tests with the Command Line Tools' Swift Testing (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

DEV=/Library/Developer/CommandLineTools/Library/Developer
swift test \
    -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
    -Xlinker -F -Xlinker "$DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$DEV/usr/lib" \
    "$@"
