# Phase C3 — R7 Semantic Partition + Layered Termination Architecture

> **Status**: DRAFT — Phase C design (documentation only). No product code or tests were modified.
> **Predecessors**: `docs/design/r7_exit_authority_gap.md` (Phase B audit, evidence capture) + `docs/design/r7_cli_outcome_contract.md` (R7 outcome contract) + `src/cli/cli_outcome.nim` (canonical boundary).
> **SSOT anchor**: `docs/spec/productization_contract.md` §v1 CLI Exit-State Contract (lines 263–281).
> **Character of this document**: Parts A–B are verified ground truth and a ratified decision *order*. Part C is a **TARGET architecture** — the collapse claims inside it are hypotheses to be verified by the per-site mapping, not established conclusions.

---

## 0. Objective

Define the Phase C design that converts the R7 exit-authority gaps into a **layered termination architecture**:

- **Correction of the Phase B audit** (Part A — five corrected claims plus one addition, each verified against the working tree at 2026-08-19).
- **Ratified semantic decision order** (Part B): domain semantics → process-boundary classification → subprocess policy → void-command conversion → dormant-code disposition, with concrete per-command domain-outcome candidates and the current sources they replace.
- **Layered architecture as a target** (Part C): Level-1 command-domain outcome enums, Level-2 classification policy `DomainOutcome → ClassificationPolicy → TerminationInstruction` with a per-site mapping of all P1 sites, Level-3 single process boundary `exitWith(CliOutcome)` — plus the explicitly OPEN semantic-partition question (the "no bucket" class).

The audit file itself is **evidence of record** and is deliberately not edited; the corrections live in this document.

---

# Part A — Corrections to the Phase B audit (verified)

Re-verified against `src/` at 2026-08-19 (method + evidence in Appendix A).

## A.1 — Correction 1: total direct `quit(` count is **83**, not 82

`r7_exit_authority_gap.md:69` states "Total: 82 direct `quit(` call sites" and §4 tallies "Classified subtotal 81 + cli_outcome:38 = 82".

The arithmetic drops one site: the canonical `cliQuit` branch at `action_interpreter_cli.nim:203` (`quit(action.exitCode)`) IS a direct `quit(` call site. The audit itself lists it among the "4 canonical sites" (§4, "Canonical boundary" row) but never adds it to the total — the subtotal 81 = P1(39) + P3(34) + P4(4) + P5(4) contains neither `:203` (listed under canonical) nor `cli_outcome.nim:38` (added separately as +1).

Reconstructed arithmetic: 81 classified + 1 (`:203` cliQuit) + 1 (`cli_outcome.nim:38` choke point inside `exitWith`) = **83**. Ripgrep `\bquit\(` over `src/cli/**` yields 85 raw lines, of which 2 are doc comments (`cli_outcome.nim:35,36`) → **83 code sites**, matching.

Corrected inventory (also folds in A.5, which moves `wf_state_vacuity.nim:164` out of P1):

| Tier | Sites | Description |
|---|---|---|
| P1 — product-termination boundary | **38** | raw `quit(` sites reachable from `ax <cmd>` (8 files) |
| D — dormant (reclassified from P1, see A.5) | **1** | `wf_state_vacuity.nim:164` |
| P3 — tooling-only | **34** | 6 files |
| P4 — bootstrap / intentional-fatal | **4** | `main.nim` |
| P5 — unreachable / dead | **4** | `wf_runners.nim` |
| Canonical boundary | **1** | `action_interpreter_cli.nim:203` (cliQuit); the other 3 canonical sites use `exitWith(` and are not `quit(` sites) |
| Choke point | **1** | `cli_outcome.nim:38` (inside `exitWith`) |
| **Total direct `quit(` sites** | **83** | 17 files |

P1 distribution (38): `action_interpreter_cli.nim` 23 (22 guards `:78,82,86,90,94,98,102,106,110,114,118,130,134,138,142,146,152,156,160,164,170,174` + fall-through `:204`); `action_output_cli.nim:32`; `cli_io_error.nim:13`; `check_cli.nim:67,90,93`; `check_spec_cli.nim:40,43,61,81,92`; `shape_cli.nim:103,112,116`; `infra_cli.nim:235,239`.

**Impact**: every downstream "39→~3" reduction argument in Part C uses the corrected 38/83 counts.

## A.2 — Correction 2: `gate_admin` "BLOCK → exit 2" live site is `gate_admin.nim:113/:119`, NOT `:297+`; it does not cross the product boundary

The audit (§5 and Appendix A) attributes "gate blocking exits 2" to `:297,313,324,329,334,339,345`. Verified:

- `gate_admin.nim:108-113` — `cmdValidate`: `let rc = validateCommand(cmd)`; on `rc != 0` prints BLOCKED; **`quit(rc)` at :113**.
- `gate_admin.nim:114-119` — `cmdValidateStdin` (JSON-stdin variant): **`quit(rc)` at :119**.
- `rc = 2` comes from `validateCommand` itself: `src/cli/gate_admin_validate.nim:93`, which `return 2` on every blocking classification (`:99,:116,:123,:131,:139,:149,:174`). The "Exit 2 on block, 0 on allow" contract is documented at `gate_admin.nim:109`.
- `:297` = `quit(1)` when the **self-test** has failures; `:298` = `quit(0)` self-test pass; `:313,:324,:329,:334,:339,:345` = usage-error `quit(1)` in the `when isMainModule` dispatch (`:304-345`). None of these is BLOCK→**2**.

**Boundary reachability**: `gate_admin` is a standalone binary (`when isMainModule`). The product dispatcher's gate surface is `gate_cli.nim` `runGateCli` (`:24-97`), which only:
- relays child `bin/gate_admin list` (`:35-42`) and `status` (`:51-58`) — both 0/1 relays;
- runs its own contract check and `bin/gate_hook` (`run` branch, `:62-93`; hook result relayed at `:90`).

`validate` / `--validate-stdin` — the only BLOCK→2 producers — are **not reachable through `ax gate` today**. The audit's §5 row "`gate_admin.nim` (BLOCK paths) exit 2 product-boundary relay" overstates the exposure: exit 2 collides with `INTERNAL_ERROR=2` **only when the tool is invoked directly** (`bin/gate_admin validate …`). These two sites stay P3 (tooling); a future `ax gate validate` surface must route through the L2 policy.

## A.3 — Correction 3: `ax verify <bad-dir>` → exit 0 root cause is the **LIVE** `src/cli/verify_cli.nim:158-164`, not the P5-dead `wf_runners` shortcut

Audit §6 attributes `ax verify <bad-dir>` → 0 to `src/cli/wf_runners.nim:100-105,163-172` ("a directory-level rejection is never mapped into `AxCommandCliResult.exitCode`"). **That shortcut can never fire**: `runAxVerifyShortcutCli` (`wf_runners.nim:96`), `runAxReportShortcutCli` (`:176`), `cmdEncodeSemanticPayload` (`:195`), `cmdVerifySemanticPayload` (`:199`) have **zero call sites in `src/`** (verified; only `src/generated/type_registry_metadata.json` metadata + a historical doc mention). The dispatcher routes `cliCommandVerify` → `runVerifyCli` (`action_interpreter_cli.nim:161-164`), and that is where the bug lives:

- `src/cli/verify_cli.nim:158` — `proc runVerifyCli*(args: seq[string]): int`
- `:160-161` — `let storePath = claimsDir & "/claims.store"; let records = readRecords(storePath)`
- `:162-164` — `if records.len == 0: echo "[verify] No claims found in " & storePath; return 0`

`readRecords` on a missing directory/store returns `@[]` (append-store semantics), so `ax verify <bad-dir>` and `ax verify <empty-store-dir>` both silently **return 0**. A Phase C fix **must target the live site**: a missing `claims.store` (or missing dir) is invalid input; an existing store with zero claims is the "0 verified" case (Part C §C.4).

## A.4 — Correction 4: `topology_cli.nim:204` is `return exitCode`, not a subprocess relay; the relay is the `apply` path

The audit (§5 row "Subprocess pass-throughs") cites `commands/topology_cli.nim` `:204` as "raw subprocess codes". Verified: `topology_cli.nim:204` is **`return exitCode`** inside `runTopologyAudit` (`:125-206`), where `exitCode` is computed from the audit result (`:166-171`: 0 unless `auditRes.errors > 0` or (`strict` and warnings > 0); `:130` is `return 2` for bad flags). No child process is involved in `runTopologyAudit`.

The real subprocess relay in topology is the **apply path**: `runTopologyApply` (`topology_cli.nim:208-259`) → `executeTopologyApply` (`src/infrastructure/topology_executor.nim:274`) → `executeTopologyPlan(execPlan, axPath, lockPath)` (`:291-292`), where `axPath = "./bin/ax"` (`topology_cli.nim:228`). The child outcome is mapped at `topology_cli.nim:234-259`: `terkSuccess`/`terkDryRun` → 0, `terkCancelled`/`terkValidationFailed` → 1, `terkRollbackFailed` → 2.

**Impact**: subprocess-pass-through inventories must list `runTopologyApply` → `executeTopologyApply` (executor) as the topology child boundary — not `:204`.

## A.5 — Correction 5: `wf_state_vacuity.nim:164` is **DORMANT** (zero live callers)

The audit §4.1 lists `wf_state_vacuity.nim:164` as a live P1 "mid-pipeline `quit(1)`". Verified dormancy chain (it cannot fire on any reachable path):

- `wf_state_vacuity.nim:145-169` — `recomputeAxProofStateSummary*`; the `quit(1)` at `:164` guards `totalSrcFuncs < metrics.KernelDomainThreshold`.
- All 5 call sites of `recomputeAxProofStateSummary` are inside **zero-call** procs:

| Intervening proc (declaration) | Call sites | Callers of the proc |
|---|---|---|
| `resetForceHealQuarantine*` (`wf_state.nim:55`) | `wf_state.nim:98` | **0** |
| `applyCertifiedExemptionsFromSource*` (`wf_state.nim:99`) | `wf_state.nim:129` | **0** |
| `mergeSemanticPayloadProofState*` (`wf_semantic.nim:472`) | `wf_semantic.nim:521` | **0** |
| `normalizeSemanticProofStateDependencies*` (`wf_semantic.nim:525`) | `wf_semantic.nim:546,562` | **0** |

Likewise the module's JsonNode gate funcs — `applyProofStateAntiVacuityGate*` (`:172`) and `applyAntiTautologySentinel*(state: var JsonNode)` (`:212`) — have **zero callers**; the live `axiom_engine.nim:159` chain binds to the `ValidatedProofReport` overloads in `proof_gate.nim`, not to these.

**But the module is on the live `ax prove` module graph**: `axiom_engine.nim` (live, drives the prove pipeline) imports `cli/wf_state`, which imports `cli/wf_state_vacuity`; `src/cli/main.nim:17,32` imports/exports `ax_workflow_cli`, which imports `wf_semantic` → `wf_state_vacuity`. Live modules consume its helpers: `wf_state.nim` uses `countAxProofStatuses` (8×) and `proofStateStringField` (5×). So "P5 → delete" is **unworkable as stated** — the module must be decided, not ignored.

Three-axis classification:

| Axis | Classification |
|---|---|
| **Reachability** | `dormant` — transitively: the quit site has zero live call paths (all intervening callers are zero-call) |
| **Product-relevance** | `TBD` — the guard's intent is a domain-content threshold ("total source functions < kernel-domain threshold") over the verification summary; if it is the intended VKD floor guard, it belongs on the `ax prove`/`ax verify` domain outcome (Levels 1–2), re-expressed without a mid-pipeline `quit` |
| **Disposition** | `delete \| resurrect \| quarantine` — see D.5 for the decision (this design recommends **quarantine**: strip the quit, register the lost guard), NOT "P5 → delete" |

## A.6 — Addition to §5: `release_cli.nim:54-57/:62-66` → exit **2** (no / bad semver tag)

The audit §5 release row only records `release_cli.nim:83` (dirty → **4**) and `:70,:73` (dry-run/no-bump → **3**). Two further **2** emissions are unrecorded:

- `release_cli.nim:54-57` — `if not tagOk: … return 2` (no semver tag found)
- `release_cli.nim:62-66` — `of doBadTag: … return 2` (last tag is not valid semver)

Both send **2** — the same code as `INTERNAL_ERROR`. The corrected release exit set is {0,1,2,3,4}, where 2 and 3 collide with the contract codes and 4 has no contract counterpart. (Completeness: `:96-99` "version line missing in axiom.nimble" → `return 1`; `ok` → 0; dry-run → 0.)

**Corrected §5 out-of-contract producer set**: release {1,2,3,4}; cert {2 = JOURNAL_REQUIRED}; topology usage {2}; standalone `gate_admin` BLOCK {2}; subprocess relays (`main.nim:89,105`; `gate_cli.nim:42,58,90`; `check_cli.nim:90`; `infra_cli.nim:235`; topology apply executor).
---

# Part B — Semantic decision order (ratified approach)

Decisions are taken in dependency order; each makes the next decidable.

## D1 — Domain semantics: per-command domain outcomes

Each command module owns ONE domain outcome enum capturing its true results (not process-exit numbers).

| Command (current impl) | Outcome enum (candidate names) | Replaces |
|---|---|---|
| release (`release_cli.nim:46-100`, `runReleaseCommand: int` = {0,1,2,3,4}) | `ReleaseOutcome = roReleased / roDryRunPreview / roNoBump / roDirtyWorktree / roMissingSemverTag / roBadSemverTag / roNimbleVersionLineMissing` | every `return N` in `runReleaseCommand`; boundary no longer sees 2/3/4 |
| cert (`cert_cli.nim:39-57`, `verifyCert: int` {0,2}; usage `:73-91`) | `CertOutcome = coPass / coVerifyFail / coJournalRequired / coUsageError` | `return 2` at `:53-54`; usage paths in `runCertCli` |
| topology (`topology_cli.nim:125-204` audit; `:207-259` apply; `:260-270` explain; `:271-293` manifest) | `TopologyOutcome = toAuditPassed / toAuditFailed / toFlagsError / toApplyOk / toApplyDryRun / toApplyCancelled / toApplyValidationFailed / toApplyRollbackFailed / toExplainOk / toExplainFailed / toManifestOk / toManifestFailed` | the four family return sets |
| gate (`gate_cli.nim:24-93`, `runGateCli: int` {0,1} + child codes) | `GateOutcome = goPass / goFailure / goUsageError / goChildCode(code: int)` | dispatch returns + child relays `:42,:58,:90` |
| check (`check_cli.nim:53-94`, `run*` — void) | `CheckOutcome = checkPass / checkFail / checkMissingSourceDir / checkNoFiles / checkChildCode(code: int)` | the void + internal quits `:67,:90,:93` |
| check-spec (`check_spec_cli.nim:33-92`, `runCheckSpec*` — void) | `CheckSpecOutcome = specTagsAligned / specOnlyDrift / codeOnlyDrift / specMissingInput / specInternal` | the void + quits `:40,:43,:61,:81,:92` |
| shape (`shape_cli.nim:91-114`, `run*` — void) | `ShapeOutcome = shapePass / shapeFail / shapeUsageError / shapeChildCode(code: int)` | the void + quits `:103,:112,:116` |
| infra (`infra_cli.nim:223-239`, `run*` — void) | `InfraOutcome = infraOk / infraChildCode(code: int) / infraUsageError` | the void + quits `:235,:239` |
| cache (`axiom_cache.nim:153-169`, `runCacheCli*` — void) | `CacheOutcome = cacheOk / cacheInputError / cacheCommandFailed` | the void; dispatcher `:119-120` silence |
| verify (`verify_cli.nim:158-245`, `runVerifyCli: int` {0,1}) | `VerifyOutcome = verifyAllPassed / verifyAnyMismatch / verifyStoreMissing / verifyNoClaims` | `return 0` at `:162-164`; remaining returns |
| prove/report (engine path) | existing `AxCommandCliResult.exitCode` {0,1} via `emitAxShortcutResult` | none — already contract-compliant |

Design point: none of these enums is `CliOutcome`. Each module exports its enum + a pure, unit-tested classifier used at the boundary (Part C Levels 1–2).

**Ordering rule D1 → D2**: no classification policy may be written before the D1 enums exist, else the {2,3,4} collisions propagate into the policy definition.

## D2 — Process-boundary classification: `DomainOutcome → ClassificationPolicy → TerminationInstruction`

Terms: `{SUCCESS, VERIFICATION_FAILURE, INVALID_INPUT, INTERNAL_ERROR, PASSTHROUGH_EXEMPT, CH_RATIFY}`. The policy function is per-domain and is the only bridge between a domain outcome and `CliOutcome`.

Per-domain policy candidates (explicit rows to ratify; no silent defaults):

| Domain outcome | Policy mapping (candidate) | Open consequence |
|---|---|---|
| release: released / dry-run preview | SUCCESS → 0 | — |
| release: no-bump / dirty worktree | **CH_RATIFY** — refused/environment, no `CliOutcome` bucket | §C.4 |
| release: missing/bad tag, semver line missing | INVALID_INPUT → 3 | — |
| cert: pass / verify fail | SUCCESS / VERIFICATION_FAILURE | — |
| cert: `JOURNAL_REQUIRED` | **CH_RATIFY** — no `CliOutcome` bucket (today 2 = INTERNAL) | §C.4 |
| topology: audit pass / audit fail / apply dry-run | SUCCESS / VERIFICATION_FAILURE | — |
| topology: rollback-failed | **CH_RATIFY** (today 2) | §C.4 |
| gate: pass / fail / usage | SUCCESS / VERIFICATION_FAILURE / INVALID_INPUT; child codes per D3 | — |
| check / shape / infra / cache | usage → INVALID_INPUT; pass/fail per domain; child per D3 | — |
| verify: all matched | SUCCESS → 0 | — |
| verify: any mismatch | VERIFICATION_FAILURE → 1 | — |
| verify: no store / empty store | **CH_RATIFY** — "invalid input" vs "0 verified" | §C.4 |

Rule: any policy outcome that cannot land in {0,1,2,3} is a **CH_RATIFY** row — never a silent remap (§0.3 trust-boundary rule).

## D3 — Subprocess policy: child exit codes are decided per child (no defaults)

| Child boundary | Child | Policy (DECIDED in D3) |
|---|---|---|
| `main.nim:89,105` | rebuilt successor | **PASSTHROUGH** (P4 bootstrap, contract-exempt) |
| `gate_cli.nim:42,58` | `gate_admin list/status` | clamp {0→gatePass, 1→gateFailure, other→INTERNAL_ERROR} |
| `gate_cli.nim:90` | `gate_hook <stage>` | clamp {0,1,2,3} via GateOutcome; out-of-range → INTERNAL_ERROR |
| `check_cli.nim:90` | `nim check` (external) | clamp {0→checkPass, 1→checkFail(VERIFICATION_FAILURE), other→INTERNAL_ERROR} |
| `infra_cli.nim:235` | `bootstrapCircleCI` (external) | clamp {0→infraOk, !=0→INTERNAL_ERROR} (operational, not verification) |
| topology executor (`topology_executor.nim:291`) | `./bin/ax` child | in-contract by construction after L3; mapped at `topology_cli.nim:234-259`, no raw forwarding |
| scaffold (audit §5 mentions a scaffold subprocess) | `runScaffoldCli` internals | **TO VERIFY at implementation**; do not default |

Rules: (1) every child boundary in code appears in this table before it ships; (2) a raw child code never reaches the process boundary — clamp via the domain policy or formal PASSTHROUGH (only `main.nim`); (3) external tools' codes are external results mapped by our policy, never merged into domain semantics.

## D4 — Void-command conversion (cache/check/infra/shape/check-spec)

Today five command surfaces are dispatched as `void` and their results ignored (`action_interpreter_cli.nim:119-120` cache, `:121-122` check, `:123-124` infra, `:125-126` shape, `:147-148` check-spec), so the dispatcher always falls through to `quit(0)` at `:204` — internal failures report success. D4 decides each returns an outcome:

| Command | void source | D4 decision |
|---|---|---|
| cache | `axiom_cache.nim:153` | `CacheOutcome`; unknown flags → `cacheUsageError` (kills the `ax cache --bogus` → 0 leak) |
| check | `check_cli.nim:53` | `CheckOutcome` |
| infra | `infra_cli.nim:223` | `InfraOutcome` |
| shape | `shape_cli.nim:91` | `ShapeOutcome` |
| check-spec | `check_spec_cli.nim:33` | `CheckSpecOutcome` |

**D4 rule**: no product command stays void; the interpreter guard becomes uniform (`if class != SUCCESS: …`), and the `:204` fall-through is deleted (L3).

## D5 — Dormant-code disposition (wf_state_vacuity + dead carrier types)

1. **`wf_state_vacuity`** — three-axis classification (A.5). **Decision by this design: QUARANTINE** — keep the module (live helpers), remove the mid-pipeline `quit(1)`, register the lost threshold-guard intent in `data/debt_registry.json` (§0.9a schema), and revisit "resurrect as a verify-prove domain guard" during D3/D5 ratification. A straight delete is rejected (module on live prove graph); a silent keep is rejected (§0.9).
2. **Dead carrier types** — `src/cli/cli_types.nim:28-40` (`VerifyWorkflowCliResult`, `VerifyTopologyCliResult`, `AuditProofBinaryCliResult`): zero references outside the declaration file (verified). **DECISION: DELETE** — AGENTS.md §0.8 (no dead carrier residue). Their only intended consumers were the P5-dead shortcut CLIs (also deleted).
3. **P5 shortcut CLIs + stubs** — `wf_runners.nim:96+`; `cmdEncodeSemanticPayload`/`cmdVerifySemanticPayload` stubs `quit(1)` at `:198,:202`; Z3-health quits at `:116,:119` inside the shortcut run/playbook — zero callers (verified). **DECISION: DELETE** per AGENTS §0.8.

---

# Part C — Layered architecture (presented as a TARGET, not a pre-verified conclusion)

## L1 — Level 1: command-domain outcome types, next to each command module

Each command module named in D1 owns:
- its domain outcome `enum type` (names per D1),
- `func classify(outcome: DomainOutcome): TerminationInstruction` (pure, unit-tested),
- **zero** `quit` calls — termination belongs to the boundary (L3).

The three abandoned carrier types are deleted (D5). No shared "mega-outcome" enum exists (D1 rule).

## L2 — Level 2: classification policy + full per-site mapping FIRST

Policy interface: `DomainOutcome → ClassificationPolicy → TerminationInstruction`. Implementations live beside the domain enums; the dispatcher consumes only `TerminationInstruction`.

**Per-site mapping workbook — every P1 `quit(` site** (this table, not the audit narrative, is the source of truth for the conversion diff):

| # | Site | After D1 (domain arm) | Term (target) |
|---|---|---|---|
| 1 | `action_interpreter_cli.nim:78` (report guard) | report outcome | classify → `exitWith` |
| 2 | `action_interpreter_cli.nim:82` (topology guard) | TopologyOutcome | classify → `exitWith` |
| 3 | `action_interpreter_cli.nim:86` (scaffold guard) | scaffold domain | classify → `exitWith` |
| 4 | `action_interpreter_cli.nim:90` (gate guard) | GateOutcome | classify → `exitWith` |
| 5-11 | `:94,:98,:102,:106,:110,:114,:118` (lint/cert/shadow/config/version/io/dag guards) | per-command domain | classify → `exitWith` |
| 12-14 | `:130,:134,:138` (git/cst/scope guards) | per-command domain | classify → `exitWith` |
| 15 | `:142` (release guard) | ReleaseOutcome | CH_RATIFY arms → `exitWith` |
| 16-19 | `:146,:152,:156,:160` (observability/baseline/invariants/vkd guards) | per-command domain | classify → `exitWith` |
| 20 | `:164` (verify guard) | VerifyOutcome | CH_RATIFY arms → `exitWith` |
| 21 | `:170` (budget guard) | per-command domain | classify → `exitWith` |
| 22 | `:174` (debt guard) | per-command domain | classify → `exitWith` |
| 23 | `action_interpreter_cli.nim:204` (fall-through `quit(0)`) | — | **deleted** (D4 guards make it dead) |
| 24 | `action_output_cli.nim:32` (`emitAxShortcutResult`) | AxCommandCliResult {0,1} | `exitWith` at boundary; emitter no longer quits |
| 25 | `cli_io_error.nim:13` (`die(code)`) | internal | `exitWith(INTERNAL_ERROR)` |
| 26-28 | `check_cli.nim:67,90,93` | CheckOutcome | per D2/D3 |
| 29-33 | `check_spec_cli.nim:40,43,61,81,92` | CheckSpecOutcome | per D2 |
| 34-36 | `shape_cli.nim:103,112,116` | ShapeOutcome | per D2/D3 |
| 37-38 | `infra_cli.nim:235,239` | InfraOutcome | per D2/D3 |
| — | `wf_state_vacuity.nim:164` (dormant; no longer counted in P1) | none (procedural quit inside a summary helper) | quit removed; Quarantine (D5) |

**Collapse target (to be verified, NOT established)**: the claim that the 38 P1 sites reduce to ~3 boundary calls — i.e. `exitWith(INVALID_INPUT)` (plan/parse, existing `:73`), `exitWith(INTERNAL_ERROR)` (engine path, existing `:183/:186`), and one `exitWith(classify(domainOutcome))` consumed by the single guarded post-command path — is a **target**. Verification protocol: (1) the workbook above maps 1:1 in the implementation diff; (2) a guard test enumerates all dispatcher exits and asserts they are exactly the L3 set; (3) the audit grep (`\bquit\(` over `src/cli/`) returns 0 outside `cli_outcome.nim` (the `exitWith` origin) and the recorded L3 sites. Until that passes, the collapse number is a hypothesis, not a fact.

## L3 — Level 3: single process boundary

- **`exitWith(CliOutcome)`** (`src/cli/cli_outcome.nim:37-38`) is the only process terminator in the product CLI; the mapping table at `cli_outcome.nim:18-27` remains the only `CliOutcome → int` map (INV-2 of the R7 contract).
- **Delete the `quit(0)` fall-through at `action_interpreter_cli.nim:204`** — without it, any future unguarded branch silently exits 0 (the audit §6 leak shape).
- **`CliOutcome` stays a 4-state presentation type — NO universal-enum collapse**: domain enums (D1) never merge into `CliOutcome`; the boundary only sees `CliOutcome`s produced by per-domain classifiers at L2 (audit §7.1 layered model).
- The canonical `cliQuit` arm (`action_interpreter_cli.nim:203`) remains the single pass-through for plan-produced codes; with INV1, its `quit(action.exitCode)` becomes `exitWith(outcomeForExitCode(action.exitCode))` via an inverse mapping (bijectivity INV7), with out-of-range codes treated as INTERNAL_ERROR.

## C.4 — The semantic-partition question is explicitly OPEN (separate ratification)

**NOT decided here.** The forced observable: some domain outcomes have no `CliOutcome` value — the "no bucket" class:

| Outcome | Today's code | Problem |
|---|---|---|
| release `roNoBump` | 3 | collides with INVALID_INPUT's 3 |
| release `roDirtyWorktree` | 4 | outside {0,1,2,3}; no value exists |
| cert `coJournalRequired` (JOURNAL_REQUIRED) | 2 | collides with INTERNAL_ERROR's 2 |
| topology `toApplyRollbackFailed` | 2 | same collision |
| verify no-claims (empty store, dir valid) | 0 | "0 verified" reported as success |
| verify `verifyStoreMissing` (bad dir) | 0 | "invalid input exits 0" (audit §6) |
| check `checkMissingSourceDir`, check-spec `specMissingInput` | 1 | environment/input ambiguity vs VERIFICATION_FAILURE |

Three candidate resolutions (for contract owners to ratify):
1. **Map to VERIFICATION_FAILURE (1)** — "requested work did not complete successfully"; simplest; loses the refusal/mismatch distinction.
2. **Ratify a new environment/refused class into the exit table** (e.g. `EnvironmentError → 3` or a reserved alias) — revises `docs/spec/productization_contract.md` lines 263-281 (contract revision is outside this document's authority).
3. **Keep the set excluded** — document the exact outcomes as excluded from the CLI boundary contract (the INV-5 signals pattern).

Until ratification, L2 rows marked CH_RATIFY must not silently commit to option 1 — that would collapse semantics the product contract has not ratified (trust-boundary §0.3).

# Open ratification questions

1. **Semantic partition** (§C.4): per-row decision among the 3 options; contract-level impact if option 2 (new class) is chosen.
2. **wf_state_vacuity disposition** — quarantine (recommended here) vs delete vs resurrect as an explicit VKD/domain floor on the verify outcome.
3. **Child-code clamp sets** — exact ranges for `nim check` / `bootstrapCircleCI` / `gate_hook` (external tools' exit codes are not contract-defined; clamp sets must be ratified with evidence).
4. **Carrier-type deletion** — confirm DELETE of the three `cli_types.nim:28-40` types is not blocked by any external consumer (none found in repo).
5. **verify no-claims vs bad-dir** — the partition question applied to `runVerifyCli`: missing store → INVALID_INPUT; empty store → "0 verified" (VERIFICATION_FAILURE, matching the `report` precedent at `report_engine.nim:25-31`).

---

## Appendix A — Source evidence (working tree @ 2026-08-19)

| Claim | Evidence |
|---|---|
| 83 direct `quit(` sites | `rg '\bquit\(' src/cli/` = 85 lines; minus 2 doc comments at `cli_outcome.nim:35-36` = 83 code sites. Per-file: action_interpreter 24 (incl. 203/204), action_output 1, axiom_status 1, check 3, check_spec 5, cli_io_error 1, cli_outcome 1, debug_mode 5, gate_admin 11 (incl. 113/119), infra 2, main 4, precompile_gates 3, run_gate 2, shape 3, subagent_orchestrator 12, wf_runners 4, wf_state_vacuity 1 → 83 |
| gate_admin BLOCK→2 at 113/119 | `gate_admin.nim:108-119` (`quit(rc)`, rc from `gate_admin_validate.nim:93` `return 2` on block: `:99,:116,:123,:131,:139,:149,:174`); `:297-298` self-test `quit(1)/quit(0)`; `:313-345` usage `quit(1)`; `runGateCli` delegation `gate_cli.nim:24-93` |
| `ax verify <bad-dir>` → 0 | `verify_cli.nim:158-164` (`return 0` on empty `readRecords`); no such path in wf_runners (dead) |
| `topology_cli.nim:204` = `return exitCode` | `commands/topology_cli.nim:166-204`; apply child path `:207-259` + `topology_executor.nim:274-292` (`axPath "./bin/ax"` at `topology_cli.nim:228`) |
| wf_state_vacuity:164 dormant | `:145-169` `recomputeAxProofStateSummary*`; zero external callers; all five intervening call sites sit in zero-call procs (wf_state/wf_semantic); module still on the live ax-prove graph via `axiom_engine` → `wf_state` and `main` → `ax_workflow_cli` → `wf_semantic` |
| release 54-57, 62-66 → 2 | `release_cli.nim:54-57` (no tag), `:62-66` (bad tag) |
| void commands | `axiom_cache.nim:153`, `check_cli.nim:53`, `infra_cli.nim:223`, `shape_cli.nim:91`, `check_spec_cli.nim:33` — all `proc ... (args: seq[string])` with no return type |
| dead carrier types | `cli_types.nim:28-40` (definitions only; grep across `src/` for the three names = zero uses) |
| audit untouched | `docs/design/r7_exit_authority_gap.md` not modified in this design cycle |

## Appendix B — Status / scope

- **Status**: DRAFT (Phase C design). No product code or test was modified by this document.
- **Relationship to the audit**: the Phase B audit remains the audit-of-record; this document is its corrective successor for the Part A items and ratifies the decision *order* (Part B) and the *target* architecture (Part C).
- **Decided here**: the five corrections (Part A), the decision order D1–D5 (Part B), the void-return decisions (D3/D4), and the disposition recommendations (D5). **Not decided here**: the semantic partition (§C.4) and the open ratification items — required before any L2 policy row tagged CH_RATIFY may ship.

---

*End of document.*
