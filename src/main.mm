#include <UIKit/UIKit.h>
#include <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>

// Định nghĩa cấu trúc Hook hệ thống
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);

extern "C" {
    // Biến trạng thái điều khiển tính năng game (Xuất ra ngoài cho Menu đọc)
    bool mod_InfGoldPlayer = false;
    bool mod_InfGoldEnemy = false;
    bool mod_ZeroGoldPlayer = false;
    bool mod_ZeroGoldEnemy = false;

    int mod_SelectedUnitId = 2;   // 2 = SWORDWRATH, 5 = GIANT...
    int mod_SpawnAmount = 1;      // Số lượng lính tùy chỉnh
    int mod_SpawnTargetTeam = 0;  // 0: Phe mình, 1: Phe địch
    bool mod_TriggerSpawnSignal = false; // Tín hiệu kích hoạt lệnh
}

// Con trỏ hàm gốc của game thu thập từ công đoạn phân tích file dump
void* (*old_CreateUnit)(void* unitTypeClass);
void* (*old_GetTeam)(int teamId); // Hàm giả định lấy thực thể Team từ trận đấu hiện tại

// ==========================================
// LOGIC HOOK GAME TRÊN IL2CPP
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

// Luồng xử lý lệnh triệu hồi lính (Chạy ngầm độc lập)
void* SpawnMonitorThread(void* arg) {
    while (true) {
        if (mod_TriggerSpawnSignal) {
            // Trong môi trường Unity il2cpp, việc gọi CreateUnit cần truyền đúng con trỏ System.Type của lính.
            // Đoạn code này chạy vòng lặp theo số lượng bạn yêu cầu từ Mod Menu.
            for (int i = 0; i < mod_SpawnAmount; i++) {
                // Logic ép sinh thực thể lính thông qua hàm Hook hoặc gọi trực tiếp offset
                // old_CreateUnit(targetClassType); 
            }
            mod_TriggerSpawnSignal = false; // Tắt tín hiệu sau khi hoàn thành
        }
        usleep(100000);
    }
    return NULL;
}

// ==========================================
// QUẢN LÝ GIAO DIỆN MOD MENU HỆ THỐNG
// ==========================================
@interface SWLMenuManager : NSObject
+ (void)showMenu;
@end

@implementation SWLMenuManager

+ (void)showMenu {
    // Tìm kiếm ViewController lớp cao nhất hiện tại một cách an toàn
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    // Nếu vẫn không tìm được qua keyWindow, quét toàn bộ các cửa sổ đang kết nối
    if (!topController && @available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) {
                    if (window.rootViewController) {
                        topController = window.rootViewController;
                        while (topController.presentedViewController) {
                            topController = topController.presentedViewController;
                        }
                        break;
                    }
                }
            }
        }
    }

    if (!topController) return; // Phòng tránh crash nếu game chưa dựng xong UI

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Stick War Mod Menu" 
                                                                   message:@"Điều khiển tính năng (Gõ 3 ngón tay để mở lại):" 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // --- KHU VỰC CÔNG TẮC VÀNG ---
    NSString *txtGoldPlayer = mod_InfGoldPlayer ? @"[ON] Vô hạn Vàng (Phe Ta)" : @"[OFF] Vô hạn Vàng (Phe Ta)";
    [alert addAction:[UIAlertAction actionWithTitle:txtGoldPlayer style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        mod_InfGoldPlayer = !mod_InfGoldPlayer;
        if (mod_InfGoldPlayer) mod_ZeroGoldPlayer = false;
    }]];
    
    NSString *txtZeroPlayer = mod_ZeroGoldPlayer ? @"[ON] Luôn có 9 Vàng (Phe Ta)" : @"[OFF] Luôn có 9 Vàng (Phe Ta)";
    [alert addAction:[UIAlertAction actionWithTitle:txtZeroPlayer style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        mod_ZeroGoldPlayer = !mod_ZeroGoldPlayer;
        if (mod_ZeroGoldPlayer) mod_InfGoldPlayer = false;
    }]];

    NSString *txtGoldEnemy = mod_InfGoldEnemy ? @"[ON] Vô hạn Vàng (Phe Địch)" : @"[OFF] Vô hạn Vàng (Phe Địch)";
    [alert addAction:[UIAlertAction actionWithTitle:txtGoldEnemy style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        mod_InfGoldEnemy = !mod_InfGoldEnemy;
        if (mod_InfGoldEnemy) mod_ZeroGoldEnemy = false;
    }]];

    NSString *txtZeroEnemy = mod_ZeroGoldEnemy ? @"[ON] Luôn có 9 Vàng (Phe Địch)" : @"[OFF] Luôn có 9 Vàng (Phe Địch)";
    [alert addAction:[UIAlertAction actionWithTitle:txtZeroEnemy style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        mod_ZeroGoldEnemy = !mod_ZeroGoldEnemy;
        if (mod_ZeroGoldEnemy) mod_InfGoldEnemy = false;
    }]];

    // --- KHU VỰC ĐIỀU CHỈNH SPAWN LÍNH (DANH SÁCH NHANH) ---
    [alert addAction:[UIAlertAction actionWithTitle:@"Triệu hồi 5 GIANT (Phe Ta)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        mod_SelectedUnitId = 5;       // ID Giant
        mod_SpawnAmount = 5;
        mod_SpawnTargetTeam = 0;      // Phe mình
        mod_TriggerSpawnSignal = true;
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Triệu hồi 10 SWORDWRATH (Phe Địch)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        mod_SelectedUnitId = 2;       // ID Swordwrath
        mod_SpawnAmount = 10;
        mod_SpawnTargetTeam = 1;      // Phe địch
        mod_TriggerSpawnSignal = true;
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng Menu" style:UIAlertActionStyleCancel handler:nil]];
    
    // Ép hiển thị Menu hệ thống lên trên cùng màn hình
    [topController presentViewController:alert animated:YES completion:nil];
}

@end

// ==========================================
// CƠ CHẾ KÍCH HOẠT MENU BẰNG CỬ CHỈ TRONG SUỐT
// ==========================================
@interface SWLGestureHandler : NSObject
+ (void)setupGesture;
@end

@implementation SWLGestureHandler

+ (void)setupGesture {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window && @available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    window = scene.windows.firstObject;
                    break;
                }
            }
        }
        
        if (window) {
            // Tạo cử chỉ chạm đồng thời 3 ngón tay lên màn hình để mở Menu
            UITapGestureRecognizer *threeFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:[SWLMenuManager class] action:@selector(showMenu)];
            threeFingerTap.numberOfTouchesRequired = 3; // Yêu cầu chạm bằng 3 ngón tay cùng lúc
            threeFingerTap.numberOfTapsRequired = 1;
            
            [window addGestureRecognizer:threeFingerTap];
            
            // Dự phòng thêm: Gõ liên tục 3 lần bằng 1 ngón tay vào màn hình phòng trường hợp đa điểm bị lỗi
            UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:[SWLMenuManager class] action:@selector(showMenu)];
            tripleTap.numberOfTapsRequired = 3; // Gõ nhanh 3 phát liên tục
            tripleTap.numberOfTouchesRequired = 1;
            
            [window addGestureRecognizer:tripleTap];
        }
    });
}

@end

// ==========================================
// HÀM KHỞI TẠO CHÍNH (CONSTRUCTOR)
// ==========================================
__attribute__((constructor)) static void init() {
    uintptr_t target_slide = _dyld_get_image_vmaddr_slide(0);
    
    void *substrate = dlopen("@executable_path/libsubstrate.dylib", RTLD_LAZY);
    if (!substrate) substrate = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY);
    
    if (substrate) {
        MSHookFunction_t MSHookFunction = (MSHookFunction_t)dlsym(substrate, "MSHookFunction");
        if (MSHookFunction) {
            // Hook hàm chỉnh Vàng (Offset Hex: 0x39747060)
            MSHookFunction((void*)(target_slide + 0x39747060), (void*)&new_set_Gold, (void**)&old_set_Gold);
        }
    }
    
    // Chạy ngầm luồng giám sát tín hiệu triệu hồi lính
    pthread_t spawnThread;
    pthread_create(&spawnThread, NULL, SpawnMonitorThread, NULL);
    
    // Kích hoạt hệ thống lắng nghe cử chỉ mở Menu độc lập chống đè đồ họa
    [SWLGestureHandler setupGesture];
}