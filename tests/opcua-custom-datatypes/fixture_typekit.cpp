#include "fixture_types.hpp"

#include <rtt/types/SequenceTypeInfo.hpp>
#include <rtt/types/TemplateTypeInfo.hpp>
#include <rtt/types/TypekitPlugin.hpp>
#include <rtt/types/Types.hpp>

#include <string>

namespace orocos::opcua::fixture {
namespace {

class FixtureTypekit final : public RTT::types::TypekitPlugin {
public:
  bool loadTypes() override {
    const RTT::types::TypeInfoRepository::shared_ptr types =
        RTT::types::Types();
    return types->addType(new RTT::types::TemplateTypeInfo<Point, false>(
               std::string(kPointTypeName))) &&
           types->addType(new RTT::types::TemplateTypeInfo<Envelope, false>(
               std::string(kEnvelopeTypeName))) &&
           types->addType(new RTT::types::SequenceTypeInfo<PointArray>(
               std::string(kPointArrayTypeName))) &&
           types->addType(new RTT::types::TemplateTypeInfo<UnsupportedValue,
                                                           false>(
               std::string(kUnsupportedTypeName)));
  }

  bool loadOperators() override { return true; }
  bool loadConstructors() override { return true; }
  bool loadGlobals() override { return true; }

  std::string getName() override { return "orocos-opcua-fixture-types"; }
};

} // namespace
} // namespace orocos::opcua::fixture

ORO_TYPEKIT_PLUGIN(orocos::opcua::fixture::FixtureTypekit)
