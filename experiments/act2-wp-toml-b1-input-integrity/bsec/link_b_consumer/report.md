# B-SEC link experiment (b) — consumer path: nph real `.nph.toml` handling

**Consumer**: `arnetheduck/nph` @ `2cacf6cc28116e4046e0b67a13545af5c4e756bd`
(fresh GitHub clone into `/tmp/bsec_consumer/nph`; source built from a neutral
cwd; binary `/tmp/bsec_consumer/bin/nph`; `--version` → `prerelease-0-g2cacf6c`).

**Result: BOTH B-1 DEFECTS REACH REAL nph BEHAVIOR through
`Toml.loadFile(configFile, NphConfig)` (`src/nph.nim:103`, config default
`.nph.toml` at `src/nph.nim:320`) — and every observable effect they produce is
also produced by a VALID config** (capability-delta boundary; see
`../capdelta/capdelta.md`).

## 0. Which toml_serialization nph actually consumes (version-gap record)

nph's nimble constraint is `toml_serialization >= 0.2.18 & < 0.3.0`
(`nph.nimble`). The build resolved to the nimble-store release package
`toml_serialization-0.2.18-76ae1c2af5dd092849b41750ff29217980dc9ca3`
(`nimbledeps/pkgs2/`). **This is not byte-identical to the B-1 subject
revision** `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` — the release copy is an
older, non-flavored code state (no `decoder.nim`/`desc.nim`/`format.nim`;
`reader.nim` differs, sha256 `a6c33994533a6529eb4b95c5c7a7d48c9c713b0b57de00c3918c71b85042f6e0`
vs subject `9e860006d4a26533beddcd762e21390fb7bafb5cf45ab1547ad96efacff569b5`).

Both defects were therefore **re-verified in the consumed copy itself**:

- **Defect (ii) early break**: `reader.nim:326-327` —
  `if fieldsDone >= totalFields: break` (identical structure to the subject's
  `reader.nim:345-346`).
- **Defect (i) duplicate-key acceptance**: `private/utils.nim:73-87` —
  `findFieldReader` wrap-around re-scan with no seen-set (identical structure
  to the subject's `utils.nim:75-87`).

The consumer-path claim below is thus anchored to the exact bytes nph
consumes, independent of the B-1 subject revision. Behaviorally, Task 1
(`../link_a_flavor/`) additionally showed the default-`Toml` flavor transfers
the defects unchanged on the subject revision itself.

## 1. Consumer call site (static facts, fresh clone @ 2cacf6cc)

| Fact | Location |
|---|---|
| `NphConfig` = `exclude, extendExclude{"extend-exclude"}, includePatterns{"include"}: seq[string]`, `color: Option[bool]` — plain overwrites, no merge/dedup semantics | `src/nph.nim:20-25` |
| `Toml.loadFile(configFile, NphConfig)` — un-keyed, default flavor | `src/nph.nim:103` |
| Parse exception ⇒ stderr warning + defaults; **no other validation** | `src/nph.nim:95-107` |
| Every infile source (dir walk, explicit files, stdin) inserts into `explicitFiles` | `src/nph.nim:327-330, 334, 370` |
| `if file in explicitFiles or matchesFilters(file, compiledPatterns)` — short-circuit ⇒ `matchesFilters` **never evaluated** | `src/nph.nim:428-429` |
| `exclude`/`extend-exclude`/`include` feed only `compiledPatterns`, consumed only by `matchesFilters` | `src/nph.nim:404-424, 132` |
| `config.color` **is** live: overrides the TTY default for `--diff` output | `src/nph.nim:384-385` |

## 2. Method

13 cases (the since-deleted driver `run.sh`, raw evidence `raw/<case>/`): each case is a fresh tree
with a deterministic misformatted Nim fixture (`a.nim`, `b.nims`, `sub/b.nim`,
`ok.nim`, `c.txt`) plus the `.nph.toml` under test; exactly one nph invocation
per case with cwd = case tree. Three-way structure per defect: **defect input /
valid TOML contrast / baseline**. Channels recorded: exit code, stdout bytes
(`--diff` output incl. ANSI), stderr (config-parse warning + `--check`
listing), sha256 manifests before/after (`files_before/after.txt`,
`nimfiles_before/after.txt`).

Note on exit codes: **every** case exits 3 because the fixture contains an
intentionally unparseable `b.nims` ("tabs are not allowed" → `Skipped file,
input cannot be parsed` → nph quits 3). The exit-code channel is therefore
uniform across all three arms and carries no defect signal here; the
discriminating channels are stdout bytes (ANSI/diff), stderr warning
presence/absence, and the rewritten-file set. This uniformity is itself part
of the observation.

## 3. Observations (verbatim, from `raw/<case>/`)

### 3.1 Defect (i) — duplicate keys (B-SEC-01)

| Case | `.nph.toml` (exact lines) | Observed |
|---|---|---|
| C1 defect | `exclude = ["XXXX_never_matches"]` ⏎ `exclude = [".*"]` | **no config warning** (dup accepted); `--check` listing identical to baseline; no "no input file" error |
| C2 valid | `exclude = [".*"]` | identical behavior to C1 |
| C0 baseline | (no config) | identical behavior to C1/C2 |
| C3 defect | `color = true` ⏎ `color = false` | `--diff`: ANSI absent (last-wins `false` applied), stdout byte-identical to C4 |
| C4 valid | `color = false` | ANSI absent |
| C5 defect | `color = false` ⏎ `color = true` | `--diff`: ANSI present (last-wins `true` applied), stdout byte-identical to C6 |
| C6 valid | `color = true` | ANSI present |

Key numbers: `stdout(c1)==stdout(c2)==stdout(c0)` byte-identical (all 0 bytes —
the `--check` listing goes to stderr); path-normalized
`stderr_norm(c1)==stderr_norm(c2)==stderr_norm(c0)` identical (`would reformat
./a.nim` + `would reformat ./sub/b.nim` in all three). `exclude = [".*"]`
would exclude every file if the filter were evaluated (→ `[Error] no input
file.`, exit 3 with no listing); it had **zero** effect.

`color` is the **only** field whose defect application is externally visible,
and it is externally visible in exactly the last-wins direction
(C3≡C4, C5≡C6, byte-identical stdout).

### 3.2 Defect (ii) — all fields filled + trailing spec-invalid input (B-SEC-02)

| Case | `.nph.toml` | Observed |
|---|---|---|
| C7 defect | 4 distinct fields, then `!!!`, `[[attacker_table]]`, `some = "garbage"` | **no config warning** — trailing spec-invalid input silently skipped; `--diff` output byte-identical to C8 (ANSI present) |
| C8 valid | same 4 fields, document ends after `color = true` | byte-identical stdout/stderr to C7 |
| C10b boundary | 3 distinct fields (`exclude` duplicated), then `!!!` | `stderr: Warning: Failed to parse config file: .nph.toml ((4, 1) illegal character "!")` — **rejected** |
| C9 control | `this is [[ not toml` | `stderr: Warning: Failed to parse config file: .nph.toml ((1, 6) expected "=")` — warning path exists and works |

C10b is the **discriminator**: trailing input is validated **iff** any field
remains unfilled. Acceptance in C7 therefore proves the early break fired
(`fieldsDone >= totalFields`) — the same mechanism as B-1 T3/Aux-ii.

### 3.3 In-place formatting — which files get touched (defect (i)+(ii) combined)

C10 (dup `exclude` + all 4 distinct fields + trailing `!!!`) vs C11 (valid:
single `exclude`, `color`) vs C12 (no config): **all three arms exit with
IDENTICAL Nim-tree manifests** (`nimfiles_after.txt`) — `a.nim` and
`sub/b.nim` rewritten in place to identical formatted bytes
(`03b6a60a…→bda43b82…`, `dd847f5a…→b02b19de…`); `ok.nim`, `b.nims`, `c.txt`
and `.nph.toml` itself untouched. C10's config was accepted without warning
(stderr contains only the fixture `b.nims` errors). The attacker-chosen
defect config changes **nothing** relative to a valid config or no config.

## 4. Consumer-path link verdict

1. **Defect (i) reaches nph**: byte-identical duplicate keys are accepted by
   nph's real config path without warning and applied last-wins (C3 vs C5
   show both directions of the last value winning on the one live field; C1
   shows silent acceptance on the dead fields). **Confirmed.**
2. **Defect (ii) reaches nph**: trailing spec-invalid input after a full field
   set is silently skipped (C7), with the C10b boundary proving the early
   break is the mechanism. **Confirmed.**
3. **But every defect-reachable configuration state is equally reachable by a
   valid config** (C1≡C2≡C0, C3≡C4, C5≡C6, C7≡C8, C10≡C11≡C12) — this is the
   capability-delta result recorded in `../capdelta/`.

## 5. Artifacts

| Path | Content |
|---|---|
| `run.sh` (deleted in the replay.sh consolidation) | idempotent driver (13 cases + equality assertions) |
| `raw/<case>/{cmd.txt,config.nph.toml,stdout.txt,stdout.catv.txt,stderr.txt,exit_code.txt,files_before.txt,files_after.txt,nimfiles_before.txt,nimfiles_after.txt}` | per-case records |
| `run_meta.txt` | rev/identity/timestamp (run metadata) |
| `../link_a_flavor/` | flavor-transfer link (a) |
| `/tmp/bsec_consumer/` | clone, build, case trees (binaries/workdirs in /tmp only) |
