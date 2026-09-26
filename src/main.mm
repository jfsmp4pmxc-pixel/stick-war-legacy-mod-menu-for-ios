#include <UIKit/UIKit.h>
#include <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <mach/vm_map.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>

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
// GLOBAL STATE
// ==========================================
static int  g_setGoldCalls = 0;
static int  g_getGoldCalls = 0;
static int  g_lastDir = 0;
static int  g_lastValue = 0;
static int  g_lastGetValue = 0;
static bool g_hookMethod = false;
static bool g_hookOK = false;

static NSMutableArray<NSString*> *g_logBuffer = nil;
static NSLock *g_logLock = nil;

// ==========================================
// LOG (an toàn trong mọi thread)
// ==========================================
static void SWLLog(NSString *fmt, ...) {
    @autoreleasepool {
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
        if (g_logBuffer.count > 300) [g_logBuffer removeObjectAtIndex:0];
        [g_logLock unlock];
    }
}

// ==========================================
// ORIGINALS
// ==========================================
void (*old_set_Gold)(void* this_, int value, void* method) = NULL;
void (*old_set_Population)(void* this_, int value, void* method) = NULL;

// ==========================================
// HOOK IMPLEMENTATIONS
// ==========================================
__attribute__((noinline))
void new_set_Gold(void* this_, int value, void* method) {
    // Guard cực kỳ quan trọng: this_ có thể NULL hoặc invalid
    if (this_ == NULL || (uintptr_t)this_ < 0x100000000ULL) {
        if (old_set_Gold) old_set_Gold(this_, value, method);
        return;
    }

    g_setGoldCalls++;

    int dir = -999;
    @try {
        dir = *(int*)((uintptr_t)this_ + OFF_Team_direction);
    } @catch (NSException *e) {
        dir = -998;
    }

    g_lastDir = dir;
    g_lastValue = value;

    if (g_setGoldCalls <= 20) {
        SWLLog(@"set_Gold #%d this=%p dir=%d val=%d",
               g_setGoldCalls, this_, dir, value);
    }

    if (old_set_Gold != NULL) {
        if (dir == 1) {
            if (mod_ZeroGoldPlayer) { old_set_Gold(this_, 9, method); return; }
            if (mod_InfGoldPlayer)  { old_set_Gold(this_, 999999, method); return; }
        } else if (dir == -1) {
            if (mod_ZeroGoldEnemy)  { old_set_Gold(this_, 9, method); return; }
            if (mod_InfGoldEnemy)   { old_set_Gold(this_, 999999, method); return; }
        }
        old_set_Gold(this_, value, method);
    }
}

__attribute__((noinline))
void new_set_Population(void* this_, int value, void* method) {
    if (old_set_Population) old_set_Population(this_, value, method);
}

// ==========================================
// INLINE HOOK ARM64 (chỉ dùng nếu KHÔNG có substrate)
// ==========================================
static bool inline_hook_arm64(void* target, void* replacement, void** orig_out) {
    const size_t PAGE = 4096;
    uintptr_t pageAddr = (uintptr_t)target & ~(uintptr_t)(PAGE - 1);

    void *newPage = mmap(NULL, PAGE, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (newPage == MAP_FAILED) {
        SWLLog(@"❌ mmap newPage fail: %s", strerror(errno));
        return false;
    }
    memcpy(newPage, (void*)pageAddr, PAGE);

    uintptr_t targetOffset = (uintptr_t)target - pageAddr;
    void *targetCopy = (void*)((uintptr_t)newPage + targetOffset);

    void *tramp = mmap(NULL, PAGE, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (tramp == MAP_FAILED) {
        SWLLog(@"❌ mmap tramp fail: %s", strerror(errno));
        munmap(newPage, PAGE);
        return false;
    }

    uint8_t saved[16];
    memcpy(saved, target, 16);
    memcpy(tramp, saved, 16);

    uint32_t* tp = (uint32_t*)((uintptr_t)tramp + 16);
    tp[0] = 0x58000050;
    tp[1] = 0xD61F0200;
    *(uint64_t*)(tp + 2) = (uint64_t)((uintptr_t)target + 16);

    mprotect(tramp, PAGE, PROT_READ | PROT_EXEC);
    sys_icache_invalidate(tramp, 32);

    uint32_t* pp = (uint32_t*)targetCopy;
    pp[0] = 0x58000050;
    pp[1] = 0xD61F0200;
    *(uint64_t*)(pp + 2) = (uint64_t)replacement;
    sys_icache_invalidate(targetCopy, 16);

    vm_prot_t cur_prot = VM_PROT_NONE;
    vm_prot_t max_prot = VM_PROT_NONE;
    vm_address_t dest = (vm_address_t)pageAddr;

    kern_return_t kr = vm_remap(mach_task_self(),
                                 &dest,
                                 PAGE,
                                 0,
                                 VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE,
                                 mach_task_self(),
                                 (vm_address_t)newPage,
                                 FALSE,
                                 &cur_prot, &max_prot,
                                 VM_INHERIT_NONE);
    if (kr != KERN_SUCCESS) {
        SWLLog(@"❌ vm_remap fail: %d", kr);
        munmap(newPage, PAGE);
        munmap(tramp, PAGE);
        return false;
    }

    SWLLog(@"✅ Inline hook OK qua vm_remap");
    *orig_out = tramp;
    return true;
}

// ==========================================
// DETECT SUBSTRATE
// ==========================================
static MSHookFunction_t g_msHook = NULL;
static bool g_msInit = false;

static bool detectSubstrate(void) {
    if (g_msInit) return (g_msHook != NULL);

    // 1. Global
    g_msHook = (MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (g_msHook) {
        g_msInit = true;
        SWLLog(@"✅ MSHookFunction có sẵn");
        return true;
    }

    // 2. Bundle
    const char* bundlePaths[] = {
        "@executable_path/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "@executable_path/Frameworks/libsubstrate.dylib",
        "@executable_path/Frameworks/libsubstitute.dylib",
        "@executable_path/Frameworks/libellekit.dylib",
        "@executable_path/libsubstrate.dylib",
        "@executable_path/libsubstitute.dylib",
    };
    for (size_t i = 0; i < sizeof(bundlePaths)/sizeof(bundlePaths[0]); i++) {
        void* h = dlopen(bundlePaths[i], RTLD_NOW | RTLD_GLOBAL);
        if (!h) continue;
        MSHookFunction_t m = (MSHookFunction_t)dlsym(h, "MSHookFunction");
        if (m) {
            g_msHook = m;
            g_msInit = true;
            SWLLog(@"✅ MSHookFunction từ: %s", bundlePaths[i]);
            return true;
        }
    }

    // 3. JB paths
    const char* jbPaths[] = {
        "/var/jb/usr/lib/libsubstrate.dylib",
        "/var/jb/usr/lib/libsubstitute.dylib",
        "/var/jb/usr/lib/libellekit.dylib",
        "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "/usr/lib/libsubstrate.dylib",
        "/usr/lib/libsubstitute.dylib",
        "/usr/lib/libellekit.dylib",
    };
    for (size_t i = 0; i < sizeof(jbPaths)/sizeof(jbPaths[0]); i++) {
        void* h = dlopen(jbPaths[i], RTLD_NOW | RTLD_GLOBAL);
        if (!h) continue;
        MSHookFunction_t m = (MSHookFunction_t)dlsym(h, "MSHookFunction");
        if (m) {
            g_msHook = m;
            g_msInit = true;
            SWLLog(@"✅ MSHookFunction từ: %s", jbPaths[i]);
            return true;
        }
    }

    // 4. Leaf names
    const char* names[] = {
        "libsubstrate.dylib",
        "libsubstitute.dylib",
        "libellekit.dylib",
        "CydiaSubstrate",
    };
    for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); i++) {
        void* h = dlopen(names[i], RTLD_NOW | RTLD_GLOBAL);
        if (!h) continue;
        MSHookFunction_t m = (MSHookFunction_t)dlsym(h, "MSHookFunction");
        if (m) {
            g_msHook = m;
            g_msInit = true;
            SWLLog(@"✅ MSHookFunction theo tên: %s", names[i]);
            return true;
        }
    }

    // Chưa tìm được — chưa đánh dấu init để lần sau thử lại
    return false;
}

static bool doHook(void* addr, void* replacement, void** orig_out) {
    if (detectSubstrate() && g_msHook) {
        g_msHook(addr, replacement, orig_out);
        g_hookMethod = true;
        return (*orig_out != NULL);
    }
    bool ok = inline_hook_arm64(addr, replacement, orig_out);
    g_hookMethod = false;
    return ok;
}

// ==========================================
// DYLD SLIDE
// ==========================================
static uintptr_t findImageSlide(const char* keyword) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, keyword)) {
            uintptr_t slide = _dyld_get_image_vmaddr_slide(i);
            SWLLog(@"Image #%u: %s slide=0x%lx", i, name, slide);
            return slide;
        }
    }
    return 0;
}

static uintptr_t getMainSlide() {
    NSString* proc = [[NSProcessInfo processInfo] processName];
    SWLLog(@"Process: %@", proc);
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
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];

    CGRect b = self.view.bounds;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 50, b.size.width - 20, 30)];
    title.text = @"📋 SWL Debug Log";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    title.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:title];

    UILabel *stats = [[UILabel alloc] initWithFrame:CGRectMake(10, 85, b.size.width - 20, 90)];
    stats.numberOfLines = 0;
    stats.textColor = [UIColor yellowColor];
    stats.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    stats.text = [NSString stringWithFormat:
        @"Hook method: %@\n"
        @"Hook OK: %@\n"
        @"set_Gold calls: %d (dir=%d val=%d)\n"
        @"get_Gold calls: %d (ret=%d)",
        g_hookMethod ? @"MSHookFunction" : @"Inline arm64",
        g_hookOK ? @"YES ✅" : @"NO ❌",
        g_setGoldCalls, g_lastDir, g_lastValue,
        g_getGoldCalls, g_lastGetValue];
    [self.view addSubview:stats];

    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(10, 185, b.size.width - 20, b.size.height - 260)];
    tv.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    tv.editable = NO;

    NSMutableString *all = [NSMutableString string];
    [g_logLock lock];
    for (NSString *line in g_logBuffer) [all appendFormat:@"%@\n", line];
    [g_logLock unlock];
    if (all.length == 0) [all appendString:@"(chưa có log)"];
    tv.text = all;
    if (tv.text.length > 1) [tv scrollRangeToVisible:NSMakeRange(tv.text.length - 1, 1)];
    [self.view addSubview:tv];

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
    if (!top) { SWLLog(@"showMenu: no top VC"); return; }
    if (top.presentedViewController) { SWLLog(@"showMenu: VC busy"); return; }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Stick War Mod Menu"
                         message:[NSString stringWithFormat:@"Hook: %@ | set calls: %d",
                                  g_hookMethod ? @"MSHook" : @"Inline",
                                  g_setGoldCalls]
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"📋 Xem Log Debug" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        SWLLogViewer *v = [SWLLogViewer new];
        v.modalPresentationStyle = UIModalPresentationOverFullScreen;
        [top presentViewController:v animated:YES completion:nil];
    }]];

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
// HOOK SETUP (chạy SAU khi app active)
// ==========================================
static void performHooks(void) {
    SWLLog(@"--- performHooks ---");

    uintptr_t slide = getMainSlide();
    SWLLog(@"main slide = 0x%lx", slide);

    if (slide == 0) {
        SWLLog(@"❌ Không tìm được slide");
        return;
    }

    void* addr_setGold = (void*)(slide + RVA_Team_set_Gold);
    SWLLog(@"set_Gold @ %p (RVA 0x%X)", addr_setGold, RVA_Team_set_Gold);

    bool ok = false;
    @try {
        ok = doHook(addr_setGold,
                    (void*)&new_set_Gold,
                    (void**)&old_set_Gold);
    } @catch (NSException *e) {
        SWLLog(@"❌ Exception khi hook set_Gold: %@", e);
    }

    if (ok) {
        SWLLog(@"✅ set_Gold hooked (%s)",
               g_hookMethod ? "MSHook" : "inline");
        g_hookOK = true;
    } else {
        SWLLog(@"❌ set_Gold hook FAILED");
    }

    // set_Population (optional, không crash nếu fail)
    void* addr_setPop = (void*)(slide + RVA_Team_set_Population);
    @try {
        bool ok2 = doHook(addr_setPop,
                          (void*)&new_set_Population,
                          (void**)&old_set_Population);
        if (ok2) SWLLog(@"✅ set_Population hooked");
        else     SWLLog(@"⚠️ set_Population hook fail");
    } @catch (NSException *e) {
        SWLLog(@"⚠️ Exception set_Population: %@", e);
    }

    SWLLog(@"--- performHooks done ---");
}

// ==========================================
// CONSTRUCTOR (chỉ log + đăng ký observer, KHÔNG hook)
// ==========================================
__attribute__((constructor)) static void swl_init() {
    @autoreleasepool {
        g_logBuffer = [NSMutableArray array];
        g_logLock = [NSLock new];

        SWLLog(@"dylib loaded — ver 5.0 (deferred hook)");

        // Đợi app active rồi mới hook
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note){
            SWLLog(@"App became active — scheduling hook");

            // Đợi thêm 3s cho chắc chắn game đã load hết + substrate đã vào
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                // Thử hook — retry tối đa 10 lần nếu chưa có substrate
                for (int attempt = 1; attempt <= 10; attempt++) {
                    SWLLog(@"Hook attempt #%d", attempt);

                    __block bool hadSubstrate = false;
                    __block bool hookDone = false;

                    dispatch_sync(dispatch_get_main_queue(), ^{
                        hadSubstrate = detectSubstrate();
                    });

                    if (hadSubstrate) {
                        SWLLog(@"Substrate sẵn sàng — thực hiện hook");
                        performHooks();
                        hookDone = true;
                    } else {
                        SWLLog(@"⚠️ Chưa có substrate, đợi 500ms rồi thử lại...");
                    }

                    if (hookDone) break;
                    usleep(500000);
                }

                // Setup gesture
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[SWLGestureHandler shared] startWatching];
                });
            });
        }];
    }
}