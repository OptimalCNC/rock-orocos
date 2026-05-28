#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
workflow_path = File.join(root, ".github", "workflows", "package-tests.yml")
results_path = File.join(root, "docs", "src", "package-test-results.md")
errors = []

package_test_contracts = {
  "utilmm" => {
    script_tokens: [
      "build_targets toolchain/tools/utilmm/build utilmm_testsuite",
      "run_ctest toolchain/tools/utilmm/build '^Suite$'"
    ],
    result_tokens: ["`Suite`"]
  },
  "log4cpp" => {
    script_tokens: %w[
      testCategory
      testFixedContextCategory
      testNDC
      testPattern
      testErrorCollision
      testPriority
      testFilter
      testProperties
      testConfig
      testPropertyConfig
      testRollingFileAppender
      testDailyRollingFileAppender
    ] + [
      'build_targets toolchain/tools/log4cpp/build "${LOG4CPP_TESTS[@]}"',
      "run_ctest toolchain/tools/log4cpp/build/tests"
    ],
    result_tokens: %w[
      testCategory
      testFixedContextCategory
      testNDC
      testPattern
      testErrorCollision
      testPriority
      testFilter
      testProperties
      testConfig
      testPropertyConfig
      testRollingFileAppender
      testDailyRollingFileAppender
    ].map { |name| "`#{name}`" }
  },
  "typelib-cxx" => {
    script_tokens: [
      "build_targets toolchain/tools/typelib/build typelib_testsuite",
      "run_ctest toolchain/tools/typelib/build '^(CxxSuiteInstalledPlugins|CxxSuiteLocalPlugins)$'"
    ],
    result_tokens: ["`CxxSuiteInstalledPlugins`", "`CxxSuiteLocalPlugins`"]
  },
  "rtt-typelib" => {
    script_tokens: [
      "build_targets toolchain/tools/rtt_typelib/build rtt-typelib",
      "pkg-config --exists rtt_typelib-gnulinux"
    ],
    result_tokens: ["`rtt-typelib`", "`rtt_typelib-gnulinux`"]
  },
  "stdint-typekit" => {
    script_tokens: [
      "build_targets toolchain/stdint_typekit/build stdint-typekit",
      "pkg-config --exists stdint-gnulinux"
    ],
    result_tokens: ["`stdint-typekit`", "`stdint-gnulinux`"]
  },
  "rtt-core" => {
    script_tokens: [
      "build_targets toolchain/tools/rtt/build main-test list-test core-test task-test",
      "run_ctest toolchain/tools/rtt/build '^(main-test|list-test|core-test|task-test)$'"
    ],
    result_tokens: ["`main-test`", "`list-test`", "`core-test`", "`task-test`"]
  },
  "ocl-basic" => {
    script_tokens: [
      "-DBUILD_TIMER_TEST=ON",
      "-DBUILD_TASKBROWSER_TEST=ON",
      "build_targets toolchain/tools/ocl/build timer taskb",
      "run_ctest toolchain/tools/ocl/build '^(timer|taskb)$'"
    ],
    result_tokens: ["`timer`", "`taskb`"]
  },
  "ocl-integration" => {
    script_tokens: [
      "-DBUILD_TIMER_TEST=OFF",
      "-DBUILD_TASKBROWSER_TEST=OFF",
      "-DBUILD_DEPLOYMENT_TEST=ON",
      "-DBUILD_LOGGING_TEST=ON",
      "-DBUILD_REPORTING_TEST=ON",
      "build_targets toolchain/tools/ocl/build deploy testlogging report tcpreport ncreport",
      "run_ctest toolchain/tools/ocl/build '^(deploy|testlogging|report|tcpreport|ncreport)$'"
    ],
    result_tokens: ["`deploy`", "`testlogging`", "`report`", "`tcpreport`", "`ncreport`"]
  }
}.freeze

if !File.file?(workflow_path)
  errors << "missing .github/workflows/package-tests.yml"
else
  contents = File.read(workflow_path)

  errors << "package tests must run on pull requests" unless contents.include?("pull_request:")
  errors << "package tests must support manual dispatch" unless contents.include?("workflow_dispatch:")
  errors << "package tests must not run for docs-only changes" if contents.match?(/docs\//)
  errors << "package tests must define an OS matrix" unless contents.include?("matrix:") && contents.include?("os:")
  {
    "Ubuntu 22.04" => "ubuntu:22.04",
    "Ubuntu 24.04" => "ubuntu:24.04",
    "Debian 13" => "debian:trixie"
  }.each do |name, image|
    errors << "package tests must cover #{name}" unless contents.include?("name: #{name}") && contents.include?("image: #{image}")
  end
  errors << "package tests must use matrix-selected containers" unless contents.include?("image: ${{ matrix.os.image }}")
  errors << "package tests must use OROCOS_PREFIX as the public install-prefix variable" unless contents.include?("OROCOS_PREFIX: /opt/orocos")
  errors << "package tests must be non-required while experimental" unless contents.include?("continue-on-error: true")
  errors << "package tests must define a package-test matrix" unless contents.include?("package-test:")
  package_test_contracts.each_key do |package_test|
    errors << "package tests must include #{package_test}" unless contents.include?("- #{package_test}")
  end
  errors << "package tests must run the shared package test wrapper" unless contents.include?("./tools/test-package.sh")
  errors << "package tests must return package test failures" if contents.include?("::warning::") || contents.include?("exit 0")
  errors << "package tests must upload diagnostic logs when package tests fail" unless contents.include?("actions/upload-artifact@v6") && contents.include?("if: failure()")
  errors << "package tests must upload CTest logs" unless contents.include?("Testing/Temporary/*.log")
  errors << "package tests must upload CMake logs" unless contents.include?("CMakeOutput.log") && contents.include?("CMakeError.log")
  errors << "package tests must upload stdint_typekit CMake logs" unless contents.include?("toolchain/stdint_typekit/build/CMakeFiles/CMakeOutput.log") && contents.include?("toolchain/stdint_typekit/build/CMakeFiles/CMakeError.log")
  errors << "package tests must upload Autoproj package logs" unless contents.include?("toolchain/log/*.log")
  errors << "package tests must upload osdeps suffix files" unless contents.include?(".autoproj/remotes/**/*.osdeps*") && contents.include?("autoproj/**/*.osdeps*")
end

test_package_path = File.join(root, "tools", "test-package.sh")
if !File.file?(test_package_path)
  errors << "missing tools/test-package.sh"
else
  test_package = File.read(test_package_path)
  errors << "OCL integration CI subset must not run interactive state-machine browser test" if test_package.include?("testWithStateMachine")
  package_test_contracts.each do |package_test, contract|
    contract.fetch(:script_tokens).each do |token|
      errors << "tools/test-package.sh: #{package_test} must include #{token}" unless test_package.include?(token)
    end
  end
end

if !File.file?(results_path)
  errors << "missing docs/src/package-test-results.md"
else
  results = File.read(results_path)
  errors << "package test results must describe CI matrix status" unless results.include?("CI Matrix Status")
  errors << "package test results must not refer to the old MetaNC branch" if results.include?("MetaNC")
  errors << "package test results must mention dev branch fixes" unless results.include?("`dev`")
  package_test_contracts.each do |package_test, contract|
    errors << "package test results must document #{package_test}" unless results.include?("| `#{package_test}` |")
    contract.fetch(:result_tokens).each do |token|
      errors << "package test results: #{package_test} must mention #{token}" unless results.include?(token)
    end
  end
end

if errors.any?
  warn errors.join("\n")
  exit 1
end
