#pragma once

#include <compare>
#include <cstdint>
#include <ostream>
#include <string_view>
#include <vector>

namespace orocos::opcua::fixture {

inline constexpr std::string_view kProviderName = "orocos-opcua-fixture";
inline constexpr std::string_view kNamespaceUri = "urn:orocos:rtt:fixture";
inline constexpr std::string_view kPointTypeName = "/orocos/fixture/Point";
inline constexpr std::string_view kEnvelopeTypeName =
    "/orocos/fixture/Envelope";
inline constexpr std::string_view kPointArrayTypeName =
    "/orocos/fixture/PointArray";

struct Point {
  double x{0.0};
  double y{0.0};

  auto operator<=>(const Point &) const = default;
};

struct Envelope {
  Point point;
  std::int32_t quality{0};

  auto operator<=>(const Envelope &) const = default;
};

using PointArray = std::vector<Point>;

inline std::ostream &operator<<(std::ostream &stream, const Point &value) {
  return stream << "Point{" << value.x << ", " << value.y << '}';
}

inline std::ostream &operator<<(std::ostream &stream, const Envelope &value) {
  return stream << "Envelope{" << value.point << ", " << value.quality << '}';
}

} // namespace orocos::opcua::fixture
