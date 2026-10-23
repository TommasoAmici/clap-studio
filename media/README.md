# Clap Studio media kit

Ten PNGs show the Library, Map, Drum Machine, Melody, and drums with melody
together in light and dark
appearance. Each full window is rendered at 3200 × 2000 pixels, including its
toolbar and inspector.

Run `scripts/media-kit.sh` from the repository to regenerate them after a UI
change. Pass another output directory to make a preview without replacing these
images. It builds the current debug app and a release seeder, then captures the
views in about two minutes. The first build takes longer.

The script makes a fresh temporary library with 384 original synthesised sounds,
then removes it after capturing. No purchased samples, personal library data or
neural models are needed. Sound names, tags, collections and map coordinates are
demonstration data. The sound map uses repeatable, irregular clouds with a few
sounds between families, rather than geometric rings.
The app's ordinary controls, waveforms and measured sound properties are real.

The capture forces only the demo app's appearance and uses a separate preference
domain. The installed app's library and macOS appearance are left alone.
