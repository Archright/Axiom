# Archright/nim-libp2p Actions 런 전수 감사 — "기존 6건 = Axiom 사전실험" 전제 판정 (2026-11-09)

> **종류**: 이력 감사 관측 기록. **판정 권위는 기계 관측이며, 이 문서는 그 기록이다.**
> **Date**: 2026-11-09 · **Branch**: `workstream/external-verification-campaign-contract` (base `be4e28a` = main @ PR #31 merge)
> **관측 대상**: Archright/nim-libp2p의 GitHub Actions 런 전수와 저장소 이력 — 외부검증 캠페인 계약([external_verification_campaign_contract.md](../spec/external_verification_campaign_contract.md) §8)이 분류 대상으로 지정한 "2026-11-08 13:32–14:57Z 런 6건"의 정체, 그리고 그 런들이 "Axiom 사전실험"인지 여부.
> **관측 도구·계정**: `gh` CLI(공식 네이티브 인증 경로, AGENTS.md §2.4) — 계정 `wintrover`(keyring 로그인). 관측 시각 2026-11-09T00:43:36Z 전후(각 관측은 아래 표의 명령 그대로 실행).

---

## §1. 관측 계약

이 감사가 답하는 질문과 판정 기준:

- **질문**: Archright/nim-libp2p에서 (a) Actions 런의 전수 분포, (b) 2026-11-08 13:32–14:57Z의 런 6건 정체, (c) Axiom 워크플로의 실행 이력 유무.
- **판정 기준**: 캠페인 계약 §8 — 해당 6건이 Axiom 실행이 아니라면 정식 S4 증거 승격 대상이 없다. 판정은 관측된 워크플로명·이벤트·실행 횟수로만 내린다(추정·기억 아님).
- **범위 외(Non-Conclusions는 §5)**: revert 동기, upstream(iftech) 측 런과의 비교, 개별 런 실패 원인 진단.

## §2. 관측 환경

| 항목 | 값 |
|---|---|
| 관측 시각 | 2026-11-09T00:40–00:44 UTC (관측 세션 실측) |
| 도구 | `gh` CLI + REST API(`gh api`) — 각 관측 아래 표에 명령 원문 기록 |
| 계정 | `wintrover`(해당 저장소 토큰 permissions: admin·maintain·push 전부 true — §3.6) |
| 관측 대상 | `Archright/nim-libp2p`(공개 fork — §3.1) |
| 관측 시점 저장소 상태 | master head `70a64acc`, pushedAt `2026-11-08T11:50:29Z` |

## §3. 기계 관측 (전부 명령→관측→exit 0)

### 3.1 저장소 신원 — iftech/nim-libp2p의 공개 fork

| 명령 | 관측 |
|---|---|
| `gh api repos/Archright/nim-libp2p --jq '{fork, parent.full_name, source.full_name, visibility, default_branch, pushed_at}'` | `fork: true` · `parent: iftech/nim-libp2p` · `source: iftech/nim-libp2p` · `visibility: PUBLIC` · `default_branch: master` · `pushed_at: 2026-11-08T11:50:29Z` |
| `gh api repos/Archright/nim-libp2p/branches/master` | head `70a64acc…` · `protected: false` |
| `gh api 'repos/Archright/nim-libp2p/compare/master...iftech:nim-libp2p:master'` | `status: diverged` · base(Archright) 기준 **ahead_by 2 / behind_by 28**(head가 base보다 28 커밋 앞섬 = Archright가 upstream 대비 28 뒤짐·2 앞섬) · merge_base `2ab3c1ec` |

### 3.2 fork의 유일한 자체 커밋 2개 — byo-agent-verify.yml 추가→revert

| 명령 | 관측 |
|---|---|
| `gh api 'repos/Archright/nim-libp2p/compare/2ab3c1ec...master' --jq '.commits[]'` | 병합 기점 이후 커밋 정확히 2개(아래) |
| `gh api repos/Archright/nim-libp2p/commits/cfed3871` | `cfed3871` · 2026-11-03T02:38:59Z · 메시지 `ci(byoa): customer BYO-Agent verification workflow — pinned propositions + Axiom reusable workflow (dry-run=false)` · 파일 `.github/workflows/byo-agent-verify.yml` **added**(+97) |
| `gh api repos/Archright/nim-libp2p/commits/70a64acc` | `70a64acc` · 2026-11-03T02:44:37Z · 메시지 `Revert "ci(byoa): customer BYO-Agent verification workflow…"` · parent `cfed3871` · 파일 동일 **removed** |
| `gh api 'repos/Archright/nim-libp2p/contents/.github/workflows/byo-agent-verify.yml?ref=cfed3871'` (base64 복호) | `on: workflow_dispatch:` 단일 트리거(input `mode`: main/empty/mismatch) — **dispatch 전용**. 헤더 주석 "Customer-side BYO-Agent workflow — Phase 4 acceptance deployment" |

→ 워크플로 파일이 master에 존재한 기간은 **2026-11-03T02:38:59Z–02:44:37Z(약 6분)** 이며, fork의 다른 모든 변경은 없다(ahead 2 = 이 커밋 쌍 전부).

### 3.3 Actions 런 전수 — 100런, 기간·이벤트 분포

| 명령 | 관측 |
|---|---|
| `gh api 'repos/Archright/nim-libp2p/actions/runs?per_page=1' --jq '.total_count'` | `100` — 저장소 전체 런 수 = 100(전수 감사 가능) |
| `gh run list -R Archright/nim-libp2p --limit 100 --json createdAt` (정렬) | 런 기간 `2026-11-02T15:37:55Z` – `2026-11-08T22:55:29Z` |
| `gh run list -R Archright/nim-libp2p --limit 100 --json event` (group_by) | `schedule 70` · `push 18` · `workflow_run 6` · `dynamic 6` |
| `gh run list -R Archright/nim-libp2p --limit 100 --json workflowName` (unique) | **21종 워크플로** — `C bindings, CodeQL, Coverage, Daily CI Failure Report, Daily interop, Daily runnableExamples, Daily test all (latest dependencies), Daily without feature flags, Dependencies, Dependency Graph, Documentation Generation And Publishing, Examples, Interoperability Tests, Mobile Android, Mobile iOS, Nimbus fleet, Nimbus soak, Nimbus test, Test All, Test AutoTLS Docker Integration, Test Multiformat Extensions` — **Axiom/BYO 명칭 0건** |

### 3.4 2026-11-08 13:32–14:57Z 런 6건 — 상세

`gh run list -R Archright/nim-libp2p --limit 100 --json …` (13:00–15:30Z 필터) 관측, 전부 `headBranch: master`:

| run id | 워크플로 | 이벤트 | 생성(UTC) | conclusion |
|---|---|---|---|---|
| `42485420720` | Nimbus soak | schedule | 2026-11-08T13:32:11Z | success |
| `42486131410` | Nimbus test | schedule | 2026-11-08T13:41:11Z | success |
| `42486412131` | Daily test all (latest dependencies) | schedule | 2026-11-08T13:44:50Z | **failure** |
| `42489730117` | Daily interop | schedule | 2026-11-08T14:25:22Z | success |
| `42490968649` | Daily runnableExamples | schedule | 2026-11-08T14:40:35Z | success |
| `42492363831` | Nimbus fleet | workflow_run | 2026-11-08T14:57:58Z | **skipped** |

보충 관측: `gh run view 42492363831` → `event: workflow_run` · `conclusion: skipped`(headBranch master).

### 3.5 Axiom 워크플로 실행 — 0회

| 명령 | 관측 |
|---|---|
| `gh workflow list -R Archright/nim-libp2p --all` | 21종(§3.3과 동일 + `dynamic/dependabot/update-graph`·`dynamic/github-code-scanning/codeql`) — `byo-agent-verify.yml` **부재** |
| `gh run list -R Archright/nim-libp2p --workflow byo-agent-verify.yml` | HTTP **404** `workflow byo-agent-verify.yml not found on the default branch` — 기본 브랜치에 존재하지 않음(revert됨) |
| 전수 런 100건의 워크플로명 unique(§3.3) | Axiom/BYO 관련 이름 0건 |

→ 관측 시점 기준 이 저장소에서 Axiom 워크플로가 실행된 적은 **한 번도 없다**: 총 런 100건 전수에 Axiom 워크플로가 없고, 유일한 Axiom 관련 파일(`byo-agent-verify.yml`)은 dispatch 전용으로 존재하다가(6분) 실행 없이 revert되었다. (주의: `byo-agent-verify.yml`이 **Phase 4 배포**였다면 그 실행 흔적이 있어야 하는데 0회다 — §5 Non-Conclusions 참조.)

### 3.6 토큰·Actions 권한

| 명령 | 관측 |
|---|---|
| `gh api repos/Archright/nim-libp2p --jq '.permissions'` | `admin: true` · `maintain: true` · `push: true` · `triage: true` · `pull: true` — **ADMIN 토큰** |
| `gh api repos/Archright/nim-libp2p/actions/permissions` | `enabled: true` · `allowed_actions: "all"` · `sha_pinning_required: false` |

## §4. 판정

**판정 — "기존 6건 = Axiom 사전실험" 전제는 거짓(False)**:

1. 2026-11-08 13:32–14:57Z의 런 6건은 전부 **업스트림 상속 daily CI 워크플로**(Nimbus soak·Nimbus test·Daily test all·Daily interop·Daily runnableExamples·Nimbus fleet(workflow_run → skipped))의 schedule/workflow_run 실행이다(§3.4). 이 워크플로들은 fork가 iftech/nim-libp2p에서 물려받은 것이며 — fork의 자체 커밋은 byo-agent-verify.yml 추가·revert 쌍뿐이다(§3.2) — 어느 것도 Axiom과 무관하다.
2. 이 저장소의 **Axiom 워크플로 실행 횟수는 0회다**(§3.5). 유일한 Axiom 흔적은 2026-11-03의 `byo-agent-verify.yml` 커밋 `cfed3871`(97줄 추가) → 6분 뒤 `70a64acc`(revert)이며, 실행 흔적이 전혀 없다.
3. 따라서 캠페인 계약 §8의 분류가 그대로 확정된다: 해당 6건에 대해 **정식 S4 증거로 승격할 대상이 없다** — 진단 자료로 보존한다. 이 판정은 관측에 근거하므로 수정을 수반하지 않는다(관측 문서 비행 — docs-only).

## §5. Non-Conclusions / Follow-up 후보 (범위 밖, 미관측·미판정 명시)

- **revert 동기 미관측**: `70a64acc`는 메시지에 사유 없는 순수 revert다(이슈·PR 참조 없음, `has_issues: false`). 왜 6분 만에 회수됐는지는 이 감사로 알 수 없다.
- **pushedAt 2026-11-08T11:50:29Z의 해석**: `gh-pages` 브랜치 head `d574f7cb`(committer date 2026-11-08T11:50:28Z) 및 "Documentation Generation And Publishing" schedule 런(11-08T11:44:41Z)과 시각이 정합하므로 **gh-pages 일일 퍼블리시(schedule)** 해석이 유력하나, 이는 상관 관측이지 인과 판정이 아니다 — 본 감사는 확정하지 않는다.
- **Nimbus fleet skipped의 사유 미관측**: workflow_run 트리거 조건이 왜 skip으로 귀결했는지는 조사하지 않았다.
- **upstream(iftech) 측 런과의 대응 비교 미수행**: 6건의 schedule이 upstream에서 동일 시간대에 실행됐는지는 관측하지 않았다(fork CI의 schedule이 upstream과 같은 정책임은 워크플로 파일 상속으로 정합하나, 런 대응은 미확인).
- **Daily test all (latest dependencies) `42486412131` failure의 원인 진단 미수행**: 캠페인과 무관한 upstream CI 실패 — 범위 밖.

## §6. 착지

본 문서는 캠페인 계약(§1 매니페스트 식별자 확정의 전제)과 함께 docs-only PR로 착지한다: 커밋 후 PR(base main) 생성 → 어드미션 게이트 관측(`gh pr checks`) → 전부 통과 시 GitHub 네이티브 merge(auto-merge, `--match-head-commit` 핀 — merge authority는 GitHub, AGENTS.md §2.3). merge SHA는 최종 보고에 기록한다.
