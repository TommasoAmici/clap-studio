# VST reverb

Please add a built-in reverb that can be used in the VST effects chain.

Check https://www.ableton.com/en/manual/live-audio-effect-reference/

- [x] Build and test the stereo reverb processor.
- [ ] Add reverb to the effects chain for auditions and bounces.

## Implementation context

- `Sources/ClapCore/Effects/BuiltInReverb.swift` implements independent stereo
  comb delays and diffusion stages. Predelay is 0–100 ms, size changes the
  reflection delays, and decay is 0.25–8 seconds to a nominal −60 dB; damping,
  stereo width and dry/wet shape the output. The reported tail includes
  predelay and diffusion allowance, capped at ten seconds. Each instance owns
  its history, which continues across blocks and changes to controls.
- The linked Ableton Reverb reference motivates the controls and describes a
  substantially broader effect. This is a simpler room approximation, not a
  reproduction; it does not include modulation, freeze or input filters.
  Changing size adjusts delay taps immediately and can produce a transition
  artifact; smoothing may be worthwhile if live size automation is added.
- `BuiltInReverbTests` covers decay at different sample rates, finite settings,
  stereo width, predelay, room controls, dry mix and block continuity. It does
  not yet cover integration with the live helper or rendered bounces.
- The processor is not yet available in the app. Chain registration awaits the
  shared built-in effects infrastructure.
