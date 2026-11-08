// Godot's iOS exporter normally generates these callbacks in the exported
// Xcode project. This engine is linked independently as a bundled framework,
// with no exported iOS native plugins. Built-in modules (including Spine and
// PlayerTools) use Godot's separate module registration path.
#include "api/api.h"

void godot_ios_plugins_initialize() {}
void godot_ios_plugins_deinitialize() {}
