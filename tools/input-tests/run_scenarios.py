import plistlib, subprocess, time, os, sys
HOME = os.path.expanduser("~")
FCFG = os.path.join(HOME, "Library/Application Support/com.soyoxymor0n.mac-mouse-fix/config.plist")
T = os.environ["T"]; I = os.environ["I"]
HELPER = os.path.join(T, "dd/Build/Products/Debug/Mac Mouse Fix.app/Contents/Library/LoginItems/Mac Mouse Fix Helper.app")
A_ID, B_ID = "com.soyoxymor0n.mmf-probe", "com.soyoxymor0n.mmf-probe2"
A_LOG, B_LOG = os.path.join(I, "probeA.log"), os.path.join(I, "probeB.log")
def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout
def row(button, keycode, app=None):
    r = {'trigger': {'button': button, 'duration': 'click', 'level': 1}, 'modifiers': {}, 'effect': {'type': 'keyboardShortcut', 'keycode': keycode, 'flags': 1179648}}
    if app: r['app'] = app
    return r
def write_rows(rows):
    os.makedirs(os.path.dirname(FCFG), exist_ok=True)
    cfg = plistlib.load(open(FCFG, 'rb')) if os.path.exists(FCFG) else {}
    cfg['Remaps'] = rows
    cfg.setdefault('State', {})['remapsAreInitialized'] = True
    plistlib.dump(cfg, open(FCFG, 'wb'))
def restart_helper():
    sh("pkill", "-f", T + "/dd/Build/Products/Debug/Mac Mouse Fix.app")
    time.sleep(2)
    sh("open", HELPER); time.sleep(4)
def read(path):
    return open(path).read() if os.path.exists(path) else ""
def run(name, rows, front, want_log, want_text, forbid_text=None):
    write_rows(rows)
    restart_helper()
    for p in (A_LOG, B_LOG):
        if os.path.exists(p): os.remove(p)
    sh("open", "-n", os.path.join(I, "Probe.app"), "--args", A_LOG); time.sleep(2)
    sh("open", "-n", os.path.join(I, "Probe2.app"), "--args", B_LOG); time.sleep(2)
    sh("open", "-a", os.path.join(I, "Probe.app" if front == A_ID else "Probe2.app")); time.sleep(2)
    sh(os.path.join(T, "testinput"), "4", "1"); time.sleep(0.15)
    sh(os.path.join(T, "testinput"), "4", "0"); time.sleep(1)
    got = read(want_log)
    ok = want_text in got and (forbid_text is None or forbid_text not in got)
    print(("PASS" if ok else "FAIL"), name, "| front:", front.split('.')[-1], "| log:", (got.strip().replace("\n", " / ")[:160] or "(empty)"))
    sh("pkill", "-x", "Probe")
    sh("pkill", "-f", "Probe2.app/Contents/MacOS/Probe")
    return ok
results = []
results.append(run("S1 global only", [row(4, 46)], B_ID, B_LOG, "code=46 flags=0x120000"))
results.append(run("S2 app row beats global (front app has the row)", [row(4, 46), row(4, 31, A_ID)], A_ID, A_LOG, "code=31 flags=0x120000"))
results.append(run("S3 other app still gets global", [row(4, 46), row(4, 31, A_ID)], B_ID, B_LOG, "code=46 flags=0x120000", "code=31"))
results.append(run("S4 app-only row does not affect other apps", [row(4, 31, A_ID)], B_ID, B_LOG, "", "KEY_DOWN"))
results.append(run("S5 app with no row for button 4 falls through to global", [row(4, 46), row(5, 31, A_ID)], A_ID, A_LOG, "code=46 flags=0x120000", "code=31"))
print("RESULT:", sum(results), "of", len(results), "passed")
