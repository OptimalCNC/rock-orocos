# Read-Only C-Array Indexing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make indexed elements of read-only RTT fixed C-array snapshots readable without making them assignable or changing writable C-array behavior.

**Architecture:** Add a read-only counterpart to `ArrayPartDataSource` that reads an element through a readable C-array parent and a runtime index datasource. `CArrayTypeInfo` selects the existing writable datasource for assignable parents and the new datasource for readable-only parents; parser and TaskBrowser code remain unchanged.

**Tech Stack:** C++20, Orocos RTT datasource/type-info APIs, Boost.Test, CMake/CTest

## Global Constraints

- Writable C-array parents must continue to expose assignable indexed elements and propagate parent updates.
- Read-only C-array parents and operation-return snapshots must expose readable, nonassignable indexed elements.
- Numeric-string and dynamic unsigned-integer indexing must follow the same assignability rule.
- Runtime indexes must remain live; do not freeze the index or element in a constant datasource.
- Out-of-range reads retain `internal::NA<T>::na()` behavior.
- Clone keeps the same parent and index; copy uses RTT's replacement map for both.
- Do not change OCL, TaskBrowser, the expression parser, Boost arrays, OPC UA, generated typekits, or wire formats.
- Run build-tree tests with `LD_LIBRARY_PATH` unset so installed RTT libraries cannot override the build tree.

---

### Task 1: Read-Only Fixed C-Array Element Access

**Files:**
- Modify: `toolchain/tools/rtt/tests/type_discovery_struct_test.cpp`
- Modify: `toolchain/tools/rtt/tests/scripting_test.cpp`
- Modify: `toolchain/tools/rtt/rtt/internal/rtt-internal-fwd.hpp`
- Modify: `toolchain/tools/rtt/rtt/internal/ArrayPartDataSource.hpp`
- Modify: `toolchain/tools/rtt/rtt/types/CArrayTypeInfo.hpp`

**Interfaces:**
- Consumes: `DataSource<ArrayT>::shared_ptr`, `DataSource<unsigned int>::shared_ptr`, `ArrayT::address()`, and RTT datasource `clone()`/`copy()` semantics.
- Produces: `internal::ReadOnlyArrayPartDataSource<ElementT, ArrayT>`, a `DataSource<ElementT>` that has no assignment interface.
- Produces: `CArrayTypeInfo::getMember()` results whose assignability matches their C-array parent.

- [ ] **Step 1: Add direct failing type-discovery regressions**

Add these test cases after `testReadOnlyArrayViewsCannotMutateSnapshots` in
`tests/type_discovery_struct_test.cpp`. Add `#include <internal/NA.hpp>` with
the other internal datasource includes:

```cpp
BOOST_AUTO_TEST_CASE( testReadOnlyCArrayElementsAreReadable )
{
    if (!Types()->type("cints")) {
        Types()->addType(new CArrayTypeInfo<carray<int> >("cints"));
    }
    if (!Types()->type("BType")) {
        Types()->addType(new StructTypeInfo<BType>("BType"));
    }

    DataSource<BType>::shared_ptr parent =
        new ConstantDataSource<BType>(BType(true));
    DataSourceBase::shared_ptr array = parent->getMember("ai");
    BOOST_REQUIRE(array);

    DataSourceBase::shared_ptr fixed_element = array->getMember("3");
    BOOST_REQUIRE(fixed_element);
    DataSource<int>::shared_ptr fixed_value =
        DataSource<int>::narrow(fixed_element.get());
    BOOST_REQUIRE(fixed_value);
    BOOST_CHECK_EQUAL(fixed_value->get(), 99);
    BOOST_CHECK(!fixed_element->isAssignable());
    BOOST_CHECK(!AssignableDataSource<int>::narrow(fixed_element.get()));

    AssignableDataSource<unsigned int>::shared_ptr index =
        new ValueDataSource<unsigned int>(3);
    DataSourceBase::shared_ptr dynamic_element = array->getMember(
        index, DataSourceBase::shared_ptr());
    BOOST_REQUIRE(dynamic_element);
    DataSource<int>::shared_ptr dynamic_value =
        DataSource<int>::narrow(dynamic_element.get());
    BOOST_REQUIRE(dynamic_value);
    BOOST_CHECK_EQUAL(dynamic_value->get(), 99);

    index->set(0);
    BOOST_CHECK_EQUAL(dynamic_value->get(), 3);

    DataSourceBase::shared_ptr cloned(dynamic_element->clone());
    DataSource<int>::shared_ptr cloned_value =
        DataSource<int>::narrow(cloned.get());
    BOOST_REQUIRE(cloned_value);
    BOOST_CHECK_EQUAL(cloned_value->get(), 3);
    BOOST_CHECK(!cloned->isAssignable());

    index->set(3);
    BOOST_CHECK_EQUAL(dynamic_value->get(), 99);
    BOOST_CHECK_EQUAL(cloned_value->get(), 99);
    index->set(5);
    BOOST_CHECK_EQUAL(dynamic_value->get(), RTT::internal::NA<int>::na());

    AssignableDataSource<BType>::shared_ptr writable_parent =
        new ValueDataSource<BType>(BType(true));
    DataSourceBase::shared_ptr writable_array =
        writable_parent->getMember("ai");
    BOOST_REQUIRE(writable_array);
    AssignableDataSource<int>::shared_ptr writable_element =
        AssignableDataSource<int>::narrow(
            writable_array->getMember("3").get());
    BOOST_REQUIRE(writable_element);
    writable_element->set(42);
    BOOST_CHECK_EQUAL(writable_parent->get().ai[3], 42);
}

BOOST_AUTO_TEST_CASE( testReadOnlyCArrayElementCopyUsesReplacementParent )
{
    AssignableDataSource<BType>::shared_ptr source =
        new ValueDataSource<BType>(BType(true));
    type_discovery discovery(source, false);
    DataSourceBase::shared_ptr array =
        discovery.discoverMember(source->set(), "ai");
    BOOST_REQUIRE(array);

    AssignableDataSource<unsigned int>::shared_ptr index =
        new ValueDataSource<unsigned int>(3);
    DataSourceBase::shared_ptr element = array->getMember(
        index, DataSourceBase::shared_ptr());
    BOOST_REQUIRE(element);

    AssignableDataSource<BType>::shared_ptr replacement =
        new ValueDataSource<BType>(BType(true));
    replacement->set().ai[3] = 123;
    std::map<const DataSourceBase*, DataSourceBase*> replacements;
    replacements[source.get()] = replacement.get();

    DataSourceBase::shared_ptr copied(element->copy(replacements));
    DataSource<int>::shared_ptr copied_value =
        DataSource<int>::narrow(copied.get());
    BOOST_REQUIRE(copied_value);
    BOOST_CHECK_EQUAL(copied_value->get(), 123);
    BOOST_CHECK(!copied->isAssignable());
}
```

- [ ] **Step 2: Add the failing operation-result scripting regression**

In `tests/scripting_test.cpp`, include `datasource_fixture.hpp`,
`types/StructTypeInfo.hpp`, and `types/CArrayTypeInfo.hpp`. Add this provider in
the anonymous test-file namespace before the test suite:

```cpp
class ReadOnlyCArrayOperationProvider
{
public:
    BType getBatch() const { return BType(true); }
};
```

Add this test beside `TestCallResultIndexing`:

```cpp
BOOST_AUTO_TEST_CASE(TestCallResultCArrayIndexingIsReadOnly)
{
    if (!Types()->type("cints")) {
        Types()->addType(new CArrayTypeInfo<carray<int> >("cints"));
    }
    if (!Types()->type("BType")) {
        Types()->addType(new StructTypeInfo<BType>("BType"));
    }

    ReadOnlyCArrayOperationProvider provider;
    tc->provides("test")->addOperation(
        "getBatch", &ReadOnlyCArrayOperationProvider::getBatch, &provider);

    Parser parser(caller->engine());
    DataSourceBase::shared_ptr result;
    try {
        result = parser.parseExpression("test.getBatch().ai[3]", tc);
    } catch (const parse_exception& error) {
        BOOST_FAIL(error.what());
    }

    BOOST_REQUIRE(result);
    DataSource<int>::shared_ptr value =
        DataSource<int>::narrow(result.get());
    BOOST_REQUIRE(value);
    BOOST_CHECK_EQUAL(value->get(), 99);
    BOOST_CHECK(!result->isAssignable());
}
```

- [ ] **Step 3: Build and verify both regressions fail for the missing behavior**

Run from `toolchain/tools/rtt`:

```bash
cmake --build build --target type_discovery_struct_test scripting_test -j2
env -u LD_LIBRARY_PATH ./build/tests/type_discovery_struct_test --run_test=TypeArchiveTestSuite/testReadOnlyCArrayElementsAreReadable,TypeArchiveTestSuite/testReadOnlyCArrayElementCopyUsesReplacementParent --log_level=test_suite
env -u LD_LIBRARY_PATH ./build/tests/scripting_test --run_test=ScriptingTestSuite/TestCallResultCArrayIndexingIsReadOnly --log_level=test_suite
```

Expected: the direct tests fail because indexed read-only C-array members are
null. The scripting test fails with the current `Illegal use of []` semantic
error. Compilation and fixture registration must succeed before accepting the
red state.

- [ ] **Step 4: Add the read-only indexed datasource**

Forward-declare the new class in `rtt/internal/rtt-internal-fwd.hpp`:

```cpp
template<typename T, typename ArrayT>
class ReadOnlyArrayPartDataSource;
```

Add this class beside `ArrayPartDataSource<T>` in
`rtt/internal/ArrayPartDataSource.hpp`:

```cpp
template<typename T, typename ArrayT>
class ReadOnlyArrayPartDataSource : public DataSource<T>
{
    typename DataSource<ArrayT>::shared_ptr mparent;
    typename DataSource<unsigned int>::shared_ptr mindex;
    unsigned int mmax;

public:
    typedef boost::intrusive_ptr<
        ReadOnlyArrayPartDataSource<T, ArrayT> > shared_ptr;

    ReadOnlyArrayPartDataSource(
        typename DataSource<ArrayT>::shared_ptr parent,
        typename DataSource<unsigned int>::shared_ptr index,
        unsigned int max)
        : mparent(parent), mindex(index), mmax(max) {}

    typename DataSource<T>::result_t get() const
    {
        unsigned int i = mindex->get();
        if (i >= mmax)
            return internal::NA<T>::na();
        return mparent->get().address()[i];
    }

    typename DataSource<T>::result_t value() const
    {
        unsigned int i = mindex->get();
        if (i >= mmax)
            return internal::NA<T>::na();
        return mparent->value().address()[i];
    }

    typename DataSource<T>::const_reference_t rvalue() const
    {
        unsigned int i = mindex->get();
        if (i >= mmax)
            return internal::NA<
                typename DataSource<T>::const_reference_t>::na();
        return mparent->rvalue().address()[i];
    }

    ReadOnlyArrayPartDataSource<T, ArrayT>* clone() const override
    {
        return new ReadOnlyArrayPartDataSource<T, ArrayT>(
            mparent, mindex, mmax);
    }

    ReadOnlyArrayPartDataSource<T, ArrayT>* copy(
        std::map<const base::DataSourceBase*, base::DataSourceBase*>& replace)
        const override
    {
        if (replace[this] != 0) {
            return static_cast<ReadOnlyArrayPartDataSource<T, ArrayT>*>(
                replace[this]);
        }
        typename DataSource<ArrayT>::shared_ptr parent_copy =
            mparent->copy(replace);
        typename DataSource<unsigned int>::shared_ptr index_copy =
            mindex->copy(replace);
        replace[this] = new ReadOnlyArrayPartDataSource<T, ArrayT>(
            parent_copy, index_copy, mmax);
        return static_cast<ReadOnlyArrayPartDataSource<T, ArrayT>*>(
            replace[this]);
    }
};
```

- [ ] **Step 5: Select writable or read-only indexing in `CArrayTypeInfo`**

For numeric-string indexing, parse the index first and retain the current
writable construction when `item` narrows to `AssignableDataSource<T>`. Use the
new datasource otherwise:

```cpp
unsigned int indx = boost::lexical_cast<unsigned int>(name);
typename DataSource<unsigned int>::shared_ptr index =
    new ConstantDataSource<unsigned int>(indx);
if (adata) {
    return new ArrayPartDataSource<typename T::value_type>(
        *adata->set().address(), index, item, data->rvalue().count());
}
return new ReadOnlyArrayPartDataSource<typename T::value_type, T>(
    data, index, data->rvalue().count());
```

For dynamic indexing, convert `id` before selecting the datasource. Replace the
assignable-only error branch with:

```cpp
if (id_indx) {
    typename AssignableDataSource<T>::shared_ptr adata =
        boost::dynamic_pointer_cast<AssignableDataSource<T> >(item);
    if (adata) {
        return new ArrayPartDataSource<typename T::value_type>(
            *adata->set().address(), id_indx, item,
            data->rvalue().count());
    }
    return new ReadOnlyArrayPartDataSource<typename T::value_type, T>(
        data, id_indx, data->rvalue().count());
}
```

Keep the existing invalid-name and invalid-index logging. Do not change the
writable `ArrayPartDataSource` implementation.

- [ ] **Step 6: Rebuild and verify the focused tests pass**

Run from `toolchain/tools/rtt`:

```bash
cmake --build build --target type_discovery_struct_test scripting_test -j2
env -u LD_LIBRARY_PATH ./build/tests/type_discovery_struct_test --run_test=TypeArchiveTestSuite/testReadOnlyCArrayElementsAreReadable,TypeArchiveTestSuite/testReadOnlyCArrayElementCopyUsesReplacementParent --log_level=test_suite
env -u LD_LIBRARY_PATH ./build/tests/scripting_test --run_test=ScriptingTestSuite/TestCallResultCArrayIndexingIsReadOnly --log_level=test_suite
```

Expected: all three regression cases pass with no semantic error and all
returned read-only elements reject `AssignableDataSource<int>` narrowing.

- [ ] **Step 7: Run the affected RTT suites and repository checks**

Run from `toolchain/tools/rtt`:

```bash
env -u LD_LIBRARY_PATH ctest --test-dir build -R '^(scripting_test|type_discovery_struct_test)$' --output-on-failure
git diff --check
git status --short
```

Expected: both CTest suites pass, `git diff --check` reports no errors, and the
status contains only the five intended RTT files.

- [ ] **Step 8: Review and commit the RTT change**

Inspect the production and test diff, then run:

```bash
git add rtt/internal/rtt-internal-fwd.hpp rtt/internal/ArrayPartDataSource.hpp rtt/types/CArrayTypeInfo.hpp tests/type_discovery_struct_test.cpp tests/scripting_test.cpp
git commit -m "fix: support read-only C-array indexing"
```

Expected: one RTT commit containing the datasource, type-info selection, and
both regression layers. The outer `orocos-rock` repository remains unchanged
apart from its already committed design and implementation-plan documents.
