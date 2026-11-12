# S1 — stale-base 오분류 결정론적 재현 (2026-10-12)

- **대상 판정식**: `src/cli/merge_cli.nim:647`
  `result.check.closureEqual = (derivedH == derivedB) and (derivedB == pinBSet)`
- **버그(주장)**: PR 자신은 신뢰 폐쇄를 전혀 바꾸지 않았는데(중립), **기준선이
  PR 분기 이후 밀린 경우**(예: main에 pin 회전 860→864가 선착지, 또는 merge
  queue 선행 PR이 폐쇄 회전) `derivedH != derivedB` 레그 하나만으로
  `closureEqual=false` → ROTATION 주체 → PR 자신의 중립 변경 경로가 ①
  allowlist 밖이라 `rqNone` + `ROT_ALLOWLIST`로 **거부 판정(오분류)**.
  이른바 stale-base 오분류.
- **수정 방향(S2 후속 — 이 문서는 재현만 고정)**: PR의 **자신의 후보 delta**로
  분류 — `closureChange = (derived(M) != derived(B))`, `M = merge(B, H)`.
  중립 PR은 기준선 드리프트와 무관하게 NORMAL. ③(구 앵커, pin@B vs derived(B))
  는 분류보다 먼저 평가되어 기존 S1' 회귀(기준선 pin stale → `ROT_OLD_PIN`)를
  보존해야 한다.
- **브랜치**: `fix/closure-candidate-delta` (S1 재현 단계 — 식 교체 없음)
- **전략**: regression characterization — `tests/cli/test_merge_cli.nim`에
  **현행 식의 관측 결과를 고정**하는 테스트를 추가(CI-green 유지)하고, `S2
  FLIP:` 마커로 식 교체 시 뒤집어야 할 단정을 명시(T2b 선례: 수정과 함께
  반전되는 앵커 테스트).

---

## §1. 재현 구성 (a/b/c 레그)

| 레그 | 구성 | 시나리오 ① (pin 회전 선착지) | 시나리오 ⑥ (큐 선행 PR) |
|---|---|---|---|
| (a) PR 변경 = 폐쇄 멤버 무관(중립) | `changed`가 pin 키·ADR·pin 파일 밖의 주체 파일 | `src/cli/merge_cli.nim`, `docs/spec/productization_contract.md` | `docs/guides/queue.md` |
| (b) 기준선 드리프트: `derivedH != derivedB` | B에만 회전이 반영된 멤버 집합 | B = 860세대 2멤버 + 회전이 편입한 2멤버 / H = 860세대 2멤버 | B = `ci/checker.mk` 내용 a2(선행 회전) / H = a1 |
| (c) `pin@B == derived(B)` (③ 정상) | 선착 회전이 재앵커 완료 | `pinB = some(b)` | `pinB = some(b)` |
| (부가) ④ 정상 | `pin@H == derived(H)` | `pinH = some(h)` | `pinH = some(h)` |

이 입력에서 실패하는 레그는 `(derivedH == derivedB)` 하나뿐이다 — `derivedB ==
pinBSet`은 참(③ 정상). 즉 거부의 원인은 PR이 아니라 **기준선의 이동**이다.

## §2. FAIL 실행 증거 — 현행 식에 수정 후 기대치를 단정 → 실패

재현 프로브: `tmp/s1_stale_base_repro/probe_stale_base.nim` (수정 후 기대치
`rqNormal` + `reasonCode == ""` + `allowlistOk` 를 단정 — 현행 코드에서는
반드시 실패해야 하는 프로브).

```bash
cd .2
nim c --hints:off -r tmp/s1_stale_base_repro/probe_stale_base.nim   # exit 1
```

관측 출력(2026-10-12, 전체 원문은 `tmp/s1_stale_base_repro/fail_output.txt`):

```
[Suite] S1 stale-base repro — POST-FIX expectations (must FAIL on the current formula)
    tmp/s1_stale_base_repro/probe_stale_base.nim(37, 28): Check failed: adj.qualification == rqNormal
    adj.qualification was rqNone
    rqNormal was rqNormal
    tmp/s1_stale_base_repro/probe_stale_base.nim(38, 29): Check failed: adj.reasonCode.len == 0
    adj.reasonCode.len was 13
    tmp/s1_stale_base_repro/probe_stale_base.nim(39, 19): Check failed: adj.check.allowlistOk
  [FAILED] ① neutral PR + base drifted by a landed pin rotation 860→864 → required NORMAL
    tmp/s1_stale_base_repro/probe_stale_base.nim(59, 28): Check failed: adj.qualification == rqNormal
    adj.qualification was rqNone
    rqNormal was rqNormal
    tmp/s1_stale_base_repro/probe_stale_base.nim(60, 29): Check failed: adj.reasonCode.len == 0
    adj.reasonCode.len was 13
  [FAILED] ⑥ neutral follower after a queue predecessor's closure rotation → required NORMAL
Error: execution of an external program failed: ... exit 1
```

`reasonCode.len was 13` = `"ROT_ALLOWLIST"` — 두 시나리오 모두 중립 PR이
ROT_ALLOWLIST 거부로 오분류됨이 기계적으로 관측됐다.

## §3. 현행 식의 관측 판정 (characterization)

관측 프로브: `tmp/s1_stale_base_repro/characterize_stale_base.nim`
(`adjudicateRotation` 결과 필드를 그대로 출력 — 2026-10-12 관측).

| 판정 필드 | ① pin 회전 선착지 | ⑥ 큐 선행 PR | 중립 PR의 올바른 값(S2 후) |
|---|---|---|---|
| `closureEqual` | false | false | (지표 폐지/재정의) |
| `qualification` | `NONE` | `NONE` | `NORMAL` |
| `reasonCode` | `ROT_ALLOWLIST` | `ROT_ALLOWLIST` | (빈 문자열) |
| `allowlistOk` | false | false | true(① vacuous-true) |
| `subjectDeltaZero` | false | false | true |
| `oldAnchorOk` (③) | **true** | **true** | true |
| `newAnchorOk` (④) | **true** | **true** | true |
| `genesis` | false | false | false |

③·④가 모두 참인 상태에서 ①(allowlist)만으로 거부된다 — 거부 사유가 PR 외부
(기준선 드리프트)에서 왔다는 것의 직접 증거다.

## §4. 테스트 고정 (characterization, CI-green)

`tests/cli/test_merge_cli.nim` 신규 스위트:
`"adjudicateRotation — stale-base neutral PR (S1 repro, closure candidate delta) — CURRENT-formula characterization"`

- 테스트 ①: pin 회전 860→864 선착지 + 중립 PR → 현행 `rqNone`/`ROT_ALLOWLIST`
  를 단정(관측 값 그대로). `S2 FLIP:` 주석으로 `rqNormal`·`reasonCode.len ==
  0`·`allowlistOk` 반전 지점 명시.
- 테스트 ⑥: 큐 선행 PR의 승인 회전 + 중립 후속 PR → 동일 관측 값 고정 + 귀속
  불변식(attribution invariance) 명시.
- 실행: `nim c --hints:off -r tests/cli/test_merge_cli.nim` → **[OK] 113건 /
  [FAILED] 0건** (2026-10-12, 신규 2케이스 포함 전부 통과 — 커밋 시 CI 무중단).
- S2 식 교체 시 위 2케이스의 `S2 FLIP:` 단정을 뒤집는 것이 **S2의 완료 조건
  중 하나**다(테스트 이름의 "CURRENT-formula characterization" 제거 포함).

## §5. 회귀 7종 × 커버리지 대비표

| # | 회귀 케이스 | 기존 | 신규(S1) | 후속(S2) |
|---|---|---|---|---|
| ① | stale-base + 중립 PR → **NORMAL** | 없음(버그 상태) | ✅ characterization 2케이스(현행 오분류 고정, FLIP 마커, `:847`) — 본 문서 §4 | `S2 FLIP:` 단정 반전 + 스위트명 갱신 |
| ② | 진짜 폐쇄 변경 + 승인 회전 → ROTATION | ✅ `:667`(단위), `:1137`(pin lag 와이어), `:1165`(제네시스 와이어), `:715`(제네시스 단위) | — | 기존 케이스 유지로 충분 |
| ③ | 변경 + allowlist 밖 → ROT_ALLOWLIST | ✅ `:689`(진짜 변경 + 밖 경로 — 수정 후에도 성립) | — | 기존 케이스 유지 |
| ④ | 기준선 pin stale → ROT_OLD_PIN(③이 분류보다 먼저) | ✅ `:703`(단위), `:768`(S1' 회귀 — pin-only PR, ③가 ④에 선행), `:1108`(T4 와이어) | — | S2가 ③ 선행 평가를 유지하는지 기존 3케이스로 검증됨 |
| ⑤ | 핀·identity·입력 실패 → fail-closed | ✅ 부분: `:942`(부분 공급→err), `:947`(derived 파일 누락→err), `:961`(UNSPECIFIED→DENY), `:1033`(derived 라인 malformed→err), `:1047`(pin 키 부재=genesis), `:1060`(pin 항목 malformed→err) | — | 잔여 브랜치: pin@B 파일 누락/파싱 실패(workspace cwd 의존), listingComplete=false(수집기 레벨), pin@H 파일 누락→④ 실패 — **temp-fixture 테스트 하니스 필요(테스트 파일에 파일 I/O 선례 없음) → 후속** |
| ⑥ | 귀속 비불변(선행 PR 변경 존재, 중립 후속 → NORMAL) | 없음 | ✅ characterization ⑥(①와 동일 입력 형태 — 순수 함수 레벨에서 드리프트 원점은 구별 불가, 서사만 상이) | M-시맨틱 도입 후 ①·⑥ 단정 반전으로 불변식 성립 |
| ⑦ | 후보 트리 불일치 → CANDIDATE_TREE_MISMATCH | 없음(`CANDIDATE_TREE_MISMATCH` 심볼 자체가 src에 미존재 — `candidateTreeDigest` 필드만 존재, `merge_cli.nim:413`) | — | **표에만 남김** — 후보 동등성 검사(derived(M) vs 후보 트리)의 배선이 전제 → S2+ 구현 후 작성 |

※ 줄번호는 2026-10-12 작업 트리 기준(S1 characterization 스위트 삽입 포함).
`git show HEAD:tests/cli/test_merge_cli.nim` 기준으로는 :847 이후 행이 +76행
시프트된다 — 심볼·스위트 명 검색을 권장.

## §6. 재현 명령 (전체)

```bash
cd .2
# 1) 버그 FAIL 증명(현행 식에 수정 후 기대치 단정 → exit 1)
nim c --hints:off -r tmp/s1_stale_base_repro/probe_stale_base.nim
# 2) 현행 식의 관측 판정 덤프
nim c --hints:off -r tmp/s1_stale_base_repro/characterize_stale_base.nim
# 3) characterization 테스트(CI-green 확인)
nim c --hints:off -r tests/cli/test_merge_cli.nim
```

## §7. S2 완료 시 갱신 목록

1. `tests/cli/test_merge_cli.nim` S1 characterization 스위트: `S2 FLIP:` 단정
   반전(①·⑥ 모두), 스위트·테스트명에서 "CURRENT-formula characterization"
   제거, 본 문서 §3 표의 "올바른 값" 열과의 일치 확인.
2. ⑦ CANDIDATE_TREE_MISMATCH 배선 시 회귀 케이스 추가(§5 표 행 해소).
3. 본 문서에 S2 판정식 커밋 해시와 재실행 증거 추가(§2 형식 동일).
