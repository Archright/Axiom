# LTO 링크 병렬도 — CI 기본 계약과 로컬 오버라이드

> **계약**: `config.nims`의 release LTO 링크 플래그(`-flto -flto-partition=balanced -flto=2`)는
> **CI(L1-a, 4GB 러너) 기본값**이다. 로컬 개발 머신은 커맨드라인 `--passL`로 링크 워커 수만
> 올릴 수 있고, 이 오버라이드는 산출 바이너리 digest에 영향을 주지 않는다(기계 실증 §4).
> **대상 독자**: 링크 wall-clock이 병목인 로컬 개발자; CI 빌드 플래그를 검토하는 리뷰어.

---

## §1. 기본값의 근거 (변경 금지 — L1-a 계약)

`config.nims` release 블록:

```nim
switch("passC", "-flto")
switch("passC", "-Wno-stringop-overflow")
switch("passL", "-flto -flto-partition=balanced -flto=2")
```

`-flto=2`는 L1-a 스크리닝(2026-08-30, `docs/reports/ci_l1a_lto_screening_p0_2026-08-30.md`)에서
채택된 CI 계약이다: 4GB CI 러너에서 peak RSS ≈1.9GB 실측(OOM 없음), 직렬 LTO 대비 link
wall-clock ≈32% 감소. GCC 문서상 `-flto-partition=balanced`는 partition별 IR을 동시 보유해
RSS가 상승하므로, 워커 수 상향은 CI 메모리 예산과 무관하지 않다 — **CI 기본 2는 그대로 둔다**.

## §2. 오버라이드는 이미 언어 네이티브로 존재한다 (config.nims 무변경)

Nim의 링커 인자 축적은 두 독립 슬롯으로 분리된다 (핀된 Nim 2.2.10, `compiler/extccomp.nim:523`):

```nim
result = conf.linkOptions & " " & conf.linkOptionsCmd & " "
#                   ↑ config 파일(nim.cfg/config.nims switch("passL"))  ↑ 커맨드라인 --passL
```

즉 **커맨드라인 `--passL` 인자는 항상 config 파일의 passL 이후에 append**된다. 공식 문서
(nimc.html, "Configuration files"): "command-line settings always take precedence over any values
defined within these files". GCC는 동일 옵션 반복 시 나중 값을 채택하므로(L1-a 보고서 §3 —
`--passL` override가 config 기본 뒤에 append되고 effective link flags에서 승리), 최종 링크
명령행은:

```
-flto -flto-partition=balanced -flto=2 -flto=16   →   effective = -flto=16 (워커 16, 파티션은 balanced 불변)
```

L1-a 측정 하네스(`tools/ci/lto_measure_shot.sh` `PASSL_OVERRIDE`)가 채택 플래그 산출에 사용한
것과 동일한 경로다 — 새 define·새 메커니즘 없이 언어 네이티브로 존재하므로 `config.nims`는
무변경으로 유지한다(최소 변경 원칙).

## §3. 사용법

```bash
# nim 직접 호출
nim c -d:release --passL:-flto=16 -o:bin/run_gate src/cli/run_gate.nim

# make 주도 빌드(checker.mk는 NIM ?= nim — env 오버라이드)
env NIM="nim --passL:-flto=16" make -f ci/checker.mk ci-compile-ax
```

워커 수는 실제 코어 수에 맞출 것(16코어 호스트에서 `-flto=16`). 주의: 병렬 LTO는 워커 수에
비례해 링크 시 peak RSS를 상승시킨다 — 메모리 여유가 없는 머신(VM·CI)에서는 기본값을 쓴다.

## §4. 결정론 — 오버라이드는 산출 digest에 무영향 (기계 실증)

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

## §5. 관련 문서

- `docs/reports/ci_l1a_lto_screening_p0_2026-08-30.md` — L1-a 채택 근거·oracle 동등성 실증
- `config.nims` release 블록 — 플래그 정본(SSOT)
- `docs/spec/config_nims_decomposition.md` — config.nims 구조
