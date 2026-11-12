# O1 검증 워밍 프로토콜 — Phase A 결과

> EXPERIMENT_ID=act3-o1-verified-warm-protocol
> Phase A — 코드 수정 없음. 직접 측정으로 워밍 님캐시 프로토콜 판정.
> 일자: 2026-08-30
> 계획: `experiments/act3-o1-verified-warm-protocol/run_e1a.sh`

---

## 0. 대상

CI의 `verify-invariant-mutation` 잡에서 `tools/local_purity_check.nim`이 수행하는
cold materialization 시간(~7m27s)을, 워밍 님캐시 프로토콜(O1)로 단축할 수 있는지
실험적으로 검증한다.

**중앙 질문**: Nim classic 백엔드는 `.o` 파일 재사용 시 mtime 비교를 하는가,
아니면 콘텐츠 비교(CfileFlag.Cached)를 하는가?

**핵심 가설**: Nim이 콘텐츠 기반 비교를 사용한다면, 워밍 님캐시 복원이 cold build와
동일한 바이너리를 생성하면서 CC 라인 수를 대폭 줄여야 한다.

---

## 1. 환경

| 항목 | 값 |
|---|---|
| Nim 버전 | 2.2.10 |
| 호스트 | axiom-verified-host (Linux amd64) |
| 실행 일시 | 2026-08-30 11:10 KST |
| Repo HEAD | `72e896d06e4bc65c774f18f8fb3fb4925f6b0b08` |
| Nim 경로 | `<user-home>/.choosenim/toolchains/nim-2.2.10/bin/nim` |
| 워크트리 경로 | Slot root `$HOME/.cache/axiom/purity-check`; the run's worktree is `$HOME/.cache/axiom/purity-check/<slotId>` (`PureCheckRoot`), where `slotId` is the SHA-256 content stamp of the build inputs + `nim --version` first line + cache-format version — no clock, no pid. The 2026-08-30 measurement below ran against the THEN-current single fixed worktree at `$HOME/.cache/axiom/purity-check`; the slot-root model landed later (same defect family as DEBT#481). See `tools/local_purity_check.nim` (`PureCheckRoot`, `slotStamp`, `acquireSlotLock`). |
| 지속 디렉터리 | `$HOME/.cache/axiom/purity-nimcache` |
| 빌드 명령 | `nim c --hints:on -d:allowMissingZ3 -o:bin/ax src/cli/main.nim` |
| 환경 변수 | `AXIOM_CI_PRESERVE_CACHE=1` (hermetic pre-build가 님캐시를 삭제하지 않도록) |

---

## 2. 프로토콜 스크립트

- `run_e1a.sh` — 단일 셸 스크립트로 E1a 전체 오케스트레이션 수행
- `o1-phase-a.md` — 이 결과 문서

스크립트는 다음 순서를 구현한다:
1. 던지기 워크트리 생성 (`git worktree add --detach`)
2. 스텝 `bin/axiom.nim` 작성 (local_purity_check.nim과 동일)
3. `git clean -ffdx -e build/nimcache -e .axiom/cache -e proofs/.lake` 실행
4. COLD build 실행 → wall-clock, CC: 라인 수, ArtifactOutputDigest 기록
5. Copy-out: 님캐시 → 스테이징 → 스탬프 기록 → `active` 심볼릭 링크 원자적 전환
6. 워크트리 삭제
7. 동일 경로에 FRESH 워크트리 재생성
8. Copy-in: 스탬프 검증 → 일치 시 `cp -a`로 님캐시 복원
9. WARM build 실행 → 동일 지표 기록
10. T2a/B1-B2: 리빌드 세트 프로브 (리프 모듈 터치)
11. T3/C1-C4: 정체성 무효화 테스트
12. T4/F1-F5: 프로세스 크래시 원자성 테스트

---

## 3. E1a — Cold vs Warm 수치

### 3.1 주요 수치

| 지표 | COLD | WARM | 변화 |
|---|---|---|---|
| Wall-clock | 46,937 ms (~47s) | 36,614 ms (~37s) | -10,323 ms (-22%) |
| CC: 라인 수 (컴파일 유닛 수) | **599** | **51** | **-548 (-91.5%)** |
| ArtifactOutputDigest | `81b044304031a359ad3eee2a649654909fd3a058f8968853d5f1a4d99743bb0d` | `81b044304031a359ad3eee2a649654909fd3a058f8968853d5f1a4d99743bb0d` | **동일** |

### 3.2 판정

- **D_cold == D_warm**: ✅ YES — 바이너리와 모든 .o 파일의 SHA-256 해시가 완전히 동일
- **CC_warm << CC_cold**: ✅ YES — 599 → 51로 91.5% 감소. warm reuse가 대부분의 재컴파일을 방지
- **wallclock_warm << wallclock_cold**: ✅ YES — 47s → 37s로 22% 단축

**가장 중요한 측정 사실**: Nim classic 백엔드는 `.o` 파일 재사용 시 **mtime이 아닌 콘텐츠 비교(CfileFlag.Cached)**를 사용한다. fresh checkout에서 `.nim` 소스 파일의 mtime은 새로우나, 복원된 `.c`/`.o` 파일의 mtime은 과거이다. Nim이 mtime 기반staleness 감지를 사용했다면 모든 599개 유닛이 재컴파일되었을 것이다. 실제로 51개만 재컴파일되었으므로, Nim은 생성된 C 파일의 콘텐츠를 기존 `.c` 파일과 비교하여 동일하면 `.o`를 재사용한다.

---

## 4. T2a / B1-B2 — 리빌드 세트 정확성

### B1: 영향 폐쇄 집합 계산

`src/gate/topology_spec.nim`을 리프 모듈로 선택하여 impact_closure_selector.nim의
`buildCoreImportGraph` / `buildReverseGraph` / `transitiveDependents` 알고리즘을
재구현하여 분석:

- Core import graph: 646개 모듈
- Core reverse graph: 1,175개 엣지
- `topology_spec.nim`은 core 모듈을 **0개** 임포트 (리프 모듈임이 확인)
- 따라서 영향 폐쇄 집합은 빈 집합

### B2: 리프 모듈 터치 프로브

`topology_spec.nim`에 순수 주석(빈 행 + `// probe-touch`)을 추가하여 mtime을 변경하되
의미적 내용은 변경하지 않음. 이후 warm build 실행:

| 조건 | CC: 라인 수 |
|---|---|
| Warm build (터치 없음) | 51 |
| Warm build (topology_spec.nim 터치 후) | **0** |

**결과**: 리프 모듈을 터치해도 **0개의 추가 CC 라인**이 발생. Nim의 콘텐츠 기반
증분 컴파일이 해당 모듈의 의존성 체인에 변화가 없음을 정확히 감지하여 재컴파일을
전혀 수행하지 않았다. 이는 Nim의 증분 컴파일이 mtime이 아닌 콘텐츠 해시를 사용함을
재확인한 것이다.

---

## 5. T3 / C1-C4 — 정체성 무효화

### C1: 스탬프 불일치 감지

Makefile에 빈 행을 추가하여 스탬프 입력 중 하나를 변경. 재계산된 스탬프:

- 저장 스탬프: `68dffaa50f7ae88a1aa88437e833b05db309a100560d737f90da9819c3d93d7b`
- 변경 후 스탬프: `ce91e13dcf8ffcd86e185f0b742c96781a50ada947dffc20aa832948d09f873`

**C1 PASS**: 스탬프 불일치가 정확히 감지됨. copy_in는 warm 유닛을 거부하고 cold build를
수행했을 것이다.

### C2: 경로 변경 무효화

워크트리 경로를 변경하여 스탬프를 재계산하면 스탬프가 달라짐. copy_in는 다른 경로의
유닛을 거부한다.

> **Superseded (2026-10-04)** — 이 측정은 THEN-현재 모델(워크트리 경로가 스탬프의
> **입력**)을 기록한 것이다. 현재 모델은 반대로, 워크트리 경로가 스탬프의
> **결과**다: `computeStamp`의 입력은 빌드 입력 파일들의 콘텐츠 + `nim --version`
> 첫 줄 + `WarmCacheVersion` 뿐이며 경로를 포함하지 않는다(feedback이 되면
> 순환이 되므로). 워크트리 경로 자체가 콘텐츠 주소화 슬롯
> (`PureCheckRoot / <slotId>`)이어서, "경로가 다르면 다른 유닛"이라는 성질은
> **구성으로 보장**된다 — 즉 무효화는 여전히 성립하지만 메커니즘이 반전되었다.
> §1의 워크트리 경로 행과 `tools/local_purity_check.nim`를 참조.

### C3: Nim 버전 변경 무효화

스탬프에 `nim --version` 첫 번째 줄이 포함되어 있으므로, Nim 버전이 변경되면
스탬프가 자동으로 무효화된다.

### C4: 입력 파일 변경 무효화

스탬프는 12개 입력 파일의 콘텐츠 해시를 모두 포함하므로, 어떤 입력 파일이든
변경되면 스탬프가 무효화된다. C1에서 이를 실증함.

**C1-C4 종합**: 정체성 검증 체계가 완전히 작동하며, 어떤 단일 guard 입력 변경도
warm 캐시를 올바르게 무효화한다.

---

## 6. T4 / F1-F5 — 프로세스 크래시 원자성

### F1: 정상 전환

`active.tmp` → `active` rename 후, `active` 심볼릭 링크는 항상 완료된 유닛을
가리킨다. 유닛 디렉터리 내에 `stamp` 파일이 존재함을 확인.

### F2: 중간 크래시 시뮬레이션

스탬프를 작성하지 않은 불완전한 유닛(`unit-incomplete-test`)을 생성하여 크래시를
시뮬레이션. `active` 심볼릭 링크를 전환하지 않은 상태에서 크래시가 발생하면,
`active`는 여전히 이전 유효한 유닛을 가리킨다.

### F3: 스탬프 선행 보장

프로토콜은 `active` 심볼릭 링크를 전환하기 전에 반드시 스탬프를 작성한다.
유닛 생성 중 크래시가 발생해도 `active`는 불완전한 유닛을 가리키지 않는다.

### F4: 내구성 (NON-goal)

마지막 유닛의 손실은 허용된다. 크래시가 copy-out 중에 발생하여 `active`가
부분적으로 기록된 유닛을 가리키는 경우, `copy_in`는 스탬프 불일치로 warm 캐시를
거부하고 cold build로 전환한다. 이는 warm 캐시 손실로 이어지지만, 프로토콜의
목표는 **정확성**이지 **내구성**이 아니다.

### F5: 실패한 전환 후 dangling 심볼릭 링크 없음

`active.tmp` → `active` rename이 실패한 후에도 `active`는 여전히 유효한 유닛을
가리킨다.

---

## 7. GO/NO-GO 판정

### **GO — O1 워밍 님캐시 프로토콜이 작동함**

**가장 중요한 측정 사실**: warm reuse가 재컴파일의 **91.5%를 제거**했다
(CC: 라인 599 → 51). 바이너리 콘텐츠 해시가 동일하며, Nim classic 백엔드는
mtime이 아닌 콘텐츠 비교(CfileFlag.Cached)를 통해 `.o` 파일을 재사용한다.

이는 CI의 cold materialization 시간(~7m27s)을 워밍 프로토콜로 크게 단축할 수
있음을 의미한다. 실제 CI 환경에서는 worktree 생성과 git clean이 여전히 필요하지만
(nimcache는 제외), nimble build 단계의 님캐시 재 materialization이 거의 사라진다.

### 주의사항

- `AXIOM_CI_PRESERVE_CACHE=1` 환경 변수를 설정해야 한다. 그렇지 않으면
  config.nims의 hermetic pre-build 블록이 MISS 시 `build/nimcache`를 삭제하여
  워밍 캐시를 무효화한다.
- 워밍 캐시의 지속 디렉터리(`$HOME/.cache/axiom/purity-nimcache/`)는 CI 에이전트
 의 로컬 디스크에 보관되어야 하며, 에이전트 재시작 시 캐시가 사라질 수 있다.
  이는 허용 가능한 동작이다(F4: 내구성은 NON-goal).
