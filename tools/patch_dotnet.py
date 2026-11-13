"""Enable the isolated Mono/Godot proof; ordinary IPA builds do not apply this."""
from pathlib import Path
import argparse
import shutil
from patch_engine import replace

ROOT = Path(__file__).resolve().parents[1]

def patch(engine):
    mono = engine / 'modules/mono'
    shutil.copyfile(ROOT / 'runtime_dotnet/host/hollow_dotnet_host.cpp', mono / 'mono_gd/hollow_dotnet_host.cpp')
    cpp = mono / 'mono_gd/gd_mono.cpp'
    replace(cpp, 'GDMono *GDMono::singleton = nullptr;', '''extern int hollow_dotnet_initialize(const char *, const char *, int, const char **, const char **, void **, unsigned int *);
extern "C" int coreclr_create_delegate(void *, unsigned int, const char *, const char *, const char *, void **);
GDMono *GDMono::singleton = nullptr;''')
    text = cpp.read_text(encoding='utf-8')
    import re
    match = re.search(r'bool load_coreclr\([^)]*\) \{', text)
    if not match: raise RuntimeError('No CoreCLR host anchor')
    text = text[:match.end()] + '''
    coreclr_initialize = &hollow_dotnet_initialize;
    coreclr_create_delegate = &::coreclr_create_delegate;
    return true;
''' + text[match.end():]
    cpp.write_text(text, encoding='utf-8')
    replace(cpp, 'return OS::get_singleton()->has_feature("dotnet");', 'return !String(ProjectSettings::get_singleton()->get_setting("dotnet/project/assembly_name", "")).is_empty();')
    scsub = mono / 'SCsub'
    with scsub.open('a', encoding='utf-8') as target:
        target.write('\nimport os\nenv_mono.Append(CPPPATH=[os.environ["HOLLOW_MONO_NATIVE"] + "/include/mono-2.0"])\nenv_mono.Append(CPPDEFINES=["HOLLOW_DOTNET_PROOF"])\n')
    # The cloned module environment must receive its include flags before files
    # are registered with the builders.
    text = scsub.read_text(encoding='utf-8')
    tail = text[text.index('\nimport os\n'):]
    text = text[:text.index('\nimport os\n')]
    text = text.replace('env_mono = env_modules.Clone()', 'env_mono = env_modules.Clone()' + tail)
    scsub.write_text(text, encoding='utf-8')
    # The proof has a small UIKit entry point and runs the actual engine in
    # headless mode. Keep this change confined to the experimental source tree.
    replace(engine / 'drivers/apple_embedded/SCsub',
            'env_apple_embedded.add_source_files(env_apple_embedded.drivers_sources, "*.swift")',
            '# UIKit proof supplies main; ordinary Hollow builds retain SwiftUI.')

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('engine',type=Path)
    patch(parser.parse_args().engine.resolve())
