# Axiom Theater Audit — 2026-07-27

> Full-codebase theater audit per AGENTS.md §0.9 (Theater Prohibition).
> Method: 8 parallel sub-agent sweeps (gate / verification / core-A / core-B / core-C / interface / tests / tooling-CI),
> followed by orchestrator re-verification of every Critical/High finding against source.
> Known items in `docs/DEBT_REGISTRY.md`, `docs/false-positives.md`, `docs/known-limitations.md`,
> `docs/stub_test_inventory.md` were excluded (no duplicates reported).

## Verdict Summary

| Severity | Count | Registered as debt |
|----------|-------|--------------------|
| Critical | 8     | DEBT#277–#284      |
| High     | 12    | DEBT#285–#296      |
| Medium   | ~30   | report-only        |
| Low      | ~20   | report-only        |

Theater signature legend (§0.9): **S1** always-pass · **S2** swallowed failure · **S3** disguised stub ·
**S4** vacuous proof/check · **S5** dead gate · **S6** unenforced claim.

All Critical/High findings below were **re-verified by the orchestrator** by reading the cited source lines.

---

## CRITICAL — verification/gate guarantee silently void

### C1. LSP crash interpreted as proof success — `src/verification/lean_lsp_protocol.nim:216-262` (S2) → DEBT#277
```nim
try: client.pollMessages()
except CatchableError:
  discard  # pollMessages may raise on channel/lock; best-effort drain
...
except CatchableError:
  discard  # hover failure does not block diagnostics collection
```
The hover sync barrier (the ONLY point guaranteeing full file elaboration) and the message drain both
discard errors. If the Lean LSP crashes before publishing diagnostics, `checkLeanSource` collects zero
diagnostics and returns `true` → false Verified verdict flows into `vpTypeLevelEncoding` certificates.

### C2. Fabricated cross-validation in IR pipeline — `src/verification/batch_uap/ir_pipeline_runner.nim:131-218` (S1/S6) → DEBT#278
Three separate paths return `crossValidation: CrossValidationResult(consistent: true)` when **no SMT and
no Lean backend was invoked**: BMC-skip (l.136), type-level fast-path without LSP (l.190-201, gated only
by the pure structural filter `classifyTypeLevel` — `success: true` with zero verification), and empty-SMT
vacuous case (l.215). Certificates carry `crossValidated: true` for work never performed; no runtime log
distinguishes fabricated from genuine results.

### C3. SMT↔Lean consistency check that checks nothing — `src/core/judge/the_judge_eval.nim:52-65` (S1/S4) → DEBT#279
```nim
let smtHypotheses = smtResult.proofTrace.splitLines()
let leanAxioms = leanResult.proofTerm.splitLines()
smtHypotheses.len > 0 and leanAxioms.len > 0
```
`proofTrace`/`proofTerm` are hardcoded `""` on success (l.37, l.45). `"".splitLines()` = `@[""]` (len 1),
so the function is **always true** whenever both provers report success. The mutual-supervision guarantee
of `evaluateHint` Phase 3 is void.

### C4. Preconditions silently erased to `True` — `src/core/trusted/ir_to_lean.nim:636,657` (S4) → DEBT#280
```nim
if e == nil: return "True"
...
else:       result = "True"   # irCall, irLoop, irRecCall, irCast …
```
`refinedExprToProp` converts any nil or unsupported IR expression (calls, loops, recursion, casts) into
the trivially-true proposition. Refinement-typed Lean proofs of such preconditions prove nothing.

### C5. Topology triple fail-open chain — `src/core/topology/{policy.nim:48, declaration.nim:124, lock.nim:92, suggest.nim:207}` (S2) → DEBT#281
```nim
except CatchableError: return TopologyPolicy()   # policy.nim
except CatchableError: discard                    # declaration.nim, lock.nim
except CatchableError: lockVios = @[]; ttlVios = @[]  # suggest.nim
```
Corrupt/missing `topology_policy.json` + `topology.json` + `topology.lock` each independently collapse to
empty structures → every topology compliance/lock/TTL check reports **zero violations** with no audit trail.

### C6. Invalid JSON becomes valid empty object — `src/core/gateway/gateway_json.nim:15-19` (S1) → DEBT#282
```nim
ok(parseJsonOpt(raw).get(newJObject()))
except CatchableError: err(axiomErrJsonInvalid)
```
`parseJsonOpt` is `raises: []` and `.get(default)` never raises → the `err` path is dead code; malformed
JSON is returned as `ok(empty object)` to all downstream gateway validation.

### C7. SMT sanitizer rewrites ill-typed constraints to tautologies — `src/core/encoding/smtlib2_sanitizer.nim:74-85` (S4) → DEBT#283
```nim
if leftType == "Bool" or rightType == "Bool":
  return SExprNode(isList: false, atom: "true")
...
if leftType.len > 0 and rightType.len > 0 and leftType != rightType:
  return SExprNode(isList: false, atom: "true")
```
Type-incompatible comparisons silently become `(assert true)` — enabling vacuous Z3 proofs at the encoding
layer with zero diagnostics.

### C8. Deferred tier-2 gates silently skipped on ledger failure — `src/gate/orchestrator/hook/executor.nim:514-517` (S2/S5) → DEBT#284
```nim
let ledger = openLedger(repoRoot)
if ledger == nil:
  logWarn(...); quit(0)
```
`openLedger` returns nil on CRC mismatch or missing ledger. Deferred gates ("will run post-commit") are
then never executed and nothing fails — the tier-2 deferral promise is unenforced. (Logged, but the
fail-open is not documented in `docs/spec/`.)

---

## HIGH — false pass reachable in normal operation

### H1. Unknown gate status reported as PASS — `src/gate/orchestrator/hook/executor.nim:1332` (S1) → DEBT#285
`GateReport(id: g.id, ok: true)` emitted for gates falling into no known status category.

### H2. Missing gate_hook binary = full gate skip — `src/gate/gateway.nim:335` (S2/S5) → DEBT#286
`gateway.nim` returns `("", 0)` when the `gate_hook` binary is absent — pre-commit succeeds with zero gates run. Related:
`src/gate/pipeline_orchestrator.nim:130,139,151,207` returns `true` whenever
state/VFS/entry infrastructure is nil.

### H3. Unknown layer bypasses import enforcement — `src/core/trusted/layer_enforcement.nim:26-27` (S4) → DEBT#287
`return true  # No rule found = allow` — files in unregistered layers get unrestricted imports.

### H4. "3-Tier Proof System" = three substring checks — `src/mcp/tools.nim:277-320` (S6/S4) → DEBT#288
`axiomValidateIntegrity` claims "Triangular Integrity Verification" but only checks: evidence dir non-empty,
`AGENTS.md` contains `"Intent"`, features dir non-empty. MCP client is told
"Verification tool passed. Triangular consistency … logged."

### H5. Unvalidated gate bypass token — `src/cli/subagent_orchestrator.nim:300-302`, `src/gate/runners/documentation_first_gate.nim:640-654` (S5) → DEBT#289
Any non-empty `AXIOM_GATE_BYPASS_TOKEN` bypasses validation with `quit(0)`; no signature check, no
persistent audit record of the bypass event (contrast with the Ed25519-audited `.axiom_emergency_bypass`).

### H6. Malformed proof report exits 0 — `src/cli/wf_runners.nim:39-40` (S1) → DEBT#290
`if summary.isNil or summary.kind != JObject: return 0` — corrupted/empty report → green exit code for CI.

### H7. Lean test suite passes with zero assertions — `tests/verification/test_healing_orchestrator.nim:303-403` (S2, 6 blocks) → DEBT#291
All `runLeanProofRefinementLoop` assertions live inside `try/except CatchableError: discard`. When the
call raises (Lean unavailable OR real crash), zero checks execute and the test passes — indistinguishable
from success, no `skip()` marker.

### H8. Gate precompile failures exit 0 — `src/cli/precompile_gates.nim:519-520` (S2) → DEBT#292
`failed > 0` produces only a WARNING log; lock file is written and process exits 0. If all gates fail to
compile, the pipeline proceeds with zero compiled gates (only hook-mode CAS-miss remains as safety net).

### H9. Hermetic build ignores sub-check failures — `tools/hermetic_build.nim:1246,1262-1276` (S2) → DEBT#293
`debt_codegen` failure prints WARNING without setting `allPassed = false` (type-registry failure at
l.1239 correctly does); `checkGolden`/`checkHooks` discard `execCmdEx` exit codes and can report
`GOLDEN_CLEAN` on git failure.

### H10. Bypass hook calls an undefined function — `kimi_pre_tool_use.nim:85,129` (S3/S5) → DEBT#294
`requestBypass(...)` has **no definition anywhere in the repository** (rg finds call sites and test
comments only) — the emergency-bypass verification chain terminates in dead, non-compiling code.

> **Historical note:** this finding applied to the audit snapshot. The `kimi_pre_tool_use.nim` hook
> was subsequently deleted as dead code in the DEBT#294 remediation (2026-07-27), so the referenced
> file no longer exists in the repository.

### H11. CI converts failures to success with `|| true` — `.circleci/continue.yml:146,174` (S2) → DEBT#295
`git fetch origin main --depth=1 2>/dev/null || true` (stale-diff gates continue silently) and
`bin/pbt_seed_parser || true` (PBT seed corruption never fails the job).

### H12. Anti-vacuity flag from substring match; Merkle tree drops unhashable files — `src/verification/lean_lsp_compiler.nim:261,338` + `src/core/observer/scanner.nim:9-10,90-91` (S4/S2) → DEBT#296
`vacuityProven = verified and source.find("ax_vacuity_check") >= 0` — presence of the tactic *name*
anywhere in the text satisfies the soundness gate consumed by `verified_set_hydration.nim`. In the state
scanner, files whose SHA-256 fails hash to `""` and are silently excluded from the Merkle root.

---

## MEDIUM (report-only, remediate opportunistically)

| Location | Sig | Summary |
|---|---|---|
| `src/gate/in_process_gates.nim:224,246-289,429-435` | S2 | 9× "SSOT missing/corrupt → return true" across logging-policy, debt-monotonic, memory-policy gates |
| `src/core/audit/sad_gate.nim:59,147` | S1/S2 | expiry-free permanent break-glass override, date parse error → enforcement over |
| `src/core/boundary/gateway/gateway_generator.nim:105-106` | S3 | macro parse failure → empty stmt list, validation procs never generated |
| `src/core/topology/node_filter.nim:78,115` + `plan.nim:53` | S2 | source discovery errors discarded → empty scan set |
| `src/core/boundary/boundary_extraction_main.nim:352` | S2 | solid-gate rejection audit records silently dropped on I/O error |
| `src/core/observer/state_hash.nim:16-32,105` | S2 | state hash computed over silently-incomplete inputs; persistence failures dropped |
| `src/core/encoding/smtlib2_util.nim:76-111` | S4 | "certified exempt" via lowercase substring import heuristics |
| `src/core/feature_manifest_guard.nim:14-19` | S5 | guard compiled out entirely in release builds despite doc claim |
| `src/core/interfaces/io_executor.nim:98-108` | S6 | `Result` error channel never used; interface contract dead |
| `src/core/encoding/vfs.nim:22-28,43-67` | S2 | VFS init/write Results discarded; read errors = empty artifact |
| `src/core/sync/sync_process_runner.nim:97,148` | S2 | output-read failure → empty output with success exit code |
| `src/core/proof/proof_cache.nim:146` | S2 | proof cache write failures invisible |
| `src/core/judge/lean_replay.nim:107-108` | S2 | Lean source write failure swallowed → replay may run stale file |
| `src/core/contracts/z3_extraction.nim:619,642,655,813` | S2 | bare `except:` in strictBlocking contract paths (violates exception_guard policy) |
| `src/verification/proof_state_builder.nim:279-283` + `state_persistence.nim:77-81` | S1 | `vacuousContradictions/timedOut/pseudoVerified/counterExamples` counters hardcoded 0 |
| `src/verification/cert_writer.nim:131-141` | S6 | `vacuityChecked: true` on certPseudoVerified certificates where no check ran |
| `src/verification/pipeline_lean_spec_inference_part2.nim:362` + `part3.nim:254` | S3 | `proofReplayVerified` param ignored; assumptions dropped as `have _ : True` |
| `src/infrastructure/native_cgroup.nim:157-167,207-239` | S3/S6 | non-Linux/kill stubs silent; spec §13 requires warning that is never emitted |
| `src/infrastructure/bypass_audit.nim:60,94` | S2 | audit-trail write/parse failures swallowed — bypass without record |
| `src/cli/commands/observability.nim` | S3 | type-only stub in production command directory |
| `src/cli/wf_state.nim:125` + `axiom_engine.nim:428` + `main.nim:52` | S2 | exemption scan/VSR ledger/source-tree-hash errors swallowed |
| `src/gate/gateway.nim:236-239,543,597` | S5 | dual-track opt-in default-off; file-based bypass without audit; manifest check env-gated |
| `tools/agent_bypass_commit.nim:119,125` + `agent_bypass_sign.nim:37` | S2 | bypass audit writes discarded; signature computed over empty tree hash on git failure |
| `tools/feature_manifest_generator.nim:239-244` | S2 | cache move failures discarded, returns ok anyway |
| `tools/seed_registry.nim:92` | S6 | invokes `python3 bin/generate-pbt-tests` despite Language Ban |
| `config.nims:312` + AGENTS.md §2 | S6 | `AXIOM_INTERNAL_BYPASS` residue guard removed; AGENTS.md/spec still describe it |
| `src/mcp/tools.nim:293` | S4 | "Context Check" = `contains("Intent")` |
| `tests/engine/test_atomic_ops.nim:130` | S1 | new `check true` stub not in stub inventory |
| `tests/gateway/effect_types_feature_test.nim` | S6 | .feature claims compile-time parseJson blocking; runner tests string round-trip only |
| `src/personas/judge_automation.nim:343` | S2 | goal-shape JSONL parse errors → silent empty |

## LOW (report-only)

`merkle_cache.nim:242`, `topology_engine.nim:230,412`, `boundary complexity_index.nim:223`,
`smart_search.nim:257,337,379`, `architecture_invariants.nim:436`, `stdlib_shield.nim:108`,
`solver_bridge.nim:139`, `provers.nim:64` (doc says fail-open, code is fail-closed),
`hotspot_analyzer.nim:30,54,68,82`, `governance_engine.nim:57,98`, `import_graph.nim:85`,
`cache_gc.nim:50-64`, `precompile_gates.nim:191,335`, `wf_state_vacuity.nim:136`,
`gate_admin_validate.nim:111`, `tools/static_analyzer.nim` (5×), `tools/ast_splitter.nim` (3×),
`tools/symbol_extractor.nim` (3×), `tools/debt_registry_gen.nim` (2×), `tools/pbt_generator.nim:84`,
`tools/build.nim:360`, `tools/shared/ast_fix_engine.nim:142`, `Makefile:47,102`,
`src/ui/ax_tui_reporter_part2.nim:143` (PASSED from raw counters),
`src/infrastructure/gate_signing/proof_verifier.nim:107` (deprecated-but-exported `verifyLeanKernel`),
`src/infrastructure/gate_signing/axiom_prove.nim:188` (0 lean files = pass),
`tests/gateway/generated_feature_runner.nim:362` (data collected then discarded before `check true`).

## Cleared as NOT theater (for the record)

- Manifest→runner wiring: all 50 `manifest.d/_index.json` entries have compile-time-asserted runners.
- `state_ledger.nim` CRC path itself fails closed (nil return) — the theater is in the *consumer* (C8).
- semantic_grounding_hook (REMOVED 2026-08-07 — context injection pipeline purge; see docs/agents/rules_workflow.md): always-exit-0 theater, tracked as DEBT#374 (Closed).
- `src/core/utils/idempotent_write.nim:14` return-true-on-identical-content: by design.
- `tests/` `skip()` usages: all legitimately conditional (Docker/tree-sitter/binary availability).
- Ed25519 emergency bypass (`gateway.nim:547-567`): signature-verified and audit-logged.

## Domain theater density

| Domain | Files | C/H findings | Density note |
|---|---|---|---|
| verification + proofs | ~180 | 4 C, 2 H | fabricated certificate metadata is systemic |
| core trusted/solver/judge | ~122 | 2 C, 1 H | judge mutual-supervision path is void |
| core topology/boundary/audit | ~160 | 1 C (4-file chain), 0 H | swallowed-failure dominant (19/26 findings) |
| core misc (C-scope) | ~160 | 2 C, 0 H | JSON/SMT encoding layer hotspots |
| gate infra | ~215 | 1 C, 3 H | infrastructure-missing → PASS pattern ×9 |
| interface (cli/mcp/infra) | ~150 | 0 C, 3 H | UI/MCP overstate guarantees |
| tests | ~397 | 0 C, 1 H | 0.2% assertion-level, but Lean suite hollow |
| tooling/CI | ~210 | 0 C, 3 H | hermetic orchestrator swallows own sub-checks |

## Remediation priority

1. **DEBT#277/278/279/280** — proof-engine core: these make false "Verified" certificates possible today.
2. **DEBT#281/282/283** — input-collapse chains that turn corrupt inputs into vacuous passes.
3. **DEBT#284–#290** — gate/CLI bypass and false-green paths.
4. **DEBT#291–#296** — test/CI/tooling theater.
5. Medium/Low: fold into DEBT#275 remediation wave (add `logWarn` to every guarantee-relevant
   `except: discard`; document remaining fail-opens in `docs/spec/` per §0.9).
