# WP3-a — Exact External Proof Outcome — Result

EXPERIMENT_ID: `act2-wp3-exact-external-proof-outcome`
PROJECT_UNDER_TEST: `nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859`
AXIOM_REVISION: fresh `bin/ax` (working tree build)
SCOPE: `stew/base36.nim::decodedLength` exact external proof outcome

---

## 실행 명령

```bash
cd <workspace>/nim-stew && \
  AXIOM_STATE_DIR=/tmp/wp3a_state \
  timeout 300 ./bin/ax \
    prove --project . --target "stew/base36.nim::decodedLength" --limit 1
```

- 로그: `/tmp/wp3a_run.log`
- **exit status = 2** (실패/미결론 종료; 자동 승격된 certificate 없음)

---

## Canonical machine-observed result

| 항목 | 값 |
|---|---|
| selected node identity | `stew/base36.nim::decodedLength` (1 match) |
| origin | external subject (`soExternalSubject`, registry-level) |
| obligation id | IR digest `262bb5be2e3a8143ba757714332be09cb71df6ad575fe94a65dedb1216f3d94c` (CAS key) |
| obligation proposition | 유일 자동 파생 obligation = `277 != 0` (div-by-zero guard, 공리적) |
| SMT-LIB digest | 발행되지 않음 (`solverMethod=smNone`) |
| Z3 invocation count | verification용 0회; tautology probe 1회 (500ms limit) |
| Z3 result | UNSAT (tautology probe) — 그러나 검증 SMT 미발행 |
| timeout 여부 | 아니오 (probe는 제한 내 완료) |
| exit status | 2 |

---

## Escape / stage result (경로별)

| 단계 | 결과 |
|---|---|
| topology analysis | PASS — 86 files, 931 candidates |
| `--target` filter | PASS — exactly 1 node match |
| frontier eligibility | PASS — eligible=1 (325 non-proof-candidate excluded) |
| IR extraction | PASS — `vtSmtNative` 분류, obligation 생성 |
| T3 tautology gate | **REJECT** — `[tautology] decodedLength: invariant is tautological` |
| KAA / Lean | **미도달** (T3 조기 종료) |
| UAP gate | `Verification-Gate: UAP produced 0 results (requests=1)` |
| persist | `PERSIST FAIL: 1 promotable certificate(s) failed canonical promotion` |
| proof_universe commit | subject CWD에 `tcVerifiedProof` journal 기록 (BLOCKER) |

---

## E1..E9 Acceptance Evidence Table

| # | Predicate | Result | Evidence | Note |
|---|---|---|---|---|
| E1 | exact target = 1 | **PASS** | log L4: `--target filter: 1 node(s) match 'stew/base36.nim::decodedLength'` | exact-qualified identity 작동 |
| E2 | external origin preserved | **UNVERIFIED** | origin은 registry-level `soExternalSubject`(axiom_engine.nim:996) 기록 | report/nodeReports에 origin key가 실제 남는지 미확인 (고지) |
| E3 | obligation exists | **PASS** | consider classify `vtSmtNative`; 유일 div guard 생성됨 | obligation은 생성됨 |
| E4 | Z3 outcome exactly classified | **PASS (Vacuous)** | `solverMethod=smNone`, T3 reject, `request=1 → 0 results` | Z3 verification 미도달 → Vacuous |
| E5 | UNSAT → Lean/KAA reached | **NA** | Z3 검증 미도달 → Lean/KAA 미진입 | 해당 없음 |
| E6 | no false Verified | **PASS (결과값)** | `verified=0/41` (자체는 정직) | ⚠ 별개 BLOCKER: subject에 `tcVerifiedProof` 기록 (아래) |
| E7 | subject immutable | **FAIL** | `nim-stew/data/trusted/journal/3ab50cc.*.json` 생성 (untracked) | 원인: proof_universe_commit.nim:235 routing defect |
| E8 | self-run zero-drift | **NOT MEASURED** | self-run 미실행 | 후속 측정 필요 |
| E9 | repeat deterministic | **NOT MEASURED** | RunA/RunB 미재실행 | 후속 측정 필요 |

---

## 신규 BLOCKER — trust journal routing defect

- **위치**: `src/verification/proof_universe_commit.nim:235`
  `let commitRes = commitVerification(currentDir, tc)` — subject CWD를 baseDir로 사용.
- **경로**: `trust_commit.nim:332-349` → `journalDir(baseDir) = baseDir/data/trusted/journal/`.
- **영향**:
  1. subject immutability(§2) 위반 — `nim-stew/data/trusted/journal/*.json` 생성.
  2. evidence integrity(§8) 위반 — vacuous 결과인데 `kind=tcVerifiedProof` claim 기록.
- **대조**: `commitCertificateVerification`(`trust_commit.nim:226`)은 `repoRootForPath(baseDir)`로
  AXIOM_STATE_DIR을 향하지만, `commitVerification`은 routing하지 않음.
- **분류**: InfrastructureRoutingFailure. 이번 WP3-a에서는 코드 수정 없이 분석만 기록.

---

## Classification

**주 결과 taxonomy: `Vacuous`**

- `NoObligation`과 구분한다: obligation은 생성됐다 (`generatedObligationCount>0`,
  `vsInconclusive` + `rkNoProperty`). "non-trivial property가 없다"는 뜻이므로 AGENTS.md §6
  Vacuity Rules에 따라 vacuity에 해당.
- Z3/Lean proof outcome은 **존재하지 않는다** (T3 gate에서 정당하게 조기 종료됨).
- 이를 "실패"로 과장하거나 "Verified"로 승격하지 않는다.

---

## Interpretation

- external symbol (decodedLength)은 **verification universe에 올바르게 admission**되었다:
  exact `--target` 1 match, frontier eligible, obligation 생성.
- 그러나 golden symbol 자체의 본문이 상수-divisor 공리적 표현이라, 유일 auto-derived obligation이
  tautology로 판정되었다. 이것은 Axiom의 정당한 vacuity 분류이며, "external ingress가 실패한 것"도,
  "Axiom이 약해진 것"도 아니다.
- 별개로, 실행 부산물로 **subject가 trust journal로 오염**되었다 — 이는 WP3-a 측정 자체가
  routing defect에 노출된 것이며 별도 BLOCKER로 다뤄야 한다.

---

## Non-Conclusions

- Z3/Lean로 decodedLength가 검증되었다고 **주장하지 않는다** (미도달).
- decodedLength가 "실패했다"고 단언하지 않는다 (vacuous — 실패가 아님).
- `verified=0/41`을 external ingress의 실패 지표로 읽지 않는다.
- E2/E8/E9는 아직 측정되지 않았다 — 이 보고서의 결론은 E1/E3/E4/E6/E7 evidence에 기반한다.
- self-run zero-drift(E8)와 determinism(E9)은 이번 WP3-a에서 확인하지 않았으므로 open으로 남긴다.

---

## Next Experiment

1. **BLOCKER 해결 후** — proof_universe_commit routing을 AXIOM_STATE_DIR 기반으로 수정하는
   별도 work-package (단, 이번 WP3-a에서는 수정하지 않음).
2. `stew/base36.nim::encode` (loop 존재, non-vacuous obligation 가능)로 exact-proof-outcome 재측정.
3. self-run zero-drift 및 RunA/RunB determinism 측정.
