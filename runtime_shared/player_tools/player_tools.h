#pragma once
#include "core/version.h"
#if VERSION_MAJOR >= 4
#include "core/object/ref_counted.h"
#include "core/object/class_db.h"
#define PlayerToolsBase RefCounted
#else
#include "core/reference.h"
#include "core/class_db.h"
#define PlayerToolsBase Reference
#endif
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include <set>

// Built into both engines. Only JSON crosses the native adapter boundary.
// All requests run synchronously on the engine/UI main thread.
class PlayerTools : public PlayerToolsBase {
    GDCLASS(PlayerTools, PlayerToolsBase);
    struct Change { Dictionary target; Variant before; Variant after; };
    Vector<Change> history;
    Array frozen;
    Array number_candidates;
    bool numeric_only = false;
    bool boolean_only = false;
    bool string_only = false;
    String candidate_kind = "number";
    String candidate_filter;
    String candidate_scope;
    bool search_started = false;
    bool candidate_truncated = false;
    int search_steps = 0;
    Array search_history;
    Array activity_baseline;
    bool activity_ready = false;
    bool activity_truncated = false;
    int max_rows = 150;
    bool search_busy = false;
    bool search_discovery = false;
    bool working_truncated = false;
    int working_index = 0;
    int working_examined = 0;
    int result_page = 0;
    String working_kind, working_filter, working_scope, working_expected, working_comparison;
    Array discovery_tasks, working_candidates;
    std::set<uint64_t> discovery_seen;
    int virtual_pad = -1;
    int original_fps = -1;
    bool owns_pause = false;
    bool previous_pause = false;
    uint64_t paused_tree = 0;
    Array rows;
    String filter;
    int visited = 0;
    int examined = 0;
    bool truncated = false;
    std::set<uint64_t> seen;

    void scan_object(Object *object, const String &label, int depth);
    void scan_value(Object *owner, const Variant &value, const Array &path, const String &label, int depth);
    bool resolve(const Dictionary &target, Object *&owner, Array &path, Variant &value, String &error);
    bool write(Object *owner, const Array &path, int index, Variant &value, const Variant &replacement);
    Dictionary scan(const String &search, const String &scope = "");
    Dictionary edit(const Dictionary &request, bool record = true);
    Dictionary undo();
    Dictionary pause(bool enabled);
    Dictionary evaluate(const String &code);
    Dictionary input(const Dictionary &command);
    Dictionary options(const Dictionary &command);
    Dictionary find_numbers(const Dictionary &command);
    Dictionary search_results();
    Dictionary continue_search();
    Dictionary inspect_scene(const Dictionary &command);
    Dictionary scene_changes(const Dictionary &command);
    bool is_frozen(const Dictionary &target) const;
    static Dictionary failure(const String &message);
    static SceneTree *tree();

protected:
    static void _bind_methods();

public:
    Dictionary request(const Dictionary &command);
    String transport(const String &json) { return dispatch_json(json); }
    static String dispatch_json(const String &json);
};
