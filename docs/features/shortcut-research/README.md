# Shortcut research

Status: in progress, 2026-10-25. Goal: for the top 50 macOS apps, every documented keyboard shortcut, with a flag for the ones that suit a mouse button. Input to the shortcut library (`../shortcut-library.md`).

## Decisions in effect

- Depth: record every documented shortcut per app, and flag the mouse-suitable ones. The library ships only the flagged rows.
- Layout: one variant per layout (US, German, Austrian). See `layouts.md`, which holds the measured key tables.
- Top 50 ranking: mixed public data. Blocked, see "App Store charts" below.
- Profile files: official Elgato profiles only, read locally. Blocked, the free files need an Elgato login.

## Data

- `data/shortcuts.json`: all extracted apps, one entry per app with its rows. Each row has the action, symbols, US key, modifiers, the mouse-suitable and destructive flags, a layout flag, and the source URL with the date read.
- `data/appstore-charts.json`: the visible Mac App Store charts, each entry checked against Mac-only search.
- `data/layouts-us-de-at.tsv` and `data/layoutdump.swift`: the measured key tables and the script that produced them.

## Extraction status

| App | Status | Shortcuts | Bundle ID | Notes |
|---|---|---|---|---|
| Google Chrome | complete | 84 | verified | read through a summarising fetch, labels paraphrased |
| Safari | complete | 57 | unverified | Apple guide cpsh003 |
| Brave | complete | 64 | verified | read through a summarising fetch |
| Firefox | no official source | 0 | verified | Mozilla page returned an error; retry |
| Microsoft Word | complete | 171 | verified | summarising fetch, not checked line by line |
| Microsoft Excel | complete | 181 | verified | "previous sheet" row conflicts in the source, recorded as Option+Left Arrow; verify |
| Microsoft PowerPoint | complete | 132 | verified | Crop (Shift+Cmd+M) comes from a page that also covers Windows; verify |
| Microsoft Outlook | complete | 111 | verified | iOS sections excluded |
| Microsoft Teams | complete | 120 | unverified | read through a summarising fetch |
| Slack | complete | 97 | verified | read through a summarising fetch |
| Zoom | complete | 75 | verified | scope labels inferred; spot-check |
| Discord | partial | 42 | verified | the FAQ rarely states the platform |
| WhatsApp | no official source | 0 | verified | no official shortcut list |
| Telegram | no official source | 0 | verified | no official shortcut list |
| Finder | partial | 84 | unverified | rows come from the Finder section of Apple's page 102650 |
| Mail | complete | 34 | unverified | the en-au page conflicts on Shift+Cmd+E; the US value was used |
| Messages | complete | 42 | unverified | |
| Calendar | complete | 41 | unverified | |
| Notes | complete | 68 | unverified | |
| Photos | partial | 67 | unverified | condensed fetch, rows may be missing |
| Music | complete | 61 | unverified | |
| Preview | complete | 35 | unverified | |
| Terminal | complete | 95 | unverified | |
| Visual Studio Code | complete | 140 | verified | default keybindings, rebuilt from a saved PDF by hand |
| iTerm2 | partial | 4 | verified | full bindings are in Preferences > Keys, not inspected |
| Obsidian | complete | 40 | verified | no default command hotkeys on the page |
| Notion | complete | 58 | verified | typed triggers excluded |
| Raycast | complete | 83 | verified | |
| 1Password | complete | 77 | verified | |
| Spotify | complete | 32 | verified | "not limited to" the list; Mac key examples are images only |
| VLC media player | partial | 14 | verified | the full list is images only |
| Dropbox | no official source | 0 | verified | the official page covers the web app only |
| Google Drive | no official source | 0 | verified | the official pages cover Drive on the web only |
| Adobe Acrobat Reader | partial | 0 | verified | helpx.adobe.com returned 403 to every request; retry |

Caveats for all rows: the research agents read most pages through a summarising fetch. The labels are paraphrased and the rows are not checked line by line against the live pages. Before release, spot-check each app. The mouse-suitable and destructive flags were set by keyword rules, not reviewed by hand.

## App Store charts

- Read from the App Store window on the owner's Mac (accessibility, read-only). Only the top sections of each chart could be read: Top Free ranks 1-34 and Top Paid ranks 1-33. The middle of the charts (about ranks 35-145) and the tail beyond the loaded sections could not be read: the window does not expose them to accessibility, and scroll-wheel events did not move the lists.
- Mac-only check against iTunes search (`entity=macSoftware`) for the 67 entries: 56 exact or prefix matches, 11 matched only by a German store name, 2 had no match, and 1 unknown. Full results: `data/appstore-charts.json`.
- Not reliable: the 11 German-name matches. One is wrong: "Microsoft 365" matched Microsoft Word. Xcode (no match in the search) is Mac software, bundle `com.apple.dt.Xcode`, confirmed by lookup by App Store ID.
- No iOS-tagged entries ("Designed for iPhone" or "Designed for iPad") were found among these 67.
- Web search: no current Mac App Store chart is public. The pages found are editorial picks, or charts from 2011.
- Apple's public RSS chart feeds for Mac apps returned 404 (`rss.applemarketingtools.com` and `rss.marketingtools.apple.com`). The general chart feed returns data, but the research agent found it to be the iOS chart, so it was not used.

## Reference sources, checked

- Logi Options+: names the actions for 4 apps (Photoshop, Word, PowerPoint, Excel), but gives no key combinations. Not a usable key source.
- Elgato Stream Deck: 41 apps, 33 readable shortcut rows, mostly from Elgato's explorer guides and one StreamYard help page. Most Marketplace profile listings have descriptions only. The free official profile files need a login (HTTP 401). Nothing was downloaded.
- Other mouse-button presets: 12 rows, all from blogs and forums. Not usable as a source for shortcuts.

## Open

1. The top-50 list. Needs the full App Store charts (a manual "See All" click, or another source), or the owner's own list of apps. Until then the extraction covers the 34 apps above.
2. Firefox, Adobe Acrobat: retry the official pages.
3. Spot-check the Office, Chrome, Teams, Slack and Zoom rows against the live pages.
4. Whether to add the Elgato profile files: needs the owner to log in and download them.
