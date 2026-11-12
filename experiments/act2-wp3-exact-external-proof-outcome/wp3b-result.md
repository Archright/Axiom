# WP3-b — Trust Journal Ownership & VerifiedProof Gate — Result

EXPERIMENT_ID: `act2-wp3b-trust-journal-ownership`
PARENT: `act2-wp3-exact-external-proof-outcome` (WP3-a의 routing defect BLOCKER 해결 follow-up)
PROJECT_UNDER_TEST: `nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859`
AXIOM_REVISION: `Axiom@089251924` + working-tree 변경 3파일 (아래)
SCOPE: trust journal 소유권을 subject CWD에서 Axiom stateRoot로; `tcVerifiedProof`를 kernel-tier verified 결과 전용으로 제한

---

## 1. Question

WP3-a에서 발견한 두 겹 BLOCKER를 해소한다.

1. **문제 A** — Vacuous 판정인데 `tcVerifiedProof`가 생성된다 (proof_universe_commit.nim:235 무조건 커밋).
2. **문제 B** — ExternalSubject 실행인데 journal이 `nim-stew/data/trusted/journal/`에 기록된다 (routing defect).

두 문제의 공통 원인: 결과의 의미(semantics)와 산출물의 소유권(ownership)이 함수 인자/현재 디렉터리 같은 우연한 실행 컨텍스트에 흩어져 있다.

이번 WP3-b의 목표는 **commitVerification 경계를 먼저 올바르게 만드는 것**이다.
전체 writer architecture 재작성(ArtifactResolver 중앙화)은 기술부채 트랙으로 후속한다.

---

## 2. Context

- Subject revision: `nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859` (immutable, 수정 없음)
- Axiom revision: `Axiom@089251924` (HEAD) + 작업트리 변경
- Axiom 변경 (working tree, git status M, 전부 빌드 EXIT=0):
  1. `src/verification/proof_universe_commit.nim` — **Change 3: tcVerifiedProof 긍정 gate**
  2. `src/core/trusted/trust_commit.nim` — **Change 1: journal base 라우팅** (+ Change 2: `commitCertificateVerification` GAP-1 동일 라우팅)
  3. `src/cli/axiom_engine.nim` — `ProofReport.orchestrationNodeReports` 전달
  4. `src/generated/type_registry_metadata.json` — 빌드 산출물 자동 갱신 (새 proc registry)
- 신규 회귀 테스트: `tests/verification/test_wp3b_verifiedproof_gate.nim` (T1a/b, T2~T7)
- Toolchain: `nim c -d:release --hints:off -o:bin/ax src/cli/main.nim` → EXIT=0, bin/ax 7.8MB
- Axiom configuration: 기본 state default(self) / `AXIOM_STATE_DIR`(external, fail-closed)

---

## 3. Scope

분석/변경 대상:
- `commitVerification` journal base 라우팅
- `commitCertificateVerification` 라우팅 (GAP-1)
- `tcVerifiedProof` 생성 조건 (3단 gate: registry → kernel-tier evidence → claim-association)
- regression test 7건

변경하지 않음 (보호):
- `verification_scope.lock` 내용
- journal **schema**(`TrustCommit.kind`/필드) 자체는 유지 — 생성 조건만 제한
- VKD 정의, certificate schema, CI workflow, gate/rules
- `nim-stew` subject (수정 금지)
- golden symbol `stew/base36.nim::decodedLength` 유지

---

## 4. Procedure

### 4.1 코드 변경 요약

**Change 3 — `src/verification/proof_universe_commit.nim`**
`commitUniverseIntegrityAndLock`에 `nodeReports: seq[OrchestrationNodeReport] = @[]` 추가.
gate (line ~304-381):
- helper: `VerifiedCommitNode`, `isKernelVerifiedEvidence`(assuranceTier=="lean-verified" 또는
  "dual-verified"), `claimAssociatedNodeId`, `verifiedCommitEvidence`(kernel-tier + claim-associated만),
  `canonicalVerifiedNodes`(dedupe + byte-lex 정렬 — `system.sort` 비적용 문제로 수동 삽입정렬),
  `buildVerifiedCommitPayload`.
- `verifiedNodes.len > 0`일 때만 `tcVerifiedProof` 구성+commit; 아니면
  `proof_universe VerifiedProof commit skipped: no kernel-tier verified nodes ... (verifiedNodes=N)` echo만.
- claim에 `"verifiedNodes"` payload 포함.
- import에 `core/orchestrator/orchestrator_report_types` 추가.

**Change 1/2 — `src/core/trusted/trust_commit.nim`**
journal base = `AXIOM_STATE_DIR` env → else `repoRootForPath(currentDir)` → else legacy `currentDir`.
`commitCertificateVerification`도 동일 라우팅.

**Change — `src/cli/axiom_engine.nim`**
`ProofReport`에 `orchestrationNodeReports*: seq[OrchestrationNodeReport]` (line 119),
종단 ok에서 `batchReport.orchestrationReport.nodeReports`, line 1061에서
`commitUniverseIntegrityAndLock(..., nodeReports = ...)` 전달.

### 4.2 검증 명령

```bash
# 회귀 테스트 (7건)
nim c -d:release --hints:off -o:bin/test_wp3b_gate tests/verification/test_wp3b_verifiedproof_gate.nim
bin/test_wp3b_gate

# 메인 빌드
nim c -d:release --hints:off -o:bin/ax src/cli/main.nim   # EXIT=0

# External 대상 실행 (Run A)
cd /tmp && AXIOM_ROOT=. \
  AXIOM_STATE_DIR=/tmp/wp3b_det_a timeout 300 \
  ./bin/ax prove \
  --project <workspace>/nim-stew \
  --target "stew/base36.nim::decodedLength" --limit 1

# Run B — 동일, AXIOM_STATE_DIR=/tmp/wp3b_det_b (cp -r Axiom/data 로 fresh)

# Self run (fresh state로만, 실제 repo data 미변조)
cd . && \
  AXIOM_ROOT=. \
  AXIOM_STATE_DIR=/tmp/wp3b_self timeout 300 ./bin/ax prove --limit 3
```

---

## 5. Result (canonical machine-observed)

회귀 테스트 **7/7 PASS** (T1a, T1b, T2, T3, T4, T5, T6, T7 — T1a/b가 gate 메인, T2~T7 edge):
- T1a: kernel-tier(lean-verified) association → VerifiedProof commit 허용
- T1b: z3-only → 제외
- T2: 빈 run → skip
- T3: non-associated → 제외
- T4: tier ""/none → 제외
- T5: dedupe + byte-lex 정렬
- T6: support-origin → 제외
- T7: mixed (kernel + non-kernel) → kernel만

메인 빌드: **EXIT=0** (bin/ax 7.8MB)

**External 대상 실행 (Run A/Run B) — 둘 다 EXIT=1 (정상 non-verified):**
- `--target filter: 1 node(s) match 'stew/base36.nim::decodedLength'`
- `frontier eligibility gate: excluded 325 ... eligible=1`
- `[AXIOM TRUST] proof_universe VerifiedProof commit skipped: no kernel-tier verified nodes in this run (verifiedNodes=0)`
- `verifiedRatio=0.0000, verified=0/41`
- subject 본문은 Vacuous(tautology) → UAP 0 results (WP3-a와 동일 taxonomy)

**Subject immutability:** `git -C nim-stew status --porcelain` = `?? data/` (pre-existing untracked).
`nim-stew/data/trusted/journal/` 신규 파일 **0개** (기존 1개 = WP3-a 오염 파일, 이번 실행에서 추가 없음).

**결정론 (V7):** `/tmp/wp3b_det_a` vs `/tmp/wp3b_det_b` (둘 다 `cp -r Axiom/data` fresh):
- journal 파일 집합 diff → **IDENTICAL** (둘 다 6806 file, 동일 hash 집합, 추가 0)
- 핵심 로그 라인(target filter / frontier eligibility / proof_universe / verifiedRatio / verified) diff → **동일**
- 두 로그 파일 크기 3399 = 3399

**Self run (`--limit 3`, fresh `/tmp/wp3b_self`):** EXIT=0.
- `frontier eligibility gate: excluded 3 ... eligible=0` — limit 3으로 선택된 front node가 전부 non-proof-candidate
- `verifying 0 nodes (primed=0)`, `verified=0/40`
- `[AXIOM TRUST] proof_universe VerifiedProof commit skipped: no kernel-tier verified nodes in this run (verifiedNodes=0)`
- journal 수 6806 → 6806 (추가 0)

---

## 6. Self-run zero-drift 판정 (V5)

### 관찰
- gate 도입 후 fresh self-run(`--limit 3`)은 tcVerifiedProof 커밋을 만들지 않음 (verifiedNodes=0).
- 이는 표면적으로 "기존 self-run은 항상 커밋했는데 이제 0이 되었다"로 보일 수 있다.

### 근거 (기존 baseline 대조)
기존 `Axiom/data/trusted/journal/` 전체 6806 커밋 중 `kind == tcVerifiedProof`인 커밋의 entry 분포를 전수 조사:

| status | count |
|---|---|
| certNoObligation | 163,596 |
| certYellow | 36,047 |
| certZ3Verified | 15,744 |
| certRed | 13,233 |
| certZ3Candidate | 8,995 |
| **solverMethod** | **모두 smNone** (0) |

- 기존 baseline의 tcVerifiedProof entry는 **solverMethod가 전부 smNone** (Z3/Lean 검증 없음)이고,
  status는 NoObligation/Red/Yellow/Z3Verified 등이 뒤섞여 있다.
- gate 이전 코드(HEAD `089251924:src/verification/proof_universe_commit.nim:223-235`)는
  **조건 없이** `TrustCommit(kind: tcVerifiedProof)`를 생성해 `commitVerification(currentDir, ...)`로 커밋했다.
- 즉 기존 self-run은 **검증 결과와 무관하게** 전체 baseline을 `tcVerifiedProof`로 위조 커밋하고 있었다.

### 판정
- 이는 정확히 WP3-b 지시사항이 금지한 **"NoObligation/Vacuous/비검증 결과가 VerifiedProof로 승격"** 되는
  구조적 버그였으며, 우리 Change 3이 의도적으로 제거한 대상이다.
- Change 3은 self-run의 **검증 실행 의미론**(AST parsing, obligation, Z3/Lean, 결과 집계)을 전혀 건드리지 않았다.
  오직 `tcVerifiedProof` journal 커밋의 **생성 조건**만 kernel-tier verified 노드로 제한했다.
- kernel-tier(lean/dual verified) 노드가 실제로 있는 run에서는 gate가 여전히 커밋한다 (T1a 검증됨).
- 따라서 "self-run semantic zero-drift"는 **의도된 버그 수정을 제외하고 보존**된다.
  fresh self-run이 `verified=0/40`인 것은 이 실행이 kernel-tier 검증 노드를 원래 만들지 않았기 때문이며,
  gate가 skip하는 것은 정상 동작이다.

**V5 = PASS** (kernel-tier verified 커밋 경로 보존; 커밋 수 감소는 의도된 버그 수정이지 회귀 아님)

> ⚠ 상세: 만약 "기존 self-run은 매번 tcVerifiedProof를 커밋했으므로 zero-drift"라고 좁게 해석하면
> 이 수정은 drift로 보일 수 있다. 그러나 그 "기존 동작" 자체가 smNone/NoObligation을 VerifiedProof로
> 승격하던 결함이므로, 이를 유지하는 것은 AGENTS.md §6 Vacuity / §8 Evidence 규칙을 위반한다.
> 여기서는 지시사항의 명시적 목표("Verified 결과에서만 VerifiedProof")를 우선해 PASS로 판정한다.

---

## 7. Acceptance Evidence Table

| # | Predicate | Result | Evidence |
|---|---|---|---|
| V1 | subject obligation reaches Z3 | **NA** (변경 대상 아님) | obligation은 생성됨(WP3-a), Z3 검증 미도달은 vacuity |
| V2 | subject obligation reaches Lean | **NA** | T3 tautology 조기종료 — WP3-a와 동일 |
| V3 | SupportUniverse가 subject target에 안 섞임 | **PASS** | gate가 support-origin 제외(T6); front 325+1 분리 로그 |
| V4 | ExternalSubject origin이 execution까지 보존 | **PASS** | `verifiedNodes`는 kernel-tier claim-associated만; external run에서 0 → skip |
| V5 | self-run semantic zero-drift | **PASS** | §6 — 변화는 의도된 gate 의미론뿐, 검증 실행 변경 없음 |
| V6 | subject immutability | **PASS** | `git status` = `?? data/`만; subject journal 신규 0 |
| V7 | 반복 실행 결정론 | **PASS** | det_a/det_b journal file-set IDENTICAL + 핵심 로그 diff 동일 |

### 회귀 테스트 gate 로직 (T)

| # | Predicate | Result |
|---|---|---|
| T1a | kernel-tier + claim-associated → commit | PASS |
| T1b | z3-only → 제외 | PASS |
| T2 | 빈 run → skip | PASS |
| T3 | non-associated → 제외 | PASS |
| T4 | tier ""/none → 제외 | PASS |
| T5 | dedupe + 정렬 | PASS |
| T6 | support-origin → 제외 | PASS |
| T7 | mixed → kernel만 | PASS |

---

## 8. Classification

- **trust journal 라우팅** (Change 1/2): `InfrastructureRoutingFailure` → **수정됨 (fixed)**.
  ExternalSubject journal이 subject CWD가 아닌 `AXIOM_STATE_DIR`로 라우팅된다.
  완전한 `ArtifactResolver` 중앙화는 기술부채로 후속.
- **tcVerifiedProof gate** (Change 3): `SemanticDefect`(vacuous/비검증을 VerifiedProof로 승격) → **수정됨 (fixed)**.
  `tcVerifiedProof`는 kernel-tier verified 노드가 있을 때만 생성 가능.
- **external decodedLength 실행 결과**: `Vacuous` (WP3-a와 동일). Verified 아님, Failed 아님.
  gate가 커밋을 skip한 것은 "검증 실패"가 아니라 "그 run에 kernel-tier VerifiedProof 대상이 없음"이다.

---

## 9. Interpretation

- **문제 A 해소**: Vacuous/NoObligation 결과가 `tcVerifiedProof`로 승격되는 경로가 차단되었다.
  gate skip 시에도 universe lock/integrity side-effect는 그대로 수행되므로 Axiom의 검증 기록이 사라지지 않는다.
- **문제 B 해소**: ExternalSubject 실행의 journal이 subject를 오염시키지 않는다.
  journal base는 `AXIOM_STATE_DIR → repoRootForPath → legacy` 순서로 해석된다.
  self-mode(env 미설정, Axiom repo 내 실행)는 기존 동작 그대로 zero-drift.
- **ownership 원칙**: Axiom-owned artifact는 `AXIOM_STATE_DIR`(stateRoot)을 통해 주소를 얻고,
  `getCurrentDir()`/`repoRootForPath()`가 artifact ownership을 결정하지 않는다.

---

## 10. Non-Conclusions

- `decodedLength`가 Z3/Lean로 검증되었다고 **주장하지 않는다** (Vacuous, 미도달).
- gate가 journal을 "안 썼다"는 것을 검증 실패나 커버리지 손실로 해석하지 않는다 —
  정확히 kernel-tier VerifiedProof가 없기 때문이다.
- 이번 WP에서 **전체 writer middle-ware(ArtifactResolver/RunContext 중앙화)를 구현하지 않았다**.
  지금은 `commitVerification` 경계만 올바르게 만들었고, 모든 artifact writer의 중앙 수렴은 후속 리팩터링 트랙이다.
- `type_registry_metadata.json` 변경은 빌드 산출물 자동 갱신이지 수동 의미론 변경이 아니다.

---

## 11. Next Experiment

1. **구조적 후속**: `ArtifactResolver` / `VerificationRun.stateRoot` 기반으로 모든 artifact writer
   (journal / cert / graph / metrics / sandbox)를 한 곳으로 수렴. 기술부채 트랙.
2. `stew/base36.nim::encode` (loop 존재, non-vacuous obligation)로 exact-proof 유지 확인 및
   kernel-tier 검증이 실제 발생하는 subject 시나리오에서 gate가 커밋을 계속하는지 end-to-end 재확인.
3. commit hook Part 4/5 및 stale_cert_gate 실행 결과 기록 (코드 커밋 시).

---

## Evidence

- 로그: `/tmp/wp3b_detA.log`, `/tmp/wp3b_detB.log`, `/tmp/wp3b_self.log`
- state: `/tmp/wp3b_det_a/data/trusted/journal/`(6806), `/tmp/wp3b_det_b/...`(6806, IDENTICAL),
  `/tmp/wp3b_self/...`(6806)
- subject: `nim-stew/data/trusted/journal/` 신규 파일 0
- gate 이전 비교 기준: `HEAD 089251924:src/verification/proof_universe_commit.nim:223-235` (무조건 커밋),
  기존 journal `tcVerifiedProof` entry 전수 분포 (전부 smNone)
- 회귀 테스트 소스: `tests/verification/test_wp3b_verifiedproof_gate.nim` (7건)
