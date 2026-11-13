# Canonical Execution Semantics

> **종류**: 설계 방향을 정의하는 **규범 사양 (Normative Spec)**. 이 문서는 증분 검증 엔진의 실행 의미론 계층을 정의하며, 하류 작업스트림(S0b–S4)이 모두 만족해야 하는 계약이다.
> **작성일**: 2026-09-04 (승인된 로드맵 v4.2)
> **권위 입력**: P2 계약 (§4, §7 — 원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제, 보존된 ADR-0017이 참조본), `src/verification/obligation/identity.nim`, `src/core/types/candidate_identity.nim`, `src/core/topology/topology_dependency.nim`, `src/core/types/obligation_evidence.nim`, `src/infrastructure/evidence_artifact_io.nim`, `src/verification/run_identity.nim`, `src/core/utils/shadow_digests.nim`, `src/generated/build_metadata.json`, `docs/spec/config_nims_hermetic_cache_quirk.md`.
> **범위**: 실행 의미론 계층 — 셀렉터 이전, 결정론적 선택 서브시스템 이후. 하류 작업스트림은 이 문서의 절을 구현/검증 대상으로 삼는다.

---

## 착수 전 4계약 문장

다음 네 문장은 이 문서의 근본 계약이며, 파생되는 모든 절의 설계와 검증은 이 문장들에 종속된다. 이 문장들은 건축가(architect)에 의해 고정되었으며, 수정·재해석·축약 없이 그대로 적용된다.

1. **ExpectedAffected의 정의와 독립 oracle의 생성 주체**: `ExpectedAffected(Δ)`는 셀렉터 구현과 코드·데이터 경로가 분리된 Independent SoundnessOracle이 생성한다. oracle은 ① `data/selector_soundness/mutation_catalog.json`의 수기 `expectedAffected` 축, ② 계약 §4.5의 Makefile 의존 축, ③ 독립 참조 구현으로 affected를 별도 계산하는 제3 축으로 구성되며(§4.5 :202의 비독립 한계 해소), 셀렉터는 ExpectedAffected를 생성하지 않고 containment 검증(`ExpectedAffected ⊆ Selected`)의 대상으로만 받는다.

2. **unresolved graph edge가 certainty를 강제하는 방법**: 그래프에 unresolved edge(해석 불가·후보 없는 호출 target, `rrUnresolved`류)가 존재하면, 그 edge 방향으로 영향이 전파될 수 있는 모든 unit에 대해 certainty는 UNCERTAIN이며 SelectionResult는 FALLBACK_REQUIRED(V2 full)이다. unresolved 정보를 digest·선택 결과에서 제거·무시·평활화하는 경로는 존재하지 않는다(GraphArtifact는 unresolved set을 보존하고, unresolvedEdges(G) ≠ ∅이면서 해당 edge가 closure에 도달 가능하면 FULL 승격).

3. **SelectionDerivation은 affectedness proof가 아니라 selector derivation certificate**: SelectionDerivation은 "이 셀렉터가 어떤 입력(CanonicalChangeSet, GraphArtifact, Universe, Policy)과 어떤 정책 적용 순서로 이 Selected 집합을 도출했는가"를 결정론적으로 재생 가능하게 기록하는 도출 증명서(derivation certificate)이다. 그것은 "선택된 unit이 실제로 semantic 영향을 받는다"는 명제를 증명하지 않는다. affectedness의 진위는 `ExpectedAffected ⊆ Selected` containment + 독립 오라클 evidence가 담당한다. (증명서를 영향을 증명하는 것처럼 읽히면 theater — 금지.)

4. **GlobalResult에서 selection-invariant semantic projection의 정의**: GlobalResult의 selection-invariant semantic projection은 "pruned run에서 Selected에 포함된 unit들의 결과로만 계산되고, full run을 Selected로 투영한 결과와 반드시 일치하는 성분들의 집합"이다: unit별 판정·ProofStatus·실패/vacuity 분류·certificate identity. universe 크기에 의존하는 합계·비율 성분(universe 전체 대비 %)은 invariant가 아니라 selection-scoped 보고값이며, 반드시 universe 컨텍스트(Selected/Universe ratio)와 함께 기록한다. 즉 Proj_{sel}(GlobalResult(FULL)) == GlobalResult(PRUNED) — 단, invariant 대상은 위 selection-invariant 성분에 한정.

---

## 1. CanonicalChangeSet

### 1.1 정의 (Normative Requirement)

`CanonicalChangeSet`은 셀렉터의 입력으로 사용되는 변경 집합의 정규화된 표현이다. 이것은 `ChangeDescriptor`(`src/core/types/candidate_identity.nim:27-34`)와 `CandidateProvenance`(`src/core/types/candidate_identity.nim:57-75`)의 확장 대상이며, 기존 3-layer logical identity 체계(`CandidateStateIdentity` / `CandidateProvenance` / `VerificationContextIdentity`) 위에 구축된다.

### 1.2 필드 규격

| 필드 | 타입 | 설명 |
|---|---|---|
| `baseCommit` | `string` | 변경의 기준이 되는 base commit SHA |
| `headCommit` | `string` | 변경의 끝 commit SHA |
| `mergeBase` | `string \| seq[string]` | merge-base commit SHA. git 현실: merge-base는 복수일 수 있음 (multi-parent merge, octopus merge) |
| `canonicalDiffDigest` | `string` | diff content의 정규화된 SHA-256. rename/copy/similarity 헤더를 포함한 diff-pairs의 정규화된 표현 |
| `diffInterpretationPolicy` | `DiffInterpretationPolicy` | rename·copy·submodule·generated·line-level 정책을 규정하는 열거형 |

### 1.3 DiffInterpretationPolicy (세부 정책)

`DiffInterpretationPolicy`는 diff 해석 시 적용되는 정책의 열거형이다:

- **renamePolicy**: `diff-pairs` 헤더의 rename/copy similarity 비율을 어떻게 처리할지 규정. git diff의 `similarity index`(예: `100%`, `67%`)를 포함한 rename/copy 헤더를 정규화 경로에 반영해야 한다.
- **copyPolicy**: copy된 파일의 diff를 원본과 독립적으로 해석할지, 또는 원본의 diff로 병합할지 규정.
- **submodulePolicy**: submodule 변경은 `submodule` 진입이 아닌 상위 레벨의 pointer 변경으로 해석. submodule 내부 diff는 별도 `CanonicalChangeSet`으로 분리.
- **generatedPolicy**: `generated` 마커가 붙은 파일(생성된 소스)의 diff는 `canonicalDiffDigest`에 포함하되, `DiffInterpretationPolicy.generated` 필드로 구분. 생성 파일의 변경은 셀렉터에 의해 자동 포함되며, manual override은 금지.
- **lineLevelPolicy**: line-level diff 해석 시, `diffInterpretationPolicy`에 따라 blank line, comment line, whitespace-only change를 포함/제외할지 결정.

### 1.4 설계 근거 (Design Rationale)

git의 현실적 제약을 정규화 경로에 반영한다:

1. **merge-base는 복수일 수 있다**: octopus merge나 multi-parent merge에서 merge-base가 단일가 아닐 수 있으므로, `mergeBase`는 `string | seq[string]`으로 선언한다. 단일 merge-base를 가정하는 코드가 있으면 그 경로는 `CanonicalChangeSet` 정합성 위반으로 처리한다.
2. **diff-pairs 헤더는 rename/copy/similarity를 운반한다**: `git diff -M -C` 출력의 `similarity index`와 rename/copy 헤더는 `canonicalDiffDigest`의 입력에 포함되어야 한다. 이 헤더를 무시하면 rename/copy에 의한 영향 전파가 누락된다.
3. **`CandidateProvenance` 확장**: 기존 `CandidateProvenance`(`src/core/types/candidate_identity.nim:57-75`)의 `orderedChanges: seq[ChangeDescriptor]`는 PR 단위의 순서화된 변경 체인을 나타낸다. `CanonicalChangeSet`은 이를 diff 기반으로 재정규화하여, PR 순서에 무관한 집합적 변경 표현을 제공한다.

### 1.5 Anchor

- `src/core/types/candidate_identity.nim:27-34` — `ChangeDescriptor` (prNumber, headSha, `changeDescriptorHash`)
- `src/core/types/candidate_identity.nim:57-75` — `CandidateProvenance` (baseCommit, orderedChanges, repositoryIdentity, provenanceDigest)
- `src/core/types/candidate_identity.nim:64-75` — `candidateProvenance` 함수: `sha256Hex(baseCommit & "|" & changesStr & "|" & repositoryIdentity)` — hash-of-parts convention

---

## 2. GraphInterpretationPolicy + GraphArtifact

### 2.1 정의 (Normative Requirement)

`GraphInterpretationPolicy`는 raw topology 그래프를 canonical graph로 변환하는 정책을 규정한다. `GraphArtifact`는 이 정책을 적용한 결과물이며, `GraphDigest = H(canonical(GraphArtifact))`로 정의된다.

### 2.2 GraphInterpretationPolicy 필드

| 필드 | 타입 | 설명 |
|---|---|---|
| `extractionMode` | `enum` | `full` (모든 edge 추출) / `contract` (contract 선언 edge만) / `reachability` (transitive closure만) |
| `edgeSemantics` | `seq[EdgeKind]` | 추출할 edge의 의미론적 종류: `call` (함수 호출), `contract` (contract 의존), `spec` (spec 선언) |
| `unresolvedEdgePolicy` | `enum` | `preserve` (unresolved edge를 보존) — **현재 topology_dependency.nim의 silent drop은 이 정책에 위배됨** |
| `builderVersionDigest` | `string` | `src/generated/build_metadata.json`의 `generatorVersion` 등 builder 식별자의 SHA-256 |

### 2.3 GraphArtifact 구조

```
GraphArtifact = {
  nodes*: seq[GraphNode],              -- 정규화된 노드 집합
  edges*: seq[GraphEdge],              -- 정규화된 edge 집합 (call/contract/spec)
  unresolvedEdges*: seq[UnresolvedEdge], -- 해석 불가 edge 보존 집합 (silent drop 결함 수정)
  builderVersionDigest*: string,        -- build_metadata.json digest 편입
  extractionPolicy*: GraphInterpretationPolicy,
}
```

### 2.4 GraphDigest

```
GraphDigest = SHA256(canonical(GraphArtifact))
```

`canonical(GraphArtifact)`는 `GraphArtifact`의 모든 필드를 정렬·정규화한 후 SHA-256을 산출한다. `unresolvedEdges`는 `GraphArtifact`의 필드로서 반드시 포함되어야 하며, 제거·무시·평활화해서는 안 된다.

### 2.5 현재 결함: topology_dependency.nim의 silent drop

`src/core/topology/topology_dependency.nim:16-41`에서 `resolveCallTarget` 함수는 `rrUnresolved`(후보 없음) 및 `rrAmbiguous`(동일 module에 여러 definition)를 반환하지만, 현재 실행 경로에서 이 결과가 **silent drop**된다. `topology_engine.nim`에서 `ResolutionResult.kind == rrUnresolved`인 경우 해당 edge는 그래프에서 제거되며, 이는 `unresolvedEdges` 보존 정책에 위배된다. 이 결함은 `GraphInterpretationPolicy.unresolvedEdgePolicy = preserve`로 수정해야 하며, `unresolvedEdges`에 포함된 edge가 closure에 도달 가능하면 해당 unit은 FULL 인증 대상으로 승격된다.

### 2.6 Builder Version Digest 편입

`src/generated/build_metadata.json`의 `generatorVersion`(현재 `2`)와 `gitHash`(`42f41b3`)는 `builderVersionDigest`에 편입되어야 한다. builder 버전이 변경되면 `GraphDigest`가 변경되어, 동일 변경 집합이라도 다른 topology 해석 결과를 가진 것으로 구별된다. 이는 hermetic cache identity의 일부이다.

### 2.7 Anchor

- `src/core/topology/topology_dependency.nim:16-41` — `ResolutionKind` (`rrUnique`, `rrAmbiguous`, `rrUnresolved`) 및 `resolveCallTarget` (현재 silent drop)
- `src/generated/build_metadata.json` — `generatorVersion: 2`, `gitHash: "42f41b3"`
- `docs/spec/config_nims_hermetic_cache_quirk.md` — DEBT#417: `.git/index`가 cache key에 포함되는 incidental state 선례. `builderVersionDigest`는 이 선례와 일관되게 toolchain/config/source/dependency fingerprint만을 포함해야 한다.

---

## 3. Semantic Input Model

### 3.1 Semantic vs Incidental Input (Normative Requirement)

`Semantic Input`은 선택 결과에 영향을 미치는 입력이고, `Incidental Input`은 선택 결과에 영향을 미치지 않는 입력이다. 이 구분은 `config.nims` hermetic cache identity(DEBT#417)의 선례를 따른다: cache key는 toolchain/config/source/dependency의 순수 함수여야 하며, VCS workspace state(`.git/index` mtime 등)는 포함되면 안 된다.

### 3.2 Semantic Input 식별자

Semantic Input의 식별자는 다음으로 구성된다:

1. **CanonicalChangeSet digest** — 변경 집합의 정규화된 표현
2. **GraphDigest** — topology 그래프의 정규화된 표현
3. **UniverseDigest** — 검증 대상 universe의 정규화된 표현
4. **PolicyDigest** — 적용된 정책의 정규화된 표현

### 3.3 Incidental Input (DEBT#417 선례)

`config.nims:443-444`에서 `.git/index` content hash가 `envHash`에 포함되지만, CI에서는 `AXIOM_CI_PRESERVE_CACHE=1`로 이 포함이 게이트된다. 이는 `.git/index`가 VCS staging state이지 compiler semantic state가 아니기 때문이다. 마찬가지로, `dependencyDigests`가 hollow(항상 `@[]`)인 현재 실행 경로에서, dependency artifact가 실제로는 semantic input에 영향을 미치지 않는 경우도 `Incidental Input`으로 분류될 수 있다. 그러나 `dependencyDigests`가 non-empty인 경우, 그것은 반드시 `Semantic Input`으로 처리된다.

### 3.4 dependencyDigests Hollow Gap

`src/verification/obligation/identity.nim:184`에서 `dependencyDigests*: seq[string]`은 `CanonicalExecutionBundle`의 필드이다. 현재 실행 경로에서 이 필드는 항상 `@[]`(비어 있음)이며, 이는 `executionIdentity`(`src/verification/obligation/identity.nim:212-217`)의 입력이 `dependencyDigests`의 실제 값이 아닌 빈 리스트라는 것을 의미한다. 이 hollow gap은 `Semantic Input Model`에서 명시적으로 다뤄져야 한다:

- `dependencyDigests`가 `@[]`이면, `Semantic Input`에 dependency artifact 영향이 없는 것으로 해석된다.
- `dependencyDigests`가 non-empty이면, 각 digest가 `Semantic Input`의 일부로 포함된다.
- 이 hollow gap은 `CanonicalExecutionBundle`의 `dependencyDigests` 필드가 실행 경로에서 항상 빈 리스트로 초기화되는 현재 구현의 기술적 한계를 반영한다. 향후 `dependencyDigests`가 채워지면, 이 필드가 `Semantic Input`에 자동으로 반영된다.

### 3.5 Anchor

- `src/verification/obligation/identity.nim:177-206` — `CanonicalExecutionBundle` 및 `canonicalExecutionBundleFingerprint`
- `src/verification/obligation/identity.nim:212-217` — `executionIdentity = H(InputIdentity + ExecutionContractDigest + BundleFingerprint)`
- `src/generated/build_metadata.json` — `generatorVersion: 2` (builder version digest 편입)
- `docs/spec/config_nims_hermetic_cache_quirk.md` — DEBT#417: semantic vs incidental input 구분의 선례

---

## 4. Selection Model & SelectionDerivation + Canonicalization

### 4.1 Selection 정의 (Normative Requirement)

```
Selection = Derive(CanonicalChangeSet, GraphArtifact, Universe, Policy)
```

`Selection`은 위 네 입력에 대해 결정론적으로 산출되는 `Selected` 집합이다. `Derive`는 순수 함수이며, 동일 입력에 대해 항상 동일한 출력을 생성한다(결정성, §4.3).

### 4.2 SelectionDerivation — 도출 증명서 (Derivation Certificate)

`SelectionDerivation`은 "이 셀렉터가 어떤 입력(CanonicalChangeSet, GraphArtifact, Universe, Policy)과 어떤 정책 적용 순서로 이 Selected 집합을 도출했는가"를 결정론적으로 재생 가능하게 기록하는 도출 증명서이다.

**중요**: `SelectionDerivation`은 "선택된 unit이 실제로 semantic 영향을 받는다"는 명제를 증명하지 않는다. affectedness의 진위는 `ExpectedAffected ⊆ Selected` containment + 독립 오라클 evidence가 담당한다. 증명서를 영향을 증명하는 것처럼 읽히면 theater(극장)이며, 이는 `AGENTS.md §0.9`에 의해 금지된다.

`SelectionDerivation`의 구조:

```
SelectionDerivation = {
  inputs*: SelectionInputs,           -- CanonicalChangeSet, GraphArtifact, Universe, Policy의 digest
  policyApplicationOrder*: seq[PolicyStep],  -- 정책 적용 순서 (결정론적 정렬)
  selectedSet*: seq[UnitID],          -- 선택된 unit 식별자 목록
  derivationGraph*: DerivationGraph,  -- 도출 단계의 DAG (idempotent·commutative·associative union)
  derivationDigest*: string,          -- SHA256 of canonical(SelectionDerivation)
}
```

### 4.3 단위별 ProofOfSelection

각 unit `u ∈ Selected`에 대해 `ProofOfSelection(u)`는 `SelectionDerivation` 내에서 `u`가 선택된 경로를 재생 가능한 체인으로 기록한다:

```
ProofOfSelection(u) = {
  unitId*: UnitID,
  selectionPath*: seq[SelectionStep],  -- u가 선택된 경로의 단계들
  stepDigests*: seq[string],           -- 각 단계의 digest (재생 검증용)
}
```

### 4.4 Canonicalization — DerivationGraph의 대수적 합집합

`DerivationGraph`(`src/core/types/obligation_evidence.nim:48-51`)는 `idempotent·commutative·associative union`을 지원한다:

- **Idempotent**: `A ∪ A = A` — 동일 도출 단계를 두 번 합쳐도 결과가 동일
- **Commutative**: `A ∪ B = B ∪ A` — 합집합 순서에 무관
- **Associative**: `(A ∪ B) ∪ C = A ∪ (B ∪ C)` — 그룹화에 무관

`toCanonicalJson`(`src/core/types/obligation_evidence.nim:264-274`)는 `HashSet`의 비결정론적 순서를 정렬된 `seq`로 변환하여 결정론적 JSON을 생성한다. `SelectionDerivation`의 직렬화는 이 방식을 따른다.

### 4.5 직렬화 — InstantiationWitness 패턴

`SelectionDerivation`의 직렬화는 `InstantiationWitness` 패턴(`src/infrastructure/evidence_artifact_io.nim:114-212`)을 따른다:

1. **공유 접두어 DAG**: `SelectionDerivation`을 DAG로 직렬화하여, full-universe 비대(universe 전체 대비 선택 비율)를 방지한다. DAG의 공유 접두어는 동일한 선택 경로를 공유하는 unit들이 중복 저장되지 않도록 한다.
2. **witnessDigest fail-closed 검증**: 직렬화된 `SelectionDerivation`은 `witnessDigest`를 포함하며, 로드 시 이 digest를 재계산하여 일치하지 않으면 `none(SelectionDerivation)`을 반환한다(`evidence_artifact_io.nim:205-207`).
3. **audit object + witnessDigest 패턴**: `InstantiationWitness`는 `sourceIdentity`, `irDigest`, `collectorIdentity`, `collectorRevision`, `schemaVersion`, `witnessDigest`, `witnesses`를 포함하는 JSON artifact로 직렬화된다. `SelectionDerivation`도 동일한 구조를 따른다.

### 4.6 Anchor

- `src/core/types/obligation_evidence.nim:48-51` — `DerivationGraph` (nodes: HashSet[string], edges: HashSet[(string, string)])
- `src/core/types/obligation_evidence.nim:257-262` — `mergeGraphs`: idempotent·commutative·associative union
- `src/core/types/obligation_evidence.nim:264-274` — `toCanonicalJson`: 결정론적 JSON (HashSet → sorted seq)
- `src/infrastructure/evidence_artifact_io.nim:114-212` — `InstantiationWitness` 패턴 (serialized audit object + witnessDigest fail-closed verification)
- `src/infrastructure/evidence_artifact_io.nim:143-161` — `saveInstantiationWitnesses`: JSON artifact 직렬화
- `src/infrastructure/evidence_artifact_io.nim:163-212` — `loadInstantiationWitnesses`: witnessDigest 재계산 및 fail-closed 검증

---

## 5. ExecutionPlan

### 5.1 정의 (Normative Requirement)

`ExecutionPlan`은 불변(immutable)이며, executor의 유일 입력이다. executor는 `ExecutionPlan`을 수신하고 이를 실행할 뿐, "왜 full인가"를 알 수 없다.

```
ExecutionPlan = {
  planIdentity*: PlanIdentity,         -- BaseRunIdentity 확장
  selection*: Selection,               -- Selected 집합
  selectionDerivation*: SelectionDerivation,  -- 도출 증명서
  planStatus*: PlanStatus,             -- VALID / FALLBACK_REQUIRED / ERROR
  certainty*: Certainty,               -- CERTAIN / UNCERTAIN
  uncertaintyReasons*: seq[string],    -- UNCERTAIN 사유 목록
}
```

### 5.2 SelectionResult — §7.7 planStatus 1:1 매핑

`ExecutionPlan.planStatus`는 P2 계약 §7.7(`:417-442` — 원 anchor `incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제, ADR-0017이 참조본)의 `planStatus`와 1:1로 매핑된다:

| planStatus | 의미 | CI 행동 |
|---|---|---|
| `VALID` | 선택 계획이 containment을 스스로 증명 가능 | V1(영향받은 검증) 인증 허용 |
| `FALLBACK_REQUIRED` | containment 증명 불가, V2 전체 인증 필요 | V2 전체 인증 필수 (fallback) |
| `ERROR` | 인자/내부 오류 | CI 실패 처리 |

`certainty` 필드는 `UNCERTAIN`일 때 `planStatus`가 반드시 `FALLBACK_REQUIRED`가 되도록 보장한다. `UNCERTAIN` 사유는 U1(src/core/ 변경인데 import 그래프가 비어/불가용)과 U2(UNCLASSIFIED 소스)로 한정된다(P2 계약 §7.7 `:425-428` — 원 anchor 삭제, ADR-0017 참조본).

### 5.3 Executor의 제한

executor는 `ExecutionPlan`을 수신하는 역할만 수행하며, plan이 왜 `FULL`(즉 `FALLBACK_REQUIRED`)인지에 대한 정보를 갖지 않는다. executor는 planStatus를 검사하고, `FALLBACK_REQUIRED`이면 전체 universe를 실행하며, `VALID`이면 Selected만 실행한다. executor는 planStatus를 재해석하거나, plan의 선택 결과를 수정하거나, plan의 certainty를 재계산하지 않는다.

### 5.4 Anchor

- P2 계약 §7.7 `planStatus` / `certainty` / exit 계약 (원 anchor `docs/spec/incremental_ci_contract.md:417-442`는 CI=0 cutover, 2026-09-20로 삭제 — ADR-0017이 참조본)
- `src/verification/run_identity.nim:98-101` — `BaseRunIdentity` (run-level identity)

---

## 6. Identity Composition

### 6.1 Per-Unit ExecutionIdentity (Normative Requirement)

각 unit의 실행 정체성은 다음으로 정의된다:

```
ExecutionIdentity = H(InputIdentity | ExecutionContractDigest | BundleFingerprint)
```

이 공식은 `src/verification/obligation/identity.nim:212-217`의 `executionIdentity` 함수와 `src/verification/run_identity.nim:98-101`의 `BaseRunIdentity`를 따른다. `ExecutionIdentity`는 **무변경**이며, 이중 스키마(double schema)를 금지한다.

### 6.2 SelectionDigest — run-level PlanIdentity에 편입

`SelectionDigest`는 다음의 해시이다:

```
SelectionDigest = H(canonical(CanonicalChangeSet, GraphDigest, UniverseDigest, PolicyDigest))
```

이 `SelectionDigest`는 run-level `PlanIdentity`(`BaseRunIdentity` 확장)에 편입된다. `PlanIdentity`는 `BaseRunIdentity`(`src/verification/run_identity.nim:98-101`)의 `semanticIdentity`와 `provenance` 필드를 확장하여 `SelectionDigest`를 포함한다.

### 6.3 SelectedDigest — witness의 결과 digest (자기참조 방지)

`SelectedDigest`는 `SelectionDerivation`의 `witnessDigest`(`src/infrastructure/evidence_artifact_io.nim:134-141`)로 산출된다. 이것은 `ExecutionIdentity`의 입력으로 사용되지 않는다 — `SelectedDigest`는 `SelectionDerivation`의 결과이므로, `ExecutionIdentity`의 입력으로 다시 편입하면 자기참조(circular reference)가 발생한다. `SelectedDigest`는 witness의 결과 digest로서, `ExecutionPlan`의 `selectionDerivation` 필드에 기록되며, `ExecutionIdentity`의 입력 리스트에 포함되지 않는다.

### 6.4 Anchor

- `src/verification/obligation/identity.nim:212-217` — `executionIdentity = H(InputIdentity + ExecutionContractDigest + BundleFingerprint)`
- `src/verification/run_identity.nim:98-101` — `BaseRunIdentity` (run-level identity)
- `src/infrastructure/evidence_artifact_io.nim:134-141` — `computeWitnessDigest`: deterministic witness integrity digest
- `src/verification/obligation/identity.nim:177-184` — `CanonicalExecutionBundle` (dependencyDigests 필드)

---

## 7. Result Normalization

### 7.1 UnitResult / GlobalResult 분리 (Normative Requirement)

`UnitResult`는 단일 verification unit의 결과이며, `GlobalResult`는 모든 unit 결과의 집합이다. `GlobalResult`는 `UnitResult`의 합산이 아니라, 각 `UnitResult`의 정규화된 projection의 합집합이다.

### 7.2 Selection-Invariant Semantic Projection (4계약 문장 4의 실현)

`GlobalResult`의 selection-invariant semantic projection은 다음 성분들의 집합이다:

1. **unit별 판정** (pass/fail/skip/unknown)
2. **ProofStatus** (verified/partial/vacuous/contradicted)
3. **실패/vacuity 분류** (failure reason / vacuity reason)
4. **certificate identity** (`CanonicalResultIdentity`)

이 성분들은 `Proj_{sel}(GlobalResult(FULL)) == GlobalResult(PRUNED)`를 만족한다. 즉, full run의 Selected 투영 결과와 pruned run의 결과는 이 성분들에 대해 반드시 일치한다.

**universe 크기에 의존하는 합계·비율 성분** (예: "전체 universe 대비 pass율", "Selected/Universe ratio")은 invariant가 아니라 selection-scoped 보고값이며, 반드시 universe 컨텍스트(Selected/Universe ratio)와 함께 기록한다.

### 7.3 Golden 불변식

```
Project(FullResult, Selected) == PrunedResult
```

**중요**: Full↔Pruned 직접 비교는 논리적 자기모순이었음이 명시된다. `FullResult`는 universe 전체의 결과이고, `PrunedResult`는 Selected만의 결과이므로, 이 둘을 직접 비교하는 것은 universe 크기 차이로 인해 의미가 없다. 반드시 `Project(FullResult, Selected)` — 즉 FullResult를 Selected로 투영한 결과 — 와 `PrunedResult`를 비교해야 한다.

### 7.4 Anchor

- `src/verification/obligation/identity.nim:223-224` — `canonicalResultIdentity = H(DecisionIdentity + FinalVerdict)`
- `src/core/utils/shadow_digests.nim:28-52` — `dependencyGraphDigest` (구조-only digest)
- `src/core/utils/shadow_digests.nim:100-108` — `sixDimensionFingerprint` (6-차원 지문)

---

## 8. Non-interference 원칙

### 8.1 정의 (Normative Requirement)

```
Result(U, Plan_A) == Result(U, Plan_B)   (동일 unit semantic input, U ∈ 양쪽)
```

동일한 unit `U`와 동일한 semantic input에 대해, 두 개의 서로 다른 `ExecutionPlan`(`Plan_A`, `Plan_B`)이 실행되어도 `U`의 결과는 동일해야 한다. 이는 `Plan_A`와 `Plan_B`의 선택 집합이 다르더라도, `U`가 양쪽 모두에 포함되어 있다면 `U`의 결과는 변하지 않아야 함을 의미한다.

### 8.2 전역 budget 누수 (해소됨 — 2026-11-14)

종전 위반(아래)은 **2026-11-14에 코드와 사양이 동일 세대로 해소**되었다:

1. ~~`src/cli/axiom_engine.nim`의 `max(1, prepared.frontier.len)` 스케일링~~ — `initAxiomEngine`에서 `budgetGas`/`expectedNodeCount` 파라미터와 엔진의 `ProofBudget` 필드가 제거되었다(`:271-277`). 엔진은 `startMono`만 보유하며 어떤 실행 계획 크기에도 비례하지 않는다.
2. ~~전역 budget 부족이 unit 실패로 기록되는 경로~~ — 오케스트레이션 호출부의 `gasLimit = engine.budget.gasTotal` 전달이 제거되었고(`:5723`가 생성자 계약), 집계 gas는 판정·게이트 입력이 아닌 telemetry로만 남는다. `orchestrationTimedOut`은 `unitBudget`(유닛 고유 신호) 소진의 결과로만 기록된다(`src/verification/batch_uap/loop_driver.nim:606`).

해소의 기계적 근거: `tests/cli/test_axiom_engine.nim`의 음성 통제(`not compiles(initAxiomEngine(..., expectedNodeCount = …))`)와 `tests/unit/batch_uap_orchestrator_test.nim` exit 0.

### 8.3 수정 요구 (Normative — 구현 완료)

budget은 per-unit contract budget이다:

1. 각 unit은 `ExecutionPlan`에 포함될 때 고유한 `unitBudget`를 부여받는다 — `src/verification/batch_uap/loop_driver.nim:602-605`, `loop_depth_scheduler.nim:334-337`.
2. `unitBudget`는 유닛 고유 신호로 결정되며(`src/core/proof/proof_budget.nim:270-280`), runtime frontier 크기나 shared gas limit에 의존하지 않는다.
3. `orchestrationTimedOut`은 `unitBudget` exhausted의 결과로 기록되며, 전역 budget 부족의 결과가 아니다.
4. targetNodeCount 기반 budget 스케일링은 **제거되었다** — 생성자는 `initAxiomEngine(startMono: int64)`(`src/cli/axiom_engine.nim:271-277`), 호출부는 `:5723`이다. 파라미터 재도입은 테스트 컴파일 실패로 차단된다.

### 8.4 Anchor

- `src/cli/axiom_engine.nim:271-277` — 엔진은 시계만 주입받는다(전역 gas 풀 없음).
- `src/cli/axiom_engine.nim:559-563` — ci-cd 게이트는 `depthCoverage`만 판정한다(전역 예산 관측 제거 → 리포트 결정론).
- `src/verification/batch_uap/loop_driver.nim:602-618` — 유닛 판정은 `checkBudget(unitBudget)`만 소비한다.

---

## 9. Downstream Mapping

이 문서의 각 절은 하류 작업스트림이 구현/검증해야 하는 대상이다. 다음 표는 각 작업스트림과 이 문서의 절을 1:1로 매핑한다.

| 작업스트림 | 이 문서의 절 | 매핑 근거 |
|---|---|---|
| **S0b** — 최소 타입 + 시행 + audit | §1 (CanonicalChangeSet), §3 (Semantic Input Model) | 최소 타입은 `CanonicalChangeSet`, `GraphArtifact`, `SelectionDerivation`의 최소 필드 집합을 정의한다. 시행은 `ExecutionPlan`의 불변성을 검증한다. audit는 `SelectionDerivation`의 `witnessDigest` fail-closed 검증을 검증한다. |
| **S0c** — 4지표 + 1비율 | §7 (Result Normalization) | 4지표(unit별 판정, ProofStatus, 실패/vacuity 분류, certificate identity)와 1비율(Selected/Universe ratio)은 §7.2의 selection-invariant projection 성분이다. |
| **S1** — 3상 + 독립 오라클 | §1 (CanonicalChangeSet), §4 (Selection Model), §8 (Non-interference) | 3상(선택/실행/결과)은 `CanonicalChangeSet` → `ExecutionPlan` → `GlobalResult` 흐름에 대응한다. 독립 오라클은 §4.2의 `ExpectedAffected` 생성 주체와 §1의 containment 검증에 대응한다. |
| **S2** — local 4단계 관문 | §5 (ExecutionPlan), §7 (Result Normalization) | 4단계 관문(선택→실행→결과→게이트)은 `ExecutionPlan`의 `planStatus` 결정과 `GlobalResult`의 selection-invariant projection에 대응한다. |
| **S3** — parallel | §4 (Selection Model), §8 (Non-interference) | parallel execution은 `ExecutionPlan`의 불변성 하에서 unit별 독립 실행을 의미하며, non-interference 원칙(§8.1)이 parallel 실행의 정합성을 보장한다. |
| **S4** — 게이트 3 | §2 (GraphInterpretationPolicy), §5 (ExecutionPlan), §7 (Result Normalization) | 3개 게이트는 `GraphArtifact` 정합성(§2), `ExecutionPlan` planStatus 유효성(§5), `GlobalResult` projection 불변식(§7.3)에 대응한다. |

---

## 문서 변경 이력

| 버전 | 날짜 | 변경 |
|---|---|---|
| v1.0.0 | 2026-09-04 | 초안 — 승인된 로드맵 v4.2 기반 |
| v1.0.1 | 2026-09-30 | **부록 D 추가 (개정/amendment)** — C15 반영 4항목: ① 오라클 스키마 ∅(빈 expectedAffected) 허용 ② 축의 정직한 열거(축③ 부재·§4.5 dangling 명시) ③ CERTAIN-사유 분류 `derivedEmpty` 추가 ④ L0-baseline carve 기록. 4계약 문장(:12–:20)은 불변 — 수정·재해석·축약 없음(ADR-0017 Amendment A2, ADR-0025 Amendment C, DEBT#466(b+)·#467–470) |

---

> **주의**: 이 문서는 규범 사양(Normative Spec)이다. 이 문서의 절은 하류 작업스트림이 반드시 만족해야 하는 계약이다. 이 문서의 내용을 수정하려면 architect 승인이 필요하다(AGENTS.md §-1, §0.10).

---

## 부록 B — 측정 도구 best-effort 정책 (AGENTS.md §0.9 문서화)

`tools/benchmark_cost_probe.nim`의 `probeReadFile`은 identity-cost 측정 중 읽을 수 없는 소스 파일을 건너뛴다(예외 삼킴). 이는 측정 하네스가 digest 비용을 재는 것이지 파일시스템 오류를 검증하는 것이 아니라는 범위 한정이며, 다음 조건으로 극장이 아니다:
1. `{.bestEffort("""...""").}` pragma로 명시적 선언 (문서화)
2. 건너뛴 파일은 런타임에 `[probe] skip unreadable file:` 로그로 출력 (런타임 로깅)
3. 측정값은 건너뜀의 영향을 받을 수 있으며, 결과 JSON의 `notes`에 기록된다

---

## 부록 C — RequestId vs ExecutionIdentity (역할 분리, 2026-09-05 확정)

- **RequestId** = plan 요청의 **유도 identity** (planning 도메인) — 요청이 어떤 정책·타깃 결정으로 유도됐는지 식별. `Requests = Derive(SelectionSet, RequestPolicy)`의 산출물 identity.
- **ExecutionIdentity** = per-unit **검증 실행 identity** (verification/cache 도메인) — `H(InputIdentity | ExecutionContractDigest | BundleFingerprint)` (본문 §7, 불변). result cache key.
- 역할 분리: RequestId는 "무엇을 요청했는가"(planning), ExecutionIdentity는 "실행 결과가 정확히 무엇과 대응하는가"(verification/cache). 두 도메인을 혼용·치환하지 않는다.
- 완전성 기준: 요청 파생의 완전성은 EligibilityOracle(독립 기준)·RequiredRequests(독립 산출물) 대비로만 판정하며, deriveRequests가 자기 출력으로 self-certifying하지 않는다. skip/fallback disposition은 독립 기준 대비 정당화 + evidence를 필수로 갖는다 (무근거 disposition = Completeness 위반).

---

## 부록 D — 2026-09-30 Amendment (C15 반영: 오라클 스키마 ∅ · 축의 정직한 열거 · derivedEmpty · L0-baseline carve)

> **개정(amendment) 선언**: 본 부록은 이 문서에 대한 **개정**이다. 착수 전 4계약 문장(:12의 "수정·재해석·축약 없이" containment 문장과 :14·:18 문장 본문)은 **불변**이며, 본 부록은 그 문장을 수정·재해석·축약하지 않는다. 하류 작업스트림(S0b–S4)이 본 부록과 본문 사이의 해석 충돌을 만나면 **부록의 개정 표시가 최우선**으로 판독한다(ADR-0017 Amendment A2(2026-09-30), ADR-0025 Amendment C(2026-09-30)와 연동 — PR-B "검증 비용 = 증명 필요 집합" 3-PR 계획).

1. **① 오라클 스키마 ∅(빈 expectedAffected) 허용** — 4계약 문장 1의 `ExpectedAffected`는 **공집합일 수 있다**(docs-only Δ 등). 단, 공집합 파생은 검증된 독립 오라클 evidence(`axiom/oracle-evidence/v1` — 5축 `executionClosure`·`productSurface`·`gateScanRoots`·`envHashInputs`·`identity`, `derivedEmpty=true`, `derivationDigest` == 파일 정확한 바이트의 sha256)로만 인정되며, 셀렉터는 이를 **소비·검증만** 한다(자기참조 금지 — §4.2, ADR-0017 A2.1). containment `ExpectedAffected ⊆ Selected`는 ∅에 대해 공허 참(vacuously true)이며, "영향-공집합 후보는 floor 면제"(ADR-0025 Amendment C §C.1)의 전제가 된다.
2. **② 축의 정직한 열거** — 문장 1이 규정하는 3축의 현황을 정직하게 기록한다: ① 수기 `expectedAffected` 축 — `data/selector_soundness/mutation_catalog.json`(+`symbol_mutation_catalog.json`) 실존; ② "계약 §4.5의 Makefile 의존 축" — **dangling 참조**: 본 문서 §4.5는 "직렬화 — InstantiationWitness 패턴"(:203-209)이며 Makefile 의존 축과 무관하고, 원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover(2026-09-20)로 삭제되어 ADR-0017이 참조본; ③ 독립 참조 구현으로 affected를 별도 계산하는 제3축 — **저장소에 부재**. 미실현 축(②·③)은 삭제하지 않고 부재 사실을 명시한다(DEBT#468).
3. **③ CERTAIN-사유 분류 `derivedEmpty` 추가** — §5.2의 UNCERTAIN 사유(U1/U2)에 대칭되는 **CERTAIN-사유 분류로 `derivedEmpty`를 추가**한다: 검증된 오라클 evidence의 `derivedEmpty=true`로 선택 파생이 공집합임이 증명된 경우, `CERTAIN` 판정의 사유로 `derivedEmpty`를 기록한다(ADR-0017 A2.3).
4. **④ L0-baseline carve 기록** — L0 단위(ADR-0019 §4, `docs/spec/incremental_ci_tiers_scheduling.md` §6.3 — 선택에 항상 포함되는 baseline)는 오라클 예측(`ExpectedAffected`) 대상 **밖 carve**로 기록한다. 단, 현행 CI에서 L0 격자 실행 자체가 미실현(DEBT#466, DEBT#469)이며, carve는 **설계 계약으로서만** 존재한다.

### Anchor (부록 D)

- ADR-0017 Amendment A2(2026-09-30) — 오라클 evidence 계약 비준(`axiom/oracle-evidence/v1`)
- ADR-0025 Amendment C(2026-09-30) — floor 면제 비준·EMPTY 모순 해소(SL-09 승격 전 선행 조건)
- `tools/ci/impact_closure_selector.nim` — `loadOracleEvidence`·`oracleEvidence` envelope(병렬 구현 중; 라인 이동 가능)
- `data/debt_registry.json` — DEBT#466(b+), DEBT#467–470
- `docs/evidence/epoch_record_oracle_select_2026-09-30.md` — Freeze/Record/Tombstone
