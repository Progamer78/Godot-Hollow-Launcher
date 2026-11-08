#include "player_tools.h"
#include "core/math/expression.h"
#include "core/io/json.h"
#include "core/os/os.h"
#include <cerrno>
#include <cstdlib>
#if VERSION_MAJOR >= 4
#include "core/object/script_language.h"
#include "scene/main/window.h"
#else
#include "core/script_language.h"
#include "scene/main/viewport.h"
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
        if (!is_empty_text(filter) && label.to_lower().find(filter) < 0) return;
        // Avoid flooding the editor with narrative text or save blobs.
        String display = type == "bool" ? (bool(value) ? "true" : "false") : String(value);
        if (display.length() > 512) return;
        Dictionary row; row["object"] = object_id(owner); row["path"] = path;
        row["label"] = label; row["type"] = type; row["value"] = display;
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

Dictionary PlayerTools::edit(const Dictionary &command) {
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
    Change change; change.target = target; change.before = current; change.after = actual;
    if (history.size() >= 20) {
#if VERSION_MAJOR >= 4
        history.remove_at(0);
#else
        history.remove(0);
#endif
    }
    history.push_back(change);
    Dictionary result; result["ok"] = true; result["message"] = "Value updated in the running game."; result["undoCount"] = history.size(); return result;
}

Dictionary PlayerTools::undo() {
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

Dictionary PlayerTools::request(const Dictionary &command) {
    String action = command.get("action", "scan");
    if (action == "scan") return scan(command.get("search", ""));
    if (action == "edit") return edit(command);
    if (action == "undo") return undo();
    if (action == "pause") return pause(command.get("enabled", false));
    if (action == "evaluate") return evaluate(command.get("code", ""));
    return failure("Unknown tools request.");
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
