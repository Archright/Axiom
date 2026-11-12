# ADR-0011: VKD Target Ratchet

## Status
Accepted (2026-08-06, human architect)

## Context
The CI baseline gate (ADR-0010) regressed: a VKD target that should have been met
was silently under-selected, so the required verification depth was not reached.
Root-cause investigation (session `ses_0346`) traced the failure to the candidate
selection logic in `src/verification/batch_uap/ir_pipeline_runner.nim`:

- `computeVkdRequiredLimit` could return a limit **below** the kernel scope size,
  truncating kernel symbols that are interleaved in registry order and starving the
  VKD numerator (`countKernelVerified`).
- `selectProofCandidates` did **not** guarantee that every emitted certificate
  targets a kernel-scope symbol, so emitted certs could fall outside the VKD
  numerator — inflating apparent coverage while the true VKD stayed flat.
- Fix delivered in PR #3.

## Decision
Adopt a **monotonic VKD target ratchet** over the candidate limit.

### The Full Formula
```
result = max(cliLimit, ceil(kernelTotal × targetVkd) + 1, kernelTotal)
```
- `cliLimit` — the explicit caller-requested limit (never silently lowered).
- `ceil(kernelTotal × targetVkd) + 1` — the count required to reach the target VKD
  fraction of the kernel scope.
- `kernelTotal` — the **floor** that guarantees the FULL kernel scope (46 kernel
  symbols) is always considered. Kernel symbols are interleaved in registry order,
  so a limit below `kernelTotal` truncates them and starves the VKD numerator.
  This feeds the VKD numerator the way the kernel scope is defined.

### Fail-Closed Branches
Reference: `src/verification/batch_uap/ir_pipeline_runner.nim:363-381`. Any
degenerate input falls back to `max(cliLimit, kernelTotal)` — never below the
explicit CLI request:

- Empty `targetVkd` string → `max(cliLimit, kernelTotal)`.
- `parseFloat` raises `ValueError` (unparseable input) → `max(cliLimit, kernelTotal)`.
- `target <= 0.0` → `max(cliLimit, kernelTotal)`.

### Certificate-to-VKD Integrity
`selectProofCandidates` enforces `verifiableOnly=true` **and** `pureOnly=true`:
- BMV-skippable string/float entries are excluded (`verifiableOnly`).
- Non-`Pure` effect entries are excluded (`pureOnly`).

This mirrors the kernel-scope filter in `collectKernelSymbols`
(`effectKind == Pure`) so every emitted certificate targets a symbol in the
46-kernel scope and therefore counts toward the VKD numerator by construction.

### Monotonic Ratchet Policy
The VKD baseline may **only move up**. A baseline update is guarded so a proposed
baseline that would regress VKD is rejected. The ratchet never lowers the required
verification depth; it only ever raises or holds it.

## Consequences
- Full kernel scope is always considered for VKD, eliminating interleaved-truncation
  starvation.
- Fail-closed behavior guarantees no silent under-selection below the CLI request.
- Every emitted cert counts toward VKD, preventing apparent-coverage theater (§0.9).
- Baseline updates cannot regress VKD (monotonic).

## References
- Session `ses_0346` root-cause chain.
- PR #3.
- `src/verification/batch_uap/ir_pipeline_runner.nim:363-391`.
- ADR-0009 (Decision Binding Framework) — pragma binding for this decision.
- ADR-0010 (CI Baseline Gate & Ephemeral Proof Pipeline).