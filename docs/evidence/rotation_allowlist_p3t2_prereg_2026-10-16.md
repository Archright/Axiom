# P3 Tier-2 site-group bounded-retry rotation 사전등록 — certificate-mint.yml 9-site wrappers (2026-10-16)

> **종류**: ROT_ALLOWLIST 사전등록 (docs/spec/admission-generation.md §4.2 경로 (b) — ROT_ALLOWLIST 사전 등록 레그; ADR-0025 Amendment 계보의 사전등록 규율 준수, 직전 선례 [rotation_allowlist_p3_prereg_2026-10-15.md](rotation_allowlist_p3_prereg_2026-10-15.md)).
> **등록일**: 2026-10-16 (착지 이전 고정 — no-peeking).
> **소유자**: 2026-10-16 사용자 전면 허가(full user authorization) + 승인 계획(P3 Tier-2 site-group generation promotion — 3번째 ceremony 실행, E3 절차 전수 재사용) 하에 P3 기계적 부분을 신규 워크트리(feat/p3t2-bounded-retry-generation, origin/main c606c4373 기점)에서 등록한다.
> **고정성**: 본 문서가 착지하는 순간 §1의 열거는 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 수록 범위 — candidate delta 경로 열거 (glob 없음)

`feat/p3t2-bounded-retry-generation` PR의 candidate delta는 아래 3경로로 **한정**된다:

1. `.github/workflows/certificate-mint.yml` — 착지된 일반화 셸 함수 `fetch_bounded <url> <outfile> <tag>`(Tier-1 first-site-group, PR #850; 신규 의미 0 — 함수 본문 3카피 전부 byte-identical임을 착지본에서 실측·추출하여 **그 본문을 그대로 재사용**)을 post-verdict bookkeeping read-path GET 9사이트에 적용한다:
   - **(P7b)** [SL-15] evidence CAS ledger append 스텝 — artifacts-list JSON GET, evidence-record artifact zip GET, admission artifact zip GET (3사이트),
   - **(P7c)** [SL-15] s1a judgment CAS ledger append 스텝 — artifacts-list JSON GET, judgment-record artifact zip GET, admission artifact zip GET (3사이트),
   - **(P7c-x)** [SL-15] extension judgment records 스텝 — artifacts-list JSON GET, judgment-record artifact zip GET, admission artifact zip GET (3사이트).

   계약(재사용 — 신규 정의 없음): max **4 attempts**, backoff **5s/10s/20s**; transient = curl transport rc ≠ 0(transport) ∪ 최종 HTTP 5xx; permanent = 최종 HTTP 4xx — **429는 transient가 아니다(retry하지 않는다**, 2026-10-15 contract alignment); 소진 시 HTTP code 출력과 함께 **명시적 실패, 성공 증거 없음**(기존과 동일한 fail-closed). 로그 계약: `MINT_FETCH_RETRY: <tag> attempt $a/4 — HTTP $code (transient)` / `(curl rc=$rc, http_code=$code)` / `(permanent — not retried)`.
2. `docs/evidence/rotation_allowlist_p3t2_prereg_2026-10-16.md` (본 문서 — 착지와 동반).
3. `docs/evidence/p3t2_bounded_retry_promotion_2026-10-16.md` (변경 기록 — pin 열거, 승격 체인, worst-case math).

**미수록 경로는 본 PR의 delta에 존재하지 않는다.** prepare-side·Tier-3 사이트(P1 cert.zip, P0, slice-engine)·P6 pagination while-loop·P6 skipped-lane justification GET·`git/commits` GET(P4/P5)·그리고 **모든 ledger append(`ax cert ledger-append`, `ax evidence ledger-append`)·`cert attest --sign`·모든 POST는 wrap 대상에서 제외**된다(C2 Task 5 안전 제약 — wrapper는 fetch-scoped ONLY; 재시도는 append를 재구동할 수 없다). **Axiom 측 핀 필드 갱신 0건** — §2의 열거 결과다.

## 2. 동반 핀 열거 (착지 전 확정 — SSOT 4종 판독)

| SSOT | 핀 필드 | 바인딩 대상 | 본 변경의 영향 |
|---|---|---|---|
| `config/trusted_writer_set.json` | `trustedWriterWorkflow` | `.github/workflows/certificate-mint.yml` (경로만 — blob 미결속) | 불변 (경로 미변경) |
| `config/trusted_writer_set.json` | `trustedAdmissionWorkflowSha` | `admission-check.yml` blob `b2b8235d79d17ec158f4d5429691ceef65575f67` | **불변** (admission-check.yml 미편집) |
| `config/policy/epoch_manifest.json` | `productionExecutionPin` | 동일 admission blob `b2b8235d…` | **불변** (동일) |
| `config/policy/merge_admission.json` | `trustSurface` | certificate-mint.yml **경로** (변경 시 auto-merge deny → 수동 승격 경로) | 본 PR이 이 경로를 침범 → 경로 (b) 사전등록(본 문서) + `dryRunExit` 0 (TRUST_SURFACE_MODIFIED — src/cli/merge_cli.nim:1458) 로 큐 통과, 아키텍트 수동 승격 결부 |
| 컨트롤러 `Archright/.github` `admission-gate.yml` | `uses:` 핀 2건 — :481 (stage=prepare)·:538 (stage=publish), 현행 `689ff9eaf63c9e3ac8ae33aefcef84a74cb0c467` | Axiom certificate-mint.yml을 담은 **커밋** SHA (git cat-file -t = commit 실측; blob sha 불가 — admission-generation.md §2.1 "커밋 SHA 핀") | **회전 대상** — Axiom 착지 후 경로 (a) 컨트롤러 PR로 신규 Axiom main 커밋 SHA로 양 핀 동시 회전 (mint blob를 담는 핀은 이 2건이 전부) |
| `config/trusted_writer_set.json` | `trustedCheckerTreeClosure` (876 멤버 — 본 등록 시점 실측) | src/verification 등 checker 클로저 blob | **불변** — `.github/` 하위 멤버 **0건** 실측 (closureChange = false → rqNormal) |

**결론**: 자기참조 잠금(ROT_NEW_PIN self-referential lock) **없음** — mint blob를 Axiom 측에서 등록하는 핀 필드가 0건이므로(STOP 조건 "pin circularity" 불발동) Axiom PR은 핀 갱신 없이 자체 blob를 착지시키고, 회전은 경로 (a)(컨트롤러 핀 PR — 양 핀 단일 논리 단위) + §4.3 사후 ruleset 재핀으로 완결된다.

## 3. 판정 변화의 결정론성

본 변경의 판정 효과는 결정론적이다 — 9사이트의 전송 실패가 "즉시 fail-closed" → "바운디드 리트라이(4 attempts, 5/10/20s) 후 기존과 동일한 fail-closed(HTTP code 출력, 성공 증거 없음)"로 바뀌는 것이 전부이며, 같은 입력(성공 응답) → 같은 판정이다. 각 attempt는 동일 run-scoped URL을 재획득할 뿐이고 본문은 하위 단계에서 전부 재파싱·재검증된다(record identity·payloadSha256·witness byte binding). ledger append(exactly-once FF-CAS)·`cert attest --sign`·모든 POST는 wrap·변경하지 않는다 — P7b no-op/append reconciliation의 D6 재진입 허용을 확장하지 않는다. 판정 권위의 이동·추가·약화 없음(Authority ≠ Adapter, AGENTS.md §2.3).

## 4. 승인 = 착지

본 사전등록의 승인은 P3 Tier-2 PR의 착지 그 자체다(AGENTS.md §0.10 결정 바인딩 — 2026-10-16 전면 허가). 착지 이후 §1 열거 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.
