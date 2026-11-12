# CI Epoch Cutover Protocol (절차 — 정본: AGENTS.md §2.5)

AGENTS.md + docs/agents/는 하나의 논리적 SSOT이다. 헌법 surface(사실·불변식·canonical location)는 AGENTS.md가 정의하고, docs/agents는 operational protocol만 담는다 — 규칙의 정본은 AGENTS.md, 실행 방법의 정본은 각 프로토콜 문서다.

> **정본: AGENTS.md §2.5.** live 실행 경계의 in-place patch 금지와, 변경이 일관된 세대 전환(epoch cutover)으로 착지해야 한다는 헌법 불변식은 **AGENTS.md §2.5**가 정의한다. 이 문서는 그 착지를 수행하는 10단계 절차·CI 변경 범위 정의·판정 기준만 담으며, 불변식을 재정의하거나 변경하지 않는다.

#### 용어 구분 — `ciGeneration` ≠ `executionEpoch`

"epoch"은 **서로 다른 세 가지**를 가리킨다. 이 프로토콜은 첫 번째만 다룬다.

| 용어 | 정체 | 정의 |
|---|---|---|
| **`ciGeneration`** | **이 문서가 다루는 것** — `.github/workflows/` 토폴로지 세대 | `AGENTS.md` §2.5의 freeze → record → tombstone → new generation → atomic binding update |
| `executionEpoch` | reuse 검증의 의미론적 세대 | `validatedAtEpoch == ctx.currentEpoch`, `currentEpoch = sha256(toolchainIdentity \| executionConfigDigest \| executionBundleFingerprint)` |
| queue-journal epoch | merge queue 저널 세대 | ADR-0020 D7, `data/merge_queue/` |

정본 정의: `docs/spec/execution_accounting_contract.md` §15.4 (`executionEpoch` vs `ciGeneration` — 표 + wire 필드 안정성 단서 포함), `docs/spec/merge_admission_controller.md` §2b (3종 구분).

> **절대 금지**: `ciGeneration` 값은 **캐시 키·reuse record·verdict identity에 어떤 형태로도 결속되어서는 안 된다.** CI 세대 전환이 reuse 판정을 바꾸면 §2.5의 목적이 정면으로 위반된다. 정적 집행 위치는 `docs/spec/verification_dag_contract.md` §3·§12.

> 본 프로토콜의 **이름**(`CI Epoch Cutover`)은 `AGENTS.md` §2.5가 §-1 불변이므로 변경하지 않는다. 위 표는 본문 용어의 정밀화를 위한 것이며 프로토콜 이름 변경이 아니다.

## §2.5 CI Self-Bootstrap Bottleneck — 실행 프로토콜

Axiom CI 자체를 변경·최적화하는 작업이 기존 CI의 전체 실행·검증 경로에 종속되어, 기존 CI의 latency와 복잡성이 CI 자체의 개선 속도를 제한하는 현상을 **CI Self-Bootstrap Bottleneck**이라 한다.

#### Mandatory CI Epoch Cutover

**모든 CI 변경은 변경 규모와 무관하게 CI Epoch Cutover protocol을 따른다.** (정본: AGENTS.md §2.5)

다음 변경은 모두 CI 변경으로 간주한다.

* CI workflow 파일 변경
* CI job 또는 execution topology 변경
* CI authority / required-check / source binding 변경
* CI artifact dependency 변경
* CI cache / runner / execution environment 변경
* CI 실행 순서, parallelism, concurrency 또는 selection logic 변경
* CI를 검증하거나 CI의 trust boundary에 영향을 주는 스크립트·설정 변경

**활성 CI에 대한 in-place patch 금지와 그 예외 조건은 헌법 불변식이다 — 정본: AGENTS.md §2.5.**
이 문서는 그 조건 아래에서 epoch cutover를 수행하는 절차만 정의한다.

#### CI Epoch Cutover Protocol

CI 변경을 수행할 때 에이전트는 다음 순서를 기본 절차로 사용한다.

1. **Freeze**
   현재 active CI의 정확한 revision을 immutable Git tag 또는 동등한 immutable reference로 고정한다.

2. **Record**
   frozen epoch의 workflow/source SHA, trusted source binding, 주요 artifact/authority binding을 기록한다.

3. **Tombstone**
   폐기되는 CI 구현을 명시적으로 종료되었음을 나타내는 tombstone으로 기록한다.
   Tombstone은 required-check 우회, trust gate 비활성화, authority 제거 또는 검증 면제를 의미하지 않는다.

4. **New Epoch**
   frozen CI를 기준으로 새로운 CI 구현을 별도 epoch로 구성한다.

5. **Atomic Binding Update**
   workflow 변경과 trusted source identity, SHA pin, digest 또는 이에 준하는 trust binding 변경은 하나의 논리적 cutover 단위로 결속한다. 일부만 갱신된 상태를 허용하지 않는다.

6. **Local / Targeted Verification**
   기존 CI 전체를 먼저 반복 실행하지 않는다. local contract, load-bearing invariant 및 필요한 targeted mutation proof를 우선 수행한다.

7. **Short Validation**
   새 CI의 실제 execution path를 최소 필요한 범위에서 검증한다.

8. **Canonical Cutover**
   검증된 새 epoch를 canonical CI execution path에 적용한다. required-check identity와 trust semantics가 의도치 않게 사라지거나 변경되지 않았음을 확인한다.

9. **Production Acceptance**
   최종적으로 실제 landing 1건으로 GitHub platform semantics, authority boundary 및 continuity를 검증한다.

10. **Rollback**
    새 epoch에 결함이 발견되면 frozen previous epoch를 명시적인 rollback reference로 사용한다.

#### 판정 기준 (Mandatory Invariants)

> 헌법 불변식 — 활성 실행 경계의 in-place patch 금지, 그리고 workflow·trusted source identity·pin/digest가 결합된 변경이 하나의 논리적 세대 전환으로 착지해야 한다는 조건 — 은 **정본: AGENTS.md §2.5**. 아래는 이 프로토콜의 절차적 판정 기준이며(결합의 실행 경로는 절차 5 Atomic Binding Update다), 헌법 불변식을 재진술하지 않는다.

* **기존 active CI의 전체 실행을 새 CI 변경의 선행조건으로 요구하지 않는다.**
* CI 개선 작업이 기존 CI의 latency를 반복적으로 지불하도록 만들지 않는다.
* Frozen epoch는 삭제하지 않고 재현 가능한 immutable baseline으로 보존한다.
* Trust semantics와 execution adapter 변경을 구분한다.
* 이 외의 헌법 수준 불변식(tombstone 권한, correctness 가정, 불변식 무효화 판정, rollback 불가 시 영구 제거)은 **정본: AGENTS.md §2.5**다 — 본 절은 재진술하지 않는다.

#### Agent Default Behavior

**CI 변경 요청을 받으면 에이전트는 먼저 현재 CI를 frozen epoch로 고정한 뒤 새 epoch를 구성해야 한다.**

즉 기본 동작은 다음과 같다.

```text
CI change requested
        ↓
freeze/tag current epoch
        ↓
record + tombstone
        ↓
construct new epoch
        ↓
local/targeted verification
        ↓
short CI validation
        ↓
canonical cutover
        ↓
production acceptance
```

에이전트는 **"작은 변경이므로 그냥 현재 CI를 수정"**하는 판단을 독자적으로 내려서는 안 된다 — 정본: AGENTS.md §2.5.

#### Purpose

CI는 자기 자신의 개선 속도를 제한하는 권위자가 되어서는 안 된다.

Axiom은 **CI Self-Bootstrap Bottleneck을 제거하여, CI 자체를 변경하는 작업이 기존 CI의 latency와 복잡성에 반복적으로 종속되지 않도록 한다.**

CI의 신뢰성은 frozen baseline, 명시적 epoch cutover, load-bearing invariant 검증, 실제 production acceptance 및 rollback 가능성으로 유지한다.


<!-- Extracted from AGENTS.md §2.5 to keep AGENTS.md under the context-size threshold. -->
