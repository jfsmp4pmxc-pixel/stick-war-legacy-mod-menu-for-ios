#include <UIKit/UIKit.h>
#include <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>

// ==========================================
// HOOK TYPES
// ==========================================
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);

extern "C" {
    bool mod_InfGoldPlayer   = false;
    bool mod_InfGoldEnemy    = false;
    bool mod_ZeroGoldPlayer  = false;
    bool mod_ZeroGoldEnemy   = false;
}

// ==========================================
// OFFSETS TỪ dump.cs + script.json
// ==========================================
#define RVA_Team_set_Gold        0x38FAAF4
#define RVA_Team_get_Gold        0x38FA974
#define RVA_Team_set_Population  0x3907D08

#define OFF_Team_direction       0x58

// ==========================================
// ORIGINAL FUNCTION POINTERS (IL2CPP instance method luôn có MethodInfo* ở cuối)
// ==========================================
void (*old_set_Gold)(void* this_, int value, void* method);
void (*old_set_Population)(void* this_, int value, void* method);

// ==========================================
// HOOK IMPLEMENTATIONS
// ==========================================
void new_set_Gold(void* this_, int value, void* method) {
    static int logCount = 0;
    if (logCount < 30) {
        int dir = this_ ? *(int*)((uintptr_t)this_ + OFF_Team_direction) : 0;
        NSLog(@"[SWL] set_Gold this=%p dir=%d value=%d", this_, dir, value);
        logCount++;
    }

    if (this_ != NULL) {
        int direction = *(int*)((uintptr_t)this_ + OFF_Team_direction);

        if (direction == 1) {
            if (mod_ZeroGoldPlayer) { old_set_Gold(this_, 9, method); return; }
            if (mod_InfGoldPlayer)  { old_set_Gold(this_, 999999, method); return; }
        }
        else if (direction == -1) {
            if (mod_ZeroGoldEnemy)  { old_set_Gold(this_, 9, method); return; }
            if (mod_InfGoldEnemy)   { old_set_Gold(this_, 999999, method); return; }
        }
    }
    old_set_Gold(this_, value, method);
}

void new_set_Population(void* this_, int value, void* method) {
    old_set_Population(this_, value, method);
}

// ==========================================
// TÌM SLIDE CỦA MAIN EXECUTABLE
// ==========================================
static uintptr_t findImageSlide(const char* keyword) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, keyword)) {
            uintptr_t slide = _dyld_get_image_vmaddr_slide(i);
            NSLog(@"[SWL] Found image #%u: %s  slide=0x%lx", i, name, slide);
            return slide;
        }
    }
    return 0;
}

static uintptr_t getMainSlide() {
    NSString* proc = [[NSProcessInfo processInfo] processName];
    uintptr_t slide = findImageSlide([proc UTF8String]);
    if (slide) return slide;

    slide = findImageSlide("StickWar");
    if (slide) return slide;

    uint32_t n = _dyld_image_count();
    if (n > 0) return _dyld_get_image_vmaddr_slide(n - 1);
    return 0;
}

// ==========================================
// HELPERS UI
// ==========================================
static UIWindow *SWLActiveWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)s;
            if (ws.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
            if (ws.windows.count > 0) return ws.windows.firstObject;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
}

static UIViewController *SWLTopViewController(void) {
    UIWindow *win = SWLActiveWindow();
    if (!win) return nil;
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// ==========================================
// MENU MANAGER
// ==========================================
@interface SWLMenuManager : NSObject
+ (void)showMenu;
@end

@implementation SWLMenuManager

+ (void)showMenu {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showMenu]; });
        return;
    }

    UIViewController *top = SWLTopViewController();
    if (!top) {
        NSLog(@"[SWL] showMenu: no top VC");
        return;
    }
    if (top.presentedViewController) {
        NSLog(@"[SWL] showMenu: another VC presented");
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Stick War Mod Menu"
                         message:@"Chạm 3 ngón hoặc gõ 3 lần để mở lại"
                  preferredStyle:UIAlertControllerStyleAlert];

    NSString *txtInfP = mod_InfGoldPlayer ? @"[ON] Vô hạn Vàng (Ta)" : @"[OFF] Vô hạn Vàng (Ta)";
    [alert addAction:[UIAlertAction actionWithTitle:txtInfP style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_InfGoldPlayer = !mod_InfGoldPlayer;
        if (mod_InfGoldPlayer) mod_ZeroGoldPlayer = false;
        NSLog(@"[SWL] InfGoldPlayer = %d", mod_InfGoldPlayer);
    }]];

    NSString *txtZeroP = mod_ZeroGoldPlayer ? @"[ON] 9 Vàng (Ta)" : @"[OFF] 9 Vàng (Ta)";
    [alert addAction:[UIAlertAction actionWithTitle:txtZeroP style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_ZeroGoldPlayer = !mod_ZeroGoldPlayer;
        if (mod_ZeroGoldPlayer) mod_InfGoldPlayer = false;
        NSLog(@"[SWL] ZeroGoldPlayer = %d", mod_ZeroGoldPlayer);
    }]];

    NSString *txtInfE = mod_InfGoldEnemy ? @"[ON] Vô hạn Vàng (Địch)" : @"[OFF] Vô hạn Vàng (Địch)";
    [alert addAction:[UIAlertAction actionWithTitle:txtInfE style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_InfGoldEnemy = !mod_InfGoldEnemy;
        if (mod_InfGoldEnemy) mod_ZeroGoldEnemy = false;
        NSLog(@"[SWL] InfGoldEnemy = %d", mod_InfGoldEnemy);
    }]];

    NSString *txtZeroE = mod_ZeroGoldEnemy ? @"[ON] 9 Vàng (Địch)" : @"[OFF] 9 Vàng (Địch)";
    [alert addAction:[UIAlertAction actionWithTitle:txtZeroE style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_ZeroGoldEnemy = !mod_ZeroGoldEnemy;
        if (mod_ZeroGoldEnemy) mod_InfGoldEnemy = false;
        NSLog(@"[SWL] ZeroGoldEnemy = %d", mod_ZeroGoldEnemy);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];

    [top presentViewController:alert animated:YES completion:nil];
}

@end

// ==========================================
// GESTURE HANDLER (singleton)
// ==========================================
@interface SWLGestureHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)startWatching;
@end

@implementation SWLGestureHandler

+ (instancetype)shared {
    static SWLGestureHandler *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SWLGestureHandler new]; });
    return s;
}

- (void)startWatching {
    dispatch_async(dispatch_get_main_queue(), ^{
        __block NSTimer *timer = nil;
        timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){
            UIWindow *win = SWLActiveWindow();
            if (win) {
                [t invalidate];
                [self attachGesturesToWindow:win];
                NSLog(@"[SWL] Gestures attached to window: %@", win);
            }
        }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    });
}

- (void)attachGesturesToWindow:(UIWindow *)window {
    for (UIGestureRecognizer *g in window.gestureRecognizers) {
        if (![g isKindOfClass:[UITapGestureRecognizer class]]) continue;
        UITapGestureRecognizer *tap = (UITapGestureRecognizer *)g;
        if (tap.numberOfTouchesRequired == 3 &&
            tap.numberOfTapsRequired == 1) {
            return;
        }
    }

    UITapGestureRecognizer *threeFinger = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleMenuGesture)];
    threeFinger.numberOfTouchesRequired = 3;
    threeFinger.numberOfTapsRequired = 1;
    threeFinger.cancelsTouchesInView = NO;
    threeFinger.delegate = self;
    [window addGestureRecognizer:threeFinger];

    UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleMenuGesture)];
    tripleTap.numberOfTouchesRequired = 1;
    tripleTap.numberOfTapsRequired = 3;
    tripleTap.cancelsTouchesInView = NO;
    tripleTap.delegate = self;
    [window addGestureRecognizer:tripleTap];
}

- (void)handleMenuGesture {
    NSLog(@"[SWL] Menu gesture fired");
    [SWLMenuManager showMenu];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g
    shouldReceiveTouch:(UITouch *)touch {
    return YES;
}

@end

// ==========================================
// CONSTRUCTOR
// ==========================================
__attribute__((constructor)) static void swl_init() {
    NSLog(@"[SWL] dylib loaded");

    // 1. Load substrate/substitute
    void* substrate = dlopen("@executable_path/libsubstrate.dylib", RTLD_LAZY);
    if (!substrate) substrate = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY);
    if (!substrate) substrate = dlopen("/usr/lib/libsubstitute.dylib", RTLD_LAZY);

    if (!substrate) {
        NSLog(@"[SWL] ❌ Không tìm thấy substrate/substitute");
    } else {
        MSHookFunction_t MSHookFunction =
            (MSHookFunction_t)dlsym(substrate, "MSHookFunction");

        if (!MSHookFunction) {
            NSLog(@"[SWL] ❌ Không có MSHookFunction");
        } else {
            uintptr_t slide = getMainSlide();
            NSLog(@"[SWL] main slide = 0x%lx", slide);

            if (slide != 0) {
                void* addr_setGold = (void*)(slide + RVA_Team_set_Gold);
                NSLog(@"[SWL] set_Gold target = %p (RVA 0x%X)",
                      addr_setGold, RVA_Team_set_Gold);
                MSHookFunction(addr_setGold,
                               (void*)&new_set_Gold,
                               (void**)&old_set_Gold);

                void* addr_setPop = (void*)(slide + RVA_Team_set_Population);
                MSHookFunction(addr_setPop,
                               (void*)&new_set_Population,
                               (void**)&old_set_Population);

                NSLog(@"[SWL] ✅ Hooks installed");
            } else {
                NSLog(@"[SWL] ❌ Không tìm được slide");
            }
        }
    }

    // 2. Setup UI gestures khi app active
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note){
        [[SWLGestureHandler shared] startWatching];
    }];
}