# Decision Binding Schema Revision Proposal

**Status**: Proposed (architect decision required)
**Date**: 2026-08-06
**Author**: Phase 1 (governance) agent
**Audience**: Human architect

---

## 1. Executive Summary

`AGENTS.md` §0.10 mandates a waiver schema that does **not** match the deployed
schema. The governance change set fixes the specification document
(`docs/spec/decision_binding_framework.md`) to describe the deployed schema
truthfully, but `AGENTS.md` itself is **immutable** and was **not** modified by
this task. The precise wording amendment for `AGENTS.md` §0.10 is proposed below
so the human architect can apply it.

---

## 2. The Mismatch

| Aspect | AGENTS.md §0.10 (as written) | Deployed schema (actual) |
|--------|------------------------------|--------------------------|
| Config file | `config/decision_binding.waiver.toml` | `config/decision_binding.waiver.toml` + `config/decision_binding.waiver.json` |
| Top-level section | `[[waivers]]` | `[[grandfather]]` |
| Scope | per-`symbol` | per-`file` |
| Fields | `symbol`, `reason`, `expires`, `legacyId` | `file`, `reason`, `expires` |

Evidence of the deployed schema:

- `config/decision_binding.waiver.toml` — `[[grandfather]]` entries with
  `file` / `reason` / `expires` (header comment: "Format: [[grandfather]] with
  file, reason, expires").
- `config/decision_binding.waiver.json` — `root["grandfather"]` array of
  `{ "file", "reason", "expires" }` objects (primary runtime source).
- **Consumer** `tools/hermetic_build.nim:1761-1842` — parses `[[grandfather]]`,
  keys `file`/`reason`/`expires`; also loads `root["grandfather"]` from the JSON
  (lines 1846-1862).
- **Consumer** `tools/decision_binding_checker.nim:93-203` — `tryLoadJSON` reads
  `root["grandfather"]` with `file`/`reason`/`expires`; TOML fallback parses
  `[[grandfather]]` with the same keys.

`AGENTS.md` line 236 currently reads:

> - `waiver.toml`에 `symbol`, `reason`, `expires`, `legacyId` 기록

This is the text that must be amended.

---

## 3. Proposed Amendment For AGENTS.md §0.10

Replace the exemption-condition bullet at **AGENTS.md ~line 236** with the
following (Korean, matching the surrounding §0.10 tone):

> - `waiver.toml`/`waiver.json`에 `grandfather` 섹션에 `file`, `reason`, `expires` 기록
> - `expires` 이후에는 lint error로 전환
> - 모든 waiver 해제 후 error mode 활성화

Corresponding English normative text (for inclusion if the architect prefers a
bilingual entry):

> - Record `file`, `reason`, `expires` under the `[[grandfather]]` top-level
>   section in `config/decision_binding.waiver.toml` (and the mirrored
>   `config/decision_binding.waiver.json`), one entry per exempted source file.
>   Waivers are file-scoped, not symbol-scoped.

The architect should also update the `# LEGACY-0000` example block in §0.10
(lines ~222-232) if that marker convention is to be kept, since the deployed
linter/checker do **not** currently recognize `LEGACY-0000` markers (no matches
in `tools/hermetic_build.nim`, `tools/decision_binding_checker.nim`, or
`src/gate/runners/decision_binding_gate.nim`).

---

## 4. Verification-Layer Implication

`src/verification/batch_uap/ir_pipeline_runner.nim` exposes two public procs —
`computeVkdRequiredLimit*` and `selectProofCandidates*` — that carry **no**
`{.axiomDecision.}` pragma. Per ADR-0009 / §0.10 R1-R2, public decision-point
symbols should carry the pragma. The pragma is owned by another agent
(`ir_pipeline_runner.nim` is not in this task's ownership set), so this report
only proposes the insertion (see §5).

The insertion binds both procs to ADR-0011 (`docs/adr/0011-vkd-target-ratchet.md`)
and uses DECISION IDs consistent with the `DECISION-0010` precedent observed in
`docs/spec/decision_binding_framework.md` (DECISION-0011 / DECISION-0012).

---

## 5. Proposed Pragma Insertion (report only — do NOT apply)

For `src/verification/batch_uap/ir_pipeline_runner.nim`:

**Location A — `computeVkdRequiredLimit` decl (line ~363):**

```nim
proc computeVkdRequiredLimit*(cliLimit: int; kernelTotal: int; targetVkd: string): int {.raises: [],
     axiomDecision(id: "DECISION-0011",
                   reason: "Monotonic VKD target ratchet; kernelTotal floor guarantees full kernel scope feeds the VKD numerator",
                   adr: "docs/adr/0011-vkd-target-ratchet.md",
                   introduced: "v31").} =
```

**Location B — `selectProofCandidates` decl (line ~383):**

```nim
proc selectProofCandidates*(limit: int; kernelTotal: int; targetVkd: string): seq[ValidatedIrEntry] {.raises: [],
     axiomDecision(id: "DECISION-0012",
                   reason: "verifiableOnly+pureOnly selection so every emitted cert targets the 46-kernel scope and counts toward the VKD numerator",
                   adr: "docs/adr/0011-vkd-target-ratchet.md",
                   introduced: "v31").} =
```

> Note: the `axiomDecision` template is currently defined as a parameterless
> pragma (`src/core/trusted/axiom_pragmas_lite.nim:136`). If the named-field form
> (`id`/`reason`/`adr`/`introduced`) is required, the template must be extended
> to accept those parameters first — otherwise the named-field pragma will not
> compile. This is a follow-up for the `ir_pipeline_runner.nim` owner to confirm
> with the pragma maintainer.

---

## 6. Files Changed By This Task

- **Created** `docs/adr/0011-vkd-target-ratchet.md`
- **Extended** `tools/sync_decisions.nim` (DecisionSpec: ADR-0009/0010/0011)
- **Regenerated** `data/decisions_graph.json` (11 nodes, idempotent)
- **Fixed** `docs/spec/decision_binding_framework.md` (waiver schema §Grandfathering
  Strategy, §Schema, §Waiver Entry Fields)
- **Created** `docs/agents/decision_binding_schema_revision_proposal.md` (this file)

**Not modified**: `AGENTS.md` (immutable per §-1), `src/verification/batch_uap/ir_pipeline_runner.nim` (owned by another agent).