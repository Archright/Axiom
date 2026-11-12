# MG eligible-REUSED 컷오버 기록 + E2E 검증 차량 (2026-10-18)

> **종류**: 실행 증거 (cutover record). **대상**: 재결 `docs/evidence/mg_reuse_policy_redecision_2026-10-18.md`(PR #918)의 이행 — 구현 PR #920(`90d517d2`, MERGED 08:54:43Z) + 컨트롤러 핀 회전 #230(→`90d517d2`) + §4.3 양 ruleset 재핀(25218071/23943917 → 컨트롤러 `758a8769`, freeze 2→0→2 정상 복귀).
> **E2E 목적**: 본 문서 자체가 **docs-only PR**로서, 착지 시 merge_group 런에서 `Judgment CAS: REUSED`(rootRecord 마커 동반) 발화와 MG wall의 401–550s 회귀를 관측하는 검증 차량이다. 판정 입력(9성분)은 docs/evidence 델타로 불변이어야 하며, 마커 부재·불일치 시 기존 EXECUTED 경로로 fail-closed되는 것이 기대 동작이다.
> **권위**: Reporter. 병합 판정 권위는 GitHub(ruleset·큐·MERGE 커밋)다.

## 컷오버 사실
- 구현: PR #920 MERGED — 벨트(:1468-1475)→venue 마커, early-return(:1559-1562) 제거→기존 fail-closed 사슬 통과, landingVenue+rootRecord 마커(:1450-1460/:1728-1748/:1910-1934), attest basis 수용 규칙(yml :1718-1730), G11 재작성+G12 7케이스.
- 핀: `338c54150b0e → 90d517d25a68` (컨트롤러 PR #230, 09:02:56Z) → 양 ruleset `758a8769…`.
- 첫 신세대 코드 랜딩(#919): wall 707s·success·EXECUTED(신선) — 마커 규칙 이전의 정상 경로 확인.

## E2E 기대/판정 (본 PR의 MG 런에서)
| 항목 | 기대 | 판정 명령 |
|---|---|---|
| REUSED 발화 | lane 로그 `Judgment CAS[...]: REUSED` + decision basis=REUSED + rootRecord 마커 | `gh api .../jobs/<lane>/logs \| grep "REUSED"` |
| fail-closed 경로 | 마커 불일치 시 EXECUTED (본 PR은 불변 기대) | decision file jq |
| MG wall | ~401–550s (기존 550–737 대비 회귀) | run duration |
| 판정/증거 동등 | verdict green·canonical projection 동일(재사용 leg byte-identical) | verdict log |
| 착지 | 정상 큐 경유 MERGED | landing_observe |

---

## Addendum — #922 음성 관측 + p2 준수 세대 전환 (2026-10-18, PR #924 이행 후)

> **권위**: Reporter. 병합 판정 권위는 GitHub(ruleset·큐·MERGE 커밋)다.

### 음성 관측 (#922 — 본 문서 원판의 E2E 차량 실행 결과)

본 문서 원판 자체가 E2E 차량이었다(#922, docs-only). 그러나 #922의 착지에서
`Judgment CAS: REUSED`는 **발화하지 않았다** — v3 클로저 wire가 운반하던
narrowing-only 멤버 `verifierIdentity` = H(B^{tree}, recipe, pins)가 매 랜딩마다
B^{tree} 전진(직전 머지 결과)을 키에 반영해, docs-only 델타(S 불변)에서도 키가
전진했기 때문이다. 계약 §4.1 p2 위반의 생산 실측 — "401–550s 회귀" 기대는
이 구조적 결함이 닫히기 전에는 관측 불가능했다.

### 수정 세대 (PR #924 — MERGED f8eb54f3ec13, 2026-10-18T13:25:24Z)

- **구현 순응**: 계약 v1.0.4(§9) — 스킴 `v3→v4`, `verifierIdentity` 멤버 완전
  제거(wire = 고정 10멤버, 트리 OID 어디에도 없음 — G12 회귀 핀), 양 collector의
  B^{tree} 측정 블록 제거, `AXIOM_JUDGMENT_CAS_BASE_TREE_OID` 소비 제거(TESTED
  probe 앵커 유지). **evidence 측 verifierIdentity B^{tree} 결속은 불변.**
- **핀 회전(A2 원자 쌍)**: `trustedCheckerTreeClosure` 재앵커(derive_checker_closure
  유도 — 정확히 1멤버, 876==876, pin@H==derived(H)) + `trustedAdmissionWorkflowSha`
  ·`productionExecutionPin` → `09e8db1dea28` (신세대 admission-check.yml blob).
- **컷오버 체인**: 컨트롤러 PR #231 MERGED(`67e1aa9de7`, 13:29:41Z — 양 호출 지점
  :430+:655) → §4.3 양 ruleset 재핀(25218071·23943917 sha `758a8769`→`67e1aa9de7`,
  ref 제거, readback byte-consistency PASS — rules/conditions/bypass 무변경,
  freeze 2→0→2 정상 복귀).
- **고아화**: 스킴 v4는 구 v3 레코드와 절대 충돌하지 않는다(계약 §9). **첫 v4
  세대 착지 1회는 EXECUTED**(v4 레코드 mint)가 예상 전이고, 이후 동일 클로저
  (docs-only) 착지부터 `basis=REUSED` 재개다 — same-key reuse는 byte-identical
  canonical projection을 반환한다(J1 실측: 이형 프로세스 2회 독립 flush 투영
  cross-run byte-identical, `a4db29d6…`; 음성 변조 exit 2).

### 본 addendum PR의 E2E 판정 (v4 첫 세대)

| 항목 | 기대 | 판정 명령 |
|---|---|---|
| 첫 v4 착지(본 PR) | lane 로그 `no record for the current closure` 포함 + `Judgment CAS[...]: EXECUTED` — v4 레코드 mint | lane 로그 grep |
| 후속 docs-only 착지 | `basis=REUSED` + `no record for the current closure` **부재** + MG wall 회귀 | lane 로그 grep + run duration |
| fail-closed | 미달 시 EXECUTED(원 실행) — REUSED는 절대 자칭하지 않음 | plan reason |
| 착지 | 정상 큐 경유 MERGED | landing observe |

판정 결과는 착지 후 본 문서 후속 addendum에 기록한다(실행 증거 — run id·wall 원문).

---

## Addendum 2 — v4 첫 세대 착지 관측 (판정 기록)

### 첫 v4 착지 (#925 — 본 문서 원 addendum 자체, MERGED `8bddab8be`, 2026-10-18T13:52:57Z)

**예상 전이 그대로 — 첫 v4 착지 1회 EXECUTED(계약 §9 고아화)**:

| 항목 | 관측값 |
|---|---|
| MG 게이트 런 | `39132586441` (admission-gate, success — 13:40:35Z → 13:52:32Z, **wall 717s**) |
| 큐 그룹 | `gh-readonly-queue/main/pr-925-f8eb54f3…` (정상 큐 경유 MERGED) |
| s1a lane(0) | `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` → `PASS — tests/unit/test_s1a_lean_golden.nim (basis=EXECUTED — fresh judgment measured)` |
| lane(1) | `AXIOM_JUDGMENT_CAS [proof_integrity] : EXECUTED — no record…` · `[d2_golden] : EXECUTED — no record…` · `[d2_persist] : EXECUTED — no record…` → 3주체 전부 `basis=EXECUTED — fresh judgment measured` PASS |
| 해석 | v4 클로저 키가 원장에 부재(고아화 예상) → 4주체 원 실행·v4 레코드 mint — `no record for the current closure`는 fail-closed 사슬의 정상 발화다 |

이 벽(717s)은 레인이 4주체 전부를 실측한 첫 세대 벽이다 — REUSED 세대 벽의 대조
기준점. (참고: #924 본체의 MG 런 39130593997은 B가 구세대 코드라 v3 동작으로
실행됐다 — 정상 부트스트랩.)

### 후속 docs-only 착지 판정 (REUSED 재개 — 본 addendum 자체가 차량)

본 addendum PR의 MG 런에서 관측 대상: `AXIOM_JUDGMENT_CAS...: REUSED`(rootRecord
마커 동반) + `no record for the current closure` **부재** + 레인 4주체 SKIP(
`basis=REUSED — record re-verified, no kernel run this attempt`) + MG wall 회귀.
판정 결과는 본 문서 다음 addendum에 run id·wall 원문으로 기록된다.

---

## Addendum 3 — REUSED 재개 판정 (확정)

**첫 REUSED-확정 착지: PR #926 (MERGED `9ae1f77a6c`, 2026-10-18T14:09:55Z)**

| 항목 | 관측값 |
|---|---|
| MG 게이트 런 | **`39134186961`** (admission-gate, success — 14:02:16Z → 14:09:33Z, **wall 437s**) |
| s1a lane(0) | `AXIOM_JUDGMENT_CAS: REUSED — record eba3e79cea75 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` → `SKIP — tests/unit/test_s1a_lean_golden.nim (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)` |
| lane(1) | `[proof_integrity] : REUSED — record 60a4ee8d4948` · `[d2_golden] : REUSED — record 0fd9965ca24d` · `[d2_persist] : REUSED — record 1487289bf7b2` — 4주체 전부 SKIP (basis=REUSED) |
| `no record for the current closure` | **양 레인 0건** (첫 세대 4건 대비) |
| venue | merge_group(착지 장소, `AXIOM_JUDGMENT_CAS_FORCE_EXECUTED: 1` = 마커)에서 REUSED 발화 — 재결(2026-10-18)의 eligible-REUSED-on-MG가 v4 세대에서 동작 |
| wall 회귀 | **717s → 437s (−280s, −39.0%)** — s1a(~5m)+3주체 원 실행 건너뜀의 실측 효과 |

**판정: p2 준수 세대(v4)의 REUSED 재개 확정** — 스킴 고아화(§9) → 첫 세대 1회
EXECUTED(#925) → 동일 클로저 docs-only 착지 REUSED(#926)의 예상 전이가 전부
관측됐다. #922의 음성 실측(매 랜딩 키 전진으로 REUSED 불가)은 v3 wire의
`verifierIdentity` 제거로 닫혔다.



