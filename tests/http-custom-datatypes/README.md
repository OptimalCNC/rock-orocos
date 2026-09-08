# HTTP codec SDK consumer

This fixture builds against an installed `rtt_http` SDK. It reuses the ordinary
RTT example types and components from the OPC UA fixture, then builds a
separate HTTP transport plugin. The ordinary targets link neither protocol.
The check verifies registration through RTT's loader, reflected composite
schemas, complete-value validation and assignment, and typed retained samples.
No OPC UA codec or server is required.

After activating the development prefix:

```sh
cmake -S tests/http-custom-datatypes -B build-http-fixture
cmake --build build-http-fixture --parallel 2
ctest --test-dir build-http-fixture --output-on-failure
```

This check validates the codec SDK boundary. HTTP routes and the OCL service
lifecycle have separate integration checks.
