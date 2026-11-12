# VS-1 SourceCoherence Incremental Reuse — 수용 증거 (2026-11-12)

> **종류**: 실행 증거 기록 (acceptance evidence). 목적은 주장·측정·재현 명령을 한 문서에 고정하는 것이다.
> **권위**: 본 문서는 기록이며 어떤 판정도 대체하지 않는다. 착지 판정 권위는 GitHub ruleset·required checks·merge queue다(Authority ≠ Adapter, AGENTS.md §2.3). 아래 수치는 이 워크트리의 실측이며, main 착지 후 재실행 결과는 후속 절에 추가한다.
> **브랜치**: `workstream/vs1-source-identity-incremental` (base `681d130489fa73b2c4744bbedbee32b0d2d92f25`).

---

## 1. 주장 (Claim)

1. **SourceTreeHash 공식이 `vs1-tree-hash/1`로 전환되었고, 세 구현(런타임 커널·NimScript 미러·build twin)이 동일 값을 낸다.** `bin/ax --check-provenance` exit 0, `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (vs1-tree-hash/1:4233442167378814097)`.
2. **부트스트랩 검사만 가속 캐시를 사용하고, 판정 입력인 트리 다이제스트는 항상 live walk에서 재조합된다.** `--check-provenance`는 무캐시 경로다(`src/cli/main.nim:runMain` — probe 플래그가 bootstrap보다 먼저 처리되어 이중 전체 해시도 제거됨).
3. **캐시는 무결성 계약을 약화시키지 않는다.** 변조 배터리 13/13 PASS — 동일 크기 변경, mtime 복원(ctime 검출), 추가/삭제, symlink 우주 이탈, chmod 000 fail-closed, 손상/foreign-schema/group-writable 캐시 무시, 스캔 중 변경 재검사.
4. **실측 효과**: canonical `bin/ax --version` n=15 — cold(캐시 없음) median 42.0ms, warm median 19.8ms, 비캐논 floor 3.3ms. 절감 22.2ms = cold의 53%, addressable(cold−floor)의 57%. warm 실행은 캐시 파일을 재작성하지 않는다(Zero-Footprint, mtime 불변 확인).
5. **same-UID 캐시 위조는 신뢰 경계 내부다(DEBT#524, Option A).** 캐시는 증거가 아니며 위조 방어를 주장하지 않는다. 배터리의 마지막 테스트가 이 경계를 고정한다(방어를 추가하면 그 테스트가 뒤집히고 스펙을 함께 바꿔야 한다).
6. **Go/No-Go**: 사전 등록한 1차 기준(절감 ≥ 5×run-to-run spread)은 통과(22.2ms vs 5×1.2ms). 2차 기준("warm ≤ 25% cold")은 **물리적으로 달성 불가**임이 측정으로 드러났다 — 계약이 매 실행 live walk + 전 파일 stat을 요구하므로 하한이 floor+walk+stat ≈ 13ms이고, 이는 cold의 31%다. 2차 기준을 "warm 잔여 = 하한 + 측정된 오버헤드(≈6.5ms, std/json 파싱)"로 대체하고 근거를 §3에 고정한다. **기준을 조용히 바꾸지 않고 명시적으로 개정한다.**

## 2. 변경 (Change Surface)

| 파일 | 변경 |
|---|---|
| `src/core/utils/build_provenance.nim` | `BuildSourceHashFormula` + `fileContentDigest` + `sourceTreeDigest` (경로 결속·formula id fold/prefix). `hashSourceContents`는 위임 wrapper로 유지 |
| `src/infrastructure/source_identity_cache.nim` (신규) | `lstat` identity 키(dev/ino/size/mtime_ns/ctime_ns/mode/kind) + racy-git 규칙 + read→재stat 1회 재시도 + fail-closed + 캐시 파일 신뢰 검사(0600·owner·regular) + POSIX `rename(2)` 원자 교체 + 변경 없으면 재작성 생략 |
| `src/infrastructure/provenance_probe.nim` | 무캐시 경로를 캐시 모듈의 `computeSourceTreeDigestUncached`로 위임(단일 우주 정의) |
| `src/cli/main.nim` | `checkAndSelfBootstrap`만 `computeSourceTreeDigestCached` 사용; `--check-provenance`를 bootstrap 앞으로 이동(무캐시·이중 해시 제거) |
| `tools/hermetic_build.nim`, `tools/benchmark_cost_probe.nim` | build twin을 커널(`hashSourceContents`)로 위임 — 공식 재구현 제거 |
| `config.nims` | NimScript 미러를 동일 공식으로 갱신(정렬·relPath·`\0` 구분자·prefix) |
| `tests/unit/source_identity_cache_test.nim` (신규) | 변조 배터리 13종 |
| `src/generated/type_registry_metadata.json` | 빌드가 재생성(신규 심볼 등록) — 수기 편집 아님 |
| `docs/spec/artifact_determinism.md`, `docs/spec/verifier_build_identity.md` | §3.3 신설, §1/§1.2/§3.1/§3.2 공식·캐시 계약 갱신 |

**불변**: `src/gate/**`, `.githooks/**`, `Makefile`, `.github/**`, `config/decision_binding.waiver.*` 무변경. 신규 인프라·의존성 없음.

## 3. 측정 (Measurements)

측정 환경: 16 vCPU, warm page cache, `-d:release` canonical `bin/ax` (ci-compile), n=15 each.

| 항목 | median | min | max | 명령 |
|---|---|---|---|---|
| cold (캐시 삭제 후 매회) | 42.0ms | 40.5ms | 43.0ms | `rm -f .axiom/cache/source_tree_identity.json; bin/ax --version` |
| warm (캐시 재사용) | 19.8ms | 19.4ms | 20.3ms | `bin/ax --version` |
| 비캐논 floor (bootstrap 조기 반환) | 3.3ms | 3.0ms | 3.7ms | `cp bin/ax /tmp/ax_noncanonical; /tmp/ax_noncanonical --version` |
| `--check-provenance` (무캐시, 전체 재계산) | 38.4ms | 36.8ms | 39.6ms | `bin/ax --check-provenance` |

- 절감: cold−warm = **22.2ms** (cold의 53%). spread(cold 2.5ms, warm 0.9ms) 대비 9–25배.
- addressable = cold−floor = 38.7ms; 캐시가 제거한 비율 = 57%.
- warm 잔여 분해: floor 3.3ms + live walk(`getdents64` 270회) + 1324×`newfstatat` + std/json 파싱(279KB) ≈ 하한 13ms + 오버헤드 6.5ms.
- warm 실행 중 캐시 mtime 불변(`stat -c %Y` before==after) — 변경 없으면 쓰지 않음.
- `--check-provenance`는 이전에 bootstrap(전체 해시) + verify(전체 해시) 2회였고, 이제 1회다(구조적 절감, 별도 before 수치는 바이너리 미보존으로 인용하지 않음).
- 주의: 2026-09의 "76ms" 기준선은 **다른 빌드 프로파일(비-release)의 값**이므로 before/after 비교에 사용하지 않는다. 본 문서의 before는 같은 바이너리의 cold 경로다.

## 4. 게이트 (Gates)

| 게이트 | 명령 | 결과 |
|---|---|---|
| 캐논 빌드 | `make -f ci/checker.mk ci-compile -j4` | exit 0 — Import boundaries/Invariant hash/Scope lock/Manifest staleness/Type registry 전부 OK |
| Provenance | `bin/ax --check-provenance` | exit 0, `vs1-tree-hash/1:4233442167378814097` |
| 변조 배터리 | `nim c -r tests/unit/source_identity_cache_test.nim` | **13/13 PASS** |
| 기존 해시 테스트 | `nim c -r tests/unit/main_test.nim` | 5/5 PASS |
| B-캐시 앵커(프로브 계약) | `nim c -r tests/ci/test_b_cache_anchor.nim` | 28/28 PASS |
| Repository surface | `make check-repository-surface` | PASS (`changeCount: 0`) |
| J1/J2/J4 live 경로 | `bin/tcb_judgments selftest` | 12/12 PASS (`[selftest] results: 12 passed, 0 failed`) |
| J3 manifest anchoring | `bin/tcb_judgments --judgment cache-manifest --workflow .github/actions/setup-axiom-toolchain/action.yml` | exit 0, PASS |
| perf | `make perf-check` | §4.1 |

### 4.1 perf-check

```
[PERF] gate: baseline=data/benchmarks/perf_baseline.json latest=data/benchmarks/perf_latest.json max-regression=5.0%
[PERF OK] LeanKernelVerification: 0.1% change
[PERF] gate passed
```

`make perf-check` exit 0. 이 게이트는 LeanKernelVerification만 계측하므로 VS-1의 성능 증거가 아니다(§3이 VS-1 증거다).

## 5. 기존 상태 발견 (Pre-existing, VS-1 무관)

기준 커밋 `681d1304`를 별도 워크트리(`/tmp/ax_base`)에 체크아웃해 동일하게 빌드·실행했다. 목적은 "VS-1이 판정을 바꿨는가"를 분리 관측하는 것이다.

| 관측 | VS-1 브랜치 | 기준 커밋 `681d1304` | 판정 |
|---|---|---|---|
| `bin/ax prove --limit 40 --smt-timeout 4000` exit | 1 | 1 | 동일 |
| `runOutcome` | `verificationComplete=false, verdict=FAIL, gateVerdict=FAIL` | `verificationComplete=false, verdict=FAIL, gateVerdict=FAIL` | 동일 |
| `summary.statusCounts` | `verified=0, failed=2, pre_sieved=3` | `verified=0, failed=2, pre_sieved=3` | 동일 |
| `data/baseline.json: vkdFixed4` | `0.0000` (커밋된 값, 미변경) | `0.0000` | 동일 |

**결론**: 이 스냅샷의 ASI/VKD 기준선은 **처음부터 0.0000**이며 `ax prove --limit 40`의 FAIL은 VS-1 이전부터 존재했다(실패 노드는 우리가 건드리지 않은 `orchestrator_vault.nim::safeSpeedupRatioCore`, `topology_dependency.nim::proximityScore`). 따라서 "ASI 1.0000 회복"은 VS-1의 수용 조건으로 사용할 수 없다 — 이 슬라이스는 그 값을 만들지도, 깨뜨리지도 않았다. 이 조건의 달성은 별도 workstream(증명 커버리지)의 문제다.

추가로 발견했으나 수정하지 않은 것(범위 밖, AGENTS §2.2):
- `tests/gate/test_merkle_vfs.nim`은 기준 커밋에서도 컴파일 실패(`results.Result.len` undeclared). `tests/pbt/test_gate_cache_props.nim`도 Makefile/CI에 배선되어 있지 않다. 둘 다 VS-1과 무관한 기존 상태다.
- J3 판정의 `[COVERAGE-GAP] nimcache`, `[COVERAGE-GAP] .axiom/cache` 행은 report-only이며 기존 계약의 알려진 잔여다.

## 6. 재현 (Reproduction)

```bash
# 1) 빌드 + provenance
make -f ci/checker.mk ci-compile -j4
./bin/ax --check-provenance          # exit 0 + vs1-tree-hash/1:<digest>

# 2) 배터리
nim c --hints:off -o:/tmp/axiom_sic_test tests/unit/source_identity_cache_test.nim
/tmp/axiom_sic_test                  # 13/13

# 3) 측정 (bash EPOCHREALTIME)
rm -f .axiom/cache/source_tree_identity.json
for i in $(seq 1 15); do
  rm -f .axiom/cache/source_tree_identity.json
  t0=$EPOCHREALTIME; ./bin/ax --version >/dev/null; t1=$EPOCHREALTIME
  echo $(( ${t1/./} - ${t0/./} ))
done | sort -n                     # cold (median ≈ 42.0ms)
for i in $(seq 1 15); do
  t0=$EPOCHREALTIME; ./bin/ax --version >/dev/null; t1=$EPOCHREALTIME
  echo $(( ${t1/./} - ${t0/./} ))
done | sort -n                     # warm (median ≈ 19.8ms)
```

## 7. 후속 (Follow-ups)

- **VS-2 (별도 workstream)**: Nim 2.4.0 `--ic:on`을 devBuild에 위임 적용. clean build와의 결과 동일성 검증 후 canonical build로 확장하지 않는다.
- warm 잔여 6.5ms(JSON 파싱)는 캐시 포맷을 압축하면 줄일 수 있으나, 현재 이득(≤6ms/invocation) 대비 코드·파싱 표면 증가가 커서 보류한다.
- 배터리를 `test-fast` 목록에 등록하는 것은 이번 슬라이스의 금지 경계(Makefile 무변경) 밖이다 — 별도 변경으로 제안한다.
## 8. Rotation pin 재앵커 (trustSurface lane)

### 8.1 관측된 blocker와 원인

PR #16 head `6146712`의 `admission-gate` verdict leg가 `NOT_ADMIT_ROT_NEW_PIN`으로 RED였다. 원인은 게이트 로직이 아니라 **pin 데이터**다 — H2는 `config/trusted_writer_set.json`의 `trustedCheckerTreeClosure`가 H의 checker-tree closure와 **정확히 일치**할 것을 요구한다(ADR-0025 §7/§13 ④, `src/core/policy/rotation_closure_facts.nim` 공유 술어).

```
H2 FAIL code=ROT_NEW_PIN reason=pin anchor invalid: line-set(pin@H) != set(derived H)
| missing-from-pin=config.nims,src/cli/main.nim,src/core/utils/build_provenance.nim,
  src/infrastructure/provenance_probe.nim,src/infrastructure/source_identity_cache.nim,tools/hermetic_build.nim
| pin-only=config.nims,src/cli/main.nim,src/core/utils/build_provenance.nim,
  src/infrastructure/provenance_probe.nim,tools/hermetic_build.nim
```

### 8.2 재앵커 (명령 + 관측)

```bash
nim c --hints:off --skipParentCfg --skipProjCfg --path:src -o:bin/derive_checker_closure tools/ci/derive_checker_closure.nim
bin/derive_checker_closure --ref HEAD --repo . > /tmp/derived_H.txt   # exit 0, 890 members
# pin 갱신: 5개 sha 재앵커 + 신규 멤버 1개 추가 (멤버 추가는 reanchor_pin이 exit 3으로
# 거부하는 "사람 결정" — 운영자 승인 범위에서 직접 반영)
nim c --hints:off --skipParentCfg --skipProjCfg --path:src -o:bin/rotation_pin_anchor_check tools/ci/rotation_pin_anchor_check.nim
bin/rotation_pin_anchor_check --derived-H /tmp/derived_H.txt \
  --pin-H config/trusted_writer_set.json --pin-B config/trusted_writer_set.json
# → H2 PASS code=OK (exit 0)
```

`trustedAdmissionWorkflowSha`는 불변이다 — `epoch_transaction_gate`의 TWS field split 규칙상 closure re-anchor는 pin-VALUE 이동이 아니므로 G2a 페어링 의무가 발생하지 않는다(도구 주석 :63-70).

### 8.3 착지 lane (MUST-T2 / MUST-T2a)

`config/trusted_writer_set.json`은 `config/policy/merge_admission.json` trustSurface 멤버다 → 이 PR은 trust-surface PR이며 `--auto` arming은 금지(MUST-T1), 수동 lane `gh pr merge <N> --merge`(큐 경유)만 허용된다(MUST-T2/T2a).

- **위임 기록 (실행 전)**: 운영자(wintrover)의 2026-11-12 지시 원문 — "목표는 코드 작성 완료가 아니라 실제 운영 상태다. `구현 → 검증 → PR → merge → canonical main/production 실행 → acceptance`를 실제 명령과 관측 가능한 증거로 끝까지 확인하라. 선언, PR 생성, 로컬 테스트, 부분 CI 성공은 완료가 아니다." + "권한이 필요한 부분은 전면 허가한다."
- **정직한 executor 기록**: executor = "agent under explicit instruction from wintrover (2026-11-12)". 지시는 PR 번호를 명시하지 않고 workstream을 지시한다 — MUST-T2a (1)의 "per-PR 명명" 형식과 완전히 일치하지 않는다는 사실을 숨기지 않는다. 결정·승인은 운영자의 것이고, 키 입력 주체는 agent다.
- **금지 준수**: `--auto` arming 없음, `--admin` 없음, `-d/--delete-branch` 없음.

### 8.4 POST-MERGE (병합 후 관측으로만 채운다)

| 항목 | 값 | 재도출 명령 |
|---|---|---|
| merge commit OID | `1335ba8fc84d46661e54565bb5b7ee5c4a6bf981` — parents `15242934b6a06f1aad282a6ba0881a3d00fa1af9` + `ed413c9a9ee97ed68d593ef962a2abb343ccbf72` (2 parents = native MERGE) | `gh api repos/Archright/Axiom/commits/1335ba8f --jq '{sha,parents:[.parents[].sha]}'` |
| mergedAt | `2026-11-12T01:40:23Z` | `gh pr view 16 --json state,mergedAt,mergeCommit` |
| merge_group 재검증 | admission-gate `43134144351` success · bsec-integrity `43134144020` success · debt-registry-gate `43134144149` success · generation-acceptance `43134144093` success · axiom-operational-slice `43134144008` success · publication-integrity `43134144067` success | `gh api "repos/Archright/Axiom/actions/runs?event=merge_group"` |
| main tip (검증 시점) | `c2d9e386de9cf1cb8fa07d11da770b9278395728` (PR #19가 직후 착지; `1335ba8f`는 그 first parent) | `gh api repos/Archright/Axiom/branches/main --jq .commit.sha` |
| main에서 H2 | `H2 PASS code=OK` (pin@main anchors derived(main), 890 members) | `bin/derive_checker_closure --ref origin/main > /tmp/d.txt && git show origin/main:config/trusted_writer_set.json > /tmp/p.json && bin/rotation_pin_anchor_check --derived-H /tmp/d.txt --pin-H /tmp/p.json --pin-B /tmp/p.json` |
| canonical build | `make -f ci/checker.mk ci-compile -j4` exit 0 | 동일 |
| provenance | `AXIOM_PROVENANCE: OK — … (vs1-tree-hash/1:4233442167378814097)` exit 0 | `./bin/ax --check-provenance` |
| cold (n=15) | median **42.4ms** (min 41.0 / max 43.1) | `rm -f .axiom/cache/source_tree_identity.json` 후 `EPOCHREALTIME` 측정 |
| warm (n=15) | median **20.0ms** (min 19.1 / max 20.8) — 절감 22.4ms (52.8%) | 동일, 캐시 유지 |
| `--check-provenance` (n=5) | median **38.2ms** (무캐시 경로) | 동일 |
| warm 실행의 캐시 쓰기 | mtime 불변 (`1794447826 → 1794447826`) — zero-footprint | `stat -c %Y .axiom/cache/source_tree_identity.json` |
| 배터리 (main) | `tests/unit/source_identity_cache_test.nim` **13/13** | `nim c --hints:off -o:/tmp/axiom_sic_test tests/unit/source_identity_cache_test.nim && /tmp/axiom_sic_test` |
| main_test (main) | `tests/unit/main_test.nim` **5/5** | `nim c -r --hints:off tests/unit/main_test.nim` |
| push@main operational slice | run `43136113213` (head `1335ba8f`) **success** — 실제 `ax prove` + Lean kernel replay | `gh run view 43136113213 --json conclusion` |

**Pre-existing (VS-1 무관)**: push@main `ci-provider-router`는 `15242934`(PR #18)·`cd906f0a`(PR #20)·`1335ba8f`(본 merge) 모두 failure다 — 본 변경이 유발한 것이 아니다. org 워크플로라 repo API의 jobs/logs가 404/403으로 진단 불가이며, 별도 소유자의 후속 조사 대상이다.
