"""Keep loose game paths separate from the signed application's resources."""
from patch_engine import replace

def patch(engine):
    apple = engine / "drivers/apple_embedded"
    # Expose the selected game's loose assets through ordinary Godot paths.
    replace(apple / "os_apple_embedded.h", "virtual String get_resource_dir() const override;",
        'virtual String get_executable_path() const override { const char *p = getenv("HOLLOW_GAME_FILES"); return p && *p ? String::utf8(p).path_join("game") : OS_Unix::get_executable_path(); }\n\tvirtual String get_resource_dir() const override;')
    os_file = apple / "os_apple_embedded.mm"
    replace(os_file, "String OS_AppleEmbedded::get_resource_dir() const {",
        'String OS_AppleEmbedded::get_resource_dir() const {\n\tconst char *p = getenv("HOLLOW_GAME_FILES");\n\tif (p && *p) return String::utf8(p);')
