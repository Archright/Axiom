# WP4-a — B-5 Result: Hardcode Removal + CWD-Dependent Source Acquisition Defect

EXPERIMENT_ID = act2-wp4a-external-proof-candidate-semantics
REVISION      = Axiom HEAD 089251924 (working tree, uncommitted WP3-b + B-3/B-5 changes)
SUBJECT       = nim-stew@c75502c (immutable <workspace>/nim-stew-clean-c75502c)

## Question

Does removing the hardcoded `decodedLength` golden-symbol registration let the generic
registry-miss path (`materializeExternalIR` → `classifyCandidateEligibility`) reproduce the
same engine behavior (decodedLength reaches Z3) — i.e. does "Registry membership ≠ Proof
eligibility" hold in practice for the real external symbol?

## Procedure (evidence commands)

1. Remove `goldenSymbolRegistered` (axiom_engine.nim:93) and the `if not goldenSymbolRegistered...`
   hardcode block (axiom_engine.nim:1024-1042) — the `registerAxiom("decodedLength", ..., isKern=true,
   bmcSkippable=false, origin=soExternalSubject)` special case.
2. Rebuild release binary.
3. E2E from a NON-subject CWD and from the subject-root CWD; compare decodedLength admission.
4. Standalone probe of `materializeExternalIR` against the real `stew/base36.nim` source.

## Result

### 1. B-5 removal is structurally clean
- No remaining `decodedLength`/`goldenSymbolRegistered` references in `axiom_engine.nim`.
- Build exit 0.
- `tests/unit/external_ir_materializer_test.nim` 9/9 OK, `tests/unit/frontier_target_selection_test.nim` 5/5 OK.
- No protected file touched (config.nims, ci.yml, gate/, verification_scope.lock, journal, VKD, baseline).

### 2. Probe proves the generic path CAN materialize the real decodedLength
Standalone `materializeExternalIR(SubjectSymbolRef("stew/base36.nim","decodedLength"), resolver)` with
subject-root CWD and a `none`-resolver (forcing the in-module disk fallback):

```
parseRootNil=false  rootKind=nkStmtList
findAllFuncDefsP(matches)=1
canonKind=ckFuncDef
irName='decodedLength'  irNameLen=13
irParams=2:  btype→irtBitVec64, length→irtBitVec64
irRetTy=irtBitVec64
isBmcSkippable=false
materializeOutcome=moMaterialized
```

- `isBmcSkippable=false` matches the removed hardcode's `bmcSkippable=false`
  (body `(length*179) div 277`: int ret, int/typedesc params, integer literals only).
- `assessAdmissibility` / `inVerifiedFragmentV1` / `classifyCandidateEligibility` do NOT read
  `isKernel` or `origin`, so the synthesized `isKernel=false` entry classifies identically to the
  removed hardcoded `isKern=true` entry.

### 3. Engine diverges — decodedLength admission depends on launch CWD

Non-subject CWD (e.g. /tmp):
```
external candidate parse failure: decodedLength in stew/base36.nim
frontier eligibility gate: excluded 326 ...; eligible=0
loop_driver: verifying 0 nodes ... 0 UAP requests
solverInvocationCount = 0
```

Subject-root CWD (`cd nim-stew-clean-c75502c && ax prove --project .`):
```
frontier eligibility gate: excluded 325 ...; eligible=1
[classify] decodedLength → vtSmtNative
[tautology] decodedLength: invariant is tautological — REJECT
IR pipeline FAIL: decodedLength status=psError provenance=solverMethod=smNone
```

## Root Cause (generically localized)

`src/infrastructure/external_ir_materializer.nim:130`:

```nim
source = readFile(symRef.relativeModulePath)   # CWD-relative path resolution
```

`materializeExternalIR` acquires subject source content from two sources:
1. the `ModuleContentResolver` (engine passes `bundle.sourceContentCache`, keyed by normalized
   relative path — line 652/653 of axiom_engine.nim);
2. if the resolver returns `none`, the in-module disk fallback `readFile(relativeModulePath)`.

The engine resolves cache misses to `none`, and the fallback then reads the **relative path against
the process CWD**. When Axiom is launched from anywhere other than the subject root, `readFile("stew/
base36.nim")` misses → raises → caught → `moParseFailure` → `eligible=0` → Z3 never reached.

This is NOT a nim-stew limitation and NOT an inability to handle `typedesc[Base36Types]`:
- The probe materializes the exact same symbol fine.
- With subject-root CWD, the engine admits it (`eligible=1`) and it reaches the IR pipeline.

It is a generic **subject-root / CWD ownership defect** in the materializer's source acquisition —
the same class of problem surfaced repeatedly in WP0-WP4 (artifact ownership decided by CWD /
current directory instead of the canonical subject state).

## Divergence point (exact)

- Probe path: CWD = subject root → disk fallback reads the right file → `moMaterialized`.
- Engine path: CWD = process CWD → `contentResolver` miss → disk fallback reads wrong location → `moParseFailure`.

Split happens at the `readFile(symRef.relativeModulePath)` fallback — it must resolve against a
canonical subject root, not CWD.

## Classification

The B-5 change removed the hardcode correctly. The regression it exposed is an
`InfrastructureFailure` / `ConfigurationError` (artifact/source resolution defect in the generic
ExternalSubject path), NOT a subject-code or Axiom-semantic failure.

## Minimal generic fix (proposed, NOT yet applied — per discipline)

Thread the canonical subject root into the materializer so source acquisition never depends on CWD:

- Add an absolute `sourceRoot*` field to `SubjectSymbolRef`.
- At the call site (`axiom_engine.nim:707`), populate it from the resolved subject root
  (the same value used to drive topology; `projectAbs`).
- In `materializeExternalIR`, change the fallback to
  `readFile(sourceRoot / symRef.relativeModulePath)`.

This is a general ExternalSubject rule for every subject repository — no nim-stew-specific branch.

## Non-Conclusions

- decodedLength's `[tautology] invariant is tautological — REJECT` in the CWD=subject run is NOT a
  new regression; it is consistent with B-2b's measured `Vacuous`/no-postcondition result. decodedLength
  remains a valid **Admission Anchor**, not a valid **ProofExecutionAnchor**.
- The B-5 removal did not establish "decodedLength reaches Z3" in the engine's default (non-subject-CWD)
  launch — this awaits the source-acquisition fix above, then re-measurement.

---

## B-5b — Fix Applied (resolver owns subject root; NOT a field on SubjectSymbolRef)

Per the user directive: **do not add `sourceRoot` to `SubjectSymbolRef`.** Instead the resolver
context owns `VerificationSubject.subjectRoot`, and the materializer receives symbol identity only;
source location is decided entirely by the resolver. `getCurrentDir()`-based fallback is removed.

### Files changed (all generic ExternalSubject rules — no nim-stew-specific branch)

| file | change |
|---|---|
| `src/infrastructure/external_ir_materializer.nim` | removed `import std/os` and the `readFile(symRef.relativeModulePath)` CWD fallback; resolver `none` → `moParseFailure`. Materializer does **no disk I/O**; source location is exclusively the resolver's responsibility. |
| `src/core/trusted/axiom_pragmas_types.nim:89` | `ModuleContentResolver` relaxed from `noSideEffect` → `axiomEffect: IOEffect` (a disk-backed resolver must be allowed to hit disk; `raises: []` kept, disk errors caught → `none`). |
| `src/cli/axiom_engine.nim` | new `subjectResolver` closure captures `sourceRoot` (= `effectiveCwdOverride` = `--project` absolute path, line 616 `sourceRoot = cwdOverride`); it checks `sourceContentCache` first, then falls back to `readFile(sourceRoot / modulePath)` — **never CWD**. The shared cache-only `contentResolver` (support hydration) is left unchanged. |
| `tests/unit/external_ir_materializer_test.nim` T5 | rewritten: (a) cache `Some` resolver → `moMaterialized`; (b) subject-rooted disk resolver (decides location from its own root) → `moMaterialized`, identical `irSerialized`; (c) `none` resolver → `moParseFailure` (no CWD fallback invariant). |

### Verification (this run)

- Release build: exit 0.
- `external_ir_materializer_test.nim` 9/9 OK; `frontier_target_selection_test.nim` 5/5 OK.
- E2E run from **three different CWDs** with the same `--project <nim-stew-clean-c75502c> --target stew/base36.nim::decodedLength --limit 1`:

| CWD | parse failure? | decodedLength classify | decodedLength ir-cas key | verifiedRatio |
|---|---|---|---|---|
| `/tmp` | 0 | `vtSmtNative` | `262bb5be2e3a8143ba757714332be09cb71df6ad575fe94a65dedb1216f3d94c` | 0.0000 |
| Axiom repo root | 0 | `vtSmtNative` | `262bb5be…` (identical) | 0.0000 |
| arbitrary temp dir | 0 | `vtSmtNative` | `262bb5be…` (identical) | 0.0000 |

**Cross-CWD path-independence confirmed**: source acquisition and the canonical IR cache key are
byte-identical across CWDs. The B-5a defect (`external candidate parse failure: decodedLength →
eligible=0` when CWD ≠ subject) is **eliminated**.

### Remaining gate for decodedLength (pre-existing, NOT a source-acquisition defect)

Even with source acquired, decodedLength is rejected at theory level in **all three CWDs**:
`[tautology] decodedLength: invariant is tautological — REJECT` → `IR pipeline FAIL ... smNone`
→ `[1/1] decodedLength — skipped by theory`. This is the pre-existing WP4-a conclusion that
decodedLength has **no meaningful postcondition** (Vacuous/NoObligation). B-5b fixed source
acquisition, not vacuity. A non-vacuous external proof target is a **separate WP4-a/next-WP** concern.

### Self-run zero-drift note

The canonical self-run (`bin/ax prove --limit 25 --smt-timeout 4000` from the Axiom repo) currently
ends in `PERSIST FAIL: canonical file already exists with a DIFFERENT canonical identity
(clampTimeoutMs / normalizeMaxWorkers)` → exit 2. This is the **pre-existing stale-cert-collision
CI defect** documented in `docs/audit/ci_gate_stale_cert_collision_root_cause_2026-08-24.md`
(R3 infrastructure defect), **not** introduced by B-5b: the support-hydration resolver
(`contentResolver`) is behaviorally unchanged (cache-only), and the canonical identity of a support
symbol is a pure source/semantic projection unaffected by the type-annotation relaxation.
`data/verification_scope.lock` was verified byte-identical to its pre-run backup (no trust-state
mutation from the self-run).
