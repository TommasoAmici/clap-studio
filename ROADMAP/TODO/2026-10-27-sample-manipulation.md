# Sample manipulation

Currently, there are very limited options to manipulate samples. I want to add VST support so we can load plugins and add distortion, reverb, etc.

The plugins should be read from the default locations like Ableton does. Let's start with VST3 only for now.

After having applied a VST to a sample, the user should be able to bounce the sample with the effects applied and save them.
Show them a native file save dialog so they can choose a folder and file name.

I'd also like to be able to apply the same effect chain to multiple samples and save them all at once. Similar to how photos can be processed in Adobe Lightroom applying the same corrections and effects at scale.

## Checklist

- [x] Discover installed VST3 bundles in the standard user and system folders.
- [ ] Load effects, edit their parameters and render an ordered chain.
- [ ] Audition and bounce one sample with a native save dialog.
- [ ] Bounce selected samples through the same chain into a chosen folder.

## Implementation context

- `VST3Discovery` searches user and system `Library/Audio/Plug-Ins/VST3`
  folders, including vendor subfolders, without executing plugin code or
  descending into bundle contents. Missing folders are harmless.
- `VST3DiscoveryTests` covers nested vendor folders, duplicate roots and
  absent locations. Discovery is only the first slice; loading and bouncing
  remain to be implemented.
