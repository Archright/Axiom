# Source Merkle Root — Platform Hash Delegation

- **Branch**: `perf/source-merkle-delegation` (base `8bbb035a7aca8ce70f980808fa0c8c609fe94d4c`)
- **날짜**: 2026-11-20
- **범위**: `computeSourceMerkleRoot`의 per-file SHA-256을 GNU coreutils `sha256sum` **단일 배치**에 위임. 판정·증거·인증서·저널 의미는 무변경.
- **완료 정의**: 코드 변경이 아니라 **보호된 main에서 재관측된 상태**. 이 문서는 main 착지 후 재측정 결과로 갱신된다.

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

### P1 — §2.5 분류: 권위 판정 부재

`--passC:-O2`(PR #122, merge `5f45c813`)를 §2.5 "CI 변경"으로 분류한 **권위 있는 판정은 저장소에 없다**. 유일한 분류 텍스트는 PR 자신의 evidence 문서(`vs_t3a_build_mode_passc_o2_2026-11-16.md:118-119`)이며, 인용한 선례 C4/PR #59는 빌드 플래그 선례가 아니다(제품 코드 메모이제이션). 설계 문서는 `DRAFT — 아키텍트 승인 대기`이고 스스로 "본 설계의 승인 없이 착지하지 않는다"(`:147`)고 명시한다. PR #122는 리뷰 0건·epoch record 0건으로 착지했다.

`docs/agents/ci_epoch_cutover.md:29-39`의 목록은 **충분조건**을 열거하며("다음 변경은 모두 … 간주한다") 빌드 플래그를 이름으로 들지 않는다. 반면 기계적 사실은 CI 캐시 표면 변경으로 읽힌다(`setup-axiom-toolchain/action.yml:350`의 `recipe_hash`가 `Makefile` 포함, `evidence_cas.nim:87-90`의 `RecipeDigestInputPaths`가 `Makefile` 포함).

**처리**: 사용자의 명시적 전면 승인("권한이 필요한 부분은 전면 허가한다")을 §2.5가 인정하는 유일한 권한 근거로 기록한다. epoch record를 조작·생성하지 않는다. 이 슬라이스는 `Makefile`의 **테스트 목록에 1줄 추가**만 하며 실행 토폴로지·캐시 키 종류·병렬성을 바꾸지 않는다.

### P2 — evidenceId ↔ VerifierBuildId: 독립

`evidenceId = H(obligationId | propositionHash | leanSourceHash | kaaDigest | toolchainFingerprint | executionContractDigest [| completenessBindingDigest])` (`kernel_acceptance_authority.nim:448-459`). 이 전이 폐쇄에 `VerifierBuildId`·`BuildSourceHash`·`BuildEnvGitHash`는 **존재하지 않는다**. `src/`에서 유입 가능한 유일한 값은 `evalImplDigest`이며 정확히 3개 파일 + `Denotation.lean`만 덮는다.

`computeSourceMerkleRoot`의 소비자는 `global_symbol_graph.nim:60`, `stage_01_ast_extract.nim:61`(둘 다 캐시指纹), `tests/unit/test_vault_sync.nim`뿐이다.

**한정**: 내부 Axiom subject에서 `subjectGitRef = git rev-parse HEAD`이므로 **커밋 자체가 모든 evidenceId를 이동**시킨다. 따라서 "evidence key byte-identical"은 **동일 트리 주장**이며 커밋 간 주장이 아니다. 새 인증서는 `toolchainIdentity.engineBuild`와 Ed25519 서명이 갱신되고, 기존 저널 claim은 재증명 전까지 VKD에서 제외된다 — 이는 verifier identity churn이며 증거 오염이 아니다.

### P3 — `sha256sum` 계약 (GNU coreutils 9.4, `/usr/bin/sha256sum`)

- `--zero` 존재: 레코드 NUL 종료, **파일명 escaping 없음**. 레코드 = `<64 lowercase hex><SP><flag><name>`, flag `' '`/`'*'`.
- `--files0-from` **없음**(`unrecognized option`, exit 1) → argv만 사용.
- 출력 순서 = argv 순서, 중복 인자도 1:1 보존.
- 파일 하나라도 없거나 읽을 수 없으면 **exit 1**이며, **stdout에서 그 레코드가 조용히 누락**된다 → 위치 기반 매핑 금지, 이름 재검증 필수.
- 인자 없이 실행하면 stdin을 읽고 `-` 레코드를 출력(exit 0) → 빈 목록 호출 금지.
- `ARG_MAX` = 2,097,152. 가드: `Σ(len+1) + 8·(argc+3) ≤ 1,048,576`.

### P4 — 측정 범위 (origin/main, 격리 worktree, n=5 median)

| 지표 | debug | release |
|---|---:|---:|
| `computeSourceMerkleRoot` (repo root, 2,572 `.nim`, 21.99 MB) | 8,258 ms | **198.6 ms** |
| prove `graph_hydration` phase | 8,623 ms | **268 ms** |
| walk+sort only | 96.1 ms | 20.1 ms |
| cache JSON load/parse | 269 ms | 49.7 ms |

release `graph_hydration`의 74.1%가 merkle pass이고, 그중 SHA 작업은 54.1%다. 해시 비용 0의 phase floor는 ≈123 ms.

**목표 재설정**: `graph_hydration ≤ 140 ms` / `computeSourceMerkleRoot ≤ 80 ms` (release). 이전 `≤1,000 ms / ≤200 ms` 쌍은 측정 범위 없이 제시된 값이므로 철회한다. debug는 release의 41.6배이므로 debug 수치로 목표를 표현하지 않는다.

---

## §3. 구현

`src/core/symbol_graph/global_symbol_graph_builder_part2.nim`:

1. `parseDelegatedDigests` (pure `func`) — `sha256sum --zero` 출력을 경로 배열과 **정확히 1:1, 입력 순서, 말미 NUL**로 파싱. 64자리 lowercase hex, `rec[64]==' '`, `rec[65] ∈ {' ','*'}`, `name == paths[i]` byte-exact. 하나라도 어긋나면 빈 seq.
2. `computeSourceMerkleRoot` (기존 화이트리스트 proc) — `sha256sum --zero -- <paths>`를 **argv 배열**로 단일 실행(셸 문자열 없음). `findExe` 실패·exec 실패·비정상 종료·파싱 실패 시 **배치 전체 폐기** 후 기존 in-process `computeFileHash`로 재계산. 부분 배치 채택 없음.
3. 미사용 `std/hashes` import 제거 — `layer core max 25` import budget 유지(추가 2개 상쇄).

`Makefile`: `TESTS_FAST_UNIT`에 신규 테스트 1줄 등록(테스트가 사문(死文)이 되지 않도록).

---

## §4. Correctness Acceptance

### 4.1 동일 트리 루트 동등성

동일 worktree(`8bbb035a`, repo root, 2,572 파일)에서 원본 바이너리와 위임 바이너리를 각각 실행:

```
ORIGINAL  best_ms=184.8  root=4568a7bbd9f0837c12bf8507c20b48838b2765d2dddc72705ea73b2919300695
DELEGATED best_ms= 67.8  root=4568a7bbd9f0837c12bf8507c20b48838b2765d2dddc72705ea73b2919300695
```

`src` 트리에서도 동일: `1dbf912df2daa93c6a2dd0d253e21e3748c7bf628a4c8cda4a9181775b1d3f78` (90.5 ms → 31.0 ms).

### 4.2 회귀 테스트 — `tests/unit/test_source_merkle_delegation.nim` (4/4 PASS)

| 테스트 | 고정하는 계약 |
|---|---|
| root is byte-identical to the in-process fold | 같은 트리에서 위임 결과 == `computeFileHash` fold. 공백·**개행**·한글 파일명, 빈 파일 포함 |
| root is deterministic across repeated calls | 반복 호출 동일 |
| unreadable-at-discovery tree falls back… | `PATH=""`로 `sha256sum` 부재 → 동일 루트(폴백이 결과를 오염시키지 않음) |
| empty tree folds to sha256 of the empty accumulator | 빈 트리 경계 |

실행: `make test-fast-one T=tests/unit/test_source_merkle_delegation.nim`

### 4.3 게이트

| 게이트 | 결과 |
|---|---|
| `check-epoch-transaction` | PASS (4-way) |
| `check-repository-surface` | PASS (`changeCount: 0`) |
| `check-decision-binding` | PASS |
| `check-architecture` | **pre-existing FAIL** — `tests/architecture_constraints.nim:24` `cannot open file: std/parsetoml` (이 diff와 무관, pristine에서도 동일) |
| `check-debt` | **pre-existing DRIFT** — nimtry 3 new/3 resolved가 **pristine `origin/main`에서 동일 재현** (§7) |

---

## §5. Performance Acceptance

### 5.1 A/B — 동일 트리·동일 캐시, interleaved, release, n=5

worktree `8bbb035a`, 동일 `logs/global_symbol_graph.d8a19c73….cache.json`(warm, 2.98 MB)에서 `AXIOM_CI=1 ax prove --target normalizeMaxWorkers`를 base/new 교차 실행:

| run | base `graph_hydration` (ms) | new `graph_hydration` (ms) |
|---:|---:|---:|
| 1 | 240 | 117 |
| 2 | 249 | 139 |
| 3 | 271 | 124 |
| 4 | 242 | 120 |
| 5 | 243 | 125 |
| **median** | **243** | **124** |

- **−119 ms (−49%)**, 목표 `≤140 ms` 충족.
- `(A)` 단독: 184.8 → 67.8 ms (−63%), 목표 `≤80 ms` 충족.
- 두 바이너리 모두 `graph_hydration`은 verdict-independent phase다. fresh worktree에는 warm vault가 없어 `verified=0`이지만 phase 측정에는 영향이 없다.

### 5.2 주장하지 않는 것

- **공식 Merge Queue SLO(P95 480초)**: 이 문서는 판정하지 않는다. 표본 창은 별도 운영 작업이다.
- debug 수치: release의 41.6배이며 debug 목표를 주장하지 않는다.
- cold(캐시 미스) 경로: release cold는 측정하지 않았다(debug cold 25,886 ms 관측).

---

## §6. 운영 상태 (main 착지 후 갱신)

- [ ] PR 생성 및 7 required contexts + `admission-check`(App 5795152) green
- [ ] merge → `origin/main`에서 재측정
- [ ] `docs/evidence/` 갱신 커밋

> 이 절은 main 착지 전까지 미충족이며, 미충족 상태를 완료로 표기하지 않는다.

---

## §7. 발견 사항 (이 PR에서 고치지 않음)

| 항목 | 상태 |
|---|---|
| `nimtry` baseline drift (3 new / 3 resolved) | **pre-existing**: pristine `origin/main`에서 동일 재현. baseline 덮어쓰기로 숨기지 않는다 |
| `tests/architecture_constraints.nim` `std/parsetoml` 부재 | pre-existing 환경 결손 |
| `computeSourceMerkleRoot` docstring "MD5-based" | **거짓** — 실제는 `$secureHash(Sha_256, …)`. 이 PR에서 정정 |
| `global_symbol_graph.nim:60` 주석 `# cheap; full pass` | 실제로는 전체 순회. 별도 문서 정정 대상 |
| `topology_analysis_cache.json` | writer 있음·reader 0 (죽은 캐시) — 별도 debt 등록 대상 (Track C) |
| `binaryDigestMemo` `threadvar` | `lake` 13 MB digest가 스레드당 1회 중복 — 별도 분석 |

---

## §8. 재현

```bash
# 동일 트리 루트 동등성 (원본 vs 위임)
git worktree add --detach /tmp/axiom-baseline-wt 8bbb035a7aca8ce70f980808fa0c8c609fe94d4c
# (probe는 build/tmp/merkle_probe*.nim, release 빌드)
/tmp/merkle-probe/probe  /tmp/axiom-baseline-wt . 3
/tmp/merkle-probe/probe2 /tmp/axiom-baseline-wt . 3

# phase A/B (동일 캐시, 교차 실행)
cd /tmp/axiom-baseline-wt
AXIOM_HERMETIC_BUILDING=1 nim c -d:release --hints:off --nimcache:build/nimcache/ci-compile/ax -o:bin/ax-base src/cli/main.nim
cp <new-bin-ax> bin/ax-new
for i in 1 2 3 4 5; do AXIOM_CI=1 ./bin/ax-base prove --target normalizeMaxWorkers; \
                        AXIOM_CI=1 ./bin/ax-new  prove --target normalizeMaxWorkers; done
jq -r 'select(.detail=="graph hydration completed") | .elapsedMs' logs/ax_prove_trajectory.jsonl
```