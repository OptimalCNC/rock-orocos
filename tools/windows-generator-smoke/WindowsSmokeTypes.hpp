#ifndef OROCOS_ROCK_WINDOWS_SMOKE_TYPES_HPP
#define OROCOS_ROCK_WINDOWS_SMOKE_TYPES_HPP

#include <cstdint>

namespace windows_smoke {
struct Sample {
    std::uint32_t sequence;
    double value;
};
}

#endif
