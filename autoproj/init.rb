# Define the github: shorthand used by imported Rock package sets.
require "autoproj/git_server_configuration"

# Keep builds repeatable by letting the build configuration define the
# toolchain environment explicitly.
Autoproj.isolate_environment

Autobuild::CMake.show_make_messages = true
