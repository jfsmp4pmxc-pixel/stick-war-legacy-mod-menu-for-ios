// Lớp mỏng bọc IL2CPP C API của Unity.
//
// Mọi hàm được tìm bằng dlsym lúc chạy, nên không cần RVA cứng và không
// phụ thuộc phiên bản game. Mod chỉ GỌI hàm của game (không vá mã, không hook).
#pragma once

#include <cstddef>
#include <cstdint>

namespace il2 {

// Callback ghi log do lớp giao diện cung cấp (có thể là nullptr).
using LogFn = void (*)(const char *line);
void set_logger(LogFn fn);
void log(const char *line);  // ghi một dòng qua logger đã đăng ký (nếu có)

// Tìm các hàm il2cpp_* qua dlsym. Trả về true nếu đủ hàm bắt buộc.
// An toàn khi gọi nhiều lần; chỉ thử lại nếu lần trước thất bại.
bool init();
bool available();

// Tìm class theo tên. `ns_hints` là mảng kết thúc bằng nullptr, ví dụ
// { "StickWar.Game.Entities", "StickWar.Game", nullptr }.
// Nếu không khớp namespace nào thì quét toàn bộ assembly theo tên class
// (ưu tiên namespace bắt đầu bằng "StickWar").
void *find_class(const char *name, const char *const *ns_hints);

void *find_method(void *klass, const char *name, int arg_count);
void *find_field(void *klass, const char *name);

// Đối tượng System.Type của một class (dùng làm tham số `Type`).
void *type_object(void *klass);

// Đọc field static / field của instance. `out` phải đủ chỗ cho kiểu field.
bool static_get(void *field, void *out);
bool field_get(void *object, void *field, void *out);

// Gọi method qua il2cpp_runtime_invoke (bắt được ngoại lệ managed).
// `params` theo quy ước IL2CPP: kiểu giá trị truyền con trỏ tới giá trị,
// kiểu tham chiếu truyền chính con trỏ đối tượng. Trả về giá trị trả về
// (đối tượng, hoặc nullptr với hàm void). `threw` (nếu khác null) được đặt
// true khi game ném ngoại lệ; khi đó `error` (nếu có) nhận "TênClass: thông điệp".
void *invoke(void *method, void *object, void **params, bool *threw,
             char *error = nullptr, size_t error_len = 0);

// Ghi field của instance (kiểu giá trị truyền con trỏ tới giá trị).
bool field_set(void *object, void *field, void *value);

// Tạo đối tượng managed mới (chưa chạy constructor; gọi ".ctor" bằng invoke).
void *new_object(void *klass);

// Đọc giá trị bool từ đối tượng đã box (kết quả trả về của method trả bool).
bool unbox_bool(void *boxed, bool fallback);

}  // namespace il2
