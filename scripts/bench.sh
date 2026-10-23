#!/bin/sh
# Measures storage, PCA, clustering, layout and search: scripts/bench.sh [sampleCount] [embeddingDim]
# Defaults to 100,000 samples x 2,048 dimensions; all generated library data is temporary.
set -e
. "$(dirname "$0")/env.sh"
cd "$ROOT"
exec "$SWIFT" run -c release ClapBench "$@"
