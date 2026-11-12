# CI Epoch Record — Dependabot 무인 병합 슬라이스 (2026-10-22)

> **권위**: Reporter only. 본 문서는 GitHub merge authority(ruleset·required checks·merge queue·MERGE commit)를 대체하지 않는다(AGENTS.md §2.3). 본 문서는 `docs/agents/ci_epoch_cutover.md`(AGENTS.md §2.5)의 10단계 절차 중 이 슬라이스가 수행한 단계의 기록이다.

## 변경 내용 (coherent generation 단위)

| 단계 | 내용 |
|---|---|
| Stage 1 (policy) | PR #1045 — `config/repository_surface.json` v84→v86 중 v86: `.github/dependabot.yml`·`.github/workflows/dependabot-auto-merge.yml` CONTROLLED 재등록(FROZEN glob 흡수 차단) |
| Stage 2 (본문, 본 PR) | `dependabot.yml` exclude-paths 스코핑 + `dependabot-auto-merge.yml` armer 신규 + 본 기록 |

## 10단계 수행 기록

1. **Freeze**: 사전 main = `e610d94ed`(PR #1044 merge, 2026-10-22). 본 기록이 immutable reference다(merge SHA는 불변).
2. **Record**: freeze 시점 required checks 5종(실측 ruleset 20303214: admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice) + merge queue(MERGE/ALLGREEN/1:1, check_response_timeout 120분). **무변경 확인이 완료 조건이다.**
3. **Tombstone**: 해당 없음 — 순수 추가(additive) 슬라이스. 폐기되는 CI 구현 없음.
4. **New Epoch**: v86 CONTROLLED 재등록 + 본문(위 표). trustSurface·required checks·캐시 키와 무관한 추가 경로.
5. **Atomic Binding**: Stage 1(policy) + Stage 2(본문)가 하나의 논리적 cutover 단위(선례 v27/v30/v73~v85 2단계 choreography). `ciGeneration`은 캐시 키·reuse record·verdict identity에 결속되지 않는다(위반 금지 — verification_dag_contract §3·§12).
6. **Local/Targeted Verification**: Stage 1 — push-admissibility 14 게이트 중 13종 PASS, `check-repository-surface`만 자기승인 차단 FAIL(v51 knownBlindSpots 문서화 경로, v83 telemetry FAIL 선례와 동일) → 소유자 수용-리스크 push(`--no-verify`, Owner 결정 #1). Stage 2 — 전 게이트 PASS 예상(두 경로가 base v86에서 CONTROLLED).
7. **Short Validation**: PR #1045가 auto-merge arm(2026-10-22T15:11:32Z, enabledBy=wintrover) → PR-head checks green → **자동 merge-queue 진입** → native MERGE `4ed1ac2cc`(15:33:13Z). 이 저장소 최초의 auto-merge×merge-queue 실증(이전 60 병합 PR 중 autoMergeRequest 0건). arm→merge 22분, 사람 행위 0회.
8. **Canonical Cutover**: 본 PR 착지로 armer가 canonical 경로에 편입. required-check identity·trust semantics 무변경(신규 워크플로는 required도 trustSurface도 아님 — 정책 SSOT·ruleset 무수정).
9. **Production Acceptance (예정)**: 최초의 자동화 가능 클래스 Dependabot PR이 사람 행위 0회로 병합되는 관측. 판정 기준: (a) `autoMergeRequest.enabledBy`가 dependabot-arm 경유(사람 아님), (b) GraphQL timeline에서 User actor 행위 0회, (c) native MERGE, (d) no-masking(venue_red 비증가·class migration 없음). 기준 사실: #910 = pre_enqueue_gap 41,144s·사람 수동 병합.
10. **Rollback**: 본 PR revert → PR #1045 revert → `gh secret delete DEPENDABOT_ARM_TOKEN`. 자동화 즉시 소멸(검증 강도는 전 단계 무변경이므로 롤백에 검증 영향 0).

## 운영 전제 (소유자 행위 의존 — 유일)

`DEPENDABOT_ARM_TOKEN` 시크릿: **fine-grained PAT**(repository access = Archright/Axiom 전용, permissions = Pull requests: Read and write, Contents: Read-only). 이유: GITHUB_TOKEN은 merge-queue 브랜치에서 auto-merge 활성화 불가(공식 문서 + rearm 실측 0/16). 기존 자격 증명 부적합 실측: DIAG App=읽기전용 계약(monitor purity), RELEASE_AUTHORITY App=과권한+환경 보호(required_reviewers). 시크릿 미설정 시 armer는 가시적 FAIL(exit 1)로 보고한다(삼킴 없음).

## 잔여 (기록 전용)

- exclude-paths가 github-actions ecosystem에서 파일 단위로 동작하지 않을 경우: armer의 trust-surface 교차 방어가 2차선으로 무인 병합을 차단한다. 다음 weekly run에서 trustSurface 클래스 PR 재제안 여부 관측 후 설계 보정(사실 보고).
- policy SSOT drift(live ruleset 5종 vs merge_admission.json v1.16.1 4종 — `axiom-operational-slice` 1건)은 본 슬라이스 범위 밖 후속 보고.
- major 업데이트·trust-surface 클래스는 의도적으로 수동 경로 유지(MUST-T2).
