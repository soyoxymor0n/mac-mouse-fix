# Keyboard layouts and key codes

Status: measured on the owner's Mac, 2026-10-25. Data: `data/layouts-us-de-at.tsv` (key codes 0 to 127 for the US, German and Austrian layouts). Script: `data/layoutdump.swift`, which reads the installed layout data with `UCKeyTranslate`. It does not switch the input source or change any setting.

## What the data shows

A key code names a physical key position. The character depends on the layout. A shortcut stores a key code and modifier flags, so a letter or symbol can land on another key in another layout.

How to type each layout-dependent character (key code plus modifier):

| Character | US | German | Austrian |
|---|---|---|---|
| Z | key code 6 | key code 16 | key code 16 |
| Y | key code 16 | key code 6 | key code 6 |
| [ | key code 33 | Option + key code 23 | Option + key code 23 |
| ] | key code 30 | Option + key code 22 | Option + key code 22 |
| { | Shift + key code 33 | Option + key code 28 | Option + key code 28 |
| } | Shift + key code 30 | Option + key code 25 | Option + key code 25 |
| ü | not on this key | key code 33 | key code 33 |
| ö, ä | not on this key | key codes 41 and 39 | key codes 41 and 39 |
| ß | not on this key | key code 27 | key code 27 |

Key codes that give the same character on all three layouts:
- All letters except Y and Z (A, S, D, F, G, H, J, K, L, Q, W, E, R, T, U, I, O, P, X, C, V, B, N, M).
- Digits 1 to 0. Shift and Option change the symbols on each layout, so check any shortcut with Shift+digit.
- Arrow keys (123 to 126), Return (36), Tab (48), Space (49), Delete (51), Escape (53).

## Correction to the library research

`shortcut-library.md`, section 3, said that on a German layout `[` and `]` are Option+8 and Option+9. The measured data shows Option+5 and Option+6 for `[` and `]`. Option+8 and Option+9 give `{` and `}`. The library research document is corrected to match.

## Consequences for the library

- Cmd+Z (undo) stored as key code 6 fires Cmd+Y on the German and Austrian layouts. Store Z as key code 16 on those layouts.
- Cmd+[ on the German or Austrian layout needs key code 23 with Option. Key code 33 without Option gives Cmd+ü. The v1 library uses the arrow keys for Chrome, which are layout-independent.
- Letters other than Y and Z, the arrow keys, and modifier-only shortcuts need no layout variant.

## Decision in effect (per layout)

The owner chose "per layout": each entry that uses a layout-dependent key stores one variant per layout (US, German, Austrian), each with its own key code and flags. The runtime does not change. The helper still receives a plain key code and flags. The app chooses the variant that matches the active input source when a row is created. That selection is a later implementation step.

Not verified here: whether Chrome and Teams accept a key code plus Option as a match for the symbol on the German layout. Test it on the owner's Mac before shipping any symbol-based entry.
