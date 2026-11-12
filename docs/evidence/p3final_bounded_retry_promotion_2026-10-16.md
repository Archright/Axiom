# P3 FINAL site-group bounded-retry promotion — 변경 기록 (2026-10-16)

> **종류**: 변경·승격 기록 (docs/spec/admission-generation.md §4 경로 (b)+(a) 수행 기록 — P3 FINAL site-group ceremony, 4번째 실행; 절차 전수 재사용 선례 [p3t2_bounded_retry_promotion_2026-10-16.md](p3t2_bounded_retry_promotion_2026-10-16.md) + [p3t2_landing_acceptance_2026-10-16.md](p3t2_landing_acceptance_2026-10-16.md)).
> **소속 PR**: `feat/p3final-bounded-retry-generation` (본 PR — Axiom 측) + 컨트롤러 핀 회전 PR (Archright/.github) + ruleset 재핀 + 통제 503 주입(스팟 체크) + 무인 착지 수용.
> **사전등록**: [rotation_allowlist_p3final_prereg_2026-10-16.md](rotation_allowlist_p3final_prereg_2026-10-16.md) (착지 전 고정 — no-peeking).
> **DEBT#474**: 본 PR은 DEBT#474("503 retry policy 미정의")의 최종 잔여분 — bare curl 24사이트 —를 제거한다. 착지·grep 감사 확인 후 별도 레지스트리 폐쇄 PR로 closed 처리한다(#848 선례).

---

## 1. 변경 내용 — certificate-mint.yml 24-site bounded-retry wrappers (파일 내 bare curl 0화)

Tier-1(PR #850)이 착지하고 Tier-2(PR #856)가 9사이트로 확장한 `fetch_bounded <url> <outfile> <tag> [accept]` 일반화 계약(4 attempts, 5/10/20s; transient = curl transport rc ≠ 0 ∪ 최종 HTTP 5xx; permanent = 최종 HTTP 4xx incl. 429 무재시도; 소진 = HTTP code/curl rc 출력과 함께 명시적 실패)을 **잔여 24 curl 사이트 전부**에 적용한다. 본 세대의 유일한 함수 본문 변경은 **선택 제4인자 `accept`(기본값 `application/vnd.github+json`)** — 기존 호출 와이어 byte-동일, raw contents 2사이트만 `application/vnd.github.raw+json`을 오늘과 동일하게 전달한다. 함수 15카피 전부 byte-identical.

| # | 스텝 | 사이트 | 래핑 대상 fetch |
|---|---|---|---|
| 1 | (0) activation guard | run-object JSON GET | `actions/runs/$RUN_ID` |
| 2 | (0) | PR-object JSON GET | `pulls/$PR_NUMBER` |
| 3 | (1) derive B/H | run-object JSON GET | `actions/runs/$RUN_ID` |
| 4 | (1) | git-commit JSON GET (merge_group 지점) | `git/commits/$RUN_HEAD` |
| 5 | (1) | PR-object JSON GET | `pulls/$N` |
| 6 | consume build-base-artifacts | artifacts-list JSON GET | `runs/$RUN_ID/artifacts` |
| 7 | consume | base.zip 다운로드 | `artifacts/$art_id/zip` |
| 8 | (2a/b/c) identity | admission blob contents GET@B (raw) | `contents/$ADMISSION_PATH?ref=$B` |
| 9 | (2a/b/c) | run-object JSON GET | `actions/runs/$RUN_ID` |
| 10 | (2a/b/c) | git-commit JSON GET | `git/commits/$r_head` |
| 11 | (2a/b/c) | PR-object JSON GET | `pulls/$PR_NUMBER` |
| 12 | (3) artifact retrieval | artifacts-list JSON GET | `runs/$RUN_ID/artifacts` |
| 13 | (3) | admission.zip 다운로드 | `artifacts/$art_id/zip` |
| 14 | (3b) tree identity | git-commit JSON GET | `git/commits/$w_merge` |
| 15 | slice-engine | epoch manifest contents GET@B (raw) | `contents/config/policy/epoch_manifest.json?ref=$B` |
| 16 | (P0) publish guard | run-object JSON GET | `actions/runs/$RUN_ID` |
| 17 | (P0) | PR-object JSON GET | `pulls/$PR_NUMBER` |
| 18 | (P1) artifact identity | artifacts-list JSON GET | `runs/$RUN_ID/artifacts` |
| 19 | (P1) | cert.zip 다운로드 | `artifacts/$art_id/zip` |
| 20 | (P4) field binding | git-commit JSON GET (subject re-derive) | `git/commits/$H` |
| 21 | (P4) | git-commit JSON GET (tree(mergeSha)) | `git/commits/$w_merge` |
| 22 | (P5) tree identity | git-commit JSON GET (tree(github.sha)) | `git/commits/$git_sha` |
| 23 | (P6) skipped-lane justification | artifacts-list JSON GET | `runs/$RUN_ID/artifacts` |
| 24 | (P6) | decision.zip 다운로드 | `artifacts/$art_id/zip` |

함수 정의 배치: 신규 카피 9건 — (0), (1), consume, (2a/b/c), (3), (3b), slice-engine, (P0), (P1). 기존 카피 6건 — (P4)〔첫 사용 앞으로 동일 스텝 내 이동〕, (P5), (P6), (P7b), (P7c), (P7c-x). `fetch_admission_zip`(P4)은 무변경 유지.

**안전 제약 준수 (C2 Task 5)**: ledger append(`ax cert ledger-append`·`ax evidence ledger-append` — curl 아님)·`cert attest --sign`·POST(0건)는 wrap·변경 없음. P6 pagination while-loop 자체는 래핑하지 않는다(단일 페이지 GET만 — Tier-1 착지 규약 유지). `fetch_bounded`는 fetch-scoped ONLY.

**로그 계약**: `MINT_FETCH_RETRY: <tag> attempt $a/4 — HTTP $code (transient)` / `(curl rc=$rc, http_code=$code)` / `(permanent — not retried)` — 기존 세대와 동일 앵커 형식. 태그 체계: `<스텝> <대상> GET (JSON GET)` / `(raw contents GET)` / `… zip download (artifact)`.

## 2. 동반 핀 열거 (사전등록 §2 요약 — 착지 전 확정)

- **Axiom 측 핀 갱신 0건**: `trustedAdmissionWorkflowSha`·`productionExecutionPin`은 `admission-check.yml` blob 결속 — 본 PR은 그 파일을 편집하지 않는다. `trustedWriterWorkflow`는 경로 선언만이다.
- **컨트롤러 핀 2건 (회전 대상 — mint blob를 담는 전부)**: `Archright/.github` `admission-gate.yml` `uses:` :481(stage=prepare)·:538(stage=publish), 현행 `b8220e2b17ab347208751b8230e7b639cec9aef9` — 회전 값 = 본 PR 착지 후의 Axiom main 커밋 SHA, 양 핀 단일 논리 단위 동시 회전.
- **보존 핀**: admission-check :430·:650 = `64f78ab7d178bb9570ad05f4eef9189530f784c8`(G2 h4b 현행 — 읽기 전 판독 후 회전 금지), runner-pool :256·:573 = `ba773d0631b5757525b16d8fd62e220492e98e76` — 무변경.
- **trustedCheckerTreeClosure**: `.github/`·`docs/` 하위 멤버 없음 — closureChange = false (rqNormal 예상).
- **trustSurface**: certificate-mint.yml 포함 — TRUST_SURFACE_MODIFIED (dryRunExit 0) 로 큐 통과, 결합 통제는 사전등록 + 회전 체인이 담당.
- **ROT_NEW_PIN 자기참조 잠금 없음** — STOP 조건(핀 순환) 불발동.

## 3. 착지 체인 (수행 순서 — 본 섹션은 착지 후 갱신된다)

| 단계 | 내용 | 증거 |
|---|---|---|
| S-A | Axiom PR (본 PR) — 24-site wrappers + prereg + 본 기록 | (착지 후 기입) |
| S-B | 컨트롤러 핀 회전 PR (Archright/.github) — b8220e2b… ×2 → 신규 Axiom main 커밋 | (기입 예정) |
| S-C | ruleset 24233738·23943917 재핀 (§4.3 — 신규 컨트롤러 HEAD, readback 검증) + 세대 태그 | (기입 예정) |
| S-D | 통제 503 주입 스팟 체크 (h4-routing-measure experiment branch; always-503 소진 1케이스 — E3 4계약 입증 재사용) | (기입 예정) |
| S-E | 무인 착지 수용 — docs 증거 PR의 4중 증거 (E1–E4) | (기입 예정) |

### S-A 로컬 검증 (착지 전 — 실측)

- `make check-workflow-shell-syntax` → **PASS** (173 run blocks, failures=0, lane-guard violations=0 — bash -n 전수 + 파스 독 룰 포함)
- parse-poison → **PASS** (certificate-mint.yml 최대 발식 스칼라 **10,831자 < 21,000** — jobs/publish/steps[9]/run((P4)); F2 기록 6,066에서 함수 9카피 추가로 증가)
- `tools/ci/verify_trusted_writer_set.sh` → **PASS** (certificate-mint.yml = 선언된 단일 writer; admission blob 결속 `f2ad3b03b3…` 불변 — G2 세대(#861/#863) 이후 현행값, 본 PR 미편집)
- `bin/debt_engine --validate` → **PASS** (**1489 total, 1489 passed, 0 failed; Metric evaluation: 3 PASS, 0 DRIFT** — 신규 DRIFT 0)
- `make check-repository-surface` → **PASS** (add/modify/delete/rename/other = 0)
- 함수 카피 단일성 실측: `fetch_bounded` 정의 **15카피, distinct-sha 1** (`802f8ddeaef7cb0c95d855435e6b4588835b628f5b71ffcc80334f03a54024a1`)
- bare curl 잔여 실측: `curl -fsSL` **0건** (파일 내 curl = 15카피 함수 본문 내부 `curl -sSL` + `fetch_admission_zip` 본문 1건만 존재)
- 게이트/부트스트랩 기계 산출물 동반 (사전등록 §1 열거 밖 — 기계적 재생성분, F2 착지 커밋 c37723388의 perf_latest.json 동반 선례와 동일 계열): `data/benchmarks/perf_latest.json`(L2 게이트 Phase 2c `make test` 재생성 — provenance.commit 필드 갱신 + LeanKernelVerification 실측 갱신), `src/generated/build_metadata.json`(문서화된 CLI 부트스트랩 빌드 재생성 — main의 2026-10-13 정체 메타데이터 catch-up: gitHash→7be5544, commitCount 2988, 10-13 이후 착지 모듈 행 추가. 판정 무영향 — 생성 데이터의 SSOT 정합화)

## 4. 최악 지연 상한 (LAYERED worst-case math — 본 변경이 추가하는 것)

래핑 호출-사이트 총계(본 PR 적용 후 파일 grep 실측): `fetch_bounded` 호출 **37곳**(기존 13: P4 artifacts·P5 artifacts+tree.zip·P6 jobs-page·P7b×3·P7c×3·P7c-x×3 + 신규 24) + `fetch_admission_zip` 1곳(P4, Tier-1 원본) = **38 invocations** × 사이트당 최대 4 attempts = **152 + merge-queue auto-requeue 1 = 153 attempts-of-record** worst case (F2 기록 53에서 +100). 사이트별 최악 체감 지연 = 4 attempts + backoff 5+10+20s(=35s) + 각 attempt의 전송 시간. 소진 시 최종 상태는 기존과 동일한 명시적 실패(성공 증거 없음 — fail-closed 유지). 이익: GitHub 일시 5xx를 사이트 내 흡수 — 런 전체 재실행(DEBT#474 실측 7m21s 손실) 제거.
