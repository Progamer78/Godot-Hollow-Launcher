#include "player_tools.h"
#include "core/math/expression.h"
#include "core/io/json.h"
#include "core/os/os.h"
#include "main/performance.h"
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
    if (++examined > 12000 || rows.size() >= 150) { truncated = true; return; }
    String type = scalar_type(value);
    if (!is_empty_text(type)) {
        if (numeric_only && type != "int" && type != "float") return;
        if (boolean_only && type != "bool") return;
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
            if (examined > 12000 || rows.size() >= 150) break;
        }
    } else if (value.get_type() == Variant::ARRAY) {
        Array array = value;
        if (array.size() > 128) truncated = true;
        for (int i = 0; i < MIN(array.size(), 128); i++) {
            Array next = path.duplicate(); Dictionary step; step["kind"] = "array"; step["index"] = i; next.push_back(step);
            scan_value(owner, array[i], next, label + "[" + itos(i) + "]", depth + 1);
            if (examined > 12000 || rows.size() >= 150) break;
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
    if (!object || depth > 5 || visited >= 600 || rows.size() >= 150 || examined > 12000) { truncated = true; return; }
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
            if (examined > 12000 || rows.size() >= 150) break;
        }
        if (!live_object(id) || examined > 12000 || rows.size() >= 150) break;
        }
    }
}

Dictionary PlayerTools::scan(const String &search) {
    rows.clear(); seen.clear(); visited = 0; examined = 0; truncated = false; filter = search.substr(0, 100).to_lower();
    SceneTree *scene = tree();
    if (!scene || !scene->get_root()) return failure("The game scene is not ready yet.");
    // Breadth first: autoloads and their game-state dictionaries are searched
    // before deep decorative scene hierarchies. Budget remains bounded.
    Array pending; pending.push_back(object_id(scene->get_root()));
    int cursor = 0;
    while (cursor < pending.size() && cursor < 600 && rows.size() < 150 && examined <= 12000) {
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
    String id = target["object"]; owner = live_object(parse_id(id)); path = target["path"];
    if (!owner || path.size() < 1 || path.size() > 8) { error = "This stat's owner no longer exists. Refresh the list."; return false; }
    value = owner;
    for (int i = 0; i < path.size(); i++) {
        if (path[i].get_type() != Variant::DICTIONARY) { error = "Invalid stat path."; return false; }
        Dictionary step = path[i]; String kind = step.get("kind", "");
        if (kind == "property" && i == 0) {
            bool valid = false; value = owner->get(String(step.get("name", "")), &valid);
            if (!valid || !live_object(parse_id(id))) { error = "The stat is no longer available."; return false; }
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
    if (target.has("type") && String(target["type"]) != scalar_type(value)) {
        error = "This stat's type changed. Refresh the list before editing it."; return false;
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
    if (action == "scan") return scan(command.get("search", ""));
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

Dictionary PlayerTools::find_numbers(const Dictionary &command) {
    String action = command.get("action", "");
    String kind = command.get("kind", action == "find_numbers" ? String("number") : candidate_kind);
    if (kind != "number" && kind != "bool") return failure("Choose Number or Boolean.");
    String comparison = command.get("comparison", "exact"), expected = String(command.get("value", "")).strip_edges();
    String name_filter = String(command.get("search", "")).substr(0, 100).strip_edges().to_lower();
    if (comparison != "any" && comparison != "exact" && comparison != "changed" && comparison != "unchanged" && comparison != "increased" && comparison != "decreased") return failure("Unknown search comparison.");
    if (kind == "bool" && (comparison == "increased" || comparison == "decreased")) return failure("Booleans support Equals, Changed and Unchanged.");
    if (comparison == "exact") {
        if (kind == "bool") {
            expected = expected.to_lower();
            if (expected != "true" && expected != "false") return failure("Choose True or False.");
        } else if (!expected.is_valid_float()) return failure("Enter a valid number before searching.");
    }
    if (action == "find_numbers") {
        numeric_only = kind == "number"; boolean_only = kind == "bool";
        scan(name_filter); numeric_only = false; boolean_only = false;
        number_candidates = rows.duplicate();
        candidate_kind = kind;
    } else if (kind != candidate_kind) return failure("Start a new search after changing the value type.");
    Array remaining;
    for (int i = 0; i < number_candidates.size(); i++) {
        Dictionary row = number_candidates[i]; Object *owner = nullptr; Array path; Variant value; String error;
        if (!resolve(row, owner, path, value, error)) continue;
        String label = row["label"];
        if ((!is_empty_text(name_filter) && label.to_lower().find(name_filter) < 0) || scalar_type(value) != String(row["type"])) continue;
        String now = value.get_type() == Variant::BOOL ? (bool(value) ? String("true") : String("false")) : String(value), before = row["value"];
        bool increased = false, decreased = false;
        if (value.get_type() == Variant::INT) {
            bool valid = false; int64_t old = parse_integer(before, valid);
            if (valid) { increased = int64_t(value) > old; decreased = int64_t(value) < old; }
        } else if (kind == "number") {
#if VERSION_MAJOR >= 4
            double old = before.to_float();
#else
            double old = before.to_double();
#endif
            increased = double(value) > old; decreased = double(value) < old;
        }
        bool exact = now == expected;
        if (kind == "number" && comparison == "exact") {
            if (value.get_type() == Variant::INT) {
                bool valid = false; int64_t number = parse_integer(expected, valid);
                exact = valid && int64_t(value) == number;
            } else {
#if VERSION_MAJOR >= 4
                exact = double(value) == expected.to_float();
#else
                exact = double(value) == expected.to_double();
#endif
            }
        }
        bool keep = comparison == "any" || (comparison == "exact" && exact) || (comparison == "changed" && now != before) || (comparison == "unchanged" && now == before) || (comparison == "increased" && increased) || (comparison == "decreased" && decreased);
        if (keep) { row["value"] = now; row["frozen"] = is_frozen(row); remaining.push_back(row); }
    }
    number_candidates = remaining;
    Dictionary result; result["ok"] = true; result["rows"] = remaining; result["truncated"] = truncated; result["undoCount"] = history.size(); return result;
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
