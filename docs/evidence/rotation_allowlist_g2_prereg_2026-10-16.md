# G2 승격 핀 회전 사전등록 — admission-check.yml blob + TWS/manifest 핀 원자 동반 (2026-10-16)

> **종류**: 사전등록 문서 (rotation pre-registration) — G2 GO-critical 2-lane job-matrix 승격 PR의 핀 회전 경로를 착지 이전에 고정한다. 형식 계보: `docs/evidence/rotation_allowlist_a5_prereg_2026-10-14.md` (A4/A5 규율 — 열거형, glob 금지).
> **등록일**: 2026-10-16 (착지 이전 고정 — no-peeking).
> **패턴**: #830-pattern 원자 세레머니 — `.github/workflows/admission-check.yml` blob 변경과 그 blob을 결속하는 양 핀(`trustedAdmissionWorkflowSha` + `productionExecutionPin`)이 **같은 커밋**에서 회전한다. PR은 자기 미래 핀 값을 스스로 운반하므로 ROT_NEW_PIN은 발동하지 않는다(§2).
> **고정성**: 본 문서가 착지하는 순간 §1의 열거는 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 회전 경로 열거 (3경로 + 동반 문서)

승격 PR이 변경하는 경로의 전체 집합:

1. `.github/workflows/admission-check.yml` — 직렬 GO 스텝 → 2-lane `go-critical-lane` job matrix 승격 (회전 **대상 blob**; 신규 blob sha `f2ad3b03b357fdf30976d4e2cbaf6b0927de8830`, 구 blob `b2b8235d79d17ec158f4d5429691ceef65575f67`).
2. `config/trusted_writer_set.json` — `trustedAdmissionWorkflowSha` → 신규 blob sha (검증: `tools/ci/verify_trusted_writer_set.sh` HEAD blob 등식 — 같은 커밋에서만 성립).
3. `config/policy/epoch_manifest.json` — `productionExecutionPin` → 동일 신규 blob sha (epoch gate `tools/ci/epoch_transaction_gate.nim`의 `productionExecutionPin != trustedAdmissionWorkflowSha` fail-closed 등식).
4. `docs/evidence/go_matrix_s1_validation_2026-10-16.md` — S1 수용 기록 (동반 문서, 판정 권위 없음).
5. `docs/evidence/rotation_allowlist_g2_prereg_2026-10-16.md` — 본 문서 (동반 문서, 판정 권위 없음).

## 2. 회전 판정 분석 (결정론)

- **분류 예상: rqNormal** — 본 PR의 candidate delta는 체커 클로저 멤버(`config/trusted_writer_set.json` `trustedCheckerTreeClosure` — 876경로, 전부 src/tools/tests/ci/config.nims 계열)를 **일절 변경하지 않는다** → `derived(M) == derived(B)` → closureChange=false → ① allowlist는 NORMAL 하에서 vacuous-true (ADR-0025 A2 (ii)).
- **④ pin anchor (ROT_NEW_PIN)** — `line-set(pin@H) == set(derived H)`: TWS@H의 클로저 라인 집합은 불변이고 derived(H)==derived(B)이므로 등식 유지 — "PR이 자기 미래 핀을 운반해도 ROT_NEW_PIN이 발동하지 않는" 이유는, 회전되는 필드(`trustedAdmissionWorkflowSha`)가 클로저 라인 집합의 구성원이 아니기 때문이다. 원자성 요구는 ROT 사다리가 아니라 `verify_trusted_writer_set.sh`의 HEAD-blob 등식과 epoch gate의 핀 등식에서 나온다.
- **방어적 열거**: 만약 (예상 외로) ROTATION으로 분류될 경우를 대비한 등식성 확인 — 경로 1은 `RotationAllowlistExtra` 멤버(`src/cli/merge_cli.nim`), 경로 2는 `RotationPinBPath`(핀 파일 자체 — 무조건 허용), 경로 3은 `RotationAllowlistExtra` 멤버(2026-10-10 확장)다. 경로 4·5는 allowlist 밖의 신규 문서로, ROTATION 분류 시 ROT_ALLOWLIST(rqNone)가 정확한 동작이다 — 본 PR은 NORMAL이므로 착지 가능하다. 분류가 ROTATION으로 관측되면 승격을 중단하고 원인을 규명한다(예상과 다른 관측 = 진행 금지).
- **trust-surface**: 경로 1·2는 `config/policy/merge_admission.json` `trustSurface` 멤버 → 판정은 TRUST_SURFACE_MODIFIED(dryRunExit 0 — 수동 병합 경로 표식)가 예상되며, 전례 PR #856(2026-10-15)과 동일 클래스로 큐 착지가 검증되어 있다. 승격 세레머니는 소유자 승인(G2 계획, 2026-10-16) 하에 진행한다.

## 3. 승인 = 착지

본 사전등록의 승인은 G2 승격 PR의 착지 그 자체다(AGENTS.md §0.10 결정 바인딩). 착지 이후 §1 열거 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

*핀 회전은 언제나 blob↔선언의 동일 커밋 원자성으로만 허용된다. 본 문서는 그 전환의 등록 전표다.*
