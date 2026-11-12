# J3 §3.3 Manifest Anchoring — 실측 기록 (2026-10-07)

**작업**: Canonical Build Reuse slice Phase 2 — J3 §3.3 manifest 앵커링 (순환성 해소) + S5 봉인 해제.
**브랜치**: `fix/j3-manifest-anchoring` (worktree `j3-manifest-anchor`, base = origin/main `558a51e48`).
**스펙**: `docs/spec/ci_optimization_tcb_judgments.md` §3.3 (구현 상태 참조), §3.1 (용어 계약).

## 1. 변경 요약

| 파일 | 변경 |
|---|---|
| `.github/actions/setup-axiom-toolchain/action.yml` | B-verify에 신뢰 입력 identity 재유도(키-파생 + 소스-파생) + 신규 semantic provenance probe step (`:317-410`, `:440-492`) + 헤더 계약 갱신 |
| `tools/ci/tcb_judgments.nim` | provenance probe report-only 행 + selftest fixture 2종 추가 (4d: 재유도 PASS, 4e: probe 마커 블록 외부 FAIL) |
| `tests/ci/test_b_cache_anchor.nim` | 신규 — action.yml 실제 스텝 본문을 추출 실행하는 파손 시뮬레이션 계약 테스트 13종 |
| `Makefile` | test-unit에 신규 테스트 등록 |
| `data/ci_pareto/selection_table.json` | S5 caveat 봉인 해제로 갱신 + updatedAt |
| `data/ci_pareto/terminal_outcome_judgment.json` | caveats에 S5 봉인 해제 기록 (본문 item은 2026-09-26 판정 시점 기록으로 보존) |
| `docs/spec/ci_optimization_tcb_judgments.md` | §3.3 구현 상태, §3.1 용어 계약, §3.7 도구 구조 |

저장 측(`ci-cache-publisher.yml`)은 변경하지 않았다 — 별도 에이전트 소관(충돌 방지). manifest schema v1의 `buildSha`/`bKey` 필드가 파생 소스(identity) 기록을 담당하며 restore-side 재유도가 그 소스를 소비한다.

## 2. 파손 시뮬레이션 3종 감지 실측

`tests/ci/test_b_cache_anchor.nim` — action.yml의 실제 B-verify python heredoc과 probe step 본문을 YAML에서 추출해 원문 그대로 실행(fixture 워크스페이스, GITHUB_OUTPUT 수집). **13/13 PASS** (`make test-unit` 포함 전체 회귀 green).

| 시나리오 | 결과 |
|---|---|
| (h) healthy | `b-verify-ok=true`, `RESULT OK — 4/4 entries digest-verified`, 파생 소스 로그 기록, 폐기 없음 |
| (a) manifest-only files{} 변조 | `sha256 mismatch` → 폐기 (기존 검증 유지) |
| (b) payload-only 바이너리 변조 | `sha256 mismatch` → 폐기 (기존 검증 유지) |
| (c) **payload+manifest 동시 변조** | digest 레이어: 자기일관 통과(원형성 사실 고정 — `b-verify-ok=true`) → **probe: provenance 불일치 감지 → 전체 B payload 폐기** |
| (i) identity 불일치 | `payload-internal identity self-claims are not an anchor` → 폐기 |
| (m) manifest 누락 / (v) vacuous files{} | 폐기 (극장 방지 유지) |
| (p1) probe healthy / (p3) content-equal 트리 | OK — semantic identity 수용(다른 커밋 트리도 src 내용 동일 시 수용) |
| (p2) probe 감지 (exit 1 = SourceCoherence FATAL 관측 계약) | 감지 → 폐기 → fail-closed 진행(잡 실패 아님) |
| (e) exp-* 네임스페이스 | SKIP — 폐기 없음 (키-파생·digest 결합만으로 운용) |
| (g) 신뢰 트리 미존재 | 폐기 (fail-closed) |

**실제 바이너리 + 실제 git 트리 감지 실측** (worktree, 재구성된 bin/ax = HEAD `cf324cb0` 트리에서 빌드):

- 정상: `AXIOM_CACHE_B_PROBE: OK — restored bin/ax embedded BuildSourceHash == trusted tree cf324cb08b9a`
- stale (신뢰 트리 = `0ad074a50` 트리 `7f1bdbac05e8` — DEBT#495 커밋, src 재계산 해시 `-9023095428418420061` vs HEAD `-7055811655676579384`):
  `AXIOM_CACHE_B_PROBE: FAIL — restored bin/ax provenance != trusted tree 7f1bdbac05e8 (SourceCoherence FATAL ...)` → `DISCARDED` → bin/ax 등 4 바이너리 실제 소멸 확인.
- 내용 동일 트리(`0275ec34d` — 마지막 src 변경 커밋, src 서브트리가 HEAD와 동일): probe OK — **바이트/커밋 단위가 아닌 semantic identity 수용 확인** (J1 §1.2 준수).

## 3. S5 판정 전환 실측

```
$ bin/tcb_judgments --judgment cache-manifest --workflow <action.yml>
변경 전 (origin/main): exit 2 — "cache-manifest CIRCULAR ... JUDGMENT-FAIL (exit 2) — improvement P2-3(a) not yet landed"
변경 후 (본 브랜치):   exit 0 — "cache-manifest PASS — files{} verification uses a trusted-input-derived expectation + semantic provenance probe (simultaneous payload+manifest contamination covered)"
$ bin/tcb_judgments selftest
[selftest] results: 12 passed, 0 failed  (기존 10 + 신규 2)
```

`data/ci_pareto/selection_table.json:13` processCaveats의 "S5 cache optimization blocked on J3 (cache-manifest circularity, exit 2)" → 봉인 해제 기록으로 갱신. S5(B-적중 빌드-스킵)의 기계적 선행조건(J3 exit 0)이 충족되었다 — S5 최적화 자체의 도입은 별도 슬라이스다.

## 4. HIT = 공급 재사용 (용어 계약) 확인

- `action.yml` 헤더: "HIT = verified computation (program warmth) SUPPLY REUSE — verdicts are always recomputed (the 4 ci-compile binaries are recompiled even on a HIT today; census 2026-09-30) — cache is acceleration, never evidence."
- `docs/spec/ci_optimization_tcb_judgments.md` §3.1: HIT = "검증된 계산(프로그램) 공급 재사용 — 판정은 항상 재계산" — S5가 빌드-스킵을 도입해도 생략되는 것은 검증된 공급의 재사용이며 판정 재계약이 아님을 명시. "cache ≠ evidence" 불변 유지.
- 본 변경은 판정 재계산 경로를 건드리지 않는다 — restore-side 검증만 강화되었다(소비자 무회귀: test-unit 전체 green, B-verify 실패/폐기 시 기존 cold fallback 경로 동일).

## 5. G7 + canonical digest (MUST 불변)

- `make verify-contract-release-e2e-full` — **G7 PASS**: `INFO: G7 pass (tier=z3-verified status=not_verifiable vaultPath=)` + `✅ verify-contract-release-e2e-full PASSED`. report 요약 failedCount=0·timeoutCount=0 — main clone의 기존 G7 report(`logs/verify_contract_e2e_report.json`, 2026-10-07 19:15, 본 작업 이전)와 동일 형태(totalSourceFunctions=40, failedCount=0, 동일 노드 `normalizeMaxWorkers -> not_verifiable (z3-verified)`)로 **기저 상태 회귀 없음** 확인.
- `bin/ax report --canonical-digest` ×2 — **동일**: `46a1b2607c4fc01908809f94e3b62ae8b40b9fe42907f9603e2b883bf0e985eb` ×2 (MUST 불변 실측).

## 6. 잔여 위험 (정직 기록)

- **동시 변조 중 bin/ax 이외의 3바이너리만 교체 + manifest 재작성** 케이스는 restore-side에서 미검출이다 — bin/ax만 SourceCoherence 자기검증을 갖는다(`src/cli/main.nim` 단수 임베드). 완전 커버는 save-side 서명(ed25519, §3.3 기준 (3)) 또는 3바이너리의 provenance 임베드 확장이 필요하며 publisher 권한이 요구된다. 현 단계에서 이 클래스는 exact-key + identity 결합 + 실행 시 게이트 판정으로 전이적으로 구속된다.
- probe는 libpcre 존재를 전제로 install step 이후 배치되었다 — libpcre 설치 실패 시 잡 자체가 중단되므로 probe 공백은 발생하지 않는다.
- action.yml 변경은 script_hash(A-layer 키 성분)를 바꾼다 — 착지 후 A/B 키 전면 1회 무효화(one-shot cold, 헤더 계약 문서화된 동작).
