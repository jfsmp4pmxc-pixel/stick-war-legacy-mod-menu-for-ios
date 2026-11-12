// Cầu nối tới logic Stick War: Legacy (chỉ gọi hàm có sẵn của game).
//
// Tên class/method lấy từ dump IL2CPP:
//   GameController.Instance (static) -> FriendlyTeam / EnemyTeam (Team)
//   Team.set_Gold(int)
//   Team.BuildUnit(Type, bool includePopulation, SpawnGroup, UnitOverrides) -> Unit
//   GameController.SetExtraPopulation(int)
//
// Mọi hàm ở đây phải được gọi trên main thread (thread của Unity trên iOS).
#pragma once

namespace game {

enum class Side { Friendly, Enemy };

enum class UnitKind { Miner, Swordwrath, Archidon, Spearton, Magikill, Giant };
constexpr int kUnitKindCount = 6;

// Tên hiển thị tiếng Việt của loại lính.
const char *unit_label(UnitKind kind);

// Chế độ ép vàng cho một phe.
enum class GoldMode { Off, Infinite, Minimum };

// Tìm class/method/field một lần. Trả về true khi mọi thứ bắt buộc đã sẵn sàng.
// Gọi lại nhiều lần được; chỉ thử lại phần còn thiếu.
bool setup();

// IL2CPP API có sẵn không (kể cả khi chưa vào trận).
bool api_ready();

// Đang trong trận (có GameController, hai Team, đã khởi tạo xong) hay chưa.
bool in_match();

// Đặt vàng cho một phe. Trả về false nếu chưa vào trận hoặc game ném ngoại lệ.
bool set_gold(Side side, int amount);

// Áp dụng chế độ vàng (gọi định kỳ).
void apply_gold_mode(Side side, GoldMode mode);

// Triệu hồi `count` lính cho một phe. Trả về số lính đã tạo thành công.
int spawn(Side side, UnitKind kind, int count);

// Nới giới hạn dân số thêm `extra` (GameController.SetExtraPopulation).
bool extend_population(int extra);

// Mô tả trạng thái ngắn gọn cho giao diện.
const char *status_text();

}  // namespace game
