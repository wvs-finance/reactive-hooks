# Equivalent Implementations Research: Origin→Callback Binding Engineering

## 1. Berkeley Sockets / epoll / io_uring

### epoll: The Closest Structural Analog

```c
// Registration (= your bind())
struct epoll_event ev;
ev.events = EPOLLIN;           // = event signature filter
ev.data.ptr = callback_ctx;    // = callbackId (pointer to handler context)
epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev);  // = bind(originEventSigId, callbackId)

// Deregistration (= your unbind())
epoll_ctl(epfd, EPOLL_CTL_DEL, fd, NULL); // = unbind(originEventSigId)
```

**Storage**: Red-black tree (`fs/eventpoll.c`) keyed by fd. Ready list as linked list.
**Fan-out**: Multiple epoll instances can watch the same fd independently.
**Lifecycle**: `close(fd)` auto-purges all epoll registrations (cleanup on destroy).

### io_uring: Completion-Based Model

```c
struct io_uring_sqe *sqe = io_uring_get_sqe(ring);
io_uring_prep_read(sqe, fd, buf, len, 0);  // origin spec
sqe->user_data = callback_id;               // callback binding
io_uring_submit(ring);                       // = subscribe + schedule

// On completion:
struct io_uring_cqe *cqe;
io_uring_wait_cqe(ring, &cqe);
handle(cqe->user_data);  // dispatch to bound callback
```

**Key insight**: io_uring's `user_data` echo pattern is closest to your model — you attach a callback identifier at submission time, and it's echoed back on completion for dispatch.

### Mapping to Your Architecture

| epoll/io_uring | Your System |
|---|---|
| `fd` (file descriptor) | `(chainId, address, eventSig)` — origin endpoint |
| `epoll_event.data.ptr` | `callbackId` |
| `epoll_ctl(ADD)` | `bind()` → `subscribe()` + `schedule()` |
| `epoll_ctl(DEL)` | `unbind()` → `unsubscribe()` |
| `epoll_wait()` | ReactVM's `react(LogRecord)` |
| `close(fd)` auto-cleanup | Contract destruction / pause |

## 2. Reactive Extensions (RxJS / Reactor / Akka)

### Observable → subscribe → Observer

```typescript
// Origin definition
const origin$ = new Observable(subscriber => {
    // event source (= your origin endpoint)
    subscriber.next(eventData);
});

// Binding (= your bind())
const subscription = origin$.subscribe({
    next: (data) => callback(data),    // = callbackId handler
    error: (err) => handleError(err),
    complete: () => cleanup()
});

// Unbinding
subscription.unsubscribe();  // = unbind()
```

### Fan-Out via Subject / Multicast

```typescript
// Single origin, multiple callbacks (= your address[] fan-out)
const subject = new Subject();
subject.subscribe(callback1);  // bind(originId, callback1)
subject.subscribe(callback2);  // bind(originId, callback2)

// Internal storage: Subject.observers[] array — FIFO ordering
```

**Key patterns**:
- **Cold Observable** (unicast): Each subscriber gets independent execution — like separate subscriptions
- **Hot Observable** (multicast via Subject): All subscribers share same event stream — like your fan-out model
- `BehaviorSubject`: Replays last value on subscribe (potential replay-on-subscribe semantic)
- `ReplaySubject`: Replays N values on subscribe

### Mapping

| RxJS | Your System |
|---|---|
| Observable | Origin (chainId + address + eventSig) |
| Observer | Callback endpoint (chainId + address + selector) |
| `subscribe()` | `bind()` |
| `unsubscribe()` | `unbind()` |
| Subject (multicast) | Origin with address[] fan-out |
| `pipe(filter(...))` | Subscription topic filters (REACTIVE_IGNORE) |

## 3. Message Brokers

### Kafka

```
Topic (origin) → Partitions → Consumer Groups → Handlers (callbacks)
```

- **Each reactive contract = its own consumer group** — gets full copy of all events
- Fan-out is automatic: N consumer groups = N copies of each message
- Within a group, partitions distribute load (not relevant to your model)
- **Closest to your model**: Topic subscription with consumer group isolation

### RabbitMQ

```
Producer → Exchange → Binding → Queue → Consumer
                        ↑
                  routing_key filter
```

- **Fanout Exchange**: Broadcasts to ALL bound queues — closest to your fan-out
- **Headers Exchange**: Matches on message headers — closest to your 6-param subscription filter
  - `x-match: all` = all headers must match (like your non-REACTIVE_IGNORE fields)
  - Your REACTIVE_IGNORE = wildcard header match
- **Binding** = your `bind()`: connects exchange to queue with routing criteria

### NATS

```
nc.subscribe("chain.1.0xddf252.*", handler);  // subject hierarchy with wildcards
```

- Subject hierarchy maps naturally to: `chain.{chainId}.{contractAddress}.{eventSig}`
- `*` wildcard = REACTIVE_IGNORE
- Multiple subscribers on same subject = fan-out

### Mapping

| Kafka/RabbitMQ | Your System |
|---|---|
| Topic / Exchange | Origin (chainId, address, eventSig) |
| Consumer Group / Queue | Callback endpoint |
| Consumer handler | Callback function selector |
| `subscribe(topic)` / `queue_bind()` | `bind()` |
| Fanout exchange | Origin → multiple callback chains |
| Headers exchange filter | 6-param subscription with REACTIVE_IGNORE |

## 4. Cross-Chain Messaging

### LayerZero V2

```solidity
// Static peer binding (= your bind, but 1:1 only)
function setPeer(uint32 _eid, bytes32 _peer) public onlyOwner {
    peers[_eid] = _peer;  // mapping(uint32 eid => bytes32 peer)
}

// Callback entry point
function _lzReceive(
    Origin calldata _origin,  // (srcEid, sender, nonce)
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
) internal override { ... }
```

**Limitations vs your model**:
- 1:1 peer binding (no fan-out)
- Push-based: sender must know destination
- No subscription filtering — all messages from peer arrive

### Hyperlane

```solidity
// Router enrollment (= your endpoint registration)
function enrollRemoteRouter(uint32 _domain, bytes32 _router) external onlyOwner {
    _enrollRemoteRouter(_domain, _router);
}

// Per-recipient ISM (Interchain Security Module)
function interchainSecurityModule() external view returns (IInterchainSecurityModule);
```

**Key insight**: Hyperlane's ISM-per-recipient pattern = your callback proxy authentication. Each destination has its own trust model.

### Your Model is Strictly More Powerful

| Feature | LayerZero | Axelar | Wormhole | Hyperlane | **Your System** |
|---------|-----------|--------|----------|-----------|----------------|
| Fan-out | No (1:1) | No (1:1) | Yes (pull) | No (1:1) | **Yes (N callbacks)** |
| Origin awareness | Required | Required | Not required | Required | **Not required** |
| Dynamic binding | Owner-only | Gateway | N/A | Owner-only | **Per-instance** |
| Event filtering | None | None | None | None | **6-param filter** |
| Pull-based | No | No | Yes | No | **Yes** |

## 5. Interrupt Descriptor Tables / Signal Handlers

### x86-64 IDT

```c
// Fixed 256-entry array of gate descriptors
struct idt_entry {
    uint16_t offset_low;     // ISR address bits 0-15
    uint16_t selector;       // code segment selector
    uint8_t  ist;            // interrupt stack table
    uint8_t  type_attr;      // gate type + DPL + present
    uint16_t offset_mid;     // ISR address bits 16-31
    uint32_t offset_high;    // ISR address bits 32-63
    uint32_t reserved;
};

// Registration (= your bind())
set_intr_gate(vector_number, handler_address);
```

**Storage**: Fixed-size array (256 entries), indexed by vector number.
**Fan-out**: Not native — but Linux adds chaining via `IRQF_SHARED`.

### Linux IRQ with Shared Interrupts

```c
// Registration with fan-out support
request_irq(irq_number, handler_func, IRQF_SHARED, "device_name", dev_id);

// Internal: linked list of handlers per IRQ
struct irqaction {
    irq_handler_t handler;
    void *dev_id;
    struct irqaction *next;  // linked list for fan-out
};
```

**Fan-out**: `IRQF_SHARED` flag enables multiple handlers on same IRQ — linked list, FIFO order.
**Cleanup**: `free_irq(irq, dev_id)` removes specific handler from chain.

### POSIX Signals

```c
struct sigaction act;
act.sa_handler = my_handler;  // callback
sigaction(SIGINT, &act, NULL); // bind(signal_number, handler)
```

### Mapping

| IDT/IRQ | Your System |
|---|---|
| Interrupt vector number | `originEventSigId` |
| ISR (Interrupt Service Routine) | Callback handler |
| `set_intr_gate()` / `request_irq()` | `bind()` |
| `free_irq()` | `unbind()` |
| `IRQF_SHARED` linked list | `address[]` fan-out |
| Gate descriptor DPL | Callback proxy authentication |
| IDT (fixed array) | Event Dispatch Table (mapping) |

## 6. Cross-Cutting Engineering Decisions

### Binding Storage

| System | Structure | Lookup | Your Analog |
|--------|-----------|--------|-------------|
| epoll | Red-black tree (by fd) | O(log n) | `mapping(bytes32 => ...)` |
| IDT | Fixed array [256] | O(1) | Could use if IDs are sequential |
| RxJS Subject | Dynamic array `observers[]` | O(n) iterate | `address[]` per origin |
| Kafka | Zookeeper/KRaft metadata | Distributed consensus | On-chain mapping |
| LayerZero | `mapping(uint32 => bytes32)` | O(1) | `mapping(uint32 => address[])` |

### Fan-Out Ordering

| System | Order | Guarantee |
|--------|-------|-----------|
| RxJS Subject | FIFO (registration order) | Synchronous in-order |
| RabbitMQ Fanout | Parallel (no order) | Independent delivery |
| Linux `IRQF_SHARED` | FIFO (registration order) | Synchronous chain |
| **Your callbacks** | Parallel (separate `Callback` events) | **Independent execution** |

### Lifecycle Management

| System | Add | Remove | Pause/Resume |
|--------|-----|--------|-------------|
| epoll | `EPOLL_CTL_ADD` | `EPOLL_CTL_DEL` | `EPOLL_CTL_MOD` (change events) |
| RxJS | `subscribe()` | `unsubscribe()` | No native (use operators) |
| Kafka | `subscribe(topic)` | `unsubscribe()` | `pause(partitions)` / `resume()` |
| Linux IRQ | `request_irq()` | `free_irq()` | `disable_irq()` / `enable_irq()` |
| **Your system** | `bind()` | `unbind()` | **Gap: no pause/resume** |

### Recommendations for Your Design

1. **Subscription handles**: Return an ID from `bind()` for lifecycle management (like RxJS `Subscription`)
2. **Pause/resume**: Consider `AbstractPausableReactive` integration — `disable_irq()`/`enable_irq()` analog
3. **Auto-cleanup**: Like `close(fd)` purging epoll entries — contract destruction should unbind all
4. **Deduplication**: Kafka consumer groups handle this — consider replay protection
5. **Backpressure**: io_uring's bounded SQ/CQ — consider gas-based throttling
