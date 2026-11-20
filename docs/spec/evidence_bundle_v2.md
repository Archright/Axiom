# Evidence Bundle v2 (`axiom.evidence-bundle.v2`)

> 계약 정본: 이 문서. 스키마 상수와 digest 정의는
> `src/verification/evidence_bundle/bundle_schema.nim`, 선택 계약은
> `bundle_export.nim`, 검증 leg/exit 계약은 `bundle_verify.nim`과 이 문서가
> 단일 SSOT를 이룬다.

## 1. 목적

Evidence Bundle v2는 **검증 실행(run) 1회가 실제로 선택한 증거**를
자기완결 디렉터리로 고정한다. 검증자는 subject 체크아웃, Axiom journal,
certificate vault, `./bin/ax` 없이 번들만으로 다음을 재확인할 수 있다.

- 번들의 모든 바이트가 선언된 digest와 일치한다 (closed set).
- 각 certificate의 identity 필드가 스스로 재계산된다.
- `sources/`의 blob이 subject tree의 선언된 digest와 일치한다.
- (선택) Lean/Z3 커널을 다시 실행해 기록된 axiom 집합을 관측한다.
- (선택) 외부 GitHub attestation / check-run / ruleset 관측과 대조한다.

번들은 **commit 신원을 주장하지 않는다**. `treeDigest`는 바이트 스냅샷의
digest이고, commit↔tree 결속은 provenance 축(§8)의 몫이다.

## 2. CLI

```
evidence-verify export <proof-state.json> <owner/repo> <commit> <base-sha> \
    <subject-root> <out-dir> [--vault <dir>] [--propositions <path>] \
    [--run-id <id>] [--run-attempt <n>] [--workflow-path <path>] \
    [--workflow-ref <ref>] [--event <name>] [--head-sha <sha>] [--allow-reused]

evidence-verify verify <bundle-dir> [--expect-commit <sha>] \
    [--attestation <path>] [--check-runs <path>] [--ruleset <path>] \
    [--kernel] [--json]
```

- export의 run envelope는 플래그가 없으면 `GITHUB_RUN_ID`,
  `GITHUB_RUN_ATTEMPT`, `GITHUB_WORKFLOW`, `GITHUB_WORKFLOW_REF`,
  `GITHUB_EVENT_NAME`, `GITHUB_SHA`에서만 읽는다. 하나라도 비면 export는
  거부된다.
- `--workflow-path`가 없고 `GITHUB_WORKFLOW_REF`가 있으면
  `owner/repo/.github/workflows/x.yml@refs/...`에서 path를 유도한다.
- `headSha`는 `subject.commit`과 같아야 한다.

### verify exit code

| code | 의미 |
|---|---|
| 0 | 요청된 leg가 전부 PASS (미요청 선택 leg는 `NOT_CHECKED`) |
| 1 | 하나 이상의 leg FAIL |
| 2 | usage/IO 오류 (인자 오류, 번들 디렉터리 부재) |
| 3 | `KERNEL_SKIPPED` — `--kernel`을 요청했으나 재실행 전제조건이 없어 실행 불가 |

`NOT_CHECKED`는 SUCCESS가 아니다. 선택 입력이 없으면 해당 leg는
`NOT_CHECKED`로 보고되며 exit 0은 "요청된 leg만 통과"를 뜻한다.

### Venue — 왜 `ax` 서브커맨드가 아니라 독립 바이너리인가

`ax`(`src/cli/main.nim`)는 checker closure(Tier C — admission 판정에 개입할 수
있는 코드)의 멤버다. 이 검증기를 `ax`에 배선하면 새 verifier 모듈이 closure
멤버로 편입되고, ADR-0025 §9의 "closure 팽창 금지"와 Amendment A2 (i)의
"NON-member production `src/`는 회전으로 승인 불가"에 따라 정식 착지 경로가
닫힌다. 증거 검증기는 admission 판정자가 아니라 증거의 외부 소비자이므로
Tier C가 아니다. 따라서 독립 바이너리 `bin/evidence-verify`로 배포된다.

이 바이너리의 신뢰는 admission rotation pin이 아니라 (a) 공개 커밋, (b) 재현
빌드, (c) 릴리스 digest pin에서 온다. 검증기가 판정 TCB와 같은 바이너리에
들어가지 않는다는 점은 "검증자 독립성"에도 부합한다.

## 3. 선택 계약 (run-scoped selection)

번들에 들어가는 certificate는 **vault 스캔으로 고르지 않는다**.

1. proof state의 `unitEvidenceRefs[<module>::<function>].canonicalEvidence`가
   run이 선택한 증거 집합이다. 필수 필드:
   `propositionHash`, `evidenceId`, `leanSourceHash`, `kaaDigest`,
   `toolchainFingerprint` (모두 64-hex).
2. `runAccounting.units[<unitId>]`가 존재하고
   `verificationOutcome == "SATISFIED"`여야 한다.
   `satisfactionSource`는 기본적으로 `FRESH`만 허용하며, `REUSED`는
   `--allow-reused`를 명시했을 때만 허용된다. 그 외 값은 fail-closed.
3. vault에서는 위 5개 필드 + `modulePath` + `functionName`이 **정확히 하나**
   일치하는 certificate만 채택한다. 0개 또는 2개 이상이면 fail-closed.
4. `unitEvidenceRefs`가 비어 있거나 선택 결과가 0개면 export는 거부된다.

runId는 **semantic identity에 들어가지 않는다** (§5의 D6 분리).

## 4. 번들 레이아웃

```
<out-dir>/
  manifest.json
  certs/<irHash>.json            # manifest.certs[].path와 1:1
  sources/source-index.json
  sources/<subject path>         # subject commit tree의 모든 blob
```

- 루트에는 `manifest.json`, `certs/`, `sources/` 외의 파일이 존재할 수 없다.
- `certs/`와 `sources/`의 파일 집합은 manifest/index가 선언한 집합과
  정확히 같아야 한다 (unlisted file, missing file 모두 FAIL).
- 어떤 구성원도 symlink일 수 없다. 중간 경로 symlink도 거부한다.
- 경로는 상대 경로이며 `..`, 절대 경로, backslash, 제어 문자를 거부한다.
- 상한: `MaxCerts=4096`, `MaxSourceFiles=20000`,
  `MaxCertBytes=8 MiB`, `MaxSourceFileBytes=8 MiB`,
  `MaxTotalSourceBytes=64 MiB`.

## 5. Manifest 스키마 (closed key set)

```json
{
  "schema": "axiom.evidence-bundle.v2",
  "subject": {
    "repository": "Archright/Axiom",
    "commit": "<40-hex>",
    "treeDigest": "<64-hex>",
    "baseSha": "<40-hex>",
    "subjectId": "<64-hex>"
  },
  "run": {
    "runId": "12345",
    "runAttempt": "1",
    "workflowPath": ".github/workflows/ci.yml",
    "workflowRef": "Archright/Axiom/.github/workflows/ci.yml@refs/heads/main",
    "event": "push",
    "headSha": "<40-hex == subject.commit>"
  },
  "toolchain": {
    "verifierBuildId": "<64-hex>",
    "verifierBundleSha256": "<64-hex sha256(getAppFilename())>",
    "nimVersion": "2.2.10",
    "leanToolchainFile": "<proofs/lean-toolchain content>",
    "leanVersion": "4.33.0",
    "leancheckerSha256": "<64-hex or \"\">",
    "z3Version": "4.13.3",
    "z3BinarySha256": "<64-hex>"
  },
  "policy": { "policyDigest": "<64-hex>", "scopeDigest": "<64-hex>" },
  "certs": [
    {
      "irHash": "<64-hex>",
      "propositionHash": "<64-hex>",
      "canonicalProposition": "<canonical predicate text>",
      "evidenceId": "<64-hex>",
      "subjectId": "<== subject.subjectId>",
      "path": "certs/<irHash>.json",
      "sha256": "<64-hex of the cert file bytes>",
      "status": "certGreen",
      "axiomsUsed": ["propext"],
      "backend": "lean+z3",
      "leanSourceDigest": "<64-hex>",
      "artifactIdentity": "<64-hex == leanSourceDigest>"
    }
  ],
  "counts": { "certs": 1, "kernelSymbols": 1 },
  "sourceVault": "<informational: vault directory used at export>",
  "evidenceDigest": "<64-hex>",
  "provenanceDigest": "<64-hex>",
  "bundleDigest": "<64-hex>"
}
```

모든 객체는 closed set이다. unknown key, missing key, 잘못된 타입은
`bundleContent` FAIL이다. duplicate key는 strict parser가 거부한다.

### Digest 정의

```
evidenceDigest   = sha256(canonicalJson({schema, subject, toolchain, policy, certs}))
provenanceDigest = sha256(canonicalJson({run, evidenceDigest}))
bundleDigest     = sha256(canonicalJson(manifest minus bundleDigest))
treeDigest       = sha256(canonicalJson({
                     schema: "axiom.evidence-bundle.tree.v1",
                     entries: [{path, mode, sha256}] sorted by path
                   }))
subjectId        = sha256("axiom.evidence-bundle.subject.v1|repo|commit|treeDigest|baseSha")
```

- `evidenceDigest`는 run-independent다. 같은 subject/cert/toolchain/policy는
  다른 run에서도 같은 값을 낸다.
- `provenanceDigest`는 run envelope를 포함하므로 **semantic identity로 쓰면
  안 된다** (D6 분리).
- `bundleDigest`는 run envelope까지 포함한 파일 전체의 봉인이다.

## 6. Certificate identity

`certEvidence` leg는 다음을 재계산한다.

```
evidenceId = H(obligationId | propositionHash | leanSourceHash | kaaDigest |
               toolchainFingerprint | executionContractDigest
               [| completenessBindingDigest])
kaaDigest  = H(canonicalKaa 문자열 그대로)
artifactIdentity = canonicalKaa.receiptArtifactIdentity == leanSourceHash
leanSourceHash   = H(leanSource)
propositionHash  = H(canonicalProposition)
```

추가 불변식:

- `status ∈ {certGreen, certLeanVerified, certDualVerified, certVerifiedAxiom}`
  이고 `statusConsistentWithEvidence`를 만족해야 한다.
  `certGreen`은 Z3 unsat + Lean verified 증거를 요구한다.
- `axiomsUsed`는 KAA `observedAxiomSet`과 집합으로 같아야 하고
  allowlist `{propext, Classical.choice, Quot.sound, funext}` 안에 있어야 한다.
  `sorry`/`trustCompiler`/`native_decide` 표기는 거부된다.
- `sourceHash`는 `sources/`의 실제 blob에 대한
  `computeStableSourceFingerprint`와 같아야 한다 (`subjectBinding` leg).

### canonicalProposition gap (정직한 한계)

현재 certificate 본문과 KAA 어디에도 canonical proposition **원문**은
저장되지 않는다. `propositionHash`는 canonical predicate의 해시이고
`leanProposition` 해시(=`leanSourceHash`)와 다르므로 재계산할 수 없다.
따라서 export는 `--propositions <path>`를 **필수**로 요구한다.

허용 형식:

```json
{ "<64-hex propositionHash>": "<canonical proposition>" }
```

또는

```json
{ "propositions": [
  { "propositionHash": "<64-hex>", "proposition": "<text>" }
] }
```

proof state의 `canonicalEvidence.canonicalProposition`이 있으면 fallback으로
쓸 수 있다. 둘 다 있으면 일치해야 한다. 없거나 해시가 맞지 않으면 export는
거부된다.

## 7. Verify legs

| leg | 요청 조건 | 검사 |
|---|---|---|
| `bundleContent` | 항상 | strict JSON, closed key/file set, path/symlink, 크기/개수, 3 digest 재계산 |
| `certEvidence` | 항상 | cert 파일 sha, identity 필드 재계산, status/axiom allowlist |
| `subjectBinding` | 항상 | `sources/` blob sha, `treeDigest`, `subjectId`, cert `sourceHash` |
| `kernel` | `--kernel` | toolchain pin 일치 + Lean/Z3 fresh re-execution + axiom 3자 대조 |
| `provenance` | `--attestation` | normalized attestation의 evidenceDigest/run envelope 일치 |
| `mergeAuthority` | `--check-runs`/`--ruleset` | admission App 5795152의 성공 run + ruleset 27097366 |

의존 leg가 실패하면 후속 leg는 `SKIPPED`로 표시한다 (SUCCESS로 읽히지 않게).

### kernel leg

전제조건이 하나라도 없으면 **FAIL이 아니라 SKIPPED(exit 3)**다.

- `verifierBuildId` == 실행 중인 verifier의 측정값
- `verifierBundleSha256` == `sha256(getAppFilename())`
- `nimVersion` == `$NimVersion`
- `leanToolchainFile` == `proofs/lean-toolchain`
- `leanVersion` == 실행된 `lean --version`
- `z3BinarySha256` == 실행 파일 sha256, checksum policy 통과,
  `z3Version` == 빌드 pin

전제조건이 맞으면 certificate마다:

1. `leanSource`를 fresh `lake env lean --threads=1`로 실행하고
   `#print axioms` 관측 집합을 manifest `axiomsUsed`와 비교한다.
2. `smtlib2`를 fresh Z3로 실행해 `unsat`을 요구한다.
3. `leancheckerSha256` pin이 있고 checker가 있으면 leanchecker deep check를
   수행한다. pin이 없거나 checker가 없으면 **SKIPPED로 보고**하되,
   Lean/Z3 재실행이 통과했다면 exit 0이다. checker가 pin과 다르면 FAIL.

## 8. Provenance / merge authority (외부 관측)

번들은 GitHub를 직접 호출하지 않는다. 호출자는 관측 JSON을 파일로 넘긴다.
이 leg들은 **입력의 내부 정합성**만 검사하며, Sigstore 서명이나 GitHub
API 응답의 진위를 재검증하지 않는다 (정직한 한계).

### 8.1 normalized attestation (`--attestation`)

closed key set:

```json
{
  "schema": "axiom.evidence-bundle.attestation.v1",
  "signerRepository": "Archright/Axiom",
  "verified": true,
  "subjectDigestSha256": "<== manifest.evidenceDigest>",
  "run": { "<manifest.run과 모든 필드 동일>" }
}
```

`signerRepository`/`verified`/digest/run이 하나라도 다르면 FAIL.
`subjectDigestSha256`이 evidenceDigest라는 계약은 이 문서가 정의한다.

### 8.2 raw check-runs (`--check-runs`)

GitHub `GET /repos/{owner}/{repo}/commits/{ref}/check-runs` 응답 형태:

- `check_runs` 배열에 `name == "admission-check"`,
  `head_sha == manifest.run.headSha`, `app.id == 5795152`인 run이 있어야 한다.
- 그 run은 `status == "completed"`, `conclusion == "success"`여야 한다.
- `total_count > fetched`면 잘린 읽기로 보고 FAIL (fail-closed).

### 8.3 raw ruleset (`--ruleset`)

- `id == 27097366`
- `enforcement == "active"`
- `bypass_actors == []`
- `rules[type=required_status_checks].parameters.required_status_checks`에
  `{context: "admission-check", integration_id: 5795152}` 존재

두 입력 중 하나만 주어지면 leg는 `NOT_CHECKED`다. 둘 다 PASS여야 PASS다.

## 9. 정직한 한계 (Honest limits)

1. **commit 신원은 provenance 축이다.** `treeDigest`/`subjectId`는 바이트
   스냅샷과 subject 라벨을 결속할 뿐, 해당 tree를 가진 Git commit이
   존재한다는 것을 증명하지 않는다. attestation/check-runs가 그 주장을 맡는다.
2. **canonicalProposition은 외부 입력이다.** §6의 gap 때문에 export는
   propositions map 없이 동작하지 않는다.
3. **Sigstore 재검증 없음.** `--attestation`은 정규화된 관측의 필드 일치만
   검사한다. 서명 검증은 호출자(예: `gh attestation verify`)의 몫이다.
4. **leanchecker는 additive.** pin/바이너리가 없으면 SKIPPED로 보고하며,
   Lean/Z3 재실행과 별개 layer다.
5. **전체 트리 스냅샷.** subject commit의 모든 blob을 `sources/`에 넣는다.
   큰 저장소에서는 번들이 커진다 (상한 §4). 선택적 subset은 v2 범위 밖이다.
6. **proof state는 외부 산출물이다.** 이 저장소에는 실제 run proof state가
   커밋되어 있지 않다. 테스트는 synthetic proof state로 export 경로를
   검증하며, 실 run에서는 `ax`가 생성한 proof state를 입력해야 한다.
7. **verifierBundleSha256은 실행 바이너리 pin이다.** export와 verify가 같은
   바이너리가 아니면 kernel leg는 FAIL한다 (기록된 verifier와 다른 실행자).

## 10. Failure semantics 요약

- 파싱: duplicate key, unknown escape, trailing bytes, BOM, invalid UTF-8,
  depth/node/string 상한 → err.
- 경로: absolute, `..`, backslash, 제어 문자, symlink, 비정규 파일 → err.
- 집합: manifest/index에 없는 파일, 선언됐지만 없는 파일 → FAIL.
- digest: 재계산 불일치 → FAIL.
- 선택: run state에 없는 unit, SATISFIED 아님, REUSED(미허용), vault match
  0/2+ → export 거부.
- 커널: 전제조건 부재 → SKIPPED(3); 재실행 실패/axiom 불일치 → FAIL(1).

## 11. 다른 증거 계약과의 관계 (중복 방지)

이 계약은 main에 이미 착지한 두 문서와 **같은 저장소에 공존**한다. 세 문서의 역할을 명시적으로 분리한다.

| 문서 | 역할 | 상태 |
|---|---|---|
| `docs/spec/admission_evidence_export_contract.md` | canonical certificate-set producer(`ax cert export`, `vault-manifest.v3`, `certificateSetDigest`) 계약 | **Proposed** — engine 구현 착지(`src/verification/cert_export.nim`, `ax cert export`/`ax cert verify-export`); run artifact 배선 미착지 |
| `docs/spec/evidence_capsule_contract.md` | portable replay tier. 축: `proofValidity` / `reproducibility` / `provenanceAuthenticity`. canonical export를 소비 | Normative v1 |
| 이 문서 | run-scoped **envelope**: 한 실행이 선택한 cert body + subject tree + run 봉투 + 외부 authority 관측 | 구현됨 (`evidence-verify`) |

### 11.1 새 권위를 만들지 않는다

번들 leg(`bundleContent`/`certEvidence`/`subjectBinding`/`kernel`/`provenance`/`mergeAuthority`)는 **소비자 측 평가**다. admission verdict·gate·App 판정을 대체하지 않는다. `PASS`는 "요청된 leg가 통과했다"만 뜻하며, capsule의 `proofValidity`/`provenanceAuthenticity` `PASS`를 함의하지 않는다.

### 11.2 이행 규칙 (binding)

engine 구현은 main `f8b3561`(`src/verification/cert_export.nim`, `ax cert export`/`ax cert verify-export`, PR #237)에 착지했다. 그러나 그 export set을 admission run artifact로 업로드하는 workflow 배선은 아직 없다 — 이 계약의 이행 trigger는 **canonical export artifact가 run에서 생산되는 시점**이다.

1. 그 시점에 `evidence-verify export`는 vault를 직접 읽지 않고 **canonical export의 certificate set을 소비**해야 한다. §3의 vault 선택 절차는 그때 제거된다.
2. bundle manifest의 cert identity(`identityDigest`, `propositionHash`, `leanSourceHash`, `kaaDigest`, `toolchainFingerprint`)는 canonical export의 필드와 동일 의미를 유지한다.
3. 이행 전까지 이 exporter는 **유일하게 구현된 run-scoped cert-body exporter**이며, 그 지위는 transitional이다. 새 certificate-set producer를 영구히 두 번째로 유지하지 않는다.
4. 검증자 역할은 겹치지 않는다: `ax cert verify-export`는 canonical export set의 검증자이고, `evidence-verify`는 run-scoped evidence seam의 검증자다. 어느 쪽도 다른 쪽의 `PASS`를 대체하거나 함의하지 않는다.

### 11.3 형식 통합은 계약 개정이다

bundle v2와 capsule v1의 형식 통합·분리는 구현 변경이 아니라 계약 개정으로만 이뤄진다. 어느 한쪽의 `PASS` 의미가 바뀌면 이 표와 양 문서를 함께 개정해야 한다.