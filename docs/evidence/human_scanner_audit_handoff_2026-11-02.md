# 인간 감사 Handoff — bytesview 정본 증거 파이프라인 (fix/upstream-receipt-evidence)

- 일자: 2026-11-02
- 대상 변경집: `985d1e302` (워크스트림 26파일, +2770/−408) + `f76f588ca` (origin/main 병합, DEBT#510→511 재번호)
- 근거 헌법: AGENTS.md §0.9b (Triple-Closure), §0.9 (극장 금지 — 발견은 등록하고 조용히 패치하지 않는다)

## 1. 목적

§0.9b Triple-Closure의 2단계(인간 감사) handoff. 이 변경집은 게이트 코드의 소비자(`src/cli/upstream_report_cli.nim` 등)를 수정하며, 게이트 스캐너 TCB 자체는 수정하지 않는다. 따라서 요청하는 인간 감사는 두 가지다:

1. **TCB 무오염 확인**: 이번 변경집이 `static_gate_scanner.nim`을 건드리지 않았다는 기계적 사실 확인 (아래 §2).
2. **TCB 자체 감사**: 115줄 스캐너가 여전히 극장 패턴을 탐지하는지 — 외부 뮤테이션 하니스(1단계)가 기계적으로 이를 입증했으므로(§3), 인간은 하니스의 변이체가 실제로 위협을 대표하는지 유효성을 판정한다.

## 2. TCB 무오염 입증 (기계적 사실)

- `985d1e302` 파일 목록(26파일)에 `src/gate/static_gate_scanner.nim` **부재** — `git show --stat 985d1e302`로 확인 가능.
- 병합 `f76f588ca`의 `src/gate/` 대비 변경: `src/gate/runners/debt_integrity_gate.nim` 3줄뿐 (`git diff 8dd517fbb...f76f588ca --name-only -- src/gate/`).
- 스캐너 파일은 115줄, 미변경.

## 3. 1단계 — 외부 뮤테이션 하니스 (PASS)

격리 worktree `/tmp/ax-mut-verify` @ `985d1e302`, 로그 보존: `/tmp/ax_mut_harness_preserved.log` (48행).

- 주입 변이체 3종: Trivial Stub (`return true`), Unmanifested Gate (manifest에 있으나 파일 부재), Lean Sorry Leak.
- `nim check bin/axiom.nim` → `src/gate/static_gate_scanner.nim(92,12) Error: Gate mutation-unmanifested-gate file not found` → **컴파일 실패 = 기대 충족** (스캐너가 극장을 탐지해 빌드를 차단).
- 결과: `✅ PASS: Scanner detected theater patterns`, elapsed 7s.
- 복원 확인: worktree `git status` 0건 후 worktree 제거 — 사용자 트리 무영향.

## 4. Purity clean-room 검증

- **1차 (exit 5)**: 오염 fail-closed. purity 실행 중 원본 트리에서 병렬로 merge를 수행해 dirty 상태가 변화 — 도구의 정상 동작(오염 → 실패 닫힘)이며 트리 자체는 무결. 오염 목록은 병합이 반입한 origin/main의 파일들이었다.
- **2차 (트리 무변경 재실행, 병합 HEAD `f76f588ca`)**: 로그 `/tmp/ax_purity2.log`.

| 항목 | 결과 |
|---|---|
| clean-room 진입 | slot `78440ec1…` |
| check-determinism (toolchain pin) | PASS (Nim 2.2.10 / Z3 4.13.3 / Lean 4.33.0) |
| Φ0 환경 변수·merkle 무결성 | PASS |
| debt 동기화 검증 | PASS — architecture_debt 507 / debt_registry 242 / debt_ledger 6 (schema·disjointness·live-file·cross-file 전부) |
| Φ2a Nim Theater Pattern Scan | 실행 (§3 하니스가 탐지 능력 입증) |
| A0′ proof-unit consistency | EXIT 0 — proof_unit_catalog sole authority |
| A3 projection invariant (static) | EXIT 0 — skip-자체 검증 PASS |
| epoch promotion transaction 4-way binding | EXIT 0 — fail-closed PASS |
| 원본 트리 오염 | **없음** — "worktree lifecycle closed: temp worktree removed, original tree unchanged" |
| check-arch (nimtry) | exit 1 — `FAIL: 39 new violations` = **main과 동일 수·동일 집합** (§5) |
| 최종 exit | 2 (= clean-room `local-verify-static-full`의 exit code, check-arch 실패 반영) |

exit 2는 purity 도구 자체의 실패가 아니라 clean-room 검증 대상 make의 결과 코드다. 오염 감시(1차에서 exit 5를 낸 경로)는 이번 실행에서 통과했다.

## 5. check-arch (nimtry) 선존재 RED 분류

- origin/main 클린 worktree: `FAIL: 39 new violations not in baseline` exit 1.
- 병합 `f76f588ca` 클린 worktree: 동일 39건, 동일 위반 목록 (우리 재작성이 구 코드 경고를 동등 형태로 치환 — 라인 시프트).
- 베이스라인(`data/nimtry_baseline.json`) 양측 동일·미변경.
- 판정: **main의 선존재 RED**. GitHub required 5 checks(admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice)에 check-arch는 포함되지 않으므로 PR-1 랜딩에 장애가 아니다. 수용 기준: "신규 위반 0 (main과 동일 실패집합)" — debt_integrity_gate exit 1(선존재 WARN 4건 + nimtry ERROR)과 동일하게 문서화된 수용 대상.

## 6. 인간 감사 요청 항목

1. **static_gate_scanner.nim (115줄) TCB 감사** — §0.9b의 "작고 순수한 TCB" 인간 검토. 특히 변이체 3종이 실제 위협 클래스를 대표하는지, `mutation-unmanifested-gate` 탐지 경로의 manifest↔파스템 일치 로직에 우회 가능성이 있는지.
2. **DEBT#511 remediation 검토** — 본 변경집이 `runUpstreamReport*`의 swallowed persist failure를 fail-closed로 폐쇄함. 폐쇄 조건(레지스트리 기재 "landed fix + passing tests")은 기계 검증으로 충족되어 PR-2에서 FIXED 전환되었고(§7), 인간은 그 코드와 테스트(4레인: display 46 / parser 9 / projection 18 / report 117 전부 PASS)를 검토한 결과를 §8에 기록한다.

## 7. DEBT#511 상태 규칙

등록 시점 규약: push-admissibility `check-repository-surface`가 `src/gate/**`를 FROZEN으로 분류해 `debt_integrity_gate.nim`의 enum 확장(3줄)을 거부함(SURFACE_FORBIDDEN) — 게이트를 origin/main 원본으로 원복하고 DEBT#511을 스키마 정규값 `open`으로 등록했다(동결 게이트 enum이 `in_progress`를 거부하므로 `open`이 준수 정규값).

폐쇄 조건은 레지스트리 기재 그대로 "landed fix + passing tests"다 — 랜딩(PR #1173, GitHub native MERGE `2e1083ed8`, required 5 checks green)과 canonical-main acceptance 재현(prove exit 1 + PROPOSITION_DISPROVED 13 records + BUG_SUSPECTED + #3364 DUPLICATE + receipt 불변, `docs/evidence/bytesview_canonical_main_acceptance_2026-11-02.md`)으로 기계 검증 완료 → PR-2에서 `status: closed, resolution: FIXED, lastVerifiedAt` 전환.

**§0.9b 인간 감사는 별도의 열린 의무로 유지된다**(§8 체크리스트) — 이는 본 부채의 생애주기와 독립적이며, 인간 감사자가 §2·§3·§6을 검토한 뒤 그 결과를 본 문서 §8에 기록하는 것으로 닫힌다.

## 8. 감사 결과 기록란 (인간 작성)

- [ ] TCB 무오염 확인 (§2)
- [ ] 하니스 변이체 유효성 판정 (§3)
- [ ] DEBT#511 remediation 승인 (§6.2)
- 감사자 / 일자 / 비고: ______________________
