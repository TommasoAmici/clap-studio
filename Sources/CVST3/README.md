# VST3 host bridge

`vendor/pluginterfaces` is the unmodified Steinberg VST3 interface repository
at commit `4f547e8e102b47de4a8b8aaf343c73b700786372` (MIT license in
`vendor/pluginterfaces/LICENSE.txt`). Only this target's own C++ source is
compiled; the interface headers define the official plugin ABI.

The C ABI keeps C++ types out of Swift. Lifecycle and controller access belong
to the main actor; audio processing runs exclusively on a worker task. A plugin
instance belongs to one bounce and is reset for every selected sample. The
module stays loaded until its instances have been terminated.

This initial host supports stereo 32-bit offline effects, generic normalized
parameters, bypass, ordered chains, latency compensation and bounded tails.
It does not host instruments, MIDI, plugin editors, sidechain audio or presets.
Inactive optional buses are negotiated as empty; plugins rejecting that layout
are reported as unsupported. Plugin code executes inside the app process.
