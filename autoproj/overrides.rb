# This file is loaded after package-set definitions.
#
# Use it for small build-configuration corrections that cannot live in package
# metadata yet. Source repository choices belong in autoproj/overrides.yml.

setup_package "rtt" do |pkg|
  pkg.use_package_xml = true
  pkg.depends_on "rtlog-cpp"
  pkg.define "ENABLE_MQ", "ON"
  pkg.define "ENABLE_CORBA", "OFF"

  # RTT's package.xml currently declares its optional CORBA backend as a
  # required dependency. Keep the resolved dependency graph consistent with
  # the no-CORBA build contract.
  pkg.post_import do
    pkg.description.dependencies.delete_if { |dependency| dependency.name == "omniorb" }
    pkg.remove_dependency "omniorb"
  end
end

setup_package "ocl" do |pkg|
  pkg.depends_on "rtt_opcua"
  pkg.define "BUILD_OPCUA", "ON"
end
