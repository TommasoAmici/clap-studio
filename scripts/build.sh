#!/bin/sh
# Debug or release build of the Swift package: scripts/build.sh [-c release]
set -e
. "$(dirname "$0")/env.sh"
cd "$ROOT"
exec "$SWIFT" build "$@"
