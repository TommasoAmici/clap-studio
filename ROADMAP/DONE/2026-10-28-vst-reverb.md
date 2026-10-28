# VST reverb

Please add a built-in reverb that can be used in the VST effects chain.

Check https://www.ableton.com/en/manual/live-audio-effect-reference/

- [x] Build and test the stereo reverb processor.
- [x] Add reverb to the effects chain for auditions and bounces.

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
  stereo width, predelay, room controls, dry mix and block continuity.
  `BuiltInReverbChainTests` checks live updates, dynamic tails, bypass and helper
  bounces, including fresh state and original file protection.
- `LiveHost` extends an active audition when a control increases its tail.
  An earlier final-buffer callback is ignored when that length has changed.
- `BuiltInEffect.reverb` registers this processor with the shared effects chain;
  see [the effects guide](../../README.md) for the available controls.
