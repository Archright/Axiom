# Proof-Required Admission Contract — Vault Certificate Binding (Pass 2.96b)

> **Status**: RATIFIED (2026-10-09) — docs-first contract (AGENTS.md §0.5). This
> document fixes the four binding decisions of the approved plan "증명 필수
> 병합" (proof-required landing): scope, binding+freshness, failure semantics,
> transition. The sibling pass it names (Pass 2.96b) and the second flag
> (`vaultCertRequired`) are implemented in `src/cli/merge_cli.nim` under the
> mirror convention defined here.
> **Related**: [merge_admission_controller.md](merge_admission_controller.md)
> (admission architecture — Pass numbering, fact model, verdict vocabulary),
> [certification_continuity_contract.md](certification_continuity_contract.md)
> (subject-continuity certificate — Pass 2.96, INV-1/INV-3),
> [merge_authority_integrity.md](merge_authority_integrity.md),
> `config/policy/merge_admission.json` (policy SSOT),
> `data/verification_scope.lock` (verification scope lock),
> `docs/spec/productization_contract.md` (v1 product contract).
> **Implementation**: `src/cli/merge_cli.nim` (Pass 2.96b + collector +
> policy-epoch identity), `tools/ci/merge_admission_cert_mirror_gate.nim`
> (mirror enforcement).

---

## 0. 문제 정의

`certRequired`(Pass 2.96)는 **subject-continuity 전용**이다: PR/subject 하나에
하나의 서명된 원장 인증서를 요구한다. 그러나 저장소에는 제2의 증명 자산 —
**canonical reference vault**(`src/verification/certificates`, 파일명 = irHash
규약, `cert_integrity_gate` 강제)에 상주하는 **커널 심볼 단위 vault 인증서** —
가 존재하며, manifest(`manifest.json`)가 `(modulePath, functionName) → irHash`
인덱스를 정본으로 유지한다.

증명 필수 병합의 질문: **vault 인증서가 실제 승인 결정에 영향을 주는 상태** —
즉, 활성 커널 심볼을 변경하는 PR이 그 심볼의 유효 vault 인증서 없이(또는
stale 인증서로) 병합 큐를 통과할 수 없게 하려면, 어떤 계약으로 이를
admission에 결속하는가?

이 문서가 확정하는 4결정은 §1–§4다. 설계 원칙:

- **certRequired 확장 금지** — subject-continuity 의미는 그대로 보존한다.
  제2 플래그 `vaultCertRequired`를 같은 미러 관례(policy 키 ↔ merge_cli const
  ↔ facts 필드)로 추가한다.
- **형제 pass** — Pass 2.96의 확장이 아니라 Pass 2.96b(회전 Pass 2.97과 같은
  번호 pass 선례: Option fact + env-gated skip).
- **새 authority 0** — 새 gate, 새 enum(reasonCode는 저널 문자열),
  새 scope authority를 만들지 않는다. 신규 코드는 ①
  `(modulePath, functionName) → vault cert` 조회 수집기 ② policy-epoch 등식
  2건만 허용된다.

## 1. 결정 ① — 범위 (Scope)

**범위 = 변경 ∩ (`data/verification_scope.lock` `kernel_symbols` −
`kernel_exempt_symbols`)**. 새 scope authority를 만들지 않는다.

- `verification_scope.lock` (schema_version 3)이 유일한 범위 authority다.
  면제 적용 후 활성 커널 집합은 `kernel_symbols`에서 `kernel_exempt_symbols`
  를 뺀 집합이다 (정본 계산: `kernel_symbols` − `kernel_exempt_symbols`;
  `vksTotal`은 이 집합의 크기와 일치해야 한다).
- 대상 심볼 = 변경된 파일(`GET /pulls/{N}/files` 전체 페이지 — trust-surface
  와 동일한 수집 경로, rename source 포함)의 경로가 활성 커널 심볼의
  `modulePath`와 일치하는 (modulePath, functionName) 쌍.
- **Pass 2.96b의 요구 대상은 그 교집합 중 vault 인증서가 존재하는 심볼**이다:
  manifest에 `(modulePath, functionName)` 항목이 있는 심볼. 인증서가 존재하는
  대상만 요구한다 — 없으면 이 pass는 그 심볼에 대해 침묵한다(없는 것을
  새로 요구하는 것은 scope 확장이며 이 계약 밖이다).
- 범위 밖 변경(활성 커널 심볼 파일 미포함) → Pass 2.96b는 fire하지 않는다
  (§4 ⑤ — TRUST_SURFACE_MODIFIED와 독립).

**측정 기록 (2026-10-09, `27fce26c`)**: kernel_symbols 40, exempt 17, 활성 23
(= `vksTotal`). canonical vault 인증서 5건이 모두 활성 23심볼 내에 존재한다:
`analyzer_shared_json.nim::firstBoolCore`(lean),
`orchestrator_topology_worker.nim::clampTimeoutMs`·`calcDynamicTimeoutCore`(smt),
`orchestrator_vault.nim::safeSpeedupRatioCore`,
`orchestrator_api.nim::normalizeMaxWorkers`(smt).

## 2. 결정 ② — 결속·신선도 (Binding & Freshness)

### 2.1 제2 플래그와 삼중 미러

`vaultCertRequired`는 Pass 2.96의 `certRequired`와 **동일한 미러 관례**를
따른다:

1. **policy SSOT** — `config/policy/merge_admission.json`의 boolean 키
   `vaultCertRequired`.
2. **merge_cli const** — `src/cli/merge_cli.nim`의 `VaultCertRequired*: bool =
   …` (컴파일 타임 상수; predicate가 읽는 유일한 값).
3. **facts 필드** — `AdmissionFacts.vaultCertRequired: bool` (I/O 경계에서
   const로 채워지는 스냅샷 필드).

기존 `tools/ci/merge_admission_cert_mirror_gate.nim`가 certRequired의 미러를
강제하듯, 제2 플래그의 미러도 같은 게이트의 같은 방식(앵커 문자열 매칭,
fail-closed)으로 강제한다 — 새 gate를 만들지 않고 기존 mirror gate가 두 쌍을
검사하도록 확장한다. 미러 게이트는 값의 정당성이 아니라 **일치**만 단언한다
(기존 게이트의 성문화된 원칙 유지).

### 2.2 policy-epoch 등식 (admission boundary의 신규 코드 ②)

`certificateFactFromNode`(`src/cli/merge_cli.nim`)의 투영을 **복제**한다:
I/O 경계의 수집기가 현재 `sha256(config/policy/merge_admission.json)`과
`sha256(data/verification_scope.lock)`을 계산해 vault-cert fact에 결속하고,
순수 predicate(Pass 2.96b)가 **EXACT 일치**만 강제한다. predicate는 트리를
재유도하지 않는다 (INV-3 동일 원칙 — OID/digest 바인딩 only).

canonical vault 인증서는 `policyDigest`/`scopeDigest` 필드를 휴대하지 않는다
(subject-continuity 인증서와의 스키마 차이 — 실측: `src/verification/
certificates/*.json` vs `data/trusted/certificates/*.json`). 따라서 이
등식의 인증서 측 값은 **manifest 상태**다: 수집기가 읽은 시점의
`manifest.json` 커밋 (B-tree git object)과 scope lock 커밋이, admission이
평가하는 B(event-frozen base)와 동일함을 digest 등식으로 고정한다. 등식이
깨지면(평가 환경의 policy/scope가 B와 다름) → §3의 POLICY_MISMATCH /
SCOPE_MISMATCH.

### 2.3 소스 신선도 — 신규 재검사 금지, 기존 판정 인용

vault 인증서의 **소스 staleness**(sourceHash ≠ 현재 소스)는 이미 존재하는
기존 판정을 인용한다: `isDeepVerified` → `dvcNotCurrent`(`src/core/types/
certificate_types.nim`: "구조적으로 valid하나 현재 product truth가 아님") —
`ax cert verify`(`verifyCertificateClosure`)가 `ccsNotCurrent`로 분류하고
exit 4로 투영하는 거부 경로. admission은 이 판정을 재구현하지 않는다:
**stale 인증서는 `ax cert verify`에서 exit 4 → 거부 해석**이며, Pass 2.96b는
manifest가 가리키는 인증서의 존재 + irHash 파일명 규약 일치(`cert_integrity_gate`
강제: vault 파일명 == 인증서 content irHash)만 요구한다.

### 2.4 semantic profile은 민팅에서 강제 (재검사 금지)

인증서의 semantic profile(번역 버전, toolchain identity, solver 프로파일)의
타당성은 **민팅 시점에 강제된다** — admission이 semantic profile을 재검사하는
경로를 만들지 않는다. admission이 소비하는 것은 존재 + identity(irHash) +
policy-epoch 등식뿐이다. 이는 `cert_integrity_gate`/`cert_reconcile`이 이미
수행하는 canonical vault 정합성 검사의 중복이 될 수 없다.

## 3. 결정 ③ — 실패 의미 (Failure Semantics)

reasonCode는 **저널 문자열**이다 (새 enum 없음 — 기존 `MergeAdmissionOutcome
.reasonCode: string` 관례). Pass 2.96b의 코드 어휘:

| code | 조건 | dryRunExit |
|---|---|---|
| `NO_CERT` | `vaultCertRequired=true`인데 대상 심볼(활성 커널 ∩ vault manifest 존재)의 vault 인증서 fact가 부재 | 1 |
| `SUBJECT_MISMATCH` | 인증서가 존재하나 manifest의 irHash와 파일명/identity가 불일치 (수집기가 실패-fact로 결속) | 1 |
| `POLICY_MISMATCH` | policy-epoch 등식 위반 — 수집기가 결속한 현재 `sha256(merge_admission.json)` ≠ 평가 환경에서 재계산된 값 (즉, 평가 환경 policy ≠ B policy) | 1 |
| `SCOPE_MISMATCH` | policy-epoch 등식 위반 — `sha256(verification_scope.lock)` 동일 구조 | 1 |

- Pass 2.96과 코드 어휘를 공유하는 것은 의도다: 같은 문자열은 같은 의미를
  갖는다 (subject-continuity Pass 2.96의 코드와 무관하게 2.96b가 독립적으로
  판정하며, 어느 pass가 발생했는지는 reason 서문으로 식별 가능해야 한다).
- **exit 4 → 거부 해석**: `ax cert verify`가 `dvcNotCurrent`(ccsNotCurrent)로
  분류한 인증서는 소스-stale이며, admission 대상 수집에서 유효 인증서로
  계수되지 않는다 (§2.3). 거부는 exit 1(NOT-ADMIT)로 투영된다.
- **`TRUST_SURFACE_MODIFIED` 예외 보존 (HARD, 2026-10-10 A1로 조건화)**: `dryRunExit`
  계약은 `GO→0`, `TRUST_SURFACE_MODIFIED→0`(수동 병합 경로 보존 — 정책이 여는
  경로를 required check가 봉쇄하지 않는다), 그 외 NOT-ADMIT→1 이다. **Pass 2.96b의
  도입은 이 예외를 변경하지 않는다.** trust-surface 히트와 vault-cert 요구가
  동시에 성립하는 결합 케이스(trust-surface 파일 변경 ∩ `vaultCertRequired`)
  에서는 **TRUST_SURFACE_MODIFIED가 우선하고 exit 0**이다 — trust surface
  pass(Pass 2.7/2.8)가 2.96b보다 선행하기 때문이다.
  **A1 개정(단일 ④ 정책 거부 = Pass 2.75)**: pass 순서는
  `Pass 0 → **2.75(pin anchor ④)** → 2.7/2.8 → 2.9 → 2.95 → 2.96 → 2.96b → 2.97 → GO`
  이며, 위 exit-0 예외는 **④ 기계 검사(pin@H == derived(H))를 통과한 경우에만**
  성립한다 — 수동 병합 경로는 "사람 의식 + 기계 검사"이다 (검증 입력 부재 시
  trust-surface 히트는 상위 fail-closed 경계에서 `ROT_UNSPECIFIED`/exit 1 —
  "검증 불가 = 착지 불가"). ④ 불일치는 Pass 2.75가 **사다리 선택 코드 verbatim**
  으로 거부한다(①→③→④ 선후위 보존). 단일 거부 계약의 4클래스 분류와 배타성은
  `src/cli/merge_cli.nim` docstring(정책 거부 @H2 / 정책 거부 @사다리·패스 /
  상위 fail-closed / 정책 라우트 exit-0)의 정본을 따른다.
- `TRUST_SURFACE_INCOMPLETE`(페이지네이션 미종료/캡 도달)도 2.96b보다
  선행하며 exit 1을 유지한다 — 나열이 불완전하면 2.96b의 대상 집합 자체가
  증명 불가다.

## 4. 결정 ④ — 전환 (Transition)

### 4.1 subject-continuity 무변경

Pass 2.96(`certRequired`, 원장 인증서, INV-1/INV-3)은 **한 글자도 바뀌지
않는다**. 판정 순서, 코드 어휘, 수집기, artifact handoff(`--cert`,
ADR-0022 §D5-3) 모두 현행 유지.

### 4.2 vault cert는 attest evidence-draft 입력 사전조건 (병존)

attest stage의 D9 evidence staging(`admission-check.yml` — B-pinned draft
`data/certification/evidence-draft.json` + H tree byte-match)은 다음
**사전조건**을 얻는다: draft의 `funcPath`/`funcName`이 vault manifest에
존재하는 대상이면, 그 vault 인증서가 **존재하고 irHash가 일치**해야 attest가
진행된다 (존재+일치 실패 = attest 단계 실패 — fail-closed). 이 사전조건은
Pass 2.96b와 **병존**한다: 사전조건은 증명 자산의 생산 입력을 묶고,
2.96b는 승인 시점의 대상을 묶는다. 어느 쪽도 다른 쪽을 대체하지 않는다.

### 4.3 형제 pass 구조 (Pass 2.96b)

- **Option fact + env-gated skip** — 회전 Pass 2.97의 선례를 그대로 따른다:
  수집기가 vault 대상 집합을 수집해 fact에 결속하고(= some), 대상이 없거나
  수집 입력이 없으면 none(= Pass skipped). Skip은 침묵이 아니라 **기록된
  스킵**이다 (dry-run JSON/journal에 2.96b 상태가 표시된다).
- fact 형태: `AdmissionFacts`에 `(symbol, irHash, currentPolicyDigest,
  currentScopeDigest)` 결속 — predicate는 등식만 평가한다.
- 순서 확정: **2.96 (subject-continuity) → 2.96b (vault cert) → 2.97
  (rotation)**. 번호 pass 삽입 선례(2.95, 2.96, 2.97의 존재)에 따른 형제
  삽입이며, 기존 pass의 재번호화는 하지 않는다.

### 4.4 롤아웃·회수

- `vaultCertRequired` 초기값은 policy SSOT가 결정한다. false = 전체 pass
  사실상 비활성(fact가 결속되어도 요구가 없으면 GO — §3 어휘는
  `vaultCertRequired=true`에서만 발생). true = 활성.
- 회수(비활성화)는 policy 키 + const 동시 변경(미러 게이트 강제)으로만
  가능하며, 본 계약 개정(architect 승인)을 요구한다 — 인증서 요구는
  §2b 플래그 플립으로 조용히 꺼질 수 없다 (Pass 2.96의 "Independent Trust
  Fact" 원칙 동일 적용).

## 5. 검증 가능한 주장의 경계 (Claims Boundary)

이 계약이 **하는 주장**: 활성 커널 심볼 변경 ∩ vault 인증서 존재 대상에
대해, 승인이 (a) 인증서 존재, (b) irHash identity 일치, (c) policy-epoch
등식을 강제한다.

이 계약이 **하지 않는 주장**: (a) vault 인증서의 semantic profile이 승인
시점에 유효함 (§2.4 — 민팅 강제 + `ax cert verify` 인용), (b) 인증서가 없는
커널 심볼의 검증 상태 (요구 집합이 아님), (c) subject-continuity 원장 인증서의
대체 (병존).

## 6. 외부 공식 문서 대조 (§0.5)

- GitHub Actions — [Events that trigger workflows: `merge_group`](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#merge_group):
  `checks_requested` 단일 activity type; "required check가 merge_group을
  트리거에 포함해야 큐 병합에서 check가 보고된다" — S2 실측(S2 시나리오의
  merge_group 관측)이 의존하는 플랫폼 계약. 저장소의 ADR-0027 설계(네이티브
  `merge_group:` 트리거 대신 org gate workflow_call 위임)는 이 공식 문서의
  이벤트 모델 위에서 동작한다.
- 이 문서 자체는 플랫폼 동작을 재정의하지 않는다 — admission predicate의
  제품 결정만 규정한다.

## 7. 구현 바인딩 요약 (구현 PR의 acceptance)

1. `config/policy/merge_admission.json` `vaultCertRequired` 키 +
   `src/cli/merge_cli.nim` `VaultCertRequired*` const + `AdmissionFacts.
   vaultCertRequired` 필드 — 삼중 미러 일치 (mirror gate 확장으로 강제).
2. 수집기 ①: (modulePath, functionName) → vault cert 조회 (canonical vault +
   manifest 인덱스), policy-epoch 등식용 현재 digest 투영 포함 (신규 코드 ②).
3. Pass 2.96b 형제 pass: §3 어휘, §4.3 순서, dryRunExit 예외 보존.
4. attest 사전조건: D9 draft 입력의 vault 존재 + irHash 일치 (§4.2).
5. 테스트: 기존 `tests/cli/test_merge_cli.nim` 패준(65 green 스캐폴드) 위에
   2.96b 케이스 + 결합 케이스 1건 (trust-surface hit + vaultCertRequired →
   `TRUST_SURFACE_MODIFIED` 우선, exit 0).
