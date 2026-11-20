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
| `44732765172` | axiom-operational-slice | <!-- FILL:c1 --> |
| `44732764882` | fresh-prove-observation | <!-- FILL:c2 --> |

### §5.2 stale-base PR-venue 재실행 실증

방법: main `8439632`에서 문서 PR을 만들고(이벤트 `base.sha = 8439632`), 별도 문서 PR을 먼저 착지시켜 main을 전진시킨 뒤, 첫 PR의 `admission-gate` run을 **rerun**한다. rerun은 원본 이벤트 payload(`base.sha = 8439632`)를 재사용하지만 `anchor-resolve`는 live main tip을 새로 해석하므로 `pr_base != anchor` 조건이 성립한다.

<!-- FILL:demo -->

## §6. 이 기록이 주장하지 않는 것

- App `5795152`의 내부 판정 로직(소스 비공개)을 변경했다고 주장하지 않는다. App의 stale-run 오결속은 별도 owner handoff다.
- 단일 계정 거버넌스의 한계(독립 승인자 부재)를 해소했다고 주장하지 않는다.
- 두 workflow가 App trust surface에서 제외되었다고 주장하지 않는다 — 계속 포함이며 `admission-check`가 거부한다.
- `#251`의 ROT_ALLOWLIST 위반은 본 범위가 아니다(별도 rotation lane 승인 필요).