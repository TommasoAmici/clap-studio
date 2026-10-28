# VST high pass filter

Please add a built-in high pass filter that can be used in the VST effects chain.

Check https://www.ableton.com/en/manual/live-audio-effect-reference/

- [x] Build and test the stereo high-pass processor.
- [ ] Add the filter to the effects chain for auditions and bounces.

## Implementation context

- Ableton's Auto Filter reference describes a high-pass filter with cutoff,
  resonance and 12/24 dB slopes. This implementation is a simpler stereo
  filter without modulation, analogue circuit models or sidechain controls.
- The low-pass and high-pass filters have matching controls and use the same
  biquad approach. Once their branches are combined, consider sharing their
  coefficient and stereo-state code without changing the filters' behaviour.
- `Sources/ClapCore/Effects/BuiltInHighPass.swift` uses independent stereo
  biquads with logarithmic 20 Hz–20 kHz cutoff (limited below Nyquist),
  resonance, 12/24 dB slopes and dry/wet. The 24 dB setting cascades two
  Butterworth sections at minimum resonance. Filter history continues across
  blocks and updates; the unused second section remains warm. Its reported
  two-second tail lets low-cutoff resonances decay during bounce.
- `BuiltInHighPassTests` checks the filter's response and resonance, slope,
  stereo isolation, block continuity, dry mix and invalid settings. Chain
  registration awaits the shared built-in effects infrastructure.
