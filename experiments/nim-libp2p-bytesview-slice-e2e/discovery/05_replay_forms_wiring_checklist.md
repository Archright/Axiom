# Investigation Report

## 0. The decisive subject fact (measured)

`<workspace>/nim-libp2p/libp2p/utils/bytesview.nim` (22 lines, **zero imports**):

```nim
type BytesView* = object
  data: seq[byte]
  rpos: int
proc init*(t: typedesc[BytesView], data: sink seq[byte]): BytesView = BytesView(data: data, rpos: 0)
template toOpenArray*(v: BytesView, b, e: int): openArray[byte] =   # :18
  v.data.toOpenArray(v.rpos + b, v.rpos + e - b)                      # :19
```

`seq.toOpenArray(first, last)` is **inclusive** → actual length = `(rpos+e-b) - (rpos+b) + 1` = **`e - 2b + 1`**; the inclusive-slice law wants **`e - b + 1`**. For `b=1, e=3`: actual **2**, law **3** — exactly the proposed `len(bv.toOpenArray(1,3)) == 2`.

Pin: HEAD `a130a7f32219909bdcda14b7f1e64d0804fc832c`, tree `ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841`, blob sha256 `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee`, porcelain clean.

**`toOpenArray` is a `template`, not a `func`** — this rules out the sidecar path (see §3c) and forces the d2-agent stamped-harness path.

---

## (a) Replay observation forms + openArray verdict

### The mechanism (`src/verification/counterexample_replay.nim`)

1. **Trigger**: only after P4 promotion `cvConfirmed → vsDisproved`, BMC lane, non-empty model — `src/verification/batch_uap/ir_pipeline_runner.nim:1605-1624` calls `replayConfirmedDisproof(subjectRepoRoot, ve.entry.sourcePath, ve.funcDef, result.verification.model, ve.parseBound)`.
2. **Harness synthesis**: writes `<state>/.axiom/tmp/replay/<digest16>/replay_harness.nim` (`counterexample_replay.nim:623-634`, `:988-1004`).
3. **Compile+run** (`buildHarnessCmd` `:935-974`):
   `nim c -r --hints:off --warnings:off --skipParentCfg --skipUserCfg --skipProjCfg --path:<moduleDir> --path:<repoRoot> --path:<repoRoot/src> --path:<repoRoot/tools> [--path:<dep>…] --nimcache:<harnessDir/nimcache> -o:<harnessDir/replay_harness_bin> <harnessPath>`
4. **Observation**: the value echoed **between `AXIOM_REPLAY_BEGIN` / `AXIOM_REPLAY_END`** markers (`extractObservedResult` `:480-495`).
5. **Agreement**: `parseConcreteLiteral(observed)` → `env["result"]` → `evaluatePostconditions` → `decideReplayVerdict` (`:465-478`): **agree ⟺ `propertyHolds == false`**.

### Every supported observation form

| Form | Supported? | Evidence |
|---|---|---|
| **int64 decimal** (e.g. `2`, `-7`) | ✅ | `parseConcreteLiteral` `:440-463` (`allCharsInSet({'0'..'9'})` + optional leading `-`) |
| **bool** (`true` / `false`) | ✅ | same, `:444-448` |
| arbitrary expression (string, float, seq, openArray) | ❌ | `parseConcreteLiteral` returns `none` → `rvUnavailable` (`decideReplayAgreement` `:1064-1068`) |
| **raised / not-raised** | ✅ but only as a *projected bool* | the d2 harness wraps the call in `try/except` and echoes `$observedReject` (template at `axiom_engine.nim:1364-1372`) |
| **return-value equality** | ✅ | int/bool return echoed between markers |
| **length of a returned openArray** | ✅ (see below) | echo `$expr.len` → an int literal |
| postcondition forms | literals, vars, `let`, `if`, casts, bv64 arith/compare/logic, `not` | `evalConcreteIr` `:380-425`; `irCall`/`irRecCall`/`irLoop`/`irCase`/string/float → `none` (fail-closed) |
| observation of a **non-int, non-bool** value | ❌ | — |

There are exactly **two harness forms**:

- **Plain** (`renderReplayHarness` `:542-568`): `include <module>` + `echo $funcName(args)`. `include` (not `import`) is load-bearing for private symbols (`docs/spec/replay_harness_config_quirks.md` Q6). **Observation = the raw return value `$`-string.**
- **Stamped / bespoke** (`ReplayConfig.harnessSource` `:94-99`): the overlay's template with `<module>` and `<lit>` placeholders (`ReplayModulePlaceholder` `:151`, `ReplayValuePlaceholder` `:155`); `<lit>` is replaced by the model literal at `counterexample_replay.nim:1322-1323`. Selected by `parseBound.replayHarnessTemplate.len > 0` (`:1303`). Requires `funcDef.params.len == 1` (`:1304-1307`) and the claim shape `<body> == <rhs>` (`:1235-1250`).

### Verdict on `len(bv.toOpenArray(1,3)) == 2` — **FEASIBLE, via the stamped path only**

- **The plain path CANNOT observe it.** `echo $bv.toOpenArray(1,3)` emits the *byte sequence* (a string), which `parseConcreteLiteral` cannot parse → `rvUnavailable`. Also `toOpenArray` is a template, so the plain `funcName(args)` call shape is wrong.
- **The stamped path CAN.** A harness template that echoes the **integer length** lands in the certified int form:

```nim
import libp2p/utils/bytesview
var bv = BytesView.init(@[1.byte, 2, 3, 4])
echo "AXIOM_REPLAY_BEGIN"
echo $(bv.toOpenArray(1, <lit>).len)     # -> "2"
echo "AXIOM_REPLAY_END"
```

  `$(...)` is required for unambiguous precedence; `BytesView.init` is exported (`:8`) and sets `rpos: 0`; `toOpenArray` and `BytesView` are exported, so `import` (not `include`) suffices.
- **Agreement arithmetic**: carrier body = the *actual* length `e - 1` (b fixed at 1); claim (β-spliced) = `(e - 1) == e`; the replay post derived by `d2AgentReplayPostcondition` (`:1235-1250`) = `result == e`. With `e = 3`: observed `2`, `2 == 3` → false → `propertyHolds == false` → **`rvAgree`** → BUG_FOUND. The observation, not the model, decides.
- **Imports needed**: **none beyond the subject module itself** — `bytesview.nim` has zero imports. Favorable.
- **Control carrier** (the UNSAT guard): `b = 0` → actual `e+1` = law `e+1` → claim `(e+1) == (e+1)` → always true → UNSAT.

**Wiring consequence**: the libp2p carrier must be a **constructed-IR carrier with exactly one model parameter** (like the d2 carriers), because `replayConfirmedDisproof` requires `funcDef.params.len == 1` (`:1304`). Two free slice indices cannot both be model-bound.

---

## (b) Minimal wiring checklist for `config/spec/nim_libp2p_bytesview_slice.json`

Two viable templates. **Template A (d2-agent clone) is the right one** given the template-vs-func issue.

| # | Touchpoint | Location | Action |
|---|---|---|---|
| 1 | Overlay path const | `src/cli/axiom_engine.nim:1349` (d2) / `:1833` (sidecar) | **new** `const NimLibp2pBytesviewSliceOverlayPath* = repoRootConst() / "config" / "spec" / "nim_libp2p_bytesview_slice.json"` |
| 2 | Overlay JSON | `config/spec/` | **new** file; `specOrigin:"soExplicit"`, `ruleId`, `ruleVersion`, non-empty `canonicalSpecIR` (required by `explicitSpecFromOverlay`, `src/core/trusted/specification_artifact.nim:68-97`); plus the d2-style `description`, `semanticCaveats`, `nonClaims`, `subject` pin, `carriers` grounding |
| 3 | Domain type + loader | `axiom_engine.nim:1624` (`loadTomlD2AgentOverlayDomain`) pattern | **new** `NimLibp2pBytesviewSliceDomain` + `loadNimLibp2pBytesviewSliceOverlayDomain()` (mirror `:1624-1750`) |
| 4 | Carrier names const | `axiom_engine.nim:1353-1362` | **new** defect/control carrier name consts (never subject symbols) |
| 5 | Replay harness template const | `axiom_engine.nim:1364-1380` | **new** — the stamped template with `<module>` + `<lit>` slots (see (a)) |
| 6 | `PreparedRun` field | `axiom_engine.nim:3912` / `:3916` | **new** `libp2pSliceOverlay*: Option[NimLibp2pBytesviewSliceDomain]` |
| 7 | Loader call site | `axiom_engine.nim:4126-4143` (d2) / `:4144-4175` (sidecar) | **new** block in `prepareProofRun`: presence-**optional** (absent → logged inert), present-but-malformed → fail-closed `err(...)` |
| 8 | `isEligible` branch | `axiom_engine.nim:4231-4278` | **new** branch: `if prepared.libp2pSliceOverlay.isSome and overlayDeclaresLibp2pSubject(..., fnName, modulePath): …` — **place it FIRST** (before the sidecar arm) or last; it is inert for other trees because it is gated on the exact `libp2p/utils/bytesview.nim` module path. Ordering matters only vs. an overlay governing the same symbol (none does) |
| 9 | Synthesizer | `axiom_engine.nim:2484-2663` (d2, **180 lines**) / `:2665-2900+` (sidecar) | **new** `synthesizeNimLibp2pBytesviewSliceCandidate` — clone the d2 shape: dedupe-by-census, resolver bytes fetch, `makeCarrier` inner proc, β-splice `irEq(irVar("result", retType), forbidIr)` with `substituteParamUse` + exactly-one-splice guard, free-variable guard, completeness bits, `saveEvidenceArtifact` + dual-write, `measureClaimCarrierParseBoundComponents`, **`parseBound.replayHarnessTemplate = <template>.replace(ReplayModulePlaceholder, domain.importModule)`**, census records, wave-facing defect entry, `logInfo` synthesis line |
| 10 | Target routing (only if `--target` names the *carrier*) | `axiom_engine.nim:4294-4312` + `d2AgentCarrierTargetRouting` `:1753-1771` | **new** routing func + branch — required only because a constructed-IR carrier has no subject-parse presence and resolves to zero frontier nodes |
| 11 | Replay dep resolution | `src/verification/counterexample_replay.nim:161-174` (`D2AgentSubjectDepPackages`), `:770-788` (`subjectTreeNeedsDepRoots`), `:790-811` (`resolveD2AgentDepSearchPaths`) | **⚠ required or risky** — see below |
| 12 | Contract doc | `docs/spec/` | **new** binding contract (d2 precedent `docs/spec/toml_d2_agent_binding_contract.md`; sidecar precedent `docs/spec/nim_stew_base36_sidecar_contract.md`) — required by §0.12 / §0.5 |
| 13 | Unit test | `tests/unit/test_<name>_binding.nim` | **new** standalone unit test (d2: `test_toml_d2_agent_binding.nim`; sidecar: `test_sidecar_binding.nim`). **Not** in `Makefile` `TESTS_FAST_UNIT` (`:63-97`) — those two are run ad hoc (`nim r …`), so no Makefile edit is required |
| 14 | Scope lock | `data/verification_scope.lock` | **no change** — external subjects bypass the kernel-scope filter (`src/core/topology/verified_frontier.nim:73-82`, `subjectMode = externalSubjectMode`) |

### (f) What is covered by existing generic code

- **Loader is content-generic.** `SidecarDomain.modulePath/symbol/valueParam` are *parsed from the JSON*, not hardcoded (`axiom_engine.nim:2173-2179`; the doc comment at `:1886` says "no subject names are hardcoded in the engine"). `explicitSpecFromOverlay` is generic (`specification_artifact.nim:68-97`).
- **BUT the const path is a hardcoded compile-time anchor** — pointing an existing const at a new file would repurpose that overlay's loader (and its grammar/validator). A 6th overlay needs its **own const + loader + domain type + synthesizer**.
- **The sidecar's closed grammar `nim-sidecar-expr-v1`** (`axiom_engine.nim:1837`, parser `:1919-2010`) supports only idents / non-negative int literals / `+` / `==` / parens — **no `*`, no `-`**. A `e-1` proposition is **outside** it. So the sidecar grammar would have to be extended (new grammar version) or the d2 constructed-IR path used.
- **The sidecar synthesizer CANNOT be reused as-is**: `synthesizeNimSidecarCandidates` requires the subject body to reference **exactly one** value parameter (`referencedParam`, `:2711-2725`) — `toOpenArray` references **two** (`b`, `e`) — and it materializes the subject body (a *template* is not a materializable `func`).
- **The d2-agent path is reusable nearly verbatim**, because `synthesizeTomlD2AgentCandidate` builds the carrier **in IR** (never materializes the subject) and the replay observes the original through a stamped harness.

### ⚠ The one real wiring hazard: dep-root resolution

`subjectTreeNeedsDepRoots(repoRoot)` (`counterexample_replay.nim:770-788`) walks the **entire subject tree** and returns true if *any* file names `serialization|faststreams|stew|results` (`D2AgentSubjectDepPackages`, `:161-162`). For nim-libp2p, **236 of 473 `.nim` files import `stew`** → the scan trips → the resolver attaches 4 unnecessary `--path:` roots, and if any is absent from the nimble store the replay **fails closed** with `rvUnavailable:subject dep resolution failed: …` (`:806-810`).

Measured on this host: `stew-0.5.0`, `serialization-0.5.4`, `faststreams-0.5.2`, `results-0.5.1` are all present in `~/.nimble/pkgs2` → it would *not* fail closed here, but the replay is coupled to the store for a zero-import module.

**Three ways out (pick one):**
1. Extend the overlay with its own `depPackages` list and make `resolveD2AgentDepSearchPaths` use it (cleanest, but touches the shared adapter);
2. Narrow the scan from "whole tree" to "the harness's actual import closure" (the harness only imports `libp2p/utils/bytesview`, which imports nothing);
3. Set `AXIOM_REPLAY_DEP_PATHS` explicitly (`:171-174`, `:742-768`) — but that is an env pin, not a code guarantee.

---

## (c) `AXIOM_STATE_DIR` seeding checklist

**Required before `ax prove --project` works:**

| Path under `<state>` | Required? | Evidence |
|---|---|---|
| `data/verification_scope.lock` | **REQUIRED (fail-closed)** | `resolveScopeLockPath` `axiom_engine.nim:3778-3784` → `loadKernelScope(..., failClosed = true)` `:4088`; `loadKernelScope` raises on missing/unreadable/no `kernel_symbols`/zero symbols (`src/core/proof/proof_integrity.nim:72-110`). **Copy the committed `data/verification_scope.lock` verbatim** (the sidecar experiment did exactly this — `ACCEPTANCE.md:111`); it needs `kernel_symbols` non-empty but **does not need the subject symbol** (external mode bypasses the filter) |
| `data/baseline.json` | optional | `readBaselineVkdFixed4` returns `""` when missing (`src/cli/shared/baseline_snapshot_core.nim:312-320`); read at `axiom_engine.nim:4333-4336` |
| `logs/` | created by the run | `stateJoin("logs", "ax_proof_state.json")` (`src/cli/wf_runners.nim:94-97`); trajectory `createDir` (`src/verification/unified_trajectory.nim:56-61`) |
| `.axiom/tmp/replay/<digest16>/` | created by the adapter | `counterexample_replay.nim:623-634`, `:990-994` |
| `.axiom/cache/evidence/<digest>.json` | created by the run | `src/infrastructure/evidence_artifact_io.nim:34-47` |
| `build/certificates/` (write vault) | created by the run **unless** `AXIOM_PROVE_VAULT_DIR` is set | `resolveVaultDirForWrite` `src/verification/cert_vault_role.nim:32-45` |
| `data/universe_merkle.lock`, `logs/global_symbol_graph.json`, `data/trusted/journal/`, `logs/z3_telemetry.jsonl` | created/read by the run | `src/core/proof/proof_universe_lock.nim:26-29`, `src/core/trusted/trust_commit.nim:79-83`, `proof_universe_commit.nim:307-310` |

**NOT required in the state dir:**
- `axiom.toml` — with `--project` it resolves to `<subject>/axiom.toml` if present, else the **Axiom repo's** (`axiom_engine.nim:4518-4524`).
- `config/spec/**` overlays — **repo-root anchored** via `repoRootConst()` (`axiom_engine.nim:1349`, `:1833`). The overlay always comes from the **Axiom repo**, never from the state dir or the subject tree.
- The subject tree itself — `--project <abs path>` (`axiom_engine.nim:4456`).

**Also required:** `AXIOM_STATE_DIR` must be set at all — `--project` without it is fail-closed: `stderr.writeLine("[AXIOM] --project requires AXIOM_STATE_DIR (fail-closed, §10.3): no state written"); quit(1)` (`axiom_engine.nim:4459-4465`).

**Reference command** (`ACCEPTANCE.md:4`):
```
AXIOM_STATE_DIR=<exp>/state_dN AXIOM_PROVE_VAULT_DIR=<exp>/vault_dN \
  bin/ax prove --project <subject-abs-path> --target "<module>::<symbol>"
```

---

## (d) Expected observable outputs (acceptance evidence)

### stdout / stderr / exit code
- **stdout: 0 bytes** (report is projected to state logs + stderr) — `ACCEPTANCE.md:40`.
- **stderr** carries the `[ce-replay]` line.
- **exit code 1** = `CliOutcome.VERIFICATION_FAILURE` (`src/cli/cli_outcome.nim:31-32`); `runOutcome.verdict=FAIL`, `gateVerdict=FAIL`.

### The two `[ce-replay]` log lines (`ir_pipeline_runner.nim:1611-1624`)

Success — exact format:
```
[INFO] ir_pipeline_runner: [ce-replay] <funcDef.name> — replay agreed; BUG_FOUND payload assembled (<N> records)
```
Failure — exact format:
```
[INFO] ir_pipeline_runner: [ce-replay] <funcDef.name> — replay <diagnostics>; fail-closed cvUnresolved
```
`diagnostics` is `$replay.verdict & ":" & replay.diagnostics` (`counterexample_replay.nim:1348`), e.g. `rvUnavailable:harness nonzero exit 1`, `rvUnavailable:subject tree drifted during replay (hash/porcelain mismatch)`, `rvDisagree:property holds on observed result — replay disagrees with solver model`.

### The 13-record counterexample payload (`counterexample_replay.nim:512-536`, `:1358-1360`)
1. `input.<param>=<lit>`
2. `propertyViolated=<SMT>`
3. `replay.verdict=rvAgree`
4. `replay.exitCode=0`
5. `replay.subjectGitRef=<sha>`
6. `replay.treeMerkle=<sha>`
7. `replay.moduleSha256=<sha>`
8. `replay.moduleSha256AfterRun=<sha>`
9. `replay.porcelainClean=true`
10. `replay.nimVersion=Nim Compiler Version 2.2.10 [Linux: amd64]`
11. `replay.nimHash=<sha>`
12. `replay.stdlibHash=` (empty on this host)
13. `replay.hostPlatform=linux-amd64`

For the libp2p slice, `replay.subjectGitRef` = `a130a7f32219909bdcda14b7f1e64d0804fc832c`, `replay.treeMerkle` = `ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841`, `replay.moduleSha256` = `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee`.

### Where the artifacts land

| Artifact | Path | Grep target |
|---|---|---|
| canonical run digest | `<state>/logs/ax_proof_state.json` → **top-level `.canonicalRunDigest`** | `run_accounting.nim:1422`; persisted by `axiom_engine.nim:738` |
| accounting/outcome digests | `<state>/logs/ax_prove_trajectory.jsonl` → the `run_result` event's `extra.runAccountingDigest` / `extra.runOutcomeDigest` / `extra.canonicalRunDigest` / `extra.gateVerdict` / `extra.verdict` | `axiom_engine.nim:3980-3989` |
| claim rows + payload | `<state>/logs/ax_prove_trajectory.jsonl` | `claimId`, `evidenceId`, `obligationId`, `specificationId`, `claimOutcome=clDisproved` |
| certificate JSON | `<vault>/<irHash>.json` (e.g. `<state>/build/certificates/` or `$AXIOM_PROVE_VAULT_DIR`) — `counterExample` is the **pre-existing** slot (`src/engine/proof_certificate.nim:65`), populated at `ir_pipeline_runner.nim:1612`, projected at `:1937` | `.counterExample` |
| vault manifest | `<vault>/manifest.json` → `entries[]` with `modulePath`, `functionName`, `status` (`certZ3Candidate` vs `certRed`), `solverMethod`, `lastVerifiedAt`, `irHash` | — |
| evidence CAS | `<state>/.axiom/cache/evidence/<digest>.json` | — |
| z3 telemetry | `<state>/logs/z3_telemetry.jsonl` | — |

### How the `29db1e36…` digests were extracted
The two-cold-run determinism check reads **`canonicalRunDigest` from `<state>/logs/ax_proof_state.json`** (top-level key) — that is the only one of the three that is a top-level report key; `runAccountingDigest`/`runOutcomeDigest` exist **only** in the trajectory event's `extra` block. `canonicalRunDigest` = `sha256Hex(canonicalSerialize(runResult))` (`src/verification/accounting/run_accounting.nim:1198-1201`).

**Honest caveat already recorded in `ACCEPTANCE.md:97`**: these digests cover **run-accounting shape** (waves/terminals/counts), not payload bytes — the same three values also appear in the 2026-10-10 C_out slice. For the libp2p run, d1↔d2 payload-level byte equality must be established **independently** (claim maps + CAS files), as the sidecar acceptance did.

### Expected libp2p-specific values
- `input.<e>=3` (or whatever the model binds — the solver picks the smallest satisfying value; **do not hard-code 3**).
- `propertyViolated=(= (bvsub e #x…01) e)` — the SMT projection of `(e-1) == e` (`irExprToSmt`).
- `replay.verdict=rvAgree` with the observed value `2` (actual) vs the law `e` (expected).
- Control carrier: UNSAT, absent from the FAIL rows, vault row `certZ3Candidate` with **no** `certRed`.

---

## Risks to flag before you commit to this

1. **`toOpenArray` is a `template`.** The whole "materialize the subject body and carry it" machinery (sidecar path) does not apply. The d2 constructed-IR + stamped-harness path is the only viable one — and it means the **solver verifies an adopted model, not the subject's body** (the same honest limit the d2 contract records at `docs/spec/toml_d2_agent_binding_contract.md` §3).
2. **The claim `(e-1) == e` is violated for *every* `e`.** The "defect" is a pure off-by-`2b` in the index arithmetic, not an input-specific bug. A domain precondition (e.g. `1 <= e`, `e <= data.len-1`) is needed to keep the model meaningful, and the control (`b = 0`) must be genuinely UNSAT for the differential to mean anything.
3. **Two free indices cannot both be model-bound** (`replayConfirmedDisproof` requires `funcDef.params.len == 1`, `counterexample_replay.nim:1304`). One index must be fixed in the constructed body — `b = 1` for the defect, `b = 0` for the control. That is a *narrowing* of the claim and must be stated in the contract's non-claims.
4. **The dep-root scan** (§b, item 11) is a real coupling to the host nimble store for a zero-import subject. It will not fail closed on this host, but it is a portability/Determinism smell.
5. **Zero-Footprint**: the subject repo's `git status --porcelain` must be empty at replay time (`counterexample_replay.nim:1028-1040`) — the libp2p clone currently is clean, and it must stay that way (never materialize a variant in the subject tree; `docs/spec/replay_harness_config_quirks.md` Q2 records that a dirty subject tree silently forces `cvUnresolved`).
6. The **exact-input gate** (`counterexample_replay.nim:1275-1284`) requires the model to bind **every** carrier parameter — with a one-parameter carrier this is trivially satisfiable, but it means the carrier must not carry extra formals.