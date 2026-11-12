# Agent Standard Operating Procedure

> Extracted from AGENTS.md §1. Refer back to AGENTS.md §2 for the condensed version.

## Step 0: Parallel Decomposition (Mandatory)

Before any operation in this SOP, the agent MUST execute AGENTS.md §2.6a:
1. Classify the task using the §2.6a table.
2. If sub-agents are mandated, dispatch them as the first action.
3. If waiver applies, document it before proceeding to Step 1.

## Core Operation Guidelines

- **On task start, consult the project policy SSOT: `AGENTS.md` and `docs/agents/*.md`.** The `.agents/skills/` directory was removed (commit 4847be498) and is **not shipped**; there is no project-local SKILL.md tree to load.
- **MCP Standard Compliance**: All outputs must comply with MCP specifications. Follow relevant protocols, interfaces, and data formats.
- **Module Structure Compliance**: All work is performed within `src/core` (core integrity), `src/cli` (standard interface), `src/mcp` (extension interface) layers. `core` does not reference `cli/mcp`.
- **Sole Modification Target**: This repository (Axiom) is the ONLY place where Axiom engine code (CLI, parsers, adapters, verification logic, gateways) may be modified. Direct modifications to target repositories (e.g., bitcoin) for Axiom-related purposes are strictly prohibited.
- **Target Repository Interaction**: External open-source repositories (bitcoin, etc.) are read-only analysis targets. When interaction is needed, all adaptation logic lives in Axiom (adapters, parsers, gateway layers). The interaction direction is always Axiom to target; reverse references are not permitted.
- **Environment Constraint Resolution**: Local environment constraints such as missing system build tools or OS libraries are resolved in isolated reproduction environments.
- **Automatic Continuation to Next Step**: Unless the user explicitly instructs stop/hold, the agent must not ask about proceeding to the next step and must continuously perform context collection, implementation, verification, and cleanup.
- All technical decisions and verification procedures are delegated to individual Skill definitions.

## Knowledge Load Protocol

- **Constitution First**: AGENTS.md §0 contains the project constitution, auto-loaded by all agents. No additional file read required.
- **Ordinance on Demand**: If modifying a module relates to a specific spec in `docs/spec/`, load that spec file and follow detailed constraints.
- **Annals on Demand**: Read `docs/history/` only when past decisions or date-based change background is needed to control inference noise.
- **Guardian First**: Before any code change, verify compliance with [GUARDIAN.md](core_rules.md) absolute rules.
- **False Positive Immortalization**: When an audit or investigation identifies a false positive, it MUST be recorded in agent memory (`tech-debt/false-positives`) per GUARDIAN.md §17. Future agents load this registry before acting on audit findings to prevent deterministic waste of re-investigating known non-issues.
- **Operation Summary**: AGENTS.md §0 = Constitution, `docs/spec/` = Ordinance, `docs/history/` = Annals, [GUARDIAN.md](core_rules.md) = Absolute Law. Maximize agent operation efficiency by increasing knowledge density and reducing noise.
- **AGENTS.md Size Guard (RETIRED 2026-10-02)**: context_size_guard 게이트군 purge(건축가 지시). AGENTS.md 크기 강제는 없음(현재 17,381B, 압축본은 계획서 참조). 문서화된 크기 정책은 docs/spec/context_size_guard_policy.md(Retired).

## Standard Operating Procedure

The mandatory 3-Step Integrity Workflow (Rule Precedence -> Context Alignment -> Gherkin Scenario Writing -> TDD Implementation) is enforced by the `integrity-workflow` gate runner (`src/gate/runners/integrity_workflow.nim`). The `integrity-workflow` skill was migrated to this runner; see `docs/agents/plugin-migration.md`.

## Pre-Push Hook Override

`git push --no-verify` bypasses the pre-push differential guard.
Use only when: (a) PBT synthesizer itself is broken.
All other pushes MUST go through the differential execution guard.
See `.githooks/pre-push` for guard logic.

`.githooks/pre-push` runs only when `core.hooksPath` points at `.githooks`. Install it with
`make -f ci/checker.mk setup-hooks`; `tools/setup_hooks.nim` is the only writer of that key
([ADR-0028](../adr/0028-hook-installation-authority.md)). On a fresh clone the key is unset —
git's documented default — so no Axiom hook is armed until that command runs.

## Background Task Auto-Notification Rule (Enforced)

Kimi CLI triggers automatic completion notifications for `Shell(run_in_background=true)` **only when the agent is idle (waiting for user input)** — per official Kimi CLI documentation (Interaction and Input > Background Tasks). If the agent continues working (calling other tools, analyzing, editing), the notification is suppressed.

**Mandatory protocol for every background task:**
1. Launch the background task with `Shell(run_in_background=true, description="...")`.
2. **Immediately return control to the user** with a one-line status message (e.g., `"Running ax prove. Will report results upon automatic completion notification."`). Do NOT call `TaskOutput`, `Grep`, `ReadFile`, or any other tool after launching.
3. Wait for the automatic completion notification (`task.completed`).
4. After receiving the notification, analyze results and report to the user.

**Exception:** If the task is known to complete in < 5 seconds, `TaskOutput(block=true, timeout=10)` is acceptable. For all other cases, the return-to-idle protocol is mandatory. Violation of this rule causes silent notification loss and wastes user waiting time.

## PR/CI Observation Wait Policy (Enforced)

PR·CI 실행 상태를 관측하며 기다릴 때 **단일 sleep은 300초(5분)를 넘지 않는다** — 300초 초과 sleep은 금지다. 더 오래 기다려야 하면 sleep을 길게 늘리지 말고 **새로운 단발 조회(one-shot query)를 반복**한다.

**승인된 대기 방식만 사용한다**:
1. `gh pr checks <N> --watch` — PR required checks 완료 대기.
2. `gh run watch <RUN_ID> --exit-status --interval 30` — repo 네이티브 run 관측(`--interval 30` 명시 필수).
3. run 객체가 아직 생성되지 않은 경우에 한정한 30초 간격 단발 부트스트랩 조회 — run 확인 즉시 1·2로 전환한다.

Hand-rolled 폴링 루프(`for`/`until` + `sleep`로 완료를 폴링)는 금지다 — 측정 인프라를 ad hoc로 만드는 행위이며, 완료 이벤트를 유실하거나 잘못된 run을 관측하는 버그가 실측됐다. 근거 요지: 긴 슬립은 중단 가능성과 관측 공백을 키운다. 관측 판정·adapter 한계를 포함한 세부 절차는 [docs/agents/merge_admission_observation.md](merge_admission_observation.md)가 담당하며, 본 절은 대기 방식의 상한만 추가로 고정한다.

## Tool Usage Enforcement

MCP server selection follows mandatory read/write separation. Agents must use the designated server for each operation type:

- **Source code reading (exploration/analysis/search)**: Must use `code-index` MCP only. (`mcp_code-index_*`) File discovery, symbol search, structure analysis, pattern matching.

**Shell tool scope restriction**: The `Shell` tool MUST ONLY be used for:
- Nim compilation (`nim c`, `nim check`)
- Axiom CLI execution (`./bin/ax prove`, `./bin/ax report`)
- Git operations (`git add`, `git commit`, `git push`)
- Directory creation (`mkdir -p`)

**Shell tool MUST NOT be used for** (all have MCP equivalents — use MCP first):
- `grep`/`rg` → `search_code_advanced` (code-index MCP)
- `cat`/`head`/`tail`/`sed`/`awk` → `get_symbol_body`/`get_file_summary` (code-index MCP)
- `ls`/`find` → `find_files` (code-index MCP)
- `python3 -c` JSON processing → `get_file_summary` (code-index MCP)
- **Open source/library documentation**: Prefer official documentation; use the `Context7` MCP (`mcp_context7_*`) where available. Internal domain boundaries (external libraries = what would be indexed externally, internal = source) remain as before.
- **Thought process/problem solving**: Must use `Sequential Thinking` MCP only. (`mcp_Sequential_Thinking_sequentialthinking`)
- **Browser/network analysis**: Must use `Chrome DevTools` MCP only. (`mcp_Chrome_DevTools_MCP_*`)

MCP server selection rules and Allowlist Gate requirements are enforced by `src/gate/runners/mcp_tool_usage_gate.nim`.

## Standard Language and Environment

- Final outputs/user interactions use Korean as the standard.
- Follow Git commit message conventions, and **commit messages must be written in English.**
- **Git Command Execution**: Repo-level `core.pager = cat` is configured in `.git/config`. Git commands no longer need `--no-pager` — the repo config handles non-interactive pager suppression automatically.
- **Agent Environment Common Settings**: Non-interactive execution and Git execution rules follow the gate pipeline in [docs/agents/quality-gates.md](quality-gates.md) and the Git rules in [docs/agents/rules_workflow.md](rules_workflow.md) §2.8. The `prek-quality-gate` skill was migrated to gates (see `docs/agents/plugin-migration.md`).
- **Standard Infrastructure**: Follow standard infrastructure tool settings in `infra/` directory for infrastructure changes.

## Merge-Boundary Protocol

**원격 CI 존재 (2026-10-04 실측 — 이전 "CI=0" 배너 대체)**: CI=0 cutover(2026-09-20/21, 삭제 커밋 `ce92fc2d1`) 이후에도 원격 실행 경계는 **살아 있다** — `gh api "repos/Archright/Axiom/actions/workflows?per_page=100"` 실측 결과 활성 워크플로 **11개**(동적 `Dependency Graph`·`Dependabot Updates` 제외): `admission-check`·`certificate-mint`(PR #42에서 org `admission-gate`의 callee로 편입)·`runner-pool-acceptance`·`repository-surface`·`probe-merge-queue`·`ci-cache-publisher`·`release-ship`·`gateway-jobs-measure`·`h4-routing-measure`·`hardware-falsification-smoke`. **`ci.yml`은 여전히 부재**(`ls .github/workflows/ci.yml` → No such file)이므로 branch-push/pull-request 범용 CI는 없고, 대신 **org required workflow `admission-gate`(pull_request + merge_group)** 가 원격 PR 판정 경로다. 그 verdict job 이름이 **라이브 required check**다 — `gh api repos/Archright/Axiom/rulesets/20303214` 실측 `required_status_checks == ["admission-check"]`(integration_id 15368)·`strict_required_status_checks_policy: true` *(원안 — superseded 2026-10-11: 라이브 ruleset 20303214 재실측은 `strict_required_status_checks_policy: false`다 — 아래 갱신 노트)*·`merge_queue`(ALLGREEN) 활성. 따라서 "원격 PR checks가 존재하지 않으며 병합 경계 검증은 로컬 게이트 + `bin/axiom-gate commit`(L2) + native MERGE 랜딩이 **유일한** 경로"라는 이전 서술은 **폐기**된다 — 병합 경계는 로컬 게이트(L2) + GitHub merge queue + native MERGE 랜딩의 3자 구조다. 실행 컴퓨팅 권위는 여전히 GitHub-hosted runners다(Hetzner fleet machinery 제거 — 커밋 `077bf663c`). **증거 경로 정정**: 이전 배너가 인용한 `data/reports/ci0-cutover-20260920/`은 **존재하지 않는다**(삭제 커밋 `70b84b8af` — "delete … ci0 evidence") — 인용을 철회하고 위 실측으로 대체한다.

**갱신 (2026-10-11 — 위 배너의 `strict_required_status_checks_policy: true` 실측 문구는 superseded)**: 라이브 main ruleset(20303214) 재실측(`gh api repos/Archright/Axiom/rulesets/20303214` — `enforcement: active`) 결과 `strict_required_status_checks_policy: false` + 활성 `merge_queue` 규칙(grouping ALLGREEN · merge_method MERGE · max_entries_to_build 2)이다 — ADR-0027 P5(operator 승인 2026-10-05)의 `strict=false` 라이브 전환이 착지한 것이며, 위 2026-10-04 실측의 `true`는 전환 이전의 역사 기록이다. 현행에서 main 착지 경로의 freshness는 큐 무효화(queue invalidation) 의미론으로 집행되므로 "strict 정책 하의 BEHIND" 유형 차단은 이 저장소의 현재 구성에서 발화하지 않는다. 이 배너의 병합 경계 결론(로컬 게이트 + GitHub merge queue + native MERGE 랜딩의 3자 구조)은 strict 문구와 무관하게 유효하다. 정본: [docs/spec/github_delegation_residuals.md](../spec/github_delegation_residuals.md) R2(2026-10-11 실측 기록) · [docs/adr/0027-queue-delegation.md](../adr/0027-queue-delegation.md) §P5 · `config/policy/merge_admission.json`.

**Rule (HARD)**: With `intent = merge_to_main`, a branch push MUST be followed by **immediate PR creation/update**. **Merge eligibility remains governed by the repository's current review/check policy** — this protocol fixes PR creation timing only.

**Semantic layers**:
| Layer | Meaning |
|---|---|
| pre-push | local admissibility of the pushed OID (early feedback) |
| PR review | trust-surface exception: human manual merge (MUST-T2; the mechanical arm-refusal gate ended with the arm-auto lane — 2026-10-03) |
| merge trigger | GitHub merge queue via required check — normal path: operator arms with the GitHub primitive `gh pr merge <N> --auto` (Axiom in-CLI arm-auto lane removed 2026-10-03 — decision-authority unification); trust-surface PRs → MUST-T2 manual merge |

(`branch-push CI` / `PR checks` / `main CI` 레이어는 CI=0 cutover, 2026-09-20으로 소멸)

**Evidence-based admission (target state)**: admission 검증은 해당 commit의 per-node evidence manifest 집합 검증이다 — `ExpectedNodes == AccountedNodes`(terminal accounting)가 최종 admission invariant이며, Validity(content 대조)와 Freshness(정책 liveness)는 분리된다. 현재 의미와 merge eligibility 정책은 유지되며, 이것은 refinement다 — see `docs/spec/verification_dag_contract.md` §2, §6, §8 (admission은 Phase 4에서 구현된다; 이 문서는 계약을 선언할 뿐이다).

**Canonical sequence** (Intent: merge_to_main):
```bash
ax git sync                          # local branch maintenance sync (§2.8; not main landing)
bin/axiom-gate commit -m "..."       # L2 gated commit (never raw git commit)
git push -u origin <branch>          # pre-push exact-OID admissibility runs here
gh pr create --base main --head <branch>   # immediately
gh pr merge <N> --auto --match-head-commit <head>   # arm via GitHub primitive (trust-surface PR → MUST-T2 manual merge, do not arm)
# if trust-surface changes are pushed after arming → `gh pr merge <N> --disable-auto` → manual path (accepted-residual window per rules_workflow §2.8 MUST-T1a)
# merge eligibility per review policy (GitHub native MERGE commit, rules_workflow §2.8 — ratified Verdict B)
```

**Auto-merge arm evidence**: `gh pr view <N> --json autoMergeRequest` (≠ null) or GraphQL `pullRequest(number: N) { isInMergeQueue }` = true — either suffices (`gh pr view --json` exposes no queue field). Trust-surface PRs: MUST-T2 human manual merge — do not arm (the mechanical arm-refusal gate was the arm-auto lane, removed 2026-10-03).

**Intent-driven procedure selection** (`Procedure = f(Intent)`):
| Intent | Path |
|---|---|
| merge_to_main | sequence above — auto-merge arm (normal path); trust-surface exception: human merge (the arm refuses auto-registration; ratified 2026-09-30) |

## Git History and Commit Operation Rules

The `--no-verify` prohibition, rebase/merge rules, and version-tag synchronization are documented in [docs/agents/rules_workflow.md](rules_workflow.md) §2.8 and enforced by the pre-commit gate pipeline ([docs/agents/quality-gates.md](quality-gates.md)). Git pager is handled by repo-level `core.pager = cat`.

## Workspace Operating Rules (clone-first)

- **보호 대상은 `main` branch이지 clone 디렉터리가 아니다.** `main`에서의 source mutation만
  금지이며, clone 안에서 `git switch -c <topic-branch>` 후 작업하는 것이 정상 경로
  (clone-first)다. "main 체크아웃 디렉터리 수정 금지"는 과잉 해석이며 정책이 아니다.
- **workspace는 기본적으로 현재 clone이다** — 별도 workspace를 새로 배정하지 않는다.
  **session은 executor일 뿐 owner가 아니다** — claim(`axiom_claim.json`)·lazy
  acquisition·SessionEnd release·lease/heartbeat/stale GC는 존재하지 않는다.
  session lifecycle ≠ workspace lifecycle.
- **Enforcement 사실(2026-10-01 실측)**: Kimi permission deny rules는 `kimi -p` print
  mode에서 **차단되지 않는다**(E0/E9) — 에디터 경로의 로컬 차단은 보장으로 진술할 수
  없으며, `main`의 유일한 기계적 backstop은 GitHub ruleset(branch protection)이다.
  구 write guard는 2026-10-03 purge되었다(추적 소스·설치본·정적 worktree deny rules).
- The former `Axiom_Enterprise/` + `Axiom_Enterprise-core/` (two-checkout, `main`/`core`) layout is legacy and no longer used.

## Worktree Bootstrap (fresh worktree → 검증 가능 상태)

신규 `git worktree`에서 Axiom을 검증 가능 상태로 만들 때의 실측 트랩과 정답 절차
(실측 2026-10-07 — [layer_closed_world_enforcement_2026-10-07.md](../evidence/layer_closed_world_enforcement_2026-10-07.md)).

- **Trap 1 — `bin/` 부재 → 컴파일타임 integrity check 실패.** 신규 worktree에는 `bin/`가
  없다. 검증 목적으로는 **메인 클론의 `bin/` 복사가 허용된다**. 단 게이트 바이너리는 소스
  변경 후 `make gate-binaries`(pre-push liveness 6종 + gate runners) 직접 타깃으로
  재빌드해야 한다 — 복사본이 갭을 메우지 못하는 폐쇄 의존 갭은 별도 이슈다.
- **Trap 2 — `src/generated/build_env.nim` 복사 금지 (SourceCoherence FATAL).** 이 파일은
  비추적 생성물이다. 메인 클론에서 복사하면 `bin/ax`에 각인된 BuildSourceHash와 어긋나
  SourceCoherence FATAL이 된다. 정답은 복사가 아니라 재생성이다 —
  `rm -f src/generated/build_env.nim && make ci-bootstrap`이 트리와 일치하는 헤르메틱
  시드를 생성한다(실측: seed hash 일치 확인).
- **Trap 3 — CAS stable entry에서 `ax prove --project` 시작 즉시
  `cannot open: <repo>/.axiom/cache/gates/axiom.toml` 실패.** `make ci-bootstrap`의
  `install_ax_cas`가 `bin/ax`를 CAS stable entry(symlink → `.axiom/cache/gates/<key>/binary`)
  로 교체하면, Nim `getAppFilename()`은 symlink를 resolve하므로(`std/os` 계약)
  `src/cli/axiom_engine.nim`의 config 폴백 앵커(`<repo>/bin → <repo>` 가정)가 CAS gates
  디렉터리를 반환해 prove TOML 로드가 실패한다. 정답은 CAS에 `axiom.toml` snapshot을
  쓰는 producer가 아니다 — CAS는 파생 게이트 artifact 저장소이고 `ax cache --clear --force`가
  통째로 교체하므로 그런 복제는 즉시 재파괴되며 중복 의미 상태(§1)가 된다. 근본 수정은
  reader가 root-resolution SSOT(`findRepoRoot`, `core/utils/repo_root.nim`)으로 repo
  anchor를 marker walk로 재규명하는 것이다(실측 2026-10-08: 수정 후 fresh worktree
  ci-bootstrap → `bin/ax prove --project` 시작 통과, EXIT=0).
- **Trap 4 — attest chain `ircheck` 미빌드 → fail-closed.** `make ci-bootstrap`의
  빌드 경계는 Nim 도구다(`ci/checker.mk` `ci-bootstrap` = "Build tools → init hooks →
  baseline", Lean leg 없음; runner-pool-acceptance 부트스트랩 아티팩트 매니페스트도
  Nim 4종뿐). attest chain(stage-b extraction-agreement, kernel re-execution)은
  `proofs/.lake/build/bin/ircheck`를 런타임 해석하며 바이너리 부재 시 fail-closed로
  끝난다(`AXIOM_IRCHECK_CMD` override 없는 한). bare `lake build`는 `@[default_target]`
  이 붙은 타깃만 빌드하는 것이 Lake의 공식 계약이고 `lean_exe ircheck`에는 그 속성이
  없으므로(`proofs/lakefile.lean`), 명시적 타깃 빌드 `lake build ircheck`가 정식
  호출이다 — [continuity_runbook.md](../evidence/continuity_runbook.md) §0 전제조건,
  lakefile.lean 주석, admission-check.yml/h4-routing-measure.yml의 동일 호출과 일치
  (실측 2026-10-09: fresh worktree에서 `Build completed successfully`, binary 119.6MB).
  **레인 바인딩 단위 스위트가 같은 전제를 소비한다**: `tests/unit/test_sidecar_binding.nim`,
  `test_base36_cout_binding.nim`, `test_toml_d2_agent_binding.nim`,
  `test_libp2p_bytesview_binding.nim`, `obligation_subject_binding_test.nim`의
  extraction-agreement leg는 `resolveRepoRoot()`로 `proofs/.lake/build/bin/ircheck`를
  런타임 조인하므로(`extraction_agreement.nim:165-173` 등) 테스트 대상 트리에 Lean leg가
  없으면 fail-closed(sentinel -2)로 끝나고 `eaAgreed` 계약이 환경적으로 깨진다 — 엔진
  판정이 아니다. 정식 호출은 스위트 실행 전 `(cd proofs && lake build ircheck)`이고,
  Lean leg를 공유하는 대안은 `AXIOM_IRCHECK_CMD=<repo>/proofs/.lake/build/bin/ircheck`
  override다. 저장소 밖에 놓인 바이너리는 `findRepoRoot`가 CWD-상대 `""` 루트로 탈출해
  ircheck 조인이 CWD 앵커가 된다
  ([nim_2_2_10_stdlib_quirks.md](../spec/nim_2_2_10_stdlib_quirks.md) Q-013) — 스위트는
  바이너리가 소스 옆에 놓이는 `nim r tests/unit/<suite>.nim` 형태로 실행한다.

정답 절차:

```bash
git worktree add <path> -b <branch> origin/main   # fresh worktree — 비추적 생성물은 처음부터 없다
cp -a <main-clone>/bin/. <path>/bin/              # Trap 1 완화 — 검증 목적 복사(커밋 대상 아님). "/." 형태로 병합
rm -f src/generated/build_env.nim                 # Trap 2 방어 — 이동물이 남아 있으면 제거 후 재생성
make ci-bootstrap                                 # tools → init hooks → baseline; 트리 일치 헤르메틱 시드 + bin/ 재빌드
(cd proofs && lake build ircheck)                 # Trap 4 — attest chain ircheck; ci-bootstrap은 Nim 경계라 Lean 미빌드
```

`make ci-bootstrap`이 양쪽 트랩을 동시에 닫는다: `ci-compile`이 `bin/ax`를 worktree
소스에서 재빌드해 각인 해시를 트리와 일치시키고, fresh checkout에서 `config.nims`가
`src/generated/build_env.nim`을 materialize한다(vendors.nims 시드 + live
BuildSourceHash 주입). "build_env.nim must exist before nimble compiles anything" 순서는
canonical-bootstrap 계약이다 — [config_nims_hermetic_cache_quirk.md](../spec/config_nims_hermetic_cache_quirk.md),
`ci/checker.mk`(`ci-bootstrap` 정의), `Makefile`(`gate-binaries`).

---

## Environment (Build & Toolchain) — Full Detail

Extracted from AGENTS.md §3 (2026-08-17 slim-down). Hard environment requirements:

- **Resource boundary (OS authority)**: gate executors attempt `systemd-run --user --scope` wrapping via `findExe` (`src/gate/orchestrator/hook/executor.nim:84` and `src/gate/utils/inprocess_dispatch.nim:660`); if systemd-run is absent, the command runs without wrapping (silent no-op fallback — isolation not applied). The former in-process cgroup sandbox module was removed (2026-10-03 decision-authority unification — resource control is not an Axiom-owned fact); worker count still queries `/sys/fs/cgroup/cpu.max` read-only at the build-worker site (`src/cli/precompile_gates.nim:227`). Historical contract: `docs/spec/gate_cgroup_isolation.md` (retired).
- **AOT Precompile Pipeline**: Gate binaries must be precompiled via `bin/precompile_gates` before hook execution. Hook mode (`allowJit=false`) fails immediately on CAS miss. See `docs/spec/aot_pipeline.md`.
- **CI=0 (2026-09-20/21 cutover, 종료 선언)**: GitHub Actions 워크플로 대부분이 제거되었으나 **부분 복구로 2개 잔존** — `repository_surface.yml`(PR 관측 전용, required check 아님) + `runner-pool-acceptance.yml`(push@main, 9-job; 2026-09-22 활성화, 증거: `data/reports/ci0-cutover-20260920/`; `.github/workflows/` 비어 있지 않음). 실행 컴퓨팅 권위는 Phase D에서 GitHub-hosted runners로 이전되었다(Hetzner fleet machinery 제거 — commit `077bf663c`). 검증 표면의 primary 실행 경로는 로컬 게이트다 — pre-commit(pre-commit gate 파이프라인) → pre-push(`bin/axiom-gate commit`의 pre-push exact-OID admissibility) → `make verify-contract`(canonical contract preservation enforcement).
- **Local Verify-Static Protocol**: 로컬 정적 게이트 검증 절차: run `make local-verify-static` (16 in-place gates) + `tools/local_purity_check` (worktree, 15 gates) before push. pre-push = push-target OID 정적 admissibility(early feedback, 16 in-place gates); local-verify-static = gate parity diagnostic. CI=0(2026-09-20) 이후 이 로컬 절차가 complete static surface의 유일한 실행 경로다.

---

## Authority Map (S2 Cutover)

| Actor | Authority |
|---|---|
| Git | branch·worktree topology과 파일시스템 격리 |
| Kimi | session 생성·cwd 결박·실행 (executor — workspace owner 아님) |
| Orca | workstream 관리 도구 (선택 — 없으면 `git` + Kimi) |
| GitHub | PR·required checks·merge queue·`main` 수렴 (I2) |
| Axiom | 무결성 predicate와 증거 (AOT·gate·attestation) |

**Axiom의 비관할(merge 정책)** — Axiom은 위 표의 무결성·증거만 소유한다.
`main` 수렴 판정은 GitHub merge authority가 관할한다.

## U2 Slot Lifecycle Abandonment

U2 slot lifecycle = 폐기된 구현. 이번 전환에서 호출·확장·의존하지 않는다. 물리적 삭제와 git 정리는 별도 cleanup 단계. execution adapter 소관.

## Orca Optional Procedure (Architecture: Orca is optional)

- 가용 시 Orca adapter로 절차를 수행한다.
- Orca adapter 사용 불가 시 현재 clone + `kimi -p`로 대체한다.

## Cold Start (serial only)

- `make build` → `nim c -d:release -o:bin/axiom-gate src/gate/gateway.nim` → `nim c -d:release -o:bin/gate_hook src/gate/runners/gate_hook.nim` → `make bin/debt_engine` + `make bin/{check_nim_theater,doc_path_validator,proof_unit_consistency_gate,proof_reconcile_gate,epoch_transaction_gate}` — 이 체인은 **CLI 부트스트랩**이며 게이트 바이너리 갱신 처방이 아니다. 게이트 바이너리의 정본 처방은 `bin/build_all_gates --release` 단일이다([rules_workflow.md](rules_workflow.md) §2.8): 모듈별 분리 nimcache(`build/nimcache_pool/mod<i>`)로 병렬 빌드되므로 "병렬 레이스 금지" 제약은 코드에 존재하지 않는다 — hook 모드(AOT, `allowJit=false`) 게이트까지 돌릴 때만 `bin/precompile_gates`를 추가로 실행한다.

## Minimal Preflight

- `orca-ide status --json`에서 runtime ready 확인.
- capability는 실행 시점 실측 — Orca CLI `--help` 출력으로 판정.
- version은 기록만 한다.

## Deployment Boundary

- `~/.kimi-code`는 배포 대상일 뿐 SSOT 아님 (Repository → deployment adapter → `~/.kimi-code`).
