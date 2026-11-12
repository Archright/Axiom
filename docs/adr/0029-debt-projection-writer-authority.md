# ADR-0029: 부채 원장 산출물별 writer/generator authority — SSOT 권한 · role-set · canonical mutation device

## Status

**Accepted (2026-10-04)** — 결정 영역 **D2 (부채 원장 산출물별 권위)**의 권위 선언 그 자체다.
아래 §Decision의 authority · role-set · device · canonical semantic input 4분리는 이 ADR이 처음
선언한다. §Context의 측정값은 **작업 시작 시점(2026-10-04) 실측**이며, 같은 날 진행된 병렬
정비가 §Consequences의 "측정 이후 변경" 항목에 그대로 기록되어 있다 — 이 ADR은 그 변경을
승인하지도 철회하지도 않고 **관측 사실로만** 기술한다. §Consequences의 잔여는 해소된 것으로
취급하지 않는다.

## Context

### 0. 왜 `config/gates.json`의 projection 모델이 이 산출물로 이전되지 않는가

`config/gates.json:2-3`는 스스로를 "Gate enablement is a pure projection of TopologySpec +
GateEnablement"으로 선언한다 — 즉 원천이 있고, 원천이 정하고, 손대면 안 되는 파생물이다.

`data/debt_registry.json`에 이 모델을 그대로 적용하면 안 된다. 이 파일의 엔트리는
**사람이 직접 쓴 산문(description·title·resolutionNote 등)**을 담고 있다. 등록 자체가
`AGENTS.md` §0.9(극장 금지)에 따른 **인간의 의무**이며, 어떤 원천에서 "파생"될 수 없다.
따라서 이 파일은 **SSOT(authority)** 이다. §2.6이 요구하는 "기존 authority가 있으면 추가하지
말고 소비하라"는 규칙은, 여기서 소비될 authority가 있다는 전제 — 파일 자체가 authority라는
전제 — 위에 성립한다.

### 1. 측정 — registry mutation sink (작업 시작 시점)

`data/debt_registry.json`에 대한 쓰기 sink가 **11개 이상** 존재했고, 그중 하나는 제품 CLI였다
(`src/cli/debt_cli.nim`, `saveJsonFile` → `writeFile(path, data.pretty())`).
"registry를 읽는 코드"와 "registry에 쓰는 코드"는 같은 파일에 뒤섞여 있었고, 읽기가 많았다.

### 2. 측정 — projection generation sink (작업 시작 시점)

`docs/DEBT_REGISTRY.md`를 생성하는 코드가 **다섯 개**였다. 이들은 바이트 형태가 서로 달랐다.

| writer | 형태 |
|---|---|
| `tools/debt_engine.nim` | 6열, severity 그룹, `> Projection: P1 vN` marker — 정본 |
| `tools/debt_codegen.nim` | 같은 6열이지만 **version marker 없음** |
| `tools/debt_registry_gen.nim` | **7열** (`Line` 열 추가) |
| `tools/debt_registry_sync.nim` | 독립 구성 |
| `tools/ast_refine.nim` | **다른 스키마 6열** + **UTC timestamp 삽입** (무결성 §3.1 위반) |

`make pre-commit`(`Makefile:935`)는 이 중 `bin/debt_engine`를 컴파일(`Makefile:940`)하고
`--validate`(`Makefile:947`)를 실행한다. 즉 pre-commit은 **검증만** 하고 재생성하지 않는다 —
동일 산출물에 **다른 바이트를 쓰는** 도구가 pre-commit 경로 밖에 존재하는 상태였다.

### 3. 문제 — "writer가 N개"는 판정 문장이 아니다

부채 원장에는 registry mutation과 projection generation이라는 **서로 다른 두 종류의 쓰기**가
존재한다. 이 둘을 하나의 "writer 수"로 세면 서로 무관한 두 집합이 하나의 숫자로 뭉개진다.
`docs/DEBT_REGISTRY.md`를 3번 쓴 도구와 `data/debt_registry.json`을 3번 쓴 도구는
완전히 다른 실패 모드를 갖는다. 따라서 §Decision은 집합을 **산출물별로** 정의한다.

## Decision

**네 가지를 혼합하지 않는다.** authority(결정권) · role-set(집합 정의) · device(집행 수단) ·
canonical semantic input(의미 입력)은 서로 다른 층이다.

| 층 | 결정 |
|---|---|
| **(a) authority — SSOT** | `data/debt_registry.json` |
| **(b) role-set — 산출물별 sink 집합** | 아래 표 |
| **(c) canonical mutation device** | `tools/debt_engine.nim` |
| **(d) canonical semantic input** | `data/debt_registry.json` 단독 |

### §1 Authority

`data/debt_registry.json`이 추적 대상 결함(tracked defect)에 대한 **유일한 권위**다. 산출물
권위 항목은 정확히 하나이며, 이는 `AGENTS.md:139`("각 제어 대상 상태·산출물에는 정확히 하나의
선언된 authority가 있다 — `Authority ≠ Adapter`")의 요구와 `AGENTS.md:162`(§2.6, "산출물당
생성 authority는 하나다 — 기존 authority가 있으면 추가하지 말고 소비한다")의 요구를 그대로
구현한다. 본 ADR은 이 두 규칙을 **재발명하지 않고 인용만 한다**.

### §2 Per-artifact role-sets — site는 산출물에 대해 ROLE로 분류된다

핵심 정의: **하나의 도구가 SSOT-mutation role과 projection-generation role을 동시에 가질 수
있다. 이것은 허용된다.** 금지되는 것은 "1 writer"와 "1 generator"를 **하나의 공유 sink 카운트**로
합산하는 것이다. 집합은 **산출물별로 독립 계산**한다.

| 산출물 | sink 집합 |
|---|---|
| `data/debt_registry.json` (registry mutation sinks) | `{tools/debt_engine.nim}` |
| `docs/DEBT_REGISTRY.md` (projection generation sinks) | `{tools/debt_engine.nim}` |
| `src/generated/debt_constants.nim` (projection generation sinks) | `{tools/debt_engine.nim}` |

이 3개 집합은 **독립**이다. 어느 집합의 위반이 다른 집합의 위반을 상쇄하지 않는다. 검증은
집합 단위로, 산출물별로, fail-closed로 수행한다.

### §3 Canonical mutation device — 그리고 그것이 무엇이 아닌가

`tools/debt_engine.nim`은 SSOT에 쓸 수 있는 **sanctioned tool 단일**이다.

이것은 **선언된 정책**이며, **sink-anchored closed-world 기계 검사**로 집행된다. 명시적으로
다음은 **아니다**:

- **파일시스템 권한이 아니다.** 파일 모드·ACL·읽기 전용 플래그는 어떤 것도 배치하지 않는다.
- **사람의 편집을 막지 않는다.** 개발자가 에디터로 `data/debt_registry.json`을 여는 것을
  이 결정은 **금지하지 않는다**. 금지한다면 그건 machine-enforced invariant가 아니라
  workflow policy이며, 서로 다른 계층이다.

machine-enforced 되는 것은 정확히 두 가지다: **미등록 코드가 SSOT에 쓰지 않는다**, 그리고
**unprojected edit는 `--validate`에서 실패한다**. human edit는 후자로 걸린다 — projection이
맞지 않으면 byte-identity가 깨진다.

### §4 Canonical semantic input — 그리고 왜 "서명"이 "증명"이 아닌가

`data/debt_registry.json`만이 **출력 바이트를 결정하는 유일한 입력**이다.
`data/architecture_debt.json`은 읽히지만(존재·파싱 선행조건 — `cmdCodegen`의
`fileExists(ArchDebtPath)` guard) 의미를 기여하지 않는 **dead parameter**였다.

> **중요 — 함수 서명은 단언이 아니다.** `aggregate`는 오랫동안 `(registry, archDebt)`를 받았으나
> `archDebt`는 **함수 본문 어디에서도 역참조되지 않았다** — 본문은 registry entry만 읽었다. 만약
> 누군가 본문 내부에 두 번째 `read`를 추가하면 **서명은 한 글자도 바뀌지 않으면서** projection
> 바이트가 바뀐다.

이것이 이 불변식을 **선언이 아니라 측정으로** 다루어야 하는 이유다. 기계가 확인하는 것은
**counterfactual**이다: **유효한** `architecture_debt.json`의 내용을 무작위화해도 출력 바이트가
바뀌지 않아야 한다. 서명 검사로는 이 불변식을 지킬 수 없다.

파라미터는 이후 제거되어 `func aggregate*`는 registry만 받는다. 서명과
단언이 일치하게 되었으나, **counterfactual은 그대로 필요하다** — 서명이 일치하는 것은 지금의
상태에 대한 사실이지, 앞으로 추가될 수 있는 body 내부 read에 대한 보호가 아니기 때문이다.

### §5 Approved manual mutation surface

**승인된 수동 mutation surface는 registry 파일 하나뿐이다.** 이것은 humans가 부채 상태를
변경하는 **운영 PROTOCOL**이며, machine-enforced invariant가 **아니다**. §5를 "사람은 이 파일만
편집한다"는 강제 규칙으로 읽으면 안 된다 — 강제되는 것은 §3의 두 항목이고, 사람이 protocol을
지키지 않더라도 `--validate`은 unprojected edit를 실패시킨다.

## Consequences

### 측정 이후 변경 (관측 기록 — 승인 아님)

같은 날 진행된 병행 정비가 아래을 변경했다. 이 ADR은 이를 **관측 사실로 기록**하며, 이 기록이
정비의 정당성을 승인하는 것은 아니다.

- **registry mutation sinks: 11+ → 2.** 현재 검증된 sink는 `tools/debt_engine.nim` 안의
  `writeFile(RegistryPath, ...)` 2곳이며, 다른 파일에는 없다. 따라서
  §2의 registry mutation 집합 `{tools/debt_engine.nim}`은 **현재 지켜진다**.
- **제품 CLI의 registry 쓰기 경로 제거.** `src/cli/debt_cli.nim`은 현재 `writeFile`을 포함하지
  않는다.
- **`tools/debt_gc.nim`, `tools/ingest_audit_debt.nim`은 현재 읽기 전용.**
- **projection generator 5 → 1.** `tools/debt_codegen.nim`, `tools/debt_registry_gen.nim`,
  `tools/debt_registry_sync.nim`은 working tree에서 **삭제**되었고, `tools/ast_refine.nim`의
  `docs/DEBT_REGISTRY.md` 기록 경로도 제거되었다(`tools/ast_refine.nim:808`은 이제 해당 파일이
  projection이 아니라는 주석). §2의 두 projection 집합도 **현재 지켜진다**.

결과적으로 §2의 세 집합이 현재 상태에서 모두 성립한다. 이는 §2가 선언한 판정 방식
(sink-anchored closed-world, 집합별 독립 평가)이 현재 트리에서 **빨강이 아닌 상태**를 본다는
뜻이며, 이는 이 ADR이 도달해야 하던 상태다.

- **`aggregate`의 dead parameter 제거.** `data/architecture_debt.json`은 §4가 설명한
  undereferenced parameter로 남아 있었으나, 파라미터가 제거되어 현재 `aggregate`는 registry만
  받는다. **서명과 단언이 처음으로 일치했다.**

### O1. 이러한 변화 (what this closes)

- **산출물별 권위가 명명되었다.** 이전에는 "debt registry SSOT"가 선언되지 않았다 — 파일의
  존재가 사실 그 권위였고, 그래서 파일을 쓰는 코드가 자동으로 권위가 되었다. 이제 권위와
  sink 집합이 문서로 고정된다.
- **shared sink count가 금지되었다.** registry mutation과 projection generation을 독립 집합으로
  정의했으므로, 앞으로 writer 수를 세는 어떤 검사도 두 집합을 합산해 통과시킬 수 없다.
- **경쟁 projection generator가 제거되었다.** 산출물당 생성 authority가 하나라는
  `AGENTS.md:162`의 요구가 현재 트리에서 성립한다.

### O2. 명시적으로 닫지 않는 것 (what this does not close)

- **downstream consumer.** 본 ADR은 `registry → debt_engine → declared projection`만 다룬다.
  `projection → consumer`에는 **어떤 주장도 하지 않는다**. field-complete projection이 만들어져도
  consumer가 그것을 올바르게 읽는다는 보장은 없다. 현재 알려진 3개의 결함 consumer
  ((deleted 2026-10-04 — zero importers, never compiled; see DEBT#487) — 6열 projection에 ≥9열을 가정해 213행 중 210행 폐기 및
  나머지 3행 오해석 · `src/gate/runners/debt_scan_gate.nim` — generator가 절대 생성하지 않는
  `"### [Exemption APPROVED] "` marker를 검색 · `tools/hotspot_ranker.nim` — projection이 사용하지
  않는 열 인덱스로 Status를 읽어 전 행을 건너뜀)는
  [`docs/spec/debt_projection_contract.md` §6.1.5](../spec/debt_projection_contract.md)에
  측정과 함께 기록되어 있다. **§6.1의 field-level 계약은 이 셋을 닫지 않는다.**
- **version bump / regeneration 정합.** generator의 `DebtProjectionVersion`은 `"2"`
  (`tools/debt_engine.nim:108`)이고 `Files` 컬럼으로 모든 파일 참조를 내보내도록 바뀌었으나,
  두 산출물은 여전히 `v1`과 `File` 컬럼을 표시한다 (`docs/DEBT_REGISTRY.md:4`,
  `src/generated/debt_constants.nim:3`, `:13`). regeneration이 남아 있다
  ([debt_projection_contract.md §3.2](../spec/debt_projection_contract.md#32-generatorversion-embedding)).
- **사람의 수동 편집.** §3이 기계 집행하는 것은 "미등록 **코드**의 쓰기"이지 사람의 손 쓰기가
  아니다. 아래 잔여 ④ 참조.

### 잔여 ① — registry 쓰기 CLI (DEBT#437)

`ax debt add/update/close` 경로는 여전히 존재하지 않는다. §5의 프로토콜은 계속 수동이다.
[debt_projection_contract.md §9](../spec/debt_projection_contract.md)는 그 경로가 지켜야 할
불변식을 이미 선언해 두었다. → follow-up.

### 잔여 ② — `debt_constants.nim`

`src/generated/debt_constants.nim`은 projection 산출물로 정본화(`AGENTS.md:162`)되었으나,
여전히 손으로 편집할 수 있는 파일로 남아 있다. §3이 기계 집행하는 것은 "미등록 코드의 쓰기"이지
**사람의 손 쓰기**가 아니므로, 이 파일에 대한 수동 편집은 §2/§3의 위반이 아니다. 어느 수준에서
봉인할지는 별도 결정이 필요하다. → follow-up.

### 잔여 ③ — requirement-inflation 항목

계획서가 지목한 **72건 requirement-inflation 항목**은 follow-up으로 남긴다.

> **Unverified.** 72라는 수치를 확인하지 못했다. `data/debt_registry.json`의 엔트리 중
> title/description/category에 `requirement` 또는 `inflation`이 들어간 것은 1건(`DEBT#454`)뿐이고,
> 어느 category도 72건에 이르지 않았다(최대 category는 56건). 이 수치는 **계획서의 주장으로
> 기록하며, 내가 검증한 값이 아니다.** 수치를 확정하려면 원천 정의가 먼저 필요하다.

### 참고 — 갱신된 sink-anchored closed-world 검사의 형태

집합을 단일 카운트로 세지 않는다:

1. 각 산출물에 대해, 그 산출물을 **쓰는** 코드 site를 전수 수집한다(sink-anchored closed world).
2. 각 site를 §2의 role-set에 대조한다.
3. 어느 site든 자기 role-set 밖에 있으면 **그 산출물에 대해** fail-closed.
4. 세 집합은 독립 평가한다 — 한 집합의 통과가 다른 집합에 영향을 주지 않는다.

이것이 없으면 "registry는 writer가 하나다"와 "Markdown은 generator가 하나다"가 각각 참인 채
병존할 수 있고, 그 합은 아무것도 말하지 않는다.

## References

- `AGENTS.md:139` — Per-output authority · `Authority ≠ Adapter`
- `AGENTS.md:162` (§2.6) — 산출물당 생성 authority는 하나
- `AGENTS.md` §0.9 — 극장 금지 (등록의 인간 의무 근거)
- `docs/agents/authority_invariant_protocol.md` — single-writer 점검 항목 · FACT/METHOD 분리
- `docs/adr/0028-hook-installation-authority.md` — authority · writer · device 3분리의 선례
- `docs/adr/0026-execution-authority-unification.md:30,217` — 권위 행위 single-writer 봉인 선례
- `docs/spec/debt_projection_contract.md` — projection 계약 §2(입력) · §6.1(field-level) · §7(versioning)
- `docs/spec/debt_registry_schema.md` §9 — Fact → Authority Map
- `config/gates.json:2-3` — "pure projection of TopologySpec + GateEnablement" (이전 불가 모델의 근거)
- `tools/debt_engine.nim` — `RegistryPath`(94) `DebtProjectionVersion`(108) `CriticalThreshold`(102),
  `proc aggregate*`, the `fileExists(ArchDebtPath)` guard in `cmdCodegen`, the two
  `idempotentWrite` calls, the two `writeFile(RegistryPath, ...)` calls, `DebtRowFields`,
  `DebtRegistryFieldsOutOfContract`
- `tools/ast_refine.nim:808` · `Makefile:935,940,947`

---

*작성일: 2026-10-04. Accepted — D2 권위 선언. 잔여 ①~⑤는 해소된 것으로 취급하지 않는다.*