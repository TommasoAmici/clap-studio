# Website images

When deploying the website, images are cached and users see the old screenshots. Let's update all images URL to include a query parameter with the current version (e.g. `?v=0.24`) for cache busting.

- [x] Version every exported image URL and preserve it when changing music views.

## Implementation context

The export reads `CFBundleShortVersionString` from `scripts/bundle.sh`,
avoiding a second version to maintain. HTML screenshot sources, the SVG icon
and local or absolute social preview URLs get the full release version.
`website/site.js` preserves the initial screenshot's query for every gallery
choice. Its own exported URL is versioned so an old cached script cannot drop
the query. Raw source previews continue to work without an export.

The website workflow also watches `scripts/bundle.sh`, so version bumps
redeploy the image URLs. See [website documentation](../../website/README.md)
for the export behavior. Replacing images within the same app version still
uses the same URLs; a release version change refreshes them.

Validation: `scripts/test-website.sh` first failed for an unversioned screenshot,
then passed for local and public URLs, copied files and a simulated version
bump. A JavaScript DOM fixture exercised every music view twice, checking both
appearances with and without an exported query. `scripts/build.sh` passed with
only the existing Command Line Tools linker-path warnings; all 413 tests in
89 suites passed. Compiler-cache and Git LFS metadata access needed sandbox
escalation in the isolated worktree.
