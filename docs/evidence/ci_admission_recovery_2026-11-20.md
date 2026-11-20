# CI admission recovery — ADR-0027 Amendment B 집행 기록 (2026-11-20)

> **Status**: 착지 기록(landing record) + 재발 방지 근거. 본 문서는 코드·정책·ruleset을 변경하지 않는다.
> **범위**: root cause B(PR-venue `B` = PR-API `base.sha` 등식)의 제거와 그 운영 검증.
> **선행 문서**: `docs/adr/0027-queue-delegation.md` Amendment B, `docs/agents/axiom_admission_verifier_ops.md`.

## §1. 관측된 결함 (root cause B)

ADR-0027 Amendment B는 PR-venue의 `B`를 `workflow_call`의 `baseSha` anchor로 규정하고 `pulls/N.base.sha`를 journal-only로 규정한다. 착지 전 main의 `certificate-mint.yml`은 A0/MINT_ID/P0 세 지점에서 `pr.base.sha == B` 등식을 강제했고, MBH는 `B = pr.base.sha`로 재유도했다. base가 전진한 뒤 발화한 PR-venue 실행에서 anchor(현재 main)와 이벤트 생성 시점의 `pr.base.sha`가 달라지면 mint가 fail-closed로 멈춘다.

실측 (PR #254, run `44719892320`):

```
MINT_A0_ACTIVATION: FAIL — PR #254 base.sha '32ebe170e937' != baseSha input '1080f6cfff70' (fail-closed)
```

이 실패는 admission-check를 현 head에 `failure`로 고정해 착지를 막는다. merge queue의 결함이 아니라 입장 판정의 결함이다.

## §2. 변경 (main `8439632`)

| 커밋 | 파일 | 내용 |
|---|---|---|
| `a60deb1c4a92987c463d02bb9d87b05cf874bdc8` | `.github/workflows/certificate-mint.yml` | A0/MINT_ID/P0 등식 제거 → `MINT_*_JOURNAL`; MBH PR-venue `B = inputs.baseSha`. merge_group venue의 `event merge_group.base_sha == B == inputs.baseSha` 등식은 불변 |
| `c60daacd4b1a7a737b99dcae74e6b6a0be2caff5` | `.github/workflows/admission-gate-v2.yml` | certificate-mint callee pin ×2 → `@a60deb1`; admission-check callee pin ×2 → `@7f3424cc` (실행 blob `433be3c3` = TWS `trustedAdmissionWorkflowSha` = `epoch_manifest.productionExecutionPin`) |

정본 blob 검증:

- `git rev-parse a60deb1:.github/workflows/certificate-mint.yml` = `c7ca8ed75ae0602ae85ce80b7dcab57b31971973` = worktree blob
- `git rev-parse 7f3424cc:.github/workflows/admission-check.yml` = `433be3c34c51cfc3fc6f8741009135cfa5906a03` = TWS 선언 = epoch pin

## §3. 착지 기록 (break-glass, MUST-T2a)

두 PR 모두 trust-surface 경로를 변경하므로 App `5795152`의 `admission-check`가 설계대로 `failure`를 발행했다. 각 PR에 병합 **전** 위임 코멘트를 등록하고, required check를 보유한 **두 ruleset**(`27097366` main, `27525972` main-admission)에 일시 bypass를 부여한 뒤 REST merge로 착지하고 즉시 원복했다.

| PR | head | App check-run (5795152) | merge commit |
|---|---|---|---|
| #259 (policy v107) | `87a131edb2a56669ac3e6d063819d43ca2215c17` | `136263437835` failure — `trust_surface=FAIL … mismatch:config/repository_surface.json` | `38b7f37c9e506e7b71409a13515365327524f847` |
| #260 (root fix) | `c60daacd4b1a7a737b99dcae74e6b6a0be2caff5` | `136270660402` failure — `trust_surface=FAIL … mismatch:.github/workflows/admission-gate-v2.yml,mismatch:.github/workflows/certificate-mint.yml` | `8439632facab5e0fbcaeb9d315342da0d487bbcd` |

ruleset 스냅샷/원복 (의미 동일 = `name`/`target`/`enforcement`/`bypass_actors`/`conditions`/`rules` 전부 일치):

| ruleset | pre-snapshot sha256 (#259 / #260) | 착지 후 |
|---|---|---|
| `27097366` | `f28eb96…` / `4830ccd…` | `bypass_actors=[]`, `current_user_can_bypass=never`, semantic identical |
| `27525972` | `fd432e8…` / `f378316…` | `bypass_actors=[]`, `current_user_can_bypass=never`, semantic identical |

App 판정은 `failure`로 보존되며 `success`로 재분류하지 않는다. 독립적 제2 승인자는 없었다.

## §4. 불변식 보존

| 불변식 | 상태 |
|---|---|
| merge authority = GitHub ruleset | 불변 |
| required 7 contexts / App `5795152` / expected source | 불변 |
| TWS · `epoch_manifest` · `trust_surface_manifest` | 불변 |
| policy v107: 두 workflow exact CONTROLLED + `frozenExceptions` 등록 (v106 `epoch-rotation` 선례와 동일 형태) | `make check-repository-surface` → `PASS / OK` (policyVersion 107) |

## §5. 운영 검증

### §5.1 canonical main push CI (`8439632`)

| run | workflow | 결과 |
|---|---|---|
| `44732764939` | Push on main | success |
| `44732764710` | trusted-writer-set | success |
| `44732765172` | axiom-operational-slice (`readiness-verdict` 포함) | success |
| `44732764882` | fresh-prove-observation | success |

### §5.2 stale-base PR-venue 재실행 실증 — 관측과 판정

방법: main `8439632`에서 문서 PR #262(head `18b2d6be`)를 만들고(이벤트 `base.sha = 8439632`), #261을 **정상 merge queue**로 착지시켜 main을 `20fc6d44`로 전진시킨 뒤, #262의 `admission-gate` run `44733678104`를 rerun(attempt 2, `2026-11-20T12:34Z`경)했다.

관측 (attempt 2):

- `anchor-resolve`: `B* = 20fc6d44fcddd4e6634cf89e53e85271a4f80473` (live main)
- `MINT_A0_JOURNAL: pr_base='8439632facab' anchor='20fc6d44fcdd' (pr.base.sha non-input — ADR-0027 Amd B)` — 등식 제거 확인, mint 성공
- `MINT_ID_JOURNAL: pr_base='8439632facab' anchor='20fc6d44fcdd'` — 동일
- `mint-prepare / prepare` success, `mint-publish / publish` success
- `attest / admission-independents` **failure**: `CANDIDATE_TREE_MISMATCH: merge-tree(20fc6d44, 18b2d6b) tree 9c20056f != tested landing candidate tree 0fc63b33` (fail-closed)

판정: mint의 stale-base 결함은 제거됐다. 동시에 이 실험은 **기존의 fail-closed 후보 동일성 계약**을 드러냈다 — PR-venue verdict는 "실제로 테스트된 후보"(이벤트 시점 `github.sha`의 merge tree)와 "현재 anchor의 merge tree"가 일치할 때만 성립한다. base가 이벤트 생성 후 전진하면 두 후보는 필연적으로 다르며, 거부는 **정직한 fail-closed**다(테스트되지 않은 후보를 통과시키지 않는다). 따라서 base 이동 후의 rerun은 재심사가 아니고, 복구 경로는 **새 이벤트**(새 head push·reopen 등)로 새 후보를 테스트하는 것이다.

### §5.3 복구 실증 — 새 이벤트(이벤트 base = anchor)

본 기록을 갱신한 새 커밋(head `33921987930862f361e4cba275dd8ff1a8a357e4`)으로 새 `pull_request` 이벤트를 발생시켰다. 새 이벤트는 `refs/pull/N/merge`를 현재 main 기준으로 새로 계산하므로, 테스트된 후보와 anchor 후보가 일치한다.

관측 (run `44738506989`, attempt 1):

- `anchor-resolve`: `B* = 20fc6d44fcdd…`
- `MINT_A0_JOURNAL: pr_base='8439632facab' anchor='20fc6d44fcdd'` — attempt 2와 동일한 발산이지만 **run 전체 success**
- `mint-prepare / prepare`·`mint-publish / publish`·`attest / admission-independents` success
- App `admission-check`: check-run `136295880865` **success** — `run=44738506989 attempt=1 conclusion=success`, `trust_surface=PASS`, `evaluated_commit=3392198…`

대조:

| 실행 | 이벤트 | 테스트된 후보(GITHUB_SHA merge tree) | anchor | 결과 |
|---|---|---|---|---|
| run `44733678104` attempt 2 | 기존 run의 rerun | attempt 1 시점 트리 `0fc63b33`(동결) | `20fc6d44` | `CANDIDATE_TREE_MISMATCH` fail-closed |
| run `44738506989` attempt 1 | 새 `pull_request` 이벤트 | 현재 main 기준 신선한 merge tree | `20fc6d44` | success + App success |

결론: base 이동 후 복구는 rerun이 아니라 **새 이벤트**다. mint는 더 이상 `pr.base.sha` 발산에서 죽지 않고, 후보 동일성 가드는 "실제로 테스트된 후보 = landing 후보"를 계속 강제한다. 이 head는 정상 merge queue 경로의 착지 대상이다(merge commit은 최종 운영 보고에 기록).

## §6. 이 기록이 주장하지 않는 것

- App `5795152`의 내부 판정 로직(소스 비공개)을 변경했다고 주장하지 않는다. App의 stale-run 오결속은 별도 owner handoff다.
- 단일 계정 거버넌스의 한계(독립 승인자 부재)를 해소했다고 주장하지 않는다.
- 두 workflow가 App trust surface에서 제외되었다고 주장하지 않는다 — 계속 포함이며 `admission-check`가 거부한다.
- `#251`의 ROT_ALLOWLIST 위반은 본 범위가 아니다(별도 rotation lane 승인 필요).