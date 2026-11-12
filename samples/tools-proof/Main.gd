extends Node

var money = 12
var health = 85.5
var player_flag = false
var player_name = "Test"
var stats = {"wallet": {"money": 40}, "levels": [1, 2, 3], 9223372036854775807: 9}
var stats_resource
var tools
var checks = 0
var typed_codes = []

func _input(event):
    if event is InputEventKey and event.pressed:
        typed_codes.append(event.unicode)

func _ready():
    call_deferred("run_checks")

func check(condition, message):
    if not condition:
        push_error("PLAYER_TOOLS_PROOF FAIL: " + message)
        get_tree().quit(1)
        assert(condition, message)
    checks += 1

func target(suffix):
    var result = tools.request({"action": "scan", "search": suffix})
    check(result.ok, "scan succeeds")
    for row in result.rows:
        if row.label.ends_with(suffix): return row
    check(false, "stat found: " + suffix)
    return {}

func edit(suffix, value):
    var row = target(suffix)
    var result = tools.request({"action": "edit", "target": row, "value": value})
    check(result.ok, "edit succeeds: " + suffix)
    return row

func run_checks():
    tools = ClassDB.call("instantiate", "PlayerTools")
    check(tools != null, "native tools class exists in release template")
    var performance = tools.request({"action": "status"})
    check(performance.ok and performance.fps >= 0 and performance.frameMs >= 0, "performance HUD has numeric FPS and frame interval")
    check(performance.processMs >= 0 and performance.physicsMs >= 0 and performance.engineMemoryBytes >= 0, "performance monitors return nonnegative runtime measurements")
    check((performance.fps == 0 and performance.frameMs == 0) or abs(performance.fps * performance.frameMs - 1000.0) < 0.01, "frame interval is consistent with observed FPS")
    stats_resource = load("res://Stats.gd").new()
    edit(".money", "999")
    check(money == 999, "script integer changed")
    check(tools.request({"action": "undo"}).ok, "undo succeeds")
    check(money == 12, "undo restored integer")
    edit(".health", "123.75")
    check(health == 123.75, "floating stat changed")
    edit(".player_flag", "true")
    check(player_flag == true, "boolean changed")
    edit(".player_name", "Changed")
    check(player_name == "Changed", "short text changed")
    edit(".stats.wallet.money", "888")
    check(stats.wallet.money == 888, "nested dictionary updated")
    edit(".stats.levels[1]", "42")
    check(stats.levels[1] == 42, "array value updated")
    edit(".stats.9223372036854775807", "77")
    check(stats[9223372036854775807] == 77, "64-bit dictionary key preserved")
    var resource_target = edit(".stats_resource.money", "321")
    check(stats_resource.money == 321, "resource instance ID preserved")
    var row = target(".money")
    check(not tools.request({"action": "edit", "target": row, "value": "9999999999999999999999999999999"}).ok, "overflow rejected")
    check(not tools.request({"action": "edit", "target": row, "value": "abc"}).ok, "invalid integer rejected")
    var health_target = target(".health")
    check(not tools.request({"action": "edit", "target": health_target, "value": "nan"}).ok, "non-finite stat rejected")
    var expression = tools.request({"action": "evaluate", "code": "get_node('ToolsProof').money + 1"})
    check(expression.ok and expression.message == "13", "expression reads real scene state")
    check(not tools.request({"action": "evaluate", "code": "(("}).ok, "invalid expression reported")
    check(not get_tree().paused, "scene starts unpaused")
    check(tools.request({"action": "pause", "enabled": true}).ok and get_tree().paused, "tools pause scene")
    tools.request({"action": "pause", "enabled": false})
    check(not get_tree().paused, "pause restored")
    get_tree().paused = true
    tools.request({"action": "pause", "enabled": true})
    tools.request({"action": "pause", "enabled": false})
    check(get_tree().paused, "original game pause preserved")
    get_tree().paused = false
    var gone = load("res://Gone.gd").new()
    gone.name = "Gone"
    add_child(gone)
    var stale = target("Gone.money")
    gone.free()
    check(not tools.request({"action": "edit", "target": stale, "value": "100"}).ok, "freed object rejected")
    edit(".money", "777")
    money = 778
    check(not tools.request({"action": "undo"}).ok, "undo does not overwrite later game changes")
    var changed_type = target(".money")
    money = "different type"
    check(not tools.request({"action": "edit", "target": changed_type, "value": "100"}).ok, "changed property type rejected")
    money = 778
    var wire = JSON.parse_string(tools.transport(JSON.stringify({"action": "scan", "search": "stats_resource.money"})))
    check(wire.ok and wire.rows.size() == 1, "JSON transport reads live resources")
    var wire_edit = JSON.parse_string(tools.transport(JSON.stringify({"action": "edit", "target": wire.rows[0], "value": "9223372036854775807"})))
    check(wire_edit.ok and stats_resource.money == 9223372036854775807, "JSON transport preserves 64-bit object IDs and values")
    var wire_undo = JSON.parse_string(tools.transport(JSON.stringify({"action": "undo"})))
    check(wire_undo.ok and stats_resource.money == 321, "JSON session undo persists between requests")
    money = 50
    var candidates = tools.request({"action": "find_numbers", "comparison": "exact", "value": "50"})
    check(candidates.ok and candidates.rows.size() == 1, "numeric search finds live exact value")
    money = 51
    candidates = tools.request({"action": "refine_numbers", "comparison": "increased"})
    check(candidates.rows.size() == 1 and candidates.rows[0].value == "51", "numeric search narrows by increase")
    check(tools.request({"action": "freeze", "target": candidates.rows[0], "value": "60"}).ok, "freeze initial edit succeeds")
    check(tools.request({"action":"read","target":candidates.rows[0]}).rows[0].frozen, "live reads report an active freeze")
    check(tools.request({"action":"scan","search":candidates.rows[0].label}).rows[0].frozen, "stat scans identify frozen variables")
    var active_freezes = tools.request({"action":"freezes"})
    check(active_freezes.ok and active_freezes.rows.size() == 1 and active_freezes.rows[0].value == "60", "active freeze list reports the held value")
    money = 1
    tools.request({"action": "tick"})
    check(money == 60, "freeze tick restores desired value")
    check(tools.request({"action":"freeze","target":candidates.rows[0],"value":"70"}).ok, "existing freeze accepts an edited pin value")
    money = 3
    tools.request({"action":"tick"})
    check(money == 70, "updated freeze replaces the old pinned value")
    var reused_freeze_slot = true
    for _i in range(25):
        if not tools.request({"action":"freeze","target":candidates.rows[0],"value":"70"}).ok:
            reused_freeze_slot = false
    check(reused_freeze_slot, "editing a pinned freeze reuses its slot instead of hitting the 20-freeze limit")
    var rescanned_target = tools.request({"action":"scan","search":candidates.rows[0].label}).rows[0]
    check(tools.request({"action":"freeze","target":rescanned_target,"value":"70"}).ok and tools.request({"action":"freezes"}).rows.size() == 1, "fresh scan freeze reuses the existing slot on both engines")
    check(tools.request({"action":"unfreeze","target":rescanned_target}).ok and tools.request({"action":"freezes"}).rows.size() == 0, "individual unfreeze resolves a fresh scan's path")
    money = 4
    tools.request({"action":"tick"})
    check(money == 4 and not tools.request({"action":"read","target":candidates.rows[0]}).rows[0].frozen, "released variable no longer reports frozen or receives writes")
    tools.request({"action":"freeze","target":candidates.rows[0],"value":"70"})
    money = "type changed"
    check(tools.request({"action":"freezes"}).rows.size() == 0, "stale freezes disappear when the variable changes type")
    tools.request({"action": "clear_freezes"})
    money = 2
    tools.request({"action": "tick"})
    check(money == 2, "cleared freeze stops writing")
    player_flag = false
    var boolean_search = tools.request({"action":"find_numbers","kind":"bool","comparison":"exact","value":"false","search":"player_flag"})
    check(boolean_search.ok and boolean_search.rows.size() == 1 and boolean_search.rows[0].type == "bool", "boolean search matches false and a variable-name filter")
    player_flag = true
    boolean_search = tools.request({"action":"refine_numbers","kind":"bool","comparison":"changed","search":"PLAYER_FLAG"})
    check(boolean_search.ok and boolean_search.rows.size() == 1 and boolean_search.rows[0].value == "true", "boolean search narrows changed values with case-insensitive names")
    check(tools.request({"action":"edit","target":boolean_search.rows[0],"value":"false"}).ok and player_flag == false, "boolean search results can be edited")
    boolean_search = tools.request({"action":"refine_numbers","kind":"bool","comparison":"unchanged"})
    check(boolean_search.rows.size() == 0, "boolean unchanged comparison drops edited values")
    check(not tools.request({"action":"find_numbers","kind":"bool","comparison":"increased"}).ok, "boolean search rejects numeric-only comparisons")
    money = 55
    var named_numbers = tools.request({"action":"find_numbers","comparison":"any","search":"money"})
    var names_match = named_numbers.rows.size() > 0
    for match_row in named_numbers.rows:
        names_match = names_match and match_row.label.to_lower().find("money") >= 0
    check(names_match, "numeric search applies variable names before the candidate limit")
    named_numbers = tools.request({"action":"refine_numbers","comparison":"any","search":"stats_resource.money"})
    check(named_numbers.rows.size() == 1 and named_numbers.rows[0].label.find("stats_resource.money") >= 0, "existing numeric candidates can be narrowed by variable path")
    check(not tools.request({"action":"find_numbers","comparison":"exact","value":"not a number"}).ok, "invalid numeric exact searches are refused")
    var monitor_target = target(".player_flag")
    var monitored = tools.request({"action":"read","target":monitor_target})
    check(monitored.ok and monitored.rows[0].value == "false", "pinned monitor reads booleans without editing them")
    player_flag = true
    monitored = tools.request({"action":"read","target":monitor_target})
    check(monitored.ok and monitored.rows[0].value == "true", "cached pinned target returns the current live value")
    var fps_property = "max_fps" if Engine.get_version_info().major >= 4 else "target_fps"
    var previous_fps = Engine.get(fps_property)
    check(tools.request({"action": "options", "fps": 30}).ok and Engine.get(fps_property) == 30, "frame cap changes actual engine setting")
    tools.request({"action": "options", "fps": 0})
    check(Engine.get(fps_property) == previous_fps, "default restores original game cap")
    check(tools.request({"action": "options", "speed": 0.5}).ok and Engine.time_scale == 0.5, "speed changes actual engine time scale")
    tools.request({"action": "options", "speed": 1.0})
    check(not tools.request({"action": "options", "speed": 0.0}).ok, "unsafe speed rejected")
    check(tools.request({"action": "input", "kind": "axis", "axis": 0, "value": 0.4}).ok, "analog event accepted")
    Input.flush_buffered_events()
    var devices = Input.get_connected_joypads()
    var device = devices[devices.size() - 1]
    check(abs(Input.get_joy_axis(device, 0) - 0.4) < 0.01, "game receives intermediate analog strength")
    check(tools.request({"action": "input", "kind": "button", "button": 0, "pressed": true}).ok, "virtual controller button accepted")
    Input.flush_buffered_events()
    check(Input.is_joy_button_pressed(device, 0), "game receives virtual controller button")
    tools.request({"action": "release_input"})
    Input.flush_buffered_events()
    check(Input.get_joy_axis(device, 0) == 0 and not Input.is_joy_button_pressed(device, 0), "focus release clears analog and gamepad holds")
    check(not tools.request({"action": "input", "kind": "axis", "axis": 99, "value": 0}).ok, "invalid axis refused")
    check(tools.request({"action":"input","kind":"button","button":0,"pressed":true,"device":0}).ok,"remapped controller targets player one")
    Input.flush_buffered_events()
    check(Input.is_joy_button_pressed(0,0),"player-one games receive remapped gamepad button")
    tools.request({"action":"input","kind":"button","button":0,"pressed":false,"device":0})
    Input.flush_buffered_events()
    check(not Input.is_joy_button_pressed(0,0),"player-one remapping releases the button")
    check(not tools.request({"action":"input","kind":"button","button":0,"pressed":true,"device":99}).ok,"invalid output player refused")
    check(tools.request({"action": "input", "kind": "text", "text": "Aé🙂"}).ok, "Unicode text events accepted")
    Input.flush_buffered_events()
    check(typed_codes.size() >= 3 and typed_codes[typed_codes.size() - 3] == 65 and typed_codes[typed_codes.size() - 2] == 233 and typed_codes[typed_codes.size() - 1] == 128578, "scene receives full Unicode text key events")
    var objects = tools.request({"action": "objects"})
    check(objects.ok and objects.rows.size() >= 2, "browser lists real scene objects")
    print("PLAYER_TOOLS_PROOF PASS checks=", checks)
    get_tree().quit()
