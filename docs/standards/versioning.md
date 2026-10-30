# Versioning

How Mac Mouse Fix NG numbers its versions and builds. Agreed with the owner on 2026-10-30.

## Version

`CFBundleShortVersionString`, e.g. `4.2.0`. Set as `MARKETING_VERSION` in `Mouse Fix.xcodeproj` (four places: app and Helper, Debug and Release). Bumped by hand, only for a build that is handed out:

| Change since the last handed-out build | Bump | Example |
|---|---|---|
| Fixes only | patch | 4.2.0 → 4.2.1 |
| New features or visible changes | minor | 4.2.0 → 4.3.0 |
| Big changes, e.g. a new settings format | major | 4.2.0 → 5.0.0 |

## Build number

`CFBundleVersion` = 30000 + the number of commits in `HEAD`. Set on every build by `tools/build/set-build-version.sh` (build phase "Set Build Number and Commit" in both targets). It only changes the built `Info.plist`, never the one in the repo.

- It grows with every commit, so a newer build has a higher number.
- It stays above upstream's build numbers (25324 when the fork started).
- The app and the Helper get the same number. The Helper uses it to check that it belongs to the running app.

## Commit

The built `Info.plist` also gets `MFGitCommit`: the short hash of `HEAD`, with `-dirty` when tracked files had uncommitted changes.

## Where to see it

The About tab shows `version (build · commit · Debug)`, e.g. `4.2.0 (38720 · 1a2b3c4 · Debug)`. "Debug" only appears in debug builds. With that line, any installed build can be traced to its exact commit.
