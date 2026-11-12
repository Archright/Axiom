# ADR-0022: Admission Artifact Authority — Trusted Writer Capability (A)

> **Historical note (2026-09-18, PR #127)**: 본 ADR이 참조하는 `ci.yml` PR 경로·nightly
> backstop은 ci.yml retirement로 삭제되었다. admission gate set은
> admission_producer.yml(PR 트리거, workflowId 359582573)과 verify-candidate 경로가
> 계승한다.

## Status

**PROPOSED (2026-09-13).** Establishes the admission-artifact authority model
(`trusted writer capability`) on top of the ADR-0021 execution-authority model
([`0021-execution-authority.md`](0021-execution-authority.md)). This ADR
introduces the **admission artifact** (A = payload + execution identity) that
records a `mergeGo` landing verdict as an **authority assertion**, and the
canonical-main bind that validates it. It does NOT supersede ADR-0021 — it
extends D3's trusted chain with a landing-side authority record and bind.

> Revised 2026-09-14 (Slice 5): canonical-main bind recomputes WHO/WHAT/LANDING/LINK from git objects + GitHub-native run evidence; admissions side-ref and JWT-WHO superseded for bind (see Revision section at end).

## Context

- **왜 mergeGo가 canonical-main에서 재계산되지 않는가?** — mergeGo(착지 결정)의
  판정 근거 중 다수는 **재계산 불가 facts**다(9차 판정):
  - **checks 결론**(PR head에 대한 check-run/check-suite 상태), **latest-attempt**,
    **workflow identity**(실행 워크플로/러너 선택) — 전부 **GitHub API live 상태**로만
    존재하며, 어디에도 영속 기록이 없다. merge_cli.nim:539-585,
    attestation_orchestrator.nim:419-436은 이 live 상태를 **그 순간** 읽어 판정한다.
  - **PR diff**(착지 후 소실 — merge로 base/head가 합쳐진 뒤에는 해당 PR의 diff를
    재구성할 수 없다), **그 순간의 cert 선택**(ledger에 cert는 남지만, 왜 그 cert가
    선택되었는지의 결정 근거·시점은 남지 않는다).
  - 따라서 verdict(mergeGo)는 **사후 재유도가 불가능한 결정**이며, "canonical-main에서
    재계산되는 사실"로 취급할 수 없다. 이 ADR은 그러한 결정을 **assertion**으로서
    영속화·검증하는 방법을 정의한다.
- **왜 assertion 형태로 영속화하는가?** — 재계산 불가 facts를 어딘가 기록하지 않으면
  착지 후에는 "무엇이 landing의 근거였는지"를 아무도 검증할 수 없다. 기록하되, 기록
  자체가 authority가 아니라 **trusted writer 실행의 산출물**로 보고 bind에서 검증한다.
- **가능한 대안 — JWT에 payload를 서명시키기**: OIDC JWT는 GitHub가 서명하는
  identity 토큰이지 payload 서명 채널이 아니다. 권위 위조(arbitrary payload를
  authorized JWT로 포장)를 막으려면 JWT는 identity만 담고, **payload는 bind가
  재유도**한다(WHO/WHAT 분리). 이 분리는 ADR-0021 D7(executor identity를 trusted
  tier가 재유도)의 연장선이다.
- **이번 범위**: A 스키마(v14) + WriterAuthority predicate + TrustedWriterSet + E1/E2
  실측 + attest.yml 강등 + canonical-main bind 스켈레톤 + ledger-guard safety net.
  mint CLI(`bin/ax admission mint/append`), bind
  (`tools/ci/verify_admitted_landing.sh`), R(H) append는 **서브C 구현 범위**로
  위임하고, 이 ADR은 그 계약을 고정한다.

## Decision

### D1. Authority definition (root = auto_merge.yml@main)

**Authority = trusted writer capability rooted in auto_merge.yml@main; OIDC authenticates the writer execution identity; deterministic re-derivation validates all independently computable claims.**

- **mergeGo의 성격**(13차 문장 유지): mergeGo는 canonical-main에서 재계산되는
  사실이 아니라, trust-surface로 보호된 auto_merge.yml@main 실행이 내린
  **authority assertion**이다. OIDC는 그 executor identity를 인증하고, bind는
  나머지 재계산 가능한 사실과 landing 관계를 독립 검증한다.
- 권위의 root는 **auto_merge.yml@main 자체**(trust-surface 보호)다 — OIDC/재유도는
  그 capability의 증명 수단이지 root가 아니다. 코드가 바뀌면(trust-surface 수동
  merge) 권한도 같은 변경으로 이전된다(§4 atomic 원칙).
- **CAS append = 저장 장치**(12차 유지): admissions side-ref append는
  transport/불변성이지 authority proof 요소가 아니다. force-push 한계(플랜 403)도
  ledger-guard(safety net)의 감지 대상.
- 재계산 불가 facts: checks 결론·latest-attempt·workflow identity(병합 시점 live
  상태, 어디에도 영속 기록 없음), PR diff(착지 후 소실), "그 순간의 cert 선택".
  → verdict는 assertion으로만 존재한다.

### D2. 채택 구조 — auto_merge.yml 실행 → admissions side-ref → canonical-main bind

```
auto_merge.yml (trusted execution — Authority root: auto_merge.yml@main)
   │ ① OIDC id-token 취득 (aud=axiom-admission-v1)
   │ ② Pass 7 관측값 포함 payload 생성
   │ ③ GITHUB_TOKEN으로 admissions side-ref CAS append (저장)
   ▼
A = { payload, executionIdentity(OIDC JWT) }
   ▼
canonical-main bind (tools/ci/verify_admitted_landing.sh — 서브C 구현):
   ├─ WHO: JWT 검증 — 현재 GitHub JWKS로 RS256 검증 + claims exact(§3)
   ├─ WHAT: payload 재유도(git objects + cert + tree digest + trust-surface/change-graph)
   ├─ LANDING: landingCandidateSha == C(C==H ∨ C∈parents(H)) ∧ landingParent1 == H^1
   └─ EFFECT: R(H) ≤ 1 (duplicate-R no-op, CAS unique)   [RETIRED 2026-10-07 — 실행 기록 참조]
```

- canonical-main.yml = bind → verify(착지 H 게이트) → accept(R(H)) [RETIRED 2026-10-07 —
  실행 기록 참조]. push(main)+ injection dispatch(transport). mint 0건, {E1,E2} 무변경,
  GITHUB_TOKEN 유지, concurrency는 acceptance 밖(성능 최적화).
- 감지(ledger-guard, schedule 무결성) = safety net 분리.
- 인간 merge 경로: cert/A 부재 착지 = bind FAIL(fail-closed).

### D3. A 스키마 (v14)

```
payload = { schemaVersion: "axiom.admission.v1",
            verdict(mergeGo|거부류), reasonCode, prNumber,
            headSha(=PR head), landingCandidateSha(Pass 7 관측),
            landingParent1(Pass 7 관측), evaluatedMainSha(AXIOM_MAIN_SHA),
            ledgerCertId, evaluatedAt, runId, runAttempt }
executionIdentity = { issuer, aud, repository, workflow_ref, workflow_sha,
                      run_id, run_attempt, event_name, iat, nbf, jti }
```

- **pinnedJwk 없음**(14차 — A 내부 JWK는 root of trust가 아님), Ed25519 attestation
  없음, admissionFactsDigest 없음, verificationLink/admissionDecision 분리 유지.

### D4. WriterAuthority (JWT) — root of trust = 현재 GitHub JWKS

**root of trust = 검증 시점 현재 GitHub JWKS.** bind가 검증 시점에 GitHub
`openid-configuration` → `jwks`를 재조회해 RS256 검증을 수행한다:

```
issuer == token.actions.githubusercontent.com
signature: RS256 — bind가 검증 시점에 GitHub JWKS(openid-configuration→jwks)를 재조회해 검증
aud == axiom-admission-v1 (exact)
repository == Archright/Axiom
workflow_ref == Archright/Axiom/.github/workflows/auto_merge.yml@refs/heads/main
workflow_sha == trustedAdmissionWorkflowSha (단일값 — §5)
event_name == workflow_run
run_id == A.payload.runId
시간: iat/nbf 정합(시간 역설 없음) ∧ exp > A.payload.evaluatedAt (결정 시점 유효)
```

- **kid 미존재 = FAIL**: 검증 시점에 JWT `kid`가 현재 JWKS에 없으면 bind FAIL.
- **JWKS rotation 한계(정직 명시)**: 검증 시점에 kid가 현재 JWKS에서 사라지면 bind
  FAIL(fail-closed) — 과거 JWT의 장기 검증을 보장하지 않는다. **historical identity
  evidence가 실제로 필요해지는 경우에 한해 key provenance를 별도 ADR로 설계한다**
  (이번 범위 밖). 운영상 canonical bind는 착지 직후 즉시 실행되므로(transport가
  merge 직후 발화) 이 윈도는 짧다; 지연 시 FAIL은 인시던트로 가시화.

### D5. TrustedWriterSet — E2를 계산 가능한 acceptance로

```
ALL workflows with contents:write  ⊆  TrustedWriterSet
TrustedWriterSet = { auto_merge.yml@trustedAdmissionWorkflowSha }
```

- **계산 수단**: `tools/ci/verify_trusted_writer_set.sh` — `.github/workflows/*.yml`
  전수에서 `contents: write` 보유 워크플로를 파싱해 집합을 구하고, TrustedWriterSet
  (단일 항목: workflow 이름 + blob sha)과의 상등(⊆ + ⊇ = 정확히 상등)을 검증.
  위반 시 exit 1 + 차이 출력. 이 script가 P6 이후 매 gate 실행으로 상시 강제.
- **현실 변경점(이 요구의 실체)**: 현재 contents:write 보유 = {attest.yml,
  auto_merge.yml}(실측, E2) — 따라서 **attest.yml을 contents: read로 강등**한다.
  근거: attest 체인의 자동 mint 성공 = 0건(전부 D9 수동), 즉 이는 휴면 권한면
  제거이며 현재 운영에 영향 0. mint authority는 D9(operator 자격증명)로 일원화 —
  "manual merge/recovery only" 원칙(merge_admission_controller.md:89)과 정합.
  publication_scope.json도 동시 갱신(attest contents_write: false).
- auto_merge.yml 코드 변경 시: trustedAdmissionWorkflowSha 갱신이 **동일
  trust-surface PR의 atomic 일부**(단일값, 누적 집합 폐기) — 갱신 전 실행은
  FAIL(fail-closed, 전환 창은 runbook 순서로 관리).

### D6. admittedLanding(A, H)

```
L1. H reachable (fail-closed)
L2. WHO: WriterAuthority(JWT, §4) PASS — 현재 JWKS 기반
L3. WHAT: A.verdict == mergeGo ∧ A.landingCandidateSha == C'
    ∧ (C'==H ∨ C'∈parents(H)) ∧ merge-commit이면 A.landingParent1 == H^1   — exact
L4. LINK: A.ledgerCertId → cert: headSha==C' ∧ headTreeDigest==sha256(C'^{tree})
    ∧ policyDigest/scopeDigest == 현재 정책
L5. 전부 PASS → verify(H); FAIL → fail-closed
```

- golden 15종: merge-commit PASS / FF PASS(PR #69 shape) / 비정형 FAIL / A 부재
  FAIL / 타-워크플로 JWT FAIL / workflow_sha 미일치 FAIL / aud 불일치 FAIL / payload
  변조 FAIL / 가짜 certId FAIL / 중간-change 삽입 FAIL / expired-at-decision FAIL /
  **kid-미존재(현재 JWKS) FAIL — rotation 한계의 기계적 증명** / policy 불일치 FAIL /
  parent-역전 PASS / **TrustedWriterSet 위반 FAIL(가상: attest.yml이
  contents:write를 되찾은 fixture)**.

### D7. replay/잔여 한계 (정직 모델링)

- JWT replay: (a) 재유도 불일치, (b) side-ref 쓰기 권한 = TrustedWriterSet
  (trust-surface merge 전제) — 두 조건이 제한. append는 저장 장치.
- contents:write 보유자의 force-push — safety net(감지) 잔여 통제(플랜 천장).
- **JWT exp 후의 historical 검증은 이 설계가 제공하지 않는다** — kid가 현재 JWKS에
  있어야 하고, 만료는 결정 시점 기준만 검사. 장기 evidence 필요 시 별도
  key-provenance ADR(§4).
- OIDC 장기 사용의 비공식성 — 플랫폼 가임 명시.
- non-goal 유지: subject wire, mint 시점, certRequired, concurrency 튜닝, DEBT#462.

### D8. canonical-main.yml — bind → continuity → accept (+ gateway-cache) — 책임 재배치 (Revised 2026-09-15)

**책임 재배치 — H-admission과 L-continuity의 분리:**

- **H-admission = PR full gate set** (canonical-main에서 재실행하지 않음):
  ci.yml PR 경로 게이트 세트(verify-static / verify-integration-*)는 합성
  merge ref `refs/pull/N/merge`에서 실행 — ADR-0021 §2 — 즉 PR CI는 이미
  merge 트리를 테스트했다. 여기에 verify-candidate + attest(Trusted tier)가
  착지 전 H를 검증하고 admission(H)을 성립시킨다.
- **H→L continuity = bind + continuity + accept**: merge 이후 새로 생기는
  사실은 H→L 전이뿐이다. bind가 착지의 정당성을 재유도하고
  (L1 landing relation / L2 WHO trailers + exact run / A2 check semantics /
  trust-surface at H^1 / policy from H tree), continuity
  (`ax cert continuity` — identity check)가 certified subject와의 연속성을
  확인하고, accept가 R(H)를 기록한다 [RETIRED 2026-10-07 — 실행 기록 참조]. 22-step gate re-execution은
  L-continuity에 기여하는 바가 0이므로 제거한다.
- **Backstop = scheduled full verification**: ci.yml nightly(`make verify-all`
  + nightly_runner + prove)가 환경 의존성·toolchain breakage·숨은 drift·
  장기 regression을 **발견**한다. nightly는 **발견용 backstop이지 두 번째
  admission authority가 아니다** — nightly 실패로 이미 accept된 main을
  사후 무효화하는 구조를 만들지 않는다(발견 사항은 다음 PR에서 수정).
  일상 착지 경로는 cheap하게 유지하고, full verification은 backstop으로 내린다.

**근거 (22-gate 전수 분류, 2026-09-15 재판정):**

- canonical-main verify job의 22 step 전수 분류: **22/22 = H-admission
  콘텐츠 체크, L-continuity 기여 0건** — SHA/시간/runner-state 입력을 읽는
  step 없음.
- **tree(L) == tree(H) 26/26 landing 실측**: base == merge-time main이면
  native merge commit은 PR head와 content-identical
  (`git cat-file -p`/`rev-parse` 실측, landing #93 = 68027286a).
- base drift는 auto_merge.yml actuator guard(:175-177)가 **거부**로 봉쇄 —
  재검증이 아니라 fail-closed다. L은 항상 admission 당시 승인된 H의 허용된
  continuation.

**계약:**

- 트리거: `push: branches: [main]` + `workflow_dispatch(inputs: expectedOid)`.
  **push(transport) + injection dispatch(transport)** — dispatch는 transport
  injection이지 authority가 아니다(헤더 주석에 명시).
- jobs:
  1. **bind** — `tools/ci/verify_landing_recomputed.sh` — WHO/WHAT/LANDING/LINK
     재유도(git objects + GitHub-native run evidence).
  2. **continuity** — `uses: ./.github/workflows/merge_continuity.yml`
     (workflow_call, inputs.expectedOid) — cheap identity check.
  3. **accept** — `bin/ax admission accept --main H` — R(H) CAS append
     (idempotent; CLI 내 CAS/중복-R no-op). accept는 최후 —
     needs: [bind, continuity], continuity PASS 이후에만 실행.
     **[RETIRED 2026-10-07]** — accept 서브커맨드·R(H) writer 폐기(실행 기록 참조).
     원문은 역사 보존을 위해 그대로 둔다.
  4. **gateway-cache** — gateway compile-state cache 생산(E1 계약, PR #95;
     restore → test-gateway → save; cache는 acceleration, evidence가 아님;
     needs: bind, accept를 block하지 않음).
- **bin/ax 명시적 provision**: bind와 accept는 bin/ax를 workspace 잔존물에
  의존하지 않고 main checkout에서 명시적으로 build한다(trusted tier owns its
  binary — attest.yml "Build trusted bin/ax from main" 패턴).
- mint/attest 호출 0건. {E1,E2} 무변경. GITHUB_TOKEN 유지(새 secret/키/서비스 없음).

### Revision (2026-09-18) — D8 transport 통합: 3-job DAG → 단일 receipt job

**판정**: D8의 3-job 실행 경계(bind → continuity(workflow_call
`merge_continuity.yml`) → accept)는 **단일 job의 ordered steps**(bind →
continuity → accept)로 축소한다. **authority semantics는 그대로**다 — 술어 전부 ·
reasonCode(L0_*, L2_*, L3_*, L4_CERT_LINK_FAILED, cc*) · fail-closed 경계 ·
accept-last 순서 · R(H) CAS append 의미론 [RETIRED 2026-10-07 — 실행 기록 참조] · top-level read-only + job-level
contents: write(기존 패턴) · push-event-as-transport · dispatch injection 없음 ·
mint/attest 호출 0건이 모두 유지된다. 병렬 job 간 transport(artifact/toolchain
cache)가 사라지는 것이 전부다.

- **기계적 변경**: 단일 checkout(ref: github.sha, fetch-depth: 0 — L0
  shallow-graft quirk 유지), 단일 bin/ax build, toolchain-cache restore 제거
  (dependency probe — receipt 경로는 cache/toolchain 자산을 읽지 않음), deps는
  설치 대신 host-side fail-closed 검증, token은 GITHUB_TOKEN env(기존 script
  계약).
- **`merge_continuity.yml` 호출 종료**(유일 호출처 canonical-main.yml:144). 파일
  자체는 본 slice에서 수정하지 않는다 — retirement(caller-0 artifact)는 별도
  slice로 이연. continuity 로직은 **기계적 등가 추출**: `tools/ci/run_landing_continuity.sh`
  + equivalence golden test `tools/ci/test_run_landing_continuity.sh`(동일 입력 →
  동일 cert 선택 · 동일 메시지 · 동일 exit status).
- **§-1 승인**: ci.yml-family workflow 권위 파일 — 본 세션 architect 명시 지시,
  2026-09-18(선례: ci.yml tombstone fa069d610, 2026-09-16).
- **범위 밖(불변)**: admission_producer.yml · merge_admission.json 정책 · bind
  술어 · branch protection(Phase 6 deferral 유지) · nightly backstop.
- **계약 정합**: [certification_continuity_contract.md](../spec/certification_continuity_contract.md)
  §4.4 I-2 — predicate/verdict SELF-CONTAINED 성격은 transport와 무관(불변).

### D9. ledger-guard.yml — safety net (NOT authority proof)

- 트리거: `push: branches: ["axiom/**"]`.
- payload `forced == true` 또는 before/after 비정상(ancestor 아님) 또는 `deleted`
  → incident 기록(fail-visible, exit 1).
- 주석에 "safety net — NOT part of the authority proof (ADR-0022 §0)" 명시 —
  force-push 한계(§7)를 감지하는 보조 장치, authority의 요소가 아니다.

### D10. post-merge verification authority — canonical-main 단일화 (Slice 1)

**결정: post-merge verification의 유일한 execution authority = `canonical-main.yml`.**
`merge_continuity.yml`을 독립 트리거(push:main + workflow_dispatch)를 지닌 병렬
워크플로에서 **workflow_call 전용 reusable component**로 전환하고, canonical-main이
`uses: ./.github/workflows/merge_continuity.yml`(inputs.expectedOid)로 호출한다.
이로써 PR #71 merge 이후 모든 착지에서 post-merge verification이 2회 실행되던
중복 authority를 제거한다.

- **단일화 구조 (D8 Revised 2026-09-15 정렬)**: canonical-main =
  bind → **continuity(workflow_call)** → accept(+ gateway-cache). continuity는
  bind PASS 이후, accept는 continuity PASS 이후(accept 최후). verify job의
  22-step gate re-execution은 폐기(책임 재배치 — D8)다. continuity
  검증 로직(`ax cert continuity` — identity check)은 이동만 하고 약화하지 않는다.
- **전환기 transport**(이 Slice 유지, Slice 3에서 제거): canonical-main의 트리거는
  `push: main` + `workflow_dispatch(expectedOid)` 둘 다 유지. auto_merge.yml의
  dispatch 대상도 merge_continuity.yml → canonical-main.yml로 변경
  (inputs.expectedOid=L). 이 dispatch는 **transport injection이지 execution
  authority가 아니다** — GITHUB_TOKEN merge가 push 이벤트를 발생시키지 않는 token
  recursion semantics를 수용하는 플랫폼 배선일 뿐이며, authority는 canonical-main의
  실행 그 자체다. 후속 Slice 3에서 GitHub App credential로 전환해 native push(main)
  수렴 예정.
- **bootstrap(PR #71 자체 착지)의 bind FAIL은 예상된 fail-closed**다: A(admission
  artifact)가 아직 없으므로 bind는 A 부재로 RED — 이는 전환 중 정상 상태이며
  incident가 아니다. 인위적 PASS 주입 금지.
- **trust-surface 전환 PR의 bind 시간축 제한**(HEAD 기준 비교)은 별도 **Slice 2**로
  위임 — 본 Slice 범위 아님.
- **OIDC 필요성 판정: YES.** WHO 바인딩(WriterAuthority, §4)이 없으면
  contents:write 보유자 = 곧 admission 발행자(root가 auto_merge.yml@main으로만
  한정되지 않음)가 되므로 OIDC identity 검증이 권위의 필수 요소다. **E2는 "정적
  선언 검사"로 격하** — contents:write 보유 집합과 TrustedWriterSet의 상등을
  실행·실측이 아닌 정적 선언(publication_scope.json + verify_trusted_writer_set.sh)
  검사로 유지한다.

## Consequences

- **긍정**: mergeGo가 assertion으로 영속화되어 착지 근거가 사후 검증 가능해진다
  (재계산 불가 facts의 유일한 기록). OIDC는 identity만, bind는 재유도 — WHO/WHAT
  분리로 payload 위조가 불가능. attest.yml contents:write 강등으로
  contents:write 보유 = {auto_merge.yml@trustedSha} 단일 수렴(TrustedWriterSet
  상등). trustedAdmissionWorkflowSha 단일값 + atomic 갱신으로 코드 변경과 권한
  이전이 결합.
- **부정(residual)**: JWKS rotation으로 과거 JWT 검증 불가(fail-closed; 장기
  evidence는 별도 key-provenance ADR 대기), force-push는 감지(safety net)만 가능,
  OIDC 장기 사용은 플랫폼 가임, mint/append CLI·bind·R(H) append [RETIRED 2026-10-07 — 실행 기록 참조]·E1/E2 실측은
  서브C/일정 범위.
- **롤아웃 순서**: (1) 본 ADR + attest.yml 강등 + publication_scope.json 갱신 +
  trusted_writer_set.json(현재 blob sha로 초기화, E1 실측 전 TODO) +
  verify_trusted_writer_set.sh 신설(E2 실측 첨부), (2) canonical-main.yml +
  ledger-guard.yml + P6 게이트 배선, (3) auto_merge.yml mint 배선(P3),
  (4) bind/R(H) 구현 [R(H) RETIRED 2026-10-07 — 실행 기록 참조] + golden 15종(서브C), (5) E1 OIDC claims 실측 후
  trustedAdmissionWorkflowSha의 workflow_sha 의미 확정 + ADR 갱신.

## References

- GitHub Docs — [Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-hardening-for-github-actions/about-security-hardening-for-github-actions): OIDC id-token, JWT claims, hash-verified JWKS
- GitHub Docs — [Reusing workflows and jobs](https://docs.github.com/en/actions/sharing-workflows-and-jobs/reusing-workflows): workflow_run event semantics
- GitHub Docs — [REST API — openid-configuration / jwks](https://docs.github.com/en/rest/oidc): 현재 JWKS 재조회 경로
- ADR-0021 [`docs/adr/0021-execution-authority.md`](0021-execution-authority.md): D3(trusted chain), D7(executor identity 재유도), D9(operator-only issuance)
- [`docs/spec/merge_admission_controller.md`](../spec/merge_admission_controller.md): §6 trust model, §8 base freshness, §10 executor seam
- [`docs/spec/certification_continuity_contract.md`](../spec/certification_continuity_contract.md): §4.1/§4.2 Trusted Attestation Boundary, §5 INV-13
- 소스 근거: `src/cli/merge_cli.nim`(539-585 — admission snapshot/collectAdmissionFacts), `src/verification/attestation_orchestrator.nim`(419-436 — cert 선택의 결정 시점)
- E1·E2 실측: **pending** — E1은 서브A probe workflow 실측(workflow_ref/workflow_sha/run_id/event_name/aud/iat/exp/jti/nbf), E2는 verify_trusted_writer_set.sh 실행 결과로 교체 예정. E1 실측 전이므로 `trustedAdmissionWorkflowSha`의 workflow_sha 의미 확정은 서브A 실측 후 갱신 필요.

## Revision (Slice 5, 2026-09-14) — Landing bind recomputed from GitHub-native evidence

**Status change**: D2 (admissions side-ref)와 D4 (WriterAuthority JWT at bind)는
canonical-main bind 경로에서 **폐기(retired)** 된다. D6의 predicate(WHO/WHAT/
LANDING/LINK 분해)은 유지되되, WHO/LANDING의 입력 소스가 교체된다. 원 결정 텍스트는
역사 보존을 위해 그대로 둔다.

### 구조적 결함 — bind-never-passes

bind는 canonical-main **자신의** OIDC id-token을 받는 반면, L2는
`run_id == A.payload.runId`(mint한 auto_merge run의 id)를 요구한다
(tools/ci/verify_admitted_landing.sh:276). canonical-main의 JWT는 구조상 이 조건을
영원히 만족할 수 없다 — bootstrap 한정이 아니라 **영구 조건**이다. 실측 증거:
canonical-main runs 34756600165 / 34758469471 / 34758957710 (landings #71/#75/#76)
모두 bind 단계에서 실패("admissions ref fetch failed — A not present yet"),
그리고 A 자체가 mint된 적 없음(auto_merge 100건 전수에서 Execute merge success
= 0건).

### 교체 설계 (이 Revision)

- **WHO = 결합 증거 판정**: merge 커밋 트레일러 `Merge-Admission-Workflow-Sha: <W>`
  + `Merge-Admission-Run-Id: <R>`, exact Execute-merge 성공 run 검증
  (GET /actions/runs/<R> — head_sha == H^2, step `Execute merge (only on mergeGo)`
  conclusion == success), H^1 시점 trust-surface state를 결합한다. W는 auto_merge가
  **PR base B의 auto_merge.yml blob**에서 계산한다
  (`git rev-parse B:.github/workflows/auto_merge.yml`) — trust root는
  **merge base 시점의 workflow 파일**이며 landing 커밋에 고정된다. GitHub API가
  제공하지 않는 field에 대해 암호학적 보장을 주장하지 않는다 — 이는 수렴적 관측
  증거 판정이며, D7의 정직 한계 모델링을 대체한다.
- **LANDING = git object authoritative**: H^1/H^2는 git에서 읽는다(PR 현재
  head_sha를 historical fact로 사용하지 않음). GET /commits/H/pulls에서
  merge_commit_sha == H인 PR이 **정확히 1개**인지 검증(0/≥2 = fail-closed),
  GET /pulls/{n}의 merge_commit_sha == H 양방향 확인.
- **CHECKS = A2 semantics 복원**: exact workflow identity(policy workflowPath +
  workflowId 귀속), exact head_sha == H^2, latest attempt wins, conclusion ==
  success(missing ≠ valid empty) — bind와 admission(merge_cli)이 동일 기준 판정.
- **TRUST-SURFACE = predicate 재사용**: merge_cli의 `trustSurfaceMatch`를 shell로
  재구현하지 않고, 읽기 전용 서브커맨드 `ax merge trust-surface-check`
  (stdin 파일 목록 → hits)로 재사용한다.
- **POLICY = H 트리의 정책**: `git show H:config/policy/merge_admission.json` —
  현재 main 정책이 아니다.
- **R(H) accept 불변**: CLI CAS+idempotent, refs/heads/axiom/canonical-acceptances.
  **[RETIRED 2026-10-07]** — writer 폐기, ref 자체는 보존(실행 기록 참조).
- **verify_admitted_landing.sh는 디스크에 유지**(bind에서 미사용; 제거는 별도).
- **auto_merge mint/OIDC 불변**(본 Revision 범위 밖).

### Bootstrap landing vs controlled landing 분리

human merge는 트레일러가 없으므로 bind는 **설계상 fail-closed**로 FAIL한다 — 이는
trust-surface 변경 PR(actuator가 애초에 merge 불가)의 문서화된 bootstrap 동작이다.
actuator landing(controlled landing)은 트레일러를 포함하며 bind를 통과한다.

### 이 ADR에서 유지되는 것 / 폐기되는 것

- **유지**: D1의 authority root(auto_merge.yml — 이제 landing 안에 H^1 blob으로
  고정), D6의 WHO/WHAT/LANDING/LINK 분해, D8의 3-job pipeline 구조, D10의
  post-merge 검증 authority 단일화(canonical-main).
- **폐기(bind 경로 한정)**: D2의 admissions side-ref를 bind 입력으로 사용하는 것,
  D4의 JWT 검증을 bind WHO 메커니즘으로 사용하는 것.

### 보충 (L0 shallow graft, 2026-09-14)

P4a bootstrap landing `f7818d6a0`(PR #79, 실제 2-parent merge commit)이
`L0_NOT_MERGE_COMMIT — parent count = 0`으로 실패했다. 원인은 bind job의
`actions/checkout` 기본 `fetch-depth: 1`: shallow graft 상태에서는 H의 부모
object가 없어 `rev-list --parents -n 1 H`가 H만 반환한다(로컬 재현 + 공식 문서
확인, `docs/spec/shallow_checkout_graft_quirk.md`). 수정: bind checkout에
`fetch-depth: 0`, L0는 부모를 읽을 수 없는 환경을 `L0_PARENTS_UNREADABLE`
(fail-closed 환경 결함)로 분리 보고 — merge-shape 판정과 환경 결함을 혼동하지
않는다. 골든 (k)/(l) 케이스가 두 경로를 고정한다.

## Revision (2026-09-15) — D8 책임 재배치: canonical-main의 H-admission re-execution 폐기

**판정**: "46분짜리 verify를 병렬화할까?" → "왜 landing 때 다시 해야 하나?" →
답: **실질적으로 불필요하다**. 잘못 설정된 검증 authority boundary의 교정이다
(성능 개선과 trust-boundary 변경을 하나의 작업으로 묶지 않음 — 이 Revision은
authority boundary 교정이며, gateway cache slice(PR #95)는 별도 성능 slice다).

### 배경 — gate re-execution은 동일 H에 대한 재계산

- canonical-main verify job의 22 step 전수 분류(agent-22, 2026-09-15):
  **22/22 = H-admission 콘텐츠 체크, L-continuity 기여 0건** — 어떤 step도
  착지 시점에만 존재하는 SHA/시간/runner-state 입력을 읽지 않는다.
- **PR CI는 합성 merge ref(`refs/pull/N/merge`)에서 실행**된다(GitHub 공식
  문서 + ADR-0021:37-38) — PR CI가 이미 merge 트리를 테스트했다.
- **tree(L) == tree(H) 26/26 landing 실측**: base == merge-time main이면
  native merge commit은 PR head와 content-identical(landing #93 실측:
  merge 68027286a = PR head tree = 08d62806d).
- base drift는 auto_merge.yml actuator guard(:171-178)가 **거부**로 봉쇄 —
  재검증 아닌 fail-closed. "검증 대상 트리가 landing과 다르다"는 가능성 자체가
  존재하지 않는다.

### 교체 설계 (책임 재배치)

```
H-admission:   PR full gate set (ci.yml on refs/pull/N/merge
               + verify-candidate + attest) — canonical-main 밖
H→L continuity: canonical-main = bind → continuity → accept
Backstop:       scheduled full verification (ci.yml nightly) — 발견용
```

- canonical-main verify job(22-step) **제거** → DAG `bind → continuity →
  accept`(accept 최후, needs: [bind, continuity]).
- **gateway-cache job** 신설: gateway compile-state cache 생산(E1 계약,
  PR #95 유지 — cache는 acceleration, evidence가 아님; needs: bind,
  accept를 block하지 않음).
- **bind/accept의 bin/ax 명시적 provision**: workspace 잔존물 의존(accept의
  구조적 결함 — 녹색 경로 미실행으로 미발견)을 제거하고 main checkout에서
  명시적 build(trusted tier owns its binary). 필요한 검증이 남으면 GitHub
  artifact로 전달 — workspace 우연 상태에 기대지 않는다.
- nightly는 **발견용 backstop**(두 번째 admission authority 금지) — nightly
  실패는 이미 accept된 착지를 사후 무효화하지 않는다; 발견 사항은 다음
  PR에서 수정.

### 유지되는 것 / 폐기되는 것

- **유지**: D1 authority root, D6 WHO/WHAT/LANDING/LINK 분해, D10의
  post-merge authority 단일화(canonical-main), bind의 fail-closed 설계,
  인간 merge fail-closed(bootstrap 문서화 상태).
- **폐기**: verify job(22-step gate re-execution) — 동일 H 재계산.
- **잔여 리스크(정직 명시)**: (1) 환경 의존 결함의 발견이 다음 PR/nightly로
  지연 — 즉시 착지 차단이 아니라 발견 지연이며, 검증 결과 변화·evidence
  손실은 없음. (2) base race는 rerun도 못 닫던 것(동일 — spec §8
  mitigated-not-atomic 유지). (3) 인간 merge는 계속 bind FAIL
  (fail-closed 유지; 무효화가 아니라 미기록).
- **§0.9b (triple-closure)**: PR tier(ci.yml + verify-candidate + attest)와
  nightly에 이미 존재 — landing path에서 제거해도 위반 없음.
### Revision (mint/publication authority split, 2026-09-15)

**attest = PREPARE (mint-only), auto_merge = COMMIT (publication) + MERGE.**

실측 배경: attest 체인이 CI에서 최초로 mint까지 도달한 직후(2026-09-15, run
34931007008) ledger append가 `403 Resource not accessible by integration`으로
실패했다. 원인은 버그가 아니라 §D5 설계 그대로다 — attest.yml은
`contents: read`로 강등되어 있고, `ax cert attest`는 mint 후 ledger append까지
exit-0 조건에 포함해 왔다. 두 authority가 하나의 attest 단계에 공존하던 설계
잔재가 403이라는 fail-closed 신호로 노출된 것이다.

**결정 (§D5 유지·강화 — 새 writer 없음):**

1. `ax cert attest` = **mint-only**: Verify(E,M) + mint + 저널 기록이 exit-0
   조건. ledger append는 attest 단계에서 제거된다. mint된 certificate는
   불변(immutable) GitHub Actions artifact `subject-certificate-<run_attempt>`로
   handoff된다 — 플랫폼이 이미 제공하는 전송 기판이며 별도의 transport
   시스템을 만들지 않는다. (정정 2026-09-29: 원문의 `<headSha>` 명칭 주장은
   drift였다 — 실측 certificate-mint.yml 업로드 이름 = `subject-certificate-${{
   inputs.runAttempt }}`(certificate-mint.yml:767, tracked; 2026-09-27 감사
   §4 행3의 `<runAttempt>` 표기와 일치). headSha 결속은 이름이 아니라
   manifest/provenance 필드가 담당한다. 명칭 재계약은 ADR-0027 P2(아티팩트
   identity = candidate identity)와 함께 명시 개정으로 확정된다.)
2. **publication authority = auto_merge.yml 단일** (TrustedWriterSet
   불변). 순서는 verdict → publication → native MERGE: `ax merge --dry-run
   --cert`가 artifact certificate로 verdict를 내리고(ledger 스캔과 동일한
   경계 검증 — Ed25519 attestation + headSha 바인딩; artifact는 같은 서명
   객체의 대체 transport이지 약한 authority가 아니다), non-mergeGo는
   publication에 도달하지 못하고, mergeGo만 `ax cert ledger-append`로
   side-ref ledger에 공개한 뒤 `ax merge --apply --cert`로 native merge를
   실행한다. publication 실패 = fail-closed (merge 없음).
3. **NO_CERT 의미 갱신**: `NO_CERT` = 평가 대상 head에 대해 유효한
   certificate이 어느 source에도 없음. `--cert`가 있으면 artifact가, 없으면
   side-ref ledger가 source다(bootstrap/recovery). ledger는 certificate의
   존재를 확인하는 durable 장소이지 certificate 생성의 필수 입력이 아니다 —
   순환 의존(admission ← ledger ← attest-append)이 제거된다.
4. **D9 재분류**: operator 자격증명은 **bootstrap/recovery 전용**. 정상
   production path에서 operator append는 허용되지 않는다 — 2026-09-09~
   09-13의 7건 수동 append는 bootstrap/migration 역사로 기록한다.
   production writer가 복수가 되는 구조로의 회귀를 금지한다.
5. **동시 발견 잠재 결함 수정**: `collectCertificateContinuityFacts`가
   matched-cert 경로에서 값을 반환하지 않아(폴스루 → zero-default
   `ok:false, err:""`) ledger에 certificate이 존재하면 admission 수집이 빈
   에러로 예외하던 결함 — `ok(some(fact))` 구성과 artifact 경로
   (`certificateFactFromPath`, `--cert`)를 같은 trust-surface PR에서 수정.

**폐기된 대안**: attest에 `contents: write` 복귀 — TrustedWriterSet 위반.
ledger append를 attest에 돌려주면 D5의 단일 writer 불변식이 깨진다.

**전환 절차**: auto_merge.yml 변경 + `config/trusted_writer_set.json`의
`trustedAdmissionWorkflowSha` 갱신이 단일 atomic PR(§5 절차). 갱신 이전의
실행은 이전 값으로 일관(fail-closed 전환 창 없음 — workflow_run 실행 정의는
항상 default branch 현재 값이고, bind는 origin/main 현재 blob을 기준으로
검증한다).

---

**실행 기록 (2026-09-18, S1 retirement)**: `merge_continuity.yml` retired
(파일 삭제, PR #126). 판정 근거 4종 — (a) `on:` = `workflow_call` 단독
(merge_continuity.yml:45-51), (b) `uses: ./.github/workflows/` 참조 0건
(caller 없음, 파일 자체 주석 외), (c) 최신 run 34731021325
(2026-09-13 01:38 push, 이후 0건 — 소비자 부재의 실측), (d)
`workflow_run:` 소비자 0건. caller 0 + dead artifact이므로 publication
scope 규칙·테스트 단언·canonical-main 주석·live 문서를 동기화하고 삭제.
실행 topology 불변(continuity는 canonical-main ordered step
`tools/ci/run_landing_continuity.sh`로 유지, 파일 무변).

---

**사후 갱신 (2026-09-18, DEBT#464 S4 Phase 0 — v12 설계 정합, docs-only)**: S4 v12 확정 구조에 따라 다음 이전이 **설계로 확정**된다(구현은 S4 Phase 1 — 본 갱신은 권한 부여 실행 0건).

- **D5 publication writer 지목 변경**: `auto_merge.yml`(삭제됨 — 선언만 잔존) → **`certificate-mint.yml` 단일 writer**. `config/trusted_writer_set.json`의 `trustedWriterWorkflow` → certificate-mint.yml, `trustedAdmissionWorkflowSha` → admission_producer.yml blob sha(착지 후 gh api 측정, atomic 갱신)로 이전 예정. **TrustedWriterSet 단일 writer 불변(§D5)·trustedAdmissionWorkflowSha 단일값·atom(§5: 한 PR에서 함께) 원칙은 유지** — 새 writer category·새 authority 체계 없음.
- **mint/publication authority 분리(2026-09-15 Revision)의 재구성**: 2계층(attest=PREPARE / auto_merge=COMMIT)은 v12에서 **witness(비권한 admission tier — 실행 원천 = B 완전 고정, 범위 = Axiom-controlled computation: bin/ax·assembler·setup-axiom-toolchain)** → **publisher(certificate-mint.yml — untrusted witness를 검증/정규화해 canonical certificate representation 재구성 → 서명 → 발행; untrusted computation 0건)**로 이전된다. publisher의 authority 근거 = `workflow_run`(completed) **privilege boundary** — activation guard 3조건(`workflow_run.event==pull_request` ∧ `conclusion==success` ∧ `path==admission_producer.yml`) · admission identity 튜플((workflow_id, path, blob_sha@M) ↔ (trusted_path, trustedAdmissionWorkflowSha)@B — 비교 anchor는 B만) · PR identity(GitHub PR API — 개수==1 ∧ head.sha==H ∧ base.sha==B ∧ base.ref==main) · artifact attempt binding 3계층(run-scoped API + trusted-name `witness-{run_attempt}` + manifest)을 전부 fail-closed로 검증한 뒤에만 서명·발행한다. (정정 2026-10-04: trusted-name의 정본 명명식은 ADR-0027 P2 개정에 따라 `admission-check-<candidate head>-<run_attempt>`이며, 이름이 run_attempt를 담아야 한다는 본 계층의 요구는 불변이다 — 초판 P2의 attempt 미포함 명명이 이 계층을 무력화한 것이 재실행 아티팩트 누적 사고의 원인이었다.) 시크릿은 어느 tier에서도 참조되지 않는다(서명키 = 공개 상수 — §4.2 시크릿 축 개정 참조).
- **attest 단일 프로세스 분리(Phase 1 예정)**: `ax cert attest`가 수행하던 커널 a–f + 서명 + D6(네트워크) + journal을 `--witness-only`(커널만 — 서명·journal·네트워크 0)와 `--sign`(검증→정규화→서명→journal) 서브명령으로 분리. 기존 attest 전체 경로는 **D9 수동 ceremony용으로 유지**.

---

**실행 기록 (2026-10-07, canonical-acceptances writer retirement)**: R(H) accept
경로(route B — `ax admission accept` 서브커맨드 + `acceptLanding`/
`readAcceptanceForLanding`/`acceptanceRewriteSeen` 기계, writer 대상
`refs/heads/axiom/canonical-acceptances`) retired(writer 삭제, 본 PR). 판정 근거
3종 — (a) GitHub required check(`admission-check`) + merge queue가 이미
authoritative acceptance다(`docs/spec/authority_contract.md` §4 — "GitHub is the
sole merge ENFORCEMENT authority"); (b) 동일 역할의 제2 수용 표면은 retire
대상이다(`authority_contract.md` §5.4 — 선례: in-CLI auto-merge lane 제거);
(c) R(H) ledger는 merge 이후의 사후 기록일 뿐 admission을 결정하지 않았으므로
제2 authority였다. 실행 경계 변경 계약 준수(`AGENTS.md` §2.5·§2.6):
authority = `authority_contract.md` §5.4 계약, state transition = 본 기록 +
`ax admission accept` → usage + exit 1(fail-closed), failure semantics =
dispatch else 분기(쓰기 시도 원천 봉쇄), proof = 반대 경로 실측(exit 1) +
`git ls-remote` tip 불변. **ref 자체는 보존된다**(§2.5 비가역 금지 — ref tip
무변경 실측; writer만 retire되어 해당 ref는 읽기 전용 역사 증거로 잔존).
admissions side-ref(`refs/heads/axiom/admissions`)의 artifact A writer
(`appendAdmissionArtifact` 계열)는 본 retirement 범위 밖(불변). PR: #548
(2026-10-07 랜딩).
