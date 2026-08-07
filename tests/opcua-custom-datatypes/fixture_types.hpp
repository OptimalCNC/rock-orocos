#pragma once

#include <boost/serialization/nvp.hpp>

#include <compare>
#include <cstdint>
#include <ios>
#include <istream>
#include <locale>
#include <ostream>
#include <string>
#include <string_view>
#include <streambuf>
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

inline bool consumeTrailingWhitespaceAndEnd(std::istream &stream) {
  using traits_type = std::streambuf::traits_type;

  std::streambuf *const buffer = stream.rdbuf();
  const std::ctype<char> &character_type =
      std::use_facet<std::ctype<char>>(stream.getloc());
  std::streambuf::int_type next = buffer->sgetc();
  while (!traits_type::eq_int_type(next, traits_type::eof()) &&
         character_type.is(std::ctype_base::space,
                           traits_type::to_char_type(next))) {
    next = buffer->snextc();
  }
  if (!traits_type::eq_int_type(next, traits_type::eof())) {
    stream.setstate(std::ios::failbit);
    return false;
  }
  return true;
}

inline bool parsePoint(std::istream &stream, Point &value, bool strict_end) {
  Point parsed;
  stream >> std::ws;
  if (!consume(stream, "Point{")) {
    return false;
  }
  if (!(stream >> parsed.x)) {
    return false;
  }
  stream >> std::ws;
  if (!consume(stream, ",")) {
    return false;
  }
  if (!(stream >> parsed.y)) {
    return false;
  }
  stream >> std::ws;
  if (!consume(stream, "}")) {
    return false;
  }
  if (strict_end && !consumeTrailingWhitespaceAndEnd(stream)) {
    return false;
  }
  value = parsed;
  return true;
}

} // namespace detail

inline std::istream &operator>>(std::istream &stream, Point &value) {
  detail::parsePoint(stream, value, true);
  return stream;
}

inline std::istream &operator>>(std::istream &stream, Envelope &value) {
  Envelope parsed;
  stream >> std::ws;
  if (!detail::consume(stream, "Envelope{")) {
    return stream;
  }
  if (!detail::parsePoint(stream, parsed.point, false)) {
    return stream;
  }
  stream >> std::ws;
  if (!detail::consume(stream, ",")) {
    return stream;
  }
  if (!(stream >> parsed.quality)) {
    return stream;
  }
  stream >> std::ws;
  if (!detail::consume(stream, "}")) {
    return stream;
  }
  if (!detail::consumeTrailingWhitespaceAndEnd(stream)) {
    return stream;
  }
  value = parsed;
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
