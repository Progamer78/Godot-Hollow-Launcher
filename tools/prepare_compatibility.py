"""Stage pinned built-in LimboAI and read legacy Godot 4 tokenizer buffers."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess

LIMBO_REVISION = "e45e60e976dafab7f2c15cc341ae366e4cf3352b"  # v1.8.1 / Godot 4.7.2


def replace(path, old, new):
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise RuntimeError(f"Compatibility patch anchor mismatch in {path.name}: {old[:60]}")
    path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")


def tokenizer(engine):
    folder = engine / "modules/gdscript"
    header = folder / "gdscript_tokenizer_buffer.h"
    source = folder / "gdscript_tokenizer_buffer.cpp"
    replace(header, "bool multiline_mode = false;", "bool legacy_v100 = false;\n\tbool multiline_mode = false;")
    replace(source, "token.type = (Token::Type)(token_type & TOKEN_MASK);",
            "token.type = (Token::Type)(token_type & TOKEN_MASK);\n"
            "\t// v101 inserted the ellipsis token before COLON. Translate token IDs,\n"
            "\t// preserving their identifier/constant index bits. Never rewrite the PCK.\n"
            "\tif (legacy_v100 && token.type >= Token::PERIOD_PERIOD_PERIOD) token.type = (Token::Type)(token.type + 1);")
    replace(source, 'ERR_FAIL_COND_V_MSG(version != TOKENIZER_VERSION, ERR_INVALID_DATA, "Binary GDScript is not compatible with this engine version.");',
            'ERR_FAIL_COND_V_MSG(version != 100 && version != TOKENIZER_VERSION, ERR_INVALID_DATA, "Unsupported binary GDScript tokenizer version (supported: 100, 101).");\n\tlegacy_v100 = version == 100;')
    replace(source, "int decompressed_size = decode_uint32(&buf[8]);", "int decompressed_size = decode_uint32(&buf[8]);\n\tERR_FAIL_COND_V(decompressed_size < 0 || decompressed_size > 256 * 1024 * 1024, ERR_INVALID_DATA);")
    replace(source, "int total_len = contents.size();", "int total_len = contents.size();\n\tconst int header_size = legacy_v100 ? 20 : 16;\n\tERR_FAIL_COND_V(total_len < header_size, ERR_INVALID_DATA);")
    replace(source, "uint32_t token_count = decode_uint32(&buf[12]);\n\n\tconst uint8_t *b = &buf[16];\n\ttotal_len -= 16;",
            "uint32_t token_count = decode_uint32(&buf[legacy_v100 ? 16 : 12]);\n\n"
            "\tconst uint8_t *b = &buf[header_size];\n\ttotal_len -= header_size;\n"
            "\tERR_FAIL_COND_V(identifier_count > uint32_t(total_len / 4) || constant_count > uint32_t(total_len / 4) || token_line_count > uint32_t(total_len / 16) || token_count > uint32_t(total_len / 5), ERR_INVALID_DATA);")
    replace(source, "uint32_t len = decode_uint32(b);\n\t\ttotal_len -= 4;", "ERR_FAIL_COND_V(total_len < 4, ERR_INVALID_DATA);\n\t\tuint32_t len = decode_uint32(b);\n\t\ttotal_len -= 4;")
    replace(source, "ERR_FAIL_COND_V((len * 4u) > (uint32_t)total_len, ERR_INVALID_DATA);", "ERR_FAIL_COND_V(len > uint32_t(total_len / 4), ERR_INVALID_DATA);")
    replace(source, "int token_len = 5;\n\t\tif ((*b)", "ERR_FAIL_COND_V(total_len < 5, ERR_INVALID_DATA);\n\t\tint token_len = 5;\n\t\tif ((*b)")
    print("Godot 4 legacy script reader: v100/v101 headers and token-ID translation enabled.")


def builtin_extension(engine):
    manager = engine / "core/extension/gdextension_manager.cpp"
    replace(manager, '#include "core/config/engine.h"', '#include "core/config/engine.h"\n#include "modules/modules_enabled.gen.h"')
    replace(manager, '\t\tif (!s.is_empty()) {\n\t\t\tLoadStatus err = load_extension(s);',
            '\t\tif (!s.is_empty()) {\n'
            '#ifdef MODULE_LIMBOAI_ENABLED\n'
            '\t\t\tif (s.ends_with("/limboai.gdextension")) {\n'
            '\t\t\t\tprint_line("Godot Player: LimboAI supplied by the built-in module; imported library is not loaded.");\n'
            '\t\t\t\tcontinue;\n\t\t\t}\n'
            '#endif\n\t\t\tLoadStatus err = load_extension(s);')


def prepare(engine, limbo, report, notice, verify_revision=True):
    target = engine / "modules/limboai"
    if target.exists():
        raise RuntimeError("Use a clean engine tree; LimboAI is already present.")
    if verify_revision:
        actual = subprocess.check_output(["git", "-c", "safe.directory=" + limbo.resolve().as_posix(), "-C", str(limbo), "rev-parse", "HEAD"], text=True).strip()
        if actual != LIMBO_REVISION:
            raise RuntimeError("Unexpected LimboAI revision")
    if not (limbo / "SCsub").is_file() or "LIMBOAI_MODULE" not in (limbo / "SCsub").read_text():
        raise RuntimeError("Expected official LimboAI built-in module sources")
    shutil.copytree(limbo, target, ignore=shutil.ignore_patterns(".git", "godot-cpp", "demo", "tests", ".github"))
    tokenizer(engine)
    builtin_extension(engine)
    notice.parent.mkdir(parents=True, exist_ok=True)
    notice.write_text((limbo / "LICENSE.md").read_text(encoding="utf-8"), encoding="utf-8")
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps({"legacy_tokenizers": [100, 101], "limboai": "1.8.1", "revision": LIMBO_REVISION, "linkage": "static built-in module; imported libraries remain blocked"}, indent=2) + "\n")
    print("Bundled LimboAI 1.8.1:", LIMBO_REVISION)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    parser.add_argument("limbo", type=Path)
    parser.add_argument("--report", type=Path, default=Path("build/compatibility-build.json"))
    parser.add_argument("--notice", type=Path, default=Path("build/COMPATIBILITY-LICENSES.txt"))
    args = parser.parse_args()
    prepare(args.engine.resolve(), args.limbo.resolve(), args.report, args.notice)
