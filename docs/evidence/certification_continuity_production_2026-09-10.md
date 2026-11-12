# Certification-Continuity Production Evidence Bundle (2026-09-10)

> **성격**: certification-continuity vertical slice(PR #57)의 머신-체커블(machine-checkable) 생산 증거 번들.
> 모든 수치는 2026-09-10 세션에서 아래 "재검증 명령(Re-verify)" 열의 명령을 실제 실행하여 확인한 것
> 또는 본 문서 상단 출처(brief/운영 저널/CI 기록)에서 가져온 것. 재검증 명령 미실행 항목은 명시적으로
> "기록값(prior-session)"으로 표시한다.
>
> **연관 문서**: runbook `docs/evidence/continuity_runbook.md`, 계약 `docs/spec/certification_continuity_contract.md`
> (커밋: PR #57 → main `73cd6def9`, 현재 origin/main `b94b03ea44` 산하에 존재).
>
> 본 파일은 저장소 관례상 `docs/evidence/` 아래에 두며 `git add -f`로 커밋한다(현재 .gitignore 상태상
> `docs/evidence/` 전체가 ignored는 아니며 `docs/evidence/context7/`만 ignored — force-add는 관례 유지 차원).

---

## 1. 개요 / Claim (OID 실측)

수직 슬라이스 문장(실측 OID 기입):

> **PR #57**(head `6f21462897fdb27da26023c50998a337c5559255`, base main `6c54983c4aa24ae9ea2c5cfe2882830a8ce87e4d`,
> title "feat(verification): continuity production probe (certified-subset) + runbook (certification-continuity vertical slice)",
> **CLOSED 2026-09-09T23:28:10Z** — publish가 자동 close)은, **materialize**가 후보 M
> (candidateCommit `73cd6def9da3d9688a3c061075ee1cdec7578288`, treeDigest
> `15fe85d02e870dc22db1bc014fe363d902c4325ff837d1d120650b4560d4c4b3`, provenance `merge_materializer`)을 확정하고
> **subject**(`2a0fbe7652b72a91dced63610291a4d3e67c7481003d8e65297a058669feba2c`, schema `axiom.subject.v1`,
> createdAt 2026-09-09T23:14:21Z)를 생성한 뒤, trusted **attestation chain**(stages a–g; evidence 기록
> `data/trusted/evidence/2a0fbe76….json`, schema `axiom.attestation.evidence.v1`, chainEntries 1 / chainDropped 0;
> Lean 재실행 정리 `theorem axiom_continuity_probe_sanity`, SMT-LIB2 Int 쿼리; func `continuityProductionProbe`
> @ `src/verification/continuity_probe.nim`; policyDigest `b0bdb8507d…`, scopeDigest `7a4cd3eb0e…`,
> envDigest `a449b9d9bf…`, toolchainIdentity `nim-2.2.10|lean-4.33.0|z3-4.13.3`)을 통과하여
> **subject-continuity certificate**(`data/trusted/certificates/2a0fbe76….json`, schema `axiom.certificate.v3`,
> fingerprint `53637ec4543ee3118e8ab58bfe28eb45f20dd2d32a16549bc32dcbc51f6e909f`, evidenceDigest
> `530335423e6b9690a0b5436d66d23467de1ffe157159931157978991569f6fee`, 검증 등급 **dual-verified**,
> winningStrategy **lean-replay**, solverStatus **unsat**, z3Executed true, leanCompilerVerified true,
> Ed25519 publicKeyId `sha256:9a17da4859fa2ee34a5b349c1ee8dabb8e116e8f612c9cfa4f836da8a9337f37`)를 발급(23:15:15Z)하고,
> FF-only **ledger append**(side-ref `refs/heads/axiom/certificates` tip
> `b0126f1f2e85697f6bd1ae5606305634d050e610`, root `be403189f47c1f8b19ce1c20c5b2cf8153a36ea9`, INV-8)를 마쳤으며,
> **exact-M FF-CAS publication**(main `73cd6def9da3d9688a3c061075ee1cdec7578288`, tree
> `c77cdbf651745afba9be82b1b70ebdf9653b7bb9` **== PR #57 head tree**; parent == pre-publication main
> `6c54983c4aa24ae9ea2c5cfe2882830a8ce87e4d`, INV-2 exact-object FF CAS)으로 **main == M**을 달성하고,
> **continuity**(`bin/ax cert continuity --main 73cd6def9… --cert /tmp/probe-cert.json` → **ccPassed**, exit 0)를
> 확인했다. **벽시계 소요**: subject 생성 23:14:21Z → publication 23:28:10Z ≈ **13m49s (≈14분)**.

운영 저널(`.axiom/gate_history.jsonl`)의 결정적 레코드:

| 시각 (UTC) | stage | verdict | 핵심값 |
|---|---|---|---|
| 2026-09-09T23:14:09Z | merge-materialize | — | pr 57 |
| 2026-09-09T23:14:22Z | merge-subject | — | subjectId `2a0fbe76…` |
| 2026-09-09T23:14:40Z | merge-extraction-agreement | **eaAgree** | "Nim extractor and Lean reference extractor agree (byte-equal serialized IR)", candidateOid `6f21462897…` |
| 2026-09-09T23:15:15Z | merge-attestation | **atPassed** | "trusted attestation chain passed (a-f) — subject-continuity certificate minted" |
| 2026-09-09T23:15:34Z | merge-publish | ABORTED/CERT_INVALID | dvcNotCurrent (pr 0, 사전 검증 시도) |
| 2026-09-09T23:16:16Z | merge-publish | ABORTED/CERT_INVALID | dvcNotCurrent (pr 0, 재시도) |
| 2026-09-09T23:19:43Z | merge-publish | ABORTED/pubError | push 실패 (exit 1, 로컬 pre-push 훅 단계) |
| 2026-09-09T23:22:37Z | merge-publish | ABORTED/pubError | push 실패 재시도 |
| 2026-09-09T23:28:11Z | merge-publish | **PUBLISHED/GO** | "published M 73cd6def9da3 — remote main == M verified at object level"; preMainSha `6c54983c4…`, postMainSha `73cd6def9…` |

실패 시도(CERT_INVALID 2회, pubError 2회)는 모두 **fail-closed + 저널링**되어 있다 — 은폐 없음.

---

## 2. 측정 대상: 신/구 경로 구분

| 구분 | 경로 | 아키텍처 |
|---|---|---|
| BEFORE (구 경로) | PR #56 (`certification-continuity-v10`, 17-커밋 아키텍처) | admission이 PR CI check-runs에 의존 → **PR에서 full L2 후보 검증**, merge 후 **main-push 때 full L2 재실행** = 매 push마다 전체 재검증 (중복) |
| AFTER (신 경로) | PR #57 (vertical slice) | **certificate가 admission 권위** (contract §4.3; runbook §7 "The PUBLICATION path is cert-gated") → certification 파이프라인은 PR-CI 대기 불필요 |

---

## 3. BEFORE 측정 — PR #56 (구 경로) CI 실행

| CI run | 이벤트 | head | 시작–종료 (UTC) | 소요 | 결론 |
|---|---|---|---|---|---|
| 34400538754 | pull_request | 37a9dc4942 | 2026-09-09T20:21:28Z → 20:43:03Z | ~21.6 min | **failure** |
| 34404342799 | pull_request | 37271b1c3c | 2026-09-09T20:59:45Z → 21:55:24Z | ~55.7 min | **failure** |
| 34409886275 | pull_request | 962acc1dc9 | 2026-09-09T21:59:39Z → 22:40:14Z | ~40.6 min (**~41 min**) | **success** — PR에서 전후보 검증 완료 |
| (merge) | REST rebase merge | — | 2026-09-09T22:53:14Z | — | PR #56 MERGED → main `6c54983c4` |
| 34414383936 | push (main) | 6c54983c4 | 2026-09-09T22:53:17Z → 23:28:28Z | ~35.2 min | **cancelled** (probe publication이 main 이동 23:28:09Z → superseded) |
| 34417063970 | push (main) | 73cd6def9 | 2026-09-09T23:28:09Z → 09-10T00:27:34Z | ~59.4 min | success — **신 main도 full L2 재실행됨 (= 중복; 5c cutover 전)** |

**중복의 실체**: PR #56 머지 직후 main-push가 새 full-L2 런(34414383936)을 즉시 시작했고, 35분을 달린 뒤
다음 main 이동(73cd6def9)에 의해 취소되었으며 다시 full-L2(34417063970, ~59분)가 처음부터 돌았다.
즉 구 경로는 **PR 검증 + 매 main-push 전체 재검증**을 모두 수행했다.

> 재검증: `gh api repos/Archright/Axiom/actions/runs/<id> --jq '{id,status,conclusion,created_at,updated_at,head_sha,event}'` — 위 5개 모두 실행 완료, 표와 일치.

---

## 4. AFTER 측정 — PR #57 (신 경로): 산출물 ID + 타임스탬프 + 재검증 명령

| # | 단계 | 산출물/ID | 시각 (UTC) | 재검증 명령 (2026-09-10 실행) | 실행 결과 |
|---|---|---|---|---|---|
| 1 | Subject | `2a0fbe7652b72a91dced63610291a4d3e67c7481003d8e65297a058669feba2c`<br>baseSha `6c54983c4…`, candidateCommit `73cd6def9…`, candidateRef `refs/queue/continuity-probe/pr-57`, treeDigest `15fe85d02…` | 23:14:21Z (저널 23:14:22Z) | `python3 -m json.tool data/trusted/subjects/2a0fbe76….json` | schema `axiom.subject.v1`, provenance `merge_materializer`, 전 필드 일치 |
| 2 | Evidence (untrusted-tier) | `data/trusted/evidence/2a0fbe76….json` — chainEntries 1, chainDropped 0; leanSource `axiom_continuity_probe_sanity`; SMT-LIB2 Int; `continuityProductionProbe`; policyDigest `b0bdb8507d…`, scopeDigest `7a4cd3eb0e…`, envDigest `a449b9d9bf…`; toolchainIdentity `nim-2.2.10\|lean-4.33.0\|z3-4.13.3` | 23:15:15Z (인증서와 동시) | `python3 -m json.tool data/trusted/evidence/2a0fbe76….json` | schema `axiom.attestation.evidence.v1`, prNumber 57, prHeadSha `6f21462897…`, 전 필드 일치 |
| 3 | Certificate | `data/trusted/certificates/2a0fbe76….json` — schema `axiom.certificate.v3`, kind `subject-continuity`, fingerprint `53637ec4…`, evidenceDigest `53033542…`, **dual-verified / lean-replay / unsat**, Ed25519 (publicKeyId `sha256:9a17da48…`), journalRef `85a4066…` | 2026-09-09T23:15:15Z (createdAt, status certGreen) | `python3 -m json.tool data/trusted/certificates/2a0fbe76….json` | 검증 등급/전략/solverMeta(leanCompilerVerified true, z3Executed true), attestation.signature 존재 — 전 필드 일치 |
| 4 | Journal (TrustCommit) | `data/trusted/journal/85a4066ff1a9e839d545a0af9f2146fc1cc5f81debb47cc5717170adc31dbcf3.json` — kind `tcVerifiedProof`, parentCommit null | — | `python3 -m json.tool data/trusted/journal/85a4066….json` | kind/claim.fingerprint `53637ec4…` 일치; 저널 총 314파일 (`find data/trusted/journal -type f \| wc -l`) |
| 5 | Ledger (side-ref) | `refs/heads/axiom/certificates` tip `b0126f1f2e85697f6bd1ae5606305634d050e610`; append 커밋 메시지 `axiom: certificate ledger append 2a0fbe76…`; root `be403189f47c1f8b19ce1c20c5b2cf8153a36ea9` | 2026-09-09T23:15~23:28 사이 | `git ls-remote origin refs/heads/axiom/certificates` + `git log --format='%H %P %s' -1 b0126f1f2e85…` | 원격 tip `b0126f1f2e85…`; 부모 = root `be403189f…` — **선형 2-커밋 체인, FF-only append (INV-8)** |
| 6 | Publication (FF-CAS) | main `73cd6def9da3d9688a3c061075ee1cdec7578288`; tree `c77cdbf651745afba9be82b1b70ebdf9653b7bb9`; parent `6c54983c4…` | ~23:28:09–10Z | `gh api repos/Archright/Axiom/git/commits/6f2146289… --jq .tree.sha` 그리고 `…/73cd6def9… --jq .tree.sha` (+ `.parents[0].sha`) | **둘 다 tree `c77cdbf65…` (동일)**; parent `6c54983c4…` — **exact-object FF CAS (INV-2)** |
| 7 | PR #57 close | CLOSED (auto-close by publish), closedAt 2026-09-09T23:28:10Z | 23:28:10Z | `gh pr view 57 --json state,closedAt,headRefOid` | state=CLOSED, closedAt=23:28:10Z, head `6f21462897…` |
| 8 | Continuity (로컬) | ccPassed | 2026-09-10 (본 세션) | `bin/ax cert continuity --main 73cd6def9da3d9688a3c061075ee1cdec7578288 --cert /tmp/probe-cert.json` | `[cert] Continuity: ccPassed (CC_PASSED) — main 73cd6def9da3 vs certified M …` **exit 0** |
| 8b | Continuity 반증 (uncertified main) | ccMismatch | 2026-09-10 (본 세션) | `bin/ax cert continuity --main b94b03ea44f21647224bad833744beb37f133d13 --cert /tmp/probe-cert.json` | `ccMismatch (CC_MISMATCH) — main b94b03ea44f2 vs…` **exit 1** (fail-visible) |
| 9 | Probe PR CI (동시 실행; admission과 무관) | 34415967934 (readiness_start.yml) success 23:13:42→23:21:08Z; 34415967939 (ci.yml) success 23:13:42→23:57:33Z | — | `gh api …/actions/runs?head_sha=6f2146289…` | 둘 다 success; **ci.yml은 publication(23:28:10Z) 이후 ~29분 뒤에야 종료** — certification 경로가 PR-CI를 기다리지 않았음을 입증 |

**AFTER 벽시계**: subject 23:14:21Z → publication 23:28:10Z = **13m49s (≈14분)** (운영 저널: materialize 23:14:09Z → PUBLISHED GO 23:28:11Z = 14m02s).
CSS certification 파이프라인(materialize+subject+attest+ledger+publish) 전체가 **PR-CI 대기 없이** 완료되었다.

---

## 5. PR #58 → #59: libpcre3 런타임 의존성 수정 (록)

| 항목 | 값 |
|---|---|
| PR #58 (branch `pcre-runtime-fix`, head `ce94b3a0f996e0ea1a6614b2e2025e63572c1bef`) | 17-커밋 아키텍처 브랜치; 16개는 이미 PR #56의 rebase-merge로 main에 반영(내용 동등); rebase가 부모를 다시 붙여 PR은 **CONFLICTING** → force-push 금지 정책상 **CLOSED** (mergedAt null) |
| PR #58 닫힘 코멘트 (원문) | "Superseded by PR #59 (clean rebased libpcre fix). The 16 architecture commits here are already in main via PR #56; closing to unblock CI. No code is lost — the workflow fix content is identical in PR #59." |
| 계보 실측 (본 세션) | `git rev-list --count ce94b3a0f99 --not main` = **17** — rebase re-parenting으로 **조상 관계상으로는 0/17이 main에 포함**. "16개 이미 main"은 **내용 동등성(content equivalence)** 주장이며 계보상으로는 검증 불가 → 정직한 측정으로 기록 |
| PR #59 (branch `pcre-runtime-fix-rebased`, head `af25c76813d9c6068365f20972c61eea7b59b1d9`, base `73cd6def9`) | 1커밋: "fix(ci): provision libpcre3 on hosted runners — cert continuity/verify dlopens std/re (certificate_verifier chain); fixes merge-continuity + attest failures on ubuntu-latest" |
| PR #59 diff (실측) | `.github/workflows/attest.yml` + `.github/workflows/merge_continuity.yml`에 `sudo apt-get update && sudo apt-get install -y libpcre3` 단계 추가; `src/generated/build_metadata.json` 재생성 (generatedAt 2026-09-10T00:12:06Z, commitCount 1061, gitHash `73cd6de`; `continuity_check.nim`/`continuity_probe.nim`/`publication_scope_gate.nim` 추가) |
| PR #59 CI run 34420664225 | 2026-09-10T00:17:32Z → 01:07:57Z **success**; jobs: verify-integration-r2-unit ✓, verify-coverage-guard ✓, verify-integration-r2-proof ✓, verify-static ✓, verify-integration-r1 ✓, pr-coverage-comment ✓ (nightly/generate-docs skipped) |
| 병합 | 2026-09-10T01:09:17Z, wintrover, REST rebase → **merge commit `b94b03ea44f21647224bad833744beb37f133d13` = 현재 origin/main** |

> 재검증: `gh pr view 56/58/59`, `gh pr diff 59`, `gh api …/actions/runs/34420664225/jobs` — 모두 실행 완료.

---

## 6. merge-continuity run 34424319042: ccError 근본 원인 (저널 프로비저닝 갭)

**실행 개요**: PR #59 머지(01:09:17Z) 직후 main-push 트리거 merge_continuity.yml run 34424319042
(push main `b94b03ea44f2`, 2026-09-10T01:09:23Z → 01:13:13Z) — continuity 잡만 **failure**, exit 1.

**CI 로그 원문 (gh run view --log-failed 발췌, 2026-09-10T01:13:11Z)**:

```
Run bin/ax cert continuity --main "b94b03ea44f21647224bad833744beb37f133d13" \
  --cert "/home/runner/work/_temp/ledger-cert.json"
[cert] Continuity: ccError (CC_ERROR) — main b94b03ea44f2 vs certified M from /home/runner/work/_temp/ledger-cert.json
[ERROR] cert_cli: continuity: CC_ERROR — fail-visible (ccPassed required for exit 0)
##[error]Process completed with exit code 1.
```

중요 관찰: **libpcre3 수정은 성공** — binary가 실행되었고 libpcre.so 오류가 사라졌다. 새 실패는 저널 갭이다.

**근본 원인 (지역 재현으로 확정)**: `.gitignore:425-428`에 `data/trusted/journal/`(+`data/trusted/certificates/`)가
gitignored로 등록되어 있어 **hosted-runner 체크아웃에는 trust-commit 저널 파일이 전혀 없다**
(개발 머신은 314파일 존재, 실측). `verifyCertificateClosure`가 인증서의 journalRef(`85a4066…`)를 해석해야
구조적 검증이 성립하는데, 저널이 없어 **구조적 검증 실패 → ccError (fail-closed)**.

**로컬 재현 매트릭스 (본 세션 2026-09-10, 전부 실행)**:

| 조건 | main `73cd6def9` (certified M) | main `b94b03ea44` (uncertified) |
|---|---|---|
| 개발 머신 (저널 314파일 존재) | **ccPassed**, exit 0 | **ccMismatch**, exit 1 |
| CI 동일 조건 (저널 없는 fresh 체크아웃 + binary; `/tmp/ev-repro` 워크트리에 binary 복사) | — | **ccError (CC_ERROR)**, exit 1 — **CI 로그와 동일 문구** |

즉 **로직 자체는 정확**하다: 저널이 있으면 certified 대비 ccPassed / uncertified 대비 ccMismatch로
구분 판정하고, 저널이 없으면 구조적 검증 실패로 ccError를 낸다. CI 실패는 **환경 프로비저닝 갭**이다.

**분류**:
- `ccError`는 **fail-closed 정상 동작** (인증서 구조 검증 실패 시 절대 통과하지 않음) — **NOT theater**:
  모든 실패가 런타임에 표시되고(fail-visible 메시지 + exit 1), 로컬에서 결정적으로 재현되며, 부분 통과/무언 통과가 없다.
- I-2 **unexpected-push 감지가 작동 중**: main이 REST 머지(PR #59)로 `b94b03ea44`로 이동했지만 ledger
  인증서가 여전히 `73cd6def9`를 인증하므로 불일치가 정당하게 플래그된다. (CI는 저널 부재로 ccError가
  앞서고, 개발 머신은 ccMismatch로 같은 사실을 판정 — 둘 다 비통과.)
- **미해결 작업 항목(본 세션에서 코드 수정 없음 — architect 승인 필요)**: CI에 저널 프로비저닝 추가
  (신뢰 artifact/ref에서 저널 fetch) 또는 CI 한정 closure를 ledger-blob-only로 완화. config/에 새 패치가
  아니라 `config/changes/ci-continuity-cutover.patch`(main 트래킹됨)와 별개 작업으로 등록.

---

## 7. Failure-scenario 표 (라이브 픽스처 + 테스트 스위트)

**Rows 1–9 — 라이브 실패 시나리오** (픽스처 `/tmp/fail-scenario-2067473-{remote.git,wt}`;
검증 레코드 원문: `/tmp/fail-scenario-2067473-wt/.axiom/gate_history.jsonl`, 총 17 레코드 — 본 세션 판독).
모두 `verdict=ABORTED`, **exit 1, fail-closed**:

| Row | 시나리오 | 시각 (UTC) | verdict 원문 (verbatim, reason 필드) |
|---|---|---|---|
| 1 | STALE_BASE | 2026-09-10T00:36:31Z | `remote main cec298f5575a != certified base 8175e5662753 — old certificate invalid; re-materialize + re-attest onto current m…` |
| 2 | SUBJECT_MISMATCH | 00:39:38Z | `re-materialized candidate 37a0a1ac3ac9 != certified M 45e55e0b0155 — the single-construction rule means inputs changed` |
| 3 | POLICY_MISMATCH | 00:41:14Z | `certificate policyDigest != sha256(current config/policy/merge_admission.json) — re-attest under the current policy` |
| 4 | CERT_INVALID (malformed JSON) | 00:41:22Z | `structural verify failed: malformed certificate JSON: input(1, 4) Error: string literal as key expected` |
| 5 | CERT_INVALID (tampered Ed25519) | 00:41:22Z | `structural verify failed: attestation verification failed: attestation: Ed25519 signature verification failed` |
| 6 | CERT_INVALID (journal-unresolvable) | 00:33:31Z | `structural verify failed: journal commit '7129abcab007353292c808bc04e80ff93b02ce6cad1a7d2d51387a8bb173c5cc' missing: trust_commit: no commit …` |
| 7 | NO_CERT | 00:38:06Z | `GITHUB_TOKEN not set — cannot read the certificate ledger (fail-closed)` |
| 8 | pubError (pr-0) | 00:44:39Z | `publishM: invalid candidate/expected OID (fail-closed)` |
| 9 | attest ledger-append fail-closed | 00:32:35Z | `stage-g certificate mint failed: subject_continuity_writer: certificate already exists — append-only, overwrite refused (fail-closed)` |

동일 픽스처의 추가 레코드(위 9행 외, 같은 gate_history.jsonl): CERT_INVALID dvcNotCurrent (00:34:26Z),
CERT_INVALID kernel-re-exec z3 누락 — "kernel re-execution failed: lean=kernel re-execution passed z3=z3
binary missing or failing the pinned checksum policy — fail-closed" (00:34:40Z), NO_CERT 재현 (00:43:08Z).

**Rows 10–13 — 테스트 스위트 결과** (prior-session 기록값; 본 세션에서 **재실행하지 않음** — attest 계열 테스트가
`data/trusted/*`에 쓰기 부작용을 낳을 수 있어 read-only 규칙 준수. 정적 check 호출 수는 근사 일치만 확인:
publication 60 / attestation 82 / continuity 22 소스 호출 수 vs 기록 57/79/19 — 각 스위트마다 정확히 +3의
차이가 있어 harness의 계수 방식 차이(중복 계수/비실행 분기 등)로 추정되나, 코드 수정 없이 정격 재현은
하지 않았다. 아래 수치는 **당시 실제 실행 PASS 수**이며 재실행 값이 아님):

| Row | 스위트 | 결과 | 비고 |
|---|---|---|---|
| 10 | test_publication.nim | **57 checks PASS** | — |
| 11 | test_attestation.nim | **79 checks PASS** | — |
| 12 | test_continuity.nim | **19 checks PASS** | — |
| 13 | test_subject.nim | **C7 FAIL** (4 vs 3 golden subjects) | **환경적 원인**: probe 세션의 미추적 파일 `data/trusted/subjects/2a0fbe76…json`이 남아 있어 golden fixture 3개 + 1개 = 4개로 카운트. 본 세션 `git status`로 미추적 파일 존재 실측 — **제품 회귀 아님** |

> brief가 "rows 10–16"을 언급하나 제공된 테스트 결과는 위 4개 스위트뿐이므로, **14–16행은 제공되지 않은
> 것으로 보고 추가 추측 없이 생략**한다 (invent 금지 원칙).

---

## 8. BEFORE/AFTER 비교 + 5c 전환 상태

| 차원 | BEFORE — PR #56 (구 경로) | AFTER — PR #57 (신 경로) |
|---|---|---|
| certification 파이프라인 소요 | full L2가 admission 전제: PR CI **~41 min** 성공이 최단 관측 | materialize→publish **≈14 min** (13m49s) |
| PR-CI 대기 | 필수 (check-runs 기반 admission) | **불필요** — cert가 권위 (probe PR CI 34415967939는 동시 진행, admission과 무관, publication 후 29분 뒤 종료) |
| main-push 시 full-L2 재실행 | 매 push마다 재실행: 34414383936 (~35 min 후 취소), 34417063970 (~59 min) — **중복** | 여전히 실행됨 (34417063970 관측) — **5c cutover 전** |
| 5c (main-push full-L2 중단) | — | **§-1 PENDING**: `config/changes/ci-continuity-cutover.patch` **PREPARED** (main 트래킹됨; ci.yml의 L2 잡을 main-push에서 제외하는 diff), **architect 승인 필요** — 미적용 상태 유지 |

**정직성 표기**: AFTER의 "no duplication"은 certification 경로에 한정된 주장이다. main-push full-L2는
5c cutover가 승인·적용될 때까지 실행되므로, **전체 CI 중복 제거는 아직 미달성**이다.

---

## 9. 산출물 인벤토리 (파일 경로 ↔ 존재 위치)

| 산출물 | 경로/ref | 존재 위치 |
|---|---|---|
| 본 증거 번들 | `docs/evidence/certification_continuity_production_2026-09-10.md` | 브랜치 `evidence-cert-continuity-2026-09-10` (git add -f) |
| Runbook | `docs/evidence/continuity_runbook.md` | main (`73cd6def9` 산하, 트래킹됨) |
| 계약서 | `docs/spec/certification_continuity_contract.md` | main (트래킹됨) |
| 인증 대상 함수 | `src/verification/continuity_probe.nim`, `src/verification/continuity_check.nim` | main (`73cd6def9`, 트래킹됨) |
| 5c cutover 패치 | `config/changes/ci-continuity-cutover.patch` | main (트래킹됨) — **PENDING, 미적용** |
| Subject | `data/trusted/subjects/2a0fbe76….json` | 로컬 워킹트리 (미추적; gitignored 아님) |
| Evidence | `data/trusted/evidence/2a0fbe76….json` | 로컬 워킹트리 (미추적) |
| Certificate | `data/trusted/certificates/2a0fbe76….json` | 로컬 워킹트리 (**gitignored**) |
| Journal | `data/trusted/journal/85a4066….json` (+314파일 전체) | 로컬 워킹트리 (**gitignored**) |
| Ledger | `refs/heads/axiom/certificates` tip `b0126f1f2e85…` | **origin 원격** (`git ls-remote` 실측) |
| Published main | `73cd6def9…` (tree `c77cdbf65…`) → `b94b03ea44…`=origin/main | **origin 원격** |
| CI 실행 기록 | runs 34400538754 / 34404342799 / 34409886275 / 34414383936 / 34417063970 / 34415967934 / 34415967939 / 34420664225 / 34424319042 | GitHub Actions (gh api로 실측) |
| 운영 저널 | `.axiom/gate_history.jsonl` (120 레코드; PR #57 파이프라인 + continuity 판정 포함) | 로컬 워킹트리 (gitignored) |
| 실패 시나리오 픽스처 | `/tmp/fail-scenario-2067473-remote.git`, `/tmp/fail-scenario-2067473-wt` (gate_history.jsonl 17 레코드) | `/tmp` (외부 보존) |
| 연속성 인증서 복사본 | `/tmp/probe-cert.json` | `/tmp` (재검증 명령에 사용) |

---

## 10. 비-결론 (이 증거가 성립시키지 않는 것)

1. **ccPassed는 호스티드 CI에서 아직 관측되지 않았다.** 최신 CI 관측은 ccError(34424319042)이며,
   ccPassed는 로컬(개발 머신) 판정만 존재. CI-side 성공은 저널 프로비저닝 수정 후에야 검증 가능.
2. **5c cutover는 적용되지 않았다.** ci.yml은 변경되지 않았고(§-1 불변), main-push full-L2는 계속 실행됨.
   패치가 준비되었을 뿐 — architect 승인과 적용이 남아 있다.
3. **platform-prevent는 DEFERRED** (이번 증거 번들의 범위 밖).
4. **테스트 스위트(PASS 수)는 prior-session 기록값** — 본 세션 재실행이 아니며(제약: data/trusted read-only),
   가까운 장래에 `data/trusted` 격리 조건에서 재실행하여 갱신하는 것이 바람직하다.
5. **ccPassed는 신원(identity) 판정** — fresh verification verdict가 아니다 (runbook §9). full-L2 백스톱은
   nightly + attest chain의 책임이며, 본 문서는 그 대체물이 아니다.
6. **PR #58의 "16커밋 이미 main"은 내용 동등성 주장** — 계보상으로는 17/17이 main 비조상(rebase re-parenting).
7. **ledger는 git side-ref** — append-only 데이터베이스가 아니다. FF-only 강제는 정책/게이트에 의존하며,
   추가적인 해시 체인/외부 감사 메커니즘 검증은 별도 범위.
8. **본 문서의 런타임 실패 기록은 모두 fail-visible** — theater 금지(§0.9) 준수의 증거로
   "언제나 통과"류의 극장적 행동은 포함하지 않는다.

---

## 11. 재검증 실행 요약 (2026-09-10 세션, 전부 실행 완료)

- `gh pr view 56 57 58 59` / `gh pr diff 59` / `gh pr view 58 --json comments` — PR 상태·머지·코멘트
- `gh api …/git/commits/{6f2146289,73cd6def9} --jq '{sha,tree,parents}'` — **tree 동일 c77cdbf65…, parent 6c54983c4…**
- `gh api …/actions/runs/{34400538754,34404342799,34409886275,34414383936,34417063970,34415967934,34415967939,34420664225,34424319042}` (+ jobs) — CI 결론·구간
- `gh run view 34424319042 --log-failed` — ccError 원문 캡처
- subject/evidence/certificate/journal JSON 판독 (`python3 -m json.tool`) — 전 필드 일치
- `git ls-remote origin refs/heads/axiom/certificates refs/heads/main` → `b0126f1f2e85…` / `b94b03ea44f2…`
- `git log --format='%H %P %s' -1 b0126f1f2e85…` → 부모 root `be403189f…` (FF-only 선형 체인)
- `bin/ax cert continuity --main {73cd6def9,b94b03ea44} …` → ccPassed (exit 0) / ccMismatch (exit 1)
- 저널 부재 재현: `/tmp/ev-repro` fresh 워크트리 + binary 복사 → **ccError, CI와 동일 문구** (exit 1)
- `.axiom/gate_history.jsonl` + `/tmp/fail-scenario-2067473-wt/.axiom/gate_history.jsonl` 판독 — 파이프라인/실패 verdict 원문
- `git rev-list --count ce94b3a0f99 --not main` = 17 (계보 실측)
- `.gitignore:425-428` (journal/certificates ignore), `git check-ignore -v docs/evidence/…` (not-ignored 확인)
