# ADR-0025 Amendment 사전등록 — VS-1 회전핀 프리플라이트 동반 경로 열거 (2026-10-20)

> **종류**: 사전등록 문서 (decision pre-registration) — VS-1(candidate delta가 클로저 멤버 `src/cli/merge_cli.nim`을 변경하고 신규 클로저 멤버 `src/core/policy/rotation_closure_facts.nim`을 **추가**한다)은 landing predicate에서 ROTATION 클래스로 분류된다. 본 문서는 그 ① allowlist 동반 경로 열거와 ④ 핀 재앵커를 착지 이전에 고정한다.
> **등록일**: 2026-10-20 (착지 이전 고정 — no-peeking).
> **소유자/권한**: 2026-10-20 사용자 전면 허가("권한이 필요한 부분은 전면 허가한다") 하에 기계적 부분을 착지 워크트리에서 등록한다. **판정 권위는 변하지 않는다** — GitHub ruleset·required checks·merge queue가 최종 병합 권위이고, 본 문서는 그 앞단의 열거를 기록할 뿐이다(Authority ≠ Adapter, AGENTS.md §2.3). trustSurface PR이므로 자동 병합은 구조적으로 거부되며 사람의 manual merge lane이 유일한 정당 경로다(`docs/agents/operations.md` MUST-T2).
> **고정성**: 본 문서가 착지하는 순간 §1의 열거는 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 수록 범위 — 열거형 4경로 (glob 없음, A4 규율 준수)

`src/cli/merge_cli.nim` `RotationAllowlistExtra`에 아래 4경로를 추가한다. 기존 문서(A5·P3·P3-final·P3-t2·guard_obligation·guard_confirmation·replay_evidence·post_vkd)가 수록한 경로는 재열거하지 않는다.

1. `src/core/policy/rotation_closure_facts.nim` — **신규 클로저 멤버**. H2(④) 판정과 pin/closure 파싱 프리미티브의 단일 구현(리프 모듈). pin@B에는 존재하지 않으므로(=신규 멤버) ① membership으로는 승인될 수 없다.
2. `tools/ci/rotation_pin_anchor_check.nim` — 프리플라이트 판정 오라클(비멤버: deriver walk 대상 밖). 같은 판정의 두 번째 구현이 아니라 리프 모듈의 CLI 표면이다.
3. `tests/ci/test_rotation_pin_anchor_check.nim` — 오라클의 exit 계약(0/1/2)·JSONC 파싱·fail-closed 입력 골든.
4. `docs/evidence/rotation_preflight_prereg_2026-10-20.md` — 게이트 계약 사전등록(착지와 동반).

이미 열거된 동반 경로(재열거 불요): `.github/workflows/admission-check.yml`, `config/policy/epoch_manifest.json`, `tests/cli/test_merge_cli.nim`. pin 파일(`config/trusted_writer_set.json`)은 `RotationPinBPath` 술어로 이미 허용되고, `src/cli/merge_cli.nim`은 pin@B 멤버다.

## 2. 판정 변화의 결정론성

- 본 회전은 **멤버십 추가 1건 + 내용 재앵커 1건**이다. ④ `line-set(pin@H) == set(derived H)`는 deriver 산출로만 갱신한다(손편집 없음 — `derive_checker_closure --ref HEAD`, 879→880 멤버).
- 재앵커 대상: `src/cli/merge_cli.nim`(리프 모듈 import·`export` 허브 재노출·`annotateNewAnchor` 위임·본 열거형 확장). 신규: `src/core/policy/rotation_closure_facts.nim`.
- **landing predicate 판정 로직은 바뀌지 않는다**: `adjudicateRotation`의 사다리·사유 문자열은 불변이고, 위임 대상 `newAnchorVerdict`가 동일 조건·동일 문자열을 반환한다. 기존 `tests/cli/test_merge_cli` 스위트(134 OK)와 신규 동등성 매트릭스가 이를 고정한다.
- A2 원자 페어: `git hash-object .github/workflows/admission-check.yml` == `trustedAdmissionWorkflowSha` == `epoch_manifest.productionExecutionPin` (워크플로 blob은 본 슬라이스에서 1회만 변경되며, 마지막 커밋에서 3자 일치를 재확인한다).

## 3. 검증 계획 (착지 전 기계 검증)

1. `nim c --skipParentCfg --skipProjCfg --path:src tools/ci/rotation_pin_anchor_check.nim` — deriver-mold seconds-class 컴파일.
2. `tools/ci/rotation_pin_anchor_check --derived-H <deriver@HEAD> --pin-H config/trusted_writer_set.json --pin-B config/trusted_writer_set.json` → `H2 PASS code=OK`, exit 0.
3. `tests/cli/test_merge_cli` · `tests/ci/test_rotation_pin_anchor_check` 전건 green.
4. `bash tools/ci/git_access_scan.sh` PASS(0 breaker) · `bash tools/ci/validate_workflow_shell.sh` PASS.
5. pre-commit 훅 전체(nim check gate·anti_theater·layer_enforcement·stale_cert·canonical build) PASS.
6. A2 3자 일치 + 클로저 H2 PASS를 **최종 커밋 트리**에서 재확인.

## 4. 범위 밖

- `ROT_ALLOWLIST` 판정 규칙 자체의 개정(예: 새 멤버 자동 승인) — 금지. 본 문서는 **경로 열거**만 한다.
- `NO_CERT`·landing predicate 판정·required check 의미 변경 — 금지.
- 본 회전이 만드는 프리플라이트 게이트의 **운영 활성화**는 별개 세대다: Axiom 착지 → org `.github` callee pin 회전 → ruleset 2개 재핀 → readback. 본 문서는 그 전환의 권한을 부여하지 않는다.
