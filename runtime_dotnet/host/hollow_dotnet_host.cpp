// Trusted Mono host experiment. Imported Windows native libraries are never staged.
#include "core/config/project_settings.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/os/os.h"
#include "core/string/print_string.h"
#include <mono/jit/jit.h>
#include <cstdio>

extern "C" int coreclr_initialize(const char *, const char *, int, const char **, const char **, void **, unsigned int *);
extern "C" void *mono_aot_module_System_Private_CoreLib_info;
extern "C" void *mono_aot_module_GodotSharp_info;

static uint32_t pe_u32(const Vector<uint8_t> &bytes, int offset) {
	return uint32_t(bytes[offset]) | uint32_t(bytes[offset + 1]) << 8 | uint32_t(bytes[offset + 2]) << 16 | uint32_t(bytes[offset + 3]) << 24;
}
static uint16_t pe_u16(const Vector<uint8_t> &bytes, int offset) {
	return uint16_t(bytes[offset]) | uint16_t(bytes[offset + 1]) << 8;
}
static bool portable_il(const Vector<uint8_t> &bytes) {
	// Accept IL-only PE images. Never load Windows machine code or ReadyToRun.
	if (bytes.size() < 128 || bytes[0] != 'M' || bytes[1] != 'Z') return false;
	uint32_t pe = pe_u32(bytes, 60);
	if (pe > uint32_t(bytes.size() - 24) || pe_u32(bytes, pe) != 0x4550) return false;
	uint32_t opt = pe + 24, opt_size = pe_u16(bytes, pe + 20), sections = pe_u16(bytes, pe + 6);
	if (opt_size < 2 || opt_size > bytes.size() - opt || sections > 96) return false;
	uint32_t directories = pe_u16(bytes, opt) == 0x20b ? 112 : pe_u16(bytes, opt) == 0x10b ? 96 : 0;
	if (!directories || opt_size < directories + 15 * 8 || pe_u32(bytes, opt + directories - 4) < 15) return false;
	uint32_t cli_rva = pe_u32(bytes, opt + directories + 14 * 8);
	uint32_t table = opt + opt_size;
	if (table > uint32_t(bytes.size()) || sections > (bytes.size() - table) / 40) return false;
	for (uint32_t i = 0; i < sections; i++) {
		uint32_t section = table + i * 40, va = pe_u32(bytes, section + 12), raw = pe_u32(bytes, section + 20), size = pe_u32(bytes, section + 16);
		if (cli_rva < va || cli_rva - va >= size) continue;
		uint64_t offset = uint64_t(raw) + cli_rva - va;
		if (offset + 72 > uint64_t(bytes.size()) || size - (cli_rva - va) < 72) return false;
		uint32_t flags = pe_u32(bytes, offset + 16);
		return (flags & 1) != 0 && (flags & 2) == 0 && pe_u32(bytes, offset + 64) == 0 && pe_u32(bytes, offset + 68) == 0;
	}
	return false;
}

int hollow_dotnet_initialize(const char *, const char *, int, const char **, const char **, void **handle, unsigned int *domain) {
	const String assembly = ProjectSettings::get_singleton()->get_setting("dotnet/project/assembly_name", "");
	ERR_FAIL_COND_V_MSG(assembly.is_empty() || assembly.get_file() != assembly || assembly.contains(":"), -1, "Invalid managed game assembly name.");
	String source;
	Ref<DirAccess> publish = DirAccess::open("res://.godot/mono/publish");
	ERR_FAIL_COND_V_MSG(publish.is_null(), -1, "Managed publish directory is missing.");
	publish->list_dir_begin();
	for (String name = publish->get_next(); !name.is_empty(); name = publish->get_next()) {
		if (publish->current_is_dir() && FileAccess::exists("res://.godot/mono/publish/" + name + "/" + assembly + ".dll")) {
			source = "res://.godot/mono/publish/" + name; break;
		}
	}
	publish->list_dir_end();
	ERR_FAIL_COND_V_MSG(source.is_empty(), -1, "Main managed assembly is missing from this pack.");
	const String cache = OS::get_singleton()->get_user_data_dir().path_join(".hollow-managed");
	ERR_FAIL_COND_V(DirAccess::make_dir_recursive_absolute(cache) != OK, -1);
	Ref<DirAccess> files = DirAccess::open(source);
	ERR_FAIL_COND_V(files.is_null(), -1);
	files->list_dir_begin(); int count = 0; uint64_t total = 0;
	for (String name = files->get_next(); !name.is_empty(); name = files->get_next()) {
		if (files->current_is_dir() || name.get_extension().to_lower() != "dll") continue;
		if (name != assembly + ".dll" && (name == "GodotSharp.dll" || name == "mscorlib.dll" || name == "netstandard.dll" || name.begins_with("System.") || name.begins_with("Microsoft."))) continue;
		Ref<FileAccess> input = FileAccess::open(source.path_join(name), FileAccess::READ);
		ERR_FAIL_COND_V(input.is_null() || input->get_length() > 32 * 1024 * 1024, -1);
		Vector<uint8_t> bytes = input->get_buffer(input->get_length());
		ERR_FAIL_COND_V_MSG(!portable_il(bytes), -1, "Unsupported native, mixed-mode or ReadyToRun game dependency: " + name);
		total += bytes.size();
		ERR_FAIL_COND_V(++count > 128 || total > 128 * 1024 * 1024, -1);
		Ref<FileAccess> target = FileAccess::open(cache.path_join(name), FileAccess::WRITE);
		ERR_FAIL_COND_V(target.is_null(), -1); target->store_buffer(bytes); target->close();
	}
	files->list_dir_end();
	const String bundled = OS::get_singleton()->get_bundle_resource_dir();
	const String managed = bundled.path_join("Managed");
	Ref<DirAccess> platform = DirAccess::open(managed);
	ERR_FAIL_COND_V_MSG(platform.is_null(), -1, "The trusted managed runtime was not bundled.");
	String tpa; platform->list_dir_begin();
	for (String name = platform->get_next(); !name.is_empty(); name = platform->get_next()) {
		if (!platform->current_is_dir() && name.get_extension() == "dll") { if (!tpa.is_empty()) tpa += ":"; tpa += managed.path_join(name); }
	}
	platform->list_dir_end();
	CharString trusted = tpa.utf8(), paths = (cache + ":" + managed).utf8(), base = managed.utf8(), native = bundled.utf8();
	const char *keys[] = { "TRUSTED_PLATFORM_ASSEMBLIES", "APP_PATHS", "APP_CONTEXT_BASE_DIRECTORY", "NATIVE_DLL_SEARCH_DIRECTORIES" };
	const char *values[] = { trusted.get_data(), paths.get_data(), base.get_data(), native.get_data() };
	mono_aot_register_module(reinterpret_cast<void **>(mono_aot_module_System_Private_CoreLib_info));
	mono_aot_register_module(reinterpret_cast<void **>(mono_aot_module_GodotSharp_info));
	mono_jit_set_aot_mode(MONO_AOT_MODE_INTERP);
	print_line("HOLLOW_DOTNET: Starting signed Mono interpreter with independent managed game assemblies.");
	return coreclr_initialize("Hollow", "Hollow", 4, keys, values, handle, domain);
}

#ifdef HOLLOW_DOTNET_PROOF
#include "main/main.h"
extern int apple_embedded_main(int, char **);
// The ordinary Xcode exporter generates these callbacks. This isolated proof
// includes no export plugins and supplies the same empty callbacks itself.
void godot_apple_embedded_plugins_initialize() {}
void godot_apple_embedded_plugins_deinitialize() {}
extern "C" int HollowRunGodotProof(const char *executable, const char *pack, const char *log) {
	setvbuf(stdout, nullptr, _IONBF, 0); setvbuf(stderr, nullptr, _IONBF, 0);
	// Upstream's change_to_launch_dir expects argv[0] to be an absolute path,
	// just as the working launcher supplies it.
	char *argv[] = { const_cast<char *>(executable), const_cast<char *>("--headless"), const_cast<char *>("--main-pack"), const_cast<char *>(pack), const_cast<char *>("--log-file"), const_cast<char *>(log), nullptr };
	int result = apple_embedded_main(6, argv);
	fprintf(stderr, "HOLLOW_GODOT_SETUP: %d\n", result);
	if (result != 0) return 100 + result;
	Error phase2 = Main::setup2(false);
	fprintf(stderr, "HOLLOW_GODOT_SETUP2: %d\n", int(phase2));
	if (phase2 != OK) return 200 + int(phase2);
	fprintf(stderr, "HOLLOW_GODOT_USER_DIR: %s\n", OS::get_singleton()->get_user_data_dir().utf8().get_data());
	result = Main::start();
	fprintf(stderr, "HOLLOW_GODOT_START: %d\n", result);
	if (result != 0) return 300 + result;
	for (int frame = 0; frame < 300; frame++) { if (Main::iteration()) { fprintf(stderr, "HOLLOW_GODOT_FINISHED: %d frames\n", frame); return 0; } }
	fprintf(stderr, "HOLLOW_GODOT_FRAME_LIMIT\n");
	return 2;
}
#endif
