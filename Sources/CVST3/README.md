# VST3 host bridge

`vendor/pluginterfaces` is the unmodified Steinberg VST3 interface repository
at the commit recorded in `vendor-revision.txt` (MIT license in
`vendor/pluginterfaces/LICENSE.txt`). Only this target's own C++ source is
compiled; the interface headers define the official plugin ABI.

Run `scripts/vendor-vst3.sh` from the repository to restore the pinned files.
Use `scripts/vendor-vst3.sh --latest` to update to upstream HEAD, or pass a
commit or tag to choose a revision. The script fetches the official repository,
replaces only the vendored interfaces, and updates the pin and bundled license
notice together. Local changes inside the vendor folder are replaced; the
bridge source and C ABI are left alone. Review the diff and run the build and
full tests after an update.

The C ABI keeps C++ types out of Swift. Lifecycle and controller access belong
to the main actor; audio processing runs exclusively on a worker task. A plugin
instance belongs to one bounce and is reset for every selected sample. The
module stays loaded until its instances have been terminated.

This initial host supports stereo 32-bit offline effects, generic normalized
parameters, bypass, ordered chains, latency compensation and bounded tails.
It does not host instruments, MIDI, plugin editors, sidechain audio or presets.
Inactive optional buses are negotiated as empty; plugins rejecting that layout
are reported as unsupported. Plugin code executes inside the app process.
