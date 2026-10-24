# Clap Studio website

A static landing page with real app screenshots, a music-view selector, and a
section for ALM Squid Salmple banks, the Pool and sending samples to the stick.
Screenshots and page colors follow the browser's light or dark preference.

To preview the source, serve the repository root:

```sh
python3 -m http.server 8080
```

Open `http://localhost:8080/website/`. The source uses the images in `media/`;
it does not keep another copy of them. All copy and screenshots work without
JavaScript; JavaScript adds the Drums, Melody and Together buttons.

To make a folder ready for any static web host:

```sh
scripts/website.sh                    # writes build/website, ignored by Git
scripts/website.sh /tmp/clap-website  # or choose another output folder
python3 -m http.server 8080 --directory build/website
```

The build uses Python's standard library, copies only the screenshots the page
can show, and changes their paths for the output folder. It refuses missing
images and Git LFS pointers: download the media first when building a website
from a checkout that skipped it. App CI does not need to build the website.

Upload the contents of that output folder when you choose a host. The website
needs no Node packages, backend, API key, external font, tracking script or
cookie. No hosting or deployment is configured here.

`scripts/test-website.sh` checks that exported image paths work within the
output folder, every musical view is present in both appearances, and missing
images or Git LFS pointers stop the build before writing output.

The page honors reduced-motion preferences, keeps its links and screenshot
controls usable by keyboard, and uses native `picture` media queries so a
change in the browser's color preference also changes the screenshots.
