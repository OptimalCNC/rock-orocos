#!/usr/bin/env ruby

# Linux source builds use one Boost SDK for RTT, HTTP, and every consumer.
# Package builds supply their own compatible SDK through DEPENDENCY_PREFIX.
require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

abort "usage: install-native-boost.rb PREFIX" unless ARGV.size == 1
prefix = File.expand_path(ARGV.fetch(0))
root = File.expand_path("..", __dir__)
lock = JSON.parse(File.read(File.join(root, "packaging/native-boost.json")))
version = lock.fetch("version")
digest = lock.fetch("sha256")
abort "invalid Boost dependency pin" unless version.match?(/\A\d+\.\d+\.\d+\z/) &&
  digest.match?(/\A[0-9a-f]{64}\z/) && lock.fetch("libraries").all? { |name| name.match?(/\A[a-z_]+\z/) }

def run!(*command)
  abort "command failed: #{command.first}" unless system(*command)
end

external = ENV["OROCOS_ROCK_DEPENDENCY_PREFIX"]
if external && !external.empty?
  # rtt_http's configure checks JSON and its supported minimum version in
  # the explicitly selected SDK. Do not overwrite package-managed Boost.
  warn "Using Boost from dependency SDK #{external}"
  exit 0
end

toolchain = File.join(prefix, "toolchain")
stamp = File.join(toolchain, "share/boost/orocos-native-build.json")
compiler = ENV.fetch("CXX", "c++")
compiler_version, status = Open3.capture2e(compiler, "--version")
abort "cannot identify C++ compiler #{compiler}" unless status.success?
identity = { "archive_sha256" => digest, "compiler" => compiler_version,
             "libraries" => lock.fetch("libraries") }
if File.file?(stamp) && JSON.parse(File.read(stamp)) == identity &&
   File.file?(File.join(toolchain, "lib/cmake/Boost-#{version}/BoostConfig.cmake")) &&
   File.file?(File.join(toolchain, "lib/libboost_json.so"))
  warn "Native Boost #{version} is already installed"
  exit 0
end

Dir.mktmpdir("orocos-native-boost.") do |temporary|
  archive = File.join(temporary, "boost.tar.xz")
  run!("curl", "--fail", "--location", "--retry", "3", "--output", archive, lock.fetch("url"))
  abort "Boost archive checksum mismatch" unless Digest::SHA256.file(archive).hexdigest == digest
  run!("tar", "-xf", archive, "-C", temporary)
  source = File.join(temporary, "boost-#{version}")
  build = File.join(temporary, "build")
  run!("cmake", "-S", source, "-B", build,
       "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_CXX_STANDARD=20",
       "-DCMAKE_INSTALL_PREFIX=#{toolchain}", "-DCMAKE_INSTALL_LIBDIR=lib",
       "-DBUILD_SHARED_LIBS=ON", "-DBUILD_TESTING=OFF",
       "-DBOOST_INCLUDE_LIBRARIES=#{lock.fetch('libraries').join(';')}")
  run!("cmake", "--build", build, "--parallel", ENV.fetch("JOBS", "2"))
  run!("cmake", "--install", build)
  notices = File.join(toolchain, "share/licenses/boost")
  FileUtils.mkdir_p(notices)
  FileUtils.cp(File.join(source, "LICENSE_1_0.txt"), notices)
  FileUtils.cp(File.join(root, "packaging/native-boost.json"), notices)
  FileUtils.mkdir_p(File.dirname(stamp))
  File.write(stamp, JSON.pretty_generate(identity) + "\n")
end
