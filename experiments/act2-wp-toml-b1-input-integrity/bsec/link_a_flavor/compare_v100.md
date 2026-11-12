# B-SEC link experiment (a) — flavor transfer: default `Toml` flavor

**Question**: the committed B-1 results (`../../observations/`, `../../JUDGMENT.md`)
were taken on the `Toml_v100` flavor (un-keyed `Toml_v100.decode(input, Obj)`).
Do the *same* byte-pinned inputs produce the *same* observations under the
**default `Toml` flavor** (v1.1.0 flags), still un-keyed
`Toml.decode(input, Obj)`?

**Result: FLAVOR TRANSFER CONFIRMED — every case byte-identical.**

`FLAVOR_TRANSFER_ASSERT=OK` (`assert_result.txt`), produced by
`diff -u` of per-case observation blocks (`observed/<case>.txt`) against the
same-extracted blocks from the committed Toml_v100 raw outputs
(`../../observations/raw/<case>/stdout.txt`).

## What is compared (byte-identity scope)

Per-case **observation block only**: the `input_len=` line plus every line from
`DECODE_RESULT=` to EOF (decode verdict, bracket-escaped field values,
sentinel booleans / exception type+message). The following are **run metadata,
excluded** from the comparison and recorded instead in `run_meta.txt` /
`raw/<case>/stdout.txt`:

- `harness_mode=` / `decode_call=` lines (they *name* the flavor invoked and
  therefore must differ between the two runs by construction)
- `input_file=` absolute path, timestamps, HEADs, toolchain identity

## Observations (default `Toml` flavor, un-keyed `Toml.decode(input, Obj)`)

Verbatim from `observed/<case>.txt` (process exit 0, stderr empty in all cases;
raw per-case records under `raw/<case>/`):

| Case | Input (pinned bytes, `../../inputs/`) | Observed |
|---|---|---|
| T1 baseline | `t1_baseline_valid.toml` | `DECODE_RESULT=OK`; `a=[first] b=[second] c=[third]` |
| T2 (dup + early break) | `t2_dup_key_then_all_fields.toml` | `DECODE_RESULT=OK`; `a=[second] b=[third] c=[]` (dup **applied** last-wins; `c="fourth"` from the input **not** stored) |
| T3 (trailing `!!!`) | `t3_all_fields_then_malformed.toml` | `DECODE_RESULT=OK`; `a=[first] b=[second] c=[third]`; trailing `!!!` silently ignored — no exception |
| Aux-i (dup isolated) | `aux_i_dup_key_isolated.toml` | `DECODE_RESULT=OK`; `a=[second] b=[] c=[]` — dup accepted with loop ending at EOF |
| Aux-ii (early-break isolated) | `aux_ii_unknown_field_isolated.toml` | `DECODE_RESULT=OK`; no `UnexpectedField` for `d = "x"` — loop exited before examining it |

## Case-by-case equality with the committed Toml_v100 results

| Case | Committed Toml_v100 block | Default-`Toml` block | Verdict |
|---|---|---|---|
| T1 baseline | identical | identical | **IDENTICAL** |
| T2 Obs-1 (`a=="second"`) | identical | identical | **IDENTICAL** |
| T2 Obs-2 (`c==""`) | identical | identical | **IDENTICAL** |
| T3 (`!!!` accepted) | identical | identical | **IDENTICAL** |
| Aux-i (dup accepted) | identical | identical | **IDENTICAL** |
| Aux-ii (`d` never examined) | identical | identical | **IDENTICAL** |

Diff artifacts for each case: `/tmp/bsec_link_a_flavor/diff_<case>.txt`
(empty files = no difference; the recorded run was idempotent — re-created at
record time by `bash run.sh`, a driver deleted in the replay.sh consolidation;
see `../README.md`).

## Interpretation

Both defects **transfer unchanged to the default flavor**:

- **Defect (i) duplicate-key last-wins** — T2 Obs-1 and Aux-i are identical on
  both flavors. Consistent with the code fact that the defects live in the
  record-decoding loop and `findFieldReader` wrap-around, which consult only
  the merged lexer flags (`TomlUnknownFields` etc.), not the flavor identity;
  `Toml_v100` and `Toml` differ only in `flavorRuntimeFlags` merged into the
  lexer.
- **Defect (ii) early termination without trailing-input validation** — T3 and
  Aux-ii identical on both flavors.

No case differs in any line; there is **no** critical finding. This link does
**not** substitute for link (b) (consumer path) — see `../link_b_consumer/`.

## Scope conditions

- Subject: `nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`
  (read-only; `subject_integrity.txt` shows `git status --porcelain` empty).
- Toolchain: Nim 2.2.10, `--mm:orc --skipUserCfg --skipParentCfg --skipProjCfg`,
  built from neutral cwd `/tmp` (see `run_meta.txt`).
- Inputs: byte-pinned, re-verified against `inputs/sha256sums.txt` before the
  run (`run.sh` aborted on mismatch).
- This establishes decoder behavior for this subject revision, this 3-field
  `Obj`, these inputs, and the two flavors' default flags only.

## Artifacts

| Path | Content |
|---|---|
| `probe_flavor_transfer.nim` | probe source (`# nim-check: skip` header) |
| `run.sh` (deleted in the replay.sh consolidation) | idempotent driver: build + 5 cases + byte-compare + integrity check |
| `raw/<case>/{cmd.txt,stdout.txt,stderr.txt,exit_code.txt}` | per-case raw records |
| `raw/build/{cmd.txt,stdout.txt,stderr.txt,exit_code.txt}` | build record |
| `observed/<case>.txt` | per-case observation block (byte-comparison subject) |
| `assert_result.txt` | `OK` = all five cases identical |
| `run_meta.txt` | timestamps/HEADs/toolchain (excluded from byte comparison) |
| `subject_integrity.txt` | post-run subject repo porcelain status |
