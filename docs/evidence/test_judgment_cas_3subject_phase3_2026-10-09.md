# test-judgment CAS 3-subject extension — Phase 3 Completion Evidence (PR #622)

> Vertical Slice 실행 증거 — **s1a test-judgment CAS의 3주체 확장**
> (`proof_integrity` · `d2_golden` · `d2_persist`). 정본: `docs/spec/test_judgment_cas_contract.md`
> (§4 9성분 closure, §5 REUSED 5조건, §6 fail-closed EXECUTED, §7 non-signature).
> body PR **#622** (head `b85baabce`, branch `feat/judgment-cas-3more`) — **MERGED 2026-10-09T00:43:54Z,
> merge commit `6767884e7111c94164a6981e0e5bb4370e984e03`** (GitHub pulls API 권위, §2.3).
> 실측: 2026-10-09 (GitHub Actions REST·런 로그 + 로컬 worktree
> `orca/workspaces/Axiom/jcas-extend-3`).
> 측정 에이전트: Kimi Code 서브에이전트 (2026-10-09).

## 1. Completion Evidence

| # | 항목 | 방법 | 실측 | 판정 |
|---|---|---|---|---|
| ① | 주체별 판정 증거 최소집합 | 소스 + 스위트 | 주체별 상수·스키마 핀 `axiom.judgment.cas.<subject>.v1`(s1a 무접미사 보존), 주체별 payload 검증기 3종 + 디스패치, 증거 타입 3종 + 와이어 + 플러시(canary 포함), `subjectCompletenessKeys` 스키마 시대 핀 — s1a 키 와이어·바이트 보존(G8 dispatch key == landed key PASS) | PASS |
| ② | 동일 9성분 closure 재사용 | `collectJudgmentClosureFor` | 기존 `collectJudgmentClosure`은 s1a 래퍼로 유지 — 3주체는 동일 9성분 수집 경로 소비, 주체별 source closure/fixture digest만 분기 | PASS |
| ③ | 워크플로 루프 확장 | `admission-check.yml` diff | plan ×4주체(주체별 decision/record/evidence 파일·env), 주체별 REUSED/EXECUTED 분기(case, SKIP/EXECUTED 표기), attest env 15개 export, 레코드 스테이징 ×4 fail-closed, artifact 12파일 | PASS |
| ④ | G8/G9 스위트 | `make test-fast-one T=tests/unit/test_judgment_cas.nim` | **68 PASS / 0 FAIL** — G8: 주체별 스키마/키 4키 pairwise-distinct, 부재→실행·타주체키→실행·정상→REUSED·변조→거부·스테일→거부 / G9: 플러시 왕복+canary+비무장 거부+witness 노드 | PASS |
| ⑤ | 3종 계측 테스트 실행 | `make test-fast-one` ×3 | `test_d2_golden` exit 0(14회 커널 체크 전부 canonical sink 경유 — `jCanonical` 래퍼), `proof_integrity_test` exit 0(12 체크포인트 관측 캡처), `test_d2_persist` exit 0(genuine kernel certificate Stage 1–5 PASS). 3종 기존 판정 단언 무변경 | PASS |
| ⑥ | G7 + digest×2 | 병합 트리(6767884e7)에서 재실행: `make build`(헤르메틱 재빌드 — SourceCoherence 재정합) → `make verify-contract-release-e2e-full`; `bin/ax report --canonical-digest` ×2 | **G7 PASS**: exit 0, `G7 pass (tier=dual-verified status=not_verifiable vaultPath=)`, `[lean-verify] PASS — proofs/ directory builds cleanly`. **digest×2 동일**: `354f811c25467787988a349053e5aab578d9c42b675fe34abc16bb0db9af4731` | PASS |
| ⑦ | push-admissibility 14게이트 | pre-push OID snapshot | b85baabce 푸시 성공 — check-debt(1454 checks PASS, advisory DRIFT 1건=⑨), check-nim-theater, doc-path-validator, proof-unit-consistency/reconcile, repository-surface, git-access, monitor-purity, workflow-shell-syntax, epoch-transaction, merge-admission-cert-mirror, layer-enforcement/negative 전부 green | PASS |
| ⑧ | epoch 트랜잭션 (G2a) | 레이어-3 3-way 일치 | `admission-check.yml` blob `95e5e4554bc1b270d964908272af36183d8b31be` == TWS `trustedAdmissionWorkflowSha` == manifest `productionExecutionPin` @HEAD (동일 커밋 원자 재바인딩, ADR-0022 §5) — trusted-writer-set-pairing CI check PASS | PASS |
| ⑨ | nimtry advisory (비차단) | `bin/nimtry src/` | 경고 7건 신규(baseline 대비): cert_cli `runWitnessOnlyCli` 117 SLOC, attestation_witness `decodeWitnessSemantic` 59 SLOC, judgment_cas exported functions 56(층 max 20), `validateS1aJudgmentPayloadNode` 86/`planJudgmentCasForSubjectWithTransport` 80/`runJudgmentAttestBranchForSubject` 113 SLOC, solid-ocp case 51/registry 0 — 전부 INFO disposition(Advisory·non-blocking·MAINTAINED), debt_engine Part D DRIFT로 표기되나 exit code에 불영향(코드 1548–1559행: structural 실패만 차단). 본 PR은 미수정, 후속 리팩터 후보로 추적 | PASSED-WITH-ADVISORY |
| ⑩ | PR→merge SHA | `gh api repos/Archright/Axiom/pulls/622` (§2.3 GitHub pulls 권위) | **MERGED 2026-10-09T00:43:54Z, merge commit `6767884e7111c94164a6981e0e5bb4370e984e03`** (= main tip). 랜딩 그룹 37865330190 전 job success(§3.1 시도 이력: 1차 후보는 mint-publish s1a-append 충돌로 fail-closed → 큐 재시도 2회 후 랜딩) | PASS |

## 2. 세대 경계 (§2.5 CI Self-Bootstrap) — 3주체 CAS 마커의 라이브 시점

- **현재 세대**: org `Archright/.github` `admission-gate.yml`의 `referenced_workflows` 핀은
  `admission-check.yml@347c1fc0d…` (실측 2026-10-09, contents API) — s1a 세대.
- **효과**: 본 PR이 착지한 3주체 plan/loop 마커(`AXIOM_JUDGMENT_CAS_*: EXECUTED/REUSED`,
  `MINT_JUDGAPPENDX_COUNT`)는 required workflow 핀이 본 PR 이후 커밋으로 전환되는
  **다음 일관 세대**부터 라이브가 된다. 전환 전 라이브 경계는 구세대로서 s1a-only CAS로
  실행되며, 3종 테스트는 일반 admission 테스트로 실행(fail-closed — §2.5 in-place 혼합 없음).
- **착지 경로**: dependabot 회전 PR(#74/#75/#76 계열) `@dependabot recreate` → main tip
  (본 PR 병합 커밋)으로 재해석 → 3-PR 병합으로 일관 세대 전환 (s1a §3.1 선례).
- **본 PR 라이브 실측(구세대)**: s1a plan은 본 PR 트리 변경으로 closure 재도출 → PR-run
  EXECUTED(fresh kernel) + MG-run REUSED(동일 키 재검증 — 병합 후보 트리 == 브랜치 트리,
  s1a ②와 동일 기제). 3종 테스트는 양쪽 런에서 실행 관측. 원문 발췌는 §3.

## 3. 라이브 실측 — 런 로그 원문 발췌 (TBD-POSTMERGE)

런 로그는 zip 리다이렉트로만 제공 — `gh api repos/Archright/Axiom/actions/runs/<id>/logs > run.zip && unzip` 후 grep.

| 관측 | PR-run 37863183512 (pull_request) | MG-run 37864249747 (merge_group, 후보 `c11ae60c1`) |
|---|---|---|
| s1a plan | `AXIOM_JUDGMENT_CAS: REUSED — record fe1066be7a34 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` (00:13:32.269Z) | `AXIOM_JUDGMENT_CAS: REUSED — record fe06f08d51c1 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` (00:38:32.006Z) |
| s1a 커널 | `SKIP — tests/unit/test_s1a_lean_golden.nim (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)` — **커널 0회** | 동일 SKIP 라인 — **커널 0회** |
| 4/4 요약 | `(proof_integrity, s1a_lean_golden [basis=REUSED — no run], d2_golden, d2_persist)` (00:15:19.998Z) | 동일 4/4 요약 (00:41:59.923Z) |
| 3종 신규 테스트 | proof_integrity PASS (00:13:32→00:13:54, 22.1s) · d2_golden PASS (00:13:54→00:15:07, 73.0s — canonical sink 14-run) · d2_persist PASS (00:15:07→00:15:19, 12.6s) | proof_integrity PASS (39.4s) · d2_golden PASS (144s) · d2_persist PASS (24s) |
| judgment append | `MINT_JUDGAPPEND: OK — idempotent no-op (judgment key fe1066be7a34 already stored, append exactly-once: 0)` / `MINT_JUDGAPPEND_COUNT=0` (00:16:37.439Z) | `MINT_JUDGAPPEND: OK — idempotent no-op (judgment key fe06f08d51c1 already stored, append exactly-once: 0)` / `MINT_JUDGAPPEND_COUNT=0` (00:43:18.543Z) |
| evidence append | `MINT_EVAPPEND: OK — evidence record appended (key dca4f9f13153, append exactly-once: 1)` / `MINT_EVAPPEND_COUNT=1` (00:16:35.320Z) | TBD-MG (별도 관측 가능) |
| verdict | `mergeGo (GO)` (00:17:02.265Z — base provenance bound to main `6cf6dd279eb2`) | admission-check job success → GitHub 병합 (00:43:54Z) |

- PR-run에서 이미 s1a **REUSED**(커널 0회) 관측: 본 PR의 변경이 s1a 테스트 소스 클로저 밖임이
  클로저 재도출로 실증됨 — 9성분 클로저 identity의 선택성에 대한 라이브 증거.
- append exactly-once 쌍: 키 `fe06f08d51c1`의 최초 append(exactly-once 1)는 선행 병합
  #617 랜딩 런(f1c207d64, 00:10Z)이 수행 — 본 PR 랜딩 런은 동일 키 no-op(0)로 소비.
  본 증거문서 §1-②의 "EXECUTED append 1 ↔ REUSED no-op 0" 쌍은
  f1c207d64 PR-run(MG 이전 런, REUSED/no-op 0) + #617 MG-run(append 1) + 본 PR 양 런(REUSED/no-op 0)의
  연쇄로 라이브 실증.

## 3.1 병합 시도 이력 (merge queue — 기계 관측 전문)

| 후보 | 런 | 결과 | 비고 |
|---|---|---|---|
| `c11ae60c1` | 37864249747 | admission-check ✓ mergeGo / **mint-publish FAIL** | s1a P7c append가 `fe06f08d51c1 … already present with DIFFERENT payload bytes (payloadSha256 mismatch — identity-derivation anomaly, fail-closed)`로 거절 — 선행 #617 랜딩이 동일 클로저 키에 자기 런의 수신 영수증 다이제스트를 실은 레코드를 먼저 저장(정확히-once 가드의 정상 fail-closed). 본 PR 변경과 무관한 **s1a 세대 기제의 잠재 병목**(동일 클로저 2번째 EXECUTED 런은 payload 재생성 불가) — 큐 재시도로 자기 치유 |
| `0a71410e5` | 37864847071 | 전체 success | REUSED 전환 (append no-op) |
| `6767884e7` | 37865330190 | 전체 success → **병합** | 랜딩 그룹 — §3 표의 MG-run |

## 4. 재현 명령

```
gh api repos/Archright/Axiom/pulls/622 --jq '{merged_at, merge_commit_sha}'   # 00:43:54Z / 6767884e7…
gh api repos/Archright/Axiom/actions/runs/37863183512    # PR-run (REUSED 사이클)
gh api repos/Archright/Axiom/actions/runs/37865330190    # 랜딩 MG-run (REUSED 사이클)
gh api repos/Archright/Axiom/actions/runs/37864249747    # 1차 큐 시도 (s1a-append 충돌 fail-closed)
make test-fast-one T=tests/unit/test_judgment_cas.nim   # 68 PASS / 0 FAIL
make test-fast-one T=tests/unit/test_d2_golden.nim      # exit 0 (canonical sink 14-run)
make test-fast-one T=tests/unit/proof_integrity_test.nim # exit 0
make test-fast-one T=tests/unit/test_d2_persist.nim     # exit 0
bin/debt_engine --validate                               # exit 0 (Part D advisory DRIFT 1건)
git show HEAD:.github/workflows/admission-check.yml | git hash-object --stdin  # == 95e5e4554…
gh api -H "Accept: application/vnd.github.raw" repos/Archright/.github/contents/.github/workflows/admission-gate.yml  # 핀 = 347c1fc0d (구세대)
```

## 5. 착지 구성 (2-PR 스플릿 근거) + 후속 항목

- **PR #622 (본 PR, MERGED)**: 모듈/CLI/테스트 + admission-check(핀 엔진) + TWS/manifest 핀 재바인딩 — G2a 원자 트랜잭션.
- **PR-2 (후속, 미착지)**: certificate-mint.yml P7c-x 3주체 ledger append 단독 PR — G2b implemented-scope
  repair path 2 (epoch 정의 무변경 + scope_conds 12→13 비감소 — 게이트 기계 검증 완료 + PR body 선언).
  이유: 비핀 엔진(mint) 변경은 승격 청구(미구현 슬라이스 중 mint engineFiles 보유 없음 — SL-18만, 이미
  implemented) 또는 path 2 수리인데, path 2는 epoch 정의 무변경을 요구하므로 G2a가 강제하는 핀 재바인딩과
  동일 diff에 있을 수 없음 (epoch_transaction_gate.nim:596–623 실측).
  준비물: `/tmp/pr2_mint.sh` (origin/main 재fetch 후 분기 — 현재 main = 6767884e7) +
  `/tmp/certificate-mint.p7cx.yml` (P7c-x 블록, +117행 순수 추가).

### 후속 항목 진행 상태 (2026-10-09 갱신)

1. **PR-2 (mint P7c-x)**: **착지 진행** — PR **#626** (head `88cefc2b9`, branch
   `feat/judgment-cas-3more-mint`, base = #622 병합 트리 6767884e7). 준비안(`certificate-mint.p7cx.yml`)
   대비 **producer-consumer 정렬 수정 1건**: admission-check 업로드 관례상 레코드 파일은
   **하이픈**(`judgment-record-proof-integrity.json`, admission-check.yml:1322), witness `.subject`
   태그는 **언더스코어**(`judgment_cas.subjectName`) — P7c-x 루프가 `tr '_' '-'`로 파일명을 도출하도록
   수정(미수정 시 첫 라이브 주기에서 mint fail-closed). s1a P7c 블록 무변경(+121/−1 순수 추가).
   PR 본문에 직렬화 근거 인용: Context7 `/websites/nim-lang_github_io_nim` — `std/json`
   (`parseJson`/`JsonNode`/`%*` — 바이트 정확 projection↔ledger 결합의 동적 스키마 표면),
   `std/jsonutils`(`toJson`/`fromJson` — 의도적 미사용 근거: 재직렬화가 바이트 동일성 파괴).
2. **핀 회전 (세대 전환)**: s1a §3.1 선례의 유일 정합 경로 — 기존 dependabot PR 병합 완료 후 신규
   dependabot 회전 PR(daily 스케줄) 또는 `@dependabot recreate` → Axiom main tip(#626 병합 커밋)
   재해석 → 3-PR 병합으로 일관 세대 전환 → **3주체 CAS 마커(plan EXECUTED/REUSED,
   MINT_JUDGAPPENDX_COUNT, 3종 REUSED 시 커널 0회) 라이브화**. 전까지 3종은 일반 admission
   테스트로 실행(관측됨 — 양 런 PASS).
3. **s1a P7c append 동시성 병목 (§3.1 발견)**: 동일 클로저 키에 대한 2번째 EXECUTED 런의 append는
   payload 재생성(런별 수신 영수증 다이제스트) 때문에 exactly-once 가드에 fail-closed — merge queue
   동시성 아래 모든 PR의 1차 큐 시도가 실패→재시도 치유(레이턴시 비용 + 런 낭비). 극장 아님(fail-closed
   정상 동작)이나 기제 개선 후보 — `src/verification/evidence_ledger.nim` identity(key 단독)와
   레코드 payload의 비결정 성분 분리 검토 필요. 본 문서가 유일한 관측 기록(등록은 인가 필요 — §0.9).
4. **nimtry advisory 7건**: judgment-cas 확장 표면의 구조 경고(SLOC 5건·export 수·case 분기 수) —
   후속 리팩터 후보 (INFO disposition, 비차단).
5. **본 증거문서의 docs PR 랜딩**: `docs/evidence/test_judgment_cas_3subject_phase3_2026-10-09.md`
   — 본 PR로 착지 중 (branch `docs/judgment-cas-3subject-evidence`, §1-⑥ postmerge 재측정 반영).
