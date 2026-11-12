# v5 acceptance B2 — 동일 closure 재사용 종결 (2026-10-22)

N-제외 `.md` 단독 변경 → 판정 closure는 PR #1019(v5.1 outcome-semantics 세대)가 발화한 v5 기록과 동일
(s1a `644f058cb5db…`, proof_integrity `b489f86ad4a5…`, d2_golden `c75da17e5463…`, d2_persist 포함).

기대: 4개 subject 전부 `AXIOM_JUDGMENT_CAS: REUSED — record <12hex> re-verified (closure re-derivation + executionEpoch
+ per-read re-hash all passed)` → `[admission-tests] SKIP (basis=REUSED)` → `exec-record[*] verdict=UNKNOWN basis=REUSED`
→ lane green (outcome-시맨틱 guard) → attest `[go-exec] exec record[*] OK — verdict=UNKNOWN basis=REUSED decision=REUSED`
→ MERGED + EXECUTED 대비 착지 시간 단축. `verdict=UNKNOWN`은 실행 결과가 아니라 재인증 승인 근거다.
