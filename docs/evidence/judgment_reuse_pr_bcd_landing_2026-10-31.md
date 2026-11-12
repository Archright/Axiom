# judgment-reuse PR-B/C/D 착지 기록 — 규범 면 세대 전진·재사용 재개 실측 (2026-10-31)

> **관측 시각**: 2026-10-31T12:10Z (UTC, GET-only 전수). **문서 성격**: 착지 기록(Reporter).
> **권위 선언**: landing truth = GitHub MERGE commit. 본 문서는 Reporter다 — GitHub의 판정을 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 측정 절차는 `docs/evidence/judgment_key_v5_measurement_prereg_2026-10-31.md`의 등록을 존중하며 본 문서는 독립 관측 원문이다.
> **게시 구조**: 본 문서 자체는 후속 docs-only PR(사후 증거 공개 — `gpa_v1_landing_2026-10-22.md` 선례 레인)로 main에 게시된다. PR은 자신의 착지 결과를 같은 커밋에 담을 수 없다(시간 역설) — 본 문서의 착지(§5)는 게시 시점 기대치만 기술하고 확정 상태는 GitHub 상태로 관측한다.
> **실험 설계**: A(#1145, 비규범→REUSED) → B(#1146, 규범 1줄→EXECUTED+mint) → C(#1147, 비규범→S1 REUSED 재개) → D(본 문서 게시). C셀 판정 기준 = 4행 판정표: S0 재사용=위반 / S1 EXECUTED=정상 / S1 유효증거 REUSED=정상 / 판별불가=UNKNOWN.

## §1. 착지 체인

| PR | 성격 | head SHA | merge commit (40-hex) | mergedAt (UTC) | merge_group admission run (wall) |
|---|---|---|---|---|---|
| #1145 | 비규범 docs-only(측정 절차 사전등록) | `7da9182faa4253d150471b8f7a27e59c32916499` | `9c007db409e7e623edfcd12972c2ddef72e904d2` | 2026-10-31T10:49:11Z | 41193592538 (success, 10:38:42Z→10:48:54Z, 612s) |
| #1146 | 규범 면 1줄(`docs/agents/logging.md`) | `4cef7a91488663b706a7e7a0d39e5ab55fdf0998` | `04d2c409d2bc5594314a455dc35714383c7014ec` | 2026-10-31T11:27:31Z | 41196023170 (success, 11:14:23Z→11:27:15Z, 772s) |
| #1147 | 비규범 docs-only(Probe-C 사전등록) | `9e227e9ae0a0b19f607b0e2f597c06a5c5cd8292` | `32d102874fc3967aa9f68b4bf23c208cf955e286` | 2026-10-31T11:58:47Z | 41198334250 (success, 11:47:49Z→11:58:41Z, 652s) |
| #1150(D) | 비규범 docs-only(본 문서) | `<본 PR head>` | (시간 역설 — 게시 후 GitHub 관측) | (동일) | `<게시 후 관측>` |

세 PR 모두 native MERGE(parents=2), GitHub merge queue 경유, dequeue·재도크 0건(§6).

## §2. A셀 — #1145 (비규범 → REUSED, 기대 충족)

- lane-0(s1a, job 124515460207): `judgment-decision.json` `basis=REUSED`, `evidenceKey=7fe9623ad931099bc275198c18fccd59570b6991c3b3244ef8554e4bc9e66f6d`, `landingVenue=merge_group`, `probeTreeOid=67e7993bdeaf07686ccc14fd621b0b8933c35317`, rootRecord{evidenceKey·executionEpoch `89ea9a266080…`·payloadSha256 `e24710b36244…`}. 로그 원문: `AXIOM_JUDGMENT_CAS: REUSED — record 7fe9623ad931 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` (2026-10-31T10:41:53Z).
- lane-1(job 124515460199): proof_integrity `basis=REUSED` evidenceKey `578fc904eb8b…`, d2_golden `basis=REUSED` `5dda82170208…`, d2_persist `basis=REUSED` `9707696c8353…`.
- `landing_observe.sh 1145` VERDICT: **TERMINAL_SUCCESS**(MERGED ∧ mergedAt ∧ mergeCommit.oid ∧ parents=2, graphql↔rest consistent).

## §3. B셀 — #1146 (규범 면 1줄 → EXECUTED + mint, 기대 충족)

- lane-0(s1a, job 124522620714): `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` (2026-10-31T11:17:47Z). `judgment-decision.json` `basis=EXECUTED`, `evidenceKey=7f58908b6d59e670aa6b24ec28f015d4788e65070b01cc01eb3b5a03f93cb540`, `probeTreeOid=1ce1ae0161cd975b34e1960d6a8dbfb5e3562f7c`, `reason="no record for the current closure (fresh judgment)"`. `exec-record[s1a] verdict=PASS basis=EXECUTED evidenceKey=7f58908b6d59 evidenceSha256=e24710b36244` + `PASS — tests/unit/test_s1a_lean_golden.nim (basis=EXECUTED — fresh judgment measured)` (11:22:25Z).
- lane-1(job 124522620772): `exec-record[proof_integrity] verdict=PASS basis=EXECUTED evidenceKey=f60864fa4abd` (11:19:49Z) · `exec-record[d2_golden] verdict=PASS basis=EXECUTED evidenceKey=b078f31029ce` (11:21:03Z) · `exec-record[d2_persist] verdict=PASS basis=EXECUTED evidenceKey=77008e499453` (11:21:26Z).
- **mint(P7c) 관측 — 사이드 ref `refs/heads/axiom/evidence-cas` 전진**: `9dceed1b2`(A 착지분) → `7a1fd6342`, append 5건: `47092d65e` 11:26:33Z `71b25391d828…`(착지 증거) → `3fa223e70` 11:26:39Z `7f58908b6d59…`(s1a) → `bcf2e74a9` 11:26:45Z `f60864fa4abd…` → `b266044ac` 11:26:49Z `b078f31029ce…` → `7a1fd6342` 11:26:53Z `77008e499453…`. 4주체 S1 레코드의 최초·유일 발화 주체 = #1146 착지 런(외부 선점 경로 관측 0건).
- probeTreeOid 전진: `67e7993bde…`(A) → `1ce1ae0161cd…`(B, A 트리 + 규범 1줄). 레인 wall 연장: lane-0 356초·lane-1 297초(A REUSED 205초 대비).
- `landing_observe.sh 1146` VERDICT: **TERMINAL_SUCCESS**.

## §4. C셀 — #1147 (비규범 → S1 REUSED 재개, 4행 판정표 "정상·기대치")

- lane-0(s1a, job 124529257412): `AXIOM_JUDGMENT_CAS: REUSED — record 7f58908b6d59 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` (2026-10-31T11:51:10Z). `judgment-decision.json` `basis=REUSED`, `evidenceKey=7f58908b6d59e670aa6b24ec28f015d4788e65070b01cc01eb3b5a03f93cb540` — **#1146이 mint한 S1 레코드와 64-hex 완전 일치**, `probeTreeOid=da66a4902f81b85f610a27e5f2fd846dc255e1a1`.
- lane-1(job 124529257373): proof_integrity `basis=REUSED evidenceKey=f60864fa4abd` · d2_golden `basis=REUSED b078f31029ce` · d2_persist `basis=REUSED 77008e499453` — 4주체 전부 S1(B mint) 계열. **S0(`7fe9623ad931` 계열) 재사용 관측 0건 — 위반 아님.**
- probeTreeOid `1ce1ae0161cd…`(B) ≠ `da66a490…`(C) — 트리가 상이해도 9성분 키 일치(트리 OID는 키에 없음, N-class docs는 배제)의 물증.
- 사이드 ref 재전진: `7a1fd6342` → `84e0cb69f`(REUSED 착지의 append — exactly-once 재결속).
- `landing_observe.sh 1147` VERDICT: **TERMINAL_SUCCESS**.
- **판정**: "새 세대에서 1회 원실행(#1146) 후 재사용이 재개된다"(계약 `test_judgment_cas_contract.md:116`)의 규범-문서-차량 최초 실측. **무효화(B) → 재발화(B mint) → 재개(C) 완전 주기 관측.**

## §5. D셀 — 본 문서 게시 PR (기대치 — 시간 역설)

- 기대: `basis=REUSED` — 본 문서는 N-class docs-only delta다(A·C셀 물증: docs/evidence만의 delta는 9성분 키 불변). 단, 게시 대기 중 병렬 워크스트림 두 건이 착지해 최신 유효 mint 계열이 교체됐다(2026-10-31 관측): #1148(규범 `docs/spec/gh_run_observation_quirks.md` 변경 → 세대 전진, EXECUTED mint: s1a `1352a2758811`·proof_integrity `28e8abb4ccd6`·d2_golden `1c59aa6efd03`·d2_persist `6b1132fa517c`) 및 #1149(EXECUTED — `no record for the current closure (fresh judgment)`, mint: s1a `f79f41b9fd3e`·proof_integrity `bfcda6c49f77`·d2_golden `4d7584921aaa`·d2_persist `343028f40351`; 사이드 ref 최상위 5-append가 이 계열. C셀 물증상 docs/evidence-only delta는 키 불변이므로 #1149의 closure 변화원은 experiments/ 범위·spec 성분으로 추정).
- 따라서 D셀의 재사용 레코드 기대치는 S1 계열(`7f58908b6d59`)도 #1148 계열도 아닌 **#1149 mint 계열(`f79f41b9fd3e` 등)**이다 — 4행 판정표 3행 "새 세대에 이미 유효한 증거 존재 → 해당 증거 재사용(정상)"의 실측 차량. S0(`7fe9623ad931` 계열) 재사용이 관측되면 위반.
- 착지 전 운영 사건(실측): 최초 push 후 preflight가 `MINT_A0_ACTIVATION: FAIL — PR #1150 base.sha '32d102874fc3' != baseSha input '696f7ea2567f' (fail-closed)`로 낡은 base 기준 검증 시도를 차단했다(원인: 대기 중 #1148/#1149 착지로 main tip 전진). `origin/main`(`ee87f0a70`) rebase → head 재push(로컬 push-admissibility 14종 PASS) → auto-merge 재arm으로 해소.
- 확정 상태는 본 PR 착지 후 GET 관측(§부록 A 명령)으로 별도 확보하며 본 문서는 게시 후 편집하지 않는다.

## §6. 판정 무결성 — L1 바인딩 (이름 5개가 아니라 SHA 귀속)

각 merge_group head 커밋의 check-runs(REST, 페이지네이션 전수)에서 5 required context가 전부 `conclusion=success`로 귀속:

| head (merge_group G) | admission-check | bsec-integrity | debt-registry-gate | generation-acceptance | axiom-operational-slice |
|---|---|---|---|---|---|
| `9c007db40…` (A) | success | success | success | success | success |
| `04d2c409d…` (B) | success | success | success | success | success |
| `32d102874…` (C) | success | success | success | success | success |

admission-gate 런 3건 공통: workflow_id `386419787`, path `.github/workflows/admission-gate-v2.yml`(org 소재), `run_attempt=1`, conclusion `success`, head_sha = 각 G(skipped/neutral 0건). 각 런의 tested tree(probeTreeOid)는 §2-§4에 귀속.

## §7. 큐 이탈·재등록 사건

0건 — #1145·#1146·#1147 모두 1회 큐 진입으로 착지(재도크·dequeue 없음, landing_observe [QUEUE] 관측).

## 부록 A. 재현 명령 (GET-only)

- PR 메타: `gh api repos/Archright/Axiom/pulls/<N> --jq '[.created_at, .merged_at, .merge_commit_sha, .head.sha]'`
- merge_group 런: `gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&per_page=30" --jq '.workflow_runs[] | select(.head_branch | test("^gh-readonly-queue/main/pr-<N>-"))'`
- 잡·마커: `gh api "repos/Archright/Axiom/actions/runs/<id>/jobs" --jq '.jobs[] | [.id, .name, .conclusion]'` → `gh api --allow-escape-sequences "repos/Archright/Axiom/actions/jobs/<job_id>/logs" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "AXIOM_JUDGMENT_CAS|basis=|no record|go-exec"`
- lane 아티팩트: `gh api repos/Archright/Axiom/actions/runs/<id>/artifacts` → `go-judgment-lane-{0,1}-<head>-<attempt>.zip` 내 `judgment-decision*.json`(`.basis`·`.evidenceKey`·`.probeTreeOid`·`.rootRecord`), `judgment-record-<head>-<attempt>.zip`, `tested-tree-digest.zip`
- check-runs: `gh api "repos/Archright/Axiom/commits/<G>/check-runs?per_page=100" (&page=2)` — 5 required context conclusion
- 사이드 ref: `gh api repos/Archright/Axiom/git/ref/heads/axiom/evidence-cas --jq '.object.sha'` + `gh api "repos/Archright/Axiom/commits?sha=axiom/evidence-cas&per_page=10"`
- 종결: `tools/ci/landing_observe.sh <N>`

## 부록 B. 조사 경계·UNKNOWN 명시

- org 게이트(`Archright/.github`, workflow_id 386419787) 내부 트리거-venue 매핑은 본 저장소 밖 — callee 측 fail-closed 증거(`admission-check.yml` M-tree 환경변수·`venue==landing` 조건)로 간접 확인.
- judgment ledger 전체 dump는 관측하지 않았다 — 레코드 키는 lane 아티팩트·잡 로그 원문·사이드 ref append 커밋으로 귀속.
- `docs/spec/test_judgment_cas_contract.md:101,116`의 v1.0.3 시대 문장(피험 트리=B^{tree} 전제)은 현행 §4.2(v1.0.5, M-tree)과 드리프트 — 본 기록의 키 판독은 코드(`admission-check.yml:3212,3216`)와 실측(probeTreeOid=각 PR M^tree) 기준. 드리프트 정리는 별도 follow-up(규범 수정 자체가 세대 전진).
- 본 슬라이스의 코드 diff: `docs/agents/logging.md` 1줄 + `docs/evidence/judgment_reuse_probe_c_2026-10-31.md` + 본 문서 — 코드·워크플로·게이트·정책 수정 0건(불변식 위반 관측 0건 → 수정 단계 미발동).
