# VS-R3 정본 Release 빌드 No-LTO 기본 전환 (Opt-in `-d:axiomLto`) — 수용 증거 (2026-11-13)

> **종류**: 실행 증거 기록 (acceptance evidence). 목적은 VS-R3 슬라이스 — `config.nims` release/danger
> 기본 빌드를 No-LTO로 전환(LTO는 `-d:axiomLto` 명시적 Opt-in)하고 규범 문서·Tier C 회전 핀을
> 정합화 — 의 사전 반박 검증, 실측, 게이트 통과, 착지 증거를 한 문서에 고정하는 것이다.
> **근거 실측**: U1 (`docs/evidence/vs_r2_authority_followups_acceptance_2026-11-13.md` §4) —
> LTO `-flto=2`의 런타임 이득 0%(`ax cert verify --kernel` 69.50s vs 68.18s, 외부 커널 지배),
> 링크 비용 +98.60s(98.89s vs 0.29s, 341배), 콜드 빌드 +59.98s(124.98s vs 65.00s).

## 1. 변경 요약

| 파일 | 변경 |
|---|---|
| `config.nims:50` | `when not defined(axiomNoLto):` → `when defined(axiomLto) and not defined(axiomNoLto):` (+ 계약 주석). `-opt:speed`·`--panics:on`·LTO 플래그 본체는 불변 |
| `docs/spec/lto_link_parallelism.md` | No-LTO 기본 계약으로 전면 개정: §1 근거(U1)·GCC 전용 경고, §2 조합 행렬(기계 실측), §3 사용법, §4–5 passL 오버라이드·결정론 실증 보존 |
| `config/trusted_writer_set.json` | `config.nims` blob SHA 재앵커(`bin/reanchor_pin --ref HEAD --write`, 멤버십 불변 — §3.4) |

## 2. 사전 반박 검증 (구현 전 — Context7 공식 문서 + 백그라운드 병렬 서브에이전트 2기)

### 2.1 조합 7개 + `--passL` append 순서 (실측 — /tmp 격리 최소 config, Nim 2.2.10 / gcc 13.3.0 / 16코어)

방법: 제안 조건문을 담은 최소 `config.nims`으로 `nim c --compileOnly` 후 nimcache `*.json`의
`linkcmd` 추출(JSON linkcmd는 `--listCmd`의 실제 `[Link]` 명령과 동일 문자열임을 확인).

| id | 조합 | linkcmd의 `-flto` | 판정 |
|---|---|---|---|
| C1 | (현행 config) release | `-flto -flto-partition=balanced -flto=2` | ✅ 변경 전 기본 LTO |
| P1 | release (proposed) | 없음 | ✅ No-LTO 기본 |
| P2 | danger | 없음 | ✅ |
| P3 | release + `-d:axiomLto` | `-flto -flto-partition=balanced -flto=2` | ✅ Opt-in |
| P4 | release + `-d:axiomNoLto` | 없음 | ✅ |
| P5 | release + `-d:axiomLto -d:axiomNoLto` | 없음 | ✅ `axiomNoLto` 우선 |
| P6 | release + `--cc:clang` | 없음 | ✅ (단, 근거는 §2.1a 참조) |
| P7 | debug (define 없음) | 없음 | ✅ |

**passL 오버라이드 순서 (O1, linkcmd 전문 중)**:

```
gcc -o probe @mprobe.nim.c.o … -pthread -pthread -flto -flto-partition=balanced -flto=2 -flto=16 -ldl
```

커맨드라인 `--passL:-flto=16`이 config `-flto=2` **뒤에** append됨(소스 근거: Nim 2.2.10
`compiler/commands.nim:865-867` — CLI passL은 passCmd2 재적용 시점 추가). GCC 동일 옵션
last-wins 규칙상 effective = `-flto=16`(§5의 byte-identical 실증이 산출 무영향을 보증).

**§2.1a P6 가드 반박(계정 반영)**: `and defined(gcc)` 가드는 커맨드라인 `--cc:clang` 선택을
차단하지 못한다 — Nim 2-pass 처리(passCmd1 → config 로드 → passCmd2 재적용,
`compiler/cmdlinehelper.nim:72-75`)로 config.nims 평가 시점 활성 CC는 항상 gcc(전역 nim.cfg
`cc = gcc`)이고 최종 링커만 커맨드라인 CC가 된다. 실측: `-d:release -d:axiomLto --cc:clang`은
clang linkcmd에 `-flto …`를 부착. 이는 현행(구 기본-LTO) config에도 동일하게 존재하는 잔존
동작이며(C2 실측), VS-R3 기본 No-LTO 전환은 노출을 줄인다. **조치**: 스펙 §1에 "GCC 전용
계약 — `-d:axiomLto --cc:clang` 조합 금지"로 문서화(신규 메커니즘 없음, 최소 변경).

**Context7 공식 문서 확인**(`/websites/nim-lang_github_io_nim`): `defined()`/`-d:x`·`-u:x`
의미론, define 심볼 case-insensitivity, `--compileOnly`/`--passL` 스위치. passL append 순서의
명시적 서술은 공식 문서에 없어 소스 근거+실측(linkcmd)으로 판정했다.

### 2.2 "3 해시 기대치" 반박 검증 (코드 근거 + 재현 계산)

| 주장 | 판정 | 근거 |
|---|---|---|
| `BuildSourceHash` 동일 | **성립** | `tools/hermetic_build.nim:851-864` — `computeDeterministicSourceHash(src)`는 src/ `.nim`만 수집(`/generated/` 제외). config.nims는 입력 집합 외 |
| `VerifierBuildId` 변경 | **성립** | `tools/hermetic_build.nim:868-910` — 매니페스트에 `config.nims` 바이트 sha256 포함 → config.nims 변경 시 필연 이동 |
| `canonicalProjectionHash` 동일 | **반박** | `canonical_projection.nim:22-65,118-120` — 상태 문서 전체를 해시하며 volatile 제거 목록에 `executionIdentity`/`verifierBuildId` **없음**. 재현 계산이 현재값 `30ab50d3…`과 정확히 일치(아래 §3.2), `verifierBuildId` 단독 변경 시 digest 변화 유도로 입증 |

원인: `canonicalProjectionHash`(전체 상태 투영)와 `certSemanticProjection`
(`certificate_verifier.nim:178-196` — 빌드 정체성 배제, 인증서 리플레이 동등성)의 혼동.
**수용 기준 교정**: 전체 digest의 변경은 바이너리-정체성 결속의 충실한 반영이므로 허용하고,
J1 패리티는 **`executionIdentity` 제외 투영의 전환 전후 동일**로 판정한다(§3.2).

**VKD 파급**: 저널 VKD admission(`cert_reconcile.nim:830-853,1208`)은 **현재 측정
engineBuild 핀**과 대조(fail-closed)하며, `ax prove` 재실행만으로 자가치유되지 않는다(증명서
하이드레이션이 구버전 engineBuild 인증서를 재사용 — `certificate_hydration_runner.nim:36-116`).
단, 현재 canonical main의 live VKD는 이미 `0/23`(`ax report --json` `metrics.vkd`)이며 이
상태에서 required 체크가 green이므로 VS-R3 착지를 차단하지 않고 추가 영향도 없다(0→0).
VKD 회복은 실제 재증명 → 신규 클레인 커밋(`cert_writer.nim:598`) 경로의 **별도 후속 슬라이스**다.

### 2.3 Tier C 재앵커 절차 (④)

현재 main `OK no-drift`(exit 0), `config.nims` 핀 `0fd75090…`. 절차: 커밋 →
`./bin/reanchor_pin --ref HEAD --write`(drift 반영) → diff 최소성 기계 확인(config.nims blob
SHA만 갱신, 멤버십 변경 시 exit 3 = 중단) → `git commit --amend --no-edit` →
`./bin/reanchor_pin --ref HEAD`로 `OK no-drift` 확인.

### 2.4 측정 분리 설계 (③)

콜드(전체 빌드) / 링크 격리(nimcache `ax.json`의 linkcmd 직접 실행) / 웜(2차 빌드)은 서로 다른
측정치로 분리 기록한다. `--compileOnly`는 linkcmd 검증 용도로만 사용. 환경: Nim 2.2.10
(choosenim toolchains), gcc 13.3.0 (Ubuntu 13.3.0-6ubuntu2~24.04.1), 16코어.

## 3. 전환 후 실측 (2026-11-13, workstream/vs-r3-no-lto-default @ main `513ce45`)

### 3.1 빌드 성능 (③ 분리 측정)

| 측정 | 값 | 비교 |
|---|---|---|
| 콜드 `make -f ci/checker.mk ci-compile-ax` (hermetic measure MISS 재실행 포함) | **83.68 s** (maxrss 1.12 GB) | U1 LTO 콜드 `nim c` 124.98s — LTO 제거의 주 절감은 링크 단계 |
| **링크 격리** (ax.json linkcmd 직접 실행) | **0.31 s** (maxrss 84 MB) | U1: LTO 98.89s vs No-LTO 0.29s — **-99.7%** |
| 웜 전체 타깃 (`make ci-compile-ax`, hermetic HIT) | 27.14 s | — |
| 순수 웜 nim 재컴파일 (CC 0 + 재링크) | 20.14 s | 링크 자체는 위 0.31s |

정본 경로 검증: `build/nimcache/ci-compile/ax/ax.json`의 `linkcmd`에 `-flto` **없음**
(전환 전 `-flto -flto-partition=balanced -flto=2` → 전환 후 NONE).
`./bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree` (exit 0).

### 3.2 3-Way Identity (② 실측 — 교정된 기준)

| 해시 | 전환 전 | 전환 후 | 판정 |
|---|---|---|---|
| `BuildSourceHash` | `vs1-tree-hash/1:-6060185168445716507` | 동일 | ✅ 불변 (입력집합 src/불변: `git diff main --stat` = config.nims+스펙 문서 2파일만, src/ 0 변경; provenance OK) |
| `VerifierBuildId` | `84ed1bf0abc18dc3954d0dd4b8f005f120ffb5311fbb8b7340351cc8a5d009be` | `b6b22c47c0b432e696e5ba58bbc6e87b6b3f58d057641eaa69332cac47b9cff9` | ✅ 이동 (예상대로 — envHash MISS → hermetic_build 재측정) |
| `canonicalProjectionHash` (전체) | `30ab50d3511f7f900ddac369497025930e1933854c274e0534c6d764143b5521` | `25c79e8caed0f76088c91b184683bd1aa9606e28b504c6c4750196644e6757e5` | ✅ 변경 (§2.2 교정 기준 — executionIdentity.verifierBuildId 경유, 정상) |
| **`executionIdentity` 제외 투영** | `1a6e8faf85fef54bafb340e59de91c51532f30e91217c9fc51d96d568794c60d` | **동일** | ✅ **J1 semantic parity 기계 입증** — 검증 의미론 바이트 단위 보존 |

`ax report --canonical-digest` (공식 CLI) = `25c79e8c…` (exit 0) — 재현 계산과 일치.
재현 방법: `canonical_projection.nim`의 volatile-strip(36키+`runtimeMeta`)·sorted-key 직렬화·
SHA-256을 그대로 python으로 재현, 전환 전(`/tmp/vsr3_pre_state.json` 백업)·후 상태에 적용.

기존 인증서 재발행 불요: `./bin/ax cert verify data/trusted/certificates/e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200.json` → `PASS (replayMatched=true, semanticHash=64b9c29e…)` (exit 0). 클로저 검증(`verifyCertificateClosureNode`)은 engineBuild를 검사하지 않는다.

## 4. 통합 게이트 결과 (전부 No-LTO 바이너리로 실행)

| 게이트 | 결과 |
|---|---|
| `make verify-contract` | `✅ PASSED` — `[PASS] g1 [PASS] g2 [PASS] g6g4 [PASS] g7` (exit 0) |
| `make verify-contract-release-e2e-full` | `[cert] Verify: PASS (kernel re-execution — lean=re-executed, z3=unsat, leanchecker=passed)`, `G7 pass (tier=dual-verified)`, `✅ PASSED` (exit 0) — 상태가 새 `VerifierBuildId b6b22c47…`로 재기록, runOutcome `verdict=PASS basis=PROVEN` |
| `make perf-check` | `[PERF OK] LeanKernelVerification: 0.0% change`, `[PERF] gate passed` (exit 0) |
| `./bin/debt_engine --validate` | `All debt validation checks passed` (exit 0) |
| `./bin/ax cert verify` (기존 인증서) | `PASS` (exit 0) |
| `./bin/ax --check-provenance` | `AXIOM_PROVENANCE: OK` (exit 0) |

## 5. MUST-T2a 권한 위임 기록

본 슬라이스는 `config.nims`(Tier C 회전 핀 대상)을 수정한다(trustSurface 터치). 세션
2026-11-13 사용자 명시: "권한이 필요한 부분은 전면 허가한다" — `bin/reanchor_pin --write`
실행, push, PR 생성, GitHub native MERGE(merge authority = GitHub ruleset + Merge Queue)에
대한 수동 병합 위임 요건 충족. 에이전트는 판정·게이트 결과를 관측·기록만 한다.

## 6. 착지 증거

PR **#15**(`workstream/vs-r3-no-lto-default`, head `910155e`): 6대 필수 체크
(admission-check·axiom-operational-slice·bsec-integrity·debt-registry-gate·generation-acceptance·publication-integrity)
**전부 pass** → `gh pr merge 15 --merge`(GitHub Merge Queue) → native MERGE 커밋
`1d881b0f274ea8661b951ab8f9a44ac247819101`(2-parent: merge-group base `52413df` + branch head
`910155e`). merge_group 워크플로 관측: trusted-writer-set·debt-registry-gate·landing-integrity·
generation-acceptance·probe-merge-queue·bsec-integrity·observer-manifest-consistency·
publication-integrity·axiom-operational-slice·admission-gate **전부 success**.

## 7. canonical main 수용 (2026-11-13, merge `1d881b0`)

복합 main(PR #14 `52413df` 포함)에서 실측한 수용 결과:

| 검증 | 결과 |
|---|---|
| `make -f ci/checker.mk ci-compile -j4` (ax 콜드) | 67.88s, integrity merkle 일치(`62f0c2f4…`) |
| `./bin/ax --check-provenance` | `AXIOM_PROVENANCE: OK` (exit 0) |
| `make verify-contract-release-e2e-full` | `[cert] Verify: PASS (kernel re-execution — lean=re-executed, z3=unsat, leanchecker=passed)`, `G7 pass (tier=dual-verified)`, `✅ PASSED` (exit 0) |
| ① linkcmd | main `build/nimcache/ci-compile/ax/ax.json`의 `linkcmd`에 `-flto` **없음** — 정본 No-LTO 운영 확정 |
| ② Identity | `VerifierBuildId` `a0606d88…`(본 슬라이스 `b6b22c47…`에서 재이동 — PR #14 src 변경 포함, 매니페스트 정상 동작). `BuildSourceHash` `vs1-tree-hash/1:2126190727417608340`(PR #14 반영). **슬라이스 범위 패리티(§3.2 — 동일 입력에서 config.nims만 변경)가 권위 비교로 유지된다** |
| ④ Tier C | `./bin/reanchor_pin --ref HEAD` → `OK no-drift` (exit 0) |
| canonical digest | `ax report --canonical-digest` = `301a1283…` (exit 0) — 복합 main 상태(executionIdentity·src 변동 반영, §2.2 교정 기준상 정상) |
| 병합 후 push CI | trusted-writer-set·axiom-operational-slice `success` |
| 작업 트리 | `git status --short` 빈 출력(clean) |

**VKD 운영 관측**: main e2e 재증명으로 VKD가 `0/23 → 1/23`(ratio 0.043)로 이동 — 캐너리
커널(`orchestrator_api.nim::normalizeMaxWorkers`)의 신규 클레인이 현재 engineBuild로 발행·
admission됐다. §2.2의 "회복은 실제 재증명 → 신규 클레인 경로뿐" 메커니즘의 운영 실증이며,
전체 VKD 회복은 별도 재증명 슬라이스로 분리된다.
