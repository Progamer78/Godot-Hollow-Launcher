#include "register_types.h"
#include "player_tools.h"
#if VERSION_MAJOR >= 4
void initialize_player_tools_module(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<PlayerTools>();
}
void uninitialize_player_tools_module(ModuleInitializationLevel level) {}
#else
void register_player_tools_types() { ClassDB::register_class<PlayerTools>(); }
void unregister_player_tools_types() {}
#endif
