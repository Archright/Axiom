# VS-TOPOLOGY-CACHE-FASTPATH — warm `ax prove` 캐시 fast path acceptance (2026-11-21)

> 범위: `analyzeTopologySourceRootIncremental`의 영속 캐시(`.axiom/cache/topology_merkle.json`)가
> 설계된 `mtime+size` 가드를 실제로 만족하도록 고친 단일 변경(PR #300)의 동등성·성능 측정과
> canonical main 착지 후 재관측.
> 기록자 ≠ 승인자: 작성자는 agent, 승인자는 사용자(wintrover)다.
> 이 문서는 측정·관측만 기록한다. 판정 계약의 정의는 `docs/spec/productization_contract.md`가 소유한다.
> **이 수치는 로컬 16 CPU 호스트의 측정이며 CI Merge Queue SLO 측정값이 아니다.**

## §1. 기준점과 환경

| 항목 | 실측값 | 명령 |
|---|---|---|
| 변경 전 main | `bc20bf6` (PR #288 머지 직후) | `git log -1` |
| 변경 브랜치/커밋 | `perf/topology-cache-fastpath` / `0655127d627668d76486912ad476512f98141b2e` | `gh pr view 300 --json headRefOid` |
| 착지 merge commit | `1c9cdc1117816e49543270dc5b95e9e9800e204c` (PR #300, 2026-11-21T05:20:18Z) | `gh pr view 300 --json mergeCommit` |
| merge parents | `1aba7300a791b5a0c9254bfe54f46667d092226d` + `0655127d…` | `git log --format='%H %P' -1 1c9cdc1` |
| 호스트 | 16 CPU / 30 GiB / Linux 6.17.0-42-generic x86_64 | `nproc`, `free -g`, `uname -srm` |
| Nim | 2.2.10 | `nim --version` |
| toolchainIdentity | `nim-2.2.10\|lean-4.33.0\|z3-4.13.3\|int64bit\|linux-amd64\|…` | `ax report --json` |

## §2. 변경 인벤토리 (5 files, +118/−101)

| 파일 | 변경 |
|---|---|
| `src/core/topology/merkle_cache.nim` | `fileSize` 영속화(읽기 optional, 기본 0=unknown); `cachedSymbols` required 승격(엔트리는 스캔 완료 후에만 기록되므로 빈 배열 = "스캔 완료, 심볼 0"); compact JSON 직렬화 |
| `src/core/topology/topology_engine.nim` | 가드 일치 시 캐시 심볼(빈 배열 포함) 신뢰; content-hash hit 시 `lastModified`/`fileSize`를 stat으로 갱신; `cacheDirty` 노출 |
| `src/cli/topology_cli.nim` | dirty일 때만 `saveCache` |
| `data/architecture_debt.json` | `bin/debt_engine --regen-arch`로 canonical hash 재생성 |
| `config/trusted_checker_closure.json` | `bin/reanchor_pin --write`로 재앵커 |

캐시는 `.axiom/` 아래 gitignored 파생 상태이며 유일한 독자는 같은 CLI의 `loadCache`다.
분석은 영속화 전에 메모리에서 완료되므로 판정·증거는 파일에 의존할 수 없다.

## §3. 동등성 (동일 트리 `bc20bf6`, 두 바이너리 A/B)

`ax report --json` diff는 정확히 다음 세 부류뿐이었다.

| diff | 원인 | 판정 |
|---|---|---|
| `executionIdentity.verifierBuildId` | `src/**` 변경에 따른 정상 identity 회전 | 예상됨 |
| `totalWallTimeMs`, `depthStats`, gates timestamp | 타이밍 필드 | 판정 입력 아님 (R8) |
| `canonicalEvidence.obligationId` 2건 | `computeBoundObligationId`가 `subjectGitRef`(= HEAD 커밋)를 입력으로 받음 | `canonical_projection.nim`에서 `canonicalEvidence`는 volatile key — digest 제외 |

`nodeReports`, `summary`(symbolCount 16,743), `toolchainIdentity`, certificates는 동일.
`ax prove` exit 0, `normalizeMaxWorkers` verified, `failedCount: 0`.
`ax report --canonical-digest`는 고정 커밋에 대해 결정론적이다.

## §4. 성능

### 4.1 착지 전 A/B (`bc20bf6` 트리, warm, `AXIOM_CI=1 bin/ax prove --target normalizeMaxWorkers`)

| 관측 | 변경 전 | 변경 후 |
|---|---|---|
| `topology scan completed` (skTopology) | 938 ms | 468 ms (5회 중앙값) |
| prove wall | 5.30 s | 4.80 s |
| `topology:` 로그 | 2589 files, 569 changed | 2589 files, 0 changed |
| 캐시 기록 | 14.07MB pretty, 매 실행 | 9.29MB compact, dirty일 때만 |

### 4.2 착지 후 canonical main (`1c9cdc1`)

```bash
make build                                   # release recipe
AXIOM_CI=1 bin/ax prove --target normalizeMaxWorkers   # ×3
```

| 관측 | 값 |
|---|---|
| `make build` wall | 40.42 s |
| `bin/ax` | 13,400,408 B |
| `bin/ax --check-provenance` | `OK — embedded BuildSourceHash == live src tree` |
| prove exit / 판정 | 0 / `normalizeMaxWorkers` verified, `failedCount: 0`, `verificationSuccessRate: 1.0` |
| prove wall (3회) | 5029 / 4991 / 4938 ms — 중앙값 **4,991 ms** |
| `topology scan completed` (4회) | 464 / 477 / 477 / 483 ms — 중앙값 **477 ms** |
| `graph hydration completed` | 170–173 ms (migration 회차 716 ms) |
| `topology:` 로그 | 매 실행 `2592 files, 0 changed` |
| `ax report --canonical-digest` | `7b4c055564131483f0e8fcfad32098692883f0317cf6e6a419fb9ff578b4cefc` |
| `git status --porcelain` | empty |

착지 후 수치가 착지 전(468 ms / 4.80 s)보다 소폭 높은 것은 main이 25커밋 전진해
파일 수가 2589→2592, symbolCount가 16,743→16,752로 늘었기 때문이며 회귀가 아니다.
canonical digest도 동일 트리가 아니므로 착지 전 값과 비교 대상이 아니다.

## §5. 범위 밖 / 후속

- CI 정책·SLO·머지 큐 시간: 이 문서의 측정 대상이 아니다. 준수 여부를 주장하지 않는다.
- `--passC:-O2`, `-d:release`, sccache, `--incremental`: 이미 실측으로 종결된 항목(재론 금지).
- 배치 해싱은 Phase D에서 GNU `sha256sum --zero --` 단일 배치 위임으로 이미 완료.
- 남은 실행 비용(IR 윈도 4유닛 재계산 ~2,994 ms, graph hydration 171 ms, symbolNames 중복 416KB,
  z3 바이너리 in-process hash)은 계약·스키마·VKD 판정에 닿으므로 별도 계획 대상이다.