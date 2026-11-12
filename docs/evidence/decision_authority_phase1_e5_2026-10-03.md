# Decision Authority 단일화 1단계 — E5 판정 실행 관측 (2026-10-03)

**계약**: 사용자 승인 계획 v5 §Completion Evidence (E5) · `docs/spec/repository_surface_contract.md` Owner 결정 #18 ·
`docs/spec/execution_accounting_contract.md` (decision algebra SSOT). 본 문서는 관측값만 기록한다 — 선언 없음.

## 착지 기록 (measured)

| PR | 착지 merge 커밋 | 시각 (UTC) | 경로 |
|---|---|---|---|
| #445 policy(surface) v52 — 6경로 FROZEN→CONTROLLED | `cb1fe995353393` | 06:59:01Z | merge queue (merge_group run 37104376590 success) |
| #446 refactor(authority) 1단계 — decision algebra·SL-05·exit 단일화 | `0a7ca6b4e2c23413` | 07:29:53Z | merge queue (merge_group run 37106204075 success) |

## E5(1) — PR candidate 판정 실행 (measured)

`bin/ax merge 446 --dry-run` (B=`cb1fe9953`, H=`4ae169e3d`, AXIOM_MAIN_SHA=동일):

```
[INFO] merge_cli: [dry-run] mergeAborted (TRUST_SURFACE_MODIFIED): trust-surface file modified
(src/cli/merge_cli.nim) — manual merge required
EXIT=0
```

- verdict = TRUST_SURFACE_MODIFIED, dryRunExit = 0 — 계약(`admission-check.yml:832-838`)의
  exit contract: 0 = admission GO **또는** TRUST_SURFACE_MODIFIED(수동머지 경로 개방). 비제로 = NOT-ADMIT 차단.
- 동일 판정 함수가 두 candidate(PR·merge_group)에 적용된다(알고리즘 1, 실행은 candidate별).

## E5(2) — merge_group candidate 판정 실행 (measured)

PR #446 enqueue → `gh-readonly-queue/main/pr-446-cb1fe995353393` 브랜치에서
`event=merge_group` admission-gate run **37106204075 = success** → MERGE `0a7ca6b4e`.
pull_request와 merge_group 모두에서 동일 admission-gate 워크플로우가 발화함을 관측.

## scope 결속 — slice-engine 관측 (measured)

PR #446 CI (run 37105267842) slice-engine step:

```
[slice-engine] epoch=N+7 implemented=["SL-08","SL-01","SL-03","SL-04","SL-12","SL-10","SL-0713"] sl08=fire sl01=fire sl02=NO-FIRE sl03=fire sl05=NO-FIRE
```

- slice-engine은 **B tree(main)의 epoch manifest**를 scope authority로 읽는다 —
  epoch-transaction 4-way 결속(catalog+manifest+engine+pin) 설계대로: SL-05 이관은 구현 커밋과
  **같은 세대로** 착지되며(`epoch_manifest.json` implementedSlices + SL-05 predicate 코드), 착지 이후
  main을 베이스로 하는 PR부터 `sl05=fire`로 predicate가 실행된다.
- 본 기록 이후의 최초 PR(Phase C)이 첫 SL-05 fire 관측점이다.

## 핀 회전 ceremony (measured)

```
productionExecutionPin (config/policy/epoch_manifest.json) = 62d150b8266a9a8b8138b8191fff5a1abdfbf930
trustedAdmissionWorkflowSha (config/trusted_writer_set.json) = 62d150b8266a9a8b8138b8191fff5a1abdfbf930
git hash-object .github/workflows/admission-check.yml       = 62d150b8266a9a8b8138b8191fff5a1abdfbf930
```

콘텐츠 어드레스드 git blob sha 3-way 일치 — `src/gate/slice_catalog.nim:288` 정의대로
workflow와 기록 필드가 원자적으로 회전됨(커밋 dddc3b191).

## 정책 PR 경로 (measured, 결정 #18 감사 추적)

- PR #445는 FROZEN인 `config/repository_surface.json` 자기 수정이므로 계약 문서화 수용 리스크 경로
  `git push --no-verify`(Owner 결정 #1, 결정 #18(c))로만 push 가능 — **본문 PR #446에는
  --no-verify 미사용**(정상 pre-push 게이트 통과).
- CI `repository-surface` check(관측 전용, required 아님 — `repository_surface.yml:1-3`)는 base-policy
  v51 기준 FAIL(SURFACE_FORBIDDEN, 정책 파일 자체 수정) — 설계상 불가피하며 merge authority가 아님.
  merge queue ALLGREEN이 관측 전용 check까지 그룹핑에 요구하지만, enqueue 후 merge_group run이
  green이면 자동 MERGE로 착지된다(#445 실측 — admin bypass 불요).
- 부분 rerun(`rerun-failed-jobs`)은 run-attempt 스코핑 artifact identity
  (`subject-certificate-<run_attempt>`, `certificate-mint.yml:879`)와 양립 불가 — 전체 rerun으로만
  해소(설계 동작, 결함 아님).

## Base-policy 래치 (measured)

```
make check-repository-surface (feat 브랜치, base=cb1fe995=v52):
  verdict: PASS | policyVersion: 52 | changeCount: 33 | violations: []
```

# Addendum — E6 권한 전이 실측 (2026-10-03, 세션 2)

## E6(a-1) — NO_CERT 루트원인 + operator re-attest 경로 (measured, PR #447)

- 최초 admission-check 실패: `NO_CERT` NOT-ADMIT → required check fail 실측.
- 루트원인: mint⇠admission 순환의존(최초 인증 PR 부트스트랩 결함) — mint가
  원장 내 subject를 요구하지만 원장 append 경로가 CI 내부에만 존재.
- 해소: `merge_admission_controller.md:89`가 계약하는 operator re-attest
  (manual-only recovery path):
  1. D9 evidence 조립(`data/certification/evidence-draft.json` @B + funcSource
     바이트 일치 실측 True, policyDigest/scopeDigest는 B 기준)
  2. `bin/ax cert subject-register --base 0a7ca6b4… --head-tree 81913371d2… --pr 447`
     → subjectId `f3d246ed98da…`
  3. `bin/ax cert attest --ref 1a77751d9e… --pr 447` PASS(커널 체인 a–f,
     lean 4.33.0 / z3 4.13.3 로컬 재실행)
  4. `bin/ax cert ledger-append` OK — 원장은 GitHub 호스팅 상태
     (ledger-list가 GITHUB_TOKEN fail-closed 실측), 커밋 불요.
- 로컬 dry-run 재관측: `mergeAborted(NO_CERT)` → `mergeGo(GO)`.
- attempt-4 전체 rerun green → merge queue → MERGED (main=830f34a04).

## E6(b) — strict freshness binding 전환 (measured)

- ruleset 20303214 `strict_required_status_checks_policy` false→true PUT,
  재조회 True 실측. GitHub가 required check를 최신 base에 재결속.

## 신뢰표면 수동 병합 경로 (measured, PR #448)

- 신뢰표면 PR(`src/cli/merge_cli.nim` 수정) dry-run:
  `mergeAborted(TRUST_SURFACE_MODIFIED)` — CLI 자체 병합 거부, 수동 병합 요구
  (merge_admission_controller.md:113 계약 동작).
- CI admission-check는 GO와 TRUST_SURFACE_MODIFIED 모두 exit 0
  (`admission-check.yml:833` — 정책이 신뢰표면 변경을 수동 경로로 라우팅).
- MUST-T2 수동 절차 `gh pr merge 448 --merge` → merge queue 전달 실측.
- 원장 선민팅(ceremony-before-check): subject-register/attest/ledger-append를
  check 실행 전 완료 → mint-publish 1차 시도 통과(#447의 4-attempt 대비).

## E6(a-2) — STALE_BASE 신선도 결속 실측 (measured, PR #449 차량)

- #448 착지로 main 이동(830f34a04→66c34a260) 후, 이동 전 base로 green이었던
  #449의 판정 재평가:
  `mergeAborted(STALE_BASE)` — "candidate verified against base 830f34a04d73,
  but current main is 66c34a260b9e — freshness binding requires the current tip"
  (로컬 dry-run 실측, `AXIOM_MAIN_SHA=$(git rev-parse origin/main)`).
- strict_required_status_checks_policy=true(E6(b))와 결합해 GitHub가 base 이동 시
  required check를 재평가 → 신선도 결속이 실제 병합 집행에 강제됨.
- 부수 관측: INV-13 — 동일 head에 원장 인증서 2건(연산자 어펜드 09:33:42Z +
  CI admission-check 레인 어펜드 09:37:47Z). 판정기는 최신 createdAt을 canonical로
  채택하는 결정론 해소로 계속 진행. 후속: 인증 어펜드 단일 writer 정리.
