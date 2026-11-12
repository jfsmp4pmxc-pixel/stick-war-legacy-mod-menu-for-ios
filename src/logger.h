// Bộ ghi log nhỏ: vừa NSLog vừa giữ vòng đệm để xem trong menu.
#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void SWLLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// Dùng làm callback cho lớp C++ (il2::set_logger).
void SWLLogC(const char *line);

// Toàn bộ log hiện có, mỗi dòng có giờ.
NSString *SWLLogDump(void);

#ifdef __cplusplus
}
#endif
