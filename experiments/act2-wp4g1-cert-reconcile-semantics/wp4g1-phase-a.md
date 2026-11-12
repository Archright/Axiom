# WP4-g.1-A — 단일 기준 사례 고정 (Single Anchor)

> EXPERIMENT_ID=act2-wp4g1-cert-reconcile-semantics
> Phase A — 코드 수정 없음. 직접 측정으로 기준 사례(891b6dae)의 NC1/NC2/NC3 판정.
> 일자: 2026-08-29
> 계획: `plans/metamorpho-stature-atom.md` WP4-g.1-A

## 0. 대상

- Tracked reference cert (stale): `src/verification/certificates/f3d17f0e592...json`
  - sourceHash `e75e86d8a285a30e43e5dbcecb9c024c198540a93b2d648eaee3b9b642c90ef9`, kernel=true, status=certZ3Candidate
- Current evidence candidate: `build/certificates/891b6daee9f7...json`
  - sourceHash `825f7f161bed3ce...`, kernel=false, status=certZ3Candidate

## 1. NC1 — SourceIdentity (PASS)

`computeAxiomFingerprint`(= `computeStableSourceFingerprint`) 알고리즘
(`src/core/identity/axiom_identity.nim:23-50`, `src/core/proof/source_fingerprint.nim`):

```
normalizePayloadForFingerprint: 각 줄 strip; 빈 줄 제거; '#' 주석 줄 제거; 나머지 "줄+공백" join; 전체 strip
sourceHash = SHA256(normalizePayload(staged topology_dependency.nim))
```

직접 측정 (Python으로 동일 알고리즘 재현):

| 입력 | fingerprint |
|---|---|
| HEAD(committed) `topology_dependency.nim` | `e75e86d8...` |
| **STAGED** `topology_dependency.nim` (`git show :src/core/topology/...`) | `825f7f16...` |

- 891b6dae cert sourceHash `825f7f16...` == **STAGED** source fingerprint → **NC1 PASS**
  (current evidence는 현재 staged source에 대응하는 것.)
- f3d17f0e cert sourceHash `e75e86d8...` == **HEAD** source fingerprint → stale
  (tracked reference cert는 staged 이전 commit에 대응.)

`certSourceHashMatchesSource`(`certificate_verifier.nim:28-43`)는 working tree 파일을
읽어 비교 — `topology_dependency.nim`은 staged-only(working tree == staged)이므로
891b6dae는 소스-staleness 통과, f3d17f0e는 `dvcNotCurrent`(stale).

## 2. NC2 — Closure (FAIL)

`ax cert verify` 직접 실행 (`bin/ax`, 00:49 빌드):

| cert | 결과 | exit | code |
|---|---|---|---|
| 891b6dae (build, kernel=false) | `FAIL — deep verification failed: dvcPbtFailed` | 1 | ccsNotDeepVerified |
| f3d17f0e (tracked ref, kernel=true) | `NOT CURRENT — ... dvcNotCurrent` | 4 | ccsNotCurrent |

`isDeepVerified`(`certificate_verifier.nim:47-126`) 비-커널 분기(line 111-113):
```nim
else:
  let passed = cert.getOrDefault("passed").getBool(false)
  if not passed: return dvcPbtFailed
```
891b6dae는 `kernel=false` 이며 `passed` 필드가 **부재**(`getBool(false)`) → `dvcPbtFailed`.

### 핵심 발견
- 새 build cert 891b6dae는 **kernel=false**(empirical 경로)인데 `passed:true`가 없다.
- 반면 기존 tracked reference cert f3d17f0e는 **kernel=true**(formal 경로).
- 즉 새 후보는 sourceHash는 staged 소스와 일치하지만, 현재 deep-verify 계약 하에서
  **"현재 증명 진리(current proof truth)"로 인정되지 않는다**.
- `passed` 필드는 엔진 평가 경로 `src/cli/axiom_engine.nim:544` (`"passed": ev.passed`)가
  작성 — 891b6dae cert에는 `passed` 부재 → 엔진 평가 경로가 아닌 build/승격 artifact로 추정.
- **NC2 FAIL → rpoResolved(NC1∧NC2∧NC3) 불성립 → Case A 아님.**

## 3. NC3 — Binding Chain (PASS)

직접 측정: journal commit `data/trusted/journal/4b0301c1...json` 존재, claim과 cert 결합 필드 일치:

| 필드 | journal claim | 891b6dae cert |
|---|---|---|
| irHash | 891b6dae... | 891b6dae... (일치) |
| sourceHash | 825f7f16... | 825f7f16... (일치) |
| modulePath | src/core/topology/topology_dependency.nim | 동일 |
| functionName | proximityScore | 동일 |
| solverStatus | unsat | unsat |
| provenance.certificateDigest | — | 975693c4... |
| identityDigest | — | 975693c4... |

- RecordLocator: cert trustCommitId / provenance.journalCommitId = `4b0301c1` == 실제 journal 파일 → 존재.
- EvidenceDigest: certificateDigest == identityDigest = `975693c4`.
- ClaimIdentity: modulePath::functionName + irHash 동일 namespace로 일치.

**NC3 PASS.**

## 4. 종합 판정

| 필요조건 | 결과 |
|---|---|
| NC1 SourceIdentity | **PASS** |
| NC2 Closure | **FAIL** (dvcPbtFailed, 비-커널 cert에 passed 부재) |
| NC3 Binding Chain | **PASS** |

**rpoResolved = NC1 ∧ NC2 ∧ NC3 = FALSE → Case A 아님.**

## 5. 교훈 (재현성/정직성)

1. WP4-g.1 계획 §0.5의 NC2 정의("verifyCertificateClosure == ccsPass")는 유효하지만,
   `verifyCertificateClosure`가 실제로는 `isDeepVerified`를 포함하며 그 정치한 정의는
   "**solver=0**"이 아니라 "**현재 deep-verify 계약(비-커널은 passed:true 요구)**"를
   포함한다. NC2는 단순 구조/서명/바인딩 검증이 아니라 **현재 증명 진리 적합성** 판정이다.
2. 891b6dae는 sourceHash가 staged 소스와 정확히 일치함에도 deep-verify를 통과하지 못한다.
   sourceHash 일치(NC1)만으로 "current evidence"를 선언하면 안 된다는 계획 원칙이
   정확히 이 사례로 검증된다.
3. 현재 어느 cert도 staged 소스에 대한 유효한 deep-verified "current truth"가 아니다:
   - f3d17f0e: stale (sourceHash=HEAD).
   - 891b6dae: sourceHash=staged 이나 passed 부재 → dvcPbtFailed.
4. 이 상태에서 reconcile --apply로 reference vault를 재물질화하려 해도, 실제 authoritative
   evidence(cert)가 deep-verify를 통과하지 못하므로 **근본 재검증 없이는 정당화 불가**.
   계획 §WP4-g.1-A A3 Case B 경로(별도 `ax prove --target proximityScore`)가 정답 방향.

## 6. 다음 단계 (Case B 방향)

- WP4-g.1-A는 **Case B**로 판정.
- 다음은 reconcile/계약 개정 이전에, 현재 staged 소스에 대한 **deep-verify를 통과하는
  authoritative current evidence**를 별도 명령(`ax prove --target`)으로 재생성하는 것.
- 그 evidence가 ccsPass를 통과하면 그때 NC2가 성립하고 기준 사례가 RESOLVED가 된다.
- 그 전까지 커밋은 blocked 유지(정직 종료 원칙).
