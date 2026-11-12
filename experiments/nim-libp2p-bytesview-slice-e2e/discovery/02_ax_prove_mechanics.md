## `ax prove` — mechanical model

### 1. Entry point and control flow

| Step | Location |
|---|---|
| Help text ("Scan source, prove top targets, and auto-heal remaining nodes until VKD reaches 1.0000.") | `src/cli/action_plan_cli.nim:21-27` |
| `"prove"` → `axSubcommandProve` | `src/cli/action_plan_cli.nim:169-172` |
| Dispatch → `cliRunAxiomEngine` → `runAxiomEngineCli` | `src/cli/action_interpreter_cli.nim:197-218` |
| `runAxiomEngineCli` (the real entry) | `src/cli/axiom_engine.nim:4434` |
| Flag parse | `src/cli/cli_surface_generated.nim:21-82` (type at `src/cli/cli_types.nim:171`) |
| `buildProofTask` (flags → domain task) | `src/cli/axiom_engine.nim:250-268` |
| `runProofPipeline` | `src/cli/axiom_engine.nim:4355` |
| `prepareProofRun` | `src/cli/axiom_engine.nim:4101` |

**The help text is wrong about the surface.** The real flag set is `--limit --target --project --plan --workers --smt-timeout --replay --converge --strict-uf --strict-induction --verify-ir-hash --update-lock --legacy-uap`. Of these, `--replay/--converge/--strict-uf/--strict-induction/--verify-ir-hash` are parsed and then **never read** (dead flags). The two that matter for the external-repo question are `--project` and `--target`.

### 2. "Scan source" — what is actually scanned

`prepareProofRun` → `analyzeSubjectSource` (`src/cli/axiom_engine.nim:3835`) → `analyzeTopologySourceRoot` (`src/cli/topology_cli.nim:359`) → `analyzeTopologySourceRootIncremental` (Merkle-cached incremental parse).

- **File filter** (`src/core/topology/node_filter.nim:20-33`): `*.nim` and `*.nims` only; excludes `nimcache, .nimcache, .nimcache_gate_hook, build, .lake, vendor, .git, logs, bin, node_modules, semantic_proofs, verifications, experimental`.
- **Root** = `getCurrentDir()` by default, or the `--project` dir when given (`src/cli/axiom_engine.nim:4550-4551`).
- There is **no registry of "files to scan"** — the scan is a filesystem walk of the subject root. The *registry* (§4) governs what is **provable**, not what is scanned.

### 3. "Top targets" — selection and ranking

1. `hydrateRunVault` (`src/cli/axiom_engine.nim:4079-4093`) loads the scope lock **fail-closed** and hydrates the verified set from the canonical vault `data/trusted/certificates/`.
2. `computeInitialFrontier` → `computeVerifiedFrontier(..., subjectMode = externalSubjectMode)` gives unverified nodes in topological order.
3. `--target` filter is applied **first**, on the pre-eligibility frontier (`src/cli/axiom_engine.nim:4288-4290`, `prepared.computeLimit` is forced to 0 when a target is present — `:4195`).
4. **Eligibility gate** (`src/cli/axiom_engine.nim:4212-4280`):
   - registry hit → `isRegistryEligible` (`:837`);
   - registry miss → **overlay-governed candidate synthesis** (sidecar / base36-C_out / base36-relational / base32-rem / d2-agent);
   - otherwise → `classifyExternalCandidate` (`:3454`), which materializes the symbol from the subject source and census-classifies it.
5. `rankBySelectionScore` (`:3812-3833`) — score = `1/(count+1)`, least-proven first, tie-break by node-id string.
6. `--target` on a canonical `module::symbol` that resolves to ≠1 node is **fail-closed**: `canonicalTargetRefusal` (`:4026-4038`).

### 4. "Auto-heal" — it does **not** modify source

`runVerificationWaves` (`src/cli/axiom_engine.nim:3653-3753`) is a **dependency-fixpoint wave loop**: up to 64 waves, each node attempted at most once, the frontier recomputed after each wave so newly-dependency-satisfied nodes get picked up. No `.nim` file is written; nothing is edited. "Auto-heal" in the help text is a misnomer for this loop.

### 5. Proof pipeline: Nim → Lean

- **Nim → IR** happens at *compile time* in the `axiomImpl`/`axiomTryImpl` macro (`src/core/trusted/axiom_pragmas_macros.nim:700-712`), stored in `runtimeAxiomRegistry` via `generateAxiomInit` (`:827-840`). For external subjects the IR is materialized at *runtime* from subject source by `materializeExternalIR` (`src/cli/axiom_engine.nim:3460`).
- **IR → Lean**: `irToLeanModule` (`src/core/trusted/ir_to_lean.nim:674-698`) emits `import Init` / `import Std.Tactic.BVDecide`, a `def`, then `theorem <fn>_post<N> (params) : (let result := <fn> …; <prop>) := by unfold <fn>; <tactic>` (`irFuncDefToTheorem`, `:598-624`), then `#print axioms <fn>`.
- **Lean is really invoked**: `canonicalLeanKernelCheck` (`src/verification/obligation/lean_kernel_boundary.nim:370-514`) writes the source to `<tmp>/axiom_kc_<sha256>.lean` and runs `lake env lean --threads=1 <file>` (or `$AXIOM_LEAN_CMD`); a receipt is issued **only on exit 0**. Called from `src/verification/batch_uap/loop_driver.nim:270`.
- **Z3 is the other leg**: `runZ3CheckViaIR` (`src/verification/batch_uap/ir_pipeline_runner.nim:304`), BMC; the Lean source is generated for cross-check (`ir_pipeline_runner.nim:1324-1330`).
- A real, checked theorem from the vault (`data/trusted/certificates/152607ea….json`):

  ```lean
  theorem axiom_continuity_probe_sanity (x : Int) (r : Int)
      (h1 : r = if x * 2 > 100 then 0 else x * 2)
      (h2 : x * 2 > 100) :
      r = 0 := by
    simp [h1, h2]
  ```
- `proofs/` is a *separate* Lean project (`proofs/lakefile.lean`, toolchain `leanprover/lean4:v4.33.0`) holding gate invariants and IR-level proofs. `ax prove` builds it via `runLeanVerifyBlock` → `verifyWithSandbox` (`src/cli/lean_verify_cmd.nim:103`), but **skips it entirely in external-subject mode** (`src/cli/axiom_engine.nim:4394-4400`).

### 6. Inputs / outputs / exit codes

**Inputs**: `axiom.toml` (`[prove] vault_dir`, `budget_gas`; `[leanstral] api_url/model/api_key` → `AXIOM_LLM_API_URL/MODEL/API_KEY`), env `AXIOM_STATE_DIR`, `AXIOM_PROVE_VAULT_DIR`, `AXIOM_PROVE_WORKERS`, `AXIOM_SMT_TIMEOUT`, `AXIOM_LEAN_CMD`.

**Outputs written** (all routed to `AXIOM_STATE_DIR` when set, else CWD-relative — `stateJoin`, `src/verification/cert_vault_role.nim:8-14`):

| Artifact | Path | Writer |
|---|---|---|
| proof state | `<state>/logs/ax_proof_state.json` | `persistAxProofState` (`src/cli/axiom_engine.nim:4351`) |
| trajectory | `<state>/logs/ax_prove_trajectory.jsonl` | `logStage` (`src/verification/unified_trajectory.nim:44-61`) |
| symbol graph | `<state>/logs/global_symbol_graph.json` | `commitUniverseIntegrityAndLock` (`src/verification/proof_universe_commit.nim:266-287`) |
| z3 telemetry | `<state>/logs/z3_telemetry.jsonl` | solver layer |
| evidence CAS | `<state>/.axiom/cache/evidence/*.json` | evidence_cas |
| certificates (write) | `<state>/build/certificates/` (default) or `$AXIOM_PROVE_VAULT_DIR` | `resolveVaultDirForWrite` (`src/verification/cert_vault_role.nim:32-45`) |
| certificates (read) | `data/trusted/certificates/` | `resolveCertificate(cvRuntimeCanonical)` |
| universe lock / journal | `<state>/data/proof_universe.lock`, `<state>/data/trusted/journal/*.json` | `commitUniverseIntegrityAndLock` |

**Exit codes** (`src/cli/cli_outcome.nim:25-36`): `0` success · `1` verification failure (≥1 failed node) · `2` internal error · `3` invalid input · `4` NOT_CURRENT. Failure semantics are **fail-closed**: a failed proof yields exit 1 and a `clDisproved` claim with a replayed counterexample; a solver/Z3 SAT is promoted only after a counterexample replay agrees against the subject's own body (`[ce-replay] … replay agreed`).

**Certificate content** (`axiom.certificate.v3`): `claim` (functionName, modulePath, status, type), `leanSource` + `leanSourceHash`, `smtlib2`, `solverInputDigest`/`solverResultDigest`/`solverStatus`, `irHash`, `sourceHash`, `kernel`, `toolchainIdentity` (`nim-2.2.10|lean-4.33.0|z3-4.13.3`), `translationVersion`, `verificationTier`, `winningStrategy`, `provenance` (journal ref), `attestation` (Ed25519), `scopeDigest`, `policyDigest`, `envDigest`, git `baseSha`/`headSha`/`headTreeDigest`, `prNumber`.

### 7. Scope mechanism (the decisive part)

- `data/verification_scope.lock:1` — 40 `kernel_symbols`, **all under `src/` of the Axiom repo**; `kernel_exempt_symbols` (17) → `vksTotal = 23`; `rust_targets` is a separate additive denominator.
- The registry is populated at **compile time** by the `axiomImpl` macro and materialized at runtime by `collectKernelSymbols` (`src/core/trusted/axiom_pragmas_procs.nim:66-90`) — note it **drops any entry whose path is not under `src/`** (`:74-85`).
- `ax scope lock` merely re-derives that same registry into the lock file (`src/cli/scope_cli.nim:14-80`); `ax scope` (default) does a read-only two-way set comparison.
- The lock path is resolved from the **Axiom/state root, not the subject** (`resolveScopeLockPath`, `src/cli/axiom_engine.nim:3778-3784`).

⇒ **Adding an external file to the kernel scope is not a data operation.** It requires the external file's Nim source to be compiled *into the `ax` binary* with an `axiomImpl`/`axiomTryImpl` annotation — i.e. vendoring it into Axiom's `src/` and rebuilding. There is no runtime path that widens `kernel_symbols` to an outside path.

### 8. Determinism & caching

- **Scope/baseline snapshot frozen at start** — no mid-run re-read (`src/cli/axiom_engine.nim:4331-4336`; end-of-run disk re-derivation of the scope digest as a freshness guard at `:4385-4389`).
- **Global symbol graph reuse** — `loadOrBuildGlobalSymbolGraph` (`src/verification/global_symbol_graph.nim:44-84`): reuse only if `GraphInputFingerprint` (source Merkle) matches **and** the stored snapshot passes schema validation; any doubt → full rebuild, fail-closed. Cache file `logs/global_symbol_graph.<sha256(repoRoot)>.cache.json`.
- **Topology Merkle cache** — incremental re-parse keyed on Merkle root (`src/cli/topology_cli.nim:370, 402`).
- **Same-run IR memo** — `Table[string, IrPipelineResult]` per worker, process-lifetime only, never cross-invocation (`src/verification/batch_uap/ir_pipeline_runner.nim:1491-1493, 1578-1625`).
- **Selection state** — `.axiom/cache/node_selection_state.json` drives the ranking counts (this is the one cache that legitimately changes *which* nodes are picked, so run-to-run target order can differ).
- **Known non-determinism**: `ax_proof_state.json` embeds wall-clock timestamps in `depthStats` — raw file digests differ between identical runs; the canonical `canonicalRunDigest` / `runAccountingDigest` / `runOutcomeDigest` are the reproducible projections (`experiments/act2-wp2-subject-scoped-execution/wp2-result.md:140`, `experiments/sidecar-adoption-e2e/ACCEPTANCE.md:5`).
- `build/nimcache_memo_baseline/` is **not** a proof-memo artifact — it is a Nim C-compile cache directory.

---

## End-to-end model of ONE `ax prove` run

```
ax prove [--limit N] [--target T] [--project DIR] [--plan P] …
│
├─ parseAxProveFlags                         src/cli/cli_surface_generated.nim:21
├─ [if --project] absolutize DIR, require it to exist, require AXIOM_STATE_DIR
│                                             src/cli/axiom_engine.nim:4451-4465
│   ├─ [if DIR/Cargo.toml] → Rust lane, whole Nim pipeline skipped   :4471-4480
│   └─ setExternalSubjectMode(true)                                  :4497
├─ load axiom.toml ([prove],[leanstral]) → env                       :4515-4542
├─ generateAxiomInit()  ← compile-time registry → runtime registry   :4508
├─ buildProofTask(flags)                                              :250
├─ runProofPipeline(task, cwd=DIR|getCurrentDir())                    :4355
│  └─ prepareProofRun                                                :4101
│     ├─ load 5 out-of-tree spec overlays (config/spec/*.json) fail-closed  :4111-4175
│     ├─ analyzeSubjectSource → topology scan (walk .nim/.nims)       :3835
│     ├─ hydrateRunVault: load scope lock (fail-closed) + verified set  :4079
│     ├─ computeInitialFrontier (topological, unverified)              :4095
│     ├─ selectFrontierNodes: --target filter → eligibility gate → limit :4289
│     │    eligibility = registry hit | overlay synth | external census
│     ├─ rankBySelectionScore (1/(count+1))                           :3812
│     └─ persist pre-loop skeleton to <state>/logs/ax_proof_state.json  :4351
│  └─ runVerificationWaves  (≤64 waves, dependency fixpoint)          :3653
│     └─ runOneWave → runBatchVerification                            :304
│        ├─ thread: selectProofCandidates + IR pipeline                :353-377
│        │    per entry: irToLeanModule → Lean source                 ir_pipeline_runner.nim:1324
│        │                runZ3CheckViaIR (BMC)                       ir_pipeline_runner.nim:304
│        │    batch: runLeanVerification → canonicalLeanKernelCheck   loop_driver.nim:270
│        │            → `lake env lean --threads=1 <tmp>.lean`         lean_kernel_boundary.nim:451
│        │            → receipt only on exit 0
│        └─ persist certificates to <state>/build/certificates (write) / data/trusted/certificates (read)
│  ├─ closure evaluation + re-read scope lock from disk                :4385
│  ├─ [if NOT externalSubjectMode] lake build proofs/ (lean-verify)   :4396
│  └─ renderLegacyReport + renderPersist                             :4411-4429
├─ loadOrBuildGlobalSymbolGraph(cwd)  (Merkle-fingerprint reuse)       :4570
├─ commitUniverseIntegrityAndLock → graph snapshot, proof_universe.lock,
│    TrustCommit journal, audit flush                                 :4575
└─ emit report JSON (stdout) + exit code                              cli_outcome.nim:25
```

---

## Verdict: is there a supported path for an external repo?

**Yes — one, and it is not the kernel-scope path.** It is the *external-subject + explicit out-of-tree spec overlay* path.

**What you must do (all mechanical, all in-repo Axiom edits):**

1. **Author an Axiom-owned spec overlay** in `config/spec/` declaring the subject module + symbol + the proposition (`canonicalSpecIR`) with `"specOrigin": "soExplicit"`, `ruleId`, `ruleVersion`, `claimOwnership`, and (for the sidecar variant) a **hash-bound adoption record** pinning the subject module's `blobSha256`. Schema precedent: `config/spec/nim_stew_base36_sidecar.json`; contract: `docs/spec/nim_stew_base36_sidecar_contract.md`.
2. **Wire the overlay into the loader.** The overlay set is a **fixed const list of 5 paths** — `Base36SizingOverlayPath` (`src/cli/axiom_engine.nim:860`), `Base32RemOverlayPath` (`:1033`), `Base36CoutOverlayPath` (`:1179`), `TomlD2AgentOverlayPath` (`:1349`), `NimSidecarOverlayPath` (`:1833`). A sixth subject needs a code change (new const + a branch in `isEligible`, `src/cli/axiom_engine.nim:4231-4278`). The generic **sidecar** loader (`synthesizeNimSidecarCandidates`, `:2665`) is the right template — it is subject-agnostic; the 5 overlays are just the currently-declared subjects.
3. **Run with state isolation** (mandatory; `--project` without `AXIOM_STATE_DIR` exits 1 immediately, `:4463-4465`):
   ```bash
   AXIOM_STATE_DIR=<state> AXIOM_PROVE_VAULT_DIR=<vault> \
     bin/ax prove --project <workspace>/nim-libp2p \
       --target "<module>.nim::<symbol>"
   ```
   `<state>/data/verification_scope.lock` must be seeded from the committed lock (the engine resolves the scope from the state root, `:3778-3784`); a fresh state dir without `data/` yields exit 2.
4. **Use a canonical `--target`** (`module::symbol`) — the refusal is fail-closed on ≠1 match (`:4026`).

**Precedent — this path has been run and frozen-accepted against an external repo.** `experiments/sidecar-adoption-e2e/ACCEPTANCE.md` (2026-10-19) judges exactly this command against nim-stew: exit **1** (VERIFICATION_FAILURE) with a real 13-record counterexample replayed against the subject's own body, control carrier UNSAT, subject tree byte-identical pre/post (95 files), and `canonicalRunDigest` **identical across two cold runs**. The earlier `experiments/act2-wp2-subject-scoped-execution/wp2-result.md` records the same shape for nim-stew with `solverInvocationCount=1` and status `timeout`/`unknown` (i.e. *reached* the solver, not *proved*).

**What you must NOT expect:**
- The external symbol does **not** enter Axiom's kernel scope, so **VKD is unaffected** — VKD's denominator is `vksTotal = 23` from `data/verification_scope.lock` and its numerator is `certGreen` in `data/trusted/certificates/` (`docs/spec/verification_density.md:170-174`). The CLI help's "until VKD reaches 1.0000" is aspirational; nothing in an external run moves it.
- `proofs/` is not built in external mode (`:4396`), so the Lean-gate-invariants project is irrelevant to an external subject; the per-symbol Lean check (`canonicalLeanKernelCheck`) still runs.
- The proposition must come from Axiom's overlay, not from the subject repo — the subject tree is read-only (Zero-Footprint).
- Candidates are rejected fail-closed for: lossy IR translation (`translationLossFree=false` → `censusEligible=false`), constant-divisor/tautology obligations, and unresolved semantic facts (`src/verification/obligation/candidate_eligibility.nim:455-507`).

**Cost estimate for libp2p (473 `.nim` files):** the scan is a full walk of the subject, and only symbols an overlay declares can become eligible — the overlay is the actual work, not the CLI invocation. A `libp2p` overlay needs a new const + a branch in `isEligible` (a source change to `src/cli/axiom_engine.nim`, which is **not** on the §-1 protected list).