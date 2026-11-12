# P3 Tier-2 site-group bounded-retry promotion — 변경 기록 (2026-10-16)

> **종류**: 변경·승격 기록 (docs/spec/admission-generation.md §4 경로 (b)+(a) 수행 기록 — P3 Tier-2 site-group ceremony, 3번째 실행; 절차 전수 재사용 선례 [p3_bounded_retry_promotion_2026-10-15.md](p3_bounded_retry_promotion_2026-10-15.md) + [p3_landing_acceptance_2026-10-15.md](p3_landing_acceptance_2026-10-15.md)).
> **소속 PR**: `feat/p3t2-bounded-retry-generation` (본 PR — Axiom 측) + 컨트롤러 핀 회전 PR (Archright/.github) + ruleset 재핀 + 통제 503 주입(스팟 체크) + 무인 착지 수용.
> **사전등록**: [rotation_allowlist_p3t2_prereg_2026-10-16.md](rotation_allowlist_p3t2_prereg_2026-10-16.md) (착지 전 고정 — no-peeking).

---

## 1. 변경 내용 — certificate-mint.yml 9-site bounded-retry wrappers (Tier-1 일반화 함수 재사용)

Tier-1 first-site-group(PR #850)이 착지한 `fetch_bounded <url> <outfile> <tag>` 일반화 계약(신규 의미 정의 없음 — **함수 본문을 착지본에서 추출해 byte-identical 재사용**, 6카피 전부 동일 실측)을 post-verdict bookkeeping read-path GET 9사이트에 적용했다:

| # | 스텝 | 사이트 | 계약 다리 | 변화 |
|---|---|---|---|---|
| 1 | (P7b) [SL-15] evidence CAS | artifacts-list JSON GET | [B2](b) 동일 계약 — 503 시 append 단계에 도달 못 함 | 즉시 fail-closed → 바운디드 리트라이 |
| 2 | (P7b) | evidence-record artifact zip GET | DEBT#474 측정 경로와 동일한 artifact 전송 | 즉시 fail-closed → 바운디드 리트라이 |
| 3 | (P7b) | admission artifact zip GET | witness 소스 전송 | 즉시 fail-closed → 바운디드 리트라이 |
| 4 | (P7c) [SL-15] s1a judgment CAS | artifacts-list JSON GET | 선행 fetch — 503 시 zip에 도달 못 함 | 즉시 fail-closed → 바운디드 리트라이 |
| 5 | (P7c) | judgment-record artifact zip GET | record 전송 | 즉시 fail-closed → 바운디드 리트라이 |
| 6 | (P7c) | admission artifact zip GET | witness 소스 전송 | 즉시 fail-closed → 바운디드 리트라이 |
| 7 | (P7c-x) [SL-15] extension judgments | artifacts-list JSON GET | 선행 fetch | 즉시 fail-closed → 바운디드 리트라이 |
| 8 | (P7c-x) | judgment-record artifact zip GET | per-subject record 묶음 전송 | 즉시 fail-closed → 바운디드 리트라이 |
| 9 | (P7c-x) | admission artifact zip GET | witness 소스 전송 | 즉시 fail-closed → 바운디드 리트라이 |

계약(재사용): max **4 attempts**, backoff **5s/10s/20s**; transient = curl transport rc ≠ 0 ∪ 최종 HTTP 5xx; permanent = 최종 HTTP 4xx — **429는 transient가 아니다(재시도하지 않는다**, 2026-10-15 contract alignment); 소진 시 HTTP code/curl rc 출력과 함께 **명시적 실패, 성공 증거 없음**. 각 attempt는 동일 run-scoped URL 재획득뿐이고 본문은 하위 binding 검증(record identity·payloadSha256·witness byte binding)이 전부 재수행한다.

**안전 제약 준수 (C2 Task 5)**: ledger append(exactly-once FF-CAS — `ax cert ledger-append` 1건, `ax evidence ledger-append` P7b·P7c 및 P7c-x per-subject loop)·`cert attest --sign`·모든 POST는 wrap·변경하지 않았다. `fetch_bounded`는 fetch-scoped ONLY — 재시도는 append를 재구동할 수 없으며, P7b no-op/append reconciliation의 D6 재진입 허용을 확장하지 않는다. prepare-side·Tier-3 사이트(P1 cert.zip, P0, slice-engine)·P6 pagination while-loop·P6 skipped-lane justification GET은 본 그룹 밖이다(미편집).

**로그 계약**: `MINT_FETCH_RETRY: <tag> attempt $a/4 — HTTP $code (transient)` / `(curl rc=$rc, http_code=$code)` / `(permanent — not retried)` — merge-queue-rearm.yml TRANSIENT (b) 앵커 형식 호환(Tier-1과 동일). 태그 체계: `P7b|P7c|P7c-x artifacts-list artifact download (JSON GET)` / `… zip download (artifact)`.

## 2. 동반 핀 열거 (사전등록 §2 요약 — 착지 전 확정)

- **Axiom 측 핀 갱신 0건**: `trustedAdmissionWorkflowSha`·`productionExecutionPin`은 모두 `admission-check.yml` blob `b2b8235d79d17ec158f4d5429691ceef65575f67`에 결속 — 본 PR은 그 파일을 편집하지 않는다. `trustedWriterWorkflow`는 경로 선언만이다.
- **컨트롤러 핀 2건 (회전 대상 — mint blob를 담는 전부)**: `Archright/.github` `admission-gate.yml`의 `uses:` 핀 :481(stage=prepare)·:538(stage=publish), 현행 `689ff9eaf63c9e3ac8ae33aefcef84a74cb0c467` — `git cat-file -t` = **commit** (PR #850 MERGE; `uses:` 핀은 blob sha를 받지 않는다). 회전 값 = 본 PR 착지 후의 Axiom main 커밋 SHA (경로 (a) — §4.1), 양 핀 단일 논리 단위 동시 회전.
- **trustedCheckerTreeClosure (876 멤버)**: `.github/` 하위 멤버 0건 실측 — closureChange = false (rqNormal), 클로저 무영향.
- **trustSurface**: certificate-mint.yml 포함 — 본 PR은 TRUST_SURFACE_MODIFIED (dryRunExit 0 — src/cli/merge_cli.nim:1458) 로 큐를 통과하며, 아키텍트 수동 승격 경로의 결합 통제는 사전등록 문서(본 PR 동반) + CODEOWNERS 리뷰가 담당한다.
- **ROT_NEW_PIN 자기참조 잠금 없음** — STOP 조건(핀 순환) 불발동.

## 3. 착지 체인 (수행 순서 — 본 섹션은 착지 후 갱신된다)

| 단계 | 내용 | 증거 |
|---|---|---|
| S-A | Axiom PR (본 PR) — 9-site wrappers + prereg + 본 기록 | (착지 후 기입) |
| S-B | 컨트롤러 핀 회전 PR (Archright/.github) — 689ff9eaf… ×2 → 신규 Axiom main 커밋 | (기입 예정) |
| S-C | ruleset 24233738·23943917 재핀 (§4.3 — 신규 컨트롤러 HEAD, readback 검증) + 세대 태그 admission-gen-h3-20261016 | (기입 예정) |
| S-D | 통제 503 주입 스팟 체크 (h4-routing-measure experiment branch; always-503 소진 1케이스 — Tier-1 4계약 입증 재사용) | (기입 예정) |
| S-E | 무인 착지 수용 — docs 증거 PR의 4중 증거 (E1–E4) | (기입 예정) |

### S-A 로컬 검증 (착지 전 — 실측)

- `make check-workflow-shell-syntax` → **PASS** (169 run blocks, failures=0, lane-guard violations=0 — bash -n 전수; 래퍼는 기존 run 블록 내부 추가라 블록 수 불변)
- parse-poison → **PASS** (certificate-mint.yml 최대 발식 스칼라 6,066자 < 21,000 — jobs/prepare/steps[2]/run)
- `tools/ci/verify_trusted_writer_set.sh` → **PASS** (certificate-mint.yml = 선언된 단일 writer; admission blob 결속 `b2b8235d…` 불변)
- `bin/debt_engine --validate` → **PASS** (**1489 total, 1489 passed, 0 failed; Metric evaluation: 3 PASS, 0 DRIFT**)
- `make check-repository-surface` → **PASS** (add/modify/delete/rename/other = 0)
- pre-commit + pre-push → 커밋/푸시 시 실측 (`bin/axiom-gate commit` 경유 — raw commit 미사용)

## 4. 최악 지연 상한 (LAYERED worst-case math — 본 변경이 추가하는 것)

래핑 사이트 총계 = Tier-1 3 + Tier-2 9 = **12 sites**. PR head 1개당 총 래핑 사이트 시도 상한 = **4 × 12 sites + merge-queue auto-requeue 1 = 49 attempts-of-record** (직전 세대 13에서 +36). 사이트별 최악 체감 지연 = 4 attempts + backoff 5+10+20s(=35s) + 각 attempt의 전송 시간. 소진 시에도 최종 상태는 기존과 동일한 명시적 실패(성공 증거 없음 — fail-closed 유지). 이익: GitHub 일시 5xx를 사이트 내 흡수 — 런 전체 재실행(DEBT#474 실측 7m21s 손실) 제거.
