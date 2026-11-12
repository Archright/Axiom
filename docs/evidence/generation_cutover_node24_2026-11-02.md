# node24 세대 전환 기록 — 2026-11-02 (repo #1189 · org #253 · 양 ruleset 재핀)

> **문서 신분**: 실행 증거(docs/evidence). 본 기록은 admission-gate 실행 세대의 node20→node24 coherent generation 전환(AGENTS.md §2.5)을 착지 순서·기계 관측·readback과 함께 보존한다. 판정 기록이 아니다 — 전환은 이미 수행됐고, 본 문서는 그 관측 사실을 남긴다.

## §1. 전환 개요

- **전환 단위**: ① Axiom PR #1189(action rotation 22파일 + A2 원자 페어, epoch N+8) → ② org Archright/.github PR #253(admission-gate-v2.yml callee 핀 6줄 일괄 회전) → ③ 양 org ruleset 순차 재핀 → ④ 본 기록의 큐 통과(신세대 merge_group 최초 green 관측).
- **세대 일관성**: 부분 회전 없음. org callee 핀 6줄 전부가 동일 Axiom 커밋(`498c5570`)을 지시한다 — 4개 고유 표적(setup-axiom-toolchain·admission-check.yml·certificate-mint.yml·runner-pool-acceptance.yml) 전부가 #1189에서 node24 회전되었기 때문. 일부만 바꾸면 node20/node24 혼합 실행 세대가 된다(§2.5 위반).

## §2. 착지 기록 (기계 관측)

### 2.1 Axiom PR #1189 — node24 generation cutover (repo 세대)

- 병합: **2026-11-02T07:46:00Z**, native GitHub MERGE, merge commit `498c55704552291da926fae6eb34bc5c0c04ec1b`
- 경로: update-branch(base 재동기 `8054c2e4`, head `fa902c00`) → PR 체크 38개 green(필수 5종 포함) → auto-merge 큐 진입 → 배치 head 체크 33개 green → 병합. 병합 전 c24e812a 헤드에서 bsec-integrity·generation-acceptance 체크런이 부재해 큐 등록이 차단됐던 사실과 update-branch로 해소된 경로도 관측 기록으로 남긴다.
- 이전 세대 마지막 착지: PR #1213(main `8c46c4ea`, 구세대 배치) — 재핀 이전 마지막 old-generation 착지.

### 2.2 A2 원자 페어 main 재실측 (관측값이 유권자)

GET ref=`498c55704552291da926fae6eb34bc5c0c04ec1b` (2026-11-02T08:0xZ):

| 항목 | 관측값 |
|---|---|
| `.github/workflows/admission-check.yml` blob | `f0bb8fb5b839770bf8e53639f3c2cb99997447d4` |
| `config/trusted_writer_set.json` :41 `trustedAdmissionWorkflowSha` | `f0bb8fb5b839770bf8e53639f3c2cb99997447d4` (일치) |
| `config/policy/epoch_manifest.json` :25 `productionExecutionPin` | `f0bb8fb5b839770bf8e53639f3c2cb99997447d4` (일치) |
| `config/policy/epoch_manifest.json` :2 `ciEpochId` | `N+8` |
| `config/policy/epoch_manifest.json` :26 `mode` | `ci-migration` |
| `src/gate/slice_catalog.nim` :306 | `SL-19` "third-party action generation cutover (node24 pin rotation)" 신설 |

3-way SHA 동일 성립 — ADR-0022 §5 원자성 충족. 복수 재확인: 로컬 `git ls-tree origin/main` 동일 blob 확인.

### 2.3 org PR #253 — trust-surface 세대 (Archright/.github)

- PR: `ci: rotate admission-gate-v2 callee pins to 498c5570 (node24 generation cutover, Axiom PR #1189 merge commit)`
- 기계 게이트: **pin-promotion-gate (DEBT#473) PASS** — PREPARED(Axiom main epoch 권위 정합) + PINNED(변경 핀 커밋에서 promoted blob 해석) 자동 검증
- 회전 diff: 6줄(핀 전용, 그 외 무변경 검증)
  - `:266` `actions/setup-axiom-toolchain` `f18713934dad`→`498c5570`
  - `:440` `workflows/admission-check.yml` (stage: attest) `f18713934dad`→`498c5570`
  - `:492` `workflows/certificate-mint.yml` (mint-prepare) `d117ae8e2`→`498c5570`
  - `:549` `workflows/certificate-mint.yml` (mint-publish) `d117ae8e2`→`498c5570`
  - `:584` `workflows/runner-pool-acceptance.yml` `f18713934dad`→`498c5570`
  - `:666` `workflows/admission-check.yml` (stage: verdict) `f18713934dad`→`498c5570`
- **인간 게이트 2 (trust-surface 병합 권한)**: 인간 아키텍트(wintrover)가 병합 수행 — MERGED **2026-11-02T08:08:28Z**, merge commit `7eaa9624d128b9f10e9e40d140d5c23367dabdad`. 에이전트는 대행하지 않았다.
- 검증 위임: 핀 유효성은 pin-promotion-gate(플랫폼 게이트)에 위임 — 별도 검증 시스템 재구현 없음.

### 2.4 양 org ruleset 순차 재핀 + readback (§4.3)

PUT은 비원자 — 순차 수행, 각 단위 GET readback으로 확인 후 다음 단위:

| 시각(Z) | ruleset | 작업 | readback |
|---|---|---|---|
| 2026-11-02T08:1x | 25218071 axiom-admission-gate | PUT `workflows[].sha` 0684026f→`7eaa9624` | GET 일치 — admission-gate-v2.yml@`7eaa9624`, enforcement active, repository_id 1182157951 보존 |
| 2026-11-02T08:1x | 23943917 landing-integrity | PUT 동일 | GET 일치 — landing-integrity.yml@`7eaa9624`, enforcement active, repository_id 1182157951 보존 |

양측 일치 후에만 전환 완료로 판정했다(양측 일치 전 완료 선언 금지 계약 준수).

## §3. 운영 전제 확인

- node24 액션(v5+ 런타임) 요구 runner ≥ 2.327.1 — **관측 2.338.2**("Current runner version: '2.338.2'", 2026-11-02 rearm 잡 라이브 로그) 충족.

## §4. 본 문서의 착지 = 신세대 최초 merge_group 관측

재핀 시점에 큐는 비어 있었고 재핀 이전 배치(#1213)가 마지막 구세대 착지였다. 따라서 **본 PR의 merge queue 통과가 org admission-gate-v2.yml@`7eaa9624` → Axiom callee @`498c5570`(node24 세대)에서 필수 체크 5종이 green으로 보고되는 최초 사건**이다. 본 PR이 red면 신세대에 실 결함이 있는 것이므로 착지하지 않는다(fail-closed).

착지 후 readback 기대치:
- 본 문서가 main에 존재(GET 200, blob 동일)
- 양 ruleset `workflows[].sha` = `7eaa9624` 불변(docs-only 착지는 org 표면 무영향)
- org `.github` HEAD = `7eaa9624` 불변

## §5. 범위 외 (명시)

- gateway-jobs-measure.yml·hardware-falsification-smoke.yml의 6핀 보존 — #1189 본문의 Follow-up(surface 정책 CONTROLLED 재등록 → 소량 회전 PR) 대기. 본 전환은 이미 승인된 범위만 수행했다.
- SLO 480초 판정·비용 분해 — Stage 4(신세대 운영 데이터 확보 후) 대상.
