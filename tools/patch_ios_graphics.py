"""Keep iOS graphics initialization consistent with the selected driver."""
from pathlib import Path


def patch(engine: Path):
    path = engine / "platform/ios/display_layer_ios.mm"
    text = path.read_text(encoding="utf-8")
    start = text.index('\t// Create GL ES 3 context\n')
    end = text.index('\n\tif (![EAGLContext setCurrentContext:context])', start)
    text = text[:start] + '''\t// This layer is created only for the selected opengl3 driver. The
\t// project's saved rendering_method can still be forward_plus or mobile
\t// when --rendering-method selects Compatibility (or Metal falls back).
\tcontext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
\tif (!context) {
\t\tNSLog(@"Failed to create OpenGL ES 3.0 context!");
\t\treturn;
\t}
''' + text[end:]
    path.write_text(text, encoding="utf-8", newline="\n")


def patch_sampler_arrays(engine: Path):
    import shutil
    from patch_engine import replace
    folder = engine / 'servers/rendering'
    shutil.copyfile(Path(__file__).resolve().parents[1] / 'ios/player_sampler_selection.inc', folder / 'player_sampler_selection.inc')
    replace(folder / 'shader_compiler.h', 'StringName current_func_name;',
            'StringName current_func_name;\n\tHashMap<StringName, String> player_sampler_helpers;\n\tint player_sampler_helper_id = 0;')
    replace(folder / 'shader_compiler.cpp', '\t\t\t\t\tcode += "(";\n\n\t\t\t\t\t// if color backbuffer',
            '\t\t\t\t\t#include "player_sampler_selection.inc"\n\t\t\t\t\tcode += "(";\n\n\t\t\t\t\t// if color backbuffer')
    replace(folder / 'shader_compiler.cpp', '\t\tr_to_add += header;',
            '\t\tif (player_sampler_helpers.has(uses_functions[k])) r_to_add += player_sampler_helpers[uses_functions[k]];\n\t\tr_to_add += header;')
    replace(folder / 'shader_compiler.cpp', '\t\t\t\t\t_dump_function_deps(pnode, fnode->name, function_code, r_gen_code.stage_globals[stage], added_funcs_per_stage[stage]);',
            '\t\t\t\t\t_dump_function_deps(pnode, fnode->name, function_code, r_gen_code.stage_globals[stage], added_funcs_per_stage[stage]);\n'
            '\t\t\t\t\tif (player_sampler_helpers.has(fnode->name)) r_gen_code.stage_globals[stage] += player_sampler_helpers[fnode->name];')
    replace(folder / 'shader_compiler.cpp', '\tused_name_defines.clear();',
            '\tplayer_sampler_helpers.clear();\n\tplayer_sampler_helper_id = 0;\n\tused_name_defines.clear();')
