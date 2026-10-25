# Input and UI test tools (test branch only)

Used to check the per-app remaps and the per-app tabs without a mouse. None of this is part of the app.

- `testinput.m`: sends one button press to a helper built with `MMF_TEST_INPUT=1`. Usage: `testinput <button> <down 1|0>`.
- `probe.m`: a small window that logs the mouse and key events it receives. Build it into a `.app` bundle with a bundle ID such as `com.soyoxymor0n.mmf-probe`.
- `inject.c`: posts real mouse and key events at the HID level (`button`, `rightclick`, `key`, `move`). Left and right clicks reach the probe, but the helper only remaps real device events.
- `ax_dump.m`: dumps an app's accessibility tree, with frames and tooltips.
- `ax_press_title.m`: presses the button with the given title through Accessibility.
- `run_scenarios.py`: the five global and app precedence scenarios. Set `T` to the test build's products folder and `I` to a folder with the probe apps.

Needs: Accessibility for the terminal app that runs the tools. The fork's helper must be on the list too, and the official app must be stopped during runs.
