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

The host supports stereo 32-bit offline effects, native NSView editors with
window sizing and focus, generic parameters as a fallback, bypass, ordered
chains, latency compensation and bounded tails. It does not host instruments,
MIDI or sidechain audio. The manufacturer’s editor can select its own presets;
component/controller state is captured where supported, up to 16 MiB each.
Saved state is restored before exposed normalized parameters on each render.
A required IComponentHandler and factory3 host context support editor hosts.
Inactive optional buses are negotiated as empty; plugins rejecting that layout
are reported as unsupported. Plugin code executes in the bundled `ClapVSTHost` helper. The app performs only file discovery, request supervision, preprocessing, verification and atomic destination replacement. Probe requests have a 30-second deadline; audio-block progress refreshes the render helper’s five-minute inactivity deadline. Cancellation kills and reaps the helper. Helpers receive scratch input/output paths, never the user’s chosen bounce destination.

Editor helpers send a main-run-loop heartbeat every half second. A hung editor
is killed after 30 seconds without that heartbeat; responsive editors stay
open until the user closes their window. Closing captures settings; cancelling
kills the session and discards its changes. `VST3Process` supervises each
Process on one DispatchQueue worker because Foundation launch and wait must
use the same thread’s run loop.
