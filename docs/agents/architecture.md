## §1. ARCHITECTURE

### 1.1 Core Architecture Decisions

- **CLI First**: `src/cli/main.nim`, Unix-pipeable.
- **MCP as Extension**: `src/mcp/` calls `src/core/`; does not replace CLI.
- **Language Ban**: Nim only. Exceptions: Lean 4 proofs, Markdown, build configs. Rust source files (`.rs`) are a narrow exception: permitted ONLY under `src/frontend/rust/` and `tests/fixtures/rust/` (verification subject frontend and fixtures); this does NOT permit porting Axiom itself to Rust. Python(`.py`), Shell(`.sh`, `.bash`), and other interpreted scripts are **prohibited as project source**. Existing scripts MUST be ported to Nim-compiled static binaries and the originals deleted. No new Python/Shell files may be added.
- **Closed-World Build**: The project builds inside a hermetic, network-less environment. The only valid build/test entry points are `nimble build`, `nimble test`, and `bin/run-gate`. All policy documents are embedded into Nim binaries at compile time; runtime reads of policy files are forbidden (Zero-Input Principle).
- **Writing Language**: English for code/docs/commits; Korean for dialogue.
- Top-Down: BDD → DDD → Nim.
- **Layered Gate Architecture**: L0 Orchestrator (`gate_hook.nim`) → L1 Meta (`gate-self-check`, `sentinel`, `quality-gate-marker`) → L2 Functional (remaining gates). L1 gates MUST NOT reference L0 entry points. Enforced by compile-time `static` assertion + runtime guard in `dispatchGate`.
- **Verification Workflow**: `ax prove` → Topology Analysis → Batch UAP Orchestrator → 4-Layer Pipeline (Scout/BMC → Detective/CEGAR+Z3 → Scribe/Leanstral → Judge/Lean Kernel) → certificate gate → report.
  - **Dual Budget System** (`src/core/proof/proof_budget.nim`): Gas limit (deterministic iteration counts) + wall-clock safety net.
  - **Incremental Verification** (`primeTransitiveFingerprintCache`): Skip nodes whose vault fingerprint matches.
  - **Leanstral→Judge Wiring**: LLM proof generation → Lean kernel verification → Judge acceptance.
  - **f×g×h Rule Engine** (`src/core/diagnostics/refactoring_engine.nim`): Maps complexity signals to refactoring templates with Z3 equivalence validation.
  - **CEGAR→BMC Bridge** (`src/verification/cegar_bmc_bridge.nim`): CEGAR counterexample → concrete BMC witness trace.
  - **Escalation Strategy**: 3 consecutive Z3 rejections → `refactoringEscalated` → human architect handoff.

### 1.1a Closed-World Build & Immutable Policy Artifacts

- **Hermetic Build**: The canonical build runs inside `bin/hermetic-build`, a network-less container defined by `Dockerfile.build`. Only tools baked into the image are available; no runtime downloads, no Python/Shell interpreters in the execution PATH.
- **Single Entry Point**: Valid build/test commands are `nimble build`, `nimble test`, and `bin/run-gate`. Custom shell/python build helpers are prohibited.
- **Immutable Policy Artifacts**: `AGENTS.md` and `docs/agents/*.md` are read-only policy SSOT. Build scripts MUST NOT write to them. `config.nims` verifies their existence and non-emptiness at compile time.
- **Zero-Input Principle**: Policy documents are embedded into Nim binaries at build time via `staticRead`/`embedAgentsDocs()`. Runtime reads of policy files are forbidden; the binary is self-contained.

### 1.2 Module Structure & Layers

| Layer | Path | Responsibility |
|-------|------|----------------|
| Domain | `src/core/` | Pure calculation, parsing, types, BMC engine, refactoring rules |
| Infrastructure | `src/verification/`, `src/engine/`, `src/frontend/`, `src/infrastructure/`, `src/personas/`, `src/semantic_proofs/`, `src/sieve/`, `src/generated/` | Lean LSP, Z3 bridge, vault, UAP pipeline, CEGAR, Leanstral, git ops, Lean proofs, AST sieve, generated artifacts |
| Presentation | `src/cli/`, `src/mcp/`, `src/ui/`, `src/api/` | Output, TUI, JSON, MCP protocol |
| Gate | `src/gate/`, `src/policy/` | Read-only static analysis enforcement, build constraints & policy |

**Proof Pipeline Key Files**:

| File | Role |
|------|------|
| `src/core/proof/proof_budget.nim` | Dual budget system (gas + wall-clock) |
| `src/verification/batch_uap/` | Batch UAP orchestrator (topology → per-node UAP) |
| `src/core/diagnostics/refactoring_engine.nim` | f×g×h rule engine + stagnation escape |
| `src/core/bmc/bmc_generic.nim` | Generalized BMC (overflow/bounds/null/race) |
| `src/verification/cegar_bmc_bridge.nim` | CEGAR → BMC concrete witness bridge |
| `src/personas/judge.nim` | Judge persona with Leanstral pre-synthesis |

**Gate Layer Sub-structure**:

| Sub-layer | Entry | Responsibility | Boundary Rule |
|-----------|-------|----------------|---------------|
| L0 Orchestrator | `src/gate/runners/gate_hook.nim` | Gate scheduling, cgroups, resource limits | Controls all layers |
| L1 Meta | `src/gate/runners/gate_self_check`, `src/gate/runners/sentinel`, `quality_gate_marker` | Infrastructure verification, marker validation | MUST NOT reference L0 entry points (compile-time `static` assert) |
| L2 Functional | `bin/run-gate`, `src/gate/runners/*` | Code/logic verification (nim check, tests, etc.) excluding architecture principles | May spawn processes under cgroups |
| L2d nimtry | `src/gate/nimtry/nimtry_cli.nim`, `src/gate/nimtry/` | Unified architecture principle enforcement (SOLID, SSOT, DRY, SoC) | SHA256 incremental cache in `.nimcache/nimtry/`; `nimtryCheck()` macro for compile-time enforcement |

**Gate Safety & Administration Layer** (added 2026-06-17):

| Component | Path | Responsibility |
|-----------|------|----------------|
| `bin/debug-mode` | `src/cli/debug_mode.nim` | Break-glass switch: downgrade all gates to warning mode during infrastructure repairs |
| `bin/gate_admin` | `src/cli/gate_admin.nim` | Gate lifecycle CLI: list, status, enable, disable, **validate**, **--validate-stdin** |
| Policy SSOT | `src/gate/policy_schema.json` | Shared policy schema for all gates |
| Failure dataset | `~/.axiom/gate_history.jsonl` | Persistent gate failure log for analysis and optimization |

**Agent Command Validation Layer** (added 2026-06-17):

| Component | Path | Responsibility |
|-----------|------|----------------|
| Kimi CLI PreToolUse hook | — (purged 2026-10-03) | The `worktree_write_guard.py` Layer 1 predicate was removed together with its tracked source, installed copy, and the static worktree deny rules in `~/.kimi-code/config.toml`. Its Nim predecessor `kimi_pre_tool_use.nim` was removed 2026-07-27 as theater (DEBT#294) |
| Hook installer | Git hooks only | `bin/setup-hooks` (`tools/setup_hooks.nim`) configures `core.hooksPath` to `.githooks/`; `~/.kimi-code` is a deployment target, not SSOT (Repository → deployment adapter → `~/.kimi-code`) |
| `delegation-enforcer` gate | `src/gate/runners/delegation_enforcer.nim` → `bin/delegation-enforcer` | Layer 2: scans agent wire logs for Bash loops (delegation violations); authoritative enforcement inside the Axiom gate pipeline |
| `delegation-enforcer` plugin | Kimi CLI plugin convention (spec: `plugin.json`; installed from global cache `~/.kimi/plugins/` — project `.agents/plugins/` **not shipped**) | Kimi CLI plugin wrapper exposing `enforce_delegation` tool |
| `delegation-enforcer` plugin wrapper | `bin/delegation-enforcer-plugin` | Thin shell wrapper that finds project root via `.axiom_root` and runs `bin/delegation-enforcer` |

**Defense model**: Layer 1 was the **Kimi PreToolUse write guard** — purged 2026-10-03 together with its tracked source (`tools/hooks/worktree_write_guard.py`), installed copy, and the static worktree deny rules. The verified platform fact stands (E0/E9, 2026-10-01): Kimi permission deny rules do **not** enforce in `kimi -p` print mode (TUI unverified), so no local editor-path veto can be claimed, and mechanical `main` protection rests solely on the GitHub ruleset (branch protection). Layer 2 (`delegation-enforcer`) provides authoritative enforcement within Axiom's gate pipeline.

**4-Layer Resource Defense Stack** (implemented in `src/gate/types.nim`, `src/gate/runners/runner_process_pool.nim`, `src/gate/runners/gate_hook.nim`):

| Layer | Mechanism | Implementation | Status |
|-------|-----------|----------------|--------|
| L1 CPU | Concurrency cap | `countProcessors() div 2` enforced at orchestrator level | Active |
| L2 Priority | Nice value | `nice -n 10` wrapper in `runBatch` | Active |
| L3 OS Guard | cgroups v2 | `systemd-run --user --scope --slice=axiom-gate` (CPUQuota=50%, IOWeight=10, MemoryMax=8G) | **Needs reimplementation** — `wrapWithCgroupsIfAvailable` removed (dead code, zero production callers). L3 spec retained for future cgroups support. |
| L4 Memory | Per-process limit | `setrlimit(RLIMIT_AS, 1536MB)` | Active |

> **Note on perceived "OOM"**: The freeze events previously misidentified as OOM are actually AMDGPU driver MODE2 resets caused by CPU starvation (all 16 cores saturated by gate processes). See `docs/history/freeze-root-cause-evidence-2026-05-27.md`. The L3 cgroups layer guarantees 50% CPU headroom, preventing GPU driver thread starvation.

**Direction**: Presentation → Infrastructure → Domain. Domain never imports Infrastructure, Presentation, or Gate.

> **Note**: The `experimental/` directory (referenced in earlier revisions for pending_deprecation, scripts, and test quarantine zones) does not currently exist in the project. If an experimental zone is needed in the future, the substructure and quarantine policy described in previous revisions should be restored from git history.

### 1.3 SOLID / SoC / SSOT / DRY

- **SOLID**: SRP per module, OCP via `gate_registry.nim`, LSP via `ProverInterface`, ISP via `domain_types.nim`, DIP via abstract orchestrators.
- **SoC**: Domain / Infrastructure / Presentation / Gate — strict separation.
- **SSOT**: Types → `domain_types.nim`; Certificates → `src/verification/certificate_manager.nim`; ASI → `src/core/metrics.nim`.
- **DRY**: Duplicate fingerprints resolved by extraction, not gate silencing.

### 1.3a Import 캡슐화 원칙 (HARD RULE)

모든 내부 구현체 및 파트 파일은 개별 호출부에서 직접 임포트하는 것을 금지하며, 반드시 상위 허브 모듈(Hub Module)에서 export하여 재내보내기 체계로 캡슐화해야 한다.

### 1.3b Facade-Include Split Order (HARD RULE)

When splitting files >500 lines using the Facade-Include pattern, the following order is **mandatory**:

1. `private/*_types.nim` — Pure type definitions, distinct types, constants
2. `private/*_vm_helpers.nim` — Compile-time helpers used by macros/templates (loaded before macros)
3. `private/*_macros.nim` — Macros, templates, converters
4. `{.experimental: "codeReordering".}` — Enable after macros are loaded
5. `private/*_procs.nim` — Runtime business logic procs

**Critical rules:**
- `_vm_helpers.nim` MUST be loaded before `_macros.nim` — macros may call compile-time helpers
- `_macros.nim` MUST be loaded before codeReordering — templates/macros need forward declaration
- `_procs.nim` MUST NOT contain templates or macros — they won't be found by codeReordering
- All imports go in the Facade root file — `_procs.nim` has no independent imports
- Include depth limit: 50 (enforced by architecture_invariants.nim)

**Rationale**: `codeReordering` only reorders `proc`/`func` declarations. Templates and macros must be defined before use, and compile-time helpers must be available to macros. Violation causes `undeclared identifier` errors at compile time.

**Example facade structure:**
```nim
# src/core/trusted/axiom_pragmas.nim (Facade root)
import std/[strutils, sequtils, os, strformat, hashes]
import core/trusted/env_types

# 1. Types (pure definitions, no dependencies)
include core/trusted/axiom_pragmas/axiom_impl_types

# 2. VM Helpers (compile-time utilities for macros)
include core/trusted/axiom_pragmas/vm_helpers

# 3. Macros (templates, macros, converters)
include core/trusted/axiom_pragmas/axiom_impl_macros

# 4. Code reordering enabled after macros
{.experimental: "codeReordering".}

# 5. Procs (runtime business logic)
include core/trusted/axiom_pragmas/axiom_impl_procs
```

**올바른 패턴:**
```nim
# src/core/domain_types.nim (Hub Module)
# import core/types/domain_types   # forwarding stub: 허브가 낮춰진 부분을 re-export
# export domain_types

# src/verification/certificate_manager.nim (소비자)
# import core/domain_types  # Hub 통해서만 접근
```

**금지된 패턴:**
```nim
# src/verification/certificate_manager.nim
# import core/types/domain_types  # 직접 내부 구현체 임포트 — 금지
```

**예외:** Hub 모듈 자체가 순환 참조를 유발하는 경우에만 직접 임포트 허용.

**장기적 방향:** 상위 비즈니스 로직 레이어가 하위 내부 구현체를 직접 참조하는 예외가 발생할 경우, 해당 의존성이 꼬인 타입들을 `core/domain_types.nim`으로 상향 재배치하여 추상화 수준을 높이는 것이 궁극적 목표이다. 단기적 예외는 허용되되, 장기적으로는 허브 모듈을 통한 캡슐화가 완성되어야 한다.

### 1.3b Forwarding Stub 설계 원칙 (HARD RULE)

#### 원칙 1: Stub에는 비즈니스 로직을 넣지 마라
Stub 파일(`src/core/*.nim`)은 오직 `import`와 `export`만 유지한다. 비즈니스 로직, 타입 정의, 함수 구현을 Stub에 배치하면 의존성 그래프가 오염되고 규모 확장 시 재발한다.

**올바른 Stub:**
```nim
# src/core/domain_types.nim (Stub)
# import core/types/domain_types
export domain_types
```

**금지된 Stub:**
```nim
# src/core/domain_types.nim (Stub)
# import core/types/domain_types
export domain_types
func extraHelper(): string = ...  # 금지: 비즈니스 로직
```

#### 원칙 2: 새 모듈 추가 시 Stub을 먼저 설계하라
새로운 모듈을 추가할 때, 상위 모듈로 export하는 Stub을 먼저 설계한다. 이것이 Axiom 엔진의 의존성 무결성을 보장하는 핵심 법칙이다.

**절차:**
1. 구현체를 `src/core/도메인/모듈명.nim`에 작성
2. `src/core/모듈명.nim`에 Forwarding Stub 생성
3. 소비자는 `import core/모듈명`으로만 접근

#### 원칙 3: Stub 삭제 전 Rosetta Stone 매핑 확보
Stub을 삭제하기 전에, Stub이 제공하던 `old → new` 매핑 정보를 SHADING_MAP이나 스크립트에 명시적으로 주입한다. 매핑 없이 Stub을 삭제하면 import 경로가 단절되어 빌드가 붕괴한다.

#### 원칙 4: 포워딩 체인 깊이 제한 (HARD RULE)
Forwarding Stub은 최대 2단계까지만 허용된다. 3단계 이상의 깊은 포워딩 체인은 IDE 인텔리센스(LSP) 성능 저하를 유발하고, 의존성 그래프를 불투명하게 만든다.

**허용:** `core/X → core/subdir/X` (2단계)
**금지:** `core/X → core/subdir/X → core/subdir/deeper/X` (3단계)

**검증:** `.githooks/pre-commit`에서 Circular Dependency Guard가 자동 검사한다.

### 1.4 Standard Output Contract

- All collection units normalized into `AxiomSession` (JSON).
- Final verification output normalized as `ProofArtifact` (verdict + witness + metadata).
- Schema: see `docs/spec/`.

### 1.4a 충돌 해결 시 의도 분석 강제 (HARD RULE)

`bin/sync-branch` 실행 중 충돌이 발생하면, 스크립트가 표준 출력(stdout)으로 `MERGE_CONTEXT`를 강제 주입합니다.

- 에이전트는 이 스트림 데이터에 포함된 `OURS INTENT`와 `THEIRS INTENT`를 대조해야 합니다.
- **결정 원칙**: 참조 카운트(ref count) = 0 + Eradication(삭제) 의도 → 파일/스텁 삭제 우선.
- 참조 카운트 > 0 → 마이그레이션 안전성(Stub 유지) 의도 우선.
- 어떠한 경우에도 `-X theirs` 등 기계적 옵션으로 아키텍처 결정을 뭉개는 행위는 금지합니다.
- 충돌 해결 후 `debt_blocker_gate`가 결과를 검증합니다. 위반 시 `exit(1)`로 파이프라인을 차단합니다.

### 1.5 Unified nimtry Engine

`nimtry` (`src/gate/nimtry/`) is the single unified engine for architecture principle enforcement (SOLID, SSOT, DRY, SoC).

- **Binary**: `src/gate/nimtry/nimtry_cli.nim`
- **Policy SSOT**: `src/gate/architecture_policy.lock`
- **Cache**: SHA256 incremental cache in `.nimcache/nimtry/` (warm-scan performance regardless of module count)
- **Compile-time plugin**: `src/core/axiom_pragmas.nim` provides compile-time enforcement via `nimtryCheck()` macro
- **Temporal OCP**: `--base-ref <git-ref>` filters case-branch counts to only lines added since the ref (uses `git diff --unified=0` hunk parsing)
- **Canonical DRY**: PNode structural normalization (commutative-operator sorting + `not`-branch swap) before AST fingerprinting eliminates syntactic-only false negatives
- **Deprecated**: `bin/architecture_gate` and the former `architecture_guard.nim` module are removed and NOT shipped. The sole architecture-principle enforcement engine is `nimtry` (`src/gate/nimtry/`), invoked via `make check-arch` (`bin/nimtry`).

### 1.6 CLI Single Namespace Policy (HARD RULE)

`ax` is the SOLE CLI entry point. `axiom` is DEPRECATED and MUST NOT be extended.

- All new commands MUST be registered under `ax` (e.g., `ax gate run`, `ax cert verify`).
- `axiom` binary is a backward-compatible redirect to `ax`. No new `axiom`-specific routing.
- Subcommand groups: `prove`, `report`, `help`, `topology`.
- `prove`, `report`, `help` 3개를 제외한 모든 명령어는 불필요하여 제거됨. 다시 추가하지 말 것.
- Legacy symbolic commands (`encode-withdraw-transition`, `build-k-induction`, etc.) are REMOVED.
- Stub commands (`audit-proof-binary`, `encode-semantic-payload`, `verify-semantic-payload`) are REMOVED.
- Violation: Adding a command under `axiom`-only namespace → SRP breach.

### 1.7 Spec Binding Gate (HARD RULE)

CLI identifiers (flags, commands) defined in source MUST appear in at least one `.feature` file. Feature files MUST NOT reference identifiers that no longer exist in source.

- **Enforced by**: `spec-binding-gate` at pre-commit
- **SSOT for CLI flags**: `cli_surface_generated.nim` (generated from `cli_surface_generator.nim`)
- **SSOT for CLI commands**: `axCommandHelpEntries()` in `action_plan_cli.nim`
- **Forward check**: Source `--flag` → must exist in at least one `.feature`
- **Backward check**: Feature `--flag` → must exist in source
- **Exemption**: `@manual` features are excluded from binding checks

---

### 1.19 Module Boundary Convention — Facade Pattern

When a module re-exports symbols from its dependencies for downstream consumers:

| Rule | Description |
|------|-------------|
| `export ModuleName` | Full module re-export at boundary/facade modules |
| `from M import X` | Private consumption only — NOT re-exported |
| `from X import nil; export X` | Clean forwarding — prevents accidental internal use of forwarded symbols |
| Dependency direction | 하위 모듈은 절대 상위 모듈을 import하지 않음 (의존성 단방향) |

**Cycle Prevention**:
- `export`는 심볼 전달이지 의존성 엣지가 아님
- 순환 참조 시 Nim은 `undeclared identifier` 에러 발생 (하드 에러 아님)
- 타입 전용 모듈(`proof_types`, `results`)은 양방향 import 가능 (행위 결합 없음)

**Convention**: `contract/verification_interface`는 `boundary/verification_interface`의 forwarding stub — `from ... import nil; export verification_interface` 패턴 사용.

---

### 1.20 Declarative Anchor Pattern — Deterministic Root Resolution

> Introduced 2026-06-16 to eliminate git worktree fragility in gate infrastructure.

#### Problem

Git worktrees cause `.git` to be a **file** (containing a `gitdir` pointer) rather than a **directory**. This breaks:
- `gorge("git rev-parse --show-toplevel")` in compile-time macros (Nim `gorge()` CWD ambiguity)
- `test -d '.git'` walk-up fallback (file is not a directory)
- Gate cache keys that don't distinguish between worktrees (cross-worktree pollution)

#### Solution: `.axiom_root` Declarative Anchor

A single anchor file `.axiom_root` at the project root replaces all git-based and heuristic root detection:

| Component | File | Mechanism |
|-----------|------|-----------|
| Anchor | `.axiom_root` | Declarative marker checked into version control |
| Runtime resolution | `src/core/utils/repo_root.nim` | `findRepoRoot()`: walks up via `fileExists(result / ".axiom_root")` |
| Compile-time resolution | `src/core/trusted/axiom_pragmas.nim` | `verifySpecification`: walks up via `gorge("realpath ...")` + `fileExists(d / ".axiom_root")` |
| Environment-injected cache | `src/core/gate/gate_memo.nim` | `computeCompositeLockHash(..., repoRoot)`: SHA-256(repoRoot) prevents cross-worktree cache pollution |

**Key design properties (GUARDIAN §-1 compliance)**:
- **Ideal**: Compile-time prevention — `verifySpecification` fails at compile time if root cannot be resolved
- **Elegant**: Language-native — `fileExists` walk-up uses no external tools; `gorge()` used only for `realpath`
- **Fundamental**: No hardcoded exceptions — anchor file is a generalizable pattern, not a git-specific hack
- **Deterministic**: Identical source → identical root resolution regardless of CWD, worktree, or CI environment

#### Bootstrap Self-Verification

The `gate_hook` orchestrator verifies its own environment on startup:
1. Calls `findRepoRoot()` to locate project root via `.axiom_root`
2. Sets `setCurrentDir(repoRoot)` to establish canonical CWD
3. Passes `$repoRoot` to child gate runners via `argsTemplate`
4. Each gate runner validates its `repoRoot` argument against the anchor before proceeding

This eliminates cascading failures where stale binaries with wrong root paths cause child processes to fail with `cannot open 'src/cli/'`.

#### Files Modified in This Architecture

| File | Change | Purpose |
|------|--------|---------|
| `.axiom_root` | **New** | Declarative anchor file |
| `src/core/utils/repo_root.nim` | **New** | Runtime `findRepoRoot()` — git-free walk-up |
| `src/core/trusted/axiom_pragmas.nim` | **Modified** | `verifySpecification` — replaced `git rev-parse` with `.axiom_root` walk-up |
| `src/core/gate/gate_memo.nim` | **Modified** | `computeCompositeLockHash` — added `repoRoot` parameter to cache key |

---

### Phase 3.5: Non-Invasive AST Interception (TRM Gate)

**Problem**: `import_encapsulation_gate.nim` (§-1 immutable) contained raw `getEnv("AXIOM_GATE_SEVERITY", "error")` calls at lines 130 and 223, bypassing the centralized `env_access` layer.

**Solution**: Term-Rewriting Template (TRM) in `axiom_pragmas.nim` intercepts the `getEnv` pattern at compile time and routes through `env_types.getAxiomEnv()`.

**Architecture Changes**:
1. **`src/core/trusted/env_types.nim`** (NEW): Extracted `EnvVar` enum + 5 core accessor procs from `env_access.nim`. Breaks circular dependency (`axiom_pragmas` ↔ `env_access`).
2. **`src/core/trusted/env_access.nim`** (MODIFIED): Re-exports `env_types` + 5 convenience procs. 11 public symbols preserved — 100% backward compatible.
3. **`src/core/trusted/axiom_pragmas.nim`** (MODIFIED): Added `import core/trusted/env_types` + TRM template `rewriteGateSeverity`.
4. **`config/effects.nims`** (MODIFIED): Added `switch("import", "core/trusted/env_types")` for belt-and-suspenders global visibility.

**Dependency Graph (After)**:
```
env_types (EnvVar + accessors, std/os only)
  ↑                    ↑
axiom_pragmas       env_access
(+ TRM template)    (+ convenience procs, re-exports env_types)
```

**Key Constraint**: `env_types.nim` does NOT import `axiom_pragmas` — this is the fundamental design that enables TRM without circular dependency.

---

<!-- Extracted from AGENTS.md §1 to keep AGENTS.md under the context-size threshold. -->
