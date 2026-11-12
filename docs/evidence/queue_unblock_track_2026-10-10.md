# merge queue 봉쇄 해소 트랙 — 실행 증거 (2026-10-10)

- **성격**: 사후 실행 기록(관측). 2026-10-09 merge queue 봉쇄의 3레이어 치유 체인, canary 실증, #654 착지, 창(window) 절차 감사 2회, merge_group `admission-gate` 벽시계 latency 관측을 담는다.
- **측정 방법**: GitHub REST API + `gh` CLI로 문서화 시점(2026-10-10)에 전수 재확인 — PR 상태·merge SHA·verdict 원문(job 로그)·ruleset history·workflow run 시간 필드. 원 기록과 관측이 다른 지점은 **관측값을 기준**으로 기록하고 그 차이를 명시한다(§1-②, §5-장벽).
- **판정 요약**: 봉쇄 3레이어(핀 회전 → deriver toolchain → rotation 정합 3종)가 순차 치유됐고, canary(PR #662)와 #654가 정상 merge queue 경로로 착지했다. 창 절차 2회 모두 3-ruleset 동시 비활성→병합→복원이며 최종 상태는 `active`/bypass 없음. admission-gate 벽시계는 n=82에서 중앙값 881s·p90 1065s·최대 1156s.

---

## §1. 봉쇄의 3레이어 치유 체인

### §1-①. callee 워크플로 핀 회전 (제1층)

main head가 다음 4개 병합을 거치며 callee 워크플로(`.github/workflows/*.yml`)가 회전했다 (실측: `git log --oneline <sha>` + `git show --stat`):

| main head | 병합 PR | 제목 | 닿은 callee 파일 |
|---|---|---|---|
| `a24abfc8e` | #656 | fix(ci): P7c-x judgment ledger append landing venue gate 복원 | `.github/workflows/certificate-mint.yml` (+2) |
| `829b188a5` | #660 | feat(merge): S1 proof-required vault admission (Pass 2.96b) | `.github/workflows/admission-check.yml` (+25) 등 |
| `73ed69a5a` | #665 | fix(ci): verdict provision-scope=full (§1-②) | — |
| `88b52abec` | #667 | fix(admission): rotation 정합 3종 (§1-③) | — |

관측 교정: 원 계획의 "dependabot 경로" 표기와 달리, 이 구간(최근 150커밋)에서 dependabot 커밋은 관측되지 않았고 실측 착지 경로는 PR #656·#660(작성자 `wintrover`, 2026-10-09)이다. 본 문서는 관측된 회전 체인만 기록한다.

### §1-②. #665 "verdict provision-scope=full" (제2층)

- **병합**: PR #665 — **MERGED**, mergeCommit `73ed69a5aec0b73fdd0cbb4ef643e4e4fb3b3f03`, mergedAt `2026-10-09T16:05:36Z` (문서화 시점 `gh pr view` 재확인).
- **원인(결함)**: merge_group 큐의 deriver `nim c`가 runtime-scope job에서 nim을 프로비전받지 못해 fail-closed.
- **실측 원문**(`command not found`):
  - run `37956296799` (pr-665-829b188a, created `16:03:22Z`, failure): `2026-10-09T16:11:37Z /home/runner/work/_temp/c2489fa5-dff7-4ae2-b205-59071caf987c.sh: line 37: nim: command not found`
  - run `37956185277` (pr-665-96520f23, created `16:02:28Z`, failure): `2026-10-09T16:19:51Z /home/runner/work/_temp/6443c500-cb16-4334-860b-775c8473b01b.sh: line 37: nim: command not found`
- **관측 교정**: 원 기록이 이 결함의 실측 런으로 지목한 `37957738444`(created `16:15:04Z`, failure)는 **#665 착지(16:05:36Z) 이후 첫 큐 진입**으로, 이 런에서 deriver는 성공했다(provision-scope=full 효과). 이 런이 노출한 것은 다음 층의 결함이다(§1-③).

### §1-③. #667 "rotation 정합 3종" (제3층)

- **병합**: PR #667 — **MERGED**, mergeCommit `88b52abece2f18272d90f48883f7f1df699faaca`, mergedAt `2026-10-09T17:08:38Z`. 내용 커밋 `6f8b3e12c` "fix(admission): rotation 정합 3종 — H 참조·pin@H 소스·trustedCheckerTreeClosure 재앵커".
- **수정 3종**: (1) rotation 판정이 H를 workspace HEAD(=B)에서 읽는 오유 → **PR head**에서 읽도록 수선, (2) pin@H를 B에서 복사하던 오유 → **`git show $H_SHA:`** 로 H 트리에서 직접 조회, (3) `trustedCheckerTreeClosure` **840키(stale) → 857행** 재앵커.
- **수정 전 실패 원문** — run `37957738444` verdict job(2026-10-09T16:33:16Z):

  ```
  [INFO] merge_cli: [dry-run] mergeAborted (ROT_ALLOWLIST): closure mismatch requires ROTATION
  but changed path(s) fall outside the allowlist (closure pin@B keys ∪ docs/adr/** ∪
  config/trusted_writer_set.json ∪ admission-check.yml·certificate-mint.yml·회전 데이터·회전 테스트
  — ADR-0025 A2) — subject Δ != 0 (fail-closed)
  ```

  동일 런 verdict JSON: `"qualification":"NONE"`, `"closureEqual":false`, `"oldAnchorOk":false`, `"newAnchorOk":false`, `"subjectDeltaZero":false` — H를 B에서 읽고 pin@H를 B에서 복사하던 시점의 fail-closed 상태를 그대로 보존한다.

## §2. canary 실증 (5요소)

- **PR #662** "docs(evidence): queue unblock canary — DEBT#501 치료 실증" — **MERGED**, mergeCommit `c3e8d8494947733a1bb3cba5fb72f3635cc6412e`, mergedAt `2026-10-09T17:50:40Z`.
- admission-gate run `37967891212`의 verdict job 로그(`1_verdict _ admission-check.txt`, 2026-10-09T17:50:04Z)에서 verdict 원문 전체:

```json
{"prNumber":662,"headSha":"aade8265ef6e838dbf131092c3a8dec6d9cb6e9b","baseSha":"88b52abece2f18272d90f48883f7f1df699faaca","verdict":{"result":"mergeGo","reasonCode":"GO","reason":"admission passes cleared (base provenance bound to main 88b52abece2f; landing freshness enforced by merge-queue invalidation — ADR-0027 P5)"},"qualification":"NORMAL","rotationCheck":{"closureEqual":true,"changed":["docs/evidence/queue_unblock_canary_2026-10-10.md"],"allowlistOk":true,"subjectDeltaZero":true,"genesis":false,"oldAnchorOk":true,"newAnchorOk":true,"delegatedToPlatform":true},"rotationNote":"","vaultCert":{"required":true,"targets":null},"preflight":false}
```

5요소 대조표:

| 요소 | 기대 | 실측 |
|---|---|---|
| qualification | `NORMAL` | `"qualification":"NORMAL"` ✓ |
| result / reasonCode | `mergeGo` / `GO` | `"result":"mergeGo"`,`"reasonCode":"GO"` ✓ |
| rotationCheck.closureEqual | `true` | `true` ✓ |
| changed | canary 파일 단독 | `["docs/evidence/queue_unblock_canary_2026-10-10.md"]` 1건 ✓ (동일 런 로그 `phase=fact-pr-files … files=1 complete=true`) |
| oldAnchorOk / newAnchorOk | `true` / `true` | 둘 다 `true` ✓ |

derived in-place: `H=aade8265…`(merge-queue 임시 head) `B=88b52abe…`(base) — verdict JSON의 headSha/baseSha와 동일.

## §3. #654 착지

- **PR #654** "docs(authority): Slice 0 — 권한 선언 (Owner 결정 #19 + ADR-0033 + surface v72)" — **MERGED**, mergeCommit `999327ab088a73d80f4088f21d4625b4c0587867`, mergedAt `2026-10-09T17:55:28Z`.
- admission-gate run `37967892805` verdict 원문(2026-10-09T17:55:04Z): `"result":"mergeGo"`, `"reasonCode":"GO"`, `"qualification":"NORMAL"`, `"closureEqual":true`, `changed` 3파일 — `config/repository_surface.json`, `docs/adr/0033-authority-declaration.md`, `docs/spec/repository_surface_contract.md`.
- **기대 위반 집합 선언과의 일치**: PR 본문 선언 — "기대 위반 집합 = 정확히 1건 {config/repository_surface.json M FROZEN SURFACE_FORBIDDEN} — pre-push surface_guard 출력 실측 일치(v71 base binding, changeCount 3)". 관측된 changed 3파일 중 FROZEN 위반은 선언대로 `config/repository_surface.json` 1건이며 나머지 2건은 정책 문서 경로다.

## §4. 창 절차 감사 (2회)

ruleset history REST API(`rulesets/{id}/history`)로 버전 시계열을 실측했다. 표기는 UTC 환산(+09:00 원본 → −9h).

### (i) #665 창 — 16:04:07Z–16:05:51Z

| ruleset | 비활성(version_id @시각) | 복원(version_id @시각) |
|---|---|---|
| repo `20303214` (main) | 52593105 @ 16:04:07Z | 52593300 @ 16:05:49Z |
| org `24233738` (axiom-admission-gate) | 52593225 @ 16:05:12Z | 52593303 @ 16:05:50Z |
| org `23943917` (landing-integrity) | 52593269 @ 16:05:33Z | 52593307 @ 16:05:51Z |

병합 #665 = 16:05:36Z — 창 내부. 창 폭 ≈ 1분 44초.

### (ii) #667 창 — 17:08:34Z–17:08:42Z

| ruleset | 비활성 | 복원 |
|---|---|---|
| repo `20303214` | 52599690 @ 17:08:34Z | 52599702 @ 17:08:40Z |
| org `24233738` | 52599693 @ 17:08:35Z | 52599706 @ 17:08:41Z |
| org `23943917` | 52599696 @ 17:08:36Z | 52599712 @ 17:08:42Z |

병합 #667 = 17:08:38Z — 창 내부. 창 폭 ≈ 8초.

### 공통 관측

- 모든 history 버전의 actor는 단일(`53123826` = `wintrover`).
- **병렬 워커·타 병합 없음**: 두 창 구간에서 main에 착지한 병합은 각각 #665·#667 단독이다 (main 병합 시각열 실측: 14:52:19 #660 → 16:05:36 #665 → 17:08:38 #667 → 17:50:40 #662 → 17:55:28 #654). 창 밖 큐 런은 병합 없이 in-place로 계속 실행됐고(예: 16:02–16:20Z의 failure 2건), 그 결과는 §1-②의 fail-closed 원문으로 기록됐다.
- **ruleset history가 감사 추적**: 위 버전 ID 시계열 자체가 비활성→병합→복원의 불변 기록이다.
- **최종 GET 검증(2026-10-10 실측)**: `GET /repos/Archright/Axiom/rulesets/{20303214,24233738,23943917}` → 세 ruleset 모두 `"enforcement":"active"`, bypass 필드 부재(bypass actor 0). org 목록 API에서도 24233738·23943917 `active` 재확인.

## §5. merge_group admission-gate 벽시계 latency

### §5-1. 측정 정의 (공식 문서 근거)

GitHub REST API "Get a workflow run" 응답의 run 오브젝트 시간 필드 정의(docs.github.com/en/rest/actions/workflow-runs — Context7 `/websites/github_en_rest`로 확인):

- `created_at` — "ISO 8601 creation timestamp" (런 레코드 생성)
- `run_started_at` — "ISO 8601 run start timestamp" (런 실행 시작)
- `updated_at` — "ISO 8601 update timestamp" (최종 갱신 = 완료 시각)

**벽시계 = `updated_at` − `run_started_at`** (런 시작 → 완료). 보충 실측: 이 범위의 merge_group 런은 `created_at == run_started_at` (생성과 시작이 동일 시각, 지연 0s).

### §5-2. 수집

```bash
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100"   # 3페이지
# 필터: name=="admission-gate" ∧ created_at ∈ [2026-10-09T00:00Z, 2026-10-10T23:59Z], id 중복 제거
```

- 고유 **82건** (success 34 / failure 48). 실측 생성 범위 `2026-10-09T00:04:04Z`–`21:27:06Z`; 2026-10-10에는 측정 시점까지 merge_group admission-gate 런이 0건이었다.
- 집계: p90은 최근위(nearest-rank, ⌈0.9·n⌉번째), 중앙값은 표준 정의.

### §5-3. 집계 (벽시계, 초)

| 모집단 | n | min | 중앙값 | p90 | 최대 |
|---|---|---|---|---|---|
| 전체 | 82 | 432s | **881s** | **1065s** | **1156s** |
| success | 34 | 511s | 892s | 1047s | 1099s |
| failure | 48 | 432s | 836s | 1100s | 1156s |

### §5-4. long-tail 사례 (상위 8건)

| run | PR(그룹) | 결론 | 벽시계 | 시작→완료(UTC) |
|---|---|---|---|---|
| 37923098545 | #652 | failure | 1156s | 11:20:18→11:39:34 |
| 37960510802 | #666 | failure | 1138s | 16:37:58→16:56:56 |
| 37969124445 | #664 | failure | 1118s | 17:50:42→18:09:20 |
| 37907825555 | #628 | failure | 1108s | 08:54:02→09:12:30 |
| 37957738444 | #662 | failure | 1100s | 16:15:04→16:33:24 (§1-③ 원문 런) |
| 37981200991 | #670 | success | 1099s | 19:34:57→19:53:16 |
| 37951806316 | #661 | failure | 1076s | 15:26:55→15:44:51 |
| 37993522451 | #674 | success | 1074s | 21:27:06→21:45:00 |

### §5-5. 런 37964818015 분해 — "verdict 직전 스케줄 지연" 가설에 대한 관측 교정

run `37964818015`(pr-662, success, 벽시계 1005s)에 대해 job 레벨 타임라인(jobs API + job 로그 타임스탬프)을 실측했다:

- job `created_at → started_at` 격차: 16개 job 전부 **≤3s** — 큐/러너 스케줄 지연 없음.
- `mint-publish/publish` 완료(17:28:56Z) → `verdict/admission-check` 시작(17:28:59Z) 인계 격차 **3s**.
- 벽시계의 53%(**537s**)는 `attest/admission-check` 잡(17:18:16→17:27:13Z)이 흡수했고, 그 로그에는 콜드 검증 스텝 다수(예: `executeCanonicalVerification` VERIFIED 실측 +38s, mul/div fixture +38s, S1-B identity fixture +45s, 캐시 복원 후 +43s)가 관측됐다.
- 같은 PR의 재큐 런 `37967891212`는 606s로 단축 — attest 잡 537s→119s. 캐시 웜 상태 차이가 지배 요인으로 관측된다.

**교정**: 원 기록의 "verdict 직전 job 스케줄 지연 정황"은 job 데이터로 재현되지 않았다. 관측된 장벽 원인은 스케줄 지연이 아니라 **attest/admission-check의 콜드 검증 계산**이다. 본 문서는 관측값을 기록한다.

측정은 관측 기록이며 최적화는 범위 밖이다 — 한 문장만: attest 콜드 스텝의 캐시 워밍 선행이 p90 단축 후보로 관측된다.

## §6. 참조 — REST PATCH 404 quirk

ruleset REST PATCH 404 quirk는 별도 quirk 문서(`docs/spec/`)에서 처리 중이다 — 본 문서에서는 다루지 않는다.

---

## 부록 A. 측정 환경·명령

- 측정일: 2026-10-10. 측정 저장소: `<user-home>/orca/workspaces/Axiom/queue-evidence` (`docs/queue-unblock-evidence` worktree, origin/main `7d7dc3ab9` 기반).
- PR 상태·merge SHA: `gh pr view {654,662,665,667} --json state,mergedAt,mergeCommit` → 전원 MERGED 재확인.
- verdict 원문: `gh api repos/Archright/Axiom/actions/runs/{37967891212,37967892805,37957738444,37956296799,37956185277}/logs` 압축 해제 후 job 로그에서 인용 (job 로그 단독 엔드포인트는 런 레벨 아카이브로 대체 — 터미널 이스케이프·워크플로 404 quirk).
- ruleset 상태·history: `gh api repos/Archright/Axiom/rulesets/{20303214,24233738,23943917}`, `gh api {repos/Archright/Axiom,orgs/Archright}/rulesets/{id}/history?per_page=30`.
- latency 수집·집계: `gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100"` 3페이지 → name·기간 필터·id 중복 제거 → python 집계(최근위 p90).
- 필수 로컬 검증(착지 전): `nimble build` → `nim c -d:danger -o:bin/build_all_gates tools/build_all_gates.nim && ./bin/build_all_gates --release` → `make bin/debt_engine bin/check_nim_theater bin/doc_path_validator bin/proof_unit_consistency_gate bin/proof_reconcile_gate bin/epoch_transaction_gate bin/layer_enforcement_gate` — 전부 통과(`ALL_HOOK_BUILDS_OK`).
