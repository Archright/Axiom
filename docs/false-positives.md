# False Positive Registry

> SSOT for agent investigation false positives. Prevents deterministic re-investigation waste across stateless agent sessions.
> Governed by GUARDIAN.md §17 — False Positive Recording Mandate (see `docs/agents/core_rules.md` §17).

**Purpose**: Every agent-driven investigation (audits, tech-debt scans, architecture checks) inevitably produces false positives — items that appear to be violations but are confirmed as correct upon deeper analysis. Without a deterministic recording mechanism, each new agent session re-investigates the same findings, wasting resources and eroding trust in automated analysis. This file is the SSOT that breaks that cycle.

**Format** (per `docs/agents/core_rules.md` §17):

```markdown
## FP-NNN: <descriptive title>

- **File**: `<path>:<line>`
- **What was flagged**: <initial agent finding>
- **Investigation result**: <definitive conclusion after deep analysis>
- **Verdict**: <NO ACTION NEEDED | DOCUMENTATION GAP | ACCEPTABLE DESIGN>
- **Date**: YYYY-MM-DD
```

---

## FP-001: context7_evidence_gate.nim — NOT Python

- **File**: `scripts/gates/context7_evidence_gate.nim`
- **What was flagged**: The `file` command misidentifies it as "Python script, Unicode text"
- **Investigation result**: It is genuine Nim source code. Uses `import std/[json, strutils, os, osproc, times]` and Nim constructs throughout. The `file` command's magic byte classifier is unreliable for Nim files that start with `#` comments.
- **Verdict**: NO ACTION NEEDED
- **Date**: 2026-05-05

---

## FP-002: submit_proof.nim "duplicate imports" — Code generation, not a bug

- **File**: `src/cli/commands/submit_proof.nim:1-4 vs 56-62`
- **What was flagged**: Apparent duplicate import blocks
- **Investigation result**: Lines 56-62 are inside a multi-line string template (`createProofSubmissionScript`) that generates Nim source code, targeting a different scope. Not actual duplicate imports.
- **Verdict**: NO ACTION NEEDED
- **Date**: 2026-05-05

---

## FP-003: echo in mcp/server.nim — MCP protocol transport

- **File**: `src/mcp/server.nim:163`
- **What was flagged**: `echo` in production code
- **Investigation result**: MCP server uses stdout as the MCP transport channel per MCP spec. The `echo` is intentional protocol output, not debug logging.
- **Verdict**: DOCUMENTATION GAP — add comment noting stdout is the MCP transport channel
- **Date**: 2026-05-05

---

## FP-004: orchestrator not missing from .physically_impure_modules — Already present

- **File**: `src/core/.physically_impure_modules:10`
- **What was flagged**: `orchestrator.nim` missing from impure list
- **Investigation result**: `orchestrator` is already listed at line 10. Agent search was a false alarm.
- **Verdict**: NO ACTION NEEDED
- **Date**: 2026-05-05

---

## FP-005: report.nim/report_cli.nim overlap — Intentional SRP separation

- **Files**: `src/cli/report.nim`, `src/cli/report_cli.nim`
- **What was flagged**: Overlapping responsibility between rendering and orchestration
- **Investigation result**: `report.nim` = pure rendering (all `func` with `noSideEffect`). `report_cli.nim` = CLI orchestration + I/O. Clean SRP separation.
- **Verdict**: ACCEPTABLE DESIGN
- **Date**: 2026-05-05

---

## FP-006: submit.nim/submit_proof.nim duplication — Different commands, different types

- **Files**: `src/cli/commands/submit.nim`, `src/cli/commands/submit_proof.nim`
- **What was flagged**: Substantially overlapping proof submission logic
- **Investigation result**: Two different CLI commands with different argument schemas (`AxSubmitCliResult` vs `SubmitProofCliResult`) and different type signatures. Not duplicated logic.
- **Verdict**: ACCEPTABLE DESIGN
- **Date**: 2026-05-05

---

## FP-007: CLI command composition root ISP/coupling warnings — Application layer orchestration

- **Files**: `src/cli/commands/*.nim`, `src/cli/*_cli.nim`
- **What was flagged**: CLI command entrypoints using a small subset of multiple provider modules can trigger ISP low-usage warnings or dependency-budget blocking.
- **Investigation result**: CLI command modules are application composition roots. Their role is to connect parsing, filesystem effects, certificate services, and report rendering while keeping `src/core` and `src/verification` ownership strict. ISP/coupling checks are domain-logic constraints; applying them unchanged to command composition roots treats necessary orchestration as low cohesion.
- **Verdict**: ACCEPTABLE DESIGN for CLI composition roots only; core and verification modules remain subject to the full gate.
- **Date**: 2026-05-11

---

## FP-008: extractZ3ProofTrace "duplication" — Different algorithms

- **Files**: `src/core/smt_to_lean_bridge.nim:774`, `src/core/provider_interface.nim:74`
- **What was flagged**: Two functions named `extractZ3ProofTrace` in different modules flagged as DRY violation during quality-gate audit
- **Investigation result**: `smt_to_lean_bridge.nim` extracts proof blocks by scanning for `unsat` and collecting lines after it. `provider_interface.nim` extracts proof blocks by scanning for `(proof` and tracking parenthesis depth. Different heuristics for different Z3 output formats.
- **Verdict**: NO ACTION NEEDED
- **Date**: 2026-05-20

---

## FP-009: stdlib references flagged as broken project references

- **Files**: `docs/spec/architectural_decisions_and_structural_limits.md` (references `osdirs.nim`, `syncio.nim`, `times.nim`)
- **What was flagged**: Broken `.nim` file references — referenced files not found in `src/` or `tests/`
- **Investigation result**: `osdirs.nim`, `syncio.nim`, and `times.nim` are Nim standard library modules, not project files. The references are documenting stdlib behavior, not project file links. The scan tool did not exclude stdlib references.
- **Verdict**: NO ACTION NEEDED — docs should clarify stdlib vs. project scope
- **Date**: 2026-06-07

---

## FP-010: when isMainModule grep hits in pattern scanner / AST query files

- **Files**: `src/gate/nimtry/forbidden_patterns.nim`, `src/gate/nimtry/nimtry_query.nim`
- **What was flagged**: Two additional `.nim` files appeared to contain `when isMainModule` blocks
- **Investigation result**: `forbidden_patterns.nim` contains `if "when isMainModule" in stripped:` — a string comparison that detects the pattern in other files (pattern scanner). `nimtry_query.nim` contains `wb == "isMainModule"` — an AST query string comparison. Neither is an actual `when isMainModule` block.
- **Verdict**: NO ACTION NEEDED
- **Date**: 2026-06-07

---

## FP-011: \uXXXX Unicode escape flagged as TODO/FIXME

- **Files**: `src/core/json_utils_scan.nim:33`, `src/core/axiom_prelude.nim:13,199`
- **What was flagged**: Three occurrences of `\uXXXX` flagged as TODO/FIXME leftover markers
- **Investigation result**: These are Unicode escape literals in source code (`\uXXXX` pattern), not TODO comments. The scan regex matched the `XXX` substring in `\uXXXX` as a false positive.
- **Verdict**: NO ACTION NEEDED
- **Date**: 2026-06-07

---

## FP-012: ssot-taint nimtry query — 366k+ false positives (DISABLED)

- **File**: `src/gate/nimtry/` (ssot-taint query)
- **What was flagged**: SSOT (Single Source of Truth) taint-tracking query produced an unusable number of violations
- **Investigation result**: The nimtry AST-based ssot-taint query generated 366k+ false positive results, making it effectively non-actionable. The query was **DISABLED** as a result. Root cause: the taint propagation rules were too aggressive, flagging every transitive reference as a potential SSOT violation without distinguishing acceptable cross-module references from genuine violations.
- **Verdict**: ACCEPTABLE DESIGN — query disabled pending rewrite with more precise taint-tracking rules
- **Date**: 2026-05-30

---

## FP-013: domain_types.nim duplication — Facade architecture, not debt

- **Files**: `src/core/domain_types.nim`, `src/core/types/domain_types.nim`
- **What was flagged**: Two `domain_types.nim` files (core 5.8K vs core/types 8.8K) — apparent DEBT#005 pattern recurrence
- **Investigation result**: `src/core/types/domain_types.nim` is a forwarding stub (module), not a type. Because it defines no type, no TypeDefFact can ever match the `"domain_types"` key in `[ssot_types]`, so the key was inert — an illusion of constraint (theater #5). The facade split itself remains valid architecture.
- **Resolution**: RESOLVED 2026-08-02 — key `"domain_types"` removed from `[ssot_types]` in `src/gate/architecture_policy.lock`. The three real type keys remain enforced by the ssot-type-placement query: `ValidatedAsi` → `src/core/metrics.nim`, `VerifiedKernelRatio` → `src/core/types/vkd_types.nim`, `ASIRatio` → `src/core/types/asi_types.nim`.
- **Verdict**: RESOLVED (2026-08-02)

---

## FP-014: integrity_refinement_types.nim — Not orphaned

- **File**: `src/core/integrity_refinement_types.nim`
- **What was flagged**: Classified as orphaned/dead code with no importers
- **Investigation result**: The module has 7 production importers (`refinement_*` modules) and 1 test file importing it. The initial audit classification was incorrect.
- **Verdict**: NO ACTION NEEDED
- **Date**: 2026-06-07

---

## FP-015: procedure-gate working tree scanning — Staged-changes only by design

- **File**: `src/cli/procedure_gate.nim`
- **What was flagged**: Procedure gate failed to detect `.feature` files in `tests/features/` when implementation files changed
- **Investigation result**: The procedure gate intentionally checks `git diff --cached` (staged changes only). Working tree scanning would cause false positives from uncommitted WIP code. This is intentional behavior, not a defect.
- **Verdict**: ACCEPTABLE DESIGN
- **Date**: 2026-06-19

---

## FP-016: Nim `noSideEffect` false positive on `result` field writes — Constructor pattern

- **Files**: Multiple `src/core/` modules (generic `Result` type manipulation)
- **What was flagged**: `func` declaration fails with "can have side effects" when writing to `result.ok` / `result.err`
- **Investigation result**: Nim's effect system conservatively flags field mutation on variant object discriminators as a side effect, even when the mutation is semantically pure (writing to the freshly-allocated `result` object before return). This is a known Nim compiler conservatism. The fix is to use constructor expression syntax (`Result[T, E](ok: false, err: value)`) instead of field mutation. Documented in `docs/spec/nim_effect_system_quirks.md` §2.1 and `docs/agents/core_rules.md` §15b.
- **Verdict**: NO ACTION NEEDED — use constructor pattern per `docs/agents/core_rules.md` §15b
- **Date**: 2026-05-04

---

## Summary

| ID | Source | Verdict | Date |
|----|--------|---------|------|
| FP-001 | context7_evidence_gate.nim → Python misidentification | NO ACTION NEEDED | 2026-05-05 |
| FP-002 | submit_proof.nim "duplicate imports" | NO ACTION NEEDED | 2026-05-05 |
| FP-003 | echo in mcp/server.nim | DOCUMENTATION GAP | 2026-05-05 |
| FP-004 | orchestrator "missing" from impure list | NO ACTION NEEDED | 2026-05-05 |
| FP-005 | report.nim/report_cli.nim overlap | ACCEPTABLE DESIGN | 2026-05-05 |
| FP-006 | submit.nim/submit_proof.nim duplication | ACCEPTABLE DESIGN | 2026-05-05 |
| FP-007 | CLI composition root ISP warnings | ACCEPTABLE DESIGN | 2026-05-11 |
| FP-008 | extractZ3ProofTrace "duplication" | NO ACTION NEEDED | 2026-05-20 |
| FP-009 | stdlib refs flagged as broken refs | NO ACTION NEEDED | 2026-06-07 |
| FP-010 | when isMainModule grep string matches | NO ACTION NEEDED | 2026-06-07 |
| FP-011 | \uXXXX Unicode escapes as TODO/FIXME | NO ACTION NEEDED | 2026-06-07 |
| FP-012 | ssot-taint query (366k+ FPs, DISABLED) | ACCEPTABLE DESIGN | 2026-05-30 |
| FP-013 | domain_types.nim facade duplication | NO ACTION NEEDED | 2026-06-07 |
| FP-014 | integrity_refinement_types.nim "orphan" | NO ACTION NEEDED | 2026-06-07 |
| FP-015 | procedure-gate working tree scanning | ACCEPTABLE DESIGN | 2026-06-19 |
| FP-016 | Nim noSideEffect false positive (constructor pattern) | NO ACTION NEEDED | 2026-05-04 |

---

## Related Documents

- `docs/agents/core_rules.md` §15b — Constructor Over Mutation (Avoid noSideEffect False Positives)
- `docs/agents/core_rules.md` §17 — False Positive Recording Mandate
- `docs/spec/nim_effect_system_quirks.md` §2.1 — Constructor pattern for `noSideEffect` false positives
- `data/logging_policy_exceptions.json` — Runtime exception list for logging-policy-gate false positives
- `docs/known-limitations.md` — Symmetric file for items blocked by genuine constraints
- `docs/DEBT_REGISTRY.md` — Debt registry with additional closed false positive entries
- `data/debt_registry.json` — Machine-readable debt registry (false positives tagged as category "False Positive" or closed with false-positive rationale)

> **Agent instruction**: Before starting any new audit or investigation, read this file first. If you discover a new false positive, append it to this file before the session ends. This prevents deterministic re-investigation waste across stateless agent sessions.
