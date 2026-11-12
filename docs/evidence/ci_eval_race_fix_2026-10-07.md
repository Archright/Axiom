# CI 평가 레이스 수정 — mint-publish ← gateway 간선 복원 (run 37569755722 실측)

- 측정일: 2026-10-07 (UTC)
- 분류: CI 구조적 레이스(오검증) 수정 — 타이밍 회피가 아닌 의존관계 선언
- 관측 대상 워크플로: org 위임 오케스트레이터 `Archright/.github` `admission-gate.yml`
  (org ruleset 24233738 `axiom-admission-gate` — target branch main, repository Axiom,
  workflow ref = **org main HEAD**, `gh api orgs/Archright/rulesets/24233738` 실측)
- 수정 PR: Archright/.github #62 (merge `3a0ae4cced8a535c055ad1eecd4c2476b2e0678c`) —
  `mint-publish: needs: [mint-prepare]` → `[mint-prepare, gateway]`
- surface 정책: 본 저장소 v62 (knownBlindSpots — caller DAG 무감시 한계 기록)

## 1. 증상 (반복 재현, 2026-10-07)

`mint-publish / publish` job의 (P6) `[B2] (c)` 단계(certificate-mint.yml)가
jobs API로 gateway lane의 결론을 집계할 때, lane이 아직 실행 중이면 in-progress
job을 "abnormal conclusion"으로 fail-closed → 오검증 red → **런 전체 재실행
(attempt 3)에서만 green**.

### attempt 1 타임라인 (run 37569755722, PR #535, 이벤트 pull_request)

| job | 결론 | started (UTC) | completed (UTC) |
|---|---|---|---|
| attest / build-base-artifacts | success | 04:05:10 | 04:08:15 |
| gateway / select | success | 04:05:12 | 04:06:43 |
| gateway / ci-bootstrap | success | 04:07:22 | **04:11:18** |
| attest / admission-check | success | 04:08:18 | 04:09:23 |
| mint-prepare / prepare | success | 04:09:26 | 04:09:49 |
| **mint-publish / publish** | **failure** | **04:09:52** | 04:10:13 |
| gateway / proof-reconcile | skipped | 04:11:18 | 04:11:18 |

- (P6) 평가 시각 **04:10:10Z** (job log `MINT_PUB_JOBS` 스텝 시작, job 112626633133)
- 실패 메시지: `MINT_PUB_JOBS: FAIL — 1 gateway-lane job(s) with abnormal
  conclusion (≠ success/skipped) — [B2] (c) (fail-closed)` — 대상 =
  in-progress `gateway / ci-bootstrap` (완료 04:11:18Z)
- 최종: `admission-check` failure (04:11:22)

### attempt 2 (부분 rerun — "re-run failed jobs")

- `mint-publish / publish`만 재실행 (04:14:00): mint-prepare/prepare는 재실행되지
  않아 `subject-certificate-2` artifact가 존재하지 않음 →
  `MINT_PUB_ART: FAIL — expected exactly one artifact named
  'subject-certificate-2', found 0` (job 112627683772)
- **별도 잔여**: attempt 스코프 artifact 규약(`subject-certificate-<run_attempt>`,
  `admission-check-<head>-<run_attempt>`)과 부분 rerun(성공 job 미재실행)의
  상호작용 문제 — 본 수정(의존관계)이 해소하지 않는다(§4 참조)

### 반복 관측

- PR #525 (attempt 2 부분 rerun 실패), PR #535 (동일) — 동일 양상

## 2. 근본 원인 (구조)

- org caller DAG: `mint-publish: needs: [mint-prepare]` — gateway 간선 부재.
  구 DAG(94a6f0864 freeze tag)는 `needs:[mint-prepare, gateway, tree-identity]`
  였으나 N+5 재등록 때 제거. **당시엔 무해**: callee (P5)/(P6)가 SL-0713
  NO-FIRE로 스킵됐다.
- N+6 gateway 래퍼 부활 + SL-0713 승격으로 callee publish job이 lane을
  직접 평가하게 됨 — (P5) `tested-tree-digest` artifact 소비 + (P6) jobs API
  lane conclusion 집계. 간선 부재가 레이스로 전환.
- callee는 자신의 시작 시점을 결정할 수 없다(reusable workflow_call callee는
  caller가 호출한 시점에 시작) — 수정은 반드시 caller 그래프여야 한다.

## 3. 수정

- `Archright/.github` PR #62: `mint-publish: needs: [mint-prepare, gateway]`
  (+ `if: !cancelled()` 유지 — gateway 실패/스킵 시에도 publish가 실행되어
  lane의 실제 결론을 fail-closed 보고; 최종 `admission-check` aggregate가
  `RESULT_GATEWAY`로 독립 차단 — never green 불변)
- GitHub Actions 공식 근거 (docs.github.com/en/actions, Context7 경유):
  - `jobs.<job_id>.needs` = "any jobs that must **complete successfully before
    this job will run**" — 호출 job(callee workflow 완료에 완료)의 완료를
    그래프로 보장
  - "If a job fails or is skipped, all jobs that need it are skipped **unless
    the jobs use a conditional expression that causes the job to continue**"
    — `!cancelled()`가 그 조건식

## 4. 잔여 (수정 범위 밖)

1. **부분 rerun artifact 혼재**: `subject-certificate-<run_attempt>` /
   `admission-check-<head>-<run_attempt>` 규약은 attempt 스코프인데, "re-run
   failed jobs"는 성공 job을 재실행하지 않아 새 attempt의 artifact가 없다.
   의존관계 수정은 첫 런의 레이스를 제거해 부분 rerun 빈도를 낮추지만, 다른
   원인의 부분 rerun에는 동일 실패가 남는다.
2. **caller-DAG 무감시**: 본 저장소의 surface 게이트는 caller needs-graph를
   볼 수 없다(파일이 org repo) — v62 knownBlindSpots 기록. caller-DAG 미러
   게이트는 후속 과제.

## 5. 관측 기록 (post-fix)

- 본 문서와 동일 PR(`fix/ci-mint-eval-race`)의 admission-gate 런에서
  수정 그래프 첫 관측: mint-publish 시작 시점 > gateway/ci-bootstrap 완료
  시점 — 수치는 PR 본문에 기록 (live run).
