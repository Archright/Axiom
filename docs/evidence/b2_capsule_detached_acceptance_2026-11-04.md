# B-2 — detached cold acceptance: MERGE_SHA에서 캡슐 재현 확인 (2026-11-04)

> **Status**: Observation evidence record — **병합 커밋(detached) 상태에서의 캡슐 Stage B 1회 재실행(run3) 관측** (`src/`·Makefile·`config/policy/**`·`.github/**` 무수정, 제품 코드 무변경, main worktree 무수정, FROZEN 무수정; 캡슐·서브젝트·`/tmp/b1_gate_a`·`/tmp/b1_gate_b`·`~/.cache/mathlib`·`~/.elan`은 전부 읽기 전용으로만 접촉. Axiom4에 착지하는 것은 본 문서 1건)
> **Created**: 2026-11-04
> **Written at**: branch `work/b2-detached-acceptance-2026-11-04` (worktree `/tmp/b2_wt/s2`), branch base = origin/main `4bc18b2154e6c56edb6a5d8b915bc5c37037883e` (= 본 acceptance가 수용하는 증Evidence PR #1271의 MERGE_SHA — state=MERGED 2026-11-04T08:34:37Z, parents=2)
> **Governing docs**:
> - 작업 계획 v6.1 — A안 "Minimal Hermetic Proof Capsule" (에이전트 세션 작업 계획; 저장소 미수록 — 본 문서가 그 S2-C 단계를 수행)
> - [docs/spec/aeneas_generation_contract.md](../spec/aeneas_generation_contract.md) (1a 세대 계약 — MERGE_SHA `0010bbd94a50602e44e2136598ef56ac97083289`)
> - [docs/spec/proof_dependency_closure.md](../spec/proof_dependency_closure.md) (1b 증명 의존성 폐쇄 규칙 — MERGE_SHA `b2f807e5e37fd438359c258712cf9aaab29b9750`)
> - [docs/spec/mathlib_hermetic_boundary.md](../spec/mathlib_hermetic_boundary.md) (1c Mathlib hermetic 실행 경계 — MERGE_SHA `b56c3c512c94b43965c7d799b12146f66e35ece9`)
> - [docs/evidence/b2_hermetic_proof_capsule_2026-11-04.md](b2_hermetic_proof_capsule_2026-11-04.md) (B-2 증Evidence — 본 문서가 수용하는 대상이자 비교 기준값의 정본; MERGE_SHA `4bc18b2154e6c56edb6a5d8b915bc5c37037883e`에 병합, 635행)
> - [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](b1_gate_a_minimal_proof_2026-11-04.md) (B-1 Gate A — MERGE_SHA `c3a4164324c479b34c5caefd94b08fe5ad263014`; F1 1토큰 수정 근거)
>
> **원칙**: 기계 출력과 오류 문자열은 원문 그대로 인용한다(재작성·요약·번역 없음). 이 문서는 관찰을 기록하며 serde_json·Aeneas·Charon에 대한 어떤 참·거짓 주장도 하지 않는다 (§Non-claims).

7-field identity (FREEZE.md §1 형식 준용 — 값은 본 문서 정체성):

- PROJECT_UNDER_TEST: **Hermetic Proof Capsule `/tmp/b2_capsule`** (pristine — 읽기 전용) — 180,040파일·11,353,320,247B(stage_a_stats 정본; `find` 전체 180,042 = 여기에 `generation.json`·`inventory.json` 2파일을 더한 값). 서브젝트 참조 identity: serde_json v1.0.154 @ `8c535a260ce561eaab4111aafc29038eb9f77ff3` (B-1 §4.1 결속)
- REVISION: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (서브젝트 — generation.json `subject.git_head` 정본, 본 세션은 서브젝트에 접촉 0건)
- AXIOM_REVISION: `4bc18b2154e6c56edb6a5d8b915bc5c37037883e` (증Evidence MERGE_SHA — **detached 체크아웃 상태에서 run3 실행**, 본 문서 작성 시점 branch base와 동일 커밋)
- CONFIG: 캡슐·서브젝트(`/tmp/b2_capsule`·`<workspace>/json`·`/tmp/b1_gate_a`·`/tmp/b1_gate_b`·`~/.cache/mathlib`·`~/.elan`) 전부 **읽기 전용** — run3의 쓰기는 격리 실행 내부(tmpfs `/tmp`·`--bind` workspace `/tmp/b2_run3/workspace`)에서만 발생. Stage B는 bwrap `--unshare-net` 샌드박스에서 네트워크 단절 상태로 실행
- TOOLCHAIN_ID: 캡슐 고정 Lean **4.35.0** (`toolchain/bin/lean` sha256 `bf8d54e4…ceb38`, generation.json 정본 — 본 세션 사전 재실측 일치) + 실행 게이트 bwrap **0.9.0** (호스트 바이너리 sha256 `e318903862396f96de3df57264e0158682b952fd3fb53ac23d876413e7b30f71` — generation.json `execution_base.bwrap_binary_sha256`와 재실측 일치) — 도구 세대는 generation.json에 봉입되어 실행 사이 고정(1a 세대 계약)
- SCOPE: **병합된 증Evidence 커밋(MERGE_SHA) 상태에서의 Stage B 1회 재실행(run3)의 관측과 증Evidence 기록과의 대조만**. **범위 밖**: rustc·charon·aeneas 재실행(A안 경계 — §4.2의 identity-only 결속 유지), 캡슐 축소, 타 머신 재현, Stage 3 채택 adjudication, run4(4번째 실행 — 수행하지 않음)
- EXPERIMENT_ID: b2-capsule-detached-acceptance-2026-11-04

---

## 1. Question

이 문서가 답하는 질문:

1. **병합된 증Evidence 커밋(MERGE_SHA) 상태에서 pristine 캡슐의 Stage B 재현 판정이 동일한가** — detached 체크아웃(`4bc18b215…`)에서의 독립 실행(run3)이 증Evidence 기록(run1·run2)과 동일한 Lean 커널 판정(`#print axioms`, sorryAx 0), 동일한 산출물 identity(olean digest 5종), 동일한 보조 관측 축을 산출하는가?
2. run3 실행이 캡슐 자체를 변경시키지 않았는가 — 실행 후 캡슐 불변성(사전 항목 재실측 + inventory 전수 재해시)이 유지되는가?

즉, 착지된 증Evidence가 **선언이 아니라 git 히스토리의 실제 병합 커밋 상태에서 재현됨**을 기계적으로 확인한다(cold acceptance — 캡슐·호스트 상태를 이전 실행과 공유하지 않는 새 프로세스에서의 검증).

## 2. Context

- 증Evidence 문서 `docs/evidence/b2_hermetic_proof_capsule_2026-11-04.md`(635행)는 PR #1271을 통해 MERGE_SHA `4bc18b2154e6c56edb6a5d8b915bc5c37037883e`에 병합되어 있다(GitHub 관측: state=MERGED 2026-11-04T08:34:37Z, parents=2, graphql↔rest consistent — 착지 시점 사실). 본 문서는 그 커밋을 detached로 체크아웃해 run3를 실행하고, 그 결과를 증Evidence 문서의 기록값과 대조한다.
- 비교 기준값은 **증Evidence 문서(병합본)와 run1·run2 기록 파일**(`/tmp/b2_run1/records/`·`/tmp/b2_run2/records/` — 디스크 보존본)이다. 판정 기준은 증Evidence §4.3과 동일하게 **Lean 커널 판정**(`#print axioms`, sorryAx 0)이며 olean digest는 동일 기대 산출물 identity, 보조 축은 참고 관측이다.
- Stage B의 정본 실행 구성은 **generation.json `sandbox_config`**다 — 증Evidence와 동일하게, 하네스 스크립트·임의 판단이 아니라 봉입된 구성이 실행을 결정한다. run3의 bwrap 명령은 generation.json을 직접 읽어 생성했다(`/tmp/b2_run3/bwrap_cmd_generated.sh` 보존).

## 3. Scope

- **범위 안**: (a) detached 체크아웃(`git fetch origin` → `git checkout 4bc18b215…`)과 증Evidence 문서 병합 확인(`git show` — 635행 존재), (b) 캡슐 사전 무결성 검증(증Evidence §5.6 항목 준용: self digest 2종·코어 9파일·toolchain bin 4종·lib 5종·`.ltar` 개수·F4 cache exe), (c) pristine 캡슐의 `/tmp/b2_run3/` 독립 Stage B 실행, (d) run3 판정 ↔ 증Evidence 기록 비교, (e) 실행 후 캡슐 불변성 재검(사전 항목 + inventory 전수 재해시), (f) 본 문서 착지(acceptance PR).
- **범위 밖**: rustc·charon·aeneas 재실행(A안 경계 — Stage B는 봉입된 Lean 증명 입력의 재컴파일·커널 판정만 수행; 이들 도구 세대는 generation.json `identity_only_bound_not_executed`로만 결속), 캡슐 축소, 타 머신 재현, Stage 3 채택 adjudication, run4.
- 원본 clone 워킹트리 무수정 — 커밋·push는 전용 worktree(`/tmp/b2_wt/s2`)에서만. `--no-verify` 미사용. 캡슐 내부에는 어떤 파일도 쓰지 않는다(§5 전수 재해시로 기계 검증).

## 4. Procedure

### 4.1 detached 체크아웃

```bash
cd /tmp/b2_wt/s2
git fetch origin
git checkout 4bc18b2154e6c56edb6a5d8b915bc5c37037883e   # detached
git cat-file -e 4bc18b2154e6c56edb6a5d8b915bc5c37037883e:docs/evidence/b2_hermetic_proof_capsule_2026-11-04.md  # EXISTS
git show --stat 4bc18b2154e6c56edb6a5d8b915bc5c37037883e  # 635 insertions, parents 2
```

실측: HEAD = `4bc18b2154e6c56edb6a5d8b915bc5c37037883e`(Merge pull request #1271), parents `e2d089537d1f9db23713808600cc70a03e13dd33` + `ddd8f943f21ea2fde528d8394c3067767fa7a7dc`, 문서 635행 존재 — 병합 상태에서 detached 실행 조건 충족.

### 4.2 캡슐 사전 무결성 검증 (증Evidence §5.6 항목 준용)

- self digest: `sha256(generation.json)` = `efdced76b105cc4843aad99cbe2f4eedab039439742870c34d85107e5d1b5133` ✓ · `sha256(inventory.json)` = `742ec2c0f78c3490621d42c67e6f88698f5588422f95b1fcf612a5af9f1d781e` ✓ (증Evidence §5.1 표와 동일)
- 코어 9파일 + toolchain bin 4종 + lib 5종 + F4 cache exe — 19파일 sha256 전수 실측, generation.json `stage_b_inputs` 기록값과 전부 일치 ✓ (실패 0)
- `cache/` `.ltar` 파일 개수 **9,031** = `cache_ltar_file_count` ✓

### 4.3 Stage B 실행 — run3

- workspace: `mkdir -p /tmp/b2_run3/{workspace,records,logs}`. `stage_b.sh`는 run2 최종본을 배치하고 digest 대조: `sha256` = `9197a0f02f829455b62660f9f8894bfa04430a1060b4ee731c0ee52d3fd54e39` = generation.json `execution_base.stage_b_sh_sha256` ✓ (run1 정본·run2 사본과의 3자 일치 유지).
- bwrap 명령은 **generation.json을 직접 읽어 생성** — `sandbox_config.bwrap_args` 중 `--bind /tmp/b2_run1/workspace /workspace`를 `--bind /tmp/b2_run3/workspace /workspace`로 치환하는 유일 변경(§7-1). 생성 스크립트는 `/tmp/b2_run3/bwrap_cmd_generated.sh`로 보존 — run2 생성본과의 diff는 workspace 바인드 경로 1행만.
- 실행: `/tmp/b2_run3/bwrap_cmd_generated.sh` — 출력을 `/tmp/b2_run3/logs/run3_full.log`로 기록, 래퍼 3행(`run3_start`·`bwrap_exit`·`run3_end`)만 덧붙임(run2 방식과 동일).

## 5. Result

### 5.1 run3 관측 원문 (하네스 출력 그대로 — `/tmp/b2_run3/records/run3_full.log`)

```
run3_start: 2026-11-04T17:39:09+09:00
== [0] sandbox state ==
uid=1000 gid=1000 groups=1000,65534
ls: cannot access '/home': No such file or directory
ls: cannot access '/root': No such file or directory
curl_exit=6
== [1] workspace copy ==
== [2] force fresh root compile ==
== [3] cache unpack ==
Already decompressed 9031 file(s)
== [4] build ==
✔ [1796/1801] Built AsBool.TypesExternal (2.7s)
✔ [1797/1801] Built AsBool.Types (2.1s)
✔ [1798/1801] Built AsBool.Funs (1.8s)
✔ [1799/1801] Built AsBool.Spec (1.7s)
✔ [1800/1801] Built AsBool (1.5s)
Build completed successfully (1801 jobs).
== [5] print axioms ==
'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]
'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]
== [6] artifact digests ==
e5b1ef421f5ebccb6aa35ebeff066db35dd944e97dbfcace61362c8d43340d58  /workspace/leanproj/.lake/build/lib/lean/AsBool.olean
bdf7f0ff6dfc84804d36a640348e9a5af6fe9f1d7e8c8a63b41ce099a6133ad9  /workspace/leanproj/.lake/build/lib/lean/AsBool/Funs.olean
5f604d403600172d402091048aebdba1e646c39a30fbe19ff095dfec6601f816  /workspace/leanproj/.lake/build/lib/lean/AsBool/Spec.olean
d66574f5f531a479d158654351aef301446b61ab7da47684526360a2fd396db8  /workspace/leanproj/.lake/build/lib/lean/AsBool/Types.olean
a41a0bed960f683f4134dddd3edb72da8cd067f369ea66c5d516404ff8bd09b8  /workspace/leanproj/.lake/build/lib/lean/AsBool/TypesExternal.olean
== [7] ro-mount check ==
touch: cannot touch '/toolchain/.write_test': Read-only file system
toolchain_readonly=ok
touch: cannot touch '/cache/.write_test': Read-only file system
cache_readonly=ok
touch: cannot touch '/tmp/b1_gate_a/leanproj/.write_test': Read-only file system
inputs_readonly=ok
bwrap_exit=0
run3_end: 2026-11-04T17:40:00+09:00
```

run3 bwrap exit = 0 (1회 성공 — 재시도·수정·중단 없음).

### 5.2 run3 ↔ 증Evidence 기록 비교 (기계 대조)

**판정·axioms·olean digest — 필수 기준 전부 동일**:

| 축 | 증Evidence 기록 (run1 = run2) | run3 | 판정 |
|---|---|---|---|
| bwrap exit | 0 | 0 | **동일** |
| lake build | exit 0, `Build completed successfully (1801 jobs)` | exit 0, `Build completed successfully (1801 jobs)` | **동일** |
| `#print axioms` (커널 판정) | `'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]`<br>`'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]` | 원문 2행 — run1 기록 파일(`/tmp/b2_run1/records/print_axioms_output.txt`)과 **바이트 동일** (diff EMPTY) | **동일** |
| sorryAx 개수 | 0 | 0 | **동일** |

**olean digest 5종 (전부 동일 — 빌드 산출물 identity)**:

| olean | 증Evidence 기록 = run3 sha256 |
|---|---|
| `AsBool.olean` | `e5b1ef421f5ebccb6aa35ebeff066db35dd944e97dbfcace61362c8d43340d58` |
| `AsBool/Funs.olean` | `bdf7f0ff6dfc84804d36a640348e9a5af6fe9f1d7e8c8a63b41ce099a6133ad9` |
| `AsBool/Spec.olean` | `5f604d403600172d402091048aebdba1e646c39a30fbe19ff095dfec6601f816` |
| `AsBool/Types.olean` | `d66574f5f531a479d158654351aef301446b61ab7da47684526360a2fd396db8` |
| `AsBool/TypesExternal.olean` | `a41a0bed960f683f4134dddd3edb72da8cd067f369ea66c5d516404ff8bd09b8` |

run3의 5종은 run1 기록 파일(`/tmp/b2_run1/records/olean_digests.txt`)과 **바이트 동일**(diff EMPTY)이며 증Evidence §5.5 표 값과도 전부 일치한다.

**관측 보조 축 — 전부 동일**: `curl_exit=6`(DNS 실패; 네트워크 통신 불가능 상태에서 실행, 시도 부재의 증명은 아님 — expected_verdict 원문 취지 유지)·`/home`·`/root` 부재·cache unpack `Already decompressed 9031 file(s)`·ro-mount 3종 ok(toolchain·cache·inputs)·uid/gid `1000`.

**정규화 full-log diff**: wall 초(`(N.Ns)`→`(Ws)` 정규화)·래퍼 라인(`runN_start`·`runN_end`·`bwrap_exit=`) 제거 후 run3 vs run1 diff **EMPTY**, run3 vs run2 diff **EMPTY** — 상이한 것은 타이밍과 래퍼 라인뿐이다.

**유일한 상이 축 — 타이밍(예고된 변동 클래스)**: 모듈 컴파일 wall — run1 5.5/2.2/1.8/1.7/1.5s·run2 3.4/2.0/1.9/1.9/1.7s vs run3 2.7/2.1/1.8/1.7/1.5s. wall은 판정·identity 축이 아니다(증Evidence §5.5 동일 취급).

### 5.3 캡슐 불변성 (사전 → 실행 → 사후)

- **사전 검증(run3 직전)**: §4.2 — 19파일 digest + self digest 2종 + `.ltar` 9,031 전부 일치.
- **사후 재검(run3 직후)**: 사전과 동일 항목 전부 재실측 일치 + **inventory 전수 재해시** — 180,040항목 전수 sha256 대조 `matched=180,040 · mismatched=0 · missing=0 → INVARIANT_PASS` (기계 판정 기록: `/tmp/b2_run3/records/inventory_full_rehash.json`). run3 실행이 캡슐에 어떤 파일 변경도 발생시키지 않았다.

### 5.4 수용 판정 (acceptance)

- 병합 커밋 `4bc18b2154e6c56edb6a5d8b915bc5c37037883e` 상태에서의 run3가 증Evidence 기록과 **필수 기준 전 축 동일** — 병합된 증Evidence는 선언이 아니라 병합 커밋 상태에서 실제로 재현됨이 기계적으로 확인됐다(TERMINAL_SUCCESS 충족: detached 재현 동일 + 본 acceptance PR의 병합).
- 세대 정본 인용: `sha256(generation.json)=efdced76b105cc4843aad99cbe2f4eedab039439742870c34d85107e5d1b5133` · `sha256(inventory.json)=742ec2c0f78c3490621d42c67e6f88698f5588422f95b1fcf612a5af9f1d781e` — 사전·사후 재실측 모두 증Evidence 기록값과 동일.

## 6. Non-claims

- 본 문서는 **제품 판정이 아니다** — v1 CLI·레인·게이트·인증서의 어떤 동작도 주장하지 않는다.
- **일반 재현 보장이 아니다** — 본 acceptance는 동일 호스트(Linux Mint 22.3·x86_64·kernel 6.17.0-42-generic·glibc 2.39)·동일 bwrap 0.9.0·동일 캡슐 세대(`efdced76…`)에서의 재현 확인이며, 머신 간 이식성·타 세대 재현은 주장하지 않는다.
- **일반 Aeneas 채택이 아니다** — 단일 함수 `as_bool`의 고정 세대 재현 관측일 뿐이며, Stage 3 채택 adjudication은 본 문서 범위 밖이다.
- rustc·charon·aeneas의 어떤 재실행도 수행하지 않았다 — 이들 도구 세대는 봉입 identity(generation.json `identity_only_bound_not_executed`)로만 결속된다. 본 세션의 실행은 캡슐 툴체인의 lean·lake와 bwrap뿐이며, **미실행 단계를 실행한 것처럼 기록하지 않는다**.
- curl_exit=6은 "네트워크 단절 상태에서의 실패 관측"이며 DNS·방화벽 경로의 부재 증명은 아니다.
- 본 문서는 증Evidence 문서의 내용을 확장·개정하지 않는다 — 병합 커밋 상태에서의 재현 확인 1건만을 추가한다.

## 7. Deviations (전수)

1. **run3의 workspace 바인드 소스 경로 치환 1건 (유일한 run3 구성 편차 — 독립 실행에 필연, 증Evidence §7-2와 동일 클래스)** — bwrap_args 중 `--bind /tmp/b2_run1/workspace /workspace`를 `--bind /tmp/b2_run3/workspace /workspace`로 치환. 나머지 인자·순서·env는 generation.json sandbox_config 무변경(명령은 generation.json을 직접 읽어 생성 — `/tmp/b2_run3/bwrap_cmd_generated.sh` 보존). 캡슐 마운트 3종(ro-bind toolchain·inputs 서브패스·cache)은 무변경.
2. **run3 실행 중 발생 편차: 없음** — bwrap exit 0, 1회 성공, 재시도·수정·중단 없음.

## 8. Repro Block

```bash
# 0) detached 체크아웃 (증Evidence 병합 커밋)
cd /tmp/b2_wt/s2
git fetch origin && git checkout 4bc18b2154e6c56edb6a5d8b915bc5c37037883e
git show --stat 4bc18b2154e6c56edb6a5d8b915bc5c37037883e   # 635 insertions, parents 2

# 1) 세대 정본 확인 (pristine 캡슐 — 읽기 전용)
sha256sum /tmp/b2_capsule/generation.json   # efdced76b105cc4843aad99cbe2f4eedab039439742870c34d85107e5d1b5133
sha256sum /tmp/b2_capsule/inventory.json    # 742ec2c0f78c3490621d42c67e6f88698f5588422f95b1fcf612a5af9f1d781e
find /tmp/b2_capsule/cache -name '*.ltar' -type f | wc -l   # 9031

# 2) run3 workspace 준비 (stage_b.sh는 정본 digest와 동일한 사본 — digest 검증 필수)
mkdir -p /tmp/b2_run3/workspace /tmp/b2_run3/records /tmp/b2_run3/logs
sha256sum /tmp/b2_run3/workspace/stage_b.sh
# 9197a0f02f829455b62660f9f8894bfa04430a1060b4ee731c0ee52d3fd54e39
#   = generation.json execution_base.stage_b_sh_sha256

# 3) bwrap 명령은 generation.json에서 생성 (workspace 소스 치환만 — §7-1)
python3 - <<'EOF'
import json
g = json.load(open('/tmp/b2_capsule/generation.json'))
args = g['sandbox_config']['bwrap_args']
i = args.index('/tmp/b2_run1/workspace')
assert args[i-1] == '--bind' and args[i+1] == '/workspace'
args = args[:i] + ['/tmp/b2_run3/workspace'] + args[i+1:]
print('exec bwrap \\\n  ' + ' \\\n  '.join(f"'{a}'" for a in args))
EOF

# 4) Stage B 실행 (네트워크 단절·캡슐 ro — 격리 실행 내부로만 쓰기)
/tmp/b2_run3/bwrap_cmd_generated.sh          # → run3_full.log 기록, bwrap_exit=0
# 기대: curl_exit=6 · Already decompressed 9031 file(s)
#       Build completed successfully (1801 jobs).
#       'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]
#       'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]
#       olean digest 5종 = 증Evidence §5.5 표 값과 동일
#       toolchain_readonly=ok · cache_readonly=ok · inputs_readonly=ok

# 5) run3 ↔ 증Evidence 기록 비교 (판정·axioms·olean digest — 필수 기준)
# 증Evidence: docs/evidence/b2_hermetic_proof_capsule_2026-11-04.md §5.3~5.5
# run1: /tmp/b2_run1/records/  ·  run2: /tmp/b2_run2/records/  ·  run3: /tmp/b2_run3/records/
# wall 초·래퍼 라인 제외 정규화 diff = EMPTY

# 6) 캡슐 불변성 재검 (사전·사후)
# 코어 9파일 + toolchain 4+5종 + F4 sha256 대조 + inventory 전수 재해시:
# 180,040항목 matched=180040 mismatched=0 missing=0 → INVARIANT_PASS
```

실행 기반: Linux Mint 22.3 (noble base) · x86_64 · kernel 6.17.0-42-generic · glibc 2.39-0ubuntu8.9 · bwrap 0.9.0 (`e3189038…30f71`) — 증Evidence 문서와 동일 호스트·동일 실행 게이트.
