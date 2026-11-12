# P3 first-site-group bounded-retry promotion — 변경 기록 (2026-10-15)

> **종류**: 변경·승격 기록 (docs/spec/admission-generation.md §4 경로 (b)+(a) 수행 기록 — Slice C S2 heavyweight ceremony).
> **소속 PR**: `feat/p3-download-recovery-tier1` (본 PR — Axiom 측) + 컨트롤러 핀 회전 PR (Archright/.github) + ruleset 재핀 + 503 주입 실험 + 무인 착지 수용.
> **사전등록**: [rotation_allowlist_p3_prereg_2026-10-15.md](rotation_allowlist_p3_prereg_2026-10-15.md) (착지 전 고정 — no-peeking).

---

## 1. 변경 내용 — certificate-mint.yml 3-site bounded-retry wrappers (DEBT#474 transport policy 일반화)

Slice B S1(PR #843)이 증명한 `fetch_admission_zip` 바운디드 리트라이 계약(max 4 attempts, backoff 5s/10s/20s; transient = curl transport rc != 0 ∪ 최종 HTTP 5xx; permanent = 최종 HTTP 4xx — **429는 transient가 아니다**, 2026-10-15 contract alignment; 소진 시 명시적 실패, 성공 증거 없음)을 재사용 가능 셸 함수 `fetch_bounded <url> <outfile> <tag>`로 일반화하고 3 call site에 적용했다:

| # | 사이트 | 위치 (본 PR 기준) | 계약 다리 | 변화 |
|---|---|---|---|---|
| 1 | (P4) artifacts-list JSON GET | publish step, 기존 wrapper 직전 | DEBT#474 측정 경로의 선행 fetch — 503 시 wrapper에 도달 못 함 | 즉시 fail-closed → 바운디드 리트라이 |
| 2 | (P5) artifacts-list GET + tested-tree-digest tree.zip | canonical tree identity step | [B2](b) — 전송 실패가 fully-green run을 red로 전환 | 두 fetch 모두 wrapper 적용 |
| 3 | (P6) jobs-page GET **단일 페이지** | gateway lane conclusion step | [B2](c) — paginated | **단일 페이지 GET만** wrap; while-loop 자체는 wrap 금지 (loop-level retry의 페이지 중복 집계 부패 방지) |

**안전 제약 준수 (C2 Task 5)**: ledger append(exactly-once FF-CAS — ax cert ledger-append, ax evidence ledger-append ×3)·`cert attest --sign`·모든 POST는 wrap·변경하지 않았다. `fetch_bounded`는 fetch-scoped로 재시도가 append를 재구동할 수 없다. 기존 `fetch_admission_zip` wrapper의 call-site 동작은 **무변경**이다.

**로그 계약**: 최종 실패 로그는 HTTP code / curl rc를 출력한다(`MINT_FETCH_RETRY: <tag> attempt $a/4 — HTTP $code (transient)` / `(curl rc=$rc, http_code=$code)` / `(permanent — not retried)`) — merge-queue-rearm.yml TRANSIENT (b) 앵커(`curl: (7|28|35|56)|5xx|429` + `download|artifact|admission-check-`)와 호환. 429는 `permanent — not retried`로 출력되되 재시도하지 않는다(분류는 rearm 앵커의 현행 상태를 따른다 — E1 착지 여부와 무관하게 본 PR은 429 retry를 추가하지 않는다).

## 2. 동반 핀 열거 (사전등록 §2 요약 — 착지 전 확정)

- **Axiom 측 핀 갱신 0건**: `trustedAdmissionWorkflowSha`·`productionExecutionPin`은 모두 `admission-check.yml` blob `b2b8235d79d17ec158f4d5429691ceef65575f67`에 결속 — 본 PR은 그 파일을 편집하지 않는다. `trustedWriterWorkflow`는 경로 선언만이다.
- **컨트롤러 핀 1건 (회전 대상)**: `Archright/.github` `admission-gate.yml`의 `uses:` 핀 `aa051134359ee37e50bf30bcc58187c58aa6fe3a` — `git cat-file -t` = **commit** (PR #815 머지; `uses:` 핀은 blob sha를 받지 않는다). 회전 값 = 본 PR 착지 후의 Axiom main 커밋 SHA (경로 (a) — §4.1).
- **trustedCheckerTreeClosure (876 멤버)**: `.github/workflows/**`는 비멤버 — closureChange = false (rqNormal), 클로저 무영향.
- **trustSurface**: certificate-mint.yml 포함 — 본 PR은 TRUST_SURFACE_MODIFIED (dryRunExit 0 — src/cli/merge_cli.nim:1458) 로 큐를 통과하며, 아키텍트 수동 승격 경로의 결합 통제는 사전등록 문서(본 PR 동반) + CODEOWNERS 리뷰가 담당한다.
- **ROT_NEW_PIN 자기참조 잠금 없음** — STOP 조건 불발동.

## 3. 착지 체인 (수행 순서 — 본 섹션은 착지 후 갱신된다)

| 단계 | 내용 | 증거 |
|---|---|---|
| S-A | Axiom PR (본 PR) — 3-site wrappers + prereg + 본 기록 | (착지 후 기입) |
| S-B | 컨트롤러 핀 회전 PR (Archright/.github) — aa0511343… → 신규 Axiom main 커밋 | (기입 예정) |
| S-C | ruleset 24233738·23943917 재핀 (§4.3 — 신규 컨트롤러 HEAD, readback 검증) | (기입 예정) |
| S-D | 통제 503 주입 실험 (queue-probe branch-local; 503→200 / always-503 / 404 / 429) | (기입 예정) |
| S-E | 무인 착지 수용 — docs 증거 PR의 4중 증거 (E1–E4) | (기입 예정) |

### S-A 로컬 검증 (착지 전 — 실측)

- `make check-workflow-shell-syntax` → PASS (169 run blocks, failures=0 — bash -n 전수 + parse-poison: 표현식 토큰 run 스칼라 21,000 초과 0건)
- `tools/ci/verify_trusted_writer_set.sh` → PASS (certificate-mint.yml = 선언된 단일 writer; admission blob 결속 불변)
- `bin/debt_engine --validate` → PASS (architecture_debt 510 + debt_registry 236 entries, schema·disjointness·cross-file 일관)
- `make check-repository-surface` → PASS (add/modify/delete/rename 0)
- pre-commit(worktree 배치·게이트 파이프라인) + pre-push(exact-OID admissibility) → 커밋/푸시 시 실측 (아래 §3 갱신에 기입)

## 4. 최악 지연 상한 (LAYERED worst-case math — 본 변경이 추가하는 것)

래핑된 3 GET 각각의 최대 전송 소모 = 4 attempts × (timeout + backoff 5+10+20s). PR head 1개당 총 래핑 사이트 시도 상한 = **4 × 3 sites + auto-requeue 1 = 13 attempts-of-record**. 이는 기존 fail-closed(1 attempt 후 red) 대비 최악 지연을 늘리지만, 성공 수렴 시 재런(런 1건 전체, 실측 7m21s — DEBT#474)을 절약한다. 소진 시에도 최종 상태는 기존과 동일한 명시적 실패(성공 증거 없음)다.
