# Lean 발행 bare-numeral 토큰화 결함 수정 + `<string>(54,3)` 귀속 교정 — 실행 증거 (2026-10-08)

브랜치: `fix/lean-emit-indentation` (origin/main = 83bc2c995 기준 worktree 토픽 브랜치)
범위: (1) `src/core/trusted/ir_to_lean.nim` 비교 피연산자 발행을 단일 규칙 `(op : BitVec 64).toInt`로 결정론화, (2) `tools/ci/add_raises_annotations.nim` 빈 multiline 테이블 생성자 파스 오류 제거(심볼 그래프 `<string>(54,3)` 노이즈의 실제 원인), (3) 회귀 테스트 2건, (4) quirk 문서, (5) DEBT#465 attribution addendum.

## 1. 결함 1 — `<string>(54,3) Error: invalid indentation`의 귀속 교정

2026-10-07 증거(`docs/evidence/debt465_c20_borem_slice_2026-10-07.md` §2)가 이 오류를 Lean 커널 진단으로 기록했으나, 실제로는 **Nim 파서 오류**다:

- `src/core/parser_utils.nim`의 `parseStringAST`가 fakePath `<string>`으로 `tools/ci/add_raises_annotations.nim`(tracked, 221줄)을 파싱하며 실패.
- 원인 구문: `PostProcess = {` + 개행 + `  }.toTable` (빈 multiline 테이블 생성자).
- 독립 재현(수정 전, nim 2.2.10): `nim check --path:. --path:src --path:tools --skipParentCfg --skipProjCfg tools/ci/add_raises_annotations.nim` → `tools/ci/add_raises_annotations.nim(53, 3) Error: invalid indentation`.
- 라이브 재측정: `bin/ax prove --target normalizeMaxWorkers` 전체 출력에서 `invalid indentation` 발생 횟수 **수정 전 1건 → 수정 후 0건** (grep 실측). 매 prove 실행마다 stderr에 섞이던 심볼 그래프 파서 노이즈가 소멸했다.
- 최종 교정 형태(2단계): 파스만 고친 한 줄 `{}.toTable`은 pre-commit nim_check_gate가 잡은 의미 오류로 기각 — `{}`/`{:}`는 빈 array 생성자라 `toTable` 타입 추론이 실패(nim 2.2.10 실측). 컴파일 가능 형태 `default(Table[string, Table[string, string]])` + 소비처 `.pairs` 순회로 확정.

lean 4.33.0은 이 문자열을 진단으로 출력한 적이 없다 — 귀속 교정의 근거는 (a) nim check 동일 재현, (b) 수정 후 라이브 prove에서 해당 줄 소멸, (c) quirk 문서 `docs/spec/nim_empty_multiline_table_constructor_quirk.md`.

## 2. 결함 2 — BMC 폴백 경로의 bare-numeral 발행 (lean 4.33.0 토큰화 오류)

`irToLeanModule` 폴백 모듈의 비교 연산이 `0.toInt`/`1.toInt`(bare 숫자 + `.toInt`)를 발행해 lean 4.33.0 토큰화가 실패했다:

- 수정 전 발행: `(maxWorkers.toInt > 0.toInt)`, `(result.toInt ≥ 1.toInt)`
- pinned lean 실측 오류: `5:25 error: unexpected identifier after decimal point; consider parenthesizing the number`, `11:20` 동일.
- `(0).toInt` 대안도 실패(괄호 숫자는 Nat로 정식화 — Nat에 toInt 없음).
- 수정: `leanBvSignedProj` 단일 규칙 — `(op : BitVec 64).toInt` — 를 `irBinExprToLean` 4분기(boLt/boLe/boGt/boGe)와 `refinedExprToProp` 4분기에 적용.
- 수정 후 발행: `((maxWorkers : BitVec 64).toInt > (0 : BitVec 64).toInt)`.

### 2.1 라이브 파이프라인 실측 (TMPDIR 우회 포획)

`canonicalLeanKernelCheck`는 커널 투입 소스를 `getTempDir()/axiom_kc_<sha256(leanSource)>.lean`에 기록 후 삭제하므로, `TMPDIR`을 관측 디렉터리로 두고 0.2s 폴링 복사기로 포획했다:

- 수정 전 바이너리(09:54 링크)의 포획물: `axiom_kc_67e9f04c….lean` — bare 형태, lean 재실행 시 5:25/11:20 토큰화 오류 재현.
- 수정 반영 바이너리의 포획물: `axiom_kc_9bfec262….lean` — ascribed 형태. 내용:

```lean
import Init
import Std.Tactic.BVDecide

def normalizeMaxWorkers (maxWorkers : BitVec 64) : BitVec 64 :=
  if ((maxWorkers : BitVec 64).toInt > (0 : BitVec 64).toInt) then
    maxWorkers
  else
    1
theorem normalizeMaxWorkers_post0 (maxWorkers : BitVec 64) :
  (let result := normalizeMaxWorkers maxWorkers;
    ((result : BitVec 64).toInt ≥ (1 : BitVec 64).toInt)) :=
by
  unfold normalizeMaxWorkers
  bv_decide

#print axioms normalizeMaxWorkers
```

- pinned lean 재실행: **토큰화 오류 소멸**. 유일 오류 = `14:2 error: None of the hypotheses are in the supported BitVec fragment after applying preprocessing.` (bv_decide 전술 프래그먼트 한계). `def normalizeMaxWorkers`는 `'normalizeMaxWorkers' does not depend on any axioms`로 axiom-free 확인.
- 따라서 라이브 `[LEAN ERROR] canonicalLeanKernelCheck: exit code 1`의 성격이 **파스 실패 → 정직한 전술 미증명**으로 바뀌었다. cert는 여전히 `certZ3Candidate`(승격 미달, §4).

## 3. 단위 회귀 테스트

`tests/unit/ir_to_lean_test.nim`에 2건 추가(`make test-fast-one T=tests/unit/ir_to_lean_test.nim`, exit 0):

- `refinedExprToProp literal operand uses ascribed projection (no bare .toInt)`: `"1.toInt" notin` + `"(1 : BitVec 64).toInt" in`
- `irExprToLean comparison literal operand uses ascribed projection`: `"0.toInt" notin` + `"(0 : BitVec 64).toInt" in`

## 4. 잔여 (본 세대 범위 밖, 추적됨)

- **승격 미달**: `cert status certZ3Candidate not promotion-eligible` 지속. 승격 authority인 canonical I6 경로의 라이브 funcDef에 대한 커널 판정이 본 슬라이스에서도 관측되지 않았고(ir_pipeline_runner가 canonical 실패를 조용히 폐기), BMC 폴백의 post 정리는 bv_decide 프래그먼트 밖(signed toInt 비교)이라 미증명. 전술 선택 변경(classifyPostCondition 라우팅)은 후속 슬라이스 과제 — DEBT#465 addendum에 기록.
- canonical I6 렌더(`renderLeanForFuncDef`, hand-built normalizeMaxWorkers, 271 bytes)는 pinned lean에서 exit 0 — I6 경로 자체의 발행은 건전.
- `test_s1a_lean_golden`의 canonical 체인 테스트 다수 실패는 베이스(83bc2c995) 동일 실패로 선존재(아래 §5 대조).

## 5. 베이스 대조 (선존재 판별)

| 항목 | 본 브랜치 | 베이스 83bc2c995 |
|---|---|---|
| `test_s1a_lean_golden` [FAILED] 수 | 10 | 10 (동일 실패 집합) |
| `test_s1a_lean_golden` [OK] 수 | 3 | 3 |
| `nimtry --diff-baseline src/` 신규 위반 | 1건 (동일 항목) | 1건 (동일 항목) |

실패 이름 목록 일치(executeCanonicalVerification VERIFIED, mul/div 체인, S1-B identity, 결정론, fingerprint ×2, evidence 일관성, evidenceId, KAA projection, splice resistance) — 본 변경 전부터 베이스에 존재하는 선존재 red이며 본 슬라이스 회귀가 아니다. 본 슬라이스 회귀 표면(ir_to_lean_test 전체 + `decodedLength`가 속한 골든 표면)은 green.

## 5.1 게이트 정합화 (규정 경로만 사용)

- `data/nimtry_baseline.json` (+45/−45): `bin/nimtry --update-baseline` 재생성. 내용은 전부 선존재 stale 정합화 — canonical_verification.nim 함수 시작행 −4, ir_pipeline_runner.nim 행 이동/727→728, attestation_orchestrator −2 등. 베이스에서 `--diff-baseline` 실행 결과가 동일하게 `New: 1, Stable: 4093`(동일 runIrPipeline 728 항목)임으로 본 슬라이스 고유 nimtry 증가는 0건.
- `data/debt_budgets.json` BUDGET#004(nimtry_violations): `bin/debt_engine --sync-budget` (공식 리컨실리에이터)로 current 2→0, open→closed, resolution WONT_FIX→FIXED. 근거: `bin/nimtry src/`가 잠금 베이스라인 PASS(projection=0). 단일 레코드만 변경(dry-run으로 확인).
- `data/architecture_debt.json` entry[243]: `bin/debt_engine --regen-arch`로 `src/core/trusted/ir_to_lean.nim` canonical hash 1건만 재생성(본 슬라이스의 소스 변경에 대한 정합화).

## 6. 명령 재현 목록

```
nim c … tmp/lean_emit_probe.nim && ./tmp/lean_emit_probe   # 3경로 렌더 덤프
cd proofs && lake env lean --threads=1 <dump>              # pinned lean 4.33.0 판정
make test-fast-one T=tests/unit/ir_to_lean_test.nim        # 회귀 2건
bin/ax prove --target normalizeMaxWorkers                  # 라이브 오라클
TMPDIR=<관측 dir> bin/ax prove … + 폴링 복사                # 커널 투입 소스 포획
```
