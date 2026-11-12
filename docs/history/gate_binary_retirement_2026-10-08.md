# Gate Binary Retirement — `bin/documentation_first_gate_selftest` · `bin/unified_gate_runner_procs`

**날짜**: 2026-10-08
**HEAD 기준**: `origin/main` = `83bc2c995` (pristine 재현 포함)
**판정**: 두 바이너리는 **retire**한다. 소스 모듈은 소유자 승인 영구 부채(DEBT#491 · DEBT#492, Closed)로
유지되며, **부활도 삭제도 하지 않는다**. 이 문서는 "이 두 바이너리가 빌드돼야 한다"는 선존재 기대를
폐기하는 근거 기록이다.

---

## 1. 배경과 이슈 전제 교정

이슈 전제: "두 게이트 바이너리가 HEAD에서 빌드 실패(선존재 파손)". 실측 교정:

- 두 바이너리는 **트래킹된 빌드 규칙이 존재한 적이 없다** — Makefile·tools/·ci/ 어디에도
  `bin/documentation_first_gate_selftest`·`bin/unified_gate_runner_procs` 타깃이 없다
  (`grep -rn` 실측, 2026-10-08). bin/ 내 존재했던 유사 이름(bin/unified_gate_runner_types 등)은
  `tools/build_all_gates.nim`의 디렉터리 walk 부산물이며, 두 대상은 그조차 빌드 실패로 생성된 적이 없다.
- pre-push liveness 7쌍(`.githooks/pre-push` pair 목록)과 `config/gates.manifest.toml` 어디에도
  두 소스는 배선되지 않았다. manifest가 가리키는 문서 게이트는
  `src/gate/runners/documentation_first_gate.nim`(gates.manifest.toml:76) 하나뿐이다.
- 즉 파손이 아니라 **배선된 적 없는 모듈**이다 — §0.12 관점에서 "새 공개 표면"을 만들 이유가 없다.

## 2. 빌드 실패 재현 (HEAD `83bc2c995`, nim 2.2.10)

```
$ nim c --hints:off ... src/gate/runners/documentation_first_gate_selftest.nim
src/gate/runners/documentation_first_gate_selftest.nim(12, 3) Error: undeclared identifier: 'stderrOut'

$ nim c --hints:off ... src/gate/runners/unified_gate_runner_procs.nim
src/gate/runners/unified_gate_runner_procs.nim(20, 9) Error: cannot open file: unified_gate_runner_procs_helpers
```

## 3. 언어적 근거 (Nim 2.2 공식 문서, Context7 조회 2026-10-08)

- **include**: "The include statement inserts the contents of specified files into the current
  scope" — 컴파일타임 파일 삽입이므로 대상 파일이 없으면 `cannot open file`로 실패한다.
  `unified_gate_runner_procs.nim:20-21`의 `unified_gate_runner_procs_helpers`·`..._scanners`는
  **어떤 커밋에도 존재한 적 없다**(DEBT#491 기술Description 실측 기록). → 모든 세대에서
  구조적으로 컴파일 불가. 수리하려면 존재하지 않던 구현을 새로 지어내야 한다 = 극장(§0.9).
- **import**: "Only top-level symbols marked with an asterisk (*) are exported" —
  `documentation_first_gate.nim:104`의 `proc stderrOut`(비공개, `*` 없음)은 import하는
  selftest 모듈 스코프에 존재하지 않아 `undeclared identifier`다. 수리하려면 배선된 게이트의
  심볼을 비배선 중복본을 위해 export하거나 중복본이 자체 헬퍼를 지녀야 한다 — 어느 쪽이든
  계약 없는 표면 확장이다(§0.12).

Nim 2.2.10 stdlib quirk 사항이 아니라 언어 시맨틱이므로 `docs/spec/nim_2_2_10_stdlib_quirks.md`
등록 대상이 아니다(동 문서 Q-001류 stdlib 제거 케이스와 별개).

## 4. 소비자·권한 실측 (모두 2026-10-08 실측)

| 질의 | 결과 |
|---|---|
| `grep -rn "documentation_first_gate_selftest" src/ tools/ tests/ --include=*.nim` | helper_spec.nim:20 + generated helper_registry.nim:11 (문자열 SSOT뿐, import 0건) |
| `grep -rn "unified_gate_runner"` (동일) | helper_spec.nim:35-38 + helper_registry.nim + 주석·도구 문자열뿐, import 0건 |
| pre-push liveness pair 목록 | 7쌍(debt_engine, check_nim_theater, doc_path_validator, proof_unit_consistency_gate, proof_reconcile_gate, epoch_transaction_gate, layer_enforcement_gate) — 두 대상 없음 |
| `config/gates.manifest.toml` | 두 소스 미배선 |
| `make gate-binaries` 범위 | liveness 6종 + validate-runners + layer_enforcement_gate + effect_contract_projection — 두 대상 없음 |
| 부채 레지스트리 | DEBT#491(unified_gate_runner_procs) · DEBT#492(documentation_first_gate_selftest) — 모두 `Theater/Dead Gate`, **[ACCEPTED 2026-10-07: Owner decision B (V1 disposition)]**, Closed |

## 5. 실제 게이트 생존 확인 (극장 판정의 반증 책임)

"self-test 게이트가 죽었다"는 전제에 대한 반증 — 진짜 셀프테스트는 wiring된 게이트 바이너리 안에
살아 있고(DEBT#492 명시), HEAD에서 재빌드 후 실측 통과한다:

```
$ nim c ... -d:release -o:bin/documentation_first_gate src/gate/runners/documentation_first_gate.nim   # exit 0
$ ./bin/documentation_first_gate --self-test
[documentation-first] --self-test
  [1] Load documentation_first.json ... OK — 12 triggers loaded
  [2] Trigger keyword matching ...     OK — clean file produces no issues
  [3] Official URL detection ...       OK — URL detection correct
  [4] Source file detection ...        OK — source file filter correct
  [5] Evidence check functions ...     OK — evidence functions execute without crash
  [6] History write ...                OK — history write succeeded
Results: 6 passed, 0 failed            # exit 0
```

게이트웨이 핀 테스트 `tests/gateway/documentation_first_gate_test.nim`도 존재한다.
→ documentation-first 자체검증 경로는 생존해 있으므로 §0.9 위반(죽은 게이트)이 아니다.

## 6. 판정과 근거

1. **두 바이너리 retire** — 빌드 규칙·소비자·계약이 없으므로 존재해야 할 바이너리가 아니다.
   재생성 요구 자체가 극장(보장 없는 산출물)을 만든다.
2. **소스 부활 금지** — DEBT#491/492는 소유자 결정 B(2026-10-07)로 "remnant purge deliberately
   NOT landed; accepted as permanent debt"로 성립한 결정 바인딩(§0.10)이다. 에이전트가 임의로
   뒤집을 수 없고, 부활은 계약 없는 새 공개 표면(§0.12)이 된다.
3. **소스 삭제 금지** — 소유자가 퍼지를 명시적으로 보류했다. §0.5c상 추적된 부채 마커의 무단
   제거도 금지된다.
4. 본 작업은 코드 변경 없이 이 기록으로 이슈를 닫는다. **Follow-up(범위 밖)**:
   `tools/build_all_gates.nim`의 발견 롤은 죽은 부채 모듈 2종을 "게이트"로 발견해 도구가 항상
   exit 1로 끝난다(단, liveness 7쌍 재빌드 자체는 정상 수행·성공). pre-push remedy 텍스트가 이
   도구를 권장하므로, 별도 이슈로 발견 롤의 부채 정합(제외 목록의 레지스트리 연동 등)을
   검토할 것.
