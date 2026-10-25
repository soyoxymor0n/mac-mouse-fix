// Probe app: a window that logs the mouse and key events it receives. Used to check injected input.
#import <Cocoa/Cocoa.h>

static NSString *logPath;

static void logLine(NSString *line) {
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!h) { [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil]; h = [NSFileHandle fileHandleForWritingAtPath:logPath]; }
    [h seekToEndOfFile];
    [h writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

@interface ProbeDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@end

@implementation ProbeDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 480, 320)
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"MMF Probe";
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    // Centre of the content area in global (CoreGraphics) coordinates: origin top-left of the primary screen.
    NSRect content = [self.window contentRectForFrameRect:self.window.frame];
    NSRect primary = NSScreen.screens.firstObject.frame;
    CGFloat cx = NSMidX(content);
    CGFloat cy = primary.size.height - NSMidY(content);
    logLine([NSString stringWithFormat:@"READY bundle=%@ centre=%.0f,%.0f", NSBundle.mainBundle.bundleIdentifier, cx, cy]);

    [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskKeyDown | NSEventMaskOtherMouseDown | NSEventMaskOtherMouseUp | NSEventMaskLeftMouseDown)
                                          handler:^NSEvent *(NSEvent *e) {
        switch (e.type) {
            case NSEventTypeOtherMouseDown: logLine([NSString stringWithFormat:@"OTHER_DOWN button=%ld", (long)e.buttonNumber]); break;
            case NSEventTypeOtherMouseUp:   logLine([NSString stringWithFormat:@"OTHER_UP button=%ld", (long)e.buttonNumber]); break;
            case NSEventTypeLeftMouseDown:  logLine(@"LEFT_DOWN"); break;
            case NSEventTypeKeyDown:        logLine([NSString stringWithFormat:@"KEY_DOWN code=%hu flags=0x%lx", e.keyCode, (unsigned long)e.modifierFlags]); break;
            default: break;
        }
        return e;
    }];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        logPath = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"/tmp/mmf-probe.log";
        [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];
        NSApplication *app = [NSApplication sharedApplication];
        ProbeDelegate *delegate = [ProbeDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
