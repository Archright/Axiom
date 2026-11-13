# 테스트 드리프트·베이스라인 스테일 일괄 수정 — 수용 증거 (2026-11-13)

> **종류**: 실행 증거 기록. canonical main(`e0747be`)에서 관측된 선재 테스트 결함 3건과
> nimtry 베이스라인 스테일 4건을 병렬 서브에이전트 4기(agent-21/22/24/23)로 진단·분류하고,
> **전부 테스트/데이터 측 기계적 드리프트**로 판정된 것만 최소 수정한다. 제품 코드(src/)는
> 무변경 — 모든 원인이 커밋된 결정(SSOT)을 테스트·베이스라인이 따라가지 못한 것이다.

## 1. 수정 내역

| 대상 | 판정 | 근거(SSOT) | 수정 |
|---|---|---|---|
| `tests/cli/test_axiom_engine.nim` 컴파일 실패(`undeclared field: 'asi'`) | 드리프트 | `LedgerEvent`는 `vkd` 스키마(`src/cli/axiom_engine.nim:158-166`, 운영 `logs/audit/vsr_ledger.jsonl`·§0.11) | `asi→vkd` 12곳 필드·키·테스트명 갱신 (agent-21) |
| 동 파일 2케이스 실패(`default path…`, `env key absent…`) | 드리프트 | DECISION-0622/0623(v32): 기본 vault = `stateJoin("build","certificates")`(`src/verification/cert_vault_role.nim:42`) | 기대값을 SSOT 합성식(`AXIOM_STATE_DIR` 우선, 미설정 시 CWD)으로 갱신 — 러너 환경 무관 결정론적 |
| `tests/unit/test_certificate_lifecycle_v3_test.nim` 1/4 | 드리프트 | DECISION-0673: 저널 루트 통합 — writer·closure reader 모두 `activeJournalRoot()`가 `AXIOM_STATE_DIR` 우선 해석 | `withHermeticJournalRoot` 주입을 `AXIOM_ROOT`→`AXIOM_STATE_DIR`로 전환 + 주석을 현행 계약으로 재서술 (agent-22) |
| `data/nimtry_baseline.json` 4,262→4,275 | 스테일 | FAIL 4건 전부 문서화된 착지 변경의 미반영: ① `main.nim` LCOM 0.667(VS-1 수용 §2) ② `provenance_probe.nim` LCOM 1.0(VS-1 위임 설계) ③ `source_identity_cache.nim:165` importc(rename(2) 원자 교체 — VS-1 설계·`nim_effect_system_quirks.md` §24, 선례 libc 바인딩 4건과 동일 패턴) ④ rust fixture `.rs`(escape-slice 수용 fixture, 형제 5종과 동일 클래스). 신규 위반 0건 — §0.9 극장 아님(에러 등급 debt anchoring 자체가 저장소 메커니즘) | 승인 플래그 `./bin/nimtry src/ --update-baseline` (agent-24) |

## 2. 검증 (전부 실측)

| 검증 | 결과 |
|---|---|
| `nim c … test_axiom_engine.nim && 실행` | **49/49 OK, FAIL 0** |
| `nim c … test_certificate_lifecycle_v3_test.nim && 실행` | **5 OK / 0 FAIL** (was 1/4) |
| `tests/verification/test_attestation.nim` (무수정) | **ALL PASSED (243 checks, 0 skipped)** — 선재 "68/1"은 현재 main에서 재현되지 않음(직전 PR들에서 해소로 추정) |
| `./bin/nimtry src/` | **PASS — 4275 violations (debt anchored), exit 0** (2회 반복 결정론 확인) |
| `make check-arch` | **✅ No architecture violations** |
| `make verify-contract` | **✅ PASSED (g1, g2, g6g4, g7)** |
| 제품 코드 변경 | **0바이트** (`git diff --stat` = 테스트 2파일 + 베이스라인 1파일) |

## 3. 발견 후속(범위 밖 — 별도 슬라이스)

- `bin/debt_integrity_gate` 로컬 실패(선재): `nimtry_violation_count` 캡 4,259 < 실측(체크아웃 시점 4,262 → 본 갱신 4,275). 승인 갱신 플래그(`--update-baseline`)로 캡 동결은 가능하나, 갱신 시 **또 다른 선재 결함이 노출**: 레지스트리 open 항목 중 코드 마커 `{.axiomDebt.}` 없는 **STALE DEBT 17건**(DEBT#524/#525 등). 마커 복원 vs 레지스트리 폐쇄는 부채 수명주기 정책 판정이 필요 → 계획 슬라이스로 분리. CI 필수 경로(debt-registry-gate는 `debt_engine --validate`만 실행)에 영향 없음.
- pre-push 스냅숏이 `effect_contract_projection`·`nimtry` 외에도 `surface_guard`·`hermetic_build`·`sync_certs` 등을 조건 없이 빌드(잔존 스냅숏 bin/ 실물 관측) — Makefile:483과 같은 부류의 낭비, 같은 계획 슬라이스에서 함께 설계.

## 4. 착지

PR 번호·필수 체크·Merge Queue·native MERGE·main 수용 결과는 본 문서 커밋 후 이어지는
수용 절차 완료 시 갱신한다.
