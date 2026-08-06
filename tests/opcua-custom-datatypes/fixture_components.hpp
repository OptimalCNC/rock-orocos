#pragma once

#include "fixture_types.hpp"

#include <rtt/TaskContext.hpp>

#include <memory>
#include <string>

namespace orocos::opcua::fixture {

class FixtureComponent final : public RTT::TaskContext {
public:
  explicit FixtureComponent(const std::string &name);
  ~FixtureComponent() override;

  FixtureComponent(const FixtureComponent &) = delete;
  FixtureComponent &operator=(const FixtureComponent &) = delete;

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

class UnsupportedComponent final : public RTT::TaskContext {
public:
  explicit UnsupportedComponent(const std::string &name);

private:
  UnsupportedValue value_{42};
};

} // namespace orocos::opcua::fixture
