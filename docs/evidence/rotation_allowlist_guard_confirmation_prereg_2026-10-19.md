# ADR-0025 Amendment 사전등록 — guard-confirmation 회전 동반 경로 열거 (2026-10-19)

> **종류**: 사전등록 문서 (decision pre-registration) — A-슬라이스(overflow 관측의 계약 정합 운영화: Option A 유지 — 미선언 guard 위반은 `unknown`+증거 정밀 reason)의 candidate delta가 클로저 멤버 `src/cli/axiom_engine.nim`·`src/cli/rust_lane_cli.nim`·`src/verification/rust_rust_pipeline.nim`·`src/verification/rust_replay_adapter.nim`의 내용을 변경해 ROTATION 클래스로 분류됨에 대응하는 ④ 핀 재앵커 + ① 동반 경로 열거형 확장의 사전등록이다(62dbeab8b PR #895·10-18 guard_obligation 선례와 동일 fix-class).
> **등록일**: 2026-10-19 (착지 이전 고정 — no-peeking).
> **소유자**: 2026-10-19 사용자 전면 허가("권한이 필요한 부분은 전면 허가한다") 하에 기계적 부분을 착지 워크트리에서 등록한다. 본 문서는 그 승인 결정의 정식 기록이다.
> **고정성**: 본 문서가 착지하는 순간 §1의 열거는 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 수록 범위 — 열거형 2경로 (glob 없음, A4 규율 준수)

`src/cli/merge_cli.nim` `RotationAllowlistExtra`에 아래 2경로를 추가한다. A5(2026-10-14)·mg_evidence(2026-10-17)·guard_obligation(2026-10-18)이 이미 수록한 경로(Makefile·docs/spec/rust_certified_subset.md·docs/spec/rust_toolchain_quirks.md·tests/gateway/rust_lane_cli_acceptance_test.nim·tests/unit/test_rust_guard_attempt.nim 등)는 재열거하지 않는다.

1. `tests/unit/test_rust_replay_adapter.nim`(회전 멤버 rust_replay_adapter.nim의 단위 계약 — test_judgment_cas 동일 클래스)
2. `docs/evidence/rotation_allowlist_guard_confirmation_prereg_2026-10-19.md`(본 문서 — 착지와 동반)

## 2. 판정 변화의 결정론성

- 본 회전은 **멤버십 불변** 조건의 내용 재앵커다: ④ `line-set(pin@H) == set(derived H)`는 유도값(`tools/ci/derive_checker_closure --ref H`) 기준으로만 갱신한다 — 추측 해시 금지(302ffb72b PR #827 훈련).
- 재앵커 대상 5경로: `src/cli/axiom_engine.nim`(§10 projectAbs 절대화 — 상대 `--project`가 lane workDir 해시·guard 리플레이 harness `include!`에 새던 결함의 근본 수정), `src/cli/rust_lane_cli.nim`(확인 필드 로그·modulePath 전달), `src/verification/rust_rust_pipeline.nim`(confirmGuardByReplay 투영), `src/verification/rust_replay_adapter.nim`(프로파일 플래그·rroPanicked·증거 기록), `src/cli/merge_cli.nim`(열거형 확장의 단일 최종 앵커 패스 — 본 커밋 blob).
- 동반 등록의 효력은 다음 세대(B-빌드 판정기)부터이며, 본 PR의 착지 경로는 trust-surface 수동 병합 경로다(④ 통과 시 TRUST_SURFACE_MODIFIED dryRunExit 0 — 전례 PR #856·62dbeab8b).
- `data/architecture_debt.json`: `debt_engine --regen-arch`로 변경 멤버 해시만 갱신(dc65a269c·62dbeab8b 선례).

## 3. 검증 계획 (착지 전 기계 검증)

1. `agent_preflight` PASS
2. `bin/nimtry src/` exit 0 (베이스라인 상태 재확인)
3. 커밋 후 `derive_checker_closure --ref HEAD` 출력의 라인 집합 == `config/trusted_writer_set.json` `trustedCheckerTreeClosure`(멤버십 불변·blob 등식)
4. `tools/ci/verify_trusted_writer_set.sh` PASS
5. `bin/debt_engine --validate` PASS
