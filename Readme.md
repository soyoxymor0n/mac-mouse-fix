# Mac Mouse Fix NG

**Mac Mouse Fix NG** is a fork of [Mac Mouse Fix](https://macmousefix.com). It is the start of a next generation of the app, with more settings and easier customization.

> This is an unofficial fork. The author of Mac Mouse Fix does not make, endorse or support it. For the official app, use [macmousefix.com](https://macmousefix.com) and the [upstream repository](https://github.com/noah-nuebling/mac-mouse-fix).

## Credits

Mac Mouse Fix was created by [Noah Nuebling](https://github.com/noah-nuebling). The upstream project is at [noah-nuebling/mac-mouse-fix](https://github.com/noah-nuebling/mac-mouse-fix). This fork builds on his code, including the scrolling engine, button handling and most of the user interface. The third-party libraries it uses are credited in [Acknowledgements.md](Acknowledgements.md).

This fork is maintained by [soyoxymor0n](https://github.com/soyoxymor0n).

## Purpose

Mac Mouse Fix makes a cheap mouse much more useful. This fork explores the next step:

- **Per-app button settings.** A Global tab holds the default button actions. Each app can have its own tab, so a button can do one thing in Teams and another in Chrome. Only the buttons you assign in an app's tab change there, and global settings never override them.
- **Easier customization.** Plans for built-in presets, a shortcut library and opt-in config sharing are in [docs/features](docs/features/README.md).
- **Keeping up with upstream.** Planned: a way to see upstream changes, judge their impact on the fork and apply them in one step (see issue #1).

The fork is experimental. Expect rough edges.

## Branches

| Branch | What it is |
|---|---|
| `beta` (default) | Current work, including the per-app tabs |
| `personal` | Earlier build branch, before the per-app tabs UI |
| `per-app-remaps` | Per-app remap logic only, without the fork-specific changes |
| `fork-setup` | Fork-specific changes: bundle identifiers and update checks off |
| `master` | Mirror of upstream |

## Differences from upstream

- Bundle identifiers start with `com.soyoxymor0n.`, so the fork can be installed next to the official app. Do not run both at the same time.
- Automatic update checks (Sparkle) are off, so the fork does not receive updates.
- License and trial state are stored under a different keychain label. The fork does not share them with the official app.
- Configuration is stored in `~/Library/Application Support/com.soyoxymor0n.mac-mouse-fix/`.

## Building

1. Install Xcode on macOS.
2. Open `Mouse Fix.xcodeproj` and select the `App` scheme.
3. Under Signing & Capabilities, set your own signing team. A free Personal Team is enough for your own Mac.
4. Quit the official Mac Mouse Fix and its helper before you run the fork.
5. On first run, grant Accessibility access to the fork in System Settings, under Privacy & Security.

## License

This project is derived from Mac Mouse Fix and is licensed under the [MMF License](License). Read it before you publish anything built from this source. It requires that derived work is clearly marked as derived. It also restricts publishing compiled apps, including keeping the licensing and trial code in place.

## Contributing and feedback

- Bugs and ideas for this fork belong in this repository's [issues](https://github.com/soyoxymor0n/mac-mouse-fix-ng/issues). Please do not open them upstream.
- Feature plans are in [docs/features](docs/features/README.md).
