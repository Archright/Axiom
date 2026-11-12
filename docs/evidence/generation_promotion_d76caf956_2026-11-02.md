# d76caf956 세대 승격 판정 기록 — 조건부 선언 (게이트 1 종결) 2026-11-02

> **유형**: 판정 기록(공식 상태 전이 — 세대 승격 선언). **정본 규범**: `docs/spec/admission-generation.md` §3.2·§4.1·§4.3·§5.4.
> **판정 매체**: 인간 아키텍트 대화 판정(2026-11-02, §2 원문 인용) → 본 docs-only PR로 canonical main 착지. **선례**: `generation_promotion_hnew_2026-10-17.md`(1파일 구조 준수).
> **관련 증거**: `docs/evidence/landing_history_audit_d76caf956_2026-11-02.md`(21착지 전수 감사) · `data/promotions/d76caf956-landing-audit/`(원본 스냅샷 75·감사로그 105·digest).

## 1. 판정 요지

| 필드 | 값 |
|---|---|
| 결정 | **선언 — d76caf956를 공식 production 실행 세대로 승격 (조건부 수용)** |
| 권한자 | 인간 아키텍트(게이트 1 소유) — 2026-11-02 대화 판정, §2 원문 인용 |
| 대상 SHA | `d76caf956000175bbc78f9b25bced842c02992a5` (Archright/.github main HEAD, PR #251 native merge, 2026-10-31T07:14:27Z) |
| §4.3 해석 | **(a) 문언 그대로** — "컨트롤러 main의 HEAD가 전진하는 모든 착지" 무조건 적용 |
| 일탈 처리 | #248·#250 = **확인된 과거 일탈**로 기록 + 인간 명시적 수용(§2·§5) |
| 기록 시점 상태 | org HEAD == 양 ruleset 핀 == d76caf956 (§6 fresh readback) — 선언창구 개방 상태에서 작성·readback (작성 04:47:00Z; 커밋 시점에는 후속 세대가 이미 착지 — §11 갱신 관측) |

## 2. 판정 원문 (인간 아키텍트, 2026-11-02 대화 — wire.jsonl 보존)

> "1번은 (a), 2번은 조건부 수용 가능으로 판단합니다. 즉, d76caf956의 승격을 더 이상 원천적으로 보류할 필요는 없다고 봅니다."
>
> "일탈을 수용하는 것은 일탈이 없었다고 선언하는 것이 아닙니다. 따라서 공식 승격 기록은 다음 두 주장을 명확히 구분해야 합니다. — 과거 21개 착지가 모두 §4.3을 완벽하게 준수했다는 주장은 하지 않습니다. — #248과 #250의 일탈을 확인하고 공개했으며, 그 잔여 위험을 인간 아키텍트가 명시적으로 수용하여 d76caf956을 승격한다는 판단은 가능합니다."

§4.3 해석 (a) 채택 근거(인간 제시 3종): ① HEAD 전진과 Ruleset SHA 일관성이라는 규범 목적에 부합 ② pinned-file 미변경을 예외 조건으로 두면 규범에 없는 조건 삽입 ③ #250의 기능적 무해성과 §4.3 절차적 의무 위반 여부는 별개.

## 3. 두 주장의 구분 (판정의 의미 경계)

- **본 기록이 하지 않는 주장**: 21개 착지가 모두 §4.3을 완벽하게 준수했다는 주장을 하지 않는다. readback 행위는 explicit 7/21 — 나머지 14는 미입증으로 유지한다.
- **본 기록이 하는 주장**: #248·#250의 일탈을 확인·공개했으며, 그 잔여 위험을 인간 아키텍트가 명시적으로 수용하여 d76caf956을 승격한다.

## 4. 수용 전 확인 5항 결과 (전부 기계 관측, 2026-11-02)

| 확인 항목 (인간 지정) | 결과 |
|---|---|
| 1. §4.3 시행 시점 (#248·#250 시점에 이미 시행 중) | ✓ 2026-10-15 커밋 `3f3d3f86` 도입 — 창(10-16 개시) 전체 시행. #248(10-23)·#250(10-31) 시점 시행본은 현행과 byte-identical — 소급 문제 없음 (audit §3) |
| 2. 스냅샷 diff로 SHA 외 규칙·조건·bypass 보존 | ✓ 창 내 연속 버전 73쌍 diff — 전부 `workflows[].sha`만 변경. enforcement(active)·conditions·bypass_actors(공집합)·rules 구조 불변 (audit §6) |
| 3. 불일치 기간 중 required check·merge authority 무약화·무우회 | ✓ §5 상세 (신규 관측) |
| 4. 두 Ruleset 불일치 해소·현재 정상 | ✓ #249(10-29)·#251(10-31T07:16) 재핀으로 수렴 — 현 양 ruleset sha==d76caf956·active (§6) |
| 5. d76caf956 최종 3-way SHA 일치 유지 | ✓ 4점: blob@Axiom main = blob@f18713934dad = TWS.trustedAdmissionWorkflowSha = epoch_manifest.productionExecutionPin(N+7) = `b9792fc61825...` (§6) |

## 5. 확인 항목 3 상세 — 두 불일치 창의 통제 무결성 (신규 관측)

**창 정의**: 창 A(#248) 2026-10-23T06:12:49Z(bcfc1bbdea 착지)~10-29T09:03:13Z(#249 착지) — 25218071이 #247 핀(7fffee31) 6일 잔존. 창 B(#250) 2026-10-31T02:27:00Z(3fcc2b5c80 착지)~07:14:27Z(#251 착지) — 양측 #249 핀(58a2c546) 4h47m 잔존.

### 5.1 ruleset 통제 상태 — 무변경
- **org 양 ruleset(25218071·23943917)**: 창 A·B 각각 상태 전이 0건. 창 A의 25218071은 10-21T16:21:48Z(핀 7fffee31)→10-29T09:04:40Z(핀 58a2c546) 스냅샷 공백 — enforcement active 포함 상태 완전 정지. 창 B는 #250 재핀 이벤트 전무(audit §5 표).
- **repo ruleset 20303214** (merge_queue + required_status_checks 5종: admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice):
  - 창 A: 이벤트 0건(10-22T06:14:34Z→10-31T03:50:12Z 공백) — 큐·체크·enforcement·bypass 전부 무변경.
  - 창 B: 이벤트 1건(10-31T03:50:12Z). **버전 55634266↔55644535 전체 diff는 `max_entries_to_build` 0↔2 단 한 필드** — required_status_checks·pull_request·enforcement·bypass_actors(공집합)·deletion·non_fast_forward 전부 무변경. 07:17:35Z에 2로 복원. 이것은 정본 §5.2의 **dispatch freeze** — #251 착지(07:14)·양 ruleset 재핀(07:16)을 브래킷하는 보호 조치로서 **약화가 아니라 강화**다.

### 5.2 착지 경로 — direct push 0
- 창 A: Axiom main first-parent 체인 **38착지 전부 2-parent GitHub native merge**(#1075~#1117), 체인 연속(commits API parents[0] 워크), direct push 0. bypass_actors 공집합 → 우회 경로 부재.
- 창 B: 4착지(#1141 02:34·#1142 02:46·#1143 03:12·#1128 03:24) 전부 큐 merge — freeze(03:50) 이전. 일차 혐의 4커밋(98d07067b7·723121372d·20e697a44e·c39fa711bd)은 **PR #1144 브랜치 커밋으로 판명**: 98d07067b7 부모 = 3ae3736a6b(#1143 merge), 체인이 f5eb8c70bc("ci: re-dispatch head checks under new org ruleset pin", 08:14)를 거쳐 #1144 merge(1d94d504d, 08:27 — unfreeze 후 착지)로 귀결 — main 직접 푸시 아님.

### 5.3 required check 실행 실적 (merge_group runs)
- 창 A(10-23~10-29): 632 runs = 587 success + 33 failure + 12 cancelled — 체크가 활성·실행 중. **33 failure는 착지 전 차단(fail-closed 작동)의 증거이지 우회가 아니다**. cancelled 12 = superseded group.
- 창 B(10-31 00:00~08:00): 120 runs 전부 success — 4착지 체크 green.
- 창 B의 후속 착지 #1144 브랜치는 재핀(07:16) 후 "re-dispatch head checks under new org ruleset pin"(f5eb8c70bc)으로 신규 핀에서 체크 재실행 후 착지 — 전환 절차의 정상 작동 관측.

### 5.4 잔여 UNKNOWN (정직 기록 — 인간 수용 대상)
- 창 내 개별 런(752 runs)의 step 수준 로그 전수 재검증은 수행하지 않았다. 대체 증거: (i) GitHub merge_queue ALLGREEN grouping + required_status_checks의 구조적 보강 (ii) 전 착지 큐 merge·direct push 0·bypass 경로 부재 관측 (iii) ruleset 상태 무변경. 이 잔여 위험은 §2 판정으로 인간 아키텍트가 수용한다.
- org repo(.github) 자체의 병합 통제는 본 확인 대상이 아니다 — 양 ruleset의 conditions는 Axiom main에 적용된다.

## 6. 최종 readback (기록 작성 시점 fresh, 2026-11-02)

| 항목 | 관측값 | 재현 명령 |
|---|---|---|
| org .github main HEAD | `d76caf956000175bbc78f9b25bced842c02992a5` (2026-10-31T07:14:27Z, 이후 커밋 0 — 선언창구 개방) | `gh api repos/Archright/.github/commits/main` |
| ruleset 25218071 (axiom-admission-gate) | sha=`d76caf956...` · enforcement active | `gh api orgs/Archright/rulesets/25218071` |
| ruleset 23943917 (landing-integrity) | sha=`d76caf956...` · enforcement active | `gh api orgs/Archright/rulesets/23943917` |
| callee 핀 (admission-gate-v2.yml@d76caf956 :440/:666) | `Axiom/admission-check.yml@f18713934dad...` | `gh api "repos/Archright/.github/contents/.github/workflows/admission-gate-v2.yml?ref=d76caf956..."` |
| 4점 blob 일치 | `b9792fc61825f05f81b43e9dd4db4d36bede0630` — blob@Axiom main = blob@f18713934dad = `trustedAdmissionWorkflowSha`(TWS) = `productionExecutionPin`(epoch_manifest, ciEpochId N+7, mode ci-migration) | `gh api repos/Archright/Axiom/contents/.github/workflows/admission-check.yml?ref=main --jq .sha` + TWS/manifest base64 |

**#251 재핀의 직접 증거(감사로그)**: `repository_ruleset.update` 2건(07:16:28Z·07:16:30Z, actor wintrover) — `ruleset_rules_updated`: 25218071 및 23943917 모두 `old_workflows_sha: 58a2c546... → new_workflows_sha: d76caf956...`. 병합(+2m01s/+2m03s)과의 시계 정합과 독립적으로 행위·전환이 기계 입증된다.

## 7. 감사 결과 요약 (무은폐 — 정본: `landing_history_audit_d76caf956_2026-11-02.md`)

- **21착지**: H_new(29094836, PR #227 merge)→d76caf956 — 44 org 커밋 중 first-parent native merge 21개(2-parent·committer GitHub), direct push 0. 44커밋≠44착지(PR 브랜치 내부 23).
- **재핀 행위 20/21** 감사로그 기계 입증(양측 쌍동 ≤2초) · **#248 단측**(25218071 미재핀 — #249 before-sha 7fffee31→58a2c546가 #248 미진입 입증) · **#250 무재핀**(3fcc2b5c80은 어느 핀에도 부재, 4h47m).
- **상태 매칭**: 양측 19 · 단측 1(#248) · 무 1(#250).
- **readback 행위**: explicit 7(#228·#231·#233·#245·#246·#249·#251) + repin_only 2 + prereg_only 1 + indirect 1 + drift-recorded 1 + absent 9 — 나머지는 미입증으로 유지.
- **rollback 스톰 5회**(10-20, #232 핀으로 후퇴 — #236·#238 SHA 최종 미생존) · 섀도 ruleset 25514358(64분 수명) · 창 시작 ruleset 재생성(24233738→25218071, 1초 차).
- **의미론적 무해(기계 입증)**: 창 A 동안 25218071 핀@7fffee31이 실행한 admission-gate-v2.yml 내용 == bcfc1bbdea 내용(#248 diff에 동 파일 부재) · 창 B 동안 양 pinned 파일 내용 불변(#250 diff = pin-promotion-gate.yml만).

## 8. 선언문 필수 명시 사항

1. **node20 범위 교정**: d76caf956 세대의 node 런타임은 **어드미션 판정 체인 한정** node20 — ruleset 강제 표면에 이미 node24 혼재(landing-integrity checkout v7.0.1 ×3·pin-promotion-gate app-token v3.3.0).
2. **#251 재핀 증거의 성격**: dossier 작성 시점의 한계("감사로그 직접 관측 불가 → +2분 시계 간접")는 착지 이력 감사의 페이지네이션+로컬 필터링(phrase/created 파라미터 무시 quirk 회피)으로 해소됐다 — 재핀 행위·before→after SHA는 §6 감사로그로 직접 입증. 선언은 갱신된 증거 상태를 반영한다.
3. **leg ③ 해석**: §4.3이 요구하는 원자성은 **각 착지(전환)의 트랜잭션 원자성**(native merge + 양 ruleset 재핀 + readback)이지 계보 전체 원자성(중간 커밋 0건)이 아니다 — d76caf956 진입은 단일 native merge(PR #251, callee 핀 회전 76aa3edb→f1871393 동봉) + 양 ruleset 재핀(07:16:28/30) + readback(§6)으로 성립. H_new→d76caf956 간 21착지(44 커밋) 경유는 위 기록대로다.

## 9. 후속

- **node24 세대가 차기 승격 판정 대상** — Stage 3 전환 진행(PR #1189 → org trust-surface PR(Archright/.github) → 게이트 2 인간 수동 병합 → 양 ruleset 순차 재핀 → 양측 GET readback(sha==신규 org HEAD + sha 외 무변경) → merge_group 체크 green). node24 org 착지 시 본 세대의 선언창구는 소멸하나 승격 상태는 본 기록으로 유지된다.
- 본 기록 PR(Axiom repo docs)은 창구를 소모하지 않는다(선례와 동일 구조 — 창구는 org .github 커밋에만 민감).

## 10. 재현 명령 (GET-only)

```bash
# 조건 5 readback
gh api repos/Archright/.github/commits/main --jq '.sha'
gh api orgs/Archright/rulesets/25218071 --jq '[.rules[] | select(.type=="workflows") | .parameters.workflows[] | .sha][0]'
gh api orgs/Archright/rulesets/23943917 --jq '[.rules[] | select(.type=="workflows") | .parameters.workflows[] | .sha][0]'
gh api "repos/Archright/.github/contents/.github/workflows/admission-gate-v2.yml?ref=d76caf956000175bbc78f9b25bced842c02992a5" --jq '.content' | base64 -d | grep -n "admission-check.yml@"
gh api repos/Archright/Axiom/contents/.github/workflows/admission-check.yml?ref=main --jq '.sha'
# 항목 3 통제 무결성
gh api "repos/Archright/Axiom/rulesets/20303214/history/55634266"   # freeze: max_entries_to_build=0
gh api "repos/Archright/Axiom/rulesets/20303214/history/55644535"   # restore: max_entries_to_build=2
gh api "repos/Archright/Axiom/commits?sha=main&since=2026-10-23T06:12:49Z&until=2026-10-29T09:03:13Z&per_page=100"   # first-parent 워크
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-10-23..2026-10-29&per_page=100" --paginate
# 전체 감사 재생산
bash data/promotions/d76caf956-landing-audit/audit_landing_history.sh
```

## 11. 착지 전 관측 갱신 (기계 관측, 2026-11-02T05:35Z — 판정 불변)

판정(§1·§2)과 그 근거(§4–§6)는 변화하지 않는다. 본 절은 본 문서 작성 후·착지 전에 관측된 후속 세대 전환을 은폐 없이 기록한다.

- 본 문서 작성: 2026-11-02T04:47:00Z — 선언창구 개방 상태 (org HEAD == 양 ruleset 핀 == d76caf956, §6 readback과 동일 시점대)
- 후속 세대 착지: 2026-11-02T04:47:56Z — org PR #252 "ci: rotate admission-gate-v2 side-pins to f1871393 (RESID-23 operator re-pin — epoch-promoted)" native merge (parent = d76caf956). diff = `admission-gate-v2.yml` 2라인: `setup-axiom-toolchain`·`runner-pool-acceptance.yml` side-pin `18b180094a…` → `f18713934dad…`
- 양 ruleset 재핀: 2026-11-02T04:49:37-38Z — 25218071·23943917 `workflows[].sha`: d76caf956 → **`0684026f1b929ed9b9c3884be4da3dc89aa2bdc6`** (착지 후 101초 — §4.3 준수 전환)
- 본 기록 커밋: 2026-11-02T04:49:51Z (c71734508) — 재핀 14초 후. §1 "기록 시점 상태"는 작성·readback 시점 기준이며, 커밋 시점의 운영 세대는 이미 0684026f였다.
- 영향 판정: d76caf956 승격 판정의 유효성에 영향 없음 — 판정 입력(조건 5의 4점 일치 포함)은 전부 04:47:56Z 이전 관측이다. 0684026f는 d76caf956을 parent로 하는 정상 §4.3 전환이며 차기 승격 판정 대상이다 (§9의 node24 예상과 별개로 중간 세대가 존재하게 됨).
- 착지 후 readback 기대치 갱신: 본 기록 PR(docs-only) 착지는 창구·핀에 영향을 주지 않으므로, 착지 후 양 ruleset·org HEAD는 **0684026f로 불별**이어야 한다 (PR 본문 Completion Evidence의 d76caf956 기대치는 본 절로 대체).
