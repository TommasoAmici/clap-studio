# VST high pass filter

Please add a built-in high pass filter that can be used in the VST effects chain.

Check https://www.ableton.com/en/manual/live-audio-effect-reference/

- [x] Build and test the stereo high-pass processor.
- [x] Add the filter to the effects chain for auditions and bounces.

## Implementation context

- Ableton's Auto Filter reference describes a high-pass filter with cutoff,
  resonance and 12/24 dB slopes. This implementation is a simpler stereo
  filter without modulation, analogue circuit models or sidechain controls.
- `Sources/ClapCore/Effects/BuiltInFilter.swift` shares the low-pass and
  high-pass coefficient and stereo-state code. `BuiltInHighPass` selects the
  high-pass numerator, preserving the low-pass filter's existing response.
- The shared filter uses independent stereo
  biquads with logarithmic 20 Hz–20 kHz cutoff (limited below Nyquist),
  resonance, 12/24 dB slopes and dry/wet. The 24 dB setting cascades two
  Butterworth sections at minimum resonance. Filter history continues across
  blocks and updates; the unused second section remains warm. Its reported
  two-second tail lets low-cutoff resonances decay during bounce.
- `BuiltInHighPassTests` checks the filter's response and resonance, slope,
  stereo isolation, block continuity, dry mix, invalid settings, live updates,
  bypass, and a helper bounce that leaves the source unchanged.
- `BuiltInEffect.highPass` registers the processor in the shared chain. Both
  filters display cutoff in Hz/kHz and slope in dB, including accessible values;
  their other parameters retain percentage displays.
- `scripts/snapshot.sh --effects-high-pass` shows the filter card. Light and
  dark appearances for both filters were inspected on macOS 26.7.2 using an
  empty scratch library; macOS 14 and 27 runtimes were unavailable.
