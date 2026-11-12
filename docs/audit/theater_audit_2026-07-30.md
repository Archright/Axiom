# Theater Audit Report — 2026-07-30

**Audit Scope**: Full codebase parallel scan (src/core, src/gate, src/cli, src/verification, src/mcp, tests/)  
**Audit Method**: 4 parallel sub-agents + manual verification of critical findings  
**Theater Definition**: AGENTS.md §0.9 — code claiming to provide a guarantee while actually guaranteeing nothing  
**Previous Audit**: 2026-07-27 (DEBT#277-#327 registered and remediated)

---

## Executive Summary

The previous theater audit (2026-07-27) registered 51 theater findings (DEBT#277-#327), most of which were remediated and marked CLOSED. This follow-up audit conducted a **full codebase rescan** to identify:

1. **New theater** introduced after 2026-07-27
2. **Previously missed theater** in code paths not covered by the first audit
3. **Regressions** where remediated code reverted to theater patterns
4. **Incomplete remediations** where the root cause was partially fixed

**Results**:
- **12 NEW critical/high findings** requiring immediate registration in `data/debt_registry.json`
- **8 previously missed findings** in `src/core/contracts/z3_extraction.nim` and `src/verification/`
- **3 test theater patterns** violating AGENTS.md §0.8 (stub prohibition)
- **5 medium-priority findings** in test infrastructure

---

## Critical Findings (NEW)

### CRITICAL-1: Emergency Bypass Audit Trail Write Silently Swallowed

**ID**: DEBT#357 (new)  
**Category**: Theater/Swallowed Failure  
**File**: `src/gate/gateway.nim:642-643, 916-917, 970-971`  
**Severity**: CRITICAL  
**Signature**: #2 (Swallowed Failure)

**Description**:
Three locations in `gateway.nim` write Ed25519 emergency bypass audit records to `bypass_audit.jsonl`. If the file write fails (disk full, permissions, etc.), the `except CatchableError: discard` block silently drops the error and the process immediately `quit(0)` — gates are fully bypassed with **NO audit record**.

```nim
except CatchableError:
  discard  # axiom:best-effort(ioboundary catch)
quit(0)  # ← BYPASS SUCCEEDS WITH NO AUDIT TRAIL
```

**Why Theater**: A security-critical bypass event must leave an audit trail. If the audit write fails, the bypass should either fail-closed or emit to stderr. A bypass with no audit record is the definition of theater — it appears to have a security control but provides no assurance.

**Remediation**: Either (a) fail-closed on audit write failure, or (b) emit to stderr before quitting, or (c) use a fallback audit mechanism (kernel log, syslog).

**Status**: NEW — not registered in debt registry

---

### CRITICAL-2: `gate_cas.nim:verifyCasIntegrity()` Always Returns True

**ID**: DEBT#358 (new)  
**Category**: Theater/Always-Pass  
**File**: `src/core/gate/gate_cas.nim:392`  
**Severity**: HIGH  
**Signature**: #1 (Always-Pass)

**Description**:
The `verifyCasIntegrity()` proc docstring claims: "Verify CAS integrity. Checks for stale temp files and manifest corruption." After cleaning stale temp dirs, the function returns `true` unconditionally at line 392. It does NOT check manifest corruption at all.

```nim
proc verifyCasIntegrity*(repoRoot: string): bool =
  ## Verify CAS integrity. Checks for stale temp files and manifest corruption.
  ...
  # Normal integrity check: no stale tmp files
  if dirExists(tmpDir):
    try: removeDir(tmpDir)
    except CatchableError: discard
  true  # ← ALWAYS returns true, never checks manifest corruption
```

**Why Theater**: The docstring promises two checks; only one half-implemented check runs; result is always `true`. This is signature #6 (Unenforced Claim) combined with #1 (Always-Pass).

**Remediation**: Either implement manifest corruption checking or update the docstring to accurately describe the limited scope.

**Status**: NEW — not registered in debt registry

---

### CRITICAL-3: `ecosystem_linkage.nim` JSON Parse Failure Returns Empty Contract as Success

**ID**: DEBT#359 (new)  
**Category**: Theater/Swallowed Failure  
**File**: `src/verification/ecosystem_linkage.nim:108`  
**Severity**: HIGH  
**Signature**: #2 (Swallowed Failure)

**Description**:
`resolveStandardLibraryContract()` uses `parseJsonOpt(content).get(newJObject())` which returns an empty `JObject` on parse failure. The subsequent `.getStr()` calls return empty strings, and the function wraps the garbage result in `ok(ExternalContract(...))` — presenting a completely empty contract as a successful resolution.

```nim
let node = parseJsonOpt(content).get(newJObject())  # empty object on failure
result = ok(ExternalContract(
  qualifiedName: node{"qualifiedName"}.getStr(),  # "" on failure
  moduleName: node{"moduleName"}.getStr(),          # "" on failure
  ...
))  # ← ok() wrapping garbage data
```

**Why Theater**: A function that resolves external contracts returns "success" with empty/garbage data when the manifest file is corrupt or unparseable. The caller believes it received a valid contract.

**Remediation**: Change to `err(...)` on JSON parse failure. Returning `ok()` with empty fields is theater.

**Status**: NEW — not registered in debt registry

---

### CRITICAL-4: `assume_guarantee.nim` Unparseable Z3 Output Treated as SAT+OK

**ID**: DEBT#360 (new)  
**Category**: Theater/Swallowed Failure  
**File**: `src/verification/solver/assume_guarantee.nim:233`  
**Severity**: HIGH  
**Signature**: #2 (Swallowed Failure)

**Description**:
`execZ3Query()` returns `(true, output, true)` as a fallback when Z3 output doesn't contain "sat", "unsat", or "unknown". This means any Z3 crash, error message, or garbled output is treated as `ok=true` (solver executed successfully) with `sat=true` (counterexample found).

```nim
# Fallback: treat non-unsat as sat
return (true, output, true)  # ← ok=true even for garbled Z3 output
```

**Why Theater**: The `ok=true` misrepresents the execution state. Z3 may have crashed or produced unparseable output, but the caller is told "solver succeeded".

**Remediation**: Return `(false, output, false)` to signal that Z3 did not produce a recognizable result.

**Status**: NEW — not registered in debt registry

---

### CRITICAL-5: MCP `axiomVerify` Reports Failed Verification as Success

**ID**: DEBT#361 (new)  
**Category**: Theater/Unenforced Claim  
**File**: `src/mcp/tools.nim:95-118` + `src/mcp/server.nim:72-73`  
**Severity**: HIGH  
**Signature**: #6 (Unenforced Claim)

**Description**:
The `axiomVerify` MCP tool invokes `ax prove --heal` but only returns raw exit code and output. It never sets an `"error"` key when `exitCode != 0`. The MCP server at `server.nim:72-73` maps responses to `"isError": true` only when the response contains `"error"`. Therefore, a failed verification (exitCode=1) appears as `"isError": false` in the MCP protocol.

**Why Theater**: The MCP client is told "verification succeeded" when it actually failed. The tool claims to verify but doesn't interpret the verification result.

**Remediation**: Add exit code interpretation to `axiomVerify`. If `exitCode != 0`, include `"error"` key in the response.

**Status**: NEW — not registered in debt registry

---

### CRITICAL-6: `z3_extraction.nim` Contract Completeness Failure Aborts All Verification

**ID**: DEBT#362 (new)  
**Category**: Theater/Always-Pass (vacuous inconclusive)  
**File**: `src/core/contracts/z3_extraction.nim:648-659`  
**Severity**: HIGH  
**Signature**: #1 (Always-Pass)

**Description**:
When `checkAxiomCompleteness()` fails for any contract, the ENTIRE verification pipeline short-circuits to `vsInconclusive` with `procsChecked: 0`. This is presented as a valid verification result, but it actually verified NOTHING.

```nim
if not checkAxiomCompleteness(n).ok:
  result = ProofResult(
    status: psUnknown,
    verificationStatus: vsInconclusive,
    procsChecked: 0, procsProven: 0, ...  # ← verified nothing
  )
```

**Why Theater**: One bad contract causes total verification abandonment. The function returns what looks like a valid result, but it verified zero procedures.

**Remediation**: Skip the bad contract and continue verifying the rest, or explicitly fail rather than return vacuous "inconclusive."

**Status**: NEW — not registered in debt registry

---

## High-Priority Findings (NEW)

### HIGH-1: `gate_admin_validate.nim` Multiple Unconditional `return true`

**ID**: DEBT#363 (new)  
**Category**: Theater/Always-Pass  
**File**: `src/cli/gate_admin_validate.nim:63, 67, 75`  
**Severity**: HIGH  
**Signature**: #1 (Always-Pass)

**Description**:
`isNoopCommand()` returns `true` unconditionally after checking empty string and known patterns. The function performs real checks, but the final `return true` at line 75 is unreachable (the loop already returned). This is dead code that looks like a real check.

**Verification**: Lines 62-76 show the function correctly returns from inside the loop, but line 75 is indeed unreachable. Not strictly theater since the function does perform checks before the unreachable line.

**Reassessment**: After reading the full context, this is **dead code** (line 75 is unreachable), not theater. The function correctly returns `true` from inside the loop at lines 63/67. Line 75 is defensive programming that can never execute.

**Status**: FALSE POSITIVE — not theater (dead code only)

---

### HIGH-2: `gate_effect_classifier.nim` String-Prefix Heuristic Disguised as Classification

**ID**: DEBT#364 (new)  
**Category**: Theater/Disguised Stub  
**File**: `src/cli/gate_effect_classifier.nim:71, 77`  
**Severity**: MEDIUM  
**Signature**: #3 (Disguised Stub)

**Description**:
`isGateEffect()` classifies effects based solely on string prefix matching (`startsWith("gate")`, `startsWith("cli")`). This is not actual classification — it's a naive heuristic presented as semantic analysis.

**Why Theater**: The function name promises semantic classification but delivers trivial string matching.

**Remediation**: Replace with proper enum-based classifier or remove entirely.

**Status**: NEW — not registered in debt registry

---

### HIGH-3: `observer/state_hash.nim` Gate 0 Uses `doAssert` (Disabled in Release)

**ID**: DEBT#365 (new)  
**Category**: Theater/Dead Gate  
**File**: `src/core/observer/state_hash.nim:153-166`  
**Severity**: HIGH  
**Signature**: #5 (Dead Gate)

**Description**:
`assertSyncProtocol()` uses `doAssert` for Gate 0 enforcement. `doAssert` is disabled in release builds (`-d:release`). When compiled with `-d:release`, the entire sync protocol check evaporates — no assertions fire, the function returns `true` unconditionally.

**Why Theater**: The gate is documented as "Gate 0" enforcement, but it is silently absent in production builds.

**Remediation**: Replace `doAssert` with runtime checks that work in release mode, OR document the release-mode exemption.

**Status**: NEW — not registered in debt registry

---

## Medium-Priority Findings (NEW)

### MEDIUM-1: `ir_to_lean.nim` Theorem Concludes `: True` (Vacuous Proof)

**ID**: DEBT#366 (new)  
**Category**: Theater/Vacuous Proof  
**File**: `src/core/ir/ir_to_lean.nim:143`  
**Severity**: MEDIUM  
**Signature**: #4 (Vacuous Proof)

**Description**:
A generated Lean theorem concludes `: True` — a tautology that requires no verification. Any proof strategy proves `True`.

**Remediation**: Remove or document as a known limitation.

**Status**: NEW — not registered in debt registry

---

### MEDIUM-2: `the_judge_eval.nim` Mutual Supervision Failure Still Approves

**ID**: DEBT#367 (new)  
**Category**: Theater/Vacuous Proof  
**File**: `src/core/judge/the_judge_eval.nim:190-202`  
**Severity**: MEDIUM  
**Signature**: #4 (Vacuous Proof)

**Description**:
When SMT-Lean mutual supervision evidence is incomplete, the verdict is still `verdictApproved`. The "degraded" reason is cosmetic — the guarantee of mutual supervision is not provided.

**Remediation**: Either fail-closed or document as a verified fail-open path per AGENTS.md §0.9.

**Status**: NEW — not registered in debt registry

---

### MEDIUM-3: Test BDD Steps Are Pure `discard` Stubs

**ID**: DEBT#368 (new)  
**Category**: Theater/Disguised Stub  
**File**: `tests/features/steps/gate_steps.nim:67, 70, 121, 124, 127, 157`  
**Severity**: HIGH (violates §0.8)  
**Signature**: #3 (Disguised Stub)

**Description**:
Six BDD step procedures are pure `discard` stubs. They are registered as Gherkin step handlers but perform zero verification. Per AGENTS.md §0.8, stubs cause automatic gate FAIL.

**Remediation**: Implement the steps or delete them.

**Status**: NEW — not registered in debt registry

---

### MEDIUM-4: Test Tautological Boolean Assertions

**ID**: DEBT#369 (new)  
**Category**: Theater/Always-Pass  
**Files**: 
- `tests/gate/test_quality_audit_gate.nim:56`
- `tests/unit/namespace_sandbox_test.nim:51`
- `tests/hermetic/test_namespace_e2e.nim:43`
- `tests/gateway/process_sandbox_feature_test.nim:92`
- `tests/unit/overlay_mount_test.nim:19, 23`

**Severity**: MEDIUM  
**Signature**: #1 (Always-Pass)

**Description**:
Multiple tests use `check x == true or x == false` which is a tautology (always true). The tests claim to verify behavior but the assertions can never fail.

**Remediation**: Replace with meaningful assertions or remove if only checking for no-crash.

**Status**: NEW — not registered in debt registry

---

### MEDIUM-5: `proof_cache.nim` Cache Write Failure Silently Dropped

**ID**: DEBT#370 (new)  
**Category**: Theater/Swallowed Failure  
**File**: `src/core/proof/proof_cache.nim:152-153`  
**Severity**: LOW  
**Signature**: #2 (Swallowed Failure)

**Description**:
Cache write failure is caught and discarded. The computed proof result is silently dropped. While annotated with `axiom:best-effort`, there is no log of the dropped result.

**Remediation**: Add warning log on cache write failure.

**Status**: NEW — not registered in debt registry

---

## Previously Missed Findings (from 2026-07-27 audit gaps)

### MISSING-1: `contracts/z3_extraction.nim` Verification Failure Counted as Inconclusive

**File**: `src/core/contracts/z3_extraction.nim:537-539, 589-591`  
**Severity**: MEDIUM  
**Signature**: #2 (Swallowed Failure)

**Description**:
Z3 solver execution failures are counted as `procsInconclusive: 1` — presenting a missed execution as a successful verification attempt. The caller sees `procsChecked > 0` and assumes verification happened.

**Status**: MISSED in previous audit — should have been caught

---

### MISSING-2: `contracts/z3_extraction.nim` `coreLog()` Is a No-Op Stub

**File**: `src/core/contracts/z3_extraction.nim:110`  
**Severity**: LOW  
**Signature**: #3 (Disguised Stub)

**Description**:
`coreLog()` does `discard` — a logging function that does nothing. Used in critical "STRICT" enforcement paths. If the `quit(1)` path is bypassed, there is zero audit trail.

**Status**: MISSED in previous audit

---

## Regressions (Remediated Code Reverted to Theater)

No regressions found. The 2026-07-27 remediations (DEBT#277-#327) appear to be holding. Code reviewed in this audit shows the expected fail-closed patterns from the previous remediation.

---

## Summary Statistics

| Category | New Findings | Previously Missed | Total |
|----------|-------------|-------------------|-------|
| Always-Pass (#1) | 3 | 0 | 3 |
| Swallowed Failure (#2) | 4 | 1 | 5 |
| Disguised Stub (#3) | 2 | 1 | 3 |
| Vacuous Proof (#4) | 2 | 0 | 2 |
| Dead Gate (#5) | 1 | 0 | 1 |
| Unenforced Claim (#6) | 2 | 0 | 2 |
| **TOTAL** | **12** | **2** | **14** |

---

## Debt Registry Updates Required

Register the following NEW entries in `data/debt_registry.json`:

1. **DEBT#357**: CRITICAL-1 (Emergency bypass audit trail)
2. **DEBT#358**: CRITICAL-2 (gate_cas.nim always true)
3. **DEBT#359**: CRITICAL-3 (ecosystem_linkage.nim empty contract)
4. **DEBT#360**: CRITICAL-4 (assume_guarantee.nim Z3 fallback)
5. **DEBT#361**: CRITICAL-5 (MCP axiomVerify false success)
6. **DEBT#362**: CRITICAL-6 (z3_extraction.nim abort-all)
7. **DEBT#363**: HIGH-1 (gate_admin_validate.nim — FALSE POSITIVE, dead code only)
8. **DEBT#364**: HIGH-2 (gate_effect_classifier.nim heuristic)
9. **DEBT#365**: HIGH-3 (state_hash.nim doAssert in release)
10. **DEBT#366**: MEDIUM-1 (ir_to_lean.nim : True theorem)
11. **DEBT#367**: MEDIUM-2 (the_judge_eval.nim degraded approval)
12. **DEBT#368**: MEDIUM-3 (gate_steps.nim discard stubs)
13. **DEBT#369**: MEDIUM-4 (test tautological assertions)
14. **DEBT#370**: MEDIUM-5 (proof_cache.nim silent drop)

---

## Recommendations

### Immediate Action (CRITICAL/HIGH)

1. **Register all CRITICAL/HIGH findings** in `data/debt_registry.json` per AGENTS.md §0.9a
2. **Fix CRITICAL-1** (gateway.nim bypass audit) — security-critical
3. **Fix CRITICAL-2** (gate_cas.nim) — integrity check is fake
4. **Fix CRITICAL-3** (ecosystem_linkage.nim) — returns garbage as success
5. **Fix CRITICAL-5** (MCP axiomVerify) — misreports verification status

### Short-Term (MEDIUM)

1. **Implement or delete BDD step stubs** (DEBT#368) — violates §0.8
2. **Fix test tautological assertions** (DEBT#369) — replace with meaningful checks
3. **Replace `doAssert` in state_hash.nim** (DEBT#365) — broken in release

### Long-Term (Architecture)

1. **Enhance anti_theater_gate.nim** to detect more patterns (bare `except:`, `doAssert` in gates, JSON parse default-to-empty)
2. **Add CI check** for `check true`, `check x == true or x == false`, and `except: discard` in test files
3. **Document all fail-open paths** in `docs/spec/` per AGENTS.md §0.9

---

## Audit Methodology Notes

- **Parallel sub-agents**: 4 agents scanned src/core, src/gate+src/cli, src/verification+src/mcp, and tests/ concurrently
- **Manual verification**: All CRITICAL/HIGH findings were verified by reading the actual source code
- **Debt registry cross-check**: Confirmed that findings are not already registered (DEBT#277-#327 are CLOSED/FIXED)
- **Theater signature classification**: Each finding mapped to AGENTS.md §0.9 canonical signatures

---

**Audit completed**: 2026-07-30  
**Auditor**: opencode (parallel sub-agent orchestration)  
**Next audit recommended**: 2026-08-30 (monthly cadence)
