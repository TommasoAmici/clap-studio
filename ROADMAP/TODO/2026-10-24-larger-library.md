# Larger library support

Since the start of this project, my library of samples has grown past 50,000 samples. Let's update our tests and benchmarks and all things with a target library of 100,000 samples instead.


- [x] Exercise 100,000 rows in storage, search, projection, clustering and map hit-testing tests; remove avoidable per-row setup work.
- [ ] Make 100,000 samples the benchmark and documentation target, and record a full release measurement.

## Implementation context

The audit found no 50,000-sample limit in storage, search or map row indices.
MIDI note counts and drum/melody bar limits are unrelated and stay unchanged.
Scale regressions use the full row count with small streaming embeddings or
128-dimensional search vectors, so they remain suitable for the normal suite.
The expensive complete 2D layout stays in the release benchmark.

`LibraryAnalyzer.computeAll` previously discovered the embedding width through a
one-row streaming pass over the entire library. At 100,000 samples that made
100,001 SQLite queries before fitting PCA. `LibraryStore.embeddedDimension` now
uses one `SELECT length(embedding) / 2 ... LIMIT 1`; the stored Float16 width is
read without decoding every vector. The model and embeddings stay unchanged.

The regression suite was run red with an unavailable width lookup: only its
width assertion failed, while search, projection/clustering and map selection
already passed at 100,000 rows. No layout algorithm change was needed.

Validation for the first slice: `scripts/build.sh` passed with only the existing
Command Line Tools linker search-path warnings. The full `scripts/test.sh` passed
390 tests in 85 suites, including the installed CLAP/BirdNET model checks. The
standalone 100,000-row regression suite takes about 0.7 seconds on an M4 Pro.
