# ADR-0023: GitHub determines runner demand; Hetzner adapter realizes demand; Axiom determines trust

> **Historical note (2026-09-20)**: 본 ADR은 2026-09-19 착지된 PR #143–#151
> (merge commits `12b135fb9` … `08f5c6222`)의 구조를 **정당화하는 결정
> 문서**다. 그 착지 당시의 게이트 부재는 `docs/ci/scale_set_authority_decision_2026-09-20.md`
> §2에서 historical fact로 기록되며, 본 ADR은 소급 승인이 아니라
> **현재·미래의 권위 경계**를 고정한다.
>
> 계류 상태: **ratified (2026-09-21, owner)** — Owner 결정 기록
> ([`docs/spec/repository_surface_contract.md`](../spec/repository_surface_contract.md)
> §Owner 결정 기록 #2·#5)과 2026-09-21 ADR 작성 승인으로 확정했다.
> 메커니즘 수단 절의 대체는 하기 **Amendment A1** 참조. ADR-0022
> ([`0022-admission-artifact-authority.md`](0022-admission-artifact-authority.md))
> 위에 설계된 admission/acceptance authority와 결합한다.

## Status

**ACCEPTED (2026-09-21, owner ratification).** Runner capacity의
**demand authority**를 GitHub에 위임하고, Axiom의 자체 demand-scaling policy를
제거한다. 이 ADR은 다음의 권위 경계를 확정한다. 메커니즘 수단 절(D2의 어댑터
의존, D3·D4의 X-ScaleSetMaxCapacity 계측)은 **Amendment A1(2026-09-21)**이
대체하며, 권위 경계(D1·D3 상한·D5)는 유지된다. 플릿 구현 코드의 착지는
CI 복구 시점이며, 본 ADR은 그 설계 확정만 고정한다.

## Context

- **Capacity 결정이 어디에 있어야 하는가**: GitHub Actions가 job queue의
  유일한 원천이다. Axiom이 queue cardinality를 추론하는 controller
  (D0의 A1 controller semantics, `decide`/`transition`)는 중복 authority다 —
  C3 ("controller does not need to know why a job is queued")의 철학을
  밀어붙이면 demand 자체도 Axiom이 알 필요가 없다.
- **착지된 현실 (PR #143–#151)**: GitHub Runner Scale Set
  (axiom-ci-scale canary/burst 워크플로) + Go scaleset-adapter
  (`tools/ci/scaleset-adapter/`, `github.com/actions/scaleset v0.4.0` pinned).
  Scale Set Client가 러너를 JIT 등록하고, adapter가 Hetzner VM을
  create/retire한다.
- **관측 방식 (B2 REST observation)**: adapter가 GitHub API를 통해
  `TotalAssignedJobs`를 읽고, `X-ScaleSetMaxCapacity` 헤더로 maxCapacity를
  광고한다 — 이 헤더가 demand 결정의 **유일한 통제 지점**이다.
- **정책 전방위**: D0 §2.1 A2 게이트(retention trigger ∧ A1 정적 미달 증명),
  retention-trigger defer, optimization N=3 봉인, entry contract §7
  Pool Controller defer가 모두 이 방향을 막고 있었으나, 배선 없이 착지가
  진행되었다 (historical fact). 본 ADR은 그 경계를 supersede한다.

## Decision

> **(2026-09-21)** D2의 어댑터 의존과 D3·D4의 수단 절은 하기
> **Amendment A1**이 대체했다. D1(demand=GitHub)·D2의 translation-only
> 원칙·D3의 상한값·D5(trust=Axiom)는 유효하다.

**D1. Demand authority = GitHub.**

GitHub이 `TotalAssignedJobs`로 수요를 결정한다. Axiom은 demand를 추정하지
않고, `advertised maxCapacity`(X-ScaleSetMaxCapacity)를 통해 GitHub이
scale set에 할당할 수 있는 상한만 광고한다. Axiom의 자체
demand-scaling policy(`decide`/`transition`)는 제거된다.

**D2. Realization authority = Hetzner adapter (translation-only).**

Hetzner adapter(`tools/ci/scaleset-adapter/`)는 GitHub의 demand를 VM
생성·폐기(create/retire)로 실현할 뿐, demand 판단(추정·예측·다운스케일
결정)을 하지 않는다. Scale Set Client(protocol + JIT lifecycle)는
`github.com/actions/scaleset` v0.4.0에 고정하고, `go.sum` 커밋.
`@latest` 사용 금지; preview 버전 갱신은 별도 검증 캠페인.

**D3. Capacity invariant (Model A).**

```
scale_set_capacity = 16
provider_available_capacity = project_quota − non_scale_set_consumption
provider_available_capacity ≥ scale_set_capacity
scale_set_owned_servers ≤ 16
advertised maxCapacity = 16
```

- 16은 axiom-ci Scale Set의 **EXCLUSIVE hard ceiling**.
- legacy 8-host pool = migration-only consumer; production routing cutover
  후 retired (retirement 전 `legacy assignment = 0` 실측).
- publisher 1 host = separate consumer, scale set 밖 상주 영구 유지.

**D4. Acceptance = convergence-based.**

VM 개수 == demand가 기준이 아니다. 기준: burst 1 (auto-supply → acquire →
ephemeral retirement), burst 16 (16 acquire, servers ≤ 16), burst 17
(GitHub assigns ≤16, ≥1 pending, servers ≤16, adapter가 17번째 create
시도 0), production workflows (admission_producer, canonical-main) GREEN
on scale set on canonical main, legacy assignment = 0 before deletion.

**D5. Axiom = trust / attestation / acceptance.**

Scale set이 생산한 실행의 신뢰·증명·수용 경계는 ADR-0022의
admission-artifact authority model과 결합해 Axiom이 소유한다. 이 ADR은
그 경계를 변경하지 않는다.

**D6. Supersedes.**

- D0 §2.1 A2 gate (`demand_driven_capacity_d0_decision_2026-09-08.md:41-47`) —
  효력 소멸, 역사 레코드로 유지.
- Controller retention trigger (`self_hosted_ci_migration.md:135-152`).
- optimization N=3 seal (`optimization-2026-09-08.md:92-93`) — 봉인 해제,
  변경은 새 campaign 승인 대상.
- entry contract §7 Pool Controller defer (`productization_entry_contract_v1.md:195`)
  — superseded-pending-ratification (Amendment Log 반영은 §8).
- Axiom demand-scaling policy (D0 §3 controller freeze) — 제거.

## Consequences

**긍정 (positive):**

- Authority 단순화: demand는 GitHub 하나, realization은 adapter 하나,
  trust는 Axiom 하나 — 중복 controller authority 제거로 극장·모순 소지 감소.
- Scale Set의 JIT lifecycle(토큰 1회성, 러너 일회성)이 보안 경계를
  강화한다 (기존 정적 2-host pool의 장수명 토큰/호스트 정리 부담 제거).
- burst 상한(16)이 **결정론적** — GitHub이 광고값을 존중하므로
  하드 캡이 프로토콜 수준에서 강제된다.

**부정 (negative):**

- Cloud-runner 운영이 GitHub Platform(Public Preview)에 의존 —
  프로토콜 변경·중단 위험은 pinned 버전 갱신 캠페인으로만 대응.
- Adapter(Go)는 기존 Nim 무접촉 원칙(§-1) 밖의 새 실행 경계 —
  binary 신뢰 경계는 배포 runbook으로 고정해야 한다.

**리스크 (risks):**

- **Quota 외부 게이트**: Hetzner project server limit — 상향(migration
  ≥25 / steady ≥17)은 Console/API 외부 권한이며, 지연 시 burst 16 실현 불가.
  fail-closed로 처리 (신규 create 금지).
- **Preview 의존**: `github.com/actions/scaleset` v0.4.0 — API 변화 시
  adapter 소스 수정 필요. @latest 금지로 묵시적 drift 차단.
- **정책 공백**: D0 freeze 해제로 Axiom controller semantics가 사라지는
  동안 legacy 8-host pool과의 경계(∃ non trivial)가 남는다 — cutover
  전 legacy assignment=0 실측을 선행 조건으로 명시.
- **ratification pending**: 본 ADR·결정 문서·Contract Amendment Log가
  architect ratification 전까지 PROPOSED — 운영값(maxCapacity=16 등)
  확정은 ratification과 함께.

## Amendment A1 (2026-09-21): 메커니즘 대체 — polling reconciler 플릿

> Owner 결정(`docs/spec/repository_surface_contract.md` §Owner 결정 기록 #2·#5)
> 와 2026-09-21 팩트 조사(Hetzner 과금 모델 공식 FAQ, GitHub 공식 actions
> 러너 문서)에 근거한다. D1(demand=GitHub)·D5(trust=Axiom)는 그대로 유지되며,
> D2의 어댑터 의존과 D3·D4의 수단 절만 대체된다. 구현 코드 착지는 CI 복구
> 시점이며, 본 amendment는 설계 확정만 고정한다.

### A1.1 과금 모델 팩트 (설계 전제)

Hetzner Cloud는 서버 **존재 기반 과금**이다 — 생성 완료된 서버는 power
state(running/off)와 무관하게 삭제까지 과금된다(공식 FAQ). 따라서 비용에
영향을 주는 유일한 수명주기 연산은 **create/delete**이며, power-off 기반
절약은 설계 공간에서 제외된다. 플릿은 탄력적 create/delete로만 운영하고,
idle 상시 비용은 0(스냅샷 보관료 제외)을 유지한다.

### A1.2 Trigger: Axiom 소유 30s 폴링 reconciler (D2 메커니즘 대체)

- 폐기: scaleset-adapter(Go, `github.com/actions/scaleset` v0.4.0) 의존
  제거 — runner pool과의 강결합이 어댑터 제거 시 전체 플릿 정지로 이어지는
  단일 실패 지점이었다(2026-09-20 관측). 어댑터 코드는 main에서 제거되었고
  tag `ci-frozen-2026-09`에 보존된다. D2의 **원칙**(realization은
  translation-only, demand 추정·예측 금지)은 유지한다.
- 채택: reconciler가 GitHub API로 라벨 매칭 큐 잡 수([self-hosted, linux,
  x64, axiom-verifier], runner group axiom-ci)를 30s 주기로 읽어
  `desired = max(queuedJobs, warmFloor=0)`를 결정하고 VM create/delete로
  실현한다.
- 선정 근거: 결정론(Axiom 소유 순수 결정 함수 — scale-v2 `decide.nim`
  선례, 10/10 테스트), Public Preview 프로토콜 의존 제거, dispatch 전용
  CI(owner POLICY) 하에서 PR 즉시성 불요.

### A1.3 수명주기 불변식 (D3 메커니즘 대체)

- `running VMs ≤ 16`(D3 상한 유지, config 값). quota 초과 시 fail-closed
  (신규 create 금지).
- **1 VM = 1 jitconfig** — 등록 수명 ≡ VM 수명. 703건 stale 등록 사고의
  재발 방지가 근거(구현 선례: `jit_supervisor.sh` / host userdata).
- **ghost unregistration (2026-09-22)**: 러너 등록은 동일 이름의 managed VM이
  owned 관측에 존재할 때만 supply로 계수된다(이름 정확 일치 조인 — VM이 없는
  등록은 공급이 되지 않음). managed 패턴 이름이며 동일 이름 VM이 없는 등록은
  reconciler가 GitHub `DELETE /actions/runners/{id}`로 해제한다. 해제는 세 관측
  모두 성공한 gated 경로에서만 실행 — 관측 실패(fail-closed)면 해제 금지,
  dry-run에서는 절대 실행하지 않는다. VM이 존재하는 러너와 관리 패턴 밖 이름은
  건드리지 않는다.
- **external-JIT-only** — 이미지에 장수명 토큰 금지. 부팅 시 registration
  token(TTL 1h)을 취득해 cloud-init jitconfig로 주입한다. `--ephemeral`
  러너(job 1회 후 자동 deregister), job 종료 후 VM delete.
  **전달 수 = 수명**.
- `warmFloor = 0` — 상시 예열 풀 없음(존재 기반 과금 하 상시 비용 0).

### A1.4a 권위 경계 (명문화 — Amendment A1)

```
GitHub            = demand authority (queued jobs) + 라너 수명주기 관측 (등록/자동 deregister/busy)
Axiom reconciler  = 용량 상한 16(D3) + 수명주기 정책(부팅 유예 5min, TTL 24h, 수요 소멸 회수) → desired state 결정
Hetzner           = 기계적 realization
mutation authority = 단일 control host의 axfleet 프로세스 (모든 실행 경로는 그 호스트의 flock 통과)
```

### A1.4 프로비저닝 원천

- 부트 원본: snapshot `axiom-runner-v4-hygiene-20260920`(id <snapshot-id>,
  2026-09-20 hygiene 완료본).
- 배치: <zone-1> + <zone-2> 다중 위치. 품절 시 위치 전환 재시도(cx23@<zone-1> 품절이
  2026-09-20 공급 중단의 직접 원인).

### A1.5 관측·수용 (D4 유지·적응)

- 공식 문서 Warning: ephemeral 러너 로그는 VM 삭제 전 수집 또는 외부 전송이
  필요하다 — 삭제 후 로그 소실은 결함이 아니라 계약으로 명시한다.
- 수용 기준: D4의 convergence 기준(큐 소화, 상한 준수, production workflow
  GREEN)을 재사용한다. 단 "advertised maxCapacity"
  (X-ScaleSetMaxCapacity) 절은 폐기하고, 상한은 reconciler config로
  강제한다.

### A1.6 현재 비용 상태 (2026-09-21)

- 서버 0, volume 0, floating IP 0. 스냅샷 4개(각 2.61GB, 합계 ≈€0.10/월)만
  존재한다. 구현 후에도 idle 시 동일 상태를 유지하는 것이 본 설계의 목표
  상태다.

### A1.7 공급 의미 정정 + 병렬 실현 (2026-09-22)

**(a) supply 의미 정의 (F1 — 결정론 pure decide).**

```
supply = owned ∩ [ (registered ∧ status=="online" ∧ ¬busy)
                   ∪ (unregistered ∧ ageSec < bootGraceSec) ]
```

- **busy 러너는 grace 내에 있어도 결코 supply가 아니다.** boot grace의
  의미는 "부팅 중 미등록" 보호로 한정된다. 등록되어 잡을 수행 중인 VM을
  grace로 공급 계수하면 잔여 수요가 있는데 creates=0으로 억제되는 꼬리가
  생긴다(2026-09-22 shard-9 실측: 12:41→12:47 starvation).
- **등록 ∧ offline은 supply가 아니다**(offline은 잡을 서빙할 수 없음).
- 미등록 ∧ age < bootGraceSec만 "부팅 중" 공급으로 계수된다.
- 결정론 불변: decide()는 순수 함수이며 입력(owned/liveRunners)을 이름
  정렬 후 평가하므로 동일 입력 → 동일 계획이 모든 규칙에서 유지된다.

**(b) rule ①b 신설 (dead-runner zombie 정리).**

```
①b: registered ∧ status=="offline" ∧ ageSec > bootGraceSec → delete
```

죽은 러너(offline 등록인데 동일 이름 managed VM이 존재, 부팅 유예 경과)의
VM은 TTL(24h)까지 기다리지 않고 부팅 유예 직후 회수된다. busy 러너는
**모든 삭제 규칙에서 전면 보호**(in-flight 잡 불변식은 ①b에도 그대로).

**(c) 병렬 실현 원칙 (F2 — 순수 decide / 병렬 실현 분리).**

- 결정(decide)과 실현(realize)은 분리된 계층이다. decide는 순수·결정론
  유지; 병렬성은 실현 세부일 뿐이며 **결정론 불변을 건드리지 않는다** —
  VM명은 발행 전 `generateNames`로 결정적으로 할당되고, 웨이브 내 동시
  기동·집계 순서는 결과에 영향을 주지 않는다.
- 실현 메커니즘: 스레드·async 없이 `startProcess` 기반 병렬 잡
  (K = defaultCeiling = 16 웨이브). credential은 기존 hcloud shell-out
  유지(신뢰 표면 무확장), mutation 단일 coordinator(flock) 불변식 유지.
- 위치 fallback(<zone-1> → <zone-2> → <zone-3>)은 워커당 기존 의미론 유지; worker별
  유니크 user-data 임시 파일로 동시 기동 간 충돌 방지. `soldOut` 관측 시
  다음 웨이브 미발행(직렬 시대 break 의미론 보존), `failed`는 errors 기록
  (최대 3개) 후 다음 틱이 deficit 재산정.

**(d) ceiling 산식 의도 명시.**

```
deficit = min(ceiling − |owned|, min(ceiling, demand) − supply), clamped ≥ 0
```

|owned|는 **삭제 예정분(같은 틱의 rule ①/①b/②/③ deletes)을 빼기 전** 값을
쓴다. 이는 의도된 올바른 동작이다 — 같은 틱에 삭제될 VM도 틱 시작 시점의
소유로 상한 산정에 포함되어, 삭제와 생성이 같은 틱에 공존하더라도
`running VMs ≤ ceiling`(D3 상한)이 틱 내 어느 시점에서도 위반되지 않는다.
(agent-40이 "동일틱 삭제 레이스"로 명명한 것은 이 의도된 동작이다.)

**(e) 관측성 정리 (F3).**

저널은 `supplyDecide`(결정 시점 supply = Plan.supply)와 `supply`(사후
투영 = owned − deletes + creates)를 **구분된 의미로 함께 기록**한다. 이
둘을 혼동한 것이 T4 오독 사례(2026-09-22)의 원인이다.

### A1.8 (2026-09-22): Path A — 워크플로 층 job 수요 축소 (K 다이얼, 통합 16→8) — 2026-09-22 일시 철회·동일일 재도입 ((e) 참조)

2026-09-22: K=8 일시 철회 — identity set 결함(실행 75~76/86, 중복 혼재) 확인. 원인 수리 및 실행 후 identity-set 게이트 부설 후 재도입 예정.

> Path A 승인("워크플로 층 비용 최적화")에 근거한다. A1.2의 demand
> authority(GitHub)와 A1.4a의 권위 경계, A1.3의 1VM=1job 불변을 **변경하지
> 않고**, 워크플로가 GitHub에 제출하는 **job 수요 자체**를 축소한다.
> 이 amendment는 신뢰 경계(D1 demand=GitHub, D5 trust=Axiom)를 건드리지
> 않는다.

**(a) 성격 — job 수요 축소 (Terminal Outcome).**

Terminal Outcome (승인 문구):

> billed 312h→≤192h(감소 ≥38%, 실측 A′ 38.5%), 지배 런 17→9 잡(−47%), identity set union=86/intersection=0, wall-clock은 기준선 초과 2런(35627687570: 1203s, 35647426568: 1266s — 현행 K=16에서 이미 15분 초과)을 제외한 전 런 ≤15분
>
> 사용자 TO 수정 승인 2026-09-22

성격: **"신뢰 경계를 바꾸어 VM 비용을 줄이는 것"이 아니라 "동일한 신뢰
경계에서 GitHub에 제출하는 job 수요 자체를 줄이는 것"**이다. GitHub에
제출되는 job cardinality가 줄어 demand authority(GitHub)의 큐가 축소되고,
reconciler의 0→N 자동 공급은 수요에 비례하므로 실현 VM 수도 동일 비율로
줄어든다.

**(b) K 다이얼 결정 — 통합 16→8 (K=8).**

- 결정 규칙: 사용자 지연 예산(CI wall-clock ≤15분)을 만족하는 범위에서
  billed server-hours를 최소화한다.
- 채택값: **K=8**. 잡 구조 ci-bootstrap 1 + gateway-shard 8 = **9 jobs**
  (기존 17 = 1 + 16 대비 **−47%**) — ≥38% 임계와 ≤15분 지연 예산을 동시에
  만족한다. K는 이 계약을 위반하는 방향으로 임의 변경하지 않는다.
- 구현: `.github/workflows/runner-pool-acceptance.yml`의 gateway-shard
  matrix(16 → 8)와 SHARD_COUNT(16 → 8)만 변경한다. 샤드 분할은 기존 SSOT
  (Makefile:gateway_shard_files, 결정론적 NR%n 배정)를 그대로 사용한다.
- 파티션 불변식: `make test-gateway-shard-audit SHARD_COUNT=8`이 각 레그에서
  fail-closed로 union=86 / intersection=0을 기계 검증한다(실행과 감사가 같은
  SSOT를 공유하므로 분기 불가).
- D3 상한(scale_set_capacity=16)과 D4 burst-16 수용 기준은 **변경 없음** —
  이 변경은 워크플로 job 수요 다이얼이지 풀 용량 상한 변경이 아니다.
  reconciler ceiling은 그대로 16이다.

**(c) A1.1 과금 서술 보완 — ceil(lifetime) 시간 과금 (정정).**

A1.1은 "서버 존재 기반 과금"으로 서술했다. 정확한 과금 단위는 **서버별
수명(create→delete)을 1시간 단위로 올림(ceil)한 시간**이다 — 공식 과금
FAQ가 partial hour의 올림 청구를 명시한다("We round up partial hours",
docs.hetzner.com Cloud 과금 FAQ). 즉:

- 존재 기간이 1시간 미만이어도 그 서버는 **1 billing hour**로 청구된다.
  power-off 절약이 설계 공간에서 제외된다는 A1.1의 결론은 이로써 강화된다
  (런당 shard VM 수명 ≪ 1h → 런당 VM = 1 billing hour).
- 단가(2026-09-22): CX23 **€0.0088/h** + Primary IPv4 **€0.0008/h** ≈
  **€0.0096/h**. 런당 billed server-hours ≈ 동시 VM 수가 성립하므로,
  job 수요 축소 17→9는 billed server-hours의 **−47% 감축**에 직결된다 —
  이것이 (b)의 K=8이 비용을 줄이는 기제다.

**(d) 신뢰 경계 불변 (명문화).**

- **1 VM = 1 job** 유지(A1.3). `--ephemeral` 러너 유지 — 영속 러너 재사용
  절대 금지.
- `decide.nim` / `userdata.nim` **일절 변경 없음** — 신뢰 경계 불변이 본
  계약의 핵심이다.
- 이번 변경 파일: `.github/workflows/runner-pool-acceptance.yml` + 본 ADR
  뿐이며, 러너 풀·수명주기·과금 경계 코드는 무변경이다.

**(e) K=8 재도입 사실 기록 (2026-09-27).**

일시 철회(`fa3d39e0f`, PR #188) 후 **동일일 `7d3a03a68`(2026-09-22,
PR #189 — "fix(ci-gateway): K=8 identity set defect")**이 identity-set 결함을
수리(감사/실행 경로 단일화 + 실행 후 identity-set 게이트 부설)하여 K=8을
재도입했다. 현행 main의 gateway-shard matrix는 static [0..7]
(`.github/workflows/runner-pool-acceptance.yml:424-425`)·`SHARD_COUNT=8`(:474)로
**K=8이 live 상태**다. A2의 A1.8 tombstone 행("K=8 재도입·통합 16→8은 Phase D
환경에서 재평가한다", 2026-09-23 작성)은 이 재도입 사실을 반영하지 못했으며,
Phase D(GHEC 전환 — `7606e0580`·`5c81ad69`) 착지 후에도 K=8이 유지되어
현행이다.

**(f) "POLICY 다이얼 금지" 의미 확정 (2026-09-27).**

`runner-pool-acceptance.yml:412`의 "matrix는 static [0..7]/K=8 유지
(ADR-0023 A1.8, **POLICY 다이얼 금지**)"에서 "POLICY 다이얼 금지"는 **K=8이
MUST 값이라는 뜻이 아니다** — K는 정책 다이얼(POLICY dial)이며, "금지"는 그 값을
임의·암묵적으로 돌리는 것을 금지한다는 뜻이다. 값의 변경은 decision-binding
경로(waiver 또는 ADR 개정 — ADR-0009, AGENTS.md §0.10 decision-binding
framework)를 통해서만 한다. 이는 D3=16의 "값은 정책으로 유지"(A2, A3)와 동일한
성격이다 — 값 자체가 불변(must)이 아니라 변경 절차가 봉인된 것이다.

## Amendment A2 (2026-09-23): 실행-컴퓨트 변이 권한 GHEC 이전 — GitHub-hosted ephemeral 러너 (Phase D 시행)

> Owner 결정(`docs/spec/repository_surface_contract.md` §Owner 결정 기록 #9,
> 2026-09-23)에 근거한 trust-boundary 변경이다. 실행-컴퓨트 변이 권한은
> axfleet(단일 control host + flock tick journal)에서 GitHub Actions on GHEC의
> GitHub-hosted 러너로 이전된다. 본 amendment는 A1의 실현 메커니즘을
> **tombstone**한다 — 본문을 다시 쓰지 않으며, amendment는 append, tombstone은
> 주석으로만 남는다. 효력은 **Phase D 착지 시**이며, axfleet·관련 구현 파일의
> 삭제는 **INV-1 merge-group 그래프 증명 성공 이후에만** 실행한다.

**유지 (변경 없음):**

- **A1.3은 명시적으로 유지된다** — 신뢰 규칙(`--ephemeral` 러너, 잡 격리 신규 VM,
  러너 재사용 금지, 1 VM = 1 job, "전달 수 = 수명")은 불변이다. **제공자만**
  변경된다: GitHub-hosted 러너가 플랫폼 계약으로 동일 보장을 공급한다 —
  "GitHub automatically provisions a fresh virtual machine. All steps within
  that job execute on the same VM... Once the job completes, the virtual
  machine is automatically decommissioned."
- D1(demand=GitHub)·D5(trust=Axiom)·D3의 **상한값(16)**은 유지된다. D3=16의
  **값은 정책으로 유지**되며, 강제(enforcement)는 reconciler config 상한
  (`decide.nim`)에서 **플랫폼 동시성(matrix caps)**으로 이동한다.

**Tombstone (Phase D 착지와 함께 효력, 삭제 = INV-1 merge-group 그래프 증명 성공 후):**

- **A1.2** — 30s polling reconciler trigger(D2 메커니즘): GitHub-hosted 러너
  실행 경로로 대체 — Axiom 측 realize/reconcile 경로 불요.
- **A1.3 중 제공자·수명주기 실행 메커니즘 절** — 1 VM=1 jitconfig, ghost
  unregistration, external-JIT-only, TTL 86400(24h), warmFloor=0:
  플랫폼이 잡 격리 신규 VM으로 동일 보장을 공급(신뢰 규칙 자체는 위 "유지" 절).
- **A1.4a** — 권위 경계 중 "mutation authority = 단일 control host의 axfleet
  프로세스(flock)" 및 "Axiom reconciler = 용량 상한 + 수명주기 정책" 행:
  실행-컴퓨트 변이 권한은 GitHub 플랫폼으로 이전.
- **A1.4** — 프로비저닝 원천(snapshot `axiom-runner-v4-hygiene-20260920`
  id <snapshot-id>, <zone-1>+<zone-2>/<zone-3> 위치 핀): GitHub-hosted 표준 러너 이미지·리전으로
  대체.
- **A1.5** — 관측·수용: D4 convergence 기준은 GitHub-hosted 환경으로 재해석
  (ephemeral 로그 수집 계약은 플랫폼 로그 정책 기준으로 재검토).
- **A1.6** — 비용 상태(2026-09-21 스냅샷): 역사 기록으로 유지(수치 스냅샷 —
  tombstone 아님).
- **A1.7** — supply 의미 정정 + 병렬 실현(decide/realize 레이어): 실행 경로
  대체. 순수 decide의 결정론 원칙은 verifier pinning 단계에서 GHEC 대응으로
  재평가한다.
- **A1.8** — Path A K 다이얼(이미 2026-09-22 일시 철회): job 수요 축소 개념
  자체는 유지되나, K=8 재도입·통합 16→8은 Phase D 환경에서 재평가한다.

## Amendment A3 (2026-09-24): 소거 게이트 재정의 — CAS 랜딩 검증 + 자체 용량 controller 소거

> Owner 결정(`docs/spec/repository_surface_contract.md` §Owner 결정 기록 #11,
> 2026-09-24)에 근거한다. A2의 소거 게이트 텍스트(`:352` — "삭제는 **INV-1
> merge-group 그래프 증명 성공 이후에만** 실행한다", `:366` — "Tombstone (Phase D
> 착지와 함께 효력, 삭제 = INV-1 merge-group 그래프 증명 성공 후)")는
> **supersede**된다 — INV-1 merge-group 그래프는 merge-queue prefix-chain
> 증명이며, merge queue 자체가 소거 대상이므로(아래 소거 집합 확장) 그 증명은
> 폐기된다. 새 게이트: **삭제 = CAS 랜딩 검증 성공 후 (Owner 결정 #11)** —
> `parents(M)==[B,H] ∧ tree(M)==GitHub-returned merge tree` 실측 ≥N회 +
> `updateRefs` CAS 성공·거부 실측 + 착지 후 `ax cert continuity` ccPassed.
> A1/A2 본문은 다시 쓰지 않으며, 본 amendment는 append, supersede는 명시로만
> 남는다.

**소거 집합 확장 (자체 용량 controller 합류):**

- A2가 플릿(Hetzner) 실행 경로를 tombstone한 데 이어, **자체 소유 용량
  controller**(`decide.nim`의 ceiling/supply 결정 규칙, `reconcile.nim`의
  supply loop)도 소거 집합에 합류한다. D3=16의 **값은 정책으로 유지**되며
  (A2·Owner 결정 #9(c) 유지), controller 코드 소거 이후의 강제는 이미 **플랫폼
  동시성(matrix caps)**에 위임되어 있다.
- controller 소거의 게이트는 A2와 동일하다: **삭제는 게이트 통과 후** — 즉
  CAS 랜딩 검증 성공 후에만 실행하며, A2의 Phase D 착지 시 효력과 결합한다.

## References

- `docs/ci/scale_set_authority_decision_2026-09-20.md` — 결정 문서
  (용량 불변식·acceptance contract·supersede table의 SSOT)
- `docs/ci/demand_driven_capacity_d0_decision_2026-09-08.md:41-47` — A2 gate
- `docs/spec/self_hosted_ci_migration.md:135-152` — retention trigger
- `docs/ci/optimization-2026-09-08.md:92-93` — N=3 seal
- `docs/spec/productization_entry_contract_v1.md:195,199-203` — §7 defer + Amendment Log
- `docs/spec/self_hosted_ci_migration.md` §provisioning credential —
  GitHub App / minimal token (JIT 레지스트레이션 경로)
- `tools/ci/scaleset-adapter/` — Go adapter (go.mod pin v0.4.0)
- GitHub Actions — [Runner Scale Sets / X-ScaleSetMaxCapacity](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/using-runner-scale-sets-with-github-actions)
- ADR-0022 [`0022-admission-artifact-authority.md`](0022-admission-artifact-authority.md) — trust/acceptance model
- Hetzner Cloud FAQ — 서버 존재 기반 과금(생성 완료 서버는 power state 무관 삭제까지 과금)
- GitHub Docs — [Ephemeral runners / registration token TTL](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners)
- Owner 결정 기록 — `docs/spec/repository_surface_contract.md` §Owner 결정 기록 (2026-09-21)
- 구현 선례 — `tools/ci/runner/`(jit_supervisor.sh, host userdata; tag `ci-frozen-2026-09` 보존)
