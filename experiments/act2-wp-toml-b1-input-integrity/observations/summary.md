# act2-wp-toml-b1-input-integrity — observations summary

## Question

Does `toml_serialization`'s record-decoding path (`Toml_v100.decode(input, T)`,
un-keyed) (1) accept byte-identical duplicate keys with last-wins semantics,
(2) terminate decoding before EOF once all declared fields are filled, and (3)
therefore accept documents containing trailing content that a conforming TOML
parser must reject — while the spec-conforming `TomlValueRef` path rejects
duplicate keys?

## Experiment identity

| Field | Value |
|---|---|
| PROJECT_UNDER_TEST | `nim-toml-serialization` (status-im) |
| PROJECT_REVISION | `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (verified: `git rev-parse HEAD` + empty `status --porcelain`, before and after; see `raw/env.txt`, `raw/post_run_subject_integrity.txt`) |
| AXIOM_REVISION | Axiom3 `cfff53198f6c8b728c89da340809ce822d2583e4` |
| TOOLCHAIN_IDENTITY | Nim Compiler Version 2.2.10 [Linux: amd64], `--mm:orc` |
| EXPERIMENT_ID | `act2-wp-toml-b1-input-integrity` |
| Date | 2026-10-11 (KST) |

## Method

One harness binary (`observations/harness/harness.nim`, copied verbatim into
each case dir). It reads a file and prints `DECODE_RESULT=OK|RAISE` plus field
values (bracket-delimited, control chars escaped) or the exception type/message.
The harness exits 0 whenever the run executes; the decode outcome lives in the
`DECODE_RESULT` line, so process exit codes stay attributable to the harness.

Exact build command (recorded: `raw/build/cmd.txt`):

```
<user-home>/.choosenim/toolchains/nim-2.2.10/bin/nim c --mm:orc --skipUserCfg --skipParentCfg --skipProjCfg --verbosity:0 --hints:off --warnings:off --nimcache:/tmp/toml_b1_repro/nimcache --out:/tmp/toml_b1_repro/bin/harness --path:<workspace>/nim-toml-serialization --path:<user-home>/.nimble/pkgs2/serialization-0.5.4-6a75be38ab6c8a5d49108a54b494ff70d68ea011 --path:<user-home>/.nimble/pkgs2/faststreams-0.5.2-589a9cf07e1d978f460f3da7f8de9b37ac3141af --path:<user-home>/.nimble/pkgs2/stew-0.5.0-db22942939773ab7d5a0f2b2668c237240c67dd6 ./experiments/act2-wp-toml-b1-input-integrity/observations/harness/harness.nim
```

Build exit code 0 (`raw/build/exit_code.txt`); stderr empty.

Decode form under test: `Toml_v100.decode(input, Obj)` — un-keyed (no key
argument), `TomlUnknownFields` NOT set, `Toml_v100` runtimeFlags `{}`.
`Obj = object of RootObj` with fields `a, b, c: string` (declaration order).

## Inputs (sha256, see `inputs/sha256sums.txt`)

| File | sha256 | Content |
|---|---|---|
| `t1_baseline_valid.toml` | `ff1dff85b7150b0574047573ab6e1c5e03543f086cd6f632561c46b31a72928f` | `a = "first"` / `b = "second"` / `c = "third"` |
| `t2_dup_key_then_all_fields.toml` | `852da135e04950656249b9481f235dbd7b73195633a1a049ebca475025c25cf3` | `a = "first"` / `a = "second"` / `b = "third"` / `c = "fourth"` |
| `t3_all_fields_then_malformed.toml` | `bd6414156535308c22a501bb3455343a65c7abc33fb2871800614e02ba8d90eb` | `a = "first"` / `b = "second"` / `c = "third"` / `!!!` |
| `aux_i_dup_key_isolated.toml` | `f8aea9f2b6c04af198308c6f2d87efd3162e919fa391a8cf5acc898497770054` | `a = "first"` / `a = "second"` |
| `aux_ii_unknown_field_isolated.toml` | `c1a01cf13f31325997db3e92b8792f75d49a73c9381e52d3fade6353808bfc93` | `a = "first"` / `b = "second"` / `c = "third"` / `d = "x"` |
| `contrast_t2_bytes_same_as_t2.toml` | `852da135e04950656249b9481f235dbd7b73195633a1a049ebca475025c25cf3` | byte-identical copy of the T2 input |

All files LF-terminated, trailing newline on the last line.

## Results

All observed values below are verbatim from the per-case `stdout.txt` files
under `observations/raw/<case>/`; every process exit code was 0 and every
`stderr.txt` was empty. "Expected" = what the code-level hypothesis predicts
(not what the TOML spec requires; spec expectations are called out in notes).

| Test | Expected (hypothesis) | Observed | Verdict | Note |
|---|---|---|---|---|
| T1 baseline (control) | decode OK; `a=="first"`, `b=="second"`, `c=="third"` | `DECODE_RESULT=OK`; `a=[first]` `b=[second]` `c=[third]`; `a_is_second=false b_is_third=false c_is_empty=false` | CONFIRMED | Control passed; all other rows are interpretable. |
| T2 Obs-1 (duplicate key rejected? applied?) | NO exception; `a=="second"` (dup NOT rejected, WAS applied) | `DECODE_RESULT=OK`; `a=[second]`; `a_is_second=true` | CONFIRMED | Byte-identical duplicate key `a` accepted; second value applied (last-wins overwrite). |
| T2 Obs-2 (early termination?) | `c==""` although input contains `c = "fourth"` | `c=[]`; `c_is_empty=true` (`b=[third]` as predicted) | CONFIRMED | Consistent with `if fieldsDone >= totalFields: break` (`reader.nim` 345-346). Alone this cannot prove the line was never read — see Aux-ii. |
| T3 trailing malformed `!!!` | decode OK; `!!!` ignored (hypothesis) — spec REQUIRES rejection | `DECODE_RESULT=OK`; `a=[first] b=[second] c=[third]`; no exception; exit 0 | CONFIRMED (defect present) | All three fields filled before `!!!` per the design note, so the `!!!` was skipped by the early break, not rejected by the lexer. No trailing-input/EOF validation occurred (`decoder.nim` 46-55 has none). |
| Aux-i duplicate in isolation | decode OK; `a=="second"`, `b==""`, `c==""` | `DECODE_RESULT=OK`; `a=[second] b=[] c=[]` | CONFIRMED | Duplicate accepted even when the loop ends at EOF (no `fieldsDone` break involved) — duplicate-key non-rejection is independent of early termination. |
| Aux-ii unknown field after all fields | decode OK (loop exits before reading `d`); had it reached `d`, unknown-field error | `DECODE_RESULT=OK`; `a=[first] b=[second] c=[third]`; NO exception | CONFIRMED | With `TomlUnknownFields` unset, reaching the `d = "x"` line would call `raiseUnexpectedField` (`reader.nim` 341-343). Success ⇒ the loop exited at the break without examining `d`. This is the discriminating evidence that the loop stops early. |
| Contrast: T2 bytes → `Toml_v100.decode(input, TomlValueRef)` | raises (spec-conforming path rejects dup) | `DECODE_RESULT=RAISE`; `EXCEPTION_TYPE=TomlError`; `EXCEPTION_MSG=[(2, 3) duplicate table key not allowed: 'a']` | CONFIRMED | `lexer.nim` `parseKeyValue`/`raiseDuplicateTableKey` path. |
| Contrast (extra): T2 bytes → `Toml.decode(input, TomlValueRef)` (default v1.1.0 flavor) | not part of hypothesis | `DECODE_RESULT=RAISE`; `TomlError` `(2, 3) duplicate table key not allowed: 'a'` | — | Same rejection on the default flavor; identical message. |

## Verdict

**Hypothesis CONFIRMED on every predicted point.** The two behaviors attribute
separately:

1. **Duplicate-key acceptance (last-wins, no rejection)** — T2 Obs-1 and Aux-i.
2. **Early termination + absent trailing-input/EOF validation** — T3, Aux-ii,
   and T2 Obs-2 (with Aux-ii supplying the "never examined" evidence that
   Obs-2 alone cannot).

Reproducibility: the (now consolidated into `bsec/replay.sh run`) reproduction driver was executed twice; all per-case raw outputs
(stdout/stderr/exit codes) were byte-identical between runs, and input
sha256 values are stable (`RAW_OUTPUTS_IDENTICAL_BETWEEN_RUNS`).

## Non-conclusions

- T2 Obs-2 (`c==""`) by itself does not prove `c = "fourth"` was never read;
  the isolated proof of non-examination is Aux-ii.
- These observations establish decoder behavior for this subject revision,
  type, flavor, and these inputs only; no claim is made about other types or
  code paths.
- No security-impact or severity assessment is made — explicitly out of scope.
- The subject repository was not modified: `git status --porcelain` empty
  before and after all runs (see `raw/env.txt`, `raw/post_run_subject_integrity.txt`).

## Evidence map

- Inputs: `inputs/*.toml`, `inputs/sha256sums.txt`
- Harness source: `observations/harness/harness.nim` (copied into each case dir)
- Build record: `observations/raw/build/{cmd.txt,stdout.txt,stderr.txt,exit_code.txt}`
- Per-case records: `observations/raw/<case>/{cmd.txt,harness.nim,stdout.txt,stderr.txt,exit_code.txt}`
- Environment/identity: `observations/raw/env.txt`
- Subject integrity (post-run): `observations/raw/post_run_subject_integrity.txt`
- Reproducer: `bsec/replay.sh run` (consolidates the former `observations/repro.sh`)
