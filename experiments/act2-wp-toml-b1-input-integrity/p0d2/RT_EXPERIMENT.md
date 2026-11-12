# P0-D2-RT — roundtrip-identity refutation (D2: encoder ≠ decoder, TOML 1.1 `\xHH`)

Experiment: `act2-wp-toml-b1-input-integrity/p0d2` (rt slice) · Date: 2026-10-12
Proof path: `replay_rt.sh` replay artifacts conforming to the product contract output schema
(`docs/spec/productization_contract.md`) · Raw runs: `raw_rt/run1`, `raw_rt/run2` · Sums: `raw_rt.SHA256SUMS`

Sibling slice: `experiment.md` in this directory covers the **consumer-visible contrast**
(nimbus-eth1 decode form, vendor pin `7352976`). This slice is the **library-level
roundtrip-identity refutation** at the verification subject itself.

## Verification subject (ONE exact commit)

| item | value |
|---|---|
| repo | `<workspace>/nim-toml-serialization` (read-only clone) |
| subject | **`4aa8e2223649fc0837c490a4acfca7b8b1e756f9`** (HEAD; `replay_rt.sh` fails closed if HEAD differs or `git status --porcelain` is non-empty) |
| provenance note (NOT the subject) | introduction range `7352976..4aa8e22`; enabled by default since `62dcb2c` (#115, "Enable TOML v1.1.0"); not applicable to v0.2.18 (`b5b387e6`) where `\x` is rejected (`lexer.nim:391-392` there) |
| materialization | `git -C <clone> archive <subject> \| tar -x` into `/tmp/p0d2_rt_env` — zero footprint, clone never mutated |
| cross-slice consistency | the exported `toml_serialization/lexer.nim` sha256 `19d69eed84f74c51…` is byte-identical to the file recorded in the sibling slice's `probes/deps.SHA256SUMS` |

## The 3-way experiment (exact bytes)

Probe: `probes/p0d2_rt_probe.nim` — per case it (A) decodes the authored fixture,
(B) encodes the intended per-spec value, (C) decodes the encoder's own output
(roundtrip), and (D) prints an independent UTF-8 oracle (`std/unicode`,
not subject code). Call form cited from the subject's own tests:
`Toml.decode(text, Target)` (`tests/test_decoder.nim:156`) and `Toml.encode(value)`
(`tests/test_encoder.nim:190`); default options, no overrides.

| case | authored input | decoder on input (hex) | encoder on intent (decisive bytes) | decode∘encode vs intent |
|---|---|---|---|---|
| 1 baseline | `value = "hello world"` | `68 65 6C 6C 6F 20 77 6F 72 6C 64` (well-formed) | no escapes | **identity holds: true** |
| 2 defect | `value = "caf\xE9"` + `ctrl = "\x80"` | `63 61 66 E9` + `80` — **raw bytes, INVALID UTF-8** (≠ intent `63 61 66 C3 A9` / `C2 80`) | emits `\xE9` = `5C 78 45 39` and `\x80` = `5C 78 38 30` (`writer.nim:131-163`, `TomlHexEscape` active via `writer.nim:30-40`) | **identity violated: false** (`63 61 66 E9` ≠ `63 61 66 C3 A9`) |
| 3 unicode | `value = "caf\u00E9"` + `ctrl = "\u0080"` | `63 61 66 C3 A9` + `C2 80` — **correct UTF-8** via `scanUnicode` (`lexer.nim:399-415`) | emits the SAME `\xE9` / `\x80` text as case 2 | **identity violated: false** — the encoder re-encodes the spec-valid values to `\xHH`, whose decode is the raw byte |

Reading: the raw-byte decode of `\xE9` (`…E9`) differs from U+00E9's UTF-8
(`…C3 A9`), while the `\u00E9` path decodes correctly. The decoder's correct
path exists in the same lexer; the default encoder never produces it for
U+0080..U+00FF. Encoder ≠ decoder ⇒ `roundtrip.identity` violated.

## Contract output (four separated items — actual values)

1. **관측 결과 (observation)** — D2 reproduced at `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`:
   encoder output for `"caf"+U+00E9` is `value = "caf\xE9"` (bytes
   `76 61 6C 75 65 20 3D 20 22 63 61 66 5C 78 45 39 22 0A`), and decoding the
   `\xE9` form yields the raw byte `63 61 66 E9` (invalid UTF-8), not U+00E9's
   UTF-8 `63 61 66 C3 A9`. `decode(encode(intent)) ≠ intent`
   (`roundtrip_identity_holds: false` in `raw_rt/run1/defect.out`).
2. **판정 (verdict)** — `UNKNOWN`.
3. **사유 (reason)** — expected-vs-observed conflict under
   `key=roundtrip.identity ∧ same scope ∧ same subject`: the contract expects
   `decode(encode(intent)) == intent` (TOML v1.1.0 defines `\xHH` as U+00HH;
   strings are sequences of Unicode characters), the pinned build observably
   yields ≠ with the raw byte in place of `C3 A9`. Per
   `docs/spec/productization_contract.md:168` (same key ∧ same scope ∧ same
   subject ∧ conflicting value → UNKNOWN) the verdict function returns UNKNOWN.
   This is the contract's verdict FOR an observed contradiction — NOT
   "insufficient evidence": the contradiction is fully observed, byte-exactly,
   and reproducibly.
4. **증거 (evidence)** — `raw_rt/run1/rt_evidence.json` §`contractOutput.증거`
   (inputs with sha256 + full byte hex, decisive bytes, reproduction conditions),
   backed by `raw_rt/run{1,2}/{baseline,defect,unicode}.{out,err,exit}`,
   `build.log`, `probes/p0d2_rt_deps.SHA256SUMS`, `inputs/rt_sha256sums.txt`,
   and `raw_rt.SHA256SUMS`.

위 네 항목(관측/판정/사유/증거)과 별개로, 산출물의 **상태 분류** 네 항목
(관측/판정/상태·tier 쌍/범위 제한)은 아래 「분류 라벨 — 제한된 실험 증거」
섹션과 `rt_evidence.json` §`classification`이 운반한다 — 두 4-튜플을
혼동하지 않는다.

## Contract 3-field bindings (real data)

| field | value |
|---|---|
| `key` | `roundtrip.identity` |
| `scope` | `toml-flavor=Toml;version=1.1.0;runtimeFlags=Toml_v110_Flags{TomlInlineTableNewline, TomlInlineTableTrailingComma, TomlHexEscape, TomlHourMinute, TomlStrictComma};options=default(init, no overrides);callForm=Toml.decode(text,T)/Toml.encode(value)` — flavor name/flags read from the pinned code (`format.nim:24-38`); both `TomlReader.init` (`reader.nim:53-66`) and `TomlWriter.init` (`writer.nim:30-40`) union `flags + flavorRuntimeFlags(Flavor)`, so callers cannot subtract `TomlHexEscape` |
| `subject` | `nim-toml-serialization@4aa8e2223649fc0837c490a4acfca7b8b1e756f9/probe=p0d2_rt_probe/input=rt_defect.toml:05e0d797408507abaee83e427d67bd2e2d68f197744fe06944e310905926c7ad` (baseline/unicode rows bind their own input hashes; the conflicting observation pair shares key∧scope∧subject) |

## Assurance tier (P0-2)

**`vtNone` (label `none`)** — from the existing `VerificationTier` enum
(`src/core/types/verification_tier.nim`). Grounding: `tierFromEvidence(
CertificateEvidence(z3Passed=false, leanVerified=false)) = vtNone` per
`verification_tier.nim:139-141` → `tierFromResults` truth table (`:32-40`),
DECISION-0630 (tier is a PURE function of stored evidence; status may never
exceed evidence). This refutation has no Z3 unsat and no Lean kernel artifact;
its evidentiary procedure is a deterministic local replay (commands + exit
codes + `outputDigest=SHA-256`, pinned commit + toolchain). A concrete
counterexample refutes; it does not verify — no solver tier is claimed.

## 분류 라벨 — 제한된 실험 증거 (limited experimental evidence)

이 슬라이스의 모든 출력(`RT_EXPERIMENT.md`, `raw_rt/run{1,2}/rt_evidence.json`
§`classification`, `replay_rt.sh`)은 아래 네 항목을 분리해서 운반한다:

1. **관측**: 고정 입력(`inputs/rt_baseline.toml`·`rt_defect.toml`·
   `rt_unicode.toml`, sha256 고정)에서 문자열 왕복 불변식
   (`roundtrip.identity`) 위반이 재현됨 — defect 입력에서
   `decode(encode(intent)) ≠ intent` (raw byte `E9` ≠ UTF-8 `C3 A9`),
   `raw_rt/run{1,2}`에 바이트 수준 재현.
2. **판정**: 제품 계약의 모순 규칙(`docs/spec/productization_contract.md:168`
   — same key ∧ same scope ∧ same subject ∧ 상충 value → UNKNOWN)에 따른
   `UNKNOWN`.
3. **상태·tier 쌍**: `certRed + vtNone`(label `none`)을 계약 어휘에 따라 투영한
   **제한적 실험 결과**. 계약 §7a에서 Verdict의 기존 표현이 정확히 이 쌍이다
   (`productization_contract.md:308`). 어휘 근거: `certRed`는 SAT/반례 전용
   (`src/core/types/verification_tier.nim:98`), solver 증거 없는 반례의 tier는
   `tierFromResults(false,false) = vtNone`
   (`verification_tier.nim:32-40,139-141`; DECISION-0630 — tier는 저장 증거의
   순수 함수), status·verificationTier는 저장 증거에서 투영된다
   (`src/verification/cert_writer.nim:303,362`).
4. **범위 제한**: `deriveClaim`을 통한 claim authority
   (`src/core/trusted/claim_authority.nim:17-20` — claim은 캡처된 solver
   증거로부터만 파생; certificate/status는 절대 `deriveClaim`의 입력이 아님),
   `identityDigest`, `trustCommitId` 결속(`productization_contract.md:304-305`,
   §7a)을 갖춘 **정식 계약 적합 인서트가 아님**. D2의 반례는 `solverSat` →
   `derivePipelineClaim` 경로가 아니라 Nim 왕복 probe의 고정 입력 관측에서
   왔다. 따라서 3의 쌍은 계약 어휘의 투영일 뿐이며, 이 슬라이스의 어떤
   산출물도 계약이 발행하는 형식 인서트로 표시·소비되어서는 안 된다.

`tierCounts` 필드는 의도적으로 존재하지 않는다(absent) —
§7b(`productization_contract.md:312-317`, `sum(tierCounts) == classifiedNodes`
다층 분류 집계)는 단일 모순 artifact에 적용되지 않는다.

## Pinned environment (P0-3)

| item | value |
|---|---|
| target | `status-im/nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (nimble declares 0.2.18; `Toml` flavor = TOML v1.1.0 per `format.nim:37-38` + `README.md:64-69,78-80`) |
| Nim | 2.2.10 [Linux: amd64], compiled 2026-04-24, git hash `bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef` (`$HOME/.choosenim/toolchains/nim-2.2.10/bin/nim`) |
| dependencies | pinned by commit, file-verified every replay by `probes/p0d2_rt_deps.SHA256SUMS` (164 files): `nim-serialization@4092500cea76154576539371709ae801afbd2a9d`, `nim-faststreams@50889cd16ec8771106cdd0eeea460039e8571e06`, `nim-stew@83eb1157963b7f49351dbdd858355fa990bbe23c`, `nim-results@df8113dda4c2d74d460a8fa98252b0b771bf1f27` (arnetheduck). Subject has no `nimble.lock` — pins are committed here. Canonicalizer extra dep: nimble `checksums-0.2.2-6357ab195ec23e0e0a54d4d8b5e0212456bf899e` |
| build flags | `nim c --warnings:off --hints:off --mm:orc --skipUserCfg --skipParentCfg --skipProjCfg --nimcache:<env>/build/nimcache_rt --path:<5 pinned dep dirs> --out:<env>/bin/p0d2_rt_probe <env>/probe.nim` (neutral cwd `/tmp/p0d2_rt_env`; binaries in `/tmp` only) |
| TOML flavor / call form | see `scope` above |
| platform | Linux x86_64, `ulimit -s` 8192 |

## Determinism + replay (two-run comparison) — P0-4 correction 적용

Command (per run): `RUN_DIR="$PWD/raw_rt/runN" P0D2_RT_CLEAN=1 bash replay_rt.sh`
from `p0d2/` (cold: env wiped, subject re-exported, deps re-fetched, binaries
rebuilt). The contract requires **projection-hash equality**
(`canonicalProjectionHashEqual`, `docs/spec/productization_contract.md:63` —
"동일 입력+환경"; §6 `:194` — "semantic equality 정의 — raw artifact byte
equality 아님"), NOT full-envelope byte equality. `replay_rt.sh` step 8
enforces exactly this split against the sibling run dir (auto-detected, or
`P0D2_COMPARE_DIR`).

**Byte-identical across two runs — these paths ONLY**:

- `raw_rt/runN/{baseline,defect,unicode}.{out,err,exit}` (9 files)
- `raw_rt/runN/build.log`
- `raw_rt/runN/rt_canonical.json`
- `raw_rt/runN/rt_canonical.sha256`

**Allowed to differ (contract volatile keys only)**:

- `rt_evidence.json` — `collection.generatedAt`와 `runtimeMeta.runId` 단 두
  키. 이것은 `src/core/utils/canonical_projection.nim:18-31`의 유일한 정본
  exclusion list에 있는 키들이며(본 슬라이스는 두 번째 목록을 만들지 않는다),
  `runtimeMeta` 봉투 자체도 `canonical_projection.nim:45-46`에서 통째로
  제외된다. 두 값은 실행 간 실제로 변한다(아래 결과) — 제거가 시연된다.
- `canonicalProjectionHash`는 그 차이에도 **동일해야 하고, 동일하다**.

**Caveats (기록됨 — 동일시하지 않음)**:

- (a) `rt_canonical.json`은 std/json `$`(삽입 순서) 렌더링이고, 해시는 정렬
  직렬화기(`canonical_projection.nim:57-78`) preimage의 SHA-256이다 — 두
  직렬화를 동일시하지 않는다(`rt_canonical.json`의 바이트 동일성은 렌더링의
  결정성일 뿐, 해시 preimage가 아니다).
- (b) 기계 간 바이트 동일성은 주장하지 않는다 — `environment.platform`,
  `stackLimitKB`가 해시에 들어간다(계약 `:63` "동일 입력+**환경**"). 본
  비교는 동일 기계상의 두 실행이다.

Result (2026-10-12 re-run, run1 vs run2, step-8 PASS + 독립 `cmp`/`diff` 재확인):

- `canonicalProjectionHash` (Axiom3 SSOT `core/utils/canonical_projection.nim::canonicalProjectionHash`,
  the single implementation, run via `probes/p0d2_canon.nim`): both runs
  `18bfdc76f9b4bfdab1d0da2fa3fb1f2b7a3f56200bc15a7c79196c588d22192c`.
- Pinned 12 paths: `cmp` all byte-identical (`raw_rt/run1` vs `run2`).
- `raw_rt/run1/rt_evidence.json` vs `run2/`: differs ONLY in
  `collection.generatedAt` (01:16:05Z vs 01:16:19Z) and `runtimeMeta.runId`
  (`2c676d23-…` vs `523d23d4-…`) — demonstrably stripped.
- `at`/timestamps are fixed at recording time; replay never regenerates them.
- Re-execution: `rt_evidence.json` §`commands` carries each command with its
  exit code and SHA-256 `outputDigest`; `canonicalization` records the SSOT
  transform (deliberately not a `commands[]` row — its output digest is a
  function of the evidence file itself).
- Sums snapshot: `raw_rt.SHA256SUMS` pins the `run1` file set (13 files).

## Target-repo-unchanged check

`git -C …/nim-toml-serialization rev-parse HEAD` = `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`
and `git status --porcelain` = empty, checked BEFORE and AFTER both replays;
`replay_rt.sh` re-asserts both on every invocation (fail-closed, step 0). The
subject was only read via `git archive`.

## CLI wiring gap (reported, not fixed)

`ax prove` (`src/cli/axiom_engine.nim` ~:3089 `proveConfig`, `:248`
`buildProofTask`, verb token at `src/cli/action_plan_cli.nim:171`) builds a
`ProofTask{limit, vaultDir, target}` consumed by the Nim symbol-graph → IR →
Z3/Lean pipeline over Axiom's own subject tree. There is no existing target
form for "run this pinned external subject binary against this input and
compare bytes" — the D2 refutation is an external-subject runtime observation
with recorded replay evidence, not a Nim-function proof obligation. Expressing
it through the existing surface would require a new target kind (external
subject + recorded-replay evidence ingestion) — a plan-needed product decision
under §0.12, intentionally NOT made here. The proof path is therefore the
`p0d2` replay artifacts (this document + `replay_rt.sh` + `raw_rt/`)
conforming to the contract output schema; no new CLI surface was added.

## Scope discipline (non-conclusions)

- Refutation only: no severity/exploitability assessment, no fix proposed or applied.
- The verifier-of-verifier chain (§0.9b) is not invoked here — this slice
  produces a concrete counterexample against a pinned build; it claims no
  verification that would itself need re-verification (tier `vtNone` says so).
- v0.2.18 (`b5b387e6`) behavior is cited from the established analysis, not re-derived.
- Only `RtConf{value, ctrl}` string fields were exercised; other TOML types untouched.
