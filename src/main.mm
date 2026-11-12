// Điểm vào của dylib: đăng ký log, đợi app active rồi gắn menu.
//
// Mod KHÔNG hook và KHÔNG vá mã. Mọi thứ đều là gọi hàm có sẵn của game
// (qua IL2CPP API), nên chỉ cần dylib được nạp vào tiến trình game.

#import <UIKit/UIKit.h>

#include "il2cpp.hpp"
#import "logger.h"
#import "menu.h"

static const char *const kVersion = "6.0";
static const int64_t kInstallDelaySeconds = 3;  // chờ Unity khởi động xong

static void SWScheduleInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kInstallDelaySeconds * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            SWMenuInstall();
        });
    });
}

__attribute__((constructor)) static void swmod_init(void) {
    @autoreleasepool {
        il2::set_logger(SWLLogC);
        SWLLog(@"StickWarMod %s đã nạp", kVersion);

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            (void)note;
            SWScheduleInstall();
        }];

        // Trường hợp dylib được nạp muộn, khi app đã active sẵn.
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
                SWScheduleInstall();
            }
        });
    }
}
