#ifndef OROCOS_PACKAGE_SMOKE_TYPES_HPP
#define OROCOS_PACKAGE_SMOKE_TYPES_HPP

#include <cstdint>

namespace package_smoke {
struct Sample {
    std::uint32_t sequence;
    double value;
};
}

#endif
