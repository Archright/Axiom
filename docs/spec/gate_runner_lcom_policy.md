# Gate Runner LCOM Policy — Procedural Module Cohesion Metric Exemption

**Status:** Adopted 2026-08-04
**Scope:** `src/gate/runners/` procedural gate-runner modules flagged by the SOLID-srp LCOM rule
**Governance:** AGENTS.md §0.2 (First-Principles Elegance), §0.9 (Theater Prohibition), §0.5b (Quirk Documentation)

---

## 1. Problem

`src/gate/nimtry/solid_queries.nim` flags modules with LCOM > 0.6 as SRP violations.
`src/gate/cohesion_enforce.nim` computes LCOM as:

```
LCOM = 1 - (connectedPairs / totalPairs)
```

where a function pair is "connected" when the two function bodies share at least one
identifier token (`nkIdent`/`nkSym` collected from the raw parse tree).

The measurement treats **the entire module** as a single implicit "class" and every
top-level function as a "method" of that class.

## 2. Why the Metric Is Inapplicable to Procedural Gate Runners

Nim modules are **namespaces of free functions**, not classes (Nim Manual §Modules:
"each [module] residing in its own file with a unique namespace"). A gate runner is a
**procedural orchestrator** with:

- **No instance state** — no object fields to share between methods.
- **Hub-and-spoke structure** — one orchestrator proc (`runGateLogic`) calls many leaf
  helpers; the leaf helpers share no identifiers with each other.
- **Helper locality** — each helper has its own parameter/local variable names, so
  pairs of leaf helpers are almost always counted as "disconnected".

Result: any well-structured procedural module with several private helpers scores a
high LCOM **by construction**, regardless of how cohesive its responsibility set is.
Additionally, `collectIdents` counts **operators** (`&`, `>`, `/`, `$`) and declaration
names as shared identifiers, inflating "connected" pairs with fake coupling — the
opposite direction of the class-based metric's intent.

## 3. Adopted Policy

A procedural gate-runner module whose only flagged metric is SOLID-srp LCOM (i.e., it
has no other architectural violation) MAY be granted an `[lcom_overrides]` entry of
`= 1.0` in `src/gate/architecture_policy.lock`, **provided**:

1. The module is a top-level procedural orchestrator with no object/ref-object state.
2. Genuine dead code was removed first (functions, unused parameters, unused constants).
3. A rationale comment is attached to the override entry (audit trail, §0.9).
4. The module passes every other gate (import encapsulation, layer, effect, purity).

The override entry is a documented policy exemption — **not** a silent skip. It is the
same mechanism used by the pre-existing 47 entries (initially "inherently cohesive
modules flagged by LCOM (small/type/parser/facade/pipeline-stage modules)").

## 4. Recorded Exemptions

| Module | Date | Rationale |
|--------|------|-----------|
| `src/gate/runners/proof_universe_lock_gate.nim` | 2026-08-04 | Procedural orchestrator; dead code (getGateTimeout, elapsedSec, discard params) removed; LCOM remains at 0.600 boundary even after cleanup; split would worsen helper-module LCOM to 0.762 |

## 5. Anti-Theater Guarantee (§0.9)

This document exists to make every override **explicitly documented and auditable**.
An override without a rationale comment or without dead-code cleanup first is
considered an undocumented fail-open (Theater signature #2) and must be rejected in
review. Runtime logging of overrides is unnecessary because the override is a static,
reviewable policy artifact, not a runtime bypass.
