# P3 FINAL site-group — 승격 수용 기록 (착지·회전·재핀·주입·무인 수용) (2026-10-16)

> **종류**: P3 FINAL site-group generation promotion ceremony의 착지 후 수용 기록 (4번째 실행 — 절차 전수 재사용 선례 [p3t2_landing_acceptance_2026-10-16.md](p3t2_landing_acceptance_2026-10-16.md)). 사전등록([rotation_allowlist_p3final_prereg_2026-10-16.md](rotation_allowlist_p3final_prereg_2026-10-16.md))과 변경 기록([p3final_bounded_retry_promotion_2026-10-16.md](p3final_bounded_retry_promotion_2026-10-16.md))의 §3 착지 체인 표(S-A…S-E)를 본 문서가 실측으로 채운다.
> **정책**: 90일 실행기록 보존 한계 — 런 ID·로그 발췌·판정의 정본 보존소는 본 문서다.
> **정정 기록**: 본 세리머니 진행 중 PR #865에 오기재된 "ROT-Landing Receipt" 코멘트(id 6206749684 — 존재하지 않는 tarball·오카피 수·stale 라인번호)는 병합 전 삭제되었고 정정 코멘트(id 6206844367)로 실측값이 재고정되었다. 본 문서는 정정 후 값을 정본으로 한다.

## 1. S-A — Axiom PR 착지 (24-site bounded-retry wrappers)

- PR: **#865** (`feat/p3final-bounded-retry-generation`) — certificate-mint.yml 잔여 24사이트(zip 4 + JSON GET 18 + raw contents GET 2) wrappers + 사전등록 + 변경 기록. 내용 커밋 `7d2a8f347`.
- 로컬 검증(착지 전 실측): check-workflow-shell-syntax **PASS(173 run blocks, failures=0**, lane-guard 0; 파스 독 최대 발식 스칼라 **10,831 < 21,000** — jobs/publish/steps[9]/run), `bin/debt_engine --validate` **1489/1489 PASS, 0 DRIFT**, verify_trusted_writer_set **PASS**(단일 writer + admission blob `f2ad3b03b3…` 불변), check-repository-surface **PASS**(0). L2 `bin/axiom-gate commit` 12 jobs 통과(커밋 `7d2a8f347`).
- 함수 카피 단일성: `fetch_bounded` 정의 **15카피 distinct-sha 1** (`802f8ddeaef7cb0c95d855435e6b4588835b628f5b71ffcc80334f03a54024a1`), bare `curl -fsSL` **0건**(착지 본문 — §5 grep audit).
- pull_request 게이트: PR-venue 런 38841755845 — 전 required check pass(ci-bootstrap 4m44s, mint-prepare/prepare 31s 포함; 예상 skipping 레인 제외 **fail 0**).
- 큐 진입: `gh pr merge --merge` → mergeStateStatus CLEAN → 큐 직렬화(#866 선착지 — 본 PR 그룹은 재구성 후 착지).
- merge_group 런 (본 PR 착지 평가): **run 38842619666 — conclusion: success** (head `7072f938231f…`; probe-merge-queue ✓ · landing-integrity ✓ · observer-manifest-consistency ✓ · bsec-integrity ✓ · **mint-prepare/prepare ✓ · mint-publish/publish ✓ · verdict/admission-check ✓**).
- MERGE 커밋: **`7072f938231f579ed851c12ad9bbdba6d05cb4ec`** (2026-10-16T03:08:51Z, GitHub native MERGE; parents = 493442a86(B) + 7d2a8f347(head); `commits/<sha>/pulls` → PR #865). 
- TRUST_SURFACE_MODIFIED 경로 실측 (verdict job 로그, run 38842619666): `{"prNumber":865,…,"verdict":{"result":"mergeAborted","reasonCode":"TRUST_SURFACE_MODIFIED",…},"qualification":"NORMAL","rotationCheck":{…,"allowlistOk":true,"subjectDeltaZero":true,…}}` + `[check] admission predicate evaluation complete — reached only on verdict GO` — **dryRunExit 0 계약으로 큐 통과, 사전등록 결합 통제(allowlistOk) 실측 정합**.
- 착지 런 mint 레그 실측 (run 38842619666 — 이 런이 소비한 callee는 직전 세대 핀 `b8220e2b…`로, 신규 본문의 소비 개시는 S-B 회전 후다 — F2 세리머니와 동일 구조):
  - `MINT_PUB: OK — ledger append (first issuance, append 1)` — provenance: B=493442a86…, H=7d2a8f347…, gateway_headSha=7072f9382…, gateway_tree=fb5c6c50…, cert_sha256=64a916528e… (보호된 exactly-once append 유지)
  - `MINT_EVAPPEND: OK — evidence record appended (key b37fae9f1ffe, append exactly-once: 1)`
  - `MINT_FETCH_RETRY:` **실제 이벤트 0건**(성공 경로 — 나머지 18건은 run 블록 스크립트 덤프 라인; 실패 경로는 §4 주입으로 입증).

## 2. S-B — 컨트롤러 핀 회전 (경로 (a), §4.1)

- 대상: `Archright/.github` admission-gate.yml `uses:` 핀 2건 (:481 stage=prepare, :538 stage=publish) — `b8220e2b17ab347208751b8230e7b639cec9aef9`(Tier-2 세대, PR #856 MERGE) → **`7072f938231f579ed851c12ad9bbdba6d05cb4ec`**(본 착지 MERGE; `uses:` 핀은 커밋 SHA만 유효). 양 핀 단일 논리 단위 동시 회전(diff = 2행).
- 보존 실측(회전 전 라이브 판독): admission-check 핀 :430·:650 = `64f78ab7d178bb9570ad05f4eef9189530f784c8`(G2 h4b 현행) **불변**, runner-pool :256·:573 = `ba773d0631…` **무변경**.
- PR: **Archright/.github #225** (`ci/p3final-mint-pin-rotation`, 커밋 3a22c34) — **pin-promotion-gate (DEBT#473) PASS(8s)**, 나머지 mirror checks SKIPPED(컨트롤러 미러 입력 부재 — 정상, #220/#222 선례와 동일).
- MERGE: **`ade11572052d9bce01242df452d05ab38ed78eb0`** (2026-10-16T03:17:04Z, native MERGE) → 컨트롤러 main HEAD.

## 3. S-C — org ruleset 재핀 (§4.3 — 빈 큐 창)

- 창 조건: Axiom merge queue 공백(GraphQL `mergeQueue.entries.totalCount == 0`) + in-flight merge_group 0건 관측(03:1xZ 실측 — WINDOW-CLEAN; 강제 개입 0).
- 직전 특이사항: #866(docs)이 본 PR 착지 직후 후행 착지(889c06b10)하여 컨트롤러 재핀 대상 sha는 본 착지와 무관하게 컨트롤러 HEAD 기준으로만 결정된다(§4.3 계약대로).
- freeze: ruleset 20303214 `max_entries_to_build` 2→0 (repo ruleset — `PUT /repos/Archright/Axiom/rulesets/20303214` 전체 본문; readback = **0** 확인).
- before: 양 ruleset sha = `74b415c414c0a501a1df125ad92289f0bac17bde`(h4b — org endpoint GET 원문 기준).
- `PUT /orgs/Archright/rulesets/24233738` → readback: workflows[0] = `{path: .github/workflows/admission-gate.yml, repository_id: 1182157951, sha: ade11572052d9bce01242df452d05ab38ed78eb0}` — sha 일치.
- `PUT /orgs/Archright/rulesets/23943917` → readback: `{path: .github/workflows/landing-integrity.yml, repository_id: 1182157951, sha: ade115720…}` — 동일.
- 무변경 대조: before↔readback 전 필드 비교(name/target/enforcement/bypass_actors/conditions/rules)에서 값 변경은 **rules 내 `.sha` 단일** — conditions(ref_name + repository_name; repository_id 부재)·bypass 무변경.
- 해제: `max_entries_to_build` 0→2 (readback = **2** 확인).
- 세대 태그: `admission-gen-h5-20261016` (컨트롤러 remote, annotated) → `ade11572052d9bce01242df452d05ab38ed78eb0`.

## 4. S-D — 통제 503 주입 스팟 체크 (fetch_bounded 계약 재확인 — always-503 소진, 2다리)

- 벤치: probe-merge-queue.yml은 FROZEN 표면 → 정산 벤치 **h4-routing-measure.yml**(CONTROLLED venue, workflow_dispatch 전용 비권위 측정 — F2와 동일)에 `p3final-injection` experiment로 수록 — 브랜치 로컬(`probe/p3final-bounded-retry-injection`, main 미착지; 커밋 d76b78978).
- 함수 동일성: **착지 main(`7072f9382…`) certificate-mint.yml에서 정규식 추출 — 15카피 전부 byte-identical, 단일 sha256 `802f8ddeaef7cb0c95d855435e6b4588835b628f5b71ffcc80334f03a54024a1`** 실측(런 로그 `extracted fetch_bounded copies: 15 distinct-sha: 1`).
- 스텁: loopback python3 http.server (127.0.0.1:18099) **always-503**. E3에서 4행동 전수 입증되었으므로 본 스팟 체크는 소진 1케이스를 **3-arg(JSON 기본) + 4-arg(raw Accept — 본 세대 신설 인자) 양 다리**로 수행.
- **런 38845768293 (2026-10-16T03:29–03:31Z) — run conclusion: success** (job `p3final-bounded-retry-injection` success, 타 job 전부 skipped — 단일 목적 디스패치; 초회 시도 런 38845463737은 미가드 measure 잡 오발로 failure — injection job 자체는 success — 이후 가드 보강 후 재디스패치):

| 관측 | 로그 발췌 | 판정 |
|---|---|---|
| 4 attempts (양 다리) | `MINT_FETCH_RETRY: p3final-always-503-exhaustion-3arg attempt 1/4 … attempt 4/4 — HTTP 503 (transient)` / `-4arg attempt 1/4 … 4/4 — HTTP 503 (transient)` | 4 attempts 상한 준수 ✓ |
| backoff 래더 | `[spot-check] rc=1 (expect 1) elapsed=35s (min 35s)` ×2 | 5+10+20s 소진 경로 ✓ |
| 소진 = 명시적 실패 | rc=1, `INJECTION: PASS — always-503 exhaustion contract met on landed P3 FINAL text (3-arg + 4-arg Accept legs)` | 성공 증거 없음(성공 body 부재 단정 통과) ✓ |

## 5. 최악 지연 상한 (LAYERED worst-case math)

래핑 call-site 총계 = `fetch_bounded` **37**(기존 13: P4 artifacts·P5 artifacts+tree.zip·P6 jobs-page·P7b×3·P7c×3·P7c-x×3 + 신규 24) + `fetch_admission_zip` **1**(P4, Tier-1 원본) = **38 invocations** × 사이트당 최대 4 attempts = **152 + merge-queue auto-requeue 1 = 153 attempts-of-record** worst case (F2 기록 53에서 +100). 사이트별 최악 체감 지연 = 4 attempts + backoff 5+10+20s(=35s) + 각 attempt의 전송 시간. 소진 시 최종 상태는 기존과 동일한 명시적 실패(성공 증거 없음 — fail-closed 유지). 이익: GitHub 일시 5xx를 사이트 내 흡수 — 런 전체 재실행(DEBT#474 실측 7m21s 손실) 제거.

## 6. S-E — 무인 착지 수용 (4중 증거)

#865 착지(본 기록이 인증하는 P3 FINAL 랜딩)의 4중 증거 — 컨트롤러 회전(S-B)이 선행 착지되었으므로 본 docs PR의 merge_group 런이 소비하는 callee 핀 = 신규 세대:

| 계층 | 채널 | 관측 |
|---|---|---|
| E1 | run object `referenced_workflows` | 본 docs PR의 MG 런 **38847179520** 기록에서 `certificate-mint.yml@7072f938231f…` 포함 신규 세대 지문 관측 (90일 보존) — 트리플: admission-check `64f78ab7d178…` + certificate-mint `7072f9382…` + runner-pool `ba773d0631…` |
| E2 | job 로그 `Uses:` | mint-publish 래퍼 실행(같은 런) — `Uses: Archright/Axiom/.github/workflows/certificate-mint.yml@7072f938231f579ed851c12ad9bbdba6d05cb4ec` 실측 + 신규 본문 판별자(`local accept=` 9카피 덤프) 관측; **MINT_PUB first issuance append 1**(B=ce142302a0…, H=f551699ce…, gateway_headSha=4484fa09e…), MINT_EVAPPEND/MINT_JUDGAPPEND/MINT_JUDGAPPENDX×3 전부 `append exactly-once: 1` |
| E3 | 핀-트리플 지문 | {admission-check `64f78ab7d178…`, certificate-mint **`7072f9382…`**, runner-pool `ba773d0631…`} — 신규 세대로서 self-consistent (S-B 회전의 직접 결과) |
| E4 | 착지 정체성 + 강제 경계 | native MERGE `7072f9382…` (parents B+head, commits/<sha>/pulls → #865) + required checks success + **ruleset readback sha == 컨트롤러 HEAD `ade115720…`** (§3) |

본 기록 PR 자체의 착지 = production acceptance 행위(admission-generation.md §5 선례). 본 문서는 관측 완료된 사실만 기술한다 — 착지 이전 값의 사전 기재는 없다(no-peeking).

## 7. CAS 무효화 관측 (PolicyDigest/트러스트 입력 회전 — 알려진 1회 비용)

#865 착지로 certificate-mint.yml(트러스트 표면)이 다시 바뀌었다. 신규 세대 핀을 소비하는 첫 랜딩 레그(본 docs PR의 MG 런 **38847179520**, attest/admission-check job)의 CAS 키 무효화 실측 — **4판정 전부 EXECUTED(신규 판정 재실행 — REUSED 마스킹 아님)**:

- `[cert] Judgment CAS[s1a]: EXECUTED — key 8f1f2227b2ad (no record for the current closure (fresh judgment))`
- `[cert] Judgment CAS[proof_integrity]: EXECUTED — key 2ae8a29e7974 (…fresh judgment)`
- `[cert] Judgment CAS[d2_golden]: EXECUTED — key 3adbc9327312 (…fresh judgment)`
- `[cert] Judgment CAS[d2_persist]: EXECUTED — key a3c29e51d90c (…fresh judgment)`

같은 런 mint-publish: 동일 키(8f1f2227b2ad·2ae8a29e7974·3adbc9327312)의 `MINT_JUDGAPPEND(X): OK … append exactly-once: 1` — 인증서 CAS 신규 발행과 정합. 알려진 1회 비용: 회전 직후 첫 런이 캐시 없이 전건 실행 — 이후 세대에서 재사용 회복이 정상 경로. 본 갱신은 착지 직후 append-only 정정(f551699ce 원문의 기입 예정 표기 대체 — commit 800d37f39 선례).

## 8. Part 2 — DEBT#474 폐쇄 (grep audit + registry)

- 착지 본문 grep audit(7072f9382 판독): `curl -fsSL` **0건** — 파일 내 curl은 15카피 `fetch_bounded` 본문 + `fetch_admission_zip` 본문 내부뿐(전부 bounded 래퍼; ledger append·`attest --sign`·POST는 애초 curl이 아니며 미래공).
- 폐쇄: 본 문서 PR 착지 후 별도 레지스트리 폐쇄 PR — status open→closed, resolution FIXED, resolutionNote(승격 4-PR 체인 #850·#856·#865+본 폐쇄, 429 permanent alignment 계약, 주입 런 38845768293 증거), `bin/debt_engine --codegen` + `--sync-budget` → `--validate` all-PASS 0-DRIFT(nimtry metric DRIFT는 #857 소관 budget으로 recorded-open 유지 — 신규 DRIFT 0).
