#include "fixture_types.hpp"

#include <rtt/opcua/task_context_proxy.hpp>
#include <rtt/opcua/type_protocol.hpp>

#include <open62541pp/client.hpp>
#include <open62541pp/services/attribute_highlevel.hpp>
#include <open62541pp/services/nodemanagement.hpp>
#include <open62541pp/ua/types.hpp>

#include <rtt/ConnPolicy.hpp>
#include <rtt/InputPort.hpp>
#include <rtt/OperationInterfacePart.hpp>
#include <rtt/OutputPort.hpp>
#include <rtt/Property.hpp>
#include <rtt/base/AttributeBase.hpp>
#include <rtt/internal/DataSource.hpp>
#include <rtt/internal/GlobalEngine.hpp>
#include <rtt/internal/OperationCallerC.hpp>
#include <rtt/os/main.h>
#include <rtt/plugin/PluginLoader.hpp>
#include <rtt/rt_string.hpp>
#include <rtt/typekit/RealTimeTypekit.hpp>
#include <rtt/types/Types.hpp>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

namespace {

using orocos::opcua::fixture::Envelope;
using orocos::opcua::fixture::Point;
using orocos::opcua::fixture::PointArray;

std::string argumentValue(int argc, char **argv, std::string_view name) {
  for (int index = 1; index + 1 < argc; ++index) {
    if (argv[index] == name) {
      return argv[index + 1];
    }
  }
  throw std::runtime_error("missing argument " + std::string(name));
}

void require(bool condition, std::string message) {
  if (!condition) {
    throw std::runtime_error(std::move(message));
  }
}

void loadTypesAndTransports(const std::string &typekit,
                            const std::string &transport) {
  if (RTT::types::Types()->type("Int32") == nullptr &&
      !RTT::types::RealTimeTypekitPlugin().loadTypes()) {
    throw std::runtime_error("unable to load canonical RTT types");
  }
  std::string error;
  if (!RTT::opcua::registerCanonicalTypeProtocols(&error)) {
    throw std::runtime_error(error);
  }
  if (!RTT::plugin::PluginLoader::Instance()->loadLibrary(typekit)) {
    throw std::runtime_error("unable to load fixture typekit: " + typekit);
  }
  if (!RTT::plugin::PluginLoader::Instance()->loadLibrary(transport)) {
    throw std::runtime_error("unable to load fixture transport: " + transport);
  }
}

template <typename Predicate>
bool waitUntil(Predicate predicate, std::chrono::milliseconds timeout =
                                        std::chrono::milliseconds(2000)) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (std::chrono::steady_clock::now() < deadline) {
    if (predicate()) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
  return predicate();
}

template <typename T> bool equalValue(const T &left, const T &right) {
  return left == right;
}

bool equalValue(const RTT::rt_string &left, const RTT::rt_string &right) {
  return std::string_view(left.c_str()) == std::string_view(right.c_str());
}

template <typename Result, typename Argument>
Result callOne(RTT::TaskContext &proxy, const std::string &operation_name,
               const Argument &argument) {
  RTT::OperationInterfacePart *operation =
      proxy.provides()->getOperation(operation_name);
  require(operation != nullptr, "missing operation " + operation_name);
  Result result{};
  RTT::internal::OperationCallerC caller(
      operation, operation_name, RTT::internal::GlobalEngine::Instance());
  caller.argC(argument).ret(result);
  caller.check();
  require(caller.call(), "operation call failed: " + operation_name);
  return result;
}

template <typename Result>
Result callZero(RTT::TaskContext &proxy, const std::string &operation_name) {
  RTT::OperationInterfacePart *operation =
      proxy.provides()->getOperation(operation_name);
  require(operation != nullptr, "missing operation " + operation_name);
  Result result{};
  RTT::internal::OperationCallerC caller(
      operation, operation_name, RTT::internal::GlobalEngine::Instance());
  caller.ret(result);
  caller.check();
  require(caller.call(), "operation call failed: " + operation_name);
  return result;
}

template <typename T>
void exercise(RTT::TaskContext &proxy, const std::string &stem,
              const T &initial, const T &updated, const T &output_value,
              const T &input_value) {
  require(equalValue(callOne<T>(proxy, stem + "Echo", initial), initial),
          stem + " operation round trip failed");

  auto *property = dynamic_cast<RTT::Property<T> *>(
      proxy.provides()->getProperty(stem + "Property"));
  require(property != nullptr, "missing property " + stem);
  require(equalValue(property->get(), initial),
          stem + " initial property mismatch");
  property->set(updated);
  require(equalValue(property->get(), updated),
          stem + " property write failed");

  RTT::base::AttributeBase *attribute =
      proxy.provides()->getAttribute(stem + "Attribute");
  require(attribute != nullptr, "missing attribute " + stem);
  auto *source = RTT::internal::AssignableDataSource<T>::narrow(
      attribute->getDataSource().get());
  require(source != nullptr, "attribute is not writable: " + stem);
  require(equalValue(source->get(), initial),
          stem + " initial attribute mismatch");
  source->set(updated);
  require(equalValue(source->get(), updated), stem + " attribute write failed");

  auto *remote_output = dynamic_cast<RTT::base::OutputPortInterface *>(
      proxy.ports()->getPort(stem + "Output"));
  require(remote_output != nullptr, "missing output port " + stem);
  RTT::InputPort<T> sink(stem + "Sink");
  require(remote_output->createConnection(
              sink, RTT::ConnPolicy::data(RTT::ConnPolicy::LOCK_FREE, false)),
          stem + " output connection failed");
  require(callOne<bool>(proxy, stem + "Emit", output_value),
          stem + " emit operation failed");
  T received{};
  require(waitUntil([&] { return sink.read(received) == RTT::NewData; }),
          stem + " output port timed out");
  require(equalValue(received, output_value),
          stem + " output port value mismatch");

  auto *remote_input = dynamic_cast<RTT::base::InputPortInterface *>(
      proxy.ports()->getPort(stem + "Input"));
  require(remote_input != nullptr, "missing input port " + stem);
  RTT::OutputPort<T> source_port(stem + "Source");
  require(source_port.createConnection(
              *remote_input,
              RTT::ConnPolicy::data(RTT::ConnPolicy::LOCK_FREE, false)),
          stem + " input connection failed");
  require(source_port.write(input_value) == RTT::WriteSuccess,
          stem + " input write failed");
  require(waitUntil([&] {
            return equalValue(callZero<T>(proxy, stem + "Take"), input_value);
          }),
          stem + " input port value mismatch");
}

void verifyCustomNodes(const std::string &endpoint) {
  ::opcua::ClientConfig config;
  config.setTimeout(2000U);
  ::opcua::Client client(std::move(config));
  client.connect(endpoint);
  const auto namespaces = client.namespaceArray();
  const auto found = std::find(namespaces.begin(), namespaces.end(),
                               orocos::opcua::fixture::kNamespaceUri);
  require(found != namespaces.end(), "fixture namespace URI is missing");
  const auto distance = std::distance(namespaces.begin(), found);
  require(distance > 1, "fixture namespace unexpectedly used index 1");
  require(distance <= std::numeric_limits<std::uint16_t>::max(),
          "fixture namespace index overflow");
  const auto namespace_index = static_cast<std::uint16_t>(distance);

  for (const std::string_view name : {"Point", "Envelope"}) {
    const ::opcua::NodeId type_id(namespace_index,
                                  "types/" + std::string(name));
    const ::opcua::NodeId encoding_id(
        namespace_index, "encodings/" + std::string(name) + "/Binary");
    const auto type_class = ::opcua::services::readNodeClass(client, type_id);
    require(type_class && type_class.value() == ::opcua::NodeClass::DataType,
            std::string(name) + " DataType node is missing");
    const auto encoding_class =
        ::opcua::services::readNodeClass(client, encoding_id);
    require(encoding_class &&
                encoding_class.value() == ::opcua::NodeClass::Object,
            std::string(name) + " encoding node is missing");
    const auto definition =
        ::opcua::services::readDataTypeDefinition(client, type_id);
    require(definition && definition.value().isScalar() &&
                definition.value().isType<::opcua::StructureDefinition>(),
            std::string(name) + " datatype definition is missing");
    const auto structure =
        definition.value().scalar<::opcua::StructureDefinition>();
    require(structure.defaultEncodingId() == encoding_id,
            std::string(name) + " encoding NodeId mismatch");
  }
  client.disconnect();
}

} // namespace

int ORO_main(int argc, char **argv) {
  try {
    const std::string typekit = argumentValue(argc, argv, "--typekit");
    const std::string transport = argumentValue(argc, argv, "--transport");
    const std::string endpoint = argumentValue(argc, argv, "--endpoint");

    loadTypesAndTransports(typekit, transport);
    verifyCustomNodes(endpoint);

    RTT::opcua::TaskContextProxyOptions options;
    options.request_timeout = std::chrono::milliseconds(1000);
    options.port_poll_interval = std::chrono::milliseconds(5);
    std::string error;
    auto proxy = RTT::opcua::TaskContextProxy::create(
        endpoint, "fixture/component", options, &error);
    require(proxy != nullptr, error);

    exercise(*proxy, "Float64Array", std::vector<double>{1.25, 2.5},
             std::vector<double>{3.75, 5.0}, std::vector<double>{6.25, 7.5},
             std::vector<double>{8.75, 10.0});
    exercise(*proxy, "Int32Array", std::vector<std::int32_t>{10, 20},
             std::vector<std::int32_t>{30, 40},
             std::vector<std::int32_t>{50, 60},
             std::vector<std::int32_t>{70, 80});
    exercise(*proxy, "StringArray", std::vector<std::string>{"alpha", "beta"},
             std::vector<std::string>{"gamma", "delta"},
             std::vector<std::string>{"epsilon", "zeta"},
             std::vector<std::string>{"eta", "theta"});
    exercise(*proxy, "RtString", RTT::rt_string("initial"),
             RTT::rt_string("updated"), RTT::rt_string("output"),
             RTT::rt_string("input"));
    exercise(*proxy, "Point", Point{1.0, 2.0}, Point{10.0, 20.0},
             Point{30.0, 40.0}, Point{50.0, 60.0});
    exercise(*proxy, "Envelope", Envelope{{3.0, 4.0}, 5},
             Envelope{{10.0, 20.0}, 30}, Envelope{{40.0, 50.0}, 60},
             Envelope{{70.0, 80.0}, 90});
    exercise(*proxy, "PointArray", PointArray{{6.0, 7.0}, {8.0, 9.0}},
             PointArray{{10.0, 11.0}, {12.0, 13.0}},
             PointArray{{14.0, 15.0}, {16.0, 17.0}},
             PointArray{{18.0, 19.0}, {20.0, 21.0}});

    proxy.reset();
    std::cout << "OPC UA external custom datatype fixture passed\n";
    return 0;
  } catch (const std::exception &exception) {
    std::cerr << "fixture-client: " << exception.what() << '\n';
    return 1;
  }
}
