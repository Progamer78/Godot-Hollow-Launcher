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
    struct IndexedLocation {
        uint64_t owner = 0;
        Array path;
        String label, lower_label;
    };
    enum IndexedStep { COMPLETE_PATH, ARRAY_ELEMENT, DICTIONARY_ELEMENT, INTEGER_KEY };
    struct IndexedValue {
        int location = 0;
        IndexedStep step = COMPLETE_PATH;
        Variant key, before;
    };
    struct SearchSnapshot {
        Vector<IndexedValue> candidates;
        String filter, kind;
        int steps = 0;
    };
    Vector<IndexedValue> number_candidates, working_candidates;
    Vector<IndexedLocation> candidate_locations, working_locations;
    bool numeric_only = false;
    bool boolean_only = false;
    bool string_only = false;
    String candidate_kind = "number";
    String candidate_filter;
    String candidate_scope;
    bool search_started = false;
    bool candidate_truncated = false;
    int search_steps = 0;
    Vector<SearchSnapshot> search_history;
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
    int working_type_mask = 0;
    bool working_name_spans = false, expected_int_valid = false, expected_float_valid = false;
    int64_t expected_int = 0;
    double expected_float = 0;
    Array discovery_tasks;
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
    bool resolve_path(uint64_t id, const Array &path, Object *&owner, Variant &value, String &error);
    bool indexed_value(const IndexedValue &candidate, const Vector<IndexedLocation> &locations, Variant &value, int *cached_location = nullptr, Variant *cached_value = nullptr);
    String indexed_label(const IndexedValue &candidate, const Vector<IndexedLocation> &locations) const;
    bool indexed_match(const IndexedValue &candidate, const Variant &value) const;
    void collect_indexed(const IndexedValue &candidate, const Variant &value);
    bool write(Object *owner, const Array &path, int index, Variant &value, const Variant &replacement);
    Dictionary scan(const String &search, const String &scope = "");
    Dictionary edit(const Dictionary &request, bool record = true);
    Dictionary undo();
    Dictionary pause(bool enabled);
    Dictionary evaluate(const String &code);
    Dictionary input(const Dictionary &command);
    Dictionary options(const Dictionary &command);
    Dictionary find_numbers(const Dictionary &command);
    Dictionary search_results(bool include_rows = true);
    Dictionary continue_search(bool progress_only = false);
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
