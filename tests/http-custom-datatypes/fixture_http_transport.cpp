#include "fixture_types.hpp"
#include <rtt/http/reflected_codec.hpp>
#include <rtt/types/TransportPlugin.hpp>
#include <rtt/types/TypekitPlugin.hpp>
#include <rtt/types/Types.hpp>

namespace fixture {
using namespace orocos::opcua::fixture;
using namespace RTT::http;

template <typename T> bool registerReflected(std::string_view name) {
  auto *type = RTT::types::Types()->type(std::string(name));
  auto protocol = makeReflectedTypeProtocol<T>(type,
      {"orocos.http.fixture", "1", std::string(name), "1", {}, {}, {}});
  return protocol && registerTypeProtocol(type, std::move(protocol));
}

class HttpTransport final : public RTT::types::TransportPlugin {
public:
  bool registerTransport(std::string name, RTT::types::TypeInfo *type) override {
    return (name == kPointTypeName || name == kEnvelopeTypeName || name == kPointArrayTypeName) &&
           static_cast<bool>(registeredTypeCodec(type));
  }
  std::string getTransportName() const override { return "HTTP"; }
  std::string getTypekitName() const override { return "orocos-opcua-fixture-types"; }
  std::string getName() const override { return "HTTP://orocos-fixture-types"; }
};
}

// The standard macro constructs a transport even for getRTTPluginName(). Keep
// that metadata path free of registration side effects. Import first, then
// prepare reflection outside RTT's repository lock. A partial codec failure
// leaves unsupported metadata; returning success retains the DSO containing
// any callbacks already installed in RTT. SDK checks verify required mappings.
extern "C" {
RTT_EXPORT bool loadRTTPlugin(RTT::TaskContext *owner) {
  if (owner) { return false; }
  RTT::types::TypekitRepository::Import(new fixture::HttpTransport());
  try {
    using namespace orocos::opcua::fixture;
    if (!RTT::http::registerCanonicalTypeProtocols()) { return true; }
    if (!fixture::registerReflected<Point>(kPointTypeName)) { return true; }
    if (!fixture::registerReflected<Envelope>(kEnvelopeTypeName)) { return true; }
    fixture::registerReflected<PointArray>(kPointArrayTypeName);
  } catch (...) {
    // Registered codec implementations must remain loaded until RTT teardown.
  }
  return true;
}
RTT_EXPORT std::string getRTTPluginName() { return "HTTP://orocos-fixture-types"; }
RTT_EXPORT std::string getRTTTargetName() { return OROCOS_TARGET_NAME; }
}
