# Auto update improvements

When starting the app, it should automatically check for available updates.
I want to be able to click Update and have the release be downloaded from GitHub automatically.
It should be moved to the Applications folder automatically too.

- [x] Check for updates every time the app starts.
- [ ] Download and verify the GitHub release when Update is clicked.
- [ ] Install the verified app in Applications and offer to restart.

## Implementation context

Startup checks bypass the daily schedule in `UpdateSchedule.shouldCheck`, while
checks during the same session remain daily. Skipped releases still stay skipped
until a manual check. `ReleaseUpdateTests` covers both schedule paths. Unbundled
development builds and snapshot launches remain offline.
