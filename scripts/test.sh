#!/bin/sh
# Runs the Swift Testing suite. With only the Command Line Tools installed the
# Testing macro plugin must be passed explicitly (see env.sh).
set -e
. "$(dirname "$0")/env.sh"
cd "$ROOT"
exec "$SWIFT" test -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGINS" "$@"
