# Evidence Identity Epoch Contract — 증거 정체성의 3분리와 회전 규칙

> **Status**: NORMATIVE REFERENCE (documentation-only). 본 문서는 이미 랜딩된 구현의
> **관측된 계약**을 정리한다 — 새 구현·CI 배선·정책 변경을 수반하지 않는다. 본 문서의
> 모든 주장은 인용된 코드 위치에 근거하며, 코드가 보증하지 않는 사항은 §8(UNKNOWN)에
> "미정"으로 남긴다 — 문서가 구현보다 강한 보증을 주장하는 것을 금지한다.
> **작성일**: 2026-11-15.
> **계열**: [execution_accounting_contract.md](execution_accounting_contract.md) §15
> (REUSED 5조건·executionEpoch/ciGeneration 분리) ·
> [test_judgment_cas_contract.md](test_judgment_cas_contract.md) (판정 CAS 9성분) ·
> [certification_continuity_contract.md](certification_continuity_contract.md)
> (D6 멱등 판정).

---

## 1. 목적과 대상 (Purpose & Target)

Axiom의 재사용 가능 산출물 — Evidence(증거)·Judgment(판정)·CompletenessBinding(완전성
바인딩) — 은 각자 content-addressed 정체성을 가진다. 이 문서는 그 정체성이 **무엇에
의해 결정되고(성분)·무엇이 바뀌면 회전하는가(회전 사유)**를 단일 참조점으로 정리한다:

- 세 축의 **3분리**: Judgment Epoch · Key Schema Version · Producer Identity (§2).
- **현행 기계 목록**: 이 저장소가 지금 실제로 실행하는 상수·게이트·정책 파일 (§3).
- **EvidenceKey의 전체 입력과 명시적 배제** 목록 (§4)·**키 회전의 핵심 계약 문장** (§5).
- `measuredBinaryDigest`가 해시하는 대상과 바이너리 digest가 EvidenceKey에 들어가지
  않는 이유 (§6).
- **과거 증거 수용 규칙**: 재사용 가능/불가능을 가르는 기계 술어 3종 (§7).
- **미확정(UNKNOWN)**: 지금 코드가 보증하지 않는 것 — 추측으로 채우지 않는다 (§8).

## 2. 3분리 — Judgment Epoch / Key Schema Version / Producer Identity

세 축은 서로 다른 사건에 반응한다. §15.4가 기계적으로 고정하는 방향성 보증은
한쪽 방향이다 — "a new `ciGeneration` MUST leave every `executionEpoch` …
bit-identical unless the execution closure itself changed"
([execution_accounting_contract.md](execution_accounting_contract.md) §15.4):
CI 세대(CI 토폴로지)는 실행 정체성을 건드리지 않는다.

| 축 | 정의(정본) | 무엇이 바뀌면 회전하는가 |
|---|---|---|
| **Judgment Epoch** (실행 의미 에포크, `executionEpoch`) | `ctx.currentEpoch = sha256(toolchainIdentity \| executionConfigDigest \| executionBundleFingerprint)` — [execution_accounting_contract.md](execution_accounting_contract.md) §15.4; 측정 단일 지점 `src/verification/accounting/execution_context.nim:26` (§A3: "execution semantic epoch. It is NOT the CI epoch") | ① 툴체인 정체성(D2) ② 실행 계약 digest ③ 실행 번들 fingerprint 중 **하나라도** 바뀌면 — 즉 "실행 클로저가 움직일 때" 정확히 회전. CI 컷오버 세대(`ciGeneration`)는 **절대** 이 축에 들어오지 않는다 |
| **Key Schema Version** (키 스킴) | `EvidenceKeyScheme` · `JudgmentKeyScheme` · `EvidenceCasSchemaVersion` · `JudgmentPayloadSchema` · `CompletenessBindingSchemaVersion` (§3 표) | 키 도출의 **알고리즘·직렬화·도메인 분리·입력 구성·출력 인코딩**이 바뀔 때 (§5의 5가지 회전 사유). 동일 출력을 산출하는 구현체 교체는 회전이 아니다 |
| **Producer Identity** (생산자 정체성) | Evidence CAS: `composeVerifierIdentity` — `src/verification/evidence_cas.nim:260` (입력 7종: `src/verification/evidence_cas.nim:207`–`222`); Judgment CAS: 클로저 성분 ①–⑨ `src/verification/judgment_cas.nim:422`–`447` | 검증자(producer)의 의미 부품이 바뀔 때: Evidence CAS는 baseTreeOid·recipe·Nim/Lean/Z3 핀·Z3 체크섬 정책·solver 옵션; Judgment CAS는 테스트 소스 클로저·픽스처·번들·의미 집합 등 9성분. 각 성분의 변경이 곧 회전 |

세 축의 독립성은 실측 사례로 구분된다:

- **CI 에포크 승격**(`config/policy/epoch_manifest.json` 변경)은 EvidenceKey의
  `policyDigest` 입력을 회전시킨다(§4: manifest가 `PolicyDigestInputPaths` 멤버 —
  `src/verification/evidence_cas.nim:96`–`101`) — 그러나 실행 클로저가 불변이라면
  `executionEpoch`는 **비트 동일**을 유지해야 한다(§15.4 방향성 보증).
- 반대로 **툴체인 번들 교체**(예: Lean 핀 회전)는 `executionBundleFingerprint`와
  Judgment 클로저 성분 ④를 움직여 `executionEpoch`를 회전시킨다 — CI 세대는 그대로다.

## 3. 현행 기계 목록 (current machine inventory)

각 항목은 이 저장소가 **지금** 실행하는 기계다. 모든 위치는 2026-11-15 기준 main
(checkout 시점) 관측이다.

| 항목 | 값 / 역할 | 정본 위치 |
|---|---|---|
| `EvidenceKeyScheme` | `"axiom.evidence.cas.key.v1"` — EvidenceKey wire의 도메인 분리자. "keys of different eras can never collide across scheme revisions" | `src/verification/evidence_cas.nim:73` |
| `JudgmentKeyScheme` | `"axiom.judgment.cas.key.v5"` — judgment key wire의 도메인 분리자. v5는 M-TREE 컷오버(①·③이 tested tree의 git 객체에서 유도) | `src/verification/judgment_cas.nim:121` |
| `JudgmentPayloadSchema` | `"axiom.judgment.cas.v2"` — 판정 projection payload의 스키마(키가 아니라 payload 내부에서 검사) | `src/verification/judgment_cas.nim:155` |
| `EvidenceCasSchemaVersion` | `"axiom.evidence.cas.v1"` — 증거 레저 **레코드** 스키마. 읽기 시 일치 검사(불일치 → corrupt, fail-closed) | 상수 `src/verification/evidence_ledger.nim:71`; 기록 `:191`; 읽기 검사 `:218` |
| `executionEpoch` | 실행 의미 에포크 = `sha256(toolchainIdentity\|executionConfigDigest\|executionBundleFingerprint)`; §A3 명명 규칙(= 실행 의미 에포크, CI 에포크 아님) | 정의 [execution_accounting_contract.md](execution_accounting_contract.md) §15.4(`:528`); 명명 `src/verification/accounting/execution_context.nim:26`; wire 키 `src/verification/accounting/run_accounting.nim:364` |
| §15.3(e) staleness 소비자 | REUSED 판정 시 `record.executionEpoch == ctx.currentEpoch` 비교 — 불일치면 stale, 재사용 거부 | 판정 CAS: `src/verification/judgment_cas.nim:1666`–`1672`(mismatch → jExecuted); 런 회계: `src/verification/accounting/run_accounting.nim:344`–`347`(validatedAtEpoch 비교); 복원 상태: `src/verification/accounting/run_accounting.nim:385`–`419`(상태 수준 (b)(c)(e)) |
| `epoch_transaction_gate` 4-way binding | CI 에포크 승격 트랜잭션의 원자성: **SliceCatalog(SSOT) + Epoch Manifest + SliceEngine 매핑(callee 3종) + productionExecutionPin**이 같은 커밋(최소 같은 PR)에서 함께 움직여야 함 — 드리프트는 fail-closed. 3-layer 판정(diff·content·pin), reason code `EPOCH_TRANSACTION_INCOMPLETE`/`EPOCH_TRANSACTION_INCONSISTENT` | `tools/ci/epoch_transaction_gate.nim:1`–`9`; 클로저 그룹 G1/G2a/G2b 규칙 `:13`–`85`; 빌드·타깃 `Makefile:374`, `Makefile:385` |
| `config/policy/epoch_manifest.json` | CI 양자화 에포크 매니페스트: 현재 `ciEpochId: "N+9"`(`:2`), `productionExecutionPin: "69d110b982adff5be7878e9fa7d233a9dfff131a"`(`:26`), `mode: "ci-migration"`. EvidenceKey의 `policyDigest` 입력 멤버(아래 §4)이자 4-way binding의 한 축 | `config/policy/epoch_manifest.json` |

주의: `epoch_manifest.json`의 에포크(`ciEpochId`)는 **CI 양자화 에포크**로 §15.4의
`ciGeneration` 계열이다 — `executionEpoch`와는 다른 축이다(§2). 이 둘의 혼동 금지가
[execution_accounting_contract.md](execution_accounting_contract.md) §15.4의 핵심
규칙이다.

## 4. EvidenceKey — 입력 전체 목록과 명시적 배제 목록

**정의** (모듈 문서 `src/verification/evidence_cas.nim:16`–`36` 및 도출부
`src/verification/evidence_cas.nim:307`–`326`):

```
EvidenceKey = H(canonical serialization of:
    schema             = EvidenceKeyScheme
    verifierIdentity   = composeVerifierIdentity(VerifierIdentityInputs)
    evidenceDraftDigest
    headTreeDigest
    mergeTreeDigest
    policyDigest
    scopeDigest)
```

wire는 RFC 8785 canonical JSON(`canonicalJsonString`)으로 고정 멤버 순서·명시적
분리자·UTF-8 바이트로 직렬화되고(§5), 해시는 하우스 커널 `sha256Hex` 하나뿐이다
(`src/verification/evidence_cas.nim:38`–`42`). 입력 조립은 전부 fail-closed
collector를 통과한다(`src/verification/evidence_cas.nim:508`–`533`).

### 4.1 입력 전체 목록 (선언적 멤버 = 계약)

멤버 집합은 `EvidenceKeyInputs` 타입이 **전체 도출 표면**이다 — "a caller CANNOT feed
provenance without widening this type, and the type is the contract"
(`src/verification/evidence_cas.nim:224`–`233`).

| 멤버 | 무엇의 digest인가 | 근거 |
|---|---|---|
| `verifierIdentity` | 검증자 의미 정체성 = `H(baseTreeOid, recipeDigest, nimPin, leanPin, z3Pin, z3ChecksumPolicyDigest, solverOptionsDigest)` | `src/verification/evidence_cas.nim:260`–`265`; 입력 7종 선언 `:207`–`222`; wire(멤버 순 고정) `:244`–`258` |
| `evidenceDraftDigest` | base-tree(B)의 증거 초안 `data/certification/evidence-draft.json` 원문 bytes의 sha256 | `src/verification/evidence_cas.nim:79`; 수집 `:434`–`439` |
| `headTreeDigest` | 대상(subject) head tree H의 git tree OID(40-hex, caller 공급) | `src/verification/evidence_cas.nim:224`–`233`; caller 공급 경로 `:508`–`514` |
| `mergeTreeDigest` | merge-candidate tree OID(40-hex, caller 공급) | 위와 동일 |
| `policyDigest` | **런타임이 읽는 정책 파일 5종**의 chained digest(고정 정렬 순서): `config/decision_binding.waiver.json`, `config/policy/epoch_manifest.json`, `config/policy/landing_required_gateway_tests.json`, `config/policy/merge_admission.json`, `config/trusted_writer_set.json` | 경로 집합 `src/verification/evidence_cas.nim:96`–`101`; 수집기 `:448`–`455` |
| `scopeDigest` | 설치된 검증 범위 잠금 `data/verification_scope.lock` bytes의 sha256 | `src/verification/evidence_cas.nim:85`; 수집 `:441`–`446` |

`verifierIdentity` 내부 멤버의 출처: `baseTreeOid`는 caller 공급(git tree OID),
`recipeDigest`는 빌드 레시피 4파일 체인(`src/verification/evidence_cas.nim:87`–`95`),
`nimPin`은 `NimVersion` 컴파일 상수(`:384`–`387`), `leanPin`은
`proofs/lean-toolchain` **내용**(trim 후 sha256, 버전 리터럴 중복 금지 — `:404`–`419`),
`z3Pin`은 생성된 `BuildEnvZ3Version`(`:389`–`402`), `z3ChecksumPolicyDigest`는
`data/policy/z3_binary_checksums.json`(`:428`–`432`), `solverOptionsDigest`는 결정적
Z3 옵션 집합(`:486` 조립부).

### 4.2 명시적 배제 목록 (provenance — 어느 것도 필드가 없다)

모듈 문서가 열거하는 배제(`src/verification/evidence_cas.nim:16`–`36`):

- `runId`·`runAttempt`·job name·runner 이미지 라벨 — 런 스코프 식별자
- BuildEnv 빌드 스탬프 `BuildDate`/`GitHash`/`CommitCount`
- `ciEpochId` 라벨 문자열(CI 세대 — §15.4의 "never an identity constituent" 규칙)
- lock/mode/maxJobs, nimcache 내용물, 레저 상태, 타임스탬프

그리고 **빌드된 바이너리의 byte hash**(`bin/ax` 등 — §6에서 상세): "Built-binary
byte hashes are NOT a sound verifier identity either"(`src/verification/evidence_cas.nim:21`).
`ArtifactDigest`는 저장 레코드의 무결성 메타데이터로만 존재하고 키에 절대 들어가지
않는다(`src/verification/evidence_cas.nim:199`–`205`, `:457`–`471`).

**명명 주의**(`src/verification/evidence_cas.nim:44`–`49`): CAS의
`EvidenceKeyInputs.policyDigest`는 정책 **집합 전체**의 chained digest이고,
attest 체인의 `AttestationInputs.policyDigest`(`sha256(config/policy/merge_admission.json)`
단일 파일)와는 다른 계약이다. 같은 이름, 다른 계약.

## 5. 핵심 계약 문장 — 구현체 교체는 회전 사유가 아니다

> **동일 SHA-256 알고리즘·동일 입력 직렬화를 쓰는 구현체 교체는 키 회전 사유가
> 아니다.**

EvidenceKey·JudgmentKey는 모두 `sha256Hex`(하우스 커널 단일 정의)와
`canonicalJsonString`(하우스 canonical 직렬화, RFC 8785)로 도출된다 —
`src/verification/evidence_cas.nim:38`–`42`,
`src/verification/judgment_cas.nim:449`–`468`(closure wire + `deriveJudgmentKey`).
이 두 프리미티브가 같은 bytes를 산출하는 한, 그 bytes를 만드는 코드가 어느 모듈에서
구현되었는지는 정체성의 입력이 아니다.

**키가 반드시 회전해야 하는 경우** — 이 5가지가 전부이며, 각각이 스킴 상수 갱신과
함께 이루어져야 한다(도메인 분리자가 다른 시대의 키 충돌을 막는다 —
`src/verification/evidence_cas.nim:73`–`75`,
`src/verification/judgment_cas.nim:121`–`123`):

1. **알고리즘 교체**: `sha256Hex` 이외의 해시(또는 다른 길이/출력 형식)로 바꿀 때.
2. **직렬화 교체**: canonical JSON(RFC 8785 고정 멤버·키 순서) 이외의 wire 형태,
   멤버 순서·분리자·인코딩 변경.
3. **도메인 분리 변경**: 스킴 상수 값 자체의 변경(`…key.v1` → `v2` 등).
4. **입력 구성 변경**: 멤버 추가·제거·재정의(예: `EvidenceKeyInputs`·`JudgmentClosure`
   타입의 확장/축소 — "the type is the contract", `src/verification/evidence_cas.nim:224`–`227`).
5. **출력 인코딩 변경**: 64 소문자 hex(`isHexOfLen` 검증 형태 —
   `src/verification/evidence_cas.nim:328`–`344`) 이외의 표현.

실측 선례 — Judgment 스킴 v2→v3→v4→v5 컷오버는 3·4번 사유의 실제 회전이다: v4는
컴포넌트 ⑤를 의미 집합 digest로 재정의, v5는 ①·③의 유도 원천을 working dir에서
tested tree의 git 객체로 교체(`src/verification/judgment_cas.nim:123`–`154`). 이
선례에서 세대 전환의 착지 방식은 **orphan + 재실행 재발행**이다: "the cutover
orphans every v4-era record in one coherent generation … they remain immutable ledger
history and can never re-verify as — or collide with — a v5 append; the new generation's
first run is EXECUTED and re-mints"(`src/verification/judgment_cas.nim:148`–`151`).

이 5가지 외의 변경(예: collector 내부의 I/O 순서, 동일 wire를 산출하는 리팩터링)은
회전 사유가 아니다 — 다만 회전이 아님을 **주장만으로** 쓰지 않는다: §7의 재사용
술어가 매 런 키를 재유도하므로, 회전이 없으면 HIT가 자동으로 성립한다.

## 6. `measuredBinaryDigest` — 무엇을 해시하며 왜 EvidenceKey에 없는가

**`measuredBinaryDigest`가 해시하는 것**은 **Lean/lake 툴체인 바이너리**다 — `bin/ax`
같은 저장소 빌드 산출물이 아니다:

- 정의: 파일 내용의 tamper-evident sha256(스레드 로컬 memo, racy-window 검증,
  read-then-restat 안정성) — `src/verification/obligation/measured_digests.nim:143`–`148`.
- 소비: `measureToolchainBundleFingerprint`가 **`leanPath`와 `lakePath` 두 바이너리**에
  적용한다 — `src/verification/obligation/lean_kernel_boundary.nim:259`–`260` — 그리고
  이들이 번들 digest 조성(`:273`–`283`)에 들어간다. 이 번들 digest가 §15.3(b)의
  `executionBundleFingerprint`(실행 정체성)·Judgment 클로저 성분 ④
  (`src/verification/judgment_cas.nim:430`)를 지탱한다. Lean/lake는 elan이 핀한
  **외부 툴체인** 바이너리로, 재빌드마다 bytes가 도는 대상이 아니다(핀은
  `lean-toolchain` 내용에서 읽는다 — `src/verification/evidence_cas.nim:404`–`419`).

**저장소 빌드 바이너리의 digest가 EvidenceKey에 들어가지 않는 이유** — hermetic
스탬프: `tools/hermetic_build.nim`가 `BuildEnvCommitCount`/`BuildEnvGitHash`/
`BuildEnvBuildDate`를 컴파일 산출물에 박는다(`tools/hermetic_build.nim:958`–`962`).
따라서 **같은 트리의 재빌드가 의미는 동일한 채 다른 bytes를 낸다** — 이를 키에
해싱하면 "the key … would differ on every CI run (permanent false MISS)"
(`src/verification/evidence_cas.nim:16`–`36`, 상세 근거 `:21`–`26`). 그래서:

- 검증자 정체성은 **의미 digest**(트리 OID·레시피·핀·정책·옵션)로만 조립되고
  바이너리 bytes는 빠진다("nothing else" — `src/verification/evidence_cas.nim:27`–`29`,
  `:244`–`265`).
- 바이너리 digest는 `ArtifactDigest`로 **레코드 수준 무결성 메타데이터**로만 저장된다
  — "NEVER hashed into the EvidenceKey"(`src/verification/evidence_cas.nim:199`–`205`).
- 수집 대상도 **검증 경로가 실제 실행하는** 바이너리로 좁혀져 있다
  (`ExecutedArtifactPaths` = ircheck 1종 — `src/verification/evidence_cas.nim:112`–`124`):
  build-only 바이너리(bin/ax, bin/core_purity_gate, bin/gate_hook 등)는 어떤 검증
  경로도 실행하지 않으므로 수집 자체가 러너 캐시 상태에 의존하게 만든다(2026-10-06
  admission 사고, 비추적 bin/gate_hook — `:34`–`36`).

정리: `measuredBinaryDigest`(lean/lake, 외부 툴체인) → 실행 번들 fingerprint·§15.3(b)
·Judgment ④의 **입력**; 저장소 빌드 바이너리 bytes → 어느 키에도 입력되지 않고
레코드 무결성 메타데이터로만 존재.

## 7. 과거 증거 수용 규칙 — 재사용 가능/불가능

과거 산출물의 재사용은 3개의 독립적 술어가 각자 fail-closed로 판정한다. 어느 하나라도
실패하면 재사용 불가(원 실행 재실행)다.

### 7.1 Evidence CAS HIT — 증거 레저 재사용

근거: `src/verification/attestation_orchestrator.nim:417`–`443`(계약 문서),
`:512`–`547`(기계).

**재사용 가능(HIT)** — 모두 성립해야:

1. 현재 워크스페이스에서 EvidenceKey를 **재유도**(`collectEvidenceKeyInputs` →
   `deriveEvidenceKey` — `src/verification/attestation_orchestrator.nim:512`–`515`);
2. 레저 멤버십 확인(`hasEvidence` — read-only consult, `:534`);
3. 저장 레코드 **재검증**: bytes 재독기 + `payloadSha256` sha256 재계산 + 전체 레코드
   검증 + 키 결합(요청한 키와 일치) — `fetchEvidenceRecord`(`:540`–`543`, 재검증
   계약 `:530`–`533`);
4. 저장 결과가 ALL-PASS이고 4개 번들 필드가 이번 런의 evidence 레코드와 **byte-equal**
   (divergence는 identity anomaly — fail-closed) — `reuseIrHashFromPayload`
   `:562`–`570`.

HIT는 스테이지 (b)+(c)만 skip하는 **유일한 공인 skip**이며 (a)+(d)(e)(f) — 주체
결합·정책/툴체인/범위 실제-동등성 — 은 fresh하게 계속 실행된다(`:426`–`437`).
또한 레코드 자체는 ALL-PASS만 저장 가능하다(`isReusableOutcome` —
`src/verification/evidence_cas.nim:186`–`192`).

**불가능(MISS/ERROR)**: 키 부재(`casMiss`)는 전체 체인 fresh 실행 + 레코드 생산.
"enabled-but-unverifiable" 상태(레코드 corrupt, 읽기 불가, env 이상)는
`casError` → `atInternalError` — fail-closed: "an unverifiable ledger is never
reported as a MISS"(`:439`–`443`).

### 7.2 Judgment CAS REUSED — 판정 레저 재사용 + `executionEpoch` 일치

근거: `src/verification/judgment_cas.nim:78`–`83`(5조건 형태),
`:1641`–`1672`(기계).

**재사용 가능(REUSED, `jReused`)** — 모두 성립해야:

1. **클로저 재유도 일치**: 현재 워크스페이스에서 재유도한 키가 레코드 키와 일치
   (`deriveJudgmentKey` 재유도 — `:1610` 원문, 상태 모드 재유도 `:2037`);
2. **`executionEpoch` 일치** — §15.3(e) staleness: 저장 payload의 `executionEpoch`가
   이번 런의 `captureReuseVerificationContext().currentEpoch`와 문자열 동일
   (`src/verification/judgment_cas.nim:1665`–`1670`; 불일치 사유문 자체에
   "executionEpoch mismatch (§15.3(e) staleness)"가 박혀 있다 — `:1668`);
3. **per-read 재해시**: `fetchEvidenceRecord`의 payload 재독기 + `payloadSha256`
   재계산(`:1649`–`1653`);
4. **payload 계약 통과**: `validateJudgmentPayloadNode` — 스키마·정준 필드 집합·17-fact
   ACCEPT_ALL 등(`:1661`–`1664`).

**불가능**: 위 어떤 조건이든 실패·측정 불가 → `jExecuted`(원 s1a 실행 재실행) —
"the stored fact is not provably this computation's fact"(`:1575`–`1578`). timeout
FAIL을 포함한 비-ALL-ACCEPT 결과는 저장·재사용 대상이 아니다
(`JudgmentVerdictAcceptAll` — `src/verification/judgment_cas.nim:163`–`166`).
런 회계의 REUSED row 판정도 동일 5조건을 따른다([execution_accounting_contract.md](execution_accounting_contract.md)
§15.3, `:496`).

### 7.3 CompletenessBinding schemaVersion 일치 — 완전성 바인딩 적재

근거: `src/core/trusted/completeness_binding.nim:33`(상수
`"completeness-binding-v1"`), `src/infrastructure/evidence_artifact_io.nim:465`–`499`
(로더).

**재사용 가능(load 성공)** — 7개 fail-closed 조건 전부(`:469`–`499`):

1. strict parse(정확한 키 집합·타입); 2. **`schemaVersion == CompletenessBindingSchemaVersion`**
(unknown → none, `:489`–`490`); 3. 키 동등성(저장 `evidenceKey` == 요청 anchor,
`:491`–`492`); 4. `evidenceDigest` 재계산 일치(`:493`); 5. `sourceIdentity`·
`subjectModuleSha256`가 현재 소스와 일치(주석만 바꿔도 stale → none, `:495`–`498`);
6. `semanticProfileId` 일치; 7. `toolchainFingerprint` 일치.

**불가능**: 저장 측도 마찬가지로 미지 버전·불완전 identity의 write를 거부한다
(`saveCompletenessBinding` — `src/infrastructure/evidence_artifact_io.nim:392`–`423`).

### 7.4 공통 규칙

- 모든 재사용 판정은 **fail-closed**다: 누락·불일치·측정 불가는 재사용 거부이지
  에러 삼킴이 아니다.
- 재사용의 정직 표기: Evidence CAS는 `AXIOM_EVIDENCE_CAS: HIT/MISS` 로그 라인
  (`src/verification/attestation_orchestrator.nim:468`–`481`), Judgment CAS는
  `AXIOM_JUDGMENT_CAS: REUSED/EXECUTED` 라인(`src/verification/judgment_cas.nim:1549`–`1562`).
- 레저는 FF-only exactly-once append — 재사용된(rebound) 레코드는 append 시 no-op
  (`alreadyPresent`, `src/verification/evidence_ledger.nim:98`–`101`).

## 8. 미확정 (UNKNOWN) — 코드가 아직 보증하지 않는 것

이 문서는 아래 사항에 대해 **어떤 정책도 선언하지 않는다**. 구현·정책 결정이
랜딩될 때 이 절을 갱신한다.

1. **`EvidenceKeyScheme` v1→v2 bump 시 기존 증거 레저의 마이그레이션 정책 — 미정.**
   Judgment 쪽의 실측 선례(§5: orphan + 재실행 재발행, `src/verification/judgment_cas.nim:148`–`151`)가
   존재하지만, evidence CAS에 같은 방식을 적용할지(고아화), 레코드 이전 도구를
   만들지, 그 외를 택할지는 결정된 바 없다.
2. **스킴 bump의 lockstep 소비자 전체 목록 — 미정.** 본 문서가 관측한 소비자는 §7의
   3술이지만, 저장소 전체에서 미래 bump와 동시 갱신이 요구되는 지점의 완전한
   명세는 존재하지 않는다.
3. **과거 세대 레코드의 감사 열람 도구 정책 — 미정.** 고아화된 v4 이전 세대 레코드는
   "immutable ledger history"로 남는다고 관측되지만(§5 인용), 이후 세대를 읽는
   도구가 과거 세대를 열람할 수단·필요성은 정의되지 않았다.
4. **`executionEpoch` 회전 후 아카이브된 run state의 재검증 정책 — 미정.** 현재
   복원 상태 재검증(`revalidateRestoredStateIdentity`)은 현재 컨텍스트와 비교해
   fail-closed로 거부한다(`src/verification/accounting/run_accounting.nim:385`–`419`).
   거부된 상태의 보존·폐기·재실행 정책은 이 문서의 범위 밖이다.

## 9. 준수와 변경 규칙 (Conformance)

- 본 문서는 문서-only 착지다: 어떤 구현·구성·CI 파일도 변경하지 않는다.
- 본 문서의 주장은 인용된 코드가 보증하는 바에 정확히 일치해야 한다 — 인용 위치가
  코드 개정으로 이동하면 이 문서를 같은 PR에서 갱신한다(file:line 인용 정합성).
- 본 문서가 새 정책을 만들지 않는다: 미래 정책은 §8에 "미정"으로 남고, 결정 시
  관련 SSOT(개별 스펙 문서 또는 AGENTS.md + docs/agents/ 체계)에 먼저 착지한 뒤
  이 문서가 이를 참조한다.
