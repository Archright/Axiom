# Hardware Candidate Smoke — Static Elimination Verdicts (H2 aarch64 / H3 ubuntu-slim)

> **Type**: static decision record (cheap smoke / static elimination phase of the approved CI-pareto plan)
> **Date**: 2026-09-25
> **Branch**: `optimize/ci-pareto` (tip `ce4da4d2c`, 2026-09-25 14:05:57 +0900)
> **Budget note**: **Zero GitHub runner-minutes consumed by this analysis.** This document was produced entirely by local read-only inspection of the repository plus public read-only HTTP fetches (GitHub Releases/API, GitHub Docs, actions/runner-images READMEs, Ubuntu package data). **No measurement runs were launched; no workflow edits were made.**
> **Method**: every conclusion cites `file:line` or an external URL. Claims that could not be verified are marked **UNKNOWN** — nothing is guessed.
> **Scope guard**: `AGENTS.md` §-1 immutables (`src/gate/runners/import_encapsulation_gate.nim`, `config.nims` importEncapsulation block, `AGENTS.md`) were read and were **not modified**. This doc proposes fixes for a *later phase*; the fixes are **not** authored here.

---

## 1. Candidate definitions

| ID | Runner label | Hardware (GitHub docs, private-repo table) | Current status |
|---|---|---|---|
| H1 | `ubuntu-24.04` x64 | 2 vCPU / 8 GB RAM / 14 GB SSD / x64 (this repo is private — `runner-pool-acceptance.yml:60-66`, `data/ci_pareto_baseline.json:3`) | **Baseline — already measured** (per-run jobsMinutes in `data/ci_pareto_baseline.json:12-23`). No work needed. |
| H2 | `ubuntu-24.04-arm` arm64 | 2 vCPU / 8 GB RAM / 14 GB SSD / arm64 | **Subject of §2 — static verdict: H2-COMPATIBLE (fixable blockers)** |
| H3 | `ubuntu-slim` | **Single-CPU / 5 GB RAM / 14 GB SSD / x64**, container-based | **Subject of §3 — verdict: LIGHT-only suitability** |

Sources for the specs table:
- Standard runners, private-repo table: https://github.com/docs raw `data/reusables/actions/supported-github-runners.md:112-148` — Linux x64 and Linux arm64 rows are **2 vCPU / 8 GB RAM / 14 GB SSD**; the labels `ubuntu-24.04` / `ubuntu-24.04-arm` are listed at `:120-123`, `:145-148`.
- Single-CPU row (slim): https://github.com/docs raw `data/reusables/actions/single-cpu-table-row.md` — **1 vCPU / 5 GB RAM / 14 GB SSD / x64**, label `ubuntu-slim`.
- Slim container + capability limits: https://docs.github.com/en/actions/reference/runners/github-hosted-runners (fetched 2026-09-25):
  - `ubuntu-slim` = Single-CPU runner, "optimized for automation tasks, issue operations and short-running jobs. They are not suitable for typical heavyweight CI/CD builds." (section "Single-CPU runners")
  - `ubuntu-slim` jobs execute **inside a container** (not a VM), unprivileged — mounting file systems / Docker-in-Docker / low-level kernel features **not supported** ("Single-CPU runners", note).
  - **The job timeout for single-CPU runners is 15 minutes** — a job reaching this limit is terminated and fails (section "Usage limits").
  - Slim image contents: https://github.com/actions/runner-images/blob/main/images/ubuntu-slim/ubuntu-slim-Readme.md (fetched raw, 2026-09-25; OS 24.04.5 LTS; `gcc`/`g++` 13.2.0, `make` 4.3, `curl`, `unzip`, `tar`, `sudo` present; **no `z3`, no Lean tooling; `jq` 1.7 preinstalled**; `awk` (used at compile time by `config.nims:28`) is not listed in the apt table — presence UNVERIFIED, see §5).

---

## 2. H2 — `ubuntu-24.04-arm` aarch64 compatibility (static verdict)

### 2.1 Verdict

> **H2-COMPATIBLE — no unfixable blocker.** Every x64-pinned assumption in the toolchain action has a verified aarch64 counterpart at the same publisher/URL pattern, so compatibility is achievable purely by arch-conditional downloads (`uname -m` / `$RUNNER_ARCH` → pick the arm64 asset). The fix itself is later-phase work and is **NOT** authored here; this section is the static verdict + exact blocker list.

Caveats that keep this a *compatibility* verdict rather than a *full-measurement entitlement*:
1. **Cross-arch certificate-identity policy is UNKNOWN/pending** — `docs/spec/ci_optimization_tcb_judgments.md:129-132` (§2.5): no ADR governs arm64↔x64 certificate identity; a candidate claiming cross-arch certificate identity equivalence **fails J2** until that policy lands. The H2 smoke run does not mint certificates, so this does not block the cheap smoke; it blocks claiming full parity evidence from it.
2. J1/J2/J3 pass on the smoke does not equal VALID — TCB judgments (J1..J4) stay phase-2 protocol outputs (`ci_optimization_tcb_judgments.md:0.1`).
3. `gcc` version drift between arm64 and x64 images (see §2.7) interacts with the **A-layer cache key** — cache keys are arbitrarily per-image, so no cross-arch cache contamination is possible with the current key structure (key includes `ImageOS`/`ImageVersion` + gcc/glibc fingerprints — `action.yml:85-95`); note this as a *cache-separation property*, not a policy relaxation (restore-keys remain forbidden — `action.yml:28-30`, enforced at `:110`, `:164`).

### 2.2 Blocker list (exact — file:line + external asset evidence)

| # | Blocker | Location | aarch64 counterpart evidence | Fix category |
|---|---|---|---|---|
| B1 | **Z3 4.13.3 hardcoded x64 asset**: `curl … z3-${Z3_VERSION}-x64-glibc-2.35.zip`, archive root comment `z3-…-x64-glibc-2.35/` | `.github/actions/setup-axiom-toolchain/action.yml:341-345` | **`z3-4.13.3-arm64-glibc-2.34.zip` EXISTS at the same release tag** — exact asset list of `z3prover/z3` release `z3-4.13.3` (GitHub Releases API, verified 2026-09-25): `z3-4.13.3-x64-glibc-2.35.zip`, `z3-4.13.3-arm64-glibc-2.34.zip`, `z3-4.13.3-arm64-osx-13.7.zip`, `z3-4.13.3-arm64-win.zip`, plus wheels `z3_solver-4.13.3.0-py3-none-manylinux_2_34_aarch64.whl`. Download URL pattern identical: `https://github.com/Z3Prover/z3/releases/download/z3-4.13.3/z3-4.13.3-arm64-glibc-2.34.zip` | arch-conditional asset name (expect `uname -m`-based pick; archive-root glob `z3-*/bin/z3` at `action.yml:345` is already arch-agnostic) |
| B2 | **jq 1.7.1 hardcoded `jq-linux64`** (x64 asset name) | `.github/actions/setup-axiom-toolchain/action.yml:359` | **`jq-linux-arm64` EXISTS in the same release** — `jqlang/jq` release `jq-1.7.1` assets (verified 2026-09-25): `jq-linux64` (= `jq-linux-amd64`, same size 2,319,424 bytes), **`jq-linux-arm64` (1,709,616 bytes)**, `jq-linux-i386`, `jq-linux-riscv64`, `jq-linux-s390x`, … | arch-conditional asset name |
| B3 | **Lean 4.33.0 toolchain via elan-init** — elan is arch-aware (verified, no blocker) | `action.yml:325-327` | elan-init.sh platform detection: `uname -s`/`uname -m` → `aarch64`/`arm64` normalized to `aarch64` (`/tmp/elan_init.sh:179-182, 267-268, 271-272`); installer URL `elan-$_arch.zip` (`:102`); **`elan-aarch64-unknown-linux-gnu.tar.gz` EXISTS** in `leanprover/elan` releases (latest tag `v4.2.4`, verified 2026-09-25). **Lean 4.33.0 ships `lean-4.33.0-linux_aarch64.tar.zst` and `…-linux_aarch64.zip`** in `leanprover/lean4` release `v4.33.0` (verified 2026-09-25). The action's `check_lake_probe` functional probe (`action.yml:314-333`) is arch-agnostic. | none needed (Lean toolchain auto-selected by elan) |
| B4 | **`libpcre3` apt install** | `action.yml:235-251` | `libpcre3` exists for **arm64 in Ubuntu noble**: `https://packages.ubuntu.com/noble/libpcre3` (verified 2026-09-25 — "arm64" download/filelist entries present). In-universe, installable via the same `sudo apt-get install -y -qq libpcre3` | none needed |
| B5 | **Nim 2.2.10 via choosenim** — source build is arch-independent; binary dist not needed | `action.yml:253-277`; kernel `import compiler/ast.nim` invariant `:265-272` | choosenim-init.sh platform mapping: `uname -m` → `aarch64` → `arm64` (`/tmp/choosenim_init.sh:167-168`); **the init script then FAILS CLOSED on arm64**: supported platforms are only `macosx_amd64 | macosx_arm | linux_amd64 | windows_amd64` (`:42-57`) — i.e., **choosenim has NO prebuilt arm64 binary** (confirmed: `nim-lang/choosenim` release `v0.8.16` assets = `choosenim-0.8.16_linux_amd64`, `_macosx_amd64`, `_macosx_arm`, `_windows_amd64(.exe)`; no `linux_arm64`; verified 2026-09-25). However the Axiom path builds Nim **from source** (`choosenim 2.2.10` compiles the toolchain on-host), and Nim publishes an **official arm64 Linux dist**: `nim-2.2.10-linux_arm64.tar.xz` **EXISTS at nim-lang.org** (HTTP 200 + archive content verified 2026-09-25: contains `nim-2.2.10/compiler/ast.nim`, `bin/nim`, `bin/nimble`). So the component is available; the blocker is *how the action invokes it* | B5a: the action's current `curl | sh` invocation (`action.yml:269`) FAILS on arm64 - init.sh's platform gate accepts only `macosx_amd64 | macosx_arm | linux_amd64 | windows_amd64` and exits 1 (`/tmp/choosenim_init.sh:42-57`), so the choosenim binary cannot be downloaded by the stock script. B5b: alternative is the official `nim-2.2.10-linux_arm64.tar.xz` dist (verified to contain `compiler/ast.nim`), which already satisfies the invariant (`action.yml:265-272`). Fix shape (later phase): arch-conditional choosenim bootstrap on arm64 (source-build choosenim, or seed from the official arm64 dist) - must preserve the compiler-internals fail-closed check. **Flag: the `.github` fix must preserve the "compiler internals present" invariant** — i.e., the arm64 path must not regress `action.yml:265-275`'s fail-closed check |
| B6 | **No hardcoded `uname` expectations in the workflows** (none present; the arm64 image reports `aarch64`) | none — arm64 image IS aarch64 | `hardware-falsification-smoke.yml:37-41` asserts `uname -m == aarch64` on `ubuntu-24.04-arm` (step "1/4 arch check") | verification-only, no fix |
| B7 | **B-layer binary artifacts are arch-bound by construction** | `action.yml:164-178` (payload), `:20-24` | build/nimcache, `.axiom/cache`, `proofs/.lake`, `bin/ax` etc. are produced by the runner that saves them; the A-key already includes image identity (`:85-95`). **No x64→arm64 cross-contamination path exists** as long as keys stay image-bound and restore-keys stay forbidden (J3, `:28-30`, `:183-184` in `ci_optimization_tcb_judgments.md`) | none needed (property to preserve) |
| B8 | **slim-style pcre verification line** (not a blocker) | `action.yml:250` (`ldconfig -p | grep 'libpcre\.so\.3'`) | x64 and arm64 both satisfy after install | none |

**Workflow-level scan** — `x86_64` / `amd64` / `x64` / `arm64` / `uname` strings across the four workflows (Grep of `.github`, 2026-09-25):
- The **only** arch-pinned downloads in the whole `.github` tree are `action.yml:341` (z3) and `action.yml:359` (jq). All four workflows (`runner-pool-acceptance.yml`, `admission-check.yml`, `certificate-mint.yml`, `repository_surface.yml`) contain **zero** x64/arm64/uname strings — they only call `setup-axiom-toolchain` and `make` recipes, which are arch-agnostic.
- `runner-pool-acceptance.yml` contains `uname`-free pure shell (select `:96-104` builds selector binaries, `impact_closure_selector.nim`); the `select` job's own Nim install (`:92-98`) has the same choosenim arm64 caveat as B5 (same `init.sh` path).
- No `ssse3`/baseline-CPU assumptions found in `.github` (Grep `ssse3` → no matches).

### 2.3 Other H2-relevant action properties (confirmed arch-neutral)
- Two-layer cache key composition — `using: 'composite'` shell only, key = `RUNNER_OS` + `ImageOS`/`ImageVersion` + gcc/glibc fingerprints + script hash (`action.yml:85-95`) — arch-neutral and separated per image.
- A-layer fingerprint verify uses `nim --version` / `lean --version` / `z3 --version` grep pins (`:129-143`) — arch-neutral.
- `unzip` and `install -m 0755` for z3 (`:342-345`) — arch-neutral.
- No arch-specific compiler flags (`-march`/`-mtune`/`native`) anywhere in `.github` (Grep over the action + workflows — no matches; the action never invokes gcc itself).

---

## 3. H3 — `ubuntu-slim` job-class suitability (static verdict)

### 3.1 Verdict

> **H3-SUITABLE-ONLY-FOR-LIGHT** — ubuntu-slim is a **Single-CPU / 5 GB RAM / 14 GB SSD** x64 container with a **hard 15-minute job timeout** and unprivileged execution (docs §1). GitHub.s own docs guidance: slim runners "are not suitable for typical heavyweight CI/CD builds" (ref §1). Therefore:
> - **LIGHT jobs** (select, repository-surface, gateway-identity-gate, proof-reconcile, admission-check's job-2 observation half) may route to H3 **if** the 15-minute cap and 5 GB RAM are respected — several do (measured ≤ ~3 min on x64) but **forcing every H3 job through the toolchain action is a blocker** (B9, B10 below).
> - **HEAVY jobs** (ci-bootstrap, gateway-shard ×8, build-base-artifacts, certificate-mint) are **H3-UNSUITABLE** on 5 GB / 1 CPU / 15-min-cap alone; exclude them by construction (see §3.3).
> - Classification below mirrors the plan's LIGHT/HEAVY split and the branch-tip companion workflow `hardware-falsification-smoke.yml:99-120` ("HEAVY(Nim LTO/Lean/Z3/gateway)는 본 스모크 범위 밖").

### 3.2 Job inventory and classification (from `.github/workflows/*.yml`)

| Job (workflow) | runs-on | timeout | Workload (what compiles/runs) | Class | H3 verdict |
|---|---|---|---|---|---|
| `select` (runner-pool-acceptance.yml:72-180) | `ubuntu-24.04` | 20 min | Pure git + two small Nim tools `impact_closure_selector.nim` / `proof_reconcile_gate.nim` built with `--skipParentCfg --skipProjCfg` **without** the repo config.nims (no LTO, no gate scanners); `jq` processing; artifact upload. Deliverable: decision record | **LIGHT** | **H3-SUITABLE** (with B9 caveat) — measured 0.42-0.43 min on x64 (`data/ci_pareto_baseline.json:22-23,35`); well under 15-min cap; RAM floor: no release/LTO link, `impact-closure` is a small tool → fits 5 GB. **Caveats:** (a) its standalone Nim install uses choosenim `init.sh` (`runner-pool-acceptance.yml:92-98`) — on slim the x64 choosenim binary exists, fine; (b) `fetch-depth: 0` on a 158 MB `.git` (`du -sh .git` = 158M, 2026-09-25) — 14 GB SSD OK; (c) `timeout-minutes: 20` **must be reduced** below slim's **15-minute platform cap** (docs §1) or the job dies at 15' by platform fiat; static analysis says work is ~1 min → set e.g. 10' (later phase). |
| `repository-surface` (repository_surface.yml:29-73) | `ubuntu-24.04` | 15 min | Checkout `fetch-depth: 0`; setup-axiom-toolchain restore-only; `nimble install -y checksums@0.2.2`; builds **one guard binary** `surface_guard.nim` with `-d:release` + `--nimcache:.nimcache_surface_guard` (per-project config.nims **not** skipped — LTO not active: config.nims gates LTO on `defined(release)…and defined(gcc)`, which IS true here — but single small tool, no parallel LTO link); git diff classification | **LIGHT** | **H3-SUITABLE** (with B9/B10 caveats) — measured 2.58-3.02 min on x64 (`data/ci_pareto_baseline.json:17-18,32`); 15-min timeout equals the slim cap (it must stay ≤15); RAM: single small release compile + `nimble install` of one package — comfortably under 5 GB. Caveat: uses `setup-axiom-toolchain` (`repository_surface.yml:40-44`) which currently **runs the full toolchain** (choosenim source build + elan + z3 + jq + `nimble install`) and A-layer cache save — on 1 vCPU the **choosenim source build alone could approach the 15-min cap** (see B10). |
| `gateway-identity-gate` (runner-pool-acceptance.yml:489-507) | `ubuntu-24.04` | 10 min | Pure shell (`ls`/`grep`/`comm` on downloaded JUnit artifacts) — no toolchain; comment states it was deliberately moved off dedicated VMs for being a "pure shell recipe" (`:484-488`) | **LIGHT** | **H3-SUITABLE** — measured 0.12-0.17 min (`data/ci_pareto_baseline.json:35`); no compile at all; trivially under 15-min and 5 GB. **No setup-axiom-toolchain use in this job** — no B9/B10 issue. |
| `proof-reconcile` (runner-pool-acceptance.yml:521-566) | `ubuntu-24.04` | 10 min | Download decision + `proof_reconcile_gate` binary + executed records; runs the downloaded verifier binary (`./verifier/proof_reconcile_gate …`) | **LIGHT** | **H3-SUITABLE** — measured 0.12-0.18 min (`data/ci_pareto_baseline.json:35`); no compile; binary downloaded from artifact; fits 5 GB (small binary + JSON dirs). No toolchain action use. |
| `admission-check` job 2 (admission-check.yml:184-566) | `ubuntu-24.04` | 30 min | Executes **B-built** `bin/ax` kernel (`cert subject-register`, `attest --witness-only`, `cert ledger-list`, `merge --dry-run`, `scope hash`, `baseline check`), `ircheck`, staging via jq/python; **no compilation of project code**; runs `bin/ax` from downloaded artifact | **LIGHT/observation (no build)** | **H3-NEEDS-MEASUREMENT** — job is a heavy *execution* of the verification engine (the B-built `ax` runs the attest chain - `cert attest` invokes lean/z3 inside it - and `merge --dry-run` runs MergeAdmissible; the verification pipeline is exercised; `data/ci_pareto_baseline.json:13-15` measured **8.05-8.85 min jobsMinutes on 2-vCPU x64** with wall 8.1-9.1 min. Two sub-risks on slim: (a) **8.x min measured on 2 vCPU → likely >15 min on 1 vCPU** (2-3× slowdown for CPU-bound `ax` work) — proximity to the hard 15-min cap is the deciding factor; (b) **RAM**: this job inherits the B-built binaries and runs the attest chain — peak memory UNKNOWN from static sources. **Static verdict: exclude from H3 until a lean `ax`-only smoke measures wall time and peak RSS on slim (that measurement itself is a tiny run — the companion workflow's arm job does a minimal `bin/ax` run; if that only exercises `--version`, add an `attest --witness-only`-scale run before routing this job).** The job also uses `setup-axiom-toolchain` (`:199-202`) → B9/B10 apply if routed. NOTE: `timeout-minutes: 30` exceeds slim's 15-min cap regardless — must be adjusted even if routed. |
| `build-base-artifacts` (admission-check.yml:89-177) | `ubuntu-24.04` | 30 min | **Full `make ci-bootstrap`** (4 release binaries with **LTO**, `config.nims:47-56` — `-flto -flto-partition=balanced`, link parallelism) + `lake build ircheck` (Lean toolchain) | **HEAVY** | **H3-UNSUITABLE** — LTO link on 1 vCPU/5 GB: parallel LTO at `parallelBuild` jobs = `min(cores, RAM/6 GiB)` (config.nims:27-41) = `min(1, 0.83)` → 1 job; even serialized, a multi-hundred-MB C-compile + LTO link of `bin/ax` (the largest binary) on 1 vCPU **exceeds the 15-min cap by construction** (x64 2-vCPU job **measured 4.5-5.03 min** for `ci-compile` — `data/ci_pareto_baseline.json:22-23` — and the companion smoke itself calls `make ci-compile` "≈ x64 baseline 4.5-5분" at `hardware-falsification-smoke.yml:93-95`; with 2× fewer cores and 1.6× less RAM, wall time plausibly 2-3× → ~9-15 min, and that is only the compile step, not the `lake build ircheck`). RAM: 8 GB x64 measured fine; 5 GB with LTO peak RSS ≈1.9 GB observed (`config.nims:54-55` comment) — fits RAM but not time. **Exclude.** |
| `ci-bootstrap` (runner-pool-acceptance.yml:189-341) | `ubuntu-24.04` | 35 min | `make ci-compile` (same as above, timeout 15 min at `:242`), `lake build` smoke, artifact manifest, **B-layer cache save** | **HEAVY** | **H3-UNSUITABLE** — identical LTO/Nim analysis as `build-base-artifacts`; also `timeout-minutes: 35` >> 15-min slim cap; also runs `setup-axiom-toolchain` (B9/B10). Measured 4.52-5.03 min × 2-vCPU x64 (`data/ci_pareto_baseline.json:22-23`). **Exclude.** |
| `gateway-shard` × 8 (runner-pool-acceptance.yml:342-475) | `ubuntu-24.04` | 35 min | Downlooads B artifacts; `make ci-bootstrap-cheap`; partition audit; **`make test-gateway`** → `AXIOM_JOBS=2 ./bin/all_gateway_runner` (Makefile:773) which **compiles ~86 release test builds** (the runner compiles each `_feature_test.nim` — `tools/ci/gateway` design) and executes them with z3/lean; junit upload | **HEAVY** | **H3-UNSUITABLE** — measured **~4.55-4.66 min jobsMinutes per shard on 2 vCPU** (`data/ci_pareto_baseline.json:22-23`; sum 37.04 for 8); 1 vCPU → ≥2× wall; inner compiles are release-mode `-d:release` (`Makefile:773` comment) and the job's own step timeout is 25 min (`:429`) — above slim's 15-min cap; RAM: sequential per-test compiles + `AXIOM_JOBS=2` runner → peak UNKNOWN but likely >5 GB for the biggest gateway test builds (each a release compile of a full CLI test binary). **Exclude.** |
| `mint` (certificate-mint.yml:81-476) | `ubuntu-24.04` | 45 min | `make ci-bootstrap` (`:227-231`, timeout 20 min) + `cert attest --sign` + ledger FF-CAS append | **HEAVY** | **H3-UNSUITABLE** — identical analysis to ci-bootstrap; `timeout-minutes: 45` >> 15; also involves the **TrustedWriterSet privileged tier** — routing to slim is a substrate change to a mint path; **high-risk, exclude**. Measured 5.30 min × 2 vCPU (`data/ci_pareto_baseline.json:16`). |
| `landing-integrity` (cross-repo, Archright/.github) | — | — | Cross-repo required workflow — observed 0.57-0.72 min (`data/ci_pareto_baseline.json:19-20`); **workflow file not in this repo** (cannot statically inspect here) | — | **Out of scope for this repo's routing decision** (its runner is configured in another repo). If that repo routes it, it fits LIGHT by measurement. |

### 3.3 Memory analysis — Nim `parallelBuild` 6 GiB/job vs slim's 5 GB (config.nims:27-41)

`config.nims:27-41`:
```
getDeterministicParallelJobs(memPerJobGiB=6.0): jobs = min(nproc, floor(MemTotalGiB / 6.0))
switch("parallelBuild", jobs)
```

| Runner | nproc | MemTotal (approx) | jobs = min(nproc, floor(RAM/6)) | Effect on heavy jobs |
|---|---|---|---|---|
| `ubuntu-24.04` (x64, private) | 2 | ~8 GB | `min(2, 1)` = **1** | baseline (measured) |
| `ubuntu-24.04-arm` | 2 | ~8 GB | `min(2, 1)` = **1** | same as H1 — no regression |
| `ubuntu-slim` | 1 | ~5 GB | `min(1, 0)` = **max(1, 0) = 1** | **never ≥2 jobs; serializes to 1 job** |

Conclusion of the calculation: on slim, `parallelBuild` silently degrades to **1 job** (floor(5/6)=0 → `max(1, 0)`), i.e., heavy Nim builds do **not OOM by this mechanism** — they just run fully serialized. The 6 GiB/job budget means a 5 GB machine can never spawn 2 concurrent C-compile jobs. (Peak-RSS risk remains only for a single job exceeding 5 GB — LTO link peak was ≈1.9 GB observed on a 4 GB runner, `config.nims:54-56` comment; `bin/ax` link on this repo measured fine on 8 GB. So the binding constraint for heavy jobs on slim is **TIME (1 vCPU near/over the 15-min cap), not RAM** — but both point to the same verdict: exclude.)

### 3.4 Blocker list for routing any job to H3 (including LIGHT ones)

| # | Blocker | Evidence | Impact |
|---|---|---|---|
| B9 | **Slim hard 15-min job timeout** vs several jobs' declared timeouts (20/30/35/45) | docs §1 "Usage limits": "The job timeout for single-CPU runners is 15 minutes… terminated and fails"; `select` timeout 20 (`runner-pool-acceptance.yml:75`), admission job2 30 (`admission-check.yml:187`), build-base 30 (`:91`), ci-bootstrap 35 (`:193`), mint 45 (`certificate-mint.yml:90`) | Any job routed to slim must have `timeout-minutes` **≤15** (ideally ≤10 with 2× headroom on 1 vCPU). Static work estimates: select ~0.5 min, surface ~3 min, identity ~0.2, reconcile ~0.2 (baseline measurements) — fine; admission job-2 ~8.5 min × 2 = risk zone (see table). |
| B10 | **`setup-axiom-toolchain` full provisioning on 1 vCPU** — choosenim **source build** of Nim 2.2.10 (`action.yml:253-277`) + elan Lean install (`:296-335`) + z3 + jq — on 1 vCPU this alone can approach the 15-min cap; the whole `repository-surface` job (including the action) measured only 2.58-3.02 min on 2-vCPU x64 (`data/ci_pareto_baseline.json:17-18,32`) | `action.yml:253-335`; `hardware-falsification-smoke.yml:109-119` (slim smoke reruns the same choosenim+checksums+surface_guard path on slim — a measurement, not a routing decision) | LIGHT jobs that currently call the action (`repository-surface:40-44`, `admission-check:199-202`, and select's inline choosenim `runner-pool-acceptance.yml:92-98`) need a slim profile: **skip toolchain install / cache restore** and rely on the job's actual needs (surface scaffold needs only `checksums@0.2.2` + nim). Alternative: use the official `nim-2.2.10-linux_x64.tar.xz` binary dist for slim LIGHT jobs (source `compiler/ast.nim` not needed by `surface_guard`/selector — selector builds with `--skipProjCfg`, `runner-pool-acceptance.yml:103-104`). This is a later-phase decision; flagged here. |
| B11 | **`nproc`/RAM detection on slim** — config.nims reads `/proc/meminfo` and `nproc` (`config.nims:27-41`) — works in slim container; result = 1 job (see §3.3). No action needed, documented for the record. | config.nims:27-41 | benign |
| B12 | **15-min unit-level step timeouts already inside jobs** (`gateway-shard` test step timeout 25 min Makefile-call, ci-bootstrap Lake smoke 5 + compile 15) | `runner-pool-acceptance.yml:238-242, 422-429` | irrelevant for LIGHT routing, cites the boundary |
| B13 | **Slim JSON artifact caveat** — none; `actions/upload-artifact`/`download-artifact` work on slim (composite action: no elevation required). Slim is unprivileged (docs §1) — the toolchain action's `sudo apt-get` (`action.yml:247-248`) and any Docker use **would not work** on slim (unprivileged container: "mounting file systems, using Docker-in-Docker… not supported") — `sudo` package present (`slim_readme.md` apt table) but **`sudo` inside the unprivileged container raises permission problems for apt installs** — treat as blocker for any job needing apt on slim (currently only the toolchain action's libpcre step does). | docs §1 (unprivileged); `action.yml:247-248`; slim apt table has `sudo` | Any future H3 job must not depend on apt-installed system deps on slim |

### 3.5 Summary verdict table

| Job | Class | H3 verdict |
|---|---|---|
| `select` | LIGHT | **H3-SUITABLE** (B9: timeout 20→≤15; B10: slim profile for Nim install) |
| `repository-surface` | LIGHT | **H3-SUITABLE** (B9: timeout 15 = cap boundary → keep ≤15; B10: slim profile for toolchain action) |
| `gateway-identity-gate` | LIGHT | **H3-SUITABLE** (no toolchain; measured 0.15 min) |
| `proof-reconcile` | LIGHT | **H3-SUITABLE** (no compile; measured 0.15 min) |
| `admission-check` job-2 (observation) | LIGHT-op | **H3-NEEDS-MEASUREMENT** (measured 8.x min on 2 vCPU; 1-vCPU wall-time and peak-RSS UNKNOWN statically; timeout 30 → must reduce) |
| `build-base-artifacts` | HEAVY | **H3-UNSUITABLE** (Nim LTO ci-bootstrap + lake; 4.5-5 min × >2× on 1 vCPU ≈ near/over 15-min cap) |
| `ci-bootstrap` | HEAVY | **H3-UNSUITABLE** (same; also B-layer writer on push@main) |
| `gateway-shard` ×8 | HEAVY | **H3-UNSUITABLE** (86 release test compiles; 4.6 min × 2 vCPU; step timeout 25 > 15) |
| `certificate-mint` | HEAVY | **H3-UNSUITABLE** (ci-bootstrap + privileged mint; timeout 45) |
| `landing-integrity` (cross-repo) | — | out of scope (workflow lives in another repo; measured 0.6-0.7 min) |

---

## 4. Budget note (zero runner-minutes) and integrity statement

- **Zero runner-minutes consumed**: no `gh workflow run`, no dispatch, no push, no measurement run was launched by this analysis. All evidence is from local file reads/greps and public HTTP fetches (listed per claim above). The companion measurement workflow `hardware-falsification-smoke.yml` (branch tip `ce4da4d2c`) remains **not dispatched**.
- **No workflow edits; no `.github` edits; no config.nims / gate / AGENTS.md edits.** All §-1 immutables unmodified (`git status` clean of tracked changes besides the pre-existing untracked plan artifacts).
- **Forbidden scope honored**: no trust-contract modification, no large runners, no self-hosted, no restore-keys, no cross-arch policy relaxation — none appear in this document except as documented-forbidden constraints (`action.yml:28-30`).
- Measurement runs, when later launched by the plan, must journal spend in `data/ci_pareto_baseline.json` `budgetLedger` (`data/ci_pareto_baseline.json:44-53`).

## 5. Unverifiable / UNKNOWN items (recorded honestly)

| Item | Status |
|---|---|
| Cross-arch certificate-identity policy (x64↔arm64) | **UNKNOWN** — no ADR exists (`docs/spec/ci_optimization_tcb_judgments.md:129-132`); H2 J2 claim blocked until policy lands |
| Peak RAM / exact wall time of `admission-check` job-2 on 1 vCPU slim | **UNKNOWN** statically — requires the small measurement (why it is H3-NEEDS-MEASUREMENT) |
| Wall-time amplification factor (2-vCPU → 1-vCPU) for the heavy Nim/LTO builds | **UNKNOWN** statically — conservative 2-3× used; verdict unchanged even at 1.5× (4.5-5 min → ~7 min compile alone + lake + manifest, near cap; shard 4.6→7+ with 25-min step timeout > 15 cap regardless) |
| `landing-integrity` workflow internals | **UNKNOWN** (cross-repo file not present in this checkout) |
| awk availability on ubuntu-slim (compile-time dep of config.nims:28 = awk /MemTotal/ on /proc/meminfo) | **UNVERIFIED** — not listed in the slim image apt table; mawk ships with base Ubuntu containers but was not confirmed on this image — verify during the slim measurement smoke |
| Exact MemTotal glimpsed by `config.nims` on each runner image (it reads `/proc/meminfo` at build time) | **UNKNOWN** — docs give 8 GB (x64/arm) and 5 GB (slim); `floor(RAM/6 GiB)` yields 1 job in all three cases (§3.3) |

---

## 6. Change history

| Version | Date | Change |
|---|---|---|
| v1.0.0 | 2026-09-25 | Initial static elimination record (H2 verdict + blocker list; H3 job-class table + verdicts; zero-runner-minute budget note) |
| v1.1.0 | 2026-09-25 | Runtime falsification results appended (§7) |

---

## 7. Runtime falsification results (2026-09-25, workflow `hardware-falsification-smoke.yml`)

총 7회 run / **11.08 runner-minutes** 소요 (budgetLedger 기록).

| Run | Target | Result | 판정 |
|---|---|---|---|
| 36103092357 (dispatch) | H3 slim LIGHT | **success** — awk `/usr/bin/awk` 실존(§5 UNKNOWN 해소), choosenim→Nim 2.2.10 자동, surface_guard 빌드 OK, VERDICT 라인 raw-log 실측. job 1.85분 | **H3 LIGHT PASS** — select/surface/observation routing 자격 부여 |
| 36104951644 (6차) | H2 arm | **success** — arch=arm64 / Z3 arm64-glibc / Lean·elan / Nim 2.2.10 arm64 / nimble deps / **`make ci-compile` (bin/ax + 3 binaries, LTO) OK on aarch64** / libpcre3 / bin/ax 실행, VERDICT `full candidate 측정 자격 부여` raw-log 실측. job 3.45분 | **H2 PASS** — full candidate 측정 자격 부여 |

**1–5차 실패 분해 (cheap falsification — 전부 smoke 구성 문제, aarch64 자체 불일치 0건):**

| 차수 | 실패 원인 | 성격 |
|---|---|---|
| 1 | Z3 자산 체크가 302 리다이렉트를 결손으로 오판 | 체크 버그 → 404만 결손 |
| 2 | nimble deps(`checksums` 등 4종) 미설치 | smoke 누락 → `--depsOnly` |
| 3 | choosenim arm64 명시 불지원("platform (linux_arm64) is not supported") + tarball 위치가 `config.nims:331-335`(§-1)의 `~/.choosenim/toolchains` 경로와 불일치 | **정적 판정 B5 런타임 실증** + 레이아웃 수정 |
| 4 | ast.nim 체크 `find -maxdepth 4` < 레이아웃 깊이 5 | 체크 버그 → maxdepth 6 |
| 5 | ci-compile **성공** 후 bin/ax 실행 시 `libpcre.so` 로딩 실패 (x64는 action.yml:235-251이 apt 설치, arm 이미지 미포함) | 시스템 런타임 → apt libpcre3 |

**H2 잔여 조건 (full measurement 전제):** choosenim 대신 arch-conditional bootstrap이 action.yml에 필요(정적 §3 B5의 공식 fix 경로) — 스모크는 tarball을 choosenim 레이아웃에 배치하는 방식으로 우회 확인. cross-arch certificate 정책(§5 UNKNOWN)은 measurement 전 ADR 대기.
**H3 잔여 조건:** HEAVY job-class는 정적 판정 UNSUITABLE 유지(runtime 검증 범위 밖). `admission-check` job-2는 H3-NEEDS-MEASUREMENT 유지.
