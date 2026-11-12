# Admission Generation SHA 핀 — 발산(divergence) 시험 기록 (2026-10-15)

> 본 문서는 Slice A(admission generation 불변 승격, `docs/spec/admission-generation.md` SSOT)의 완료 증거 중 런타임 sha 준수를 입증하는 발산 시험의 관측 기록이다. **본 PR 자체의 큐 착지가 시험의 첫 관측 사례가 된다** — 본 PR의 merge_group admission-gate 런이 controller main ≠ H₁ 상태에서도 핀-트리플을 유지하면 통과다.

## 1. 시험 설계 (인식론적 한계의 해소)

- S5(acceptance, PR #841) 시점에는 ruleset `sha`와 `ref`가 동일 커밋(H₁)으로 귀결되어 "플랫폼이 sha를 준수하는가"는 원리상 관측 불가였다(§6, `docs/spec/admission-generation.md`).
- 발산 시험: controller(Archright/.github) main을 **고의로 H₁을 지나게**(advance) 만든 뒤, 다음 admission 실행이 여전히 H₁ 세대를 실행하는지 관측한다. `ref`는 이미 소멸 상태이므로, main 이동 후에도 admission이 정상 dispatch·실행되면 sha-only 해석이 작동한다는 실증이 된다.

## 2. 핀 상태 (S4 완료 시점 readback, 2026-10-15 06:31Z)

| Ruleset | workflow 참조 (readback 원문) |
|---|---|
| 24233738 axiom-admission-gate | `{repository_id: 1182157951, path: .github/workflows/admission-gate.yml, sha: e968b5c0c20b7c63adaad74a235c31392b6ac497}` (ref 소멸) |
| 23943917 landing-integrity | `{repository_id: 1182157951, path: .github/workflows/landing-integrity.yml, sha: e968b5c0c20b7c63adaad74a235c31392b6ac497}` (ref 소멸) |

- 세대 태그: `admission-gen-h0-20261015` → H₀ `abe66968dbcb…`, `admission-gen-h1-20261015` → H₁ `e968b5c0c20b…` (controller remote).
- 회전 차단: dependabot `ignore:` 4핀(PR #218), 회전 대기 PR #214~#217 dependabot 자가 close 실증.

## 3. 발산 마커 착지

- Controller PR **#219** (README 발산 마커) — pin-promotion-gate pass 후 네이티브 MERGE.
- 착지 결과 controller main = **`85af8e05f583babbfa77ef1f6ad7cf4e1aa42049` ≠ H₁** (2026-10-15, 발산 상태 성립).

## 4. S5 acceptance 선행 증거 (PR #841, 핀 직후 main==H₁ 상태)

- 착지: 2026-10-15T07:14:51Z, MERGE commit `a91eb85278f82f4db2ea84a63feb9b75374fb026` (네이티브 merge queue 경유, `gh-readonly-queue/main/pr-841-…`).
- MG admission-gate 런 38695499846 success — `referenced_workflows` = 신뢰 핀-트리플 정확 일치:
  - `admission-check.yml@dc527994c987cad9d7d83f1dc27650d0c15eb63e`
  - `certificate-mint.yml@aa051134359ee37e50bf30bcc58187c58aa6fe3a`
  - `runner-pool-acceptance.yml@ba773d0631b5757525b16d8fd62e220492e98e76`
- MERGE commit check-runs: `admission-check` success (07:14:22Z), `bsec-integrity` success (06:56:42Z), app=github-actions.
- 재트리거 계기: ruleset workflow 참조 변경 후 열린 PR은 required workflow가 자동 재실행되지 않는다(공식 거동) — 빈 커밋 `e5fd51616`으로 재실행 유도, 전 체크 green 후 auto-merge 큐 진입. **비상 창·직접 병합·수동 rearm 미사용** (merge-queue-rearm 런 38697468784는 병합 후 4초 발화한 무해 no-arm 관측).

## 5. 발산 판정 기준 (본 PR)

본 PR의 merge_group admission-gate 런에 대해:

1. `referenced_workflows` 핀-트리플이 §4와 동일(세 불변) → **통과** (sha가 실행을 지배).
2. 잡 지문·동작 이상(런타임이 main `85af8e05f`를 따라간 흔적, 실행 불능, check 미보고) → **실패** → `docs/spec/admission-generation.md` §5 롤백 행렬 적용 (H₀ 복원 또는 조사).

판정 결과는 완료 보고 및 7일 드리프트 가드 기록에 확정 반영한다.

## 6. 잔여 (본 슬라이스 밖)

- 도구체인 원격 fetch 무해시 검증, `vars.CI_RUNNER_MAP`, landing-integrity `ubuntu-latest` — `docs/spec/admission-generation.md` 잔여 가변 표면 위임.
- CAS 실패기록 종단 상태, J4 hermetic 3종, DEBT#474 잔여 7개 다운로드 래퍼, DEBT#473 레지스트리 폐쇄(데이터 mutation 필요) — 후속 슬라이스.
