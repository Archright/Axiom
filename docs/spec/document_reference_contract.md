# Document Reference Resolution Policy

> **Status**: NORMATIVE (ratified 2026-08-23). Defines how file-path references
> inside repository documentation are resolved — specifically which references
> may legitimately be **absent in a fresh clone** and under what contract. This is a
> **reference-resolution policy** for documentation links, NOT an artifact
> taxonomy and NOT a second SSOT for artifact meaning.
> **SSOT anchors**: artifact taxonomy & persistence — `docs/spec/repository_state_model.md`;
> policy manifest consumed by the validator — `tools/ci/doc_reference_policy.json`;
> validator implementation — `tools/ci/doc_path_validator.nim`;
> archived/skipped doc scopes — `tools/ci/archived_docs.json`.
> **Related**: `docs/spec/repository_state_model.md`, `docs/spec/audit_tooling_contract.md`,
> `docs/spec/change_governance_contract.md`.

---

## 1. Purpose and Domain

`doc_path_validator` historically resolved every documentation file reference by
checking **only file existence** — a binary coarse existence test. That confuses
two distinct facts:

- **the reference is valid** (points at the right logical artifact), and
- **the referenced file must exist in a fresh clone** (its persistence state).

Some references legitimately point at artifacts that need not be present in a
fresh clone: retrospective historical records (superseded audit results) and
generated reports (regenerated on demand). Treating those as hard existence
failures produces false gate failures on a clean checkout.

This contract introduces a **reference resolution policy** — a small, explicit,
fail-closed exception mechanism — so the validator can distinguish "normative
reference that must resolve" from "non-canonical reference whose absence is a
normal state change."

### 1.1 Not a taxonomy — axis separation (INVARIANT-DRP-1)

Artifact **class** (CANONICAL / DERIVED / EPHEMERAL / EXTERNAL) and **persistence**
(TRACKED / IGNORED / REGENERATED) are defined once in `repository_state_model.md`
and are NOT redefined here. This document adds a **third, independent axis**:
the *document-reference resolution policy* describing how a documentation link
to a path is resolved.

```
INVARIANT-DRP-1 (axis separation): reference resolution policy (§2) is NOT
   the same axis as artifact class or persistence. Mapping them 1:1 is forbidden.
   - a HISTORICAL_ALLOWED document is typically DERIVED + REGENERATED/IGNORED, but
     the reference policy governs link resolution, not the artifact's state role;
   - a MUST_EXIST reference may target a CANONICAL+TRACKED spec OR any artifact
     that must resolve in a fresh clone;
   - no reference policy is inferred from a path's class — both must be declared.
```

The contract is deliberately **not** a general semantic/metadata schema for
documentation references. It declares only the resolution policy and (for
generated targets) the regeneration command identity. Everything else — artifact
meaning, class, persistence — remains in `repository_state_model.md`.

---

## 2. Reference Resolution Policies

Every file-path reference in active documentation receives exactly one policy.
**Unclassified references are MUST_EXIST (fail-closed).**

| Policy | Resolution contract | Absence in fresh clone |
|---|---|---|
| `MUST_EXIST` (default) | Reference must resolve to an existing file | **FAIL** |
| `HISTORICAL_ALLOWED` | Reference is a provenance pointer to a retrospective/ historical record; does NOT assert current existence | **allowed** (absence is not a finding; validity of the reference itself is not asserted) |
| `GENERATED_ALLOWED` | Reference points at a deterministically regenerable artifact; absence allowed **only when** a valid canonical reproducer is declared | **allowed iff** valid `reproducerTarget` present and target identity resolves |
| `EXTERNAL_ALLOWED` | Reference is local/CI-only, never durable repository truth | **allowed** (never treated as canonical) |

### 2.1 MUST_EXIST (INVARIANT-DRP-2)

```
INVARIANT-DRP-2 (fail-closed default): an unclassified reference is MUST_EXIST.
   A missing MUST_EXIST target is an error/warning and fails the gate, exactly as
   before this contract. Classification is a REVOCABLE CARVE-OUT, not a default
   relaxation: a reference is only weakened by an explicit, intentional,
   reviewed declaration in the policy manifest.
```

This is what keeps the contract an explicit-responsibility declaration instead
of a silent always-pass escape. Forgetting to classify a historical/generated
reference therefore stays a FAIL, not a silent pass.

### 2.2 HISTORICAL_ALLOWED (INVARIANT-DRP-3)

```
INVARIANT-DRP-3 (historical = provenance reference): a HISTORICAL_ALLOWED
   reference asserts only that some past event/decision was recorded at the
   referenced path. It does NOT assert current existence and does NOT assert the
   reference still resolves. Absence is a normal, expected state — e.g. a
   superseded audit result that has since been gitignored or removed.
```

Because absence is permitted, a HISTORICAL_ALLOWED reference gives **no**
guarantee that the referenced artifact is well-formed or currently valid. It is a
retrospective pointer, documented intent — not a resolvable dependency. The
validator therefore skips it without comment when absent: this is documented,
intentional behavior, not a silent fallback.

### 2.3 GENERATED_ALLOWED (INVARIANT-DRP-4)

```
INVARIANT-DRP-4 (generated requires a real reproducer): a GENERATED_ALLOWED
   reference may be absent ONLY when the manifest declares a valid
   `reproducerTarget` — a canonical `make <target>` identity (a Makefile target
   that deterministically produces the artifact) — AND that target identity
   actually exists (make -n probe = EXISTS). GENERATED_ALLOWED with no declared
   reproducer (rrGeneratedNoReproducer), an ABSENT reproducer, or a
   PROBE-ERROR reproducer is still a FAIL — never promoted to allowed.
```

`reproducerTarget` is **not a free-form string**; it is a canonical command/build
target identity whose existence the validator verifies. This prevents
`class=generated` from becoming a blanket "anything may be absent" escape: the
declarer must name a concrete, existing regeneration path. The intended
invariant:

```
INVARIANT-DRP-4a (reproducer is concrete): GENERATED_ALLOWED
   ⇒ ∃ `reproducerTarget` ∧ validator-confirmed target identity exists.
   "valid canonical reproducer declared" ≠ "some producer string is present".
```

**Responsibility bound (INVARIANT-DRP-8)**: the validator's contract ends at
confirming that the *declared reproducer* is a canonical target identity that
`make -n` recognizes as existing. It does **not** execute the reproducer, does
not assert the regenerated artifact's content is valid, and does not verify that
the reproducer actually produces the referenced path. Those are the domain of
Artifact Reproduction / regeneration tests, a separate scope. The validator's
absence-allowance is therefore: *a concrete, existing regeneration path exists*,
not *the artifact is provably regenerable*. Failing open on this boundary is
forbidden; the probe is tri-state (EXISTS / ABSENT / PROBE-ERROR) and only
EXISTS permits absence (INVARIANT-DRP-7).

### 2.4 EXTERNAL_ALLOWED (INVARIANT-DRP-5)

```
INVARIANT-DRP-5 (external never durable truth): an EXTERNAL_ALLOWED reference
   is local/CI tooling state, never a canonical measurement or decision artifact.
   It must never be promoted to repository truth and never feed a product claim.
```

---

## 3. Policy Manifest (`doc_reference_policy.json`)

The manifest is a **reference-resolution exception policy** — the closed set of
carve-outs declared intentionally. It has three hard limits:

```
INVARIANT-DRP-6 (manifest is an exception policy, not an SSOT): the manifest
   declares resolution policy only. It MUST NOT define artifact taxonomy (see
   repository_state_model.md), MUST NOT declare new semantic classes, MUST NOT
   store per-reference metadata beyond {policy, [reproducerTarget], [comment]}.
   `comment` is an inert documentation field; a semantic field (e.g. `authority`)
   is rejected as malformed because it could never influence resolution.
   Extending it into a semantic/metadata SSOT is forbidden.
```

Schema, per referenced path:

```json
{
  "docs/audit/report_counts.json": {
    "policy": "GENERATED_ALLOWED",
    "reproducerTarget": "make audit-dir-doc",
    "comment": "Regenerated debt report; absence allowed via canonical reproducer"
  },
  "docs/audit/productization_readiness_2026-08-17.md": {
    "policy": "HISTORICAL_ALLOWED"
  }
}
```

- Keys are exact relative paths (as they appear in references).
- `policy` ∈ { `MUST_EXIST`, `HISTORICAL_ALLOWED`, `GENERATED_ALLOWED`, `EXTERNAL_ALLOWED` }.
- `reproducerTarget` is REQUIRED for `GENERATED_ALLOWED`, must be an existing
  canonical `make <target>` identity, and is otherwise forbidden.
- `comment` is an inert documentation field; it is ignored by resolution.
- A **malformed manifest** (invalid JSON, unknown policy, or an entry carrying
  any key other than `policy`/`reproducerTarget`/`comment` — notably a semantic
  field such as `authority`) is a gate **FAIL**, not a silent ignore.
- GENERATED_ALLOWED **without a declared `reproducerTarget` is NOT malformed**:
  it is a precise resolvable decision — `rrGeneratedNoReproducer` — that FAILS
  at resolve time (INVARIANT-DRP-4). This keeps the loader from misclassifying
  an intending-but-incomplete declaration as a parse error while still never
  promoting it to allowed.

---

## 4. Validator Contract

`doc_path_validator.nim` resolves each reference in an active doc as follows:

```
resolve(path):
  if path is whitelisted             → skip (existing whitelist)
  if path is in archived/skipped doc → skip (existing DEBT#403, whole-doc)
  policy = referencePolicy(path)     # manifest lookup; default MUST_EXIST
  if file exists                     → PASS (file presence satisfied)
  case policy:
    MUST_EXIST         → FAIL (error/warning, existing behavior)
    HISTORICAL_ALLOWED → PASS-absent (not a finding; INVARIANT-DRP-3)
    GENERATED_ALLOWED  → ...
        if reproducerTarget is empty            → FAIL (rrGeneratedNoReproducer;
                                                       INVARIANT-DRP-4)
        else probe the canonical `make <target>` identity (tri-state):
            EXISTS      → PASS-absent (INVARIANT-DRP-4/4a)
            ABSENT      → FAIL (rrTargetAbsent)
            PROBE-ERROR → FAIL (rrProbeError; fail-closed, never promoted)
    EXTERNAL_ALLOWED   → PASS-absent (INVARIANT-DRP-5)
  malformed manifest   → FAIL
```

```
INVARIANT-DRP-7 (no silent weaken): the only ways a missing target avoids FAIL
   are (a) an explicit HISTORICAL_ALLOWED declaration, or (b) an explicit
   GENERATED_ALLOWED declaration with a CONFIRMED-EXISTING canonical reproducer
   (make -n probe = EXISTS), or (c) an EXTERNAL_ALLOWED declaration. No other
   path. A malformed manifest, an unknown policy, an empty reproducer on
   GENERATED_ALLOWED, an ABSENT/PROBE-ERROR reproducer, or any metadata
   inconsistency is FAIL. `comment` is inert and never influences this.
```

---

## 5. Non-Goals

| NOT | Because |
|---|---|
| an artifact taxonomy | class/persistence lives once in `repository_state_model.md` |
| a semantic/metadata SSOT for references | that would recreate the exact split-brain this contract removes (§1, INVARIANT-DRP-6) |
| a promise that absent references are still valid | HISTORICAL/EXTERNAL absence asserts nothing about current validity (INVARIANT-DRP-3) |
| a permissive everything-passes mode | fail-closed default + INVARIANT-DRP-7 keep classification an explicit responsibility |
| a change to any normative spec's meaning | classification marks intent; it does not rewrite the referenced document |

---

## 6. Ratified Amendment Log

| Amendment | Section | Ratified | Summary |
|---|---|---|---|
| (initial ratification) | whole | 2026-08-23 | Introduce reference resolution policy as a third axis; classify the 4 fresh-clone-absent references (2 HISTORICAL_ALLOWED, 2 GENERATED_ALLOWED); keep MUST_EXIST fail-closed default. |
| authority→comment removal | §3 | 2026-08-23 | Manifest per-entry surface narrowed to `{policy, [reproducerTarget], [comment]}`; `authority` (a semantic field) is now REJECTED as malformed. `reproducerTarget` changed from a free-form build identity to an exact canonical `make <target>`; GENERATED_ALLOWED without it is `rrGeneratedNoReproducer` (resolve-time FAIL), not malformed. Absence-resolution now uses a native `make -n` tri-state probe (EXISTS/ABSENT/PROBE-ERROR) with responsibility bound (INVARIANT-DRP-8): confirming the reproducer target exists, not provable regeneration. |
| build_env registration | §2.3 | 2026-08-23 | Register `src/generated/build_env.nim` as GENERATED_ALLOWED with `reproducerTarget: make check-decision-binding` — a legitimate untracked+gitignored hermetic-build artifact (blanket-purity design) whose two spec references would otherwise resolve as MUST_EXIST-absent in a fresh pre-build checkout. Same contract, one more evidence entry. |
