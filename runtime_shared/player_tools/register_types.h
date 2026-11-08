#include "core/version.h"
#if VERSION_MAJOR >= 4
#include "modules/register_module_types.h"
void initialize_player_tools_module(ModuleInitializationLevel level);
void uninitialize_player_tools_module(ModuleInitializationLevel level);
#else
void register_player_tools_types();
void unregister_player_tools_types();
#endif
