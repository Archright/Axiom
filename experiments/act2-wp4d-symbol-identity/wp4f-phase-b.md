# WP4-f Phase B — Blocker B 재평가: TheaterGuard illFormed는 의도된·테스트된 동작이다

EXPERIMENT_ID: act2-wp4f-b-blocker-b
PARENT: act2-wp4f-phase-a (localization 완료)
SUBJECT: nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859
ANCHOR (Phase A): `stew/bitops2.nim::getBitsBE` (generic param `T: type[SomeUnsignedInt]`)
STATUS: Phase B — 코드 수정 없음. 사용자가 선택한 "Blocker B 수정" 전제를 검증한 결과,
**Blocker B는 defect가 아니라 의도된 anti-theater invariant 동작임이 확정됨.**

---

## Question

Phase A 발견 2에서 확정한 "postcondition 없는 함수가 `ogrGenerated`인데 SMT 빈 채로
illFormed가 되는" Blocker B를 어떻게 수정할 것인가?

사용자가 "B"를 선택했으나, Phase B에서 이 전제 자체를 검증해야 한다:
**이 illFormed는 수정해야 할 결함인가, 아니면 보호해야 할 의도된 불변식인가?**

답: **전자(결함)가 아니라 후자(의도된·테스트된 anti-theater 불변식)다.**

---

## 실측 근거 1 — TheaterGuard 동작은 유닛테스트로 명시적으로 고정되어 있다

`tests/unit/test_ir_pipeline_theaterguard.nim` **test (d)** (line 99-121)이
정확히 getBitsBE와 동일한 구조(obligation 생성 + postcondition 없음 → 빈 SMT → illFormed)를
**의도된 동작으로 단언**한다.

```nim
test "(d) TheaterGuard fires for obligations-without-postconditions and preserves the count":
  # x / y has NO postcondition (division-only, no clamp pattern) — irToSmtScript
  # emits an empty script even though obligations WERE generated (division
  # safety + synthesized division guard). The TheaterGuard fails closed
  # (rkObligationIllFormed) and — per DEBT#423 — must record the generated
  # obligation count instead of bypassing it with 0.
  ...
  check result.verification.reason == rkObligationIllFormed
  check result.obligationVerdict.kind == ogrIllFormed
  check result.obligationVerdict.reason == "theater_detected"
  check result.obligationVerdict.obligationCount == expected   # count preserved
```

실행 결과: 6/6 `[OK]` (본 Phase B에서 재실행 확인).

## 실측 근거 2 — getBitsBE는 TheaterGuard 경로로 illFormed가 된다

`wp4d4-ladder-getbitsbe.log` line 20:
```
[WARN] ir_pipeline_runner: [TheaterGuard] getBitsBE — obligation generated but adapter produced empty SMT script
```
이후 line 26/40: `status=psSkip provenance=not_verifiable:illFormed`.

## 실측 근거 3 — getBitsBE는 postcondition이 전혀 없는 함수다

소스 `stew/bitops2.nim:559-610`:
- `doAssert a < b and sliceLen <= resultBits and b <= totalBits` — **precondition** (assumption)
- 본문은 bit-shift/조건부 표현 — `collectPostconditions`가 인식하는 clamp 패턴이 **아님**
- 그래서 `postConditions = []`

`irToSmtScript` (ir_to_smt_chunk3.nim:240-258):
- Step 3: preconditions를 **assumption**으로 assert
- Step 5: `f.postConditions.len == 0 → return ""` (검증할 goal이 없음)

즉 getBitsBE는 **검증할 postcondition goal이 없는 함수**다.

---

## 결론 — Blocker B 수정은 "하지 않는다"

### 핵심 판정

아래 세 수정 방향은 전부 **거부**한다.

| 방향 | 내용 | 거부 사유 |
|------|------|-----------|
| (A) 안전 postcondition 자동합성 | getBitsBE에 `result >= ...` 같은 post를 짜낸다 | 본문이 clamp가 아니므로 **anti-theater 위반** (contract_synthesis.nim:255-260 "never fabricate a constraint"). AGENTS.md §3 금지. |
| (C) post-only ogrGenerated | postcondition이 없으면 ogrGenerated를 내지 않는다 | okContractPre(precondition)는 verified-fragment allowlist(verified_fragment.nim:45)의 정당한 obligation kind. 의미 변경의 blast radius가 self-repo zero-drift까지 크다. |
| TheaterGuard 약화 | `ogrGenerated + 빈 SMT`에서 illFormed 대신 성공/건너뜀으로 | test (d)가 정확히 이 동작을 고정. 보호된 Act 1 anti-theater invariant. AGENTS.md §3 "convert failure→success 금지". |

**TheaterGuard의 fail-closed illFormed는 옳다.** "obligation이 생성됐는데 검증할
goal(postcondition)이 없어 빈 SMT"라는 상태를 숨기지 않고 명시적으로 낙인한다. 이는
`DEBT#423`이 기록한 의도적 방어다.

### 진짜 교훈 — anchor 선정

getBitsBE는 **증명 anchor로 적합하지 않은 함수**였다:
- postcondition이 없음 → 검증할 goal 없음
- generic (`T: type[SomeUnsignedInt]`) → Phase A 발견 1의 의미 파괴 위험
- `func` + `template` 이중 정의 → WP4-d duplicate identity 문제

**Blocker B의 정당한 해소는 코드 수정이 아니라 anchor 재선택이다.** 검증할 실제
postcondition goal을 가진 함수를 골라야 A4를 통과한다. (Phase B와 병행해 실행한
anchor 후보 탐색 결과는 하단 "Next" 참조.)

---

## Classification

- A4에서 getBitsBE: `psSkip / not_verifiable:illFormed` — **올바른 fail-closed verdict**
- Blocker B "수정": 실행하지 않음 (의도된 동작 보존)
- 결과 taxonomy: `Unsupported/Incomplete` 가 아니라 `CorrectlyNonVerifiable(noPostconditionGoal)`
  — 즉 "검증할 postcondition이 없는 함수"라는 정직한 분류.

## Non-Claims

- 이 WP는 어떤 코드도 수정/추가하지 않았다.
- TheaterGuard나 `irToSmtScript`, obligation generator를 건드리지 않았다.
- getBitsBE가 "Verified"가 되도록 강제하지 않았다 (그것은 우리 목표가 아니다).
- 이 판정은 "현재 코드 + 현재 실행 경로" 기준이다. postcondition 합성이 clamp 이외
  패턴으로 확장되면 재판정이 필요하다.

## Evidence

- `tests/unit/test_ir_pipeline_theaterguard.nim:99-121` (test d — 의도된 동작 고정, 6/6 PASS)
- `experiments/act2-wp4d-symbol-identity/wp4d4-ladder-getbitsbe.log:20,26,40`
- `src/core/trusted/private/ir_to_smt_chunk3.nim:240-258` (pre=assumption, post=goal, 빈 post → "")
- `src/core/trusted/contract_synthesis.nim:255-260` (anti-theater — constraint 짜내기 금지)
- `src/core/trusted/contract_synthesis.nim:306-313` (synthesizeContracts — pre/post 배치)
- `src/verification/batch_uap/ir_pipeline_runner.nim:939` (TheaterGuard)
- `src/verification/obligation/verified_fragment.nim:45` (okContractPre allowlist)

## Next

WP4-f Blocker B는 "코드 수정 없이" 닫는다. 다음 WP는 **postcondition goal을 가진 외부
함수를 anchor로 선정**하고 그 함수로 8-stage(A1–A8)를 다시 실행하는 것이다.
(getBitsBE는 negative/control anchor로 유지한다.)
