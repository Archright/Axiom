# ACT2-R0 Campaign Re-anchor — R0-E Reproduction Report

- 실험 ID: `experiments/act2-r0-reanchor/` (워크스페이스: `Axiom-worktree-r0`, branch `feature/act2-r0-reanchor`)
- 산출일: 2026-10-01
- 정본 산출물: `r0-evidence-manifest.json` · `reproduction.json` · `execution_authority.json` · `subject_authority.json` · `coverage-matrix.json` (+`.md`) · `restored_evidence_checksums.txt` · `reproduction_v1.json`(v1 보존본) · `self_check.md`

## Question

8월 31일에 끊긴 Act2 외부검증 캠페인의 권위 사슬을 복구하기 위해, 최신 Axiom 바이너리(827329cbd 재빌드)로 fresh state에서 `stew/bitops2.nim::getBitsBE` 타깃 재관측을 수행하고, (a) 역사 WP4j34 결과와 **동일 의미론 클래스(same-class)** 인지, (b) 실행 ingress가 **선언 manifest에 완전히 포함**되는지(미선언 0), (c) 네트워크/AF_UNIX IPC가 OS 격리+strace 검증 하에서 **0건 or 목록화**되는지를 기계적으로 판정한다.

정본 등식: `Canonical result = Subject(ingressDigest) × Execution(axiomCommit·axBinarySha256·executionIngressDigest·toolchainDigest) × State(stateSeedDigest) × Env(envAllowlist)`.

## Context

- **Subject revision**: `nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859` (`origin/master` 일치), read-only. `git status --porcelain` = `?? data/` 1줄만.
- **Axiom revision**: `axiomCommit=827329cbd8a95d614c09aa600cb7385307e66178`(40자), `buildEnvCommitCount=1910`, `buildSourceHash=2739333566168504023`, `axBinarySha256=fd7c36b1026c78605a5fac72d9a06edb468eb2f1aa805373873f541e4da3884b`(재빌드, `bin/ax --version` exit 0 = SourceCoherence PASS).
- **WORKTREE 이관 사실**: 기존 작업 트리 `Axiom-worktree`는 외부 세션이 소유하여 접근 금지 상태가 되어, 동일 브랜치 `feature/act2-r0-reanchor`@`827329cbd`를 새 worktree `Axiom-worktree-r0`로 이관하여 모든 v2/v3 실행을 수행했다. v1 실행은 구 `Axiom-worktree`에서 수행됨. 이관 전후 HEAD 동일(827329cbd)이며, 관측된 repo 파일들의 내용 동일성은 선언 manifest의 path→sha256(4688 entry)로 결속된다(이관 전후 파일 각각에 대해 별도 해시 검증은 수행하지 않음 — Non-Conclusions 참조).
- **Configuration**: `bin/ax prove --project <nim-stew> --target stew/bitops2.nim::getBitsBE --limit 1`, `AXIOM_STATE_DIR=fresh state`, env allowlist + amendments(§Procedure).
- **Toolchain identity**: nim-2.2.10 | lean-4.33.0 | z3-4.13.3 (표시용 metadata; authority = `toolchainDigest`). elan shim(`.elan/bin/lake`·`lean`, sha256 e0f4b30b29c5…) → 실바이너리: lake 60330ab6f07d…, lean e8baaa71855a…, z3 `<user-home>/.local/bin/z3` 4c13bd5b2526… (모두 선언 manifest에 path→sha256로 포함).
- **VERIFICATION_SCOPE**: `repo:data/verification_scope.lock`(stateSeed 경유) + `--target` 1건.
- **EXPERIMENT_ID**: `ACT2-R0` / `experiments/act2-r0-reanchor`.

## Scope

분석 대상:

- subject ingress closure(`*.nim`+`*.nims`+`axiom.toml(부재)`) — `subject_authority.json` (ingressManifest 87 entry, ingressDigest `978d8269…`)
- 실행 ingress 선언(관측분 승격): `repo:src/**` 1294 파일+136 dir, `repo:.lake` 프로브(absent), `subject:.git/**`·`.gitignore`·dir 목록(48 entry), `toolchain:.elan` 성공 읽기 3166+absent 27, `repo:bin/ax`, 바이너리 4종 — **executionIngressManifest 4,688 entry, digest `2237e13ab4edf759ac590879210de69e6f355e0e1991fcfe8451793e0adc33fd`**
- state seed 3종(`verification_scope.lock`·`baseline.json`·`universe_merkle.lock absent-fresh`) + dir scaffold 5건 → stateSeedDigest `34b5e10f081968ad80b557e23d36abbcaddd1d12440b7daacc83b3f5178daf7a`
- env allowlist 8변수 + amendments 3건(아래)
- strace 관측(`openat/openat2/execve/socket/connect`)의 logical 매핑 및 선언 대조

제외:

- archival 17개 evidence 의무 추적, 8월 dirty-state 재구성, `base36.decodedLength` 등 다른 OPEN 타깃, R0-L(랜딩) 전 과정, Axiom 제품 코드·AGENTS.md·게이트 수정
- system 파일(`/etc/ld.so.cache`·libc·locale·nsswitch·`/dev/urandom` 등) = **OS runtime baseline으로 excluded class** — 프로젝트 ingress 아님(v1·v3 동일 관측, 문서화)
- 실패 프로브(ENOENT/EACCES) = 바이트 미유입 → 비-ingress(absent/규칙으로 목록화)

## Procedure

실행 사다리: `stew/bitops2.nim::getBitsBE`(1순위 성공 — `--target filter: 1 node(s) match` 1정확 매치, 사다리 2/3순위 불필요 기록).

**v1 (원본 관측, 구 worktree, HOME 실사용):**

```bash
cd .-worktree      # 구 worktree (외부 세션 소유 — 이후 접근 금지)
export STATE=/tmp/act2r0_witness_1790821709
strace -f -e trace=openat,openat2,execve,socket,connect -o "$STATE/execution_observe.log" \
  unshare -rni -- env -i PATH="$PATH" HOME=<user-home> TMPDIR="$STATE/tmp" \
      AXIOM_STATE_DIR="$STATE" LANG=C LC_ALL=C \
      bin/ax prove --project <workspace>/nim-stew \
                   --target stew/bitops2.nim::getBitsBE --limit 1
# → exit 2, same-class, AF_INET 0, AF_UNIX nscd 20건(ENOENT), 미선언 ingress 다수(manifest 13 entry 한계)
```

**v2 (보정 1차 재실행 — HOME 중립화 + GIT_CONFIG_NOSYSTEM):**

```bash
cd .-worktree-r0
export STATE2=/tmp/act2r0_witness_v2_$(date +%s); mkdir -p "$STATE2/data" "$STATE2/tmp" "$STATE2/home" "$STATE2/.axiom/cache"
cp data/{verification_scope.lock,baseline.json} "$STATE2/data/"   # universe_merkle.lock: absent-fresh
strace -f -e trace=openat,openat2,execve,socket,connect -o "$STATE2/execution_observe_v2.log" \
  unshare -rni -- env -i PATH="$PATH" HOME="$STATE2/home" TMPDIR="$STATE2/tmp" \
      AXIOM_STATE_DIR="$STATE2" LANG=C LC_ALL=C GIT_CONFIG_NOSYSTEM=1 \
      bin/ax prove --project <workspace>/nim-stew \
                   --target stew/bitops2.nim::getBitsBE --limit 1
# → exit 0, DIVERGENT: elan shim이 $HOME/.elan 부재로 툴체인 발견 실패 → 다운로드 시도(netns 차단,
#   DGRAM DNS 소켓 6건 관측) → "Lean compiler dysfunctional", executionComplete=false, statusCounts=null
```

**v3 (정본 — env allowlist amendment 후 재실행):**

```bash
cd .-worktree-r0
export STATE3=/tmp/act2r0_witness_v3_$(date +%s); mkdir -p "$STATE3/data" "$STATE3/tmp" "$STATE3/home" "$STATE3/.axiom/cache"
cp data/{verification_scope.lock,baseline.json} "$STATE3/data/"   # universe_merkle.lock: absent-fresh
strace -f -e trace=openat,openat2,execve,socket,connect -o "$STATE3/execution_observe_v3.log" \
  unshare -rni -- env -i PATH="$PATH" HOME="$STATE3/home" ELAN_HOME=<user-home>/.elan TMPDIR="$STATE3/tmp" \
      AXIOM_STATE_DIR="$STATE3" LANG=C LC_ALL=C GIT_CONFIG_NOSYSTEM=1 \
      bin/ax prove --project <workspace>/nim-stew \
                   --target stew/bitops2.nim::getBitsBE --limit 1
# → exit 2 ✅ same-class (전 항목 v1 대조)
```

env allowlist amendments(전부 기록됨, `r0-evidence-manifest.json`):

1. `HOME → state home scaffold` — git config 중립화(v1 `~/.gitconfig` 18회·`~/.config/git/ignore` 5회 → v2/v3 0회)
2. `GIT_CONFIG_NOSYSTEM=1` — `/etc/gitconfig` system config 배제(v1 1회 → v2/v3 0회)
3. `ELAN_HOME=<user-home>/.elan` — elan 툴체인 발견 유지(v2 divergence 근거로 추가; HOME은 계속 중립)

분석 절차:

```bash
python3 /tmp/ingress_parse_v3.py <log> <STATE> <REPO> <SUBJECT> --out <parsed>.json   # v3 파서(pid-cwd 추론, 성공/실패/dir 분류)
python3 /tmp/build_manifest_v2.py        # v1 관측분 → 선언 manifest(digest 2237e13a…)
# 관측(성공 읽기+execve+dir) ⊆ 선언(executionIngressManifest ∪ subject ingressManifest) 대조 → 미선언 0
```

## Result

정본(v3) — 기계 관측:

| 항목 | 값 |
|---|---|
| exit | **2** (gateVerdict FAIL, v1과 동일) |
| same-class | **성립 — 4중 일치**(아래 Evidence) |
| nodeId | `stew/bitops2.nim::getBitsBE` (frontier 1 node match) |
| statusCounts | verified 0 · pre_sieved 1 · 나머지 전부 0 (`summary.preSieved=1, failedCount=0, …`) |
| proofSummary | IR pipeline Total 6 · Pass 3 · Fail 3 (getBitsBE psFail smBMC/pkZ3Bmc) · Sieve-Gate StructuralAST succeeded → srNoTransformApplied skip · UAP 0 results(requests=1) · verified=0/40 |
| 미선언 ingress | **0** (성공 읽기·execve·dir 목록 전부 선언분 내) |
| AF_INET/AF_INET6 connect | **0건** |
| AF_UNIX | 20건 — 전부 `/var/run/nscd/socket`, 전부 ENOENT(연결 성립 0) — systemIPCAllowlist amendment(requiresRatification=true) |
| env(HOME) 읽기 | 0건 (git config 완전 중립화) |
| subject 사후 상태 | `?? data/` 1줄 — 무변경 |
| layer1(git_file_list) | **PASS** — 86/86 `.nim` 일치 (.nims 제외 부분검증), gitIndexHash `6b38830d…` |
| layer2(sourceFingerprint) | **unable** — `runtimeMeta`에 `subject` 키가 스키마상 미존재(v1·v3 동일); 독립 재계산 `e9d02504…`(경로 87=87 일치) 기록 |

## Evidence

- **same-class 4중 기계 일치 (v1 대비 강화 — 바이트 수준):**
  1. completeness evidence: `.axiom/cache/evidence/df2ff30d5f73102dd89274c1df96ea9a922e935954714e81808e60fc8a60691c.json` **바이트 동일**(v1=v3=`c80cce75…`; `translationLossFree=false, bindingUniverseComplete=false, opaque-boundary-present, sourceBindingCount=15, irBindingCount=13`) + `.witness.json` 바이트 동일(`fdb0d821…`) — 역사 "15 vs 13"과 정확 일치
  2. Z3 스크립트 digest: `d067de0283743d9117ac7a7e900452bd6d7a0fab013e734e` v1/v3 `z3_telemetry.jsonl` 양쪽 존재 + `canonical_envelope_digest` 3종 전부 양쪽 동일
  3. provenance 쌍: `smBMC/pkZ3Bmc` 동일
  4. exit 코드: 2 = 2
  - 부가: `node_selection_state.json` 바이트 동일(`d747e19f…`), trajectory 상태열 동일(4 `ssStarted`), certificate journal 6건(v1 6건), `ax_proof_state.json` 키 23개 diff 0
- **ingress 선언(정본)**: `executionIngressManifest` 4,688 entry(전부 sha256 또는 `absent` 또는 `dir:`), raw 원문 `/tmp/exec_ingress_manifest_v2.txt`, **digest `2237e13ab4edf759ac590879210de69e6f355e0e1991fcfe8451793e0adc33fd`** (v1 13-entry digest `aa850772…`는 이력 보존); `repo:bin/ax` = `fd7c36b1…` = `axBinarySha256` 교차 일치
- **state/binding**: `stateSeedDigest=34b5e10f081968ad80b557e23d36abbcaddd1d12440b7daacc83b3f5178daf7a`, canonicalArtifacts 24종 sha256(reproduction.json), observeLog sha256=`79e8596325026da5c9ce75ef9ebb7b8998f616bdc18185bda8d8e6041eba04da`
- **manifest**: `r0-evidence-manifest.json`(sha256 `3611aa1e2cbf1ebfea2c361a576268e712f7c8490886bd70b1ba96729faf6c85`) — subjectAuthority·executionAuthority·stateSeed·envAllowlist(amendments)·historicalJournal·restoredHistoricalEvidence 31건·irrecoverable 6항·reproduction·firstOpenTarget
- **historical journal**: `workspace-untracked:nim-stew/data/trusted/journal/3ab50cc271cdc3166d6ad39c9b34f7a01a2c0626fdd08cfecdb33107135c2aad.json` sha256=`519aca4c70e1c78846be6ace6c7798643a15d4aa113c6d73fec0e266f15394e9`, provenance **unqualified**(DEBT `data/debt_registry.json:3466`, DEBT#445 "Historical tcVerifiedProof records are provenance-unqualified"), subjectBinding=none
- **복구 증거**: `restored_evidence_checksums.txt` 31/31 존재+sha256 일치
- **v2 divergence 기록**: `/tmp/act2r0_witness_v2_1790824471/` (exit 0, "Lean compiler dysfunctional", DGRAM DNS 소켓 6건 — amendment 근거)

## Classification

**same-class PASS (재관측 통과)** — 수정4 판정: 동일 의미론 판정 성립(4중 일치, 바이트 수준 evidence). Amendments 발생(env 3건 — 전부 기록). systemIPCAllowlist 1건(nscd probe)이 **사용자 비준 필요 잔재**(`requiresRatification: true`)이며, 이 항목이 비준되기 전까지 R0-E 게이트 판정은 "비준 대기 항목 존재"로 보고된다(blocker 아님 — 연결 성립 0·데이터 교환 0·완전 ENOENT 프로브).

## Interpretation

- 8월 WP4j34 결과(exit 2, Incomplete/fact-blocked)의 의미론 페이로드는 827329cbd 바이너리에서 **충실히 재현**된다: completeness evidence가 **바이트-동일**하고 Z3 스크립트·provenance·exit 코드가 일치한다. 바이너리 rev 차이(44fefd470 → 827329cbd)가 의미론 발산을 일으키지 않았다(기계 귀속 divergence 없음).
- 실행 ingress는 이제 **선언 manifest가 정본**이고 strace는 검증자다(수정5): 관측(성공 읽기 21030+execve+dir) ⊆ 선언(4688 entry + subject closure 87)이 성립 — `repo:src/**` 자기 스캔(1294), `.lake` 프로브, `subject:.git` 메타, elan 런타임 라이브러리(3166), git_config HOME 읽기(중립화로 소거) 전부 선언/배제 규칙으로 해소.
- layer1 equality가 **PASS로 복구**(v1: ENOENT로 불가 → v3: git_file_list.json 86/86 `.nim` 일치). layer2는 스키마상 필드 부재로 "unable"이 정직한 판정.
- AF_UNIX nscd 프로브는 glibc NSS가 bash(lake 래퍼)에서 실행하는 시스템 서비스 프로브 — 연결 성립 0·ENOENT 100%·pid/execve 상관 확정. 제거는 제품 변경이 필요하므로 amendment 목록화가 최소 개입의 정직한 처리다.
- v2 divergence는 환경 amendment의 필요성을 기계적으로 입증한 사례로 보존: HOME 중립화 단독으로는 elan 툴체인 발견이 깨진다(다운로드 시도→netns 차단). `ELAN_HOME` amendment 후 v3에서 same-class 복원.

## Non-Conclusions

1. **byte-identity는 미성립**: v1과 v3의 파생 산출물(`z3_telemetry.jsonl`의 `ts`/`time_ms`, trajectory의 `ts`)은 시간 필드에서 다르다. 동일성은 **same-class(의미론 동등)** 범위에서만 주장한다.
2. **8월 dirty-state 재구성 불가**: 8/31 당시 작업트리 상태(무커밋 delta `f7dd583+uncommitted delta`, 삭제된 증거 `cfdc76cab`·`089251924`·`/tmp/act21_witness_0` 등 irrecoverable 6항)의 정확한 재현은 불가능하다. historical journal은 준수한 증거가 아니다.
3. **journal provenance-unqualified**: historical `tcVerifiedProof` 기록은 커널 증거 결속 없이 쓰여진 legacy-unverified 인구(DEBT#445) — 증거로 사용할 수 없고, 본 보고서는 이를 subjectBinding=none으로만 인용한다.
4. **"project verified" 주장 불가**: verified=0/40 · gateVerdict FAIL · 증명서 미발행(`stew_bitops2_nim__getBitsBE.json` ENOENT) — 이 실험은 getBitsBE 슬라이스의 **비검증(Incomplete/fact-blocked)** 만을 확립한다.
5. **선언 manifest=정본·strace=검증자 + worktree 충돌 이관 사실**: strace는 관측 도구이며 선언의 정본은 manifest다. 그러나 v1 관측은 구 `Axiom-worktree`에서, v2/v3는 새 `Axiom-worktree-r0`에서 이뤄졌다 — 같은 HEAD(827329cbd)지만 이관 전후 파일 내용의 사전 동일성 검증은 수행하지 않았다(선언 manifests의 sha256은 각 실행 시점 파일 기준). 따라서 "관측 경로 집합의 안정성"은 실행 재현(v1⊇v3 관측 일치 — src 1294 동일 등)으로 뒷받침되며, 바이트 해시 결속은 실행별로 분리된다.

## Next Experiment

`firstOpenTarget = bitops2.getBitsBE`(`sortKey=12`, `lastVerdict=pre_sieved`, OPEN) — **이번 캠페인에서 실행하지 않음**(식별만). 다음 실험(ACT2-R0 후속): WP4-j 사전 선별(`pre_sieved`) 경로를 UAP 0-results 문제와 함께 재시도 — `proof Summary`의 `getBitsBE psFail smBMC/pkZ3Bmc`와 Sieve-Gate `srNoTransformApplied` skip을 해소할 수 있는 타깃·방법론 변경 없이는 verified=0이 유지될 것으로 예측된다. 2순위 OPEN: `base36.decodedLength`(sortKey 17, timeout).