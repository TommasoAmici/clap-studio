# VST erosion

Please add a built-in erosion that can be used in the VST effects chain.

Check https://www.ableton.com/en/manual/live-audio-effect-reference/

- [x] Build and test the erosion processor.
- [x] Add erosion to the effects chain and verify audition and bounce.

## Implementation context

- `Sources/ClapCore/Effects/BuiltinErosion.swift` modulates a bounded, one-millisecond fractional delay with a sine wave and filtered, seeded noise. The Ableton Erosion reference describes this type of modulation; this implementation is an independent approximation, not a model of its precise sound.
- Frequency sets the sine and noise-filter center; Amount sets delay depth; Noise Blend mixes carriers; Filter Width sets the noise bandwidth; Stereo Width changes the right carrier. All values are normalized and have stable parameter IDs. Zero Amount is an exact pass-through; each instance keeps independent delay, oscillator and noise state across blocks.
- `BuiltInEffect` registers the processor with the shared preview and bounce chain. `Tests/ClapCoreTests/BuiltinErosionTests.swift` checks live changes, bypass, silent input, stereo behavior, block continuity, multiple sample rates and an independent helper bounce that leaves the source untouched.
- The native effects card scrolls vertically when its controls exceed the available height. Light and dark snapshots show the first four erosion controls; scrolling to Stereo Width and keyboard focus still need an interactive check. User-facing controls are described in [README.md](../../README.md).
