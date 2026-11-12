# Probe-C 사전등록 — 규범 면 세대 전진 후 비규범 docs-only PR의 판정 재사용 재개 (2026-10-31)

> **종류**: 판정 CAS 의미론 C셀 차량 사전등록. 본 문서는 Reporter다 — 판정 권한이 아니며 게이트·required check·병합 권한에 영향을 주지 않는다(AGENTS.md §2.3, Authority ≠ Adapter).
> **판정 극칙**: 본 문서는 기대를 등록할 뿐 결과를 대체하지 않는다. 실측은 착지 후 별도 증거 공개 PR이 GET-only 관측 원문으로 기록한다(본 문서는 착지 전에 고정).
> **Date**: 2026-10-31 · **Branch**: `work/judgment-reuse-probe-c` · **Scope**: 본 문서 1건(`docs/evidence/*.md`, N-class — semantic-set S 비멤버, `src/verification/semantic_set_derivation.nim:116-122` 배제표 N).

## §0. 상속·참조

| 권위 | 내용 | 위치 |
|---|---|---|
| 판정 CAS 계약 | 5조건·fail-closed("조회 실패도 MISS")·세대 전진 시 첫 실행=EXECUTED 후 재사용 재개 | `docs/spec/test_judgment_cas_contract.md` §5-§6, `:116` |
| 키 파생 | 피험 트리 = candidate M^tree(커밋 SHA는 키에 0개 — 내용 digest만) | `src/verification/judgment_cas.nim:421-468`, `admission-check.yml:3212,3216` |
| 규범 면 분류 | docs/spec/·docs/agents/·config/policy/·config/templates/ + AGENTS.md·DEBT_REGISTRY.md·nimble.lock = S 멤버(배제 금지) | `src/verification/semantic_set_derivation.nim:183-192,241-242` |
| 관측 프로토콜 | GET-only·merge_group 런이 admission authority | `docs/agents/merge_admission_observation.md` |

## §1. 배경 — A/B셀 관측 완결분 (등록 시점 기준)

- **A셀(PR #1145, 2026-10-31T10:49:11Z MERGED, merge `9c007db40`)**: 비규범 docs-only 1건 — merge_group 런 41193592538에서 4주체 `basis=REUSED`: s1a 레코드 `7fe9623ad931099bc275198c18fccd59570b6991c3b3244ef8554e4bc9e66f6d` 재검증 통과(lane-0 로그 원문 `AXIOM_JUDGMENT_CAS: REUSED — record 7fe9623ad931 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)`), proof_integrity `578fc904eb8b`, d2_golden `5dda82170208`, d2_persist `9707696c8353`. probeTreeOid `67e7993bdeaf07686ccc14fd621b0b8933c35317`.
- **B셀(PR #1146, 2026-10-31T11:27:31Z MERGED, merge `04d2c409d`)**: 규범 면 `docs/agents/logging.md` 1줄 명확화 — merge_group 런 41196023170에서 4주체 `basis=EXECUTED — no record for the current closure (fresh judgment)`(테스트 실실행 PASS): s1a `7f58908b6d59e670aa6b24ec28f015d4788e65070b01cc01eb3b5a03f93cb540`·proof_integrity `f60864fa4abd…`·d2_golden `b078f31029ce…`·d2_persist `77008e499453…`. probeTreeOid `1ce1ae0161cd975b34e1960d6a8dbfb5e3562f7c`. 사이드 ref `axiom/evidence-cas` `9dceed1b2`→`7a1fd6342` 전진(append 5건: 4 judgment 레코드 + 착지 증거 `71b25391d828…`) — B 착지 런의 mint가 S1 레코드를 발화.

## §2. C셀 기대 — 4행 판정표

본 PR(비규범 docs-only 1건 추가)의 merge_group admission 관측에 적용한다:

| 관측 결과 | 판정 |
|---|---|
| S0(구세대 `7fe9623ad931` 계열) 레코드 재사용 | **위반** — 구세대 증거 재사용(불변식 위반, 최소 수정+epoch cutover 슬라이스로 이관) |
| S1에서 EXECUTED | 정상 — 신세대 재원실행(유효 S1 레코드 미조달 시) |
| S1의 PR-B mint 레코드(`7f58908b6d59` 계열)로 REUSED | **정상 — 재개(기대치)**: "새 세대에서 1회 원실행 후 재사용이 재개된다"(계약 `:116`) |
| 사용 증거의 세대 판별 불가 | UNKNOWN — 성공 처리 금지(fail-closed) |

**기대 근거(결정론)**: 본 PR의 피험 트리 M^tree = PR-B 착지 후 main(S1 규범 내용, probeTree `1ce1ae01…`의 규범 부분과 동일) + 본 문서(N-class, S 비멤버·테스트 소스/골든 픽스처 비해당) → 9성분 키가 PR-B가 mint한 S1 레코드와 일치 → 5조건(멤버십·payload·executionEpoch·per-read re-hash·rootRecord provenance) 통과 시 REUSED.

## §3. 실패·정직 경로

- 본 PR이 S0 레코드(`7fe9623ad931` 계열)를 재사용하면 이 슬라이스는 결함 보고로 닫힌다 — 수리는 별도 슬라이스(epoch cutover 동반)로 이관하고 성공 선언 없이 상태만 기록한다.
- 예상외 결과는 먼저 불변식 위반 여부를 확인한 후에만 수정을 고려한다(위반 아닌 예상외는 기록으로 남긴다).
- required check 실패·UNKNOWN·관측 불가 시 정지·보고(무한 대기 금지).

## §4. 재현 명령 (GET-only)

- 본 PR 관측: `tools/ci/landing_observe.sh <본 PR 번호>`
- merge_group 런: `gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&per_page=30" --jq '.workflow_runs[] | select(.head_branch | test("^gh-readonly-queue/main/pr-<본 PR>-"))'`
- basis 마커: `gh api --allow-escape-sequences "repos/Archright/Axiom/actions/jobs/<lane_job_id>/logs" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "AXIOM_JUDGMENT_CAS|basis=|no record|go-exec"`
- lane 아티팩트: `gh api repos/Archright/Axiom/actions/runs/<run_id>/artifacts` → `go-judgment-lane-{0,1}-<head>-<attempt>` 내 `judgment-decision*.json`의 `.basis`·`.evidenceKey`·`.probeTreeOid`
- 사이드 ref: `gh api repos/Archright/Axiom/git/ref/heads/axiom/evidence-cas --jq '.object.sha'` (기준 `7a1fd6342`)
