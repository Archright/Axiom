# WP4-g.1-D — Reference Cert Reconciliation 기준 사례 실측 (Baseline Result)

> EXPERIMENT_ID=act2-wp4g1-cert-reconcile-semantics
> Phase D — artifact-local `projectReferenceCertificate` 기준 사례(proximityScore)의
> rpoResolved 실측 확정. 코드 수정 없이 probe로 직접 호출.
> 일자: 2026-08-29
> 계획: `plans/metamorpho-stature-atom.md` WP4-g.1-D

## 0. 목표

f3d17f0e(tracked reference cert, stale)를 **현재 staged source**에 대해 결정론적으로
재물질화할 수 있는가를 probe로 직접 실측한다. CLI의 journal-wide `--check`(module마다
`git show` subprocess 수천 개 spawn = 병목)를 피하고, 대상 1개 module만 snapshot으로
넣어 `projectReferenceCertificate`를 직접 호출한다.

## 1. 입력 고정 (Identity Set)

| identity | 값 |
|---|---|
| tracked cert path | `src/verification/certificates/f3d17f0e592362e8183b876069904f5f504bd09c2530d21b9c878e31f854e6ac.json` |
| tracked claim identity | `src/core/topology/topology_dependency.nim::proximityScore` |
| tracked `irHash` (old) | `f3d17f0e...` (cert 파일명과 동일 namespace) |
| tracked `sourceHash` (stale) | `e75e86d8...` (= HEAD 이전 commit) |
| current staged source | `git show :src/core/topology/topology_dependency.nim` |
| current stagedHash | `825f7f161bed3ce6802ce50bfc48a8062ea7bb2b0ad7df648eb89a86344c7c6d` |

## 2. probe 구성 (wp4g1_baseline_probe.nim)

- `findRepoRoot` → `axiom.toml` 발견 시 repo root 설정·`setCurrentDir` (CWD 독립).
- staged source 1개만 `sourceSnapshot[modulePath]`에 주입.
- `projectReferenceCertificate(trackedPath, repoRoot, sourceSnapshot, repoRoot)` 호출.
  - **주의**: 두 번째 인자(`journalBaseDir`)는 **trust root(= repoRoot)** 를 넘긴다.
    `listCommitIds`/`readCommit`은 내부에서 `data/trusted/journal`을 다시 append한다.
    `repoRoot/data/trusted/journal`을 넘기면 이중 append로 commit을 찾지 못해
    `rpoNoCurrentEvidence`로 잘못 판정된다 (아래 §5의 측정 실수 — 기록).

## 3. 실측 결과 (probe stdout)

```
outcome:       rpoResolved
claimIdentity: src/core/topology/topology_dependency.nim::proximityScore
trackedCertId: f3d17f0e592362e8183b876069904f5f504bd09c2530d21b9c878e31f854e6ac
stagedHash:    825f7f16...
journalCommit: 4b0301c13a35517c5fb95a069c1040e458a4856159129687b609b521b86fddab
certDigest:    975693c4f218e13b4c60eb1106092ca1075845b07758ee31f991e3b144e1b667
bytesLen:      4754
```

- **outcome = rpoResolved** (NC1 ∧ NC2 ∧ NC3 통과).
- 기준 사례의 canonical replacement는 journal commit `4b0301c1...`, identityDigest
  `975693c4...`, canonical bytes 4754 byte로 결정된다.

## 4. 매칭 경로 (claim identity, irHash 아님)

- tracked cert의 `irHash=f3d17f0e...`와 journal record의 `irHash=891b6dae...`는 **다르다**.
  이는 정상이다: staged source가 진짜로 바뀌었기 때문에 함수 IR digest가 새 source에 대해
  달라진 것이다.
- `projectReferenceCertificate`는 **old irHash로 매칭하지 않고** claim identity
  (`modulePath::functionName`) + current staged source binding(`candidate.sourceHash ==
  fingerprint(current source)`)으로 매칭한다. 이 4-way identity 분리(WP4-d) 덕분에
  genuine drift 케이스에서도 current evidence를 찾을 수 있다.
- journal `4b0301c1`은 v1 flat claim shape이며 `modulePath`/`functionName`이 tracked
  claim identity와 일치하고 `sourceHash=825f7f16` == stagedHash → `boundCommits.len==1`.

## 5. 측정 실수 기록 (rpoNoCurrentEvidence 오판 원인)

초기 probe가 `journalBaseDir = repoRoot / "data/trusted/journal"`을 넘겨
`rpoNoCurrentEvidence`로 나왔다. 원인은 **probe 설정 오류**였고 implementation defect가
아니다.

- `readCommit(baseDir, id)`는 `commitPath = baseDir / "data"/"trusted"/"journal"`을 사용.
- `journalBaseDir` 인자명에도 불구하고 전달값은 **trust root**여야 한다 (cert_cli.nim이
  `baseDir = repoRoot`를 넘겨 호출 — `src/cli/cert_cli.nim:147`, `:90`).
- 위 실수가 없다면 v1 flat claim이 올바르게 매칭됨 — debug probe(`wp4g1_debug_probe.nim`)로
  `readCommit ok: true` 및 claim field 정상 확인.

결론: **현재 `projectReferenceCertificate` 구현은 검증된 상태로 정확하고,**
probe의 교훈은 "journalBaseDir 인자 = trust root"라는 계약 재확인이다.

## 6. WP4-g.1-C defect-fix 완료 여부 (이 문서 종속)

- C-phase에서 irHash 매칭 → claim identity + currentSource binding으로 재작성 완료.
- 단위테스트 `tests/unit/cert_reconcile_test.nim` 16/16 PASS (검증됨).
- 본 probe도 같은 구현으로 rpoResolved를 실측 — implementation correctness 재확인.

## 7. 다음 단계

1. `--check --staged` (full) 실행 — journal-wide `git show` 수천 spawn 병목으로 느림,
   background 비동기 실행.
2. `--apply` (P1-P4 all-or-nothing): 모든 tracked cert가 rpoResolved여야만 교체.
   만약 reference vault의 다른 cert(f3d17f0e 외 5개)가 rpoNoCurrentEvidence면
   `--apply`는 REFUSED(exit 2) — honest fail-closed 유지.
3. 교체 후 `stale_cert_gate`가 current stagedHash에 대해 PASS(exit 0)되는지 확인.
4. 커밋 2건 분할 + PR.

## 8. 교훈 (재현성/정직성)

- "rpoNoCurrentEvidence"가 나왔다고 바로 implementation defect로 단정하지 말 것.
  입력 파라미터 계약(journalBaseDir = trust root, snapshot 구성)을 먼저 검증해야 한다.
- 실제 authoritative replacement(4754 byte, 4b0301c1)는 한 곳(projectReferenceCertificate)
  에서만 결정된다. CLI `--apply`는 이 bytes를 정확히 materialize한다.
- `--check`의 exit semantics: hasDrift → 1, else 0. `--apply`는 P1 실패 시 2.
