# VST low pass filter

Please add a built-in low pass filter that can be used in the VST effects chain.

Check https://www.ableton.com/en/manual/live-audio-effect-reference/

- [x] Build and test the stereo low-pass processor.
- [x] Add the filter to the effects chain for auditions and bounces.

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
- `BuiltInEffect.lowPass` registers the processor in the shared chain for both
  live preview and helper-process bounces. `BuiltInLowPassTests` checks response,
  slope, stereo separation, block continuity, dry mix, invalid settings, live
  updates, bypass, and that bouncing filters audio without modifying its source.
  Its two-second reported tail allows low-cutoff resonances to decay during bounce.
- `scripts/snapshot.sh --effects-low-pass` opens the filter card in a scratch
  effects drawer. The controls use the existing normalized percentage sliders;
  the light appearance was inspected on macOS 26.7.2. macOS 14 runtime was
  not available for a separate check.
