#include "fixture_types.hpp"

#include <rtt/opcua/object_model.hpp>
#include <rtt/opcua/server.hpp>
#include <rtt/opcua/type_protocol.hpp>

#include <rtt/InputPort.hpp>
#include <rtt/OutputPort.hpp>
#include <rtt/TaskContext.hpp>
#include <rtt/os/main.h>
#include <rtt/plugin/PluginLoader.hpp>
#include <rtt/rt_string.hpp>
#include <rtt/typekit/RealTimeTypekit.hpp>
#include <rtt/types/Types.hpp>

#include <atomic>
#include <charconv>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <fstream>
#include <iostream>
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

volatile std::sig_atomic_t stop_requested = 0;

void stopHandler(int) { stop_requested = 1; }

std::string argumentValue(int argc, char **argv, std::string_view name) {
  for (int index = 1; index + 1 < argc; ++index) {
    if (argv[index] == name) {
      return argv[index + 1];
    }
  }
  throw std::runtime_error("missing argument " + std::string(name));
}

std::uint16_t parsePort(const std::string &text) {
  std::uint16_t port{0};
  const auto result =
      std::from_chars(text.data(), text.data() + text.size(), port);
  if (result.ec != std::errc{} || result.ptr != text.data() + text.size() ||
      port == 0U) {
    throw std::runtime_error("invalid --port value: " + text);
  }
  return port;
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

template <typename T> struct Surface {
  Surface(std::string stem, T initial)
      : stem(std::move(stem)), property(initial), attribute(std::move(initial)),
        output(this->stem + "Output"), input(this->stem + "Input") {}

  T echo(T value) { return value; }

  bool emit(T value) { return output.write(value) == RTT::WriteSuccess; }

  T take() {
    T value{};
    static_cast<void>(input.read(value));
    return value;
  }

  std::string stem;
  T property;
  T attribute;
  RTT::OutputPort<T> output;
  RTT::InputPort<T> input;
};

class FixtureComponent final : public RTT::TaskContext {
public:
  FixtureComponent()
      : RTT::TaskContext("fixture/component", RTT::TaskContext::PreOperational),
        float64_array_("Float64Array", {1.25, 2.5}),
        int32_array_("Int32Array", {10, 20}),
        string_array_("StringArray", {"alpha", "beta"}),
        rt_string_("RtString", RTT::rt_string("initial")),
        point_("Point", Point{1.0, 2.0}),
        envelope_("Envelope", Envelope{{3.0, 4.0}, 5}),
        point_array_("PointArray", {{6.0, 7.0}, {8.0, 9.0}}) {
    publish(float64_array_);
    publish(int32_array_);
    publish(string_array_);
    publish(rt_string_);
    publish(point_);
    publish(envelope_);
    publish(point_array_);
  }

private:
  template <typename T> void publish(Surface<T> &surface) {
    addProperty(surface.stem + "Property", surface.property);
    addAttribute(surface.stem + "Attribute", surface.attribute);
    addPort(surface.output);
    addPort(surface.input);
    addOperation(surface.stem + "Echo", &Surface<T>::echo, &surface,
                 RTT::OwnThread)
        .arg("value", "Value to return.");
    addOperation(surface.stem + "Emit", &Surface<T>::emit, &surface,
                 RTT::OwnThread)
        .arg("value", "Value to publish.");
    addOperation(surface.stem + "Take", &Surface<T>::take, &surface,
                 RTT::OwnThread);
  }

  Surface<std::vector<double>> float64_array_;
  Surface<std::vector<std::int32_t>> int32_array_;
  Surface<std::vector<std::string>> string_array_;
  Surface<RTT::rt_string> rt_string_;
  Surface<Point> point_;
  Surface<Envelope> envelope_;
  Surface<PointArray> point_array_;
};

} // namespace

int ORO_main(int argc, char **argv) {
  try {
    const std::string typekit = argumentValue(argc, argv, "--typekit");
    const std::string transport = argumentValue(argc, argv, "--transport");
    const std::string ready_file = argumentValue(argc, argv, "--ready");
    const std::uint16_t port = parsePort(argumentValue(argc, argv, "--port"));

    loadTypesAndTransports(typekit, transport);

    RTT::opcua::ServerOptions server_options;
    server_options.port = port;
    server_options.additional_namespace_uris = {
        "urn:orocos:rtt:fixture:unrelated"};
    RTT::opcua::Server server(server_options);
    std::string error;
    if (!server.start(&error)) {
      throw std::runtime_error(error);
    }

    RTT::opcua::ObjectModelOptions model_options;
    model_options.reconcile_interval = std::chrono::milliseconds(10);
    model_options.warning_sink = [](const std::string &warning) {
      std::cerr << warning << '\n';
    };
    RTT::opcua::ObjectModel model(server, model_options);
    FixtureComponent component;
    auto registration = model.registerComponent(component, &error);
    if (!registration) {
      throw std::runtime_error(error);
    }
    const auto unsupported = model.unsupportedResources(component.getName());
    if (!unsupported.empty()) {
      throw std::runtime_error("fixture component has " +
                               std::to_string(unsupported.size()) +
                               " unsupported resources");
    }

    std::ofstream ready(ready_file, std::ios::trunc);
    if (!ready) {
      throw std::runtime_error("unable to create ready file: " + ready_file);
    }
    ready << server.endpointUrl() << '\n';
    ready.close();

    std::signal(SIGINT, stopHandler);
    std::signal(SIGTERM, stopHandler);
    while (stop_requested == 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    registration->reset();
    server.stop();
    return 0;
  } catch (const std::exception &exception) {
    std::cerr << "fixture-server: " << exception.what() << '\n';
    return 1;
  }
}
