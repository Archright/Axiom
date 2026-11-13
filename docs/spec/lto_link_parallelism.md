# LTO 링크 병렬도 — Opt-in 계약과 로컬 오버라이드

> **계약**: `config.nims`의 release/danger 빌드는 기본 **No-LTO**로 링크한다(VS-R3, 2026-11-13).
> LTO가 필요하면 `-d:axiomLto`로 명시적으로 Opt-in한다(이때의 링크 플래그는
> `-flto -flto-partition=balanced -flto=2`). 로컬 개발 머신은 커맨드라인 `--passL`로 링크 워커
> 수만 올릴 수 있고, 이 오버라이드는 산출 바이너리 digest에 영향을 주지 않는다(기계 실증 §4).
> **대상 독자**: 링크 wall-clock이 병목인 로컬 개발자; CI 빌드 플래그를 검토하는 리뷰어.

---

## §1. 기본값의 근거 (VS-R3 — No-LTO 기본)

전환 근거는 U1 교차 실측(`docs/evidence/vs_r2_authority_followups_acceptance_2026-11-13.md` §4,
2026-11-13, Nim 2.2.10 / gcc 13.3.0 / 16코어)이다: 동일 소스·동일 nimcache에서 LTO(`-flto=2`)와
No-LTO 릴리스 바이너리의 **런타임 차이는 0%**이고, LTO가 링크 단계에만 **+98.60s**를 추가했다.
검증 의미론(J1/J2/J3, 5-State Exit Contract)은 LTO 링크 정책에 의존하지 않으므로(Execution
Adapter), 기본 경로에서 효과 없는 링크 비용을 제거한다.

Opt-in 시의 `-flto=2`는 L1-a 스크리닝(2026-08-30,
`docs/reports/ci_l1a_lto_screening_p0_2026-08-30.md`)에서 채택된 값이다: 4GB CI 러너에서
peak RSS ≈1.9GB 실측(OOM 없음), 직렬 LTO 대비 link wall-clock ≈32% 감소. GCC 문서상
`-flto-partition=balanced`는 partition별 IR을 동시 보유해 RSS가 상승하므로, 워커 수 상향은
메모리 예산과 무관하지 않다 — **CI에서 Opt-in할 때 기본 2를 유지한다**.

**GCC 전용 계약**: 이 LTO 블록의 플래그(`-flto`, `-flto-partition=balanced`,
`-Wno-stringop-overflow`)는 GCC 전용이다. `config.nims`의 `and defined(gcc)` 가드는
커맨드라인 `--cc:clang` 선택을 **차단하지 못한다** — Nim 2.2.10은 커맨드라인을 2패스로 처리해
(passCmd1 → config 로드 → passCmd2 재적용, `compiler/cmdlinehelper.nim:72-75`) config.nims
평가 시점의 활성 CC는 항상 gcc(전역 nim.cfg `cc = gcc`)이고 최종 링커만 커맨드라인 CC가 된다.
따라서 `-d:axiomLto --cc:clang` 조합은 clang에 GCC 전용 플래그를 전달한다(실측 기입증,
2026-11-13) — **이 조합을 사용하지 말 것**. 이 한계는 구(舊) 기본-LTO 시대에도 동일하게
존재했던 잔존 동작이다.

## §2. Opt-in 조합 행렬 (기계 실측 2026-11-13)

`when defined(axiomLto) and not defined(axiomNoLto):` 조건의 조합별 동작
(검증 방법: `/tmp` 격리 최소 config로 `nim c --compileOnly` 후 nimcache `*.json`의 `linkcmd`
추출 — JSON linkcmd는 `--listCmd`의 실제 `[Link]` 명령과 동일 문자열임을 확인):

| 조합 | linkcmd의 `-flto` |
|---|---|
| release (gcc 기본) | 없음 — No-LTO 기본 |
| danger (gcc 기본) | 없음 |
| release + `-d:axiomLto` | `-flto -flto-partition=balanced -flto=2` |
| release + `-d:axiomNoLto` | 없음 |
| release + `-d:axiomLto -d:axiomNoLto` | 없음 — `axiomNoLto` 우선 |
| release + `--cc:clang` (기본) | 없음 |
| debug (define 없음) | 없음 |

## §3. 사용법

```bash
# 기본 릴리스 빌드 (No-LTO)
make -f ci/checker.mk ci-compile-ax

# LTO Opt-in
nim c -d:release -d:axiomLto -o:bin/ax src/cli/main.nim

# Opt-in + 로컬 링크 워커 상향
nim c -d:release -d:axiomLto --passL:-flto=16 -o:bin/ax src/cli/main.nim

# make 주도 빌드(checker.mk는 NIM ?= nim — env 오버라이드)
env NIM="nim -d:axiomLto --passL:-flto=16" make -f ci/checker.mk ci-compile-ax
```

워커 수는 실제 코어 수에 맞출 것(16코어 호스트에서 `-flto=16`). 주의: 병렬 LTO는 워커 수에
비례해 링크 시 peak RSS를 상승시킨다 — 메모리 여유가 없는 머신(VM·CI)에서는 기본값을 쓴다.

## §4. 오버라이드는 이미 언어 네이티브로 존재한다

Nim의 링커 인자 축적은 두 독립 슬롯으로 분리된다 (핀된 Nim 2.2.10, `compiler/extccomp.nim:523`):

```nim
result = conf.linkOptions & " " & conf.linkOptionsCmd & " "
#                   ↑ config 파일(nim.cfg/config.nims switch("passL"))  ↑ 커맨드라인 --passL
```

즉 **커맨드라인 `--passL` 인자는 항상 config 파일의 passL 이후에 append**된다(소스 근거:
`compiler/commands.nim:865-867` — CLI passL은 passCmd2 재적용 시점에 추가). GCC는 동일 옵션
반복 시 나중 값을 채택하므로, Opt-in 시 최종 링크 명령행은:

```
-flto -flto-partition=balanced -flto=2 -flto=16   →   effective = -flto=16 (워커 16, 파티션은 balanced 불변)
```

## §5. 결정론 — 오버라이드는 산출 digest에 무영향 (기계 실증)

전제: GCC `-flto[=n]`은 링크 시 최적화/코드생성에 쓰는 **병렬 워커 수만** 제어하고,
partitioning은 `-flto-partition=balanced`가 별도로 결정한다(GCC Optimize Options 문서).
워커 수는 스케줄링에만 관여하므로 파티션 집합·최적화 순서는 동일 → 산출 바이너리는
byte-identical이어야 한다.

실측(2026-11-09, 워크트리 `workstream/lto-lever` @ main `2c48285`, Nim 2.2.10 / gcc 13.3.0 /
16코어): `make -f ci/checker.mk ci-compile-ax`로 동일 nimcache 위에서 A(기본 `-flto=2`) →
B(`--passL:-flto=16`) → A′(기본 재링크) 순서로 링크:

| 단계 | effective link flags | wall | `sha256sum bin/ax` |
|---|---|---|---|
| A (콜드 풀빌드) | `-flto -flto-partition=balanced -flto=2` | 2m03.4s | `087c37d3…19e922` |
| B (재링크) | `… -flto=2 -flto=16` | 49.1s | `087c37d3…19e922` |
| A′ (재링크) | `… -flto=2` | 1m47.5s | `087c37d3…19e922` |

A == B == A′ byte-identical 관측이 오버라이드의 결정론 보증이다(전체 digest:
`087c37d3103aa083b60df107aea75c849ba747c6c59987fd16ba961ed5bde922`; B의 effective 플래그는
nimcache `ax.json`의 `linkcmd`에서 `['-flto','-flto-partition=balanced','-flto=2','-flto=16']`
로 기계 확인 — 커맨드라인 `-flto=16`이 config `-flto=2` 뒤에 append됨). 재링크만 격리 비교하면
링크 wall-clock 107.5s → 49.1s(−54%). 원거리 대규모 실증: VS-2b/3 판정 패키지(2026-11-08,
`~/.cache/axiom/vs23-lab/`)에서 `-flto=2` 127.8s vs `-flto=16` 105.0s(저부하 53.5s)·산출
digest byte-identical.

## §6. 관련 문서

- `docs/evidence/vs_r3_no_lto_default_acceptance_2026-11-13.md` — VS-R3 전환 수용 증거(반박 검증·실측·착지)
- `docs/evidence/vs_r2_authority_followups_acceptance_2026-11-13.md` §4 — U1 LTO/No-LTO 교차 실측
- `docs/reports/ci_l1a_lto_screening_p0_2026-08-30.md` — L1-a `-flto=2` 채택 근거·oracle 동등성 실증
- `config.nims` release 블록 — 플래그 정본(SSOT)
- `docs/spec/config_nims_decomposition.md` — config.nims 구조
