# FAQ

Answers to common questions about the shortcut library in Mac Mouse Fix NG.

## A shortcut doesn't work

First check the shortcut in the app's own keyboard settings. Apps can change their default shortcuts between versions, and you may have changed one yourself.

For example, in VS Code: open Settings, choose Keyboard Shortcuts, and search for the command name. If the shortcut listed there is different from the one in Mac Mouse Fix NG, record the one VS Code shows instead.

If the shortcut in the app matches and it still doesn't work, please [report it](#how-to-report-a-problem).

## Why a shortcut is missing on my keyboard

Some shortcuts use a dead key on German and Austrian keyboards: the backtick (`` ` ``), `^` and `~` keys. A dead key waits for the next key before it types anything, so these shortcuts may not work the same way there.

The library offers those shortcuts only on US keyboards until they have been checked on other layouts.

## What the circle and checkmark mean

Next to each library entry in the menu there is a small badge:

- An empty circle means the entry has not been checked in the app yet.
- A seal with a checkmark means the entry was checked in the app.

## How to report a problem

1. In the Buttons tab, right-click the app's tab in the strip on the left.
2. Choose "Report a Problem with Shortcuts…".
3. Your browser opens a new GitHub issue. Fill in which shortcut doesn't work, what happens and what you expected, then submit it.

The issue is pre-filled with the app's name and bundle ID, the Mac Mouse Fix NG version, the macOS version and your keyboard layout. Nothing else from your settings is included. You can edit or delete any of it before you submit. You need a GitHub account to submit the issue.
