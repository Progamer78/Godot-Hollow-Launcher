#include "ArchiveCore.inc"
#include <iostream>
int main(int argc, char **argv) {
    if (argc < 3) return 2;
    std::string error; bool ok = false; std::string action = argv[1];
    if (action == "list") {
        std::vector<PlayerArchive::Entry> entries;
        ok = PlayerArchive::list(argv[2], entries, error);
        if (ok) for (auto &entry : entries) std::cout << entry.size << "\t" << entry.position << "\t" << entry.index << "\t" << entry.name << "\n";
    } else if (action == "extract" && argc == 6) {
        ok = PlayerArchive::extract(argv[2], argv[3], argv[4], std::stoull(argv[5]), error);
    } else if (action == "extract_at" && argc == 8) {
        ok = PlayerArchive::extract(argv[2], argv[3], argv[4], std::stoull(argv[5]), error, std::stoull(argv[6]), std::stoull(argv[7]));
    } else if (action == "create" && argc % 2 == 1) {
        std::vector<std::string> files, names;
        for (int i = 3; i + 1 < argc; i += 2) { files.push_back(argv[i]); names.push_back(argv[i + 1]); }
        ok = PlayerArchive::create(argv[2], files, names, error);
    }
    if (!ok) std::cerr << error << "\n";
    return ok ? 0 : 1;
}
