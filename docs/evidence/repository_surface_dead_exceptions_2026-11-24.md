# Repository Surface 죽은 예외 실측 — 존재하지 않는 5경로 (2026-11-24 UTC)

- **성격**: 관측 기록. 정책·config 파일을 **수정하지 않는다**. 판정도 내리지 않는다 — 처분(disposition) 후보만 기록한다.
- **관측 시각**: `2026-11-24T05:38Z` – `2026-11-24T05:49Z` (UTC)
- **관측 대상**: 라이브 default branch `Archright/Axiom` `main` = `c07b8354b6af6db666c99f9480856ab37b9ed6c4`
- **정책 기준**: `config/repository_surface.json` `policyVersion 108` (blob `7643eebb1e4f7b33e5529cce65a3a0b06f687514`)
- **기록자 ≠ 승인자**: 작성자는 에이전트이며, 처분 결정 권한은 인간 아키텍트에게 있다.

## §0. 결론

`frozenExceptions.paths` 116건 중 **5건**이 라이브 `main`에 존재하지 않는다. 5건은 **두 개의 서로 다른 현상**이며, 하나로 취급하면 처분을 틀린다.

| # | 현상 | 경로 | 근거 |
|---|---|---|---|
| 1 | **의도된 은퇴 후 잔여물** | `gateway-jobs-measure.yml`·`h4-routing-measure.yml`·`hardware-falsification-smoke.yml` | 삭제 커밋 `6f875c45`이 "the policy file is left untouched"라고 명시 |
| 2 | **본문 PR 미착지** | `trust-surface-pin-notice.yml` | v87 정책 등재(2026-10-23)만 있고 본문 커밋 0건 |
| 3 | **이중 historical 등재 불일치** | `src/gate/orchestrator.nim` | DEBT#476이 이미 `historicalFiles`에 기록(`DELETED 2026-10-04`), 정책 예외는 이를 반영하지 않음 |

핵심 발견은 "죽은 예외는 무해하다"가 **아니라는** 점이다. §5에서 실측으로 보이듯, 죽은 예외는 여전히 **유효한 CONTROLLED 사전 승인**이며, FROZEN glob이 기본거부하는 경로의 **재도입을 PASS시킨다**.

## §1. 경로별 관측 행

다섯 행 모두 `lookup_result = NOT_FOUND (HTTP 404)`. `observed_at`은 각 호출 시각이며 §2의 명령이 그대로 재현한다.

| path | observed_main_sha | observed_at | lookup_result | exception_group | disposition |
|---|---|---|---|---|---|
| `.github/workflows/gateway-jobs-measure.yml` | `c07b8354b6af6db666c99f9480856ab37b9ed6c4` | `2026-11-24T05:48:52Z` | `NOT_FOUND (HTTP 404)` | `ci-infra` | `RETIRE_RESIDUE` — `6f875c45`이 VS-C1으로 은퇴, 예외 등재만 잔존 |
| `.github/workflows/h4-routing-measure.yml` | `c07b8354b6af6db666c99f9480856ab37b9ed6c4` | `2026-11-24T05:48:53Z` | `NOT_FOUND (HTTP 404)` | `ci-infra` | `RETIRE_RESIDUE` — 동일 커밋 |
| `.github/workflows/hardware-falsification-smoke.yml` | `c07b8354b6af6db666c99f9480856ab37b9ed6c4` | `2026-11-24T05:48:53Z` | `NOT_FOUND (HTTP 404)` | `ci-infra` | `RETIRE_RESIDUE` — 동일 커밋 |
| `.github/workflows/trust-surface-pin-notice.yml` | `c07b8354b6af6db666c99f9480856ab37b9ed6c4` | `2026-11-24T05:48:54Z` | `NOT_FOUND (HTTP 404)` | `ci-infra` | `NEVER_LANDED` — v87 선등록 후 본문 미착지, 이 repo 이력에 커밋 0건 |
| `src/gate/orchestrator.nim` | `c07b8354b6af6db666c99f9480856ab37b9ed6c4` | `2026-11-24T05:48:55Z` | `NOT_FOUND (HTTP 404)` | `gate-infra` | `STALE_VS_DEBT_REGISTRY` — DEBT#476 `historicalFiles`가 이미 historical로 기록 |

`disposition`은 **후보 라벨**이며 집행된 변경이 아니다. 어떤 정책·config도 수정되지 않았다.

## §2. 재현 명령

모든 lookup은 라이브 API를 직접 조회했다. 로컬 클론은 `c07b8354`를 포함하지 않으므로(§3) 로컬 `git`만으로는 이 record를 재현할 수 없다.

```bash
# 0. 대상 식별 + default branch 고정
gh api repos/{owner}/{repo} --jq '{full_name, default_branch}'
# -> {"default_branch":"main","full_name":"Archright/Axiom"}
gh api repos/Archright/Axiom/git/ref/heads/main --jq '.object.sha'
# -> c07b8354b6af6db666c99f9480856ab37b9ed6c4

# 1. 경로별 존재 확인 (5회) — HTTP status를 직접 본다
SHA=c07b8354b6af6db666c99f9480856ab37b9ed6c4
for p in \
  .github/workflows/gateway-jobs-measure.yml \
  .github/workflows/h4-routing-measure.yml \
  .github/workflows/hardware-falsification-smoke.yml \
  .github/workflows/trust-surface-pin-notice.yml \
  src/gate/orchestrator.nim ; do
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  code=$(gh api "repos/Archright/Axiom/contents/$p?ref=$SHA" --silent --include | head -1 | awk '{print $2}')
  echo "$ts HTTP=$code $p"
done
# -> 5행 모두 2026-11-24T05:48:5xZ HTTP=404

# 2. 양성 대조군 — 쿼리 형태 자체가 유효함을 증명 (404가 "잘못된 쿼리"가 아님)
gh api "repos/Archright/Axiom/contents/.github/workflows/admission-check.yml?ref=$SHA" \
  --jq '{name, sha, size}'
# -> {"name":"admission-check.yml","sha":"433be3c34c51cfc3fc6f8741009135cfa5906a03","size":327211}
gh api "repos/Archright/Axiom/contents/config/repository_surface.json?ref=$SHA" \
  --jq '{name, sha, size}'
# -> {"name":"repository_surface.json","sha":"7643eebb...","size":103648}

# 3. 트리 전수 대조 — 7,581 entry, truncation 없음
gh api "repos/Archright/Axiom/git/trees/$SHA?recursive=1" --jq '.truncated'
# -> false
gh api "repos/Archright/Axiom/git/trees/$SHA?recursive=1" --jq '.tree[].path' > /tmp/tree.txt
for p in <위 5경로>; do grep -qxF "$p" /tmp/tree.txt && echo PRESENT || echo ABSENT; done
# -> 5행 모두 ABSENT

# 4. 디렉터리 열람 — 대소문자/경로 변형 배제
gh api "repos/Archright/Axiom/contents/.github/workflows?ref=$SHA" --paginate --jq '.[].name' | sort
# -> 25개 파일, 5경로 중 어느 것도 없음
gh api "repos/Archright/Axiom/contents/src/gate?ref=$SHA" --paginate --jq '.[].name' | sort
# -> orchestrator.nim 없음; src/gate/orchestrator/ 는 hook/ 만 포함

# 5. 이력 조회 — "삭제됨"과 "애초에 없었음"의 구분
gh api "repos/Archright/Axiom/commits?path=.github/workflows/trust-surface-pin-notice.yml&sha=main" --jq 'length'
# -> 0
gh api "repos/Archright/Axiom/commits?path=src/gate/orchestrator.nim&sha=main" --jq 'length'
# -> 0

# 6. 삭제 커밋 확인 + ancestry (로컬 클론에 없으므로 API로)
gh api "repos/Archright/Axiom/commits/6f875c45535e6bcc28032db48bbe7fe42158302d" \
  --jq '{sha, date: .commit.committer.date, msg: (.commit.message | split("\n")[0])}'
# -> 2026-11-14T14:28:16Z "ci: retire three zero-run measurement workflows (VS-C1)"
gh api "repos/Archright/Axiom/compare/6f875c45...main" --jq '{status, behind_by}'
# -> {"status":"ahead","behind_by":0}  (= main의 조상)

# 7. frozenExceptions 전수 스캔 — brief의 5건이 완전한지 검증
#    (config/repository_surface.json @ c07b8354, frozenExceptions.paths 116건)
#    -> ABSENT 5건, present 111건. 목록은 §1과 정확히 일치. 그 외 없음.
```

## §3. 관측 환경 주의 — 로컬 클론은 라이브 `main`이 아니다

로컬 클론 `HEAD` = `160e70cda364e5745133d3f04d2e1295b4a026df` (로컬 `main`, 2026-11-24T03:27:38Z 커밋 기준), 라이브 `main` = `c07b8354`. 로컬 클론은 `c07b8354`를 **포함하지 않는다**.

이 record의 모든 판정은 라이브 API 응답에 근거한다. 로컬 `git log`는 §1의 "이력 0건" 주장에 대해 **보조 증거로만** 사용했고, 최종 확인은 `commits?path=` API(§2-5)로 수행했다. 이유: 로컬 클론이 오래된 경우 "이력에 없다"가 거짓 음성이 될 수 있다.

## §4. 잔여 보호 참조 — 5경로를 다른 보호장치가 참조하는가

`AGENTS.md` 기준 "App byte-identity 집합 안의 죽은 예외"와 "어디에도 참조되지 않는 죽은 예외"는 서로 다른 발견이다. 세 파일을 라이브 SHA에서 직접 읽어 확인했다.

| 보호장치 | 파일 | 크기 | 5경로 중 참조 | 비고 |
|---|---|---|---|---|
| 서피스 가드 정책 | `config/repository_surface.json` | 116 exceptions / 264 CONTROLLED | **5/5** | 유일한 참조자 (§4.1) |
| App byte-identity | `config/policy/trust_surface_manifest.json` | **18 paths** | **0/5** | blob-equality 비교 집합 |
| merge admission 수동감사 | `config/policy/merge_admission.json` → `trustSurface` | **39 entries** | **0/5** | glob 1건(`.github/actions/setup-axiom-toolchain/**`) 포함 |
| checker closure | `config/trusted_checker_closure.json` → `trustedCheckerTreeClosure` | **891 entries** | **0/5** | wildcard key 0건 — glob 우회 불가 |
| CODEOWNERS | `.github/CODEOWNERS` | — | 0/5 | measurement/orchestrator 항목 없음 |
| required context | `merge_admission.requiredValidations` | 6 entries | 0/5 | 5경로는 required check 생산자가 아님 |

```bash
# §4 재현
SHA=c07b8354b6af6db666c99f9480856ab37b9ed6c4
for f in config/policy/trust_surface_manifest.json \
         config/policy/merge_admission.json \
         config/trusted_checker_closure.json ; do
  gh api "repos/Archright/Axiom/contents/$f?ref=$SHA" --jq '.content' | base64 -d > /tmp/$(basename $f)
done
# 이후 각 파일에서 5경로 문자열 검색 -> 전부 0 hit
```

### §4.1 유일한 참조자는 정책 자신이다

`config/trusted_checker_closure.json`은 wildcard key를 하나도 쓰지 않으므로(`[k for k in c if '*' in k]` → `[]`) glob에 의한 암묵 포함은 없다. 5경로는 891 집합에 **명시적으로 없다**. 즉 5경로에 대해 살아 있는 유일한 장치는 `repository_surface.json`의 예외 등재 그 자체다.

## §5. 죽은 예외는 불활성이 아니다 — 실측

`tools/surface_guard.nim`의 dead-exception 판정은 **정책 텍스트 내부의 교차 검사**이며 파일시스템을 보지 않는다(`isValidPolicy`, `tools/surface_guard.nim:464-466`: `for e in excPaths: if e notin conflicts: return false`). `conflicts`는 `classes.CONTROLLED`의 exact 패턴과 `classes.FROZEN` glob의 교차로 계산되고(`tools/surface_guard.nim:447-460`), **디스크 존재 여부는 입력이 아니다**. 따라서 파일이 삭제되어도 예외 등재가 CONTROLLED에 남아 있으면 "죽은" 것으로 판정되지 않는다 — 가드의 dead 판정은 **정책상 불일치**만 잡고 **실물 부재**는 잡지 않는다.

그 결과를 실제 바이너리로 확인했다 (`bin/surface_guard`, Linux ELF, WSL `Ubuntu-24.04`에서 실행, 정책 = 라이브 v108).

| 시나리오 | diff | verdict | reasonCode | exit | 해석 |
|---|---|---|---|---|---|
| A. 변경 없음 | empty | `PASS` | `OK` | 0 | 5건이 구조 검증을 **통과** (dead으로 거부되지 않음) |
| B. 5경로 재추가 | `A` × 5 | `PASS` | `OK` | 0 | **죽은 예외가 FROZEN 기본거부를 무력화** — 재도입 허용 |
| C. 5경로 수정 | `M` × 5 | `PASS` | `OK` | 0 | 동일 |
| D. 반사실: 5경로 등재를 제거하고 동일 `A` × 5 | `A` × 5 | `FAIL` | `SURFACE_FORBIDDEN` | 1 | FROZEN(`.github/**`, `src/gate/**`)가 정상 작동 |

```bash
# 재현 (B / D). D는 정책 사본에서 두 등재(CONTROLLED exact + frozenExceptions.paths)를 모두 제거한 뒤 실행.
./bin/surface_guard --policy <policy.json> --diff <name-status>
```

**B와 D의 대비가 핵심이다**: FROZEN 규칙은 `ADD: FAIL`인데, 라이브 정책(B)에서 이 5경로의 `ADD`는 `PASS`다. 즉 §1의 `ci-infra`/`gate-infra` 예외는 "죽었지만 무해한 잔여물"이 아니라, **은퇴한 워크플로를 다시 추가할 수 있는 사전 승인 레인**으로 남아 있다. 등재를 제거하면(D) 같은 변경이 `FROZEN`/`SURFACE_FORBIDDEN`으로 거부된다 — 두 등재가 실제로 verdict를 바꾸는 **load-bearing** 상태다.

이것은 §0.9(극장 금지) 관점의 관측이다: 예외 등재가 존재하는 파일에 대해서는 아무것도 보장하지 않으면서, 존재하지 않는 파일에 대해서는 FROZEN 기본거부를 해제한다. 다만 이 record는 **판정하지 않는다** — 위 표는 관측이다.

## §6. 두 현상의 분리 — 처분이 달라야 하는 이유

### §6.1 은퇴 잔여물 3건 (`RETIRE_RESIDUE`)

삭제 커밋 `6f875c45535e6bcc28032db48bbe7fe42158302d` (2026-11-14T14:28:16Z)의 메시지 전문:

> `gateway-jobs-measure, h4-routing-measure, hardware-falsification-smoke` have zero runs and no consumer path (workflow_call, workflow_run, API dispatch, docs/ops, ruleset). None produces a required context. Baseline policy lists them as DELETE (always PASS); **the policy file is left untouched.**

커밋 스스로가 "정책 파일은 건드리지 않았다"고 기록했다. 따라서 이 3건은 **누락이 아니라 명시된 생략**이다. 다만 그 생략이 §5의 ADD 레인을 남겼다는 사실은 커밋 메시지에 기록되어 있지 않다.

세 경로는 baseline `c021c338`에는 **실재했다**(`git cat-file -e c021c338:<path>` → PRESENT). 즉 "이 repo에 존재한 적 있는 파일"이다.

**시점 순서 (정책 description의 버전 노트 기준)**

| 시점 | 사건 | 출처 |
|---|---|---|
| 2026-10-13 (v79) | `h4-routing-measure.yml`이 FROZEN→CONTROLLED로 이동 | description v79 |
| 2026-11-12 (v97) | `gateway-jobs-measure.yml`·`hardware-falsification-smoke.yml`이 CONTROLLED로 재승인 | description v97 |
| 2026-11-14T14:28:16Z | `6f875c45`이 3개 워크플로 삭제, 정책 미수정 | 커밋 메시지 |
| 2026-11-18 (v102) | 109건을 `frozenExceptions`로 편성 — **이미 삭제된 3건 포함** | description v102 |

즉 죽은 3건은 삭제된 뒤에 **예외 그룹으로 재등재**되었다. v102의 편성 작업은 대상 경로의 디스크 존재를 확인하지 않았다(§5의 dead 판정이 구조 검사이므로 통과했다). 이 순서는 "등재 시점에 이미 죽어 있었다"는 뜻이며, §6.2·§6.3과 달리 **삭제와 재등재가 서로의 존재를 몰랐다**는 형태다.

### §6.2 미착지 1건 (`NEVER_LANDED`)

`.github/workflows/trust-surface-pin-notice.yml`은 v87 (2026-10-23)이 "2단계 = 본문은 trust-surface-pin-notice 배치 PR에서 본 PR merge 후 정상 push"로 **선등록**한 경로다. 라이브 API 기준 `commits?path=` 응답이 **0건**이며 baseline `c021c338`에도 없다. 본문 PR이 이 세대에 착지하지 않았다.

이 항목은 §6.1과 처분이 다르다: 은퇴한 것이 아니라 **애초에 도착하지 않은** 선등록이다. 처분 선택지는 (a) 본문 PR 착지, (b) 등재 철회 두 가지이며, 둘 중 어느 것도 이 record가 결정하지 않는다.

### §6.3 이중 historical 불일치 1건 (`STALE_VS_DEBT_REGISTRY`)

`src/gate/orchestrator.nim`은 `data/debt_registry.json` DEBT#476 항목에서 이미 historical로 기록되어 있다:

```
"lineRange": "...; src/gate/orchestrator.nim:1-160 (DELETED 2026-10-04, zero importers)"
"historicalFiles": ["src/gate/orchestrator.nim"]
```

즉 **두 번째 권위가 이미 그 파일을 부재로 선언**했는데, `repository_surface.json`의 `gate-infra` 예외는 그 사실을 반영하지 않았다. 이 항목은 §6.1·§6.2와 달리 **저장소 내부의 두 레지스트리 사이 불일치**이며, 하나의 사실에 두 개의 상태가 존재하는 형태다.

부수 관측: `config/topology.json:1077`에 이 경로가 `domain: gate, subdomain: root`로 여전히 선언되어 있다. `src/core/topology/suggest.nim:116`이 "declared in topology.json but missing on disk"를 ghost path로 탐지하므로, 이 경로는 **세 번째** 불일치 축(topology 선언)도 갖는다. topology 쪽 탐지가 실제로 이 항목을 보고하는지는 이 record에서 확인하지 않았다 — 미검증으로 남긴다.

## §7. 확인된 것 / 확인하지 않은 것

| 주장 | 상태 |
|---|---|
| 5경로가 라이브 `main`에 없다 | **확인** (HTTP 404 × 5, 트리 전수 대조, 디렉터리 열람) |
| `frozenExceptions` 116건 중 부재는 정확히 5건이다 | **확인** (전수 스캔) |
| 5경로를 참조하는 다른 보호장치가 없다 (18/39/891/CODEOWNERS/required) | **확인** |
| 세 워크플로는 의도적으로 은퇴했고 정책은 의도적으로 미수정이다 | **확인** (`6f875c45` 메시지) |
| `trust-surface-pin-notice.yml`은 이 repo 이력에 커밋이 없다 | **확인** (API `commits?path=`, 0건) |
| `orchestrator.nim`은 DEBT#476에 historical로 기록되어 있다 | **확인** |
| 죽은 예외가 FROZEN ADD 기본거부를 해제한다 | **확인** (§5 시나리오 B vs D, 실제 바이너리) |
| `topology.json` ghost-path 탐지가 `orchestrator.nim`을 보고한다 | **미확인** — 도구를 실행하지 않았다 |
| 예외 등재를 제거하는 것이 옳은 처분이다 | **판정하지 않음** — 인간 아키텍트 권한 |

## §8. 범위 밖 / 후속

- 정책·config 수정 없음. `config/repository_surface.json`, `config/policy/*`, `config/trusted_checker_closure.json`, `data/debt_registry.json` 모두 **읽기만** 했다.
- §8.1의 그룹별 존재율은 §2-7의 트리 전수 대조를 그룹별로 집계한 것이며, 116건 **전수** 측정이다(표본 아님).
- `data/debt_registry.json` DEBT#476의 `historicalFiles`와 `repository_surface.json` 사이의 정합을 기계적으로 검사하는 게이트는 이 record에서 발견되지 않았다. 이 축의 자동 탐지 유무는 미확인이다.

### §8.1 그룹별 실물 존재율 (전수)

| 그룹 | 등재 | 부재 | 존재 | 부재 경로 |
|---|---|---|---|---|
| `generated-manifest` | 52 | 0 | 52 | — |
| `gate-infra` | 38 | **1** | 37 | `src/gate/orchestrator.nim` |
| `ci-infra` | 19 | **4** | 15 | `gateway-jobs-measure.yml`·`h4-routing-measure.yml`·`hardware-falsification-smoke.yml`·`trust-surface-pin-notice.yml` |
| `epoch-rotation` | 2 | 0 | 2 | — |
| `admission-mint-pin-rotation` | 2 | 0 | 2 | — |
| `fresh-prove-observation` | 1 | 0 | 1 | — |
| `trust-supply-path` | 1 | 0 | 1 | — |
| `publication-venue-split` | 1 | 0 | 1 | — |
| **합계** | **116** | **5** | **111** | |

부재는 `ci-infra`(4/19 = 21.1%)와 `gate-infra`(1/38 = 2.6%) 두 그룹에만 분포한다. 나머지 6개 그룹은 부재 0이다. 두 그룹 모두 **정확 경로 등재** 방식이며, `ci-infra`의 부재율이 높은 것은 이 그룹이 "기존 reviewed 워크플로의 carve-out"을 모으는 그룹이어서 워크플로 은퇴가 그대로 누적되기 때문이다.
