# frozen_string_literal: true

require "typelib"
require "orogen"

header = File.expand_path(ARGV.fetch(0))
registry = Typelib::Registry.import(header, "c")
registry.get("/windows_smoke/Sample")

loader = OroGen::Loaders::PkgConfig.new(ENV.fetch("OROCOS_TARGET", "win32"))
paths = [
    loader.task_library_path_from_name("windows_smoke"),
    loader.typekit_library_path_from_name("windows_smoke"),
    loader.transport_library_path_from_name("windows_smoke", "typelib")
]
missing_paths = paths.reject { |path| File.file?(path) }
unless missing_paths.empty?
    abort "OroGen loader returned missing libraries: #{missing_paths.join(', ')}"
end

puts "Validated Typelib import and OroGen package loading"
