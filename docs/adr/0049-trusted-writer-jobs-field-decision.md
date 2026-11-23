# ADR-0049: `TrustedWriterSet`의 per-job authority 차원 — `trustedWriterJobs` 필드 수용 결정 (DEBT#557)

## Status

**Accepted — 옵션 2 (필드 수용 + 빈 집합) 채택 (2026-11-23)**

- **일시·권한**: 2026-11-23 — 저장소의 단독 아키텍트(`wintrover` —
  `@Archright/architect` 단독 멤버)가 **현 세션에서 본 결정 기록 작업 전반에 부여한
  포괄 승인**을 결정 근거로 기록한다. 이 승인은 세션 단위 포괄 승인이지 서명·날인된
  문서가 아니다 — 본 기록은 서명 아티팩트를 주장하지 않고, 독립적인 두 번째 승인자나
  위원회를 주장하지 않는다(§0.9 honest-executor; 같은 기록 관행:
  `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md:21`).
- **결정 내용·효과**:
  1. **옵션 2 채택** — `config/trusted_writer_set.json`은 `trustedWriterJobs` 필드를
     **가질 수 있다**. 본 결정이 수용하는 값은 **빈 배열**이며, 어떤 job도 job 단위
     writer 권한을 받지 않는다(§3.2).
  2. **옵션 1(필드 + 명명 집합)은 본 ADR에서 채택하지 않는다** — 기각이 아니라
     **이연**이다. 사유는 §3.1.
  3. **옵션 3(wontfix)을 채택하지 않는다** — 사유는 §3.3.
  4. **DEBT#557은 Open으로 유지**된다 — 본 문서는 `docs/DEBT_REGISTRY.md:139`와
     `data/debt_registry.json`을 수정하지 않는다.
- **경계 불변**: 본 문서는 필드를 **추가하지 않는다**. 오늘 이 파일은
  `trustedWriterWorkflow`(`:40`)와 `trustedAdmissionWorkflowSha`(`:41`) 두 필드만
  가지며 `trustedWriterJobs`는 부재다(실측: §2.1). 본 ADR 착지 후에도 부재다 — 추가는
  §0.1의 1번이다. R3는 계속 dormant다(`tools/ci/trusted_writer_set_gate.nim:334`).
  본 문서 작성 PR은 `docs/adr/**` 1파일 추가이며, 그 경로는 trustSurface 39항목·18경로
  manifest·891항목 closure 어디에도 없고 `src/cli/merge_cli.nim:1036`의 회전
  allowlist(`RotationAdrGlob`, `:228`)로 허용되므로 일반 lane이다.

## 0. 추적 (Tracking)

- **이슈 #385** — 본 결정의 정식 추적 이슈(Open). 본 문서는 이슈를 닫지 않는다.
- **DEBT#557** — `docs/DEBT_REGISTRY.md:139` (High,
  `Theater/Trusted-Writer-Set`, **Open**). 결정 대기 상태의 정식 추적 엔트리이며,
  본 문서는 레지스트리를 수정하지 않는다.
- **결정 쌍**: 본 문서는 ADR-0048(`certificate-mint.yml`의 다음 content 승인 여부)와
  같은 세션의 결정 쌍이다 — 두 대상 모두 18경로 manifest의 구성원이므로 실행 레인
  형태가 같다.
- 측정 기준: origin/main **5b14bbfc** (2026-11-23). 아래 사실 중 §2.6의 관측 집합은
  같은 트리에서 `tools/ci/trusted_writer_set_gate.nim`을 실행해 얻은 **실측 출력**이다.
  본 문서 작성 PR은 파일 1건(본 문서)만 추가한다.

### 0.1 미실행 실행 단계 (전수)

이 표가 이슈 #385를 작업 손실 없이 닫을 수 있게 하는 tracker다. **아래 단계 중
실행된 것은 하나도 없다.**

| # | 미실행 실행 단계 | 변경되는 아티팩트 | 레인 |
|---|---|---|---|
| 1 | **`trustedWriterJobs: []` 필드 수용** — 빈 배열. `pathSetDigest`(`:48`)는 불변 | `config/trusted_writer_set.json` (`:40-41` 뒤 필드 추가) | **break-glass + epoch rotation** |
| 2 | **App accepted schema 확장** — `tws_new_field` 거부 해소 | out-of-tree App(`axiom-admission-verifier`, 5795152) accepted schema — 저장소 파일 아님 | **App 소유자** (ADM-01: 소유자 UNKNOWN — 지정이 선행) |
| 3 | **ADR-0042 사실 클래스 표에 세 번째 클래스 append** — `trustedWriterJobs`는 앵커도 `pathSetDigest`도 value closure도 아니다. before/after 인용, 본문 재작성 금지 | `docs/adr/0042-trust-epoch-closure-split.md` | 일반 PR (docs/adr allowlist, `merge_cli.nim:1036`) |
| 4 | **R3 활성화 결정 — job 단위 권한의 실제 부여.** 명명 집합은 관측 집합과 정확히 같아야 하므로(⊆∧⊇), 부여 시점의 관측 3건이 그대로 고정된다: `.github/workflows/admission-gate-v2.yml#mint-prepare`, `#mint-publish`, `.github/workflows/certificate-mint.yml#publish` | `config/trusted_writer_set.json` | **별도 break-glass + 별도 권한 결정** |
| 5 | **#301 재개** — rebase(debt counters 충돌), 새 preflight, 새 landing-venue run | PR #301 | 스키마 장벽 해소 후 일반 lane |
| 6 | **DEBT#557 상태 갱신** | `docs/DEBT_REGISTRY.md:139` + `data/debt_registry.json` | 일반 PR |
| 7 | (선택) `.sh` 관측 범위를 job-level로 확장 — DEBT#557의 **원 결함** | `tools/ci/verify_trusted_writer_set.sh` (`:108-114`) | 일반 PR (repository_surface CONTROLLED, closure 0건) |

- **1번과 4번은 다른 결정이다.** 1번은 표현 슬롯을 만들고(권한 0건), 4번은 권한을
  부여한다. 1번의 빈 배열은 R3를 활성화하지 않으므로(`:334`) 1번만으로는 어떤 job도
  writer가 되지 않는다.
- **2번은 이 저장소 밖에서 완결된다.** 1번만 착지하면 in-tree gate는 통과하지만
  App은 여전히 `tws_new_field`로 거부한다 — 1번과 2번은 짝이다.
- **7번은 이 결정으로 닫히지 않는다.** 옵션 2는 `.sh`의 top-level-only 관측을 고치지
  않는다(§2.7). DEBT#557의 원 결함은 7번이 착지할 때까지 live다.

## 1. 질의 (Query)

`TrustedWriterSet`(`config/trusted_writer_set.json`)이 **job 단위 authority 차원**을
가질 수 있는가 — 가질 수 있다면 본 결정은 그 차원에 어떤 값을 수용하는가?

이 질의는 스키마 취향 문제가 아니다. 이 파일은 "어떤 CI job이 writer 권한으로 행동할
수 있는가"를 선언하는 문서이고(이슈 #385), job 단위 차원을 추가한다는 것은 **하나의
job을 신뢰 경계 안으로 들이는 일**이다. 구현자가 답할 수 없는 결정이다.

## 2. 관련 사실 (Facts)

### 2.1 필드 부재 — 실측

```
:40  "trustedWriterWorkflow": ".github/workflows/certificate-mint.yml",
:41  "trustedAdmissionWorkflowSha": "433be3c34c51cfc3fc6f8741009135cfa5906a03",
...
:48  "pathSetDigest": "axiom.trusted-checker-closure.path-set.v1:757310d4..."
```

- `trustedWriterJobs`는 **없다**. 파일의 마지막 키는 `pathSetDigest`(`:48`)다.
- 즉 현재 authority 차원은 **워크플로 단위 하나**뿐이다. job 단위로 "이 job은 써도
  된다"를 표현할 어휘가 없다.

### 2.2 R3는 이미 코딩돼 있다 — 그리고 그것이 break-glass라는 자기 선언

`tools/ci/trusted_writer_set_gate.nim:26-28`:

```
## R3 declared job set — when `config/trusted_writer_set.json` carries an
##    optional `trustedWriterJobs` array, the observed job-level writer set
##    must equal it exactly (⊆ ∧ ⊇). The field cannot be introduced by a PR:
##    the verifier rejects unknown TWS fields (`tws_new_field`) and the file is
##    blob-pinned in the trust-surface manifest, so R3 activating is itself an
##    audited break-glass event.
```

- 로더도 이미 있다 — `:370-371`: `if node.hasKey("trustedWriterJobs")`.
- 즉 in-tree gate는 필드에 대해 **관대**하다. 거부자는 out-of-tree App이다(§2.5).
- 그리고 이 주석이 결정의 성격을 스스로 규정한다: **R3 활성화 = audited break-glass
  event.** 본 ADR은 그 규정을 그대로 받는다.

### 2.3 활성 조건은 필드 존재가 아니라 원소 수다 (`:334`)

```nim
if declared.writerJobs.len > 0:
```

- **빈 배열은 R3를 활성화하지 않는다.** 이것이 옵션 2의 기계적 의미다 — 문서적 수사가
  아니라 코드 술어다. `trustedWriterJobs: []`는 로더에서 원소 0건으로 채워지고
  (`:370-373`), 판정에서 R3 분기를 타지 않는다.
- 결과: **빈 배열과 필드 부재는 게이트 판정상 구별되지 않는다.** 따라서 옵션 2의
  효력은 **App accepted schema 차원**에 있고 in-tree 판정 차원에는 없다. 이 구별을
  명시하지 않으면 옵션 2는 극장(§0.9)이 된다 — 본 문서는 그 구별을 §3.2와 §4에 남긴다.

### 2.4 R3 비활성 시 남는 강제 — 그리고 그 정직한 표기

- `--base`가 주어지면 R2 delta가 유지된다: base에 없던 job-level writer가 head에 있으면
  `tws_job_level_write_added:` (`:341-344`).
- `--base` 없이 R3도 없으면 **note만** 남는다 — `:345-348`:
  "job-level writers observed without a declared job set (absolute closure requires
  trustedWriterJobs; delta mode requires --base)".
- 즉 이 상태는 "절대 폐쇄가 없다"를 note로 **정직하게 기록**한다. 폐쇄를 주장하지
  않는다. 옵션 2는 이 상태를 유지한다.

### 2.5 App이 실제 거부자다 — 필드 도입 시도는 실재했다

- #301 verdict(이슈 #385 인용 원문):
  `trust_surface=FAIL — ... reasons=tws_new_field:trustedWriterJobs`.
- in-repo 측정 기록: `data/ci_optimization/ancestry_three_state_gate_2026-11-22/measurement.json:35`
  — `{ "pr": 301, "head": "356f2872...", "kind": "trust_surface=FAIL", "reasons":
  "tws_new_field:trustedWriterJobs" }`.
- 따라서 필드 도입은 가설이 아니라 **실제로 시도되어 스키마 차원에서 거부된** 사건이다.

### 2.6 관측된 job writer 3건 — 실측 (origin/main 5b14bbfc)

같은 트리에서 `tools/ci/trusted_writer_set_gate.nim`을 빌드해 실행한 출력:

```
observed job-level contents:write holders: 3
  .github/workflows/admission-gate-v2.yml#mint-prepare
  .github/workflows/admission-gate-v2.yml#mint-publish
  .github/workflows/certificate-mint.yml#publish
```

- 식별자 형식은 `jobWriterId` = `wf.path & "#" & job.name` (`:286-287`).
- 출처 site: `.github/workflows/admission-gate-v2.yml:535`(`mint-prepare`),
  `:592`(`mint-publish`), `.github/workflows/certificate-mint.yml:1282`(`publish`).
- 상속 실측: `effectiveContents`(`:275-281`)는 job 블록이 workflow 블록을 **대체**한다고
  규정한다. `certificate-mint.yml`은 top-level이 write(`:175-178`)이지만 `prepare` job이
  자기 블록에서 read로 대체하므로(`:206-209`) job writer는 1건만 나온다 — 상속만으로
  writer가 늘지 않는다는 실측이다.
- **기록 드리프트**: DEBT#557은 2026-11-17에 admission-gate-v2.yml 6건,
  `release-ship.yml` 2건, `dependabot-auto-merge.yml` 1건을 기록했다(`:139`). 오늘
  실측은 3건이다. 그 사이 tree가 변했다 — 명명 집합은 **측정 시점에 결속**되며, 과거
  기록을 그대로 옮겨 적으면 오늘 tree에서 `tws_declared_job_not_observed:`로 fail한다.

### 2.7 DEBT#557의 원 결함은 top-level-only 관측이다

- `.sh` verifier의 관측 코드는 column-0 `permissions:`만 수집한다 —
  `tools/ci/verify_trusted_writer_set.sh:108-114`의 awk는 `^permissions:`(column 0)로
  시작해 다음 column-0 키에서 끝난다. 같은 파일의 parser 주석(`:108-110`)이 "only the
  top-level permissions block counts"를 명시한다.
- 따라서 게이트는 `PASS`를 출력하면서 관측 집합을 `{certificate-mint.yml}`로 보고한다 —
  job-level grant는 **관측되지 않는다**. `:139`는 이것을 "a masking claim"이라고
  기록한다.
- 이 결함은 옵션 2로 고쳐지지 않는다(§3.3, §0.1의 7번).

### 2.8 보호 표면

| 목록 | `config/trusted_writer_set.json` |
|---|---|
| `config/policy/trust_surface_manifest.json` (18경로) | **`:22`** |
| `config/policy/merge_admission.json` trustSurface (39항목) | **`:87`** (index 8) |
| `config/trusted_checker_closure.json` (891항목) | 0건 |

### 2.9 ADR-0042의 사실 클래스 — 2분류가 불완전해진다

`docs/adr/0042-trust-epoch-closure-split.md:28-33`은 이 문서의 사실을 두 클래스로
나눈다: **anchors**(`trustedWriterWorkflow`, `trustedAdmissionWorkflowSha`) +
`pathSetDigest`는 "epoch rotation only", **mutable derived closure**는 value re-anchor.

`trustedWriterJobs`는 **어느 쪽도 아니다** — 앵커도 아니고, `pathSetDigest`가 요약하는
path-set도 아니고, value closure도 아니다. 세 번째 클래스다. 따라서 실행 시 ADR-0042의
표는 불완전해지며, 그 보정은 append-only amendment로만 가능하다(§0.1의 3번; 형식 선례
ADR-0025 Amendment A2 `docs/adr/0025-gateway-landing-authority.md:417`, Amendment E
`:769` — before/after 인용, 본문 재작성 금지).

## 3. 옵션 (Options)

### 3.1 옵션 1 — 필드 + 명명 집합 (본 ADR에서 채택하지 않음 / 이연)

- **가능성은 있다.** R3는 이미 코딩돼 있고(`:26-28`), App 확장은 정책 행위다.
- **그러나 지금 명명하면 권한을 새로 부여한다.** 명명 집합은 관측 집합과 **정확히
  같아야** 한다(⊆∧⊇, `:26-27`). 오늘 관측은 3건이므로(§2.6), 지금 명명하는 것은 기존
  grant를 사후 승인하는 일이 아니라 **job 단위 권한을 처음으로 선언**하는 일이다.
  "누가 job 단위 writer 권한을 갖는가"는 이슈 #385가 명시적으로 아키텍트에게 올린
  질문이며, 본 ADR은 그 답을 지금 확정하지 않는다.
- **그 결정에 필요한 근거가 없다.** 각 job이 왜 writer여야 하는가는 어디에도 기록돼
  있지 않다. `:139`가 기록하는 것은 오히려 "관측된 grant가 선언되지 않았다"이다.
- **과거 기록으로 명명하면 fail한다.** §2.6의 드리프트 때문에 11-17의 9건을 옮겨 적으면
  오늘 tree에서 `tws_declared_job_not_observed:`가 발생한다.
- 따라서 이 옵션은 **더 큰 결정**이며, 지금 결정할 근거가 없다. §0.1의 4번으로 이연한다.
  기각이 아니다 — 사용 가능한 상태로 남는다.

### 3.2 옵션 2 — 필드 + 빈 집합 (채택)

- **권한 부여 0건이 코드 술어로 보장된다.** 빈 배열은 R3를 활성화하지 않는다
  (`:334` — `len > 0`). 어떤 job도 새 권한을 얻지 않는다. "grant 없는 메커니즘"이
  수사가 아니라 술어라는 점이 이 옵션의 핵심이다.
- **표현 슬롯을 산다.** 필드가 App accepted schema에 존재하게 되면 `tws_new_field`
  거부가 해소되고, 후속 명명 집합 PR(§0.1의 4번)이 스키마 장벽에 막히지 않는다.
  즉 옵션 2는 **미래 결정의 비용을 낮추고 현재 권한은 0으로 유지**한다.
- **잔여 강제는 사라지지 않는다.** R2 delta(`:341-344`)가 base 대비 신규 job-level
  writer 추가를 계속 거부하고, 절대 폐쇄 부재는 note로 기록된다(`:345-348`). 빈 집합은
  "폐쇄됨"을 주장하지 않는다 — 이 정직성이 §0.9의 극장 금지와 충돌하지 않는 이유다.
- **정직한 한계 (두 가지)**:
  1. 빈 배열과 부재는 게이트 판정상 동일하다(`:334`). 옵션 2가 사는 것은 **표현
     슬롯**이지 강제력이 아니다.
  2. 따라서 **DEBT#557은 옵션 2로 닫히지 않는다** — `.sh`의 top-level-only 관측
     결함(§2.7)은 그대로다. 옵션 2를 "job-level closure가 이제 강제된다"로 인용하면
     그것이 극장이다. 본 문서는 그 인용을 금지한다.
- **블롭 변경 비용**: 필드 수용은 이 파일의 bytes를 바꾸므로 App-protected 경로
  변경이다(`:22`) → break-glass + epoch rotation(`trust_surface_manifest.json:3`).
  `pathSetDigest`(`:48`)는 path-set 기준이므로 필드 추가로 변하지 않는다 — 이 구별을
  회전 기록에 명시해야 한다(ADR-0042의 값/경로 구분, `:109-111`).

### 3.3 옵션 3 — wontfix (채택하지 않음)

- `:139`의 원 결함은 `.sh`가 top-level 블록만 관측한다는 것이다. **옵션 2도 그것을
  고치지 않는다** — `.sh`는 여전히 column-0 `permissions:`만 본다(`:108-114`).
- **그럼에도 wontfix를 택하지 않는 이유**: 옵션 3은 "job-level writer authority는 범위
  밖"을 선언하고 `trustedWriterJobs`가 tree에 나타나서는 안 된다고 못박는다(이슈 #385
  옵션 3). 그러나 관측된 3건은 **실재하는 grant**다 — `:345-348`이 말하는 것은 "없다"가
  아니라 "**선언 없이 관측됐다**"이다. 실재하는 것을 어휘에서 지우는 wontfix는 측정된
  사실과 어긋난다.
- wontfix를 택하면 DEBT#557은 "mechanism was rejected"로 재등록되어야 한다(이슈 #385).
  그 재등록은 별도 결정이며 본 ADR은 하지 않는다.

## 4. 결정 (Decision)

**결정(한 문장)**: `TrustedWriterSet`은 `trustedWriterJobs` 필드를 **가질 수 있다** —
단 본 결정이 수용하는 값은 **빈 배열**이고, 어떤 job도 job 단위 writer 권한을 얻지
않으며, R3는 활성화되지 않는다(`:334`).

### 결과 (Consequences)

1. **DEBT#557은 Open으로 남는다.** 옵션 2는 `.sh`의 top-level-only 관측 결함(§2.7)을
   고치지 않는다. 상태 갱신은 §0.1의 6번이다.
2. **R3는 dormant로 유지된다.** 활성 조건은 `len > 0`이므로 빈 배열은 무해하지만
   **무효과**다. 이 무효과는 결함이 아니라 본 결정의 내용이다 — 권한 부여 0건.
3. **옵션 2의 효력은 App accepted schema에 있다.** in-tree 판정은 변하지 않는다.
   따라서 필드 수용과 App 확장(§0.1의 2번)은 짝이며, 하나만으로는 #301류의 거부가
   해소되지 않는다.
4. **필드 수용은 blob 변경이다** → break-glass + epoch rotation. `pathSetDigest`(`:48`)는
   변하지 않는다 — 이 구별을 회전 기록에 명시해야 한다(ADR-0042의 값/경로 구분,
   `:109-111`).
5. **ADR-0042의 2분류 표가 불완전해진다.** `trustedWriterJobs`는 앵커도 value closure도
   아니다 — append-only amendment가 실행 시 필요하다(§0.1의 3번). 형식 선례는 ADR-0025
   Amendment A2(`:417`)·E(`:769`)다.
6. **job 단위 권한의 실제 부여는 여전히 미결이다.** 옵션 1은 이연됐고(§3.1), 그 결정
   없이는 어떤 job도 새 권한을 갖지 않는다 — 본 ADR은 권한을 **하나도** 만들지 않는다.
7. **App accepted schema는 out-of-tree이며 소유자 UNKNOWN(ADM-01)** — 필드 수용의
   절반은 이 저장소 밖에서 완결된다(`docs/evidence/trust_surface_ratification_366_2026-11-23.md:78-79`).

## 5. 결정 권한·절차 (Decision authority and procedure)

- **판정 권한**: 저장소 단독 아키텍트. 본 문서는 그 승인의 기록이며 결정을 대리하지
  않는다.
- **근거**: AGENTS.md §0.10 결정 바인딩; §0.9 극장 금지(빈 집합을 "폐쇄됨"으로 인용하는
  것을 금지하는 근거); `tools/ci/trusted_writer_set_gate.nim:26-30`(R3 활성화 =
  audited break-glass event — 결정의 성격을 게이트 자신이 규정한다);
  `config/policy/trust_surface_manifest.json:3`(break-glass + epoch rotation 요구).
- **절차**: 본 ADR 착지 → §0.1의 1·2(필드 수용 + App 확장) → 3(ADR-0042 amendment)
  → 5(#301 rebase) → 6(registry 갱신). 4번(R3 활성화)은 **별도 결정**이며 본 ADR의
  절차에 포함되지 않는다. **어느 단계도 본 ADR 착지에 포함되지 않는다.**
- **본 문서는 종결이 아니다**: DEBT#557은 Open, 필드는 부재, R3는 dormant, 이슈 #385는
  Open으로 남는다. 본 문서의 착지는 그 대기 상태의 정본화다.

## References

- 이슈 **#385** — "policy(authority): decide whether trustedWriterJobs may join
  TrustedWriterSet (DEBT#557)" (Open)
- DEBT#557 — `docs/DEBT_REGISTRY.md:139` (High, `Theater/Trusted-Writer-Set`, **Open**)
- `config/trusted_writer_set.json` — `:40`, `:41`, `:48` (`trustedWriterJobs` 부재)
- `tools/ci/trusted_writer_set_gate.nim` — `:26-28` (R3 계약·break-glass 자기 선언),
  `:275-281` (`effectiveContents`), `:286-287` (`jobWriterId`), `:334` (R3 활성 조건),
  `:341-344` (R2 delta), `:345-348` (절대 폐쇄 부재 note), `:370-371` (필드 로더)
- `tools/ci/verify_trusted_writer_set.sh` — `:108-114` (top-level-only 관측)
- `.github/workflows/admission-gate-v2.yml` — `:535`, `:592`
- `.github/workflows/certificate-mint.yml` — `:175-178` (top-level write), `:206-209`
  (`prepare` read 대체), `:1282` (`publish` job write)
- `config/policy/trust_surface_manifest.json` — `:3`, `:22`
- `config/policy/merge_admission.json` — `:87` (trustSurface index 8, 39항목)
- `data/ci_optimization/ancestry_three_state_gate_2026-11-22/measurement.json:35`
  (#301 `tws_new_field:trustedWriterJobs` 실측)
- ADR-0042 — `docs/adr/0042-trust-epoch-closure-split.md:28-33`, `:109-111`
- ADR-0025 — `docs/adr/0025-gateway-landing-authority.md:417` (Amendment A2),
  `:769` (Amendment E) — append-only amendment 형식 선례
- ADR-0048 — `docs/adr/0048-certificate-mint-next-content-decision.md` (결정 쌍)
- ADM-01 / App 집행 집합 — `docs/evidence/trust_surface_ratification_366_2026-11-23.md`
  `:40-43`, `:70-79`