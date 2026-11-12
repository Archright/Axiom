# Certificate / Asset Lifecycle Contracts — 공통 Invariant

> **SSOT 문서** — 이 문서는 Canonical State / Verification State / Transient Artifact /
> Audit Metadata / Promotion 의 권한 경계를 고정한다. 이 문서의 계약을 위반하는 변경은
> architecture principle breach로 간주된다. (AGENTS.md §0 원칙과 동일 등급)

## 배경

목표는 개별 DEBT를 임시로 닫는 것이 아니라, 각 상태 도메인의 **의미와 권한을 분리**하여
결정론성(determinism)과 soundness를 **구조적으로** 보장하는 것이다.

핵심 원칙: *"결정론적이어야 하는 것은 Canonical Semantic State이고, 불변이어야 하는 것은
Verification Evidence이며, Proof Result는 Bounded/Unbounded를 구조적으로 구분해야 하고,
Audit 시간 정보는 별도의 lifecycle을 가져야 하며, 각 domain의 canonical mutation은
독립된 Promotion Boundary를 통해서만 허용한다."*

## 0. 공통 Invariant (6개)

| # | Invariant | 정의 |
|---|-----------|------|
| 1 | **Canonical semantic state** | Git-tracked SSOT. 결정론적. 임의 generator가 직접 수정하지 않음. 명시적 promotion만 mutation authority. |
| 2 | **Transient artifact** | build-local evidence/cache. canonical SSOT가 아님. 필요 시 GC 대상. stale gate 대상 여부는 lifecycle 계약으로 별도 결정. |
| 3 | **Verification state** | `Proven(Unbounded)` / `BoundedEvidence(depth=K)` / `Refuted` / `Inconclusive`를 구분. **bounded ≠ unbounded.** |
| 4 | **Audit/provenance** | timestamp, commit hash 등 허용. semantic state와 분리. 결정론성 비교에서는 **semantic state만** 비교. |
| 5 | **Promotion** | `generate → validate → inspect → authorize → atomic promote`. canonical write authority를 하나로 제한. |
| 6 | **Verification = Verdict × Scope × Provenance** | 3축 직교. K(depth)는 evidence metadata(Provenance)이며 Scope에 중첩하지 않음. |

## 1. Verification 이중축 모델

```
                  Verification
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
       Verdict       Scope      Provenance
          │            │            │
       Proved      Unbounded      CHC/Lean
       Refuted     Bounded        BMC/...
       Inconcl.                  evidence
```

- **Verdict** × **Scope** × **Provenance** 는 직교한다.
- `vsProved`는 "증명 성공" verdict이다. bounded/unbounded는 `proofScope`가 결정한다.
- `K`(depth)는 **semantic contract가 아니라 evidence metadata(Provenance)** 이다.
  - `stepBound`/`loopBound`/`depthK`는 solver 설정·증명 절차 제어에만 사용되며,
    검증 판정(soundness)에 소비되지 않는다 (`ir_pipeline_runner.nim:634-636`).
  - 따라서 `ProofScope`는 `{psUnbounded, psBounded}` 순수 enum이고, depth를 중첩하지 않는다.

## 2. Proof Status → VKD Predicate 격리

```
VerificationResult
        │
        ▼
   Query helper (SSOT 독립)
        ├── isProved()
        ├── isUnboundedProved()
        └── isBoundedProved()
        │
        ▼
   VKD policy (별도 정책 계층)
        └── isGenuineKernel()
```

- **`verification_result_types.nim` (SSOT)**: `isProved` / `isUnboundedProved` /
  `isBoundedProved` — 유일한 scope 축, policy 아님.
- **VKD policy (별도 모듈)**: `isGenuineKernel(f, r) = isKernel(f) ∧ isUnboundedProved(r)`.

### Query helper 의미

| Helper | 조건 |
|--------|------|
| `isProved()` | `status == vsProved` |
| `isUnboundedProved()` | `status == vsProved ∧ proofScope == psUnbounded` |
| `isBoundedProved()` | `status == vsProved ∧ proofScope == psBounded` |
| `isGenuineKernel()` | `axiom(f) ∧ pure(f) ∧ isUnboundedProved(r)` |

### vsProved raw comparison prohibition

- **`status == vsProved` is forbidden in proof-authoritative decision logic** (anti-theater rule S3).
- The only exception is the helper function bodies in `verification_result_types.nim` (SSOT).
- All consumers must use `isProved()`, `isUnboundedProved()`, or `isBoundedProved()` — never raw `status == vsProved`.
- This prevents proof-authoritative decisions that bypass scope awareness (bounded vs unbounded).
- Enforced by `anti_theater_gate` rule S3: detects `status == vsProved` / `.status == vsProved` in added lines of src/ and tools/ .nim files except `verification_result_types.nim` (helper SSOT) and `anti_theater_gate.nim` (self-reference).

### VKD 수치

- `genuineKernel` = `axiom ∧ pure ∧ status==Proved ∧ proofScope==Unbounded`.
- CHC → Proved+Unbounded → **count**.
- BMC → Proved+Bounded → **don't count**.
- 결과: `baseline.json`의 `vkdFixed4` = `5/40` **유지**.

## 3. Construction & Deserialization 경계

- **Internal construction** (factory): `scope: ProofScope`는 **compile-time mandatory argument**.
  기본값 없음 → 누락 시 컴파일 실패 (type-level invariant).
- **External input** (미래 대비): scope 누락 시 `deriveVerdict`의 기존
  `vsInconclusive + rkNone → rkEvidenceRejected` 코어스로 fail-closed 처리.
  `rkMissingScope`는 신설하지 않는다 (현재 외부 deserialization 경로 부재, YAGNI).
- **Consumer Breath**: 소비자는 raw `status == vsProved` 대신 **semantic requirement에 맞는 helper**를
  사용해야 한다. bounded 결과를 unbounded로 취급하는 consumer blindness 금지.

## 4. Asset Promotion (Canonical mutation authority)

```
Canonical C  +  Staging S  +  PromotionIntent I
        ↓
   semantic Δ = diff(C, S)
        ↓
   Δ == I ?          (intent가 선언한 add/modify와 Δ 일치)
        ↓
   policy validate   (allowed: expected add/mod; forbidden: unexpected del/schema/identity)
        ↓
   authorize → atomic replace
```

- **AssetPromotionBoundary ≠ CertificatePromotionBoundary** (도메인 경계 유지).
- generator가 canonical을 직접 수정할 수 없다 — 항상 staging을 거쳐 Intent Delta 검증.
- write를 수동으로 막는 write-guard에 예외를 추가하지 않는다 (구조적 강제).

## 5. Certificate Lifecycle

- **Canonical-only stale gate 유지**: `stale_cert_gate`는 canonical SSOT consistency만 책임.
  transient cert를 같은 gate에 강제로 넣지 않는다.
- **transient cert = immutable evidence**: 225개 transient cert는 proof evidence이며
  (`winningStrategy: lean-replay`, `verificationTier: lean-verified`),
  개별 파일에 `lifecycleStage`를 주입하지 않는다. lifecycle은 path/manifest로 표현한다.
- **GC는 별도 lifecycle 정책**: `ax clean --transient` 같은 전용 운영으로 분리한다.
- **`verifyCertificateClosure` 이중 root 규칙**: source-staleness leg는 `projectRoot`
  오버라이드가 주어지면 그 root의 모듈 바이트를 읽는다(외부 subject cert —
  `ax cert verify --project <subjectRoot> <path>`가 공식 진입점). 저널 leg
  (`trustCommitId` 해석)는 항상 AXIOM 제품 repo root의 `data/trusted/journal/`에서
  해석한다 — 저널은 제품의 소유 산출물이고 subject 모듈 바이트와 root를 공유하지 않는다.

## 6. Metadata: semantic / audit 분리

- **semantic state**: `baseline.json`의 `timestamp`(SHA-256 내용 해시) — 결정론적 semantic.
- **audit metadata**: ISO 8601 timestamp (`generatedAt`/`lastSeen`/`firstSeen`/`updated_at`) —
  semantic state에서 분리해 audit artifact로 이동. 결정론성 비교에서 제외.
- `idempotentWrite`/comparison-exclusion(`build_metadata_generator.nim:236-250`)은
  **보조 구현 기법** — 기본 설계 원칙이 아니다.

## 7. Reference Vault = Deterministic Materialized Projection (`ax cert reconcile`)

> **역할**: Reference Vault는 Canonical Proof/Evidence의 **결정론적 materialized view**다.
> 사람이 curate하는 저장소가 아니다. `src/verification/certificates/`의 reference
> certificate는 항상 `CurrentCanonicalEvidence`로부터 재계산되어야 한다.

### 7.1 상태 모델 재확정 (§0 invariant #1 개정)

§0 invariant #1("명시적 promotion만 mutation authority")은 유지되되,
`ReferenceVault`의 정의를 재확정한다:

| 구분 | 내용 |
|------|------|
| **AUTHORITATIVE** | source, proof obligations, execution evidence (TrustCommit journal — `provenance_contract_v3.md` ratify: "Journal = ledger, Certificate = projection"), toolchain identity, solver/kernel 결과 |
| **DERIVED** (materialized view) | reference certificates (`src/verification/certificates/`), VKD baseline, reports, indexes |

**핵심 불변식**: `ReferenceVault == Materialize(CurrentCanonicalEvidence)` —
같은 source + 같은 toolchain + 같은 evidence + 같은 policy → 항상 동일한
byte-level reference vault 표현. Reference certificate에 문제가 생기면
"certificate을 고친다"가 아니라 **"evidence를 재계산하고 projection을 다시 materialize한다"**.

### 7.2 현재 gap (검증 완료)

- reference vault에 새/갱신 `.json`을 쓰는 유일 경로는 `reissueReference`
  (`src/verification/cert_promotion.nim:546`)의 status 재분류뿐 —
  `sourceHash`/`irHash` 재계산 없음.
- `ax vkd sync`는 runtime canonical/transient에만 기록 (orphan step은 의도적으로
  non-destructive, ADR-0012). `tools/rebuild_assets.nim:42`는 `writeCertificates`를
  호출하나 대상이 `build/certificates`(transient)이고 `promotionActive`를 설정하지 않음.
- 따라서 **"source 변경 → reference cert 재생성 → commit"** 상태 전이 그래프에
  한 단계가 제품 프리미티브로 존재하지 않는다. `stale_cert_gate`가 포착한 것이
  정확히 이 단절이다.

### 7.3 새 프리미티브: `ax cert reconcile`

certificate lifecycle 소속. VKD는 projection/metric layer로 유지한다.
`ax vkd reconcile-reference`로 명명하지 않는다.

| 플래그 | 동작 |
|--------|------|
| `--check` | 현재 canonical evidence로부터 기대 reference projection을 결정론적으로 계산하여 tracked vault와 diff(ADDED/UPDATED/REMOVED/UNCHANGED). 파일 불변. drift 시 non-zero exit. (Terraform plan / generator-checker 분리와 동일 구조) |
| `--apply` | 동일 알고리즘 + 원자적 materialization: collect evidence → validate → compute expected vault → diff → write temp vault → fsync/validate → atomic replace → re-read → digest equality 확인 후에만 성공 |

- push CI는 `--check`만, 로컬 개발은 `--apply` (기존 VKD SOP의 generator/checker 분리 원칙 확장).

### 7.4 승격 predicate (reference vault 진입 조건 — 전부 만족해야 함)

```
sourceHash == currentSourceHash ∧ evidence 구조적 유효 ∧ proof/evidence provenance 존재
∧ 주장 status에 상응하는 solver/kernel invocation 유효 ∧ toolchain identity 기록
∧ 인증서 schema canonical (RFC 8785) ∧ obligation이 현재 proof universe에 존재
```

### 7.5 제거 의미론

사람이 무엇을 지울지 판단하는 destructive cleanup이 아니라, 현재 canonical state로
투영했을 때 존재할 수 없는 artifact만 algorithm이 제거하는 **deterministic materialization**.
ADR-0012의 non-destructive 원칙과 충돌하지 않는다 — reconcile은 prove에 절대 자동
포함되지 않는 별도 명시적 명령이다.

### 7.6 결정론성 근거 (byte-stable materialization 보장)

Ed25519 서명 RFC 8032 결정론적 (`src/infrastructure/certificate_attestation.nim:239`,
상수 seed 유도 key), 인증서 작성 경로에 wall-clock timestamp 없음,
RFC 8785 canonical JSON 직렬화, 모든 hash는 내용 유도
(`sourceHash`/`inputHash`/`solverInputDigest`/`solverResultDigest`).

### 7.7 기존 invariant와의 정합성

- **§4 Asset Promotion**의 `generate → validate → inspect → authorize → atomic promote`
  경계를 그대로 통과한다 (`reconcile --apply`가 곧 이 5단계의 인스턴스).
- **§5 강화** — `stale_cert_gate`는 canonical SSOT consistency만 책임지되,
  remediation 안내가 `ax vkd sync`에서 `ax cert reconcile --apply`로 수정된다
  (gate 자체는 mutation 수행 안 함).
- **§0 invariant #1**의 "명시적 promotion만 mutation authority"는 유지 —
  reconcile이 그 명시적 promotion 경로가 된다. write-guard 예외 추가 없음
  (reconcile은 `setPromotionActive`/`clearPromotionActive` 기존 메커니즘 사용).

### 7.8 명시적 금지사항

- **C0.4 레거시 인증서 면제/사면 없음**, `--no-verify` 불가.
- tracked cert 수동 `rm`/`cp` 금지 — 반드시 reconcile의 결과로만 제거/추가.
- fingerprint granularity 변경(module→function)은 이후 정밀화 WP의 과제 —
  invariant "certificate valid iff certificate input identity == current canonical
  input identity"는 granularity와 무관하게 유지.

### 7.9 구현 위치 참조

| 구성 요소 | 경로 |
|-----------|------|
| CLI wiring | `src/cli/cert_cli.nim` (reissue-reference 서브커맨드 패턴) |
| 재사용 빌딩 블록 | `src/verification/cert_builder.nim:43` (`writeCertificates`, `destructiveClean`) |
| orphan 정리 | `src/verification/cert_writer.nim:588` (`cleanOrphanCertificates`) |
| promotion 활성화 | `src/verification/cert_promotion.nim:131` (`setPromotionActive`) |
| vault 읽기 | `src/verification/cert_vault_role.nim:23` (`resolveCertificate(cvCanonicalRead)`) |

상세 WP 계획은 `experiments/act2-wp4g-cert-reconcile/wp4g-plan.md` (별도 문서).

### 7.10 결정론적 Materialized Projection — Result 타입 계약 (WP4-g)

> **참조**: `experiments/act2-wp4g-cert-reconcile/wp4g0-authority-audit.md` (WP4-g 권한 감사)

#### 7.10.1 Result 타입 계약

projection 함수는 failable하다. 투영은 journal-global이 아닌 **artifact-local, per-cert** 단위로 수행된다 — 하나의 tracked reference cert와 그에 바인딩된 현재 증거만을 입력으로 받는다:

```
F(TrackedReferenceCerts, SourceSnapshot, BoundCurrentEvidenceCandidate) → Result<CanonicalReferenceProjection, ProjectionError>
```

| `irHash`별 current variant 수 | 반환 값 |
|---|---|
| 0 | `NoCurrentEvidence` |
| 1 | deterministic projection (`bytes`) |
| \>1 | `Ambiguous` |

`>1` variant는 "bad data"가 아니라 현재 계약 하에서 함수 값이 **정의되지 않은 상태**이다. `Ambiguous`는 오류가 아니라 계약의 미정의 영역이며, `ProjectionError.Ambiguous`로 명시적으로 보고된다.

#### 7.10.2 무순서 증거 집합 세마틱스

기존 설계의 parent-chain fold는 폐기되었다. 각 journal record는 독립적인 root이며, 시간/순서 필드가 존재하지 않는다. `replayJournal`의 순서는 commitId-lexical 정렬이다 (`trust_commit.nim:399`) — 이는 해시 아티팩트이지 의미론적 순서가 아니다.

증거 수집 순서:
1. journal 레코드를 결정론적으로 열거 (`trust_commit.nim:371` `listCommitIds`)
2. 각 레코드를 독립적으로 검증
3. 독립 검증 결과를 모아 canonical evidence set 구축

**순서는 의미론적 의존성이 아니다**. 동일한 `Journal` + `SourceSnapshot` 쌍에 대해 레코드 열거 순서와 무관하게 동일한 `CanonicalReferenceProjection`이 산출되어야 한다. 이는 `computeStableSourceFingerprint` (`core/proof/source_fingerprint.nim:13`)와 `canonicalCertificateString` (`verification/canonical_certificate_payload.nim:45`)가 순서에 무관하게 결정론적이어야 한다는 원칙과 동일하다.

> **Doctrine (WP4-g.1)**: current evidence의 존재는 current verification run이 결정한다. journal은 그 결과가 persist된 저장 매체이며, 바인딩 체인(4-way identity)이 완전한 기록만 해당 정의의 current evidence 후보다. variant 계수는 evidence가 아니다.
>
> 실측 근거: journal 전체를 대상 reconciliation 시 6,824개 역사적 journal 레코드에서 variant explosion이 발생하여 15개 AMBIGUOUS가 산출되었다. 이는 역사 journal이 현재 reference materialization의 권위가 아님을 경험적으로 입증한다 — reference certificate는 현재 canonical evidence의 materialized view이며, journal은 persistence 매체일 뿐이다.

**투영은 artifact-local이다**: 각 reference cert에 대해 하나의 `BoundCurrentEvidenceCandidate`만이 투영 입력으로 유효하다. journal 전체를 스캔하여 variant를 수집하는 것은 현재 계약 하에서 정의되지 않은 동작이다.

#### 7.10.3 Variant Set 구조 및 SelectionPolicy

```
R* = { irHash → variants: Set[(certificateIdentity, bytes)] }
SelectionPolicy = RejectMultiple   # variants.size > 1 → AMBIGUOUS
```

`SelectionPolicy`는 **플러그 가능**하다. 현재 기본값은 `RejectMultiple`이며, `variants.size > 1`이면 즉시 `AMBIGUOUS`로 판정한다. 향후 Open Issue #1 해결 시 `MultiProjection` 또는 `StrongestEvidence`로 교체 가능하며, 이는 핵심 증거 수집 로직을 재작성하지 않고 `SelectionPolicy` 인터페이스만 교체하면 된다.

#### 7.10.4 순수성 — Case U 제거

기존 vault는 **입력이 아니다**. Case U(기존 vault에 의존하는 경로)는 완전히 제거되었다.

검증 테스트 세 가지 — 비어 있는 vault (`loadManifest` (`verification/vault_manifest.nim:41`) 반환 빈 manifest), R1 초기 vault, R2 초기 vault — 동일한 `Journal` + `SourceSnapshot`에 대해 모두 동일한 `--check` 출력을 산출해야 한다. vault의 내용이 projection 결과에 영향을 주면 안 된다. `F(TrackedReferenceCerts, SourceSnapshot, BoundCurrentEvidenceCandidate)`는 vault를 읽지 않고 오직 tracked reference certs, source snapshot, 그리고 바운드된 현재 증거 후보만으로 결정론적으로 투영을 계산한다.

> **reconcile non-verification principle**: reconcile은 검증을 수행하지 않는다. solver=0, verification execution=0, journal mutation=0, source mutation=0.

#### 7.10.5 전체 vault 원자 트랜잭션

모든 정의가 해석 가능(resolvable)하고, 모든 검증이 통과하며, 모호함(ambiguity)이 없을 때에만 적용(apply)한다. **부분 적용은 없다**.

교체는 단일 `renameat2(RENAME_EXCHANGE)` 시스템 콜로 수행한다 — 네임스페이스 전환을 원자적으로 만든다.

- **Crash durability claim 없음**: `renameat2` 자체가 crash-safe를 보장하지 않는다. 플랫폼이 `renameat2`를 지원하지 않거나 실패하면 **fail-closed**이다.
- **비원자적 폴백 없음**: `RENAME_EXCHANGE`가 실패하거나 지원되지 않는 플랫폼에서 비원자적 복사/삭제 폴백을 제공하지 않는다.
- **syscall 번호 routing**: `renameat2`는 아키텍처별 syscall 번호 상수로 호출되어야 한다. generic `syscall()`에 `AT_FDCWD=-100`을 첫 인자로 넘기면 `EINVAL`이 반환된다. 따라서 아키텍처별 `SYS_renameat2` 상수(예: `__NR_renameat2`)를 사용해야 한다.

#### 7.10.6 재구성 레시피 (이미 증명됨)

동일한 입력에 대해 항상 동일한 인증서를 산출하는 재구성 경로:

1. `parse(record.claim)` 정규화 — stray `trustCommitId`, `provenance`, `attestation` 제거
2. `trustCommitId` 추가
3. `provenance` 추가
4. Ed25519 결정론적 재서명 — 상수 seed (`signCertificatePayload` (`certificate_attestation.nim:239`), `verifyCertificateAttestation` (`certificate_attestation.nim:254`))
   - **주의**: 상수 seed의 custody는 Open Issue #3이다.
5. RFC 8785 canonical bytes 직렬화 (`canonicalCertificateString` (`verification/canonical_certificate_payload.nim:45`))
6. `verifyCertificateClosure` (`certificate_verifier.nim:207`)로 재검증 → PASS만 허용

#### 7.10.7 측정 결과 및 NC2/성축(resolution) 분리 (WP4-g0 감사에서 발췌)

> **참조**: `experiments/act2-wp4g-cert-reconcile/wp4g0-authority-audit.md` §7

**NC2/성축(resolution) 분리**: `proximityScore(topology_dependency.nim)`는 NC2(resolution) 항목으로 이제 **RESOLVED**이며 재물질화 가능(REPLACE 가능)하다. calcDynamicTimeoutCore(variants:7)/safeSpeedupRatioCore(6)/clampTimeoutMs(11)/normalizeMaxWorkers(9)/firstBoolCore(5) 5개는 run-residue AMBIGUOUS이며 MATERIALIZATION_UNDEFINED로 분류된다. 이 상태를 §7에 명시한다.

| definition | records | closure필터 후 variant | 판정 |
|---|---|---|---|
| proximityScore (NC2) | 1 | 1 | RESOLVED — 재물질화 가능 |
| safeSpeedupRatioCore | 6 | 3 | AMBIGUOUS → MATERIALIZATION_UNDEFINED |
| clampTimeoutMs | 11 | 4 | AMBIGUOUS → MATERIALIZATION_UNDEFINED |
| firstBoolCore | 5 | 3 | AMBIGUOUS → MATERIALIZATION_UNDEFINED |
| calcDynamicTimeoutCore | 7 | 3 | AMBIGUOUS → MATERIALIZATION_UNDEFINED |
| normalizeMaxWorkers | 9 | 2 | AMBIGUOUS → MATERIALIZATION_UNDEFINED |

**5 AMBIGUOUS 표현 규정**: 위 5개 항목은 proximityScore와 달리 run-residue cert에 대한 AMBIGUOUS이며, MATERIALIZATION_UNDEFINED로 분류된다. 이는 현재 canonical evidence에 대한 단일 결정론적 투영이 불가능한(run-residue) 인증서임을 의미한다.

> **WP4-g.1**: WP4-g.1 closes the current stale sourceHash workflow. It does NOT upgrade stale_cert_gate into full provenance validation.

#### 7.10.8 Run-Residue 발견 (WP4-g0 감사에서 발췌)

> **참조**: `experiments/act2-wp4g-cert-reconcile/wp4g0-authority-audit.md` §8

현재 reference vault의 6개 인증서 중 **5개는 run-residue**이다 — journal의 결정론적 투영이 아니다. `ReferenceVault == Materialize(CurrentCanonicalEvidence)`는 5/6에 대해 실제로 실현된 적이 없다. 이 인증서들은 build/run의 부수 효과로 발행된 것이지, journal reconciliation을 통해 결정론적으로 도출된 것이 아니다. 유일하게 결정론적 투영과 일치하는 것은 `proximityScore` 신규 인증서(`891b6daee`)이며, 이 하나만이 `REPLACE` 가능하다.

#### 7.10.9 Open Issues

| # | 이슈 | 설명 |
|---|---|---|
| #1 | Vault cardinality / selection semantics (CRITICAL) | 다중 인증서 projection vs 단일 선택 규칙 vs canonical run 지정. tier comparability (Lean↔Z3↔NoObligation), 동일 tier 내 tie-break, 다른 identityDigest 처리. 해결 전까지 "latest"/"strongest" 선택 의미론 발명 금지. |
| #2 | runId / run identity 부재 | journal 레코드에 runId 필드가 없어 동일 source에 대해 서로 다른 run의 증거를 구별할 수 없다. |
| #3 | Constant-seed signing key custody | 재현성을 위한 상수 seed의 custody가 결정되지 않았다. 재구성 레시피의 4단계는 "결정론적이지만 custody가 불확실한" 서명을 산출한다. |
| #4 | Archive namespace | archived cert과 current cert의 네임스페이스 분리가 결정되지 않았다. |

> **Bound current evidence candidate**: a bound current evidence candidate is the maximum derivable from the existing schema (`axiom.certificate.v3` + `TrustCommit`). `runId`/`assuranceTier` current-run guarantees remain Open Issue until schema extension.

#### 7.10.10 명시적 금지사항 (Forbidden List)

다음은 `ax cert reconcile`의 결정론적 materialization 계약에서 **명시적으로 금지**하는 행위이다. 이 금지사항은 §7.8의 기존 금지사항을 확장하며, WP4-g0 감사 결과를 반영한다.

| # | 금지 사항 | 이유 |
|---|---|---|
| C0.4 | legacy 인증서 면제/사면 | §7.8 유지. `reissueReference`의 status 재분류만 유일한 기록 경로. |
| `--no-verify` | 검증 우회 불가 | 결정론적 materialization의 핵심은 검증이다. |
| tracked cert 수동 `rm`/`cp` | 반드시 reconcile의 결과로만 제거/추가 | §7.8 유지. |
| 자동 `prove` 호출 | reconcile이 prove에 절대 자동 포함되지 않음 | §7.5 유지. |
| fingerprint granularity 변경 | module-level 정책 유지; 후속 WP에서만 조정 가능 | §7.8 유지. |
| "latest" / "strongest" 선택 의미론 발명 | Open Issue #1 해결 전까지 어떤 multi-cert selection 규칙도 발명하지 않음 | WP4-g0 감사 §9 #1. |
| 비원자적 폴백 | `renameat2(RENAME_EXCHANGE)` 실패 시 fail-closed; 비원자적 복사/삭제 폴백 없음 | §7.10.5. |
| Case U 회귀 | 기존 vault를 입력으로 다시 도입하지 않음 | §7.10.4. |
| 부분 적용 | 모든 정의 해석 가능 ∧ 모든 검증 통과 ∧ 모호함 없을 때만 적용; 부분 적용 금지 | §7.10.5. |

이 금지 목록은 추후 Open Issue 해결 시에만 변경 가능하며, 변경 시 반드시 본 문서의 해당 항목을 갱신하고 변경 사유를 기록해야 한다.

#### 7.10.11 Kernel 정규화 규칙

`ax cert reconcile`는 reference certificate의 kernel 필드를 legacy metadata에 대해 표준화한다:

| 조건 | kernel |
|---|---|
| `certZ3Candidate` + `leanCompilerVerified=true` | `kernel=false` |
| `certGreen` / `certLeanVerified` / `certDualVerified` + `leanCompilerVerified=true` | `kernel=true` |

> **This rule canonicalizes legacy metadata; it does not redefine kernel semantics.**
> 이 규칙은 legacy metadata를 표준화할 뿐, kernel 의미를 재정의하지 않는다.

#### 7.10.12 --cert 스코핑 및 trackedCertName replace-in-place 세마닉스

**--cert 스코핑**: `--cert`는 on-disk 파일명 prefix(또는 content irHash prefix)와 매치한다. 매치하는 tracked reference cert가 0개이면 `CERT_NOT_FOUND` 반환코드 2.

**trackedCertName replace-in-place semantics**: tracked reference cert 파일명은 안정적 identity이다. 재물질화(reconciliation)는 content만 교체한다 — 파일명은 변경되지 않는다. content 교체 후 irHash는 새 evidence의 irHash(`891b6daee9...`)로 갱신된다.
