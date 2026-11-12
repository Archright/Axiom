# GHEC ruleset 제어장치 + P1(c) App bypass 실측 (2026-09-24)

> 관측 기록이며 추가 구현을 포함하지 않는다. 판정: **scratch 양측 CLOSED — 차단 측·bypass 측 모두 실측 PASS**.
> main ruleset은 아직 교체 전(기존 구 ruleset이 App도 차단 — 아래 §4), Owner #11 운영 실측은 별도.

## 1. 플랫폼 전제 (전부 실측)

| 항목 | 값 | 근거 |
|---|---|---|
| Enterprise | slug `archright`, GHEC 체험판 (기록 시점 잔여 31일) | `github.com/enterprises/archright/settings/profile` |
| Org 플랜 | `Archright` → `plan.name=enterprise`, seats 50 | `gh api /orgs/Archright --jq '.plan'` |
| 저장소 | `Archright/Axiom` (Org 소속 private) | enterprise Organizations 목록 + rulesets API 200 |
| GitHub App | `axiom-ci-elastic` app_id=`4879411`, installation_id=`160192931` | `config/app_landing_binding.json` (READY) |
| App private key | SHA256 fingerprint `Li0jQkpNssx0gKgIhEitQzc28TsCJfFW2UpHn0Ms9h0=` | App 설정 페이지 표시값과 피인증 대조 일치 (경로·사본 미기록) |
| installation token | `POST /app/installations/160192931/access_tokens` 발급 성공 (JWT `iss=4879411`) | 1h TTL — 토큰 값은 미기록 |

## 2. scratch ruleset — 실험 대상

| 항목 | 값 |
|---|---|
| id / name | `23914707` / `cas-probe-scratch` |
| 조건 | `refs/heads/cas-probe/*`, enforcement `active` |
| rules | `update`(`update_allows_fetch_and_merge=false`), `deletion`, `non_fast_forward` |
| bypass_actors | **정확히 1**: `{actor_id: 4879411, actor_type: Integration, bypass_mode: always}` |
| Restrict updates 식별자 | 공식 REST 문서 확정: rule `type: "update"` |

probe ref: `refs/heads/cas-probe/1` (head `79f22a675…` = main tip에서 생성).

## 3. 양측 실측 결과

### 3a. 차단 측 — 사용자 토큰 (wintrover, org admin) = **PASS(거부 확인)**

```
updateRefs(repositoryId=R_kgDORnV8bQ, name=refs/heads/cas-probe/1,
           beforeOid=79f22a675…, afterOid=5d899557d…)   # GH_TOKEN = user token
→ UNPROCESSABLE: "Branch 'refs/heads/cas-probe/1' is protected:
   Cannot update this protected ref."
→ 직후 head 재확인 = 79f22a675… (무변경)
```

org admin도 bypass_actors에 없으면 거부됨을 실측.

### 3b. bypass 측 — App installation token = **P1c_BYPASS_PASS**

```
updateRefs(same variables)                          # GH_TOKEN = installation token
→ {"data":{"updateRefs":{"clientMutationId":null}}}  # errors 없음
→ 직후 head = 5d899557d89e50b3d3f08fe4fad2856d5cfaba24 = afterOid
```

**판정**: scratch 범위에서 제어장치 의미론이 계획과 일치 —
`Integration(4879411)`만 bypass, 그 외 모든 행위자(포함 org admin)는 차단,
bypass 성공 시 head가 정확히 afterOid로 이동.

## 4. main no-op probe — 기존 구 ruleset이 App도 차단 (잔여 조치 근거)

```
main = 79f22a67588cb8e37e0ca0f6d52131e42d5fe55f
updateRefs(refs/heads/main, beforeOid=main, afterOid=main)  # App 토큰, no-op
→ UNPROCESSABLE: "Branch 'refs/heads/main' is protected: Changes must be
   made through a pull request. Required status check
   \"ci/circleci: verify-static\" is expected."
→ main head 무변경 확인
```

- 기존 `main` ruleset `id=20303214` (2026-08-03 생성, bypass_actors `[]`,
  rules: `deletion`/`non_fast_forward`/`required_linear_history`/`pull_request`/
  `required_status_checks`(`ci/circleci: verify-static`, integration_id 302869)/
  `required_signatures`).
- 원인: GHEC 이전 시점의 잔재 — CircleCI 유령 필수 체크 + bypass 부재.
- **잔여 조치 (Owner #11 전)**: 동일 ruleset에 App bypass(`Integration, 4879411,
  always`) 추가 또는 현행 아키텍처 세트로 교체. 그 전까지 main CAS 랜딩은 차단.
- 기존 human PR 경유 native MERGE는 현행 그대로 관측됨(PR #203–#205 착지) —
  human 경로 변경 없음.

## 5. 이 문서가 닫는 질문 / 닫지 않는 질문

| 질문 | 상태 |
|---|---|
| ruleset `update` 규칙이 비-bypass 행위자를 막는가 | **CLOSED (PASS)** — §3a |
| App bypass 시 updateRefs가 beforeOid 대로 착지하는가 | **CLOSED (PASS)** — §3b |
| main에서 같은 의미론이 성립하는가 | **CLOSED (PASS)** — Owner #11 CAS 착지 실측: main←M `b75f6162`, parents(M)=`[aa34d24d5`(B)`, 55a632c4a`(H)`]`, `updateRefs beforeOid=B` 원자적 CAS, PR #211 `merged=true` |
| 운영 PR 전체 체인(mint→CAS 착지→거부→continuity) | **CLOSED (PASS)** — §7 실측 기록 (admission 6×green, mint 4×green, LANDING_OK, MAIN_MOVED 거부, CC_PASSED) |

## 6. 추적

- Owner #11 게이트: `docs/spec/repository_surface_contract.md` Owner #11,
  `docs/spec/certification_continuity_contract.md` §10.6
- Landing binding: `config/app_landing_binding.json` (READY)
- TrustedWriterSet: `config/trusted_writer_set.json`
  (`trustedAdmissionWorkflowSha=c7280c0e7659e28f43bade6a35982c70263ce143` —
  이름 분리(d565c226c) 시 same-commit 원자 갱신, ADR-0022 §5)
- 병렬 조사 산출: ruleset 403 원인(GHEC 미연결)→해소, Completion Evidence
  23항목, Phase D 소거 인벤토리 — 각 서브에이전트 리포트 및 투두 기록 참조

<!-- Owner #11 CAS landing operational proof (2026-09-24) -->

<!-- Owner #11 chain update (2026-09-24): admission-check first GREEN (run 35955557993→35961453432 series after set+e/seed-guard/actions:read fixes); certificate-mint activation+B/H+B-checkout passed, then failed at local-action resolution (run 35961831811 — path: _b vs workspace-root-relative action). Root-checkout fix landed on main (PR #213); this commit re-triggers the chain with a fresh B/H pair. -->

<!-- Owner #11 chain update 2 (2026-09-24): mint 4th blocker = runner image LTO mismatch (ubuntu-22.04 gcc11.3 vs ubuntu-latest-built nimcache LTO13.1, run 35963379690) — fixed by runs-on ubuntu-latest (PR #214). This commit re-triggers admission-check → mint. -->

<!-- Owner #11 chain update 3 (2026-09-24): mint reached (2a)+(3) for the first time; (4) died on undeclared GITHUB_TOKEN under set -u (swallowed as "ax rejected the witness") — steps (4)(5)(6+7) now declare it (PR #215). Re-trigger. -->

<!-- Owner #11 chain update 4 (2026-09-24): mint GREEN + cert(B=90936ac8,H=972a873b) ledger f78efbdb7; #215 mid-run merge advanced main to aa34d24d5 so that cert's B is stale vs current main (CAS beforeOid=B fail-closed by design); local bin/ax rebuilt with re-registered identity (365692388). Re-trigger freezes B=aa34d24d5 → new cert → immediate apply before any further main movement. -->

## 7. Owner #11 체인 실측 — 최종 (2026-09-24)

§5의 두 OPEN 항목을 닫는 관측 기록. 전 단계 fail-closed 실측 포함.

### 7.1 AMBIGUOUS_VALIDATION 소거 (이름 분리)

- 원인 실측: run `35967200922` jobs API에 이름 `admission-check`가 **2건**
  (네이티브 Actions job + 워크플로우가 Checks API로 POST한 동명 Check Run) —
  `merge_cli.containsCheck`는 완전일치 `c == name`이라 matches=2 → AMBIGUOUS.
- 해소: POST Check Run 이름만 `admission-check` → `landing-trigger`로 분리
  (external_id `admission-check-{PR}`(App 웹후크 계약 키)·mint artifact 이름·
  네이티브 job 이름·정책 바인딩은 불변). trusted sha same-commit 원자 갱신
  `79ca90f8 → c7280c0e` (ADR-0022 §5), commit `d565c226c`.
- 실측: run `35969650072` green — job `admission-check`(1m39s)와
  `landing-trigger`(0s) 분리 확인.

### 7.2 apply fail-closed 3회 (전부 main 무변경)

| 회 | reasonCode | 원인 | 수정 |
|---|---|---|---|
| 1 | `TREE_UNRESOLVABLE` | REST `/commits/{sha}` tree가 `commit.tree.sha`에 존재 (최상위 `.tree`=null, live probe) — `landing_cli.fetchCommitTreeOf`·`verifyCreatedCommit` 2곳이 최상위를 읽음 | `7e72d501a` |
| 2 | `GRAPHQL_ERROR` | GraphQL `Ref` 타입에 `oid` 필드 없음 (`__type` live probe: fields=`id, target, …`) | `22e20934e` — `target { oid }` |
| 3 | `UPDATE_REF_REJECTED` | mutation에 선언만 한 미사용 `$refId` 변수 → GraphQL 검증 거부. no-op probe(before=after=current → `errors=[]`)로 최종 shape 사전 실측 | `55a632c4a` |

- 3회 모두 `main untouched` + exit 1로 확인. mutation 최종 shape는
  live probe로 커밋 전 검증(0-OID before는 GitHub 내부오류 유발로 폐기).

### 7.3 CAS 착지 실측 (PR #211)

- dry-run: `mergeGo (GO): … tested base matches current main` → `--apply`:
  `LANDING_OK {"mergeSha": "b75f6162fb85feb8ebdafeff42e07cb09f74b8d1"}`.
- 객관 검증 (API): `main = b75f6162`,
  `parents(M) = [aa34d24d5(B), 55a632c4a(H)]` (INV-1 형태),
  PR #211 `state=closed, merged=true, merge_commit_sha=b75f6162`.
- cert: `5b9bd522f0f8…` (B=`aa34d24d5`, H=`55a632c4a`), ledger `785374a73`.

### 7.4 stale-B 거부 실측

- 착지 후 이전 B(`aa34d24d5`)로 `--apply` 재시도 →
  `LANDING_FAIL {"reasonCode":"MAIN_MOVED","reason":"main is now b75f6162fb85 !=
  expected B aa34d24d5991 — CAS observation mismatch, no mutation attempted"}`,
  exit 1, 재시도 후 main = `b75f6162` 무변경. `beforeOid=B` CAS가 actuator로
  실측 성립.

### 7.5 continuity 실측

- `ax cert continuity --main b75f6162… --cert 5b9bd522….json` →
  `ccPassed (CC_PASSED)`, exit 0 (kind/Ed25519/ancestry/tree/policy/scope 전부 통과).

### 7.6 잔여 결함 제거 (PR #216) + trust-surface 정책 실측

- 착지 후 merge_cli Pass 7(`resolveMergeShapeApi`)이 동일 최상위 tree 파싱
  결함으로 `continuity check skipped` + exit 1 — post-merge API 관측만 실패
  (Landing App 내부 step 4 continuity는 착지 전에 이미 통과).
- PR #216 (`fix/post-merge-shape-tree-parse`, off `b75f6162`):
  `checkedStr(…, "commit", "tree", "sha")` 1곳 + `debt_engine --regen-arch`
  1항목(merge_cli.nim contentHash) — admission green `35976199833`,
  mint green `35976722205`, cert `04daecf7…` (B=`b75f6162`, H=`9d6199b5e`).
- `src/cli/merge_cli.nim`은 trust-surface → `ax merge` 자동 착지가
  `TRUST_SURFACE_MODIFIED`로 거부됨을 **정책대로 실측**. 아키택트 승인 후
  GitHub 네이티브 MERGE(§2 공인 랜딩 메커니즘)로 병합:
  N=`cb7d5b606881…`, `parents(N)=[b75f6162, 9d6199b5e]=[B,H]` (API 실측),
  `ax cert continuity --main N` → `ccPassed`, exit 0.

### 7.7 판정

| 항목 | 결과 |
|---|---|
| merge queue/SHA 행동계약 의존 | 없음 — actuator는 `updateRefs beforeOid` CAS만 |
| 검증 graph == landing graph | parents(M)=[B,H] exact, cert (B,H) exact 바인드 |
| base race | CAS가 원자 차단 (MAIN_MOVED 실측) |
| 헤츠너 fleet 의존 | 없음 — GitHub-hosted + B-pinned verifier |

---

> **부록 — ADR-0027 supersession note (2026-09-29, append-only)**: 본 기록은
> 2026-09-24 시점의 관측·판정이며 아래 노트는 그 사실을 변경하지 않는다. §7.1의
> "external_id `admission-check-{PR}`(App 웹후크 계약 키)·mint artifact 이름·
> 네이티브 job 이름·정책 바인딩은 불변"은 ADR-0027 P2(후보 인증 위임 — GitHub
> Merge Queue)가 명시 개정으로 **de-contractualize**한다: 아티팩트 identity =
> candidate identity(`admission-check-<candidate head>`, candidate head =
> `pull_request.head.sha || merge_group.head_sha || github.sha`). §7.7의
> "merge queue … 의존 없음" 행 또한 큐 위임 채택 이전 시점의 기록이다.
