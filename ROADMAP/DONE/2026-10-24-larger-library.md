# Larger library support

Since the start of this project, my library of samples has grown past 50,000 samples. Let's update our tests and benchmarks and all things with a target library of 100,000 samples instead.


- [x] Exercise 100,000 rows in storage, search, projection, clustering and map hit-testing tests; remove avoidable per-row setup work.
- [x] Make 100,000 samples the benchmark and documentation target, and record a full release measurement.

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


`Sources/ClapBench/StoreBench.swift` measures sample-row synchronization,
unchanged rescans, reopening SQLite and loading samples, original Float16
embedding streaming, width lookup and loading the saved 128-dimensional map.
It generates its own temporary library and removes it afterwards. These are
storage operations; filesystem scanning and audio/model work stay outside this
benchmark and remain covered by the end-to-end tests. `main.swift` also measures
search over both the 128-dimensional projection and the original embedding.

The default `scripts/bench.sh` run is now 100,000 x 2,048. A release run on an
Apple M4 Pro with 48 GiB RAM, Apple Swift 6.4 and the macOS 26.5 SDK measured:

| Operation | Seconds |
| --- | ---: |
| Add 100,000 sample rows | 1.705 |
| Rescan unchanged rows | 0.166 |
| Reopen and load the library | 0.239 |
| Stream original embeddings | 0.254 |
| Load cached analysis | 0.277 |
| Fit PCA | 4.254 |
| Project embeddings | 0.090 |
| Cluster samples | 0.021 |
| Rebuild full 2D layout | 5.097 |
| 100 projected similarity queries | 0.048 |
| 100 full-width similarity queries | 0.674 |
| 100,000 hover lookups | 0.010 |

`/usr/bin/time -l scripts/bench.sh` reported peak RSS of 1,272,233,984 bytes
(about 1.18 GiB). The benchmark holds the complete generated Float32 matrix
(about 781 MiB at this target) in memory so every numerical stage uses the same
data; this is not a measurement of the app's memory use. The app's PCA path
continues to stream 4,096-row batches. Total command time also includes a build
when necessary; use the printed stage times for comparisons.

The earlier release baseline already completed all 100,000 rows. The layout
algorithm is unchanged; varying layout times across runs reflect workload and
parallel execution, not an optimization in this feature. GPU frame rate and
indexing 100,000 real audio files were not measured. The old unmeasured frame-rate
claim was removed from `MapRenderer` rather than extended to the new target.

Final slice validation: the debug build and default release benchmark passed;
`scripts/test.sh` again passed all 390 tests in 85 suites with installed models.
Only the existing Command Line Tools linker search-path warnings were emitted.
No UI behavior or rendering changed, so no new snapshot was needed.
