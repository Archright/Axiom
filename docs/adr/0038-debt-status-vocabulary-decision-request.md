# ADR-0038: 부채 status 어휘 이중 정의 — statusEnum(5값) vs matchesStatus(4값) 의미 계약 결정 요청서

## Status

**Proposed — 인간 아키텍트 결정 대기 (2026-11-02)** — 이 문서는 결정을 내리지 않고
결정을 요청한다. 판정 권한은 인간 아키텍트에게만 있으며(§6), 본 문서는 그 자체로
계약·정책·스키마·코드의 어떤 변경도 아니다. 이 문서의 수용은 어떤 표면의 의미도
바꾸지 않는다 — 표면 변경은 판정 이후 별도 권한 경로의 대상이다.

## 0. 추적 (Tracking)

- **DEBT#512** (`data/debt_registry.json`) — 이 드리프트의 **결정 대기 상태의 정식
  추적 엔트리**다. status=open, resolution=UNRESOLVED로 등록되어 있으며(등록 PR
  #1180, merge cfd685ccb), 본 문서는 레지스트리를 수정하지 않는다. 결정이
  내려지고 그 파생 요구사항이 착지할 때까지 open으로 유지된다.
- 측정 기준: origin/main **7975f3ebe** (2026-11-02). 아래 모든 사실은 읽기 전용
  관측이며, 이 문서 작성 PR은 파일 1건(본 문서)만 추가한다.

## 1. 질의 (Query)

부채 status 어휘에는 서로 어긋나는 두 정의가 존재한다.

- **Schema**: `data/debt_schema.json:12-16` `statusEnum` — 5값
- **Gate**: `src/gate/runners/debt_integrity_gate.nim:60-62` `matchesStatus` — 4값

핵심 질의: 이 차이는

- **(a)** Schema가 부채 전체 생애주기 상태 공간을, Gate가 admission 단계에서
  허용하는 하위 집합을 표현하는 **의도된 2층 구분**인가, 아니면
- **(b)** 동일 규범 집합을 표현해야 하는 두 소비자 사이의 **실제 드리프트**인가.

그리고 5번째 값의 정체(§3.1)와, admission 맥락에서 그 값이 허용·거부되어야 하는
의미가 무엇인가.

## 2. 관련 사실 (Facts)

### 2.1 두 어휘의 실측 값

Schema — `data/debt_schema.json:12-16`:

```json
"statusEnum": {
  "type": "string",
  "enum": ["open", "closed", "accepted", "deferred", "in_progress"],
  "description": "Canonical lifecycle status. Prefer these values for new entries."
}
```

Gate — `src/gate/runners/debt_integrity_gate.nim:60-62`:

```nim
func matchesStatus(s: string): bool =
  s in ["open", "closed", "deferred", "resolved"]
```

| 집합 | 값 |
|---|---|
| statusEnum (5) | `open`, `closed`, `accepted`, `deferred`, `in_progress` |
| matchesStatus (4) | `open`, `closed`, `deferred`, `resolved` |
| 교집합 (3) | `open`, `closed`, `deferred` |
| 스키마 전용 (2) | `accepted`, `in_progress` — 게이트 구조검증 비매칭 |
| 게이트 전용 (1) | `resolved` — statusEnum 부재 |

`docs/spec/debt_registry_schema.md` §3도 status 예시로 정확히 statusEnum의 5값을
나열한다("e.g. `open`, `closed`, `accepted`, `deferred`, `in_progress`"). 같은
문서 §5의 resolution 정준값은 `FIXED`/`FALSE_POSITIVE`/`WONT_FIX`/`ORPHANED`/
`UNRESOLVED`다 — `resolved`는 스키마·spec 어느 정준 status 목록에도 없다.

### 2.2 집행 경로 (enforcement path)

- `validateDebtRegistryImpl` (`debt_integrity_gate.nim:107-122`)는 각 엔트리의
  status에 `matchesStatus`를 적용하고, 비매칭이면 `entry[N].status: invalid`
  finding을 추가한다(:121-122).
- `run()`은 이 findings를 **warn 채널**로 기록한다(:263-265, `logWarn`) — registry
  구조 findings는 이 바이너리의 exit code에 직접 반영되지 않는다. exit code를
  결정하는 것은 레지스트리 부재(:252-254), Step 2(베이스라인 지표 증가,
  :277-287), Step 5(STALE 바인딩 실패, :316-334)뿐이다.
- 같은 파일의 Step 3 결합검증은 별도 술어로 동작한다: `isAcceptedStatus`
  (:234-235, `accepted`/`exempted`)와 `isOpenStatus`(:237-238, `open`)가
  :303-305에서 소비된다. 즉 **게이트는 `accepted`를 의미적으로 처리하면서, 자기
  구조검증(`matchesStatus`)은 `accepted`를 invalid로 표지한다** — 두 경로가 같은
  바이너리 안에 공존한다.
- 워크스트림 관행상 게이트 실행의 판정은 "실패집합"을 클린 베이스라인과 비교하는
  방식이며, 그 실패집합에는 WARN 채널 findings가 포함된다(커밋 2cd4977a0 커밋
  메시지 재검증 기록: "실패집합 = 클린 베이스라인과 동일 (WARN
  [26][36][382][417] + nimtry 4222>4092)"). 신규 `status: invalid` finding은 이
  실패집합에 delta를 만든다.

### 2.3 측정된 선례 — DEBT#511 in_progress 거부 (2026-11-02)

- DEBT#511 등록 작업이 스키마 정규값 `in_progress`를 사용하자 게이트가
  `status: invalid` finding을 만들었다. 작업은 게이트의 3줄 enum 정렬을 시도했고,
  push-admissibility check(`check-repository-surface` → `bin/surface_guard`)가
  **reasonCode SURFACE_FORBIDDEN**(`tools/surface_guard.nim:258`)으로 이를 거부했다
  — `src/gate/**`는 **FROZEN**(policyVersion 91, BASE_SHA 바인딩)이기 때문이다.
- 해소: 게이트를 origin/main 원본으로 **바이트 동일 원복**(--no-verify 미사용)하고
  DEBT#511을 `open`으로 재등록(커밋 **2cd4977a0**, PR **#1173**). 커밋 메시지:
  "동결 게이트 enum이 in_progress를 거부하므로 open이 준수 정규값 — DEBT#510과
  동일 관례".
- 참고: DEBT#511 엔트리 자체는 이후 별도 정비에서 해소되어 현재는 closed/FIXED다.
  선례로서 의미를 갖는 것은 2026-11-02 등록 시점의 거부 사건 기록(2cd4977a0 커밋
  메시지, DEBT#512 description)이다.
- DEBT#512 자체도 같은 이유로 `status=open`으로 등록되었다. 레지스트리 description
  인용: "The only gate-compliant status for an unresolved entry is therefore open
  — in_progress, which the schema itself recommends for that state, is unusable."

### 2.4 DEBT#512 결합 해시 (contentHash 2종)

하나의 `contentHash` 필드는 하나의 아티팩트만 결합할 수 있어, DEBT#512는 양측을
다음과 같이 나눠 기록했다(본 문서가 독립 재계산으로 재검증함 — 동일값 확인):

| 대상 | 규칙 | 값 |
|---|---|---|
| `matchesStatus` 정준 본문 | spec §6 규칙 1 (선언 :60~본문 끝 :62, trim) | `sha256:6ad7558fadeb774b00c6f1d5910cbf5fd3a550784b080973eac2d3c42e901ed8` (= registry contentHash 필드값) |
| schema 측 `statusEnum` 블록 | spec §6 비절차 아티팩트 규칙 (`data/debt_schema.json:12-16`, 행 내용 trim) | `sha256:69e80b46fd97996b8b51ff132595f2a8404e0a8e180937cfa60e9294e29b14c2` (= registry description 기록값) |

### 2.5 표면 분류 (config/repository_surface.json, policyVersion 91)

BASE 정책(변경 PR 자신의 정책이 아닌) 기준 분류:

| 경로 | 분류 | 비고 |
|---|---|---|
| `src/gate/**` (debt_integrity_gate.nim 포함) | **FROZEN** | 검증 엔진 TCB; v51이 열거한 15 FROZEN 경계 중 하나 |
| `config/policy/**` | **FROZEN** | 정책 자체 변경도 아키텍트 승인 정책 PR 필요 |
| `data/debt_schema.json` | CONTROLLED | v40 등록("registry structure contract kind") |
| `docs/spec/debt_registry_schema.md` | CONTROLLED | v40 등록(spec kind) |

FROZEN 해제의 유일 경로는 인간 아키텍트 승인 정책 PR(FROZEN→CONTROLLED
재등록)이다 — v52–v91의 해당 재등록 전체가 인간 아키텍트 승인을 decision basis로
기록한다. 분류는 BASE 정책으로 판정되므로 PR이 자기 표면을 스스로 완화할 수
없다.

### 2.6 소비자 (consumers)

- `debt_engine --validate` — registry 구조를 `data/debt_schema.json`으로 검증한다
  (spec §9 Fact→Authority Map: "registry 구조 — field shapes/types/allowlist →
  `data/debt_schema.json`"). 단 entry-level `status` 정의 자체는 minLength 1에
  freeform 허용(`data/debt_schema.json:176-180`)이라, statusEnum 비매칭 값도
  `--validate`에서 거부되지 않는다 — statusEnum은 구조 강제가 아니라 "prefer"
  권고로 기술되어 있다.
- `debt_integrity_gate` — §2.2 참조.
- `docs/DEBT_REGISTRY.md`·`src/generated/debt_constants.nim` — `debt_engine`
  codegen projection(spec §9). status 어휘를 바꾸는 옵션은 이들 재생성을 수반한다.

## 3. 두 해석 (Two interpretations)

### (a) 의도된 2층 구분

**의미**: `statusEnum`은 부채 도메인의 **전체 생애주기 상태 공간**(무엇이 존재할
수 있는가)을, `matchesStatus`는 admission 단계가 레지스트리 진입에 허용하는
**하위 집합**(무엇이 등록될 수 있는가)을 표현한다. 두 집합이 다른 것은 결함이
아니라 층위 구분이다.

**결과**: 이 해석이 참이면 스키마 전용 2값(`accepted`, `in_progress`)은 admission
어휘 밖의 상태 표현이며, 거부되는 것이 의도된 동작이다. 다음 세 관측은 이 해석
아래에서도 사실로 남으며, "(a)가 참일 때 의도된 결과"로 기술되어야 한다:

1. 게이트 Step 3는 `accepted`를 의미적으로 소비한다 — admission 어휘에 없는 값을
   처리하는 분기가 동일 바이너리에 존재한다(§2.2).
2. `resolved`는 스키마·spec의 정준 status 목록 어디에도 없다(§2.1) — admission
   전용 종결 어휘가 스키마 계약 밖에 존재하는 형태가 된다.
3. remediation 진행 중 엔트리의 유일한 게이트 준수 status가 `open`이다(DEBT#510 /
   DEBT#511 / DEBT#512 관례, §2.3) — "진행 중"을 admission에서 표현하는 방법은
   `open`으로의 매핑뿐이다.

### (b) 실제 드리프트

**의미**: 두 목록은 동일 규범 집합(부채 status 어휘)의 두 표현이며, 독립 기원에서
분기했다. `matchesStatus`는 병합 이전 debt-ct-gate 시절의 독립 4값 목록으로,
`statusEnum`("Canonical lifecycle status")과의 정합 검증 없이 통합되었다.

**이 해석을 가리키는 관측** (판정이 아니라 사실 나열이다):

- 불일치가 **양방향 대칭**이다 — 스키마 전용 2값이 게이트에서 거부되고, 게이트
  전용 1값이 스키마에 부재하다(교집합 3/5).
- 게이트가 **자기 Step 3에서 소비하는 `accepted`를 자기 구조검증이 거부**한다
  (§2.2). 의도적 부분집합 설계라면 같은 파일 안에서 양쪽을 일치시켰을 개연성이
  높다 — 다만 이것은 설계 의도에 대한 추론이지 관측 자체는 아니다.
- 스키마 정규값을 따라 쓴 기여자가 실제 게이트 실패집합 delta를 만들었다(§2.3) —
  "스키마의 권고를 따르면 게이트 판정이 어긋난다"는 관계가 실측되었다.

### 3.1 5번째 값의 정체

`statusEnum` 리터럴 순서의 5번째 값은 **`in_progress`**다. (스키마 전용값은
`accepted`와 `in_progress` 2값이다.) 의미: remediation이 진행 중이며 아직 종결되지
않은 상태. 스키마는 이 값을 "Canonical lifecycle status"로 권고하고 spec §3도 같은
값을 나열한다.

admission 맥락에서의 현재 실측 동작: `in_progress`는 `matchesStatus` 비매칭 →
`status: invalid` finding → 실패집합 delta(§2.2–2.3). 따라서 "이 값이 admission에서
허용돼야 하는가 거부돼야 하는가"가 이 문서의 질의 그 자체다:

- **(a)가 참**이면 `in_progress`의 admission 거부가 의도이며, "진행 중 엔트리는
  `open`으로 등록한다"는 매핑이 계약의 명시적 부분이 된다.
- **(b)가 참**이면 `in_progress`는 admission에서 허용되도록 어휘가 정렬되어야
  하며, 정렬 방향(어느 표면이 이동하는가)은 하위 결정이다.

## 4. 해석별 파생 요구사항 (Derived requirements)

### (a)가 참일 때

- 2층 관계(생애주기 전체 공간 vs admission 부분집합)와 admission 매핑("진행 중
  엔트리는 `open`으로 등록", "`accepted`는 admission 어휘 밖")이 계약 문서
  (`docs/spec/debt_registry_schema.md`)에 명시되어야 한다 — 현재 spec은 두 집합의
  관계를 기술하지 않는다.
- 스키마·게이트 **코드 변경은 불필요**하다 — FROZEN 표면 이동이 없다.
- DEBT#512는 "의도된 설계" 판정과 문서화 리메디에이션으로 종결할 수 있다.
- 남는 것: 게이트 내부 `accepted` 이중 취급(구조검증 거부 + Step 3 소비)과
  `resolved`의 비정준 지위가 "의도"로 확정된다 — 계약 문서가 이 둘을 명시적으로
  정당화해야 하며, 그 정당화 없이는 (a) 판정 후에도 같은 질문이 재발한다.

### (b)가 참일 때

- 정렬 변경이 필요하며, 방향은 하위 결정이다:
  - **게이트→스키마 정렬**: `src/gate/**` FROZEN(policyVersion 91) 해제가 선행한다
    — 아키텍트 승인 정책 PR(FROZEN→CONTROLLED 재등록, v52–v91 선례) 후 소비 PR이
    이어지는 2단계 절차.
  - **스키마→게이트 정렬**: `data/debt_schema.json`·`docs/spec/debt_registry_schema.md`는
    CONTROLLED라 일반 PR로 편집 가능하나, `debt_engine` codegen projection
    재생성(`docs/DEBT_REGISTRY.md`·`src/generated/debt_constants.nim`)과 기존
    엔트리 status 값들의 소급 정합성 검토가 수반된다.
- 어느 방향이든 DEBT#512는 판정 + 정렬 PR로 종결된다. 정렬 전까지 레지스트리
  등록 관행(미해결 엔트리 `open`)은 유지된다.

## 5. 결정 옵션 (Options)

**권고 없음 — 아키텍트 판정 대기.** 아래 옵션들은 이 문서가 제시하는 선택지며,
조합·변형 선택도 아키텍트 권한이다.

### 옵션 1 — 2층 의미 선언 ((a) 채택, 문서만 변경)

`docs/spec/debt_registry_schema.md`(및 필요 시 `data/debt_schema.json` `$comment`)
에 statusEnum(생애주기 전체)과 admission 어휘(matchesStatus 부분집합)의 관계와
매핑을 명시한다.

- **장점**: FROZEN 표면 이동 없음; 최소 변경; 단일 PR로 즉시 실행 가능.
- **단점/비용**: 게이트 코드의 `accepted` 이중 취급과 `resolved` 비정준 지위를
  코드가 아닌 문서가 정당화하는 구조가 된다; `matchesStatus` 자체는 그대로라 게이트
  findings의 현행 상태도 유지된다.

### 옵션 2 — 게이트를 스키마에 정렬 ((b) 채택, 스키마가 정규)

아키텍트 승인 정책 PR로 `src/gate/runners/debt_integrity_gate.nim`을
FROZEN→CONTROLLED 재등록한 뒤, 소비 PR에서 `matchesStatus`를 statusEnum 5값에
정렬한다(`resolved`의 처리 — 유지·제거·스키마 편입 — 는 동일 결정 내에서
정해진다).

- **장점**: 집행 지점에서 드리프트가 종료된다; "스키마 권고 준수 → 게이트
  실패집합 delta"라는 실측 피해(§2.3)의 근본 제거.
- **단점/비용**: 검증 엔진 TCB(`src/gate/**`) 이동 — 정책 버전 상승, 2단계 절차,
  높은 검증 비용; 경로 자체는 v52–v91 선례로 확립돼 있으나 전부 인간 아키텍트
  승인을 요구한다.

### 옵션 3 — 스키마를 게이트에 정렬 ((b) 채택, 게이트가 정규)

`data/debt_schema.json`의 `statusEnum`을 admission 어휘(`open`/`closed`/
`deferred`/`resolved`)와 일치시키거나, statusEnum의 지위를 재정의해 두 소비자의
어휘를 동일하게 만든다(`in_progress`·`accepted`의 어휘상 지위 재결정 포함).

- **장점**: FROZEN 코드 이동 없음(두 파일 모두 CONTROLLED); 단일 PR 가능성.
- **단점/비용**: `in_progress` 생애주기 표현의 상실(또는 별도 표현 정의 필요) —
  DEBT#506/507/511 이래의 `UNRESOLVED` + 진행 중 표기 관행과, 동결 게이트 회피용
  `status=open` 등록 관례(DEBT#510/511/512)의 재검토를 수반한다; codegen projection
  재생성이 필요하다; "Canonical" 명칭을 admission 4값에 부여할 근거가 문서화되어야
  한다.

## 6. 결정 권한·절차 (Decision authority and procedure)

- **판정 권한**: 인간 아키텍트 전용. 이 문서는 결정을 대리하지 않는다. 본 문서의
  PR은 파일 1건(본 문서)만 추가하며 코드·config·레지스트리·게이트를 일절 수정하지
  않는다.
- **근거**: `src/gate/**`·`config/policy/**`는 FROZEN이고 해제의 유일 경로는 인간
  아키텍트 승인 정책 PR이다(v52–v91 전 선례); AGENTS.md §0.10 결정 바인딩 — 변경은
  커밋된 결정에 구속되며 waiver 없는 우회가 금지된다.
- **절차 (제안 — 구속력 없음)**: 아키텍트가 (a)/(b) 판정과 옵션(또는 그 조합·변형)
  을 지정한다 → 본 ADR의 Status를 "Accepted (날짜, 판정 내용)"으로 갱신하거나
  후속 ADR에서 확정한다 → 지정된 옵션의 파생 요구사항(§4)이 실행 경로가 된다.
- DEBT#512는 결정이 레지스트리에 반영될 때까지 `status=open`의 정식 추적
  엔트리로 유지된다.

## References

- DEBT#512 — `data/debt_registry.json` (등록 PR #1180, merge cfd685ccb)
- DEBT#511 거부 선례 — 커밋 2cd4977a0, PR #1173
- `src/gate/runners/debt_integrity_gate.nim` :60-62, :107-122, :234-238, :263-265, :303-305
- `data/debt_schema.json` :12-16, :176-180
- `docs/spec/debt_registry_schema.md` §3, §5, §6, §9
- `config/repository_surface.json` (policyVersion 91 — `src/gate/**` FROZEN;
  `data/debt_schema.json`·`docs/spec/debt_registry_schema.md` CONTROLLED)
- `tools/surface_guard.nim:258` (SURFACE_FORBIDDEN)
