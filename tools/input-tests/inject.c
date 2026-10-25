// Injects mouse button and key events at the HID level, as a physical device would.
// Usage:
//   inject move <x> <y>
//   inject button <x> <y> <buttonNumber>     (1 = left, 2 = right, 3 = middle, 4 = back, 5 = forward)
//   inject key <keycode> <flags>             (flags in CGEventFlags form, e.g. 1048576 = Command)
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void postMouse(CGEventType type, CGPoint p, int button) {
    CGEventRef e = CGEventCreateMouseEvent(NULL, type, p, (CGMouseButton)(button > 2 ? button - 1 : 0));
    if (button > 2) CGEventSetIntegerValueField(e, kCGMouseEventButtonNumber, button - 1);
    /// A real click carries its click count. Without it, click-level triggers (level 1) don't match.
    CGEventSetIntegerValueField(e, kCGMouseEventClickState, 1);
    /// The helper reads pressure to tell presses from releases. Real devices report 1.0 on press.
    int isDown = (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventOtherMouseDown);
    CGEventSetDoubleValueField(e, kCGMouseEventPressure, isDown ? 1.0 : 0.0);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
}

int main(int argc, const char *argv[]) {
    if (argc < 3) { fprintf(stderr, "usage: see source\n"); return 2; }
    if (strcmp(argv[1], "move") == 0 && argc == 4) {
        CGWarpMouseCursorPosition(CGPointMake(atof(argv[2]), atof(argv[3])));
        return 0;
    }
    if (strcmp(argv[1], "button") == 0 && argc == 5) {
        CGPoint p = CGPointMake(atof(argv[2]), atof(argv[3]));
        int button = atoi(argv[4]);
        CGWarpMouseCursorPosition(p);
        usleep(100000);
        postMouse(button == 1 ? kCGEventLeftMouseDown : (button == 2 ? kCGEventRightMouseDown : kCGEventOtherMouseDown), p, button);
        usleep(60000);
        postMouse(button == 1 ? kCGEventLeftMouseUp : (button == 2 ? kCGEventRightMouseUp : kCGEventOtherMouseUp), p, button);
        return 0;
    }
    if (strcmp(argv[1], "rightclick") == 0 && argc == 4) {
        CGPoint p = CGPointMake(atof(argv[2]), atof(argv[3]));
        CGWarpMouseCursorPosition(p);
        usleep(100000);
        CGEventRef d = CGEventCreateMouseEvent(NULL, kCGEventRightMouseDown, p, kCGMouseButtonRight);
        CGEventSetIntegerValueField(d, kCGMouseEventClickState, 1);
        CGEventPost(kCGHIDEventTap, d); CFRelease(d);
        usleep(60000);
        CGEventRef u = CGEventCreateMouseEvent(NULL, kCGEventRightMouseUp, p, kCGMouseButtonRight);
        CGEventSetIntegerValueField(u, kCGMouseEventClickState, 1);
        CGEventPost(kCGHIDEventTap, u); CFRelease(u);
        return 0;
    }
    if (strcmp(argv[1], "key") == 0 && argc == 4) {
        CGKeyCode code = (CGKeyCode)atoi(argv[2]);
        CGEventFlags flags = (CGEventFlags)strtoull(argv[3], NULL, 10);
        CGEventRef down = CGEventCreateKeyboardEvent(NULL, code, true);
        CGEventRef up = CGEventCreateKeyboardEvent(NULL, code, false);
        CGEventSetFlags(down, flags); CGEventSetFlags(up, flags);
        CGEventPost(kCGHIDEventTap, down); usleep(40000); CGEventPost(kCGHIDEventTap, up);
        CFRelease(down); CFRelease(up);
        return 0;
    }
    fprintf(stderr, "bad arguments\n");
    return 2;
}
