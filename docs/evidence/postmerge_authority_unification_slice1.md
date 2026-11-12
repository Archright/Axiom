# Post-merge verification authority unification — Slice 1 evidence (2026-09-13)

## Scope (plan v16 terminal outcome)

PR #71 (`feature/admission-trusted-writer`)의 Slice 1은 post-merge main 검증 권위를
**단일 workflow(`canonical-main.yml`)로 일원화**하고, 그 권위가 관측 가능한 정적 트리거 구조
(E1/E2)를 만족함을 기계 판정으로 입증한다.

---

## E1: top-level post-merge authority = {canonical-main}

### 실측 명령

```bash
$ grep -l "branches:" .github/workflows/*.yml
.github/workflows/canonical-main.yml
.github/workflows/ci.yml
.github/workflows/ledger-guard.yml
.github/workflows/readiness_start.yml
# exit 0
```

`branches:` 문자열 보유 4개 파일 중, 주석 제외 후 python `yaml.safe_load`로 파싱한 실제
`on:` 블록 (PyYAML YAML1.1의 `on:`→`True` 키 변환 처리):

| workflow | 실제 트리거 | 비고 |
|---|---|---|
| `canonical-main.yml` | `push: branches=[main]` + `workflow_dispatch` | **post-merge 검증 단일 권위** (D8/D10) |
| `ci.yml` | `push: branches=[main, docs/**]` + `pull_request` + `schedule` | 5개 검증 job이 push:main에서 제외 (`if:` 가드, ci.yml:85) — post-merge 검증 주체 아님 |
| `ledger-guard.yml` | `push: branches=[axiom/**]` | ADR-0022 §5 safety net — **권위 증명의 일부 아님** (파일 헤더 명시) |
| `readiness_start.yml` | `pull_request` + `merge_group` | `branches:`는 PR/merge_group의 필드 — grep -l 오탐, main-push 트리거 없음 |

**판정**: `push: branches:[main]`을 가진 workflow = `{canonical-main.yml}` 단일. 참고 비교
(계획 v16 기대)의 `{ci.yml, canonical-main.yml}`과 정합 — ci.yml은 검증 job이 push:main에서
제외되므로 post-merge 검증 권위가 아니며, ledger-guard·readiness_start는 트리거가 다르므로
E1 대상에서 제외.

---

## E2: merge_continuity independent trigger = 0

### 실측 명령

```bash
$ grep -rn "merge_continuity.yml/dispatches" --include="*" . 2>/dev/null \
    | grep -v "^\./\.git/" | grep -v "^\./\.wt/"
# (출력 없음 — 0건)
# exit 0 (PIPESTATUS[0]=0)
```

### workflow_call 단독 확인 (python yaml 파싱)

`merge_continuity.yml`의 `on:` 블록 (45–51행):

```yaml
on:
  workflow_call:
    inputs:
      expectedOid:
        description: "observed main merge-commit SHA to certify (required)"
        required: true
        type: string
```

- 외부 트리거(`push` / `workflow_dispatch` / `pull_request` / `schedule` / `workflow_run`) **0건**.
- `workflow_call` 보유 workflow = `{auto_merge.yml, canonical-main.yml, merge_continuity.yml}` 3개
  (자체 호출 아님).
- 호출부는 `canonical-main.yml:239` `uses: ./.github/workflows/merge_continuity.yml` 단일 —
  auto_merge.yml은 dispatch 대상이 `canonical-main.yml/dispatches`로 재타겟
  (`auto_merge.yml:316`, HTTP 204 fail-closed, `expectedOid=L` transport injection).

**판정**: merge_continuity는 독립 진입 0건, workflow_call 재사용 컴포넌트로만 존재. (base
`36c84c9d`에서는 `push: branches:[main]` + `workflow_dispatch` 보유였음 — 단일화로 제거됨.)

---

## E2b (bootstrap 관측, 2026-09-13 실측): H=99fc4122b merge — canonical-main 발화 & bind FAIL

PR #71 merge 커밋 `H = 99fc4122b56137d8ad1b64c38bd7e9c2addbd3de`에서의 run 전수
(`gh api /actions/runs?head_sha=99fc4122b…`, 6건):

| run id | workflow | event | conclusion |
|---|---|---|---|
| 34756599981 | ci.yml | push | success |
| **34756600165** | **canonical-main** | **push** | **failure — bind FAIL (아래 원문)** |
| 34756752062 | auto merge admission | workflow_run | success |
| 34756751994 | oidc claims probe | workflow_run | success |
| 34756752049 | verify-candidate | workflow_run | skipped (PR 전용 — 정상) |
| 34756754858 | attest | workflow_run | skipped (PR 전용 — 정상) |

- **post-merge verification run = canonical-main 1건뿐** (merge_continuity 독립 실행 0) —
  단일화가 런타임에서도 관측됨.
- **bind step 로그 원문** (run 34756600165):
  ```
  bind: admissions ref fetch failed — A not present yet (fail-closed)
  bind: TODO(서브C) — tools/ci/verify_admitted_landing.sh not implemented; skipping
  verification is NOT authority (ADR-0022). Landing H=99fc4122b… unbound until the script lands.
  ```
  verify / accept / continuity = 전부 skipped (needs 체인 — bind FAIL이 정확히 상류를 차단).
- **원인 (불가피)**: 이 착지를 만든 merge는 HUMAN merge였고, 실행된 auto_merge(34756004178,
  main@36c84c9d5 기준)에는 mint step이 아직 없었다(mint는 이 PR이 싣는 변경). 즉 A가 생성될
  경로가 이 착지 시점에 존재하지 않음 — ADR-0022가 예고한 bootstrap 상태 그대로.
  ADR-0022 §D10: "bootstrap(PR #71 자체 착지)에서 bind FAIL = 예상된 fail-closed".
- **판정**: 이 failure는 "A 없는 착지를 거부하는" fail-closed 동작의 관측 증거이며 구조 결함이
  아니다. terminal E3~E6는 mint가 동작하는 다음 controlled landing H*에서 판정한다.

## E1b (OIDC claims 실측 — probe run 34756751994)

JWT payload 전문 (aud=axiom-admission-v1, self-hosted runner):
```json
{"iss":"https://token.actions.githubusercontent.com",
 "aud":"axiom-admission-v1",
 "repository":"Archright/Axiom",
 "workflow_ref":"Archright/Axiom/.github/workflows/oidc_probe.yml@refs/heads/main",
 "workflow_sha":"99fc4122b56137d8ad1b64c38bd7e9c2addbd3de",
 "job_workflow_ref":"Archright/Axiom/.github/workflows/oidc_probe.yml@refs/heads/main",
 "job_workflow_sha":"99fc4122b56137d8ad1b64c38bd7e9c2addbd3de",
 "event_name":"workflow_run","run_id":"34756751994","run_attempt":"1",
 "ref":"refs/heads/main","ref_protected":"true","sub":"repo:Archright/Axiom:ref:refs/heads/main",
 "iat":1789301947,"nbf":1789301647,"exp":1789302247,"jti":"63ab9579-…"}
```
- **확정**: `workflow_sha` = **머지 커밋 = main tip** (토큰 발급 시점의 default-branch 파일
  커밋). bind의 HEAD-blob 비교 기준(verify_admitted_landing.sh:59-61,277-287)이 런타임
  의미와 정합함을 실증. kid `38826b17-…`, RS256 — 현재 GitHub JWKS 검증 대상.
- issuer/aud/event_name/처리 모델 전부 ADR-0022 §3 예측과 일치.

---

## E3: H* → canonical-main run = 1

**관측 1차 (bootstrap 후속, H₁ = 17bb90c7e — PR #76 human merge, 2026-09-13)**:

- run 전수(`gh api /actions/runs?head_sha=17bb90c7…`): **canonical-main 단 1건**
  (34758957710, event=**push**), merge_continuity 독립 실행 0 — 단일화 런타임 재확인.
- bind FAIL(동일 원문: `admissions ref fetch failed — A not present yet`) — 원인: human
  merge라 actuator mergeGo 경로가 아니어서 mint 미구동. main 배선은 완료됐으나 actuator
  merge가 아직 한 번도 지나가지 않음. E4~E6는 **actuator mergeGo 착지 H₂**에서 판정.
- merge 전 baseline: canonical-main run 목록에 2a181d4aa(34758469471, failure — bootstrap
  계열)만 존재. H₁에서의 신규 run = 1건이 정확히 그 착지에 귀속.

**PENDING(H₂)** — actuator mergeGo 착지에서 run=1 재확인 (부모 P6b).

## E4: bind/verify success

**PENDING** — H* canonical-main run의 bind/verify 결론 (부모 P6에서 채움).

## E5: R(H*) = 1

**OBSOLETE-BY-RETIREMENT (2026-10-07)** — `refs/heads/axiom/canonical-acceptances`
writer가 폐기되었다(`docs/spec/authority_contract.md` §5.4 — GitHub required
check + merge queue가 authoritative acceptance; ref 자체는 보존). R(H*) 건수는
더 이상 관측 표면이 아니다. 원문(PENDING, 역사 보존): `refs/heads/axiom/canonical-acceptances`의 R(H*) 건수 (부모 P6에서 채움).

## E6: rerun → R(H*) unchanged

**OBSOLETE-BY-RETIREMENT (2026-10-07)** — writer 부재로 rerun이 ledger 원장을
변경할 수 없다(불변은 쓰기 금지로 성립 — writer retired). 원문(PENDING, 역사
보존): rerun 후 R(H*) 불변 (부모 P6에서 채움).

---

## Commits

PR #71 Slice 1 (unification 관점, origin/main `36c84c9d` 이후):

| sha (abbrev) | 제목 |
|---|---|
| `c3ec1b871` | docs(adr): ADR-0022 admission artifact authority — trusted writer capability (A) + TrustedWriterSet registration |
| `1fb5e4a25` | chore(ci): attest.yml contents write→read demotion + publication_scope registration (ADR-0022 §4 TrustedWriterSet) |
| `c22ad1a85` | feat(ci): canonical-main landing bind/verify/accept pipeline + ledger-guard safety net (ADR-0022 D8/D9) |
| `4639f308e` | feat(ci): auto_merge mint wiring — OIDC admission artifact A (ADR-0022 §1 ②③) |
| `a059513fd` | feat(ci): post-merge verification authority unification — merge_continuity as workflow_call, canonical-main sole authority, auto_merge dispatch retarget, trusted-sha atomic update (ADR-0022 D10) |

> **주의**: `a059513fd`(D10)는 **내용 없는 커밋(empty commit)** — `tree(a059513fd) ==
> tree(c2bc90b1c) == 1f5effdaf…`, `git diff` 0줄. 단일화된 상태는 D10 이전 커밋
> (c22ad1a85 등)에 이미 포함되어 있으며, D10은 그 상태를 선언·기록한 커밋이다.

---

## Gate evidence

- **pre-push (Part 1~3) — PASS (로컬 실측, 빈 refspec)**
  `Axiom Tier Integrity Gate PASS` / `anti_theater_gate PASS — no staged changes to check` /
  `layer_enforcement_gate PASS — no layer violations in 1581 files`.
  (Part 4 push-admissibility는 빈 refspec으로 스킵 — `OID_REF: 잘못된 배열 첨자`. 실제
  push 시의 Part 4 결과는 PENDING.)
- **TrustedWriterSet 검증 (E2 도구) — PASS (로컬 실측)**
  `verify_trusted_writer_set: PASS — contents:write holders == TrustedWriterSet = {
  .github/workflows/auto_merge.yml@5fe733b047a61e3c2d440160bed08255a98a6d76 }` (exit 0);
  `trustedAdmissionWorkflowSha` == 현재 HEAD auto_merge.yml blob sha (`git rev-parse
  HEAD:.github/workflows/auto_merge.yml`) — atomic 일치 실측.
- **publication_scope selftest — PASS 8/8 (로컬 실측)**
  `bin/publication_scope_gate --selftest` → case1~case6c 전부 PASS, `selftest PASS: all 8
  assertions hold`, exit 0.
- **publication_scope gate 본체 — FAIL (로컬 실측, 위험 항목)**
  `bin/publication_scope_gate` → `RED: rule-violation: .github/workflows/canonical-main.yml
  actions: read=true but publication_scope.json declares actions_read=false`, exit 1.
  `config/publication_scope.json`의 canonical-main.yml 규칙에 `actions_read` 미선언
  (auto_merge/attest/verify-candidate만 true). CI `check-publication-scope`(Makefile:215)가
  빨간 실패할 수 있음 — **추가 등록 필요 (서브C/후속 커밋)**.
- **make test / nimtry 0 violations** — **PENDING** (로컬 bin/은 gitignored라 현재 트리
  기준 실측 부적절; nimtry는 `PASS — 4082 violations (debt anchored)`로 판정됨. 원본 CI
  로그의 make test exit 0 + nimtry 0 violations는 부모 P6에서 확보 예정).
