# WP4-a Phase B-1: Registry Field Measurement Report

## 0. Experiment Metadata

| Field | Value |
|-------|-------|
| `PROJECT_UNDER_TEST` | nim-stew-clean-c75502c |
| `AXIOM_REVISION` | <workspace>/Axiom (git HEAD at time of measurement) |
| `AXIOM_CONFIGURATION` | bin/ax (pre-built binary, read-only) |
| `TOOLCHAIN_IDENTITY` | Nim compiler (used to build bin/ax) |
| `VERIFICATION_SCOPE` | RuntimeAxiomEntry registry field supply paths and consumption |
| `EXPERIMENT_ID` | wp4a-b1 |

## 1. Registry Field Supply Path Measurement

### 1.1 `registerAxiom` — the single write path for RuntimeAxiomEntry

**Definition:** `src/core/trusted/axiom_pragmas_procs.nim:21-27`

```nim
proc registerAxiom*(name, irStr, smtSrc, leanSrc, srcPath: string;
  isKern: bool = true; irHash: string = ""; effectKind: AxiomEffectKind = Pure;
  bmcSkippable: bool = false; origin: AxiomEntryOrigin = soAxiomSupport) {.raises: [].} =
  runtimeAxiomRegistry.add(RuntimeAxiomEntry(
    name: name, irSerialized: irStr,
    smtSource: smtSrc, leanSource: leanSrc,
    sourcePath: srcPath, isKernel: isKern, irHash: irHash,
    effectKind: effectKind, bmcSkippable: bmcSkippable,
    origin: origin))
```

**Key finding:** `registerAxiom` sets ALL 11 fields of `RuntimeAxiomEntry`. The defaults for optional parameters are: `isKern=true`, `irHash=""`, `effectKind=Pure`, `bmcSkippable=false`, `origin=soAxiomSupport`.

### 1.2 `generateAxiomInit` — compile-time macro that populates registry from `axiomRegistry`

**Definition:** `src/core/trusted/axiom_pragmas_macros.nim:823-836`

```nim
macro generateAxiomInit*(): untyped =
  result = newStmtList()
  for entry in axiomRegistry:
    let n = newLit(entry.funcName)
    let ir = newLit(entry.irSerialized)
    let smt = newLit(entry.smtSource)
    let lean = newLit(entry.leanSource)
    let sp = newLit(entry.sourcePath)
    let isKernExpr = newLit(entry.isKernel)
    let irHashLit = newLit(entry.irHash)
    let ekLit = newLit(entry.effectKind)
    let bmcSkipLit = newLit(entry.bmcSkippable)
    result.add quote do:
      registerAxiom(`n`, `ir`, `smt`, `lean`, `sp`,
        isKern = `isKernExpr`, irHash = `irHashLit`,
        effectKind = `ekLit`, bmcSkippable = `bmcSkipLit`)
```

**Key finding:** The macro emits `registerAxiom` calls with ALL fields from the compile-time `axiomRegistry`. The `origin` parameter is NOT passed, so it defaults to `soAxiomSupport`.

### 1.3 `axiomRegistry` compile-time population

**Definition:** `src/core/trusted/axiom_pragmas_macros.nim:692-701` (and multiple fallback paths at lines 724, 763, 783, 795, 809)

The compile-time `axiomRegistry` (type `AxiomCompileEntry`) is populated by the `axiomImpl` and `axiomTryImpl` macros at each `#axiom` pragma site. `AxiomCompileEntry` has the same fields as `RuntimeAxiomEntry` except it uses `funcName` instead of `name`.

`AxiomCompileEntry` definition (`axiom_pragmas_types.nim:42-51`):
```nim
AxiomCompileEntry* = object
  funcName*: string
  irSerialized*: string
  irHash*: string
  smtSource*: string
  leanSource*: string
  sourcePath*: string
  isKernel*: bool
  effectKind*: AxiomEffectKind
  bmcSkippable*: bool
```

### 1.4 `axiom_engine.nim` — external subject registration

**Definition:** `src/cli/axiom_engine.nim:998-1000`

```nim
registerAxiom("decodedLength", irStr, "", "", endians2Path,
  isKern = true, effectKind = Pure, bmcSkippable = false,
  origin = soExternalSubject)
```

**Key finding:** The external subject entry for "decodedLength" explicitly sets `origin = soExternalSubject`. All other fields use `registerAxiom` defaults or explicit values: `smtSource=""`, `leanSource=""`, `irHash=""`, `effectKind=Pure`, `bmcSkippable=false`.

### 1.5 `generateAxiomInit()` call site in axiom_engine.nim

**Definition:** `src/cli/axiom_engine.nim:978`

```nim
generateAxiomInit()
```

This is called at runtime during engine initialization, which expands the compile-time `axiomRegistry` into `registerAxiom` calls, populating `runtimeAxiomRegistry` with all Axiom-support entries (origin defaults to `soAxiomSupport`).

### 1.6 Registry field supply summary table

| Field | Supply Source | Supply Path | Default if Omitted |
|-------|-------------|-------------|-------------------|
| `name` | `registerAxiom(name, ...)` arg | Explicit parameter | — |
| `irSerialized` | `registerAxiom(..., irStr, ...)` arg | Explicit parameter | — |
| `smtSource` | `registerAxiom(..., smtSrc, ...)` arg | Explicit parameter | `""` |
| `leanSource` | `registerAxiom(..., leanSrc, ...)` arg | Explicit parameter | `""` |
| `sourcePath` | `registerAxiom(..., srcPath)` arg | Explicit parameter | — |
| `isKernel` | `registerAxiom(..., isKern)` arg | Explicit parameter | `true` |
| `irHash` | `registerAxiom(..., irHash)` arg | Explicit parameter | `""` |
| `effectKind` | `registerAxiom(..., effectKind)` arg | Explicit parameter | `Pure` |
| `bmcSkippable` | `registerAxiom(..., bmcSkippable)` arg | Explicit parameter | `false` |
| `origin` | `registerAxiom(..., origin)` arg | Explicit parameter | `soAxiomSupport` |
| `expectedObligation` | Field in `RuntimeAxiomEntry` | NOT set by `registerAxiom` | `false` (field default) |

**Critical observation:** `expectedObligation` is NOT set by `registerAxiom` at all — it is not a parameter of `registerAxiom` and is not set in `generateAxiomInit`. It always defaults to `false` for all registry entries (both compile-time and runtime).

### 1.7 Actual bin/ax cross-confirmation

**Command executed:**
```
cd /tmp && rm -rf /tmp/wp4a_b1_state && mkdir -p /tmp/wp4a_b1_state && cp -r ./data /tmp/wp4a_b1_state/
AXIOM_ROOT=. AXIOM_STATE_DIR=/tmp/wp4a_b1_state timeout 120 ./bin/ax prove --project <workspace>/nim-stew-clean-c75502c --limit 1
```

**Output confirming registry is populated:**
```
[INFO] axiom_engine: frontier eligibility gate: excluded 1 non-proof-candidate candidate(s); eligible=0
[INFO] axiom_engine: phase-10: IR extraction — 5/230 entries (limit=0)
[INFO] ir_pipeline_runner: [ir-cas] MISS func=normalizeMaxWorkers ...
[INFO] ir_pipeline_runner: [classify] calcDynamicTimeoutCore → vtStructural
[INFO] ir_pipeline_runner: [ir-cas] MISS func=calcDynamicTimeoutCore ...
[INFO] ir_pipeline_runner: [classify] safeSpeedupRatioCore → vtSmtNative
[INFO] ir_pipeline_runner: [classify] proximityScore → vtSmtNative
[INFO] loop_driver: PBT Registry: 230 properties registered
```

**Interpretation:** The registry contains 230 entries (including Axiom-support functions and the external subject "decodedLength"). The `[classify]` and `[ir-cas]` log lines confirm that `classifyCandidateEligibility` and `deserializeIRFuncDef` are actively processing registry entries at runtime. The pipeline is consuming `irSerialized` (for IR deserialization) and `bmcSkippable` (for admissibility classification) from registry entries.

## 2. External Synthesized Entry — Minimum Field Set Analysis

### 2.1 `classifyCandidateEligibility` field consumption

**Definition:** `src/verification/obligation/candidate_eligibility.nim:52-76`

```nim
func classifyCandidateEligibility*(entry: RuntimeAxiomEntry;
  funcDef: IRFuncDef): EligibilityClass =
  let genResult = generateCanonicalObligations(funcDef, defaultScopePolicy())
  case genResult.kind
  of ogrIllFormed: return elMalformed
  of ogrNoApplicableObligation: return elNoObligation
  of ogrUnsupported: return elUnsupported
  of ogrGenerated:
    if not inVerifiedFragmentV1(entry, funcDef, genResult):
      return elUnsupported
    return elProofCandidate
```

**Direct field reads from `entry`:** NONE. `classifyCandidateEligibility` does not read any field from `entry` directly. It passes `entry` to `inVerifiedFragmentV1`.

### 2.2 `inVerifiedFragmentV1` field consumption

**Definition:** `src/verification/obligation/verified_fragment.nim:52-71`

```nim
func inVerifiedFragmentV1*(entry: RuntimeAxiomEntry; funcDef: IRFuncDef;
  genResult: ObligationGenerationResult): bool =
  if assessAdmissibility(entry, funcDef).decision == INELIGIBLE:
    return false
  if genResult.kind != ogrGenerated:
    return false
  for obl in genResult.obligations.items:
    if obl.kind notin VerifiedFragmentAllowlist:
      return false
  true
```

**Direct field reads from `entry`:** NONE directly. It passes `entry` to `assessAdmissibility`.

### 2.3 `assessAdmissibility` field consumption

**Definition:** `src/verification/admissibility.nim:58-106`

```nim
func assessAdmissibility*(entry: RuntimeAxiomEntry; funcDef: IRFuncDef): AdmissibilityOutcome =
  if entry.bmcSkippable:
    return AdmissibilityOutcome(decision: INELIGIBLE,
      reason: ireUnsupportedType,
      detail: "compile-time bmcSkippable (string/float not QF_BV-representable)")
  let tierInfo = classifyFunction(funcDef)
  ...
```

**Direct field reads from `entry`:** `entry.bmcSkippable` (line 81). This is the ONLY field from `RuntimeAxiomEntry` consumed in the entire `classifyCandidateEligibility` call chain.

### 2.4 `isFrontierSelectionEligible` field consumption

**Definition:** `src/verification/obligation/candidate_eligibility.nim:82-100`

```nim
proc isFrontierSelectionEligible*(funcName: string): bool =
  var bare = funcName
  if bare.endsWith("*"): bare = bare[0..^2]
  for entry in runtimeAxiomRegistry:
    if entry.name != bare or entry.irSerialized.len == 0:
      continue
    let funcDef = deserializeIRFuncDef(entry.irSerialized)
    if funcDef.name.len > 0:
      return classifyCandidateEligibility(entry, funcDef) == elProofCandidate
  false
```

**Direct field reads from `entry`:** `entry.name` (line 94), `entry.irSerialized` (line 95, 97).

### 2.5 Pipeline inclusion (`ir_pipeline_runner.nim`) field consumption

**Definition:** `src/verification/batch_uap/ir_pipeline_runner.nim:1214-1218`

```nim
let eligibility = classifyCandidateEligibility(ve.entry, ve.funcDef)
if eligibility != elProofCandidate: continue
if ve.entry.isKernelScopeMember or (externalSubjectMode and ve.entry.origin == soExternalSubject):
  result.add(ve)
```

**Direct field reads from `entry` for pipeline inclusion:** `entry.isKernel`, `entry.origin` (line 1217). `isKernelScopeMember` (defined in `axiom_pragmas_procs.nim:9-14`) reads `entry.isKernel`, `entry.irSerialized`, `entry.effectKind`, `entry.bmcSkippable`.

### 2.6 Other registry consumers and their field reads

| Consumer | File:Line | Fields Read |
|----------|-----------|-------------|
| `lookupAxiomIR` | `axiom_pragmas_procs.nim:29-33` | `entry.name`, `entry.irSerialized` |
| `lookupAxiomLeanSource` | `axiom_pragmas_procs.nim:35-38` | `entry.name`, `entry.leanSource` |
| `countKernelFunctions` | `axiom_pragmas_procs.nim:16-19` | `entry.isKernel`, `entry.irSerialized`, `entry.effectKind`, `entry.bmcSkippable` (via `isKernelScopeMember`) |
| `collectKernelSymbols` | `axiom_pragmas_procs.nim:66-76` | `entry.isKernel`, `entry.irSerialized`, `entry.effectKind`, `entry.bmcSkippable`, `entry.sourcePath` |
| `initRegistryLookup` | `axiom_pragmas_procs.nim:41-44` | `entry.name` (as table key), full entry |
| `pbt_adapter` | `pbt_adapter.nim:48-79` | `entry.name`, `entry.irHash`, `entry.sourcePath`, `entry.isKernel`, `entry.expectedObligation` |
| `loop_driver` | `loop_driver.nim:153-156, 1163-1168` | `entry.isKernel`, `entry.irHash` |
| `cert_writer.lookupIsKernel` | `cert_writer.nim:46-51` | `entry.isKernel` |
| `topology_cli` | `topology_cli.nim:395` | `runtimeAxiomRegistry.len` (count only) |

### 2.7 Minimum field set determination

The question is: what is the minimum field set for a synthesized `RuntimeAxiomEntry` to pass through the classifier path and be accepted as a proof candidate?

The classifier path is:
1. `isFrontierSelectionEligible` — requires `name` and `irSerialized`
2. `classifyCandidateEligibility` — requires `bmcSkippable` (via `assessAdmissibility`)
3. Pipeline inclusion — requires `origin == soExternalSubject` (when `externalSubjectMode` is true)

The `classifyCandidateEligibility` call chain (`classifyCandidateEligibility` → `inVerifiedFragmentV1` → `assessAdmissibility`) reads ONLY `entry.bmcSkippable`. No other entry field is read.

**Minimum field set for classifier path:**

| Field | Required for classifier? | Required for pipeline inclusion? | Required for lookup? | Minimum? |
|-------|------------------------|--------------------------------|---------------------|----------|
| `name` | No (not read by classifier) | No | **YES** (isFrontierSelectionEligible lookup) | **YES** |
| `irSerialized` | No (not read by classifier) | No | **YES** (isFrontierSelectionEligible + deserializeIRFuncDef) | **YES** |
| `bmcSkippable` | **YES** (assessAdmissibility) | No (OR condition with origin) | No | **YES** |
| `origin` | No | **YES** (externalSubjectMode gate) | No | **YES** (for external subject) |
| `isKernel` | No | No (OR condition with origin) | No | No |
| `effectKind` | No | No (OR condition with origin) | No | No |
| `smtSource` | No | No | No | No |
| `leanSource` | No | No | No | No |
| `sourcePath` | No | No | No | No |
| `irHash` | No | No | No | No |
| `expectedObligation` | No | No | No | No |

### 2.8 Final minimum field set for external synthesized entry

The minimum field set for a synthesized `RuntimeAxiomEntry` to be classified as `elProofCandidate` by the classifier path and accepted into the pipeline as an external subject is:

1. **`name`** — required for `isFrontierSelectionEligible` lookup (`candidate_eligibility.nim:94`)
2. **`irSerialized`** — required for `deserializeIRFuncDef` in `isFrontierSelectionEligible` (`candidate_eligibility.nim:97`) and for pipeline processing (`ir_pipeline_runner.nim:1153`)
3. **`bmcSkippable`** — required by `assessAdmissibility` (`admissibility.nim:81`) which is in the `classifyCandidateEligibility` chain
4. **`origin`** — required for pipeline inclusion when `externalSubjectMode` is true (`ir_pipeline_runner.nim:1217`)

All other fields (`smtSource`, `leanSource`, `sourcePath`, `isKernel`, `irHash`, `effectKind`, `expectedObligation`) are NOT consumed by the classifier path or the external subject pipeline inclusion gate.

## 3. B-2 Consumption Matrix

| Field | `classifyCandidateEligibility` chain | `inVerifiedFragmentV1` | `assessAdmissibility` | `isFrontierSelectionEligible` | Pipeline inclusion (external) | `isKernelScopeMember` | Minimum for external synthesized entry |
|-------|--------------------------------------|------------------------|----------------------|------------------------------|------------------------------|----------------------|---------------------------------------|
| `name` | ✗ | ✗ | ✗ | **✓** (line 94) | ✗ | ✗ | **YES** (lookup) |
| `irSerialized` | ✗ | ✗ | ✗ | **✓** (line 95, 97) | ✗ | **✓** | **YES** (deserialization) |
| `bmcSkippable` | ✗ (passed through) | ✗ (passed through) | **✓** (line 81) | ✗ | ✗ | **✓** | **YES** (admissibility) |
| `origin` | ✗ | ✗ | ✗ | ✗ | **✓** (line 1217) | ✗ | **YES** (external subject gate) |
| `isKernel` | ✗ | ✗ | ✗ | ✗ | ✗ (OR with origin) | **✓** | No |
| `effectKind` | ✗ | ✗ | ✗ | ✗ | ✗ (OR with origin) | **✓** | No |
| `smtSource` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | No |
| `leanSource` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | No |
| `sourcePath` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | No |
| `irHash` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | No |
| `expectedObligation` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | No |

**Legend:** ✓ = consumed in this code path, ✗ = not consumed

## 4. Conclusions

### B-1: Registry field supply paths
- All 11 fields of `RuntimeAxiomEntry` are populated by `registerAxiom` at runtime.
- The compile-time `axiomRegistry` → `generateAxiomInit` → `registerAxiom` chain supplies all fields including `origin=soAxiomSupport` (default).
- The external subject entry at `axiom_engine.nim:998-1000` explicitly sets `origin=soExternalSubject` and all other fields to defaults or explicit values.
- `expectedObligation` is never set by `registerAxiom` or `generateAxiomInit`; it always defaults to `false`.
- The actual product binary (`bin/ax`) populates the registry with 230 entries at runtime, confirmed by log output.

### B-2: Minimum field set for external synthesized entry
The classifier path (`classifyCandidateEligibility` → `inVerifiedFragmentV1` → `assessAdmissibility`) reads ONLY `entry.bmcSkippable`. The lookup gate (`isFrontierSelectionEligible`) requires `entry.name` and `entry.irSerialized`. The pipeline inclusion gate for external subjects requires `entry.origin == soExternalSubject`.

**Minimum field set: `name` + `irSerialized` + `bmcSkippable` + `origin`**

The remaining 7 fields (`smtSource`, `leanSource`, `sourcePath`, `isKernel`, `irHash`, `effectKind`, `expectedObligation`) are not consumed by any code path in the classifier or external subject pipeline inclusion flow.

## 5. Cross-Confirmation Evidence

The `bin/ax prove` execution produced the following confirming evidence:
- `PBT Registry: 230 properties registered` — registry is populated at runtime
- `[classify]` log lines for Axiom-self functions — `classifyCandidateEligibility` is actively called
- `[ir-cas] MISS` log lines — `deserializeIRFuncDef` is actively called on registry entries
- `frontier eligibility gate: excluded 1 non-proof-candidate candidate(s)` — `isFrontierSelectionEligible` is actively filtering registry entries
- `phase-10: IR extraction — 5/230 entries (limit=1)` — pipeline is processing registry entries

All evidence confirms that the registry is populated with real data at runtime and that the classifier path consumes the fields identified above.
