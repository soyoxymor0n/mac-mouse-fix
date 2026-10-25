#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
/// Presses the first AXButton whose title equals argv[2] in the app with bundle id argv[1].
static NSString *str(AXUIElementRef e, CFStringRef a) {
    CFTypeRef v = NULL; NSString *s = nil;
    if (AXUIElementCopyAttributeValue(e, a, &v) == kAXErrorSuccess && v) { if (CFGetTypeID(v) == CFStringGetTypeID()) s = [(__bridge NSString *)v copy]; CFRelease(v); }
    return s;
}
static NSArray *kids(AXUIElementRef e) { CFTypeRef k = NULL; NSArray *r = @[]; if (AXUIElementCopyAttributeValue(e, kAXChildrenAttribute, &k) == kAXErrorSuccess && k) { r = [(__bridge NSArray *)k copy]; CFRelease(k); } return r; }
static BOOL pressTitle(AXUIElementRef e, NSString *title, int depth) {
    if (depth > 10) return NO;
    if ([str(e, kAXRoleAttribute) isEqualToString:@"AXButton"] && [str(e, kAXTitleAttribute) isEqualToString:title]) {
        return AXUIElementPerformAction(e, kAXPressAction) == kAXErrorSuccess;
    }
    for (id c in kids(e)) if (pressTitle((__bridge AXUIElementRef)c, title, depth + 1)) return YES;
    return NO;
}
int main(int argc, const char *argv[]) {
    if (argc < 3) return 2;
    NSString *bid = [NSString stringWithUTF8String:argv[1]], *title = [NSString stringWithUTF8String:argv[2]];
    for (NSRunningApplication *app in [NSWorkspace sharedWorkspace].runningApplications) {
        if (![app.bundleIdentifier isEqualToString:bid]) continue;
        AXUIElementRef ax = AXUIElementCreateApplication(app.processIdentifier);
        for (id w in kids(ax)) if (pressTitle((__bridge AXUIElementRef)w, title, 0)) { printf("pressed '%s'\n", title.UTF8String); return 0; }
        printf("button '%s' not found\n", title.UTF8String); return 1;
    }
    printf("app not running\n"); return 1;
}
