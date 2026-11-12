Done. Here is the complete handoff.

## Branch verification
`followup/libp2p-bytesview-slice` @ `7d8856dd5` — confirmed before and after the change. Working tree was clean at start; no commit, no push.

## The fix — `src/verification/batch_uap/loop_driver.nim`

Function: `runBatchUapOrchestration*` (the sequential per-depth node loop). Two hunks, +17/-1 lines:

```diff
@@ -1049,6 +1049,22 @@ proc runBatchUapOrchestration*(
               attemptIR.obligationVerdict.kind == ogrGenerated:
             ogrAttemptedCount += attemptIR.obligationVerdict.obligationCount
 
+        # ── P4 disproof carve-out ─────────────────────────────
+        # A fatal pre-sieve block is a STRUCTURAL verdict (the governed
+        # symbol is not a materializable routine), not a refutation: it must
+        # not swallow a P4-promoted, replay-confirmed disproof of an adopted
+        # claim. The vsDisproved terminal is the ONLY path that marks a node
+        # failed, so terminating the node as PRE-SIEVED here would make a
+        # confirmed disproof structurally invisible to the exit rule. The
+        # attribution is the SAME claim-scoped lookup stage2Budget consumes
+        # (scopedIrResultForNode), so the disproof observed here is exactly
+        # the one that terminal acts on. Fail-closed: only vsDisproved (the
+        # P4 finalizer's cvConfirmed promotion) carves out; every demotion
+        # (cvSpurious/cvUnresolved, incl. replay disagreement) stays
+        # vsInconclusive and keeps the pre-sieve verdict.
+        let disproofCarveOut = attemptIR.funcName.len > 0 and
+            attemptIR.verification.status == vsDisproved
+
         # Handle stage 1 early exits
@@ -1085,7 +1101,7 @@
-        if cached.blocked:
+        if cached.blocked and not disproofCarveOut:
           # Pre-sieve blocked or UAP request build failed
           report.nodeReports.add(OrchestrationNodeReport(
```

Everything else in the blocked branch is byte-identical (node report, refactor-trigger collection, progress sink, log line). The exit rule, sieve rules, and summary schema are untouched.

## The scoped-result keying I found (this was the part worth checking)

- `scopedIrResultForNode` (`loop_driver.nim:333-354`) keys by `extractBareFuncName(sorterNodeId(nodeIdStr))` — i.e. the node's **bare function name** — and then requires the result's module path to equal the node's module path.
- `stage2Budget` (`:373`) calls **exactly the same** proc with the same `nodeIdStr` (`prev.nodeIdStr` == the loop's `nodeIdStr`). So the carve-out uses `attemptIR` (already computed at `:1045` from the identical call) — the disproof observed by the carve-out is by construction the one `stage2Budget` consumes. No new lookup, no second source of truth.
- Map key: `ax prove` always takes the **precomputed** path (`axiom_engine.nim:388` passes `preComputedIrResults = irResults`), so the key is `irResultMap[irResult.funcName]` (`:780`) and `funcName = entry.name` (`ir_pipeline_runner.nim:697` etc.). The wave entry is `waveEntry.name = examinedFn` (`axiom_engine.nim:3283`), i.e. **`toOpenArray`** — not the carrier name. The log line `[ir-cas] MISS func=bvSliceLenActual` is the CAS memo log of `ve.funcDef.name`, **not** the map key. So the lookup HITs: bare name `toOpenArray`, module `libp2p/utils/bytesview.nim` on both sides (`entry.sourcePath` = the subject-relative module path; `normalizeScopeModulePath` passes it through unchanged since it contains `/`).
- Terminal reachability: a P4-promoted disproof carries reason `rkNone`/`rkCandidateCounterexample` (`deriveVerdict` coerces `vsDisproved`), so it is not swallowed by the earlier `rkNotEncodable/rkNoProperty/rkUnsupportedTheory` BMC-skipped branch at `:435`; it reaches the `vsDisproved` terminal at `:474-492` → `verified=false, skipReason=osrNone` → `orchestrationProofFailed` → `failedCount++` → exit 1.

## Test

Existing pattern found and used: `tests/unit/batch_uap_orchestrator_test.nim` already drives `runBatchUapOrchestration` directly, so I extended that file (I did **not** touch `tests/unit/test_libp2p_bytesview_binding.nim`).

New suite `"BatchUapOrchestrator — P4 disproof carve-out"` with two cases:
- fatally blocked node **without** a scoped disproof → `orchestrationPreSievedUnverifiable` (unchanged)
- fatally blocked node **with** a scoped `vsDisproved` result → `orchestrationProofFailed`

The blocked node is a `template` declaration (drives `blocked_non_routine`, a fatal pre-sieve verdict) and the disproof is a real `IrPipelineResult` with `makeDisproved(smBMC, pkZ3Bmc, psBounded)` and `ogrGenerated` obligations.

Results:
- `nim c -r tests/unit/batch_uap_orchestrator_test.nim` → **EXIT=0**, both new cases `[OK]`. Runtime log confirms the behavioural switch: `— pre-sieved` without the disproof, `— failed` with it.
- `nim c -r tests/unit/test_libp2p_bytesview_binding.nim` → **EXIT=0**, all cases `[OK]` (still green, unmodified).
- `nim c --hints:off -d:allowMissingZ3 --nimcache:/tmp/ld_fix_nc -o:/tmp/ld_fix_check src/cli/main.nim` → **EXIT=0**, zero `Error` lines (only the pre-existing `[decision-binding] WARN` about 45 functions missing `{.axiomDecision.}`).

## `git status --porcelain`

```
 M src/verification/batch_uap/loop_driver.nim
 M tests/unit/batch_uap_orchestrator_test.nim
```

Only the two expected files. Nothing else modified, nothing untracked, no build artifacts in the tree.

## Notes / scoped-out follow-ups (for the parent)

1. **The parallel path was deliberately left alone.** `runParallelDepthBatchUap` (`loop_depth_scheduler.nim:208-227`) has the analogous blocked branch, but that context carries **no** `irResultMap` at all, so the carve-out cannot be applied there without plumbing the IR results into the parallel context — a larger change than the stated scope. It only runs when `AXIOM_PROVE_WORKERS > 1` (default is 1, and the root-cause trace points at the sequential branch), so it does not affect this lane's smoke. Worth a separate ticket if the parallel path ever needs the same contract.
2. **The P6 OGR attempt accounting was intentionally not changed.** `if not cached.blocked:` at `:1047` still excludes a carved-out node from `ogrAttemptedCount`, even though the node now does reach the disproof terminal. Changing it would move OGR/PAR telemetry numbers and was outside "change ONLY this"; flagging it so the parent can decide.
3. **The carve-out also covers the other `blocked=true` cause** (UAP request build failure, `stages.nim:219-227`), since the branch is shared. That follows the stated contract literally ("do NOT emit the PRE-SIEVED report … fall through to the normal `stage2Budget` path"), and is the same direction (a confirmed disproof must not be swallowed), but it is broader than "pre-sieve block" alone.
4. The engine binary was built to `/tmp/ld_fix_check` (outside the repo) and nimcaches to `/tmp/ld_fix_nc`, `/tmp/ld_fix_tc`, `/tmp/ld_fix_tc2`. The new test writes its vault under `getTempDir()`, so the repo tree stays clean.
5. I did not run the full `ax prove` integration smoke against the nim-libp2p subject — that is the parent's step. The unit test pins the engine contract that the smoke depends on.