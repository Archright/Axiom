# Source Merkle Root — Platform Hash Delegation

- **상태**: MERGED — PR #227, merge commit `e36677804b5ccb70ce6da7f3b88777878bafeebb` (2026-11-20T04:34:27Z, merge queue 경유)
- **날짜**: 2026-11-20
- **범위**: `computeSourceMerkleRoot`의 per-file SHA-256을 GNU coreutils `sha256sum` **단일 배치**에 위임. 판정·증거·인증서·저널 의미는 무변경.
- **완료 정의**: 코드 병합이 아니라 **보호된 main에서 재관측된 상태**. 이 문서는 그 관측과 한계를 기록한다.

---

## §1. 궁극적 목적과 이 슬라이스의 위치

Axiom은 "빠른 프로그램"이 아니라 **같은 입력에 대해 같은 신뢰 판정을 내리는 검증기**다. 따라서 최적화의 목적은 판정을 바꾸지 않고 **중복 연산과 대기만 제거**하는 것이다.

이 슬라이스는 그중 **Axiom이 직접 할 이유가 없는 연산**을 플랫폼에 넘긴다: 파일 바이트의 SHA-256. Axiom은 경로 탐색·정렬·레코드 조립·최종 루트·판정 권한을 계속 소유한다.

### 변경하지 않는 것 (명시)

| 대상 | 상태 |
|---|---|
| `computeSourceMerkleRoot`의 반환값 (동일 트리) | **byte-identical** (§4) |
| canonical projection / `subjectTreeMerkleRoot` | 무관 — 실제 생산자는 `measureSubjectTreeMerkleRoot` (`canonical_verification.nim:966-1016`) |
| evidence key / certificate identity 계열 | 무관 — `computeSourceMerkleRoot`는 evidence 소비자 **0** (§2 P2) |
| exit 의미, 판정 행, 게이트 임계값 | 무변경 |
| CI 토폴로지·캐시·러너·병렬성 | 무변경 |

---

## §2. Preflight (4 게이트 폐쇄)

### P1 — Track A(`--passC:-O2`) 판정: **변경 없음**

PR #122가 도입한 `--passC:-O2`는 **유지**한다. 근거는 레인 실측이다:

- GO-critical 레인(`test-fast-one`) 증분: **+0.25 s/test** (7.18 s vs 6.93 s), 실행 시간 증분 0.00 s.
- 전체 빌드 38 s → 90 s 악화는 **레인에 전이되지 않는다** — 레인은 개별 테스트를 `nim c -r`로 컴파일하며 지배 비용은 Nim 프론트엔드다.
- `test-fast-one`은 `admission-check`의 GO-critical 레인에서만 호출되고, #227의 PR 실행에서는 **skip**(로그 0회)이었다.

따라서 이 슬라이스는 컴파일 옵션을 바꾸지 않는다. `Makefile` 변경은 테스트 목록 1줄 추가뿐이며, §2.5 Epoch Cutover 분류는 **변경이 없으므로 moot**다. (초기 계획의 O2 제거/`-d:release` 도입/`--incremental:on`/sccache 도입은 각각 악화·의미 변경·AssertionDefect·이득 없음으로 **배제**했다.)

### P2 — evidenceId ↔ VerifierBuildId: 독립

`evidenceId = H(obligationId | propositionHash | leanSourceHash | kaaDigest | toolchainFingerprint | executionContractDigest [| completenessBindingDigest])` (`kernel_acceptance_authority.nim:448-459`). 이 전이 폐쇄에 `VerifierBuildId`·`BuildSourceHash`·`BuildEnvGitHash`는 **존재하지 않는다**. `src/`에서 유입 가능한 유일한 값은 `evalImplDigest`이며 정확히 3개 파일 + `Denotation.lean`만 덮는다.

`computeSourceMerkleRoot`의 소비자는 `global_symbol_graph.nim:60`, `stage_01_ast_extract.nim:61`(둘 다 캐시 지문), `tests/unit/test_vault_sync.nim`뿐이다.

**한정**: 내부 Axiom subject에서 `subjectGitRef = git rev-parse HEAD`이므로 **커밋 자체가 모든 evidenceId를 이동**시킨다. 따라서 "evidence key byte-identical" 주장은 **동일 트리 주장**이며 커밋 간 주장이 아니다. 이 머지에서 새 인증서는 `toolchainIdentity.engineBuild`와 Ed25519 서명이 갱신되고, 기존 저널 claim은 재증명 전까지 VKD에서 제외된다 — 이는 verifier identity churn이며 증거 오염이 아니다.

### P3 — `sha256sum` 계약 (GNU coreutils 9.4, `/usr/bin/sha256sum`)

- `--zero` 존재: 레코드 NUL 종료, **파일명 escaping 없음**. 레코드 = `<64 lowercase hex><SP><flag><name>`, flag `' '`/`'*'`.
- `--files0-from` **없음**(`unrecognized option`, exit 1) → argv만 사용.
- 출력 순서 = argv 순서, 중복 인자도 1:1 보존.
- 파일 하나라도 없거나 읽을 수 없으면 **exit 1**이며, **stdout에서 그 레코드가 조용히 누락**된다 → 위치 기반 매핑 금지, 이름 재검증 필수.
- 인자 없이 실행하면 stdin을 읽고 `-` 레코드를 출력(exit 0) → 빈 목록 호출 금지.
- `ARG_MAX` = 2,097,152. 가드: `Σ(len+1) + 8·(argc+3) ≤ 1,048,576`; 초과 시 위임하지 않고 in-process 경로를 사용한다.

### P4 — 측정 범위 (origin/main, 격리 worktree, n=5 median)

| 지표 | debug | release |
|---|---:|---:|
| `computeSourceMerkleRoot` (repo root, 2,572 `.nim`, 21.99 MB) | 8,258 ms | **198.6 ms** |
| prove `graph_hydration` phase | 8,623 ms | **268 ms** |
| walk+sort only | 96.1 ms | 20.1 ms |
| cache JSON load/parse | 269 ms | 49.7 ms |

release `graph_hydration`의 74.1%가 merkle pass이고, 그중 SHA 작업은 54.1%다. 해시 비용 0의 phase floor는 ≈123 ms.

**목표**: `graph_hydration ≤ 140 ms` / `computeSourceMerkleRoot ≤ 80 ms` (release, 무부하). 이전 `≤1,000 ms / ≤200 ms` 쌍은 측정 범위 없이 제시된 값이므로 철회한다. debug는 release의 41.6배이므로 debug 수치로 목표를 표현하지 않는다.

---

## §3. 구현

`src/core/symbol_graph/global_symbol_graph_builder_part2.nim`:

1. `parseDelegatedDigests` (pure `func`) — `sha256sum --zero` 출력을 경로 배열과 **정확히 1:1, 입력 순서, 말미 NUL**로 파싱. 64자리 lowercase hex, `rec[64]==' '`, `rec[65] ∈ {' ','*'}`, `name == paths[i]` byte-exact. 하나라도 어긋나면 빈 seq.
2. `computeSourceMerkleRoot` (기존 화이트리스트 proc) — `sha256sum --zero -- <paths>`를 **argv 배열**로 단일 실행(셸 문자열 없음). `findExe` 실패·exec 실패·비정상 종료·파싱 실패 시 **배치 전체 폐기** 후 기존 in-process `computeFileHash`로 재계산. 부분 배치 채택 없음.
3. 미사용 `std/hashes` import 제거 — `layer core max 25` import budget 유지(추가 2개 상쇄).

### 3.1 회전 delta의 형태 (allowlist 정합)

merge-queue 판정은 **B에서 빌드한 `bin/ax`**로 후보 delta의 모든 경로를 회전 allowlist(ADR-0025 A2)에 대조한다. 최초 후보는 자기 단위 테스트·증거 문서·`TESTS_FAST_UNIT` 등록까지 포함해 `ROT_ALLOWLIST`로 거부됐다(run `44668581737`; `oldAnchorOk`/`newAnchorOk`는 모두 true).

allowlist를 perf PR에서 확장하는 대신 delta를 **변경이 기계적으로 강제하는 4경로**로 축소했다:

- `src/core/symbol_graph/global_symbol_graph_builder_part2.nim` — 클로저 멤버(판정 영향 변경)
- `config/trusted_checker_closure.json` — 새 blob sha (`bin/reanchor_pin --write`)
- `data/architecture_debt.json` — entry 199 hash 재앵커 (`debt_engine --regen-arch`)
- `src/generated/type_registry_metadata.json` — `parseDelegatedDigests` 등록(생성물)

테스트·증거·Makefile 등록은 **이 후속 NORMAL PR**(클로저 멤버 미변경 → ROTATION 아님)로 분리했다. 구현·핀·부채 항목은 `6f2b123`과 byte-identical이다.

`Makefile`: `TESTS_FAST_UNIT`에 테스트 1줄 등록(테스트가 사문(死文)이 되지 않도록) — 이 PR에서 수행.

---

## §4. Correctness Acceptance

### 4.1 merged candidate (동일 트리)

`/tmp/merge-check`(`abcc12c` + PR head `6f2b123`, 충돌 0)에서 원본/위임 바이너리를 실행:

```
original  181.7 ms  root 9994f43d28d7dbebf7436bee21541e7ef198248e4b4fa69554dc650e9afd6cec
delegated  65.0 ms  root 9994f43d28d7dbebf7436bee21541e7ef198248e4b4fa69554dc650e9afd6cec
```

### 4.2 canonical main (post-merge, `e36677804`)

동일 트리(2,579 `.nim`, 21.01 MB)에서 in-process 경로(`probe-old`, `8bbb035` 빌드)와 위임 경로(`probe2`, main 빌드)를 **교차 실행**:

| n | old in-process (ms) | delegated (ms) | root |
|---:|---:|---:|---|
| 1 | 307.3 | 134.5 | `6b9e1a2b…a5d629f3` |
| 2 | 269.3 | 142.3 | 동일 |
| 3 | 302.0 | 132.2 | 동일 |
| 4 | 268.3 | 115.7 | 동일 |
| 5 | 280.8 | 139.4 | 동일 |
| **median** | **280.8** | **134.5** | **byte-identical 5/5** |

root 전체: `6b9e1a2ba86c3d39c22e7c476b3d26d607695e98b286e9b11effb0b6a5d629f3`.

### 4.3 회귀 테스트 — `tests/unit/test_source_merkle_delegation.nim`

| 테스트 | 고정하는 계약 |
|---|---|
| root is byte-identical to the in-process fold | 같은 트리에서 위임 결과 == `computeFileHash` fold. 공백·**개행**·한글 파일명, 빈 파일 포함 |
| root is deterministic across repeated calls | 반복 호출 동일 |
| unreadable-at-discovery tree falls back… | `PATH=""`로 `sha256sum` 부재 → 동일 루트(폴백이 결과를 오염시키지 않음) |
| empty tree folds to sha256 of the empty accumulator | 빈 트리 경계 |

실행: `make test-fast-one T=tests/unit/test_source_merkle_delegation.nim` → **4/4 PASS** (PR 이전 브랜치 `6f2b123` 및 이 PR에서 재확인).

### 4.4 게이트

| 게이트 | 결과 |
|---|---|
| PR required contexts + `admission-check` | **35 pass / 0 fail / 13 skip** (head `e0b79a3`) |
| merge_group `admission-gate` | **success** (run `44674123967`, 후보 `e36677804`) |
| `check-epoch-transaction` | PASS (4-way) |
| `check-repository-surface` | PASS (`changeCount: 0`) |
| `check-decision-binding` | PASS |
| `bin/reanchor_pin --ref HEAD` | `OK no-drift — pin@HEAD anchors derived(HEAD)` |
| `check-architecture` | **pre-existing FAIL** — `tests/architecture_constraints.nim:24` `cannot open file: std/parsetoml` (이 diff와 무관, pristine에서도 동일) |
| `check-debt` | **pre-existing DRIFT** — nimtry baseline drift가 pristine `origin/main`에서 동일 재현 (§7) |

---

## §5. Performance Acceptance

### 5.1 Pre-merge A/B — 무부하, 동일 트리·동일 캐시, interleaved, release, n=5

worktree `8bbb035a`, 동일 warm cache(2.98 MB)에서 base/new `ax prove` 교차 실행:

| run | base `graph_hydration` (ms) | new (ms) |
|---:|---:|---:|
| 1 | 240 | 117 |
| 2 | 249 | 139 |
| 3 | 271 | 124 |
| 4 | 242 | 120 |
| 5 | 243 | 125 |
| **median** | **243** | **124** |

- **−119 ms (−49%)**, 목표 `≤140 ms` 충족.
- merkle 단독: 184.8 → 67.8 ms (−63%), 목표 `≤80 ms` 충족.

### 5.2 Post-merge A/B — canonical main, interleaved, release, n=5

main(`e36677804`) 체크아웃에서 base(`bin/ax-base`, `8bbb035` 빌드 = in-process 경로)와 new(main `bin/ax`)를 교차 실행:

| pair | base (ms) | new (ms) |
|---:|---:|---:|
| 1 | 296 | 198 |
| 2 | 354 | 214 |
| 3 | 347 | 188 |
| 4 | 295 | 192 |
| 5 | 344 | 184 |
| **median** | **344** | **192** |

- **−152 ms (−44%)**, ratio 1.79 — 교차 측정이므로 부하에 독립적인 비율이다.
- **환경 명시**: 이 측정은 동시 빌드가 진행 중인 호스트에서 수행됐다(load average 6.9–11.0, 16 CPU / 30 GiB). 절대값은 무부하 §5.1보다 약 1.4배 부풀려져 있다(base 243 → 344). 따라서 **`≤140 ms` 절대 목표는 이 조건에서 판정하지 않는다** — 판정은 §5.1(무부하, 충족)이 담당하고, §5.2는 canonical main에서 비율이 유지됨을 보인다.
- 단일 바이너리 연속 실행 시 hydration: batch 1 `[1788(콜드), 232, 213, 208, 271]`, batch 2 `[255, 275, 324, …]` — 첫 실행은 캐시 재생성(콜드)이며 steady state는 부하 조건에서 200–320 ms다.

### 5.3 주장하지 않는 것

- **공식 Merge Queue SLO(P95 480초)**: 이 문서는 판정하지 않는다. 공식 고정 측정 창의 표본은 여전히 0이며, 이 슬라이스는 SLO 표본을 만들지 않는다(CI·러너·캐시·병렬성 무변경).
- debug 수치: release의 41.6배이며 debug 목표를 주장하지 않는다.
- cold(캐시 미스) 경로: release cold는 측정하지 않았다(debug cold 25,886 ms 관측).
- 부하 조건의 절대 시간: §5.2 참조.

---

## §6. 운영 상태 (관측 완료)

- [x] PR 생성 및 required contexts + `admission-check`(App 5795152) green — 35 pass / 0 fail
- [x] merge queue 경유 merge — `e36677804` (2026-11-20T04:34:27Z), merge_group admission-gate `success`
- [x] `origin/main`에서 재측정 — root 5/5 byte-identical, phase interleaved A/B −44%
- [x] `docs/evidence/` 갱신 — 이 문서 (후속 NORMAL PR)

---

## §7. 발견 사항과 후속

| 항목 | 상태 |
|---|---|
| `ROT_ALLOWLIST`로 인한 최초 후보 거부 (run `44668581737`) | **해소** — delta를 4경로로 축소(§3.1). allowlist 정책은 **확장하지 않음** |
| `stale base`로 인한 mint-prepare fail-closed (`PR base.sha cd7b1dea != main f7d73fd8`) | **해소** — `origin/main`을 브랜치에 병합해 base 갱신. 후속 PR 생성 시에도 base.sha 신선도 확인 필요 |
| `topology_analysis_cache.json` write-only 캐시 | **DEBT#561 등록 완료** (PR #231, merge `4f36457`) — 삭제/수정은 별도 |
| core purity 위반(`startProcess(`) | **PR #232 anchor 착지** (`abcc12c`) — 게이트는 B의 judge+baseline으로 H를 판정하므로 PR 자기 승인 불가 |
| `nimtry` baseline drift | **pre-existing**: pristine `origin/main`에서 동일 재현. baseline 덮어쓰기로 숨기지 않는다 |
| `tests/architecture_constraints.nim` `std/parsetoml` 부재 | pre-existing 환경 결손 |
| `global_symbol_graph.nim:60` 주석 `# cheap; full pass` | 실제로는 전체 순회. 별도 문서 정정 대상 |
| `binaryDigestMemo` `threadvar` | 13 MB digest가 스레드당 1회 중복 — 별도 분석 |
| Merge Queue P95 SLO | **미판정** — 공식 측정 창 표본 0. 별도 운영 작업 |
| pre-push hook 소요 (166–300 s, 예산 120 s) | 운영 정책 경고. 이 슬라이스의 범위 밖 |

---

## §8. 재현

```bash
# canonical main
git fetch origin && git switch main && git pull --ff-only
git log --oneline -1    # e36677804 Merge pull request #227

# 위임/원본 바이너리 (동일 트리 root 동등성)
nim c -d:release --hints:off --nimcache:/tmp/merkle-probe/nc2 \
  -o:/tmp/merkle-probe/probe2 build/tmp/merkle_probe.nim
/tmp/merkle-probe/probe-old . 5
/tmp/merkle-probe/probe2     . 5

# phase A/B (교차 실행; base는 8bbb035 빌드)
for i in 1 2 3 4 5; do
  AXIOM_CI=1 /tmp/axiom-baseline-wt/bin/ax-base prove --target normalizeMaxWorkers
  AXIOM_CI=1 ./bin/ax prove --target normalizeMaxWorkers
done
jq -r 'select(.detail=="graph hydration completed") | .elapsedMs' logs/ax_prove_trajectory.jsonl | tail -10

# 회귀 테스트
make test-fast-one T=tests/unit/test_source_merkle_delegation.nim
```