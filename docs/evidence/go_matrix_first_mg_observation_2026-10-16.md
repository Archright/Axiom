# G2 첫 production MG 관측 — 2-lane 매트릭스 첫 실행 (2026-10-16)

> **종류**: 실행 증거 문서 (first-production-MG observation) — 사전등록 `docs/evidence/go_matrix_parallelization_prereg_2026-10-16.md` §8의 S2-이월 검증 항목(per-lane EXECUTED + 실제 Judgment-CAS)과 §4.1 D4-composite의 **1차 데이터 포인트**를 등록한다. 성능 판정(S3)은 아니다 — §5의 ≥5 PR 표본이 필요하다.
> **관측 대상**: 신세대 ruleset 핀(controller `74b415c414c0…` → Axiom admission-check.yml `64f78ab7d178…`, blob `f2ad3b03`) 아래의 **첫 merge_group admission 런**.
> **상태**: 메커니즘 선기록(no-peeking 규율 — 관측 전 추출 절차 고정, 결과는 관측 후 기입).

## 1. 관측 절차 (사전등록 §4.3 verbatim — 관측 전 고정)

1. MG 런 식별: `gh api repos/Archright/Axiom/actions/runs?event=merge_group` — ruleset 재핀(2026-10-15T20:11Z) 이후 생성된 첫 `admission-gate` 런.
2. 레인 job 목록·conclusion·runner: `.../runs/<ID>/jobs` — `attest / go-critical-lane (0|1)` 이름 확인.
3. per-lane EXECUTED 증거: 각 레인 job 로그에서 `RUN make test-fast-one` / `PASS — <test>` / `basis=EXECUTED` 라인 + Judgment-CAS plan 스테이징 라인(과목별 decision 파일).
4. attest 소비: `attest / admission-check` job 로그의 judgment record fail-closed 루프 라인(4 subject record) + armed attest 라인.
5. D4 스텝 1차값: jobs API steps[]의 GO 스텝(레인) started_at→completed_at (API 초) + 레인 셋업 경계(체크아웃 시작→GO 직전).
6. 집계·착지: `admission-check` required check success, MG 런 success, native MERGE 커밋(parents=2), ruleset readback (`74b415c414c0…` 유지).

## 2. 세레머니 체인 기록 (착지 확정분 — 2026-10-15 실측)

- Axiom #861 (d8bc0f0a6ece, 18:59:14Z) → 결함 발견(레인 job 정의 누락 — 0-job 계획 거부) → §7 앵커 롤백(rulesets → f26306b453, freeze/readback) → Axiom #863 핫픽스 (64f78ab7d178, 20:05:50Z, blob f2ad3b03 + 핀 동기) → Controller #224 (74b415c414c0, 20:09:52Z, PINNED OK) → ruleset 재핀 (24233738+23943917 → 74b415c414c0, config 비-sha diff 없음, freeze 2→0→2 readback) → 태그 `admission-gen-h4b-20261016`.
- 결함 세대의 태그 `admission-gen-h4-20261016` (b26fbbd882)는 역사 기록으로 보존(삭제하지 않음 — 고정 세대의 실패는 세대 이력의 일부다).

## 3. 관측 결과 (관측 후 기입 — 아래 §4)

TBD (MG 런 ID, 레인별 EXECUTED/CAS 라인, D4-composite, 집계·착지 — §1 절차 산출물)

## 4. 편차

TBD
