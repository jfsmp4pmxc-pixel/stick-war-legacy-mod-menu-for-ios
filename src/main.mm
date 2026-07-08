#include <UIKit/UIKit.h>
#include <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>

// Định nghĩa cấu trúc Hook hệ thống
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);

extern "C" {
    // Biến trạng thái điều khiển tính năng game
    bool mod_InfGoldPlayer = false;
    bool mod_InfGoldEnemy = false;
    bool mod_ZeroGoldPlayer = false;
    bool mod_ZeroGoldEnemy = false;

    int mod_SelectedUnitId = 2; // Mặc định: 2 = SWORDWRATH
    int mod_SpawnAmount = 1;
    int mod_SpawnTargetTeam = 0; // 0: Ta, 1: Địch
    bool mod_TriggerSpawnSignal = false;
}

// ==========================================
// LOGIC HOOK GAME (GIỮ NGUYÊN)
// ==========================================
void (*old_set_Gold)(void* instance, int value);
void new_set_Gold(void* instance, int value) {
    if (instance != NULL) {
        int direction = *(int*)((uintptr_t)instance + 0x58); // Offset 0x58: direction
        
        if (direction == 1) { // PHE TA
            if (mod_ZeroGoldPlayer) { old_set_Gold(instance, 9); return; }
            if (mod_InfGoldPlayer) { old_set_Gold(instance, 999999); return; }
        } 
        else if (direction == -1) { // PHE ĐỊCH
            if (mod_ZeroGoldEnemy) { old_set_Gold(instance, 9); return; }
            if (mod_InfGoldEnemy) { old_set_Gold(instance, 999999); return; }
        }
    }
    old_set_Gold(instance, value);
}

// Luồng giám sát lệnh triệu hồi lính từ giao diện
void* SpawnMonitorThread(void* arg) {
    while (true) {
        if (mod_TriggerSpawnSignal) {
            // Nơi xử lý vòng lặp gọi hàm sinh lính theo số lượng (mod_SpawnAmount)
            // và loại lính (mod_SelectedUnitId)...
            usleep(500000); 
            mod_TriggerSpawnSignal = false; // Reset tín hiệu
        }
        usleep(100000);
    }
    return NULL;
}

// ==========================================
// GIAO DIỆN MOD MENU TRÊN IOS (UIBUTTON & MENU)
// ==========================================
@interface SWLMenuManager : NSObject
+ (void)showMenu;
@end

@implementation SWLMenuManager

+ (void)showMenu {
    // Tạo bảng Menu dạng ActionSheet hiển thị từ giữa hoặc dưới màn hình lên
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Stick War Mod Menu" 
                                                                   message:@"Chọn tính năng bạn muốn điều chỉnh:" 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 1. Công tắc Vàng phe Ta
    NSString *txtGoldPlayer = mod_InfGoldPlayer ? @"[ON] Vô hạn Vàng (Phe Ta)" : @"[OFF] Vô hạn Vàng (Phe Ta)";
    [alert addAction:[UIAlertAction actionWithTitle:txtGoldPlayer style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        mod_InfGoldPlayer = !mod_InfGoldPlayer;
        if (mod_InfGoldPlayer) mod_ZeroGoldPlayer = false; // Tắt trạng thái mâu thuẫn
    }]];
    
    // 2. Công tắc 9 Vàng phe Ta
    NSString *txtZeroPlayer = mod_ZeroGoldPlayer ? @"[ON] Luôn có 9 Vàng (Phe Ta)" : @"[OFF] Luôn có 9 Vàng (Phe Ta)";
    [alert addAction:[UIAlertAction actionWithTitle:txtZeroPlayer style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        mod_ZeroGoldPlayer = !mod_ZeroGoldPlayer;
        if (mod_ZeroGoldPlayer) mod_InfGoldPlayer = false;
    }]];

    // 3. Công tắc Vàng phe Địch (Hardcore)
    NSString *txtGoldEnemy = mod_InfGoldEnemy ? @"[ON] Vô hạn Vàng (Phe Địch)" : @"[OFF] Vô hạn Vàng (Phe Địch)";
    [alert addAction:[UIAlertAction actionWithTitle:txtGoldEnemy style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        mod_InfGoldEnemy = !mod_InfGoldEnemy;
        if (mod_InfGoldEnemy) mod_ZeroGoldEnemy = false;
    }]];

    // 4. Công tắc 9 Vàng phe Địch
    NSString *txtZeroEnemy = mod_ZeroGoldEnemy ? @"[ON] Luôn có 9 Vàng (Phe Địch)" : @"[OFF] Luôn có 9 Vàng (Phe Địch)";
    [alert addAction:[UIAlertAction actionWithTitle:txtZeroEnemy style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        mod_ZeroGoldEnemy = !mod_ZeroGoldEnemy;
        if (mod_ZeroGoldEnemy) mod_InfGoldEnemy = false;
    }]];

    // 5. Tính năng Gọi Lính Tùy Chỉnh nhanh (Ví dụ chọn gọi Khổng Lồ)
    [alert addAction:[UIAlertAction actionWithTitle:@"Triệu hồi 5 GIANT (Phe Ta)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        mod_SelectedUnitId = 5;       // 5 là ID Giant trong enum của bạn
        mod_SpawnAmount = 5;          // Gọi hẳn 5 con
        mod_SpawnTargetTeam = 0;      // Phe mình
        mod_TriggerSpawnSignal = true; // Kích hoạt lệnh
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Triệu hồi 10 SWORDWRATH (Phe Địch)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        mod_SelectedUnitId = 2;       // ID Swordwrath
        mod_SpawnAmount = 10;
        mod_SpawnTargetTeam = 1;      // Phe địch
        mod_TriggerSpawnSignal = true;
    }]];

    // Nút đóng Menu
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng Menu" style:UIAlertActionStyleCancel handler:nil]];
    
    [topController presentViewController:alert animated:YES completion:nil];
}

@end

// ==========================================
// TỰ ĐỘNG CHÈN NÚT "..." VÀO GÓC TRÁI DƯỚI CÙNG
// ==========================================
void CreateMenuButton() {
    // Chờ 5 giây sau khi game vào để đảm bảo Window của Unity đã dựng xong hoàn toàn
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        // Lấy Cửa sổ hiển thị chính (An toàn hơn cho mọi đời iOS)
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *window in scene.windows) {
                        if (window.isKeyWindow) {
                            keyWindow = window;
                            break;
                        }
                    }
                }
            }
        }
        if (!keyWindow) {
            keyWindow = [UIApplication sharedApplication].keyWindow;
        }
        
        if (!keyWindow) return; // Nếu chưa tìm thấy window thì thoát để tránh crash

        // Tạo nút bấm "..."
        UIButton *modButton = [UIButton buttonWithType:UIButtonTypeCustom];
        
        // Lấy kích thước thực tế của màn hình (hỗ trợ cả khi xoay ngang game)
        CGFloat screenHeight = keyWindow.bounds.size.height;
        
        // Cấu hình vị trí: Góc trái dưới cùng (Cách lề trái 25pt, Cách đáy màn hình 35pt để né vạch Home)
        // Kích thước nút: 50x50 cho dễ chạm
        modButton.frame = CGRectMake(25, screenHeight - 85, 50, 50);
        
        // Thiết lập chữ hiển thị
        [modButton setTitle:@"..." forState:UIControlStateNormal];
        modButton.titleLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
        [modButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        
        // Đổ bóng đậm hơn để hiển thị rõ trên mọi môi trường đồ họa của game
        modButton.layer.shadowColor = [UIColor blackColor].CGColor;
        modButton.layer.shadowOffset = CGSizeMake(0.0, 2.0);
        modButton.layer.shadowOpacity = 0.9;
        modButton.layer.shadowRadius = 2.0;
        
        // Đảm bảo nút luôn nằm trên cùng các layer khác và không bị bo góc che khuất chữ
        modButton.clipsToBounds = NO;
        
        // Gán sự kiện khi chạm vào nút
        [modButton addTarget:[SWLMenuManager class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        
        // Đưa nút lên lớp cao nhất của ứng dụng
        [keyWindow addSubview:modButton];
        [keyWindow bringSubviewToFront:modButton];
    });
}

// ==========================================
// KHỞI TẠO HOOK & LUỒNG KHI GAME CHẠY
// ==========================================
__attribute__((constructor)) static void init() {
    uintptr_t target_slide = _dyld_get_image_vmaddr_slide(0);
    
    void *substrate = dlopen("@executable_path/libsubstrate.dylib", RTLD_LAZY);
    if (!substrate) substrate = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY);
    
    if (substrate) {
        MSHookFunction_t MSHookFunction = (MSHookFunction_t)dlsym(substrate, "MSHookFunction");
        if (MSHookFunction) {
            // Hook hàm set_Gold (Offset Hex: 0x39747060)
            MSHookFunction((void*)(target_slide + 0x39747060), (void*)&new_set_Gold, (void**)&old_set_Gold);
        }
    }
    
    // Chạy luồng ngầm quản lý Spawn lính
    pthread_t spawnThread;
    pthread_create(&spawnThread, NULL, SpawnMonitorThread, NULL);
    
    // Gọi hàm tạo nút bấm "..." sau khi game khởi động
    CreateMenuButton();
}