#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)

packages = {
  "farbot" => File.join(root, "toolchain", "farbot", "CMakeLists.txt"),
  "rtlog-cpp" => File.join(root, "toolchain", "rtlog-cpp", "CMakeLists.txt"),
  "rtt" => File.join(root, "toolchain", "tools", "rtt", "CMakeLists.txt"),
  "ocl" => File.join(root, "toolchain", "tools", "ocl", "CMakeLists.txt"),
  "typelib" => File.join(root, "toolchain", "tools", "typelib", "CMakeLists.txt"),
  "utilmm" => File.join(root, "toolchain", "tools", "utilmm", "CMakeLists.txt"),
  "rtt_typelib" => File.join(root, "toolchain", "tools", "rtt_typelib", "CMakeLists.txt")
}

orogen_project = File.join(root, "toolchain", "tools", "orogen", "lib", "orogen", "gen", "project.rb")
orogen_typekit = File.join(root, "toolchain", "tools", "orogen", "lib", "orogen", "gen", "typekit.rb")

errors = []

packages.each do |package, path|
  unless File.file?(path)
    errors << "#{package}: missing #{path.sub("#{root}/", "")}"
    next
  end

  contents = File.read(path)
  errors << "#{package}: CMAKE_CXX_STANDARD must be 20" unless contents.match?(/set\s*\(\s*CMAKE_CXX_STANDARD\s+20\s*\)/i)
  errors << "#{package}: CMAKE_CXX_STANDARD_REQUIRED must be ON" unless contents.match?(/set\s*\(\s*CMAKE_CXX_STANDARD_REQUIRED\s+ON\s*\)/i)
  errors << "#{package}: CMAKE_CXX_EXTENSIONS must be OFF" unless contents.match?(/set\s*\(\s*CMAKE_CXX_EXTENSIONS\s+OFF\s*\)/i)
end

{
  "orogen project default" => orogen_project,
  "orogen typekit default" => orogen_typekit
}.each do |label, path|
  unless File.file?(path)
    errors << "#{label}: missing #{path.sub("#{root}/", "")}"
    next
  end

  errors << "#{label}: must default to c++20" unless File.read(path).include?('@cxx_standard = "c++20"')
end

if errors.any?
  warn errors.join("\n")
  exit 1
end
