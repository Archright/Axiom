# Phase A — Forensic Measurements: WP4-k (First Obligation Execution Closure)

**Experiment ID:** act2-wpk-obligation-execution
**Subject:** <workspace> / Axiom (Nim source under `Axiom/src/`)
**Date:** 2026-08-30
**Scope:** Read-only measurement only. No source code modified. No binary executed.

---

## 1. Gap-2 Exact Site: `runZ3CheckViaIR(funcDef, phase = spBmc)` at ir_pipeline_runner.nim:1017

### (a) `ogr.kind == ogrGenerated` and `lowered` in scope at :943–952

```nim
# :943
if ogr.kind == ogrGenerated:
  let firstObl = ogr.obligations.value[0]
  if firstObl.proposition != nil:
    let loweringCtx = SmtLoweringContext(
      logic: smtLogic,
      rlimit: z3DeterministicBudget,
      obligationKind: $firstObl.kind)
    let lowered = lowerObligationToSmt(firstObl.proposition, loweringCtx)
    if not lowered.empty:
      smtScript = lowered.smtScript
```

Both `ogr` and `lowered` are in scope at :943–952. `lowered` is a `SmtLoweringResult` with field `smtScript`.

### (b) `lowered.smtScript` field existence

`SmtLoweringResult` (defined in `obligation_smt_lowering.nim`) carries `smtScript: string`. Confirmed by :952 assignment `smtScript = lowered.smtScript`.

### (c) The :1017 call site — is `lowered.smtScript` observable there?

At :1017:
```nim
let bmcOutcome = runZ3CheckViaIR(funcDef, phase = spBmc)
```

This calls the **first overload** `runZ3CheckViaIR*(funcDef: IRFuncDef, phase: SmtPhase)` at :251, which internally does:
```nim
let smtScript = irToSmtScript(funcDef)   # :252 — re-generates from funcDef
```

The `lowered.smtScript` (assigned to the local `smtScript` variable at :952) is **NOT** passed to this call. The obligation-derived SMT script computed at :950–952 is discarded at :1017 in favor of re-generating via `irToSmtScript(funcDef)`.

### (d) How `irToSmtScript(funcDef)` at :1017 would differ from `lowered.smtScript`

- `irToSmtScript(funcDef)` at :252 produces a **postcondition-derived** SMT script via the classic adapter's string-based output (the legacy IR→SMT adapter).
- `lowered.smtScript` (from `lowerObligationToSmt` at :950) produces an **obligation-derived** SMT script from the obligation's typed `IRExpr` proposition through the typed ProofIR→SMT path.

The obligation-derived path (P3 Typed Obligation Lowering, :934–952) is the intended canonical path for `ogrGenerated` targets, but the BMC check at :1017 bypasses it by re-running the legacy adapter.

### IR Pipeline Scope Boundaries

- **Stage 1** (`:399`): Deserialize IR
- **Stage 2** (`:929–933`): Generate SMT-LIB2 via `irToSmtScript`
- **Stage 2b** (`:943–952`): P3 Typed Obligation Lowering — overrides `smtScript` with obligation-derived version
- **Stage 3** (`:1009`): Generate Lean via `irToLeanModule`
- **Stage 4** (`:1010–1017`): Cross-validation + Z3 check-sat
- **Stage 4b** (`:1017`): `runZ3CheckViaIR(funcDef, spBmc)` — **gap 2**: re-generates SMT via legacy adapter instead of using the already-lowered obligation script

---

## 2. Drop Ledger — Loop Driver Sieve Rejects

The "sieve" in loop_driver.nim is the **Pre-Sieve Interceptor** (Stage 1b). The primary rejection site is:

| Line | Status | Classification | Has Reason? |
|------|--------|---------------|-------------|
| :955 | `orchestrationPreSievedUnverifiable` | Pre-sieve blocked | Yes — `"PRE-SIEVED"` in `evidenceLogJson` |

The pre-sieve block at :951–967 has two sub-paths:

1. **Terminal block** (`:195–207`): `isPreSieveTerminalBlock(sieveResult.sieveVerdict)` is true → `orchestrationPreSievedUnverifiable` with refactor trigger. This is a **hard reject** — the candidate is genuinely fatal (non-Nim file, empty source, non-routine symbol).

2. **Carve-out** (`:208–211`): Opinion-fusion block only → falls through to Stage 1c. Not a reject.

**"Pattern mismatch"** is referenced at :193 in loop_driver.nim:
> "Pattern mismatch on the structural opinion is a strategy failure, not a candidate failure — the routine is handed downstream for obligation-aware execution instead of being scraped."

This is a comment, not an enum value. The sieve engine (`sieve/sieve_engine.nim:51–119`) uses `SieveVerdict.blocked: bool` as the sole rejection signal. There are **no** `erGuardReject` or `hard-reject` enum values in the codebase — these are conceptual categories from prior analysis notes.

**Total rejection sites in loop_driver.nim (sieve-related):** 1 hard reject site at :955 (`orchestrationPreSievedUnverifiable`), with 1 sub-classification (terminal block vs. carve-out) determined by `isPreSieveTerminalBlock` at :195.

---

## 3. Drop Ledger — Scheduler (batch_uap)

The scheduler is `runBatchUapOrchestration` in `loop_driver.nim:608`. The canonical-id/rejection paths (7 sites per prior notes):

| # | Line | Status | Classification | Has Reason? |
|---|------|--------|---------------|-------------|
| 1 | :939 | `orchestrationProofFailed` | Type-directed candidate (no kernel acceptance) | Yes — `"TYPE-DIRECTED (candidate only, no kernel acceptance)"` |
| 2 | :955 | `orchestrationPreSievedUnverifiable` | Pre-sieve blocked | Yes — `"PRE-SIEVED"` |
| 3 | :985 | `orchestrationTimedOut` | Node timeout | Yes — `"node timeout during UAP"` |
| 4 | :999 | `orchestrationSkippedByTheory` | BMC-incompatible theory | Yes — `"UAP skipped by theory (BMC incompatible)"` |
| 5 | :1001 | `orchestrationNotVerifiable` | Obligation terminal (ogrUnsupported/ogrIllFormed) | Yes — `budgeted.skipDetail` or `$budgeted.skipReason` |
| 6 | :1003 | `orchestrationProofFailed` | UAP failed (other) | Yes — `"UAP failed"` |
| 7 | :1144 | `orchestrationVerified` | Success (promotion-eligible) | Yes — promotion result |

**Classification:**
- **Terminal accounting (has reason):** All 7 sites carry a reason in `evidenceLogJson` or `skipDetail`.
- **Silent drop (no reason):** None. Every rejection path records a reason.

Note: The scheduler also has early-exit paths for cache hits (`:923–931`) and budget exhaustion (`:871–882`) that are not rejection sites per se but are terminal accounting points.

---

## 4. CanonicalEnvelopeDigest Computation Site: z3_pool.nim

### `buildZ3QueryEnvelope` at :607

```nim
proc buildZ3QueryEnvelope(query: string; timeoutMs: int; sentinel: string;
    enableProofs: bool = false; mode: Z3ExecutionMode = zmRaw): string =
  result = query
  # ... adds options, reset, random seeds ...
  # :648-650 — sentinel append (LAST):
  if not result.endsWith("\n"):
    result.add("\n")
  result.add("(echo \"" & sentinel & "\")\n")
```

**Key findings:**
- The sentinel is appended **LAST** (`:648–650`), after all other modifications to `result`.
- **No digest is computed** inside `buildZ3QueryEnvelope`. The function is purely a string builder.
- The "pre-sentinel bytes" are the value of `result` just before `:650` (i.e., the envelope with all options but without the sentinel echo).
- The "full payload incl sentinel" is the final `result` returned by the function.
- The envelope variable is the implicit `result` (Nim's default return variable).

### Where a digest would be computed

A canonical digest of the pre-sentinel bytes would need to be computed **after** `buildZ3QueryEnvelope` returns, or within it before the sentinel append at `:650`. Currently, no such digest exists.

The `payload` variable at `:832` holds the full envelope (incl. sentinel):
```nim
payload = buildZ3QueryEnvelope(query, timeoutMs, sentinel, enableProofs, mode)
```

---

## 5. solverInvocationId / Deterministic Exec

### `z3ExecPersistent` at z3_pool.nim:745

```nim
proc z3ExecPersistent*(query: string; timeoutMs: int; desiredWorkers: int = 1;
    enableProofs: bool = false; queryType: string = "unknown"; cegarIters: int = 0):
    Result[string, string] {.gcsafe, raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
```

**Invocation params:**
- `timeoutMs`: From `getBudgetFor(phase)` at :597–605 (SmtBudget: 8000ms for spBmc, 2000ms for spBaseCase, 5000ms for spInductiveStep, clamped by `AXIOM_SMT_TIMEOUT` env)
- `rlimit`: Set inside `buildZ3QueryEnvelope` at :620–622 from `z3DeterministicBudget` (the deterministic budget SSOT)
- `queryType`: Defaults to `"unknown"` — passed to telemetry at :772
- `cegarIters`: Default 0, passed to telemetry at :778
- `enableProofs`: Default false, passed to `buildZ3QueryEnvelope` at :832

### `AXIOM_Z3_INCREMENTAL` env read

At z3_pool.nim:338:
```nim
threadZ3Worker.scopeTracker.enabled = getEnv("AXIOM_Z3_INCREMENTAL") == "1"
```
This is read once during lazy worker initialization in `getThreadZ3Worker`, not per-invocation.

### Per-invocation identifier / digest

**No invocation-id or digest is currently attached per invocation.** The only per-invocation identifier is the `sentinel` string (`"AXIOM_Z3_EOF_" & $id` from `nextZ3Sentinel` at :653–658), which is used for output parsing (finding the end of a query's output) but is not carried forward as a digest or invocation ID in the result.

The `queryType` parameter (default `"unknown"`) is the closest thing to a classification label, but it is only used in telemetry logging, not attached to the result or used for deterministic replay.

---

## 6. Existing Digest Fields

### `smtScriptDigest`

| File | Line | Struct |
|------|------|--------|
| `core/trusted/solver_invocation.nim` | 19 | `SolverInvocation.smtScriptDigest: string` |
| `core/trusted/solver_invocation.nim` | 65 | `smtDigestConsistent()` function — compares `sha256Hex(si.smtScript) == si.smtScriptDigest` |
| `core/trusted/evidence_capture.nim` | 72 | Populated as `sha256Hex(smtScript)` in `SolverInvocation` construction |
| `core/trusted/claim_store_append.nim` | 57 | Serialized into JSON as `"smtScriptDigest"` |

### `smtDigestConsistent`

`core/trusted/solver_invocation.nim:62` — a **function** (not a field), `smtDigestConsistent*(si: SolverInvocation): bool`.

### `CanonicalEnvelopeDigest`

**No occurrences found** in `src/`. This is entirely net-new for O9.

### `TransportPayloadDigest`

**No occurrences found** in `src/`. This is entirely net-new for O9.

### `SolverInvocation`

`core/trusted/solver_invocation.nim:8` — defined as:
```nim
SolverInvocation* = object
  scriptDigest*: string
  solverIdentity*: string
  solverVersion*: string
  solverOptionsDigest*: string
  semanticProfileId*: string
  encodingIdentity*: string
  env*: string
  canonicalSourceIdentity*: string
  specificationIdentity*: string
  translationIdentityHash*: string
  smtScriptDigest*: string
  smtScript*: string
```

**Summary:** `smtScriptDigest` already exists in `SolverInvocation`. `CanonicalEnvelopeDigest` and `TransportPayloadDigest` are net-new for O9. No `solverInvocationId` or per-invocation digest exists today.

---

## 7. IrPipelineResult Struct

**Definition:** `ir_pipeline_runner.nim:108`

```nim
IrPipelineResult* = object
  funcName*: string
  modulePath*: string
  irDigest*: string
  smtScript*: string
  leanSource*: string
  crossValidation*: CrossValidationResult
  z3Sat*: bool
  success*: bool
  skipped*: bool
  verification*: vrt.VerificationResult
  provenance*: VerificationProvenance
  backend*: VerificationBackend
  actualBackend*: VerificationBackend
  fallbackOccurred*: bool
  fallbackReason*: string
  requestedBackend*: VerificationBackend
  selectedBackend*: VerificationBackend
  complexity*: float
  verifiedClaim*: Option[VerifiedClaim]
  obligationVerdict*: ObligationVerdictInfo
  evidence*: Option[CanonicalLeanEvidence] = none(CanonicalLeanEvidence)
```

**Value type:** Yes — `object` (not `ref object`). Nim value type with copy semantics.

**`toProofCertificate` at :1298:** Accesses only named fields (additive-safe). The conversion function `resultMethodToSolverMethod` at :1291 maps `vrt.SolverMethod` → `proof_certificate.SolverMethod`. The certificate writing path uses `ProofCertificate` (defined in `engine/proof_certificate.nim:67`) which is a separate ADT with its own fields.

**Certificate writing path (`cert_writer.nim`):**
- `writeCertificateFromUapResult` at `cert_writer.nim:212` — writes JSON via `certJson["key"] = ...` (open-ended `JsonNode` key-value construction, not a fixed-schema record).
- The `solverInvocation` JSON field at `:445–450` is written as a sub-object with `engine`, `version`, `strategy`, `mode` — **not** using `solverMethod` enum directly. The `solverMethod` from `ProofCertificate` is used for display/aggregation but not serialized into the cert JSON's `solverInvocation` field.

---

## 8. `osr` Enum (ObligationSkipReason)

**Definition:** `obligation_types.nim:236`

```nim
ObligationSkipReason* = enum
  osrNone                ## no skip — normal termination (verified / failed / timeout)
  osrNoObligation        ## proven absence of obligations (rkNoObligation / ogrNoApplicableObligation)
  osrBmcSkipped          ## BMC skipped — type not representable in QF_BV (vpBmcSkipped)
  osrObligationTerminal  ## obligation generator terminal (ogrUnsupported / ogrIllFormed)
```

**`$` renderer** at `obligation_types.nim:242–248`:
```nim
func `$`*(reason: ObligationSkipReason): string {.raises: [].} =
  case reason
  of osrNone: ""
  of osrNoObligation: "no_obligation"
  of osrBmcSkipped: "bmc_skipped"
  of osrObligationTerminal: "obligation_terminal"
```

**New members for O9:** `osrDroppedOutsideScope` and `osrDroppedNoPlan` would require:
1. New enum members added to `ObligationSkipReason`
2. New `of` branches in the `$` renderer at `:242–248` (to preserve the serialization invariant of legacy-compatible string literals)
3. New `of` branches in every `case reason` dispatch that exhaustively matches `ObligationSkipReason` — currently used at `loop_driver.nim:998–1003` (3 branches) and `stages.nim:336,349,360,372` (4 branches)

**Note:** There is no `ObligationSieveResult` type in the codebase. The `osr*` prefix belongs to `ObligationSkipReason`.

---

## 9. SolverOutcome Values + Certificate solverMethod

### `SolverOutcome` (solver_adapter.nim:28)

```nim
SolverOutcome* = object
  status*: SolverStatus
  certificate*: CandidateCertificate
  statistics*: SolverStatistics
  diagnostics*: string
```

### `SolverStatus` enum (solver_adapter.nim:11)

```nim
SolverStatus* = enum
  sosUnsat, sosSat, sosUnknown, sosTimeout, sosResourceLimit,
  sosProcessError, sosParseError
```

### `SolverMethod` enum (engine/proof_certificate.nim:42)

```nim
SolverMethod* = enum
  smFFI               ## Z3 C API direct call
  smCLI               ## Z3 subprocess via persistent pool (z3_pool.z3ExecPersistent)
  smLean              ## Lean 4 kernel type-checking
  smTypeLevel         ## Type-level encoding fast-path
  smSpacer            ## Spacer CHC bypass
  smTrivial           ## Trivial proof (pre-sieve / type-directed)
  smNone              ## No solver invoked (error / skip)
```

### Which solverMethod is produced on the IR pipeline / z3 CLI path?

**`smCLI`** — The IR pipeline's `runZ3CheckViaIR` calls `z3ExecPersistent` (the persistent pool path). The mapping is at `ir_pipeline_runner.nim:1294`:
```nim
of vrt.smBMC: proof_certificate.smCLI
```

### Exact write site for solverMethod in the certificate

`ir_pipeline_runner.nim:1352` — inside `toProofCertificate`:
```nim
let cert = ProofCertificate(
  ...
  solverMethod: sm,
  ...
)
```

The `solverMethod` field in `ProofCertificate` is set via `resultMethodToSolverMethod(r.verification.solverMethod)` which maps the `VerificationResult.solverMethod` (from `vrt.SolverMethod`: smCHC, smBMC, smTypeLevel, smNone) to `proof_certificate.SolverMethod` (smSpacer, smCLI, smTypeLevel, smNone).

The `cert_writer.nim` `writeCertificateFromUapResult` path (`:445–450`) does **NOT** write `solverMethod` into the certificate JSON. Instead it writes a `solverInvocation` sub-object with `engine`/`version`/`strategy`/`mode` string fields. The `solverMethod` enum is used in `ProofCertificate` for display/aggregation but not serialized into the canonical cert JSON by the UAP write path.

---

## 10. assertNotTerminal Precedent

**Definition:** `proof_state_machine.nim:112–120`

```nim
func assertNotTerminal*(o: ObligationOutcome): TransitionResult[ObligationOutcome] {.axiomDecision(
  id = "DECISION-0813",
  reason = "Shared terminal-state guard for all state-machine transitions — terminal outcomes reject further transitions",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} =
  if o.phase == ppTerminal:
    errResult[ObligationOutcome]("cannot transition from terminal state")
  else:
    okResult(o)
```

**Signature:** `func assertNotTerminal*(o: ObligationOutcome): TransitionResult[ObligationOutcome]`
- Pure func (no side effects)
- Returns `errResult` with reason string when terminal, `okResult(o)` otherwise
- Has `{.axiomDecision(...)}` pragma with id `DECISION-0813`

**Test pattern:** `proof_state_machine_test.nim` does **not exist** in the codebase. There is no existing test for `assertNotTerminal`. A test would follow the pattern: construct a terminal `ObligationOutcome` (phase=ppTerminal, terminal=some(ptProved)), call `assertNotTerminal`, and assert the result is `errResult`.

---

## 11. proc→func Cap

**Current count:** `grep -rn "^proc " src/core/ | grep -v "test" | wc -l` = **898**

**Cap:** 950 procs in `src/core`

**Headroom:** 950 − 898 = **52 procs** remaining before the cap.

**`import core/trusted/axiom_pragmas_lite` usage:** Already widely used across the codebase. Confirmed in 37+ files including `proof_state_machine.nim`, `canonical_obligation_generator.nim`, `axiom_engine.nim`, `weaver.nim`, and many others. The file `core/trusted/axiom_pragmas_lite.nim` exists and is the lightweight re-export of pragma/type definitions intended for leaf files.

---

## Summary of Net-New Items for O9

| Item | Status |
|------|--------|
| `CanonicalEnvelopeDigest` | Net-new — no occurrences in `src/` |
| `TransportPayloadDigest` | Net-new — no occurrences in `src/` |
| `osrDroppedOutsideScope` | Net-new — not in `ObligationSkipReason` |
| `osrDroppedNoPlan` | Net-new — not in `ObligationSkipReason` |
| Per-invocation digest/ID | Net-new — no invocation-id or digest attached per `z3ExecPersistent` call |
| `smtScriptDigest` on obligation-derived script | Net-new for the obligation path — exists on `SolverInvocation` but not on the obligation-lowered SMT script |
| `proof_state_machine_test.nim` | Does not exist — no test for `assertNotTerminal` |
| `ObligationSieveResult` type | Does not exist — the `osr*` enum is `ObligationSkipReason` |
