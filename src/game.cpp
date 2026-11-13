#include "game.hpp"

#include <chrono>
#include <cstdint>
#include <cstdio>

#include "il2cpp.hpp"

namespace game {
namespace {

// Namespace gợi ý (theo script.json: StickWar.Game.Entities.Team, StickWar.Game.Mines...).
const char *const kNamespaces[] = {"StickWar.Game.Entities", "StickWar.Game", "StickWar.Game.Levels",
                                   "StickWar", "", nullptr};

// Tên class của từng loại lính trong dump (Archidon trong game là class "Archer").
const char *const kUnitClassNames[kUnitKindCount] = {
    "Miner", "Swordwrath", "Archer", "Spearton", "Magikill", "Giant",
};

const char *const kUnitLabels[kUnitKindCount] = {
    "Thợ mỏ", "Swordwrath", "Archidon", "Spearton", "Magikill", "Giant",
};

constexpr int kInfiniteGold = 999999;
constexpr int kMinimumGold = 9;

struct State {
    bool resolved = false;

    void *controller_class = nullptr;
    void *team_class = nullptr;
    void *unit_classes[kUnitKindCount] = {};

    void *instance_field = nullptr;     // GameController.Instance (static)
    void *friendly_field = nullptr;     // GameController.FriendlyTeam
    void *enemy_field = nullptr;        // GameController.EnemyTeam
    void *initialized_field = nullptr;  // GameController.IsInitialized

    void *set_gold_method = nullptr;        // Team.set_Gold(int)
    void *build_unit_method = nullptr;      // Team.BuildUnit(Type, bool, SpawnGroup, UnitOverrides)
    void *extra_population_method = nullptr;  // GameController.SetExtraPopulation(int)

    // Các đường triệu hồi dự phòng (tuỳ chọn, thiếu thì bỏ qua đường đó).
    void *level_class = nullptr;
    void *overrides_class = nullptr;          // UnitOverrides
    void *level_instance_field = nullptr;     // Level.Instance (static)
    void *level_spawn_method = nullptr;       // Level.SpawnUnit(Team, Type)
    void *queue_unit_method = nullptr;        // Team.QueueUnit(Type)

    // Nút xây lính của HUD (chỉ cho phe ta): Hud.Instance.BuildXxx().
    void *hud_class = nullptr;
    void *hud_instance_field = nullptr;       // Hud.Instance (static)
    void *hud_build_methods[kUnitKindCount] = {};

    // Cờ xây tức thì của màn chơi (Level.Instance).
    void *instant_build_field = nullptr;      // Level.hasInstantBuild
    void *immediate_build_field = nullptr;    // Level.hasReallyImmediateNoWaitBuildTime
};

// Tên method nút xây lính trên HUD, theo thứ tự UnitKind.
const char *const kHudBuildMethods[kUnitKindCount] = {
    "BuildMiner", "BuildSwordwrath", "BuildArcher", "BuildSpearton", "BuildMagikill", "BuildGiant",
};

// Đường gọi để tạo lính; lần thành công đầu tiên được nhớ lại.
enum class Route { Unknown, LevelSpawn, BuildWithOverrides, Queue, HudButton };
constexpr int kRouteCount = 5;
Route g_route = Route::Unknown;
int g_route_failures[kRouteCount] = {};  // để chỉ ghi log lỗi chi tiết vài lần đầu

const char *route_name(Route route) {
    switch (route) {
        case Route::LevelSpawn: return "Level.SpawnUnit";
        case Route::BuildWithOverrides: return "Team.BuildUnit(+UnitOverrides)";
        case Route::Queue: return "Team.QueueUnit";
        case Route::HudButton: return "Hud.BuildXxx";
        default: return "?";
    }
}

State g;
char g_status[96] = "chưa khởi tạo";

bool g_verbose = true;  // false khi đang thử lại nhiều lần, tránh tràn log

void say(const char *text) {
    if (g_verbose) il2::log(text);
}

void say_missing(const char *what) {
    char buf[160];
    std::snprintf(buf, sizeof(buf), "không tìm thấy %s", what);
    say(buf);
}

void set_status(const char *text) { std::snprintf(g_status, sizeof(g_status), "%s", text); }

void *controller() {
    void *instance = nullptr;
    if (!il2::static_get(g.instance_field, &instance)) return nullptr;
    return instance;
}

void *team_of(Side side) {
    void *ctrl = controller();
    if (!ctrl) return nullptr;
    void *team = nullptr;
    void *field = (side == Side::Friendly) ? g.friendly_field : g.enemy_field;
    if (!il2::field_get(ctrl, field, &team)) return nullptr;
    return team;
}

}  // namespace

const char *unit_label(UnitKind kind) { return kUnitLabels[static_cast<int>(kind)]; }

bool api_ready() { return il2::available(); }

bool setup() {
    if (g.resolved) return true;

    // Menu gọi hàm này định kỳ: chỉ thử lại mỗi 2 giây và chỉ ghi lỗi vài lần đầu.
    using Clock = std::chrono::steady_clock;
    static Clock::time_point last_attempt;
    static bool attempted = false;
    static int attempts = 0;
    const Clock::time_point now = Clock::now();
    if (attempted && now - last_attempt < std::chrono::seconds(2)) return false;
    attempted = true;
    last_attempt = now;
    g_verbose = (++attempts <= 3);

    if (!il2::init()) {
        set_status("thiếu IL2CPP API");
        return false;
    }

    if (!g.controller_class) g.controller_class = il2::find_class("GameController", kNamespaces);
    if (!g.team_class) g.team_class = il2::find_class("Team", kNamespaces);
    if (!g.controller_class || !g.team_class) {
        if (!g.controller_class) say_missing("class GameController");
        if (!g.team_class) say_missing("class Team");
        set_status("chưa thấy class của game");
        return false;
    }

    if (!g.instance_field) g.instance_field = il2::find_field(g.controller_class, "Instance");
    if (!g.friendly_field) g.friendly_field = il2::find_field(g.controller_class, "FriendlyTeam");
    if (!g.enemy_field) g.enemy_field = il2::find_field(g.controller_class, "EnemyTeam");
    if (!g.initialized_field) g.initialized_field = il2::find_field(g.controller_class, "IsInitialized");

    if (!g.set_gold_method) g.set_gold_method = il2::find_method(g.team_class, "set_Gold", 1);
    if (!g.build_unit_method) g.build_unit_method = il2::find_method(g.team_class, "BuildUnit", 4);
    if (!g.extra_population_method) {
        g.extra_population_method = il2::find_method(g.controller_class, "SetExtraPopulation", 1);
    }

    // Đường dự phòng: thiếu cái nào chỉ làm mất đường tương ứng.
    if (!g.level_class) g.level_class = il2::find_class("Level", kNamespaces);
    if (g.level_class) {
        if (!g.level_instance_field) g.level_instance_field = il2::find_field(g.level_class, "Instance");
        if (!g.level_spawn_method) g.level_spawn_method = il2::find_method(g.level_class, "SpawnUnit", 2);
    }
    if (!g.overrides_class) g.overrides_class = il2::find_class("UnitOverrides", kNamespaces);
    if (!g.queue_unit_method) g.queue_unit_method = il2::find_method(g.team_class, "QueueUnit", 1);

    if (g.level_class) {
        if (!g.instant_build_field) g.instant_build_field = il2::find_field(g.level_class, "hasInstantBuild");
        if (!g.immediate_build_field) {
            g.immediate_build_field = il2::find_field(g.level_class, "hasReallyImmediateNoWaitBuildTime");
        }
    }

    if (!g.hud_class) g.hud_class = il2::find_class("Hud", kNamespaces);
    if (g.hud_class) {
        if (!g.hud_instance_field) g.hud_instance_field = il2::find_field(g.hud_class, "Instance");
        for (int i = 0; i < kUnitKindCount; i++) {
            if (!g.hud_build_methods[i]) {
                g.hud_build_methods[i] = il2::find_method(g.hud_class, kHudBuildMethods[i], 0);
            }
        }
    }

    for (int i = 0; i < kUnitKindCount; i++) {
        if (!g.unit_classes[i]) g.unit_classes[i] = il2::find_class(kUnitClassNames[i], kNamespaces);
        if (!g.unit_classes[i]) say_missing(kUnitClassNames[i]);
    }

    bool core_ok = g.instance_field && g.friendly_field && g.enemy_field && g.initialized_field &&
                   g.set_gold_method && g.build_unit_method;
    if (!core_ok) {
        if (!g.instance_field) say_missing("GameController.Instance");
        if (!g.friendly_field) say_missing("GameController.FriendlyTeam");
        if (!g.enemy_field) say_missing("GameController.EnemyTeam");
        if (!g.initialized_field) say_missing("GameController.IsInitialized");
        if (!g.set_gold_method) say_missing("Team.set_Gold");
        if (!g.build_unit_method) say_missing("Team.BuildUnit");
        set_status("thiếu field/method của game");
        return false;
    }

    g.resolved = true;
    g_verbose = true;
    say("đã tìm đủ class/method của game");
    set_status("sẵn sàng, chưa vào trận");
    return true;
}

bool in_match() {
    if (!g.resolved && !setup()) return false;

    void *ctrl = controller();
    if (!ctrl) {
        set_status("sẵn sàng, chưa vào trận");
        return false;
    }

    uint8_t initialized = 0;
    il2::field_get(ctrl, g.initialized_field, &initialized);
    if (!initialized || !team_of(Side::Friendly) || !team_of(Side::Enemy)) {
        set_status("đang tải trận...");
        return false;
    }

    set_status("đang trong trận");
    return true;
}

bool set_gold(Side side, int amount) {
    if (!in_match()) return false;
    void *team = team_of(side);
    if (!team) return false;

    int32_t value = amount;
    void *params[1] = {&value};
    bool threw = false;
    il2::invoke(g.set_gold_method, team, params, &threw);
    if (threw) say("Team.set_Gold ném ngoại lệ");
    return !threw;
}

void apply_gold_mode(Side side, GoldMode mode) {
    switch (mode) {
        case GoldMode::Infinite:
            set_gold(side, kInfiniteGold);
            break;
        case GoldMode::Minimum:
            set_gold(side, kMinimumGold);
            break;
        case GoldMode::Off:
            break;
    }
}

// Bật cờ xây tức thì của màn chơi để lính vào hàng chờ ra ngay (chỉ đường Queue/HUD cần).
static void enable_instant_build() {
    if (!g.level_instance_field) return;
    void *level = nullptr;
    if (!il2::static_get(g.level_instance_field, &level) || !level) return;
    uint8_t on = 1;
    static bool logged = false;
    bool any = false;
    if (g.instant_build_field) any |= il2::field_set(level, g.instant_build_field, &on);
    if (g.immediate_build_field) any |= il2::field_set(level, g.immediate_build_field, &on);
    if (any && !logged) {
        logged = true;
        il2::log("đã bật xây lính tức thì cho màn chơi (Level.hasInstantBuild)");
    }
}

// Ghi log lỗi của một đường: chi tiết vài lần đầu, sau đó im để khỏi tràn log.
static void log_route_failure(Route route, const char *detail) {
    int &count = g_route_failures[static_cast<int>(route)];
    if (count++ >= 2) return;
    char buf[1400];
    std::snprintf(buf, sizeof(buf), "%s: %s", route_name(route), detail);
    il2::log(buf);
}

// Thử tạo một lính theo `route`. Trả về true nếu game trả về lính / nhận lệnh.
static bool try_route(Route route, void *team, void *type_object, UnitKind kind, Side side) {
    char error[1200];
    bool threw = false;
    bool ok = false;

    switch (route) {
        case Route::LevelSpawn: {
            // Level.Instance.SpawnUnit(Team team, Type type) -> Unit
            if (!g.level_instance_field || !g.level_spawn_method) return false;
            void *level = nullptr;
            if (!il2::static_get(g.level_instance_field, &level) || !level) return false;
            void *params[2] = {team, type_object};
            void *unit = il2::invoke(g.level_spawn_method, level, params, &threw, error, sizeof(error));
            ok = !threw && unit != nullptr;
            break;
        }
        case Route::BuildWithOverrides: {
            // Team.BuildUnit(Type, bool includePopulation, SpawnGroup, UnitOverrides) -> Unit
            // UnitOverrides phải qua constructor để có giá trị mặc định (hệ số = 1).
            void *overrides = nullptr;
            if (g.overrides_class) {
                overrides = il2::new_object(g.overrides_class);
                void *ctor = il2::find_method(g.overrides_class, ".ctor", 0);
                if (overrides && ctor) {
                    il2::invoke(ctor, overrides, nullptr, &threw, error, sizeof(error));
                    if (threw) overrides = nullptr;
                }
            }
            if (!overrides) return false;
            uint8_t include_population = 1;
            void *params[4] = {type_object, &include_population, nullptr, overrides};
            void *unit = il2::invoke(g.build_unit_method, team, params, &threw, error, sizeof(error));
            ok = !threw && unit != nullptr;
            break;
        }
        case Route::Queue: {
            // Team.QueueUnit(Type) -> bool: đưa lính vào hàng chờ xây như bấm nút trên HUD.
            if (!g.queue_unit_method) return false;
            enable_instant_build();
            void *params[1] = {type_object};
            void *result = il2::invoke(g.queue_unit_method, team, params, &threw, error, sizeof(error));
            ok = !threw && il2::unbox_bool(result, true);
            if (!threw && !ok) {
                log_route_failure(route, "trả về false (thiếu vàng, hết dân số hoặc hàng chờ đầy?)");
            }
            break;
        }
        case Route::HudButton: {
            // Hud.Instance.BuildXxx(): chính hàm của nút xây lính; chỉ tác động phe ta.
            if (side != Side::Friendly) return false;
            void *method = g.hud_build_methods[static_cast<int>(kind)];
            if (!g.hud_instance_field || !method) return false;
            void *hud = nullptr;
            if (!il2::static_get(g.hud_instance_field, &hud) || !hud) return false;
            enable_instant_build();
            il2::invoke(method, hud, nullptr, &threw, error, sizeof(error));
            ok = !threw;  // hàm trả void: không biết có đủ vàng/dân số hay không
            break;
        }
        default:
            return false;
    }

    if (threw) log_route_failure(route, error);
    return ok;
}

static bool spawn_one(void *team, void *type_object, UnitKind kind, Side side) {
    // Đường đã từng thành công thì dùng lại trước.
    if (g_route != Route::Unknown) {
        if (try_route(g_route, team, type_object, kind, side)) return true;
        g_route = Route::Unknown;
    }

    static const Route kOrder[] = {Route::LevelSpawn, Route::BuildWithOverrides, Route::Queue,
                                   Route::HudButton};
    for (Route route : kOrder) {
        if (try_route(route, team, type_object, kind, side)) {
            g_route = route;
            char buf[96];
            std::snprintf(buf, sizeof(buf), "triệu hồi chạy được qua %s", route_name(route));
            il2::log(buf);
            return true;
        }
    }
    il2::log("mọi đường triệu hồi đều thất bại");
    return false;
}

int spawn(Side side, UnitKind kind, int count) {
    if (count <= 0 || !in_match()) return 0;

    const int index = static_cast<int>(kind);
    void *klass = g.unit_classes[index];
    if (!klass) {
        klass = il2::find_class(kUnitClassNames[index], kNamespaces);
        g.unit_classes[index] = klass;
    }
    if (!klass) {
        say_missing(kUnitClassNames[index]);
        return 0;
    }

    void *team = team_of(side);
    if (!team) return 0;

    int created = 0;
    for (int i = 0; i < count; i++) {
        void *type_object = il2::type_object(klass);
        if (!type_object) {
            say("không lấy được System.Type của lính");
            break;
        }
        if (!spawn_one(team, type_object, kind, side)) break;  // mọi đường đều lỗi: dừng, tránh spam
        created++;
    }

    char buf[96];
    std::snprintf(buf, sizeof(buf), "triệu hồi %s x%d (%s): được %d", kUnitLabels[index], count,
                  side == Side::Friendly ? "ta" : "địch", created);
    say(buf);
    return created;
}

bool extend_population(int extra) {
    if (!in_match() || !g.extra_population_method) return false;
    void *ctrl = controller();
    if (!ctrl) return false;

    int32_t value = extra;
    void *params[1] = {&value};
    bool threw = false;
    il2::invoke(g.extra_population_method, ctrl, params, &threw);
    if (threw) say("GameController.SetExtraPopulation ném ngoại lệ");
    return !threw;
}

const char *status_text() { return g_status; }

}  // namespace game
