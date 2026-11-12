# 3 Gates & Self-Evolution Loop — Verification Artifacts

## Sub-task 1: The Sieve (판별)

### Evidence A: grep for "Sieve" / "sieve" / "Proven.*Unverifiable"
```bash
$ grep -rn "Sieve\|sieve" src/cli/wf_runners.nim
# (no output)

$ grep -rn "Proven.*Unverifiable\|Unverifiable.*Proven" src/
# (no output)
```

### Evidence B: axProofShortcutExitCode behavior
```bash
$ sed -n '24,41p' src/cli/wf_runners.nim
```
```nim
func axProofShortcutExitCode*(
  reportNode: JsonNode; requirePerfectAsi: bool = false; continueOnError: bool = false
): int {.nosideeffect.} =
  let hasVerified = reportNode.getOrDefault("verifiedCount").getInt() > 0
  let hasUnverifiable = reportNode.getOrDefault("unverifiableCount").getInt() > 0
  let hasVacuous = reportNode.getOrDefault("vacuousCount").getInt() > 0
  let hasTimeout = reportNode.getOrDefault("timeoutCount").getInt() > 0
  if hasVacuous and not continueOnError:
    return 2
  if requirePerfectAsi and (hasUnverifiable or hasTimeout):
    return 1
  if hasVerified:
    return 0
  return 1
```

**Verdict**: `axProofShortcutExitCode` reads pre-computed JSON counts. It does NOT invoke UAP to classify nodes. The classification is based on stale topology data, not live proof results.

---

## Sub-task 2: Diagnosis (진단)

### Evidence C: buildTimeoutDiagnosis callers
```bash
$ grep -rn "buildTimeoutDiagnosis" src/ --include="*.nim"
```
```
src/core/diagnostics_engine.nim:269:func buildTimeoutDiagnosis*(...)
src/core/orchestrator_topology_worker.nim:34:  let diagnosis = buildTimeoutDiagnosis(
src/core/orchestrator_topology_worker.nim:70:  buildTimeoutDiagnosis(
```

**Verdict**: `buildTimeoutDiagnosis` is called from `orchestrator_topology_worker.nim` (lines 34, 70). It is NOT called from `runAxProveShortcutCli`, `runUniversalAcceptancePipeline`, or `runBatchUapOrchestrator`.

### Evidence D: buildStructuralDiagnosis callers
```bash
$ grep -rn "buildStructuralDiagnosis" src/ --include="*.nim"
```
```
src/core/diagnostics_engine.nim:377:func buildStructuralDiagnosis*(...)
```

**Verdict**: `buildStructuralDiagnosis` has **zero callers** in `src/`. It is defined but never invoked.

---

## Sub-task 3: Guidance (교정)

### Evidence E: generateRefactoringTemplates callers
```bash
$ grep -rn "generateRefactoringTemplates" src/ --include="*.nim"
```
```
src/core/diagnostics_engine.nim:429:proc generateRefactoringTemplates*(diagnosis: TimeoutDiagnosis): seq[RefactoringTemplate] {.raises: [].} =
```

**Verdict**: `generateRefactoringTemplates` has **zero callers** in `src/`. It is defined but never invoked.

### Evidence F: runAxHealCli callers from ax prove path
```bash
$ grep -rn "runAxHealCli" src/cli/wf_runners.nim src/cli/action_interpreter_cli.nim src/cli/action_plan_cli.nim
# (no output)
```

**Verdict**: `runAxHealCli` is never invoked from the `ax prove` dispatch chain.

---

## Sub-task 4: Self-Evolution Loop

### Evidence G: Closed-loop search
```bash
$ grep -rn "counterexample learning\|law revision\|self.evolution\|closed.loop" src/ --include="*.nim"
# (no output)
```

### Evidence H: runBatchUapOrchestrator rounds
```bash
$ sed -n '60,65p' src/verification/batch_uap_orchestrator.nim
```
```nim
proc runBatchUapOrchestration*(
  initialState: SorterState;
  requests: seq[OrchestrationProofRequest];
  vaultDir: string;
  maxRounds: int = 6;
```

**Verdict**: `maxRounds = 6` is a batch parameter, not a per-function self-evolution loop. No feedback edge from output back to input exists in `runUniversalAcceptancePipeline`.

### Evidence I: Refactoring stagnation
```bash
$ sed -n '37,48p' src/core/refactoring_engine.nim
```
```nim
RefactoringStagnation* = object
  consecutiveFailures*: int
  maxFailures*: int            ## Default 3
  escalated*: bool
  escalationReport*: string
```

**Verdict**: Stagnation detection exists but acts as an escape valve (human handoff), not a learning loop.

---

## Sub-task 5: Persona Loop Order Motivation

### Evidence J: Git history for universal_pipeline.nim
```bash
$ git log --oneline --all -- src/verification/universal_pipeline.nim | head -n 10
```
```
f27307a0 feat(prove): implement 4-layer proof pipeline architecture (Phase 0-8)
1c2e9aed fix: eliminate try/except — direct JSON construction and proper {.raises: [].}
46e58715 fix: resolve spec-binding gate errors and raises pragma violations
a348886a refactor: VulnerabilityHit pure ADT with strictCaseObjects
f5bfddbb feat(debt): Phase 2.4 try/except → Result[T,E] conversion (partial)
4fa44158 Nim 2.x migration: Zero-Macro pattern + heal route removal + SOLID decomposition
e8e4ff29 WIP: SOLID modularization Phase 4-5
81a4924e refactor(srp): rollback gateway.nim to core, fix persona re-exports, register import-facade roles
ea3b2b1f refactor(personas): extract persona_interface.nim and centralize artifact types
01cd261e Refactor universal pipeline into persona orchestrator
```

### Evidence K: Commit message for persona orchestrator refactor
```
01cd261e Refactor universal pipeline into persona orchestrator
```

No mention of loop order change rationale.

### Evidence L: f27307a0 commit message
```
feat(prove): implement 4-layer proof pipeline architecture (Phase 0-8)
...
Refs: Notion spec v0.3.7 (정체성)
```

This commit (2026-06-01) claims to implement the 4-layer architecture per Notion spec, but only adds Scribe→Judge wiring. It does NOT integrate BMC/CEGAR into the persona pipeline.

### Evidence M: Inline comments in universal_pipeline.nim
```bash
$ grep -n "Scout\|Layer 1\|BMC\|CEGAR\|fixed.point\|order\|sequence" src/verification/universal_pipeline.nim
```
```
# Phase 1 wiring: Leanstral -> Judge (Scribe -> Layer 4)
```

Only comment is about Scribe→Judge wiring. No rationale for persona order.

**Verdict**: No documented rationale for the Detective→Legislator→SWAT→Scribe→Judge→Detective order. The order may have emerged organically during incremental development rather than by intentional design.

---

## Overall Verdict

| Test | Result |
|---|---|
| The Sieve gate implemented | ❌ FAIL |
| Diagnosis engine implemented but unwired | ⚠️ PARTIAL |
| Guidance engine implemented but unwired | ⚠️ PARTIAL |
| Self-evolution loop outside UAP | ❌ FAIL |
| Persona loop order rationale documented | ❌ FAIL |
