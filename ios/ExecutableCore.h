#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>
namespace PlayerExecutable {
bool candidates(const std::vector<uint8_t> &bytes, std::vector<std::array<uint8_t, 32>> &keys, std::string &error);
}
