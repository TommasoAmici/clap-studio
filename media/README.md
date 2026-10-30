# Clap Studio media kit

These images are stored with Git LFS. Run `git lfs pull --include="media/**"`
after initializing Git LFS to download them, or `scripts/setup.sh --media`
to initialize the repository and download the images together.

Eighteen PNGs show the Library, Map, Drum Machine, Melody, and drums with melody
together, plus field recordings on the world map and Squid Salmple banks, Pool
and Send sheet, in light and dark appearance. Each full window is rendered at
3200 × 2000 pixels, including its
toolbar and inspector. Two silent, looping GIFs show the drums and melody
playing together, with their real moving playheads, at 1600 × 1000 pixels. Each
GIF records one two-bar phrase at 124 BPM (about four seconds).

Run `scripts/media-kit.sh` from the repository to regenerate them after a UI
change. Pass another output directory to make a preview without replacing these
images. It builds the current debug app and a release seeder, then captures the
views in a few minutes. The first build takes longer.

The PNGs are native captures: macOS draws the window and the script records
exactly that, so they match the app on the Mac that ran it, including the
toolbar and glass of its macOS version. This needs screen capture access for
your terminal (System Settings > Privacy & Security) and a Retina display; the
script stops if an image is not 3200 pixels wide. Leave the window alone while
it runs. The GIFs are drawn from the window's views instead, because the app
steps each frame itself.

The script makes a fresh temporary library with 420 original synthesised sounds,
then removes it after capturing. No purchased samples, personal library data or
neural models are needed. Thirty-six ambience sounds have demonstration GPS coordinates at twelve places
around the world; they were synthesised, not recorded in those places. The
Places image uses the real Apple basemap and may need a network connection for
tiles. Its world view is rendered in two matching halves during capture, with
the library’s real pin counts, so every demonstration place fits in the image.
Each ambience clip has one eight-second segment; no neural sound labels are
claimed.

The Squid images use a demonstration stick inside the temporary folder. It
holds 54 copies of the synthetic sounds, exported through the app's usual Squid
conversion with category tags and level matching. The banks show all eight
channels and free slots; the Pool shows folders within folders. The Send image
shows the real export sheet over the full window. No physical USB stick is
needed or accessed. The displayed drive name and FAT32 format are demonstration
data; audio properties and folder contents are read from the generated files.

Use these images to highlight ALM Squid Salmple support on the website:

| View | Light | Dark |
| --- | --- | --- |
| Banks and channels | [PNG](squid-banks-light.png) | [PNG](squid-banks-dark.png) |
| Pool folders and samples | [PNG](squid-pool-light.png) | [PNG](squid-pool-dark.png) |
| Send samples to the Pool | [PNG](squid-send-light.png) | [PNG](squid-send-dark.png) |

Sound names, tags, collections and map coordinates are
demonstration data. The sound map uses repeatable, irregular clouds with a few
sounds between families, rather than geometric rings.
The app's ordinary controls, waveforms and measured sound properties are real.

The capture forces only the demo app's appearance and uses a separate preference
domain. The installed app's library and macOS appearance are left alone.

With a seeded scratch library, `scripts/snapshot.sh out.png --media --usb Studio
--select` captures the banks; `--usb pool` captures the Pool. Add
`--usb pool/Drums/Kicks --send Drums/Kicks` to show the Send sheet. Set
`CLAP_DATA_DIR` to that scratch library, set `CLAP_NO_INDEX=1`, and use a
separate demo executable as `scripts/media-kit.sh` does to keep preferences apart.

For a single playback capture from a scratch library, use
`CLAP_DATA_DIR=/tmp/clap-demo scripts/snapshot.sh out.gif --drums --melody --animate --scale 1`. Animation
uses the real playback engine and records 48 frames through the same window
renderer as the PNGs. It needs no screen capture permission or video encoder, and is not a native capture;
GIFs carry no audio.
