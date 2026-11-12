# Continual Revalidation Governance (Post-GO)

**Status**: Active — governs post-START productization revalidation.
**Related**: AGENTS.md §0.12 (product-contract-first), `tools/readiness_evaluator.nim` (decision predicate SSOT), `config/readiness_policy.json` (parameters).

---

## 1. Purpose & Status

After Productization START = GO (STOP at A~D+E0), a **continual revalidation loop** keeps the product contract alive. START is a **point-in-time judgment**, not a permanent certificate. The loop runs baseline revalidation on every relevant trigger and applies trigger-based governance reopen when evidence, provenance, or contract alignment breaks. (CI=0 cutover, 2026-09-20로 원격 워크플로 트리거는 소멸 — 트리거는 로컬 게이트/운영 판단이 담당.)

---

## 2. State Machine

```
PRE-START → START GATE PASS → PRODUCTIZATION ACTIVE
  → (Continuous Baseline Revalidation + Trigger-Based Governance Reopen)
  → PASS = CONTINUE
  → CONTRACT·EVIDENCE·PROVENANCE FAIL = BLOCKED (→ relevant START gate reopened)
  → INFRA·UNRESOLVED = revalidation needed (NOT auto-BLOCK)
```

---

## 3. Baseline Automation (Single Canonical Workflow — RETIRED 2026-09-20)

**RETIRED**: CI=0 cutover(2026-09-20)로 실행 워크플로 자체가 제거되었다 — 역대 트리거 서술은
역사 기록이다. 당시 정의:

`.github/workflows/readiness_start.yml` triggers on:

- `pull_request` → `main`
- `merge_group`

(The former `push` → `main` trigger was removed 2026-09-11 — CI de-duplication
cutover: PR checks are the authoritative merge-boundary validation, and
post-merge main-state monitoring is owned by the canonical-main
`[continuity]` step (`ax cert continuity`, tools/ci/run_landing_continuity.sh)
plus the nightly full-L2 backstop. `merge_continuity.yml`, the reusable
workflow whose cert-selection walk that step extracts, was retired
2026-09-18 — dead artifact with 0 callers. A
push:main readiness re-run duplicated the PR run byte-identically and had no
consumer.)

---

## 4. Outcome Taxonomy

Separate **ObservedState** from **DecisionOutcome**:

| ObservedState | DecisionOutcome |
|---|---|
| `OBSERVED_PASS` | `CONTINUE` |
| `OBSERVED_FAIL` | `BLOCK` or `UNRESOLVED` (depends on failureCategory) |
| `UNKNOWN` | `UNRESOLVED` |
| `NOT_RUN` | `UNRESOLVED` |

**failureCategory** values:

| Category | Outcome |
|---|---|
| `PASS` | CONTINUE |
| `CONTRACT_FAIL` | BLOCK |
| `EVIDENCE_FAIL` | BLOCK |
| `PROVENANCE_FAIL` | BLOCK |
| `INFRA_FAIL` | UNRESOLVED |
| `UNRESOLVED` | UNRESOLVED |
| `SKIPPED(NOT_EVALUATED)` | UNRESOLVED |

**Critical invariants**: `UNKNOWN ≠ FAIL`; `INFRA·UNRESOLVED ≠ BLOCK`. The readiness evaluator is the decision predicate SSOT.

---

## 5. Reopen Criteria (Human-Triggered Governance)

Automation is **only** baseline revalidation. Governance reopen is human-triggered:

| Trigger | Action |
|---|---|
| Canonical path / cert schema·identity change | readiness + `check-cert-integrity` + `check-determinism` |
| Verification semantics change | readiness + `check-cert-integrity` + `check-determinism` |
| Execution contract change | readiness + `check-cert-integrity` + `check-determinism` |
| Toolchain change | readiness + `check-cert-integrity` + `check-determinism` |
| Deterministic replay failure | START-B reopen |
| Evidence/provenance inconsistency | cert-integrity + anti-theater audit |
| Real OSS corpus anomaly | Nim-Stew External Reality Gate |

**Explicitly NOT new START blockers**: dead gates, 50-gate speed, VKD% change, dormant gate revival, performance.

---

## 6. Honesty Declarations

(a) **Trigger classification is HUMAN-GOVERNED** — no automated dependency analysis yet.
(b) ~~Push-main readiness is post-merge detection, not merge enforcement.~~
Superseded 2026-09-11: the push→main readiness trigger was removed (CI
de-duplication). Post-merge detection is now owned by the canonical-main
`[continuity]` step plus the nightly full-L2 backstop.
(`merge_continuity.yml` retired 2026-09-18 — the reusable component it called
was deleted; the cert-selection walk lives on in run_landing_continuity.sh.)
(c) **CI-generated decision records** should by default be GitHub Actions artifacts (not a Git event log); any kept `data/` readiness records are deliberately reviewed/selected.
(d) **`UNRESOLVED ≠ BLOCK`** and **`UNKNOWN ≠ FAIL`** — a CI/runner/infra error must not over-block the product.
(e) **Content-based deterministic decision identity**: `H(policyDigest + evidenceDigest + executionContractDigest + verdict + outcome)`. Parent = lineage metadata only. Serialized record may be timestamp-varying (provenance) even though canonical identity is deterministic.

---

## 7. Immutable Decision Ledger (Deferred, Optional)

**NOT built now.** Build only when GO→BLOCKED→GO history / release audit decision chain / external customer provenance is actually needed. Principles for that time: content-based `decisionId`, parent = lineage, CI decisions as artifacts first, Git is optional ratified preservation only (no event log), do not add another projection engine — keep the readiness evaluator as SSOT.

---

## 8. Nim-Stew External Reality Gate (Spec Only for Now)

Independent validation domain. Internal START → External Reality Gate → Nim-Stew.

**External-Slice conditions**: real repo ingest → actual target selection → actual verification → actual certificate → repeated run (determinism) → no false promotion.

**External critical failure** → External Gate FAIL → Productization BLOCKED → relevant START gate reopened.

**Building internal gates does NOT imply external codebases pass automatically.**
