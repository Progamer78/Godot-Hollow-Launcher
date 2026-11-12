#include "player_tools.h"
#include "core/math/expression.h"
#include "core/io/json.h"
#include "core/os/os.h"
#include "main/performance.h"
#include "scene/gui/control.h"
#include <cerrno>
#include <cstdlib>
#if VERSION_MAJOR >= 4
#include "core/object/script_language.h"
#include "scene/main/window.h"
#include "core/input/input.h"
#include "core/config/engine.h"
#else
#include "core/script_language.h"
#include "scene/main/viewport.h"
#include "core/os/input.h"
#include "core/os/keyboard.h"
#include "core/engine.h"
#endif

static uint64_t parse_id(const String &text) {
    uint64_t result = 0;
    if (!text.length() || text.length() > 20) return 0;
    for (int i = 0; i < text.length(); i++) {
        if (text[i] < '0' || text[i] > '9') return 0;
        uint64_t digit = text[i] - '0';
        if (result > (UINT64_MAX - digit) / 10) return 0;
        result = result * 10 + digit;
    }
    return result;
}
static int64_t parse_integer(const String &text, bool &valid) {
    const CharString utf8 = text.strip_edges().utf8();
    const char *start = utf8.get_data(); char *end = nullptr;
    errno = 0;
    long long number = std::strtoll(start, &end, 10);
    valid = errno != ERANGE && end != start && end && *end == 0;
    return int64_t(number);
}

static Object *live_object(uint64_t id) {
#if VERSION_MAJOR >= 4
    return ObjectDB::get_instance(ObjectID(id));
#else
    return ObjectDB::get_instance(id);
#endif
}
static String object_id(Object *object) { return String::num_uint64(uint64_t(object->get_instance_id())); }
static bool string_key(const Variant &key) {
    return key.get_type() == Variant::STRING
#if VERSION_MAJOR >= 4
        || key.get_type() == Variant::STRING_NAME
#endif
        ;
}
static String scalar_type(const Variant &value) {
    switch (value.get_type()) {
        case Variant::BOOL: return "bool";
        case Variant::INT: return "int";
#if VERSION_MAJOR >= 4
        case Variant::FLOAT: return "float";
#else
        case Variant::REAL: return "float";
#endif
        case Variant::STRING: return "string";
        default: return "";
    }
}
static bool is_empty_text(const String &text) { return text.length() == 0; }

SceneTree *PlayerTools::tree() {
    return OS::get_singleton() ? Object::cast_to<SceneTree>(OS::get_singleton()->get_main_loop()) : nullptr;
}
Dictionary PlayerTools::failure(const String &message) {
    Dictionary result; result["ok"] = false; result["message"] = message; return result;
}
void PlayerTools::_bind_methods() {
    ClassDB::bind_method(D_METHOD("request", "command"), &PlayerTools::request);
    ClassDB::bind_method(D_METHOD("transport", "json"), &PlayerTools::transport);
}

void PlayerTools::scan_value(Object *owner, const Variant &value, const Array &path, const String &label, int depth) {
    if (++examined > 12000 || rows.size() >= max_rows) { truncated = true; return; }
    String type = scalar_type(value);
    if (!is_empty_text(type)) {
        if (numeric_only && type != "int" && type != "float") return;
        if (boolean_only && type != "bool") return;
        if (string_only && type != "string") return;
        if (!is_empty_text(filter) && label.to_lower().find(filter) < 0) return;
        // Avoid flooding the editor with narrative text or save blobs.
        String display = type == "bool" ? (bool(value) ? "true" : "false") : String(value);
        if (display.length() > 512) return;
        Dictionary row; row["object"] = object_id(owner); row["path"] = path;
        row["label"] = label; row["type"] = type; row["value"] = display; row["frozen"] = is_frozen(row);
        rows.push_back(row); return;
    }
    if (depth >= 5) return;
    if (value.get_type() == Variant::DICTIONARY) {
        Dictionary dictionary = value;
        Array keys;
        const Variant *key_pointer = nullptr;
        while ((key_pointer = dictionary.next(key_pointer)) && keys.size() < 256) keys.push_back(*key_pointer);
        if (dictionary.size() > 256) truncated = true;
        for (int i = 0; i < MIN(keys.size(), 256); i++) {
            Variant key = keys[i];
            if (!dictionary.has(key)) continue;
            if (!string_key(key) && key.get_type() != Variant::INT) continue;
            Array next = path.duplicate(); Dictionary step;
            step["kind"] = string_key(key) ? "dictionary" : "dictionary_int";
            step["name"] = String(key); // Preserve 64-bit integer keys across JSON.
            next.push_back(step);
            scan_value(owner, dictionary[key], next, label + "." + String(key), depth + 1);
            if (examined > 12000 || rows.size() >= max_rows) break;
        }
    } else if (value.get_type() == Variant::ARRAY) {
        Array array = value;
        if (array.size() > 128) truncated = true;
        for (int i = 0; i < MIN(array.size(), 128); i++) {
            Array next = path.duplicate(); Dictionary step; step["kind"] = "array"; step["index"] = i; next.push_back(step);
            scan_value(owner, array[i], next, label + "[" + itos(i) + "]", depth + 1);
            if (examined > 12000 || rows.size() >= max_rows) break;
        }
    } else if (value.get_type() == Variant::OBJECT) {
#if VERSION_MAJOR >= 4
        Object *object = value.get_validated_object();
#else
        Object *object = live_object(value.get_object_instance_id());
#endif
        if (object) scan_object(object, label, depth + 1);
    }
}

void PlayerTools::scan_object(Object *object, const String &label, int depth) {
    if (!object || depth > 5 || visited >= 600 || rows.size() >= max_rows || examined > 12000) { truncated = true; return; }
    if (!seen.insert(uint64_t(object->get_instance_id())).second) return;
    visited++;
    ScriptInstance *script = object->get_script_instance();
    if (script) {
        uint64_t id = uint64_t(object->get_instance_id());
        List<PropertyInfo> properties;
        script->get_property_list(&properties);
        for (int pass = 0; pass < (is_empty_text(filter) ? 1 : 2); pass++) {
        for (List<PropertyInfo>::Element *item = properties.front(); item; item = item->next()) {
            const PropertyInfo &info = item->get();
            if (info.usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP)) continue;
            if (!is_empty_text(filter)) {
                const bool matches = String(info.name).to_lower().find(filter) >= 0;
                if (matches != (pass == 0)) continue;
            }
            // A script getter can delete its owner. Resolve the ID again before
            // each access, and stop when it is no longer alive.
            Object *current = live_object(id);
            if (!current) break;
            bool valid = false; Variant value = current->get(info.name, &valid);
            if (!valid || !live_object(id)) continue;
            Array path; Dictionary step; step["kind"] = "property"; step["name"] = String(info.name); path.push_back(step);
            scan_value(current, value, path, label + "." + String(info.name), depth);
            if (examined > 12000 || rows.size() >= max_rows) break;
        }
        if (!live_object(id) || examined > 12000 || rows.size() >= max_rows) break;
        }
    }
}

Dictionary PlayerTools::scan(const String &search, const String &scope) {
    rows.clear(); seen.clear(); visited = 0; examined = 0; truncated = false; filter = search.substr(0, 100).to_lower();
    SceneTree *scene = tree();
    if (!scene || !scene->get_root()) return failure("The game scene is not ready yet.");
    // Breadth first: autoloads and their game-state dictionaries are searched
    // before deep decorative scene hierarchies. Budget remains bounded.
    Node *start = scene->get_root();
    if (!is_empty_text(scope)) {
        start = Object::cast_to<Node>(live_object(parse_id(scope)));
        if (!start || !start->is_inside_tree()) return failure("This scene object is no longer available. Choose another object or clear the scope.");
    }
    Array pending; pending.push_back(object_id(start));
    int cursor = 0;
    while (cursor < pending.size() && cursor < 600 && rows.size() < max_rows && examined <= 12000) {
        Object *object = live_object(parse_id(pending[cursor++]));
        Node *node = Object::cast_to<Node>(object);
        if (!node) continue;
        String label(node->get_path());
        const uint64_t id = uint64_t(node->get_instance_id());
        scan_object(node, label, 0);
        node = Object::cast_to<Node>(live_object(id));
        if (!node) continue;
        for (int i = 0; i < node->get_child_count() && pending.size() < 600; i++) pending.push_back(object_id(node->get_child(i)));
        if (pending.size() >= 600) truncated = true;
    }
    if (cursor < pending.size()) truncated = true;
    Dictionary result; result["ok"] = true; result["rows"] = rows; result["truncated"] = truncated;
    result["visited"] = visited; result["undoCount"] = history.size();
    return result;
}

bool PlayerTools::resolve(const Dictionary &target, Object *&owner, Array &path, Variant &value, String &error) {
    if (!target.has("object") || !target.has("path") || target["path"].get_type() != Variant::ARRAY) { error = "Invalid stat reference."; return false; }
    String id = target["object"]; path = target["path"];
    if (!resolve_path(parse_id(id), path, owner, value, error)) return false;
    if (target.has("type") && String(target["type"]) != scalar_type(value)) {
        error = "This stat's type changed. Refresh the list before editing it."; return false;
    }
    return true;
}

bool PlayerTools::resolve_path(uint64_t id, const Array &path, Object *&owner, Variant &value, String &error) {
    owner = live_object(id);
    if (!owner || path.size() < 1 || path.size() > 8) { error = "This stat's owner no longer exists. Refresh the list."; return false; }
    value = owner;
    for (int i = 0; i < path.size(); i++) {
        if (path[i].get_type() != Variant::DICTIONARY) { error = "Invalid stat path."; return false; }
        Dictionary step = path[i]; String kind = step.get("kind", "");
        if (kind == "property" && i == 0) {
            bool valid = false; value = owner->get(String(step.get("name", "")), &valid);
            if (!valid || !live_object(id)) { error = "The stat is no longer available."; return false; }
        } else if ((kind == "dictionary" || kind == "dictionary_int") && value.get_type() == Variant::DICTIONARY) {
            Dictionary dictionary = value; Variant key = step.get("name", "");
            if (kind == "dictionary_int") {
                bool valid = false; key = parse_integer(key, valid);
                if (!valid) { error = "Invalid integer dictionary key."; return false; }
            }
            if (!dictionary.has(key)) { error = "This dictionary entry was removed. Refresh the list."; return false; }
            value = dictionary[key];
        } else if (kind == "array" && value.get_type() == Variant::ARRAY) {
            Array array = value; int index = step.get("index", -1);
            if (index < 0 || index >= array.size()) { error = "The array changed. Refresh the list."; return false; }
            value = array[index];
        } else { error = "The stat structure changed. Refresh the list."; return false; }
    }
    return true;
}

bool PlayerTools::write(Object *owner, const Array &path, int index, Variant &value, const Variant &replacement) {
    if (index == path.size()) { value = replacement; return true; }
    Dictionary step = path[index]; String kind = step.get("kind", "");
    if (kind == "property" && index == 0) {
        StringName name = String(step["name"]); bool valid = false; const uint64_t id = uint64_t(owner->get_instance_id());
        Variant child = owner->get(name, &valid);
        if (!valid || !live_object(id) || !write(owner, path, index + 1, child, replacement)) return false;
        owner = live_object(id); if (!owner) return false;
        owner->set(name, child, &valid); return valid;
    }
    if (value.get_type() == Variant::DICTIONARY && (kind == "dictionary" || kind == "dictionary_int")) {
        // Copy the container before editing, so a failed property setter does
        // not partially mutate the original shared dictionary or array.
        Dictionary dictionary = Dictionary(value).duplicate(); Variant key = step["name"];
        if (kind == "dictionary_int") { bool valid = false; key = parse_integer(key, valid); if (!valid) return false; }
        if (!dictionary.has(key)) return false;
        Variant child = dictionary[key];
        if (!write(owner, path, index + 1, child, replacement)) return false;
        dictionary[key] = child; value = dictionary; return true;
    }
    if (value.get_type() == Variant::ARRAY && kind == "array") {
        Array array = Array(value).duplicate(); int position = step["index"];
        if (position < 0 || position >= array.size()) return false;
        Variant child = array[position];
        if (!write(owner, path, index + 1, child, replacement)) return false;
        array[position] = child; value = array; return true;
    }
    return false;
}

Dictionary PlayerTools::edit(const Dictionary &command, bool record) {
    if (!command.has("target") || command["target"].get_type() != Variant::DICTIONARY) return failure("Choose a stat first.");
    Dictionary target = command["target"]; Object *owner = nullptr; Array path; Variant current; String error;
    if (!resolve(target, owner, path, current, error)) return failure(error);
    String text = command.get("value", ""); String type = scalar_type(current); Variant replacement;
    if (type == "int") {
        bool valid = false; int64_t number = parse_integer(text, valid);
        if (!valid) return failure("Enter a whole number within the signed 64-bit range.");
        replacement = number;
    } else if (type == "float") {
        if (!text.is_valid_float()) return failure("Enter a finite decimal number.");
#if VERSION_MAJOR >= 4
        double number = text.to_float();
#else
        double number = text.to_double();
#endif
        if (Math::is_nan(number) || Math::is_inf(number)) return failure("Enter a finite decimal number."); replacement = number;
    } else if (type == "bool") {
        if (text != "true" && text != "false") return failure("Choose true or false.");
        replacement = text == "true";
    } else if (type == "string") {
        if (text.length() > 512) return failure("Text edits are limited to 512 characters."); replacement = text;
    } else return failure("Only numbers, booleans and short text can be edited here.");
    Variant root;
    if (!write(owner, path, 0, root, replacement)) return failure("The game rejected this change.");
    Variant actual; Object *check_owner = nullptr; Array check_path;
    if (!resolve(target, check_owner, check_path, actual, error) || actual != replacement) return failure("The game's setter did not keep that value. Refresh to inspect it.");
    if (record) {
    Change change; change.target = target; change.before = current; change.after = actual;
    if (history.size() >= 20) {
#if VERSION_MAJOR >= 4
        history.remove_at(0);
#else
        history.remove(0);
#endif
    }
    history.push_back(change);
    }
    Dictionary result; result["ok"] = true; result["message"] = "Value updated in the running game."; result["undoCount"] = history.size(); return result;
}

Dictionary PlayerTools::undo() {
    frozen.clear();
    if (!history.size()) return failure("There are no edits to undo in this session.");
    Change change = history[history.size() - 1]; Object *owner = nullptr; Array path; Variant current; String error;
    if (!resolve(change.target, owner, path, current, error)) return failure(error);
    if (current != change.after) return failure("The game changed this value since your edit. Undo would overwrite that progress; refresh and edit it manually instead.");
    Variant root; if (!write(owner, path, 0, root, change.before)) return failure("The game rejected undo.");
    history.resize(history.size() - 1);
    Dictionary result; result["ok"] = true; result["message"] = "Previous value restored."; result["undoCount"] = history.size(); return result;
}

Dictionary PlayerTools::pause(bool enabled) {
    SceneTree *scene = tree(); if (!scene) return failure("The game scene is not ready yet.");
    if (enabled && !owns_pause) { previous_pause = scene->is_paused(); paused_tree = uint64_t(scene->get_instance_id()); owns_pause = true; scene->set_pause(true); }
    if (!enabled && owns_pause) { if (uint64_t(scene->get_instance_id()) == paused_tree) scene->set_pause(previous_pause); owns_pause = false; }
    Dictionary result; result["ok"] = true; return result;
}

Dictionary PlayerTools::evaluate(const String &code) {
    if (!tree() || !tree()->get_root()) return failure("The game scene is not ready yet.");
    if (code.length() < 1 || code.length() > 1024) return failure("Enter an expression up to 1024 characters.");
    Ref<Expression> expression;
#if VERSION_MAJOR >= 4
    expression.instantiate();
#else
    expression.instance();
#endif
    Error error = expression->parse(code);
    if (error != OK) return failure(expression->get_error_text());
    Variant value = expression->execute(Array(), tree()->get_root(), false);
    if (expression->has_execute_failed()) return failure(expression->get_error_text());
    Dictionary result; result["ok"] = true; result["message"] = String(value).substr(0, 4096); return result;
}

static bool same_target(const Dictionary &left, const Dictionary &right) {
    if (left.get("object", Variant()) != right.get("object", Variant())) return false;
    Array left_path = left.get("path", Array()), right_path = right.get("path", Array());
    if (left_path.size() != right_path.size() || left_path.size() == 0) return false;
    // Godot 3 container equality compares identity. A fresh scan constructs new
    // path arrays, so compare each supported step's fields explicitly.
    for (int i = 0; i < left_path.size(); i++) {
        if (left_path[i].get_type() != Variant::DICTIONARY || right_path[i].get_type() != Variant::DICTIONARY) return false;
        Dictionary a = left_path[i], b = right_path[i];
        if (a.get("kind", Variant()) != b.get("kind", Variant()) || a.get("name", Variant()) != b.get("name", Variant()) || a.get("index", Variant()) != b.get("index", Variant())) return false;
    }
    return true;
}

bool PlayerTools::is_frozen(const Dictionary &target) const {
    for (int i = 0; i < frozen.size(); i++) {
        Dictionary entry = frozen[i], prior = entry.get("target", Dictionary());
        if (same_target(prior, target) && prior.get("type", Variant()) == target.get("type", Variant())) return true;
    }
    return false;
}

Dictionary PlayerTools::request(const Dictionary &command) {
    String action = command.get("action", "scan");
    if (action == "objects") {
        if (!tree() || !tree()->get_root()) return failure("Scene is not ready.");
        Array pending, objects; pending.push_back(object_id(tree()->get_root()));
        for (int index = 0; index < pending.size() && index < 200; index++) {
            Node *node = Object::cast_to<Node>(live_object(parse_id(pending[index])));
            if (!node) continue;
            Dictionary row; row["object"] = object_id(node); row["path"] = Array(); row["label"] = String(node->get_path());
            row["value"] = node->get_class(); row["type"] = "object"; objects.push_back(row);
            for (int child = 0; child < node->get_child_count() && pending.size() < 201; child++) pending.push_back(object_id(node->get_child(child)));
        }
        Dictionary result; result["ok"] = true; result["rows"] = objects; result["truncated"] = pending.size() > 200; result["undoCount"] = history.size(); return result;
    }
    if (action == "scan") return scan(command.get("search", ""), command.get("scope", ""));
    if (action == "scene_tree" || action == "scene_node") return inspect_scene(command);
    if (action == "capture_activity" || action == "compare_activity") return scene_changes(command);
    if (action == "search_results") {
        if (!(search_busy && search_discovery)) result_page = command.get("page", result_page);
        return search_results();
    }
    if (action == "continue_search") return continue_search(command.get("progressOnly", false));
    if (action == "cancel_search") { search_busy = false; discovery_tasks.clear(); working_candidates.clear(); working_locations.clear(); discovery_seen.clear(); return search_results(); }
    if (action == "reset_search") {
        search_busy = false; discovery_tasks.clear(); working_candidates.clear(); working_locations.clear(); discovery_seen.clear(); result_page = 0;
        number_candidates.clear(); candidate_locations.clear(); search_history.clear(); search_started = false; search_steps = 0; candidate_truncated = false;
        return search_results();
    }
    if (action == "undo_search") {
        if (search_busy) return failure("Cancel the current search before undoing a refinement.");
        result_page = 0;
        if (search_history.size() == 0) return failure("There is no earlier refinement to restore.");
        SearchSnapshot previous = search_history[search_history.size() - 1]; search_history.resize(search_history.size() - 1);
        number_candidates = previous.candidates; candidate_filter = previous.filter; candidate_kind = previous.kind; search_steps = previous.steps;
        return search_results();
    }
    if (action == "read") {
        Dictionary target = command.get("target", Dictionary()); Object *owner = nullptr; Array path; Variant value; String error;
        if (!resolve(target, owner, path, value, error)) return failure(error);
        Node *node = Object::cast_to<Node>(owner);
        if (node && !node->is_inside_tree()) return failure("This object left the active scene.");
        if (is_empty_text(scalar_type(value))) return failure("This value cannot be monitored.");
        String display = value.get_type() == Variant::BOOL ? (bool(value) ? String("true") : String("false")) : String(value);
        if (display.length() > 512) return failure("This value is too long to monitor.");
        Dictionary row = target.duplicate(); row["value"] = display; row["frozen"] = is_frozen(row); Array values; values.push_back(row);
        Dictionary result; result["ok"] = true; result["rows"] = values; return result;
    }
    if (action == "freezes") {
        Array active, values;
        for (int i = 0; i < frozen.size(); i++) {
            Dictionary entry = frozen[i], target = entry.get("target", Dictionary());
            Object *owner = nullptr; Array path; Variant value; String error;
            if (!resolve(target, owner, path, value, error)) continue;
            Node *node = Object::cast_to<Node>(owner);
            if (node && !node->is_inside_tree()) continue;
            active.push_back(entry);
            Dictionary row = target.duplicate(); row["frozen"] = true; row["value"] = entry.get("value", ""); values.push_back(row);
        }
        frozen = active;
        Dictionary result; result["ok"] = true; result["rows"] = values; return result;
    }
    if (action == "unfreeze") {
        Dictionary target = command.get("target", Dictionary()); Array remaining;
        for (int i = 0; i < frozen.size(); i++) {
            Dictionary entry = frozen[i], prior = entry.get("target", Dictionary());
            if (!same_target(prior, target)) remaining.push_back(entry);
        }
        frozen = remaining;
        Dictionary result; result["ok"] = true; result["message"] = "Freeze released. The current value is unchanged."; return result;
    }
    if (action == "edit") return edit(command);
    if (action == "undo") return undo();
    if (action == "pause") return pause(command.get("enabled", false));
    if (action == "evaluate") return evaluate(command.get("code", ""));
    if (action == "input" || action == "release_input") return input(command);
    if (action == "options" || action == "status") return options(command);
    if (action == "find_numbers" || action == "refine_numbers") return find_numbers(command);
    if (action == "freeze") {
        int existing=-1;
        Dictionary target=command.get("target",Dictionary());
        for(int i=0;i<frozen.size();i++) {
            Dictionary prior=frozen[i], old_target=prior.get("target",Dictionary());
            if(same_target(old_target,target)) { existing=i; break; }
        }
        if (existing < 0 && frozen.size() >= 20) return failure("Only 20 values can be frozen in one session.");
        Dictionary result = edit(command);
        if (bool(result.get("ok", false))) { if(existing>=0) frozen[existing]=command; else frozen.push_back(command); result["message"] = "Frozen. This value will be held while the app is active."; }
        return result;
    }
    if (action == "clear_freezes") { frozen.clear(); Dictionary result; result["ok"] = true; return result; }
    if (action == "tick") {
        int failed = 0;
        if (tree() && !tree()->is_paused()) {
            Array remaining;
            for (int i = 0; i < frozen.size(); i++) {
                Dictionary result = edit(frozen[i], false);
                if (bool(result.get("ok", false))) remaining.push_back(frozen[i]); else failed++;
            }
            frozen = remaining;
        }
        Dictionary result; result["ok"] = true; result["message"] = itos(frozen.size()) + " frozen values; " + itos(failed) + " stale values released."; return result;
    }
    return failure("Unknown tools request.");
}

Dictionary PlayerTools::options(const Dictionary &command) {
    Engine *engine = Engine::get_singleton();
    if (!engine) return failure("Engine is not ready.");
#if VERSION_MAJOR >= 4
    if (original_fps < 0) original_fps = engine->get_max_fps();
#else
    if (original_fps < 0) original_fps = engine->get_target_fps();
#endif
    if (command.has("fps")) {
        int fps = command["fps"];
        if (fps != 0 && fps != 30 && fps != 60 && fps != 120) return failure("Choose the default, 30, 60 or 120 FPS.");
#if VERSION_MAJOR >= 4
        engine->set_max_fps(fps == 0 ? original_fps : fps);
#else
        engine->set_target_fps(fps == 0 ? original_fps : fps);
#endif
    }
    if (command.has("speed")) {
        double speed = command["speed"];
        if (Math::is_nan(speed) || Math::is_inf(speed) || speed < 0.25 || speed > 3) return failure("Game speed must be between 0.25 and 3.");
        engine->set_time_scale(speed);
    }
    Dictionary result; result["ok"] = true;
    const double fps = engine->get_frames_per_second();
    result["fps"] = fps > 0 && !Math::is_nan(fps) && !Math::is_inf(fps) ? fps : 0.0;
    result["frameMs"] = fps > 0 && !Math::is_nan(fps) && !Math::is_inf(fps) ? 1000.0 / fps : 0.0;
    Performance *performance = Performance::get_singleton();
    if (performance) {
        result["processMs"] = MAX(0.0, double(performance->get_monitor(Performance::TIME_PROCESS)) * 1000.0);
        result["physicsMs"] = MAX(0.0, double(performance->get_monitor(Performance::TIME_PHYSICS_PROCESS)) * 1000.0);
        result["engineMemoryBytes"] = MAX(0.0, double(performance->get_monitor(Performance::MEMORY_STATIC)));
    }
    result["message"] = String("FPS: ") + itos(engine->get_frames_per_second()) + " | speed: " + String::num(engine->get_time_scale()) + " | scene: " + (tree() && tree()->get_current_scene() ? String(tree()->get_current_scene()->get_name()) : String("loading"));
    result["ready"] = tree() && tree()->get_current_scene();
    return result;
}

Dictionary PlayerTools::input(const Dictionary &command) {
    Input *input = Input::get_singleton(); if (!input) return failure("Input is not ready.");
    const bool release = String(command.get("action", "")) == "release_input";
    if (release && virtual_pad < 0) { Dictionary result; result["ok"] = true; return result; }
    if (!release && String(command.get("kind", "")) == "text") {
        String text = command.get("text", ""); if (text.length() > 2048) return failure("Send at most 2048 characters at once.");
        for (int i = 0; i < text.length(); i++) {
            uint32_t codepoint = text[i];
            // Godot 3 uses UTF-16 wchar_t on Windows; Apple and Godot 4
            // use full-width code points. Send one event per Unicode scalar.
            if (codepoint >= 0xD800 && codepoint <= 0xDBFF && i + 1 < text.length()) {
                uint32_t next = text[i + 1];
                if (next >= 0xDC00 && next <= 0xDFFF) { codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + next - 0xDC00; i++; }
            }
            for (int pressed = 1; pressed >= 0; pressed--) {
                Ref<InputEventKey> event;
#if VERSION_MAJOR >= 4
                event.instantiate();
                if (codepoint == '\n') event->set_keycode(Key::ENTER);
#else
                event.instance();
                if (codepoint == '\n') event->set_scancode(KEY_ENTER);
#endif
                event->set_unicode(codepoint); event->set_pressed(pressed); input->parse_input_event(event);
            }
        }
        Dictionary result; result["ok"] = true; return result;
    }
    int requested_device=int(command.get("device",-1));
    if(requested_device < -1 || requested_device > 7) return failure("Invalid controller output device.");
    if (virtual_pad < 0 && requested_device < 0) {
        Array connected = input->get_connected_joypads();
        for (int device = 15; device >= 8; device--) if (!connected.has(device)) { virtual_pad = device; break; }
        if (virtual_pad < 0) return failure("No free virtual gamepad slot.");
        input->joy_connection_changed(virtual_pad, true, "Godot Player Virtual Controller", "");
    }
    const int output_device=requested_device>=0 ? requested_device : virtual_pad;
    String kind = command.get("kind", "axis");
    if (release || kind == "axis") {
        int first = release ? 0 : int(command.get("axis", 0)), last = release ? 5 : first;
        double value = release ? 0.0 : double(command.get("value", 0.0));
        if (first < 0 || last > 5 || Math::is_nan(value) || Math::is_inf(value) || value < -1 || value > 1) return failure("Invalid gamepad axis value.");
        for (int axis = first; axis <= last; axis++) {
            Ref<InputEventJoypadMotion> event;
#if VERSION_MAJOR >= 4
            event.instantiate(); event->set_axis(JoyAxis(axis));
#else
            event.instance(); event->set_axis(axis >= 4 ? axis + 2 : axis);
#endif
            event->set_device(output_device); event->set_axis_value(value); input->parse_input_event(event);
        }
    }
    if (release || kind == "button") {
        int first = release ? 0 : int(command.get("button", 0)), last = release ? 13 : first;
        if (first < 0 || last > 13) return failure("Invalid gamepad button.");
        for (int button = first; button <= last; button++) {
            Ref<InputEventJoypadButton> event;
#if VERSION_MAJOR >= 4
            static const int mapping[] = {0, 1, 2, 3, 9, 10, 4, 6, 7, 8, 11, 12, 13, 14};
            event.instantiate(); event->set_button_index(JoyButton(mapping[button]));
#else
            static const int mapping[] = {0, 1, 2, 3, 4, 5, 10, 11, 8, 9, 12, 13, 14, 15};
            event.instance(); event->set_button_index(mapping[button]);
#endif
            event->set_device(output_device); event->set_pressed(!release && bool(command.get("pressed", false))); input->parse_input_event(event);
        }
    }
    Dictionary result; result["ok"] = true; return result;
}

static bool search_scalar(Variant::Type type) {
    return type == Variant::BOOL || type == Variant::INT || type == Variant::STRING
#if VERSION_MAJOR >= 4
        || type == Variant::FLOAT;
#else
        || type == Variant::REAL;
#endif
}
static String stat_text(const Variant &value) {
    return value.get_type() == Variant::BOOL ? (bool(value) ? String("true") : String("false")) : String(value);
}

bool PlayerTools::indexed_value(const IndexedValue &candidate, const Vector<IndexedLocation> &locations, Variant &value, int *cached_location, Variant *cached_value) {
    if (candidate.location < 0 || candidate.location >= locations.size()) return false;
    const IndexedLocation &location = locations[candidate.location];
    Object *owner = nullptr; String error;
    if (cached_location && cached_value && *cached_location == candidate.location) {
        owner = live_object(location.owner); if (!owner) return false;
        value = *cached_value;
    } else {
        if (!resolve_path(location.owner, location.path, owner, value, error)) return false;
        if (cached_location && cached_value) { *cached_location = candidate.location; *cached_value = value; }
    }
    Node *node = Object::cast_to<Node>(owner); if (node && !node->is_inside_tree()) return false;
    if (candidate.step == ARRAY_ELEMENT) {
        if (value.get_type() != Variant::ARRAY) return false;
        Array array = value; int index = candidate.key;
        if (index < 0 || index >= array.size()) return false;
        value = array[index];
    } else if (candidate.step != COMPLETE_PATH) {
        if (value.get_type() != Variant::DICTIONARY) return false;
        Dictionary dictionary = value;
        if (!dictionary.has(candidate.key)) return false;
        value = dictionary[candidate.key];
    }
    return value.get_type() == candidate.before.get_type();
}
String PlayerTools::indexed_label(const IndexedValue &candidate, const Vector<IndexedLocation> &locations) const {
    String label = locations[candidate.location].label;
    if (candidate.step == ARRAY_ELEMENT) return label + "[" + itos(int(candidate.key)) + "]";
    if (candidate.step != COMPLETE_PATH) return label + "." + String(candidate.key);
    return label;
}
bool PlayerTools::indexed_match(const IndexedValue &candidate, const Variant &value) const {
    const Variant::Type type = value.get_type();
    if (!search_scalar(type) || !(working_type_mask & (1 << int(type)))) return false;
    if (type == Variant::STRING && String(value).length() > 512) return false;
    if (working_filter.length()) {
        const IndexedLocation &location = working_locations[candidate.location];
        if (location.lower_label.find(working_filter) < 0) {
            if (candidate.step == COMPLETE_PATH) return false;
            String suffix = candidate.step == ARRAY_ELEMENT ? "[" + itos(int(candidate.key)) + "]" : "." + String(candidate.key).to_lower();
            if ((working_name_spans ? location.lower_label + suffix : suffix).find(working_filter) < 0) return false;
        }
    }
    if (working_comparison == "any") return true;
    if (working_comparison == "changed") return value != candidate.before;
    if (working_comparison == "unchanged") return value == candidate.before;
    if (working_comparison == "exact") {
        if (type == Variant::INT) return expected_int_valid && int64_t(value) == expected_int;
        if (type == Variant::BOOL) return working_expected.to_lower() == (bool(value) ? "true" : "false");
        if (type == Variant::STRING) return String(value) == working_expected;
        return expected_float_valid && double(value) == expected_float;
    }
    if (type != Variant::BOOL && type != Variant::STRING) {
        const bool up = type == Variant::INT ? int64_t(value) > int64_t(candidate.before) : double(value) > double(candidate.before);
        const bool down = type == Variant::INT ? int64_t(value) < int64_t(candidate.before) : double(value) < double(candidate.before);
        return working_comparison == "increased" ? up : down;
    }
    return false;
}
void PlayerTools::collect_indexed(const IndexedValue &candidate, const Variant &value) {
    if (!indexed_match(candidate, value)) return;
    if (working_candidates.size() >= 250000) { working_truncated = true; return; }
    IndexedValue current = candidate; current.before = value;
    working_candidates.push_back(current);
}

Dictionary PlayerTools::find_numbers(const Dictionary &command) {
    if (search_busy) return failure("A search is already running. Wait or cancel it first.");
    const bool start = String(command.get("action", "")) == "find_numbers";
    String kind = command.get("kind", start ? String("number") : candidate_kind);
    String comparison = command.get("comparison", "exact"), expected = command.get("value", "");
    String scope = command.get("scope", start ? String("") : candidate_scope);
    if (kind != "number" && kind != "bool" && kind != "string" && kind != "any") return failure("Choose Any, Number, Boolean or Text.");
    if (comparison != "any" && comparison != "exact" && comparison != "changed" && comparison != "unchanged" && comparison != "increased" && comparison != "decreased") return failure("Unknown search comparison.");
    if (start && comparison != "any" && comparison != "exact") return failure("Start with Any or Equals, then narrow by changes after playing.");
    if (kind == "number" || kind == "bool") expected = expected.strip_edges();
    if (comparison == "exact" && kind == "number" && !expected.is_valid_float()) return failure("Enter a valid number before searching.");
    if (comparison == "exact" && kind == "bool" && expected.to_lower() != "true" && expected.to_lower() != "false") return failure("Choose True or False.");
    if (!start && (!search_started || scope != candidate_scope)) return failure("Start a new search after choosing a different scene scope.");
    if (start) {
        SceneTree *scene = tree();
        if (!scene || !scene->get_root()) return failure("The game scene is not ready yet.");
        Node *root = scope.length() ? Object::cast_to<Node>(live_object(parse_id(scope))) : scene->get_root();
        if (!root || !root->is_inside_tree()) return failure("This scene object is no longer available. Clear the scope or choose another object.");
        discovery_tasks.clear(); discovery_seen.clear(); working_locations.clear();
        Dictionary task; task["object"] = object_id(root); task["label"] = String(root->get_path()); task["depth"] = 0;
        discovery_tasks.push_back(task);
    } else working_locations = candidate_locations;
    working_candidates.clear(); working_index = 0; working_examined = 0;
    working_kind = kind; working_filter = String(command.get("search", "")).substr(0, 100).strip_edges().to_lower();
    working_scope = scope; working_comparison = comparison; working_expected = expected;
    working_name_spans = working_filter.find(".") >= 0 || working_filter.find("/") >= 0 || working_filter.find("[") >= 0;
    working_type_mask = 0;
    for (int type = 0; type <= int(Variant::STRING); type++) {
        if (!search_scalar(Variant::Type(type))) continue;
        if (kind == "bool" && type != int(Variant::BOOL)) continue;
        if (kind == "string" && type != int(Variant::STRING)) continue;
        if (kind == "number" && (type == int(Variant::BOOL) || type == int(Variant::STRING))) continue;
        working_type_mask |= 1 << type;
    }
    expected_int = parse_integer(expected, expected_int_valid); expected_float_valid = expected.is_valid_float();
#if VERSION_MAJOR >= 4
    expected_float = expected_float_valid ? expected.to_float() : 0;
#else
    expected_float = expected_float_valid ? expected.to_double() : 0;
#endif
    search_busy = true; search_discovery = start; working_truncated = start ? false : candidate_truncated;
    return continue_search();
}

Dictionary PlayerTools::continue_search(bool progress_only) {
    if (!search_busy) return search_results();
    const uint64_t started = OS::get_singleton()->get_ticks_usec();
    int processed = 0;
    int cached_location = -1; Variant cached_value;
    while (processed++ < 512 && OS::get_singleton()->get_ticks_usec() - started < 8000) {
        if (!search_discovery) {
            if (working_index >= number_candidates.size()) break;
            const IndexedValue &candidate = number_candidates[working_index++]; working_examined++;
            Variant value; if (indexed_value(candidate, candidate_locations, value, &cached_location, &cached_value)) collect_indexed(candidate, value);
            continue;
        }
        if (discovery_tasks.size() == 0) break;
        int last = discovery_tasks.size() - 1;
        Dictionary task = discovery_tasks[last]; discovery_tasks.resize(last);
        if (++working_examined > 1000000 || working_candidates.size() >= 250000) { working_truncated = true; discovery_tasks.clear(); break; }
        Object *owner = live_object(parse_id(task.get("object", "")));
        if (!owner) continue;
        Node *node = Object::cast_to<Node>(owner);
        if (node && !node->is_inside_tree()) continue;
        String label = task.get("label", ""); int depth = task.get("depth", 0);
        if (!task.has("path")) {
            if (!discovery_seen.insert(uint64_t(owner->get_instance_id())).second) continue;
            if (node) {
                for (int i = node->get_child_count() - 1; i >= 0; i--) {
                    if (discovery_tasks.size() >= 50000) { working_truncated = true; break; }
                    Node *child = node->get_child(i);
                    Dictionary next; next["object"] = object_id(child); next["label"] = String(child->get_path()); next["depth"] = 0; discovery_tasks.push_back(next);
                }
            }
            ScriptInstance *instance = owner->get_script_instance();
            if (!instance) continue;
            List<PropertyInfo> properties; instance->get_property_list(&properties);
            for (int pass = 0; pass < (working_filter.length() ? 2 : 1); pass++) {
                for (List<PropertyInfo>::Element *item = properties.back(); item; item = item->prev()) {
                    const PropertyInfo &info = item->get();
                    if (info.usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP)) continue;
                    if (working_filter.length()) {
                        const bool matches = (label + "." + String(info.name)).to_lower().find(working_filter) >= 0;
                        if (matches != (pass == 1)) continue;
                    }
                    if (discovery_tasks.size() >= 50000) { working_truncated = true; break; }
                    Array path; Dictionary step; step["kind"] = "property"; step["name"] = String(info.name); path.push_back(step);
                    Dictionary next; next["object"] = task["object"]; next["path"] = path; next["label"] = label + "." + String(info.name); next["depth"] = depth; discovery_tasks.push_back(next);
                }
            }
            continue;
        }
        Array path = task["path"]; Variant value; String error;
        const uint64_t id = parse_id(task["object"]);
        if (!resolve_path(id, path, owner, value, error)) continue;
        if (task.has("containerType") && int(task["containerType"]) != int(value.get_type())) { working_truncated = true; continue; }
        if (value.get_type() == Variant::OBJECT) {
            if (depth >= 8) { working_truncated = true; continue; }
#if VERSION_MAJOR >= 4
            Object *child = value.get_validated_object();
#else
            Object *child = live_object(value.get_object_instance_id());
#endif
            if (child && discovery_tasks.size() < 50000) { Dictionary next; next["object"] = object_id(child); next["label"] = label; next["depth"] = depth + 1; discovery_tasks.push_back(next); }
            continue;
        }
        if (!search_scalar(value.get_type()) && value.get_type() != Variant::DICTIONARY && value.get_type() != Variant::ARRAY) continue;
        int location = task.get("location", -1);
        if (location < 0) {
            IndexedLocation entry; entry.owner = id; entry.path = path; entry.label = label; entry.lower_label = label.to_lower();
            location = working_locations.size(); working_locations.push_back(entry);
        }
        if (search_scalar(value.get_type())) {
            IndexedValue candidate; candidate.location = location; candidate.before = value; collect_indexed(candidate, value); continue;
        }
        if (depth >= 8 || path.size() >= 8) { working_truncated = true; continue; }
        Dictionary dictionary; Array array;
        const bool is_dictionary = value.get_type() == Variant::DICTIONARY;
        if (is_dictionary) dictionary = value; else array = value;
        const int count = is_dictionary ? dictionary.size() : array.size();
        int cursor = task.get("cursor", 0), initial_cursor = cursor;
        Variant after = task.get("after", Variant()), last_key = after;
        if (is_dictionary && task.has("after") && !dictionary.has(after)) { working_truncated = true; continue; }
        const Variant *key = is_dictionary ? dictionary.next(task.has("after") ? &after : nullptr) : nullptr;
        Array children;
        // Index scalar entries in place. Share the container's path/label once,
        // rather than allocating a Dictionary, full path and label per value.
        for (int i = 0; i < 64 && cursor < count && processed < 512 && OS::get_singleton()->get_ticks_usec() - started < 8000; i++) {
            processed++;
            if (++working_examined > 1000000 || working_candidates.size() >= 250000 || discovery_tasks.size() + children.size() + 1 >= 50000) { working_truncated = true; cursor = count; break; }
            IndexedValue candidate; candidate.location = location; Variant child_value;
            if (is_dictionary) {
                if (!key) { cursor = count; break; }
                last_key = *key; key = dictionary.next(key); cursor++;
                if (!string_key(last_key) && last_key.get_type() != Variant::INT) continue;
                candidate.step = string_key(last_key) ? DICTIONARY_ELEMENT : INTEGER_KEY;
                candidate.key = last_key; child_value = dictionary[last_key];
            } else { candidate.step = ARRAY_ELEMENT; candidate.key = cursor; child_value = array[cursor++]; }
            if (search_scalar(child_value.get_type())) { candidate.before = child_value; collect_indexed(candidate, child_value); continue; }
            Dictionary step;
            step["kind"] = candidate.step == ARRAY_ELEMENT ? "array" : (candidate.step == INTEGER_KEY ? "dictionary_int" : "dictionary");
            if (candidate.step == ARRAY_ELEMENT) step["index"] = candidate.key; else step["name"] = String(candidate.key);
            Array nested = path.duplicate(); nested.push_back(step);
            Dictionary next; next["object"] = task["object"]; next["path"] = nested; next["label"] = indexed_label(candidate, working_locations); next["depth"] = depth + 1; children.push_back(next);
        }
        if (cursor < count && discovery_tasks.size() + children.size() < 50000) {
            Dictionary resume = task.duplicate(); resume["cursor"] = cursor; resume["containerType"] = int(value.get_type()); resume["location"] = location;
            if (is_dictionary && (cursor > initial_cursor || task.has("after"))) resume["after"] = last_key;
            discovery_tasks.push_back(resume);
        }
        for (int child = children.size() - 1; child >= 0; child--) discovery_tasks.push_back(children[child]);
    }
    const bool complete = search_discovery ? discovery_tasks.size() == 0 : working_index >= number_candidates.size();
    if (complete) {
        if (search_discovery) { search_history.clear(); search_steps = 0; }
        else {
            SearchSnapshot previous; previous.candidates = number_candidates; previous.filter = candidate_filter; previous.kind = candidate_kind; previous.steps = search_steps;
            search_history.push_back(previous); search_steps++;
            int history_rows = 0;
            for (int i = 0; i < search_history.size(); i++) history_rows += search_history[i].candidates.size();
            while (search_history.size() > 1 && (history_rows > 250000 || search_history.size() > 8)) {
                history_rows -= search_history[0].candidates.size();
                for (int i = 1; i < search_history.size(); i++) search_history.write[i - 1] = search_history[i];
                search_history.resize(search_history.size() - 1);
            }
        }
        number_candidates = working_candidates; working_candidates = Vector<IndexedValue>();
        candidate_locations = working_locations; working_locations = Vector<IndexedLocation>();
        candidate_kind = working_kind; candidate_filter = working_filter; candidate_scope = working_scope;
        candidate_truncated = working_truncated; search_started = true; search_busy = false; result_page = 0; discovery_seen.clear();
    }
    return search_results(!progress_only || !search_busy);
}

Dictionary PlayerTools::search_results(bool include_rows) {
    Array displayed; int stale = 0;
    const bool preview = search_busy && search_discovery;
    const Vector<IndexedValue> &candidates = preview ? working_candidates : number_candidates;
    const Vector<IndexedLocation> &locations = preview ? working_locations : candidate_locations;
    const int page_count = MAX(1, (candidates.size() + 99) / 100);
    if (!preview) result_page = CLAMP(result_page, 0, page_count - 1);
    const int page = preview ? 0 : result_page;
    int cached_location = -1; Variant cached_value;
    for (int i = page * 100; include_rows && i < MIN(candidates.size(), (page + 1) * 100); i++) {
        const IndexedValue &candidate = candidates[i]; Variant value;
        if (!indexed_value(candidate, locations, value, &cached_location, &cached_value) || (value.get_type() == Variant::STRING && String(value).length() > 512)) { stale++; continue; }
        const IndexedLocation &location = locations[candidate.location];
        Array path = location.path.duplicate();
        if (candidate.step != COMPLETE_PATH) {
            Dictionary step;
            step["kind"] = candidate.step == ARRAY_ELEMENT ? "array" : (candidate.step == INTEGER_KEY ? "dictionary_int" : "dictionary");
            if (candidate.step == ARRAY_ELEMENT) step["index"] = candidate.key; else step["name"] = String(candidate.key);
            path.push_back(step);
        }
        Dictionary row; row["object"] = String::num_uint64(location.owner); row["path"] = path;
        row["label"] = indexed_label(candidate, locations); row["type"] = scalar_type(value);
        row["previous"] = stat_text(candidate.before); row["value"] = stat_text(value); row["frozen"] = is_frozen(row); displayed.push_back(row);
    }
    Dictionary result; result["ok"] = true;
    if (include_rows) result["rows"] = displayed;
    result["searchStarted"] = search_started; result["searchKind"] = candidate_kind; result["searchFilter"] = candidate_filter; result["searchScope"] = candidate_scope;
    result["candidateCount"] = candidates.size(); result["staleCount"] = stale; result["searchSteps"] = search_steps;
    result["searchUndoCount"] = search_history.size(); result["truncated"] = preview ? working_truncated : candidate_truncated;
    result["searching"] = search_busy; result["examined"] = working_examined; result["workingMatches"] = working_candidates.size(); result["searchDiscovery"] = preview;
    result["page"] = page; result["pageCount"] = page_count; result["undoCount"] = history.size();
    result["indexedLocations"] = locations.size(); result["indexRecordsBytes"] = int64_t(candidates.size()) * sizeof(IndexedValue) + int64_t(locations.size()) * sizeof(IndexedLocation);
    return result;
}

static Dictionary scene_node_info(Node *node) {
    Dictionary info; info["object"] = object_id(node); info["name"] = String(node->get_name());
    info["path"] = String(node->get_path()); info["className"] = node->get_class();
    info["processing"] = node->is_processing() || node->is_physics_processing();
    info["inputProcessing"] = node->is_processing_input() || node->is_processing_unhandled_input();
    CanvasItem *canvas = Object::cast_to<CanvasItem>(node);
    if (canvas) info["visible"] = canvas->is_visible_in_tree();
    ScriptInstance *instance = node->get_script_instance();
    info["scriptPath"] = instance ? instance->get_script()->get_path() : String();
#if VERSION_MAJOR >= 4
    info["scenePath"] = node->get_scene_file_path();
#else
    info["scenePath"] = node->get_filename();
#endif
    return info;
}

Dictionary PlayerTools::inspect_scene(const Dictionary &command) {
    SceneTree *scene = tree();
    if (!scene || !scene->get_root()) return failure("The game scene is not ready yet.");
    Dictionary result; result["ok"] = true;
    Node *current = scene->get_current_scene();
    if (current) result["currentScene"] = scene_node_info(current);
    if (String(command.get("action", "")) == "scene_tree") {
        Array pending, nodes; pending.push_back(object_id(scene->get_root()));
        String query = String(command.get("search", "")).substr(0, 100).strip_edges().to_lower();
        bool visible_only = command.get("visibleOnly", true); int cursor = 0;
        while (cursor < pending.size() && cursor < 600 && nodes.size() < 200) {
            Node *node = Object::cast_to<Node>(live_object(parse_id(pending[cursor++])));
            if (!node || !node->is_inside_tree()) continue;
            Dictionary info = scene_node_info(node);
            String label = String(info["path"]) + " " + String(info["scriptPath"]);
            if ((!visible_only || bool(info.get("visible", true))) && (is_empty_text(query) || label.to_lower().find(query) >= 0)) nodes.push_back(info);
            for (int child = 0; child < node->get_child_count() && pending.size() < 600; child++) pending.push_back(object_id(node->get_child(child)));
        }
        result["nodes"] = nodes; result["truncated"] = cursor < pending.size() || pending.size() >= 600; return result;
    }
    Node *node = Object::cast_to<Node>(live_object(parse_id(command.get("object", ""))));
    if (!node || !node->is_inside_tree()) return failure("This scene object is no longer available. Refresh the scene list.");
    result["node"] = scene_node_info(node);
    Array actions;
    List<MethodInfo> signals; node->get_signal_list(&signals);
    for (List<MethodInfo>::Element *item = signals.front(); item && actions.size() < 80; item = item->next()) {
        List<Object::Connection> connections; node->get_signal_connection_list(item->get().name, &connections);
        for (List<Object::Connection>::Element *link = connections.front(); link && actions.size() < 80; link = link->next()) {
            const Object::Connection &connection = link->get(); Object *target = nullptr; String method;
#if VERSION_MAJOR >= 4
            target = ObjectDB::get_instance(connection.callable.get_object_id()); method = connection.callable.get_method();
#else
            target = connection.target; method = connection.method;
#endif
            if (!target) continue;
            Node *target_node = Object::cast_to<Node>(target);
            Dictionary action; action["signal"] = String(item->get().name); action["method"] = method;
            action["targetPath"] = target_node && target_node->is_inside_tree() ? String(target_node->get_path()) : target->get_class();
            action["targetObject"] = target_node ? object_id(target_node) : String(); actions.push_back(action);
        }
    }
    result["actions"] = actions;
    ScriptInstance *instance = node->get_script_instance();
    if (instance) {
        Ref<Script> script = instance->get_script();
        String source = script->get_source_code(); result["scriptSource"] = source.substr(0, 32768); result["sourceTruncated"] = source.length() > 32768;
    }
    return result;
}

Dictionary PlayerTools::scene_changes(const Dictionary &command) {
    if (String(command.get("action", "")) == "capture_activity") {
        max_rows = 2000;
        Dictionary captured = scan("", command.get("scope", "")); max_rows = 150;
        if (!bool(captured.get("ok", false))) return captured;
        activity_baseline = rows.duplicate(true); activity_ready = true; activity_truncated = truncated;
    }
    if (!activity_ready) return failure("Capture a snapshot, play the game, then compare changes.");
    Array changed; int changed_count = 0, stale = 0;
    for (int i = 0; i < activity_baseline.size(); i++) {
        Dictionary original = activity_baseline[i]; Object *owner = nullptr; Array path; Variant value; String error;
        if (!resolve(original, owner, path, value, error)) { stale++; continue; }
        Node *node = Object::cast_to<Node>(owner);
        if (node && !node->is_inside_tree()) { stale++; continue; }
        String now = value.get_type() == Variant::BOOL ? (bool(value) ? String("true") : String("false")) : String(value);
        if (now == String(original["value"]) || now.length() > 512) continue;
        changed_count++;
        if (changed.size() >= 200) continue;
        Dictionary row = original.duplicate(); row["previous"] = original["value"]; row["value"] = now; row["frozen"] = is_frozen(row); changed.push_back(row);
    }
    Dictionary result; result["ok"] = true; result["rows"] = changed; result["snapshotCount"] = activity_baseline.size();
    result["changedCount"] = changed_count; result["staleCount"] = stale; result["truncated"] = activity_truncated;
    return result;
}

String PlayerTools::dispatch_json(const String &json) {
    if (json.length() > 16384) {
#if VERSION_MAJOR >= 4
        return JSON::stringify(failure("Tools request is too large."));
#else
        return JSON::print(failure("Tools request is too large."));
#endif
    }
    Variant decoded;
#if VERSION_MAJOR >= 4
    decoded = JSON::parse_string(json);
#else
    String message; int line = 0; JSON::parse(json, decoded, message, line);
#endif
    Dictionary response;
    if (decoded.get_type() != Variant::DICTIONARY) response = failure("Invalid tools request.");
    else if (!tree() || !tree()->get_root()) response = failure("The game scene is not ready yet.");
    else {
        Node *root = tree()->get_root(); Ref<PlayerTools> tools;
        if (root->has_meta("godot_player_tools_session_v1")) tools = root->get_meta("godot_player_tools_session_v1");
        if (tools.is_null()) {
#if VERSION_MAJOR >= 4
            tools.instantiate();
#else
            tools.instance();
#endif
            root->set_meta("godot_player_tools_session_v1", tools);
        }
        response = tools->request(decoded);
    }
#if VERSION_MAJOR >= 4
    return JSON::stringify(response);
#else
    return JSON::print(response);
#endif
}
