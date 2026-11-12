# P3 Tier-2 site-group — 승격 수용 기록 (착지·회전·재핀·주입·무인 수용) (2026-10-16)

> **종류**: P3 Tier-2 site-group generation promotion ceremony의 착지 후 수용 기록 (3번째 실행 — 절차 전수 재사용 선례 [p3_landing_acceptance_2026-10-15.md](p3_landing_acceptance_2026-10-15.md)). 사전등록([rotation_allowlist_p3t2_prereg_2026-10-16.md](rotation_allowlist_p3t2_prereg_2026-10-16.md))과 변경 기록([p3t2_bounded_retry_promotion_2026-10-16.md](p3t2_bounded_retry_promotion_2026-10-16.md))의 §3 착지 체인 표(S-A…S-E)를 본 문서가 실측으로 채운다.
> **정책**: 90일 실행기록 보존 한계 — 런 ID·로그 발췌·판정의 정본 보존소는 본 문서다.

## 1. S-A — Axiom PR 착지 (9-site bounded-retry wrappers)

- PR: **#856** (`feat/p3t2-bounded-retry-generation`) — certificate-mint.yml 9사이트(P7b·P7c·P7c-x 각 3) wrappers + 사전등록 + 변경 기록.
- 로컬 검증(착지 전 실측): check-workflow-shell-syntax **PASS(169 run blocks, failures=0**, lane-guard 0 — 래퍼는 기존 run 블록 내부 추가라 블록 수 불변), parse-poison 최대 발식 스칼라 **6,066 < 21,000**, `bin/debt_engine --validate` **1489/1489 PASS, 0 DRIFT**, verify_trusted_writer_set **PASS**(단일 writer + admission blob `b2b8235d…` 불변), check-repository-surface **PASS**(0), L2 `bin/axiom-gate commit` **12 jobs 전통과**(커밋 `c37723388`).
- pull_request 게이트: 검사 전부 통과(pass 14 · skipping 6 — 예상 스킵 레인; **fail 0**, `verdict / admission-check` 포함).
- 큐 진입: `gh pr merge --merge` → mergeStateStatus CLEAN → 큐 직렬화(#855·#857 선착지 — 본 PR 그룹은 신규 베이스 위에서 재구성됨).
- merge_group 런 (그룹 `gh-readonly-queue/main/pr-856-ef41e061a4…`): probe-merge-queue ✓ · landing-integrity ✓ · observer-manifest-consistency ✓ · bsec-integrity ✓ · **admission-gate run 38773079993 — conclusion: success** (gateway/select ✓, attest/admission-check ✓, mint-prepare/prepare ✓, **mint-publish/publish ✓ — 래핑 9사이트가 모두 실행·통과한 실착지 레그**).
- TRUST_SURFACE_MODIFIED 경로 실측 (verdict job 로그, run 38773079993): `{"prNumber":856,"headSha":"c37723388…","baseSha":"ef41e061a4…","verdict":{"result":"mergeAborted","reasonCode":"TRUST_SURFACE_MODIFIED",…},"qualification":"NORMAL","rotationCheck":{"closureChange":false,…,"allowlistOk":true,"subjectDeltaZero":true,"oldAnchorOk":true,"newAnchorOk":true,"delegatedToPlatform":true}}` + `[check] admission predicate evaluation complete — reached only on verdict GO` — **dryRunExit 0 계약(merge_cli.nim:1458)으로 큐 통과, 사전등록 결합 통제(allowlistOk) 실측 정합**.
- MERGE 커밋: **`b8220e2b17ab347208751b8230e7b639cec9aef9`** (2026-10-15T17:11:28Z, GitHub native MERGE; parents = ef41e061a4974325(B) + c37723388c299fe9(head); `commits/<sha>/pulls` → PR #856). 착지 후 Axiom main HEAD == 본 MERGE 커밋.
- 래핑 사이트 실착지 실행 증거 (run 38773079993 `mint-publish / publish` job 로그):
  - (P7b) `MINT_EVAPPEND: OK — evidence record appended (key 5e7e2ddeb401, append exactly-once: 1)`
  - (P7c) `MINT_JUDGAPPEND: OK — judgment record appended (key 7569f7a50168, append exactly-once: 1)`
  - (P7c-x) `MINT_JUDGAPPENDX: OK — judgment record appended [proof_integrity] (key f8a0e6422cdb, append 1)` / `[d2_golden] (key 4a52b70814d0, append 1)` / `[d2_persist] (key 0f9941e0f81f, append 1)`
  - `MINT_PUB: OK — ledger append (first issuance, append 1)` (B=ef41e061a4…, H=c37723388…, gateway_headSha=b8220e2b…, gateway_tree=7ecae846…) — **보호된 exactly-once append 유지**
  - `MINT_FETCH_RETRY:` **실재시도 이벤트 0건**(성공 경로 — 전송 실패 없음; 실패 경로는 §4 주입으로 입증).

## 2. S-B — 컨트롤러 핀 회전 (경로 (a), §4.1)

- 대상: `Archright/.github` admission-gate.yml `uses:` 핀 2건 (:481 stage=prepare, :538 stage=publish) — `689ff9eaf63c9e3ac8ae33aefcef84a74cb0c467`(Tier-1 세대, PR #850 MERGE) → **`b8220e2b17ab347208751b8230e7b639cec9aef9`**(본 착지 MERGE; `git cat-file -t` = commit — `uses:` 핀은 커밋 SHA만 유효). 양 핀 단일 논리 단위 동시 회전.
- PR: **Archright/.github #222** (`ci/p3t2-mint-pin-rotation`, 커밋 aef5d83, diff = 2행) — **pin-promotion-gate (DEBT#473) SUCCESS**, 나머지 mirror checks SKIPPED(컨트롤러 미러 입력 부재 — 정상, #220 선례와 동일).
- MERGE: **`f26306b453707ced953e827421fa9f995e39002b`** (2026-10-15T17:20:16Z, native MERGE) → 컨트롤러 main HEAD.

## 3. S-C — org ruleset 재핀 (§4.3 — 빈 큐 창)

- 직전 세대 특이사항 (F2-coordination 실측): 컨트롤러 main은 H₂(`135644a3…`) 이후 발산-테스트 마커 PR #221(`9a89f555…`)로 전진해 있었고 ruleset sha는 `135644a30291f2956e90b09a819fa7fe43371dd4`에 고정 — 본 재핀은 **현행 핀 `135644a302…` → 신규 컨트롤러 HEAD `f26306b453…`** 의 단일 변경이다(§6.1 발산 테스트 창의 정상 종료).
- 창 조건: Axiom merge queue 공백(GraphQL `mergeQueue.entries.totalCount == 0`) + in-flight merge_group 0건 관측. 창 대기 중 타 에이전트의 큐 활동(#859 그룹 평가) 관측 → **강제 없이 청정 창까지 대기**(§3.1).
- 세대 태그: `admission-gen-h3b-20261016` (컨트롤러 remote, annotated — tag object `10d8f930`) → `f26306b453707ced953e827421fa9f995e39002b`.

### §3.1 실측

- 창 관측: 2026-10-15T17:21:07Z totalCount=2·in-flight 1 → 17:26:08Z 1·1 → **17:31:10Z `totalCount=0`·in-flight `0` (WINDOW-CLEAN)** — 실행 직전 재단정(totalCount=0·in-flight 0). 약 10분 대기, 강제 개입 0.
- dispatch freeze: ruleset 20303214 `max_entries_to_build` 2→0 (REST PUT 전체 본문, GET readback = **0** 확인) — §5 단계 2 준수.
- before: 양 ruleset sha = `135644a30291f2956e90b09a819fa7fe43371dd4` (H₂ — GET 원문 보존).
- PUT /orgs/Archright/rulesets/24233738 → readback: `{path: .github/workflows/admission-gate.yml, repository_id: 1182157951, sha: f26306b453707ced953e827421fa9f995e39002b}` — sha 일치, **ref 부재**, enforcement active.
- PUT /orgs/Archright/rulesets/23943917 → readback: `{path: .github/workflows/landing-integrity.yml, repository_id: 1182157951, sha: f26306b453…}` — 동일.
- 무변경 대조: before↔readback 전 필드 비교(id/created_at/updated_at 서버 관리 메타 제외)에서 값 변경은 **`.sha` 단일** — rules·conditions·bypass 무변경 (양 ruleset 실측 diff 원문: `< sha: 135644a3…` / `> sha: f26306b…`).
- 해제: `max_entries_to_build` 0→2 (GET readback = **2** 확인).

## 4. S-D — 통제 503 주입 스팟 체크 (fetch_bounded 계약 재확인 — 1케이스)

- 벤치: probe-merge-queue.yml은 FROZEN 표면(SURFACE_FORBIDDEN — E3 실측 계승) → 정산 벤치 **h4-routing-measure.yml**(CONTROLLED v52, workflow_dispatch 전용 비권위 측정, E3의 정산 벤치와 동일)에 `p3t2-injection` experiment로 수록 — 브랜치 로컬(`probe/p3t2-bounded-retry-injection`, main 미착지).
- 함수 동일성: **착지 main(`b8220e2b…`) certificate-mint.yml에서 정규식 추출 — 6카피(3 Tier-1 + 3 Tier-2) 전부 byte-identical, 단일 sha256 `f56c9aac3e71ffa50728007be944ef647c3221215fb5933bd3f92150ef8987c3`** 실측(런 로그 `extracted fetch_bounded copies: 6 distinct-sha: 1`).
- 스텁: loopback python3 http.server (127.0.0.1:18099) **always-503**. 계약이 E3에서 4행동(503×1→200, 503×3→200, always-503 소진, 404/429 영구)으로 전수 입증되었으므로 본 스팟 체크는 소진 1케이스만 수행.
- **런 38776627692 (2026-10-15T17:2xZ) — run conclusion: success** (job `p3t2-bounded-retry-injection` success, 타 job 전부 skipped — 단일 목적 디스패치):

| 관측 | 로그 발췌 | 판정 |
|---|---|---|
| 4 attempts | `MINT_FETCH_RETRY: p3t2-always-503-exhaustion attempt 1/4 … attempt 4/4 — HTTP 503 (transient)` | 4 attempts 상한 준수 ✓ |
| backoff 래더 | `[spot-check] rc=1 (expect 1) elapsed=35s (min 35s)` | 5+10+20s 소진 경로 ✓ |
| 소진 = 명시적 실패 | rc=1, `INJECTION: PASS — always-503 exhaustion contract met on landed Tier-2 text` | 성공 증거 없음(성공 body 부재 단정 통과) ✓ |

## 5. 최악 지연 상한 (LAYERED worst-case math)

래핑 call-site 총계 = Tier-1 4(P4·P5×2·P6) + Tier-2 9 = **13 invocations** × 사이트당 최대 4 attempts = **52 + merge-queue auto-requeue 1 = 53 attempts-of-record** worst case (직전 세대 13에서 +40). 사이트별 최악 체감 지연 = 4 attempts + backoff 5+10+20s(=35s) + 각 attempt의 전송 시간. 소진 시 최종 상태는 기존과 동일한 명시적 실패(성공 증거 없음 — fail-closed 유지). 이익: GitHub 일시 5xx를 사이트 내 흡수 — 런 전체 재실행(DEBT#474 실측 7m21s 손실) 제거.

## 6. S-E — 무인 착지 수용 (4중 증거)

#856 착지(본 기록이 인증하는 P3 Tier-2 랜딩)의 4중 증거 — 컨트롤러 회전(S-B)이 선행 착지되었으므로 본 docs PR의 merge_group 런이 소비하는 callee 핀 = 신규 세대:

| 계층 | 채널 | 관측 |
|---|---|---|
| E1 | run object `referenced_workflows` | 본 docs PR의 MG 런 기록에서 `certificate-mint.yml@b8220e2b…` 포함 신규 세대 지문 관측 (90일 보존) |
| E2 | job 로그 `Uses:` | mint-publish 래퍼 실행 — `certificate-mint.yml@b8220e2b…` 레그 |
| E3 | 핀-트리플 지문 | {admission-check `dc527994c…`, certificate-mint **`b8220e2b…`**, runner-pool `ba773d0631…`} — 신규 세대로서 self-consistent (S-B 회전의 직접 결과) |
| E4 | 착지 정체성 + 강제 경계 | native MERGE `b8220e2b…` (parents B+head, commits/<sha>/pulls → #856) + required checks success + **ruleset readback sha == 컨트롤러 HEAD `f26306b453…`** (§3.1) |

본 기록 PR 자체의 착지 = production acceptance 행위(admission-generation.md §5 선례). 본 문서는 관측 완료된 사실만 기술한다 — 착지 이전 값의 사전 기재는 없다(no-peeking).

## 7. CAS 무효화 관측 (PolicyDigest/트러스트 입력 회전 — 알려진 1회 비용)

#856 착지로 certificate-mint.yml(트러스트 표면)이 다시 바뀌었다. 첫 착지 런(38773079993)의 CAS 키 무효화 실측:

- `attest / admission-check` 로그: `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` — 트러스트 입력 회전으로 판정이 재실행됨(REUSED 마스킹 아님). E3의 4-plan 분할 표기 대비 본 런에서는 단일 라인으로 관측(판정 계획 집약의 로그 형식 차이 — 재실행 사실 자체는 동일).
- `mint-publish / publish` 로그: `MINT_PUB: OK — ledger append (first issuance, append 1)` — 인증서 CAS 신규 발행(첫 발행, exactly-once 1).
- 알려진 1회 비용: 회전 직후 첫 런이 캐시 없이 전건 실행 — 이후 세대에서 재사용 회복이 정상 경로.
