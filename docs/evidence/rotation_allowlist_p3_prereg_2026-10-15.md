# P3 first-site-group bounded-retry rotation 사전등록 — certificate-mint.yml 3-site wrappers (2026-10-15)

> **종류**: ROT_ALLOWLIST 사전등록 (docs/spec/admission-generation.md §4.2 경로 (b) — ROT_ALLOWLIST 사전 등록 레그; ADR-0025 Amendment 계보의 사전등록 규율 준수, 선례 docs/evidence/rotation_allowlist_a5_prereg_2026-10-14.md).
> **등록일**: 2026-10-15 (착지 이전 고정 — no-peeking).
> **소유자**: 2026-10-15 사용자 전면 허가(full user authorization) + 승인 계획(P3 Slice C S2 heavyweight ceremony) 하에 P3 기계적 부분을 착지 워크트리(feat/p3-download-recovery-tier1)에서 등록한다.
> **고정성**: 본 문서가 착지하는 순간 §1의 열거는 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 수록 범위 — candidate delta 경로 열거 (glob 없음)

`feat/p3-download-recovery-tier1` PR의 candidate delta는 아래 3경로로 **한정**된다:

1. `.github/workflows/certificate-mint.yml` — 기존 `fetch_admission_zip` 바운디드 리트라이 계약(DEBT#474 transport policy: max 4 attempts, backoff 5/10/20s, transient = HTTP 5xx ∪ curl transport rc, permanent = HTTP 4xx — 429는 retry하지 않는다)을 `fetch_bounded <url> <outfile> <tag>` 셸 함수로 일반화하고 3 call site에 적용:
   (P4) artifacts-list JSON GET (publish step, 기존 wrapper 직전),
   (P5) artifacts-list GET + tested-tree-digest tree.zip download (canonical tree identity step),
   (P6) jobs-page GET **단일 페이지** (gateway lane conclusion step — while-loop 자체는 wrap하지 않는다; loop-level retry의 페이지 중복 집계 부패 방지).
2. `docs/evidence/rotation_allowlist_p3_prereg_2026-10-15.md` (본 문서 — 착지와 동반).
3. `docs/evidence/p3_bounded_retry_promotion_2026-10-15.md` (변경 기록 — pin 열거, 승격 체인, 503 주입 실험, worst-case math).

미수록 경로는 본 PR의 delta에 존재하지 않는다. **Axiom 측 핀 필드 갱신 0건** — §2의 열거 결과다.

## 2. 동반 핀 열거 (착지 전 확정 — SSOT 4종 판독)

| SSOT | 핀 필드 | 바인딩 대상 | 본 변경의 영향 |
|---|---|---|---|
| `config/trusted_writer_set.json` | `trustedWriterWorkflow` | `.github/workflows/certificate-mint.yml` (경로만 — blob 미결속) | 불변 (경로 미변경) |
| `config/trusted_writer_set.json` | `trustedAdmissionWorkflowSha` | `admission-check.yml` blob `b2b8235d79d17ec158f4d5429691ceef65575f67` | **불변** (admission-check.yml 미편집) |
| `config/policy/epoch_manifest.json` | `productionExecutionPin` | 동일 admission blob `b2b8235d…` | **불변** (동일) |
| `config/policy/merge_admission.json` | `trustSurface` | certificate-mint.yml **경로** (변경 시 auto-merge deny → 수동 승격 경로) | 본 PR이 이 경로를 침범 → 경로 (b) 사전등록(본 문서) + `dryRunExit` 0 (TRUST_SURFACE_MODIFIED — src/cli/merge_cli.nim:1458) 로 큐 통과, 아키텍트 수동 승격 결부 |
| 컨트롤러 `Archright/.github` `admission-gate.yml` | `uses:` 핀 `aa051134359ee37e50bf30bcc58187c58aa6fe3a` | Axiom certificate-mint.yml 를 담은 **커밋** SHA (git cat-file: commit — PR #815 머지; blob sha가 아님 — `uses:` 핀은 커밋 SHA만 유효) | **회전 대상** — Axiom 착지 후 경로 (a) 컨트롤러 PR로 신규 Axiom main 커밋 SHA로 회전 |
| `config/trusted_writer_set.json` | `trustedCheckerTreeClosure` (876 멤버) | src/verification 등 checker 클로저 blob | **불변** — 본 delta는 클로저 멤버 0건 (`.github/workflows/**`는 클로저 비멤버; closureChange = false → rqNormal) |

**결론**: 자기참조 잠금(ROT_NEW_PIN self-referential lock) **없음** — mint blob를 Axiom 측에서 등록하는 핀 필드가 0건이므로 Axiom PR은 핀 갱신 없이 자체 blob를 착지시키고, 회전은 경로 (a)(컨트롤러 핀 PR) + §4.3 사후 ruleset 재핀으로 완결된다.

## 3. 판정 변화의 결정론성

본 변경의 판정 효과는 결정론적이다 — 3 call site의 전송 실패가 "즉시 fail-closed" → "바운디드 리트라이(4 attempts, 5/10/20s) 후 기존과 동일한 fail-closed"로 바뀌는 것이 전부이며, 같은 입력(성공 응답) → 같은 판정이다. ledger append(exactly-once FF-CAS)·`cert attest --sign`·모든 POST는 wrap 대상에서 **제외**된다(C2 Task 5 안전 제약 — wrapper는 fetch-scoped, 재시도는 append를 재구동할 수 없다). 판정 권위의 이동·추가·약화 없음(Authority ≠ Adapter, AGENTS.md §2.3).

## 4. 승인 = 착지

본 사전등록의 승인은 P3 PR의 착지 그 자체다(AGENTS.md §0.10 결정 바인딩 — 2026-10-15 전면 허가). 착지 이후 §1 열거 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.
