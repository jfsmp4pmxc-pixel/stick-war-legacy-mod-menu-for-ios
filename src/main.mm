#include <UIKit/UIKit.h>
#include <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>

// ==========================================
// HOOK TYPES
// ==========================================
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);

extern "C" {
    bool mod_InfGoldPlayer     = false;
    bool mod_InfGoldEnemy      = false;
    bool mod_ZeroGoldPlayer    = false;
    bool mod_ZeroGoldEnemy     = false;

    int  mod_SelectedUnitId    = 2;
    int  mod_SpawnAmount       = 1;
    int  mod_SpawnTargetTeam   = 0;
    bool mod_TriggerSpawnSignal = false;
}

void (*old_set_Gold)(void* instance, int value);

// ==========================================
// HOOK LOGIC
// ==========================================
void new_set_Gold(void* instance, int value) {
    if (instance != NULL) {
        int direction = *(int*)((uintptr_t)instance + 0x58);
        if (direction == 1) {
            if (mod_ZeroGoldPlayer) { old_set_Gold(instance, 9); return; }
            if (mod_InfGoldPlayer)  { old_set_Gold(instance, 999999); return; }
        } else if (direction == -1) {
            if (mod_ZeroGoldEnemy)  { old_set_Gold(instance, 9); return; }
            if (mod_InfGoldEnemy)   { old_set_Gold(instance, 999999); return; }
        }
    }
    old_set_Gold(instance, value);
}

void* SpawnMonitorThread(void* arg) {
    while (true) {
        if (mod_TriggerSpawnSignal) {
            for (int i = 0; i < mod_SpawnAmount; i++) {
                // TODO: gọi CreateUnit với class type tương ứng
            }
            mod_TriggerSpawnSignal = false;
        }
        usleep(100000);
    }
    return NULL;
}

// ==========================================
// HELPERS
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
        NSLog(@"[SWL] showMenu: no top VC yet");
        return;
    }
    if (top.presentedViewController) {
        NSLog(@"[SWL] showMenu: another VC is presented");
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Stick War Mod Menu"
                         message:@"Chạm 3 ngón hoặc gõ 3 lần để mở lại"
                  preferredStyle:UIAlertControllerStyleAlert];

    // ---- Vàng phe ta ----
    NSString *txtInfP = mod_InfGoldPlayer ? @"[ON] Vô hạn Vàng (Ta)" : @"[OFF] Vô hạn Vàng (Ta)";
    [alert addAction:[UIAlertAction actionWithTitle:txtInfP style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_InfGoldPlayer = !mod_InfGoldPlayer;
        if (mod_InfGoldPlayer) mod_ZeroGoldPlayer = false;
    }]];

    NSString *txtZeroP = mod_ZeroGoldPlayer ? @"[ON] 9 Vàng (Ta)" : @"[OFF] 9 Vàng (Ta)";
    [alert addAction:[UIAlertAction actionWithTitle:txtZeroP style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_ZeroGoldPlayer = !mod_ZeroGoldPlayer;
        if (mod_ZeroGoldPlayer) mod_InfGoldPlayer = false;
    }]];

    // ---- Vàng phe địch ----
    NSString *txtInfE = mod_InfGoldEnemy ? @"[ON] Vô hạn Vàng (Địch)" : @"[OFF] Vô hạn Vàng (Địch)";
    [alert addAction:[UIAlertAction actionWithTitle:txtInfE style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_InfGoldEnemy = !mod_InfGoldEnemy;
        if (mod_InfGoldEnemy) mod_ZeroGoldEnemy = false;
    }]];

    NSString *txtZeroE = mod_ZeroGoldEnemy ? @"[ON] 9 Vàng (Địch)" : @"[OFF] 9 Vàng (Địch)";
    [alert addAction:[UIAlertAction actionWithTitle:txtZeroE style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_ZeroGoldEnemy = !mod_ZeroGoldEnemy;
        if (mod_ZeroGoldEnemy) mod_InfGoldEnemy = false;
    }]];

    // ---- Spawn nhanh ----
    [alert addAction:[UIAlertAction actionWithTitle:@"Spawn 5 GIANT (Ta)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_SelectedUnitId = 5; mod_SpawnAmount = 5;
        mod_SpawnTargetTeam = 0; mod_TriggerSpawnSignal = true;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Spawn 10 SWORDWRATH (Địch)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_SelectedUnitId = 2; mod_SpawnAmount = 10;
        mod_SpawnTargetTeam = 1; mod_TriggerSpawnSignal = true;
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];

    [top presentViewController:alert animated:YES completion:nil];
}

@end

// ==========================================
// GESTURE HANDLER (singleton để giữ delegate sống)
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
    // Tránh add trùng: chỉ check theo class UITapGestureRecognizer
    for (UIGestureRecognizer *g in window.gestureRecognizers) {
        if (![g isKindOfClass:[UITapGestureRecognizer class]]) continue;
        UITapGestureRecognizer *tap = (UITapGestureRecognizer *)g;
        if (tap.numberOfTouchesRequired == 3 &&
            tap.numberOfTapsRequired == 1) {
            return; // đã có rồi
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

    // --- Hook ---
    void *substrate = dlopen("@executable_path/libsubstrate.dylib", RTLD_LAZY);
    if (!substrate) substrate = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY);
    if (!substrate) substrate = dlopen("/usr/lib/libsubstitute.dylib", RTLD_LAZY);

    if (substrate) {
        MSHookFunction_t MSHookFunction =
            (MSHookFunction_t)dlsym(substrate, "MSHookFunction");
        if (MSHookFunction) {
            uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
            MSHookFunction((void*)(slide + 0x39747060),
                           (void*)&new_set_Gold,
                           (void**)&old_set_Gold);
            NSLog(@"[SWL] Hook installed at %p", (void*)(slide + 0x39747060));
        } else {
            NSLog(@"[SWL] MSHookFunction not found");
        }
    } else {
        NSLog(@"[SWL] substrate/substitute not found");
    }

    // --- Spawn thread ---
    pthread_t th;
    pthread_create(&th, NULL, SpawnMonitorThread, NULL);

    // --- UI: chờ app active rồi mới gắn gesture ---
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note){
        [[SWLGestureHandler shared] startWatching];
    }];
}