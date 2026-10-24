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

The website needs no Node packages, backend, API key, external font, tracking
script or cookie.

## Link previews

`og-image.png` is a 1200 × 630 share card using the app icon and sound map.
Open Graph and Twitter metadata use it for large link previews. The export
includes the image alongside the page.

Set `WEBSITE_URL` to the public website address when exporting so preview
images have an absolute URL, including any subfolder:

```sh
WEBSITE_URL=https://your-domain/ scripts/website.sh
```

Local previews work without that setting. To regenerate the card after
changing the app icon or screenshots, download the media and run:

```sh
swift scripts/render-og-image.swift
```

## VPS deployment

The [Website workflow](../.github/workflows/website.yml) follows the
[Salmple deployment](https://github.com/TommasoAmici/salmple): build the static
folder, then copy it over SSH with `rsync`. Changes to the website, PNG
screenshots, export scripts or workflow run the export checks on pull requests
and deploy after a push to `main`. **Run workflow** on `main` can deploy again
without another commit. Running it on another branch only checks the build.
This job downloads PNG screenshots through Git LFS; the app release job keeps
skipping media.

Add these repository secrets under **Settings → Secrets and variables →
Actions**, using the same values as the Salmple repository:

- `SSH_HOST`: the VPS hostname or address.
- `SSH_USER`: the account used to upload the website.
- `SSH_PORT`: the SSH port.
- `SSH_KNOWN_HOSTS`: the trusted host-key entry, including the port when needed.
- `SSH_KEY`: the account's private SSH key.

Under **Settings → Secrets and variables → Actions → Variables**, set
`WEBSITE_URL` to the site's public address so deployed link previews point to
the correct image.

On the VPS, create `/var/www/html/clap-studio/`, give the SSH account permission
to write there, and configure your web server to serve that directory for the
site's domain. The workflow sets directories to `755` and files to `644`, as
Salmple does. `rsync --delete` removes old files inside this website directory
that are absent from the new build.

`scripts/test-website.sh` checks that exported image paths work within the
output folder, every musical view is present in both appearances, and missing
images or Git LFS pointers stop the build before writing output.

The page honors reduced-motion preferences, keeps its links and screenshot
controls usable by keyboard, and uses native `picture` media queries so a
change in the browser's color preference also changes the screenshots.
