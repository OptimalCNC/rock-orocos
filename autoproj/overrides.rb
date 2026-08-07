# This file is loaded after package-set definitions.
#
# Use it for small build-configuration corrections that cannot live in package
# metadata yet. Source repository choices belong in autoproj/overrides.yml.

setup_package "rtt" do |pkg|
  pkg.use_package_xml = true
  pkg.depends_on "rtlog-cpp"
  pkg.define "ENABLE_MQ", "ON"
  pkg.define "ENABLE_CORBA", "OFF"
end

setup_package "ocl" do |pkg|
  pkg.depends_on "rtt_opcua"
  pkg.define "BUILD_OPCUA", "ON"
end
