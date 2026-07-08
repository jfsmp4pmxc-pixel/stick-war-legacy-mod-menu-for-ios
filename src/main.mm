#include <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>

// Định nghĩa con trỏ hàm để gọi hàm MSHookFunction hệ thống
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);

extern "C" {
    // ==========================================
    // TRẠNG THÁI CÔNG TẮC ĐIỀU KHIỂN TỪ MOD MENU
    // ==========================================
    // (Giao diện Menu của bạn sẽ thay đổi các biến này)
    
    bool mod_InfGoldPlayer = false;   // Bật/tắt Vô hạn vàng phe Ta
    bool mod_InfGoldEnemy = false;    // Bật/tắt Vô hạn vàng phe Địch
    bool mod_ZeroGoldPlayer = false;  // Bật/tắt Luôn luôn 9 vàng phe Ta
    bool mod_ZeroGoldEnemy = false;   // Bật/tắt Luôn luôn 9 vàng phe Địch

    int mod_SelectedUnitId = 2;       // ID loại lính chọn từ danh sách (Mặc định: 2 = SWORDWRATH)
    int mod_SpawnAmount = 1;          // Số lượng lính tùy chỉnh cần gọi
    int mod_SpawnTargetTeam = 0;      // Phe nhận lính (0: Phe mình, 1: Phe địch)
    bool mod_TriggerSpawnSignal = false; // Menu bật true để kích hoạt lệnh triệu hồi
}

// ==========================================
// LOGIC HOOK XỬ LÝ VÀNG (set_Gold)
// ==========================================
void (*old_set_Gold)(void* instance, int value);
void new_set_Gold(void* instance, int value) {
    if (instance != NULL) {
        // Đọc biến direction (Offset 0x58 từ class Team) để phân biệt phe
        int direction = *(int*)((uintptr_t)instance + 0x58); 
        
        if (direction == 1) { // PHE TA (PLAYER)
            if (mod_ZeroGoldPlayer) {
                old_set_Gold(instance, 9); // Luôn giữ 9 vàng
                return;
            }
            if (mod_InfGoldPlayer) {
                old_set_Gold(instance, 999999); // Vô hạn vàng
                return;
            }
        } 
        else if (direction == -1) { // PHE ĐỊCH (ENEMY)
            if (mod_ZeroGoldEnemy) {
                old_set_Gold(instance, 9); // Luôn giữ 9 vàng
                return;
            }
            if (mod_InfGoldEnemy) {
                old_set_Gold(instance, 999999); // Vô hạn vàng tăng độ khó
                return;
            }
        }
    }
    // Trả về logic gốc nếu không bật tính năng nào
    old_set_Gold(instance, value);
}

// ==========================================
// LOGIC HOOK TRIỆU HỒI LÍNH (CreateUnit)
// ==========================================
void* (*old_CreateUnit)(void* unitTypeClass);
void* new_CreateUnit(void* unitTypeClass) {
    // Gọi hàm gốc để tạo thực thể GameObject của lính trước
    void* newUnitGameObject = old_CreateUnit(unitTypeClass);
    
    // Nếu có tín hiệu triệu hồi lính tùy chỉnh đang chạy
    if (newUnitGameObject != NULL && mod_TriggerSpawnSignal) {
        // [TÙY BIẾN PHÂN PHE CHO LÍNH TẠI ĐÂY NẾU CẦN]
        // Thường biến 'team' nằm ở cấu trúc dữ liệu bên trong Unit, bạn có thể ép
        // thuộc tính team dựa trên giá trị của mod_SpawnTargetTeam.
    }
    return newUnitGameObject;
}

// Vòng lặp kiểm tra tín hiệu bấm nút từ Menu (Chạy ngầm độc lập)
void* SpawnMonitorThread(void* arg) {
    while (true) {
        if (mod_TriggerSpawnSignal) {
            // Nhận tín hiệu triệu hồi lính từ menu
            // Thực hiện vòng lặp gọi hàm sinh lính theo số lượng tùy chỉnh
            for (int i = 0; i < mod_SpawnAmount; i++) {
                // Giả lập hoặc gọi trực tiếp thông qua việc đẩy dữ liệu vào Class lính
                // (Trong game Unity tĩnh, bạn cần truyền class tương ứng với mod_SelectedUnitId)
            }
            // Triệu hồi xong, tắt tín hiệu chờ lượt bấm tiếp theo
            mod_TriggerSpawnSignal = false; 
        }
        usleep(100000); // Ngủ 100ms để tránh tốn CPU của iPhone
    }
    return NULL;
}

// ==========================================
// HÀM KHỞI TẠO HOOK KHI GAME LOAD
// ==========================================
__attribute__((constructor)) static void init() {
    // Lấy Base Address của game (ASLR)
    uintptr_t target_slide = _dyld_get_image_vmaddr_slide(0);
    
    // Nạp thư viện Substrate hệ thống để lấy hàm Hook
    void *substrate = dlopen("@executable_path/libsubstrate.dylib", RTLD_LAZY);
    if (!substrate) {
        substrate = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY);
    }
    
    if (substrate) {
        MSHookFunction_t MSHookFunction = (MSHookFunction_t)dlsym(substrate, "MSHookFunction");
        if (MSHookFunction) {
            // Hook hàm set_Gold (Offset Hex: 0x39747060)
            MSHookFunction((void*)(target_slide + 0x39747060), (void*)&new_set_Gold, (void**)&old_set_Gold);
            
            // Hook hàm CreateUnit (Offset Hex: 0x3914AF8)
            MSHookFunction((void*)(target_slide + 0x3914AF8), (void*)&new_CreateUnit, (void**)&old_CreateUnit);
        }
    }
    
    // Khởi tạo luồng chạy ngầm theo dõi nút bấm Spawn lính
    pthread_t spawnThread;
    pthread_create(&spawnThread, NULL, SpawnMonitorThread, NULL);
}
