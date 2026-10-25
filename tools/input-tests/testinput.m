// Sends one button press to the test-hooked helper: testinput <button 1-5> <down 1|0>
#import <Foundation/Foundation.h>
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: testinput <button> <down 1|0>\n"); return 2; }
        NSDictionary *info = @{ @"button": @(atoi(argv[1])), @"down": @(atoi(argv[2]) != 0) };
        [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"com.soyoxymor0n.mmf.testInput" object:nil userInfo:info deliverImmediately:YES];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    }
    return 0;
}
