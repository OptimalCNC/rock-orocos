# OPC UA TaskBrowser Custom Datatype Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the installed `ctaskbrowser-opcua` display, inspect, invoke, and
persistently update the fixture's structured custom datatypes through the
native OPC UA proxy.

**Architecture:** RTT continues to own C++ structure and sequence semantics,
while the external fixture typekit supplies member metadata and the fixture OPC
UA plugin supplies complete-value codecs. Two narrowly scoped RTT fixes preserve
read-only structured members and propagate `updated()` after indexed sequence
element writes. A Ruby process driver exercises the installed TaskBrowser in
two client sessions so reconnect verification distinguishes a server write from
a client-cache-only update.

**Tech Stack:** C++20, Orocos RTT/OCL, Boost.Serialization, Boost.Test,
open62541 `v1.4.15`, open62541pp `v0.21.2`, Ruby standard library, CMake, CTest,
ASan/UBSan, mdBook.

## Global Constraints

- Work only in `/home/liufang/MetaNC/orocos-rock/.worktrees/orocos-opcua-custom-datatypes`
  and its existing nested package worktrees.
- Install and test only below `/tmp`; never read from, link against, or install
  into `~/.orocos`.
- Keep RTT CORBA disabled with `ENABLE_CORBA=OFF`.
- Keep open62541 at `v1.4.15` and open62541pp at `v0.21.2`.
- Do not modify open62541 or open62541pp source and do not build either
  dependency's unit tests.
- Treat the OPC UA address space as a static graph for this version. Do not add
  unpublish, component replacement, reconciliation, PubSub, PKI, access-control,
  or publication-mode behavior.
- Keep whole-component publication. Do not add resource allowlists.
- The fixture typekit owns RTT member names and structure metadata. `rtt_opcua`
  owns wire encoding and proxy I/O and must not synthesize RTT metadata from OPC
  UA datatype definitions.
- Keep `/orocos/fixture/UnsupportedValue` opaque so strict publication failure
  remains covered.
- Do not change OCL or `rtt_opcua` production source. The known gaps are in RTT
  member semantics and fixture metadata.
- Preserve the user-owned `docs/src/SUMMARY.md`,
  `docs/src/opcua-web-gateway-plan.md`, and `.tb_history` changes.
- Commit RTT changes in `toolchain/tools/rtt`; commit fixture and harness
  changes in the root repository. Do not merge or push in this plan.

## Execution Environment

Use a maintained dependency prefix containing the already-built farbot,
rtlog-cpp, open62541, and open62541pp prerequisites. It must be below `/tmp`.

```bash
cd /home/liufang/MetaNC/orocos-rock/.worktrees/orocos-opcua-custom-datatypes

export OROCOS_TB_VERIFY_ROOT
OROCOS_TB_VERIFY_ROOT="$(mktemp -d /tmp/orocos-opcua-taskbrowser.XXXXXX)"

export OROCOS_TB_DEPENDENCY_PREFIX
OROCOS_TB_DEPENDENCY_PREFIX="${OROCOS_ROCK_OPCUA_DEPENDENCY_PREFIX:?set OROCOS_ROCK_OPCUA_DEPENDENCY_PREFIX to the maintained /tmp dependency prefix}"

case "$OROCOS_TB_DEPENDENCY_PREFIX" in
  /tmp/*) ;;
  *) printf '%s\n' "dependency prefix must be below /tmp" >&2; exit 1 ;;
esac

test -f "$OROCOS_TB_DEPENDENCY_PREFIX/lib/cmake/open62541/open62541Config.cmake"
test -f "$OROCOS_TB_DEPENDENCY_PREFIX/lib/cmake/open62541pp/open62541ppConfig.cmake"
```

Expected: all checks exit zero and `OROCOS_TB_VERIFY_ROOT` names a new directory
below `/tmp`.

## File Map

| File | Responsibility |
| --- | --- |
| `toolchain/tools/rtt/rtt/internal/PartDataSource.hpp` | Own a read-only member snapshot while retaining its copied parent. |
| `toolchain/tools/rtt/rtt/internal/rtt-internal-fwd.hpp` | Forward-declare the read-only datasource. |
| `toolchain/tools/rtt/rtt/types/type_discovery.hpp` | Select assignable references or read-only snapshots during member discovery. |
| `toolchain/tools/rtt/rtt/types/StructTypeInfo.hpp` | Preserve nonassignability when reading a constant's member. |
| `toolchain/tools/rtt/rtt/internal/FusedFunctorDataSource.hpp` | Notify a sequence parent after a referenced element changes. |
| `toolchain/tools/rtt/tests/type_discovery_struct_test.cpp` | Regress constant members and nested sequence update propagation. |
| `tests/opcua-custom-datatypes/fixture_types.hpp` | Define fixture member names and readable stream syntax. |
| `tests/opcua-custom-datatypes/fixture_typekit.cpp` | Register member-aware RTT structures. |
| `tests/opcua-custom-datatypes/fixture_client.cpp` | Assert local type metadata before remote proxy tests. |
| `tests/opcua-custom-datatypes/ctaskbrowser_acceptance.rb` | Drive and validate two installed TaskBrowser sessions. |
| `tools/test-opcua-custom-datatypes.sh` | Run RTT regressions and TaskBrowser acceptance from an isolated prefix. |

---

### Task 1: Preserve Read-Only Structured Members

**Files:**

- Modify: `toolchain/tools/rtt/tests/type_discovery_struct_test.cpp`
- Modify: `toolchain/tools/rtt/rtt/internal/rtt-internal-fwd.hpp`
- Modify: `toolchain/tools/rtt/rtt/internal/PartDataSource.hpp`
- Modify: `toolchain/tools/rtt/rtt/types/type_discovery.hpp`
- Modify: `toolchain/tools/rtt/rtt/types/StructTypeInfo.hpp`

**Interfaces:**

- Consumes: `StructTypeInfo<T>::getMember()`, Boost.Serialization discovery,
  and `DataSourceBase::isAssignable()`.
- Produces: `internal::ReadOnlyPartDataSource<T>` and
  `type_discovery(parent, parts_assignable)`. Passing `false` returns readable,
  nonassignable member snapshots.

- [ ] **Step 1: Configure a focused temporary RTT test build**

```bash
cmake -S toolchain/tools/rtt \
  -B "$OROCOS_TB_VERIFY_ROOT/rtt-build" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_PREFIX_PATH="$OROCOS_TB_DEPENDENCY_PREFIX" \
  -DCMAKE_INSTALL_PREFIX="$OROCOS_TB_VERIFY_ROOT/rtt-prefix" \
  -DOROCOS_TARGET=gnulinux \
  -DENABLE_CORBA=OFF \
  -DENABLE_MQ=OFF \
  -DENABLE_TESTS=ON \
  -DBUILD_TESTING=ON

cmake --build "$OROCOS_TB_VERIFY_ROOT/rtt-build" --parallel 2 \
  --target type_discovery_struct_test property_test marshalling_test
```

Expected: configuration and unchanged baseline targets pass without resolving
any home-directory Orocos installation.

- [ ] **Step 2: Add failing constant-member assertions**

Extend `testATypeStruct` in `type_discovery_struct_test.cpp`:

```cpp
DataSource<AType>::shared_ptr constant =
    new ConstantDataSource<AType>(AType(true));
DataSourceBase::shared_ptr constant_a = constant->getMember("a");

BOOST_REQUIRE(constant_a);
DataSource<int>::shared_ptr readable_a =
    DataSource<int>::narrow(constant_a.get());
BOOST_REQUIRE(readable_a);
BOOST_CHECK_EQUAL(readable_a->get(), constant->get().a);
BOOST_CHECK(!constant_a->isAssignable());
BOOST_CHECK(!AssignableDataSource<int>::narrow(constant_a.get()));
```

Extend `testCTypeStruct` with a nested path:

```cpp
DataSource<CType>::shared_ptr constant =
    new ConstantDataSource<CType>(CType(true));
DataSourceBase::shared_ptr constant_a = constant->getMember("a");
BOOST_REQUIRE(constant_a);
DataSourceBase::shared_ptr nested = constant_a->getMember("a");

BOOST_REQUIRE(nested);
DataSource<int>::shared_ptr readable = DataSource<int>::narrow(nested.get());
BOOST_REQUIRE(readable);
BOOST_CHECK_EQUAL(readable->get(), constant->get().a.a);
BOOST_CHECK(!nested->isAssignable());
```

- [ ] **Step 3: Run the test and verify the temporary-copy bug**

```bash
cmake --build "$OROCOS_TB_VERIFY_ROOT/rtt-build" --parallel 2 \
  --target type_discovery_struct_test
ctest --test-dir "$OROCOS_TB_VERIFY_ROOT/rtt-build" \
  --output-on-failure -R '^type_discovery_struct_test$'
```

Expected: FAIL because `StructTypeInfo` currently places a constant parent in a
`ValueDataSource<T>` and exposes assignable `PartDataSource` members.

- [ ] **Step 4: Add a parent-retaining read-only member datasource**

Forward-declare it in `rtt/internal/rtt-internal-fwd.hpp`:

```cpp
template <typename T>
class ReadOnlyPartDataSource;
```

Add it next to `PartDataSource<T>` in `rtt/internal/PartDataSource.hpp`:

```cpp
template <typename T>
class ReadOnlyPartDataSource : public DataSource<T> {
    typename DataSource<T>::value_t mvalue;
    base::DataSourceBase::shared_ptr mparent;

public:
    typedef boost::intrusive_ptr<ReadOnlyPartDataSource<T> > shared_ptr;

    ReadOnlyPartDataSource(
        typename DataSource<T>::const_reference_t value,
        base::DataSourceBase::shared_ptr parent)
        : mvalue(value), mparent(parent) {}

    typename DataSource<T>::result_t get() const { return mvalue; }
    typename DataSource<T>::result_t value() const { return mvalue; }
    typename DataSource<T>::const_reference_t rvalue() const { return mvalue; }

    ReadOnlyPartDataSource<T>* clone() const override {
        return new ReadOnlyPartDataSource<T>(mvalue, mparent);
    }

    ReadOnlyPartDataSource<T>* copy(
        std::map<const base::DataSourceBase*, base::DataSourceBase*>& replace)
        const override {
        if (replace[this] != 0) {
            return static_cast<ReadOnlyPartDataSource<T>*>(replace[this]);
        }
        replace[this] = new ReadOnlyPartDataSource<T>(mvalue, mparent);
        return static_cast<ReadOnlyPartDataSource<T>*>(replace[this]);
    }
};
```

`mparent` keeps shallow views such as `carray<T>` tied to the lifetime of the
copied structure that owns their storage.

- [ ] **Step 5: Make member writability explicit in type discovery**

Add `bool mparts_assignable` and initialize it in both constructors:

```cpp
type_discovery(base::DataSourceBase::shared_ptr parent,
               bool parts_assignable = true)
    : mparent(parent), mparts_assignable(parts_assignable), mref(0) {}

type_discovery()
    : mparent(), mparts_assignable(false), mref(0) {}
```

Route primitive and composite members through this helper:

```cpp
template <typename T>
void addPart(T& value) {
    if (!mparent) {
        return;
    }
    if (mparts_assignable) {
        mparts.push_back(new internal::PartDataSource<T>(value, mparent));
    } else {
        mparts.push_back(
            new internal::ReadOnlyPartDataSource<T>(value, mparent));
    }
}
```

Use the same selection for serialization-array and Boost-array overloads. Put
their `carray<T>` view in a named local before calling `addPart()` so the
read-only datasource copies the view while retaining `mparent`.

- [ ] **Step 6: Preserve parent writability in `StructTypeInfo`**

Use assignable discovery only for an assignable parent. For a readable constant,
create the existing snapshot and use read-only discovery:

```cpp
if (adata) {
    type_discovery in(adata, true);
    return in.discoverMember(adata->set(), name);
}

typename internal::DataSource<T>::shared_ptr data =
    boost::dynamic_pointer_cast<internal::DataSource<T> >(item);
if (data) {
    typename internal::AssignableDataSource<T>::shared_ptr snapshot =
        new internal::ValueDataSource<T>(data->get());
    type_discovery in(snapshot, false);
    return in.discoverMember(snapshot->set(), name);
}
```

In `getMember(internal::Reference*, ...)`, return `false` for a nonassignable
parent instead of returning a writable reference into a temporary snapshot.

- [ ] **Step 7: Run focused RTT regression tests**

```bash
cmake --build "$OROCOS_TB_VERIFY_ROOT/rtt-build" --parallel 2 \
  --target type_discovery_struct_test property_test marshalling_test
ctest --test-dir "$OROCOS_TB_VERIFY_ROOT/rtt-build" \
  --output-on-failure \
  -R '^(type_discovery_struct_test|property_test|marshalling_test)$'
```

Expected: PASS. Assignable members still update parents, constant nested members
are readable and nonassignable, and decomposition/marshalling remain green.

- [ ] **Step 8: Commit the RTT read-only fix**

```bash
git -C toolchain/tools/rtt add \
  rtt/internal/rtt-internal-fwd.hpp \
  rtt/internal/PartDataSource.hpp \
  rtt/types/type_discovery.hpp \
  rtt/types/StructTypeInfo.hpp \
  tests/type_discovery_struct_test.cpp
git -C toolchain/tools/rtt commit -m \
  "fix: preserve readonly structured members"
```

---

### Task 2: Propagate Indexed Sequence Element Updates

**Files:**

- Modify: `toolchain/tools/rtt/tests/type_discovery_struct_test.cpp`
- Modify: `toolchain/tools/rtt/rtt/internal/FusedFunctorDataSource.hpp`

**Interfaces:**

- Consumes: the pure-reference `FusedFunctorDataSource<Signature>` used by
  `SequenceTypeInfoBase<T>::getMember()`.
- Produces: `FusedFunctorDataSource::updated()` propagation that calls
  `SequenceFactory::update(args)` after, and only after, a referenced element
  has changed.

- [ ] **Step 1: Add an update-observing test datasource**

Add near the top of `type_discovery_struct_test.cpp`:

```cpp
template <typename T>
class UpdateTrackingDataSource : public ValueDataSource<T> {
public:
    explicit UpdateTrackingDataSource(const T& value)
        : ValueDataSource<T>(value), update_count(0) {}

    void updated() override { ++update_count; }

    std::size_t update_count;
};
```

Add this test after `testCTypeStruct`:

```cpp
BOOST_AUTO_TEST_CASE(testSequenceStructMemberNotifiesParent)
{
    if (!Types()->type("AType")) {
        Types()->addType(new StructTypeInfo<AType>("AType"));
    }
    if (!Types()->type("as")) {
        Types()->addType(new SequenceTypeInfo<vector<AType> >("as"));
    }

    boost::intrusive_ptr<UpdateTrackingDataSource<vector<AType> > > parent =
        new UpdateTrackingDataSource<vector<AType> >(
            vector<AType>(1, AType(true)));
    AssignableDataSource<AType>::shared_ptr element =
        AssignableDataSource<AType>::narrow(parent->getMember("0").get());
    BOOST_REQUIRE(element);

    element->get();
    BOOST_CHECK_EQUAL(parent->update_count, 0U);

    AType replacement(true);
    replacement.a = 21;
    element->set(replacement);
    BOOST_CHECK_EQUAL(parent->update_count, 1U);

    AssignableDataSource<int>::shared_ptr member =
        AssignableDataSource<int>::narrow(element->getMember("a").get());
    BOOST_REQUIRE(member);
    parent->update_count = 0U;
    member->set(42);

    BOOST_CHECK_EQUAL(parent->update_count, 1U);
    BOOST_CHECK_EQUAL(parent->get().front().a, 42);
}
```

- [ ] **Step 2: Run the test and verify notification ordering is wrong**

```bash
cmake --build "$OROCOS_TB_VERIFY_ROOT/rtt-build" --parallel 2 \
  --target type_discovery_struct_test
ctest --test-dir "$OROCOS_TB_VERIFY_ROOT/rtt-build" \
  --output-on-failure -R '^type_discovery_struct_test$'
```

Expected: FAIL. A read currently notifies the parent, while direct and nested
assignments fail to notify after the new value is stored.

- [ ] **Step 3: Correct the pure-reference lifecycle**

In the pure-reference specialization in
`rtt/internal/FusedFunctorDataSource.hpp`, remove
`SequenceFactory::update(args)` from `evaluate()`. Add notification after direct
assignment and expose it for nested `PartDataSource` updates:

```cpp
bool evaluate() const {
    typedef typename bf::result_of::invoke<call_type, arg_type>::type iret;
    typedef iret(*IType)(call_type, arg_type const&);
    IType foo = &bf::invoke<call_type, arg_type>;
    ret.exec(boost::bind(foo, boost::ref(ff), SequenceFactory::data(args)));
    return true;
}

void set(typename AssignableDataSource<value_t>::param_t arg) {
    get();
    ret.result() = arg;
    updated();
}

reference_t set() {
    get();
    return ret.result();
}

void updated() override {
    SequenceFactory::update(args);
}
```

The reference-returning `set()` does not notify immediately. Its caller mutates
the reference and then calls `updated()` once the mutation is complete.

- [ ] **Step 4: Run structure and container tests**

```bash
cmake --build "$OROCOS_TB_VERIFY_ROOT/rtt-build" --parallel 2 \
  --target type_discovery_struct_test type_discovery_container_test
ctest --test-dir "$OROCOS_TB_VERIFY_ROOT/rtt-build" \
  --output-on-failure \
  -R '^(type_discovery_struct_test|type_discovery_container_test)$'
```

Expected: PASS. Reads cause zero callbacks; direct and nested writes cause one
callback after the new value is visible.

- [ ] **Step 5: Commit the RTT sequence fix**

```bash
git -C toolchain/tools/rtt add \
  rtt/internal/FusedFunctorDataSource.hpp \
  tests/type_discovery_struct_test.cpp
git -C toolchain/tools/rtt commit -m \
  "fix: propagate indexed sequence updates"
```

---

### Task 3: Make the Fixture Structures Member-Aware

**Files:**

- Modify: `tests/opcua-custom-datatypes/fixture_types.hpp`
- Modify: `tests/opcua-custom-datatypes/fixture_typekit.cpp`
- Modify: `tests/opcua-custom-datatypes/fixture_client.cpp`

**Interfaces:**

- Consumes: `StructTypeInfo<T, true>`, Task 1's read-only behavior, and the
  complete-value fixture codecs already in `fixture_transport.cpp`.
- Produces: case-sensitive fields `Point.{x,y}` and
  `Envelope.{point,quality}`, plus text formats `Point{x, y}` and
  `Envelope{Point{x, y}, quality}`.

- [ ] **Step 1: Add failing local type-system assertions**

Add this function to `fixture_client.cpp` and call it immediately after
`loadTypesAndTransports(typekit, transport)`:

```cpp
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

  RTT::internal::DataSource<Envelope>::shared_ptr constant =
      new RTT::internal::ConstantDataSource<Envelope>(Envelope{{3.0, 4.0}, 5});
  RTT::base::DataSourceBase::shared_ptr constant_point =
      constant->getMember("point");
  require(constant_point != nullptr, "Envelope constant point is missing");
  RTT::base::DataSourceBase::shared_ptr constant_x =
      constant_point->getMember("x");
  require(constant_x != nullptr, "Envelope constant member is missing");
  require(!constant_x->isAssignable(),
          "Envelope constant member is unexpectedly writable");
}
```

- [ ] **Step 2: Run the harness and prove the opaque metadata fails**

```bash
./tools/test-opcua-custom-datatypes.sh \
  --prefix "$OROCOS_TB_VERIFY_ROOT/opaque-prefix" \
  --dependency-prefix "$OROCOS_TB_DEPENDENCY_PREFIX" \
  --target gnulinux
```

Expected: FAIL from `fixture-client` with `Point member names mismatch`.

- [ ] **Step 3: Define serialization names and stream input**

In `fixture_types.hpp`, include `<ios>`, `<istream>`, `<string>`, and
`<boost/serialization/nvp.hpp>`. Add strict parsers for the existing output
grammar:

```cpp
namespace detail {

inline bool consume(std::istream &stream, std::string_view expected) {
  for (const char expected_character : expected) {
    char actual_character = '\0';
    if (!stream.get(actual_character) || actual_character != expected_character) {
      stream.setstate(std::ios::failbit);
      return false;
    }
  }
  return true;
}

} // namespace detail

inline std::istream &operator>>(std::istream &stream, Point &value) {
  stream >> std::ws;
  if (!detail::consume(stream, "Point{")) return stream;
  stream >> value.x >> std::ws;
  if (!detail::consume(stream, ",")) return stream;
  stream >> value.y >> std::ws;
  detail::consume(stream, "}");
  return stream;
}

inline std::istream &operator>>(std::istream &stream, Envelope &value) {
  stream >> std::ws;
  if (!detail::consume(stream, "Envelope{")) return stream;
  stream >> value.point >> std::ws;
  if (!detail::consume(stream, ",")) return stream;
  stream >> value.quality >> std::ws;
  detail::consume(stream, "}");
  return stream;
}
```

After the fixture namespace, register exact Boost.Serialization names:

```cpp
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
```

- [ ] **Step 4: Register member-aware RTT structures**

Add `#include <rtt/types/StructTypeInfo.hpp>` to `fixture_typekit.cpp` and
replace only the `Point` and `Envelope` registrations:

```cpp
types->addType(new RTT::types::StructTypeInfo<Point, true>(
    std::string(kPointTypeName))) &&
types->addType(new RTT::types::StructTypeInfo<Envelope, true>(
    std::string(kEnvelopeTypeName)))
```

Keep `SequenceTypeInfo<PointArray>` and
`TemplateTypeInfo<UnsupportedValue, false>` unchanged.

- [ ] **Step 5: Re-run the cross-process fixture**

```bash
./tools/test-opcua-custom-datatypes.sh \
  --prefix "$OROCOS_TB_VERIFY_ROOT/member-aware-prefix" \
  --dependency-prefix "$OROCOS_TB_DEPENDENCY_PREFIX" \
  --target gnulinux
```

Expected: PASS. The client proves member discovery, stream round-trip,
transitive constant read-only behavior, and existing OPC UA round-trips.

- [ ] **Step 6: Commit fixture metadata**

```bash
git add \
  tests/opcua-custom-datatypes/fixture_types.hpp \
  tests/opcua-custom-datatypes/fixture_typekit.cpp \
  tests/opcua-custom-datatypes/fixture_client.cpp
git commit -m "test: expose fixture structure metadata"
```

---

### Task 4: Exercise the Installed TaskBrowser in Two Sessions

**Files:**

- Create: `tests/opcua-custom-datatypes/ctaskbrowser_acceptance.rb`
- Modify: `tools/test-opcua-custom-datatypes.sh`

**Interfaces:**

- Consumes: installed `ctaskbrowser-opcua`, fixture import
  `orocos_opcua_fixture`, endpoint URL, and component `sample`.
- Produces: a process acceptance command proving display, nested access,
  operation invocation, writes, constant rejection, indexed structure-array
  access, and server persistence across reconnect.

- [ ] **Step 1: Create the transcript driver**

Create `tests/opcua-custom-datatypes/ctaskbrowser_acceptance.rb`:

```ruby
#!/usr/bin/env ruby

require "optparse"
require "pty"
require "timeout"

options = {}
OptionParser.new do |parser|
  parser.on("--client PATH") { |value| options[:client] = value }
  parser.on("--endpoint URL") { |value| options[:endpoint] = value }
  parser.on("--component NAME") { |value| options[:component] = value }
end.parse!

%i[client endpoint component].each do |key|
  abort("missing --#{key.to_s.tr('_', '-')}") unless options[key]
end

ANSI_ESCAPE = /\e\[[0-?]*[ -\/]*[@-~]/

def run_session(options, commands)
  transcript = +""
  child_pid = nil
  status = nil

  begin
    Timeout.timeout(20) do
      PTY.spawn(
        { "TERM" => "dumb" },
        options.fetch(:client),
        "--import", "orocos_opcua_fixture",
        options.fetch(:endpoint), options.fetch(:component)
      ) do |reader, writer, pid|
        child_pid = pid
        writer.write(commands.join("\n") + "\n")
        writer.flush
        begin
          loop { transcript << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
        ensure
          _, status = Process.wait2(pid)
          child_pid = nil
        end
      end
    end
  rescue Timeout::Error
    if child_pid
      begin
        Process.kill("TERM", child_pid)
      rescue Errno::ESRCH
      end
      begin
        Process.wait(child_pid)
      rescue Errno::ECHILD
      end
    end
    abort("ctaskbrowser-opcua timed out:\n#{transcript}")
  end

  transcript = transcript.gsub(ANSI_ESCAPE, "").delete("\r")
  abort("ctaskbrowser-opcua failed:\n#{transcript}") unless status&.success?
  transcript
end

def command_segments(transcript, commands)
  starts = []
  cursor = 0
  commands.each do |command|
    position = transcript.index(command, cursor)
    abort("command not echoed: #{command}\n#{transcript}") unless position
    starts << position
    cursor = position + command.length
  end

  commands.each_index.to_h do |index|
    finish = starts[index + 1] || transcript.length
    [commands[index], transcript[starts[index]...finish]]
  end
end

def expect_segment(segments, command, pattern)
  segment = segments.fetch(command)
  return if segment.match?(pattern)
  abort("unexpected result for #{command}:\n#{segment}")
end
```

Run these commands in the first process:

```ruby
first_commands = [
  "PointAttribute",
  "EnvelopeAttribute",
  "EnvelopeConstant",
  "PointArrayAttribute",
  "PointAttribute.x",
  "EnvelopeAttribute.point.x",
  "EnvelopeAttribute.quality",
  "EnvelopeProperty.point.y",
  "PointArrayAttribute[0].x",
  "EnvelopeEcho(EnvelopeAttribute)",
  "EnvelopeAttribute.point.x = 101",
  "EnvelopeAttribute.quality = 102",
  "EnvelopeProperty.point.y = 103",
  "PointArrayAttribute[0].x = 201",
  "EnvelopeConstant.point.x = 999",
  "EnvelopeConstant.point.x",
  "quit"
]
```

Use `expect_segment` to assert the known values left by `fixture-client`:

```ruby
first = command_segments(run_session(options, first_commands), first_commands)
expect_segment(first, "PointAttribute", /=\s*Point\{10(?:\.0+)?, 20(?:\.0+)?\}/)
expect_segment(first, "EnvelopeAttribute", /=\s*Envelope\{Point\{10(?:\.0+)?, 20(?:\.0+)?\}, 30\}/)
expect_segment(first, "EnvelopeConstant", /=\s*Envelope\{Point\{3(?:\.0+)?, 4(?:\.0+)?\}, 5\}/)
expect_segment(first, "PointArrayAttribute", /Point\{10(?:\.0+)?, 11(?:\.0+)?\}.*Point\{12(?:\.0+)?, 13(?:\.0+)?\}/m)
expect_segment(first, "PointAttribute.x", /=\s*10(?:\.0+)?\b/)
expect_segment(first, "EnvelopeAttribute.point.x", /=\s*10(?:\.0+)?\b/)
expect_segment(first, "EnvelopeAttribute.quality", /=\s*30\b/)
expect_segment(first, "EnvelopeProperty.point.y", /=\s*20(?:\.0+)?\b/)
expect_segment(first, "PointArrayAttribute[0].x", /=\s*10(?:\.0+)?\b/)
expect_segment(first, "EnvelopeEcho(EnvelopeAttribute)", /=\s*Envelope\{Point\{10(?:\.0+)?, 20(?:\.0+)?\}, 30\}/)
expect_segment(first, "EnvelopeConstant.point.x = 999", /Fatal Semantic error:.*Cannot assign constant/m)
expect_segment(first, "EnvelopeConstant.point.x", /=\s*3(?:\.0+)?\b/)
```

Reconnect with a second process and prove server-side persistence:

```ruby
second_commands = [
  "EnvelopeAttribute.point.x",
  "EnvelopeAttribute.quality",
  "EnvelopeProperty.point.y",
  "PointArrayAttribute[0].x",
  "EnvelopeConstant.point.x",
  "quit"
]
second = command_segments(run_session(options, second_commands), second_commands)
expect_segment(second, "EnvelopeAttribute.point.x", /=\s*101(?:\.0+)?\b/)
expect_segment(second, "EnvelopeAttribute.quality", /=\s*102\b/)
expect_segment(second, "EnvelopeProperty.point.y", /=\s*103(?:\.0+)?\b/)
expect_segment(second, "PointArrayAttribute[0].x", /=\s*201(?:\.0+)?\b/)
expect_segment(second, "EnvelopeConstant.point.x", /=\s*3(?:\.0+)?\b/)
puts "ctaskbrowser-opcua custom datatype acceptance passed"
```

- [ ] **Step 2: Syntax-check the driver**

```bash
ruby -c tests/opcua-custom-datatypes/ctaskbrowser_acceptance.rb
```

Expected: `Syntax OK`.

- [ ] **Step 3: Wire the installed client into the harness**

Define and require these artifacts in `tools/test-opcua-custom-datatypes.sh`:

```bash
TASKBROWSER="$PREFIX/bin/ctaskbrowser-opcua"
TASKBROWSER_BINARY="$PREFIX/bin/ctaskbrowser-opcua-$TARGET"
TASKBROWSER_ACCEPTANCE="$OROCOS_ROCK_ROOT/tests/opcua-custom-datatypes/ctaskbrowser_acceptance.rb"
```

Extend the RTT target and CTest lists:

```bash
cmake --build "$TEST_ROOT/rtt-build" --parallel "$BUILD_PARALLEL" \
    --target typekit_test scripting_test \
    type_discovery_struct_test type_discovery_container_test
ctest --test-dir "$TEST_ROOT/rtt-build" --output-on-failure \
    --timeout "$TEST_TIMEOUT" \
    -R '^(typekit_test|scripting_test|type_discovery_struct_test|type_discovery_container_test)$'
```

After the deployer-mode `fixture-client` succeeds and before terminating the
deployer, run:

```bash
orocos_rock_info "Running installed ctaskbrowser-opcua custom datatype acceptance"
ruby "$TASKBROWSER_ACCEPTANCE" \
    --client "$TASKBROWSER" \
    --endpoint "$START_ENDPOINT" \
    --component sample
```

Add all three variables to artifact checks. Add only `TASKBROWSER_BINARY` to the
`ldd` scan because the unsuffixed command is a wrapper. The harness's temporary
`HOME` keeps `.tb_history` below `/tmp`.

- [ ] **Step 4: Check scripts before the full build**

```bash
bash -n tools/test-opcua-custom-datatypes.sh
ruby -c tests/opcua-custom-datatypes/ctaskbrowser_acceptance.rb
```

Expected: both exit zero and Ruby prints `Syntax OK`.

- [ ] **Step 5: Run complete installed-client acceptance**

```bash
./tools/test-opcua-custom-datatypes.sh \
  --prefix "$OROCOS_TB_VERIFY_ROOT/taskbrowser-prefix" \
  --dependency-prefix "$OROCOS_TB_DEPENDENCY_PREFIX" \
  --target gnulinux
```

Expected: PASS with `ctaskbrowser-opcua custom datatype acceptance passed` and
`OPC UA custom datatype verification passed`. The same run proves no-start
closure, explicit startup, strict unsupported-type publication, and no
home-prefix contamination.

- [ ] **Step 6: Commit TaskBrowser acceptance**

```bash
git add \
  tests/opcua-custom-datatypes/ctaskbrowser_acceptance.rb \
  tools/test-opcua-custom-datatypes.sh
git commit -m "test: exercise custom datatypes in opcua taskbrowser"
```

---

### Task 5: Run Sanitizers and the Final Review Gate

**Files:**

- Verify only; this task creates no source file.

**Interfaces:**

- Consumes: the two RTT commits and two root commits from Tasks 1 through 4.
- Produces: evidence that the change is warning-clean, sanitizer-clean,
  isolated from `~/.orocos`, and limited to approved repositories.

- [ ] **Step 1: Configure a separate RTT sanitizer build**

```bash
cmake -S toolchain/tools/rtt \
  -B "$OROCOS_TB_VERIFY_ROOT/rtt-sanitizer-build" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_PREFIX_PATH="$OROCOS_TB_DEPENDENCY_PREFIX" \
  -DOROCOS_TARGET=gnulinux \
  -DENABLE_CORBA=OFF \
  -DENABLE_MQ=OFF \
  -DENABLE_TESTS=ON \
  -DBUILD_TESTING=ON \
  -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"

cmake --build "$OROCOS_TB_VERIFY_ROOT/rtt-sanitizer-build" --parallel 2 \
  --target type_discovery_struct_test type_discovery_container_test
```

Expected: both targets compile with the repository warning policy.

- [ ] **Step 2: Run sanitizer tests**

```bash
ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
ctest --test-dir "$OROCOS_TB_VERIFY_ROOT/rtt-sanitizer-build" \
  --output-on-failure \
  -R '^(type_discovery_struct_test|type_discovery_container_test)$'
```

Expected: PASS with no ASan, LeakSanitizer, or UBSan diagnostic.

- [ ] **Step 3: Run policy and whitespace checks**

```bash
ruby tools/check-repository-policy.rb
ruby tools/check-autoproj-policy.rb
ruby tools/check-cpp20-policy.rb
git diff --check HEAD~2..HEAD
git -C toolchain/tools/rtt diff --check HEAD~2..HEAD
```

Expected: every command exits zero.

- [ ] **Step 4: Confirm unrelated package trees stayed clean**

```bash
git -C toolchain/open62541 status --short
git -C toolchain/open62541pp status --short
git -C toolchain/tools/rtt_opcua status --short
git -C toolchain/tools/ocl status --short
```

Expected: all four commands print nothing.

- [ ] **Step 5: Review exact root and RTT changes**

```bash
git status --short
git diff HEAD~2..HEAD -- \
  tests/opcua-custom-datatypes \
  tools/test-opcua-custom-datatypes.sh
git -C toolchain/tools/rtt status --short
git -C toolchain/tools/rtt diff HEAD~2..HEAD -- \
  rtt/internal/rtt-internal-fwd.hpp \
  rtt/internal/PartDataSource.hpp \
  rtt/internal/FusedFunctorDataSource.hpp \
  rtt/types/type_discovery.hpp \
  rtt/types/StructTypeInfo.hpp \
  tests/type_discovery_struct_test.cpp
```

Expected: only the user-owned root files listed in Global Constraints remain
uncommitted; RTT is clean. The diff has no third-party, OCL, `rtt_opcua`,
unpublish, PubSub, security, or MetaNC application changes.

- [ ] **Step 6: Apply completion verification and review workflows**

Invoke `superpowers:verification-before-completion` and report fresh outputs
from Steps 2 through 5. Then invoke `superpowers:requesting-code-review` against
the root and RTT commit ranges. Resolve every correctness finding and repeat the
affected checks before any merge or push decision.
