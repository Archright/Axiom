# ADR-0025 Amendment 사전등록 — guard-obligation 회전 동반 경로 열거 (2026-10-18)

> **종류**: 사전등록 문서 (decision pre-registration) — PR #919(선언-무관 guard 의무 증명 시도 + 선언 경로 반례 확인 승격)의 candidate delta가 클로저 멤버 `src/verification/rust_extraction_agreement.nim`·`src/verification/rust_obligation_render.nim`·`src/verification/rust_rust_pipeline.nim`·`src/cli/rust_lane_cli.nim`의 내용을 변경해 ROTATION 클래스로 분류됨에 대응하는 ④ 핀 재앵커 + ① 동반 경로 열거형 확장의 사전등록이다(62dbeab8b PR #895 — MG run 38997388474 ROT_NEW_PIN 해소와 동일 fix-class).
> **등록일**: 2026-10-18 (착지 이전 고정 — no-peeking; 큐 실측 MG run 39109781339 verdict `mergeAborted ROT_NEW_PIN` + `allowlistOk:false`).
> **소유자**: 2026-10-18 사용자 전면 허가("권한이 필요한 부분은 전면 허가한다") 하에 기계적 부분을 착지 워크트리에서 등록한다. 본 문서는 그 승인 결정의 정식 기록이다.
> **고정성**: 본 문서가 착지하는 순간 §1의 열거는 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 수록 범위 — 열거형 9경로 (glob 없음, A4 규율 준수)

`src/cli/merge_cli.nim` `RotationAllowlistExtra`에 아래 9경로를 선언 순서 그대로 수록한다. 미수록 경로는 fail-closed(ROT_ALLOWLIST)를 유지한다 — docs/**·tests/fixtures/rust/** 글롭화 금지. A5(2026-10-14)·mg_evidence(2026-10-17)가 이미 수록한 경로(docs/spec/rust_certified_subset.md·src/cli/rust_lane_cli.nim·tests/gateway/rust_lane_cli_acceptance_test.nim·tests/gateway/rust_subject_provenance_issuance_test.nim·data/benchmarks/perf_latest.json·data/debt_ledger.json·data/nimtry_baseline.json 등)는 재열거하지 않는다.

1. `docs/evidence/rotation_allowlist_guard_obligation_prereg_2026-10-18.md`(본 문서 — 착지와 동반)
2. `.gitignore`(tests/fixtures/rust/** negation 추가 — 픽스처 추적 누락 수리)
3. `Makefile`(test-fast grep 오탐 정밀화 — "psError"/"FAILED state" 무해 문자열 오판 수리)
4. `tests/fixtures/rust/axiom_guard_probe/Cargo.lock`
5. `tests/fixtures/rust/axiom_guard_probe/Cargo.toml`
6. `tests/fixtures/rust/axiom_guard_probe/README.md`
7. `tests/fixtures/rust/axiom_guard_probe/axiom_guard_probe.llbc`
8. `tests/fixtures/rust/axiom_guard_probe/src/lib.rs`
9. `tests/unit/test_rust_guard_attempt.nim`(회전 멤버의 단위 계약 — test_judgment_cas 동일 클래스) — `tests/unit/test_theater_allowlist_structure.nim`(선재 기대치 낡음 수리, cf648b2f8) 포함.

## 2. 판정 변화의 결정론성

- 본 회전은 **멤버십 불변**(876 유지 — 신규 클로저 멤버 0) 조건下的 내용 재앵커다: ④ `line-set(pin@H) == set(derived H)`는 유도값(`tools/ci/derive_checker_closure --ref H`) 기준으로만 갱신한다 — 추측 해시 금지(302ffb72b PR #827 훈련).
- 재앵커 대상 5경로: `src/cli/rust_lane_cli.nim`·`src/verification/rust_extraction_agreement.nim`·`src/verification/rust_obligation_render.nim`·`src/verification/rust_rust_pipeline.nim`·`src/cli/merge_cli.nim`(열거형 확장의 단일 최종 앵커 패스 — 본 커밋 blob).
- 동반 등록의 효력은 다음 세대(B-빌드 판정기)부터이며, 본 PR의 착지 경로는 trust-surface 수동 병합 경로다(④ 통과 시 TRUST_SURFACE_MODIFIED dryRunExit 0 — 전례 PR #856·62dbeab8b).
- `data/architecture_debt.json`: merge_cli.nim의 rawContentHash+canonicalSyntaxHash 2필드만 `debt_engine --regen-arch`로 갱신(dc65a269c·62dbeab8b 선례).

## 3. 검증 계획 (착지 전 기계 검증)

1. `agent_preflight` PASS
2. `bin/nimtry src/` exit 0 (베이스라인 래칭 후 재확인)
3. 커밋 후 `derive_checker_closure --ref HEAD` 출력의 라인 집합 == `config/trusted_writer_set.json` `trustedCheckerTreeClosure`(멤버십 876·blob 등식)
4. `tools/ci/verify_trusted_writer_set.sh` PASS
5. `bin/debt_engine --validate` 6 PASS 0 DRIFT
