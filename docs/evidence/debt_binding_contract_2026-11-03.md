# A-lite 바인딩 유형 계약 착지 증거 (2026-11-03)

**슬라이스**: debt binding-type contract — LIVE 권한(`bin/debt_engine --validate`) 경유 시행
**브랜치**: `work/a-lite-binding-contract-2026-11-03` (base: main @ `95623dbf7`)
**작업 공간**: 전용 worktree `/tmp/a_lite_binding_wt` (main worktree 무수정)
**FROZEN 준수**: `src/gate/**`, `AGENTS.md`, `Makefile`, `ci/checker.mk`, `config/policy/**`, `.github/**`, `config/repository_surface.json`, `vendor/**` 미수정 (§-1 포함)

---

## 1. 변경 내역 (6 files)

| 파일 | 변경 |
|---|---|
| `data/debt_schema.json` | `DebtRegistryEntry`에 `binding`(enum `["nim_pragma","registry_disposition"]`)·`bindingRationale`(string, minLength 1, `\S` 패턴) 속성 추가 + `allOf` 조건부(`binding` == `registry_disposition`일 때만 `bindingRationale` 필수). `additionalProperties: false` 유지. **`default` 키워드 미사용** — 부재 해석은 조건부의 `required: ["binding"]`에 의한 검증기 동작으로 보장. |
| `data/debt_registry.json` | 정확히 10개 STALE 엔트리에만 2필드 추가. **diff = 20 insertions / 0 deletions** — 나머지 234엔트리·기존 필드 바이트 불변 (`git diff --numstat` 실측). |
| `src/core/debt/debt_registry_projection.nim` | `DebtRegistryFieldsOutOfContract`에 `"binding"`, `"bindingRationale"` 추가 (P0 통과). projection은 이 필드를 읽거나 렌더링하지 않음. |
| `docs/spec/debt_registry_schema.md` | §3 필드 표 2행 추가 + 신규 §10 "Binding type" 섹션(허용값, 부재=nim_pragma 해석의 검증기 동작+산문 이중 명시, 예약값 `comment_marker` FAIL, rationale 내용·추적 지시 요건, 정직 범위 선언). §9 Fact→Authority 참조 불변. |
| `tests/ci/test_debt_schema_theater_rule.py` | 바인딩 규칙 fixture 5종 추가 — 음성 3(registry_disposition 무-rationale → invalid, 예약값 `comment_marker` → invalid, 공백-only rationale → invalid) + 양성 2(registry_disposition+rationale → valid, **레거시 무-binding → valid**). pytest 수집용 wrapper 추가, 기존 직접 실행 경로(CI `python3 tests/ci/...`) 유지. |
| `docs/evidence/debt_binding_contract_2026-11-03.md` | 본 문서. |

10엔트리 분류와 rationale 추적 지시: 비-Nim 매체 5(DEBT-CI#003, DEBT#432, DEBT#472, DEBT#506, DEBT#509), 의도적 무마커/처분 등록 5(DEBT#496=ADR-0029 §5, DEBT#504=rotation-class, DEBT#505=nimtry 앵커 처분, DEBT#507=rotation 후속, DEBT#512=FROZEN 장벽·ADR-0038 pending). 각 `bindingRationale`은 엔트리 자체의 `resolution`/`source`를 명시하고 해당 시 외부 문서 경로·항목 ID를 지시한다.

## 2. 검증 행렬 (실측, worktree /tmp/a_lite_binding_wt, 2026-11-03)

| # | 명령 | 실측 결과 |
|---|---|---|
| 1 | `python3 -c "json.load(...)"` (schema+registry) | both JSON parse OK |
| 2 | `python3 tests/ci/test_debt_schema_theater_rule.py` | `PASS: Theater five-field + binding-type fixtures all green (3 negative, 2 positive); real registry is clean` — rc=0 |
| 3 | `python3 -m pytest tests/ci/test_debt_schema_theater_rule.py -v` | `1 passed in 0.17s` (pytest 9.2.0, 측정을 위해 사용자 로컬 설치; CI는 jsonschema만 설치하고 스크립트를 직접 실행) |
| 4 | `make bin/debt_engine && bin/debt_engine --validate` | `✅ [schema] standard JSON Schema validation passed (Draft 2020-12)` (W6) · `✅ P0 every registry field is declared in or out of projection contract` · `Checks: 1538 total, 1538 passed, 0 failed` · `All debt validation checks passed.` — **EXIT=0** (검사 수: 기존 기준 1538과 동일) |
| 5 | `make bin/nimtry && bin/nimtry src/` | `[nimtry] PASS — 4261 violations (debt anchored) (errors: 373, warnings: 3888) (cache: 1328 hits, 0 misses)` — **EXIT=0**. projection 파일 편집에도 앵커 이동 없음 → **재앵커 시퀀스(nimtry --update-baseline + debt_engine --regen-arch + debt_integrity_gate --update-baseline + --sync-budget) 미수행(불필요)**, `data/nimtry_baseline.json`·`data/debt_ledger.json` 미변경. |
| 6 | `bin/debt_integrity_gate` | **10 stale debt(s) — FAIL, EXIT=1 — 변경 없음** (§3 verbatim). 게이트 스캔 결과는 이 슬라이스 전후 동일. |
| 7 | `jq` 10엔트리 확인 | `binding == "registry_disposition"`인 엔트리 = 정확히 10 (DEBT-CI#003, DEBT#432, DEBT#472, DEBT#496, DEBT#504, DEBT#505, DEBT#506, DEBT#507, DEBT#509, DEBT#512), 전부 `bindingRationale` 비공백. 총 244 entries. |
| 8 | `git diff --numstat data/debt_registry.json` | `20  0` — 순수 삽입. |
| 9 | `git status` (커밋 직전) | 수정 = 위 6파일뿐. (`make build`가 재생성한 `src/generated/build_metadata.json`은 변경 목록 밖이라 원복.) |

측정 비고: 최초 nimtry 실행은 본 검증의 pytest 실행이 만든 `tests/ci/__pycache__/*.pyc` 1건을 신규 위반으로 보고 FAIL → 캐시 제거 후 재실행 PASS(위 #5). 슬라이스 코드와 무관한 측정 부산물이며, 재발 방지를 위해 pytest 실행 시 bytecode/cacheprovider 비활성화 권장.

## 3. bin/debt_integrity_gate 출력 (verbatim — STALE 10 그대로)

```
[INFO] [debt-integrity-gate]: nimtry — Active Violations: 4261 / Historical Baseline Cap: 4261
[INFO] [debt-integrity-gate]: Registry: 244 entries (30 open, 0 accepted)
[INFO] [debt-integrity-gate]: Code: 23 {.axiomDebt.} markers found
[ERROR] [debt-integrity-gate]: STALE: DEBT-CI#003 is open in registry but has no {.axiomDebt.} marker
[ERROR] [debt-integrity-gate]: STALE: DEBT#432 is open in registry but has no {.axiomDebt.} marker
[ERROR] [debt-integrity-gate]: STALE: DEBT#472 is open in registry but has no {.axiomDebt.} marker
[ERROR] [debt-integrity-gate]: STALE: DEBT#496 is open in registry but has no {.axiomDebt.} marker
[ERROR] [debt-integrity-gate]: STALE: DEBT#504 is open in registry but has no {.axiomDebt.} marker
[ERROR] [debt-integrity-gate]: STALE: DEBT#505 is open in registry but has no {.axiomDebt.} marker
[ERROR] [debt-integrity-gate]: STALE: DEBT#506 is open in registry but has no {.axiomDebt.} marker
[ERROR] [debt-integrity-gate]: STALE: DEBT#507 is open in registry but has no {.axiomDebt.} marker
[ERROR] [debt-integrity-gate]: STALE: DEBT#509 is open in registry but has no {.axiomDebt.} marker
[ERROR] [debt-integrity-gate]: STALE: DEBT#512 is open in registry but has no {.axiomDebt.} marker
[ERROR] [debt-integrity-gate]: 10 stale debt(s) — FAIL
```

EXIT=1. **이 FAIL은 정상이다.** 게이트(`src/gate/runners/debt_integrity_gate.nim`)는 FROZEN이며 본 슬라이스가 건드리지 않았다 — STALE 10은 여전히 "open in registry but has no {.axiomDebt.} marker"로 보고된다. 참고 사실: (a) 게이트 자체는 orphan이다 — DEBT#499(registry `audit` 소스, 수동 전용, 소비자 0)가 이를 등록하며, 게이트는 어떤 파이프라인 소비자도 갖지 않는다(PUSH_ADMISSIBILITY_GATES 미포함). (b) DEBT#512는 이 STALE 드rift 자체(statusEnum↔matchesStatus 불일치 + FROZEN 장벽)를 등록한 엔트리로, ADR-0038(`docs/adr/0038-debt-status-vocabulary-decision-request.md`) 결정 요청이 pending이다. 바인딩 선언은 게이트의 STALE 판정을 해소·마스킹하지 않는다 — 게이트의 src/ 스캔은 `{.axiomDebt.}` 마커 유무만 보고하고 `binding`/`bindingRationale`은 읽지 않는다(필드는 projection out-of-contract로 등록되어 게이트 관점 부재와 무관).

## 4. 정직 범위 선언 (Honest Scope)

본 슬라이스가 완료하는 것은 문서화된 처분을 참조하는 바인딩 선언의 **기계적 형식 검증**이지, 처분의 의미적 정당성 자동 입증이 **아니다**. `bin/debt_engine --validate`는 각 `bindingRationale`의 존재·비공백·enum 적합성만 검증한다(W6 Draft 2020-12 + 조건부). rationale이 서술하는 처분 자체("이 매체에는 Nim pragma가 구조적으로 불가능하다", "ADR-0029 §5가 이 표면의 작성자 권위다" 등)의 진위는 여전히 인간 검토와 해당 문서(ADR-0029, ADR-0038, config/repository_surface.json, DECISION-0630)의 권위에 의존한다. STALE FAIL의 해소는 본 슬라이스의 범위가 아니며, 그 판정은 FROZEN 게이트에 그대로 남는다(§3).
