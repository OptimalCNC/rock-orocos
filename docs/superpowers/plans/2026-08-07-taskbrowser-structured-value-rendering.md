# TaskBrowser Structured Value Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OCL TaskBrowser display RTT structures and sequences as bounded,
named values while evaluating a remote structured result exactly once.

**Architecture:** Add an internal OCL renderer that snapshots one RTT data
source, builds a bounded local value tree from RTT member metadata, and formats
that tree without any OPC UA dependency. TaskBrowser delegates non-PropertyBag
results to the renderer; the installed OPC UA fixture verifies that the same
path works across a real `deployer-opcua`/`ctaskbrowser-opcua` connection.

**Tech Stack:** C++20, Orocos RTT/OCL, Boost.Serialization, Boost.Test, Ruby
standard library, CMake, CTest, ASan/UBSan, open62541 `v1.4.15`, and
open62541pp `v0.21.2`.

## Global Constraints

- Work only in
  `/home/liufang/MetaNC/orocos-rock/.worktrees/orocos-opcua-custom-datatypes`
  and its existing nested OCL worktree.
- Install, build, and test only below `/tmp`; never install into or resolve
  packages from `~/.orocos`.
- Do not modify RTT, `rtt_opcua`, open62541, or open62541pp source.
- Do not build open62541 or open62541pp unit tests.
- Keep open62541 at `v1.4.15` and open62541pp at `v0.21.2`.
- Treat the OPC UA address space as a static graph. Do not add unpublish,
  reconciliation, replacement, PubSub, PKI, access-control, or publication
  modes.
- Keep `.types` unchanged and do not add `.type` or `.types <expression>`.
- Preserve expression syntax, assignment behavior, type names, RTT values, and
  OPC UA wire values.
- Render at most 3 sequence elements, structural depth 3, 20 members per
  structure, and 4096 total bytes including the ` = ` prefix.
- Use a 100-printable-character compact threshold and 2-space indentation.
- Every omission must be explicit and every opened delimiter must be closed.
- Keep `RTT::PropertyBag` on its existing specialized TaskBrowser path.
- Preserve the user-owned `docs/src/SUMMARY.md`,
  `docs/src/opcua-web-gateway-plan.md`, and `.tb_history` changes.
- Commit OCL production and unit-test changes inside `toolchain/tools/ocl`.
  Commit fixture and harness changes in the root repository. Do not merge or
  push as part of this plan.

## Execution Environment

Use the already validated temporary RTT/OPC UA prefix and third-party dependency
prefix for focused OCL cycles. Create a new build, install, and home directory:

```bash
cd /home/liufang/MetaNC/orocos-rock/.worktrees/orocos-opcua-custom-datatypes

export OROCOS_RENDER_ROOT
OROCOS_RENDER_ROOT="$(mktemp -d /tmp/orocos-taskbrowser-render.XXXXXX)"

export OROCOS_RENDER_BASE_PREFIX
OROCOS_RENDER_BASE_PREFIX="${OROCOS_RENDER_BASE_PREFIX:-/tmp/orocos-opcua-final-prefix.9IXGem}"

export OROCOS_RENDER_DEPENDENCY_PREFIX
OROCOS_RENDER_DEPENDENCY_PREFIX="${OROCOS_RENDER_DEPENDENCY_PREFIX:-/tmp/orocos-opcua-sdd-deps.vUOKRE/prefix}"

case "$OROCOS_RENDER_ROOT:$OROCOS_RENDER_BASE_PREFIX:$OROCOS_RENDER_DEPENDENCY_PREFIX" in
  /tmp/*:/tmp/*:/tmp/*) ;;
  *) printf '%s\n' "all verification prefixes must be below /tmp" >&2; exit 1 ;;
esac

test -f "$OROCOS_RENDER_BASE_PREFIX/lib/pkgconfig/orocos-rtt-gnulinux.pc"
test -f "$OROCOS_RENDER_BASE_PREFIX/lib/pkgconfig/rtt_opcua-gnulinux.pc"
test -f "$OROCOS_RENDER_DEPENDENCY_PREFIX/lib/cmake/open62541/open62541Config.cmake"
test -f "$OROCOS_RENDER_DEPENDENCY_PREFIX/lib/cmake/open62541pp/open62541ppConfig.cmake"

mkdir -p "$OROCOS_RENDER_ROOT/home"
export HOME="$OROCOS_RENDER_ROOT/home"
export OROCOS_TARGET=gnulinux
export PKG_CONFIG_PATH="$OROCOS_RENDER_BASE_PREFIX/lib/pkgconfig:$OROCOS_RENDER_DEPENDENCY_PREFIX/lib/pkgconfig"
export LD_LIBRARY_PATH="$OROCOS_RENDER_BASE_PREFIX/lib:$OROCOS_RENDER_BASE_PREFIX/lib/orocos/gnulinux:$OROCOS_RENDER_DEPENDENCY_PREFIX/lib"

cmake -S toolchain/tools/ocl -B "$OROCOS_RENDER_ROOT/ocl-build" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$OROCOS_RENDER_ROOT/prefix" \
  -DCMAKE_PREFIX_PATH="$OROCOS_RENDER_BASE_PREFIX;$OROCOS_RENDER_DEPENDENCY_PREFIX" \
  -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF \
  -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
  -DCMAKE_IGNORE_PREFIX_PATH="$HOME/.orocos" \
  -DOROCOS_TARGET=gnulinux \
  -DBUILD_TESTING=ON \
  -DBUILD_TESTS=ON \
  -DBUILD_TASKBROWSER=ON \
  -DBUILD_DEPLOYMENT=ON \
  -DBUILD_OPCUA=ON
```

Expected: configuration uses only the two named `/tmp` dependency prefixes and
creates no file below a login home `.orocos` directory.

## File Map

| File | Responsibility |
| --- | --- |
| `toolchain/tools/ocl/taskbrowser/internal/StructuredValueRenderer.hpp` | Private renderer API, fixed limits, and result status. |
| `toolchain/tools/ocl/taskbrowser/StructuredValueRenderer.cpp` | Snapshot, metadata traversal, layout, and bounded output. |
| `toolchain/tools/ocl/taskbrowser/TaskBrowser.cpp` | Delegate ordinary expression results to the renderer. |
| `toolchain/tools/ocl/taskbrowser/tests/structured_value_renderer_test.cpp` | Direct renderer and TaskBrowser integration regressions. |
| `toolchain/tools/ocl/taskbrowser/tests/CMakeLists.txt` | Build the noninteractive Boost.Test target separately from `taskb`. |
| `tests/opcua-custom-datatypes/fixture_components.cpp` | Add one large PointArray attribute for installed preview validation. |
| `tests/opcua-custom-datatypes/ctaskbrowser_acceptance.rb` | Assert exact named values and bounded large-array output remotely. |
| `tools/test-opcua-custom-datatypes.sh` | Build and run the new OCL test in the isolated full-stack harness. |

---

### Task 1: Add the Snapshot Renderer and Compact Named Values

**Files:**

- Create: `toolchain/tools/ocl/taskbrowser/internal/StructuredValueRenderer.hpp`
- Create: `toolchain/tools/ocl/taskbrowser/StructuredValueRenderer.cpp`
- Create: `toolchain/tools/ocl/taskbrowser/tests/structured_value_renderer_test.cpp`
- Modify: `toolchain/tools/ocl/taskbrowser/tests/CMakeLists.txt`

**Interfaces:**

- Consumes: `RTT::types::TypeInfo::buildValue()`,
  `RTT::base::DataSourceBase::update()`, `getMemberNames()`, and `getMember()`.
- Produces:

  ```cpp
  namespace OCL::detail {
  struct StructuredValueRenderOptions;
  enum class StructuredValueRenderStatus;
  struct StructuredValueRenderResult;

  StructuredValueRenderResult renderStructuredValue(
      RTT::base::DataSourceBase::shared_ptr source,
      const StructuredValueRenderOptions &options = {});
  }
  ```

- Guarantee: for a member-aware type that can build a local value,
  `renderStructuredValue()` resets the source and evaluates it only through one
  `snapshot->update(source.get())` call. It never invokes `source->set()`,
  `source->updated()`, or source-member traversal. A type with no value factory
  retains its legacy scalar stream fallback.

- [ ] **Step 1: Split the existing interactive test from the new unit target**

Replace the source glob in `taskbrowser/tests/CMakeLists.txt` with explicit
targets so the Boost.Test translation unit does not collide with `ORO_main`:

```cmake
CMAKE_DEPENDENT_OPTION(
  BUILD_TASKBROWSER_TEST
  "Build TaskBrowser Test"
  ON
  "BUILD_TASKBROWSER;BUILD_TESTS"
  OFF
)

IF(BUILD_TASKBROWSER_TEST)
  GLOBAL_ADD_TEST(taskb main.cpp)
  program_add_deps(taskb ${OROCOS-RTT_LIBRARIES} orocos-ocl-taskbrowser)

  GLOBAL_ADD_TEST(
    taskbrowser_value_renderer_test
    structured_value_renderer_test.cpp
  )
  program_add_deps(
    taskbrowser_value_renderer_test
    ${OROCOS-RTT_LIBRARIES}
    ${OROCOS-RTT_TYPEKIT_LIBRARIES}
    orocos-ocl-taskbrowser
  )
  set_tests_properties(
    taskbrowser_value_renderer_test
    PROPERTIES
      ENVIRONMENT
        "ORO_TB_HISTFILE=${CMAKE_CURRENT_BINARY_DIR}/taskbrowser-value-renderer.history"
  )
ENDIF()
```

- [ ] **Step 2: Add compact-structure test types and registration**

Start `structured_value_renderer_test.cpp` with a Point, Envelope, and opaque
type whose old stream syntax makes fallback observable:

```cpp
#define BOOST_TEST_MODULE taskbrowser_value_renderer
#include <boost/test/included/unit_test.hpp>

#include "taskbrowser/internal/StructuredValueRenderer.hpp"

#include <boost/serialization/nvp.hpp>
#include <rtt/internal/DataSources.hpp>
#include <rtt/typekit/RealTimeTypekit.hpp>
#include <rtt/types/StructTypeInfo.hpp>
#include <rtt/types/TemplateTypeInfo.hpp>
#include <rtt/types/Types.hpp>

#include <cstdint>
#include <map>
#include <ostream>
#include <string>
#include <utility>
#include <vector>

namespace renderer_test {

struct Point {
  double x{0.0};
  double y{0.0};
};

struct Envelope {
  Point point;
  std::int32_t quality{0};
};

struct Opaque {
  std::int32_t value{0};
};

struct Empty {};

struct TextValue {
  std::string text;
};

std::ostream &operator<<(std::ostream &stream, const Point &value) {
  return stream << "Point{" << value.x << ", " << value.y << '}';
}

std::ostream &operator<<(std::ostream &stream, const Envelope &value) {
  return stream << "Envelope{" << value.point << ", " << value.quality << '}';
}

std::ostream &operator<<(std::ostream &stream, const Opaque &value) {
  return stream << "Opaque{" << value.value << '}';
}

} // namespace renderer_test

namespace boost::serialization {

template <class Archive>
void serialize(Archive &archive, renderer_test::Point &value,
               const unsigned int) {
  archive & make_nvp("x", value.x);
  archive & make_nvp("y", value.y);
}

template <class Archive>
void serialize(Archive &archive, renderer_test::Envelope &value,
               const unsigned int) {
  archive & make_nvp("point", value.point);
  archive & make_nvp("quality", value.quality);
}

template <class Archive>
void serialize(Archive &, renderer_test::Empty &, const unsigned int) {}

template <class Archive>
void serialize(Archive &archive, renderer_test::TextValue &value,
               const unsigned int) {
  archive & make_nvp("text", value.text);
}

} // namespace boost::serialization

namespace {

void loadRendererTypes() {
  auto types = RTT::types::Types();
  if (types->type("Float64") == nullptr) {
    RTT::types::RealTimeTypekitPlugin().loadTypes();
  }
  if (types->type("/test/taskbrowser/Point") == nullptr) {
    BOOST_REQUIRE(types->addType(
        new RTT::types::StructTypeInfo<renderer_test::Point, true>(
            "/test/taskbrowser/Point")));
    BOOST_REQUIRE(types->addType(
        new RTT::types::StructTypeInfo<renderer_test::Envelope, true>(
            "/test/taskbrowser/Envelope")));
    BOOST_REQUIRE(types->addType(
        new RTT::types::TemplateTypeInfo<renderer_test::Opaque, true>(
            "/test/taskbrowser/Opaque")));
    BOOST_REQUIRE(types->addType(
        new RTT::types::StructTypeInfo<renderer_test::Empty, false>(
            "/test/taskbrowser/Empty")));
    BOOST_REQUIRE(types->addType(
        new RTT::types::StructTypeInfo<renderer_test::TextValue, false>(
            "/test/taskbrowser/TextValue")));
  }
}

template <typename T>
RTT::base::DataSourceBase::shared_ptr valueSource(T value) {
  return new RTT::internal::ValueDataSource<T>(std::move(value));
}

} // namespace
```

- [ ] **Step 3: Write failing compact, scalar, and opaque tests**

Add these exact assertions:

```cpp
BOOST_AUTO_TEST_CASE(renders_named_structures_instead_of_stream_operators) {
  loadRendererTypes();
  const auto result = OCL::detail::renderStructuredValue(
      valueSource(renderer_test::Envelope{{3.0, 4.0}, 5}));

  BOOST_TEST(result.status ==
             OCL::detail::StructuredValueRenderStatus::rendered);
  BOOST_TEST(result.text ==
             "{point: {x: 3.0, y: 4.0}, quality: 5}");
}

BOOST_AUTO_TEST_CASE(preserves_a_decimal_marker_for_floating_values) {
  loadRendererTypes();
  BOOST_TEST(OCL::detail::renderStructuredValue(valueSource(3.0F)).text ==
             "3.0");
  BOOST_TEST(OCL::detail::renderStructuredValue(valueSource(-4.0)).text ==
             "-4.0");
  BOOST_TEST(OCL::detail::renderStructuredValue(valueSource(1.25)).text ==
             "1.25");
}

BOOST_AUTO_TEST_CASE(keeps_opaque_stream_representation) {
  loadRendererTypes();
  const auto result = OCL::detail::renderStructuredValue(
      valueSource(renderer_test::Opaque{7}));
  BOOST_TEST(result.text == "Opaque{7}");
}

BOOST_AUTO_TEST_CASE(preserves_scalar_and_hexadecimal_representation) {
  loadRendererTypes();
  BOOST_TEST(OCL::detail::renderStructuredValue(valueSource(true)).text ==
             "true");
  BOOST_TEST(OCL::detail::renderStructuredValue(
                 valueSource(std::string("alpha"))).text == "alpha");
  BOOST_TEST(OCL::detail::renderStructuredValue(valueSource('x')).text ==
             "x");

  OCL::detail::StructuredValueRenderOptions options;
  options.hexadecimal = true;
  BOOST_TEST(OCL::detail::renderStructuredValue(
                 valueSource(std::int32_t{26}), options).text == "1a");
}

BOOST_AUTO_TEST_CASE(renders_an_empty_member_aware_structure) {
  loadRendererTypes();
  BOOST_TEST(OCL::detail::renderStructuredValue(
                 valueSource(renderer_test::Empty{})).text == "{}");
}
```

- [ ] **Step 4: Add a counting source and the one-evaluation test**

Add this read-only source to the anonymous namespace:

```cpp
template <typename T>
class CountingDataSource final : public RTT::internal::DataSource<T> {
public:
  explicit CountingDataSource(T value, bool succeeds = true)
      : value_(std::move(value)), succeeds_(succeeds) {}

  bool evaluate() const override {
    ++evaluation_count_;
    return succeeds_;
  }

  typename RTT::internal::DataSource<T>::result_t get() const override {
    return value_;
  }

  typename RTT::internal::DataSource<T>::result_t value() const override {
    return value_;
  }

  typename RTT::internal::DataSource<T>::const_reference_t
  rvalue() const override {
    return value_;
  }

  CountingDataSource *clone() const override {
    return new CountingDataSource(value_, succeeds_);
  }

  CountingDataSource *copy(
      std::map<const RTT::base::DataSourceBase *,
               RTT::base::DataSourceBase *> &copies) const override {
    const auto existing = copies.find(this);
    if (existing != copies.end()) {
      return static_cast<CountingDataSource *>(existing->second);
    }
    auto *copy = new CountingDataSource(value_, succeeds_);
    copies[this] = copy;
    return copy;
  }

  std::size_t evaluationCount() const { return evaluation_count_; }

private:
  T value_;
  bool succeeds_;
  mutable std::size_t evaluation_count_{0};
};
```

Then assert the root is read once:

```cpp
BOOST_AUTO_TEST_CASE(snapshots_a_structured_source_exactly_once) {
  loadRendererTypes();
  auto source = new CountingDataSource<renderer_test::Envelope>(
      renderer_test::Envelope{{3.0, 4.0}, 5});

  const auto result = OCL::detail::renderStructuredValue(source);

  BOOST_TEST(result.status ==
             OCL::detail::StructuredValueRenderStatus::rendered);
  BOOST_TEST(source->evaluationCount() == 1U);
  BOOST_TEST(result.text ==
             "{point: {x: 3.0, y: 4.0}, quality: 5}");
}
```

Add this assignable probe as well:

```cpp
template <typename T>
class MutationProbeDataSource final
    : public RTT::internal::AssignableDataSource<T> {
public:
  explicit MutationProbeDataSource(T value) : value_(std::move(value)) {}

  bool evaluate() const override {
    ++evaluation_count_;
    return true;
  }

  typename RTT::internal::DataSource<T>::result_t get() const override {
    return value_;
  }

  typename RTT::internal::DataSource<T>::result_t value() const override {
    return value_;
  }

  typename RTT::internal::DataSource<T>::const_reference_t
  rvalue() const override {
    return value_;
  }

  void set(typename RTT::internal::AssignableDataSource<T>::param_t value)
      override {
    ++set_value_count_;
    value_ = value;
  }

  typename RTT::internal::AssignableDataSource<T>::reference_t set() override {
    ++mutable_reference_count_;
    return value_;
  }

  void updated() override { ++updated_count_; }

  MutationProbeDataSource *clone() const override {
    return new MutationProbeDataSource(value_);
  }

  MutationProbeDataSource *copy(
      std::map<const RTT::base::DataSourceBase *,
               RTT::base::DataSourceBase *> &copies) const override {
    const auto existing = copies.find(this);
    if (existing != copies.end()) {
      return static_cast<MutationProbeDataSource *>(existing->second);
    }
    auto *copy = new MutationProbeDataSource(value_);
    copies[this] = copy;
    return copy;
  }

  std::size_t evaluationCount() const { return evaluation_count_; }
  std::size_t setValueCount() const { return set_value_count_; }
  std::size_t mutableReferenceCount() const { return mutable_reference_count_; }
  std::size_t updatedCount() const { return updated_count_; }

private:
  T value_;
  mutable std::size_t evaluation_count_{0};
  std::size_t set_value_count_{0};
  std::size_t mutable_reference_count_{0};
  std::size_t updated_count_{0};
};
```

Assert rendering does not request a mutable source reference or publish a
source update:

```cpp
BOOST_AUTO_TEST_CASE(never_traverses_or_mutates_the_source) {
  loadRendererTypes();
  auto source = new MutationProbeDataSource<renderer_test::Envelope>(
      renderer_test::Envelope{{3.0, 4.0}, 5});

  const auto result = OCL::detail::renderStructuredValue(source);

  BOOST_TEST(result.text ==
             "{point: {x: 3.0, y: 4.0}, quality: 5}");
  BOOST_TEST(source->evaluationCount() == 1U);
  BOOST_TEST(source->setValueCount() == 0U);
  BOOST_TEST(source->mutableReferenceCount() == 0U);
  BOOST_TEST(source->updatedCount() == 0U);
}
```

This catches both direct writes and accidental `getMember()` traversal on the
assignable remote root, because `StructTypeInfo::getMember()` requests the
parent's mutable `set()` reference.

- [ ] **Step 5: Build and verify the test fails before implementation**

```bash
cmake -S toolchain/tools/ocl -B "$OROCOS_RENDER_ROOT/ocl-build"
cmake --build "$OROCOS_RENDER_ROOT/ocl-build" --parallel 2 \
  --target taskbrowser_value_renderer_test
```

Expected: FAIL because
`taskbrowser/internal/StructuredValueRenderer.hpp` and
`renderStructuredValue()` do not exist.

- [ ] **Step 6: Add the private renderer interface**

Create `taskbrowser/internal/StructuredValueRenderer.hpp`:

```cpp
#pragma once

#include <rtt/base/DataSourceBase.hpp>

#include <cstddef>
#include <string>

namespace OCL::detail {

struct StructuredValueRenderOptions {
  std::size_t compact_width{100};
  std::size_t sequence_items{3};
  std::size_t max_structural_depth{3};
  std::size_t structure_members{20};
  std::size_t max_result_bytes{4096};
  std::size_t indentation{2};
  bool hexadecimal{false};
};

enum class StructuredValueRenderStatus {
  rendered,
  evaluation_failed,
};

struct StructuredValueRenderResult {
  StructuredValueRenderStatus status;
  std::string text;
};

StructuredValueRenderResult renderStructuredValue(
    RTT::base::DataSourceBase::shared_ptr source,
    const StructuredValueRenderOptions &options = {});

} // namespace OCL::detail
```

Keep this header under `taskbrowser/internal/`; the existing top-level header
glob must not install it as public OCL API.

- [ ] **Step 7: Implement snapshotting and compact recursive capture**

Create `taskbrowser/StructuredValueRenderer.cpp`. Use one local snapshot for
both metadata traversal and leaf streaming:

```cpp
#include "internal/StructuredValueRenderer.hpp"

#include <rtt/internal/DataSource.hpp>
#include <rtt/internal/DataSources.hpp>
#include <rtt/types/TypeInfo.hpp>

#include <algorithm>
#include <cmath>
#include <optional>
#include <sstream>
#include <utility>
#include <vector>

namespace {

using DataSourcePtr = RTT::base::DataSourceBase::shared_ptr;

struct RenderNode {
  enum class Kind { scalar, structure, sequence, unavailable };
  Kind kind{Kind::scalar};
  std::string scalar;
  std::vector<std::pair<std::string, RenderNode>> children;
  std::size_t omitted{0};
  bool collapsed{false};
};

enum class SnapshotStatus { ready, unavailable, evaluation_failed };

struct SnapshotResult {
  SnapshotStatus status;
  DataSourcePtr value;
};

SnapshotResult snapshot(DataSourcePtr source) {
  if (!source || source->getTypeInfo() == nullptr) {
    return {SnapshotStatus::evaluation_failed, {}};
  }
  source->reset();
  DataSourcePtr local = source->getTypeInfo()->buildValue();
  if (!local || !local->isAssignable()) {
    return {SnapshotStatus::unavailable, {}};
  }
  if (!local->update(source.get())) {
    return {SnapshotStatus::evaluation_failed, {}};
  }
  return {SnapshotStatus::ready, std::move(local)};
}

template <typename T>
std::optional<std::string> floatingText(DataSourcePtr source) {
  auto typed = boost::dynamic_pointer_cast<RTT::internal::DataSource<T>>(source);
  if (!typed) {
    return std::nullopt;
  }
  std::ostringstream stream;
  stream << typed->value();
  std::string text = stream.str();
  if (std::isfinite(typed->value()) &&
      std::floor(typed->value()) == typed->value()) {
    const std::size_t exponent = text.find_first_of("eE");
    if (text.find('.') == std::string::npos) {
      text.insert(exponent == std::string::npos ? text.size() : exponent,
                  ".0");
    }
  }
  return text;
}

std::string scalarText(DataSourcePtr source, bool hexadecimal) {
  if (auto text = floatingText<float>(source)) {
    return *text;
  }
  if (auto text = floatingText<double>(source)) {
    return *text;
  }
  std::ostringstream stream;
  stream << (hexadecimal ? std::hex : std::dec) << source;
  return stream.str();
}

} // namespace
```

Complete the first version of `captureNode()` so an empty member list becomes a
scalar unless `source->getTypeInfo()->getMemberFactory()` is non-null. A member
factory with no names is an empty structure and renders as `{}`. A nonempty
member list becomes a structure whose children are captured in metadata order.
Do not consult `TypeInfo::isStreamable()` when a member factory is present.
Format compact structures as:

```cpp
std::string renderCompact(const RenderNode &node);

std::string renderCompactStructure(const RenderNode &node) {
  std::string output{"{"};
  for (std::size_t index = 0; index < node.children.size(); ++index) {
    if (index != 0U) {
      output += ", ";
    }
    output += node.children[index].first;
    output += ": ";
    output += renderCompact(node.children[index].second);
  }
  output += "}";
  return output;
}
```

Finally implement `renderStructuredValue()` as:

```cpp
StructuredValueRenderResult renderStructuredValue(
    DataSourcePtr source, const StructuredValueRenderOptions &options) {
  try {
    const SnapshotResult local = snapshot(source);
    if (local.status == SnapshotStatus::evaluation_failed) {
      return {StructuredValueRenderStatus::evaluation_failed, {}};
    }
    if (local.status == SnapshotStatus::unavailable) {
      if (!source->evaluate()) {
        return {StructuredValueRenderStatus::evaluation_failed, {}};
      }
      return {StructuredValueRenderStatus::rendered,
              scalarText(source, options.hexadecimal)};
    }
    return {StructuredValueRenderStatus::rendered,
            renderCompact(captureNode(local.value, 1, options))};
  } catch (const std::exception &) {
    return {StructuredValueRenderStatus::evaluation_failed, {}};
  } catch (...) {
    return {StructuredValueRenderStatus::evaluation_failed, {}};
  }
}
```

The `unavailable` branch is only the compatibility fallback for a type that
cannot build a local value. Types with member metadata must build and update a
snapshot; a failed update is an evaluation failure, not an empty structure.

- [ ] **Step 8: Run the focused tests**

```bash
cmake -S toolchain/tools/ocl -B "$OROCOS_RENDER_ROOT/ocl-build"
cmake --build "$OROCOS_RENDER_ROOT/ocl-build" --parallel 2 \
  --target taskbrowser_value_renderer_test
ctest --test-dir "$OROCOS_RENDER_ROOT/ocl-build" \
  --output-on-failure -R '^taskbrowser_value_renderer_test$'
```

Expected: PASS with the exact named Envelope output and evaluation count 1.

- [ ] **Step 9: Commit the compact renderer**

```bash
git -C toolchain/tools/ocl add \
  taskbrowser/internal/StructuredValueRenderer.hpp \
  taskbrowser/StructuredValueRenderer.cpp \
  taskbrowser/tests/structured_value_renderer_test.cpp \
  taskbrowser/tests/CMakeLists.txt
git -C toolchain/tools/ocl diff --cached --check
git -C toolchain/tools/ocl commit -m \
  "feat: render named TaskBrowser structures"
```

---

### Task 2: Bound Sequences, Nesting, Members, and Bytes

**Files:**

- Modify: `toolchain/tools/ocl/taskbrowser/StructuredValueRenderer.cpp`
- Modify: `toolchain/tools/ocl/taskbrowser/tests/structured_value_renderer_test.cpp`

**Interfaces:**

- Consumes: `StructuredValueRenderOptions` and the compact renderer from Task 1.
- Produces: deterministic compact/multiline layout, sequence preview,
  depth/member collapse, `<unavailable>`, and delimiter-safe byte limiting.
- Guarantee: `result.text.size() + std::string(" = ").size()` never exceeds
  `options.max_result_bytes` when that option is at least the fixed omission
  marker and closing delimiters.

- [ ] **Step 1: Add sequence and deep-structure test types**

Extend the test file with these values and Boost.Serialization names:

```cpp
struct Level4 { std::int32_t value{4}; };
struct Level3 { Level4 level4; };
struct Level2 { Level3 level3; };
struct Level1 { Level2 level2; };

struct WideValue {
  std::int32_t m00{0}, m01{1}, m02{2}, m03{3}, m04{4}, m05{5}, m06{6};
  std::int32_t m07{7}, m08{8}, m09{9}, m10{10}, m11{11}, m12{12}, m13{13};
  std::int32_t m14{14}, m15{15}, m16{16}, m17{17}, m18{18}, m19{19}, m20{20};
};
```

Register `/test/taskbrowser/PointArray` with
`RTT::types::SequenceTypeInfo<std::vector<renderer_test::Point>>`, register each
Level type and WideValue with `StructTypeInfo<..., false>`, and serialize every
field with its exact name. Add `<rtt/types/SequenceTypeInfo.hpp>` and use these
registrations inside `loadRendererTypes()`:

```cpp
BOOST_REQUIRE(types->addType(
    new RTT::types::SequenceTypeInfo<std::vector<renderer_test::Point>>(
        "/test/taskbrowser/PointArray")));
BOOST_REQUIRE(types->addType(
    new RTT::types::StructTypeInfo<renderer_test::Level4, false>(
        "/test/taskbrowser/Level4")));
BOOST_REQUIRE(types->addType(
    new RTT::types::StructTypeInfo<renderer_test::Level3, false>(
        "/test/taskbrowser/Level3")));
BOOST_REQUIRE(types->addType(
    new RTT::types::StructTypeInfo<renderer_test::Level2, false>(
        "/test/taskbrowser/Level2")));
BOOST_REQUIRE(types->addType(
    new RTT::types::StructTypeInfo<renderer_test::Level1, false>(
        "/test/taskbrowser/Level1")));
BOOST_REQUIRE(types->addType(
    new RTT::types::StructTypeInfo<renderer_test::WideValue, false>(
        "/test/taskbrowser/WideValue")));
```

The four level serializers each expose their one named member:

```cpp
archive & make_nvp("value", value.value);   // Level4
archive & make_nvp("level4", value.level4); // Level3
archive & make_nvp("level3", value.level3); // Level2
archive & make_nvp("level2", value.level2); // Level1
```

The WideValue archive must contain all 21 calls:

```cpp
archive & make_nvp("m00", value.m00);
archive & make_nvp("m01", value.m01);
archive & make_nvp("m02", value.m02);
archive & make_nvp("m03", value.m03);
archive & make_nvp("m04", value.m04);
archive & make_nvp("m05", value.m05);
archive & make_nvp("m06", value.m06);
archive & make_nvp("m07", value.m07);
archive & make_nvp("m08", value.m08);
archive & make_nvp("m09", value.m09);
archive & make_nvp("m10", value.m10);
archive & make_nvp("m11", value.m11);
archive & make_nvp("m12", value.m12);
archive & make_nvp("m13", value.m13);
archive & make_nvp("m14", value.m14);
archive & make_nvp("m15", value.m15);
archive & make_nvp("m16", value.m16);
archive & make_nvp("m17", value.m17);
archive & make_nvp("m18", value.m18);
archive & make_nvp("m19", value.m19);
archive & make_nvp("m20", value.m20);
```

- [ ] **Step 2: Write failing sequence preview tests**

Use `PointArray = std::vector<renderer_test::Point>` and assert:

```cpp
BOOST_AUTO_TEST_CASE(previews_zero_one_three_and_four_sequence_items) {
  loadRendererTypes();
  using PointArray = std::vector<renderer_test::Point>;

  BOOST_TEST(OCL::detail::renderStructuredValue(valueSource(PointArray{})).text ==
             "[]");
  BOOST_TEST(OCL::detail::renderStructuredValue(
                 valueSource(PointArray{{1.0, 2.0}})).text ==
             "[[0]: {x: 1.0, y: 2.0}]");
  BOOST_TEST(OCL::detail::renderStructuredValue(
                 valueSource(PointArray{{1.0, 2.0}, {3.0, 4.0},
                                        {5.0, 6.0}})).text ==
             "[[0]: {x: 1.0, y: 2.0}, [1]: {x: 3.0, y: 4.0}, "
             "[2]: {x: 5.0, y: 6.0}]");

  const auto four = OCL::detail::renderStructuredValue(valueSource(PointArray{
      {1.0, 2.0}, {3.0, 4.0}, {5.0, 6.0}, {7.0, 8.0}}));
  BOOST_TEST(four.text.find("[3]") == std::string::npos);
  BOOST_TEST(four.text.find("... 1 items omitted") != std::string::npos);
}
```

Add a 1000-element PointArray test. Its complete bounded representation remains
compact because the approved preview is 95 characters including ` = `:

```text
[[0]: {x: 1.0, y: 2.0}, [1]: {x: 3.0, y: 4.0}, [2]: {x: 5.0, y: 6.0}, ... 997 items omitted]
```

The test must compare that exact string. Multiline layout is covered separately
by the 101-character and WideValue tests.

- [ ] **Step 3: Write failing layout, depth, and member-limit tests**

Add exact assertions:

```cpp
BOOST_AUTO_TEST_CASE(collapses_structural_depth_four) {
  loadRendererTypes();
  const auto result = OCL::detail::renderStructuredValue(
      valueSource(renderer_test::Level1{}));
  BOOST_TEST(result.text ==
             "{level2: {level3: {level4: {...}}}}");
}

BOOST_AUTO_TEST_CASE(limits_a_structure_to_twenty_members) {
  loadRendererTypes();
  const auto result = OCL::detail::renderStructuredValue(
      valueSource(renderer_test::WideValue{}));
  BOOST_TEST(result.text.find("m19: 19") != std::string::npos);
  BOOST_TEST(result.text.find("m20: 20") == std::string::npos);
  BOOST_TEST(result.text.find("... 1 members omitted") != std::string::npos);
  BOOST_TEST(result.text.find('\n') != std::string::npos);
}
```

Use the already registered `TextValue` for the exact boundary. The compact form
is `{text: VALUE}`, so 89 content bytes produce a 100-byte ` = <value>` and 90
produce 101 bytes:

```cpp
BOOST_AUTO_TEST_CASE(switches_to_multiline_above_one_hundred_characters) {
  loadRendererTypes();
  const auto at_limit = OCL::detail::renderStructuredValue(
      valueSource(renderer_test::TextValue{std::string(89, 'a')}));
  const auto above_limit = OCL::detail::renderStructuredValue(
      valueSource(renderer_test::TextValue{std::string(90, 'a')}));

  BOOST_TEST(at_limit.text.find('\n') == std::string::npos);
  BOOST_TEST(at_limit.text.size() + 3U == 100U);
  BOOST_TEST(above_limit.text ==
             "{\n  text: " + std::string(90, 'a') + "\n}");
}
```

- [ ] **Step 4: Write failing unavailable-member and byte-budget tests**

Subclass `ValueDataSource<Envelope>` only for direct local-tree testing:

```cpp
class MissingQualityDataSource final
    : public RTT::internal::ValueDataSource<renderer_test::Envelope> {
public:
  using RTT::internal::ValueDataSource<renderer_test::Envelope>::ValueDataSource;

  RTT::base::DataSourceBase::shared_ptr
  getMember(const std::string &name) override {
    if (name == "quality") {
      return {};
    }
    return RTT::internal::ValueDataSource<renderer_test::Envelope>::getMember(name);
  }
};
```

Expose a second private-header entry point used only after snapshot creation:

```cpp
std::string renderStructuredSnapshotForTest(
    RTT::base::DataSourceBase::shared_ptr snapshot,
    const StructuredValueRenderOptions &options = {});
```

It must call the same capture/layout implementation as
`renderStructuredValue()` and must never evaluate the supplied snapshot. Test:

```cpp
BOOST_AUTO_TEST_CASE(continues_after_an_unavailable_member) {
  loadRendererTypes();
  auto snapshot = new MissingQualityDataSource(
      renderer_test::Envelope{{3.0, 4.0}, 5});
  BOOST_TEST(OCL::detail::renderStructuredSnapshotForTest(snapshot) ==
             "{point: {x: 3.0, y: 4.0}, quality: <unavailable>}");
}
```

For the byte budget, render
`renderer_test::TextValue{std::string(6000, 'x')}`. Assert all of the following:

```cpp
bool balancedDelimiters(const std::string &text) {
  std::vector<char> open;
  for (const char character : text) {
    if (character == '{' || character == '[') {
      open.push_back(character);
    } else if (character == '}' || character == ']') {
      if (open.empty()) {
        return false;
      }
      const char expected = character == '}' ? '{' : '[';
      if (open.back() != expected) {
        return false;
      }
      open.pop_back();
    }
  }
  return open.empty();
}

const auto result = OCL::detail::renderStructuredValue(
    valueSource(renderer_test::TextValue{std::string(6000, 'x')}));
BOOST_TEST(result.text.size() + 3U <= 4096U);
BOOST_TEST(result.text.find("bytes omitted") != std::string::npos);
BOOST_TEST(result.text.front() == '{');
BOOST_TEST(result.text.back() == '}');
BOOST_TEST(balancedDelimiters(result.text));

const std::regex omitted_pattern(R"(\.\.\. ([0-9]+) bytes omitted)");
std::smatch omitted_match;
BOOST_REQUIRE(std::regex_search(result.text, omitted_match, omitted_pattern));
const std::size_t value_begin = result.text.find("text: ") + 6U;
const std::size_t marker_begin =
    static_cast<std::size_t>(omitted_match.position(0));
const std::size_t retained = marker_begin - value_begin;
const std::size_t omitted =
    static_cast<std::size_t>(std::stoull(omitted_match.str(1)));
BOOST_TEST(retained + omitted == 6000U);
```

Add `<regex>` to the test includes. Exercise structural truncation with the
existing WideValue and a deliberately small valid budget:

```cpp
OCL::detail::StructuredValueRenderOptions small_budget;
small_budget.max_result_bytes = 80;
const auto bounded = OCL::detail::renderStructuredValue(
    valueSource(renderer_test::WideValue{}), small_budget);
BOOST_TEST(bounded.text.size() + 3U <= 80U);
BOOST_TEST(bounded.text.find("... output omitted") != std::string::npos);
BOOST_TEST(balancedDelimiters(bounded.text));
```

- [ ] **Step 5: Run the expanded tests and observe the missing limits**

```bash
cmake --build "$OROCOS_RENDER_ROOT/ocl-build" --parallel 2 \
  --target taskbrowser_value_renderer_test
ctest --test-dir "$OROCOS_RENDER_ROOT/ocl-build" \
  --output-on-failure -R '^taskbrowser_value_renderer_test$'
```

Expected: FAIL because Task 1 treats sequences as ordinary structures, has no
layout switch, and does not enforce depth, member, or byte limits.

- [ ] **Step 6: Classify sequences and capture only the approved preview**

In `StructuredValueRenderer.cpp`, classify a local node as a sequence only when
its metadata contains both `size` and `capacity` and its `size` member narrows
to `RTT::internal::DataSource<int>`. Read that local size once. Capture indexes
with `ConstantDataSource<unsigned int>`:

```cpp
auto index = new RTT::internal::ConstantDataSource<unsigned int>(i);
DataSourcePtr element =
    source->getMember(index, RTT::base::DataSourceBase::shared_ptr{});
```

Capture indexes `0..min(size, options.sequence_items)-1`; set
`node.omitted = size - captured`. Do not also capture the metadata-only `size`
and `capacity` members. Empty sequences become a sequence node with no children
and render as `[]`.

- [ ] **Step 7: Enforce structural depth and member limits during capture**

Pass structural depth explicitly:

```cpp
RenderNode captureNode(DataSourcePtr source, std::size_t structural_depth,
                       const StructuredValueRenderOptions &options);
```

Classify the node before checking depth. If a structure or sequence has
`structural_depth > options.max_structural_depth`, set `collapsed = true` and
do not resolve its children. Render collapsed structures as `{...}` and
collapsed sequences as `[...]`.

For structures, copy at most `options.structure_members` metadata names, retain
their order, and set `omitted` to the remaining count. A null or throwing
member lookup produces a child with `Kind::unavailable` and text
`<unavailable>`; it does not stop sibling capture.

- [ ] **Step 8: Add deterministic compact and multiline layout**

Implement both layouts from the captured tree without touching a data source:

```cpp
std::string renderCompact(const RenderNode &node);
std::string renderMultiline(const RenderNode &node, std::size_t depth,
                            std::size_t indentation);
```

The compact sequence syntax is `[[0]: value, [1]: value]`. The multiline
syntax puts one child or omission marker per line, indents children by exactly
`options.indentation`, and places closing delimiters at the parent's indent.

Generate the bounded compact candidate first. Keep it only when its printable
length plus the 3-byte ` = ` prefix is at most `options.compact_width` and no
descendant is already multiline. Otherwise use multiline layout. Do not inspect
terminal width or environment variables.

- [ ] **Step 9: Apply a delimiter-aware 4096-byte budget**

Render the chosen tree through a budget writer that receives
`options.max_result_bytes - 3`. Before writing a child, reserve bytes for:

1. the current node's closing delimiter;
2. every ancestor closing delimiter;
3. either that complete child or `... output omitted` plus its separator.

If a complete structural child cannot fit, emit `... output omitted` at the
current level and close all delimiters. For an oversized scalar, capture its
existing stream representation first and shorten it with this stable loop:

```cpp
std::string truncateScalar(const std::string &text, std::size_t budget) {
  std::size_t prefix = budget;
  for (;;) {
    const std::size_t omitted = text.size() - std::min(prefix, text.size());
    const std::string marker =
        "... " + std::to_string(omitted) + " bytes omitted";
    const std::size_t next = budget > marker.size() ? budget - marker.size() : 0;
    if (next == prefix) {
      return text.substr(0, prefix) + marker;
    }
    prefix = next;
  }
}
```

Account for separators and closing delimiters before passing the scalar budget,
so the final result including ` = ` is never larger than 4096 bytes.

- [ ] **Step 10: Run all renderer tests**

```bash
cmake --build "$OROCOS_RENDER_ROOT/ocl-build" --parallel 2 \
  --target taskbrowser_value_renderer_test
ctest --test-dir "$OROCOS_RENDER_ROOT/ocl-build" \
  --output-on-failure -R '^taskbrowser_value_renderer_test$'
```

Expected: PASS for sequences of 0/1/3/4/1000 elements, depth 3, the 20-member
limit, exact compact/multiline boundary, inaccessible members, and both budget
paths.

- [ ] **Step 11: Commit bounded rendering**

```bash
git -C toolchain/tools/ocl add \
  taskbrowser/StructuredValueRenderer.cpp \
  taskbrowser/internal/StructuredValueRenderer.hpp \
  taskbrowser/tests/structured_value_renderer_test.cpp
git -C toolchain/tools/ocl diff --cached --check
git -C toolchain/tools/ocl commit -m \
  "feat: bound TaskBrowser structured output"
```

---

### Task 3: Integrate the Renderer into TaskBrowser

**Files:**

- Modify: `toolchain/tools/ocl/taskbrowser/TaskBrowser.cpp`
- Modify: `toolchain/tools/ocl/taskbrowser/tests/structured_value_renderer_test.cpp`

**Interfaces:**

- Consumes: `OCL::detail::renderStructuredValue()` from Tasks 1-2.
- Produces: `TaskBrowser::printResult()` output beginning with exactly ` = `,
  followed by the bounded renderer text or `(evaluation failed)`.
- Preserves: the current recursive/nonrecursive PropertyBag presentation and
  public `TaskBrowser::printResult()` signature.

- [ ] **Step 1: Add a TaskBrowser output probe**

Add to the test file:

```cpp
#include "taskbrowser/TaskBrowser.hpp"
#include <rtt/PropertyBag.hpp>
#include <rtt/TaskContext.hpp>

class TaskBrowserProbe final : public OCL::TaskBrowser {
public:
  explicit TaskBrowserProbe(RTT::TaskContext *task)
      : OCL::TaskBrowser(task) {
    setColorTheme(nocolors);
  }

  std::string render(RTT::base::DataSourceBase::shared_ptr source,
                     bool recurse = true) {
    sresult.str("");
    sresult.clear();
    printResult(source.get(), recurse);
    return sresult.str();
  }
};
```

- [ ] **Step 2: Write failing TaskBrowser integration tests**

Add one fixture that owns a single `RTT::TaskContext` and `TaskBrowserProbe`,
then assert:

```cpp
BOOST_FIXTURE_TEST_CASE(taskbrowser_prints_the_exact_named_value,
                        TaskBrowserFixture) {
  auto source = valueSource(renderer_test::Envelope{{3.0, 4.0}, 5});
  BOOST_TEST(browser.render(source) ==
             " = {point: {x: 3.0, y: 4.0}, quality: 5}");
}

BOOST_FIXTURE_TEST_CASE(taskbrowser_reads_a_structured_root_once,
                        TaskBrowserFixture) {
  auto source = new CountingDataSource<renderer_test::Envelope>(
      renderer_test::Envelope{{3.0, 4.0}, 5});
  BOOST_TEST(browser.render(source) ==
             " = {point: {x: 3.0, y: 4.0}, quality: 5}");
  BOOST_TEST(source->evaluationCount() == 1U);
}

BOOST_FIXTURE_TEST_CASE(taskbrowser_reports_a_failed_root_snapshot,
                        TaskBrowserFixture) {
  auto source = new CountingDataSource<renderer_test::Envelope>(
      renderer_test::Envelope{}, false);
  BOOST_TEST(browser.render(source) == " = (evaluation failed)");
  BOOST_TEST(source->evaluationCount() == 1U);
}
```

Add a `PropertyBag` regression with one owned property:

```cpp
BOOST_FIXTURE_TEST_CASE(property_bags_keep_the_specialized_display,
                        TaskBrowserFixture) {
  RTT::PropertyBag bag;
  bag.ownProperty(new RTT::Property<std::int32_t>("answer", "", 42));
  auto source = valueSource(bag);

  const std::string summary = browser.render(source, false);
  BOOST_TEST(summary.find("1") != std::string::npos);
  BOOST_TEST(summary.find("Properties") != std::string::npos);

  const std::string expanded = browser.render(source, true);
  BOOST_TEST(expanded.find("answer") != std::string::npos);
  BOOST_TEST(expanded.find("42") != std::string::npos);
}
```

Add `<rtt/Property.hpp>` to the test includes. This prevents renderer
integration from absorbing the specialized bag path.

- [ ] **Step 3: Run the integration tests and observe legacy output**

```bash
cmake --build "$OROCOS_RENDER_ROOT/ocl-build" --parallel 2 \
  --target taskbrowser_value_renderer_test
ctest --test-dir "$OROCOS_RENDER_ROOT/ocl-build" \
  --output-on-failure -R '^taskbrowser_value_renderer_test$'
```

Expected: FAIL because `TaskBrowser::doPrint()` still prefers streamable custom
types and `printResult()` still leaves a width of 20 on the output stream.

- [ ] **Step 4: Delegate ordinary results to the renderer**

Include the private renderer header in `TaskBrowser.cpp`. Change
`printResult()` so it writes the prefix without field width state:

```cpp
void TaskBrowser::printResult(base::DataSourceBase *ds, bool recurse) {
  sresult << " = ";
  if (ds) {
    doPrint(ds, recurse);
  } else {
    sresult << "(null)";
  }
  sresult << right;
}
```

Keep the current PropertyBag branch at the top of `doPrint()`. It may reset and
evaluate its bag source as it does today. Replace the legacy streamable/member
recursion branch with:

```cpp
detail::StructuredValueRenderOptions options;
options.hexadecimal = usehex;
const detail::StructuredValueRenderResult result =
    detail::renderStructuredValue(ds, options);
if (result.status == detail::StructuredValueRenderStatus::evaluation_failed) {
  sresult << "(evaluation failed)";
  return;
}
sresult << result.text;
```

Do not call `ds->evaluate()` before `renderStructuredValue()`. Remove the old
recursive structure/sequence loop so no path resolves members on the remote
source.

- [ ] **Step 5: Verify renderer, legacy TaskBrowser, and OCL policy tests**

```bash
cmake --build "$OROCOS_RENDER_ROOT/ocl-build" --parallel 2 \
  --target taskbrowser_value_renderer_test taskb rtlog_policy_test
ctest --test-dir "$OROCOS_RENDER_ROOT/ocl-build" \
  --output-on-failure \
  -R '^(taskbrowser_value_renderer_test|taskb|rtlog_policy_test)$'
```

Expected: all three tests pass. The noninteractive renderer test must not write
history into the real home directory.

- [ ] **Step 6: Commit TaskBrowser integration**

```bash
git -C toolchain/tools/ocl add \
  taskbrowser/TaskBrowser.cpp \
  taskbrowser/tests/structured_value_renderer_test.cpp
git -C toolchain/tools/ocl diff --cached --check
git -C toolchain/tools/ocl commit -m \
  "feat: use structured renderer in TaskBrowser"
```

---

### Task 4: Verify Installed OPC UA Values and the Full Temporary Build

**Files:**

- Modify: `tests/opcua-custom-datatypes/fixture_components.cpp`
- Modify: `tests/opcua-custom-datatypes/ctaskbrowser_acceptance.rb`
- Modify: `tools/test-opcua-custom-datatypes.sh`

**Interfaces:**

- Consumes: the installed OCL renderer, existing fixture typekit/transport,
  `deployer-opcua`, and `ctaskbrowser-opcua`.
- Produces: a `LargePointArrayAttribute` containing 1000 Points and exact
  two-process acceptance evidence for compact, nested, and truncated values.
- Guarantee: the harness uses a new `/tmp` prefix and temporary `HOME`, scans
  its evidence for `.orocos` contamination, and leaves third-party tests
  disabled.

- [ ] **Step 1: Add one large fixture attribute**

In `fixture_components.cpp`, add:

```cpp
PointArray makeLargePointArray() {
  PointArray points;
  points.reserve(1000);
  for (std::size_t index = 0; index < 1000; ++index) {
    const double x = static_cast<double>(index * 2 + 1);
    points.push_back(Point{x, x + 1.0});
  }
  return points;
}
```

Initialize `large_point_array` with that helper, add only one attribute, and
declare the storage beside the other surfaces:

```cpp
explicit Impl(FixtureComponent &owner)
    : float64_array("Float64Array", {1.25, 2.5}),
      int32_array("Int32Array", {10, 20}),
      string_array("StringArray", {"alpha", "beta"}),
      rt_string("RtString", RTT::rt_string("initial")),
      point("Point", Point{1.0, 2.0}),
      envelope("Envelope", Envelope{{3.0, 4.0}, 5}),
      point_array("PointArray", {{6.0, 7.0}, {8.0, 9.0}}),
      large_point_array(makeLargePointArray()) {
  owner.addProperty("Gain", gain);
  owner.addAttribute("Status", status);
  owner.addConstant("Limit", limit);
  owner.addOperation("echo", &Impl::echo, this, RTT::OwnThread)
      .arg("value", "Value to return.");

  publishSurface(owner, float64_array);
  publishSurface(owner, int32_array);
  publishSurface(owner, string_array);
  publishSurface(owner, rt_string);
  publishSurface(owner, point);
  publishSurface(owner, envelope);
  publishSurface(owner, point_array);
  owner.addAttribute("LargePointArrayAttribute", large_point_array);
}

PointArray large_point_array;
```

Do not add a property, constant, port, or operation for this large value.

- [ ] **Step 2: Update acceptance expectations for named rendering**

In `ctaskbrowser_acceptance.rb`, replace the positional Point, Envelope, and
PointArray patterns with exact structural patterns:

First make the scalar helper enforce, rather than merely allow, the decimal
marker and rename its keyword at every call site:

```ruby
def scalar_result_pattern(value, require_zero_decimal:)
  suffix = require_zero_decimal ? "\\.0+" : ""
  /^[ \t]*=[ \t]*#{Regexp.escape(value.to_s)}#{suffix}[ \t]*$/
end
```

The helper self-check must accept ` = 10.0` and reject ` = 10` for a floating
expectation. Integral expectations continue to accept only the integral form.

```ruby
expect_segment(
  first, "PointAttribute",
  /^[ \t]*=[ \t]*\{x: 10\.0, y: 20\.0\}[ \t]*$/,
  first_transcript
)
expect_segment(
  first, "EnvelopeAttribute",
  /^[ \t]*=[ \t]*\{point: \{x: 10\.0, y: 20\.0\}, quality: 30\}[ \t]*$/,
  first_transcript
)
expect_segment(
  first, "EnvelopeConstant",
  /^[ \t]*=[ \t]*\{point: \{x: 3\.0, y: 4\.0\}, quality: 5\}[ \t]*$/,
  first_transcript
)
expect_segment(
  first, "PointArrayAttribute",
  /^[ \t]*=[ \t]*\[\[0\]: \{x: 10\.0, y: 11\.0\}, \[1\]: \{x: 12\.0, y: 13\.0\}\][ \t]*$/,
  first_transcript
)
```

Update `EnvelopeEcho(EnvelopeAttribute)` to the same named Envelope shape. Keep
all nested reads, writes, reconnect persistence, and constant assignment
failure assertions unchanged except for replacing every
`allow_zero_decimal:` keyword with `require_zero_decimal:`.

- [ ] **Step 3: Add the installed large-value acceptance assertion**

Add `LargePointArrayAttribute` immediately before the final
`EnvelopeConstant.point.x` command in the first command list. Its complete
bounded value remains compact under the approved 100-character rule:

```ruby
expect_segment(
  first, "LargePointArrayAttribute",
  Regexp.new(
    "\\A[ \\t]*=[ \\t]*" \
    "\\[\\[0\\]: \\{x: 1\\.0, y: 2\\.0\\}, " \
    "\\[1\\]: \\{x: 3\\.0, y: 4\\.0\\}, " \
    "\\[2\\]: \\{x: 5\\.0, y: 6\\.0\\}, " \
    "\\.\\.\\. 997 items omitted\\][ \\t]*\\z"
  ),
  first_transcript
)
```

Keep `EnvelopeConstant.point.x` after the large expression and before `quit` so
the transcript proves the client remains usable after bounded rendering.

- [ ] **Step 4: Make the full harness build and run the renderer unit test**

Add `taskbrowser_value_renderer_test` to the explicit OCL target list:

```bash
cmake --build "$TEST_ROOT/ocl-build" --parallel "$BUILD_PARALLEL" \
    --target taskbrowser_value_renderer_test \
    ocl_opcua_deployment_test deployer-opcua ctaskbrowser-opcua
```

Extend the OCL CTest expression:

```bash
ctest --test-dir "$TEST_ROOT/ocl-build" --output-on-failure \
    --timeout "$TEST_TIMEOUT" \
    -R '^(taskbrowser_value_renderer_test|ocl_opcua_deployment_.*|ctaskbrowser_opcua_.*)$'
```

- [ ] **Step 5: Run a focused sanitizer build**

Use the already installed temporary RTT dependency, not a home prefix:

```bash
export OROCOS_RENDER_SAN_ROOT
OROCOS_RENDER_SAN_ROOT="$(mktemp -d /tmp/orocos-taskbrowser-render-san.XXXXXX)"
mkdir -p "$OROCOS_RENDER_SAN_ROOT/home"

HOME="$OROCOS_RENDER_SAN_ROOT/home" cmake \
  -S toolchain/tools/ocl -B "$OROCOS_RENDER_SAN_ROOT/build" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_PREFIX_PATH="$OROCOS_RENDER_BASE_PREFIX;$OROCOS_RENDER_DEPENDENCY_PREFIX" \
  -DCMAKE_INSTALL_PREFIX="$OROCOS_RENDER_SAN_ROOT/prefix" \
  -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF \
  -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
  -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address,undefined" \
  -DOROCOS_TARGET=gnulinux \
  -DBUILD_TESTING=ON -DBUILD_TESTS=ON \
  -DBUILD_TASKBROWSER=ON -DBUILD_OPCUA=OFF

cmake --build "$OROCOS_RENDER_SAN_ROOT/build" --parallel 2 \
  --target taskbrowser_value_renderer_test
ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1 \
HOME="$OROCOS_RENDER_SAN_ROOT/home" \
ctest --test-dir "$OROCOS_RENDER_SAN_ROOT/build" \
  --output-on-failure -R '^taskbrowser_value_renderer_test$'
```

Expected: PASS with ASan, LSan, and UBSan enabled. This target does not execute
the known third-party `stbsp_vsprintfcb` path and therefore needs no sanitizer
suppression.

- [ ] **Step 6: Run the complete isolated OPC UA harness**

```bash
export OROCOS_RENDER_FINAL_PREFIX
OROCOS_RENDER_FINAL_PREFIX="$(mktemp -d /tmp/orocos-opcua-render-final.XXXXXX)"

HOME="$OROCOS_RENDER_ROOT/home" \
./tools/test-opcua-custom-datatypes.sh \
  --prefix "$OROCOS_RENDER_FINAL_PREFIX" \
  --dependency-prefix "$OROCOS_RENDER_DEPENDENCY_PREFIX" \
  --target gnulinux
```

Expected:

- RTT focused tests pass;
- all `rtt_opcua` tests pass;
- `taskbrowser_value_renderer_test`, OCL OPC UA lifecycle tests, and
  `ctaskbrowser-opcua` CLI tests pass;
- standalone custom-datatype client passes;
- explicit-start deployer client passes;
- two-session installed TaskBrowser acceptance prints named structures and the
  bounded 1000-point preview;
- the harness reports no dependency or artifact below a home `.orocos` path.

- [ ] **Step 7: Commit fixture and harness acceptance**

```bash
git add \
  tests/opcua-custom-datatypes/fixture_components.cpp \
  tests/opcua-custom-datatypes/ctaskbrowser_acceptance.rb \
  tools/test-opcua-custom-datatypes.sh
git diff --cached --check
git commit -m "test: cover bounded TaskBrowser values"
```

Do not stage `docs/src/SUMMARY.md`,
`docs/src/opcua-web-gateway-plan.md`, or `.tb_history`.

- [ ] **Step 8: Record final evidence without merging or pushing**

```bash
git -C toolchain/tools/ocl status --short --branch
git -C toolchain/tools/ocl log -3 --oneline
git status --short --branch
git log -3 --oneline

git -C toolchain/tools/ocl diff --check
git diff --check
```

Expected: the nested OCL worktree is clean and contains the three focused OCL
commits. The root repository contains the fixture/harness commit plus the plan
commit, while only the three pre-existing user-owned paths remain unstaged.
No branch is merged or pushed.

## Completion Checklist

- Exact compact Envelope output:
  `{point: {x: 3.0, y: 4.0}, quality: 5}`.
- Whole Float32/Float64 values retain `.0`.
- Sequences show at most indexes 0, 1, and 2 with an exact omitted count.
- Structural depth 4 collapses; structures show at most 20 members.
- Multiline layout starts above 100 printable characters and uses 2 spaces.
- Total ` = <value>` output is at most 4096 bytes with balanced delimiters.
- Unavailable members do not hide readable siblings.
- Opaque types retain their stream representation.
- One structured expression performs exactly one root evaluation and no source
  mutation.
- Constants remain read-only and nested expression paths still work.
- Local tests, sanitizers, and installed two-process OPC UA acceptance pass
  entirely below `/tmp`.
