# P3 FINAL site-group bounded-retry rotation 사전등록 — certificate-mint.yml 24-site wrappers (2026-10-16)

> **종류**: ROT_ALLOWLIST 사전등록 (docs/spec/admission-generation.md §4.2 경로 (b) — ROT_ALLOWLIST 사전 등록 레그; ADR-0025 Amendment 계보의 사전등록 규율 준수, 직전 선례 [rotation_allowlist_p3t2_prereg_2026-10-16.md](rotation_allowlist_p3t2_prereg_2026-10-16.md)).
> **등록일**: 2026-10-16 (착지 이전 고정 — no-peeking).
> **소유자**: 2026-10-16 사용자 전면 허가(full user authorization) + 승인 계획(P3 FINAL site-group generation promotion — 4번째 ceremony 실행, PR #850/E3·#856/F2 절차 전수 재사용) 하에 P3 기계적 부분을 신규 워크트리(`feat/p3final-bounded-retry-generation`, origin/main `7be55445d` 기점)에서 등록한다.
> **고정성**: 본 문서가 착지하는 순간 §1의 열거는 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 수록 범위 — candidate delta 경로 열거 (glob 없음)

`feat/p3final-bounded-retry-generation` PR의 candidate delta는 아래 3경로로 **한정**된다:

1. `.github/workflows/certificate-mint.yml` — 착지된 일반화 셸 함수 `fetch_bounded`(Tier-1 PR #850 착지, Tier-2 PR #856이 byte-identical 6카피로 확장)를 **잔여 24 curl 사이트 전부**에 적용해 DEBT#474의 "무재시도 다운로드 사이트"를 0으로 만든다(파일 내 bare curl 호출 0건 목표). 라인번호는 기점 `7be55445d` 원문 판독값:

   **zip 다운로드 4사이트**:
   - `:592` prepare build-base-artifacts — base.zip (`$art_id/zip`, `$RUNNER_TEMP/base.zip`),
   - `:785` prepare (3) artifact retrieval — admission.zip (`$art_id/zip`, `$RUNNER_TEMP/admission.zip`),
   - `:1239` publish (P1) — cert.zip (`$art_id/zip`, `$RUNNER_TEMP/cert.zip`),
   - `:1723` publish (P6) skipped-lane justification — decision.zip (`$art_id/zip`, `$RUNNER_TEMP/decision.zip`; `ci-select-decision` artifact — 순수 읽기).

   **JSON API GET 18사이트** (idempotent 순수 읽기 — artifacts lists·runs·pulls·git/commits):
   - prepare (0): `:258` run_obj, `:284` pr_obj —
   - prepare (1): `:348` run_obj, `:393` commit_obj(merge_group 지점), `:418` pr —
   - prepare consume: `:582` artifacts-list —
   - prepare (2a/b/c): `:698` r_obj, `:707` commit_obj, `:719` pr_obj —
   - publish (P0): `:1143` run_obj, `:1170` pr_obj —
   - publish (P4): `:1341` commit_obj(subject re-derive), `:1490` commit_obj(tree(mergeSha)) —
   - publish (P5): `:1592` commit_obj(tree(github.sha)) —
   - publish (P6): `:1716` artifacts-list(skipped-lane justification).

   **contents API GET 2사이트** (raw 판독 — 순수 읽기):
   - prepare (2a): `:675` admission workflow blob@B (`Accept: application/vnd.github.raw+json`),
   - publish slice-engine: `:1076` epoch manifest@B (동일 raw Accept).

   **Accept 헤더 일반화 (본 세대의 유일한 함수 본문 변경)**: 착지 함수는 JSON Accept를 하드코딩하며 raw contents 2사이트는 그대로 래핑하면 본문 표현이 달라진다. 본 PR은 함수에 **선택 제4인자 `accept`(기본값 `application/vnd.github+json`)**를 추가한다 — 기존 3-인자 호출의 와이어 요청은 byte-동일(기본값 = 기존 헤더), raw 2사이트만 4번째 인자로 `application/vnd.github.raw+json`을 전달하며 이는 각 사이트가 오늘 보내는 요청과 byte-동일하다. 파싱·검증 로직 변경 0건, 재시도 계약 변경 0건. 함수 15카피(기존 6 + 신규 9)는 전부 byte-identical로 유지한다(주입 하니스의 단일 sha 실측 유지). P4 스텝의 `fetch_bounded` 정의블록은 첫 사용 지점(:1341 subject re-derive GET) 앞으로 **동일 스텝 내 이동**된다(주문 전 정의 — bash 요구). `fetch_admission_zip`(P4, Tier-1 원본)은 현행 유지 — 무변경.

   계약(재사용 — 신규 정의 없음): max **4 attempts**, backoff **5s/10s/20s**; transient = curl transport rc ≠ 0(transport) ∪ 최종 HTTP 5xx; permanent = 최종 HTTP 4xx — **429는 transient가 아니다(재시도하지 않는다**, 2026-10-15 contract alignment); 소진 시 HTTP code/curl rc 출력과 함께 **명시적 실패, 성공 증거 없음**(기존과 동일한 fail-closed). 로그 계약: `MINT_FETCH_RETRY: <tag> attempt $a/4 — HTTP $code (transient)` / `(curl rc=$rc, http_code=$code)` / `(permanent — not retried)`.

   **제외 (C2 Task 5 안전 제약 — 무변경 확인)**: 모든 ledger append(`ax cert ledger-append`, `ax evidence ledger-append` — `ax` CLI, curl 아님)·`cert attest --sign`·모든 POST(파일 내 POST 0건 실측)는 wrap 대상이 아니며, P6 pagination while-loop 자체는 여전히 래핑하지 않는다(단일 페이지 GET만 래핑 — Tier-1 착지 상태 그대로; 루프 레벨 재시도는 jq_tmp 페이지 재적재 corruption). wrapper는 fetch-scoped ONLY — 재시도는 append를 재구동할 수 없다.
2. `docs/evidence/rotation_allowlist_p3final_prereg_2026-10-16.md` (본 문서 — 착지와 동반).
3. `docs/evidence/p3final_bounded_retry_promotion_2026-10-16.md` (변경 기록 — pin 열거, 승격 체인, worst-case math).

**미수록 경로는 본 PR의 delta에 존재하지 않는다.** admission-check.yml·runner-pool-acceptance.yml·setup-axiom-toolchain·config/·src/ 는 미편집이다. **Axiom 측 핀 필드 갱신 0건** — §2의 열거 결과다.

## 2. 동반 핀 열거 (착지 전 확정 — SSOT 판독, 기점 커밋 `7be55445d` / 컨트롤러 main `74b415c414c0a501a1df125ad92289f0bac17bde` 판독)

| SSOT | 핀 필드 | 바인딩 대상 | 본 변경의 영향 |
|---|---|---|---|
| `config/trusted_writer_set.json` | `trustedWriterWorkflow` | `.github/workflows/certificate-mint.yml` (경로만 — blob 미결속) | 불변 (경로 미변경) |
| `config/trusted_writer_set.json` | `trustedAdmissionWorkflowSha` | `admission-check.yml` blob | **불변** (admission-check.yml 미편집) |
| `config/policy/epoch_manifest.json` | `productionExecutionPin` | 동일 admission blob | **불변** (동일) |
| `config/policy/merge_admission.json` | `trustSurface` | certificate-mint.yml **경로** | 본 PR이 이 경로를 침범 → 경로 (b) 사전등록(본 문서) + `dryRunExit` 0 (TRUST_SURFACE_MODIFIED — src/cli/merge_cli.nim) 로 큐 통과, 아키텍트 수동 승격 결부 |
| 컨트롤러 `Archright/.github` `admission-gate.yml` | `uses:` 핀 2건 — :481 (stage=prepare)·:538 (stage=publish), 현행 `b8220e2b17ab347208751b8230e7b639cec9aef9` | Axiom certificate-mint.yml을 담은 **커밋** SHA (`git cat-file -t` = commit — blob sha 불가) | **회전 대상** — Axiom 착지 후 경로 (a) 컨트롤러 PR로 신규 Axiom main 커밋 SHA로 양 핀 동시 회전 (mint blob를 담는 핀은 이 2건이 전부) |
| 컨트롤러 `Archright/.github` `admission-gate.yml` | `uses:` 핀 2건 — :430·:650 admission-check, 현행 `64f78ab7d178bb9570ad05f4eef9189530f784c8` | Axiom admission-check.yml (G2 h4b 현행) | **보존** — 본 PR은 admission-check.yml을 편집하지 않으므로 회전하지 않는다 |
| 컨트롤러 `Archright/.github` `admission-gate.yml` | `uses:` 핀 — :256 setup-axiom-toolchain·:573 runner-pool-acceptance, 현행 `ba773d0631b5757525b16d8fd62e220492e98e76` | runner-pool 세대 | **무변경** (터치 금지) |
| `config/trusted_writer_set.json` | `trustedCheckerTreeClosure` | src/verification 등 checker 클로저 blob | **불변** — `.github/`·`docs/` 하위 멤버 없음 (closureChange = false → rqNormal 예상) |

**결론**: 자기참조 잠금(ROT_NEW_PIN self-referential lock) **없음** — mint blob를 Axiom 측에서 등록하는 핀 필드가 0건이므로 Axiom PR은 핀 갱신 없이 자체 blob를 착지시키고, 회전은 경로 (a)(컨트롤러 핀 PR — 양 핀 단일 논리 단위) + §4.3 사후 ruleset 재핀(24233738·23943917 — 현행 `74b415c414…` → 신규 컨트롤러 HEAD, freeze/unfreeze 20303214)으로 완결된다.

## 3. 판정 변화의 결정론성

본 변경의 판정 효과는 결정론적이다 — 24사이트의 전송 실패가 "즉시 fail-closed" → "바운디드 리트라이(4 attempts, 5/10/20s) 후 기존과 동일한 fail-closed(HTTP code 출력, 성공 증거 없음)"로 바뀌는 것이 전부이며, 같은 입력(성공 응답) → 같은 판정이다. 각 attempt는 동일 run-scoped URL을 재획득할 뿐이고 본문은 하위 단계에서 전부 재파싱·재검증된다(artifact exactly-one + expired=false, blob sha 결속, commit object 재유도, witness byte binding). contents 2사이트의 raw Accept는 4번째 인자로 보존되어 오늘과 byte-동일한 요청이 나간다. ledger append(exactly-once FF-CAS)·`cert attest --sign`·모든 POST는 wrap·변경하지 않는다. 판정 권위의 이동·추가·약화 없음(Authority ≠ Adapter, AGENTS.md §2.3).

## 4. 승인 = 착지

본 사전등록의 승인은 P3 FINAL PR의 착지 그 자체다(AGENTS.md §0.10 결정 바인딩 — 2026-10-16 전면 허가). 착지 이후 §1 열거 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다.
