# ACT 2 — WP4-i External Structural Signature/Type Ingress — Report

Date: 2026-08-30.
AGENTS.md §14 reporting contract for WP4-i. Canonical artifacts live in
`Axiom/experiments/act2-wpi-structural-ingress/` (corpus originally materialized
in the workspace-root `experiments/` and copied here; originals retained).

---

## Question

The working premise entering this WP was: "StructuralAST fails to parse legal
external signatures containing `openArray[byte]`, `HSlice`,
`type[SomeUnsignedInt]`; a structural representation extension (ParamType) is
needed." WP4-i was scoped to measure that claim on a signature corpus, localize
the exact loss point, and only then extend representation — under the discipline
Measure → Localize → Minimal generic fix → Regression → Same-anchor replay.

## Context

- PROJECT_UNDER_TEST: nim-stew (immutable subject `nim-stew-clean-c75502c`).
- SUBJECT_SYMBOL: `stew/bitops2.nim:559 :: getBitsBE`
  (`openArray[byte]`, `HSlice`, `type[SomeUnsignedInt]` signature; template
  overload at :599-600).
- AXIOM_REVISION: Axiom working tree + WP4-i Phase C minimal fix (on top of
  WP4-h-3 typed ProofIR).
- AXIOM_CONFIGURATION: `nim c -d:release -o:bin/ax src/cli/main.nim`; CLI `prove`
  with `AXIOM_STATE_DIR` state dir seeded from `data/verification_scope.lock`.
- TOOLCHAIN_IDENTITY: Nim 2.2.10 (hermetic layered build), Z3 (not reached this WP).
- EXPERIMENT_ID: `act2-wpi-structural-ingress`.

## Scope

In scope: signature-corpus measurement (Phase A), static loss-point
localization (Phase B), the resulting minimal generic ingress fix (Phase C),
regression + self zero-drift (Phase E), same-anchor replay (Phase F).
Out of scope (unchanged from the WP charter): SMT/lowering expansion, IRType
promotion, contract injection, Lean/KAA/Trust rework, Track B.

## Procedure

1. Phase A (coder agent): `probe/corpus_probe.nim` ran 12 cases (8 minimal
   signature cases + the real func/template texts + empty-string case) through
   the actual pipeline parser `parseNimRes` (Nim compiler parser), plus
   `nim check` legality baseline; JSON output; run twice for determinism.
2. Phase B (explore agent): static 13-hop call-chain localization of
   `sourceCode` from CLI to the guard, plus adversarial elimination of
   alternative hypotheses (a–e).
3. Phase C (coder agent): baseline internal snapshot → fix → rebuild/audit →
   5 regression suites → internal zero-drift re-run → cheap external probe.
4. Phase F (direct): canonical same-anchor replay with fresh state dir.

## Result

### The premise was REFUTED (Phase A+B, convergent)
- Corpus: ALL non-empty cases parse successfully with Axiom's own parser —
  including the verbatim `getBitsBE` func and template texts and every minimal
  case (`openArray[byte]`, `HSlice`, `typedesc[int]`,
  `type[SomeUnsignedInt]`, combinations). The ONLY failing case is the empty
  string. Determinism: run1 JSON == run2 JSON byte-identical.
- Root cause (mechanical): `src/cli/payload_bridge.nim` read the module file
  with `readFileOpt(modulePath)` resolved against the PROCESS CWD instead of
  the subject root. For `--project` external subjects the read fails →
  `sourceCode = ""` → `parseStringAST` silently returns nil
  (`src/core/parser_utils.nim:72` early-return, no diagnostic capture —
  confirmed by the unmodified `logs/lean_lsp_payloads.jsonl`) →
  `parseNimRes` err("Failed to parse Nim source") → guard hard-reject.
  The internal path (`wf_planning.nim:99`) already resolved against
  `sourceRoot`; only the external payload bridge lacked it.

### Phase C — minimal generic fix (applied)
- `src/cli/payload_bridge.nim`: both `readFileOpt` sites now resolve against a
  new `sourceRoot: string = ""` parameter (subject root when set; empty →
  byte-identical legacy behavior). No content fabrication; unreadable stays `""`.
- `src/cli/axiom_engine.nim:840`: passes `bundle.sourceRoot` (positional).
- `src/core/diagnostics/pattern_guard.nim:312-317`: empty/whitespace source now
  fails with the explicit reason "Empty source: no source content available"
  instead of a conflated parse error (P4 fail-closed observability).
- `src/core/parser_utils.nim`: deliberately untouched.

### Phase E — regression + zero-drift
- 5 regression suites green (95 assertions total): theaterguard 2, eligibility 5,
  state_machine 52, obligation_ir 23, obligation_adapters 13. No test changes
  needed.
- Audit: 2 pre-existing violations (identity.nim:52, canonical_cache.nim:149);
  0 from touched files. Build exit 0 before and after.
- Internal zero-drift: pre/post proof summaries identical
  (Total=5, Pass=3, Fail=2, TO=0, Skip=0, Error=0, exit 0).

### Phase F — same-anchor replay (canonical run)
- `runs/prove_getBitsBE_postfix_run1.log` (exit 0). Delta vs pre-fix:
  - `structural_ast (topology)` → `structural_ast (io_boundary)` — the sieve now
    analyzes the real function body (empty-source fallback gone).
  - `Failed to parse source: Failed to parse Nim source` — GONE.
  - New guard context: `Missing preconditions: has_loop` → `erGuardHardReject`.
  - Still: `solverInvocationCount=0`, `obligationAttemptedCount=0`,
    `smtlib2Query=""`, UAP 0 results, node `pre_sieved`, tier `unknown`,
    verifiedRatio 0.0000 (0/40).
  - `obligationGeneratedCount=13` — WP4-h-3's intrinsic obligations ARE
    generated in the IR pipeline but are never ATTEMPTED because the node dies
    in the structural healing path first.

## Evidence

- `canonical/signature_corpus.json` (+ run1/run2, corpus_README.md, probe).
- `canonical/phase_c_implementation.md` — diff summary, audit, tests, zero-drift.
- `runs/prove_getBitsBE_postfix_run1.log`, `runs/README.md` (delta table).
- Pre-fix comparison: `../act2-wp4h3-proofir/runs/prove_getBitsBE_run1.log`.
- Trajectory/telemetry preserved under `/tmp/wpi_replay/state/logs/`.

## Classification

- The standing claim "openArray/HSlice/typedesc signatures fail structural
  ingress" — REFUTED. Per AGENTS.md §10 the failure was an **Axiom integration
  defect** (CWD-relative source read), not an unsupported language construct.
- End-to-end getBitsBE outcome: still no proof attempt. The NEW boundary is the
  structural healing pattern-precondition check (`Missing preconditions:
  has_loop` under the content-derived `io_boundary` rule): the sieve selects a
  loop-oriented healing pattern for a loop-free function, and non-applicability
  escalates as a hard reject — blocking the 13 already-generated intrinsic
  obligations from ever being attempted. This is a **strategy-selection /
  escalation-semantics** boundary, not a parse, type, or solver boundary.

## Interpretation

- WP4-i achieved its operative goal under the corrected premise: external
  structural ingress now delivers real, parseable source to the pipeline, with
  fail-closed observability and zero drift on internal runs.
- The WP's original representation-extension plan (ParamType) was NOT needed:
  implementing it would have been speculative work on a refuted premise. It is
  recorded as intentionally skipped.

## Non-Conclusions

- No verification result is claimed for getBitsBE; Z3/Lean/KAA/Trust were not
  reached. The node remains `pre_sieved` with an escalated structural task.
- The corpus proves parseability of the signature class, not semantic
  interpretation or SMT lowerability of those types (that remains future work
  if ever required by an obligation).
- The zero-drift check covers one internal prove snapshot; it is evidence of
  unchanged behavior on that path, not a proof of global behavioral identity.

## Next Experiment

Smallest next WP (boundary moved one stage deeper): the structural healing
path for loop-free functions. Two candidate questions, to be measured before
any fix: (1) does the sieve's dominant-rule selection (`io_boundary` for a
loop-free bit-manipulation function) mis-select, and (2) should pattern
non-applicability escalate as `erGuardHardReject` (terminal) or as a soft
skip/retry that lets the 13 generated intrinsic obligations — already carried
by WP4-h-3's typed ProofIR — be attempted through the Z3 path? Measuring (2)
first is the most direct route to observing the typed-lowering → Z3 boundary
end-to-end on the same anchor.
