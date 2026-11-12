# ADR-0025 Amendment A5 사전등록 — rust lane 착지 rotation allowlist 확장 (2026-10-14)

> **종류**: 사전등록 문서 (decision pre-registration) — PR #827(rust lane live CLI 착지)의 candidate delta가 클로저 멤버 `src/cli/merge_cli.nim`(`RotationAllowlistExtra` SSOT)를 변경해 ROTATION 클래스로 분류됨에 대응하는 동반 회전 경로 열거형 확장의 사전등록이다(ADR-0025 Amendment A4와 같은 fix-class).
> **등록일**: 2026-10-14 (착지 이전 고정 — no-peeking).
> **소유자**: 2026-10-14 사용자 전면 허가 하에 A5 기계적 부분을 착지 워크트리에서 등록한다. 본 문서는 그 승인 결정의 정식 기록이다.
> **고정성**: 본 문서가 착지하는 순간 §1의 열거는 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 수록 범위 — 열거형 16경로 (glob 없음, A4 규율 준수)

`src/cli/merge_cli.nim` `RotationAllowlistExtra`에 아래 16경로를 선언 순서 그대로 수록한다. 미수록 경로는 fail-closed(ROT_ALLOWLIST)를 유지한다 — docs/**·tests/fixtures/rust/** 글롭화 금지.

1. `data/verification_scope.lock`
2. `docs/evidence/rotation_allowlist_a5_prereg_2026-10-14.md`(본 문서 — 착지와 동반)
3. `docs/spec/rust_certified_subset.md`
4. `docs/spec/rust_toolchain_quirks.md`
5. `src/cli/rust_lane_cli.nim`
6. `src/verification/charon_runner.nim`
7. `tests/fixtures/rust/axiom_rust_probe/Cargo.lock`
8. `tests/fixtures/rust/axiom_rust_probe/Cargo.toml`
9. `tests/fixtures/rust/axiom_rust_probe/README.md`
10. `tests/fixtures/rust/axiom_rust_probe/axiom.specs.json`
11. `tests/fixtures/rust/axiom_rust_probe/axiom_rust_probe.llbc`
12. `tests/fixtures/rust/axiom_rust_probe/src/lib.rs`
13. `tests/gateway/rust_lane_cli_acceptance_test.nim`
14. `tests/gateway/rust_subject_provenance_issuance_test.nim`
15. `tests/gateway/rust_subject_three_cases_test.nim`
16. `tests/unit/test_charon_runner.nim`

## 2. 판정 변화의 결정론성

본 확장의 판정 효과는 결정론적이다 — 수록 경로로 한정된 candidate delta의 판정이 ROT_ALLOWLIST(rqNone) → ROTATION(rqRotation)으로 바뀌는 것이 전부이며, 같은 delta → 같은 판정이다. 비수록 경로의 판정은 불변이며, 어떤 판정 권위도 이동·추가·약화하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).

## 3. 승인 = 착지

본 사전등록의 승인은 PR #827의 착지 그 자체다(AGENTS.md §0.10 결정 바인딩). 착지 이후 §1 열거 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.
