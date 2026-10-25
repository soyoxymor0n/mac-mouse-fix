#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
static int lines = 0;
static NSString *attr(AXUIElementRef e, CFStringRef name) {
    CFTypeRef v = NULL;
    if (AXUIElementCopyAttributeValue(e, name, &v) != kAXErrorSuccess || !v) return nil;
    NSString *s = CFGetTypeID(v) == CFStringGetTypeID() ? [(__bridge NSString *)v copy] : nil;
    CFRelease(v);
    return s;
}
static void dump(AXUIElementRef e, int depth) {
    if (depth > 12 || lines > 400) return;
    NSString *role = attr(e, kAXRoleAttribute), *title = attr(e, kAXTitleAttribute), *desc = attr(e, kAXDescriptionAttribute), *help = attr(e, kAXHelpAttribute);
    CFTypeRef vr = NULL; NSString *valueStr = nil;
    if (AXUIElementCopyAttributeValue(e, kAXValueAttribute, &vr) == kAXErrorSuccess && vr) { if (CFGetTypeID(vr) == CFStringGetTypeID()) valueStr = [(__bridge NSString *)vr copy]; else if (CFGetTypeID(vr) == CFNumberGetTypeID()) valueStr = [NSString stringWithFormat:@"%@", (__bridge NSNumber *)vr]; CFRelease(vr); }
    if (role) {
        printf("%*s%s", depth * 2, "", role.UTF8String);
        if (title.length) printf(" title=\"%s\"", title.UTF8String);
        if (desc.length) printf(" desc=\"%s\"", desc.UTF8String);
        if (help.length) printf(" help=\"%s\"", help.UTF8String);
        if (valueStr.length) printf(" value=\"%s\"", valueStr.UTF8String);
        CFTypeRef pv = NULL, sv = NULL; CGPoint pt = {0,0}; CGSize sz = {0,0};
        if (AXUIElementCopyAttributeValue(e, kAXPositionAttribute, &pv) == kAXErrorSuccess && pv) { AXValueGetValue(pv, kAXValueCGPointType, &pt); CFRelease(pv); }
        if (AXUIElementCopyAttributeValue(e, kAXSizeAttribute, &sv) == kAXErrorSuccess && sv) { AXValueGetValue(sv, kAXValueCGSizeType, &sz); CFRelease(sv); }
        printf(" @%.0f,%.0f %.0fx%.0f", pt.x, pt.y, sz.width, sz.height);
        printf("\n"); lines++;
    }
    CFTypeRef kids = NULL;
    if (AXUIElementCopyAttributeValue(e, kAXChildrenAttribute, &kids) == kAXErrorSuccess && kids) {
        for (id c in (__bridge NSArray *)kids) dump((__bridge AXUIElementRef)c, depth + 1);
        CFRelease(kids);
    }
}
int main(int argc, const char *argv[]) {
    NSString *bid = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"com.soyoxymor0n.mac-mouse-fix";
    for (NSRunningApplication *app in [NSWorkspace sharedWorkspace].runningApplications) {
        if (![app.bundleIdentifier isEqualToString:bid]) continue;
        AXUIElementRef ax = AXUIElementCreateApplication(app.processIdentifier);
        printf("== %s pid=%d\n", bid.UTF8String, app.processIdentifier);
        CFTypeRef wins = NULL;
        AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute, &wins);
        for (id w in (__bridge NSArray *)wins) dump((__bridge AXUIElementRef)w, 0);
        if (wins) CFRelease(wins);
        CFTypeRef sheets = NULL; (void)sheets;
        return 0;
    }
    printf("app %s not running\n", bid.UTF8String);
    return 1;
}
