# VST erosion

Please add a built-in erosion that can be used in the VST effects chain.

Check https://www.ableton.com/en/manual/live-audio-effect-reference/

- [x] Build and test the erosion processor.
- [ ] Add erosion to the effects chain and verify audition and bounce.

## Implementation context

- `Sources/ClapCore/Effects/BuiltinErosion.swift` modulates a bounded, one-millisecond fractional delay with a sine wave and filtered, seeded noise. The Ableton Erosion reference describes this type of modulation; this implementation is an independent approximation, not a model of its precise sound.
- Frequency sets the sine and noise-filter center; Amount sets delay depth; Noise Blend mixes carriers; Filter Width sets the noise bandwidth; Stereo Width changes the right carrier. All values are normalized and have stable parameter IDs. Zero Amount is an exact pass-through; each instance keeps independent delay, oscillator and noise state across blocks.
- `Tests/ClapCoreTests/BuiltinErosionTests.swift` checks live changes, silent input, stereo behavior, controls, block continuity and multiple sample rates. The processor must still be registered with the shared built-in chain before it can be used or documented in the README.
