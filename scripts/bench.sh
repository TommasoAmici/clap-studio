#!/bin/sh
# Measures library-scale PCA, clustering, layout and search: scripts/bench.sh [sampleCount] [embeddingDim]
set -e
. "$(dirname "$0")/env.sh"
cd "$ROOT"
exec "$SWIFT" run -c release ClapBench "$@"
