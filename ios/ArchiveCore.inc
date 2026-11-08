// Plain C++/stdio: safe before either engine initializes. Reuses the engine's
// bundled MiniZip/zlib; no APK/EXE/native-library code is ever executed.
#include "ArchiveCore.h"
#include "thirdparty/minizip/unzip.h"
#include "thirdparty/minizip/zip.h"
#include <cstdio>
#include <cstring>
#include <set>
#include <limits>

namespace PlayerArchive {
static voidpf ZCALLBACK open_file(voidpf, const void *path, int mode) {
    return std::fopen(static_cast<const char *>(path), mode & ZLIB_FILEFUNC_MODE_CREATE ? "wb+" : "rb");
}
static uLong ZCALLBACK read_file(voidpf, voidpf file, void *buffer, uLong size) { return uLong(std::fread(buffer, 1, size, static_cast<FILE *>(file))); }
static uLong ZCALLBACK write_file(voidpf, voidpf file, const void *buffer, uLong size) { return uLong(std::fwrite(buffer, 1, size, static_cast<FILE *>(file))); }
static ZPOS64_T ZCALLBACK tell_file(voidpf, voidpf file) {
#ifdef _WIN32
    return _ftelli64(static_cast<FILE *>(file));
#else
    return ftello(static_cast<FILE *>(file));
#endif
}
static long ZCALLBACK seek_file(voidpf, voidpf file, ZPOS64_T offset, int origin) {
    if (offset > uint64_t(INT64_MAX)) return -1;
#ifdef _WIN32
    return _fseeki64(static_cast<FILE *>(file), int64_t(offset), origin);
#else
    return fseeko(static_cast<FILE *>(file), off_t(offset), origin);
#endif
}
static int ZCALLBACK close_file(voidpf, voidpf file) { return std::fclose(static_cast<FILE *>(file)); }
static int ZCALLBACK error_file(voidpf, voidpf file) { return std::ferror(static_cast<FILE *>(file)); }
static zlib_filefunc64_def callbacks() {
    zlib_filefunc64_def io = {};
    io.zopen64_file = open_file; io.zread_file = read_file; io.zwrite_file = write_file;
    io.ztell64_file = tell_file; io.zseek64_file = seek_file; io.zclose_file = close_file; io.zerror_file = error_file;
    return io;
}
bool safe_path(const std::string &path) {
    if (path.empty() || path.size() > 16384 || path.front() == '/' || path.find_first_of("\\:") != std::string::npos || path.find('\0') != std::string::npos) return false;
    size_t start = 0;
    while (start < path.size()) {
        size_t end = path.find('/', start); if (end == std::string::npos) end = path.size();
        std::string part = path.substr(start, end - start);
        if (part.empty() || part == "." || part == "..") return false;
        start = end + 1;
    }
    return true;
}
bool list(const std::string &archive, std::vector<Entry> &entries, std::string &error) {
    entries.clear(); auto io = callbacks(); unzFile zip = unzOpen2_64(archive.c_str(), &io);
    if (!zip) { error = "Cannot open ZIP/APK. Split, encrypted, or incomplete downloads may not be supported."; return false; }
    unz_global_info64 global = {}; bool ok = unzGetGlobalInfo64(zip, &global) == UNZ_OK && global.number_entry <= 200000;
    std::set<std::string> names; uint64_t total = 0, metadata = 0;
    int status = unzGoToFirstFile(zip);
    for (uint64_t i = 0; ok && i < global.number_entry; i++) {
        unz_file_info64 info = {};
        ok = status == UNZ_OK && unzGetCurrentFileInfo64(zip, &info, nullptr, 0, nullptr, 0, nullptr, 0) == UNZ_OK;
        if (!ok || info.size_filename == 0 || info.size_filename > 16384) { ok = false; break; }
        metadata += info.size_filename;
        if (metadata > 32 * 1024 * 1024) { ok = false; break; }
        std::vector<char> buffer(info.size_filename + 1);
        ok = unzGetCurrentFileInfo64(zip, &info, buffer.data(), uLong(buffer.size()), nullptr, 0, nullptr, 0) == UNZ_OK;
        std::string name(buffer.data(), info.size_filename);
        bool symlink = ((info.external_fa >> 16) & 0170000) == 0120000;
        if (!ok || !safe_path(name) || !names.insert(name).second || symlink || (info.flag & 1) || (info.compression_method != 0 && info.compression_method != Z_DEFLATED) || info.uncompressed_size > (uint64_t(16) << 30) || total > (uint64_t(32) << 30) - info.uncompressed_size) { ok = false; break; }
        total += info.uncompressed_size;
        unz64_file_pos position = {};
        if (unzGetFilePos64(zip, &position) != UNZ_OK) { ok = false; break; }
        entries.push_back({name, info.uncompressed_size, name.back() == '/', position.pos_in_zip_directory, position.num_of_file});
        status = unzGoToNextFile(zip);
    }
    unzClose(zip);
    if (!ok) { entries.clear(); error = "Unsafe, encrypted, oversized, duplicate, or unsupported ZIP entries. Nothing was installed."; }
    return ok;
}
bool extract(const std::string &archive, const std::string &name, const std::string &destination, uint64_t limit, std::string &error, uint64_t position, uint64_t index) {
    auto io = callbacks(); unzFile zip = unzOpen2_64(archive.c_str(), &io);
    bool opened = false; FILE *output = nullptr; bool ok = zip && safe_path(name);
    if (ok && position != UINT64_MAX) {
        unz64_file_pos entry = {}; entry.pos_in_zip_directory = position; entry.num_of_file = index;
        ok = unzGoToFilePos64(zip, &entry) == UNZ_OK;
    } else if (ok) ok = unzLocateFile(zip, name.c_str(), 1) == UNZ_OK;
    unz_file_info64 info = {};
    if (ok) ok = unzGetCurrentFileInfo64(zip, &info, nullptr, 0, nullptr, 0, nullptr, 0) == UNZ_OK && !(info.flag & 1) && info.uncompressed_size <= limit;
    if (ok) {
        if (info.size_filename != name.size()) ok = false;
        else {
            std::vector<char> actual(name.size() + 1);
            ok = unzGetCurrentFileInfo64(zip, &info, actual.data(), uLong(actual.size()), nullptr, 0, nullptr, 0) == UNZ_OK && std::string(actual.data(), name.size()) == name;
        }
    }
    if (ok) { opened = unzOpenCurrentFile(zip) == UNZ_OK; ok = opened; }
    if (ok) { output = std::fopen(destination.c_str(), "wb"); ok = output != nullptr; }
    std::vector<char> buffer(256 * 1024); uint64_t written = 0;
    while (ok) {
        int count = unzReadCurrentFile(zip, buffer.data(), unsigned(buffer.size()));
        if (count < 0) { ok = false; break; }
        if (count == 0) break;
        if (uint64_t(count) > limit - written || std::fwrite(buffer.data(), 1, count, output) != size_t(count)) { ok = false; break; }
        written += count;
    }
    if (output && std::fclose(output) != 0) ok = false;
    if (opened && unzCloseCurrentFile(zip) != UNZ_OK) ok = false; // CRC integrity.
    if (zip) unzClose(zip);
    if (written != info.uncompressed_size) ok = false;
    if (!ok) { if (output) std::remove(destination.c_str()); error = "ZIP extraction failed (CRC, truncated file, size limit, or insufficient storage)."; }
    return ok;
}
bool create(const std::string &archive, const std::vector<std::string> &paths, const std::vector<std::string> &names, std::string &error) {
    if (paths.size() != names.size() || names.size() > 100000) { error = "Invalid archive file list."; return false; }
    auto io = callbacks(); zipFile zip = zipOpen2_64(archive.c_str(), APPEND_STATUS_CREATE, nullptr, &io);
    bool ok = zip != nullptr; std::set<std::string> seen; std::vector<char> buffer(256 * 1024);
    for (size_t i = 0; ok && i < paths.size(); i++) {
        if (!safe_path(names[i]) || !seen.insert(names[i]).second) { ok = false; break; }
        bool directory = names[i].back() == '/';
        FILE *input = directory ? nullptr : std::fopen(paths[i].c_str(), "rb"); if (!directory && !input) { ok = false; break; }
        zip_fileinfo info = {};
        ok = zipOpenNewFileInZip4_64(zip, names[i].c_str(), &info, nullptr, 0, nullptr, 0, nullptr, Z_DEFLATED, Z_DEFAULT_COMPRESSION, 0, -MAX_WBITS, DEF_MEM_LEVEL, Z_DEFAULT_STRATEGY, nullptr, 0, (3 << 8) | 45, 1 << 11, 1) == ZIP_OK;
        bool opened = ok;
        while (ok && !directory) {
            size_t count = std::fread(buffer.data(), 1, buffer.size(), input);
            if (!count) { if (std::ferror(input)) ok = false; break; }
            ok = zipWriteInFileInZip(zip, buffer.data(), unsigned(count)) == ZIP_OK;
        }
        if (input) std::fclose(input); if (opened && zipCloseFileInZip(zip) != ZIP_OK) ok = false;
    }
    if (zip && zipClose(zip, nullptr) != ZIP_OK) ok = false;
    if (!ok) { std::remove(archive.c_str()); error = "Could not finish archive. Check available storage."; }
    return ok;
}
}
