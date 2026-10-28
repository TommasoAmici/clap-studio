# VST low pass filter

Please add a built-in low pass filter that can be used in the VST effects chain.

Check https://www.ableton.com/en/manual/live-audio-effect-reference/

- [x] Build and test the stereo low-pass processor.
- [ ] Add the filter to the effects chain for auditions and bounces.

## Implementation context

- `Sources/ClapCore/Effects/BuiltInLowPass.swift` implements independent stereo
  biquads with logarithmic 20 Hz–20 kHz cutoff (limited below Nyquist),
  resonance, 12/24 dB slopes and dry/wet. The 24 dB setting cascades two
  Butterworth sections at minimum resonance. Filter history continues across
  blocks and parameter updates; the second section remains warm when unused.
- The linked Ableton Auto Filter reference describes low-pass cutoff,
  resonance and 12/24 dB slopes; this is a simpler filter without modulation,
  circuit emulation or sidechain. A future high-pass can reuse the state and
  coefficient approach with a high-pass numerator.
- `BuiltInLowPassTests` checks frequency response, slope, stereo separation,
  block continuity, dry mix and invalid settings. Its two-second reported tail
  allows low-cutoff resonances to decay during bounce.
- The processor is not yet reachable from the app. Chain registration awaits
  the shared built-in effects infrastructure.
