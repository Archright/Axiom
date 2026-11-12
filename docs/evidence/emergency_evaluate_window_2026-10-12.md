# 비상 evaluate 창 감사 기록 — 2026-10-12 (핀 파스 독 사고, PR #794 착지)

> `docs/spec/github_ruleset_api_quirks.md` "비상 창 절차 사용 시 의무(HARD RULE)"에
> 따른 시간제 ruleset 비활성 창의 감사 기록. 복원은 GET 관측으로 검증됨(완료 조건 충족).
> 시각은 전부 UTC. GitHub ruleset history 버전 ID로 교차 검증 완료.

## 사유

- 2026-10-12T09:50:31Z org 호출자(Archright/.github `admission-gate.yml`)의 callee 핀이
  PR #780 세대(blob `e9fbebb2…`, run 본문에 신규 보간 토큰 포함)로 회전된 뒤,
  required workflow가 **0-job 로드 실패**(최초 38237548129, 38239637198 등 전수 재현) —
  check-run 자체가 생성되지 않아 merge queue 필수검사가 구조적으로 불가능해짐.
- 양 ruleset 모두 bypass 미구성(`bypass_actors: []`) → 정상 경로로는 수정+원자 승격
  PR(#794)의 착지가 불가. 유일한 자구 착지 경로로 시간제 evaluate 창을 사용함
  (사용자 전면 허가 하에 수행, §2.5 일관 세대 전환 준수 목적).

## 창 이력 (ruleset history 교차 검증)

| ruleset | id | 전환 | 시각(UTC) | history version_id |
|---|---|---|---|---|
| axiom-admission-gate (org) | 24233738 | active→evaluate | 12:25:33Z | 52836629 |
| main (repo) | 20303214 | active→evaluate | 12:40:44Z | 52838094 |
| axiom-admission-gate (org) | 24233738 | evaluate→active | 12:41:49Z | 52838211 |
| main (repo) | 20303214 | evaluate→active | 12:41:50Z | 52838216 |

- actor: GitHub User id 53123826 (wintrover). 전 전환을 문서화된 PUT(전체 본문)으로
  수행했고 전환 전 스텝샵을 보존(`ruleset_org_backup.json`, `ruleset_main_backup.json`).
- 총 창 길이: org 16분 16초, repo 66초(repo 창은 #794 머지에 필요한 최소 순간만 개방).

## 창 내 착지 (전수 검증: since/until 커밋 조회)

- **정확히 1건**: `18bb145e9` — PR #794 "fix(admission): verdict leg run 본문 신규 보간
  토큰 제거"(워크플로 수정 + `config/trusted_writer_set.json`·`config/policy/epoch_manifest.json`
  원자 승격 + quirk Q4 문서화, 합계 4파일).

## 창 최소화 조치

- 창 개방 전 큐 보호: #788/#791/#793 auto-merge 해제, #787 `dequeuePullRequest`로 큐 제거
  → 창 내 auto-merge 무장 PR은 #794 단독.
- 창 외 ruleset은 미변경(감사: org ruleset history의 10-12 레코드는 위 2건뿐).

## 복원 관측 (완료 조건 — 주장 아닌 관측)

- 2026-10-12T12:41:52Z GET 관측: 24233738 `active`, 20303214 `active`.
- 2026-10-12T23:13:04Z 재관측: 동일(`active`/`active`).
- GitHub ruleset history에 위 4개 전환 레코드 존재 — 감사 추적 일치.

## 사후 정확(정직 기록)

- 창으로 착지한 #794의 승격 blob(`ec54a744…`)은 **여전히 파스 독 상태**였음이 이후
  판명(38251477288, 12:49:31Z 0-job; parse-probe oracle 재확인) — #794 착지는 필요조건이었으나
  충분조건이 아니었다. 최종 복구는 PR #795(`288a410a`, run 본문 보간 토큰 전량 제거)와
  .github 핀 회전(#184 → #188)으로 완성, 게이트 16-job green 회복(유령 push run은
  15:44:35Z 이후 소멸 관측).
- 근본 원인 정체(21,000자 표현식 한도)와 oracle 근거:
  `docs/evidence/admission_parse_poison_oracle_2026-10-13.md`,
  `docs/spec/gh_run_observation_quirks.md` Q4(PR #796).

## 관련 참조

- PR: Axiom #794/#795/#796/#791(acceptance: `qualification: NORMAL`, run 38289641939),
  .github #172/#173/#182/#183/#184/#185/#188
- 런: 38237548129(최초 0-job) · 38249898618(H1 대조, 파스 OK/판정 실패) ·
  38251477288(독 지속 재현) · 38289641939(S5 acceptance)
