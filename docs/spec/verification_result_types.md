# Verification Result Types — Backend Capability & Execution-Availability Model

**Date:** 2026-08-11
**Phase:** P2 (backend capability layer)
**ADR refs:** DECISION-0612..DECISION-0618
**Related:** [C13 — Backend Activation / Provenance](cfg_contract_specification.md)

---

## Purpose

This document is the single source of truth for the **verification verdict/result types** (P1) and the **backend capability & execution-availability model** (P2/P3). It defines what each backend *can represent* (capability) independently from what it *can execute* (availability).

---

## Backend Enum

```nim
Backend* = enum
  bkChc  ## transition-system CHC encoding (VerificationModel → HORN script, Spacer)
  bkBmc  ## depth-bounded unrolling; needs a resolved static loop bound
```

- **bkChc** — the primary execution backend; has a wired execution path (`availableToRun = true`).
- **bkBmc** — capability-registered but **has no BMC executor wired today**. It is a future capability axis. Routing to it would be theater (§0.9) unless an executor is present.

---

## BackendCapability Shape

```nim
BackendCapability* = object
  backend*: Backend
  theories*: set[TheoryKind]
  controls*: set[ControlKind]
  contracts*: set[ContractKind]
  availableToRun*: bool
```

| Field | Meaning |
|-------|---------|
| `backend` | The backend identifier |
| `theories` | Theory kinds the backend can represent |
| `controls` | Control-flow constructs the backend can encode |
| `contracts` | Contract kinds the backend can express |
| `availableToRun` | Whether a wired execution path exists today |

---

## canEncode — Representability Predicate

`canEncode(profile, capability)` returns `true` iff the obligation's required features are a **subset** of the backend's capabilities:

```nim
profile.theories <= capability.theories and
(profile.control in capability.controls) and
profile.contracts <= capability.contracts
```

This is a **sound-representation** question (expressibility), NOT a **provability** question (whether the solver can discharge it).

---

## Capability Table

| Backend | Theories | Controls | Contracts | availableToRun |
|---------|----------|----------|-----------|----------------|
| **bkChc** | {thBitVec, thArray} | {ctTransitionSys, ctBoundedLoop} | {ckPostcondition, ckInvariant} | **true** |
| **bkBmc** | {thBitVec, thArray} | {ctBoundedLoop} | {ckPostcondition} | **false** |

---

## Core Invariant

> **Capability(R) ⊭ Executable(R).** Only backends with an execution path (`availableToRun = true`) may be routing targets. Today, `isRunnable` returns `true` for `bkChc` only (CHC/Spacer via `runIrPipeline`). `bkBmc` is capability-registered but void of an executor — routing to it would be theater (§0.9).

This separation ensures that a backend being *representable* (it can encode the obligation's semantics) is never conflated with it being *runnable* (it has a wired execution path). The `isRunnable` predicate (DECISION-0618) resolves routing targets through a single source of truth (`capabilitiesOf`).

---

## C13 Reference (Backend Activation / Provenance)

See [C13 in `cfg_contract_specification.md`](cfg_contract_specification.md#c13--backend-activation--provenance) for the normative contract on `actualBackend` provenance. The capability≠executable principle complements C13: C13 governs *which backend actually ran* (provenance), while this spec governs *which backends are eligible to run* (capability vs. availability).

---

## Documented Decisions

| ID | Subject |
|----|---------|
| DECISION-0612 | Per-backend capability table — the SSOT that maps a backend to its representable feature set |
| DECISION-0613 | Derive a VerificationModel's required-representation profile from its semantic fields |
| DECISION-0614 | `canEncode(profile, capability)` — sound-representation predicate (required ⊆ capability) |
| DECISION-0615 | Convenience overload — `canEncode(profile, backend)` resolves the capability table |
| DECISION-0616 | `canEncode(model, backend)` — derives the model profile then consults the capability table |
| DECISION-0617 | `compatibilityReason` — deterministic human-readable explanation of encodability |
| DECISION-0618 | `isRunnable` — execution-availability predicate; routes routing targets through `capabilitiesOf` |

---

## Quirks

- **bkBmc has no executor**: The BMC backend is registered in the capability table with full representational power for bounded-loop obligations, but no BMC executor is wired. This is intentional — BMC execution is a future capability axis.
- **Lean is not a Backend member**: Lean is reserved for a later capability axis once a Lean encoder is wired. It is intentionally absent from the `Backend` enum.
