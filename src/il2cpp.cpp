#include "il2cpp.hpp"

#include <dlfcn.h>

#include <cstdio>
#include <cstring>

namespace il2 {
namespace {

using domain_get_fn = void *(*)();
using domain_get_assemblies_fn = void **(*)(void *domain, size_t *count);
using assembly_get_image_fn = void *(*)(void *assembly);
using image_get_name_fn = const char *(*)(void *image);
using image_get_class_count_fn = size_t (*)(void *image);
using image_get_class_fn = void *(*)(void *image, size_t index);
using class_from_name_fn = void *(*)(void *image, const char *ns, const char *name);
using class_get_name_fn = const char *(*)(void *klass);
using class_get_namespace_fn = const char *(*)(void *klass);
using class_get_method_fn = void *(*)(void *klass, const char *name, int argc);
using class_get_field_fn = void *(*)(void *klass, const char *name);
using class_get_type_fn = void *(*)(void *klass);
using type_get_object_fn = void *(*)(void *type);
using field_static_get_fn = void (*)(void *field, void *value);
using field_get_fn = void (*)(void *object, void *field, void *value);
using runtime_invoke_fn = void *(*)(void *method, void *object, void **params, void **exc);

struct Api {
    domain_get_fn domain_get = nullptr;
    domain_get_assemblies_fn domain_get_assemblies = nullptr;
    assembly_get_image_fn assembly_get_image = nullptr;
    image_get_name_fn image_get_name = nullptr;
    image_get_class_count_fn image_get_class_count = nullptr;
    image_get_class_fn image_get_class = nullptr;
    class_from_name_fn class_from_name = nullptr;
    class_get_name_fn class_get_name = nullptr;
    class_get_namespace_fn class_get_namespace = nullptr;
    class_get_method_fn class_get_method = nullptr;
    class_get_field_fn class_get_field = nullptr;
    class_get_type_fn class_get_type = nullptr;
    type_get_object_fn type_get_object = nullptr;
    field_static_get_fn field_static_get = nullptr;
    field_get_fn field_get = nullptr;
    runtime_invoke_fn runtime_invoke = nullptr;
};

Api g_api;
bool g_ok = false;
LogFn g_log = nullptr;

void log_line(const char *fmt, const char *a = "") {
    if (!g_log) return;
    char buf[256];
    std::snprintf(buf, sizeof(buf), fmt, a);
    g_log(buf);
}

bool g_quiet = false;  // true từ lần init thứ hai để không lặp lại log lỗi

template <typename Fn>
bool resolve(Fn &slot, const char *symbol) {
    slot = reinterpret_cast<Fn>(dlsym(RTLD_DEFAULT, symbol));
    if (!slot && !g_quiet) log_line("thiếu symbol: %s", symbol);
    return slot != nullptr;
}

// Duyệt mọi assembly, gọi `visit(image)`; dừng khi visit trả về true.
template <typename Visit>
bool for_each_image(Visit visit) {
    void *domain = g_api.domain_get();
    if (!domain) return false;
    size_t count = 0;
    void **assemblies = g_api.domain_get_assemblies(domain, &count);
    if (!assemblies) return false;
    for (size_t i = 0; i < count; i++) {
        void *image = g_api.assembly_get_image(assemblies[i]);
        if (image && visit(image)) return true;
    }
    return false;
}

}  // namespace

void set_logger(LogFn fn) { g_log = fn; }

void log(const char *line) {
    if (g_log && line) g_log(line);
}

bool available() { return g_ok; }

bool init() {
    if (g_ok) return true;

    bool ok = true;
    ok &= resolve(g_api.domain_get, "il2cpp_domain_get");
    ok &= resolve(g_api.domain_get_assemblies, "il2cpp_domain_get_assemblies");
    ok &= resolve(g_api.assembly_get_image, "il2cpp_assembly_get_image");
    ok &= resolve(g_api.image_get_name, "il2cpp_image_get_name");
    ok &= resolve(g_api.image_get_class_count, "il2cpp_image_get_class_count");
    ok &= resolve(g_api.image_get_class, "il2cpp_image_get_class");
    ok &= resolve(g_api.class_from_name, "il2cpp_class_from_name");
    ok &= resolve(g_api.class_get_name, "il2cpp_class_get_name");
    ok &= resolve(g_api.class_get_namespace, "il2cpp_class_get_namespace");
    ok &= resolve(g_api.class_get_method, "il2cpp_class_get_method_from_name");
    ok &= resolve(g_api.class_get_field, "il2cpp_class_get_field_from_name");
    ok &= resolve(g_api.class_get_type, "il2cpp_class_get_type");
    ok &= resolve(g_api.type_get_object, "il2cpp_type_get_object");
    ok &= resolve(g_api.field_static_get, "il2cpp_field_static_get_value");
    ok &= resolve(g_api.field_get, "il2cpp_field_get_value");
    ok &= resolve(g_api.runtime_invoke, "il2cpp_runtime_invoke");

    g_ok = ok;
    if (ok) log_line("IL2CPP API sẵn sàng");
    g_quiet = true;
    return ok;
}

void *find_class(const char *name, const char *const *ns_hints) {
    if (!g_ok || !name) return nullptr;

    // 1. Thử các namespace gợi ý trên từng assembly.
    void *found = nullptr;
    if (ns_hints) {
        for_each_image([&](void *image) {
            for (const char *const *ns = ns_hints; *ns; ns++) {
                found = g_api.class_from_name(image, *ns, name);
                if (found) return true;
            }
            return false;
        });
        if (found) return found;
    }

    // 2. Quét toàn bộ class theo tên, ưu tiên namespace "StickWar...".
    void *fallback = nullptr;
    for_each_image([&](void *image) {
        size_t count = g_api.image_get_class_count(image);
        for (size_t i = 0; i < count; i++) {
            void *klass = g_api.image_get_class(image, i);
            if (!klass) continue;
            const char *class_name = g_api.class_get_name(klass);
            if (!class_name || std::strcmp(class_name, name) != 0) continue;
            const char *ns = g_api.class_get_namespace(klass);
            if (ns && std::strncmp(ns, "StickWar", 8) == 0) {
                found = klass;
                return true;
            }
            if (!fallback) fallback = klass;
        }
        return false;
    });
    return found ? found : fallback;
}

void *find_method(void *klass, const char *name, int arg_count) {
    if (!g_ok || !klass) return nullptr;
    return g_api.class_get_method(klass, name, arg_count);
}

void *find_field(void *klass, const char *name) {
    if (!g_ok || !klass) return nullptr;
    return g_api.class_get_field(klass, name);
}

void *type_object(void *klass) {
    if (!g_ok || !klass) return nullptr;
    void *type = g_api.class_get_type(klass);
    return type ? g_api.type_get_object(type) : nullptr;
}

bool static_get(void *field, void *out) {
    if (!g_ok || !field || !out) return false;
    g_api.field_static_get(field, out);
    return true;
}

bool field_get(void *object, void *field, void *out) {
    if (!g_ok || !object || !field || !out) return false;
    g_api.field_get(object, field, out);
    return true;
}

void *invoke(void *method, void *object, void **params, bool *threw) {
    if (threw) *threw = false;
    if (!g_ok || !method) return nullptr;
    void *exception = nullptr;
    void *result = g_api.runtime_invoke(method, object, params, &exception);
    if (exception) {
        if (threw) *threw = true;
        return nullptr;
    }
    return result;
}

}  // namespace il2
