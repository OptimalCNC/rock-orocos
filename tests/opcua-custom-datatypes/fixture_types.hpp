#pragma once

#include <boost/serialization/nvp.hpp>

#include <compare>
#include <cstdint>
#include <ios>
#include <istream>
#include <ostream>
#include <string>
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
inline constexpr std::string_view kUnsupportedTypeName =
    "/orocos/fixture/UnsupportedValue";

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

struct UnsupportedValue {
  std::int32_t value{0};

  auto operator<=>(const UnsupportedValue &) const = default;
};

namespace detail {

inline bool consume(std::istream &stream, std::string_view expected) {
  for (const char expected_character : expected) {
    char actual_character = '\0';
    if (!stream.get(actual_character) ||
        actual_character != expected_character) {
      stream.setstate(std::ios::failbit);
      return false;
    }
  }
  return true;
}

} // namespace detail

inline std::istream &operator>>(std::istream &stream, Point &value) {
  stream >> std::ws;
  if (!detail::consume(stream, "Point{")) {
    return stream;
  }
  stream >> value.x >> std::ws;
  if (!detail::consume(stream, ",")) {
    return stream;
  }
  stream >> value.y >> std::ws;
  detail::consume(stream, "}");
  return stream;
}

inline std::istream &operator>>(std::istream &stream, Envelope &value) {
  stream >> std::ws;
  if (!detail::consume(stream, "Envelope{")) {
    return stream;
  }
  stream >> value.point >> std::ws;
  if (!detail::consume(stream, ",")) {
    return stream;
  }
  stream >> value.quality >> std::ws;
  detail::consume(stream, "}");
  return stream;
}

inline std::ostream &operator<<(std::ostream &stream, const Point &value) {
  return stream << "Point{" << value.x << ", " << value.y << '}';
}

inline std::ostream &operator<<(std::ostream &stream, const Envelope &value) {
  return stream << "Envelope{" << value.point << ", " << value.quality << '}';
}

inline std::ostream &operator<<(std::ostream &stream,
                                const UnsupportedValue &value) {
  return stream << "UnsupportedValue{" << value.value << '}';
}

} // namespace orocos::opcua::fixture

namespace boost::serialization {

template <class Archive>
void serialize(Archive &archive, orocos::opcua::fixture::Point &value,
               const unsigned int) {
  archive & make_nvp("x", value.x);
  archive & make_nvp("y", value.y);
}

template <class Archive>
void serialize(Archive &archive, orocos::opcua::fixture::Envelope &value,
               const unsigned int) {
  archive & make_nvp("point", value.point);
  archive & make_nvp("quality", value.quality);
}

} // namespace boost::serialization
