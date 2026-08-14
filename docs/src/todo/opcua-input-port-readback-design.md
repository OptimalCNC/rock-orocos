# OPC UA Input Port Readback

**Status:** Proposed; readback semantics approved in discussion on 2026-08-14.

## Context

The current canonical mapping publishes an RTT input port as a write-only OPC
UA `value` Variable. This accurately reflects that an RTT input port cannot be
observed without consuming data, but it gives generic OPC UA clients a poor
operator experience. UaExpert displays `BadNotReadable` continuously for the
Variable, including after a successful Write.

Making the Variable readable cannot expose component consumption or process
state because a generic RTT input port provides neither. Readback therefore
must be an explicit bridge-owned command history value.

## Decision

`Ports/<input>/value` will advertise both `CurrentRead` and `CurrentWrite`.
Its read value is the last OPC UA sample that the bridge successfully delivered
to the RTT input port.

The contract is:

- Every valid OPC UA Write attempts exactly one RTT delivery, including a Write
  equal to the previously accepted value.
- The bridge updates its readback only after RTT reports `WriteSuccess`.
- Before the first successful delivery, Read and monitoring report
  `BadWaitingForInitialData`.
- A failed Write does not change the readback.
- Read is non-consuming and never reads the RTT input port.
- Readback does not mean that component logic received, consumed, processed, or
  acted on the sample.
- Actual component or process state must be published separately through an
  output port, attribute, property, or operation result.

The stored sample is scoped to the published component instance and exists only
for the lifetime of its OPC UA publication. Republishing a new component
instance starts without readback data.

## Concurrency And Errors

The input Variable backend serializes delivery and readback updates so
concurrent client Writes have an unambiguous order. A successful Write becomes
the readback before the next serialized Write is handled. Reads take a snapshot
of the stored encoded sample.

Existing validation remains:

- an absent value or incompatible datatype/rank returns `BadTypeMismatch`;
- an index-range Write or Read returns `BadIndexRangeInvalid`;
- an unavailable component or bridge returns `BadNotConnected`; and
- only a `Good` RTT delivery status updates readback.

OPC UA subscriptions observe the readback Variable as current state. Multiple
equal Writes are still distinct RTT delivery attempts, although a subscription
with ordinary data-change filtering may not emit another notification for an
equal value.

## Compatibility

Retaining output ports remain read-only latest-value Variables. Non-retaining
outputs still omit canonical `value`. Canonical port Methods remain absent, and
RTT-generated port services remain recursively available under `Services`.

`TaskContextProxy` continues to use an input Variable only for remote Writes.
Discovery changes its required input access schema from write-only to
read/write; it does not treat readback as an RTT input sample or component
acknowledgement.

## Verification

Publisher and deployment tests will verify:

- exact read/write access metadata;
- `BadWaitingForInitialData` before the first accepted Write;
- successful Write followed by readable matching data;
- two equal Writes still produce two RTT `NewData` deliveries;
- invalid and failed Writes do not replace the last accepted readback;
- readback monitoring after a successful Write; and
- unchanged output, non-retaining-output, proxy, and generated-service
  behavior.

The temporary deployment probe will verify the same behavior through UaExpert
and its direct OPC UA client.
