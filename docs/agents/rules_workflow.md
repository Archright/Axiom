## §2. RULES & WORKFLOW

### 2.1 Knowledge Load Protocol (Mandatory)

1. **Constitution First**: AGENTS.md §0 is auto-loaded.
2. **Ordinance on Demand**: Load `docs/spec/` files when modifying related modules.
3. **Annals on Demand**: Read `docs/history/` only when past decisions needed.
   - **3a. Annals Write-Back (HARD RULE)**: Any quarantine, deletion, or refactor that moves code out of `src/` **MUST** be accompanied by a `docs/history/` registry entry in the same commit. Pattern: `test-deletion-registry.md` (file path, deletion reason, restoration risk, SSOT authority). Required for `experimental/pending_deprecation/` entries (see §1.2 Experimental Zone Sub-structure).
    - **3b. Context Injection Pipeline**: REMOVED 2026-08-07 — `.axiom/context.ir` auto-load via `bin/axiom-agent` was dead (no agent runtime implements the wrapper); AGENTS.md is the sole project context channel.
4. **Guardian First**: Before any code change, verify compliance with GUARDIAN.
5. **Pre-flight Baseline Discovery (HARD RULE)**: Before proposing any architectural plan or structural refactor, the agent **MUST** execute a deterministic static analysis of the current codebase state and cross-check against natural-language debt/issue logs.
   - **Skepticism Rule**: All `DEBT_REGISTRY.md` entries and issue descriptions are *hypotheses* that may be stale, partially resolved, or inaccurately scoped. The codebase is the ground truth; the document is a map.
   - **Mandatory Measurement**: Run the appropriate gate or scanner (e.g., the DAG/import cycle analysis in `src/gate/gate_dag.nim` and `src/core/topology/import_graph.nim`, or `nim c -r src/gate/runners/debt_scan_gate.nim` for the debt/stub scan) and inject the concrete numeric output (cycle count, stub count, coverage percentage) into the planning context.
   - **Hypothesis-First Validation**: If the plan assumes a problem (e.g., "circular dependency", "stub files"), the agent must first run a one-line verification command that proves the problem exists in the current HEAD. No plan may be built on unverified assumptions.

### 2.1a Epistemic Grounding / Glossary Pipeline

**REMOVED 2026-08-07** — Context injection via glossary/CWA hooks (`{.glossary.}`, `core_vocabulary.json`, `project_vocabulary.json`, `semantic_grounding_hook`, `UserPromptSubmit`) was dead (no agent runtime implements `UserPromptSubmit`); AGENTS.md §0.11 Domain Lexicon is the replacement.

---

### 2.2 Tool Usage Enforcement

| Operation | Tool |
|-----------|------|
| Code reading | `code-index` MCP |
| Code writing | Native `WriteFile` / `StrReplaceFile` |
| Problem solving | `Sequential Thinking` MCP |
| Browser | `Chrome DevTools` MCP |
| Shell scope | Nim compilation, Axiom CLI, Git, `mkdir` |
| Nim fallback | Built-in tools only after MCP failure |

**HARD RULE**: `ReadFile` on source files (`.nim`, `.py`, `.js`, `.ts`, `.rs`, `.go`, `.java`, `.c`, `.cpp`, `.h`) is **STRICTLY PROHIBITED**. Use `code-index` MCP exclusively. `ReadFile` reserved for plain-text documents (`.md`, `.toml`, `.txt`, `.yaml`, `.json`, config files) only. Violation = tool misuse.

Full SOP: [operations.md](operations.md)

### 2.3 Background Task Protocol

Launch → return status → wait for completion → analyze.

### 2.4 Parallel-First Mandate (UNCONDITIONAL)

**Parallel-first is the law.** All independent work MUST be dispatched to parallel sub-agents. Sequential execution is FORBIDDEN unless strict data dependency is proven. Parent MUST NOT block on child — fire-and-collect only.

Every task MUST begin with decomposition. Classify task type, dispatch parallel sub-agents, collect asynchronously. Waiver permitted only for single-file read with documented justification.

Full policy: [mcp-parallelism.md](mcp-parallelism.md)

### 2.4a Subagent Timeout Heuristic (HARD RULE)

Subagent timeout is **300 seconds (5 minutes)**. If a subagent exceeds this limit, it is **assumed to be insufficiently parallelized** and MUST be decomposed further.

| Symptom | Diagnosis | Action |
|---------|-----------|--------|
| Subagent > 3 min | Monolithic task, not decomposed | Split into smaller parallel subagents |
| Subagent > 3 min on single file | File too large for one pass | Use batch script (§2.11) or split file |
| Subagent > 3 min on research | Too many search queries | Narrow scope, launch multiple explore agents |

**Rationale**: A well-decomposed subagent task (single file edit, single search, single compile check) completes in <60s. 5 minutes = 300s provides 5× headroom. Exceeding this threshold is a **decomposition failure**, not a timeout issue.

**Config**: `agent_task_timeout_s = 300` in `~/.kimi/config.toml`

### 2.5 Evidence-Based Deterministic Convergence (EDC)

Every `delegate_task` MUST include a `post_condition` array of shell-checkable commands. Sub-agents call `verify_success` before terminating. Main agent checks `docs/evidence/verifications/` evidence and confirms all VERIFY entries show PASS before trusting work.

Full protocol: [evidence-based-deterministic-convergence.md](evidence-based-deterministic-convergence.md)

### 2.6 Incremental Principle (HARD RULE)

Pre-commit stage gates MUST check **ONLY changed files**. Full-tree scans belong to pre-push or explicit `ax gate run --full-tree`.

| Stage | Scope | Time Budget |
|-------|-------|-------------|
| pre-commit | Changed files only | < 10s per gate |
| pre-push | Full tree + gateway tests | < 30s total |

Gate implementations receiving `files: seq[string]` MUST NOT append additional files (e.g., dynamic test discovery) when `files` is non-empty. `files = @[]` means "full tree" — only then may gates scan directories.

**Violation**: Appending `tests/gateway/*` to a `files` list that already contains `src/api.nim` → **SRP breach + incremental principle violation**. The caller controls scope; the callee must not expand it.

**Why**: `gate_replay.nim` already documented the optimization rationale: "instead of running the full pre-commit hook (nim check on all .nim files, 15–40 s/commit), we run nim check <changed files>." This principle must be encoded in ALL gate implementations, not just replay.

**nimtry**: Architecture principle gate (`src/gate/nimtry/nimtry_cli.nim`) enforces the incremental principle with SHA256 cache in `build/nimcache/nimtry/`. Pre-commit: checks only changed files against cached hashes. Pre-push: full-tree scan when cache miss or `--full-tree` flag is set.


### 2.6a Exemption Check (HARD RULE)

Before reporting any file as technical debt, check docs/DEBT_REGISTRY.md for existing [Exemption APPROVED] entries. Exempted files are NOT debt.

**Enforcement**: Use the debt scan gate (`nim c -r src/gate/runners/debt_scan_gate.nim`) which auto-filters exempted files.

**Violation**: Reporting an exempted file as new debt = false positive waste.

### 2.7 Gherkin Tag Schema for Spec↔Test Binding

The procedure gate uses **tag-based static analysis** to determine whether a `tests/features/*.feature` file requires a corresponding test runner. This replaces pure filename convention with a metadata-driven contract verified at gate time.

**Gherkin Tag Schema:**

| Tag | Semantics |
|-----|-----------|
| *(absent)* | Default `@executable`. Runner expected at `tests/gateway/{base}_feature_test.nim` (deterministic filename convention). |
| `@manual` | No automated runner required. Feature is exempt from zombie check. |
| `@executable` | Explicit marker that a runner is required. Same behavior as default (absent tag). |

**Implementation:**
- `src/gate/tag_parser.nim` — deterministic line scanner. Reads only lines preceding `Feature:`. Complexity O(lines before Feature), typically ≤ 5.
- `src/gate/runners/procedure_gate.nim` — `findZombieFeatures` skips `@manual` features; all others use filename convention fallback.
- `src/core/axiom_pragmas.nim` — `axiomFeature(path)` compile-time macro. Test files may optionally declare their upstream feature; compilation aborts if the file is missing. Zero runtime overhead.

**Determinism guarantee:** identical feature file content → identical tag parse → identical zombie check result. No external parser dependencies.

### 2.8 Git & Environment

Git: `core.pager = cat` (repo-level), commits in English. Language: user interaction in Korean; project files in English. Encoding: UTF-8 per `.editorconfig` + `.gitattributes`.

**Native-MERGE Landing Policy (HARD RULE)**: PR landing on main uses the GitHub native MERGE commit — merge commit enabled, rebase merge and squash merge disabled at the repository level (ratified Verdict B, 2026-09-10). Axiom owns verification/certification (base, head, policy, scope, evidence), admission, ledger, and continuity; **merge semantics and the resulting tree are supplied by GitHub (TCB), the commit object is assembled by Axiom via the low-level Create a commit API (`[B,H]` + returned tree — accepted minimal layer, not a merge reimplementation), and the ref update is executed by the Landing App via `updateRefs` CAS**. Cross-branch *maintenance* sync (feature branches, not main landing) still uses the sanctioned `ax git sync` rebase path. Direct `git merge` and raw `git rebase` in the terminal are prohibited — raw rebase is BLOCKED by `data/command_policy.json` (exit 2).

**Auto-Merge Default Policy (2026-09-30; revised 2026-10-03 — decision-authority unification)**: Normal-path main landing is delegated to GitHub auto-merge + merge queue. Flow: `gh pr create` → the operator arms with the GitHub primitive `gh pr merge <N> --auto --match-head-commit <headSha>` (Axiom provides only the required check; it does not fetch or re-interpret rulesets — the in-CLI arm-auto lane was removed as a duplicate enforcement authority) → the merge queue builds merge group G on the latest base → `admission-check(G)` runs (org gate, `merge_group` event) → GREEN → GitHub lands G as a native MERGE commit → main. Human commands on the normal path: one arm invocation, zero merge commands.

- **Arm conditions**: the operator arms when the PR's required check state permits; the ruleset's active `merge_queue` rule (merge_method == MERGE) and required status `admission-check` are GitHub-enforced. `strict_required_status_checks_policy` remains uncited by this policy — freshness authority is the merge queue (the queue rebuilds on the latest base). Axiom runs no arming preflight: the trust-surface arming gate ended with the arm-auto lane; trust-surface PRs are governed by MUST-T2.
- **Execution**: `gh pr merge <N> --auto --match-head-commit <headSha>` — no strategy flag: MERGE-method authority is the ruleset queue, not the CLI. `--match-head-commit` is a point-in-time arm precondition only (arm fails when head ≠ H at arm time), NOT a persistent head pin — post-arm integrity comes from the merge queue's re-evaluation semantics (latest base + queued contents re-tested before landing).
- **Arm evidence** (either command suffices): `gh pr view <N> --json autoMergeRequest` ≠ null, or GraphQL `pullRequest(number: N) { isInMergeQueue }` = true (`gh pr view --json` exposes no queue field).
- **Trust-surface exception (ratified 2026-09-30)**: the exception is defined as "not automated by Axiom" — NOT as "independently approved by another human" (rationale: the org has exactly one `architect` team member (wintrover) and GitHub forbids PR-author self-approval → code-owner review = structural deadlock; GitHub has no per-file-path merge/auto-merge denial without an approval requirement; `bypass_actors` would widen merge authority since required checks are included). **재검토 조건 (2026-10-05)**: write 권한을 가진 두 번째 리뷰어가 실재하여 `@Archright/architect`에 합류하면, code-owner review를 merge 선행 요건으로 다시 도입한다 — 그 시점부터는 code-owner review가 구조적 교착이 아니라 실제 4-eyes가 되므로 위 거부의 전제(단일 멤버)가 성립하지 않는다. Binding statements:
- **MUST-T1 (revised 2026-10-03)**: A trust-surface PR MUST NOT be registered as an auto-merge candidate through any Axiom-controlled path. (원안: "trust-surface PR을 Axiom 제어 경로로 auto-merge 대상에 등록하지 않는다.") The former arm-time registration decision source (`trustSurfaceOutcome`) is gone with the arm-auto lane; the binding now rests on the operator + MUST-T2.
- **MUST-T1a (accepted residual — post-registration window)**: if trust-surface changes are pushed AFTER registration, the canonical procedure is to disarm (`gh pr merge <N> --disable-auto`) and take the manual path; a push that lands before disarm is an **accepted residual** (fixture #396 measured the window).
- **MUST-T2**: The normal landing path for a trust-surface PR is a human-performed manual merge.
- **MUST-T2a (delegated execution, ratified 2026-11-04)**: MUST-T2's "human-performed" binds the decision and the authorization, not the keystroke executor. The operator (the sole architect) may delegate execution of the single manual merge command to the agent when ALL of the following hold — any miss voids the delegation and the operator-keystroke path applies: (1) **per-PR and point-in-time** — the delegation names the PR and is recorded verbatim (message + date) in the landing evidence BEFORE the command runs; blanket/standing delegation is void; (2) **operator session** — the command runs under the operator's authenticated `gh auth` (actor attribution remains the operator; executor identity is a documentation fact, not a platform fact); (3) **manual lane only** — the delegated command is the one-shot merge invocation the operator would issue (`gh pr merge <N> --merge`, transiting the merge queue per repo configuration); `--auto` arming remains forbidden (MUST-T1 unchanged — the landing stays "not automated by Axiom": one human decision, one command, zero arming); (4) **honest executor record** — evidence names the executor as "agent under explicit per-PR delegation from wintrover"; recording an agent-executed merge as human keystrokes is Theater (AGENTS.md §0.9). 근거: 비준 예외의 정의 속성은 "not automated by Axiom"이지 키 입력 주체가 아니며(:125), 조직에 architect가 1인뿐이므로 운영자의 명시적 per-PR 명령이 가용한 최강의 인간 통제다. 권한 기록: 아키텍트 지시 2026-11-04("대행을 원해") — 개정 PR 본문에 원문 인용·보존; 기록자≠승인자.
- **MUST-T3**: A normal PR must be able to land with ZERO human merge commands after verification, via GitHub native auto-merge + merge queue.
- **NOT MUST**: independent third-party approval, CODEOWNERS approval itself, bypass actors, a disarm/monitor workflow, closing every bypass route.
- **Accepted residuals (explicit list)**: (1) raw `gh pr merge --auto` or GitHub UI arming — since 2026-10-03 this IS the canonical normal path (GitHub primitive, no Axiom re-interpretation); for trust-surface PRs it remains forbidden (MUST-T2; incident #390 measured the failure mode that motivated arming discipline); (2) the post-registration push window (MUST-T1a, fixture #396); (3) manual merges leave no "why manual" intent in GitHub's audit log — the arm-refusal journal stage (`merge-arm`) ended with the arm-auto lane (2026-10-03). 그 자리를 대신하는 것은 GitHub 플랫폼이 스스로 남긴 merge 기록이다 — evidence lane의 L3 관측(`gh pr view --json state,mergedAt,mergeCommit` → `MERGED` + mergeCommit OID)이 인용 가능한 플랫폼 기록으로 남는다. 잔여는 "왜 수동이었는가"를 설명하는 의도 필드의 부재로 한정된다 — merge 사실 자체의 기록 부재가 아니다.
- **Authority layering**: `merge_ruleset_drift_monitor` (configuration snapshot + drift detection — NOT a security boundary) → GitHub authorization (completion-time re-evaluation of CURRENT rules) → GitHub merge queue → MERGE. Axiom supplies the admission predicate as the required check only; it does not adjudicate admission outside the check lane, and ruleset admin changes are a configuration-plane external invariant (accepted residual — `docs/spec/github_delegation_residuals.md` R7). Never describe both as the same boundary.
- **Mid-queue ruleset mutation ban (HARD RULE)**: 활성 merge queue가 entry를 가진 동안 main-target ruleset(및 branch protection)을 변경하지 않는다. 2026-10-05 사고가 이 순서를 어긴 결과다 — 에이전트가 merge queue 진행 중 main ruleset에 `update` 규칙을 추가하자, 큐의 ref 갱신이 즉시 거절되었다(`rule_type:"update"`/`result:"fail"`/`details:"Cannot update this protected ref."` — `rulesets/rule-suites` 4360251067, actor `github-merge-queue[bot]`, 1초 뒤 `removed_from_merge_queue`); main이 동결된 것은 약 49분이었다. 변경이 불가피할 때 순서는 고정이다 — **drain queue → change ruleset → take snapshot → resume**. 어느 단계도 생략·재배열·병합하지 않는다. 정본: [docs/spec/merge_authority_integrity.md](../spec/merge_authority_integrity.md) §5(M2).
- **진단 identity는 대상을 바꾸지 않는다 (HARD RULE)**: merge-admission을 **진단하는** identity는 진단 대상(ruleset · merge queue · merge state)을 mutate하지 않는다 — 관측은 GET/GraphQL query만. 관측 도구와 변경 도구가 같은 identity를 쓰면 그것은 진단이 아니라 자기참조다. 정본: [docs/spec/merge_authority_integrity.md](../spec/merge_authority_integrity.md) §4(M7 · 진단 순수성, `Administration` write 게이팅과 Mutator 창 포함).

**Agent Branch Sync**: Never execute `git rebase` directly in the terminal. Use `ax git sync` for branch synchronization and `bin/axiom-gate commit` for commits. This rule exists because LLMs are strongly biased toward `git rebase`/`git merge` from training data; rebase is permitted only through the deterministic `ax git sync` wrapper (which is the ONLY approved local sync path — `git_cli.syncBranch` carries an `{.axiomDecision.}` declaration and command-injection guards).

**COMMAND: GIT IMMUNITY RULE (HARD RULE)**: Before ANY code modification or file creation, agents MUST execute `nim c -r src/gate/runners/agent_preflight.nim` to verify workspace synchronization safety. Violation = task failure.

1. **Pre-flight mandatory**: All code writes/commits MUST be preceded by `agent_preflight` execution.
2. **No HEAD mutation**: `git reset --hard`, detached HEAD work, or branch checkout without explicit user request is FORBIDDEN.
3. **Infra crosscheck**: When creating new files in `bin/*` or `tools/*`, agents MUST run `git ls-files` to verify no duplicate exists on other branches.
4. **Root cause**: Agent sessions that skip workspace sync verification create orphan commits in reflog, generate duplicate infrastructure files across branches, and cause silent data loss during branch synchronization.

**Plugin Worktree Resolution**: Plugins are loaded from `~/.kimi/plugins/` (global cache). The project `.agents/plugins/` directory was removed (commit 4847be498) and is **not shipped** — plugins are never loaded from it. All plugin commands use `axiom-launch` (installed at `~/.local/bin/axiom-launch`) which resolves `bin/` scripts dynamically via a 3-tier fallback chain:
  1. `git rev-parse --show-toplevel` (if inside a git repo; 셸 레벨 전용 — compile-time/NimScript는 `.axiom_root` 앵커, AGENTS.md §2.7 참조)
  2. Search upward for `axiom.nimble` (project marker)
  3. `~/.axiom-current` symlink (stable fallback)

No plugin.json edits needed — `axiom-launch` adapts automatically.

**Gate Binary Cache Invalidation on Workspace/Branch Switch**: Gate binaries are compiled artifacts cached in `bin/` per workspace. After switching **workspace**(다른 clone) 또는 **branch**, that workspace's `bin/` binaries may be stale or missing. Hooks never JIT-rebuild ("no JIT rebuild inside the hook"), so the switch leaves you with a stale binary that silently passes `fileExists` checks.

**정본 처방 (단일)**:

```bash
bin/build_all_gates --release
```

- 이것이 stale/missing 바이너리의 **유일한 처방**이다 — 실제로 FAIL을 내는 `.githooks/pre-commit`와 `.githooks/pre-push`가 출력하는 문구와 동일하다. `bin/build_all_gates`는 추적 대상이 아니므로 fresh clone에서는 `nim c -o:bin/build_all_gates tools/build_all_gates.nim`으로 먼저 만든다.
- **accepted-dead honest-skip**: 소스가 `data/debt_registry.json`에서 closed WONT_FIX "Theater/Dead Gate" 판정을 받았고(예: DEBT#491/492 — 영구 uncompilable, 소비자 0) 파일 sha256이 판정의 contentHash와 일치하는 게이트 러너는 FAIL이 아니라 `[SKIPPED] <gate> — accepted dead (<id>): <title>` 사유 표기로 건너뛴다(§0.9 — 판정 불가의 정직한 표기이며 PASS 아님). skip은 content 바인딩이라 소스 편집·삭제 즉시 소멸하고 정상 판정으로 복귀하며, registry 부재·불손 시 skip 없이 전량 정상 판정(fail-closed)이다. 빌더는 `tools/build_all_gates.nim`의 `registryBoundDeadSkips`가 유일한 authority고 레지스트리 판정을 읽기만 한다.
- **"병렬 실행 금지" 처방은 존재하지 않는다.** `tools/build_all_gates.nim`은 `tools/process_pool.nim`의 `runPool`로 병렬 빌드하지만 모듈마다 `--nimcache:build/nimcache_pool/mod<i>`가 분리되어 공유 nimcache 경합이 없다. 게이트가 요구하는 것은 게이트 바이너리(`bin/`)의 최신성이지 직렬성이 아니다.
- hook 실행 모드(`allowJit=false`)는 CAS miss에서 즉시 실패하므로, hook 게이트를 함께 돌릴 때는 `bin/precompile_gates`를 **추가로** 실행한다. 이는 gate 바이너리 갱신의 대체 경로가 아니라 hook 실행용 AOT CAS 준비이며 산출물은 `bin/`이 아니라 `.axiom/cache/gates/<casKey>/binary`이다([docs/spec/aot_pipeline.md](../spec/aot_pipeline.md) §4).
- **Root cause**: Gate memo cache keys include `repoRoot` (SHA-256 of the workspace path), so cache invalidation is correct. But the binary itself is a compiled artifact — it does NOT auto-invalidate when source changes elsewhere.

**작업 공간 정책 (clone-first, HARD RULE)** — 상세: [docs/agents/operations.md](operations.md). 불변식(I1 workstream 격리 / I2 결정론적 수렴 / `main` source mutation 금지)은 **정본: AGENTS.md §2.7**:

- **clone-first**: 보호 대상은 clone 디렉터리가 아니라 `main` branch다 — clone 안에서 `git switch -c <topic-branch>` 후 작업하는 것이 정상 경로(clone-first)이고 금지되지 않는다.
- **workspace**: 기본은 현재 clone이다 — 별도 workspace를 새로 배정하지 않는다. **session은 executor일 뿐 owner가 아니다** — claim·lazy acquisition·SessionEnd release·lease/heartbeat/stale GC 프로토콜은 없다(§0.9 무효 층 제거).
**Workstream 절차 (clone-first)**:

1. **branch 확인** — `git status --short --branch`. `main`이면 `git switch -c <branch>`(`feature/`·`fix/`·`refactor/`·`chore/`). 전용 브랜치 중복 생성·`main` 직접 커밋 금지, `main`의 미커밋 변경은 reset/discard/stash 금지(§2.1).
2. **gate 바이너리 갱신** — branch 전환 후 `bin/build_all_gates --release` (위 정본 처방). stale는 자동 재컴파일 안 됨.
3. **세션 시작** — kimi 세션을 clone 디렉터리에서 시작한다(실행기의 cwd 결박). 세션은 executor이며 workspace를 장악하지 않는다.
4. **branch 작업 → PR → 수렴** — `ax git sync` → `bin/axiom-gate commit` → `git push -u origin <branch>` → `gh pr create --base main --head <branch>` → `gh pr merge <N> --auto --match-head-commit <headSha>` (GitHub primitive 무기화; merge queue가 병합 — `--arm-auto` 플래그는 2026-10-03 제거됨). 수렴 권한은 GitHub merge authority에 있고 Axiom은 무결성 predicate와 증거만 담당한다([docs/agents/operations.md](operations.md) §Canonical sequence, §Authority Map).

### 2.9 Autonomous Infrastructure Safety

Historical gate incidents (fork bomb prevention, 2026-05-27 freeze root cause) are recorded in `docs/history/agents-md-embedded-historical-notes.md` per the Documentation-First Principle.

### 2.10 External Repository Interaction (HARD RULE)

**Duplicate Issue Prevention (HARD RULE)**: Before creating a GitHub issue on any external repository, agents MUST:
1. Search existing issues using relevant keywords (error messages, tool names, affected components)
2. Verify no duplicate exists
3. If a duplicate is found, add a comment to the existing issue instead of creating a new one

**Violation**: Creating a duplicate issue → SRP breach.

### 2.11 Bulk Operations (HARD RULE)

**Batch Binary Mandate**: When performing the same operation on multiple files (e.g., adding pragmas, func/proc conversion, mass refactoring), agents MUST use a single **Nim-compiled static binary** that processes ALL files in one tool call. File-by-file interactive conversion with LLM reasoning between each step is FORBIDDEN.

**Why**: Each tool call incurs 15-30s of LLM thinking overhead. For N files with M operations each, interactive approach costs N×M×20s. A batch binary costs N×2s (compilation only). Additionally, Python/shell scripts are prohibited as project source under the Language Ban; only Nim-compiled binaries are allowed in the execution layer.

**Measured evidence** (2026-05-31): 52 verification/ files — batch script: 82s ✅, interactive agent: 900s+ timeout ❌. (Historical evidence; future bulk tools MUST be Nim binaries.)

**Pattern**:
```nim
# ✅ CORRECT: single Nim binary, all files
for fpath in files:
    modify(fpath)
    compile(fpath)
    if errors: revert(fpath)
```
```nim
# ❌ FORBIDDEN: one tool call per file
# Agent: modify file 1 → compile → parse → modify file 2 → compile → ...
```

**Violation**: File-by-file interactive conversion in sub-agents, or use of Python/shell batch scripts, → task failure.

### 2.12 No Deferral Mandate (HARD RULE)

**"별도 세션" is FORBIDDEN.** Agents MUST NOT defer work to a "separate session", "future session", or "next time". When a task is assigned, it MUST be completed in the current session.

- If a sub-agent times out, resume it or execute the work directly.
- If a task is too large for one sub-agent, decompose into smaller parallel sub-agents.
- If a task requires sustained effort, continue working until completion — do not stop and say "this needs a separate session."
- The only acceptable stopping conditions are: (a) task fully completed, (b) user explicitly says stop, or (c) hard blocker that cannot be resolved (document and escalate).

**Violation**: Saying "별도 세션에서 진행" or equivalent deferral language → task failure.

---

### 2.13 Verification Surface (정정 2026-10-15 — "CI=0 cutover/부분 복구 2개 잔존" 서술 폐기, SSOT 이관)

원격 실행 경계는 존재한다: in-repo 워크플로 16개 + org 필수 워크플로 `admission-gate`(Archright/.github — ruleset 24233738)가 원격 PR admission 경로다. "원격 PR admission/verify 파이프라인은 존재하지 않으며 admission evidence의 권위는 로컬이다"라는 서술과 "2개 잔존" 프레임은 [operations.md](operations.md) 2026-10-04 배너가 폐기했다 — Verification surface의 정본 SSOT는 operations.md §Merge-Boundary Protocol이며, 이 절은 그 내용을 중복하지 않는다. 로컬 게이트(git hooks + orchestrator_hook)는 원격 경계와 병행하는 로컬 표면이다:

| Surface | Rule |
|------|-------------|
| pre-commit | `.githooks/pre-commit` — worktree placement/topology assert (fail-closed) → `bin/nim_check_gate incremental` on staged `.nim` → `bin/anti_theater_gate` → `bin/layer_enforcement_gate --strict` → `bin/stale_cert_gate` → `nim check src/cli/main.nim` (staged paths touch `src/`·`config/` only) |
| pre-push | `.githooks/pre-push` — `bin/gate_tier_integrity --strict` → `bin/anti_theater_gate` → `bin/layer_enforcement_gate --strict` → per push-target OID snapshot(`git worktree add --detach <OID>`) `make push-admissibility` (the `PUSH_ADMISSIBILITY_GATES` set, Makefile:54) |
| canonical enforcement | `make verify-contract` (contract preservation §) |
| hook install authority | authority = canonical value `core.hooksPath = .githooks` · sole writer = `tools/setup_hooks.nim` · enforcement = `.githooks/pre-commit` + `.githooks/pre-push` · install = `make -f ci/checker.mk setup-hooks` — [ADR-0028](../adr/0028-hook-installation-authority.md). Fresh clone: key unset is git's default (EXPECTED-PRE-INSTALL-DEFAULT), not a defect |

---

### 2.14 Compiler-in-the-Loop Atomic Mutation (HARD RULE)

When renaming, removing, or modifying a symbol's signature:

| Step | Action | Tool |
|------|--------|------|
| 1 | Make the change in the DEFINITION file | Edit |
| 2 | Run `nim check <file>` on the definition file | `tools/verify_symbol.nim` |
| 3 | Search all usages: `grep -rn "SymbolName" src/` | Grep |
| 4 | Fix EACH usage file, running `nim check <file>` after EACH fix | Edit + verify |
| 5 | **NEVER** batch-fix multiple files without intermediate compile checks | — |
| 6 | Final: `nim check src/cli/main.nim` (full project entry point) | verify |

**Rationale**: Nim has no incremental compilation mode — orphaned references from incomplete renames cascade into deep compile error chains that waste agent cycles.

**Violation**: Batch-fixing N files then running a single `nim check` → rework if any fix is wrong.

---

### 2.15 Pipeline Health Instrumentation (RETIRED 2026-09-20 — CI=0)

CI=0 cutover(2026-09-20)로 원격 CI 파이프라인과 CI 헬스 폴러, 파이프라인 헬스 게이트는 더 이상 유효한 경로가 아니다 — 검증 표면이 전부 로컬이므로 원격 헬스 증거 개념이 소멸했다. 관련 폴러 도구·게이트 러너·게이트 매니페스트 entry는 cutover에서 삭제되었다(역사 기록: ADR, docs/evidence).

- `docs/evidence/ci/` — Evidence directory (보존)
- `data/debt_registry.json` — Debt registry (CI/Pipeline Health category, 보존)

---

<!-- Extracted from AGENTS.md §2 to keep AGENTS.md under the context-size threshold. -->
