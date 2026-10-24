# Media kit Salmple feature
Please add screenshots of the ALM Salmple views. That's a feature I want to highlight on the website.

- [x] Add repeatable banks, Pool and Send screenshots in light and dark appearance to the media kit.

## Implementation context

- `Sources/ClapMediaSeed/MediaSquid.swift` exports the existing synthetic library
  into `Squid Demo/ALM022` under the scratch library: four Studio banks, a Live
  set and nested Pool folders. The seeder checks bank occupancy, file counts and
  embedded category tags before marking the fixture ready.
- `Sources/ClapStudio/DebugSnapshotSquid.swift` loads that fixture only in a
  debug snapshot with media mode, USB selection, a scratch data path and the
  seeder's marker. Connected-drive watching is already disabled in media mode.
  The fixture uses a transient SQLite root after normal startup has purged
  earlier transient roots. Cached measurements are imported off the main
  actor; the fixture stays out of the ordinary library and map and is purged
  when the capture app exits.
- Measuring all 54 files during every debug snapshot took 21.55 seconds, plus
  the snapshot's six-second startup and three-second settling waits, exceeding
  `scripts/snapshot.sh`'s 29-second limit. The release seeder now measures the
  exported files once into `Squid Demo/.clap-media.sqlite`. That separate cache
  is outside `ALM022`, survives the capture app's transient-root purge, and is
  removed with the script's scratch folder.
- The debug window renderer composes an attached sheet over the full window
  only in media mode, preserving the kit's standard dimensions. The long
  sidebar is scrolled to show the Squid sets and Pool.
  `NSGraphicsContext(bitmapImageRep:)` already scales window points according
  to the bitmap's size; adding another scale doubled the sheet and clipped it.
  Composition uses the sheet's real position relative to the main window with
  that existing transform.
- `UsbDrive` exposes its existing initializer so debug tooling can supply
  demonstration drive metadata. `UsbDriveIdentityTests`, using an ordinary
  `import ClapCore`, first failed with the expected initializer access error.
- The real USB hardware is unnecessary: audio conversion, folders and category
  tags use the usual Squid code. Displayed FAT32 metadata is demonstration data,
  as explained in [the media kit](../../media/README.md).
- Verified `scripts/build.sh` with no new warnings and the full
  `scripts/test.sh`: 399 tests in 87 suites passed, including the installed
  model checks. The complete media-kit script produced 18 PNGs and two GIFs;
  after correcting sheet scaling, all six Squid images were captured again
  through `scripts/snapshot.sh` and visually checked at 3200 × 2000 pixels.
  Existing committed media assets were kept; only the six Squid PNGs were added.
