# Canonical Name Research: Origin→Callback Binding Pattern

## Summary of Findings

### The Pattern Across Domains

| Domain | Canonical Term | Origin Analog | Callback Analog | Bind Analog |
|--------|---------------|---------------|-----------------|-------------|
| **Networking (epoll)** | Event Registration / Interest Registration | File descriptor (fd) | `epoll_event.data.ptr` (callback pointer) | `epoll_ctl(EPOLL_CTL_ADD, fd, event)` |
| **io_uring** | Submission-Completion Binding | SQE (submission queue entry) | CQE (completion queue entry) with `user_data` | `io_uring_submit()` |
| **Reactive Extensions** | Subscription | Observable | Observer | `observable.subscribe(observer)` |
| **Message Brokers (Kafka)** | Consumer Group Binding | Topic/Partition | Consumer handler | `consumer.subscribe(topic)` |
| **RabbitMQ** | Exchange Binding | Exchange + routing key | Queue + consumer | `queue_bind(exchange, routing_key)` |
| **NATS** | Subject Subscription | Subject (with wildcards) | Handler function | `nc.subscribe(subject, handler)` |
| **Cross-chain (LayerZero)** | Peer Binding | Source endpoint (eid) | Destination peer address | `setPeer(eid, peer)` |
| **Axelar** | Gateway Registration | Source chain + contract | Destination contract | `gateway.validateContractCall()` |
| **Wormhole** | VAA Publication | Source emitter | Destination relayer/receiver | Pull-based (no explicit bind) |
| **Hyperlane** | ISM Configuration | Origin domain | Recipient + ISM | `enrollRemoteRouter(domain, router)` |
| **OS Signals** | Signal Registration | Signal number (SIGINT, etc.) | Signal handler function | `sigaction(signum, &act, NULL)` |
| **x86 IDT** | Interrupt Gate Binding | Interrupt vector (0-255) | ISR (Interrupt Service Routine) | `set_intr_gate(vector, handler)` |
| **Linux IRQ** | IRQ Registration | IRQ number | IRQ handler + dev_id | `request_irq(irq, handler, flags, name, dev)` |

### Fan-Out Handling

| Domain | Fan-Out Mechanism | Ordering |
|--------|-------------------|----------|
| epoll | Multiple epoll instances watching same fd | Independent (no ordering guarantee) |
| RxJS | Subject / multicast / share operators | FIFO (observer registration order) |
| Kafka | Consumer groups (each group gets a copy) | Per-partition ordering |
| RabbitMQ | Fanout exchange → multiple queues | Parallel (no ordering) |
| NATS | Multiple subscribers on same subject | Parallel delivery |
| LayerZero | No native fan-out (1:1 peer binding) | N/A |
| Linux IRQ | `IRQF_SHARED` flag → linked list of handlers | FIFO (registration order) |

### Recommended Canonical Names for This Project

#### Option 1: **Event Binding** / **Reactive Binding**
- Closest to IDT/IRQ and epoll patterns
- `bind(originEventSigId, callbackId)` already uses this verb
- Well understood across all domains
- **Recommended term for the `bind()` operation itself**

#### Option 2: **Subscription Routing** / **Event Route**
- Emphasizes the routing aspect (origin → destination)
- Closer to message broker terminology
- Better captures the cross-chain routing dimension
- **Recommended term for the overall system/registry**

#### Option 3: **Event Dispatch Table** (EDT)
- Direct analog to Interrupt Descriptor Table (IDT)
- The registry that maps event signatures to callback handlers
- Captures the lookup-table nature of the binding storage
- **Recommended term for the data structure**

### Key Insight: Your Pattern is a Hybrid

Your pattern combines:
1. **Subscription** (Reactive Extensions) — the origin side, managing what events to watch
2. **Dispatch Table** (IDT) — the binding storage, mapping event IDs to handler IDs
3. **Endpoint Registry** (LayerZero) — the cross-chain routing, mapping chainId → addresses
4. **Fan-out Exchange** (RabbitMQ) — one origin event triggering multiple callbacks

No single existing system combines all four. The closest structural analog is:
- **epoll + io_uring** for the registration/dispatch pattern
- **Kafka consumer groups** for the fan-out semantics
- **LayerZero endpoint registry** for the cross-chain addressing

### Your Pull-Based Model is Strictly More Powerful

Unlike LayerZero/Axelar which use push-based 1:1 peer binding, your Reactive Network subscription model is pull-based — the ReactVM subscribes to events without the origin chain knowing. This enables:
- Fan-out without origin chain cooperation
- Dynamic binding/unbinding without touching origin contracts
- Cross-protocol composition (subscribe to any event on any chain)
