# VS-T3 레버 (a) 테스트 빌드 모드 — `--passC:-O2` 판정 정체성 검토와 착지 (2026-11-16)

> **종류**: 잔여 레버 (a)의 계약 검토(판정 정체성 선행 조건) 수행 기록 + 최소 착지.
> `docs/design/admission_gate_performance_cutover_design_2026-11-13.md` §10은 레버 (a)
> "테스트 레인 release 빌드"에 "판정 정체성 검토 선행 필수"를 걸었다. 검토 결과:
> **`-d:release`는 이 저장소에서 정체성 담보 불가(특이 3요인) → 기각. 대신
> `--passC:-O2`(C 컴파일만, 코드젠·검사 무변경)는 정체성 불변을 실증으로 확정 —
> 이 변형으로 착지한다.** 검사 실행·판정 재계산·evidence key·exit 의미는 전부 무변경이다.

관측·측정 핀: `0d924abb`(origin/main). 조사는 /tmp 격리 worktree + /tmp/bench 마이크로
벤치마크로 수행했고, 착지 A/B는 본 PR 워크트리에서 **생산 레시피 그대로**(`make
test-fast-one`) 수행했다. 원 기록 보존: `/tmp/bench/bench_summary.txt`·`closures_resolved.txt`.

## 1. 공식 문서상 모드별 의미 — "release가 검사를 끈다"는 통념이 부정확

| 항목 | debug | `-d:release` | `-d:danger` |
|---|---|---|---|
| bounds/overflow/obj/field/range 검사 | ON | **ON (유지)** | OFF |
| `assert` | ON | **ON (유지)** | OFF (코드 미생성) |
| `doAssert` | ON | ON | **ON (전 모드 발화)** |
| stacktrace/linetrace/lineDir | ON | OFF | OFF |
| C 최적화 | `-O0` | `-O3 -fno-ident -fno-math-errno` | 동일 |

근거(Nim 공식 문서, Context7·핀 툴체인 소스 대조):

- changelog 0.20.0 — "`-d:release` switch now does not disable runtime checks anymore…
  use `-d:danger`" (이후 전 버전 지속).
- `nimc.md` defines 표 — release는 optimizer ON·trace off이고 **검사를 바꾸지 않는다**;
  `-ffast-math`는 옵트인 예시일 뿐 기본값이 아니다.
- `advopt.txt` — `--passC`는 **C 컴파일러에만** 전달된다(링크 아님; linkcmd 실측에서
  `-O` 부재 확인).
- 핀 툴체인 `config/nim.cfg` — `@if danger or quick` → 검사+assertions off,
  `@if release or danger` → `opt:speed`+trace off (검사 미변경);
  `gcc.options.speed = "-O3 -fno-ident -fno-math-errno"`.
- stdlib `lib/std/assertions.nim` — `assert`는 `compileOption("assertions")` 게이트,
  `doAssert`는 무조건 발화.

로컬 실증(Nim 2.2.10 + gcc 13.3, /tmp/modes): `assert false`는 release에서도 exit 1,
danger에서만 exit 0; `doAssert false`·오버플로·인덱스 검사는 release에서 발화;
`doAssertRaises(OverflowDefect)`는 danger에서만 AssertionDefect로 붕괴; FP 10M 루프의
비트 패턴은 -O0/-O2/-O3/release/danger 전부 동일.

설계 문서 §10 레버 (a)의 전제 서술("release 빌드 시 debug assertion·오버플로 검사
부재화")은 이 표로 정정한다.

## 2. 그럼에도 `-d:release`를 쓰지 않는 이유 — 이 저장소 특이 3요인

1. **`config.nims:47-49`** — 이 저장소의 release 정의에 `--panics:on`을 얹는다 →
   defect가 catch 불가한 abort로 전환(실증: `--panics:on`에서
   `try/except OverflowDefect`가 못 잡고 exit 1). unittest 프레임의 예외 캡처·
   `doAssertRaises` 의존을 무효화할 수 있다.
2. **`gateway_main.nim:192,233`** `when not defined(release)` — 저장소에서 release가
   코드 분기를 바꾸는 유일 지점(스윕 확정). release 적용 시 분기가 전환된다.
3. **stacktrace off** — 결함 진단 출력 형태가 변한다. 유닛 게이트의 `grep "Traceback"`
   실패 패턴 감쇠 위험(Makefile test-fast 유닛 집계 레시피).

`--passC:-O2`는 셋 전부에 해당하지 않는다: Nim 코드젠이 완전히 동일(같은 .c, 같은
검사 코드, 컴파일타임 조건 변화 0)이고 유일 변수는 gcc -O2다.

## 3. 판정 정체성 — 의존 클로저 전수 스윕

대상: `test-fast-one`(Makefile:1093-1096) 소비 **6 유니크 타깃** — 배터리
checker·probe 2종(`admission-check.yml:4041`·`:4053`, lane-0/lane-1 양측) + GO 루프
4타깃(`:4203-4205`) s1a·proof_integrity·d2_golden·d2_persist.

판정 메커니즘은 assert/doAssert **비의존**이다: checker는 순수 Result/문자열 반환
(expectPass/expectFail = 문자열 비교), probe는 expect(bool)+Result err(try/except는
readFile 주변뿐), s1a는 std/unittest `check`(비발생성 누적). 핫 체인 `sha256Hex`는
nimble `checksums-0.2.2`의 `sha2.nim`이다.

nimcache json "compile" 배열로 추출한 실제 의존 클로저(checker 38 / probe 116 /
s1a 134 모듈; repo 58 + nimble 15 파일 해석 — 원 기록 `/tmp/bench/closures_resolved.txt`):

| 분류 | 위치 | 모드 민감도 |
|---|---|---|
| (i) 도달 불가능한 내부 불변식·사전조건 (전부 `doAssert`) | `axiom_ir_helpers.nim:31`, `results.nim:45,50`, `repo_root.nim:18,21`, `canonical_obligation_generator.nim:258`, `canonical_verification.nim:812`, `no_obligation_provenance.nim:36`, `obligation_ir.nim:108`, `obligation_types.nim:170`, `sha_utils.nim:35,46`, `sha2.nim:282` | **전 모드 유지** — release/passC 어느 쪽도 불변 |
| (ii) defect catch 의존 | `compiler/lexer.nim:581` `except OverflowDefect, RangeDefect` (nimble nim-2.0.8) | danger에서만 변화, release는 검사 유지라 발화 유지 |
| (iii) Nim 레벨 분기 | `gateway_main.nim:192,233` `when not defined(release)` | release에서 분기 전환 — **passC는 무변경** |

**판정**: `--passC:-O2` → 판정 변화 불가. 유일 변수인 gcc -O2에 대해서도 핫 루프
(sha2)는 UB-free 구조다(생성 C에서 `m[]` `nimZeroMem` 영초기화·`raiseIndexError2`
가드·전부 unsigned 정수·FP 0 확인) — 관찰 가능 동작이 불변이다.

## 4. 마이크로 벤치마크 — 최적화 레벨 간 결정론 (119,585,096B sha256, 생산 경로 그대로)

| 변형 | C 플래그 | 소요(초) | digest |
|---|---|---|---|
| v0 현행 debug | `-O0` (gcc 기본) | 40.13 / 40.71 | `98f62e5f…b49b9b` |
| v1 `--passC:-O2` | `-O2` | **12.30 / 12.20 / 12.67** | 동일 |
| v2 `--passC:-O3` | `-O3` | 12.29 / 11.83 (1회 23.17 — CPU 경합 이상치) | 동일 |
| v3 `-d:release` | `-O3 -fno-ident -fno-math-errno` | 2.06 / 1.97 | 동일 |
| v1s `-O2`+stacktrace:off | `-O2` | 0.79 / 0.85 | 동일 |

digest는 **전 변형·전 실행에서 동일**하고 `sha256sum` 기준과 일치한다 → 최적화
레벨 간 결정론 실증. 컴파일 비용: 플래그 변경 시 전 C 재컴파일(임베디드 컴파일
명령 기반, warm 체커 기준 17-19s) — B-cache 세대 전환 1회성이고 job1이 흡수한다.

**권고하지 않는 옵션(기록만)**: v1s(`--stacktrace:off`, 0.8s 도달)는 결함 진단
표면을 바꾼다; v3(`-d:release`)는 §2의 3요인으로 정체성 담보가 성립하지 않는다.

## 5. 착지 A/B 실증 (본 PR, 생산 레시피 그대로)

워크트리 `0d924abb`, `make test-fast-one T=tools/ci/check_evidence_id_contract.nim`:

- **warm v0 3.00s EXIT=0 ↔ warm v1 2.99s EXIT=0 — 출력 바이트 완전 동일(diff 0)**:
  `[PASS]` 전 행·`self-check PASSED`·계약 `evidence-id-contract.v1` 전부 일치.
- v1 첫 실행 11.6s = 플래그 변경에 따른 **1회성** C 전체 재컴파일(nimcache `.c`가
  컴파일 명령을 내장 → shouldRecompile). 이후 warm 3.0s로 수렴 — 세대 전환 비용의
  레인 유입 0(잔여는 CI job1의 B-cache 재생성이 흡수).
- nimcache `build/nimcache/test/ax-one.json`의 compile 엔트리(38모듈) gcc 명령에
  `-O2` 임장 확인: `gcc -c -w -fmax-errors=3 -fno-strict-aliasing -pthread -O2 …`.
- hermetic "Environment changed (MISS)" 1회 관측 = Makefile 변경에 따른 세대 전환
  1회성(재실행 시 HIT 복귀) — 판정 관련 0건.

## 6. 변경 내용·영향 반경·정책 적합성

- **diff: Makefile:1096 1토큰** — `--hints:off` → `--hints:off --passC:-O2`.
  CI 토폴로지·workflow·required checks·게이트 구성은 무변경(topology epoch
  cutover 불요 — C4/PR #59와 동일한 클래스의 제품/도구 내부 최적화).
- 소비자는 `test-fast-one` 경유 6 유니크 타깃뿐이다.
- surface 정책: Makefile은 현재 `config/repository_surface.json`(v99)에서
  **CONTROLLED**(MODIFY=PASS) — DEBT#432의 "FROZEN Makefile" 서술은 v51 시대
  드리프트다(현 FROZEN 목록에 Makefile 부재; 현세대 main에 Makefile 착지 다수).

## 7. 착지 후 관찰 항목

1. 첫 B-cache 재생성 배치에서 job1이 전 C 재컴파일을 흡수하고 레인은 warm으로
   유지되는지(nimcache 복원 TEST_SUPPLY_N 구조 무변경).
2. 판정·evidence key 불변: CONTRACT_VERSION·digest·[PASS]/[FAIL] 행이 전 레인에서
   변경 전과 동일.
3. 배터리·GO 스텝 실측 절감 — 기대는 방향성 외삽(로컬 v0 40s ≈ CI probe 44s):
   probe digest 44s→~13s(3.3x), 배터리 99s→~68s, s1a 56.5s→~26s,
   **lane(0) 294s→~232s(−62s 추정)**. 표본 1-3회 외삽임을 명시 — 착지 후 2회 MG
   관측으로 확정한다.
4. vendor C(ed25519)가 -O2로 컴파일되는 경로 관찰(업스트릭 표준 빌드 조건과
   동일하므로 무해 예상).
