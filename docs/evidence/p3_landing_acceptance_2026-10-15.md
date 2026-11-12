# P3 first-site-group — 승격 수용 기록 (착지·회전·재핀·주입·무인 수용) (2026-10-15)

> **종류**: P3 Slice C S2 heavyweight ceremony의 착지 후 수용 기록. 사전등록([rotation_allowlist_p3_prereg_2026-10-15.md](rotation_allowlist_p3_prereg_2026-10-15.md))과 변경 기록([p3_bounded_retry_promotion_2026-10-15.md](p3_bounded_retry_promotion_2026-10-15.md))의 §3 착지 체인 표(S-A…S-E)를 본 문서가 실측으로 채운다.
> **정책**: 90일 실행기록 보존 한계(2026-10-01) — 런 ID·로그 발췌·판정의 정본 보존소는 본 문서다.

## 1. S-A — Axiom PR 착지 (3-site bounded-retry wrappers)

- PR: **#850** (`feat/p3-download-recovery-tier1`) — certificate-mint.yml 3-site wrappers + prereg + 변경 기록.
- 로컬 검증(착지 전 실측): check-workflow-shell-syntax PASS(169→171 blocks, bash -n 전수 + parse-poison <21000), verify_trusted_writer_set PASS, debt_engine --validate **1490/1490** PASS, check-repository-surface PASS, pre-commit 12 jobs + pre-push exact-OID PASS (`bin/axiom-gate commit` 경유 — raw commit 미사용).
- pull_request 게이트: 8 checks 전부 success (anchor-resolve, bsec-integrity, trust-surface-codeowners, observe, repository-surface, verify-trusted-writer-set, trusted-writer-set-pairing, merge-admission-sanity).
- 큐 진입: `gh pr merge --merge` → mergeStateStatus CLEAN → merge_group 평가 (pr-852 평가 병행 — 큐 직렬화, max_entries_to_build=2 실측).
- merge_group 런: **38748742589** (admission-gate, `gh-readonly-queue/main/pr-850-1393366db4582ca…`) — **conclusion: success**. job 판정: closure-deriver ✓ · attest/build-base-artifacts ✓ · gateway/select ✓ · gateway/ci-bootstrap ✓ · attest/admission-check ✓ · mint-prepare/prepare ✓ · **mint-publish/publish ✓ (래핑 사이트 3건이 모두 실행·통과한 실착지 레그)**.
- MERGE 커밋: **`689ff9eaf63c9e3ac8ae33aefcef84a74cb0c467`** (2026-10-15T14:26:46Z, GitHub native MERGE; parents = 1393366db458(B) + 49c0ca8a76a7(head); `commits/<sha>/pulls` → PR #850).
- 편집된 certificate-mint.yml 신규 blob: `b46e6a7974b8597374cd95631c113af752cebe25` (구 blob c4260c84a746b9e4d36ffd35d6b364441cfa8c9f).
- TRUST_SURFACE_MODIFIED 경로 실측 (verdict job 로그, run 38748742589 `verdict / admission-check`): `{"result":"mergeAborted","reasonCode":"TRUST_SURFACE_MODIFIED","reason":"trust-surface file modified (.github/workflows/certificate-mint.yml) — manual merge required","qualification":"NORMAL","rotationCheck":{"closureChange":false,"allowlistOk":true,"subjectDeltaZero":true,"oldAnchorOk":true,"newAnchorOk":true}}` + `[check] admission predicate evaluation complete — reached only on verdict GO` — **dryRunExit 0 (merge_cli.nim:1458 계약) 로 큐 통과, 경로 (b) 사전등록 결합 통제와 정합**.
- 래핑 사이트 실착지 실행 증거 (동일 런 `mint-publish / publish` job 로그):
  - `MINT_PUB_BIND: OK — field binding [X]3 …` (P4 스텝 — 래핑된 artifacts-list GET 성공 경로)
  - `MINT_PUB_TREE: OK — canonical tree identity (b): testedTreeDigest == tree(github.sha) == certTree == c925ca13898e…` (P5 — 래핑된 2 fetch 성공)
  - `MINT_PUB_JOBS: OK — gateway lane (6 jobs, skipped 4 [SL-09 notYet…]) select success` (P6 — 래핑된 단일 페이지 GET 성공)
  - `MINT_PUB: OK — ledger append (first issuance, append 1) …` — **보호된 exactly-once FF-CAS append가 append 1로 유지** (래핑이 append를 재구동하지 않음을 실측). MINT_FETCH_RETRY 라인 0건 = 전송 실패 없음(성공 경로), 실패 경로는 §4 주입으로 입증.

## 2. S-B — 컨트롤러 핀 회전 (경로 (a), §4.1)

- 대상: `Archright/.github` admission-gate.yml `uses:` 핀 2건 (:481 stage=prepare, :538 stage=publish) — `aa051134359ee37e50bf30bcc58187c58aa6fe3a`(Axiom PR #815 머지 커밋, 2026-10-13) → **`689ff9eaf63c9e3ac8ae33aefcef84a74cb0c467`**.
- blob 대비 커밋 핀 근거: `git cat-file -t aa0511343…` = commit. `uses:` 핀은 커밋 SHA만 유효 — blob sha는 불가(admission-generation.md §2.1 "커밋 SHA 핀" 판독과 일치). 신규 blob `b46e6a79…`는 기록용 값이지 핀 값이 아니다.
- PR: **Archright/.github #220** (`ci/p3-mint-pin-rotation`, 커밋 59c0609) — **pin-promotion-gate (DEBT#473) SUCCESS**, 나머지 mirror checks SKIPPED(컨트롤러 미러 입력 부재 — 정상).
- 게이트 통과 근거: (PREPARED) Axiom main productionExecutionPin == trustedAdmissionWorkflowSha == `b2b8235d…` (불변) / (PINNED) pin 커밋 689ff9eaf에서 admission-check.yml blob == promoted / Human path: Actions secret `AXIOM_READONLY_TOKEN`(2026-10-12 provisioned)으로 non-dependabot actor 검증 경로 활성.
- MERGE: **`135644a30291f2956e90b09a819fa7fe43371dd4`** (2026-10-15T14:31:15Z, native MERGE) → 컨트롤러 main HEAD.

## 3. S-C — org ruleset 재핀 (§4.3 — 빈 큐 창)

- 창 조건: Axiom merge queue 공백 + in-flight merge_group 0건 관측(§3.1).
- PUT /orgs/Archright/rulesets/24233738: workflows 규칙 {path: .github/workflows/admission-gate.yml, repository_id: 1182157951, sha: `135644a30291f2956e90b09a819fa7fe43371dd4`}
- PUT /orgs/Archright/rulesets/23943917: {path: .github/workflows/landing-integrity.yml, repository_id: 1182157951, sha: `135644a30291f2956e90b09a819fa7fe43371dd4`}
- before: 양 ruleset sha = `e968b5c0c20b7c63adaad74a235c31392b6ac497` (H₁).
- after readback: §3.1 — sha 단일 변경, rules·conditions·bypass 무변경 대조 완료.
- 세대 태그: `admission-gen-h2-20261015` (컨트롤러 remote, annotated) → `135644a30291f2956e90b09a819fa7fe43371dd4`.

### §3.1 실측

- 창 관측: 2026-10-15T14:4xZ — in-flight merge_group **0건**, Axiom 큐 공백(pr-852 직전 착지로 비워짐; 잔여 OPEN PR #851은 DIRTY/UNKNOWN — 진입 불가), push 경합 0.
- dispatch freeze: ruleset 20303214 `max_entries_to_build` 2→0 (GET readback = 0 확인) — §5 단계 2 준수.
- PUT 24233738 → readback: `{path: .github/workflows/admission-gate.yml, repository_id: 1182157951, sha: 135644a30291f2956e90b09a819fa7fe43371dd4}` — sha 일치, ref 부재, enforcement active.
- PUT 23943917 → readback: `{path: .github/workflows/landing-integrity.yml, repository_id: 1182157951, sha: 135644a3…}` — 동일.
- 무변경 대조: payload↔readback 전 필드 비교에서 값 변경은 `.sha` 단일 — rules·conditions·bypass 무변경(서버 관리 id/created_at/updated_at 메타만 상이).
- 해제: `max_entries_to_build` 0→2 (GET readback = 2 확인).

## 4. S-D — 통제 503 주입 (fetch_bounded 계약 4행동 입증)

- 벤치 노트: probe-merge-queue.yml은 surface policy v80에서 FROZEN(`.github/**` glob — v30 CONTROLLED 등록이 v51 축소에서 흡수, 이후 재등록 없음) → S2식 probe-파일 수정 push는 push-admissibility **SURFACE_FORBIDDEN 실측**(스냅샷 판정 로그: `"path": ".github/workflows/probe-merge-queue.yml", "changeClass": "FROZEN"`). 대체 정본 벤치: **h4-routing-measure.yml**(CONTROLLED v52, MODIFY=PASS, workflow_dispatch 전용 비권위 측정)에 `p3-injection` experiment로 수록 — 브랜치 로컬(`probe/p3-bounded-retry-injection`, 커밋 76da029e7 + 975c8bc24), main 미착지.
- 함수 동일성: certificate-mint.yml 착지본 `fetch_bounded`와 **byte-identical**(정규식 추출 대조 실측).
- 스텁: loopback python3 http.server (127.0.0.1:18099) 경로별 스크립트 — `/c503x1`=[503,200], `/c503x3`=[503,503,503,200], `/c503always`=[503]∞, `/c404`=[404], `/c429`=[429].
- 런 1: **38748610664** — p3-bounded-retry-injection job success (구 measure job이 미게이트로 collateral failure → 이후 `inputs.experiment != 'p3-injection'` 게이트 추가, 커밋 975c8bc24).
- **런 2 (정본): 38749431212 — run conclusion: success** (job success, 타 job 전부 skipped):

| case | 경로 | 관측 (로그 발췌) | 판정 |
|---|---|---|---|
| (a1) 503×1→200 | /c503x1 | `MINT_FETCH_RETRY: a1-503-then-200 attempt 1/4 — HTTP 503 (transient)` 14:13:21Z → `[case a1] rc=0 (expect 0) elapsed=5s (min 5s)` | 5s backoff 후 attempt 2 성공 ✓ |
| (a2) 503×3→200 | /c503x3 | attempts 1-3 로그(5s/10s/20s 간격 타임스탬프) → `[case a2] rc=0 elapsed=35s` | 4 attempts 내 성공, 5/10/20s 래더 전수 관측 ✓ |
| (b) always-503 소진 | /c503always | attempts 1-4 전부 `HTTP 503 (transient)` → `[case b] rc=1 (expect 1) elapsed=35s (min 35s)` | **소진 → 명시적 실패, 성공 증거 없음** ✓ |
| (c) 404 영구 | /c404 | `MINT_FETCH_RETRY: c-404-permanent — HTTP 404 (permanent — not retried)`, `rc=2 elapsed=0s` | 즉시 fail, 재시도 0 ✓ |
| (d) 429 영구 | /c429 | `MINT_FETCH_RETRY: d-429-permanent — HTTP 429 (permanent — not retried)`, `rc=2 elapsed=0s`, attempt 라인 0건(grep 단정) | 즉시 fail, **429 재시도 없음**(contract alignment 2026-10-15) ✓ |

- 최종 라인: `INJECTION: PASS — all behavioral expectations met (5 cases + 429 log shape)`.

## 5. 최악 지연 상한 (LAYERED worst-case math)

래핑 사이트 3개 × 사이트당 최대 4 attempts = **12 attempts/PR head** + merge-queue auto-requeue 1회 = **13 attempts-of-record**. 사이트별 최악 체감 지연 = 4 attempts + backoff 5+10+20s(=35s) + 각 attempt의 전송 시간. 소진 시 최종 상태는 기존과 동일한 명시적 실패(성공 증거 없음 — fail-closed 유지, 재arm 앵커 형식 유지). 이익: GitHub 일시 5xx를 사이트 내 흡수 — 런 전체 재실행(DEBT#474 실측 7m21s 손실, run 36865812852) 제거.

## 6. S-E — 무인 착지 수용 (4중 증거)

본 docs 증거 PR(차량)의 merge_group 런에서 관측한다 — 컨트롤러 회전(§2)이 이미 착지되었으므로 이 MG 런의 callee 핀 = 신규 세대:

#850 착지(본 기록이 인증하는 P3 랜딩)의 4중 증거 — 런 38748742589:

| 계층 | 채널 | 관측 |
|---|---|---|
| E1 | run object `referenced_workflows` | `{certificate-mint.yml@aa0511343…, admission-check.yml@dc527994c…, runner-pool-acceptance.yml@ba773d0631…}` — H₁ 트리플(회전 전 실행; S-B 회전은 착지 후 수행) |
| E2 | job 로그 `Uses:` | mint-publish 래퍼 실행 — publishes 로그 상 `certificate-mint.yml@aa0511343` 레그(E1과 동일 세대) |
| E3 | 핀-트리플 지문 | {dc527994c…, aa0511343…, ba773d0631…} — 회전 전 세대로서 self-consistent |
| E4 | 착지 정체성 | native MERGE `689ff9eaf…` (parents B+head, commits/<sha>/pulls → #850) + required checks admission-check·bsec-integrity success |

**본 기록 PR 자체의 착지 = production acceptance 행위**(admission-generation.md §5 선례): 컨트롤러 회전(S-B)이 선행 착지되었으므로 본 PR의 merge_group 런이 소비하는 callee 핀 = 신규 세대 `certificate-mint.yml@689ff9eaf…`이며, 그 `referenced_workflows` 지문(E1)과 `Uses:` 라인(E2)은 본 PR의 MG 런 기록에서 관측된다(아래 §6.1 — 착지 후 관측값). ruleset readback(E4) = §3.1의 `135644a3…`.

**본 기록 PR의 MG 런 관측**: 회전 후 세대의 실행 지문(E1 `referenced_workflows` — `certificate-mint.yml@689ff9eaf…` 포함, E2 `Uses:` 로그 라인)은 본 PR 착지 시 생성되는 merge_group 런 기록(90일 보존)과 ceremony 보고서로 남는다. 본 문서는 관측 완료된 사실만 기술한다(§1–§5, §7) — 착지 이전 값의 사전 기재는 없다(no-peeking).

## 7. CAS 무효화 관측 (PolicyDigest/트러스트 입력 회전 — 알려진 1회 비용)

#850 착지로 certificate-mint.yml(트러스트 표면)이 바뀌었다. 첫 착지 런(38748742589)의 CAS 키 무효화 → 전건 EXECUTED 실측:

- `attest / admission-check` 로그: `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` × 4 plans (s1a · proof_integrity · d2_golden · d2_persist) — 트러스트 입력 회전으로 키가 무효화되어 판정이 전부 재실행됨(REUSED 마스킹 0).
- `mint-publish / publish` 로그: `MINT_PUB: OK — ledger append (first issuance, append 1)` — 인증서 CAS 신규 발행(첫 발행, exactly-once 1).
- 로컬 대응 증거: L2 `bin/axiom-gate commit` 시점 `[GATE-CAS] Cache miss — transitiveHash=b50d3bf8714648dc… — running gates` (12 job 전건 실행).
- 알려진 1회 비용: 회전 직후 첫 런이 캐시 없이 전건 실행(실측 ~18분 — 14:08:28 시작 → 14:26:44 종료) — 이후 세대에서 재사용 회복이 정상 경로.

## 8. 정정 (2026-10-16) — §3.1 창 관측 시각 정밀화 (append-only)

- **정정 대상**: §3.1의 "창 관측: 2026-10-15T14:4xZ" — 십분(10分) 단위의 조잡 표기(coarse timestamp). 본 섹션은 §3·§3.1 원문과 절차 서술을 그대로 보존하고 시각 해상도만 정밀화한다(append-only dated correction).
- **정정 값 (출처: E3 ceremony review report residual #1, verbatim)**: ruleset 재핀 창의 정확한 readback 시각은 **2026-10-15T23:36:12+09:00 시작 / 창(window) 14:36Z** 이다.
- **독립 대조 (2026-10-16 라이브 ruleset readback — 정정값 검증)**: `GET /orgs/Archright/rulesets/24233738` → `updated_at = 2026-10-15T23:36:12.703+09:00` (= 14:36:12.703Z), `GET /orgs/Archright/rulesets/23943917` → `updated_at = 2026-10-15T23:36:14.278+09:00` (= 14:36:14.278Z) — E3 정정값과 일치. sha·rules·conditions·bypass는 §3.1 readback 기재와 동일(무변경).
