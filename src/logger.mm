#import "logger.h"

static const NSUInteger kMaxLines = 400;

static NSMutableArray<NSString *> *sLines;
static NSObject *sLock;
static NSDateFormatter *sFormatter;

static void SWLEnsureInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sLines = [NSMutableArray array];
        sLock = [NSObject new];
        sFormatter = [NSDateFormatter new];
        sFormatter.dateFormat = @"HH:mm:ss";
    });
}

static void SWLAppend(NSString *message) {
    SWLEnsureInit();
    NSLog(@"[StickWarMod] %@", message);
    @synchronized(sLock) {
        NSString *stamp = [sFormatter stringFromDate:[NSDate date]];
        [sLines addObject:[NSString stringWithFormat:@"[%@] %@", stamp, message]];
        if (sLines.count > kMaxLines) {
            [sLines removeObjectsInRange:NSMakeRange(0, sLines.count - kMaxLines)];
        }
    }
}

void SWLLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    SWLAppend(message);
}

void SWLLogC(const char *line) {
    if (!line) return;
    NSString *message = [NSString stringWithUTF8String:line];
    if (message) SWLAppend(message);
}

NSString *SWLLogDump(void) {
    SWLEnsureInit();
    @synchronized(sLock) {
        if (sLines.count == 0) return @"(chưa có log)";
        return [sLines componentsJoinedByString:@"\n"];
    }
}
