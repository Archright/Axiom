# WP4-a — B-5b Result: Subject-Scoped Source Resolver (cross-CWD fix)

EXPERIMENT_ID = act2-wp4a-external-proof-candidate-semantics
REVISION      = Axiom working tree (WP3-b + B-3/B-5/B-5b changes, uncommitted)
SUBJECT       = nim-stew@c75502c (immutable `<workspace>/nim-stew-clean-c75502c`)
PARENT        = `wp4a-b5-cwd-sourcing-defect.md` (B-5a: defect localized)

## Question (B-5b)

Per the UX directive: do **not** add `sourceRoot` to `SubjectSymbolRef`. Instead make the resolver
context own `VerificationSubject.subjectRoot`, let the materializer accept symbol identity only,
have the **resolver** decide the source location, and remove the `getCurrentDir()`-based source
fallback. Then add a cross-CWD regression and verify path-independence.

Does this remove the B-5a failure — `external candidate parse failure: decodedLength → eligible=0`
when Axiom launches from a CWD other than the subject root — for a **generic** ExternalSubject (no
nim-stew-specific branch)?

## Decision (from the user)

- SubjectSymbolRef keeps **no** sourceRoot field.
- The resolver closure (built from the engine's run context) owns the subject root.
- Materializer takes symbol identity only; source location is the resolver's job.
- `getCurrentDir()`-based fallback in the materializer is removed.
- New cross-CWD regression added; then fresh/warm + path-independence.

## Files changed

| file:line | change | generic? |
|---|---|---|
| `src/infrastructure/external_ir_materializer.nim` | `import std/os` removed; `readFile(symRef.relativeModulePath)` fallback removed; resolver `none` → `moParseFailure`. Module pipeline doc states: no disk I/O, no CWD, location decided entirely by resolver. | ✅ |
| `src/core/trusted/axiom_pragmas_types.nim:89` | `ModuleContentResolver` effect relaxed `noSideEffect` → `axiomEffect: IOEffect` (disk-backed resolver may hit disk); `raises: []` kept. | ✅ |
| `src/cli/axiom_engine.nim` | new `subjectResolver` closure: (1) `sourceContentCache` fast path, (2) disk `readFile(sourceRoot / modulePath)` where `sourceRoot` = `--project` absolute path (`runProofPipeline` line 616 `sourceRoot = cwdOverride`); **never** CWD. Used **only** at the external materialization call site. Shared cache-only `contentResolver` (support hydration) unchanged. | ✅ |
| `tests/unit/external_ir_materializer_test.nim` T5 | rewritten: cache-`Some` → `moMaterialized`; subject-rooted disk resolver → `moMaterialized` + identical `irSerialized` vs cache path; `none` resolver → `moParseFailure` (no-CWD-fallback invariant). | ✅ |

No protected file touched: `config.nims`, `.github/workflows/ci.yml`, `src/gate/`,
`data/verification_scope.lock`, `data/baseline.json`, journal schema, VKD.

## Result (evidence)

### Build + unit
- `nim c -d:release -o:bin/ax src/cli/main.nim` → exit 0.
- `tests/unit/external_ir_materializer_test.nim` → 9/9 OK.
- `tests/unit/frontier_target_selection_test.nim` → 5/5 OK.

### Cross-CWD E2E (same exact command; only CWD differs)
`ax prove --project <nim-stew-clean-c75502c> --target stew/base36.nim::decodedLength --limit 1`

| CWD | `parse failure` count | decodedLength classify | decodedLength ir-cas key | verifiedRatio |
|---|---|---|---|---|
| `/tmp` | 0 | `vtSmtNative` | `262bb5be2e3a8143ba757714332be09cb71df6ad575fe94a65dedb1216f3d94c` | 0.0000 |
| Axiom repo root | 0 | `vtSmtNative` | `262bb5be…` (identical) | 0.0000 |
| arbitrary temp dir | 0 | `vtSmtNative` | `262bb5be…` (identical) | 0.0000 |

**Path-independence confirmed**: the canonical IR cache key and the full classification trace are
byte-identical across all three CWDs. The B-5a `external candidate parse failure` is **gone** in
every CWD.

## Interpretation

- B-5b **eliminates the CWD-vs-subject source-acquisition defect** for the generic ExternalSubject
  path. Source location is now owned by the resolver context against `VerificationSubject.subjectRoot`,
  never by the process CWD.
- decodedLength still stops at the theory gate in all three CWDs:
  `[tautology] decodedLength: invariant is tautological — REJECT` → `smNone` → `skipped by theory`.
  This is the **pre-existing WP4-a conclusion** that decodedLength has no meaningful postcondition
  (Vacuous / NoObligation). B-5b fixed source acquisition, **not** vacuity; proving a non-vacuous
  external symbol is a separate WP4-a/next-WP step.

## Self-run zero-drift

The canonical self-run (`bin/ax prove --limit 25 --smt-timeout 4000` from the Axiom repo) currently
ends in `PERSIST FAIL: canonical file already exists with a DIFFERENT canonical identity` for
`clampTimeoutMs`/`normalizeMaxWorkers` → exit 2. This is the **pre-existing stale-cert-collision
infrastructure defect** (`docs/audit/ci_gate_stale_cert_collision_root_cause_2026-08-24.md`, R3),
**not** introduced by B-5b: the support hydration resolver is behaviorally unchanged (cache-only),
and a support symbol's canonical identity is a pure source/semantic projection unaffected by the
effect-annotation relaxation. `data/verification_scope.lock` was byte-identical to its pre-run
backup (no trust-state mutation from the self-run).

## Protected invariants (B-6)

- Subject immutability: `nim-stew-clean-c75502c` HEAD = c75502c, working tree clean (0 changes).
- `config.nims`, `ci.yml`, `src/gate/`, `verification_scope.lock`, `baseline.json` — unmodified.
- No nim-stew-specific condition, no `verification_scope.lock` edit, no journal/VKD/cert schema edit.

## Classification

- Source-acquisition defect: **InfrastructureFailure** — now **fixed** (generic rule).
- decodedLength theory rejection: pre-existing `NoObligation`/`Vacuous` semantic classification.

## Non-Conclusions

- B-5b does **not** make decodedLength reach Z3 (it is vacuously no-obligation); this is not claimed.
- B-5b does **not** address the pre-existing stale-cert self-run RED; that is tracked separately
  (R3 CI defect).
- No submodule/vendoring, no `verification_scope.lock` ext, no golden-symbol replacement performed.

## Recommended next work package

A non-vacuous, proof-capable external symbol (per WP4-a Phase C plan) to carry
`ObligationUniverse → ProofCandidate → Z3 → Lean → KAA` on the now-fixed source-acquisition path.
