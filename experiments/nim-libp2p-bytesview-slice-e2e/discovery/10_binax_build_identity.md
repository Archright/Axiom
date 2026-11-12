Investigation complete. Here is the full report.

## (a) Official build commands

### `bin/ax` — entry source is `src/cli/main.nim`

There are four distinct recipes in the repo. All use the same entry module; they differ in flags.

**CI canonical** — `ci/checker.mk:529-530`, reached via `make ci-bootstrap` (`ci/checker.mk:538-541`) from `.github/workflows/admission-check.yml:472` (`make ci-bootstrap`):
```make
ci-compile-ax:
	AXIOM_HERMETIC_BUILDING=1 $(NIM) c -d:release --hints:off --nimcache:$(CI_COMPILE_NIMCACHE)/ax -o:bin/ax src/cli/main.nim
```
`make -n -f ci/checker.mk ci-compile-ax` expands to exactly:
`AXIOM_HERMETIC_BUILDING=1 nim c -d:release --hints:off --nimcache:build/nimcache/ci-compile/ax -o:bin/ax src/cli/main.nim`

**Makefile `build`** — `Makefile:943-946`, used by `.github/workflows/axiom-operational-slice.yml:43` (`run: make build`):
```make
build: $(METADATA) ## 전체 CLI 빌드 (nim check)
	$(NIM) c --hints:off -d:allowMissingZ3 -o:bin/ax src/cli/main.nim
```
No `-d:release` — this is a **debug** build (consistent with the 26 MB `bin/ax`).

**Makefile G7 release E2E** — `Makefile:804-807` (the one that already emits binary identity):
```make
verify-contract-release-e2e:
	$(NIM) c -d:release --hints:off --nimcache:$(VC_NIMCACHE_g7) -o:bin/ax src/cli/main.nim || exit 1
	@echo "  -- executable identity:"; sha256sum bin/ax
```

**nimble** — `axiom.nimble`: `task build` runs `nimble hermetic` first, then `nim c -d:release -o:bin/ax src/cli/main.nim`; `task devBuild` adds `AXIOM_FAST_BUILD=1 AXIOM_HERMETIC_BUILDING=1` and also builds `bin/axiom-gate` + `bin/precompile_gates`. (`src/bin/ax.nim` is a nimble *package* shim for the `bin = @["bin/ax", "bin/run_gate"]` declaration — it is not what `make build` compiles.)

**Recommendation for the runbook:** use the release form, since the G7 acceptance path and CI both use it:
```
nim c -d:release --hints:off -o:bin/ax src/cli/main.nim
```
The critic's point is correct in substance but the *current* binary is not stale (see (c)).

### The three tools — validation of the prior agent's proposals

| Binary | Prior proposal | Verdict | Authority |
|---|---|---|---|
| `derive_checker_closure` | `nim c --hints:off --skipParentCfg --skipProjCfg --noNimblePath --path:src -o:bin/derive_checker_closure tools/ci/derive_checker_closure.nim` | **Correct except `--noNimblePath`**, which CI does not use. **There is no Makefile target** for it. | `.github/workflows/admission-check.yml:511-512` |
| `axiom-gate` | `nim c -d:release -o:bin/axiom-gate src/gate/gateway.nim` | **Correct.** No Makefile target exists. | `axiom.nimble:60`; `docs/agents/operations.md:250` |
| `debt_engine` | `nim c -d:release -o:bin/debt_engine tools/debt_engine.nim` | **Wrong** — matches neither recipe. | `Makefile:154-155`, `Makefile:1211` |

Exact Makefile recipes:
```make
Makefile:154-155
bin/debt_engine: $(DEBT_AUDIT_SRCS)
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

Makefile:1211   (pre-commit step 1/5)
	@$(NIM) c -d:release $(NIM_TOOL_FLAGS) -o:bin/debt_engine tools/debt_engine.nim
```
`make -n -B bin/debt_engine` expands (`NIM_TOOL_FLAGS` = `Makefile:22`) to:
```
nim c --hints:off --skipParentCfg --skipProjCfg --path:<user-home>/.choosenim/toolchains/nim-2.2.10 --path:. --path:src --path:tools --path:<pkgs2/checksums-0.2.2-...> --path:<pkgs2/fusion-1.2-...> -o:bin/debt_engine tools/debt_engine.nim
```
Note `--skipProjCfg` means `config.nims` does **not** run for this one.

## (b) Build identity — `axiomRevision` is dead; the real mechanism is SourceCoherence

**`axiomRevision` is unusable.** `src/cli/axiom_engine.nim:4488-4490`:
```nim
discard VerificationRun(
  subject: subjectForRuntimeMeta,
  axiomRevision: AxiomEngineVersionHash,
  ...
```
The value is constructed and **immediately discarded** — it reaches no output. `AxiomEngineVersionHash` itself is a compile-time const (`src/core/utils/constants.nim:53`): `"v0.5.0-dev-" & BuildEnvGitHash[0..6]`, where `BuildEnvGitHash` lives in `src/generated/build_env.nim:13`.

**The load-bearing mechanism is the src-tree hash (`BuildSourceHash`):**

- `src/core/utils/build_provenance.nim:41-50` — `hashSourceContents`: sort `src/**/*.nim` by relative path (excluding `src/generated/`), concatenate, `$hash()`. Build-time twin: `tools/hermetic_build.nim:851-866` `computeDeterministicSourceHash`.
- `src/generated/build_env.nim:18` — `BuildSourceHash*` is the value compiled into the binary.
- `src/cli/main.nim:69-74` — **every `bin/ax` run** recomputes the live tree hash and compares it to the embedded one:
  ```nim
  let srcHash = computeSourceTreeHash(projectRoot / "src")
  if srcHash == BuildSourceHash: return
  stderr.writeLine("[FATAL] Engine source/source mismatch (SourceCoherence FAIL) tree=" & srcHash & " embedded=" & BuildSourceHash & " — run 'make build' or 'make ci-bootstrap'")
  quit(1)
  ```
  A stale binary therefore **physically cannot produce a proof** — it exits 1 at startup.
- `src/infrastructure/provenance_probe.nim:51-70` — `verifyProvenanceOrFatal`, the `--check-provenance` probe (no canonical-path early return).

**Where build identity surfaces:**

| Surface | Carries build identity? | Evidence |
|---|---|---|
| `bin/ax --check-provenance` | **YES** — prints embedded hash == live tree hash | `src/cli/main.nim:84` |
| `bin/hermetic_build --check-source-hash` | **YES** (build_env level) | `tools/hermetic_build.nim:1926-1958` |
| `make check-build-state-coherence` | **YES** (Contract A preflight) | `Makefile:421-422` |
| Certificate `toolchainIdentity.engineBuild` | **YES** — SHA-256 over the build-input manifest | `src/verification/attestation_orchestrator.nim:166-202`; written at `src/verification/cert_writer.nim:519-520` |
| Certificate `provenance` | NO — only `journalCommitId` + `certificateDigest` | `cert_writer.nim:611-614` |
| Report `executionIdentity.toolchainIdentity` | NO — pinned toolchain string (nim/lean/z3/modelprofile), no engineBuild | `attestation_orchestrator.nim:204-222` |
| Report `runtimeMeta` | NO — timings + subject fingerprints | `axiom_engine.nim:4579-4594`, `wf_render.nim:504` |
| Trajectory `logs/ax_prove_trajectory.jsonl` | NO — phase/nodeId/status events only | inspected |
| `ax --version` | NO — product semver from `axiom.nimble` only (prints `v0.6.0`) | `src/cli/version.nim` → `src/core/release/version_derive.nim` |

**`engineBuild` admissibility (important):** `attestation_orchestrator.nim:152-165` returns `"unmeasured"` unless the id is 64-hex **and** `VerifierBuildSourceHash == BuildSourceHash`. `cert_reconcile.nim:847` then fails closed: `if verifierEngineBuildId() == "unmeasured": return false`. So a `nim c` after an edit **without** a fresh `bin/hermetic_build` yields `engineBuild="unmeasured"` → the certificate cannot be admitted.

**How to evidence binary↔source in the acceptance doc** (ranked by strength):
1. `bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (<hash>)`. This *is* the proof: the hash covers all of `src/**/*.nim`, so a changed `src/cli/axiom_engine.nim` necessarily changes it.
2. `bin/hermetic_build --check-source-hash` → `[build-coherence] PASS tree=… embedded=…` (`make check-build-state-coherence`).
3. `sha256sum bin/ax` to pin the exact bytes (the pattern already used at `Makefile:807` and `Makefile:847`).
4. Certificate `toolchainIdentity.engineBuild` — only meaningful if non-`"unmeasured"`.
Do **not** cite `axiomRevision` or `ax --version` as build evidence.

## (c) Staleness verdict for the current `bin/ax`

**`bin/ax` is CURRENT for the pre-change tree — not stale.** Measured:

- `bin/ax` mtime `2026-10-22 10:38:21`
- `src/cli/axiom_engine.nim` mtime `2026-10-20 14:29:10` (last commit `b326d6f6d`, 2026-10-20)
- `find src -name '*.nim' -newer bin/ax` → only `src/generated/build_env.nim` (gitignored build artifact)
- `bin/hermetic_build --check-source-hash` → `PASS tree=7334173467771305006 embedded=7334173467771305006`
- `bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK`

**But it becomes stale the instant we edit `src/cli/axiom_engine.nim`**: the live tree hash changes, the embedded `7334173467771305006` no longer matches, and the current `bin/ax` will `[FATAL] Engine source/source mismatch` and `quit(1)` before doing any work. So the rebuild is mandatory — the critic is right about the requirement, wrong that the current binary was already stale.

**Two other real staleness findings on this host:**
- `bin/axiom-gate` (2026-10-07 13:45) vs `src/gate/gateway.nim` (2026-10-15 21:36) → **STALE**
- `bin/hermetic_build` (2026-10-20 14:10) vs `tools/hermetic_build.nim` (2026-10-20 14:29) → **STALE**, and this one is a *blocker*: the stale binary predates commit `b326d6f6d` ("measured verifier identity"), so it emits `build_env.nim` **without** `VerifierBuildId`/`VerifierBuildSourceHash` lines. Current `src/generated/build_env.nim` confirms this — it has no such lines, and `.axiom/cache/build_env.body` reproduces the same omission. Hence `verifierEngineBuildId()` == `"unmeasured"` today.

`bin/derive_checker_closure` (2026-10-20 20:12) and `bin/debt_engine` (2026-10-20 14:10) are both fresh vs their sources.

## Build order constraint (task 5) — a `nim c` alone is NOT sufficient

1. `config/paths.nims:58` auto-injects the nimble dep paths (`checksums, ed25519, fusion, malebolgia, nimcrypto`) and `:60-65` adds `.`, `src`, `tests/gateway`, `src/shared_types`, `tools`. **No `--path` flags are needed** for `nim c src/cli/main.nim`. All 5 deps are present in `~/.nimble/pkgs2`; Nim is 2.2.10 (matches the pin; `NIM_TOOLCHAIN_ROOT` resolves to `~/.choosenim/toolchains/nim-2.2.10`); Z3 is 4.13.3, matching the `ExpectedZ3Version` hard-fail at `tools/hermetic_build.nim:1970-1975`.
2. `config.nims:366-…` `block hermeticPreBuild` runs before every `nim c` (skipped when `AXIOM_HERMETIC_BUILDING=1`) and regenerates `src/generated/build_env.nim`, always substituting the **live** tree hash (`config.nims:511-515`). `config.nims:626-639` `block sourceHashSeedGuard` is top-level and fires even under `AXIOM_HERMETIC_BUILDING=1`. ⇒ the compiled `BuildSourceHash` always matches the tree, provided the compile happens after the edit.
3. **The `VerifierBuildId` is the part that is not automatic.** It is only written by a *current* `bin/hermetic_build` (`tools/hermetic_build.nim:941,947` and the `--materialize` path at `:1908-1921`, which recomputes `measuredVerifierBuildId()`). The `config.nims` body-restore path only *preserves* an already-present `VerifierBuildId` line (`config.nims:516-540`) — it never creates one.

**Therefore the required order is:**
```
# 1. refresh the orchestrator so it can measure the verifier build identity
nim c -o:bin/hermetic_build --hints:off tools/hermetic_build.nim     # or: nimble hermetic
# 2. write build_env.nim for the NEW tree (build_env.nim must gain VerifierBuildId/VerifierBuildSourceHash)
bin/hermetic_build --materialize      # or a full `bin/hermetic_build`
# 3. compile the CLI
nim c -d:release --hints:off -o:bin/ax src/cli/main.nim
# 4. prove the binary is the new one
bin/ax --check-provenance              # must print AXIOM_PROVENANCE: OK
```
Skipping steps 1-2 still yields a binary that passes `--check-provenance`, but its certificates carry `toolchainIdentity.engineBuild == "unmeasured"` and are rejected by `cert_reconcile.nim:847`.

Two environment notes: the working tree is currently on branch `followup/libp2p-bytesview-slice` at `0b2564b27` (not `main` — the branch moved during this session), and `git status --porcelain` is clean. One caveat: my read-only check of `bin/hermetic_build --check-source-hash` did rewrite the untracked/gitignored `src/generated/build_env.nim` (refreshing `BuildEnvGitHash` to `0b2564b27…`, commit count 3380) — no tracked file was modified, and `git status` remains clean.