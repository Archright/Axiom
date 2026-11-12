# WP4-f Phase A — Generic Type Semantic Boundary: localization (코드 수정 없음)

EXPERIMENT_ID: act2-wp4f-generic-type-boundary (Phase A — localization only)
PARENT: act2-wp4d-symbol-identity / WP4-e complete
SUBJECT: nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859
ANCHOR: `stew/bitops2.nim::getBitsBE` (generic param `T: type[SomeUnsignedInt]`)
STATUS: Phase A 완료 — 코드 수정 없음. 두 개의 독립 blocker 확정.

## Question

`getBitsBE`(generic param `T: type[SomeUnsignedInt]`)가 A4 planning에서 `illFormed`로
스킵되는 정확한 이유는 무엇인가?

특히 사용자 WP4-f 프레임의 셋 중 어느 Case인가:

- Case A — AST→Canon→IR 사이에서 generic type 정보 손실
- Case B — IR에는 존재하나 SMT lowering에서 표현 불가
- Case C — 표현은 되나 proof capability 부족

측정 결과: **셋 중 어느 하나로 깔끔하게 단정할 수 없다. 두 개의 독립 blocker가 있고,
현재 illFormed를 일으키는 직접 원인은 generic type이 아니라 postcondition vacuous 이다.**

---

## 측정 경로 (각 hop을 file:line으로 확인)

```
getBitsBE Nim source
  └─ func getBitsBE*(data: openArray[byte], slice: HSlice, T: type[SomeUnsignedInt]): T
     (nim-stew@c75502c stew/bitops2.nim:559)
        ↓
convertFuncDefCanon (ast_to_ir.nim:1199)
  └─ generic param 섹션 n.children[2] 를 읽지 않음
     → children[3](formalParams) + children[6](body)만 처리 (line 1215-1244)
        ↓
convertTypeCanon (ast_to_ir.nim:43)
  └─ ckIdent "SomeUnsignedInt" / "T" → else 브랜치 line 56-57 → irtBitVec64() (고정 64비트)
        ↓
IRFuncDef
  └─ postConditions = []  (값 없음)
        ↓
synthesizeContracts (contract_synthesis.nim:306-313)
  └─ pre: division/index/assert guards; post가 비면 collectPostconditions 호출
        ↓
collectPostconditions (contract_synthesis.nim:208-267)
  └─ retType=irtBitVec64 → clamp 패턴일 때만 post조건 생성
  └─ getBitsBE 본문은 bit-shift/조건부 표현 (clamp 아님) → 빈 배열 반환
        ↓
irToSmtScript (ir_to_smt_chunk3.nim:131)
  └─ f.postConditions.len == 0 → return "" (line 257-258)  ← EMPTY SMT
        ↓
TheaterGuard (ir_pipeline_runner.nim:939)
  └─ ogr.kind == ogrGenerated && smtScript.len == 0 → illFormed ("theater_detected")
        ↓
IR pipeline skip: getBitsBE status=psSkip provenance=not_verifiable:illFormed,solverMethod=smNone
```

---

## 발견 1 — generic type 정보 손실 (Case A 성격, 잠재적 의미 파괴 위험)

**근거:**
- `convertFuncDefCanon` (ast_to_ir.nim:1199)은 generic param 섹션 `n.children[2]`를
  **읽지 않는다.** children[4] 미만 또는 formalParams(children[3])만 다루고,
  본문(children[6])만 변환한다. 결과적으로 `T: type[SomeUnsignedInt]` 선언은
  IRFuncDef에 존재하지 않는다.
- `SomeUnsignedInt` / `T` 가 본문에서 타입으로 참조될 때 `convertTypeCanon`
  (ast_to_ir.nim:43)의 `else` 브랜치 (line 56-57)로 흘러 **`irtBitVec64()`**
  (고정 64비트) 로 매핑된다. "임의 unsigned 폭"이라는 generic 의미가 64비트로 고정된다.

**의미:** `SomeUnsignedInt`는 `uint8..uint64` 어떤 인스턴스화든 캡처하는 제네릭 타입인데,
64비트로 고정되면 `uint8`/`uint16`/`uint32` 의미와 충돌한다. 이것은 사용자가 금지한
"대충 concrete integer로 치환"의 정확한 함정이다. 현재 illFormed 경로에서는 이 64비트
고정이 결과에 영향을 주지 않지만, postcondition/obligation이 SMT로 흘러갈 때 정보 손실이
표면화된다.

---

## 발견 2 — illFormed의 직접 trigger는 postcondition vacuous (일반 문제)

**근거 (실측 로그 wp4d4-ladder-getbitsbe.log):**
- line 52: `cross-validation skipped (vacuous — no postconditions)`
- line 20: `[TheaterGuard] getBitsBE — obligation generated but adapter produced empty SMT script`
- line 26/40: `status=psSkip provenance=not_verifiable:illFormed,solverMethod=smNone`

**코드 근거:**
- `synthesizeContracts` (contract_synthesis.nim:306-313): pre에 division/index/assert
  guard를 추가, post가 비면 `collectPostconditions` 호출.
- `collectPostconditions` (contract_synthesis.nim:230-254): `irtBitVec64` 반환 시
  body가 clamp/witlower/upper 패턴일 때만 post를 생성. `getBitsBE`는 bit-shift 표현이라
  **빈 배열** 반환.
- `irToSmtScript` (ir_to_smt_chunk3.nim:257-258): `f.postConditions.len == 0` → `return ""`.
- TheaterGuard: obligation은 생성됐는데(`ogrGenerated`) SMT가 비어서 → illFormed.

**의미:** 이것은 generic type과 무관하다. postcondition이 없는 어떤 함수라도 동일하게
vacuous로 끝난다. `getBitsBE`가 현재 illFormed가 되는 **직접 원인은 이것** 이다.

---

## Case 판정

| Case | 해당 여부 | 근거 |
|------|-----------|------|
| Case A (generic IR 손실) | **예 — 존재함, 그러나 현재 illFormed의 원인은 아님** | ast_to_ir.nim:1199(children[2] 미처리), ast_to_ir.nim:56-57(→irtBitVec64) |
| Case B (SMT lowering 표현 불가) | 아님 | SMT에 도달하기 전에 postcondition vacuous로 early-return (ir_to_smt_chunk3.nim:257) |
| Case C (capability 부족) | 아님 (현재 판정에서) | 유효한 SMT가 생성되기 전에 vacuous로 종료 |

**결론:** 현재 `illFormed`는 Case A/B/C 어디에도 정확히 속하지 않는다. 그것은 제4의
별개 문제 — **"postcondition이 없는 함수의 vacuous SMT 처리"** 이다.

---

## 다음 WP 제안

WP4-f는 "generic type boundary" 하나로 묶으면 안 된다. 두 blocker를 분리해야 한다.

### Blocker A (Case A) — generic type 정보 손실
`convertTypeCanon`이 `SomeUnsignedInt`를 `irtBitVec64`로 고정 매핑하고,
`convertFuncDefCanon`이 generic param children[2]를 무시한다.
→ Generic type의 semantic representation을 보존하는 모델 필요 (symbolic width 등).
**이건 큰 변경이므로 별도 WP.**

### Blocker B — postcondition vacuous → empty SMT (현재 illFormed 직접 원인)
postcondition이 없는 함수가 `ogrGenerated`인데 SMT 빈 채로 illFormed가 되는 것.
**이게 지금 getBitsBE를 막는 실제 blocker.**
→ 이건 generic type과 무관한 일반 문제.

### 최소 수정 원칙
generic type을 `uint32`/`uint64`로 치환하는 우회는 금지 (발견 1이 그 함정을 확인).
postcondition 문제와 generic type 문제를 섞지 말 것.

---

## Non-Claim

- 이 WP는 어떤 코드도 수정하지 않았다 (Phase A localization only).
- 실측으로 확정한 것은 로그 + 위 file:line 경로뿐. 다른 경로(예: fake 증명)는 없다.
- Case 판정은 "현재 코드+현재 실행 경로" 기준이며, 코드가 바뀌면 재판정 필요.

## Evidence

- `experiments/act2-wp4d-symbol-identity/wp4d4-ladder-getbitsbe.log` (line 20, 26, 52)
- `src/core/trusted/ast_to_ir.nim:1199` (convertFuncDefCanon — generic param 무시)
- `src/core/trusted/ast_to_ir.nim:43,56-57` (convertTypeCanon → irtBitVec64)
- `src/core/trusted/contract_synthesis.nim:208,230-254,306-313` (postconditions 빈)
- `src/core/trusted/private/ir_to_smt_chunk3.nim:257-258` (postConditions.len==0 → "")
- `src/verification/batch_uap/ir_pipeline_runner.nim:939` (TheaterGuard)
