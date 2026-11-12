// Menu overlay: nút nổi kéo được + bảng điều khiển vàng / triệu hồi lính.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Tạo cửa sổ overlay (gọi trên bất kỳ thread nào, tự chuyển về main thread).
// An toàn khi gọi nhiều lần; nếu chưa có scene sẵn sàng sẽ tự thử lại.
void SWMenuInstall(void);

#ifdef __cplusplus
}
#endif
