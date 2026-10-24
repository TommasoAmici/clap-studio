# Clap Studio media kit

Twelve PNGs show the Library, Map, Drum Machine, Melody, and drums with melody
together, plus field recordings on the world map, in light and dark
appearance. Each full window is rendered at 3200 × 2000 pixels, including its
toolbar and inspector.

Run `scripts/media-kit.sh` from the repository to regenerate them after a UI
change. Pass another output directory to make a preview without replacing these
images. It builds the current debug app and a release seeder, then captures the
views in about two minutes. The first build takes longer.

The script makes a fresh temporary library with 420 original synthesised sounds,
then removes it after capturing. No purchased samples, personal library data or
neural models are needed. Thirty-six ambience sounds have demonstration GPS coordinates at twelve places
around the world; they were synthesised, not recorded in those places. The
Places image uses the real Apple basemap and may need a network connection for
tiles. Its world view is rendered in two matching halves during capture, with
the library’s real pin counts, so every demonstration place fits in the image.
Each ambience clip has one eight-second segment; no neural sound labels are
claimed.

Sound names, tags, collections and map coordinates are
demonstration data. The sound map uses repeatable, irregular clouds with a few
sounds between families, rather than geometric rings.
The app's ordinary controls, waveforms and measured sound properties are real.

The capture forces only the demo app's appearance and uses a separate preference
domain. The installed app's library and macOS appearance are left alone.
