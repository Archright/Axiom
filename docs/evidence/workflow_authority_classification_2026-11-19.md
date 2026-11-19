# Workflow authority classification — `axiom-operational-slice.yml` (2026-11-19)

> **Status**: 권위 분류 동결. 본 문서는 **문서만** 추가한다 — 워크플로·정책·소스 변경 없음.
> **Created**: 2026-11-19
> **Measured at**: 2026-11-19T08:18Z (UTC). `gh` 2.102.0.
> **Base**: `7b1c0c35351be04416066fbdf35a1f517de4151e` (origin/main)
> **동반 문서**: `docs/evidence/github_free_parity_2026-11-19.md` (같은 시점의 ruleset·run 실측)

## §0. 분류 결론

| 질문 | 판정 | 근거 |
|---|---|---|
| required-context producer인가? | **예** | ruleset `27097366`의 `axiom-operational-slice` @ `15368`; merge_group run `44481530942`의 동명 job `success` (§1) |
| 실패가 병합을 막는가? | **예** (NO-GO/UNKNOWN 경로) | `readiness_start_gate.nim:531-546`의 `quit(1)` + job 배선 (§2) |
| trust writer인가? | **아니오** | `contents: read`만, 시크릿 0, repo ref/원장/CAS 쓰기 0 (§3) |
| 조치 | **KEEP** — trust surface 유지 | 제거하면 PR이 자기 merge gate를 수정한 채 착지할 수 있다 (§4) |

`axiom-operational-slice`는 **병합 게이트의 일부이면서 신뢰 쓰기 권한은 없는** 워크플로다. 두 속성은 배타적이지 않다: 판정(차단)은 하되, 저장소 상태는 쓰지 않는다.

## §1. required-context producer (live 실측)

### §1.1 ruleset 선언

`GET repos/Archright/Axiom/rulesets/27097366`의 `required_status_checks` 7개 중 하나:

```json
{ "context": "axiom-operational-slice", "integration_id": 15368 }
```

`15368`은 GitHub Actions 앱이다(`app_slug: github-actions`; 같은 응답의 다른 6개 context도 동일 앱, `admission-check`만 `5795152`).

### §1.2 merge_group run에서의 생산

run `44481530942`(event `merge_group`, head `7b1c0c35351be04416066fbdf35a1f517de4151e`, path `.github/workflows/axiom-operational-slice.yml`, conclusion `success`)의 job은 두 개다:

| job | conclusion | started_at | completed_at |
|---|---|---|---|
| `axiom-operational-slice` | `success` | `2026-11-19T07:41:19Z` | `2026-11-19T07:44:00Z` |
| `readiness-verdict` | `success` | `2026-11-19T07:44:02Z` | `2026-11-19T07:48:15Z` |

즉 같은 워크플로 파일이 merge_group에서 **두 개의 required context**(`axiom-operational-slice`, `readiness-verdict`)를 동시에 생산한다.

**경계 명시**: 이 job들은 `admission-gate` run `44481531363`에 속하지 않는다 — 그 run의 26개 job에는 `axiom-operational-slice`가 0건이다. 두 run은 같은 큐 커밋에서 병렬로 발화한 별개 run이다.

### §1.3 merge commit의 check-run

`GET repos/Archright/Axiom/commits/7b1c0c3…/check-runs` (총 49건) 중:

| check-run id | name | `app.id` | conclusion | details_url |
|---|---|---|---|---|
| `135414658942` | `axiom-operational-slice` | `15368` | `success` | `…/actions/runs/44481530942/job/135414658942` |

### §1.4 정책 mirror

- `config/policy/merge_admission.json:33-41` — `requiredValidations`의 `axiom-operational-slice` 항목(`workflowPath .github/workflows/axiom-operational-slice.yml`, `job axiom-operational-slice`, `acceptableConclusion success`, `workflowIdObservation {value: 414023971, observedAt: 2026-11-11T01:01:50Z}`).
- `config/policy/merge_admission.json:95` — `trustSurface`에 같은 경로가 등재되어 있다.
- 워크플로 자신의 트리거: `.github/workflows/axiom-operational-slice.yml:14-20` — `pull_request`, `merge_group`, `push: branches: [main]`, `workflow_dispatch`. **경로 필터가 없다** → 모든 PR과 모든 merge_group에서 실행된다.

## §2. 실패가 병합을 막는 경로

### §2.1 판정 → exit

`src/gate/runners/readiness_start_gate.nim:531-546`:

```nim
531	  case res.verdict
532	  of "NO-GO":
533	    logError("readiness_start_gate",
534	             "readiness verdict NO-GO — contract blockers present; gate FAILS.")
535	    quit(1)
536	  of "CONDITIONAL GO":
537	    for c in res.conditions:
538	      logWarn("readiness_start_gate", "CONDITION: " & c)
539	    logWarn("readiness_start_gate",
540	            "verdict CONDITIONAL GO — conditions above are attached to the GO; not silent.")
541	  of "GO":
542	    logInfo("readiness_start_gate", "verdict GO — all invariants PASS.")
543	  else:
544	    logError("readiness_start_gate",
545	             "unexpected verdict '" & res.verdict & "' — fail-closed.")
546	    quit(1)
```

- `NO-GO` → `quit(1)` (`:532-535`)
- 표 밖 verdict(UNKNOWN) → `quit(1)` (`:543-546`)
- `GO` → exit 0 (`:541-542`)
- **`CONDITIONAL GO` → exit 0** (`:536-540`). 조건은 warning으로만 부착된다 — 이 verdict는 병합을 막지 않는다. "실패가 병합을 막는다"는 주장은 **NO-GO/UNKNOWN 경로에 한정**된다.

### §2.2 job 배선

`.github/workflows/axiom-operational-slice.yml`:

- `:303-305` — `readiness-verdict` job은 `needs: [axiom-operational-slice]`, `if: ${{ !cancelled() }}`.
- `:470-484` — 게이트 실행 스텝:

```yaml
470	      - name: "Run the readiness gate (verdict → exit)"
479	        run: |
480	          set -euo pipefail
481	          AXIOM_HERMETIC_BUILDING=1 nim c ... -o:bin/readiness_start_gate src/gate/runners/readiness_start_gate.nim
482	          AXIOM_CI=1 ... \
484	            ./bin/readiness_start_gate
```

`set -euo pipefail`이므로 게이트의 비-0 exit은 스텝을 실패시키고, 스텝 실패는 job 실패가 되며, job id가 곧 check-run context다(`:289-291`: "The job id IS the check-run context — no job-level `name:` key"). 워크플로 주석도 같은 계약을 명시한다(`:473-478`: "The gate's exit code IS this job's verdict — no post-processing").

- `:6-9` — "It must NEVER be conditionally skipped: a skipped required check reports success — so no job-level or step-level `if:` may gate it." 이는 required check를 skip으로 통과시키는 플랫폼 함정에 대한 방어다.
- `:285-298` — `readiness-verdict` job도 같은 규칙을 따른다(유일한 job-level `if:`가 `!cancelled()`, 스텝 조건은 업로드의 `always()`뿐).

### §2.3 producer job 자체의 실패 경로

`axiom-operational-slice` job의 핵심 스텝은 `make verify-contract-release-e2e-full`(`:142-143`)이며, 그 비-0 exit은 스텝 실패 → job 실패 → required context 실패다. 워크플로 헤더가 이 실행의 의미를 규정한다(`:3-5`: "runs the REAL `ax prove` and replays the SAME certificate through the Lean kernel").

### §2.4 관측 범위의 정직한 한계

run `44481530942`에서 `axiom-operational-slice`와 `readiness-verdict`는 **둘 다 success**였다. 따라서 본 관측은 "실패 시 차단"을 **경로 인용**(§2.1-§2.3)으로 확립하며, 실패 실행을 재현한 것은 아니다.

기록된 선례(재측정 아님): `config/policy/merge_admission.json:4`의 v1.17.0 절은 이 check의 negative control을 기록한다 — "negative control PR #1041: check FAILURE + isRequired=true + mergeStateStatus=BLOCKED, closed without merge".

## §3. trust writer가 아니다

| 검사 | 결과 | 명령/위치 |
|---|---|---|
| 상위 `permissions` | `contents: read` 단일 | `.github/workflows/axiom-operational-slice.yml:22-23` |
| `readiness-verdict` job 권한 | `contents: read` | 동일 파일 `:308-309` |
| 시크릿 참조 | **0건** | `grep -c "secrets\." .github/workflows/axiom-operational-slice.yml` → `0` |
| repo ref 쓰기 | 0건 | `grep -n "git push\|refs/heads\|axiom/certificates\|axiom/evidence-cas\|contents: write"` → 무매치 |
| 원장/CAS 쓰기 | 0건 | `grep -n "ledger\|CAS"` → 무매치 |
| 산출물 | `actions/upload-artifact` 3회(아티팩트만) | `:254`, `:273`, `:521` |
| `admission-check` producer 여부 | **아니다** — ruleset상 `admission-check`는 `5795152`, 이 check는 `15368` | §1.1 |

플랫폼 기본값도 같은 방향이다(실측):

```console
$ gh api repos/Archright/Axiom/actions/permissions/workflow
{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}
$ gh api repos/Archright/Axiom/actions/secrets | jq .total_count    # 0
$ gh api orgs/Archright/actions/secrets | jq .total_count           # 0
```

즉 이 워크플로는 **판정하고 차단할 뿐**, 저장소·원장·trust manifest에 아무것도 쓰지 않는다. "required check"라는 속성과 "trust writer"라는 속성은 서로 다른 축이다.

## §4. 왜 KEEP인가 — 제거하면 무엇이 깨지는가

### §4.1 trust surface가 막는 것

`config/policy/trust_surface_manifest.json:3`:

> "Execution surface that must be byte-identical between a merge-group commit G and its base B_mg. A PR that alters any listed path cannot receive the independent verifier's admission-check; such changes require the audited break-glass lane and an explicit epoch rotation."

`:10`에 `.github/workflows/axiom-operational-slice.yml`이 등재되어 있다. 비교는 blob 기반이며 `readFrom`은 **B_mg**(`:4-5`)다.

### §4.2 제거 시나리오

merge_group run은 **큐 커밋 G의 바이트**로 워크플로를 실행한다(G는 PR 변경을 포함한다). 그러나 trust surface manifest는 **B_mg에서** 읽힌다(`config/policy/trust_surface_manifest.json:5` — `readFrom: "B_mg (merge_group.base_sha), never from G"`). 두 사실이 순서를 결정한다:

1. 항목 제거를 시도하는 PR **자신**은 B_mg의 manifest로 판정되므로, 그 PR에서는 보호가 그대로 작동한다(같은 PR에서 제거와 약화를 함께 할 수 없다).
2. 제거가 승인되어 착지한 뒤, **다음 PR부터** B_mg의 manifest에 이 경로가 없으므로 App은 blob 비교를 하지 않는다.
3. 그 상태에서 PR이 job id(`axiom-operational-slice`, `readiness-verdict`)를 유지한 채 게이트 호출을 약화(예: 게이트 실행 스텝을 `exit 0`으로 치환)하면, 약화된 워크플로가 자기 큐 커밋에서 실행되어 required context를 green으로 만든다.

즉 문제는 삭제 그 자체보다 **삭제 이후의 영구 무보호**다. 제거는 정책 파일 변경이므로 그 PR도 break-glass/rotation 레인을 통과해야 하고(`trust_surface_manifest.json:20`이 자기 자신을, `config/policy/merge_admission.json:84`가 정책 파일 자신을 등재), 통과한 뒤에는 후속 PR 전부가 보호를 잃는다. 그 상태를 만들 이유가 없다는 것이 KEEP의 근거다.

이것이 "PR이 자기 merge gate를 수정한다"는 자기참조 문제다. 판정 로직·입력(`tools/readiness_evaluator.nim`, `src/gate/runners/readiness_start_gate.nim`, `config/readiness_policy.json`, `tools/ci/readiness_collect_ci.nim`)은 이미 `config/policy/merge_admission.json:112-115`에 등재되어 있지만, **워크플로 본문 자체**는 `trust_surface_manifest.json:10`이 담당한다. 두 등재는 서로를 대체하지 않는다.

### §4.3 두 번째 층 — FROZEN

`config/repository_surface.json`:

- `:309-322` `FROZEN` 목록, `:316`에 `".github/**"`.
- `:336-340` `FROZEN` 규칙: `ADD: FAIL`, `MODIFY: FAIL`, `DELETE: FAIL`.
- `:355` 판정은 **BASE 정책**(merge-base with main)으로 수행된다 — PR이 정책을 함께 바꿔 자기 변경을 승인할 수 없다.

따라서 워크플로 파일의 추가·수정·삭제는 표면 게이트에서도 거부된다. trust surface 등재는 이와 **독립적인 두 번째 층**이며, 하나를 제거하면 나머지 하나만 남는다.

### §4.4 결론

`axiom-operational-slice`는 **KEEP**한다. 제거는 문서 편집이 아니라 정책 변경이며, 본 문서의 범위 밖이다. 본 문서는 제거를 제안하지 않는다.

## §5. 알려진 blind spot — 동명 context spoof (코드 변경 없음)

required context는 플랫폼에서 **이름 + `integration_id`**로 매칭된다. `axiom-operational-slice`의 `integration_id`는 `15368`(GitHub Actions)이며, 이 앱은 저장소의 모든 Actions check-run이 공유한다. 따라서 **같은 이름의 job을 가진 워크플로**가 같은 앱으로 check-run을 내면 이름이 충돌한다.

이 잔여면은 정책 문서가 이미 인정한다:

- `config/policy/merge_admission.json:4` (v1.12.0 절): "a PR-side workflow with the same job name is not blocked by the platform".
- 같은 줄 (v1.15.0 절): Axiom-side identity mirror는 "a RECORDED binding for judgment reference, NOT a merge-time re-verification".

오늘 이 blind spot을 막는 것은 **App 수준 context binding이 아니라** 다음 두 층이다:

1. `config/repository_surface.json:316`의 `FROZEN .github/**` — 새 워크플로 파일 ADD가 FAIL.
2. `config/policy/trust_surface_manifest.json:10`의 trust surface 등재 — 기존 파일 MODIFY가 App 판정에서 거부.

즉 **정책·표면 층의 방어**이며, 플랫폼이 앱 단위로 context를 결속해 주는 것이 아니다. `admission-check`가 App `5795152`로 분리된 것과 달리, 나머지 6개 context는 이 잔여면을 공유한다.

**본 PR에서는 코드 변경을 하지 않는다.** 이 항목은 blind spot 기록이며, 해소(예: context별 App 분리)는 별도 결정·별도 PR의 범위다.

## §6. 검증 명령

```console
gh api repos/Archright/Axiom/rulesets/27097366
gh api repos/Archright/Axiom/actions/runs/44481530942/jobs
gh api repos/Archright/Axiom/actions/runs/44481531363/jobs
gh api "repos/Archright/Axiom/commits/7b1c0c35351be04416066fbdf35a1f517de4151e/check-runs?per_page=100"
gh api repos/Archright/Axiom/actions/permissions/workflow
gh api repos/Archright/Axiom/actions/secrets
gh api orgs/Archright/actions/secrets
grep -c "secrets\." .github/workflows/axiom-operational-slice.yml
grep -n "git push\|refs/heads\|axiom/certificates\|axiom/evidence-cas\|contents: write" .github/workflows/axiom-operational-slice.yml
grep -n "ledger\|CAS" .github/workflows/axiom-operational-slice.yml
```