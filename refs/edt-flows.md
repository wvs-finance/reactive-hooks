# Event Dispatch Table (EDT) — Testable Flows

## Design Decisions (from brainstorming)

- **Motivation**: Declarative origin→callback registry with multi-chain fan-out (A+B)
- **Self-sync**: `bind()` auto-detects Reactive Network chainIds and routes through self-subscription
- **Chain ID type**: `uint32` for both origin and callback
- **Endpoints**: Contract addresses mapped to event sigs (origin) / selectors (callback) via `AddressToBytes32`
- **Origin identity**: Dual — hierarchical storage for enumeration + `keccak256` hash for O(1) lookup (C)
- **Pause/resume**: Per-binding granularity
- **Origin lifecycle**: Independent from bindings — origins exist regardless of bound callbacks (B)
- **Architecture**: Approach 3 — EDT as Storage Module + Stateless Dispatch (Mod+Lib pattern)
- **Funding**: Quote-then-fund, not fund-then-revert (Reactive Network keeps ETH on revert)
- **Three bind modes**: Immediate (funding-aware), Scheduled (paused), Auto-activate (self-sync on funding)
- **Storage primitive**: Custom doubly-linked list (~100 lines, based on vittominacori pattern, with bytes32 nodes, free functions, pause/skip semantics)

## Architecture (Approach 3)

```
EventDispatchStorageMod    ← storage layout (the table itself)
  └── struct EDTStorage { origins, callbacks, bindings, pauseState }

EventDispatchLib           ← stateless functions operating on EDTStorage
  └── bind / unbind / pause / resume / dispatch

OriginLib                  ← wraps SubscriptionLib with origin registration
CallbackLib                ← callback endpoint management
```

## Flow Definitions

### F1 — Origin Identity (determinism + injectivity + registration)

**What we're proving:** `originId` is deterministic (same inputs → same hash) and injective (different inputs → different hash). The hierarchical storage allows enumeration by chainId. Both representations stay in sync.

**Test scenarios:**

```
F1.1 — Determinism
  Given: OriginEndpoint(chainId=1, emitter=0xAAA, eventSig=SWAP_SIG)
  When:  originId(endpoint) called twice
  Then:  results are identical

F1.2 — Injectivity (different eventSig)
  Given: endpoint_a with eventSig=SWAP_SIG, endpoint_b with eventSig=MINT_SIG
  When:  originId(a), originId(b)
  Then:  ids differ

F1.3 — Injectivity (different chainId)
  Given: endpoint_a with chainId=1, endpoint_b with chainId=42161
  Then:  ids differ

F1.4 — Injectivity (different emitter)
  Given: endpoint_a with emitter=0xAAA, endpoint_b with emitter=0xBBB
  Then:  ids differ

F1.5 — Register + enumerate
  Given: registerOrigin(chainId=1, emitter=0xAAA, eventSig=SWAP_SIG)
         registerOrigin(chainId=1, emitter=0xAAA, eventSig=MINT_SIG)
         registerOrigin(chainId=42161, emitter=0xBBB, eventSig=SWAP_SIG)
  When:  getOriginsByChain(1)
  Then:  returns 2 entries (0xAAA+SWAP, 0xAAA+MINT)
  When:  getOriginsByChain(42161)
  Then:  returns 1 entry (0xBBB+SWAP)
  When:  lookupOrigin(originId(first_endpoint))
  Then:  returns the OriginEndpoint struct (hash→hierarchical round-trip)

F1.6 — Duplicate registration is idempotent
  Given: registerOrigin(chainId=1, emitter=0xAAA, eventSig=SWAP_SIG) called twice
  Then:  no revert, getOriginsByChain(1) still returns 1 entry
```

**Minimum code to write:**
1. `OriginEndpoint` struct + `originId()` pure function (types)
2. `OriginRegistryStorage` struct with dual storage (storage mod)
3. `registerOrigin()` + `getOriginsByChain()` + `lookupOrigin()` (lib functions)
4. A test harness contract that exposes these for Foundry

**What we're NOT writing yet:** callbacks, bindings, subscriptions, funding, self-sync.

---

### F2 — Self-Sync Origin Detection

**What we're proving:** When `chainId` is a Reactive Network chain (LASNA or REACTIVE_MAINNET), `registerOrigin()` routes through self-subscription instead of cross-chain subscription.

**Test scenarios:**

```
F2.1 — Self-sync detection (LASNA)
  Given: registerOrigin(chainId=5318007, emitter=0xSELF, eventSig=SIG)
  Then:  isSelfSync(5318007) returns true
  Then:  subscription routed via reactiveNetworkSingleSubscription()

F2.2 — Self-sync detection (REACTIVE_MAINNET)
  Given: registerOrigin(chainId=1597, emitter=0xSELF, eventSig=SIG)
  Then:  isSelfSync(1597) returns true

F2.3 — Cross-chain detection
  Given: registerOrigin(chainId=1, emitter=0xPOOL, eventSig=SWAP_SIG)
  Then:  isSelfSync(1) returns false
  Then:  subscription routed via reactVMSingleSubscription()
```

**Depends on:** F1 (origin types + registration)

---

### F3 — Callback Identity

**What we're proving:** `callbackId` is deterministic and injective. Callback endpoints can be registered and looked up.

**Test scenarios:**

```
F3.1 — Determinism
  Given: CallbackEndpoint(chainId=1, target=0xADAPTER, selector=0x12345678, gasLimit=500000)
  When:  callbackId(endpoint) called twice
  Then:  results are identical

F3.2 — Injectivity (different selector)
  Given: callback_a with selector=onV3Swap.selector, callback_b with selector=onV3Mint.selector
  Then:  callbackId(a) != callbackId(b)

F3.3 — Injectivity (different target)
  Given: callback_a with target=0xAAA, callback_b with target=0xBBB
  Then:  callbackId(a) != callbackId(b)

F3.4 — Injectivity (different chainId)
  Given: callback_a with chainId=1, callback_b with chainId=42161
  Then:  callbackId(a) != callbackId(b)

F3.5 — Register + lookup round-trip
  Given: registerCallback(CallbackEndpoint(...))
  When:  lookupCallback(callbackId(endpoint))
  Then:  returns the CallbackEndpoint struct

F3.6 — Idempotent registration
  Given: registerCallback(same endpoint) called twice
  Then:  no revert, count unchanged
```

**Depends on:** Independent of F1/F2

---

### F4 — Immediate Bind (funding-aware)

**What we're proving:** `bind(originId, callbackId)` creates an Active binding with quote-then-fund payment flow. Reverts if insolvent before funding.

**Test scenarios:**

```
F4.1 — Successful immediate bind
  Given: registered origin O₁, registered callback C₁, sufficient contract balance
  When:  bind(O₁, C₁) with inline payment
  Then:  binding created with state=Active
  Then:  subscription activated for O₁
  Then:  binding is discoverable by bindingId

F4.2 — Revert on insufficient funds (quote-then-fund)
  Given: registered origin O₁, registered callback C₁, zero balance
  When:  bind(O₁, C₁)
  Then:  reverts BEFORE sending any ETH to SystemContract
  Then:  no ETH lost

F4.3 — Revert on unregistered origin
  Given: unregistered originId, registered callback C₁
  When:  bind(unregisteredOriginId, C₁)
  Then:  reverts

F4.4 — Revert on unregistered callback
  Given: registered origin O₁, unregistered callbackId
  When:  bind(O₁, unregisteredCallbackId)
  Then:  reverts

F4.5 — Duplicate bind is idempotent
  Given: existing active binding (O₁, C₁)
  When:  bind(O₁, C₁) again
  Then:  no revert, no duplicate binding created
```

**Depends on:** F1, F3

---

### F5 — Scheduled Bind (PendingFunding)

**What we're proving:** `scheduleBind(originId, callbackId)` creates a binding in PendingFunding state without requiring funds.

**Test scenarios:**

```
F5.1 — Successful scheduled bind
  Given: registered origin O₁, registered callback C₁, zero balance
  When:  scheduleBind(O₁, C₁)
  Then:  binding created with state=PendingFunding
  Then:  NO subscription activated (no debt incurred)

F5.2 — PendingFunding binding not in dispatch results
  Given: binding (O₁, C₁) in PendingFunding state
  When:  dispatch(O₁)
  Then:  C₁ NOT in results (not active)

F5.3 — Manual resume activates scheduled bind
  Given: binding (O₁, C₁) in PendingFunding, contract now funded
  When:  resume(bindingId)
  Then:  state transitions to Active
  Then:  subscription activated
```

**Depends on:** F1, F3, F4 (bind mechanics)

---

### F6 — Auto-Activate via Self-Sync

**What we're proving:** When a contract receives funding, a self-sync event triggers ReactVM to activate PendingFunding bindings automatically.

**Test scenarios:**

```
F6.1 — Funding triggers self-sync event
  Given: contract with PendingFunding binding (O₁, C₁)
  When:  ETH sent to contract via receive()
  Then:  Funded(address, uint256) event emitted
  Then:  self-subscription picks up Funded event

F6.2 — ReactVM processes Funded event and activates bindings
  Given: ReactVM receives LogRecord for Funded event
  When:  processLog routes to auto-activate handler
  Then:  PendingFunding bindings with sufficient funding → state=Active
  Then:  subscriptions activated for newly active bindings

F6.3 — Partial funding does not activate
  Given: binding requires 0.1 ETH, contract receives 0.05 ETH
  When:  Funded event processed
  Then:  binding remains PendingFunding

F6.4 — Multiple PendingFunding bindings prioritized
  Given: bindings B₁, B₂, B₃ all PendingFunding
  When:  sufficient funding for B₁ and B₂ but not B₃
  Then:  B₁, B₂ activated (FIFO order), B₃ remains PendingFunding
```

**Depends on:** F2 (self-sync), F5 (scheduled bind)

---

### F7 — Fan-Out Dispatch

**What we're proving:** A single origin event dispatches to multiple bound callbacks. The doubly-linked list preserves FIFO ordering.

**Test scenarios:**

```
F7.1 — Single callback dispatch
  Given: active binding (O₁, C₁)
  When:  dispatch(O₁)
  Then:  returns [C₁]

F7.2 — Multi-callback fan-out
  Given: active bindings (O₁, C₁), (O₁, C₂), (O₁, C₃)
  When:  dispatch(O₁)
  Then:  returns [C₁, C₂, C₃] in FIFO registration order

F7.3 — Isolated origins
  Given: active bindings (O₁, C₁), (O₂, C₂)
  When:  dispatch(O₁)
  Then:  returns [C₁] only (O₂'s callbacks not included)

F7.4 — Empty dispatch
  Given: registered origin O₁ with no bindings
  When:  dispatch(O₁)
  Then:  returns empty array
```

**Depends on:** F4 (bind), doubly-linked list container

---

### F8 — Per-Binding Pause

**What we're proving:** `pause(bindingId)` excludes a specific binding from dispatch without unsubscribing the origin.

**Test scenarios:**

```
F8.1 — Pause excludes from dispatch
  Given: active bindings (O₁, C₁), (O₁, C₂)
  When:  pause(binding for C₁)
  When:  dispatch(O₁)
  Then:  returns [C₂] only

F8.2 — Resume re-includes in dispatch
  Given: paused binding (O₁, C₁)
  When:  resume(binding for C₁)
  When:  dispatch(O₁)
  Then:  returns [C₁, C₂]

F8.3 — Pause does not affect origin subscription
  Given: active bindings (O₁, C₁), (O₁, C₂)
  When:  pause(binding for C₁)
  Then:  origin O₁ subscription still active (C₂ still needs it)

F8.4 — Pause all callbacks does not unsubscribe origin
  Given: active bindings (O₁, C₁)
  When:  pause(binding for C₁)
  Then:  origin O₁ subscription still active (origin lifecycle independent)
  When:  dispatch(O₁)
  Then:  returns empty array
```

**Depends on:** F7 (fan-out dispatch)

---

### F9 — Unbind (callback removal, origin persists)

**What we're proving:** `unbind(bindingId)` removes the callback routing but the origin subscription persists (independent lifecycle per Q8 answer B).

**Test scenarios:**

```
F9.1 — Unbind removes from dispatch
  Given: active bindings (O₁, C₁), (O₁, C₂)
  When:  unbind(binding for C₁)
  When:  dispatch(O₁)
  Then:  returns [C₂] only

F9.2 — Origin persists after last unbind
  Given: active binding (O₁, C₁) — only binding for O₁
  When:  unbind(binding for C₁)
  Then:  origin O₁ still registered
  Then:  origin O₁ subscription still active
  When:  lookupOrigin(O₁)
  Then:  returns the OriginEndpoint struct

F9.3 — Re-bind after unbind
  Given: unbound (O₁, C₁)
  When:  bind(O₁, C₁) again
  Then:  new binding created, Active state
  When:  dispatch(O₁)
  Then:  returns [C₁]

F9.4 — Unbind non-existent binding reverts
  Given: no binding for (O₁, C₃)
  When:  unbind(fakeBindingId)
  Then:  reverts
```

**Depends on:** F7 (fan-out dispatch)

---

### F10 — Quote-Then-Fund Safety

**What we're proving:** The quote-then-fund pattern prevents ETH loss on validation failure. All checks happen before any funds are sent to SystemContract.

**Test scenarios:**

```
F10.1 — quoteBind returns accurate cost
  Given: registered origin O₁ (not yet subscribed)
  When:  quoteBind(O₁, C₁)
  Then:  returns estimated subscription cost

F10.2 — quoteBind for already-subscribed origin returns 0
  Given: origin O₁ already subscribed (via prior bind)
  When:  quoteBind(O₁, C₂)
  Then:  returns 0 (no new subscription needed, origin independent)

F10.3 — Validation failure before funding
  Given: unregistered originId, contract has 1 ETH balance
  When:  bind(unregisteredOriginId, C₁)
  Then:  reverts
  Then:  contract balance unchanged (no ETH sent to SystemContract)

F10.4 — Insufficient balance detected before funding
  Given: registered origin O₁, contract has 0 balance
  When:  bind(O₁, C₁)
  Then:  reverts with insufficient funds
  Then:  no ETH transferred anywhere
```

**Depends on:** F4 (bind mechanics)

---

## Flow Dependency Graph

```
F1 (Origin Identity) ──────┬──→ F2 (Self-Sync Detection) ──→ F6 (Auto-Activate)
                            │                                      ↑
                            ├──→ F4 (Immediate Bind) ──→ F7 (Fan-Out) ──→ F8 (Pause)
                            │         ↑                              └──→ F9 (Unbind)
F3 (Callback Identity) ────┘         │
                                      └──→ F5 (Scheduled Bind) ──→ F6
                                      └──→ F10 (Quote-Then-Fund)
```

## Implementation Order

1. **F1** — Origin Identity (foundation, zero dependencies)
2. **F3** — Callback Identity (independent, parallel with F1)
3. **F4** — Immediate Bind (needs F1 + F3)
4. **F10** — Quote-Then-Fund Safety (needs F4)
5. **F7** — Fan-Out Dispatch (needs F4 + doubly-linked list)
6. **F8** — Per-Binding Pause (needs F7)
7. **F9** — Unbind (needs F7)
8. **F5** — Scheduled Bind (needs F4)
9. **F2** — Self-Sync Detection (needs F1 + SubscriptionLib)
10. **F6** — Auto-Activate (needs F2 + F5)
