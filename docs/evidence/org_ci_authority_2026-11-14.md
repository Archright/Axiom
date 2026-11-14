# Organization CI 권위 감사 — Archright/.github & Axiom (2026-11-14)

> **Status**: 관측 증거 기록 (VS-C0). 본 문서는 삭제·통합을 실행하지 않는다 — 권위 그래프만 확정한다.
> **Created**: 2026-11-14
> **Measured at**: 2026-11-14T13:55Z (gh api readback, 재실행 시 값이 달라질 수 있음)
> **Base**: `fe20556` (origin/main)

## 1. Per-output authority

| 산출물·상태 | Authoritative owner | Axiom 소유 여부 |
|---|---|---|
| 파일 버전·이력 | Git | 비소유 (활용) |
| 빌드 진입점 | Nim/Nimble, Lean, Make | 비소유 (계약 준수) |
| 검증 의미론 | Axiom 엔진 (`src/`, `tools/`) | **소유** |
| CI 실행 | GitHub Actions | 비소유 (위임) |
| 아티팩트 보관 | GitHub Artifacts | 비소유 (위임) |
| PR check 표시 | GitHub Checks | 비소유 (위임) |
| 병합 허용·거부 | GitHub Rulesets + merge queue | 비소유 (집행 위임) |
| 신뢰 워크플로 출처 | 조직 ruleset의 SHA 핀 | 비소유 (핀 값만 기록) |

## 2. Axiom main에 강제되는 조직 required workflow (실측)

`GET /repos/Archright/Axiom/rulesets` → active branch ruleset 4건. Axiom 대상은 2건.

| ruleset | required workflow | source repo_id | sha | conditions | bypass |
|---|---|---|---|---|---|
| 25218071 `axiom-admission-gate` | `.github/workflows/admission-gate-v2.yml` | 1182157951 (Archright/.github) | `6b91c6e74ca2f12173118dc902284bfe1836933d` | `refs/heads/main` + repository `Axiom` | `[]` |
| 23943917 `landing-integrity` | `.github/workflows/landing-integrity.yml` | 1182157951 | `6b91c6e74ca2f12173118dc902284bfe1836933d` | `refs/heads/main` + repository `Axiom` | `[]` |

- 두 규칙 모두 `workflows` 규칙 1건뿐이며 `do_not_enforce_on_create=false`다.
- **핀은 자동 추종하지 않는다**: `Archright/.github` main HEAD는 `e677cd2348ca41e64427b4adb7646763b7cd20a7`(2026-11-14 readback)로, 규칙 핀 `6b91c6e7`과 다르다. required workflow는 핀 SHA의 정의로 실행되므로 `.github` main의 후속 커밋(문서·비필수 워크플로 변경)은 Axiom 병합 판정에 영향을 주지 않는다.
- Axiom 저장소 ruleset `main`(27097366)의 required context는 정확히 6개다: `admission-check`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`, `publication-integrity`. merge queue는 `MERGE` / `ALLGREEN` / max_entries_to_build=2 / max_entries_to_merge=1. bypass actor는 0이다.
- `nim-libp2p` 전용 ruleset 2건(27208234, 27205573)은 `repository_name include ["nim-libp2p"]`이며 ref는 `refs/heads/master` / `refs/heads/axiom-admission-probe`다 — **Axiom 범위 밖**.

## 3. 조직 워크플로 인벤토리

`Archright/.github`의 파일은 5개다. Actions API에는 파일이 존재하지 않는 등록 항목(ghost)이 별도로 남아 있다.

| 파일 | triggers | permissions | jobs | total_runs | 판정 |
|---|---|---|---|---|---|
| `admission-gate-v2.yml` (50,775 B) | `pull_request`, `merge_group` | `contents: read` | anchor-resolve, closure-deriver, attest, mint-prepare, mint-publish, gateway, verdict, admission-check | 56 | **AUTHORITY** (필수 workflow) |
| `landing-integrity.yml` (23,709 B) | `pull_request`, `merge_group` | `contents: read`, `pull-requests: read` | trust-surface-codeowners, trusted-writer-set-pairing, merge-admission-sanity | 294 | **AUTHORITY** (필수 workflow) |
| `nim-libp2p-pr-admission.yml` (42,842 B) | `pull_request` | `contents: read` | propositions, verify-a, verify-b, admission-integrity, subject-verdict | 7 | **OUT OF SCOPE** (nim-libp2p 대상) |
| `pin-promotion-gate.yml` (16,272 B) | `pull_request`, `merge_group` | `contents: read`, `pull-requests: read` | pin-promotion-gate | 227 | 독립 PR 게이트 (조직 required 아님) |
| `parse-probe.yml` (1,430 B) | `workflow_dispatch` only | `contents: read` | control-good, h6-probe, current-pin | 2 | **DEAD** (아래 §5) |

**Ghost 등록**: Actions API는 `probe-m-*`, `probe-s1-*`, `probe-t22/25`, `probe-x1/x2`, `zz-resolve-probe` 등 15개 항목을 active로 나열하지만, `contents/.github/workflows/<name>`는 전부 404다. 실행 가능한 파일이 없으며 run은 0이다. 목록 기반 폐기 판정이 파일 실재를 확인해야 하는 이유다.

## 4. 중복·권한 질문 4건 판정

1. **admission-gate-v2 vs nim-libp2p-pr-admission** — 대상 저장소가 다르다(Axiom vs nim-libp2p). 검증 절차를 공유하지 않는다. **중복 아님.**
2. **landing-integrity는 admission의 증거 검사 어댑터인가** — job 집합이 교집합 없이 분리되어 있다(`trust-surface-codeowners`, `trusted-writer-set-pairing`, `merge-admission-sanity`). admission-gate의 callee(`admission-check.yml`)가 실행하는 job과 겹치지 않는다. **독립 권한.**
3. **pin-promotion-gate는 독립 승격 권한인가** — 자체 job 1개, `pull_request` + `merge_group`, 조직 required workflow 아님. `.github` 저장소 자체 PR에서 실행된다. **독립 게이트로 유지.**
4. **parse-probe는 운영 필수인가** — `workflow_dispatch` 전용, 총 run 2건(둘 다 2026-10-12, `probe/s1-*` 브랜치, failure). ruleset 참조 0. **폐기 후보.**

## 5. Axiom 저장소 워크플로 (C1 근거)

- main의 `.github/workflows/*.yml`은 26개다.
- required context 6개를 생산하는 파일은 `admission-check.yml`, `bsec-integrity.yml`, `debt-registry-gate.yml`, `generation-acceptance.yml`, `axiom-operational-slice.yml`, `publication-integrity.yml`이다.
- 총 run 0건이며 소비 경로 5종(`workflow_call`, `workflow_run`, API dispatch, 문서·운영 절차, ruleset 참조)이 모두 0인 파일 3개:
  - `gateway-jobs-measure.yml` (0)
  - `h4-routing-measure.yml` (0)
  - `hardware-falsification-smoke.yml` (0)
- 위 3개는 required producer가 아니므로 삭제해도 6개 context의 producer·의미는 불변이다 (VS-C1).

## 6. 판정

- **통합 불필요**: 동일 책임을 수행하는 중복 워크플로는 확인되지 않았다. admission-gate-v2 내부의 job 분리는 이미 실행 단위 재사용(callee) 구조다. 파일을 하나로 합치면 서로 다른 실패 의미만 결합된다.
- **삭제 후보**: `parse-probe.yml`(조직, VS-C2), Axiom 3종(VS-C1).
- **보존**: `landing-integrity.yml`, `pin-promotion-gate.yml`은 독립 권한이므로 유지한다.
- required workflow 핀 SHA는 `.github` main HEAD와 일치하지 않으며, 이를 같다고 가정하면 관측이 틀린다. 판정 authority는 ruleset의 핀 값이다.

## Non-claims

- 본 문서는 어떤 워크플로도 삭제하지 않는다. 삭제는 VS-C1/C2의 별도 PR에서 수행한다.
- run 수는 2026-11-14 readback이며, 미래의 실행을 예측하지 않는다.
- `nim-libp2p-pr-admission.yml`의 실행 7건은 `.github` 저장소 자체 PR에서 발생한 것이며, nim-libp2p 대상 강제 여부의 증거로 사용하지 않는다.