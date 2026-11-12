# Constitution Details

Extracted from AGENTS.md §0 to keep the root file under the 18,000-char context-size threshold.

---

## §0.3 Trust Boundaries — Full Detail

**Gate Layer Boundary**: L1 Meta gates (`gate-self-check`, `sentinel`, `quality-gate-marker`) MUST NOT reference L0 Orchestrator entry points (`gate_hook`). Enforced by compile-time assertions in `src/gate/gate_registry.nim` plus the meta-gate entry check in `src/gate/orchestrator/hook/executor.nim`.

**Tool Misuse Boundary**: `ReadFile` on source code files (`.nim`, `.py`, `.js`, `.ts`, `.rs`, `.go`, `.java`, `.c`, `.cpp`, `.h`) is **tool misuse** due to upstream MIME-type collision (`.nim` → `video/vnd.nokia.interleaved-multimedia`). Enforced by `src/gate/runners/mcp_tool_usage_gate.nim`, which scans session artifacts for `ReadFile` + `.nim` patterns; failure blocks promotion. The deterministic 3-prong defense (`Shell`/`cat`, `code-index`, `Glob`) is prescribed in [docs/agents/operations.md](operations.md) §"Tool Usage Enforcement".

**Deterministic Root Resolution**: When verifying project root (for gate cache keys, compile-time spec binding, or CI path resolution), agents and gate tools MUST use the `.axiom_root` declarative anchor file — NOT `git rev-parse --show-toplevel`. The `.axiom_root` file is checked into version control and placed at the project root. Root resolution walks up from the start directory using `fileExists` to find the nearest ancestor containing `.axiom_root` (with `axiom.toml` as backward-compatible fallback). The anchor requirement is scoped to compile-time/NimScript resolution: no shell exists under `nim check`, so `gorge` returns empty (§17 quirk), and the fallback `test -d '.git'` check also fails in worktrees (discovered 2026-06-16). That failure was mis-generalized to `git rev-parse --show-toplevel`, which itself works in worktrees and remains valid at shell level (hooks, axiom.nimble). See `docs/spec/nim_effect_system_quirks.md §12`.

---

## §0.4b Policy SSOT Boundary — Full Table

| Rule | Description |
|------|-------------|
| Project policy SSOT | Project policies/rules/workflow live in `AGENTS.md` and `docs/agents/*.md`. The `.agents/skills/` directory was removed (commit 4847be498) and is **not shipped**; no agent skill tree exists at that path. Reintroduction is a feature decision, not theater remediation: opencode recognizes project-level .agents/skills/<name>/SKILL.md as a standard skill location, so a real SKILL.md would be consumed. Dummy/template files remain prohibited (AGENTS.md §0.9 signature #3/#6). |
| Global skills cache is general-purpose | Agent runtime operations, general-purpose tool workflows only. Project policy skills forbidden |
| AGENTS.md takes precedence | When skills and AGENTS.md conflict, AGENTS.md wins |
| Version controlled | The policy SSOT (`AGENTS.md` + `docs/agents/*.md`) is versioned with the project via Git |
| Migrated skills | Once a skill is migrated to a plugin, gate, config file, or orchestrator binary, its SKILL.md is removed. See `docs/agents/plugin-migration.md` for the canonical migration registry. |
| `subagent-mandate` → `delegation-enforcer` | The `subagent-mandate` skill has been migrated to the `delegation-enforcer` gate (`src/gate/runners/delegation_enforcer.nim`); its SKILL.md is removed and the gate source is the SSOT. The `.agents/plugins/delegation-enforcer/` plugin directory is **not shipped**. |

---

## §0.5b Quirk Documentation Mandate — Full Detail

**Rationale**: Agent sessions are stateless. Without persisted quirk records, each new agent re-discovers the same issues, wasting resources. The quirk documentation is the SSOT that breaks this cycle.

**Enforcement**:
1. Discovery → immediate documentation in `docs/spec/<topic>_quirks.md`
2. Reference → add entry in AGENTS.md relevant section
3. Gate → `nimtry` may be extended to verify quirk documentation completeness

**Examples**: `docs/spec/nim_effect_system_quirks.md` (Nim stdlib side effects)
- **Layered Decoupling**: `docs/spec/layered_decoupling_spec.md` (타입/매크로 분리 패턴, Package-Root Absolute Addressing, domain_layout.json SSOT)
- **Declarative Effect Isolation**: `docs/spec/declarative_effect_isolation_quirks.md` ({.axiomIoBoundary.} pragma, nimtry PURITY short-circuit)
- **Sync Daemon Git Quirks**: `docs/spec/sync_daemon_quirks.md` (update-ref vs branch -f, GIT_OPTIONAL_LOCKS, TOCTOU race)
- **Pre-Commit Hook Quirks**: git log -1 returns previous commit in pre-commit; use .git/COMMIT_EDITMSG (doc deleted — see git log for history)
- **State Ledger Architecture**: `docs/spec/state_ledger_architecture.md` (v27 cross-process ledger, mmap read-only, CRC32 integrity, atomic write)
- **NimScript Gorge Limitations**: `docs/spec/nim_effect_system_quirks.md §14` (config.nims에서 walkDir/getFileInfo/parseJson 사용 불가, import boundary gate 이전 필요)
- **Hermetic Enforcement**: `docs/spec/hermetic_enforcement_roadmap.md` (gorge elimination, Nim-native alternatives, nimtry hermetic_guard)
- **Manifest Atomicity**: `docs/spec/manifest_atomicity.md` (temp+fsync+rename, source_hash SHA-256, stale detection)
- **TCB Formal Verification**: `docs/spec/tcb_formal_verification_roadmap.md` ({.cast(noSideEffect).} TCB, tcb_cast_audit, Z3/Lean roadmap)
- **IOCapability Sealed Token**: `src/core/interfaces/io_executor.nim` (distinct sealed object, unforgeable I/O permission)
- **Pure Wrapper TCB**: `src/core/pure/` (pure_stdlib.nim, pure_path.nim — only location for {.cast(noSideEffect).})
- **VFS Handle Double Indirection**: `docs/spec/vfs_handle_double_deref_quirks.md` (`ref object` is already a pointer — `unsafeAddr` creates double indirection)
- **Hermetic Z3 Version Pinning**: `docs/spec/hermetic_z3_pinning.md` (선언+검증 패턴, Explicit Bypass Flag, Sole Producer SSOT)
- **Axiom IR inline-pass mixed typing**: `docs/spec/axiom_ir_recompute_typ_inline_pass_quirk.md` (inline 패스가 스마트 생성자로 구조적 노드만 `typ` 채우고 역직렬화 리프는 `typ == nil`로 남김 → 구식 `recomputeTyp` 조기 반환이 리프 백필 누락 → `validateExprTypes` nil 검사로 `vpBmcSkipped`; ref object 얕은 복사로 리프 공유)
- **PNode/NimNode Type Separation**: `docs/spec/pnode_nimnode_type_separation_quirk.md`
- **Nim 2.2 Thread Isolation (ARC/ORC)**: `docs/spec/nim_thread_arc_isolation_quirks.md`
- **git ls-files 토폴로지 전수 파싱**: `docs/spec/pnode_parse_char_literal_quirks.md`
- **Nim deprecated enum field pragma**: `docs/spec/nim_deprecated_enum_pragma_quirk.md`
- **PNode canonical source identity (v6)**: `docs/spec/canonical_ast_identity.md` — PNode = Syntax Domain SSOT; canonicalSyntaxHash `nim-pnode-canonical-v2`; canonicalizePNode omits `n.info`/comments/synthetic; default-ordered + `{nkTableConstr,nkCurly}` allowlist; `serializeCanonicalPNode` intentionally not a separate primitive.
- **SLOC when evaluator (v8)**: `docs/spec/effective_sloc.md` — Effective SLOC = distinct source lines with ≥1 effective source-origin unit; WhenEvaluator Tier1(순수 상수식)→Tier2(선언적 WhenContext)→Unknown; `DefineContext{knownDefined,knownUndefined,else-Unknown}` (암묵 false 금지); `effectiveSloc(node, ctx): Result[int, UnknownReason]` (no -1 sentinel); `sourceSloc(node): int` (모든 branch); compiler semantic modules 미도입.
- **Nested Worktree config.nims Double-Load**: `docs/spec/nested_worktree_config_quirks.md` (**worktree root의 strict ancestor에 `config.nims`가 없을 것** — 조상 config.nims 이중 로드 → src 이중 등록 → 빌드 불가. 중첩 금지가 규칙이 아니다; checkout 형제 배치는 충분조건일 뿐)
- **gh Org-Required-Workflow Run 404**: `docs/spec/gh_org_required_workflow_run_quirks.md` (`gh run watch/view/list`가 org 필수 워크플로 런의 workflow id를 현 repo로 해석 → 404; PR 게이트 관측 대체 = `gh pr checks <n> --watch` + REST `/actions/runs/{id}`)
- **Config.nims Hermetic Cache Git Index Quirk**: `docs/spec/config_nims_hermetic_cache_quirk.md` (envHash의 `.git/index` → dirty-tree cache MISS; CI에서 꺼짐; DEBT#417)
- **Publication Scope Parser Quirks**: `docs/spec/publication_scope_parser_quirks.md` (job-level `if:` = indent-4만, step `if:` = indent-6는 건너뜀; guard 매칭 = 공백 축약 후 완전 일치, 표현식 동등 아님; 단방향 guard 요구)
- **GitHub Actions Run Observation Quirks**: `docs/spec/gh_run_observation_quirks.md` (`workflow_run.head_sha` = PR head ≠ lane 실행 주제 합성 병합 커밋 — R10의 근본 원인, 정체성은 `head ∈ parents(build)` 결속; merge-queue speculative stacking으로 그룹의 base ≠ main → PR→mg 메모 단절(class A); `gh api …/jobs/{id}/logs`는 ANSI escape 포함 시 출력 거부 → `--allow-escape-sequences` + `sed` 탈출; `run:` 블록의 표현식 토큰은 셸 이전 보간 — 주석 포함; `gh run rerun`은 원 attempt의 이벤트 SHA/ref·체인 정의를 재생 — 핀 회전 미반영, 체인 수정 검증은 identity-changing 신규 트리거만 유효; merge-queue 재진입 자가치유 루프 — 뜨거운 main 아래 각출→재진입 반복은 지연 신호이지 실패가 아니다; `persist-credentials: false` 체크아웃의 `origin` fetch는 인증 헤더가 없어 "could not read Username"로 실패 — 후보 저장소의 자격 증명 부재 불변식은 유지하고 B 워크스페이스 config의 `http.https://github.com/.extraheader`를 일회성 `-c` 설정으로만 주입)
- **strictEffects Experimental Flag No-Op**: `docs/spec/nim_effect_system_quirks.md §31` (Nim 2.2.10 `Feature.strictEffects`는 `compiler/options.nim:225`에 선언만 있고 읽는 코드 0건; 효과 시스템은 무조건 ON이며 opt-out은 `LegacyFeature.laxEffects`)
- **GitHub Ruleset API 쓰기 경로**: `docs/spec/github_ruleset_api_quirks.md` (REST ruleset 갱신의 문서화 동사는 PUT이지 PATCH가 아님 — PATCH는 미문서화 메서드로 실측 404, 동일 토큰 GET 200 + GraphQL 쓰기 성공이므로 권한 실패가 아님; 이력 서브리소스는 `/history` 문서화, `/versions`는 미문서화; 실측 쓰기 경로는 GraphQL `updateRepositoryRuleset` — org ruleset node_id도 동일 mutation으로 갱신, `updateOrganizationRuleset` mutation은 스키마에 없음(introspection 확인); REST PUT은 미실측 — 실측 없이 동작 단정 금지; 비상 창 절차 사용 시 감사 기록 + 복원 관측 증거 의무)
- **Pre-Push Hook Snapshot GIT_DIR 상속**: `docs/spec/git_hook_snapshot_quirks.md` (훅이 export하는 GIT_DIR·GIT_WORK_TREE 등이 `make -C $SNAP` 스냅샷 실행까지 상속 — push-target OID가 아닌 체크아웃 HEAD의 diff가 판정됨; git githooks(5)가 명시하는 env-clearing 요구 미이행. 2026-10-10 실측, 수정 착지 `8c7a865db`)
- **Merge-Admission 관측 계층 Quirks**: `docs/spec/gh_merge_admission_observation_quirks.md` (landing_observe.sh pr-head 행이 advisory 포함 애그리게이트 `statusCheckRollup`을 required rollup으로 계수 → GitHub 큐 권위와 모순된 TERMINAL_FAIL — Authority ≠ Adapter; merge_group 런 `gh run view --log` 404 확장 재측정 + REST `runs/{id}/jobs`·`jobs/{id}/logs` 본문 경로; org audit-log가 created/action/phrase 필터를 조용히 무시(created_at은 epoch-ms) — `--paginate --jq` 클라이언트 필터 필수. 2026-10-10 실측)
- **GitHub Auto-Merge × Merge-Queue Quirks**: `docs/spec/gh_automerge_merge_queue_quirks.md` (`gh pr checks --watch`는 merge-queue 단계 미추적·PR-head checks 종료 즉시 exit 0 — 큐 진입 확인은 단발 조회+5분 슬립; auto-merge 자동 enqueue는 최장 required check 완료 후 발화(arm→enqueue 10분+ 정상 지연); 큐 진입 후 `autoMergeRequest`는 null — arm 상태는 timeline `AutoMergeEnabledEvent`로 판정; `dependabot.yml` 착지 ~20초 내 즉시 업데이트 run 발화; `check-repository-surface`는 merge-base..HEAD diff만 판정 — 미커밋 편집은 로컬 PASS·커밋 후 스냅샷 FAIL로 뒤집힘, 정책 파일 자기개정은 소유자 수용-리스크 경로; org ruleset은 repo 엔드포인트로 읽기 가능(admin:org 불필요); pyyaml `on:`→`True` 파싱. 2026-10-22 실측 #1045/#1046/#1047)
- **GitHub Actions Runner Group Addressing Quirks**: `docs/spec/runner_group_addressing_quirks.md` (`runs-on: {group: X, labels: [...]}`의 `group`은 self-hosted/larger runner group 전용 — 표준 GitHub-hosted pool은 `runs-on: <string|list>` label로만 주소 지정, job 객체의 `runner_group_name: "GitHub Actions"`는 표시명이지 주소 불가·`runner_id/runner_name`은 문서의 null과 달리 `""`/`0` 실측; org 필수 워크플로의 `vars.*`는 YAML 소유 repo가 아닌 대상 repo(`github.repository`) 기준 해석 — 대상 repo 변수 1개로 커버, `fromJSON('')`은 템플릿 평가 시점 fail-closed; merge-queue 대기 브랜치는 push 거부되고 `gh pr merge --disable-auto`로 탈큐 불가 — GraphQL `dequeuePullRequest(input: {id})`만 유효(`enqueuePullRequest`의 `pullRequestId`와 비대칭, introspection 확인); `rerun-failed-jobs`의 in-progress 403 "This workflow is already running"은 미문서화(문서는 201만)·완료 후 재실행은 0-step 미시작 job 포함 — at-most-once 식별은 `(run_id, run_attempt, previous_attempt_url)`. 2026-10-11 실측)
- **Rust Toolchain Pin vs Required Components**: `docs/spec/rust_toolchain_quirks.md` (Charon 고정 툴체인 `nightly-2026-09-17`의 선언 components(`rustc-dev`,`llvm-tools`,`rust-src`,`miri`)에 `rustfmt`가 없지만 `make build-charon-rust`가 `cargo fmt`를 실행 → `error: 'cargo-fmt' is not installed for the toolchain ...` 즉시 실패 — **선언 핀 ≠ 재현 가능 빌드**, provenance/`RunnerPoolSpecDigest`는 실제 요구 컴포넌트 집합(선언 4개 + `rustfmt`)을 기록해야 함; `rust-toolchain`은 `charon/rust-toolchain` 심링크이지 `rust-toolchain.template`은 존재하지 않음; Aeneas는 Charon을 AENEAS repo의 `./charon-pin`(`798016509139eb51f0d764645f76d068d34ba5f6`, `charon_version 0.1.281`)으로 고정 — pin 권위는 소비자 repo 측. 2026-10-12 실측)
- **LLBC JSON 스트리밍 인터닝 & 폐쇄 문법 경계**: `docs/spec/llbc_quirks.md` (타입/상수 인터닝이 **별도 id 공간**을 쓰고 정의가 문서순 첫 출현에서 스트리밍됨 — 미정의 `Deduplicated` 참조는 반드시 거절; `is_zero`/`is_escape` 형태의 `Switch`는 v1.4에서 측정된 bool-expression 형태만 붕괴(단일 bool 패턴, `ite(cond,true,e)→or`, `ite(cond,e,false)→and`, `ite(cond,true,false)→cond`)되고 그 밖의 `Switch`/제어흐름은 여전히 거절이며 "11종" 측정은 `Assert`/`Switch` 누락으로 불완전했음; `AddChecked`는 `Assert`(오버플로 가드)+`Panic`과 **하나의 하강 단위**로만 소비, 고독한 `Assert`는 거절; `on_unwind`는 전체 statement 객체, 1원소 NonEmptyVec은 배열 아닌 객체, `BinaryOp` 연산자는 bare string이며 v1은 `Eq`만 허용 — `+`는 `BinaryOp`가 아니라 `AddChecked`. 2026-10-12 실측; Q11 — inherent-impl 메서드 이름경로의 `Impl{kind:"InherentImplBlock", skip_binder:타입참조}}` 원소는 소유자를 **타입 인턴 테이블 경유**로 해석(스칼라 소유자는 nominal path 없어 비주소화), Q12 — `layout` 키 아래 레이아웃 표현식이 같은 `Value/[id,payload]` 형식으로 타입 인턴 공간과 **id 충돌** → 수집기는 `layout` 키 비강하. 2026-11-02 실측)
- **GHEC↔Ubicloud CI Provider Failover Quirks**: `docs/spec/ci_provider_failover_quirks.md` (Actions 예산 hard-stop은 GitHub-hosted만 차단 — self-hosted(Ubicloud)는 Actions 분 과금 밖·U1 미실측; 0-step 차단 run에서도 `workflow_run` 발화(10/10 실측 — 39893960477→39893993637) → 분류는 job 필드로; GITHUB_TOKEN 권한 스코프에 `variables` 부재(공식 permissions 표 실측 fetch) — 변수 쓰기는 GitHub App `Variables: read/write`; `rerun-failed-jobs`는 0-step 미실행 실패 포함 — 전환 write 후 검증 경로, write-실패와 state=UNKNOWN은 구별(H16); concurrency `queue: max`는 pending 100 상한이며 full 시 신규 run 취소(공식) → schedule 재조정이 수렴 경로; `workflow_run.path`는 `@ref` suffix 가능·실측도 갈림 — strip 후 비교(exact bare 금지); Ubicloud JIT runner는 Default group id 1, custom label은 지원팀 전용(`ubuntu-24.04` alias는 canary identity 충돌 — 금지), hard cap 없음(UsageAlert email-only, `COST_CAP_UNVERIFIED`), job당 분 `ceil`; self-hosted runner isolation 없음 — 제어 워크플로는 checkout 0. 2026-10-23 실측)
- **git rev-parse --verify full-OID echo**: `docs/spec/git_rev_parse_verify_echo_quirk.md` (full 40-hex OID는 객체 존재 확인 없이 echo — 구문 수용이지 존재 증명이 아님; 존재 권한은 `git cat-file -t`; 원격 병합 후 fetch 없이 detached worktree 생성 불가. 2026-11-02 실측)
- **make build 스탬프 → porcelain 오염 → Zero-Footprint fail-close**: `docs/spec/build_metadata_stamp_porcelain_quirk.md` (빌드가 트래킹된 `src/generated/build_metadata.json`을 재스탬프 → replay post-run porcelain 검사가 리포 전체를 보아 counterexample 확인이 cvUnresolved로 fail-close — 관측은 일어나지만 판정은 거부; cold acceptance는 빌드 후 HEAD 복원·porcelain empty 확인 후 케이스 실행. 2026-11-02 실측)
- **Evidence-manifest gitignore mismatch**: `docs/spec/evidence_manifest_gitignore_quirk.md` (`git add <dir>`가 gitignored 증거 파일(*.log/*.sh/*.diff)을 조용히 건너뜀 → SHA256SUMS가 리포에 없는 파일을 참조해 fresh clone 검증 불가; 슬라이스 관례는 증거 산출물 .txt 재명명 + 병합 후 ls-tree로 매니페스트=커밋 집합 검증. 2026-11-02 실측)
- **workflow_run 이름 필터 등록-세대 의존**: `docs/spec/workflow_run_name_filter_quirks.md` (`on.workflow_run.workflows:`는 workflow **이름** 매칭이지 path가 아니고, 이름 해석은 org ruleset 주입 required workflow의 현재 등록 세대(`(repository_id+path)` 쌍)에 의존 — 세대 전환이 같은 repo 파일의 매칭 결과를 바꾼다; 2026-10-12 전환 창에 게이트 완료 후 발화 0건(실패 방향 = 침묵, 낭비 아님) → 멱등 PUT·룰 재등록은 회복 실패, `admission-gate-v2.yml` rename + ruleset path 갱신(2026-10-16)으로 회복; B3 #1213 화이트리스트(`['admission-gate','admission-gate-v2']`)는 현재 등록 이름 + 부존재 이름 예비항이며 게시 판정 authority는 in-job guard(run.path)로 존속; org 게이트 런은 repo runs API 열거 불가 → 트리거 측 증명은 guard 값으로. 2026-10-12→11-02 실측)
- **Agent CLI Path-Encoding Quirks**: `docs/spec/agent_tool_path_quirks.md` (repo 클론 경로의 비ASCII 문자(`<home-desktop>`)에서 에이전트의 `Write`/`Edit`가 간헐 실패 — `Read`·`Bash`는 정상, `/tmp` ASCII 절대경로는 정상: 경로 인코딩 결합 실패; 회피 규범 = repo 내 파일은 Bash heredoc으로 작성, 2단(/tmp 초안→heredoc 반영) 허용. 2026-11-02 실측)
- **Push-Admissibility Stale-Binary Quirk**: `docs/spec/push_admissibility_stale_binary_quirk.md` (make push-admissibility 레시피가 `bin/epoch_transaction_gate`를 prerequisite 미선언 직접 호출 → 스테일 미추적 로컬 빌드가 재빌드 없이 판정 → SL-19 "unknown slice id" 3건 위양(실측); 회피 = dry-run에서 unknown slice id 보고 시 바이너리 mtime과 최신 catalog 커밋 비교 → `make bin/epoch_transaction_gate` 재빌드 → 같은 HEAD에서 dry-run 재실행. 2026-11-02 실측)
- **jq 1.7 IN($array) 멤버십 함정**: `docs/spec/jq_17_in_membership_quirk.md` (`IN(s)`의 인자는 문서상 **stream**이지 배열이 아님 — 단일 배열 인자는 배열 자체가 유일 후보가 되어 스칼라 입력이 항상 false, 오류·경고 없음; 올바른 멤버십 = `IN($arr[])` 스프레드 또는 `($arr | index($x)) != null`; GET-only 스윕의 분류 필터가 조용히 전부 false가 되는 실패 모드 — true 0건은 "빈 모집단"이 아니라 "필터 결함"으로 fail-closed. 2026-11-03 실측, node24 merge-queue critical-path census 중 발견)

---

## §0.6 Static First Enforcement — Full Detail

- `proc` is permitted ONLY at the outermost I/O boundary (CLI argument parsing, file reads, OS calls).
- **0.2 Exception (noSideEffect false positive)**: Nim `noSideEffect` false positive on `result` field writes — the constructor pattern is the sanctioned exception (function returns via `result` field mutation but is semantically side-effect-free). Allowed only when the compiler's effect system is demonstrably wrong and the quirk is documented.
- Every `func` MUST declare its full exception set via `{.raises: [].}`. Undeclared raises are a compile-time breach.
- Domain objects MUST use `distinct` types to semantically prevent accidental type confusion (e.g., `FilePath` vs `string`, `Hash` vs `string`).
- **Enforcement**: `nimtry` gate audits each `proc` declaration. If a `proc` has zero I/O calls (stdlib I/O modules), the gate warns to convert it to `func`. The compiler's effect system is the ultimate authority — `func` that fails compilation must revert to `proc`.
- **Side Effect Registry**: Nim stdlib side effect quirks (e.g., `parseJson` is not pure) are documented in `docs/spec/nim_effect_system_quirks.md`. Agents MUST consult this registry before any proc→func conversion.
- **`{.axiomIoBoundary.}` Pragma**: Defined in `src/core/trusted/axiom_pragmas.nim`. **Note**: `axiomIoBoundary` is a module-level `template`, not a per-proc `{.pragma.}`. For per-proc I/O annotation, use `{.axiomEffect: IoEffect.}` instead. Every `proc` performing I/O MUST have one of these annotations. `func` MUST NOT. See architecture.md §1.19.
- **Layered Decoupling**: `docs/spec/layered_decoupling_spec.md` (타입/매크로 분리 패턴, Package-Root Absolute Addressing, domain_layout.json SSOT)

---

## §0.6a Concurrent Code Policy — Full Detail

- CPU-bound parallel work: malebolgia MAY be used (value-type args only, 6-point checklist in `docs/spec/concurrency_policy.md` §1)
- I/O-bound: `asyncdispatch` or `startProcess` (OS process isolation)
- External programs: `startProcess` with bounded concurrency (`MaxConcurrentL2 = 4`)
- ALL non-cyclic `ref object` MUST have `{.acyclic.}` annotation (optimizes away ORC cycle collector)
- `ref object` in async contexts: check if the TYPE itself has self-referential fields. If no self-referential fields, `{.acyclic.}` is safe (e.g., LeanLspClient). Async runtime's internal cycles are ORC-level concern, not type-level.
- malebolgia `spawn` with `ref object` args is FORBIDDEN (non-atomic RC corruption risk)
- Nested `createMaster()` is FORBIDDEN (unbounded thread explosion)
- Full spec: `docs/spec/concurrency_policy.md`

---

## §0.6b Binary File Policy — Full Detail

리포지토리에 바이너리 파일(PDF, 이미지, 데이터셋 등)을 추가할 때는 반드시 Git LFS를 사용해야 합니다.

- **`.gitattributes`에 추적 패턴이 정의되어 있습니다**: `*.pdf`, `*.png`, `*.jpg` 등. 새 바이너리 형식 추가 시 `git lfs track "*.ext"` 실행 후 `.gitattributes`를 커밋.
- **`.gitattributes`에 패턴이 없는 바이너리 형식은 추가 금지**. 먼저 LFS 추적 설정 후 추가.
- **기존 Git 히스토리의 바이너리는 LFS로 마이그레이션 완료됨** (2026-06-08, PDF 12개).
- **검증**: `src/gate/runners/binary_artifact_gate.nim`(pre-commit)과 `src/gate/runners/asset_hygiene_gate.nim`이 `git check-attr filter`로 `.gitattributes` LFS 추적 여부와 바이너리/포인터 무결성을 점검.
- **예외**: 10KB 이하의 작은 아이콘/로고 파일은 직접 추적 허용.

---

## §0.7 Business-Only Test Scope — Full Detail

| FORBIDDEN | PERMITTED |
|-----------|-----------|
| Unit tests for simple field access / getters | Integration tests for business scenarios declared in `tests/gateway/*.feature` |
| Unit tests for type conversion (`$`, `parseInt`) | End-to-end tests for gate contracts (e.g., `passFilenames: false` cache key isolation) |
| Unit tests for error handling paths the compiler already checks | Workflow tests for 4-step integrity (Intent → Spec → Test → Code) |
| Mock-based tests that verify call order | Real binary execution tests that verify observable behavior |

- **No exceptions**: Even if a module is "critical", compiler-guaranteed behaviors do not get test exemptions.
- **Procedure gate enforcement**: `tests/gateway/*.feature` is the sole SSOT for test scope. Any test file not traceable to a `.feature` scenario is a zombie and MUST be deleted.

---

## §0.8 No Stub Files — Full Detail

- **Definition of a stub**: Any test file where >50% of assertions are `check true`, `doAssert true`, or empty `suite`/`test` blocks with TODO comments and no observable verification.
- **Immediate action**: Stubs are detected at gate time and the agent's work is **REJECTED** without review of the remaining code.
- **Agent accountability**: If an agent creates a stub file to artificially inflate test count or pass quality gates, the entire task is failed. The agent MUST delete its own stubs before requesting approval.
- **Detection**: `procedure-gate` runs static analysis on `tests/gateway/*_test.nim` to count `check true` density. Density ≥ 50% → automatic FAIL.

---

## §0.5c Structured Debt & Quirk Marker Policy (HARD RULE)

### Debt Tracking Pragma Specification

The `{.axiomDebt.}` pragma is the single source of truth for debt annotation in source code.

**Syntax**:
```nim
proc myProc() {.axiomDebt: "DEBT#243", kind: "quirk", category: "compiler", impact: "Low".} =
  # Implementation with known quirk
```

**Parameters**:
- `id`: `string` — DEBT#xxx identifier (mandatory)
- `kind`: `string` — `"debt"` (default) | `"quirk"` | `"theater"` | `"fixme"`
- `category`: `string` — free-form category (e.g., "compiler", "structural")
- `impact`: `string` — `"Critical"` | `"High"` | `"Medium"` | `"Low"`

**Enum-backed validation**: `src/core/types/debt_types.nim` defines `DebtKind` enum. The `parseDebtKind()` function converts strings to `DebtKind` at runtime.

### QUIRK(DEBT#xxx) Comment Marker Convention

Structured quirk markers in comments MUST follow this pattern:
```nim
# axiom:quirk(DEBT#390) — Nim VM stack limit workaround
```

**Rules**:
1. **No standalone euphemisms**: Bare `quirk`, `hack`, `workaround` in comments are blocked by `architecture_invariants.nim` compile-time scan.
2. **Structured exemption only**: `axiom:quirk(DEBT#xxx)` pattern is allowed (exempt from euphemism ban).
3. **DEBT#xxx must exist**: The ID must correspond to an entry in `data/debt_registry.json` (validated by `debt_integrity_gate.nim` at runtime).
4. **DEBT# prefix**: Use `DEBT#` (hash), not `DEBT-` (dash), to match existing convention.

**Enforcement**:
- **Compile-time**: `architecture_invariants.nim` → `executeAntiSlackingScan` macro (line-by-line, with exemption)
- **Runtime**: `debt_integrity_gate.nim` → bidirectional binding check (code marker ↔ registry entry)

### Migration Path

Existing euphemism markers (`# hack`, `# workaround`) should be migrated:
1. Create a debt registry entry in `data/debt_registry.json`
2. Add `{.axiomDebt: "DEBT#xxx", kind: "quirk".}` pragma to the proc/type
3. Update the comment to `# axiom:quirk(DEBT#xxx) — description`

### Quirk Evaluation Protocol (Decision Tree for Agents)

When discovering a potential language/compiler/stdlib quirk, follow this exact sequence:

```
[ Quirk keyword detected ("quirk", "hack", "workaround", "fixme", "xxx") ]
  │
  ├─→ [ Is it standalone? (no DEBT#xxx ID) ]
  │        │
  │       YES ──→ ❌ THEATER VIOLATION (AGENTS.md §0.9)
  │                Remove or add DEBT#xxx ID
  │
  └─→ [ Has DEBT#xxx ID? ]
           │
          YES
           │
           ├─→ [ Does DEBT#xxx exist in data/debt_registry.json? ]
           │        │
           │       NO ──→ Create registry entry first
           │                (category: "Quirk/<topic>")
           │
           └─→ [ Has {.axiomDebt.} pragma? ]
                    │
                   NO ──→ Add pragma: {.axiomDebt: "DEBT#xxx", kind: "quirk".}
                   │
                  YES
                   │
                   └─→ ✅ VALID SPEC (do NOT modify/remove)
                         Update comment to # axiom:quirk(DEBT#xxx) — description
```

**0-Token Skip Rule**: Before investigating, check `data/debt_registry.json`. If `DEBT#xxx` entry exists with `resolution: "FALSE_POSITIVE"` or `resolution: "FIXED"`, skip investigation (per §0.9a).

**Example Workflow**:
1. Agent finds `result = parseEnum[DebtKind](s)` in `debt_types.nim`
2. Checks `data/debt_registry.json` for `DEBT#390` → not found
3. Creates `DEBT#390` entry (category: `Quirk/NimParseEnum`)
4. Quirk 규격에 따라 문법을 기록 (§0.5b의 정식 `QUIRK(DEBT#xxx)` 마커 — 비정식 `// quirk`/`// hack` 주석 금지)
5. Adds pragma: `{.axiomDebt: "DEBT#390", kind: "quirk".}`
6. Updates comment: `# axiom:quirk(DEBT#390) — parseEnum not compile-time`

---

## §0.9b Infinite Regress Termination — Full Detail (HARD RULE)

**Problem**: "Who verifies the verifier?" leads to infinite regress. Checking `static_gate_scanner.nim` with itself is circular.

**Solution — Triple-Closure Architecture**:

1. **External Mutation Harness** (Process Boundary)
   - `tools/mutation_harness.sh` injects fake stubs and expects build failure.
   - If build passes → `static_gate_scanner.nim` is theater (FAIL).
   - **Verifies**: Scanner's operational correctness.

2. **Human Static Audit** (TCB Boundary)
   - `static_gate_scanner.nim` is kept as a small, pure-functional compile-time scanner. NOTE: the file is currently 121 lines (not ≤50); this deviation is tracked transparently as **DEBT#404** (architect-approved option B, 2026-08-02) — thin-shadow splitting was rejected as theater risk (§0.9) and logic was not shrunk. Awaiting future amendment.
   - Humans audit the scanner TCB directly — no tool recursion needed.
   - **Verifies**: Scanner's logical correctness.

3. **Orthogonal Domain Partitioning** (Language Boundary)
   - Nim engine (`static_gate_scanner.nim`) verifies Nim code only.
   - Lean 4 engine (`ax_vacuity_check.lean`) verifies Lean proofs only.
   - Two engines in different languages cannot share a bug.
   - **Verifies**: Full system coverage.

**When suspecting theater in source code, agents MUST follow this 3-step verification**:

```
Step 1: Run `tools/mutation_harness.sh` (or equivalent CI check)
        └── If PASS → Scanner works → Proceed to Step 2
        └── If FAIL → Scanner is theater → Register DEBT entry

Step 2: Audit `src/gate/static_gate_scanner.nim` (small TCB; currently 121 lines, deviation tracked as DEBT#404)
        └── Check: pure functions, no side effects, correct logic
        └── If suspicious → Register DEBT entry

Step 3: Verify both engines independently
        └── Nim: `nim c bin/axiom.nim` (build success)
        └── Lean: `lake build` (proof compilation)
        └── If either fails → Investigate domain-specific theater
```

**Enforcement**: Skipping any step = task failure. `static_gate_scanner.nim` alone is NEVER sufficient.

---

## §0.12 제품 계약 및 수직 슬라이스 우선 — 전문(체크리스트) (HARD RULE)

AGENTS.md §0.12의 constitutional 원칙(제품 계약·acceptance criteria가 구현에 선행한다)이 정본이며, 본 섹션은 그 실행 체크리스트를 보존한다. AGENTS.md에서 발췌(2026-10-03).

Axiom 개발은 **커밋된 제품 계약과 고객 대면 수직 슬라이스**로 주도한다 — 서브시스템 완결성이 아니다. **제품 계약 먼저**: 구현/대폭 확장 전에 봉사하는 커밋된 계약을 식별. **수직 슬라이스 먼저**: 서브시스템 생성 전에 구체적 고객 대면 슬라이스를 닫거나 계약을 만족시킴을 확립.

구현 전 5문항: ① **제품 계약** — 어떤 명시적 계약/사용자 가시 동작을 만족, 없다면 왜 지금인가; ② **고객 필요** — 어떤 구체적 제품 문제가 의존하는가; ③ **수직 슬라이스** — 어떤 종단간 슬라이스를 닫고 고객 가치는 어디인가; ④ **최소 범위** — 가장 작은 구현은 무엇, 무엇을 유보하는가; ⑤ **Acceptance** — 계약 만족을 보여주는 실행 가능한 테스트/골든 픽스처는 무엇인가.

규칙: 우아함·재사용·이론·미래 필요만으로 서브시스템 금지; 최소 변경 우선; 고객 무관하면 유보; 슬라이스 선행은 correctness·integrity·reproducibility·determinism의 검증된 전제조건일 때만. 단위 테스트·아키텍처 품질·커버리지는 제품 준비성을 **입증 못한다** — 종단간 계약이 필요하다. 서브시스템 생성 자체는 산출물이 아니다.

### 제품 계약 SSOT

`docs/spec/productization_contract.md` + `config/readiness_policy.json` + `tools/readiness_evaluator.nim`이 범위 정의. 충돌 시: 계약 보존 → 최소 변경 → 무관 유보 → 확장 전 계약 명시 개정. 모든 새 공개 표면/지표/산출물/주장은 계약 또는 승인 개정으로 정당화.
