#include <UIKit/UIKit.h>
#include <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>

// Định nghĩa cấu trúc Hook hệ thống
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);

extern "C" {
    // Biến trạng thái điều khiển tính năng game (Xuất ra ngoài để Menu đọc)
    bool mod_InfGoldPlayer = false;
    bool mod_InfGoldEnemy = false;
    bool mod_ZeroGoldPlayer = false;
    bool mod_ZeroGoldEnemy = false;

    int mod_SelectedUnitId = 2;   // Mặc định: 2 = SWORDWRATH
    int mod_SpawnAmount = 1;      // Số lượng lính tùy chỉnh
    int mod_SpawnTargetTeam = 0;  // 0: Phe mình, 1: Phe địch
    bool mod_TriggerSpawnSignal = false; // Tín hiệu bấm nút từ Menu
}

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
            // [Xử lý Spawn Lính]: Logic vòng lặp gọi hàm sinh lính Unity tại đây...
            usleep(500000); 
            mod_TriggerSpawnSignal = false; 
        }
        usleep(100000);
    }
    return NULL;
}

// ==========================================
// QUẢN LÝ HIỂN THỊ MENU HỆ THỐNG
// ==========================================
@interface SWLMenuManager : NSObject
+ (void)showMenu;
@end

@implementation SWLMenuManager

+ (void)showMenu {
    // Lấy ViewController đang hiển thị trên màn hình hiện tại
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Stick War Mod Menu" 
                                                                   message:@"Chọn tính năng cần điều chỉnh:" 
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
    
    [topController presentViewController:alert animated:YES completion:nil];
}

@end

// ==========================================
// TẠO LỚP WINDOW RIÊNG ĐỂ HIỆN NÚT "..." KHÔNG NỀN
// ==========================================
static UIWindow *customOverlayWindow = nil;

void CreateIndependentMenuButton() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        // 1. Khởi tạo một Window độc lập hoàn toàn với cấu trúc của Unity
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        customOverlayWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, screenBounds.size.height - 75, 60, 60)];
        
        // Làm cho nền của Window này hoàn toàn trong suốt
        customOverlayWindow.backgroundColor = [UIColor clearColor];
        
        // Đặt mức ưu tiên siêu cao, nằm đè lên cả Thanh trạng thái (Status Bar) để Unity không thể che
        customOverlayWindow.windowLevel = UIWindowLevelStatusBar + 100;
        
        // Cần gán một RootViewController trống để thỏa mãn cấu trúc iOS 15+
        customOverlayWindow.rootViewController = [[UIViewController alloc] init];
        customOverlayWindow.rootViewController.view.backgroundColor = [UIColor clearColor];
        
        // 2. Tạo nút bấm "..." không nền bên trong Window độc lập này
        UIButton *modButton = [UIButton buttonWithType:UIButtonTypeCustom];
        modButton.frame = CGRectMake(0, 0, 50, 50);
        
        [modButton setTitle:@"..." forState:UIControlStateNormal];
        modButton.titleLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
        [modButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        
        // Tạo đổ bóng đen sâu phía sau chữ "..." để nổi bật trên mọi địa hình map game
        modButton.layer.shadowColor = [UIColor blackColor].CGColor;
        modButton.layer.shadowOffset = CGSizeMake(0.0, 1.5);
        modButton.layer.shadowOpacity = 0.95;
        modButton.layer.shadowRadius = 1.5;
        
        // Gán sự kiện mở bảng danh sách Mod Menu khi bấm vào
        [modButton addTarget:[SWLMenuManager class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        
        // Đưa nút vào Window độc lập và kích hoạt hiển thị
        [customOverlayWindow.rootViewController.view addSubview:modButton];
        customOverlayWindow.hidden = NO; 
    });
}

// ==========================================
// HÀM KHỞI TẠO CHÍNH (CONSTRUCTOR)
// ==========================================
__attribute__((constructor)) static void init() {
    // Tính toán địa chỉ bộ nhớ nền ASLR
    uintptr_t target_slide = _dyld_get_image_vmaddr_slide(0);
    
    // Nạp thư viện Substrate để tiến hành Hook
    void *substrate = dlopen("@executable_path/libsubstrate.dylib", RTLD_LAZY);
    if (!substrate) substrate = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY);
    
    if (substrate) {
        MSHookFunction_t MSHookFunction = (MSHookFunction_t)dlsym(substrate, "MSHookFunction");
        if (MSHookFunction) {
            // Tiến hành Hook vào hàm chỉnh Vàng (Offset Hex đã phân tích: 0x39747060)
            MSHookFunction((void*)(target_slide + 0x39747060), (void*)&new_set_Gold, (void**)&old_set_Gold);
        }
    }
    
    // Chạy ngầm luồng giám sát tín hiệu triệu hồi lính
    pthread_t spawnThread;
    pthread_create(&spawnThread, NULL, SpawnMonitorThread, NULL);
    
    // Tạo nút bấm "..." ở góc trái dưới cùng bằng cơ chế Window độc lập chống đè
    CreateIndependentMenuButton();
}