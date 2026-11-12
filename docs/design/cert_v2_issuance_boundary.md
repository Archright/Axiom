# Cert V2 Issuance Boundary — Design Document

**Status**: Proposal  
**Author**: Design agent  
**Date**: 2026-08-13  
**Related**: `docs/spec/cfg_contract_specification.md`, DECISION-0605 (CertificateIdentity), DECISION-0628 (writeCertificateFromUapResult)

---

## 1. Gap Map — Where Postcondition P Is Available vs. Discarded

The postcondition spec formula `P` (a `seq[string]` of SMT-LIB2 assertions) is synthesized at Stage 0b but dropped before the certificate writer. Below is the exact trace.

### 1.1 Synthesis (P exists)

| Step | File | Line | What happens |
|------|------|------|-------------|
| S1 | `src/core/trusted/contract_synthesis.nim` | 306 | `func synthesizeContracts*(funcDef: var IRFuncDef)` populates `funcDef.postConditions: seq[string]` via `collectPostconditions(funcDef)` |
| S2 | `src/verification/batch_uap/ir_pipeline_runner.nim` | 351 | `synthesizeContracts(funcDef)` is called inside `runIrPipeline`. The `funcDef.postConditions` field is now populated. |
| S3 | `src/verification/batch_uap/ir_pipeline_runner.nim` | 355 | `contractFromFuncDef(funcDef)` reads `funcDef.postConditions` (line 322) and passes it to the CHC bridge — **P is consumed here for SMT/Lean verification** |

### 1.2 Drop Point 1 — IrPipelineResult

| Step | File | Line | What happens |
|------|------|------|-------------|
| D1 | `src/verification/batch_uap/ir_pipeline_runner.nim` | 81–102 | `IrPipelineResult*` object definition — **no `postConditions` field exists**. All construction sites (lines 336, 374, 420, 448, 473, 509, 539, 586, 612, 641, 664, 694, 729, 761, 783, 798) omit postConditions entirely. |

**Consequence**: Even though `funcDef.postConditions` is populated at S2, the `IrPipelineResult` that carries the pipeline outcome forward has no field to hold it. The spec is lost at the boundary between `runIrPipeline` and every downstream consumer.

### 1.3 Drop Point 2 — FinalReportCertInput

| Step | File | Line | What happens |
|------|------|------|-------------|
| D2 | `src/verification/batch_uap/stages.nim` | 59–69 | `FinalReportCertInput*` object definition — **no spec/formula field exists** (fields: `status, modulePath, functionName, sourceCode, kernelVerified, smtlib2, solverStatus, vacuityProven, irHash`). |
| D3 | `src/verification/batch_uap/stages.nim` | 449–459 | `buildFinalNodeReport` constructs `FinalReportCertInput` — **does not pass any postConditions or spec formula**. The `uapReq.postConditions` (available from `UniversalPipelineRequest`, pipeline_core_types.nim:176) is never forwarded. |

### 1.4 Drop Point 3 — writeCertificateFromUapResult Call Sites

| Step | File | Line | What happens |
|------|------|------|-------------|
| D4 | `src/verification/batch_uap/loop_driver.nim` | 854 | `writeCertificateFromUapResult(...)` called with `leanProposition=""` (default parameter value, cert_writer.nim:364). |
| D5 | `src/verification/batch_uap/loop_depth_scheduler.nim` | 511 | Same — `writeCertificateFromUapResult(...)` called with `leanProposition=""` (default). |

### 1.5 Drop Point 4 — CertificateIdentity Fields Never Populated

| Step | File | Line | What happens |
|------|------|------|-------------|
| D6 | `src/core/trusted/private/evidence_identity.nim` | 14–51 | `CertificateIdentity*` has `propertyFormula: string`, `smtHash: string`, `smtOrigin: string` fields — **but they are never populated with the spec P**. In `cert_writer.nim:422–428`, `CertificateIdentity` is constructed with `formula: leanProposition` (which is `""`), and `smtHash`/`smtOrigin` are not set at all. |

### 1.6 Existing `specOrigin` Field (for reference)

The `specOrigin` field on `CertificateIdentity` (evidence_identity.nim:22) is a `string` that is part of the identity digest computation (line 42). It is currently always empty in practice because no code path populates it. The `evidence_calculus.nim:69–72` `EvidenceBundle` type reuses `CertificateEvidence` as its canonical base (P0 type) but does not add spec-provenance fields.

---

## 2. Proposal: Certificate V2 with Spec Provenance

### 2.1 New Fields

Add to `CertificateIdentity` (evidence_identity.nim:14):

```nim
type
  CertificateIdentity* {.axiomDecision(...).} = object
    formula*: string                       # legacy formula (kept for backward compat)
    schemaVersion*: string                 # "2" for CertV2
    functionId*: string
    specOrigin*: string                    # provenance: e.g. "synthesizeContracts@contract_synthesis.nim:306"
    propertyFormula*: string               # serialized postcondition P (the spec)
    sourceHash*: string
    irHash*: string
    smtHash*: string
    translationVersion*: string
    solverIdentity*: string
    proofArtifactDigest*: string
```

Add to `IrPipelineResult` (ir_pipeline_runner.nim:81):

```nim
  IrPipelineResult* = object
    # ... existing fields ...
    complexity*: float
    postConditions*: seq[string]           # <-- NEW: carry synthesized spec forward
```

Add to `FinalReportCertInput` (stages.nim:59):

```nim
  FinalReportCertInput* = object
    status*: OrchestrationNodeStatus
    modulePath*: string
    functionName*: string
    sourceCode*: string
    kernelVerified*: bool
    smtlib2*: string
    solverStatus*: string
    vacuityProven*: bool
    irHash*: string
    specFormula*: string                   # <-- NEW: serialized postcondition P
    specOrigin*: string                    # <-- NEW: provenance trace
```

### 2.2 Minimal Welding

#### Step A — Capture postConditions in IrPipelineResult

**File**: `src/verification/batch_uap/ir_pipeline_runner.nim`

1. Add `postConditions*: seq[string]` field to `IrPipelineResult` at line 102 (after `complexity*`).
2. After `synthesizeContracts(funcDef)` at line 351, capture the result into every `IrPipelineResult` construction site:
   - Add `postConditions: funcDef.postConditions` to each `IrPipelineResult(...)` literal (lines 336, 374, 420, 448, 473, 509, 539, 586, 612, 641, 664, 694, 729, 761, 783, 798).

#### Step B — Thread through UniversalPipelineRequest → UniversalPipelineResult

`UniversalPipelineRequest` (pipeline_core_types.nim:176) already has `postConditions*: seq[string]`.  
`UniversalPipelineResult` (universal_pipeline_contract.nim:294) already has `postConditions*: seq[string]`.

No change needed here — the types already support it. The gap is that `IrPipelineResult.postConditions` is not wired into `uapReq.postConditions` / `uapOutput.postConditions` in the loop_driver and loop_depth_scheduler paths.

In `loop_driver.nim` and `loop_depth_scheduler.nim`, when constructing `BudgetedPayload` / `ParallelNodeResult` from `IrPipelineResult`, forward `irResult.postConditions` into `uapReq.postConditions` (or `uapOutput.postConditions`).

#### Step C — Thread through buildFinalNodeReport → FinalReportCertInput

**File**: `src/verification/batch_uap/stages.nim`

1. Add `specFormula*: string` and `specOrigin*: string` to `FinalReportCertInput` (after line 68).
2. In `buildFinalNodeReport` (line 449–459), add:
   ```nim
   specFormula: uapReq.postConditions.join("\n"),
   specOrigin: "synthesizeContracts@contract_synthesis.nim:306",
   ```

#### Step D — Thread through writeCertificateFromUapResult

**File**: `src/verification/cert_writer.nim`

1. Add `specFormula: string = ""` and `specOrigin: string = ""` parameters to `writeCertificateFromUapResult` (after line 364, alongside `leanProposition`).
2. In the cert JSON construction (around line 420), when `schemaVersion == "2"`:
   ```nim
   certJson["specFormula"] = %(specFormula)
   certJson["specOrigin"] = %(specOrigin)
   ```
3. In `CertificateIdentity` construction (line 422–428), populate:
   ```nim
   propertyFormula: specFormula,
   specOrigin: specOrigin,
   ```

#### Step E — Update call sites

**File**: `src/verification/batch_uap/loop_driver.nim` (line 854)
**File**: `src/verification/batch_uap/loop_depth_scheduler.nim` (line 511)

Pass `specFormula` and `specOrigin` from `certInput` to `writeCertificateFromUapResult`:
```nim
writeCertificateFromUapResult(
  certDir,
  proven.certInput.modulePath,
  proven.certInput.functionName,
  proven.certInput.sourceCode,
  proven.certInput.kernelVerified,
  proven.certInput.smtlib2,
  proven.certInput.solverStatus,
  certLogLines,
  proven.certInput.vacuityProven,
  irHash = irHash,
  specFormula = proven.certInput.specFormula,
  specOrigin = proven.certInput.specOrigin,
  negativeTestResult = false
)
```

### 2.3 Thread Safety

All additions are value types (`seq[string]`, `string`). `IrPipelineResult` is already a value type (not `ref`). `FinalReportCertInput` is a value type. The `writeCertificateFromUapResult` calls happen on the main thread (single-threaded vault I/O, as noted in loop_driver.nim:849 and loop_depth_scheduler.nim:506). No shared mutable state is introduced.

---

## 3. Legacy / Staleness Rule

### 3.1 Classification Table

When loading a certificate, inspect `schemaVersion`:

| `schemaVersion` | Classification | Behavior |
|-----------------|---------------|----------|
| `"2"` | **CertV2** — spec-carrying | Full processing: `propertyFormula` and `specOrigin` are read, identity digest includes spec provenance, promotion basis is valid. |
| `"1"` (or absent) | **CertV1 / Legacy** — no spec | Readable but **not a promotion basis**. `propertyFormula` is empty or legacy `formula` field. `specOrigin` is absent. These certs can be inspected but cannot serve as the spec-provenance anchor for V2 promotion. |
| Missing key | **Corrupt / Unknown** | Treat as V1 legacy (readable, not promotable). |

### 3.2 Load-Path Classification

In the cert loader (`cert_writer.nim` or a new `cert_loader.nim`):

```nim
func classifyCertVersion*(certJson: JsonNode): CertVersion =
  let sv = certJson.get["schemaVersion"].getStr("")
  if sv == "2":
    result = cvV2
  elif sv == "1" or sv == "":
    result = cvLegacy   # csbNotCurrent for promotion purposes
  else:
    result = cvUnknown  # treat as legacy
```

- **`cvV2`**: Full spec-provenance path active. `propertyFormula` and `specOrigin` are populated from the cert JSON.
- **`cvLegacy`**: Cert is readable for audit/inspection. `propertyFormula` falls back to legacy `formula` field (evidence_identity.nim:19). **Not a promotion basis** — any attempt to promote from a V1 cert must re-synthesize the spec from source.
- **`cvUnknown`**: Same as `cvLegacy` but logged as a warning (potential schema drift).

### 3.3 `csbNotCurrent` Semantics

`csbNotCurrent` (Certificate Status Base — not current) means:
- The cert is **not rejected** — it remains readable and valid for its original verification purpose.
- It is **excluded** from any path that requires spec-provenance anchoring (e.g., V2 promotion, spec-delta comparison, provenance chain extension).
- A V1 cert can be re-issued as V2 by re-running the pipeline (which will synthesize the spec again at Stage 0b and carry it forward through the new CertV2 path).

---

## 4. Summary of Changes (File:Line)

| Change | File | Line(s) |
|--------|------|---------|
| Add `postConditions` to `IrPipelineResult` | `src/verification/batch_uap/ir_pipeline_runner.nim` | 102 |
| Populate `postConditions` in all `IrPipelineResult` construction sites | `src/verification/batch_uap/ir_pipeline_runner.nim` | 336, 374, 420, 448, 473, 509, 539, 586, 612, 641, 664, 694, 729, 761, 783, 798 |
| Add `specFormula` + `specOrigin` to `FinalReportCertInput` | `src/verification/batch_uap/stages.nim` | 68 |
| Pass spec fields in `buildFinalNodeReport` | `src/verification/batch_uap/stages.nim` | 449–459 |
| Add `specFormula` + `specOrigin` params to `writeCertificateFromUapResult` | `src/verification/cert_writer.nim` | 364 |
| Write spec fields into cert JSON + CertificateIdentity | `src/verification/cert_writer.nim` | 420–428 |
| Pass spec fields at call site 1 | `src/verification/batch_uap/loop_driver.nim` | 854 |
| Pass spec fields at call site 2 | `src/verification/batch_uap/loop_depth_scheduler.nim` | 511 |
| Add `schemaVersion` field to `CertificateIdentity` | `src/core/trusted/private/evidence_identity.nim` | 20 (already exists, set to `"2"` for V2) |
| Add `specOrigin` population in `CertificateIdentity` construction | `src/verification/cert_writer.nim` | 422–428 |
| Add `postConditions` to `UniversalPipelineResult` (already exists) | `src/core/contracts/universal_pipeline_contract.nim` | 294 (no change needed) |
| Add `postConditions` to `UniversalPipelineRequest` (already exists) | `src/core/types/pipeline_core_types.nim` | 176 (no change needed) |
| Add load-path classification for `schemaVersion` | `src/verification/cert_writer.nim` (or new `cert_loader.nim`) | new |

---

## 5. References

- `contract_synthesis.nim:306` — `synthesizeContracts` populates `funcDef.postConditions`
- `ir_pipeline_runner.nim:351` — calls `synthesizeContracts(funcDef)` but drops result
- `ir_pipeline_runner.nim:81–102` — `IrPipelineResult` lacks `postConditions`
- `stages.nim:59–69` — `FinalReportCertInput` lacks spec field
- `stages.nim:449–459` — `buildFinalNodeReport` doesn't pass spec
- `loop_driver.nim:854` — `writeCertificateFromUapResult` with `leanProposition=""`
- `loop_depth_scheduler.nim:511` — same
- `evidence_identity.nim:14–51` — `CertificateIdentity` has `propertyFormula`/`smtHash`/`smtOrigin` but never populated
- `cert_writer.nim:353–366` — `writeCertificateFromUapResult` signature
- `cert_writer.nim:421` — writes `schemaVersion = "1"`
- `evidence_calculus.nim:69–72` — `EvidenceBundle` reuses `CertificateEvidence` (P0 canonical base)
- `pipeline_core_types.nim:176` — `UniversalPipelineRequest.postConditions` (already exists)
- `universal_pipeline_contract.nim:294` — `UniversalPipelineResult.postConditions` (already exists)
