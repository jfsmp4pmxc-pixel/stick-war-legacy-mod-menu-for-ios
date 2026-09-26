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
// OFFSETS
// ==========================================
#define RVA_Team_set_Gold        0x38FAAF4
#define RVA_Team_get_Gold        0x38FA974
#define RVA_Team_set_Population  0x3907D08

#define OFF_Team_direction       0x58

// ==========================================
// GLOBAL DEBUG STATE
// ==========================================
static int  g_setGoldCalls = 0;
static int  g_getGoldCalls = 0;
static int  g_lastDir = 0;
static int  g_lastValue = 0;
static int  g_lastGetValue = 0;
static char g_lastName[64] = "";

static NSMutableArray<NSString*> *g_logBuffer = nil;
static NSLock *g_logLock = nil;

// ==========================================
// LOG SYSTEM
// ==========================================
static void SWLLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSLog(@"[SWL] %@", msg);

    if (!g_logBuffer) {
        g_logBuffer = [NSMutableArray array];
        g_logLock = [NSLock new];
    }
    [g_logLock lock];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"HH:mm:ss";
    NSString *ts = [df stringFromDate:[NSDate date]];
    [g_logBuffer addObject:[NSString stringWithFormat:@"[%@] %@", ts, msg]];
    if (g_logBuffer.count > 200) [g_logBuffer removeObjectAtIndex:0];
    [g_logLock unlock];
}

// ==========================================
// ORIGINAL FUNCTIONS
// ==========================================
void (*old_set_Gold)(void* this_, int value, void* method);
void (*old_set_Population)(void* this_, int value, void* method);
int  (*old_get_Gold)(void* this_, void* method);

// ==========================================
// HOOK IMPLEMENTATIONS
// ==========================================
void new_set_Gold(void* this_, int value, void* method) {
    g_setGoldCalls++;
    int dir = this_ ? *(int*)((uintptr_t)this_ + OFF_Team_direction) : -999;
    g_lastDir = dir;
    g_lastValue = value;
    snprintf(g_lastName, sizeof(g_lastName), "set_Gold dir=%d val=%d", dir, value);

    if (g_setGoldCalls <= 20) {
        SWLLog(@"set_Gold #%d this=%p dir=%d value=%d",
               g_setGoldCalls, this_, dir, value);
    }

    if (this_ != NULL) {
        if (dir == 1) {
            if (mod_ZeroGoldPlayer) { old_set_Gold(this_, 9, method); return; }
            if (mod_InfGoldPlayer)  { old_set_Gold(this_, 999999, method); return; }
        } else if (dir == -1) {
            if (mod_ZeroGoldEnemy)  { old_set_Gold(this_, 9, method); return; }
            if (mod_InfGoldEnemy)   { old_set_Gold(this_, 999999, method); return; }
        }
    }
    old_set_Gold(this_, value, method);
}

int new_get_Gold(void* this_, void* method) {
    g_getGoldCalls++;
    int ret = old_get_Gold(this_, method);
    int dir = this_ ? *(int*)((uintptr_t)this_ + OFF_Team_direction) : -999;
    g_lastGetValue = ret;

    if (g_getGoldCalls <= 20) {
        SWLLog(@"get_Gold #%d this=%p dir=%d ret=%d",
               g_getGoldCalls, this_, dir, ret);
    }

    if (this_ != NULL) {
        if (dir == 1 && mod_InfGoldPlayer) return 999999;
        if (dir == -1 && mod_InfGoldEnemy) return 999999;
    }
    return ret;
}

void new_set_Population(void* this_, int value, void* method) {
    old_set_Population(this_, value, method);
}

// ==========================================
// DYLD SLIDE
// ==========================================
static uintptr_t findImageSlide(const char* keyword) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, keyword)) {
            uintptr_t slide = _dyld_get_image_vmaddr_slide(i);
            SWLLog(@"Image #%u: %s  slide=0x%lx", i, name, slide);
            return slide;
        }
    }
    return 0;
}

static uintptr_t getMainSlide() {
    NSString* proc = [[NSProcessInfo processInfo] processName];
    SWLLog(@"Process name: %@", proc);
    uintptr_t slide = findImageSlide([proc UTF8String]);
    if (slide) return slide;
    slide = findImageSlide("StickWar");
    if (slide) return slide;
    uint32_t n = _dyld_image_count();
    if (n > 0) return _dyld_get_image_vmaddr_slide(n - 1);
    return 0;
}

// ==========================================
// UI HELPERS
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
// LOG VIEWER
// ==========================================
@interface SWLLogViewer : UIViewController
@end

@implementation SWLLogViewer

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.9];

    CGRect b = self.view.bounds;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 50, b.size.width - 20, 30)];
    title.text = @"📋 SWL Debug Log";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];

    // Thống kê
    UILabel *stats = [[UILabel alloc] initWithFrame:CGRectMake(10, 85, b.size.width - 20, 80)];
    stats.numberOfLines = 0;
    stats.textColor = [UIColor yellowColor];
    stats.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    stats.text = [NSString stringWithFormat:
        @"set_Gold calls: %d\n"
        @"get_Gold calls: %d\n"
        @"last set: dir=%d val=%d\n"
        @"last get value: %d",
        g_setGoldCalls, g_getGoldCalls,
        g_lastDir, g_lastValue, g_lastGetValue];
    [self.view addSubview:stats];

    // Log list
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(10, 175, b.size.width - 20, b.size.height - 250)];
    tv.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    tv.editable = NO;

    NSMutableString *all = [NSMutableString string];
    [g_logLock lock];
    for (NSString *line in g_logBuffer) {
        [all appendFormat:@"%@\n", line];
    }
    [g_logLock unlock];
    if (all.length == 0) [all appendString:@"(chưa có log)"];
    tv.text = all;

    // Auto-scroll to bottom
    NSRange r = NSMakeRange(tv.text.length - 1, 1);
    [tv scrollRangeToVisible:r];

    [self.view addSubview:tv];

    // Close button
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(20, b.size.height - 60, b.size.width - 40, 44);
    [close setTitle:@"Đóng" forState:UIControlStateNormal];
    close.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1];
    close.layer.cornerRadius = 8;
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

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
        SWLLog(@"showMenu: no top VC");
        return;
    }
    if (top.presentedViewController) {
        SWLLog(@"showMenu: another VC presented");
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Stick War Mod Menu"
                         message:[NSString stringWithFormat:@"Hooks: %d set / %d get",
                                  g_setGoldCalls, g_getGoldCalls]
                  preferredStyle:UIAlertControllerStyleAlert];

    // ===== XEM LOG =====
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 Xem Log Debug" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        SWLLogViewer *v = [SWLLogViewer new];
        v.modalPresentationStyle = UIModalPresentationOverFullScreen;
        [top presentViewController:v animated:YES completion:nil];
    }]];

    // ===== VÀNG PHE TA =====
    NSString *txtInfP = mod_InfGoldPlayer ? @"[ON] Vô hạn Vàng (Ta)" : @"[OFF] Vô hạn Vàng (Ta)";
    [alert addAction:[UIAlertAction actionWithTitle:txtInfP style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_InfGoldPlayer = !mod_InfGoldPlayer;
        if (mod_InfGoldPlayer) mod_ZeroGoldPlayer = false;
        SWLLog(@"InfGoldPlayer = %d", mod_InfGoldPlayer);
    }]];

    NSString *txtZeroP = mod_ZeroGoldPlayer ? @"[ON] 9 Vàng (Ta)" : @"[OFF] 9 Vàng (Ta)";
    [alert addAction:[UIAlertAction actionWithTitle:txtZeroP style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_ZeroGoldPlayer = !mod_ZeroGoldPlayer;
        if (mod_ZeroGoldPlayer) mod_InfGoldPlayer = false;
        SWLLog(@"ZeroGoldPlayer = %d", mod_ZeroGoldPlayer);
    }]];

    // ===== VÀNG PHE ĐỊCH =====
    NSString *txtInfE = mod_InfGoldEnemy ? @"[ON] Vô hạn Vàng (Địch)" : @"[OFF] Vô hạn Vàng (Địch)";
    [alert addAction:[UIAlertAction actionWithTitle:txtInfE style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_InfGoldEnemy = !mod_InfGoldEnemy;
        if (mod_InfGoldEnemy) mod_ZeroGoldEnemy = false;
        SWLLog(@"InfGoldEnemy = %d", mod_InfGoldEnemy);
    }]];

    NSString *txtZeroE = mod_ZeroGoldEnemy ? @"[ON] 9 Vàng (Địch)" : @"[OFF] 9 Vàng (Địch)";
    [alert addAction:[UIAlertAction actionWithTitle:txtZeroE style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        mod_ZeroGoldEnemy = !mod_ZeroGoldEnemy;
        if (mod_ZeroGoldEnemy) mod_InfGoldEnemy = false;
        SWLLog(@"ZeroGoldEnemy = %d", mod_ZeroGoldEnemy);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];

    [top presentViewController:alert animated:YES completion:nil];
}

@end

// ==========================================
// GESTURE HANDLER
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
                SWLLog(@"Gestures attached");
            }
        }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    });
}

- (void)attachGesturesToWindow:(UIWindow *)window {
    for (UIGestureRecognizer *g in window.gestureRecognizers) {
        if (![g isKindOfClass:[UITapGestureRecognizer class]]) continue;
        UITapGestureRecognizer *tap = (UITapGestureRecognizer *)g;
        if (tap.numberOfTouchesRequired == 3 && tap.numberOfTapsRequired == 1) return;
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
    SWLLog(@"Menu gesture fired");
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
    // Init log system trước
    g_logBuffer = [NSMutableArray array];
    g_logLock = [NSLock new];

    SWLLog(@"dylib loaded — ver 2.0");

    // 1. Substrate
    void* substrate = dlopen("@executable_path/libsubstrate.dylib", RTLD_LAZY);
    if (!substrate) substrate = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY);
    if (!substrate) substrate = dlopen("/usr/lib/libsubstitute.dylib", RTLD_LAZY);

    if (!substrate) {
        SWLLog(@"❌ Không có substrate/substitute");
    } else {
        SWLLog(@"✅ substrate loaded");
        MSHookFunction_t MSHookFunction =
            (MSHookFunction_t)dlsym(substrate, "MSHookFunction");

        if (!MSHookFunction) {
            SWLLog(@"❌ Không có MSHookFunction");
        } else {
            SWLLog(@"✅ MSHookFunction available");
            uintptr_t slide = getMainSlide();
            SWLLog(@"main slide = 0x%lx", slide);

            if (slide != 0) {
                void* addr_setGold = (void*)(slide + RVA_Team_set_Gold);
                SWLLog(@"set_Gold @ %p (RVA 0x%X)", addr_setGold, RVA_Team_set_Gold);
                MSHookFunction(addr_setGold, (void*)&new_set_Gold, (void**)&old_set_Gold);

                void* addr_getGold = (void*)(slide + RVA_Team_get_Gold);
                SWLLog(@"get_Gold @ %p (RVA 0x%X)", addr_getGold, RVA_Team_get_Gold);
                MSHookFunction(addr_getGold, (void*)&new_get_Gold, (void**)&old_get_Gold);

                void* addr_setPop = (void*)(slide + RVA_Team_set_Population);
                MSHookFunction(addr_setPop, (void*)&new_set_Population, (void**)&old_set_Population);

                SWLLog(@"✅ Hooks installed");
            } else {
                SWLLog(@"❌ Không tìm được slide");
            }
        }
    }

    // 2. UI
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note){
        [[SWLGestureHandler shared] startWatching];
    }];
}