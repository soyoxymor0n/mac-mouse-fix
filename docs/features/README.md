# Phase 2 features

Plans for three features after the per-app button tabs. All three are proposals. Nothing is built, and no code has changed.

## Features

- [App presets](app-presets.md): built-in button presets for common apps, such as Teams (button 4 mic, button 5 camera) and Chrome (back and forward), added to an app tab with one click. Recommended first, as bundled data.
- [Shortcut library](shortcut-library.md): a bundled, cited list of keyboard shortcuts for about 6 to 12 apps, so users do not have to look them up. Recommended second, after presets.
- [Community sharing (opt-in)](community-sharing.md): opt-in download and upload of app-tab setups. Recommended as a curated GitHub repository first, with no in-app upload. A Cloudflare Worker with D1 only if demand appears, and with downloads and sharing consented separately.

## Open decisions for the owner

Presets
- Which presets ship in v1: Teams and Chrome only (recommended), or more? ([app-presets.md, section 9](app-presets.md#9-open-decisions-for-the-owner))
- Which keyboard layout do you use? Test Chrome's Command+[ on your German layout before choosing how key codes are stored. ([decision 5](app-presets.md#9-open-decisions-for-the-owner))

Shortcut library
- Which six apps come first: Chrome, Firefox, Safari, Teams, Slack and VS Code (recommended)? ([shortcut-library.md, section 9](shortcut-library.md#9-open-decisions-for-the-owner))
- Destructive shortcuts (Quit, Log Out, Force Quit, Empty Trash): excluded (recommended)? ([decision 5](shortcut-library.md#9-open-decisions-for-the-owner))

Community sharing
- Start with a GitHub repository only, with no in-app upload (recommended)? ([community-sharing.md, decision 1](community-sharing.md#9-open-decisions-for-the-owner))
- Separate consent for downloading and for sharing (recommended). Your original "in return" framing ties downloads to sharing, which conflicts with GDPR Article 7(4). ([decision 2](community-sharing.md#9-open-decisions-for-the-owner))
- Who is the data controller, you or your employer, and does your employer need to approve a public service? Resolve this before any server work. ([decision 8](community-sharing.md#9-open-decisions-for-the-owner))
- Log and record retention periods, and the license for shared setups (CC0 recommended). ([decisions 5 and 7](community-sharing.md#9-open-decisions-for-the-owner))

## Cross-cutting notes

- The license (`License` in the repo root) restricts publishing compiled apps and requires the monetization code to stay in place. Question for you: whether any of these features is a substantial addition that changes that analysis. This is not legal advice.
- Each plan lists its sources at the end. Some facts are unverified and are marked as such in the plans.
