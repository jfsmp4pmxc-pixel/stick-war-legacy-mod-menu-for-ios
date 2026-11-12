# Stick War: Legacy Mod Menu (iOS)

Dylib mod cho **Stick War: Legacy** trên iOS (arm64, iOS 15+), chèn vào app bằng TrollStore hoặc công cụ chèn dylib tương tự. Mod dùng cho **chơi offline**, tránh dùng ở Tournament hay bất cứ chế độ nào có bảng xếp hạng.

## Tính năng

- **Vàng**: chọn riêng cho phe ta và phe địch: Tắt / Vô hạn / Còn 9.
- **Triệu hồi lính**: chọn phe (Ta / Địch), số lượng (1 / 5 / 10 / 25), rồi bấm loại lính: Thợ mỏ, Swordwrath, Archidon, Spearton, Magikill, Giant.
- **Nới giới hạn dân số** thêm 50.
- **Xem và sao chép log** để gửi khi cần báo lỗi.

## Cách dùng

1. Chèn `StickWarMod.dylib` vào app game, mở game.
2. Sau vài giây một nút tròn **SW** hiện ở góc trái màn hình. Kéo để di chuyển, chạm để mở menu.
3. Vào một màn chơi rồi mới dùng các nút (dòng trạng thái đầu menu chuyển sang "đang trong trận").

## Cách hoạt động

Mod **không hook và không vá mã**. Nó tìm class và method của game theo tên lúc chạy qua IL2CPP API (`dlsym`), rồi chỉ **gọi** hàm có sẵn của game bằng `il2cpp_runtime_invoke`:

| Việc | Hàm của game |
| --- | --- |
| Lấy hai phe | `GameController.Instance` → `FriendlyTeam` / `EnemyTeam` |
| Đặt vàng | `Team.set_Gold(int)` (gọi lại mỗi 0,25 giây khi bật) |
| Triệu hồi lính | `Team.BuildUnit(Type, bool, SpawnGroup, UnitOverrides)` |
| Nới dân số | `GameController.SetExtraPopulation(int)` |

Vì tìm theo tên, bản cập nhật game không làm hỏng mod trừ khi nhà phát hành đổi tên các class/method trên. Các tên này lấy từ dump IL2CPP (RVA của bản đã dump chỉ để tham khảo: `Team.set_Gold` 0x38FAAF4, `Team.BuildUnit` 0x38F6188, `GameController.SetExtraPopulation` 0x3A017A8).

## Cấu trúc

```
src/
  il2cpp.hpp/.cpp   tìm class/method/field và gọi hàm qua IL2CPP API
  game.hpp/.cpp     logic mod: vàng, triệu hồi lính, dân số
  menu.h/.mm        nút nổi và bảng điều khiển (UIKit)
  logger.h/.mm      log có vòng đệm, xem được trong menu
  main.mm           điểm vào của dylib
.github/workflows/main.yml   build bằng GitHub Actions
```

## Build

Mỗi lần push lên `main` (hoặc chạy tay workflow **Build iOS Standalone Dylib**), GitHub Actions biên dịch và ký ad-hoc `StickWarMod.dylib`. Tải ở mục **Artifacts** của lần chạy.

Build tay trên macOS có Xcode:

```bash
clang++ -dynamiclib -std=c++17 -fobjc-arc -fvisibility=hidden -arch arm64 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" -miphoneos-version-min=15.0 \
  -framework Foundation -framework UIKit src/*.cpp src/*.mm -o StickWarMod.dylib
codesign -f -s - StickWarMod.dylib
```

## Khi không chạy

Mở menu → **Xem log**. Dòng trạng thái đầu menu cho biết:

- `IL2CPP ✗`: không tìm thấy các hàm `il2cpp_*` trong tiến trình (bản game đã ẩn symbol). Gửi log để xử lý tiếp.
- `chưa thấy class của game` hoặc `thiếu field/method của game`: tên class/method khác với dump, log sẽ ghi rõ tên nào thiếu.
- `Team.BuildUnit ném ngoại lệ`: game từ chối tham số khi triệu hồi (thường do thiếu SpawnGroup/UnitOverrides). Gửi log để chỉnh.
