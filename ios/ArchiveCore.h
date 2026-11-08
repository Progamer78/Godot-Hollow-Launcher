#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace PlayerArchive {
struct Entry { std::string name; uint64_t size; bool directory; uint64_t position; uint64_t index; };
bool safe_path(const std::string &path);
bool list(const std::string &archive, std::vector<Entry> &entries, std::string &error);
bool extract(const std::string &archive, const std::string &name, const std::string &destination, uint64_t limit, std::string &error, uint64_t position = UINT64_MAX, uint64_t index = 0);
bool create(const std::string &archive, const std::vector<std::string> &paths, const std::vector<std::string> &names, std::string &error);
}
