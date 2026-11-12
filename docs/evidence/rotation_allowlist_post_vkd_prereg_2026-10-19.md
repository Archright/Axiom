# ADR-0025 Amendment 사전등록 — post-vkd 회전 동반 경로 열거 (2026-10-19, 세 번째)

> **종류**: 사전등록 문서 (decision pre-registration) — #936/#950 시대 일관성 스윕(dead code 처분·주석/문서 정정)의 candidate delta가 클로저 멤버 `src/cli/shared/proof_hydration.nim`을 변경해 ROTATION 클래스로 분류됨에 대응하는 ④ 핀 재앵커 + ① 동반 경로 열거형 확장의 사전등록이다(62dbeab8b·10-18·10-19 선례와 동일 fix-class).
> **등록일**: 2026-10-19 (착지 이전 고정 — no-peeking; 같은 날짜의 첫(guard_confirmation)·둘째(replay_evidence) 사전등록과 별개 슬라이스).
> **소유자**: 2026-10-19 사용자 전면 허가("권한이 필요한 부분은 전면 허가한다") 하에 기계적 부분을 착지 워크트리에서 등록한다.
> **고정성**: 본 문서가 착지하는 순간 §1의 열거는 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 수록 범위 — 열거형 3경로 (glob 없음, A4 규율 준수)

`src/cli/merge_cli.nim` `RotationAllowlistExtra`에 아래 3경로를 추가한다. 기존 문서(A5·mg_evidence·guard_obligation·guard_confirmation·replay_evidence)가 수록한 경로는 재열거하지 않는다.

1. `docs/agents/report-guardrails.md`(정정: 존재하지 않는 `buildAsiReportNode`·강제 위치 서술을 실제 구현으로)
2. `tests/unit/test_vkd_ssot_invariant.nim`(동면 테스트의 폐기된 "vault-scan fallback" 주석 정정 — #936 이후 canonical reader는 캐시를 읽지 않음)
3. `docs/evidence/rotation_allowlist_post_vkd_prereg_2026-10-19.md`(본 문서 — 착지와 동반)

## 2. 판정 변화의 결정론성

- 본 회전은 **멤버십 불변** 조건의 내용 재앵커다: ④ `line-set(pin@H) == set(derived H)`는 유도값 기준으로만 갱신한다.
- 재앵커 대상 2경로: `src/cli/shared/proof_hydration.nim`(dead `tryWriteBackL1Cache` 삭제 — 호출자 0, #936이 저널 기반으로 전환; 모듈/DEBT#433 주석의 거짓 서술 3블록 정정, `forceHydration` 무시 명시), `src/cli/merge_cli.nim`(열거형 확장의 단일 최종 앵커 패스 — 본 커밋 blob).
- DEBT#433 레지스트리 항목은 §0.5c(추적 마커 수정 금지)에 따라 **역사 기록 보존** — 해소 판정은 debt 프로세스 소관(후속 보고). `src/generated/type_registry_metadata.json`의 stale 엔트리는 차기 hermetic 빌드에서 갱신(게이트 무영향).
- `data/architecture_debt.json`: `debt_engine --regen-arch`; `data/nimtry_baseline.json`: `nimtry --update-baseline`(dead code 제거 반영) + `--sync-budget`.

## 3. 검증 계획 (착지 전 기계 검증)

1. `agent_preflight` PASS · `bin/nimtry src/` exit 0
2. 빌드 + `make local-verify-static`·`verify-contract`·`test-fast`(43)
3. 커밋 후 `derive_checker_closure --ref HEAD` == pin(멤버십 불변·blob 등식), `verify_trusted_writer_set.sh` PASS, `debt_engine --validate` PASS
