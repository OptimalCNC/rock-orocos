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
#include <rtt/Service.hpp>
#include <rtt/base/AttributeBase.hpp>
#include <rtt/internal/DataSource.hpp>
#include <rtt/internal/DataSources.hpp>
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

bool hasFlag(int argc, char **argv, std::string_view name) {
  return std::any_of(argv + 1, argv + argc,
                     [name](const char *argument) {
                       return std::string_view(argument) == name;
                     });
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

void verifyTypeInfoContract() {
  const auto point_name =
      std::string(orocos::opcua::fixture::kPointTypeName);
  const auto envelope_name =
      std::string(orocos::opcua::fixture::kEnvelopeTypeName);

  const RTT::types::TypeInfo *point_info = RTT::types::Types()->type(point_name);
  const RTT::types::TypeInfo *envelope_info =
      RTT::types::Types()->type(envelope_name);
  require(point_info != nullptr, "Point TypeInfo is missing");
  require(envelope_info != nullptr, "Envelope TypeInfo is missing");
  require(point_info->getMemberNames() ==
              std::vector<std::string>({"x", "y"}),
          "Point member names mismatch");
  require(envelope_info->getMemberNames() ==
              std::vector<std::string>({"point", "quality"}),
          "Envelope member names mismatch");

  RTT::internal::AssignableDataSource<Point>::shared_ptr point =
      new RTT::internal::ValueDataSource<Point>(Point{1.0, 2.0});
  require(point_info->toString(point) == "Point{1, 2}",
          "Point stream output mismatch");
  require(point_info->fromString("Point{7, 8}", point),
          "Point stream input failed");
  require(point->get() == Point{7.0, 8.0}, "Point stream value mismatch");
  const Point point_before_invalid = point->get();
  require(!point_info->fromString("Point{9, 10}garbage", point),
          "Point trailing input was accepted");
  require(point->get() == point_before_invalid,
          "Point trailing input changed the destination");
  require(!point_info->fromString("Point{9; 10}", point),
          "Point malformed delimiter was accepted");
  require(point->get() == point_before_invalid,
          "Point malformed input changed the destination");

  RTT::internal::AssignableDataSource<Envelope>::shared_ptr envelope =
      new RTT::internal::ValueDataSource<Envelope>(Envelope{{1.0, 2.0}, 3});
  require(envelope_info->toString(envelope) ==
              "Envelope{Point{1, 2}, 3}",
          "Envelope stream output mismatch");
  require(envelope_info->fromString("Envelope{Point{4, 5}, 6}", envelope),
          "Envelope stream input failed");
  require(envelope->get() == Envelope{{4.0, 5.0}, 6},
          "Envelope stream value mismatch");
  const Envelope envelope_before_invalid = envelope->get();
  require(!envelope_info->fromString(
              "Envelope{Point{7, 8}, 9}garbage", envelope),
          "Envelope trailing input was accepted");
  require(envelope->get() == envelope_before_invalid,
          "Envelope trailing input changed the destination");
  require(!envelope_info->fromString("Envelope{Point{7, 8}; 9}", envelope),
          "Envelope malformed delimiter was accepted");
  require(envelope->get() == envelope_before_invalid,
          "Envelope malformed input changed the destination");

  RTT::internal::DataSource<Envelope>::shared_ptr constant =
      new RTT::internal::ConstantDataSource<Envelope>(Envelope{{3.0, 4.0}, 5});
  RTT::base::DataSourceBase::shared_ptr constant_point =
      constant->getMember("point");
  require(constant_point != nullptr, "Envelope constant point is missing");
  RTT::base::DataSourceBase::shared_ptr constant_x =
      constant_point->getMember("x");
  require(constant_x != nullptr, "Envelope constant member is missing");
  auto *readable_x =
      RTT::internal::DataSource<double>::narrow(constant_x.get());
  require(readable_x != nullptr, "Envelope constant member is not readable");
  require(readable_x->get() == 3.0,
          "Envelope constant member has an unexpected value");
  require(!constant_x->isAssignable(),
          "Envelope constant member is unexpectedly writable");
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
Result callOne(RTT::Service &service, const std::string &operation_name,
               const Argument &argument) {
  RTT::OperationInterfacePart *operation =
      service.getOperation(operation_name);
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
Result callZero(RTT::Service &service, const std::string &operation_name) {
  RTT::OperationInterfacePart *operation =
      service.getOperation(operation_name);
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
  RTT::Service &service = *proxy.provides();
  require(equalValue(callOne<T>(service, stem + "Echo", initial), initial),
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

  RTT::base::AttributeBase *constant =
      proxy.provides()->getAttribute(stem + "Constant");
  require(constant != nullptr, "missing constant " + stem);
  auto *constant_source =
      RTT::internal::DataSource<T>::narrow(constant->getDataSource().get());
  require(constant_source != nullptr, "constant has unexpected type: " + stem);
  require(equalValue(constant_source->get(), initial),
          stem + " constant value mismatch");
  require(RTT::internal::AssignableDataSource<T>::narrow(
              constant->getDataSource().get()) == nullptr,
          stem + " constant is unexpectedly writable");

  auto *remote_output = dynamic_cast<RTT::base::OutputPortInterface *>(
      proxy.ports()->getPort(stem + "Output"));
  require(remote_output != nullptr, "missing output port " + stem);
  RTT::InputPort<T> sink(stem + "Sink");
  require(remote_output->createConnection(
              sink, RTT::ConnPolicy::data(RTT::ConnPolicy::LOCK_FREE, false)),
          stem + " output connection failed");
  require(callOne<bool>(service, stem + "Emit", output_value),
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
            return equalValue(callZero<T>(service, stem + "Take"), input_value);
          }),
          stem + " input port value mismatch");
}

std::vector<std::string> operationNames(RTT::Service &service) {
  std::vector<std::string> names = service.getNames();
  std::sort(names.begin(), names.end());
  return names;
}

std::string formatNames(const std::vector<std::string> &names) {
  std::string result;
  for (const std::string &name : names) {
    if (!result.empty()) {
      result += ", ";
    }
    result += name;
  }
  return result;
}

void requireOperationNames(RTT::Service &service,
                           const std::vector<std::string> &expected,
                           const std::string &interface_name) {
  const std::vector<std::string> actual = operationNames(service);
  require(actual == expected,
          interface_name + " operation set mismatch; expected: [" +
              formatNames(expected) + "]; actual: [" + formatNames(actual) +
              "]");
}

const std::vector<std::string> kExpectedOpcUaOperations{
    "endpointUrl",      "isRunning", "lastError",
    "publishComponent", "start",     "unsupportedResources"};

const std::vector<std::string> kExpectedDeployerOperations{
    "activate",
    "addPeer",
    "aliasPeer",
    "cleanup",
    "cleanupComponents",
    "clearConfiguration",
    "configure",
    "configureComponent",
    "configureComponents",
    "connect",
    "connectOperations",
    "connectPeers",
    "connectPorts",
    "connectServices",
    "connectTwoPorts",
    "createStream",
    "displayComponentTypes",
    "error",
    "getComponentTypes",
    "getCpuAffinity",
    "getPeriod",
    "import",
    "inException",
    "inFatalError",
    "inRunTimeError",
    "isActive",
    "isConfigured",
    "isRunning",
    "kickOut",
    "kickOutAll",
    "kickOutComponent",
    "kickStart",
    "loadComponent",
    "loadComponents",
    "loadConfiguration",
    "loadConfigurationString",
    "loadLibrary",
    "loadService",
    "path",
    "recover",
    "reloadLibrary",
    "removePeer",
    "runScript",
    "setActivity",
    "setActivityOnCPU",
    "setCpuAffinity",
    "setFileDescriptorActivity",
    "setMasterSlaveActivity",
    "setPeriod",
    "setPeriodicActivity",
    "setPeriodicActivityOnCPU",
    "setSequentialActivity",
    "setSlaveActivity",
    "setWaitPeriodPolicy",
    "start",
    "startComponent",
    "startComponents",
    "stop",
    "stopComponent",
    "stopComponents",
    "stream",
    "trigger",
    "unloadComponent",
    "unloadComponents",
    "update",
    "waitForInterrupt",
    "waitForSignal"};

void requireConnPolicyArgument(RTT::Service &service,
                               const std::string &operation_name,
                               std::size_t expected_arity) {
  RTT::OperationInterfacePart *operation =
      service.getOperation(operation_name);
  require(operation != nullptr, "missing Deployer operation " + operation_name);
  const std::vector<RTT::ArgumentDescription> arguments =
      operation->getArgumentList();
  require(arguments.size() == expected_arity,
          "unexpected argument count for " + operation_name);
  require(!arguments.empty() && arguments.back().type == "ConnPolicy",
          operation_name + " does not expose its ConnPolicy argument");
}

void verifyDeployerInterface(RTT::TaskContext &deployer) {
  RTT::Service &root = *deployer.provides();
  requireOperationNames(root, kExpectedDeployerOperations, "remote Deployer");
  requireConnPolicyArgument(root, "createStream", 3U);
  requireConnPolicyArgument(root, "connect", 3U);
  requireConnPolicyArgument(root, "stream", 2U);

  RTT::Service::shared_ptr opcua = root.getService("opcua");
  require(opcua != nullptr, "remote Deployer is missing the opcua service");
  requireOperationNames(*opcua, kExpectedOpcUaOperations,
                        "remote opcua service");
  require(callZero<bool>(*opcua, "isRunning"),
          "remote opcua service is not running");
  require(!callZero<std::string>(*opcua, "endpointUrl").empty(),
          "remote opcua endpoint URL is empty");
}

void exerciseSupportedComponent(RTT::TaskContext &proxy) {
  RTT::Service &service = *proxy.provides();
  require(callOne<std::int32_t>(service, "echo", std::int32_t{42}) == 42,
          "built-in echo operation round trip failed");

  auto *gain = dynamic_cast<RTT::Property<std::int32_t> *>(
      service.getProperty("Gain"));
  require(gain != nullptr, "missing writable Gain property");
  gain->set(9);
  require(gain->get() == 9, "Gain property write failed");

  RTT::base::AttributeBase *status = service.getAttribute("Status");
  require(status != nullptr, "missing writable Status attribute");
  auto *status_source = RTT::internal::AssignableDataSource<std::string>::narrow(
      status->getDataSource().get());
  require(status_source != nullptr, "Status attribute is not writable");
  status_source->set("running");
  require(status_source->get() == "running", "Status attribute write failed");

  RTT::base::AttributeBase *limit = service.getAttribute("Limit");
  require(limit != nullptr, "missing read-only Limit constant");
  auto *limit_source = RTT::internal::DataSource<std::int32_t>::narrow(
      limit->getDataSource().get());
  require(limit_source != nullptr && limit_source->get() == 100,
          "Limit constant has an unexpected value");
  require(RTT::internal::AssignableDataSource<std::int32_t>::narrow(
              limit->getDataSource().get()) == nullptr,
          "Limit constant is unexpectedly writable");

  exercise(proxy, "Float64Array", std::vector<double>{1.25, 2.5},
           std::vector<double>{3.75, 5.0},
           std::vector<double>{6.25, 7.5},
           std::vector<double>{8.75, 10.0});
  exercise(proxy, "Int32Array", std::vector<std::int32_t>{10, 20},
           std::vector<std::int32_t>{30, 40},
           std::vector<std::int32_t>{50, 60},
           std::vector<std::int32_t>{70, 80});
  exercise(proxy, "StringArray", std::vector<std::string>{"alpha", "beta"},
           std::vector<std::string>{"gamma", "delta"},
           std::vector<std::string>{"epsilon", "zeta"},
           std::vector<std::string>{"eta", "theta"});
  exercise(proxy, "RtString", RTT::rt_string("initial"),
           RTT::rt_string("updated"), RTT::rt_string("output"),
           RTT::rt_string("input"));
  exercise(proxy, "Point", Point{1.0, 2.0}, Point{10.0, 20.0},
           Point{30.0, 40.0}, Point{50.0, 60.0});
  exercise(proxy, "Envelope", Envelope{{3.0, 4.0}, 5},
           Envelope{{10.0, 20.0}, 30}, Envelope{{40.0, 50.0}, 60},
           Envelope{{70.0, 80.0}, 90});
  exercise(proxy, "PointArray", PointArray{{6.0, 7.0}, {8.0, 9.0}},
           PointArray{{10.0, 11.0}, {12.0, 13.0}},
           PointArray{{14.0, 15.0}, {16.0, 17.0}},
           PointArray{{18.0, 19.0}, {20.0, 21.0}});
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
    const std::string component = argumentValue(argc, argv, "--component");
    const bool standalone = hasFlag(argc, argv, "--standalone");
    const bool deployer_mode = hasFlag(argc, argv, "--deployer");
    const bool probe_only = hasFlag(argc, argv, "--probe-only");
    require(standalone != deployer_mode,
            "select exactly one of --standalone or --deployer");

    loadTypesAndTransports(typekit, transport);
    verifyTypeInfoContract();

    RTT::opcua::TaskContextProxyOptions options;
    options.request_timeout = std::chrono::milliseconds(1000);
    options.port_poll_interval = std::chrono::milliseconds(5);
    std::string error;
    auto create_proxy = [&](const std::string &name) {
      error.clear();
      auto proxy = RTT::opcua::TaskContextProxy::create(endpoint, name, options,
                                                        &error);
      require(proxy != nullptr,
              error.empty() ? "unable to create proxy for " + name : error);
      return proxy;
    };

    if (probe_only) {
      auto proxy = create_proxy(component);
      require(proxy->ready(), "OPC UA probe proxy is not ready");
      std::cout << "OPC UA endpoint probe passed\n";
      return 0;
    }

    verifyCustomNodes(endpoint);
    if (standalone) {
      auto proxy = create_proxy(component);
      exerciseSupportedComponent(*proxy);
    } else {
      auto deployer = create_proxy("Deployer");
      verifyDeployerInterface(*deployer);

      RTT::Service &root = *deployer->provides();
      RTT::Service::shared_ptr opcua = root.getService("opcua");
      require(opcua != nullptr, "remote Deployer is missing the opcua service");

      auto sample = create_proxy(component);
      require(callOne<bool>(*opcua, "publishComponent", component),
              "first repeated publication failed");
      require(callOne<bool>(*opcua, "publishComponent", component),
              "second repeated publication failed");
      exerciseSupportedComponent(*sample);

      require(!callOne<bool>(*opcua, "publishComponent",
                             std::string("unsupported")),
              "unsupported component publication unexpectedly succeeded");
      require(callZero<std::string>(*opcua, "lastError") ==
                  "strict OPC UA publication rejected component 'unsupported'",
              "unexpected strict-publication error");
      const std::vector<std::string> expected_diagnostics{
          "OPC UA: component 'unsupported' rejected property "
          "'UnsupportedProperty' because RTT type "
          "'/orocos/fixture/UnsupportedValue' has no registered OPC UA "
          "protocol."};
      require(callOne<std::vector<std::string>>(
                  *opcua, "unsupportedResources", std::string("unsupported")) ==
                  expected_diagnostics,
              "unexpected unsupported-resource diagnostics");

      require(!callOne<bool>(root, "unloadComponent", component),
              "published component unload unexpectedly succeeded");
      require(callZero<std::string>(*opcua, "lastError") ==
                  "Cannot unload component '" + component +
                      "': it is published through OPC UA",
              "unexpected unload rejection error");
      require(equalValue(callOne<Point>(*sample->provides(), "PointEcho",
                                        Point{90.0, 91.0}),
                         Point{90.0, 91.0}),
              "published component stopped responding after unload rejection");
    }

    std::cout << "OPC UA external custom datatype fixture passed\n";
    return 0;
  } catch (const std::exception &exception) {
    std::cerr << "fixture-client: " << exception.what() << '\n';
    return 1;
  }
}
