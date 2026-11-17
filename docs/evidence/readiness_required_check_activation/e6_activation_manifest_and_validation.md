# E6 — activation manifest·기계 관계 검증·§7.3 정정·ruleset 이력·큐 양성 관측

> DEBT#537 청산 증거 체인의 E6. 활성화 기록의 정본 착지, 검증기의 정직한 실패,
> 위임 기록의 보수적 오기록 정정, ruleset 버전 이력 감사, 그리고 스테디 상태
> 큐 양성 관측의 지정을 기록한다. 원본: `data/promotions/readiness-verdict-activation/manifest.json`,
> `raw/ruleset_history_post_rotation.json`.

## §1. activation manifest 착지

- `data/promotions/readiness-verdict-activation/manifest.json` — axiom.promotion-manifest.v1
  형상(선례 `axiom-operational-slice-activation`)에 검증기 관계필드
  (`schemaVersion/repository/promotionId/candidateSha/candidatePr/mergeSha/acceptanceRun/rulesetReadback/productionRun`)를
  병행 수록. rotation 착지·사전 PUT 일탈·프로브 3종·제3자 재현 결과·readback를 모두 기록.

## §2. 검증기 관계 판정 (2026-11-16T17:27Z, 원문)

```
$ GPA_WORKFLOW=axiom-operational-slice bash tools/promotion/validate_manifest.sh \
    data/promotions/readiness-verdict-activation/manifest.json
VALIDATE_MANIFEST: data/promotions/readiness-verdict-activation/manifest.json (repo=Archright/Axiom, workflow=axiom-operational-slice)
  schema — OK
  (1) acceptanceRun.event — 기대 'merge_group', 실제 'pull_request'
  (2) candidateSha — OK (PR 121 head = 8170dac…)
  (3) rulesetReadback — OK (provenance=operator-promotion-adapter, fetchedAt=2026-11-16T17:27:18Z, expected==actual)
  (4) productionRun — OK (run 43911956696 head_sha = mergeSha = e3ec8ae…)
  (5) mergeSha — OK (PR 121 mergeCommit = e3ec8ae…)
VALIDATE_MANIFEST: FAIL — 관계 검증 실패 …
```

**해석**: rel_1(merge_group acceptance run)은 rotation 착지에서 **구조적으로 불충족**이다
(정책 미러 동반 단일 PR은 어떤 순서로도 큐 자격 불가 — GPA 실측 §4 참조, VS-I/PR #45
범주). 실패는 정직하게 기록되며 조용한 통과 선언은 하지 않는다(AGENTS.md §0.9;
VS-I 선례는 manifest 없이 문서 대체 — 본 활성화는 관계 4항이 기계 검증되는
manifest + 실패 1항의 명시 기록을 택했다). rel_2/3/4/5는 전부 API 실측 일치.

## §3. §7.3 정정 (위임 기록 서술 vs UTC 사실)

- **위임 기록**(`must_t2a_rotation_landing.md` §2.1): "§7.3 '드리프트 창은 PUT과 같은
  UTC 일 내 폐쇄'도 이미 위반된 상태다 (2026-11-16 PUT → 2026-11-17 착지)" — **KST
  날짜 대조에 근거한 보수적 오기록**(병합 전 시점 기록이라 착지 시각을 미래로
  추정해 기록함).
- **UTC 사실(실측)**: 사전 PUT 2026-11-16T14:19:58Z(58006001) → 정책 미러 착지
  16:50:39Z → 복원 PUT 16:50:55Z(58030755) — **전부 같은 UTC 일(2026-11-16)**.
  스펙 §7.3("같은 UTC 일 내 폐쇄")은 **실충족**이다. 위임 기록 원문은 병합 전
  커밋된 시점 기록으로서 불변 보존하고, 본 문서가 정정 기록이다.

## §4. ruleset 버전 이력 감사 (raw/ruleset_history_post_rotation.json)

| version | 시각(원문 tz) | UTC | 내용 |
|---|---|---|---|
| 58006001 | 2026-11-16T23:19:58+09:00 | 14:19:58Z | 사전 PUT — readiness-verdict 7번째 required context 추가(**순서 역전 일탈**, fail-closed 창 2h31m, 창 중 병합 0건) |
| 58030608 | 2026-11-17T01:50:14+09:00 | 16:50:14Z | rotation용 일시 bypass 등록 |
| 58030755 | 2026-11-17T01:50:56+09:00 | 16:50:55Z | bypass 제거·복원(RESTORE_IDENTICAL) |

GPA 일시 red(run 43882659122 `REJECTED:RULESET_UNAVAILABLE`)은 §사전 PUT 창의
예측된 관측이며(위임 기록 §2.1에 사전 기록), 착지 후 7==7 스테디 상태로 해소.

## §5. 스테디 상태 큐 양성 관측 (지정)

본 증거 착지 PR이 activation 이후 **첫 큐 통과 후보**다: 정책 미러를 변경하지 않는
PR은 큐 자격을 가지며, 큐 진입 시 merge_group run에서 readiness-verdict가 실행되어
CONDITIONAL GO(exit 0)로 통과하고 native MERGE로 착지해야 한다. 착지 후 해당
merge_group run id·conclusion은 PR 대화에 관측 기록으로 남긴다(이 문서의 후속
관측 지점 — PR-3 착지가 그 자체로 양성 대조다).
