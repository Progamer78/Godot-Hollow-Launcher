extends Node

var money = 12
var health = 85.5
var player_flag = false
var player_name = "Test"
var stats = {"wallet": {"money": 40}, "levels": [1, 2, 3], 9223372036854775807: 9}
var stats_resource
var tools
var checks = 0

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
    print("PLAYER_TOOLS_PROOF PASS checks=", checks)
    get_tree().quit()
