#!/bin/sh
# Runs the Swift Testing suite. With only the Command Line Tools installed the
# Testing macro plugin must be passed explicitly.
set -e
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swift 2>/dev/null || command -v swift)")/../lib/swift/host/plugins/testing"
exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
