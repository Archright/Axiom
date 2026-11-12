# Artifact upload-site inventory (G1) — 2026-10-10

> **성격**: G1 완료 기준의 기계 판독 목록 — `.github/workflows/`의 모든 `actions/upload-artifact` site의 산출물 대장. 기계 판독 본체는 **`artifact_upload_inventory_2026-10-10.json`**이며, 이 문서는 그 서사 동반물이다(기록 관례 선례: `docs/evidence/ci_structural_duplicate_census_2026-09-30.md` + `.json`).
> **측정 기준 (measured base)**: 워크플로 YAML = **PR #710 적용 후 트리** — 브랜치 `feat/storage-retention-policy` @ `cbaed951f`(workflow YAML 내용 = `4554c48f3`). 단, **PR #710은 본 기록 작성 시점(2026-10-11 조회)에 OPEN·미병합**이며 `origin/main`은 `0f57b44a9`다. 두 트리에서 워크플로 파일이 다른 것은 `admission-check.yml`과 `runner-pool-acceptance.yml`뿐이다: main에는 ① 4 hot-path site에 `retention-days`가 **없음**(암묵적 90일 기본 상속) ② admission-check.yml에 7번째 upload site(J3 test-mode nimcache 재-업로드, 커밋 `e0553280b`/`af3cfa2e7`)가 있다. 관측(retention 실측)은 GitHub REST(`repos/Archright/Axiom/actions/artifacts`, 2026-10-11, 총 7,135건 live sample)로 수행했다.
> **범위**: 22 site — `admission-check.yml` ×6, `certificate-mint.yml` ×1, `gateway-jobs-measure.yml` ×1, `probe-merge-queue.yml` ×1, `h4-routing-measure.yml` ×3, `runner-pool-acceptance.yml` ×9, `observation.yml` ×1.

## 과제 brief 대비 발견 차이 (divergence)

과제 brief의 센서스는 20 site(`admission-check.yml` ×5, `observation.yml` 미포함)였으나 실측 YAML은 22 site다: `admission-check.yml`은 양 트리 모두 **6개** upload step을 가진다(`evidence-record-*`:1526, `judgment-record-*`:1542, `admission-verdict-*`:2024, witness `admission-check-<H>-<attempt>`:2042 — venue-split evidence 표면, `epoch_record_storage_retention_2026-10-10.md` §11 follow-up 1(b) 참조), 그리고 `observation.yml:149`가 22번째 site다. "실제 YAML을 읽는다"는 지시가 분석 기준이므로 site를 줄여 brief에 맞추지 않고 전수를 기록했다.

## 요약

| 구분 | 값 |
|---|---|
| 4 hot-path site (PR #710, `retention-days: 3`) | `admission-check.yml:509-545`(base-artifacts), `admission-check.yml:582-589`(base-nimcache), `runner-pool-acceptance.yml:665-681`(ci-bootstrap-artifacts), `runner-pool-acceptance.yml:769-773`(candidate-arm64) |
| hot-path의 관측 retention | 전부 **90일**(전-컷오버 샘플 — PR #710 미병합으로 라이브 런은 main YAML을 실행; post-cutover 샘플 4/4/6/0건 모두 90일) → **요청 3일의 라이브 관측 샘플 0건** (JSON 각 site의 `observed_retention_days.note`) |
| 이미 `overwrite: true`를 가진 site | `admission-check.yml:543`, `:589` (가속 2곳 — `docs/spec/github_artifact_attempt_quirks.md:33-36`의 정책 형태) |
| `overwrite` 결여 + 재실행 충돌 class | `runner-pool-acceptance.yml:669`(ci-bootstrap-artifacts, fail-open 소비자), `:772`(candidate-arm64, fail-closed 소비자) — **DEBT-CI#003** |
| 만료 실패 모드 집계 | fail-closed 13 / fail-open 3 (base-nimcache, ci-bootstrap-artifacts, merge-group-payload — publisher의 base-seed 소비는 skip이지 red가 아님) / in-repo 소비자 없음 6 |
| 분류 | evidence-chain 13 / acceleration 2 / measure 6 / probe 1 |

## 관측 방법과 한계

- `requested_retention_days` = post-#710 YAML의 각 upload step 값; `origin/main` 값은 별도 필드(main에서는 ①②④ 사이트가 암묵 90일).
- `expected_retention_days` = 전역 기본(90일, `epoch_record_storage_retention_2026-10-10.md` §4 — `github.retention_days`가 해석되는 값, AXIOM_ARTIFACT_RECORD v1 `expected_retention_days` 정의 §3.2).
- `observed_retention_days` = REST census(`expires_at − created_at`, 이름 패턴 그룹화). **GitHub은 만료 artifact를 API에서 숨기므로 빈 히스토그램 = "live 샘플 없음" = `unknown`이지 0이 아니다**(`epoch_record_storage_retention_2026-10-10.md` §3.2 기록된 동일 플랫폼 한계). `executed-ci-bootstrap`, `executed-shard-<N>`, `gateway-empty-scope-na`, `gateway-jobs-junit-*`, `exp-h4-*` 5군은 창 내 live 샘플이 없어 `unknown`이다.
- publisher 실행 수(7일 창 2026-10-04..2026-10-10, 698건)는 `gh api …/workflows/ci-cache-publisher.yml/runs?created=…` `total_count`(2026-10-11 조회)다 — `docs/audit/ci_semantic_reduction_audit_2026-09-27.md` 부록 supersession note의 측정과 동일 소스.
