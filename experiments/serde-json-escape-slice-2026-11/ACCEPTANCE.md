# ACCEPTANCE — serde_json escape 수직 슬라이스 증거 패키지

> 이 문서는 **관측된 사실만** 기록한다. 실행하지 않은 것, 재현하지 못한 것은 그렇게 적는다.
> 브랜치: `feat/rust-escape-slice` · 작성일: 2026-11-12 · 실험 디렉터리: `experiments/serde-json-escape-slice-2026-11/`

## 0. 범위와 환경

| 항목 | 값 (관측) |
|---|---|
| Axiom 버전 | `v0.6.3` (`toolchainIdentity.axiomVersion`) |
| Nim | `2.2.10` |
| Lean | `4.33.0` (`toolchainIdentity.lean`) |
| solver 표기 | `4.13.3` (`solverInvocation.version`, `toolchainIdentity.z3`) |
| charon | `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)` (pinned = measured, `ok=true`) |
| rustc | `rustc 1.95.0 (59807616e 2026-04-14)`, `rustc-sha256=bff349e72704ff70bc08a234a3847338e797065bbedde5e556808bc87b7bf7c6`, `components-sha256=a13769c18a7a74ea492ab633b644d6c238ae81e536d30d3f168eddb57e86000e`, `channel=stable-x86_64-unknown-linux-gnu`, `profile=minimal` |
| serde_json 주체 | `/tmp/axiom-serde-json` @ `8c535a260ce561eaab4111aafc29038eb9f77ff3` |
| Cargo.lock (배치본) | sha256 `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` |
| scope lock (run1/d2) | sha256 `6002ee054ebc27762959c0fb46f558102e829a9a2b20b5b0a1c601d93902f37b` |
| scope lock (escape) | `state_escape/data/verification_scope.lock` — `jq '{n:(.rust_targets|length),vksRust}'` → `{"n":2,"vksRust":2}` |

커밋되는 증거는 `ACCEPTANCE.md`·`inputs/`·`runs/`뿐이다. `state*/`·`vault*/`는 `.gitignore`로 제외한다(기존 `experiments/` 관례와 동일). `inputs/verification_scope.lock`은 `state_escape/data/verification_scope.lock`의 복사본이다.

`state_escape` 락은 `state/data/verification_scope.lock`을 복사한 뒤 `rust_targets`만 2개 항목(`axiom_escape_probe::is_escape`, `axiom_escape_probe::is_escape_mutant`)으로 교체하고 `vksRust`를 2로 설정한 것이다. 나머지 필드는 원본과 동일하다.

---

## 1. TASK 1 — 부정 통제 1차 실행 (수정 전 · historical)

### 1.1 실행한 명령 (그대로)

```bash
AXIOM_STATE_DIR=$PWD/experiments/serde-json-escape-slice-2026-11/state_escape \
AXIOM_PROVE_VAULT_DIR=$PWD/experiments/serde-json-escape-slice-2026-11/vault_escape \
AXIOM_CHARON_BIN="$(command -v charon)" GITHUB_TOKEN="$(gh auth token)" \
./bin/ax prove --project tests/fixtures/rust/axiom_escape_probe
```

stdout/stderr는 `runs/escape/stdout.log`, `runs/escape/stderr.log`에 각각 저장했고, 종료 코드는 `runs/escape/exit_code.txt`에 기록했다.

### 1.2 종료 코드

```
EXIT=0
```

**예상(1)과 다르다.** 아래 1.4의 이유로 mutant가 `failed`가 아니라 `unknown`으로 분류되었고, `failed=0`이므로 실패 종료 조건이 성립하지 않았다.

### 1.3 stderr 전문 (verbatim)

```
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/ref/heads/axiom/evidence-cas elapsed_ms=400 status=200 OK
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/commits/fceadadefe96242bdab18a03ded719590c814bed elapsed_ms=375 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/trees/97af3bc988e0dce0bc68c6c44bb7a88d1eefa840?recursive=1 elapsed_ms=363 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/ref/heads/axiom/evidence-cas elapsed_ms=321 status=200 OK
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/commits/36563ec3d6c2b595db7a0e6629237a0a373c3620 elapsed_ms=318 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/trees/d21dfbc99113a0e7c0f8e9cad876049fae7dc900?recursive=1 elapsed_ms=377 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/blobs/004b867b82187de7e0bcb00346977b1fe01fa317 elapsed_ms=362 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/ref/heads/axiom/evidence-cas elapsed_ms=380 status=200 OK
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/commits/36563ec3d6c2b595db7a0e6629237a0a373c3620 elapsed_ms=339 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/trees/d21dfbc99113a0e7c0f8e9cad876049fae7dc900?recursive=1 elapsed_ms=337 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/blobs/004b867b82187de7e0bcb00346977b1fe01fa317 elapsed_ms=336 outcome=ok
[AXIOM][rust-lane] charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true
[AXIOM][rust-lane] dep-info /workspace/Axiom/experiments/serde-json-escape-slice-2026-11/state_escape/.axiom/rust-lane/515aeff29933b27b/charon-target/x86_64-unknown-linux-gnu/debug/libaxiom_escape_probe.d
[AXIOM][rust-lane] ledger transport armed (live); repo=Archright/Axiom
[AXIOM][rust-lane] verified: axiom_escape_probe::is_escape → /workspace/Axiom/experiments/serde-json-escape-slice-2026-11/vault_escape/39dacdaedb5f19cd96fdcd989256bb00878bf6f5ba3eb25d5e78f136ebdb0f7c.json
[AXIOM][rust-lane] axiom_escape_probe::is_escape_mutant → unknown (stage=kernel): spec declined by kernel; counterexample unconfirmed (cvUnresolved precedent, ir_pipeline_runner.nim:1450-1458): canonicalLeanKernelCheck: exit code 1: /tmp/axiom_kc_2657449a7232e7eb37cd82fdc13fd950460d6e448bb25b46217e071f36b6e136.lean:8:2: error: omega could not prove the goal: | No usable constraints found. You may need to unfold definitions so `omega` can see linear arithmetic facts about `Nat` and `Int`, which may also involve multiplication, division, and modular remainder by constants. — replay rvUnavailable:harness compile failed (exit 1): error[E0308]: mismatched types
  --> /workspace/Axiom/experiments/serde-json-escape-slice-2026-11/state_escape/.axiom/tmp/rust_replay/888e7711ea82d40e/replay_harness.rs:4:; fail-closed cvUnresolved
[AXIOM][rust-lane] done: verified=1/2 failed=0 unknown=1 error=0
[AXIOM][rust-lane] §6c identity sidecar skipped: claim identity unmeasurable: candidate count is 2 — the §6c certified scope is exactly one target
```

stdout: 비어 있음(0바이트).

### 1.4 결과 요약과 실패 원인

- `is_escape`: **verified** → `vault_escape/39dacdae….json`
- `is_escape_mutant`: **unknown** (stage=kernel) — 커널은 goal을 거부했으나(`omega could not prove the goal`), 반례 확인(replay)이 **하네스 컴파일 실패**로 완결되지 않아 `cvUnresolved` fail-closed로 남았다.
- 요약: `verified=1/2 failed=0 unknown=1 error=0`, `verifiedRatio=0.5` (`state_escape/logs/ax_prove_trajectory.jsonl`의 `extra.summary`).

생성된 replay 하네스 전문 (`state_escape/.axiom/tmp/rust_replay/888e7711ea82d40e/replay_harness.rs`):

```rust
include!("/workspace/Axiom/tests/fixtures/rust/axiom_escape_probe/src/lib.rs");
fn main() {
    println!("AXIOM_REPLAY_BEGIN");
    println!("{}", is_escape_mutant(32, 1));
    println!("AXIOM_REPLAY_END");
}
```

두 번째 인자 `including_control_characters`는 `bool`인데 정수 리터럴 `1`이 전달되었다. 동일 파일을 `/tmp`에서 `rustc --edition 2021`로 수동 컴파일한 관측(도구 로그가 아닌 별도 재현):

```
error[E0308]: mismatched types
  --> replay_harness.rs:4:41
   |
 4 |     println!("{}", is_escape_mutant(32, 1));
   |                    ----------------     ^ expected `bool`, found integer
   |
   |                    arguments to this function are incorrect
   |
note: function defined here
  --> /workspace/Axiom/tests/fixtures/rust/axiom_escape_probe/src/lib.rs:10:8
   |
10 | pub fn is_escape_mutant(ch: u8, including_control_characters: bool) -> bool {
   |        ^^^^^^^^^^^^^^^^         ----------------------------------

error: aborting due to 1 previous error
```

즉 반례 값 자체(`ch=32`, `including_control_characters=true`)는 spec과 일치하지만, **bool 파라미터의 replay 리터럴 인코딩**이 컴파일 불가능한 형태(`1`)로 방출되어 확인 단계가 닫히지 않았다. 이 실행에서 mutant는 `DISPROVED`로 관측되지 않았다.

### 1.5 is_escape 인증서 (escape 런)

- 경로: `vault_escape/39dacdaedb5f19cd96fdcd989256bb00878bf6f5ba3eb25d5e78f136ebdb0f7c.json`
- 파일 sha256: `13b84ca6bf11c2f0a246092d60c034a4a092c4b0e2e85bbe784b499f579b2db4`
- `status`: `certLeanVerified` · `trusted`: `true` · `verificationTier`: `lean-verified` · `reason`: `uap-lean-verified`
- `irHash`: `39dacdaedb5f19cd96fdcd989256bb00878bf6f5ba3eb25d5e78f136ebdb0f7c`
- `propositionHash`: `b782686f5e472094358f8871338b08a258efa36df316ebe80267cb32c2bf251f`
- `leanSourceHash`: `a02f54f9198f8cb6fa0a5622ffc60f407913f0e43b1b34a6061baa747352416b`
- `solverResultDigest`: `sha256:857da2b8a52a961db5c7b5dbea70194371218efc4c5048e3fbd483d794cd7095`
- `toolchainFingerprint`: `93863c86c449631dbd4daa4b413b6ecb95310d15dafdb37c8070bd6cc53ded9f`
- `modulePath`: `/workspace/Axiom/tests/fixtures/rust/axiom_escape_probe/src/lib.rs`
- `sourceHash`: `e9db6aa831634b8bcb8f217ea4e2a39b5889c316abed72c5377f81a2ce2bf0d3` (serde_json과 다름 — 소스 파일이 다름)
- `fingerprint`: `553c7280ca66dfe2d5ca96f858342b12ddf9b5f7d8a42127da1ff40449f012e3` (serde_json과 동일)
- `identityDigest`: `578cd6b3b1a776b9c5e7ecb633ffd99e50f0b4bd2049ccf3aafbca88e3efa461` (serde_json과 다름)

`leanProposition` (verbatim):

```
∀ (ch : Int) (including_control_characters : Int), ((0 ≤ ch) ∧ (ch < 256)) → ((0 ≤ including_control_characters) ∧ (including_control_characters < 2)) → ((is_escape ch including_control_characters) = (if (((ch = 34) ∨ (ch = 92)) ∨ ((including_control_characters = 1) ∧ (ch < 32))) then 1 else 0))
```

관측: 이 fixture 인증서의 `irHash`/`propositionHash`/`leanSourceHash`/`fingerprint`는 serde_json 인증서와 **동일**하다(본문이 동일하고 IR이 본문 기반이기 때문). `modulePath`·`sourceHash`·`identityDigest`는 다르다.

---

## 1A. TASK 1 재실행 — 부정 통제 (수정 후 · escape3 / escape4)

### 1A.1 수정 내용 (이 실험 디렉터리 밖, `src/`)

1. **replay bool 호출 리터럴** — `src/verification/rust_replay_adapter.nim`의 `rustHarnessLiteral`: IR 모델 리터럴 `0`/`1`을 Rust 호출부의 `false`/`true`로 투영한다(v1.4 Bool 0/1 임베드). 수정 전에는 `1`이 그대로 방출되어 `expected bool, found integer`로 컴파일이 실패했다(§1.4).
2. **concrete replay의 Bool↔Int 동등** — `src/verification/counterexample_replay.nim`의 `evalConcreteBinOp(boEq)`: 같은 bv64 값 도메인에서 `ckBool`과 `ckInt`는 int가 정확히 0/1일 때만 동등하다. 그 외 int는 `none`(fail-closed). 수정 전에는 종류가 다르면 무조건 `none`이어서 postcondition `result == ite(prop, 1, 0)`(bool vs int)이 평가 불가로 남았다.

두 수정 모두 `func` + `{.raises: [].}`를 유지하며, 판정 술어를 새로 만들지 않는다.

### 1A.2 실행한 명령 (escape4, 그대로)

```bash
EXP=experiments/serde-json-escape-slice-2026-11
rm -rf "$EXP/state_escape4" "$EXP/vault_escape4"
mkdir -p "$EXP/state_escape4/data"
cp "$EXP/state_escape/data/verification_scope.lock" "$EXP/state_escape4/data/"
AXIOM_STATE_DIR="$PWD/$EXP/state_escape4" \
AXIOM_PROVE_VAULT_DIR="$PWD/$EXP/vault_escape4" \
AXIOM_CHARON_BIN="$(command -v charon)" GITHUB_TOKEN="$(gh auth token)" \
./bin/ax prove --project tests/fixtures/rust/axiom_escape_probe
```

escape3은 같은 명령에서 state/vault 이름만 `state_escape3`/`vault_escape3`이다. 로그: `runs/escape4/{stdout,stderr}.log`, `runs/escape4/exit_code.txt`, `runs/escape3/ax_prove_trajectory.jsonl`.

### 1A.3 종료 코드

```
EXIT=1
```

### 1A.4 관측 요약

- `is_escape` → **verified** → `vault_escape4/39dacdae….json`
- `is_escape_mutant` → **failed (stage=kernel)**, `counterexample CONFIRMED: input.ch=32, input.including_control_characters=1`, `replay.verdict=rvAgree`(반례 재현이 solver 모델과 일치), `replay.exitCode=0`
- 요약: `verified=1/2 failed=1 unknown=0 error=0` (`runs/escape4/stderr.log:17`)
- 주체 무변경: `replay.worktreeStable=true`, `subjectInputsPre == subjectInputsPost`(`d7ccb945…`), `moduleSha256 == moduleSha256AfterRun`(`0da37179…`)

### 1A.5 stderr 발췌 (verbatim, `runs/escape4/stderr.log:12-18`)

```
[AXIOM][rust-lane] charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true
[AXIOM][rust-lane] dep-info /workspace/Axiom/experiments/serde-json-escape-slice-2026-11/state_escape4/.axiom/rust-lane/515aeff29933b27b/charon-target/x86_64-unknown-linux-gnu/debug/libaxiom_escape_probe.d
[AXIOM][rust-lane] ledger transport armed (live); repo=Archright/Axiom
[AXIOM][rust-lane] verified: axiom_escape_probe::is_escape → /workspace/Axiom/experiments/serde-json-escape-slice-2026-11/vault_escape4/39dacdaedb5f19cd96fdcd989256bb00878bf6f5ba3eb25d5e78f136ebdb0f7c.json
[AXIOM][rust-lane] axiom_escape_probe::is_escape_mutant → failed (stage=kernel): spec declined by kernel; counterexample CONFIRMED: input.ch=32, input.including_control_characters=1, propertyViolated=(= result (ite (or (or (= ch #x0000000000000022) (= ch #x000000000000005C)) (and (= including_control_characters #x0000000000000001) (bvslt ch #x0000000000000020))) #x0000000000000001 #x0000000000000000)), replay.verdict=rvAgree, replay.exitCode=0, replay.subjectGitRef=681d130489fa73b2c4744bbedbee32b0d2d92f25, replay.treeMerkle=c61c3d4ff8b7310ebc4d166dcee2cf843ea8f936, replay.moduleSha256=0da37179218cbc07a5cc20f463ecb8b269b0913abbaf48aeae90e2a2ce029493, replay.moduleSha256AfterRun=0da37179218cbc07a5cc20f463ecb8b269b0913abbaf48aeae90e2a2ce029493, replay.worktreeStable=true, replay.subjectInputsPre=d7ccb945c2970d716cb38fd9231453b229df3ef14198d5c068fb912230be83ed, replay.subjectInputsPost=d7ccb945c2970d716cb38fd9231453b229df3ef14198d5c068fb912230be83ed, replay.repoFootprintPre=a626add0cff1a744b9b2cbeb80871b2fe589a0e8630d10872e3f541ce2ee03cf, replay.repoFootprintPost=a626add0cff1a744b9b2cbeb80871b2fe589a0e8630d10872e3f541ce2ee03cf, replay.rustVersion=rustc 1.95.0 (59807616e 2026-04-14), replay.rustcHash=bff349e72704ff70bc08a234a3847338e797065bbedde5e556808bc87b7bf7c6, replay.componentsHash=a13769c18a7a74ea492ab633b644d6c238ae81e536d30d3f168eddb57e86000e, replay.rustChannel=stable-x86_64-unknown-linux-gnu, replay.rustProfile=minimal, replay.rustComponents=cargo-x86_64-unknown-linux-gnu,rust-std-x86_64-unknown-linux-gnu,rustc-x86_64-unknown-linux-gnu, replay.rustDeclaredPin=, replay.hostPlatform=linux-amd64
[AXIOM][rust-lane] done: verified=1/2 failed=1 unknown=0 error=0
[AXIOM][rust-lane] §6c identity sidecar skipped: claim identity unmeasurable: candidate count is 2 — the §6c certified scope is exactly one target
```

### 1A.6 생성된 replay 하네스 (escape4)

`state_escape4/.axiom/tmp/rust_replay/888e7711ea82d40e/replay_harness.rs` (sha256 `75491795824ff9492e9be72bc5ee73587958c46fa79712d55cb865079b1efab6`):

```rust
include!("/workspace/Axiom/tests/fixtures/rust/axiom_escape_probe/src/lib.rs");
fn main() {
    println!("AXIOM_REPLAY_BEGIN");
    println!("{}", is_escape_mutant(32, true));
    println!("AXIOM_REPLAY_END");
}
```

bool 파라미터가 `true`로 방출된다(수정 전 `1`).

### 1A.7 인증서 5필드 + 결정론 (escape3 vs escape4)

| 필드 | escape3 | escape4 | 판정 |
|---|---|---|---|
| `irHash` | `39dacdaedb5f19cd96fdcd989256bb00878bf6f5ba3eb25d5e78f136ebdb0f7c` | 동일 | **IDENTICAL** |
| `propositionHash` | `b782686f5e472094358f8871338b08a258efa36df316ebe80267cb32c2bf251f` | 동일 | **IDENTICAL** |
| `leanSourceHash` | `a02f54f9198f8cb6fa0a5622ffc60f407913f0e43b1b34a6061baa747352416b` | 동일 | **IDENTICAL** |
| `solverResultDigest` | `sha256:857da2b8a52a961db5c7b5dbea70194371218efc4c5048e3fbd483d794cd7095` | 동일 | **IDENTICAL** |
| `toolchainFingerprint` | `93863c86c449631dbd4daa4b413b6ecb95310d15dafdb37c8070bd6cc53ded9f` | 동일 | **IDENTICAL** |

인증서 파일 sha256: escape3 `d3a84348866ed8f6b535674a4499ba5a38f43b182424d1718ab43e72e5235122`, escape4 `a1b37acd9dc66f6823cbd4f7d67a1bcc617317f6e342722d9ec8b46b97490ec3`. 파일 바이트 차이는 §2.6과 같은 이유(런별 저널/서명)다. `replay.repoFootprintPre/Post`는 런마다 다르다(캠페인 state 디렉터리가 런마다 새로 생성됨) — 의미 해시가 아니다.

---

## 2. TASK 2 — serde_json 양성 타깃 콜드 결정론 재실행

### 2.1 준비

```bash
cp experiments/serde-json-escape-slice-2026-11/inputs/Cargo.lock /tmp/axiom-serde-json/Cargo.lock
# sha256 1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4
```

`state_d2`는 새 디렉터리이므로 락이 없어 첫 시도가 실패했다(관측):

```
[ERROR] action_interpreter_cli: [ERROR] [AXIOM] rust lane requires the verification scope lock (fail-closed): not found at '.../state_d2/data/verification_scope.lock' — with --project the lock is resolved from the state root ($AXIOM_STATE_DIR/data/verification_scope.lock)
```

→ `state/data/verification_scope.lock`을 `state_d2/data/verification_scope.lock`으로 복사(동일 sha256 `6002ee05…`)한 뒤 재실행했다. 첫 시도 종료 코드는 `3`이었다.

### 2.2 실행한 명령 (그대로)

```bash
AXIOM_STATE_DIR=$PWD/experiments/serde-json-escape-slice-2026-11/state_d2 \
AXIOM_PROVE_VAULT_DIR=$PWD/experiments/serde-json-escape-slice-2026-11/vault_d2 \
CARGO_NET_OFFLINE=true AXIOM_CHARON_BIN="$(command -v charon)" GITHUB_TOKEN="$(gh auth token)" \
./bin/ax prove --project /tmp/axiom-serde-json --target serde_json::read::is_escape
```

### 2.3 종료 코드

```
EXIT=0
```

### 2.4 stderr 전문 (verbatim)

```
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/ref/heads/axiom/evidence-cas elapsed_ms=363 status=200 OK
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/commits/36563ec3d6c2b595db7a0e6629237a0a373c3620 elapsed_ms=314 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/trees/d21dfbc99113a0e7c0f8e9cad876049fae7dc900?recursive=1 elapsed_ms=346 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/ref/heads/axiom/evidence-cas elapsed_ms=342 status=200 OK
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/commits/e23efa5522283ac7a2fb45a09045249a2ff80f3f elapsed_ms=315 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/trees/452a86eb0bdc553cfeb6f875c77dc169cca8ef75?recursive=1 elapsed_ms=596 outcome=ok
[INFO] ledger_side_ref: phase=ledger-request url=https://api.github.com/repos/Archright/Axiom/git/blobs/f99635a03cb7344798a5514c5d1ce8f0f8c2d12b elapsed_ms=659 outcome=ok
[AXIOM][rust-lane] charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true
[AXIOM][rust-lane] dep-info /workspace/Axiom/experiments/serde-json-escape-slice-2026-11/state_d2/.axiom/rust-lane/1d3566952b5d872e/charon-target/x86_64-unknown-linux-gnu/debug/libserde_json.d
[AXIOM][rust-lane] ledger transport armed (live); repo=Archright/Axiom
[AXIOM][rust-lane] verified: serde_json::read::is_escape → /workspace/Axiom/experiments/serde-json-escape-slice-2026-11/vault_d2/39dacdaedb5f19cd96fdcd989256bb00878bf6f5ba3eb25d5e78f136ebdb0f7c.json
[AXIOM][rust-lane] done: verified=1/1 failed=0 unknown=0 error=0
```

stdout: 비어 있음(0바이트).

### 2.5 주체 무변경 확인

```bash
rm -f /tmp/axiom-serde-json/Cargo.lock
git -C /tmp/axiom-serde-json status --porcelain   # 출력 없음
git -C /tmp/axiom-serde-json rev-parse HEAD       # 8c535a260ce561eaab4111aafc29038eb9f77ff3
```

### 2.6 결정론 비교 (run1 vs d2)

| 필드 | run1 | d2 | 판정 |
|---|---|---|---|
| `irHash` | `39dacdaedb5f19cd96fdcd989256bb00878bf6f5ba3eb25d5e78f136ebdb0f7c` | 동일 | **IDENTICAL** |
| `propositionHash` | `b782686f5e472094358f8871338b08a258efa36df316ebe80267cb32c2bf251f` | 동일 | **IDENTICAL** |
| `leanSourceHash` | `a02f54f9198f8cb6fa0a5622ffc60f407913f0e43b1b34a6061baa747352416b` | 동일 | **IDENTICAL** |
| `solverResultDigest` | `sha256:857da2b8a52a961db5c7b5dbea70194371218efc4c5048e3fbd483d794cd7095` | 동일 | **IDENTICAL** |
| `toolchainFingerprint` | `93863c86c449631dbd4daa4b413b6ecb95310d15dafdb37c8070bd6cc53ded9f` | 동일 | **IDENTICAL** |

추가 관측:

- 보고서 `identityBundleDigest`: run1 `d78f7909d10998f400038ce1232e35c479d28281f90dad9aa4641d4ecf5ef4f5`, d2 동일 → **IDENTICAL**
- `fingerprint`: `553c7280ca66dfe2d5ca96f858342b12ddf9b5f7d8a42127da1ff40449f012e3` 양쪽 동일
- **다른 필드**(런별 저널/서명 결속): `journalRef`, `signature`, `evidenceId`, `identityDigest`, `executionContractDigest`, `kaaDigest`, `trustCommitId`, `attestation.claimDigest`
- §6c identity sidecar(`skreport-identity.json`)는 `binding.payloadSha256`만 다르고(인증서 경로가 vault vs vault_d2) 나머지 identity 필드는 동일

인증서 파일 sha256:

| 런 | 파일 | sha256 |
|---|---|---|
| run1 | `runs/run1/cert_is_escape.json` | `35cdc05e0398948a53738b34327fbcd507469f475e7ef6bb9a98144eed92a678` |
| d2 | `vault_d2/39dacdae….json` | `eb0a5e98765f6a07538e138f6a9859c7c815031cded6aad3272cbfb602db7514` |
| escape | `vault_escape/39dacdae….json` | `13b84ca6bf11c2f0a246092d60c034a4a092c4b0e2e85bbe784b499f579b2db4` |

파일 바이트가 다른 것은 저널 커밋/서명이 런마다 새로 발급되기 때문이며, 검증 의미를 담는 5개 필드는 전부 동일하다.

### 2.7 주체 매니페스트

- `runs/run1/subject_manifest_post.sha256` 파일 sha256: `757a21a1c7a43e08490754930186eb381d0ef3d53fcb0e1f9e2b788265c01465`
- `runs/run1/subject_manifest_with_lock.sha256` 파일 sha256: `1382588e90eabde187c44630b72fc974843230bca14c5383c9018e1c08e6fdd9`
- d2 실행 후 동일 구성으로 재생성한 매니페스트(`runs/d2/subject_manifest_post.sha256`)는 run1의 post 매니페스트와 **diff 결과 공백**(정확히 일치). 재생성 명령:

```bash
cd /tmp/axiom-serde-json && find . -type f -not -path './.git/*' -not -path './target/*' -not -name Cargo.lock \
  | sort | xargs -d '\n' sha256sum | sed 's|  \./|  /tmp/axiom-serde-json/|'
```

- `src/read.rs` blob sha256: `523eec008a92c1be499978ee96bce7a8dc7d6ddff9a63b5ed404c19d01fb953a`
- 주체 소스 fingerprint: `f03e32dc7effa2b39cc692bfbc8639aa0eb7a26207d0aafd4777f9f44c0378a0`

---

## 3. 판정

근거 계약: `docs/spec/bug_verdict_glossary.md` §2.2 정준 발견 모델 판정표.

### 3.1 serde_json `read::is_escape`

- 기계 관측: `certLeanVerified` (Lean 커널 검증 완료, `trusted=true`, `lean-verified`)
- `propositionVerdict` = `NOT_DISPROVED` (주어진 P·D에 대해 커널 증명이 존재)
- `requirementSourceStatus` = `unrecorded` (캠페인 기록 상태)
- 판정표: `NOT_DISPROVED` + (전 상태) → `bugAttribution = UNKNOWN` — **보고하지 않는다**
- 주의(용어집 §2.2 운영 관측 지점): `vdVerified`가 표시 계층에 직렬화되지 않아 표시 계층은 `NOT_DISPROVED`를 관측할 수 없고 fail-closed로 `UNKNOWN`을 투영한다. 어느 경로로도 `BUG_FOUND`가 아니다.

### 3.2 fixture `is_escape_mutant` (부정 통제)

- **의도된** 매핑: `DISPROVED` + `unrecorded` → `BUG_SUSPECTED` (A-essentials 충족 시). 이는 합성 fixture이며 실제 버그가 아니다.
- **관측된** 기계 결과(수정 후, escape3/escape4): `failed` (stage=kernel), `counterexample CONFIRMED` (`ch=32`, `including_control_characters=1`), `replay.verdict=rvAgree` — 반례가 실제 Rust 프로그램 재생으로 확인되었다(§1A).
- 수정 전 1차 실행(§1)은 `unknown` (`cvUnresolved`)이었다 — replay 하네스 컴파일 실패로 반례 확인이 닫히지 않았다. 이 historical 관측은 §1에 그대로 보존한다.
- 따라서 이 fixture의 `propositionVerdict`는 `DISPROVED`이며, 판정표에 따라 `bugAttribution = BUG_SUSPECTED`(합성 fixture, 실제 버그 아님) — **보고 대상 아님**.

### 3.3 공통

- `BUG_FOUND`는 어느 항목에서도 주장하지 않는다 — `requirementSourceStatus = recordedBinding`인 명제가 없고, mutant는 `DISPROVED`로 관측되지 않았다.
- `BUG_SUSPECTED`도 이번 실행에서는 주장하지 않는다(3.2의 관측 결과).

---

## 4. 외부 근거 (RFC 8259)

Context7 MCP로 조회한 RFC Editor 문서에서 반환된 RFC 8259 §7(Strings) 요지(출처: `https://www.rfc-editor.org/rfc/rfc8259.html`, Context7 라이브러리 `/websites/rfc-editor_rfc`, 조회일 2026-11-12):

> "JSON strings are enclosed in quotation marks and support all Unicode characters. Characters such as quotation marks, reverse solidus, and control characters (U+0000 through U+001F) must be escaped."

이는 spec의 `ch == 34`(`"`), `ch == 92`(`\`), `including_control_characters && ch < 32`(U+0000–U+001F)와 일치한다. mutant의 `ch < 0x21`(U+0020, space 포함)은 이 규정보다 한 칸 넓다 — 반례 `ch=32`가 spec과 어긋나는 지점이다.

---

## 5. 미완 / 후속 (관측된 사실만)

1. ~~**replay bool 인코딩 결함**~~ — **해결됨(§1A)**: `rustHarnessLiteral`이 bool 파라미터를 `true`/`false`로 방출하고, `evalConcreteBinOp(boEq)`가 v1.4 Bool 0/1 임베드에서 `ckBool`↔`ckInt(0/1)` 동등을 허용한다. escape3/escape4에서 부정 통제가 `failed`(DISPROVED)로 닫혔다.
2. **fixture 디렉터리 트리 해시**: 캠페인 기록값 `636b16ef52d39848b5cf4968a638d8300c0b8fa6`. 본 실행에서 독립 재계산을 시도했으나 일치하는 구성을 찾지 못했다(임시 git repo `write-tree` = `c0d0079871ecc8766826e22e114590d77b15aaaa`, sha256 매니페스트 = `b1e3588ffcce7e51ecf1f589fce725cfe808946160dbc05619b91bab030704e0`). 따라서 이 값은 **기록값으로만** 인용하며 재현된 값으로 주장하지 않는다. 측정된 파일별 sha256: `Cargo.lock` `3716ef52…`, `Cargo.toml` `55fdf95d…`, `axiom.specs.json` `8270a7bb…`, `src/lib.rs` `0da37179…`.
3. `state_escape` 실행은 후보가 2개라 §6c identity sidecar가 생성되지 않았다(로그에 사유 기록됨).
